#!/bin/sh
# Builds the runtime object of an hxmc target (hxmc/README.md, "Runtime"):
# hxc/rt compiled by zig cc -O2 for the target, partially linked (ld -r) with
# the parts of the C library it and generated code use, into one relocatable
# object bin/hxmc/rt/<target>/rt.o, which hxmc's linker then links with the
# program (and lays out once, see Link.hx).
#   sh hxmc/tools/mkrt.sh linux-x86_64
set -eu
target=$1
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ZIG=${ZIG:-zig}
case $target in
linux-x86_64) triple=x86_64-linux-musl ;;
linux-arm64) triple=aarch64-linux-musl ;;
windows-x86_64) triple=x86_64-windows-gnu ;;
windows-arm64) triple=aarch64-windows-gnu ;;
macos-x86_64) triple=x86_64-macos ;;
macos-arm64) triple=aarch64-macos ;;
*) echo "mkrt: unknown target $target" >&2; exit 1 ;;
esac
out=$ROOT/bin/hxmc/rt/$target
mkdir -p "$out/obj"
CFLAGS="-O2 -g0 -w -fno-strict-aliasing -fno-pie -fno-pic -ffunction-sections -fdata-sections -DHXC_NO_SSL -DHXC_NO_UV -DRT_CALL_ON_STACK -I $ROOT/hxc/rt"
files="rt rt_dyn rt_std rt_str rt_sys rt_net rt_ssl rt_uv rt_thread rt_census"
case $target in
windows-*)
	CFLAGS="-O2 -g0 -w -fno-strict-aliasing -DHXC_NO_SSL -DHXC_NO_UV -I $ROOT/hxc/rt"
	files="$files rt_win rt_sys_win rt_net_win" ;;
macos-*)
	# position-independent (macOS executables are), against libSystem;
	# arm64 macOS calls main on its own stack without ucontext already
	CFLAGS="-O2 -g0 -w -fno-strict-aliasing -mmacosx-version-min=$([ $target = macos-arm64 ] && echo 11.0 || echo 10.15) -DHXC_NO_SSL -DHXC_NO_UV -I $ROOT/hxc/rt" ;;
esac
objs=
for f in $files; do
	$ZIG cc -target $triple $CFLAGS -c "$ROOT/hxc/rt/$f.c" -o "$out/obj/$f.o" &
	objs="$objs $out/obj/$f.o"
done
# the slow paths of generated code (rthxmc.c)
$ZIG cc -target $triple $CFLAGS -c "$ROOT/hxmc/tools/rthxmc.c" -o "$out/obj/rthxmc.o" &
objs="$objs $out/obj/rthxmc.o"
wait
# what generated code calls in the C library besides the runtime (MirBuild)
libm="memset memcpy fmod floor ceil sin cos tan asin acos atan atan2 exp log pow sqrt"
case $target in
macos-*)
	# the runtime's Mach-O objects merged into one (hxmc --mkrt-macho); the
	# C library is libSystem, bound at load time
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt-macho "$out/rt.o" $objs
	ls -l "$out/rt.o"
	exit 0 ;;
windows-*)
	# the runtime's own COFF objects, the C runtime's startup object and the
	# archives zig links (the MinGW-w64 libraries, compiler-rt, the import
	# libraries of the UCRT and the Windows DLLs the runtime uses), selected
	# and resolved by hxmc itself (hxmc --mkrt)
	printf 'int main(void){return 0;}\n' > "$out/obj/stub.c"
	WINLIBS="-lws2_32 -liphlpapi -luserenv -lpsapi -ldbghelp -lole32 -lshell32 -luser32 -ladvapi32 -lcrypt32 -lbcrypt"
	$ZIG cc -target $triple -O2 "$out/obj/stub.c" -o "$out/obj/stub.exe" $WINLIBS
	line=$($ZIG cc -target $triple -O2 -v "$out/obj/stub.c" -o "$out/obj/stub.exe" $WINLIBS 2>&1 | grep 'lld-link' | head -1)
	inputs=$(echo "$line" | tr ' ' '\n' | grep -E '\.(obj|lib)$' | grep -v '^-' | grep -v '/stub.obj$' | tr '\n' ' ')
	sj=_setjmp; [ $target = windows-arm64 ] && sj=__mingw_setjmp
	undef="-u mainCRTStartup -u $sj -u _tls_index -u _tls_used -x main"
	for f in $libm; do undef="$undef -u $f"; done
	"${HXMC:-$ROOT/bin/hxmc/hxmc}" --mkrt "$out/rt.o" $objs $inputs $undef
	ls -l "$out/rt.o"
	exit 0 ;;
esac
# the C library: zig builds it on first use; a static link of a stub tells where
printf 'int main(void){return 0;}\n' > "$out/obj/stub.c"
# (twice: the first run may build the C library and name temporary paths)
$ZIG cc -target $triple -static -O2 "$out/obj/stub.c" -o "$out/obj/stub"
line=$($ZIG cc -target $triple -static -O2 -v "$out/obj/stub.c" -o "$out/obj/stub" 2>&1 | grep 'ld.lld' | head -1)
crt1=$(echo "$line" | tr ' ' '\n' | grep '/crt1.o$')
libs=$(echo "$line" | tr ' ' '\n' | grep -E '/lib(c|zigc|compiler_rt)\.a$' | tr '\n' ' ')
undef="-u _setjmp"
for f in $libm; do undef="$undef -u $f"; done
# word-at-a-time memcmp and bcmp in place of musl's byte loops (rtlibc.c)
$ZIG cc -target $triple -O2 -g0 -ffreestanding -fno-builtin -ffunction-sections -c "$ROOT/hxmc/tools/rtlibc.c" -o "$out/obj/rtlibc.o"
objs="$objs $out/obj/rtlibc.o"
ld.lld -r --strip-debug -o "$out/rt.o" $undef "$crt1" $objs --start-group $libs --end-group
ls -l "$out/rt.o"
