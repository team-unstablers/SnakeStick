/* SPDX-License-Identifier: GPL-2.0-or-later */

/*
 * The config.h seen by libntfs-3g, mkntfs and the CNTFS3G helpers. This directory comes first
 * in the target's header search paths, so `#include "config.h"` in the submodule's sources finds
 * this file. It includes the generated ../config.h unchanged and then undefines DEBUG.
 *
 * SwiftPM and Xcode define DEBUG=1 for C targets in debug builds, and ntfs-3g treats DEBUG as
 * its own debug-build switch: every function logs trace messages, the initial log handler
 * prints to stdout/stderr, and some sanity checks call exit(). The library is built the same
 * way in debug and release builds instead.
 */

#ifndef CNTFS3G_OVERRIDE_CONFIG_H
#define CNTFS3G_OVERRIDE_CONFIG_H

#include "../config.h"

#undef DEBUG

#endif /* CNTFS3G_OVERRIDE_CONFIG_H */
