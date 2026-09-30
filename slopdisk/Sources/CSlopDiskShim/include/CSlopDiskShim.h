//
//  CSlopDiskShim.h
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  Disk ioctls for SDRawDevice. The request macros (_IOR / _IO) are function-like and are not imported into
//  Swift, and hard-coding their numeric values would fail silently (ENOTTY or garbage) if they were wrong,
//  so the calls live here. Every function returns 0 on success or an errno value on failure.
//

#ifndef CSLOPDISKSHIM_H
#define CSLOPDISKSHIM_H

#include <stdint.h>

/// Logical block (sector) size in bytes.
/// macOS: DKIOCGETBLOCKSIZE (uint32_t). Linux: BLKSSZGET (int).
int sd_get_logical_block_size(int fd, uint32_t *out);

/// Number of logical blocks.
/// macOS: DKIOCGETBLOCKCOUNT (uint64_t). Linux: BLKGETSIZE64 (bytes, uint64_t) divided by the BLKSSZGET size.
int sd_get_block_count(int fd, uint64_t *out);

/// Asks the device to flush its write cache.
/// macOS: DKIOCSYNCHRONIZECACHE. Linux: fsync. Other platforms: ENOTSUP.
int sd_synchronize_cache(int fd);

#endif /* CSLOPDISKSHIM_H */
