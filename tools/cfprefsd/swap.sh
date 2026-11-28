# Mac VM: which cfprefsd agent serves the user's session (user/<uid> domain): sh swap.sh ours | apple | status
U=$(id -u); L=com.apple.cfprefsd.xpc.agent; S() { echo pear | sudo -S -p "" "$@"; }
case "$1" in
ours)
  S mkdir -p /usr/local/libexec; S cp ~/cfpd/out/cfprefsd /usr/local/libexec/cfprefsd-pearos; S codesign -f -s - /usr/local/libexec/cfprefsd-pearos 2>/dev/null
  cat > ~/cfpd/$L.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$L</string>
<key>LimitLoadToSessionType</key><string>Background</string>
<key>MachServices</key><dict><key>com.apple.cfprefsd.agent</key><true/></dict>
<key>ProgramArguments</key><array><string>/usr/local/libexec/cfprefsd-pearos</string><string>agent</string></array>
<key>EnableTransactions</key><true/><key>DrainMessagesOnFailedInit</key><true/><key>POSIXSpawnType</key><string>Adaptive</string>
<key>SoftResourceLimits</key><dict><key>NumberOfFiles</key><integer>512</integer></dict>
<key>HardResourceLimits</key><dict><key>NumberOfFiles</key><integer>512</integer></dict>
<key>StandardErrorPath</key><string>/tmp/cfprefsd-pearos.log</string>
</dict></plist>
P
  launchctl bootout user/$U/$L 2>&1; sleep 1; launchctl bootstrap user/$U ~/cfpd/$L.plist 2>&1 ;;
apple)
  launchctl bootout user/$U/$L 2>&1; sleep 1; launchctl bootstrap user/$U /System/Library/LaunchAgents/$L.plist 2>&1 ;;
esac
launchctl print user/$U/$L 2>&1 | grep -E "program|pid =|state ="
