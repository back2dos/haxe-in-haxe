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
(test/generated/haxe-in-haxe.hl; HAXE_IN_HAXE_PORT overrides the command).
Steps excluded on purpose are listed in SKIPPED with the reason.

utest is installed as upstream CI does (`haxelib git utest
https://github.com/haxe-utest/utest.git`): cloned into
test/generated/upstream/libs/utest and registered in a local haxelib repo
(test/generated/upstream/.haxelib), which haxelib finds from the step
directories below it.
"""
import os, pathlib, shlex, shutil, subprocess, sys, time

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

SKIPPED = {
    "sourcemaps": "JS source maps (run.hxml compiles with --js): a target generator",
    "nullsafety-js-es6": "test-js-es6.hxml compiles with --js",
    "display": "Macro.hx only installs haxeserver here; display tests run in their own job",
    "party": "tink_core and hxcoro are cloned from GitHub; run separately",
}


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
            cmd = shlex.quote(hl) + " " + shlex.quote(str(ROOT / "test" / "generated" / "haxe-in-haxe.hl"))
    (bin_dir / "haxe").write_text("#!/bin/sh\nexec " + cmd + ' "$@"\n')
    (bin_dir / "haxe").chmod(0o755)


def setup_libs() -> None:
    utest = GENERATED / "libs" / "utest"
    if not utest.exists():
        subprocess.run(["git", "clone", "-q", "--depth", "1", "https://github.com/haxe-utest/utest.git", str(utest)], check=True)
    if not (GENERATED / ".haxelib").exists():
        subprocess.run(["haxelib", "newrepo"], cwd=GENERATED, check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["haxelib", "dev", "utest", str(utest)], cwd=GENERATED, check=True, stdout=subprocess.DEVNULL)


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
        log = base / (name + ".log")
        start = time.time()
        with open(log, "w") as out:
            try:
                code = subprocess.run(cmd, cwd=work / "tests" / sub, env=env, stdout=out, stderr=subprocess.STDOUT, timeout=3600).returncode
            except subprocess.TimeoutExpired:
                code = "timeout"
        results.append((name, code, time.time() - start))
        print(f"{'PASS' if code == 0 else 'FAIL':5} {name:20} exit {code!s:8} {time.time() - start:7.1f}s  {log.relative_to(ROOT)}", flush=True)
    for name, why in SKIPPED.items():
        if not names or any(n in name for n in names):
            print(f"SKIP  {name:20} {why}")
    failed = [r for r in results if r[1] != 0]
    print(f"{label}: {len(results) - len(failed)}/{len(results)} steps passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
