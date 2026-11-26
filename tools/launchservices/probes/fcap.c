// DYLD_INSERT_LIBRARIES interposer: logs open()/mmap() of csstore files with the caller's backtrace depth-3 (who maps the store).
// Build (macOS): clang -dynamiclib fcap.c -o fcap.dylib
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>
#include <sys/mman.h>
#include <execinfo.h>
static int fdset[64];
static int my_open(const char*p,int fl,...){ va_list a; va_start(a,fl); int m=va_arg(a,int); va_end(a); int fd=open(p,fl,m);
  if(p&&strstr(p,"csstore")){ void*bt[6]; int n=backtrace(bt,6); fprintf(stderr,"FCAP open(%s,%#x)=%d\n",p,fl,fd); backtrace_symbols_fd(bt+1,n-1,2); if(fd>=0&&fd<64) fdset[fd]=1; } return fd; }
static void*my_mmap(void*a,size_t l,int pr,int fl,int fd,off_t o){ void*r=mmap(a,l,pr,fl,fd,o);
  if(fd>=0&&fd<64&&fdset[fd]){ fprintf(stderr,"FCAP mmap(len=%zu prot=%d flags=%#x fd=%d off=%lld)=%p\n",l,pr,fl,fd,(long long)o,r); } return r; }
static int my_close(int fd){ if(fd>=0&&fd<64) fdset[fd]=0; return close(fd); }
#define INTERPOSE(a,b) __attribute__((used)) static struct{const void*n;const void*o;} _ip_##b __attribute__((section("__DATA,__interpose"))) = {(const void*)(unsigned long)&a,(const void*)(unsigned long)&b};
INTERPOSE(my_open,open)
INTERPOSE(my_mmap,mmap)
INTERPOSE(my_close,close)
