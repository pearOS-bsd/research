#!/bin/sh
# Mac VM: the front application path (910 from root, 920, 300, 320) and its notifications, against Apple's launchservicesd (no argument) or
# another one (__LSXPCSERVICENAME=$1): a listener, an application that checks in (Foreground, frontable, ready), root makes it front, then
# moves it back with 920 and quits it.  Prints the normalized transcript (norm.py) to stdout.   sh lsvd-front.sh [SERVICE] > out.txt
[ -n "$1" ] && export __LSXPCSERVICENAME=$1
CODES=512,513,514,515,516,517,528,529,545,546,547,561,562,256,257,258,265,269,272,275,416
./lsx cmd=100 > /dev/null 2>&1
./lsx cmd=100 clientversion:u=277872640 -- cmd=410 listener needsassertions:b=0 clientid:u=4242 set:au=$CODES sleep=8 > front-notes.txt 2>&1 &
sleep 1
./lsx cmd=100 clientversion:u=277872640 -- cmd=500 "info:d=LSDisplayName:s=frontprobe^CFBundleExecutablePath:s=/tmp/lsvd/lsx^ApplicationType:s=Foreground^CFBundleIdentifier:s=com.pearos.frontprobe" deathport \
  -- cmd=510 asn=@2 info:d=LSNotifyApplicationFrontable:b=1 -- cmd=520 asn=@2 sleep=4 -- cmd=510 asn=@2 info:d=Hidden:b=1 -- cmd=320 -- cmd=320 includehidden:b=1 -- cmd=590 asn=@2 > front-app.txt 2>&1 &
sleep 1
echo pear | sudo -S -E ./lsx cmd=100 clientversion:u=277872640 -- cmd=330 criteria:d=LSDisplayName:s=frontprobe -- cmd=300 -- cmd=910 asn=@2 -- cmd=300 -- cmd=320 -- cmd=920 order:u=0 -- cmd=920 asn=@2 "order:au=0" > front-root.txt 2>&1
sleep 7
for f in front-root.txt front-app.txt front-notes.txt; do echo "==== $f"; python3 norm.py < $f; done
