#!/usr/bin/env python3
"""Extract the dyld shared cache set (all subcaches, .symbols, .dyldlinkedit) from an IPSW system cryptex DMG
with NO apfs-fuse: apfsmini.py reads the sealed APFS volume (hashed nodes, fext tree) and the decmpfs LZBITMAP
(type 14, resource fork) files are decompressed with libzbitmap (source: Go module github.com/blacktop/lzfse-cgo,
libzbitmap.c / libzbitmap.h; build: gcc -O2 -shared -fPIC -o libzbm.so libzbitmap.c).
usage: extract_dsc.py <cryptex.dmg> <out dir> <libzbm.so>
The DMG: pip install remotezip; RemoteZip(<ipsw url>).extract('078-xxxxx-xxx.dmg') (the one named ...SystemCryptex,
about 1 GB compressed for iPadOS 16.2 20C65; the url comes from api.ipsw.me /v4/device/<product>?type=ipsw).
"""
import sys, struct, ctypes, io, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import apfsmini
dmg, out, so = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
lib = ctypes.CDLL(so)
lib.zbm_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
a = apfsmini.APFS(dmg); a.build_scan(); a.build_fext()
d = a.lookup('/System/Library/Caches/com.apple.dyld')

def dstream(v):
    x = v[92:]; n, used = struct.unpack('<HH', x[:4]); p = 4; hdr = []
    for i in range(n):
        t, fl, sz = struct.unpack('<BBH', x[p:p + 4]); hdr.append((t, sz)); p += 4
    for t, sz in hdr:
        if t == 8:
            return struct.unpack('<Q', x[p:p + 8])[0]
        p += (sz + 7) & ~7

def rsrc(oid):
    v = a.xattr[oid]['com.apple.ResourceFork']
    xid, size = struct.unpack('<QQ', v[4:20])
    b = io.BytesIO()
    for la, l, pb in sorted(a.ext[xid]):
        a.f.seek(pb * 4096); b.write(a.f.read(l))
    return b.getvalue()[:size]

for name, o in sorted(a.drec[d].items()):
    if not name.startswith('dyld_shared_cache_'):
        continue
    if dstream(a.ino[o]) is not None:
        with open(os.path.join(out, name), 'wb') as f:
            a.read_file(o, f)
        continue
    dm = a.xattr[o]['com.apple.decmpfs']
    ln = struct.unpack('<HH', dm[:4])[1]
    magic, ctype, usize = struct.unpack('<4sIQ', dm[4:20])
    assert magic == b'fpmc' and ctype == 14, (name, magic, ctype)
    rs = rsrc(o)
    first = struct.unpack('<I', rs[:4])[0]
    offs = list(struct.unpack('<%dI' % (first // 4), rs[:first])) + [len(rs)]
    res = bytearray()
    for i in range(len(offs) - 1):
        blk = rs[offs[i]:offs[i + 1]]
        want = min(0x10000, usize - len(res))
        buf = ctypes.create_string_buffer(0x10000); ol = ctypes.c_size_t(0)
        if lib.zbm_decompress(buf, 0x10000, blk, len(blk), ctypes.byref(ol)) == 0:
            res += buf.raw[:ol.value]
        elif len(blk) in (want, want + 1):
            res += blk[-want:]
        else:
            raise SystemExit('bad block %d of %s' % (i, name))
    assert len(res) == usize
    open(os.path.join(out, name), 'wb').write(bytes(res))
    print(name, usize)
