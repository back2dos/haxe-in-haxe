#!/usr/bin/env python3
"""How much optimization the generated code needs (hxmc/README.md, "Step 0").

    python3 hxmc/bench/measure.py [-n RUNS] [-c alloc,nbody,...,port] [-v tcc,O1,O2,hxmc] [--json out.json]

Every case is lowered to C once by the hxc tool (bin/hxc-dev/tool); the
runtime (hxc/rt) is compiled once with clang -O2; only the generated C
changes between the variants:

  tcc   the generated C by tcc (no optimization at all: a naive code generator)
  O1    clang -O1
  O2    clang -O2 (what hxmc must match)
  hxmc  the case compiled by hxmc (bin/hxmc/hxmc, development build linked
        with bin/hxmc/rt-dev: the runtime by clang -O2 with OS threads)
  hxmcs the shipped path: hxmc's own linker, a static executable with the
        runtime object of hxmc/tools/mkrt.sh (musl, zig cc -O2)
  O1ni  clang -O1 -fno-inline-functions: no inlining of Haxe functions
        (the runtime helpers marked inline still are)

The runtime is built with green threads (-DRT_GREEN_THREADS) so that tcc's
code (which cannot use TLS) and clang's agree on it; the cases are single
threaded. Cases: the HaxeBenchmarks cases of site/bench/haxebench.py (its
checkout, $HAXEBENCH, default bin/haxebench), and `port`: the port compiling
its own source to HXB (site/bench/run.py's "self" workload).
"""
import argparse, concurrent.futures, json, os, resource, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HB = Path(os.environ.get("HAXEBENCH", ROOT / "bin/haxebench"))
OUT = ROOT / "bin/hxmc-bench"
TOOL = ROOT / "bin/hxc-dev/tool"
RT = ROOT / "hxc/rt"
RT_FILES = ["rt", "rt_dyn", "rt_std", "rt_str", "rt_sys", "rt_net", "rt_ssl", "rt_uv", "rt_thread", "rt_census"]
BASE = ["-w", "-fno-strict-aliasing", "-DHXC_NO_SSL", "-DHXC_NO_UV", "-DHXC_CONST_IDS", "-DRT_GREEN_THREADS", "-I", str(RT)]
VARIANTS = {"tcc": ["tcc"], "O1": ["clang", "-O1"], "O2": ["clang", "-O2"], "O1ni": ["clang", "-O1", "-fno-inline-functions"]}
JOBS = os.cpu_count() or 4

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


def run(cmd, cwd=None, env=None):
    r = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, preexec_fn=unlimited)
    if r.returncode != 0:
        raise RuntimeError(" ".join(map(str, cmd)) + "\n" + r.stdout.decode(errors="replace")[-2000:])
    return r.stdout


def compile_all(cc, jobs):
    """jobs: (src, obj) pairs; compiles the missing or stale ones in parallel."""
    todo = [(s, o) for s, o in jobs if not o.exists() or o.stat().st_mtime < s.stat().st_mtime]
    with concurrent.futures.ThreadPoolExecutor(JOBS) as ex:
        list(ex.map(lambda so: run(cc + BASE + ["-c", str(so[0]), "-o", str(so[1])]), todo))
    return [o for _, o in jobs]


def runtime_objs():
    d = OUT / "rt-O2"
    d.mkdir(parents=True, exist_ok=True)
    return compile_all(["clang", "-O2"], [(RT / f"{f}.c", d / f"{f}.o") for f in RT_FILES])


def case_env():
    return dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"))


