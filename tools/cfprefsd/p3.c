// Disk behaviour: when and how a write reaches ~/Library/Preferences (no synchronize, then synchronize), and what removal of the last key does.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>
static const char *path(void){ static char p[512]; snprintf(p,512,"%s/Library/Preferences/org.pearos.cfptest3.plist",getenv("HOME")); return p; }
static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void show(const char *tag, double t0){ struct stat st; if(stat(path(),&st)==0) printf("%-10s t=%.3f size=%lld mode=%o uid=%d ino=%llu\n",tag,now()-t0,(long long)st.st_size,st.st_mode&07777,st.st_uid,(unsigned long long)st.st_ino); else printf("%-10s t=%.3f absent\n",tag,now()-t0); fflush(stdout); }
int main(void){
  CFStringRef app=CFSTR("org.pearos.cfptest3"); double t0=now();
  show("start",t0);
  CFPreferencesSetAppValue(CFSTR("a"),CFSTR("x"),app); show("set",t0);
  for(int i=0;i<30;i++){ usleep(100000); struct stat st; if(stat(path(),&st)==0){ show("appeared",t0); break; } }
  CFPreferencesSetAppValue(CFSTR("b"),CFSTR("y"),app); CFPreferencesAppSynchronize(app); show("sync",t0);
  CFPreferencesSetAppValue(CFSTR("a"),NULL,app); CFPreferencesSetAppValue(CFSTR("b"),NULL,app); CFPreferencesAppSynchronize(app); show("empty",t0);
  usleep(500000); show("empty+0.5",t0);
  return 0;
}
