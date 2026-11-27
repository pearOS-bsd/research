// Test probe: the methods and extended type encodings of WindowManager.framework's XPC protocols.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
extern const char *_protocol_getMethodTypeEncoding(Protocol *, SEL, BOOL, BOOL);
int main(int argc, char **argv) {
  dlopen(argv[1], RTLD_NOW);
  for (int a = 2; a < argc; a++) {
    Protocol *p = objc_getProtocol(argv[a]); if (!p) { printf("no %s\n", argv[a]); continue; }
    printf("@protocol %s\n", argv[a]);
    for (int req = 1; req >= 0; req--) { unsigned n = 0; struct objc_method_description *m = protocol_copyMethodDescriptionList(p, req, YES, &n);
      for (unsigned i = 0; i < n; i++) printf("  %s %s | %s\n", req ? "req" : "opt", sel_getName(m[i].name), _protocol_getMethodTypeEncoding(p, m[i].name, req, YES)); free(m); }
  }
  return 0;
}
