#!/bin/sh
# EXPERIMENTAL: builds mbedtls and libuv as fat (x86-64 + aarch64) static
# libraries with cosmocc, for the Cosmopolitan builds of the hxc runtime
# (backend/haxelib/build.sh, site/build.sh, `-D hxc.static`; see bench/COSMO.md).
#
#   sh backend/tools/cosmo-deps.sh [out dir]      (default: bin/cosmo-deps)
#
# Installs into the out dir:
#   include/mbedtls, include/psa, include/uv.h, include/uv/
#   lib/libmbedtls.a lib/libmbedx509.a lib/libmbedcrypto.a lib/libuv.a
#   lib/.aarch64/*.a        (cosmocc maps -L<dir> to -L<dir>/.aarch64 for aarch64)
#   VERSIONS                versions, commits and patch checksums of this build
# and links with: -I<out>/include -L<out>/lib -lmbedtls -lmbedx509 -lmbedcrypto -luv
#
# The sources are fetched with git at pinned tags and checked against the
# pinned commits (git's object ids are checksums of the whole tree), then
# patched with backend/tools/cosmo-patches/*.patch (why: see the patches).
# Nothing is rebuilt when VERSIONS already matches. Needs: cosmocc and cosmoar
# on PATH (or COSMOCC=<cosmocc dir>), git, patch. About 2 minutes on 4 cores.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$PWD
OUT=${1:-${COSMO_DEPS:-bin/cosmo-deps}}
case $OUT in /*) ;; *) OUT=$ROOT/$OUT ;; esac
PATCHES=$ROOT/backend/tools/cosmo-patches
[ -n "${COSMOCC:-}" ] && PATH=$COSMOCC/bin:$PATH
command -v cosmocc >/dev/null || { echo "cosmo-deps: cosmocc not found (put cosmocc/bin on PATH or set COSMOCC)" >&2; exit 1; }

# mbedtls 2.28 (LTS): the API backend/rt/rt_ssl.c is written against, as
# upstream Haxe's bindings (haxe/libs/mbedtls) and the system 2.28 packages
MBEDTLS_VERSION=2.28.10
MBEDTLS_URL=https://github.com/Mbed-TLS/mbedtls.git
MBEDTLS_COMMIT=2fc8413bfcb51354c8e679141b17b3f1a5942561
# libuv 1.48: the version the native builds were checked with (Ubuntu 24.04)
LIBUV_VERSION=1.48.0
LIBUV_URL=https://github.com/libuv/libuv.git
LIBUV_COMMIT=e9f29cb984231524e3931aa0ae2c5dae1a32884e

CFLAGS="-O2 -w -fno-strict-aliasing"
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 4)}

sum() { sha256sum "$1" | cut -d' ' -f1; }
STAMP="mbedtls $MBEDTLS_VERSION $MBEDTLS_COMMIT $(sum "$PATCHES/mbedtls-$MBEDTLS_VERSION.patch")
libuv $LIBUV_VERSION $LIBUV_COMMIT $(sum "$PATCHES/libuv-$LIBUV_VERSION.patch")
cflags $CFLAGS
cosmocc $(cosmocc --version 2>&1 | head -n 1)"
if [ -f "$OUT/VERSIONS" ] && [ "$(cat "$OUT/VERSIONS")" = "$STAMP" ]; then
	echo "cosmo-deps: $OUT is up to date"
	exit 0
fi

W=$OUT/build
rm -rf "$W" "$OUT/include" "$OUT/lib" "$OUT/VERSIONS"
mkdir -p "$W" "$OUT/include" "$OUT/lib"

# fetch <name> <url> <tag> <commit>
fetch() {
	git clone -q -c advice.detachedHead=false --depth 1 --branch "$3" "$2" "$W/$1"
	got=$(git -C "$W/$1" rev-parse HEAD)
	if [ "$got" != "$4" ]; then
		echo "cosmo-deps: $1: tag $3 is commit $got, expected $4" >&2
		exit 1
	fi
	(cd "$W/$1" && patch -s -p1 < "$PATCHES/$1.patch")
}

# compile <src dir> <obj dir> <cflags> <files...>: fat objects, in parallel
compile() {
	src=$1 obj=$2 flags=$3
	shift 3
	mkdir -p "$obj"
	for f; do echo "$f"; done | xargs -P "$JOBS" -I{} sh -c \
		'f={}; o='"$obj"'/$(echo "$f" | tr / _); cd '"$src"' && cosmocc '"$CFLAGS $flags"' -c "$f" -o "${o%.c}.o"'
}

# archive <lib> <obj dir> <object basenames...>
archive() {
	lib=$1 obj=$2
	shift 2
	objs=
	for f; do objs="$objs $obj/$(echo "$f" | tr / _ | sed 's/\.c$/.o/')"; done
	cosmoar rcs "$OUT/lib/$lib" $objs
}

echo "cosmo-deps: mbedtls $MBEDTLS_VERSION"
fetch mbedtls-$MBEDTLS_VERSION "$MBEDTLS_URL" v$MBEDTLS_VERSION $MBEDTLS_COMMIT
M=$W/mbedtls-$MBEDTLS_VERSION
# the library's own lists (library/Makefile): crypto, x509 and tls objects
objs() { sed -n "/^$1=/,/^\$/p" "$M/library/Makefile" | tr ' \\\t' '\n\n\n' | grep '\.o$' | sed 's/\.o$/.c/'; }
CRYPTO=$(objs OBJS_CRYPTO)
X509=$(objs OBJS_X509)
TLS=$(objs OBJS_TLS)
compile "$M/library" "$W/obj-mbedtls" "-I. -I../include -D_FILE_OFFSET_BITS=64" $CRYPTO $X509 $TLS
archive libmbedcrypto.a "$W/obj-mbedtls" $CRYPTO
archive libmbedx509.a "$W/obj-mbedtls" $X509
archive libmbedtls.a "$W/obj-mbedtls" $TLS
cp -r "$M/include/mbedtls" "$M/include/psa" "$OUT/include/"

echo "cosmo-deps: libuv $LIBUV_VERSION"
fetch libuv-$LIBUV_VERSION "$LIBUV_URL" v$LIBUV_VERSION $LIBUV_COMMIT
U=$W/libuv-$LIBUV_VERSION
# CMakeLists.txt's common and unix sources, plus the generic poll(2) backend
# and the platform files of its posix-poll ports (GNU/Hurd, Cygwin), with
# src/unix/cosmo.c (from the patch) for the rest
UV="src/fs-poll.c src/idna.c src/inet.c src/random.c src/strscpy.c src/strtok.c
src/thread-common.c src/threadpool.c src/timer.c src/uv-common.c src/uv-data-getter-setters.c src/version.c
src/unix/async.c src/unix/core.c src/unix/dl.c src/unix/fs.c src/unix/getaddrinfo.c src/unix/getnameinfo.c
src/unix/loop-watcher.c src/unix/loop.c src/unix/pipe.c src/unix/poll.c src/unix/process.c
src/unix/random-devurandom.c src/unix/signal.c src/unix/stream.c src/unix/tcp.c src/unix/thread.c
src/unix/tty.c src/unix/udp.c
src/unix/posix-poll.c src/unix/posix-hrtime.c src/unix/bsd-ifaddrs.c src/unix/no-fsevents.c
src/unix/no-proctitle.c src/unix/sysinfo-loadavg.c src/unix/sysinfo-memory.c src/unix/cosmo.c"
compile "$U" "$W/obj-uv" "-Iinclude -Isrc -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE" $UV
archive libuv.a "$W/obj-uv" $UV
cp "$U/include/uv.h" "$OUT/include/"
cp -r "$U/include/uv" "$OUT/include/"
cp "$M/LICENSE" "$OUT/LICENSE.mbedtls"
cp "$U/LICENSE" "$OUT/LICENSE.libuv"

rm -rf "$W"
echo "$STAMP" > "$OUT/VERSIONS"
ls -l "$OUT/lib" "$OUT/lib/.aarch64"
