#!/bin/sh
# EXPERIMENTAL: builds the backend tool, then compiles a program with it to C
# and to a native binary (CC, default tcc for fast builds; CC="gcc -O2" for
# speed; CC="cosmocc -O2" for a portable APE binary, see bench/COSMO.md).
# When EMXX is set (e.g. EMXX=em++), also to linear-memory wasm.
#   sh backend/build.sh [source dir] [main class]     (default: backend/bench Bench)
#   sh backend/build.sh port                          (the port itself: bin/backend/hih/hih)
#   CC="cosmocc -O2" BIN=hih.com sh backend/build.sh port
#   HXFLAGS="-D retain" VARIANT=-retain sh backend/build.sh
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
# backend/std: the hxc target's std (backend/std-hxc) with the Eval originals for macros
python3 backend/tools/mkstd.py
if [ -z "${SKIP_TOOL:-}" ]; then
	"$HAXE" -cp src -cp backend/src -main backend.Main -lib hxnodejs -cp bench/js-shims --js bin/backend/wbk.js -w -WDeprecated
fi
# hxnodejs's stdout flush fails on pipes, hence the file
HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std} node --stack-size=65500 bin/backend/wbk.js "$OUT/prog" \
	-cp backend/std $ARGS --custom-target hxc ${HXFLAGS:-} > "$OUT/wbk.log" 2>&1 || { cat "$OUT/wbk.log"; exit 1; }
# slots are read as int32/double/pointer through casts (FI/FD/FP): no strict aliasing
# without mbedtls/libuv: their natives fail when called (RT_LIBS="-lmbedtls -lmbedx509 -lmbedcrypto -luv" and RT_NO= to link them)
$CC -w -fno-strict-aliasing ${RT_NO--DHXC_NO_SSL -DHXC_NO_UV} -I backend/rt "$OUT/prog.c" backend/rt/rt*.c -lm ${RT_LIBS:-} -o "$OUT/$BIN"
# linear-memory wasm, compiled as C++ so try/catch uses wasm exception handling
if [ -n "${EMXX:-}" ]; then
	for f in backend/rt/rt*.c; do emcc -O2 -w -c -fwasm-exceptions -DHXC_NO_NET -DHXC_NO_SSL -DHXC_NO_UV -I backend/rt "$f" -o "$OUT/$(basename "$f" .c)_wasm.o"; done
	$EMXX -O2 -w -x c++ -fwasm-exceptions -I backend/rt -c "$OUT/prog.c" -o "$OUT/prog_wasm.o"
	$EMXX -O2 -fwasm-exceptions -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sINITIAL_MEMORY=64MB -sSTACK_SIZE=8MB -sEXIT_RUNTIME=1 \
		"$OUT/prog_wasm.o" "$OUT"/rt*_wasm.o -o "$OUT/prog_linear.js"
fi
ls -l "$OUT/$BIN"
