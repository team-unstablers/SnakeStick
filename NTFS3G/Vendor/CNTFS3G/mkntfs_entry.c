/*
 * In-process entry point for ntfsprogs/mkntfs.c.
 *
 * mkntfs keeps its state in file-scope statics and parses argv with getopt_long(), so calls are
 * serialized and the getopt state is reset before each one.
 */

#include <getopt.h>
#include <pthread.h>
#include <unistd.h>

#include "include/CNTFS3G.h"

/* mkntfs.c's main(), renamed by the target's cSettings (see Package.swift). */
int ntfs3g_mkntfs_main(int argc, char *argv[]);

static pthread_mutex_t mkntfs_lock = PTHREAD_MUTEX_INITIALIZER;

int ntfs3g_mkntfs(int argc, char *argv[])
{
	int result;

	pthread_mutex_lock(&mkntfs_lock);
	optreset = 1;
	optind = 1;
	result = ntfs3g_mkntfs_main(argc, argv);
	pthread_mutex_unlock(&mkntfs_lock);
	return result;
}
