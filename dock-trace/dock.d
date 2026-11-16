#pragma D option quiet
pid$target:libxpc.dylib:bootstrap_look_up*:entry { printf("LOOKUP %s\n", copyinstr(arg1)); }
pid$target:libxpc.dylib:bootstrap_check_in*:entry { printf("CHECKIN %s\n", copyinstr(arg1)); }
pid$target:libxpc.dylib:xpc_connection_create_mach_service:entry { printf("XPCSVC %s\n", copyinstr(arg0)); }
pid$target:CoreFoundation:CFPreferencesCopyAppValue:entry { printf("PREF %s\n", copyinstr(*(uint64_t*)copyin(arg0+0x10,8))); }
syscall::open:entry,syscall::open_nocancel:entry /pid==$target/ { printf("OPEN %s\n", copyinstr(arg0)); }
syscall::openat:entry /pid==$target/ { printf("OPENAT %s\n", copyinstr(arg1)); }
