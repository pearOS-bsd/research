#!/bin/sh
# Writes text stubs (install name + exported symbols) for Wallpaper.framework and WindowManager.framework from images extracted out of the
# dyld cache (ipsw dyld extract), for linking wptest.swift on a Mac.  The stubs are generated, never committed (they list Apple's symbols).
#   sh mk-tbd.sh EXTRACTED_DIR OUT_FW_DIR
set -e
X="$1"; O="$2"
for n in Wallpaper WindowManager; do
	mkdir -p "$O/$n.framework"
	{ printf -- "--- !tapi-tbd\ntbd-version: 4\ntargets: [ x86_64-macos ]\ninstall-name: '/System/Library/PrivateFrameworks/$n.framework/Versions/A/$n'\nexports:\n  - targets: [ x86_64-macos ]\n    symbols: [\n"
	  llvm-objdump --macho --exports-trie "$X/$n" | awk '{print $NF}' | grep '^_' | sed "s/.*/      '&',/" | sed '$ s/,$//'
	  printf "    ]\n...\n"; } > "$O/$n.framework/$n.tbd"
done
