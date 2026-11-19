import lldb
log = open("/tmp/sdf.log", "w")
KEYS = {"CASDFGlassDisplacementEffect": ["height","curvature","angle","maskOffset"], "CASDFGlassHighlightEffect": ["color","height","angle","spread","amount","curvature","global"],
        "CASDFShadowEffect": ["color","radius","offset","punchout","invert"], "CASDFFillEffect": ["color"], "CASDFOutputEffect": ["minimum","maximum"],
        "CASDFKeyFillHighlightEffect": ["keyColor","keyHeightScale","keyHeightOffset","keySpreadScale","keySpreadOffset","fillColor","fillHeightScale","fillHeightOffset","fillSpreadScale","fillSpreadOffset"],
        "CASDFGradientContourEffect": ["startColor","endColor","angle","radius","shadowEffectOffset","shadowGradientStart","shadowGradientEnd","shadowAlpha","gradientOffset"]}
def ev(frame, expr):
    v = frame.EvaluateExpression(expr); return (v.GetSummary() or v.GetValue() or "?") if v.IsValid() else "?"
def dump(frame, obj, depth=0):
    cls = ev(frame, '(const char *)object_getClassName((id)%s)' % obj).strip('"')
    out = [cls]
    for k in KEYS.get(cls, []):
        out.append("%s=%s" % (k, ev(frame, '(id)[(id)%s valueForKey:@"%s"]' % (obj, k)).replace("\n", " ")[:90]))
    return " ".join(out)
def cb_effect(frame, bp, d):
    log.write("SDFLayer.setEffect: %s\n" % dump(frame, "$rdx")); log.flush(); return False
def num(name, reg="xmm0"):
    def cb(frame, bp, d):
        v = frame.FindRegister(reg); data = v.GetData(); err = lldb.SBError()
        log.write("%s %.4f\n" % (name, data.GetDouble(err, 0))); log.flush(); return False
    return cb
cb_smooth = num("SDFLayer.smoothness"); cb_gauss = num("SDFLayer.gaussianRadius")
def cb_mode(frame, bp, d): log.write("Element.setMode: %s\n" % ev(frame, '(const char *)[(id)$rdx UTF8String]')); log.flush(); return False
def cb_op(frame, bp, d): log.write("Element.setOperation: %s\n" % ev(frame, '(const char *)[(id)$rdx UTF8String]')); log.flush(); return False
def cb_merge(frame, bp, d): log.write("SDFLayer.setMergeElements: %d\n" % (frame.FindRegister("rdx").GetValueAsUnsigned() & 0xff)); log.flush(); return False
def cb_filter(frame, bp, d): log.write("filterWithType %s\n" % ev(frame, '(const char *)[(id)$rdx UTF8String]')); log.flush(); return False
def cb_fkey(frame, bp, d): log.write("  CAFilter setValue %s forKey %s\n" % (ev(frame, '(id)[(id)$rdx description]'), ev(frame, '(id)[(id)$rcx description]'))); log.flush(); return False
def cb_groupname(frame, bp, d): log.write("Backdrop.setGroupName %s\n" % ev(frame, '(id)[(id)$rdx description]')); log.flush(); return False
def cb_bscale(frame, bp, d): log.write("Backdrop.setScale %.4f\n" % frame.FindRegister("xmm0").GetData().GetDouble(lldb.SBError(), 0)); log.flush(); return False
def __lldb_init_module(dbg, d):
    t = dbg.GetSelectedTarget()
    for sym, fn in (("-[CASDFLayer setEffect:]", "cb_effect"), ("-[CASDFLayer setSmoothness:]", "cb_smooth"), ("-[CASDFLayer setGaussianRadius:]", "cb_gauss"), ("-[CASDFLayer setMergeElements:]", "cb_merge"),
                    ("-[CASDFElementLayer setMode:]", "cb_mode"), ("-[CASDFElementLayer setOperation:]", "cb_op"), ("+[CAFilter filterWithType:]", "cb_filter"), ("-[CAFilter setValue:forKey:]", "cb_fkey"),
                    ("-[CABackdropLayer setGroupName:]", "cb_groupname"), ("-[CABackdropLayer setScale:]", "cb_bscale")):
        b = t.BreakpointCreateByName(sym); b.SetScriptCallbackFunction("sdfbp." + fn); log.write("bp %s %d\n" % (sym, b.GetNumLocations())); log.flush()
import time
def run():
    d = lldb.debugger; d.SetAsync(False); p = d.GetSelectedTarget().GetProcess(); t0 = time.time()
    while time.time() - t0 < 50 and p.GetState() == lldb.eStateStopped: p.Continue()
    p.Detach()
