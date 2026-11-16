/* Move the mouse on the Mac VM:  mouse X Y   |   mouse right X Y   |   mouse drag X1 Y1 X2 Y2
 *    (synthetic CGEvent, needs the Accessibility TCC row of sshd-keygen-wrapper); with a third argument "click" it also clicks.
 * Build on the Mac: clang -o mouse mouse.c -framework CoreGraphics -framework CoreFoundation */
#include <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv)
{
	if (argc < 3) return 2;
	if (!strcmp(argv[1], "drag") && argc >= 6) {                  /* mouse drag X1 Y1 X2 Y2 : press, move in steps, release */
		CGPoint a = CGPointMake(atof(argv[2]), atof(argv[3])), b = CGPointMake(atof(argv[4]), atof(argv[5]));
		CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, a, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(150000);
		e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, a, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(150000);
		for (int i = 1; i <= 20; i++) { CGPoint q = CGPointMake(a.x + (b.x - a.x) * i / 20, a.y + (b.y - a.y) * i / 20); e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDragged, q, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(40000); }
		usleep(200000); e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, b, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); return 0;
	}
	if (!strcmp(argv[1], "right") && argc >= 4) {                 /* mouse right X Y : right click */
		CGPoint q = CGPointMake(atof(argv[2]), atof(argv[3]));
		CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, q, kCGMouseButtonRight); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(200000);
		e = CGEventCreateMouseEvent(NULL, kCGEventRightMouseDown, q, kCGMouseButtonRight); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(80000);
		e = CGEventCreateMouseEvent(NULL, kCGEventRightMouseUp, q, kCGMouseButtonRight); CGEventPost(kCGHIDEventTap, e); CFRelease(e); return 0;
	}
	CGPoint p = CGPointMake(atof(argv[1]), atof(argv[2]));
	CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e);
	if (argc > 3 && !strcmp(argv[3], "click")) {
		usleep(200000);
		e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(60000);
		e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e);
	}
	return 0;
}
