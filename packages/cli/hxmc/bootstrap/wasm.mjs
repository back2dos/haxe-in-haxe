// The compiler as a WebAssembly module (@hxmc/wasm: haxe.wasm and its WASI
// runner wasi.mjs), for machines where no native compiler runs: the
// installed package (npm i @hxmc/wasm, e.g. in WebContainers), else the one
// downloaded into the cache (<cache>/npm/<version>/wasm/), else downloaded
// now: the tarball of the same version from the npm registry
// (npm_config_registry, else the registry of an .npmrc, else
// registry.npmjs.org), checked against the integrity pack.mjs pinned in
// @hxmc/cli's package.json ("hxmc": {"wasmIntegrity"}). HXMC_WASM_TARBALL (a
// path or a URL) replaces the registry's tarball (tests).
import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import zlib from 'node:zlib';
import { notice, npmCache, pkgJson, version } from './launcher.mjs';

const NAME = '@hxmc/wasm';

// the directory of a @hxmc/wasm of this version (haxe.wasm, wasi.mjs)
export async function wasmPackage() {
	try {
		const p = createRequire(import.meta.url).resolve(`${NAME}/package.json`);
		if (JSON.parse(fs.readFileSync(p, 'utf8')).version === version) return path.dirname(p);
	} catch {}
	const dir = path.join(npmCache(), 'wasm');
	if (fs.existsSync(path.join(dir, 'haxe.wasm'))) return dir;
	await download(dir);
	return dir;
}

function fail(text) {
	process.stderr.write(`hxmc: ${text}\n`);
	process.exit(1);
}

// npm's registry for @hxmc: the environment (npm and npx pass their
// configuration on as npm_config_*), else the first .npmrc that names one (the
// project's and its parents', the user's), else npm's default
export function registry() {
	const env = process.env['npm_config_@hxmc:registry'] || process.env.npm_config_registry;
	if (env) return env;
	const rcs = [];
	for (let d = process.cwd(); ; d = path.dirname(d)) {
		rcs.push(path.join(d, '.npmrc'));
		if (path.dirname(d) === d) break;
	}
	rcs.push(process.env.npm_config_userconfig || path.join(os.homedir(), '.npmrc'));
	for (const rc of rcs) {
		let text;
		try {
			text = fs.readFileSync(rc, 'utf8');
		} catch {
			continue;
		}
		const conf = {};
		for (const line of text.split(/\r?\n/)) {
			const m = /^\s*([^#;=\s][^=]*?)\s*=\s*(.*?)\s*$/.exec(line);
			if (m) conf[m[1]] = m[2].replace(/^"(.*)"$/, '$1').replace(/\$\{([^}]+)\}/g, (_, v) => process.env[v] ?? '');
		}
		const r = conf['@hxmc:registry'] || conf.registry;
		if (r) return r;
	}
	return 'https://registry.npmjs.org/';
}

async function fetchBytes(url) {
	if (!/^https?:/.test(url)) return fs.readFileSync(url.startsWith('file:') ? new URL(url) : url);
	let first;
	try {
		const r = await fetch(url);
		if (!r.ok) throw new Error(`HTTP ${r.status}`);
		return Buffer.from(await r.arrayBuffer());
	} catch (e) {
		first = e;
	}
	// (node's fetch does not follow the environment's proxy settings, curl does)
	try {
		return execFileSync('curl', ['-sSfL', '--retry', '2', url], { maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });
	} catch {}
	throw first.cause ?? first;
}

async function download(dir) {
	const integrity = pkgJson.hxmc?.wasmIntegrity;
	const url = process.env.HXMC_WASM_TARBALL || `${registry().replace(/\/+$/, '')}/${NAME}/-/wasm-${version}.tgz`;
	const how = `install it (npm i ${NAME}@${version})`;
	if (!integrity) fail(`no native compiler runs here, and this @hxmc/cli pins no ${NAME} to download: ${how}`);
	notice(`hxmc: no native compiler runs here: downloading ${NAME}@${version} (${url})\n`);
	let tgz;
	try {
		tgz = await fetchBytes(url);
	} catch (e) {
		fail(`no native compiler runs here, and ${NAME}@${version} could not be downloaded from ${url} (${/^HTTP /.test(e.message) ? e.message : `${e.code ?? e.message}; offline?`}): ${how}, or connect to the network`);
	}
	const [algo, want] = integrity.split('-', 2);
	if (crypto.createHash(algo).update(tgz).digest('base64') !== want) fail(`${url} is not the ${NAME}@${version} this @hxmc/cli pins (integrity mismatch)`);
	// extracted next to its place, then renamed into place (a concurrent download wins)
	fs.mkdirSync(path.dirname(dir), { recursive: true });
	const tmp = fs.mkdtempSync(`${dir}.tmp-`);
	try {
		untar(zlib.gunzipSync(tgz), tmp);
		if (!fs.existsSync(path.join(tmp, 'haxe.wasm'))) throw new Error('no haxe.wasm in the tarball');
		try {
			fs.renameSync(tmp, dir);
		} catch (e) {
			if (!fs.existsSync(path.join(dir, 'haxe.wasm'))) throw e;
		}
		notice(`hxmc: ${NAME}@${version} is in ${dir}\n`);
	} catch (e) {
		fail(`unpacking ${NAME}@${version} into ${dir} failed: ${e.message}`);
	} finally {
		fs.rmSync(tmp, { recursive: true, force: true });
	}
}

// the regular files of an npm tarball (ustar, with pax and GNU long names),
// without its package/ prefix
function untar(buf, out) {
	let longName = null;
	for (let at = 0; at + 512 <= buf.length;) {
		const h = buf.subarray(at, at + 512);
		if (h.every(b => b === 0)) break;
		const str = (o, n) => h.subarray(o, o + n).toString('utf8').replace(/\0.*$/s, '');
		const size = parseInt(str(124, 12).trim() || '0', 8);
		const type = String.fromCharCode(h[156] || 48);
		const data = buf.subarray(at + 512, at + 512 + size);
		at += 512 + Math.ceil(size / 512) * 512;
		if (type === 'x') {
			const m = /\d+ path=([^\n]*)\n/.exec(data.toString('utf8'));
			if (m) longName = m[1];
			continue;
		}
		if (type === 'L') {
			longName = data.toString('utf8').replace(/\0.*$/s, '');
			continue;
		}
		if (type === 'g') continue;
		const prefix = str(345, 155);
		let name = longName ?? (prefix ? `${prefix}/${str(0, 100)}` : str(0, 100));
		longName = null;
		if (type !== '0' && type !== '7') continue;
		name = name.replace(/^[^/]*\//, ''); // package/
		if (!name || name.split(/[\\/]/).some(s => s === '..' || s === '') || path.isAbsolute(name)) throw new Error(`bad entry ${name}`);
		const file = path.join(out, name);
		fs.mkdirSync(path.dirname(file), { recursive: true });
		fs.writeFileSync(file, data);
	}
}
