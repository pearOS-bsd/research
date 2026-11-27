// Test probe: which coder keys each WindowManagerXPC* class of WindowManager.framework asks for in initWithCoder: (a recording NSCoder).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
@interface RecCoder : NSCoder @end
@implementation RecCoder
- (BOOL)allowsKeyedCoding { return YES; }
- (BOOL)requiresSecureCoding { return YES; }
- (BOOL)containsValueForKey:(NSString *)k { printf("  contains %s\n", k.UTF8String); return NO; }
- (id)decodeObjectOfClass:(Class)c forKey:(NSString *)k { printf("  object %s of %s\n", k.UTF8String, class_getName(c)); return nil; }
- (id)decodeObjectOfClasses:(NSSet *)s forKey:(NSString *)k { printf("  objects %s of %s\n", k.UTF8String, s.description.UTF8String); return nil; }
- (id)decodeObjectForKey:(NSString *)k { printf("  object %s\n", k.UTF8String); return nil; }
- (int64_t)decodeInt64ForKey:(NSString *)k { printf("  int64 %s\n", k.UTF8String); return 0; }
- (NSInteger)decodeIntegerForKey:(NSString *)k { printf("  integer %s\n", k.UTF8String); return 0; }
- (BOOL)decodeBoolForKey:(NSString *)k { printf("  bool %s\n", k.UTF8String); return NO; }
- (double)decodeDoubleForKey:(NSString *)k { printf("  double %s\n", k.UTF8String); return 0; }
- (int32_t)decodeInt32ForKey:(NSString *)k { printf("  int32 %s\n", k.UTF8String); return 0; }
- (void)failWithError:(NSError *)e { printf("  failWithError %s\n", e.description.UTF8String); }
- (NSError *)error { return nil; }
- (NSDecodingFailurePolicy)decodingFailurePolicy { return NSDecodingFailurePolicySetErrorAndReturn; }
@end
int main(int argc, char **argv) {
  dlopen("/System/Library/PrivateFrameworks/WindowManager.framework/Versions/A/WindowManager", RTLD_NOW);
  unsigned n = 0; const char **names = objc_copyClassNamesForImage("/System/Library/PrivateFrameworks/WindowManager.framework/Versions/A/WindowManager", &n);
  for (unsigned i = 0; i < n; i++) {
    Class c = objc_getClass(names[i]);
    if (!class_respondsToSelector(object_getClass(c), @selector(supportsSecureCoding))) continue;
    printf("%s\n", names[i]);
    @try { id o = [[c alloc] initWithCoder:[RecCoder new]]; printf("  -> %s\n", o ? "object" : "nil"); } @catch (id e) { printf("  exception %s\n", [e description].UTF8String); }
  }
  return 0;
}
