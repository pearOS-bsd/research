// SPDX-License-Identifier: BSD-2-Clause
// Copyright (c) 2026 Alexandru Balan
// Test probe (Mac, and pearOS through the dyld cache): makes the Dock's start-up calls through Apple's frameworks, one service per word:
//   ./dsprobe uninstall dmd ua progress analytics ae named usernoted
// Run with DYLD_INSERT_LIBRARIES=./dcap.dylib to record the wire, IS_REDIRECT=from=to to point it at our servers.
// Our declarations of the few entry points it calls (names from the Dock's imports and the frameworks' exports), not Apple's headers.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <xpc/xpc.h>

static void say(NSString *fmt, ...) { va_list a; va_start(a, fmt); NSString *s = [[NSString alloc] initWithFormat:fmt arguments:a]; va_end(a); printf("PROBE %s\n", s.UTF8String); fflush(stdout); }
static void *fw(const char *path) { void *h = dlopen(path, RTLD_NOW); if (!h) say(@"dlopen %s: %s", path, dlerror()); return h; }
static void wait_s(double s) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

@protocol NDProto
- (void)flushNamedData:(NSString *)n;
- (void)flushNamedData:(NSString *)n withReply:(void (^)(BOOL, NSError *))r;
- (void)getDataItemsWithReply:(void (^)(NSDictionary *, NSError *))r;
- (void)getDataKeysWithReply:(void (^)(NSArray *, NSError *))r;
- (void)getNamedData:(NSString *)n withReply:(void (^)(NSData *, NSError *))r;
- (void)setNamedData:(NSString *)n data:(NSData *)d withReply:(void (^)(BOOL, NSError *))r;
@end
@interface Delegate : NSObject @end
@implementation Delegate
- (BOOL)respondsToSelector:(SEL)s { BOOL r = [super respondsToSelector:s]; if (!r) say(@"delegate asked for %s", sel_getName(s)); return r; }
- (void)bestAppSuggestionChanged:(id)s { say(@"bestAppSuggestionChanged: %@", s); }
- (void)completedUninstallOfBundlePaths:(id)p { say(@"completedUninstallOfBundlePaths: %@", p); }
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    Delegate *del = [Delegate new];
    for (int i = 1; i < argc; i++) {
      NSString *w = @(argv[i]);
      if ([w isEqual:@"uninstall"]) {
        fw("/System/Library/PrivateFrameworks/Uninstall.framework/Uninstall");
        id c = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("UNUninstallClient") alloc], sel_getUid("initWithDelegate:"), del);
        say(@"UNUninstallClient %@", c);
        NSURL *u = [NSURL fileURLWithPath:@"/Applications/Safari.app"];
        long r = ((long (*)(id, SEL, id))objc_msgSend)(c, sel_getUid("uninstallablityOfFileAtURL:"), u);
        say(@"uninstallablityOfFileAtURL Safari = %ld", r);
        if (getenv("PROBE_UNINSTALL_ABORT")) {
          id req = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("UNUninstallClientRequest") alloc], sel_getUid("initWithBundleURL:"), [NSURL fileURLWithPath:@"/tmp/nonexistent-probe.app"]);
          ((void (*)(id, SEL, id))objc_msgSend)(c, sel_getUid("abortRequest:"), req);
          say(@"abortRequest sent");
        }
        if (getenv("PROBE_UNINSTALL_QUEUE") && getenv("IS_REDIRECT")) {      /* only against a test server: a path that does not exist */
          id req = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("UNUninstallClientRequest") alloc], sel_getUid("initWithBundleURL:"), [NSURL fileURLWithPath:@"/tmp/nonexistent-probe.app"]);
          NSError *e = nil;
          BOOL ok = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(c, sel_getUid("queueRequest:error:"), req, &e);
          say(@"queueRequest:error: = %d %@", ok, e);
        }
        wait_s(2);
      } else if ([w isEqual:@"dmd"]) {
        fw("/System/Library/PrivateFrameworks/DeviceManagement.framework/DeviceManagement");
        id m = ((id (*)(id, SEL, id))objc_msgSend)([objc_getClass("DMFApplicationPolicyMonitor") alloc], sel_getUid("initWithPolicyChangeHandler:"), ^(id x) { say(@"policy change %@", x); });
        say(@"DMFApplicationPolicyMonitor %@", m);
        __block int done = 0;
        ((void (*)(id, SEL, id, id))objc_msgSend)(m, sel_getUid("requestPoliciesForBundleIdentifiers:completionHandler:"), @[ @"com.apple.Safari", @"com.apple.finder" ],
          ^(id pol, id err) { say(@"policies %@ error %@", pol, err); done = 1; });
        for (int k = 0; k < 50 && !done; k++) wait_s(0.1);
      } else if ([w isEqual:@"dmd2"]) {        /* what the Dock calls (ECScreenTimeController) */
        fw("/System/Library/PrivateFrameworks/DeviceManagement.framework/DeviceManagement");
        __block int done = 0;
        ((void (*)(id, SEL, id, id))objc_msgSend)(objc_getClass("DMFApplicationPolicyMonitor"), sel_getUid("createPolicyMonitorWithPolicyChangeHandler:completionHandler:"),
          ^(id x) { say(@"policy change %@", x); }, ^(id mon, BOOL enabled, NSError *err) { say(@"createPolicyMonitor: %@ enabled %d error %@", mon, enabled, err); done = 1; });
        for (int k = 0; k < 50 && !done; k++) wait_s(0.1);
      } else if ([w isEqual:@"ua"]) {
        fw("/System/Library/PrivateFrameworks/UserActivity.framework/UserActivity");
        id m = [objc_getClass("UABestAppSuggestionManager") new];
        ((void (*)(id, SEL, id))objc_msgSend)(m, sel_getUid("setDelegate:"), del);
        ((void (*)(id, SEL))objc_msgSend)(m, sel_getUid("startListeningForBestAppSuggestions"));
        say(@"UABestAppSuggestionManager %@ listening", m);
        wait_s(2);
        say(@"bestAppSuggestion %@", ((id (*)(id, SEL))objc_msgSend)(m, sel_getUid("bestAppSuggestion")));
      } else if ([w isEqual:@"progress"]) {
        NSURL *d = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]];
        id sub = [NSProgress addSubscriberForFileURL:d withPublishingHandler:^NSProgressUnpublishingHandler(NSProgress *p) { say(@"progress published %@", p); return ^{ say(@"progress unpublished"); }; }];
        say(@"subscriber %@", sub);
        wait_s(2);
        [NSProgress removeSubscriber:sub];
        wait_s(0.5);
      } else if ([w isEqual:@"publish"]) {
        NSString *f = [NSHomeDirectory() stringByAppendingPathComponent:@"Downloads/probe-download.bin"];
        [[NSData data] writeToFile:f atomically:NO];
        NSProgress *p = [NSProgress progressWithTotalUnitCount:100];
        p.kind = NSProgressKindFile;
        [p setUserInfoObject:NSProgressFileOperationKindDownloading forKey:NSProgressFileOperationKindKey];
        [p setUserInfoObject:[NSURL fileURLWithPath:f] forKey:NSProgressFileURLKey];
        [p publish];
        say(@"published %@", p);
        for (int k = 1; k <= 4; k++) { wait_s(0.5); p.completedUnitCount = k * 25; }
        wait_s(0.5);
        [p unpublish];
        say(@"unpublished");
        wait_s(0.5);
      } else if ([w isEqual:@"subscribe"]) {
        NSURL *d = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Downloads"]];
        id sub = [NSProgress addSubscriberForFileURL:d withPublishingHandler:^NSProgressUnpublishingHandler(NSProgress *p) {
          say(@"progress published %@ fraction %f userInfo %@", p, p.fractionCompleted, p.userInfo);
          return ^{ say(@"progress unpublished"); }; }];
        say(@"subscriber %@", sub);
        wait_s(atof(getenv("PROBE_WAIT") ?: "6"));
        [NSProgress removeSubscriber:sub];
        wait_s(0.5);
      } else if ([w isEqual:@"analytics"]) {
        fw("/System/Library/PrivateFrameworks/CoreAnalytics.framework/CoreAnalytics");
        bool (*used)(const char *) = dlsym(RTLD_DEFAULT, "analytics_is_event_used");
        void (*send)(const char *, xpc_object_t) = dlsym(RTLD_DEFAULT, "analytics_send_event");
        const char *ev = getenv("PROBE_EVENT") ?: "com.apple.dock.launch";
        say(@"analytics_is_event_used(%s) = %d", ev, used ? used(ev) : -1);
        xpc_object_t d = xpc_dictionary_create(NULL, NULL, 0); xpc_dictionary_set_int64(d, "probe", 1);
        if (send) send(ev, d);
        wait_s(1);
      } else if ([w isEqual:@"ae"]) {
        fw("/System/Library/Frameworks/CoreServices.framework/CoreServices");
        void (*aeinit)(void *) = dlsym(RTLD_DEFAULT, "aeInitializeFromHIToolbox");
        uint32_t tbl[0xe0 / 4] = { 1 };                 /* what the Dock passes: a zeroed table, version 1 (Dock 0x10000d672) */
        say(@"aeInitializeFromHIToolbox %p", aeinit);
        if (aeinit) aeinit(tbl);
        int (*inst)(uint32_t, uint32_t, void *, void *, bool) = dlsym(RTLD_DEFAULT, "AEInstallEventHandler");
        say(@"AEInstallEventHandler = %d", inst ? inst('aevt', 'quit', (void *)1, NULL, false) : -1);
        wait_s(2);
      } else if ([w isEqual:@"named"]) {
        fw("/System/Library/Frameworks/CoreServices.framework/CoreServices");
        /* shapes read from CarbonCore's code (DOCK-SERVICES-2.md 6): name, flags 0, ... */
        long (*set)(const char *, int, const void *, unsigned) = dlsym(RTLD_DEFAULT, "_CSSetNamedData");   /* C string name, flags 0, bytes, length */
        CFDataRef (*copy)(CFStringRef, int, void **) = dlsym(RTLD_DEFAULT, "_CSCopyNamedData");
        CFStringRef key = CFSTR("com.pearos.probe");
        NSData *val = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
        long r = set ? set("com.pearos.probe", 0, val.bytes, (unsigned)val.length) : -1;
        say(@"_CSSetNamedData = %ld", r);
        void *err = NULL;
        CFDataRef got = copy ? copy(key, 0, &err) : NULL;
        say(@"_CSCopyNamedData = %@ err %p", (__bridge id)got, err);
        got = copy ? copy(CFSTR("com.pearos.nosuchkey"), 0, &err) : NULL;
        say(@"_CSCopyNamedData(missing) = %@ err %@", (__bridge id)got, err ? (__bridge id)err : nil);
        wait_s(0.5);
      } else if ([w isEqual:@"namedx"]) {      /* the other methods of _CSNamedDataReadWriteProtocol, straight over NSXPC (CarbonCore's own client uses get/set only) */
        fw("/System/Library/Frameworks/CoreServices.framework/CoreServices");
        NSXPCConnection *c = getenv("PROBE_ND") ? [[NSXPCConnection alloc] initWithMachServiceName:@(getenv("PROBE_ND")) options:0] : [[NSXPCConnection alloc] initWithServiceName:@"com.apple.carboncore.csnameddata"];
        c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(NDProto)];
        [c resume];
        id<NDProto> p = [c synchronousRemoteObjectProxyWithErrorHandler:^(NSError *e) { say(@"error %@", e); }];
        [p setNamedData:@"com.pearos.k1" data:[@"v1" dataUsingEncoding:4] withReply:^(BOOL ok, NSError *e) { say(@"set+reply %d %@", ok, e); }];
        [p getDataKeysWithReply:^(NSArray *k, NSError *e) { say(@"keys %@ %@", k, e); }];
        [p getDataItemsWithReply:^(NSDictionary *d, NSError *e) { say(@"items %@ %@", d, e); }];
        [p flushNamedData:@"com.pearos.k1" withReply:^(BOOL ok, NSError *e) { say(@"flush %d %@", ok, e); }];
        [p flushNamedData:@"com.pearos.nosuch" withReply:^(BOOL ok, NSError *e) { say(@"flush missing %d %@", ok, e); }];
        [p getNamedData:@"com.pearos.k1" withReply:^(NSData *d, NSError *e) { say(@"get after flush %@ %@", d, e); }];
        [p setNamedData:@"com.pearos.k2" data:nil withReply:^(BOOL ok, NSError *e) { say(@"set nil %d %@", ok, e); }];
        [c invalidate];
      } else if ([w isEqual:@"usernoted"]) {
        xpc_connection_t c = xpc_connection_create_mach_service(getenv("PROBE_UN") ?: "com.apple.usernoted.dock", dispatch_get_main_queue(), 0);
        xpc_connection_set_event_handler(c, ^(xpc_object_t m) { char *s = xpc_copy_description(m); say(@"usernoted.dock: %s", s); free(s); });
        xpc_connection_resume(c);
        xpc_object_t m = xpc_dictionary_create(NULL, NULL, 0); xpc_dictionary_set_uint64(m, "message_type", 1);
        xpc_connection_send_message(c, m);
        wait_s(3);
      } else say(@"unknown word %@", w);
    }
  }
  return 0;
}
