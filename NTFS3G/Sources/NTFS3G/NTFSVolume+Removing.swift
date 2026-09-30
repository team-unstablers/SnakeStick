// SPDX-License-Identifier: GPL-2.0-or-later

internal import CNTFS3G
import Foundation

extension NTFSVolume {
    /// Removes the file or empty directory `path`.
    ///
    /// Unlike the other methods, `path` is matched ignoring case, component by component, the
    /// way names are compared when items are created: `/EFI/Boot/BOOTX64.EFI` removes
    /// `/efi/boot/bootx64.efi`. A component that matches exactly is preferred.
    ///
    /// Throws ``NTFS3GError/directoryNotEmpty(_:)`` for a directory that has entries, and
    /// ``NTFS3GError/invalidPath(_:)`` for `/`. NTFS metadata files such as `$MFT`, and
    /// everything in `$Extend`, cannot be removed: they throw
    /// ``NTFS3GError/posix(operation:path:errno:)`` with `EPERM`, as the ntfs-3g driver does.
    public func removeItem(_ path: String) throws {
        let volume = try requireWritableVolume()
        let target = try NTFSPath(path)
        guard !target.isRoot else {
            throw NTFS3GError.invalidPath(path)
        }
        let name = try NTFSName(target.name!)

        // The metadata files, $Extend included, are all entries of the root directory, so the
        // first component decides. The check uses the MFT reference so that no metadata inode
        // is ever opened here.
        let top = try withInode(.root, in: volume) { root in
            try lookUpChild(named: target.components[0], in: root, path: target.prefix(1), ignoringCase: true)
        }
        guard cntfs3g_is_metadata(top) == 0 else {
            throw NTFS3GError.posix(operation: "remove", path: target.string, errno: EPERM)
        }

        let parent = try openDirectory(target.parent, in: volume, ignoringCase: true)
        let item: Inode
        do {
            item = try openChild(named: target.name!, in: parent, path: target, ignoringCase: true)
        } catch {
            ntfs_inode_close(parent)
            throw error
        }
        // Closes item and parent, whether or not it succeeds.
        guard cntfs3g_delete_ignoring_case(item, parent, name.characters, UInt8(name.length)) == 0 else {
            let code = errno
            if code == ENOTEMPTY {
                throw NTFS3GError.directoryNotEmpty(target.string)
            }
            throw NTFS3GError.posix(operation: "remove", path: target.string, errno: code)
        }
    }
}
