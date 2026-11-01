import sys; sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/y33work'); sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/y34work')
from ct import *
import itertools, random, ctypes, subprocess
f2=F('162',0x1c733c13c,0x1c733c334,'spl162.raw'); f0=F('160',0x1c5ec8d2c,0x1c5ec8f44,'spl160.raw')
names=['isMonarchLinked','isTigrisLinked','isPeaceLinked','isYukonLinked','isAzulLinked','_isNewEnoughToKnowAbout2020Phones','_isNewEnoughToKnowAboutRoundPads','isSkyLinked','isSydneyLinked']
def go(f,flags,beta,t):
    q={n:flags[i] for i,n in enumerate(names)}
    q['_supportsApplicationType:']=lambda x:flags[9] if x==2 else flags[11]
    q['wantsFullScreen']=flags[10]; q['isBeta']=beta
    r=run(f,q,selfinit={0xc0:t})
    assert not r['err'],r['err']
    return struct.unpack_from('<Q',r['mem'],0xc0)[0]
src='''#include "/home/user/external-display-test/Backport162/Y34SplashTypes.h"
uint64_t pure(uint64_t t, const uint8_t *f){ Y34SplashQuery q={f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],f[10],f[11]}; return Y34_SplashTypes(t,q);}'''
open('p.c','w').write(src); subprocess.check_call(['gcc','-O1','-shared','-fPIC','-o','p.so','p.c'])
lib=ctypes.CDLL('./p.so'); lib.pure.restype=ctypes.c_uint64; lib.pure.argtypes=[ctypes.c_uint64,ctypes.c_char_p]
random.seed(2); seeds=[0,0x123456789abcdef0,random.getrandbits(64)]
bad=0;n=0;d=0
for flags in itertools.product((0,1),repeat=12):
    for beta in (0,1):
        for t in seeds:
            e2=go(f2,flags,beta,t); p=lib.pure(t,bytes(flags)); e0=go(f0,flags,beta,t); n+=1
            if e2!=p: bad+=1; print('MISMATCH',flags,hex(t),hex(e2),hex(p)) if bad<4 else None
            if e0!=e2:
                d+=1
                if not(flags[8] and flags[11] and beta): print('UNEXPECTED',flags,beta)
print('unicorn: cases',n,'pure vs unicorn16.2 mismatches',bad,'16.0!=16.2 cases',d)
