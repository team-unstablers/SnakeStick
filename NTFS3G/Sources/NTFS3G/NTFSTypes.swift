// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Options for ``NTFSVolume/format(path:options:)``.
public struct NTFSFormatOptions: Sendable, Equatable {
    /// The volume label. At most 32 UTF-16 code units, without the characters that Windows
    /// forbids in names and without a trailing dot or space. Empty means no label.
    public var label: String

    /// The cluster size in bytes. ``NTFSVolume/estimatedVolumeSize(forTreeAt:clusterSize:)``
    /// must be given the same value.
    public var clusterSize: Int

    /// The logical sector size of the target disk in bytes: 512 or 4096.
    public var sectorSize: Int

    /// The LBA, in sectors of `sectorSize`, at which the partition will start on the target disk.
    /// Only recorded in the boot sector ("hidden sectors"); the image itself always starts at
    /// byte 0 of the file.
    public var partitionStartSector: UInt64

    public init(
        label: String = "",
        clusterSize: Int = 4096,
        sectorSize: Int = 512,
        partitionStartSector: UInt64 = 0
    ) {
        self.label = label
        self.clusterSize = clusterSize
        self.sectorSize = sectorSize
        self.partitionStartSector = partitionStartSector
    }
}

/// The times stored for a file or directory. NTFS keeps them with 100 ns precision.
///
/// NTFS also records when the MFT record last changed. That time is always set to the current
/// time by libntfs-3g and cannot be chosen, so it is not part of this type.
public struct NTFSFileTimes: Sendable, Equatable {
    public var creation: Date
    public var modification: Date
    public var access: Date

    public init(creation: Date, modification: Date, access: Date) {
        self.creation = creation
        self.modification = modification
        self.access = access
    }
}

public enum NTFSItemKind: Sendable, Hashable {
    case file
    case directory
}

public struct NTFSDirectoryEntry: Sendable, Hashable {
    public var name: String
    public var kind: NTFSItemKind

    public init(name: String, kind: NTFSItemKind) {
        self.name = name
        self.kind = kind
    }
}

public struct NTFSItemAttributes: Sendable, Equatable {
    public var kind: NTFSItemKind
    /// The size of the unnamed data stream in bytes. Always 0 for a directory.
    public var size: Int64
    public var times: NTFSFileTimes

    public init(kind: NTFSItemKind, size: Int64, times: NTFSFileTimes) {
        self.kind = kind
        self.size = size
        self.times = times
    }
}

public struct NTFSCopyProgress: Sendable, Equatable {
    /// Bytes of file data written so far, over all files.
    public var completedBytes: Int64
    /// The total size of all regular files in the source tree, measured before copying.
    public var totalBytes: Int64
    /// The NTFS path of the file being written.
    public var currentPath: String

    public init(completedBytes: Int64, totalBytes: Int64, currentPath: String) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.currentPath = currentPath
    }
}

public struct NTFSCopySummary: Sendable, Equatable {
    /// Regular files created.
    public var files: Int
    /// Directories created (not counting the destination).
    public var directories: Int
    /// Bytes of file data written.
    public var bytes: Int64

    public init(files: Int, directories: Int, bytes: Int64) {
        self.files = files
        self.directories = directories
        self.bytes = bytes
    }
}
