#!/bin/sh
# Which Dock runs on the Mac VM:   sh dock-switch.sh ours     (our ~/dock-cocoa/Dock.app as a launchd job com.pearos.dock, KeepAlive; the real Dock is booted out)
#                                  sh dock-switch.sh real     (back to Apple's Dock: our job removed, the real job bootstrapped and kicked)
# Build ours first (tar apps/dock-cocoa + dock/dock_layout.* to ~/ and make).  Nothing under /System is touched.
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
case "$1" in
ours) $M 'cat > /tmp/com.pearos.dock.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>Label</key><string>com.pearos.dock</string><key>Program</key><string>/Users/alex/dock-cocoa/Dock.app/Contents/MacOS/Dock</string>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ProcessType</key><string>Interactive</string><key>ThrottleInterval</key><integer>1</integer>
<key>StandardErrorPath</key><string>/tmp/pearos-dock.err</string>
<key>MachServices</key><dict><key>com.apple.dock.server</key><dict><key>HideUntilCheckIn</key><true/></dict></dict></dict></plist>
EOF
launchctl bootout gui/501/com.pearos.dock 2>/dev/null; launchctl bootout gui/501/com.apple.Dock.agent 2>/dev/null; sleep 2; launchctl bootstrap gui/501 /tmp/com.pearos.dock.plist 2>&1 | head -1; sleep 4; launchctl print gui/501/com.pearos.dock 2>&1 | grep -E "state =|pid ="; ~/bisect/wl Dock | head -3';;
real) $M 'launchctl bootout gui/501/com.pearos.dock 2>/dev/null; sleep 1; launchctl bootstrap gui/501 /System/Library/LaunchAgents/com.apple.Dock.plist 2>&1 | head -1; launchctl kickstart gui/501/com.apple.Dock.agent 2>&1 | head -1; sleep 4; pgrep -lx Dock; launchctl print gui/501/com.apple.Dock.agent 2>&1 | grep -E "state ="';;
*) echo "usage: sh dock-switch.sh ours|real"; exit 2;;
esac
