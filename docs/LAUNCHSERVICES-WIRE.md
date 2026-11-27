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

Container = `CoreServicesStore.framework` (`CSStore2::Store`, magic `bdsl`). Derived from decompilation (`CSStore2::Store::_Create`, `getUnit`, `String::Create`, `_CSStoreGetUnit`, `_CSStringBindingFindStringAndBindings`) **[decompiled]** and then **verified against Apple's own reader**: a 10 MB real store parsed by `csstore.py` gives the same length and CRC32 for 30,000 randomly sampled units as `_CSStoreGetUnit` of CoreServicesStore (0 mismatches), and a store rebuilt by `csstore_write.py` from those units (all 33 tables, 97,000 units, different layout) is read back identically by Apple's code (0 mismatches of 30,000) **[captured: `probes/u.m`]**. An empty store (`make_empty_store.py`, 33 tables, no records) is opened by `-[_CSStore initWithContentsOfURL:error:]` and its binding units are readable **[captured: `probes/v.m`]**. The Launch Services layer accepts such a store as a database once the conditions of 5.7 hold (U2 answered).

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
- `<array>` unit: `u32 head` then elements. `head` low bits = count, top byte flags: `0x20` = packed 16-bit elements (`2a000020 1909 410c ...` = 42 u16 ids), 0 = u32 elements (`01000000 a4340600` = 1 element 0x634a4). `00000020` = empty array. Elements are unit ids (strings, claims, ...). Flag/width rules: see 5.9 (u16 packed iff every element < 0x10000).
- `<dictionary>` unit = `u32 0, u32 offset of an id map` (key id -> value id); only 7 exist in the real file (unclear use, U3).
- `PropertyList` unit = ASCII `lnch` + a complete binary plist `bplist00...` (Info.plist dictionary, entitlements, ...), referenced from Bundle `infoDictionary`, `entitlements`, `intentDefinitionURLs` ... **[captured]**.
- `Alias` unit = CFURL bookmark data (`book` + `0x2ccc` ...): the bundle's URL; referenced from `Bundle.bookmark`. The path printed by `lsregister` ("path: /System/Applications/iPhone Mirroring.app (0x145c)") is the Alias unit id **[captured]**.

### 5.5 String binding tables (14 of them)

Each binding table (`UTIBinding`, `ExtensionBinding`, `BundleIDBinding`, ...) has one unit (id 4/8/0xc/0x10/0x14), an open-addressing hash set (the unit is `keys[n]` then `values[n]`, not 8-byte pairs, see 5.9); the table extra (28 bytes) is `u32 0 | u32 unit id | u32 slots (prime: 511, 1021, 2041, 4081, 8161) | u32 used | u32 slots/2 | u32 0xeeeeeee1 (empty marker) | u32 0xddddddd2 (deleted marker)`; `BindableKeyMap` has 4 more bytes. An empty slot is `eeeeeee1 eeeeeee1`. Lookup = string -> string id (`String::Find`) -> `__CSStringBindingGetBindings(store, table, stringId)` -> BindingList unit id **[decompiled]**; slot layout and hash: **decoded in 5.9** (keys[n] then values[n], slot = id % n, linear probing; the value is an `<array>` unit id). `BindingList` units are lists of (binding class, values), see 5.14.

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

### 5.12 What Apple's client needs in a Bundle record (end-to-end, Mac VM, Apple's client against a store written by `lsbuild.py`/`lsapp.py`)

Method: `probes/lsf.m` serves a store FILE as `com.apple.lsd.mapdb` (launchd job `com.pearos.t.lsf`; the client process is pointed at it with `DYLD_INSERT_LIBRARIES=redirect.dylib IS_REDIRECT=com.apple.lsd.mapdb=com.pearos.t.lsf`; **note**: SIP strips `DYLD_*` when the process is started through `/usr/bin/perl` (`perl -e 'alarm N; exec @ARGV'`): put `env DYLD_...=... prog` after perl), `probes/q.m` asks `LSBundleRecord bundleRecordWithBundleIdentifier:allowPlaceholder:error:` (a), `LSApplicationRecord initWithURL:allowPlaceholder:error:` (b) and `gen` (`~/isw/gen.m` of IconServices: `ISBundleIcon initWithBundleURL:` + `ISGenerationRequest generateImageReturningRecordIdentifiers:`, the recipe of the icon agent) (c). Records were removed word by word (delta debugging) from a record that works; every row below is a measured result, a store with **one Bundle record** and nothing else (no claims, types, plugins, services, no localized strings):

