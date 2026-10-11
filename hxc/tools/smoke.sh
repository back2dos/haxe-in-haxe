#!/bin/sh
# A smoke test of a release build of the port (.github/workflows/build.yml):
# runs a hello world with --interp, writes HXB and compiles it to JS (and runs
# that with node when available).
#
#   HAXE_STD_PATH=<std> sh hxc/tools/smoke.sh <binary>
set -eu
BIN=$1
case "$BIN" in /*|[A-Za-z]:*) ;; *) BIN=$PWD/$BIN ;; esac
W=${SMOKE_DIR:-$(mktemp -d)}
mkdir -p "$W"
cd "$W"
cat > Main.hx <<'EOF'
class Main {
	static function main() {
		var a = [for (i in 0...5) i * i];
		trace("Hello from haxe-in-haxe " + a);
		var json = haxe.Json.stringify({ok: true, n: a.length});
		#if sys Sys.println(json); #else trace(json); #end
	}
}
EOF
expect() {
	if ! grep -q 'ok":true' "$1"; then
		echo "FAIL: $2"
		cat "$1"
		exit 1
	fi
	echo "ok: $2"
}
"$BIN" --version
"$BIN" -main Main --interp > interp.txt 2>&1 || { cat interp.txt; exit 1; }
cat interp.txt
expect interp.txt "--interp"
"$BIN" -main Main --hxb out.hxb
test -s out.hxb
echo "ok: --hxb ($(wc -c < out.hxb) bytes)"
"$BIN" -main Main --js out.js
test -s out.js
echo "ok: --js ($(wc -c < out.js) bytes)"
if command -v node > /dev/null 2>&1; then
	node out.js > js.txt 2>&1 || { cat js.txt; exit 1; }
	expect js.txt "node out.js"
fi
# extras, reported but not fatal (SMOKE_STRICT=1 makes them fatal): processes,
# the file system, another target, --run
cat > Extra.hx <<'EOF'
class Extra {
	static function main() {
		sys.io.File.saveContent("extra.txt", "written");
		Sys.println("file: " + sys.io.File.getContent("extra.txt") + " " + sys.FileSystem.exists("extra.txt") + ", cwd " + Sys.getCwd());
		Sys.println("system: " + Sys.systemName());
		var p = new sys.io.Process("node", ["-e", "console.log('from node')"]);
		Sys.println("process: " + StringTools.trim(p.stdout.readAll().toString()) + ", exit " + p.exitCode());
		Sys.println("command exit " + Sys.command("node", ["-e", "process.exit(3)"]));
	}
}
EOF
fails=0
extra() {
	name=$1
	shift
	if "$@" > extra.log 2>&1; then
		echo "extra ok: $name"
	else
		echo "extra FAIL: $name"
		fails=$((fails + 1))
	fi
	sed 's/^/    /' extra.log
}
extra "--interp file system and processes" "$BIN" -main Extra --interp
extra "--js with --cmd" "$BIN" -main Main --js cmd.js --cmd "node cmd.js"
extra "--python" "$BIN" -main Main --python out.py
extra "--run" "$BIN" --run Main
echo "smoke: done ($fails extra failures)"
if [ "$fails" -gt 0 ] && [ -n "${SMOKE_STRICT:-}" ]; then exit 1; fi
exit 0
