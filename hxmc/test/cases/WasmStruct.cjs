// The host of WasmStruct.hx: C functions taking and returning structs as
// clang compiles them for wasm32 (CAbi.wasmSig): a struct of one scalar as
// that scalar, another as the address of a copy; a result of one scalar
// returned, another stored at an address given first.
module.exports = mem => {
	const dv = () => new DataView(mem().buffer);
	return {
		host: {
			// struct { double x, y; } (16 bytes)
			w_pt_sum: p => dv().getFloat64(p, true) + 10 * dv().getFloat64(p + 8, true),
			w_pt_make: (out, x, y) => { dv().setFloat64(out, x, true); dv().setFloat64(out + 8, y, true); },
			w_pt_swap: (out, p) => { const a = dv().getFloat64(p, true), b = dv().getFloat64(p + 8, true); dv().setFloat64(out, b, true); dv().setFloat64(out + 8, a, true); },
			// struct { float f; } and struct { int64_t l; }: scalars
			w_one_f: (v, k) => v * k,
			w_one_l: v => v * 3n,
			// struct { int32_t a; uint8_t b; uint16_t c; } (8 bytes) between scalars
			w_mix: (k, p, z) => k + dv().getInt32(p, true) + 100 * dv().getUint8(p + 4) + 10000 * dv().getUint16(p + 6, true) + z,
		},
	};
};
