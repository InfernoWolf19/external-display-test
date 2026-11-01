#!/usr/bin/env python3
"""a2c.py : static recompiler arm64(e) function (from a dyld shared cache) -> portable C.

usage: a2c.py <160|162> <start-hex> <end-hex> <cname> <sig> [--ret KIND] [--kinds sel=kind,...] > out.c

sig: comma list of argument kinds in ABI order: x (integer register), d (double register).
     return kind: v | x | d | size (d0,d1) | rect (d0..d3)
The generated function keeps the machine code semantics 1:1 (registers are C variables, the stack is a
byte array, flags are explicit); calls go through macros resolved by the includer (device prelude or test prelude).
"""
import sys, re, os, json, struct, subprocess
sys.dont_write_bytecode = True
sys.path.insert(0, '/home/user/external-display-test/Backport162/tools/y26_classic_tree')
from emu_lib import dump, S, DSC
import capstone
from capstone import arm64 as A

W = '/tmp/claude-0/-home-user-external-display-test/y34work/'
MEMO_F = W + 'a2c_memo.json'
memo = json.load(open(MEMO_F)) if os.path.exists(MEMO_F) else {}
def save_memo(): json.dump(memo, open(MEMO_F, 'w'))

def run(a): return subprocess.run(a, capture_output=True, text=True).stdout

class Ctx:
    def __init__(s, ver):
        s.ver = ver; s.cache = DSC[ver]
    def a2s2(s, addr):
        k = 'a2sx%s:%x' % (s.ver, addr)
        if k in memo: return memo[k]
        o = subprocess.run([S + 'bin/ipsw', 'dsc', 'a2s', s.cache, hex(addr)], capture_output=True, text=True); o = o.stdout + o.stderr
        m = re.search(r'0x[0-9a-f]+: (\S+)', o); sym = m.group(1) if m else ''
        m2 = re.search(r'section=(\S+)', o); sec = m2.group(1) if m2 else ''
        memo[k] = [sym, sec]; return memo[k]
    def a2s(s, addr):
        k = 'a2s%s:%x' % (s.ver, addr)
        if k in memo: return memo[k]
        r = s.a2s2(addr)[0]
        memo[k] = r; return r
    def sel(s, addr):
        k = 'sel%s:%x' % (s.ver, addr)
        if k in memo: return memo[k]
        o = run([S + 'bin/sel', s.cache, hex(addr)]); m = re.search(r'-> "(.*)"', o)
        r = m.group(1) if m else ''; memo[k] = r; return r
    def cfstr(s, addr):
        k = 'cf%s:%x' % (s.ver, addr)
        if k in memo: return memo[k]
        o = run([S + 'bin/cfstr', s.cache, hex(addr)]); m = re.search(r'-> "(.*)"', o)
        r = m.group(1) if m else ''; memo[k] = r; return r
    def read(s, addr, n):
        pg = addr & ~0xfff
        d = dump(s.ver, pg, 0x1000)
        off = addr - pg
        assert off + n <= 0x1000
        return d[off:off + n]
    def cstring(s, addr):
        out = b''
        while len(out) < 512:
            pg = addr & ~0xfff; n = min(0x1000 - (addr - pg), 64)
            chunk = s.read(addr, n); z = chunk.find(b'\0')
            if z >= 0: out += chunk[:z]; return out.decode('utf8', 'replace')
            out += chunk; addr += n
        return out.decode('utf8', 'replace')
    def stubname(s, t):
        """name of a call target: 'msgSend:sel' / symbol / ''"""
        k = 'stub%s:%x' % (s.ver, t)
        if k in memo: return memo[k]
        code = dump(s.ver, t & ~0xfff, 0x1000); off = t & 0xfff
        md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
        ins = list(md.disasm(code[off:off + 20], t))
        r = ''
        if len(ins) >= 2 and ins[0].mnemonic == 'adrp' and ins[1].mnemonic == 'ldr' and ins[1].op_str.startswith('x1,'):
            m1 = re.match(r'x1, #(0x[0-9a-f]+)', ins[0].op_str)  # adrp x1, #page
            pg = int(ins[0].op_str.split('#')[1], 16)
            m2 = re.search(r'#(0x[0-9a-f]+|\d+)\]', ins[1].op_str)
            ref = pg + (int(m2.group(1), 0) if m2 else 0)
            r = 'msgSend:' + s.sel(ref)
        elif len(ins) >= 3 and ins[0].mnemonic == 'adrp' and ins[0].op_str.startswith('x16') and ins[1].mnemonic == 'add':
            pg = int(ins[0].op_str.split('#')[1], 16); o = int(ins[1].op_str.split('#')[-1], 0)
            r = s.a2s(pg + o)
        if not r: r = s.a2s(t)
        memo[k] = r; return r

_IVT = {}
def ivar_tables(ver):
    if ver in _IVT: return _IVT[ver]
    fn = S + ('sb160n_objc.txt' if ver == '160' else 'sb162_objc.txt')
    tab = {}; cur = None
    for l in open(fn, errors='replace'):
        m = re.match(r'@interface (\w+)(?: \((\w+)\))? *(?::\s*(\w+))?', l)
        if m and l.rstrip().endswith('{') or (m and '{ //' in l):
            cur = m.group(1); tab.setdefault(cur, {'super': m.group(3), 'iv': []}); continue
        if cur:
            if l.startswith('}'): cur = None; continue
            m2 = re.match(r'\s+(.+?)\b(\w+);\s*//\s*\+0x([0-9a-f]+)\s+0x([0-9a-f]+)', l)
            if m2: tab[cur]['iv'].append((m2.group(2), int(m2.group(4), 16), int(m2.group(3), 16)))
    _IVT[ver] = tab; return tab


_RET = {}
def ret_kinds(ver):
    """selector -> set of return kinds (x v d size rect STRUCT..) from the ObjC dumps of that build"""
    if ver in _RET: return _RET[ver]
    out = {}
    names = ['sb160n_objc.txt', 'UIKitCore160n.txt'] if ver == '160' else ['sb162_objc.txt', 'UIKitCore162.txt']
    for fnm in names:
        if not os.path.exists(S + fnm): continue
        for l in open(S + fnm, errors='replace'):
            if l.startswith('- (') or l.startswith('+ ('):
                d = 0; k = 2
                while k < len(l):
                    if l[k] == '(': d += 1
                    elif l[k] == ')':
                        d -= 1
                        if d == 0: break
                    k += 1
                t = l[3:k].strip()
                rest = l[k + 1:]
                for _ in range(4): rest = re.sub(r'\{[^{}]*\}', '', rest)
                b2 = re.sub(r'\((?:[^()]|\([^()]*\))*\)', '', rest.split(';')[0])
                parts = re.findall(r'(\w+):', b2)
                sel = (':'.join(parts) + ':') if parts else (b2.split()[0] if b2.split() else None)
                if not sel: continue
                if t.startswith('struct CGRect'): kd = 'rect'
                elif t.startswith('struct CGSize'): kd = 'size'
                elif t in ('double', 'CGFloat'): kd = 'd'
                elif t == 'void': kd = 'v'
                elif t.startswith('struct') or t.startswith('union'): kd = 'STRUCT ' + t[:40]
                else: kd = 'x'
                out.setdefault(sel, set()).add(kd)
    _RET[ver] = out; return out
FN_KINDS = {'BSRectWithSize': 'rect', 'BSSizeSwap': 'size', 'BSSizeRoundForScale': 'size', 'SBUICScaledRectWithOffsets': 'rect', 'BSRectWithSizeCenteredInRect': 'rect',
            'BSRectRoundForScale': 'rect', 'BSSizeScale': 'size', 'UIRectGetCenter': 'size', 'BSPointRoundForScale': 'size', 'CGRectIntegral': 'rect',
            'CGRectInset': 'rect', 'CGRectOffset': 'rect', 'UIEdgeInsetsInsetRect': 'rect', 'CGRectUnion': 'rect', 'CGRectIntersection': 'rect', 'CGSizeApplyAffineTransform': 'size'}

def rname(n):
    n = {'fp': 'x29', 'lr': 'x30'}.get(n, n)
    return n

