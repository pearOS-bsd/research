import lldb
log = open("/tmp/glass.log", "w")
def s(frame, reg):
    v = frame.EvaluateExpression('(const char *)[(id)$%s UTF8String]' % reg)
    return v.GetSummary() if v.IsValid() else "?"
def cb_filter(frame, bp, d):
    log.write("filterWithType %s\n" % s(frame, "rdx")); log.flush(); return False
def mk(name):
    def cb(frame, bp, d):
        cls = frame.EvaluateExpression('(const char *)object_getClassName((id)$rdi)').GetSummary()
        log.write("%s on %s < %s\n" % (name, cls, " < ".join((f.GetFunctionName() or "?") for f in list(frame.GetThread().frames)[1:5]))); log.flush(); return False
    return cb
for n in ("setFilters", "setBackgroundFilters", "setCompositingFilter", "backdrop"): globals()["cb_" + n] = mk(n)
def __lldb_init_module(dbg, d):
    t = dbg.GetSelectedTarget()
    for sym, fn in (("+[CAFilter filterWithType:]", "glassbp.cb_filter"), ("-[CALayer setFilters:]", "glassbp.cb_setFilters"), ("-[CALayer setBackgroundFilters:]", "glassbp.cb_setBackgroundFilters"), ("-[CALayer setCompositingFilter:]", "glassbp.cb_setCompositingFilter"), ("-[CABackdropLayer init]", "glassbp.cb_backdrop")):
        b = t.BreakpointCreateByName(sym); b.SetScriptCallbackFunction(fn); log.write("bp %s %d\n" % (sym, b.GetNumLocations())); log.flush()
import time
def run():
    d = lldb.debugger; d.SetAsync(False); p = d.GetSelectedTarget().GetProcess(); t0 = time.time()
    while time.time() - t0 < 40 and p.GetState() == lldb.eStateStopped: p.Continue()
    p.Detach()
