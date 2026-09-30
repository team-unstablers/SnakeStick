// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NTFS3G
import SlopDisk

/// Writes a Windows installer for `request.isoPath` to `request.target`: the eight steps of
/// ``Phase`` in order, then cleanup.
///
/// - A `.device` target needs root and must be an eligible disk (P8) at least
///   ``ISOInfo/requiredBytes`` large (C10); both are checked again here.
/// - An `.image` target is created sparse, attached with `hdiutil` and detached at the end.
/// - Cancelling the task stops the pipeline at the next check (between steps, and during the
///   copy and the verification). After cleanup a `.failed` event of kind `.cancelled` is sent and
///   `CancellationError` is thrown.
/// - On failure, after cleanup, a `.failed` event is sent and the ``InstallerError`` is thrown.
///   The target is left as it is (P16).
///
/// The work runs on its own thread; `events` is called from that thread.
public func runInstaller(
    _ request: InstallerRequest,
    events: @escaping @Sendable (InstallerEvent) -> Void
) async throws -> InstallerResult {
    let cancellation = CancellationFlag()
    return try await withTaskCancellationHandler {
        try await Blocking.run {
            try Pipeline(request: request, events: events, cancellation: cancellation).run()
        }
    } onCancel: {
        cancellation.cancel()
    }
}

final class Pipeline {
    let request: InstallerRequest
    let events: @Sendable (InstallerEvent) -> Void
    let cancellation: CancellationFlag
    let reporter: ProgressReporter
    let tools: DiskTools
    let startTime = Date()

    private(set) var phase: Phase = .openISO
    private var targetModified = false
    /// The file being copied or verified, for error messages.
    private var currentPath: String?

    // Resources released by cleanup(), in reverse order of acquisition (§11).
    private var work: WorkDirectory?
    private var iso: ISOSession?
    private var imageDevice: String?
    private var mountGuard: MountGuard?
    private var bootMountPoint: URL?

    init(request: InstallerRequest, events: @escaping @Sendable (InstallerEvent) -> Void, cancellation: CancellationFlag) {
        self.request = request
        self.events = events
        self.cancellation = cancellation
        reporter = ProgressReporter(verify: request.options.verifyAfterWrite, send: events)
        tools = DiskTools(log: { events(.log($0)) })
    }

    func log(_ message: String) {
        events(.log(message))
    }

    func run() throws -> InstallerResult {
        let result: InstallerResult
        do {
            result = try execute()
        } catch {
            let cancelled = error is CancellationError
            let failure = cancelled
                ? InstallerError(phase: phase, kind: .cancelled, message: "Cancelled.", targetModified: targetModified)
                : Self.installerError(from: error, phase: phase, targetModified: targetModified, currentPath: currentPath)
            log(cancelled ? "cancelled during step \(phase.rawValue)/8" : "error: \(failure)")
            cleanup()
            events(.failed(failure))
            if cancelled {
                throw CancellationError()
            }
            throw failure
        }
        cleanup()
        events(.finished(result))
        return result
    }

    // MARK: - Steps

