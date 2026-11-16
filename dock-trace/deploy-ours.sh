#!/bin/sh
# Build apps/dock-cocoa on the Mac VM and put the new binary under ~/dock-cocoa (the path of the TCC rows and of the launchd job); restart the job if it is loaded.
#   sh research/dock-trace/deploy-ours.sh
M="ssh -p 2229 -i $HOME/fbsd-vm/id_ed25519 -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q alex@localhost"
cd ~/pearOS/apps && tar -cf - dock-cocoa dock/dock_layout.c dock/dock_layout.h | $M 'rm -rf ~/dock-build && mkdir ~/dock-build && cd ~/dock-build && tar xf - && cd dock-cocoa && make 2>&1 | grep -E "error|warning: unused" | head -12
if [ -x Dock.app/Contents/MacOS/Dock ]; then
  mkdir -p ~/dock-cocoa && rsync -a --delete Dock.app ~/dock-cocoa/ && codesign --force -s - ~/dock-cocoa/Dock.app && rsync -a ~/dock-build/dock/ ~/dock/ 2>/dev/null
  if launchctl print gui/501/com.pearos.dock >/dev/null 2>&1; then launchctl kickstart -k gui/501/com.pearos.dock; sleep 5; echo "job restarted"; tail -2 /tmp/pearos-dock.err; fi
  echo deployed
else echo BUILD-FAILED; fi'
