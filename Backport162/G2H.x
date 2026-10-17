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
// The mask keeps its job (crop the card to the icon box, g2f_closecrop) but is given room for the shadow wherever it is not cropping: whenever its bounds are set to a size that
// covers the container (creation, and the target of the "zoom over" animation that ends in the release) the mask view is inflated by the extent of the window's shadow on every side:
// slack = max over the shadow views of (2.8 x shadowRadius + max(|offset.x|, |offset.y|)), 2.8 being the factor stock itself uses for the shadow-inclusive bounds
// (-[SBFluidSwitcherViewController _visibleSwitcherBoundsIncludingShadow], 16.2 0x1c78133f4 const -2.8; G1C.x).  Bounds that crop (the icon box) stay exact.  Consequences:
//  * close: the mask starts as large as container + shadow (nothing changes in the first frame, the shadow does not vanish), then shrinks to the icon box with the same spring as before:
//    the shadow is swept away together with the zoom instead of switching off;
//  * open: the first pass creates the mask at container + shadow (the 25 ms until the "zoom over" pass crop it, the card is icon sized then), the "zoom over" animation grows it to container +
//    shadow, so the shadow is revealed with the window, and when G2F releases the mask nothing changes in that frame (the mask never clipped anything inside the slack).
// Implemented without touching G2F.x: the plain UIView that G2F sets as the item container's maskView (hook of -[SBFluidSwitcherItemContainer setMaskView:]) is switched to a runtime
// subclass (object_setClass, no new ivars: the instance size is unchanged) that adds the slack in -setBounds: and takes it out again in the -bounds getter, so G2F's own comparisons of
// mask.bounds with the container bounds keep working.  The host container is kept in an associated weak box.
//
// ===== Diagnostics (Backport162.debug, g2h_dimdiag) =====
// For every animated home -> app (1 -> 3) and app -> home (3 -> 1) transition of the root: one line per transition phase and one every 50 ms for 1.5 s after phase 1 ("[g2h] dim#N
// open|close t=+0.350 ..."): the root's answers for the window (shadowOpacityForLayoutRole:atIndex:, shadowStyleForLayoutRole:inAppLayout:, opacityForLayoutRole:..., dimmingAlpha...,
// wallpaperOverlayAlpha, lighteningAlpha, backgroundOpacity) and for the home screen / wallpaper (homeScreenAlpha, homeScreenDimmingAlpha, homeScreenBackdropBlurProgress / Type,
// homeScreenScale, wallpaperScale / Style), and what the item container really shows: its shadowAlpha / shadowStyle, every shadow layer (radius, opacity, offset, view alpha, presentation
// opacity) and the mask (class, bounds, presentation bounds, corner radius).  Mask adoption / removal lines carry the slack.
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

// weak holder of the container that a mask belongs to (the mask can outlive its container inside an animation completion block)
@interface G2HWeakBox : NSObject
@property (nonatomic, weak) UIView *view;
@end
@implementation G2HWeakBox
@end

static IMP gG2HOrigSetMask, gG2HOrigEvent, gG2HOrigLayout;
static IMP gG2HUISetBounds, gG2HUIBounds;                                  // UIView's own -setBounds: / -bounds (the superclass implementations of the mask subclass)
static Class gG2HMaskCls;
static const void *kG2HHost = &kG2HHost;                                    // associated G2HWeakBox on the mask view
static const void *kG2HApplied = &kG2HApplied;                              // associated NSNumber on the mask view: the slack included in its current bounds (each side)

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
// Part 1: the shadow room of G2F's crop mask (g2h_maskshadow)
// ==================================================================================================================================================================================
static UIView *G2H_Host(UIView *mask) {
    G2HWeakBox *b = objc_getAssociatedObject(mask, kG2HHost);
    return b.view;
}
static double G2H_Applied(UIView *mask) {
    NSNumber *n = objc_getAssociatedObject(mask, kG2HApplied);
    return n ? n.doubleValue : 0.0;
}

// The extent of the window's shadow: every SBAppSwitcherPageShadowView below the container, its own layer and the layers of its subviews (the diffuse and the rim shadow view), the layers
// that really shadow (radius > 0 and opacity > 0).  2.8 x radius + the larger offset component, the shadow-inclusive inset of stock (see the header).  0 when there is no shadow.
static void G2H_ScanShadow(UIView *v, int depth, int *budget, double *e, int *n, NSMutableString *dump) {
    if (!v || depth > 10 || *budget <= 0) return;
    (*budget)--;
    static Class sh; static dispatch_once_t once;
    dispatch_once(&once, ^{ sh = NSClassFromString(@"SBAppSwitcherPageShadowView"); });
    if (sh && [v isKindOfClass:sh]) {
        NSMutableArray *views = [NSMutableArray arrayWithObject:v];
        for (UIView *s in v.subviews) [views addObject:s];
        for (UIView *s in views) {
            CALayer *l = s.layer;
            if (!l) continue;
            double r = l.shadowRadius, op = l.shadowOpacity;
            CGSize off = l.shadowOffset;
            if (dump) [dump appendFormat:@" [%@ r %.1f op %.2f off {%.1f, %.1f} alpha %.2f pres %.2f]", s == v ? @"shadowview" : NSStringFromClass([s class]), r, op, off.width, off.height, s.alpha,
                       (double)([l presentationLayer] ? [(CALayer *)[l presentationLayer] shadowOpacity] : op)];
            if (r > 0.0 && op > 0.0) {
                double x = 2.8 * r + fmax(fabs(off.width), fabs(off.height));
                if (x > *e) *e = x;
                (*n)++;
            }
        }
        return;
    }
    for (UIView *s in v.subviews) G2H_ScanShadow(s, depth + 1, budget, e, n, dump);
}
static double G2H_Slack(UIView *host, int *count) {
    double e = 0.0; int n = 0, budget = 600;
    G2H_ScanShadow(host, 0, &budget, &e, &n, nil);
    if (count) *count = n;
    return e;
}

