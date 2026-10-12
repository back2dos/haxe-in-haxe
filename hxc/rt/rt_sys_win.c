// The runtime for the C output of hxc/: operating-system primitives behind
// hxc.NativeSys (hxc/std/hxc/NativeSys.hx) on Windows (rt_sys.c elsewhere).
// Empty elsewhere.
//
// They behave as the OCaml runtime and Unix library do on Windows, which the
// reference compiler is built with: paths, environment variables, arguments
// and command lines are UTF-16 (the W functions) and UTF-8 on the Haxe side;
// files and pipes are C runtime descriptors in binary mode; a command line
// runs through %COMSPEC% /c (Sys.command: _wsystem; a Process without
// arguments: Unix.open_process_full); a program with arguments is found as
// Unix.create_process finds it (SearchPath with the .exe extension) and its
// command line quotes the arguments as Unix.make_cmdline does; exit codes are
// the processes' own (no wait status).
#ifdef _WIN32
#include "rt.h"
#include "rt_win.h"
#include <conio.h>
#include <stdio.h>
#include <limits.h>

extern int rt_argc;
extern char **rt_argv;

#define BYTES_LEN(b) (((int32_t *)(b))[0])
#define BYTES_DATA(b) ((unsigned char *)(b) + 8)
void *haxe_io_Bytes_alloc(int32_t len);

static void write_all(int fd, const char *p, size_t n) {
	while (n > 0) {
		int w = _write(fd, p, n > INT_MAX ? INT_MAX : (unsigned)n);
		if (w <= 0) return;
		p += w;
		n -= (size_t)w;
	}
}

static void print_to(int fd, void *s) {
	char *u = hx_str_to_utf8(hx_str_or_null(s));
	write_all(fd, u, strlen(u));
	free(u);
}

void hxc_NativeSys_print(void *s) { print_to(1, s); }
void hxc_NativeSys_printErr(void *s) { print_to(2, s); }

static void *str_of_c(const char *s) { return hx_str_of_utf8(s, (int32_t)strlen(s)); }

static void *str_of_w(const wchar_t *w) {
	char *u = rt_win_utf8(w);
	void *s = str_of_c(u);
	free(u);
	return s;
}

static wchar_t *wide_of(void *s) {
	char *u = hx_str_to_utf8(s);
	wchar_t *w = rt_win_wide(u);
	free(u);
	return w;
}

// an Array<String> of n C strings
static void *str_array(char **v, int32_t n) {
	void *a = hx_arr_new(AK_PTR, n);
	RT_ROOT(a);
	for (int32_t i = 0; i < n; i++) {
		void *s = str_of_c(v[i]);
		RT_RELOAD(a);
		rt_set_ptr(ARR_DATA(a), &FP(ARR_DATA(a), i), s);
	}
	RT_RELOAD(a);
	RT_UNROOT(1);
	return a;
}

void *hxc_NativeSys_args(void) { return str_array(rt_argv + 1, rt_argc > 0 ? rt_argc - 1 : 0); }
void *hxc_NativeSys_argv0(void) { return rt_argc > 0 ? str_of_c(rt_argv[0]) : NULL; }

void *hxc_NativeSys_getEnv(void *s) {
	wchar_t *n = wide_of(s);
	wchar_t *v = _wgetenv(n);
	void *r = v ? str_of_w(v) : NULL;
	free(n);
	return r;
}

// _wputenv_s updates the C runtime's table and the process environment
// (which child processes inherit); an empty value removes the variable
void hxc_NativeSys_putEnv(void *s, void *v) {
	wchar_t *n = wide_of(s);
	wchar_t *w = v ? wide_of(v) : NULL;
	_wputenv_s(n, w ? w : L"");
	free(n);
	free(w);
}

// the process environment ("=C:=C:\..." entries included: Sys.environment skips them)
void *hxc_NativeSys_environ(void) {
	wchar_t *block = GetEnvironmentStringsW();
	int32_t n = 0;
	for (wchar_t *e = block; e && *e; e += wcslen(e) + 1) n++;
	char **v = (char **)malloc(sizeof(char *) * (n + 1));
	int32_t i = 0;
	for (wchar_t *e = block; e && *e; e += wcslen(e) + 1) v[i++] = rt_win_utf8(e);
	if (block) FreeEnvironmentStringsW(block);
	void *a = str_array(v, n);
	for (i = 0; i < n; i++) free(v[i]);
	free(v);
	return a;
}

