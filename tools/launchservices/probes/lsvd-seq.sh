# the requests of lsvd-compare.sh: one client that checks in and goes through the commands (LSX = the lsx binary; __LSXPCSERVICENAME = the server)
L=${LSX:-./lsx}
$L cmd=100 clientversion:u=277872640 \
 -- cmd=500 "info:d=LSDisplayName:s=lsxprobe^CFBundleExecutablePath:s=/tmp/lsvd/lsx^LSExecutableFileName:s=lsx^ApplicationType:s=Foreground^LSArchitecture:s=x86_64^CFBundleIdentifier:s=com.pearos.lsxprobe" deathport \
 -- cmd=505 -- cmd=505 pid:i=1 \
 -- cmd=360 asn=@2 restrictto:as=pid,ApplicationType,LSDisplayName,ChangeCount,Nope \
 -- cmd=510 asn=@2 info:d=LSNotifyApplicationFrontable:b=1 \
 -- cmd=520 asn=@2 \
 -- cmd=370 asn=@2 \
 -- cmd=380 asn=@2 modifiers:d=LSFoo:b=1 \
 -- cmd=370 asn=@2 \
 -- cmd=910 asn=@2 \
 -- cmd=920 asn=@2 order:au=1 \
 -- cmd=450 asn=@2 code:i=561 when:f=1 data:d=X:b=1 \
 -- cmd=120 \
 -- cmd=210 info:d=LSFooMeta:i=7 \
 -- cmd=200 wanted:as=LSFooMeta,LSSessionID,LSCGSSessionID \
 -- cmd=130 asn1:u=1 asn2:u=2 \
 -- cmd=330 criteria:d=LSDisplayName:s=lsxprobe \
 -- cmd=331 path:s=/tmp/lsvd/lsx \
 -- cmd=597 info:d=LSDisplayName:s=other \
 -- cmd=600 -- cmd=610 asn=@2 -- cmd=420 id:u=999 \
 -- cmd=360 asn=@2 \
 -- cmd=590 asn=@2 exitstatus:i=0 \
 -- cmd=360 asn=@2 restrictto:as=pid \
 -- cmd=700 pid:i=1 \
 -- cmd=12345 -- cmd=98 -- cmd=1000 -- cmd=595 \
 -- cmd=140
