// G2E.x : smooth start of the home-swipe close (DELIBERATE, switchable deviation from stock 16.0 and 16.2).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Switch: g2e_closesmooth (default ON, kill switch file Backport162.off.g2e_closesmooth).
// Setup: G2E_Setup(). Log lines (Backport162.debug): "[g2e] ...". Spec: specs/CLOSE-SMOOTH-0.7.5.md.
//
// Symptom (user videos 0dee8146 / af7310bc, logs fed63049 / 4e9ad132): the window stays at full size while the finger travels, then shrinks by ~6-12 % of its width in ONE 60 fps frame
// (area per frame 93.9k, 92.9k, 91.4k, 80.4k, 71.1k, 62.8k, 52.2k, 41.7k ... px), the shrink speed dips for three frames and rises again after the hand-off to the transition.
//
// Mechanism (read from the binaries; 16.0 and 16.2 are byte-identical in every piece below up to register numbers / ivar offsets, so this is STOCK behaviour, not a port defect):
//  * Two animation systems run in sequence on the SAME item container, selected by the update mode of the layout attributes
//    (+[UIView(SBFFluidBehaviorSettings) sb_animateWithSettings:mode:animations:completion:] 16.0 0x18eb3aab4 / 16.2 0x18edd9a58: 1 none, 2 no retarget, 3 animated spring, 4 retarget, 5 interactive tracking):
//    (1) interactive phase: -[SBGestureSwitcherModifier animationAttributesForLayoutElement:] (16.0 0x1c63807a4, 16.2 0x1c7828718) sets updateMode 5 = tracking spring, whose
//        parameters (trackingResponse / trackingDampingRatio) come from -[SBHomeGestureSwitcherModifier animationAttributesForLayoutElement:] 0x1c603af08 (16.2 0x1c74b64fc) ->
//        -[SBHomeGestureSwitcherModifier _layoutSettingsForAppLayout:layoutSettings:] 0x1c603b068 (16.2 0x1c74b665c):
//          card == _selectedAppLayout and starting mode 2 with stackedProgress > 0  -> stackedSwitcherTrackingSettings
//          card == _selectedAppLayout otherwise                                      -> the passed default layoutSettings, i.e. -[SBFFluidBehaviorSettings setDefaultValues] 0x18eb3b248:
//                                                                                       trackingResponse 0.15, trackingDampingRatio 0.86 (a real tracking spring)
//          any other card (and the selected one when no fly-in property exists)     -> a FRESH SBFFluidBehaviorSettings with trackingResponse = 0 (0x1c603b1fc): the layer is set straight to
//                                                                                       every model value (no spring, so it has NO velocity).
//    (2) transition: 3->1 is SBHomeGestureToZoomDownSwitcherModifier (16.0 0x1c646fbd0 / 16.2 0x1c7925388) = SBFullScreenToHomeIconZoomSwitcherModifier + the attribute modifier
//        SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier (16.0 0x1c63f92c0 / 16.2 0x1c78a5d70), update mode 3: a real spring (iPad rows: layout z 1.1 r 0.375-0.425, position z 0.86-0.88
//        r 0.45-0.50, scale z 0.90-0.96 r 0.40-0.50) that retargets from the PRESENTATION value of the layer with the layer's velocity (UIKit fluid behaviour).
//    The 16.2 VC consumer (-[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] block 16.0 0x1c5fca514 / 16.2 0x1c744326c) has the same selector sequence apart from
//    unrelated 16.2 additions (clipping, group opacity, accessory scale): nothing in the hand-off differs.
//  * Consequence in the videos: with trackingResponse 0 the layer copies the model exactly (model 0.9933 -> 0.9085 in one 22 ms update = the finger moved ~30 pt while the main thread
//    prepared the gesture), i.e. it jumps in one frame, and when the transition starts the layer has no spring velocity, so the zoom-down spring restarts from rest (the dip, then the rise).
//
// Fix (default ON): in the instant branch only (fresh settings object, trackingResponse == 0, gesture still running, starting environment mode 3) the tracking spring becomes the
// one the SAME function already uses for the selected card (live values of the passed default layoutSettings: trackingResponse 0.15, trackingDampingRatio 0.86).  The window then
// follows the finger through a spring, a single large update is spread over several frames, and the layer carries a real velocity into the zoom-down (UIKit retargets with it).
// Everything else (transition springs, targets, timing, the other branches, mode 1 / mode 2 starts) stays stock.
//
// Computed with the logged sample series (spring integrated at 0.1 ms; layer = tracking spring following the model, then the zoom-down scale spring z 0.93 r 0.45 toward 0.1176 with
// velocity continuity; worst case over the video frame phase), see the "[g2e] expected" line which re-computes it at start-up:
//    flick of log fed63049 (0.9933 0.9085 0.8538 0.8291 0.8073, hand-off 62 ms after the first sample):  trackingResponse 0    -> worst frame ratio 0.860, max change of the ratio between frames 0.140
//                                                                                                    trackingResponse 0.15 -> worst frame ratio 0.880, max change 0.026
//    flick of log 4e9ad132 (0.9895 0.8171, hand-off 18 ms later):                                      trackingResponse 0    -> 0.826 / 0.174
//                                                                                                    trackingResponse 0.15 -> 0.879 / 0.037

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2E_ON() BP_OnName("g2e_closesmooth")
#define G2E_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static IMP gG2EOrigLayout;
static char kG2ELogged;

