// G2H.x : the drop shadow of a window popped in / out around the zoom to / from a home screen icon.  Switch g2h_maskshadow (default ON, a repair of OUR deviation g2f_closecrop, not of stock)
// and g2h_dimdiag (default ON, diagnostics only, writes only with Backport162.debug).  Kill switch files: <jbroot>/tmp/Backport162.off.g2h_maskshadow / .off.g2h_dimdiag.
// Setup: G2H_Setup().  Log lines: "[g2h] ...".  Spec: specs/OPEN-DIM-0.7.7.md (evidence with numbers, addresses, reasoning, what is unproven).
//
// ===== Symptom (user, recording 8227294a = RPReplay_Final1792262963, a windowed web app opened / closed from its Home Screen icon) =====
// "the area around the window darkens like a sec after the window fully opens".  Measured: while the window opens the wallpaper dims smoothly (home screen blur), the window reaches
// its final size at t = 2.09 s, and in ONE frame (t = 2.093 s, same at 3.793 s and 5.577 s) a drop shadow appears around the window (mean luma -15 right of it, -14 below it, -4 above
// it, decaying with the distance); on every close the shadow vanishes within two frames of the start of the close (t = 2.727 .. 2.743 s).  Open start -> pop = 0.45 s each time.
//
// ===== Cause (our port, not stock) =====
// The window's shadow is CALayer shadow of two views inside the item container (SBAppSwitcherPageView -> SBAppSwitcherPageShadowView -> diffuse / rim shadow view; 16.0 0x1c5ed3d00 /
// 0x1c5ed43fc set layer shadowRadius / shadowOpacity / shadowOffset), i.e. it is drawn OUTSIDE the container's bounds.  G2F.x (g2f_closecrop, build 24816c1) crops the card to the icon
// box during the zoom with a UIView maskView on the item container whose bounds start at / return to the container bounds.  A layer mask clips every sublayer, shadows included, so while
// the mask exists the shadow cannot be seen: the mask is created in the first layout pass of an open (phase 1) and of a close, released when the spring that animates it back to the
// container bounds has settled (log "[g2f] crop: mask released", 0.53 s after "zoom over" in log 291a0cf5).  Stock drives the shadow smoothly (shadowOpacityForLayoutRole:atIndex:
// 1.0 from the Stage Manager floor, applied with the "style" animation of _applyStyleToAppLayout:roleMask:completion:, 16.0 0x1c5fd5504 / 16.2 0x1c744e5c4 identical for the shadow); the
// jump is the mask coming off (open) and going on (close).
//
// ===== Fix (default ON) =====
// 0.7.7 first attempt (build ed3eb1b) inflated the crop mask by the shadow extent (231 pt on every side).  WRONG: the crop is measured in the mask's bounds, so with the mask 462 pt wider
// it only started to crop the card after half of its travel and the nested outer card of the old problem came back (user, recordings 080e9505 / 7b244285).  The mask is now EXACTLY what
// G2F makes (the geometry and timing of 24816c1, which the user approved, for the open as well as the close: nothing in this file touches the mask's bounds, centre or radius any more).
// What remains is the pop of the shadow when the mask is dropped.  The shadow is requested at full strength from the first frame (log 27f5d0d0: shadowOpacity 1.0, shadowStyle 5, container
// shadowAlpha 1.0, shadow layer r 70 / opacity 0.35 / offset y +35 at phase 1) and is hidden only by the mask, so when G2F drops the mask (end of the open, 0.56 - 0.60 s after phase 1) it is
// revealed in one frame.  The layer that draws it is NOT the SBAppSwitcherPageShadowView (its own layer has opacity 0, radius 3) but its child, an SBFView with shadowRadius 70 / shadowOpacity 0.35 /
// offset y +35 (found by the layer values: shadowRadius > 3 and shadowOpacity > 0).  Version 7df60c8 faded the UIView alpha of the page shadow view with animateWithDuration: and the
// user's recording d5e8fb61 (log bd05b284) still shows the pop in one frame (right strip 132.8 -> 123.7, below the window 151.2 -> 117.6, left 110.1 -> 102.8 between 2.152 and 2.168 s),
// so that fade did nothing visible.  Now: right after the mask is removed from an item container that is on screen, every shadow-casting layer gets an explicit Core Animation
// (CABasicAnimation on shadowOpacity, 0 -> its model value, ease-out, 0.28 s); the model value is not changed.  Follow-up samples at +50 / +100 / +200 / +300 ms log the presentation
// values (shadow fade lines).
// Not addressed (deliberately, the crop has priority): at the START of a close the shadow still disappears at once, because the exact crop mask clips it from its first frame; a shadow of the
// full window outline around a card that is being cropped to the icon box would show the old nested shape again.
//
// ===== Diagnostics (Backport162.debug, g2h_dimdiag) =====
// For every animated home -> app (1 -> 3) and app -> home (3 -> 1) transition of the root: one line per transition phase and one every 50 ms for 1.5 s after phase 1 ("[g2h] dim#N
// open|close t=+0.350 ..."): the root's answers for the window (shadowOpacityForLayoutRole:atIndex:, shadowStyleForLayoutRole:inAppLayout:, opacityForLayoutRole:..., dimmingAlpha...,
// wallpaperOverlayAlpha, lighteningAlpha, backgroundOpacity) and for the home screen / wallpaper (homeScreenAlpha, homeScreenDimmingAlpha, homeScreenBackdropBlurProgress / Type,
// homeScreenScale, wallpaperScale / Style), and what the item container really shows: its shadowAlpha / shadowStyle, every shadow layer (radius, opacity, offset, view alpha, presentation
// opacity) and the mask (class, bounds, presentation bounds, corner radius).  Mask set / removal lines and the mask timing samples (mask#N) are logged too.
//
// 16.0 = 20A8372, 16.2 = 20C65.  All reads are guarded (respondsToSelector, @try); the diagnostics run only with Backport162.debug on.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2H_FIX_ON() BP_OnName("g2h_maskshadow")
#define G2H_DIAG_ON() BP_OnName("g2h_dimdiag")
#define G2H_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static IMP gG2HOrigSetMask, gG2HOrigEvent, gG2HOrigLayout;
static unsigned gG2HMaskSerial;                                            // counts the masks that G2F put on an item container (each open / close that crops)
static const double kG2HFadeDuration = 0.28;                               // the fade of the shadow after the mask is dropped (seconds)

