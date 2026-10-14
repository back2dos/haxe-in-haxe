// Runs a WebAssembly module hxmc built for wasm32-wasi under node's WASI
// (hxmc/README.md, "WebAssembly"):
//   node --experimental-wasm-exnref --no-turbo-fast-api-calls hxmc/tools/wasi.mjs <module.wasm> [args...]
// (node 22: exception handling with exnref is behind the flag, and WASI's
// fd_write as a fast API call can collect V8's heap and crash when the
// module's memory is large)
// The module sees the arguments, the environment and the whole file system
// (preopened as "/"; the runtime resolves relative paths against $PWD).
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import process from 'node:process';

const wasi = new WASI({
	version: 'preview1',
	args: process.argv.slice(2),
	env: { ...process.env, PWD: process.cwd() },
	preopens: { '/': '/' },
	returnOnExit: true,
});
const mod = await WebAssembly.compile(await readFile(process.argv[2]));
const inst = await WebAssembly.instantiate(mod, wasi.getImportObject());
process.exitCode = wasi.start(inst) ?? 0;
