// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Step 7: the 1 MiB FAT partition that holds UEFI:NTFS (§8), and its check in step 8.
struct BootPartition {
    static let volumeLabel = "UEFI_NTFS"
    /// Items macOS may leave on a volume mounted read-write (C6). Removed before unmounting.
    static let metadataNames: Set<String> = [".fseventsd", ".Spotlight-V100", ".Trashes", ".TemporaryItems", ".DS_Store"]

    let slice: PartitionSlice
    let mountPoint: URL
    let tools: DiskTools
    let mountGuard: MountGuard
    let log: (String) -> Void

    /// `newfs_msdos` on the raw slice (the FAT type is left to it: FAT12 for 1 MiB, U8), a
    /// read-write mount, the four files copied without extended attributes, the macOS
    /// metadata scrubbed, and an unmount.
    func create() throws {
        guard slice.hasSlicePaths else {
            throw InstallerError(phase: .prepareBootPartition, kind: .other, message: "\(slice.bsdName) is not a partition slice name.", targetModified: true)
        }
        let format = try tools.subprocess.run("/sbin/newfs_msdos", ["-v", Self.volumeLabel, slice.raw])
        guard format.status == 0 else {
            throw failure("newfs_msdos failed on \(slice.raw): \(format.stderrText)")
        }
        try mount(readOnly: false)
        var mounted = true
        defer {
            if mounted {
                tools.unmount(mountPoint.path)
            }
        }

        let destination = mountPoint.appendingPathComponent(UEFINTFSPayload.directoryOnPartition, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in UEFINTFSPayload.fileNames {
            let copy = try tools.subprocess.run(
                "/usr/bin/ditto", ["--norsrc", "--noextattr", "--noqtn", "--noacl", try UEFINTFSPayload.url(of: name).path, destination.appendingPathComponent(name).path]
            )
            guard copy.status == 0 else {
                throw failure("Copying \(name) to the boot partition failed: \(copy.stderrText)")
            }
        }
        let removed = scrubMetadata()
        log("boot partition: removed before unmounting: \(removed.isEmpty ? "nothing" : removed.joined(separator: ", "))")

        mounted = false
        guard tools.unmount(mountPoint.path) else {
            throw failure("The boot partition \(slice.buffered) could not be unmounted.")
        }
    }

    /// Mounts the partition read-only and compares the four files with the bundled ones. Fails on
    /// `._*` files and `.DS_Store`; other macOS metadata is only logged (U9).
    func verify() throws {
        try mount(readOnly: true)
        defer { tools.unmount(mountPoint.path) }
        let directory = mountPoint.appendingPathComponent(UEFINTFSPayload.directoryOnPartition)
        for name in UEFINTFSPayload.fileNames {
            let written = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: written.path) else {
                throw failure("The boot partition lacks \(UEFINTFSPayload.directoryOnPartition)/\(name).", phase: .verify, kind: .verificationFailed)
            }
            guard try UEFINTFSPayload.sha256(of: written) == UEFINTFSPayload.sha256(of: UEFINTFSPayload.url(of: name)) else {
                throw failure("\(UEFINTFSPayload.directoryOnPartition)/\(name) on the boot partition differs from the bundled file.", phase: .verify, kind: .verificationFailed)
            }
        }
        let leftovers = metadataItems()
        if !leftovers.isEmpty {
            log("boot partition: macOS metadata found after unmounting: \(leftovers.joined(separator: ", "))")
        }
        if let appleDouble = leftovers.first(where: { ($0 as NSString).lastPathComponent.hasPrefix("._") || $0.hasSuffix(".DS_Store") }) {
            throw failure("The boot partition contains \(appleDouble).", phase: .verify, kind: .verificationFailed)
        }
    }

    private func mount(readOnly: Bool) throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        // One attempt plus one retry; the guard's permission is used up by each attempt (C22).
        var lastError = ""
        for _ in 0 ..< 2 {
            mountGuard.allowNextMount(of: slice.bsdName)
            let arguments = (readOnly ? ["mount", "readOnly"] : ["mount"]) + ["-mountPoint", mountPoint.path, slice.buffered]
            let output = try tools.subprocess.run("/usr/sbin/diskutil", arguments)
            if output.status == 0 {
                return
            }
            lastError = output.stderrText.isEmpty ? output.stdoutText : output.stderrText
            Thread.sleep(forTimeInterval: 1)
        }
        throw failure("The boot partition \(slice.buffered) could not be mounted: \(lastError)", phase: readOnly ? .verify : .prepareBootPartition)
    }

    /// Removes the items in ``metadataNames`` at the root and `._*` / `.DS_Store` anywhere.
    private func scrubMetadata() -> [String] {
        var removed: [String] = []
        for relative in metadataItems() {
            do {
                try FileManager.default.removeItem(at: mountPoint.appendingPathComponent(relative))
                removed.append(relative)
            } catch {
                log("boot partition: could not remove \(relative): \(error)")
            }
        }
        return removed
    }

    /// Relative paths of macOS metadata on the mounted partition.
    private func metadataItems() -> [String] {
        var found: [String] = []
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: mountPoint.path)) ?? [] where Self.metadataNames.contains(name) {
            found.append(name)
        }
        if let enumerator = fm.enumerator(atPath: mountPoint.path) {
            for case let relative as String in enumerator {
                let name = (relative as NSString).lastPathComponent
                if name.hasPrefix("._") || (name == ".DS_Store" && relative != name) {
                    found.append(relative)
                }
                if Self.metadataNames.contains(relative) {
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }

    private func failure(_ message: String, phase: Phase = .prepareBootPartition, kind: InstallerError.Kind = .io) -> InstallerError {
        InstallerError(phase: phase, kind: kind, message: message, targetModified: true, path: slice.buffered)
    }
}
