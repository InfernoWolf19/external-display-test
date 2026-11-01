#!/usr/bin/env python3
"""selcheck.py file.gen.c : selectors / classes / functions used by a lifted body that no 16.0 ObjC dump (SpringBoard, UIKitCore, other *160* dumps) defines"""
import re, sys, glob, os
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/'
defs=set(); classes=set()
files=[S+'sb160n_objc.txt', S+'UIKitCore160n.txt']+[f for f in glob.glob(S+'*160*.txt') if 'objc' in f.lower() or f.endswith('160n.txt')]
for fn in dict.fromkeys(files):
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
            rest=l[k+1:]
            for _ in range(4): rest=re.sub(r'\{[^{}]*\}', '', rest)
            body=rest.split(';')[0].strip()
            # remove (type) argument annotations
            b2=re.sub(r'\((?:[^()]|\([^()]*\))*\)', '', body)
            parts=re.findall(r'(\w+):', b2)
            if parts: defs.add(':'.join(parts)+':')
            elif b2.split(): defs.add(b2.split()[0])
        m=re.match(r'@interface (\w+)', l)
        if m: classes.add(m.group(1))
txt=open(sys.argv[1]).read()
m=re.search(r'_sels\[\] = \{(.*?)\};', txt)
sels=re.findall(r'"(.*?)"', m.group(1)) if m else []
miss=[x for x in sels if x not in defs]
print('selectors used', len(sels), 'not defined by any 16.0 dump:', miss)
m=re.search(r'_cls\[\] = \{(.*?)\};', txt)
cl=re.findall(r'"(.*?)"', m.group(1)) if m else []
print('classes not in the 16.0 dumps:', [c for c in cl if c not in classes])
