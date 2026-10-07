import sys,pickle; sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/tp')
from bodydiff import *
cm=json.load(open(S+'tp/common_meths.json'))
s0=load_syms(S+'sb_syms.txt'); s2=load_syms(S+'sb162_syms.txt')
n0={a:re.sub(r'\.\d+$','',n) for a,n in s0.items()}; n2={a:re.sub(r'\.\d+$','',n) for a,n in s2.items()}
st0=pickle.load(open(S+'tp/selmap_160.pkl','rb'))[1]; st2=pickle.load(open(S+'tp/selmap_162.pkl','rb'))[1]
i0=dump(C0,s0); i2=dump(C2,s2)
def seq(ops,syms,st):
    o=[]
    for a,(op,args) in ops:
        if op in('bl','b'):
            t=int(re.search(r'0x[0-9a-f]+',args).group(0),16)
            o.append(op+' '+('msg:'+st[t] if t in st else syms.get(t,'X')))
        elif op in('nop','pacibsp','autibsp','retab','ret','brk') : continue
        elif op in('adrp','adr') : o.append(op)
        else:
            if re.search(r'\bsp\b',args) : continue   # frame layout noise
            o.append(op)
    return o
def consts(ops):
    o=[]
    for a,(op,args) in ops:
        if op in('bl','b','adrp','adr') or re.search(r'\bsp\b',args): continue
        a2=re.sub(r'\[[^\]]*\]','[]',args)
        o+=re.findall(r'#-?0x[0-9a-f]{1,6}\b|#-?\d+(?:\.\d+)?',a2)
    return o
out={}
for name,((a0,z0),(a2,z2)) in cm.items():
    o0=[(a,i0[a]) for a in range(a0,a0+z0,4) if a in i0]; o2=[(a,i2[a]) for a in range(a2,a2+z2,4) if a in i2]
    m0,m2=seq(o0,n0,st0),seq(o2,n2,st2)
    if m0==m2: out[name]=('same' if consts(o0)==consts(o2) else 'const',1.0,len(m0),len(m2))
    else: out[name]=('logic',round(difflib.SequenceMatcher(None,m0,m2,autojunk=False).ratio(),3),len(m0),len(m2))
json.dump(out,open(S+'tp/bodydiff3.json','w'))
import collections; print(collections.Counter(v[0] for v in out.values()))