void hxc_NativeSys_sleep(double seconds) {
	if (RT_NTHREADS() > 1) {
		rt_sleep(seconds);
		return;
	}
	if (seconds <= 0) return;
	Sleep((DWORD)(seconds * 1000.0 + 0.5));
}

// _wgetcwd has no trailing separator but at a drive's root ("C:\")
void *hxc_NativeSys_getCwd(void) {
	wchar_t *w = _wgetcwd(NULL, 0);
	if (!w) hx_throw_str("getCwd failed");
	char *u = rt_win_utf8(w);
	free(w);
	size_t n = strlen(u);
	char *b = (char *)malloc(n + 2);
	memcpy(b, u, n + 1);
	free(u);
	if (n == 0 || (b[n - 1] != '/' && b[n - 1] != '\\')) {
		b[n] = '/';
		b[n + 1] = 0;
	}
	void *s = str_of_c(b);
	free(b);
	return s;
}

int32_t hxc_NativeSys_setCwd(void *s) {
	wchar_t *w = wide_of(s);
	int r = _wchdir(w);
	free(w);
	return r == 0;
}

void *hxc_NativeSys_systemName(void) { return hx_str_of_ascii("Windows"); }
void *hxc_NativeSys_hostSystem(void) { return hx_str_of_ascii("Windows"); }

// Sys.command: the C runtime's _wsystem (%COMSPEC% /c cmd), whose result is
// the exit code (OCaml's caml_sys_system_command on Windows)
int32_t hxc_NativeSys_command(void *cmd) {
	wchar_t *w = wide_of(cmd);
	int r;
	RT_BLOCKING(r = _wsystem(w)); // w is malloc'ed: no heap pointer
	free(w);
	return r;
}

// Sys.command quotes its arguments for cmd.exe on Windows (the hxc std's Sys)
int32_t hxc_NativeSys_commandArgs(void *cmd, void *args) { return -2; }

void hxc_NativeSys_exit(int32_t code) {
	fflush(stdout);
	fflush(stderr);
	exit(code);
}

// seconds since the epoch: FILETIME counts 100 ns from 1601
double hxc_NativeSys_time(void) {
	FILETIME ft;
	GetSystemTimePreciseAsFileTime(&ft);
	uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
	return (double)(t - 116444736000000000ull) / 1e7;
}

// user and kernel time of the process (clock() is wall-clock time on Windows)
double hxc_NativeSys_cpuTime(void) {
	FILETIME c, e, k, u;
	if (!GetProcessTimes(GetCurrentProcess(), &c, &e, &k, &u)) return 0;
	uint64_t kt = ((uint64_t)k.dwHighDateTime << 32) | k.dwLowDateTime;
	uint64_t ut = ((uint64_t)u.dwHighDateTime << 32) | u.dwLowDateTime;
	return (double)(kt + ut) / 1e7;
}

void *hxc_NativeSys_programPath(void) {
	wchar_t buf[32768];
	DWORD n = GetModuleFileNameW(NULL, buf, 32768);
	if (n == 0 || n >= 32768) return rt_argc > 0 ? str_of_c(rt_argv[0]) : hx_str_of_ascii("");
	return str_of_w(buf);
}

// extc's sys_getch: the console without line buffering, or a byte of a
// redirected standard input
int32_t hxc_NativeSys_getChar(int32_t echo) {
	HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
	DWORD ft = h != INVALID_HANDLE_VALUE ? GetFileType(h) : FILE_TYPE_CHAR;
	if (ft == FILE_TYPE_CHAR) {
		int c;
		RT_BLOCKING(c = echo ? _getche() : _getch());
		return c;
	}
	unsigned char c;
	int r;
	RT_BLOCKING(r = _read(0, &c, 1));
	if (r <= 0) hx_throw_str("Eof");
	if (echo) _write(1, &c, 1);
	return c;
}

// ---- files: C runtime descriptors in binary mode, not inherited

