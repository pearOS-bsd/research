#!/bin/sh
# Trace a Dock built on the Mac VM (default: ~/dock-cocoa/Dock) with the same probes as capture.sh and print the trace:  sh research/dock-trace/trace-ours.sh [binary]
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
D="$(cd "$(dirname "$0")" && pwd)"; BIN="${1:-~/dock-cocoa/Dock}"
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$D/dock.d" alex@localhost:/tmp/dock.d
$M "echo pear | sudo -S -p '' dtrace -s /tmp/dock.d -c $BIN -o /tmp/ours-trace.txt >/dev/null 2>&1; cat /tmp/ours-trace.txt" | sed 's#/Users/alex#/Users/USER#g' | grep -v '^$'
