# libLaunchServicesSupport.dylib (macOS 26.7.2)

Apple's private `/usr/lib/libLaunchServicesSupport.dylib` (on disk in `/System/Cryptexes/OS/usr/lib/`, not in the
dyld shared cache), install name `/usr/lib/libLaunchServicesSupport.dylib`, compatibility and current version 1.0.0,
universal x86_64 + arm64e, 78 exports per architecture (the "160" seen earlier counted both slices plus header lines).
Our implementation: `github.com/pearOS-bsd/LaunchServices`, directory `libLaunchServicesSupport/`.

How this was found: the x86_64 slice was decompiled with Ghidra 12.1.4 headless (all functions, one pass) and
checked against `llvm-objdump` disassembly where the pseudocode was unclear (jump tables, register use, the
places marked "as Apple" below). Strings, CFStrings, the ObjC metadata (methods, type encodings, ivars,
properties) and the import table were read with `llvm-objdump --macho`. Nothing of Apple's is stored in the repos.

## Who uses it

Only two programs of 26.7.2 link it:
- **Dock**: `_LSForceQuitApplication`, `_kLSForceQuitApplicationPresentFirstForceQuitDialogKey`
- **loginwindow**: the same two plus `_LSRegisterAsQuitReallyHelperClient`

## Libraries it links (load commands, in order)

CoreServices, AppServerSupport (private), BackgroundTaskManagement (private), CoreAnalytics (private, no symbol used),
CoreGraphics, Foundation, libquit (**weak**), QuartzCore, Security, SkyLight (private), libobjc, libc++, libSystem,
CoreFoundation. Our build has the same list in the same order.

Imports that matter: LaunchServices SPI (`_LSASNCreateWithPid`, `_LSASNExtractHighAndLowParts`, `_LSASNGetTypeID`,
`_LSCopyApplicationInformation`, `_LSCopyApplicationInformationItem`, `_LSCopyMatchingApplications`,
`_LSIsApplicationRunning`, `_LSApplicationQuitting`, 15 `_kLSApplication*` / `_kLS*Key` keys), SkyLight
(`SLSGetUserAccessibilityReportForPid` and 13 `kSLSUserAccessibilityReport*` keys), CoreGraphics
(`CGGetActiveDisplayList`, `CGDisplayBounds`, `CGRegionIsRect`, `CGRegionGetBoundingBox`, `CGRectIntersection`),
QuartzCore (`CA_CGRectApplyTransform`, `-[NSValue CATransform3DValue]`), libquit (`LQReportHang`), BTM
(`BTMItemIdentifierForURLAndType`, `BTMManager`), AppServerSupport (`OSLaunchdJob`, `LASSProperties4RB`), libxpc
(`xpc_copy_entitlement_for_token`), libSystem (`os_state_add_handler`, `os_unfair_lock`, `proc_name`, `kill`,
`task_info`, `backtrace`), libc++ (`std::string`, `std::ostringstream`, `std::sort`).

## The exports

