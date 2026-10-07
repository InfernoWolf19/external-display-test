import re,subprocess,bisect,functools,json,os
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad'
C2=S+'/dsc162/20C65__iPad13,4_5_6_7_8_9_10_11/dyld_shared_cache_arm64e'
IPSW=S+'/bin/ipsw'
# SpringBoard 16.2 section table
SECT=[]
def load_sections():
    out=subprocess.run([IPSW,'dsc','macho',C2,'SpringBoard','-l'],capture_output=True,text=True).stdout
    for l in out.splitlines():
        m=re.match(r'^\s+sz=0x[0-9a-f]+ off=\S+ addr=(0x[0-9a-f]+)-(0x[0-9a-f]+)\s+(\S+)',l)
        if m: SECT.append((int(m.group(1),16),int(m.group(2),16),m.group(3)))
    SECT.sort()
load_sections()
_starts=[s[0] for s in SECT]
def section_of(a):
    i=bisect.bisect_right(_starts,a)-1
    if i>=0 and SECT[i][0]<=a<SECT[i][1]: return SECT[i][2]
    return None
# symbols of SpringBoard 16.2 (code + data)
SYMS={}
for l in open(S+'/sb162_syms.txt',errors='replace'):
    m=re.match(r'(0x[0-9a-f]+):\s+\([^)]*\)\s+\S+\s+(\S.*?)\s*$',l)
    if m: SYMS[int(m.group(1),16)]=m.group(2)
SYMK=sorted(SYMS)
def sym_at(a): 
    return SYMS.get(a)
def func_size(a):
    i=bisect.bisect_right(SYMK,a)
    # next symbol that is in __text
    while i<len(SYMK) and section_of(SYMK[i])!='__TEXT.__text': i+=1
    return (SYMK[i]-a) if i<len(SYMK) else 0
@functools.lru_cache(maxsize=None)
def disasm(a,n):
    out=subprocess.run([IPSW,'dsc','disass',C2,'--vaddr',hex(a),'--count',str(n),'--quiet','--no-color'],capture_output=True,text=True).stdout
    res=[]
    for l in out.splitlines():
        m=re.match(r'^(0x[0-9a-f]+):\s+((?:[0-9a-f]{2} ){4})\s*(\S+)\s*(.*)$',l)
        if m:
            b=bytes.fromhex(m.group(2).replace(' ',''))
            res.append((int(m.group(1),16),int.from_bytes(b,'little'),m.group(3),m.group(4).strip()))
    return res
@functools.lru_cache(maxsize=None)
def read_u64(a):
    out=subprocess.run([IPSW,'dsc','dump',C2,hex(a),'-a','-c','1'],capture_output=True,text=True).stdout
    m=re.findall(r'0x[0-9a-f]+',out)
    return int(m[-1],16) if m else None
def read_bytes(a,n):
    out=subprocess.run([IPSW,'dsc','dump',C2,hex(a),'--size',str(n)],capture_output=True,text=True).stdout
    bs=b''
    for l in out.splitlines():
        m=re.match(r'^([0-9a-f]{16}):\s+(.*?)\s*\|',l)
        if m: bs+=bytes.fromhex(''.join(re.findall(r'\b[0-9a-f]{2}\b',m.group(2))))
    return bs[:n]
@functools.lru_cache(maxsize=None)
def read_cstr(a):
    return read_bytes(a,200).split(b'\0')[0].decode('latin1')
@functools.lru_cache(maxsize=None)
def a2s(a):
    out=subprocess.run([IPSW,'dsc','a2s',C2,hex(a)],capture_output=True,text=True).stdout
    m=re.search(r'0x[0-9a-f]+: (\S+)',out)
    return m.group(1) if m else None
def strip_ptr(v):
    return None if v is None else v & 0x0000000FFFFFFFFF

@functools.lru_cache(maxsize=None)
def resolve_stub(t):
    """Follow cache-optimised direct stubs (adrp/add/br) to the final target; return (final_addr, name)."""
    cur=t
    for _ in range(4):
        ins=disasm(cur,3)
        if len(ins)>=3 and ins[0][2]=='adrp' and ins[1][2]=='add' and ins[2][2]=='br':
            m1=re.match(r'(x\d+),\s*(0x[0-9a-f]+)',ins[0][3]); m2=re.match(r'(x\d+),\s*(x\d+),\s*#(0x[0-9a-f]+)',ins[1][3])
            cur=int(m1.group(2),16)+int(m2.group(3),16)
            continue
        break
    return cur,a2s(cur)

@functools.lru_cache(maxsize=None)
def a2s_img(a):
    out=subprocess.run([IPSW,'dsc','a2s',C2,hex(a)],capture_output=True,text=True).stdout
    m=re.search(r'0x[0-9a-f]+: (\S+)',out); img=re.search(r'dylib=(\S*)',out)
    return (m.group(1) if m else None, os.path.basename(img.group(1)) if img and img.group(1) else None)
