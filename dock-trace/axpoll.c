/* axpoll TITLE SECONDS [INTERVAL_MS] [PID]: samples the accessibility position and size of the Dock item with that title and prints "ms x y w h" (the timing curve of an animation: bounce, magnification, autohide ...).
 * Also with TITLE "list": the Dock's AXList frame.  Build on the Mac: clang -o axpoll axpoll.c -framework ApplicationServices -framework CoreFoundation */
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
static double now(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec * 1000.0 + t.tv_usec / 1000.0; }
static AXUIElementRef find(AXUIElementRef e, const char *title, int depth)
{
	CFTypeRef t = NULL; if (AXUIElementCopyAttributeValue(e, kAXTitleAttribute, &t) == 0 && t) { char b[256]; int ok = CFStringGetCString(t, b, sizeof b, kCFStringEncodingUTF8); CFRelease(t); if (ok && !strcmp(b, title)) return (AXUIElementRef)CFRetain(e); }
	if (depth > 4) return NULL; CFArrayRef kids = NULL; if (AXUIElementCopyAttributeValue(e, kAXChildrenAttribute, (CFTypeRef *)&kids) != 0 || !kids) return NULL;
	AXUIElementRef r = NULL; for (CFIndex i = 0; i < CFArrayGetCount(kids) && !r; i++) r = find((AXUIElementRef)CFArrayGetValueAtIndex(kids, i), title, depth + 1); CFRelease(kids); return r;
}
int main(int argc, char **argv)
{
	if (argc < 3) return 2; double secs = atof(argv[2]), ms = argc > 3 ? atof(argv[3]) : 5; pid_t pid = 0;
	if (argc > 4) pid = atoi(argv[4]); else { FILE *p = popen("pgrep -x Dock", "r"); if (p) { if (fscanf(p, "%d", &pid) != 1) pid = 0; pclose(p); } }
	AXUIElementRef app = AXUIElementCreateApplication(pid), item = strcmp(argv[1], "list") ? find(app, argv[1], 0) : NULL;
	if (!strcmp(argv[1], "list")) { CFArrayRef k = NULL; AXUIElementCopyAttributeValue(app, kAXChildrenAttribute, (CFTypeRef *)&k); if (k && CFArrayGetCount(k)) item = (AXUIElementRef)CFRetain(CFArrayGetValueAtIndex(k, 0)); }
	if (!item) { fprintf(stderr, "axpoll: no item %s\n", argv[1]); return 1; }
	double t0 = now();
	while (now() - t0 < secs * 1000) {
		CFTypeRef pv = NULL, sv = NULL; CGPoint p = { 0, 0 }; CGSize s = { 0, 0 };
		if (AXUIElementCopyAttributeValue(item, kAXPositionAttribute, &pv) == 0 && pv) { AXValueGetValue(pv, kAXValueCGPointType, &p); CFRelease(pv); }
		if (AXUIElementCopyAttributeValue(item, kAXSizeAttribute, &sv) == 0 && sv) { AXValueGetValue(sv, kAXValueCGSizeType, &s); CFRelease(sv); }
		printf("%.0f %.1f %.1f %.1f %.1f\n", now() - t0, p.x, p.y, s.width, s.height); fflush(stdout); usleep((useconds_t)(ms * 1000));
	}
	return 0;
}
