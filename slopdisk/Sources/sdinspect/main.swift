//
//  main.swift
//  sdinspect
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  Read-only inspection of a disk image's partition table structures.
//  Every open in this target uses `.readOnly`; no write path of SlopDisk may be reachable from here.
//

import Foundation
import SlopDisk

enum ExitStatus: Int32 {
    case ok = 0
    case degraded = 1
    case unrecoverable = 2
    case usage = 64
    case ioError = 74
}

func writeStandardError(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

func run(_ arguments: [String]) -> ExitStatus {
    let options: Arguments
    switch Arguments.parse(arguments) {
    case .help:
        print(Arguments.usage)
        return .ok
    case .usageError(let message):
        writeStandardError("sdinspect: \(message)\n\(Arguments.usage)\n")
        return .usage
    case .run(let parsed):
        options = parsed
    }

    let inspection: SDInspection
    do throws(SDError) {
        let sectorSize: Int
        if let requested = options.sectorSize {
            sectorSize = requested
        } else {
            sectorSize = try SDDiskImage.detectSectorSize(path: options.path)
        }
        let device = try SDFileBlockDevice(path: options.path, mode: .readOnly, sectorSize: sectorSize)
        inspection = try SDInspection.read(from: device)
    } catch {
        writeStandardError("sdinspect: \(options.path): \(describe(error))\n")
        if case .invalidArgument = error {
            return .usage
        }
        return .ioError
    }

    print(Report(inspection: inspection, includeHex: options.hex).render(), terminator: "")

    switch inspection.scheme {
    case .success(.gpt(.degraded)):
        return .degraded
    case .failure:
        return .unrecoverable
    case .success:
        return .ok
    }
}

func describe(_ error: SDError) -> String {
    switch error {
    case .io(let operation, let code):
        "\(operation): \(String(cString: strerror(code)))"
    case .locked:
        "locked by another process"
    case .invalidArgument(let message):
        message
    default:
        "\(error)"
    }
}

exit(run(Array(CommandLine.arguments.dropFirst())).rawValue)
