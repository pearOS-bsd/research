/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Mac VM probe for research/docs/TCC-WIRE.md (build on the Mac: see tools/tcc/README.md). */
// Calls the public TCC-backed checks of CoreGraphics/ApplicationServices/IOKit and starts a window-server connection, so the tccd conversation of each can be recorded with xcap.dylib.
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/IOHIDLib.h>
int main(int argc, char **argv) {
  @autoreleasepool {
    const char *w = argc > 1 ? argv[1] : "all";
    if (!strcmp(w, "cgs") || !strcmp(w, "all")) { printf("RESULT CGMainDisplayID %u\n", CGMainDisplayID()); }
    if (!strcmp(w, "app") || !strcmp(w, "all")) { [NSApplication sharedApplication]; printf("RESULT NSApp %p\n", NSApp); }
    if (!strcmp(w, "sc") || !strcmp(w, "all")) printf("RESULT CGPreflightScreenCaptureAccess %d\n", CGPreflightScreenCaptureAccess());
    if (!strcmp(w, "le") || !strcmp(w, "all")) printf("RESULT CGPreflightListenEventAccess %d\n", CGPreflightListenEventAccess());
    if (!strcmp(w, "pe") || !strcmp(w, "all")) printf("RESULT CGPreflightPostEventAccess %d\n", CGPreflightPostEventAccess());
    if (!strcmp(w, "ax") || !strcmp(w, "all")) printf("RESULT AXIsProcessTrusted %d\n", AXIsProcessTrusted());
    if (!strcmp(w, "hid") || !strcmp(w, "all")) printf("RESULT IOHIDCheckAccess(ListenEvent) %d\n", IOHIDCheckAccess(kIOHIDRequestTypeListenEvent));
    fflush(stdout);
  }
  return 0;
}
