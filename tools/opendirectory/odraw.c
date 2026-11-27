/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 *
 * Hand-made requests to the opendirectoryd pipes (macOS test helper): odraw SERVICE RPC [key=int|key=s:string|key=u:UUID ...]
 * prints the reply (or the error of xpc_pipe_routine).  Build: clang odraw.c -o odraw */
#include <xpc/xpc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uuid/uuid.h>
typedef void *xpc_pipe_t;
extern xpc_pipe_t xpc_pipe_create(const char *name, uint64_t flags);
extern int xpc_pipe_routine(xpc_pipe_t p, xpc_object_t m, xpc_object_t *reply);
int main(int argc, char **argv) {
	if (argc < 3) return 2;
	xpc_pipe_t p = xpc_pipe_create(argv[1], 0);
	xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0), r = NULL;
	if (strcmp(argv[2], "-")) xpc_dictionary_set_string(m, "rpc_name", argv[2]);
	xpc_dictionary_set_int64(m, "rpc_version", 2);
	for (int i = 3; i < argc; i++) {
		char *eq = strchr(argv[i], '='); if (!eq) continue; *eq++ = 0;
		if (!strncmp(eq, "s:", 2)) xpc_dictionary_set_string(m, argv[i], eq + 2);
		else if (!strncmp(eq, "u:", 2)) { uuid_t u; uuid_parse(eq + 2, u); xpc_dictionary_set_uuid(m, argv[i], u); }
		else xpc_dictionary_set_int64(m, argv[i], atoll(eq));
	}
	int rc = xpc_pipe_routine(p, m, &r);
	printf("rc %d\n", rc);
	if (r) { char *d = xpc_copy_description(r); printf("%s\n", d); free(d); }
	return 0;
}
