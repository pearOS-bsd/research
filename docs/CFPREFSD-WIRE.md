# cfprefsd wire and behaviour specification

Target: macOS 26.7.2, CoreFoundation-5026.6.7.5, x86_64 slice extracted from the dyld shared cache
(`~/.pear/extracted/cf/CoreFoundation`, sha256 `705a7e48...aec3`). `/usr/sbin/cfprefsd` is a thin
stub: it sets up quarantine and then calls `__CFXPreferencesDaemon_main` in CoreFoundation. Every
piece of the server lives in CoreFoundation (`cfprefsd.m`, `CFPreferencesIO.m`,
`CFXPreferences_Internal.h` per the assert strings).

Method: Ghidra 12.1.4 through REA, plus `llvm-objdump`. Selector references in the extracted image point
into the shared cache selector area, so they were resolved by parsing the cache mappings (script in the
session scratchpad). CFString constants were resolved the same way. All addresses are VM addresses in that
image.

Tags: **[read]** means the decompiled code shows it. **[inferred]** means a reasoned guess that was not
proven line by line. Function names are given as `name @ address`.

---

## 0. Summary for implementers

- One XPC mach-service listener. The daemon role uses `com.apple.cfprefsd.daemon` and the agent role uses
  `com.apple.cfprefsd.agent`. Every message is a dictionary keyed by `CFPreferencesOperation` (int64).
- Operations: 1 = read or write a source. 2 = agent check-in. 3 = flush managed. 4 = flush domain.
  5 = multi-message. 6 = user deleted. 7 = observe. 8 = unobserve. 9 = get path. 999 = synchronize now.
- Invalidation goes through a shared memory page of 4096 `uint32` counters. Its name is
  `apple.cfprefs.<euid>v1` for the agent or `apple.cfprefs.daemonv1` for the daemon. Each source owns one
  slot. The slot index is computed from `CFHash(domain)`. Any write bumps the slot. A client re-fetches when
  the slot value differs from the `CFPreferencesShmemState` it last saw.
- Writes stay in memory and the slot is bumped at once. Disk writes run on a 10 s interval timer, or happen
  synchronously when the client asks. A file is written as a binary plist to a mkstemp file, then fsync,
  then `renameat`. The mode is 0600, or 0644 for AnyUser. The owner is the writer's euid and egid.
- Change notifications are sent over the client's own peer connection
  (`xpc_connection_send_message_with_reply`) to every connection that sent op 7 for that source, except the
  writer.

---

## 1. `__CFXPreferencesDaemon_main @ 0x7ff803093dbf`

| Item | Behaviour | Tag |
|---|---|---|
| argv | Only `argc > 0` is checked. Otherwise it prints `"cfprefsd is not intended to be used directly"` and calls `exit(0)`. The launchd argument `agent`/`daemon` is **not read**. | read |
| global | Sets `_isCFPrefsD = 1`. | read |
| I/O policy | `setiopolicy_np(9 /*IOPOL_TYPE_VFS_...*/, 0, 1)`. On failure it only logs. | read |
| queue | `dispatch_queue_create("com.apple.cfprefsd", autorelease_frequency(WORK_ITEM))`. | read |
| signals | `signal(SIGTERM)`, `signal(30 = SIGUSR1)` (both ignored), plus a dispatch signal source for each. | read |
| SIGTERM | `_terminating++`, then `_CFPrefsSynchronizeForDaemonTermination()` (writes every dirty source), then `exit(0)` (`_____CFXPreferencesDaemon_main_block_invoke @ 0x7ff803093f67`). | read |
| SIGUSR1 | Takes a snapshot of all sources and writes a debug dump to `/tmp/cfprefsddump(<pid>:<abs time>).txt` (`block_invoke_2/_3 @ 0x7ff803093f7e/0x7ff803093f93`). | read |
| test mode | When the process is not restricted (`__CFProcessIsRestricted`) and env `__CFPreferencesTestDaemon` is set, `testMode = 1`. Test mode uses service names with a `.test` suffix, a shmem name prefix `test.` instead of `apple.`, and `os_transaction_create("cfprefsd testing")`. | read |
| object | `cfprefsd = [[CFPrefsDaemon alloc] initWithRole:0 testMode:t]`, then `[cfprefsd enterSandbox]`, then `dispatch_main()`. | read |
| idle exit | No idle-exit code exists. Dirty sources hold an `os_transaction` ("CFPrefs domain dirty: <domain>", `-[CFPDSource setDirty:].cold.1 @ 0x7ff8030afffd`). Disk writes hold "CFPrefs domain writing: <domain>". launchd may therefore kill a clean, idle cfprefsd (transaction model). | read / inferred (launchd side) |

### Role (`-[CFPrefsDaemon initWithRole:testMode:] @ 0x7ff803092f3f`)

`role == 0` means "auto-detect" (`cold.2 @ 0x7ff8030b2166`, block @ `0x7ff8030931c9`). Outside test mode
the code calls `vproc_swap_string(NULL, 6 /*VPROC_GSK_MGR_NAME*/, ...)`. If the value is `"System"`, the
role is **2 (daemon)**. Otherwise it is **1 (agent)**. In test mode the role is daemon when
`getuid() == 0`. Role **3** is the in-process "direct mode" instance created inside client processes (see §8).

| role | service (`_name`, +0x10) | shmem name (`getShmemName:bufLen: @ 0x7ff8030b1815`) |
|---|---|---|
| 1 agent | `com.apple.cfprefsd.agent` (`.test`) | `apple.cfprefs.%d` + `v1` -> `apple.cfprefs.<cfprefsdEuid>v1` |
| 2 daemon | `com.apple.cfprefsd.daemon` (`.test`) | `apple.cfprefs.daemonv1` |
| 3 direct | (none, uses `xpc_connection_create(NULL,NULL)`) | `apple.cfprefs.<euid>v1` |

Format strings, read exactly: `"%scfprefs.%dv%d"` and `"%scfprefs.daemonv%d"` with version `1`. The
buffer length is 0x1f.

