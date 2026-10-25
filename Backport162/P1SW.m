// P1SW.m : switcher modifier / coordinator leftovers of REVIEW-CORE-0.7.9 (specs/CORE-LEFTOVERS-0.7.9.md item 3): M4, M6, M8 (M5 is appended below by its own section).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Every body was decoded from the 16.2 disassembly and diffed against the 16.0 method.
// Switches (all default on; each replaced IMP checks its switch at call time and runs the saved 16.0 IMP when it is off):
//   p1_homescroll  SBHomeGestureToSwitcherSwitcherModifier -_appLayoutToScrollToDuringTransition  (M8)
//   p1_defroles    SBDefaultImplementationsSwitcherModifier -scaleForLayoutRole:inAppLayout: / -frameForLayoutRole:inAppLayout:withBounds:  (M4)
//   p1_asynceval   SBMainSwitcherControllerCoordinator -_evaluateAsynchronousRenderingEnablement is a no-op like 16.2  (M6)
//   p1_orient      the orientation family of M5 that does not need the 16.2 traits assistant (see the section below): SBLayoutState ...unknownAllowed:, SBSwitcherController coordinateSpaceForLayoutElement:layoutState: /
//                  sceneEntityFrameForWorkspaceEntity:inLayoutState: / _updateAppTransitionContext:withOrientationActuationContext:, SBApplicationSceneHandle _createApplicationSceneSettingsFromContext:entity:
// Logs: grep "p1sw:" in Backport162.log.

#import "G1BKit.h"
#import <dlfcn.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"


