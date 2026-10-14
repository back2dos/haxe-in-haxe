#!/bin/sh
# Runs the hxmc tool on an archive (stats on):
#   sh hxmc/tools/hxmc.sh <case> [main class] [hxmc arguments...]
#       a case of the test corpus (bin/hxmc-t/<case>/, written by hxmc/tools/run.py), output m
#   sh hxmc/tools/hxmc.sh <archive.zip> <main class> [hxmc arguments...]
#       any archive, output next to it (p)
# HXMC_TOOL picks the tool (default bin/hxmc/hxmc), HXMC_WRAP a wrapper
# (valgrind, gdb); HXMC_DUMP=<function> prints its Mir, ...
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
case=$1
shift
main=${1:-$case}
[ $# -gt 0 ] && shift
case $case in
*.zip) hxb=$case; out=$(dirname "$case")/p ;;
*) hxb=$ROOT/bin/hxmc-t/$case/prog.hxb.zip; out=$ROOT/bin/hxmc-t/$case/m ;;
esac
export HAXE_STD_PATH=$ROOT/haxe/std HXMC_STATS=1
ulimit -s unlimited 2>/dev/null || true
${HXMC_WRAP:-} "${HXMC_TOOL:-$ROOT/bin/hxmc/hxmc}" "$out" --hxb-lib "$hxb" -main "$main" --custom-target hxmc -D disable-parallelism "$@"
