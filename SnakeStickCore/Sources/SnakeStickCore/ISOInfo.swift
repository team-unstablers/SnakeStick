// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import NTFS3G
import WIMLib

/// What SnakeStick needs to know about a Windows installation ISO.
public struct ISOInfo: Sendable, Codable, Equatable {
    /// The ISO 9660 volume identifier, without trailing spaces. Empty if there is none (P5).
    public var volumeLabel: String
    /// The size of the ISO file in bytes.
    public var fileSize: UInt64
    /// `"Windows 11 25H2"`, or `"Windows 11 (build N)"` for builds not in the table (P6).
    public var windowsVersion: String
    public var build: Int
    /// `"x64"`, `"ARM64"` or `"x86"` (or `"arch N"` for other codes).
    public var architecture: String
    /// Whether the Windows UEFI CA 2023 boot loader option can be used: build 26200 or later (P7).
    public var supportsCA2023: Bool
    /// The smallest target that holds the installer (decision 25, C10).
    public var requiredBytes: UInt64

    public init(
        volumeLabel: String, fileSize: UInt64, windowsVersion: String, build: Int,
        architecture: String, supportsCA2023: Bool, requiredBytes: UInt64
    ) {
        self.volumeLabel = volumeLabel
        self.fileSize = fileSize
        self.windowsVersion = windowsVersion
        self.build = build
        self.architecture = architecture
        self.supportsCA2023 = supportsCA2023
        self.requiredBytes = requiredBytes
    }

    /// The first build with Windows UEFI CA 2023 signed boot loaders that work (F24).
    public static let ca2023MinimumBuild = 26200

    /// NTFS volume estimate + 1 MiB FAT partition + 1 MiB each for the GPT at both ends (rounded to
    /// the alignment) + 2 MiB for alignment leftovers. Larger than the exact minimum on purpose.
    public static func requiredBytes(forVolumeEstimate estimate: UInt64) -> UInt64 {
        estimate + 5 * mebibyte
    }

    /// The Windows release for a build number (P6).
    public static func windowsVersion(build: Int, major: Int?) -> String {
        let names = [
            26200: "Windows 11 25H2", 26100: "Windows 11 24H2", 22631: "Windows 11 23H2",
            22621: "Windows 11 22H2", 22000: "Windows 11 21H2",
            19045: "Windows 10 22H2", 19044: "Windows 10 21H2",
        ]
        if let name = names[build] {
            return name
        }
        let product = (major ?? 10) == 10 && build >= 22000 ? "Windows 11" : "Windows \(major ?? 10)"
        return "\(product) (build \(build))"
    }

    /// The display name of a `WINDOWS/ARCH` value (P6).
    static func architectureName(_ architecture: WIMArchitecture?) -> String {
        switch architecture {
        case .x64: "x64"
        case .arm64: "ARM64"
        case .x86: "x86"
        case .arm: "ARM"
        case .other(let code): "arch \(code)"
        case nil: "unknown"
        }
    }
}

let mebibyte: UInt64 = 1 << 20

/// Reads the ISO without writing anything: its label, the Windows release in `sources/install.wim`
/// (or `install.esd`; `sources/boot.wim` must exist and is the fallback)
/// and the size of the target it needs. Mounts the ISO read-only for a few seconds.
public func inspectISO(at path: String) async throws -> ISOInfo {
    try await Blocking.run {
        let work = try WorkDirectory(log: { _ in })
        defer { work.remove() }
        let session = try ISOSession(path: path, workDirectory: work, tools: DiskTools(log: { _ in }))
        defer { session.close() }
        return session.info
    }
}

/// An ISO attached for the pipeline or for ``inspectISO(at:)``. Step 1 of the pipeline keeps it
/// attached and copies from ``mountPoint``.
final class ISOSession {
    let path: String
    let mountPoint: URL
    let info: ISOInfo
    /// `sources/boot.wim` as spelled on the ISO.
    let bootWIM: URL
    /// The image index read for ``info`` (2, the Setup image, or the last one).
    let bootWIMImage: Int
    private let device: String
    private let tools: DiskTools
    private var attached = true

