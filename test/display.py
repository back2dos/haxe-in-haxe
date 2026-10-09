#!/usr/bin/env python3
"""Display (IDE services) conformance harness for the translated compiler.

The corpus is haxe/tests/display/src/cases/*.hx. Every documented test method
holds a source snippet with `{-N-}` markers; the method body names the display
requests it issues (fields/toplevel -> display/completion, type/doc/metadataDoc
-> display/hover, position(s) -> display/definition, usage ->
display/references, signature -> display/signatureHelp, diagnostics() ->
display/diagnostics). Markers are extracted exactly like
tests/display/src-shared/Marker.hx and the snippet is written to
test/generated/display/<Case>/<method>/<CaseFile>.hx, mirroring the Vfs of
RpcDisplayTestContext (cwd = that directory, `-cp src-misc`,
`-D message.reporting=classic`, `--no-output`).

Each request is sent as a batch `--display <json-rpc>` invocation to the
pinned reference compiler and to the port. The comparison is exact over exit
code, stdout and stderr, after replacing the `"timestamp"` value of JSON-RPC
responses (wall-clock time).

Requests with a non-literal marker (e.g. `pos(i)` in a loop) are expanded over
every marker of the snippet. `documentSymbols()` (the removed legacy
`0@module-symbols` form) is sent as display/documentSymbols. `initialize`,
display/metadata and display/defines are sent once. With --extended, every
marker is also queried with every position-based method (completion, hover,
definition, typeDefinition, implementation, references, signatureHelp) and
every snippet with diagnostics, documentSymbols, statistics and package.

Usage: HAXE_REFERENCE=haxe/haxe python3 test/display.py [-j N] [--extended] [name-substring ...]
"""
import argparse, concurrent.futures, json, os, pathlib, re, shlex, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
CASES = ROOT / "haxe/tests/display/src/cases"
SRC_MISC = ROOT / "haxe/tests/display/src-misc"
GENERATED = ROOT / "test/generated/display"
TIMEOUT = 600

METHODS = {
	"fields": ("display/completion", True),
	"toplevel": ("display/completion", True),
	"type": ("display/hover", False),
	"doc": ("display/hover", False),
	"metadataDoc": ("display/hover", False),
	"position": ("display/definition", False),
	"positions": ("display/definition", False),
	"usage": ("display/references", False),
	"signature": ("display/signatureHelp", True),
}
MARKER_RE = re.compile(r"{-(\d+)-}")
CALL_RE = re.compile(r"\b(" + "|".join(METHODS) + r")\(pos\(([^)]*)\)")
DIAG_RE = re.compile(r"\bdiagnostics\(\)")
SYMBOLS_RE = re.compile(r"\bdocumentSymbols\(\)")
# --extended: every marker and snippet is queried with every file-level method.
EXTENDED_MARKER = ["display/completion", "display/hover", "display/definition", "display/typeDefinition",
	"display/implementation", "display/references", "display/signatureHelp"]
EXTENDED_FILE = ["display/diagnostics", "display/documentSymbols", "display/statistics", "display/package"]
TIMESTAMP_RE = re.compile(r'"timestamp":-?[0-9.eE+-]+')


def extract_markers(doc):
	markers = {}
	acc = 0
	def repl(m):
		nonlocal acc
		markers[int(m.group(1))] = m.start() - acc
		acc += len(m.group(0))
		return ""
	return MARKER_RE.sub(repl, doc), markers


def body_of(text, start):
	"""Text of the brace-delimited block starting at or after `start`."""
	i = text.index("{", start)
	depth = 0
	for j in range(i, len(text)):
		c = text[j]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				return text[i:j + 1]
	return text[i:]


def parse_case_file(path, extended=False):
	text = path.read_text()
	tests = []
	pos = 0
	while True:
		start = text.find("/**", pos)
		if start < 0:
			break
		end = text.find("**/", start + 3)
		if end < 0:
			break
		doc = text[start + 3:end]
		pos = end + 3
		m = re.compile(r"\s*((?:@[:\w]+(?:\([^)]*\))?\s*)*)(?:(?:public|private|static|override)\s+)*function\s+(\w+)").match(text, pos)
		if not m:
			continue
		meta, name = m.group(1), m.group(2)
		if "@:funcCode" in meta:
			doc = "class Main { static function main() { " + doc + "}}"
		doc = doc.replace("**\\/", "**/")
		filename = path.name
		fm = re.search(r'@:filename\(\s*"([^"]*)"\s*\)', meta)
		if fm:
			filename = fm.group(1)
		body = body_of(text, m.end())
		source, markers = extract_markers(doc)
		requests = []
		for call in CALL_RE.finditer(body):
			method, arg = call.group(1), call.group(2).strip()
			ids = [int(arg)] if arg.isdigit() else sorted(markers)
			for i in ids:
				if i in markers:
					requests.append((method, i))
		if DIAG_RE.search(body):
			requests.append(("display/diagnostics", None))
		if SYMBOLS_RE.search(body):
			# The legacy `0@module-symbols` form is gone; the JSON-RPC equivalent is used.
			requests.append(("display/documentSymbols", None))
		if extended:
			for i in sorted(markers):
				requests.extend((rpc, i) for rpc in EXTENDED_MARKER)
			requests.extend((rpc, None) for rpc in EXTENDED_FILE)
		seen = set()
		unique = []
		for method, i in requests:
			rpc = METHODS[method][0] if method in METHODS else method
			key = (rpc, i)
			if key not in seen:
				seen.add(key)
				unique.append((rpc, i))
		tests.append(dict(case=path.stem, name=name, filename=filename, source=source, markers=markers, requests=unique))
	return tests


