// The daemon side: kCFPreferencesAnyUser (/Library/Preferences) written as root and read as a user; root's own domain.
// p5 write (as root) | p5 read (as a user) | p5 clean (as root)
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
static void step(const char *s){ printf("=== STEP %s\n", s); fflush(stdout); }
static void st(const char *p){ struct stat s; if(stat(p,&s)==0) printf("=== FILE %s size=%lld mode=%o uid=%d\n",p,(long long)s.st_size,s.st_mode&07777,s.st_uid); else printf("=== FILE %s absent\n",p); fflush(stdout); }
int main(int argc,char**argv){
  CFStringRef app=CFSTR("org.pearos.cfptest5");
  if(argc>1&&!strcmp(argv[1],"write")){
    step("anyuser-write");
    CFPreferencesSetValue(CFSTR("sys"),CFSTR("v1"),app,kCFPreferencesAnyUser,kCFPreferencesAnyHost);
    CFPreferencesSynchronize(app,kCFPreferencesAnyUser,kCFPreferencesAnyHost);
    st("/Library/Preferences/org.pearos.cfptest5.plist");
    step("root-own-write");
    CFPreferencesSetAppValue(CFSTR("r"),CFSTR("rootval"),app); CFPreferencesAppSynchronize(app);
    st("/var/root/Library/Preferences/org.pearos.cfptest5.plist");
  } else if(argc>1&&!strcmp(argv[1],"read")){
    step("user-read-anyuser");
    CFPropertyListRef v=CFPreferencesCopyAppValue(CFSTR("sys"),app); CFShow(v);
    step("user-write-anyuser");
    CFPreferencesSetValue(CFSTR("sys"),CFSTR("v2"),app,kCFPreferencesAnyUser,kCFPreferencesAnyHost);
    printf("sync=%d\n",CFPreferencesSynchronize(app,kCFPreferencesAnyUser,kCFPreferencesAnyHost));
    v=CFPreferencesCopyValue(CFSTR("sys"),app,kCFPreferencesAnyUser,kCFPreferencesAnyHost); CFShow(v);
  } else {
    step("clean");
    CFPreferencesSetValue(CFSTR("sys"),NULL,app,kCFPreferencesAnyUser,kCFPreferencesAnyHost);
    CFPreferencesSetAppValue(CFSTR("r"),NULL,app);
    CFPreferencesSynchronize(app,kCFPreferencesAnyUser,kCFPreferencesAnyHost); CFPreferencesAppSynchronize(app);
  }
  return 0;
}
