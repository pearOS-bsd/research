/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Mac VM probe for research/docs/TCC-WIRE.md (build on the Mac: see tools/tcc/README.md). */
// TCC client probe: calls libTCC entry points so the XPC conversation with tccd can be recorded (xcap.dylib).
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach.h>
#include <bsm/libbsm.h>
extern int TCCAccessPreflight(CFStringRef s, CFDictionaryRef o);
extern Boolean TCCAccessRequest(CFStringRef s, CFDictionaryRef o, void (^b)(Boolean));
extern Boolean TCCAccessCheckAuditToken(CFStringRef s, audit_token_t t, CFDictionaryRef o);
extern int TCCAccessPreflightWithAuditToken(CFStringRef s, audit_token_t t, CFDictionaryRef o);
extern CFArrayRef TCCAccessCopyInformation(CFStringRef s);
extern Boolean TCCAccessRestricted(CFStringRef s);
extern CFArrayRef TCCServiceCopyNames(void);
extern Boolean TCCAccessReset(CFStringRef s);
int main(int argc, char **argv) {
  audit_token_t tok; mach_msg_type_number_t n = TASK_AUDIT_TOKEN_COUNT;
  task_info(mach_task_self(), TASK_AUDIT_TOKEN, (task_info_t)&tok, &n);
  for (int i = 2; i < argc; i++) {
    CFStringRef s = CFStringCreateWithCString(0, argv[i], kCFStringEncodingUTF8);
    const char *op = argv[1];
    if (!strcmp(op, "pre")) printf("RESULT TCCAccessPreflight(%s) = %d\n", argv[i], TCCAccessPreflight(s, 0));
    else if (!strcmp(op, "req")) printf("RESULT TCCAccessRequest(%s) = %d\n", argv[i], TCCAccessRequest(s, 0, ^(Boolean g){ printf("  block granted=%d\n", g); }));
    else if (!strcmp(op, "chk")) printf("RESULT TCCAccessCheckAuditToken(%s) = %d\n", argv[i], TCCAccessCheckAuditToken(s, tok, 0));
    else if (!strcmp(op, "pat")) printf("RESULT TCCAccessPreflightWithAuditToken(%s) = %d\n", argv[i], TCCAccessPreflightWithAuditToken(s, tok, 0));
    else if (!strcmp(op, "res")) printf("RESULT TCCAccessRestricted(%s) = %d\n", argv[i], TCCAccessRestricted(s));
    else if (!strcmp(op, "inf")) { CFArrayRef a = TCCAccessCopyInformation(s); printf("RESULT TCCAccessCopyInformation(%s) = %p\n", argv[i], a); if (a) CFShow(a); }
    fflush(stdout);
  }
  if (!strcmp(argv[1], "req")) sleep(3);
  return 0;
}