extern void P1_NoteMissing(id o, SEL x);
extern Ivar P1_IvarOf(id o, const char *name);
static inline BOOL PS_Resp(id o, SEL x) {
    if (!o) return NO;
    if ([o respondsToSelector:x]) return YES;
    P1_NoteMissing(o, x);
    return NO;
}
static id PS_S0(id o, const char *s) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((id (*)(id, SEL))objc_msgSend)(o, x) : nil; }
static id PS_S1(id o, const char *s, id a) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((id (*)(id, SEL, id))objc_msgSend)(o, x, a) : nil; }
static BOOL PS_B0(id o, const char *s) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, x) : NO; }
static BOOL PS_B1(id o, const char *s, id a) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((BOOL (*)(id, SEL, id))objc_msgSend)(o, x, a) : NO; }
static long long PS_L0(id o, const char *s) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((long long (*)(id, SEL))objc_msgSend)(o, x) : 0; }
static double PS_D0(id o, const char *s) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((double (*)(id, SEL))objc_msgSend)(o, x) : 0.0; }
static CGRect PS_R0(id o, const char *s) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, x) : CGRectZero; }
static CGPoint PS_P1(id o, const char *s, id a) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(o, x, a) : CGPointZero; }
static CGSize PS_Z1(id o, const char *s, id a) { SEL x = sel_registerName(s); return PS_Resp(o, x) ? ((CGSize (*)(id, SEL, id))objc_msgSend)(o, x, a) : CGSizeZero; }
static long long PS_IvarLL(id o, const char *name) {
    Ivar iv = P1_IvarOf(o, name);
    return iv ? *(long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : 0;
}
static id PS_Ivar(id o, const char *name) {
    Ivar iv = P1_IvarOf(o, name);
    return BP_ObjIvar(o, iv);
}
static CGPoint PS_IvarPoint(id o, const char *name) {
    Ivar iv = P1_IvarOf(o, name);
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
static IMP sCoordSpace, sSceneFrame, sUpdateCtx2, sSceneHandleForOrient, sLSOrientForElement, sCreateSettings;

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
    long long env = PS_L0(layout, "environment");               // 16.0 0x1c63df39c / 16.2 0x1c788a4d0: -environment is sent to the SBAppLayout (x19 = the layout argument), not to the modifier
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

// ---------------------------------------------------------------------------------------------- M5 orientation family (the part that does not need the 16.2 SBSwitcherTraitsAssistant)
// 16.2 SBLayoutState (0x1c766f7ac, 0x1c766f80c): -interfaceOrientationForLayoutElement:unknownAllowed: and -_interfaceOrientationForElementIdentifier:unknownAllowed: are new; the old
// -interfaceOrientationForElementIdentifier: is the `unknownAllowed:NO` case (0x1c766f804). Body: element unknown or its mapped orientation 0 -> unknownAllowed ? 0 : [[self class] _defaultInterfaceOrientation];
// a known element that is not in the orientation map is an assertion in both releases ("Layout state element is known but its orientation is not mapped.", not raised here: answers 0 and logs once).
static IMP sLSOrientForId;
static long long PS_LSOrient(id self, SEL _cmd, id ident, BOOL unknownAllowed) {
    id elem = PS_S1(self, "elementWithIdentifier:", ident);
    id map = PS_Ivar(self, "_interfaceOrientationByLayoutElementIdentifier");
    long long o = 0;
    if (elem && map) {
        id num = [map objectForKey:ident];
        if (!num) { static BOOL once; if (!once) { once = YES; BP_Log(@"p1sw: orient: layout state element %@ is known but its orientation is not mapped (16.0 / 16.2 raise an assertion here)", ident); } }
        else o = [num respondsToSelector:@selector(integerValue)] ? (long long)[num integerValue] : 0;
    }
    if (o == 0 && !unknownAllowed) o = ((long long (*)(id, SEL))objc_msgSend)((id)object_getClass(self), sel_registerName("_defaultInterfaceOrientation"));
    return o;
}
static long long PS_LSOrientForId(id self, SEL _cmd, id ident, BOOL unknownAllowed) { return PS_LSOrient(self, _cmd, ident, unknownAllowed); }
static long long PS_LSOrientForElem(id self, SEL _cmd, id element, BOOL unknownAllowed) {
    return PS_LSOrient(self, _cmd, PS_S0(element, "uniqueIdentifier"), unknownAllowed);
}

// SBApplicationSceneHandle -_createApplicationSceneSettingsFromContext:entity: (16.2 0x1c729d898, 16.0 0x1c5e2b338). The only orientation delta of the body is that the element lookup of the context's layout state
// is -interfaceOrientationForLayoutElement:unknownAllowed:YES (an element that is not in the layout state answers 0 -> the context / scene orientation is used, 16.0 answered the default orientation).
// (16.2 also raises an assertion for a frame of zero size / "frame (%@) isn't valid", not ported: a crash path, the 16.0 behaviour without it is kept.)
// 16.0 body kept; during the call the layout state of the context answers that one lookup (same layout state, the scene's element identifier) with the unknownAllowed:YES answer.
static __thread __unsafe_unretained id tOrientState;
static __thread __unsafe_unretained id tOrientId;
static id PS_CreateSettings(id self, SEL _cmd, id context, id entity) {
    if (!BP_OnName("p1_orient")) return ((id (*)(id, SEL, id, id))sCreateSettings)(self, _cmd, context, entity);
    id prevState = tOrientState, prevId = tOrientId;
    tOrientState = PS_S0(context, "layoutState");
    tOrientId = PS_S0(self, "sceneIdentifier");
    id r = ((id (*)(id, SEL, id, id))sCreateSettings)(self, _cmd, context, entity);
    tOrientState = prevState; tOrientId = prevId;
    return r;
}
static long long PS_LSForElement(id self, SEL _cmd, id element) {
    if (tOrientState && self == tOrientState && tOrientId && [PS_S0(element, "uniqueIdentifier") isEqual:tOrientId]) {
        tOrientState = nil;                                                              // consumed: only the lookup of this scene's element
        return PS_LSOrient(self, _cmd, PS_S0(element, "uniqueIdentifier"), YES);
    }
    return ((long long (*)(id, SEL, id))sLSOrientForElement)(self, _cmd, element);
}

// SBSwitcherController -coordinateSpaceForLayoutElement:layoutState: (16.2 0x1c7603a88, 16.0 0x1c617c1c4): with Stage Manager the orientation of the layout state ([layoutState interfaceOrientation]) replaces the per-element one.
static id PS_CoordSpace(id self, SEL _cmd, id element, id state) {
    if (!BP_OnName("p1_orient")) return ((id (*)(id, SEL, id, id))sCoordSpace)(self, _cmd, element, state);
    id window = PS_S0(self, "switcherWindow");
    id appLayout = PS_S0(state, "appLayout");
    SEL so = sel_registerName("interfaceOrientationForLayoutElement:");
    long long o = [state respondsToSelector:so] ? ((long long (*)(id, SEL, id))objc_msgSend)(state, so, element) : 0;
    if (PS_B0(self, "isChamoisWindowingUIEnabled")) o = PS_L0(state, "interfaceOrientation");
    long long role = PS_L0(element, "layoutRole");
    BOOL inset = PS_B0(appLayout, "isInsetForHomeAffordance");
    SEL rf = sel_registerName("referenceFrameForForInterfaceOrientation:layoutRole:appLayout:isInsetForHomeAffordance:");
    if (![self respondsToSelector:rf]) return ((id (*)(id, SEL, id, id))sCoordSpace)(self, _cmd, element, state);
    CGRect frame = ((CGRect (*)(id, SEL, long long, long long, id, BOOL))objc_msgSend)(self, rf, o, role, appLayout, inset);
    Class cs = NSClassFromString(@"SBSceneLayoutCoordinateSpace");
    SEL s1 = sel_registerName("coordinateSpaceForFrame:withinCoordinateSpace:"), s2 = sel_registerName("coordinateSpaceForInterfaceOrientation:withReferenceCoordinateSpace:inOrientation:");
    if (!cs || ![(id)cs respondsToSelector:s1] || ![(id)cs respondsToSelector:s2]) return ((id (*)(id, SEL, id, id))sCoordSpace)(self, _cmd, element, state);
    id space = ((id (*)(id, SEL, CGRect, id))objc_msgSend)((id)cs, s1, frame, window);
    return ((id (*)(id, SEL, long long, id, long long))objc_msgSend)((id)cs, s2, o, space, PS_L0(window, "interfaceOrientation"));
}

// SBSwitcherController -sceneEntityFrameForWorkspaceEntity:inLayoutState: (16.2 0x1c76073e4, 16.0 0x1c617ef24): with Stage Manager the scene's orientation for the reference frame is [layoutState interfaceOrientation]
// instead of -interfaceOrientationForSceneHandle: (the only use of that query in the body). (16.2 also logs an error when the result has a zero size; not ported, log only.)
static __thread __unsafe_unretained id tFrameSelf;
static __thread long long tFrameOrient;
static CGRect PS_SceneFrame(id self, SEL _cmd, id entity, id state) {
    typedef CGRect (*Orig)(id, SEL, id, id);
    if (!BP_OnName("p1_orient") || !PS_B0(self, "isChamoisWindowingUIEnabled")) return ((Orig)sSceneFrame)(self, _cmd, entity, state);
    id prevSelf = tFrameSelf; long long prevO = tFrameOrient;
    tFrameSelf = self; tFrameOrient = PS_L0(state, "interfaceOrientation");
    CGRect r = ((Orig)sSceneFrame)(self, _cmd, entity, state);
    tFrameSelf = prevSelf; tFrameOrient = prevO;
    return r;
}
static long long PS_SceneHandleOrient(id self, SEL _cmd, id handle) {
    if (tFrameSelf && tFrameSelf == self) { tFrameSelf = nil; return tFrameOrient; }       // consumed: first use inside sceneEntityFrameForWorkspaceEntity:inLayoutState:
    return ((long long (*)(id, SEL, id))sSceneHandleForOrient)(self, _cmd, handle);
}

// SBSwitcherController -_updateAppTransitionContext:withOrientationActuationContext: (16.2 0x1c76026a4, 16.0 0x1c617af88 = the 3 argument form with accountForSceneState:YES): 16.2 passes
// accountForSceneState = !isChamoisWindowingUIEnabled and its primary delegate argument (the 16.0 3 argument form reads the same ivar itself).
static void PS_UpdateCtx2(id self, SEL _cmd, id context, id actuation) {
    SEL three = sel_registerName("_updateAppTransitionContext:withOrientationActuationContext:accountForSceneState:");
    if (!BP_OnName("p1_orient") || ![self respondsToSelector:three]) { ((void (*)(id, SEL, id, id))sUpdateCtx2)(self, _cmd, context, actuation); return; }
    ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(self, three, context, actuation, !PS_B0(self, "isChamoisWindowingUIEnabled"));
}

static void PS_OrientSetup(void) {
    Class ls = NSClassFromString(@"SBLayoutState");
    if (ls) {
        if (!class_getInstanceMethod(ls, sel_registerName("interfaceOrientationForLayoutElement:unknownAllowed:")))
            class_addMethod(ls, sel_registerName("interfaceOrientationForLayoutElement:unknownAllowed:"), (IMP)PS_LSOrientForElem, "q28@0:8@16B24");
        if (!class_getInstanceMethod(ls, sel_registerName("_interfaceOrientationForElementIdentifier:unknownAllowed:")))
            class_addMethod(ls, sel_registerName("_interfaceOrientationForElementIdentifier:unknownAllowed:"), (IMP)PS_LSOrientForId, "q28@0:8@16B24");
    }
    sLSOrientForElement = PS_Replace("SBLayoutState", "interfaceOrientationForLayoutElement:", (IMP)PS_LSForElement);
    sCreateSettings = PS_Replace("SBApplicationSceneHandle", "_createApplicationSceneSettingsFromContext:entity:", (IMP)PS_CreateSettings);
    sCoordSpace = PS_Replace("SBSwitcherController", "coordinateSpaceForLayoutElement:layoutState:", (IMP)PS_CoordSpace);
    sSceneFrame = PS_Replace("SBSwitcherController", "sceneEntityFrameForWorkspaceEntity:inLayoutState:", (IMP)PS_SceneFrame);
    sSceneHandleForOrient = PS_Replace("SBSwitcherController", "interfaceOrientationForSceneHandle:", (IMP)PS_SceneHandleOrient);
    sUpdateCtx2 = PS_Replace("SBSwitcherController", "_updateAppTransitionContext:withOrientationActuationContext:", (IMP)PS_UpdateCtx2);
    BP_Log(@"p1sw: orient installed layoutstate=%d settings=%d coordspace=%d sceneframe=%d handleorient=%d updatectx=%d", sLSOrientForElement != NULL, sCreateSettings != NULL, sCoordSpace != NULL, sSceneFrame != NULL, sSceneHandleForOrient != NULL, sUpdateCtx2 != NULL);
}

void P1SW_Setup(void) {
    if (!BP_OnName("p1_sw")) return;
    sScroll = PS_Replace("SBHomeGestureToSwitcherSwitcherModifier", "_appLayoutToScrollToDuringTransition", (IMP)PS_ScrollTo);
    sDefScale = PS_Replace("SBDefaultImplementationsSwitcherModifier", "scaleForLayoutRole:inAppLayout:", (IMP)PS_DefScale);
    sDefFrame = PS_Replace("SBDefaultImplementationsSwitcherModifier", "frameForLayoutRole:inAppLayout:withBounds:", (IMP)PS_DefFrame);
    sAsyncEval = PS_Replace("SBMainSwitcherControllerCoordinator", "_evaluateAsynchronousRenderingEnablement", (IMP)PS_AsyncEval);
    PS_OrientSetup();
    BP_Log(@"p1sw: installed scroll=%d defscale=%d defframe=%d asynceval=%d", sScroll != NULL, sDefScale != NULL, sDefFrame != NULL, sAsyncEval != NULL);
}

#pragma clang diagnostic pop
