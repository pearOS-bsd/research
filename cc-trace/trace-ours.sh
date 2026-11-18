#!/bin/sh
# Startup trace of OUR ControlCenter on the Mac VM (same dtrace script as capture.sh): the real job com.apple.controlcenter is replaced by a launchd job com.pearos.controlcenter
# (same MachServices as Apple's plist) that runs ~/cc-cocoa/ControlCenter.app, dtrace -W waits for it.  Prints the trace; restore with  sh cc-switch.sh real
D="$(cd "$(dirname "$0")" && pwd)"
sh "$D/cc-switch.sh" stop >/dev/null 2>&1
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$D/cc.d" alex@localhost:/tmp/cc.d
$M 'F=/tmp/cc-ours-$$.txt; echo pear | sudo -S -p "" rm -f $F; (echo pear | sudo -S -p "" dtrace -Z -W ControlCenter -s /tmp/cc.d -o $F >/dev/null 2>&1 &); sleep 8; launchctl bootstrap gui/501 /tmp/com.pearos.controlcenter.plist; sleep 35; echo pear | sudo -S -p "" pkill dtrace; sleep 1; cat $F; echo pear | sudo -S -p "" rm -f $F' | sed 's#/Users/alex#/Users/USER#g' | grep -v '^$'
