#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface NSObject(X) -(id)initWithSize:(CGSize)s scale:(double)sc; -(CGImageRef)CGImageForImageDescriptor:(id)d; -(id)initWithBundleURL:(id)u; +(id)sharedInstance; @end
int main(){ @autoreleasepool{
  dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices",RTLD_NOW);
  id d=[[NSClassFromString(@"ISImageDescriptor") alloc] initWithSize:CGSizeMake(64,64) scale:2];
  id ic=[[NSClassFromString(@"ISBundleIcon") alloc] initWithBundleURL:[NSURL fileURLWithPath:@"/System/Applications/Calculator.app"]];
  [ic CGImageForImageDescriptor:d];
  id mgr=[NSClassFromString(@"ISIconManager") sharedInstance];
  id cache=[mgr valueForKey:@"iconCache"]; id store=[cache valueForKey:@"store"];
  NSLog(@"cache=%@\nstoreURL=%@\ndomain=%@\ncachePath=%@ sandboxToken=%@",cache,[store valueForKey:@"storeURL"],[store valueForKey:@"domain"],[cache valueForKey:@"cachePath"],[cache valueForKey:@"sandboxToken"]);
  id df=[NSClassFromString(@"ISDefaults") sharedInstance];
  NSLog(@"defaults: cacheURL=%@ metalCacheURL=%@ salt=%@ serviceName=%@ usePersistent=%@ prepareImageDelay=%@",[df valueForKey:@"cacheURL"],[df valueForKey:@"metalCacheURL"],[df valueForKey:@"cacheSaltString"],[df valueForKey:@"serviceName"],[df valueForKey:@"usePerstentCache"],[df valueForKey:@"prepareImageDelay"]);
  NSLog(@"descriptor digest=%@ icon digest=%@",[d valueForKey:@"digest"],[ic valueForKey:@"digest"]);
}}