    init(path: String, workDirectory: WorkDirectory, tools: DiskTools) throws {
        self.path = path
        self.tools = tools
        let fileSize: UInt64
        let label: String
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                throw InstallerError(phase: .openISO, kind: .invalidISO, message: "\(path) is not a Windows ISO: it is not a file.", path: path)
            }
            fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            label = try ISOImage.readVolumeLabel(path: path) ?? ""
        } catch let error as InstallerError {
            throw error
        } catch {
            let code = (error as NSError).underlyingErrors.first.map { ($0 as NSError).code }
                ?? ((error as NSError).domain == NSPOSIXErrorDomain ? (error as NSError).code : nil)
            let missing = code == Int(ENOENT) || (error as NSError).code == NSFileReadNoSuchFileError
            throw InstallerError(
                phase: .openISO, kind: missing ? .isoMissing : .io,
                message: missing ? "\(path) does not exist." : "\(path) cannot be read.",
                underlying: "\(error)", path: path, errno: code.map { Int32($0) }
            )
        }

        let mountPoint = workDirectory.url.appendingPathComponent("iso")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attachment: DiskTools.Attachment
        do {
            attachment = try tools.attachISO(path, at: mountPoint.path)
        } catch {
            throw InstallerError(
                phase: .openISO, kind: .invalidISO,
                message: "\(path) is not a Windows ISO: it could not be mounted.", underlying: "\(error)", path: path
            )
        }
        device = attachment.device
        self.mountPoint = URL(fileURLWithPath: attachment.mountPoint ?? mountPoint.path, isDirectory: true)

        do {
            guard let bootWIM = ISOImage.findItem(["sources", "boot.wim"], under: self.mountPoint) else {
                throw InstallerError(
                    phase: .openISO, kind: .invalidISO,
                    message: "\(path) is not a Windows ISO: sources/boot.wim is missing.", path: path
                )
            }
            self.bootWIM = bootWIM
            let wim: WIMFile
            let images: [WIMImage]
            do {
                wim = try WIMFile(path: bootWIM.path)
                images = try wim.images
            } catch {
                throw InstallerError(
                    phase: .openISO, kind: .invalidISO,
                    message: "\(path) is not a Windows ISO: sources/boot.wim cannot be read.", underlying: "\(error)", path: path
                )
            }
            defer { wim.close() }
            guard let setupImage = images.first(where: { $0.index == 2 }) ?? images.last, setupImage.build != nil else {
                throw InstallerError(
                    phase: .openISO, kind: .invalidISO,
                    message: "\(path) is not a Windows ISO: sources/boot.wim names no Windows build.", path: path
                )
            }
            bootWIMImage = setupImage.index
            // The release comes from the install image, as Rufus reads it (PopulateWindowsVersion):
            // boot.wim holds Windows PE, whose build can be older than the product's (an ISO of
            // build 26300 carries a 26100 boot.wim). boot.wim image 2 is the fallback. P6 named
            // boot.wim; the user chose the install image on 2026-09-30 after this was found.
            let image = ISOImage.installImage(under: self.mountPoint, log: tools.subprocess.log) ?? setupImage
            let build = image.build ?? setupImage.build!

            let estimate: Int64
            do {
                estimate = try NTFSVolume.estimatedVolumeSize(forTreeAt: self.mountPoint, clusterSize: NTFSLayout.clusterSize)
            } catch {
                throw InstallerError(
                    phase: .openISO, kind: .invalidISO,
                    message: "The files on \(path) cannot be copied to NTFS.", underlying: "\(error)", path: path
                )
            }
            info = ISOInfo(
                volumeLabel: label,
                fileSize: fileSize,
                windowsVersion: ISOInfo.windowsVersion(build: build, major: image.major),
                build: build,
                architecture: ISOInfo.architectureName(image.architecture),
                supportsCA2023: build >= ISOInfo.ca2023MinimumBuild,
                requiredBytes: ISOInfo.requiredBytes(forVolumeEstimate: UInt64(estimate))
            )
        } catch {
            tools.detach(attachment.device)
            throw error
        }
    }

    /// Detaches the ISO. Safe to call more than once.
    func close() {
        guard attached else {
            return
        }
        attached = false
        tools.detach(device)
    }

    deinit {
        close()
    }
}

/// Reading an ISO file directly, without mounting it.
enum ISOImage {
    static let sectorSize = 2048

    /// The volume identifier of the ISO 9660 primary volume descriptor, or `nil` if the file has
    /// none. Reads the descriptors from sector 16 on, stopping at the terminator.
    static func readVolumeLabel(path: String) throws -> String? {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        for sector in 16 ..< 64 {
            try handle.seek(toOffset: UInt64(sector * sectorSize))
            guard let data = try handle.read(upToCount: sectorSize), data.count == sectorSize else {
                return nil
            }
            let bytes = [UInt8](data)
            guard bytes[1 ..< 6].elementsEqual("CD001".utf8) else {
                return nil
            }
            if bytes[0] == 255 {
                return nil
            }
            if let label = parseVolumeLabel(primaryDescriptor: bytes) {
                return label
            }
        }
        return nil
    }

    /// The volume identifier (bytes 40..<72) of a primary volume descriptor (type 1, "CD001"),
    /// with trailing spaces and NULs removed. `nil` for any other sector.
    static func parseVolumeLabel(primaryDescriptor bytes: [UInt8]) -> String? {
        guard bytes.count >= 72, bytes[0] == 1, bytes[1 ..< 6].elementsEqual("CD001".utf8) else {
            return nil
        }
        var field = Array(bytes[40 ..< 72])
        while let last = field.last, last == 0x20 || last == 0 {
            field.removeLast()
        }
        return String(decoding: field, as: UTF8.self)
    }

    /// Image 1 of `sources/install.wim`, `install.esd` or `install.swm` (the first that exists),
    /// if it opens and names a build.
    static func installImage(under root: URL, log: (String) -> Void) -> WIMImage? {
        for name in ["install.wim", "install.esd", "install.swm"] {
            guard let url = findItem(["sources", name], under: root) else {
                continue
            }
            do {
                let wim = try WIMFile(path: url.path)
                defer { wim.close() }
                if let image = try wim.images.first, image.build != nil {
                    return image
                }
                log("sources/\(name) names no Windows build; using boot.wim")
            } catch {
                log("sources/\(name) cannot be read (\(error)); using boot.wim")
            }
            return nil
        }
        return nil
    }

    /// Finds `components` under `root`, matching each name ignoring case (ISO mounts may be
    /// case-sensitive, and Windows ISOs are not consistent about case). The result carries the
    /// names as they are stored; an exact match is preferred.
    static func findItem(_ components: [String], under root: URL) -> URL? {
        var current = root
        for component in components {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  let match = names.first(where: { $0 == component })
                  ?? names.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame })
            else {
                return nil
            }
            current.appendPathComponent(match)
        }
        return current
    }
}
