#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface NSObject(X) -(id)initWithSize:(CGSize)s scale:(double)sc; -(CGImageRef)CGImageForImageDescriptor:(id)d; -(id)initWithBundleURL:(id)u; -(id)initWithType:(id)t; -(void)getCGImageForImageDescriptor:(id)d completion:(void(^)(CGImageRef))c; -(void)prepareImagesForImageDescriptors:(id)d; @end
int main(int argc,char**argv){ @autoreleasepool{
  dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices",RTLD_NOW);
  double sz=argc>3?atof(argv[3]):128;
  id d=[[NSClassFromString(@"ISImageDescriptor") alloc] initWithSize:CGSizeMake(sz,sz) scale:1];
  id ic = argv[1][0]=='/' ? [[NSClassFromString(@"ISBundleIcon") alloc] initWithBundleURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]] : [[NSClassFromString(@"ISTypeIcon") alloc] initWithType:[NSString stringWithUTF8String:argv[1]]];
  dispatch_semaphore_t s=dispatch_semaphore_create(0);
  [ic getCGImageForImageDescriptor:d completion:^(CGImageRef im){ printf("async image=%p %zux%zu\n",im,im?CGImageGetWidth(im):0,im?CGImageGetHeight(im):0); dispatch_semaphore_signal(s);}];
  long r=dispatch_semaphore_wait(s,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC)); printf("wait=%ld\n",r);
}}
