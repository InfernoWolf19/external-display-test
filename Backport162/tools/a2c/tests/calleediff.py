#!/usr/bin/env python3
"""calleediff.py a.gen.c [b.gen.c ...] : for every selector used by the lifted bodies compare the SpringBoard implementations of 16.0 and 16.2 (a2c canonical text, raw listing fallback)"""
import sys, re, subprocess
import mdiff
only=None
args=sys.argv[1:]
if '--only' in args:
    i=args.index('--only'); only=set(args[i+1].split(',')); args=args[:i]
sels=set()
for f in args:
    txt=open(f).read()
    m=re.search(r'_sels\[\] = \{(.*?)\};', txt)
    sels|=set(re.findall(r'"(.*?)"', m.group(1)))
if only: sels&=only
for sel in sorted(sels):
    pat=r'[-+]\[\w+(?:\(\w+\))? '+re.escape(sel)+r'\]$'
    hits=mdiff.find('162',pat)
    if not hits: print('EXTERNAL', sel); continue
    for a2,n in hits:
        m160=[x for x in mdiff.SYM['160'] if x[1]==n]
        if not m160: print('ONLY162', n[:120]); continue
        a0=m160[0][0]; e0=mdiff.span('160',a0); e2=mdiff.span('162',a2)
        cl=re.match(r'[-+]\[(\w+)',n).group(1)
        try:
            t0,_=mdiff.lift('160',a0,e0,cls=cl); t2,_=mdiff.lift('162',a2,e2,cls=cl)
            r='SAME' if mdiff.canon(t0)==mdiff.canon(t2) else 'DIFF'
        except Exception as ex:
            r='NOLIFT(%s)'%repr(ex)[:50]
        print(r, n[:130], (e0-a0)//4, (e2-a2)//4)
mdiff.a2c.save_memo()
