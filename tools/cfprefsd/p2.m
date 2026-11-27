// Observers and NSUserDefaults: shows how change notifications reach a client (run two copies: "watch" and "write").
#import <Foundation/Foundation.h>
@interface W : NSObject @end
@implementation W
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)o change:(NSDictionary *)c context:(void *)x { printf("=== KVO %s -> %s\n", kp.UTF8String, [[c description] UTF8String]); fflush(stdout); }
@end
int main(int argc, char **argv) { @autoreleasepool {
  NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"org.pearos.cfptest2"];
  if (argc > 1 && !strcmp(argv[1], "watch")) {
    W *w = [W new];
    printf("=== STEP watch-start\n"); fflush(stdout);
    [d addObserver:w forKeyPath:@"wk" options:NSKeyValueObservingOptionNew context:0];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *n){ printf("=== DIDCHANGE\n"); fflush(stdout); }];
    printf("=== STEP watching %s\n", [[d objectForKey:@"wk"] description].UTF8String); fflush(stdout);
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:12]];
    printf("=== STEP watch-end %s\n", [[d objectForKey:@"wk"] description].UTF8String);
  } else {
    printf("=== STEP write\n"); fflush(stdout);
    [d setObject:@(time(0)) forKey:@"wk"];
    [d synchronize];
    printf("=== STEP registerDefaults\n"); fflush(stdout);
    [d registerDefaults:@{@"rk": @1}];
    printf("=== STEP removeSuite\n"); fflush(stdout);
    [d removePersistentDomainForName:@"org.pearos.cfptest2"];
    printf("=== STEP end\n");
  }
}}
