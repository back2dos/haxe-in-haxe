#!/bin/sh
# Builds mbedtls and libuv as static libraries for the release builds of the
# hxc runtime (`make deps`, `make release`, `make cosmo`, the haxelib package;
# see hxc/README.md "Sockets, TLS and libuv"), with one of two toolchains:
#
#   sh hxc/tools/deps.sh cosmo <out dir>       cosmocc: fat (x86-64 + aarch64) libraries
#   sh hxc/tools/deps.sh <zig target> <out dir>   zig cc -target <zig target>, e.g.
#                                              x86_64-linux-gnu.2.28, aarch64-macos,
#                                              x86_64-windows-gnu
#
# Installs into the out dir:
#   include/mbedtls, include/psa, include/uv.h, include/uv/
#   lib/libmbedtls.a lib/libmbedx509.a lib/libmbedcrypto.a lib/libuv.a
#   lib/.aarch64/*.a        (cosmo only: cosmocc maps -L<dir> to -L<dir>/.aarch64 for aarch64)
#   LICENSE.mbedtls, LICENSE.libuv
#   VERSIONS                versions, commits, patch checksums and toolchain of this build
# and links with: -I<out>/include -L<out>/lib -lmbedtls -lmbedx509 -lmbedcrypto -luv
#
# The sources are fetched with git at pinned tags and checked against the
# pinned commits (git's object ids are checksums of the whole tree). The
# Cosmopolitan build applies hxc/tools/cosmo-patches/*.patch (why: see the
# patches); the zig builds use the sources as released. libuv is built from
# the source lists of its CMakeLists.txt for the target's OS (linux, darwin,
# win; for cosmo the generic poll(2) port). Windows programs link the system
# libraries libuv and mbedtls need: -lws2_32 -liphlpapi -luserenv -lpsapi
# -ldbghelp -lole32 -lshell32 -luser32 -ladvapi32 -lbcrypt. Nothing is rebuilt when VERSIONS
# already matches. Needs: git, patch; cosmocc and cosmoar on PATH (or
# COSMOCC=<cosmocc dir>), or zig (ZIG, default zig). About 1-2 minutes on 4 cores.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$PWD
T=${1:?usage: deps.sh cosmo|<zig target> <out dir>}
OUT=${2:?usage: deps.sh cosmo|<zig target> <out dir>}
case $OUT in /*) ;; *) OUT=$ROOT/$OUT ;; esac
PATCHES=$ROOT/hxc/tools/cosmo-patches

# mbedtls 2.28 (LTS): the API hxc/rt/rt_ssl.c is written against, as
# upstream Haxe's bindings (haxe/libs/mbedtls) and the system 2.28 packages
MBEDTLS_VERSION=2.28.10
MBEDTLS_URL=https://github.com/Mbed-TLS/mbedtls.git
MBEDTLS_COMMIT=2fc8413bfcb51354c8e679141b17b3f1a5942561
# libuv 1.48: the version the native builds were checked with (Ubuntu 24.04)
LIBUV_VERSION=1.48.0
LIBUV_URL=https://github.com/libuv/libuv.git
LIBUV_COMMIT=e9f29cb984231524e3931aa0ae2c5dae1a32884e

CFLAGS="-O2 -w -fno-strict-aliasing"
JOBS=${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}

sum() { sha256sum "$1" | cut -d' ' -f1; }
if [ "$T" = cosmo ]; then
	[ -n "${COSMOCC:-}" ] && PATH=$COSMOCC/bin:$PATH
	command -v cosmocc >/dev/null || { echo "deps: cosmocc not found (put cosmocc/bin on PATH or set COSMOCC)" >&2; exit 1; }
	CC=cosmocc
	AR=cosmoar
	OS=cosmo
	TOOLCHAIN="cosmocc $(cosmocc --version 2>&1 | head -n 1)"
	MBEDTLS_PATCH=$PATCHES/mbedtls-$MBEDTLS_VERSION.patch
	LIBUV_PATCH=$PATCHES/libuv-$LIBUV_VERSION.patch
	PATCHED="$(sum "$MBEDTLS_PATCH") $(sum "$LIBUV_PATCH")"
else
	ZIG=${ZIG:-zig}
	command -v "$ZIG" >/dev/null || { echo "deps: zig not found (set ZIG)" >&2; exit 1; }
	CC="$ZIG cc -target $T"
	AR="$ZIG ar"
	case $T in
		*-linux*) OS=linux ;;
		*-macos*) OS=darwin ;;
		*-windows*) OS=win ;;
		*) echo "deps: unsupported target $T (linux, macos or windows)" >&2; exit 1 ;;
	esac
	TOOLCHAIN="zig $("$ZIG" version) -target $T"
	MBEDTLS_PATCH=
	LIBUV_PATCH=
	PATCHED=unpatched
fi
STAMP="mbedtls $MBEDTLS_VERSION $MBEDTLS_COMMIT
libuv $LIBUV_VERSION $LIBUV_COMMIT
patches $PATCHED
cflags $CFLAGS
$TOOLCHAIN"
if [ -f "$OUT/VERSIONS" ] && [ "$(cat "$OUT/VERSIONS")" = "$STAMP" ]; then
	echo "deps: $OUT is up to date"
	exit 0
fi

W=$OUT/build
rm -rf "$W" "$OUT/include" "$OUT/lib" "$OUT/VERSIONS"
mkdir -p "$W" "$OUT/include" "$OUT/lib"

# fetch <name> <url> <tag> <commit> [patch]
fetch() {
	git clone -q -c advice.detachedHead=false --depth 1 --branch "$3" "$2" "$W/$1"
	got=$(git -C "$W/$1" rev-parse HEAD)
	if [ "$got" != "$4" ]; then
		echo "deps: $1: tag $3 is commit $got, expected $4" >&2
		exit 1
	fi
	if [ -n "${5:-}" ]; then (cd "$W/$1" && patch -s -p1 < "$5"); fi
}

# compile <src dir> <obj dir> <cflags> <files...>: in parallel (cosmocc: fat objects)
compile() {
	src=$1 obj=$2 flags=$3
	shift 3
	mkdir -p "$obj"
	for f; do echo "$f"; done | xargs -P "$JOBS" -I{} sh -c \
		'f={}; o='"$obj"'/$(echo "$f" | tr / _); cd '"$src"' && '"$CC $CFLAGS $flags"' -c "$f" -o "${o%.c}.o"'
}

# archive <lib> <obj dir> <sources...>
archive() {
	lib=$1 obj=$2
	shift 2
	objs=
	for f; do objs="$objs $obj/$(echo "$f" | tr / _ | sed 's/\.c$/.o/')"; done
	$AR rcs "$OUT/lib/$lib" $objs
}

echo "deps: mbedtls $MBEDTLS_VERSION ($TOOLCHAIN)"
fetch mbedtls-$MBEDTLS_VERSION "$MBEDTLS_URL" v$MBEDTLS_VERSION $MBEDTLS_COMMIT "$MBEDTLS_PATCH"
M=$W/mbedtls-$MBEDTLS_VERSION
# the library's own lists (library/Makefile): crypto, x509 and tls objects
objs() { sed -n "/^$1=/,/^\$/p" "$M/library/Makefile" | tr ' \\\t' '\n\n\n' | grep '\.o$' | sed 's/\.o$/.c/'; }
CRYPTO=$(objs OBJS_CRYPTO)
X509=$(objs OBJS_X509)
TLS=$(objs OBJS_TLS)
MBEDTLS_FLAGS="-I. -I../include -D_FILE_OFFSET_BITS=64"
# Windows on arm64: timing.c's portable hardclock calls gettimeofday without
# including MinGW's sys/time.h, which declares it
[ "$OS" = win ] && MBEDTLS_FLAGS="$MBEDTLS_FLAGS -include sys/time.h"
compile "$M/library" "$W/obj-mbedtls" "$MBEDTLS_FLAGS" $CRYPTO $X509 $TLS
archive libmbedcrypto.a "$W/obj-mbedtls" $CRYPTO
archive libmbedx509.a "$W/obj-mbedtls" $X509
archive libmbedtls.a "$W/obj-mbedtls" $TLS
cp -r "$M/include/mbedtls" "$M/include/psa" "$OUT/include/"

echo "deps: libuv $LIBUV_VERSION ($TOOLCHAIN)"
fetch libuv-$LIBUV_VERSION "$LIBUV_URL" v$LIBUV_VERSION $LIBUV_COMMIT "$LIBUV_PATCH"
U=$W/libuv-$LIBUV_VERSION
# CMakeLists.txt's common and unix sources (Windows: its win sources), then the OS's
UV_COMMON="src/fs-poll.c src/idna.c src/inet.c src/random.c src/strscpy.c src/strtok.c
src/thread-common.c src/threadpool.c src/timer.c src/uv-common.c src/uv-data-getter-setters.c src/version.c"
UV="$UV_COMMON
src/unix/async.c src/unix/core.c src/unix/dl.c src/unix/fs.c src/unix/getaddrinfo.c src/unix/getnameinfo.c
src/unix/loop-watcher.c src/unix/loop.c src/unix/pipe.c src/unix/poll.c src/unix/process.c
src/unix/random-devurandom.c src/unix/signal.c src/unix/stream.c src/unix/tcp.c src/unix/thread.c
src/unix/tty.c src/unix/udp.c"
UV_FLAGS="-Iinclude -Isrc -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE"
case $OS in
	linux)
		UV="$UV src/unix/proctitle.c src/unix/linux.c src/unix/procfs-exepath.c src/unix/random-getrandom.c
src/unix/random-sysctl-linux.c"
		UV_FLAGS="$UV_FLAGS -D_GNU_SOURCE -D_POSIX_C_SOURCE=200112" ;;
	darwin)
		# fsevents.c and darwin*.c load CoreFoundation/CoreServices with dlopen
		# (declarations from src/unix/darwin-stub.h): no SDK frameworks to link
		UV="$UV src/unix/proctitle.c src/unix/bsd-ifaddrs.c src/unix/kqueue.c src/unix/random-getentropy.c
src/unix/darwin-proctitle.c src/unix/darwin.c src/unix/fsevents.c"
		UV_FLAGS="$UV_FLAGS -D_DARWIN_UNLIMITED_SELECT=1 -D_DARWIN_USE_64_BIT_INODE=1" ;;
	win)
		UV="$UV_COMMON src/win/async.c src/win/core.c src/win/detect-wakeup.c src/win/dl.c src/win/error.c src/win/fs.c
src/win/fs-event.c src/win/getaddrinfo.c src/win/getnameinfo.c src/win/handle.c src/win/loop-watcher.c src/win/pipe.c
src/win/thread.c src/win/poll.c src/win/process.c src/win/process-stdio.c src/win/signal.c src/win/snprintf.c
src/win/stream.c src/win/tcp.c src/win/tty.c src/win/udp.c src/win/util.c src/win/winapi.c src/win/winsock.c"
		UV_FLAGS="-Iinclude -Isrc -DWIN32_LEAN_AND_MEAN -D_WIN32_WINNT=0x0602 -D_CRT_DECLARE_NONSTDC_NAMES=0" ;;
	cosmo)
		# the generic poll(2) backend and the platform files of its posix-poll
		# ports (GNU/Hurd, Cygwin), with src/unix/cosmo.c (from the patch) for the rest
		UV="$UV src/unix/posix-poll.c src/unix/posix-hrtime.c src/unix/bsd-ifaddrs.c src/unix/no-fsevents.c
src/unix/no-proctitle.c src/unix/sysinfo-loadavg.c src/unix/sysinfo-memory.c src/unix/cosmo.c"
		UV_FLAGS="$UV_FLAGS -D_GNU_SOURCE" ;;
esac
compile "$U" "$W/obj-uv" "$UV_FLAGS" $UV
archive libuv.a "$W/obj-uv" $UV
cp "$U/include/uv.h" "$OUT/include/"
cp -r "$U/include/uv" "$OUT/include/"
cp "$M/LICENSE" "$OUT/LICENSE.mbedtls"
cp "$U/LICENSE" "$OUT/LICENSE.libuv"

rm -rf "$W"
echo "$STAMP" > "$OUT/VERSIONS"
ls -l "$OUT/lib"
