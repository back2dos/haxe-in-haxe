#!/usr/bin/env python3
"""Eval debugger conformance harness (`-D eval-debugger=host:port`).

The Eval debugger is a JSON-RPC client: the compiler connects to the debugger
(the vshaxe eval debug adapter, here this script) at host:port, waits for a
`continue`, and answers requests while the interpreted program runs or stands
at a breakpoint. Frames: the debugger sends a 2-byte little-endian length then
the JSON text, the compiler a 4-byte little-endian length then the JSON text
(evalDebugSocket.ml, core/socket.ml).

This script drives the reference compiler and the port through the same
scripted sessions (breakpoints, conditional breakpoints, stepping, stack
traces, scopes, variables and their children, evaluation, assignment,
exception stops, function breakpoints) over test/eval-debugger/,
records every message each compiler sends (responses and events, with their
order normalized: after each request the response, then the events in arrival
order) plus the program's stdout/stderr and exit code, and compares the two
transcripts.

`getCompletion` is not exercised: upstream's handler reads the eval of the
socket thread, which has none, so the request kills the debugger thread (the
reference then hangs; the port's green-thread runtime reports a deadlock).

Usage: HAXE_REFERENCE=haxe/haxe HAXE_IN_HAXE_PORT=bin/port/hih python3 test/eval-debugger.py
           [--keep] [--show reference|port] [scenario ...]
"""
import argparse, json, os, pathlib, re, select, socket, struct, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TIMEOUT = 15
STEP_WAIT = 1.0
VERBOSE = False
CASES = ROOT / "test/eval-debugger"
OUT = ROOT / "test/generated/eval-debugger"


