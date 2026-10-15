// hxmc's runtime objects (rt.o, ssl.o, uv.o for the six native targets) are
// built by zig from hxmc/c (the C runtime, mbedtls and libuv: deps.sh,
// mkrt.sh), which a source-only bootstrap cannot do. They are keyed by a hash
// of their inputs (every file of hxmc/c, the zig version it pins) and
// published as the assets of the GitHub release `rt-<hash>`:
//   node hxmc/bootstrap/rt.mjs hash                  the hash
//   node hxmc/bootstrap/rt.mjs fetch <dir>           <dir>/<target>/{rt,ssl,uv}.o and
//                                                    <dir>/LICENSE.{mbedtls,libuv}
//                                                    (exit 2: no such release)
//   node hxmc/bootstrap/rt.mjs pack <dir> <out dir>  the assets of <dir>, gzipped
// <dir>/HASH records what <dir> holds. HXMC_RT_REPO names the repository
// (default benmerckx/haxe-in-haxe).
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(path.dirname(fileURLToPath(import.meta.url))));
export const TARGETS = ['linux-x86_64', 'linux-arm64', 'windows-x86_64', 'windows-arm64', 'macos-x86_64', 'macos-arm64'];
const OBJECTS = ['rt.o', 'ssl.o', 'uv.o'];
const LICENSES = ['LICENSE.mbedtls', 'LICENSE.libuv'];

function files(dir, rel = '') {
	const out = [];
	for (const n of fs.readdirSync(path.join(dir, rel)).sort()) {
		const r = rel ? `${rel}/${n}` : n;
		if (fs.statSync(path.join(dir, r)).isDirectory()) out.push(...files(dir, r));
		else out.push(r);
	}
	return out;
}

export function hash() {
	const h = crypto.createHash('sha256');
	const c = path.join(root, 'hxmc', 'c');
	for (const f of files(c)) {
		h.update(`${f}\0`);
		// (line ends as committed: a Windows checkout may have CRLF)
		h.update(fs.readFileSync(path.join(c, f), 'utf8').replace(/\r\n/g, '\n'));
		h.update('\0');
	}
	h.update(TARGETS.join(','));
	return h.digest('hex').slice(0, 16);
}

function assets() {
	return [...TARGETS.flatMap(t => OBJECTS.map(o => [`${t}/${o}`, `${t}-${o}.gz`])), ...LICENSES.map(l => [l, `${l}.gz`])];
}

function download(url) {
	// curl follows the environment's proxy settings, node's fetch does not
	try {
		return execFileSync('curl', ['-sSfL', '--retry', '3', url], { maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });
	} catch (e) {
		if (e.code !== 'ENOENT') return null;
	}
	return fetch(url).then(r => r.ok ? r.arrayBuffer().then(b => Buffer.from(b)) : null);
}

async function fetchAll(dir) {
	const h = hash();
	const stamp = path.join(dir, 'HASH');
	if (fs.existsSync(stamp) && fs.readFileSync(stamp, 'utf8').trim() === h && assets().every(([f]) => fs.existsSync(path.join(dir, f)))) {
		console.log(`rt: ${dir} holds rt-${h}`);
		return 0;
	}
	const repo = process.env.HXMC_RT_REPO || 'benmerckx/haxe-in-haxe';
	const base = `https://github.com/${repo}/releases/download/rt-${h}/`;
	const got = [];
	for (const [file, asset] of assets()) {
		const data = await download(base + asset);
		if (!data) {
			console.error(`rt: no release rt-${h} in ${repo} (${asset}): build them with zig (make rt-build)`);
			return 2;
		}
		got.push([file, zlib.gunzipSync(data)]);
	}
	for (const [file, data] of got) {
		fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
		fs.writeFileSync(path.join(dir, file), data);
	}
	fs.writeFileSync(stamp, h + '\n');
	console.log(`rt: downloaded rt-${h} into ${dir}`);
	return 0;
}

function pack(dir, out) {
	fs.mkdirSync(out, { recursive: true });
	for (const [file, asset] of assets())
		fs.writeFileSync(path.join(out, asset), zlib.gzipSync(fs.readFileSync(path.join(dir, file)), { level: 9 }));
	console.log(`rt: ${assets().length} assets of rt-${hash()} in ${out}`);
	return 0;
}

const [cmd, ...args] = process.argv.slice(2);
if (cmd === 'hash') console.log(hash());
else if (cmd === 'fetch' && args.length === 1) process.exitCode = await fetchAll(args[0]);
else if (cmd === 'pack' && args.length === 2) process.exitCode = pack(args[0], args[1]);
else {
	console.error('usage: node hxmc/bootstrap/rt.mjs hash | fetch <dir> | pack <dir> <out dir>');
	process.exitCode = 2;
}