int32_t hxc_NativeSys_fileOpen(void *path, int32_t mode) {
	static const int flags[] = {_O_RDONLY, _O_WRONLY | _O_CREAT | _O_TRUNC, _O_WRONLY | _O_CREAT | _O_APPEND, _O_RDWR | _O_CREAT};
	if (mode < 0 || mode > 3) return -1;
	wchar_t *p = wide_of(path);
	int fd = _wopen(p, flags[mode] | _O_BINARY | _O_NOINHERIT, _S_IREAD | _S_IWRITE);
	free(p);
	return fd;
}

// Reads and writes of pipes and consoles block: with other threads they go
// through a malloc'ed buffer in a safe region (a collection may move the Bytes)
int32_t hxc_NativeSys_fileRead(int32_t fd, void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos + len > BYTES_LEN(b)) hx_throw_str("OutsideBounds");
	if (RT_NTHREADS() > 1) {
		char *tmp = (char *)malloc(len > 0 ? (size_t)len : 1);
		RT_ROOT(b);
		int r;
		RT_BLOCKING(r = _read(fd, tmp, (unsigned)len));
		RT_RELOAD(b);
		RT_UNROOT(1);
		if (r > 0) memcpy(BYTES_DATA(b) + pos, tmp, (size_t)r);
		free(tmp);
		return r;
	}
	return _read(fd, BYTES_DATA(b) + pos, (unsigned)len);
}

int32_t hxc_NativeSys_fileWrite(int32_t fd, void *b, int32_t pos, int32_t len) {
	if (pos < 0 || len < 0 || pos + len > BYTES_LEN(b)) hx_throw_str("OutsideBounds");
	if (RT_NTHREADS() > 1) {
		char *tmp = (char *)malloc(len > 0 ? (size_t)len : 1);
		memcpy(tmp, BYTES_DATA(b) + pos, (size_t)len);
		int r;
		RT_BLOCKING(r = _write(fd, tmp, (unsigned)len));
		free(tmp);
		return r;
	}
	return _write(fd, BYTES_DATA(b) + pos, (unsigned)len);
}

void hxc_NativeSys_fileClose(int32_t fd) {
	rt_fd_closed(fd);
	_close(fd);
}

void hxc_NativeSys_fileSeek(int32_t fd, int32_t p, int32_t whence) {
	static const int w[] = {SEEK_SET, SEEK_CUR, SEEK_END};
	if (_lseeki64(fd, p, w[whence < 0 || whence > 2 ? 0 : whence]) < 0) hx_throw_str("seek failed");
}

int32_t hxc_NativeSys_fileTell(int32_t fd) { return (int32_t)_telli64(fd); }

void *hxc_NativeSys_fileContent(void *path) {
	wchar_t *p = wide_of(path);
	int fd = _wopen(p, _O_RDONLY | _O_BINARY | _O_NOINHERIT);
	free(p);
	if (fd < 0) return NULL;
	size_t cap = 65536, n = 0;
	struct _stat64 st;
	if (_fstat64(fd, &st) == 0 && (st.st_mode & _S_IFMT) == _S_IFREG) cap = (size_t)st.st_size + 1;
	char *buf = (char *)malloc(cap);
	for (;;) {
		if (n == cap) buf = (char *)realloc(buf, cap *= 2);
		size_t want = cap - n > INT_MAX ? INT_MAX : cap - n;
		int r = _read(fd, buf + n, (unsigned)want);
		if (r < 0) {
			free(buf);
			_close(fd);
			return NULL;
		}
		if (r == 0) break;
		n += (size_t)r;
	}
	_close(fd);
	void *b = haxe_io_Bytes_alloc((int32_t)n);
	memcpy(BYTES_DATA(b), buf, n);
	free(buf);
	return b;
}

int32_t hxc_NativeSys_fileSave(void *path, void *b, int32_t append) {
	wchar_t *p = wide_of(path);
	int fd = _wopen(p, _O_WRONLY | _O_CREAT | _O_BINARY | _O_NOINHERIT | (append ? _O_APPEND : _O_TRUNC), _S_IREAD | _S_IWRITE);
	free(p);
	if (fd < 0) return 0;
	const char *d = (const char *)BYTES_DATA(b);
	size_t n = (size_t)BYTES_LEN(b);
	int ok = 1;
	while (n > 0) {
		int w = _write(fd, d, n > INT_MAX ? INT_MAX : (unsigned)n);
		if (w <= 0) {
			ok = 0;
			break;
		}
		d += w;
		n -= (size_t)w;
	}
	return _close(fd) == 0 && ok;
}

