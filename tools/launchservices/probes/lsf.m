// Test server: hands a csstore FILE (env LSF_STORE, re-read on every request) to Apple's Launch Services client as com.apple.lsd.mapdb does
// (reply of getServerStoreNonBlocking..., see docs/LAUNCHSERVICES-WIRE.md section 3).  Mach service name: env LSF_NAME.  Test tool, our own code (BSD-2-Clause).
// Build (macOS): clang -fobjc-arc -framework Foundation lsf.m -o lsf
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#define MSG(T, ...) ((T (*)(__VA_ARGS__))objc_msgSend)
@interface S : NSObject <NSXPCListenerDelegate> @end
@implementation S
- (void)getServerStoreNonBlockingWithCompletionHandler:(void (^)(id, id, id, BOOL, NSError *))reply {
	NSURL *url = [NSURL fileURLWithPath: @(getenv("LSF_STORE"))]; NSError *e = nil;
	id store = MSG(id, id, SEL, id, NSError **)([NSClassFromString(@"_CSStore") alloc], sel_registerName("initWithContentsOfURL:error:"), url, &e);
	id node = MSG(id, id, SEL, id, unsigned, NSError **)([NSClassFromString(@"FSNode") alloc], sel_registerName("initWithURL:flags:error:"), url, 0, NULL);
	fprintf(stderr, "lsf: store %s %s\n", store ? "ok" : [[e description] UTF8String], getenv("LSF_STORE")); reply(store, node, nil, NO, store ? nil : e);
}
- (void)getSystemContentStoreWithCompletionHandler:(void (^)(id, id, NSError *))reply { reply(nil, nil, [NSError errorWithDomain: NSOSStatusErrorDomain code: -10814 userInfo: nil]); }
- (void)getServerStatusWithCompletionHandler:(void (^)(unsigned))reply { reply(256); }
- (void)getSystemModeWithCompletionHandler:(void (^)(NSString *, NSError *))reply { reply(nil, nil); }
- (void)getPreferencesWithCompletionHandler:(void (^)(NSDictionary *, NSError *))reply { reply(@{}, nil); }
- (void)getSettingsStoreConfigurationWithCompletionHandler:(void (^)(id, NSError *))reply { reply(nil, [NSError errorWithDomain: NSOSStatusErrorDomain code: -10814 userInfo: nil]); }
- (void)getSelectedDeveloperDirectoryURLWithCompletionHandler:(void (^)(NSURL *))reply { reply(nil); }
- (void)getKernelPackageExtensionsWithCompletionHandler:(void (^)(NSArray *, NSError *))reply { reply(@[ @"app", @"bundle", @"framework", @"plugin", @"kext" ], nil); }
- (void)getApplicationCategoryIdentifiersSetWithCompletionHandler:(void (^)(NSSet *, NSError *))reply { reply([NSSet set], nil); }
- (void)getSessionLanguagesForImproperlyLocalizedProcessWithCompletionHandler:(void (^)(NSArray *))reply { reply(@[]); }
- (BOOL)listener:(NSXPCListener *)l shouldAcceptNewConnection:(NSXPCConnection *)c {
	NSXPCInterface *i = MSG(id, id, SEL)(NSClassFromString(@"_LSDReadService"), sel_registerName("XPCInterface")); if (!i) return NO;
	c.exportedInterface = i; c.exportedObject = self; [c resume]; return YES; }
@end
int main(void) { @autoreleasepool {
	dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW);
	static S *s; s = [S new]; NSXPCListener *l = [[NSXPCListener alloc] initWithMachServiceName: @(getenv("LSF_NAME"))]; l.delegate = s; [l resume]; [[NSRunLoop currentRunLoop] run]; } return 0; }
