// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SnakeStickCore

/// Exit codes (P20, sysexits.h).
enum ExitCode: Int32 {
    case success = 0
    /// The user declined the confirmation; nothing was written.
    case declined = 1
    case usage = 64
    case invalidISO = 65
    case noInput = 66
    case unavailable = 69
    case software = 70
    case cannotCreate = 73
    case io = 74
    case noPermission = 77
    case interrupted = 130

    init(for error: InstallerError) {
        self = switch error.kind {
        case .usage: .usage
        case .isoMissing: .noInput
        case .invalidISO: .invalidISO
        case .rootRequired: .noPermission
        case .targetIneligible, .insufficientSpace: .unavailable
        case .targetExists: .cannotCreate
        case .io, .verificationFailed: .io
        case .cancelled: .interrupted
        case .other: .software
        }
    }
}

struct UsageError: Error, Equatable, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

struct WriteOptions: Equatable {
    var label: String?
    var verify = true
    var ca2023 = false
    var verbose = false

    var installerOptions: InstallerOptions {
        InstallerOptions(volumeLabel: label, verifyAfterWrite: verify, useCA2023Bootloaders: ca2023)
    }
}

enum Command: Equatable {
    case help
    case make(iso: String, disk: String, options: WriteOptions, assumeYes: Bool)
    case build(iso: String, output: String, imageSize: UInt64?, options: WriteOptions)
    case disks
    case info(iso: String)
    /// Internal: run one job for the app over the socket at `socket` (stage 20).
    case ipc(socket: String)
}

enum Arguments {
    static let usage = """
        usage: snakestick make  [--label LABEL] [--no-verify] [--ca-2023] [--yes] [--verbose] ISO DISK
               snakestick build [--label LABEL] [--no-verify] [--ca-2023] [--imgsize SIZE] [--verbose] -o IMAGE ISO
               snakestick disks
               snakestick info ISO

        make    writes the Windows installer in ISO to DISK (disk4, /dev/disk4 or /dev/rdisk4). Needs root.
        build   writes it to a new raw disk image IMAGE instead. SIZE uses SI units: 8G is 8,000,000,000
                bytes. By default the image is as small as the ISO allows.
        disks   lists the disks make can write to, and why the others are left out.
        info    shows what SnakeStick reads from ISO.

        --label LABEL   NTFS volume label (default: the ISO's label)
        --no-verify     do not read the NTFS volume back and compare it with the ISO
        --ca-2023       use the Windows UEFI CA 2023 signed boot loaders (Windows 11 25H2 or later)
        --yes           do not ask for the disk name before erasing it
        --verbose       print every step and external command to stderr
        """

    static func parse(_ arguments: [String]) throws(UsageError) -> Command {
        guard let subcommand = arguments.first else {
            throw UsageError("missing subcommand")
        }
        if ["-h", "--help", "help"].contains(subcommand) {
            return .help
        }
        var options = WriteOptions()
        var assumeYes = false
        var imageSize: UInt64?
        var output: String?
        var socket: String?
        var positional: [String] = []
        let allowed: Set<String> = switch subcommand {
        case "make": ["--label", "--no-verify", "--ca-2023", "--yes", "--verbose"]
        case "build": ["--label", "--no-verify", "--ca-2023", "--imgsize", "--verbose", "-o"]
        case "disks", "info": []
        case "ipc": ["--socket"]
        default: throw UsageError("unknown subcommand '\(subcommand)'")
        }

        var index = 1
        var onlyPositional = false
        func value(for option: String, inline: String?) throws(UsageError) -> String {
            if let inline {
                return inline
            }
            index += 1
            guard index < arguments.count else {
                throw UsageError("\(option) needs a value")
            }
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            if onlyPositional || !argument.hasPrefix("-") || argument == "-" {
                positional.append(argument)
                index += 1
                continue
            }
            if argument == "--" {
                onlyPositional = true
                index += 1
                continue
            }
            let parts = argument.split(separator: "=", maxSplits: 1).map(String.init)
            let name = parts[0]
            let inline = parts.count == 2 ? parts[1] : nil
            guard allowed.contains(name) else {
                throw UsageError("unknown option '\(name)' for \(subcommand)")
            }
            switch name {
            case "--label":
                options.label = try value(for: name, inline: inline)
            case "--imgsize":
                let text = try value(for: name, inline: inline)
                guard let size = SISize.parse(text) else {
                    throw UsageError("--imgsize: '\(text)' is not a size such as 8G or 7.5G")
                }
                imageSize = size
            case "-o":
                output = try value(for: name, inline: inline)
            case "--socket":
                socket = try value(for: name, inline: inline)
            default:
                guard inline == nil else {
                    throw UsageError("\(name) takes no value")
                }
                switch name {
                case "--no-verify": options.verify = false
                case "--ca-2023": options.ca2023 = true
                case "--yes": assumeYes = true
                case "--verbose": options.verbose = true
                default: break
                }
            }
            index += 1
        }

        switch subcommand {
        case "make":
            guard positional.count == 2 else {
                throw UsageError("make needs ISO and DISK")
            }
            return .make(iso: positional[0], disk: try diskName(positional[1]), options: options, assumeYes: assumeYes)
        case "build":
            guard let output else {
                throw UsageError("build needs -o IMAGE")
            }
            guard positional.count == 1 else {
                throw UsageError("build needs ISO")
            }
            return .build(iso: positional[0], output: output, imageSize: imageSize, options: options)
        case "disks":
            guard positional.isEmpty else {
                throw UsageError("disks takes no arguments")
            }
            return .disks
        case "ipc":
            guard let socket, positional.isEmpty else {
                throw UsageError("ipc needs --socket PATH and nothing else")
            }
            return .ipc(socket: socket)
        default:
            guard positional.count == 1 else {
                throw UsageError("info needs ISO")
            }
            return .info(iso: positional[0])
        }
    }

    /// `disk4`, `/dev/disk4` or `/dev/rdisk4` → `disk4`. Slices and anything else are usage errors.
    static func diskName(_ text: String) throws(UsageError) -> String {
        var name = text
        if name.hasPrefix("/dev/") {
            name.removeFirst("/dev/".count)
            if name.hasPrefix("rdisk") {
                name.removeFirst()
            }
        }
        guard DiskCandidate.isWholeDiskName(name) else {
            throw UsageError("'\(text)' is not a whole disk such as disk4, /dev/disk4 or /dev/rdisk4")
        }
        return name
    }
}
