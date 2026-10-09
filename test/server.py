#!/usr/bin/env python3
"""Compilation-server conformance harness for the translated compiler.

Starts the pinned reference compiler and the port (HashLink build) as
compilation servers (`--wait <port>`), then sends the same requests to both
through `--connect` (the reference client talks to the reference server, the
port's client to the port's server). For each request the two must agree on:

- the exit code and the client's stdout/stderr (paths of the scratch
  directories are normalized), and
- the HXB archive: same member set, byte-identical uncompressed payloads.

Scenarios:

- `cases`: every selected conformance case is compiled `--rounds` times in a
  row on the same servers, so later rounds reuse the server cache.
- `edit`: a small project is copied to a scratch directory, compiled, a file is
  modified (and a new one added), and it is compiled again; this exercises
  cache invalidation. Its server logs (`-v`) are compared line by line, after
  dropping timing lines.
- `misc`: program output under `--interp`, stdin forwarding, `--cmd`, macro
  output, type errors, `--version` and `--next` through the server.
- `server-connect`: the compilers connect to the harness (`--server-connect`)
  and answer length-prefixed requests.

`--hxb-cache` keeps the default HXB module cache (the port needs the HXB
reader to restore modules from it); by default every request adds
`-D disable-hxb-cache`, which caches typed modules in memory. `--fresh`
restarts the servers for every case, so with `--hxb-cache --rounds 1` each
request is the first compilation of a server (HXB written to and exported
from the cache, no restoring).

HAXE_IN_HAXE_PORT replaces the HashLink build with another prebuilt port
command (as in conformance.py), e.g. bin/backend/hih/hih (backend/build.sh port).

Usage: HAXE_REFERENCE=haxe/haxe python3 test/server.py [-j N] [--rounds N] [--hxb-cache] [--fresh]
           [--scenario cases|edit|misc|server-connect|all] [--cases FILE] [name-substring ...]
"""
import argparse, concurrent.futures, os, pathlib, re, shlex, shutil, socket, subprocess, sys, time, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
STD = ROOT / "haxe/std"
GENERATED = ROOT / "test/generated/server"
sys.path.insert(0, str(ROOT / "test"))
import conformance  # noqa: E402  (parse_cases, compare)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def listening(port):
    """Whether a TCP socket listens on [port] (Linux /proc). Connecting to probe
    would send an empty request, which makes a server stop."""
    try:
        text = pathlib.Path("/proc/net/tcp").read_text()
    except OSError:
        time.sleep(2)
        return True
    for line in text.splitlines()[1:]:
        fields = line.split()
        if fields[1].endswith(":%04X" % port) and fields[3] == "0A":
            return True
    return False


