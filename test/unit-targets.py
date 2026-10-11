#!/usr/bin/env python3
"""Compiles upstream's unit test suite (haxe/tests/unit) to every target with
the reference and the port and compares the generated files byte for byte.

  HAXE_REFERENCE=haxe/haxe python3 test/unit-targets.py [-j N] [target ...]

For each target below, both compilers run the target's upstream hxml
(compile-<target>.hxml, with the hxmls it includes inlined) from the same
working directory, a copy of tests/unit in test/generated/unit-targets/unit
(the hxmls write next to the tests, and tests/ belongs to the submodule). The
output paths of the hxml (`bin/...`) are moved to out/<target>/<side>/ so
both runs keep their own output; everything else is the upstream invocation
plus `-D disable-parallelism` (the reference allocates IDs from counters
shared by parallel workers otherwise) and the target's extra arguments in
TARGETS. A file named by a define instead of an output option (FIXED_OUTPUTS)
keeps its upstream path; the two runs of that target are then sequential. The
programs are not run, and compile-macro.hxml (--interp, no output) is left to
test/upstream.py, which runs it; the fuzzer's `diff:<target>` lanes cover the
generators with random programs.

Every file of the two output trees must exist on both sides and be identical.
JAR members (and the `--java-lib` jar the JVM generator copies to lib/) are
compared by member names and uncompressed member bytes, never container
bytes. The SWF body is compared after inflating (see `normalize`).

Known nondeterminism normalized: unit.TestMainNow embeds
`HelperMacros.getCompilationDate()`, a macro returning `Std.string(Date.now())`
("YYYY-MM-DD HH:MM:SS", local time), so the two compilations embed the time
they ran at. Such a string is replaced by a placeholder of the same length
only when it parses to a time inside the window in which the two compilers of
that target ran, together with the forms generators derive from it (the hash
in hxcpp's HX_ literal, the hl/c constant name); every other byte is compared
as is.

HAXE_REFERENCE: the reference compiler built from the pinned haxe/ submodule
(its directory supplies std/ and tests/unit, so a worktree without the
submodule works). HAXE_IN_HAXE_PORT: the port command (default bin/port/hih,
from hxc/tools/port-dev.sh). Libraries come from a haxelib repository of the
harness (test/generated/unit-targets/haxelib, as HAXELIB_PATH): utest, cloned
as test/upstream.py does (`haxelib git utest` upstream; the clone goes through
the proxy), and hxcpp and hxjava registered from the default repository, since
the cpp and jvm targets add `-lib hxcpp`/`-lib hxjava` even when nothing is
compiled. Nothing is downloaded from lib.haxe.org. JVM also needs
native_java/native.jar, built with `haxelib run hxjava` as
compile-java-native.hxml does (one jar for both compilers). A target whose
requirement is missing (hxcpp, hxjava, or compc from the Flex SDK for
compile-flash.hxml's SWC) is reported as SKIP with the reason.
"""
import argparse, concurrent.futures, datetime, difflib, os, pathlib, re, shlex, shutil, subprocess, sys, time, zipfile, zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
GENERATED = ROOT / "test/generated/unit-targets"
TIMEOUT = 3600

# name -> (upstream hxml, extra arguments, requirement)
TARGETS = {
    "js": ("compile-js.hxml", [], None),
    "lua": ("compile-lua.hxml", [], None),
    "python": ("compile-python.hxml", [], None),
    "php": ("compile-php.hxml", [], None),
    "neko": ("compile-neko.hxml", [], None),
    "hl": ("compile-hl.hxml", [], None),
    # hlgen.makefile=ci only writes a Makefile; no-compilation as in the fuzzer's hlc lane
    "hlc": ("compile-hlc.hxml", ["-D", "no-compilation"], None),
    # compile-jvm.hxml is compile-java-native.hxml (native.jar, built once below) then this
    "jvm": ("compile-jvm-only.hxml", [], "hxjava"),
    # generate the sources only: compiling them is hxcpp's job, not the compiler's
    "cpp": ("compile-cpp.hxml", ["-D", "no-compilation"], "hxcpp"),
    "cppia": ("compile-cppia.hxml", [], None),
    # the cppia host (scriptable C++ with the scripthost classes), sources only
    "cppia-host": ("compile-cppia-host.hxml", ["-D", "no-compilation"], "hxcpp"),
    "flash": ("compile-flash.hxml", [], "compc"),
    "flash-no-swc": ("compile-flash-no-swc.hxml", [], None),
}

