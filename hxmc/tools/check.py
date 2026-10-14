#!/usr/bin/env python3
"""Runs the executables staged by `run.py --stage <dir>` on the machine of their
target (the CI workflow .github/workflows/hxmc.yml: macOS, Windows arm64) and
compares each output with the expected one (hxc's, written on Linux).

    python3 hxmc/tools/check.py <dir> [--summary <file>]

Exits non-zero when a case differs; prints one line per case and, with
--summary (e.g. $GITHUB_STEP_SUMMARY), the failures with the start of their
diff in Markdown.
"""
import argparse, difflib, os, stat, subprocess, sys, time
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--summary")
    ap.add_argument("--timeout", type=int, default=300)
    a = ap.parse_args()
    env = dict(os.environ, RT_MINOR_KB=os.environ.get("RT_MINOR_KB", "64"))
    cases = sorted(d for d in Path(a.dir).iterdir() if (d / "expected.txt").exists())
    bad = []
    t0 = time.perf_counter()
    for d in cases:
        exe = d / "m.exe" if (d / "m.exe").exists() else d / "m"
        exe.chmod(exe.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        t = time.perf_counter()
        try:
            r = subprocess.run([str(exe.resolve())], cwd=d, env=env, capture_output=True, timeout=a.timeout)
            got = f"exit {r.returncode}\n".encode() + r.stdout
            err = r.stderr
        except subprocess.TimeoutExpired:
            got, err = b"timeout\n", b""
        exp = (d / "expected.txt").read_bytes()
        ok = got == exp
        print(f"{d.name:24} {'ok' if ok else 'DIFFERS':8} {time.perf_counter() - t:.1f}s", flush=True)
        if not ok:
            (d / "got.txt").write_bytes(got + err)
            diff = list(difflib.unified_diff(exp.decode(errors="replace").splitlines(), got.decode(errors="replace").splitlines(), "expected", "got", lineterm="", n=1))[:30]
            bad.append((d.name, diff, err.decode(errors="replace")[-1500:]))
            print("    " + "\n    ".join(diff))
            if err:
                print("    stderr: " + err.decode(errors="replace")[-1500:].replace("\n", "\n    "))
    print(f"{len(cases) - len(bad)}/{len(cases)} ok, {time.perf_counter() - t0:.1f}s")
    if a.summary:
        with open(a.summary, "a") as f:
            f.write(f"### {Path(a.dir).name}: {len(cases) - len(bad)}/{len(cases)} ok\n\n")
            for name, diff, err in bad[:20]:
                f.write(f"<details><summary>{name}</summary>\n\n```\n" + "\n".join(diff) + "\n" + err + "\n```\n</details>\n\n")
    sys.exit(1 if bad or not cases else 0)


if __name__ == "__main__":
    main()
