#!/bin/sh
# Build apps/controlcenter-cocoa (+ the shared window code of dock-cocoa) on the Mac VM into ~/cc-all, sign it ad hoc with the real ControlCenter's entitlements, give com.apple.controlcenter the TCC rows
# the event tap needs (the cdhash requirement is cleared at every build), and restart our job if it is loaded.   sh research/cc-trace/deploy-ours.sh
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
cd ~/pearOS/apps && tar -cf - controlcenter-cocoa dock-cocoa | $M 'rm -rf ~/cc-all && mkdir ~/cc-all && cd ~/cc-all && tar xf - && cd controlcenter-cocoa && make 2>&1 | grep -E "error|warning: unused" | head -12
if [ -x ControlCenter.app/Contents/MacOS/ControlCenter ]; then
  { [ -s ~/cc-ents.plist ] || codesign -d --entitlements :- /System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter > ~/cc-ents.plist 2>/dev/null; }
  codesign --force -s - --entitlements ~/cc-ents.plist ControlCenter.app 2>/dev/null || codesign --force -s - ControlCenter.app
  for S in kTCCServiceAccessibility kTCCServiceListenEvent kTCCServicePostEvent; do echo pear | sudo -S -p "" sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "insert or ignore into access (service,client,client_type,auth_value,auth_reason,auth_version,flags) values (\"$S\",\"com.apple.controlcenter\",0,2,4,1,0); update access set csreq=NULL, auth_value=2 where client=\"com.apple.controlcenter\" and service=\"$S\";" 2>/dev/null; done
  echo pear | sudo -S -p "" killall tccd 2>/dev/null; sleep 2
  if launchctl print gui/501/com.pearos.controlcenter >/dev/null 2>&1; then launchctl kickstart -k gui/501/com.pearos.controlcenter; sleep 4; echo "job restarted"; tail -2 /tmp/pearos-cc.err; fi
  echo deployed
else echo BUILD-FAILED; fi'
