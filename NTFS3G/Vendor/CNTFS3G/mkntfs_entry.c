/* SPDX-License-Identifier: GPL-2.0-or-later */

/*
 * In-process entry point for ntfsprogs/mkntfs.c.
 *
 * mkntfs is written to run once per process. To run it repeatedly in-process without patching
 * the submodule:
 *
 *   - mkntfs.c is compiled as part of this file (it is left out of the target's sources list),
 *     so that its file-scope statics can be reset after each run; see reset_mkntfs_globals().
 *   - Calls are serialized, and the getopt state is reset before each one.
 *   - mkntfs's main() calls utils_set_locale(), which runs setlocale(LC_ALL, "") and switches
 *     the whole process to the locale of the environment, from then on and for every thread
 *     (a de_DE locale turns the decimal point into a comma for every C-level number formatter
 *     and parser in the process). Saving and restoring the locale around the call would still
 *     expose the change to other threads while mkntfs runs, so the call is redirected to
 *     keep_process_locale(), which does nothing. mkntfs converts the label with libntfs-3g's
 *     built-in UTF-8 converter, which does not depend on the locale.
 *   - mkntfs's main() also installs ntfs_log_handler_outerr as the libntfs-3g log handler, and
 *     -q clears some libntfs-3g log levels. Both are restored afterwards; the log handler to
 *     ntfs_log_handler_stderr, the handler installed by cntfs3g_initialize().
 */

#include "config.h"

#include <getopt.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

#include "include/CNTFS3G.h"

/*
 * Stands in for utils_set_locale() in mkntfs.c. Defined before utils.h is included, so that
 * its declaration there (renamed by the macro below) refers to this static function.
 */
static int keep_process_locale(void)
{
	return 0;
}

#define utils_set_locale keep_process_locale

/*
 * Defines ntfs3g_mkntfs_main() (main(), renamed by the target's cSettings) and the g_* statics.
 * It also leaves `byte`, `uint32_t` and `uint64_t` defined as macros for the rest of this file.
 */
#include "../ntfs-3g/ntfsprogs/mkntfs.c"

#undef utils_set_locale

/*
 * Restores the file-scope statics of mkntfs.c to their initial values after a run.
 *
 * mkntfs_cleanup() frees the list at g_allocation without clearing the pointer, so the next run
 * would walk freed memory (it crashes or loops forever), and it never frees g_upcaseinfo. The
 * other statics are either cleared by mkntfs_cleanup() or assigned before use; they are reset
 * here anyway so that every run starts from the state of a fresh process. `opts` is cleared by
 * mkntfs_parse_options() itself.
 *
 * Every run that allocates goes through mkntfs_redirect(), which always ends in
 * mkntfs_cleanup(), so the pointers cleared here no longer own memory (except g_upcaseinfo).
 *
 * Check this list against mkntfs.c whenever the submodule is moved to another tag.
 */
static void reset_mkntfs_globals(void)
{
	free(g_upcaseinfo);

	g_buf = NULL;
	g_mft_bitmap_byte_size = 0;
	g_mft_bitmap = NULL;
	g_lcn_bitmap_byte_size = 0;
	g_dynamic_buf_size = 0;
	g_dynamic_buf = NULL;
	g_upcaseinfo = NULL;
	g_rl_mft = NULL;
	g_rl_mft_bmp = NULL;
	g_rl_mftmirr = NULL;
	g_rl_logfile = NULL;
	g_rl_boot = NULL;
	g_rl_bad = NULL;
	g_index_block = NULL;
	g_vol = NULL;
	g_mft_size = 0;
	g_mft_lcn = 0;
	g_mftmirr_lcn = 0;
	g_logfile_lcn = 0;
	g_logfile_size = 0;
	g_mft_zone_end = 0;
	g_num_bad_blocks = 0;
	g_bad_blocks = NULL;
	g_allocation = NULL;
}

static pthread_mutex_t mkntfs_lock = PTHREAD_MUTEX_INITIALIZER;

int ntfs3g_mkntfs(int argc, char *argv[])
{
	u32 saved_levels;
	int result;

	pthread_mutex_lock(&mkntfs_lock);

	saved_levels = ntfs_log_get_levels();

	optreset = 1;
	optind = 1;
	result = ntfs3g_mkntfs_main(argc, argv);
	reset_mkntfs_globals();

	ntfs_log_clear_levels(UINT32_MAX);
	ntfs_log_set_levels(saved_levels);
	ntfs_log_set_handler(ntfs_log_handler_stderr);

	pthread_mutex_unlock(&mkntfs_lock);
	return result;
}
