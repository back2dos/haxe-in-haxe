// Runs a WebAssembly module hxmc built for wasm32-wasi under node's WASI, in
// this process: imported by the launcher, or as a command
//   node hxmc/bootstrap/wasi.mjs <module.wasm[.br]> [args...]
// The module sees the arguments, the environment and the whole file system
// (preopened as "/"; on Windows /c/<dir>, /d/<dir>, ... for C:\<dir>, ...), and resolves
// relative paths against $PWD. A module ending in .br (brotli) or .gz is
// decompressed first (the committed stage0 is hxmc/bootstrap/stage0.wasm.br).
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import v8 from 'node:v8';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';
// (node's WASI warns that it is experimental)
const emitWarning = process.emitWarning;
process.emitWarning = (w, ...rest) => {
	if (String(w).includes('WASI')) return;
	emitWarning.call(process, w, ...rest);
};
const { WASI } = await import('node:wasi');

// node 22: exception handling with exnref is behind a flag, and WASI's
// fd_write as a fast API call can collect V8's heap and crash when the
// module's memory is large
v8.setFlagsFromString('--experimental-wasm-exnref');
v8.setFlagsFromString('--no-turbo-fast-api-calls');

// Windows: the top-level directories of every drive as /<drive>/<name> (node's
// WASI does not resolve paths under a preopened drive root), at most 60 (the
// runtime's limit is 64), the drive of the working directory first
function preopens() {
	if (process.platform !== 'win32') return { '/': '/' };
	const r = {};
	let n = 0;
	const first = process.cwd().charAt(0).toUpperCase();
	const drives = [first, ...'CDEFGHIJKLMNOPQRSTUVWXYZ'.split('').filter(d => d !== first)];
	for (const d of drives) {
		let entries;
		try {
			entries = fs.readdirSync(`${d}:\\`, { withFileTypes: true });
		} catch {
			continue;
		}
		for (const e of entries) {
			if (n >= 60) return r;
			if (!e.isDirectory() || e.name.startsWith('$')) continue;
			r[`/${d.toLowerCase()}/${e.name}`] = `${d}:\\${e.name}`;
			n++;
		}
	}
	return r;
}

export function wasiPath(p) {
	if (process.platform !== 'win32') return p;
	const m = /^([A-Za-z]):[\\/](.*)$/.exec(p);
	return m ? `/${m[1].toLowerCase()}/${m[2].replace(/\\/g, '/')}` : p.replace(/\\/g, '/');
}

// variables that hold paths (HAXE_STD_PATH may hold several, by the host's delimiter)
const PATH_VARS = ['HAXE_STD_PATH', 'HXMC_STD', 'HXMC_RT_DIR', 'HXMC_RT_OBJ', 'HXMC_EXE_LIST'];

export function runWasm(module, args, env = process.env) {
	const e = { ...env, PWD: wasiPath(process.cwd()) };
	for (const k of PATH_VARS) if (e[k]) e[k] = e[k].split(path.delimiter).map(wasiPath).join(':');
	const pre = preopens();
	// (HXMC_WASI_DEBUG=1: what the module is given)
	if (env.HXMC_WASI_DEBUG) console.error(JSON.stringify({ preopens: pre, PWD: e.PWD, HAXE_STD_PATH: e.HAXE_STD_PATH }));
	const wasi = new WASI({
		version: 'preview1',
		args: [wasiPath(path.resolve(module)), ...args],
		env: e,
		preopens: pre,
		returnOnExit: true,
	});
	let bytes = fs.readFileSync(module);
	if (module.endsWith('.br')) bytes = zlib.brotliDecompressSync(bytes);
	else if (module.endsWith('.gz')) bytes = zlib.gunzipSync(bytes);
	const mod = new WebAssembly.Module(bytes);
	const inst = new WebAssembly.Instance(mod, wasi.getImportObject());
	return wasi.start(inst) ?? 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	if (process.argv.length < 3) {
		console.error('usage: node wasi.mjs <module.wasm[.br]> [args...]');
		process.exit(2);
	}
	process.exitCode = runWasm(process.argv[2], process.argv.slice(3));
}
