#!/bin/sh
# Builds the fuzzer with hxc (hxc/build.sh) to bin/fuzz/fuzz.
# CC defaults to clang -O2, whose OS threads let -j N run workers in parallel
# (with tcc the green threads serialize them).
#   sh test/fuzz/build.sh
set -eu
cd "$(dirname "$0")/../.."
export CC="${CC:-clang -O2}"
# reuse the hxc tool when it exists (rebuild it with SKIP_TOOL=)
if [ -f bin/hxc/wbk.js ]; then export SKIP_TOOL=${SKIP_TOOL-1}; fi
sh hxc/build.sh test/fuzz Fuzz
mkdir -p bin/fuzz
cp bin/hxc/Fuzz/prog_c bin/fuzz/fuzz
echo "built bin/fuzz/fuzz"
