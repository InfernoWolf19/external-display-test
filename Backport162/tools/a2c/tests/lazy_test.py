import sys; sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/y34work')
from lzt import *
import random
sizes=[(320,480),(320,568),(375,667),(414,736),(320,693),(375,812),(390,844),(414,896),(428,926),(393,852),(430,932),(768,1024),(810,1080),(834,1112),(1024,1366),(744,1133),(820,1180),(954,1373),(834,1194),(970,1389),(1192,1590),(1000,1000)]
random.seed(5)
allsz=[(float(a),float(b)) for a,b in sizes]
snapsets=[[]]+[[s] for s in allsz]+[random.sample(allsz,2) for _ in range(20)]
ex='void run(void *self){ LIFTFN((uint64_t)(uintptr_t)self, 0); }'
l0=build('lazy160.gen.c','t160',ex.replace('LIFTFN','lazy160'))
l2=build('lazy162.gen.c','t162',ex.replace('LIFTFN','lazy162'))
def go(lib,t1,t2,nep,hb,b,sn,dc):
    q={'_supportsApplicationType:':lambda t:{1:t1,2:t2}[t],'_isNewEnoughToKnowAboutRoundPads':nep,'usesSplashBoard':0,'_bypassesClassicMode':0}
    e=Env(q,sn,dc,hb,b)
    lib.lift_set(e.cb,e.iv)
    buf=(ctypes.c_uint8*0x200)()
    lib.run(ctypes.byref(buf))
    if e.err: return ('ERR',e.err)
    return struct.unpack_from('<Q',bytes(buf),0xc0)[0]
dc=int(sys.argv[1])
emu=pickle.load(open('/tmp/claude-0/-home-user-external-display-test/y33work/lz2_dc%d.pkl'%dc,'rb'))
bad=0;n=0
for k,(e0,e2) in emu.items():
    hb,b,t1,t2,nep,si=k
    r0=go(l0,t1,t2,nep,hb,b,snapsets[si],dc); r2=go(l2,t1,t2,nep,hb,b,snapsets[si],dc)
    n+=1
    if r0!=e0 or r2!=e2:
        bad+=1
        if bad<10: print('MISMATCH',k,'lift160',r0,'emu160',e0,'lift162',r2,'emu162',e2)
print('compared',n,'bad',bad)
