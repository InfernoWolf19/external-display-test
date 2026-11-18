#!/usr/bin/env python3
"""tracecmp.py <ver> <start> <end> <cname> <sig> <retkind> <cls|-> <nseeds> [argkinds]
Differential test of a2c.py output: the original machine code (Unicorn) and the lifted C (gcc, test prelude) run on the same modelled environment
(same fake objects, same deterministic answers for every call); the traces of all calls (callee, x0..x7, d0..d7) and the result / the written
object memory are compared.  Calls are identified by name; answers depend on (seed, call index, callee name) only."""
import sys, os, re, struct, ctypes, subprocess, random, hashlib
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)) + '/..')
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

def is_obj_sel(name):
    if not name.startswith('M:'): return False
    a2c.ret_kinds('162')
    ts = a2c.RAWT.get(name[2:])
    if not ts: return True            # unknown selector: assume an object (a dereferenced small integer would crash the C side)
    return any(('*' in x) or x.strip() in ('id', 'Class') or x.startswith('id ') or x.startswith('id<') or x.startswith('id /*') for x in ts)
def ret_values(seed, name, idx, kind):
    r = rnd(seed, name, idx)
    c = r.random()
    if is_obj_sel(name) or name.startswith('F:objc_alloc') or name in ('F:SBSafeCast', 'F:objc_opt_class', 'F:objc_msgSendSuper2', 'F:objc_opt_new', 'F:objc_loadWeakRetained'):
        x0 = ('i', 0) if c < 0.3 else ('o', r.randrange(1, 40))
    elif c < 0.3: x0 = ('i', 0)
    elif c < 0.5: x0 = ('i', 1)
    elif c < 0.6: x0 = ('i', r.choice([2, 3, 4, 8]))
    else: x0 = ('i', r.randrange(1, 3))
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

PACRE = re.compile(r'(pac|aut)([id][ab])(z?)$')
NSB = ('SYM', 'NSConcreteStackBlock')
def n_mod(N, m):
    hi = (m >> 48) & 0xffff
    return (N(m & 0xffffffffffff), hi) if hi else N(m)
DATASYM = {}      # data symbol -> the NSString constant it holds (--datasyms kCAFilterBox=box): the Unicorn side reads the real CFString, the lifted side a cell
def isk(n): return isinstance(n, tuple) and n[0] == 'K'
def blk_snapshot(rd, N2, addr):
    """normalised image of the block literal at addr (isa, flags, invoke, descriptor, captured words) when addr holds a block isa, else None"""
    if N2(rd(addr)) != NSB: return None
    d = N2(rd(addr + 24)); size = d[2] if isinstance(d, tuple) and d[0] == 'DESC' else 0x28
    out = [NSB, rd(addr + 8), N2(rd(addr + 16)), d]
    for o in range(0x20, size, 8): out.append(N2(rd(addr + o)))
    return tuple(out)

class Case:
    def __init__(s, ver, start, end, cname, sig, retk, cls, kinds_at, locals_=None):
        s.ver, s.start, s.end, s.cname, s.sig, s.retk, s.cls, s.kinds_at = ver, start, end, cname, parse_sig(sig), retk, cls, kinds_at
        s.locals = locals_ or {}

