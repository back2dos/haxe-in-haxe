#!/usr/bin/env python3
"""Runs the upstream compiler test suite (haxe/tests) with the port.

The steps are those of upstream CI's target-independent "macro" job
(haxe/tests/runci/targets/Macro.hx), in the same order: the unit tests in the
macro context (and their HXB round trip), null safety, the misc projects,
eval resolution, the sys tests through HXB, compiler loops, connect_stdin,
threads and the third-party projects. Each step runs on a fresh copy of
haxe/tests in test/generated/upstream/<compiler>/ (the runners write build
output next to the tests) with a `haxe` on PATH that runs the chosen compiler,
so the runners' own nested `haxe` calls use it too.

  python3 test/upstream.py [--reference] [step ...]

--reference runs the pinned reference compiler instead, for the baseline.
The port is the HashLink build test/conformance.py makes
(test/generated/conformance/haxe-in-haxe.hl, from test/conformance.py; HAXE_IN_HAXE_PORT overrides the command).
Steps excluded on purpose are listed in SKIPPED with the reason.

Single misc projects that need a target generator the port does not have
(AGENTS.md: HXB only) are listed in MISC_EXCLUDED with the reason. The misc
runner (tests/misc/src/Main.hx) only runs project hxmls whose path matches the
MISC_TEST_FILTER define, so the "misc" step passes it a negative lookahead
over the excluded paths (for both compilers, so the counts stay comparable).
The "misc-resolution" step uses the same runner and RESOLUTION_EXCLUDED.

utest is installed as upstream CI does (`haxelib git utest
https://github.com/haxe-utest/utest.git`): cloned into
test/generated/upstream/libs/utest (at UTEST_COMMIT) and registered in a local
haxelib repo (test/generated/upstream/.haxelib), which haxelib finds from the
step directories below it. haxeserver (`haxelibInstallGit("Simn", "haxeserver")`)
is registered the same way, at HAXESERVER_COMMIT.

The third-party projects (Macro.hx `party`) are cloned at the commits pinned
in PARTY into test/generated/upstream/party/<name>, once, and run in place
(they are not copied per compiler; hxcoro's tests/bin is removed before its
first step). Each has its own local haxelib repo, as upstream. tink_core's
test dependencies (`haxelib install tests.hxml --always` upstream) are the
pinned releases of TINK_CORE_LIBS: haxelib's own download of lib.haxe.org
files fails behind this environment's proxy (the 302 to
haxelib-files.haxe.org yields an empty download), so the zips are fetched with
curl and installed with `haxelib install <zip>`, dependencies first. hxcoro's
`haxelib git utest` is the shared utest clone, registered with `haxelib dev`.
"""
import os, pathlib, re, shlex, shutil, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parent.parent
HAXE = ROOT / "haxe"
GENERATED = ROOT / "test" / "generated" / "upstream"

# (name, directory under tests/, command): Macro.hx `runCommand`s
STEPS = [
    ("unit-macro", "unit", ["haxe", "compile-macro.hxml", "--hxb", "bin/hxb/eval.zip"]),
    ("unit-macro-hxblib", "unit", ["haxe", "compile-macro.hxml", "--hxb-lib", "bin/hxb/eval.zip"]),
    ("nullsafety", "nullsafety", ["haxe", "test.hxml"]),
    ("misc", "misc", ["haxe", "compile.hxml"]),
    ("misc-resolution", "misc", ["haxe", "run-base.hxml", "--run", "Main", "eval/resolution"]),
    ("sys-hxb", "sys", ["haxe", "compile-eval-hxb.hxml"]),
    ("sys-run", "sys", ["haxe", "--hxb-lib", "bin/eval/sys.hxb", "--run", "Main"]),
    ("compiler-loops", "misc", ["haxe", "run-base.hxml", "-D", "timeout=3", "--run", "Main", "eval/compiler_loops"]),
    ("connect-stdin", "misc/eval/connect_stdin", ["haxe", "run.hxml"]),
    ("threads", "threads", ["haxe", "build.hxml", "--interp"]),
]

