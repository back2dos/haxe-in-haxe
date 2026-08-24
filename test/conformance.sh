#!/bin/sh
# Member-by-member HXB conformance harness. Run with:
# HAXE_REFERENCE=/absolute/path/to/pinned/haxe sh test/conformance.sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HAXE_STD_PATH="$repository_root/haxe/std"
export HAXE_STD_PATH

if [ -z "${HAXE_REFERENCE:-}" ] || [ ! -x "$HAXE_REFERENCE" ]; then
	echo "HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule." >&2
	exit 2
fi

conformance_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/haxe-in-haxe-conformance.XXXXXX")
trap 'rm -rf "$conformance_tmpdir"' EXIT INT TERM

reference_output="$conformance_tmpdir/reference.hxb"
compiler_hxb="$conformance_tmpdir/haxe-in-haxe.eval.hxb"
source_run_output="$conformance_tmpdir/source-run.hxb"
port_output="$conformance_tmpdir/port.hxb"

# Keep this initial case inside the port's currently supported batch subset.
"$HAXE_REFERENCE" -cp test/conformance --main unit.moduleload.Basic --hxb "$reference_output"

# Build the port as Eval HXB. This also executes its source form once because
# --run arguments belong to haxe.Main after the compiler archive is written.
"$HAXE_REFERENCE" -cp src -D haxe_in_haxe_bootstrap --hxb "$compiler_hxb" \
	--run haxe.Main -- -cp test/conformance --main unit.moduleload.Basic \
	--hxb "$source_run_output"

if ! unzip -Z1 "$compiler_hxb" | LC_ALL=C grep -qx "eval/haxe/Main.hxb"; then
	echo "Compiler archive does not contain eval/haxe/Main.hxb" >&2
	exit 1
fi

# The conformance candidate must come from the compiler loaded out of HXB.
"$HAXE_REFERENCE" --hxb-lib "$compiler_hxb" --run haxe.Main -- \
	-cp test/conformance --main unit.moduleload.Basic --hxb "$port_output"

sh test/compare-hxb.sh "$source_run_output" "$port_output"
echo "Eval HXB execution passed inside conformance harness"

sh test/compare-hxb.sh "$reference_output" "$port_output"

echo "HXB conformance passed: unit.moduleload.Basic"
exit 0
