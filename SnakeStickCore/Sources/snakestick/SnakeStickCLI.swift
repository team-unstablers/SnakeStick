// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SnakeStickCore

@main
struct SnakeStickCLI {
    static func main() async {
        let code = await run(Array(CommandLine.arguments.dropFirst()))
        exit(code.rawValue)
    }

    static func run(_ arguments: [String]) async -> ExitCode {
        let command: Command
        do {
            command = try Arguments.parse(arguments)
        } catch {
            Console.error("snakestick: \(error)\n\n\(Arguments.usage)")
            return .usage
        }
        switch command {
        case .help:
            print(Arguments.usage)
            return .success
        case .disks:
            return disks()
        case .info(let iso):
            return await info(iso: iso)
        case .make(let iso, let disk, let options, let assumeYes):
            return await make(iso: iso, disk: disk, options: options, assumeYes: assumeYes)
        case .build(let iso, let output, let imageSize, let options):
            return await build(iso: iso, output: output, imageSize: imageSize, options: options)
        case .ipc(let socket):
            return await ipc(socketPath: socket)
        }
    }

    // MARK: - Subcommands

    static func disks() -> ExitCode {
        let disks: [DiskCandidate]
        do {
            disks = try listWholeDisks()
        } catch {
            return report(error)
        }
        let eligible = disks.filter(\.isEligible)
        if eligible.isEmpty {
            print("No external or removable disks found.")
        } else {
            print(table([["DISK", "SIZE", "PROTOCOL", "MODEL", "CONTENTS"]] + eligible.map {
                [$0.bsdName, SISize.format($0.sizeBytes), $0.protocolName, $0.model, contents(of: $0)]
            }))
        }
        let excluded = disks.filter { !$0.isEligible }
        if !excluded.isEmpty {
            print("\nNot offered:")
            print(table(excluded.map { [$0.bsdName, SISize.format($0.sizeBytes), $0.model, $0.ineligibleReason ?? ""] }))
        }
        return .success
    }

    static func info(iso: String) async -> ExitCode {
        do {
            let info = try await inspectISO(at: absolutePath(iso))
            print(table([
                ["Windows", info.windowsVersion],
                ["Build", String(info.build)],
                ["Architecture", info.architecture],
                ["Volume label", info.volumeLabel.isEmpty ? "(none)" : info.volumeLabel],
                ["ISO size", "\(SISize.format(info.fileSize)) (\(info.fileSize) bytes)"],
                ["Needs", "\(SISize.format(info.requiredBytes)) (\(info.requiredBytes) bytes)"],
                ["CA 2023 boot loaders", info.supportsCA2023 ? "available (--ca-2023)" : "not available (needs build \(ISOInfo.ca2023MinimumBuild) or later)"],
            ]))
            return .success
        } catch {
            return report(error)
        }
    }

