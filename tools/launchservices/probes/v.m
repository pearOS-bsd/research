// Open a csstore file with Apple's CoreServicesStore (container-level acceptance test of a store we wrote) and print its usage breakdown.
// Build (macOS): clang -fobjc-arc -framework Foundation v.m -o v      Run: ./v FILE
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
int main(int argc,char**argv){ @autoreleasepool{ setvbuf(stdout,0,_IOLBF,0);
  dlopen("/System/Library/PrivateFrameworks/CoreServicesStore.framework/CoreServicesStore",RTLD_NOW);
  NSError*e=nil; id s=[NSClassFromString(@"_CSStore") alloc];
  s=((id(*)(id,SEL,id,id*))objc_msgSend)(s,NSSelectorFromString(@"initWithContentsOfURL:error:"),[NSURL fileURLWithPath:@(argv[1])],&e);
  printf("store=%s err=%s\n",[[s description] UTF8String],[[e description] UTF8String]);
  if(!s) return 1;
  id v=((id(*)(id,SEL))objc_msgSend)(NSClassFromString(@"_CSVisualizer"),@selector(alloc));
  v=((id(*)(id,SEL,id,BOOL))objc_msgSend)(v,NSSelectorFromString(@"initWithStore:useStandardTableFunctions:"),s,YES);
  id u=((id(*)(id,SEL))objc_msgSend)(v,NSSelectorFromString(@"breakDownUsage")); printf("%s\n",[[u description] UTF8String]);
}}
