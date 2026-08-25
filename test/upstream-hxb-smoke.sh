#!/bin/sh
# Source-only HXB breadth smoke tests. These prove successful emission and
# reference consumption, but intentionally do not claim payload conformance.

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HAXE_STD_PATH="$repository_root/haxe/std"
HAXE_IN_HAXE_STD_PATH="$HAXE_STD_PATH"
export HAXE_STD_PATH HAXE_IN_HAXE_STD_PATH

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
run_case global-metadata-wildcard haxe/tests/misc/eval/projects/GlobalMetadataWildcard Main
run_case hxb-wildcard-exclude haxe/tests/misc/eval/projects/HxbWildcardExclude/src Main
run_case issue-10107 haxe/tests/misc/eval/projects/Issue10107 Main
run_case issue-10152 haxe/tests/misc/eval/projects/Issue10152 Main
run_case issue-10171 haxe/tests/misc/eval/projects/Issue10171 Main
run_case issue-10623 haxe/tests/misc/eval/projects/Issue10623 Main
run_case issue-10591 haxe/tests/misc/eval/projects/Issue10591 Main
run_case issue-10739 haxe/tests/misc/eval/projects/Issue10739 Main
run_case issue-10782 haxe/tests/misc/eval/projects/Issue10782 Main
run_case issue-10804 haxe/tests/misc/eval/projects/Issue10804 Main
run_case issue-10819 haxe/tests/misc/eval/projects/Issue10819 Main
run_case issue-10825 haxe/tests/misc/eval/projects/Issue10825 Main
run_case issue-10832 haxe/tests/misc/eval/projects/Issue10832 Main
run_case issue-10959 haxe/tests/misc/eval/projects/Issue10959 Main
run_case issue-10980 haxe/tests/misc/eval/projects/Issue10980 Main
run_case issue-11152 haxe/tests/misc/eval/projects/Issue11152 Main
run_case issue-11176 haxe/tests/misc/eval/projects/Issue11176 Main
run_case issue-11180 haxe/tests/misc/eval/projects/Issue11180 Main
run_case issue-11102 haxe/tests/misc/eval/projects/Issue11102 Main
run_case issue-11286 haxe/tests/misc/eval/projects/Issue11286 Main
run_case issue-11323 haxe/tests/misc/eval/projects/Issue11323 Main
run_case issue-11392 haxe/tests/misc/eval/projects/Issue11392 Main
run_case issue-11396 haxe/tests/misc/eval/projects/Issue11396 Main
run_case issue-11545 haxe/tests/misc/eval/projects/Issue11545 Main
run_case issue-11661 haxe/tests/misc/eval/projects/Issue11661 Main
run_case issue-11676 haxe/tests/misc/eval/projects/Issue11676 Main
run_case issue-11686 haxe/tests/misc/eval/projects/Issue11686 Main
run_case issue-11688 haxe/tests/misc/eval/projects/Issue11688 Main
run_case issue-11813 haxe/tests/misc/eval/projects/Issue11813 Main
run_case issue-12177 haxe/tests/misc/eval/projects/Issue12177 Main
run_case issue-12526 haxe/tests/misc/eval/projects/Issue12526 Main
run_case issue-12957 haxe/tests/misc/eval/projects/Issue12957 Main
run_case issue-12977 haxe/tests/misc/eval/projects/Issue12977 Main
run_case issue-2938 haxe/tests/misc/eval/projects/Issue2938 Main
run_case issue-2991 haxe/tests/misc/eval/projects/Issue2991 Main
run_case issue-2995 haxe/tests/misc/eval/projects/Issue2995 Main
run_case issue-3310 haxe/tests/misc/eval/projects/Issue3310 Main
run_case issue-3756 haxe/tests/misc/eval/projects/Issue3756 Main
run_case issue-4265 haxe/tests/misc/eval/projects/Issue4265 Main
run_case issue-4399 haxe/tests/misc/eval/projects/Issue4399 Main
run_case issue-4458 haxe/tests/misc/eval/projects/Issue4458 Main
