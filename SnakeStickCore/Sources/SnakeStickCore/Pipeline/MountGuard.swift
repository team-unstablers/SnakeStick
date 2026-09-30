// SPDX-License-Identifier: GPL-3.0-or-later

@preconcurrency import DiskArbitration
import Foundation
import os

/// Keeps macOS from mounting anything on the target while the pipeline works (decision 21, C7).
///
/// A DiskArbitration mount-approval callback refuses every mount of the whole disk and its
/// slices, except the next mount of a slice marked with ``allowNextMount(of:)`` (the FAT
/// partition, which the pipeline mounts itself). A mark is used up by one mount (C22).
final class MountGuard: @unchecked Sendable {
    // Unchecked: `session` is only used from init and release(); the mutable state is behind
    // `state`'s lock, and `context` is written once in init.
    private struct State {
        var allowed: Set<String> = []
        var refused: [String] = []
        var released = false
    }

    let wholeDisk: String
    private let session: DASession
    private let queue = DispatchQueue(label: "SnakeStickCore.MountGuard")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let log: @Sendable (String) -> Void
    private var context: Unmanaged<MountGuard>?

    init(wholeDisk: String, log: @escaping @Sendable (String) -> Void) throws {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw InstallerError(phase: .prepareTarget, kind: .other, message: "DiskArbitration is not available.")
        }
        self.wholeDisk = wholeDisk
        self.session = session
        self.log = log
        DASessionSetDispatchQueue(session, queue)
        // The callback holds a reference until release(), so the guard cannot be deallocated
        // while DiskArbitration may still call it. The pipeline always releases it (§11).
        let context = Unmanaged.passRetained(self)
        self.context = context
        DARegisterDiskMountApprovalCallback(session, nil, mountGuardApproval, context.toOpaque())
        log("mount guard: refusing mounts of \(wholeDisk) and its slices")
    }

    /// Lets the next mount of `bsdName` through (one mount only).
    func allowNextMount(of bsdName: String) {
        state.withLock { _ = $0.allowed.insert(bsdName) }
    }

    /// Unregisters the callback. Safe to call more than once.
    func release() {
        let alreadyReleased = state.withLock { state in
            defer { state.released = true }
            return state.released
        }
        guard !alreadyReleased, let context else {
            return
        }
        let callback: DADiskMountApprovalCallback = mountGuardApproval
        DAUnregisterCallback(session, unsafeBitCast(callback, to: UnsafeMutableRawPointer.self), context.toOpaque())
        // Drain callbacks already queued, so that none runs after release returns.
        queue.sync {}
        DASessionSetDispatchQueue(session, nil)
        let refused = state.withLock { $0.refused }
        log("mount guard: released \(wholeDisk); refused \(refused.isEmpty ? "no mounts" : refused.joined(separator: ", "))")
        context.release()
    }

    fileprivate func decide(_ bsdName: String) -> Bool {
        guard bsdName == wholeDisk || bsdName.hasPrefix(wholeDisk + "s") else {
            return true
        }
        let allowed = state.withLock { state in
            if state.released || state.allowed.remove(bsdName) != nil {
                return true
            }
            state.refused.append(bsdName)
            return false
        }
        log("mount guard: \(allowed ? "allowed" : "refused") a mount of \(bsdName)")
        return allowed
    }
}

private func mountGuardApproval(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) -> Unmanaged<DADissenter>? {
    guard let context, let name = DADiskGetBSDName(disk) else {
        return nil
    }
    let guardian = Unmanaged<MountGuard>.fromOpaque(context).takeUnretainedValue()
    if guardian.decide(String(cString: name)) {
        return nil
    }
    let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnNotPermitted), "SnakeStick is writing to this disk" as CFString)
    return Unmanaged.passRetained(dissenter)
}
