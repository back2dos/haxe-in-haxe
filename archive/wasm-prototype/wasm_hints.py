#!/usr/bin/env python3
# EXPERIMENTAL: adds V8's experimental "compilationHints" custom section to a
# wasm module, marking every function body of at least THRESHOLD bytes as
# Liftoff-only, so V8 never spends tens of seconds optimizing it (see
# bench/WASM-BACKEND.md §4). Needs node --experimental-wasm-compilation-hints
# --no-wasm-dynamic-tiering (dynamic tiering ignores the hints).
#   wasm_hints.py in.wasm out.wasm [THRESHOLD=100000]
import sys

def leb(b, p):
    r = s = 0
    while True:
        x = b[p]; p += 1; r |= (x & 0x7F) << s; s += 7
        if x < 0x80: return r, p

def enc(n):
    o = bytearray()
    while True:
        x = n & 0x7F; n >>= 7
        if n: o.append(x | 0x80)
        else:
            o.append(x); return bytes(o)

src, dst = sys.argv[1], sys.argv[2]
threshold = int(sys.argv[3]) if len(sys.argv) > 3 else 100000
b = open(src, "rb").read()
p = 8
while True:  # find the code section
    sid = b[p]; size, q = leb(b, p + 1)
    if sid == 10: break
    p = q + size
code_start = p
n, p = leb(b, q)
hints = bytearray()
for _ in range(n):
    size, body = leb(b, p); p = body + size
    hints.append(0x14 if size >= threshold else 0)  # 0x14: top tier = baseline
name = b"compilationHints"
payload = enc(len(name)) + name + enc(n) + bytes(hints)
open(dst, "wb").write(b[:code_start] + bytes([0]) + enc(len(payload)) + payload + b[code_start:])
print(f"{n} functions, {sum(1 for h in hints if h)} marked Liftoff-only")
