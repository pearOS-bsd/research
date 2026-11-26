# Launch Services daemons: wire protocols and the CSStore database (macOS 26.7.2, build xnu-12377.161.15.701.48, x86_64)

Goal: enough to write wire-compatible replacements for the Launch Services daemons (`lsd`, `launchservicesd`) and a writer for the database file they hand to every client, prioritised by what blocks the pearOS Dock. Same method and evidence tags as `ICONSERVICES-WIRE.md`: **[captured]** (seen on the wire / on disk on the Mac VM), **[runtime]** (read from the live ObjC runtime), **[decompiled]** (REA/Ghidra, function named), **[header]** (class dump / type strings of the binary), **[inferred]**. No Apple code or binary is in this repository; tools are in `tools/launchservices/`, decoded captures in `tools/launchservices/captures/`.

Evidence sources
- `LaunchServices.framework`, `CoreServicesStore.framework`, `lsd` from the dyld shared cache of the Mac (`ipsw class-dump`, `ipsw dyld extract`, REA/Ghidra on CoreServicesStore). The server classes (`_LSDReadService`, `_LSDModifyService`, ...) live in LaunchServices.framework itself; `/usr/libexec/lsd` (105 KB) is only a `main` that starts them **[header]**.
- Mac VM probes (all in `tools/launchservices/probes/`): `p.m` (protocols + allowed classes from the live runtime), `xcap.c` (interposer: every XPC connect/send/reply, saves `root`/`ool`/shared memory), `c.m`, `a.m`, `rd.m` (clients), `v.m`, `u.m` (open a csstore with Apple's reader, read units), `fcap.c`. Decoders: `tools/iconservices/bp17.py` (NSXPC root), `tools/launchservices/csstore.py`, `lsrecord.py`.
- SIP is ON on the Mac VM; nothing here needed it off (see question Q1 in section 9).

## 1. Mach services

launchd jobs **[captured: plists + `launchctl print`]**:

| job label | domain | program | MachServices | notes |
|---|---|---|---|---|
| `com.apple.lsd` | system LaunchDaemon (`/System/Library/LaunchDaemons/com.apple.lsd.plist`) | `/usr/libexec/lsd runAsRoot` (pid 215 on the VM, root) | `com.apple.lsd.advertisingidentifiers`, `.diagnostics`, `.dissemination`, `.encryption`, `.extensions`, `.mapdb`, `.modifydb`, `.open`, `.openurl`, `.personaobserver`, `.plugin`, `.trustedsignatures`, `com.apple.security.translocation` | `EnableTransactions`, `EnablePressuredExit=false`, `ThrottleInterval 1`, `PublishesEvents com.apple.launchservices.LSObserver`, `POSIXSpawnType Adaptive` |
| `com.apple.lsd` | per-user LaunchAgent (`/System/Library/LaunchAgents/com.apple.lsd.plist`, `LimitLoadToSessionType Background`) | `/usr/libexec/lsd` (pid 399, the user) | same list without `dissemination` and `encryption` | same keys. A client of the user session finds the gui-domain instance first; the system instance serves root/system clients and is the one that sees `com.apple.lsd.system.*` names |
| `com.apple.coreservices.launchservicesd` | system LaunchDaemon | `/System/Library/CoreServices/launchservicesd` (pid 141, root) | `com.apple.coreservices.launchservicesd` | `RunAtLoad`, no NSXPC: plain XPC dictionaries, section 6. Links RunningBoard(+Services), AppServerSupport, Security |
| `com.apple.CoreServices.coreservicesd` | system LaunchDaemon | `/System/Library/CoreServices/coreservicesd` | `com.apple.CoreServices.coreservicesd` (`ResetAtClose`) | CarbonCore, not Launch Services |

The framework also knows the names `com.apple.lsd.xpc`, `.icons`, `.installation`, `.rebuild`, `.appprotection`, `.firstboot`, `com.apple.lsd.system.<name>` for every service, `com.apple.coreservices.code-evaluation`, `.quarantine-resolver`, `.uiagent` **[header: strings]**; the plists above do not publish them (internal or used for other roles).

Service classes (`+[_LSDService subclasses]`, `+connectionType`, `+XPCConnectionIsAlwaysPrivileged`) **[runtime: p.m]**:

| Mach service | class | connectionType | protocol | always privileged |
|---|---|---|---|---|
| `com.apple.lsd.mapdb` | `_LSDReadService` | 0 | `_LSDReadProtocol` | no |
| `com.apple.lsd.modifydb` | `_LSDModifyService` | 1 | `_LSDModifyProtocol` | no |
| `com.apple.lsd.open` | `_LSDOpenService` | 3 | `_LSDOpenProtocol` | no |
| `com.apple.lsd.advertisingidentifiers` | `_LSDDeviceIdentifierService` | 7 | `_LSDDeviceIdentifierProtocol` | no |
| `com.apple.lsd.trustedsignatures` | `_LSDTrustedSignatureService` | 8 | `_LSDTrustedSignatureProtocol` | no |
| `com.apple.lsd.encryption` | `_LSDDeviceEncryptionService` | 12 | `_LSDDeviceEncryptionServiceProtocol` | yes |

The other published names (`dissemination`, `plugin`, `openurl`, `diagnostics`, `extensions`, `personaobserver`, `security.translocation`) have classes/protocols in the framework (`_LSDDisseminationService`, `LSDPluginManager`, `LSAppTranslocationResult`, ...) but are not `_LSDService` subclasses; their protocol shapes are in section 2.3 where a protocol exists, the rest is unknown (U4). The mapping of the remaining connection types (2, 4, 5, 6, 9, 10, 11, 13, 14) to names is **[inferred]** from the order of the name strings (2 openurl, 4 plugin, 5 xpc, 9 diagnostics, 10 icons, 11 dissemination, 13 rebuild, 14 appprotection) and is not needed for the Dock.

All NSXPC services are created by `-[NSXPCConnection initWithMachServiceName:options:]` with **options 0** (clients) **[captured: xcap]**; the server accepts every connection and keeps one `_LSDClient` per connection (`_LSDService -listener:shouldAcceptNewConnection:`); entitlement checks are per method (below, e.g. error -54 "required entitlement missing").

What the real Dock looks up of these: `com.apple.lsd.mapdb`, `com.apple.lsd.modifydb`, `com.apple.coreservices.launchservicesd` (+ `lsbestappsuggestionmanager`, `sharedfilelistd`, `appleevents`, not Launch Services daemons) **[captured: research/dock-trace golden trace]**.

## 2. NSXPC protocols (full extended type encodings and allowed classes)

Read with `protocol_copyMethodDescriptionList` + `_protocol_getMethodTypeEncoding`, allowed classes with `-[NSXPCInterface classesForSelector:argumentIndex:ofReply:]` on `+[<Service> XPCInterface]` **[runtime]**; complete text in `tools/launchservices/captures/protocols.txt` (regenerate with `probes/p.m`). Envelope and `bplist17` as in ICONSERVICES-WIRE section 3 (`f=33`, `root`, `proxynum=1`, `replysig`, `sequence`, `ool`). Reply blocks use the compact types `v@?...`. In the tables `arg`/`reply` are the allowed class sets set by `setClasses:forSelector:`; "(ext)" means the class named in the extended type encoding only.

### 2.1 `_LSDReadProtocol` (`com.apple.lsd.mapdb`), 15 methods, all required

| selector | extended type | arg classes | reply classes |
|---|---|---|---|
| `getServerStoreNonBlockingWithCompletionHandler:` | `v24@0:8@?<v@?@@"FSNode"@"NSXPCListenerEndpoint"c@"NSError">16` | - | 0 `_CSStore`, 1 `FSNode`, 2 `NSXPCListenerEndpoint`, 3 BOOL, 4 `NSError` |
| `getSystemContentStoreWithCompletionHandler:` | `...@?<v@?@@"FSNode"@"NSError">16` | - | 0 `_CSStore`, 1 `FSNode`, 2 `NSError` |
| `getServerStatusWithCompletionHandler:` | `...@?<v@?I>16` | - | 0 uint32 |
| `getSystemModeWithCompletionHandler:` | `...<v@?@"NSString"@"NSError">` | - | NSString, NSError |
| `getPreferencesWithCompletionHandler:` | `...<v@?@"NSDictionary"@"NSError">` | - | plist classes (NSArray NSData NSDate NSDictionary NSNull NSNumber NSOrderedSet NSSet NSString), NSError |
| `getSettingsStoreConfigurationWithCompletionHandler:` | `...<v@?@"LSSettingsStoreConfiguration"@"NSError">` | - | `LSSettingsStoreConfiguration`, NSError |
| `getSelectedDeveloperDirectoryURLWithCompletionHandler:` | `...<v@?@"NSURL">` | - | NSURL |
| `getKernelPackageExtensionsWithCompletionHandler:` | `...<v@?@"NSArray"@"NSError">` | - | NSArray+NSString, NSError |
| `getApplicationCategoryIdentifiersSetWithCompletionHandler:` | `...<v@?@"NSSet"@"NSError">` | - | NSSet+NSString, NSError |
| `getSessionLanguagesForImproperlyLocalizedProcessWithCompletionHandler:` | `...<v@?@"NSArray"@"NSError">` | - | NSArray+NSString |
| `getEligibilityAnswerForDomain:withCompletionHandler:` | `v32@0:8Q16@?<v@?@"NSNumber"@"NSError">24` | - | NSNumber, NSError |
| `getCurrentApplicationDefaultInfoForCategory:completion:` | `v32@0:8Q16@?<v@?@"LSDefaultApplicationQueryResult"@"NSError">24` | - | `LSDefaultApplicationQueryResult`, NSError |
| `mapBundleIdentifiers:orMachOUUIDs:completionHandler:` | `v40@0:8@"NSSet"16@"NSSet"24@?<v@?@"NSArray"@"NSArray"@"NSError">32` | 0 {NSSet,NSString}, 1 {NSSet,NSUUID} | NSArray+NSUUID, NSArray+NSString, NSError |
| `mapPlugInBundleIdentifiersToContainingBundleIdentifiers:completionHandler:` | `v32@0:8@"NSSet"16@?<v@?@"NSDictionary"@"NSError">24` | 0 {NSSet,NSString} | NSDictionary+NSString, NSError |
| `getRedactedAppexRecordForSystemAppexWithUUID:node:bundleIdentifier:platform:completionHandler:` | `v52@0:8@"NSUUID"16@"FSNode"24@"NSString"32I40@?<v@?@"LSApplicationExtensionRecord"@"NSError">44` | NSUUID, FSNode, NSString | `LSApplicationExtensionRecord`, NSError |
| `getRedactedPluginProxyForSystemAppexWithUUID:node:bundleIdentifier:platform:completionHandler:` | same args, reply `@"LSPlugInKitProxy"` | same | `LSPlugInKitProxy`, NSError |

(`_LSDReadClient` also implements `getPreferredAppMarketplacesWithCompletion:` that is not in the protocol **[header]**.)

Real replies of the VM, decoded **[captured: rd.m, `captures/lsdread-replies.txt`]**: `getServerStatus` -> 256; `getSystemMode` -> (nil, nil); `getPreferences` -> empty NSDictionary; `getSettingsStoreConfiguration` -> `LSSettingsStoreConfiguration{endpoint: NSXPCListenerEndpoint{ep:0}}` (endpoint in `ool[0]`, an `_LSServerSettingsStoreXPCProtocol` listener); `getSelectedDeveloperDirectoryURL` -> `file:///Library/Developer/CommandLineTools/`; `getKernelPackageExtensions` -> NSArray of 105 strings (extensions that are packages: `app`, `bundle`, `kext`, ...); `getApplicationCategoryIdentifiersSet` -> NSSet of 47 `public.app-category.*`; `getSystemContentStore` -> (`_CSStore`, `FSNode .../SystemDataOnly-com.apple.LaunchServices-20971545-v2.csstore`, nil), a second, system-only store (7.9 MB, generation 273023); `getEligibilityAnswerForDomain:0` -> `NSOSStatusErrorDomain -50 "Can't ask to evaluate domain 0"` (`_LSLine/_LSFunction/_LSFile/_LSErrorMessage` in userInfo); `mapBundleIdentifiers:...` and `mapPlugIn...` from an unentitled caller -> `NSOSStatusErrorDomain -54` ("required entitlement missing").

### 2.2 `_LSDModifyProtocol` (`com.apple.lsd.modifydb`), 29 methods

Extended types (reply block in angle brackets; `c` = BOOL, `I` = uint32):

| selector | extended type | arg classes |
|---|---|---|
| `registerItemInfo:alias:diskImageAlias:bundleURL:installationPlist:completionHandler:` | `v64@0:8@"LSRegistrationInfo"16@"NSData"24@"NSData"32@"NSURL"40@"NSDictionary"48@?<v@?cI@"NSArray"c@"NSError">56` | LSRegistrationInfo; NSData; NSData; NSURL; plist set {NSArray NSData NSDate NSDictionary NSNumber NSString} |
| `unregisterBundleUnit:options:completionHandler:` | `v32@0:8I16I20@?<v@?c@"NSError">24` | - |
| `registerContainerURL:completionHandler:` | `v32@0:8@"NSURL"16@?<v@?I@"NSError">24` | NSURL |
| `updateContainerUnit:completionHandler:` | `v28@0:8I16@?<v@?@"NSData"@"NSError">20` | - |
| `removeContainer:` | `v20@0:8I16` | - |
| `registerExtensionPoint:platform:declaringURL:withInfo:completionHandler:` | `v52@0:8@"NSString"16I24@"NSURL"28@"NSDictionary"36@?<v@?c@"NSError">44` | NSString; -; NSURL; plist set |
| `unregisterExtensionPoint:platform:withVersion:parentBundleUnit:completionHandler:` | `v48@0:8@"NSString"16I24@"NSString"28I36@?<v@?c@"NSError">40` | NSString; -; NSString |
| `performPostInstallationRegistration:personaUniqueStrings:operationUUID:reply:` | `v48@0:8@"NSArray"16@"NSArray"24@"NSUUID"32@?<v@?@"LSRecordPromise"@"<_LSPendingSaveToken>"@"NSError">40` | plist set; {NSArray,NSString}; NSUUID. Reply 0 `LSRecordPromise`, **reply 1 is a proxy** (`_LSPendingSaveToken` remote object, NSXPC reverse interface), 2 NSError |
| `performPostUninstallationUnregistrationOfBundleID:operationUUID:unregisterType:precondition:reply:` | `v52@0:8@"NSString"16@"NSUUID"24I32@"LSPrecondition"36@?<v@?@"<_LSPendingSaveToken>"@"NSError">44` | NSString; NSUUID; -; LSPrecondition. Reply 0 proxy |
| `performUpdateOfPersonasOfBundleIDs:toPersonaUniqueStrings:operationUUID:reply:` | `v48@0:8@"NSSet"16@"NSSet"24@"NSUUID"32@?<v@?@"<_LSPendingSaveToken>"@"NSError">40` | {NSSet,NSString} x2; NSUUID. Reply 0 proxy |
| `updateRecordForApp:withSINF:iTunesMetadata:placeholderMetadata:sendNotification:operationUUID:returnSaveToken:completionHandler:` | `v72@0:8@"NSString"16@"NSDictionary"24@"NSDictionary"32@"NSDictionary"40i48@"NSUUID"52c60@?<v@?c@"<_LSPendingSaveToken>"@"NSError">64` | NSString; plist set x3; -; NSUUID. Reply 1 proxy |
| `setHandler:version:forURLScheme:completionHandler:` | `v72@0:8@"NSString"16{LSVersionNumber=[32C]}24@"NSString"56@?<v@?c@"NSError">64` | NSString; struct; NSString |
| `setHandler:version:roles:forContentType:completionHandler:` | `v76@0:8@"NSString"16{LSVersionNumber=[32C]}24I56@"NSString"60@?<v@?c@"NSError">68` | NSString; struct; -; NSString |
| `removeHandlerForURLScheme:completionHandler:`, `removeHandlerForContentType:roles:completionHandler:`, `removeAllHandlerPrefsForBundleID:completionHandler:`, `removeAllHandlersWithCompletionHandler:` | NSString args, reply `v@?c@"NSError"` | NSString |
| `setPreferenceValue:forKey:forApplicationAtURL:completionHandler:`, `setPreferenceValueForCallingApplication:forKey:completionHandler:` | `v48@0:8@16@"NSString"24@"NSURL"32@?<v@?c@"NSError">40` / `v40...` | plist set; NSString; NSURL |
| `setDatabaseIsSeeded:completionHandler:` | `v28@0:8c16@?<v@?c@"NSError">20` | - |
| `garbageCollectDatabaseWithCompletionHandler:`, `resetServerStoreWithCompletionHandler:`, `removeDatabaseStoreOnNextOpportunity:`, `forceSaveForTestingWithCompletion:` (reply `v@?@"NSError"`), `requestLSDExitSafely:completionHandler:` (`d16`) | simple | - |
| `registerSelf`, `synchronizeWithMobileInstallation` | `v16@0:8` (no reply) | - |

`LSRegistrationInfo` (keys, **[captured]** for `LSRegisterURL` / display-name lookup of an unregistered app): `version` (7), `action` (203), `options` (0x2000000), `itemFlags` (1048590), `containerUnit` (Container unit id, 4 = the `/` volume record), `bundleUnit` (0 = new), `bundleClass` (2 = application), `inoBundle`, `inoExec`, `contentModDate`, `execContentModDate` (doubles).

### 2.3 Other protocols

- `_LSDOpenProtocol` (`com.apple.lsd.open`, type 3): `failedToOpenApplication:withURL:completionHandler:` (`v40@0:8@"NSString"16@"NSURL"24@?<v@?c@"NSError">32`), `getURLOverrideForURL:completionHandler:` (`...<v@?@"NSURL"@"NSError">`), `getiCloudHostNamesWithCompletionHandler:` (`<v@?@"NSSet">`), `openUserActivityWithUniqueIdentifier:activityData:activityType:bundleIdentifier:options:completionHandler:` (`v64@0:8@"NSUUID"16@"NSData"24@"NSString"32@"NSString"40@"NSDictionary"48@?<v@?c@"NSError">56`), `updateRestrictionKnowledgeWithCompletionHandler:` (`<v@?c@"NSError">`).
- `_LSDDeviceIdentifierProtocol` (`advertisingidentifiers`, type 7): `getIdentifierOfType:completionHandler:` (`v32@0:8q16@?<v@?@"NSUUID">24`), `getIdentifierOfType:forApplicationAtURL:completionHandler:` (NSURL), `getIdentifierOfType:vendorName:completionHandler:` (NSString), `clearAllIdentifiersOfType:` (`v24@0:8q16`).
- `_LSDTrustedSignatureProtocol` (`trustedsignatures`, type 8): `getIsTrustedForURL:completionHandler:` (`<v@?@"NSNumber"@"NSError">`), `trust:URL:completionHandler:` (`v36@0:8c16@"NSURL"20@?<v@?c@"NSError">28`), `updateTrustExpirationDateForURL:`.
- `_LSDDeviceEncryptionServiceProtocol` (`encryption`, type 12, privileged): `encryptData:reply:`, `decryptData:reply:` (`v32@0:8@"NSData"16@?<v@?@"NSData"@"NSError">24`).
- Not `_LSDService`-based **[runtime, classes inferred from the extended types only: `interfaceWithProtocol:`, the real `setClasses:` calls were not read]**: `_LSDDisseminationServerProtocol` (`registerDisseminationSinkWithReply:` -> NSDictionary, NSError; server side of `dissemination`) and `_LSDDisseminationClientProtocol` (`bundleContainerizedBundleModifiedWithIdentifier:completion:`, `bundleMetadataUpdatedForIdentifier:SINF:iTunesPlist:placeholderMetadata:completion:`, delivered to the registered sink); `LSDPluginProtocol` (`XPCListenerEndpoint`, `start`) and `LSDPluginServiceProtocol` (`endpointForServiceIdentifier:reply:` -> NSXPCListenerEndpoint); `LSDatabaseBlockingFetchProtocol` (`getServerStoreBlockingWithCompletionHandler:` reply `(_CSStore, FSNode, NSError)`; Mach name `com.apple.lsd.LSDatabaseBlockingFetchServer`, an internal helper listener); `_LSServerSettingsStoreXPCProtocol` (`userElectionForExtensionKey:reply:`, `setUserElection:forExtensionKey:reply:`, `resetUserElectionsWithReply:`; the endpoint returned by `getSettingsStoreConfiguration`); `LSCodeEvaluationServerProtocol`/`ClientProtocol` (`com.apple.coreservices.code-evaluation`, the Gatekeeper UI helper, not needed); `LSInstallProgressProtocol`.

## 3. What a client does at the first Launch Services use

Client = `probes/c.m` (`mode seq` calls `+[LSRecord _is_getSequenceNumber:andUUID:]`, the call IconServices makes in `ISGenerationRequest`) under `xcap.dylib` **[captured]**; text in `captures/getServerStoreNonBlocking.txt`.

1. `CONNECT com.apple.lsd.mapdb flags=0` and, **synchronously**, `getServerStoreNonBlockingWithCompletionHandler:` (sequence 1). Request root: `["getServerStoreNonBlockingWithCompletionHandler:", "v24@0:8@?16", [nil]]`; `replysig = v44@?0@8@"FSNode"16@"NSXPCListenerEndpoint"24c32@"NSError"36`.
2. Reply (495-byte root + `ool`):
```
[ nil, "v@?@@"FSNode"@"NSXPCListenerEndpoint"c@"NSError"", [
    { $class:"_CSStore", XPCRepresentation: 0 },                 // 0 = index into the message's "ool" array
    { $class:"FSNode", URL:{NSURL NS.base:nil NS.relative:"file:///var/folders/<hash>/<hash>/0/com.apple.LaunchServices.dv/com.apple.LaunchServices-20971545-v2.csstore"},
      isDirectory:0, referringAliasNode:nil },
    nil,        // NSXPCListenerEndpoint
    0,          // BOOL
    nil ] ]     // NSError
xpc dictionary: root (data), ool = [ <xpc data, 10125312 bytes> ]
```
   `_CSStore` encodes itself with `encodeXPCObject:forKey:` under the key `XPCRepresentation`: the value is an **xpc data object holding the whole store file** (libxpc sends it as an out-of-line descriptor); `-[_CSStore initWithCoder:]` -> `__CSStoreCreateWithXPCRepresentation` -> `CSStore2::Store::CreateWithXPCObject` **[captured + header]**. The file is also named by the FSNode: the client process has the file mapped by that path (`lsof`: `txt REG ...com.apple.LaunchServices-20971545-v2.csstore`; `vmmap`: `mapped file ... rw-/rwx SM=COW` of the same size as the ool data) **[captured]**. Whether the client uses the mapping or the xpc data, and what the endpoint/BOOL mean, is not determined (U1); a replacement should send both exactly like this (the data identical to the file, the file readable by the client).
3. From the store the client reads the **database header** (section 5.3) and nothing else is needed for `_is_getSequenceNumber:andUUID:`: sequence = `CacheSequenceNum` (2148 on the VM), UUID = `CacheGUID` (7CEC9DD7-EAC7-4AA5-878E-B3CE4DB0524D); both equal what `lsregister -dump` prints and what IconServices put in `ISGenerationRequest.lsDatabaseSequenceNumber/lsDatabaseUUID` **[captured]**. So the "database UUID + sequence number" IconServices needs are bytes 0x68/0x88 of the header unit of the store (section 5.3): the sequence is bumped by the server on every modification (2148 -> 2160 after two registrations of new apps), the UUID is fixed at database creation.
4. Other traffic of the same call: `cfprefsd` (preferences), nothing else; **no other Launch Services XPC call for read-only queries** such as `LSBundleRecord bundleRecordWithBundleIdentifier:` (all lookups run in-process on the mapped store) **[captured]**.
5. Registration of an unknown bundle (`LSCopyDisplayNameForURL` or `LSRegisterURL` on an unregistered `.app`) **[captured: `captures/registerItemInfo.txt`]**: after the first `getServerStore...` the client connects `com.apple.lsd.modifydb` (flags 0) and sends **synchronously** `registerItemInfo:alias:diskImageAlias:bundleURL:installationPlist:completionHandler:` with `LSRegistrationInfo{version 7, action 203, options 33554432, itemFlags 1048590, containerUnit 4, bundleUnit 0, bundleClass 2, inoBundle, inoExec 0, contentModDate, execContentModDate 0}`, `alias` = 692-byte CFURL bookmark data (`book...`) of the bundle, `diskImageAlias` nil, `bundleURL` = `file:///tmp/lsq/T2.app/`, `installationPlist` nil. Reply `[nil, "v@?cI@"NSArray"c@"NSError"", [1, 2160, nil, 0, nil]]` = (success YES, bundleUnit/sequence 2160, nil, NO, nil). Then the client calls `getServerStoreNonBlocking...` **again** (a new 10 MB store, sequence 2160) and posts distributed notifications (`com.apple.distributed_notifications@Uv3`, 2 sends). The **server reads the bundle itself** (Info.plist, code signature, icons) and builds the Bundle/Claim/Type/... records; the client only says which URL.
6. IconServices: `+[LSRecord _is_remapLSDatabase]` forces a re-fetch (same call 1); `_is_resourceTokenForRecords:` is used by the agent when it renders (no extra wire).

Failure behaviour seen in earlier work (lsd-objc README): when the reply is never sent or the connection is invalidated, the client either waits forever or continues without LS data (ControlCenter/Dock hang); a valid reply as above was always accepted.

## 4. Where the stores live

`/private/var/folders/<a>/<b>/0/com.apple.LaunchServices.dv/` (`getconf DARWIN_USER_DIR` + `0/`; the `.dv` suffix = data vault: `ls` there fails with "Operation not permitted" even for root; clients read the file because they hold the vault right, root cannot list it) **[captured: lsof]**:

| file | owner process | size on VM | content |
|---|---|---|---|
| `com.apple.LaunchServices-20971545-v2.csstore` | user `lsd` (per-user DB) | 10,100,736 .. 10,223,616 (grows by registrations; client copies are page-rounded) | everything registered for the user's session (338 bundles) |
| `SystemDataOnly-com.apple.LaunchServices-20971545-v2.csstore` | `getSystemContentStore` | 7,966,720 | system-only part |
| `/private/var/folders/zz/zyxvpxvq6csfxvn_n0000000000000/0/com.apple.LaunchServices.dv/com.apple.LaunchServices-20971545-v2.csstore` | root `lsd` | 10,219,520 | the system-scope DB |

The number 20971545 is `0x01400019`, the first u32 of the database header unit (section 5.3): the LaunchServices schema version, the suffix `v2` the CSStore format version (header byte +4) **[captured + inferred]**. Changing either invalidates old files.

## 5. The CSStore2 database format

Container = `CoreServicesStore.framework` (`CSStore2::Store`, magic `bdsl`). Derived from decompilation (`CSStore2::Store::_Create`, `getUnit`, `String::Create`, `_CSStoreGetUnit`, `_CSStringBindingFindStringAndBindings`) **[decompiled]** and then **verified against Apple's own reader**: a 10 MB real store parsed by `csstore.py` gives the same length and CRC32 for 30,000 randomly sampled units as `_CSStoreGetUnit` of CoreServicesStore (0 mismatches), and a store rebuilt by `csstore_write.py` from those units (all 33 tables, 97,000 units, different layout) is read back identically by Apple's code (0 mismatches of 30,000) **[captured: `probes/u.m`]**. An empty store (`make_empty_store.py`, 33 tables, no records) is opened by `-[_CSStore initWithContentsOfURL:error:]` and its binding units are readable **[captured: `probes/v.m`]**. What was not tested: that the Launch Services layer accepts such a store as a database (U2).

All integers little endian.

### 5.1 File header (100 bytes = `sizeof(Data)`)

```
+0x00 u32 magic = 0x6c736462 ("bdsl").  Old CSStore1 files (first u32 0xd0fad0da or 0xdad0fad0) are refused: "Encountered CSStore1 file, can't read it."
+0x04 u8  version = 2
+0x05 u8  0
+0x06 u16 checksum: let c = crc32(seed 0x6e797267, bytes[100 .. used)); stored = c & 0xffff, or (c & 0xffff) | 0xe000 when (c & 0xffff) <= 2
                    (a stored value <= 2 means "no checksum": the loader then only checks that the file has no run of zeroed pages)
+0x08 u32 generation (580634 on the VM; `lsregister -dump`: "gen"). Bumped by every write of the store; not the LS sequence number
+0x0c u32 used length: bytes in use, <= file length (file lengths are multiples of 4096). Loader refuses file length < this, and this < +0x10
+0x10 u32 live length: bytes of live units; used - live = "Collectable" bytes (lsregister: 355876 = 10121432 - 9765556)
+0x14      the <catalog> table unit (80 bytes), then more units
```
Validation seen in `_Create`: length >= 100, magic, version 2, `used <= length`, `live <= used`, checksum, (tail) zero-page check. A checksum failure returns NSCocoaError 0xffffdae8-family errors.

### 5.2 Units, tables, id maps

```
unit  = u32 hdr | u32 payload_length | payload | pad to 4 bytes        (units are bump-allocated back to back, 4-byte aligned)
        hdr bits 0..29 = unit id >> 2 (so ids are multiples of 4, 0 = null id); bits 30..31 = 1 for table units, else 0
table = a unit in the catalog, payload = name[48] (NUL padded) | u64 0 | u64 0 | u32 last_allocated_index | u32 idmap_offset (0xffffffff = none) | table-specific extra
        (72 + extra bytes; a table id is 4*k, k = 1..; the next unit id of a table = 4*(last_allocated_index+1))
catalog = the table unit at file offset 0x14 (name "<catalog>", hdr 0x7fffdb5d, last_allocated_index 0x21): its unit "records" are the tables themselves
id map (HashMap<id, offset>) = u32 nbuckets | nbuckets x { u32 count, u32 entries_offset } | entries { u32 id, u32 unit_offset }, count entries per bucket, an entry whose offset is 0xffffffff is deleted
        bucket = (id >> 2) % nbuckets          for every table EXCEPT <string> and <array>
        bucket = (id >> 2) & (nbuckets - 1)    for <string> and <array>: nbuckets must be a power of two (the real files use 8192, ~7 per bucket)
```
(Evidence for the last rule: a rebuild with nbuckets = number of units (60,298 / 18,975) was **not found** by `_CSStoreGetUnit` for any string/array unit, a rebuild with 8192 was found for all.) The lookup `Store::getUnit(table, id)`: table -> idmap offset (`table+0x4c`) -> `Find(id)` -> offset -> checks `hdr*4 == id` and that the table-unit flag equals "is the catalog"; failures log "CSStore corruption detected (1/2/3)".

Table list of this OS (id: name, extra bytes), all present in the real file **[captured]**:
4 `DB Header` (192-byte header struct, 5.3), 8 `Bundle`, 12 `Claim`, 16 `Service`, 20 `Type`, 24 `HandlerPref`, 28 `Container`, 32 `Alias`, 36 `Plugin`, 40 `ExtensionPoint`, 44 `BindingList`, 48 `PropertyList`, 52 `LocalizedString`, 56 `CanonicalString` (no extra); 60 `BindableKeyMap` (32), 64 `UTIBinding`, 68 `ExtensionBinding`, 72 `OSTypeBinding`, 76 `MIMEBinding`, 80 `NSPasteboardBinding`, 84 `DeviceModelCodeBinding`, 88 `BluetoothVendorProductIDBinding`, 92 `URLSchemeBinding`, 96 `BundleIDBinding`, 100 `BundleNameBinding`, 104 `ActivityTypeBinding`, 108 `PluginBundleIDBinding`, 112 `PluginProtocolBinding`, 116 `PluginUUIDBinding`, 120 `ExtensionPointIDBinding` (28 each); 124 `<string>` (4: offset of an optional in-file string cache, 0xffffffff accepted), 128 `<array>`, 132 `<dictionary>`.
Record sizes (fixed payload length per table): Bundle 588, Claim 44, Service 44, Type 68, Container 24, Plugin 212, ExtensionPoint 76, LocalizedString 12, CanonicalString 16; Alias 496..1448 (CFURL bookmark data), PropertyList 42..19192, BindingList 16..276, `<string>` 1..298, `<array>` 4..4716, `<dictionary>` 8.

### 5.3 DB Header table (id 4)

The table unit has payload 72 + 192: the 192 extra bytes are the Launch Services database header (offsets from the start of the extra bytes) **[captured: correlated with `lsregister -dump` line by line]**:
```
+0x00 u32 0x01400019   LaunchServices schema version (= 20971545, in the file name)
+0x04 u32 0xc0         size of this struct
+0x08 u64[4]           seeded system version 26,7,2,0         ("Seeded System Version: 26.7.2")
+0x28 u32 0x05000001   flags (seeded ...: not decoded)        +0x2c u32 0
+0x30 char[16]         build "25G332"
+0x40 char[64]         model code "/iMac19,1"                  ("Seeded Model Code")
+0x80 u64              CacheSequenceNum (database sequence number, 2148)
+0x88 uuid[16]         CacheGUID  (7CEC9DD7-EAC7-4AA5-878E-B3CE4DB0524D)   [network order bytes as printed]
+0x98 u32              date initialised, POSIX seconds (1794243379 = 2026-11-09 08:56)
+0x9c u32 0
+0xa0 char[32]         xcode-select version "2416"
```
`tools/launchservices/make_empty_store.py` writes exactly this.

### 5.4 Strings, arrays, dictionaries, property lists

- `<string>` unit payload = UTF-8 bytes, no NUL; id = 4 x sequence. Strings are interned (one unit per distinct string); every other table refers to a string by id. Lookup by content (`String::Find`/`__CSGetStringForCharacters`) uses a hash cache (in memory, optionally persisted: the table extra).
- `<array>` unit: `u32 head` then elements. `head` low bits = count, top byte flags: `0x20` = packed 16-bit elements (`2a000020 1909 410c ...` = 42 u16 ids), 0 = u32 elements (`01000000 a4340600` = 1 element 0x634a4). `00000020` = empty array. Elements are unit ids (strings, claims, ...). Exact flag/width rules: not fully decoded (U3, `CSStore2::Array::_unpack`).
- `<dictionary>` unit = `u32 0, u32 offset of an id map` (key id -> value id); only 7 exist in the real file (unclear use, U3).
- `PropertyList` unit = ASCII `lnch` + a complete binary plist `bplist00...` (Info.plist dictionary, entitlements, ...), referenced from Bundle `infoDictionary`, `entitlements`, `intentDefinitionURLs` ... **[captured]**.
- `Alias` unit = CFURL bookmark data (`book` + `0x2ccc` ...): the bundle's URL; referenced from `Bundle.bookmark`. The path printed by `lsregister` ("path: /System/Applications/iPhone Mirroring.app (0x145c)") is the Alias unit id **[captured]**.

### 5.5 String binding tables (14 of them)

Each binding table (`UTIBinding`, `ExtensionBinding`, `BundleIDBinding`, ...) has one unit (id 4/8/0xc/0x10/0x14) of 8-byte slots, an open-addressing hash set; the table extra (28 bytes) is `u32 0 | u32 unit id | u32 slots (prime: 511, 1021, 2041, 4081, 8161) | u32 used | u32 slots/2 | u32 0xeeeeeee1 (empty marker) | u32 0xddddddd2 (deleted marker)`; `BindableKeyMap` has 4 more bytes. An empty slot is `eeeeeee1 eeeeeee1`. Lookup = string -> string id (`String::Find`) -> `__CSStringBindingGetBindings(store, table, stringId)` -> BindingList unit id **[decompiled]**; the slot layout and the hash that places an id in a slot are not decoded (U3). `BindingList` units (16..276 bytes) hold the list of (claim/type/bundle unit ids) bound to a string; `u32 count, ...` not decoded.

### 5.6 `Bundle` record (588 bytes, `#pragma pack(4)`: 64-bit members are 4-aligned; bit-field structs use the smallest integer)

Offsets from the ObjC type encoding of `LSBundleData` (with member names, in the binary), verified by decoding the Finder record and comparing every field with `lsregister -dump` (bundle id, exec path, version strings, team id `0000000000`, sequenceNumber 1748, ...) **[header + captured]**. Fields hold ids of other units unless noted: S = string id, A = array id, P = PropertyList id, C = Container id, B = Alias id.
```
  0 B bookmark          4 C container       8 S execPath        12 S exactIdentifier  16 S teamID     20 S codeInfoIdentifier
 24 u32 platform (1 = native)   28 i32 registrationTime (POSIX)   32 version[32] (4 x u64)   64 execSDKVersion[32]
 96 A machOUUIDs      100 B dataContainerAlias   104 S bundleName   108 S localizedShortDisplayName  112 S displayName  116 A localizedDisplayName
120 contextualUsageDescriptions  124 P infoDictionary  128 P entitlements  132 groupContainers  136 u8 containingDirectoryClass
137 u8 profileValidationState  140 intentDefinitionURLs  144 u16 _sliceMask  146 flags byte (appleInternal, ..., redactable)
148 u32 _clas (2 = application, kLSBundleClassApplication)   152 u64 _bundleFlags   160 u32 _plistContentFlags   164 u32 _itemFlags
168 u8 _iconFlags  169 _highResFlags  170 appNapFlags  171 eGPUFlags  172..176 safeAperture* / gameMode / identifiedGame flags  177 systemHiddenFlags
180 moreFlags (3 bytes, 19 bits)   184 u32 _hfsType ('APPL')  188 u32 _hfsCreator   192 u64 _inoBundle  200 u64 _inoExec  208 i32 _mtime
212 u32 minSystemVersionPlatform  216 _minSystemVersion[32]  248 _maxSystemVersion[32]  280 u32 ownerUID  284 i32 _executablemtime  288 _execMinOSVersion[32]
320 u64 sequenceNumber (database sequence at the last change of this record)   328 u64 itemID   336 u32 deviceFamilies
340 S identifier  344 A counterpartIdentifiers  348 A equivalentBundleIdentifiers  352 S categoryType  356 S secondaryCategoryType  360 S filename (lower case "finder.app")
364 S bundleVersion  368 S shortVersionString  372 u32 installType  376 u64 installFailureReason  384 S vendorName  388 u64 purchaserDSID  396 u64 downloaderDSID
404 u64 familyID  412 itemName  416 u64 storefront  424 u64 versionIdentifier  432 sourceAppBundleID  436 appVariant  440 managementDeclarationIdentifier
444 u64 ratingRank  452 ratingLabel  456 u64 genreID  464 genre  468 distributorInfo  472 u64 ratingRankEligibilityDomain
480 S primaryIconName  484 P iconsDict  488 A iconFileNames  492 S libraryPath  496 libraryItems  500 A claims  504 A types  508 A services
512 alternateNames  516 alternateBundleIdentifiers  520 A plugins  524 driverExtensions  528 extensionPoints  532 A activityTypes  536 A bgPermittedIDs
540 appContainerAlias  544 u8 revision  545 retries  548 sandboxEnvironmentVariables  552 bundlePersonas  556 bundlePersonaTypes  560 i32 recordModificationTime
564 supportedGameControllers  568 wrappedRelativePath  572 mobileInstallIDs  576 applicationManagementDomain  580 A trustedCodeHashes  584 reserved
```
Other record layouts: `LSExtensionPointData = {i, I, version[32], I x6, Q}` (76 bytes), `LSPluginData = {LSBundleBaseData(148), I x5, version[32], I x3}` (212), `LSSliceData {i,i}`, `LSPersistentIdentifierData {C, C[3], I, I, C[16], c[0]}` **[header]**. `Claim` (44), `Service` (44), `Type` (68), `Container` (24), `Alias` and `LocalizedString`/`CanonicalString` have no named encoding in the binary; their fields are U3.

### 5.7 What it takes for a client to accept a store (evidence: Apple's client on the Mac VM, `probes/lsf.m` + `probes/q.m`)

`__LSDatabaseCreateWithAccessContext` -> `_LSSchemaConfigureForStore` **[decompiled]** runs on every store a client receives; when it fails the client logs "LaunchServices database schema version: 20971545 ... _LSSchemaConfigureForStore failed ... Building database from scratch in this client!" (`log show --predicate 'process == "q"'`), ignores the file and registers the system bundles itself in memory (this is what the earlier empty store did: lookups answered "not found"). The checks, in order:
1. table `DB Header` exists, its extra is 0xc0 bytes, `u32[0]` = schema version 0x01400019, `u32[1]` = 0xc0.
2. the 13 tables Bundle, Claim, Service, Type, HandlerPref, Container, Alias, Plugin, ExtensionPoint, BindingList, PropertyList, LocalizedString, CanonicalString exist (looked up by name).
3. `_CSBindableKeyMapInit("BindableKeyMap")`.
4. for the 15 binding tables (`kLSBindingInfo`: UTIBinding, ExtensionBinding, OSTypeBinding, MIMEBinding, NSPasteboardBinding, DeviceModelCodeBinding, BluetoothVendorProductIDBinding, URLSchemeBinding, BundleIDBinding, BundleNameBinding, ActivityTypeBinding, PluginBundleIDBinding, PluginProtocolBinding, PluginUUIDBinding, ExtensionPointIDBinding): the **binding class name must exist as a string in the store** (`__CSGetStringForCharacters`; error kLSDataErr, `_LSSchemaConfigureBindingMap`, `BindingClassName=...`), then `_CSStringBindingStoreInit`. Class names: `com.apple.uniform-type-identifier`, `public.filename-extension`, `com.apple.ostype`, `public.mime-type`, `com.apple.nspboard-type`, `com.apple.device-model-code`, `public.bluetooth-vendor-product-id`, `public.url-scheme` (the first eight strings of a real store, ids 4, 8, ..., 0x20; the last seven tables have none). `BindingList` entries use these string ids as the class of a list of values (5.9).
An empty store with those 8 strings, a correct `<string>` cache (5.8) and the 33 tables is accepted (no "from scratch" message). `lsbuild.LSDB` does it.

### 5.8 Strings: immediate ids, the string cache, the hash

`CSStore2::String::Find(store, chars, len)` **[decompiled]**:
- A string of 1..5 characters, every character in `kPackedAlphabet` = `"\0 abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"` (64 bytes; index 0 is NUL) has **no unit**: its id is `pack * 4 + 1`, `pack` = the 6-bit alphabet indexes, first character most significant (`png` = 0x44f21 is the key of ExtensionBinding, found with it in the real store). Ids with bit 0 set are therefore not unit ids; the empty string is id 1. Every record field that holds a string id may hold such an immediate (language codes, extensions, `APPL` ...).
- Any other string: the persisted cache. The `<string>` table's 4 extra bytes hold the **file offset** of a raw block (not a unit; in the real file it sits right before the `<array>` table unit): `u32 nbuckets` (<= 0x2000, real 8192) | `nbuckets x {u32 count, u32 absolute offset of the entries}` | entries `{u32 string id, u32 0x100 + retain count}` (8 bytes, `count` of them in the bucket). Bucket = `hash(utf8 bytes) % nbuckets`, `hash`: `h = len; for each byte b: h = b + h*17 (32 bit); if len > 0x80 only the first and the last 64 bytes; result = ((h << (len & 7)) + h) & 0xffff`. Verified for all 60,298 strings of the real store (0 mismatches). `Find` reads **only** this cache: a non-immediate string that is not in it does not exist for the client, whatever the `<string>` units say. `String::Get(id)` of a unit needs no cache.
The cache also holds ~10,000 more entries than there are strings (ids of other tables, flag word 0): not needed.

### 5.9 String bindings (the 15 hash tables) - decoded, verified with Apple's code

Header = the table's extra (28 bytes): `u32 0 | u32 unit id of the hash unit | u32 slots n | u32 free slots (n - live keys) | u32 n/2 | u32 0xeeeeeee1 (empty) | u32 0xddddddd2 (deleted)`. The hash unit is `keys[n]` then `values[n]` (two u32 arrays, 8n bytes; **not** pairs): `CSMapFindBucketForKey`, `CSMapGetValue`, `CSMapSetValue` **[decompiled]**.
- key = string id (5.8; immediate ids are keys too), `slot = key % n` (no hash function for the string bindings), linear probing forward with wrap-around; a miss is an empty slot (a deleted slot is skipped). `n` is a prime of the series 511, 1021, 2041, 4081, 8161 (`n -> 2n - 1`): `CSMapSetValue` grows the table when free == n/2.
- value = **unit id of an `<array>`** (5.4). `BundleIDBinding`: array of Bundle unit ids with that CFBundleIdentifier (com.apple.finder -> `[0x6d4]`, com.apple.calculator -> 5 bundles: the system one and four test copies). `ExtensionBinding`, `UTIBinding`, `MIMEBinding`, `OSTypeBinding`, `URLSchemeBinding`: arrays of Claim / Type / Service ids (the table of each element is not tagged; it follows from the binding class). `BundleNameBinding`, `ActivityTypeBinding`, `Plugin*`: arrays of Plugin / Bundle ids.
- Reading: `_CSStringBindingFindStringAndBindings(store, CSMap*, chars, len, &stringId, &arrayId)`; `probes/b.m` calls it on a file (the map object is made with `_CSStringBindingStoreInit(store, tableName, 0, 1, buf)`): finds com.apple.finder in the real store (array `01 00 00 20 d4 06`), and in stores written by `lsbuild.py`.
- BindableKeyMap has the same unit shape but small integer keys (not decoded).
- Arrays (5.4) are now fully known: payload = `u32 head` + elements; `head = count | 0x20000000` and u16 elements **iff every element < 0x10000**, else `head = count` and u32 elements; element order is the order of insertion (not sorted); the unit length is `4 + count*width` (the 4-byte alignment is outside the payload).

### 5.10 Property lists are compacted

A `PropertyList` unit = `lnch` + binary plist whose **keys and string values are replaced by short forms** (`_LSPlistCompactString`, `_LSPlistRestoreString` **[decompiled]**; the Info.plist of Calculator is stored as `{'p': 'com.apple.calculator', 'e': '6.0', 'g': ['MacOSX'], 'O': 'Calculator', 'm': 'APPL', ...}`; readers compact the key they ask for, so uncompacted keys are **not found**). Rule: the list `common` of 257 strings (the block of `_LSPlistGetCommonStrings`: CFBundleInfoDictionaryVersion, CFBundleIdentifier, ... entitlements, in a fixed order; metadata of the Apple binary, extracted by `extract_common_strings.py`, not stored in this repository). A string equal to `common[i]` becomes `abbreviation(i)`: the base-64 digits of `i`, least significant first, alphabet `abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ~!@#$%^&*()_` (`i < 64`: 1 character, `i < 256`: 2). A string that already equals one of the 256 abbreviations, or starts with U+0008, gets U+0008 in front. Everything else is stored unchanged. Same for the entitlements plist and the icons plist (`iconsDict`: `{'S': {CFBundleIconFile..}}`, key `S` = common[44]).

### 5.11 Alias = CFURL bookmark data (byte-exact writer)

Layout in `tools/launchservices/bookmark.py` (header `book`, 0x40-byte header, data items {len, type, payload}, TOC `0xfffffffe`). `bookmark.for_path` re-creates, **byte for byte**, the Alias units of the real store for `/System/Library/CoreServices/Finder.app` (716 bytes) and `/tmp/Fake_ours.app` (668 bytes) **[verified: `r == d`]**. Keys: 0xd010 flags (`00000020`), 0x1004 path components of the **resolved** path (`/tmp/x` is `private`, `tmp`, `x`), 0x1020 file name, 0x1005 file ids of the components (u64; on the system volume `0x0fffffff00000000 | inode`), 0x1030 file id of the item, 0x1040 creation date (big-endian double, CFAbsoluteTime = birth time - 978307200), 0x1010 properties (3 x u64: 2, 0xf, 0), 0x2005 volume URL `file:///`, 0x2010 volume name, 0x2012 volume size, 0x2013 volume creation date, 0x2011 volume UUID string, 0x2020 volume flags (24 bytes), 0x2002 mount point, 0x2030 is-root (type 0x0501 = true), 0xff00 the path as the caller gave it. Identical items are written once (the file name item is the last path component).

## 6. `com.apple.coreservices.launchservicesd` (plain XPC dictionaries)

Full conversation of a minimal AppKit client (`probes/a.m`, `NSApplication sharedApplication` + `finishLaunching`), in `captures/launchservicesd-xpc.txt` **[captured]**. Connection flags 2 (privileged); every request is a dictionary with `command` (int64) and `session` (int64: -2 = "the session of the calling process" in the first messages; replies to 100/410 carry 100001, the user session id; later requests of the same client carry 100728, a number the client derived after check-in, not decoded); replies carry `success` (bool).

| command | request keys | reply | notes |
|---|---|---|---|
| 100 | `clientversion` (u64 277872640 = 0x10900000) | `serverversion` (same), `success` true, `session` int64 100001 | first message; client library version echo |
| 110 | - | `lsinfopage` (xpc shmem, 61440 bytes = 15 pages), `success` | polled between almost all other calls; shared "info page", header `04 01 00 00 | 00 f0 00 00 (size 0xf000) | a1 86 01 00 (=100001, the session)` then 0x...-byte records of running applications (ASN, uuid, flags): layout not decoded (U5). The pearOS stub sends an all-zero page |
| 130 | `asn1`, `asn2` (u64) | `success` false (unknown ASN) | |
| 200 | `wanted` array of key names (`LSSessionID`) | `metainfo` {LSSessionID: int64 100001}, `success` | stub answers `LSCGSSessionID` |
| 300 | - | `success` false while no application is in front | front application |
| 360 | `asn` (u64 = hi<<32 | lo), optional `restrictto` array of keys | `success` false (unknown asn) or `result` dictionary (the keys asked, or the whole record) + `cacheable` bool (true when the whole record was asked) | the record of an application, section 6.1 |
| 410 | `listener` (xpc endpoint), `needsassertions` bool, `clientid` u64, `addasn` array of u64 (first) or `set` array of u64 notification-class ids (512, 513, 561, ...) plus `id` | `id` u64 (10371), `success`, `affectedasns` array, `session` | registers the client's listener endpoint for LS notifications (the same message also carries an NSXPC invocation `registerListenerEndpointWithXPCListenerEndpoint:reply:` with the endpoint in `ool[0]`) |
| 500 | `info` dictionary (below), `deathport` (mach send right) | `success`, `result` dictionary (the check-in record, section 6.1) | application check-in. The earlier stub shape was confirmed |
| 505 | - | `success` false | |
| 510 | `asn`, `info` {key: value to set} (e.g. `LSNotifyApplicationFrontable`, `LSPersistenceSuppressRelaunchAtLogin`, `ApplicationType`) | `success`, `info` = whole record after the change | `ChangeCount` grows by 2 per set |

6.1 Check-in `info` of a plain Mach-O (`500`): `LSDisplayName`, `CFBundleSignature` "????", `LSExecutableFileName`, `CFBundleExecutablePath`, `LSExecutableSDKVersion` "26.5", `LSCheckInTime*` (xpc date), `LSArchitecture` "x86_64", `CFBundlePackageType` "????", `LSDYLDPlatformKey` 1, `Flavor` 3, `ApplicationType` "BackgroundOnly". The reply `result` adds `LSAuditToken` (32 bytes, the audit token), `LSExecutableFilenameLowerCaseKey`, `LSApplicationMemberCoalitionIDKey` (int64), `LSASN` {`com.apple.coreservices.asn.lo` u64, `com.apple.coreservices.asn.hi` u64 0, `com.apple.coreservices.asn` uuid C96172A0-CE74-4D62-AFEF-ECFE4D04D827}, `pid`, `LSApplicationHasRegistered` true, `ChangeCount` int64 (515, +2 per set), `CFBundleExecutablePathDeviceID`, `CFBundleExecutablePathINode`, later `LSApplicationReadyToBeFrontableKey`, `CanBecomeFrontmost`, `Hidden`, `LSApplicationHasSignalledItIsReady`. The ASN as a number is `hi << 32 | lo` (4295013348 = 0x10000b3e4 = 0x100000000 + 430180; the check-in reply shows `lo` 430185 for the same process: the request value `asn` is `hi<<32|lo` of the number the client was given by a previous call, exact relation to `LSASN.lo` not established).

## 7. Minimal compatible subset for the Dock

What blocks the pearOS Dock now: the first call of the first LS user (IconServices `ISGenerationRequest`, or any `LSRecord` use) is the **synchronous** `getServerStoreNonBlocking...` on `com.apple.lsd.mapdb`; if the server cannot answer with a valid store the client waits or the connection is dropped (lsd-objc README).

Needed, in this order:
1. `com.apple.lsd.mapdb` (NSXPC, options 0): `getServerStoreNonBlocking...` -> exactly the reply of section 3 (`_CSStore{XPCRepresentation:0}`, `FSNode` of the store file, nil, 0, nil, with `ool[0]` = the file as an xpc data object). Everything else of `_LSDReadProtocol` may answer with the values of 2.1 (status 256, empty preferences, `LSSettingsStoreConfiguration` with an endpoint, developer dir, 105/47 element sets, errors -50/-54 for the entitled calls); `getSystemContentStore...` -> the same shape with the system store (or the same store).
2. The store: a valid container (5.1/5.2) with the 33 tables and a header (5.3) whose **UUID is stable and sequence bumped on every change**; `make_empty_store.py` produces such a file. To show tiles with name and icon the database needs the Bundle record (5.6) plus its strings/plists of every application the Dock lists; the *icon pixels* do not come from the database (IconServices renders from the bundle), the database supplies bundle identity (`identifier`, `execPath`, `iconsDict`/`primaryIconName`, `_itemFlags`, `claims/types`) to `ISBundleIcon`. Which exact fields the Dock path reads is **not yet traced** (U6).
3. `com.apple.lsd.modifydb`: `registerItemInfo:...` must return `(YES, unit, nil, NO, nil)` and update the store (read the bundle, write the records, bump the sequence), and the next `getServerStore...` must return the new store; `unregisterBundleUnit`, `registerContainerURL` (reply `I` = container unit) and `setDatabaseIsSeeded` as simple success. The remaining methods can reply success/nil.
4. `com.apple.coreservices.launchservicesd`: 100, 110, 130, 200, 300, 360, 410, 500, 505, 510 as in section 6 (the existing `lsd-stub` already does most; 130 is new).
5. Not needed for startup: `open`, `openurl`, `advertisingidentifiers`, `trustedsignatures`, `encryption`, `dissemination`, `plugin`, `diagnostics`, `extensions`, `personaobserver`, `translocation`.

Not testable on this machine: the FreeBSD VM lacks the Mac-side runtime files (`/root/dnew`, `/root/macbins`), so a store written by our tools has not been given to a real Launch Services client on pearOS yet; only Apple's CoreServicesStore reader has accepted it (section 5).

## 8. Tools

| file | purpose |
|---|---|
| `tools/launchservices/probes/p.m` | dumps every `_LSDService` subclass: protocol, type encodings, allowed classes, connection type |
| `probes/xcap.c` | interposer: logs/saves every XPC send/reply (root, ool, shared memory) |
| `probes/c.m`, `a.m`, `rd.m` | clients: first use, AppKit check-in, all read methods |
| `probes/v.m`, `u.m` | open a csstore with Apple's reader / read units through `_CSStoreGetUnit` |
| `probes/fcap.c` | open/mmap interposer (did not trigger: the client maps through another path) |
| `csstore.py` | read-only parser (`FILE`, `FILE TABLE [N]`) |
| `csstore_write.py`, `make_empty_store.py` | container writer; empty 33-table store with a DB header |
| `lsrecord.py`, `extract_enc.py` | decode a record from the named ObjC struct encoding taken from the user's LaunchServices binary |
| `captures/` | decoded wire captures and the protocol dump |

## 9. Unknowns and questions

- U1: client use of `FSNode` file vs `XPCRepresentation` data; meaning of the endpoint (reply 2) and BOOL (reply 3) of `getServerStoreNonBlocking`, `getServerStatus` = 256. `fcap` did not see `open`/`mmap` (the client maps through a path not interposed).
- U2: that the Launch Services layer (not only CSStore) accepts a store we wrote: header flags `+0x28 = 0x05000001`, "seeded" state, recovery-file logic. Needs the pearOS stack (or SIP off to attach to lsd).
- U3: layouts of `Claim`, `Type`, `Service`, `Container`, `Plugin` fields, `LocalizedString`, `CanonicalString`, `BindingList`, array flag rules, binding slot layout and its hash, `<dictionary>` use, `Bundle` flag bit meanings; per-field "what the Dock reads".
- U4: protocols of `diagnostics`, `extensions`, `personaobserver`, `openurl`, `security.translocation`; real `setClasses:` of the non-`_LSDService` interfaces; connection types 2/4/5/6/9/10/11/13/14.
- U5: layout of `lsinfopage` (61440-byte shared page).
- U6: which `LSBundleRecord`/`LSApplicationRecord` properties the Dock and IconServices' `ISBundleIcon` read; the server side of registration (what lsd writes for a bundle: strings, plist filtering, bookmark creation, claims from `CFBundleDocumentTypes`, UTType records) was only observed from the client side.
- U7: LSD behaviour with the entitlement checks of `modifydb` for unentitled callers (the probes were not refused for `registerItemInfo`: a plain unsigned user binary registered an app).
- Q1 (owner): Disabling SIP on the Mac VM would allow attaching lldb to `lsd` (server side of registration, `getServerStore`) and reading the `.dv` directory; not needed so far. Say if you want it.

## 10. Reproduce

```
# Mac VM (ssh -p 2229 ...): build and run
clang -fobjc-arc -framework Foundation p.m -o p && ./p
clang -dynamiclib xcap.c -o xcap.dylib; clang -fobjc-arc -framework Foundation -framework CoreServices c.m -o lsc
DYLD_INSERT_LIBRARIES=/tmp/xcap.dylib ./lsc seq          # writes /tmp/lscap/NNN_{ssend,sreply}.root + .ool0, prints the descriptions
python3 tools/iconservices/bp17.py lscap/001_sreply.root   # decode the NSXPC root
python3 tools/launchservices/csstore.py lscap/001_sreply.ool0            # list tables
python3 tools/launchservices/make_empty_store.py empty.csstore 100        # write an empty store; test with probes/v.m
```
