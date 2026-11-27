# TCC: the wire protocol of libTCC and tccd (macOS 26.7.2, x86_64)

Goal: a wire-compatible `tccd` for pearOS (`d/darwin/tccd`), so Apple's TCC client in SkyLight, AppKit, HIServices, IOKit and the apps gets an answer instead of waiting for ever (on pearOS `SLSInitialize -> SLSTCCService::TCCAccessCheck -> TCCAccessPreflight -> tccd_send_message -> xpc_connection_send_message_with_reply_sync` to `com.apple.tccd.system` blocked: our iconservicesagent and the real Dock hung there, `lsquery` hung in `TCCAccessRequest`).

Evidence tags: **[captured]** (recorded on the Mac VM with an interposer or read from its files), **[decompiled]** (Ghidra through REA on `TCC.framework` extracted from the dyld cache, function named), **[inferred]**. Probes: `tools/tcc/` (and `tools/launchservices/probes/xcap.c`, the XPC recorder). Recorded on 2026-11-27, Mac VM macOS 26.7.2 (25G332), SIP on.

## 1. The services and the jobs

| Mach service | job (Mac) | program | domain |
|---|---|---|---|
| `com.apple.tccd.system` | `/System/Library/LaunchDaemons/com.apple.tccd.system.plist` | `/System/Library/PrivateFrameworks/TCC.framework/Support/tccd system` | system (root); `MachServices`, `POSIXSpawnType Adaptive`, `EnablePressuredExit`, `PublishesEvents com.apple.tccd.events` |
| `com.apple.tccd` (+ `com.apple.usernotifications.delegate.com.apple.tccd`) | `/System/Library/LaunchAgents/com.apple.tccd.plist` | `.../tccd` (no argument) | per user; same keys, `WatchPaths /Library/Application Support/com.apple.TCC/MDMOverrides.plist` |

**[captured]** (the plists). Neither job has `RunAtLoad`: both start at the first look-up.

The client chooses the instance by service (`_is_system_service` in libTCC **[decompiled]**); the system services are sent with `XPC_CONNECTION_MACH_SERVICE_PRIVILEGED` (flags 2), the user ones with flags 0 **[captured]**. One connection per request (libTCC creates a connection, sends, cancels).

## 2. The request

Every authorization call sends the same dictionary, with `xpc_connection_send_message_with_reply_sync` (preflight, check) or `..._with_reply` (TCCAccessRequest with a block) **[captured]**:

| key | type | meaning |
|---|---|---|
| `function` | string | always `"TCCAccessRequest"` for TCCAccessPreflight, TCCAccessRequest, TCCAccessCheckAuditToken, TCCAccessPreflightWithAuditToken, TCCAccessRestricted and the tcc_server SPI |
| `service` | string | `kTCCService...` |
| `preflight` | bool | true: only ask (no prompt); false: a request (may prompt) |
| `target_token` | null or data (32 bytes) | null: the caller itself; else the `audit_token_t` of the process asked about (val[5] = pid) |
| `require_purpose` | null or bool | `kTCCAccessCheckOptionPurposeRequired` |
| `background_session` | bool | |
| `TCCD_MSG_ID` | string | `"<pid>.<n>"`: the number of the message of this process (tccd logs it: `AUTHREQ_CTX: msgID=...`) |

The tcc_server SPI (`tcc_server_message_request_authorization`, linked by SkyLight) adds `TCCD_MSG_SPI_VERSION` 2, `TCCD_MSG_REQUEST_TYPE_KEY` 0, `TCC_MSG_REQUEST_AUTHORIZATION_SUBJECT_CREDENTIAL_DICTIONARY_KEY` `{TCCD_MSG_CREDENTIAL_AUTHENTICATOR_TYPE_KEY: 0}`, `TCCD_MSG_MESSAGE_OPTION_REQUEST_USAGE_STRING_POLICY_KEY`, `TCCD_MSG_MESSAGE_OPTION_REQUEST_PROMPT_POLICY_KEY` (1 = do not prompt) and has no `preflight`; the function name is the same and so is the reply **[captured: tools/tcc/tccs.c]**. Its record carries `authorization_right` = `auth_value` and `authorization_reason` = `auth_reason` **[captured]**.

`TCCAccessCopyInformation` sends `{function: "TCCAccessCopyInformation", service, TCCD_MSG_ID}` and reads the array `clients` of the reply; without it the call returns NULL **[decompiled: `___TCCAccessCopyInformation_block_invoke_2`]**. Other function names exist in the client (`TCCAccessCopyInformationForServices`, `TCCAccessSetInternal`, `TCCAccessResetInternal`, `TCCAccessGetOverrides`, `TCCServiceCopyDescriptions`, `TCCExpirationReset`, `TCCGetIdentityForCredential`, `TCCReportUse`, ...) **[decompiled: strings]**; they are management calls that need `com.apple.private.tcc.manager.*` entitlements.