def request_json(rpc, filename, offset):
	params = {"file": filename}
	if offset is not None:
		params["offset"] = offset
	if rpc in ("display/completion", "display/signatureHelp"):
		params["wasAutoTriggered"] = False
	return json.dumps({"method": rpc, "id": 1, "params": params}, separators=(",", ":"))


def run(cmd, cwd, env):
	start = time.monotonic()
	try:
		p = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=TIMEOUT)
		res = (p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace"))
	except subprocess.TimeoutExpired:
		res = ("timeout", "", "")
	return res, time.monotonic() - start


def normalize(res):
	code, out, err = res
	return (code, TIMESTAMP_RE.sub('"timestamp":0', out), TIMESTAMP_RE.sub('"timestamp":0', err))


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("-j", type=int, default=1)
	ap.add_argument("--list", action="store_true", help="list requests without running them")
	ap.add_argument("--extended", action="store_true", help="query every marker with every position method")
	ap.add_argument("filters", nargs="*")
	args = ap.parse_args()

	reference = os.environ.get("HAXE_REFERENCE", str(ROOT / "haxe/haxe"))
	port = shlex.split(os.environ.get("HAXE_IN_HAXE_PORT", "hl " + str(ROOT / "test/generated/haxe-in-haxe.hl")))  # the build test/conformance.py makes
	env = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"))

	jobs = []
	for path in sorted(CASES.glob("*.hx")):
		if path.name == "import.hx":
			continue
		for t in parse_case_file(path, args.extended):
			label = t["case"] + "." + t["name"]
			if args.filters and not any(f in label for f in args.filters):
				continue
			d = GENERATED / t["case"] / t["name"]
			for rpc, marker in t["requests"]:
				offset = None if marker is None else t["markers"][marker]
				jobs.append(dict(label=label, dir=d, test=t, rpc=rpc, marker=marker, json=request_json(rpc, t["filename"], offset)))
	# Requests that do not depend on a file.
	globals_test = dict(case="_global", name="test", filename="Main.hx", source="class Main {}\n", markers={})
	for rpc, params in [("initialize", {}), ("display/metadata", {"compiler": True, "user": True}),
			("display/defines", {"compiler": True, "user": True})]:
		label = "_global." + rpc
		if args.filters and not any(f in label for f in args.filters):
			continue
		jobs.append(dict(label=label, dir=GENERATED / "_global", test=globals_test, rpc=rpc, marker=None,
			json=json.dumps({"method": rpc, "id": 1, "params": params}, separators=(",", ":"))))
	if args.list:
		for j in jobs:
			print(j["label"], j["rpc"], j["marker"])
		print(len(jobs), "requests")
		return 0

	written = set()
	for j in jobs:
		if j["dir"] in written:
			continue
		written.add(j["dir"])
		j["dir"].mkdir(parents=True, exist_ok=True)
		target = j["dir"] / j["test"]["filename"]
		target.parent.mkdir(parents=True, exist_ok=True)
		target.write_text(j["test"]["source"])

	common = ["-cp", str(SRC_MISC), "-D", "message.reporting=classic", "--no-output", "--display"]

	def one(j):
		ref, tr = run([reference] + common + [j["json"]], j["dir"], env)
		got, tp = run(port + common + [j["json"]], j["dir"], env)
		return j, normalize(ref), normalize(got), tr, tp

	results = {"match": 0, "mismatch": 0, "timeout": 0}
	failures = []
	start = time.monotonic()
	with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.j)) as ex:
		for j, ref, got, tr, tp in ex.map(one, jobs):
			tag = "%s %s %s" % (j["label"], j["rpc"], "" if j["marker"] is None else "{-%d-}" % j["marker"])
			if got[0] == "timeout":
				status = "timeout"
			elif ref == got:
				status = "match"
			else:
				status = "mismatch"
			results[status] += 1
			if status != "match":
				failures.append(tag)
				name = "%s.%s.%s" % (j["rpc"].replace("/", "_"), "file" if j["marker"] is None else j["marker"], "txt")
				with open(j["dir"] / ("request." + name), "w") as f:
					f.write(j["json"] + "\n")
				with open(j["dir"] / ("ref." + name), "w") as f:
					f.write("exit %s\n--- stdout\n%s\n--- stderr\n%s\n" % ref)
				with open(j["dir"] / ("port." + name), "w") as f:
					f.write("exit %s\n--- stdout\n%s\n--- stderr\n%s\n" % got)
			print("%-8s %s (ref %.1fs, port %.1fs)" % (status.upper(), tag, tr, tp), flush=True)
	total = sum(results.values())
	print("\n%d requests: %d match, %d mismatch, %d timeout (%.0fs)" % (total, results["match"], results["mismatch"], results["timeout"], time.monotonic() - start))
	if failures:
		(GENERATED / "failures.txt").write_text("\n".join(failures) + "\n")
	return 0 if not failures else 1


if __name__ == "__main__":
	sys.exit(main())