    private func execute() throws -> InstallerResult {
        let options = request.options
        try checkRequestBeforeStarting()
        try cancellation.check()
        let work = try WorkDirectory(log: { [events] in events(.log($0)) })
        self.work = work
        log("work directory: \(work.url.path)")

        // 1. Open the ISO.
        reporter.start(.openISO)
        let iso = try ISOSession(path: request.isoPath, workDirectory: work, tools: tools)
        self.iso = iso
        let info = iso.info
        let label = VolumeLabel.resolve(requested: options.volumeLabel, isoLabel: info.volumeLabel)
        log("ISO: \(info.windowsVersion), \(info.architecture), label \"\(info.volumeLabel)\", \(info.requiredBytes) bytes needed; volume label \"\(label)\"")
        var replacements: CA2023Replacements?
        if options.useCA2023Bootloaders {
            guard info.supportsCA2023 else {
                throw InstallerError(
                    phase: .openISO, kind: .invalidISO,
                    message: "The Windows UEFI CA 2023 boot loaders need Windows 11 25H2 (build \(ISOInfo.ca2023MinimumBuild)) or later; this ISO is build \(info.build)."
                )
            }
            replacements = try CA2023Replacements.prepare(
                bootWIM: iso.bootWIM, isoRoot: iso.mountPoint, architecture: info.architecture, into: work.subdirectory("wim")
            )
        }
        try cancellation.check()

        // 2. Prepare the target.
        begin(.prepareTarget)
        let target = try prepareTarget(requiredBytes: info.requiredBytes)
        // The guard goes up before the unmount, so that nothing can be mounted in between.
        let mountGuard = try MountGuard(wholeDisk: target.wholeBSD, log: { [events] in events(.log($0)) })
        self.mountGuard = mountGuard
        let unmount = try tools.subprocess.run("/usr/sbin/diskutil", ["unmountDisk", "force", target.buffered])
        guard unmount.status == 0 else {
            throw InstallerError(
                phase: .prepareTarget, kind: .io,
                message: "The volumes on \(target.wholeBSD) could not be unmounted: \(unmount.stderrText)", path: target.buffered
            )
        }
        try cancellation.check()

        // 3. Write the partition table.
        begin(.writePartitionTable)
        let table = try Partitioning.writePartitionTable(devicePath: target.raw, label: label, willCommit: { self.targetModified = true })
        log("GPT: \(table.sectorCount) sectors of \(table.sectorSize) bytes; NTFS \(table.ntfs.begin)-\(table.ntfs.end), UEFI:NTFS \(table.fat.begin)-\(table.fat.end)")
        try cancellation.check()

        // 4. Check the slices against the table before anything is formatted (C17).
        begin(.checkPartitions)
        let ntfsSlice = target.slice(forEntry: table.ntfs.index)
        let fatSlice = target.slice(forEntry: table.fat.index)
        try Partitioning.checkSlice(ntfsSlice, of: target, expected: table.ntfs, cancellation: cancellation)
        try Partitioning.checkSlice(fatSlice, of: target, expected: table.fat, cancellation: cancellation)
        try cancellation.check()

        // 5. Format the NTFS partition.
        //
        // Workaround (decision 14 fallback, chosen by the user on 2026-09-30): NTFS3G gets the
        // buffered slice /dev/diskNs1, not the raw /dev/rdiskNs1 that C8 intends. libntfs-3g's
        // unix_io issues reads and writes that are not multiples of the sector size, and raw disk
        // nodes reject those with EINVAL (U11: mkntfs fails with "Error writing ... Invalid
        // argument" on both hdiutil devices and a real USB stick). Through the buffer cache the
        // same I/O works; libntfs-3g flushes with F_FULLFSYNC when it closes the device. The price
        // is throughput: about 57% of a raw sequential write on the stick that was measured.
        begin(.formatNTFS)
        try NTFSVolume.format(path: ntfsSlice.buffered, options: NTFSFormatOptions(
            label: label,
            clusterSize: NTFSLayout.clusterSize,
            sectorSize: table.sectorSize,
            partitionStartSector: table.ntfs.begin
        ))
        try cancellation.check()

        // 6. Copy the files.
        begin(.copyFiles, detail: "Checking the files on the ISO")
        let volume = try NTFSVolume(path: ntfsSlice.buffered, mode: .readWrite)
        do {
            let summary = try volume.copyTree(from: iso.mountPoint) { [self] progress in
                try cancellation.check()
                currentPath = progress.currentPath
                reporter.copied(progress.completedBytes, of: progress.totalBytes, path: progress.currentPath)
            }
            log("copied \(summary.files) files and \(summary.directories) directories, \(summary.bytes) bytes")
            currentPath = nil
            try replacements?.apply(to: volume, log: log)
        } catch {
            // The volume stays open after copyTree throws; close it so that the device can be
            // detached (C27, C19).
            try? volume.close()
            throw error
        }
        try volume.close()
        try cancellation.check()

        // 7. The UEFI:NTFS boot partition.
        begin(.prepareBootPartition)
        let efiMountPoint = try work.subdirectory("efi")
        bootMountPoint = efiMountPoint
        let boot = BootPartition(slice: fatSlice, mountPoint: efiMountPoint, tools: tools, mountGuard: mountGuard, log: log)
        try boot.create()
        try cancellation.check()

        // 8. Verify.
        begin(.verify)
        try Verification.checkPartitionTable(device: target.raw, expected: table)
        try boot.verify()
        if options.verifyAfterWrite {
            let check = try NTFSVolume(path: ntfsSlice.buffered, mode: .readOnly)
            defer { try? check.close() }
            try Verification.compareTree(
                volume: check, isoRoot: iso.mountPoint, overrides: replacements?.expectedContents ?? [:], cancellation: cancellation
            ) { done, total, path in
                currentPath = path
                reporter.verified(done, of: total, path: path)
            }
            currentPath = nil
        }
        reporter.verified(1, of: 1, path: "")
        return InstallerResult(elapsed: Date().timeIntervalSince(startTime), verified: options.verifyAfterWrite)
    }