static BOOL G2E_Scalar(id o, const char *name, void *out, size_t size) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) return NO;
    memcpy(out, (const char *)(__bridge void *)o + ivar_getOffset(iv), size);
    return YES;
}
static double G2E_Dbl(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(o, s) : 0.0;
}

// -[SBHomeGestureSwitcherModifier _layoutSettingsForAppLayout:layoutSettings:]  16.0 0x1c603b068, 16.2 0x1c74b665c
static id G2E_LayoutSettings(id self, SEL _cmd, id appLayout, id settings) {
    id r = ((id (*)(id, SEL, id, id))gG2EOrigLayout)(self, _cmd, appLayout, settings);
    if (!G2E_ON() || !r || r == settings) return r;                                 // not the fresh instant-tracking object
    @try {
        long long mode = 0; BOOL ended = NO;
        if (!G2E_Scalar(self, "_startingEnvironmentMode", &mode, sizeof mode) || mode != 3) return r;
        if (G2E_Scalar(self, "_gestureHasEnded", &ended, sizeof ended) && ended) return r;
        if (![r respondsToSelector:@selector(setTrackingResponse:)] || ![r respondsToSelector:@selector(setTrackingDampingRatio:)]) return r;
        if (fabs(G2E_Dbl(r, "trackingResponse")) > 1e-9) return r;                  // a stock spring already
        double resp = G2E_Dbl(settings, "trackingResponse"), damp = G2E_Dbl(settings, "trackingDampingRatio");
        if (resp <= 1e-9) return r;                                                 // no stock tracking spring to borrow
        if (damp <= 1e-9) damp = 0.86;
        ((void (*)(id, SEL, double))objc_msgSend)(r, @selector(setTrackingResponse:), resp);
        ((void (*)(id, SEL, double))objc_msgSend)(r, @selector(setTrackingDampingRatio:), damp);
        if (BP_LogEnabled() && !objc_getAssociatedObject(self, &kG2ELogged)) {
            objc_setAssociatedObject(self, &kG2ELogged, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            BP_Log(@"[g2e] home gesture (mode 3 start): card %p got instant tracking (response 0) -> tracking spring response %.3f damping %.2f (the selected-card spring of the same method)", appLayout, resp, damp);
        }
    } @catch (NSException *e) {
        G2E_LOG(@"[g2e] exception %@", e);
    }
    return r;
}

// ---- start-up numbers: the logged sample series through "tracking spring (response R) -> zoom-down scale spring with velocity continuity" ----
static void G2E_Step(double *x, double *v, double tgt, double z, double r, double dt) {
    double w = 2.0 * M_PI / r, a = -w * w * (*x - tgt) - 2.0 * z * w * *v;
    *v += a * dt; *x += *v * dt;
}
static void G2E_Series(const double *ts, const double *tg, int n, double handoff, double R, double *worst, double *jerk) {
    enum { N = 3500 };
    static double out[N];
    double x = 1.0, v = 0.0, dt = 0.0001, tgt = 1.0;
    for (int i = 0; i < N; i++) {
        double t = i * dt;
        for (int k = 0; k < n; k++) if (t >= ts[k]) tgt = tg[k];
        if (t >= handoff) G2E_Step(&x, &v, 0.1176, 0.93, 0.45, dt);
        else if (R <= 0) { x = tgt; v = 0; }
        else G2E_Step(&x, &v, tgt, 0.86, R, dt);
        out[i] = x;
    }
    *worst = 9; *jerk = 0;
    for (int ph = 0; ph <= 16; ph += 2) {
        double prevRatio = 0; BOOL have = NO;
        for (int k = 0; k < 13; k++) {
            int i0 = (int)((ph * 0.001 + k / 60.0) / dt), i1 = (int)((ph * 0.001 + (k + 1) / 60.0) / dt);
            if (i1 >= N) break;
            double ratio = out[i1] / out[i0];
            if (ratio < *worst) *worst = ratio;
            if (have && fabs(ratio - prevRatio) > *jerk) *jerk = fabs(ratio - prevRatio);
            prevRatio = ratio; have = YES;
        }
    }
}
static void G2E_LogExpected(void) {
    if (!BP_LogEnabled()) return;
    static const double t1[] = { 0.0, 0.019, 0.041, 0.052, 0.061, 0.069 }, g1[] = { 1.0, 0.9933, 0.9085, 0.8538, 0.8291, 0.8073 };
    static const double t2[] = { 0.0, 0.002, 0.030 }, g2[] = { 1.0, 0.9895, 0.8171 };
    double w0, j0, w1, j1;
    G2E_Series(t1, g1, 6, 0.081, 0.0, &w0, &j0); G2E_Series(t1, g1, 6, 0.081, 0.15, &w1, &j1);
    BP_Log(@"[g2e] expected at 60 fps, flick of log fed63049: tracking response 0 -> worst frame ratio %.3f, max ratio change %.3f | response 0.15 -> %.3f, %.3f", w0, j0, w1, j1);
    G2E_Series(t2, g2, 3, 0.048, 0.0, &w0, &j0); G2E_Series(t2, g2, 3, 0.048, 0.15, &w1, &j1);
    BP_Log(@"[g2e] expected at 60 fps, flick of log 4e9ad132: tracking response 0 -> worst frame ratio %.3f, max ratio change %.3f | response 0.15 -> %.3f, %.3f", w0, j0, w1, j1);
}

void G2E_Setup(void) {
    if (!G2E_ON()) return;
    Class c = NSClassFromString(@"SBHomeGestureSwitcherModifier");
    SEL s = NSSelectorFromString(@"_layoutSettingsForAppLayout:layoutSettings:");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m || !class_getInstanceVariable(c, "_startingEnvironmentMode")) { BP_Log(@"[g2e] SBHomeGestureSwitcherModifier _layoutSettingsForAppLayout:layoutSettings: not found, not installed"); return; }
    gG2EOrigLayout = method_getImplementation(m);
    class_replaceMethod(c, s, (IMP)G2E_LayoutSettings, method_getTypeEncoding(m));
    BP_Log(@"[g2e] installed (home swipe close: instant gesture tracking of a mode 3 start becomes the stock tracking spring)");
    G2E_LogExpected();
}
#pragma clang diagnostic pop
