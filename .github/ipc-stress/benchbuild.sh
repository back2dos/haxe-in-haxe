#!/bin/bash
# TEMPORARY (ipc-arm64): three HaxeBenchmarks cases for linux-arm64 by a tool
# (Bench --setup has fetched bin/bench).
#   benchbuild.sh <repo> <tool> <out dir>
set -eu
repo=$(cd "$1" && pwd) tool=$(cd "$(dirname "$2")" && pwd)/$(basename "$2") out=$3
mkdir -p "$out"; out=$(cd "$out" && pwd)
b=$repo/bin/bench
export HAXE_STD_PATH=$repo/haxe/upstream/std
ulimit -s unlimited 2>/dev/null || true
std="-cp $repo/bin/hxmc/std --custom-target hxmc -D hxmc.target=linux-arm64"
(cd "$b/runner/cases/binarytrees" && "$tool" "$out/binarytrees" -cp . -main BMBinaryTreesCode $std)
(cd "$b/runner/cases/json" && "$tool" "$out/json" -cp . -main BMJsonCode $std)
f=
for d in formatter/src tokentree/src haxeparser/src hxparse/src json2object/src hxargs hxjsonast/src; do f="$f -cp $b/libs/$d -D ${d%%/*}"; done
(cd "$b/runner/cases/formatter_noio" && "$tool" "$out/formatter" -cp . $f -main BMFormatterNoIOCode $std)
ls -l "$out"
