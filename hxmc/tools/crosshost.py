#!/usr/bin/env python3
"""hxmc's output does not depend on the host it runs on (hxmc/README.md,
"WebAssembly"): the tool built as a WebAssembly module (wasm32-wasi, run under
node) must write the same bytes as the native tool.

    python3 hxmc/tools/crosshost.py [--targets T,T,...] [--tool] [--wasm M] [case ...]

The native tool (bin/hxmc/hxmc) builds itself from source as a module
(bin/hxmc-t/xhost/hxmc.wasm; --wasm reuses one already built), then both
build each corpus case (hxmc/test/cases, all when none is named) for each
target (default: all seven) and the outputs are compared byte for byte;
--tool also builds the tool itself both ways (for the host, about a minute
under node). One line per program, exit 1 if any differs or fails. Outputs
that agree are deleted; differing ones stay in bin/hxmc-t/xhost/<target>/
(<case>-n native, <case>-w the module's).
"""
import argparse, concurrent.futures, os, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "bin/hxmc-t/xhost"
HXMC = ROOT / "bin/hxmc/hxmc"
STD = ROOT / "bin/hxmc/std"
TARGETS = ["linux-x86_64", "linux-arm64", "windows-x86_64", "windows-arm64", "macos-x86_64", "macos-arm64", "wasm32-wasi"]
NODE = ["node", "--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--no-warnings", "--stack-size=65500", str(ROOT / "hxmc/tools/wasi.mjs")]
TOOL_ARGS = ["-cp", str(ROOT / "src"), "-cp", str(ROOT / "hxmc/src"), "-main", "hxmc.Main", "-D", "disable-parallelism", "-D", "hih_no_generators"]


def env_for(target):
    env = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"))
    # the module's own path says nothing about where the runtime objects are
    if target != "wasm32-wasi":
        env["HXMC_RT_OBJ"] = str(ROOT / f"bin/hxmc/rt/{target}/rt.o")
    return env


def build(tool, out, args, target):
    for p in (out, out.with_name(out.name + ".exe")):
        if p.exists():
            p.unlink()
    shutil.rmtree(out.with_name(out.name + ".hxmc"), ignore_errors=True)
    r = subprocess.run(tool + [str(out)] + args + ["-cp", str(STD), "--custom-target", "hxmc", "-D", f"hxmc.target={target}"],
                       cwd=ROOT, env=env_for(target), capture_output=True, text=True)
    shutil.rmtree(out.with_name(out.name + ".hxmc"), ignore_errors=True)
    if not out.exists() and out.with_name(out.name + ".exe").exists():
        out = out.with_name(out.name + ".exe")
    if r.returncode != 0 or not out.exists():
        return None, f"exit {r.returncode}: " + (r.stdout + r.stderr).strip()[-300:]
    return out, None


def compare(wasm, target, case):
    d = OUT / target
    d.mkdir(parents=True, exist_ok=True)
    args = TOOL_ARGS if case == "TOOL" else ["-cp", str(ROOT / "hxmc/test/cases"), "-main", case]
    n, err = build([str(HXMC)], d / f"{case}-n", args, target)
    if err:
        return False, f"native tool: {err}"
    w, err = build(NODE + [str(wasm)], d / f"{case}-w", args, target)
    if err:
        return False, f"module: {err}"
    a, b = n.read_bytes(), w.read_bytes()
    if a == b:
        n.unlink()
        w.unlink()
        return True, f"{len(a)} bytes, identical"
    at = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
    return False, f"DIFFER: {len(a)} / {len(b)} bytes, first at offset {at} ({n.name}, {w.name})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--targets", default=",".join(TARGETS))
    ap.add_argument("--tool", action="store_true")
    ap.add_argument("--wasm")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("cases", nargs="*")
    a = ap.parse_args()
    cases = a.cases or sorted(p.stem for p in (ROOT / "hxmc/test/cases").glob("*.hx"))
    OUT.mkdir(parents=True, exist_ok=True)
    t0 = time.perf_counter()
    if a.wasm:
        wasm = Path(a.wasm).resolve()
    else:
        wasm, err = build([str(HXMC)], OUT / "hxmc.wasm", TOOL_ARGS, "wasm32-wasi")
        if err:
            sys.exit(f"the tool as a module: {err}")
        print(f"the tool as a module: {wasm.stat().st_size} bytes, {time.perf_counter() - t0:.1f}s", flush=True)
    jobs = [(t, c) for t in a.targets.split(",") for c in cases]
    if a.tool:
        jobs.insert(0, ("linux-x86_64", "TOOL"))
    bad = 0
    with concurrent.futures.ThreadPoolExecutor(max(1, a.j)) as ex:
        futs = {ex.submit(compare, wasm, t, c): (t, c) for t, c in jobs}
        for f in concurrent.futures.as_completed(futs):
            t, c = futs[f]
            ok, detail = f.result()
            bad += not ok
            print(f"{t:15} {c:15} {'ok  ' if ok else 'FAIL'} {detail}", flush=True)
    print(f"crosshost: {len(jobs) - bad}/{len(jobs)} identical, {time.perf_counter() - t0:.0f}s")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
