#!/usr/bin/env python3
"""Decode a launchservicesd info page (the `lsinfopage` shared memory of command 110).

python3 infopage.py PAGE.bin [lsappinfo-list.txt]

Layout: research/docs/LAUNCHSERVICES-WIRE.md section 6.3 (decompiled from LaunchServices
LSSharedMemoryPage::*, _LSSharedMemoryGet*).  With the output of `lsappinfo list` the
records are joined with the application names by ASN.
"""
import re
import struct
import sys

HDR = [
    (0x00, "version (0x104)"), (0x04, "size"), (0x08, "sessionID"), (0x0c, "lockCount"),
    (0x10, "debugLevel"), (0x14, "changeCount"),
    (0x20, "frontApplicationASNSeed"), (0x24, "menuBarOwnerASNSeed"), (0x28, "applicationListSeed"),
    (0x2c, "pendingApplicationListSeed"), (0x30, "visibleApplicationListSeed"),
    (0x34, "applicationInformationSeed"),
    (0x50, "frontASNLow"), (0x54, "menuBarOwnerASNLow"), (0x58, "systemProcessASNLow"),
    (0x5c, "sessionLauncherASNLow"), (0x60, "launchProgressFlags"),
    (0x64, "launchProgressUserActivityCount"), (0x68, "CGSSessionID"),
    (0x6c, "nextAppToBringForwardASNLow"), (0x70, "systemUIPresentationMode"),
    (0x74, "metaInformationFlags"), (0x78, "systemUIPresentationOptions"),
    (0x7c, "expectedFrontApplicationASNLow"), (0x88, "applicationListCount"),
    (0x8c, "applicationListCapacity (0x32a)"),
]
REC = struct.Struct("<IIIH2xiiQQi4xQi4xQ")   # 72 bytes at 0x90 + i * 0x48


def main():
    b = open(sys.argv[1], "rb").read()
    names = {}
    if len(sys.argv) > 2:
        for m in re.finditer(r'"([^"]*)" ASN:0x0-0x([0-9a-f]+):', open(sys.argv[2]).read()):
            names[int(m.group(2), 16)] = m.group(1)
    for off, n in HDR:
        v = struct.unpack_from("<I", b, off)[0]
        extra = " (%s)" % names[v] if n.endswith("ASNLow") and v in names else ""
        print("%#06x %-34s %#x%s" % (off, n, v, extra))
    used = [o for o in range(0x18, 0x90, 4) if o not in dict(HDR) and struct.unpack_from("<I", b, o)[0]]
    if used:
        print("unnamed header words that are not zero:", ", ".join("%#x" % o for o in used))
    cnt = min(struct.unpack_from("<I", b, 0x88)[0], 0x32a)
    print("\n idx  asnLow   chg      flags    u16  pid    pidver bundleIDHash     execNameHash     bndlDev    bndlIno            execDev    execIno            name")
    for i in range(cnt):
        r = REC.unpack_from(b, 0x90 + i * 0x48)
        print("%4d  %#-8x %#-8x %#-8x %-4x %-6d %-6d %016x %016x %#-10x %#-18x %#-10x %#-18x %s"
              % ((i,) + r + (names.get(r[0], ""),)))
    tail = b[0x90 + cnt * 0x48:]
    if any(tail):
        print("bytes after the records are not zero")


if __name__ == "__main__":
    main()
