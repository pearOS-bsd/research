#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
extern const char *_protocol_getMethodTypeEncoding(Protocol*, SEL, BOOL, BOOL);
static void dumpProto(Protocol *p){
  printf("PROTOCOL %s\n", protocol_getName(p));
  for(int req=1;req>=0;req--){
    unsigned n; struct objc_method_description *d = protocol_copyMethodDescriptionList(p,req,YES,&n);
    for(unsigned i=0;i<n;i++) printf("  %s %s  type=%s  ext=%s\n", req?"req":"opt", sel_getName(d[i].name), d[i].types, _protocol_getMethodTypeEncoding(p,d[i].name,req,YES));
  }
}
static void dumpIface(NSXPCInterface *x){
  Protocol *p = x.protocol; dumpProto(p);
  unsigned n; struct objc_method_description *d = protocol_copyMethodDescriptionList(p,YES,YES,&n);
  for(unsigned i=0;i<n;i++){
    NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:d[i].types];
    for(NSUInteger a=2;a<s.numberOfArguments;a++){
      if(strstr([s getArgumentTypeAtIndex:a],"@?")) continue; NSSet *c=[x classesForSelector:d[i].name argumentIndex:a-2 ofReply:NO];
      printf("  CLASSES %s arg%lu: %s\n", sel_getName(d[i].name),(unsigned long)a-2,[[c description] UTF8String]);
    }
    for(NSUInteger a=0;a<8;a++){
      NSSet *c=nil; @try{c=[x classesForSelector:d[i].name argumentIndex:a ofReply:YES];}@catch(id e){break;}
      if(c.count) printf("  CLASSES %s reply%lu: %s\n", sel_getName(d[i].name),(unsigned long)a,[[c description] UTF8String]);
    }
  }
}
int main(){ @autoreleasepool{
  dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices",RTLD_NOW);
  Class c=NSClassFromString(@"NSXPCInterface");
  id x=[c performSelector:NSSelectorFromString(@"_IS_iconCacheServiceInterface")];
  dumpIface(x);
  Protocol *sp=NSProtocolFromString(@"ISStoreServiceProtocol");
  dumpProto(sp);
  NSXPCInterface *si=[NSXPCInterface interfaceWithProtocol:sp]; dumpIface(si);
  unsigned n; Protocol * __unsafe_unretained *pl=objc_copyProtocolList(&n);
  for(unsigned i=0;i<n;i++){ const char*nm=protocol_getName(pl[i]); if(strncmp(nm,"IS",2)==0||strstr(nm,"IconServ")) printf("proto %s\n",nm);}
}}
