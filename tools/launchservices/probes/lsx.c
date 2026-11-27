/* lsx.c - scriptable plain-XPC client of com.apple.coreservices.launchservicesd (macOS), to compare servers.
 * Mac VM: clang lsx.c -o lsx
 *   ./lsx REQ [-- REQ ...]          one connection, the requests in order, each reply printed (xpc description)
 * REQ is a list of words:
 *   cmd=N            "command" int64 (required)
 *   session=N        "session" int64 (default -2)
 *   KEY:i=N KEY:u=N KEY:f=X  int64 / uint64 / double          KEY:s=STR  string     KEY:b=0|1  bool
 *   KEY:au=N,N,...   array of uint64         KEY:as=A,B,...  array of strings
 *   KEY:d=K1:s=v^K2:b=1^...  dictionary (same typed items, '^' separated)
 *   deathport        a send right of a new receive right under "deathport" (check-in)
 *   listener         an endpoint of an anonymous listener of this process under "listener" (410): every message the
 *                    server sends to it is printed as "NOTE <description>" with the time since start
 *   asn=@N           "asn" uint64 = LSASN.lo of the Nth reply's result (or info; or the first element of a result array) - 1 based
 *   sleep=S          after this request, wait S seconds (messages to the listener keep coming)
 *   page=FILE        write the "lsinfopage" shared memory of this request's reply (110) to FILE
 * __LSXPCSERVICENAME=NAME talks to another server (user-domain lookup, as LaunchServices does). */
#include <xpc/xpc.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
extern size_t xpc_shmem_map(xpc_object_t, void **region);

static xpc_connection_t c, lis;
static xpc_object_t replies[64];
static int nrep;
static struct timespec t0;

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (t.tv_sec - t0.tv_sec) + (t.tv_nsec - t0.tv_nsec) / 1e9; }

static void put(xpc_object_t d, char *item);

static xpc_object_t typed(char *type, char *v)
{
	if (!strcmp(type, "i")) return xpc_int64_create(strtoll(v, 0, 0));
	if (!strcmp(type, "u")) return xpc_uint64_create(strtoull(v, 0, 0));
	if (!strcmp(type, "s")) return xpc_string_create(v);
	if (!strcmp(type, "b")) return xpc_bool_create(atoi(v));
	if (!strcmp(type, "f")) return xpc_double_create(atof(v));
	if (!strcmp(type, "au") || !strcmp(type, "as")) {
		xpc_object_t a = xpc_array_create(NULL, 0);
		for (char *sv = 0, *p = strtok_r(v, ",", &sv); p; p = strtok_r(0, ",", &sv))
			xpc_array_append_value(a, type[1] == 'u' ? xpc_uint64_create(strtoull(p, 0, 0)) : xpc_string_create(p));
		return a;
	}
	if (!strcmp(type, "d")) {
		xpc_object_t d = xpc_dictionary_create(NULL, NULL, 0);
		for (char *sv = 0, *p = strtok_r(v, "^", &sv); p; p = strtok_r(0, "^", &sv)) put(d, p);
		return d;
	}
	fprintf(stderr, "bad type %s\n", type); exit(2);
}

static void put(xpc_object_t d, char *item)
{
	char *eq = strchr(item, '='), *col;
	if (!eq) { fprintf(stderr, "bad item %s\n", item); exit(2); }
	*eq = 0;
	if ((col = strchr(item, ':')) != NULL) { *col = 0; xpc_dictionary_set_value(d, item, typed(col + 1, eq + 1)); }
	else xpc_dictionary_set_int64(d, item, strtoll(eq + 1, 0, 0));
}

static uint64_t asn_of(int n)
{
	if (n < 1 || n > nrep) return 0;
	xpc_object_t r = xpc_dictionary_get_value(replies[n - 1], "result");
	if (r && xpc_get_type(r) == XPC_TYPE_ARRAY) return xpc_array_get_count(r) ? xpc_array_get_uint64(r, 0) : 0;	/* 330: the first match */
	if (!r) r = xpc_dictionary_get_value(replies[n - 1], "info");
	xpc_object_t a = r ? xpc_dictionary_get_value(r, "LSASN") : NULL;
	return a ? xpc_dictionary_get_uint64(a, "com.apple.coreservices.asn.lo") : 0;
}

