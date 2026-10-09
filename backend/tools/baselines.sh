#!/bin/sh
# EXPERIMENTAL: builds the comparison targets for a benchmark from the same
# source: HL/C native, HL/C -> wasm (Emscripten, like bench/build-wasm.sh)
# and JS. Needs HAXE_HLC (a haxe with the hl2c fix), HL_SRC, emsdk and the
# runtime objects from bench/build-wasm.sh in bin/bench/wasm/obj.
#   VARIANT=-retain HXFLAGS="-D retain" sh backend/tools/baselines.sh
set -eu
cd "$(dirname "$0")/../.."
SRC=${1:-backend/bench}
MAIN=${2:-Bench}
OUT=bin/backend/$MAIN${VARIANT:-}
mkdir -p "$OUT"
rm -rf "$OUT/hlc"
"${HAXE_HLC:-/root/haxe-hlc/haxe}" -cp "$SRC" -main "$MAIN" ${HXFLAGS:-} --hl "$OUT/hlc/main.c" > /dev/null 2>&1 || true # the haxelib build step fails
test -f "$OUT/hlc/main.c"
gcc -O2 -std=c11 -w -o "$OUT/hlc_native" -I "$OUT/hlc" -I "${HL_SRC:-/opt/hlsrc/hlm}/src" "$OUT/hlc/main.c" -L/usr/local/lib -lhl -lm -Wl,-rpath,/usr/local/lib
command -v emcc > /dev/null || PATH=${EMSDK:-/root/emsdk}/upstream/emscripten:$PATH
F="-O2 -std=c11 -w -DHL_NO_THREADS -fwasm-exceptions -sSUPPORT_LONGJMP=wasm"
emcc $F -I "${HL_SRC:-/opt/hlsrc/hlm}/src" -I "$OUT/hlc" -c "$OUT/hlc/main.c" -o "$OUT/hlc/main.o"
emcc -O2 -g2 "$OUT/hlc/main.o" bin/bench/wasm/obj/*.o -fwasm-exceptions -sSUPPORT_LONGJMP=wasm -sNODERAWFS=1 \
	-sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=256MB -sMAXIMUM_MEMORY=4GB -sSTACK_SIZE=8MB \
	-sBINARYEN_EXTRA_PASSES=--spill-pointers -sEXIT_RUNTIME=1 -o "$OUT/hlc_wasm.js" 2> /dev/null
"$(dirname "$(command -v emcc)")/../bin/wasm-opt" --mvp-features --enable-bulk-memory --enable-bulk-memory-opt --enable-call-indirect-overlong --enable-exception-handling --enable-multivalue --enable-mutable-globals --enable-nontrapping-float-to-int --enable-reference-types --enable-sign-ext --strip-debug --strip-producers "$OUT/hlc_wasm.wasm" -o "$OUT/hlc_wasm.wasm"
"${HAXE:-haxe/haxe}" -cp "$SRC" -main "$MAIN" ${HXFLAGS:-} --js "$OUT/js.js"
ls -l "$OUT"
