#!/bin/sh
# Mac VM: run the same requests against Apple's launchservicesd and against another one (default com.pearos.t.lsd, a test launchd job of
# LaunchServices/launchservicesd), with a notification listener (410, every code) beside them, and print both transcripts normalized
# (addresses, ASNs, pids, times, coalitions, inodes, audit tokens, session numbers replaced by names) and their diff.
#   sh lsvd-compare.sh [OTHER_SERVICE]     needs ./lsx (clang lsx.c -o lsx) and seq.sh (the requests: lsvd-seq.sh)
OTHER=${1:-com.pearos.t.lsd}
CODES=$(python3 -c "print(','.join(str(x) for x in list(range(0x100,0x122))+list(range(0x180,0x1b8))+list(range(0x200,0x23c))+[0x280,0x281]+list(range(0x290,0x295))+list(range(0x2a0,0x2a4))+[0x301,0x310,0x401,0x480]))")
run() {	# $1 = tag, $2 = service name or empty (Apple's)
	if [ -n "$2" ]; then export __LSXPCSERVICENAME=$2; else unset __LSXPCSERVICENAME; fi
	./lsx cmd=100 > /dev/null 2>&1	# start the server first (launchd starts a job at the first connection; a new binary is scanned once)
	./lsx cmd=100 clientversion:u=277872640 -- cmd=410 listener needsassertions:b=0 clientid:u=4242 set:au=$CODES sleep=5 > notes-$1.txt 2>&1 &
	L=$!; sleep 2
	sh lsvd-seq.sh > seq-$1.txt 2>&1
	wait $L
	{ cat seq-$1.txt; echo "---- notifications"; cat notes-$1.txt; } | python3 norm.py > norm-$1.txt
}
run apple ""
run ours "$OTHER"
diff -u norm-apple.txt norm-ours.txt > diff.txt; echo "diff lines: $(grep -c '^[-+][^-+]' diff.txt)"
