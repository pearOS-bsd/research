#include <dlfcn.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
@interface LogArch : NSKeyedArchiver @end
@interface NSObject(X) -(id)initWithSize:(CGSize)s scale:(double)sc; -(id)initWithData:(id)d uuid:(id)u validationToken:(id)t; @end
static int depth=0;
@implementation LogArch
-(void)encodeObject:(id)o forKey:(NSString*)k{ printf("%*sobj  key=%s class=%s\n",depth*2,"",k.UTF8String,o?object_getClassName(o):"nil"); depth++; [super encodeObject:o forKey:k]; depth--; }
-(void)encodeConditionalObject:(id)o forKey:(NSString*)k{ printf("%*scond key=%s\n",depth*2,"",k.UTF8String); [super encodeConditionalObject:o forKey:k]; }
-(void)encodeBool:(BOOL)v forKey:(NSString*)k{ printf("%*sbool key=%s val=%d\n",depth*2,"",k.UTF8String,v); [super encodeBool:v forKey:k]; }
-(void)encodeInt:(int)v forKey:(NSString*)k{ printf("%*sint32 key=%s val=%d\n",depth*2,"",k.UTF8String,v); [super encodeInt:v forKey:k]; }
-(void)encodeInt32:(int32_t)v forKey:(NSString*)k{ printf("%*sint32 key=%s val=%d\n",depth*2,"",k.UTF8String,v); [super encodeInt32:v forKey:k]; }
-(void)encodeInt64:(int64_t)v forKey:(NSString*)k{ printf("%*sint64 key=%s val=%lld\n",depth*2,"",k.UTF8String,v); [super encodeInt64:v forKey:k]; }
-(void)encodeInteger:(NSInteger)v forKey:(NSString*)k{ printf("%*sint64 key=%s val=%ld\n",depth*2,"",k.UTF8String,(long)v); [super encodeInteger:v forKey:k]; }
-(void)encodeDouble:(double)v forKey:(NSString*)k{ printf("%*sdouble key=%s val=%g\n",depth*2,"",k.UTF8String,v); [super encodeDouble:v forKey:k]; }
-(void)encodeFloat:(float)v forKey:(NSString*)k{ printf("%*sfloat key=%s val=%g\n",depth*2,"",k.UTF8String,v); [super encodeFloat:v forKey:k]; }
-(void)encodeBytes:(const uint8_t*)b length:(NSUInteger)l forKey:(NSString*)k{ printf("%*sbytes key=%s len=%lu\n",depth*2,"",k.UTF8String,(unsigned long)l); [super encodeBytes:b length:l forKey:k]; }
-(void)encodeXPCObject:(id)o forKey:(NSString*)k{ printf("%*sxpc key=%s\n",depth*2,"",k.UTF8String); }
@end
static void dump(const char*name, id obj){
  printf("---- %s (%s)\n",name,object_getClassName(obj));
  LogArch *a=[[LogArch alloc] initRequiringSecureCoding:YES];
  [a encodeObject:obj forKey:@"root"]; [a finishEncoding];
}
int main(){ @autoreleasepool{
  dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices",RTLD_NOW);
  Class BI=NSClassFromString(@"ISBundleIcon"),TI=NSClassFromString(@"ISTypeIcon"),ID=NSClassFromString(@"ISImageDescriptor"),GR=NSClassFromString(@"ISGenerationRequest"),
  II=NSClassFromString(@"ISIcnsIcon"),BII=NSClassFromString(@"ISBundleIdentifierIcon"),CFG=NSClassFromString(@"ISIconCacheConfiguration"),RS=NSClassFromString(@"ISGenerationResponse");
  id d=[[ID alloc] initWithSize:CGSizeMake(128,128) scale:1];
  id bi=[[BI alloc] performSelector:NSSelectorFromString(@"initWithBundleURL:") withObject:[NSURL fileURLWithPath:@"/System/Applications/Calculator.app"]];
  id ti=[[TI alloc] performSelector:NSSelectorFromString(@"initWithType:") withObject:@"public.folder"];
  id bii=[[BII alloc] performSelector:NSSelectorFromString(@"initWithBundleIdentifier:") withObject:@"com.apple.calculator"];
  id req=[[GR alloc] init]; [req setValue:bi forKey:@"icon"]; [req setValue:d forKey:@"imageDescriptor"];
  dump("ImageDescriptor",d); dump("BundleIcon",bi); dump("TypeIcon",ti); dump("BundleIdentifierIcon",bii); dump("GenerationRequest",req);
  id cfg=[[CFG alloc] init]; [cfg setValue:[NSURL fileURLWithPath:@"/x"] forKey:@"url"]; [cfg setValue:@"ext" forKey:@"sandboxExtension"]; [cfg setValue:@"salt" forKey:@"salt"]; dump("CacheConfiguration",cfg);
  id e=[[RS alloc] performSelector:NSSelectorFromString(@"initWithError:") withObject:[NSError errorWithDomain:@"d" code:1 userInfo:nil]]; dump("Response(error)",e);
  id r=[[RS alloc] initWithData:[NSData dataWithBytes:"abcd" length:4] uuid:[NSUUID UUID] validationToken:[NSData dataWithBytes:"tok" length:3]]; dump("Response(data)",r);
  NSData *ic=[NSData dataWithContentsOfFile:@"/System/Applications/Calculator.app/Contents/Resources/AppIcon.icns"];
  if(ic){ id ii=[[II alloc] performSelector:NSSelectorFromString(@"initWithIcnsData:") withObject:ic]; dump("IcnsIcon",ii); }
}}
