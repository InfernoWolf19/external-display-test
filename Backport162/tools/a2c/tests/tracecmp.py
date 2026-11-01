#!/usr/bin/env python3
"""tracecmp.py <ver> <start> <end> <cname> <sig> <retkind> <cls|-> <nseeds> [argkinds]
Differential test of a2c.py output: the original machine code (Unicorn) and the lifted C (gcc, test prelude) run on the same modelled environment
(same fake objects, same deterministic answers for every call); the traces of all calls (callee, x0..x7, d0..d7) and the result / the written
object memory are compared.  Calls are identified by name; answers depend on (seed, call index, callee name) only."""
import sys, os, re, struct, ctypes, subprocess, random, hashlib
sys.dont_write_bytecode = True
sys.path.insert(0, '/tmp/claude-0/-home-user-external-display-test/y34work')
sys.path.insert(0, '/home/user/external-display-test/Backport162/tools/y26_classic_tree')
import a2c
from emu_lib import dump
from emu import fix_ptrs
from unicorn import *
from unicorn.arm64_const import *
W = a2c.W; T = '/home/user/external-display-test/Backport162/tools/a2c/'
SELF_EMU = 0x70000000; OBJ_EMU = 0x71000000; OBJ_SZ = 0x10000; SELF_SZ = 0x2000; STK_EMU = 0x7f000000; SP0_EMU = 0x7f080000
def d2i(x): return struct.unpack('<Q', struct.pack('<d', x))[0]
def i2d(i): return struct.unpack('<d', struct.pack('<Q', i & 0xffffffffffffffff))[0]
DVALS = [0.0, 1.0, 0.5, 2.0, 20.0, 100.5, 320.0, 375.0, 667.0, 768.0, 1024.0, 1366.0, -1.0, 44.0, 0.25]

def rnd(seed, name, idx):
    h = hashlib.md5(('%d/%s/%d' % (seed, name, idx)).encode()).digest()
    return random.Random(int.from_bytes(h[:8], 'little'))

def ret_values(seed, name, idx, kind):
    r = rnd(seed, name, idx)
    c = r.random()
    if c < 0.3: x0 = ('i', 0)
    elif c < 0.5: x0 = ('i', 1)
    elif c < 0.6: x0 = ('i', r.choice([2, 3, 4, 8]))
    else: x0 = ('o', r.randrange(1, 40))
    ds = [r.choice(DVALS) for _ in range(4)]
    return x0, ds

def mem_words(seed, n, tag):
    r = random.Random(seed * 7919 + __import__('zlib').crc32(tag.encode()) % 1000)
    out = []
    for i in range(n):
        c = r.random()
        if c < 0.5: out.append(('i', 0))
        elif c < 0.7: out.append(('o', r.randrange(1, 40)))
        elif c < 0.8: out.append(('i', r.choice([1, 2, 3, 4])))
        else: out.append(('d', r.choice(DVALS)))
    return out

def enc(w, objbase):
    k, v = w
    if k == 'i': return v
    if k == 'o': return objbase + v * 0x100
    return d2i(v)

def parse_sig(sig): return [x for x in sig.split(',') if x]

class Case:
    def __init__(s, ver, start, end, cname, sig, retk, cls, kinds_at):
        s.ver, s.start, s.end, s.cname, s.sig, s.retk, s.cls, s.kinds_at = ver, start, end, cname, parse_sig(sig), retk, cls, kinds_at

