// P1SW.m : switcher modifier / coordinator leftovers of REVIEW-CORE-0.7.9 (specs/CORE-LEFTOVERS-0.7.9.md item 3): M4, M6, M8 (M5 is appended below by its own section).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Every body was decoded from the 16.2 disassembly and diffed against the 16.0 method.
// Switches (all default on; each replaced IMP checks its switch at call time and runs the saved 16.0 IMP when it is off):
//   p1_homescroll  SBHomeGestureToSwitcherSwitcherModifier -_appLayoutToScrollToDuringTransition  (M8)
//   p1_defroles    SBDefaultImplementationsSwitcherModifier -scaleForLayoutRole:inAppLayout: / -frameForLayoutRole:inAppLayout:withBounds:  (M4)
//   p1_asynceval   SBMainSwitcherControllerCoordinator -_evaluateAsynchronousRenderingEnablement is a no-op like 16.2  (M6)
// Logs: grep "p1sw:" in Backport162.log.

#import "G1BKit.h"
#import <dlfcn.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static id PS_S0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((id (*)(id, SEL))objc_msgSend)(o, x) : nil; }
static id PS_S1(id o, const char *s, id a) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, x, a) : nil; }
static BOOL PS_B0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, x) : NO; }
static BOOL PS_B1(id o, const char *s, id a) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((BOOL (*)(id, SEL, id))objc_msgSend)(o, x, a) : NO; }
static long long PS_L0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((long long (*)(id, SEL))objc_msgSend)(o, x) : 0; }
static double PS_D0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((double (*)(id, SEL))objc_msgSend)(o, x) : 0.0; }
static CGRect PS_R0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, x) : CGRectZero; }
static CGPoint PS_P1(id o, const char *s, id a) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(o, x, a) : CGPointZero; }
static CGSize PS_Z1(id o, const char *s, id a) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((CGSize (*)(id, SEL, id))objc_msgSend)(o, x, a) : CGSizeZero; }
static long long PS_IvarLL(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? *(long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : 0;
}
static id PS_Ivar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return BP_ObjIvar(o, iv);
}
static CGPoint PS_IvarPoint(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? *(CGPoint *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : CGPointZero;
}
static IMP PS_Replace(const char *cls, const char *sel, IMP imp) {
    Class c = NSClassFromString([NSString stringWithUTF8String:cls]);
    SEL s = sel_registerName(sel);
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) { BP_Log(@"p1sw: %s -%s not found, not replaced", cls, sel); return NULL; }
    IMP prev = method_getImplementation(m);
    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
    return prev;
}

static IMP sScroll, sDefScale, sDefFrame, sAsyncEval;

