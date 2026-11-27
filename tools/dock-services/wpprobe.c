// Test probe: sends raw AgentXPCMessage JSON to com.apple.wallpaper (or $WP_SERVICE) and prints the reply. Args: JSON strings.
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) {
  const char *svc = getenv("WP_SERVICE") ? getenv("WP_SERVICE") : "com.apple.wallpaper";
  xpc_connection_t c = xpc_connection_create_mach_service(svc, NULL, 0);
  xpc_connection_set_event_handler(c, ^(xpc_object_t e) { char *d = xpc_copy_description(e); printf("EVENT %s\n", d); free(d); });
  xpc_connection_resume(c);
  for (int i = 1; i < argc; i++) {
    xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
    if (strcmp(argv[i], "-raw")) xpc_dictionary_set_data(m, "AgentXPCMessage", argv[i], strlen(argv[i]));
    else xpc_dictionary_set_string(m, "foo", "bar");
    xpc_object_t r = xpc_connection_send_message_with_reply_sync(c, m);
    char *d = xpc_copy_description(r); printf("== %s\n%s\n", argv[i], d); free(d);
    if (xpc_get_type(r) == XPC_TYPE_DICTIONARY) xpc_dictionary_apply(r, ^bool(const char *k, xpc_object_t v) { if (xpc_get_type(v) == XPC_TYPE_DATA) printf("  %s = %.*s\n", k, (int)xpc_data_get_length(v), (const char *)xpc_data_get_bytes_ptr(v)); return true; });
  }
  return 0;
}
