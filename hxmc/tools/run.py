#!/usr/bin/env python3
"""The hxmc test corpus (hxmc/README.md, "Tests"): every program compiled by
hxmc, run, and its output compared with its golden file.

    python3 hxmc/tools/run.py [-j N] [-v] [--target T] [--stage DIR] [--bless] [case ...]

The cases are the programs of hxmc/test/cases (<Name>.hx with class <Name>)
and the fuzzer programs frozen in hxmc/test/fuzz-1000.tar.gz (extracted to
bin/hxmc-fuzz, cases fuzz-<seed>). Each case's HXB archive is written once
by the reference compiler (`-cp bin/hxmc/std --custom-target hxmc`; cached,
rewritten when a source is newer); hxmc (bin/hxmc/hxmc) compiles it and the
output ("exit <code>" and stdout) must equal hxmc/test/expected/<case>.txt.

The golden files were written by hxc (the C target) when hxmc separated from
it, and are frozen: a new case gets its golden file with --bless (written
from hxmc's own output, to be checked by hand before committing). --target
cross-builds for another hxmc target (linux-arm64 runs under
qemu-aarch64-static, windows-x86_64 under wine64, wasm32-wasi under node or
wasmtime: HXMC_WASM_RUNNER=wasmtime); --stage only builds and
copies each executable with its golden file to DIR/<case>/ (hxmc/tools/check.py
runs them on the target's machine, the CI workflow .github/workflows/hxmc.yml).
"""
import argparse, concurrent.futures, os, re, shutil, subprocess, sys, tarfile, time, resource
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "bin/hxmc-t"
HAXE = os.environ.get("HAXE", str(ROOT / "haxe/haxe"))
HXMC = Path(os.environ.get("HXMC_TOOL", str(ROOT / "bin/hxmc/hxmc")))
STD = ROOT / "bin/hxmc/std"
CASES = ROOT / "hxmc/test/cases"
EXPECTED = ROOT / "hxmc/test/expected"
FUZZ_TAR = ROOT / "hxmc/test/fuzz-1000.tar.gz"
FUZZ = ROOT / "bin/hxmc-fuzz"
ENV = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"), WINEDEBUG="-all")


def unlimited():
    resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))


def sh(cmd, cwd=ROOT, env=ENV, timeout=300):
    r = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, capture_output=True, preexec_fn=unlimited, timeout=timeout)
    return r.returncode, r.stdout.decode(errors="replace"), r.stderr.decode(errors="replace")


def newest(paths):
    t = 0
    for p in paths:
        for f in ([p] if p.is_file() else p.rglob("*.hx")):
            t = max(t, f.stat().st_mtime)
    return t


def fuzz_programs():
    stamp = FUZZ / ".stamp"
    if not stamp.exists() or stamp.stat().st_mtime < FUZZ_TAR.stat().st_mtime:
        if FUZZ.exists():
            shutil.rmtree(FUZZ)
        FUZZ.mkdir(parents=True)
        with tarfile.open(FUZZ_TAR) as t:
            t.extractall(FUZZ, filter="data")
        stamp.touch()
    return sorted(d for d in FUZZ.iterdir() if (d / "Main.hx").exists())


def case_list(names):
    cases = [(p.stem, [CASES], p.stem) for p in sorted(CASES.glob("*.hx"))]
    cases += [("fuzz-" + d.name, [d], "Main") for d in fuzz_programs()]
    if names:
        known = {c[0]: c for c in cases}
        bad = [n for n in names if n not in known]
        if bad:
            sys.exit("run.py: unknown case(s): " + ", ".join(bad))
        cases = [known[n] for n in names]
    return cases


# the cases a WebAssembly module cannot run (hxmc/README.md, "WebAssembly")
WASM_EXCLUDED = {"ThreadNatives": "no threads on wasm32-wasi", "NetNatives": "no sockets on wasm32-wasi"}


