// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Turns pipeline activity into `.progress` events (P15).
///
/// Overall fraction: steps 1–5 take 1% each, step 6 (copy) runs to 80% (97% without
/// verification), step 7 takes 1%, step 8 the rest. Only step 6 reports a remaining time, from
/// its throughput over the last 10 seconds.
final class ProgressReporter {
    private let send: (InstallerEvent) -> Void
    private let copyEnd: Double
    private var phase: Phase = .openISO
    private var lastSent = Date.distantPast
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    private let clock: () -> TimeInterval

    static let window: TimeInterval = 10
    static let minimumInterval: TimeInterval = 0.1

    init(verify: Bool, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, send: @escaping (InstallerEvent) -> Void) {
        self.send = send
        self.clock = clock
        copyEnd = verify ? 0.80 : 0.97
    }

    func start(_ phase: Phase, detail: String? = nil) {
        self.phase = phase
        samples.removeAll()
        send(.log("Step \(phase.rawValue)/8: \(phase.title)"))
        emit(fraction: base(of: phase), detail: detail, remaining: nil, force: true)
    }

    /// Replaces the detail of the current step, e.g. while the copy scans the ISO (C23).
    func detail(_ text: String) {
        emit(fraction: base(of: phase), detail: text, remaining: nil, force: true)
    }

    func copied(_ done: Int64, of total: Int64, path: String) {
        let now = clock()
        samples.append((now, done))
        samples.removeAll { now - $0.time > Self.window }
        let ratio = total > 0 ? Double(done) / Double(total) : 1
        let fraction = base(of: .copyFiles) + (copyEnd - base(of: .copyFiles)) * ratio
        let remaining = Self.remainingTime(samples: samples, done: done, total: total)
        emit(fraction: fraction, detail: path, remaining: remaining, force: done >= total)
    }

    func verified(_ done: Int64, of total: Int64, path: String) {
        let ratio = total > 0 ? Double(done) / Double(total) : 1
        let fraction = base(of: .verify) + (1 - base(of: .verify)) * ratio
        emit(fraction: fraction, detail: path, remaining: nil, force: done >= total)
    }

    /// Seconds left at the throughput between the oldest and newest sample, once they span at
    /// least two seconds.
    static func remainingTime(samples: [(time: TimeInterval, bytes: Int64)], done: Int64, total: Int64) -> TimeInterval? {
        guard let first = samples.first, let last = samples.last, last.time - first.time >= 2 else {
            return nil
        }
        let rate = Double(last.bytes - first.bytes) / (last.time - first.time)
        guard rate > 0 else {
            return nil
        }
        return Double(max(0, total - done)) / rate
    }

    func base(of phase: Phase) -> Double {
        switch phase {
        case .openISO, .prepareTarget, .writePartitionTable, .checkPartitions, .formatNTFS:
            Double(phase.rawValue - 1) * 0.01
        case .copyFiles:
            0.05
        case .prepareBootPartition:
            copyEnd
        case .verify:
            copyEnd + 0.01
        }
    }

    private func emit(fraction: Double, detail: String?, remaining: TimeInterval?, force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSent) >= Self.minimumInterval else {
            return
        }
        lastSent = now
        send(.progress(InstallerProgress(phase: phase, fraction: min(1, fraction), detail: detail, estimatedRemaining: remaining)))
    }
}