def generate(case):
    """Lowers the case to C (<out>/prog_hxc); returns (dir, run cwd, run args)."""
    out = OUT / case
    out.mkdir(parents=True, exist_ok=True)
    std = ["-cp", str(ROOT / "bin/hxc/std"), "--custom-target", "hxc"]
    if case == "port":
        args = ["-cp", "src", "-main", "haxe.Main", "-cp", "hxc/js", "-D", "disable-parallelism"]
        cwd = ROOT
        runargs = ["-cp", "src", "-main", "haxe.Main", "-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out / "self.hxb")]
        runcwd = ROOT
    else:
        d, main, cps, defs = CASES[case]
        cwd = HB / "runner/cases" / d
        args = ["-cp", "."] + sum([["-cp", c] for c in cps], []) + ["-main", main] + sum([["-D", x] for x in defs], [])
        runcwd = cwd / "out"
        runcwd.mkdir(exist_ok=True)
        runargs = []
    t = time.perf_counter()
    run([str(TOOL), str(out / "prog")] + args + std, cwd=cwd, env=case_env())
    return out / "prog_hxc", runcwd, runargs, time.perf_counter() - t


HXMC = Path(os.environ.get("HXMC_TOOL", ROOT / "bin/hxmc/hxmc"))


def build_hxmc(cdir, case, static=False):
    """The same program through HXB (written by the reference) and hxmc."""
    d = cdir.parent
    hxb = d / "prog.hxb.zip"
    args, cwd = case_args(case)
    run([str(ROOT / "haxe/haxe")] + args + ["-cp", str(ROOT / "bin/hxc/std"), "--custom-target", f"hxc={d}/x", "--hxb", str(hxb), "--no-output"],
        cwd=cwd, env=case_env())
    main = args[args.index("-main") + 1]
    t = time.perf_counter()
    env = dict(case_env(), HXMC_HYBRID="1", HXMC_RT=str(ROOT / "bin/hxmc/rt-dev"), HXMC_RT_INCLUDE=str(RT))
    exe = d / "bin-hxmc"
    if static:
        env = case_env()
        exe = d / "bin-hxmcs"
    run([str(HXMC), str(exe), "--hxb-lib", str(hxb), "-main", main, "--custom-target", "hxc", "-D", "disable-parallelism"], cwd=ROOT, env=env)
    return exe, time.perf_counter() - t


def case_args(case):
    if case == "port":
        return ["-cp", "src", "-main", "haxe.Main", "-cp", "hxc/js", "-D", "disable-parallelism"], ROOT
    d, main, cps, defs = CASES[case]
    return ["-cp", "."] + sum([["-cp", c] for c in cps], []) + ["-main", main] + sum([["-D", x] for x in defs], []), HB / "runner/cases" / d


def build(cdir, variant, rtobjs, case):
    if variant == "hxmc":
        return build_hxmc(cdir, case)
    if variant == "hxmcs":
        return build_hxmc(cdir, case, True)
    cc = VARIANTS[variant]
    od = cdir / f"obj-{variant}"
    od.mkdir(exist_ok=True)
    files = (cdir / "files.txt").read_text().split()
    t = time.perf_counter()
    objs = compile_all(cc, [(cdir / f, od / (f[:-2] + ".o")) for f in files])
    ct = time.perf_counter() - t
    exe = cdir.parent / f"bin-{variant}"
    run(["clang", "-o", str(exe)] + [str(o) for o in objs] + [str(o) for o in rtobjs] + ["-lm"])
    return exe, ct


def size_kb(exe):
    """The executable's size without symbols (a stripped copy)."""
    tmp = Path(str(exe) + ".stripped")
    r = subprocess.run(["strip", "-o", str(tmp), str(exe)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if r.returncode != 0:  # hxmc's executables: no section headers (no symbols) unless -debug
        return (Path(exe).stat().st_size + 1023) // 1024
    kb = (tmp.stat().st_size + 1023) // 1024
    tmp.unlink()
    return kb


def timed(cmd, cwd, n):
    best = None
    for _ in range(n):
        t = time.perf_counter()
        p = subprocess.Popen(cmd, cwd=cwd, env=case_env(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, preexec_fn=unlimited)
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
    ap.add_argument("-v", default=",".join(list(VARIANTS) + ["hxmc"]))
    ap.add_argument("--json")
    a = ap.parse_args()
    rtobjs = runtime_objs()
    results = json.load(open(a.json)) if a.json and os.path.exists(a.json) else {}
    for case in a.c.split(","):
        try:
            cdir, runcwd, runargs, gt = generate(case)
        except Exception as e:
            print(f"{case:16} generation FAILED: {str(e)[-300:]}", flush=True)
            continue
        row = dict(results.get(case, {}), gen=round(gt, 2))
        for v in a.v.split(","):
            try:
                exe, ct = build(cdir, v, rtobjs, case)
                rt = timed([str(exe)] + runargs, runcwd, a.n)
                kb = size_kb(exe)
                row[v] = {"compile": round(ct, 2), "run": round(rt, 3), "kb": kb}
                print(f"{case:16} {v:5} compile {ct:6.2f}s  run {rt:7.3f}s  size {kb:7} KB", flush=True)
            except Exception as e:
                row[v] = {"error": str(e)[-300:]}
                print(f"{case:16} {v:4} FAILED: {str(e).strip().splitlines()[-1]}", flush=True)
        results[case] = row
        if a.json:
            json.dump(results, open(a.json, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    main()
