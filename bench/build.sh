#!/bin/sh
# Builds the translated compiler (haxe.Main) for each benchmark target.
# Usage: HAXE=haxe/haxe sh bench/build.sh [js] [hl] [hlc] [jvm] [cpp] [wasm]
# (wasm needs the hxc C output first: sh backend/build.sh port)
set -u
cd "$(dirname "$0")/.."
HAXE=${HAXE:-haxe/haxe}
OUT=bin/bench
mkdir -p "$OUT"
targets=${*:-js hl hlc jvm cpp}
for t in $targets; do
	start=$(date +%s)
	case $t in
		js) "$HAXE" -cp src -main haxe.Main -lib hxnodejs -cp bench/js-shims --js "$OUT/hih.js" ;;
		hl) "$HAXE" -cp runtime/hl -cp src -main haxe.Main --hl "$OUT/hih.hl" ;;
		hlc) # needs a compiler with the hl2c fix (HAXE_HLC) and HashLink headers (HL_INCLUDE);
			# HL_STATIC="libhl.a fmt.o ..." links the (patched) runtime statically
			rm -rf "$OUT/hlc" && "${HAXE_HLC:-$HAXE}" -cp runtime/hl -cp src -main haxe.Main --hl "$OUT/hlc/main.c" ;
			if [ -n "${HL_STATIC:-}" ]; then
				cc -O2 -std=c11 -w -o "$OUT/hih-hlc" -I "$OUT/hlc" -I "${HL_INCLUDE:-/usr/local/include}" "$OUT/hlc/main.c" $HL_STATIC -lpng16 -lturbojpeg -lvorbisfile -lz -lm -lpthread -ldl
			else
				cc -O2 -std=c11 -w -o "$OUT/hih-hlc" -I "$OUT/hlc" -I "${HL_INCLUDE:-/usr/local/include}" "$OUT/hlc/main.c" -L/usr/local/lib -lhl -l:fmt.hdll -lm -Wl,-rpath,/usr/local/lib
			fi ;;
		jvm) "$HAXE" -cp src -main haxe.Main -lib hxjava --jvm "$OUT/hih.jar" ;;
		cpp) # CPP_FLAGS="-D HXCPP_SINGLE_THREAD_MARK" needs bench/hxcpp-single-thread-mark.patch
			"$HAXE" -cp src -main haxe.Main -lib hxcpp -D HXCPP_M64 ${CPP_FLAGS:-} --cpp "$OUT/cpp" ;;
		wasm) # the hxc C output (sh backend/build.sh port) built like site/build.sh's WebAssembly
			# (wasm64, wasm exceptions), but for Node with direct file system access (NODERAWFS);
			# needs em++ on PATH (. ~/emsdk/emsdk_env.sh)
			C=bin/backend/hih/prog.c
			F="-O2 -w -fno-strict-aliasing -fwasm-exceptions -sMEMORY64=1 -I backend/rt"
			RT="rt rt_dyn rt_std rt_str rt_sys rt_net rt_ssl rt_uv rt_thread rt_census"
			mkdir -p "$OUT/wasm/obj"
			# Emscripten's ENV doesn't inherit the process environment (HAXE_STD_PATH)
			echo 'Module.preRun = [() => { for (const k in process.env) ENV[k] = process.env[k]; }];' > "$OUT/wasm/env.js"
			em++ -x c++ $F -c "$C" -o "$OUT/wasm/obj/prog.o" &&
			for f in $RT; do em++ -x c++ $F -DHXC_NO_NET -DHXC_NO_SSL -DHXC_NO_UV -c "backend/rt/$f.c" -o "$OUT/wasm/obj/$f.o" || exit 1; done &&
			em++ $F -o "$OUT/wasm/hih.js" "$OUT/wasm/obj/prog.o" $(for f in $RT; do echo "$OUT/wasm/obj/$f.o"; done) \
				-sENVIRONMENT=node -sNODERAWFS=1 --pre-js "$OUT/wasm/env.js" \
				-sEXIT_RUNTIME=1 -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sMAXIMUM_MEMORY=8GB -sSTACK_SIZE=8MB ;;
		*) echo "unknown target $t" >&2; exit 2 ;;
	esac > "$OUT/build-$t.log" 2>&1
	echo "$t exit=$? $(( $(date +%s) - start ))s"
done