// ---------------------------------------------------------------------------------------------- M8 _appLayoutToScrollToDuringTransition (16.2 0x1c795038c, 16.0 0x1c6499a54)
// Deltas 16.0 -> 16.2 (everything else, including the arithmetic, is identical): the first thing 16.2 reads is -isChamoisWindowingUIEnabled.
//  * _startingEnvironmentMode (+0x98) == 1 (start from the home screen): 16.0 returns [appLayouts firstObject]. 16.2 with Stage Manager returns the first app layout of the FIRST
//    continuous expose identifier ([[self appLayoutsForContinuousExposeIdentifier:[[self continuousExposeIdentifiersInSwitcher] firstObject]] firstObject]), nil when there is no
//    identifier. Without Stage Manager it is the 16.0 behaviour.
//  * every other mode: index of _appLayout (+0x88) in appLayouts (nil when NSNotFound), +1 / -1 from the lift off velocity (+0xa0, x only) or translation (+0xb0, x only) against
//    velocityXThresholdForUnconditionalArcSwipe * points per millimetre and half the container width; 16.0 then applied the selection tweak "mode 3 and the new index is 0 -> index
//    (w8 ^ 1)"; 16.2 skips that tweak when Stage Manager is on. Final clamp: min(count - 1, max(0, index)).
// _SBMainScreenPointsPerMillimeter is a private static of SpringBoard (not exported): (MGCopyAnswer("main-screen-pitch") / 25.4) / [[UIScreen mainScreen] nativeScale], once.
static double PS_PointsPerMillimeter(void) {
    static double v;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        typedef void *(*MGFn)(void *, void *);
        MGFn mg = (MGFn)dlsym(RTLD_DEFAULT, "MGCopyAnswer");
        double dpi = 264.0;                                                              // iPad pitch; only used when MobileGestalt cannot be reached
        if (mg) {
            id a = (__bridge_transfer id)mg((__bridge void *)@"main-screen-pitch", NULL);
            SEL uv = sel_registerName("unsignedIntValue");
            unsigned int pitch = [a respondsToSelector:uv] ? ((unsigned int (*)(id, SEL))objc_msgSend)(a, uv) : 0;
            if (pitch > 0) dpi = (double)pitch;
        }
        id screen = PS_S0((id)NSClassFromString(@"UIScreen"), "mainScreen");
        double ns = PS_D0(screen, "nativeScale");
        v = (dpi / 25.4) / (ns > 0 ? ns : 2.0);
    });
    return v;
}
static id PS_ScrollTo(id self, SEL _cmd) {
    if (!BP_OnName("p1_homescroll")) return ((id (*)(id, SEL))sScroll)(self, _cmd);
    BOOL chamois = PS_B0(self, "isChamoisWindowingUIEnabled");
    long long mode = PS_IvarLL(self, "_startingEnvironmentMode");
    if (mode == 1 && chamois) {
        SEL ids = sel_registerName("continuousExposeIdentifiersInSwitcher"), forId = sel_registerName("appLayoutsForContinuousExposeIdentifier:");
        if (![self respondsToSelector:ids] || ![self respondsToSelector:forId]) return ((id (*)(id, SEL))sScroll)(self, _cmd);   // the 16.0 selector family only: the 16.0 result
        id ident = [(NSArray *)PS_S0(self, "continuousExposeIdentifiersInSwitcher") firstObject];
        if (!ident) return nil;
        return [(NSArray *)PS_S1(self, "appLayoutsForContinuousExposeIdentifier:", ident) firstObject];
    }
    if (mode == 1) return [(NSArray *)PS_S0(self, "appLayouts") firstObject];
    NSArray *layouts = PS_S0(self, "appLayouts");
    NSUInteger idx = [layouts indexOfObject:PS_Ivar(self, "_appLayout")];
    if (idx == NSNotFound) return nil;
    double thr = PS_D0(PS_S0(self, "homeGestureSettings"), "velocityXThresholdForUnconditionalArcSwipe") * PS_PointsPerMillimeter();
    double width = PS_R0(self, "containerViewBounds").size.width;
    double vel = PS_IvarPoint(self, "_liftOffVelocity").x, trans = PS_IvarPoint(self, "_liftOffTranslation").x;
    unsigned w8 = (vel > thr) ? 1u : (trans > width * 0.5 ? 1u : 0u);
    long long n;
    BOOL decrement = (vel < -thr) || (trans < -width * 0.5);
    if (decrement) n = (long long)idx - 1; else n = (long long)idx + (long long)w8;
    if (!chamois) {                                                                     // 16.0 only: the selection tweak
        BOOL keep = (mode != 3) || (n != 0);
        if (decrement || keep) n = keep ? n : 0;
        else n = (long long)(w8 ^ 1u);
    }
    long long last = (long long)layouts.count - 1, lo = n < 0 ? 0 : n;
    long long pick = last > lo ? lo : last;
    if (pick < 0) return nil;                                                           // empty list (16.2 would throw on objectAtIndex:-1)
    return [layouts objectAtIndex:(NSUInteger)pick];
}

