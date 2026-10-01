// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import os
import SnakeStickCore

/// The window's state machine (§14): 01 nothing chosen → 02 ready ↔ 02b disk menu → 03 erase
/// sheet → 04 writing ↔ 05 cancel sheet → 06 done | 07 failed.
@Observable
final class InstallerViewModel {
    enum Stage: Equatable {
        /// 01 / 02, and after a stop (`stoppedByUser`).
        case idle
        /// Between "Erase and Write" and the first event from the tool ("Waiting for
        /// authorization…" while the administrator dialog is up).
        case starting
        /// 04.
        case writing(InstallerProgress)
        /// 06.
        case finished(InstallerResult)
        /// 07.
        case failed(InstallerError)
    }

    /// Closing the main window or quitting while a job runs goes through 05, like "Cancel".
    enum ExitRequest {
        case closeWindow
        case quit
    }

    struct ISOState: Equatable {
        var url: URL
        var info: ISOInfo?
        var error: String?
        var reading: Bool { info == nil && error == nil }
    }

    // Form
    private(set) var iso: ISOState?
    private(set) var disks: [DiskCandidate] = []
    var selectedDisk: String? {
        didSet { if selectedDisk == Self.noteTag { selectedDisk = oldValue } }
    }
    var volumeLabel = ""
    var verifyAfterWrite = true
    var useCA2023 = false

    // Progress
    private(set) var stage: Stage = .idle {
        didSet { performDeferredExit() }
    }
    private(set) var stoppedByUser = false
    private(set) var log: [String] = []

    // Sheets
    var showsEraseConfirmation = false
    var showsCancelConfirmation = false
    var showsFullDiskAccessNotice = false

    /// The tag of the disabled note at the bottom of the disk menu.
    static let noteTag = "--note--"

    @ObservationIgnored private let runner = InstallerRunner()
    @ObservationIgnored private var watcher: DiskWatcher?
    @ObservationIgnored private let logger = Logger(subsystem: SnakeStickConstants.appBundleIdentifier, category: "installer")
    /// The disk the current or last job wrote to, for the eject button and the messages.
    @ObservationIgnored private var jobDisk: DiskCandidate?
    /// What 05 is up for: nil for "Cancel", otherwise the close or quit that asked.
    @ObservationIgnored private var exitRequest: ExitRequest?
    /// A close or quit that "Stop" held back until the job has been cleaned up.
    @ObservationIgnored private var deferredExit: ExitRequest?
    /// Closes the main window or quits; set by `AppDelegate`.
    @ObservationIgnored var performExit: ((ExitRequest) -> Void)?

    init() {
        runner.onEvent = { [weak self] event in self?.handle(event) }
        runner.onEnded = { [weak self] reason in self?.runEnded(reason) }
        watcher = DiskWatcher { [weak self] in self?.refreshDisks() }
        refreshDisks()
    }

    // MARK: - Derived state

    var isBusy: Bool {
        switch stage {
        case .starting, .writing: true
        default: false
        }
    }

    var isoInfo: ISOInfo? { iso?.info }

    var selectedCandidate: DiskCandidate? {
        disks.first { $0.bsdName == selectedDisk }
    }

    var requiredBytes: UInt64? { isoInfo?.requiredBytes }

    func fits(_ disk: DiskCandidate) -> Bool {
        guard let requiredBytes else {
            return true
        }
        return disk.isLargeEnough(for: requiredBytes)
    }

    var canStart: Bool {
        !isBusy && isoInfo != nil && selectedCandidate.map(fits) == true
    }

    var ca2023Available: Bool { isoInfo?.supportsCA2023 == true }

    // MARK: - Form actions

    func chooseISO(_ url: URL) {
        guard !isBusy else {
            return
        }
        iso = ISOState(url: url)
        useCA2023 = false
        resetFinishedStage()
        Task {
            do {
                let info = try await inspectISO(at: url.path)
                guard iso?.url == url else {
                    return
                }
                iso?.info = info
                volumeLabel = info.volumeLabel
                if let disk = selectedCandidate, !fits(disk) {
                    selectedDisk = nil
                }
            } catch {
                guard iso?.url == url else {
                    return
                }
                let kind = (error as? InstallerError)?.kind
                iso?.error = kind == .isoMissing || kind == .io
                    ? String(localized: "The ISO file cannot be read.")
                    : String(localized: "This is not a Windows installation ISO.")
                append("inspecting \(url.path) failed: \(error)")
            }
        }
    }

    func refreshDisks() {
        do {
            disks = try listDiskCandidates()
        } catch {
            disks = []
            append("listing disks failed: \(error)")
        }
        if let selectedDisk, !disks.contains(where: { $0.bsdName == selectedDisk }), !isBusy {
            self.selectedDisk = nil
        }
    }

    // MARK: - Writing

    /// "Start Writing" → 03.
    func requestStart() {
        guard canStart else {
            return
        }
        showsEraseConfirmation = true
    }

