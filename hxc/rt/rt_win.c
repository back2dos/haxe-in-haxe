// The runtime for the C output of hxc/: the Windows host layer (rt_win.h).
// Empty elsewhere.
#ifdef _WIN32
#include "rt.h"
#include "rt_win.h"
#include <stdio.h>

// ---- reservations committed on first touch

typedef struct {
	char *start, *end; // [start, end): 0 when the entry is free
	char *guard_start, *guard_end; // never committed
} win_range;

#define MAX_RANGES 256
static win_range ranges[MAX_RANGES];
static SRWLOCK ranges_lock = SRWLOCK_INIT;
static size_t page_size;
// committed per fault: a large heap region in large chunks, stacks in small ones
#define CHUNK_MIN ((size_t)64 << 10)
#define CHUNK_MAX ((size_t)4 << 20)

size_t rt_win_page_size(void) {
	if (!page_size) {
		SYSTEM_INFO si;
		GetSystemInfo(&si);
		page_size = si.dwPageSize;
	}
	return page_size;
}

static win_range *find_range(char *a) {
	for (int i = 0; i < MAX_RANGES; i++)
		if (ranges[i].start && a >= ranges[i].start && a < ranges[i].end) return &ranges[i];
	return NULL;
}

// commits the chunk around a in r (the caller holds the lock, shared)
static int commit_at(win_range *r, char *a) {
	if (a >= r->guard_start && a < r->guard_end) return 0;
	size_t size = (size_t)(r->end - r->start);
	size_t chunk = size / 64;
	if (chunk < CHUNK_MIN) chunk = CHUNK_MIN;
	if (chunk > CHUNK_MAX) chunk = CHUNK_MAX;
	char *lo = r->start + ((size_t)(a - r->start) / chunk) * chunk;
	char *hi = lo + chunk;
	if (hi > r->end) hi = r->end;
	// not into the guard
	if (r->guard_end > r->guard_start) {
		if (r->guard_start >= lo && r->guard_start < hi && a < r->guard_start) hi = r->guard_start;
		if (r->guard_end > lo && r->guard_end <= hi && a >= r->guard_end) lo = r->guard_end;
	}
	return VirtualAlloc(lo, (size_t)(hi - lo), MEM_COMMIT, PAGE_READWRITE) != NULL;
}

static LONG CALLBACK commit_handler(EXCEPTION_POINTERS *e) {
	EXCEPTION_RECORD *r = e->ExceptionRecord;
	if (r->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || r->NumberParameters < 2) return EXCEPTION_CONTINUE_SEARCH;
	char *a = (char *)r->ExceptionInformation[1];
	AcquireSRWLockShared(&ranges_lock);
	win_range *w = find_range(a);
	int ok = w && commit_at(w, a);
	ReleaseSRWLockShared(&ranges_lock);
	return ok ? EXCEPTION_CONTINUE_EXECUTION : EXCEPTION_CONTINUE_SEARCH;
}

void *rt_win_reserve(size_t bytes) {
	static int handler_installed;
	char *p = (char *)VirtualAlloc(NULL, bytes, MEM_RESERVE, PAGE_READWRITE);
	if (!p) return NULL;
	AcquireSRWLockExclusive(&ranges_lock);
	if (!handler_installed) {
		AddVectoredExceptionHandler(1, commit_handler);
		handler_installed = 1;
	}
	int i = 0;
	while (i < MAX_RANGES && ranges[i].start) i++;
	if (i == MAX_RANGES) {
		ReleaseSRWLockExclusive(&ranges_lock);
		VirtualFree(p, 0, MEM_RELEASE);
		return NULL;
	}
	ranges[i].start = p;
	ranges[i].end = p + bytes;
	ranges[i].guard_start = ranges[i].guard_end = NULL;
	ReleaseSRWLockExclusive(&ranges_lock);
	return p;
}

void rt_win_release(void *p, size_t bytes) {
	(void)bytes;
	AcquireSRWLockExclusive(&ranges_lock);
	win_range *r = find_range((char *)p);
	if (r) r->start = r->end = NULL;
	ReleaseSRWLockExclusive(&ranges_lock);
	VirtualFree(p, 0, MEM_RELEASE);
}

void rt_win_guard(void *p, size_t bytes) {
	AcquireSRWLockExclusive(&ranges_lock);
	win_range *r = find_range((char *)p);
	if (r) {
		r->guard_start = (char *)p;
		r->guard_end = (char *)p + bytes;
	}
	ReleaseSRWLockExclusive(&ranges_lock);
	VirtualFree(p, bytes, MEM_DECOMMIT);
}

void rt_win_decommit(void *p, size_t bytes) {
	if (bytes) VirtualFree(p, bytes, MEM_DECOMMIT);
}

// ---- text

wchar_t *rt_win_wide(const char *s) {
	int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
	wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (n > 0 ? n : 1));
	if (n <= 0 || !MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n)) w[0] = 0;
	return w;
}

char *rt_win_utf8(const wchar_t *w) {
	int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
	char *s = (char *)malloc(n > 0 ? n : 1);
	if (n <= 0 || !WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL)) s[0] = 0;
	return s;
}

// ---- errors: OCaml's runtime/win32.c error table (caml_win32_maperr)

