# dock-services: probes for com.apple.wallpaper and com.apple.windowmanager.external

Evidence and results: `../../docs/DOCK-WINDOWMANAGER-WALLPAPER.md`.  Test code only (our own, BSD-2-Clause), run on the Mac VM (macOS 26.7.2).

| file | what |
|---|---|
| `wptest.swift` + `mods/` | a client that makes the Dock's start-up calls through Apple's Wallpaper.framework and WindowManager.framework. `mods/` holds OUR declarations of the few entry points (names from the Dock's imports), not Apple's interfaces. Build: `sh mk-tbd.sh <extracted> fw && swiftc -O -I mods -F fw -framework Wallpaper -framework WindowManager wptest.swift -o wptest` (`NO_WP=1` / `NO_WM=1` skip one part) |
| `xcap.c` | DYLD_INSERT_LIBRARIES interposer: every XPC send / reply / incoming message, JSON data values printed, NSXPC `root` blobs saved to `$XCAP_DIR` (decode with `../iconservices/bp17.py`) |
| `wpprobe.c` | raw `AgentXPCMessage` JSON to `com.apple.wallpaper` (or `$WP_SERVICE`), prints the replies |
| `keyprobe.m` | the coder key of every `WindowManagerXPC*` class (a recording NSCoder given to `initWithCoder:`) |
| `protoprobe.m` | selectors + extended type encodings of a protocol (`./protoprobe <image> <protocol>...`); output for WindowManager in `wm-protocols.txt` |
| `labtest.sh` | FreeBSD lab VM: d's launchd with the two jobs of `d/darwin/{windowmanager,wallpaperagent}`, then `wpprobe` and `wptest` |

Apple's client against our servers on the Mac: jobs `com.pearos.t.wallpaper` / `com.pearos.t.windowmanager` and
`IS_REDIRECT=com.apple.wallpaper=com.pearos.t.wallpaper,com.apple.windowmanager.external=com.pearos.t.windowmanager DYLD_INSERT_LIBRARIES=redirect.dylib:xcap.dylib ./wptest`
(`IconServices/test/redirect.c`).