# target -> outputs named by a define instead of an output option: the define is part of
# the output (gencpp's Options.txt lists every define), so both compilers use the upstream
# path; the two runs are then sequential and the file is moved to out/<target>/<side>/
# after each
FIXED_OUTPUTS = {
    "cppia-host": ["bin/cppia.classes"],
}

# hxml options whose argument is an output path
OUTPUT_FLAGS = {"-js", "--js", "-lua", "--lua", "-python", "--python", "-php", "--php", "-neko", "--neko",
                "-hl", "--hl", "-cpp", "--cpp", "-cppia", "--cppia", "-swf", "--swf", "-jvm", "--jvm"}

# the date as Std.string(Date) prints it, or with every separator as `_` (identifiers)
DATE = re.compile(rb"\d{4}([-_])\d\d\1\d\d[ _]\d\d[:_]\d\d[:_]\d\d")
DATE_PLACEHOLDER = b"YYYY-MM-DD HH:MM:SS"


def inline_hxml(directory, name):
    """The lines of an hxml with the hxmls it names inlined (as the compiler reads them)."""
    lines = []
    for line in (directory / name).read_text().splitlines():
        stripped = line.strip()
        if stripped.endswith(".hxml") and " " not in stripped and (directory / stripped).is_file():
            lines += inline_hxml(directory, stripped)
        else:
            lines.append(line)
    return lines


def side_hxml(directory, name, out):
    """The hxml with its output paths (bin/...) moved under `out`."""
    result = []
    for line in inline_hxml(directory, name):
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0] in OUTPUT_FLAGS and parts[1].startswith("bin/"):
            line = parts[0] + " " + out + "/" + parts[1][len("bin/"):]
        result.append(line)
    return "\n".join(result) + "\n"


def run(cmd, cwd, log, env):
    start = time.time()
    try:
        with open(log, "wb") as stream:
            code = subprocess.run(cmd, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=TIMEOUT).returncode
    except subprocess.TimeoutExpired:
        code = "timeout"
    return code, start, time.time()


def last_lines(log, n=6):
    try:
        lines = [l for l in pathlib.Path(log).read_text(errors="replace").splitlines() if l.strip()]
    except OSError:
        return ""
    return "\n".join("    " + l[:200] for l in lines[-n:])


def normalize(path, data, window):
    """Known time-dependent bytes (see the module comment) and SWF compression."""
    if path.endswith(".swf") and data[:3] == b"CWS":
        # The dates sit in the compressed body; compare the inflated body (with an FWS
        # header) so the placeholder can be applied. The deflate output itself is checked
        # by the fuzzer's diff:swf lane, which has no time-dependent strings.
        data = b"FWS" + data[3:8] + zlib.decompress(data[8:])

    dates = set()
    for m in DATE.finditer(data):
        d = m.group()[:4] + b"-" + m.group()[5:7] + b"-" + m.group()[8:10] + b" " + m.group()[11:13] + b":" + m.group()[14:16] + b":" + m.group()[17:]
        try:
            t = datetime.datetime.strptime(d.decode(), "%Y-%m-%d %H:%M:%S").timestamp()
        except ValueError:
            continue
        if window[0] - 1 <= t <= window[1] + 1:
            dates.add(d)
    for d in dates:
        # forms the generators derive from the string: hxcpp's HX_ literal carries its
        # hash (gencpp `strq`), hl/c names the constant after it (s$2026_10_11_18_24_37)
        data = re.sub(rb'HX_\("' + re.escape(d) + rb'"(,[0-9a-f]{2}){4}\)', b'HX_("' + DATE_PLACEHOLDER + b'",hh,hh,hh,hh)', data)
        data = data.replace(re.sub(rb"[- :]", b"_", d), re.sub(rb"[- :]", b"_", DATE_PLACEHOLDER))
        data = data.replace(d, DATE_PLACEHOLDER)
    return data


def is_zip(path):
    return path.endswith(".jar") or path.endswith(".zip")


def files_of(root):
    return sorted(str(p.relative_to(root)) for p in root.rglob("*") if p.is_file())


def describe(name, a, b):
    """A unified diff head (text) or the first differing offset (binary)."""
    try:
        ta, tb = a.decode("utf-8"), b.decode("utf-8")
    except UnicodeDecodeError:
        i = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
        lo = max(0, i - 16)
        return (f"    binary, sizes {len(a)}/{len(b)}, first difference at byte {i}\n"
                f"    reference {a[lo:i + 32].hex()}\n    port      {b[lo:i + 32].hex()}")
    diff = difflib.unified_diff(ta.splitlines(), tb.splitlines(), "reference/" + name, "port/" + name, lineterm="", n=2)
    return "\n".join("    " + l[:200] for l in list(diff)[:40])