// Sys.file_exists, Sys.is_directory: _wstati64
static int path_stat(void *path, struct _stat64 *st) {
	wchar_t *p = wide_of(path);
	int r = _wstat64(p, st);
	free(p);
	return r;
}

int32_t hxc_NativeSys_exists(void *path) {
	struct _stat64 st;
	return path_stat(path, &st) == 0;
}

int32_t hxc_NativeSys_isDirectory(void *path) {
	struct _stat64 st;
	return path_stat(path, &st) == 0 && (st.st_mode & _S_IFMT) == _S_IFDIR;
}

int32_t hxc_NativeSys_createDirectory(void *path) {
	wchar_t *p = wide_of(path);
	int r = _wmkdir(p);
	free(p);
	return r == 0;
}

// caml_win32_unlink: a read-only file is made writable, then removed
int32_t hxc_NativeSys_deleteFile(void *path) {
	wchar_t *p = wide_of(path);
	int r = _wunlink(p);
	if (r == -1 && errno == EACCES) {
		DWORD attrs = GetFileAttributesW(p);
		if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_READONLY) && SetFileAttributesW(p, attrs & ~FILE_ATTRIBUTE_READONLY)) {
			r = _wunlink(p);
			if (r == -1) SetFileAttributesW(p, attrs);
		}
	}
	free(p);
	return r == 0;
}

int32_t hxc_NativeSys_deleteDirectory(void *path) {
	wchar_t *p = wide_of(path);
	int r = _wrmdir(p);
	free(p);
	return r == 0;
}

// caml_win32_rename: MoveFileEx replacing the target, a directory over an
// empty directory, never a directory over a file
int32_t hxc_NativeSys_rename(void *path, void *newPath) {
	wchar_t *a = wide_of(path), *b = wide_of(newPath);
	int ok = 0;
	DWORD na = INVALID_FILE_ATTRIBUTES, oa = GetFileAttributesW(a);
	const DWORD flags = MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH | MOVEFILE_COPY_ALLOWED;
	if (oa != INVALID_FILE_ATTRIBUTES && (oa & FILE_ATTRIBUTE_DIRECTORY)) {
		na = GetFileAttributesW(b);
		if (na != INVALID_FILE_ATTRIBUTES && !(na & FILE_ATTRIBUTE_DIRECTORY)) goto done;
	}
	if (MoveFileExW(a, b, flags)) {
		ok = 1;
		goto done;
	}
	if (oa != INVALID_FILE_ATTRIBUTES && (oa & FILE_ATTRIBUTE_DIRECTORY) && na != INVALID_FILE_ATTRIBUTES && (na & FILE_ATTRIBUTE_DIRECTORY)) {
		RemoveDirectoryW(b);
		ok = MoveFileExW(a, b, flags) != 0;
	}
done:
	free(a);
	free(b);
	return ok;
}

// Sys.readdir (caml_read_directory: FindFirstFile over dir\*)
void *hxc_NativeSys_readDirectory(void *path) {
	char *u = hx_str_to_utf8(path);
	size_t l = strlen(u);
	char *pat = (char *)malloc(l + 3);
	memcpy(pat, u, l);
	free(u);
	if (l > 0 && pat[l - 1] != '/' && pat[l - 1] != '\\' && pat[l - 1] != ':') pat[l++] = '\\';
	pat[l++] = '*';
	pat[l] = 0;
	wchar_t *w = rt_win_wide(pat);
	free(pat);
	WIN32_FIND_DATAW fd;
	HANDLE h = FindFirstFileW(w, &fd);
	free(w);
	if (h == INVALID_HANDLE_VALUE) {
		if (GetLastError() != ERROR_FILE_NOT_FOUND) return NULL;
		return hx_arr_new(AK_PTR, 0);
	}
	int32_t n = 0, cap = 16;
	char **names = (char **)malloc(sizeof(char *) * cap);
	do {
		if (wcscmp(fd.cFileName, L".") == 0 || wcscmp(fd.cFileName, L"..") == 0) continue;
		if (n == cap) names = (char **)realloc(names, sizeof(char *) * (cap *= 2));
		names[n++] = rt_win_utf8(fd.cFileName);
	} while (FindNextFileW(h, &fd));
	FindClose(h);
	void *a = str_array(names, n);
	for (int32_t i = 0; i < n; i++) free(names[i]);
	free(names);
	return a;
}

