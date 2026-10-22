#!/bin/bash
# TEMPORARY (ipc-arm64): the cost of the dmb ishst before reference stores on
# arm64: the port's self-compile and three HaxeBenchmarks cases, built with
# (fix/) and without (nofix/) the barrier, interleaved round by round.
#   bench.sh <repo> <ab dir: fix/, nofix/, runner/> <rounds>
set -u
repo=$1 ab=$2 n=$3
export HAXE_STD_PATH=$repo/haxe/upstream/std
cases=$ab/runner/cases
t() { # label variant cmd...: wall and user seconds
	local l=$1 v=$2; shift 2
	/usr/bin/time -o "$ab/t.txt" -f "%e %U" "$@" > /dev/null 2>&1 || echo "FAILED $l $v" >&2
	echo "R $l $v $(tail -1 "$ab/t.txt")"
}
for k in $(seq 1 "$n"); do
	if [ $((k % 2)) = 1 ]; then vs="fix nofix"; else vs="nofix fix"; fi
	for v in $vs; do
		(cd "$repo" && t self $v "$ab/$v/haxe" haxe-in-haxe.hxml)
		(cd "$repo" && t self-seq $v "$ab/$v/haxe" haxe-in-haxe.hxml -D disable-parallelism)
		(cd "$cases/binarytrees" && t binarytrees $v "$ab/$v/binarytrees")
		(cd "$cases/json/data" && t json $v "$ab/$v/json")
		(cd "$cases/formatter_noio/data" && t formatter $v "$ab/$v/formatter")
	done
done > "$ab/bench.txt"
cat "$ab/bench.txt"
python3 - "$ab/bench.txt" <<'PY'
import sys, statistics as st
d = {}
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) == 5 and p[0] == "R":
        d.setdefault((p[1], p[2]), []).append((float(p[3]), float(p[4])))
print("%-12s %10s %10s %8s   %10s %10s %8s" % ("case", "fix wall", "nofix", "delta", "fix user", "nofix", "delta"))
for c in ["self", "self-seq", "binarytrees", "json", "formatter"]:
    f, n = d.get((c, "fix")), d.get((c, "nofix"))
    if not f or not n: continue
    fw, nw = st.median(x[0] for x in f), st.median(x[0] for x in n)
    fu, nu = st.median(x[1] for x in f), st.median(x[1] for x in n)
    if nw == 0 or nu == 0: continue
    print("%-12s %10.3f %10.3f %+7.2f%%   %10.3f %10.3f %+7.2f%%" % (c, fw, nw, 100 * (fw / nw - 1), fu, nu, 100 * (fu / nu - 1)))
PY
