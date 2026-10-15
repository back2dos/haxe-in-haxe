#!/usr/bin/env python3
"""Tiered checks of hxmc (hxmc/README.md, "Iteration loop"): one line per lane
with its result and time, a summary at the end, exit 1 if any lane failed.

    python3 hxmc/tools/tiers.py quick|check|full [--port] [case ...]

  quick  the x64 corpus (64 KB nursery), again with RT_VERIFY=1, and the
         wasm corpus under node (64 KB): after every edit (well under a
         minute once the tool is built)
  check  quick + linux-arm64 (qemu) and windows-x86_64 (wine) corpus, x64
         with a 16 KB nursery, ThreadNatives x30, the tool as a WebAssembly
         module building three cases for x64, arm64 and wasm32-wasi
         byte-identical to the native tool (crosshost.py); --port adds the native
         port's self-compile (when code generation or the runtime
         changed): before local commits
  full   every lane: x64, arm64 and wine at 64, 16 and 256 KB, each with
         RT_VERIFY=1 too; wasm under node and wasmtime at 16, 64 and 256 KB,
         under node with RT_VERIFY=1 at 64 and 256 KB; ThreadNatives x300
         (16 KB) and x100 (64 KB); the port's self-compile natively (64 KB,
         256 KB, 256 KB with RT_VERIFY=1) and as a module (node, node with
         256 KB, wasmtime); the tool as a module building every case for
         every target and the tool itself byte-identical to the native tool;
         the fixpoint: before pushing

Cases named restrict the corpus lanes to them (the area being changed); the
port, ThreadNatives and fixpoint lanes ignore them. Each corpus lane is
run.py with -j (all cores); lanes run one after another (they share the
cases' output directories). The tool is not rebuilt here: the Makefile's
targets of the same names rebuild it first.
"""
import os, subprocess, sys, time, zipfile, hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"), WINEDEBUG="-all")
NODE = ["node", "--experimental-wasm-exnref", "--no-turbo-fast-api-calls", "--no-warnings", "--stack-size=8000", str(ROOT / "hxmc/tools/wasi.mjs")]
results = []


def lane(name, fn):
    t = time.perf_counter()
    try:
        ok, detail = fn()
    except Exception as e:
        ok, detail = False, f"{type(e).__name__}: {e}"
    dt = time.perf_counter() - t
    results.append((name, ok, dt))
    print(f"{name:28} {'ok  ' if ok else 'FAIL'} {dt:6.1f}s  {detail}", flush=True)


def corpus(target=None, env=None, cases=()):
    def fn():
        cmd = [sys.executable, str(ROOT / "hxmc/tools/run.py"), "-j", str(os.cpu_count() or 4)]
        if target:
            cmd += ["--target", target]
        r = subprocess.run(cmd + list(cases), cwd=ROOT, env=dict(ENV, **(env or {})), capture_output=True, text=True)
        lines = r.stdout.strip().splitlines()
        bad = [l.split()[0] + " " + l.split()[1] for l in lines[:-1] if len(l.split()) > 1 and l.split()[1] not in ("ok", "excluded")]
        return r.returncode == 0, (lines[-1] if lines else r.stderr[-300:]) + ("" if not bad else "  " + ", ".join(bad[:8]))
    return fn


def threads(n, kb, env=None):
    def fn():
        subprocess.run([sys.executable, str(ROOT / "hxmc/tools/run.py"), "ThreadNatives"], cwd=ROOT, env=ENV, capture_output=True)
        d = ROOT / "bin/hxmc-t/ThreadNatives"
        exp = (ROOT / "hxmc/test/expected/ThreadNatives.txt").read_bytes()
        bad = 0
        for _ in range(n):
            try:
                r = subprocess.run([str(d / "m")], cwd=d, env=dict(ENV, RT_MINOR_KB=str(kb), **(env or {})), capture_output=True, timeout=60)
                got = f"exit {r.returncode}\n".encode() + r.stdout
            except subprocess.TimeoutExpired:
                got = b"timeout"
            bad += got != exp
        return bad == 0, f"{n - bad}/{n} runs"
    return fn


def digest(path):
    z = zipfile.ZipFile(path)
    h = hashlib.sha256()
    for n in sorted(z.namelist()):
        h.update(n.encode())
        h.update(z.read(n))
    return h.hexdigest()


def port_native():
    # portcheck.sh: builds the port, self-compiles it, compares with the reference (also 256 KB)
    r = subprocess.run(["sh", str(ROOT / "hxmc/tools/portcheck.sh")], cwd=ROOT, env=dict(ENV, SMALL="1"), capture_output=True, text=True)
    out = r.stdout
    ok = r.returncode == 0 and " 0 differ" in out and "names equal" in out and "small nursery: same" in out
    sc = [l for l in out.splitlines() if l.startswith("self-compile")]
    return ok, (sc[0] if sc else out[-300:])


