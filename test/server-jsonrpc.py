#!/usr/bin/env python3
"""`server/*` JSON-RPC methods through a running compilation server.

Starts the pinned reference compiler and the port as compilation servers
(`--wait <port>`, one after the other, on the same project directory
test/server-jsonrpc/), compiles the project through `--connect`, then sends
the same sequence of display JSON-RPC requests (`--display <json>`) to each:
`initialize`, `server/readClassPaths`, `server/contexts`, `server/modules`,
`server/module`, `server/type`, `server/typeContexts`, `server/files`,
`server/moduleCreated`, `server/invalidate`, `server/configure`,
`server/memory`, `server/memory/context`, `server/memory/module` and
`typer/compiledTypes`, with a recompilation in between so that modules come
back from the server's HXB module cache.

Compared per request: exit code, stdout, and the JSON response, after
normalizing what is legitimately runtime-specific:
- the `timestamp` of every response;
- in the `server/memory*` responses, every `size` and cache total (object
  sizes are measured on OCaml's heap by the reference and on the host heap by
  the port, see src/context/Memory.hx), the order of the size-sorted lists
  (sorted by name instead) and `leaks` (which objects reach the memory markers
  depends on the runtime's object graph).

Usage: HAXE_REFERENCE=haxe/haxe HAXE_IN_HAXE_PORT=bin/port/hih python3 test/server-jsonrpc.py [--keep]
"""
import argparse, json, os, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "test/server-jsonrpc"
OUT = ROOT / "test/generated/server-jsonrpc"
sys.path.insert(0, str(ROOT / "test"))
import server  # noqa: E402  (start_server, stop_server)

BASE0 = ["--cwd", str(PROJECT), "-cp", "src", "-main", "Main", "--interp", "--no-output", "-D", "disable-parallelism"]
# The server's module cache: HXB (the default; `server/module` reads modules back with
# the HXB reader) or typed modules in memory.
MODES = [("hxb-cache", []), ("disable-hxb-cache", ["-D", "disable-hxb-cache"])]
MEMORY = ("server/memory", "server/memory/context", "server/memory/module")
SIZES = ("size", "totalCache", "contextCache", "haxelibCache", "directoryCache", "nativeLibCache", "moduleExtra")


