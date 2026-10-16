// The playground's compiler in real browsers (Playwright: chromium, firefox,
// webkit): serves a built site (`make site`), starts its worker as the page
// does and runs a program with --interp, compiles it to HXB, and asks for
// diagnostics and a completion, with each of the two modules (hih.wasm:
// exception handling with exnref; hih-legacy.wasm: the legacy instructions).
// Then the page itself (index.html, Monaco blocked: its plain editor): the
// module it picks (hih.wasm; hih-legacy.wasm with ?eh=legacy, and in a
// Chromium whose V8 runs without exnref) and a Run of its first example.
// With a benchmark history in the site (bench/, `make site BENCH_DATA=...`):
// the Programs tables (run time, compile time) with the "Over time" charts
// hidden, and with ?bench-history one chart per case with a hover tooltip, in
// light and dark mode, and at a phone's width (screenshots into $SCREENSHOTS
// when set).
//   node hxmc/web/tools/browser-test.mjs bin/site [chromium firefox webkit]
// (Playwright from npm, with its browsers: npx playwright install)
import { createServer } from 'node:http';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch { pw = require(path.join(process.execPath, '../../lib/node_modules/playwright')); }
const dir = process.argv[2];
const names = process.argv.length > 3 ? process.argv.slice(3) : ['chromium', 'firefox', 'webkit'];
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.css': 'text/css', '.json': 'application/json' };
const modules = ['hih.wasm', 'hih-legacy.wasm'].filter((m) => existsSync(path.join(dir, m)));
const server = createServer(async (req, res) => {
	const p = path.join(dir, decodeURIComponent(new URL(req.url, 'http://x').pathname));
	try {
		const b = req.url === '/' ? Buffer.from('<!doctype html><title>test</title>') : await readFile(p);
		res.writeHead(200, { 'content-type': req.url === '/' ? 'text/html' : types[path.extname(p)] || 'application/octet-stream' });
		res.end(b);
	} catch {
		res.writeHead(404);
		res.end();
	}
}).listen(0);
const port = server.address().port;

const code = 'class Main {\n\tstatic function main() {\n\t\tvar a = [for (i in 0...5) i * i];\n\t\ttrace("Hello " + a);\n\t\ttry throw "oops" catch (e:String) Sys.println("caught " + e);\n\t\tSys.println(haxe.Json.stringify({ok: true}));\n\t}\n}\n';

async function inPage([code, wasm]) {
	const w = new Worker('worker.js');
	const replies = [];
	let wake = null;
	w.onmessage = (e) => { replies.push(e.data); if (wake) wake(); };
	w.onerror = (e) => { replies.push({ type: 'failed', message: e.message }); if (wake) wake(); };
	async function until(pred) {
		while (true) {
			const i = replies.findIndex(pred);
			if (i >= 0) return replies.splice(i, 1)[0];
			await new Promise((r) => (wake = r));
		}
	}
	const log = [];
	const t0 = performance.now();
	w.postMessage({ type: 'module', module: await WebAssembly.compileStreaming(fetch(wasm)) });
	w.postMessage({ type: 'warmup' });
	const ready = await until((r) => r.type === 'ready' || r.type === 'failed');
	log.push(`ready ${ready.type} ${ready.message ?? ''} ${Math.round(performance.now() - t0)} ms`);
	if (ready.type === 'failed') return log;
	// (three times: the engines optimize the module's code while it runs)
	for (let k = 0; k < 3; k++) {
		w.postMessage({ type: 'compile', id: 1, mode: 'run', main: 'Main', file: 'Main.hx', code });
		const done = await until((r) => r.type === 'done' || r.type === 'failed');
		for (const r of replies.splice(0)) if (k == 0) log.push(`${r.type} ${r.text}`);
		log.push(`run ${done.status} ${Math.round(done.ms)} ms ${done.message ?? ''}`);
	}
	w.postMessage({ type: 'compile', id: 2, mode: 'hxb', main: 'Main', file: 'Main.hx', code });
	const hxb = await until((r) => r.type === 'done' || r.type === 'failed');
	replies.splice(0);
	log.push(`hxb ${hxb.status} ${hxb.zip ? hxb.zip.byteLength + ' bytes' : hxb.message} ${Math.round(hxb.ms)} ms`);
	w.postMessage({ type: 'check', id: 3, main: 'Main', file: 'Main.hx', code: code.replace('trace(', 'trace(undefinedThing + ') });
	const check = await until((r) => r.type === 'check' || r.type === 'failed');
	log.push(`check ${check.status} ${JSON.stringify(check.output)}`);
	const at = code.indexOf(' + a') + 4;
	const dcode = code.slice(0, at) + '.' + code.slice(at);
	w.postMessage({ type: 'display', id: 4, main: 'Main', file: 'Main.hx', code: dcode,
		request: { jsonrpc: '2.0', id: 1, method: 'display/completion', params: { file: '/work/Main.hx', offset: at + 1, wasAutoTriggered: true } } });
	const disp = await until((r) => r.type === 'display' || r.type === 'failed');
	log.push(`display ${disp.status} ${(disp.output ?? disp.message).slice(0, 120)}`);
	w.terminate();
	return log;
}

