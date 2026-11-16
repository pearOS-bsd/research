#!/bin/sh
# Screenshot of OUR Dock alone on the Mac VM: stops the real Dock (launchctl bootout), runs ~/dock-cocoa/Dock.app for 20 s, takes the picture after 15 s, restores the real Dock
# (bootstrap + kickstart; the job has RunAtLoad false).   sh research/dock-trace/shot-ours.sh out.png     (build first: tar apps/dock-cocoa + dock/dock_layout.* to ~/ and make)
OUT="${1:-ours.png}"
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
$M 'launchctl bootout gui/501/com.apple.Dock.agent 2>&1 | head -1; sleep 2; (cd ~/dock-cocoa && DOCK_WINDOW=20 ./Dock.app/Contents/MacOS/Dock >/tmp/dockrun.out 2>&1 &); sleep 15; screencapture -x /tmp/ours-shot.png; sleep 6; launchctl bootstrap gui/501 /System/Library/LaunchAgents/com.apple.Dock.plist 2>&1 | head -1; launchctl kickstart gui/501/com.apple.Dock.agent 2>&1 | head -1; sleep 3; pgrep -x Dock >/dev/null && echo real-dock-restored || echo REAL-DOCK-NOT-RUNNING'
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null alex@localhost:/tmp/ours-shot.png "$OUT"
