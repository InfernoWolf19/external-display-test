import subprocess,re,sys,json,os
cache=sys.argv[1]; start=sys.argv[2]; count=sys.argv[3]
def run(a): return subprocess.run(a,capture_output=True,text=True).stdout
def dis(a,n): return run(['./bin/ipsw','dsc','disass',cache,'--vaddr',a,'--quiet','--count',str(n),'--no-color'])
CF='cfcache.json'
memo=json.load(open(CF)) if os.path.exists(CF) else {}
def save(): json.dump(memo,open(CF,'w'))
def a2s(t):
    k='a2s:'+t
    if k in memo: return memo[k]
    o=run(['./bin/ipsw','dsc','a2s',cache,t]); m=re.search(r'0x[0-9a-f]+: (\S+)',o); memo[k]=m.group(1) if m else ''; return memo[k]
def instrs(a,n):
    out=[]
    for l in dis(a,n).splitlines():
        m=re.match(r'^(0x[0-9a-f]+):\s+(?:[0-9a-f]{2} ){4}\s*(\S+)\s*(.*)$',l)
        if m: out.append((int(m.group(1),16),m.group(2),m.group(3).strip()))
    return out
def resolve(t):
    k='bl:'+t
    if k in memo: return memo[k]
    ins=instrs(t,5); r=''
    txt=' | '.join(f'{m} {o}' for _,m,o in ins[:4])
    m1=re.search(r'adrp\s+x1,\s*(0x[0-9a-f]+)',txt); m2=re.search(r'ldr\s+x1,\s*\[x1(?:,\s*#(0x[0-9a-f]+))?\]',txt)
    if m1 and m2:
        ref=hex(int(m1.group(1),16)+(int(m2.group(1),16) if m2.group(1) else 0))
        s=run(['./bin/sel',cache,ref]); mm=re.search(r'-> "(.*)"',s); r='msgSend:'+(mm.group(1) if mm else '?')
    else:
        m3=re.search(r'adrp\s+x16,\s*(0x[0-9a-f]+).*add\s+x16,\s*x16,\s*#(0x[0-9a-f]+).*br\s+x16',txt)
        if m3: r=a2s(hex(int(m3.group(1),16)+int(m3.group(2),16)))
        if not r: r=a2s(t)
        if not r: r='fn'
    memo[k]=r; return r
def cfs(addr):
    k='cf:'+addr
    if k in memo: return memo[k]
    o=run(['./bin/cfstr',cache,addr]); m=re.search(r'-> "(.*)"',o); memo[k]=m.group(1) if m else ''; return memo[k]
ins=instrs(start,int(count))
adrp={}
first=True
for a,m,o in ins:
    if m=='pacibsp':
        if not first: break
        first=False
    note=''
    mm=re.match(r'(x\d+),\s*(0x[0-9a-f]+)$',o)
    if m=='adrp' and mm: adrp[mm.group(1)]=int(mm.group(2),16)
    ma=re.match(r'(x\d+),\s*(x\d+),\s*#(0x[0-9a-f]+)$',o)
    if m=='add' and ma and ma.group(2) in adrp:
        addr=hex(adrp[ma.group(2)]+int(ma.group(3),16)); s=cfs(addr)
        if s: note=f'"{s}"'
    mb=re.match(r'(0x[0-9a-f]+)$',o)
    if m in('bl','b') and mb: note=resolve(mb.group(1))
    print(f'{a:#x}: {m:6} {o:38} {note}')
save()
