#!/bin/sh
# Builds the backend tool, then compiles a program with it to C and to a
# native binary (CC, default tcc for fast builds; CC="clang -O2" for speed;
# CC="cosmocc -O2" for a portable APE binary, see docs/COSMO.md). When EMXX is
# set (e.g. EMXX=em++), also to linear-memory wasm.
#   sh hxc/build.sh [source dir] [main class]     (default: hxc/test Bench)
#   sh hxc/build.sh port                          (the port itself: bin/hxc/hih/hih)
#   CC="cosmocc -O2" BIN=hih.com sh hxc/build.sh port
#   CC="cosmocc -O2" RT_DEPS=bin/cosmo-deps BIN=hih.com sh hxc/build.sh port   (with mbedtls/libuv: hxc/tools/cosmo-deps.sh)
#   HXFLAGS="-D retain" VARIANT=-retain sh hxc/build.sh
# The C is written in chunks to $OUT/prog_hxc/ and compiled in parallel, reusing
# the objects of unchanged chunks (hxc/tools/cc-chunks.sh: JOBS, CFLAGS;
# HXC_IDS=const|extern, see below; CC="clang -O2 -flto=thin" for ThinLTO);
# HXC_SINGLE=1 writes and compiles one file $OUT/prog.c instead; HXC_CHUNK_KB
# sets the chunk size (default 192).
set -eu
cd "$(dirname "$0")/.."
HAXE=${HAXE:-haxe/haxe}
CC=${CC:-tcc}
if [ "${1:-}" = port ]; then
	OUT=bin/hxc/hih
	ARGS="-cp src -main haxe.Main -cp runtime/js -D disable-parallelism"
	BIN=${BIN:-hih}
else
	MAIN=${2:-Bench}
	OUT=bin/hxc/$MAIN${VARIANT:-}
	ARGS="-cp ${1:-hxc/test} -main $MAIN"
	BIN=prog_c
fi
mkdir -p "$OUT"
# EMXX builds from the single file
if [ -n "${EMXX:-}" ]; then HXC_SINGLE=1; fi
export HXC_SINGLE=${HXC_SINGLE:-0}
# bin/hxc/std: the hxc target's std (hxc/std) with the Eval originals for macros
# (given last: the last class path wins over earlier ones, e.g. runtime/js)
python3 hxc/tools/mkstd.py
if [ -z "${SKIP_TOOL:-}" ]; then
	"$HAXE" -cp src -cp hxc/src -main backend.Main -lib hxnodejs -cp runtime/js --js bin/hxc/wbk.js -w -WDeprecated
fi
# hxnodejs's stdout flush fails on pipes, hence the file
HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std} node --stack-size=65500 bin/hxc/wbk.js "$OUT/prog" \
	$ARGS -cp bin/hxc/std --custom-target hxc ${HXFLAGS:-} > "$OUT/wbk.log" 2>&1 || { cat "$OUT/wbk.log"; exit 1; }
# slots are read as int32/double/pointer through casts (FI/FD/FP): no strict aliasing
# without mbedtls/libuv: their natives fail when called (RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" and RT_NO= to link them;
# with cosmocc, RT_DEPS=bin/cosmo-deps links the static libraries of hxc/tools/cosmo-deps.sh)
RT_INC=
if [ -n "${RT_DEPS:-}" ]; then
	RT_NO=${RT_NO-}
	RT_INC="-I$RT_DEPS/include"
	RT_LIBS="-L$RT_DEPS/lib -lmbedtls -lmbedx509 -lmbedcrypto -luv ${RT_LIBS:-}"
fi
RT_FLAGS="-w -fno-strict-aliasing ${RT_NO--DHXC_NO_SSL -DHXC_NO_UV} $RT_INC -I hxc/rt"
if [ "${HXC_SINGLE:-0}" != 0 ]; then
	$CC $RT_FLAGS "$OUT/prog.c" hxc/rt/rt*.c -lm ${RT_LIBS:-} -o "$OUT/$BIN"
else
	# chunks in parallel, unchanged ones reused (hxc/tools/cc-chunks.sh).
	# HXC_IDS=const (default except with tcc): the ids are #defines (ids.h) as
	# fast as the single file, but a change of an id (a new closure, type or
	# field name) recompiles every chunk; HXC_IDS=extern: const globals, about
	# 2% slower with clang -O2, an edit recompiles only the chunks it changes
	case "$CC" in tcc*|*/tcc*) IDS=extern ;; *) IDS=const ;; esac
	if [ "${HXC_IDS:-$IDS}" = const ]; then RT_FLAGS="$RT_FLAGS -DHXC_CONST_IDS"; fi
	CC="$CC" CFLAGS="$RT_FLAGS ${CFLAGS:-}" LIBS="-lm ${RT_LIBS:-}" sh hxc/tools/cc-chunks.sh "$OUT/prog_hxc" "$OUT/$BIN"
fi
# linear-memory wasm, compiled as C++ so try/catch uses wasm exception handling
if [ -n "${EMXX:-}" ]; then
	for f in hxc/rt/rt*.c; do emcc -O2 -w -c -fwasm-exceptions -DHXC_NO_NET -DHXC_NO_SSL -DHXC_NO_UV -I hxc/rt "$f" -o "$OUT/$(basename "$f" .c)_wasm.o"; done
	$EMXX -O2 -w -x c++ -fwasm-exceptions -I hxc/rt -c "$OUT/prog.c" -o "$OUT/prog_wasm.o"
	$EMXX -O2 -fwasm-exceptions -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sINITIAL_MEMORY=64MB -sSTACK_SIZE=8MB -sEXIT_RUNTIME=1 \
		"$OUT/prog_wasm.o" "$OUT"/rt*_wasm.o -o "$OUT/prog_linear.js"
fi
ls -l "$OUT/$BIN"
