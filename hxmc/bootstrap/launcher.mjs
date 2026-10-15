// The npm package's `haxe` command (README.md, "Using hxmc"): the native
// compiler for this machine: one hxmc-rebuild built (in the cache), else the
// platform package's (@hxmc/<os>-<cpu>), else the WebAssembly compiler
// (hxmc/bootstrap/haxe.wasm, under node's WASI) builds it in the foreground
// (build.mjs), once for every concurrent invocation. On Unix the
// native compiler then replaces hxmc/bootstrap/haxe and dist/haxe, so npm's
// link and lix run it without node. Machines without a native target run the
// WebAssembly compiler.
import { spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { runWasm } from './wasi.mjs';
import { PLATFORMS } from './platforms.mjs';

export const bootDir = path.dirname(fileURLToPath(import.meta.url));
export const pkgDir = path.dirname(path.dirname(bootDir));
export const wasmPath = path.join(bootDir, 'haxe.wasm');
const version = JSON.parse(fs.readFileSync(path.join(pkgDir, 'package.json'), 'utf8')).version;

// hxmc's name of this machine (null: no native build, WebAssembly only)
export function hostTarget() {
	const arch = { x64: 'x86_64', arm64: 'arm64' }[process.arch];
	const plat = { linux: 'linux', darwin: 'macos', win32: 'windows' }[process.platform];
	return arch && plat ? `${plat}-${arch}` : null;
}

// shared by every project: <cache>/hxmc/<version>/<target>
export function cacheDir() {
	if (process.env.HXMC_CACHE) return path.join(process.env.HXMC_CACHE, version, hostTarget());
	const home = os.homedir();
	const base = process.platform === 'win32' ? (process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local'))
		: process.platform === 'darwin' ? path.join(home, 'Library', 'Caches')
		: (process.env.XDG_CACHE_HOME || path.join(home, '.cache'));
	return path.join(base, 'hxmc', version, hostTarget());
}

export const exeName = process.platform === 'win32' ? 'haxe.exe' : 'haxe';

// what the compilers need to find the package's std, hxmc's std and the
// runtime objects (hxmc.HaxeMain finds them itself as hxmc/bootstrap/haxe)
export function toolEnv(extra = {}) {
	const env = { ...process.env, ...extra };
	if (!env.HAXE_STD_PATH) env.HAXE_STD_PATH = path.join(pkgDir, 'haxe', 'upstream', 'std');
	if (!env.HXMC_STD) env.HXMC_STD = path.join(bootDir, 'hxmc-std');
	if (!env.HXMC_RT_DIR) env.HXMC_RT_DIR = path.join(bootDir, 'rt');
	return env;
}

// lix's name of this machine (haxeshim's Platform; its NekoInstallation reads it
// from <installation>/platform.txt)
const LIX_PLATFORM = {
	'linux-x86_64': 'linux64', 'linux-arm64': 'linux-arm64', 'macos-x86_64': 'mac64', 'macos-arm64': 'mac-arm',
	'windows-x86_64': 'win64', 'windows-arm64': 'win64',
};

// dist/: an installation lix can use (`lix use haxe ./node_modules/@hxmc/cli/dist`):
// dist/haxe (this launcher, then the native compiler), dist/std (upstream's
// std: a symbolic link, a junction on Windows, else a copy), dist/platform.txt
export function setupDist() {
	const dist = path.join(pkgDir, 'dist');
	try {
		const std = path.join(dist, 'std');
		if (!fs.existsSync(std)) {
			const target = path.join(pkgDir, 'haxe', 'upstream', 'std');
			try {
				// (relative on Unix: the package can move; a junction needs an absolute target)
				if (process.platform === 'win32') fs.symlinkSync(target, std, 'junction');
				else fs.symlinkSync(path.join('..', 'haxe', 'upstream', 'std'), std, 'dir');
			} catch {
				fs.cpSync(target, std, { recursive: true });
			}
		}
		const platform = path.join(dist, 'platform.txt');
		const host = hostTarget();
		if (host && !fs.existsSync(platform)) fs.writeFileSync(platform, LIX_PLATFORM[host]);
	} catch {
		// a read-only package: lix cannot use dist/ then
	}
}

// a notice on an interactive terminal only: editors run `haxe --wait stdio`
// (length-prefixed answers on stderr) and parse `haxe --version`
function notice(text) {
	if (process.stderr.isTTY && !process.env.HXMC_QUIET) process.stderr.write(text);
}

function sleep(ms) {
	Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

// the native compiler for this machine, built in the foreground on first use
// (build.mjs; one build at a time: a second invocation waits for it)
export function ensureNative() {
	const dir = cacheDir();
	const native = path.join(dir, exeName);
	if (fs.existsSync(native)) return native;
	fs.mkdirSync(dir, { recursive: true });
	const lock = path.join(dir, 'build.lock');
	const log = path.join(dir, 'build.log');
	if (lockHeld(lock)) {
		notice(`hxmc: waiting for the native compiler being built for ${hostTarget()} (log: ${log})\n`);
		while (lockHeld(lock) && !fs.existsSync(native)) sleep(500);
		if (fs.existsSync(native)) return native;
	}
	notice(`hxmc: building the native compiler for ${hostTarget()} (one time, about 40 s; log: ${log})\n`);
	const out = fs.openSync(log, 'w');
	const r = spawnSync(process.execPath, [path.join(bootDir, 'build.mjs')], { stdio: ['ignore', out, out], windowsHide: true });
	fs.closeSync(out);
	if (r.status !== 0 || !fs.existsSync(native)) {
		process.stderr.write(`hxmc: building the native compiler failed (exit ${r.status ?? r.signal}; log: ${log})\n`);
		process.exit(r.status || 1);
	}
	return native;
}

// the native compiler of the platform package (@hxmc/<os>-<cpu>, an optional
// dependency), unless HXMC_PLATFORM_PACKAGE=0
export function platformBinary() {
	const p = PLATFORMS[hostTarget()];
	if (!p || process.env.HXMC_PLATFORM_PACKAGE === '0') return null;
	try {
		const bin = path.join(path.dirname(createRequire(import.meta.url).resolve(`${p.pkg}/package.json`)), p.exe);
		return fs.existsSync(bin) ? bin : null;
	} catch {
		return null;
	}
}

export function main(args) {
	const host = hostTarget();
	if (host && process.env.HXMC_NATIVE !== '0') {
		setupDist();
		// one hxmc-rebuild built (or the WebAssembly compiler did, earlier), the
		// platform package's, else built now
		const cached = path.join(cacheDir(), exeName);
		const native = fs.existsSync(cached) ? cached : platformBinary() ?? ensureNative();
		install(native);
		const r = spawnSync(native, args, { stdio: 'inherit', env: toolEnv() });
		if (r.error) throw r.error;
		process.exit(r.status ?? (r.signal ? 1 : 0));
	}
	// no native target for this machine: the WebAssembly compiler
	process.exitCode = wasm(args, host);
}

// the WebAssembly compiler: executables it writes are marked here (WASI has no chmod)
function wasm(args, host) {
	const list = path.join(os.tmpdir(), `hxmc-${process.pid}.exe-list`);
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

export function lockHeld(lock) {
	try {
		const pid = Number(fs.readFileSync(lock, 'utf8'));
		process.kill(pid, 0); // throws when that process is gone
		return true;
	} catch (e) {
		return e.code === 'EPERM';
	}
}

// The native compiler replaces the launcher where npm's link and lix point:
// on Unix hxmc/bootstrap/haxe and dist/haxe (renames in those directories:
// the links keep pointing at them); on Windows npm's haxe.cmd keeps running
// this launcher, and the native compiler is copied to dist/haxe.exe for lix.
export function install(native) {
	// (not in a checkout of the repository, where these files are sources)
	if (process.env.HXMC_INSTALL === '0' || fs.existsSync(path.join(pkgDir, '.git'))) return;
	const targets = process.platform === 'win32' ? [path.join(pkgDir, 'dist', 'haxe.exe')] : [path.join(bootDir, 'haxe'), path.join(pkgDir, 'dist', 'haxe')];
	for (const target of targets) {
		// (already there: the same size, and not older than the native compiler)
		if (fs.existsSync(target)) {
			const t = fs.statSync(target), n = fs.statSync(native);
			if (t.size === n.size && t.mtimeMs >= n.mtimeMs) continue;
		}
		const tmp = `${target}.${process.pid}.new`;
		try {
			fs.copyFileSync(native, tmp);
			fs.chmodSync(tmp, 0o755);
			fs.renameSync(tmp, target);
		} catch {
			fs.rmSync(tmp, { force: true }); // read-only package: stays the launcher
		}
	}
}
