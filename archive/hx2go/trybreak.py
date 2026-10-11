"""hx2go translates break/continue inside a try body (which becomes a Go
closure) as `hx_try_state = 2/3; return`, meaning "leave the closure and
break/continue the enclosing loop". When the loop is itself inside the
closure, that skips the rest of the try body. Rewrite those to a labeled
break/continue of the innermost enclosing loop."""
import re, glob
total = 0
for f in glob.glob('*.go'):
    s = open(f).read()
    if 'hx_try_state = ' not in s: continue
    stack = []  # (open_pos, line_text)
    i, n = 0, len(s)
    hits = []  # (pos, kind, loop_open_pos)
    while i < n:
        c = s[i]
        if c == '/' and s.startswith('//', i):
            i = s.find('\n', i); i = n if i < 0 else i; continue
        if c == '"':
            i += 1
            while i < n and s[i] != '"':
                i += 2 if s[i] == '\\' else 1
            i += 1; continue
        if c == '`':
            i = s.find('`', i + 1) + 1; continue
        if c == "'":
            i += 1
            while i < n and s[i] != "'":
                i += 2 if s[i] == '\\' else 1
            i += 1; continue
        if c == '{':
            ls = s.rfind('\n', 0, i) + 1
            stack.append((i, s[ls:i].strip()))
        elif c == '}':
            if stack: stack.pop()
        elif c == 'h' and s.startswith('hx_try_state = ', i):
            m = re.match(r'hx_try_state = ([23]); return', s[i:i + 40])
            if m:
                for pos, text in reversed(stack):
                    if re.match(r'for\b', text):
                        hits.append((i, m.group(0), m.group(1), pos)); break
                    if re.search(r'\bfunc\s*\(', text):
                        break
        i += 1
    if not hits: continue
    labels = {}
    for pos, old, kind, loop in hits:
        labels.setdefault(loop, 'hxLoop%d' % (len(labels) + total))
    # apply from the end so positions stay valid
    edits = [(pos, len(old), ('break ' if kind == '2' else 'continue ') + labels[loop]) for pos, old, kind, loop in hits]
    for loop, lab in labels.items():
        ls = s.rfind('\n', 0, loop) + 1
        edits.append((ls, 0, lab + ':\n'))
    for pos, ln, new in sorted(edits, key=lambda e: -e[0]):
        s = s[:pos] + new + s[pos + ln:]
    open(f, 'w').write(s)
    total += len(hits)
print('try-body break/continue rewritten:', total)
