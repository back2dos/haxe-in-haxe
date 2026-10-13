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
*) echo "mkrt: unknown target $target" >&2; exit 1 ;;
esac
out=$ROOT/bin/hxmc/rt/$target
mkdir -p "$out/obj"
CFLAGS="-O2 -g0 -w -fno-strict-aliasing -fno-pie -fno-pic -DHXC_NO_SSL -DHXC_NO_UV -DRT_CALL_ON_STACK -I $ROOT/hxc/rt"
objs=
for f in rt rt_dyn rt_std rt_str rt_sys rt_net rt_ssl rt_uv rt_thread rt_census; do
	$ZIG cc -target $triple $CFLAGS -c "$ROOT/hxc/rt/$f.c" -o "$out/obj/$f.o" &
	objs="$objs $out/obj/$f.o"
done
wait
# the C library: zig builds it on first use; a static link of a stub tells where
printf 'int main(void){return 0;}\n' > "$out/obj/stub.c"
# (twice: the first run may build the C library and name temporary paths)
$ZIG cc -target $triple -static -O2 "$out/obj/stub.c" -o "$out/obj/stub"
line=$($ZIG cc -target $triple -static -O2 -v "$out/obj/stub.c" -o "$out/obj/stub" 2>&1 | grep 'ld.lld' | head -1)
crt1=$(echo "$line" | tr ' ' '\n' | grep '/crt1.o$')
libs=$(echo "$line" | tr ' ' '\n' | grep -E '/lib(c|zigc|compiler_rt)\.a$' | tr '\n' ' ')
# what generated code calls in the C library besides the runtime (MirBuild)
undef="-u _setjmp -u memset -u memcpy -u fmod -u floor -u ceil -u sin -u cos -u tan -u asin -u acos -u atan -u atan2 -u exp -u log -u pow -u sqrt"
ld.lld -r --strip-debug -o "$out/rt.o" $undef "$crt1" $objs --start-group $libs --end-group
ls -l "$out/rt.o"
