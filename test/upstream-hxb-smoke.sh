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
run_case issue-11164 haxe/tests/misc/eval/projects/Issue11164 Main
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
run_case issue-2997 haxe/tests/misc/eval/projects/Issue2997 Main
run_case issue-3310 haxe/tests/misc/eval/projects/Issue3310 Main
run_case issue-3756 haxe/tests/misc/eval/projects/Issue3756 Main
run_case issue-4070 haxe/tests/misc/eval/projects/Issue4070 Main
run_case issue-4265 haxe/tests/misc/eval/projects/Issue4265 Main
run_case issue-4399 haxe/tests/misc/eval/projects/Issue4399 Main
run_case issue-4458 haxe/tests/misc/eval/projects/Issue4458 Main
run_case issue-2508 haxe/tests/misc/eval/projects/Issue2508 Main
run_case issue-3956 haxe/tests/misc/eval/projects/Issue3956 Main
run_case issue-4563 haxe/tests/misc/eval/projects/Issue4563 Main
run_case issue-4662 haxe/tests/misc/eval/projects/Issue4662 Main
run_case issue-4720 haxe/tests/misc/eval/projects/Issue4720 Main
run_case issue-4982 haxe/tests/misc/eval/projects/Issue4982 Main
run_case issue-5005 haxe/tests/misc/eval/projects/Issue5005 Main
run_case issue-5118 haxe/tests/misc/eval/projects/Issue5118 Main
run_case issue-5125 haxe/tests/misc/eval/projects/Issue5125 Main
run_case issue-5128 haxe/tests/misc/eval/projects/Issue5128 Main
run_case issue-5152 haxe/tests/misc/eval/projects/Issue5152 Main
run_case issue-5214 haxe/tests/misc/eval/projects/Issue5214 Main
run_case issue-5321 haxe/tests/misc/eval/projects/Issue5321 Main
run_case issue-5458 haxe/tests/misc/eval/projects/Issue5458 Main
run_case issue-5854 haxe/tests/misc/eval/projects/Issue5854 Main
run_case issue-6066 haxe/tests/misc/eval/projects/Issue6066 Main
run_case issue-6226 haxe/tests/misc/eval/projects/Issue6226 Main
run_case issue-6427 haxe/tests/misc/eval/projects/Issue6427 Main
run_case issue-6772 haxe/tests/misc/eval/projects/Issue6772 Main
run_case issue-6810 haxe/tests/misc/eval/projects/Issue6810 Main
run_case issue-6846 haxe/tests/misc/eval/projects/Issue6846 Main
run_case issue-7017 haxe/tests/misc/eval/projects/Issue7017 Main
run_case issue-7096 haxe/tests/misc/eval/projects/Issue7096 Main
run_case issue-7660 haxe/tests/misc/eval/projects/Issue7660 Main
run_case issue-8364 haxe/tests/misc/eval/projects/Issue8364 Main
run_case issue-8472 haxe/tests/misc/eval/projects/Issue8472 Main
run_case issue-8530 haxe/tests/misc/eval/projects/Issue8530 Main
run_case issue-8574 haxe/tests/misc/eval/projects/Issue8574 Main
run_case issue-8650 haxe/tests/misc/eval/projects/Issue8650 Main
run_case issue-8946 haxe/tests/misc/eval/projects/Issue8946 Main
run_case issue-9192 haxe/tests/misc/eval/projects/Issue9192 Main
run_case issue-9286 haxe/tests/misc/eval/projects/Issue9286 Main
run_case issue-9359 haxe/tests/misc/eval/projects/Issue9359 Main
run_case issue-9455 haxe/tests/misc/eval/projects/Issue9455 Main
run_case issue-9514 haxe/tests/misc/eval/projects/Issue9514 Main
run_case issue-9571 haxe/tests/misc/eval/projects/Issue9571 Main
