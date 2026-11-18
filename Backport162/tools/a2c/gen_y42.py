#!/usr/bin/env python3
"""gen_y42.py [name ...] : regenerates the lifted C files of the Y42+ ports (Backport162/Y42*Lift.c) from the 16.2 machine code with a2c.py (same job format as gen_y34.py; a body may list
`locals`: address -> C name of block invoke / helper bodies lifted earlier in the same file).  Kinds: 'sel=k' for a selector, 'fn:name=k' for a C function."""
import sys, os
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import a2c

OUT = os.path.join(HERE, '..', '..')
JOBS = {
 'shelf': dict(file='Y42ShelfLift.c',
  head='''// Y42ShelfLift.c : -[SBShelfLiveContentOverlayCoordinator _addOverlaysIfNeededForTransitionContext:] of iPadOS 16.2 (20C65, 0x1c798ac94 .. 0x1c798b330) and its block invoke
// 0x1c798b338, recompiled from the 16.2 machine code by tools/a2c/a2c.py (a stack block: arm64e pacda isa / pacia invoke, descriptor, one captured object).  Plain C, no ARC.
// The 16.2 init of SBShelfLiveContentOverlay (0x1c798b6b8, 84 instructions) is lifted too: the 16.0 class only has the referenceOrientation: init, the 16.2 coordinator body asks for the new selector.  Installed by Y42Shelf.x (switch y42_shelf).  Verified with tools/a2c/tests/tracecmp.py (calls, ownership events, PAC logs, block image against the Unicorn emulation).  NOT device tested.
''',
  bodies=[('162', 0x1c798b338, 0x1c798b344, 'shelfblk7', 'x,x', 'x', 'SBShelfLiveContentOverlayCoordinator', '', {}),
          ('162', 0x1c798ac94, 0x1c798b330, 'shelf162', 'x,x,x', 'v', 'SBShelfLiveContentOverlayCoordinator', '', {0x1c798b338: 'shelfblk7'}),
          ('162', 0x1c798b6b8, 0x1c798b808, 'shelfinit', 'x,x,x,d,d,x,x,x,x', 'x', 'SBShelfLiveContentOverlay', '', {})],
  tcargs=['--datasyms', 'kCAFilterBox=box'],
  tail='''
void y42_shelf_add(void *self, void *cmd, void *context) { shelf162((uint64_t)(uintptr_t)self, (uint64_t)(uintptr_t)cmd, (uint64_t)(uintptr_t)context); }
// -[SBShelfLiveContentOverlay initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:livePortalView:isInsetForHomeAffordance:] 0x1c798b6b8, installed as an IMP (the ownership
// is the machine code's: self arrives +1 and is returned +1)
uint64_t y42_shelf_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t contentOri, uint64_t containerOri, uint64_t portal, uint64_t inset) {
    return shelfinit(self, cmd, handle, w, h, contentOri, containerOri, portal, inset & 1);
}
const char *y42_shelf_preflight(void) { const char *m = shelf162_preflight(); return m ? m : shelfinit_preflight(); }
'''),
}

def gen(name):
    j = JOBS[name]
    parts = [j['head'], '#include "tools/a2c/liftdev.h"\n']
    for ver, st, en, cname, sig, ret, cls, kinds, locs in j['bodies']:
        kd = {}
        for kv in [x for x in kinds.split(',') if x]:
            k, v = kv.split('=')
            kd[k if k.startswith('fn:') else 'msgSend:' + k] = v
        L = a2c.Lift(ver, st, en, cname, sig, ret, kd, cls)
        L.locals = dict(locs)
        head, fn = L.generate()
        for w in L.stats['warn']: sys.stderr.write('WARN %s: %s\n' % (cname, w))
        parts.append(head + '\n' + fn + '\n')
    parts.append(j['tail'])
    open(os.path.join(OUT, j['file']), 'w').write('\n'.join(parts))
    a2c.save_memo()
    print('wrote', j['file'])

if __name__ == '__main__':
    for n in (sys.argv[1:] or list(JOBS)): gen(n)