def client(cmd, port, args):
    try:
        p = subprocess.run(cmd + ["--connect", str(port)] + args, capture_output=True, timeout=300, stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return "timeout", "", ""


def session(cmd, env, extra):
    """Runs the request sequence on a fresh server; returns [(label, code, stdout, response)]."""
    BASE = BASE0 + extra
    srv = server.start_server("server", cmd, env, OUT / ("server-%s.log" % pathlib.Path(cmd[0]).name))
    log = []
    try:
        def compile_(label):
            code, out, err = client(cmd, srv["port"], BASE)
            log.append((label, code, out, err))

        def rpc(method, params=None):
            req = {"jsonrpc": "2.0", "id": 1, "method": method}
            if params is not None:
                req["params"] = params
            code, out, err = client(cmd, srv["port"], BASE + ["--display", json.dumps(req)])
            try:
                resp = json.loads(err)
            except ValueError:
                resp = err
            log.append((method + " " + json.dumps(params, sort_keys=True), code, out, resp))
            return resp

        def result(resp):
            try:
                return resp["result"]["result"]
            except (TypeError, KeyError):
                return None

        compile_("compile 1")
        rpc("initialize", {"supportsResolve": True})
        rpc("server/readClassPaths", {})
        contexts = result(rpc("server/contexts", {})) or []
        signs = [c["signature"] for c in contexts]
        for sign in signs:
            rpc("server/modules", {"signature": sign})
            rpc("server/files", {"signature": sign})
            for path in ["pack.Other", "Main", "Build", "StdTypes", "haxe.ds.StringMap", "NoSuchModule"]:
                rpc("server/module", {"signature": sign, "path": path})
            for mod, typ in [("pack.Other", "E"), ("pack.Other", "Abs"), ("pack.Other", "T"), ("pack.Other", "Other"), ("pack.Other", "Nope"),
                             ("Main", "Main"), ("Nope", "Nope")]:
                rpc("server/type", {"signature": sign, "modulePath": mod, "typeName": typ})
            rpc("server/memory/context", {"signature": sign})
            rpc("server/memory/module", {"signature": sign, "path": "pack.Other"})
        rpc("server/typeContexts", {"modulePath": "pack.Other", "typeName": "E"})
        rpc("server/typeContexts", {"modulePath": "Main", "typeName": "Main"})
        rpc("server/memory", {})
        rpc("server/configure", {"print": {"addedDirectory": True, "stats": False}, "noModuleChecks": False})
        rpc("server/configure", {"print": {"noSuchSetting": True}})
        rpc("server/moduleCreated", {"file": str(PROJECT / "src/pack/Other.hx")})
        rpc("server/invalidate", {"file": str(PROJECT / "src/pack/Other.hx")})
        for sign in signs:
            rpc("server/module", {"signature": sign, "path": "pack.Other"})
            rpc("server/module", {"signature": sign, "path": "Main"})
        compile_("compile 2")
        for sign in signs:
            rpc("server/modules", {"signature": sign})
            rpc("server/module", {"signature": sign, "path": "pack.Other"})
            rpc("server/module", {"signature": sign, "path": "Main"})
            rpc("server/type", {"signature": sign, "modulePath": "pack.Other", "typeName": "Other"})
        rpc("server/memory", {})
        rpc("typer/compiledTypes", {})
        rpc("server/noSuchMethod", {})
    finally:
        server.stop_server(srv)
    return log


def strip_memory(j):
    if isinstance(j, dict):
        out = {}
        for k, v in j.items():
            if k in SIZES:
                out[k] = 0
            elif k == "leaks":
                out[k] = "<leaks>"
            else:
                out[k] = strip_memory(v)
        return out
    if isinstance(j, list):
        l = [strip_memory(x) for x in j]
        if all(isinstance(x, dict) and ("path" in x or "name" in x) for x in l):
            l.sort(key=lambda x: json.dumps(x, sort_keys=True))
        return l
    return j


def normalize(entry):
    label, code, out, resp = entry
    if isinstance(resp, dict):
        r = resp.get("result")
        if isinstance(r, dict) and "timestamp" in r:
            r["timestamp"] = 0
        if label.split(" ")[0] in MEMORY:
            resp = strip_memory(resp)
    elif isinstance(resp, str):
        resp = re.sub(r'"timestamp":[0-9.e+-]+', '"timestamp":0', resp)
    return json.dumps([label, code, out, resp], indent=1, ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="write both transcripts to test/generated/server-jsonrpc")
    a = ap.parse_args()
    ref = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
    port = os.environ.get("HAXE_IN_HAXE_PORT", str(ROOT / "bin/port/hih"))
    env = dict(os.environ)
    OUT.mkdir(parents=True, exist_ok=True)
    ok = True
    for mode, extra in MODES:
        r = [normalize(e) for e in session([ref], env, extra)]
        p = [normalize(e) for e in session([port], env, extra)]
        if a.keep:
            (OUT / ("%s.reference.json" % mode)).write_text("[\n" + ",\n".join(r) + "\n]\n")
            (OUT / ("%s.port.json" % mode)).write_text("[\n" + ",\n".join(p) + "\n]\n")
        same = 0
        for i, (x, y) in enumerate(zip(r, p)):
            label = json.loads(x)[0]
            if x == y:
                same += 1
                print("ok   %s %3d %s" % (mode, i + 1, label))
            else:
                print("FAIL %s %3d %s\n  reference: %s\n  port:      %s" % (mode, i + 1, label, x[:600].replace("\n", ""), y[:600].replace("\n", "")))
        if len(r) != len(p):
            print("FAIL %s request count: reference %d, port %d" % (mode, len(r), len(p)))
        print("%s: %d/%d requests identical" % (mode, same, max(len(r), len(p))))
        ok = ok and same == len(r) == len(p)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
