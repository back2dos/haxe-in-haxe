#!/bin/sh
# Builds the runtime objects of an hxmc target (README.md, "hxmc"): the
# runtime is Haxe (hxmc/std/hxmc/rt); rt.o is the parts of the C library
# that generated code and the runtime's Haxe code call (musl's members and
# its startup object on Linux, the C runtime's startup objects, MinGW-w64's
# members and the UCRT's imports on Windows; nothing on macOS, whose C
# library is libSystem, bound at load time), partially linked (ld -r) into
# one relocatable object bin/hxmc/rt/<target>/rt.o, which hxmc's linker then
# links with the program (and lays out once, see Link.hx). Next to it, ssl.o
# and uv.o: mbedtls and libuv (which hxmc/std/hxmc/rt/Ssl.hx and Uv.hx call),
# linked only into programs that refer to them, from the libraries
# hxmc/c/deps.sh built into bin/hxmc/deps/<target> (DEPS); without them,
# neither.
# zig must be the version of hxmc/c/zig-version (the objects are published
# by a hash of hxmc/c: hxmc/bootstrap/rt.mjs).
#   sh hxmc/c/mkrt.sh linux-x86_64
set -eu
target=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ZIG=${ZIG:-zig}
want=$(cat "$ROOT/hxmc/c/zig-version")
[ "$($ZIG version)" = "$want" ] || echo "mkrt: zig $($ZIG version), hxmc/c/zig-version says $want" >&2
case $target in
linux-x86_64) triple=x86_64-linux-musl ;;
linux-arm64) triple=aarch64-linux-musl ;;
windows-x86_64) triple=x86_64-windows-gnu ;;
windows-arm64) triple=aarch64-windows-gnu ;;
macos-x86_64) triple=x86_64-macos ;;
macos-arm64) triple=aarch64-macos ;;
*) echo "mkrt: unknown target $target" >&2; exit 1 ;;
esac
out=$ROOT/bin/hxmc/rt/$target
deps=${DEPS:-$ROOT/bin/hxmc/deps/$target}
mkdir -p "$out/obj"
# mbedtls and libuv themselves, when deps.sh built them
if [ -f "$deps/VERSIONS" ]; then
	sslar="$deps/lib/libmbedtls.a $deps/lib/libmbedx509.a $deps/lib/libmbedcrypto.a"
	uvar="$deps/lib/libuv.a"
	cp "$deps/LICENSE.mbedtls" "$deps/LICENSE.libuv" "$out/.."/
else
	echo "mkrt: no $deps/VERSIONS (hxmc/c/deps.sh): no ssl.o and uv.o" >&2
	sslar=
	uvar=
