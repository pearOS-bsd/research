// Minimal AppKit client: sharedApplication + finishLaunching, to see the plain-XPC conversation with launchservicesd (check-in etc.).
// Build (macOS): clang -fobjc-arc -framework Cocoa a.m -o lsa
#import <Cocoa/Cocoa.h>
int main(int argc,char**argv){ @autoreleasepool{ setvbuf(stdout,0,_IOLBF,0);
  [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; [NSApp finishLaunching];
  printf("RESULT launched\n");
  NSDate*d=[NSDate dateWithTimeIntervalSinceNow:3]; while([d timeIntervalSinceNow]>0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:d];
  printf("RESULT done\n"); }}