// Extc.get_full_path: GetFullPathName (the file need not exist)
void *hxc_NativeSys_fullPath(void *path) {
	wchar_t *p = wide_of(path);
	DWORD n = GetFullPathNameW(p, 0, NULL, NULL);
	if (n == 0) {
		free(p);
		return NULL;
	}
	wchar_t *buf = (wchar_t *)malloc(sizeof(wchar_t) * (n + 1));
	DWORD m = GetFullPathNameW(p, n + 1, buf, NULL);
	free(p);
	void *s = m == 0 || m > n ? NULL : str_of_w(buf);
	free(buf);
	return s;
}

// Extc.get_real_path: the full path with the drive letter upper-cased and
// each existing component as the file system spells it
void *hxc_NativeSys_realPath(void *path) {
	wchar_t *p = wide_of(path);
	DWORD n = GetFullPathNameW(p, 0, NULL, NULL);
	if (n == 0) {
		free(p);
		return NULL;
	}
	size_t cap = (size_t)n + 1 + 4 * MAX_PATH;
	wchar_t *out = (wchar_t *)malloc(sizeof(wchar_t) * cap);
	DWORD m = GetFullPathNameW(p, n + 1, out, NULL);
	free(p);
	if (m == 0 || m > n) {
		free(out);
		return NULL;
	}
	size_t len = wcslen(out), i = 0, last;
	if (len >= 2 && out[1] == L':') {
		if (out[0] >= L'a' && out[0] <= L'z') out[0] += L'A' - L'a';
		i = len >= 3 && out[2] == L'\\' ? 3 : 2;
	}
	last = i;
	while (i < len) {
		while (i < len && out[i] != L'\\') i++;
		out[i] = 0;
		WIN32_FIND_DATAW data;
		HANDLE h = FindFirstFileW(out, &data);
		if (h != INVALID_HANDLE_VALUE) {
			size_t klen = wcslen(data.cFileName);
			if (klen != i - last && len + klen < cap) { // a ~ (short name) was expanded
				ptrdiff_t d = (ptrdiff_t)klen - (ptrdiff_t)(i - last);
				memmove(out + i + d, out + i, sizeof(wchar_t) * (len - i + 1));
				len += d;
				i += d;
			}
			if (klen == i - last) memcpy(out + last, data.cFileName, sizeof(wchar_t) * klen);
			FindClose(h);
		}
		if (i < len) out[i] = L'\\';
		i++;
		last = i;
	}
	void *s = str_of_w(out);
	free(out);
	return s;
}

// Unix.stat as Windows' C runtime fills it (uid, gid, ino: 0)
void *hxc_NativeSys_stat(void *path) {
	struct _stat64 st;
	if (path_stat(path, &st) != 0) return NULL;
	double v[11] = {(double)st.st_gid, (double)st.st_uid, (double)st.st_atime, (double)st.st_mtime, (double)st.st_ctime, (double)st.st_dev,
		(double)st.st_ino, (double)st.st_nlink, (double)st.st_rdev, (double)st.st_size, (double)st.st_mode};
	void *a = hx_arr_new(AK_F64, 11);
	memcpy(ARR_DATA(a), v, sizeof v);
	return a;
}

// ---- processes: ids of processes this process created, with their handles

typedef struct {
	DWORD pid;
	HANDLE h;
} win_proc;
static win_proc *procs;
static int nprocs, procs_cap;
static SRWLOCK procs_lock = SRWLOCK_INIT;
// handles are made inheritable only for the CreateProcess they are for
static SRWLOCK spawn_lock = SRWLOCK_INIT;

// a copy of the process's handle (closed by the caller), NULL when unknown
static HANDLE proc_handle(DWORD pid) {
	HANDLE h = NULL, self = GetCurrentProcess();
	AcquireSRWLockShared(&procs_lock);
	for (int i = 0; i < nprocs; i++)
		if (procs[i].pid == pid && !DuplicateHandle(self, procs[i].h, self, &h, 0, FALSE, DUPLICATE_SAME_ACCESS)) h = NULL;
	ReleaseSRWLockShared(&procs_lock);
	return h;
}