fi
rm -f "$out/ssl.o" "$out/uv.o" "$out/obj/ssl.undef" "$out/obj/uv.undef"
# the functions the runtime's Haxe code declares (its externs of mbedtls and
# libuv, hxmc/std/hxmc/rt/Ssl.hx and Uv.hx) are the roots of ssl.o and uv.o
sslroots=; for f in $(grep -o 'static function mbedtls_[a-z0-9_]*' "$ROOT/hxmc/std/hxmc/rt/Ssl.hx" | sed 's/static function //' | sort -u) mbedtls_entropy_func mbedtls_ctr_drbg_random; do sslroots="$sslroots -u $f"; done
uvroots=; for f in $(grep -o 'static function uv_[a-z0-9_]*' "$ROOT/hxmc/std/hxmc/rt/Uv.hx" | sed 's/static function //' | sort -u); do uvroots="$uvroots -u $f"; done
# what generated code calls in the C library (MirBuild), and what the
# runtime's Haxe code calls (hxmc/std/hxmc/unsafe/LibC.hx; the collector and
# the threads: hxmc/std/hxmc/rt/Os.hx, Threads.hx, Start.hx); no math: Math
# is Haxe (hxmc/std/hxmc/rt/LibM.hx) and instructions
libc="memset memcpy"
libc="$libc memmove memcmp strlen strcmp malloc free strtod rand clock_gettime mktime"
libc="$libc getenv exit fflush atexit nanosleep"
case $target in
windows-*)
	libc="$libc _mktime64 _localtime64_s _gmtime64_s"
	# hxmc/std/hxmc/unsafe/Win32.hx (the UCRT's part; kernel32's are imports)
	libc="$libc _write _read _close _wopen _lseeki64 _telli64 _fstat64 _wstat64 _wgetenv _wputenv_s _wgetcwd _wchdir"
	libc="$libc _wsystem _wmkdir _wunlink _wrmdir _getch _getche _errno _open_osfhandle _get_osfhandle fflush exit realloc"
	libc="$libc GetEnvironmentStringsW FreeEnvironmentStringsW Sleep GetSystemTimePreciseAsFileTime GetProcessTimes"
	libc="$libc GetCurrentProcess GetModuleFileNameW GetStdHandle GetFileType GetFileAttributesW SetFileAttributesW MoveFileExW"
	libc="$libc RemoveDirectoryW FindFirstFileW FindNextFileW FindClose GetLastError GetFullPathNameW DuplicateHandle CloseHandle"
	libc="$libc SearchPathW CreateFileW CreatePipe CreateProcessW WaitForSingleObject GetExitCodeProcess TerminateProcess"
	# hxmc/std/hxmc/unsafe/Winsock.hx
	libc="$libc socket closesocket accept bind connect listen getsockname getpeername getsockopt setsockopt recv send"
	libc="$libc select shutdown ioctlsocket gethostname gethostbyname gethostbyaddr WSAGetLastError SetHandleInformation"
	libc="$libc strerror _strdup _setmode"
	case $target in windows-arm64) libc="$libc __mingw_longjmp" ;; *) libc="$libc longjmp" ;; esac ;;
*)
	libc="$libc localtime_r gmtime_r"
	# hxmc/std/hxmc/unsafe/Posix.hx
	libc="$libc write read open close lseek fcntl pipe dup2 isatty tcgetattr tcsetattr getenv setenv unsetenv getcwd chdir"
	libc="$libc nanosleep gettimeofday clock readlink realpath system fork execvp _exit exit fflush waitpid kill mkdir"
	libc="$libc unlink rmdir rename stat fstat opendir readdir closedir realloc environ"
	libc="$libc socket bind connect accept listen getsockname getpeername getsockopt setsockopt recv send select"
	libc="$libc shutdown signal strerror gethostname gethostbyname gethostbyaddr strdup sched_yield"
	# hxmc/std/hxmc/rt/Os.hx, Start.hx
	libc="$libc sysconf mmap munmap mprotect madvise poll _longjmp"
	libc="$libc pthread_mutex_init pthread_mutex_destroy pthread_mutex_lock pthread_mutex_trylock pthread_mutex_unlock"
	libc="$libc pthread_condattr_init pthread_condattr_setclock pthread_cond_init pthread_cond_destroy pthread_cond_wait"
	libc="$libc pthread_cond_timedwait pthread_cond_signal pthread_cond_broadcast pthread_attr_init pthread_attr_destroy"
	libc="$libc pthread_attr_setstacksize pthread_attr_setdetachstate pthread_create"
	case $target in linux-*) libc="$libc __errno_location" ;; esac ;;
esac
case $target in
macos-*)
	# nothing of the C library (libSystem, bound at load time): an empty object
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/rt.o" $([ $target = macos-arm64 ] && echo --arm64)
	[ -n "$sslar" ] && "${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/ssl.o" $sslar $sslroots
	[ -n "$uvar" ] && "${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/uv.o" $uvar $uvroots
	ls -l "$out/rt.o" "$out/ssl.o" "$out/uv.o"
	exit 0 ;;
