import re, sys
t=open(sys.argv[1]).read()
fns=re.findall(r'"(.*?)"', re.search(r'_fns\[\] = \{(.*?)\};', t).group(1))
seen={}
for m in re.finditer(r'CALLFN\(\w+_fns, (\d+), (\w+)\)', t):
    seen.setdefault(fns[int(m.group(1))], set()).add(m.group(2))
for k,v in sorted(seen.items()): print('%-50s %s' % (k, sorted(v)))
