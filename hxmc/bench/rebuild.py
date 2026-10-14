#!/usr/bin/env python3
"""Rebuild times of hxmc (hxmc/README.md, "Rebuilds").

    python3 hxmc/bench/rebuild.py [-c small,port] [--tool bin/hxmc/hxmc] [--server]

For each program: a cold build (empty object cache), a rebuild without
change, and a rebuild after a one-function edit of one module (a second HXB
archive, written by the reference compiler from a copy of the sources with
that edit). Only hxmc's own time is measured (from the archive to the
executable); writing the archive is your Haxe's job. Prints the tool's
breakdown (modules compiled and cached, codegen, link).

--server: the same three builds from source through the resident tool
(`hxmc --server`, the port's compilation server: `haxe --connect`), the
edit made in a copy of the sources; the time is the client's.
"""
import argparse, os, re, shutil, subprocess, sys, time, resource
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "bin/hxmc-rebuild"
ENV = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"), HXMC_STATS="1")

# program: (source dirs to copy, class paths relative to the copy, main, file to edit, anchor, inserted text)
PROGRAMS = {
    "small": (["hxmc/test/cases"], ["hxmc/test/cases"], "Regress", "hxmc/test/cases/Regress.hx", "static function main() {", "\n\t\ttrace(\"edited\");"),
    "port": (["src"], ["src"], "haxe.Main", "src/typing/Operators.hx", "function makeBinop(", None),
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
    args = sum([["-cp", src / c] for c in cps], []) + ["-cp", ROOT / "bin/hxmc/std", "-main", main]
    sh([ROOT / "haxe/haxe"] + args + ["--custom-target", f"hxmc={d}/x", "--hxb", hxb, "-D", "disable-parallelism", "--no-output"])
    shutil.rmtree(src)
    return hxb


def build(tool, hxb, main, out):
    t = time.perf_counter()
    log = sh([tool, out, "--hxb-lib", hxb, "-main", main, "--custom-target", "hxmc", "-D", "disable-parallelism"])
    t = time.perf_counter() - t
    m = re.search(r"modules (\d+): (\d+) cached, (\d+) compiled", log)
    c = re.search(r"codegen (\d+) ms", log)
    l = re.search(r"link (\d+) ms", log)
    return t, f"{m.group(3)}/{m.group(1)} modules compiled, codegen {c.group(1)} ms, link {l.group(1)} ms" if m else log[-300:]


def server(tool, name, port=6127):
    dirs, cps, main, f, anchor, text = PROGRAMS[name]
    src = OUT / name / "srv-src"
    shutil.rmtree(src, ignore_errors=True)
    for s in dirs:
        shutil.copytree(ROOT / s, src / s)
    out = OUT / name / "srv-exe"
    shutil.rmtree(str(out) + ".hxmc", ignore_errors=True)
    # (the GC settings given: the tool would run itself again with them, as a child)
    env = dict(ENV, RT_OLD_MB=ENV.get("RT_OLD_MB", "4096"), RT_MINOR_KB=ENV.get("RT_MINOR_KB", "32768"))
    srv = subprocess.Popen([tool, "--server", "--wait", str(port)], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, preexec_fn=unlimited)
    time.sleep(1)
    args = sum([["-cp", src / c] for c in cps], []) + ["-cp", ROOT / "bin/hxmc/std", "-main", main, "--custom-target", "hxmc",
        "-D", "disable-parallelism", "-D", "disable-hxb-cache", "-D", f"hxmc.out={out}", "--no-output"]
    p = src / f
    orig = p.read_text()
    i = orig.index(anchor)
    if text is None:
        j = orig.index("{", i) + 1
        edited = orig[:j] + "\n\t\tif (Sys.getEnv(\"HXMC_NEVER_SET\") == \"x\") trace(\"edited\");" + orig[j:]
    else:
        j = i + len(anchor)
        edited = orig[:j] + text + orig[j:]
    try:
        for label, content in [("cold", None), ("no change", None), ("one module edited", edited), ("edited back", orig)]:
            if content is not None:
                p.write_text(content)
            t = time.perf_counter()
            sh([ROOT / "haxe/haxe", "--connect", str(port)] + args)
            t = time.perf_counter() - t
            print(f"{name:6} server {label:18} {t:6.2f} s", flush=True)
    finally:
        srv.kill()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-c", default="small,port")
    ap.add_argument("--tool", default=str(ROOT / "bin/hxmc/hxmc"))
    ap.add_argument("--server", action="store_true")
    a = ap.parse_args()
    if a.server:
        for name in a.c.split(","):
            server(a.tool, name)
        return
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
