#!/bin/sh
# lab test: our launchd with the WindowManager and WallpaperAgent jobs, then Apple's client (wptest: Wallpaper.framework + WindowManager.framework
# of the dyld cache, built on the Mac) and a raw XPC probe (wpprobe)
T=/root/ccbuild/wmtest; D=/root/ccbuild/tccdtest/dout
kldstat -q -m darwinator || kldload /root/darwinator/darwinator.ko
sysctl kern.darwinator.dyld=1 kern.darwinator.two_volumes=2 kern.darwinator.fast_sleep_ms=5 >/dev/null
pkill -9 launchd; pkill -9 WindowManager; pkill -9 WallpaperAgent; sleep 1
mkdir -p $T/jobs
for j in $T/darwin/windowmanager/launchd/*.plist $T/darwin/wallpaperagent/launchd/*.plist; do
	sed -e "s|/usr/libexec/pearos/\([A-Za-z]*\)</string>|/usr/bin/env</string><string>WM_LOG=1</string><string>WP_LOG=1</string><string>$T/out/\1</string>|" -e "s/@USER@/root/g" $j > $T/jobs/${j##*/}; done
(cd /tmp; nohup $D/launchd/launchd $D/notifyd/notifyd $T/jobs/*.plist > /tmp/wm-lab.log 2>&1 &)
sleep 3
cd $T/probe
echo "== wpprobe"; timeout 30 ./wpprobe '{"bogus":{}}' '{"releaseAssertion":{"id":7}}' '{"takeAssertion":{"value":{"display":{"display":"D19AD5BA-D2A3-3EBB-0024-A4187A84FFFE","spaceName":"","contentType":{"desktop":{}},"isPreview":false}},"id":3}}'; echo "exit $?"
echo "== wptest"; timeout 40 ./wptest; echo "exit $?"
echo "== server lines"; grep -E "WindowManager:|WallpaperAgent:" /tmp/wm-lab.log | head -30
