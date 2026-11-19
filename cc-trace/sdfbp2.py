import lldb
log = open("/tmp/sdf2.log", "w")
def num(name):
    def cb(frame, bp, d):
        err = lldb.SBError(); log.write("%s %.4f\n" % (name, frame.FindRegister("xmm0").GetData().GetDouble(err, 0))); log.flush(); return False
    return cb
def mk_init(name):
    def cb(frame, bp, d):
        log.write("INIT %s\n" % name); log.flush(); return False
    return cb
SETS = {"CASDFGlassDisplacementEffect": ["setHeight:","setCurvature:","setAngle:","setMaskOffset:"], "CASDFGlassHighlightEffect": ["setHeight:","setAngle:","setSpread:","setAmount:","setCurvature:"],
        "CASDFShadowEffect": ["setRadius:"], "CASDFGradientContourEffect": ["setRadius:","setAngle:","setShadowAlpha:"], "CASDFKeyFillHighlightEffect": ["setKeyHeightScale:","setKeySpreadScale:","setFillHeightScale:"], "CASDFOutputEffect": ["setMinimum:","setMaximum:"]}
def __lldb_init_module(dbg, d):
    t = dbg.GetSelectedTarget(); i = 0
    for cls, sels in SETS.items():
        b = t.BreakpointCreateByName("-[%s init]" % cls); globals()["i%d" % i] = mk_init(cls); b.SetScriptCallbackFunction("sdfbp2.i%d" % i); i += 1
        for s in sels:
            b = t.BreakpointCreateByName("-[%s %s]" % (cls, s)); globals()["n%d" % i] = num("%s %s" % (cls, s)); b.SetScriptCallbackFunction("sdfbp2.n%d" % i); i += 1
            log.write("bp %s %s %d\n" % (cls, s, b.GetNumLocations()))
    log.flush()
import time
def run():
    d = lldb.debugger; d.SetAsync(False); p = d.GetSelectedTarget().GetProcess(); t0 = time.time()
    while time.time() - t0 < 50 and p.GetState() == lldb.eStateStopped: p.Continue()
    p.Detach()
