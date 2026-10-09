#!/usr/bin/env python3
"""Haxelib (-L/--library) conformance for the translated compiler.

Creates a scratch project with a local haxelib repository (`haxelib newrepo`)
and two development libraries (`haxelib dev`, no network): `hihlib` (class
path, define, extraParams.hxml) and `hihdep`, which depends on `hihlib`. The
pinned reference and the port then compile the same invocations; exit codes,
stderr and the HXB archives (member set, byte-identical payloads) must agree.

Cases: one library, a library with a dependency, several -L in a row (one
haxelib call), --haxelib-global (rejected by both without a global repository
entry), a missing library, and -L inside an hxml file. With --server, each
invocation also runs through `--connect` on a reference and a port server.

Usage: HAXE_REFERENCE=haxe/haxe python3 test/haxelib.py [--server]
"""
import argparse, os, pathlib, shutil, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
STD = ROOT / "haxe/std"
GENERATED = ROOT / "test/generated/haxelib"
sys.path.insert(0, str(ROOT / "test"))
import conformance  # noqa: E402
import server  # noqa: E402

FILES = {
    "libs/hihlib/haxelib.json": '{"name":"hihlib","version":"1.2.3","classPath":"src","license":"MIT","contributors":["x"],"releasenote":"","dependencies":{}}',
    "libs/hihlib/extraParams.hxml": "-D hihlib_extra=7\n",
    "libs/hihlib/src/hihlib/Tool.hx": "package hihlib;\nclass Tool {\n\tpublic static function twice(x:Int) return x * 2;\n\t#if hihlib_extra public static var extra = 1; #end\n}\n",
    "libs/hihdep/haxelib.json": '{"name":"hihdep","version":"0.1.0","classPath":"src","license":"MIT","contributors":["x"],"releasenote":"","dependencies":{"hihlib":""}}',
    "libs/hihdep/src/hihdep/Dep.hx": "package hihdep;\nclass Dep {\n\tpublic static function run() return hihlib.Tool.twice(21);\n}\n",
    "proj/src/Main.hx": "class Main {\n\tstatic function main() {\n\t\ttrace(hihlib.Tool.twice(2));\n\t\t#if hihdep trace(hihdep.Dep.run()); #end\n\t}\n}\n",
    "proj/build.hxml": "-cp src\n-L hihlib\n--main Main\n",
}

CASES = [
    ("one-lib", ["-cp", "src", "-L", "hihlib", "--main", "Main"]),
    ("dependency", ["-cp", "src", "--library", "hihdep", "--main", "Main"]),
    ("several", ["-cp", "src", "-L", "hihlib", "-L", "hihdep", "--main", "Main"]),
    ("lib-flag", ["-cp", "src", "-lib", "hihlib", "--main", "Main"]),
    ("global", ["-cp", "src", "--haxelib-global", "-L", "hihlib", "--main", "Main"]),
    ("missing", ["-cp", "src", "-L", "nosuchlib", "--main", "Main"]),
    ("hxml", ["build.hxml"]),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", action="store_true")
    opts = ap.parse_args()
    reference = os.path.abspath(os.environ.get("HAXE_REFERENCE", ""))
    if not os.access(reference, os.X_OK):
        raise SystemExit("HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule.")
    if not shutil.which("haxelib"):
        raise SystemExit("haxelib not found")
    env = os.environ.copy()
    env["HAXE_STD_PATH"] = str(STD)
    env["HAXE_IN_HAXE_STD_PATH"] = str(STD)
    if GENERATED.exists():
        shutil.rmtree(GENERATED)
    for name, text in FILES.items():
        f = GENERATED / name
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)
    proj = GENERATED / "proj"
    for cmd in [["haxelib", "newrepo"], ["haxelib", "dev", "hihlib", str(GENERATED / "libs/hihlib")], ["haxelib", "dev", "hihdep", str(GENERATED / "libs/hihdep")]]:
        subprocess.run(cmd, cwd=proj, env=env, check=True, capture_output=True)
    hl = os.environ.get("HAXE_HL") or shutil.which("hl")
    port_hl = GENERATED / "haxe-in-haxe.hl"
    subprocess.run([reference, "-cp", str(ROOT / "runtime/hl"), "-cp", str(ROOT / "src"), "-main", "haxe.Main", "-hl", str(port_hl)], cwd=ROOT, env=env, check=True)
    ref_cmd, port_cmd = [reference], [hl, str(port_hl)]
    servers = None
    if opts.server:
        servers = (server.start_server("reference", ref_cmd, env, GENERATED / "reference-server.log"),
                   server.start_server("port", port_cmd, env, GENERATED / "port-server.log"))
    failures = 0
    try:
        for name, args in CASES:
            modes = [("batch", None)] + ([("server", servers)] if servers else [])
            for mode, srv in modes:
                outs = {}
                for who, cmd in [("ref", ref_cmd), ("port", port_cmd)]:
                    hxb = GENERATED / ("%s-%s-%s.hxb" % (name, mode, who))
                    # The port restores cached modules only from memory (see test/server.py).
                    cache = ["-D", "disable-hxb-cache"] if srv is not None else []
                    full = ["--hxb", str(hxb), "-D", "disable-parallelism"] + cache + ["--interp", "--no-output"] + args
                    if srv is None:
                        p = subprocess.run(cmd + full, cwd=proj, env=env, capture_output=True, stdin=subprocess.DEVNULL)
                        res = (p.returncode, p.stdout.decode(errors="replace"), p.stderr.decode(errors="replace"))
                    else:
                        s = srv[0] if who == "ref" else srv[1]
                        res = server.run_client(cmd, s["port"], full, proj, env)
                    res = (res[0], res[1].replace("-%s.hxb" % who, "-X.hxb"), res[2].replace("-%s.hxb" % who, "-X.hxb"))
                    outs[who] = (res, hxb)
                (ref, ref_hxb), (port, port_hxb) = outs["ref"], outs["port"]
                detail = server.compare_outputs(ref, port, ref_hxb, port_hxb, GENERATED)
                status = "PASS" if detail is None else "FAIL"
                if detail is None:
                    detail = ("both reject: " + ref[2].strip().splitlines()[0][:100]) if ref[0] != 0 else "%d members identical" % len(__import__("zipfile").ZipFile(ref_hxb).namelist())
                failures += status == "FAIL"
                print("%-6s %-24s %s" % (status, "%s/%s" % (name, mode), detail), flush=True)
    finally:
        if servers:
            for s in servers:
                server.stop_server(s)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
