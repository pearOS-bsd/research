#!/usr/bin/env python3
"""Normalises an xcap capture so that a run against Apple's cfprefsd and one against ours (test mode) can be diffed:
drops object addresses, the test suffixes of the service and shared memory names, the counter values (ShmemState) and the
pid of the writer; keeps operations, keys, value types, lengths and the order of the messages.
Use: norm.py capture.txt > normalised.txt"""
import re, sys
out = []
for line in open(sys.argv[1], errors='replace'):
    line = line.rstrip('\n')
    if 'null-object' in line or line.startswith('xcap loaded'):
        continue
    line = re.sub(r'0x[0-9a-f]+', '0x', line)
    line = line.replace('com.apple.cfprefsd.agent.test', 'com.apple.cfprefsd.agent').replace('com.apple.cfprefsd.daemon.test', 'com.apple.cfprefsd.daemon')
    line = line.replace('"test.cfprefs.', '"apple.cfprefs.')
    line = re.sub(r'length = \d+, (contents = "apple\.cfprefs)', r'length = L, \1', line)
    line = re.sub(r'(CFPreferencesShmemState" => <uint64: 0x>: )\d+', r'\1N', line)
    line = re.sub(r'(CFPreferencesPID" => <int64: 0x>: )\d+', r'\1N', line)
    line = re.sub(r'(length = \d+ bytes, contents = )0x\.\.\.|contents = 0x[0-9a-f.]*', 'contents = ...', line)
    line = re.sub(r'(string cache = 0x), length', r'\1, length', line)
    line = re.sub(r'(transaction: )\d', r'\1T', line)
    line = re.sub(r'(capacity = )\d+', r'\1C', line)
    line = re.sub(r'CAP#\d+', 'CAP', line)
    line = re.sub(r'(conn=com.apple.cfprefsd.\w+) flags=\d', r'\1', line)
    out.append(line)
# group the messages by connection (the order between the agent and the daemon depends on timing; the order on each
# connection does not); STEP lines of the probe go to every stream
streams, cur = {}, None
for line in out:
    if line.startswith('=== STEP'):
        for k in ('agent', 'daemon', 'other'): streams.setdefault(k, []).append(line)
        cur = None
        continue
    m = re.match(r'(CAP \w+|CONNECT) conn=com\.apple\.cfprefsd\.(agent|daemon)|CONNECT com\.apple\.cfprefsd\.(agent|daemon)', line)
    if m:
        cur = m.group(2) or m.group(3)
    streams.setdefault(cur or 'other', []).append(line)
for k in ('agent', 'daemon', 'other'):
    print('##### ' + k)
    print('\n'.join(streams.get(k, [])))