### Listener

- `xpc_connection_create_mach_service(name, NULL, 1 /*XPC_CONNECTION_MACH_SERVICE_LISTENER*/)` when this
  is cfprefsd. Otherwise it is an anonymous connection. **[read]**
- New peer (`block_invoke_2 @ 0x7ff80309324d`): each peer gets its own serial queue named
  `"client-<pid>"` (autorelease frequency work item). It also gets a `_CFPrefsClientContext` as the
  connection context (`valid = 1`, a 16-bit field = 0xffff) and the finalizer `client_context_finalizer`.
  Then the peer is activated. **[read]**
- Peer messages (`block_invoke_3 @ 0x7ff8030933d6`): while `_terminating` is set, the peer connection is
  cancelled. A dictionary goes to `handleMessage:fromPeer:replyHandler:`. The reply handler sends the reply
  only when it is not NULL (`block_invoke_4 @ 0x7ff8030935bb`). On `XPC_ERROR_CONNECTION_INVALID`, every
  source that the connection observed gets `observingConnectionWasInvalidated:` (or
  `removeObservingConnection:daemon:` for tombstones) (`block_invoke.132 @ 0x7ff8030935e7`). **[read]**
- Agent role at startup: `checkIn` (op 2 to the daemon, see §6), plus
  `notify_register_dispatch("CFPreferencesAgentsShouldCheckIn")`, which runs `checkIn` again. **[read]**
- Daemon role at startup: creates the queue `"com.apple.CFPreferences.AgentForwarding"` and the agent
  dictionary (+0x238). Then it calls `notify_post("CFPreferencesAgentsShouldCheckIn")`. **[read]**

### Sandbox (`-[CFPrefsDaemon(Sandbox) enterSandbox] @ 0x7ff8030939c4`)

`sandbox_init_with_parameters("com.apple.cfprefsd", 1 /*named*/, {"HOME", realpath(home), "SHMEM_NAME",
<shmem name>, "ROLE", "agent"|"daemon"})`. In recovery it rewrites `/private`. `handleMessage` calls
`enterSandbox` again whenever `_inSandbox == 0`. When that fails, the daemon sends an error reply
`"cfprefsd is unable to initialize sandbox..."` (type 1), **but the asm shows it then goes on processing
the message** (`handleMessage...cold.2 @ 0x7ff8030b1d24`, falls through at 0x7ff8030b1da6). **[read]**
pearOS has no Seatbelt, so it can skip this step.

---

## 2. Message dispatch and op table

`-[CFPrefsDaemon handleMessage:fromPeer:replyHandler:] @ 0x7ff8030915c5`, which goes to
`cold.2 @ 0x7ff8030b1d24`:

1. An error object is ignored. A non-dictionary triggers `assert(type == XPC_TYPE_DICTIONARY)`.
2. Test-only fault injection: when it is enabled, a message without `PreviousMessageInjectedFailure` gets
   its connection cancelled.
3. The server sets `"connection"` = the peer connection object **in the incoming message** (internal key,
   used later by `_CFPrefsConnectionForMessage`).
4. It switches on `xpc_dictionary_get_int64(msg, "CFPreferencesOperation")`:

| op | handler | reply |
|---|---|---|
| 1 | `handleSourceMessage:replyHandler: @ 0x7ff80309164b`, then `-[CFPDSource acceptMessage:] @ 0x7ff80308a70e`. Read source, write key(s), FullCloudSync | yes |
| 2 | `handleAgentCheckInMessage: @ 0x7ff8030b103b` (daemon only) | **none** |
| 3 | `handleFlushManagedMessage:replyHandler: @ 0x7ff8030b0f48` | yes (empty, after work) |
| 4 | `handleFlushSourceForDomainMessage:replyHandler: @ 0x7ff8030b11e4` | yes (empty) |
| 5 | `handleMultiMessage:replyHandler: @ 0x7ff803091f42` | yes |
| 6 | `handleUserDeletedMessage:replyHandler: @ 0x7ff8030b12b4` | yes |
| 7 | same path as op 1 -> `setObserved:YES bySenderOfMessage:` | yes (shmem fields) |
| 8 | same path as op 1 -> `setObserved:NO ...` | yes (shmem fields) |
| 9 | same path as op 1 -> returns `CFPreferencesUncanonicalizedPath` | yes |
| 999 | `[[_CFPrefsSynchronizer sharedInstance] synchronize]` (write every dirty source now). The client sends it from `simulateTimerSynchronizeForTestingForUser:` (`@ 0x7ff803095092`) | **none** |
| other | error `"Unsupported CFPreferences Daemon Operation"`, type 1 | yes |

### Error reply shape (`_populateErrorReply @ 0x7ff80308fddc`)

```
reply = xpc_dictionary_create_reply(msg) ?: xpc_dictionary_create(NULL,NULL,0)
reply["CFPreferencesPropertyList"]    = <removed>
reply["CFPreferencesErrorDescription"] = string
reply["CFPreferencesErrorType"]        = int64 type
(optional) reply["CFPreferencesErrorClientFault"] = true
```

Error types, read from the client handler `handleErrorReply:...retryContinuation: @ 0x7ff80309c043`:

| type | meaning (client reaction) |
|---|---|
| 0 | Denied or failed. The client logs the error and marks the write failed. |
| 1 | Fatal. The client logs "detaching from cfprefsd" and sets the source to `_volatile` (memory only). |
| 2 | "Couldn't enqueue updated values" (server side). |
| 3 | Access token needed. Reply has `CFPreferencesAccessToken` (string path). The client stores the path, attaches a token, and retries (max 10). |
| 4 | Directory needed. Reply has `CFPreferencesUncanonicalizedPath`. The client runs `mkdir dirname(path)` with mode 0700 and its own euid/egid, then retries (max 3). |
| 5 | Write failed (client `writeFailedForKeys`). No server producer was seen in this pass. |

### Op 5: multi-message

