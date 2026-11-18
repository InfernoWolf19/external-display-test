#!/usr/bin/env python3
# minimal read-only APFS reader (no checksum verification, sealed volumes ok, no compression/encryption)
import struct, sys, collections
BS = 4096

class APFS:
    def __init__(self, path):
        self.f = open(path, 'rb')
        nx = self.blk(0)
        assert nx[32:36] == b'NXSB'
        dblk, xblk, dbase, xbase = struct.unpack('<IIqq', nx[104:128])
        best = None
        for i in range(dblk):
            b = self.blk(dbase + i)
            if b[32:36] == b'NXSB':
                xid = struct.unpack('<Q', b[16:24])[0]
                if best is None or xid > best[0]:
                    best = (xid, b)
        self.xid, nx = best
        self.nx = nx
        self.fs_oid = struct.unpack('<Q', nx[184:192])[0]
        om = self.blk(struct.unpack('<Q', nx[160:168])[0])
        self.nx_omap_tree = struct.unpack('<Q', om[48:56])[0]
        pa = self.omap_lookup(self.nx_omap_tree, self.fs_oid)
        self.apsb = self.blk(pa)
        assert self.apsb[32:36] == b'APSB'
        vom = self.blk(struct.unpack('<Q', self.apsb[128:136])[0])
        self.vol_omap_tree = struct.unpack('<Q', vom[48:56])[0]
        self.root_oid = struct.unpack('<Q', self.apsb[136:144])[0]

    def blk(self, n):
        self.f.seek(n * BS)
        return self.f.read(BS)

    @staticmethod
    def node(b):
        # header (obj_phys_t) present iff the object type at +24 is btree / btree node; sealed hashed nodes have none
        h = 32
        flags, level, nkeys = struct.unpack('<HHI', b[h:h + 8])
        toff, tlen = struct.unpack('<HH', b[h + 8:h + 12])
        return flags, level, nkeys, toff, tlen, h

    def entries(self, b):
        flags, level, nkeys, toff, tlen, h = self.node(b)
        fixed = flags & 4
        kbase = h + 24 + toff + tlen
        vend = BS - 40 if flags & 1 else BS
        for i in range(nkeys):
            if fixed:
                ko, vo = struct.unpack('<HH', b[h + 24 + toff + i * 4:h + 24 + toff + i * 4 + 4])
                kl, vl = 16, (16 if level == 0 else 8)
            else:
                ko, kl, vo, vl = struct.unpack('<HHHH', b[h + 24 + toff + i * 8:h + 24 + toff + i * 8 + 8])
            key = b[kbase + ko:kbase + ko + kl]
            val = b[vend - vo:vend - vo + vl] if vo != 0xFFFF else b''
            yield key, val

    def omap_lookup(self, tree, oid, xid=None):
        xid = xid or self.xid
        b = self.blk(tree)
        while True:
            flags, level, nkeys, toff, tlen, h = self.node(b)
            best = None
            for key, val in self.entries(b):
                koid, kxid = struct.unpack('<QQ', key)
                if koid < oid or (koid == oid and kxid <= xid):
                    best = (koid, kxid, val)
                    if koid == oid and kxid == xid:
                        break
            if level == 0:
                if best is None or best[0] != oid:
                    raise KeyError(hex(oid))
                return struct.unpack('<Q', best[2][8:16])[0]
            b = self.blk(struct.unpack('<Q', best[2][:8])[0])

    def fs_records(self, node_oid=None, b=None):
        if b is None:
            pa = self.omap_lookup(self.vol_omap_tree, node_oid)
            b = self.blk(pa)
        flags, level, nkeys, toff, tlen, h = self.node(b)
        for key, val in self.entries(b):
            if level == 0:
                yield key, val
            else:
                child = struct.unpack('<Q', val[:8])[0]
                yield from self.fs_records(b=self.blk(child))

    def build_scan(self):
        # tree-structure independent: parse every fs-tree leaf reachable through the volume omap
        import collections
        self.drec = collections.defaultdict(dict); self.ext = collections.defaultdict(list); self.ino = {}; self.xattr = {}
        om = self.blk(self.vol_omap_tree)
        leaves = [struct.unpack('<Q', v[:8])[0] for k, v in self.entries(om)]
        best = {}
        for pa in leaves:
            for k, v in self.entries(self.blk(pa)):
                oid, xid = struct.unpack('<QQ', k)
                fl, sz, paddr = struct.unpack('<IIQ', v[:16])
                if xid <= self.xid and (oid not in best or best[oid][0] < xid):
                    best[oid] = (xid, paddr)
        n = 0
        for oid, (xid, paddr) in best.items():
            b = self.blk(paddr)
            fl, lv, nk, to, tl, h = self.node(b)
            if lv != 0 or nk == 0 or nk > 2000 or h + 24 + to + tl > BS:
                continue
            n += 1
            try:
                for key, val in self.entries(b):
                    self._rec(key, val)
            except Exception:
                pass
        self.leaves = n

    def build_fext(self):
        root = struct.unpack('<Q', self.apsb[1032:1040])[0]
        def walk(pa, d=0):
            b = self.blk(pa)
            fl, lv, nk, to, tl, h = self.node(b)
            for key, val in self.entries(b):
                if lv == 0:
                    pid, la = struct.unpack('<QQ', key[:16])
                    lf, pb = struct.unpack('<QQ', val[:16])
                    self.ext[pid].append((la, lf & 0x00FFFFFFFFFFFFFF, pb))
                else:
                    walk(struct.unpack('<Q', val[:8])[0], d + 1)
        walk(root)

    def _rec(self, key, val):
        if len(key) < 8:
            return
        h = struct.unpack('<Q', key[:8])[0]
        oid, typ = h & 0x0FFFFFFFFFFFFFFF, h >> 60
        if typ == 9 and len(key) >= 12:
            nlh = struct.unpack('<I', key[8:12])[0]
            name = key[12:12 + (nlh & 0x3FF)].rstrip(b'\0').decode('utf8', 'replace')
            self.drec[oid][name] = struct.unpack('<Q', val[:8])[0]
        elif typ == 8 and len(key) >= 16 and len(val) >= 16:
            la = struct.unpack('<Q', key[8:16])[0]
            lf, pb = struct.unpack('<QQ', val[:16])
            self.ext[oid].append((la, lf & 0x00FFFFFFFFFFFFFF, pb))
        elif typ == 3:
            self.ino[oid] = val
        elif typ == 4 and len(key) >= 10:
            nl = struct.unpack('<H', key[8:10])[0]
            self.xattr.setdefault(oid, {})[key[10:10 + nl].rstrip(b'\0').decode('utf8','replace')] = val

    def build(self):
        self.drec = collections.defaultdict(dict)
        self.ext = collections.defaultdict(list)
        self.ino = {}
        for key, val in self.fs_records(self.root_oid):
            h = struct.unpack('<Q', key[:8])[0]
            oid, typ = h & 0x0FFFFFFFFFFFFFFF, h >> 60
            if typ == 9:   # drec
                nlh = struct.unpack('<I', key[8:12])[0]
                name = key[12:12 + (nlh & 0x3FF)].rstrip(b'\0').decode('utf8', 'replace')
                self.drec[oid][name] = struct.unpack('<Q', val[:8])[0]
            elif typ == 8:  # file extent
                la = struct.unpack('<Q', key[8:16])[0]
                lf, pb = struct.unpack('<QQ', val[:16])
                self.ext[oid].append((la, lf & 0x00FFFFFFFFFFFFFF, pb))
            elif typ == 3:  # inode
                self.ino[oid] = val

    def lookup(self, path):
        cur = 2
        for p in [x for x in path.split('/') if x]:
            cur = self.drec[cur][p]
        return cur

    def size(self, oid):
        v = self.ino[oid]
        # j_inode_val: parent,private,create,mod,change,access (6*8) internal_flags(8) nchildren(4) default_prot(4) write_gen(4) bsd_flags(4) owner(4) group(4) mode(2) pad(2) uncompressed_size(8)
        return struct.unpack('<Q', v[84:92])[0] if len(v) >= 92 else None

    def extents_size(self, oid):
        e = sorted(self.ext[oid])
        return (e[-1][0] + e[-1][1]) if e else 0

    def read_file(self, oid, out, chunk=1 << 24):
        n = 0
        pid = struct.unpack('<Q', self.ino[oid][8:16])[0]
        for la, ln, pb in sorted(self.ext[pid]):
            assert la == n or la >= n, (la, n)
            if la > n:
                out.write(b'\0' * (la - n)); n = la
            self.f.seek(pb * BS)
            left = ln
            while left:
                d = self.f.read(min(chunk, left)); out.write(d); left -= len(d)
            n += ln
        return n


if __name__ == '__main__':
    a = APFS(sys.argv[1])
    a.build_scan(); a.build_fext()
    print('leaves', a.leaves, 'xid', a.xid, 'inodes', len(a.ino), 'drec dirs', len(a.drec))
    cmd = sys.argv[2]
    if cmd == 'ls':
        d = a.lookup(sys.argv[3])
        for n, o in sorted(a.drec[d].items()):
            print(n, o)
    elif cmd == 'cat':
        o = a.lookup(sys.argv[3])
        a.read_file(o, open(sys.argv[4], 'wb'))
