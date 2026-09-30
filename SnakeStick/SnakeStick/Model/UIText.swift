// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SnakeStickCore

/// User-facing wording of core values (decision 26: String Catalog, English base, Korean from
/// the Figma mockups). The core's own messages are English and go to the log.
enum UIText {
    static func size(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    static func stepTitle(_ phase: Phase) -> String {
        switch phase {
        case .openISO: String(localized: "Opening the ISO")
        case .prepareTarget: String(localized: "Preparing the target disk")
        case .writePartitionTable: String(localized: "Writing the partition table")
        case .checkPartitions: String(localized: "Checking the partitions")
        case .formatNTFS: String(localized: "Formatting the NTFS partition")
        case .copyFiles: String(localized: "Copying files")
        case .prepareBootPartition: String(localized: "Preparing the UEFI:NTFS boot partition")
        case .verify: String(localized: "Verifying the written data")
        }
    }

    static func stepName(_ phase: Phase) -> String {
        switch phase {
        case .openISO: String(localized: "Open ISO")
        case .prepareTarget: String(localized: "Prepare target")
        case .writePartitionTable: String(localized: "Partition table")
        case .checkPartitions: String(localized: "Check partitions")
        case .formatNTFS: String(localized: "NTFS format")
        case .copyFiles: String(localized: "Copy files")
        case .prepareBootPartition: String(localized: "Boot partition")
        case .verify: String(localized: "Verify")
        }
    }

    /// `Windows 11 25H2 · x64 · 7.21 GB`
    static func isoSubtitle(_ info: ISOInfo) -> String {
        String(localized: "\(info.windowsVersion) · \(info.architecture) · \(size(info.fileSize))")
    }

    /// `SanDisk Ultra USB 3.0 — 30.75 GB (disk4)`, with ` · Not enough space` when it is too small.
    static func diskMenuItem(_ disk: DiskCandidate, fits: Bool) -> String {
        fits
            ? String(localized: "\(disk.model) — \(size(disk.sizeBytes)) (\(disk.bsdName))")
            : String(localized: "\(disk.model) — \(size(disk.sizeBytes)) (\(disk.bsdName)) · Not enough space")
    }

    /// `disk4 · USB external disk · 1 partition (ExFAT “UNTITLED”)` (§2).
    static func diskSubtitle(_ disk: DiskCandidate) -> String {
        let kind = String(localized: "\(disk.protocolName) external disk")
        var partitions = String(localized: "\(disk.partitionCount) partitions")
        if !disk.volumes.isEmpty {
            let volumes = disk.volumes.map { "\($0.fileSystem) “\($0.name)”" }.joined(separator: ", ")
            partitions += " (\(volumes))"
        }
        return "\(disk.bsdName) · \(kind) · \(partitions)"
    }

    static func elapsed(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds.rounded()) ?? "\(Int(seconds))"
    }

    /// Marks errors made by the app, whose `message` is already localized.
    static let appOrigin = "SnakeStick app"

    /// The body of the 07 panel: what went wrong, then the state of the stick.
    static func errorBody(_ error: InstallerError) -> String {
        let cause: String
        switch error.kind {
        case _ where error.underlying == appOrigin:
            cause = error.message
        case .io:
            let code = error.errno.map(errnoSymbol) ?? "EIO"
            if let path = error.path, !path.hasPrefix("/dev/") {
                let shown = path.hasPrefix("/") ? String(path.dropFirst()) : path
                cause = String(localized: "An I/O error occurred while writing \(shown) (\(code)). The stick may have been removed or damaged.")
            } else {
                cause = String(localized: "An I/O error occurred (\(code)). The stick may have been removed or damaged.")
            }
        case .verificationFailed:
            cause = String(localized: "What was written differs from the ISO: \(error.path ?? "?").")
        case .invalidISO:
            cause = String(localized: "The ISO cannot be used: it is not a Windows installation ISO, or it lacks what the chosen options need.")
        case .isoMissing:
            cause = String(localized: "The ISO file cannot be read.")
        case .usage:
            cause = String(localized: "The volume label cannot be used on NTFS: at most 32 characters, none of \"*/:<>?\\|, and no space or dot at the end.")
        case .targetIneligible, .rootRequired:
            cause = String(localized: "The target disk cannot be written: it is gone, internal, or the startup disk.")
        case .insufficientSpace:
            cause = String(localized: "The target disk does not have enough space for this ISO.")
        case .targetExists, .cancelled, .other:
            cause = String(localized: "An unexpected error occurred. See the log for details.")
        }
        let state = error.targetModified
            ? String(localized: "The stick cannot be booted now.")
            : String(localized: "The stick was not changed.")
        return "\(cause) \(state)"
    }

    private static func errnoSymbol(_ code: Int32) -> String {
        [EIO: "EIO", ENXIO: "ENXIO", ENODEV: "ENODEV", ENOSPC: "ENOSPC", EACCES: "EACCES", EPERM: "EPERM",
         EBUSY: "EBUSY", EROFS: "EROFS", ETIMEDOUT: "ETIMEDOUT", EINVAL: "EINVAL", ENOENT: "ENOENT"][code] ?? "errno \(code)"
    }
}
