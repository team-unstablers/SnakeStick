//
//  SDError.swift
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//

import Foundation

/// The single error type thrown by SlopDisk.
public enum SDError: Error, Hashable, Sendable {
    /// A POSIX call failed. `operation` names the call (e.g. `"pread"`), `errno` is the value it left behind.
    case io(operation: String, errno: Int32)
    /// A failure reported by a third-party `SDBlockDevice` implementation.
    case device(description: String)
    case invalidArgument(String)
    /// The file to be created already exists.
    case fileExists(path: String)
    /// The image file is locked by another open file description.
    case locked(path: String)
    /// A write was attempted on a read-only device.
    case readOnly
    /// The device cannot hold a GPT with 128 entries.
    case diskTooSmall(minimum: SDSize)
    /// Both GPT copies are damaged.
    case gptUnrecoverable
    /// The disk does not hold a GPT. Start the transaction with `clear()`.
    case schemeNotGPT
    /// The transaction has already been committed.
    case transactionFinished
    /// `refresh()`, `repair()`, or `withTransaction(_:)` was called from inside a transaction body.
    case transactionInProgress
    /// The label needs more than 36 UTF-16 code units.
    case labelTooLong(utf16Count: Int)
    /// The partition type GUID is all zeros, which marks an unused entry.
    case invalidPartitionType
    case insufficientSpace(requested: SDSize)
    case outOfUsableRange
    case overlapsExistingPartition(SDPartition.ID)
    /// More than 128 entry slots would be needed.
    case tooManyPartitions
    case partitionNotFound(SDPartition.ID)
    case duplicateUniqueID(UUID)
    /// The table read back after a write does not match what was written.
    case verificationFailed(String)
}
