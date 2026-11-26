#!/usr/bin/env python3
"""Pull the named ObjC struct encodings (e.g. LSBundleData with its field names) out of a LaunchServices binary taken from the user's Mac.
usage: extract_enc.py LaunchServices-binary NAME > NAME.enc      (the encoding is metadata of the binary; it is not stored in this repository)"""
import re, subprocess, sys
txt = subprocess.run(['strings', '-a', sys.argv[1]], capture_output=True, text=True, errors='replace').stdout
best = ''
for m in re.finditer(r'\{' + re.escape(sys.argv[2]) + '="', txt):
    i = m.start(); d = 0; j = i
    while j < len(txt):
        c = txt[j]
        if c == '{': d += 1
        elif c == '}':
            d -= 1
            if d == 0: break
        j += 1
    if j - i > len(best): best = txt[i:j+1]
print(best)
