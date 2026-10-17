// The host of WasmStruct.hx: C functions taking and returning structs as
// clang compiles them for wasm32 (CAbi.wasmSig): a struct of one scalar as
// that scalar, another as the address of a copy; a result of one scalar
// returned, another stored at an address given first.
// A callback (hxmc's own convention, called from JavaScript): a struct
// by its address, a struct result stored at an address given first.
module.exports = (mem, exports) => {
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
			// calls back fn(result, &{x, y}, k) with the struct at buf, its result at buf + 16
			w_call: (fn, buf) => {
				dv().setFloat64(buf, 2.5, true);
				dv().setFloat64(buf + 8, -1, true);
				exports().__indirect_function_table.get(fn)(BigInt(buf + 16), BigInt(buf), 4);
				return dv().getFloat64(buf + 16, true) + 10 * dv().getFloat64(buf + 24, true);
			},
		},
	};
};
