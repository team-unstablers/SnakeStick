// SPDX-License-Identifier: GPL-3.0-or-later

import DiskArbitration
import Foundation

/// Calls `onChange` on the main queue whenever DiskArbitration reports a disk appearing or
/// disappearing (§2), so that the disk menu stays current.
final class DiskWatcher {
    private let session: DASession?
    private let onChange: () -> Void
    private var pending = false

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        session = DASessionCreate(kCFAllocatorDefault)
        guard let session else {
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(session, nil, diskWatcherCallback, context)
        DARegisterDiskDisappearedCallback(session, nil, diskWatcherCallback, context)
        DASessionSetDispatchQueue(session, .main)
    }

    isolated deinit {
        if let session {
            let callback: DADiskAppearedCallback = diskWatcherCallback
            DAUnregisterCallback(session, unsafeBitCast(callback, to: UnsafeMutableRawPointer.self), Unmanaged.passUnretained(self).toOpaque())
            DASessionSetDispatchQueue(session, nil)
        }
    }

    /// Coalesces the burst of callbacks a single disk produces (one per slice).
    fileprivate func changed() {
        guard !pending else {
            return
        }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pending = false
            self?.onChange()
        }
    }
}

nonisolated private func diskWatcherCallback(_ disk: DADisk, _ context: UnsafeMutableRawPointer?) {
    guard let context else {
        return
    }
    // DiskArbitration calls back on the main queue (DASessionSetDispatchQueue above). The
    // pointer crosses into the main actor as a plain address.
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else {
            return
        }
        Unmanaged<DiskWatcher>.fromOpaque(pointer).takeUnretainedValue().changed()
    }
}

/// Ejects a whole disk after unmounting its volumes (P21: the app does it, no root needed).
enum DiskEjector {
    static func eject(bsdName: String) async throws {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName)
        else {
            throw EjectError(status: nil)
        }
        DASessionSetDispatchQueue(session, .main)
        defer { DASessionSetDispatchQueue(session, nil) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
            DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), ejectStepCallback, box)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = Unmanaged.passRetained(ContinuationBox(continuation)).toOpaque()
            DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), ejectStepCallback, box)
        }
    }

    struct EjectError: Error, CustomStringConvertible {
        let status: DAReturn?

        var description: String {
            status.map { String(format: "DiskArbitration error 0x%08x", UInt32(bitPattern: $0)) } ?? "the disk is gone"
        }
    }
}

nonisolated private final class ContinuationBox {
    let continuation: CheckedContinuation<Void, Error>

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }
}

nonisolated private func ejectStepCallback(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else {
        return
    }
    let box = Unmanaged<ContinuationBox>.fromOpaque(context).takeRetainedValue()
    if let dissenter {
        box.continuation.resume(throwing: DiskEjector.EjectError(status: DADissenterGetStatus(dissenter)))
    } else {
        box.continuation.resume()
    }
}