static void listener_start(void)
{
	if (lis) return;
	lis = xpc_connection_create(NULL, NULL);
	xpc_connection_set_event_handler(lis, ^(xpc_object_t peer) {
		if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) { char *d = xpc_copy_description(peer); printf("NOTE-LISTENER-EVENT %s\n", d); free(d); return; }
		printf("NOTE-PEER pid=%d\n", xpc_connection_get_pid(peer)); fflush(stdout);
		xpc_connection_set_event_handler(peer, ^(xpc_object_t m) {
			char *d = xpc_copy_description(m);
			xpc_object_t rp = xpc_get_type(m) == XPC_TYPE_DICTIONARY ? xpc_dictionary_create_reply(m) : NULL;
			printf("NOTE t=%.3f wantsreply=%d %s\n", now(), rp != NULL, d); fflush(stdout); free(d);
			if (rp) xpc_release(rp);
		});
		xpc_connection_resume(peer);
	});
	xpc_connection_resume(lis);
}

int main(int argc, char **argv)
{
	const char *svc = getenv("__LSXPCSERVICENAME");
	clock_gettime(CLOCK_MONOTONIC, &t0);
	setvbuf(stdout, NULL, _IOLBF, 0);
	c = xpc_connection_create_mach_service(svc ? svc : "com.apple.coreservices.launchservicesd", NULL, svc ? 0 : 2);
	xpc_connection_set_event_handler(c, ^(xpc_object_t e) { char *d = xpc_copy_description(e); printf("CONN-EVENT %s\n", d); free(d); });
	xpc_connection_resume(c);
	for (int i = 1; i < argc; ) {
		xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0);
		int sl = 0;
		const char *page = NULL;
		xpc_dictionary_set_int64(m, "session", -2);
		for (; i < argc && strcmp(argv[i], "--"); i++) {
			char *a = strdup(argv[i]);
			if (!strcmp(a, "deathport")) {
				mach_port_t dp; mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &dp);
				mach_port_insert_right(mach_task_self(), dp, dp, MACH_MSG_TYPE_MAKE_SEND);
				xpc_dictionary_set_mach_send(m, "deathport", dp);
			} else if (!strcmp(a, "listener")) {
				listener_start();
				xpc_dictionary_set_value(m, "listener", xpc_endpoint_create(lis));
			} else if (!strncmp(a, "asn=@", 5)) {
				xpc_dictionary_set_uint64(m, "asn", asn_of(atoi(a + 5)));
			} else if (!strncmp(a, "page=", 5)) {
				page = a + 5;
			} else if (!strncmp(a, "sleep=", 6)) {
				sl = atoi(a + 6);
			} else if (!strncmp(a, "cmd=", 4)) {
				xpc_dictionary_set_int64(m, "command", strtoll(a + 4, 0, 0));
			} else put(m, a);
		}
		i++;
		char *d = xpc_copy_description(m); printf("SEND t=%.3f %s\n", now(), d); free(d);
		xpc_object_t r = xpc_connection_send_message_with_reply_sync(c, m);
		d = xpc_copy_description(r); printf("REPLY %s\n", d); free(d);
		if (nrep < 64) replies[nrep++] = r;
		if (page && xpc_get_type(r) == XPC_TYPE_DICTIONARY && xpc_dictionary_get_value(r, "lsinfopage")) {
			void *p = NULL; size_t n = xpc_shmem_map(xpc_dictionary_get_value(r, "lsinfopage"), &p);
			FILE *f = fopen(page, "wb"); if (f && p) { fwrite(p, 1, n, f); fclose(f); }
			printf("PAGE %s %zu bytes\n", page, n);
		}
		if (sl) sleep(sl);
	}
	return 0;
}
