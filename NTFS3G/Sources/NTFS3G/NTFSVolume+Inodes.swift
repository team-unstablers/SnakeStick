// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Darwin

/// Inode plumbing shared by the public operations.
///
/// libntfs-3g keeps one in-memory instance per open inode and does not detect a second
/// ntfs_inode_open of the same inode, so an inode is never opened twice at a time here: path
/// walks close each directory as soon as its child is open, and a new item is closed with
/// ntfs_inode_close_in_dir while its parent stays open.
extension NTFSVolume {
    typealias Inode = UnsafeMutablePointer<ntfs_inode>

    static let lookupFailed = UInt64.max

    /// Opens the inode at `path`. The caller closes it with ntfs_inode_close.
    ///
    /// Throws `.notFound` or `.notADirectory` naming the first component that does not exist
    /// or is not a directory. Lookups are case-sensitive.
    func openInode(_ path: NTFSPath, in volume: UnsafeMutablePointer<ntfs_volume>) throws -> Inode {
        guard var current = ntfs_inode_open(volume, MFT_REF(FILE_root.rawValue)) else {
            throw NTFS3GError.posix(operation: "open inode", path: "/", errno: errno)
        }
        for (index, component) in path.components.enumerated() {
            let child: Inode
            do {
                guard cntfs3g_inode_is_directory(current) != 0 else {
                    throw NTFS3GError.notADirectory(path.prefix(index).string)
                }
                child = try openChild(named: component, in: current, path: path.prefix(index + 1))
            } catch {
                ntfs_inode_close(current)
                throw error
            }
            ntfs_inode_close(current)
            current = child
        }
        return current
    }

    /// Opens the directory at `path`. The caller closes it with ntfs_inode_close.
    func openDirectory(_ path: NTFSPath, in volume: UnsafeMutablePointer<ntfs_volume>) throws -> Inode {
        let inode = try openInode(path, in: volume)
        guard cntfs3g_inode_is_directory(inode) != 0 else {
            ntfs_inode_close(inode)
            throw NTFS3GError.notADirectory(path.string)
        }
        return inode
    }

    private func openChild(named component: String, in directory: Inode, path: NTFSPath) throws -> Inode {
        let name = try NTFSName(component)
        let reference = ntfs_inode_lookup_by_name(directory, name.characters, Int32(name.length))
        guard reference != Self.lookupFailed else {
            let code = errno
            if code == ENOENT {
                throw NTFS3GError.notFound(path.string)
            }
            throw NTFS3GError.posix(operation: "lookup", path: path.string, errno: code)
        }
        guard let child = ntfs_inode_open(directory.pointee.vol, reference) else {
            throw NTFS3GError.posix(operation: "open inode", path: path.string, errno: errno)
        }
        return child
    }

    /// Runs `body` with the directory at `path` open, then closes it and reports a failure to
    /// flush it.
    func withDirectory<Result>(
        _ path: NTFSPath,
        in volume: UnsafeMutablePointer<ntfs_volume>,
        _ body: (Inode) throws -> Result
    ) throws -> Result {
        let directory = try openDirectory(path, in: volume)
        let result: Result
        do {
            result = try body(directory)
        } catch {
            ntfs_inode_close(directory)
            throw error
        }
        guard ntfs_inode_close(directory) == 0 else {
            throw NTFS3GError.posix(operation: "close", path: path.string, errno: errno)
        }
        return result
    }

    /// Runs `body` with the inode at `path` open, then closes it.
    func withInode<Result>(
        _ path: NTFSPath,
        in volume: UnsafeMutablePointer<ntfs_volume>,
        _ body: (Inode) throws -> Result
    ) throws -> Result {
        let inode = try openInode(path, in: volume)
        defer { ntfs_inode_close(inode) }
        return try body(inode)
    }

    /// Converts `name` and checks that Windows can use it: no forbidden characters, no trailing
    /// dot or space, not a reserved device name such as CON.
    func validatedName(_ name: String, in volume: UnsafeMutablePointer<ntfs_volume>) throws(NTFS3GError) -> NTFSName {
        let ntfsName = try NTFSName(name)
        guard !ntfs_forbidden_names(volume, ntfsName.characters, Int32(ntfsName.length), .true).isTrue else {
            throw .invalidName(name)
        }
        return ntfsName
    }

    /// Creates the file or directory `path`, whose parent `parent` is open, runs `body` with it,
    /// sets `times` if given, and closes it.
    ///
    /// The times are set last because creating children and writing data change them.
    /// Throws `.alreadyExists` if the parent has an entry whose name equals the new one when
    /// case is ignored: Windows could not tell the two apart.
    func createItem(
        _ path: NTFSPath,
        kind: NTFSItemKind,
        in parent: Inode,
        times: NTFSTicks?,
        _ body: (Inode) throws -> Void
    ) throws {
        let volume = parent.pointee.vol!
        let name = try validatedName(path.name!, in: volume)

        let existing = cntfs3g_lookup_ignoring_case(parent, name.characters, Int32(name.length))
        guard existing == Self.lookupFailed else {
            throw NTFS3GError.alreadyExists(path.string)
        }
        guard errno == ENOENT else {
            throw NTFS3GError.posix(operation: "lookup", path: path.string, errno: errno)
        }

        let type = switch kind {
        case .file: S_IFREG
        case .directory: S_IFDIR
        }
        guard let inode = ntfs_create(parent, 0, name.characters, UInt8(name.length), type) else {
            throw NTFS3GError.posix(operation: "create", path: path.string, errno: errno)
        }

        do {
            try body(inode)
            if let times {
                try setTimes(times, on: inode, path: path)
            }
        } catch {
            if ntfs_inode_close_in_dir(inode, parent) != 0 {
                ntfs_inode_close(inode)
            }
            throw error
        }
        guard ntfs_inode_close_in_dir(inode, parent) == 0 else {
            let code = errno
            ntfs_inode_close(inode)
            throw NTFS3GError.posix(operation: "close", path: path.string, errno: code)
        }
    }

    private func setTimes(_ times: NTFSTicks, on inode: Inode, path: NTFSPath) throws {
        // {creation, last data change, last access} in host byte order. The MFT change time
        // is always set to the current time by libntfs-3g.
        let values = [times.creation, times.modification, times.access]
        let result = values.withUnsafeBytes {
            ntfs_inode_set_times(inode, $0.baseAddress!.assumingMemoryBound(to: CChar.self), $0.count, 0)
        }
        guard result == 0 else {
            throw NTFS3GError.posix(operation: "setTimes", path: path.string, errno: errno)
        }
    }
}

/// File times in NTFS units (100 ns since 1601-01-01 UTC).
struct NTFSTicks {
    var creation: UInt64
    var modification: UInt64
    var access: UInt64
}

extension NTFSTicks {
    /// Converts `times`, throwing `.posix(operation: "setTimes", path:, errno: EINVAL)` for
    /// dates NTFS cannot store.
    init(_ times: NTFSFileTimes, path: String) throws(NTFS3GError) {
        guard let creation = NTFSTime.ticks(from: times.creation),
              let modification = NTFSTime.ticks(from: times.modification),
              let access = NTFSTime.ticks(from: times.access)
        else {
            throw .posix(operation: "setTimes", path: path, errno: EINVAL)
        }
        self.init(creation: creation, modification: modification, access: access)
    }
}