- `CFPreferencesMessages` must be an XPC array whose items are all dictionaries or null. Otherwise the
  daemon sends an error reply (`cold.2/.3`). **[read]**
- Each dictionary item goes through `handleMessage:fromPeer:` **synchronously**, with the same peer. The
  sub-reply (or `xpc_null` when there is no reply) is stored at the same index. **[read]**
- The reply is `{ CFPreferencesMessages: [replies...] }`. It has the same count, and null slots stay null.
  **[read]**

---

## 3. Op 1/7/8/9: source messages

### 3.1 Request keys read by the server

| key | type | meaning / default | where |
|---|---|---|---|
| `CFPreferencesOperation` | int64 | 1/7/8/9 | acceptMessage |
| `CFPreferencesDomain` | string | Required, else `"Domain not found"` (type 1). `"Apple Global Domain"`, `".GlobalPreferences"` and `kCFPreferencesAnyApplication` are all rewritten in the message to `"kCFPreferencesAnyApplication"`. `kCFPreferencesCurrentApplication` is rejected. The domain is interned. | `_CFPrefsGetFixedUpDomainForMessage @ 0x7ff803090471` |
| `CFPreferencesUser` | string | Missing means `kCFPreferencesAnyUser`. `"kCFPreferencesCurrentUser"` is replaced by the user name of the **peer's euid**. A flag "root or role account" (uid < 501) is computed. | `_CFPrefsCopyFixedUpUserForMessage @ 0x7ff803090c2f` |
| `CFPreferencesIsByHost` | bool | ByHost file | handleSourceMessage |
| `CFPreferencesIsManaged` | bool | MDM source, `/Library/Managed Preferences` | handleSourceMessage |
| `CFPreferencesCurrentApplicationDomain` | bool | The domain is the client's main bundle id (container / cloud entitlement logic) | handleSourceMessage |
| `CFPreferencesHostBundleIdentifier` | string | Main bundle id of the client, used for container fix-up | `_CFPrefsCopyFixedUpContainerForMessage @ 0x7ff803090641` |
| `CFPreferencesContainer` | string | Container path. `kCFPreferencesNoContainer` means none. The server resolves it with `open`+`F_GETPATH`. When it is missing and the client is sandboxed, the server uses `sandbox_container_path_for_audit_token`. | same |
| `Key` | string | Key to write. With `Value` present this is a write. Without `Value` it is a read. | `_CFPrefsDecodeKeyValuePairFromXPCMessage @ 0x7ff802ff4321` |
| `Value` | xpc object | New value. `xpc_null` means delete. Strings and booleans arrive as native xpc. Everything else arrives as **binary-plist `data`** (`_CFPrefsEncodeValueIntoMessage @ 0x7ff802f011c5`, format 200 = bplist). The server decodes data with `CFPropertyListCreateWithData` and anything else with `_CFXPCCreateCFObjectFromXPCObject` (`_CFPrefsApplyChangesQueueToDictionary @ 0x7ff802fbc010`). | |
| `MultiKeySet` | bool | When true, `Value` is an xpc dictionary {key: value,...} (internal key name "MultipleKeys", encoding 1) | decode |
| `CFPreferencesShouldWriteSynchronously` | bool | Write to disk before replying | acceptMessage |
| `CFPreferencesAvoidCache` | bool | Flush the cache first (`syncWriteToDiskAndFlushCacheForReason:"we're avoiding the cache"`), so the server re-reads from disk | acceptMessage |
| `CFPreferencesRestrictedReadability` | bool | Sets flag 0x10: the file is always 0600 | acceptMessage |
| `CFPreferencesFileProtectionClass` | int64 | Stored on the source and passed to `mkstemp_dprotected_np` | acceptMessage |
| `CFPreferencesUseCorrectOwner` | bool | Owner = `getpwnam(source user)` instead of the peer euid/egid | acceptMessage |
| `ValidatePlist` | bool | Validate the cached or disk plist. **If disk validation fails, the file is unlinked** and the cache is cleared ("...validation failed") | `copyPropertyListWithoutDrainingPendingChangesValidatingPlist:... @ 0x7ff803088499` |
| `CFPreferencesShmemIndex` | int64 | Optional. When present, not -1 and different from the source's index, the server logs and replies `"Lookup inconsistency"` (type 1) | `handleSourceMessage block_invoke_2 @ 0x7ff80309247c` |
| `CFPreferencesAuditToken` | data[32] | Always **erased** on entry. It is only re-set from `CFPreferencesAuditTokenToImpersonate` when the peer has `com.apple.private.defaults-impersonate` | `_CFPrefsFixUpIncomingMessageForPIDImpersonationIfNeeded @ 0x7ff80308feac` |
| `CFPreferencesAccessToken` | fd | File descriptor proving access to another user's file | `validatePOSIXPermissionsForMessage... @ 0x7ff80308a01f` |
| `CFPreferencesSandboxExtension` | string | Consumed for the request (`_consumeSandboxExtensions`) | |
| `CFPreferencesCloudConfig`, `CFPreferencesCloudStoreIdentifier`, `FullCloudSync` | string / string / bool | Cloud sources (§9) | handleSourceMessage |
| `kCFPreferencesTestingSimulateSlowFilesystem`, `kCFPreferencesTestingSimulateOutOfDiskSpace` | bool / int64 | Testing only (sleep 1 s; fake ENOSPC) | |

The client builds these keys in `-[CFPrefsPlistSource createSynchronizeMessage] @ 0x7ff802f00d14`. That
function sets Domain, HostBundleIdentifier, CurrentApplicationDomain, IsByHost, Operation=1, IsManaged, and
User (omitted for AnyUser!). It also sets UseCorrectOwner, Container, the pair
ShouldWriteSynchronously+AvoidCache (always together), FileProtectionClass and RestrictedReadability.

### 3.2 Source lookup (`withSourceForDomain:... @ 0x7ff803086533`)

- The cache key is `CFPDSourceLookUpKey{uncanonicalized path, cloudConfigurationPath}`. Two requests that
  resolve to the same file share one source. **[read]**
