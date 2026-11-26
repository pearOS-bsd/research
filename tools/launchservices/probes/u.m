// Read units of a csstore file through Apple's _CSStoreGetUnit and print "tableid unitid length crc32(payload)" for each "tableid unitid" line of stdin.
// Build (macOS): clang -fobjc-arc -framework Foundation u.m -o u      Run: ./u FILE < pairs.txt
#include <dlfcn.h>
#include <zlib.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
typedef const void *(*GetUnit)(void *store, unsigned table, unsigned unit, unsigned *len);
int main(int argc,char**argv){ @autoreleasepool{ setvbuf(stdout,0,_IOLBF,0);
  void*h=dlopen("/System/Library/PrivateFrameworks/CoreServicesStore.framework/CoreServicesStore",RTLD_NOW);
  GetUnit gu=(GetUnit)dlsym(h,"CSStoreGetUnit");
  NSError*e=nil; id s=[NSClassFromString(@"_CSStore") alloc];
  s=((id(*)(id,SEL,id,id*))objc_msgSend)(s,NSSelectorFromString(@"initWithContentsOfURL:error:"),[NSURL fileURLWithPath:@(argv[1])],&e);
  if(!s){ printf("open failed %s\n",[[e description] UTF8String]); return 1; }
  unsigned t,u; while(scanf("%u %u",&t,&u)==2){ unsigned len=0; const void*p=gu((__bridge void*)s,t,u,&len); printf("%u %u %u %08lx\n",t,u,p?len:0xffffffffu,p?crc32(0,p,len):0); }
}}
