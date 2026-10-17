// Runs a module built with -D hxmc.wasm-gc (hxmc/src/hxmc/wasmgc) under node:
//   node hxmc/bootstrap/wasmgc.mjs prog.wasm [args...]
// The module imports its host from "hxmc" and exports _start, plus the
// accessors that read its strings (arrays of UTF-16 units).
import * as fs from "node:fs";
import * as path from "node:path";
const { readFileSync, writeSync } = fs;

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
	// GcSys's op codes
	sysStr(op, a, b) {
		const s = a === null ? null : str(a);
		try {
			switch (op) {
				case 0: return process.env[s] === undefined ? null : ofJs(process.env[s]);
				case 1: return ofJs(process.cwd());
				case 2: return ofJs(path.resolve(s));
				case 3: return ofJs(fs.readdirSync(s).join("\0"));
				case 4: return ofJs(args.join("\0"));
				case 5: return ofJs(Object.entries(process.env).map(([k, v]) => k + "=" + v).join("\0"));
				case 6: return ofJs(path.resolve(file));
				case 7: {
					const st = fs.statSync(s);
					const t = (d) => Math.floor(d.getTime() / 1000);
					return ofJs([st.gid, st.uid, t(st.atime), t(st.mtime), t(st.ctime), st.dev, st.ino, st.nlink, st.rdev, st.size, st.mode].join("\0"));
				}
				default: return ofJs("Wasi");
			}
		} catch (e) {
			return null;
		}
	},
	sysNum(op, a, b, n) {
		const s = a === null ? null : str(a), t = b === null ? null : str(b);
		try {
			switch (op) {
				case 0: return fs.existsSync(s) ? 1 : 0;
				case 1: return fs.existsSync(s) && fs.statSync(s).isDirectory() ? 1 : 0;
				case 2: fs.mkdirSync(s, { recursive: true }); return 1;
				case 3: fs.unlinkSync(s); return 1;
				case 4: fs.rmdirSync(s); return 1;
				case 5: fs.renameSync(s, t); return 1;
				case 6: process.chdir(s); return 1;
				case 7: process.exit(n);
				case 8: return Date.now() / 1000;
				case 9: { const u = process.cpuUsage(); return (u.user + u.system) / 1e6; }
				case 10: Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, n * 1000); return 0;
				case 11: if (t === null) delete process.env[s]; else process.env[s] = t; return 0;
				default: return 0;
			}
		} catch (e) {
			return 0;
		}
	},
	// GcDate's op codes
	dateNum(op, t, y, m, d, h, mi, s) {
		const date = new Date(t);
		switch (op) {
			case 0: return new Date(y, m, d, h, mi, s).getTime();
			case 1: return date.getFullYear();
			case 2: return date.getMonth();
			case 3: return date.getDate();
			case 4: return date.getDay();
			case 5: return date.getHours();
			case 6: return date.getMinutes();
			case 7: return date.getSeconds();
			case 8: return date.getUTCFullYear();
			case 9: return date.getUTCMonth();
			case 10: return date.getUTCDate();
			case 11: return date.getUTCDay();
			case 12: return date.getUTCHours();
			case 13: return date.getUTCMinutes();
			case 14: return date.getUTCSeconds();
			case 15: return date.getTimezoneOffset();
			default: return Date.now();
		}
	},
	readFile(p) {
		let data;
		try {
			data = readFileSync(str(p));
		} catch (e) {
			return null;
		}
		const b = exports.hxmc_bytes_new(data.length);
		for (let i = 0; i < data.length; i++) exports.hxmc_bytes_set(b, i, data[i]);
		return b;
	},
	writeFile(p, b, append) {
		const n = exports.hxmc_bytes_len(b), data = new Uint8Array(n);
		for (let i = 0; i < n; i++) data[i] = exports.hxmc_bytes_get(b, i);
		try {
			(append ? fs.appendFileSync : fs.writeFileSync)(str(p), data);
			return 1;
		} catch (e) {
			return 0;
		}
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
