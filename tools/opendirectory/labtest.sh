#!/bin/sh
# lab test: our launchd with the opendirectoryd and distnoted jobs, then Apple's clients (libsystem_info, CoreFoundation, Foundation of the dyld cache; probes built on the Mac)
T=/root/ccbuild/odtest; S=/root/ccbuild/dnew-src
kldstat -q -m darwinator || kldload /root/darwinator/darwinator.ko
sysctl kern.darwinator.dyld=1 kern.darwinator.two_volumes=2 kern.darwinator.fast_sleep_ms=5 >/dev/null
pkill -9 launchd; pkill -9 opendirectoryd; pkill -9 distnoted; sleep 1
mkdir -p $T/jobs
for j in $S/opendirectoryd/launchd/*.plist $S/distnoted/launchd/*.plist; do sed -e "s|/usr/libexec/pearos/opendirectoryd|$S/out/opendirectoryd/opendirectoryd|" -e "s|/usr/libexec/pearos/distnoted|$S/out/distnoted/distnoted|" -e "s/@USER@/root/g" $j > $T/jobs/${j##*/}; done
L=/root/ccbuild/tccdtest/dout
(cd /tmp; nohup $L/launchd/launchd $L/notifyd/notifyd $T/jobs/*.plist > /tmp/od-lab.log 2>&1 &)
sleep 3
cd $T/probe
echo "== odt"; timeout 60 ./odt pwuid:0 pwnam:root pwnam:nosuchuser grgid:0 grnam:wheel gl:root u2u:0 u2u:1001 g2u:0 g2u:4242 n2u:root uu2id:AAAABBBB-CCCC-DDDD-EEEE-FFFF00001092 ck:0:0 ck:0:5 u2n:0 pwent grent; echo "exit $?"
echo "== odraw"; timeout 20 ./odraw com.apple.system.opendirectoryd.libinfo bogus; timeout 20 ./odraw com.apple.system.opendirectoryd.libinfo getpwuid uid=0 | tr -s '\t\n' '  '; echo
echo "== dnt"; (timeout 20 ./dnt two com.pearos.t4 o 3 > /tmp/dnt-a.txt 2>&1 &); sleep 1.5; timeout 20 ./dnt post com.pearos.t4 o k1=v1; sleep 3; cat /tmp/dnt-a.txt
echo "== dnt2"; timeout 30 ./dnt2; echo "exit $?"
echo "== daemon lines"; grep "opendirectoryd\|distnoted" /tmp/od-lab.log | head -40
