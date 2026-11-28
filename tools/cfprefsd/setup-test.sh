# Mac VM: run our cfprefsd as the test services (com.apple.cfprefsd.agent.test / .daemon.test) next to Apple's.
set -e
cd ~/cfpd; CC=clang MAC=1 sh build.sh out >/dev/null 2>&1
cat > /tmp/com.pearos.t.cfpagent.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.pearos.t.cfpagent</string>
<key>ProgramArguments</key><array><string>$HOME/cfpd/out/cfprefsd</string><string>agent</string><string>-v</string></array>
<key>EnvironmentVariables</key><dict><key>__CFPreferencesTestDaemon</key><string>1</string></dict>
<key>MachServices</key><dict><key>com.apple.cfprefsd.agent.test</key><true/></dict>
<key>StandardErrorPath</key><string>/tmp/cfpagent.log</string>
</dict></plist>
P
cat > $HOME/cfpd/com.pearos.t.cfpdaemon.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.pearos.t.cfpdaemon</string>
<key>ProgramArguments</key><array><string>/tmp/cfprefsd-test</string><string>daemon</string><string>-v</string></array>
<key>EnvironmentVariables</key><dict><key>__CFPreferencesTestDaemon</key><string>1</string></dict>
<key>MachServices</key><dict><key>com.apple.cfprefsd.daemon.test</key><true/></dict>
<key>StandardErrorPath</key><string>/tmp/cfpdaemon.log</string>
</dict></plist>
P
echo pear | sudo -S -p "" rm -f /tmp/cfprefsd-test; cp out/cfprefsd /tmp/cfprefsd-test
launchctl bootout gui/$(id -u)/com.pearos.t.cfpagent 2>/dev/null || true
echo pear | sudo -S -p "" launchctl bootout system/com.pearos.t.cfpdaemon 2>/dev/null || true
for i in 1 2 3 4 5 6 7 8 9 10; do launchctl print gui/$(id -u)/com.pearos.t.cfpagent >/dev/null 2>&1 || break; sleep 0.5; done
sleep 1
echo pear | sudo -S -p "" rm -f /tmp/cfpagent.log /tmp/cfpdaemon.log
launchctl bootstrap gui/$(id -u) /tmp/com.pearos.t.cfpagent.plist
echo pear | sudo -S -p "" rm -f /tmp/com.pearos.t.cfpdaemon.plist; echo pear | sudo -S -p "" cp $HOME/cfpd/com.pearos.t.cfpdaemon.plist /tmp/; echo pear | sudo -S -p "" chown root:wheel /tmp/com.pearos.t.cfpdaemon.plist
echo pear | sudo -S -p "" launchctl bootstrap system /tmp/com.pearos.t.cfpdaemon.plist
echo loaded
