#!/bin/sh
# Runs the hxmc tool on a case of the test corpus (its cached archive in
# bin/hxmc-t/<case>/, written by hxmc/tools/run.py), development build:
#   sh hxmc/tools/hxmc.sh <case> [main class]
# with HXMC_DUMP=<function>, HXMC_ONLY=..., HXMC_SKIP=... as needed.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
case=$1
main=${2:-$1}
d=$ROOT/bin/hxmc-t/$case
export HAXE_STD_PATH=$ROOT/haxe/std HXMC_HYBRID=1 HXMC_RT=$ROOT/bin/hxmc/rt-dev HXMC_STATS=1 HXMC_RT_INCLUDE=$ROOT/hxc/rt
ulimit -s unlimited 2>/dev/null || true
"$ROOT/bin/hxmc/hxmc" "$d/m" --hxb-lib "$d/prog.hxb.zip" -main "$main" --custom-target hxc -D disable-parallelism
