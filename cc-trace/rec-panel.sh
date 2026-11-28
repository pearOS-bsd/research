# Mac VM: record the Control Center panel: open, hover a tile, open a page, close.   sh rec.sh OUT.mov
O=$1; rm -f $O
screencapture -x -V 7 $O &
R=$!; sleep 1
~/bisect/mouse 1115 15 click; sleep 1.5
~/bisect/mouse 1040 75; sleep 1.0
~/bisect/mouse 1200 300; sleep 0.8
~/bisect/mouse 1200 300 click; sleep 1.2
~/bisect/mouse 400 500 click
wait $R; ls -la $O
