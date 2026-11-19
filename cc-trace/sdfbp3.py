import lldb
log = open("/tmp/sdf3.log", "w")
def ev(frame, expr):
    v = frame.EvaluateExpression(expr); return (v.GetSummary() or v.GetValue() or "?") if v.IsValid() else "?"
def cb_skv(frame, bp, d):
    log.write("%s setValue:%s forKey:%s\n" % (ev(frame, '(const char *)object_getClassName((id)$rdi)'), ev(frame, '(id)[(id)$rdx description]').replace("\n"," ")[:100], ev(frame, '(id)[(id)$rcx description]'))); log.flush(); return False
def cb_eff(frame, bp, d):
    log.write("SDFLayer.setEffect: %s name=%s\n" % (ev(frame, '(const char *)object_getClassName((id)$rdx)'), ev(frame, '(id)[(id)$rdx name]'))); log.flush(); return False
def cb_layerskv(frame, bp, d):
    k = ev(frame, '(id)[(id)$rcx description]')
    if "effect" in k.lower() or "sdf" in k.lower(): log.write("SDFLayer setValue:%s forKey:%s\n" % (ev(frame, '(id)[(id)$rdx description]').replace("\n"," ")[:160], k)); log.flush()
    return False
def __lldb_init_module(dbg, d):
    t = dbg.GetSelectedTarget()
    for sym, fn in (("-[CASDFEffect setValue:forKey:]", "cb_skv"), ("-[CASDFLayer setEffect:]", "cb_eff"), ("-[CASDFLayer setValue:forKey:]", "cb_layerskv")):
        b = t.BreakpointCreateByName(sym); b.SetScriptCallbackFunction("sdfbp3." + fn); log.write("bp %s %d\n" % (sym, b.GetNumLocations())); log.flush()
import time
def run():
    d = lldb.debugger; d.SetAsync(False); p = d.GetSelectedTarget().GetProcess(); t0 = time.time()
    while time.time() - t0 < 50 and p.GetState() == lldb.eStateStopped: p.Continue()
    p.Detach()
