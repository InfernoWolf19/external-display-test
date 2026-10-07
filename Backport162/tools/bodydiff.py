import re,subprocess,json,sys,bisect,difflib,collections
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/'
IPSW=S+'bin/ipsw'
C0=S+'dsc/com.apple.dyld/dyld_shared_cache_arm64e'; C2=S+'dsc162/20C65__iPad13,4_5_6_7_8_9_10_11/dyld_shared_cache_arm64e'
def textrange(cache):
    out=subprocess.run([IPSW,'dsc','macho',cache,'SpringBoard','-l'],capture_output=True,text=True).stdout
    for l in out.splitlines():
        m=re.match(r'^\s+sz=0x[0-9a-f]+ off=\S+ addr=(0x[0-9a-f]+)-(0x[0-9a-f]+)\s+__TEXT\.__text\b',l)
        if m: return int(m.group(1),16),int(m.group(2),16)
def load_syms(p):
    d={}
    for l in open(p,errors='replace'):
        m=re.match(r'(0x[0-9a-f]+):\s+\([^)]*\)\s+\S+\s+(\S.*?)\s*$',l)
        if m: d[int(m.group(1),16)]=m.group(2)
    return d
def dump(cache,syms):
    lo,hi=textrange(cache)
    out=subprocess.run([IPSW,'dsc','disass',cache,'--vaddr',hex(lo),'--count',str((hi-lo)//4),'--quiet','--no-color'],capture_output=True,text=True).stdout
    ins={}
    for l in out.splitlines():
        m=re.match(r'^(0x[0-9a-f]+):\s+((?:[0-9a-f]{2} ){4})\s*(\S+)\s*(.*)$',l)
        if m: ins[int(m.group(1),16)]=(m.group(3),m.group(4).strip())
    return ins
def norm(ops,syms):
    # keep small immediates; map call targets to symbol names
    out=[]
    for a,(op,args) in ops:
        if op in('bl','b'):
            t=int(re.search(r'0x[0-9a-f]+',args).group(0),16)
            out.append(op+' '+(syms.get(t,'X')))
        else:
            args=re.sub(r'0x[0-9a-f]{7,}','A',args)
            args=re.sub(r'\b[xwvqdsh]\d+\b','r',args)
            args=re.sub(r'\b(fp|lr|sp)\b','r',args)
            out.append(op+' '+args)
    return out
if __name__=='__main__':
    cm=json.load(open(S+'tp/common_meths.json'))
    s0=load_syms(S+'sb_syms.txt'); s2=load_syms(S+'sb162_syms.txt')
    # name-only maps for call normalisation
    n0={a:re.sub(r'\.\d+$','',n) for a,n in s0.items()}; n2={a:re.sub(r'\.\d+$','',n) for a,n in s2.items()}
    i0=dump(C0,s0); i2=dump(C2,s2)
    print('insns',len(i0),len(i2),file=sys.stderr)
    res={}
    for name,((a0,z0),(a2,z2)) in cm.items():
        o0=[(a,i0[a]) for a in range(a0,a0+z0,4) if a in i0]; o2=[(a,i2[a]) for a in range(a2,a2+z2,4) if a in i2]
        f0=norm(o0,n0); f2=norm(o2,n2)
        r=1.0 if f0==f2 else difflib.SequenceMatcher(None,f0,f2,autojunk=False).ratio()
        res[name]=(r,len(f0),len(f2),a0,a2)
    json.dump(res,open(S+'tp/bodydiff.json','w'))
