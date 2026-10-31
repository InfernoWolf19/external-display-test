import sys, re, struct, json, itertools
from unicorn import *
from unicorn.arm64_const import *
from emu_lib import dump

SW, SH = 7777.25, 8888.75      # sentinel screen size (rounded reference bounds)
SELF = 0x70000000
PAGE = 0x1000

def d2i(x): return struct.unpack('<Q', struct.pack('<d', x))[0]
def i2d(i): return struct.unpack('<d', struct.pack('<Q', i & 0xffffffffffffffff))[0]

def fix_ptrs(data):
    out = bytearray(data)
    for i in range(0, len(out), 8):
        v = struct.unpack_from('<Q', out, i)[0]
        if v >> 63:
            a = 0x180000000 + (v & 0xffffffff)
            if 0x180000000 <= a < 0x200000000 and ((v >> 51) & 0x7ff) < 0x40:
                struct.pack_into('<Q', out, i, a)
        else:
            a = v & 0x7ffffffffff
            if 0x180000000 <= a < 0x200000000 and (v >> 43) < 0x1000 and (v >> 51) < 0x40:
                struct.pack_into('<Q', out, i, a)
    return bytes(out)

class Fn:
    def __init__(self, ver, start, end, names):
        self.ver, self.start, self.end = ver, start, end
        self.code = dump(ver, start & ~0xfff, ((end - (start & ~0xfff)) + 0xfff) & ~0xfff)
        self.names = names     # addr -> name
        self.pages = {}

def parse_names(rawfile):
    names = {}
    for l in open(rawfile):
        m = re.match(r'^0x([0-9a-f]+): +(bl|b) +0x([0-9a-f]+) +(\S+)', l)
        if m: names[int(m.group(3), 16)] = m.group(4)
    return names

class Run:
    """one emulation under a (partial) assignment; unknown boolean queries are recorded and answered False"""
    def __init__(self, fn, env, assign):
        self.fn, self.env, self.assign = fn, env, assign
        self.trace = []            # list of (var, answered)
        self.result = None
        self.err = None
        self.cmplog = []

    def var(self, key):
        if key in self.assign: v = self.assign[key]
        else: v = False
        if not any(k == key for k, _ in self.trace): self.trace.append((key, v))
        return v

    def run(self):
        fn = self.fn
        uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
        uc.reg_write(UC_ARM64_REG_CPACR_EL1, 0x300000)
        base = fn.start & ~0xfff
        uc.mem_map(base, len(fn.code)); uc.mem_write(base, fn.code)
        uc.mem_map(SELF, 0x2000)
        uc.mem_map(0x71000000, 0x1000)
        uc.mem_map(0x7f000000, 0x100000)
        mapped = set()
        def unmapped(uc, access, address, size, value, ud):
            pg = address & ~0xfff
            if pg in mapped: return False
            try:
                data = dump(fn.ver, pg, 0x1000)
            except AssertionError:
                return False
            data = fix_ptrs(data)
            uc.mem_map(pg, 0x1000); uc.mem_write(pg, data); mapped.add(pg)
            return True
        uc.hook_add(UC_HOOK_MEM_READ_UNMAPPED | UC_HOOK_MEM_WRITE_UNMAPPED | UC_HOOK_MEM_FETCH_UNMAPPED, unmapped)
        uc.reg_write(UC_ARM64_REG_SP, 0x7f080000)
        uc.reg_write(UC_ARM64_REG_X0, SELF)
        uc.reg_write(UC_ARM64_REG_X30, 0xdead0000)
        me = self
        def setd(i, v): uc.reg_write(UC_ARM64_REG_D0 + i, d2i(v))
        def getd(i): return i2d(uc.reg_read(UC_ARM64_REG_D0 + i))
        def size_cmp(kind):
            a = (getd(0), getd(1)); b = (getd(2), getd(3))
            me.cmplog.append((kind, a, b))
            if me.env['bounds'] is None:
                sa = (a == (SW, SH)); sb = (b == (SW, SH))
                if sa and not sb: return me.var((kind, 'L', b))
                if sb and not sa: return me.var((kind, 'R', a))
                if sa and sb: raise RuntimeError('both sentinel')
            if kind == 'EQ': return a == b
            if kind == 'GE': return a[0] >= b[0] and a[1] >= b[1]
            if kind == 'LT': return a[0] < b[0] and a[1] < b[1]
            raise RuntimeError(kind)
        def callout(name, pc):
            x0 = uc.reg_read(UC_ARM64_REG_X0)
            if name.startswith('_objc_') or name == '_objc_claimAutoreleasedReturnValue': return
            if name == '___sb__runningInSpringBoard': uc.reg_write(UC_ARM64_REG_X0, 1); return
            if name == 'msgSend:usesSplashBoard': uc.reg_write(UC_ARM64_REG_X0, int(me.var(('F', 'usesSplashBoard')))); return
            if name == 'msgSend:_useSupportedTypesForSplashBoard': uc.reg_write(UC_ARM64_REG_X0, int(me.var(('F', 'useSupportedTypesForSplashBoard')))); return
            if name == 'msgSend:_bypassesClassicMode': uc.reg_write(UC_ARM64_REG_X0, int(me.var(('F', 'bypassesClassicMode')))); return
            if name == 'msgSend:isSydneyLinked': uc.reg_write(UC_ARM64_REG_X0, int(me.var(('F', 'isSydneyLinked')))); return
            if name == 'msgSend:isTigrisLinked': uc.reg_write(UC_ARM64_REG_X0, int(me.var(('F', 'isTigrisLinked')))); return
            if name.startswith('msgSend:KJHKJH'): uc.reg_write(UC_ARM64_REG_X0, int(me.var(('F', 'KJH')))); return
            if name == '_SBHScreenTypeForCurrentDevice': uc.reg_write(UC_ARM64_REG_X0, 31 if me.var(('F', 'screenType31')) else 0xfff); return
            if name == '_SBFEffectiveDeviceClass': uc.reg_write(UC_ARM64_REG_X0, me.env['dc']); return
            if name == '_SBFEffectiveHomeButtonType': uc.reg_write(UC_ARM64_REG_X0, me.env['hb']); return
            if name == 'msgSend:_supportsApplicationType:':
                t = uc.reg_read(UC_ARM64_REG_X2); uc.reg_write(UC_ARM64_REG_X0, int(me.var(('T', t)))); return
            if name == '___sb__mainScreenReferenceBounds' or name == 'msgSend:_referenceBounds':
                setd(0, 0.0); setd(1, 0.0); bw, bh = me.env['bounds'] if me.env['bounds'] else (SW, SH)
                setd(2, bw); setd(3, bh); return
            if name == 'msgSend:mainScreen' or name == 'msgSend:currentDevice': uc.reg_write(UC_ARM64_REG_X0, 0x71000000); return
            if name == 'msgSend:userInterfaceIdiom': uc.reg_write(UC_ARM64_REG_X0, 1); return
            if name == '_BSSizeRoundForScale':
                assert getd(2) == 1.0
                if me.env['bounds'] is not None:
                    setd(0, float(round(getd(0)))); setd(1, float(round(getd(1))))
                return
            if name == '_BSSizeEqualToSize': uc.reg_write(UC_ARM64_REG_X0, int(size_cmp('EQ'))); return
            if name == '_BSSizeGreaterThanOrEqualToSize': uc.reg_write(UC_ARM64_REG_X0, int(size_cmp('GE'))); return
            if name == '_BSSizeLessThanSize': uc.reg_write(UC_ARM64_REG_X0, int(size_cmp('LT'))); return
            raise RuntimeError('unhandled callout ' + name)
        def code(uc, addr, size, ud):
            if addr == 0xdead0000: me.result = uc.reg_read(UC_ARM64_REG_X0); uc.emu_stop(); return
            if fn.start <= addr < fn.end:
                insn = struct.unpack('<I', uc.mem_read(addr, 4))[0]
                if insn in (0xd65f0fff, 0xd65f03c0):
                    me.result = uc.reg_read(UC_ARM64_REG_X0); me.result = me.result - (1 << 64) if me.result >> 63 else me.result
                    uc.emu_stop()
                return
            nm = fn.names.get(addr)
            if nm is None: me.err = 'pc outside function %x' % addr; uc.emu_stop(); return
            try:
                callout(nm, addr)
            except Exception as e:
                me.err = 'callout %s: %r' % (nm, e); uc.emu_stop(); return
            uc.reg_write(UC_ARM64_REG_PC, uc.reg_read(UC_ARM64_REG_X30))
        uc.hook_add(UC_HOOK_CODE, code)
        try:
            uc.emu_start(fn.start, 0, count=20000)
        except UcError as e:
            me.err = 'uc error %s at pc=%x' % (e, uc.reg_read(UC_ARM64_REG_PC))
        return self

