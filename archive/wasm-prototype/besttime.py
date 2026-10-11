#!/usr/bin/env python3
# EXPERIMENTAL helper: best wall time of N runs and peak RSS of a command.
#   besttime.py N cmd args...   (prints "best_s rss_mb" and checks stdout is stable)
import os, resource, subprocess, sys, time
n = int(sys.argv[1]); cmd = sys.argv[2:]
best = None; out0 = None; rss = 0
for _ in range(n):
    t = time.perf_counter()
    p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    dt = time.perf_counter() - t
    if p.returncode != 0: sys.exit(f"exit {p.returncode}: {' '.join(cmd)}")
    if out0 is None: out0 = p.stdout
    elif p.stdout != out0: sys.exit("unstable output")
    best = dt if best is None else min(best, dt)
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024
print(f"{best:.3f}s {rss:.0f}MB out={out0.decode().split()}")