// ---------------------------------------------------------------------------------------------- M4 SBDefaultImplementationsSwitcherModifier role scale / frame
// scaleForLayoutRole:inAppLayout: 16.2 0x1c788a930 (16.0 0x1c63df6b8 is `fmov d0, #1.0; ret`): with Stage Manager on the model based scale of the item of that role:
//   al = [self appLayoutContainingAppLayout:layout]; item = [al itemForLayoutRole:[al layoutRoleForItem:[layout itemForLayoutRole:role]]]; model = [self overlappingModelForAppLayout:layout];
//   fully occluded -> [[self chamoisLayoutAttributes] stageOcclusionDodgingPeekScale]; partially occluded -> [attrs partiallyOccludedStageScaleForItemWithSize:[model sizeForItem:item]]; else 1.0.
// frameForLayoutRole:inAppLayout:withBounds: 16.2 0x1c788a480 (16.0 0x1c63df34c): environment 2 / 3, Stage Manager off and role 4 (the center item) are unchanged. For the model path
// (Stage Manager, other roles) 16.2 adds to the 16.0 maths (a) the peeking centre of a fully occluded item (when unoccludedPeekingCenterForItem: is not CGPointZero it replaces the
// centre; NOT in the review, found in the disassembly) and (b) for stages with two or more items the scale about the overlapping anchor for a partially occluded item:
// origin -= (centerForItem - overlappingScaleAnchorCenterForItem) * (1 - scale), scale = 1 or partiallyOccludedStageScaleForItemWithSize:; skipped for a fully occluded item.
// The model selectors that 16.0 lacks (unoccludedPeekingCenterForItem:, overlappingScaleAnchorCenterForItem:, partiallyOccludedStageScaleForItemWithSize:) are added by G2; when one of them
// is missing the 16.0 body runs. The FullScreen floor (G1C_FS_RoleScale / RoleFrame) answers these queries first in the Stage Manager chains; this default is the 16.2 answer of the chains without it.
static BOOL PS_ModelReady(void) {
    static int ok = -1;
    if (ok < 0) {
        Class calc = NSClassFromString(@"SBDisplayItemLayoutAttributesCalculator");
        Class model = NSClassFromString(@"SBChamoisOverlappingModel");
        Class attrs = NSClassFromString(@"SBSwitcherChamoisLayoutAttributes");
        ok = (calc && model && attrs
              && class_getInstanceMethod(model, sel_registerName("unoccludedPeekingCenterForItem:"))
              && class_getInstanceMethod(model, sel_registerName("overlappingScaleAnchorCenterForItem:"))
              && class_getInstanceMethod(attrs, sel_registerName("partiallyOccludedStageScaleForItemWithSize:"))) ? 1 : 0;
        if (!ok) BP_Log(@"p1sw: defroles: the model / attribute selectors are not all present (calc=%d model=%d attrs=%d), the 16.0 default role frame / scale stay", calc != nil, model != nil, attrs != nil);
    }
    return ok == 1;
}
static double PS_DefScale(id self, SEL _cmd, long long role, id layout) {
    if (!BP_OnName("p1_defroles") || !PS_ModelReady()) return ((double (*)(id, SEL, long long, id))sDefScale)(self, _cmd, role, layout);
    if (!PS_B0(self, "isChamoisWindowingUIEnabled")) return 1.0;
    id al = PS_S1(self, "appLayoutContainingAppLayout:", layout);
    SEL ifr = sel_registerName("itemForLayoutRole:"), lri = sel_registerName("layoutRoleForItem:");
    if (![layout respondsToSelector:ifr] || ![al respondsToSelector:lri] || ![al respondsToSelector:ifr]) return 1.0;
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(layout, ifr, role);
    long long r = ((long long (*)(id, SEL, id))objc_msgSend)(al, lri, item);
    id model = PS_S1(self, "overlappingModelForAppLayout:", layout);
    id attrs = PS_S0(self, "chamoisLayoutAttributes");
    id it2 = ((id (*)(id, SEL, long long))objc_msgSend)(al, ifr, r);
    if (PS_B1(model, "isItemFullyOccluded:", it2)) return PS_D0(attrs, "stageOcclusionDodgingPeekScale");
    if (!PS_B1(model, "isItemPartiallyOccluded:", it2)) return 1.0;
    SEL ps = sel_registerName("partiallyOccludedStageScaleForItemWithSize:");
    if (![attrs respondsToSelector:ps]) return 1.0;
    return ((double (*)(id, SEL, CGSize))objc_msgSend)(attrs, ps, PS_Z1(model, "sizeForItem:", it2));
}
static CGRect PS_Integral(CGRect r, double scale) {                                    // _UIRectIntegralWithScale: origin down, far edge up, on the pixel grid
    typedef CGRect (*Fn)(CGRect, double);
    static Fn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (Fn)dlsym(RTLD_DEFAULT, "UIRectIntegralWithScale"); });
    if (fn) return fn(r, scale);
    if (scale <= 0) scale = 1;
    double x0 = floor(CGRectGetMinX(r) * scale) / scale, y0 = floor(CGRectGetMinY(r) * scale) / scale;
    double x1 = ceil(CGRectGetMaxX(r) * scale) / scale, y1 = ceil(CGRectGetMaxY(r) * scale) / scale;
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}
static CGRect PS_DefFrame(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    typedef CGRect (*Orig)(id, SEL, long long, id, CGRect);
    if (!BP_OnName("p1_defroles") || !PS_ModelReady()) return ((Orig)sDefFrame)(self, _cmd, role, layout, bounds);
    long long env = PS_L0(self, "environment");
    if (env == 3 || env == 2 || role == 4 || !PS_B0(self, "isChamoisWindowingUIEnabled")) return ((Orig)sDefFrame)(self, _cmd, role, layout, bounds);   // identical in 16.0 and 16.2
    id calc = PS_S0(self, "displayItemLayoutAttributesCalculator");
    SEL om = sel_registerName("overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:");
    SEL ifr = sel_registerName("itemForLayoutRole:");
    if (![calc respondsToSelector:om] || ![layout respondsToSelector:ifr]) return ((Orig)sDefFrame)(self, _cmd, role, layout, bounds);
    id al = PS_S1(self, "appLayoutContainingAppLayout:", layout);
    long long orient = PS_L0(self, "switcherInterfaceOrientation");
    id attrs = PS_S0(self, "chamoisLayoutAttributes");
    double dock = PS_D0(self, "floatingDockHeight"), scale = PS_D0(self, "screenScale");
    CGRect cb = PS_R0(self, "containerViewBounds");
    BOOL sh = PS_B0(self, "prefersStripHidden"), dh = PS_B0(self, "prefersDockHidden");
    id model = ((id (*)(id, SEL, id, long long, id, double, double, CGRect, BOOL, BOOL))objc_msgSend)(calc, om, al, orient, attrs, dock, scale, cb, sh, dh);
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(layout, ifr, role);
    CGPoint c = PS_P1(model, "centerForItem:", item);
    if (PS_B1(model, "isItemFullyOccluded:", item)) {
        CGPoint peek = PS_P1(model, "unoccludedPeekingCenterForItem:", item);
        if (!(peek.x == 0 && peek.y == 0)) c = peek;                                    // CGPointZero = no peeking centre
    }
    CGSize size = PS_Z1(model, "sizeForItem:", item);
    CGRect rect = CGRectMake(c.x - size.width * 0.5, c.y - size.height * 0.5, size.width, size.height);    // _UIRectCenteredAboutPoint(_SBRectWithSize(size), center)
    CGRect bb = PS_R0(model, "boundingBox");
    double x = bounds.origin.x + (rect.origin.x - bb.origin.x), y = bounds.origin.y + (rect.origin.y - bb.origin.y);
    NSArray *all = PS_S0(layout, "allItems");
    if ([all count] >= 2) {
        id attrs2 = PS_S0(self, "chamoisLayoutAttributes");
        id model2 = PS_S1(self, "overlappingModelForAppLayout:", layout);
        id item2 = ((id (*)(id, SEL, long long))objc_msgSend)(layout, ifr, role);
        if (!PS_B1(model2, "isItemFullyOccluded:", item2)) {
            CGPoint c2 = PS_P1(model2, "centerForItem:", item2);
            CGPoint anchor = PS_P1(model2, "overlappingScaleAnchorCenterForItem:", item2);
            double s = 1.0;
            if (PS_B1(model2, "isItemPartiallyOccluded:", item2)) {
                SEL ps = sel_registerName("partiallyOccludedStageScaleForItemWithSize:");
                if ([attrs2 respondsToSelector:ps]) s = ((double (*)(id, SEL, CGSize))objc_msgSend)(attrs2, ps, PS_Z1(model2, "sizeForItem:", item2));
            }
            x -= (c2.x - anchor.x) * (1.0 - s);
            y -= (c2.y - anchor.y) * (1.0 - s);
        }
    }
    return PS_Integral(CGRectMake(x, y, rect.size.width, rect.size.height), PS_D0(self, "screenScale"));
}

