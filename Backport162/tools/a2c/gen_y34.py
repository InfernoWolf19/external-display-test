#!/usr/bin/env python3
"""gen_y34.py [name ...] : regenerates the lifted C files of the Y34 / Y35 ports (Backport162/Y34*Lift*.c) from the 16.2 machine code with a2c.py.
Each entry: output file, header comment, bodies (ver, start, end, cname, sig, ret, cls, kinds), hand written C wrappers appended after the bodies
(exact ABI signatures of the Objective-C methods; they only forward to the lifted bodies)."""
import sys, os, subprocess
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import a2c

OUT = os.path.join(HERE, '..', '..')
PH = 'SBDeviceApplicationSceneViewPlaceholderContentViewProvider'
JOBS = {
 'lazy': dict(file='Y34LazyTypes.c',
  head='''// Y34LazyTypes.c : -[SBApplication(Classic_Internal) _calculateSupportedTypesLazilyIfNecessary] of iPadOS 16.2 (20C65, 0x1c7339fb0 .. 0x1c733b320, 1244 instructions), recompiled from
// the 16.2 machine code by tools/a2c/a2c.py (one machine instruction = one C statement, see tools/a2c/README.txt), NOT re-typed.  Plain C, no ARC: the function retains / releases exactly
// where the machine code does.  Installed by Y34ClassicTypes.x (switch y34_lazytypes).  Verified against the Unicorn emulation of the original code on 22704 inputs per device class
// (tools/a2c/tests/lazy_test.py: every home button type x device class 0/1/2 x 22 screen sizes x type bits x snapshot lists) and by tools/a2c/tests/tracecmp.py (call traces).
''',
  bodies=[('162', 0x1c7339fb0, 0x1c733b320, 'lazy162', 'x,x', 'v', 'SBApplication', '')],
  tail='''
void y34_lazy_types(void *self, void *cmd) { lazy162((uint64_t)(uintptr_t)self, (uint64_t)(uintptr_t)cmd); }
// first symbol / class / ivar this body needs and the process cannot resolve (NULL = all resolved)
const char *y34_lazy_types_preflight(void) { return lazy162_preflight(); }
'''),
 'placeholder': dict(file='Y34PlaceholderLift.c',
  head='''// Y34PlaceholderLift.c : the classic (iPhone-only app) launch image / zoom view path of iPadOS 16.2 (20C65), recompiled from the 16.2 machine code by tools/a2c/a2c.py:
//   -[SBDeviceApplicationSceneViewPlaceholderContentViewProvider sceneView:requestsPlaceholderContentViewWithContext:]   0x1c72a9bf8 (373 instructions)
//   -[SBDeviceApplicationSceneViewPlaceholderContentViewProvider _contentViewFromSceneHandle:displayConfiguration:orientation:snapshot:size:statusBarDescriptor:hasOrientationMismatchForClassicApp:customContainerBounds:]  0x1c7922f04
//   +[SBUIController(SBUIAnimationController) zoomViewForDeviceApplicationSceneHandle:displayConfiguration:interfaceOrientation:snapshot:snapshotSize:statusBarDescriptor:decodeImage:hasOrientationMismatchForClassicApp:customContainerBounds:]  0x1c77b55d4 (363 instructions)
// Plain C, no ARC.  Installed by Y34ClassicPlaceholder.x (switch y34_placeholder).  Verified with tools/a2c/tests/tracecmp.py (Unicorn emulation of the original vs this C on the same modelled environment).
''',
  bodies=[('162', 0x1c72a9bf8, 0x1c72aa1cc, 'ph162', 'x,x,x,x', 'x', PH, 'scale=d'),
          ('162', 0x1c7922f04, 0x1c7922f34, 'cv162', 'x,x,x,x,x,x,x,x,d,d,d,d,d,d', 'x', PH, ''),
          ('162', 0x1c77b55d4, 0x1c77b5b80, 'zoom162', 'x,x,x,x,x,x,d,d,x,x,b,d,d,d,d', 'x', 'SBUIController', '')],
  tail='''
uint64_t y34_ph_request(uint64_t self, uint64_t cmd, uint64_t sceneView, uint64_t context) { return ph162(self, cmd, sceneView, context); }
uint64_t y34_ph_contentView(uint64_t self, uint64_t cmd, uint64_t handle, uint64_t config, uint64_t orientation, uint64_t snapshot, double sw, double sh, uint64_t statusBar, uint8_t mismatch,
                            double bx, double by, double bw, double bh) {
    return cv162(self, cmd, handle, config, orientation, snapshot, statusBar, mismatch, sw, sh, bx, by, bw, bh);
}
uint64_t y34_zoom_view(uint64_t self, uint64_t cmd, uint64_t handle, uint64_t config, uint64_t orientation, uint64_t snapshot, double sw, double sh, uint64_t statusBar, uint8_t decode,
                       uint8_t mismatch, double bx, double by, double bw, double bh) {
    return zoom162(self, cmd, handle, config, orientation, snapshot, sw, sh, statusBar, decode, mismatch, bx, by, bw, bh);
}
const char *y34_placeholder_preflight(void) {
    const char *m = ph162_preflight(); if (m) return m;
    m = cv162_preflight(); if (m) return m;
    return zoom162_preflight();
}
'''),
}

def gen(name):
    j = JOBS[name]
    parts = [j['head'], '#include "tools/a2c/liftdev.h"\n']
    for ver, st, en, cname, sig, ret, cls, kinds in j['bodies']:
        kd = {}
        for kv in [x for x in kinds.split(',') if x]:
            k, v = kv.split('='); kd['msgSend:' + k] = v
        L = a2c.Lift(ver, st, en, cname, sig, ret, kd, cls)
        head, fn = L.generate()
        for w in L.stats['warn']: sys.stderr.write('WARN %s: %s\n' % (cname, w))
        parts.append(head + '\n' + fn + '\n')
    parts.append(j['tail'])
    open(os.path.join(OUT, j['file']), 'w').write('\n'.join(parts))
    a2c.save_memo()
    print('wrote', j['file'])

if __name__ == '__main__':
    for n in (sys.argv[1:] or list(JOBS)): gen(n)
