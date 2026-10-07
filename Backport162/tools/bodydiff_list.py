import re,sys,bisect
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/'
PAT=re.compile(r'Chamois|ContinuousExpose|SBSystemShell|ExternalDisplay|NonInteractiveDisplay|SBDisplayManager|SBSceneHostingDisplay|SBWindowScene|SBLockedPointer|SBDisplayItem|SBDisplayArrangement|SBStage|SBMedusa|SBDeviceApplicationSceneHandle|SBAppLayout|StripView|SBFluidSwitcherViewController|SBFluidSwitcherItemContainer')
def load(p):
    L=[]
    for l in open(p,errors='replace'):
        m=re.match(r'(0x[0-9a-f]+):\s+\(__TEXT,__text\)\s+\S+\s+(\S.*?)\s*$',l)
        if m: L.append((int(m.group(1),16),m.group(2)))
    L.sort(); return L
def meths(L):
    d={}
    addrs=[a for a,_ in L]
    for i,(a,n) in enumerate(L):
        if n.startswith(('-[','+[','___')) and PAT.search(n) and 'cold' not in n:
            sz=(L[i+1][0]-a) if i+1<len(L) else 0
            d[n]=(a,sz)
    return d
a=meths(load(S+'sb_syms.txt')); b=meths(load(S+'sb162_syms.txt'))
com=[n for n in a if n in b]
print(len(a),len(b),len(com))
import json
json.dump({n:[a[n],b[n]] for n in com},open(S+'tp/common_meths.json','w'))
