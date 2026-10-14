#!/usr/bin/env python3
"""Compares two HXB archives member by member (the port's self-compile check,
hxmc/tools/portcheck.sh and the CI workflow .github/workflows/hxmc.yml).

    python3 hxmc/tools/hxbcmp.py <a.hxb> <b.hxb> [--roots <root a> <root b>]

Without --roots the uncompressed .hxb payloads must be byte-identical. With
--roots, archives written in different directories (and on Windows, whose
absolute paths the port takes from the system: D:\\x\\src\\...) are compared
with each root replaced by one placeholder, and the separators after it by
"/", in the strings of each module's string pool (the STR chunk), which is
where file names are; everything else must be identical.
"""
import argparse, struct, sys, zipfile


def uleb(b, i):
    v = s = 0
    while True:
        c = b[i]
        i += 1
        v |= (c & 0x7F) << s
        s += 7
        if c < 0x80:
            return v, i


def wuleb(v):
    out = bytearray()
    while True:
        c = v & 0x7F
        v >>= 7
        if v:
            out.append(c | 0x80)
        else:
            out.append(c)
            return bytes(out)


def normalize(b, root):
    if not root:
        return b
    root = root.encode()
    alt = root.replace(b"\\", b"/")
    out = bytearray(b[:4])  # "hxb" + version
    i = 4
    while i < len(b):
        kind = b[i:i + 3]
        (n,) = struct.unpack_from("<i", b, i + 3)
        data = b[i + 7:i + 7 + n]
        i += 7 + n
        if kind == b"STR":
            cnt, j = uleb(data, 0)
            nd = bytearray(wuleb(cnt))
            for _ in range(cnt):
                l, j = uleb(data, j)
                s = data[j:j + l]
                j += l
                for r in (root, alt):
                    if s.startswith(r):
                        s = b"<ROOT>" + s[len(r):].replace(b"\\", b"/")
                        break
                nd += wuleb(len(s)) + s
            data = bytes(nd)
        out += kind + struct.pack("<i", len(data)) + data
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--roots", nargs=2)
    x = ap.parse_args()
    ra, rb = x.roots or (None, None)
    a, b = zipfile.ZipFile(x.a), zipfile.ZipFile(x.b)
    na = sorted(n for n in a.namelist() if n.endswith(".hxb"))
    nb = sorted(n for n in b.namelist() if n.endswith(".hxb"))
    diff = [n for n in na if n in nb and normalize(a.read(n), ra) != normalize(b.read(n), rb)]
    print(f"{len(na)} modules, {'names equal' if na == nb else 'NAMES DIFFER'}, {len(diff)} differ" + (" (roots normalized)" if ra else ""))
    for n in diff[:10]:
        print("  differs: " + n)
    for n in sorted(set(na) ^ set(nb))[:10]:
        print("  only in " + ("a" if n in na else "b") + ": " + n)
    sys.exit(0 if na == nb and not diff else 1)


if __name__ == "__main__":
    main()
