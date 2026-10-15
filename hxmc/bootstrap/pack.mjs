// The npm packages from one build (`make npm`, CI):
//   node hxmc/bootstrap/pack.mjs <version> <natives dir> <out dir>
// <natives dir>/<target>/haxe[.exe] are the native compilers (hxmc.HaxeMain,
// cross-built by the tool). Writes <out dir>/hxmc-<version>.tgz (the main
// package, package.json at the repository root, its optionalDependencies on
// the platform packages at the same version) and one hxmc-<os>-<cpu>-<version>.tgz
// per platform package (@hxmc/<os>-<cpu>: the native compiler and the licenses,
// with npm's os and cpu fields).
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
const pack = cwd => execFileSync(npm, ['pack', '--pack-destination', outAbs], { cwd, stdio: ['ignore', 'pipe', 'inherit'], shell: process.platform === 'win32' }).toString().trim().split('\n').pop();

const main = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
for (const [target, p] of Object.entries(PLATFORMS)) {
	const bin = path.join(natives, target, p.exe);
	if (!fs.existsSync(bin)) {
		console.error(`pack: ${bin} is missing`);
		process.exit(1);
	}
	const stage = path.join(outAbs, 'stage', p.pkg.replace('/', '-').replace('@', ''));
	fs.rmSync(stage, { recursive: true, force: true });
	fs.mkdirSync(stage, { recursive: true });
	fs.copyFileSync(bin, path.join(stage, p.exe));
	fs.chmodSync(path.join(stage, p.exe), 0o755);
	for (const f of ['LICENSE', 'COPYING']) fs.copyFileSync(path.join(root, f), path.join(stage, f));
	fs.writeFileSync(path.join(stage, 'package.json'), JSON.stringify({
		name: p.pkg,
		version,
		description: `The native compiler of the hxmc package for ${p.os} ${p.cpu} (the Haxe compiler ported to Haxe, with hxmc built in)`,
		license: main.license,
		repository: main.repository,
		os: [p.os],
		cpu: [p.cpu],
		files: [p.exe, 'LICENSE', 'COPYING'],
	}, null, 2) + '\n');
	console.log(`pack: ${pack(stage)}`);
}
// the main package: the version and its platform packages' versions set for this pack only
const saved = fs.readFileSync(path.join(root, 'package.json'), 'utf8');
try {
	main.version = version;
	main.optionalDependencies = Object.fromEntries(Object.values(PLATFORMS).map(p => [p.pkg, version]));
	fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify(main, null, 2) + '\n');
	console.log(`pack: ${pack(root)}`);
} finally {
	fs.writeFileSync(path.join(root, 'package.json'), saved);
}
