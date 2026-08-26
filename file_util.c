#include <utime.h>
#include <time.h>
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif
#include "brl.mod/blitz.mod/blitz.h"

static unsigned long bmk_temporary_output_counter;

BBString * bmk_temporary_output_path(BBString * publishedPath) {
	char * published = (char *)bbStringToUTF8String(publishedPath);
	size_t capacity = strlen(published) + 80;
	char * temporary = bbMemAlloc(capacity);
#ifdef _WIN32
	unsigned long processId = (unsigned long)GetCurrentProcessId();
#else
	unsigned long processId = (unsigned long)getpid();
#endif
	unsigned long ordinal = ++bmk_temporary_output_counter;
	snprintf(temporary, capacity, "%s.bmk-tmp-%lu-%lu", published, processId, ordinal);
	BBString * result = bbStringFromUTF8String((const unsigned char *)temporary);
	bbMemFree(temporary);
	bbMemFree(published);
	return result;
}

BBString * bmk_temporary_staging_path(BBString * buildRoot) {
	char * root = (char *)bbStringToUTF8String(buildRoot);
	size_t capacity = strlen(root) + 48;
	char * temporary = bbMemAlloc(capacity);
#ifdef _WIN32
	unsigned long processId = (unsigned long)GetCurrentProcessId();
#else
	unsigned long processId = (unsigned long)getpid();
#endif
	unsigned long ordinal = ++bmk_temporary_output_counter;
	snprintf(temporary, capacity, "%s/.s-%lx-%lx", root, processId, ordinal);
	BBString * result = bbStringFromUTF8String((const unsigned char *)temporary);
	bbMemFree(temporary);
	bbMemFree(root);
	return result;
}

void bmx_setfiletimenow(BBString * path) {
	char * p = (char *)bbStringToUTF8String(path);
	struct utimbuf times;
	
	times.actime = time(NULL);
	times.modtime = time(NULL); 

	utime(p, &times);
	
	bbMemFree(p);
}

int bmk_atomic_replace(BBString * temporaryPath, BBString * publishedPath) {
	char * temporary = (char *)bbStringToUTF8String(temporaryPath);
	char * published = (char *)bbStringToUTF8String(publishedPath);
	int result;

#ifdef _WIN32
	result = MoveFileExA(temporary, published,
		MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
	result = rename(temporary, published) == 0;
#endif

	bbMemFree(temporary);
	bbMemFree(published);
	return result;
}
