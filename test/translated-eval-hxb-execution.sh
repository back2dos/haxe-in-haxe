#!/bin/sh
# Build the translated compiler entry as Eval HXB, execute it from source and
# from HXB, then compare the emitted archives member-by-member.

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
host=${HAXE_REFERENCE:-${HAXE_HOST:-haxe}}

execution_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/haxe-in-haxe-translated-eval.XXXXXX")
trap 'rm -rf "$execution_tmpdir"' EXIT INT TERM

compiler_hxb="$execution_tmpdir/compiler.eval.hxb"
source_output="$execution_tmpdir/source.eval.hxb"
loaded_output="$execution_tmpdir/loaded.eval.hxb"

cd "$repository_root"
"$host" -cp src -cp test -main TranslatedPipeline \
	--interp --no-output --hxb "$compiler_hxb"

# Disabling parallelism makes allocation order deterministic across the source
# and HXB-loaded executions while keeping their effective compiler arguments
# identical.
"$host" -cp src -cp test --run TranslatedPipeline \
	-D disable_parallelism -cp test/conformance \
	--main unit.moduleload.Basic --interp --no-output --hxb "$source_output"

"$host" --hxb-lib "$compiler_hxb" --run TranslatedPipeline \
	-D disable_parallelism -cp test/conformance \
	--main unit.moduleload.Basic --interp --no-output --hxb "$loaded_output"

sh test/compare-hxb.sh "$source_output" "$loaded_output"
"$host" --hxb-lib "$loaded_output" --run unit.moduleload.Basic

echo "Translated Eval-HXB execution passed: source and loaded outputs match"
