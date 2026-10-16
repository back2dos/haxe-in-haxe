// The host of WasmImports.hx: the imports its C functions become.
module.exports = mem => ({
	host: {
		h_mix: (a, b, c, d, e) => a + b + c + Number(d) + e,
		h_strlen: p => { const m = new Uint8Array(mem().buffer); let n = 0; while (m[p + n]) n++; return n; },
		// three ints in the module's memory, below its data (from 4 KB)
		h_lib: v => v + 1,
		h_buffer: () => { new Int32Array(mem().buffer, 1024, 3).set([10, -20, 30]); return 1024; },
	},
	env: { e_twice: v => 2 * v },
});
