#!/bin/sh
# The port built by hxmc compiles its own source to HXB; the archive must be
# identical to the reference compiler's (member by member).
#   sh hxmc/tools/portcheck.sh [hxmc arguments...]
# Writes (once, then when src/ is newer) bin/hxmc-t/port/prog.hxb.zip (the
# port's archive, by the reference: haxe -cp src -cp bin/hxmc/std -main
# haxe.Main --custom-target hxmc=x --hxb <it> -D disable-parallelism
# --no-output) and bin/hxmc-t/self-ref.hxb (the reference's own self-compile
# to HXB). HXMC_TOOL picks the tool (default bin/hxmc/hxmc); SMALL=1 also runs
# the port with a 256 KB nursery (missing or stale roots show).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
export HAXE_STD_PATH=$ROOT/haxe/std
T=${HXMC_TOOL:-bin/hxmc/hxmc}
mkdir -p bin/hxmc-t/port
new=$(find src -name '*.hx' -newer bin/hxmc-t/port/prog.hxb.zip 2>/dev/null | head -1)
if [ ! -f bin/hxmc-t/port/prog.hxb.zip ] || [ -n "$new" ]; then
	haxe/haxe -cp src -cp bin/hxmc/std -main haxe.Main --custom-target hxmc=bin/hxmc-t/port/x --hxb bin/hxmc-t/port/prog.hxb.zip -D disable-parallelism --no-output || exit 1
fi
new=$(find src -name '*.hx' -newer bin/hxmc-t/self-ref.hxb 2>/dev/null | head -1)
if [ ! -f bin/hxmc-t/self-ref.hxb ] || [ -n "$new" ]; then
	haxe/haxe -cp src -main haxe.Main -D disable-parallelism --interp --no-output --hxb bin/hxmc-t/self-ref.hxb || exit 1
fi
$T bin/hxmc-t/port/s --hxb-lib bin/hxmc-t/port/prog.hxb.zip -main haxe.Main --custom-target hxmc -D disable-parallelism "$@" || exit 1
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
