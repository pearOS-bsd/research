/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Mac VM probe for research/docs/TCC-WIRE.md (build on the Mac: see tools/tcc/README.md). */
// Probe for the tcc_server SPI (TCCD_MSG_SPI_VERSION 2) used by SkyLight: one tcc_server_message_request_authorization per service, so its XPC messages can be recorded with xcap.dylib.
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <unistd.h>
typedef void *tcc_t;
extern tcc_t tcc_server_create(dispatch_queue_t q);
extern tcc_t tcc_service_singleton_for_CF_name(CFStringRef n);
extern tcc_t tcc_credential_singleton_for_self(void);
extern tcc_t tcc_message_options_create(void);
extern void tcc_message_options_set_reply_handler_policy(tcc_t o, int p);
extern void tcc_message_options_set_request_prompt_policy(tcc_t o, int p);
extern void tcc_server_message_request_authorization(tcc_t s, tcc_t opt, tcc_t cred, tcc_t svc, tcc_t ind, void (^b)(tcc_t rec, CFErrorRef e));
extern long tcc_authorization_record_get_authorization_right(tcc_t r);
extern long tcc_authorization_record_get_authorization_reason(tcc_t r);
int main(int argc, char **argv) {
  tcc_t srv = tcc_server_create(dispatch_queue_create("p", 0));
  for (int i = 1; i < argc; i++) {
    CFStringRef n = CFStringCreateWithCString(0, argv[i], kCFStringEncodingUTF8);
    tcc_t svc = tcc_service_singleton_for_CF_name(n), o = tcc_message_options_create();
    tcc_message_options_set_reply_handler_policy(o, 1);
    tcc_message_options_set_request_prompt_policy(o, 1);
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    const char *nm = argv[i];
    tcc_server_message_request_authorization(srv, o, tcc_credential_singleton_for_self(), svc, 0, ^(tcc_t r, CFErrorRef e) {
      printf("RESULT %s rec=%p right=%ld reason=%ld err=%p\n", nm, r, r ? tcc_authorization_record_get_authorization_right(r) : -1, r ? tcc_authorization_record_get_authorization_reason(r) : -1, e);
      if (e) CFShow(e);
      fflush(stdout); dispatch_semaphore_signal(s); });
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 5000000000LL));
  }
  return 0;
}