// Unix.make_cmdline's maybe_quote: Filename.quote (the C runtime's argument
// parsing rules) when the argument is empty or holds a space, tab or quote
static void cmdline_add(char **b, size_t *n, size_t *cap, const char *s) {
	size_t l = strlen(s);
	if (*cap < *n + 2 * l + 4) {
		*cap = (*n + 2 * l + 4) * 2;
		*b = (char *)realloc(*b, *cap);
	}
	char *o = *b + *n;
	if (*n > 0) *o++ = ' ';
	if (l > 0 && !strpbrk(s, " \"\t")) {
		memcpy(o, s, l);
		o += l;
	} else {
		*o++ = '"';
		size_t bs = 0;
		for (size_t i = 0; i < l; i++) {
			if (s[i] == '\\') {
				bs++;
				continue;
			}
			if (s[i] == '"') {
				for (size_t k = 0; k < 2 * bs + 1; k++) *o++ = '\\';
			} else
				for (size_t k = 0; k < bs; k++) *o++ = '\\';
			bs = 0;
			*o++ = s[i];
		}
		for (size_t k = 0; k < 2 * bs; k++) *o++ = '\\';
		*o++ = '"';
	}
	*n = (size_t)(o - *b);
	(*b)[*n] = 0;
}

// caml_search_exe_in_path: SearchPath with .exe, else the name as given
static wchar_t *search_exe(const wchar_t *name) {
	DWORD n = SearchPathW(NULL, name, L".exe", 0, NULL, NULL);
	if (n > 0) {
		wchar_t *f = (wchar_t *)malloc(sizeof(wchar_t) * (n + 1));
		DWORD m = SearchPathW(NULL, name, L".exe", n + 1, f, NULL);
		if (m > 0 && m <= n) return f;
		free(f);
	}
	return _wcsdup(name);
}