// ==================================================================================================================================================================================
// small typed senders
// ==================================================================================================================================================================================
static id G2H_IvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? BP_ObjIvar(o, iv) : nil;
}
static id G2H_Obj(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static id G2H_Obj1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil;
}
static long long G2H_LL(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((long long (*)(id, SEL))objc_msgSend)(o, s) : 0;
}
static BOOL G2H_Bool(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO;
}
static double G2H_Dbl(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(o, s) : 0.0;
}

// ==================================================================================================================================================================================
// Part 1: the shadow no longer pops when G2F drops the crop mask (g2h_maskshadow)
// ==================================================================================================================================================================================
// The layers that draw the window's shadow: every view below the container whose layer shadows for real (shadowOpacity > 0, shadowRadius > 3), found by the layer values and not by class
// name.  In log bd05b284 (and 27f5d0d0) that is ONE layer, the SBFView below the SBAppSwitcherPageShadowView: radius 70, opacity 0.35, offset y +35 (the page shadow view's own layer
// has opacity 0 and radius 3 and draws nothing).  budget / depth keep the walk cheap (a container holds the page, the app's view and a few accessories).
static void G2H_CollectShadow(UIView *v, int depth, int *budget, NSMutableArray *views) {
    if (!v || depth > 12 || *budget <= 0) return;
    (*budget)--;
    CALayer *l = v.layer;
    if (l && l.shadowRadius > 3.0 && l.shadowOpacity > 0.0) [views addObject:v];
    for (UIView *s in v.subviews) G2H_CollectShadow(s, depth + 1, budget, views);
}
// One text element per shadow-casting view (and the page shadow view that parents it): class, layer shadowRadius / shadowOpacity (model) / offset, view alpha, presentation shadowOpacity,
// presentation layer opacity, number of running animations.
static NSString *G2H_ShadowDump(UIView *host, int *count) {
    NSMutableArray *views = [NSMutableArray array];
    int budget = 800;
    G2H_CollectShadow(host, 0, &budget, views);
    NSMutableString *o = [NSMutableString string];
    for (UIView *v in views) {
        CALayer *l = v.layer, *pl = [l presentationLayer] ?: l;
        CGSize off = l.shadowOffset;
        [o appendFormat:@" [%@ r %.1f op %.3f off {%.1f, %.1f} alpha %.2f | pres op %.3f layerOpacity %.3f anims %lu]", NSStringFromClass([v class]), l.shadowRadius, l.shadowOpacity, off.width, off.height, v.alpha,
         pl.shadowOpacity, pl.opacity, (unsigned long)l.animationKeys.count];
    }
    if (count) *count = (int)views.count;
    return o;
}

