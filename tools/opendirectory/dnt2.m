/* SPDX-License-Identifier: BSD-2-Clause
 * Copyright (c) 2026 Alexandru Balan
 * Probe of NSDistributedNotificationCenter (macOS test helper): observes NAME (with a selector), posts it with an object and a userInfo,
 * then suspends and unsuspends the center.  Build: clang -fobjc-arc dnt2.m -o dnt2 -framework Foundation */
#import <Foundation/Foundation.h>
@interface O : NSObject @end
@implementation O
- (void)got:(NSNotification *)n { printf("GOT %s object=%s userInfo=%s\n", n.name.UTF8String, [[n.object description] UTF8String], [[n.userInfo description] UTF8String]); fflush(stdout); }
@end
int main(int argc, char **argv) {
	@autoreleasepool {
		NSDistributedNotificationCenter *c = [NSDistributedNotificationCenter defaultCenter];
		NSString *nm = argc > 1 ? @(argv[1]) : @"com.pearos.t2";
		O *o = [O new];
		[c addObserver:o selector:@selector(got:) name:nm object:@"objA"];
		[c addObserver:o selector:@selector(got:) name:nil object:nil];
		[c postNotificationName:nm object:@"objA" userInfo:@{ @"n": @42, @"d": [NSData dataWithBytes:"ab" length:2] } deliverImmediately:YES];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
		c.suspended = YES;
		[c postNotificationName:nm object:@"objA" userInfo:nil options:NSNotificationPostToAllSessions];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
		c.suspended = NO;
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
		[c removeObserver:o];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
	}
	return 0;
}
