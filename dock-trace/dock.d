#pragma D option quiet
pid$target:libxpc.dylib:bootstrap_look_up*:entry { printf("LOOKUP %s\n", copyinstr(arg1)); }
pid$target:libxpc.dylib:bootstrap_check_in*:entry { printf("CHECKIN %s\n", copyinstr(arg1)); }
pid$target:libxpc.dylib:xpc_connection_create_mach_service:entry { printf("XPCSVC %s\n", copyinstr(arg0)); }
pid$target:CoreFoundation:CFPreferencesCopyAppValue:entry { printf("PREF %s\n", copyinstr(*(uint64_t*)copyin(arg0+0x10,8))); }
syscall::open:entry,syscall::open_nocancel:entry /pid==$target/ { printf("OPEN %s\n", copyinstr(arg0)); }
syscall::openat:entry /pid==$target/ { printf("OPENAT %s\n", copyinstr(arg1)); }
/* SkyLight: the first call of every SLS/CGS function, in order (the window the Dock creates and what it does to it) */
pid$target:SkyLight:SLS*:entry /!seen[probefunc]/ { seen[probefunc] = 1; printf("SLS %s\n", probefunc); }
pid$target:SkyLight:CGS*:entry /!seen[probefunc]/ { seen[probefunc] = 1; printf("SLS %s\n", probefunc); }
