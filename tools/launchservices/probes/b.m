// Look a string up in a binding table of a csstore file with Apple's CoreServicesStore: _CSStringBindingFindStringAndBindings.
// Build (macOS): clang -fobjc-arc -framework Foundation b.m -o b      Run: ./b FILE TABLENAME STRING   (TABLENAME: BundleIDBinding, ExtensionBinding, UTIBinding ...)
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
typedef int (*Find)(void *store, void *map, const char *chars, unsigned len, unsigned *strId, unsigned *bindings);
typedef int (*Init)(void *store, CFStringRef table, unsigned classNameId, unsigned char flag, void *map);
typedef const void *(*GetUnit)(void *store, unsigned table, unsigned unit, unsigned *len);
int main(int argc, char **argv) { @autoreleasepool { setvbuf(stdout, 0, _IOLBF, 0);
	void *h = dlopen("/System/Library/PrivateFrameworks/CoreServicesStore.framework/CoreServicesStore", RTLD_NOW);
	Find f = (Find)dlsym(h, "CSStringBindingFindStringAndBindings"); GetUnit gu = (GetUnit)dlsym(h, "CSStoreGetUnit");
	NSError *e = nil; id s = [NSClassFromString(@"_CSStore") alloc];
	s = ((id(*)(id, SEL, id, id *))objc_msgSend)(s, NSSelectorFromString(@"initWithContentsOfURL:error:"), [NSURL fileURLWithPath: @(argv[1])], &e);
	if (!s) { printf("open failed %s\n", [[e description] UTF8String]); return 1; }
	Init in = (Init)dlsym(h, "CSStringBindingStoreInit"); static char map[0x200] __attribute__((aligned(16)));
	int ir = in((__bridge void *)s, (__bridge CFStringRef)@(argv[2]), 0, 1, map); printf("init %#x\n", ir);
	unsigned sid = 0, bid = 0; int r = f((__bridge void *)s, map, argv[3], (unsigned)strlen(argv[3]), &sid, &bid);
	printf("result %#x string id %#x bindings %#x\n", r, sid, bid);
	if (bid) { unsigned len = 0; const unsigned char *p = gu((__bridge void *)s, 128, bid, &len); printf("array unit len %u:", len); for (unsigned i = 0; p && i < len; i++) printf(" %02x", p[i]); printf("\n"); }
}}
