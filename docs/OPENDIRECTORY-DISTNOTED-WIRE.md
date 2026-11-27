# opendirectoryd (libinfo, membership) and distnoted: the wire protocols

macOS 26.7.2 (25G332), Mac VM, 2026-11-27.  Tags: **[captured]** = recorded on the Mac with Apple's client and Apple's daemon; **[decompiled]** = read in Apple's binary (Ghidra through rea) or in Apple's open source Libinfo; **[inferred]** = our conclusion, not observed.
Tools (all ours, BSD-2-Clause): `research/tools/opendirectory/` — `odcap.c` (DYLD_INSERT_LIBRARIES interposer: logs xpc pipe requests/replies, connection sends and incoming events; `IS_REDIRECT=from=to` renames services for `xpc_pipe_create` and `xpc_connection_create_mach_service`), `odt.c` (libinfo / mbr_* calls), `odraw.c` (hand-made pipe requests), `dnt.c` (CFNotificationCenter distributed center), `dnt2.m` (NSDistributedNotificationCenter).
Implementations: `d/darwin/opendirectoryd`, `d/darwin/distnoted`.

## 1. opendirectoryd: libinfo and membership

### Transport
- libsystem_info's `_od_rpc_call` (Libinfo `lookup.subproj/ds_module.c`) opens `xpc_pipe_create("com.apple.system.opendirectoryd.libinfo", 0xa)` (XPC_PIPE_PRIVILEGED | XPC_PIPE_PROPAGATE_QOS); the membership API (`membership.subproj/membership.c`) opens `com.apple.system.opendirectoryd.membership` the same way **[captured: `pipe_create ... flags=0xa`]**.
- Request: a dictionary with `rpc_name` (string), `rpc_version` (int64 2) and the keys of the call; `xpc_pipe_routine` waits for the reply **[captured]**.
- The client keeps the reply only when the audit token of the reply's sender has uid 0 (`_valid_token`) **[decompiled: Libinfo]**: the server runs as root.
- Every reply carries `rpc_version` 2 **[captured]**.
- A call the server does not serve (unknown `rpc_name`, no `rpc_name`, look-ups by key of hosts/services/protocols/rpc/networks/aliases/fstab/mac, `getnetgrent`, `innetgr`): no reply; `xpc_pipe_routine` returns 5 (EIO) at once **[captured: `odraw ... bogus` -> `rc 5`]**.  Our daemon releases the request without a reply (its reply right dies), which gives the client the same EIO **[captured against ours]**.
- Lists that are not users or groups (`getservent`, `getprotoent`, `getrpcent`, `getnetent`, `alias_getent`, `getfsent`): the reply `{rpc_version 2}` with no `result` **[captured]**.
- On the Mac the job also has `com.apple.system.DirectoryService.libinfo_v1`, `...membership_v1`, `com.apple.system.opendirectoryd.api`, `com.apple.private.opendirectoryd.rpc`, `com.apple.opendirectoryd.osWatchdog` (plist) — the libinfo of macOS 26 does not use them for the calls below **[captured: only the two pipes were opened]**.

### libinfo calls **[captured]**
| rpc_name | request keys | reply |
|---|---|---|
| getpwuid | `uid` int64 | `pw_name pw_passwd pw_uid(int64) pw_gid(int64) pw_dir pw_shell pw_gecos pw_uuid(uuid)` |
| getpwnam | `name` string | same |
| getpwuuid | `uuid` uuid | same |
| getgrgid | `gid` int64 | `gr_name gr_passwd("*") gr_gid(int64) gr_uuid(uuid) gr_mem(array of strings)` |
| getgrnam | `name` | same |
| getgruuid | `uuid` | same |
| getgrouplist (also initgroups) | `name`, `ngroups` (65) | `groups` (data: int32 little-endian array), `count` (int64) |
| getpwent | — | `result`: array of dicts `pw_name pw_passwd pw_uid pw_gid pw_dir pw_shell pw_gecos`, **ids as strings** ("501"), no uuid |
| getgrent | — | `result`: array of dicts `gr_name gr_passwd gr_gid(string) gr_mem` |

