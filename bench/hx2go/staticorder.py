"""Static pass over Hx_Boot: a StaticInit must run after the StaticInits of the
static variables its initializers read (directly or through Hx_Init_* helpers)."""
import re, glob
src = {f: open(f).read() for f in glob.glob('*.go')}
funcs = {}
for s in src.values():
    for m in re.finditer(r'^func (\w+)\(.*?^}', s, re.S | re.M):
        funcs[m.group(1)] = m.group(0)
init_of = {}
for name, body in funcs.items():
    if name.startswith('Hx_StaticInit_'):
        for v in re.findall(r'^\s*(Hx_Field_\w+) = ', body, re.M):
            init_of.setdefault(v, name)
def reads(name, seen):
    if name in seen: return set()
    seen.add(name); body = funcs.get(name, ''); out = set(re.findall(r'\bHx_Field_\w+', body))
    # follow calls into other generated functions (static initializers often
    # call ordinary static functions)
    for h in set(re.findall(r'\b(Hx_(?:Init|Field)_\w+)\(', body)):
        if h in funcs: out |= reads(h, seen)
    return out
deps = {}
for name in funcs:
    if name.startswith('Hx_StaticInit_'):
        deps[name] = {init_of[v] for v in reads(name, set()) if v in init_of and init_of[v] != name}
main = open('Main.go').read()
order = re.findall(r'^    (Hx_StaticInit_\w+)\(\)$', main, re.M)
moves = 0
for it in range(2000):
    changed = False
    for i, a in enumerate(order):
        later = [b for b in deps.get(a, ()) if b in order and order.index(b) > i]
        if later:
            for b in later: order.remove(b)
            i = order.index(a)
            for b in later: order.insert(i, b)
            moves += len(later); changed = True; break
    if not changed: break
print('static order moves:', moves, 'converged' if not changed else 'NOT converged')
body = ''.join('    %s()\n' % n for n in order)
first = main.index('    ' + re.findall(r'^    (Hx_StaticInit_\w+)\(\)$', main, re.M)[0])
rest = re.sub(r'^    Hx_StaticInit_\w+\(\)\n', '', main[first:], flags=re.M)
open('Main.go', 'w').write(main[:first] + body + rest)
