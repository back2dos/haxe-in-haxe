#!/bin/sh
# Compiles the port's C (the chunks of hxc/build.sh port, default
# bin/hxc/hih/prog_hxc) with `zig cc` for another target, without mbedtls and
# libuv (their natives throw when called). Used by .github/workflows/build.yml.
#
#   sh hxc/tools/zig-build.sh <zig target> <binary> [chunk dir]
#   sh hxc/tools/zig-build.sh x86_64-linux-gnu.2.28 bin/zig/hih-linux-x86_64
#
# Targets: x86_64-linux-gnu.2.28, aarch64-linux-gnu.2.28 (glibc: musl has no
# ucontext, which rt_run_main uses for its 1 GB stack), x86_64-macos,
# aarch64-macos. ZIG: the zig executable (default zig); JOBS as cc-chunks.sh.
set -eu
cd "$(dirname "$0")/../.."
T=$1
BIN=$2
SRC=${3:-bin/hxc/hih/prog_hxc}
ZIG=${ZIG:-zig}
LINK=
case "$T" in
	*-linux-musl*) LINK=-static ;;
esac
mkdir -p "$(dirname "$BIN")"
# the same runtime files as site/build.sh
RT="rt rt_dyn rt_std rt_str rt_sys rt_net rt_ssl rt_uv rt_thread rt_census"
FLAGS="-w -fno-strict-aliasing -DHXC_CONST_IDS -DHXC_NO_SSL -DHXC_NO_UV"
CC="$ZIG cc -target $T -O2" CFLAGS="$FLAGS" LDFLAGS="$FLAGS -s $LINK" LIBS="-lm -lpthread" RT_FILES="$RT" \
	OBJ_DIR="$SRC/obj-zig-$T" sh hxc/tools/cc-chunks.sh "$SRC" "$BIN"
ls -l "$BIN"
