/* SPDX-License-Identifier: GPL-2.0-or-later */

/*
 * Umbrella header exposing libntfs-3g and mkntfs to Swift.
 *
 * config.h is included first so that the ntfs-3g headers see the same HAVE_* macros as the
 * library build, and the same undefined DEBUG (see override/config.h). HAVE_CONFIG_H is not
 * defined here: the ntfs-3g headers would then include "config.h" relative to their own
 * directory, where it does not exist.
 */

#ifndef CNTFS3G_H
#define CNTFS3G_H

#include "../override/config.h"

#include "../../ntfs-3g/include/ntfs-3g/types.h"
#include "../../ntfs-3g/include/ntfs-3g/layout.h"
#include "../../ntfs-3g/include/ntfs-3g/device.h"
#include "../../ntfs-3g/include/ntfs-3g/volume.h"
#include "../../ntfs-3g/include/ntfs-3g/inode.h"
#include "../../ntfs-3g/include/ntfs-3g/attrib.h"
#include "../../ntfs-3g/include/ntfs-3g/dir.h"
#include "../../ntfs-3g/include/ntfs-3g/unistr.h"
#include "../../ntfs-3g/include/ntfs-3g/logging.h"

/*
 * Runs mkntfs in-process with the given argv (argv[0] is the program name) and returns its exit
 * status. Calls are serialized internally, and mkntfs can be run any number of times.
 *
 * Unlike the mkntfs program, it does not change the process locale. The libntfs-3g log levels
 * and log handler, which mkntfs changes, are restored before returning; the log handler is
 * left as ntfs_log_handler_stderr.
 */
int ntfs3g_mkntfs(int argc, char *argv[]);

/*
 * Installs ntfs_log_handler_stderr as the libntfs-3g log handler. Only the first call in the
 * process does anything; call it before any other libntfs-3g function.
 */
void cntfs3g_initialize(void);

/* MREF(): the MFT record number of an MFT reference, without the sequence number. */
u64 cntfs3g_mref(MFT_REF mref);

/*
 * Whether an MFT reference returned by ntfs_readdir() names an NTFS metadata file ($MFT,
 * $Bitmap, ...). The root directory is not metadata. Same test as ntfs_filldir() in dir.c.
 */
int cntfs3g_is_metadata(MFT_REF mref);

/* Whether the MFT record of an open inode is flagged as a directory. */
int cntfs3g_inode_is_directory(ntfs_inode *ni);

/*
 * Copies the creation, last data change and last access times of an open inode, in host byte
 * order, into times[0..2]. The unit is 100 ns since 1601-01-01 UTC.
 */
void cntfs3g_inode_get_times(ntfs_inode *ni, u64 times[3]);

/*
 * Like ntfs_inode_lookup_by_name(), but finds an entry whose name equals uname when case is
 * ignored (using the volume's $UpCase table). Returns the MFT reference of one such entry, or
 * (u64)-1 with errno set (ENOENT if there is none).
 */
u64 cntfs3g_lookup_ignoring_case(ntfs_inode *dir_ni, const ntfschar *uname, int uname_len);

#endif /* CNTFS3G_H */
