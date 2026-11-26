# IconServices wire protocol and store (macOS 26.7.2, build xnu-12377.161.15.701.48, x86_64)

Goal: enough to write a wire-compatible `iconservicesagent` (LaunchAgent, Mach service `com.apple.iconservices`) and `iconservicesd` (LaunchDaemon, Mach service `com.apple.iconservices.store`). Method: decompile with REA/Ghidra, runtime introspection of the real frameworks on the Mac VM, lldb captures of a real client. No Apple code or binaries are in this repository; the tools used are in `tools/iconservices/`.

Status of each claim is marked: **[captured]** (seen on the wire / on disk on the Mac VM), **[runtime]** (read from the live ObjC runtime), **[decompiled]** (REA/Ghidra, function address given, image base `0x7ff8...` = x86_64 dyld cache address of IconServices in the 26.7.2 cache), **[header]** (class dump), **[inferred]** (no direct observation; reasoning given).

Evidence sources
- Thin slices of the two executables: `iconservicesagent`, `iconservicesd` (REA, class dump with `ipsw class-dump`).
- `IconServices.framework` extracted from the dyld shared cache (`ipsw dyld extract`); REA addresses below are in this image. The extracted image has no selector strings (they live in other subcaches), so decompiled code shows `DAT_...` for selectors; behaviour was therefore confirmed dynamically.
- Mac VM probes: `tools/iconservices/probes/` (`p.m` protocol/interface dump, `q.m` coder key logger, `r2.m` client, `cap.c` + `l7.txt` lldb capture, `s.m` store/defaults dump). Decoders: `tools/iconservices/bp17.py` (NSXPC root archive), `tools/iconservices/idx.py` (store.index).

## 1. Topology

```
 client process (Dock, Finder, ...)                       Mac: launchd
  IconServices.framework (ISIcon, ISIconManager ...)
      |  NSXPC  "com.apple.iconservices"  (options 0)  ---> iconservicesagent (per user, gui domain)   IconCacheService
      |                                                          |  NSXPC "com.apple.iconservices.store" (privileged)
      |  NSXPC  "com.apple.iconservices.store" (options 2) ---> iconservicesd (_iconservices, system)   StoreService
      |
      +-- reads files directly (no IPC):
            <per-user cache dir>/com.apple.iconservices/store.index         (mmap, read)
            /Library/Caches/com.apple.iconservices.store/<UUID>.isdata      (mmap, read)
```

- Agent job `com.apple.iconservices.iconservicesagent`: LaunchAgent, `MachServices{com.apple.iconservices}`, `RunAtLoad=false`, `EnablePressuredExit`, `EnableTransactions`, `POSIXSpawnType=Adaptive` **[captured: plist on the VM]**. A second instance with argument `runAsRoot` was running as root (pid 804, started by a job not identified, see unknowns).
- Daemon job `com.apple.iconservices.iconservicesd`: LaunchDaemon, `UserName=_iconservices`, `MachServices{com.apple.iconservices.store}`, `RunAtLoad=true`, `LaunchEvents com.apple.notifyd.matching`: `com.apple.iconservicesd.clearCache.immediately`, `com.apple.system.lowdiskspace.system`, `com.apple.system.verylowdiskspace.system` **[captured]**.
- Both executables are plain `NSXPCListener`/`NSXPCInterface` services (classes `IconCacheService` and `StoreService` are the listener delegates **[header]**). Only the client -> agent, client -> daemon and agent -> daemon directions exist; the services export their protocol and have no remote (callback) protocol: the interfaces below have no reverse interface set **[runtime]**.
- Link lists: agent links `RenderBox`, `IconRendering`, `SkyLight`, `Metal`, `QuartzCore`, `IOSurface`, `CoreUI`, `IconFoundation`, `IconServices`, `libbsm` (audit token); daemon links only `CoreServices`, `IconServices`, `Foundation`, `libbsm` **[captured: otool -L]**. IconServices.framework re-exports `IconFoundation` and weak-links `IconRendering` **[captured: dyld_info]**.

## 2. Protocols (full type encodings)

Both protocols were read from the live runtime (`protocol_copyMethodDescriptionList` + `_protocol_getMethodTypeEncoding`) and the allowed classes with `-[NSXPCInterface classesForSelector:argumentIndex:ofReply:]` after calling `+[NSXPCInterface _IS_iconCacheServiceInterface]` (decompiled at `0x7ff814aa1e52`) **[runtime]**. Probe: `probes/p.m`.

### 2.1 `ISIconCacheServiceProtocol` (client -> agent, Mach service `com.apple.iconservices`)

| selector | type | extended type | arg classes | reply classes |
|---|---|---|---|---|
| `generateImageWithRequest:reply:` | `v32@0:8@16@?24` | `v32@0:8@"ISGenerationRequest"16@?<v@?@"ISGenerationResponse">24` | arg0 `{ISGenerationRequest}` | reply0 `{ISGenerationResponse}` |
| `clearAllCachedItemsWithReply:` | `v24@0:8@?16` | `v24@0:8@?<v@?c@"NSError">16` | none | reply0 BOOL, reply1 `{NSError}` |
| `fetchCacheConfigurationWithReply:` | `v24@0:8@?16` | `v24@0:8@?<v@?@"ISIconCacheConfiguration">16` | none | reply0 `{ISIconCacheConfiguration}` |

