// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Foundation

/// An NTFS volume stored in an image file, opened through libntfs-3g.
///
/// The image holds exactly one partition, starting at byte 0 of the file. Placing it inside a
/// disk image is up to the caller.
///
/// All methods block on file I/O. The class is not `Sendable`: create it, use it and close it
/// from one task, typically a background one. Call ``close()`` when done; it flushes the
/// volume and reports errors that `deinit` could only log.
public final class NTFSVolume {
    public enum Mode: Sendable {
        case readOnly
        case readWrite
    }

    /// The volume label, or an empty string if there is none.
    public let label: String

    /// The cluster size in bytes.
    public let clusterSize: Int

    /// The size of the volume in bytes (clusters × cluster size).
    public let totalBytes: Int64

    /// Free space in bytes, counted from the cluster bitmap when read. After ``close()``, the
    /// value last observed while the volume was open.
    public var freeBytes: Int64 {
        guard let handle else {
            return lastFreeBytes
        }
        if ntfs_volume_get_free_space(handle) == 0 {
            lastFreeBytes = handle.pointee.free_clusters * Int64(handle.pointee.cluster_size)
        }
        return lastFreeBytes
    }

    let path: String
    let mode: Mode
    private var handle: UnsafeMutablePointer<ntfs_volume>?
    private var lastFreeBytes: Int64 = 0

    /// Mounts the NTFS volume in the image file at `path`.
    ///
    /// A read-write mount fails if Windows left the volume hibernated or not cleanly unmounted;
    /// libntfs-3g's recovery options are not used.
    public init(path: String, mode: Mode) throws {
        cntfs3g_initialize()
        let flags = switch mode {
        case .readOnly: ntfs_mount_flags(NTFS_MNT_RDONLY)
        case .readWrite: ntfs_mount_flags(NTFS_MNT_NONE)
        }
        guard let handle = ntfs_mount(path, flags) else {
            throw NTFS3GError.posix(operation: "mount", path: path, errno: errno)
        }
        self.path = path
        self.mode = mode
        self.handle = handle
        label = handle.pointee.vol_name.map { String(cString: $0) } ?? ""
        clusterSize = Int(handle.pointee.cluster_size)
        totalBytes = handle.pointee.nr_clusters * Int64(handle.pointee.cluster_size)
        _ = freeBytes
    }

    deinit {
        if let handle {
            fputs("NTFS3G: warning: NTFSVolume for \(path) was not closed; unmounting it now\n", stderr)
            ntfs_umount(handle, CNTFS3G.BOOL(0))
        }
    }

    /// Flushes and unmounts the volume. Calling it again does nothing. Every other method
    /// throws ``NTFS3GError/volumeClosed`` afterwards.
    ///
    /// libntfs-3g releases the volume even when unmounting fails, so the volume counts as
    /// closed after an error too.
    public func close() throws {
        guard let handle else {
            return
        }
        _ = freeBytes
        // Forget the pointer first: ntfs_umount frees it whether or not it succeeds.
        self.handle = nil
        guard ntfs_umount(handle, CNTFS3G.BOOL(0)) == 0 else {
            throw NTFS3GError.posix(operation: "umount", path: path, errno: errno)
        }
    }

    func requireVolume() throws(NTFS3GError) -> UnsafeMutablePointer<ntfs_volume> {
        guard let handle else {
            throw .volumeClosed
        }
        return handle
    }

    func requireWritableVolume() throws(NTFS3GError) -> UnsafeMutablePointer<ntfs_volume> {
        let volume = try requireVolume()
        guard mode == .readWrite else {
            throw .readOnlyVolume
        }
        return volume
    }
}

// MARK: - Formatting

extension NTFSVolume {
    /// The longest volume label Windows accepts, in UTF-16 code units.
    static let maximumLabelLength = 32

    /// Formats the file at `path` as an empty NTFS volume that fills the whole file.
    ///
    /// The file must already exist with its final size. mkntfs runs in-process and calls are
    /// serialized. Unlike the mkntfs program, it leaves the process locale alone; the
    /// libntfs-3g logging state that it changes is restored afterwards.
    public static func format(path: String, options: NTFSFormatOptions = .init()) throws {
        cntfs3g_initialize()
        try validateLabel(options.label)

        var info = stat()
        guard stat(path, &info) == 0 else {
            throw NTFS3GError.posix(operation: "stat", path: path, errno: errno)
        }

        var arguments = [
            "mkntfs",
            "-F",  // the target is not a block device
            "-Q",  // do not zero the volume or check for bad sectors
            "-q",
            "-s", String(options.sectorSize),
            "-p", String(options.partitionStartSector),
            // mkntfs warns that Windows cannot boot the volume unless the geometry is given.
            "-H", "255",
            "-S", "63",
            // Always explicit, so that the cluster size matches estimatedVolumeSize's.
            "-c", String(options.clusterSize),
        ]
        if !options.label.isEmpty {
            arguments += ["-L", options.label]
        }
        arguments.append(path)

        let argv = arguments.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        var terminatedArgv = argv + [nil]
        let status = ntfs3g_mkntfs(Int32(argv.count), &terminatedArgv)
        guard status == 0 else {
            throw NTFS3GError.formatFailed(status: status)
        }
    }

    /// Volume labels follow the file name rules except for reserved device names (a label is
    /// not a file name), and are limited to 32 UTF-16 code units.
    static func validateLabel(_ label: String) throws(NTFS3GError) {
        guard !label.isEmpty else {
            return
        }
        let name = try NTFSName(label, maximumLength: maximumLabelLength)
        guard !ntfs_forbidden_chars(name.characters, Int32(name.length), .true).isTrue else {
            throw .invalidName(label)
        }
    }
}

extension CNTFS3G.BOOL {
    // Spelled out because Darwin's TRUE and FALSE macros, and ObjectiveC.BOOL, shadow
    // ntfs-3g's names.
    static let `true` = CNTFS3G.BOOL(1)
    static let `false` = CNTFS3G.BOOL(0)

    var isTrue: Bool {
        rawValue != 0
    }
}
