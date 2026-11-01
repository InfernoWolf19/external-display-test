#!/usr/bin/env python3
"""kindcheck.py file.gen.c : compares the return kind a2c chose for every message send with the return type in the ObjC dumps (16.2 SpringBoard, UIKitCore, FrontBoard...)"""
import re, sys, glob, os
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/'
ret={}
for fn in [S+'sb162_objc.txt', S+'UIKitCore162.txt']+[f for f in glob.glob(S+'*162*.txt') if f.endswith('162.txt') and 'objc' not in f]:
    if not os.path.exists(fn): continue
    for l in open(fn, errors='replace'):
        if l.startswith('- (') or l.startswith('+ ('):
            d=0; k=2
            while k < len(l):
                if l[k]=='(': d+=1
                elif l[k]==')':
                    d-=1
                    if d==0: break
                k+=1
            rtype=l[3:k]
            rest=l[k+1:]
            for _ in range(4): rest=re.sub(r'\{[^{}]*\}', '', rest)
            b2=re.sub(r'\((?:[^()]|\([^()]*\))*\)', '', rest.split(';')[0])
            parts=re.findall(r'(\w+):', b2)
            sel=(':'.join(parts)+':') if parts else (b2.split()[0] if b2.split() else None)
            if sel: ret.setdefault(sel,set()).add(rtype)
def kind_of(t):
    t=t.strip()
    if t.startswith('struct CGRect'): return 'rect'
    if t.startswith('struct CGSize'): return 'size'
    if t in ('double','CGFloat'): return 'd'
    if t=='void': return 'v'
    if t.startswith('struct'): return 'STRUCT '+t[:50]
    return 'x'
txt=open(sys.argv[1]).read()
m=re.search(r'_sels\[\] = \{(.*?)\};', txt); sels=re.findall(r'"(.*?)"', m.group(1))
cn=re.search(r'static const char \*const (\w+)_sels', txt).group(1)
bad=0
for mm in re.finditer(r'SEL\('+cn+r'_sels, (\d+)\);\n\s*CALLMSG\((\w+)\)', txt):
    sel=sels[int(mm.group(1))]; chosen=mm.group(2)
    types=ret.get(sel)
    if not types: print('  ?', sel[:70], chosen, '(no dump)'); continue
    ks={kind_of(t) for t in types}
    if chosen not in ks and not (chosen=='x' and ks=={'v'}) and not (chosen=='v'):
        bad+=1; print('MISMATCH', sel[:90], 'chosen', chosen, 'dump', types)
print('checked; mismatches', bad)
