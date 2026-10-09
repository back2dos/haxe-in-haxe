#!/usr/bin/env python3
"""Execution conformance for the port's Eval interpreter (--interp / --run).

Every case of the conformance lists is executed by the pinned reference and by
the port, and both must produce the same exit code, stdout and stderr:

- direct/module cases get `--interp` appended, so their program runs;
- hxml cases run as written when they execute (`--interp`, `--run`, `-x`) and
  are skipped otherwise;
- hxblib cases (test/conformance-hxblib-cases.txt) run against a library
  archive the reference builds first, when they use `--interp`. Each hxml case runs in a scratch copy of its directory
  so that nothing is written into the haxe/ submodule.

Timings are summed per side, which makes this also an Eval-vs-Eval benchmark
(the reference's OCaml Eval against the port's Eval on the HashLink host).

Usage: HAXE_REFERENCE=haxe/haxe python3 test/interp.py [-j N] [--cases FILE ...] [name-substring ...]
"""
import argparse, concurrent.futures, os, pathlib, re, shlex, shutil, subprocess, sys, tempfile, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "test"))
from conformance import parse_cases  # noqa: E402

STD = ROOT / "haxe/std"
GENERATED = ROOT / "test/generated/interp"
TIMEOUT = 300
EXECUTES = re.compile(r"^\s*(--interp|--run|-x)\b", re.M)


def run(cmd, cwd, env):
    start = time.monotonic()
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=TIMEOUT)
        return p.returncode, p.stdout, p.stderr, time.monotonic() - start
    except subprocess.TimeoutExpired:
        return "timeout", b"", b"", time.monotonic() - start


def prepare(case, reference, env):
    """Returns (cwd, args, scratch dir or None), or None when the case does not execute."""
    if case.get("lib"):
        # hxblib case: the reference builds the library archive, which both
        # compilers then load with --hxb-lib.
        if "--interp" not in case["args"]:
            return None
        out = GENERATED / case["name"]
        out.mkdir(parents=True, exist_ok=True)
        lib = out / "lib.hxb"
        subprocess.run([reference, "--hxb", str(lib), "--no-output"] + case["lib"], cwd=case["cwd"], env=env, capture_output=True, timeout=TIMEOUT)
        return case["cwd"], ["--hxb-lib", str(lib)] + case["args"], None
    if case.get("hxml"):
        text = (case["cwd"] / case["args"][0]).read_text(errors="replace")
        if not EXECUTES.search(text):
            return None
        scratch = pathlib.Path(tempfile.mkdtemp(prefix="hih-interp-"))
        dest = scratch / case["cwd"].name
        shutil.copytree(case["cwd"], dest)
        return dest, case["args"], scratch
    return ROOT, case["args"] + ["--interp"], None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--cases", action="append", type=pathlib.Path)
    ap.add_argument("filters", nargs="*")
    opts = ap.parse_args()
    reference = str(pathlib.Path(os.environ.get("HAXE_REFERENCE", ROOT / "haxe/haxe")).resolve())
    port = shlex.split(os.environ.get("HAXE_IN_HAXE_PORT", "hl " + str(ROOT / "bin/bench/hih.hl")))
    env = dict(os.environ, HAXE_STD_PATH=str(STD), HAXE_IN_HAXE_STD_PATH=str(STD))
    files = opts.cases or [ROOT / "test/conformance-cases.txt", ROOT / "test/conformance-macro-cases.txt"]
    cases = [c for f in files for c in parse_cases(f)]
    if opts.filters:
        cases = [c for c in cases if any(f in c["name"] for f in opts.filters)]
    GENERATED.mkdir(parents=True, exist_ok=True)

    def one(case):
        prep = prepare(case, reference, env)
        if prep is None:
            return case["name"], "SKIP", "does not execute", 0, 0
        cwd, args, scratch = prep
        try:
            ref = run([reference] + args, cwd, env)
            # Reset the scratch copy so the port sees the same files as the reference did.
            if scratch:
                shutil.rmtree(cwd)
                shutil.copytree(case["cwd"], cwd)
            got = run(port + args, cwd, env)
        finally:
            if scratch:
                shutil.rmtree(scratch, ignore_errors=True)
        out = GENERATED / case["name"]
        out.mkdir(exist_ok=True)
        for side, r in (("reference", ref), ("port", got)):
            (out / (side + ".stdout")).write_bytes(r[1])
            (out / (side + ".stderr")).write_bytes(r[2])
        diffs = [what for what, i in (("exit", 0), ("stdout", 1), ("stderr", 2)) if ref[i] != got[i]]
        if not diffs:
            status, detail = "PASS", "exit %s, %d bytes out" % (ref[0], len(ref[1]))
        else:
            status = "FAIL"
            detail = "differs: %s (reference exit %s, port exit %s)" % (", ".join(diffs), ref[0], got[0])
            if "stdout" in diffs or "stderr" in diffs:
                k = 1 if "stdout" in diffs else 2
                a, b = ref[k].decode(errors="replace").splitlines(), got[k].decode(errors="replace").splitlines()
                n = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
                detail += " | line %d: ref %r port %r" % (n + 1, (a[n] if n < len(a) else "")[:80], (b[n] if n < len(b) else "")[:80])
        return case["name"], status, detail, ref[3], got[3]

    results = []
    with concurrent.futures.ThreadPoolExecutor(opts.j) as pool:
        for r in pool.map(one, cases):
            results.append(r)
            name, status, detail, tr, tp = r
            timing = "" if status == "SKIP" else "%6.2fs %6.2fs  " % (tr, tp)
            print("%-6s %-46s %s%s" % (status, name, timing, detail), flush=True)
    counts = {}
    for r in results:
        counts[r[1]] = counts.get(r[1], 0) + 1
    ran = [r for r in results if r[1] != "SKIP"]
    tr, tp = sum(r[3] for r in ran), sum(r[4] for r in ran)
    print("Interp: %d cases: %s" % (len(results), ", ".join("%s %d" % kv for kv in sorted(counts.items()))))
    if ran:
        print("Time (compile + run, summed): reference %.1fs, port %.1fs (%.1fx)" % (tr, tp, tp / tr if tr else 0))
    return 1 if counts.get("FAIL") else 0


if __name__ == "__main__":
    sys.exit(main())
