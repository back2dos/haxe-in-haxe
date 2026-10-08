"""Rebuild the hx2go output in the current directory and apply rule-based fixes
at the positions Go reports, until a build produces no fixable error."""
import re, subprocess, sys, collections

def build():
    p = subprocess.run(['go', 'build', '-gcflags=-e', '-o', '../hih-go', '.'], capture_output=True, text=True)
    return p.returncode, p.stderr

def split_errors(log):
    errs = []
    for line in log.splitlines():
        m = re.match(r'\./(\S+\.go):(\d+):(\d+): (.*)', line)
        if m: errs.append([m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)])
        elif errs and line.startswith('\t'): errs[-1][3] += '\n' + line
    return errs

files = {}
def lines(f):
    if f not in files: files[f] = open(f).read().split('\n')
    return files[f]

def replace_at(f, ln, col, old, new):
    L = lines(f); s = L[ln-1]; i = col - 1
    if s[i:i+len(old)] != old:
        j = s.find(old)
        if j < 0 or s.count(old) != 1: return False
        i = j
    L[ln-1] = s[:i] + new + s[i+len(old):]
    return True

def fix(errs):
    n = 0
    # apply right-to-left within a line so columns stay valid
    for f, ln, col, msg in sorted(errs, key=lambda e: (e[0], e[1], -e[2])):
        first = msg.split('\n')[0]
        if first in ('break is not in a loop, switch, or select',):
            n += replace_at(f, ln, col, 'break', '{}')
        elif first == 'continue is not in a loop':
            n += replace_at(f, ln, col, 'continue', '{}')
        elif first == 'missing return':
            L = lines(f); L.insert(ln-1, '\tpanic("unreachable")'); n += 1
            # later errors in this file on following lines shift; stop after one per file
            return n
        else:
            m = re.match(r'cannot use (.*) \((?:variable|value) of (?:interface |pointer |struct )?type (HxArray\[[^\n]*?\])\) as HxArray\[any\] value', first)
            if m and not m.group(2) == 'HxArray[any]':
                n += replace_at(f, ln, col, m.group(1), '(' + m.group(1) + ').Dyn()'); continue
            m = re.match(r'cannot use (.*) \((?:variable|value) of (?:interface )?type HxArray\[any\]\) as (HxArray\[(.*)\]) value', first)
            if m:
                n += replace_at(f, ln, col, m.group(1), 'HxMakeArrayView[' + m.group(3) + '](' + m.group(1) + ')'); continue
            m = re.match(r'cannot use (.*) \((?:variable|value) of (?:interface )?type any\) as (\S+) value in .*(?:need type assertion|does not implement)', first)
            if m:
                n += replace_at(f, ln, col, m.group(1), '(' + m.group(1) + ').(' + m.group(2) + ')'); continue
    return n

for it in range(40):
    files.clear()
    code, log = build()
    if code == 0: print('BUILD OK'); sys.exit(0)
    errs = split_errors(log)
    n = fix(errs)
    for f, L in files.items(): open(f, 'w').write('\n'.join(L))
    print(f'iteration {it}: {len(errs)} errors, {n} fixed', flush=True)
    if n == 0:
        open('../build.log', 'w').write(log); break
