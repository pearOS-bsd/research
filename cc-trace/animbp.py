import lldb, struct
log = open("/tmp/anim.log", "w")
def xmm(frame, i):
    r = frame.FindRegister("xmm%d" % i)
    v = r.GetValue()
    try:
        data = r.GetData(); err = lldb.SBError(); return data.GetDouble(err, 0)
    except Exception: return None
def mk(name, n):
    def cb(frame, bp_loc, d):
        vals = [xmm(frame, i) for i in range(n)]
        log.write("%s %s\n" % (name, ["%.4f" % v if v is not None else None for v in vals])); log.flush(); return False
    return cb
def __lldb_init_module(dbg, d):
    tgt = dbg.GetSelectedTarget()
    for name, sym, n in (("spring", "$s7SwiftUI9AnimationV6spring8response15dampingFraction13blendDurationACSd_S2dtFZ", 3), ("interp", "$s7SwiftUI9AnimationV19interpolatingSpring4mass9stiffness7damping15initialVelocityACSd_S3dtFZ", 4),
                         ("easeInOut", "$s7SwiftUI9AnimationV9easeInOut8durationACSd_tFZ", 1), ("easeOut", "$s7SwiftUI9AnimationV7easeOut8durationACSd_tFZ", 1), ("linear", "$s7SwiftUI9AnimationV6linear8durationACSd_tFZ", 1)):
        bp = tgt.BreakpointCreateByName(sym); fn = "abp.cb_" + name
        globals()["cb_" + name] = mk(name, n); bp.SetScriptCallbackFunction(fn)
        log.write("bp %s locations %d\n" % (name, bp.GetNumLocations())); log.flush()
import time
def run():
    d = lldb.debugger; d.SetAsync(False); p = d.GetSelectedTarget().GetProcess(); t0 = time.time()
    while time.time() - t0 < 40 and p.GetState() == lldb.eStateStopped:
        p.Continue()
    p.Detach()
