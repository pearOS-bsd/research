/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Test probe (Mac / pearOS): one raw XPC message with a reply to a Mach service, prints the reply (and any message the service sends in 2 s).
 *   ./xraw [-p] SERVICE key=i:N key=u:N key=s:STR key=b:1 ...     (-p: privileged connection, as libraries connect to system daemons) */
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  int a = 1; uint64_t fl = 0;
  if (argc > 1 && !strcmp(argv[1], "-p")) { fl = XPC_CONNECTION_MACH_SERVICE_PRIVILEGED; a++; }
  if (a >= argc) { fprintf(stderr, "usage: xraw [-p] SERVICE key=type:value...\n"); return 2; }
  xpc_connection_t c = xpc_connection_create_mach_service(argv[a++], NULL, fl);
  xpc_connection_set_event_handler(c, ^(xpc_object_t m) { char *d = xpc_copy_description(m); printf("event: %s\n", d); free(d); fflush(stdout); });
  xpc_connection_resume(c);
  xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
  for (; a < argc; a++) {
    char *k = strdup(argv[a]), *eq = strchr(k, '='); if (!eq || eq[2] != ':') continue; *eq = 0; char t = eq[1]; const char *v = eq + 3;
    if (t == 'i') xpc_dictionary_set_int64(m, k, strtoll(v, 0, 0)); else if (t == 'u') xpc_dictionary_set_uint64(m, k, strtoull(v, 0, 0));
    else if (t == 'b') xpc_dictionary_set_bool(m, k, atoi(v)); else xpc_dictionary_set_string(m, k, v);
  }
  xpc_object_t r = xpc_connection_send_message_with_reply_sync(c, m);
  char *d = xpc_copy_description(r); printf("reply: %s\n", d); free(d); fflush(stdout);
  dispatch_after(dispatch_time(0, 2LL * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
  dispatch_main();
}
