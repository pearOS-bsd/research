# Trace of the real Dock (what ours must reproduce)

`real-dock-startup-macos26.7.2.txt`: the startup of `Dock` on macOS 26.7.2 (x86_64, SIP off), captured with `capture.sh` (dtrace). Line kinds: `LOOKUP` (bootstrap look-up), `CHECKIN` (the service the Dock provides), `XPCSVC` (xpc connection to a Mach service), `PREF` (a preference key read), `OPEN`/`OPENAT` (files). 175 to 250 lines depending on the run; the file includes the dyld phase.
Known limits: `fs_usage` does not start on this VM (`ktrace_start: Invalid argument`); some dtrace actions drop addresses that are not mapped yet ("invalid address"), so the trace can miss a few events; the run is one startup, not a session with clicks.
Findings summary: `docs/development/DOCK-REPLACEMENT.md`.

## Comparing
`python3 compare.py REAL.txt OURS.txt [--order] [--all-opens]` prints, per kind, what ours lacks (`-`) and has extra (`+`); exit 1 on any difference. Checked 2026-11-16: two captures of the real Dock give the same sets for every kind, and the same order for LOOKUP / CHECKIN / XPCSVC / PREF; the order of file opens varies (so `--order` ignores OPEN). A trace with a service removed and a fake one added is reported as different.
