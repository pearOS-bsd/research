/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Test probe (Mac / pearOS): com.apple.usernoted.dock as the Dock speaks it: {message_type 1} then optional (type, bundle id) pairs; prints what comes back.
 *   ./undock [SERVICE [TYPE BUNDLE]...] */
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
  const char *name = argc > 1 ? argv[1] : "com.apple.usernoted.dock";
  xpc_connection_t c = xpc_connection_create_mach_service(name, dispatch_get_main_queue(), 0);
  xpc_connection_set_event_handler(c, ^(xpc_object_t m) { char *d = xpc_copy_description(m); printf("recv: %s\n", d); free(d); fflush(stdout); });
  xpc_connection_resume(c);
  xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
  xpc_dictionary_set_uint64(m, "message_type", 1);
  xpc_connection_send_message(c, m);
  for (int i = 2; i + 1 < argc; i += 2) { xpc_object_t x = xpc_dictionary_create(NULL,NULL,0); xpc_dictionary_set_uint64(x,"message_type",atoi(argv[i])); xpc_dictionary_set_string(x,"bundle_identifier",argv[i+1]); xpc_connection_send_message(c,x); }
  dispatch_after(dispatch_time(0, 4LL*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
  dispatch_main();
}
