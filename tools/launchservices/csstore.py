#!/usr/bin/env python3
"""Read-only parser of the CSStore2 container (magic 'bdsl', version 2) as used by Launch Services.
Format derived from CoreServicesStore (CSStore2::Store::_Create/getUnit) and from dumps of a real store, see docs/LAUNCHSERVICES-WIRE.md.
usage: csstore.py FILE            list tables
       csstore.py FILE TABLE [N]  list the first N units of a table (name or id), hex payload
"""
import struct, sys, zlib

class Store:
    def __init__(s, data):
        s.d = data
        magic, ver, flags, crc, gen, used, live = struct.unpack_from('<IBBHIII', data, 0)
        assert magic == 0x6c736462 and ver == 2, 'not a CSStore2'
        s.gen, s.used, s.live, s.crc = gen, used, live, crc
        s.tables = {}
        cat = 0x14                         # the catalog table is the first unit, at offset 0x14
        s.catalog = s.table_at(cat)
        for tid, off in s.idmap(s.catalog['idmap']):
            t = s.table_at(off)
            t['id'] = tid
            s.tables[t['name']] = t
        s.by_id = {t['id']: t for t in s.tables.values()}
    def check_crc(s):
        c = zlib.crc32(s.d[100:s.used], 0x6e797267) & 0xffffffff
        return (c & 0xffff) == s.crc
    def table_at(s, off):
        hdr, ln = struct.unpack_from('<II', s.d, off)
        name = s.d[off+8:off+56].split(b'\0')[0].decode()
        x2, x3, x4, x5 = struct.unpack_from('<QQII', s.d, off+56)
        return dict(off=off, hdr=hdr, name=name, x2=x2, x3=x3, nextid=x4, idmap=x5)
    def idmap(s, off):
        """HashMap<id,offset>: u32 nbuckets; nbuckets*{u32 count,u32 entries_offset}; entries {u32 key,u32 value}"""
        if off == 0xffffffff: return
        nb, = struct.unpack_from('<I', s.d, off)
        for b in range(nb):
            cnt, eo = struct.unpack_from('<II', s.d, off+4+8*b)
            for i in range(cnt):
                k, v = struct.unpack_from('<II', s.d, eo+8*i)
                if v != 0xffffffff: yield k, v
    def units(s, table):
        t = s.tables[table] if isinstance(table, str) else s.by_id[table]
        for uid, off in s.idmap(t['idmap']):
            hdr, ln = struct.unpack_from('<II', s.d, off)
            yield uid, hdr, s.d[off+8:off+8+ln]

if __name__ == '__main__':
    st = Store(open(sys.argv[1], 'rb').read())
    print('gen', st.gen, 'used', st.used, 'live', st.live, 'crc ok', st.check_crc())
    if len(sys.argv) == 2:
        for t in sorted(st.tables.values(), key=lambda t: t['id']):
            n = sum(1 for _ in st.units(t['name']))
            print('%#06x %-34s nextid=%#x idmap=%#x units=%d' % (t['id'], t['name'], t['nextid'], t['idmap'], n))
    else:
        t = sys.argv[2]
        t = int(t, 0) if t.startswith('0') else t
        lim = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        for i, (uid, hdr, p) in enumerate(st.units(t)):
            if i >= lim: break
            print('unit %#x hdr %#x len %d: %s' % (uid, hdr, len(p), p[:96].hex()))