- No `pw_class`, `pw_change`, `pw_expire` in replies (the client fills "" and 0).
- `pw_passwd`: "********" for an account with a password (alex), "*" otherwise (root, the _ accounts).
- Not found: `{error 2, error_desc "record not found"}`.  A missing or mistyped key (`uid` as a string): `{error 22, error_desc "<missing or invalid type>"}`.
- getgrouplist of an unknown user: `{count 1, groups = [-1]}` (the client then returns basegid and -1).
- Mac example: `getgrouplist alex` -> count 16, `12 20 61 79 80 81 701 33 98 100 204 250 395 398 399 400` (nested groups: everyone 12 and localaccounts 61 are not in `gr_mem`).  getgrgid 20 (staff) gr_mem = [root] only.
- `getpwnam` after `getpwuid` of the same user is served from libinfo's cache (no request).

### membership calls **[captured]**
| rpc_name | request keys | reply |
|---|---|---|
| mbr_identifier_translate | `type` int64, `identifier` data, `requesting` int64 | `identifier` data, `rectype` (1 user, 2 group) |
| mbr_check_membership | `user_idtype` 6, `user_id` 16-byte data, `group_idtype` 6, `group_id`, `refresh` bool | `ismember` bool |
| mbr_check_service_membership | `user_idtype` 6, `user_id`, `service` | `ismember` bool, or `error 2` when the group `com.apple.access_<service>` does not exist |
| mbr_cache_flush | — | `{}` |
| mbr_set_identifier_ttl | `type`, `identifier`, `ttl` | `{}`; without identifier `error 2` |

- Id types (membership.h): 0 UID, 1 GID, 4 USERNAME, 5 GROUPNAME, 6 UUID, 30 UID_OR_GID, 31 NAME.  UID/GID identifiers are 4-byte little-endian; names are sent without NUL and returned **with** NUL (`alex\0`, 5 bytes).
- `mbr_uuid_to_id` sends requesting 30 and gets a 4-byte id + rectype.
- `mbr_uid_to_uuid(0)` and UUIDs with the FFFFEEEE prefix are answered in the client (no request) **[captured; decompiled: Libinfo `mbr_identifier_translate` shortcut]**.
- UUIDs: alex = `BF24CC3D-C44B-414F-8834-39359D9AE676` (random GeneratedUID of an account made by Setup); root/daemon/nobody/_www = `FFFFEEEE-DDDD-CCCC-BBBB-AAAA<uid>`; wheel/staff/admin/... = `ABCDEFAB-CDEF-ABCD-EFAB-CDEF<gid>` (`dscl . -read /Groups/X GeneratedUID`).  An unknown uid 4242 -> `FFFFEEEE-...-AAAA00001092` rectype 1; an unknown gid 4242 -> **`AAAABBBB-CCCC-DDDD-EEEE-FFFF00001092`** rectype 2; an unknown name or uuid -> `error 2`; a missing identifier -> `{error 22, error_desc "invalid size for identifier"}`; check_membership without keys -> `error 22`.
- check_membership of an unknown user (FFFFEEEE uuid of uid 4242) -> `ismember false`, no error.