// the page: the module it fetches, then a Run of the example it loads
async function pageTest(browser, query, expect) {
	const page = await browser.newPage();
	const fetched = [];
	page.on('request', (r) => { const p = new URL(r.url()).pathname; if (p.endsWith('.wasm')) fetched.push(path.basename(p)); });
	await page.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
	await page.goto(`http://localhost:${port}/index.html${query}`);
	await page.evaluate(() => document.getElementById('playground').scrollIntoView());
	const state = () => page.evaluate(() => document.getElementById('state').textContent);
	await page.waitForFunction(() => /^Ready|cannot|could not/.test(document.getElementById('state').textContent), null, { timeout: 180000 });
	const ready = await state();
	let run = '';
	if (ready.startsWith('Ready')) {
		await page.waitForFunction(() => document.querySelector('textarea[aria-label="Haxe source"]')?.value, null, { timeout: 30000 });
		await page.click('#run');
		await page.waitForFunction(() => /^exit/.test(document.getElementById('timing').textContent), null, { timeout: 180000 });
		run = await page.evaluate(() => document.getElementById('timing').textContent + ': ' + document.getElementById('out').textContent.trim().split('\n')[0]);
	}
	await page.close();
	const ok = fetched.length === 1 && fetched[0] === expect && run.startsWith('exit 0');
	console.log(`  page${query} ${ok ? 'ok' : 'FAILED'}: fetched ${fetched.join(', ') || 'nothing'} (expected ${expect}); ${ready}; ${run}`);
	return ok;
}

