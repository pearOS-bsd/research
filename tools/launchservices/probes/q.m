// Launch Services record lookups of Apple's client against whatever store the server hands out.
// Build (macOS): clang -fobjc-arc -framework Foundation -framework CoreServices q.m -o q
// usage: q bid <bundle-id> | url <path> | pxy <path> | seq
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#define MSG(T, ...) ((T (*)(__VA_ARGS__))objc_msgSend)
int main(int argc, char **argv) { @autoreleasepool { setvbuf(stdout, 0, _IOLBF, 0);
	dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_NOW);
	const char *m = argc > 1 ? argv[1] : "seq"; NSError *e = nil; Class B = NSClassFromString(@"LSBundleRecord");
	if (!strcmp(m, "seq")) { unsigned long long n = 0; id u = nil; MSG(void, id, SEL, unsigned long long *, id *)(NSClassFromString(@"LSRecord"), sel_registerName("_is_getSequenceNumber:andUUID:"), &n, &u); printf("RESULT seq=%llu uuid=%s\n", n, [[u description] UTF8String]); return 0; }
	id r = nil;
	if (!strcmp(m, "bid")) r = MSG(id, id, SEL, id, BOOL, id *)(B, sel_registerName("bundleRecordWithBundleIdentifier:allowPlaceholder:error:"), @(argv[2]), NO, &e);
	else if (!strcmp(m, "url")) r = MSG(id, id, SEL, id, BOOL, id *)(MSG(id, id, SEL)(NSClassFromString(@"LSApplicationRecord"), sel_registerName("alloc")), sel_registerName("initWithURL:allowPlaceholder:error:"), [NSURL fileURLWithPath: @(argv[2])], NO, &e);
	else if (!strcmp(m, "pxy")) { r = MSG(id, id, SEL, id, id *)(NSClassFromString(@"LSBundleProxy"), sel_registerName("bundleProxyForURL:error:"), [NSURL fileURLWithPath: @(argv[2])], &e); }
	printf("RESULT record=%s err=%s\n", [[r description] UTF8String], [[e description] UTF8String]);
	if (r) { for (NSString *k in @[ @"bundleIdentifier", @"URL", @"localizedName", @"iconDictionary", @"primaryIconName", @"iconFileNames", @"infoDictionary", @"executableURL", @"compatibilityState", @"bundleVersion", @"shortVersionString", @"typeForInstallMachinery", @"developerType", @"bundleClass", @"teamIdentifier", @"claims", @"supportedTypes" ]) { @try { id v = [r valueForKey: k]; printf("  %s = %s\n", k.UTF8String, [[v description] UTF8String]); } @catch (id x) { printf("  %s !! %s\n", k.UTF8String, [[x description] UTF8String]); } } }
	return r ? 0 : 1; } }
