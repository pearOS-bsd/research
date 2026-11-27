#!/bin/sh
# lab test (FreeBSD lab VM, darwinator): the launchd of d with the jobs of d/darwin/{usernoted,appleeventsd,analyticsd,filecoordinationd,
# csnameddatad,dmd,useractivityd,uninstalld} (and distnoted, for the isAlive notification), then Apple's clients from the dyld cache through the
# probes built on the Mac (dsprobe, xraw, undock2 = undock signed ad hoc with the identifier com.apple.dock).
#   sh labtest.sh [D_OUT [PROBES]]     D_OUT = output of d/darwin/build.sh, PROBES = directory of the Mac-built probes
O=${1:-/root/ccbuild/ds2/out}; P=${2:-/root/ccbuild/ds2probe}; S=/root/ccbuild/ds2/d/darwin; T=/root/ccbuild/ds2/jobs
kldstat -q -m darwinator || kldload /root/darwinator/darwinator.ko
sysctl kern.darwinator.dyld=1 kern.darwinator.two_volumes=2 kern.darwinator.fast_sleep_ms=5 >/dev/null
pkill -9 launchd; for n in usernoted appleeventsd analyticsd filecoordinationd csnameddatad dmd useractivityd uninstalld distnoted; do pkill -9 $n; done; sleep 1
rm -rf $T; mkdir -p $T
# every program through env with its own log switch (and the test switch of its entitlement check: the probes carry no entitlement);
# the launchd of d takes at most 8 ProgramArguments
for d in usernoted appleeventsd analyticsd filecoordinationd csnameddatad dmd useractivityd uninstalld distnoted; do
	case $d in
	usernoted|appleeventsd|analyticsd) a=""; v="<string>-v</string>";;
	filecoordinationd) a="<string>FC_LOG=1</string>"; v="";;
	csnameddatad) a="<string>ND_LOG=1</string>"; v="";;
	dmd) a="<string>DMD_LOG=1</string><string>DMD_NO_ENTITLEMENT_CHECK=1</string>"; v="";;
	useractivityd) a="<string>UA_LOG=1</string><string>UA_NO_ENTITLEMENT_CHECK=1</string>"; v="";;
	uninstalld) a="<string>UN_LOG=1</string><string>UN_NO_ENTITLEMENT_CHECK=1</string>"; v="";;
	*) a=""; v="";;
	esac
	for j in $S/$d/launchd/*.plist; do
		sed -e "s|<string>/usr/libexec/pearos/$d</string>|<string>/usr/bin/env</string>$a<string>$O/$d/out/$d</string>$v|" -e "s/@USER@/root/g" $j > $T/${j##*/}
	done
done
# AE.framework's check-in first asks com.apple.coreservices.launchservicesd (d's launchd keeps that name for its owner): the job of LaunchServices
LS=${LS:-/root/ccbuild/lsout}; J=/root/ccbuild/LaunchServices/launchd/com.apple.coreservices.launchservicesd.plist
[ -x $LS/launchservicesd ] && [ -f $J ] && sed -e "s|<string>/usr/libexec/pearos/launchservicesd</string>|<string>$LS/launchservicesd</string>|" $J > $T/${J##*/}
(cd /tmp; nohup $O/launchd/launchd $O/notifyd/notifyd $T/*.plist > /tmp/ds2-lab.log 2>&1 &)
sleep 3
cd $P
echo "== appleevents check-in";    timeout 30 ./xraw -p com.apple.coreservices.appleevents command=i:100 appName=s:probe signature=i:0 needsProcessAssertions=b:0 | head -5
echo "== appleevents bad command"; timeout 30 ./xraw -p com.apple.coreservices.appleevents command=i:9999 | head -3
echo "== analytics";               timeout 30 ./xraw -p com.apple.analyticsd command=s:send event=s:com.apple.dock.test json=s:{} | head -3
echo "== usernoted as the Dock";   timeout 30 ./undock2
echo "== usernoted unsigned";      timeout 10 ./undock
echo "== Apple's frameworks";      timeout 120 ./dsprobe ae analytics named namedx dmd dmd2 ua uninstall progress 2>&1 | grep PROBE
echo "== publish + subscribe";     (timeout 40 ./dsprobe subscribe > /tmp/ds2-sub.txt 2>&1 &); sleep 2; timeout 40 ./dsprobe publish 2>&1 | grep PROBE; sleep 5; grep PROBE /tmp/ds2-sub.txt
echo "== daemon lines";            grep -E "usernoted:|appleeventsd:|analyticsd:|filecoordinationd:|csnameddatad:|dmd:|useractivityd:|uninstalld:|NOT FOUND" /tmp/ds2-lab.log | head -60
