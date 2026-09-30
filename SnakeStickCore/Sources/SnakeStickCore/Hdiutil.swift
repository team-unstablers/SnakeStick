import Foundation

/// `hdiutil` and `diskutil` invocations shared by the pipeline and `inspectISO`.
struct DiskTools {
    let subprocess: Subprocess

    init(log: @escaping @Sendable (String) -> Void) {
        subprocess = Subprocess(log: log)
    }

    struct Attachment {
        /// The whole-disk node, `/dev/diskN`.
        var device: String
        /// Where the file system was mounted, if it was.
        var mountPoint: String?
    }

    /// Mounts an ISO read-only at `mountPoint`, hidden from the Finder (P3).
    func attachISO(_ path: String, at mountPoint: String) throws -> Attachment {
        let output = try subprocess.run(
            "/usr/bin/hdiutil",
            ["attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", "-mountpoint", mountPoint, path]
        )
        guard output.status == 0 else {
            throw DiskToolError.failed("hdiutil attach", output.stderrText)
        }
        let attachment = try Self.parseAttachment(output.stdout)
        guard attachment.mountPoint != nil else {
            // Attached but nothing mounted: detach again before reporting.
            detach(attachment.device)
            throw DiskToolError.failed("hdiutil attach", "no file system was mounted")
        }
        return attachment
    }

    /// Attaches a raw image without mounting anything (C5, C20).
    func attachRawImage(_ path: String) throws -> Attachment {
        let output = try subprocess.run(
            "/usr/bin/hdiutil",
            ["attach", "-nomount", "-imagekey", "diskimage-class=CRawDiskImage", "-plist", path]
        )
        guard output.status == 0 else {
            throw DiskToolError.failed("hdiutil attach", output.stderrText)
        }
        return try Self.parseAttachment(output.stdout)
    }

    /// Detaches `device` (`/dev/diskN` or a mount point). Retries three times one second apart
    /// when it is busy, then forces it (§11). Returns whether it succeeded; failures are logged.
    @discardableResult
    func detach(_ device: String) -> Bool {
        for attempt in 0 ..< 4 {
            var arguments = ["detach", device]
            if attempt == 3 {
                arguments.append("-force")
            }
            guard let output = try? subprocess.run("/usr/bin/hdiutil", arguments) else {
                return false
            }
            if output.status == 0 {
                return true
            }
            if attempt < 3 {
                Thread.sleep(forTimeInterval: 1)
            }
        }
        return false
    }

    /// `diskutil unmount [force]` with the same retries as ``detach(_:)``.
    @discardableResult
    func unmount(_ target: String) -> Bool {
        for attempt in 0 ..< 4 {
            let arguments = attempt == 3 ? ["unmount", "force", target] : ["unmount", target]
            guard let output = try? subprocess.run("/usr/sbin/diskutil", arguments) else {
                return false
            }
            if output.status == 0 {
                return true
            }
            if attempt < 3 {
                Thread.sleep(forTimeInterval: 1)
            }
        }
        return false
    }

    /// Picks the whole-disk entry and the mount point from `hdiutil attach -plist` output. The
    /// whole disk is the entry whose `dev-entry` is `/dev/diskN`, whatever its position or
    /// content hint (C26).
    static func parseAttachment(_ plist: Data) throws -> Attachment {
        var data = plist
        if let start = data.range(of: Data("<?xml".utf8))?.lowerBound, start > data.startIndex {
            data = data[start...]
        }
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]]
        else {
            throw DiskToolError.failed("hdiutil attach", "unreadable plist output")
        }
        let wholePattern = #/^/dev/disk[0-9]+$/#
        let devices = entities.compactMap { $0["dev-entry"] as? String }
        guard let whole = devices.first(where: { $0.wholeMatch(of: wholePattern) != nil }) else {
            throw DiskToolError.failed("hdiutil attach", "no whole-disk entry in \(devices)")
        }
        let mountPoint = entities.lazy.compactMap { $0["mount-point"] as? String }.first
        return Attachment(device: whole, mountPoint: mountPoint)
    }
}

enum DiskToolError: Error, CustomStringConvertible {
    case failed(String, String)

    var description: String {
        switch self {
        case .failed(let command, let reason): "\(command) failed: \(reason)"
        }
    }
}
