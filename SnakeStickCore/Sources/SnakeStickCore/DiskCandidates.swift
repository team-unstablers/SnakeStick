// SPDX-License-Identifier: GPL-3.0-or-later

import DiskArbitration
import Foundation

/// A whole disk that SnakeStick could write to, as DiskArbitration describes it (P8).
public struct DiskCandidate: Sendable, Codable, Identifiable, Equatable {
    public struct Volume: Sendable, Codable, Equatable {
        public var name: String
        /// DiskArbitration's volume type, such as `"ExFAT"` or `"MS-DOS (FAT32)"`.
        public var fileSystem: String

        public init(name: String, fileSystem: String) {
            self.name = name
            self.fileSystem = fileSystem
        }
    }

    public var id: String { bsdName }
    /// `"disk4"`.
    public var bsdName: String
    /// Vendor and model, e.g. `"SanDisk Ultra USB 3.0"`.
    public var model: String
    public var sizeBytes: UInt64
    /// `DADeviceProtocol`, e.g. `"USB"`.
    public var protocolName: String
    /// Partitions directly on the disk.
    public var partitionCount: Int
    /// Volumes DiskArbitration recognized on the disk.
    public var volumes: [Volume]
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isBootDisk: Bool
    /// A disk image, or a disk synthesized by a volume manager such as APFS.
    public var isVirtual: Bool
    /// Whether the disk may be written to at all (P8). The size check against an ISO is separate:
    /// see ``isLargeEnough(for:)``.
    public var isEligible: Bool
    /// Why the disk is not eligible, in English.
    public var ineligibleReason: String?

    public init(
        bsdName: String, model: String, sizeBytes: UInt64, protocolName: String, partitionCount: Int,
        volumes: [Volume], isInternal: Bool, isRemovable: Bool, isBootDisk: Bool, isVirtual: Bool,
        isEligible: Bool, ineligibleReason: String?
    ) {
        self.bsdName = bsdName
        self.model = model
        self.sizeBytes = sizeBytes
        self.protocolName = protocolName
        self.partitionCount = partitionCount
        self.volumes = volumes
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isBootDisk = isBootDisk
        self.isVirtual = isVirtual
        self.isEligible = isEligible
        self.ineligibleReason = ineligibleReason
    }

    public func isLargeEnough(for requiredBytes: UInt64) -> Bool {
        sizeBytes >= requiredBytes
    }

    /// Whether `name` is a whole-disk BSD name, `disk` followed by digits (C21).
    public static func isWholeDiskName(_ name: String) -> Bool {
        name.wholeMatch(of: #/disk[0-9]+/#) != nil
    }
}

/// The verdict of ``DiskCandidate/classify(description:bootWholeDisks:isSynthesized:)``.
public struct DiskClassification: Sendable, Equatable {
    public var bsdName: String
    public var isWhole: Bool
    public var isInternal: Bool
    public var isRemovable: Bool
    public var isBootDisk: Bool
    public var isVirtual: Bool
    public var isWritable: Bool
    public var isEligible: Bool
    public var ineligibleReason: String?
}

extension DiskCandidate {
    /// The partition scheme DiskArbitration reports for a disk that APFS synthesizes on top of a
    /// container partition (`7C3457EF-…` is the partition type, this is the scheme name).
    static let apfsSynthesizedContent = "EF57347C-0000-11AA-AA11-00306543ECAC"

    /// Applies the P8 rules to a DiskArbitration description (`DADiskCopyDescription`, keyed by
    /// the `DA…` strings). Pure, so that the rules can be tested with dictionaries.
    ///
    /// Eligible: a whole, writable disk that is external or removable, is not a disk image or
    /// synthesized disk, and is not (beneath) the startup disk. A missing `DADeviceInternal`
    /// counts as internal. Disk images report no `DADeviceInternal` and `DAMediaRemovable = 1`,
    /// and APFS synthesized disks copy the device keys of their physical store, so both are
    /// recognized by other keys.
    public static func classify(
        description: [String: Any],
        bootWholeDisks: Set<String>,
        isSynthesized: Bool = false
    ) -> DiskClassification {
        let bsdName = description["DAMediaBSDName"] as? String ?? ""
        let isWhole = bool(description["DAMediaWhole"]) ?? false
        let isInternal = bool(description["DADeviceInternal"]) ?? true
        let isRemovable = bool(description["DAMediaRemovable"]) ?? false
        let isWritable = bool(description["DAMediaWritable"]) ?? true
        let deviceProtocol = trimmed(description["DADeviceProtocol"])
        let model = trimmed(description["DADeviceModel"])
        let devicePath = description["DADevicePath"] as? String ?? ""
        let content = description["DAMediaContent"] as? String ?? ""
        let isVirtual = isSynthesized
            || deviceProtocol == "Virtual Interface"
            || model == "Disk Image"
            || devicePath.contains("AppleDiskImage")
            || content.caseInsensitiveCompare(apfsSynthesizedContent) == .orderedSame
        let isBootDisk = bootWholeDisks.contains(bsdName)

        let reason: String? = if !isWhole {
            "not a whole disk"
        } else if isBootDisk {
            "startup disk"
        } else if isVirtual {
            "disk image or virtual disk"
        } else if isInternal && !isRemovable {
            "internal disk"
        } else if !isWritable {
            "read-only media"
        } else {
            nil
        }
        return DiskClassification(
            bsdName: bsdName, isWhole: isWhole, isInternal: isInternal, isRemovable: isRemovable,
            isBootDisk: isBootDisk, isVirtual: isVirtual, isWritable: isWritable,
            isEligible: reason == nil, ineligibleReason: reason
        )
    }

