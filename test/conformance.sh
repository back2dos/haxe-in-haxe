#!/bin/sh
# Byte-for-byte HXB conformance harness. Run with:
# HAXE_REFERENCE=/absolute/path/to/pinned/haxe sh test/conformance.sh

set -eu

if [ -z "${HAXE_REFERENCE:-}" ] || [ ! -x "$HAXE_REFERENCE" ]; then
	echo "HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule." >&2
	exit 2
fi

conformance_tmpdir=$(mktemp -d /private/tmp/haxe-in-haxe-conformance.XXXXXX)
trap 'rm -rf "$conformance_tmpdir"' EXIT INT TERM

reference_output="$conformance_tmpdir/reference.hxb"
port_output="$conformance_tmpdir/port.hxb"

# Keep this initial case inside the port's currently supported batch subset.
"$HAXE_REFERENCE" -cp test --main unit.moduleload.Example --hxb "$reference_output"
haxe -cp src --run haxe.Main -cp test --main unit.moduleload.Example --hxb "$port_output"

if cmp -s "$reference_output" "$port_output"; then
	echo "HXB conformance passed: unit.moduleload.Example"
	exit 0
fi

echo "HXB conformance failed: unit.moduleload.Example" >&2
echo "Reference: $reference_output" >&2
echo "Port:      $port_output" >&2
exit 1