def self_compile(cmd, env=None):
    def fn():
        out = ROOT / "bin/hxmc-t/self-tier.hxb"
        if out.exists():
            out.unlink()
        r = subprocess.run(cmd + ["-cp", "src", "-main", "haxe.Main", "-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out)],
                           cwd=ROOT, env=dict(ENV, **(env or {})), capture_output=True, text=True)
        if r.returncode != 0:
            return False, (r.stdout + r.stderr)[-300:]
        same = digest(out) == digest(ROOT / "bin/hxmc-t/self-ref.hxb")
        return same, "identical to the reference" if same else "DIFFERS from the reference"
    return fn


def wasm_port_build():
    d = ROOT / "bin/hxmc-t/wport"
    d.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([str(ROOT / "haxe/haxe"), "-cp", "src", "-cp", "bin/hxmc/std", "-main", "haxe.Main", "--custom-target", f"hxmc={d}/x", "--hxb", str(d / "prog.hxb.zip"),
                        "-D", "disable-parallelism", "-D", "hxmc.target=wasm32-wasi", "--no-output"], cwd=ROOT, env=ENV, capture_output=True, text=True)
    if r.returncode != 0:
        return False, r.stderr[-300:]
    r = subprocess.run([str(ROOT / "bin/hxmc/hxmc"), str(d / "haxe.wasm"), "--hxb-lib", str(d / "prog.hxb.zip"), "-main", "haxe.Main", "--custom-target", "hxmc",
                        "-D", "disable-parallelism", "-D", "hxmc.target=wasm32-wasi"], cwd=ROOT, env=ENV, capture_output=True, text=True)
    return r.returncode == 0, f"{(d / 'haxe.wasm').stat().st_size} bytes" if r.returncode == 0 else r.stderr[-300:]


def crosshost(args):
    def fn():
        r = subprocess.run([sys.executable, str(ROOT / "hxmc/tools/crosshost.py")] + args, cwd=ROOT, env=ENV, capture_output=True, text=True)
        lines = r.stdout.strip().splitlines()
        bad = [" ".join(l.split()[:2]) for l in lines[:-1] if len(l.split()) > 2 and l.split()[2] == "FAIL"]
        return r.returncode == 0, (lines[-1] if lines else r.stderr[-300:]) + ("" if not bad else "  " + ", ".join(bad[:8]))
    return fn


def fixpoint():
    r = subprocess.run(["make", "--no-print-directory", "fixpoint"], cwd=ROOT, env=ENV, capture_output=True, text=True)
    said = [l for l in r.stdout.splitlines() if l.startswith("fixpoint:")]
    return r.returncode == 0, said[-1] if said else (r.stdout + r.stderr)[-300:]


def main():
    args = sys.argv[1:]
    if not args or args[0] not in ("quick", "check", "full"):
        sys.exit(__doc__)
    tier, port = args[0], "--port" in args
    cases = [a for a in args[1:] if a != "--port"]
    t0 = time.perf_counter()
    if tier in ("quick", "check"):
        lane("x64", corpus(cases=cases))
        lane("x64 RT_VERIFY", corpus(env={"RT_VERIFY": "1"}, cases=cases))
        lane("wasm node", corpus("wasm32-wasi", cases=cases))
    if tier == "check":
        lane("x64 16K", corpus(env={"RT_MINOR_KB": "16"}, cases=cases))
        lane("arm64 (qemu)", corpus("linux-arm64", cases=cases))
        lane("windows (wine)", corpus("windows-x86_64", cases=cases))
        lane("ThreadNatives x30", threads(30, 16))
        lane("cross-host", crosshost(["--targets", "linux-x86_64,linux-arm64,wasm32-wasi"] + (cases or ["Unsafe", "SwitchIndex", "Regress"])))
        if port:
            lane("port self-compile", port_native)
    if tier == "full":
        for t in ["linux-x86_64", "linux-arm64", "windows-x86_64"]:
            for kb in ["64", "16", "256"]:
                lane(f"{t} {kb}K", corpus(t, {"RT_MINOR_KB": kb}, cases))
                lane(f"{t} {kb}K RT_VERIFY", corpus(t, {"RT_MINOR_KB": kb, "RT_VERIFY": "1"}, cases))
        for kb in ["16", "64", "256"]:
            lane(f"wasm node {kb}K", corpus("wasm32-wasi", {"RT_MINOR_KB": kb}, cases))
            lane(f"wasm wasmtime {kb}K", corpus("wasm32-wasi", {"RT_MINOR_KB": kb, "HXMC_WASM_RUNNER": "wasmtime"}, cases))
        for kb in ["64", "256"]:
            lane(f"wasm node {kb}K RT_VERIFY", corpus("wasm32-wasi", {"RT_MINOR_KB": kb, "RT_VERIFY": "1"}, cases))
        lane("ThreadNatives x300 16K", threads(300, 16))
        lane("ThreadNatives x100 64K", threads(100, 64))
        lane("port self-compile", port_native)
        lane("port 256K RT_VERIFY", self_compile([str(ROOT / "bin/hxmc-t/port/s")], {"RT_MINOR_KB": "256", "RT_VERIFY": "1"}))
        lane("wasm port build", wasm_port_build)
        wp = str(ROOT / "bin/hxmc-t/wport/haxe.wasm")
        lane("wasm port node", self_compile(NODE + [wp]))
        lane("wasm port node 256K", self_compile(NODE + [wp], {"RT_MINOR_KB": "256"}))
        lane("wasm port wasmtime", self_compile(["wasmtime", "run", "-W", "exceptions=y", "-W", "max-wasm-stack=67108864", "--dir", "/",
                                                 "--env", "HAXE_STD_PATH", "--env", f"PWD={ROOT}", wp]))
        lane("cross-host", crosshost(["--tool"] + list(cases)))
        lane("fixpoint", fixpoint)
    bad = [n for n, ok, _ in results if not ok]
    print(f"{tier}: {len(results) - len(bad)}/{len(results)} lanes ok, {time.perf_counter() - t0:.0f}s" + ("" if not bad else "; FAILED: " + ", ".join(bad)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