def run_case(name, cps, main, args):
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    # (WebAssembly: the program is typed for it, with its runtime)
    wasm = bool(args.target and args.target.startswith("wasm"))
    if wasm and name in WASM_EXCLUDED:
        return name, "excluded", WASM_EXCLUDED[name]
    hxb = d / ("prog-" + args.target + ".hxb.zip" if wasm else "prog.hxb.zip")
    src_t = newest(cps)
    t0 = time.perf_counter()
    if not hxb.exists() or hxb.stat().st_mtime < max(src_t, (STD / ".stamp").stat().st_mtime):
        cmd = [HAXE] + sum([["-cp", c] for c in cps], []) + ["-cp", STD, "-main", main, "--custom-target", f"hxmc={d}/x",
               "--hxb", hxb, "-D", "disable-parallelism", "--no-output"] + (["-D", "hxmc.target=" + args.target] if wasm else [])
        code, o, e = sh(cmd)
        if code != 0:
            return name, "hxb-fail", (o + e)[-1500:]
    expected = EXPECTED / (name + ".txt")
    if not expected.exists() and not args.bless:
        return name, "no-golden", f"{expected} is missing (--bless writes it from hxmc's output)"
    env = dict(ENV, HXMC_STATS="1")
    tgt = ["-D", "hxmc.target=" + args.target] if args.target else []
    exe = d / ("m-" + args.target if args.target else "m")
    if args.target and args.target.startswith("windows"):
        exe = d / ("m-" + args.target + ".exe")
    if args.target and args.target.startswith("wasm"):
        exe = d / ("m-" + args.target + ".wasm")
    code, o, e = sh([HXMC, exe, "--hxb-lib", hxb, "-main", main, "--custom-target", "hxmc", "-D", "disable-parallelism"] + tgt, env=env)
    (d / "hxmc.log").write_text(o + e)
    if code != 0:
        return name, "hxmc-fail", (o + e)[-2000:]
    m = re.search(r"hxmc: (\d+) functions", o)
    nf = m.group(1) + " functions" if m else ""
    if args.stage:
        # cross builds: the executable and the expected output, run elsewhere (check.py)
        sd = Path(args.stage) / name
        sd.mkdir(parents=True, exist_ok=True)
        shutil.copy(exe, sd / ("m" + exe.suffix))
        shutil.copy(expected, sd / "expected.txt")
        return name, "ok", "staged " + nf
    try:
        runner = {"linux-arm64": ["qemu-aarch64-static"], "windows-x86_64": ["/usr/lib/wine/wine64"]}.get(args.target, [])
        if args.target and args.target.startswith("wasm"):
            runner = wasm_runner()
        # a small nursery: frequent collections, so a missing or stale root shows
        code, o, e = sh(runner + [exe], cwd=d, timeout=120, env=dict(ENV, RT_MINOR_KB=os.environ.get("RT_MINOR_KB", "64")))
    except subprocess.TimeoutExpired:
        return name, "timeout", ""
    got = f"exit {code}\n" + o
    if args.bless and not expected.exists():
        expected.write_bytes(got.encode())
        return name, "blessed", f"wrote {expected} (check it)"
    if got.encode() != expected.read_bytes():
        (d / "got.txt").write_bytes((got + e).encode())
        return name, "differs", f"diff {expected} {d / 'got.txt'}\n" + e[-800:]
    return name, "ok", f"{time.perf_counter() - t0:.1f}s {nf}"


# node 22: exception handling with exnref is behind a flag; its WASI's fd_write
# is a fast API call that can start a collection of V8's heap with a large
# WebAssembly memory, which crashes: no fast API calls
NODE_FLAGS = ["--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--no-warnings"]


def wasm_runner():
    """wasm32-wasi: node (hxmc/tools/wasi.mjs) or, with HXMC_WASM_RUNNER=wasmtime, wasmtime"""
    if os.environ.get("HXMC_WASM_RUNNER") == "wasmtime":
        return ["wasmtime", "run", "-W", "exceptions=y", "--dir", ".", "--dir", "/", "--env", "RT_MINOR_KB"]
    return ["node"] + NODE_FLAGS + [str(ROOT / "hxmc/tools/wasi.mjs")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-v", action="store_true", help="print the details of failures")
    ap.add_argument("--target", help="hxmc.target (run with qemu-aarch64-static / wine64 as needed)")
    ap.add_argument("--stage", help="do not run: copy each executable and its golden file to <dir>/<case>/ (hxmc/tools/check.py runs them)")
    ap.add_argument("--bless", action="store_true", help="write the golden file of a case that has none from hxmc's output")
    ap.add_argument("cases", nargs="*")
    a = ap.parse_args()
    if not (STD / ".stamp").exists():
        sys.exit("run.py: bin/hxmc/std is missing (python3 hxmc/tools/mkstd.py, or make -f hxmc/Makefile)")
    cases = case_list(a.cases)
    t = time.perf_counter()
    bad = excluded = 0
    with concurrent.futures.ThreadPoolExecutor(a.j) as ex:
        for name, status, detail in ex.map(lambda c: run_case(*c, a), cases):
            print(f"{name:24} {status:12} {detail if status in ('ok', 'blessed', 'excluded') or not a.v else ''}", flush=True)
            if status == "excluded":
                excluded += 1
            elif status not in ("ok", "blessed"):
                bad += 1
                if a.v:
                    print("    " + detail.replace("\n", "\n    "))
    print(f"{len(cases) - bad - excluded}/{len(cases) - excluded} ok" + (f" ({excluded} excluded)" if excluded else "") + f", {time.perf_counter() - t:.1f}s")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
