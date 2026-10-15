#!/bin/sh
# Builds the runtime object of an hxmc target (hxmc/README.md, "Runtime"):
# hxmc/rt compiled by zig cc -O2 for the target, partially linked (ld -r) with
# the parts of the C library it and generated code use, into one relocatable
# object bin/hxmc/rt/<target>/rt.o, which hxmc's linker then links with the
# program (and lays out once, see Link.hx). Next to it, ssl.o and uv.o:
# sys.ssl (rt_ssl.c with mbedtls) and libuv (rt_uv.c with libuv), linked only
# into programs that refer to them, from the libraries hxmc/tools/deps.sh
# built into bin/hxmc/deps/<target> (DEPS); without them, stubs that throw.
#   sh hxmc/tools/mkrt.sh linux-x86_64
set -eu
target=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ZIG=${ZIG:-zig}
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
CFLAGS="-O2 -g0 -w -fno-strict-aliasing -fno-pie -fno-pic -ffunction-sections -fdata-sections -DRT_CALL_ON_STACK -I $ROOT/hxmc/rt"
files="rt rt_dyn rt_thread"
case $target in
windows-*)
	CFLAGS="-O2 -g0 -w -fno-strict-aliasing -I $ROOT/hxmc/rt"
	files="$files rt_win" ;;
macos-*)
	# position-independent (macOS executables are), against libSystem;
	# arm64 macOS calls main on its own stack without ucontext already
	CFLAGS="-O2 -g0 -w -fno-strict-aliasing -mmacosx-version-min=$([ $target = macos-arm64 ] && echo 11.0 || echo 10.15) -I $ROOT/hxmc/rt" ;;
esac
# HXMC_RT_CENSUS=1: a debug build with the heap census (RT_CENSUS, rt_census.c)
if [ "${HXMC_RT_CENSUS:-}" = 1 ]; then
	CFLAGS="$CFLAGS -DRT_CENSUS_BUILD"
	files="$files rt_census"
fi
objs=
for f in $files; do
	$ZIG cc -target $triple $CFLAGS -c "$ROOT/hxmc/rt/$f.c" -o "$out/obj/$f.o" &
	objs="$objs $out/obj/$f.o"
done
# the slow paths of generated code (rthxmc.c)
$ZIG cc -target $triple $CFLAGS -c "$ROOT/hxmc/rt/rthxmc.c" -o "$out/obj/rthxmc.o" &
objs="$objs $out/obj/rthxmc.o"
# rt_ssl.c and rt_uv.c: with mbedtls and libuv when deps.sh built them, else stubs
if [ -f "$deps/VERSIONS" ]; then
	$ZIG cc -target $triple $CFLAGS -I "$deps/include" -c "$ROOT/hxmc/rt/rt_ssl.c" -o "$out/obj/rt_ssl.o" &
	$ZIG cc -target $triple $CFLAGS -I "$deps/include" -c "$ROOT/hxmc/rt/rt_uv.c" -o "$out/obj/rt_uv.o" &
	sslar="$deps/lib/libmbedtls.a $deps/lib/libmbedx509.a $deps/lib/libmbedcrypto.a"
	uvar="$deps/lib/libuv.a"
else
	echo "mkrt: no $deps/VERSIONS (hxmc/tools/deps.sh): sys.ssl and libuv are stubs that throw" >&2
	$ZIG cc -target $triple $CFLAGS -DHXMC_NO_SSL -c "$ROOT/hxmc/rt/rt_ssl.c" -o "$out/obj/rt_ssl.o" &
	$ZIG cc -target $triple $CFLAGS -DHXMC_NO_UV -c "$ROOT/hxmc/rt/rt_uv.c" -o "$out/obj/rt_uv.o" &
	sslar=
	uvar=
