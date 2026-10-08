"""hx2go emits `hx_try_state = 1; hx_try_return = EXPR; return` for a return
inside a try body. If EXPR throws and the try catches it, the state already
says "returned" and the function returns the zero value. Evaluate EXPR first."""
import glob
HEAD = 'hx_try_state = 1; hx_try_return = '
total = 0
def scan_to_end(s, i):
    depth = 0; n = len(s)
    while i < n:
        c = s[i]
        if c == '"':
            i += 1
            while s[i] != '"': i += 2 if s[i] == '\\' else 1
        elif c == '`':
            i = s.index('`', i + 1)
        elif c == "'":
            i += 1
            while s[i] != "'": i += 2 if s[i] == '\\' else 1
        elif c == '/' and s.startswith('//', i):
            i = s.index('\n', i) - 1
        elif c in '([{': depth += 1
        elif c in ')]}': depth -= 1
        elif depth == 0 and s.startswith('; return', i):
            return i
        i += 1
    raise ValueError('no end')
for f in glob.glob('*.go'):
    s = open(f).read()
    if HEAD not in s: continue
    out = []; pos = 0
    while True:
        j = s.find(HEAD, pos)
        if j < 0: out.append(s[pos:]); break
        k = scan_to_end(s, j + len(HEAD))
        expr = s[j + len(HEAD):k]
        out.append(s[pos:j]); out.append('hx_try_return = ' + expr + '; hx_try_state = 1')
        pos = k; total += 1
    open(f, 'w').write(''.join(out))
print('try returns reordered:', total)
