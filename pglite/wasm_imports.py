# Prints the symbols a wasm side module needs from the main module: its env function imports and
# the GOT.mem/GOT.func entries it does not define (export) itself. Usage: wasm_imports.py <module.wasm>
import sys
data = open(sys.argv[1], 'rb').read()
def leb(d, i):
    r = s = 0
    while True:
        b = d[i]; i += 1; r |= (b & 0x7f) << s; s += 7
        if b < 0x80: return r, i
def limits(d, j):
    flags = d[j]; j += 1
    _, j = leb(d, j)
    if flags & 1: _, j = leb(d, j)
    return j
i = 8; got = set(); exports = set(); funcs = set()
while i < len(data):
    sid = data[i]; i += 1; size, i = leb(data, i); end = i + size
    if sid == 2:
        n, j = leb(data, i)
        for _ in range(n):
            l, j = leb(data, j); mod = data[j:j+l].decode(); j += l
            l, j = leb(data, j); name = data[j:j+l].decode(); j += l
            kind = data[j]; j += 1
            if kind == 0: _, j = leb(data, j)
            elif kind == 1: j += 1; j = limits(data, j)
            elif kind == 2: j = limits(data, j)
            elif kind == 3: j += 2
            elif kind == 4: j += 1; _, j = leb(data, j)
            if mod in ('GOT.mem', 'GOT.func'): got.add(name)
            elif mod == 'env' and kind == 0: funcs.add(name)
    elif sid == 7:
        n, j = leb(data, i)
        for _ in range(n):
            l, j = leb(data, j); name = data[j:j+l].decode(); j += l
            j += 1; _, j = leb(data, j)
            exports.add(name)
    i = end
out = (got - exports) | funcs
print('\n'.join(sorted(out)))
