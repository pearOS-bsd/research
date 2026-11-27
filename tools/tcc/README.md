# TCC probes (Mac VM)

Programs that call Apple's libTCC (TCC.framework) so the XPC conversation with `tccd` can be recorded (with `tools/launchservices/probes/xcap.c`) or pointed at our `tccd` (with `IconServices/test/redirect.c`). Findings: `docs/TCC-WIRE.md`.

Build on the Mac:

    clang tcct.c -o tcct -framework CoreFoundation -F/System/Library/PrivateFrameworks -framework TCC
    clang tccs.c -o tccs -framework CoreFoundation -F/System/Library/PrivateFrameworks -framework TCC
    clang raw.c -o raw
    clang -fobjc-arc cgt.m -o cgt -framework Cocoa -framework ApplicationServices -framework IOKit
    clang -dynamiclib ../launchservices/probes/xcap.c -o xcap.dylib

- `tcct OP SERVICE...`: OP = `pre` (TCCAccessPreflight), `req` (TCCAccessRequest with a reply block), `chk` (TCCAccessCheckAuditToken with the own token), `pat` (TCCAccessPreflightWithAuditToken), `res` (TCCAccessRestricted), `inf` (TCCAccessCopyInformation).
- `tccs SERVICE...`: the tcc_server SPI (`tcc_server_message_request_authorization`, what SkyLight links).
- `raw TCCD-SERVICE FUNCTION[:SERVICE]...`: hand-made messages (`-` = no "function" key), prints the replies.
- `cgt [cgs|app|sc|le|pe|ax|hid|all]`: the public checks (CGMainDisplayID = SLSInitialize, CGPreflight*Access, AXIsProcessTrusted, IOHIDCheckAccess).

Record: `DYLD_INSERT_LIBRARIES=./xcap.dylib ./tcct pre kTCCServiceListenEvent`.  Without the grants of the ssh session (the responsible process is `sshd-keygen-wrapper`, which has rows in TCC.db): run it as a launchd job (`launchctl submit -l com.pearos.t.tccprobe -o OUT -e OUT -- script.sh`).
Against our daemon: jobs `com.pearos.t.tccd.system` (LaunchDaemon, root) / `com.pearos.t.tccd` (LaunchAgent) running `tccd system=com.pearos.t.tccd.system` / `tccd user=com.pearos.t.tccd`, then `IS_REDIRECT=com.apple.tccd.system=com.pearos.t.tccd.system,com.apple.tccd=com.pearos.t.tccd DYLD_INSERT_LIBRARIES=redirect.dylib ./tcct pre ...`.
