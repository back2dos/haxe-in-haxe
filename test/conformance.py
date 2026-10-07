#!/usr/bin/env python3
"""HXB conformance harness for the translated compiler (haxe.Main).

For every case in test/conformance-cases.txt:

1. The pinned reference compiles the case to HXB.
2. The port, compiled to an Eval HXB archive by the reference and executed
   through --hxb-lib, compiles the same invocation.
3. Both archives must have the same member set and byte-identical
   uncompressed .hxb payloads (ZIP container bytes are never compared).
4. The reference must consume the port's archive without the case's source
   class path.
5. Unless --no-source-run is given, the port executed from source must produce
   the same member set and payloads as the port executed from HXB.

A case the reference rejects is an expected-failure case: the port must reject
it as well. Both invocations use -D disable-parallelism: the reference
allocates variable IDs from a global counter shared by parallel filter
workers, so its own output is otherwise not reproducible run to run.

Usage: HAXE_REFERENCE=haxe/haxe python3 test/conformance.py [-j N] [--no-source-run] [name-substring ...]
"""
import argparse, concurrent.futures, os, pathlib, shlex, shutil, subprocess, sys, tempfile, time, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STD = ROOT / "haxe/std"
GENERATED = ROOT / "test/generated/conformance"
STACK = ["-D", "eval-call-stack-depth=10000"]
COMMON = ["-D", "disable-parallelism", "--interp", "--no-output"]
TIMEOUT = 900


def parse_cases():
    cases = []
    for line in (ROOT / "test/conformance-cases.txt").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = shlex.split(line)
        kind, name = parts[0], parts[1]
        if kind == "direct":
            cases.append(dict(kind=kind, name=name, cwd=ROOT, args=["-cp", parts[2], "--main", parts[3]], consume=["--main", parts[3]]))
        elif kind == "module":
            cases.append(dict(kind=kind, name=name, cwd=ROOT, args=["-cp", parts[2], parts[3]], consume=[parts[3]]))
        elif kind == "hxml":
            # HXML configurations select their own target; only defines and the output are added.
            cases.append(dict(kind=kind, name=name, cwd=ROOT / parts[2], args=[parts[3]], consume=["--main", parts[4]], hxml=True))
        else:
            raise SystemExit("Unknown case kind: " + line)
    return cases


