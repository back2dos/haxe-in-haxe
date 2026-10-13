#!/usr/bin/env python3
"""The hxmc iteration loop (hxmc/README.md): differential tests against hxc.

    python3 hxmc/tools/run.py [-j N] [-k] [--native-only] [case ...]

Every case is a program (hxmc/test/cases/<Name>.hx with class <Name>, or a
directory given as <dir>:<Main>). Its HXB archive is written once by the
reference compiler (cached, rewritten when a source is newer); the oracle is
the same archive compiled by hxc (bin/hxc-dev/tool, tcc), run once and its
output cached; then hxmc (bin/hxmc/hxmc) compiles the archive (development
build: native code + the C of the rest) and the output must be identical.
Prints per case the share of functions compiled natively.
"""
import argparse, concurrent.futures, os, re, subprocess, sys, time, resource
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "bin/hxmc-t"
HAXE = os.environ.get("HAXE", str(ROOT / "haxe/haxe"))
TOOL = ROOT / "bin/hxc-dev/tool"
HXMC = ROOT / "bin/hxmc/hxmc"
CASES = ROOT / "hxmc/test/cases"
ENV = dict(os.environ, HAXE_STD_PATH=str(ROOT / "haxe/std"))


def unlimited():
    resource.setrlimit(resource.RLIMIT_STACK, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))


def sh(cmd, cwd=ROOT, env=ENV, timeout=300):
    r = subprocess.run([str(c) for c in cmd], cwd=cwd, env=env, capture_output=True, preexec_fn=unlimited, timeout=timeout)
    return r.returncode, r.stdout.decode(errors="replace"), r.stderr.decode(errors="replace")


def newest(paths):
    t = 0
    for p in paths:
        for f in ([p] if p.is_file() else p.rglob("*.hx")):
            t = max(t, f.stat().st_mtime)
    return t


# programs of the repository used as cases: name -> (class path, main class)
SUITE = {
    "hxc-bench": ("hxc/test", "Bench"),
    "hxc-exc": ("hxc/test/exc", "Exc"),
    "hxc-regress": ("hxc/test/regress", "Regress"),
}


def case_list(names, fuzz):
    cases = []
    if not names:
        names = sorted(p.stem for p in CASES.glob("*.hx")) + sorted(SUITE)
    for n in names:
        if n in SUITE:
            cp, main = SUITE[n]
            cases.append((n, [ROOT / cp], main))
        elif ":" in n:
            d, main = n.split(":")
            cases.append((Path(d).name + "-" + main, [Path(d).resolve()], main))
        else:
            cases.append((n, [CASES], n))
    if fuzz:
        for d in sorted(Path(fuzz).iterdir()):
            if (d / "Main.hx").exists():
                cases.append(("fuzz-" + d.name, [d.resolve()], "Main"))
    return cases


def run_case(name, cps, main, args):
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    hxb = d / "prog.hxb.zip"
    src_t = newest([cp / (main.replace(".", "/") + ".hx") for cp in cps if (cp / (main.replace(".", "/") + ".hx")).exists()] or cps)
    t0 = time.perf_counter()
    if not hxb.exists() or hxb.stat().st_mtime < src_t:
        cmd = [HAXE] + sum([["-cp", c] for c in cps], []) + ["-cp", ROOT / "bin/hxc/std", "-main", main, "--custom-target", f"hxc={d}/x",
               "--hxb", hxb, "-D", "disable-parallelism", "--no-output"]
        code, o, e = sh(cmd)
        if code != 0:
            return name, "hxb-fail", (o + e)[-1500:], None
    # the oracle: hxc + tcc
    expected = d / "expected.txt"
    if not expected.exists() or expected.stat().st_mtime < hxb.stat().st_mtime:
        code, o, e = sh([TOOL, d / "c", "--hxb-lib", hxb, "-main", main, "--custom-target", "hxc", "-D", "disable-parallelism"])
        if code != 0:
            return name, "hxc-fail", (o + e)[-1500:], None
        code, o, e = sh(["sh", ROOT / "hxc/tools/cc-chunks.sh", d / "c_hxc", d / "c.bin"],
                        env=dict(ENV, CC="tcc", CFLAGS="-w -fno-strict-aliasing -DHXC_NO_SSL -DHXC_NO_UV", RT_DIR=str(ROOT / "hxc/rt")))
        if code != 0:
            return name, "hxc-cc-fail", (o + e)[-1500:], None
        code, o, e = sh([d / "c.bin"], cwd=d)
        expected.write_bytes((f"exit {code}\n" + o).encode())
    env = dict(ENV, HXMC_STATS="1")
    if args.hybrid:
        env.update(HXMC_HYBRID="1", HXMC_RT=str(ROOT / "bin/hxmc/rt-dev"), HXMC_RT_INCLUDE=str(ROOT / "hxc/rt"))
    code, o, e = sh([HXMC, d / "m", "--hxb-lib", hxb, "-main", main, "--custom-target", "hxc", "-D", "disable-parallelism"], env=env)
    m = re.search(r"(\d+)/(\d+) functions native", o)
    stats = (int(m.group(1)), int(m.group(2))) if m else None
    (d / "hxmc.log").write_text(o + e)
    if code != 0:
        return name, "hxmc-fail", (o + e)[-2000:], stats
    try:
        code, o, e = sh([d / "m"], cwd=d, timeout=60)
    except subprocess.TimeoutExpired:
        return name, "timeout", "", stats
    got = f"exit {code}\n" + o
    if got.encode() != expected.read_bytes():
        (d / "got.txt").write_bytes((got + e).encode())
        return name, "differs", f"diff {expected} {d / 'got.txt'}\n" + e[-800:], stats
    return name, "ok", f"{time.perf_counter() - t0:.1f}s", stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4)
    ap.add_argument("-v", action="store_true", help="print the details of failures")
    ap.add_argument("--hybrid", action="store_true", help="development builds (C for what hxmc does not compile, the system's linker)")
    ap.add_argument("--fuzz", help="also every program of this directory (written by bin/fuzz/fuzz --emit)")
    ap.add_argument("cases", nargs="*")
    a = ap.parse_args()
    cases = case_list(a.cases, a.fuzz)
    t = time.perf_counter()
    nat = tot = 0
    bad = 0
    with concurrent.futures.ThreadPoolExecutor(a.j) as ex:
        for name, status, detail, stats in ex.map(lambda c: run_case(*c, a), cases):
            s = f"{stats[0]}/{stats[1]} native" if stats else ""
            if stats:
                nat += stats[0]
                tot += stats[1]
            print(f"{name:24} {status:12} {s:18} {detail if status == 'ok' or not a.v else ''}")
            if status != "ok":
                bad += 1
                if a.v:
                    print("    " + detail.replace("\n", "\n    "))
    pct = f"{100 * nat / tot:.1f}%" if tot else "-"
    print(f"{len(cases) - bad}/{len(cases)} ok, {nat}/{tot} functions native ({pct}), {time.perf_counter() - t:.1f}s")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
