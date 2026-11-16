/* Move the mouse on the Mac VM:  mouse X Y   (synthetic CGEvent, needs the Accessibility TCC row of sshd-keygen-wrapper); with a third argument "click" it also clicks.
 * Build on the Mac: clang -o mouse mouse.c -framework CoreGraphics -framework CoreFoundation */
#include <CoreGraphics/CoreGraphics.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv)
{
	if (argc < 3) return 2;
	CGPoint p = CGPointMake(atof(argv[1]), atof(argv[2]));
	CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e);
	if (argc > 3 && !strcmp(argv[3], "click")) {
		usleep(200000);
		e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(60000);
		e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e);
	}
	return 0;
}
