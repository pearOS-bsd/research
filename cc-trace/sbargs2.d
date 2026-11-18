#pragma D option quiet
pid$target:SkyLight:SLSTransactionSystemStatusBarRegisterSortedWindow:entry { this->p = (uint64_t*)copyin(arg3, 64); printf("REG wid=%x key=%x a4=%x a5=%x | %x %x %x %x %x %x %x %x\n", arg1, arg2, arg4, arg5, this->p[0],this->p[1],this->p[2],this->p[3],this->p[4],this->p[5],this->p[6],this->p[7]); }
pid$target:SkyLight:SLSCopySystemStatusBarMetrics:entry { self->m = arg4; self->a = arg0; self->b = arg1; self->c = arg2; self->d = arg3; }
pid$target:SkyLight:SLSCopySystemStatusBarMetrics:return /self->m/ { this->q = (uint64_t*)copyin(self->m, 16); printf("METRICS ret=%x args %x %x %x %x out %x %x\n", arg1, self->a, self->b, self->c, self->d, this->q[0], this->q[1]); self->m = 0; }
pid$target:SkyLight:SLSSystemStatusBarGetWindowPreferredPosition:entry { self->pp = arg2; self->w = arg1; }
pid$target:SkyLight:SLSSystemStatusBarGetWindowPreferredPosition:return /self->pp/ { this->r = (uint32_t*)copyin(self->pp, 16); printf("PREFPOS wid=%x ret=%x out %x %x %x %x\n", self->w, arg1, this->r[0], this->r[1], this->r[2], this->r[3]); self->pp = 0; }
pid$target:SkyLight:SLSTransactionSetWindowShadowProperties:entry { this->p = (uint64_t*)copyin(arg2, 32); printf("SHADOW wid=%x a2 %x %x %x %x a3 %x a4 %x a5 %x\n", arg1, this->p[0],this->p[1],this->p[2],this->p[3], arg3, arg4, arg5); }
pid$target:SkyLight:SLSSetWindowTitle:entry { printf("TITLE wid=%x %s\n", arg1, copyinstr(arg2)); }
pid$target:SkyLight:SLSSetWindowProperty:entry { printf("PROP wid=%x %s\n", arg1, copyinstr(arg2)); }