// the mask subclass: -setBounds: adds the slack when the requested size covers the host (not cropping), -bounds hides it again
static void G2H_MaskSetBounds(UIView *self, SEL _cmd, CGRect b) {
    CGRect eff = b;
    double applied = 0.0;
    UIView *host = G2H_Host(self);
    if (host && G2H_FIX_ON()) {
        CGSize hs = host.bounds.size;
        if (b.size.width >= hs.width - 0.01 && b.size.height >= hs.height - 0.01) {
            applied = G2H_Slack(host, NULL);
            eff.size.width += 2.0 * applied;
            eff.size.height += 2.0 * applied;
        }
    }
    objc_setAssociatedObject(self, kG2HApplied, applied != 0.0 ? @(applied) : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, CGRect))gG2HUISetBounds)(self, _cmd, eff);
}
static CGRect G2H_MaskBounds(UIView *self, SEL _cmd) {
    CGRect b = ((CGRect (*)(id, SEL))gG2HUIBounds)(self, _cmd);
    double a = G2H_Applied(self);
    if (a != 0.0) { b.size.width -= 2.0 * a; b.size.height -= 2.0 * a; }
    return b;
}

// -[UIView setMaskView:] on SBFluidSwitcherItemContainer: the plain UIView of G2F becomes a G2HMask and is inflated at once (inside performWithoutAnimation: G2F's block around the
// assignment is already one, the second one is for any other caller).
static void G2H_SetMaskView(id self, SEL _cmd, UIView *m) {
    UIView *prev = nil;
    if (!m && BP_LogEnabled() && [self respondsToSelector:@selector(maskView)]) prev = [(UIView *)self maskView];
    ((void (*)(id, SEL, id))gG2HOrigSetMask)(self, _cmd, m);
    if (!m) {
        if (prev && gG2HMaskCls && object_getClass(prev) == gG2HMaskCls) G2H_LOG(@"[g2h] mask removed from container %p (the shadow is no longer clipped by anything; mask bounds %@)", self, NSStringFromCGRect(prev.bounds));
        return;
    }
    @try {
        if (!G2H_FIX_ON() || !gG2HMaskCls || ![self isKindOfClass:[UIView class]]) return;
        if (object_getClass(m) != [UIView class]) return;                     // only the plain UIView that G2F creates (an adopted mask already has our class)
        UIView *host = (UIView *)self;
        G2HWeakBox *box = [G2HWeakBox new];
        box.view = host;
        objc_setAssociatedObject(m, kG2HHost, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        object_setClass(m, gG2HMaskCls);
        CGSize cb = host.bounds.size;
        [UIView performWithoutAnimation:^{ m.bounds = CGRectMake(0, 0, cb.width, cb.height); }];
        int n = 0;
        double e = G2H_Slack(host, &n);
        G2H_LOG(@"[g2h] mask adopted on container %p: container bounds %@, shadow slack %.1f on every side (%d shadow layers), mask bounds now %@ (logical %@)", self, NSStringFromCGSize(cb), e, n,
                NSStringFromCGRect([m.layer bounds]), NSStringFromCGRect(m.bounds));
        if (e == 0.0) G2H_LOG(@"[g2h] mask adopted without slack: no shadow layer (radius > 0, opacity > 0) below the container yet; later bounds changes look again");
    } @catch (NSException *ex) { G2H_LOG(@"[g2h] mask adoption exception %@", ex); }
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
        NSMutableString *sh = [NSMutableString string];
        int budget = 600, n = 0; double e = 0;
        G2H_ScanShadow(cv, 0, &budget, &e, &n, sh);
        [o appendFormat:@" shadows(%d, extent %.1f)%@", n, e, sh.length ? sh : @" none"];
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
    // part 1: the mask subclass and the setMaskView: hook of the item container
    Class ic = NSClassFromString(@"SBFluidSwitcherItemContainer");
    SEL ms = @selector(setMaskView:);
    Method mm = ic ? class_getInstanceMethod(ic, ms) : NULL;
    Method sb = class_getInstanceMethod([UIView class], @selector(setBounds:));
    Method gb = class_getInstanceMethod([UIView class], @selector(bounds));
    if (!mm || !sb || !gb) {
        BP_Log(@"[g2h] SBFluidSwitcherItemContainer setMaskView: / UIView bounds not found, mask shadow room not installed");
    } else {
        gG2HUISetBounds = method_getImplementation(sb);
        gG2HUIBounds = method_getImplementation(gb);
        Class sub = NSClassFromString(@"BP162ShadowRoomMaskView");
        if (!sub) {
            sub = objc_allocateClassPair([UIView class], "BP162ShadowRoomMaskView", 0);
            if (sub) {
                class_addMethod(sub, @selector(setBounds:), (IMP)G2H_MaskSetBounds, method_getTypeEncoding(sb));
                class_addMethod(sub, @selector(bounds), (IMP)G2H_MaskBounds, method_getTypeEncoding(gb));
                objc_registerClassPair(sub);
            }
        }
        gG2HMaskCls = sub;
        if (!sub) BP_Log(@"[g2h] could not create the mask subclass, mask shadow room not installed");
        else {
            gG2HOrigSetMask = method_getImplementation(mm);
            class_replaceMethod(ic, ms, (IMP)G2H_SetMaskView, method_getTypeEncoding(mm));
            BP_Log(@"[g2h] installed (the crop mask of g2f_closecrop leaves room for the window's shadow: %@)", G2H_FIX_ON() ? @"ON" : @"off");
        }
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
