import sys; sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/y34work')
from lzt import *
import itertools, random
ex='''
#include "/home/user/external-display-test/Backport162/Y34SplashTypes.h"
void run(void *self){ splash162((uint64_t)(uintptr_t)self, 0); }
void run160(void *self){ splash160((uint64_t)(uintptr_t)self, 0); }
uint64_t pure(uint64_t t, const uint8_t *f, int beta16) {
    Y34SplashQuery q = { f[0],f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8], f[9],f[10],f[11] };
    if (beta16) q.sydney = 0;  /* never used: 16.0 handled by caller through sydneyNotBeta */
    return Y34_SplashTypes(t, q);
}
'''
open(W+'splash_all.gen.c','w').write(open(W+'splash162.gen.c').read()+open(W+'splash160.gen.c').read().replace('splash160_SEL','splash160_SEL'))
lib=build('splash_all.gen.c','tsplash',ex)
lib.pure.restype=ctypes.c_uint64; lib.pure.argtypes=[ctypes.c_uint64,ctypes.c_char_p,ctypes.c_int]
names=['isMonarchLinked','isTigrisLinked','isPeaceLinked','isYukonLinked','isAzulLinked','_isNewEnoughToKnowAbout2020Phones','_isNewEnoughToKnowAboutRoundPads','isSkyLinked','isSydneyLinked']
class E2(Env):
    def __init__(s,flags,beta):
        s.fl=flags; s.beta=beta; s.err=None; s.cb=CB(s.call); s.iv=IV(lambda n: IVMAP[n]); s.log=[]
    def call(s,isMsg,name,X,VR):
        name=name.decode(); s.log.append(name)
        if not isMsg: s.err='fn '+name; return
        if name in names: X[0]=s.fl[names.index(name)]; return
        if name=='_supportsApplicationType:': X[0]=s.fl[9] if X[2]==2 else s.fl[11]; return
        if name=='wantsFullScreen': X[0]=s.fl[10]; return
        if name=='isBeta': X[0]=s.beta; return
        s.err='sel '+name
def runlift(fn,flags,beta,types):
    e=E2(flags,beta); lib.lift_set(e.cb,e.iv)
    buf=(ctypes.c_uint8*0x200)(); struct.pack_into('<Q',buf,0xc0,types)
    fn(ctypes.byref(buf))
    assert not e.err,e.err
    return struct.unpack_from('<Q',bytes(buf),0xc0)[0]
random.seed(1)
seeds=[0,0xffffffffffffffff,0x123456789abcdef0]+[random.getrandbits(64) for _ in range(5)]
bad=0;n=0;d160=0;d160_sydney_beta=0
for flags in itertools.product((0,1),repeat=12):
    fb=bytes(flags)
    for beta in (0,1):
        for t in seeds:
            r2=runlift(lib.run,flags,beta,t); p=lib.pure(t,fb,0); n+=1
            if r2!=p: bad+=1; 
            if bad and bad<5 and r2!=p: print('MISMATCH 162',flags,hex(t),hex(r2),hex(p))
            r0=runlift(lib.run160,flags,beta,t)
            if r0!=r2:
                d160+=1
                # explain: only allowed difference: sydney && type1 && beta  (flags[8],flags[11])
                if not (flags[8] and flags[11] and beta): print('UNEXPECTED 160/162 difference',flags,beta,hex(t),hex(r0),hex(r2))
                else: d160_sydney_beta+=1
print('cases',n,'pure vs lifted 16.2 mismatches',bad,'| 16.0 vs 16.2 differing cases',d160,'(all with sydney+beta+type1: %d)'%d160_sydney_beta)
