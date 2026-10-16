// The host of WasmCallback.hx: calls its callback through the exported table,
// later, from node's event loop (after the module's _start returned).
module.exports = (mem, exports) => ({
	host: {
		h_later: (fn, times, arg) => {
			let n = 0;
			const tick = () => {
				const r = exports().__indirect_function_table.get(fn)(n, arg + n);
				console.log(`host: tick ${n} returned ${r}`);
				if (++n < times) setTimeout(tick, 1);
			};
			setTimeout(tick, 1);
		},
	},
});