def compare(ref_root, port_root, window):
    """None when the trees conform, else (summary, detail of the first difference)."""
    fa, fb = files_of(ref_root), files_of(port_root)
    if not fa:
        return "reference wrote no files", ""
    if fa != fb:
        only_a, only_b = sorted(set(fa) - set(fb)), sorted(set(fb) - set(fa))
        return f"file set differs (reference-only {len(only_a)} {only_a[:3]}, port-only {len(only_b)} {only_b[:3]})", ""
    differing, first, members = [], None, 0
    for name in fa:
        a, b = (ref_root / name).read_bytes(), (port_root / name).read_bytes()
        if is_zip(name):
            try:
                za, zb = zipfile.ZipFile(ref_root / name), zipfile.ZipFile(port_root / name)
            except zipfile.BadZipFile as e:
                differing.append(name)
                first = first or (name, f"    unreadable archive: {e}")
                continue
            na, nb = za.namelist(), zb.namelist()
            if sorted(na) != sorted(nb):
                differing.append(name)
                only_a, only_b = sorted(set(na) - set(nb)), sorted(set(nb) - set(na))
                first = first or (name, f"    member set differs (reference-only {only_a[:3]}, port-only {only_b[:3]})")
                continue
            for m in sorted(na):
                members += 1
                x, y = normalize(m, za.read(m), window), normalize(m, zb.read(m), window)
                if x != y:
                    differing.append(name + "!" + m)
                    first = first or (name + "!" + m, describe(m, x, y))
            continue
        if a != b:
            x, y = normalize(name, a, window), normalize(name, b, window)
            if x != y:
                differing.append(name)
                first = first or (name, describe(name, x, y))
    if differing:
        return f"{len(differing)}/{len(fa) + members} files differ: {' '.join(differing[:4])}", f"  first: {first[0]}\n{first[1]}"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=os.cpu_count() or 2, help="parallel compilations")
    ap.add_argument("targets", nargs="*", help=f"targets to run (default all: {' '.join(TARGETS)})")
    opts = ap.parse_args()
    unknown = [t for t in opts.targets if t not in TARGETS]
    if unknown:
        raise SystemExit("unknown target(s): " + " ".join(unknown))
    targets = opts.targets or list(TARGETS)
    reference = os.environ.get("HAXE_REFERENCE")
    if not reference or not os.access(reference, os.X_OK):
        raise SystemExit("HAXE_REFERENCE must be the executable built from the pinned haxe/ submodule.")
    reference = os.path.abspath(reference)
    haxe_dir = pathlib.Path(reference).parent
    if not (haxe_dir / "tests/unit").is_dir():
        haxe_dir = ROOT / "haxe"
    std = haxe_dir / "std"
    port = os.environ.get("HAXE_IN_HAXE_PORT") or str(ROOT / "bin/port/hih")
    port_cmd = [str(ROOT / a) if (ROOT / a).is_file() else a for a in shlex.split(port)]
    if not os.access(port_cmd[0], os.X_OK) and not shutil.which(port_cmd[0]):
        raise SystemExit(f"port not found: {port} (sh hxc/tools/port-dev.sh, or set HAXE_IN_HAXE_PORT)")

    env = os.environ.copy()
    env["HAXE_STD_PATH"] = str(std)
    env["HAXE_IN_HAXE_STD_PATH"] = str(std)
    lib_env = dict(env)  # the default haxelib repository (hxjava)

    # A haxelib repository of our own (HAXELIB_PATH): utest, cloned as test/upstream.py
    # does, and hxcpp/hxjava from the default repository, which the cpp and jvm targets
    # add implicitly (`-lib hxcpp`, `-lib hxjava`) even when nothing is compiled.
    skipped, missing = {}, {}
    sys.path.insert(0, str(ROOT / "test"))
    import upstream
    repo = GENERATED / "haxelib"
    repo.mkdir(parents=True, exist_ok=True)
    env["HAXELIB_PATH"] = str(repo)
    utest = upstream.GENERATED / "libs" / "utest"
    try:
        upstream.clone("https://github.com/haxe-utest/utest.git", upstream.UTEST_COMMIT, utest)
        subprocess.run(["haxelib", "dev", "utest", str(utest)], env=env, check=True, stdout=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, OSError) as e:
        for t in targets:
            skipped[t] = f"utest could not be installed ({e})"
    for lib in ("hxcpp", "hxjava"):
        found = subprocess.run(["haxelib", "libpath", lib], env=lib_env, capture_output=True, text=True)
        path = found.stdout.strip().splitlines()[-1] if found.returncode == 0 and found.stdout.strip() else ""
        if path and os.path.isdir(path):
            subprocess.run(["haxelib", "dev", lib, path], env=env, check=True, stdout=subprocess.DEVNULL)
        else:
            missing[lib] = f"haxelib {lib} is not installed (needed even with -D no-compilation: the target adds -lib {lib})"

    work = GENERATED / "unit"
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(haxe_dir / "tests/unit", work, ignore=shutil.ignore_patterns("bin"))

    def requirement(req):
        if req == "compc":
            # compile-flash.hxml builds native_swf/lib.swc with the Flex SDK's compc for -swf-lib
            return None if shutil.which("compc") else "compc (Flex SDK) is not installed, needed to build native_swf/lib.swc for -swf-lib; flash-no-swc covers the rest"
        if req in missing:
            return missing[req]
        if req == "hxjava":
            # compile-java-native.hxml: `haxelib run hxjava native_java/hxjava_build.txt --out native_java/native`
            log = GENERATED / "native-jar.log"
            code, _, _ = run(["haxelib", "run", "hxjava", "native_java/hxjava_build.txt", "--out", "native_java/native"], work, log, lib_env)
            if code != 0 or not (work / "native_java/native.jar").is_file():
                return f"building native_java/native.jar failed (exit {code}), see {log.relative_to(ROOT)}"
            return None
        return None

    jobs = []
    for t in targets:
        hxml, extra, req = TARGETS[t]
        if t in skipped:
            continue
        why = requirement(req)
        if why:
            skipped[t] = why
            continue
        for side in ("reference", "port"):
            out = f"out/{t}/{side}"
            hxml_name = f"unit-targets-{t}-{side}.hxml"
            (work / hxml_name).write_text(side_hxml(work, hxml, out))
            (work / out).mkdir(parents=True)
            cmd = ([reference] if side == "reference" else port_cmd) + ["-D", "disable-parallelism"] + extra + [hxml_name]
            jobs.append((t, side, cmd))

    def run_target(t, sides):
        """Runs the sides of a target in order (FIXED_OUTPUTS) or one side alone."""
        done = []
        for side, cmd in sides:
            result = run(cmd, work, GENERATED / f"{t}-{side}.log", env)
            for fixed in FIXED_OUTPUTS.get(t, []):
                if (work / fixed).exists():
                    shutil.move(str(work / fixed), str(work / "out" / t / side / pathlib.Path(fixed).name))
            done.append((side, result))
        return done

    groups = []
    for t, side, cmd in jobs:
        if t in FIXED_OUTPUTS and groups and groups[-1][0] == t:
            groups[-1][1].append((side, cmd))
        else:
            groups.append((t, [(side, cmd)]))
    for fixed in {pathlib.Path(f).parent for fs in FIXED_OUTPUTS.values() for f in fs}:
        (work / fixed).mkdir(parents=True, exist_ok=True)
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, opts.j)) as pool:
        futures = {pool.submit(run_target, t, sides): t for t, sides in groups}
        for f in concurrent.futures.as_completed(futures):
            t = futures[f]
            for side, result in f.result():
                results[(t, side)] = result
                code, start, end = result
                print(f"  {t:13} {side:9} exit {code!s:7} {end - start:7.1f}s", flush=True)

    passed, failed = [], []
    print()
    for t in targets:
        if t in skipped:
            print(f"SKIP  {t:13} {skipped[t]}")
            continue
        (rc, rs, re_), (pc, ps, pe) = results[(t, "reference")], results[(t, "port")]
        ref_log, port_log = GENERATED / f"{t}-reference.log", GENERATED / f"{t}-port.log"
        if rc != 0:
            failed.append(t)
            print(f"FAIL  {t:13} reference exit {rc} ({ref_log.relative_to(ROOT)})\n{last_lines(ref_log)}")
            continue
        if pc != 0:
            failed.append(t)
            print(f"FAIL  {t:13} port exit {pc} ({port_log.relative_to(ROOT)})\n{last_lines(port_log)}")
            continue
        window = (min(rs, ps), max(re_, pe))
        result = compare(work / "out" / t / "reference", work / "out" / t / "port", window)
        if result:
            failed.append(t)
            print(f"FAIL  {t:13} {result[0]}\n{result[1]}")
        else:
            n = len(files_of(work / "out" / t / "reference"))
            passed.append(t)
            print(f"PASS  {t:13} {n} files identical")
    print(f"\nunit-targets: {len(passed)} passed, {len(failed)} failed, {len(skipped)} skipped"
          + (f" (failed: {' '.join(failed)})" if failed else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
