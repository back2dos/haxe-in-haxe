#!/bin/sh
# Source-only HXB breadth smoke tests. These prove successful emission and
# reference consumption, but intentionally do not claim payload conformance.

set -eu

if [ -z "${HAXE_REFERENCE:-}" ] || [ ! -x "$HAXE_REFERENCE" ]; then
	echo "HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule." >&2
	exit 2
fi

smoke_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/haxe-in-haxe-upstream-smoke.XXXXXX")
trap 'rm -rf "$smoke_tmpdir"' EXIT INT TERM

run_case() {
	name=$1
	class_path=$2
	main=$3
	reference_output="$smoke_tmpdir/$name-reference.hxb"
	port_output="$smoke_tmpdir/$name-port.hxb"
	dump_path="$smoke_tmpdir/$name-dump"
	mkdir -p "$dump_path"

	"$HAXE_REFERENCE" -cp "$class_path" --main "$main" --hxb "$reference_output"
	"$HAXE_REFERENCE" -cp src -D haxe_in_haxe_bootstrap --run haxe.Main -- \
		-cp "$class_path" --main "$main" --hxb "$port_output"
	"$HAXE_REFERENCE" --hxb-lib "$port_output" -cp "$class_path" --main "$main" \
		--no-output -D dump=record -D dump-path="$dump_path"
	echo "HXB smoke passed: $name ($main)"
}

run_case module-fields test unit.moduleload.ModuleFields
run_case issue-7237 haxe/tests/optimization/src issues.Issue7237
run_case issue-6015 haxe/tests/optimization/src issues.Issue6015
run_case issue-6093 haxe/tests/optimization/src issues.Issue6093
run_case issue-5931 haxe/tests/optimization/src issues.Issue5931
run_case issue-3524 haxe/tests/optimization/src issues.Issue3524
run_case issue-11005 haxe/tests/misc/eval/projects/Issue11005 Main
run_case issue-9204 haxe/tests/misc/eval/projects/Issue9204 Main
