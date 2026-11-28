#!/bin/sh
# Which ControlCenter runs on the Mac VM:  sh cc-switch.sh ours | real | stop
#   ours: launchd job com.pearos.controlcenter (~/cc-all/controlcenter-cocoa/ControlCenter.app, KeepAlive, same MachServices as Apple's com.apple.controlcenter); Apple's job is booted out
#   stop: both booted out (used before a trace)      real: back to Apple's job.  Nothing under /System is touched.
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
PL='cat > /tmp/com.pearos.controlcenter.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>Label</key><string>com.pearos.controlcenter</string><key>Program</key><string>/Users/alex/cc-all/controlcenter-cocoa/ControlCenter.app/Contents/MacOS/ControlCenter</string>
<key>RunAtLoad</key><true/><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict><key>ProcessType</key><string>App</string><key>ThrottleInterval</key><integer>1</integer>
<key>LimitLoadToSessionType</key><array><string>Aqua</string></array>
<key>StandardErrorPath</key><string>/tmp/pearos-cc.err</string>
<key>MachServices</key><dict><key>com.apple.controlcenter.ccutil</key><dict/><key>com.apple.SystemBannerService</key><dict/><key>com.apple.SystemBanner</key><dict/>
<key>com.apple.controlcenter.controlcentermodule</key><dict/><key>com.apple.controlcenter.show.toggles</key><dict><key>HideUntilCheckIn</key><true/></dict><key>com.apple.controlcenter.statusitems</key><dict/></dict></dict></plist>
EOF'
case "$1" in
ours) $M "$PL"'
launchctl bootout gui/501/com.pearos.controlcenter 2>/dev/null; launchctl bootout gui/501/com.apple.controlcenter 2>/dev/null; launchctl bootout gui/501/com.pearos.ccdump 2>/dev/null; sleep 2; launchctl bootstrap gui/501 /tmp/com.pearos.controlcenter.plist 2>&1 | head -1; sleep 4; pgrep -lx ControlCenter';;
stop) $M "$PL"'
launchctl bootout gui/501/com.pearos.controlcenter 2>/dev/null; launchctl bootout gui/501/com.apple.controlcenter 2>/dev/null; sleep 1; pgrep -lx ControlCenter';;
real) $M 'launchctl bootout gui/501/com.pearos.controlcenter 2>/dev/null; sleep 1; launchctl bootstrap gui/501 /System/Library/LaunchAgents/com.apple.controlcenter.plist 2>&1 | head -1; launchctl kickstart gui/501/com.apple.controlcenter 2>&1 | head -1; sleep 4; pgrep -lx ControlCenter';;
*) echo "usage: sh cc-switch.sh ours|real|stop"; exit 2;;
esac
