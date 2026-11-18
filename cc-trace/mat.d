#pragma D option quiet
objc$target:CABackdropLayer:*:entry { printf("BD %s\n", probefunc); }
objc$target:CAFilter:*:entry { printf("FILTER %s\n", probefunc); }
objc$target:CAMeshTransform:*:entry { printf("MESH %s\n", probefunc); }
objc$target:CASDFLayer:*:entry { printf("SDF %s\n", probefunc); }
objc$target:NSVisualEffectView:*:entry { printf("NSVEV %s\n", probefunc); }
objc$target:NSGlassEffectView:*:entry { printf("GLASS %s\n", probefunc); }
objc$target:_NSGlassEffect*:*:entry { printf("GLASS %s %s\n", probemod, probefunc); }