// Fade the shadow in: the removal of the mask has just happened (same run loop turn, nothing rendered yet).  A UIView alpha animation of the page shadow view had no visible effect in
// recording d5e8fb61 (user: the pop is still one frame): the layer that draws the shadow is a child, its alpha was never what showed.  So the shadow layer's own shadowOpacity is animated
// with Core Animation (explicit CABasicAnimation 0 -> model value, ease-out, kG2HFadeDuration): independent of the UIView animation state of whatever block the mask was dropped in.
// The model value is left alone (the style pass keeps owning it).  Follow-up samples at +50 / +100 / +200 / +300 ms log the presentation values, which prove the fade.
static void G2H_FadeShadowIn(UIView *host) {
    NSMutableArray *views = [NSMutableArray array];
    int budget = 800;
    G2H_CollectShadow(host, 0, &budget, views);
    if (!views.count) { G2H_LOG(@"[g2h] mask removed from container %p: no shadow-casting layer (radius > 3, opacity > 0) below it, no fade", host); return; }
    for (UIView *v in views) {
        CALayer *l = v.layer;
        CABasicAnimation *an = [CABasicAnimation animationWithKeyPath:@"shadowOpacity"];
        an.fromValue = @(0.0f);
        an.toValue = @(l.shadowOpacity);
        an.duration = kG2HFadeDuration;
        an.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [l addAnimation:an forKey:@"bp162.g2h.shadowfade"];
    }
    G2H_LOG(@"[g2h] mask removed from container %p: %lu shadow layer(s) fade in over %.2f s (shadowOpacity 0 -> model value, CABasicAnimation):%@", host, (unsigned long)views.count, kG2HFadeDuration, G2H_ShadowDump(host, NULL));
    if (!BP_LogEnabled()) return;
    __weak UIView *wh = host;
    double t0 = CACurrentMediaTime();
    static const int kMs[] = { 50, 100, 200, 300 };
    for (int k = 0; k < 4; k++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMs[k] * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            UIView *h = wh;
            if (!h || !BP_LogEnabled()) return;
            @try { BP_Log(@"[g2h] shadow fade t=+%.3f container %p:%@", CACurrentMediaTime() - t0, h, G2H_ShadowDump(h, NULL)); } @catch (NSException *ex) { BP_Log(@"[g2h] shadow fade sample exception %@", ex); }
        });
    }
}

// Crop timing of one mask, for the log: its logical / layer (model) / presentation bounds, the container bounds, at the moment the mask is set and 50, 100, 150, 250 ms later.  With the mask
// exactly as G2F makes it the layer bounds equal the logical bounds (the model value, i.e. the target of the running animation); the presentation bounds are what is on screen.
static void G2H_MaskSample(UIView *host, UIView *m, unsigned serial, double t0, NSString *what) {
    CALayer *pl = [m.layer presentationLayer] ?: m.layer;
    G2H_LOG(@"[g2h] mask#%u %@ t=%+.3f container %p bounds %@ | mask logical %@ layer %@ pres %@ r %.1f (presentation r %.1f)", serial, what, CACurrentMediaTime() - t0, host,
            NSStringFromCGSize(host.bounds.size), NSStringFromCGSize(m.bounds.size), NSStringFromCGSize(m.layer.bounds.size), NSStringFromCGSize(pl.bounds.size), m.layer.cornerRadius, pl.cornerRadius);
}

