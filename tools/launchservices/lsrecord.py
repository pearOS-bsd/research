#!/usr/bin/env python3
"""Decode LaunchServices (structs are #pragma pack(4): 8-byte members are 4-aligned) record units from an ObjC type encoding with field names (as found in the LaunchServices binary).
Natural x86_64 alignment; a struct of bitfields (b1...) is stored in `bits_storage` bytes."""
import re, struct

def parse(enc, i=0):
    """returns (node, next).  node = ('struct', name, [(field, node)...]) | ('prim', ch) | ('array', n, node) | ('bits', n)"""
    c = enc[i]
    if c == '{':
        j = enc.index('=', i); name = enc[i+1:j]; i = j + 1; fields = []
        while enc[i] != '}':
            fname = None
            if enc[i] == '"':
                k = enc.index('"', i+1); fname = enc[i+1:k]; i = k + 1
            node, i = parse(enc, i); fields.append((fname, node))
        return ('struct', name, fields), i + 1
    if c == '[':
        m = re.match(r'\[(\d+)', enc[i:]); n = int(m.group(1)); node, k = parse(enc, i + m.end())
        assert enc[k] == ']'; return ('array', n, node), k + 1
    if c == 'b':
        m = re.match(r'b(\d+)', enc[i:]); return ('bits', int(m.group(1))), i + m.end()
    return ('prim', c), i + 1

SZ = {'I': 4, 'i': 4, 'Q': 8, 'q': 8, 'C': 1, 'c': 1, 'S': 2, 's': 2, 'B': 1, 'd': 8, 'f': 4}

def layout(node, off=0, bits_storage=0, qa=4):
    """returns (size, align, [(path, offset, kind)])"""
    k = node[0]
    if k == 'prim': s = SZ[node[1]]; return s, min(s, qa), [('', 0, node[1])]
    if k == 'array':
        s, a, f = layout(node[2], 0, bits_storage, qa); return s * node[1], a, [('', 0, 'A%d%s' % (node[1], node[2][1] if node[2][0] == 'prim' else '?'))]
    if k == 'struct':
        o = 0; al = 1; out = []; bits = 0
        fields = node[2]
        # a struct made only of bitfields is stored in bits_storage bytes
        if all(f[1][0] == 'bits' for f in fields):
            nb = sum(f[1][1] for f in fields)
            st = next(x for x in (1, 2, 4, 8) if nb <= x * 8) if bits_storage == 0 else bits_storage
            return st, min(st, qa), [(f[0], 0, 'bit%d' % f[1][1]) for f in fields]
        for fname, sub in fields:
            s, a, sf = layout(sub, 0, bits_storage, qa); al = max(al, a); o = (o + a - 1) & ~(a - 1)
            if sub[0] == 'struct':
                for p, po, kd in sf: out.append(((fname + '.' if fname else '') + p, o + po, kd))
            else: out.append((fname, o, sf[0][2]))
            o += s
        o = (o + al - 1) & ~(al - 1)
        return o, al, out

def fields_of(enc, bits_storage=0):
    node, _ = parse(enc); size, al, f = layout(node, 0, bits_storage); return size, f


def decode(enc, payload):
    size, flds = fields_of(enc)
    out = {}
    for name, off, kind in flds:
        if kind == 'I': out[name] = struct.unpack_from('<I', payload, off)[0]
        elif kind == 'i': out[name] = struct.unpack_from('<i', payload, off)[0]
        elif kind == 'Q': out[name] = struct.unpack_from('<Q', payload, off)[0]
        elif kind == 'C': out[name] = payload[off]
        elif kind == 'S': out[name] = struct.unpack_from('<H', payload, off)[0]
        elif kind.startswith('A'): out[name] = payload[off:off+int(kind[1:].rstrip('C?I'))]
        elif kind.startswith('bit'): out[name] = ('bits', off)
    return out
