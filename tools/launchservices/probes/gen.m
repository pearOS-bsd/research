// Icon recipe client of IconServices: ISBundleIcon initWithBundleURL: + ISGenerationRequest generateImageReturningRecordIdentifiers: (what the icon agent calls); optional PNG out.
// Build (macOS): clang -fobjc-arc -framework Foundation -framework ImageIO -framework CoreGraphics gen.m -o gen     Run: ./gen BUNDLE.app SIZE [out.png]
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
int main(int argc, char **argv) {
	dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_NOW);
	id icon = ((id(*)(id,SEL,id))objc_msgSend)([objc_getClass("ISBundleIcon") alloc], sel_getUid("initWithBundleURL:"), [NSURL fileURLWithPath: @(argv[1])]);
	id d = ((id(*)(id,SEL,CGSize,double))objc_msgSend)([objc_getClass("ISImageDescriptor") alloc], sel_getUid("initWithSize:scale:"), CGSizeMake(atof(argv[2]), atof(argv[2])), 1.0);
	id r = [objc_getClass("ISGenerationRequest") new];
	((void(*)(id,SEL,id))objc_msgSend)(r, sel_getUid("setIcon:"), icon);
	((void(*)(id,SEL,id))objc_msgSend)(r, sel_getUid("setImageDescriptor:"), d);
	id ids = nil; NSDate *t = [NSDate date];
	id out = ((id(*)(id,SEL,id*))objc_msgSend)(r, sel_getUid("generateImageReturningRecordIdentifiers:"), &ids);
	printf("time %.3f result %s ids %s\n", -[t timeIntervalSinceNow], out ? class_getName([out class]) : "nil", ids ? [[ids description] UTF8String] : "nil");
	if (out) { printf("%s\n", [[out description] UTF8String]);
		for (Class c = [out class]; c && c != [NSObject class]; c = class_getSuperclass(c)) { unsigned n; Method *m = class_copyMethodList(c, &n); for (unsigned i = 0; i < n; i++) printf("  -%s %s %s\n", class_getName(c), sel_getName(method_getName(m[i])), method_getTypeEncoding(m[i])); free(m); } }
	if (out && argc > 3) { CGImageRef im = ((CGImageRef(*)(id,SEL))objc_msgSend)(out, sel_getUid("CGImage")); CGImageDestinationRef d2 = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[3])], CFSTR("public.png"), 1, NULL); CGImageDestinationAddImage(d2, im, NULL); CGImageDestinationFinalize(d2); }
	return 0;
}
