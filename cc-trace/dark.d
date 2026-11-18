#pragma D option quiet
pid$target:SkyLight:SLSSet*:entry { printf("SLS %s %x %x\n", probefunc, arg0, arg1); }
pid$target:SkyLight:SLSTransactionSet*:entry { printf("SLS %s\n", probefunc); }
pid$target:SkyLight:*Appearance*:entry { printf("SLSA %s %x %x\n", probefunc, arg0, arg1); }
pid$target:CoreFoundation:CFPreferencesSet*:entry { printf("CFPREF %s\n", probefunc); }
pid$target:CoreFoundation:_CFPreferences*Set*:entry { printf("CFPREF %s\n", probefunc); }
pid$target:CoreFoundation:CFPreferencesAppSynchronize:entry { printf("CFPREF sync\n"); }
