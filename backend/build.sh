#!/bin/sh
# EXPERIMENTAL: builds the backend tool, then compiles a program with it to C
# and to a native binary (CC, default tcc for fast builds; CC="gcc -O2" for
# speed; CC="cosmocc -O2" for a portable APE binary, see bench/COSMO.md).
# When EMXX is set (e.g. EMXX=em++), also to linear-memory wasm.
#   sh backend/build.sh [source dir] [main class]     (default: backend/bench Bench)
#   sh backend/build.sh port                          (the port itself: bin/backend/hih/hih)
#   CC="cosmocc -O2" BIN=hih.com sh backend/build.sh port
#   CC="cosmocc -O2" RT_DEPS=bin/cosmo-deps BIN=hih.com sh backend/build.sh port   (with mbedtls/libuv: backend/tools/cosmo-deps.sh)
#   HXFLAGS="-D retain" VARIANT=-retain sh backend/build.sh
# The C is written in chunks to $OUT/prog_hxc/ and compiled in parallel, reusing
# the objects of unchanged chunks (backend/tools/cc-chunks.sh: JOBS, CFLAGS;
# CFLAGS=-DHXC_CONST_IDS folds the ids, CC="clang -O2 -flto=thin" for ThinLTO);
# HXC_SINGLE=1 writes and compiles one file $OUT/prog.c instead; HXC_CHUNK_KB
# sets the chunk size (default 384).
set -eu
cd "$(dirname "$0")/.."
HAXE=${HAXE:-haxe/haxe}
CC=${CC:-tcc}
if [ "${1:-}" = port ]; then
	OUT=bin/backend/hih
	ARGS="-cp src -main haxe.Main -cp bench/js-shims -D disable-parallelism"
	BIN=${BIN:-hih}
else
	MAIN=${2:-Bench}
	OUT=bin/backend/$MAIN${VARIANT:-}
	ARGS="-cp ${1:-backend/bench} -main $MAIN"
	BIN=prog_c
fi
mkdir -p "$OUT"
# EMXX builds from the single file
if [ -n "${EMXX:-}" ]; then HXC_SINGLE=1; fi
export HXC_SINGLE=${HXC_SINGLE:-0}
# backend/std: the hxc target's std (backend/std-hxc) with the Eval originals for macros
# (given last: the last class path wins over earlier ones, e.g. bench/js-shims)
python3 backend/tools/mkstd.py
if [ -z "${SKIP_TOOL:-}" ]; then
	"$HAXE" -cp src -cp backend/src -main backend.Main -lib hxnodejs -cp bench/js-shims --js bin/backend/wbk.js -w -WDeprecated
fi
# hxnodejs's stdout flush fails on pipes, hence the file
HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std} node --stack-size=65500 bin/backend/wbk.js "$OUT/prog" \
	$ARGS -cp backend/std --custom-target hxc ${HXFLAGS:-} > "$OUT/wbk.log" 2>&1 || { cat "$OUT/wbk.log"; exit 1; }
# slots are read as int32/double/pointer through casts (FI/FD/FP): no strict aliasing
# without mbedtls/libuv: their natives fail when called (RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" and RT_NO= to link them;
# with cosmocc, RT_DEPS=bin/cosmo-deps links the static libraries of backend/tools/cosmo-deps.sh)
RT_INC=
if [ -n "${RT_DEPS:-}" ]; then
	RT_NO=${RT_NO-}
	RT_INC="-I$RT_DEPS/include"
	RT_LIBS="-L$RT_DEPS/lib -lmbedtls -lmbedx509 -lmbedcrypto -luv ${RT_LIBS:-}"
fi
RT_FLAGS="-w -fno-strict-aliasing ${RT_NO--DHXC_NO_SSL -DHXC_NO_UV} $RT_INC -I backend/rt"
if [ "${HXC_SINGLE:-0}" != 0 ]; then
	$CC $RT_FLAGS "$OUT/prog.c" backend/rt/rt*.c -lm ${RT_LIBS:-} -o "$OUT/$BIN"
else
	# chunks in parallel, unchanged ones reused (backend/tools/cc-chunks.sh)
	CC="$CC" CFLAGS="$RT_FLAGS ${CFLAGS:-}" LIBS="-lm ${RT_LIBS:-}" sh backend/tools/cc-chunks.sh "$OUT/prog_hxc" "$OUT/$BIN"
fi
# linear-memory wasm, compiled as C++ so try/catch uses wasm exception handling
if [ -n "${EMXX:-}" ]; then
	for f in backend/rt/rt*.c; do emcc -O2 -w -c -fwasm-exceptions -DHXC_NO_NET -DHXC_NO_SSL -DHXC_NO_UV -I backend/rt "$f" -o "$OUT/$(basename "$f" .c)_wasm.o"; done
	$EMXX -O2 -w -x c++ -fwasm-exceptions -I backend/rt -c "$OUT/prog.c" -o "$OUT/prog_wasm.o"
	$EMXX -O2 -fwasm-exceptions -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sINITIAL_MEMORY=64MB -sSTACK_SIZE=8MB -sEXIT_RUNTIME=1 \
		"$OUT/prog_wasm.o" "$OUT"/rt*_wasm.o -o "$OUT/prog_linear.js"
fi
ls -l "$OUT/$BIN"
