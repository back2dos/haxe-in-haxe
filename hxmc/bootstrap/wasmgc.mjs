// Runs a module built with -D hxmc.wasm-gc (hxmc/src/hxmc/wasmgc) under node:
//   node hxmc/bootstrap/wasmgc.mjs prog.wasm [args...]
// The module imports its host from "hxmc" and exports _start, plus the
// accessors that read its strings (arrays of UTF-16 units).
import { readFileSync, writeSync } from "node:fs";

const [file, ...args] = process.argv.slice(2);
if (!file) {
	console.error("usage: node wasmgc.mjs prog.wasm [args...]");
	process.exit(2);
}
let exports;
// a string of the module as a JavaScript string
function str(s) {
	if (s === null) return "null";
	const n = exports.hxmc_str_len(s);
	let out = "";
	for (let i = 0; i < n; i += 4096) {
		const units = [];
		for (let k = i; k < Math.min(n, i + 4096); k++) units.push(exports.hxmc_str_get(s, k));
		out += String.fromCharCode(...units);
	}
	return out;
}
const hxmc = {
	write(fd, s) {
		writeSync(fd === 2 ? 2 : 1, str(s));
	},
	now() {
		return performance.now() / 1000;
	},
	fmt(v) {
		return ofJs(String(v));
	},
	parseFloat(s) {
		return parseFloat(str(s));
	},
	math(op, x, y) {
		switch (op) {
			case 0: return Math.sin(x);
			case 1: return Math.cos(x);
			case 2: return Math.tan(x);
			case 3: return Math.asin(x);
			case 4: return Math.acos(x);
			case 5: return Math.atan(x);
			case 6: return Math.atan2(x, y);
			case 7: return Math.exp(x);
			case 8: return Math.log(x);
			default: return Math.pow(x, y);
		}
	},
	random() {
		return Math.random();
	},
};
// a JavaScript string as one of the module's
function ofJs(t) {
	const s = exports.hxmc_str_new(t.length);
	for (let i = 0; i < t.length; i++) exports.hxmc_str_set(s, i, t.charCodeAt(i));
	return s;
}
const { instance } = await WebAssembly.instantiate(readFileSync(file), { hxmc });
exports = instance.exports;
try {
	exports._start();
} catch (e) {
	if (e instanceof WebAssembly.Exception) {
		console.error("Uncaught exception (a Haxe value)");
		process.exit(1);
	}
	throw e;
}
