//
//  SDDiskImage.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

public enum SDDiskImageSource: Sendable {
    /// A raw image file. Pass a file system path; for a `URL`, use `url.path(percentEncoded: false)`.
    case file(String)
    /// A sparse in-memory image (`SDMemoryBlockDevice`). It can be created but not reopened.
    case inMemory
}

/// Factory that picks a block device backend for a disk image and wraps it in an `SDDisk`.
public enum SDDiskImage {
    /// Creates a new, all-zero image.
    ///
    /// `desiredSize` is rounded up to a multiple of `sectorSize`; the actual size is `disk.size`.
    /// The returned disk has `scheme == .none`. Throws `.diskTooSmall` if the image cannot hold a GPT,
    /// and `.fileExists` if the file already exists.
    public static func create(
        _ source: SDDiskImageSource, desiredSize: SDSize, sectorSize: Int = 512
    ) throws(SDError) -> SDDisk {
        try validate(sectorSize: sectorSize)
        let unit = UInt64(sectorSize)
        let remainder = desiredSize.bytes % unit
        let (byteCount, overflow) = desiredSize.bytes.addingReportingOverflow(remainder == 0 ? 0 : unit - remainder)
        guard !overflow else {
            throw .invalidArgument("desired size \(desiredSize.bytes) overflows when rounded to sectors")
        }
        let sectorCount = byteCount / unit
        let minimum = GPTGeometry.minimumSectorCount(sectorSize: sectorSize)
        guard sectorCount >= minimum else {
            throw .diskTooSmall(minimum: SDSize(bytes: minimum * unit))
        }

        let device: any SDBlockDevice
        switch source {
        case .inMemory:
            device = SDMemoryBlockDevice(sectorSize: sectorSize, sectorCount: sectorCount)
        case .file(let path):
            device = try SDFileBlockDevice.create(path: path, byteCount: byteCount, sectorSize: sectorSize)
        }
        // A new device is all zeros, so reading it would only confirm `.none`.
        return try SDDisk(device: device, ignoringExistingTable: true)
    }

    /// Opens an existing image file.
    ///
    /// With `sectorSize: nil`, the sector size is detected by looking for "EFI PART" at byte offset 512
    /// and then 4096; if neither is found, 512 is used. Throws `.invalidArgument` for `.inMemory`.
    public static func open(
        _ source: SDDiskImageSource, mode: SDOpenMode = .readWrite, sectorSize: Int? = nil
    ) throws(SDError) -> SDDisk {
        guard case .file(let path) = source else {
            throw .invalidArgument("an in-memory image cannot be opened; keep the SDDisk returned by create")
        }
        let resolved: Int
        if let sectorSize {
            resolved = sectorSize
        } else {
            resolved = try detectSectorSize(path: path)
        }
        try validate(sectorSize: resolved)
        let device = try SDFileBlockDevice(path: path, mode: mode, sectorSize: resolved)
        return try SDDisk(device: device)
    }

    /// Looks for a GPT header signature at byte offsets 512 and 4096. Returns 512 if neither is present.
    ///
    /// The probe device is opened read-only and released before this returns, so its shared lock
    /// does not conflict with a subsequent read-write open.
    package static func detectSectorSize(path: String) throws(SDError) -> Int {
        let probe = try SDFileBlockDevice(path: path, mode: .readOnly, sectorSize: 512)
        if probe.sectorCount > 1, GPTHeader.hasSignature(try probe.readSectors(lba: 1, count: 1)) {
            return 512
        }
        if probe.sectorCount > 8, GPTHeader.hasSignature(try probe.readSectors(lba: 8, count: 1)) {
            return 4096
        }
        return 512
    }

    private static func validate(sectorSize: Int) throws(SDError) {
        guard sectorSize == 512 || sectorSize == 4096 else {
            throw .invalidArgument("sector size must be 512 or 4096, not \(sectorSize)")
        }
    }
}
