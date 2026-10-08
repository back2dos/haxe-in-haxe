#!/bin/sh
# Builds the translated compiler (haxe.Main) for each benchmark target.
# Usage: HAXE=haxe/haxe sh bench/build.sh [js] [hl] [hlc] [jvm] [cpp]
set -u
cd "$(dirname "$0")/.."
HAXE=${HAXE:-haxe/haxe}
OUT=bin/bench
mkdir -p "$OUT"
targets=${*:-js hl hlc jvm cpp}
for t in $targets; do
	start=$(date +%s)
	case $t in
		js) "$HAXE" -cp bench/js-shims -cp src -main haxe.Main -lib hxnodejs --js "$OUT/hih.js" ;;
		hl) "$HAXE" -cp runtime/hl -cp src -main haxe.Main --hl "$OUT/hih.hl" ;;
		hlc) # needs a compiler with the hl2c fix (HAXE_HLC) and HashLink headers (HL_INCLUDE)
			rm -rf "$OUT/hlc" && "${HAXE_HLC:-$HAXE}" -cp runtime/hl -cp src -main haxe.Main --hl "$OUT/hlc/main.c" ;
			[ -f "$OUT/hlc/main.c" ] && cc -O2 -std=c11 -w -g -o "$OUT/hih-hlc" -I "$OUT/hlc" -I "${HL_INCLUDE:-/usr/local/include}" "$OUT/hlc/main.c" -L/usr/local/lib -lhl -l:fmt.hdll -lm -Wl,-rpath,/usr/local/lib ;;
		jvm) "$HAXE" -cp src -main haxe.Main -lib hxjava --jvm "$OUT/hih.jar" ;;
		cpp) "$HAXE" -cp src -main haxe.Main -lib hxcpp -D HXCPP_M64 --cpp "$OUT/cpp" ;;
		*) echo "unknown target $t" >&2; exit 2 ;;
	esac > "$OUT/build-$t.log" 2>&1
	echo "$t exit=$? $(( $(date +%s) - start ))s"
done
