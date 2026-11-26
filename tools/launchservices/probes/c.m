// First-use client of Launch Services: what a process does when it touches the database. Run under xcap.dylib.
// Build (macOS): clang -fobjc-arc -framework Foundation -framework CoreServices c.m -o lsc
// modes: seq | bundle <bundle-id> | url <path> | regurl <path> | appurls <bundle-id> | reg <path>
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <objc/message.h>
int main(int argc,char**argv){ @autoreleasepool{
  setvbuf(stdout,0,_IOLBF,0);
  dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices",RTLD_NOW);
  const char*mode=argc>1?argv[1]:"seq";
  if(!strcmp(mode,"seq")){ unsigned long long n=0; id u=nil;
    ((void(*)(id,SEL,unsigned long long*,id*))objc_msgSend)(NSClassFromString(@"LSRecord"),NSSelectorFromString(@"_is_getSequenceNumber:andUUID:"),&n,&u);
    printf("RESULT seq=%llu uuid=%s\n",n,[[u description] UTF8String]); }
  else if(!strcmp(mode,"bundle")){ NSError*e=nil; id r=((id(*)(id,SEL,id,BOOL,id*))objc_msgSend)(NSClassFromString(@"LSBundleRecord"),NSSelectorFromString(@"bundleRecordWithBundleIdentifier:allowPlaceholder:error:"),argc>2?@(argv[2]):@"com.apple.finder",NO,&e);
    printf("RESULT %s err=%s\n",[[r description] UTF8String],[[e description] UTF8String]); }
  else if(!strcmp(mode,"url")){ NSURL*u=[NSURL fileURLWithPath:@(argv[2])]; CFStringRef n=NULL; OSStatus st=LSCopyDisplayNameForURL((__bridge CFURLRef)u,&n);
    printf("RESULT LSCopyDisplayNameForURL st=%d name=%s\n",(int)st,n?[(__bridge NSString*)n UTF8String]:"-"); }
  else if(!strcmp(mode,"regurl")){ OSStatus st=LSRegisterURL((__bridge CFURLRef)[NSURL fileURLWithPath:@(argv[2])],true); printf("RESULT LSRegisterURL st=%d\n",(int)st); }
  else if(!strcmp(mode,"appurls")){ CFArrayRef a=LSCopyApplicationURLsForBundleIdentifier((__bridge CFStringRef)@(argv[2]),NULL); printf("RESULT LSCopyApplicationURLsForBundleIdentifier %s\n",[[(__bridge id)a description] UTF8String]); }
  else if(!strcmp(mode,"reg")){ id w=((id(*)(id,SEL))objc_msgSend)(NSClassFromString(@"LSApplicationWorkspace"),@selector(defaultWorkspace)); BOOL ok=((BOOL(*)(id,SEL,id))objc_msgSend)(w,NSSelectorFromString(@"registerApplication:"),[NSURL fileURLWithPath:@(argv[2])]); printf("RESULT registerApplication=%d\n",ok); }
}}
