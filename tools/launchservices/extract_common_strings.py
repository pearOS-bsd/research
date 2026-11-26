#!/usr/bin/env python3
"""Write plist_common_strings.txt: the list of common strings of Launch Services' property list compaction (LaunchServices
_LSPlistGetCommonStrings), read from the LaunchServices binary of the user's Mac (extracted from the dyld shared cache by `ipsw dyld extract`).
The list is metadata of the Apple binary and is NOT stored in this repository (.gitignore); lsbuild.py reads it when present.
usage: extract_common_strings.py LaunchServices-image > plist_common_strings.txt
How: the block of _LSPlistGetCommonStrings is a straight sequence of `lea rdx,[rip+cfstring]; call -[NSMutableArray addObject:]`; we collect the CFString
references of that block in order (the block ends where the next function starts) and read the string contents."""
import struct, sys, re
d = open(sys.argv[1], 'rb').read()
magic, cpu, sub, ft, ncmds = struct.unpack_from('<IiiII', d, 0)
secs = {}; off = 32
for _ in range(ncmds):
    cmd, cs = struct.unpack_from('<II', d, off)
    if cmd == 0x19:
        for k in range(struct.unpack_from('<I', d, off + 64)[0]):
            so = off + 72 + 80 * k; name = d[so:so + 16].split(b'\0')[0].decode(); addr, size, foff = struct.unpack_from('<QQI', d, so + 32); secs[name] = (addr, size, foff)
    off += cs
base_v = secs['__text'][0] - secs['__text'][2]          # image base: vm address of file offset 0
def foff(a, sec): return a - secs[sec][0] + secs[sec][2]
# locate the block: the function that stores into _LSPlistGetCommonStrings()::result is found through its first common string
first = b'UISupportedInterfaceOrientations\0'
cs_sec = secs['__cstring']; p = d.find(first, cs_sec[2], cs_sec[2] + cs_sec[1]); assert p > 0, 'string not found'
cf = secs['__cfstring']; ref = None
for i in range(cf[2], cf[2] + cf[1], 32):
    isa, fl, ptr, ln = struct.unpack_from('<QQQQ', d, i)
    if (ptr & 0xfffffffff) + 0x7ff800000000 - base_v == p: ref = i - cf[2] + cf[0]; break
assert ref, 'cfstring not found'
t = secs['__text']; txt = d[t[2]:t[2] + t[1]]
rx = struct.pack('<i', 0)                               # find the lea that references `ref`
pos = None
for m in re.finditer(b'\x48\x8d\x15', txt):
    disp = struct.unpack_from('<i', txt, m.start() + 3)[0]
    if t[0] + m.start() + 7 + disp == ref: pos = m.start(); break
assert pos is not None, 'block not found'
while txt[pos - 1:pos] != b'\x55' and pos > 0: pos -= 1       # walk back to the function prologue (push rbp)
out = []; i = pos
while len(out) < 4096:
    if txt[i:i + 3] == b'\x48\x8d\x15':
        a = t[0] + i + 7 + struct.unpack_from('<i', txt, i + 3)[0]
        if cf[0] <= a < cf[0] + cf[1]:
            isa, fl, ptr, ln = struct.unpack_from('<QQQQ', d, foff(a, '__cfstring'))
            q = (ptr & 0xfffffffff) + 0x7ff800000000 - base_v
            out.append(d[q:q + ln].decode('utf8'))
        i += 7; continue
    if txt[i:i + 2] == b'\x5d\xc3' and len(out) > 100: break    # pop rbp; ret ends the block
    i += 1
print('\n'.join(out))
