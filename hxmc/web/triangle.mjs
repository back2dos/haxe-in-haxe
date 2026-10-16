// The Graphics section's triangle: packages/gfx/examples/Triangle.hx, built by
// hxmc for wasm32-wasi (`make site`: gfx/triangle.wasm), run by @hxmc/os's
// browser.mjs with the imports.mjs of @hxmc/os and @hxmc/gfx (gfx/os.mjs,
// gfx/gfx.mjs), drawing on the section's canvas with WebGPU. The files carry
// this script's ?v= (the site's build, Version.hx).
const v = new URL(import.meta.url).search;
const canvas = document.getElementById('triangle');
const state = document.getElementById('triangle-state');

function show(text) {
	state.textContent = text;
	state.hidden = false;
}

const NO_WEBGPU = 'WebGPU is not available in this browser, so the triangle cannot be drawn here. It runs in Chrome and Edge 113+, Safari 26+ and Firefox 141+ (Windows).';
if (!navigator.gpu) show(NO_WEBGPU);
else {
	try {
		const { run } = await import('./gfx/browser.mjs' + v);
		const { host } = await run('gfx/triangle.wasm' + v, { imports: ['gfx/os.mjs' + v, 'gfx/gfx.mjs' + v], canvas, stderr: (s) => console.error('triangle: ' + s) });
		// (for the site's browser test)
		canvas.hxmc = host;
		if (!host.gfx.device) show(NO_WEBGPU);
		else if (host.exitCode !== null && host.exitCode !== 0) show('The triangle stopped (exit ' + host.exitCode + '): see the console.');
	} catch (e) {
		console.error(e);
		show('The triangle could not start: ' + e.message);
	}
}