windows-*)
	# the runtime's own COFF objects, the C runtime's startup object and the
	# archives zig links (the MinGW-w64 libraries, compiler-rt, the import
	# libraries of the UCRT and the Windows DLLs the runtime uses), selected
	# and resolved by hxmc itself (hxmc --mkrt)
	printf 'int main(void){return 0;}\n' > "$out/obj/stub.c"
	WINLIBS="-lws2_32 -liphlpapi -luserenv -lpsapi -ldbghelp -lole32 -lshell32 -luser32 -ladvapi32 -lcrypt32 -lbcrypt"
	$ZIG cc -target $triple -O2 "$out/obj/stub.c" -o "$out/obj/stub.exe" $WINLIBS
	line=$($ZIG cc -target $triple -O2 -v "$out/obj/stub.c" -o "$out/obj/stub.exe" $WINLIBS 2>&1 | grep 'lld-link' | head -1)
	inputs=$(echo "$line" | tr ' ' '\n' | grep -E '\.(obj|lib)$' | grep -v '^-' | grep -v '/stub.obj$' | tr '\n' ' ')
	# ssl.o, uv.o: their objects and libraries, the C library for imports
	# only; the rest of the C library they need comes with rt.o
	sysar=
	for a in $inputs; do case $a in *.lib|*.a) sysar="$sysar -i $a" ;; esac; done
	touch "$out/obj/ssl.undef"
	[ -n "$sslar" ] && "${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/ssl.o" $sslar $sysar $sslroots -U "$out/obj/ssl.undef"
	touch "$out/obj/uv.undef"
	[ -n "$uvar" ] && "${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/uv.o" $uvar $sysar $uvroots -U "$out/obj/uv.undef"
	sj=_setjmp; [ $target = windows-arm64 ] && sj=__mingw_setjmp
	undef="-u mainCRTStartup -u $sj -u _tls_index -u _tls_used -x main"
	for f in $libc $(cat "$out/obj/ssl.undef" "$out/obj/uv.undef" | grep -v '^hx\|^rt_\|^haxe_') ; do undef="$undef -u $f"; done
	for f in $(cat "$out/obj/ssl.undef" "$out/obj/uv.undef" | grep '^hx\|^haxe_'); do undef="$undef -x $f"; done
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/rt.o" $inputs $undef
	ls -l "$out/rt.o" "$out/ssl.o" "$out/uv.o"
	exit 0 ;;
esac
# the C library: zig builds it on first use; a static link of a stub tells where
printf 'int main(void){return 0;}\n' > "$out/obj/stub.c"
# (twice: the first run may build the C library and name temporary paths)
$ZIG cc -target $triple -static -O2 "$out/obj/stub.c" -o "$out/obj/stub"
line=$($ZIG cc -target $triple -static -O2 -v "$out/obj/stub.c" -o "$out/obj/stub" 2>&1 | grep 'ld.lld' | head -1)
crt1=$(echo "$line" | tr ' ' '\n' | grep '/crt1.o$')
libs=$(echo "$line" | tr ' ' '\n' | grep -E '/lib(c|zigc|compiler_rt)\.a$' | tr '\n' ' ')
# ssl.o, uv.o: their objects and libraries; the C library they need comes with rt.o
[ -n "$sslar" ] && ld.lld -r --strip-debug -o "$out/ssl.o" $sslroots --start-group $sslar --end-group
[ -n "$uvar" ] && ld.lld -r --strip-debug -o "$out/uv.o" $uvroots --start-group $uvar --end-group
undef="-u _setjmp"
for f in $libc $(nm -u $(ls "$out/ssl.o" "$out/uv.o" 2>/dev/null) | awk '{print $2}' | grep -v '^hx\|^haxe_' | sort -u); do undef="$undef -u $f"; done
ld.lld -r --strip-debug -o "$out/rt.o" $undef "$crt1" --start-group $libs --end-group
ls -l "$out/rt.o" "$out/ssl.o" "$out/uv.o"
