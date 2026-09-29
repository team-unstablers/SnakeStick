/*
 * Umbrella header exposing libntfs-3g and mkntfs to Swift.
 *
 * config.h is included first so that the ntfs-3g headers see the same HAVE_* macros as the
 * library build. HAVE_CONFIG_H is not defined here: the ntfs-3g headers would then include
 * "config.h" relative to their own directory, where it does not exist.
 */

#ifndef CNTFS3G_H
#define CNTFS3G_H

#include "../config.h"

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
 * status. Calls are serialized internally.
 *
 * mkntfs installs ntfs_log_handler_outerr as the libntfs-3g log handler, which stays in effect
 * after it returns.
 */
int ntfs3g_mkntfs(int argc, char *argv[]);

#endif /* CNTFS3G_H */