# --------------------------------------------------------------- emulator side
def emu_names(ver, start, end):
    S = a2c.S
    cache = a2c.DSC[ver]
    ann = S + ('annot162.py' if ver == '162' else 'annot160b.py')
    out = subprocess.run(['python3', ann, cache, hex(start), str((end - start) // 4 + 8)], capture_output=True, text=True, cwd=S).stdout
    names = {}
    for l in out.splitlines():
        m = re.match(r'^0x([0-9a-f]+): +(bl|b) +0x([0-9a-f]+) +(\S+)', l)
        if m: names[int(m.group(3), 16)] = m.group(4)[2:] if m.group(4).startswith('j__') else m.group(4)
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
    pacs = {}
    from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
    md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    for i_ in md.disasm(bytes(code[c.start - base:c.end - base]), c.start):
        if PACRE.match(i_.mnemonic):
            pacs[i_.address] = (i_.mnemonic, [x.strip() for x in i_.op_str.split(',')])
            uc.mem_write(i_.address, struct.pack('<I', 0xd503201f))      # nop: signing is the identity, the operands are logged (the lifted LIFT_PAC logs the same)
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
        if v in c.locals: return ('LFN', c.locals[v])
        if v == 0x72000000 or 0x180000000 <= v < 0x188000000: return ('SEL',)   # selector (uniqued method name region of the cache)
        if SELF_EMU <= v < SELF_EMU + SELF_SZ: return ('S', v - SELF_EMU)
        if OBJ_EMU <= v < OBJ_EMU + OBJ_SZ: return ('O', v - OBJ_EMU)
        if SP0_EMU - 0x4000 <= v < SP0_EMU + 0x100: return ('K', v - SP0_EMU)
        if v >= (1 << 44) and (v >> 60) == 0 and (v >> 52) == 0:
            sy_ = ctx.a2s2(v & 0x7ffffffffff)[0]
            if sy_.lstrip('_') == 'NSConcreteStackBlock': return NSB
            return ('CLS', sy_[len('_OBJC_CLASS_$_'):]) if sy_.startswith('_OBJC_CLASS_$_') else ('CLS', '?')   # chained (PAC / diversity) class reference read from the cache data: class identity is not decoded here
        if 0x180000000 <= v < 0x200000000:
            sec = ctx.a2s2(v)[1]
            if 'objc_data' in sec:
                sy_ = ctx.a2s2(v)[0]
                if sy_.lstrip('_') == 'NSConcreteStackBlock': return NSB
                return ('CLS', sy_[len('_OBJC_CLASS_$_'):]) if sy_.startswith('_OBJC_CLASS_$_') else ('CLS', '?')
            if 'cfstring' in sec: return ('STR', ctx.cfstr(v))
            if 'cstring' in sec or 'methname' in sec or 'oslogstring' in sec: return ('STR', ctx.cstring(v))
            if ctx.a2s2(v)[0].lstrip('_') == 'NSConcreteStackBlock': return NSB
            if 'const' in sec:
                try:
                    w = struct.unpack('<5Q', ctx.read(v, 40))
                    dp = lambda q: (0x180000000 + (q & 0xffffffff)) if q >> 63 else (q & 0x7ffffffffff)
                    sg = ctx.cstring(dp(w[2])) if not (0x18 <= w[1] <= 0x400 and 0x180000000 <= dp(w[2]) < 0x200000000 and 'text' in ctx.a2s2(dp(w[2]))[1]) else ctx.cstring(dp(w[4]))
                    if 0x18 <= w[1] <= 0x400 and sg and all(32 <= ord(ch) < 127 for ch in sg): return ('DESC', sg, w[1])
                except Exception: pass
        return v
    def callout(nm, addr):
        n = names[addr]
        x = [uc.reg_read(UC_ARM64_REG_X0 + i) for i in range(8)]
        r = re.match(r'_objc_(retain|release)_x(\d+)$', n)
        if r:
            v_ = uc.reg_read(UC_ARM64_REG_X0 + int(r.group(2)))
            tr.calls.append(('E:' + r.group(1), (N(v_),), (), ()))
            if r.group(1) == 'retain': uc.reg_write(UC_ARM64_REG_X0, v_)
            return
        OWN = {'objc_claimAutoreleasedReturnValue': 'claim', 'objc_retainAutoreleasedReturnValue': 'claim', 'objc_autoreleaseReturnValue': 'autoreleaseRV', 'objc_retain': 'retain', 'objc_autorelease': 'autorelease',
               'objc_unsafeClaimAutoreleasedReturnValue': 'unsafeclaim', 'objc_retainAutorelease': 'retainAutorelease', 'objc_retainAutoreleaseReturnValue': 'retainAutoreleaseRV', 'objc_release': 'release'}
        if n.lstrip('_') in OWN:
            tr.calls.append(('E:' + OWN[n.lstrip('_')], (N(x[0]),), (), ())); return
        if n.lstrip('_') == 'objc_storeStrong':
            tr.calls.append(('E:storeStrong', (N(x[0]), N(x[1])), (), ()))
            uc.mem_write(x[0], struct.pack('<Q', x[1])); return
        if n.lstrip('_') == 'objc_enumerationMutation':
            tr.calls.append((norm_name(n), tuple(N(v) for v in x[:2]), (), ())); return
        d = [uc.reg_read(UC_ARM64_REG_D0 + i) for i in range(8)]
        kind = c.kinds_at.get(callout.pc, 'x')
        if n.startswith('msgSend:'): uc.reg_write(UC_ARM64_REG_X1, 0x72000000); x[1] = 0x72000000
        xs_ = tuple(N(v) for v in x)
        if n.lstrip('_').startswith('os_log') and n.lstrip('_').endswith('_impl'): xs_ = (('DSO',),) + xs_[1:]
        if n.lstrip('_') == 'objc_msgSendSuper2': xs_ = xs_[:1] + (('SEL',),) + xs_[2:]
        sp_ = uc.reg_read(UC_ARM64_REG_SP)
        stk_ = tuple(N(struct.unpack('<Q', bytes(uc.mem_read(sp_ + 8 * j, 8)))[0]) for j in range(12))
        blks = tuple(b for b in (blk_snapshot(lambda a_: struct.unpack('<Q', bytes(uc.mem_read(a_, 8)))[0], N, v) for v in x[:8] if isk(N(v))) if b)
        if n.lstrip('_') == 'objc_msgSendSuper2': blks = blks + (('SUPER', N(struct.unpack('<Q', bytes(uc.mem_read(x[0], 8)))[0]), N(struct.unpack('<Q', bytes(uc.mem_read(x[0] + 8, 8)))[0])),)
        tr.calls.append((norm_name(n), xs_, tuple(d), stk_) + ((blks,) if blks else ()))
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
        if kind in ('m48', 'm128'):
            nb = int(kind[1:]); buf = b''.join(struct.pack('<d', ds[j % 4]) for j in range(nb // 8))
            uc.mem_write(uc.reg_read(UC_ARM64_REG_X8), buf); return
        if kind == 'x':
            uc.reg_write(UC_ARM64_REG_X0, enc(x0, OBJ_EMU))
        else:
            nd = {'d': 1, 'size': 2, 'rect': 4}[kind]
            for j in range(nd): uc.reg_write(UC_ARM64_REG_D0 + j, d2i(ds[j]))
    callout.pc = 0
    def code_hook(uc, addr, size, ud):
        if addr in pacs:
            mn_, ops_ = pacs[addr]
            def rv(o):
                return 0 if o in ('xzr',) else uc.reg_read(UC_ARM64_REG_X0 + int(o[1:])) if o[0] == 'x' else uc.reg_read(UC_ARM64_REG_SP)
            pm_ = PACRE.match(mn_)
            tr.calls.append(('E:' + pm_.group(1) + pm_.group(2), (N(rv(ops_[0])), n_mod(N, rv(ops_[1])) if len(ops_) > 1 else 0), (), ()))
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
        if clsp[i]: strmap[clsp[i]] = ('CLS', ctypes.string_at(clsp[i]).decode())
    cstrs = (ctypes.c_void_p * 256).in_dll(lib, 'lift_cstrs')
    cells = (ctypes.c_uint64 * 128).in_dll(lib, 'lift_cells')
    def cellmap():
        for i in range(ctypes.c_int.in_dll(lib, 'lift_ncells').value):
            nm_ = ctypes.string_at(cells[2 * i + 1]).decode().lstrip('_')
            strmap[ctypes.addressof(cells) + 16 * i] = ('SYM', nm_)
            strmap[cells[2 * i]] = ('STR', DATASYM[nm_]) if nm_ in DATASYM else ('SYMVAL', nm_)
    fnaddrs = (ctypes.c_uint64 * 32).in_dll(lib, 'lift_fnaddrs'); fnnames = (ctypes.c_char_p * 16).in_dll(lib, 'lift_fnnames')
    descs = (ctypes.c_uint64 * 48).in_dll(lib, 'lift_descs')
    tr = Trace(); idx = [0]
    def N(v):
        cellmap()
        for i_ in range(ctypes.c_int.in_dll(lib, 'lift_ncstr').value):
            if cstrs[i_] == v: return ('STR', ctypes.string_at(cstrs[i_]).decode())
        for i_ in range(ctypes.c_int.in_dll(lib, 'lift_nfn').value):
            if fnaddrs[2 * i_] == v: return ('LFN', fnnames[i_].decode())
        for i_ in range(ctypes.c_int.in_dll(lib, 'lift_ndesc').value):
            if descs[3 * i_] == v: return ('DESC', ctypes.string_at(descs[3 * i_ + 1]).decode(), descs[3 * i_ + 2])
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
        if n.lstrip('_').startswith('os_log') and n.lstrip('_').endswith('_impl'): xs_ = (('DSO',),) + xs_[1:]
        if not isMsg and n.lstrip('_') == 'objc_msgSendSuper2': xs_ = xs_[:1] + (('SEL',),) + xs_[2:]
        stk_ = tuple(N(struct.unpack('<Q', ctypes.string_at(X[31] + 8 * j, 8))[0]) for j in range(12))
        blks = tuple(b for b in (blk_snapshot(lambda a_: struct.unpack('<Q', ctypes.string_at(a_, 8))[0], N, X[i]) for i in range(8) if isk(N(X[i]))) if b)
        if n.lstrip('_') == 'objc_msgSendSuper2': blks = blks + (('SUPER', N(struct.unpack('<Q', ctypes.string_at(X[0], 8))[0]), N(struct.unpack('<Q', ctypes.string_at(X[0] + 8, 8))[0])),)
        tr.calls.append((nm, xs_, d, stk_) + ((blks,) if blks else ()))
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
        if kind in ('m48', 'm128'):
            nb = int(kind[1:]); ctypes.memmove(X[8], b''.join(struct.pack('<d', ds[j % 4]) for j in range(nb // 8)), nb); return
        if kind == 'x': X[0] = enc(x0, objb)
        else:
            nd = {'d': 1, 'size': 2, 'rect': 4}[kind]
            for j in range(nd): VR[j][0] = d2i(ds[j]); VR[j][1] = 0
    def ev(what, a, b):
        w = what.decode()
        if PACRE.match(w): tr.calls.append(('E:' + w, (N(a), n_mod(N, b)), (), ()))
        elif w == 'storeStrong': tr.calls.append(('E:' + w, (N(a), N(b)), (), ()))
        else: tr.calls.append(('E:' + w, (N(a),), (), ()))
    EV = ctypes.CFUNCTYPE(None, ctypes.c_char_p, ctypes.c_uint64, ctypes.c_uint64)
    evo = EV(ev); lib.lift_set_ev(evo)
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
    if '--datasyms' in sys.argv:
        for kv in sys.argv[sys.argv.index('--datasyms') + 1].split(','):
            k_, v_ = kv.split('='); DATASYM[k_] = v_
    locs = {}; lbody = ''
    if '--locals' in sys.argv:
        for spec in sys.argv[sys.argv.index('--locals') + 1].split(','):
            a_, e_, cn_, sg_, rk_ = spec.split(':'); sg_ = sg_.replace('+', ',')
            LL = a2c.Lift(ver, int(a_, 16), int(e_, 16), cn_, sg_, rk_, {}, cls)
            LL.locals = dict(locs)
            hh, ff = LL.generate(); lbody += hh + '\n' + ff + '\n'; locs[int(a_, 16)] = cn_
            for w in LL.stats['warn']: print('WARN', cn_, w)
    L = a2c.Lift(ver, st, en, cname, sig, retk, kinds_, cls)
    L.locals = dict(locs)
    head, fn = L.generate()
    a2c.save_memo()
    for w in L.stats['warn']: print('WARN', w)
    open(W + cname + '.tc.c', 'w').write('#include "liftest.h"\n' + lbody + head + '\n' + fn + '\nconst char *const *lift_dbg_fns = %s_fns; int lift_dbg_nfns = (int)(sizeof(%s_fns) / sizeof(%s_fns[0])); const char *const *lift_dbg_strs = %s_strs; int lift_dbg_nstrs = (int)(sizeof(%s_strs) / sizeof(%s_strs[0])); const char *const *lift_dbg_cls = %s_cls; int lift_dbg_ncls = (int)(sizeof(%s_cls) / sizeof(%s_cls[0])); const char *const *lift_dbg_sels = %s_sels; int lift_dbg_nsels = (int)(sizeof(%s_sels) / sizeof(%s_sels[0]));\n' % ((cname,) * 12) + '''
void run(uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3, uint64_t a4, uint64_t a5, uint64_t a6, uint64_t a7, double d0, double d1, double d2, double d3, double d4, double d5, double d6, double d7, uint64_t st0, uint64_t st1, uint64_t st2, uint64_t st3) {
    %s
}
''' % build_call(cname, sig, retk))
    # make run return the integer result
    src = open(W + cname + '.tc.c').read().replace('void run(uint64_t a0', 'uint64_t run(uint64_t a0')
    src = src.replace('    ' + build_call(cname, sig, retk), '    ' + build_call(cname, sig, retk, ret=True))
    open(W + cname + '.tc.c', 'w').write(src)
    so = W + cname + '.tc.so'
    subprocess.check_call(['gcc', '-g', '-O0', '-shared', '-fPIC', '-w', '-I', T, W + cname + '.tc.c', '-o', so, '-lm'])
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
    c = Case(ver, st, en, cname, sig, retk, cls, L.kinds_at, locs)
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
        if os.environ.get('TCDUMP') and seed == 0:
            for c_ in te.calls: print('EMU ', c_[0], c_[1][:3], c_[4:] if len(c_) > 4 else '')
            for c_ in tl.calls: print('LIFT', c_[0], c_[1][:3], c_[4:] if len(c_) > 4 else '')
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
