//
//  SDPartitionAttributes.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// GPT partition attribute bits. Unknown bits are preserved when read and written.
public struct SDPartitionAttributes: OptionSet, Hashable, Sendable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// Bit 0: required for the platform to function.
    public static let requiredPartition = SDPartitionAttributes(rawValue: 1 << 0)
    /// Bit 1: firmware must not produce an EFI_BLOCK_IO_PROTOCOL for this partition.
    public static let noBlockIOProtocol = SDPartitionAttributes(rawValue: 1 << 1)
    /// Bit 2: legacy BIOS bootable.
    public static let legacyBIOSBootable = SDPartitionAttributes(rawValue: 1 << 2)
    /// Bit 60 (Microsoft Basic Data only): read-only.
    public static let msReadOnly = SDPartitionAttributes(rawValue: 1 << 60)
    /// Bit 61 (Microsoft Basic Data only): shadow copy.
    public static let msShadowCopy = SDPartitionAttributes(rawValue: 1 << 61)
    /// Bit 62 (Microsoft Basic Data only): hidden.
    public static let msHidden = SDPartitionAttributes(rawValue: 1 << 62)
    /// Bit 63 (Microsoft Basic Data only): no drive letter.
    public static let msNoDriveLetter = SDPartitionAttributes(rawValue: 1 << 63)
}