## 3. The reply

The keys that libTCC reads from a reply **[decompiled: `___TCCAccessRequest_block_invoke.157`]**: `abort` (a string: the client then crashes on purpose, `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`, with `problem_key`), `extension` / `generic_extension` (sandbox extensions to consume), `preflight_unknown`, `restricted`, `result`, `do_not_cache` (when false and the call asked for caching, the answer is kept in the process: `_TCCAccessRequest_cache_map`). An XPC error (connection invalid) counts as "denied". TCCAccessPreflight returns 0 (granted) when `result` is true, 2 when `preflight_unknown` is true, else 1 **[captured: return values against the replies]**.

The shapes that tccd sends **[captured]**:

| case | reply |
|---|---|
| allowed (row in TCC.db) | `{result: true, auth_value: 2, auth_reason: 4, auth_version: 1, prompt_type: 1}` (+ `do_not_cache: true`, see below) |
| allowed by entitlement `com.apple.private.tcc.allow` | `auth_value 2, auth_reason 11` (tccd log `AUTHREQ_RESULT: ... authValue=2, authReason=11` for UserEventAgent; the XPC shape is that of the row case **[inferred]**) |
| no decision yet, preflight | `{preflight_unknown: true, auth_value: 1, auth_reason: 5 (system instance) / 0 (user instance), auth_version: 1, prompt_type: 1}` |
| denied (row, or service policy) | `{result: false, auth_value: 0, auth_reason: 4 or 5, auth_version: 1, prompt_type: 1}` |
| a request that may not prompt (no UI session, background) | `{result: false, auth_value: 0, auth_reason: 5, ...}`; with the SPI's prompt policy 1: `auth_reason 10` |
| unknown service name | `{result: false, auth_value: 0, auth_reason: 1, auth_error_code: 2, auth_error_string: "Invalid Service Name: kTCCServiceBogus"}` (no `auth_version`) |
| `target_token` of another process, requester not entitled | `{result: false, auth_value: 0, auth_reason: 1, auth_version: 1, prompt_type: 1, auth_error_code: 3, auth_error_string: "Requestor: TCCDProcess: ... is not entitled to check access for accessor ..."}` (user instance); the system instance answered `{result: false, auth_value: 0, auth_reason: 1, auth_version: 1, prompt_type: 0}` with no error string, even for the caller's own token, except for Accessibility (`AXIsProcessTrusted` sends its own token and gets the normal answer) |
| a function the caller may not use, an unknown function, no `function` | `{}` (the empty dictionary) |

`do_not_cache: true` came only with replies to processes whose responsible process is another one (the probes under ssh: TCC attributes them to `/usr/libexec/sshd-keygen-wrapper`); the same probes as a launchd job (their own responsible process) got the same answers without `do_not_cache` **[captured]**, so the key means "this answer is about another code identity" **[inferred]**.

Authorization values (the `auth_value` column of TCC.db): 0 denied, 1 unknown, 2 allowed, 3 limited. Reasons seen: 0 none, 1 error, 3 user set, 4 system set, 5 service policy, 10 preflight unknown / no prompt, 11 entitled.

## 4. What a Mac answers without a row (default per service)

Every name in the strings of `tccd` sent with TCCAccessPreflight (ssh session; `tools/tcc` + xcap) **[captured]**:

- system instance (`com.apple.tccd.system`): Accessibility, ListenEvent, PostEvent, ScreenCapture, RemoteDesktop: unknown (1/5); DeveloperTool, SystemPolicyAllFiles: denied by service policy (0/5); EndpointSecurityClient: invalid on this Mac.
- user instance: allowed by service policy (2/5): Liverpool, Ubiquity, UserTracking, WebKitIntelligentTrackingPrevention; denied by service policy (0/5): Facebook, LinkedIn, Pasteboard, ShareKit, SinaWeibo, TencentWeibo, Twitter; unknown (1/0): AddressBook, All, AppleEvents, AudioCapture, BluetoothAlways, Calendar, Camera, ContactsFull, ContactsLimited, EnergyKitGuidance, ExternalCameraMedia, FileProviderDomain, FileProviderPresence, FocusStatus, GameCenterFriends, MediaLibrary, Microphone, Motion, Photos, PhotosAdd, Prototype3Rights, Prototype4Rights, Reminders, Siri, SpeechRecognition, SystemPolicyAppBundles, SystemPolicyAppData, SystemPolicyDesktopFolder, SystemPolicyDeveloperFiles, SystemPolicyDocumentsFolder, SystemPolicyDownloadsFolder, SystemPolicyNetworkVolumes, SystemPolicyRemovableVolumes, SystemPolicySysAdminFiles, VirtualMachineNetworking, VoiceBanking, WebBrowserPublicKeyCredential, Willow.
- invalid on macOS (`auth_error_code 2`): the iOS / watchOS services that tccd also knows (Accessory*, Calls, Contactless*, CrashDetection, ExposureNotification*, FaceID, FallDetection, FinancialData, KeyboardNetwork, MicrophoneInjection, MSO, NearbyInteraction, PKPassLibraryBackgroundAddPasses, SecureElementAccess, SensorKit*, BluetoothPeripheral, BluetoothWhileInUse), and Location (locationd's).

(The ssh session has rows for Accessibility, ScreenCapture and SystemPolicyAllFiles; for the services with rows the defaults above come from the launchd-job run.)

## 5. Which clients ask what at start-up

- `SLSInitialize` (any program that connects to the window server, e.g. `CGMainDisplayID`): one preflight of `kTCCServiceListenEvent` to `com.apple.tccd.system` **[captured: tools/tcc/cgt.m cgs]**. This is the call our iconservicesagent and the Dock waited on.
- `CGPreflightScreenCaptureAccess`: ScreenCapture; `CGPreflightPostEventAccess`: PostEvent; `CGPreflightListenEventAccess` and `IOHIDCheckAccess`: ListenEvent; `AXIsProcessTrusted`: Accessibility with the own `target_token` (twice) **[captured]**.
- Entitlements of the first-party programs **[captured: codesign -d --entitlements]**: Dock `com.apple.private.tcc.allow` = PostEvent, AppleEvents, FileProviderDomain, ScreenCapture, SystemPolicy{Desktop,Documents,Downloads}Folder, SystemPolicy{Network,Removable}Volumes; iconservicesagent: SystemPolicyAllFiles; Finder: ScreenCapture, SystemPolicyAllFiles, AddressBook, Calendar, Reminders, PostEvent, AppleEvents, SystemPolicyRemovableVolumes, Accessibility; ControlCenter: BluetoothPeripheral, ScreenCapture, AddressBook, Calendar, Microphone, SystemPolicyAppData; WindowServer: Accessibility, ListenEvent, PostEvent, ScreenCapture (and `com.apple.private.tcc.manager.check-by-audit-token` for the same four); SystemUIServer: Calendar, Reminders, AddressBook, AppleEvents, ScreenCapture, Microphone, SystemPolicyRemovableVolumes.

## 6. TCC.db

SQLite, `/Library/Application Support/com.apple.TCC/TCC.db` (system instance) and `~/Library/Application Support/com.apple.TCC/TCC.db` (user instance), `admin.version` = 32 **[captured: .schema]**. Tables: `admin(key, value)`, `policies`, `active_policy`, `access`, `access_overrides`, `expired`, `integrity_flag`. `access`: `service, client, client_type (0 bundle id, 1 absolute path), auth_value, auth_reason, auth_version, csreq BLOB, policy_id, indirect_object_identifier_type, indirect_object_identifier DEFAULT 'UNUSED', indirect_object_code_identity BLOB, flags, last_modified, pid, pid_version, boot_uuid DEFAULT 'UNUSED', last_reminded`, primary key `(service, client, client_type, indirect_object_identifier)`.

## 7. What our tccd does (d/darwin/tccd)

Order: invalid service -> `com.apple.private.tcc.allow` of the subject's code signature (2/11) -> a row of `access` for the signing identifier (client_type 0) or the path (client_type 1) -> the default of section 4 (a request that would prompt is denied: 0/5, or 0/10 with the SPI's prompt policy 1; there is no consent UI on pearOS yet). `target_token` of another process needs `com.apple.private.tcc.manager.check-by-audit-token` for the service (else the error-3 reply). Unknown functions get `{}`; every message with a reply port gets a reply. The subject is the requesting process itself (pearOS has no responsible-process tracking), so `do_not_cache` is never sent.

Not done: `csreq` is not checked (a row matches by identifier or path alone), AppleEvents rows with an indirect object are not matched, no consent prompt, no writes (TCCAccessSet/Reset, the `tccutil` calls), no `clients` for TCCAccessCopyInformation, no `com.apple.tccd.events`, the self-token quirk of the system instance (section 3) is not reproduced (the own token is answered normally).

Checked: Apple's libTCC on the Mac against our daemon (redirected names): the return values of TCCAccessPreflight, TCCAccessCheckAuditToken, TCCAccessRequest (block), the tcc_server SPI and the CG/AX/IOHID calls equal those of Apple's tccd for the same process as a launchd job (section 4); `tccd -check` reads the Dock's identifier and entitlements and a TCC.db row. On the FreeBSD lab VM (darwinator): our launchd starts both jobs on demand and the Mac's libTCC (from the dyld cache) gets the same answers. Reading TCC.db on pearOS fails for now: libsqlite3 gets `disk I/O error` because darwinator answers EINVAL to `fcntl` F_OFD_SETLK/F_OFD_GETLK (90-92) and F_SETCONFINED (95), which Apple's SQLite uses; tccd then answers from rules 1, 2 and 4.
