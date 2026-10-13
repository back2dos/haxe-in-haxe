#!/usr/bin/env python3
"""Checks the x86-64 encoder against llvm-mc (hxmc/README.md, "Testing").

    python3 hxmc/tools/enctest.py [--arch x64|a64]

Runs hxmc/test/encoder/EncTest.hx on Eval (the reference compiler,
haxe/haxe), which prints `<intel syntax>|<hex bytes>` per instruction,
assembles the same text with llvm-mc and compares the encodings.
"""
import os, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HAXE = os.environ.get("HAXE", str(ROOT / "haxe/haxe"))


def main():
    arch = sys.argv[sys.argv.index("--arch") + 1] if "--arch" in sys.argv else "x64"
    env = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"))
    out = subprocess.run([HAXE, "-cp", "hxmc/src", "-cp", "hxmc/test/encoder", "--run", "EncTest" if arch == "x64" else "EncTestA64"], cwd=ROOT,
                         env=env, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(out.stdout + out.stderr)
    cases = [l.rsplit("|", 1) for l in out.stdout.splitlines() if "|" in l]
    if arch == "x64":
        src = ".intel_syntax noprefix\n" + "\n".join(t for t, _ in cases) + "\n"
        triple = "-triple=x86_64"
    else:
        src = "\n".join(t for t, _ in cases) + "\n"
        triple = "-triple=aarch64"
    mc = subprocess.run(["llvm-mc", triple, "--show-encoding"], input=src, capture_output=True, text=True)
    if mc.returncode != 0:
        sys.exit(mc.stderr[:3000])
    encs = []
    for line in mc.stdout.splitlines():
        m = re.search(r"encoding: \[([^\]]*)\]", line)
        if m:
            encs.append("".join(b[2:].zfill(2) for b in m.group(1).split(",")).lower())
    if len(encs) != len(cases):
        sys.exit(f"llvm-mc produced {len(encs)} encodings for {len(cases)} lines")
    bad = [(t, ours, ref) for (t, ours), ref in zip(cases, encs) if ours != ref]
    for t, ours, ref in bad[:40]:
        print(f"MISMATCH {t:50} ours {ours:24} llvm-mc {ref}")
    print(f"{len(cases) - len(bad)}/{len(cases)} encodings match")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