def explore(fn, env):
    """DFS over the boolean variables the function queries; returns list of (assignment-dict, result)"""
    leaves = []
    stack = [dict()]
    seen = 0
    while stack:
        a = stack.pop()
        r = Run(fn, env, a).run()
        seen += 1
        if r.err or r.result is None:
            raise RuntimeError('run failed: %s assign=%s' % (r.err, a))
        # variables queried in order; those not in `a` are answered False; branch by flipping each unassigned queried var
        fixed = dict(a)
        for key, v in r.trace:
            if key not in a:
                fixed[key] = v
        leaves.append((fixed, r.result, [k for k, _ in r.trace]))
        # for each queried-but-unassigned var (in order), create a sibling with that var True, keeping earlier choices
        prefix = dict(a)
        for key, v in r.trace:
            if key in a: continue
            sib = dict(prefix); sib[key] = True      # v was False
            stack.append(sib)
            prefix[key] = False
    return leaves


def load(ver):
    if ver == '162': return Fn('162', 0x1c733c334, 0x1c733da28, parse_names('cm162.raw'))
    return Fn('160', 0x1c5ec8f44, 0x1c5eca42c, parse_names('cm160.raw'))

def explore_under(fn, env, fixed):
    """leaves of fn consistent with the fixed assignment: list of (full assignment, result)"""
    out = []
    stack = [dict(fixed)]
    while stack:
        a = stack.pop()
        r = Run(fn, env, a).run()
        if r.err or r.result is None: raise RuntimeError('run failed: %s assign=%s' % (r.err, a))
        fx = dict(a)
        for key, v in r.trace:
            if key not in a: fx[key] = v
        out.append((fx, r.result))
        prefix = dict(a)
        for key, v in r.trace:
            if key in a: continue
            sib = dict(prefix); sib[key] = True; stack.append(sib); prefix[key] = False
    return out

if __name__ == '__main__':
    import pickle
    hb = int(sys.argv[1]); W = float(sys.argv[2]); H = float(sys.argv[3])
    env = {'dc': 2, 'hb': hb, 'bounds': (W, H)}
    f0, f2 = load('160'), load('162')
    l2 = explore_under(f2, env, {})
    l0 = explore_under(f0, env, {})
    print('hb', hb, 'size', W, H, 'leaves 160:', len(l0), ' 162:', len(l2))
    from collections import Counter
    print(' 160 results', sorted(Counter(r for _, r in l0).items()))
    print(' 162 results', sorted(Counter(r for _, r in l2).items()))
    pickle.dump((l0, l2), open('leaves_%d_%d_%d.pkl' % (hb, W, H), 'wb'))
