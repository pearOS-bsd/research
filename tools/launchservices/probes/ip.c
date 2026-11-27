/* ip.c - dump the launchservicesd "info page" (command 110 reply, lsinfopage shmem).
 * Mac VM: clang ip.c -o ip && ./ip [out.bin] [checkin]
 * Sends 100 (check-in of the client library) then 110 to com.apple.coreservices.launchservicesd
 * like a LaunchServices client, maps the shared memory and writes it to out.bin.
 * __LSXPCSERVICENAME=NAME talks to another server (as LaunchServices does).
 * With "checkin", sends a 500 first-time application check-in in between (BackgroundOnly). */
#include <xpc/xpc.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach.h>
extern size_t xpc_shmem_map(xpc_object_t, void **region);

static xpc_connection_t c;
static xpc_object_t rpc(xpc_object_t m) {
    xpc_object_t r = xpc_connection_send_message_with_reply_sync(c, m);
    char *d = xpc_copy_description(r); fprintf(stderr, "%s\n", d); free(d);
    return r;
}
static xpc_object_t msg(int64_t cmd, int64_t session) {
    xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(m, "command", cmd);
    xpc_dictionary_set_int64(m, "session", session);
    return m;
}
int main(int argc, char **argv) {
    const char *out = argc > 1 ? argv[1] : "infopage.bin";
    const char *svc = getenv("__LSXPCSERVICENAME");   /* the same override as LaunchServices: another server, in the user domain */
    c = xpc_connection_create_mach_service(svc ? svc : "com.apple.coreservices.launchservicesd", NULL, svc ? 0 : 2);
    xpc_connection_set_event_handler(c, ^(xpc_object_t e) { (void)e; });
    xpc_connection_resume(c);
    xpc_object_t m = msg(100, -2);
    xpc_dictionary_set_uint64(m, "clientversion", 277872640);
    xpc_object_t r = rpc(m);
    int64_t session = xpc_dictionary_get_int64(r, "session");
    if (argc > 2 && !strcmp(argv[2], "checkin")) {
        m = msg(500, -2);
        xpc_object_t info = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_string(info, "LSDisplayName", "ip");
        xpc_dictionary_set_string(info, "CFBundleExecutablePath", argv[0]);
        xpc_dictionary_set_string(info, "LSExecutableFileName", "ip");
        xpc_dictionary_set_string(info, "ApplicationType", "Foreground");
        xpc_dictionary_set_string(info, "LSArchitecture", "x86_64");
        xpc_dictionary_set_value(m, "info", info);
        mach_port_t dp; mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &dp);
        mach_port_insert_right(mach_task_self(), dp, dp, MACH_MSG_TYPE_MAKE_SEND);
        xpc_dictionary_set_mach_send(m, "deathport", dp);
        rpc(m);
    }
    m = msg(110, -2);
    r = rpc(m);
    xpc_object_t sh = xpc_dictionary_get_value(r, "lsinfopage");
    if (!sh) { fprintf(stderr, "no lsinfopage\n"); return 1; }
    void *p = NULL; size_t n = xpc_shmem_map(sh, &p);
    fprintf(stderr, "mapped %zu bytes at %p session %lld\n", n, p, session);
    FILE *f = fopen(out, "wb"); fwrite(p, 1, n, f); fclose(f);
    if (argc > 3) sleep(atoi(argv[3]));   /* keep the check-in alive */
    return 0;
}
