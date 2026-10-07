import sys,re,collections
sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/tp')
from common import *
HEX=re.compile(r'0x[0-9a-f]+')
def analyze(fa, size=None):
    size=size or func_size(fa)
    ins=disasm(fa,size//4)
    end=fa+size
    refs=[]   # (insn_addr, kind, target, detail)
    page={}
    for (a,w,op,args) in ins:
        if op=='adrp':
            m=re.match(r'(x\d+),\s*(0x[0-9a-f]+)',args); page[m.group(1)]=int(m.group(2),16); continue
        if op in('add','ldr','str','ldrsw','ldrb','ldrh','ldur','ldp','stp','ldr') and False: pass
        m=re.match(r'(x\d+),\s*(x\d+),\s*#(0x[0-9a-f]+)$',args) if op=='add' else None
        if m and m.group(2) in page:
            refs.append((a,'addr',page[m.group(2)]+int(m.group(3),16),'add')); continue
        m=re.match(r'([xwdsq]\d+),\s*\[(x\d+)(?:,\s*#(0x[0-9a-f]+))?\]',args) if op in('ldr','ldrsw','ldrb','ldrh','str','strb','ldur') else None
        if m and m.group(2) in page:
            refs.append((a,'mem',page[m.group(2)]+(int(m.group(3),16) if m.group(3) else 0),op)); continue
        if op in('bl','b') :
            t=int(HEX.search(args).group(0),16)
            refs.append((a,'call' if op=='bl' else 'jump',t,op))
        elif op.startswith('b.') or op in('cbz','cbnz','tbz','tbnz'):
            t=int(HEX.findall(args)[-1],16)
            refs.append((a,'local' if fa<=t<end else 'cond-out',t,op))
        elif op in('adr','ldr') and re.search(r'0x[0-9a-f]+$',args) and op=='adr':
            refs.append((a,'adr',int(HEX.findall(args)[-1],16),op))
    return ins,refs
def classify(t):
    sec=section_of(t)
    return sec
if __name__=='__main__':
    fa=int(sys.argv[1],16)
    ins,refs=analyze(fa)
    cnt=collections.Counter()
    for a,k,t,op in refs:
        sec=classify(t)
        cnt[(k,sec)]+=1
    for k,v in sorted(cnt.items(),key=lambda x:-x[1]): print(v,k)
