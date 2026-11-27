#!/usr/bin/env python3
"""Self-test of infopage.py: a page laid out like the one lsd-stub writes (header of
LSSharedMemoryPage(LSSessionID) + one record) must decode to the same fields."""
import os
import struct
import subprocess
import sys
import tempfile

page = bytearray(61440)
struct.pack_into("<III", page, 0, 0x104, 61440, 100001)
for off in range(0x20, 0x38, 4):
    struct.pack_into("<I", page, off, 100)
struct.pack_into("<I", page, 0x68, 257)
struct.pack_into("<II", page, 0x88, 1, 0x32a)
struct.pack_into("<IIIH2xiiQQi4xQi4xQ", page, 0x90, 0x89089, 0x202, 0x80, 1, 4242, 7,
                 0x405fb37c70e1a673, 0xdb610cddec279fbc, 0x100000a, 0x0fffffff00037386, 0x100000a, 0x0fffffff0003738b)
with tempfile.NamedTemporaryFile(delete=False) as f:
    f.write(page)
here = os.path.dirname(os.path.abspath(__file__))
out = subprocess.run([sys.executable, "-I", os.path.join(here, "infopage.py"), f.name], check=True, capture_output=True, text=True).stdout
os.unlink(f.name)
for want in ("version (0x104)                    0x104", "sessionID                          0x186a1", "applicationListCount               0x1",
             "0x89089", "4242", "405fb37c70e1a673", "0xfffffff0003738b"):
    assert want in out, (want, out)
print("infopage.py: ok")
