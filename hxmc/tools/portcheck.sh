#!/bin/sh
# The port built by hxmc compiles its own source to HXB; the archive must be
# identical to the reference compiler's (member by member).
#   sh hxmc/tools/portcheck.sh [hxmc arguments...]
# Needs bin/hxmc-t/port/prog.hxb.zip (the port's archive, written by the
# reference: haxe -cp src -cp hxc/js -cp bin/hxc/std -main haxe.Main
# --custom-target hxc=x --hxb <it> -D disable-parallelism --no-output) and
# bin/hxmc-t/self-ref.hxb (the reference's own self-compile to HXB).
# HXMC_TOOL picks the tool (default bin/hxmc-fast/hxmc); SMALL=1 also runs the
# port with a 256 KB nursery (missing or stale roots show).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
export HAXE_STD_PATH=$ROOT/haxe/std
T=${HXMC_TOOL:-bin/hxmc-fast/hxmc}
$T bin/hxmc-t/port/s --hxb-lib bin/hxmc-t/port/prog.hxb.zip -main haxe.Main --custom-target hxc -D disable-parallelism "$@" || exit 1
ls -l bin/hxmc-t/port/s
s=$(date +%s.%N)
bin/hxmc-t/port/s -cp src -main haxe.Main -D disable-parallelism --interp --no-output --hxb bin/hxmc-t/self-hxmc.hxb || { echo "self-compile FAILED"; exit 1; }
e=$(date +%s.%N)
echo "self-compile $(echo "$e - $s" | bc) s"
python3 -c "
import zipfile
a=zipfile.ZipFile('bin/hxmc-t/self-ref.hxb'); b=zipfile.ZipFile('bin/hxmc-t/self-hxmc.hxb')
na=sorted(n for n in a.namelist() if n.endswith('.hxb')); nb=sorted(n for n in b.namelist() if n.endswith('.hxb'))
d=sum(1 for n in na if n in nb and a.read(n)!=b.read(n))
print(len(na), 'modules', 'names equal' if na==nb else 'NAMES DIFFER', d, 'differ')"
if [ -n "${SMALL:-}" ]; then
	RT_MINOR_KB=256 bin/hxmc-t/port/s -cp src -main haxe.Main -D disable-parallelism --interp --no-output --hxb bin/hxmc-t/self-small.hxb || { echo "small-nursery self-compile FAILED"; exit 1; }
	a=$(unzip -p bin/hxmc-t/self-small.hxb | md5sum); b=$(unzip -p bin/hxmc-t/self-hxmc.hxb | md5sum)
	[ "$a" = "$b" ] && echo "small nursery: same" || echo "small nursery: DIFFERENT"
fi
