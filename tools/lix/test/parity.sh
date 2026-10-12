#!/bin/sh
# Runs the commands of tools/lix/test/parity-cases.sh with the reference lix (the npm
# package, node) and with the port (bin/lix), each in a root and project of its
# own, and compares their output, exit codes and the files they leave behind
# (haxe_libraries/, .haxerc, the library cache), with the roots' paths
# normalized. Prints a line per case and a summary; the logs are in
# bin/lix-parity/.
#
#   sh tools/lix/test/parity.sh                (all cases)
#   sh tools/lix/test/parity.sh install              (cases whose name contains "install")
#
# PORT_BIN: the port's directory (default bin/lix; e.g. one with links to lix.com).
# REF_LIX: the reference's bin directory (default: lix@17.0.3 installed with npm
# into bin/lix-ref). Network access: the reference uses node's https, run with
# NODE_USE_ENV_PROXY=1 when HTTPS_PROXY is set.
set -u
cd "$(dirname "$0")/../../.."
ROOT=$PWD
OUT=$ROOT/bin/lix-parity
PORT_BIN=${PORT_BIN:-$ROOT/bin/lix}
if [ -z "${REF_LIX:-}" ]; then
	REF_LIX=$ROOT/bin/lix-ref/node_modules/.bin
	if [ ! -x "$REF_LIX/lix" ]; then
		mkdir -p bin/lix-ref
		(cd bin/lix-ref && npm install --silent --ignore-scripts lix@17.0.3 > /dev/null) || { echo "npm install lix failed"; exit 1; }
	fi
fi
[ -x "$PORT_BIN/lix" ] || { echo "no $PORT_BIN/lix: make lix"; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
FILTER=${1:-}
pass=0
fail=0

# the state of an implementation's world: its files and their contents
snapshot() {
	(
		cd "$1"
		find . -path ./root/downloads -prune -o -path ./root/versions -prune -o -path ./root/neko -prune -o -path ./root/haxelib -prune \
			-o -path '*/.cache/*' -prune -o \( -type f -o -type l \) -print | grep -v '/root/haxe_libraries/[^/]*/[^/]*/[^/]*/.' | LC_ALL=C sort
		for f in $(find . -path ./root/haxe_libraries -prune -o \( -name '*.hxml' -o -name .haxerc \) -type f -print | LC_ALL=C sort); do
			echo "--- $f"
			cat "$f"
			echo
		done
	) | sed "s#$1#<ROOT>#g"
}

run_case() {
	name=$1
	shift
	case "$name" in *"$FILTER"*) ;; *) return ;; esac
	for impl in ref port; do
		W=$OUT/$name/$impl
		mkdir -p "$W/root" "$W/project"
		if [ $impl = ref ]; then BIN=$REF_LIX; else BIN=$PORT_BIN; fi
		# a shared download of Haxe/neko, so the cases need not download them each time
		if [ -d "$OUT/shared-versions" ]; then
			ln -s "$OUT/shared-versions" "$W/root/versions"
			ln -s "$OUT/shared-neko" "$W/root/neko"
		fi
		: > "$W/log"
		for cmd in "$@"; do
			(
				cd "$W/project"
				export HAXESHIM_ROOT=$W/root PATH="$BIN:$PATH" NODE_USE_ENV_PROXY=1 NODE_NO_WARNINGS=1
				echo "\$ $cmd"
				sh -c "$cmd" 2>&1
				echo "[exit $?]"
			) >> "$W/log"
		done
		# the port's own command (lix shims) is not in the reference's help
		sed -e "s#$W#<ROOT>#g" -e '/^ *shims \[<dir>\] : /d' -e '/^ *this binary (or in <dir>) that run as lix does$/d' "$W/log" > "$W/log.norm"
		snapshot "$W" > "$W/files"
	done
	if cmp -s "$OUT/$name/ref/log.norm" "$OUT/$name/port/log.norm" && cmp -s "$OUT/$name/ref/files" "$OUT/$name/port/files"; then
		echo "ok    $name"
		pass=$((pass + 1))
	else
		echo "FAIL  $name"
		diff "$OUT/$name/ref/log.norm" "$OUT/$name/port/log.norm" | head -20
		diff "$OUT/$name/ref/files" "$OUT/$name/port/files" | head -20
		fail=$((fail + 1))
	fi
}

# Haxe and neko, downloaded once by the port for the cases that compile
prepare_haxe() {
	[ -d "$OUT/shared-versions" ] && return
	W=$OUT/prepare
	mkdir -p "$W/project"
	(cd "$W/project" && HAXESHIM_ROOT=$W/root "$PORT_BIN/lix" --silent scope create && HAXESHIM_ROOT=$W/root "$PORT_BIN/lix" install haxe 4.3.6 > "$W/log" 2>&1) || { cat "$W/log"; exit 1; }
	mv "$W/root/versions" "$OUT/shared-versions"
	mv "$W/root/neko" "$OUT/shared-neko"
}

. "$ROOT/tools/lix/test/parity-cases.sh"

echo "$pass passed, $fail failed"
[ $fail = 0 ]
