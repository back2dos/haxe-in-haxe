#!/bin/bash
# TEMPORARY (ipc-arm64): upstream's TestUnicode (sys suite) alone, run N times
# in a copy of haxe/upstream/tests/sys.
#   sysloop.sh <repo> <utest checkout> <work dir> <iterations>
set -u
repo=$1 utest=$2 work=$3 n=$4
rm -rf "$work"
cp -r "$repo/haxe/upstream/tests/sys" "$work"
cd "$work"
cat > src/Main.hx <<'EOF'
class Main {
	static public function main() {
		var runner = new utest.Runner();
		runner.addCase(new TestUnicode());
		var report = utest.ui.Report.create(runner);
		report.displayHeader = AlwaysShowHeader;
		report.displaySuccessResults = NeverShowSuccessResults;
		runner.run();
	}
}
EOF
sed -i "s#^-lib utest#-cp $utest/src#" *.hxml
haxe -D github -D Linux compile-eval-hxb.hxml || { echo "sysloop: the build failed"; exit 2; }
fails=0
for i in $(seq 1 "$n"); do
	if ! haxe --hxb-lib bin/eval/sys.hxb --run Main > out.txt 2>&1; then
		fails=$((fails + 1))
		echo "--- iteration $i failed"
		grep -v "^\s*$" out.txt | grep -iv "OK \.*$" | tail -20
	fi
done
echo "sysloop $work: $n runs, $fails failures"
