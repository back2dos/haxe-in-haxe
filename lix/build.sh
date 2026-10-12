#!/bin/sh
# Builds lix (the lix client and haxeshim, lix/src) with hxc: bin/lix/lix, and
# bin/lix/haxe, bin/lix/haxelib, bin/lix/neko linking to it (the binary acts as
# the command it is invoked as, see lix/src/lix/cli/Main.hx).
#
#   sh lix/build.sh
#   CC="clang -O2" sh lix/build.sh                 (default)
#   CC=tcc sh lix/build.sh                          (fast compile)
#   CC="cosmocc -O2" RT_DEPS=bin/cosmo-deps BIN=lix.com sh lix/build.sh   (portable APE, hxc/tools/cosmo-deps.sh)
#
# Needs the native backend tool (TOOL, default bin/hxc-dev/tool: sh hxc/tools/dev-tool.sh),
# haxe/std, libuv and mbedtls (the system's, or RT_DEPS), and hxcoro: HXCORO=<checkout>, or
# a checkout of HXCORO_REV made into bin/lix/hxcoro.
set -eu
cd "$(dirname "$0")/.."
OUT=${OUT:-bin/lix}
TOOL=${TOOL:-bin/hxc-dev/tool}
CC=${CC:-clang -O2}
BIN=${BIN:-lix}
HXCORO_REV=4b1a4d49542c578dc184297b75d125093ca444d2
mkdir -p "$OUT"
if [ -z "${HXCORO:-}" ]; then
	HXCORO=$OUT/hxcoro
	if [ "$(git -C "$HXCORO" rev-parse HEAD 2>/dev/null || true)" != "$HXCORO_REV" ]; then
		rm -rf "$HXCORO"
		git init -q "$HXCORO"
		git -C "$HXCORO" fetch -q --depth 1 https://github.com/HaxeFoundation/hxcoro.git "$HXCORO_REV"
		git -C "$HXCORO" checkout -q FETCH_HEAD
	fi
fi
if [ ! -x "$TOOL" ]; then sh hxc/tools/dev-tool.sh; fi
python3 hxc/tools/mkstd.py
ulimit -s unlimited 2>/dev/null || true
HAXE_STD_PATH=${HAXE_STD_PATH:-$PWD/haxe/std} "$TOOL" "$OUT/lix" -cp lix/src -cp "$HXCORO/src" -cp bin/hxc/std \
	-main lix.cli.Main -D no-deprecation-warnings --custom-target hxc ${HXFLAGS:-} > "$OUT/gen.log" 2>&1 || { cat "$OUT/gen.log"; exit 1; }
RT_INC=
RT_LIBS=${RT_LIBS:-"-lmbedtls -lmbedx509 -lmbedcrypto -luv"}
if [ -n "${RT_DEPS:-}" ]; then
	RT_INC="-I$RT_DEPS/include"
	RT_LIBS="-L$RT_DEPS/lib $RT_LIBS"
fi
case "$CC" in tcc*|*/tcc*) IDS= ;; *) IDS=-DHXC_CONST_IDS ;; esac
CC="$CC" CFLAGS="-w -fno-strict-aliasing $IDS $RT_INC -I hxc/rt ${CFLAGS:-}" LIBS="-lm $RT_LIBS" \
	sh hxc/tools/cc-chunks.sh "$OUT/lix_hxc" "$OUT/$BIN"
for cmd in haxe haxelib neko; do ln -sf "$BIN" "$OUT/$cmd"; done
ls -l "$OUT/$BIN"
