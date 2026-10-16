// The Graphics section's triangle: packages/gfx/examples/Triangle.hx, built by
// hxmc for wasm32-wasi (`make site`: gfx/triangle.wasm), run by @hxmc/os's
// browser.mjs with the imports.mjs of @hxmc/os and @hxmc/gfx (gfx/os.mjs,
// gfx/gfx.mjs), drawing on the section's canvas with WebGPU, else WebGL2
// (?gfx=webgl2: WebGL2 even with WebGPU). The caption names the one it drew
// with. The files carry this script's ?v= (the site's build, Version.hx).
const v = new URL(import.meta.url).search;
const canvas = document.getElementById('triangle');
const state = document.getElementById('triangle-state');
const api = document.getElementById('triangle-api');
const NAMES = { webgpu: 'WebGPU', webgl2: 'WebGL2' };

function show(text) {
	state.textContent = text;
	state.hidden = false;
}

try {
	const gfx = new URLSearchParams(location.search).get('gfx') ?? undefined;
	const { run } = await import('./gfx/browser.mjs' + v);
	const { host } = await run('gfx/triangle.wasm' + v, { imports: ['gfx/os.mjs' + v, 'gfx/gfx.mjs' + v], canvas, gfx, stderr: (s) => console.error('triangle: ' + s) });
	// (for the site's browser test)
	canvas.hxmc = host;
	const name = NAMES[host.gfx.backend];
	if (!name) show('Neither WebGPU nor WebGL2 is available in this browser, so the triangle cannot be drawn here.');
	else if (host.exitCode !== null && host.exitCode !== 0) show('The triangle stopped (exit ' + host.exitCode + '): see the console.');
	else {
		api.textContent = name;
		canvas.setAttribute('aria-label', 'A triangle with a red, a green and a blue corner, drawn with ' + name);
	}
} catch (e) {
	console.error(e);
	show('The triangle could not start: ' + e.message);
}