// the Programs benchmarks: the latest run's table and the compile-time table
// below it, with the "Over time" charts hidden; then with ?bench-history (the
// charts' code kept for later) one chart per case with a hover tooltip; at a
// phone's width, no horizontal scrolling of the page
async function benchTest(browser, name) {
	let ok = true;
	const latest = existsSync(path.join(dir, 'bench/latest.json'));
	const views = [
		{ colorScheme: 'light', width: 1100, query: '' },
		{ colorScheme: 'dark', width: 1100, query: '' },
		{ colorScheme: 'light', width: 1100, query: '?bench-history' },
		{ colorScheme: 'dark', width: 1100, query: '?bench-history' },
		{ colorScheme: 'light', width: 375, query: '' },
	];
	for (const { colorScheme, width, query } of views) {
		const view = `${colorScheme}, ${width} px${query ? ', ' + query : ''}`;
		let pass = true;
		const page = await browser.newPage({ colorScheme, viewport: { width, height: 900 } });
		const errors = [];
		page.on('pageerror', (e) => errors.push(e.message));
		await page.route(/^https:\/\/cdn\.jsdelivr\.net\//, (r) => r.abort());
		await page.goto(`http://localhost:${port}/index.html${query}`);
		let facts = '';
		try {
			// (the tables: the latest run, which a history of imported points only lacks)
			if (latest) {
				await page.waitForSelector('#programs-results table', { timeout: 30000 });
				await page.waitForSelector('#programs-compile table', { timeout: 5000 });
			}
			if (query) {
				await page.waitForSelector('#programs-history svg', { timeout: 30000 });
				const svg = page.locator('#programs-history .plot svg').first();
				await svg.scrollIntoViewIfNeeded();
				const box = await svg.boundingBox();
				await svg.hover({ position: { x: box.width * 0.95, y: box.height / 2 } });
				await page.waitForSelector('#programs-history .tip:not([hidden])', { timeout: 5000 });
			} else {
				// (the history would have been fetched and drawn by now if it were shown)
				await page.waitForTimeout(500);
			}
			facts = await page.evaluate(() => {
				const q = (s) => document.querySelectorAll(s).length;
				const visible = (e) => !!e && e.getClientRects().length > 0 && getComputedStyle(e).visibility !== 'hidden';
				const compileCells = [...document.querySelectorAll('#programs-compile tbody tr:not(.ref) td.num')];
				return {
					rows: q('#programs-results tbody tr'),
					cols: q('#programs-results thead th'),
					tabs: [...document.querySelectorAll('#programs-results .tabs button')].map((b) => b.textContent).join(','),
					compileRows: q('#programs-compile tbody tr:not(.ref)'),
					compileCols: q('#programs-compile thead th'),
					compileVisible: visible(document.querySelector('#programs-compile table')),
					compileValues: compileCells.filter((td) => /\d/.test(td.textContent)).length,
					compileSplit: q('#programs-compile td .parts'),
					compileNote: (document.querySelector('#programs-compile .note')?.textContent ?? '').slice(0, 40),
					historyVisible: visible(document.getElementById('programs-over-time')),
					charts: q('#programs-history svg'),
					lines: q('#programs-history svg .series path'),
					tip: document.querySelector('#programs-history .tip')?.textContent.slice(0, 60) ?? '',
					series: getComputedStyle(document.documentElement).getPropertyValue('--s1').trim(),
					pageScroll: document.documentElement.scrollWidth - document.documentElement.clientWidth,
				};
			});
			if (latest && (facts.rows < 1 || !facts.compileVisible || facts.compileRows !== facts.rows || facts.compileCols !== facts.cols || facts.compileValues < 1 || !/Compile time/.test(await page.textContent('#programs-compile h4'))))
				pass = false;
			if (query ? !facts.historyVisible || facts.charts < 1 || facts.lines < 1 : facts.historyVisible || facts.charts > 0) pass = false;
			if (facts.pageScroll > 0) pass = false;
			if (process.env.SCREENSHOTS) {
				await page.locator('#benchmarks').screenshot({ path: path.join(process.env.SCREENSHOTS, `bench-${name}-${colorScheme}-${width}${query ? '-history' : ''}.png`) });
			}
		} catch (e) {
			pass = false;
			facts = e.message.split('\n')[0];
		}
		if (errors.length) pass = false;
		if (!pass) ok = false;
		console.log(`  benchmarks (${view}) ${pass ? 'ok' : 'FAILED'}: ${JSON.stringify(facts)}${errors.length ? '; errors: ' + errors.join('; ') : ''}`);
		await page.close();
	}
	return ok;
}

let failed = 0;
const launches = names.map((name) => ({ name, label: name, opts: {} }));
// (a Chromium without exnref: the page falls back to the legacy module by itself)
if (names.includes('chromium') && modules.includes('hih-legacy.wasm'))
	launches.push({ name: 'chromium', label: 'chromium without exnref', opts: { args: ['--js-flags=--no-experimental-wasm-exnref'] }, noExnref: true });
for (const { name, label, opts, noExnref } of launches) {
	let browser;
	try {
		browser = await pw[name].launch(opts);
		console.log(`== ${label} ${browser.version()}`);
		if (noExnref) {
			// (the error the exnref module gets there, as in browsers without exnref)
			const page = await browser.newPage();
			await page.goto(`http://localhost:${port}/`);
			const err = await page.evaluate(async () => {
				try { await WebAssembly.compileStreaming(fetch('hih.wasm')); return 'compiled'; } catch (e) { return e.message; }
			});
			await page.close();
			console.log(`  hih.wasm: ${err}`);
			if (err === 'compiled') failed++;
			if (!(await pageTest(browser, '', 'hih-legacy.wasm'))) failed++;
			continue;
		}
		for (const wasm of modules) {
			const page = await browser.newPage();
			await page.goto(`http://localhost:${port}/`);
			const log = await page.evaluate(inPage, [code, wasm]);
			await page.close();
			console.log(`  ${wasm}`);
			for (const l of log) console.log('    ' + l);
			if (!log.some((l) => l.startsWith('run 0')) || !log.some((l) => l.startsWith('hxb 0'))) failed++;
		}
		if (existsSync(path.join(dir, 'bench/history.json')) && !(await benchTest(browser, name))) failed++;
		if (existsSync(path.join(dir, 'index.html'))) {
			if (!(await pageTest(browser, '', 'hih.wasm'))) failed++;
			if (modules.includes('hih-legacy.wasm') && !(await pageTest(browser, '?eh=legacy', 'hih-legacy.wasm'))) failed++;
		}
	} catch (e) {
		console.log(`== ${label}: ${e.message.split('\n')[0]}`);
		failed++;
	} finally {
		if (browser) await browser.close();
	}
}
server.close();
process.exit(failed ? 1 : 0);
