// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where the installer is written.
public enum InstallerTarget: Sendable, Codable, Equatable {
    /// A whole disk, by BSD name (`"disk4"`). The pipeline opens `/dev/rdisk4`. Needs root.
    case device(bsdName: String)
    /// A raw disk image. The file must not exist; it is created sparse with `size` bytes (rounded
    /// up to whole sectors) and attached with `hdiutil`.
    case image(path: String, size: UInt64)
}

public struct InstallerOptions: Sendable, Codable, Equatable {
    /// The NTFS volume label (also the GPT name of the NTFS partition). `nil` uses
    /// ``ISOInfo/volumeLabel`` or, if that is not a valid NTFS label, `"WINDOWS"`.
    public var volumeLabel: String?
    /// Read the NTFS volume back and compare it with the ISO after writing. The partition table
    /// and the boot partition are checked either way.
    public var verifyAfterWrite: Bool
    /// Replace the boot loaders with the Windows UEFI CA 2023 signed ones from `boot.wim`.
    /// Windows 11 25H2 (build 26200) or later only.
    public var useCA2023Bootloaders: Bool

    public init(volumeLabel: String? = nil, verifyAfterWrite: Bool = true, useCA2023Bootloaders: Bool = false) {
        self.volumeLabel = volumeLabel
        self.verifyAfterWrite = verifyAfterWrite
        self.useCA2023Bootloaders = useCA2023Bootloaders
    }
}

public struct InstallerRequest: Sendable, Codable, Equatable {
    public var isoPath: String
    public var target: InstallerTarget
    public var options: InstallerOptions

    public init(isoPath: String, target: InstallerTarget, options: InstallerOptions = .init()) {
        self.isoPath = isoPath
        self.target = target
        self.options = options
    }
}

/// The eight steps of the pipeline, in order.
public enum Phase: Int, Sendable, Codable, CaseIterable, Comparable {
    case openISO = 1
    case prepareTarget
    case writePartitionTable
    case checkPartitions
    case formatNTFS
    case copyFiles
    case prepareBootPartition
    case verify

    public static func < (lhs: Phase, rhs: Phase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The step shown while it runs, in English (the CLI's wording).
    public var title: String {
        switch self {
        case .openISO: "Opening the ISO"
        case .prepareTarget: "Preparing the target disk"
        case .writePartitionTable: "Writing the partition table"
        case .checkPartitions: "Checking the partitions"
        case .formatNTFS: "Formatting the NTFS partition"
        case .copyFiles: "Copying files"
        case .prepareBootPartition: "Preparing the UEFI:NTFS boot partition"
        case .verify: "Verifying the written data"
        }
    }

    /// A short name for error messages, in English.
    public var name: String {
        switch self {
        case .openISO: "open ISO"
        case .prepareTarget: "prepare target"
        case .writePartitionTable: "partition table"
        case .checkPartitions: "check partitions"
        case .formatNTFS: "NTFS format"
        case .copyFiles: "copy files"
        case .prepareBootPartition: "boot partition"
        case .verify: "verify"
        }
    }
}

public struct Progress: Sendable, Codable, Equatable {
    public var phase: Phase
    /// Overall progress, 0...1. Copying the files takes most of it.
    public var fraction: Double
    /// The file being copied or verified, if any.
    public var detail: String?
    /// Only while the files are copied, from the recent throughput.
    public var estimatedRemaining: TimeInterval?

    public init(phase: Phase, fraction: Double, detail: String? = nil, estimatedRemaining: TimeInterval? = nil) {
        self.phase = phase
        self.fraction = fraction
        self.detail = detail
        self.estimatedRemaining = estimatedRemaining
    }
}

public enum InstallerEvent: Sendable, Codable, Equatable {
    case progress(Progress)
    /// Phase changes, external commands with their exit status, cleanup results, errors.
    case log(String)
    case finished(InstallerResult)
    case failed(InstallerError)
}

public struct InstallerResult: Sendable, Codable, Equatable {
    public var elapsed: TimeInterval
    /// Whether the NTFS volume was read back and compared with the ISO.
    public var verified: Bool

    public init(elapsed: TimeInterval, verified: Bool) {
        self.elapsed = elapsed
        self.verified = verified
    }
}

/// Every error the pipeline reports. Carries both an English message (for the CLI and logs) and
/// the structured fields a GUI needs to word it in another language.
public struct InstallerError: Error, Sendable, Codable, Equatable, CustomStringConvertible {
    public enum Kind: String, Sendable, Codable {
        /// An argument or option is unusable (label, image size, disk name).
        case usage
        /// The ISO file does not exist or cannot be read.
        case isoMissing
        /// The file is not a Windows installation ISO, or lacks what an option needs.
        case invalidISO
        /// Writing to a disk needs root.
        case rootRequired
        /// The disk is not an eligible target (internal, boot disk, image, gone).
        case targetIneligible
        /// The target is smaller than ``ISOInfo/requiredBytes``.
        case insufficientSpace
        /// The image file already exists.
        case targetExists
        /// A read, write or system call failed.
        case io
        /// What was read back differs from what was written.
        case verificationFailed
        /// The operation was cancelled.
        case cancelled
        /// Anything else, such as a partition slice that does not match the table.
        case other
    }

    public var phase: Phase
    public var kind: Kind
    /// For people, in English: what went wrong.
    public var message: String
    /// For developers: the error type and errno.
    public var underlying: String
    /// For people, in English: the state the target is left in.
    public var targetState: String
    /// Whether the target was changed before the failure (the partition table was written).
    public var targetModified: Bool
    /// The file or device the error is about, if any.
    public var path: String?
    /// The errno of a failed system call, if any.
    public var errno: Int32?

    public init(
        phase: Phase, kind: Kind, message: String, underlying: String = "",
        targetModified: Bool = false, path: String? = nil, errno: Int32? = nil
    ) {
        self.phase = phase
        self.kind = kind
        self.message = message
        self.underlying = underlying
        self.targetModified = targetModified
        self.targetState = targetModified
            ? "The target cannot be booted now; write it again to use it."
            : "The target was not changed."
        self.path = path
        self.errno = errno
    }

    public var description: String {
        "\(message) (\(phase.name)\(underlying.isEmpty ? "" : ": \(underlying)"))"
    }

    var markingTargetModified: InstallerError {
        var copy = self
        copy.targetModified = true
        copy.targetState = "The target cannot be booted now; write it again to use it."
        return copy
    }
}
