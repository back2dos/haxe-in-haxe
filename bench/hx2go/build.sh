#!/bin/sh
# Builds the translated compiler with the hx2go custom target (Go) and patches
# the generated Go until it builds and runs (see bench/README.md).
# Usage: HAXE=haxe/haxe sh bench/hx2go/build.sh
# Needs: haxelib hx2go (git 2739b6c), go, python3.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HAXE=$(cd "$ROOT" && realpath "${HAXE:-haxe/haxe}")
T="$ROOT/bench/hx2go"
W="$ROOT/bin/bench/go-work"
rm -rf "$W" && mkdir -p "$W/bin"
cp -r "$ROOT/src" "$W/src"
# Source-level workarounds for hx2go bugs (exception field named `error`,
# enum-valued default arguments, catch(e:Dynamic) + isOfType, nullable function values).
(cd "$W" && patch -s -p1 < "$T/source.patch")
# hx2go runs `haxe` from PATH
ln -s "$HAXE" "$W/bin/haxe"
(cd "$W" && PATH="$W/bin:$PATH" HAXE_STD_PATH="$ROOT/haxe/std" haxe -cp src -main haxe.Main -L hx2go --custom-target go=out > gen.log 2>&1)
cd "$W/out/main"
# Go positions instead of Haxe positions in compiler errors
for f in *.go; do sed -i -e '/^\/\/line /d' -e 's#/\*line [^*]*\*/##g' "$f"; done
python3 "$T/manual.py"       # hand fixes and runtime patches
python3 "$T/trybreak.py"     # break/continue inside try bodies
python3 "$T/tryreturn.py"    # return inside try bodies
python3 "$T/autofix.py"      # rule-based fixes for the remaining Go compile errors
python3 "$T/staticorder.py"  # static initialization order
go build -o "$ROOT/bin/bench/hih-go" .
echo "built $ROOT/bin/bench/hih-go"
