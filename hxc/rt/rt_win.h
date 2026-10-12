// The runtime for the C output of hxc/: the Windows host layer of native
// Windows builds (_WIN32: zig cc -target x86_64-windows-gnu, MinGW-w64 with
// the UCRT). Included by the runtime's .c files only (never by generated
// code: windows.h defines macros such as min, IN or ERROR), in place of the
// POSIX headers they use elsewhere. rt_win.c implements it.
//
// Memory: the collector reserves large ranges (16 GB heap regions, 1 GB
// shadow stack) and relies on the kernel committing pages as they are
// touched (MAP_NORESERVE). Windows commits explicitly, so rt_win_reserve
// reserves address space and registers the range: a vectored exception
// handler commits the pages of a registered range on their first access
// (in chunks), and rt_win_decommit gives them back (madvise MADV_DONTNEED).
// A guard (mprotect PROT_NONE) is a part of a range that is never committed.
// System calls do not fault into the handler, but every heap object a native
// passes to one was written by the program first (allocation zeroes or fills
// it), so its pages are committed.
//
// Text: the runtime's strings are UTF-8 (hx_str_to_utf8) and Windows' are
// UTF-16: every path, environment variable, argument and command line goes
// through the W functions, as OCaml's runtime does on Windows.
#pragma once
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#endif
// select's sets are arrays of sockets there (64 by default)
#ifndef FD_SETSIZE
#define FD_SETSIZE 1024
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#include <direct.h>
#include <process.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// ---- memory (rt.c, rt_thread.c)
void *rt_win_reserve(size_t bytes); // NULL on failure
void rt_win_release(void *p, size_t bytes);
void rt_win_guard(void *p, size_t bytes); // never committed: an access faults
void rt_win_decommit(void *p, size_t bytes);
size_t rt_win_page_size(void);

#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 2
#define MAP_ANONYMOUS 0x20
#define MAP_NORESERVE 0x4000
#define MAP_FAILED ((void *)-1)
#define MADV_DONTNEED 4
#ifndef _SC_PAGESIZE
#define _SC_PAGESIZE 30
#endif
static inline void *rt_win_mmap(size_t bytes) {
	void *p = rt_win_reserve(bytes);
	return p ? p : MAP_FAILED;
}
#define mmap(addr, len, prot, flags, fd, off) rt_win_mmap(len)
#define munmap(p, len) (rt_win_release((p), (len)), 0)
#define mprotect(p, len, prot) (rt_win_guard((p), (len)), 0)
#define madvise(p, len, advice) (rt_win_decommit((p), (len)), 0)
#define sysconf(name) ((long)rt_win_page_size())

// ---- time
static inline struct tm *localtime_r(const time_t *t, struct tm *r) { return localtime_s(r, t) == 0 ? r : NULL; }
static inline struct tm *gmtime_r(const time_t *t, struct tm *r) { return gmtime_s(r, t) == 0 ? r : NULL; }

// ---- text: malloc'ed conversions (invalid sequences become U+FFFD)
wchar_t *rt_win_wide(const char *utf8);
char *rt_win_utf8(const wchar_t *w);

// ---- errors: a Win32 error code as the errno OCaml's runtime maps it to
// (caml_win32_maperr), and a Winsock error as the errno its Unix library
// reports (unixsupport_win32.c)
int rt_win_errno(DWORD err);
int rt_win_sock_errno(int wsa);
void rt_win_sockets_init(void); // WSAStartup, once

// ---- descriptors: CRT file descriptors (files, pipes, the standard
// streams), which the hxc std uses as on POSIX
HANDLE rt_win_fd_handle(int fd);
#endif
