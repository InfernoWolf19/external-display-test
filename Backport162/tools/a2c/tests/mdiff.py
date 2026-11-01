#!/usr/bin/env python3
"""mdiff.py '<symbol substring or regex>' ... : lift every matching method of 16.0 and 16.2 with a2c and compare the canonical text
(addresses / labels removed; ivars, selectors, classes, symbols are already NAMES in the lifted text).  Prints SAME / DIFF per method."""
import sys, re, bisect, os
sys.dont_write_bytecode = True
sys.path.insert(0, '/tmp/claude-0/-home-user-external-display-test/y34work')
import a2c
S = a2c.S
def syms(fn):
    out = []
    for l in open(S + fn, errors='replace'):
        m = re.match(r'(0x[0-9a-f]+):\s+\(__TEXT,__text\)\s+\S+(?:\s+\(was a private external\))?\s+(\S.*?)\s*$', l)
        if m: out.append((int(m.group(1), 16), m.group(2)))
    out.sort(); return out
SYM = {'160': syms('sb_syms.txt'), '162': syms('sb162_syms.txt')}
def find(ver, pat):
    return [(a, n) for a, n in SYM[ver] if re.search(pat, n)]
def span(ver, a):
    ks = [x[0] for x in SYM[ver]]
    i = bisect.bisect_right(ks, a)
    return SYM[ver][i][0] if i < len(ks) else None
def lift(ver, a, e, sig='x,x', cls=None):
    L = a2c.Lift(ver, a, e, 'm', sig, 'x', {}, cls)
    head, fn = L.generate()
    txt = head + '\n' + fn
    return txt, L.stats['warn']
def canon(txt):
    lines = []
    lab = {}
    for l in txt.splitlines():
        l = re.sub(r'/\*.*?\*/', '', l).rstrip()
        if not l.strip() or l.startswith('#define') or l.startswith('/*'): continue
        lines.append(l)
    out = []
    for l in lines:
        l = re.sub(r'\bL[0-9a-f]{6,}\b', lambda m: 'L', l)
        l = re.sub(r'(X\[\d+\] = )0x1[0-9a-f]{8}ull;', r'\1ADRP;', l)
        l = re.sub(r'\bm_(sels|cls|ivs|fns|strs)\b', r'\1', l)
        out.append(l)
    return out
if __name__ == '__main__':
    for pat in sys.argv[1:]:
        for a0, n0 in find('160', pat):
            nn = re.sub(r'^-\[|^\+\[', lambda m: m.group(0), n0)
            m162 = [(a, n) for a, n in SYM['162'] if n == n0]
            if not m162: print('ONLY160', n0); continue
            a2, n2 = m162[0]
            e0, e2 = span('160', a0), span('162', a2)
            try:
                cl = re.match(r'[-+]\[(\w+)', n0).group(1); t0, w0 = lift('160', a0, e0, cls=cl); t2, w2 = lift('162', a2, e2, cls=cl)
            except Exception as ex:
                print('ERR ', n0, repr(ex)[:120]); continue
            c0, c2 = canon(t0), canon(t2)
            print('SAME' if c0 == c2 else 'DIFF', n0, '(%d / %d insns)' % ((e0 - a0) // 4, (e2 - a2) // 4))
        for a2, n2 in find('162', pat):
            if not any(n == n2 for a, n in SYM['160']): print('ONLY162', n2, hex(a2), '(%d insns)' % ((span('162', a2) - a2) // 4))
        a2c.save_memo()