// ---------------------------------------------------------------------------------------------- M6 _evaluateAsynchronousRenderingEnablement (16.2 0x1c76e1fcc is a bare `ret`, 16.0 0x1c624ce08 275 instructions)
// 16.0 toggled -setAsyncRenderingDisabled: of the main display's switcher VC and the layer target's async rendering (embedded display switcher window) from the coordinator on every transition
// (to / from the switcher environment mode 3). 16.2 left that to the per-display VC response flags (-_updateAsyncRenderingAndResizesHostedContext, ported in P1Drag.m, M7).
static void PS_AsyncEval(id self, SEL _cmd) {
    if (!BP_OnName("p1_asynceval")) { ((void (*)(id, SEL))sAsyncEval)(self, _cmd); return; }
    static BOOL logged;
    if (!logged) { logged = YES; BP_Log(@"p1sw: _evaluateAsynchronousRenderingEnablement skipped (16.2 body is empty; kill file Backport162.off.p1_asynceval restores the 16.0 body)"); }
}

void P1SW_Setup(void) {
    if (!BP_OnName("p1_sw")) return;
    sScroll = PS_Replace("SBHomeGestureToSwitcherSwitcherModifier", "_appLayoutToScrollToDuringTransition", (IMP)PS_ScrollTo);
    sDefScale = PS_Replace("SBDefaultImplementationsSwitcherModifier", "scaleForLayoutRole:inAppLayout:", (IMP)PS_DefScale);
    sDefFrame = PS_Replace("SBDefaultImplementationsSwitcherModifier", "frameForLayoutRole:inAppLayout:withBounds:", (IMP)PS_DefFrame);
    sAsyncEval = PS_Replace("SBMainSwitcherControllerCoordinator", "_evaluateAsynchronousRenderingEnablement", (IMP)PS_AsyncEval);
    BP_Log(@"p1sw: installed scroll=%d defscale=%d defframe=%d asynceval=%d", sScroll != NULL, sDefScale != NULL, sDefFrame != NULL, sAsyncEval != NULL);
}

#pragma clang diagnostic pop
