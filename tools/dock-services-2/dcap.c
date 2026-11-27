/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 *
 * DYLD_INSERT_LIBRARIES interposer (macOS test helper, not part of the product): records every XPC connection a client makes
 * (xpc_connection_create_mach_service AND xpc_connection_create, the second one is how framework XPC services such as
 * com.apple.carboncore.csnameddata are reached), every message it sends, every reply and every incoming message, with the
 * xpc description; NSXPC "root" blobs are saved to $DCAP_DIR (default /tmp/dcap) as NNN_tag.root (decode: ../iconservices/bp17.py).
 * IS_REDIRECT="from=to,..." renames services: a renamed xpc_connection_create(name) becomes xpc_connection_create_mach_service(to)
 * (a test job of launchd serves it).  Based on ../dock-services/xcap.c and ../opendirectory/odcap.c.
 * Build: clang -dynamiclib dcap.c -o dcap.dylib     Use: DYLD_INSERT_LIBRARIES=./dcap.dylib ./client */
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <Block.h>

static int n;
static const char *dir(void) { const char *d = getenv("DCAP_DIR"); return d ? d : "/tmp/dcap"; }
static const char *
map(const char *name)
{
	char buf[4096];
	const char *r = getenv("IS_REDIRECT");

	if (!r || !name) return NULL;
	strncpy(buf, r, sizeof buf - 1); buf[sizeof buf - 1] = 0;
	for (char *save = NULL, *p = strtok_r(buf, ",", &save); p; p = strtok_r(NULL, ",", &save)) {
		char *eq = strchr(p, '=');
		if (eq) { *eq = 0; if (!strcmp(p, name)) return strdup(eq + 1); }
	}
	return NULL;
}
static void
dump(xpc_object_t msg, const char *tag, xpc_connection_t conn)
{
	int id = __sync_fetch_and_add(&n, 1);
	const char *cn = conn ? xpc_connection_get_name(conn) : NULL;
	char *d;

	fprintf(stderr, "CAP#%03d %s conn=%s pid=%d\n", id, tag, cn ? cn : "-", conn ? xpc_connection_get_pid(conn) : 0);
	if (xpc_get_type(msg) == XPC_TYPE_DICTIONARY) {
		size_t l = 0;
		const void *p = xpc_dictionary_get_data(msg, "root", &l);
		if (p) {
			char nm[512]; FILE *f;
			snprintf(nm, sizeof nm, "%s/%03d_%s.root", dir(), id, tag);
			if ((f = fopen(nm, "wb"))) { fwrite(p, 1, l, f); fclose(f); }
			fprintf(stderr, "  root_len=%zu -> %s\n", l, nm);
		}
	}
	d = xpc_copy_description(msg); fprintf(stderr, "%s\n", d); free(d);
}
static xpc_connection_t
my_create_mach_service(const char *name, dispatch_queue_t q, uint64_t flags)
{
	const char *to = map(name);

	fprintf(stderr, "CONNECT mach %s%s%s flags=%llu\n", name, to ? " -> " : "", to ? to : "", (unsigned long long)flags);
	return xpc_connection_create_mach_service(to ? to : name, q, flags);
}
static xpc_connection_t
my_create(const char *name, dispatch_queue_t q)
{
	const char *to = map(name);

	fprintf(stderr, "CONNECT xpcservice %s%s%s\n", name ? name : "(anonymous)", to ? " -> " : "", to ? to : "");
	return to ? xpc_connection_create_mach_service(to, q, 0) : xpc_connection_create(name, q);
}
static void my_send(xpc_connection_t c, xpc_object_t m) { dump(m, "send", c); xpc_connection_send_message(c, m); }
static void
my_send_reply(xpc_connection_t c, xpc_object_t m, dispatch_queue_t q, xpc_handler_t h)
{
	xpc_handler_t hh = Block_copy(h);

	dump(m, "asend", c);
	xpc_connection_send_message_with_reply(c, m, q, ^(xpc_object_t r) { dump(r, "areply", c); if (hh) hh(r); });
}
static xpc_object_t
my_send_sync(xpc_connection_t c, xpc_object_t m)
{
	xpc_object_t r;

	dump(m, "ssend", c);
	r = xpc_connection_send_message_with_reply_sync(c, m);
	if (r) dump(r, "sreply", c);
	return r;
}
static void
my_set_handler(xpc_connection_t c, xpc_handler_t h)
{
	xpc_handler_t hh = Block_copy(h);

	xpc_connection_set_event_handler(c, ^(xpc_object_t e) { dump(e, "recv", c); hh(e); });
}

#define INTERPOSE(a, b) __attribute__((used)) static struct { const void *n, *o; } _ip_##b __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&a, (const void *)(unsigned long)&b };
INTERPOSE(my_create_mach_service, xpc_connection_create_mach_service)
INTERPOSE(my_create, xpc_connection_create)
INTERPOSE(my_send, xpc_connection_send_message)
INTERPOSE(my_send_reply, xpc_connection_send_message_with_reply)
INTERPOSE(my_send_sync, xpc_connection_send_message_with_reply_sync)
INTERPOSE(my_set_handler, xpc_connection_set_event_handler)
