// Calls every parameterless/simple method of _LSDReadProtocol on com.apple.lsd.mapdb and prints the reply objects.  Run under xcap.dylib to capture the wire.
// Build (macOS): clang -fobjc-arc -framework Foundation rd.m -o rd
#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
@protocol RP
- (void)getServerStatusWithCompletionHandler:(void(^)(unsigned))h;
- (void)getSystemModeWithCompletionHandler:(void(^)(id,id))h;
- (void)getPreferencesWithCompletionHandler:(void(^)(id,id))h;
- (void)getSettingsStoreConfigurationWithCompletionHandler:(void(^)(id,id))h;
- (void)getSelectedDeveloperDirectoryURLWithCompletionHandler:(void(^)(id))h;
- (void)getKernelPackageExtensionsWithCompletionHandler:(void(^)(id,id))h;
- (void)getApplicationCategoryIdentifiersSetWithCompletionHandler:(void(^)(id,id))h;
- (void)getSessionLanguagesForImproperlyLocalizedProcessWithCompletionHandler:(void(^)(id,id))h;
- (void)getSystemContentStoreWithCompletionHandler:(void(^)(id,id,id))h;
- (void)getEligibilityAnswerForDomain:(unsigned long long)d withCompletionHandler:(void(^)(id,id))h;
- (void)mapBundleIdentifiers:(id)a orMachOUUIDs:(id)b completionHandler:(void(^)(id,id,id))h;
- (void)mapPlugInBundleIdentifiersToContainingBundleIdentifiers:(id)a completionHandler:(void(^)(id,id))h;
@end
int main(int argc,char**argv){ @autoreleasepool{ setvbuf(stdout,0,_IOLBF,0);
  dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",RTLD_NOW);
  Class svc=NSClassFromString(@"_LSDReadService"); NSXPCInterface*ifc=[svc performSelector:@selector(XPCInterface)];
  NSXPCConnection*c=[[NSXPCConnection alloc] initWithMachServiceName:@"com.apple.lsd.mapdb" options:0]; c.remoteObjectInterface=ifc; [c resume];
  id<RP> p=[c synchronousRemoteObjectProxyWithErrorHandler:^(NSError*e){ printf("ERROR %s\n",[[e description] UTF8String]); }];
  printf("CALL getServerStatus\n"); [p getServerStatusWithCompletionHandler:^(unsigned s){ printf("  -> status=%u\n",s); }];
  printf("CALL getSystemMode\n"); [p getSystemModeWithCompletionHandler:^(id a,id b){ printf("  -> %s | %s\n",[[a description] UTF8String],[[b description] UTF8String]); }];
  printf("CALL getPreferences\n"); [p getPreferencesWithCompletionHandler:^(id a,id b){ printf("  -> %s | %s\n",[[a description] UTF8String],[[b description] UTF8String]); }];
  printf("CALL getSettingsStoreConfiguration\n"); [p getSettingsStoreConfigurationWithCompletionHandler:^(id a,id b){ printf("  -> %s | %s\n",[[a description] UTF8String],[[b description] UTF8String]); }];
  printf("CALL getSelectedDeveloperDirectoryURL\n"); [p getSelectedDeveloperDirectoryURLWithCompletionHandler:^(id a){ printf("  -> %s\n",[[a description] UTF8String]); }];
  printf("CALL getKernelPackageExtensions\n"); [p getKernelPackageExtensionsWithCompletionHandler:^(id a,id b){ printf("  -> %lu items | %s\n",(unsigned long)[a count],[[b description] UTF8String]); }];
  printf("CALL getApplicationCategoryIdentifiersSet\n"); [p getApplicationCategoryIdentifiersSetWithCompletionHandler:^(id a,id b){ printf("  -> %lu items | %s\n",(unsigned long)[a count],[[b description] UTF8String]); }];
  printf("CALL getSessionLanguagesForImproperlyLocalizedProcess\n"); [p getSessionLanguagesForImproperlyLocalizedProcessWithCompletionHandler:^(id a,id b){ printf("  -> %s | %s\n",[[a description] UTF8String],[[b description] UTF8String]); }];
  printf("CALL getSystemContentStore\n"); [p getSystemContentStoreWithCompletionHandler:^(id a,id b,id e){ printf("  -> %s | %s | %s\n",[[a description] UTF8String],[[b description] UTF8String],[[e description] UTF8String]); }];
  printf("CALL getEligibilityAnswerForDomain:0\n"); [p getEligibilityAnswerForDomain:0 withCompletionHandler:^(id a,id b){ printf("  -> %s | %s\n",[[a description] UTF8String],[[b description] UTF8String]); }];
  printf("CALL mapBundleIdentifiers\n"); [p mapBundleIdentifiers:[NSSet setWithObject:@"com.apple.finder"] orMachOUUIDs:[NSSet set] completionHandler:^(id a,id b,id e){ printf("  -> %s | %s | %s\n",[[a description] UTF8String],[[b description] UTF8String],[[e description] UTF8String]); }];
  printf("CALL mapPlugInBundleIdentifiers\n"); [p mapPlugInBundleIdentifiersToContainingBundleIdentifiers:[NSSet setWithObject:@"com.apple.finder.Sync"] completionHandler:^(id a,id b){ printf("  -> %s | %s\n",[[a description] UTF8String],[[b description] UTF8String]); }];
  printf("DONE\n");
}}
