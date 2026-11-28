# cfprefsd probes (macOS test helpers, not part of the product)

What Apple's `cfprefsd` (macOS 26.7.2, CoreFoundation-5026.6.7.5) says to its clients, recorded on the Mac VM.  The protocol is written up in `research/docs/CFPREFSD-WIRE.md`; our daemon is `d/darwin/cfprefsd`.

| file | what |
|---|---|
| `xcap.c` | `DYLD_INSERT_LIBRARIES` interposer: every XPC connection, message, reply and incoming event (wrapped event handler) with its `xpc_copy_description` |
| `p1.c` | CFPreferences C API: read a missing domain, set, synchronize, key list, ByHost, a global key, delete |
| `p2.m` | NSUserDefaults suite: `watch` (KVO + NSUserDefaultsDidChangeNotification) and `write` in a second process (`run2.sh` runs both) |
| `p3.c`, `p4.c` | disk behaviour: when the plist file appears / is rewritten, mode, owner, inode |
| `p5.c` | the daemon side: `kCFPreferencesAnyUser` written by root and read / written by a user, root's own domain |
| `norm.py` | normalises a capture (addresses, test names, counter values, per-connection order) so that Apple's run and ours can be diffed |
| `setup-test.sh`, `cmp.sh` | Mac VM: build `d/darwin/cfprefsd`, run it as the test services (`com.apple.cfprefsd.{agent,daemon}.test`, jobs `com.pearos.t.cfpagent` / `com.pearos.t.cfpdaemon`), run a probe against Apple's daemon and against ours (`__CFPreferencesTestDaemon=1`) from the same files: `/tmp/cmp-apple.txt`, `/tmp/cmp-ours.txt` |
| `swap.sh` | Mac VM: put our agent in place of Apple's for the session (`ours`) and back (`apple`); needs SIP off (launchd refuses to boot out a system job otherwise) |
| `captures/` | the recorded output of the probes (text) |

Build and run on the Mac: `clang -dynamiclib xcap.c -o xcap.dylib; clang p1.c -framework CoreFoundation -o p1; DYLD_INSERT_LIBRARIES=./xcap.dylib ./p1`.  For a system tool, copy it and sign the copy ad hoc first (`codesign -s - defaults-copy`).

Findings so far (details and evidence in the wire document):
- Two services: `com.apple.cfprefsd.daemon` (root, system domains: `/Library/Preferences`, managed) and `com.apple.cfprefsd.agent` (per user).  A client talks to both: the first read is one `CFPreferencesOperation` 5 (multi-message) to each, an array with one slot per source of the search list (nulls for the slots that service does not own); the reply array has the same positions.
- Op 1 without `Key` reads a source (reply: `CFPreferencesPropertyList` binary plist, absent when the domain is empty, plus `CFPreferencesShmemName` / `Index` / `State`); op 1 with `Key` and `Value` writes (Value: XPC string, binary plist data for numbers, null to remove).  Op 7 registers an observer, op 4 removes a whole domain (`defaults delete DOMAIN`).
- A change is pushed to an observing client as a message `{CFPreferencesDomain, CFPreferencesUser (the user name), CFPreferencesIsByHost, CFPreferencesPID (the writer)}`; the client answers with an empty message and re-reads; that reply carries `PlistDiff` (the changed keys).
- Shared memory `apple.cfprefs.<uid>v1` (agent) and `apple.cfprefs.daemonv1` (daemon): one counter per source (`ShmemIndex`), bumped at every change (`ShmemState`); the client compares it before using its cache.
- Files: binary plist, mode 0600, owner the user, xattr `com.apple.quarantine` `0086;<hex time>;com.apple.cfprefsd;`; the first write creates the file at once, later ones are written a little later through a new file (new inode); a domain whose last key is removed stays as an empty dictionary file.  ByHost files use the IOPlatformUUID: `ByHost/<domain>.<UUID>.plist`.
