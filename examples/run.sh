#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
host=${HAXE_HOST:-haxe}
example=${1:-hello}

case "$example" in
	hello) main=examples.Hello ;;
	shapes) main=examples.Shapes ;;
	fibonacci) main=examples.Fibonacci ;;
	*)
		echo "Unknown example: $example" >&2
		echo "Choose hello, shapes, or fibonacci." >&2
		exit 2
		;;
esac

output="$repository_root/examples/generated/$example"
mkdir -p "$output"

cd "$repository_root"
"$host" haxe-in-haxe.hxml

# Exercise the compiler port loaded from its Eval HXB archive. Its current
# bootstrap pipeline emits a portable cross-target HXB for the example.
HAXE_IN_HAXE_STD_PATH="$repository_root/haxe/std" \
	"$host" --hxb-lib "$repository_root/bin/haxe-in-haxe.hxb" \
	--run haxe.Main -- \
	-cp "$repository_root/examples/src" --main "$main" \
	--hxb "$output/port.cross.hxb"

# Build an Eval-flavoured archive with the host so the example can actually be
# selected by the Eval HXB loader, then execute without its source class path.
"$host" -cp "$repository_root/examples/src" --main "$main" \
	--interp --no-output --hxb "$output/host.eval.hxb"

echo "Port output: $output/port.cross.hxb"
echo "Running $main from $output/host.eval.hxb"
"$host" --hxb-lib "$output/host.eval.hxb" --run "$main"