Only these three are in the protocol. `IconCacheService` also has `clearCachedItemsForBundeID:reply:` (typo is Apple's) and `generateStoreUnitWithRequest:validationToken:` but they are not part of the exported protocol (not reachable by a client) **[header, runtime]**. Other selectors seen in the agent (`registerRecordIdentifiers:asSourceForUnit:`, `registerTintColor:forUnit:` on `ISMutableIconCache`; `addData:forUUID:`, `removeDataForUUID:`, `removeUnitForUUID:` on `ISStoreMapTable`/`ISStore`) are in-process calls, not wire calls **[header]**.

Replies have the class sets above; the interface sets no further `setClasses:` (the nested classes are validated by the `initWithCoder:` of each class with `decodeObjectOfClass:forKey:`).

### 2.2 `ISStoreServiceProtocol` (agent -> daemon and client -> daemon, Mach service `com.apple.iconservices.store`)

| selector | type | extended type |
|---|---|---|
| `addData:withUUID:domain:completion:` | `v48@0:8@16@24@32@?40` | `v48@0:8@"NSData"16@"NSUUID"24@"NSString"32@?<v@?c>40` |
| `fetchCachePathForDomain:completion:` | `v32@0:8@16@?24` | `v32@0:8@"NSString"16@?<v@?@"NSString"@"NSString">24` |
| `removeItemWithUUID:domain:completion:` | `v40@0:8@16@24@?32` | `v40@0:8@"NSUUID"16@"NSString"24@?<v@?c>32` |

Argument classes are the single class named in the extended encoding (NSData, NSUUID, NSString); replies: `fetchCachePathForDomain` returns two `NSString` (path, sandbox extension), the other two return a BOOL. (The interface was built here with `+interfaceWithProtocol:`, which infers the sets from the extended types; the real daemon's `setClasses:` calls in `StoreService` were not decompiled. Unknown U7.)

Client-side wrappers (category `NSXPCConnection(ISStore)`): `_ISStore_addData:withUUID:domain:completion:` (`0x7ff814aa990e`), `_ISStore_removeItemWithUUID:domain:completion:` (`0x7ff814aa9ad1`), `_ISStore_fetchCachePathForDomain:error:` (`0x7ff814a86650`, synchronous) **[decompiled/header]**. `ISStore addUnitWithData:` (`0x7ff814ac5862`) and `removeUnitForUUID:` (`0x7ff814ac5b91`) call them.

## 3. NSXPC message envelope (what is actually on the Mach/XPC wire)

Captured with lldb breakpoints on `xpc_connection_send_message_with_reply[_sync]` and `-[NSXPCConnection _decodeAndInvokeReplyBlockWithEvent:sequence:replyInfo:]`, a helper dylib (`cap.c`) dumping the XPC dictionary **[captured]**.

Request (client -> service), an `xpc_dictionary` with exactly these keys:

| key | type | value |
|---|---|---|
| `f` | uint64 | `33` (0x21) |
| `root` | data | archive of the invocation, format `bplist17` (section 3.1) |
| `proxynum` | uint64 | `1` (the exported root object) |
| `replysig` | string | method signature of the reply block, e.g. `v16@?0@"ISGenerationResponse"8` (extended encoding of the block argument) |
| `sequence` | uint64 | 1, 2, ... per connection, each invocation with a reply increments it |

Reply (service -> client): dictionary with `root` (data, bplist17) and, when the reply contains an `xpc_object` (here: shared memory), `ool` (array of xpc objects, index = the integer stored in the archive). Connection event handler also receives reply messages without `sequence` (the NSXPC layer matches the reply by the connection's reply handler, not by a key).

Mach service connections, as created by `-[NSXPCConnection initWithMachServiceName:options:]` **[captured: lldb on `xpc_connection_create_mach_service`]**:
- `com.apple.iconservices` flags `0` (agent; from `-[ISIconManager _init]`, `0x?` bt frame `+218`).
- `com.apple.iconservices.store` flags `2` = `XPC_CONNECTION_MACH_SERVICE_PRIVILEGED` (from `-[ISStore init]` `+140`).
Remote object interface = `_IS_iconCacheServiceInterface` / `ISStoreServiceProtocol`; no exported interface.

### 3.1 `bplist17` root archive (decoded from captures)

`tools/iconservices/bp17.py` decodes every captured `root` blob completely (consumed == length for all 6 messages). Format as derived from the samples (not from Foundation source; unknown U1 is whether more tags exist):

```
file   = "bplist17" object
object tags (first byte):
  a0 u64le        array, u64 = absolute offset of the LAST byte of the array (inclusive)
  d0 u64le        dictionary, same end convention, items = key,value,key,value ...
  e0              nil
  c0 / c1         false / true
  1n <n bytes>    unsigned integer, n = 1,2,4,8 little endian  (11 00 = 0, 12 34 08 = 0x0834)
  22 <f32> / 23 <f64>   float / double (little endian)
  7n <n bytes>    ASCII string, n includes the trailing NUL (n < 15); 7f 1m <m bytes> = long form (length as 1n integer)
  6n / 6f         UTF-16LE string, n = number of UTF-16 units (no NUL); NSString values are sent this way, keys and class names as 7n
  4n / 4f         data, n bytes
  8n <n bytes>    back-reference: absolute file offset of an earlier identical ASCII string (string interning)
```
Top level of every message is an array of three items: `[ selector-string-or-nil, method-type-string, [ argument objects... ] ]`. Requests: selector = `generateImageWithRequest:reply:` and type = `v32@0:8@16@?24` (the compact type, not the extended one); the block argument is sent as `nil` (`e0`) in the argument array. Replies: selector nil, type = block type with compact encoding (`v@?@`, `v@?@@`), arguments = reply arguments. Objects are dictionaries with a `$class` key whose value is the class name (ASCII) and then one key per `encode...:forKey:`; sub-objects (NSURL, NSUUID) are dictionaries too (`$class` is then a back-reference). Strings are interned: the 2nd and later occurrences of `$class`, `NSUUID`, `NS.uuidbytes`... are `81 <off>` or `82 <off16>` references to the first occurrence.

Decoded messages (full dumps; paths from the VM):

```
SEND fetchCacheConfigurationWithReply:   (sync, sequence 1)
 root[77]:  [ "fetchCacheConfigurationWithReply:", "v24@0:8@?16", [ nil ] ]
 replysig = v16@?0@"ISIconCacheConfiguration"8

REPLY (872 bytes)
 [ nil, "v@?@", [ { $class: "ISIconCacheConfiguration",
     url: { $class:"NSURL", NS.base: nil,
            NS.relative: u16 "file:///var/folders/qw/<id>/C/com.apple.iconservicesagent//../com.apple.iconservices/" },
     sandboxExtension: u16 "<sandbox extension token>" } ] ]
 (no `salt` key: it is not encoded, see section 4.3)

SEND fetchCachePathForDomain:completion:   to com.apple.iconservices.store (sync, sequence 1)
 [ "fetchCachePathForDomain:completion:", "v32@0:8@16@?24", [ nil, nil ] ]      domain = nil
 replysig = v24@?0@"NSString"8@"NSString"16
REPLY (558 bytes)
 [ nil, "v@?@@", [ u16 "/Library/Caches/com.apple.iconservices.store",
                   u16 "<sandbox extension token>" ] ]

SEND generateImageWithRequest:reply:   (async, sequence 2, 805 bytes)
 [ "generateImageWithRequest:reply:", "v32@0:8@16@?24",
   [ { $class:"ISGenerationRequest",
       imageDescriptor: { $class:"ISImageDescriptor", size.width:128.0 size.height:128.0 scale:1.0
           variantOptions:0 badgeOptions:0 backgroundStyle:0 tintColor:nil ignoreCache:false graphicVariant:false
           appearance:0 contrast:0 vibrancy:0 appearanceVariant:0 background:0 specialIconOptions:2
           platformStyle:0 languageDirection:1 layoutDirection:0 },
       icon: { $class:"ISBundleIcon", digest:{NSUUID NS.uuidbytes data[16]},
               bundleURLString:{NSURL NS.base:nil NS.relative:u16 "file:///tmp/FakeAppA.app/"},
               tag:nil tagClass:nil type:nil },
       lsDatabaseUUID:{NSUUID NS.uuidbytes data[16]}, lsDatabaseSequenceNumber: 2100 },
     nil ] ]
 replysig = v16@?0@"ISGenerationResponse"8
REPLY (210 bytes)
 [ nil, "v@?@", [ { $class:"ISGenerationResponse", sharedMemory: 0,
                    uuid:{NSUUID NS.uuidbytes data[16]},
                    validationToken: data[40] } ] ]
 xpc dictionary: "ool" => [ <shmem: 151552 bytes (37 pages)> ]      (sharedMemory:0 = index into "ool")
```
The sandbox extension strings are `<64 hex>;00;00000000;00000000;00000000;000000000000001a;com.apple.app-sandbox.read;01;0100000a;<16 hex>;00;<lowercase path>`, i.e. `sandbox_extension_issue_file("com.apple.app-sandbox.read", path, ...)` of the per-user cache directory (config reply) and of `/Library/Caches/com.apple.iconservices.store` (store reply) **[captured]**. (The first field is a keyed hash from the kernel; the 16 hex field before `;00;` differs per call.)

## 4. Classes on the wire (`encodeWithCoder:` / `initWithCoder:`)

Keys and value kinds were obtained by encoding real instances with a logging `NSKeyedArchiver` subclass (`probes/q.m`, secure coding) **[runtime]**, then cross-checked against the NSXPC captures above **[captured]** (the captured keys match, order included). Decompiled encoders: `ISGenerationRequest encodeWithCoder:` `0x7ff814a87260`, `initWithCoder:` `0x7ff814abfc8f`; `ISGenerationResponse encodeWithCoder:` `0x7ff814ac0033`, `initWithCoder:` `0x7ff814a8730c`, `initWithData:uuid:validationToken:` `0x7ff814abfec4`, `initWithError:` `0x7ff814abffc7`; `ISIconCacheConfiguration encodeWithCoder:` `0x7ff814b02131`, `initWithCoder:` `0x7ff814b021a6`; `ISConcreteIcon encodeWithCoder:` `0x7ff814ab3de5`, `initWithCoder:` `0x7ff814ab3e55`.

All classes: `+supportsSecureCoding` = YES.

**ISGenerationRequest** (keys in encode order): `imageDescriptor` (ISImageDescriptor), `icon` (ISConcreteIcon subclass, decoded as `ISConcreteIcon` class set), `lsDatabaseUUID` (NSUUID), `lsDatabaseSequenceNumber` (int64). On decode (decompiled `0x7ff814abfc8f`): the four keys are read, then the current Launch Services database UUID and sequence number are fetched and compared with the decoded ones (when the decoded UUID is missing, the icon is nil, or the sequence is not newer, a Launch Services call is made; the exact selectors are stripped in the extracted image, U11). A pearOS agent should treat both as informational and echo the same database UUID/sequence in the validation token (section 6).

**ISImageDescriptor** keys: `size.width` (double), `size.height` (double), `scale` (double), `variantOptions`, `badgeOptions`, `backgroundStyle` (int64), `tintColor` (IFColor or nil), `ignoreCache`, `graphicVariant` (bool), `appearance`, `contrast`, `vibrancy`, `appearanceVariant`, `background`, `specialIconOptions`, `platformStyle`, `languageDirection`, `layoutDirection` (int64). Values for `ISImageDescriptor initWithSize:{128,128} scale:1`: `specialIconOptions=2`, `languageDirection=1`, all others 0/false/nil **[captured]**. (`shape`, `shouldApplyMask`, `drawBorder`, `drawBadge`, `templateVariant`, `selectedVariant`, `assetPlatformHint` are properties but are not encoded.)

**ISBundleIcon** keys: `digest` (NSUUID, from ISConcreteIcon), `bundleURLString` (NSURL, encoded as the NSURL object with `NS.base`, `NS.relative`; the key name says "String" but the object is an NSURL), `tag`, `tagClass`, `type` (strings or nil).
**ISTypeIcon**: `digest`, `type` (NSString), `iconConfig` (nil or ISIconConfiguration object).
**ISBundleIdentifierIcon**: `digest`, `bundleIdentifier`, `bundleVersion`.
**ISIcnsIcon**: `digest`, `icnsData` (NSData).
These four are the icon classes the Dock uses; others (`ISBindableIcon` subclasses, `ISSymbolIcon`...) exist in the framework and share `digest`.

**ISIconCacheConfiguration** keys: `url` (NSURL), `sandboxExtension` (NSString). The `salt` property exists (`ISDefaults cacheSaltString`, nil on the VM) but is not encoded.

**ISGenerationResponse** (two shapes):
- success: `sharedMemory` (xpc object via `encodeXPCObject:forKey:`; stored as an integer index into the xpc message's `ool` array), `uuid` (NSUUID = unit UUID), `validationToken` (NSData, 40 bytes, section 6). `initWithData:uuid:validationToken:` builds the shared memory with `xpc_shmem_create_readonly(bytes, length)` (`0x7ff814abfec4`); the client's `data` getter maps it with `xpc_shmem_map` (`0x7ff814a8745b`).
- error: only `error` (NSError: `NSCode`, `NSDomain`, `NSUserInfo`) (`initWithError:`).
`initWithCoder:` decodes `error` first; if absent it decodes `sharedMemory`, `uuid` (NSUUID), `validationToken` (NSData) **[decompiled 0x7ff814a8730c]**.

## 5. What the client does, in order (ISBundleIcon -> image)

Trace with lldb breakpoints on all `IS*` methods and the XPC calls, client = `probes/r2.m` (`getCGImageForImageDescriptor:completion:` on an ISBundleIcon) **[captured]**:

1. `-[ISIcon CGImageForImageDescriptor:]` / `getCGImageForImageDescriptor:completion:` -> `-[ISConcreteIcon imageForImageDescriptor:]` -> `_cachedImageForDescriptor:` (per-process `ISImageCache`, miss) -> `_imageFromStoreForDescriptor:`.
2. First use in the process: `+[ISIconManager sharedInstance]` -> `-[ISIconManager _init]` creates the NSXPC connection to `com.apple.iconservices` and **synchronously** calls `fetchCacheConfigurationWithReply:`. The reply block runs `-[ISIconCache initWithConfiguration:]` (maps `<url>/store.index`, consumes `sandboxExtension` when sandboxed; token printed 0 in an unsandboxed process) which creates `ISStore`: `-[ISStore init]` opens the connection to `com.apple.iconservices.store` and **synchronously** calls `fetchCachePathForDomain:` (domain nil, the `ISStore domain` property is nil on the VM) -> `storeURL = file:///Library/Caches/com.apple.iconservices.store/`. **This is the reason the Dock blocks without an agent: the first icon request waits for two synchronous XPC calls.**
3. Lookup (client only, no IPC): `-[ISIconCache findStoreUnitForIcon:descriptor:UUID:validationToken:]` (`0x7ff814b027b0`) -> `ISStoreIndex enumerateValuesForUUID:` with the icon digest; an item matches when the descriptor UUID, the scale and the size range match (section 7). Hit: `ISStore unitForUUID:` -> `+[ISStoreUnit storeUnitWithStoreURL:UUID:]` (`0x7ff814a87863`) opens `<storeURL>/<UUID>.isdata` with `open(O_RDONLY|O_NOFOLLOW)`, `lseek(SEEK_END)`, `mmap(PROT_READ, MAP_SHARED)`; then `ISConcreteIcon assessValidationToken:` (`0x7ff814ab4c33`), and the unit is decoded to a bitmap and put in the `ISImageCache`.
4. Miss: `-[ISConcreteIcon generateImageWithDescriptor:completion:]` (`0x7ff814ab76d7`) sends **asynchronously** `generateImageWithRequest:reply:` (sequence 2); the reply block reads `error`, `data`, `uuid`, `validationToken` of the response, builds the image from `data` directly (no `ISStoreUnit`) and stores the token in the image cache. The next request for the same icon finds the unit through steps 1-3.
5. Other XPC calls seen in the same run but not IconServices: `com.apple.lsd.mapdb`, `com.apple.cfprefsd.*`, `com.apple.analyticsd`.

What the agent does for a request **[inferred from headers + effects, not traced: the agent cannot be attached because of SIP]**: `IconCacheService generateImageWithRequest:reply:` (a) checks the request with `_isRequestValidForToken:clientPID:icon:` (`Util pidFromAuditToken` from the connection's audit token, presumably refusing icons the client could not read, e.g. file URLs the client has no access to), (b) `_skipCacheForIcon:`, (c) `generateStoreUnitWithRequest:validationToken:` -> `-[ISGenerationRequest generateImageReturningRecordIdentifiers:]` renders the bitmap and returns the unit data and the identifiers of the Launch Services records it depended on, (d) the unit is written through `ISStore addUnitWithData:` -> daemon `addData:withUUID:domain:completion:`, (e) a node is appended to `store.index` (`ISMutableStoreIndex addValue:`), `registerRecordIdentifiers:asSourceForUnit:` and `registerTintColor:forUnit:` update two `ISStoreMapTable` files, (f) replies with the unit. Effects observed on the VM for one request: new file `/Library/Caches/com.apple.iconservices.store/AAC33B3B-1D68-3C52-9743-55693279D9D7.isdata` (148072 bytes) at the time of the request, whose UUID equals `ISGenerationResponse.uuid`; a new node in the user `store.index` whose key is the request's icon digest, whose bitmap UUID is the same UUID and whose validation token is byte-identical to the response's (section 6) **[captured]**. The reply data is the same bytes as the unit file (151552-byte shared memory = 148072 rounded up to pages; the page-rounded size is of the mapping).

## 6. Validation token (40 bytes)

Layout, from the response, the index node and `assessValidationToken:` (`0x7ff814ab4c33`: `length == 0x28`, `*(u64*)(token+0x10)` compared with the current LS database sequence number, `uuid_compare(token, currentLSDatabaseUUID)`; if both match the unit is valid (return 0); else the third UUID `token+0x18` is compared with the third UUID of the icon cache's latest token: equal -> 1 (revalidate), different -> 2 (invalid)) **[decompiled + captured]**:

```
+0x00  uuid[16]   Launch Services database UUID (same as ISGenerationRequest.lsDatabaseUUID: 7CEC9DD7-EAC7-4AA5-878E-B3CE4DB0524D on the VM)
+0x10  u64 le     Launch Services database sequence number at generation time (request 2100 -> token 2104 on the VM; the agent re-reads the current number)
+0x18  uuid[16]   "RSC UUID" (name printed by ISIconCache's description): changes per unit; identifies the set of Launch Services records the unit came from (what registerRecordIdentifiers:asSourceForUnit: registers)
```

## 7. Store files

### 7.1 User index: `<DARWIN_USER_CACHE_DIR>/com.apple.iconservices/store.index` (+ `tint-color-registry.map`)

Path given by the config reply: `.../C/com.apple.iconservicesagent//../com.apple.iconservices/` (the agent's own cache dir `C/com.apple.iconservicesagent/` also exists, mode 0700). `ISDefaults cacheURL` = same dir, `metalCacheURL` = `<cacheURL>/__METAL_CACHE__` **[captured, `probes/s.m`]**. The dir is `drwx--x--x` owned by the user, files `-rw-------`: the client (same user) reads it directly. The 643072-byte file on the VM; `idx.py` parses it and verifies that all 108 nodes are reachable through their hash chain (0 errors) **[captured + decompiled]**.

Header (20 bytes, little endian), from `+[NSData(ISMutableStoreIndex_HashTable) mappedDataWithCapacity:additionalSize:]` (`0x7ff814aa15ad`) and the file:
```
+0x00 u32 version = 0x0b
+0x04 u8  flag = 1  (stored as u32 1)
+0x08 u32 count (nodes in use; 108 on the VM)
+0x0c u32 capacity (number of hash buckets; 4000)
+0x10 u32 unallocated offset = bytes used in the node area (108 * 152 = 16416)
+0x14 buckets[capacity]: u64 each = (size << 32) | offset  of the first node of the chain, 0 = empty   (offset relative to the node area)
+0x14 + 8*capacity = node area (0x7d14 for capacity 4000)
```
Mapping size = `pagesize + capacity*0x2c + additionalSize + 0x13` rounded to a page (so 44 bytes reserved per bucket/node pair; nodes are 152 bytes, so the file is extended by `_extend`/`_extendData` when full). Unused tail is zero.

Node (152 = 0x98 bytes), `addValue:size:forUUID:` (`0x7ff814aa17f7`), `addNodeWithSize:` (`0x7ff814aa1677`, node size = payload + 0x24):
```
+0x00 u64  self reference = (size << 32) | offset
+0x08 uuid key        the icon digest (== payload.key)
+0x18 u64  next reference in the bucket chain (0 = end); the next offset must be greater than the current one (cyclic chain guard logs "Cyclic node detected")
+0x20 u8   valid = 1  (removal clears it)
+0x24 payload, 116 bytes (below)
```
Bucket index = `(uuid_u64[0] ^ uuid_u64[1]) % capacity`, the two halves read as native (little endian) u64 (`enumerateValuesForUUID:bock:` `0x7ff814aa136c`: `param_3[1] ^ param_3[0]`, `% capacity` in `setNodeRef:forKey:` `0x7ff814aa1535`). Insert: append at `unallocated`, chain at the tail of the bucket, `count++`. On failure the whole index is reset ("Index will be reset!", `0x7ff814aa3493`).

Payload (116 bytes = the struct passed to `-[ISMutableStoreIndex addValue:]`, type `{?=[16C]{CGSize}dI[16C][16C]{?=[16C]Q[16C]}}`; offsets relative to the payload, add 0x24 for the node) **[header + captured; field meaning checked against the `-[ISIconCache description]` dump below for the items printed (0-4) and the response/token of the captured request; all 108 nodes parse and chain-verify]**:
```
+0x00 uuid[16]   key: icon digest ("UUID:" in the description; equal to node +0x08)
+0x10 double     CGSize.width  = lower bound of the valid size range   ("Valid from: 33pt ...")
+0x18 double     CGSize.height = upper bound of the valid size range   ("... to 128pt")
+0x20 double     nominal size the bitmap was rendered at              ("Size: 128pt")
+0x28 u32        scale (1 or 2)                                       ("@1x")
+0x2c uuid[16]   descriptor digest                                    ("Descriptor UUID:")
+0x3c uuid[16]   bitmap UUID = file name of the unit (<UUID>.isdata)  ("Bitmap filename:")
+0x4c uuid[16]   validation token part 1: Launch Services database UUID   ("DB UUID:")
+0x5c u64        validation token part 2: LS database sequence number     ("seq:")
+0x64 uuid[16]   validation token part 3: RSC UUID                        ("RSC UUID:")
```
Bytes +0x4c..+0x73 are exactly the 40-byte token of section 6. Distribution on the VM: sizes (lower,upper) = (0,16)x1, (19,24)x2, (25,32)x1/x2, (33,128)x1, (129,256)x1; the unit for a nominal size serves every request whose size lies inside the range at the same scale.
Printed by `-[ISIconCache description]` (captured with `probes/s.m`):
```
Item [0]  UUID: B90B9E04-ADDD-322C-A0E4-FD0FF7655C49
  Size: 32pt @1x   Valid from: 25pt to 32pt
  Bitmap filename: 7498F8C8-1876-31EC-967A-D42FD21BF237.isdata
  Validation Token:- DB UUID: 7CEC9DD7-EAC7-4AA5-878E-B3CE4DB0524D seq: 2084 RSC UUID: EF87B922-7716-3BE7-A5EB-127BCD1A7330
  Descriptor UUID: C6A40129-C51A-3855-AAAC-B0F368D27371
```

### 7.2 Unit files: `/Library/Caches/com.apple.iconservices.store/<UUID>.isdata`

Owner `_iconservices:admin`, directory `drwx--x--x` (no listing for others, traversal allowed), files `-rw-r--r--`; flat directory (167 entries), no subdirectories, `domain` nil **[captured]**. The agent never writes them directly: it calls the daemon (`addData:withUUID:domain:`); the daemon is the only writer (it is the only process running as `_iconservices`). Reader: `+[ISStoreUnit storeUnitWithStoreURL:UUID:]` (section 5). `removeItemWithUUID:` deletes the file; `removeAllData`/`removeAllDataThrottled` (daemon, on clearCache / low disk notifications) empty the directory (`StoreService` methods **[header]**, bodies not decompiled).

Unit file format (observed on two units; fields beyond the sizes are not decoded, U5):
```
+0x00 u32 = 9           version
+0x04 u32               byte size of the pixel block (131072 = 128*128*8 for the 128pt unit, 2304 = 24*24*4 for the 24pt one)
+0x08 u32               byte size of a second block that follows the pixels (16952 for the 128pt unit, 0 for the 24pt one)
+0x0c u32 = 1
+0x10 f32 f32           128.0 128.0 (24.0 24.0)             canvas size
+0x18 f32 f32           33.0 33.0 (19.0 19.0)               lower bound of the valid size range ( = payload lower bound)
+0x20 f32 f32           128.0 128.0 (24.0 24.0)             nominal size
+0x28 u32               0x00400001 (0x00200000)             flags
+0x2c f32               0.0 (1.0)                           scale?
+0x30 pixel data (size from +0x04), then the second block
```
File size = 0x30 + both block sizes (148072 = 48 + 131072 + 16952; 2352 = 48 + 2304). The first 0x30.. bytes of the pixel block are zero (transparent corners). Pixel format of the 24pt unit is 4 bytes/pixel with the premultiplied corner shape visible; the 128pt unit is 8 bytes/pixel (probably 16-bit float RGBA for wide colour). Unknown U5.

## 8. Rendering: who computes what

- The pixels are produced **in the agent** (`generateImageReturningRecordIdentifiers:` is in IconServices.framework, `ISGenerationRequest(Generation)`, `0x7ff814ac077c`, called by `IconCacheService generateStoreUnitWithRequest:validationToken:`); the agent process links `IconRendering`, `RenderBox`, `Metal`, `QuartzCore`, `IOSurface`, `CoreUI`, `SkyLight` and has `ISGPUIdleTimer` (exits when the GPU has been idle: `initWithQueue:`, `armTimer`, `_handleSigterm`), and `ISDefaults metalCacheURL` = `__METAL_CACHE__` (Metal shader cache in the user cache dir) **[header + otool]**.
- Compositing path (headers): `ISGenerationRequest` -> resource provider of the icon (`ISBundleIcon makeResourceProvider` -> `_makeAppResourceProvider` etc. which read the bundle's `CFBundleIconFile`/`CFBundleIconName` (`.icns`, `Assets.car` through CoreUI `CUICatalog`/`CUINamedIconLayerStack`) and the LaunchServices record (`LSBundleRecord`, `LSClaimRecord`, `UTTypeRecord` additions) -> recipe (`ISIconSpecification`, `ISIconStackComposer`, `ISCompositorRecipe`...) -> `IconRendering` (Glass / layered icons on 26) -> bitmap (IFBitmap in IconFoundation). The client does none of this: the client only builds `ISGenerationRequest`, maps/reads units and converts them to `CGImage`.
- The client does compute locally: the `ISImageDescriptor` and icon digests (`ISConcreteIcon initWithDigest:`, `-[ISImageDescriptor digest:size:]`, `NSUUID _IS_UUIDByXORingUUIDs:/_IS_UUIDWithData:/...`), the placeholder/fallback image (`_placeholderImageForError:descriptor:`, `_fallbackKey`), and the conversion of the unit/reply `data` to a CGImage.
- A pearOS agent therefore needs: an NSXPC listener with the three methods, reading the icon sources (`.icns`, `Assets.car`/CoreUI, `Info.plist`), composing them like the real recipes (rounded-rect mask, shadow, template/dark/tinted variants), emitting units in the `isdata` format, writing the index in the format of 7.1, and a daemon that stores the files. The first usable subset for the Dock is: `ISBundleIcon`, `ISTypeIcon`, `ISIcnsIcon` at 16..1024pt @1x/@2x.

## 9. Minimal compatible implementation (what must hold on the wire)

1. Agent: NSXPC listener on `com.apple.iconservices` with the interface of 2.1 (secure coding, classes exactly as in the table); `fetchCacheConfigurationWithReply:` returns `ISIconCacheConfiguration{url = <per-user cache dir>/com.apple.iconservices/, sandboxExtension = <string>}`; on FreeBSD there is no `sandbox_extension_issue_file`, so any non-nil string (the real format in section 3) is accepted by our own client (an Apple client in a sandbox needs a real token: unknown U6).
2. Daemon: listener on `com.apple.iconservices.store` with 2.2; `fetchCachePathForDomain:` -> (`/Library/Caches/com.apple.iconservices.store`, extension string); `addData:withUUID:domain:` writes `<UUID>.isdata` (UUID upper-case, hyphenated) and replies YES.
3. Response: `ISGenerationResponse{sharedMemory (xpc shmem, read-only), uuid, validationToken(40)}`, error shape on failure; also append the index node (7.1) so that the next request is served without IPC.
4. Our client library must write requests with the exact keys of section 4 (the Dock code path: `ISBundleIcon`, `ISTypeIcon`, `ISIcnsIcon`, `ISImageDescriptor`).
5. NSXPC layer: the envelope of section 3 (`f=33`, `root`, `proxynum`, `replysig`, `sequence`, `ool`) and the `bplist17` of 3.1 (decoder available; an encoder is straightforward from the same description, round-trip against `bp17.py` is the check).

## 10. Unknowns

- U1: `bplist17` is derived from six captures; rarely used tags (dates, arrays of objects with back-references, NSNumber of other widths, NSData > 4 GiB, class-reference reuse `$classes`) are unverified. Foundation's `_NSXPCSerialization*` (`_NSXPCSerializationDecodeTypedObjCValuesFromArray`) is the reference to decompile next. Also the unexplained trailing byte: array/dict end offsets are inclusive, `a0 <len-1>` always ends at the last byte.
- U2: digest algorithms. The icon digest of `ISBundleIcon` (e.g. `D3F051D6-4E50-07D5-1C6D-40EDD02983B9`) is not an RFC-4122 UUID (version nibble 0): probably an XOR of several UUIDs (`_IS_UUIDByXORingUUIDs:`) of path/bundle/LS-record hashes. The descriptor digest (`C6A40129-...`, version 3 = MD5-based, `_IS_UUIDWithData:`) and the unit UUIDs (version 3) hash unknown byte sequences. Only matters if our client and agent must interoperate with Apple's; between our own components any consistent function works.
- U3: payload doubles (lower bound / nominal size) and the exact rule used to choose among several index items (nearest size >= request?) were inferred from the printed dump, not from `findStoreUnitForIcon:` (decompiled `0x7ff814b027b0` but selectors unresolved).
- U4: the descriptor digest does not obviously depend on the size: the 74 items at 128pt@1x of this user's index share `C6A40129-...`, while `791FDB20-...` appears for both a 16pt and a 128pt item of other icons and `D6300087-...` for @2x items; so it hashes (some of) the other descriptor fields and the scale, not the size. Exact input unknown.
- U5: unit file fields at +0x18/+0x28/+0x2c, the second block (16952 bytes) and the pixel formats; need decompile of the consumer (IconFoundation `IFBitmap`/`IFImage` from `data`).
- U6: whether Apple's client accepts a nil/empty `sandboxExtension` and `fetchCachePathForDomain` extension (the real tokens are kernel-signed); irrelevant on FreeBSD for our own client.
- U7: the real `setClasses:` calls of `StoreService`/`ISStore` connections (only the inferred sets are known); the semantics of `domain` (always nil on the VM) and the daemon's reply when `domain` is non-nil.
- U8: the agent's side of a request was not traced (cannot attach to a SIP-protected process): the order (a)-(f) of section 5 is inferred; `_isRequestValidForToken:clientPID:icon:` rules not decompiled (selectors are stripped in the extracted image; decompile `IconCacheService` methods in the agent executable instead, whose strings are in the executable itself).
- U9: the `runAsRoot` agent instance: which job starts it, and whether root-owned clients use `/var/root/Library/Caches` or the same dir.
- U10: `ISStoreMapTable` file formats (`tint-color-registry.map` 3002368 bytes on the VM, and the unit-source registry), `ISDefaults` preference keys (`defaults read com.apple.iconservices` is empty on the VM), the clear-cache operations (`ClearCacheOperation`, `scheduleCacheOperation:`, notifyd names `com.apple.iconservicesd.clearCache.immediately`).
- U11: the meaning of `lsDatabaseSequenceNumber` update rule in `ISGenerationRequest initWithCoder:` (it compares with the live LS database; if newer, a sync call is made) and the 4-increment between request (2100) and token (2104) seen on the VM.

## 11. How to reproduce

```
# Mac VM: ssh -p 2229 ... alex@localhost
clang -fobjc-arc -framework Foundation -framework CoreGraphics r2.m -o r2        # client
clang -dynamiclib cap.c -o cap.dylib                                           # xpc dumper
lldb -b -s l7.txt-based script ./r2 /tmp/FakeApp.app 1 128                      # prints CAP#n and writes /tmp/cap/NNN_*.root / .ool0
python3 tools/iconservices/bp17.py cap/*.root                                  # decode NSXPC archives
python3 tools/iconservices/idx.py store.index <UUID-substring>                 # parse store.index
```
A bundle whose icon was never rendered is needed to force `generateImageWithRequest:reply:` (a copy of an app bundle with a random-colour `.icns`, generated per run); cached icons are served from the index with no XPC.
