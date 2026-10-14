#!/usr/bin/env python3
"""The port built by hxmc compiles its own source to HXB on the machine of its
target (the CI workflow .github/workflows/hxmc.yml); the archive is compared
with the reference compiler's, written on Linux (hxmc/tools/hxbcmp.py).

    python3 hxmc/tools/selfcheck.py --port <exe> --src <src dir> --std <std dir>
        --ref <self-ref.hxb> --ref-root <dir> --root <dir> [--summary <file>]
        [--runner <command>]

A WebAssembly port runs under --runner (node with hxmc/tools/wasi.mjs, or
wasmtime with the root reachable and HAXE_STD_PATH and PWD passed).

The source and std are copied to <root>/src and <root>/std and the port runs
in <root> (HAXE_STD_PATH=std), as the reference did in <ref-root>. With
relative class paths, positions name files relatively; only each module's
own file is an absolute path, so with the same root the archives must be
byte-identical, and with another one (Windows: D:\\...) identical once each
root is replaced by the same placeholder.
"""
import argparse, os, shlex, shutil, stat, subprocess, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hxbcmp  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--std", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--ref-root", required=True)
    ap.add_argument("--root", required=True)
    ap.add_argument("--summary")
    ap.add_argument("--runner", default="", help="the command that runs the port (WebAssembly)")
    a = ap.parse_args()
    root = Path(a.root)
    port = Path(a.port).resolve()
    port.chmod(port.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    root.mkdir(parents=True, exist_ok=True)
    for name, src in (("src", a.src), ("std", a.std)):
        if (root / name).exists():
            shutil.rmtree(root / name)
        shutil.copytree(src, root / name)
    out = root / "self.hxb"
    # (PWD: a WebAssembly port resolves relative paths against it)
    env = dict(os.environ, HAXE_STD_PATH="std", PWD=str(root.resolve()))
    t = time.perf_counter()
    r = subprocess.run(shlex.split(a.runner) + [str(port), "-cp", "src", "-main", "haxe.Main", "-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out)],
                       cwd=root, env=env, capture_output=True)
    dt = time.perf_counter() - t
    sys.stdout.write(r.stdout.decode(errors="replace"))
    sys.stdout.write(r.stderr.decode(errors="replace"))
    ok = r.returncode == 0 and out.exists()
    line = f"self-compile: exit {r.returncode}, {dt:.1f} s"
    if ok:
        za, zb = hxbcmp.zipfile.ZipFile(a.ref), hxbcmp.zipfile.ZipFile(out)
        same_root = str(root) == a.ref_root
        ra, rb = (None, None) if same_root else (a.ref_root, str(root))
        na = sorted(n for n in za.namelist() if n.endswith(".hxb"))
        nb = sorted(n for n in zb.namelist() if n.endswith(".hxb"))
        diff = [n for n in na if n in nb and hxbcmp.normalize(za.read(n), ra) != hxbcmp.normalize(zb.read(n), rb)]
        ok = na == nb and not diff
        line += f"; {len(na)} modules, {'names equal' if na == nb else 'NAMES DIFFER'}, {len(diff)} differ"
        line += " (byte-identical)" if same_root and ok else " (roots normalized)" if not same_root else ""
        for n in diff[:10]:
            line += "\n  differs: " + n
        if diff:
            line += "\n  first: " + hxbcmp.explain(hxbcmp.normalize(za.read(diff[0]), ra), hxbcmp.normalize(zb.read(diff[0]), rb))
    print(line)
    if a.summary:
        with open(a.summary, "a") as f:
            f.write(f"### port self-compile{' (' + a.runner.split()[0] + ')' if a.runner else ''}: {'ok' if ok else 'FAILED'}\n\n```\n{line}\n```\n\n")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
