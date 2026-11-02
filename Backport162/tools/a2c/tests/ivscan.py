import sys, re, os
os.environ['A2C_INSPECT']='1'
import mdiff
cls=sys.argv[1]; ivs=set(sys.argv[2].split(','))
for a,n in mdiff.SYM['162']:
    if not re.match(r'[-+]\[%s(\(\w+\))? '%re.escape(cls), n): continue
    e=mdiff.span('162',a)
    try:
        t,w=mdiff.lift('162',a,e,cls=cls)
    except Exception as ex:
        print('ERR',n[:90],repr(ex)[:60]); continue
    m=re.search(r'_ivs\[\] = \{(.*?)\};',t)
    used=set(re.findall(r'"\w+\.(\w+)"',m.group(1))) if m else set()
    if used&ivs: print('USES',sorted(used&ivs),n[:110],(e-a)//4)
mdiff.a2c.save_memo()
