// Delay of a deferred write: set a value in an existing domain, then poll the file's inode until it changes.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
int main(int argc,char**argv){
  char p[512]; snprintf(p,512,"%s/Library/Preferences/org.pearos.cfptest3.plist",getenv("HOME"));
  struct stat a,b; stat(p,&a);
  int v=(int)time(0); CFNumberRef n=CFNumberCreate(0,kCFNumberIntType,&v);
  CFPreferencesSetAppValue(CFSTR("t"),n,CFSTR("org.pearos.cfptest3"));
  if(argc>1) CFPreferencesAppSynchronize(CFSTR("org.pearos.cfptest3"));
  double t0=now();
  for(int i=0;i<600;i++){ usleep(100000); if(stat(p,&b)==0&&b.st_ino!=a.st_ino){ printf("rewritten after %.2f s (size %lld)\n",now()-t0,(long long)b.st_size); return 0; } }
  printf("not rewritten in 60 s\n"); return 0;
}
