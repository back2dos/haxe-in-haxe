#!/bin/sh
# EXPERIMENTAL: builds bench.ml natively (ocamlopt) and with wasm_of_ocaml,
# with both integer layers. Needs opam with wasm_of_ocaml-compiler and
# Binaryen on PATH.
set -eu
cd "$(dirname "$0")"
OUT=../../bin/backend/ocaml
mkdir -p "$OUT"
for retain in false true; do
	for layer in int63 int32; do
		n=bench_${layer}_$retain
		python3 -c "import sys;s=open('bench.ml').read().replace('RETAIN','$retain').replace('INTLAYER',open('$layer.ml').read());open('$OUT/$n.ml','w').write(s)"
		(cd "$OUT" && ocamlfind ocamlopt -O3 -package unix $n.ml -o $n.native 2> /dev/null || ocamlopt $n.ml -o $n.native)
		(cd "$OUT" && ocamlfind ocamlc -package js_of_ocaml -linkpkg $n.ml -o $n.byte && wasm_of_ocaml --opt=3 $n.byte -o $n.js)
	done
done
