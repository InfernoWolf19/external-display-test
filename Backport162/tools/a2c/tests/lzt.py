import sys, ctypes, struct, subprocess, random, pickle, os
sys.dont_write_bytecode=True
sys.path.insert(0,'/tmp/claude-0/-home-user-external-display-test/y33work')
sys.path.insert(0,'/home/user/external-display-test/Backport162/tools/y26_classic_tree')
W='/tmp/claude-0/-home-user-external-display-test/y34work/'
T='/home/user/external-display-test/Backport162/tools/a2c/'
def build(gen, fname, exports):
    c=W+fname+'.c'; so=W+fname+'.so'
    open(c,'w').write('#include "liftest.h"\n#include "%s"\n%s\n'%(W+gen,exports))
    subprocess.check_call(['gcc','-O1','-shared','-fPIC','-w','-I',T,c,'-o',so,'-lm'])
    return ctypes.CDLL(so)

CB=ctypes.CFUNCTYPE(None,ctypes.c_int,ctypes.c_char_p,ctypes.POINTER(ctypes.c_uint64),ctypes.POINTER(ctypes.c_uint64*2))
IV=ctypes.CFUNCTYPE(ctypes.c_long,ctypes.c_char_p)
OBJ_MANIFEST=0x71000100; OBJ_PRED=0x71000200; OBJ_ARR=0x71000300; OBJ_GID=0x71000400; OBJ_SNAP=0x71001000
def d2i(x): return struct.unpack('<Q',struct.pack('<d',x))[0]
def i2d(i): return struct.unpack('<d',struct.pack('<Q',i&0xffffffffffffffff))[0]
IVMAP={b'SBApplication._appInfo':0xa8,b'SBApplication._calculatedSupportedTypes':0xb8,b'SBApplication._supportedTypes':0xc0}
class Env:
    def __init__(s,q,snaps,dc,hb,bounds):
        s.q,s.snaps,s.dc,s.hb,s.bounds=q,snaps,dc,hb,bounds
        s.items=(ctypes.c_uint64*64)(); s.mut=(ctypes.c_uint64*4)(); s.err=None
        s.cb=CB(s.call); s.iv=IV(lambda n: IVMAP[n])
    def call(s,isMsg,name,X,VR):
        name=name.decode()
        def setd(i,v): VR[i][0]=d2i(v)
        def getd(i): return i2d(VR[i][0])
        x0=X[0]
        try:
            if isMsg:
                sel=name
                if sel=='currentDevice' or sel=='mainScreen': X[0]=0x71000f00; return
                if sel=='userInterfaceIdiom': X[0]=1 if s.dc==2 else 0; return
                if sel=='_referenceBounds':
                    setd(0,0.);setd(1,0.);setd(2,s.bounds[0]);setd(3,s.bounds[1]); return
                if sel=='_snapshotManifest': X[0]=OBJ_MANIFEST; return
                if sel=='predicate': X[0]=OBJ_PRED; return
                if sel in('setContentTypeMask:','setRequiredOSVersion:'): return
                if sel=='defaultGroupIdentifier': X[0]=OBJ_GID; return
                if sel=='snapshotsForGroupID:matchingPredicate:': X[0]=OBJ_ARR; return
                if sel=='countByEnumeratingWithState:objects:count:':
                    st=X[2]; sv=struct.unpack('<Q',ctypes.string_at(st,8))[0]
                    if sv!=0: X[0]=0; return
                    n=len(s.snaps)
                    for i in range(n): s.items[i]=OBJ_SNAP+0x10*i
                    ctypes.memmove(st,struct.pack('<QQQ',1,ctypes.addressof(s.items),ctypes.addressof(s.mut)),24)
                    X[0]=n; return
                if sel=='referenceSize':
                    i=(x0-OBJ_SNAP)//0x10; setd(0,s.snaps[i][0]); setd(1,s.snaps[i][1]); return
                if sel in s.q:
                    v=s.q[sel]
                    if callable(v): v=v(X[2])
                    X[0]=int(v); return
                raise RuntimeError('unmodelled selector '+sel)
            nm=name
            if nm=='___sb__runningInSpringBoard': X[0]=1; return
            if nm=='_SBFEffectiveDeviceClass': X[0]=s.dc; return
            if nm=='_SBFEffectiveHomeButtonType': X[0]=s.hb; return
            if nm=='_MGCopyAnswer': X[0]=OBJ_GID; return
            if nm=='___sb__mainScreenReferenceBounds':
                setd(0,0.);setd(1,0.);setd(2,s.bounds[0]);setd(3,s.bounds[1]); return
            if nm=='_BSSizeRoundForScale':
                sc=getd(2); setd(0,float(round(getd(0)*sc)/sc)); setd(1,float(round(getd(1)*sc)/sc)); return
            if nm=='_BSSizeEqualToSize': X[0]=int(getd(0)==getd(2) and getd(1)==getd(3)); return
            raise RuntimeError('unhandled '+nm)
        except Exception as e:
            s.err=repr(e)
