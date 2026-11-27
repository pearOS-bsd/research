# The Dock, com.apple.windowmanager.external and com.apple.wallpaper (macOS 26.7.2)

What the real Dock asks of WindowManager.app and WallpaperAgent.app when it starts, the wire of both services, and what the
replacements in `d` (`darwin/windowmanager`, `darwin/wallpaperagent`) answer.  Tags: **[captured]** seen on the Mac VM (log, a test client,
an XPC interposer), **[decompiled]** read from the binaries (strings, class dump, Ghidra through rea), **[inferred]** our reading or our choice.

Tools and probes: `research/tools/dock-services/` (the test client `wptest.swift` with its own declarations of the framework entry points,
`xcap.c` interposer, `wpprobe.c`, `keyprobe.m`, `protoprobe.m`, `labtest.sh`).

## 1. Who serves the names [captured]

| name | launchd job (`/System/Library/LaunchAgents`) | program |
|---|---|---|
| `com.apple.windowmanager.external` (+ `.server`, `.dragserver`) | `com.apple.WindowManager.plist`, label `com.apple.WindowManager.agent`, Aqua, RunAtLoad false, KeepAlive AfterInitialDemand | `/System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager` |
| `com.apple.wallpaper` (+ `.CacheDelete`, `.debug.service`, a usernotifications delegate name) | `com.apple.wallpaper.plist`, label `com.apple.wallpaper.agent`, Aqua, RunAtLoad false | `/System/Library/CoreServices/WallpaperAgent.app/Contents/MacOS/WallpaperAgent` |

The Dock links `Wallpaper.framework`, `WindowManager.framework` and `WindowManagement.framework` (otool -L).  Its entitlements include
`com.apple.private.wallpaper` and `com.apple.private.windowmanager`.

## 2. The Dock at start (log of a `killall Dock`, `log show --info --debug`, processes Dock / WallpaperAgent / WindowManager) [captured]

