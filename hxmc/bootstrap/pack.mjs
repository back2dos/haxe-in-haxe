// The npm packages from one build (`make npm`, CI), all at one version:
//   node hxmc/bootstrap/pack.mjs <version> <natives dir> <out dir>
// <natives dir>/<target>/haxe[.exe] are the native compilers (hxmc.HaxeMain,
// cross-built by the tool). Writes to <out dir>, in the order they are
// published (each one's dependencies first):
//   hxmc-<os>-<cpu>-<version>.tgz  the six platform packages @hxmc/<os>-<cpu>:
//                                  the native compiler, with npm's os and cpu
//   hxmc-wasm-<version>.tgz        @hxmc/wasm: the compiler as a wasm32-wasi
//                                  module (hxmc/bootstrap/haxe.wasm) and its
//                                  runner (wasi.mjs)
//   hxmc-source-<version>.tgz      @hxmc/source: haxe/src, hxmc/src, hxmc/std
//                                  and hxmc-rebuild (rebuild.mjs), a peer
//                                  dependency on @hxmc/cli at this version
//   hxmc-cli-<version>.tgz         @hxmc/cli (package.json at the repository
//                                  root): the launcher, the std, hxmc's merged
//                                  std, the runtime objects, dist/ for lix; its
//                                  optional dependencies on the platform
//                                  packages at this version and the integrity
//                                  of @hxmc/wasm's tarball ("hxmc":
//                                  {"wasmIntegrity"}: the launcher's download)
// and sizes.md, their sizes.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { PLATFORMS } from './platforms.mjs';

const root = path.dirname(path.dirname(path.dirname(fileURLToPath(import.meta.url))));
const [version, natives, out] = process.argv.slice(2);
if (!version || !natives || !out) {
	console.error('usage: node hxmc/bootstrap/pack.mjs <version> <natives dir> <out dir>');
	process.exit(2);
}
fs.mkdirSync(out, { recursive: true });
const outAbs = path.resolve(out);
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const sizes = [];
// npm pack's report: {filename, size, unpackedSize, entryCount, integrity}
function pack(cwd) {
	const r = JSON.parse(execFileSync(npm, ['pack', '--json', '--pack-destination', outAbs], { cwd, stdio: ['ignore', 'pipe', 'inherit'], shell: process.platform === 'win32' }).toString())[0];
	console.log(`pack: ${r.filename} (${(r.size / 1024).toFixed(0)} KB, ${(r.unpackedSize / 1024).toFixed(0)} KB unpacked, ${r.entryCount} files)`);
	sizes.push(r);
	return r;
}

const main = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
const common = { version, license: main.license, repository: main.repository };
function stage(name, manifest, files, exec = []) {
	const dir = path.join(outAbs, 'stage', name.replace('/', '-').replace('@', ''));
	fs.rmSync(dir, { recursive: true, force: true });
	fs.mkdirSync(dir, { recursive: true });
	for (const [to, from] of [...files, ['LICENSE', 'LICENSE'], ['COPYING', 'COPYING']]) {
		const src = path.join(root, from);
		if (!fs.existsSync(src)) {
			console.error(`pack: ${src} is missing`);
			process.exit(1);
		}
		fs.mkdirSync(path.dirname(path.join(dir, to)), { recursive: true });
		fs.cpSync(src, path.join(dir, to), { recursive: true });
	}
	for (const f of exec) fs.chmodSync(path.join(dir, f), 0o755);
	fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name, ...common, ...manifest }, null, 2) + '\n');
	return pack(dir);
}

for (const [target, p] of Object.entries(PLATFORMS)) {
	const bin = path.relative(root, path.resolve(natives, target, p.exe));
	stage(p.pkg, {
		description: `The native compiler of @hxmc/cli for ${p.os} ${p.cpu} (the Haxe compiler ported to Haxe, with hxmc built in)`,
		os: [p.os],
		cpu: [p.cpu],
		files: [p.exe, 'LICENSE', 'COPYING'],
	}, [[p.exe, bin]], [p.exe]);
}

const wasm = stage('@hxmc/wasm', {
	description: 'The compiler of @hxmc/cli as a WebAssembly module (wasm32-wasi) with its runner for node: where no native compiler runs (WebContainers, noexec sandboxes); @hxmc/cli uses it when installed, or downloads it',
	type: 'module',
	main: 'wasi.mjs',
	files: ['haxe.wasm', 'wasi.mjs', 'LICENSE', 'COPYING'],
	engines: main.engines,
}, [['haxe.wasm', 'hxmc/bootstrap/haxe.wasm'], ['wasi.mjs', 'hxmc/bootstrap/wasi.mjs']]);

stage('@hxmc/source', {
	description: "The sources of @hxmc/cli's compiler (the Haxe compiler ported to Haxe, hxmc) and hxmc-rebuild, which builds it again from them for @hxmc/cli",
	type: 'module',
	bin: { 'hxmc-rebuild': 'hxmc/bootstrap/hxmc-rebuild' },
	files: ['haxe/src/', 'hxmc/src/', 'hxmc/std/', 'hxmc/bootstrap/', 'LICENSE', 'COPYING'],
	peerDependencies: { '@hxmc/cli': version },
	engines: main.engines,
}, [['haxe/src', 'haxe/src'], ['hxmc/src', 'hxmc/src'], ['hxmc/std', 'hxmc/std'],
	['hxmc/bootstrap/rebuild.mjs', 'hxmc/bootstrap/rebuild.mjs'], ['hxmc/bootstrap/hxmc-rebuild', 'hxmc/bootstrap/hxmc-rebuild']], ['hxmc/bootstrap/hxmc-rebuild']);

// the main package: the version, its platform packages' versions and
// @hxmc/wasm's integrity set for this pack only
const saved = fs.readFileSync(path.join(root, 'package.json'), 'utf8');
try {
	main.version = version;
	main.optionalDependencies = Object.fromEntries(Object.values(PLATFORMS).map(p => [p.pkg, version]));
	main.hxmc = { wasmIntegrity: wasm.integrity };
	fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify(main, null, 2) + '\n');
	pack(root);
} finally {
	fs.writeFileSync(path.join(root, 'package.json'), saved);
}

const kb = n => `${(n / 1024 / 1024).toFixed(1)} MB`;
fs.writeFileSync(path.join(outAbs, 'sizes.md'), [
	'| npm package | tarball | unpacked | files |', '| --- | ---: | ---: | ---: |',
	...sizes.map(s => `| ${s.name}@${s.version} | ${kb(s.size)} | ${kb(s.unpackedSize)} | ${s.entryCount} |`),
].join('\n') + '\n');
console.log(fs.readFileSync(path.join(outAbs, 'sizes.md'), 'utf8'));