    private func begin(_ phase: Phase, detail: String? = nil) {
        self.phase = phase
        reporter.start(phase, detail: detail)
    }

    /// What can be rejected before anything is attached or written.
    private func checkRequestBeforeStarting() throws {
        switch request.target {
        case .device(let bsdName):
            guard getuid() == 0 else {
                throw InstallerError(phase: .prepareTarget, kind: .rootRequired, message: "Writing to a disk needs root privileges (root required).")
            }
            guard DiskCandidate.isWholeDiskName(bsdName) else {
                throw InstallerError(phase: .prepareTarget, kind: .usage, message: "\(bsdName) is not a whole-disk name such as disk4.")
            }
        case .image(let path, _):
            if FileManager.default.fileExists(atPath: path) {
                throw InstallerError(phase: .prepareTarget, kind: .targetExists, message: "\(path) already exists.", path: path, errno: EEXIST)
            }
        }
        if let label = request.options.volumeLabel, !VolumeLabel.isValid(label) {
            throw InstallerError(
                phase: .openISO, kind: .usage,
                message: "\"\(label)\" cannot be an NTFS volume label: at most 32 characters, none of \"*/:<>?\\| or control characters, and no space or dot at the end."
            )
        }
    }

    /// Step 2 (§4): checks a disk again (C21, C10) or creates and attaches an image.
    private func prepareTarget(requiredBytes: UInt64) throws -> TargetDevice {
        switch request.target {
        case .device(let bsdName):
            let disks = try listWholeDisks()
            guard let disk = disks.first(where: { $0.bsdName == bsdName }) else {
                throw InstallerError(phase: .prepareTarget, kind: .targetIneligible, message: "\(bsdName) was not found.", path: "/dev/\(bsdName)")
            }
            guard disk.isEligible else {
                throw InstallerError(
                    phase: .prepareTarget, kind: .targetIneligible,
                    message: "\(bsdName) cannot be written: \(disk.ineligibleReason ?? "not eligible").", path: "/dev/\(bsdName)"
                )
            }
            guard disk.isLargeEnough(for: requiredBytes) else {
                throw InstallerError(
                    phase: .prepareTarget, kind: .insufficientSpace,
                    message: "\(bsdName) holds \(disk.sizeBytes) bytes; this ISO needs \(requiredBytes).", path: "/dev/\(bsdName)"
                )
            }
            return try TargetDevice(wholeBSD: bsdName)

        case .image(let path, let size):
            let rounded = (size + 511) / 512 * 512
            guard rounded >= requiredBytes else {
                throw InstallerError(
                    phase: .prepareTarget, kind: .insufficientSpace,
                    message: "An image of \(rounded) bytes is too small; this ISO needs \(requiredBytes).", path: path
                )
            }
            let fd = open(path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o644)
            guard fd >= 0 else {
                let code = errno
                throw InstallerError(
                    phase: .prepareTarget, kind: code == EEXIST ? .targetExists : .io,
                    message: "\(path) cannot be created: \(String(cString: strerror(code))).", path: path, errno: code
                )
            }
            let truncated = ftruncate(fd, off_t(rounded))
            let code = errno
            close(fd)
            guard truncated == 0 else {
                throw InstallerError(
                    phase: .prepareTarget, kind: .io,
                    message: "\(path) cannot be sized to \(rounded) bytes: \(String(cString: strerror(code))).", path: path, errno: code
                )
            }
            let attachment: DiskTools.Attachment
            do {
                attachment = try tools.attachRawImage(path)
            } catch {
                throw InstallerError(phase: .prepareTarget, kind: .io, message: "\(path) could not be attached.", underlying: "\(error)", path: path)
            }
            imageDevice = attachment.device
            // C20: the device node comes from the attach that just ran, checked against
            // ^/dev/disk[0-9]+$ by parseAttachment.
            return try TargetDevice(wholeBSD: String(attachment.device.dropFirst("/dev/".count)))
        }
    }

