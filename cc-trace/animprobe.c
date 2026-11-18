/* animprobe CLICK_X CLICK_Y DELAY_MS X Y W H OUT.png: posts a mouse click, waits DELAY_MS, captures one frame of the region and prints "start end" (ms after the click) of the capture call.
 * A sweep of DELAY_MS gives the frames of an animation that is faster than the 10 frames / s a capture loop can do in the VM (software rendering).
 * Build on the Mac: clang -o animprobe animprobe.c -framework ApplicationServices -framework ImageIO -framework CoreFoundation */
#include <ApplicationServices/ApplicationServices.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <dlfcn.h>
static double now(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec * 1000.0 + t.tv_usec / 1000.0; }
int main(int argc, char **argv)
{
	if (argc < 9) return 2; CGPoint p = CGPointMake(atof(argv[1]), atof(argv[2])); double delay = atof(argv[3]); CGRect r = CGRectMake(atof(argv[4]), atof(argv[5]), atof(argv[6]), atof(argv[7]));
	CGImageRef (*f)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) = dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");
	CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(150000);
	double t0 = now();
	e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e);
	e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap, e); CFRelease(e);
	if (delay > 0) usleep((useconds_t)(delay * 1000));
	double a = now() - t0; CGImageRef im = f ? f(r, kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault) : NULL; double b = now() - t0;
	if (im) { CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (UInt8 *)argv[8], strlen(argv[8]), false); CGImageDestinationRef d = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL); CGImageDestinationAddImage(d, im, NULL); CGImageDestinationFinalize(d); }
	printf("%.0f %.0f\n", a, b); return im ? 0 : 1;
}
