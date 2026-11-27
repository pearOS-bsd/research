/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 *
 * DYLD_INSERT_LIBRARIES interposer (macOS test helper, not part of the product): records the conversation of libsystem_info
 * (xpc pipes: getpwuid & co, mbr_*) and of CoreFoundation's distributed notification center (xpc connections) with the
 * xpc description of every message, request and reply; incoming messages of a connection are recorded by wrapping its event
 * handler.  IS_REDIRECT="from=to,..." renames Mach services for xpc_pipe_create and xpc_connection_create_mach_service
 * (point Apple's client at our daemons); ODCAP_QUIET=1 turns the log off (only the redirect).
 * Build: clang -dynamiclib odcap.c -o odcap.dylib       Use: DYLD_INSERT_LIBRARIES=./odcap.dylib ./odt ... */
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <Block.h>

typedef void *xpc_pipe_t;
extern xpc_pipe_t xpc_pipe_create(const char *name, uint64_t flags);
extern int xpc_pipe_routine(xpc_pipe_t p, xpc_object_t m, xpc_object_t *reply);
extern int xpc_pipe_routine_with_flags(xpc_pipe_t p, xpc_object_t m, xpc_object_t *reply, uint64_t flags);
extern int xpc_pipe_simpleroutine(xpc_pipe_t p, xpc_object_t m);

static int quiet(void) { return getenv("ODCAP_QUIET") != NULL; }
static const char *
map(const char *name)
{
	char buf[4096];
	const char *r = getenv("IS_REDIRECT");

	if (!r || !name) return name;
	strncpy(buf, r, sizeof buf - 1); buf[sizeof buf - 1] = 0;
	for (char *save = NULL, *p = strtok_r(buf, ",", &save); p; p = strtok_r(NULL, ",", &save)) {
		char *eq = strchr(p, '=');
		if (eq) { *eq = 0; if (!strcmp(p, name)) return strdup(eq + 1); }
	}
	return name;
}
static void
dump(const char *tag, const char *who, xpc_object_t m)
{
	char *d;

	if (quiet()) return;
	d = m ? xpc_copy_description(m) : strdup("(null)");
	fprintf(stderr, "ODCAP %s %s: %s\n", tag, who ? who : "-", d);
	free(d);
}
static const char *cname(xpc_connection_t c) { const char *n = c ? xpc_connection_get_name(c) : NULL; return n ? n : "-"; }

static xpc_pipe_t
my_pipe_create(const char *name, uint64_t flags)
{
	const char *to = map(name);

	if (!quiet()) fprintf(stderr, "ODCAP pipe_create %s -> %s flags=0x%llx\n", name, to, (unsigned long long)flags);
	return xpc_pipe_create(to, flags);
}
static int
my_pipe_routine(xpc_pipe_t p, xpc_object_t m, xpc_object_t *reply)
{
	int rc;

	dump("pipe_request", "", m);
	rc = xpc_pipe_routine(p, m, reply);
	if (!quiet()) fprintf(stderr, "ODCAP pipe_rc %d\n", rc);
	if (rc == 0 && reply) dump("pipe_reply", "", *reply);
	return rc;
}
static int
my_pipe_routine_flags(xpc_pipe_t p, xpc_object_t m, xpc_object_t *reply, uint64_t fl)
{
	int rc;

	dump("pipe_request(flags)", "", m);
	rc = xpc_pipe_routine_with_flags(p, m, reply, fl);
	if (!quiet()) fprintf(stderr, "ODCAP pipe_rc %d\n", rc);
	if (rc == 0 && reply) dump("pipe_reply", "", *reply);
	return rc;
}
static int my_pipe_simple(xpc_pipe_t p, xpc_object_t m) { dump("pipe_simple", "", m); return xpc_pipe_simpleroutine(p, m); }

static xpc_connection_t
my_create(const char *name, dispatch_queue_t q, uint64_t flags)
{
	const char *to = map(name);

	if (!quiet()) fprintf(stderr, "ODCAP connect %s -> %s flags=%llu\n", name, to, (unsigned long long)flags);
	return xpc_connection_create_mach_service(to, q, flags);
}
static void
my_set_handler(xpc_connection_t c, xpc_handler_t h)
{
	xpc_handler_t hh = Block_copy(h);

	xpc_connection_set_event_handler(c, ^(xpc_object_t e) { dump("event", cname(c), e); hh(e); });
}
static void my_send(xpc_connection_t c, xpc_object_t m) { dump("send", cname(c), m); xpc_connection_send_message(c, m); }
static void
my_send_reply(xpc_connection_t c, xpc_object_t m, dispatch_queue_t q, xpc_handler_t h)
{
	xpc_handler_t hh = Block_copy(h);

	dump("asend", cname(c), m);
	xpc_connection_send_message_with_reply(c, m, q, ^(xpc_object_t r) { dump("areply", cname(c), r); if (hh) hh(r); });
}
static xpc_object_t
my_send_sync(xpc_connection_t c, xpc_object_t m)
{
	xpc_object_t r;

	dump("ssend", cname(c), m);
	r = xpc_connection_send_message_with_reply_sync(c, m);
	dump("sreply", cname(c), r);
	return r;
}

#define INTERPOSE(a, b) __attribute__((used)) static struct { const void *n, *o; } _ip_##b __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&a, (const void *)(unsigned long)&b };
INTERPOSE(my_pipe_create, xpc_pipe_create)
INTERPOSE(my_pipe_routine, xpc_pipe_routine)
INTERPOSE(my_pipe_routine_flags, xpc_pipe_routine_with_flags)
INTERPOSE(my_pipe_simple, xpc_pipe_simpleroutine)
INTERPOSE(my_create, xpc_connection_create_mach_service)
INTERPOSE(my_set_handler, xpc_connection_set_event_handler)
INTERPOSE(my_send, xpc_connection_send_message)
INTERPOSE(my_send_reply, xpc_connection_send_message_with_reply)
INTERPOSE(my_send_sync, xpc_connection_send_message_with_reply_sync)