    // MARK: - Cleanup

    /// §11: boot partition unmount → ISO detach → image detach → mount guard → work directory.
    /// Every step runs even if an earlier one fails.
    private func cleanup() {
        if let bootMountPoint, WorkDirectory.mountPoints().contains(bootMountPoint.path) {
            log("cleanup: unmounting \(bootMountPoint.path)")
            if !tools.unmount(bootMountPoint.path) {
                log("cleanup: \(bootMountPoint.path) is still mounted")
            }
        }
        bootMountPoint = nil
        iso?.close()
        iso = nil
        if let imageDevice {
            if !tools.detach(imageDevice) {
                log("cleanup: \(imageDevice) could not be detached")
            }
            self.imageDevice = nil
        }
        mountGuard?.release()
        mountGuard = nil
        work?.remove()
        work = nil
        log("cleanup: done")
    }

    // MARK: - Errors

    static func installerError(from error: Error, phase: Phase, targetModified: Bool, currentPath: String?) -> InstallerError {
        var result: InstallerError
        switch error {
        case let error as InstallerError:
            result = error
        case let error as NTFS3GError:
            if case .posix(let operation, let path, let code) = error {
                let where_ = path ?? currentPath
                result = InstallerError(
                    phase: phase, kind: .io,
                    message: "\(operation.capitalizedFirst) failed\(where_.map { " on \($0)" } ?? ""): \(String(cString: strerror(code))) (\(errnoName(code))).",
                    underlying: "NTFS3GError: \(error)", path: where_, errno: code
                )
            } else {
                result = InstallerError(phase: phase, kind: .other, message: "\(error)".capitalizedFirst + ".", underlying: "NTFS3GError: \(error)", path: currentPath)
            }
        case let error as SDError:
            if case .io(let operation, let code) = error {
                result = InstallerError(
                    phase: phase, kind: .io,
                    message: "\(operation) failed: \(String(cString: strerror(code))) (\(errnoName(code))).",
                    underlying: "SDError: \(error)", errno: code
                )
            } else {
                result = InstallerError(phase: phase, kind: .other, message: "The partition table could not be written.", underlying: "SDError: \(error)")
            }
        case let error as DiskToolError:
            result = InstallerError(phase: phase, kind: .io, message: "\(error)".capitalizedFirst + ".", underlying: "\(error)")
        case let error as CocoaError:
            let code = (error.underlying as? POSIXError)?.code.rawValue
            result = InstallerError(
                phase: phase, kind: .io, message: error.localizedDescription, underlying: "\(error)",
                path: error.filePath, errno: code
            )
        default:
            result = InstallerError(phase: phase, kind: .other, message: "\(error)", underlying: "\(type(of: error)): \(error)")
        }
        if targetModified && !result.targetModified {
            result = result.markingTargetModified
        }
        return result
    }
}

/// The symbolic name of an errno value, e.g. `"EIO"`.
func errnoName(_ code: Int32) -> String {
    let names: [Int32: String] = [
        EPERM: "EPERM", ENOENT: "ENOENT", EIO: "EIO", ENXIO: "ENXIO", EBADF: "EBADF", EACCES: "EACCES",
        EBUSY: "EBUSY", EEXIST: "EEXIST", ENODEV: "ENODEV", ENOTDIR: "ENOTDIR", EISDIR: "EISDIR",
        EINVAL: "EINVAL", EFBIG: "EFBIG", ENOSPC: "ENOSPC", EROFS: "EROFS", ETIMEDOUT: "ETIMEDOUT",
        ENAMETOOLONG: "ENAMETOOLONG", ENOTEMPTY: "ENOTEMPTY", EAGAIN: "EAGAIN", ENOMEM: "ENOMEM",
    ]
    return names[code] ?? "errno \(code)"
}

extension CocoaError {
    fileprivate var underlying: Error? {
        (userInfo[NSUnderlyingErrorKey] as? Error)
    }
}
