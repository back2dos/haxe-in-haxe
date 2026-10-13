#!/usr/bin/env python3
"""Rebuild times of hxmc (hxmc/README.md, "Rebuilds").

    python3 hxmc/bench/rebuild.py [-c small,port] [--tool bin/hxmc/hxmc]

For each program: a cold build (empty object cache), a rebuild without
change, and a rebuild after a one-function edit of one module (a second HXB
archive, written by the reference compiler from a copy of the sources with
that edit). Only hxmc's own time is measured (from the archive to the
executable); writing the archive is your Haxe's job. Prints the tool's
breakdown (modules compiled and cached, codegen, link).
"""
import argparse, os, re, shutil, subprocess, sys, time, resource
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "bin/hxmc-rebuild"
ENV = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"), HXMC_STATS="1")

# program: (source dirs to copy, class paths relative to the copy, main, file to edit, anchor, inserted text)
PROGRAMS = {
    "small": (["hxc/test/regress"], ["hxc/test/regress"], "Regress", "hxc/test/regress/Regress.hx", "static function main() {", "\n\t\ttrace(\"edited\");"),
    "port": (["src", "hxc/js"], ["src", "hxc/js"], "haxe.Main", "src/typing/Operators.hx", "function makeBinop(", None),
}


def unlimited():
    resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))


def sh(cmd, cwd=ROOT):
    r = subprocess.run([str(c) for c in cmd], cwd=cwd, env=ENV, capture_output=True, text=True, preexec_fn=unlimited)
    if r.returncode != 0:
        sys.exit(" ".join(map(str, cmd)) + "\n" + r.stdout[-2000:] + r.stderr[-2000:])
    return r.stdout


def archive(name, variant, dirs, cps, main, edit):
    d = OUT / name / variant
    hxb = d / "prog.hxb.zip"
    if hxb.exists():
        return hxb
    src = d / "src"
    for s in dirs:
        shutil.copytree(ROOT / s, src / s, dirs_exist_ok=True)
    if edit:
        f, anchor, text = edit
        p = src / f
        t = p.read_text()
        i = t.index(anchor)
        if text is None:
            # a statement at the start of the function body: the body's first "{"
            j = t.index("{", i) + 1
            t = t[:j] + "\n\t\tif (Sys.getEnv(\"HXMC_NEVER_SET\") == \"x\") trace(\"edited\");" + t[j:]
        else:
            j = i + len(anchor)
            t = t[:j] + text + t[j:]
        p.write_text(t)
    args = sum([["-cp", src / c] for c in cps], []) + ["-cp", ROOT / "bin/hxc/std", "-main", main]
    sh([ROOT / "haxe/haxe"] + args + ["--custom-target", f"hxc={d}/x", "--hxb", hxb, "-D", "disable-parallelism", "--no-output"])
    shutil.rmtree(src)
    return hxb


def build(tool, hxb, main, out):
    t = time.perf_counter()
    log = sh([tool, out, "--hxb-lib", hxb, "-main", main, "--custom-target", "hxc", "-D", "disable-parallelism"])
    t = time.perf_counter() - t
    m = re.search(r"modules (\d+): (\d+) cached, (\d+) compiled", log)
    c = re.search(r"codegen (\d+) ms", log)
    l = re.search(r"link (\d+) ms", log)
    return t, f"{m.group(3)}/{m.group(1)} modules compiled, codegen {c.group(1)} ms, link {l.group(1)} ms" if m else log[-300:]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-c", default="small,port")
    ap.add_argument("--tool", default=str(ROOT / "bin/hxmc/hxmc"))
    a = ap.parse_args()
    for name in a.c.split(","):
        dirs, cps, main, f, anchor, text = PROGRAMS[name]
        hxa = archive(name, "a", dirs, cps, main, None)
        hxb = archive(name, "b", dirs, cps, main, (f, anchor, text))
        out = OUT / name / "exe"
        shutil.rmtree(str(out) + ".hxmc", ignore_errors=True)
        for label, hx in [("cold", hxa), ("no change", hxa), ("one module edited", hxb)]:
            t, info = build(a.tool, hx, main, out)
            print(f"{name:6} {label:18} {t:6.2f} s   {info}", flush=True)


if __name__ == "__main__":
    main()
