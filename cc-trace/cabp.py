import lldb, time
log = open("/tmp/ca.log", "w")
def cb_add(frame, bp_loc, d):
    log.write("addAnimation %s\n" % " < ".join(f.GetFunctionName() or "?" for f in list(frame.GetThread().frames)[:6])); log.flush(); return False
def cb_spring(frame, bp_loc, d):
    log.write("interpSpring caller: %s\n" % " < ".join(f.GetFunctionName() or "?" for f in list(frame.GetThread().frames)[1:7])); log.flush(); return False
def __lldb_init_module(dbg, d):
    t = dbg.GetSelectedTarget()
    for sym, fn, mod in (("-[CALayer addAnimation:forKey:]", "cabp.cb_add", None), ("$s7SwiftUI9AnimationV19interpolatingSpring4mass9stiffness7damping15initialVelocityACSd_S3dtFZ", "cabp.cb_spring", None)):
        bp = t.BreakpointCreateByName(sym); bp.SetScriptCallbackFunction(fn); log.write("bp %s %d\n" % (sym[:30], bp.GetNumLocations())); log.flush()
def run():
    d = lldb.debugger; d.SetAsync(False); p = d.GetSelectedTarget().GetProcess(); t0 = time.time()
    while time.time() - t0 < 35 and p.GetState() == lldb.eStateStopped: p.Continue()
    p.Detach()
