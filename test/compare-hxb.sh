#!/bin/sh
# Compare HXB semantics without comparing ZIP container bytes.

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: sh test/compare-hxb.sh <expected.hxb> <actual.hxb>" >&2
	exit 2
fi

expected=$1
actual=$2

if [ ! -f "$expected" ] || [ ! -f "$actual" ]; then
	echo "Both HXB archives must exist." >&2
	exit 2
fi

compare_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/haxe-in-haxe-compare.XXXXXX")
trap 'rm -rf "$compare_tmpdir"' EXIT INT TERM

expected_entries="$compare_tmpdir/expected.entries"
actual_entries="$compare_tmpdir/actual.entries"
LC_ALL=C unzip -Z1 "$expected" | LC_ALL=C sort > "$expected_entries"
LC_ALL=C unzip -Z1 "$actual" | LC_ALL=C sort > "$actual_entries"

if ! cmp -s "$expected_entries" "$actual_entries"; then
	echo "HXB archive member set differs" >&2
	diff -u "$expected_entries" "$actual_entries" >&2 || true
	exit 1
fi

while IFS= read -r entry; do
	case "$entry" in
		*.hxb)
			unzip -p "$expected" "$entry" > "$compare_tmpdir/expected.member"
			unzip -p "$actual" "$entry" > "$compare_tmpdir/actual.member"
			if ! cmp -s "$compare_tmpdir/expected.member" "$compare_tmpdir/actual.member"; then
				first_difference=$(cmp -l "$compare_tmpdir/expected.member" "$compare_tmpdir/actual.member" 2>/dev/null | sed -n '1p' || true)
				echo "HXB payload differs: $entry" >&2
				if [ -n "$first_difference" ]; then
					echo "First differing byte (offset, expected, actual): $first_difference" >&2
				fi
				exit 1
			fi
			;;
	esac
done < "$expected_entries"
