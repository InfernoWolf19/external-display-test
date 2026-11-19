#!/usr/bin/env python3
"""clsuse.py lifted.c ... : classify every CLS() use of a lifted file: super receiver (stored for objc_msgSendSuper2), alloc (objc_alloc / alloc / new: redirected to a registered runtime subclass by lift_msg_fix / lift_intercept),
type check (objc_opt_isKindOfClass / SBSafeCast / isKindOfClass: / class equality), class method receiver (any other message), or other.  CLS() always answers the REAL class (Y34LiftRT.c)."""
import sys, re
for f in sys.argv[1:]:
    txt = open(f).read().splitlines()
    cur = None; fnsets = {}
    for l in txt:
        m = re.match(r'static const char \*const (\w+)_fns\[\] = \{(.*?)\};', l)
        if m: fnsets[m.group(1)] = re.findall(r'"(.*?)"', m.group(2))
        m = re.match(r'static const char \*const (\w+)_cls\[\] = \{(.*?)\};', l)
    for i, l in enumerate(txt):
        m = re.search(r'CLS\((\w+)_cls, (\d+)\)', l)
        if not m: continue
        body, k = m.group(1), int(m.group(2))
        cm = re.search(r'static const char \*const %s_cls\[\] = \{(.*?)\};' % body, '\n'.join(txt))
        name = re.findall(r'"(.*?)"', cm.group(1))[k]
        kind = 'other'
        for j in range(i + 1, min(i + 14, len(txt))):
            t = txt[j]
            if 'ST64' in t and 'objc_super' not in t and re.search(r'X\[\d+\]\);', t) and 'CALL' not in t and kind == 'other' and 'msgSendSuper2' in '\n'.join(txt[j:j + 12]): kind = 'super receiver'; break
            fm = re.search(r'CALLFN\((\w+)_fns, (\d+)', t)
            if fm:
                fn = fnsets.get(fm.group(1), [])[int(fm.group(2))].lstrip('_')
                kind = 'alloc' if fn in ('objc_alloc', 'objc_alloc_init', 'objc_opt_new', 'objc_allocWithZone') else ('type check' if fn in ('objc_opt_isKindOfClass', 'SBSafeCast') else 'C function argument (%s)' % fn)
                break
            if 'CALLMSG' in t:
                sm = re.search(r'SEL\((\w+)_sels, (\d+)\)', '\n'.join(txt[i:j + 1]))
                sel = re.findall(r'"(.*?)"', re.search(r'static const char \*const %s_sels\[\] = \{(.*?)\};' % body, '\n'.join(txt)).group(1))[int(sm.group(2))] if sm else '?'
                kind = 'alloc / new (class method, redirected)' if sel in ('alloc', 'new', 'allocWithZone:') else ('type check (%s)' % sel if sel in ('isKindOfClass:', 'isMemberOfClass:', 'isSubclassOfClass:') else 'class method receiver (%s)' % sel)
                break
        print('%-28s %-8s %-48s %s' % (f.split('/')[-1], body, name, kind))