Order (times of one run, ms after the Dock's first log line):

1. +75 `com.apple.wallpaper` connection; `BEGIN: Wallpaper initialization`; agent logs `XPC Message Received: setDisplaySpacesInfo` (twice);
   Dock `Created desktop wallpaper window: <118: ... size 1280x800 ... needsBackdrop: false>`; `Beginning initial task`; `END: Wallpaper initialization`;
   `Posting com.apple.desktop.ready`; `Take Assertion 1: display: D19AD5BA-..., space: , contentType: desktop`; agent `takeAssertion`;
   Dock `Reply(id: 1, contextID: 3116590373)`.  All of it in ~8 ms, BEFORE the bar.
2. +370 ... +410: the bar is built (`DockBar activate`, `_addFavoriteApps()` tiles, trash, running processes).  The wallpaper reply is not waited for by the bar.
3. +430 `com.apple.windowmanager:xpc Asynchronously beginning desktop peek monitor`, connection to `com.apple.windowmanager.external`;
   WindowManager logs `AdminXPCConnection xpcBeginDesktopPeekMonitor`, `adminXPCConnectionDidBeginDesktopPeekMonitor`,
   `desktopPeekMonitorStateDidChange` (sent to the client).  AFTER the bar.
4. +505 `Completed initial task, and populating layer contents` (wallpaper), another `setDisplaySpacesInfo`.
Nothing else goes to either service in the first 10 s.

So on the Mac neither service is on the path of the bar: the wallpaper initialization is synchronous only as far as the sends go (the
assertion reply arrives asynchronously), and the peek monitor begins after the bar.  [inferred] On pearOS they are still worth serving: without the assertion's context the desktop window has no content, and a
missing name gives the frameworks an error path the Mac never takes.

The Dock's calls into the frameworks (imports of `Dock`, chained fixups) [decompiled]:
- Wallpaper: `WallpaperManager.init()` (subclassed: `cfc`), `makeMainDisplay(_:)`, `makeFirstSpace(space:display:) throws`,
  `WallpaperDisplayAssertion.init(display:spaceName:) async throws` and `.layer`, `WallpaperPresentationModeAssertion.takeIdle()`,
  `getLegacyDesktopPicture(space:display:)`, `setLegacyDesktopPicture(_:space:display:onBehalfOfProcess:)`.
- WindowManager: `WindowManager.shared`, `createDesktopPeekMonitor()`, `WindowManagerDesktopPeekMonitor.begin()` + delegate,
  `createExposeCoordinator()`, `synchronouslyRequestLayoutState/LayoutControl/RemoteTransitionCoordinator`, `assignWindows(...)`,
  `provideVisibilityHintForSpace`, `synchronouslyCommitPendingUpdates` (Mission Control, App Exposé, Show Desktop: not at start).

## 3. com.apple.wallpaper

### 3.1 Wire [captured: `wptest` (same framework calls as the Dock) + `xcap.dylib`]
Plain XPC.  A request is a dictionary with ONE key `AgentXPCMessage` whose value is DATA holding JSON (Swift `JSONEncoder`; key order varies
between runs) `{"<case>":{<arguments>}}`:

```
send (no reply)  {"setDisplaySpacesInfo":{"info":{"firstSpaces":[],"mainDisplay":"D19AD5BA-D2A3-3EBB-0024-A4187A84FFFE"}}}     makeMainDisplay
send (no reply)  {"setDisplaySpacesInfo":{"info":{"firstSpaces":["D19AD5BA-...",""],"mainDisplay":"D19AD5BA-..."}}}          makeFirstSpace (pairs display, space)
with reply       {"takeAssertion":{"value":{"display":{"display":"D19AD5BA-...","spaceName":"","contentType":{"desktop":{}},"isPreview":false}},"id":1}}
   reply         {"AssertionReply": DATA {"id":1,"contextID":883870413}}       -> WallpaperDisplayAssertion.layer is a CALayerHost with that contextId
with reply       {"releaseAssertion":{"id":1}}                                 (when the assertion object goes away)
   reply         {} (empty dictionary)
```
The message cases (strings of Wallpaper.framework, `AgentXPCMessage` coding keys) [decompiled]: takeAssertion, releaseAssertion, setAssertions,
setLegacyDesktopPictureConfiguration, getLegacyDesktopPictureConfiguration, setDisplaySpacesInfo, setOverride, getOverride,
updateDesktopWallpaperUserSettings, updateScreenSaverWallpaperUserSettings, purgeChoice, downloadChoice, cancelDownload, pauseDownload,
resumeDownload, addChoiceRequest, removeChoiceRequest, invokeContextMenuAction, ensureViewModelIsUpToDate, skipShuffledContent,
canSkipShuffledContent, diagnosticState, snapshotAllSpaces, getCaches, registerSettingsObserver.  Server-to-client `ClientXPCMessage`:
userSettingsDidChange, settingsViewModelDidChange, downloadDidUpdate.

### 3.2 Apple's agent with odd input [captured: `wpprobe`]
An unknown case (`{"bogus":{}}`), text that is not JSON, a dictionary without `AgentXPCMessage`, a `releaseAssertion` of an unknown id, a
`getLegacyDesktopPictureConfiguration` with keys it did not like: all get an EMPTY dictionary as the reply.  A second `takeAssertion` from the
same connection gets a new context id.  An unsigned client without `com.apple.private.wallpaper` is accepted for these messages.

### 3.3 What `d/darwin/wallpaperagent` does
Same name, same wire: `setDisplaySpacesInfo` kept; `takeAssertion` -> a CoreAnimation remote context (`+[CAContext remoteContextWithOptions:]`)
whose root layer has the display's size and the picture, reply `{"id":N,"contextID":C}`; `releaseAssertion` invalidates it, reply `{}`; every
other message -> `{}` when a reply is asked for.  The client's assertions are released when its connection goes.
[inferred/ours] the picture: `WP_IMAGE` or a plain colour; the Mac's wallpaper store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`,
the NeptuneOne extension providers) is not read.  Other names of the job (CacheDelete, debug.service) are not served.

