//
//  Report.swift
//  sdinspect
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation
import SlopDisk

/// Renders an `SDInspection` as text. Everything printed comes from the inspection; nothing is re-read.
struct Report {
    let inspection: SDInspection
    let includeHex: Bool

    func render() -> String {
        var lines: [String] = []
        lines.append(field("scheme", schemeText))
        lines.append(field("sector size", "\(inspection.sectorSize)   sectors: \(inspection.sectorCount) (\(diskSize))"))
        lines.append(field("disk GUID", diskGUIDText))
        lines.append(field("primary hdr", headerText(inspection.primary, examinedLBA: primaryLBA)))
        lines.append(field("backup  hdr", headerText(inspection.backup, examinedLBA: backupLBA)))
        lines.append(field("usable", usableText))
        lines.append(field("pmbr", mbrKindText))

        if case .success(.gpt) = inspection.scheme {
            lines.append(contentsOf: partitionTable())
        }
        if inspection.mbr.kind == .mbr || inspection.mbr.kind == .hybrid {
            lines.append(contentsOf: mbrTable())
        }
        if includeHex {
            for sector in inspection.rawSectors {
                lines.append("")
                lines.append("LBA \(sector.lba) (\(sector.bytes.count) bytes)")
                lines.append(contentsOf: HexDump.lines(sector.bytes))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Summary fields

    private func field(_ name: String, _ value: String) -> String {
        name.padding(12) + ": " + value
    }

    private var schemeText: String {
        switch inspection.scheme {
        case .success(.gpt(.healthy)):
            "GPT (healthy)"
        case .success(.gpt(.degraded(let issues))):
            "GPT (degraded: \(issues.sorted(by: { $0.order < $1.order }).map(\.name).joined(separator: ", ")))"
        case .success(.none):
            "NONE"
        case .success(.mbr):
            "MBR"
        case .failure(.gptUnrecoverable):
            "GPT UNRECOVERABLE"
        case .failure(let error):
            "ERROR (\(error))"
        }
    }

    private var diskSize: SDSize {
        let (bytes, overflow) = inspection.sectorCount.multipliedReportingOverflow(by: UInt64(inspection.sectorSize))
        return SDSize(bytes: overflow ? .max : bytes)
    }

    private var diskGUIDText: String {
        if let diskID = inspection.diskID {
            return diskID.uuidString
        }
        // No adopted copy: show what the headers claim, if anything.
        let claimed = Set([inspection.primary?.diskGUID, inspection.backup?.diskGUID].compactMap { $0 })
        if claimed.isEmpty {
            return "-"
        }
        return claimed.map(\.uuidString).sorted().joined(separator: " / ") + " (not adopted)"
    }

    private var primaryLBA: UInt64? {
        inspection.rawSectors.first { $0.lba == 1 }?.lba
    }

    private var backupLBA: UInt64? {
        inspection.rawSectors.first { $0.lba > 1 }?.lba
    }

    private func headerText(_ report: SDInspection.HeaderReport?, examinedLBA: UInt64?) -> String {
        guard let examinedLBA else {
            return "not examined"
        }
        let location = "LBA \(examinedLBA)".padding(11)
        guard let report else {
            return location + "missing (no EFI PART signature)"
        }
        var parts: [String] = []
        switch report.damage {
        case nil, .fields?:
            parts.append("header crc OK")
        case .headerCRC?:
            if report.storedHeaderCRC == report.computedHeaderCRC {
                parts.append("header size BAD(\(report.headerSize))")
            } else {
                parts.append("header crc BAD(\(hex(report.storedHeaderCRC))/\(hex(report.computedHeaderCRC)))")
            }
        case .signature?:
            parts.append("missing (no EFI PART signature)")
        }
        if report.damage == .fields {
            parts.append("fields INVALID")
        }
        // Fields of a damaged header can hold anything, so the end LBA is computed without trapping on overflow.
        let entrySectors = report.entryArraySectorCount
        let (entryEnd, overflow) = report.partitionEntryLBA.addingReportingOverflow(entrySectors)
        if entrySectors == 0 {
            parts.append("entries none")
        } else if overflow {
            parts.append("entries LBA \(report.partitionEntryLBA)..(overflow)")
        } else {
            parts.append("entries LBA \(report.partitionEntryLBA)..\(entryEnd - 1)")
        }
        if let computed = report.computedEntriesCRC {
            parts.append(computed == report.storedEntriesCRC
                ? "crc OK"
                : "crc BAD(\(hex(report.storedEntriesCRC))/\(hex(computed)))")
        } else {
            parts.append("crc not checked")
        }
        return location + parts.joined(separator: "  ")
    }

    private var usableText: String {
        let report: SDInspection.HeaderReport? = switch inspection.adoptedCopy {
        case .primary?: inspection.primary
        case .backup?: inspection.backup
        case nil: nil
        }
        guard let report else {
            return "-"
        }
        return "LBA \(report.firstUsableLBA) .. \(report.lastUsableLBA)"
    }

    private var mbrKindText: String {
        switch inspection.mbr.kind {
        case .protective: "protective"
        case .hybrid: "hybrid"
        case .mbr: "mbr"
        case .missing: "missing"
        }
    }

    // MARK: - Tables

    private func partitionTable() -> [String] {
        guard !inspection.partitions.isEmpty else {
            return ["(no partitions)"]
        }
        let header = ["#", "begin", "end", "size", "type", "attrs", "label"]
        let rows = inspection.partitions.map { partition in
            [
                "\(partition.index)",
                "\(partition.begin)",
                "\(partition.end)",
                partition.size.description,
                partition.type.description,
                attributesText(partition.attributes),
                partition.label,
            ]
        }
        return Self.table(header: header, rows: rows, rightAligned: [0])
    }

    private func mbrTable() -> [String] {
        let header = ["#", "boot", "type", "first LBA", "sectors"]
        let rows = inspection.mbr.entries
            .filter { $0.type != 0 || $0.firstLBA != 0 || $0.sectorCount != 0 || $0.isBootable }
            .map { entry in
                [
                    "\(entry.index)",
                    entry.isBootable ? "*" : "-",
                    "0x" + hexDigits(UInt64(entry.type), width: 2),
                    "\(entry.firstLBA)",
                    "\(entry.sectorCount)",
                ]
            }
        guard !rows.isEmpty else {
            return []
        }
        return ["", "MBR entries:"] + Self.table(header: header, rows: rows, rightAligned: [0])
    }

    private func attributesText(_ attributes: SDPartitionAttributes) -> String {
        guard !attributes.isEmpty else {
            return "-"
        }
        let known: [(SDPartitionAttributes, String)] = [
            (.requiredPartition, "required"),
            (.noBlockIOProtocol, "noblockio"),
            (.legacyBIOSBootable, "legacyboot"),
            (.msReadOnly, "readonly"),
            (.msShadowCopy, "shadowcopy"),
            (.msHidden, "hidden"),
            (.msNoDriveLetter, "nodriveletter"),
        ]
        var remaining = attributes
        var names: [String] = []
        for (flag, name) in known where attributes.contains(flag) {
            names.append(name)
            remaining.remove(flag)
        }
        if !remaining.isEmpty {
            names.append("0x" + hexDigits(remaining.rawValue, width: 16))
        }
        return names.joined(separator: ",")
    }

    /// Left-aligned columns separated by two spaces; the last column is not padded.
    private static func table(header: [String], rows: [[String]], rightAligned: Set<Int>) -> [String] {
        let all = [header] + rows
        let widths = (0 ..< header.count).map { column in
            all.map { $0[column].count }.max() ?? 0
        }
        return all.map { row in
            var cells: [String] = []
            for (column, cell) in row.enumerated() {
                if column == row.count - 1 {
                    cells.append(cell)
                } else if rightAligned.contains(column) {
                    cells.append(String(repeating: " ", count: widths[column] - cell.count) + cell)
                } else {
                    cells.append(cell.padding(widths[column]))
                }
            }
            return " " + cells.joined(separator: "  ")
        }
    }

    private func hex(_ value: UInt32) -> String {
        "0x" + hexDigits(UInt64(value), width: 8)
    }
}

func hexDigits(_ value: UInt64, width: Int) -> String {
    let digits = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
}

extension String {
    /// Pads with spaces on the right to at least `width` characters.
    func padding(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}

extension SDGPTIssue {
    /// Declaration order, for stable output.
    var order: Int {
        switch self {
        case .primaryHeaderInvalid: 0
        case .primaryEntriesCRCMismatch: 1
        case .backupHeaderInvalid: 2
        case .backupEntriesCRCMismatch: 3
        case .backupNotAtEndOfDisk: 4
        case .protectiveMBRMissing: 5
        case .hybridMBR: 6
        case .copiesDiffer: 7
        case .invalidEntries: 8
        }
    }

    var name: String {
        switch self {
        case .primaryHeaderInvalid(let damage): "primaryHeaderInvalid(\(damage.name))"
        case .primaryEntriesCRCMismatch: "primaryEntriesCRCMismatch"
        case .backupHeaderInvalid(let damage): "backupHeaderInvalid(\(damage.name))"
        case .backupEntriesCRCMismatch: "backupEntriesCRCMismatch"
        case .backupNotAtEndOfDisk: "backupNotAtEndOfDisk"
        case .protectiveMBRMissing: "protectiveMBRMissing"
        case .hybridMBR: "hybridMBR"
        case .copiesDiffer: "copiesDiffer"
        case .invalidEntries: "invalidEntries"
        }
    }
}

extension SDGPTHeaderDamage {
    var name: String {
        switch self {
        case .signature: "signature"
        case .headerCRC: "headerCRC"
        case .fields: "fields"
        }
    }
}
