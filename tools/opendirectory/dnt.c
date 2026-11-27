/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 *
 * Probe of the distributed notification center (macOS test helper).
 *   dnt obs NAME [OBJECT] [SECONDS] [SB]  observe NAME ("*" = every name), print what arrives; SB = suspension behavior 1 Drop 2 Coalesce 3 Hold 4 DeliverImmediately
 *   dnt post NAME [OBJECT] [k=v ...]        post NAME with OBJECT and a userInfo of strings (flags: DNT_FLAGS=n, kCFNotificationDeliverImmediately=1 PostToAllSessions=2)
 *   dnt both NAME                           observe and post in one process
 *   dnt two NAME OBJECT [SECONDS]           two observers in one process: NAME with any object and NAME with OBJECT
 * Build: clang dnt.c -o dnt -framework CoreFoundation */
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void
cb(CFNotificationCenterRef c, void *obs, CFNotificationName name, const void *object, CFDictionaryRef ui)
{
	char n[256] = "", o[256] = "";

	if (name) CFStringGetCString(name, n, sizeof n, kCFStringEncodingUTF8);
	if (object && CFGetTypeID(object) == CFStringGetTypeID()) CFStringGetCString(object, o, sizeof o, kCFStringEncodingUTF8);
	printf("GOT name=%s object=%s userInfo=", n, o);
	if (ui) { CFStringRef d = CFCopyDescription(ui); char b[2048]; CFStringGetCString(d, b, sizeof b, kCFStringEncodingUTF8); printf("%s", b); CFRelease(d); } else printf("(null)");
	printf("\n"); fflush(stdout);
}
static CFStringRef s(const char *c) { return c ? CFStringCreateWithCString(0, c, kCFStringEncodingUTF8) : NULL; }

int
main(int argc, char **argv)
{
	CFNotificationCenterRef dc = CFNotificationCenterGetDistributedCenter();

	if (argc < 3) return 2;
	if (!strcmp(argv[1], "two") && argc > 3) {
		CFNotificationCenterAddObserver(dc, (void *)1, cb, s(argv[2]), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
		CFNotificationCenterAddObserver(dc, (void *)2, cb, s(argv[2]), s(argv[3]), CFNotificationSuspensionBehaviorDeliverImmediately);
		printf("observing\n"); fflush(stdout);
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, argc > 4 ? atof(argv[4]) : 5, false);
		return 0;
	}
	if (!strcmp(argv[1], "obs") || !strcmp(argv[1], "both")) {
		const char *nm = argv[2], *ob = argc > 3 && strcmp(argv[3], "-") ? argv[3] : NULL;
		double secs = argc > 4 ? atof(argv[4]) : 5;
		CFNotificationSuspensionBehavior sb = argc > 5 ? atoi(argv[5]) : CFNotificationSuspensionBehaviorDeliverImmediately;

		if (!strcmp(argv[1], "both")) { ob = NULL; secs = 2; }
		CFNotificationCenterAddObserver(dc, (void *)1, cb, strcmp(nm, "*") ? s(nm) : NULL, s(ob), sb);
		printf("observing\n"); fflush(stdout);
		if (!strcmp(argv[1], "both")) {
			CFStringRef k = s("key"), v = s("value");
			CFDictionaryRef ui = CFDictionaryCreate(0, (const void **)&k, (const void **)&v, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			CFNotificationCenterPostNotificationWithOptions(dc, s(nm), s("obj"), ui, kCFNotificationDeliverImmediately);
		}
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, secs, false);
		CFNotificationCenterRemoveObserver(dc, (void *)1, strcmp(nm, "*") ? s(nm) : NULL, s(ob));
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.3, false);
	} else if (!strcmp(argv[1], "post")) {
		CFMutableDictionaryRef ui = NULL;
		const char *fl = getenv("DNT_FLAGS");

		for (int i = 4; i < argc; i++) {
			char *eq = strchr(argv[i], '=');
			if (!eq) continue;
			if (!ui) ui = CFDictionaryCreateMutable(0, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			*eq = 0; CFDictionarySetValue(ui, s(argv[i]), s(eq + 1));
		}
		CFNotificationCenterPostNotificationWithOptions(dc, s(argv[2]), argc > 3 && strcmp(argv[3], "-") ? s(argv[3]) : NULL, ui, fl ? atoi(fl) : 0);
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
		printf("posted\n");
	}
	return 0;
}
