/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Mac VM probe for research/docs/TCC-WIRE.md (build on the Mac: see tools/tcc/README.md). */
// Sends hand-made messages to tccd (system or user) and prints the replies: argv[1] = service name of tccd, then function names ("-" = no function key).
#include <xpc/xpc.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
  xpc_connection_t c = xpc_connection_create_mach_service(argv[1], 0, strcmp(argv[1], "com.apple.tccd.system") ? 0 : XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
  xpc_connection_set_event_handler(c, ^(xpc_object_t e) { });
  xpc_connection_resume(c);
  for (int i = 2; i < argc; i++) {
    xpc_object_t m = xpc_dictionary_create(0, 0, 0);
    char *f = strdup(argv[i]), *svc = strchr(f, ':');
    if (svc) *svc++ = 0;
    if (strcmp(f, "-")) xpc_dictionary_set_string(m, "function", f);
    if (svc) xpc_dictionary_set_string(m, "service", svc);
    char id[32]; snprintf(id, 32, "%d.%d", getpid(), i); xpc_dictionary_set_string(m, "TCCD_MSG_ID", id);
    xpc_object_t r = xpc_connection_send_message_with_reply_sync(c, m);
    char *d = xpc_copy_description(r); printf("== %s\n%s\n", argv[i], d); free(d); fflush(stdout);
  }
  return 0;
}