    /// `DADeviceVendor` + `DADeviceModel`, trimmed. The vendor is left out when it is empty or
    /// only repeats the protocol (USB bridges report `"USB"`).
    static func displayModel(description: [String: Any]) -> String {
        let vendor = trimmed(description["DADeviceVendor"])
        let model = trimmed(description["DADeviceModel"])
        let deviceProtocol = trimmed(description["DADeviceProtocol"])
        if vendor.isEmpty || vendor == deviceProtocol || model.lowercased().hasPrefix(vendor.lowercased()) {
            return model.isEmpty ? vendor : model
        }
        return model.isEmpty ? vendor : "\(vendor) \(model)"
    }

    /// The file system shown for a volume. `DAVolumeKind` decides: `DAVolumeType` was seen to
    /// report `MS-DOS (FAT12)` for an NTFS volume (macOS 26), so it is used only for FAT, where it
    /// names the FAT type.
    static func fileSystemName(kind: String?, type: String?) -> String? {
        switch kind?.lowercased() {
        case "msdos": type ?? "MS-DOS"
        case "ntfs": "NTFS"
        case "exfat": "ExFAT"
        case "apfs": "APFS"
        case "hfs": "Mac OS Extended"
        case "udf": "UDF"
        case "cd9660": "ISO 9660"
        case let other?: type ?? other
        case nil: type
        }
    }

    private static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        default: nil
        }
    }

    private static func trimmed(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// The external and removable whole disks that may be written to (P8). Internal disks, disk
/// images and the startup disk are not returned.
public func listDiskCandidates() throws -> [DiskCandidate] {
    try listWholeDisks().filter(\.isEligible)
}

/// Every whole disk with its verdict, eligible or not (for `snakestick disks`).
public func listWholeDisks() throws -> [DiskCandidate] {
    guard let session = DASessionCreate(kCFAllocatorDefault) else {
        throw InstallerError(phase: .prepareTarget, kind: .other, message: "DiskArbitration is not available.")
    }
    let bootWholeDisks = startupWholeDisks()
    guard !bootWholeDisks.isEmpty else {
        // Without knowing the startup disk nothing can be offered safely.
        throw InstallerError(phase: .prepareTarget, kind: .other, message: "The startup disk cannot be determined.")
    }
    let allNames = IORegistry.allMediaBSDNames()

    var descriptions: [String: [String: Any]] = [:]
    for name in allNames {
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, name),
              let description = DADiskCopyDescription(disk) as? [String: Any]
        else {
            continue
        }
        descriptions[name] = description
    }

    var candidates: [DiskCandidate] = []
    for (name, description) in descriptions where DiskCandidate.isWholeDiskName(name) {
        let media = IORegistry.media(bsdName: name)
        let verdict = DiskCandidate.classify(
            description: description,
            bootWholeDisks: bootWholeDisks,
            isSynthesized: media?.isSynthesized ?? false
        )
        guard verdict.isWhole else {
            continue
        }
        let partitionNames = descriptions.keys.filter { $0.wholeMatch(of: try! Regex("\(name)s[0-9]+")) != nil }
        var volumes: [DiskCandidate.Volume] = []
        for partition in [name] + partitionNames.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            guard let partitionDescription = descriptions[partition],
                  let type = DiskCandidate.fileSystemName(
                      kind: partitionDescription["DAVolumeKind"] as? String,
                      type: partitionDescription["DAVolumeType"] as? String
                  )
            else {
                continue
            }
            volumes.append(.init(name: partitionDescription["DAVolumeName"] as? String ?? "", fileSystem: type))
        }
        candidates.append(DiskCandidate(
            bsdName: name,
            model: DiskCandidate.displayModel(description: description),
            sizeBytes: (description["DAMediaSize"] as? NSNumber)?.uint64Value ?? 0,
            protocolName: (description["DADeviceProtocol"] as? String ?? "").trimmingCharacters(in: .whitespaces),
            partitionCount: partitionNames.count,
            volumes: volumes,
            isInternal: verdict.isInternal,
            isRemovable: verdict.isRemovable,
            isBootDisk: verdict.isBootDisk,
            isVirtual: verdict.isVirtual,
            isEligible: verdict.isEligible,
            ineligibleReason: verdict.ineligibleReason
        ))
    }
    return candidates.sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
}

/// The whole disks beneath `/` and `/System/Volumes/Data`, including the physical stores of an
/// APFS container.
func startupWholeDisks() -> Set<String> {
    var result: Set<String> = []
    for path in ["/", "/System/Volumes/Data"] {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            continue
        }
        let from = withUnsafeBytes(of: info.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        guard from.hasPrefix("/dev/") else {
            continue
        }
        result.formUnion(IORegistry.wholeDisksBeneath(bsdName: String(from.dropFirst("/dev/".count))))
    }
    return result
}
