// The package's `haxe` command (README.md):
// - the native build for this machine, when one is in the cache, runs as a
//   child process;
// - otherwise the WebAssembly build (lib/haxe.wasm) runs here under node's
//   WASI, and a detached process builds the native one with it (lib/build.mjs).
// On Unix, once the native build exists and the package is writable, it
// replaces bin/haxe itself, so npm's link to bin/haxe runs it without node.
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { runWasm } from './wasi.mjs';

export const pkgDir = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
export const libDir = path.join(pkgDir, 'lib', 'haxe');
export const wasmPath = path.join(pkgDir, 'lib', 'haxe.wasm');
const version = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8')).version;

// hxmc's name of this machine (null: no native build, WebAssembly only)
export function hostTarget() {
	const arch = { x64: 'x86_64', arm64: 'arm64' }[process.arch];
	const plat = { linux: 'linux', darwin: 'macos', win32: 'windows' }[process.platform];
	return arch && plat ? `${plat}-${arch}` : null;
}

export function cacheDir() {
	if (process.env.HAXE_IN_HAXE_CACHE) return path.join(process.env.HAXE_IN_HAXE_CACHE, version, hostTarget());
	const home = os.homedir();
	const base = process.platform === 'win32' ? (process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local'))
		: process.platform === 'darwin' ? path.join(home, 'Library', 'Caches')
		: (process.env.XDG_CACHE_HOME || path.join(home, '.cache'));
	return path.join(base, 'haxe-in-haxe', version, hostTarget());
}

export const exeName = process.platform === 'win32' ? 'haxe.exe' : 'haxe';

// what the binaries need to find the package's std and runtime objects
// (hxmc.HaxeMain finds them itself when it is bin/haxe)
export function toolEnv(extra = {}) {
	const env = { ...process.env, ...extra };
	if (!env.HAXE_STD_PATH) env.HAXE_STD_PATH = path.join(libDir, 'std');
	if (!env.HXMC_RT_DIR) env.HXMC_RT_DIR = path.join(libDir, 'rt');
	return env;
}

export function main(args) {
	const host = hostTarget();
	const mode = process.env.HAXE_IN_HAXE_NATIVE; // "0": WebAssembly only; "wait": build the native first
	if (host && mode !== '0') {
		const native = path.join(cacheDir(), exeName);
		if (!fs.existsSync(native) && mode === 'wait') {
			const r = spawnSync(process.execPath, [path.join(pkgDir, 'lib', 'build.mjs')], { stdio: 'inherit' });
			if (r.status !== 0) process.exit(r.status ?? 1);
		}
		if (fs.existsSync(native)) {
			install(native);
			const r = spawnSync(native, args, { stdio: 'inherit', env: toolEnv() });
			if (r.error) throw r.error;
			process.exit(r.status ?? (r.signal ? 1 : 0));
		}
		startBuild();
	}
	process.exitCode = wasm(args, host);
}

// the WebAssembly build: executables it writes are marked here (WASI has no chmod)
function wasm(args, host) {
	const list = path.join(os.tmpdir(), `haxe-in-haxe-${process.pid}.exe-list`);
	const extra = { HXMC_EXE_LIST: list };
	if (host) extra.HXMC_HOST = host;
	let code;
	try {
		code = runWasm(wasmPath, args, toolEnv(extra));
	} finally {
		if (fs.existsSync(list)) {
			for (const f of fs.readFileSync(list, 'utf8').split('\n')) if (f) fs.chmodSync(f, 0o755);
			fs.rmSync(list, { force: true });
		}
	}
	return code;
}

// the native build in the background, unless one is running (lib/build.mjs
// holds a lock in the cache directory)
function startBuild() {
	const dir = cacheDir();
	fs.mkdirSync(dir, { recursive: true });
	if (lockHeld(path.join(dir, 'build.lock'))) return;
	if (!process.env.HAXE_IN_HAXE_QUIET)
		process.stderr.write(`haxe-in-haxe: building the native compiler for ${hostTarget()} in the background (log: ${path.join(dir, 'build.log')}); WebAssembly until then\n`);
	const log = fs.openSync(path.join(dir, 'build.log'), 'w');
	const child = spawn(process.execPath, [path.join(pkgDir, 'lib', 'build.mjs')], {
		detached: true, stdio: ['ignore', log, log], windowsHide: true,
	});
	child.unref();
}

export function lockHeld(lock) {
	try {
		const pid = Number(fs.readFileSync(lock, 'utf8'));
		process.kill(pid, 0); // throws when that process is gone
		return true;
	} catch (e) {
		return e.code === 'EPERM';
	}
}

// Unix: the native build replaces bin/haxe (a rename in the package's bin
// directory: npm's link keeps pointing at bin/haxe). Windows keeps this
// launcher (npm's haxe.cmd runs node on it).
export function install(native) {
	if (process.platform === 'win32' || process.env.HAXE_IN_HAXE_INSTALL === '0') return;
	const target = path.join(pkgDir, 'bin', 'haxe');
	const tmp = `${target}.${process.pid}.new`;
	try {
		fs.copyFileSync(native, tmp);
		fs.chmodSync(tmp, 0o755);
		fs.renameSync(tmp, target);
	} catch {
		fs.rmSync(tmp, { force: true }); // read-only package: stays the launcher
	}
}
