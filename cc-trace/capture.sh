#!/bin/sh
# Trace the startup of the real ControlCenter on the Mac VM with dtrace (root through sudo, password pear), without touching /System:
#   sh research/cc-trace/capture.sh > startup.txt
# It waits for a ControlCenter process (dtrace -W), kills the running ControlCenter (launchd starts it again) and records for 25 s:
#   LOOKUP / CHECKIN (bootstrap), XPCSVC (xpc_connection_create_mach_service), PREF (CFPreferencesCopyAppValue: the key), OPEN / OPENAT (files).
# NOTE: dtrace -o APPENDS to an existing file, so every run uses a fresh file name (a stale file once contaminated the results).
# Compare two such traces (ours and the real one) with: sort -u both, then diff.  The Mac's user name is replaced by USER.
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
D="$(cd "$(dirname "$0")" && pwd)"
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$D/cc.d" alex@localhost:/tmp/cc.d
$M 'F=/tmp/cc-trace-$$.txt; echo pear | sudo -S -p "" rm -f $F; (echo pear | sudo -S -p "" dtrace -Z -W ControlCenter -s /tmp/cc.d -o $F >/dev/null 2>/tmp/dtrace-$$.err &); sleep 8; launchctl kickstart -k gui/501/com.apple.controlcenter; sleep 35; echo pear | sudo -S -p "" pkill dtrace; sleep 1; cat $F; echo pear | sudo -S -p "" rm -f $F' | sed 's#/Users/alex#/Users/USER#g' | grep -v '^$'
