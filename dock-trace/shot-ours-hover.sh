#!/bin/sh
# Screenshot of OUR Dock with the pointer over a tile (stops the real Dock, restores it):  sh shot-ours-hover.sh out.png X Y      (needs ~/bisect/mouse built from mouse.c on the Mac)
OUT="${1:-ours-hover.png}"; X="${2:-168}"; Y="${3:-765}"
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
$M "if launchctl print gui/501/com.pearos.dock >/dev/null 2>&1; then
  launchctl kickstart -k gui/501/com.pearos.dock; sleep 14; ~/bisect/mouse 640 400; sleep 0.5; ~/bisect/mouse $X $Y; sleep 1.5; screencapture -x /tmp/ours-hover.png; ~/bisect/mouse 640 400; echo our-dock-left-running
else
  launchctl bootout gui/501/com.apple.Dock.agent 2>&1 | head -1; sleep 2; (cd ~/dock-cocoa && DOCK_WINDOW=26 ./Dock.app/Contents/MacOS/Dock >/tmp/dockrun.out 2>&1 &); sleep 14; ~/bisect/mouse 640 400; sleep 0.5; ~/bisect/mouse $X $Y; sleep 1.5; screencapture -x /tmp/ours-hover.png; ~/bisect/mouse 640 400; sleep 8; launchctl bootstrap gui/501 /System/Library/LaunchAgents/com.apple.Dock.plist 2>&1 | head -1; launchctl kickstart gui/501/com.apple.Dock.agent 2>&1 | head -1; sleep 3; pgrep -x Dock >/dev/null && echo real-dock-restored || echo REAL-DOCK-NOT-RUNNING
fi"
scp -q -P 2229 -i "$HOME/fbsd-vm/id_ed25519" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null alex@localhost:/tmp/ours-hover.png "$OUT"
