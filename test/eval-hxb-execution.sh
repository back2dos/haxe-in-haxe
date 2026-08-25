#!/bin/sh
# Build the port as Eval HXB with the pinned compiler, then execute it through
# that compiler's HXB loader. Both executions compile the same fixture.
#
# HAXE_REFERENCE=/absolute/path/to/pinned/haxe sh test/eval-hxb-execution.sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HAXE_STD_PATH="$repository_root/haxe/std"
HAXE_IN_HAXE_STD_PATH="$HAXE_STD_PATH"
export HAXE_STD_PATH HAXE_IN_HAXE_STD_PATH

if [ -z "${HAXE_REFERENCE:-}" ] || [ ! -x "$HAXE_REFERENCE" ]; then
	echo "HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule." >&2
	exit 2
fi

execution_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/haxe-in-haxe-eval-execution.XXXXXX")
trap 'rm -rf "$execution_tmpdir"' EXIT INT TERM

compiler_hxb="$execution_tmpdir/haxe-in-haxe.eval.hxb"
source_run_output="$execution_tmpdir/source-run.hxb"
loaded_run_output="$execution_tmpdir/loaded-run.hxb"

# --run makes this an Eval compilation. Arguments following it are passed to
# haxe.Main, so building the compiler archive also exercises the source form.
"$HAXE_REFERENCE" -cp src -D haxe_in_haxe_bootstrap --hxb "$compiler_hxb" \
	--run haxe.Main -- -cp test/conformance --main unit.moduleload.Basic \
	--hxb "$source_run_output"

if ! unzip -Z1 "$compiler_hxb" | LC_ALL=C grep -qx "eval/haxe/Main.hxb"; then
	echo "Compiler archive does not contain eval/haxe/Main.hxb" >&2
	exit 1
fi

# Execute the same compiler code from HXB instead of source.
"$HAXE_REFERENCE" --hxb-lib "$compiler_hxb" --run haxe.Main -- \
	-cp test/conformance --main unit.moduleload.Basic --hxb "$loaded_run_output"

sh test/compare-hxb.sh "$source_run_output" "$loaded_run_output"
echo "Eval HXB execution passed: source and loaded compiler outputs match"
