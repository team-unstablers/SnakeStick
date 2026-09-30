//
//  shim.c
//  slopdisk
//
//  Created by Gyuhwan Park on 9/30/26.
//
//  The output arguments use exactly the C type each ioctl writes. A wider or narrower variable would let the
//  kernel write past it or leave part of it uninitialized, without any error.
//

#include "CSlopDiskShim.h"

#include <errno.h>

#if defined(__APPLE__)
#include <sys/disk.h>
#include <sys/ioctl.h>
#elif defined(__linux__)
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <unistd.h>
#endif

/// errno after a failed call, never 0.
static int sd_last_error(void) {
    return errno != 0 ? errno : EIO;
}

int sd_get_logical_block_size(int fd, uint32_t *out) {
#if defined(__APPLE__)
    uint32_t size = 0;
    if (ioctl(fd, DKIOCGETBLOCKSIZE, &size) != 0) {
        return sd_last_error();
    }
    *out = size;
    return 0;
#elif defined(__linux__)
    int size = 0;
    if (ioctl(fd, BLKSSZGET, &size) != 0) {
        return sd_last_error();
    }
    if (size <= 0) {
        return EINVAL;
    }
    *out = (uint32_t)size;
    return 0;
#else
    (void)fd;
    (void)out;
    return ENOTSUP;
#endif
}

int sd_get_block_count(int fd, uint64_t *out) {
#if defined(__APPLE__)
    uint64_t count = 0;
    if (ioctl(fd, DKIOCGETBLOCKCOUNT, &count) != 0) {
        return sd_last_error();
    }
    *out = count;
    return 0;
#elif defined(__linux__)
    // BLKGETSIZE64 reports bytes, not sectors.
    uint64_t bytes = 0;
    int size = 0;
    if (ioctl(fd, BLKGETSIZE64, &bytes) != 0) {
        return sd_last_error();
    }
    if (ioctl(fd, BLKSSZGET, &size) != 0) {
        return sd_last_error();
    }
    if (size <= 0) {
        return EINVAL;
    }
    *out = bytes / (uint64_t)size;
    return 0;
#else
    (void)fd;
    (void)out;
    return ENOTSUP;
#endif
}

int sd_synchronize_cache(int fd) {
#if defined(__APPLE__)
    if (ioctl(fd, DKIOCSYNCHRONIZECACHE) != 0) {
        return sd_last_error();
    }
    return 0;
#elif defined(__linux__)
    // fsync on a block device writes its page cache and then issues a cache flush to the device.
    if (fsync(fd) != 0) {
        return sd_last_error();
    }
    return 0;
#else
    (void)fd;
    return ENOTSUP;
#endif
}
