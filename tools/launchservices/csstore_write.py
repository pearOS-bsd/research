#!/usr/bin/env python3
"""Writer for the CSStore2 container (see docs/LAUNCHSERVICES-WIRE.md section 6).  Builds a store from tables that
contain units; bump-allocates 4-byte aligned units, writes the id maps (HashMap id->offset, bucket=(id>>2)%nbuckets), the catalog,
the header and the CRC.  Used to test what Apple's reader accepts (lsregister -dump FILE).
"""
import struct, zlib, sys

def align4(n): return (n + 3) & ~3

class Table:
    def __init__(self, name, tid, extra=b'', nextid=0):
        self.name, self.id, self.extra, self.nextid = name, tid, extra, nextid
        self.units = {}            # unit id -> payload bytes
        self.nbuckets = 0          # id map size (0 = number of units, at least 16)
    def add(self, payload, uid=None):
        if uid is None:
            self.nextid += 1; uid = self.nextid * 4
        else:
            self.nextid = max(self.nextid, uid // 4)
        self.units[uid] = payload; return uid

def build(tables, generation=1):
    """tables: list of Table in catalog order (first table id is 4).  Returns bytes."""
    out = bytearray(0x14)                        # header filled at the end
    def put(b):                                  # append 4-aligned, return offset
        while len(out) % 4: out.append(0)
        o = len(out); out.extend(b); return o
    def unit(hdr, payload): return struct.pack('<II', hdr, len(payload)) + payload
    def idmap(entries, nb=None):                 # entries: list of (key, value)
        nb = nb or max(16, len(entries))
        bk = [[] for _ in range(nb)]
        for k, v in entries: bk[(k >> 2) % nb].append((k, v))
        base = len(out) + (-len(out) % 4)
        ent_off = base + 4 + 8 * nb
        hdr = struct.pack('<I', nb); ents = b''; cur = ent_off
        for b in bk:
            hdr += struct.pack('<II', len(b), cur)
            for k, v in b: ents += struct.pack('<II', k, v); cur += 8
        return put(hdr + ents)
    cat_off = 0x14
    tbl_off = {}
    # reserve the catalog table unit at 0x14 (80 bytes), patched after the layout is known
    out.extend(b'\0' * 80)
    placed = []
    for t in tables:
        # table unit placed now with a dummy idmap offset; patched below
        off = put(unit(0x40000000 | (t.id >> 2), b'\0' * (72 + len(t.extra))))
        tbl_off[t.id] = off
        ents = []
        for uid, payload in sorted(t.units.items()):
            uo = put(unit(uid >> 2, payload)); ents.append((uid, uo))
        im = idmap(ents, t.nbuckets or None)
        placed.append((t, off, im))
    for t, off, im in placed:
        name = t.name.encode().ljust(48, b'\0')
        body = name + struct.pack('<QQII', 0, 0, t.nextid, im) + t.extra
        struct.pack_into('<II', out, off, 0x40000000 | (t.id >> 2), len(body)); out[off + 8:off + 8 + len(body)] = body
    cim = idmap([(t.id, tbl_off[t.id]) for t in tables])
    cname = b'<catalog>'.ljust(48, b'\0')
    body = cname + struct.pack('<QQII', 0, 0, 0x21, cim)
    struct.pack_into('<II', out, cat_off, 0x7fffdb5d, len(body)); out[cat_off + 8:cat_off + 8 + len(body)] = body
    used = len(out)
    struct.pack_into('<IBBHIII', out, 0, 0x6c736462, 2, 0, 0, generation, used, used)
    c = zlib.crc32(bytes(out[100:used]), 0x6e797267) & 0xffffffff
    c = c & 0xffff if (c & 0xffff) > 2 else (c | 0xffffe000) & 0xffff
    struct.pack_into('<H', out, 6, c)
    # pad to a page multiple like the real files (size is a multiple of 4096)
    out.extend(b'\0' * (-len(out) % 4096))
    return bytes(out)
