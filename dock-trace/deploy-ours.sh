#!/bin/sh
# Build apps/dock-cocoa on the Mac VM and put the new binary under ~/dock-cocoa (the path of the TCC rows and of the launchd job); restart the job if it is loaded.
#   sh research/dock-trace/deploy-ours.sh
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
cd ~/pearOS/apps && tar -cf - dock-cocoa | $M 'rm -rf ~/dock-build && mkdir ~/dock-build && cd ~/dock-build && tar xf - && cd dock-cocoa && make 2>&1 | grep -E "error|warning: unused" | head -12
if [ -x Dock.app/Contents/MacOS/Dock ]; then
  mkdir -p ~/dock-cocoa && rsync -a --delete Dock.app ~/dock-cocoa/ && { [ -s ~/dock-ents.plist ] || codesign -d --entitlements :- /System/Library/CoreServices/Dock.app/Contents/MacOS/Dock > ~/dock-ents.plist 2>/dev/null; } ; codesign --force -s - --entitlements ~/dock-ents.plist ~/dock-cocoa/Dock.app 2>/dev/null || codesign --force -s - ~/dock-cocoa/Dock.app && rsync -a ~/dock-build/dock/ ~/dock/ 2>/dev/null
  # TCC identifies the app by CFBundleIdentifier (com.apple.dock) and stores a code requirement (the cdhash of the binary) on first use: a new build is refused until that requirement is cleared
  for S in kTCCServiceAccessibility kTCCServiceListenEvent kTCCServicePostEvent; do echo pear | sudo -S -p "" sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "insert or ignore into access (service,client,client_type,auth_value,auth_reason,auth_version,flags) values (\"$S\",\"com.apple.dock\",0,2,4,1,0); update access set csreq=NULL, auth_value=2 where client=\"com.apple.dock\" and service=\"$S\";" 2>/dev/null; done
  if launchctl print gui/501/com.pearos.dock >/dev/null 2>&1; then echo pear | sudo -S -p "" killall tccd 2>/dev/null; sleep 2; launchctl kickstart -k gui/501/com.pearos.dock; sleep 5; echo "job restarted"; tail -2 /tmp/pearos-dock.err; fi
  echo deployed
else echo BUILD-FAILED; fi'