# Macro.hx party(): (name, project under party/, command); upstream clones the
# default branches (hxcoro: Config.hxcoroVersion = "master") at depth 1
PARTY_STEPS = [
    ("party-tink_core", "tink_core", ["haxe", "tests.hxml", "-w", "-WDeprecated", "--interp", "--macro", "addMetadata('@:exclude','Futures','testDelay')"]),
    ("party-hxcoro", "hxcoro", ["haxe", "--cwd", "tests", "build-eval.hxml"]),
    ("party-hxcoro-hxb", "hxcoro", ["haxe", "--cwd", "tests", "build-eval.hxml", "--hxb", "bin/test.hxb"]),
    ("party-hxcoro-hxblib", "hxcoro", ["haxe", "--cwd", "tests", "build-eval.hxml", "--hxb-lib", "bin/test.hxb"]),
]

# name -> (repository, pinned commit: the default branch when this was added)
PARTY = {
    "tink_core": ("https://github.com/haxetink/tink_core", "b6745a86244ada0e920ce4c52abae45a85707bb6"),
    "hxcoro": ("https://github.com/HaxeFoundation/hxcoro", "4b1a4d49542c578dc184297b75d125093ca444d2"),
}
UTEST_COMMIT = "a055e05e2e872ae12a32b53d0200612345059c38"
# Macro.hx `haxelibInstallGit("Simn", "haxeserver")` (for the display tests, which run in
# their own job; test/conformance-upstream-cases.txt compiles their runner)
HAXESERVER_COMMIT = "fad3af2a59a5b00e4abb3f0b4734b779dba90ba5"

# `haxelib install tests.hxml --always` in tink_core: the latest releases of
# tink_unittest and deep_equal and their dependencies when this was added,
# dependencies before dependents (tink_core itself is `haxelib dev tink_core .`)
TINK_CORE_LIBS = [
    ("ansi", "1.0.0"), ("tink_core", "2.1.1"), ("tink_priority", "0.1.4"), ("deep_equal", "0.4.0"),
    ("tink_macro", "1.0.4"), ("tink_streams", "0.4.0"), ("tink_syntaxhub", "0.6.1"),
    ("tink_testrunner", "0.9.0"), ("tink_unittest", "0.8.0"),
]

SKIPPED = {
    "sourcemaps": "JS source maps (run.hxml compiles with --js): a target generator",
    "nullsafety-js-es6": "test-js-es6.hxml compiles with --js",
    "display": "Macro.hx only installs haxeserver here; display tests run in their own job",
}


# misc project hxml (path as the misc runner prints it) -> reason
MISC_EXCLUDED = {
    "projects/HxbWildcardExclude/compile.hxml": "step 1 compiles with -js next to --hxb (the archive itself is written)",
    "projects/Issue4660/compile.hxml": "Test.hx runs `haxe -js out.js` and checks the generated JavaScript",
}


# eval/resolution project hxml -> reason
RESOLUTION_EXCLUDED = {
    "projects/Issue9367/compile.hxml": "compiles with -js and runs `node test.js`",
    "projects/modulestatics/compile.hxml": "compiles with -js and runs `node test.js`",
    "projects/spec/compile.hxml": "compiles with -js and runs `node test.js`",
}

# step -> [(file under the step directory, text removed from it, reason)]:
# commands of an hxml that need a target generator the port does not have,
# removed for both compilers when the rest of the step does not depend on them
NEKO_EXITCODE = (
    "compile-each.hxml", "--cmd haxe compile-neko-exitcode.hxml\n--next\n",
    "builds bin/neko/ExitCode.n with -neko and nekotools; ExitCode.getNative only copies it on Windows (gcc builds bin/ExitCode elsewhere)",
)
# sys-run: TestCommandBase.testCommand runs `haxe compile-each.hxml --run TestArguments`
STEP_PATCHES = {"sys-hxb": [NEKO_EXITCODE], "sys-run": [NEKO_EXITCODE]}