- When no source exists, the server creates one (block @ 0x7ff803086849):
  - A container gives `CFPDContainerSource`. A cloud config gives `CFPDCloudSource`. Domain ==
    AnyApplication with user != AnyUser, not byHost and not managed gives `CFPDMirroredSource` with mirrored
    keys `["AppleLanguages","AppleLocale"]`. Every other case gives `CFPDSource`
    (`_createSourceWithDomain:... @ 0x7ff8030ae541`). **[read]**
  - A tombstone already present for that source (which still holds observers) hands its observers to the new
    source (`transferObservingConnectionsToSource:`). **[read]**
- When the source is missing (no path), the reply is `"Domain or user not found"` (type 1).

### 3.3 Shmem index of a source (block @ 0x7ff803086849), **[read]**

```
base = (domain ? (CFHash(domain) % 585) * 7 + (CFStringGetLength(domain) % 7) : 0)
if (base > 0xff8 || base == 0) base = (len % 7) + 1
variant = container            ? 6
        : cloudConfig          ? 5
        : managed              ? (user == AnyUser ? 4 : 3)
        : user == AnyUser      ? 2
        : byHost               ? 0 : 1
index = (int16)(base + variant)              // always 1..4094
```

So each domain owns a run of 7 consecutive slots that starts at `base`. "Flush domain"
(`updateShmemForDomain: @ 0x7ff8030b15af`) bumps all 7 slots. **`CFHash` must be Apple's string hash**,
because clients cache the index (see the "Lookup inconsistency" check). **[read]** The CFHash requirement
itself is **[inferred]**.

### 3.4 `-[CFPDSource acceptMessage:] @ 0x7ff80308a70e`: flow and reply

1. op 9: the reply gets `CFPreferencesUncanonicalizedPath` = path string (`cold.7 @ 0x7ff8030b0a16`).
   Nothing else happens. For the mirrored source the value is an array [own path, mirror path]
   (`-[CFPDMirroredSource acceptMessage:] @ 0x7ff8030af996`).
2. AvoidCache, RestrictedReadability, FileProtectionClass and the test flags are applied.
3. Write path (Key+Value present):
   - read-only mode (`_CFPrefsReadOnly`) -> result 8 `"Writing has been disabled"`.
   - The owner uid/gid comes from the peer (or from `getpwnam` with UseCorrectOwner). When it differs from
     the cached owner, the server runs `syncWriteToDisk` first.
   - When no directory fd is cached, the server calls `cacheFileInfoForWriting:...` (opens or creates, §5).
4. Read path: when nothing is cached, the server calls `cacheFileInfo`. Then, if the file is **>= 1 MiB**
   and not validating, it opens the file and the reply carries `PlistFD` (fd). Otherwise it copies the cached
   data (`copyPropertyListWithoutDrainingPendingChanges...`)
   (`openPropertyListWithout... @ 0x7ff8030aed07`: `fstat` size `< 0x100000` means no fd).
5. `validateMessage:withNewKey:...` (§7) returns a code, which the server maps:

| code | reply |
|---|---|
| 1 OK, op 1 read | `CFPreferencesPropertyList` = xpc data (bplist) when present. `PlistFD` when big. `PlistDiff` = xpc array `[k1,v1,k2,v2,...]` of **pending, not yet drained changes** when there are any. Then the shmem fields. |
| 1 OK, op 7/8 | `setObserved:(op==7) bySenderOfMessage:`. Then the shmem fields. |
| 1 OK, write | `enqueueNewKey:value:encoding:inBatch:NO fromMessage:`. On failure: `"Couldn't enqueue updated values"` type 2. When the size grew: `CFPreferencesByteCountThreshold` (§8). A sync write happens if `ShouldWriteSynchronously`, the 35459826 workaround applies, or the file was just created. If source user != cfprefsd's own user: `flushDomain:inAgentForUser:` (§6). Then `asyncNotifyObserversOfWriteFromConnection:message:` (§4). |
| 2, 3 | `"Operation not allowed"` or a specific sandbox/POSIX message, type 0, plus `CFPreferencesErrorClientFault = true` |
| 4 | `"Access token needed"` type 3, plus `CFPreferencesAccessToken` = file path (string) |
| 5 | `"Directory needed"` type 4, plus `CFPreferencesUncanonicalizedPath` |
| 6 | `"Invalid plist data"` type 1 |
| 7 | `"Path not accessible"` type 0 |
| 8 | `"Writing has been disabled"` type 0 |
| 9 | `"Unable to determine access"` type 0 |

**Every** op 1/7/8 reply (success or error) then gets: **[read]**

```
CFPreferencesShmemIndex  int64  = source.shmemIndex
CFPreferencesShmemName   string = "apple.cfprefs.501v1" | "apple.cfprefs.daemonv1"
CFPreferencesShmemState  uint64 = shmem[shmemIndex]        (current uint32 counter)
```

6. After the message: a file created by this request that is still **0 bytes** is unlinked
   (`cleanUpIfNecessaryAfterCreatingPlist @ 0x7ff8030aeaa5`). Sources flagged "never cache" are flushed.
   The fds are closed. **[read]**
7. `cleanUpAfterAcceptingMessage: @ 0x7ff80308b89f`: in the **agent**, the domains `com.apple.CoreGraphics`
   and `com.apple.assistant.backedup` (and the key `com.apple.ColorSync.Devices` in AnyApplication) also
   send op 4 to the daemon (`flushDomainInDaemon:`) (workaround 35459826). **[read]**

### 3.5 How the client uses the reply (`-[CFPrefsPlistSource handleReply:toRequestNewDataMessage:...] @ 0x7ff802f01d35`)

- On the first reply only: `shm_open(CFPreferencesShmemName, O_RDONLY)` and `mmap(16384, PROT_READ,
  MAP_SHARED)` (`-[_CFXPreferences shmemForRole:name:] @ 0x7ff802f03233`). The client stores
  `shmemEntry = base + 4*CFPreferencesShmemIndex`. When the mapping fails, the source goes "volatile".
  **[read]**
