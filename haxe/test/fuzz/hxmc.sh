#!/bin/sh
# The hxmc target of the fuzzer: compiles a program to a native executable
# <out>/prog with the hxmc tool (bin/hxmc/hxmc, `make hxmc`), for the host.
#   sh test/fuzz/hxmc.sh <out dir> <haxe arguments ...>
set -eu
OUT=$1
shift
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# the hxmc target's std, as the Makefile makes it
[ -f "$ROOT/bin/hxmc/std/.stamp" ] || (cd "$ROOT" && python3 hxmc/tools/mkstd.py)
HAXE_STD_PATH=${HAXE_STD_PATH:-$ROOT/haxe/std} "$ROOT/bin/hxmc/hxmc" "$OUT/prog" "$@" \
	-cp "$ROOT/bin/hxmc/std" --custom-target hxmc > "$OUT/hxmc.log" 2>&1 || { cat "$OUT/hxmc.log"; exit 1; }
cat "$OUT/hxmc.log"