# step -> excluded runner projects
STEP_EXCLUDED = {"misc": MISC_EXCLUDED, "misc-resolution": RESOLUTION_EXCLUDED}


def misc_filter_args(excluded: dict = MISC_EXCLUDED) -> list:
    if not excluded:
        return []
    alternatives = "|".join(re.escape(path) for path in sorted(excluded))
    return ["-D", "MISC_TEST_FILTER=^(?!(?:" + alternatives + ")$)"]


def wrapper(bin_dir: pathlib.Path, reference: bool) -> None:
    bin_dir.mkdir(parents=True, exist_ok=True)
    if reference:
        cmd = shlex.quote(str(HAXE / "haxe"))
    else:
        port = os.environ.get("HAXE_IN_HAXE_PORT")
        if port:
            cmd = port
        else:
            hl = os.environ.get("HAXE_HL") or shutil.which("hl")
            cmd = shlex.quote(hl) + " " + shlex.quote(str(ROOT / "test" / "generated" / "conformance" / "haxe-in-haxe.hl"))
    (bin_dir / "haxe").write_text("#!/bin/sh\nexec " + cmd + ' "$@"\n')
    (bin_dir / "haxe").chmod(0o755)


def clone(url: str, commit: str, target: pathlib.Path) -> None:
    """A depth-1 clone of `url` at `commit` (GitHub serves commits by hash)."""
    if target.exists():
        return
    tmp = target.with_name(target.name + ".tmp")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)
    for cmd in (["git", "init", "-q"], ["git", "fetch", "-q", "--depth", "1", url, commit], ["git", "checkout", "-q", "FETCH_HEAD"]):
        subprocess.run(cmd, cwd=tmp, check=True)
    tmp.rename(target)


def haxelib(cwd: pathlib.Path, *args: str) -> None:
    subprocess.run(["haxelib", *args], cwd=cwd, check=True, stdout=subprocess.DEVNULL)


def setup_party() -> None:
    party = GENERATED / "party"
    for name, (url, commit) in PARTY.items():
        project = party / name
        if (project / ".haxelib").exists():
            continue
        clone(url, commit, project)
        haxelib(project, "newrepo")
        if name == "tink_core":
            downloads = party / "downloads"
            downloads.mkdir(exist_ok=True)
            for lib, version in TINK_CORE_LIBS:
                zip_path = downloads / f"{lib}-{version}.zip"
                if not zip_path.exists():
                    url = f"https://haxelib-files.haxe.org/files/3.0/{lib}-{version.replace('.', ',')}.zip"
                    subprocess.run(["curl", "-sSLf", "-o", str(zip_path), url], check=True)
                haxelib(project, "install", str(zip_path), "--always")
            haxelib(project, "dev", "tink_core", ".")
        else:
            haxelib(project, "dev", "utest", str(GENERATED / "libs" / "utest"))
            haxelib(project, "dev", "hxcoro", ".")


def setup_libs() -> None:
    utest = GENERATED / "libs" / "utest"
    if not utest.exists():
        clone("https://github.com/haxe-utest/utest.git", UTEST_COMMIT, utest)
    haxeserver = GENERATED / "libs" / "haxeserver"
    if not haxeserver.exists():
        clone("https://github.com/Simn/haxeserver", HAXESERVER_COMMIT, haxeserver)
    if not (GENERATED / ".haxelib").exists():
        subprocess.run(["haxelib", "newrepo"], cwd=GENERATED, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["haxelib", "dev", "utest", str(utest)], cwd=GENERATED, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["haxelib", "dev", "haxeserver", str(haxeserver)], cwd=GENERATED, check=True, stdout=subprocess.DEVNULL)