- `lastKnownShmemState = CFPreferencesShmemState`. **[read]**
- Base dictionary = `CFPreferencesPropertyList` (data) or the `PlistFD` mmap. When neither is present, the
  base is an empty dictionary. Then `PlistDiff` is applied on top. `CFPreferencesValidationPropertyList` (a
  dictionary, mirrored source) is merged. The top level must be a dictionary. **[read]**
- Staleness check before each use (`alreadylocked_generationCount @ 0x7ff80309d26a`):
  `if (!volatile && (shmemEntry == NULL || (*shmemEntry != -1 && *shmemEntry != lastKnownShmemState)))`
  the client re-sends op 1 (read) for that source. **[read]**

### 3.6 Which service the client picks (`createRequestNewContentMessageForDaemon: @ 0x7ff802f0079d`)

| condition | role |
|---|---|
| direct mode | 3 (in-process) |
| user == AnyUser | 2 daemon |
| client euid == 0 and (user == CurrentUser or user uid < 501) | 2 daemon |
| otherwise | `canLookUpAgents` ? 1 agent : 2 daemon |

**[read]**

---

## 4. Observation and change notifications

- op 7 adds the peer connection to the source's observer set (+0x48) and the source to the client context's
  `_observedSources`. op 8 removes both (`setObserved:bySenderOfMessage: @ 0x7ff80308a265`, blocks
  @ 0x7ff80308a3a5 / 0x7ff80308a47f). **[read]**
- On an accepted write (`asyncNotifyObserversOfWriteFromConnection:message:` block @ 0x7ff803088b85), the
  server builds one message: **[read]**

```
{ CFPreferencesDomain:      string  (source domain),
  CFPreferencesUser:        string  (source user),
  CFPreferencesIsByHost:    bool,
  CFPreferencesContainer:   string  (if any),
  CFPreferencesCloudConfig: string  (if any),
  CFPreferencesPID:         int64   (pid of the writer, from its audit token) }
```

  (The keys are in the static table `__CFPrefsNotifyFuncKeys @ 0x7ff840242670`. There is no
  `CFPreferencesOperation`.)
- `notifyFunc @ 0x7ff803088d98` runs for each observer connection **other than the writer's** and calls
  `xpc_connection_send_message_with_reply(peer, copy, observationQueue, handler)` on the existing peer
  connection. Flow control: one notification in flight per client. When one is already in flight, the
  server sets `didDeferKVONotifications`. When the reply arrives, a deferred notification is sent again
  (`___notifyFunc_block_invoke*` @ 0x7ff80308de68..0x7ff80308e011). **[read]**
- The client's connection handler (`_setupNewDaemonConnection:` block @ 0x7ff803096283) replies at once with
  an empty `xpc_dictionary_create_reply`. It then, asynchronously, runs
  `updateSearchListsForIdentifier:(domain)`, which drives KVO / `NSUserDefaultsDidChange`
  (block_2 @ 0x7ff8030964bb). **[read]**
- When a source is evicted while observers remain, a `CFPDObserverOnlyTombstone` keeps the observers and the
  shmem index. Its notification is just `{ CFPreferencesDomain: string }`, sent with reply and one in flight
  (`-[CFPDObserverOnlyTombstone _sendNotificationToConnection:] @ 0x7ff80308c806`). **[read]**

---

## 5. Paths, shared memory, disk writes

### 5.1 Path rules (`+[CFPrefsDaemon _getUncanonicalizedSourcePath:...] @ 0x7ff80308637b`)

Non-managed: `_CFPrefsGetPathForTriplet @ 0x7ff80306189f` plus
`_CFPrefsCreatePreferencesDirectoryURLForTriplet @ 0x7ff802fc8913`. **[read]**

1. Directory:
   - user == `kCFPreferencesAnyUser` -> `/Library/Preferences/`. Inside cfprefsd this **only works when
     euid == 0**, so the agent cannot serve AnyUser.
   - container given -> `<container>/Library/Preferences/` (or `.../Library/Preferences/ByHost/`).
   - otherwise: home = `getpwuid(geteuid())` for CurrentUser, else `getpwnam(user)`. If there is no entry,
     `/var/empty`. Then add `Library/Preferences/` or `Library/Preferences/ByHost/`.
2. File name: domain = `_CFPrefsGetCacheStringForBundleID(domain)`, and AnyApplication becomes
   `.GlobalPreferences`. A trailing `.plist` is stripped (case-insensitive, anchored at the end).
   - byHost and user != AnyUser -> `<name>.<hostid>.plist`
   - otherwise -> `<name>.plist` (byHost is ignored for AnyUser)
3. A path that starts with `/private/var/empty` or `/var/empty` is cleared, so the result is "not found". A
   leading `/private` is stripped.
4. Root's home is whatever `getpwuid(0)->pw_dir` returns (`/var/root`), so root uses
   `/var/root/Library/Preferences/...`.

Host id (`_CFXPreferencesGetByHostIdentifierString @ 0x7ff802fdaef1`, block @ 0x7ff802fdaf0f):
`gethostuuid(uuid, {30,0})`, then `CFUUIDCreateString` (uppercase). If the string starts with
`00000000-0000-1000-8000-`, the id is the **last 12 chars lowercased** (legacy MAC form). When
`gethostuuid` fails: `00000000-0000-0000-0000-000000000000`. When the string cannot be built:
`UnknownHostID`. **[read]**

Managed (`_CFPrefsGetPathForManagedBundleID @ 0x7ff802fab926`): base `/Library/Managed Preferences/`. **[read]**
- AnyUser: `<domain>.plist` (or the directory itself when there is no domain)
- CurrentUser: `<login name>/<domain>.plist` (inside cfprefsd: `CFCopyUserName()` cached)
- other user: `<user>/<domain>.plist`
- `managedUsesContainer` asserts `!useSystemContainer`.

