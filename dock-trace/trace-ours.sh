#!/bin/sh
# Trace a Dock built on the Mac VM (default: ~/dock-cocoa/Dock) with the same probes as capture.sh and print the trace:  sh research/dock-trace/trace-ours.sh [binary]
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
D="$(cd "$(dirname "$0")" && pwd)"; BIN="${1:-~/dock-cocoa/Dock}"
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$D/dock.d" alex@localhost:/tmp/dock.d
$M "F=/tmp/ours-trace-\$\$.txt; echo pear | sudo -S -p '' rm -f \$F; echo pear | sudo -S -p '' dtrace -Z -s /tmp/dock.d -c $BIN -o \$F >/dev/null 2>/tmp/dtrace-ours.err; cat \$F; echo pear | sudo -S -p '' rm -f \$F" | sed 's#/Users/alex#/Users/USER#g' | grep -v '^$'