    static func make(iso: String, disk: String, options: WriteOptions, assumeYes: Bool) async -> ExitCode {
        let isoPath = absolutePath(iso)
        let info: ISOInfo
        let candidate: DiskCandidate
        switch await checkDevice(isoPath: isoPath, disk: disk) {
        case .success(let checked):
            (info, candidate) = checked
        case .failure(.rootRequired):
            Console.error("snakestick: make writes to a disk and needs root. Run it with sudo:\n  sudo snakestick make \(CommandLine.arguments.dropFirst(2).joined(separator: " "))")
            return .noPermission
        case .failure(.rejected(_, let message)):
            Console.error("snakestick: \(message)")
            return .unavailable
        case .failure(.error(let error)):
            return report(error)
        }

        print("ISO:    \(info.windowsVersion) \(info.architecture), \(SISize.format(info.fileSize))")
        print("Target: \(disk), \(candidate.model), \(SISize.format(candidate.sizeBytes)), \(candidate.protocolName)")
        print("        \(contents(of: candidate))")
        if !assumeYes {
            print("Everything on \(disk) will be erased.")
            print("Type the disk name (\(disk)) to continue: ", terminator: "")
            fflush(stdout)
            guard readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces) == disk else {
                print("Aborted; nothing was written.")
                return .declined
            }
        }
        return await write(InstallerRequest(isoPath: isoPath, target: .device(bsdName: disk), options: options.installerOptions), verbose: options.verbose) { result in
            print("Done in \(duration(result.elapsed)).\(result.verified ? " The written data matches the ISO." : "") You can eject \(disk) now.")
        }
    }

    static func build(iso: String, output: String, imageSize: UInt64?, options: WriteOptions) async -> ExitCode {
        let isoPath = absolutePath(iso)
        let imagePath = absolutePath(output)
        if FileManager.default.fileExists(atPath: imagePath) {
            Console.error("snakestick: \(imagePath) already exists.")
            return .cannotCreate
        }
        let info: ISOInfo
        do {
            info = try await inspectISO(at: isoPath)
        } catch {
            return report(error)
        }
        // Without --imgsize the image is exactly the required size, in bytes (decision 25).
        let size = imageSize ?? info.requiredBytes
        guard size >= info.requiredBytes else {
            Console.error("snakestick: --imgsize \(size) bytes is too small; this ISO needs \(info.requiredBytes) bytes (--imgsize \(minimumSISize(info.requiredBytes)) or more).")
            return .usage
        }
        let request = InstallerRequest(isoPath: isoPath, target: .image(path: imagePath, size: size), options: options.installerOptions)
        return await write(request, verbose: options.verbose) { result in
            print("Done in \(duration(result.elapsed)).\(result.verified ? " The written data matches the ISO." : "")")
            print("\(imagePath): \(size) bytes (\(SISize.format(size)))")
        }
    }

    // MARK: - Checking a disk

    enum DeviceCheckFailure: Error {
        case rootRequired
        /// Not found or not eligible (`.targetIneligible`), or too small (`.insufficientSpace`).
        /// The message is the same for `make` and `ipc`.
        case rejected(InstallerError.Kind, String)
        case error(any Error)
    }

    /// What `make` and `ipc` check before a disk is written, in this order: root (before anything
    /// is opened, P14), the ISO, the disk's existence, the eligibility rules (which cannot be
    /// skipped, not even with --yes) and the size.
    static func checkDevice(isoPath: String, disk: String) async -> Result<(ISOInfo, DiskCandidate), DeviceCheckFailure> {
        guard getuid() == 0 else {
            return .failure(.rootRequired)
        }
        let info: ISOInfo
        let candidate: DiskCandidate
        do {
            info = try await inspectISO(at: isoPath)
            guard let found = try listWholeDisks().first(where: { $0.bsdName == disk }) else {
                return .failure(.rejected(.targetIneligible, "\(disk) was not found. See snakestick disks."))
            }
            candidate = found
        } catch {
            return .failure(.error(error))
        }
        guard candidate.isEligible else {
            return .failure(.rejected(.targetIneligible, "\(disk) cannot be written: \(candidate.ineligibleReason ?? "not eligible"). See snakestick disks."))
        }
        guard candidate.isLargeEnough(for: info.requiredBytes) else {
            return .failure(.rejected(.insufficientSpace, "\(disk) holds \(SISize.format(candidate.sizeBytes)); this ISO needs \(SISize.format(info.requiredBytes))."))
        }
        return .success((info, candidate))
    }

    // MARK: - Running the pipeline

    static func write(_ request: InstallerRequest, verbose: Bool, finished: (InstallerResult) -> Void) async -> ExitCode {
        let console = Console(verbose: verbose)
        let outcome = await runPipeline(request, events: { console.handle($0) }) { cancel in
            // SIGINT cancels the pipeline, which cleans up before it returns (P16).
            signal(SIGINT, SIG_IGN)
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            interrupt.setEventHandler { @Sendable in
                console.note("Interrupted; cleaning up. The target will not be bootable.")
                cancel()
            }
            interrupt.resume()
            return {
                interrupt.cancel()
                signal(SIGINT, SIG_DFL)
            }
        }
        console.finishLine()
        switch outcome {
        case .finished(let result):
            finished(result)
            return .success
        case .cancelled:
            Console.error("snakestick: cancelled. The target was left as it is and cannot be booted; write it again to use it.")
            return .interrupted
        case .failed(let error):
            return report(error)
        }
    }

    enum PipelineOutcome {
        case finished(InstallerResult)
        case cancelled
        case failed(any Error)
    }

    /// Runs the pipeline for `request`. It is cancelled when the calling task is (`ipc`), or
    /// through `cancellation` (SIGINT for `make` and `build`), which gets the function that
    /// cancels the pipeline and returns the function that uninstalls it once the pipeline has
    /// returned. Cancelling stops the pipeline at its next check; it cleans up before it returns.
    static func runPipeline(
        _ request: InstallerRequest,
        events: @escaping @Sendable (InstallerEvent) -> Void,
        cancellation: (_ cancel: @escaping @Sendable () -> Void) -> () -> Void = { _ in {} }
    ) async -> PipelineOutcome {
        let task = Task {
            try await runInstaller(request, events: events)
        }
        let uninstall = cancellation { task.cancel() }
        defer { uninstall() }
        do {
            return .finished(try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            })
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error)
        }
    }

    /// Prints `error` and returns its exit code.
    static func report(_ error: Error) -> ExitCode {
        guard let error = error as? InstallerError else {
            Console.error("snakestick: \(error)")
            return .software
        }
        var text = "snakestick: \(error.message)"
        if error.phase > .openISO || error.targetModified {
            text += "\n  failed at step \(error.phase.rawValue)/8 (\(error.phase.name))"
        }
        if !error.underlying.isEmpty {
            text += "\n  \(error.underlying)"
        }
        if error.targetModified {
            text += "\n  \(error.targetState)"
        }
        Console.error(text)
        return ExitCode(for: error)
    }

    // MARK: - Formatting

    static func absolutePath(_ path: String) -> String {
        path.hasPrefix("/") ? path : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path).standardizedFileURL.path
    }

    static func contents(of disk: DiskCandidate) -> String {
        let partitions = disk.partitionCount == 1 ? "1 partition" : "\(disk.partitionCount) partitions"
        guard !disk.volumes.isEmpty else {
            return partitions
        }
        return partitions + " (" + disk.volumes.map { "\($0.fileSystem) \"\($0.name)\"" }.joined(separator: ", ") + ")"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60) min \(total % 60) s" : "\(total) s"
    }

    /// The smallest `--imgsize` in tenths of a gigabyte that holds `bytes`, e.g. `"7.3G"`.
    static func minimumSISize(_ bytes: UInt64) -> String {
        let tenths = (bytes + 99_999_999) / 100_000_000
        return tenths % 10 == 0 ? "\(tenths / 10)G" : "\(tenths / 10).\(tenths % 10)G"
    }

    static func table(_ rows: [[String]]) -> String {
        guard let columns = rows.map(\.count).max() else {
            return ""
        }
        let widths = (0 ..< columns).map { column in rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { index, cell in
                index == row.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