class Session:
    def __init__(self, compiler, args, cwd):
        self.srv = socket.socket()
        self.srv.bind(("127.0.0.1", 0))
        self.srv.listen(1)
        port = self.srv.getsockname()[1]
        self.proc = subprocess.Popen(
            [compiler, "--cwd", str(cwd)] + args + ["-D", "eval-debugger=127.0.0.1:%d" % port],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.srv.settimeout(60)
        self.conn, _ = self.srv.accept()
        self.buf = b""
        self.rid = 0
        self.log = []
        self.closed = False

    def _recv(self, timeout):
        """One message, None at EOF, or "timeout"."""
        while True:
            if len(self.buf) >= 4:
                n = struct.unpack("<I", self.buf[:4])[0]
                if len(self.buf) >= 4 + n:
                    m = self.buf[4:4 + n]
                    self.buf = self.buf[4 + n:]
                    return json.loads(m.decode("utf-8"))
            if self.closed:
                return None
            r, _, _ = select.select([self.conn], [], [], timeout)
            if not r:
                return "timeout"
            x = self.conn.recv(65536)
            if not x:
                self.closed = True
                continue
            self.buf += x

    def request(self, method, params=None, wait_stop=False, drain=0.3):
        """Sends a request; reads until its response (and, with [wait_stop], until a
        stop event or the end of the connection), then whatever arrives within
        [drain] seconds."""
        self.rid += 1
        o = {"jsonrpc": "2.0", "id": self.rid, "method": method}
        if params is not None:
            o["params"] = params
        s = json.dumps(o).encode("utf-8")
        self.conn.sendall(struct.pack("<H", len(s)) + s)
        response = None
        events = []
        stopped = False
        deadline = time.time() + TIMEOUT
        while response is None or (wait_stop and not stopped):
            m = self._recv(max(0.0, deadline - time.time()))
            if m == "timeout":
                events.append({"harness": "timeout"})
                break
            if m is None:
                events.append({"harness": "eof"})
                stopped = True
                if response is None:
                    break
                continue
            if "method" in m:
                events.append(m)
                if m["method"] in ("breakpointStop", "exceptionStop"):
                    stopped = True
            else:
                response = m
        while not self.closed:
            m = self._recv(drain)
            if m == "timeout" or m is None:
                break
            events.append(m)
        entry = {"request": o, "response": response, "events": events}
        if VERBOSE:
            print(json.dumps(entry), flush=True)
        self.log.append(entry)
        return response

    def step(self, method):
        """Stepping sends no event: the program stands again once it reaches the next
        debug point (assumed within STEP_WAIT seconds)."""
        return self.request(method, T0, drain=STEP_WAIT)

    def result(self, method, params=None, **kw):
        r = self.request(method, params, **kw)
        return r.get("result") if isinstance(r, dict) else None

    def finish(self):
        try:
            out, err = self.proc.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            out, err = self.proc.communicate()
            err += b"\n<harness: killed after timeout>"
        rest = []
        while not self.closed:
            m = self._recv(0.5)
            if m == "timeout" or m is None:
                break
            rest.append(m)
        self.conn.close()
        self.srv.close()
        return {
            "log": self.log,
            "trailing": rest,
            "stdout": out.decode("utf-8", "replace"),
            "stderr": err.decode("utf-8", "replace"),
            "exit": self.proc.returncode,
        }


T0 = {"threadId": 0}


def inspect_frame(s, frame_id=1, depth=1):
    """Scopes of a frame, their variables and (to [depth]) the variables' children."""
    scopes = s.result("getScopes", {"frameId": frame_id}) or []
    for sc in scopes:
        vars_ = s.result("getVariables", {"id": sc["id"]}) or []
        for v in vars_ if depth > 0 else []:
            if v.get("id"):
                s.result("getVariables", {"id": v["id"]})


def scenario_breakpoints(s):
    s.result("setBreakpoints", {"file": "Main.hx", "breakpoints": [{"line": 26}, {"line": 38}, {"line": 46, "condition": "i == 1"}]})
    s.result("setExceptionOptions", ["uncaught"])
    s.request("continue", T0, wait_stop=True)
    s.result("getThreads", {})
    s.result("stackTrace", T0)
    inspect_frame(s)
    s.result("evaluate", {"expr": "a + 1", "frameId": 1})
    s.result("evaluate", {"expr": "b.length", "frameId": 1})
    s.result("evaluate", {"expr": "b.charAt(0) + c", "frameId": 1})
    s.result("evaluate", {"expr": "var q = 5", "frameId": 1})
    s.result("evaluate", {"expr": "q * 2", "frameId": 1})
    s.result("evaluate", {"expr": "nope(", "frameId": 1})
    s.result("evaluate", {"expr": "counter", "frameId": 1})
    s.result("evaluate", {"expr": "Main.counter + 1", "frameId": 1})
    s.result("evaluate", {"expr": "[a, 2, 3].length", "frameId": 1})
    s.result("evaluate", {"expr": "{x: a}", "frameId": 1})
    s.step("next")
    s.result("stackTrace", T0)
    s.step("next")
    s.result("stackTrace", T0)
    inspect_frame(s)
    s.step("stepOut")
    s.result("stackTrace", T0)
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    inspect_frame(s, depth=1)
    s.result("evaluate", {"expr": "p.sum()", "frameId": 1})
    s.result("evaluate", {"expr": "p.x * 10", "frameId": 1})
    s.result("evaluate", {"expr": "col", "frameId": 1})
    s.result("evaluate", {"expr": "o.name", "frameId": 1})
    s.result("evaluate", {"expr": "m", "frameId": 1})
    s.result("evaluate", {"expr": "new Point(1, 2)", "frameId": 1})
    s.result("evaluate", {"expr": "arr[1]", "frameId": 1})
    s.result("evaluate", {"expr": "r = 100", "frameId": 1})
    s.result("evaluate", {"expr": "r", "frameId": 1})
    s.step("stepIn")
    s.result("stackTrace", T0)
    s.step("stepIn")
    s.result("stackTrace", T0)
    inspect_frame(s)
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    inspect_frame(s, depth=0)
    s.result("removeBreakpoint", {"id": 3})
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.request("continue", T0, wait_stop=True)


def scenario_set_variable(s):
    s.result("setBreakpoints", {"file": "Main.hx", "breakpoints": [{"line": 39}]})
    s.result("setExceptionOptions", ["none"])
    s.request("continue", T0, wait_stop=True)
    scopes = s.result("getScopes", {"frameId": 1}) or []
    for sc in scopes:
        vars_ = s.result("getVariables", {"id": sc["id"]}) or []
        names = {v["name"]: v for v in vars_}
        if "r" in names:
            s.result("setVariable", {"id": sc["id"], "name": "r", "value": "7"})
        if "arr" in names and names["arr"].get("id"):
            s.result("setVariable", {"id": names["arr"]["id"], "name": "[1]", "value": "20"})
            s.result("getVariables", {"id": names["arr"]["id"]})
        if "o" in names and names["o"].get("id"):
            s.result("setVariable", {"id": names["o"]["id"], "name": "value", "value": "\"changed\""})
            s.result("getVariables", {"id": names["o"]["id"]})
        if "arr" in names:
            s.result("setVariable", {"id": sc["id"], "name": "t", "value": "1.5"})
        s.result("getVariables", {"id": sc["id"]})
    s.result("setVariable", {"id": 9999, "name": "x", "value": "1"})
    s.result("getVariables", {"id": 9999})
    s.request("continue", T0, wait_stop=True)


def scenario_exceptions(s):
    s.result("setExceptionOptions", ["all"])
    s.result("setBreakpoints", {"file": "Main.hx", "breakpoints": []})
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    inspect_frame(s, depth=0)
    s.result("setExceptionOptions", ["uncaught"])
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.request("continue", T0, wait_stop=True)


def scenario_function_breakpoints(s):
    s.result("setFunctionBreakpoints", [{"name": "Main.helper"}, {"name": "Point.sum"}])
    s.result("setExceptionOptions", ["none"])
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.step("next")
    s.result("stackTrace", T0)
    inspect_frame(s, depth=0)
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.request("pause", T0)
    s.request("continue", T0, wait_stop=True)
    s.request("continue", T0, wait_stop=True)


def scenario_errors(s):
    s.result("setBreakpoint", {"file": "Main.hx", "breakpoint": {"line": 27, "column": 3}})
    s.result("setBreakpoint", {"file": "Main.hx", "breakpoint": {"line": 33}})
    s.result("noSuchMethod", {})
    s.result("getScopes", {"frameId": 77})
    s.result("getVariables", {"id": 0})
    s.result("stackTrace", {"threadId": 5})
    s.result("setExceptionOptions", ["none"])
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.request("continue", T0, wait_stop=True)


def scenario_macro(s):
    """A breakpoint in a macro function: the macro context's interpreter stops
    while the compiler types MacroMain, then the program runs in the second
    (`--interp`) context, which shares the breakpoints."""
    s.result("setBreakpoints", {"file": "MacroMain.hx", "breakpoints": [{"line": 13}, {"line": 5}]})
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    inspect_frame(s)
    s.result("evaluate", {"expr": "n + 1", "frameId": 1})
    s.result("evaluate", {"expr": "e.pos", "frameId": 1})
    s.step("next")
    s.result("stackTrace", T0)
    inspect_frame(s, depth=0)
    s.request("continue", T0, wait_stop=True)
    s.result("stackTrace", T0)
    s.request("continue", T0, wait_stop=True)


SCENARIOS = {
    "breakpoints": (scenario_breakpoints, ["-main", "Main", "--interp"]),
    "set-variable": (scenario_set_variable, ["-main", "Main", "--interp"]),
    "exceptions": (scenario_exceptions, ["-main", "Main", "--interp"]),
    "function-breakpoints": (scenario_function_breakpoints, ["-main", "Main", "--interp"]),
    "errors": (scenario_errors, ["-main", "Main", "--interp"]),
    "macro": (scenario_macro, ["-main", "MacroMain", "--interp"]),
}


def run(compiler, name):
    f, args = SCENARIOS[name]
    s = Session(compiler, args, CASES)
    try:
        f(s)
    except Exception as e:  # a broken session still yields a transcript to compare
        s.log.append({"harness-error": repr(e)})
    return s.finish()


SOFFSET = re.compile(r"^(index|offset)\d+$")


def normalize(t):
    """Drops what is legitimately runtime-specific: a string's `index<i>`/`offset<i>`
    children (OCaml's cache of code point offsets, which the port's strings do not
    have), the host's thread number in "Thread N killed on uncaught exception",
    and the response to a request after which the program ran to its end (sent
    or not before the process exited, a race)."""
    for e in t["log"]:
        if {"harness": "eof"} in e.get("events", []):
            # the program ended: whether the response to the request that let it
            # run to its end was sent before the process exited is a race
            e["response"] = "<maybe>"
        r = e.get("response")
        if isinstance(r, dict) and e["request"]["method"] == "getVariables" and isinstance(r.get("result"), list):
            r["result"] = [v for v in r["result"] if not SOFFSET.match(str(v.get("name")))]
    t["stderr"] = re.sub(r"Thread \d+ killed", "Thread N killed", t["stderr"])
    text = json.dumps(t, indent=1, sort_keys=False, ensure_ascii=False)
    return text.replace(str(CASES), "<cases>")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", action="store_true", help="write the transcripts to test/generated/eval-debugger")
    ap.add_argument("--show", choices=["reference", "port"], help="run one compiler only and print its transcript")
    ap.add_argument("names", nargs="*")
    a = ap.parse_args()
    ref = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
    port = os.environ.get("HAXE_IN_HAXE_PORT", str(ROOT / "bin/port/hih"))
    names = [n for n in SCENARIOS if not a.names or n in a.names]
    if a.show:
        global VERBOSE
        VERBOSE = True
        for name in names:
            t = run(ref if a.show == "reference" else port, name)
            print(json.dumps({k: v for k, v in t.items() if k != "log"}, indent=1))
        return
    failed = 0
    for name in names:
        r = normalize(run(ref, name))
        p = normalize(run(port, name))
        if a.keep or r != p:
            OUT.mkdir(parents=True, exist_ok=True)
            (OUT / (name + ".reference.json")).write_text(r)
            (OUT / (name + ".port.json")).write_text(p)
        if r == p:
            print("ok   " + name)
        else:
            failed += 1
            print("FAIL " + name + " (see test/generated/eval-debugger/%s.*.json)" % name)
    print("%d/%d scenarios identical" % (len(names) - failed, len(names)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