// -[UIView setMaskView:] on SBFluidSwitcherItemContainer.  Removal of the mask: the shadow fades in.  A mask being set: timing diagnostics (nothing is changed).
static void G2H_SetMaskView(id self, SEL _cmd, UIView *m) {
    UIView *prev = nil;
    BOOL fade = NO;
    if (!m && [self isKindOfClass:[UIView class]] && [self respondsToSelector:@selector(maskView)]) {
        prev = [(UIView *)self maskView];
        UIView *h = (UIView *)self;
        fade = prev && G2H_FIX_ON() && h.window && !h.hidden && h.alpha > 0.01;       // a container that is being recycled is not on screen: no fade
    }
    ((void (*)(id, SEL, id))gG2HOrigSetMask)(self, _cmd, m);
    @try {
        if (!m) {
            if (fade) G2H_FadeShadowIn((UIView *)self);
            else if (prev) G2H_LOG(@"[g2h] mask removed from container %p (not on screen or g2h_maskshadow off: no fade)", self);
            return;
        }
        if (!BP_LogEnabled() || !G2H_DIAG_ON() || ![self isKindOfClass:[UIView class]]) return;
        UIView *host = (UIView *)self;
        unsigned serial = ++gG2HMaskSerial;
        double t0 = CACurrentMediaTime();
        __weak UIView *wh = host, *wm = m;
        G2H_MaskSample(host, m, serial, t0, @"set");
        static const int kMs[] = { 0, 50, 100, 150, 250 };
        for (int k = 0; k < 5; k++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kMs[k] * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                UIView *h = wh, *mm = wm;
                if (!h || !mm || !BP_LogEnabled()) return;
                @try { G2H_MaskSample(h, mm, serial, t0, @"sample"); } @catch (NSException *ex) { BP_Log(@"[g2h] mask sample exception %@", ex); }
            });
        }
    } @catch (NSException *ex) { G2H_LOG(@"[g2h] setMaskView exception %@", ex); }
}

// ==================================================================================================================================================================================
// Part 2: diagnostics (g2h_dimdiag)
// ==================================================================================================================================================================================
static __weak id gG2HVC;                                                   // the switcher view controller of the last layout pass
static unsigned gG2HSerial;                                                // serial of the traced transition (0 = none yet)
static double gG2HT0;                                                      // CACurrentMediaTime() of its phase 1
static int gG2HKind;                                                       // 1 open (1 -> 3), 2 close (3 -> 1)
static id gG2HLayout;                                                      // the stage layout of the traced transition (target of an open, source of a close)

static NSString *G2H_Q(id root, const char *sel, NSString *label, int kind, long long a, unsigned long long b, id l) {
    SEL s = sel_registerName(sel);
    if (!root || ![root respondsToSelector:s]) return @"";
    @try {
        switch (kind) {
            case 0: return [NSString stringWithFormat:@" %@=%.3f", label, ((double (*)(id, SEL))objc_msgSend)(root, s)];
            case 1: return [NSString stringWithFormat:@" %@=%lld", label, ((long long (*)(id, SEL))objc_msgSend)(root, s)];
            case 2: return b == NSNotFound ? @"" : [NSString stringWithFormat:@" %@=%.3f", label, ((double (*)(id, SEL, unsigned long long))objc_msgSend)(root, s, b)];
            case 3: return (b == NSNotFound) ? @"" : [NSString stringWithFormat:@" %@=%.3f", label, ((double (*)(id, SEL, long long, unsigned long long))objc_msgSend)(root, s, a, b)];
            case 4: return l ? [NSString stringWithFormat:@" %@=%lld", label, ((long long (*)(id, SEL, long long, id))objc_msgSend)(root, s, a, l)] : @"";
            case 5: return (l && b != NSNotFound) ? [NSString stringWithFormat:@" %@=%.3f", label, ((double (*)(id, SEL, long long, id, unsigned long long))objc_msgSend)(root, s, a, l, b)] : @"";
            case 6: return l ? [NSString stringWithFormat:@" %@=%.3f", label, ((double (*)(id, SEL, long long, id))objc_msgSend)(root, s, a, l)] : @"";
        }
    } @catch (NSException *ex) { return [NSString stringWithFormat:@" %@=<exception %@>", label, ex.name]; }
    return @"";
}

