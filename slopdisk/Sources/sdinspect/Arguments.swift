//
//  Arguments.swift
//  sdinspect
//
//  Created by Gyuhwan Park on 9/30/26.
//

/// Command-line options. Parsed by hand; the package has no dependencies.
struct Arguments: Equatable {
    var sectorSize: Int?
    var hex = false
    var path: String

    static let usage = """
        usage: sdinspect [--sector-size 512|4096] [--hex] [--help] <image-path>

        Prints the protective MBR, both GPT headers (with CRC status), and the partition table of a disk image.
        The image is opened read-only.

          --sector-size N   Use N-byte sectors (512 or 4096) instead of detecting them.
          --hex             Append hex dumps of LBA 0, LBA 1, and the backup header sector.
          --help            Show this help.

        Exit status: 0 healthy GPT, no table, or MBR; 1 degraded GPT; 2 unrecoverable GPT;
                     64 usage error; 74 I/O error.
        """

    enum Outcome: Equatable {
        case run(Arguments)
        case help
        case usageError(String)
    }

    static func parse(_ arguments: [String]) -> Outcome {
        var sectorSize: Int?
        var hex = false
        var path: String?
        var index = 0
        var optionsEnded = false

        func setPath(_ value: String) -> String? {
            guard path == nil else {
                return "unexpected extra argument '\(value)'"
            }
            path = value
            return nil
        }

        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if optionsEnded || !argument.hasPrefix("-") || argument == "-" {
                if let error = setPath(argument) {
                    return .usageError(error)
                }
                continue
            }
            switch argument {
            case "--":
                optionsEnded = true
            case "--help", "-h":
                return .help
            case "--hex":
                hex = true
            case "--sector-size":
                guard index < arguments.count else {
                    return .usageError("--sector-size needs a value")
                }
                let value = arguments[index]
                index += 1
                guard let size = parseSectorSize(value) else {
                    return .usageError("invalid sector size '\(value)'; use 512 or 4096")
                }
                sectorSize = size
            default:
                if argument.hasPrefix("--sector-size=") {
                    let value = String(argument.dropFirst("--sector-size=".count))
                    guard let size = parseSectorSize(value) else {
                        return .usageError("invalid sector size '\(value)'; use 512 or 4096")
                    }
                    sectorSize = size
                } else {
                    return .usageError("unknown option '\(argument)'")
                }
            }
        }
        guard let path else {
            return .usageError("missing image path")
        }
        return .run(Arguments(sectorSize: sectorSize, hex: hex, path: path))
    }

    private static func parseSectorSize(_ value: String) -> Int? {
        switch value {
        case "512": 512
        case "4096": 4096
        default: nil
        }
    }
}
