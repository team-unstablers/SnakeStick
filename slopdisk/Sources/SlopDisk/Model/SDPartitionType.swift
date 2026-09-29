//
//  SDPartitionType.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// A GPT partition type GUID.
///
/// Unknown GUIDs are preserved as-is. There is deliberately no `.fat32`: GPT has no FAT32 type GUID,
/// and FAT32 data partitions use `.microsoftBasicData`.
public struct SDPartitionType: Hashable, Sendable, CustomStringConvertible {
    public var guid: UUID

    public init(guid: UUID) {
        self.guid = guid
    }

    public static let efiSystem = SDPartitionType(known: "C12A7328-F81F-11D2-BA4B-00A0C93EC93B")
    public static let microsoftBasicData = SDPartitionType(known: "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7")
    public static let microsoftReserved = SDPartitionType(known: "E3C9E316-0B5C-4DB8-817D-F92DF00215AE")
    public static let microsoftRecovery = SDPartitionType(known: "DE94BBA4-06D1-4D40-A16A-BFD50179D6AC")
    public static let biosBoot = SDPartitionType(known: "21686148-6449-6E6F-744E-656564454649")
    public static let linuxFilesystem = SDPartitionType(known: "0FC63DAF-8483-4772-8E79-3D69D8477DE4")
    public static let linuxSwap = SDPartitionType(known: "0657FD6D-A4AB-43C4-84E5-0933C84B4F4F")
    public static let appleAPFS = SDPartitionType(known: "7C3457EF-0000-11AA-AA11-00306543ECAC")
    public static let appleHFSPlus = SDPartitionType(known: "48465300-0000-11AA-AA11-00306543ECAC")

    private static let names: [SDPartitionType: String] = [
        .efiSystem: "EFI System",
        .microsoftBasicData: "Microsoft Basic Data",
        .microsoftReserved: "Microsoft Reserved",
        .microsoftRecovery: "Windows Recovery",
        .biosBoot: "BIOS Boot",
        .linuxFilesystem: "Linux Filesystem",
        .linuxSwap: "Linux Swap",
        .appleAPFS: "Apple APFS",
        .appleHFSPlus: "Apple HFS+",
    ]

    /// A human-readable name for well-known types, `nil` otherwise.
    public var name: String? {
        Self.names[self]
    }

    /// `name` if known, otherwise the upper-case GUID string.
    public var description: String {
        name ?? guid.uuidString
    }

    /// The all-zero GUID marks an unused entry slot and is not a valid type.
    var isUnused: Bool {
        guid == GUIDCodec.zero
    }

    private init(known string: String) {
        guard let guid = UUID(uuidString: string) else {
            preconditionFailure("malformed built-in GUID \(string)")
        }
        self.guid = guid
    }
}
