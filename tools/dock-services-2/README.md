# dock-services-2: probes for the Dock's start-up services, part 2

Evidence and results: `../../docs/DOCK-SERVICES-2.md`.  Test code only (our own, BSD-2-Clause), built and run on the Mac VM (macOS 26.7.2); the Mac-built binaries also run on the FreeBSD lab VM through darwinator and the Mac's dyld cache.

| file | what |
|---|---|
| `dsprobe.m` | the Dock's start-up calls through Apple's frameworks, one word per service: `uninstall dmd dmd2 ua progress subscribe publish analytics ae named namedx usernoted` (`PROBE_UN`, `PROBE_ND`, `PROBE_EVENT`, `PROBE_WAIT`, `PROBE_UNINSTALL_ABORT`, `PROBE_UNINSTALL_QUEUE` only with `IS_REDIRECT`).  Build: `clang -fobjc-arc -framework Foundation -o dsprobe dsprobe.m` |
| `dcap.c` | DYLD_INSERT_LIBRARIES interposer: every XPC connection (`xpc_connection_create_mach_service` and `xpc_connection_create`), message, reply and incoming message; NSXPC `root` blobs to `$DCAP_DIR` (default /tmp/dcap); `IS_REDIRECT=from=to` renames services (an XPC service becomes a Mach service of a test job).  Build: `clang -dynamiclib dcap.c -o dcap.dylib` |
| `xraw.c` | `./xraw [-p] SERVICE key=i:N key=u:N key=s:STR key=b:1`: one raw XPC request, the reply and the next 2 s of messages |
| `protos.m` | `./protos IMAGE[,IMAGE] PATTERN...`: selectors + extended type encodings of matching protocols; output in `protocols.txt` |
| `bp17x.py` | bplist17 (NSXPC `root`) decoder: `../iconservices/bp17.py` plus the one-byte `0xbN` objects of proxy records |
| `labtest.sh` | FreeBSD lab VM: d's launchd with the jobs of the eight daemons (+ distnoted, launchservicesd), then the Mac-built probes |

`undock` (usernoted.dock probe) is the `usernoted` word of `dsprobe` as a small C program; to be served by usernoted (Apple's or ours) a probe must be signed with the Dock's identifier: `codesign -f -s - -i com.apple.dock undock2`.
Test jobs on the Mac: `com.pearos.t.un` (gui), `com.pearos.t.nd`, `com.pearos.t.dmd`, `com.pearos.t.ua` (gui), `com.pearos.t.fcd`, `com.pearos.t.aed`, `com.pearos.t.and`, `com.pearos.t.und` (LaunchDaemons: Foundation, AE, CoreAnalytics and Uninstall look those services up in the system domain).
