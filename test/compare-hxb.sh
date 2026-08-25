#!/bin/sh
# Compare HXB semantics without comparing ZIP container bytes.

set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
	echo "usage: sh test/compare-hxb.sh <expected.hxb> <actual.hxb> [member]" >&2
	exit 2
fi

expected=$1
actual=$2
selected_member=${3:-}

if [ ! -f "$expected" ] || [ ! -f "$actual" ]; then
	echo "Both HXB archives must exist." >&2
	exit 2
fi

compare_tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/haxe-in-haxe-compare.XXXXXX")
trap 'rm -rf "$compare_tmpdir"' EXIT INT TERM

if [ -n "$selected_member" ]; then
	if ! unzip -Z1 "$expected" | LC_ALL=C grep -Fqx "$selected_member" || ! unzip -Z1 "$actual" | LC_ALL=C grep -Fqx "$selected_member"; then
		echo "HXB member is missing: $selected_member" >&2
		exit 1
	fi
	unzip -p "$expected" "$selected_member" > "$compare_tmpdir/expected.member"
	unzip -p "$actual" "$selected_member" > "$compare_tmpdir/actual.member"
	if ! cmp -s "$compare_tmpdir/expected.member" "$compare_tmpdir/actual.member"; then
		first_difference=$(cmp -l "$compare_tmpdir/expected.member" "$compare_tmpdir/actual.member" 2>/dev/null | sed -n '1p' || true)
		echo "HXB payload differs: $selected_member" >&2
		if [ -n "$first_difference" ]; then
			echo "First differing byte (offset, expected, actual): $first_difference" >&2
		fi
		module_root=$(printf '%s' "$selected_member" | sed 's|^[^/]*/||; s|\.hxb$||; s|/|.|g')
		echo "Typed-dump diagnostic root: $module_root" >&2
		exit 1
	fi
	exit 0
fi

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
				module_root=$(printf '%s' "$entry" | sed 's|^[^/]*/||; s|\.hxb$||; s|/|.|g')
				echo "Typed-dump diagnostic root: $module_root" >&2
				exit 1
			fi
			;;
	esac
done < "$expected_entries"