def start_server(name, cmd, env, log, verbose=False):
    """Starts a server and waits until it listens, without sending a request."""
    port = free_port()
    logf = open(log, "wb")
    args = cmd + (["-v"] if verbose else []) + ["--wait", str(port)]
    proc = subprocess.Popen(args, cwd=ROOT, env=env, stdout=logf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise SystemExit("%s server exited early, see %s" % (name, log))
        if listening(port):
            break
        time.sleep(0.1)
    else:
        raise SystemExit("%s server did not start" % name)
    return dict(name=name, port=port, proc=proc, log=logf, path=log)


def stop_server(server):
    server["proc"].terminate()
    try:
        server["proc"].wait(timeout=10)
    except subprocess.TimeoutExpired:
        server["proc"].kill()
    server["log"].close()


def run_client(client_cmd, port, args, cwd, env, timeout=900):
    try:
        p = subprocess.run(client_cmd + ["--connect", str(port)] + args, cwd=cwd, env=env, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return p.returncode, p.stdout.decode(errors="replace"), p.stderr.decode(errors="replace")
    except subprocess.TimeoutExpired:
        return "timeout", "", ""


def normalize(text, out_dir):
    # Archive names differ between the two compilers (refN.hxb / portN.hxb).
    return re.sub(r"\b(ref|port)(\d*)\.hxb", r"X\2.hxb", text.replace(str(out_dir), "<OUT>"))


def compare_outputs(ref, port, ref_hxb, port_hxb, out_dir):
    rc, rout, rerr = ref
    pc, pout, perr = port
    if rc != pc:
        return "exit code differs (reference %s, port %s): %s" % (rc, pc, (perr or rerr).strip()[:300])
    if normalize(rout, out_dir) != normalize(pout, out_dir):
        return "stdout differs: reference %r, port %r" % (rout[:200], pout[:200])
    if normalize(rerr, out_dir) != normalize(perr, out_dir):
        return "stderr differs: reference %r, port %r" % (rerr[:300], perr[:300])
    if rc == 0 and ref_hxb.exists():
        if not port_hxb.exists():
            return "port wrote no archive"
        return conformance.compare(ref_hxb, port_hxb)
    return None


def scenario_cases(opts, cases, ref_cmd, port_cmd, env, extra):
    """Compiles each case several times on one pair of servers."""
    results = []
    servers = []
    for k in range(opts.j):
        r = start_server("reference", ref_cmd, env, GENERATED / ("reference-%d.log" % k))
        p = start_server("port", port_cmd, env, GENERATED / ("port-%d.log" % k))
        servers.append((r, p))
    try:
        def worker(k):
            r, p = servers[k]
            out = []
            for i, case in enumerate(cases):
                if i % opts.j != k:
                    continue
                d = GENERATED / case["name"]
                if d.exists():
                    shutil.rmtree(d)
                d.mkdir(parents=True)
                if opts.fresh:
                    # A new server pair per case: every first round starts from an empty cache.
                    stop_server(r)
                    stop_server(p)
                    r = start_server("reference", ref_cmd, env, GENERATED / ("reference-%d.log" % k))
                    p = start_server("port", port_cmd, env, GENERATED / ("port-%d.log" % k))
                    servers[k] = (r, p)
                for rnd in range(1, opts.rounds + 1):
                    ref_hxb, port_hxb = d / ("ref%d.hxb" % rnd), d / ("port%d.hxb" % rnd)
                    def inv(hxb):
                        if case.get("hxml"):
                            return ["--hxb", str(hxb), "-D", "disable-parallelism", "--no-output"] + extra + case["args"]
                        return conformance.COMMON + extra + case["args"] + ["--hxb", str(hxb)]
                    t0 = time.monotonic()
                    ref = run_client(ref_cmd, r["port"], inv(ref_hxb), case["cwd"], env)
                    port = run_client(port_cmd, p["port"], inv(port_hxb), case["cwd"], env)
                    detail = compare_outputs(ref, port, ref_hxb, port_hxb, d)
                    status = "PASS" if detail is None else "FAIL"
                    if detail is None:
                        detail = ("both reject" if ref[0] != 0 else "%d members identical" % len(zipfile.ZipFile(ref_hxb).namelist()))
                    res = dict(name="%s#%d" % (case["name"], rnd), status=status, detail=detail, seconds=round(time.monotonic() - t0, 1))
                    print("%-6s %-44s %6.1fs  %s" % (res["status"], res["name"], res["seconds"], res["detail"]), flush=True)
                    out.append(res)
            return out
        with concurrent.futures.ThreadPoolExecutor(max_workers=opts.j) as pool:
            for out in pool.map(worker, range(opts.j)):
                results.extend(out)
    finally:
        for r, p in servers:
            stop_server(r)
            stop_server(p)
    return results


EDIT_MAIN = """class Main {
	static function main() {
		trace(Helper.value());
		var o = new Other();
		trace(o.name());
	}
}
"""
EDIT_HELPER = """class Helper {
	public static function value() return 1;
}
"""
EDIT_HELPER2 = """class Helper {
	public static function value() return "changed " + Added.x;
}
"""
EDIT_OTHER = """class Other {
	public function new() {}
	public function name() return "other";
}
"""
EDIT_ADDED = """class Added {
	public static var x = 42;
}
"""
EDIT_BROKEN = """class Helper {
	public static function value() return 1 +;
}
"""


def scenario_edit(opts, ref_cmd, port_cmd, env, extra):
    """Compile, edit a file, add a file, break a file, fix it, remove a file:
    compare each step, then compare the verbose server logs."""
    results = []
    r = start_server("reference", ref_cmd, env, GENERATED / "edit-reference.log", True)
    p = start_server("port", port_cmd, env, GENERATED / "edit-port.log", True)
    proj = GENERATED / "edit-project"
    try:
        if proj.exists():
            shutil.rmtree(proj)
        for d in ["src", "out-ref", "out-port"]:
            (proj / d).mkdir(parents=True)
        def write(name, text):
            (proj / "src" / name).write_text(text)
        def remove(name):
            os.remove(proj / "src" / name)
        write("Main.hx", EDIT_MAIN)
        write("Helper.hx", EDIT_HELPER)
        write("Other.hx", EDIT_OTHER)
        steps = [
            ("initial", None),
            ("unchanged", None),
            ("edit-helper", lambda: (write("Added.hx", EDIT_ADDED), write("Helper.hx", EDIT_HELPER2))),
            ("unchanged-after-edit", None),
            ("syntax-error", lambda: write("Helper.hx", EDIT_BROKEN)),
            ("fixed", lambda: write("Helper.hx", EDIT_HELPER2)),
            ("remove-file", lambda: (remove("Added.hx"), write("Helper.hx", EDIT_HELPER))),
            ("touch-only", lambda: os.utime(proj / "src" / "Other.hx")),
        ]
        for name, action in steps:
            if action:
                time.sleep(1.1)  # file times have one-second resolution on some hosts
                action()
            outs = {}
            for who, cmd, srv in [("ref", ref_cmd, r), ("port", port_cmd, p)]:
                hxb = proj / ("out-" + who) / ("%s.hxb" % name)
                args = conformance.COMMON + extra + ["-cp", "src", "--main", "Main", "--hxb", str(hxb)]
                res = run_client(cmd, srv["port"], args, proj, env)
                outs[who] = ((res[0], res[1].replace("out-" + who, "out-X"), res[2].replace("out-" + who, "out-X")), hxb)
            (ref, ref_hxb), (port, port_hxb) = outs["ref"], outs["port"]
            detail = compare_outputs(ref, port, ref_hxb, port_hxb, proj)
            status = "PASS" if detail is None else "FAIL"
            if detail is None:
                detail = "both reject" if ref[0] != 0 else "%d members identical" % len(zipfile.ZipFile(ref_hxb).namelist())
            print("%-6s %-44s %s" % (status, "edit:" + name, detail), flush=True)
            results.append(dict(name="edit:" + name, status=status, detail=detail, seconds=0))
    finally:
        stop_server(r)
        stop_server(p)
    # Server logs: the messages must agree apart from timing, socket chunking and ports.
    def log_lines(path, who):
        lines = []
        for line in pathlib.Path(path).read_text(errors="replace").splitlines():
            line = line.replace("out-" + who, "out-X")
            if line.startswith(("Time spent", "SIGNAL", "Waiting for data", "Reading ", "connect_arg:", ".init")) or line == "":
                continue
            if re.match(r"^\s*\S+\(.*:\d+\)$", line):  # host stack trace on termination
                continue
            lines.append(line)
        return lines
    a = log_lines(GENERATED / "edit-reference.log", "ref")
    b = log_lines(GENERATED / "edit-port.log", "port")
    same = a == b
    detail = "server logs agree (%d lines)" % len(a)
    if not same:
        import difflib
        diff = list(difflib.unified_diff(a, b, "reference", "port", lineterm="", n=1))
        (GENERATED / "edit-log.diff").write_text("\n".join(diff) + "\n")
        detail = "server logs differ, see test/generated/server/edit-log.diff (%d diff lines)" % len(diff)
    print("%-6s %-44s %s" % ("PASS" if same else "FAIL", "edit:server-log", detail), flush=True)
    results.append(dict(name="edit:server-log", status="PASS" if same else "FAIL", detail=detail, seconds=0))
    return results


MISC_MAIN = """class Main {
	@:deprecated("use other") static function old() return 1;
	static function main() {
		trace("hello " + old());
		var line = try Sys.stdin().readLine() catch (e:haxe.io.Eof) "<eof>";
		Sys.println("stdin: " + line);
		Sys.stderr().writeString("to stderr\\n");
	}
}
"""
MISC_BROKEN = """class Broken {
	static function main() {
		var x:Int = "not an int";
	}
}
"""

MISC_REQUESTS = [
    # name, arguments, stdin
    ("interp-run", ["-cp", "src", "--main", "Main", "--interp"], b""),
    ("interp-stdin", ["-cp", "src", "--main", "Main", "--interp"], b"forwarded line\nsecond\n"),
    ("cmd", ["-cp", "src", "--main", "Main", "--interp", "--cmd", "echo from-cmd", "--cmd", "sh -c 'cat; echo err >&2; exit 0'"], b"cmd stdin\n"),
    ("cmd-fails", ["-cp", "src", "--main", "Main", "--interp", "--cmd", "sh -c 'exit 3'"], b""),
    ("macro-print", ["-cp", "src", "--main", "Main", "--no-output", "--macro", "Sys.println('from macro')"], b""),
    ("type-error", ["-cp", "src", "--main", "Broken", "--interp", "--no-output"], b""),
    ("missing-class", ["-cp", "src", "--main", "Nope", "--interp", "--no-output"], b""),
    ("version", ["--version"], b""),
    ("next", ["-cp", "src", "--main", "Main", "--interp", "--no-output", "--next", "-cp", "src", "--main", "Broken", "--interp", "--no-output"], b""),
    ("interp-run-again", ["-cp", "src", "--main", "Main", "--interp"], b""),
]


def run_client_input(client_cmd, port, args, cwd, env, data, timeout=300):
    try:
        p = subprocess.run(client_cmd + ["--connect", str(port)] + args, cwd=cwd, env=env, capture_output=True, timeout=timeout, input=data)
        return p.returncode, p.stdout.decode(errors="replace"), p.stderr.decode(errors="replace")
    except subprocess.TimeoutExpired:
        return "timeout", "", ""


def scenario_misc(opts, ref_cmd, port_cmd, env, extra):
    """Program output, stdin forwarding, --cmd, macro output, errors and --next through the server."""
    results = []
    proj = GENERATED / "misc-project"
    if proj.exists():
        shutil.rmtree(proj)
    (proj / "src").mkdir(parents=True)
    (proj / "src" / "Main.hx").write_text(MISC_MAIN)
    (proj / "src" / "Broken.hx").write_text(MISC_BROKEN)
    r = start_server("reference", ref_cmd, env, GENERATED / "misc-reference.log")
    p = start_server("port", port_cmd, env, GENERATED / "misc-port.log")
    try:
        for name, args, data in MISC_REQUESTS:
            args = ["-D", "disable-parallelism"] + extra + args
            ref = run_client_input(ref_cmd, r["port"], args, proj, env, data)
            port = run_client_input(port_cmd, p["port"], args, proj, env, data)
            detail = compare_outputs(ref, port, pathlib.Path("/nonexistent"), pathlib.Path("/nonexistent"), proj)
            status = "PASS" if detail is None else "FAIL"
            if detail is None:
                detail = "exit %s, %d bytes stdout, %d bytes stderr identical" % (ref[0], len(ref[1]), len(ref[2]))
            print("%-6s %-44s %s" % (status, "misc:" + name, detail), flush=True)
            results.append(dict(name="misc:" + name, status=status, detail=detail, seconds=0))
    finally:
        stop_server(r)
        stop_server(p)
    return results


def scenario_server_connect(opts, ref_cmd, port_cmd, env, extra):
    """`--server-connect`: the compiler connects to us and reads length-prefixed requests."""
    import struct
    results = []
    proj = GENERATED / "misc-project"
    if not proj.exists():
        (proj / "src").mkdir(parents=True)
        (proj / "src" / "Main.hx").write_text(MISC_MAIN)
        (proj / "src" / "Broken.hx").write_text(MISC_BROKEN)
    requests = [
        ["--cwd", str(proj), "-D", "disable-parallelism"] + extra + ["-cp", "src", "--main", "Main", "--interp"],
        ["--cwd", str(proj), "-D", "disable-parallelism"] + extra + ["-cp", "src", "--main", "Broken", "--interp", "--no-output"],
        ["--cwd", str(proj), "-D", "disable-parallelism"] + extra + ["-cp", "src", "--main", "Main", "--interp"],
    ]
    responses = {}
    for who, cmd in [("ref", ref_cmd), ("port", port_cmd)]:
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        log = open(GENERATED / ("server-connect-%s.log" % who), "wb")
        proc = subprocess.Popen(cmd + ["--server-connect", "127.0.0.1:%d" % port], cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        listener.settimeout(60)
        out = []
        try:
            conn, _ = listener.accept()
            conn.settimeout(300)
            def recv_exact(n):
                buf = b""
                while len(buf) < n:
                    chunk = conn.recv(n - len(buf))
                    if not chunk:
                        raise EOFError
                    buf += chunk
                return buf
            for req in requests:
                payload = "\n".join(req).encode()
                conn.sendall(struct.pack("<i", len(payload)) + payload)
                (length,) = struct.unpack("<i", recv_exact(4))
                out.append(recv_exact(length).decode(errors="replace"))
            conn.close()
            code = proc.wait(timeout=60)
            out.append("exit %d" % code)
        except Exception as e:
            out.append("error: %r" % e)
            proc.kill()
        finally:
            listener.close()
            log.close()
        responses[who] = out
    for i, (a, b) in enumerate(zip(responses["ref"], responses["port"])):
        same = a == b
        detail = ("%d bytes identical" % len(a)) if same else "reference %r, port %r" % (a[:300], b[:300])
        name = "server-connect:%d" % (i + 1)
        print("%-6s %-44s %s" % ("PASS" if same else "FAIL", name, detail), flush=True)
        results.append(dict(name=name, status="PASS" if same else "FAIL", detail=detail, seconds=0))
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=1, help="server pairs (each pair gets a share of the cases)")
    ap.add_argument("--rounds", type=int, default=2)
    ap.add_argument("--hxb-cache", action="store_true", help="keep the default HXB module cache")
    ap.add_argument("--fresh", action="store_true", help="restart the servers for every case")
    ap.add_argument("--scenario", default="all", choices=["cases", "edit", "misc", "server-connect", "all"])
    ap.add_argument("--cases", default="test/conformance-cases.txt")
    ap.add_argument("filters", nargs="*")
    opts = ap.parse_args()
    reference = os.environ.get("HAXE_REFERENCE")
    if not reference or not os.access(reference, os.X_OK):
        raise SystemExit("HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule.")
    reference = os.path.abspath(reference)
    env = os.environ.copy()
    env["HAXE_STD_PATH"] = str(STD)
    env["HAXE_IN_HAXE_STD_PATH"] = str(STD)
    GENERATED.mkdir(parents=True, exist_ok=True)
    if os.environ.get("HAXE_IN_HAXE_PORT"):
        # a prebuilt port command (e.g. the hxc build bin/backend/hih/hih), as in conformance.py
        port_cmd = [str(ROOT / a) if (ROOT / a).is_file() else a for a in shlex.split(os.environ["HAXE_IN_HAXE_PORT"])]
    else:
        hl = os.environ.get("HAXE_HL") or shutil.which("hl")
        port_hl = GENERATED / "haxe-in-haxe.hl"
        code = subprocess.run([reference, "-cp", str(ROOT / "runtime/hl"), "-cp", str(ROOT / "src"), "-main", "haxe.Main", "-hl", str(port_hl)], cwd=ROOT, env=env).returncode
        if code != 0:
            raise SystemExit("Building the port for HashLink failed")
        port_cmd = [hl, str(port_hl)]
    ref_cmd = [reference]
    extra = [] if opts.hxb_cache else ["-D", "disable-hxb-cache"]
    results = []
    if opts.scenario in ("cases", "all"):
        cases = [c for c in conformance.parse_cases(ROOT / opts.cases) if not opts.filters or any(f in c["name"] for f in opts.filters)]
        results += scenario_cases(opts, cases, ref_cmd, port_cmd, env, extra)
    if opts.scenario in ("edit", "all"):
        results += scenario_edit(opts, ref_cmd, port_cmd, env, extra)
    if opts.scenario in ("misc", "all"):
        results += scenario_misc(opts, ref_cmd, port_cmd, env, extra)
    if opts.scenario in ("server-connect", "all"):
        results += scenario_server_connect(opts, ref_cmd, port_cmd, env, extra)
    counts = {}
    for r in results:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print("Server conformance: %d requests: %s" % (len(results), ", ".join("%s %d" % kv for kv in sorted(counts.items()))))
    (GENERATED / "summary.tsv").write_text("".join("%s\t%s\t%s\n" % (r["status"], r["name"], r["detail"]) for r in results))
    sys.exit(1 if counts.get("FAIL") else 0)


if __name__ == "__main__":
    main()
