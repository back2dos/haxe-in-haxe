#!/bin/sh
# The native backend tool for fast iteration on the lowering and the runtime:
# bin/hxc-dev/tool (the port + C backend, built with clang -O2).
#
#   sh hxc/tools/dev-tool.sh
#
# The tool regenerates its own C (about 10 s) and the changed chunks are
# recompiled (objects reused, hxc/tools/cc-chunks.sh). Without a tool yet,
# the JS build (bin/hxc/wbk.js, about 65 s) generates the first one.
# A change to the lowering takes effect in programs the new tool compiles; the
# tool itself is compiled by the previous one (run twice to rebuild it with
# its own output). TOOL_CC overrides the C compiler (default clang -O2).
set -eu
cd "$(dirname "$0")/../.."
T=bin/hxc-dev
HAXE=${HAXE:-haxe/haxe}
mkdir -p "$T"
python3 hxc/tools/mkstd.py
ulimit -s unlimited 2>/dev/null || true
ARGS="-cp src -cp hxc/src -cp hxc/js -cp bin/hxc/std -main backend.Main -D disable-parallelism --custom-target hxc"
if [ -x "$T/tool" ]; then
	HAXE_STD_PATH=$PWD/haxe/std "$T/tool" "$T/tool" $ARGS > "$T/gen.log" 2>&1 || { cat "$T/gen.log"; exit 1; }
else
	"$HAXE" -cp src -cp hxc/src -main backend.Main -lib hxnodejs -cp hxc/js --js bin/hxc/wbk.js -w -WDeprecated
	HAXE_STD_PATH=$PWD/haxe/std node --stack-size=65500 bin/hxc/wbk.js "$T/tool" $ARGS > "$T/gen.log" 2>&1 || { cat "$T/gen.log"; exit 1; }
fi
# the running tool is replaced: write the new binary next to it, then move it
CC="${TOOL_CC:-clang -O2}" CFLAGS="-w -fno-strict-aliasing -DHXC_NO_SSL -DHXC_NO_UV -DHXC_CONST_IDS" \
	sh hxc/tools/cc-chunks.sh "$T/tool_hxc" "$T/tool.new"
mv "$T/tool.new" "$T/tool"
