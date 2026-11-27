/* fk.c - a fake launchservicesd that answers 100 and 110 (an all-zero page) and, at the N-th 110 (argv[2], default 2), boots its own launchd job out,
 * so the client gets XPC_ERROR_CONNECTION_INVALID.  Reproduces the pearOS Dock abort on the Mac VM: LaunchServices then has no connection for ever
 * ("Unable to register with launchservicsed, couldn't create connection object."), no 500 is sent and HIServices _RegisterApplication finds no ASN
 * (the Dock requires one and aborts; probes/a.m does not require one and goes on).
 * Mac VM: clang fk.c -o fk; LaunchAgent com.pearos.t.fk (MachServices com.pearos.t.fk, ProgramArguments fk com.pearos.t.fk);
 * env __LSXPCSERVICENAME=com.pearos.t.fk OS_ACTIVITY_DT_MODE=YES ./lsa   (probes/a.m) */
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <dispatch/dispatch.h>
int main(int c, char **v) {
  int lim = c > 2 ? atoi(v[2]) : 2; __block int n110 = 0;
  xpc_connection_t l = xpc_connection_create_mach_service(v[1], dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
  xpc_connection_set_event_handler(l, ^(xpc_object_t peer) {
    if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) return;
    xpc_connection_set_event_handler(peer, ^(xpc_object_t m) {
      if (xpc_get_type(m) != XPC_TYPE_DICTIONARY) return;
      long cmd = xpc_dictionary_get_int64(m, "command"); fprintf(stderr, "fk: cmd %ld\n", cmd);
      xpc_object_t r = xpc_dictionary_create_reply(m); if (!r) return;
      if (cmd == 100) { xpc_dictionary_set_uint64(r, "serverversion", 0x10900000); xpc_dictionary_set_int64(r, "session", 100001); xpc_dictionary_set_bool(r, "success", 1); }
      else if (cmd == 110) { void *p = mmap(0, 61440, 3, MAP_ANON|MAP_PRIVATE, -1, 0); xpc_dictionary_set_value(r, "lsinfopage", xpc_shmem_create(p, 61440)); xpc_dictionary_set_bool(r, "success", 1);
        if (++n110 >= lim) { xpc_connection_send_message(peer, r); fprintf(stderr, "fk: bootout\n"); usleep(100000); system("launchctl bootout gui/501/com.pearos.t.fk"); return; } }
      else xpc_dictionary_set_bool(r, "success", 0);
      xpc_connection_send_message(peer, r); });
    xpc_connection_resume(peer); });
  xpc_connection_resume(l); dispatch_main(); }
