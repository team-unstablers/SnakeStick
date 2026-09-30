// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

extension NTFSVolume {
    /// A conservative upper bound on the size of a volume that, formatted with `clusterSize`,
    /// can hold the contents of the host directory `source` copied by
    /// ``copyTree(from:to:progress:)`` into its root. A multiple of 1 MiB.
    ///
    /// The source is scanned with the same rules as `copyTree`: symbolic links and special
    /// files throw ``NTFS3GError/unsupportedFileType(_:)``. Names are not checked.
    ///
    /// The bound holds for both 512- and 4096-byte sectors. It is the sum of:
    /// - file data, each file rounded up to whole clusters (small files that NTFS stores inside
    ///   their MFT record are counted as a full cluster anyway);
    /// - one 4 KiB MFT record per file and directory (1 KiB with 512-byte sectors, 4 KiB with
    ///   4096-byte sectors), plus 16 records of slack because the MFT grows 16 records at a
    ///   time;
    /// - for each non-empty directory, three times the size of its index entries plus one
    ///   index block, rounded up to the allocation unit (B+tree nodes can be half empty);
    /// - the empty volume's fixed metadata, measured at 435–896 KiB depending on cluster size
    ///   and bounded here by 1 MiB + 8 clusters;
    /// - `$LogFile`, which mkntfs sizes from the volume (2 MiB below 200 MiB, 1/200 of the
    ///   volume up to 12 GiB, 64 MiB from there), and the cluster bitmap, both computed for the
    ///   resulting volume size by iterating to a fixed point;
    /// - one cluster at the end for the backup boot sector;
    /// - a margin of 4 MiB plus 1/512 of the file data.
    public static func estimatedVolumeSize(forTreeAt source: URL, clusterSize: Int = 4096) throws -> Int64 {
        let items = try SourceTree.scan(source)
        let cluster = Int64(clusterSize)
        guard cluster > 0, cluster & (cluster - 1) == 0 else {
            throw NTFS3GError.posix(operation: "estimatedVolumeSize", path: nil, errno: EINVAL)
        }

        var tally = EstimateTally(cluster: cluster)
        tally.addDirectory(items)

        let fixed = tally.dataBytes
            + tally.recordBytes
            + 16 * EstimateTally.recordSize
            + tally.indexBytes
            + (1 << 20) + 8 * cluster  // empty-volume metadata other than $LogFile and $Bitmap
            + cluster                  // backup boot sector
            + (4 << 20) + tally.dataBytes / 512

        // $LogFile and $Bitmap grow with the volume; both bounds are non-decreasing, so this
        // reaches a fixed point after a few rounds.
        var size = roundUp(fixed, to: 1 << 20)
        while true {
            let next = roundUp(fixed + logFileBound(forVolumeSize: size) + bitmapBytes(forVolumeSize: size, cluster: cluster), to: 1 << 20)
            if next <= size {
                return size
            }
            size = next
        }
    }

    /// An upper bound on the $LogFile size mkntfs picks for a volume of `size` bytes (see
    /// mkntfs_initialize_rl_logfile), non-decreasing in `size`.
    private static func logFileBound(forVolumeSize size: Int64) -> Int64 {
        if size >= 12 << 30 {
            return 64 << 20
        }
        return max(2 << 20, (size + 199) / 200)
    }

    /// The clusters taken by $Bitmap: one bit per cluster, in 8-byte units.
    private static func bitmapBytes(forVolumeSize size: Int64, cluster: Int64) -> Int64 {
        let clusters = (size + cluster - 1) / cluster
        return roundUp(roundUp((clusters + 7) / 8, to: 8), to: cluster)
    }
}

private struct EstimateTally {
    /// The largest MFT record: mkntfs uses max(1024, sector size).
    static let recordSize: Int64 = 4096
    /// The largest index block: mkntfs uses max(4096, sector size).
    static let indexBlockSize: Int64 = 4096

    let cluster: Int64
    var dataBytes: Int64 = 0
    var recordBytes: Int64 = 0
    var indexBytes: Int64 = 0

    init(cluster: Int64) {
        self.cluster = cluster
    }

    /// Adds the index of a directory holding `items`, and the items themselves.
    mutating func addDirectory(_ items: [SourceItem]) {
        guard !items.isEmpty else {
            return
        }
        var entries: Int64 = 0
        for item in items {
            // INDEX_ENTRY header (16) + FILE_NAME attribute (66) + the UTF-16 name, 8-aligned.
            entries += roundUp(16 + 66 + 2 * Int64(item.name.utf16.count), to: 8)
            recordBytes += Self.recordSize
            switch item.kind {
            case .file(let size):
                dataBytes += roundUp(size, to: cluster)
            case .directory(let children):
                addDirectory(children)
            }
        }
        indexBytes += roundUp(3 * entries + Self.indexBlockSize, to: max(cluster, Self.indexBlockSize))
    }
}

private func roundUp(_ value: Int64, to unit: Int64) -> Int64 {
    (value + unit - 1) / unit * unit
}