Legend: **faithful** = same logic as the decompiled code (checked on the Mac against Apple's, see Tests);
**faithful (bug kept)** = Apple's code has an odd corner and we do the same.

### Force quit (Dock, loginwindow)

`Boolean _LSForceQuitApplication(LSSessionID session, LSASNRef asn, CFDictionaryRef options, void (^completion)(BOOL ok, NSError *error))` — faithful. Always returns true.
- Logs `_LSForceQuitApplication(asn=%{public}@ options=%{public}@` (quitsupport, info; the options' description with newlines replaced by spaces).
- `completion == NULL || asn == NULL || session == 0`: completion (if any) gets `NO` + `NSOSStatusErrorDomain -50`, empty user info.
- Options (CFBoolean, compared with `CFEqual(value, kCFBooleanTrue)` when the key is present): `"remove"` (default true),
  `LSForceQuitApplicationDoNotInformLibQuitKey` (default **true**; true is what makes it call `LQReportHang` — the name is the
  opposite of what it does), `LSForceQuitApplicationSynchronousOperationKey` (default false),
  `LSForceQuitApplicationPresentFirstForceQuitDialogKey` (read, not used).
- Not synchronous: copies the options with the synchronous key set (`CFDictionaryCreateCopyWithItem`) and calls itself on
  `dispatch_get_global_queue(0,0)`; the completion is wrapped (log "Completed async _forceQuit, calling completion block with %{BOOL}d eror=%{public}@").
- Synchronous: pid = `_kLSPIDKey` (kCFNumberIntType), coalition = `_kLSApplicationCoalitionIDKey` (kCFNumberLongLongType), both through
  `_LSCopyApplicationInformationItem(-2, asn, key)`.
  1. pid != 0 and the libquit option: `LQReportHang(pid, forceQuitApplicationQ, block)` (no NULL check of the weak symbol), the block signals a semaphore.
  2. For each pid of `_kLSApplicationAllRelatedApplicationCoalitionPIDsArrayKey`: skip 0, the app's pid or an equal ASN, foreground apps, UI-element apps that are user visible (below); others get SIGTERM (`killPID(p, false)`), a failure adds the error and clears success.
  3. pid != 0: wait for the libquit semaphore (forever), make a `DISPATCH_SOURCE_TYPE_PROC` / `DISPATCH_PROC_EXIT` source on a queue `"procDeath"`, SIGTERM the app, wait 3 s for the exit, else SIGKILL; cancel the source; an error is added.
  4. `remove`: `_LSApplicationQuitting(-2, asn, 0x89)` (log on error with `GetMacOSStatusErrorString`).
  5. completion(`YES`, nil) or (`NO`, `NSOSStatusErrorDomain -600` with `NSMultipleUnderlyingErrorsKey` = the errors).
- `killPID(pid, hard)`: pid < 2 → OSStatus -50 `{pid}`; `kill(pid, hard ? 9 : 15)`; ESRCH counts as success; EPERM → POSIX 1, EINVAL → POSIX 22, else POSIX errno, user info `{pid: n}`.

`CFStringRef _kLSForceQuitApplicationDoNotInformLibQuitKey / PresentFirstForceQuitDialogKey / SynchronousOperationKey` (in `__DATA,__data`) — faithful: the strings `LSForceQuitApplicationDoNotInformLibQuitKey`, `LSForceQuitApplicationPresentFirstForceQuitDialogKey`, `LSForceQuitApplicationSynchronousOperationKey`.

`BOOL _LSRegisterAsQuitReallyHelperClient(NSDictionary *options, NSError **error)` — faithful.
- `DontTakeAction`, `DontSendAnalytics`: stored when `[options[key] isEqual:@YES]` (static flags, not read elsewhere in this image).
- `task_info(mach_task_self_, TASK_AUDIT_TOKEN)` (abort on failure); `xpc_copy_entitlement_for_token` must give non-NULL for
  `com.apple.private.xpc.launchd.job-manager` and `xpc_bool_true` for `com.apple.private.backgroundtaskmanagement.manage`,
  `com.apple.private.SkyLight.user-accessibility-report`, `com.apple.private.controlcenter.controlcentermodule`;
  else `NSOSStatusErrorDomain -54` with `NSDebugDescriptionErrorKey` = `Missing entitlement <name>`.
- Then once: `os_state_add_handler(global(0,0), …)` (title `QuitReallyTrackedApps`: `+[LSExitedApplication statusString]`) and `os_state_add_handler(global(-2,0), …)` (title `ExitedApps`: `appDictionary` of every application from `_LSCopyMatchingApplications` with the include-exited and exited-but-has-remaining keys), binary plist, `osd_type` 1, data at offset 200.
- If the first handle is non-zero: once `[[BTMManager shared] registerForceQuitHandler:[[BTMManagerSupport alloc] init]]`, returns YES. Failure path logs (error) `quitSupport: _LSRegisterAsQuitReallyHelperClient( %{public}@ ) failing with error %{public}@`.

`Boolean _LSApplicationHasAVisibleWindowOrContext(LSASNRef)` — faithful. NULL → false; else the static check:
SkyLight's accessibility report for the app's pid; a remote context whose shape box is ≥16×16 → true; the spaces of type < 6 and ≠ 3;
per window: level 25 with space IDs, rectangular shape ≥16×16 and not (ordered out with y ≥ 0) → true; else a window not ordered out,
level > −2147483623, alpha ≥ 0.5, on one of those spaces, whose screen-visible shape is ≥32×32, or whose shape moved by its
`CATransform3D` intersects a display (`CGGetActiveDisplayList` / `CGDisplayBounds`) by ≥32×32 → true.

`BOOL _LSSysdiagnoseStatus(NSDictionary *options, void (^reply)(NSDictionary *, NSError *))` — faithful (bug kept). With
`options[@"LSASN"]`: reply(appDictionary(asn), nil). Without: when `_LSCopyMatchingApplications` fails reply(nil, nil); otherwise it
builds the dictionary of all applications **and never calls reply** (Apple's code has no call there). Returns YES.
`appDictionary` keys: `name` (display name or `-`), `type` (`foreground` / `uielement` / `background`), `pid`, `uservisible`,
`visiblewindoworcontext`, `childApps`, `relatedApps`, `coalitionID`, `coalitionPIDs` (`{pid, name}` from `proc_name` for non-apps),
`relatedCoalitionIDs`, `relatedCoalitionPIDS`, `jobs` (`[OSLaunchdJob <path> : <label>]`).

### Classes

`LSExitedApplication : NSObject` — faithful (ivars `_asnRef` `{CFReleaser<const __LSASN *>="fItem"^{__LSASN}}` @8, `_info` @16; the
same 25 instance and 14 class methods with the same type encodings, the same 6 properties). The tracker of applications that
quit while helpers still run: a set under an `os_unfair_lock`, the serial queue `quitReallyScheduling`, `statusString`
(`LSExitedApplicationStatus  <date>` + ` - …`, ` -- childrenASNs=…`, ` -- coalitionID=%lld coalitionPIDs=…`, ` -- coalitionID=%lld jobs=…`),
`description` = `"%@ "%@"` (ASN, display name), `oneShotJobs` = launchd jobs of the coalition not allowed in the background,
`unloadLaunchdJobs` (`-[OSLaunchdJob remove:]`, an error other than 36 is logged and then traps, as Apple), `killSubordinateProcesses`
(`_LSForceQuitApplication(-2, asn, NULL, log block)`), `hasControlCenterItem` (always NO: the control-center check copies the bundle
id and answers false). Background-job policy (`launchJobIsAllowedInBackground`): `LASSProperties4RB hostPID > 1` allowed;
serviceType 1 (daemon) allowed when BTM knows the plist (`BTMItemIdentifierForURLAndType` 0x10, then 0x10010), 2 (agent) with 8 / 0x10008,
3/5/6 allowed, 4 only `com.apple.CoreSimulator.simdiskimaged`, `com.apple.Siri.agent`, `com.apple.install.osinstallersetupd`,
`com.apple.install.osisstashhelper`, `com.apple.sear.ac-sign.agent`, others allowed.

`BTMManagerSupport : NSObject <BTMForceQuitHandler>` — faithful. `-forceQuitAppURL:` (called by BTM when a login item is removed):
on queue `btmForceQuitQ`, every application whose bundle URL is the URL (same pointer, same `NSURLFileResourceIdentifierKey`,
or equal URL / path) is force quit with `_LSForceQuitApplication(-2, asn, NULL, …)`, waiting for each.

### Logs — faithful

`os_log_t _LS…Log(void)`, subsystem `com.apple.launchservices`, made once each: Default `default`, Analytics `analytics`,
AppCheckIn `appcheckin`, Extensions `extensions`, Front `front`, Install `appinstallation`, Progress `progress`,
Dissemination `dissemination`, Privacy `privacy`, DataSeparation `datasep`, DatabaseGet `db`, Open `open`,
QuitSupport `quitsupport`, Record `record`, Registration `registration`, TemplateApp `templateapp`, Binding `binding`,
AppProtection `appprotection`, CSUI `csui`, PluginFault `pluginfault`, Telemetry `telemetry`.
All log texts of the quit code are Apple's; on the Mac VM the unified-log lines of our build and Apple's are identical for the same calls.

### Version and string helpers — faithful

- `libLaunchServicesSupportVersionString` = `@(#)PROGRAM:libLaunchServicesSupport  PROJECT:LaunchServices-\n` (the project version is empty in the shipped binary); `libLaunchServicesSupportVersionNumber` = 0.0.
- `NSString *loggableURL(NSURL *)`: file URL → `fileSystemRepresentation`; else `"<scheme>:..."`.
- `NSString *backtraceString(void)`: `backtrace(…, 100)`, frames 1…n of `backtrace_symbols` with frame number, image and address cut off, joined by `" / "`; `copyBacktraceString` returns it +1.
- `NSString *processName(int)` (C++ name): `proc_name`, nil when it gives 0.

### C++ CoreFoundation helpers (Itanium names; return types are not in the names, they come from the code)

| function | notes |
|---|---|
| `std::string asString(const void *)` | debug text of a CF object: `[ NULL ] `, strings in quotes with `\n` → space (`?` if not UTF-8), `( a, b)`, `{ k=v, … }` (keys sorted when all are strings), `((…))` for sets, `$HEX` data, dates (`now-ish ` / `soon-ish ` / `N seconds from now, ` / `N seconds ago, ` + `YYYY/MM/DD HH:MM:SS` local), numbers (ints, `showpoint` floats, raw hex for other types), `true`/`false`, URLs (`base:`), `ERROR:domain #code userInfo`, `kCFNULL`, `ASN:0x<hi>-0x<lo>:` + `(pid=N)`, identities, certificates (`CERT:`), keys (`KEY:`), anything else through `CFCopyDescription` |
| `std::string asString(double, bool relative)` | faithful (bugs kept): absolute = GMT `YYYY/MM/DD HH:SS` (the minute is missing, seconds through a char); relative = first non-zero unit of the *Gregorian date of the interval* and the next one, month/day/hour/minute written as raw bytes |
| `std::string CFStringConvertToString(CFStringRef, CFStringEncoding)` | `CFStringGetCStringPtr` or `CFStringGetBytes` |
| `CFArrayApplyBlock` (2) | on a copy; typed form skips NULL / other types and returns true only if the block ran and never stopped |
| `CFArrayCreateByApplyingBlock` | block returns +1 objects, `bool *stop` |
| `CFArraySort` | sorted copy, comparator `cmp(a,b) <= 0` (as Apple); a type mismatch (type 0 matches nothing) gives an unsorted copy |
| `CFArrayCopyMergedArrays`, `CFArrayCreateWithItems` (10, NULLs dropped), `CFArrayCreateWithSet`, `CFArrayAppendArray`, `CFArrayRemoveValue` (all occurrences), `CFArrayRemoveValues` | faithful |
| `CFStringCreateByHexEncodingMemory/Data` | lowercase, ASCII |
| `CFDataCreateFromHexEncodedString` | odd length starting with `$` is read without it; NULL on a bad pair |
| `CFDictionaryApplyBlock` (2) | bug kept: the typed form runs the block only when `typeID == (CFGetTypeID(value) == typeID)` (so only for type 0 or 1) |
| `CFDictionaryCreateWithItems` (2,3,4,5,6 pairs), `CFDictionaryCreateCopyWithItem`, `CFDictionaryCopyWithItem`, `CFDictionaryCopyMerge`, `CFDictionaryCopyAllKeys/Values`, `CFDictionaryGetBooleanValue`, `…GetValueAsLong/Double/Int/UInt64` | faithful |
| `CFDictionaryCreateCopyWithItems` (5 pairs) | bug kept: the fifth pair is stored as key = v5, value = k5 |
| `CFSetApplyBlock` (2) | optional `qsort_b` with the sign of the comparator; true when every item was visited |
| `CFSetCreateWithArray`, `CFSetCreateMergedSet` | faithful |
| `CFSetAppendSet` | bug kept: reads the destination's own values and adds them back (the set does not change) |
| `CFStringLongestCommonPrefix` | compares the UTF-8 C string pointers (no fallback) |

## Tests (Mac VM, macOS 26.7.2, x86_64)

`LaunchServices/test/lsss_check.mm` loads Apple's dylib and ours (a copy with another install name) and compares 203 results:
the export sets (identical, 78), the 21 log objects, the version symbols and keys, `asString` on 35 kinds of objects and 18
intervals, all CF helpers on sample inputs (including the odd corners above), `loggableURL`, `processName`, `backtraceString`,
the ObjC metadata of both classes (methods + type encodings, ivars + offsets, properties + attributes, protocols, size),
`LSExitedApplication` behaviour, `_LSRegisterAsQuitReallyHelperClient` without entitlements (same -54 error),
`_LSApplicationHasAVisibleWindowOrContext` / `_LSSysdiagnoseStatus` for Finder, and `_LSForceQuitApplication` on a `/bin/sleep`
and on a Calculator the test starts itself (synchronous, libquit off): both quit it the same way, with the same log lines.
2026-11-27: 203 checks, 0 failures, for the Mac build and for the dylib built on FreeBSD (`build-bsd.sh`).

Not yet run on pearOS itself (needs the ISO stack with libquit, BTM, SkyLight's report and Dock/loginwindow).