| need | Bundle field (offset) | evidence |
|---|---|---|
| store accepted | 5.7 (class-name strings, string cache, 33 tables, header) | without: "Building database from scratch in this client" |
| (a) by identifier | `identifier` S (340) = **lower-case** id; `_clas` (148) = 2 (application; with 0 the evaluator rejects it: "disallowed bundle class"); binding `BundleIDBinding[lower id] = [bundle unit]` | all other words zero: found |
| (a) | `Container` (4) must be a unit id of the Container table; a zero 24-byte payload (state 0) is accepted for lookups but makes the client call `updateContainerUnit:` on every lookup when modifydb is served (5.15) (unit 4 on the VM; a new zero Container, or 0xc, made bid and url fail; 0x8 worked for bid only) | |
| (a) | `_bundleFlags` (152, u64) bit 47 (`0x800000000000`, "in a temporary directory") must be **clear** unless the bundle really is under /tmp: `isBindingOK_NoIO` rejects such bundles for identifier lookups ("temporary directory") **[decompiled]**; the lsd record of a copy in /tmp carries it (0x8000_0000_0082) and is therefore invisible to bundleRecordWithBundleIdentifier: (visible to the URL lookup) | |
| (a) | `_itemFlags` (164): with bit 0x4 set (lsd writes 0x10008e) the lookup of our app in `/Users/alex/lsq` failed, 0x10008a (0x4 cleared) or 0 works; cause not found (U9) | |
| (a) | the string of the identifier must be findable (5.8: not immediate -> in the cache); `exactIdentifier` (12) / `codeInfoIdentifier` (20) are not needed | |
| (b) by URL | `bookmark` (0) = Alias unit (5.11) of the bundle's path | |
| (b) | `revision` (544, u8) = 0xb (the value lsd writes) | without: not found (it is the only scalar the URL lookup needs besides 208) |
| (b) | `_mtime` (208, i32 CFAbsoluteTime seconds) **equal to the bundle directory's mtime**; a wrong value: not found. `_executablemtime` (284) is not checked. `_inoBundle` (192, u64 file id) and `_inoExec` (200) were set to the real ones but not tested alone | |
| (b) | `_LSBundleFindWithNode` **[decompiled]**: reads the identifier of the node, asks the BindingEvaluator (identifier binding) with the filter `_LSBundleMatchesNode`, and falls back to `__CSStoreEnumerateUnits` over the Bundle table with the same filter; `_LSBundleMatchesNode` = `_LSAliasAndInodeOnContainerMatchesNode(db, bookmark, _inoBundle, container, node, flags)`: the Alias is turned into an FSNode and compared by **path** without I/O (`_LSAliasMatchesPath_NoIO` -> `FSNode initWithBookmarkData:` -> `_LSPathMatchesPath_NoIO`), the container record is checked (`_LSContainerCheckState`). So a bundle is found by URL by the path stored in its Alias; the Alias needs the resolved path components and the path string (5.11) | |
| (c) icon | `iconsDict` (484) = PropertyList of `{'CFBundlePrimaryIcon': {'CFBundleIconFile': f, 'CFBundleIconName': n}}` (compacted keys, 5.10). The flat form `{'CFBundleIconFile': ...}` is **ignored**. `primaryIconName` (480) and `iconFileNames` (488) were not needed for the pixels (the record's `iconDictionary` / `iconFileNames` properties return them) | proof: an app whose record says `Other` while Info.plist says `AppIcon` renders `Other.icns` (a different image: md5 9b5017a7... vs 6d15bfe1... for the copy of Calculator; PNGs inspected: the Automator robot vs the calculator); without a record (empty store) the icon comes from Info.plist (the client registers nothing, falls back to the bundle) |
| (c) | the sequence number the icon request carries is `CacheSequenceNum` of the header (`q seq` returns the header value for an accepted store; the earlier "sequence 0" was a rejected store) | |

`localizedName` comes from the file name unless `displayName` (112)/`bundleName` (104)/LocalizedStrings are set; the `infoDictionary` (124) was not needed for any of the three lookups (it is read for individual keys by other APIs).

### 5.13 What lsd writes when it registers an application (diff of the real store before/after `LSRegisterURL` of a fresh copy of Calculator in /tmp with another CFBundleIdentifier, `probes/xcap.c` capture of both `getServerStore` replies; header sequence 2800 -> 2804 for the whole change)

New units: 1 Bundle, 1 Alias, 3 PropertyList (infoDictionary, iconsDict, an empty `{}` plist at 140 whose payload is a raw `bplist00` without `lnch`), 2 LocalizedString, 4 strings, 16 arrays; changed: `BundleIDBinding`, `BundleNameBinding`, `ActivityTypeBinding`. No Claim/Type/Container were added (the claims array 500 is empty for Calculator, the volume's Container existed). The Bundle record (offsets as in 5.6): `bookmark`, `container` 4, `execPath` `Contents/MacOS/<exe>`, `exactIdentifier` = id with its case, `teamID`/`codeInfoIdentifier` 0 (unsigned copy; signed: "0000000000" and the id), `platform` 1, `registrationTime` = now (CFAbsoluteTime), `version` = CFBundleVersion as 4 x u64 (major, minor, patch, 0), `execSDKVersion` (26,7,2,0), `bundleName`, `displayName`, `localizedShortDisplayName`/`localizedDisplayName` = LocalizedString ids (5.14), `infoDictionary`, `entitlements` 0, `containingDirectoryClass` (136) 0xff for /tmp (1 for /System/Applications), `_clas` 2, `_bundleFlags` 0x82 | tmp bit, `_plistContentFlags` 0x10000, `_itemFlags` 0x10008e, `_hfsType` 'APPL' (u32 0x4150504c), `_hfsCreator` 0x3f3f3f3f ('????'), `_inoBundle`/`_inoExec` = file ids (no 0x0fffffff high word for the Data volume), `_mtime` = `_executablemtime` = bundle mtime, `minSystemVersion` (26,x), `ownerUID` 501 (280), `sequenceNumber` (320) = the new database sequence (= the Bundle unit id in both observed cases), `identifier` lower case, `counterpartIdentifiers`/`equivalentBundleIdentifiers`/`claims`/`plugins`/`bgPermittedIDs` = empty arrays (`00000020`), `filename` lower case, `bundleVersion`, `shortVersionString`, `primaryIconName`, `iconsDict`, `iconFileNames` (`Contents/Resources/<icon>.icns`), `activityTypes` (532) = `NOTIFICATION#:<bundle id>` + `pv-<hash>` (+ NSUserActivityTypes), `revision` 0xb, `recordModificationTime` = registration time, `machOUUIDs` = array of the UUID strings of the slices. Bindings: `BundleIDBinding[lower id]`, `BundleNameBinding[lower file name]` and `BundleNameBinding[CFBundleName]` (case kept; the key's array lists every bundle with that name), `ActivityTypeBinding[each activity type]`. Header: `CacheSequenceNum` += 4 per registration (observed 2148 -> 2152 for one, 2796 -> 2800 -> 2804 for later ones). `lsapp.py` writes this set except machOUUIDs, LocalizedStrings, entitlements and the signing fields.

### 5.15 Container record (24 bytes) and what the client does with it **[decompiled: LaunchServices `_LSContainerCheckState`, `_LSContainerDataNeedsUpdate`, `_LSUpdateContainerState`, `_LSContainerAddWithNode`, `_LSCreateContainerNodesAndFlagsForNode`, `-[FSNode getVolumeIdentifier:error:]`; verified on the Mac VM with `lsd` of ours, `probes`: lsquery with modifydb served]**

```
+0  u16 flags      0x0002 node is the root volume (rootVolumeNode)   0x0040 node is the preboot volume (prebootVolumeNode)
                   0x0010 set for both of the above (0x12 / 0x50)   0x0008 translocated mount point (and the flag byte of __LSIsNodeTranslocatedMountPoint)
                   0x0004 volume is on a disk image   0x0001 isOnLocalVolume   0x0020 isOnTimeMachineVolume (only when local and not 0x1b)
+2  i8  state      1 mounted, 0 not yet known, -1 not mounted (_LSContainerStateGetDescription)
+3  u8  0
+4  i32 checked    CFAbsoluteTime of the last state check (Apple: boot time + ~20 s)
+8  u64 volumeID   first 8 bytes (little endian) of the NSData [NSURL getResourceValue:forKey:NSURLVolumeIdentifierKey]; Mac VM: 67 45 64 00 00 00 00 00 = 0x644567 (same for / and /System/Volumes/Data: Foundation resolves "/" through the firmlink to the Data volume; not statfs fsid, not st_dev)
+16 u32 alias      Alias unit (bookmark) of the volume, 0 = none (Apple writes 4)
+20 u32 alias2     second Alias (disk image), 0 = none
```
Apple's record for unit 4: `13 00 01 00 | c42ab430 | 67456400 00000000 | 04000000 | 00000000` = flags 0x13 (root | local | 0x10), state 1, checked = boot + 20 s, volumeID 0x644567, alias 4.

Client rule: `_LSContainerCheckState(db, unit)` reads the record and calls `_LSContainerDataNeedsUpdate`: **update needed iff `state == 0`, or (`flags & 0x28` != 0 and (`checked == 0` is skipped; else `now - checked >= 86400`))**. So a record with state != 0 and flags without 0x08/0x20 is used as is: the client never calls `updateContainerUnit:`. A record with state 0 (our earlier all-zero Container) always needs an update: `_LSUpdateContainerState` asks `_LSDModifyService updateContainerUnit:completionHandler:` (when `hasServer` and not `isServer`), the zero reply keeps state 0, and the client asks again on every lookup (550 calls). If the update runs locally it resolves the volume node (alias, else rootVolumeNode for 0x2 / prebootVolumeNode for 0x40), stores state 1 and `checked = now` (0xff when the node cannot be found). The state is returned to `_LSAliasAndInodeOnContainerMatchesNode`. Registering (`_LSContainerAddWithNode`) finds an existing container by (`flags`, `volumeID`) equality or by `_LSAliasCompareToNode`, otherwise adds a record with state 0 and then marks it mounted.

Minimal rule for pearOS: write the Container with `flags 0x13`, `state 1`, `checked` = now, `volumeID` = the 8 bytes Foundation returns for `NSURLVolumeIdentifierKey` of `/`, aliases 0, and answer `updateContainerUnit:` with the same 24 bytes. Proven: Apple's client on the Mac VM finds Calculator by identifier, by URL and renders the icon recipe against our lsd with modifydb served, 0 `updateContainerUnit` calls (`LaunchServices` `lsd/apps.m LSDContainerRecord`). darwinator must provide what `NSURLVolumeIdentifierKey` is built from (it is computed inside Foundation/CF, the syscalls were not identified: interposing getattrlist/statfs/fsctl showed no call), and `getattrlist`/`statfs` for `/` as Apple's `FSNode` uses them when the update does run (volume UUID `ATTR_VOL_UUID`, local mount flag).

### 5.14 Other record layouts (partial)

- `LocalizedString` (12 bytes) = `u32 array of language codes | u32 array of the localized strings (same order) | u32 0` (Calculator: 'he','ko','pl',... -> 'מחשבון','계산기','Kalkulator'; language codes are mostly immediate ids, `es_419`, `zh_TW` are string units). Fields 108/116 of Bundle point at them.
- `CanonicalString` (16 bytes) = `u32 string id | u32 array | u32 array | u32 0` (the system folder names: 'Volume', 'Saved Searches', ...).
- `Container` (24 bytes): layout and client rule in 5.15.
- `BindingList` = `u32 n` then n x `{u32 class, u32 count, count x u32 values}`; `class` is the **string id of a binding class name** (4 = `com.apple.uniform-type-identifier`, 8 = `public.filename-extension`, 0xc = `com.apple.ostype`, 0x10 = `public.mime-type`, 0x14 = `com.apple.nspboard-type`, 0x18, 0x1c, 0x20 = `public.url-scheme`), the values are string ids (immediate ids included): the extensions / UTIs / schemes a Claim claims (Calculator's claim 0xd00: `[(0x20, [immediate 'calculator'-like id])]`). The lists are decoded exactly (the length of every unit equals 4 + sum(8 + 4 count)).
- `Claim` (44 bytes = 11 u32): `w0` hash/name id (not decoded), `w1` (a string id or 1), `w2` (a language string such as `zh_TW`, or flags), `w3` flags (0x20002 / 0x40002: role mask), **`w4` = the unit id of the Bundle it belongs to**, `w5` BindingList (types the claim is for, other class), `w6`..`w7` (an icon file string `Contents/Resources/MakePDF.icns`), **`w10` = BindingList of what is claimed** (extensions, UTIs, scheme). A bundle's `claims` (500) is an array of Claim ids; `ExtensionBinding`/`UTIBinding`/`URLSchemeBinding`/... arrays contain Claim ids.
- `Type` (68 bytes = 17 u32): `w3` = the UTI string id (`public.bzip2-archive`), `w5` = a parent/conforming UTI string, `w6` PropertyList (the UTTypeSymbolName dictionary...), `w13`/`w14` BindingLists (the tags: extensions / MIME types, and the conforms-to list); the rest not decoded.
- `Service` (44 bytes): `w2` app name string, `w3` service name ('makeNewAppleScript'), `w4` menu title ('Script Editor/Make New AppleScript'), `w8` BindingList; not needed for lookups.
Writing claims/types is NOT needed for the three lookups above; it is needed for "which application opens this file" (U3, next).

## 6. `com.apple.coreservices.launchservicesd` (plain XPC dictionaries)

Full conversation of a minimal AppKit client (`probes/a.m`, `NSApplication sharedApplication` + `finishLaunching`), in `captures/launchservicesd-xpc.txt` **[captured]**. Connection flags 2 (privileged); every request is a dictionary with `command` (int64) and `session` (int64: -2 = "the session of the calling process" in the first messages; replies to 100/410 carry 100001, the user session id; later requests of the same client carry 100728, a number the client derived after check-in, not decoded); replies carry `success` (bool).

| command | request keys | reply | notes |
|---|---|---|---|
| 100 | `clientversion` (u64 277872640 = 0x10900000) | `serverversion` (same), `success` true, `session` int64 100001 | first message; client library version echo |
| 110 | - | `lsinfopage` (xpc shmem, 61440 bytes = 15 pages), `success` | the shared "info page" of the session: layout in 6.3. Clients ask again before most other calls (seen with the Mac daemon too, reason in 6.3) |
| 130 | `asn1`, `asn2` (u64) | `success` false (unknown ASN) | |
| 200 | `wanted` array of key names (`LSSessionID`) | `metainfo` {LSSessionID: int64 100001}, `success` | stub answers `LSCGSSessionID` |
| 300 | - | `success` false while no application is in front | front application |
| 360 | `asn` (u64 = hi<<32 | lo), optional `restrictto` array of keys | `success` false (unknown asn) or `result` dictionary (the keys asked, or the whole record) + `cacheable` bool (true when the whole record was asked) | the record of an application, section 6.1 |
| 410 | `listener` (xpc endpoint), `needsassertions` bool, `clientid` u64, `addasn` array of u64 (first) or `set` array of u64 notification-class ids (512, 513, 561, ...) plus `id` | `id` u64 (10371), `success`, `affectedasns` array, `session` | registers the client's listener endpoint for LS notifications (the same message also carries an NSXPC invocation `registerListenerEndpointWithXPCListenerEndpoint:reply:` with the endpoint in `ool[0]`) |
| 500 | `info` dictionary (below), `deathport` (mach send right) | `success`, `result` dictionary (the check-in record, section 6.1) | application check-in. The earlier stub shape was confirmed |
| 505 | - | `success` false | |
| 510 | `asn`, `info` {key: value to set} (e.g. `LSNotifyApplicationFrontable`, `LSPersistenceSuppressRelaunchAtLogin`, `ApplicationType`) | `success`, `info` = whole record after the change | `ChangeCount` grows by 2 per set |

6.1 Check-in `info` of a plain Mach-O (`500`): `LSDisplayName`, `CFBundleSignature` "????", `LSExecutableFileName`, `CFBundleExecutablePath`, `LSExecutableSDKVersion` "26.5", `LSCheckInTime*` (xpc date), `LSArchitecture` "x86_64", `CFBundlePackageType` "????", `LSDYLDPlatformKey` 1, `Flavor` 3, `ApplicationType` "BackgroundOnly". The reply `result` adds `LSAuditToken` (32 bytes, the audit token), `LSExecutableFilenameLowerCaseKey`, `LSApplicationMemberCoalitionIDKey` (int64), `LSASN` {`com.apple.coreservices.asn.lo` u64, `com.apple.coreservices.asn.hi` u64 0, `com.apple.coreservices.asn` uuid C96172A0-CE74-4D62-AFEF-ECFE4D04D827}, `pid`, `LSApplicationHasRegistered` true, `ChangeCount` int64 (515, +2 per set), `CFBundleExecutablePathDeviceID`, `CFBundleExecutablePathINode`, later `LSApplicationReadyToBeFrontableKey`, `CanBecomeFrontmost`, `Hidden`, `LSApplicationHasSignalledItIsReady`. The ASN as a number is `hi << 32 | lo` (4295013348 = 0x10000b3e4 = 0x100000000 + 430180; the check-in reply shows `lo` 430185 for the same process: the request value `asn` is `hi<<32|lo` of the number the client was given by a previous call, exact relation to `LSASN.lo` not established). **[decompiled: `_LSASNCreateWithPid` = `_LSASNCreate(alloc, 1, pid)`, `_LSGetCurrentApplicationASN` = `_LSASNCreate(0, 0, 2)`]** an ASN with `hi` = 1 is a *pid ASN* (`lo` is a pid, 0xb3e4 = 46052 here), `hi` 0 `lo` 2 means "the current application"; a server must resolve a `hi` = 1 ASN by pid.

### 6.2 Every command a client sends

The numbers are the argument of `createLSMessage(command)` in each LaunchServices function **[decompiled: LaunchServices x86_64, `llvm-objdump` of the `mov $imm, %edi` before each call]**; request/reply keys come from section 6 **[captured]** where seen, otherwise from the decompiled sender **[decompiled]**. A server that wants to be wire-compatible must answer each with at least `success` (bool); a request whose reply does not come keeps the caller waiting.

| command | client function | what it is | keys known |
|---|---|---|---|
| 98 | `handleSessionInformationMessage` block | answer to a session-information message of the server | - |
| 99 | `_LSSetMetaApplicationInformationItem` | set one key of the session meta information | - |
| 100 | `LSClientToServerConnection::setupServerConnection` | connection check-in, once per connection (again after `XPC_ERROR_CONNECTION_INTERRUPTED`) | req `clientversion` u64 0x10900000, `session`; reply `serverversion` **must equal 0x10900000** (else "bad version", the connection is used anyway but the client re-sends 100), `session`, optional `reconnectclient` bool + `reconnectoptions` dict + `reconnectflags` u64 |
| 110 | `LSSharedMemoryPage::CopyForSessionID` | the info page, 6.3 | reply `success`, `lsinfopage` (shmem) |
| 120 | `_LSAllocatePSN` | allocate a process serial number | - |
| 130 | `_LSCompareASNsLong` | are two ASNs the same application | `asn1`, `asn2` u64 -> `success` |
| 140 | `_LSSetApplicationLaunchServicesServerConnectionStatus` | tell the server the client's connection status flags | - |
| 200 / 210 | `_LSCopyMetaApplicationInformation` / `_LSSetMetaApplicationInformation` | session meta information (`LSSessionID`, `LSCGSSessionID`, ...) | 200: `wanted` array -> `metainfo` dict |
| 300 | `_LSCopyFrontApplication` | front application | -> `success` false when none, else an ASN |
| 310 | `CopyApplicationArray` | list of applications | - |
| 320 | `_LSCopyApplicationArrayInFrontToBackOrder` | applications front to back | - |
| 330 / 331 | `_LSCopyMatchingApplications` / `_LSCopyApplicationsWithPath` | applications matching a dictionary / a path (the client first tries the page: pid and `CFBundleIdentifier` matches, 6.3) | - |
| 360 | `_LSCopyApplicationInformation` | record of one application (only when the page and the local cache have nothing) | `asn`, `restrictto` -> `result`, `cacheable` |
| 370 / 380 | `_LSCopyLaunchModifiers` / `_LSPostLaunchModifiers` | launch modifiers of an application | - |
| 410 / 420 | `LSNotificationReceiver::modify` / `_LSUnscheduleNotificationFunction` | register / drop a notification listener | 410: `listener` endpoint, `set`/`addasn`, `id` |
| 450 | `_LSSendNotification` | the client sends a notification to the server | - |
| 500 | `_LSApplicationCheckIn`, `_LSReCheckinApplication` | application check-in | `info`, `deathport` -> `result` with `LSASN` (6.1) |
| 501 | `_LSApplicationCheckInProxy` | check-in for another process | - |
| 505 | `_LSApplicationCheckIn` with a dictionary that only holds `pid` | "is this pid checked in?" | -> `result` |
| 510 | `_LSSetApplicationInformation` | set keys of a record | `asn`, `info` -> `info` |
| 520 | `_LSSignalApplicationReady` | the application is ready | - |
| 590 | `_LSApplicationQuitting` | the application is quitting | - |
| 595 / 596 | `_LSCreateCSUIConnectionForLaunching` / `_LSRegisterNamedXPCConnection` | named connections | - |
| 597 | `_LSReCheckinApplication` | re-check-in after a server restart | - |
| 598 / 599 | `_LSClientSideRegisterAsReconnectionHelper` blocks | reconnection helper | - |
| 600 | `_CASNotifyServerSideAboutLaunchedApplication` | a launcher tells the server about a launched application | - |
| 610 | `_LSWaitForApplicationCheckIn` | wait for an application to check in | - |
| 700 | `_LSCopyApplicationDeathInformationForPid` | death information of a pid | - |
| 900 | `_LSPassDownCurrentEventState` | current event state | - |
| 910 | `_LSSetFrontApplicationLong(WithCompletion)`, `_LSRequestProcessBecomeFrontmost` | make an application front | - |
| 920 | `_LSOrderApplications` | reorder applications | - |
| 1000-1030 | `_LSGetCurrentActivationToken`, `_LSDonateActivationToken`, `_LSIsActivationTokenValidForTarget`, `_LSInvalidateActivationToken` | activation tokens | - |

A message from the server with `shuttingdown` true makes the client set its connection status to 0x80000000 and stop connecting **[decompiled: event handler of `setupServerConnection`]**.

### 6.3 `launchservicesd`: the info page (`lsinfopage`)

**[decompiled: LaunchServices `LSSharedMemoryPage::LSSharedMemoryPage(LSSessionID)`, `CopyForSessionID`, `GetApplicationInformation`, `GetApplicationInformationForPid`, `GetIndexedApplicationInformation`, `GetIndexedApplicationAdditionalInformation`, `SetApplicationInformation`, every `_LSSharedMemoryGet*`; `copyMatchingApplicationsBasedOnSharedMemory`] [captured: `probes/ip.c` + `infopage.py` on the Mac VM, `captures/infopage.txt`]**

What the client checks when it gets the page (`CopyForSessionID`): the mapped length (`xpc_shmem_map`) must be >= 0xe460, the word at +0 must be **0x104** and the word at +4 must be >= 0xe460. Otherwise it logs "Shared memory page version %d didn't match expected one ...", unmaps it and has **no page** (it asks again with 110 at the next use; an all-zero page is in this case). A page with a valid header is kept in a per-session cache and remapped with `vm_remap(copy = 0)`, so **the server writes the page in place and clients read the changes live**; the page has to be one object for the whole session. A page whose `metaInformationFlags` (+0x74) is negative is "destroyed": the client drops it. While the lock count (+0x0c) is not 0 the readers return nothing.

Header (all little-endian 32-bit words; the daemon allocates `round_page(0xe460)` = 0xf000 bytes, zeroes it and sets what the "init" column says):

| offset | name (from the getter `_LSSharedMemoryGet<Name>`) | init | observed on the Mac |
|---|---|---|---|
| 0x00 | Version | 0x104 | 0x104 |
| 0x04 | Size | 0xf000 | 0xf000 |
| 0x08 | SessionID | the session | 100001 |
| 0x0c | LockCount (writers increment it around a record write) | 0 | 0 |
| 0x10 | DebugLevel | 0 | 0 |
| 0x14 | ChangeCount | 0 | 0 |
| 0x20 | FrontApplicationASNSeed | 100 | +1 per change of front application |
| 0x24 | MenuBarOwnerASNSeed | 100 | +1 per change of menu bar owner |
| 0x28 | ApplicationListSeed | 100 | +1 per application added, more on removal |
| 0x2c | PendingApplicationListSeed | 100 | 100 |
| 0x30 | VisibleApplicationListSeed | 100 | changes with launch/quit |
| 0x34 | ApplicationInformationSeed | 100 | +4 at a check-in, +0x30 at an app launch |
| 0x50 | FrontASNLow | 0 | low half of the front ASN (Terminal, then Calculator) |
| 0x54 | MenuBarOwnerASNLow | 0 | same as front in the captures |
| 0x58 | SystemProcessASNLow | 0 | loginwindow |
| 0x5c | SessionLauncherASNLow | 0 | 0 |
| 0x60 | LaunchProgressFlags | 0 | 0 |
| 0x64 | LaunchProgressUserActivityCount | 0 | 0 |
| 0x68 | CGSSessionID | 0 | 0x101 (the WindowServer session) |
| 0x6c | NextAppToBringForwardASNLow | 0 | 0 |
| 0x70 | SystemUIPresentationMode | 0 | 0 |
| 0x74 | MetaInformationFlags (negative = page destroyed) | 0 | 0 |
| 0x78 | SystemUIPresentationOptions | 0 | 0 |
| 0x7c | ExpectedFrontApplicationASNLow | 0 | 0 |
| 0x88 | ApplicationListCount (`IsApplicationInformationUsable` = count < 0x32b) | 0 | 43 |
| 0x8c | capacity | 0x32a | 0x32a |

Records: `0x90 + i * 0x48`, i < min(count, 0x32a) (0x90 + 0x32a * 0x48 = 0xe460, the minimum size). Removing an application compacts the array (the count drops, later records move down).

| offset | type | meaning | evidence |
|---|---|---|---|
| +0x00 | u32 | ASN low half (the key of all lookups) | [decompiled] lookups by ASN; [captured] = `LSASN.lo`, e.g. 0x89089 for the probe whose 500 reply had lo 561289 |
| +0x04 | u32 | `ChangeCount` of the record (the writer sets it to 0 first and writes it last) | [decompiled] `SetApplicationInformation`; [captured] 0x202 = 514 = `ChangeCount` of the 500 reply |
| +0x08 | u32 | flags; < 0 (sign bit) = slot not valid; bit 0x2 = skipped by the pid/bundle-id matchers (application going away) | [decompiled]; [captured] 0x80 = a checked-in process with no bundle (the probe), 0x40c0 Foreground apps (Terminal, Calculator), 0x44c0 Finder, 0x64e0/0x44e0/0x44d0 UIElement, 0x4090/0x4490/0x40a0 BackgroundOnly: the other bits are not decoded [inferred: they follow ApplicationType, readiness and visibility] |
| +0x0c | u16 | position in the front-to-back order of visible applications (1 = front, 0 = not in the list) | [captured] Calculator 1, Terminal 1 -> 2, Finder 2 -> 3, back after quit |
| +0x10 | i32 | pid | [decompiled] `GetApplicationInformationForPid`; [captured] |
| +0x14 | i32 | pid version (`audit_token_to_pidversion` of the check-in) | [decompiled] `_LSSharedMemorySetApplicationInformationFromToken` |
| +0x18 | u64 | `CFHash(CFBundleIdentifier)` (0 if none; a hash of 0 is stored as 1) | [decompiled] `copyMatchingApplicationsBasedOnSharedMemory`; [captured] 0x405fb37c70e1a673 = CFHash("com.apple.loginwindow") |
| +0x20 | u64 | `CFHash` of the executable file name (case kept) | [captured] 0xdb610cddec279fbc = CFHash("loginwindow"), CFHash("ViewBridgeAuxiliary") |
| +0x28 | i32 | device of the bundle (`CFBundleExecutablePathDeviceID` for a bare executable) | [captured] 0x100000a = `stat -f %d` of loginwindow.app |
| +0x30 | u64 | inode of the bundle directory | [captured] 0x0fffffff00037386 = `stat -f %i` of /System/Library/CoreServices/loginwindow.app |
| +0x38 | i32 | device of the executable | [captured] |
| +0x40 | u64 | inode of the executable (`CFBundleExecutablePathINode`) | [captured] 0x0fffffff0003738b = inode of .../Contents/MacOS/loginwindow; for a bare executable +0x28/+0x30 = +0x38/+0x40 |

ASN low halves given by the Mac daemon are `k * 0x1001` (k a counter: 0x5005 loginwindow, 0x1c01c Terminal, 0x89089 ...) **[captured]**; the client only needs them to be unique and equal to `LSASN.lo` of the record.

When the daemon updates the page **[captured]**: at a check-in (500) it adds a record (count + 1, ApplicationListSeed + 1, VisibleApplicationListSeed + 1, ApplicationInformationSeed + 4); when an application becomes front it sets FrontASNLow and MenuBarOwnerASNLow, bumps the two seeds and rewrites the +0x0c order of every visible record; at a quit it removes the record and bumps the seeds again. The client side reads seeds to invalidate its caches (`_LSGetFrontApplicationSeed`, `_LSGetApplicationListSeed`, ... log "frontApplicationSeed=%d") and stops an iteration when ApplicationListSeed changes under it.

Why the client asks for 110 so often: `CopyForSessionID` caches the page under the session number written at +8, but the callers ask for session -2 ("the session of this process", `NormalizeLSSessionID` keeps -2 unless the session attribute bit 0x10 is set), so most lookups miss the cache and send 110 again **[decompiled]**; the same pattern is seen with the real daemon (`captures/launchservicesd-xpc.txt`).

### 6.4 The Dock abort "unable to get application ASN from launchservicesd" (HIServices `_RegisterApplication`)

**[decompiled: HIServices `____RegisterApplication_block_invoke`, LaunchServices `_LSApplicationCheckIn`, `LSClientToServerConnection::setupServerConnection` and its event handler, `clientIsAllowedToConnect`, `IsLSServerConnected`] [captured: Mac VM, `probes/fk.c`]**

1. `_RegisterApplication` calls `_LSApplicationCheckIn(-2, info)`. If that returns NULL it tries `_LSCopyApplicationInformation(-2, ASN{hi 1, lo pid})`. If both fail the ASN low half (`DAT_7ff8438121a4`) stays 0, and when the application requires an ASN (the Dock does; a plain AppKit tool does not) and `sysctlbyname("hw.willshutdown")` does not say "shutting down", it aborts with that message.
2. `_LSApplicationCheckIn` returns NULL **without sending 500** when: the session normalizes to 0 or `info` is NULL; `clientIsAllowedToConnect()` is false (`kern.willshutdown` sysctl readable and not 0, connection status flags bit 1/2 set, e.g. after a server message with `shuttingdown`); or `LSClientToServerConnection` has no xpc connection: log "rdar://problem/28724618 Unable to register with launchservicsed, couldn't create connection object."
3. The xpc connection to launchservicesd is created once (`dispatch_once`) and kept in a global. On `XPC_ERROR_CONNECTION_INTERRUPTED` the client drops its cached pages and sends 100 again on the next use (the connection survives). On **`XPC_ERROR_CONNECTION_INVALID`** it sets the global to NULL ("Got an XPC_ERROR_INVALID on our server connection, so failing.", crash string "XPC_ERROR_CONNECTION_INVALID from launchservicesd") and **never creates it again**: every later LaunchServices call that needs the server fails at once and sends nothing.
4. The content of the info page is **not** what stops the 500: Apple's AppKit client (probes/a.m) against `lsd-stub` with an all-zero page, on the Mac VM through `__LSXPCSERVICENAME`, sends 505 and 500 and checks in normally (the zero page is only rejected and asked for again).
5. Reproduction of the pearOS signature on the Mac VM: `probes/fk.c` answers 100 and two 110 (zero page) and then makes its service disappear (it boots its own launchd job out). The client logs `XPC_ERROR_INVALID` then "couldn't create connection object", and the server never sees 500 - the same `100, 110, 110, (abort)` that the Dock shows on pearOS. When the server only cancels the peer connection (INTERRUPTED), the client reconnects with 100 and checks in.

So on pearOS the Dock's connection to `lsd-stub` became **invalid** after the second 110: the service went away for the client (stub process died or its receive right/launchd registration was lost under darwinator) or darwinator's libxpc delivered `XPC_ERROR_CONNECTION_INVALID` for another reason. To confirm on pearOS: Dock.out (with `OS_ACTIVITY_DT_MODE=YES`) should show "Got an XPC_ERROR_INVALID on our server connection" or "couldn't create connection object"; check whether `lsd-stub` is still alive after the second 110. A valid page (6.3) is still needed for correct behaviour after check-in (front application, application lists, pid and bundle-id lookups without 360).

## 7. Minimal compatible subset for the Dock

What blocks the pearOS Dock now: the first call of the first LS user (IconServices `ISGenerationRequest`, or any `LSRecord` use) is the **synchronous** `getServerStoreNonBlocking...` on `com.apple.lsd.mapdb`; if the server cannot answer with a valid store the client waits or the connection is dropped (lsd-objc README).

Needed, in this order:
1. `com.apple.lsd.mapdb` (NSXPC, options 0): `getServerStoreNonBlocking...` -> exactly the reply of section 3 (`_CSStore{XPCRepresentation:0}`, `FSNode` of the store file, nil, 0, nil, with `ool[0]` = the file as an xpc data object). Everything else of `_LSDReadProtocol` may answer with the values of 2.1 (status 256, empty preferences, `LSSettingsStoreConfiguration` with an endpoint, developer dir, 105/47 element sets, errors -50/-54 for the entitled calls); `getSystemContentStore...` -> the same shape with the system store (or the same store).
2. The store: a valid container (5.1/5.2) with the 33 tables, the DB header (5.3) whose **UUID is stable and sequence bumped on every change**, the 8 binding class-name strings and the string cache (5.7/5.8): without them the client discards the file and builds its own. Records: one Bundle per application (5.12: `_clas` 2, identifier + binding, Alias of the path, `_mtime`, `revision` 0xb, Container of the volume, `iconsDict` in the `CFBundlePrimaryIcon` form; not under /tmp unless it is a test) is what Apple's client needs to find the application by identifier and by URL and to render its icon from the record (proven on the Mac VM, `lsapp.py`). The *icon pixels* still come from the bundle (IconServices renders them); the record supplies identity and the icon names.
3. `com.apple.lsd.modifydb`: `registerItemInfo:...` must return `(YES, unit, nil, NO, nil)` and update the store (read the bundle, write the records, bump the sequence), and the next `getServerStore...` must return the new store; `unregisterBundleUnit`, `registerContainerURL` (reply `I` = container unit) and `setDatabaseIsSeeded` as simple success. The remaining methods can reply success/nil.
4. `com.apple.coreservices.launchservicesd`: 100, 110, 130, 200, 300, 360, 410, 500, 505, 510 as in section 6, with a valid info page (6.3: version 0x104, one page per session written in place, a record per check-in); the service must stay valid for the client for the whole session: an `XPC_ERROR_CONNECTION_INVALID` makes LaunchServices give up for ever and the Dock aborts (6.4).
5. Not needed for startup: `open`, `openurl`, `advertisingidentifiers`, `trustedsignatures`, `encryption`, `dissemination`, `plugin`, `diagnostics`, `extensions`, `personaobserver`, `translocation`.

On the Mac VM a store written by our tools is accepted by Apple's Launch Services client (5.7, 5.12). **To do in `LaunchServices/store` (C writer of our lsd)**: add the 8 class-name strings and the `<string>` cache (5.7/5.8) and the Bundle records of `lsapp.py` (5.12); our lsd serves the empty store without them, which the client rejects (it then builds a database in its own process, as the Dock log showed). pearOS itself was not tested in this round.

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
| `lsbuild.py` | store builder: strings (immediate ids, cache), arrays, compacted property lists, Alias/Container/Bundle units, binding hash tables, load an existing store (`LSDB.from_store`) and add to it, sequence bump |
| `lsapp.py` | `python3 lsapp.py [--base STORE] OUT APP.app ...`: registers application bundles like lsd does (5.13) |
| `bookmark.py` | byte-exact reader/writer of the CFURL bookmark data of the Alias table |
| `extract_common_strings.py` | writes `plist_common_strings.txt` (257 strings of the plist compaction) from the user's LaunchServices binary (the list is not kept in the repository) |
| `probes/lsf.m`, `probes/q.m`, `probes/b.m` | serve a store file as `com.apple.lsd.mapdb`; lookups by identifier / URL; one binding lookup with `_CSStringBindingFindStringAndBindings` |
| `lsrecord.py`, `extract_enc.py` | decode a record from the named ObjC struct encoding taken from the user's LaunchServices binary |
| `probes/ip.c` | client: 100 + (500) + 110 to launchservicesd (or `__LSXPCSERVICENAME`), maps `lsinfopage` and writes it to a file |
| `infopage.py` | decoder of the info page (6.3), joins `lsappinfo list` names |
| `probes/fk.c` | fake launchservicesd that invalidates the client connection after N 110: reproduces the Dock ASN abort (6.4) |
| `captures/` | decoded wire captures and the protocol dump; `infopage.txt` (pages across check-in, launch, quit), `infopage-checkin500.txt` |

## 9. Unknowns and questions

- U1: client use of `FSNode` file vs `XPCRepresentation` data; meaning of the endpoint (reply 2) and BOOL (reply 3) of `getServerStoreNonBlocking`, `getServerStatus` = 256. `fcap` did not see `open`/`mmap` (the client maps through a path not interposed).
- U2 (answered): Apple's client accepts a store we wrote when 5.7 holds; header flag `+0x28` and "seeded" state were not needed.
- U3 (partly answered): binding hash (5.9), arrays (5.9), strings (5.8), plist compaction (5.10), bookmark (5.11), BindingList/LocalizedString/CanonicalString (5.14) decoded; open: field meaning of `Claim` (w0..w9), `Type` (w0..w17), `Service`, `Plugin`, `ExtensionPoint`, `Container`, the `Bundle` flag bits (`_bundleFlags`, `_itemFlags`, `_plistContentFlags`, `moreFlags`), `BindableKeyMap`, `<dictionary>`; the 63 extra cache entries.
- U4: protocols of `diagnostics`, `extensions`, `personaobserver`, `openurl`, `security.translocation`; real `setClasses:` of the non-`_LSDService` interfaces; connection types 2/4/5/6/9/10/11/13/14.
- U5 (answered, 6.3): layout of `lsinfopage`. Open: the meaning of most bits of the record flags (+0x08) and every server-side update beyond the observed ones (needs the launchservicesd binary).
- U6 (answered for the three lookups, 5.12): which Bundle fields Apple's client needs for identifier lookup, URL lookup and ISBundleIcon. Open: what the *Dock* reads beyond that (display names, claims for "open with"); server side of registration beyond the observed diff (5.13): reading code signatures (teamID, cdhashes), entitlements, claims/types from CFBundleDocumentTypes / UTExportedTypeDeclarations.
- U7: LSD behaviour with the entitlement checks of `modifydb` for unentitled callers (the probes were not refused for `registerItemInfo`: a plain unsigned user binary registered an app).
- Q1 (owner): Disabling SIP on the Mac VM would allow attaching lldb to `lsd` (server side of registration, `getServerStore`) and reading the `.dv` directory; not needed so far. Say if you want it.

- U8 (answered, 5.15): Container layout and client rule. Open: the exact origin of the `NSURLVolumeIdentifierKey` value 0x644567 inside CF (no syscall seen by interposition); on pearOS it is whatever the Apple Foundation returns on darwinator.
- U9: why `_itemFlags` bit 0x4 (set by lsd, 0x10008e) made `bundleRecordWithBundleIdentifier:` fail for our application in a user directory while the system Calculator with the same word is found; 0x10008a works.

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

End-to-end proof (5.12), Mac VM, all files in /tmp or ~/isw (nothing of Apple's is kept in the repository; `plist_common_strings.txt` is produced from the Mac's own LaunchServices image: `ipsw dyld extract <dsc> LaunchServices -o DIR; python3 extract_common_strings.py DIR/LaunchServices > tools/launchservices/plist_common_strings.txt`):
```
clang -fobjc-arc -framework Foundation lsf.m -o lsf; clang -fobjc-arc -framework Foundation -framework CoreServices q.m -o q     # probes/
# launchd job com.pearos.t.lsf: ProgramArguments lsf, MachServices com.pearos.t.lsf, env LSF_NAME=com.pearos.t.lsf LSF_STORE=/tmp/lsf/store.csstore
cp -R /System/Applications/Calculator.app ~/lsq/Calc.app
python3 lsapp.py [--base real.csstore] /tmp/lsf/store.csstore ~/lsq/Calc.app           # the store is re-read on every request
env DYLD_INSERT_LIBRARIES=redirect.dylib IS_REDIRECT=com.apple.lsd.mapdb=com.pearos.t.lsf ./q bid com.apple.calculator     # found, URL = ~/lsq/Calc.app
env DYLD_INSERT_LIBRARIES=redirect.dylib IS_REDIRECT=com.apple.lsd.mapdb=com.pearos.t.lsf ./q url ~/lsq/Calc.app
env DYLD_INSERT_LIBRARIES=redirect.dylib IS_REDIRECT=com.apple.lsd.mapdb=com.pearos.t.lsf ./gen ~/lsq/Calc.app 128 out.png   # icon from the record
log show --last 1m --info --debug --predicate 'process == "q"'                         # "Building database from scratch in this client!" = store rejected
```
