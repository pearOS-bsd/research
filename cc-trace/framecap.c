/* framecap X Y W H SECONDS INTERVAL_MS OUTDIR: captures a region of the screen repeatedly (CGWindowListCreateImage) and writes OUTDIR/NNN-<ms>.png: the frames of an animation on a Mac without a screen recorder.
 * Build on the Mac: clang -o framecap framecap.c -framework ApplicationServices -framework ImageIO -framework CoreFoundation */
#include <ApplicationServices/ApplicationServices.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <unistd.h>
#include <dlfcn.h>
#include <string.h>
static double now(void) { struct timeval t; gettimeofday(&t, NULL); return t.tv_sec * 1000.0 + t.tv_usec / 1000.0; }
int main(int argc, char **argv)
{
	if (argc < 8) return 2; CGRect r = CGRectMake(atof(argv[1]), atof(argv[2]), atof(argv[3]), atof(argv[4])); double secs = atof(argv[5]), iv = atof(argv[6]); double t0 = now(); int n = 0; CGImageRef (*f)(CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) = dlsym(RTLD_DEFAULT, "CGWindowListCreateImage");      /* obsoleted in macOS 15 for compilation, still in the library */
	CGImageRef *imgs = calloc(4000, sizeof *imgs); double *ts = calloc(4000, sizeof *ts); int cnt = 0;
	while (now() - t0 < secs * 1000 && cnt < 4000) {              /* capture first, encode afterwards: PNG encoding made the loop 7 fps */
		double t = now() - t0; CGImageRef im = f ? f(r, kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageDefault) : NULL;
		if (im) { imgs[cnt] = im; ts[cnt++] = t; }
		double w = iv - (now() - t0 - t); if (w > 0) usleep((useconds_t)(w * 1000));
	}
	for (int i = 0; i < cnt; i++) {
		char p[512]; snprintf(p, sizeof p, "%s/%03d-%04.0f.png", argv[7], n++, ts[i]); CFURLRef u = CFURLCreateFromFileSystemRepresentation(NULL, (UInt8 *)p, strlen(p), false);
		CGImageDestinationRef d = CGImageDestinationCreateWithURL(u, CFSTR("public.png"), 1, NULL); CGImageDestinationAddImage(d, imgs[i], NULL); CGImageDestinationFinalize(d); CFRelease(d); CFRelease(u); CGImageRelease(imgs[i]);
	}
	return 0;
}
