#!/usr/bin/env python3
"""Compare two Dock startup traces (capture.sh): python3 compare.py REAL.txt OURS.txt [--order] [--all-opens]
Kinds: LOOKUP CHECKIN XPCSVC PREF OPEN.  OPEN is reduced to what is not the dynamic loader's noise (dylibs, frameworks, /dev, Cryptexes copies) unless --all-opens.
Exit 0 only when every kind has the same set (and, with --order, the same first-occurrence order).  Prints what is missing in ours (-) and what ours has extra (+)."""
import sys,re
a=[x for x in sys.argv[1:] if not x.startswith('--')]; order='--order' in sys.argv; allo='--all-opens' in sys.argv
NOISE=re.compile(r'\.dylib$|^/usr/lib|/System/Library/(Frameworks|PrivateFrameworks)/|Cryptexes|^/dev/|^/$|/System/Library/dyld|^System/Library/dyld')
def load(p):
    d={}
    for l in open(p,errors='replace'):
        l=l.rstrip('\n')
        if not l: continue
        k,_,v=l.partition(' ')
        if k=='OPENAT': k='OPEN'
        if k=='STAT': continue
        if k=='OPEN' and not allo and NOISE.search(v): continue
        d.setdefault(k,[]).append(v)
    return d
A,B=load(a[0]),load(a[1]); bad=0
for k in sorted(set(A)|set(B)):
    sa=list(dict.fromkeys(A.get(k,[]))); sb=list(dict.fromkeys(B.get(k,[])))
    miss=[x for x in sa if x not in sb]; extra=[x for x in sb if x not in sa]
    ok=not miss and not extra
    if ok and order and k!='OPEN': ok=sa==sb       # the order of file opens varies between two runs of the real Dock
    print(f'{k:8} real {len(sa):3}  ours {len(sb):3}  {"same" if ok else "DIFFERENT"}')
    for x in miss[:25]: print('   -',x)
    for x in extra[:25]: print('   +',x)
    if len(miss)>25 or len(extra)>25: print('   ...')
    if not ok: bad=1
    if not ok and not miss and not extra: print('   (same set, other order)')
sys.exit(bad)