A container with AnyUser must be under `/private/var/containers/Shared/SystemGroup/`. Otherwise the error is
`"Using kCFPreferencesAnyUser with a container is only allowed for System Containers"`. **[read]** The exact
condition is not fully clear in the decompile (**[inferred]**).

### 5.2 Shared memory (`-[CFPrefsDaemon _initializeShmemPage:] @ 0x7ff8030b169f`)

| item | value | tag |
|---|---|---|
| API | POSIX `shm_open(name, O_RDWR\|O_CREAT (0x202), 0644)`, `ftruncate(fd, 0x4000)`, `mmap(NULL, 0x4000, PROT_READ\|PROT_WRITE, MAP_SHARED, fd, 0)`, `close(fd)`. (Not xpc_shmem.) | read |
| size | 16384 bytes = **4096 `uint32` counters**. Slot 0 is unused (`updateEntireShmem` bumps 1..4095). | read |
| fallback | When shm fails: fault log "cross-process preferences will not work correctly", then `calloc(1, 0x4000)` (private). | read |
| direct-mode client (role 3) | If `sandbox_check(pid, "ipc-posix-shm-write-data", name)` passes, it calls `shm_open(name, O_RDWR)` **without O_CREAT** and attaches to the **real agent's page**. So in-process writers bump the same counters. | read |
| bump | `__atomic_add(&slot, 1)`. When the result is 0 it is set to 1 (0 is never reused). `updateShmemIndex: @ 0x7ff8030b14e4`. | read |
| bumped when | every write (`setDirty:YES` -> `updateShmemEntry`, `@ 0x7ff803087d9e`). op 4: the 7 domain slots. op 3: the slots of dead managed sources (bitset). op 6: all slots 1..4095. | read |
| client map | `shm_open(name, O_RDONLY, 0)`, `mmap(0x4000, PROT_READ, MAP_SHARED)` | read |

### 5.3 Disk writes

Write pipeline (`enqueueNewKey:... @ 0x7ff8030891e2`, `drainPendingChanges @ 0x7ff803088f26`): **[read]**
- Pending changes are an xpc array `[k,v,k,v...]`. A value for an existing key is replaced in place.
  `xpc_null` means delete. The pending byte count is tracked.
- `setDirty:YES` bumps shmem, adds the source to `_CFPrefsSynchronizer`, and takes an os_transaction.
- When pending changes exceed **128 KiB** (0x20000), the server drains them at once into a new plist buffer.
- Drain: copy the current plist into a mutable dictionary (or a new empty one), apply the queue, and build a
  `CFPDPurgeableBuffer` holding the **binary plist** (`__CFBinaryPlistCreateDataUsingExternalBufferAllocator`,
  `-[CFPDPurgeableBuffer initWithPropertyList:] @ 0x7ff802ff4d2f`). An empty dictionary is still serialised;
  no delete-when-empty code was found (**[inferred]**: the file stays as an empty-dict plist).

When (`-[_CFPrefsSynchronizer init] @ 0x7ff80308578c`): **[read]**
- Timer: `dispatch_source_create(DISPATCH_SOURCE_TYPE_INTERVAL, 10000 /*ms*/, 0, "CFPreferences Periodic
  Sync Queue")`. The type was resolved by `ipsw dyld a2s` to `__dispatch_source_type_interval`. The timer is
  resumed on the first dirty source. Each tick takes a snapshot of the dirty set, clears it, and for each
  source calls `createDiskWrite` under the lock, then the write block, then `handleWritingResult:`
  (`_CFPrefsSynchronizeDirtySourceForTimer @ 0x7ff8030858e9`).
- Synchronous (`syncWriteToDisk @ 0x7ff8030883ff`) on: `CFPreferencesShouldWriteSynchronously`, the
  workaround domains, a newly created file, an owner change, AvoidCache, SIGTERM, op 999. The daemon also
  forces `ShouldWriteSynchronously` for system users (root or role accounts) (handleSourceMessage).

File open/create (`cacheFileInfoForWriting:euid:egid:didCreate: @ 0x7ff8030873d8`): **[read]**
- `open(dirname, O_SEARCH (0x40100000))`, then `openat(dirfd, basename, O_RDONLY)`.
- For writes on ENOENT: `openat(dirfd, basename, O_CREAT, 0600 | 0644)`. This creates an **empty** file,
  which is removed after the request when nothing was written.
- Parent directory missing (ENOENT/ENOTDIR): if the directory is exactly `/Library/Preferences`, the server
  creates it (`_CFPrefsCreatePreferencesDirectory(path, 0755, 0, 0x50)`). Otherwise the error is
  "Directory needed" (type 4) and the **client creates it with 0700**.
- `F_GETPATH` gives the canonical path. In cfprefsd the server also calls
  `sandbox_passthrough_access(fd, 0x102)`.

Atomic write (`createDiskWrite @ 0x7ff803087e1d`, `_CFPrefsTemporaryFDToWriteTo @ 0x7ff803061a5b`,
`_CFPrefsWritePlistToFDThenClose @ 0x7ff803061e71`): **[read]**
1. Mode `0600`. It is `0644` when user == AnyUser and the source is not restricted.
2. Temp dir = `_dirhelper_relative(0, <parent dir>)`. Name = `"<basename>.XXXXXXX"`. Created with
   `mkstemp` (or `mkstemp_dprotected_np(path, protectionClass, 0)` when a protection class is set; on
   ENOTSUP it falls back if the filesystem has no protection). (**[inferred]**: the dirhelper result is on
   the same volume so that `rename` works; pearOS can simply use the parent directory.)
3. `fchown(owner uid, gid)`, `fchmod(mode)`.
4. `write()` loop (retries EINTR=4 and EAGAIN=35), `fsync()` (retries EINTR), `fchown`+`fchmod` again.
5. Re-validate the buffer as a plist. On failure: error 0xbadd, no rename, purge.
6. `close`, then `renameat(AT_FDCWD, tmp, dirfd, basename)`. On failure: fault log and `unlink(tmp)`.
7. ENOSPC (28) from the write sets the source dirty again (`handleWritingResult: @ 0x7ff8030881f3`).
8. Owner = the last writer's peer `euid/egid`, or `getpwnam(user)` with `CFPreferencesUseCorrectOwner`.