static NSString *G2H_Sample(id root, id vc, id layout) {
    NSMutableString *o = [NSMutableString string];
    NSUInteger idx = NSNotFound;
    long long role = 1;
    id leaf = nil, c = nil;
    @try {
        NSArray *aps = G2H_Obj(vc, "appLayouts");
        if (layout && aps) idx = [aps indexOfObject:layout];
        NSArray *leafs = G2H_Obj(layout, "leafAppLayouts");
        leaf = leafs.firstObject;
        id item = [G2H_Obj(leaf, "allItems") firstObject];
        if (item && [layout respondsToSelector:sel_registerName("layoutRoleForItem:")]) role = ((long long (*)(id, SEL, id))objc_msgSend)(layout, sel_registerName("layoutRoleForItem:"), item);
        c = leaf ? G2H_Obj1(vc, "_itemContainerForAppLayoutIfExists:", leaf) : nil;
    } @catch (NSException *ex) { [o appendFormat:@" <lookup exception %@>", ex.name]; }
    [o appendFormat:@" idx=%@ role=%lld |", idx == NSNotFound ? @"-" : [NSString stringWithFormat:@"%lu", (unsigned long)idx], role];
    [o appendString:G2H_Q(root, "shadowOpacityForLayoutRole:atIndex:", @"shadowOpacity", 3, role, idx, nil)];
    [o appendString:G2H_Q(root, "shadowStyleForLayoutRole:inAppLayout:", @"shadowStyle", 4, role, 0, layout)];
    [o appendString:G2H_Q(root, "opacityForLayoutRole:inAppLayout:atIndex:", @"opacity", 5, role, idx, layout)];
    [o appendString:G2H_Q(root, "dimmingAlphaForLayoutRole:inAppLayout:", @"dimming", 6, role, 0, layout)];
    [o appendString:G2H_Q(root, "wallpaperOverlayAlphaForIndex:", @"wallpaperOverlay", 2, 0, idx, nil)];
    [o appendString:G2H_Q(root, "lighteningAlphaForIndex:", @"lightening", 2, 0, idx, nil)];
    [o appendString:G2H_Q(root, "backgroundOpacityForIndex:", @"background", 2, 0, idx, nil)];
    [o appendString:@" | home"];
    [o appendString:G2H_Q(root, "homeScreenAlpha", @"alpha", 0, 0, 0, nil)];
    [o appendString:G2H_Q(root, "homeScreenDimmingAlpha", @"dim", 0, 0, 0, nil)];
    [o appendString:G2H_Q(root, "homeScreenBackdropBlurProgress", @"blur", 0, 0, 0, nil)];
    [o appendString:G2H_Q(root, "homeScreenBackdropBlurType", @"blurType", 1, 0, 0, nil)];
    [o appendString:G2H_Q(root, "homeScreenScale", @"scale", 0, 0, 0, nil)];
    [o appendString:G2H_Q(root, "wallpaperScale", @"wallpaperScale", 0, 0, 0, nil)];
    [o appendString:G2H_Q(root, "wallpaperStyle", @"wallpaperStyle", 1, 0, 0, nil)];
    [o appendString:@" | container"];
    if (!c || ![c isKindOfClass:[UIView class]]) { [o appendString:@" none"]; return o; }
    @try {
        UIView *cv = (UIView *)c;
        CALayer *pl = [cv.layer presentationLayer] ?: cv.layer;
        [o appendFormat:@" %p shadowAlpha=%.3f shadowStyle=%lld alpha=%.3f presBounds=%@", c, G2H_Dbl(c, "shadowAlpha"), G2H_LL(c, "shadowStyle"), cv.alpha, NSStringFromCGSize(pl.bounds.size)];
        int n = 0;
        NSString *sh = G2H_ShadowDump(cv, &n);
        [o appendFormat:@" shadows(%d)%@", n, sh.length ? sh : @" none"];
        UIView *m = cv.maskView;
        if (m) {
            CALayer *mp = [m.layer presentationLayer] ?: m.layer;
            [o appendFormat:@" mask(%@ logical %@ layer %@ pres %@ r %.1f)", NSStringFromClass([m class]), NSStringFromCGSize(m.bounds.size), NSStringFromCGSize(m.layer.bounds.size), NSStringFromCGSize(mp.bounds.size), m.layer.cornerRadius];
        } else [o appendString:@" mask(none)"];
    } @catch (NSException *ex) { [o appendFormat:@" <container exception %@>", ex.name]; }
    return o;
}

static void G2H_LogSample(id root, NSString *tag, unsigned serial, double t0) {
    id vc = gG2HVC;
    G2H_LOG(@"[g2h] dim#%u %@ t=%+.3f%@", serial, tag, CACurrentMediaTime() - t0, G2H_Sample(root, vc, gG2HLayout));
}