def main() -> None:
    args = sys.argv[1:]
    reference = "--reference" in args
    names = [a for a in args if not a.startswith("--")]
    label = "reference" if reference else "port"
    GENERATED.mkdir(parents=True, exist_ok=True)
    setup_libs()
    base = GENERATED / label
    bin_dir = base / "bin"
    wrapper(bin_dir, reference)
    env = dict(os.environ)
    env["PATH"] = str(bin_dir) + os.pathsep + env["PATH"]
    env["HAXE_STD_PATH"] = str(HAXE / "std")
    results = []

    def record(name, cmd, cwd, step_env):
        log = base / (name + ".log")
        start = time.time()
        with open(log, "w") as out:
            try:
                code = subprocess.run(cmd, cwd=cwd, env=step_env, stdout=out, stderr=subprocess.STDOUT, timeout=3600).returncode
            except subprocess.TimeoutExpired:
                code = "timeout"
        results.append((name, code, time.time() - start))
        print(f"{'PASS' if code == 0 else 'FAIL':5} {name:20} exit {code!s:8} {time.time() - start:7.1f}s  {log.relative_to(ROOT)}", flush=True)

    for name, sub, cmd in STEPS:
        if names and not any(n in name for n in names):
            continue
        work = base / name
        if work.exists():
            shutil.rmtree(work)
        shutil.copytree(HAXE / "tests", work / "tests", symlinks=True)
        # paths relative to the tests (../../std, ../../extra) resolve as in haxe/
        os.symlink(HAXE / "std", work / "std")
        os.symlink(HAXE / "extra", work / "extra")
        # sys-run uses the archive of sys-hxb
        if name == "sys-run" and (base / "sys-hxb" / "tests" / "sys" / "bin").exists():
            shutil.copytree(base / "sys-hxb" / "tests" / "sys" / "bin", work / "tests" / "sys" / "bin", dirs_exist_ok=True)
        if name == "unit-macro-hxblib" and (base / "unit-macro" / "tests" / "unit" / "bin").exists():
            shutil.copytree(base / "unit-macro" / "tests" / "unit" / "bin", work / "tests" / "unit" / "bin", dirs_exist_ok=True)
        for file, text, _ in STEP_PATCHES.get(name, []):
            target = work / "tests" / sub / file
            content = target.read_text()
            assert text in content, (name, file)
            target.write_text(content.replace(text, "", 1))
        # runci System.runSysTest exports EXISTS=1 for the sys tests
        step_env = dict(env, EXISTS="1") if name == "sys-run" else env
        if name in STEP_EXCLUDED:
            # the defines must precede the hxml: arguments after its --run go to the runner
            cmd = cmd[:1] + misc_filter_args(STEP_EXCLUDED[name]) + cmd[1:]
        record(name, cmd, work / "tests" / sub, step_env)
    party_steps = [p for p in PARTY_STEPS if not names or any(n in p[0] for n in names)]
    if party_steps:
        setup_party()
        hxcoro_bin = GENERATED / "party" / "hxcoro" / "tests" / "bin"
        if hxcoro_bin.exists():
            shutil.rmtree(hxcoro_bin)
    for name, project, cmd in party_steps:
        record(name, cmd, GENERATED / "party" / project, env)
    for name, why in SKIPPED.items():
        if not names or any(n in name for n in names):
            print(f"SKIP  {name:20} {why}")
    for step, patches in STEP_PATCHES.items():
        if not names or any(n in step for n in names):
            for file, text, why in patches:
                print(f"SKIP  {step} {file}: {text.splitlines()[0]}: {why}")
    for step, excluded in STEP_EXCLUDED.items():
        if not names or any(n in step for n in names):
            for path, why in excluded.items():
                print(f"SKIP  {step} {path}: {why}")
    failed = [r for r in results if r[1] != 0]
    print(f"{label}: {len(results) - len(failed)}/{len(results)} steps passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
