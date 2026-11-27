// Exercises the CFPreferences API of the current user; run under xcap.dylib to see what goes to cfprefsd.
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#define S(x) CFSTR(x)
static void step(const char *s){ printf("=== STEP %s\n", s); fflush(stdout); }
int main(int argc, char **argv) {
  CFStringRef app = S("org.pearos.cfptest");
  step("copy-missing");
  CFPropertyListRef v = CFPreferencesCopyAppValue(S("k1"), app); if (v) CFRelease(v);
  step("set");
  int n = 42; CFNumberRef num = CFNumberCreate(0, kCFNumberIntType, &n);
  CFPreferencesSetAppValue(S("k1"), num, app);
  CFPreferencesSetAppValue(S("k2"), S("hello"), app);
  step("sync");
  CFPreferencesAppSynchronize(app);
  step("copy-after");
  v = CFPreferencesCopyAppValue(S("k1"), app); CFShow(v); if (v) CFRelease(v);
  step("keylist");
  CFArrayRef ks = CFPreferencesCopyKeyList(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost); CFShow(ks);
  step("byhost-set");
  CFPreferencesSetValue(S("h1"), S("hostval"), app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
  CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
  step("global-read");
  v = CFPreferencesCopyAppValue(S("AppleLocale"), kCFPreferencesAnyApplication); CFShow(v);
  step("delete");
  CFPreferencesSetAppValue(S("k1"), NULL, app);
  CFPreferencesSetAppValue(S("k2"), NULL, app);
  CFPreferencesSetValue(S("h1"), NULL, app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
  CFPreferencesAppSynchronize(app);
  CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
  step("end");
  return 0;
}
