// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// A snapshot of a host directory tree, taken with lstat(2) so that symbolic links are never
/// followed. Shared by copyTree and estimatedVolumeSize so that both apply the same rules.
struct SourceItem {
    enum Kind {
        case file(size: Int64)
        case directory(children: [SourceItem])
    }

    let name: String
    /// The path as built from the names readdir(3) returned, byte for byte.
    let path: String
    let kind: Kind
    let birthTime: timespec
    let modificationTime: timespec
}

enum SourceTree {
    /// The entries of the directory `root`, recursively, each directory's entries sorted by
    /// name (`String`'s `<`).
    ///
    /// Throws `.unsupportedFileType` for a symbolic link or special file anywhere in the tree,
    /// including `root` itself.
    static func scan(_ root: URL) throws -> [SourceItem] {
        let path = root.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw NTFS3GError.posix(operation: "lstat", path: path, errno: errno)
        }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return try scanDirectory(path)
        case S_IFREG:
            throw NTFS3GError.posix(operation: "opendir", path: path, errno: ENOTDIR)
        default:
            throw NTFS3GError.unsupportedFileType(root)
        }
    }

    private static func scanDirectory(_ path: String) throws -> [SourceItem] {
        var items: [SourceItem] = []
        for name in try entryNames(path).sorted() {
            let itemPath = path.hasSuffix("/") ? path + name : path + "/" + name
            var info = stat()
            guard lstat(itemPath, &info) == 0 else {
                throw NTFS3GError.posix(operation: "lstat", path: itemPath, errno: errno)
            }
            let kind: SourceItem.Kind
            switch info.st_mode & S_IFMT {
            case S_IFREG:
                kind = .file(size: Int64(info.st_size))
            case S_IFDIR:
                kind = .directory(children: try scanDirectory(itemPath))
            default:
                throw NTFS3GError.unsupportedFileType(URL(fileURLWithPath: itemPath))
            }
            items.append(SourceItem(
                name: name,
                path: itemPath,
                kind: kind,
                birthTime: info.st_birthtimespec,
                modificationTime: info.st_mtimespec
            ))
        }
        return items
    }

    /// The names in a directory, except `.` and `..`, exactly as the file system returns them.
    private static func entryNames(_ path: String) throws -> [String] {
        guard let directory = opendir(path) else {
            throw NTFS3GError.posix(operation: "opendir", path: path, errno: errno)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno != 0 {
                    throw NTFS3GError.posix(operation: "readdir", path: path, errno: errno)
                }
                return names
            }
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: &entry.pointee.d_name) {
                String(decoding: $0.prefix(length), as: UTF8.self)
            }
            if name != "." && name != ".." {
                names.append(name)
            }
        }
    }
}
