#!/usr/bin/env python3
"""Checks that the changes to Haxe files since a git revision only touch comments
and whitespace: every changed .hx file must have the same tokens, with comments
removed, as at the revision.

    python3 tools/comment-only-diff.py [REV]      (default: HEAD)

Exits 1 and names the files whose code changed.
"""
import subprocess, sys


def strip(src):
    """The source without comments, as a list of code tokens (whitespace dropped)."""
    out, i, n = [], 0, len(src)
    tok = []

    def flush():
        if tok:
            out.append("".join(tok))
            tok.clear()

    while i < n:
        c = src[i]
        if src.startswith("//", i):
            flush()
            while i < n and src[i] != "\n":
                i += 1
        elif src.startswith("/*", i):
            flush()
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
        elif c in "\"'":
            # a string literal, kept whole (escapes skipped)
            flush()
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif c == "~" and src.startswith("~/", i):
            # a regex literal ~/.../flags
            flush()
            j = i + 2
            while j < n and src[j] != "/":
                j += 2 if src[j] == "\\" else 1
            j += 1
            while j < n and src[j].isalpha():
                j += 1
            out.append(src[i:j])
            i = j
        elif c.isspace():
            flush()
            i += 1
        else:
            tok.append(c)
            i += 1
    flush()
    return out


def main():
    rev = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    files = subprocess.run(["git", "diff", "--name-only", "--diff-filter=M", rev, "--", "*.hx"], stdout=subprocess.PIPE, text=True, check=True).stdout.split()
    bad = []
    for f in files:
        old = subprocess.run(["git", "show", f"{rev}:{f}"], stdout=subprocess.PIPE, text=True, check=True).stdout
        new = open(f, encoding="utf-8").read()
        if strip(old) != strip(new):
            bad.append(f)
    added = subprocess.run(["git", "diff", "--name-only", "--diff-filter=ADR", rev, "--", "*.hx"], stdout=subprocess.PIPE, text=True, check=True).stdout.split()
    for f in added:
        bad.append(f + " (added, removed or renamed)")
    if bad:
        print("code changed in:\n  " + "\n  ".join(bad))
        sys.exit(1)
    print(f"{len(files)} files changed, comments and whitespace only")


if __name__ == "__main__":
    main()