fi
wait
rm -f "$out/ssl.o" "$out/uv.o" "$out/obj/ssl.undef" "$out/obj/uv.undef"
# what generated code calls in the C library besides the runtime (MirBuild),
# and what the runtime's Haxe code calls (hxmc/std/hxmc/unsafe/LibC.hx)
libm="memset memcpy fmod floor ceil sin cos tan asin acos atan atan2 exp log pow sqrt"
libm="$libm memmove memcmp strlen strcmp malloc free strtod rand clock_gettime mktime"
case $target in
windows-*)
	libm="$libm _mktime64 _localtime64_s _gmtime64_s"
	# hxmc/std/hxmc/unsafe/Win32.hx (the UCRT's part; kernel32's are imports)
	libm="$libm _write _read _close _wopen _lseeki64 _telli64 _fstat64 _wstat64 _wgetenv _wputenv_s _wgetcwd _wchdir"
	libm="$libm _wsystem _wmkdir _wunlink _wrmdir _getch _getche _errno _open_osfhandle _get_osfhandle fflush exit realloc"
	libm="$libm GetEnvironmentStringsW FreeEnvironmentStringsW Sleep GetSystemTimePreciseAsFileTime GetProcessTimes"
	libm="$libm GetCurrentProcess GetModuleFileNameW GetStdHandle GetFileType GetFileAttributesW SetFileAttributesW MoveFileExW"
	libm="$libm RemoveDirectoryW FindFirstFileW FindNextFileW FindClose GetLastError GetFullPathNameW DuplicateHandle CloseHandle"
	libm="$libm SearchPathW CreateFileW CreatePipe CreateProcessW WaitForSingleObject GetExitCodeProcess TerminateProcess"
	# hxmc/std/hxmc/unsafe/Winsock.hx
	libm="$libm socket closesocket accept bind connect listen getsockname getpeername getsockopt setsockopt recv send"
	libm="$libm select shutdown ioctlsocket gethostname gethostbyname gethostbyaddr WSAGetLastError SetHandleInformation"
	libm="$libm strerror _strdup rt_win_sock_errno rt_win_sockets_init" ;;
*)
	libm="$libm localtime_r gmtime_r"
	# hxmc/std/hxmc/unsafe/Posix.hx
	libm="$libm write read open close lseek fcntl pipe dup2 isatty tcgetattr tcsetattr getenv setenv unsetenv getcwd chdir"
	libm="$libm nanosleep gettimeofday clock readlink realpath system fork execvp _exit exit fflush waitpid kill mkdir"
	libm="$libm unlink rmdir rename stat fstat opendir readdir closedir realloc environ"
	libm="$libm socket bind connect accept listen getsockname getpeername getsockopt setsockopt recv send select"
	libm="$libm shutdown signal strerror gethostname gethostbyname gethostbyaddr strdup sched_yield"
	case $target in linux-*) libm="$libm __errno_location" ;; esac ;;
esac
case $target in
macos-*)
	# the runtime's Mach-O objects merged into one (hxmc --mkrt-macho); the
	# C library is libSystem, bound at load time
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/rt.o" $objs
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/ssl.o" "$out/obj/rt_ssl.o" $sslar
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/uv.o" "$out/obj/rt_uv.o" $uvar
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
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/ssl.o" "$out/obj/rt_ssl.o" $sslar $sysar -U "$out/obj/ssl.undef"
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/uv.o" "$out/obj/rt_uv.o" $uvar $sysar -U "$out/obj/uv.undef"
	sj=_setjmp; [ $target = windows-arm64 ] && sj=__mingw_setjmp
	undef="-u mainCRTStartup -u $sj -u _tls_index -u _tls_used -x main"
	for f in $libm $(cat "$out/obj/ssl.undef" "$out/obj/uv.undef" | grep -v '^hx\|^rt_\|^haxe_') ; do undef="$undef -u $f"; done
	for f in $(cat "$out/obj/ssl.undef" "$out/obj/uv.undef" | grep '^hx\|^haxe_'); do undef="$undef -x $f"; done
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/rt.o" $objs $inputs $undef
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
ld.lld -r --strip-debug -o "$out/ssl.o" "$out/obj/rt_ssl.o" --start-group $sslar --end-group
ld.lld -r --strip-debug -o "$out/uv.o" "$out/obj/rt_uv.o" $uvar
undef="-u _setjmp"
for f in $libm $(nm -u "$out/ssl.o" "$out/uv.o" | awk '{print $2}' | grep -v '^hx\|^haxe_' | sort -u); do undef="$undef -u $f"; done
# word-at-a-time memcmp and bcmp in place of musl's byte loops (rtlibc.c)
$ZIG cc -target $triple -O2 -g0 -ffreestanding -fno-builtin -ffunction-sections -c "$ROOT/hxmc/rt/rtlibc.c" -o "$out/obj/rtlibc.o"
objs="$objs $out/obj/rtlibc.o"
ld.lld -r --strip-debug -o "$out/rt.o" $undef "$crt1" $objs --start-group $libs --end-group
ls -l "$out/rt.o" "$out/ssl.o" "$out/uv.o"
