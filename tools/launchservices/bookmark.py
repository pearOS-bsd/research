#!/usr/bin/env python3
"""Reader/writer of the CFURL bookmark data format ('book', version 0x10050000) as stored in the Launch Services Alias table.
Layout learnt from the Alias units of a real store (docs/LAUNCHSERVICES-WIRE.md section 5.7); the container is the same for every bookmark:
  +0 'book' | u32 total size | u32 0x10050000 | u32 0x40 (header size) | zeros to 0x40
  +0x40 data area: items {u32 length, u32 type, payload padded to 4}; the first u32 of the area is the offset of the TOC (relative to 0x40)
  TOC = {u32 size, u32 0xfffffffe, u32 id 1, u32 next 0, u32 count, count x {u32 key, u32 offset, u32 0}}
item types: 0x0101 string, 0x0201 data, 0x0303 u32, 0x0304 u64, 0x0601 array (payload = u32 offsets of the elements), 0x0901 url, 0x0500/0x0501 false/true (length 0), 0x0801.. date
"""
import struct, sys

def decode(b):
    assert b[:4] == b'book', 'not bookmark data'
    total, ver, hsz = struct.unpack_from('<III', b, 4)
    base = 0x40
    toc_off, = struct.unpack_from('<I', b, base)
    t = base + toc_off
    size, magic, tid, nxt, cnt = struct.unpack_from('<IIIII', b, t)
    assert magic == 0xfffffffe
    def item(off):
        ln, ty = struct.unpack_from('<II', b, base + off)
        p = b[base + off + 8: base + off + 8 + ln]
        if ty == 0x0601: return ('array', [item(o) for o in struct.unpack('<%dI' % (ln // 4), p)])
        return (ty, bytes(p))
    items = {}
    for i in range(cnt):
        k, o, _ = struct.unpack_from('<III', b, t + 20 + 12 * i)
        items[k] = (o, item(o))
    return dict(version=ver, total=total, items=items)

def encode(items, version=0x10050000):
    """items: list of (key, value) in the order the data area is laid out; value = ('array', [values]) | (type, payload bytes).
    returns the bookmark bytes (the 4 bytes at 0x40 hold the TOC offset)."""
    area = bytearray(b'\0\0\0\0'); seen = {}
    def put(v):                                  # identical items are written once (the real files share e.g. the last path component with the file name)
        if v[0] == 'array':
            offs = [put(e) for e in v[1]]
            key = ('array', tuple(offs))
            if key in seen: return seen[key]
            o = len(area); area.extend(struct.pack('<II', 4 * len(offs), 0x0601) + b''.join(struct.pack('<I', x) for x in offs)); seen[key] = o; return o
        ty, p = v
        if (ty, p) in seen: return seen[(ty, p)]
        o = len(area); area.extend(struct.pack('<II', len(p), ty) + p + b'\0' * (-len(p) % 4)); seen[(ty, p)] = o; return o
    toc = [(k, put(v)) for k, v in items]
    toc.sort()
    toc_off = len(area)
    area.extend(struct.pack("<IIIII", 12 * len(toc) + 12, 0xfffffffe, 1, 0, len(toc)) + b''.join(struct.pack('<III', k, o, 0) for k, o in toc))
    struct.pack_into('<I', area, 0, toc_off)
    return b'book' + struct.pack('<III', 0x40 + len(area), version, 0x40) + b'\0' * (0x40 - 16) + bytes(area)

def for_path(path, inodes, date, file_id=None, volume=None, props=(2, 0xf, 0), components=None):
    """bookmark data of a directory at `path` (what lsd stores for an application).  inodes = file ids of every path component (root first),
    date = CFAbsoluteTime of the item, volume = dict(name, uuid, size, flags(24 bytes), url='file:///') of the volume (the system volume by default)."""
    v = dict(name='Untitled', uuid='FFB57133-8043-402E-B8A2-2FE703F20768', size=0x3ff37f6000, url='file:///', root=True,
             flags=bytes.fromhex('8100000001000000ef130000010000000000000001000000'), mount='/', date=0x41c8450f8c000000); v.update(volume or {})
    comps = components or [c for c in path.split('/') if c]            # components of the RESOLVED path (/tmp/x is private, tmp, x), `path` stays as given
    u64 = lambda x: (0x0304, struct.pack('<Q', x))
    s = lambda x: (0x0101, x.encode())
    dt = (0x0400, struct.pack('>d', date)); vdt = (0x0400, struct.pack('>Q', v['date']))
    items = [(0xd010, (0x0303, bytes.fromhex('00000020'))), (0x1004, ('array', [s(c) for c in comps])), (0x1020, s(comps[-1])),
             (0x1005, ('array', [u64(i) for i in inodes])), (0x1030, u64(file_id if file_id is not None else inodes[-1])), (0x1040, dt),
             (0x1010, (0x0201, struct.pack('<QQQ', *props))), (0x2005, (0x0901, v['url'].encode())), (0x2010, s(v['name'])), (0x2012, u64(v['size'])), (0x2013, vdt),
             (0x2011, s(v['uuid'])), (0x2020, (0x0201, v['flags'])), (0x2002, s(v['mount'])), (0x2030, (0x0501 if v['root'] else 0x0500, b'')), (0xff00, s(path))]
    return encode(items)

if __name__ == '__main__':
    d = decode(open(sys.argv[1], 'rb').read())
    def show(v, ind=''):
        if v[0] == 'array':
            print(ind + 'array'); [show(e, ind + '  ') for e in v[1]]
        else:
            ty, p = v
            print(ind + '%#06x' % ty, p.decode('utf8', 'replace') if ty in (0x101, 0x901) else p.hex())
    for k, (o, v) in sorted(d['items'].items(), key=lambda kv: kv[1][0]):
        print('key %#06x at %#x' % (k, o)); show(v, '  ')
