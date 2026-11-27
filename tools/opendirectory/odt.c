/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 *
 * Probe of libinfo and membership (macOS test helper): every argument is one call, its result is printed.
 *   pwuid:N pwnam:NAME grgid:N grnam:NAME gl:NAME (getgrouplist) pwent grent
 *   u2u:UID g2u:GID uu2id:UUID n2u:USERNAME gn2u:GROUPNAME ck:UID:GID (mbr_check_membership) cs:UID:SERVICE (mbr_check_service_membership)
 *   u2n:UID (mbr_identifier_translate uid -> name)
 * Build: clang odt.c -o odt */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <uuid/uuid.h>
#include <membership.h>

extern int mbr_identifier_translate(int, const void *, size_t, int, void **, int *);
extern int mbr_check_service_membership(const uuid_t, const char *, int *);
extern int mbr_user_name_to_uuid(const char *, uuid_t);
extern int mbr_group_name_to_uuid(const char *, uuid_t);

static void pw(struct passwd *p) {
	if (!p) { printf("  (null)\n"); return; }
	printf("  %s:%s:%u:%u:%ld:%ld:%s:%s:%s:%s\n", p->pw_name, p->pw_passwd, p->pw_uid, p->pw_gid, (long)p->pw_change, (long)p->pw_expire,
	    p->pw_class, p->pw_gecos, p->pw_dir, p->pw_shell);
}
static void gr(struct group *g) {
	if (!g) { printf("  (null)\n"); return; }
	printf("  %s:%s:%u:", g->gr_name, g->gr_passwd, g->gr_gid);
	for (char **m = g->gr_mem; m && *m; m++) printf("%s%s", *m, m[1] ? "," : "");
	printf("\n");
}
static void pu(uuid_t u) { char s[40]; uuid_unparse_upper(u, s); printf("  %s\n", s); }

int main(int argc, char **argv) {
	for (int i = 1; i < argc; i++) {
		char *a = argv[i], *v = strchr(a, ':');
		uuid_t u; int rc, t, ism;
		if (v) v++;
		printf("== %s\n", a); fflush(stdout);
		if (!strncmp(a, "pwuid:", 6)) pw(getpwuid(atoi(v)));
		else if (!strncmp(a, "pwnam:", 6)) pw(getpwnam(v));
		else if (!strncmp(a, "grgid:", 6)) gr(getgrgid(atoi(v)));
		else if (!strncmp(a, "grnam:", 6)) gr(getgrnam(v));
		else if (!strncmp(a, "gl:", 3)) { int g[64], n = 64; rc = getgrouplist(v, 20, g, &n); printf("  rc %d n %d:", rc, n); for (int k = 0; k < n; k++) printf(" %d", g[k]); printf("\n"); }
		else if (!strcmp(a, "pwent")) { struct passwd *p; int n = 0; setpwent(); while ((p = getpwent()) && n++ < 5) pw(p); endpwent(); }
		else if (!strcmp(a, "grent")) { struct group *g; int n = 0; setgrent(); while ((g = getgrent()) && n++ < 5) gr(g); endgrent(); }
		else if (!strncmp(a, "u2u:", 4)) { rc = mbr_uid_to_uuid(atoi(v), u); printf("  rc %d\n", rc); if (!rc) pu(u); }
		else if (!strncmp(a, "g2u:", 4)) { rc = mbr_gid_to_uuid(atoi(v), u); printf("  rc %d\n", rc); if (!rc) pu(u); }
		else if (!strncmp(a, "n2u:", 4)) { rc = mbr_user_name_to_uuid(v, u); printf("  rc %d\n", rc); if (!rc) pu(u); }
		else if (!strncmp(a, "gn2u:", 5)) { rc = mbr_group_name_to_uuid(v, u); printf("  rc %d\n", rc); if (!rc) pu(u); }
		else if (!strncmp(a, "uu2id:", 6)) { uid_t id; uuid_parse(v, u); rc = mbr_uuid_to_id(u, &id, &t); printf("  rc %d id %u type %d\n", rc, rc ? 0 : id, rc ? -9 : t); }
		else if (!strncmp(a, "u2n:", 4)) { id_t id = atoi(v); void *r = 0; rc = mbr_identifier_translate(ID_TYPE_UID, &id, sizeof id, ID_TYPE_USERNAME, &r, &t); printf("  rc %d %s type %d\n", rc, rc ? "-" : (char *)r, t); }
		else if (!strncmp(a, "ck:", 3)) { uuid_t g; int uid = atoi(v), gid = atoi(strchr(v, ':') + 1); mbr_uid_to_uuid(uid, u); mbr_gid_to_uuid(gid, g); rc = mbr_check_membership(u, g, &ism); printf("  rc %d ismember %d\n", rc, ism); }
		else if (!strncmp(a, "cs:", 3)) { int uid = atoi(v); mbr_uid_to_uuid(uid, u); rc = mbr_check_service_membership(u, strchr(v, ':') + 1, &ism); printf("  rc %d ismember %d\n", rc, ism); }
		else printf("  ?\n");
		fflush(stdout);
	}
	return 0;
}