## 4. com.apple.windowmanager.external

### 4.1 Interface [decompiled + captured]
NSXPC.  The framework's `AgentXPCProxy` (client) connects to the Mach service; the exported (server) protocol is the Swift protocol
`_TtP13WindowManager28AgentXPCProxyServerInterface_` (46 methods), the client exports `_TtP13WindowManager28AgentXPCProxyClientInterface_`
(8 callbacks).  Selectors and extended type encodings (read with `protoprobe`, `_protocol_getMethodTypeEncoding`): `research/tools/dock-services/wm-protocols.txt`.
Arguments are `NSSecureCoding` boxes, each with ONE `NSData` under one key: the JSON of a Swift Codable value.  Keys (read with `keyprobe`, a
recording NSCoder given to each class's `initWithCoder:`) [captured]:

| class | key | | class | key |
|---|---|---|---|---|
| WindowManagerXPCLayoutState | WMXPCLS | | WindowManagerXPCModalRevealAssertionID | WMXPCRAID |
| WindowManagerXPCTransitionAnimations | WMXPCTA | | WindowManagerXPCHideWindowsInclusion | WMXPCHWI |
| WindowManagerXPCDisplayAnimations | WMXPCDA | | WindowManagerXPCWindowPickingSessionExclusionList | WMXPCWPSEL |
| WindowManagerXPCDraggableOverlayTarget | WMXPCDOT | | WindowManagerXPCWindowPickingSessionConfiguration | WMXPCWPSC |
| WindowManagerXPCDraggableOverlaySessionID | WMXPCDOSID | | WindowManagerXPCExposeCoordinatorID | WMXPCWVID |
| WindowManagerXPCRemoteTransitionType | WMXPCRTT | | WindowManagerXPCExposeMode | WMXPCWVWM |
| WindowManagerXPCWindowPickingSessionWindow | WMXPCWPSW | | WindowManagerXPCExposeToggleTransition | WMXPCETT |
| WindowManagerXPCWindowPickingSessionClientInfo | WMXPCWPOVCI | | WindowManagerXPCExposeGestureAssertionID | WMXPCEGAID |
| WindowManagerXPCDesktopPeekMonitorID | WMXPCDPMID | | WindowManagerXPCExposeGestureAssertionDirection | WMXPCEGAD |
| WindowManagerXPCDesktopState | WMXPCDS | | WindowManager.WindowManagerXPCTilingPositionRequest (`_TtC13...37WindowManagerXPCTilingPositionRequest`) | WMXPCTILPOS |

### 4.2 The Dock's start-up call [captured: `wptest` + `xcap.dylib`, the NSXPC `root` decoded with `research/tools/iconservices/bp17.py`]
```
xpcBeginDesktopPeekMonitor:completion:   signature v32@0:8@16@?24, replysig v16@?0@"NSError"8
  arg 0: WindowManagerXPCDesktopPeekMonitorID { WMXPCDPMID = DATA {"id":"302FFE35-4215-4F53-937C-A25D47425CB9"} }   (a new UUID per monitor)
```
Apple's server then calls `desktopPeekMonitorStateDidChange:` (`v24@0:8@"NSDictionary"16`) on the client [captured: WindowManager's log].  The
dictionary is space ID (UInt64) -> `WindowManagerXPCDesktopState` (WindowManager.app maps its `[UInt64: DesktopPeekMonitor.DesktopState]`, its
`lastSentSpaceIDToDesktopState`, through `XPCDesktopState(rawValue:)` and `AdminXPCListener.desktopPeekMonitorStateDidChange(_:)`) [decompiled: WindowManager.app
FUN_1000088f5].  `DesktopState` = { peekState (enter / entering / exit / exiting / widgetRevealAssertionHeld, with SpringParameters dampingRatio,
response), desktopIconsHidden, widgetsHidden } [decompiled: exports].  The values Apple sends at start were NOT captured (see 4.3).

