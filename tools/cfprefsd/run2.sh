cd ~/cfp && clang -dynamiclib xcap.c -o xcap.dylib && clang -fobjc-arc p2.m -framework Foundation -o p2 || exit 1
DYLD_INSERT_LIBRARIES=./xcap.dylib ./p2 watch > w.log 2>&1 &
sleep 4
DYLD_INSERT_LIBRARIES=./xcap.dylib ./p2 write > wr.log 2>&1
sleep 10
echo "#### WATCH"; grep -v "null-object" w.log
echo "#### WRITER"; grep -v "null-object" wr.log
