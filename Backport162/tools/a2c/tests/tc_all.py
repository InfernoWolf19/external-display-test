#!/usr/bin/env python3
"""tc_all.py [job ...] [--seeds N] : tracecmp every body of the gen_y34.py jobs (calls, ownership events, PAC / block images, objc_super classes, memory, result) against the Unicorn emulation."""
import sys, os, subprocess
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..'))
import gen_y34, gen_y42
args = [a for a in sys.argv[1:] if not a.startswith('--')]
seeds = sys.argv[sys.argv.index('--seeds') + 1] if '--seeds' in sys.argv else '20'
if seeds in args: args.remove(seeds)
bad = 0
for job, d in gen_y34.JOBS.items():
    if args and job not in args: continue
    for (ver, st, en, cn, sig, ret, cls, kinds) in d['bodies']:
        if cn == 'lazy162': continue        # 1244 instructions: verified by lazy_test.py on 22704 inputs
        cmd = [sys.executable, os.path.join(HERE, 'tracecmp.py'), ver, '%x' % st, '%x' % en, cn, sig, ret, cls or '-', seeds]
        if kinds: cmd += ['--kinds', kinds]
        o = subprocess.run(cmd, capture_output=True, text=True)
        last = (o.stdout.strip().splitlines() or ['(no output) ' + o.stderr.strip()[-300:]])[-1]
        ok = ' mismatches 0,' in last
        bad += not ok
        print('%-5s %-6s %-22s %s' % ('OK' if ok else 'FAIL', job, cn, last)); sys.stdout.flush()
for job, d in gen_y42.JOBS.items():
    if args and job not in args: continue
    ends = {b[1]: b[2] for b in d['bodies']}
    names = {b[1]: b for b in d['bodies']}
    for (ver, st, en, cn, sig, ret, cls, kinds, locs) in d['bodies']:
        cmd = [sys.executable, os.path.join(HERE, 'tracecmp.py'), ver, '%x' % st, '%x' % en, cn, sig, ret, cls or '-', seeds]
        if kinds: cmd += ['--kinds', kinds]
        if locs: cmd += ['--locals', ','.join('%x:%x:%s:%s:%s' % (a, ends[a], c, names[a][4].replace(',', '+'), names[a][5]) for a, c in locs.items())]
        cmd += d.get('tcargs', [])
        o = subprocess.run(cmd, capture_output=True, text=True)
        last = (o.stdout.strip().splitlines() or ['(no output) ' + o.stderr.strip()[-300:]])[-1]
        ok = ' mismatches 0,' in last
        bad += not ok
        print('%-5s %-6s %-22s %s' % ('OK' if ok else 'FAIL', job, cn, last)); sys.stdout.flush()
sys.exit(1 if bad else 0)
