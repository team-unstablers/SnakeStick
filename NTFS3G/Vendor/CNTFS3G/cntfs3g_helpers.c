/* SPDX-License-Identifier: GPL-2.0-or-later */

/*
 * Small helpers for the NTFS3G Swift target: one-time logging setup, and wrappers around
 * libntfs-3g macros (MREF, le*_to_cpu, NVol*) that are not imported into Swift.
 */

#include <pthread.h>

#include "include/CNTFS3G.h"

static pthread_once_t initialize_once = PTHREAD_ONCE_INIT;

static void initialize(void)
{
	/* The library default is ntfs_log_handler_null, which drops every message. */
	ntfs_log_set_handler(ntfs_log_handler_stderr);
}

void cntfs3g_initialize(void)
{
	pthread_once(&initialize_once, initialize);
}

u64 cntfs3g_mref(MFT_REF mref)
{
	return MREF(mref);
}

int cntfs3g_is_metadata(MFT_REF mref)
{
	return MREF(mref) != FILE_root && MREF(mref) < FILE_first_user;
}

int cntfs3g_inode_is_directory(ntfs_inode *ni)
{
	return (ni->mrec->flags & MFT_RECORD_IS_DIRECTORY) != 0;
}

void cntfs3g_inode_get_times(ntfs_inode *ni, u64 times[3])
{
	times[0] = sle64_to_cpu(ni->creation_time);
	times[1] = sle64_to_cpu(ni->last_data_change_time);
	times[2] = sle64_to_cpu(ni->last_access_time);
}

u64 cntfs3g_lookup_ignoring_case(ntfs_inode *dir_ni, const ntfschar *uname, int uname_len)
{
	ntfs_volume *vol = dir_ni->vol;
	BOOL case_sensitive = NVolCaseSensitive(vol) ? TRUE : FALSE;
	u64 mref;

	/*
	 * ntfs_inode_lookup_by_name() compares names ignoring case when the volume is not mounted
	 * case-sensitive. That comparison is a coarsening of the $I30 collation order (upper-cased
	 * names first), so the B+tree walk stays valid and finds an entry that differs only in
	 * case. It needs only vol->upcase, which is always loaded.
	 *
	 * ntfs_set_ignore_case() is not used: it switches the volume for good, and ntfs_readdir()
	 * would then return lower-cased names. The flag is cleared only for this one lookup.
	 * NTFSVolume is not shared between threads, so nothing else observes the change.
	 */
	NVolClearCaseSensitive(vol);
	mref = ntfs_inode_lookup_by_name(dir_ni, uname, uname_len);
	if (case_sensitive)
		NVolSetCaseSensitive(vol);
	return mref;
}

int cntfs3g_delete_ignoring_case(ntfs_inode *ni, ntfs_inode *dir_ni, const ntfschar *name, u8 name_len)
{
	ntfs_volume *vol = dir_ni->vol;
	BOOL case_sensitive = NVolCaseSensitive(vol) ? TRUE : FALSE;
	int ret;

	/*
	 * ntfs_delete() picks the $FILE_NAME attribute to remove by comparing its name with name,
	 * first exactly and then ignoring case. On a case-sensitive mount the second pass still
	 * compares POSIX-namespace names exactly, and ntfs_create() stores POSIX names, so a name
	 * that differs in case fails with ENOENT. As in cntfs3g_lookup_ignoring_case(), the flag is
	 * cleared for this one call. Nothing else in ntfs_delete() or the functions it calls reads
	 * the flag.
	 *
	 * No pathname is passed. ntfs_delete() uses it only to invalidate the path-to-inode cache,
	 * and a NULL pathname invalidates by inode number instead.
	 */
	NVolClearCaseSensitive(vol);
	ret = ntfs_delete(vol, NULL, ni, dir_ni, name, name_len);
	if (case_sensitive)
		NVolSetCaseSensitive(vol);
	return ret;
}
