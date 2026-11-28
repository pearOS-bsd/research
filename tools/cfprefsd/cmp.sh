# Mac VM: run one probe against Apple's cfprefsd and against ours (test mode), same starting files; outputs /tmp/cmp-apple.txt and /tmp/cmp-ours.txt
P=${1:-p1}; cd ~/cfp; clang p5.c -framework CoreFoundation -o p5 2>/dev/null
clean() { killall -u $(id -un) cfprefsd 2>/dev/null; echo pear | sudo -S -p '' rm -f /Library/Preferences/org.pearos.cfptest5.plist /var/root/Library/Preferences/org.pearos.cfptest5.plist; sleep 1; rm -f ~/Library/Preferences/org.pearos.cfptest*.plist ~/Library/Preferences/ByHost/org.pearos.cfptest*; }
run() {
  case $P in
  run2) DYLD_INSERT_LIBRARIES=./xcap.dylib ./p2 watch > /tmp/w.log 2>&1 & sleep 4; DYLD_INSERT_LIBRARIES=./xcap.dylib ./p2 write > /tmp/wr.log 2>&1; sleep 16; echo "=== STEP watcher"; cat /tmp/w.log; echo "=== STEP writer"; cat /tmp/wr.log ;;
  defaults) DYLD_INSERT_LIBRARIES=./xcap.dylib ./defaults-copy write org.pearos.cfptest4 k -int 3; DYLD_INSERT_LIBRARIES=./xcap.dylib ./defaults-copy read org.pearos.cfptest4; DYLD_INSERT_LIBRARIES=./xcap.dylib ./defaults-copy delete org.pearos.cfptest4 ;;
  p5) SU="echo pear | sudo -S -p '' env ${__CFPreferencesTestDaemon:+__CFPreferencesTestDaemon=1} DYLD_INSERT_LIBRARIES=./xcap.dylib"; sh -c "$SU ./p5 write"; DYLD_INSERT_LIBRARIES=./xcap.dylib ./p5 read; sh -c "$SU ./p5 clean"; echo pear | sudo -S -p '' rm -f /Library/Preferences/org.pearos.cfptest5.plist /var/root/Library/Preferences/org.pearos.cfptest5.plist ;;
  *) DYLD_INSERT_LIBRARIES=./xcap.dylib ./$P ;;
  esac
}
clean; run > /tmp/cmp-apple.txt 2>&1
sh ~/cfpd/setup-test.sh >/dev/null 2>&1; launchctl bootout gui/$(id -u)/com.pearos.t.cfpagent; echo pear | sudo -S -p "" launchctl bootout system/com.pearos.t.cfpdaemon; sleep 1; clean; sh ~/cfpd/setup-test.sh >/dev/null 2>&1; sleep 1
export __CFPreferencesTestDaemon=1; run > /tmp/cmp-ours.txt 2>&1
