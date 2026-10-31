import pickle,sys
from dag import *
hb=int(sys.argv[1])
d0,r0=make('varleaves_160_%d.pkl'%hb); d2,r2=make('varleaves_162_%d.pkl'%hb)
lv2=pickle.load(open('varleaves_162_%d.pkl'%hb,'rb'))
diff=0; tot=0
regions={}
for a,r in lv2:
    tot+=1
    s=evalset(d0,r0,a)
    if s!={r}:
        diff+=1
        regions.setdefault((r,tuple(sorted(s))),[]).append(a)
print('hb',hb,'162 leaves',tot,'with differing 160 result',diff)
for (r,s),lst in sorted(regions.items()):
    print(' 162 ->',r,' 160 ->',s,' leaves:',len(lst))
    # show minimal common conditions of first leaf
    if len(lst)<=3:
        for a in lst: print('    ',' '.join(('' if v else '!')+fmtkey(k) for k,v in a.items()))
print()
for (r,s),lst in sorted(regions.items()):
    common=None
    for a in lst:
        items=set(a.items())
        common=items if common is None else common&items
    print(' 162 ->',r,' 160 ->',s,' common conditions:',' '.join(('' if v else '!')+fmtkey(k) for k,v in sorted(common,key=lambda kv:str(kv[0]))))
