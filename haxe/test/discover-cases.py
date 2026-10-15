#!/usr/bin/env python3
"""Discover HXB conformance cases in the pinned upstream test suite.

Every candidate configuration is compiled by a macro probe: the pinned
reference compiler built with test/macro-probe.patch applied, which reports
when a macro context is created. A configuration is a conformance case when
the probe accepts its HXB invocation without creating a macro context and it
does not select a non-Eval target. Everything else is recorded with its
reason in test/upstream-hxb-exclusions.md.

Usage:
  HAXE_MACRO_PROBE=/path/to/patched/haxe python3 test/discover-cases.py [-j N]

Writes the "Discovered" section of test/conformance-cases.txt and the
generated table of test/upstream-hxb-exclusions.md.
"""
import argparse, concurrent.futures, os, pathlib, re, subprocess, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TESTS = ROOT / "haxe/tests"
STD = ROOT / "haxe/std"
MARK = "# --- Discovered (test/discover-cases.py) ---"
TARGET_FLAGS = re.compile(r"^\s*-{1,2}(js|cpp|hl|jvm|java|cs|python|lua|php|neko|swf|as3|cppia)\b", re.M)


def candidates():
    out = []
    for base, prefix in [("misc/eval/projects", "eval"), ("misc/eval/resolution/projects", "resolution"), ("misc/eval/compiler_loops/projects", "loops")]:
        for project in sorted((TESTS / base).iterdir()):
            if not project.is_dir():
                continue
            hxmls = sorted(p for p in project.glob("compile*.hxml") if "fail" not in p.name)
            if not hxmls:
                out.append(dict(name="%s-%s" % (prefix, project.name), kind="none", project=project, reason="only compile-fail configurations"))
            for h in hxmls:
                out.append(dict(name="%s-%s-%s" % (prefix, project.name, h.stem), kind="hxml", project=project, hxml=h.name))
    for issue in sorted((TESTS / "optimization/src/issues").glob("*.hx")):
        out.append(dict(name="optimization-" + issue.stem, kind="module", project=ROOT, cp="haxe/tests/optimization/src", module="issues." + issue.stem))
    return out


def classify(probe, env, case):
    if case["kind"] == "none":
        return case, "exclude", case["reason"]
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "out.hxb")
        if case["kind"] == "hxml":
            text = (case["project"] / case["hxml"]).read_text(errors="replace")
            if re.search(r"^\s*(-L|-lib|--library)\b", text, re.M):
                return case, "exclude", "requires a haxelib library"
            if re.search(r"^\s*--next\b|^\s*--each\b", text, re.M):
                return case, "exclude", "multi-part (--next/--each) configuration"
            if TARGET_FLAGS.search(text):
                return case, "exclude", "selects a non-Eval target"
            cmd = [probe, "--hxb", out, "-D", "disable-parallelism", "--no-output", case["hxml"]]
        else:
            cmd = [probe, "-D", "disable-parallelism", "--interp", "--no-output", "-cp", case["cp"], case["module"], "--hxb", out]
        try:
            r = subprocess.run(cmd, cwd=case["project"], env=env, capture_output=True, text=True, errors="replace", timeout=300)
        except subprocess.TimeoutExpired:
            return case, "exclude", "reference timed out"
        if "HXB-MACRO-CONTEXT-CREATED" in r.stderr:
            return case, "exclude", "creates a macro context (Eval macro milestone)"
        if r.returncode != 0:
            lines = [l.strip() for l in (r.stderr + r.stdout).splitlines() if l.strip().startswith("|") and l.strip()[1:].strip() and not set(l.strip()[1:].strip()) <= set("^ ")]
            why = lines[0][1:].strip() if lines else (r.stderr.strip().splitlines() or ["no output"])[-1]
            return case, "exclude", "reference rejects the HXB invocation: " + why[:120]
        if not os.path.exists(out):
            return case, "exclude", "reference writes no HXB archive for this configuration"
        return case, "include", None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=os.cpu_count() or 2)
    opts = ap.parse_args()
    probe = os.environ.get("HAXE_MACRO_PROBE")
    if not probe or not os.access(probe, os.X_OK):
        raise SystemExit("HAXE_MACRO_PROBE must be the pinned compiler built with test/macro-probe.patch")
    env = os.environ.copy()
    env["HAXE_STD_PATH"] = str(STD)
    env["HXB_REPORT_MACRO"] = "1"
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts.j) as pool:
        for case, verdict, reason in pool.map(lambda c: classify(probe, env, c), candidates()):
            results.append((case, verdict, reason))
            print("%-8s %s %s" % (verdict, case["name"], reason or ""), flush=True)

    lines = [MARK]
    for case, verdict, _ in results:
        if verdict != "include":
            continue
        if case["kind"] == "hxml":
            lines.append("hxml %s %s %s" % (case["name"], case["project"].relative_to(ROOT), case["hxml"]))
        else:
            lines.append("module %s %s %s" % (case["name"], case["cp"], case["module"]))
    cases_file = ROOT / "test/conformance-cases.txt"
    text = cases_file.read_text()
    head = text.split(MARK)[0].rstrip("\n")
    cases_file.write_text(head + "\n\n" + "\n".join(lines) + "\n")

    table = ["| Configuration | Reason |", "| --- | --- |"]
    for case, verdict, reason in results:
        if verdict == "exclude":
            where = case.get("hxml") or case.get("module") or ""
            table.append("| `%s` %s | %s |" % (case["name"], where, reason.replace("|", "\\|")))
    exclusions = ROOT / "test/upstream-hxb-exclusions.md"
    ex_text = exclusions.read_text()
    marker = "<!-- discovered -->"
    head = ex_text.split(marker)[0].rstrip("\n")
    exclusions.write_text(head + "\n\n" + marker + "\n\n## Discovered configurations excluded from conformance\n\n" + "\n".join(table) + "\n")
    inc = sum(1 for r in results if r[1] == "include")
    print("Discovered %d candidate configurations: %d included, %d excluded" % (len(results), inc, len(results) - inc))


if __name__ == "__main__":
    main()