// CONOUT$ opens when the process has a console
static int has_console(void) {
	HANDLE h = CreateFileW(L"CONOUT$", GENERIC_WRITE, FILE_SHARE_WRITE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	if (h == INVALID_HANDLE_VALUE) return 0;
	CloseHandle(h);
	return 1;
}

// the parent's end of a pipe as a descriptor
static int pipe_fd(HANDLE h, int flags) {
	int fd = _open_osfhandle((intptr_t)h, flags | _O_BINARY | _O_NOINHERIT);
	if (fd < 0) CloseHandle(h);
	return fd;
}

int32_t hxc_NativeSys_processRun(void *cmd, void *args, void *fds) {
	char *line = NULL;
	size_t n = 0, cap = 0;
	wchar_t *exe;
	if (args) {
		// Unix.create_process cmd (cmd :: args)
		char *c = hx_str_to_utf8(cmd);
		cmdline_add(&line, &n, &cap, c);
		wchar_t *wc = rt_win_wide(c);
		free(c);
		exe = search_exe(wc);
		free(wc);
		for (int32_t i = 0; i < ARR_LEN(args); i++) {
			char *a = hx_str_to_utf8(hx_aget_p_slow(args, i));
			cmdline_add(&line, &n, &cap, a);
			free(a);
		}
	} else {
		// Unix.open_process_full: %COMSPEC% /c cmd
		wchar_t *shell = _wgetenv(L"COMSPEC");
		if (!shell) return -1;
		char *s = rt_win_utf8(shell), *c = hx_str_to_utf8(cmd);
		size_t ls = strlen(s), lc = strlen(c);
		line = (char *)malloc(ls + lc + 5);
		memcpy(line, s, ls);
		memcpy(line + ls, " /c ", 4);
		memcpy(line + ls + 4, c, lc + 1);
		free(s);
		free(c);
		exe = search_exe(shell);
	}
	wchar_t *wline = rt_win_wide(line);
	free(line);
	// pipes: the child's ends are inheritable copies, the parent's are not
	SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, FALSE};
	HANDLE in_r, in_w, out_r, out_w, err_r, err_w;
	if (!CreatePipe(&in_r, &in_w, &sa, 0)) goto fail0;
	if (!CreatePipe(&out_r, &out_w, &sa, 0)) goto fail1;
	if (!CreatePipe(&err_r, &err_w, &sa, 0)) goto fail2;
	STARTUPINFOW si;
	ZeroMemory(&si, sizeof si);
	si.cb = sizeof si;
	si.dwFlags = STARTF_USESTDHANDLES;
	DWORD flags = CREATE_UNICODE_ENVIRONMENT;
	if (!has_console()) {
		flags |= CREATE_NEW_CONSOLE;
		si.dwFlags |= STARTF_USESHOWWINDOW;
		si.wShowWindow = SW_HIDE;
	}
	PROCESS_INFORMATION pi;
	HANDLE self = GetCurrentProcess();
	AcquireSRWLockExclusive(&spawn_lock);
	DuplicateHandle(self, in_r, self, &si.hStdInput, 0, TRUE, DUPLICATE_SAME_ACCESS);
	DuplicateHandle(self, out_w, self, &si.hStdOutput, 0, TRUE, DUPLICATE_SAME_ACCESS);
	DuplicateHandle(self, err_w, self, &si.hStdError, 0, TRUE, DUPLICATE_SAME_ACCESS);
	BOOL ok = CreateProcessW(exe, wline, NULL, NULL, TRUE, flags, NULL, NULL, &si, &pi);
	CloseHandle(si.hStdInput);
	CloseHandle(si.hStdOutput);
	CloseHandle(si.hStdError);
	ReleaseSRWLockExclusive(&spawn_lock);
	CloseHandle(in_r);
	CloseHandle(out_w);
	CloseHandle(err_w);
	free(exe);
	free(wline);
	if (!ok) {
		CloseHandle(in_w);
		CloseHandle(out_r);
		CloseHandle(err_r);
		return -1;
	}
	CloseHandle(pi.hThread);
	AcquireSRWLockExclusive(&procs_lock);
	if (nprocs == procs_cap) {
		procs_cap = procs_cap ? procs_cap * 2 : 16;
		procs = (win_proc *)realloc(procs, sizeof(win_proc) * procs_cap);
	}
	procs[nprocs].pid = pi.dwProcessId;
	procs[nprocs++].h = pi.hProcess;
	ReleaseSRWLockExclusive(&procs_lock);
	int32_t v[3] = {pipe_fd(in_w, _O_WRONLY), pipe_fd(out_r, _O_RDONLY), pipe_fd(err_r, _O_RDONLY)};
	RT_ROOT(fds);
	for (int i = 0; i < 3; i++) hx_aset_slow(fds_root, i, AK_I32, (uint64_t)(uint32_t)v[i]);
	RT_UNROOT(1);
	return (int32_t)pi.dwProcessId;
fail2:
	CloseHandle(out_r);
	CloseHandle(out_w);
fail1:
	CloseHandle(in_r);
	CloseHandle(in_w);
fail0:
	free(exe);
	free(wline);
	return -1;
}

// the exit code (Windows exit codes are 32 bits: a negative Int for codes
// such as 0xC0000005), or -1 while the process runs
int32_t hxc_NativeSys_processWait(int32_t pid, int32_t block) {
	HANDLE h = proc_handle((DWORD)pid);
	if (!h) return -1;
	DWORD r;
	RT_BLOCKING(r = WaitForSingleObject(h, block ? INFINITE : 0));
	DWORD code;
	BOOL got = r == WAIT_OBJECT_0 && GetExitCodeProcess(h, &code);
	CloseHandle(h);
	if (!got) return -1;
	// reaped: the handle is closed (the std caches the exit code)
	AcquireSRWLockExclusive(&procs_lock);
	for (int i = 0; i < nprocs; i++)
		if (procs[i].pid == (DWORD)pid) {
			CloseHandle(procs[i].h);
			procs[i] = procs[--nprocs];
			break;
		}
	ReleaseSRWLockExclusive(&procs_lock);
	return (int32_t)code;
}

// Unix.kill pid Sys.sigkill: TerminateProcess with exit code 0
void hxc_NativeSys_processKill(int32_t pid) {
	HANDLE h = proc_handle((DWORD)pid);
	if (h) {
		TerminateProcess(h, 0);
		CloseHandle(h);
	}
}

#endif
