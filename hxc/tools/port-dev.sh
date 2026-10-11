#!/bin/sh
# Builds the port with the native hxc tool for fast iteration on src/:
# bin/port/hih (the port's C in bin/port/hih_hxc/, compiled in chunks; only
# the chunks whose C changed are recompiled).
#
#   sh hxc/tools/port-dev.sh
#
# HXC_TOOL: the tool (default bin/hxc-dev/tool, see hxc/tools/dev-tool.sh; a
# tool built from another checkout works too: it only compiles this one's
# sources). CC: the C compiler (default clang -O2; tcc compiles in about a
# second, the port then runs about 2.5 times slower). The ids are const
# globals (not HXC_CONST_IDS), so a new name does not recompile every chunk.
# HAXE_STD_PATH: the upstream std (default haxe/std; set it in a worktree
# without the submodule).
set -eu
cd "$(dirname "$0")/../.."
TOOL=${HXC_TOOL:-bin/hxc-dev/tool}
if [ ! -x "$TOOL" ]; then
	echo "no hxc tool at $TOOL: sh hxc/tools/dev-tool.sh (or set HXC_TOOL)" >&2
	exit 1
fi
OUT=bin/port
mkdir -p "$OUT"
export HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std}
python3 hxc/tools/mkstd.py
ulimit -s unlimited 2>/dev/null || true
"$TOOL" "$OUT/hih" -cp src -main haxe.Main -cp runtime/js -D disable-parallelism \
	-cp bin/hxc/std --custom-target hxc > "$OUT/gen.log" 2>&1 || { cat "$OUT/gen.log"; exit 1; }
CC="${CC:-clang -O2}" CFLAGS="-w -fno-strict-aliasing -DHXC_NO_SSL -DHXC_NO_UV" \
	sh hxc/tools/cc-chunks.sh "$OUT/hih_hxc" "$OUT/hih"