### What pearOS answers (decisions)
- The accounts are FreeBSD's `/etc/passwd`, `/etc/group`; `/etc/master.passwd` (root only) decides "********" vs "*".
- The files have no GeneratedUID: users get `FFFFEEEE-...<uid>`, groups of `/etc/group` `ABCDEFAB-...<gid>` — the derivation Apple uses for its own accounts and Libinfo's fallback without opendirectoryd; ids in no file get the Mac's unknown answers above **[inferred: a stored random GeneratedUID like alex's would need a store pearOS does not have]**.
- Membership is flat (primary group + `gr_mem`); the Mac's implicit everyone/localaccounts membership is not added because those groups are not in the FreeBSD files.

## 2. distnoted

### Services and jobs **[captured: launchctl, plists]**
- `com.apple.distnoted.xpc.agent`: `/usr/sbin/distnoted agent`, `com.apple.distributed_notifications@Uv3`, one per user (LimitLoadToSessionType Background; 17 instances on the Mac VM, one per uid).
- `com.apple.distnoted.xpc.daemon`: `/usr/sbin/distnoted daemon`, user `_distnote`, services `com.apple.distributed_notifications@0v3` and `@1v3`.
- CoreFoundation strings next to the client code: `com.apple.distributed_notifications@1v3`, `@Uv3`, `/usr/sbin/distnoted`, `System`, `LoginWindow` **[decompiled: dyld cache strings]**.  A process of the user (also root through sudo in the user's session) connects to `@Uv3` **[captured]**.  The daemon's binary carries the entitlement name `com.apple.private.distributed-notification-0v3` (the agents' service) **[decompiled]**.

### Client -> server messages (one-way, `xpc_connection_send_message`, no reply) **[captured]**
- `{method "register", version 1, name, object, token (uint64), options (uint64), pn (path of the program)}`.  Any name = the string `kCFNotificationAnyName`, any object = `kCFNotificationAnyObject`.  Tokens are the client's: `(n << 32) | (n - 1)` (4294967296, 8589934593 ...).
- options: suspension behavior in the low 4 bits — DeliverImmediately -> 1, Drop -> 2, Coalesce -> 4, Hold -> 8; `0x80000` from CFNotificationCenterAddObserver, `0x40000` from NSDistributedNotificationCenter (default Coalesce: 262148).  The daemon keeps `options & 0xf` **[decompiled: `(uVar5 & 0xf) + 0x20000` passed to `_CFXNotificationRegistrarAddRemoteToken`]**.
- `{method "unregister", version 1, tokens: [uint64...]}` (one per removed observer).
- `{method "post", version 1, name, object (kCFNotificationAnyObject when NULL), userinfo (data: binary plist, only when there is one), options}`: options are the post options (1 kCFNotificationDeliverImmediately, 2 kCFNotificationPostToAllSessions; the NS `deliverImmediately:YES` -> 1, `NSNotificationPostToAllSessions` -> 2).
- `{method "suspend", version 1}` / `{method "unsuspend", version 1}` (NSDistributedNotificationCenter `suspended`).

### Server -> client **[captured]**
- `{method "post_token", version 1, token, name, object, userinfo?}` for **each matching registration** of the client (two registrations of one process that both match -> two messages); the object is the post's string (a post with no object arrives as `kCFNotificationAnyObject`).

### Rules of Apple's distnoted **[decompiled: `/usr/sbin/distnoted` 26.7.2, CoreFoundation-5026.6.7.5; handler at 0x1000026cd, `ClientOfLocalNoteServer postNotification:object:token:options:immediate:userInfo:` at 0x100003507]**
- Every method checks `version == 1`.
- register: name/object strings -> CFStrings (the any-strings become the CF constants); a registration with any name **and** any object is ignored when `sandbox_check_by_reference(ref, NULL)` returns 0 (an unsandboxed client) **[captured: an all-names observer, also as root, never got anything]**.  A registration with any name and a given object is kept.
- post: userinfo refused for a sandboxed client without `distributed-notification-post`; `options & 2` -> copy of the message with `method "post_all"` sent to the daemon (`ClientOfSuperNoteServer sendMessage:`), nothing local; else the seven `Apple*PreferencesChangedNotification` names post `com.apple.distnote.locale_changed`, `com.apple.MCX._managementStatusChangedForDomains` and `com.apple.CFPreferences._domainsChangedExternally` post their own notify name; then every client gets `handlePost:userInfo:`.
- postNotification per registration: if the post is not immediate, the registration not DeliverImmediately and the client suspended: Hold (8) -> queued; Coalesce (4) -> queued after removing a queued post of the same name and object; Drop -> nothing.  Otherwise: an immediate post (or registration) first sends the queue, then the message.  unsuspend sends the queue.
- Other methods: `monitor`, `dump` (diagnostics).
- Unknown: the message the daemon sends back to the agents for a post_all, and how an agent introduces itself **[not found; ours: the daemon sends `{method "post", ...options without 2}` to every peer of `@0v3`, an agent sends `{method "unsuspend", version 1}` when it connects]** — both ends are ours on pearOS.

### Checked against ours
Same probe runs against Apple's distnoted and ours (Mac, redirected names; FreeBSD lab VM with our launchd): two observers in one process (`dnt two`) get 2 deliveries for an object post and 1 for an object-less post; an observer for another object and an all-names observer get none; NS: object filter, userInfo with NSNumber and NSData, suspended + PostToAllSessions -> delivered after unsuspend through agent -> daemon -> agent.
