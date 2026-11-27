// Test probe (Mac): the methods and extended type encodings of the Objective-C protocols whose name contains a pattern.
//   ./protos IMAGE[,IMAGE...] PATTERN...
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
extern const char *_protocol_getMethodTypeEncoding(Protocol *, SEL, BOOL, BOOL);
int main(int argc, char **argv) {
  char *imgs = strdup(argv[1]);
  for (char *s = NULL, *p = strtok_r(imgs, ",", &s); p; p = strtok_r(NULL, ",", &s)) if (!dlopen(p, RTLD_NOW)) printf("dlopen %s: %s\n", p, dlerror());
  unsigned np = 0; Protocol * __unsafe_unretained *all = objc_copyProtocolList(&np);
  for (unsigned k = 0; k < np; k++) {
    const char *name = protocol_getName(all[k]); int hit = 0;
    for (int a = 2; a < argc; a++) if (strstr(name, argv[a])) hit = 1;
    if (!hit) continue;
    printf("@protocol %s\n", name);
    for (int req = 1; req >= 0; req--) { unsigned n = 0; struct objc_method_description *m = protocol_copyMethodDescriptionList(all[k], req, YES, &n);
      for (unsigned i = 0; i < n; i++) printf("  %s %s | %s\n", req ? "req" : "opt", sel_getName(m[i].name), _protocol_getMethodTypeEncoding(all[k], m[i].name, req, YES)); free(m); }
  }
  return 0;
}