static const struct {
	DWORD win;
	int err;
} err_table[] = {
	{ERROR_INVALID_FUNCTION, EINVAL}, {ERROR_FILE_NOT_FOUND, ENOENT}, {ERROR_PATH_NOT_FOUND, ENOENT},
	{ERROR_TOO_MANY_OPEN_FILES, EMFILE}, {ERROR_ACCESS_DENIED, EACCES}, {ERROR_INVALID_HANDLE, EBADF},
	{ERROR_ARENA_TRASHED, ENOMEM}, {ERROR_NOT_ENOUGH_MEMORY, ENOMEM}, {ERROR_INVALID_BLOCK, ENOMEM},
	{ERROR_BAD_ENVIRONMENT, E2BIG}, {ERROR_BAD_FORMAT, ENOEXEC}, {ERROR_INVALID_ACCESS, EINVAL},
	{ERROR_INVALID_DATA, EINVAL}, {ERROR_INVALID_DRIVE, ENOENT}, {ERROR_CURRENT_DIRECTORY, EACCES},
	{ERROR_NOT_SAME_DEVICE, EXDEV}, {ERROR_NO_MORE_FILES, ENOENT}, {ERROR_LOCK_VIOLATION, EACCES},
	{ERROR_BAD_NETPATH, ENOENT}, {ERROR_NETWORK_ACCESS_DENIED, EACCES}, {ERROR_BAD_NET_NAME, ENOENT},
	{ERROR_FILE_EXISTS, EEXIST}, {ERROR_CANNOT_MAKE, EACCES}, {ERROR_FAIL_I24, EACCES},
	{ERROR_INVALID_PARAMETER, EINVAL}, {ERROR_NO_PROC_SLOTS, EAGAIN}, {ERROR_DRIVE_LOCKED, EACCES},
	{ERROR_BROKEN_PIPE, EPIPE}, {ERROR_NO_DATA, EPIPE}, {ERROR_DISK_FULL, ENOSPC},
	{ERROR_INVALID_TARGET_HANDLE, EBADF}, {ERROR_WAIT_NO_CHILDREN, ECHILD}, {ERROR_CHILD_NOT_COMPLETE, ECHILD},
	{ERROR_DIRECT_ACCESS_HANDLE, EBADF}, {ERROR_NEGATIVE_SEEK, EINVAL}, {ERROR_SEEK_ON_DEVICE, EACCES},
	{ERROR_DIR_NOT_EMPTY, ENOTEMPTY}, {ERROR_NOT_LOCKED, EACCES}, {ERROR_BAD_PATHNAME, ENOENT},
	{ERROR_MAX_THRDS_REACHED, EAGAIN}, {ERROR_LOCK_FAILED, EACCES}, {ERROR_ALREADY_EXISTS, EEXIST},
	{ERROR_FILENAME_EXCED_RANGE, ENOENT}, {ERROR_NESTING_NOT_ALLOWED, EAGAIN}, {ERROR_NOT_ENOUGH_QUOTA, ENOMEM},
	{ERROR_DIRECTORY, ENOTDIR}, {ERROR_SHARING_VIOLATION, EACCES}, {ERROR_PRIVILEGE_NOT_HELD, EPERM},
};

int rt_win_errno(DWORD err) {
	for (size_t i = 0; i < sizeof err_table / sizeof err_table[0]; i++)
		if (err_table[i].win == err) return err_table[i].err;
	if (err >= ERROR_WRITE_PROTECT && err <= ERROR_SHARING_BUFFER_EXCEEDED) return EACCES;
	if (err >= ERROR_INVALID_STARTING_CODESEG && err <= ERROR_INFLOOP_IN_RELOC_CHAIN) return ENOEXEC;
	return EINVAL;
}

int rt_win_sock_errno(int wsa) {
	switch (wsa) {
	case WSAEINTR: return EINTR;
	case WSAEBADF: return EBADF;
	case WSAEACCES: return EACCES;
	case WSAEFAULT: return EFAULT;
	case WSAEINVAL: return EINVAL;
	case WSAEMFILE: return EMFILE;
	case WSAEWOULDBLOCK: return EWOULDBLOCK;
	case WSAEINPROGRESS: return EINPROGRESS;
	case WSAEALREADY: return EALREADY;
	case WSAENOTSOCK: return ENOTSOCK;
	case WSAEDESTADDRREQ: return EDESTADDRREQ;
	case WSAEMSGSIZE: return EMSGSIZE;
	case WSAEPROTOTYPE: return EPROTOTYPE;
	case WSAENOPROTOOPT: return ENOPROTOOPT;
	case WSAEPROTONOSUPPORT: return EPROTONOSUPPORT;
	case WSAEOPNOTSUPP: return EOPNOTSUPP;
	case WSAEAFNOSUPPORT: return EAFNOSUPPORT;
	case WSAEADDRINUSE: return EADDRINUSE;
	case WSAEADDRNOTAVAIL: return EADDRNOTAVAIL;
	case WSAENETDOWN: return ENETDOWN;
	case WSAENETUNREACH: return ENETUNREACH;
	case WSAENETRESET: return ENETRESET;
	case WSAECONNABORTED: return ECONNABORTED;
	case WSAECONNRESET: return ECONNRESET;
	case WSAENOBUFS: return ENOBUFS;
	case WSAEISCONN: return EISCONN;
	case WSAENOTCONN: return ENOTCONN;
	case WSAETIMEDOUT: return ETIMEDOUT;
	case WSAECONNREFUSED: return ECONNREFUSED;
	case WSAELOOP: return ELOOP;
	case WSAENAMETOOLONG: return ENAMETOOLONG;
	case WSAEHOSTUNREACH: return EHOSTUNREACH;
	case WSAENOTEMPTY: return ENOTEMPTY;
	default: return EINVAL;
	}
}

void rt_win_sockets_init(void) {
	static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
	BOOL pending;
	if (InitOnceBeginInitialize(&once, 0, &pending, NULL) && pending) {
		WSADATA d;
		WSAStartup(MAKEWORD(2, 2), &d);
		InitOnceComplete(&once, 0, NULL);
	}
}

HANDLE rt_win_fd_handle(int fd) { return (HANDLE)_get_osfhandle(fd); }

#endif
