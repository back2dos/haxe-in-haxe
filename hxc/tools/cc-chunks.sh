#!/bin/sh
# Compiles the chunked C output of the backend (the .c files <dir>/files.txt
# lists, see hxc/README.md "Chunked output") and the runtime in parallel,
# reusing the object files that are newer than their source and headers, then
# links <binary>.
#
#   CC="clang -O2" CFLAGS="..." sh hxc/tools/cc-chunks.sh <dir> <binary>
#
# CC        compiler with its options (default tcc), used to compile and link
# CFLAGS    compile options (the runtime's -I and defines are added)
# LDFLAGS   link options (default: $CFLAGS); LIBS: libraries (default -lm)
# JOBS      parallel compilations (default: the number of cores)
# RT_DIR    the runtime sources (default hxc/rt); RT_FILES: their names
#           without .c (default: every rt*.c of RT_DIR)
# OBJ_DIR   where the objects go (default below)
# HXC_CCACHE=0  do not use ccache (used with gcc/clang/cc when installed)
#
# Objects go to <dir>/obj-<hash of CC and CFLAGS>, so builds with different
# compilers or options keep their own. With -DHXC_CONST_IDS in CFLAGS every
# file also depends on ids.h. With clang -flto=thin and ld.lld, ThinLTO uses a
# cache (<objdir>/thinlto; it saves little after an edit: site/bench/README.md).
set -eu
SRC=$1
BIN=$2
RT_DIR=${RT_DIR:-hxc/rt}
CC=${CC:-tcc}
CFLAGS="${CFLAGS:-} -I $RT_DIR"
LDFLAGS=${LDFLAGS-$CFLAGS}
LIBS=${LIBS--lm}
JOBS=${JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}
key=$(printf '%s|%s' "$CC" "$CFLAGS" | cksum | cut -d' ' -f1)
OBJ=${OBJ_DIR:-$SRC/obj-$key}
mkdir -p "$OBJ"

PFX=
if [ "${HXC_CCACHE:-1}" != 0 ] && command -v ccache >/dev/null 2>&1; then
	case "$(basename "${CC%% *}")" in gcc*|clang*|cc|c++|g++*) PFX=ccache ;; esac
fi

hdeps="$SRC/hxc.h $RT_DIR/rt.h $RT_DIR/rt_gc.h"
case "$CFLAGS" in *HXC_CONST_IDS*) hdeps="$hdeps $SRC/ids.h" ;; esac
rdeps="$RT_DIR/rt.h $RT_DIR/rt_gc.h"

# needs <obj> <src> <headers...>: the object is missing or older than a source
stale() {
	o=$1
	shift
	[ -f "$o" ] || return 0
	for d in "$@"; do
		[ ! -f "$d" ] || [ ! "$d" -nt "$o" ] || return 0
	done
	return 1
}

todo=$OBJ/todo
: > "$todo"
objs=
for f in $(cat "$SRC/files.txt"); do
	o=$OBJ/${f%.c}.o
	objs="$objs $o"
	if stale "$o" "$SRC/$f" $hdeps; then echo "$SRC/$f $o" >> "$todo"; fi
done
if [ -z "${RT_FILES:-}" ]; then
	RT_FILES=$(cd "$RT_DIR" && for f in rt*.c; do echo "${f%.c}"; done)
fi
for f in $RT_FILES; do
	o=$OBJ/$f.o
	objs="$objs $o"
	if stale "$o" "$RT_DIR/$f.c" $rdeps; then echo "$RT_DIR/$f.c $o" >> "$todo"; fi
done

n=$(wc -l < "$todo" | tr -d ' ')
echo "cc-chunks: compiling $n of $(echo $objs | wc -w | tr -d ' ') files (-j$JOBS)"
if [ "$n" -gt 0 ]; then
	export CC CFLAGS PFX
	# word splitting of $CC/$CFLAGS is intended (a command with options)
	xargs -P "$JOBS" -n 2 sh -c '$PFX $CC $CFLAGS -c "$0" -o "$1" || { rm -f "$1"; exit 255; }' < "$todo"
fi

LTO=
case "$CC $LDFLAGS" in
	*clang*-flto=thin*) if command -v ld.lld >/dev/null 2>&1; then LTO="-fuse-ld=lld -Wl,--thinlto-cache-dir=$OBJ/thinlto"; fi ;;
esac
$CC $LDFLAGS $LTO $objs $LIBS -o "$BIN"
