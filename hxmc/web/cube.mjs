// The Graphics section's cube: packages/gfx/examples/Cube.hx, built by hxmc
// for wasm32-wasi (`make site`: gfx/cube.wasm), run by @hxmc/os's
// browser.mjs with the imports.mjs of @hxmc/os and @hxmc/gfx (gfx/os.mjs,
// gfx/gfx.mjs), drawing on the section's canvas with WebGPU, else WebGL2
// (?gfx=webgl2: WebGL2 even with WebGPU; ?cube-angle=a: still, turned by a
// radians, as the tests draw it). The caption names the API it drew with.
// The files carry this script's ?v= (the site's build, Version.hx).
const v = new URL(import.meta.url).search;
const canvas = document.getElementById('cube');
const state = document.getElementById('cube-state');
const api = document.getElementById('cube-api');
const NAMES = { webgpu: 'WebGPU', webgl2: 'WebGL2' };

function show(text) {
	state.textContent = text;
	state.hidden = false;
}

try {
	const query = new URLSearchParams(location.search);
	const gfx = query.get('gfx') ?? undefined, angle = query.get('cube-angle');
	const { run } = await import('./gfx/browser.mjs' + v);
	const { host } = await run('gfx/cube.wasm' + v, {
		imports: ['gfx/os.mjs' + v, 'gfx/gfx.mjs' + v], canvas, gfx, args: angle ? ['--angle', angle] : [],
		stderr: (s) => console.error('cube: ' + s),
	});
	// (for the site's browser test)
	canvas.hxmc = host;
	const name = NAMES[host.gfx.backend];
	if (!name) show('Neither WebGPU nor WebGL2 is available in this browser, so the cube cannot be drawn here.');
	else if (host.exitCode !== null && host.exitCode !== 0) show('The cube stopped (exit ' + host.exitCode + '): see the console.');
	else {
		api.textContent = name;
		canvas.setAttribute('aria-label', 'A rotating textured cube under a translucent panel, drawn with ' + name);
	}
} catch (e) {
	console.error(e);
	show('The cube could not start: ' + e.message);
}
