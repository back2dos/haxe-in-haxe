// Builds the native compiler for this machine with the WebAssembly one, from
// the sources in lib/haxe/src, into the cache directory (launcher.mjs):
//   <cache>/haxe[.exe]   (renamed into place when complete)
// One build at a time: <cache>/build.lock holds the builder's process id.
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { cacheDir, exeName, hostTarget, install, libDir, lockHeld, toolEnv, wasmPath } from './launcher.mjs';
import { runWasm } from './wasi.mjs';

const host = hostTarget();
if (!host) {
	console.error(`haxe-in-haxe: no native build for ${process.platform}-${process.arch}`);
	process.exit(1);
}
const dir = cacheDir();
fs.mkdirSync(dir, { recursive: true });
const lock = path.join(dir, 'build.lock');
try {
	fs.writeFileSync(lock, String(process.pid), { flag: 'wx' });
} catch {
	if (lockHeld(lock)) {
		console.error('haxe-in-haxe: another build is running');
		process.exit(0);
	}
	fs.writeFileSync(lock, String(process.pid)); // a stale lock
}
let code = 1;
try {
	const work = path.join(dir, 'build');
	fs.rmSync(work, { recursive: true, force: true });
	fs.mkdirSync(work);
	const out = path.join(work, 'haxe');
	const src = path.join(libDir, 'src');
	const t0 = Date.now();
	console.log(`haxe-in-haxe: building ${host} (${new Date().toISOString()})`);
	// a second attempt resumes from the modules the first one compiled
	// (<work>/haxe.hxmc): the WebAssembly build can run out of its 4 GB
	for (let attempt = 0; attempt < 2; attempt++) {
		code = runWasm(wasmPath, [
			'-cp', path.join(src, 'port'), '-cp', path.join(src, 'hxmc'), '-main', 'hxmc.HaxeMain',
			'-D', 'disable-parallelism', '-D', `hxmc.target=${host}`, '--custom-target', `hxmc=${out}`,
		], toolEnv({ HXMC_HOST: host }));
		if (code === 0) break;
	}
	const built = fs.existsSync(out) ? out : fs.existsSync(`${out}.exe`) ? `${out}.exe` : null;
	if (code === 0 && built) {
		fs.chmodSync(built, 0o755);
		fs.renameSync(built, path.join(dir, exeName));
		fs.rmSync(work, { recursive: true, force: true });
		console.log(`haxe-in-haxe: done in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
		install(path.join(dir, exeName));
	} else {
		console.error(`haxe-in-haxe: the build failed (exit ${code})`);
		if (code === 0) code = 1;
	}
} finally {
	fs.rmSync(lock, { force: true });
}
process.exit(code);
