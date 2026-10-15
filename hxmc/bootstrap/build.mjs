// Builds the native compiler for this machine with the WebAssembly one, from
// the package's sources (haxe/src, hxmc/), into the cache directory
// (launcher.mjs): <cache>/haxe[.exe], renamed into place when complete.
//   node build.mjs              (the launcher, on first use)
//   node build.mjs --rebuild    (hxmc-rebuild: hxmc/std merged again first,
//                                in the foreground, replacing a native build)
// One build at a time: <cache>/build.lock holds the builder's process id.
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { bootDir, cacheDir, exeName, hostTarget, install, lockHeld, pkgDir, toolEnv, wasmPath } from './launcher.mjs';
import { runWasm } from './wasi.mjs';

const rebuild = process.argv.includes('--rebuild');
const host = hostTarget();
if (!host) {
	console.error(`hxmc: no native build for ${process.platform}-${process.arch}`);
	process.exit(1);
}
const dir = cacheDir();
fs.mkdirSync(dir, { recursive: true });
const lock = path.join(dir, 'build.lock');
try {
	fs.writeFileSync(lock, String(process.pid), { flag: 'wx' });
} catch {
	if (lockHeld(lock)) {
		console.error('hxmc: another build is running');
		process.exit(rebuild ? 1 : 0);
	}
	fs.writeFileSync(lock, String(process.pid)); // a stale lock
}
let code = 1;
try {
	const env = toolEnv({ HXMC_HOST: host });
	if (rebuild) {
		// hxmc's std as programs see it (hxmc/MkStd.hx, on Eval)
		console.log('hxmc: merging hxmc/std into hxmc/bootstrap/hxmc-std');
		code = runWasm(wasmPath, ['-cp', pkgDir, '--run', 'hxmc.MkStd', path.join(pkgDir, 'hxmc', 'std'),
			path.join(pkgDir, 'haxe', 'upstream', 'std'), path.join(bootDir, 'hxmc-std')], env);
		if (code !== 0) throw new Error(`hxmc.MkStd failed (exit ${code})`);
	}
	const work = path.join(dir, 'build');
	fs.rmSync(work, { recursive: true, force: true });
	fs.mkdirSync(work);
	const out = path.join(work, 'haxe');
	const t0 = Date.now();
	console.log(`hxmc: building the native compiler for ${host} (${new Date().toISOString()})`);
	code = runWasm(wasmPath, [
		'-cp', path.join(pkgDir, 'haxe', 'src'), '-cp', pkgDir, '-main', 'hxmc.HaxeMain',
		'-D', 'disable-parallelism', '-D', `hxmc.target=${host}`, '--custom-target', `hxmc=${out}`,
	], env);
	const built = fs.existsSync(out) ? out : fs.existsSync(`${out}.exe`) ? `${out}.exe` : null;
	if (code === 0 && built) {
		fs.chmodSync(built, 0o755);
		fs.renameSync(built, path.join(dir, exeName));
		fs.rmSync(work, { recursive: true, force: true });
		console.log(`hxmc: done in ${((Date.now() - t0) / 1000).toFixed(1)} s: ${path.join(dir, exeName)}`);
		install(path.join(dir, exeName));
	} else {
		console.error(`hxmc: the build failed (exit ${code})`);
		if (code === 0) code = 1;
	}
} catch (e) {
	console.error(`hxmc: ${e.message}`);
	code = 1;
} finally {
	fs.rmSync(lock, { force: true });
}
process.exit(code);