    /// "Erase and Write" in 03: the tool as root, after the administrator dialog.
    func confirmErase() {
        guard canStart, let iso, let disk = selectedCandidate else {
            return
        }
        jobDisk = disk
        stoppedByUser = false
        stage = .starting
        log.removeAll()
        let request = InstallerRequest(
            isoPath: iso.url.path,
            target: .device(bsdName: disk.bsdName),
            options: InstallerOptions(
                volumeLabel: volumeLabel.isEmpty ? nil : volumeLabel,
                verifyAfterWrite: verifyAfterWrite,
                useCA2023Bootloaders: useCA2023 && ca2023Available
            )
        )
        let prompt = String(localized: "SnakeStick wants to erase “\(disk.model)” (\(disk.bsdName)) and make it a Windows installation disk.")
        // The administrator dialog comes up now; the stage stays at "Waiting for
        // authorization…" until the tool's first event.
        do {
            try runner.start(request, prompt: prompt)
        } catch {
            fail(appError(String(localized: "The write could not be started: \(String(describing: error))")))
        }
    }

    /// "Cancel" in 04 → 05.
    func requestCancel() {
        guard isBusy else {
            return
        }
        exitRequest = nil
        showsCancelConfirmation = true
    }

    /// Closing the main window or quitting. While a job runs this is refused and 05 comes up
    /// instead; after "Stop", the close or quit happens once the job has been cleaned up. Quitting
    /// must not skip 05: when the app goes away, the tool gets EOF on its socket, cancels the job
    /// and cleans up.
    func allowsExit(_ request: ExitRequest) -> Bool {
        guard isBusy else {
            return true
        }
        if stoppedByUser {
            deferExit(request)
        } else {
            exitRequest = request
            showsCancelConfirmation = true
        }
        return false
    }

    /// "Stop" in 05.
    func confirmCancel() {
        stoppedByUser = true
        if let exitRequest {
            deferExit(exitRequest)
        }
        runner.cancel()
    }

    /// Quitting also covers closing the window.
    private func deferExit(_ request: ExitRequest) {
        if deferredExit != .quit {
            deferredExit = request
        }
    }

    private func performDeferredExit() {
        guard !isBusy, let exit = deferredExit else {
            return
        }
        deferredExit = nil
        exitRequest = nil
        // After the stage change has been handled.
        Task { performExit?(exit) }
    }

    /// "Done" in 06 → 02.
    func acknowledge() {
        stage = .idle
    }

    /// "Try Again" in 07.
    func retry() {
        stage = .idle
        requestStart()
    }

    /// "Eject" in 06 (P21).
    func eject() {
        guard let disk = jobDisk else {
            return
        }
        Task {
            do {
                try await DiskEjector.eject(bsdName: disk.bsdName)
                stage = .idle
                refreshDisks()
            } catch {
                append("ejecting \(disk.bsdName) failed: \(error)")
                fail(InstallerError(
                    phase: .verify, kind: .other,
                    message: String(localized: "“\(disk.model)” could not be ejected: \(String(describing: error))"),
                    underlying: UIText.appOrigin
                ))
            }
        }
    }

    var jobDiskModel: String { jobDisk?.model ?? selectedCandidate?.model ?? "" }

    // MARK: - Events

    private func handle(_ event: InstallerEvent) {
        switch event {
        case .progress(let progress):
            if isBusy {
                stage = .writing(progress)
            }
        case .log(let line):
            append(line)
        case .finished(let result):
            stage = .finished(result)
            refreshDisks()
        case .failed(let error):
            if error.kind == .cancelled {
                stoppedByUser = true
                stage = .idle
            } else {
                stage = .failed(error)
            }
            // P6: TCC refusing the root tool shows up as EPERM. Whether it does, and whether Full
            // Disk Access for the app helps, has not been tried yet (U1).
            if error.errno == EPERM {
                showsFullDiskAccessNotice = true
            }
            refreshDisks()
        }
    }

    private func runEnded(_ reason: InstallerRunner.EndReason) {
        switch reason {
        case .authCancelled:
            append("the administrator authorization was cancelled")
            if isBusy {
                stage = .idle
            }
        case .lost(let detail):
            append("the tool ended without a result: \(detail)")
            if isBusy {
                fail(appError(String(localized: "The write stopped without a result.")))
            }
        case .osascriptFailed(let detail):
            append("osascript failed: \(detail)")
            if isBusy {
                fail(appError(String(localized: "The write could not be started as an administrator: \(detail)")))
            }
        }
    }

    private func fail(_ error: InstallerError) {
        append("error: \(error)")
        stage = .failed(error)
    }

    /// An error raised by the app itself; its message is already localized (see `UIText.errorBody`).
    private func appError(_ message: String) -> InstallerError {
        InstallerError(phase: .prepareTarget, kind: .other, message: message, underlying: UIText.appOrigin)
    }

    private func resetFinishedStage() {
        if case .finished = stage {
            stage = .idle
        }
        if case .failed = stage {
            stage = .idle
        }
        stoppedByUser = false
    }

    private func append(_ line: String) {
        log.append(line)
        logger.log("\(line, privacy: .public)")
    }
}
