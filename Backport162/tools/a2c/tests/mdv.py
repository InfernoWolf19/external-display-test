import sys, re, difflib
sys.argv_save=sys.argv
import mdiff
name=sys.argv[1]
cl=re.match(r'[-+]\[(\w+)',name).group(1)
r={}
for ver in ('160','162'):
    m=[x for x in mdiff.SYM[ver] if x[1]==name]
    if not m: print('missing in',ver); sys.exit()
    a=m[0][0]; e=mdiff.span(ver,a)
    t,w=mdiff.lift(ver,a,e,cls=cl)
    r[ver]=mdiff.canon(t)
    if w: print('warn',ver,w)
body=lambda L:[l for l in L if not l.startswith('static const char *') or '[]' in l]
d=list(difflib.unified_diff(body(r['160']),body(r['162']),lineterm='',n=2))
print('\n'.join(d) if d else 'SAME')
