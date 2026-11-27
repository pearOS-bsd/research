# opendirectoryd and distnoted probes (Mac VM)

Programs that call Apple's libsystem_info (getpwuid & co, mbr_*) and CoreFoundation's distributed notification center, so that the conversation with `opendirectoryd` / `distnoted` can be recorded (`odcap.dylib`) or pointed at ours (`IS_REDIRECT`).  Findings: `docs/OPENDIRECTORY-DISTNOTED-WIRE.md`.

Build on the Mac:

    clang -dynamiclib odcap.c -o odcap.dylib
    clang odt.c -o odt
    clang odraw.c -o odraw
    clang dnt.c -o dnt -framework CoreFoundation
    clang -fobjc-arc dnt2.m -o dnt2 -framework Foundation

- `odt pwuid:N pwnam:NAME grgid:N grnam:NAME gl:NAME pwent grent u2u:UID g2u:GID n2u:NAME gn2u:NAME uu2id:UUID u2n:UID ck:UID:GID cs:UID:SERVICE`
- `odraw SERVICE RPC [key=int|key=s:string|key=u:UUID ...]`: a hand-made pipe request (`-` = no rpc_name).
- `dnt obs NAME [OBJECT|-] [SECONDS] [SB]`, `dnt post NAME [OBJECT|-] [k=v ...]` (DNT_FLAGS = post options), `dnt two NAME OBJECT`, `dnt2` (Foundation: object filter, userInfo, suspend, PostToAllSessions).

Record: `DYLD_INSERT_LIBRARIES=./odcap.dylib ./odt pwuid:501` (lines `ODCAP pipe_request/pipe_reply/send/event`).
Against our daemons: jobs `com.pearos.t.od` (LaunchDaemon, root: `opendirectoryd -v libinfo=com.pearos.t.od.libinfo membership=com.pearos.t.od.membership passwd=... group=... master=...`), `com.pearos.t.dn` (LaunchAgent: `distnoted agent=com.pearos.t.dn.U super=com.pearos.t.dn.0`), `com.pearos.t.dnd` (LaunchDaemon: `distnoted daemon=com.pearos.t.dn.1 agents=com.pearos.t.dn.0`), then `IS_REDIRECT=com.apple.system.opendirectoryd.libinfo=com.pearos.t.od.libinfo,com.apple.system.opendirectoryd.membership=com.pearos.t.od.membership,com.apple.distributed_notifications@Uv3=com.pearos.t.dn.U ODCAP_QUIET=1 DYLD_INSERT_LIBRARIES=./odcap.dylib ./odt ...`.
FreeBSD lab VM: `labtest.sh` (our launchd + the job plists of d, the probes copied from the Mac).
