// EXPERIMENTAL: runs a module from backend/ under Node: node run.js prog.wasm
const fs = require("fs");
const out = [];
const t0 = process.hrtime.bigint();
const mod = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
const t1 = process.hrtime.bigint();
const inst = new WebAssembly.Instance(mod, { env: { printInt: (v) => out.push(String(v)) } });
inst.exports.main();
const t2 = process.hrtime.bigint();
process.stdout.write(out.join("\n") + "\n");
if (process.env.RT_STATS) console.error(`compile ${(Number(t1 - t0) / 1e6).toFixed(1)} ms, run ${(Number(t2 - t1) / 1e6).toFixed(1)} ms`);
