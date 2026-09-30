// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The whole disk being written, whether a real disk or an attached image (§4). Everything after
/// step 2 only sees this.
struct TargetDevice {
    /// `"disk4"`.
    let wholeBSD: String

    init(wholeBSD: String) throws {
        guard DiskCandidate.isWholeDiskName(wholeBSD) else {
            throw InstallerError(phase: .prepareTarget, kind: .usage, message: "\(wholeBSD) is not a whole-disk name.")
        }
        self.wholeBSD = wholeBSD
    }

    /// `/dev/rdiskN`: SlopDisk and `newfs_msdos` write here (C8).
    var raw: String { "/dev/r\(wholeBSD)" }
    /// `/dev/diskN`: `diskutil` takes this.
    var buffered: String { "/dev/\(wholeBSD)" }

    /// The partition in GPT entry slot `index` (0-based), published by the kernel as `diskNs<index+1>`.
    func slice(forEntry index: Int) -> PartitionSlice {
        PartitionSlice(bsdName: "\(wholeBSD)s\(index + 1)")
    }
}

/// A partition slice of the target. The paths are built from strings, so they say nothing about
/// which disk they belong to until `Partitioning.checkSlice` has compared them with the table (C17).
struct PartitionSlice {
    let bsdName: String
    var raw: String { "/dev/r\(bsdName)" }
    var buffered: String { "/dev/\(bsdName)" }

    /// C18: only these shapes are handed to tools that format.
    var hasSlicePaths: Bool {
        raw.wholeMatch(of: #/\/dev\/rdisk[0-9]+s[0-9]+/#) != nil
            && buffered.wholeMatch(of: #/\/dev\/disk[0-9]+s[0-9]+/#) != nil
    }
}
