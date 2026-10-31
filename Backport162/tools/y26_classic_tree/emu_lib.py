import subprocess, re, os, struct, sys
S='/tmp/claude-0/-home-user-external-display-test/831757de-8472-5d7e-a1ed-05fb16db2e95/scratchpad/'
DSC={'160':S+'dsc/com.apple.dyld/dyld_shared_cache_arm64e','162':S+'dsc162/20C65__iPad13,4_5_6_7_8_9_10_11/dyld_shared_cache_arm64e'}
CACHE='/tmp/claude-0/-home-user-external-display-test/y24work/dumpcache/'
os.makedirs(CACHE,exist_ok=True)
def dump(ver,addr,size):
    fn=CACHE+'%s_%x_%x.bin'%(ver,addr,size)
    if os.path.exists(fn): return open(fn,'rb').read()
    out=subprocess.run([S+'bin/ipsw','dsc','dump',DSC[ver],hex(addr),'--size',str(size)],capture_output=True,text=True).stdout
    data=bytearray()
    for l in out.splitlines():
        m=re.match(r'^[0-9a-f]{16}:\s+([0-9a-f ]+?)\s*\|',l)
        if m:
            data+=bytes.fromhex(m.group(1).replace(' ',''))
    assert len(data)==size,(len(data),size,out[:300])
    open(fn,'wb').write(bytes(data))
    return bytes(data)
if __name__=='__main__':
    d=dump(sys.argv[1],int(sys.argv[2],16),int(sys.argv[3]))
    print(len(d), d[:16].hex())