# --------------------------------------------------------------- emulator side
def emu_names(ver, start, end):
    S = a2c.S
    cache = a2c.DSC[ver]
    ann = S + ('annot162.py' if ver == '162' else 'annot160b.py')
    out = subprocess.run(['python3', ann, cache, hex(start), str((end - start) // 4 + 8)], capture_output=True, text=True, cwd=S).stdout
    names = {}
    for l in out.splitlines():
        m = re.match(r'^0x([0-9a-f]+): +(bl|b) +0x([0-9a-f]+) +(\S+)', l)
        if m: names[int(m.group(3), 16)] = m.group(4)
    return names

def norm_name(n):
    if n.startswith('msgSend:'): return 'M:' + n[8:]
    return 'F:' + n.lstrip('_')

class Trace:
    def __init__(s): s.calls = []; s.ret = None

def run_emu(c, names, seed, args, case_mem):
    code = dump(c.ver, c.start & ~0xfff, ((c.end - (c.start & ~0xfff)) + 0xfff) & ~0xfff)
    uc = Uc(UC_ARCH_ARM64, UC_MODE_ARM)
    uc.reg_write(UC_ARM64_REG_CPACR_EL1, 0x300000)
    base = c.start & ~0xfff
    uc.mem_map(base, len(code)); uc.mem_write(base, code)
    uc.mem_map(SELF_EMU, SELF_SZ); uc.mem_map(OBJ_EMU, OBJ_SZ); uc.mem_map(STK_EMU, 0x100000)
    selfw, objw = case_mem
    uc.mem_write(SELF_EMU, b''.join(struct.pack('<Q', enc(w, OBJ_EMU)) for w in selfw))
    uc.mem_write(OBJ_EMU, b''.join(struct.pack('<Q', enc(w, OBJ_EMU)) for w in objw))
    mapped = set()
    def unm(uc, access, address, size, value, ud):
        pg = address & ~0xfff
        if pg in mapped: return False
        try: data = dump(c.ver, pg, 0x1000)
        except AssertionError: return False
        uc.mem_map(pg, 0x1000); uc.mem_write(pg, fix_ptrs(data)); mapped.add(pg); return True
    uc.hook_add(UC_HOOK_MEM_READ_UNMAPPED | UC_HOOK_MEM_WRITE_UNMAPPED | UC_HOOK_MEM_FETCH_UNMAPPED, unm)
    uc.reg_write(UC_ARM64_REG_SP, SP0_EMU); uc.reg_write(UC_ARM64_REG_X30, 0xdead0000)
    xi = 0; di = 0
    soff = 0
    for kind, v in zip(c.sig, args):
        if kind == 'x':
            uc.reg_write(UC_ARM64_REG_X0 + xi, v); xi += 1
        elif kind == 'd':
            uc.reg_write(UC_ARM64_REG_D0 + di, d2i(v)); di += 1
        else:
            sz = {'b': 1, 'w': 4, 'q': 8}[kind]; soff = (soff + sz - 1) // sz * sz
            uc.mem_write(SP0_EMU + soff, int(v & ((1 << (8 * sz)) - 1)).to_bytes(sz, 'little')); soff += sz
    tr = Trace(); idx = [0]
    ctx = a2c.Ctx(c.ver)
    def N(v):
        if v == 0x72000000: return ('SEL',)
        if SELF_EMU <= v < SELF_EMU + SELF_SZ: return ('S', v - SELF_EMU)
        if OBJ_EMU <= v < OBJ_EMU + OBJ_SZ: return ('O', v - OBJ_EMU)
        if SP0_EMU - 0x4000 <= v < SP0_EMU + 0x100: return ('K', v - SP0_EMU)
        if v >= (1 << 44) and (v >> 60) == 0 and (v >> 52) == 0: return ('CLS', '?')   # chained (PAC / diversity) class reference read from the cache data: class identity is not decoded here
        if 0x180000000 <= v < 0x200000000:
            sec = ctx.a2s2(v)[1]
            if 'objc_data' in sec: return ('CLS', '?')
            if 'cfstring' in sec: return ('STR', ctx.cfstr(v))
            if 'cstring' in sec or 'methname' in sec: return ('STR', ctx.cstring(v))
        return v
    def callout(nm, addr):
        n = names[addr]
        x = [uc.reg_read(UC_ARM64_REG_X0 + i) for i in range(8)]
        r = re.match(r'_objc_(retain|release)_x(\d+)$', n)
        if r:
            if r.group(1) == 'retain': uc.reg_write(UC_ARM64_REG_X0, uc.reg_read(UC_ARM64_REG_X0 + int(r.group(2))))
            return
        if n.lstrip('_') in ('objc_claimAutoreleasedReturnValue', 'objc_retainAutoreleasedReturnValue', 'objc_autoreleaseReturnValue', 'objc_retain', 'objc_autorelease', 'objc_unsafeClaimAutoreleasedReturnValue', 'objc_retainAutorelease', 'objc_retainAutoreleaseReturnValue'): return
        if n.lstrip('_') == 'objc_release': return
        if n.lstrip('_') in ('objc_storeStrong', 'objc_enumerationMutation'):
            tr.calls.append((norm_name(n), tuple(N(v) for v in x[:2]), (), ())); return
        d = [uc.reg_read(UC_ARM64_REG_D0 + i) for i in range(8)]
        kind = c.kinds_at.get(callout.pc, 'x')
        if n.startswith('msgSend:'): uc.reg_write(UC_ARM64_REG_X1, 0x72000000); x[1] = 0x72000000
        xs_ = tuple(N(v) for v in x)
        sp_ = uc.reg_read(UC_ARM64_REG_SP)
        stk_ = tuple(N(struct.unpack('<Q', bytes(uc.mem_read(sp_ + 8 * j, 8)))[0]) for j in range(12))
        tr.calls.append((norm_name(n), xs_, tuple(d), stk_))
        k = idx[0]; idx[0] += 1
        if n == 'msgSend:countByEnumeratingWithState:objects:count:':
            st = x[2]; first = struct.unpack('<Q', bytes(uc.mem_read(st, 8)))[0] == 0
            if first:
                cnt = 1 + rnd(seed, 'enum', k).randrange(3)
                uc.mem_write(OBJ_EMU + 0xf000, b''.join(struct.pack('<Q', OBJ_EMU + 0x100 * (1 + j)) for j in range(4)))
                uc.mem_write(st, struct.pack('<QQQ', 1, OBJ_EMU + 0xf000, OBJ_EMU + 0xf100))
                uc.reg_write(UC_ARM64_REG_X0, cnt)
            else: uc.reg_write(UC_ARM64_REG_X0, 0)
            return
        x0, ds = ret_values(seed, norm_name(n), k, kind)
        if kind == 'v': return
        if kind == 'x':
            uc.reg_write(UC_ARM64_REG_X0, enc(x0, OBJ_EMU))
        else:
            nd = {'d': 1, 'size': 2, 'rect': 4}[kind]
            for j in range(nd): uc.reg_write(UC_ARM64_REG_D0 + j, d2i(ds[j]))
    callout.pc = 0
    def code_hook(uc, addr, size, ud):
        if addr == 0xdead0000:
            tr.ret = (uc.reg_read(UC_ARM64_REG_X0), uc.reg_read(UC_ARM64_REG_D0), uc.reg_read(UC_ARM64_REG_D1)); uc.emu_stop(); return
        if c.start <= addr < c.end:
            insn = struct.unpack('<I', uc.mem_read(addr, 4))[0]
            if insn in (0xd65f0fff, 0xd65f03c0):
                tr.ret = (uc.reg_read(UC_ARM64_REG_X0), uc.reg_read(UC_ARM64_REG_D0), uc.reg_read(UC_ARM64_REG_D1)); uc.emu_stop()
            return
        if addr in names:
            # the call came from the instruction before: its address is lr - 4
            callout.pc = uc.reg_read(UC_ARM64_REG_X30) - 4
            callout(names[addr], addr)
            lr_ = uc.reg_read(UC_ARM64_REG_X30)
            if lr_ == 0xdead0000:    # tail call out of the function
                tr.ret = (uc.reg_read(UC_ARM64_REG_X0), uc.reg_read(UC_ARM64_REG_D0), uc.reg_read(UC_ARM64_REG_D1)); uc.emu_stop(); return
            uc.reg_write(UC_ARM64_REG_PC, lr_)
            return
        tr.err = 'pc outside %x' % addr; uc.emu_stop()
    uc.hook_add(UC_HOOK_CODE, code_hook)
    tr.err = None
    try: uc.emu_start(c.start, 0, count=2000000)
    except UcError as e: tr.err = 'uc %s pc=%x' % (e, uc.reg_read(UC_ARM64_REG_PC))
    mem = bytes(uc.mem_read(SELF_EMU, SELF_SZ))
    tr.mem = [N(struct.unpack_from('<Q', mem, o)[0]) for o in range(0, SELF_SZ, 8)]
    tr.omem = [N(struct.unpack_from('<Q', bytes(uc.mem_read(OBJ_EMU, 0x800)), o)[0]) for o in range(0, 0x800, 8)]
    return tr, N

# --------------------------------------------------------------- lifted side
CB = ctypes.CFUNCTYPE(None, ctypes.c_int, ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_uint64 * 2))
IV = ctypes.CFUNCTYPE(ctypes.c_long, ctypes.c_char_p)

def build_lifted(c, gen_file, ivmap_sig):
    exp = '''
void run(void *self, void *a1, void *a2, void *a3, void *a4, double *dd) {
    %s
}
''' % ('(void)0;')
    return None

def run_lifted(c, lib, kinds_at, seed, args, case_mem, ivmap):
    libc = ctypes.CDLL(None); libc.mmap.restype = ctypes.c_void_p
    libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long]
    for a_, n_ in ((SELF_EMU, SELF_SZ), (OBJ_EMU, OBJ_SZ)):
        r_ = libc.mmap(a_, n_, 3, 0x32 | 0x10, -1, 0)   # PROT_READ|WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED
        assert r_ == a_, hex(r_ or 0)
    selfb = SELF_EMU; objb = OBJ_EMU
    selfbuf = (ctypes.c_uint8 * SELF_SZ).from_address(selfb); objbuf = (ctypes.c_uint8 * OBJ_SZ).from_address(objb)
    selfw, objw = case_mem
    ctypes.memmove(selfb, b''.join(struct.pack('<Q', enc(w, objb)) for w in selfw), SELF_SZ)
    ctypes.memmove(objb, b''.join(struct.pack('<Q', enc(w, objb)) for w in objw), OBJ_SZ)
    sp0 = ctypes.c_uint64.in_dll(lib, 'lift_sp0')
    nstr = ctypes.c_int.in_dll(lib, 'lift_dbg_nstrs').value
    strp = ctypes.POINTER(ctypes.c_void_p).in_dll(lib, 'lift_dbg_strs')
    strmap = {strp[i]: ('STR', ctypes.string_at(strp[i]).decode()) for i in range(nstr) if strp[i]}
    ncls = ctypes.c_int.in_dll(lib, 'lift_dbg_ncls').value
    clsp = ctypes.POINTER(ctypes.c_void_p).in_dll(lib, 'lift_dbg_cls')
    nsel = ctypes.c_int.in_dll(lib, 'lift_dbg_nsels').value
    selp = ctypes.POINTER(ctypes.c_void_p).in_dll(lib, 'lift_dbg_sels')
    for i in range(nsel):
        if selp[i]: strmap[selp[i]] = ('SEL',)
    for i in range(ncls):
        if clsp[i]: strmap[clsp[i]] = ('CLS', '?')
    tr = Trace(); idx = [0]
    def N(v):
        if v in strmap: return strmap[v]
        if selfb <= v < selfb + SELF_SZ: return ('S', v - selfb)
        if objb <= v < objb + OBJ_SZ: return ('O', v - objb)
        if sp0.value - 0x4000 <= v < sp0.value + 0x100: return ('K', v - sp0.value)
        return v
    kind_p = ctypes.c_char_p.in_dll(lib, 'lift_kind')
    def cb(isMsg, name, X, VR):
        n = name.decode()
        nm = ('M:' + n) if isMsg else ('F:' + n.lstrip('_'))
        kind = kind_p.value.decode() if kind_p.value else 'x'
        if not isMsg and n.lstrip('_') in ('objc_enumerationMutation',):
            tr.calls.append((nm, tuple(N(X[i]) for i in range(2)), (), ())); return
        d = tuple(VR[i][0] for i in range(8))
        xs_ = tuple(N(X[i]) for i in range(8))
        stk_ = tuple(N(struct.unpack('<Q', ctypes.string_at(X[31] + 8 * j, 8))[0]) for j in range(12))
        tr.calls.append((nm, xs_, d, stk_))
        k = idx[0]; idx[0] += 1
        if isMsg and n == 'countByEnumeratingWithState:objects:count:':
            st = X[2]; first = struct.unpack('<Q', ctypes.string_at(st, 8))[0] == 0
            if first:
                cnt = 1 + rnd(seed, 'enum', k).randrange(3)
                ctypes.memmove(objb + 0xf000, b''.join(struct.pack('<Q', objb + 0x100 * (1 + j)) for j in range(4)), 32)
                ctypes.memmove(st, struct.pack('<QQQ', 1, objb + 0xf000, objb + 0xf100), 24)
                X[0] = cnt
            else: X[0] = 0
            return
        x0, ds = ret_values(seed, nm, k, kind)
        if kind == 'v': return
        if kind == 'x': X[0] = enc(x0, objb)
        else:
            nd = {'d': 1, 'size': 2, 'rect': 4}[kind]
            for j in range(nd): VR[j][0] = d2i(ds[j]); VR[j][1] = 0
    cbo = CB(cb); ivo = IV(lambda n: ivmap[n.decode()])
    lib.lift_set(cbo, ivo)
    xs = []; ds_ = []; sts = []
    for kind, v in zip(c.sig, args):
        (xs if kind == 'x' else (ds_ if kind == 'd' else sts)).append(v)
    # call run(self-derived args) : integer args as pointers into the buffers
    xs = [selfb if v == SELF_EMU else (objb + (v - OBJ_EMU) if OBJ_EMU <= v < OBJ_EMU + OBJ_SZ else v) for v in xs]
    xs += [0] * (8 - len(xs)); ds_ += [0.0] * (8 - len(ds_))
    lib.run.restype = ctypes.c_uint64
    sts += [0] * (4 - len(sts))
    lib.run.argtypes = [ctypes.c_uint64] * 8 + [ctypes.c_double] * 8 + [ctypes.c_uint64] * 4
    r = lib.run(*xs, *ds_, *sts)
    tr.ret = (r, None, None)
    mem = bytes(selfbuf)
    tr.mem = [N(struct.unpack_from('<Q', mem, o)[0]) for o in range(0, SELF_SZ, 8)]
    tr.omem = [N(struct.unpack_from('<Q', bytes(objbuf[:0x800]), o)[0]) for o in range(0, 0x800, 8)]
    tr.err = None
    return tr, N

def main():
    ver, st, en, cname, sig, retk, cls, nseeds = sys.argv[1], int(sys.argv[2], 16), int(sys.argv[3], 16), sys.argv[4], sys.argv[5], sys.argv[6], sys.argv[7], int(sys.argv[8])
    cls = None if cls == '-' else cls
    kinds_ = {}
    if '--kinds' in sys.argv:
        for kv in sys.argv[sys.argv.index('--kinds') + 1].split(','):
            k_, v_ = kv.split('='); kinds_['msgSend:' + k_] = v_
    L = a2c.Lift(ver, st, en, cname, sig, retk, kinds_, cls)
    head, fn = L.generate()
    a2c.save_memo()
    for w in L.stats['warn']: print('WARN', w)
    open(W + cname + '.tc.c', 'w').write('#include "liftest.h"\n' + head + '\n' + fn + '\nconst char *const *lift_dbg_strs = %s_strs; int lift_dbg_nstrs = (int)(sizeof(%s_strs) / sizeof(%s_strs[0])); const char *const *lift_dbg_cls = %s_cls; int lift_dbg_ncls = (int)(sizeof(%s_cls) / sizeof(%s_cls[0])); const char *const *lift_dbg_sels = %s_sels; int lift_dbg_nsels = (int)(sizeof(%s_sels) / sizeof(%s_sels[0]));\n' % (cname, cname, cname, cname, cname, cname, cname, cname, cname) + '''
void run(uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, uint64_t st0, uint64_t st1, uint64_t st2, uint64_t st3) {
    %s
}
''' % build_call(cname, sig, retk))
    # make run return the integer result
    src = open(W + cname + '.tc.c').read().replace('void run(uint64_t a0', 'uint64_t run(uint64_t a0')
    src = src.replace('    ' + build_call(cname, sig, retk), '    ' + build_call(cname, sig, retk, ret=True))
    open(W + cname + '.tc.c', 'w').write(src)
    so = W + cname + '.tc.so'
    subprocess.check_call(['gcc', '-O1', '-shared', '-fPIC', '-w', '-I', T, W + cname + '.tc.c', '-o', so, '-lm'])
    lib = ctypes.CDLL(so)
    # ivar offsets: every spec Class.name -> offset of this version's table
    tab = a2c.ivar_tables(ver)
    ivmap = {}
    ivline = [l for l in head.splitlines() if '_ivs[]' in l][0]
    for spec in re.findall(r'"([A-Za-z0-9_]+\.[A-Za-z0-9_]+)"', ivline):
        cl, nm_ = spec.split('.', 1)
        c0 = cl
        while c0 and c0 in tab:
            hit = [o for n_, o, sz in tab[c0]['iv'] if n_ == nm_]
            if hit: ivmap[spec] = hit[0]; break
            c0 = tab[c0]['super']
        else:
            ivmap[spec] = -1
    print('ivmap', ivmap)
    names = emu_names(ver, st, en)
    c = Case(ver, st, en, cname, sig, retk, cls, L.kinds_at)
    bad = 0; ncalls = 0; paths = set()
    for seed in range(nseeds):
        r = random.Random(seed)
        selfw = mem_words(seed, SELF_SZ // 8, 'self'); objw = mem_words(seed, OBJ_SZ // 8, 'obj')
        args = []
        for kind in c.sig:
            if kind == 'd': args.append(r.choice(DVALS))
            elif kind in ('b', 'w', 'q'): args.append(r.choice([0, 1]))
            else: args.append(r.choice([SELF_EMU, OBJ_EMU + 0x100 * r.randrange(1, 40), 0, 1]))
        args[0:1] = [SELF_EMU] if c.sig and c.sig[0] == 'x' else args[0:1]
        te, Ne = run_emu(c, names, seed, args, (selfw, objw))
        tl, Nl = run_lifted(c, lib, L.kinds_at, seed, args, (selfw, objw), ivmap)
        ncalls += len(te.calls)
        paths.add(tuple(x[0] for x in te.calls))
        ok = te.err is None and te.calls == tl.calls and te.mem == tl.mem and te.omem == tl.omem and (retk in ('v', 'd', 'size', 'rect') or Ne(te.ret[0]) == Nl(tl.ret[0]))
        if not ok:
            bad += 1
            if bad <= 3:
                print('MISMATCH seed', seed, 'emu err', te.err)
                for i, (a, b) in enumerate(zip(te.calls, tl.calls)):
                    if a != b: print(' first call difference at', i, '\n  emu ', a, '\n  lift', b); break
                else:
                    print(' emu tail', [c_[0] for c_ in te.calls][-3:], 'lift tail', [c_[0] for c_ in tl.calls][-3:])
                    print(' calls', len(te.calls), len(tl.calls), 'mem equal', te.mem == tl.mem, 'omem equal', te.omem == tl.omem, 'ret', Ne(te.ret[0]), Nl(tl.ret[0]))
                for i_, (a_, b_) in enumerate(zip(te.mem, tl.mem)):
                    if a_ != b_: print('  mem word', hex(i_ * 8), 'emu', a_, 'lift', b_); break
    print('%s: seeds %d, mismatches %d, total calls compared %d, distinct call sequences %d' % (cname, nseeds, bad, ncalls, len(paths)))

def build_call(cname, sig, retk, ret=False):
    sg = parse_sig(sig)
    xs = ['a%d' % i for i in range(sum(1 for k in sg if k == 'x'))]
    ds = ['d%d' % i for i in range(sum(1 for k in sg if k == 'd'))]
    # ABI order of the lifted function parameters = order in sig
    args = []; xi = 0; di = 0; si = 0
    for k in sg:
        if k == 'x': args.append('a%d' % xi); xi += 1
        elif k == 'd': args.append('d%d' % di); di += 1
        else: args.append('(%s)st%d' % ({'b': 'uint8_t', 'w': 'uint32_t', 'q': 'uint64_t'}[k], si)); si += 1
    call = '%s(%s)' % (cname, ', '.join(args))
    if retk == 'x': return ('return %s;' % call) if ret else '(void)%s;' % call
    if retk == 'v': return ('%s; return 0;' % call) if ret else '%s;' % call
    if retk == 'd': return ('(void)%s; return 0;' % call) if ret else '(void)%s;' % call
    return ('(void)%s; return 0;' % call) if ret else '(void)%s;' % call

if __name__ == '__main__': main()