def run(cmd, cwd, log, env):
    start = time.monotonic()
    try:
        with open(log, "wb") as stream:
            code = subprocess.run(cmd, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        code = "timeout"
    return code, time.monotonic() - start


def first_error(log):
    try:
        text = pathlib.Path(log).read_text(errors="replace")
    except OSError:
        return ""
    lines = [l.strip() for l in text.splitlines() if l.strip() and not l.startswith("Called from")]
    for l in lines:
        if l.startswith("|"):
            content = l[1:].strip()
            if content and not set(content) <= set("^ ") and content != "[...]":
                return content[:200]
    return (lines[-1] if lines else "")[:200]


def compare(expected, actual):
    """Returns None when the archives conform, otherwise a description."""
    try:
        a = zipfile.ZipFile(expected)
        b = zipfile.ZipFile(actual)
    except (OSError, zipfile.BadZipFile) as e:
        return "unreadable archive: %s" % e
    na, nb = set(a.namelist()), set(b.namelist())
    if na != nb:
        only_a = sorted(na - nb)
        only_b = sorted(nb - na)
        return "member set differs (reference-only %d %s, port-only %d %s)" % (len(only_a), only_a[:3], len(only_b), only_b[:3])
    diffs = []
    for name in sorted(na):
        if not name.endswith(".hxb"):
            continue
        x, y = a.read(name), b.read(name)
        if x != y:
            i = next((i for i in range(min(len(x), len(y))) if x[i] != y[i]), min(len(x), len(y)))
            diffs.append("%s@%d" % (name, i))
    if diffs:
        return "%d/%d payloads differ: %s" % (len(diffs), len(na), " ".join(diffs[:4]))
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--no-source-run", action="store_true")
    ap.add_argument("filters", nargs="*")
    opts = ap.parse_args()
    reference = os.environ.get("HAXE_REFERENCE")
    if not reference or not os.access(reference, os.X_OK):
        raise SystemExit("HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule.")
    reference = os.path.abspath(reference)
    env = os.environ.copy()
    env["HAXE_STD_PATH"] = str(STD)
    env["HAXE_IN_HAXE_STD_PATH"] = str(STD)

    cases = [c for c in parse_cases() if not opts.filters or any(f in c["name"] for f in opts.filters)]
    GENERATED.mkdir(parents=True, exist_ok=True)
    compiler = GENERATED / "haxe-in-haxe.eval.hxb"
    code, _ = run([reference, "-cp", str(ROOT / "src"), "-main", "haxe.Main", "--interp", "--no-output", "--hxb", str(compiler)], ROOT, GENERATED / "build.log", env)
    if code != 0:
        raise SystemExit("Building the port as Eval HXB failed; see " + str(GENERATED / "build.log"))
    if "eval/haxe/Main.hxb" not in zipfile.ZipFile(compiler).namelist():
        raise SystemExit("Compiler archive does not contain eval/haxe/Main.hxb")

    def run_case(case):
        out = GENERATED / case["name"]
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        cwd = case["cwd"]
        ref_hxb, port_hxb, src_hxb = out / "reference.hxb", out / "port.hxb", out / "source.hxb"
        def invocation(hxb):
            # An HXML configuration may end in --run, which takes all following
            # arguments, so the output and defines precede it; --no-output keeps
            # the reference from executing the program.
            if case.get("hxml"):
                return ["--hxb", str(hxb), "-D", "disable-parallelism", "--no-output"] + case["args"]
            return COMMON + case["args"] + ["--hxb", str(hxb)]
        rc, rt = run([reference] + invocation(ref_hxb), cwd, out / "reference.log", env)
        pc, pt = run([reference] + STACK + ["--hxb-lib", str(compiler), "--run", "haxe.Main"] + invocation(port_hxb), cwd, out / "port.log", env)
        result = dict(name=case["name"], seconds=round(rt + pt, 1))
        if rc != 0:
            if pc == 0:
                result.update(status="FAIL", detail="reference rejects (%s) but port accepts" % first_error(out / "reference.log"))
            else:
                result.update(status="EXPECTED-FAILURE", detail="both reject: " + first_error(out / "reference.log"))
            return result
        if pc != 0:
            result.update(status="FAIL", detail="port failed (%s): %s" % (pc, first_error(out / "port.log")))
            return result
        diff = compare(ref_hxb, port_hxb)
        if diff:
            result.update(status="FAIL", detail=diff)
            return result
        names = zipfile.ZipFile(port_hxb).namelist()
        target = ["--interp", "--no-output"] if any(n.startswith("eval/") for n in names) else ["--no-output"]
        cc, _ = run([reference, "--hxb-lib", str(port_hxb)] + case["consume"] + target, ROOT, out / "consume.log", env)
        if cc != 0:
            result.update(status="FAIL", detail="reference cannot consume port archive: " + first_error(out / "consume.log"))
            return result
        if not opts.no_source_run:
            sc, st = run([reference] + STACK + ["-cp", str(ROOT / "src"), "--run", "haxe.Main"] + invocation(src_hxb), cwd, out / "source.log", env)
            result["seconds"] = round(result["seconds"] + st, 1)
            if sc != 0:
                result.update(status="FAIL", detail="source-executed port failed: " + first_error(out / "source.log"))
                return result
            diff = compare(port_hxb, src_hxb)
            if diff:
                result.update(status="FAIL", detail="source vs Eval-HXB execution: " + diff)
                return result
        members = len(zipfile.ZipFile(ref_hxb).namelist())
        result.update(status="PASS", detail="%d members identical" % members)
        return result

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts.j) as pool:
        for r in pool.map(run_case, cases):
            results.append(r)
            print("%-17s %-40s %6.1fs  %s" % (r["status"], r["name"], r["seconds"], r["detail"]), flush=True)
    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    summary = ", ".join("%s %d" % kv for kv in sorted(counts.items()))
    print("Conformance: %d cases: %s" % (len(results), summary))
    (GENERATED / "summary.tsv").write_text("".join("%s\t%s\t%s\n" % (r["status"], r["name"], r["detail"]) for r in results))
    sys.exit(1 if counts.get("FAIL") else 0)


if __name__ == "__main__":
    main()