### 4.3 Entitlement [decompiled + captured]
`AdminXPCListener.listener(_:shouldAcceptNewConnection:)` asks the connection for a 31-character entitlement: `com.apple.private.windowmanager`.
A client without it is refused: an unsigned test client sees `Connection interrupted` on each of its three connection attempts, with Apple's
server and with ours.  This is why Apple's replies could not be captured from our client (an ad-hoc signature with that entitlement is killed by
AMFI on the Mac with SIP on).

### 4.4 What `d/darwin/windowmanager` does
Same name, same protocol (all 46 selectors with Apple's type encodings, the 20 box classes with Apple's names and keys), same entitlement check
(`valueForEntitlement:`, and on pearOS, where csops reports no entitlements, the code signature of the peer's executable: `common/csent.c`).
- `xpcBeginDesktopPeekMonitor:completion:` -> completion(nil), then `desktopPeekMonitorStateDidChange:` with an EMPTY dictionary [inferred: nothing
  is peeked on pearOS; Apple's start values unknown].  `xpcEndDesktopPeekMonitor:` -> completion(nil).
- `xpcBeginExposeCoordinator:`, `xpcEndExposeCoordinator:`, `xpcProvideVisibilityHintForSpace:` -> completion(nil); `xpcCommitPendingUpdatesWithCompletion:` -> YES [inferred].
- Every other method answers its reply at once: an NSError `NSCocoaErrorDomain` 3328 (NSFeatureUnsupportedError), NO, or 0 + error [ours: Apple
  implements them; its errors for a refused request were not observed].  A selector outside the protocol is dropped by NSXPC itself, as on the Mac.
- `com.apple.windowmanager.server` stays with `darwin/wm-stub`; `.dragserver` is not served.

## 5. Tests

### 5.1 Mac VM, Apple's client against ours [captured]
Jobs `com.pearos.t.wallpaper` / `com.pearos.t.windowmanager` (our binaries, built on Linux and on FreeBSD), the names redirected in the client with
`IconServices/test/redirect.c`.  `wptest` (Apple's Wallpaper.framework and WindowManager.framework) gets: the same three wallpaper messages, the
reply `{"id":1,"contextID":4240797380}` and a `CALayerHost` with that context id, `{}` for releaseAssertion; for WindowManager (entitlement check off
with `WM_NO_ENTITLEMENT_CHECK=1`, the client is unsigned) `peek monitor begun`, the completion (bplist17 `[nil, "v@?@", [nil]]`) and the callback
`desktopPeekMonitorStateDidChange:` with an empty NSDictionary.  With the check on, the client gets `Connection interrupted` three times, as with Apple's.

### 5.2 FreeBSD lab VM (darwinator, d's launchd, our jobs) [captured: `labtest.sh`]
Our launchd starts both jobs at the first look-up.  `wpprobe`: `{}` for an unknown case and for releaseAssertion, `AssertionReply {"id":3,"contextID":0}`
(no CARenderServer on the lab VM: `remoteContextWithOptions:` gives nil).  `wptest` unsigned: WindowManager refuses (`no com.apple.private.windowmanager`);
`wptest` ad-hoc signed with `com.apple.private.windowmanager` (darwinator has no AMFI): accepted, `xpcBeginDesktopPeekMonitor` served.

### 5.3 Open
- On the lab VM `wptest`'s `WallpaperDisplayAssertion(display:spaceName:)` (a Swift `async` init) did not send `takeAssertion` within 3 s (the
  two synchronous sends went): Swift concurrency on darwinator, to look at.
- The real Dock against our two servers on pearOS (the ISO VM) is not done yet; the picture of the Mac's wallpaper store; Apple's initial desktop states.