Changes made behind its back: there is **no kqueue/vnode watch** on plist files. `respondToFileWrittenToBehindOurBack
@ 0x7ff803087ca6` (= `lockedSync:` clear cache, so the next read hits the disk) only runs on op 4, op 3
(managed) and op 6. Tools that write files directly (for example `defaults` in direct mode) must send op 4.
Only directory **deletion** is watched with an FSEvents stream (`_CFPrefsWatchForDeletionOfDirectory`,
`deletionStreamCallback @ 0x7ff80308edae`). **[read]** That the deletion watch is the only watch is
**[inferred]** from the symbol set.

---

## 6. Daemon and agent split

- Agent check-in (`-[CFPrefsDaemon checkIn].cold.1 @ 0x7ff8030b2239`): the agent connects to
  `com.apple.cfprefsd.daemon` (flag `XPC_CONNECTION_MACH_SERVICE_PRIVILEGED` = 2, outside test mode;
  `copyResumedAgentToDaemonXPCConnection @ 0x7ff8030b0e2a`) and sends (no reply expected):
  `{ CFPreferencesOperation: 2, CFPreferencesUser: <CFCopyUserName or "InvalidUserName">,
  CFPreferencesEndpoint: xpc_endpoint_create(agent listener) }`. **[read]**
- Daemon side (`handleAgentCheckInMessage: @ 0x7ff8030b103b`): `xpc_connection_create_from_endpoint`, then
  `agents[user] = conn` on the AgentForwarding queue. The entry is removed on connection errors (blocks
  @ 0x7ff803092cee / 0x7ff803092d7b). An agent that receives op 2 only logs an error. **[read]**
- Daemon to agent:
  - A daemon write to a source whose user != the daemon's own user name calls
    `flushDomain:inAgentForUser: @ 0x7ff803090f18`, which sends a **sync** `{Operation:4, CFPreferencesDomain}`
    to that user's agent. **[read]**
  - op 3 in the daemon also sends `{Operation:3}` to each agent (`sendEachAgent: @ 0x7ff8030b1510`, waits for
    all replies). **[read]**
  - op 6 removes the agent entry for that user. **[read]**
- Agent to daemon: only the workaround domains (§3.4 step 7) send a sync op 4 to the daemon. The agent does
  **not** forward ordinary requests. The client picks the service itself (§3.6). **[read]**
- Users and domains: the agent serves its own user's home domains (Library/Preferences, ByHost, containers).
  The daemon serves AnyUser (`/Library/Preferences`), root and role accounts, other users when root asks,
  and managed sources. **[read]** for path rules and client selection; the overall split is **[inferred]**.

Op 4 (`handleFlushSourceForDomainMessage: @ 0x7ff8030b11e4`): `CFPreferencesDomain` (C string) -> for each
cached source of that domain, `respondToFileWrittenToBehindOurBack`. Then the server bumps the 7 shmem slots
of the domain and replies with an empty dictionary. **[read]**

Op 3 (`handleFlushManagedMessage: @ 0x7ff8030b0f48`): `_CFPrefsResetManagedPreferencesStateCache()`. For all
known managed sources, the server calls `respondToFileWrittenToBehindOurBack` and bumps the slots in the dead
managed bitset (`_deadManagedSourceBitSet`, 64 x uint64). It calls `notifyObservers` on managed tombstones,
replies with an empty dictionary, and (daemon only) forwards op 3 to the agents. **[read]**

Op 6 (`handleUserDeletedMessage: @ 0x7ff8030b12b4`): agent -> error type 1. The peer euid must be 0, else
`"Only root processes are allowed..."`. `CFPreferencesUser` is required, else `"No username in user deleted
message"`. The server drops `agents[user]`, flushes the cache of all sources, bumps shmem slots 1..4095, and
replies with an empty dictionary. **[read]**

---

## 7. Permission and validation (`validateMessage:withNewKey:... @ 0x7ff80308a15d`)

Validation runs only when the request reads an existing plist or writes. The order is:

1. POSIX (`validatePOSIXPermissionsForMessage:accessType:fileUID:mode:fullyValidated: @ 0x7ff80308a01f`):
   **[read]**
   - Allowed when peer euid == 0 or peer euid == cfprefsd's euid.
   - Read by another uid: allowed if `S_IROTH` is set, or if peer euid == file uid and `S_IRUSR` is set.
   - Write by another uid: never allowed without a token.
   - Otherwise the server needs `CFPreferencesAccessToken` (an fd, `xpc_dictionary_dup_fd`) checked by
     `validateAccessToken:accessType:`. With no token, the result is code 4 -> type 3 + the path.
   - Denied messages: `"accessing another user's preferences requires sufficient permissions to be able to
     read the file"` / `"writing to another user's preferences requires sufficient permissions to write to
     the file"`.
2. Sandbox (`validateSandboxPermissionsForMessage:containerPath:accessType:`):
   `sandbox_check_by_audit_token` for `user-preference-read`/`-write` and `file-read-data`/`file-write-data`.
   The messages say "...requires user-preference-read or file-read-data sandbox access" (with an
   "outside an application's container" variant). pearOS has no sandbox, so it can treat this check as always
   allowed. **[read]**
3. Cloud: the `com.apple.developer.ubiquity-kvstore-identifier` entitlement (or
   `com.apple.private.ubiquity-kvstore-access`, `...additional-kvstore-identifiers`,
   `com.apple.private.trust-defaults-kvstore-identifier`) is needed, else `"'com.apple.developer.ubiquity-
   kvstore-identifier' entitlement needed to use cloud preferences"`. **[read]**

---

## 8. Size threshold, AvoidCache, direct mode