static void G2H_OnEvent(id root, id event) {
    long long f = G2H_LL(event, "fromEnvironmentMode"), t = G2H_LL(event, "toEnvironmentMode"), ph = G2H_LL(event, "phase");
    int kind = (f == 1 && t == 3) ? 1 : ((f == 3 && t == 1) ? 2 : 0);
    if (!kind || !G2H_Bool(event, "isAnimated")) return;
    double now = CACurrentMediaTime();
    if (ph == 1) {
        gG2HSerial++; gG2HT0 = now; gG2HKind = kind;
        gG2HLayout = G2H_Obj(event, kind == 1 ? "toAppLayout" : "fromAppLayout");
    } else if (!gG2HSerial || gG2HKind != kind || now - gG2HT0 > 6.0) return;
    unsigned serial = gG2HSerial;
    double t0 = gG2HT0;
    NSString *kn = kind == 1 ? @"open" : @"close";
    G2H_LOG(@"[g2h] dim#%u %@ phase=%lld gesture=%d modes %lld->%lld floor=%@", serial, kn, ph, G2H_Bool(event, "isGestureInitiated"), f, t, NSStringFromClass([G2H_Obj(root, "floorModifier") class]));
    G2H_LogSample(root, [NSString stringWithFormat:@"%@ phase=%lld", kn, ph], serial, t0);
    if (ph != 1) return;
    for (int k = 1; k <= 30; k++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(k * 50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if (gG2HSerial != serial || !BP_LogEnabled() || !G2H_DIAG_ON()) return;
            @try { G2H_LogSample(root, kn, serial, t0); } @catch (NSException *ex) { BP_Log(@"[g2h] dim sample exception %@", ex); }
        });
    }
}

static id G2H_Event(id self, SEL _cmd, id event) {
    id r = ((id (*)(id, SEL, id))gG2HOrigEvent)(self, _cmd, event);
    if (BP_LogEnabled() && G2H_DIAG_ON() && event) {
        @try { G2H_OnEvent(self, event); } @catch (NSException *ex) { BP_Log(@"[g2h] dim event exception %@", ex); }
    }
    return r;
}
static void G2H_Layout(id vc, SEL _cmd, id appLayout, unsigned long long roleMask, id completion) {
    gG2HVC = vc;
    ((void (*)(id, SEL, id, unsigned long long, id))gG2HOrigLayout)(vc, _cmd, appLayout, roleMask, completion);
}

// ==================================================================================================================================================================================
void G2H_Setup(void) {
    // part 1: the setMaskView: hook of the item container
    Class ic = NSClassFromString(@"SBFluidSwitcherItemContainer");
    SEL ms = @selector(setMaskView:);
    Method mm = ic ? class_getInstanceMethod(ic, ms) : NULL;
    if (!mm) {
        BP_Log(@"[g2h] SBFluidSwitcherItemContainer setMaskView: not found, shadow fade not installed");
    } else {
        gG2HOrigSetMask = method_getImplementation(mm);
        class_replaceMethod(ic, ms, (IMP)G2H_SetMaskView, method_getTypeEncoding(mm));
        BP_Log(@"[g2h] installed (the window shadow fades in over %.2f s when the crop mask of g2f_closecrop is dropped instead of popping: %@; mask timing log with Backport162.debug)", kG2HFadeDuration, G2H_FIX_ON() ? @"ON" : @"off");
    }
    // part 2: diagnostics
    Class rc = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
    SEL es = sel_registerName("handleTransitionEvent:");
    Method em = rc ? class_getInstanceMethod(rc, es) : NULL;
    Class vcc = NSClassFromString(@"SBFluidSwitcherViewController");
    SEL ls = sel_registerName("_layoutAppLayout:roleMask:completion:");
    Method lm = vcc ? class_getInstanceMethod(vcc, ls) : NULL;
    if (!em || !lm) { BP_Log(@"[g2h] SBContinuousExposeRootSwitcherModifier handleTransitionEvent: / SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion: not found, dim diagnostics not installed"); return; }
    gG2HOrigEvent = method_getImplementation(em);
    class_replaceMethod(rc, es, (IMP)G2H_Event, method_getTypeEncoding(em));
    gG2HOrigLayout = method_getImplementation(lm);
    class_replaceMethod(vcc, ls, (IMP)G2H_Layout, method_getTypeEncoding(lm));
    BP_Log(@"[g2h] installed (dim diagnostics %@: open / close of a window to the home screen, queries + shadow + mask at each phase and every 50 ms for 1.5 s, only with Backport162.debug)", G2H_DIAG_ON() ? @"ON" : @"off");
}
#pragma clang diagnostic pop
