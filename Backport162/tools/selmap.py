import re,subprocess,sys,json,pickle
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/'
IPSW=S+'bin/ipsw'
def sh(a): return subprocess.run(a,capture_output=True,text=True).stdout
def build(cache,tag,stubs,selrefs):
    (sa,sb),(ra,rb)=stubs,selrefs
    n=(rb-ra)//8
    out=sh([IPSW,'dsc','dump',cache,hex(ra),'-a','-c',str(n)])
    ptrs=[int(x,16) for x in re.findall(r'0x[0-9a-f]+',out)][-n:]
    lo,hi=min(ptrs),max(ptrs)+200
    print(tag,n,hex(lo),hex(hi),file=sys.stderr)
    # dump selector blob in chunks
    blob=bytearray(); step=0x400000
    a=lo&~0xf
    while a<hi:
        sz=min(step,hi-a)
        o=sh([IPSW,'dsc','dump',cache,hex(a),'--size',str(sz)])
        chunk=bytearray()
        for l in o.splitlines():
            m=re.match(r'^([0-9a-f]{16}):\s+(.*?)\s*\|',l)
            if m: chunk+=bytes.fromhex(''.join(re.findall(r'\b[0-9a-f]{2}\b',m.group(2))))
        blob+=chunk[:sz]; a+=sz
    base=lo&~0xf
    def cs(p):
        i=p-base; j=blob.find(b'\0',i); return blob[i:j].decode('latin1')
    slot2sel={ra+8*i:cs(p) for i,p in enumerate(ptrs)}
    # stubs
    o=sh([IPSW,'dsc','disass',cache,'--vaddr',hex(sa),'--count',str((sb-sa)//4),'--quiet','--no-color'])
    ins=[]
    for l in o.splitlines():
        m=re.match(r'^(0x[0-9a-f]+):\s+(?:[0-9a-f]{2} ){4}\s*(\S+)\s*(.*)$',l)
        if m: ins.append((int(m.group(1),16),m.group(2),m.group(3).strip()))
    stub2sel={}
    for i in range(len(ins)-1):
        a,op,ar=ins[i]
        if op=='adrp' and ar.startswith('x1,') :
            a2,op2,ar2=ins[i+1]
            m=re.match(r'x1,\s*\[x1(?:,\s*#(0x[0-9a-f]+))?\]',ar2)
            if op2=='ldr' and m:
                pg=int(re.search(r'0x[0-9a-f]+',ar).group(0),16); slot=pg+(int(m.group(1),16) if m.group(1) else 0)
                if slot in slot2sel: stub2sel[a]=slot2sel[slot]
    pickle.dump((slot2sel,stub2sel),open(S+f'tp/selmap_{tag}.pkl','wb'))
    print(tag,'slots',len(slot2sel),'stubs',len(stub2sel),file=sys.stderr)
C0=S+'dsc/com.apple.dyld/dyld_shared_cache_arm64e'; C2=S+'dsc162/20C65__iPad13,4_5_6_7_8_9_10_11/dyld_shared_cache_arm64e'
build(C0,'160',(0x1c683cfe0,0x1c68f5000),(0x1d7d29728,0x1d7d60ad0))
build(C2,'162',(0x1c7d15800,0x1c7dd2000),(0x1d7cca8c0,0x1d7d03168))
