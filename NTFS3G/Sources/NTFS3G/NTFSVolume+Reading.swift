// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Foundation

extension NTFSVolume {
    /// The files and directories in the directory `path`, sorted by name (`String`'s `<`).
    ///
    /// `.` and `..`, NTFS metadata files such as `$MFT`, and DOS 8.3 alias names are left out.
    /// Names are returned exactly as stored, without Unicode normalization.
    public func contentsOfDirectory(_ path: String) throws -> [NTFSDirectoryEntry] {
        let volume = try requireVolume()
        let target = try NTFSPath(path)
        return try withInode(target, in: volume) { inode in
            guard cntfs3g_inode_is_directory(inode) != 0 else {
                throw NTFS3GError.notADirectory(target.string)
            }
            let collector = DirectoryCollector()
            var position: s64 = 0
            let result = withExtendedLifetime(collector) {
                ntfs_readdir(inode, &position, Unmanaged.passUnretained(collector).toOpaque(), collectDirectoryEntry)
            }
            guard result == 0 else {
                throw NTFS3GError.posix(operation: "readdir", path: target.string, errno: errno)
            }
            return collector.entries.sorted { $0.name < $1.name }
        }
    }

    /// The kind, size and times of the item at `path`. The size of a directory is 0.
    public func attributesOfItem(_ path: String) throws -> NTFSItemAttributes {
        let volume = try requireVolume()
        let target = try NTFSPath(path)
        return try withInode(target, in: volume) { inode in
            var ticks: [UInt64] = [0, 0, 0]
            ticks.withUnsafeMutableBufferPointer { cntfs3g_inode_get_times(inode, $0.baseAddress) }
            let times = NTFSFileTimes(
                creation: NTFSTime.date(fromTicks: ticks[0]),
                modification: NTFSTime.date(fromTicks: ticks[1]),
                access: NTFSTime.date(fromTicks: ticks[2])
            )
            guard cntfs3g_inode_is_directory(inode) == 0 else {
                return NTFSItemAttributes(kind: .directory, size: 0, times: times)
            }
            let size = try withDataAttribute(of: inode, path: target) { $0.pointee.data_size }
            return NTFSItemAttributes(kind: .file, size: size, times: times)
        }
    }

    /// Reads up to `buffer.count` bytes of the file `path`, starting at byte `offset`. Returns
    /// the number of bytes read, which is 0 at or past the end of the file.
    public func readFile(_ path: String, into buffer: UnsafeMutableRawBufferPointer, at offset: Int64) throws -> Int {
        let volume = try requireVolume()
        let target = try NTFSPath(path)
        guard offset >= 0 else {
            throw NTFS3GError.posix(operation: "read", path: target.string, errno: EINVAL)
        }
        return try withInode(target, in: volume) { inode in
            guard cntfs3g_inode_is_directory(inode) == 0 else {
                throw NTFS3GError.isADirectory(target.string)
            }
            return try withDataAttribute(of: inode, path: target) { attribute in
                let size = attribute.pointee.data_size
                guard offset < size, let base = buffer.baseAddress else {
                    return 0
                }
                // ntfs_attr_pread may read less than asked.
                let wanted = Int(min(Int64(buffer.count), size - offset))
                var done = 0
                while done < wanted {
                    let count = ntfs_attr_pread(attribute, offset + Int64(done), s64(wanted - done), base + done)
                    guard count > 0 else {
                        throw NTFS3GError.posix(operation: "read", path: target.string, errno: count < 0 ? errno : EIO)
                    }
                    done += Int(count)
                }
                return done
            }
        }
    }
}

private final class DirectoryCollector {
    var entries: [NTFSDirectoryEntry] = []
}

/// ntfs_filldir_t callback for ntfs_readdir.
private let collectDirectoryEntry: ntfs_filldir_t = { context, name, nameLength, nameType, _, reference, type in
    guard let context, let name else {
        return 0
    }
    // A name that also has a separate DOS 8.3 entry is reported twice; skip the alias.
    guard UInt32(nameType) != UInt32(FILE_NAME_DOS.rawValue), cntfs3g_is_metadata(reference) == 0 else {
        return 0
    }
    // NTFS stores names as little-endian UTF-16, which is the host order on macOS.
    let string = String(decoding: UnsafeBufferPointer(start: name, count: Int(nameLength)), as: UTF16.self)
    guard string != ".", string != ".." else {
        return 0
    }
    let kind: NTFSItemKind = type == NTFS_DT_DIR ? .directory : .file
    let collector = Unmanaged<DirectoryCollector>.fromOpaque(context).takeUnretainedValue()
    collector.entries.append(NTFSDirectoryEntry(name: string, kind: kind))
    return 0
}
