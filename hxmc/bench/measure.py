#!/usr/bin/env python3
"""Run time, size and build time of hxmc's executables (hxmc/README.md, "Numbers").

    python3 hxmc/bench/measure.py [-n RUNS] [-c alloc,nbody,...,port] [--json out.json]

Every case is typed once by the reference compiler into an HXB archive
(`-cp bin/hxmc/std --custom-target hxmc`), compiled by the tool (HXMC_TOOL,
default bin/hxmc/hxmc: a cold build, its object cache removed first) to a
static executable with the runtime object of hxmc/tools/mkrt.sh (the one
next to the tool), and run
RUNS times (the best time is kept). Sizes are of the executable as written
(no symbol table unless -debug). Cases: the HaxeBenchmarks cases of
site/bench/haxebench.py (its checkout, $HAXEBENCH, default bin/haxebench), and
`port`: the port compiling its own source to HXB (site/bench/run.py's "self"
workload). HXMC_STD (default bin/hxmc/std) and HXMC_BENCH_OUT (default
bin/hxmc-bench) let a saved earlier tool, its std and runtime object be
measured beside the current ones. --target wasm32-wasi builds WebAssembly
modules (typed for it) and runs them with --runner node (default) or
wasmtime.
"""
import argparse, json, os, resource, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HB = Path(os.environ.get("HAXEBENCH", ROOT / "bin/haxebench"))
OUT = Path(os.environ.get("HXMC_BENCH_OUT", ROOT / "bin/hxmc-bench"))
HXMC = Path(os.environ.get("HXMC_TOOL", ROOT / "bin/hxmc/hxmc"))
STD = ["-cp", os.environ.get("HXMC_STD", str(ROOT / "bin/hxmc/std"))]

FORMATTER_CPS = ["formatter/src", "tokentree/src", "haxeparser/src", "hxparse/src", "json2object/src", "hxargs", "hxjsonast/src"]
CASES = {
    "alloc": ("alloc", "BMAllocCode", [], []),
    "bcrypt": ("bcrypt", "BMBCryptCode", [str(HB / "libs/crypto/src")], []),
    "binarytrees": ("binarytrees", "BMBinaryTreesCode", [], []),
    "json": ("json", "BMJsonCode", [], []),
    "mandelbrot": ("mandelbrot", "BMMandelbrotCode", [], []),
    "mandelbrot_anon": ("mandelbrot_anon_objects", "BMMandelbrotCode", ["../mandelbrot"], ["anon_objects"]),
    "nbody": ("nbody", "BMNBodyCode", [], []),
    "sha256": ("sha256", "BMSHA256Code", [], []),
    "sha512": ("sha512", "BMSHA512Code", [str(HB / "libs/crypto/src")], []),
    "formatter_noio": ("formatter_noio", "BMFormatterNoIOCode", [str(HB / "libs" / d) for d in FORMATTER_CPS], [d.split("/")[0] for d in FORMATTER_CPS]),
    "port": None,
}


def unlimited():
    resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))


def env():
    return dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"))


def run(cmd, cwd=None):
    r = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, preexec_fn=unlimited)
    if r.returncode != 0:
        raise RuntimeError(" ".join(map(str, cmd)) + "\n" + r.stdout.decode(errors="replace")[-2000:])
    return r.stdout


def case_args(case, out):
    """(haxe arguments, their cwd, the executable's arguments, its cwd)"""
    if case == "port":
        return ["-cp", "src", "-main", "haxe.Main", "-D", "disable-parallelism"], ROOT, \
            ["-cp", "src", "-main", "haxe.Main", "-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out / "self.hxb")], ROOT
    d, main, cps, defs = CASES[case]
    cwd = HB / "runner/cases" / d
    runcwd = cwd / "out"
    runcwd.mkdir(exist_ok=True)
    return ["-cp", "."] + sum([["-cp", c] for c in cps], []) + ["-main", main] + sum([["-D", x] for x in defs], []), cwd, [], runcwd


TARGET = None


def build(case):
    out = OUT / case
    out.mkdir(parents=True, exist_ok=True)
    args, cwd, runargs, runcwd = case_args(case, out)
    tgt = ["-D", "hxmc.target=" + TARGET] if TARGET else []
    hxb = out / "prog.hxb.zip"
    run([ROOT / "haxe/haxe"] + args + STD + ["--custom-target", f"hxmc={out}/x", "--hxb", hxb, "--no-output"] + tgt, cwd=cwd)
    main = args[args.index("-main") + 1]
    exe = out / ("bin-hxmc.wasm" if TARGET and TARGET.startswith("wasm") else "bin-hxmc")
    shutil.rmtree(str(exe) + ".hxmc", ignore_errors=True)
    t = time.perf_counter()
    run([HXMC, exe, "--hxb-lib", hxb, "-main", main, "--custom-target", "hxmc", "-D", "disable-parallelism"] + tgt, cwd=ROOT)
    return exe, time.perf_counter() - t, runargs, runcwd


def timed(cmd, cwd, n):
    best = None
    for _ in range(n):
        t = time.perf_counter()
        p = subprocess.Popen(cmd, cwd=cwd, env=env(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, preexec_fn=unlimited)
        _, err = p.communicate()
        t = time.perf_counter() - t
        if p.returncode != 0:
            raise RuntimeError(f"exit {p.returncode}: {err.decode(errors='replace')[-500:]}")
        best = t if best is None else min(best, t)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-c", default=",".join(CASES))
    ap.add_argument("--json")
    ap.add_argument("--target", help="hxmc.target (wasm32-wasi: run with --runner)")
    ap.add_argument("--runner", default="node", help="node or wasmtime (wasm32-wasi)")
    a = ap.parse_args()
    global TARGET
    TARGET = a.target
    wasm = bool(TARGET and TARGET.startswith("wasm"))
    results = json.load(open(a.json)) if a.json and os.path.exists(a.json) else {}
    for case in a.c.split(","):
        try:
            exe, ct, runargs, runcwd = build(case)
            pre = []
            if wasm:
                pre = ["wasmtime", "run", "-W", "exceptions=y", "-W", "max-wasm-stack=67108864", "--dir", "/", "--env", "PWD=" + str(runcwd)] if a.runner == "wasmtime" else \
                    ["node", "--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--stack-size=65500", "--no-warnings", str(ROOT / "hxmc/tools/wasi.mjs")]
            rt = timed(pre + [str(exe)] + runargs, runcwd, a.n)
            kb = (exe.stat().st_size + 1023) // 1024
            results[case] = {"build": round(ct, 2), "run": round(rt, 3), "kb": kb}
            print(f"{case:16} build {ct:6.2f}s  run {rt:7.3f}s  size {kb:7} KB", flush=True)
        except Exception as e:
            results[case] = {"error": str(e)[-300:]}
            print(f"{case:16} FAILED: {str(e).strip().splitlines()[-1]}", flush=True)
        if a.json:
            json.dump(results, open(a.json, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
