// Runs a WebAssembly module hxmc built for wasm32-wasi under node's WASI, in
// this process. The module sees the arguments, the environment and the whole
// file system (preopened as "/"; drive letters on Windows), and resolves
// relative paths against $PWD.
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import v8 from 'node:v8';
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

function preopens() {
	if (process.platform !== 'win32') return { '/': '/' };
	const r = {};
	for (const d of 'CDEFGHIJKLMNOPQRSTUVWXYZ') if (fs.existsSync(`${d}:\\`)) r[`/${d.toLowerCase()}`] = `${d}:\\`;
	return r;
}

function wasiPath(p) {
	if (process.platform !== 'win32') return p;
	const m = /^([A-Za-z]):[\\/](.*)$/.exec(p);
	return m ? `/${m[1].toLowerCase()}/${m[2].replace(/\\/g, '/')}` : p.replace(/\\/g, '/');
}

export function runWasm(module, args, env) {
	const e = { ...env, PWD: wasiPath(process.cwd()) };
	for (const k of ['HAXE_STD_PATH', 'HXMC_RT_DIR', 'HXMC_EXE_LIST']) if (e[k]) e[k] = wasiPath(e[k]);
	const wasi = new WASI({
		version: 'preview1',
		args: [wasiPath(path.resolve(module)), ...args],
		env: e,
		preopens: preopens(),
		returnOnExit: true,
	});
	const mod = new WebAssembly.Module(fs.readFileSync(module));
	const inst = new WebAssembly.Instance(mod, wasi.getImportObject());
	return wasi.start(inst) ?? 0;
}