- `CFPreferencesByteCountThreshold` (int64) is attached to a write reply only when the approximate size grew.
  Size = pending bytes + (cached plist length or `fstatat` size)
  (`approximatePlistSizeIncludingPendingChanges @ 0x7ff8030af793`). Value from
  `_CFPrefsDomainSizeAcceptabilityForByteCount @ 0x7ff802f9f626`: `0` when <= 3 MiB (0x300000), `1` when
  <= 4 MiB, `2` above. The client feeds it to `handlePossibleOversizedMessage:forWritingKeys:...` (warn or
  limit). **[read]**
- AvoidCache: see §3.1. The client always sends it together with ShouldWriteSynchronously. That happens when
  `_CFPrefsSynchronizeIsSynchronous`, when the source `avoidsDaemonCache`, or when testing flags are set (it
  can also be random in a stress mode). **[read]**
- Direct mode (`_CFPrefsDirectMode @ 0x7ff802f009b1`, block @ 0x7ff802f00a0a): the client **bypasses
  cfprefsd** when it is cfprefsd itself, when env `__CFPREFERENCES_AVOID_DAEMON` is set, when
  `sandbox_check(pid,"mach-lookup","com.apple.cfprefsd.daemon")` denies, or when the process path starts
  with one of these 12 entries (`____CFPrefsProcessPathRequiresDirectMode_block_invoke @ 0x7ff803094129`,
  table @ 0x7ff840243180): `/System/Library/CoreServices/ReportCrash`, `/usr/sbin/distnoted`,
  `/usr/libexec/trustd`, `/usr/libexec/xpcd`, `/usr/bin/heap`, `/usr/bin/leaks`, `/usr/bin/vmmap`,
  `/usr/local/bin/ddt`, `.../FSEvents.framework/.../fseventsd`, `/usr/local/bin/dsymForUUID`,
  `.../Admin.framework/Resources/userInit`, `/usr/libexec/syspolicyd`. Per-source direct mode also exists
  (`_CFPrefsDirectModeEnabledForDomain @ 0x7ff803097535`, `-[CFPrefsPlistSource _shouldEnableDirectMode]`;
  not analysed). In direct mode the client builds an in-process `CFPrefsDaemon` (role 3,
  `directCFPrefsD`) and runs the same message code locally. It writes files itself and bumps the agent's shmem
  when it is allowed to. **[read]**

---

## 9. Cloud, mirrored, managed (brief)

- **Mirrored** (`CFPDMirroredSource`): current-user `.GlobalPreferences` mirrors the keys `AppleLanguages`
  and `AppleLocale` into a second source (+0x98). A read reply adds `CFPreferencesValidationPropertyList` (the
  mirror's plist data). op 9 returns both paths. **[read]**
- **Cloud** (`CFPDCloudSource`): selected by `CFPreferencesCloudConfig` (configuration plist path) and
  `CFPreferencesCloudStoreIdentifier` (string). It needs an entitlement (§7). `FullCloudSync: true` calls
  `synchronizeWithCloud:replyHandler:`. A non-cloud domain gets `"Domain not cloud-backed"`. Shmem variant 5.
  **[read]**
- **Managed**: path rules are in §5.1, variants 3/4, flush is op 3. A read of a managed source returns nothing
  unless `CFPreferencesIsManaged(domain, ...)` is true (`copyPropertyListWithoutDraining... @ 0x7ff803088499`).
  **[read]**

---

## 10. Checked on the Mac VM (2026-11-28)

Apple's clients against Apple's cfprefsd and against ours (`d/darwin/cfprefsd`, test mode), diffed with
`research/tools/cfprefsd/norm.py` (`cmp.sh`):

- **Same:** the CFPreferences C API probe (`p1`), `defaults write/read/delete`, the disk probe (`p3`) and the
  daemon probe (`p5`) produce the same messages, the same reply keys, the same `CFPreferencesShmemIndex`
  values (for example 2615..2619 for `org.pearos.cfptest`, 1078..1082 for the global domain) and the same files.
  This confirms the slot formula of §3.3 with Apple's `CFHash`.
- **Different but harmless:** Apple's replies can carry `PlistDiff` (pending changes). Ours always merge the
  pending changes first and send the whole dictionary, so the client ends up with the same contents.
- **Seen in the files:** the mirror file `.GlobalPreferences_m.plist` holds `AppleLanguages`/`AppleLocale` plus
  `Sig_<key>` = `"<process>(<pid>): <yyyy-mm-dd hh:mm:ss> (<zone>)"` (for example
  `"UserAccountUpdater(1052): 2026-11-09 08:57:13 (PST)"`). A 0-byte mirror (root's) means no
  `CFPreferencesValidationPropertyList` in the reply.
- **Disk timing:** a new file appears during the write request (sync). A later change appears within about 0.1 s
  in one run and only after the 10 s timer in another (§5.3).
- **Quarantine:** Apple's files carry `com.apple.quarantine` = `0086;<hex time>;com.apple.cfprefsd;`. The stub
  `/usr/sbin/cfprefsd` calls `_qtn_proc_alloc`, `_qtn_proc_set_identifier("com.apple.cfprefsd")`,
  `_qtn_proc_set_flags(6)` and `_qtn_proc_apply_to_self`, and exits when the apply fails. Ours does the same and the
  apply returns 0, but our files get no xattr. The cause was not found.
- **Not done on the Mac:** replacing the session's own agent. That needs SIP off; the GPU VM (reims) has SIP on.

## 11. Open points (not read in this pass)

- `validateAccessToken:accessType:`, `validateSandboxForRead/Write:`: only the outline is known.
- `processEndOfMessageIntendingToRemoveSource:replacingWithTombstone:`: the exact eviction policy for
  sources.
- What the client does with `ByteCountThreshold` 1 and 2 (warn or refuse).
- How `_dirhelper_relative(0, dir)` resolves on macOS. Check on the Mac VM which directory the
  `*.plist.XXXXXXX` temp files appear in.
- Not yet confirmed on the Mac VM: `lsof -p $(pgrep -u $USER cfprefsd)` should show
  `apple.cfprefs.<uid>v1` as a PSXSHM object of 16384 bytes.
