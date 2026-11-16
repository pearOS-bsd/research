# What the Mac has, what we provide, which repositories are still missing (2026-11-16)

Source: the map of the dyld shared cache of macOS 26.7.2 (x86_64h) on the test VM (`dyld_shared_cache_x86_64h.map`: 3625 images) and the repositories as they are now.
The disk side of the Mac (LaunchDaemons, /usr/libexec, CoreServices daemons) was not reachable when this was written (ssh to the Mac VM timed out): the list of daemons is taken from what the real Dock and Finder ask for on the pearOS stack (`d/session`, DOCK-SERVICES.md).

## 1. The dyld cache: what is in it
| part | images | who provides it for us |
|---|---|---|
| `/System/Library/Frameworks` | 387 images (293 frameworks: AppKit, Foundation, CoreFoundation, CoreGraphics, CoreText, ImageIO, CoreServices, Security, IOKit, SystemConfiguration, QuartzCore, Metal, WebKit, SwiftUI ...) | the cache itself: unmodified Mac code runs on darwinator (kernel module) + the real dyld; **AppKit is replaced by ours** (`AppKit` repo, `/open/AppKit`) |
| `/System/Library/PrivateFrameworks` | 2251 images (SkyLight, UIFoundation, CoreUI, IconServices, LaunchServices pieces, HIServices ...) | the cache; **SkyLight** talks to our server (`SkyLight` repo + `WindowServer`) through `wsbridge` (`d/darwin`) |
| `/usr/lib` (269), `/usr/lib/system` (44), `/usr/lib/swift` (82) | libSystem, libobjc, libdispatch, libxpc, libc++, the Swift runtime ... | the cache; the **kernel side** of libSystem (syscalls, Mach IPC, workqueues, kqueue) is `darwinator` |
| `/System/iOSSupport` | 493 (Catalyst) | the cache, not used |
Not available from the cache and replaced by stubs (`open/gen-stubs.py`): libswiftCoreImage, libswiftMetal, libswiftQuartzCore, libswiftSpatial, RecapPerformanceTesting (they pull the real AppKit in).

## 2. What runs from disk and not from the cache (daemons, apps, bundles): our side is `d` and `apps`
Real binaries copied from the user's own Mac at build time: cfprefsd, coreservicesd, iconservicesd/agent, sharedfilelistd, Dock, Finder, ControlCenter.  Ours: launchd, notifyd, lsd-objc (LaunchServices), wsbridge, carender-stub (CARenderServer), hid-stub, wm-stub, svc-stub/xpc-stub (about 30 service names answered with the minimum), usernoted, airportd, the Open and Save Panel Service, wsd.

## 3. Repositories that are still missing (proposal)
| repository | what it would hold | why / evidence |
|---|---|---|
| `dyld` (or `loader`) | the user-space loader pieces: `darwinator/dyld` (machrun, libmachcompat, libexctrace: the old GNUstep-era path), the cache tools (`macdeps.sh`, `fwskel.py` symlink skeleton, framework-paths, symbolization) | today they are mixed in `darwinator/tools` and `darwinator/dyld`; the kernel module repository should stay only the module |
| `macdeps` (or `sysroot`) | **only scripts and lists, no Apple files**: how to build the sysroot from the user's own Mac / installer (`macdeps.list`, copy of the cache, ICU data, fonts, the bundles the Dock/Finder need, check sums) | everything the stack needs from Apple is copied by hand today; one reproducible recipe is missing |
| `IOKit` | the IOKit side in user space: the registry data (`io_nodes`: IOSurfaceRoot, IONameMatch ...), HID (`hid-stub`), power/backlight stubs | grew inside `darwinator` (`mach_ipc.c`) and `d`; Dock/IconServices needed IOSurfaceRoot, CGDisplay, HID |
| `HIToolbox` / `ViewBridge` (only if needed) | the pieces of the Mac UI stack that sit between AppKit and SkyLight and that we cannot take from the cache once AppKit is ours | decide from the gap list of the `open` layer (OpenGaps) |
| `Frameworks-decompiled` | `SDK/foundation` (decompiled Foundation, tests) apart from the compat SDK | `SDK` mixes two things: the GNUstep-era compat layer (`src/`: about 100 framework shims for the old path) and the decompiled Foundation |
| `Tests` (or in each repo) | cross-repository tests: run the real Mac apps (TextEdit, Stickies, Calculator ...) on `open` and compare screenshots with the Mac | today ad hoc in my scripts |
| `docs` / `wiki` | the user documentation (what pearOS is, how to install, how to run a Mac app) | the profile README is the homepage; the rest is in `research` |

## 4. Candidates to retire (the old path)
GNUstep-era code that `open` + darwinator make unnecessary: `AppKit/back-wsd`, most of `SDK/src` (the shims of 100 frameworks), `iso/ci/gnustep-*.sh`, `ports/`.  They can move to `research` (legacy) once the ISO build no longer needs them.
