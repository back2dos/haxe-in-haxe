#!/bin/sh
# EXPERIMENTAL: builds the backend tool and compiles a program with it to C,
# then to a native binary (CC, default tcc for fast builds; CC="gcc -O2" for
# speed). When EMXX is set (e.g. EMXX=em++), also to linear-memory wasm.
#   sh backend/build.sh [source dir] [main class]     (default: backend/bench Bench)
#   HXFLAGS="-D retain" VARIANT=-retain sh backend/build.sh
set -eu
cd "$(dirname "$0")/.."
HAXE=${HAXE:-haxe/haxe}
CC=${CC:-tcc}
SRC=${1:-backend/bench}
MAIN=${2:-Bench}
OUT=bin/backend/$MAIN${VARIANT:-}
mkdir -p "$OUT"
if [ -z "${SKIP_TOOL:-}" ]; then
	"$HAXE" -cp src -cp backend/src -main backend.Main -lib hxnodejs -cp bench/js-shims --js bin/backend/wbk.js -w -WDeprecated
fi
# hxnodejs's stdout flush fails on pipes, hence the file
HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std} node --stack-size=65500 bin/backend/wbk.js "$OUT/prog" \
	-cp "$SRC" -main "$MAIN" ${HXFLAGS:-} > "$OUT/wbk.log" 2>&1 || { cat "$OUT/wbk.log"; exit 1; }
$CC -w -I backend/rt "$OUT/prog.c" backend/rt/rt.c -o "$OUT/prog_c"
# linear-memory wasm, compiled as C++ so try/catch uses wasm exception handling
if [ -n "${EMXX:-}" ]; then
	emcc -O2 -w -c -fwasm-exceptions -I backend/rt backend/rt/rt.c -o "$OUT/rt_wasm.o"
	$EMXX -O2 -w -x c++ -fwasm-exceptions -I backend/rt -c "$OUT/prog.c" -o "$OUT/prog_wasm.o"
	$EMXX -O2 -fwasm-exceptions -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=4GB -sINITIAL_MEMORY=64MB -sSTACK_SIZE=8MB -sEXIT_RUNTIME=1 \
		"$OUT/prog_wasm.o" "$OUT/rt_wasm.o" -o "$OUT/prog_linear.js"
fi
ls -l "$OUT/prog_c"
