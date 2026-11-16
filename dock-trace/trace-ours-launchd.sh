#!/bin/sh
# Trace a Dock built on the Mac VM when started BY LAUNCHD in the user's GUI domain (like the real one): the way a process is started changes the services it touches.
#   sh research/dock-trace/trace-ours-launchd.sh [binary]      (the real Dock keeps running; only the new process named Dock is traced: dtrace -W Dock prints both if the real one restarts)
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
D="$(cd "$(dirname "$0")" && pwd)"; BIN="${1:-/Users/alex/dock-cocoa/Dock.app/Contents/MacOS/Dock}"
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$D/dock.d" alex@localhost:/tmp/dock.d
$M "cat > /tmp/com.pearos.dock.test.plist <<EOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict>
<key>Label</key><string>com.pearos.dock.test</string><key>Program</key><string>$BIN</string><key>RunAtLoad</key><true/><key>POSIXSpawnType</key><string>App</string></dict></plist>
EOF
launchctl bootout gui/501/com.pearos.dock.test 2>/dev/null
F=/tmp/ours-trace-\$\$.txt; echo pear | sudo -S -p '' rm -f \$F; (echo pear | sudo -S -p '' dtrace -Z -W Dock -s /tmp/dock.d -o \$F >/dev/null 2>&1 &); sleep 3
launchctl bootstrap gui/501 /tmp/com.pearos.dock.test.plist; sleep 8
launchctl bootout gui/501/com.pearos.dock.test 2>/dev/null; echo pear | sudo -S -p '' pkill dtrace; sleep 1; cat \$F; echo pear | sudo -S -p '' rm -f \$F" | sed 's#/Users/alex#/Users/USER#g' | grep -v '^$'
