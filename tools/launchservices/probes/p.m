// Dump every _LSDService subclass: connection type, protocol, methods (extended type encodings) and the allowed classes
// of each argument/reply as set by +XPCInterface (setClasses:forSelector:). Build on macOS: clang -fobjc-arc -framework Foundation p.m -o p
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
extern const char *_protocol_getMethodTypeEncoding(Protocol*, SEL, BOOL, BOOL);
static void dumpIface(NSXPCInterface *x){
  Protocol *p = x.protocol; printf("  PROTOCOL %s\n", protocol_getName(p));
  unsigned np; Protocol * __unsafe_unretained *adopted = protocol_copyProtocolList(p,&np);
  for(unsigned i=0;i<np;i++) printf("  ADOPTS %s\n", protocol_getName(adopted[i]));
  for(int req=1;req>=0;req--){
    unsigned n; struct objc_method_description *d = protocol_copyMethodDescriptionList(p,req,YES,&n);
    for(unsigned i=0;i<n;i++){
      SEL s=d[i].name;
      printf("  %s %s\n    type=%s\n    ext=%s\n", req?"req":"opt", sel_getName(s), d[i].types, _protocol_getMethodTypeEncoding(p,s,req,YES));
      NSMethodSignature *sig=[NSMethodSignature signatureWithObjCTypes:d[i].types];
      for(NSUInteger a=2;a<sig.numberOfArguments;a++){ const char *t=[sig getArgumentTypeAtIndex:a];
        if(t[0]!='@') continue;
        NSSet *c=[x classesForSelector:s argumentIndex:a-2 ofReply:NO];
        if(strncmp(t,"@?",2)==0){
          // reply block args
          for(NSUInteger r=0;r<8;r++){ id rc=nil; @try{rc=[x classesForSelector:s argumentIndex:r ofReply:YES];}@catch(id e){break;}
            if([rc isKindOfClass:[NSXPCInterface class]]){ printf("    reply%lu proxy interface: %s\n",(unsigned long)r,protocol_getName([(NSXPCInterface*)rc protocol])); continue; }
            if([rc count]){ NSMutableArray *nm=[NSMutableArray array]; for(Class k in rc)[nm addObject:NSStringFromClass(k)]; [nm sortUsingSelector:@selector(compare:)]; printf("    reply%lu classes: %s\n",(unsigned long)r,[[nm componentsJoinedByString:@", "] UTF8String]); } }
          continue; }
        NSMutableArray *nm=[NSMutableArray array]; for(Class k in c)[nm addObject:NSStringFromClass(k)]; [nm sortUsingSelector:@selector(compare:)];
        printf("    arg%lu classes: %s\n",(unsigned long)a-2,[[nm componentsJoinedByString:@", "] UTF8String]);
      }
    }
  }
}
int main(){ setvbuf(stdout,0,_IOLBF,0); @autoreleasepool{
  dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",RTLD_NOW);
  Class base=NSClassFromString(@"_LSDService");
  unsigned n; Class *all=objc_copyClassList(&n);
  for(unsigned i=0;i<n;i++){ Class c=all[i]; if(c==base) continue; Class s=class_getSuperclass(c); BOOL sub=NO; while(s){ if(s==base){sub=YES;break;} s=class_getSuperclass(s);} if(!sub) continue;
    printf("SERVICE %s\n",class_getName(c));
    printf("  connectionType=%d isEnabled=%d alwaysPrivileged=%d clientClass=%s\n",(int)(unsigned short)((unsigned short(*)(id,SEL))objc_msgSend)(c,@selector(connectionType)),
      (c && [c respondsToSelector:@selector(isEnabled)])? (int)((signed char(*)(id,SEL))objc_msgSend)(c,@selector(isEnabled)):-1,
      (int)((signed char(*)(id,SEL))objc_msgSend)(c,@selector(XPCConnectionIsAlwaysPrivileged)),
      class_getName((Class)((id(*)(id,SEL))objc_msgSend)(c,@selector(clientClass))));
    @try{ NSXPCConnection *cn=((id(*)(id,SEL))objc_msgSend)(c,@selector(XPCConnectionToService)); printf("  serviceName=%s\n",[[cn serviceName] UTF8String]); }@catch(id e){ printf("  serviceName=? (%s)\n",[[e description] UTF8String]); }
    id x=((id(*)(id,SEL))objc_msgSend)(c,@selector(XPCInterface)); if(x) dumpIface(x); else printf("  no interface\n");
  }
  // protocols whose services are not _LSDService subclasses: plain interfaceWithProtocol (classes inferred from extended types)
  const char *extra[]={"_LSDDisseminationServerProtocol","_LSDDisseminationClientProtocol","LSDPluginProtocol","LSDPluginServiceProtocol","LSDatabaseBlockingFetchProtocol","_LSServerSettingsStoreXPCProtocol","LSCodeEvaluationServerProtocol","LSCodeEvaluationClientProtocol","LSInstallProgressProtocol",0};
  for(int i=0;extra[i];i++){ Protocol *p=NSProtocolFromString([NSString stringWithUTF8String:extra[i]]); if(!p){printf("NOPROTO %s\n",extra[i]);continue;} printf("EXTRA %s\n",extra[i]); dumpIface([NSXPCInterface interfaceWithProtocol:p]); }
}}