class Lift:
    def __init__(s, ver, start, end, cname, sig, retk, kinds, cls=None):
        s.cls = cls
        s.ctx = Ctx(ver); s.ver = ver; s.start = start; s.end = end; s.cname = cname
        s.sig = sig; s.retk = retk; s.kinds = kinds
        code = dump(ver, start & ~0xfff, ((end - (start & ~0xfff)) + 0xfff) & ~0xfff)
        md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM); md.detail = True
        s.ins = list(md.disasm(code[start & 0xfff:(start & 0xfff) + (end - start)], start))
        assert len(s.ins) * 4 == end - start, (len(s.ins), (end - start) // 4)
        s.cval = {}   # reg -> const address
        s.baked = set(); s.kinds_at = {}; s.bakedsym = {}
        s.out = []
        s.globals = {}   # addr -> description
        s.stats = {'warn': []}
        s.callseq = 0
        s.sels = {}; s.cls = {}; s.ivs = {}; s.dbls = {}; s.strs = {}
        s.fns = {}
    # ---------------- operand helpers
    def reg(s, r, i):  # register name via capstone
        return rname(i.reg_name(r))
    def rd(s, i, o, signed=False):
        """C expression (uint64 / uint32) reading operand o (reg or imm), including shift/extend"""
        if o.type == A.ARM64_OP_IMM:
            return '0x%xull' % (o.imm & 0xffffffffffffffff)
        n = s.reg(o.reg, i)
        e = s.rdreg(n)
        e = s.apply_ext(o, e, n)
        return e
    def rdreg(s, n):
        if n in ('xzr',): return '0ull'
        if n in ('wzr',): return '0u'
        if n in ('sp', 'wsp'): return 'X[31]' if n == 'sp' else '(uint32_t)X[31]'
        if n[0] == 'x': return 'X[%d]' % int(n[1:])
        if n[0] == 'w': return '(uint32_t)X[%d]' % int(n[1:])
        raise Exception('reg ' + n)
    def apply_ext(s, o, e, n):
        is64 = n[0] == 'x' or n == 'sp'
        ext = o.ext
        if ext:
            m = {A.ARM64_EXT_UXTB: ('(uint8_t)', 0), A.ARM64_EXT_UXTH: ('(uint16_t)', 0), A.ARM64_EXT_UXTW: ('(uint32_t)', 0),
                 A.ARM64_EXT_UXTX: ('', 0), A.ARM64_EXT_SXTB: ('(int64_t)(int8_t)', 1), A.ARM64_EXT_SXTH: ('(int64_t)(int16_t)', 1),
                 A.ARM64_EXT_SXTW: ('(int64_t)(int32_t)', 1), A.ARM64_EXT_SXTX: ('(int64_t)', 1)}[ext]
            e = '(uint64_t)(%s(%s))' % (m[0], e)
        sh = o.shift
        if sh.type != A.ARM64_SFT_INVALID and sh.value >= 0:
            if sh.type == A.ARM64_SFT_LSL: e = '((%s) << %d)' % (e if is64 else '(uint32_t)(%s)' % e, sh.value)
            elif sh.type == A.ARM64_SFT_LSR: e = '((%s) >> %d)' % (e if is64 else '(uint32_t)(%s)' % e, sh.value)
            elif sh.type == A.ARM64_SFT_ASR:
                e = '((uint64_t)((int64_t)(%s) >> %d))' % (e, sh.value) if is64 else '((uint32_t)((int32_t)(%s) >> %d))' % (e, sh.value)
            elif sh.type == A.ARM64_SFT_MSL: raise Exception('msl')
            else: raise Exception('shift %d' % sh.type)
        return e
    def wr(s, i, n, val):
        if n in ('xzr', 'wzr'): return 'void_(%s);' % val if False else ''
        if n == 'sp': return 'X[31] = (uint64_t)(%s);' % val
        k = int(n[1:])
        if n[0] == 'x': return 'X[%d] = (uint64_t)(%s);' % (k, val)
        if n[0] == 'w': return 'X[%d] = (uint32_t)(%s);' % (k, val)
        raise Exception('wr ' + n)
    # ---------------- floating point registers: V[n][0/1] = low/high 64 bits
    def fp_is(s, n): return n[0] in 'dsqvbh' and n[1:].isdigit()
    def fpidx(s, n): return int(n[1:])
    def frd(s, n):
        k = s.fpidx(n)
        if n[0] == 'd': return 'FD(VR[%d][0])' % k
        if n[0] == 's': return 'FS(VR[%d][0])' % k
        raise Exception('frd ' + n)
    def fwr(s, n, expr):
        k = s.fpidx(n)
        if n[0] == 'd': return 'VR[%d][0] = DB(%s); VR[%d][1] = 0;' % (k, expr, k)
        if n[0] == 's': return 'VR[%d][0] = SB(%s); VR[%d][1] = 0;' % (k, expr, k)
        raise Exception('fwr ' + n)
    # ---------------- address
    def addr(s, i, m):
        base = s.reg(m.base, i)
        b = s.rdreg(base)
        disp = m.disp
        if m.index:
            idx = s.reg(m.index, i)
            ie = s.rdreg(idx)
            # capstone puts shift / extend on the operand
            return base, b, ie, disp
        return base, b, None, disp
    def label(s, a): return 'L%x' % a
    def emit(s, line): s.out.append('    ' + line)

    # classify resolved const addresses
    def classify(s, addr):
        c = s.ctx
        sym, sec = c.a2s2(addr)
        if sym.startswith('_OBJC_IVAR_$_'): sym = sym[1:]
        if sym.startswith('OBJC_IVAR_$_'): return ('ivar', sym[len('OBJC_IVAR_$_'):])
        if sym.startswith('_ptr._OBJC_CLASS_$_') and 'classrefs' in sec: return ('cls', sym[len('_ptr._OBJC_CLASS_$_'):])
        if 'selrefs' in sec:
            sl = c.sel(addr)
            if sl: return ('sel', sl)
        if 'cfstring' in sec:
            cf = c.cfstr(addr)
            return ('cfstr', cf)
        return ('data', sym)

    def run(s):
        ins = s.ins
        targets = set()
        for i in ins:
            if i.group(A.ARM64_GRP_JUMP) or i.mnemonic.startswith('b.') or i.mnemonic in ('b', 'cbz', 'cbnz', 'tbz', 'tbnz', 'bl'):
                for o in i.operands:
                    if o.type == A.ARM64_OP_IMM and s.start <= o.imm < s.end and i.mnemonic != 'bl':
                        targets.add(o.imm)
        s.targets = targets
        n = len(ins); idxof = {i.address: k for k, i in enumerate(ins)}
        # ---- flow analysis of the constant registers (adrp / add / table pointers), meet = intersection
        saved = (dict(s.sels), dict(s.cls), dict(s.ivs), dict(s.fns), dict(s.strs), list(s.stats['warn']))
        states = {0: ({'x0': ('self', s.cls)} if s.cls else {}, set())}
        work = [0]
        s.dry = True
        def succs(k, i):
            mn = i.mnemonic; r = []
            if mn in ('ret', 'retab', 'retaa'): return r
            if mn == 'b':
                t = i.operands[0].imm
                if t in idxof: r.append(idxof[t])
                return r
            if mn.startswith('b.') or mn in ('cbz', 'cbnz', 'tbz', 'tbnz'):
                t = i.operands[-1].imm
                if t in idxof: r.append(idxof[t])
            if k + 1 < n: r.append(k + 1)
            return r
        while work:
            k = work.pop()
            s.cval = dict(states[k][0]); s.baked = set(states[k][1]); s.out = []
            s.insn(k, ins[k])
            ex = (dict(s.cval), set(s.baked))
            for t in succs(k, ins[k]):
                if t not in states:
                    states[t] = (dict(ex[0]), set(ex[1])); work.append(t)
                else:
                    c0, b0 = states[t]
                    c1 = {r: v for r, v in c0.items() if ex[0].get(r) == v and ((r in b0) == (r in ex[1]))}
                    b1 = {r for r in b0 if r in c1}
                    if c1 != c0 or b1 != b0:
                        states[t] = (c1, b1); work.append(t)
        s.dry = False
        s.sels, s.cls, s.ivs, s.fns, s.strs = saved[0], saved[1], saved[2], saved[3], saved[4]
        s.stats['warn'] = saved[5]
        s.out = []
        for idx, i in enumerate(ins):
            if i.address in targets: s.out.append('%s:' % s.label(i.address))
            s.out.append('    /* %x: %s %s */' % (i.address, i.mnemonic, i.op_str))
            if idx in states:
                s.cval = dict(states[idx][0]); s.baked = set(states[idx][1])
                s.insn(idx, i)
            else:
                s.out.append('    /* unreachable */')
        return '\n'.join(s.out)

    def cond(s, cc):
        return {A.ARM64_CC_EQ: 'Z', A.ARM64_CC_NE: '!Z', A.ARM64_CC_HS: 'C', A.ARM64_CC_LO: '!C', A.ARM64_CC_MI: 'N', A.ARM64_CC_PL: '!N',
                A.ARM64_CC_VS: 'V', A.ARM64_CC_VC: '!V', A.ARM64_CC_HI: '(C && !Z)', A.ARM64_CC_LS: '(!C || Z)', A.ARM64_CC_GE: '(N == V)',
                A.ARM64_CC_LT: '(N != V)', A.ARM64_CC_GT: '(!Z && N == V)', A.ARM64_CC_LE: '(Z || N != V)', A.ARM64_CC_AL: '1', A.ARM64_CC_NV: '1'}[cc]

    def insn(s, idx, i):
        mn = i.mnemonic; ops = i.operands; E = s.emit
        invalidate = []
        def isreg(o): return o.type == A.ARM64_OP_REG
        def nm(o): return s.reg(o.reg, i)
        # ----- ignored
        if mn in ('pacibsp', 'autibsp', 'paciasp', 'autiasp', 'nop', 'xpaclri', 'hint', 'brk', 'dmb', 'dsb', 'isb'):
            return
        if mn == 'eor' and ops and nm(ops[0]) == 'x16' and len(ops) == 3 and nm(ops[1]) == 'x30': return
        if mn == 'tbz' and nm(ops[0]) == 'x16': return
        if mn.startswith('pac') or mn.startswith('aut') and mn not in ('autibsp', 'autiasp'):
            s.stats['warn'].append('BLOCK/PAC: %x %s %s is not executable in recompiled code (inspection only)' % (i.address, mn, i.op_str)); return
        if mn in ('retab', 'ret', 'retaa'):
            E('goto Lret;'); return
        # ----- moves / arithmetic
        if mn in ('mov', 'movz', 'movn', 'movk', 'mvn') :
            d = nm(ops[0])
            if d[0] in 'xw' or d in ('sp', 'wsp'):
                if mn == 'movk':
                    sh = ops[1].shift.value if ops[1].shift.type != A.ARM64_SFT_INVALID else 0
                    imm = ops[1].imm
                    E('X[%d] = (X[%d] & ~(0xffffull << %d)) | (0x%xull << %d);' % (int(d[1:]), int(d[1:]), sh, imm, sh) if d[0] == 'x' else
                      'X[%d] = (uint32_t)((X[%d] & ~(0xffffull << %d)) | (0x%xull << %d));' % (int(d[1:]), int(d[1:]), sh, imm, sh))
                    s.kill(d); return
                v = s.rd(i, ops[1])
                if mn == 'movn' or mn == 'mvn':
                    if ops[1].type == A.ARM64_OP_IMM:
                        sh = ops[1].shift.value if ops[1].shift.type != A.ARM64_SFT_INVALID else 0
                        v = '~(0x%xull << %d)' % (ops[1].imm & 0xffff if mn=='movn' else ops[1].imm, sh)
                    else: v = '~(%s)' % v
                if mn == 'movz' and ops[1].type == A.ARM64_OP_IMM and ops[1].shift.type != A.ARM64_SFT_INVALID:
                    v = '(0x%xull << %d)' % (ops[1].imm, ops[1].shift.value)
                E(s.wr(i, d, v)); 
                if ops[1].type == A.ARM64_OP_REG and nm(ops[1]) in s.cval and d[0]=='x':
                    s.cval[d] = s.cval[nm(ops[1])]
                    if nm(ops[1]) in s.baked: s.baked.add(d)
                else: s.kill(d)
                return
            # mov vN.16b / mov d, v
            if s.fp_is(d):
                src = nm(ops[1]) if isreg(ops[1]) else None
                # mov v0.16b, v1.16b  (capstone prints mov for orr v.16b)
                dk = s.fpidx(d); sk = s.fpidx(src)
                E('VR[%d][0] = VR[%d][0]; VR[%d][1] = VR[%d][1];' % (dk, sk, dk, sk)); return
        if mn in ('add', 'sub', 'adds', 'subs'):
            d = nm(ops[0])
            if s.fp_is(d): raise Exception('fp add/sub')
            a = s.rd(i, ops[1]); b = s.rd(i, ops[2])
            if ops[1].type == A.ARM64_OP_REG and mn in ('add',) and ops[2].type == A.ARM64_OP_IMM and isinstance(s.cval.get(nm(ops[1])), int) and d[0] == 'x':
                bk = nm(ops[1]) in s.baked
                s.cval[d] = s.cval[nm(ops[1])] + ops[2].imm
                if bk: s.baked.add(d)
                else: s.baked.discard(d)
                cvalres = s.cval[d]
            else: s.kill(d); cvalres = None
            is64 = (d[0] == 'x' or d == 'sp') if d not in ('xzr','wzr') else d == 'xzr'
            if mn == 'add' and cvalres is not None and d not in s.baked:
                k = s.classify(cvalres)
                if k[0] == 'cfstr':
                    E('X[%d] = (uint64_t)CFSTR_(%s_strs, %d); /* @"%s" */' % (int(d[1:]), s.cname, s.intern(s.strs, k[1]), k[1])); return
                sym_, sec_ = s.ctx.a2s2(cvalres)
                if not sec_ and sym_ in ('?', ''):
                    lit0 = s.ctx.cstring(cvalres)
                    if lit0 and all(32 <= ord(ch) < 127 for ch in lit0):
                        sec_ = '__TEXT.__objc_methname' if (d == 'x1' and re.match(r'^[A-Za-z_][A-Za-z0-9_:]*$', lit0)) else '__TEXT.__cstring'
                if 'methname' in sec_:
                    nmx = s.ctx.cstring(cvalres)
                    E('X[%d] = (uint64_t)SEL(%s_sels, %d); /* direct selector %s */' % (int(d[1:]), s.cname, s.intern(s.sels, nmx), nmx)); s.cval[d] = ('sel', nmx); return
                if 'cstring' in sec_:
                    lit = s.ctx.cstring(cvalres)
                    E('X[%d] = (uint64_t)(uintptr_t)%s;' % (int(d[1:]), json.dumps(lit))); return
            if mn in ('add', 'sub'):
                E(s.wr(i, d, '(%s) %s (%s)' % (a, '+' if mn == 'add' else '-', b)))
            else:
                s.flags_add_sub(mn == 'adds', a, b, is64)
                E(s.wr(i, d, 'RES'))
            return
        if mn in ('cmp', 'cmn', 'tst'):
            a = s.rd(i, ops[0]); b = s.rd(i, ops[1])
            is64 = nm(ops[0])[0] == 'x' or nm(ops[0]) == 'sp'
            if mn == 'tst': s.flags_logic('&', a, b, is64)
            else: s.flags_add_sub(mn == 'cmn', a, b, is64)
            return
        if mn in ('ccmp', 'ccmn', 'fccmp', 'fccmpe'):
            nz = ops[2].imm; c = s.cond(i.cc)
            setf = 'N = %d; Z = %d; C = %d; V = %d;' % ((nz >> 3) & 1, (nz >> 2) & 1, (nz >> 1) & 1, nz & 1)
            if mn.startswith('f'):
                a = s.frd(nm(ops[0])); b = s.frd(nm(ops[1])) if ops[1].type == A.ARM64_OP_REG else '0.0'
                E('if (%s) { FCMP(%s, %s); } else { %s }' % (c, a, b, setf)); return
            a = s.rd(i, ops[0]); b = s.rd(i, ops[1]); is64 = nm(ops[0])[0] == 'x'
            t = 'uint64_t' if is64 else 'uint32_t'; sh = 63 if is64 else 31
            if mn == 'ccmp':
                body = '%s a_ = (%s)(%s), b_ = (%s)(%s); %s r_ = a_ - b_; N = (r_ >> %d) & 1; Z = (r_ == 0); C = (a_ >= b_); V = (((a_ ^ b_) & (a_ ^ r_)) >> %d) & 1;' % (t, t, a, t, b, t, sh, sh)
            else:
                body = '%s a_ = (%s)(%s), b_ = (%s)(%s); %s r_ = a_ + b_; N = (r_ >> %d) & 1; Z = (r_ == 0); C = (r_ < a_); V = ((~(a_ ^ b_) & (a_ ^ r_)) >> %d) & 1;' % (t, t, a, t, b, t, sh, sh)
            E('if (%s) { %s } else { %s }' % (c, body, setf)); return
        if mn in ('and', 'orr', 'eor', 'ands', 'bic', 'orn', 'eon', 'bics'):
            d = nm(ops[0])
            a = s.rd(i, ops[1]); b = s.rd(i, ops[2])
            s.kill(d)
            is64 = d[0] == 'x'
            if ops[2].type == A.ARM64_OP_IMM:
                b = '0x%xull' % (ops[2].imm & ((1 << 64) - 1) if is64 else ops[2].imm & 0xffffffff)
            opmap = {'and': '&', 'ands': '&', 'orr': '|', 'eor': '^', 'bic': '& ~', 'bics': '& ~', 'orn': '| ~', 'eon': '^ ~'}
            op = opmap[mn]
            if mn in ('ands', 'bics'):
                s.flags_logic(op, a, b, is64); E(s.wr(i, d, 'RES')); return
            E(s.wr(i, d, '(%s) %s (%s)' % (a, op, b))); return
        if mn in ('lsl', 'lsr', 'asr', 'ror') and isreg(ops[0]) and nm(ops[0])[0] in 'xw':
            d = nm(ops[0]); is64 = d[0] == 'x'
            a = s.rd(i, ops[1]); s.kill(d)
            if ops[2].type == A.ARM64_OP_IMM: amt = '%d' % ops[2].imm
            else: amt = '(%s & %d)' % (s.rd(i, ops[2]), 63 if is64 else 31)
            if mn == 'lsl': E(s.wr(i, d, '(%s) << %s' % (a, amt)))
            elif mn == 'lsr': E(s.wr(i, d, '(%s) >> %s' % (a if is64 else '(uint32_t)(%s)' % a, amt)))
            elif mn == 'asr': E(s.wr(i, d, '(uint64_t)((int64_t)(%s) >> %s)' % (a, amt) if is64 else '(uint32_t)((int32_t)(%s) >> %s)' % (a, amt)))
            else: raise Exception('ror')
            return
        if mn in ('ubfx', 'sbfx', 'ubfiz', 'sbfiz', 'bfi', 'bfxil', 'uxtb', 'uxth', 'sxtb', 'sxth', 'sxtw', 'uxtw'):
            d = nm(ops[0]); s.kill(d)
            a = s.rd(i, ops[1])
            if mn == 'uxtb': E(s.wr(i, d, '(uint8_t)(%s)' % a)); return
            if mn == 'uxth': E(s.wr(i, d, '(uint16_t)(%s)' % a)); return
            if mn == 'sxtb': E(s.wr(i, d, '(int64_t)(int8_t)(%s)' % a if d[0]=='x' else '(uint32_t)(int32_t)(int8_t)(%s)' % a)); return
            if mn == 'sxth': E(s.wr(i, d, '(int64_t)(int16_t)(%s)' % a if d[0]=='x' else '(uint32_t)(int32_t)(int16_t)(%s)' % a)); return
            if mn == 'sxtw': E(s.wr(i, d, '(int64_t)(int32_t)(%s)' % a)); return
            if mn == 'uxtw': E(s.wr(i, d, '(uint32_t)(%s)' % a)); return
            lsb = ops[2].imm; width = ops[3].imm
            m = '((1ull << %d) - 1)' % width if width < 64 else '~0ull'
            if mn == 'ubfx': E(s.wr(i, d, '((%s) >> %d) & %s' % (a, lsb, m))); return
            if mn == 'sbfx':
                bits = 64 if d[0] == 'x' else 32
                E(s.wr(i, d, '(uint64_t)(((int64_t)((%s) << %d)) >> %d)' % (a if d[0]=='x' else '(uint64_t)(uint32_t)(%s)'%a, 64 - lsb - width, 64 - width))); return
            if mn == 'ubfiz': E(s.wr(i, d, '(((%s) & %s) << %d)' % (a, m, lsb))); return
            if mn == 'bfi':
                E(s.wr(i, d, '((%s) & ~(%s << %d)) | (((%s) & %s) << %d)' % (s.rdreg(d), m, lsb, a, m, lsb))); return
            raise Exception(mn)
        if mn in ('mul', 'madd', 'msub', 'mneg', 'smull', 'umull', 'sdiv', 'udiv', 'neg', 'negs'):
            d = nm(ops[0]); s.kill(d)
            if mn == 'mul': E(s.wr(i, d, '(%s) * (%s)' % (s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'madd': E(s.wr(i, d, '(%s) * (%s) + (%s)' % (s.rd(i, ops[1]), s.rd(i, ops[2]), s.rd(i, ops[3])))); return
            if mn == 'msub': E(s.wr(i, d, '(%s) - (%s) * (%s)' % (s.rd(i, ops[3]), s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'neg': E(s.wr(i, d, '0 - (%s)' % s.rd(i, ops[1]))); return
            if mn == 'smull': E(s.wr(i, d, '(int64_t)(int32_t)(%s) * (int64_t)(int32_t)(%s)' % (s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'umull': E(s.wr(i, d, '(uint64_t)(uint32_t)(%s) * (uint64_t)(uint32_t)(%s)' % (s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'sdiv':
                if d[0] == 'x': E(s.wr(i, d, 'SDIV64(%s, %s)' % (s.rd(i, ops[1]), s.rd(i, ops[2]))))
                else: E(s.wr(i, d, 'SDIV32(%s, %s)' % (s.rd(i, ops[1]), s.rd(i, ops[2]))))
                return
            if mn == 'udiv': E(s.wr(i, d, '((%s) ? (%s) / (%s) : 0)' % (s.rd(i, ops[2]), s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            raise Exception(mn)
        if mn in ('csel', 'csinc', 'csinv', 'csneg', 'cset', 'csetm', 'cinc', 'cinv', 'cneg'):
            d = nm(ops[0]); s.kill(d)
            cc = i.cc
            c = s.cond(cc)
            if mn == 'cset': E(s.wr(i, d, '(%s) ? 1 : 0' % c)); return
            if mn == 'csetm': E(s.wr(i, d, '(%s) ? ~0ull : 0' % c)); return
            if mn == 'csel': E(s.wr(i, d, '(%s) ? (%s) : (%s)' % (c, s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'csinc': E(s.wr(i, d, '(%s) ? (%s) : (%s) + 1' % (c, s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'csinv': E(s.wr(i, d, '(%s) ? (%s) : ~(%s)' % (c, s.rd(i, ops[1]), s.rd(i, ops[2])))); return
            if mn == 'cinc': E(s.wr(i, d, '(%s) ? (%s) + 1 : (%s)' % (c, s.rd(i, ops[1]), s.rd(i, ops[1])))); return
            raise Exception(mn)
        if mn == 'adrp':
            d = nm(ops[0]); a = ops[1].imm
            s.cval[d] = a; s.baked.discard(d)
            E('X[%d] = 0x%xull;' % (int(d[1:]), a)); return
        if mn == 'adr':
            d = nm(ops[0]); a = ops[1].imm
            s.cval[d] = a; s.baked.discard(d)
            E('X[%d] = 0x%xull;' % (int(d[1:]), a)); return
        # ----- branches
        if mn == 'b':
            t = ops[0].imm
            if s.start <= t < s.end: E('goto %s;' % s.label(t)); return
            s.tailcall(i, t); return
        if mn.startswith('b.'):
            E('if (%s) goto %s;' % (s.cond(i.cc), s.label(ops[0].imm))); return
        if mn in ('cbz', 'cbnz'):
            r = nm(ops[0]); e = s.rdreg(r)
            E('if (%s %s 0) goto %s;' % (e, '==' if mn == 'cbz' else '!=', s.label(ops[1].imm))); return
        if mn in ('tbz', 'tbnz'):
            r = nm(ops[0]); e = s.rdreg(r)
            E('if ((((%s) >> %d) & 1) %s 0) goto %s;' % (e, ops[1].imm, '==' if mn == 'tbz' else '!=', s.label(ops[2].imm))); return
        if mn == 'bl':
            s.call(idx, i, ops[0].imm); return
        # ----- memory
        if mn in ('ldr', 'ldur', 'ldrb', 'ldrh', 'ldrsw', 'ldrsb', 'ldrsh', 'ldurb', 'ldurh', 'ldursw', 'str', 'stur', 'strb', 'strh', 'sturb', 'sturh', 'ldp', 'stp', 'ldrsb', 'ldursb', 'ldursh', 'ldpsw'):
            s.memop(i, mn); return
        # ----- fp
        if s.fpinsn(idx, i): return
        raise Exception('unhandled %x %s %s' % (i.address, mn, i.op_str))

    def flags_add_sub(s, is_add, a, b, is64):
        t = 'uint64_t' if is64 else 'uint32_t'; st = 'int64_t' if is64 else 'int32_t'; sh = 63 if is64 else 31
        s.emit('{ %s a_ = (%s)(%s), b_ = (%s)(%s); %s r_ = %s; ' % (t, t, a, t, b, t, 'a_ + b_' if is_add else 'a_ - b_') +
               'N = (r_ >> %d) & 1; Z = (r_ == 0); ' % sh +
               ('C = (r_ < a_); V = ((~(a_ ^ b_) & (a_ ^ r_)) >> %d) & 1; ' % sh if is_add else 'C = (a_ >= b_); V = (((a_ ^ b_) & (a_ ^ r_)) >> %d) & 1; ' % sh) +
               'RES = r_; }')
    def flags_logic(s, op, a, b, is64):
        t = 'uint64_t' if is64 else 'uint32_t'; sh = 63 if is64 else 31
        s.emit('{ %s r_ = (%s)((%s) %s (%s)); N = (r_ >> %d) & 1; Z = (r_ == 0); C = 0; V = 0; RES = r_; }' % (t, t, a, op, b, sh))

    def memop(s, i, mn):
        ops = i.operands; E = s.emit
        load = mn.startswith('ld')
        pair = mn in ('ldp', 'stp', 'ldpsw')
        nreg = 2 if pair else 1
        regs = [s.reg(o.reg, i) for o in ops[:nreg]]
        m = ops[nreg]
        assert m.type == A.ARM64_OP_MEM, i.op_str
        base = s.reg(m.mem.base, i)
        # size
        szmap = {'ldrb': 1, 'ldurb': 1, 'strb': 1, 'sturb': 1, 'ldrh': 2, 'ldurh': 2, 'strh': 2, 'sturh': 2, 'ldrsw': 4, 'ldursw': 4, 'ldpsw': 4,
                 'ldrsb': 1, 'ldursb': 1, 'ldrsh': 2, 'ldursh': 2}
        r0 = regs[0]
        if mn in szmap: sz = szmap[mn]
        else:
            sz = {'x': 8, 'w': 4, 'd': 8, 's': 4, 'q': 16, 'b': 1, 'h': 2}[r0[0]]
        # effective address
        disp = m.mem.disp
        post = False
        if ops[-1].type == A.ARM64_OP_IMM and len(ops) > nreg + 1:
            post = True; postimm = ops[-1].imm
        wb = i.writeback
        if m.mem.index:
            ie = s.rdreg(s.reg(m.mem.index, i))
            o2 = m
            ie = s.apply_ext(m, ie, s.reg(m.mem.index, i))
            ea = '(%s) + (%s)' % (s.rdreg(base), ie)
        else:
            ea = '(%s) + (%d)' % (s.rdreg(base), disp)
        const_addr = None
        selfcls = None; eas = None
        if isinstance(s.cval.get(base), int) and not m.mem.index:
            const_addr = s.cval[base] + disp
        if isinstance(s.cval.get(base), tuple) and s.cval[base][0] == 'self' and not m.mem.index and not post:
            selfcls = s.cval[base][1]
        if post:
            ea = '%s' % s.rdreg(base)
            const_addr = s.cval.get(base) if isinstance(s.cval.get(base), int) else None
        if selfcls:
            ivs = s.ivmap(selfcls, disp, sz)
            if ivs:
                ea = '(%s) + IVOFF(%s_ivs, %d) + (%d)' % (s.rdreg(base), s.cname, s.intern(s.ivs, ivs[0]), ivs[1])
            if pair:
                eas = []
                for j in range(2):
                    iv2 = s.ivmap(selfcls, disp + j * sz, sz)
                    if iv2: eas.append('(%s) + IVOFF(%s_ivs, %d) + (%d)' % (s.rdreg(base), s.cname, s.intern(s.ivs, iv2[0]), iv2[1]))
                    else: eas.append('(%s) + (%d)' % (s.rdreg(base), disp + j * sz))
        if wb and not post:
            E('X[%d] = (uint64_t)(%s);' % (int(base[1:]) if base != 'sp' else 31, ea)); ea = s.rdreg(base)
        elif not wb: pass
        if base == 'sp': pass
        # constant (global) loads
        if load and const_addr is not None and not pair and base in s.baked and sz in (1, 2, 4, 8) and r0[0] in 'xwd':
            data = s.ctx.read(const_addr, sz)
            v = int.from_bytes(data, 'little')
            if sz == 8 and r0[0] == 'x' and (v >= (1 << 40) or 0x180000000 <= v < 0x200000000) and base in s.bakedsym:
                sy, ta = s.bakedsym[base]
                E('X[%d] = LD64((uint64_t)GSYM(%s_fns, %d) + %d); /* %s: pointer value, loaded at run time */' % (int(r0[1:]), s.cname, s.intern(s.fns, sy), const_addr - ta, sy)); s.kill(r0); return
            if mn in ('ldrsw', 'ldursw'): v = struct.unpack('<q', struct.pack('<i', v & 0xffffffff))[0] & 0xffffffffffffffff
            if r0[0] == 'd': E('VR[%d][0] = 0x%xull; VR[%d][1] = 0; /* baked const @%x */' % (int(r0[1:]), v, int(r0[1:]), const_addr))
            else: E(s.wr(i, r0, '0x%xull' % v) + ' /* baked const @%x */' % const_addr); s.kill(r0); s.baked.discard(r0)
            return
        if load and const_addr is not None and not pair and r0[0] in 'xwd' and sz in (4, 8):
            k = s.classify(const_addr)
            if k[0] == 'ivar':
                E('X[%d] = %s(IVOFF(%s_ivs, %d));' % (int(r0[1:]), '(uint64_t)(int64_t)(int32_t)' if sz == 4 else '', s.cname, s.intern(s.ivs, k[1])))
                return
            if k[0] == 'cls':
                E('X[%d] = (uint64_t)CLS(%s_cls, %d);' % (int(r0[1:]), s.cname, s.intern(s.cls, k[1]))); return
            if k[0] == 'sel':
                E('X[%d] = (uint64_t)SEL(%s_sels, %d);' % (int(r0[1:]), s.cname, s.intern(s.sels, k[1]))); s.cval[r0] = ('sel', k[1]); s.baked.discard(r0); return
            if k[0] == 'cfstr':
                E('X[%d] = (uint64_t)CFSTR_(%s_strs, %d);' % (int(r0[1:]), s.cname, s.intern(s.strs, k[1]))); return
            if k[0] == 'data':
                data = s.ctx.read(const_addr, sz)
                sym = k[1]
                if r0[0] == 'd':
                    v = struct.unpack('<Q', data)[0]
                    E('VR[%d][0] = 0x%xull; VR[%d][1] = 0; /* const %s @%x */' % (int(r0[1:]), v, int(r0[1:]), sym, const_addr)); return
                if sz == 8 and r0[0] == 'x':
                    raw = struct.unpack('<Q', data)[0]
                    from emu import fix_ptrs
                    tgt = struct.unpack('<Q', fix_ptrs(data))[0]
                    tsym = s.ctx.a2s(tgt) if 0x180000000 <= tgt < 0x200000000 else ''
                    if tsym == '___stack_chk_guard':
                        E('X[%d] = (uint64_t)(uintptr_t)&lift_guard_cell;' % int(r0[1:])); s.kill(r0); return
                    tsec = s.ctx.a2s2(tgt)[1] if tsym else ''
                    if 0x180000000 <= tgt < 0x200000000 and 'cfstring' in s.ctx.a2s2(tgt)[1]:
                        txt = s.ctx.cfstr(tgt)
                        E('X[%d] = (uint64_t)CFSTR_(%s_strs, %d); /* @"%s" */' % (int(r0[1:]), s.cname, s.intern(s.strs, txt), txt)); s.kill(r0); return
                    if tsym.startswith('_OBJC_CLASS_$_'):
                        E('X[%d] = (uint64_t)CLS(%s_cls, %d);' % (int(r0[1:]), s.cname, s.intern(s.cls, tsym[len('_OBJC_CLASS_$_'):]))); s.kill(r0); return
                    if tsym and ('__TEXT' in tsec or '__const' in tsec or 'cstring' in tsec):
                        s.cval[r0] = tgt; s.baked.add(r0); s.bakedsym[r0] = (tsym, tgt)
                        E('X[%d] = 0x%xull; /* address of %s (immutable table, loads from it are baked) */' % (int(r0[1:]), tgt, tsym)); return
                    if tsym:
                        E('X[%d] = (uint64_t)GSYM(%s_fns, %d); /* %s */' % (int(r0[1:]), s.cname, s.intern(s.fns, tsym), tsym)); s.kill(r0); return
                s.stats['warn'].append('unresolved data load %x (%s)' % (const_addr, sym))
        # generic
        def rdmem(expr, sz, signed):
            return {1: 'LD8', 2: 'LD16', 4: 'LD32', 8: 'LD64'}[sz] + '(%s)' % expr
        if pair:
            for j, r in enumerate(regs):
                off = j * sz
                a = eas[j] if eas else '(%s) + %d' % (ea, off)
                if load and const_addr is not None and base in s.baked and sz in (4, 8):
                    bv = int.from_bytes(s.ctx.read(const_addr + off, sz), 'little')
                    if r[0] in 'xw': E(s.wr(i, r, '0x%xull' % bv) + ' /* baked const @%x */' % (const_addr + off)); s.kill(r)
                    else: E('VR[%d][0] = 0x%xull; VR[%d][1] = 0; /* baked const @%x */' % (int(r[1:]), bv, int(r[1:]), const_addr + off))
                elif load:
                    if r[0] in 'xw':
                        v = 'LD%d(%s)' % (sz * 8, a)
                        if mn == 'ldpsw': v = '(uint64_t)(int64_t)(int32_t)%s' % v
                        E(s.wr(i, r, v)); s.kill(r)
                    else:
                        k = int(r[1:])
                        if sz == 16: E('VR[%d][0] = LD64(%s); VR[%d][1] = LD64(%s + 8);' % (k, a, k, a))
                        else: E('VR[%d][0] = LD%d(%s); VR[%d][1] = 0;' % (k, sz * 8, a, k))
                else:
                    if r in ('xzr', 'wzr'): v = '0'
                    elif r[0] in 'xw': v = s.rdreg(r)
                    else:
                        k = int(r[1:])
                        if sz == 16: E('ST64(%s, VR[%d][0]); ST64(%s + 8, VR[%d][1]);' % (a, k, a, k)); continue
                        v = 'VR[%d][0]' % k
                    E('ST%d(%s, %s);' % (sz * 8, a, v))
        else:
            r = r0
            if load:
                if r[0] in 'xw':
                    v = 'LD%d(%s)' % (sz * 8, ea)
                    if mn in ('ldrsw', 'ldursw'): v = '(uint64_t)(int64_t)(int32_t)%s' % v
                    elif mn in ('ldrsb', 'ldursb'): v = '(uint64_t)(int64_t)(int8_t)%s' % v if r[0] == 'x' else '(uint32_t)(int32_t)(int8_t)%s' % v
                    elif mn in ('ldrsh', 'ldursh'): v = '(uint64_t)(int64_t)(int16_t)%s' % v if r[0] == 'x' else '(uint32_t)(int32_t)(int16_t)%s' % v
                    E(s.wr(i, r, v)); s.kill(r)
                else:
                    k = int(r[1:])
                    if sz == 16: E('VR[%d][0] = LD64(%s); VR[%d][1] = LD64((%s) + 8);' % (k, ea, k, ea))
                    else: E('VR[%d][0] = LD%d(%s); VR[%d][1] = 0;' % (k, sz * 8, ea, k))
            else:
                if r in ('xzr', 'wzr'): v = '0'
                elif r[0] in 'xw': v = s.rdreg(r)
                else:
                    k = int(r[1:])
                    if sz == 16: E('ST64(%s, VR[%d][0]); ST64((%s) + 8, VR[%d][1]);' % (ea, k, ea, k)); v = None
                    else: v = 'VR[%d][0]' % k
                if v is not None: E('ST%d(%s, %s);' % (sz * 8, ea, v))
        if post:
            E('X[%d] = (uint64_t)(%s) + (%d);' % (int(base[1:]) if base != 'sp' else 31, s.rdreg(base), postimm))
            s.kill(base)

    def ivmap(s, cls, off, size):
        """(Class.ivar, delta) when `off` lies inside an ivar of cls (or of an SB superclass) in this build's table, None otherwise"""
        tab = ivar_tables(s.ver); c = cls; seen = 0
        while c and c in tab and seen < 16:
            for name, o, sz in tab[c]['iv']:
                if o <= off < o + max(sz, 1): return ('%s.%s' % (c, name), off - o)
            c = tab[c]['super']; seen += 1
        return None
    def kill(s, r):
        s.cval.pop(r, None); s.baked.discard(r)
    def intern(s, d, name):
        if name not in d: d[name] = len(d)
        return d[name]

    # ---------------- floating point
    def fpinsn(s, idx, i):
        return s._fpinsn(idx, i) is not False
    def _fpinsn(s, idx, i):
        mn = i.mnemonic; ops = i.operands; E = s.emit
        def nm(o): return s.reg(o.reg, i)
        def isreg(o): return o.type == A.ARM64_OP_REG
        if mn == 'fmov':
            d = nm(ops[0])
            if ops[1].type == A.ARM64_OP_FP:
                v = ops[1].fp
                E('VR[%d][0] = 0x%xull; VR[%d][1] = 0;' % (int(d[1:]), struct.unpack('<Q', struct.pack('<d', v))[0] if d[0] == 'd' else struct.unpack('<I', struct.pack('<f', v))[0], int(d[1:]))); return
            src = nm(ops[1])
            if d[0] in 'xw' and s.fp_is(src):
                if ops[1].vector_index >= 0 or '[' in i.op_str:
                    E(s.wr(i, d, 'VR[%d][%d]' % (int(src[1:]), ops[1].vector_index))); return
                E(s.wr(i, d, 'VR[%d][0]' % int(src[1:]) if d[0] == 'x' else '(uint32_t)VR[%d][0]' % int(src[1:]))); s.kill(d); return
            if s.fp_is(d) and src[0] in 'xw' or src in ('xzr', 'wzr'):
                E('VR[%d][0] = %s; VR[%d][1] = 0;' % (int(d[1:]), s.rdreg(src) if src not in ('xzr','wzr') else '0', int(d[1:]))); return
            if s.fp_is(d) and s.fp_is(src):
                E('VR[%d][0] = VR[%d][0]; VR[%d][1] = 0;' % (int(d[1:]), int(src[1:]), int(d[1:]))); return
        if mn in ('fcmp', 'fcmpe'):
            a = nm(ops[0]); 
            if ops[1].type == A.ARM64_OP_FP: b = '0.0'
            else: b = s.frd(nm(ops[1]))
            E('FCMP(%s, %s);' % (s.frd(a), b)); return
        if mn in ('fadd', 'fsub', 'fmul', 'fdiv', 'fmax', 'fmin', 'fmaxnm', 'fminnm', 'fnmul'):
            d = nm(ops[0])
            if s.vec(i):
                return s.vecop(i)
            op = {'fadd': '+', 'fsub': '-', 'fmul': '*', 'fdiv': '/'}.get(mn)
            a = s.frd(nm(ops[1])); b = s.frd(nm(ops[2]))
            if mn in ('fmax', 'fmaxnm'): E(s.fwr(d, 'FMAXF_(%s, %s)' % (a, b))); return
            if mn in ('fmin', 'fminnm'): E(s.fwr(d, 'FMINF_(%s, %s)' % (a, b))); return
            if mn == 'fnmul': E(s.fwr(d, '-(%s * %s)' % (a, b))); return
            E(s.fwr(d, '%s %s %s' % (a, op, b))); return
        if mn in ('fmadd', 'fmsub', 'fnmadd', 'fnmsub'):
            d = nm(ops[0]); a = s.frd(nm(ops[1])); b = s.frd(nm(ops[2])); c = s.frd(nm(ops[3]))
            ex = {'fmadd': '%s * %s + %s', 'fmsub': '%s - %s * %s', 'fnmadd': '-(%s * %s) - %s', 'fnmsub': '%s * %s - %s'}[mn]
            if mn == 'fmsub': E(s.fwr(d, 'FMA_(-(%s), %s, %s)' % (a, b, c)))
            elif mn == 'fmadd': E(s.fwr(d, 'FMA_(%s, %s, %s)' % (a, b, c)))
            elif mn == 'fnmadd': E(s.fwr(d, 'FMA_(-(%s), %s, -(%s))' % (a, b, c)))
            else: E(s.fwr(d, 'FMA_(%s, %s, -(%s))' % (a, b, c)))
            return
        if mn in ('fneg', 'fabs', 'fsqrt', 'frintm', 'frintp', 'frintn', 'frintz', 'frinta', 'frintx', 'frinti'):
            d = nm(ops[0])
            if s.vec(i): return s.vecop(i)
            a = s.frd(nm(ops[1]))
            f = {'fneg': '-%s', 'fabs': 'fabs(%s)', 'fsqrt': 'sqrt(%s)', 'frintm': 'floor(%s)', 'frintp': 'ceil(%s)', 'frintn': 'nearbyint(%s)', 'frintz': 'trunc(%s)', 'frinta': 'round(%s)', 'frintx': 'rint(%s)', 'frinti': 'nearbyint(%s)'}[mn]
            E(s.fwr(d, f % a)); return
        if mn in ('fcsel',):
            d = nm(ops[0]); a = s.frd(nm(ops[1])); b = s.frd(nm(ops[2]))
            E(s.fwr(d, '(%s) ? %s : %s' % (s.cond(i.cc), a, b))); return
        if mn in ('scvtf', 'ucvtf'):
            d = nm(ops[0]); sr = nm(ops[1])
            if s.vec(i): return s.vecop(i)
            e = s.rdreg(sr)
            if mn == 'scvtf': E(s.fwr(d, '(double)(int64_t)(%s)' % e if sr[0] == 'x' else '(double)(int32_t)(%s)' % e))
            else: E(s.fwr(d, '(double)(uint64_t)(%s)' % e if sr[0] == 'x' else '(double)(uint32_t)(%s)' % e))
            return
        if mn in ('fcvtzs', 'fcvtzu', 'fcvtms', 'fcvtps', 'fcvtns', 'fcvtas', 'fcvtmu', 'fcvtpu', 'fcvtau'):
            d = nm(ops[0]); a = s.frd(nm(ops[1]))
            f = {'fcvtzs': 'trunc', 'fcvtzu': 'trunc', 'fcvtms': 'floor', 'fcvtps': 'ceil', 'fcvtns': 'nearbyint', 'fcvtas': 'round', 'fcvtmu': 'floor', 'fcvtpu': 'ceil', 'fcvtau': 'round'}[mn]
            if mn.endswith('u'):
                E(s.wr(i, d, 'CVTU(%s(%s))' % (f, a))); return
            E(s.wr(i, d, ('CVTS64(%s(%s))' if d[0] == 'x' else 'CVTS32(%s(%s))') % (f, a))); return
        if mn == 'fcvt':
            d = nm(ops[0]); a = nm(ops[1])
            if d[0] == 'd' and a[0] == 's': E(s.fwr(d, '(double)%s' % s.frd(a))); return
            if d[0] == 's' and a[0] == 'd': E(s.fwr(d, '(float)%s' % s.frd(a))); return
        if mn in ('movi', 'dup', 'ext', 'ins', 'umov', 'zip1', 'zip2', 'fcvtl', 'fcvtn', 'bsl', 'bif', 'bit', 'mvni', 'ldr', 'cmeq', 'cmgt', 'fcmeq', 'fcmgt', 'fcmge', 'fcmle', 'fcmlt', 'and', 'orr', 'eor', 'bic', 'addp', 'faddp', 'xtn', 'sshll', 'ushll', 'trn1', 'trn2', 'uzp1', 'uzp2', 'rev64', 'smov'):
            return s.vecop(i)
        if s.vec(i): return s.vecop(i)
        return False
    def vec(s, i):
        for o in i.operands:
            if o.type == A.ARM64_OP_REG and i.reg_name(o.reg)[0] == 'v': return True
        return False
    def vecop(s, i):
        mn = i.mnemonic; ops = i.operands; E = s.emit
        if mn == 'movi' and ops[1].type == A.ARM64_OP_IMM:
            d = int(s.reg(ops[0].reg, i)[1:]); imm = ops[1].imm & 0xffffffffffffffff
            v = {A.ARM64_VAS_2D: 64, A.ARM64_VAS_1D: 64}.get(ops[0].vas)
            if v == 64:
                E('VR[%d][0] = 0x%xull; VR[%d][1] = %s;' % (d, imm, d, '0x%xull' % imm if ops[0].vas == A.ARM64_VAS_2D else '0')); return
            if imm == 0:
                E('VR[%d][0] = 0; VR[%d][1] = 0;' % (d, d)); return
        raise Exception('vector op %x %s %s' % (i.address, i.mnemonic, i.op_str))

    # ---------------- calls
    def callkind(s, idx, name):
        """decide the return kind of the call at idx by scanning the code after it"""
        ins = s.ins
        akey = name + '@%x' % ins[idx].address
        if akey in s.kinds: return s.kinds[akey]
        if name in s.kinds: return s.kinds[name]
        if name.startswith('msgSend:'):
            ks = ret_kinds(s.ver).get(name[8:])
            if ks and len(ks) == 1:
                k0 = next(iter(ks))
                if k0.startswith('STRUCT'): s.stats['warn'].append('call %s returns %s: indirect result (x8) is NOT modelled' % (name, k0))
                return 'x' if k0.startswith('STRUCT') else k0
            if ks and len(ks) > 1: raise Exception('AMBIGUOUS return kind of %s in the dumps %s (call at %x): give --kinds %s=<x|v|d|size|rect>' % (name, sorted(ks), ins[idx].address, name[8:]))
        elif name.lstrip('_') in FN_KINDS: return FN_KINDS[name.lstrip('_')]
        d_used = -1; x_used = False; d_written = set(); x_written = set(); first = None
        for j in range(idx + 1, min(idx + 60, len(ins))):
            q = ins[j]
            if q.address in s.targets: break
            mn = q.mnemonic
            reads_x = set(); reads_d = set(); writes_x = set(); writes_d = set()
            ops = q.operands
            for k, o in enumerate(ops):
                if o.type == A.ARM64_OP_REG:
                    n = s.reg(o.reg, q)
                    isw = (k == 0 and mn not in ('str', 'stur', 'strb', 'strh', 'cmp', 'cmn', 'tst', 'fcmp', 'fcmpe', 'cbz', 'cbnz', 'tbz', 'tbnz', 'stp', 'sturb', 'sturh'))
                    if mn == 'ldp' and k < 2: isw = True
                    if mn == 'stp' and k < 2: isw = False
                    kind = 'x' if n[0] in 'xw' else ('d' if n[0] in 'dsqv' else '?')
                    idxn = int(n[1:]) if n[1:].isdigit() else -1
                    if kind == 'x' and idxn >= 0: (writes_x if isw else reads_x).add(idxn)
                    elif kind == 'd' and idxn >= 0: (writes_d if isw else reads_d).add(idxn)
                elif o.type == A.ARM64_OP_MEM:
                    n = s.reg(o.mem.base, q)
                    if n[0] in 'xw' and n[1:].isdigit(): reads_x.add(int(n[1:]))
                    if o.mem.index:
                        n = s.reg(o.mem.index, q)
                        if n[0] in 'xw' and n[1:].isdigit(): reads_x.add(int(n[1:]))
            if mn in ('bl', 'blr'): break
            for r in reads_x:
                if r == 0 and 0 not in x_written:
                    x_used = True
                    if first is None: first = 'x'
            for r in reads_d:
                if r < 4 and r not in d_written:
                    d_used = max(d_used, r)
                    if first is None: first = 'd'
            x_written |= writes_x; d_written |= writes_d
            if mn in ('b', 'ret', 'retab') or mn.startswith('b.') or mn in ('cbz', 'cbnz', 'tbz', 'tbnz') and False:
                break
            if mn == 'b' or mn in ('ret', 'retab'): break
        if x_used and d_used >= 0:
            s.stats['warn'].append('call %s at %x: both x0 and d0..d%d are read afterwards, chose %s' % (name, ins[idx].address, d_used, first))
            if first == 'x': return 'x'
        elif x_used: return 'x'
        if d_used >= 0: return {0: 'd', 1: 'size', 2: 'rect', 3: 'rect'}[d_used]
        return 'x'

    def rtcall(s, nm):
        """C statement for a call of an objc runtime helper / stack check, None for any other callee"""
        m = re.match(r'objc_(retain|release)_x(\d+)$', nm.lstrip('_'))
        if m:
            fnm = m.group(1); r = int(m.group(2))
            return ('X[0] = (uint64_t)RT_%s((void *)X[%d]);' if fnm == 'retain' else 'RT_%s((void *)X[%d]);') % (fnm.upper(), r)
        rt = {'objc_claimAutoreleasedReturnValue': 'X[0] = (uint64_t)RT_CLAIM((void *)X[0]);',
              'objc_retainAutoreleasedReturnValue': 'X[0] = (uint64_t)RT_CLAIM((void *)X[0]);',
              'objc_unsafeClaimAutoreleasedReturnValue': 'X[0] = (uint64_t)RT_UNSAFECLAIM((void *)X[0]);',
              'objc_retain': 'X[0] = (uint64_t)RT_RETAIN((void *)X[0]);',
              'objc_release': 'RT_RELEASE((void *)X[0]);',
              'objc_autorelease': 'X[0] = (uint64_t)RT_AUTORELEASE((void *)X[0]);',
              'objc_retainAutorelease': 'X[0] = (uint64_t)RT_RETAINAUTORELEASE((void *)X[0]);',
              'objc_autoreleaseReturnValue': 'X[0] = (uint64_t)RT_AUTORELEASERV((void *)X[0]);',
              'objc_retainAutoreleaseReturnValue': 'X[0] = (uint64_t)RT_RETAINAUTORELEASERV((void *)X[0]);',
              'objc_storeStrong': 'RT_STORESTRONG((void **)X[0], (void *)X[1]);',
              'objc_enumerationMutation': 'RT_ENUMMUT((void *)X[0]);',
              'stack_chk_fail': 'STACKFAIL();'}
        return rt.get(nm.lstrip('_'))
    def call(s, idx, i, t):
        E = s.emit
        nm = s.ctx.stubname(t)
        if not nm: s.stats['warn'].append('unresolved call %x -> %x' % (i.address, t)); nm = 'UNRESOLVED_%x' % t
        # registers clobbered
        x1tag = s.cval.get('x1')
        for rr in range(0, 18): s.kill('x%d' % rr)
        if nm.lstrip('_') == 'objc_msgSendSuper2' and isinstance(x1tag, tuple) and x1tag[0] == 'sel' and x1tag[1].startswith('init') and s.cls:
            s.cval['x0'] = ('self', s.cls)
        if nm.startswith('msgSend:'):
            sel = nm[8:]
            kind = s.callkind(idx, nm)
            E('X[1] = (uint64_t)SEL(%s_sels, %d);' % (s.cname, s.intern(s.sels, sel)))
            E('CALLMSG(%s);' % kind); s.note_call(i, nm, kind); return
        rc = s.rtcall(nm)
        if rc is not None:
            E(rc); return
        kind = s.callkind(idx, nm)
        k = s.intern(s.fns, nm)
        E('CALLFN(%s_fns, %d, %s);' % (s.cname, k, kind)); s.note_call(i, nm, kind)
    def note_call(s, i, nm, kind): s.kinds_at[i.address] = kind
    def tailcall(s, i, t):
        nm = s.ctx.stubname(t)
        s.emit('/* tail call %s */' % nm)
        if nm.startswith('msgSend:'):
            s.emit('X[1] = (uint64_t)SEL(%s_sels, %d);' % (s.cname, s.intern(s.sels, nm[8:])))
            kind = s.retk
            s.emit('CALLMSG(%s); goto Lret;' % kind); return
        rc = s.rtcall(nm)
        if rc is not None:
            s.emit(rc + ' goto Lret;'); return
        k = s.intern(s.fns, nm)
        s.emit('CALLFN(%s_fns, %d, %s); goto Lret;' % (s.cname, k, s.retk))

    def generate(s):
        body = s.run()
        sig = s.sig.split(',') if s.sig else []
        params = []; pre = []
        xi = 0; di = 0
        soff = 0
        for k, a in enumerate(sig):
            if a == 'x': params.append('uint64_t a%d' % k); pre.append('X[%d] = a%d;' % (xi, k)); xi += 1
            elif a == 'd': params.append('double a%d' % k); pre.append('VR[%d][0] = DB(a%d);' % (di, k)); di += 1
            elif a in ('b', 'w', 'q'):
                # argument passed on the stack (Darwin packs by natural alignment): the machine code reads it at [sp_at_entry + soff]
                sz = {'b': 1, 'w': 4, 'q': 8}[a]
                soff = (soff + sz - 1) // sz * sz
                params.append('%s a%d' % ({'b': 'uint8_t', 'w': 'uint32_t', 'q': 'uint64_t'}[a], k))
                pre.append('ST%d(X[31] + %d, a%d);' % (sz * 8, soff, k)); soff += sz
            else: raise Exception(a)
        rt = {'v': 'void', 'x': 'uint64_t', 'd': 'double', 'size': 'LiftSize', 'rect': 'LiftRect'}[s.retk]
        ret = {'v': 'return;', 'x': 'return X[0];', 'd': 'return FD(VR[0][0]);', 'size': 'LiftSize r_ = { FD(VR[0][0]), FD(VR[1][0]) }; return r_;',
               'rect': 'LiftRect r_ = { FD(VR[0][0]), FD(VR[1][0]), FD(VR[2][0]), FD(VR[3][0]) }; return r_;'}[s.retk]
        h = []
        h.append('/* generated by tools/a2c/a2c.py from %s %x..%x (%d instructions) -- do not edit by hand */' % (s.ver, s.start, s.end, len(s.ins)))
        for n, j in sorted(s.sels.items(), key=lambda kv: kv[1]): h.append('#define %s_SEL_%d "%s"' % (s.cname, j, n))
        tabs = []
        tabs.append('static const char *const %s_sels[] = { %s };' % (s.cname, ', '.join('"%s"' % n for n, j in sorted(s.sels.items(), key=lambda kv: kv[1])) or '0'))
        tabs.append('static const char *const %s_cls[] = { %s };' % (s.cname, ', '.join('"%s"' % n for n, j in sorted(s.cls.items(), key=lambda kv: kv[1])) or '0'))
        tabs.append('static const char *const %s_ivs[] = { %s };' % (s.cname, ', '.join('"%s"' % n for n, j in sorted(s.ivs.items(), key=lambda kv: kv[1])) or '0'))
        tabs.append('static const char *const %s_fns[] = { %s };' % (s.cname, ', '.join('"%s"' % n for n, j in sorted(s.fns.items(), key=lambda kv: kv[1])) or '0'))
        tabs.append('static const char *const %s_strs[] = { %s };' % (s.cname, ', '.join(json.dumps(n) for n, j in sorted(s.strs.items(), key=lambda kv: kv[1])) or '0'))
        tabs.append('static const char *%s_preflight(void) { return LIFT_PREFLIGHT(%s_fns, %s_cls, %s_ivs); }' % (s.cname, s.cname, s.cname, s.cname))
        head = '\n'.join(h + tabs)
        fn = []
        fn.append('static %s %s(%s) {' % (rt, s.cname, ', '.join(params) or 'void'))
        fn.append('    uint64_t X[32]; uint64_t VR[32][2]; int N = 0, Z = 0, C = 0, V = 0; uint64_t RES = 0; (void)RES;')
        fn.append('    uint8_t stk_[0x1000] __attribute__((aligned(16)));')
        fn.append('    memset(X, 0, sizeof X); memset(VR, 0, sizeof VR);')
        fn.append('    X[31] = (uint64_t)(uintptr_t)(stk_ + 0x800); X[30] = 0xdead0000ull;')
        fn.append('    LIFT_ENTRY(); LIFT_STKINIT(stk_);')
        for p in pre: fn.append('    ' + p)
        fn.append(body)
        fn.append('Lret:')
        fn.append('    ' + ret)
        fn.append('}')
        return head, '\n'.join(fn)

def main():
    a = sys.argv
    ver, st, en, cname, sig = a[1], int(a[2], 16), int(a[3], 16), a[4], a[5]
    retk = 'x'; kinds = {}
    if '--ret' in a: retk = a[a.index('--ret') + 1]
    if '--kinds' in a:
        for kv in a[a.index('--kinds') + 1].split(','):
            k, v = kv.split('='); kinds[k if k.startswith('fn:') else 'msgSend:' + k] = v
    cls = a[a.index('--cls') + 1] if '--cls' in a else None
    L = Lift(ver, st, en, cname, sig, retk, kinds, cls)
    head, fn = L.generate()
    save_memo()
    print(head); print(fn)
    for w in L.stats['warn']: sys.stderr.write('WARN ' + w + '\n')

if __name__ == '__main__': main()
