#!/bin/sh
# Assembles the package from the repository's builds (README.md):
#   packages/haxe/build.sh        (from the repository root: make hxmc rt std first)
# lib/haxe.wasm: the compiler with hxmc as a wasm32-wasi module (hxmc.HaxeMain)
# lib/haxe/std: haxe/std with hxmc/Init.hx; lib/haxe/hxmc-std: bin/hxmc/std;
# lib/haxe/rt/<target>: the runtime objects; lib/haxe/src: the compiler's
# sources (port, hxmc), for the native build on the user's machine
set -e
cd "$(dirname "$0")/../.."
P=packages/haxe
L=$P/lib/haxe
ulimit -s unlimited 2>/dev/null || true
mkdir -p bin/npm
bin/hxmc/hxmc bin/npm/haxe.wasm -cp src -cp hxmc/src -main hxmc.HaxeMain -D disable-parallelism \
	-cp bin/hxmc/std --custom-target hxmc -D hxmc.target=wasm32-wasi > bin/npm/haxe.wasm.log 2>&1 \
	|| { cat bin/npm/haxe.wasm.log; exit 1; }
cp bin/npm/haxe.wasm $P/lib/haxe.wasm
rm -rf $L
mkdir -p $L/rt $L/src
cp -r haxe/std $L/std
cp -r $P/src/hxmc $L/std/
cp -r bin/hxmc/std $L/hxmc-std
rm -f $L/hxmc-std/.stamp
for d in bin/hxmc/rt/*/; do
	t=$(basename "$d")
	mkdir -p $L/rt/$t
	cp "$d/rt.o" "$d/ssl.o" "$d/uv.o" $L/rt/$t/
done
cp -r src $L/src/port
cp -r hxmc/src $L/src/hxmc
du -sh $P/lib/haxe.wasm $L/*
