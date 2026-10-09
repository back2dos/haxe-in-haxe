#!/bin/sh
# EXPERIMENTAL: builds the backend tool and compiles backend/bench/Bench.hx
# with it to C (native) and WasmGC. Needs Node, gcc and Binaryen (wasm-opt).
#   sh backend/build.sh [Program.hx dir] [Main class]
set -eu
cd "$(dirname "$0")/.."
HAXE=${HAXE:-haxe/haxe}
BINARYEN=${BINARYEN:-/root/emsdk/upstream/bin}
SRC=${1:-backend/bench}
MAIN=${2:-Bench}
OUT=bin/backend/$MAIN${VARIANT:-}
mkdir -p "$OUT"
"$HAXE" -cp src -cp backend/src -main backend.Main -lib hxnodejs -cp bench/js-shims --js bin/backend/wbk.js -w -WDeprecated
# hxnodejs's stdout flush fails on pipes, hence the file
HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std} node --stack-size=65500 bin/backend/wbk.js "$OUT/prog" -cp "$SRC" -main "$MAIN" ${HXFLAGS:-} > "$OUT/wbk.log" 2>&1 || { cat "$OUT/wbk.log"; exit 1; }
${CC:-gcc} -O2 -w -I backend/rt "$OUT/prog.c" backend/rt/rt.c -o "$OUT/prog_c"
F="--enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory --enable-multivalue --enable-sign-ext --enable-nontrapping-float-to-int"
"$BINARYEN/wasm-as" $F "$OUT/prog.wat" -o "$OUT/prog.raw.wasm"
"$BINARYEN/wasm-opt" $F -O3 "$OUT/prog.raw.wasm" -o "$OUT/prog.wasm"
ls -l "$OUT/prog_c" "$OUT/prog.wasm"
