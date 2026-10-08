#!/usr/bin/env python3
"""Benchmark the pinned reference compiler against the translated compiler
(haxe.Main) built for several targets (see bench/build.sh).

Each run compiles a workload to HXB with -D disable-parallelism. Every
runner's archive is checked against the reference output (same member set,
identical uncompressed .hxb payloads) before its timing counts.

Usage: HAXE_REFERENCE=haxe/haxe python3 bench/run.py [-n RUNS] [runner ...]
"""
import argparse, os, pathlib, shutil, statistics, subprocess, sys, tempfile, time, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / "bin/bench"
STD = ROOT / "haxe/std"

WORKLOADS = {
    # name: (cwd, arguments)
    "hello": (ROOT / "bench/workloads", ["-cp", ".", "--main", "Hello"]),
    "trycatch": (ROOT, ["-cp", "test", "--main", "unit.moduleload.TryCatch"]),
    # Many std modules as bare roots. (The port's own source is not a workload:
    # compiling it executes std macros, which are outside the first milestone.)
    "stdlib": (ROOT, """haxe.Json haxe.Serializer haxe.Unserializer haxe.crypto.Sha256 haxe.crypto.Md5
        haxe.crypto.Base64 haxe.io.BytesBuffer haxe.zip.Reader haxe.zip.Writer haxe.ds.BalancedTree
        haxe.ds.GenericStack haxe.ds.ListSort haxe.xml.Parser haxe.xml.Printer haxe.Template
        haxe.format.JsonParser haxe.io.Path haxe.Int64Helper haxe.CallStack DateTools EReg StringTools
        Lambda haxe.ds.Vector haxe.EnumFlags haxe.http.HttpBase haxe.crypto.Hmac haxe.crypto.Crc32
        haxe.zip.Huffman haxe.zip.InflateImpl haxe.io.Float32Array haxe.ds.HashMap""".split()),
}


def runners(reference):
    return {
        "reference": [reference],
        "hl": ["hl", str(BIN / "hih.hl")],
        "cpp": [str(BIN / "cpp/Main")],
        "hlc": [str(BIN / "hih-hlc")],
        "jvm": ["java", "-Xss512m", "-XX:+UnlockDiagnosticVMOptions", "-XX:-BytecodeVerificationRemote", "-XX:-BytecodeVerificationLocal", "-jar", str(BIN / "hih.jar")],
        "js": ["node", "--stack-size=65500", str(BIN / "hih.js")],
        "go": [str(BIN / "hih-go")],
    }


def payloads(path):
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n) for n in z.namelist() if n.endswith(".hxb")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-w", "--workload", action="append")
    ap.add_argument("runners", nargs="*")
    opts = ap.parse_args()
    reference = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
    reference = str(pathlib.Path(reference).resolve())
    table = runners(reference)
    names = opts.runners or list(table)
    # The reference output is what every other runner is checked against.
    names = ["reference"] + [n for n in names if n != "reference"]
    env = dict(os.environ, HAXE_STD_PATH=str(STD), HAXE_IN_HAXE_STD_PATH=str(STD))
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="hih-bench-"))
    results = {}
    try:
        for wname in opts.workload or list(WORKLOADS):
            cwd, args = WORKLOADS[wname]
            expected = None
            for rname in names:
                times = []
                status = "ok"
                for i in range(opts.n):
                    out = tmp / f"{wname}-{rname}-{i}.hxb"
                    cmd = table[rname] + args + ["-D", "disable-parallelism", "--interp", "--no-output", "--hxb", str(out)]
                    start = time.perf_counter()
                    with open(tmp / "log.txt", "w") as log:
                        code = subprocess.run(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
                    elapsed = time.perf_counter() - start
                    if code != 0 or not out.exists():
                        status = f"exit {code}: " + (tmp / "log.txt").read_text()[-300:].strip().replace("\n", " | ")
                        break
                    got = payloads(out)
                    if expected is None:
                        expected = got
                    elif got != expected:
                        bad = sum(1 for k in set(got) | set(expected) if got.get(k) != expected.get(k))
                        status = f"output differs from reference ({bad} members)"
                        break
                    times.append(elapsed)
                results[(wname, rname)] = (times, status)
                med = f"{statistics.median(times):8.2f}s" if times and status == "ok" else "       -"
                print(f"{wname:8} {rname:10} {med}  {status if status != 'ok' else 'runs: ' + ' '.join(f'{t:.2f}' for t in times)}", flush=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
