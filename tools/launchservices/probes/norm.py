#!/usr/bin/env python3
"""Normalize an lsx transcript (stdin) so that two servers can be diffed: object addresses, times, pids, ASNs, coalition ids, inodes,
audit tokens and session numbers become stable names (ASN1, ASN2 ... in order of appearance); the entries of every dictionary are sorted
by key (libxpc prints them in hash order)."""
import re, sys
t = sys.stdin.read()
t = re.sub(r'<([a-z0-9 ]+): 0x[0-9a-f]+>', r'<\1>', t)
t = re.sub(r'voucher = 0x[0-9a-f]+', 'voucher', t)
t = re.sub(r'transaction: \d', 'transaction', t)
t = re.sub(r't=[\d.]+', 't', t)
t = re.sub(r'<date> .*', '<date> DATE', t)
t = re.sub(r'(contents = 0x)[0-9a-f]+\.\.\.', r'\1TOKEN', t)
t = re.sub(r'("when" => <double>: )[\d.]+', r'\1WHEN', t)
t = re.sub(r'(name = )\d+', r'\1PORT', t)
for k in ['pid', 'LSApplicationMemberCoalitionIDKey', 'LSApplicationCoalitionIDKey', 'CFBundleExecutablePathINode', 'CFBundleExecutablePathDeviceID',
          'session', 'id', 'seed', 'ChangeCount', 'clientid', 'msgid']:
    t = re.sub(r'("%s" => <u?int64>: )-?\d+' % k, r'\1N', t)
t = re.sub(r'NOTE-PEER pid=\d+', 'NOTE-PEER', t)
names = {}
def asn(m):
    v = m.group(2)
    if v not in names: names[v] = 'ASN%d' % (len(names) + 1)
    return m.group(1) + names[v]
t = re.sub(r'("(?:asn|asn1|asn2|affected|com\.apple\.coreservices\.asn\.lo)" => <uint64>: )(\d+)', asn, t)

# sort dictionary entries: parse blocks by indentation
lines = t.split('\n')
def block(i, depth):
    """lines[i:] at indentation depth: list of entries (text lines) until a closing '}' at depth-1; returns (entries, next i)"""
    out = []
    while i < len(lines):
        l = lines[i]
        ind = len(l) - len(l.lstrip('\t'))
        if l.strip() == '}' and ind == depth - 1: return out, i
        if ind < depth and depth > 0: return out, i
        if l.rstrip().endswith('contents ='):
            kids, j = block(i + 1, ind + 1)
            if 'dictionary' in l: kids.sort(key=lambda e: e[0])
            close = lines[j] if j < len(lines) else ''
            out.append((l, kids, close)); i = j + 1
        else:
            out.append((l, [], None)); i += 1
    return out, i
def emit(es, o):
    for h, kids, close in es:
        o.append(h)
        if close is not None: emit(kids, o); o.append(close)
ents, _ = block(0, 0)
o = []; emit(ents, o)
sys.stdout.write('\n'.join(o))
