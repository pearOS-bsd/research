// lsc.m - Apple's LaunchServices client (AppKit + the private _LS calls WebKit uses) against a launchservicesd, to check a server of ours
// with the real client code: check-in through NSApplication, the record, the front-to-back list, the meta information, and the
// notifications the client library decodes (it registers a block, then starts itself as a regular application that checks in and quits; NSWorkspace launch / terminate notifications are printed).
// Mac VM: clang -fobjc-arc -framework Cocoa lsc.m -o lsc;   [__LSXPCSERVICENAME=com.pearos.t.lsd] ./lsc
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <spawn.h>
#include <sys/wait.h>
typedef const void *LSASNRef;
typedef int LSSessionID;
typedef int LSNotificationCode;
typedef uint64_t LSNotificationID;
extern char **environ;
static void *ls;
#define F(ret, name, ...) ret (*name)(__VA_ARGS__) = (ret (*)(__VA_ARGS__))dlsym(ls, #name)
static NSString *desc(CFTypeRef o) { return o ? [(__bridge id)o description] : @"(null)"; }
int main(int argc, char **argv) { @autoreleasepool {
	setvbuf(stdout, 0, _IOLBF, 0);
	if (argc > 1 && !strcmp(argv[1], "child")) {	/* a regular application that checks in, runs 2 s and quits */
		[NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular]; [NSApp finishLaunching];
		NSDate *d = [NSDate dateWithTimeIntervalSinceNow:2]; while ([d timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:d];
		return 0;
	}
	ls = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices", RTLD_NOW);
	F(LSASNRef, _LSGetCurrentApplicationASN, void);
	F(CFDictionaryRef, _LSCopyApplicationInformation, LSSessionID, LSASNRef, CFArrayRef);
	F(CFArrayRef, _LSCopyApplicationArrayInFrontToBackOrder, LSSessionID, uint32_t);
	F(LSASNRef, _LSCopyFrontApplication, LSSessionID);
	F(CFDictionaryRef, _LSCopyMetaApplicationInformation, LSSessionID, CFArrayRef);
	F(LSNotificationID, _LSScheduleNotificationOnQueueWithBlock, LSSessionID, dispatch_queue_t, void (^)(LSNotificationCode, CFAbsoluteTime, CFTypeRef, LSASNRef, LSSessionID, LSNotificationID));
	F(OSStatus, _LSModifyNotification, LSNotificationID, uint32_t, LSNotificationCode *, uint32_t, LSNotificationCode *, uint32_t, LSASNRef *);
	[NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; [NSApp finishLaunching];
	LSASNRef me = _LSGetCurrentApplicationASN();
	printf("RESULT asn %s\n", desc(me).UTF8String);
	CFDictionaryRef info = _LSCopyApplicationInformation(-2, me, NULL);
	printf("RESULT info keys %lu pid %s type %s name %s\n", info ? (unsigned long)CFDictionaryGetCount(info) : 0UL,
		desc(info ? CFDictionaryGetValue(info, CFSTR("pid")) : NULL).UTF8String, desc(info ? CFDictionaryGetValue(info, CFSTR("ApplicationType")) : NULL).UTF8String,
		desc(info ? CFDictionaryGetValue(info, CFSTR("LSDisplayName")) : NULL).UTF8String);
	if (getenv("LSC_KEYS")) printf("RESULT keys %s\n", [[[(__bridge NSDictionary *)info allKeys] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","].UTF8String);
	CFArrayRef keys = (__bridge CFArrayRef)@[ @"LSDisplayName", @"pid" ];
	printf("RESULT info restricted %s\n", [desc(_LSCopyApplicationInformation(-2, me, keys)) stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String);
	printf("RESULT front %s\n", desc(_LSCopyFrontApplication(-2)).UTF8String);
	CFArrayRef list = _LSCopyApplicationArrayInFrontToBackOrder(-2, 0);
	printf("RESULT front-to-back count %ld\n", list ? (long)CFArrayGetCount(list) : -1L);
	printf("RESULT meta %s\n", [desc(_LSCopyMetaApplicationInformation(-2, (__bridge CFArrayRef)@[ @"LSSessionID", @"LSFrontApplicationSeed" ])) stringByReplacingOccurrencesOfString:@"\n" withString:@" "].UTF8String);
	printf("RESULT NSRunningApplication current pid %d name %s policy %ld\n", NSRunningApplication.currentApplication.processIdentifier,
		NSRunningApplication.currentApplication.localizedName.UTF8String, (long)NSRunningApplication.currentApplication.activationPolicy);
	__block int seen = 0;
	LSNotificationID nid = _LSScheduleNotificationOnQueueWithBlock(-2, dispatch_get_main_queue(), ^(LSNotificationCode code, CFAbsoluteTime when, CFTypeRef data, LSASNRef asn, LSSessionID session, LSNotificationID n) {
		NSString *d = desc(data);
		printf("NOTIFY code 0x%x asn %s session %d data-keys %lu\n", code, desc(asn).UTF8String, session,
			data && CFGetTypeID(data) == CFDictionaryGetTypeID() ? (unsigned long)CFDictionaryGetCount((CFDictionaryRef)data) : 0UL);
		(void)d; seen++;
	});
	LSNotificationCode codes[] = { 0x101, 0x102, 0x109, 0x10d, 0x110, 0x113, 0x200, 0x201 };
	OSStatus st = _LSModifyNotification(nid, sizeof codes / sizeof codes[0], codes, 0, NULL, 0, NULL);
	printf("RESULT notification id %llu modify %d\n", (unsigned long long)nid, (int)st);
	for (NSString *n in @[ NSWorkspaceWillLaunchApplicationNotification, NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification, NSWorkspaceDidActivateApplicationNotification, NSWorkspaceDidDeactivateApplicationNotification ])
		[NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *note) {
			NSRunningApplication *ra = note.userInfo[NSWorkspaceApplicationKey];
			printf("WORKSPACE %s %s pid %d\n", note.name.UTF8String, ra.localizedName.UTF8String, ra.processIdentifier); seen++;
		}];
	printf("RESULT runningApplications %lu\n", (unsigned long)NSWorkspace.sharedWorkspace.runningApplications.count);
	NSDate *dl = [NSDate dateWithTimeIntervalSinceNow:1]; while ([dl timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:dl];
	pid_t child; char *cargv[] = { argv[0], "child", NULL };
	if (posix_spawn(&child, argv[0], NULL, NULL, cargv, environ) == 0) {
		dl = [NSDate dateWithTimeIntervalSinceNow:6]; while ([dl timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:dl];
		waitpid(child, NULL, WNOHANG);
	}
	printf("RESULT runningApplications %lu\n", (unsigned long)NSWorkspace.sharedWorkspace.runningApplications.count);
	printf("RESULT notifications seen %d\n", seen);
}}
