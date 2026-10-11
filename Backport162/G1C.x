// group1c-reconstruct.hooks.m
//
// DRAFT. Logos source (same conventions as group1b-modifiers.hooks.m, whose helper kit it uses). Reconstructs, as new run-time
// classes / whole-method replacements, the iPadOS 16.2 (20C65) Stage Manager pieces that group1b tagged NOT PORTABLE, for
// iPadOS 16.0 (20A8372) SpringBoard. Behaviour and every address are in group1c-reconstruct.md (item numbers in the comments).
//
// INTEGRATION
//   * (INTEGRATION: now its own translation unit; the helper kit is G1BKit.h and the G1B class globals are extern below.) It uses G1B_MakeClass, G1B_SUPER,
//     G1B_GET / G1B_SET, G1B_Send0/1/LL0/B0/B1/V1/VLL, G1B_Append, G1B_HasSuper, G1B_IvarOffset, G1B_NewUpdateLayoutResponse, gTransSuper,
//     and the event / response classes it builds (gFilteringCls, gOverrideIdsCls, gPulseCls, gInvalidateRespCls, ...).
//   * Call G1C_Setup() from the %ctor right after G1B_Setup() (and after the group 2 / 2b setup, see the SUMMARY install order).
//   * Compile with ARC, -Wall -Werror. Unused statics are covered by the pragmas below.
//   * Feature switch: F_G1C (switch file <jbroot>/tmp/Backport162.off.group1c); when it is not defined by the host it aliases F_G1B.
//   * "BP162 data model helpers" = the API of the parallel package group2b-reconstruct (see the md, section "Requirements on the data layer").
//     Every use is behind a G1C_DM_* wrapper that checks for the symbol at run time and degrades to the 16.0 absolute-geometry API.
//
// RULES followed: no hard-coded ivar offsets (ivar_getOffset by name, run-time ivars added with class_addIvar); every private call is
// guarded with respondsToSelector: / instancesRespondToSelector: / class_getInstanceMethod; nothing dereferences nil; %orig is on its own
// line; messages to `id` that could collide with Foundation selectors named `type` go through objc_msgSend casts.
//
// Tags in the comments: DONE or UNSURE:<what to check on a device>.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>
#import <unistd.h>
#import <math.h>
#import "BP.h"
#import "G1BKit.h"
#import "BPShared.h"

// INTEGRATION: interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
@interface SBFluidSwitcherGestureManager : NSObject @end
@interface SBFluidSwitcherViewController : UIViewController @end
@interface SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier : NSObject @end
@interface SBRevealContinuousExposeStripOverflowRootSwitcherModifier : NSObject @end
@interface SBContinuousExposeWindowDragModifierEvent : NSObject @end
@interface SBFluidSwitcherGestureWorkspaceTransaction : NSObject @end
@interface SBContinuousExposeRootSwitcherModifier : NSObject @end
@interface SBFullScreenContinuousExposeSwitcherModifier : NSObject @end
@interface SBItemResizeGestureSwitcherModifier : NSObject @end
// END INTEGRATION interfaces

extern Class gFilteringCls, gOverrideIdsCls, gOverrideIdsSuper, gGrabberRespCls, gOrientRespCls, gInvalidateRespCls, gF2SCls, gXBCls, gDndToAppCls;     // G1B.x

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

#define G1C_ON() BP_On(F_G1C)

// ---- glitch diagnostics (specs/AUDIT-STRIPGLITCH-0.6.6.md): every line starts with "GLITCH"; nothing is built unless logging is on ----
static NSString *G1C_DbgCls(id o) { return o ? NSStringFromClass(object_getClass(o)) : @"nil"; }
static NSString *G1C_DbgLayout(id l) {
    if (!l) return @"nil";
    id ident = [l respondsToSelector:NSSelectorFromString(@"continuousExposeIdentifier")] ? ((id (*)(id, SEL))objc_msgSend)(l, NSSelectorFromString(@"continuousExposeIdentifier")) : nil;
    Class alc = NSClassFromString(@"SBAppLayout");
    id homeL = (alc && [alc respondsToSelector:@selector(homeScreenAppLayout)]) ? ((id (*)(id, SEL))objc_msgSend)((id)alc, @selector(homeScreenAppLayout)) : nil;
    BOOL home = homeL && [l isEqual:homeL];
    return [NSString stringWithFormat:@"%@%@", home ? @"HOME:" : @"", [ident isKindOfClass:[NSString class]] ? ident : @"-"];
}
static NSString *G1C_DbgIds(id arr) {
    NSArray *a = [arr isKindOfClass:[NSArray class]] ? arr : ([arr respondsToSelector:@selector(array)] ? ((id (*)(id, SEL))objc_msgSend)(arr, @selector(array)) : nil);
    return a ? [NSString stringWithFormat:@"[%@]", [a componentsJoinedByString:@","]] : @"nil";
}

typedef struct { double x, y, w, h; } G1CRectRaw;      // layout-compatible with CGRect (used for the few places we pass rects through varargs-free casts)

// ---- small typed senders (all callers guard with respondsToSelector:) ----
static inline CGRect  G1C_SendRect0(id o, SEL s)                    { return ((CGRect (*)(id, SEL))objc_msgSend)(o, s); }
static inline CGPoint G1C_SendPoint0(id o, SEL s)                   { return ((CGPoint (*)(id, SEL))objc_msgSend)(o, s); }
static inline CGSize  G1C_SendSize0(id o, SEL s)                    { return ((CGSize (*)(id, SEL))objc_msgSend)(o, s); }
static inline double  G1C_SendD0(id o, SEL s)                       { return ((double (*)(id, SEL))objc_msgSend)(o, s); }
static inline id      G1C_Send2(id o, SEL s, id a, id b)            { return ((id (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b); }
static inline id      G1C_SendLL1(id o, SEL s, long long a)         { return ((id (*)(id, SEL, long long))objc_msgSend)(o, s, a); }
static inline BOOL    G1C_SendBLL1(id o, SEL s, long long a)        { return ((BOOL (*)(id, SEL, long long))objc_msgSend)(o, s, a); }
static inline void    G1C_SendVB(id o, SEL s, BOOL a)               { ((void (*)(id, SEL, BOOL))objc_msgSend)(o, s, a); }
static inline void    G1C_SendVD(id o, SEL s, double a)             { ((void (*)(id, SEL, double))objc_msgSend)(o, s, a); }
static inline id      G1C_Cls0(NSString *n, SEL s)                  { Class c = NSClassFromString(n); return (c && [c respondsToSelector:s]) ? G1B_Send0((id)c, s) : nil; }
static inline long long G1C_SendLLId(id o, SEL s, id a)          { return ((long long (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline BOOL    G1C_Resp(id o, SEL s)                         { return o && [o respondsToSelector:s]; }
static inline BOOL    G1C_IsKind(id o, NSString *clsName)           { Class c = NSClassFromString(clsName); return c && o && [o isKindOfClass:c]; }

// object ivar of a system object by name (never an offset); returns nil when the ivar is absent
static id G1C_IvarObj(id o, const char *name) {
    if (!o) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(o), name);
    if (!iv) return nil;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || enc[0] != '@') return nil;
    return object_getIvar(o, iv);
}
static BOOL G1C_IvarRaw(id o, const char *name, void *buf, size_t size, BOOL write) {
    if (!o) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(o), name);
    if (!iv) return NO;
    uint8_t *p = (uint8_t *)(__bridge void *)o + ivar_getOffset(iv);
    if (write) memcpy(p, buf, size); else memcpy(buf, p, size);
    return YES;
}
static BOOL   G1C_IvarBool(id o, const char *n)   { BOOL v = NO; G1C_IvarRaw(o, n, &v, sizeof v, NO); return v; }
static long long G1C_IvarLL(id o, const char *n)  { long long v = 0; G1C_IvarRaw(o, n, &v, sizeof v, NO); return v; }
static double G1C_IvarD(id o, const char *n)      { double v = 0; G1C_IvarRaw(o, n, &v, sizeof v, NO); return v; }
static CGRect G1C_IvarRect(id o, const char *n)   { CGRect v = CGRectZero; G1C_IvarRaw(o, n, &v, sizeof v, NO); return v; }
static CGPoint G1C_IvarPoint(id o, const char *n) { CGPoint v = CGPointZero; G1C_IvarRaw(o, n, &v, sizeof v, NO); return v; }
static void G1C_SetIvarBool(id o, const char *n, BOOL v)   { G1C_IvarRaw(o, n, &v, sizeof v, YES); }
static void G1C_SetIvarLL(id o, const char *n, long long v){ G1C_IvarRaw(o, n, &v, sizeof v, YES); }
static void G1C_SetIvarD(id o, const char *n, double v)    { G1C_IvarRaw(o, n, &v, sizeof v, YES); }
static void G1C_SetIvarPoint(id o, const char *n, CGPoint v){ G1C_IvarRaw(o, n, &v, sizeof v, YES); }

// +[SBSwitcherModifierEventResponse responseByAppendingResponse:toResponse:] (16.0 and 16.2 both have it); falls back to the C helper.
static id G1C_AppendResp(id newResp, id existing) {
    Class rc = NSClassFromString(@"SBSwitcherModifierEventResponse");
    SEL s = NSSelectorFromString(@"responseByAppendingResponse:toResponse:");
    if (rc && [rc respondsToSelector:s]) return G1C_Send2((id)rc, s, newResp, existing);
    return G1B_Append(newResp, existing);
}

// ============================================================================================================
// G1C_DM_*  thin wrappers over the data model (group2b "BP162 data model helpers")                                  DONE
// ============================================================================================================
// The 16.2 modifiers below use the attributedSize / normalizedCenter API of SBDisplayItemLayoutAttributes. group2b adds the 16.2 selectors as shims on the
// 16.0 class; each wrapper calls the 16.2 selector when present and otherwise degrades to the 16.0 API (absolute / normalized size and center, which the 16.0
// class accepts in both forms: components <= 1 are treated as fractions of the bounds, see -centerInBounds: 160 0x1c614b920).
// What is REQUIRED from the data layer is listed in the md, section "Requirements on the data layer" (DM1..DM8).
typedef struct { CGSize normalizedSize; CGRect referenceBounds; long long semanticSizeType; } G1CAttributedSize;     // SBDisplayItemAttributedSize

static inline id G1C_SendLL1x(id o, SEL s, long long a) { return ((id (*)(id, SEL, long long))objc_msgSend)(o, s, a); }

// DM1  -[SBDisplayItemLayoutAttributes sizeInBounds:defaultSize:screenEdgePadding:]   (162 0x1c75cf618)
static CGSize G1C_DM_SizeInBounds(id attrs, CGRect bounds, CGSize def, double pad) {
    SEL s162 = NSSelectorFromString(@"sizeInBounds:defaultSize:screenEdgePadding:");
    if (attrs && [attrs respondsToSelector:s162]) return ((CGSize (*)(id, SEL, CGRect, CGSize, double))objc_msgSend)(attrs, s162, bounds, def, pad);
    if (attrs && [attrs respondsToSelector:@selector(sizeInBounds:)]) return ((CGSize (*)(id, SEL, CGRect))objc_msgSend)(attrs, @selector(sizeInBounds:), bounds);
    return CGSizeZero;
}
// DM2  center in the given bounds (both builds)
static CGPoint G1C_DM_CenterInBounds(id attrs, CGRect bounds) {
    if (attrs && [attrs respondsToSelector:@selector(centerInBounds:)]) return ((CGPoint (*)(id, SEL, CGRect))objc_msgSend)(attrs, @selector(centerInBounds:), bounds);
    return CGPointZero;
}
// DM3  attributes with a new absolute center (the wrapper converts to the normalized form 16.2 stores)
static id G1C_DM_AttrsByModifyingCenter(id attrs, CGPoint centerAbs, CGRect bounds) {
    if (!attrs) return nil;
    Class ac = object_getClass(attrs);
    CGPoint n = centerAbs;
    SEL np = @selector(normalizedPointForPoint:inBounds:);
    if ([ac respondsToSelector:np]) n = ((CGPoint (*)(id, SEL, CGPoint, CGRect))objc_msgSend)((id)ac, np, centerAbs, bounds);
    SEL s162 = NSSelectorFromString(@"attributesByModifyingNormalizedCenter:");
    if ([attrs respondsToSelector:s162]) return ((id (*)(id, SEL, CGPoint))objc_msgSend)(attrs, s162, n);
    if ([attrs respondsToSelector:@selector(attributesByModifyingCenter:)]) return ((id (*)(id, SEL, CGPoint))objc_msgSend)(attrs, @selector(attributesByModifyingCenter:), n);
    return attrs;
}
// DM4  attributes with a new absolute size. 16.2: attributedSize = _SBDisplayItemAttributedSizeInfer(size, bounds, defaultSize, padding)
//      (162 0x1c75cedfc; semantic types: 3 = size equals bounds, 1 = full width, 2 = full height, 6/4/5 = default size / default width / default height,
//       9/7/8 = bounds inset by 2*padding in both/width/height, 0 = unspecified).
static G1CAttributedSize G1C_DM_InferAttributedSize(CGSize size, CGRect bounds, CGSize def, double pad) {
    G1CAttributedSize r;
    r.normalizedSize = CGSizeMake(bounds.size.width != 0 ? size.width / bounds.size.width : 0, bounds.size.height != 0 ? size.height / bounds.size.height : 0);
    r.referenceBounds = bounds;
    BOOL wEq = fabs(size.width - bounds.size.width) < 0.0001, hEq = fabs(size.height - bounds.size.height) < 0.0001;
    long long t = 0;
    if (wEq || hEq) t = wEq ? (hEq ? 3 : 1) : 2;
    else {
        BOOL dw = fabs(size.width - def.width) < 0.0001, dh = fabs(size.height - def.height) < 0.0001;
        if (dw || dh) t = dw ? (dh ? 6 : 4) : 5;
        else {
            BOOL pw = fabs(size.width - (bounds.size.width - 2 * pad)) < 0.0001, ph = fabs(size.height - (bounds.size.height - 2 * pad)) < 0.0001;
            t = pw ? (ph ? 9 : 7) : (ph ? 8 : 0);
        }
    }
    r.semanticSizeType = t;
    return r;
}
static id G1C_DM_AttrsByModifyingSize(id attrs, CGSize sizeAbs, CGRect bounds, CGSize def, double pad) {
    if (!attrs) return nil;
    SEL s162 = NSSelectorFromString(@"attributesByModifyingAttributedSize:");
    if ([attrs respondsToSelector:s162]) {
        G1CAttributedSize as = G1C_DM_InferAttributedSize(sizeAbs, bounds, def, pad);
        return ((id (*)(id, SEL, G1CAttributedSize))objc_msgSend)(attrs, s162, as);
    }
    Class ac = object_getClass(attrs);
    CGSize n = sizeAbs;
    SEL ns = @selector(normalizedSizeForSize:inBounds:);
    if ([ac respondsToSelector:ns]) n = ((CGSize (*)(id, SEL, CGSize, CGRect))objc_msgSend)((id)ac, ns, sizeAbs, bounds);
    if ([attrs respondsToSelector:@selector(attributesByModifyingSize:)]) return ((id (*)(id, SEL, CGSize))objc_msgSend)(attrs, @selector(attributesByModifyingSize:), n);
    return attrs;
}
// DM5  chamois layout attribute readers used by the modifiers (16.0 has all of them)
static CGSize G1C_DM_DefaultWindowSize(id chamoisAttrs) { return (chamoisAttrs && [chamoisAttrs respondsToSelector:@selector(defaultWindowSize)]) ? G1C_SendSize0(chamoisAttrs, @selector(defaultWindowSize)) : CGSizeZero; }
static double G1C_DM_ScreenEdgePadding(id chamoisAttrs) { return G1B_Dbl0(chamoisAttrs, @selector(screenEdgePadding)); }
// DM6  SBChamoisOverlappingModel extras (group2 A3): widthThresholdToHideStrip, stageArea, isItemCoveredByFullyOccludedPeekingItem:, compactedBoundingBox ...
static double G1C_DM_WidthThresholdToHideStrip(id model) { return G1B_Dbl0(model, NSSelectorFromString(@"widthThresholdToHideStrip")); }
static CGRect G1C_DM_StageArea(id model) { SEL s = NSSelectorFromString(@"stageArea"); return (model && [model respondsToSelector:s]) ? G1C_SendRect0(model, s) : CGRectZero; }

// ============================================================================================================
// 5a  SBGridSwipeUpGestureSwitcherModifier (16.2 adds delayCompletionUntilTransitionBegins) + SBGridSwipeUpGestureRootSwitcherModifier
//     + SBContinuousExposeToHomeSwitcherModifier (ported wrapper, derived from SwitcherDismissFix 0.3.0)           DONE
// ============================================================================================================
// 16.2 changes to SBGridSwipeUpGestureSwitcherModifier (diffed method by method, 160 0x1c64260d0.. vs 162 0x1c78d5e88..):
//   new ivar _delayCompletionUntilTransitionBegins (+0x98), new init 0x1c78d5e90 initWithGestureID:delayCompletionUntilTransitionBegins:
//   (initWithGestureID: becomes a thunk passing NO), new handleTransitionEvent: 0x1c78d6530, handleGestureEvent: 0x1c78d63b0 sets state 1 at
//   gesture end ONLY if !delay. Everything else is identical. 16.0 has none of it, so a run-time SUBCLASS carries the ivar.
static Class gGridGestCls, gGridGestBase, gGridGestGrand, gGridRootCls, gGridRootSuper, gCEToHomeCls, gCEToHomeSuper;
static ptrdiff_t gGridDelayOff = -1;

static id G1C_GridGest_Init(id self, SEL _cmd, id gestureID, BOOL delay) {
    id me = G1B_SUPER(id, gGridGestBase, self, @selector(initWithGestureID:), (struct objc_super *, SEL, id), gestureID);
    if (me && gGridDelayOff >= 0) *(BOOL *)((uint8_t *)(__bridge void *)me + gGridDelayOff) = delay;
    return me;
}
static BOOL G1C_GridGest_Delay(id self, SEL _cmd) { return gGridDelayOff >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)self + gGridDelayOff); }
static id G1C_GridGest_HandleGesture(id self, SEL _cmd, id event) {
    // 16.0 / 16.2 first call [super handleGestureEvent:] of SBGestureSwitcherModifier (the superref of SBGridSwipeUpGestureSwitcherModifier)
    id resp = G1B_SUPER(id, gGridGestGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!event || ![event respondsToSelector:@selector(phase)]) return resp;
    long long phase = G1B_SendLL0(event, @selector(phase));
    if ((phase == 2 || phase == 3) && [event respondsToSelector:@selector(translationInContainerView)])
        G1C_SetIvarPoint(self, "_translation", G1C_SendPoint0(event, @selector(translationInContainerView)));
    if (phase != 3) return resp;
    long long goesToSwitcher = [self respondsToSelector:@selector(finalResponseForGestureEvent:)]
        ? ((long long (*)(id, SEL, id))objc_msgSend)(self, @selector(finalResponseForGestureEvent:), event) : 0;
    Class reqC = NSClassFromString(@"SBMutableSwitcherTransitionRequest");
    Class perfC = NSClassFromString(@"SBPerformTransitionSwitcherEventResponse");
    SEL initP = @selector(initWithTransitionRequest:gestureInitiated:);
    if (reqC && perfC && [perfC instancesRespondToSelector:initP]) {
        id req = [[reqC alloc] init];
        if (goesToSwitcher) { if ([req respondsToSelector:@selector(setUnlockedEnvironmentMode:)]) G1B_SendVLL(req, @selector(setUnlockedEnvironmentMode:), 2); }
        else {
            id home = G1C_Cls0(@"SBAppLayout", @selector(homeScreenAppLayout));
            if (home && [req respondsToSelector:@selector(setAppLayout:)]) G1B_SendV1(req, @selector(setAppLayout:), home);
        }
        id perform = ((id (*)(id, SEL, id, BOOL))objc_msgSend)([perfC alloc], initP, req, YES);
        if (perform) resp = G1C_AppendResp(perform, resp);
    }
    if (BP_LogEnabled()) BP_Log(@"GLITCH grid swipe-up gesture ended: goesToSwitcher=%lld delay=%d translation=%@ -> requested %@", goesToSwitcher, G1C_GridGest_Delay(self, 0), NSStringFromCGPoint(G1C_IvarPoint(self, "_translation")), goesToSwitcher ? @"switcher (unlocked env mode 2)" : @"home app layout");
    if (!G1C_GridGest_Delay(self, 0)) G1B_SendVLL(self, @selector(setState:), 1);      // 16.0: always; 16.2: only when not delayed
    return resp;
}
static id G1C_GridGest_HandleTransition(id self, SEL _cmd, id event) {
    id resp = G1B_SUPER(id, gGridGestBase, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1C_GridGest_Delay(self, 0) && event && [event respondsToSelector:@selector(phase)] && G1B_SendLL0(event, @selector(phase)) >= 2) {
        if (BP_LogEnabled() && G1B_SendLL0(self, @selector(state)) != 1) BP_Log(@"GLITCH grid swipe-up gesture completes on transition phase %lld (modes %lld->%lld)", G1B_SendLL0(event, @selector(phase)), G1B_SendLL0(event, @selector(fromEnvironmentMode)), G1B_SendLL0(event, @selector(toEnvironmentMode)));
        G1B_SendVLL(self, @selector(setState:), 1);                                    // complete when the transition that the gesture requested has begun
    }
    return resp;
}

static BOOL G1C_BuildGridGesture(void) {
    Class base = NSClassFromString(@"SBGridSwipeUpGestureSwitcherModifier");
    if (!base || ![base instancesRespondToSelector:@selector(initWithGestureID:)] || ![base instancesRespondToSelector:@selector(finalResponseForGestureEvent:)]) return NO;
    gGridGestBase = base; gGridGestGrand = class_getSuperclass(base);
    const G1BIvar iv[] = { { "_bp_delayCompletionUntilTransitionBegins", sizeof(BOOL), 0, "B" } };
    const G1BMethod m[] = {
        { "initWithGestureID:delayCompletionUntilTransitionBegins:", (IMP)G1C_GridGest_Init,            "@28@0:8@16B24" },
        { "delayCompletionUntilTransitionBegins",                    (IMP)G1C_GridGest_Delay,           "B16@0:8" },
        { "handleGestureEvent:",                                     (IMP)G1C_GridGest_HandleGesture,   "@24@0:8@16" },
        { "handleTransitionEvent:",                                  (IMP)G1C_GridGest_HandleTransition,"@24@0:8@16" },
    };
    BOOL made = NO;
    gGridGestCls = G1B_MakeClass("BP162GridSwipeUpGestureSwitcherModifier", base, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gGridDelayOff = G1B_IvarOffset(gGridGestCls, "_bp_delayCompletionUntilTransitionBegins");
    return gGridGestCls != Nil && gGridDelayOff >= 0;
}

// ---- SBContinuousExposeToHomeSwitcherModifier (16.2 0x1c76..; ported once already by SwitcherDismissFix 0.3.0 under the name SDF...) ----
// init: super initWithTransitionID:; store direction + the Stage Manager modifier; child SBHomeToGridSwitcherModifier
//       initWithTransitionID:direction:(direction != 0) multitaskingModifier:[ce copy].
// _isEffectivelyHome = (isPreparingLayout && direction == 1) || (isUpdatingLayout && direction == 0).
// effectively home: anchorPointForIndex: (.5,.5); shouldUseAnchorPointToPinLayoutRolesToSpace: YES; perspectiveAngleForAppLayout: 0;
//   adjustedSpaceAccessoryViewFrame: unchanged; adjustedSpaceAccessoryViewAnchorPoint: (.5,.5); else [super].
// headerStyleForIndex:, shadowStyleForLayoutRole:inAppLayout:, homeScreenBackdropBlurType: answered by the Stage Manager modifier attached
//   temporarily (performTransactionWithTemporaryChildModifier:usingBlock:).
static ptrdiff_t gCEHDirOff = -1;
static char kCEHModifier;
static long long G1C_CEH_Dir(id s) { return gCEHDirOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)s + gCEHDirOff); }
static BOOL G1C_CEH_IsHome(id s) {
    long long d = G1C_CEH_Dir(s);
    BOOL prep = [s respondsToSelector:@selector(isPreparingLayout)] && G1B_SendB0(s, @selector(isPreparingLayout));
    BOOL upd = [s respondsToSelector:@selector(isUpdatingLayout)] && G1B_SendB0(s, @selector(isUpdatingLayout));
    return (prep && d == 1) || (upd && d == 0);
}
static id G1C_CEH_Init(id self, SEL _cmd, id tid, long long dir, id ce) {
    if (BP_LogEnabled()) BP_Log(@"GLITCH ToHome modifier init direction=%lld (0=switcher->home, 1=home->switcher) ce=%@", dir, G1C_DbgCls(ce));
    if (!ce) return nil;
    id me = G1B_SUPER(id, gCEToHomeSuper, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (!me || gCEHDirOff < 0) return nil;
    *(long long *)((uint8_t *)(__bridge void *)me + gCEHDirOff) = dir;
    G1B_SET(me, kCEHModifier, ce);
    Class grid = NSClassFromString(@"SBHomeToGridSwitcherModifier");
    SEL gi = @selector(initWithTransitionID:direction:multitaskingModifier:);
    if (!grid || ![grid instancesRespondToSelector:gi] || ![me respondsToSelector:@selector(addChildModifier:)]) return nil;
    id child = ((id (*)(id, SEL, id, long long, id))objc_msgSend)([grid alloc], gi, tid, dir != 0, [ce copy]);
    if (!child) return nil;
    G1B_SendV1(me, @selector(addChildModifier:), child);
    return me;
}
static BOOL gCEHAnchorLogged[2];
static CGPoint G1C_CEH_Anchor(id self, SEL _cmd, unsigned long long i) {
    if (G1C_CEH_IsHome(self)) {
        // 6.8 diagnostics: the 16.0 Stage Manager switcher answers anchorPointForIndex: itself (x = 0 for single windows), 16.2's does not (default .5): log once per effectively-home state
        if (i < 2 && !gCEHAnchorLogged[i] && BP_LogEnabled()) {
            gCEHAnchorLogged[i] = YES;
            id ce = G1B_GET(self, kCEHModifier);
            CGPoint own = (ce && [ce respondsToSelector:_cmd]) ? ((CGPoint (*)(id, SEL, unsigned long long))objc_msgSend)(ce, _cmd, i) : CGPointMake(-1, -1);
            BP_Log(@"GLITCH ToHome effectively home dir=%lld idx=%llu: anchor forced to (0.5,0.5), the switcher copy's own anchor would be (%.3f,%.3f)", G1C_CEH_Dir(self), i, own.x, own.y);
        }
        return CGPointMake(0.5, 0.5);
    }
    if (i < 2) gCEHAnchorLogged[i] = NO;
    return G1B_SUPER(CGPoint, gCEToHomeSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static BOOL G1C_CEH_PinSpace(id self, SEL _cmd, long long sp) {
    if (G1C_CEH_IsHome(self)) return YES;
    return G1B_SUPER(BOOL, gCEToHomeSuper, self, _cmd, (struct objc_super *, SEL, long long), sp);
}
static double G1C_CEH_Perspective(id self, SEL _cmd, id l) {
    if (G1C_CEH_IsHome(self)) return 0.0;
    return G1B_SUPER(double, gCEToHomeSuper, self, _cmd, (struct objc_super *, SEL, id), l);
}
static CGRect G1C_CEH_AccFrame(id self, SEL _cmd, CGRect f, id l) {
    if (G1C_CEH_IsHome(self)) return f;
    return G1B_SUPER(CGRect, gCEToHomeSuper, self, _cmd, (struct objc_super *, SEL, CGRect, id), f, l);
}
static CGPoint G1C_CEH_AccAnchor(id self, SEL _cmd, CGPoint p, id l) {
    if (G1C_CEH_IsHome(self)) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gCEToHomeSuper, self, _cmd, (struct objc_super *, SEL, CGPoint, id), p, l);
}
static long long G1C_CEH_AskCE(id self, void (^ask)(id ce, long long *r)) {
    id ce = G1B_GET(self, kCEHModifier);
    __block long long r = 0;
    if (!ce || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)]) return 0;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), ce, ^{ ask(ce, &r); });
    return r;
}
static long long G1C_CEH_Header(id self, SEL _cmd, unsigned long long i) {
    return G1C_CEH_AskCE(self, ^(id ce, long long *r) { *r = ((long long (*)(id, SEL, unsigned long long))objc_msgSend)(ce, _cmd, i); });
}
static long long G1C_CEH_Shadow(id self, SEL _cmd, long long role, id l) {
    return G1C_CEH_AskCE(self, ^(id ce, long long *r) { *r = ((long long (*)(id, SEL, long long, id))objc_msgSend)(ce, _cmd, role, l); });
}
static long long G1C_CEH_Blur(id self, SEL _cmd) {
    return G1C_CEH_AskCE(self, ^(id ce, long long *r) { *r = ((long long (*)(id, SEL))objc_msgSend)(ce, _cmd); });
}
static BOOL G1C_BuildCEToHome(void) {
    gCEToHomeSuper = NSClassFromString(@"SBTransitionSwitcherModifier");
    if (!gCEToHomeSuper || !NSClassFromString(@"SBHomeToGridSwitcherModifier")) return NO;
    const G1BIvar iv[] = { { "_direction", sizeof(long long), 3, "q" } };
    const G1BMethod m[] = {
        { "initWithTransitionID:direction:continuousExposeModifier:", (IMP)G1C_CEH_Init, "@40@0:8@16q24@32" },
        { "anchorPointForIndex:", (IMP)G1C_CEH_Anchor, "{CGPoint=dd}24@0:8Q16" },
        { "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)G1C_CEH_PinSpace, "B24@0:8q16" },
        { "perspectiveAngleForAppLayout:", (IMP)G1C_CEH_Perspective, "d24@0:8@16" },
        { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1C_CEH_AccFrame, "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48" },
        { "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (IMP)G1C_CEH_AccAnchor, "{CGPoint=dd}40@0:8{CGPoint=dd}16@32" },
        { "headerStyleForIndex:", (IMP)G1C_CEH_Header, "q24@0:8Q16" },
        { "shadowStyleForLayoutRole:inAppLayout:", (IMP)G1C_CEH_Shadow, "q32@0:8q16@24" },
        { "homeScreenBackdropBlurType", (IMP)G1C_CEH_Blur, "q16@0:8" },
    };
    BOOL made = NO;
    gCEToHomeCls = G1B_MakeClass("SBContinuousExposeToHomeSwitcherModifier", gCEToHomeSuper, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gCEHDirOff = G1B_IvarOffset(gCEToHomeCls, "_direction");
    return gCEToHomeCls != Nil && gCEHDirOff >= 0;
}

// ---- SBGridSwipeUpGestureRootSwitcherModifier (new in 16.2, gesture type 3) ----
static char kGridRootMulti;
static id G1C_GridRoot_Init(id self, SEL _cmd, long long mode, id multi) {
    if (!multi) return nil;                                                               // 16.2 asserts (SBGridSwipeUpGestureRootSwitcherModifier.m:0x1a)
    id me = G1B_SUPER(id, gGridRootSuper, self, @selector(initWithStartingEnvironmentMode:), (struct objc_super *, SEL, long long), mode);
    if (me) G1B_SET(me, kGridRootMulti, multi);                                           
    return me;
}
static long long G1C_GridRoot_Type(id self, SEL _cmd) { return 3; }
static id G1C_GridRoot_NewMulti(id self, SEL _cmd) { id m = G1B_GET(self, kGridRootMulti); return m ? [m copy] : nil; }
static id G1C_GridRoot_GestureChild(id self, SEL _cmd, id event, id activeTransition) {
    id gid = (event && [event respondsToSelector:@selector(gestureID)]) ? G1B_Send0(event, @selector(gestureID)) : nil;
    Class g = gGridGestCls ?: gGridGestBase;
    if (!g || !gid) return nil;
    SEL withDelay = @selector(initWithGestureID:delayCompletionUntilTransitionBegins:);
    if ([g instancesRespondToSelector:withDelay]) return ((id (*)(id, SEL, id, BOOL))objc_msgSend)([g alloc], withDelay, gid, YES);
    return ((id (*)(id, SEL, id))objc_msgSend)([g alloc], @selector(initWithGestureID:), gid);
}
static id G1C_GridRoot_TransitionChild(id self, SEL _cmd, id event, id activeGesture) {
    if (!event || ![event respondsToSelector:@selector(fromEnvironmentMode)]) return nil;
    if (G1B_SendLL0(event, @selector(fromEnvironmentMode)) != 2 || G1B_SendLL0(event, @selector(toEnvironmentMode)) != 1) return nil;
    Class ceC = NSClassFromString(@"SBAppSwitcherContinuousExposeSwitcherModifier");
    id multi = G1B_Send0(self, @selector(_newMultitaskingModifier));
    id ce = (ceC && multi && [multi isKindOfClass:ceC]) ? multi : nil;                    // _SBSafeCast
    SEL ini = @selector(initWithTransitionID:direction:continuousExposeModifier:);
    if (!ce || !gCEToHomeCls || ![gCEToHomeCls instancesRespondToSelector:ini]) return nil;
    if (BP_LogEnabled()) BP_Log(@"GLITCH grid root builds ToHome (gesture 2->1) with multitasking modifier %@", G1C_DbgCls(ce));
    return ((id (*)(id, SEL, id, long long, id))objc_msgSend)([gCEToHomeCls alloc], ini, G1B_Send0(event, @selector(transitionID)), 0, ce);
}
static id G1C_GestureRoot_GestureModifier(id self, SEL _cmd) {      // 16.2 renamed _gestureModifier -> gestureModifier (property)
    return [self respondsToSelector:@selector(_gestureModifier)] ? G1B_Send0(self, @selector(_gestureModifier)) : nil;
}
static BOOL G1C_BuildGridRoot(void) {
    Class sup = NSClassFromString(@"SBGestureRootSwitcherModifier");
    if (!sup || !gGridGestBase) return NO;
    gGridRootSuper = sup;
    if (!class_getInstanceMethod(sup, @selector(gestureModifier)) && class_getInstanceMethod(sup, @selector(_gestureModifier)))
        class_addMethod(sup, @selector(gestureModifier), (IMP)G1C_GestureRoot_GestureModifier, "@16@0:8");
    const G1BMethod m[] = {
        { "initWithStartingEnvironmentMode:multitaskingModifier:", (IMP)G1C_GridRoot_Init, "@32@0:8q16@24" },
        { "gestureType", (IMP)G1C_GridRoot_Type, "q16@0:8" },
        { "_newMultitaskingModifier", (IMP)G1C_GridRoot_NewMulti, "@16@0:8" },
        { "gestureChildModifierForGestureEvent:activeTransitionModifier:", (IMP)G1C_GridRoot_GestureChild, "@32@0:8@16@24" },
        { "transitionChildModifierForMainTransitionEvent:activeGestureModifier:", (IMP)G1C_GridRoot_TransitionChild, "@32@0:8@16@24" },
    };
    gGridRootCls = G1B_MakeClass("SBGridSwipeUpGestureRootSwitcherModifier", sup, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
    return gGridRootCls != Nil;
}
// Factory used by the Root's gestureModifierForGestureEvent: (item 2, gesture type 3).
static id G1C_NewGridSwipeUpRoot(long long mode, id multitaskingModifier) {
    SEL ini = @selector(initWithStartingEnvironmentMode:multitaskingModifier:);
    if (!gGridRootCls || !multitaskingModifier || ![gGridRootCls instancesRespondToSelector:ini]) return nil;
    return ((id (*)(id, SEL, long long, id))objc_msgSend)([gGridRootCls alloc], ini, mode, multitaskingModifier);
}

// ============================================================================================================
// 5b  Gesture workspace transactions: base-class API change + 16.2 class names                                 DONE
// ============================================================================================================
// 16.2: the gesture manager no longer tail-calls  -[txn updateGestureWithTransitionRequest:] / -[txn completeGestureWithTransitionRequest:]
// (16.0 SBFluidSwitcherGestureManager 0x1c643fb98 / 0x1c643fba0 are bare `b objc_msgSend$...` thunks). 16.2's manager methods
// handleTransitionRequestForGestureUpdate: (0x1c78f17f0) / ...Complete: (0x1c78f17fc) send
//   [txn handleTransitionRequestForGestureUpdate:req fromGestureManager:self]        (0x1c78f17f8)
//   [txn handleTransitionRequestForGestureComplete:req fromGestureManager:self]      (0x1c78f1870; before it, for Complete: if [[req appLayout] isEqual:[SBAppLayout homeScreenAppLayout]]
//                                                                                    the manager calls its own _clearSystemApertureZStackPolicyAssistantSuppression)
// and the base transaction (0x1c74b0490 / 0x1c74afba4) uses the manager to find the target SBSwitcherController of the request
// (_workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel:, _switcherControllerForWorkspaceTransitionRequest:, per-switcher
// layout-state maps). The two Stage Manager subclasses only override the entry points: Reveal sets _completedGestureWithTransitionRequest before [super].
// Port: (a) the 16.2 entry points exist on the 16.0 base class and forward to the 16.0 methods (the 16.0 subclass override
// completeGestureWithTransitionRequest: then still runs, so the flag logic of the Reveal transaction is preserved), (b) the 16.2 class names are
// run-time subclasses of the 16.0 classes (gesture type 0xb / 0xc), (c) the manager's class mapping may return them.
static Class gStripRevealTxnCls, gStripOverflowTxnCls;
static __thread int gTxnFwdDepth;
static void G1C_Txn_Update(id self, SEL _cmd, id req, id mgr) {
    if (gTxnFwdDepth > 0 || !G1C_ON() || ![self respondsToSelector:@selector(updateGestureWithTransitionRequest:)]) return;
    gTxnFwdDepth++;
    G1B_SendV1(self, @selector(updateGestureWithTransitionRequest:), req);
    gTxnFwdDepth--;
}
static void G1C_Txn_Complete(id self, SEL _cmd, id req, id mgr) {
    if (gTxnFwdDepth > 0 || !G1C_ON() || ![self respondsToSelector:@selector(completeGestureWithTransitionRequest:)]) return;
    gTxnFwdDepth++;
    G1B_SendV1(self, @selector(completeGestureWithTransitionRequest:), req);
    gTxnFwdDepth--;
}
static void G1C_BuildTransactions(void) {
    Class base = NSClassFromString(@"SBFluidSwitcherGestureWorkspaceTransaction");
    if (base) {
        if (!class_getInstanceMethod(base, @selector(handleTransitionRequestForGestureUpdate:fromGestureManager:)))
            class_addMethod(base, @selector(handleTransitionRequestForGestureUpdate:fromGestureManager:), (IMP)G1C_Txn_Update, "v32@0:8@16@24");
        if (!class_getInstanceMethod(base, @selector(handleTransitionRequestForGestureComplete:fromGestureManager:)))
            class_addMethod(base, @selector(handleTransitionRequestForGestureComplete:fromGestureManager:), (IMP)G1C_Txn_Complete, "v32@0:8@16@24");
    }
    Class rv = NSClassFromString(@"SBRevealContinuousExposeStripsGestureWorkspaceTransaction");
    Class of = NSClassFromString(@"SBRevealContinuousExposeStripOverflowGestureWorkspaceTransaction");
    if (rv) gStripRevealTxnCls = G1B_MakeClass("SBContinuousExposeStripRevealGestureWorkspaceTransaction", rv, NULL, 0, NULL, 0, NULL, NULL);
    if (of) gStripOverflowTxnCls = G1B_MakeClass("SBContinuousExposeStripOverflowGestureWorkspaceTransaction", of, NULL, 0, NULL, 0, NULL, NULL);
}
%group G1C_Txn
%hook SBFluidSwitcherGestureManager
- (Class)_fluidSwitcherGestureTransactionClassForGestureType:(long long)type {
    Class c = %orig;
    if (!G1C_ON() || !c) return c;
    // keep the 16.0 behaviour unless the alias exists; the alias IS-A the 16.0 class, so every 16.0 check still holds
    if (type == 0xb && gStripRevealTxnCls && c == NSClassFromString(@"SBRevealContinuousExposeStripsGestureWorkspaceTransaction")) return gStripRevealTxnCls;
    if (type == 0xc && gStripOverflowTxnCls && c == NSClassFromString(@"SBRevealContinuousExposeStripOverflowGestureWorkspaceTransaction")) return gStripOverflowTxnCls;
    return c;
}
%end
%end

// ============================================================================================================
// 5c  Continuous Expose identifier pipeline: ids-changed event (2-list form), SBContinuousExposeIdentifierSlideModifier (16.2 form),
//     SBOverrideContinuousExposeIdentifiersSwitcherModifier (upgraded to the two lists), the VC update method.      DONE
// ============================================================================================================
// ---- helpers -------------------------------------------------------------------------------------------
static id G1C_NewTimerResponse(double delay, NSString *reason) {
    Class tc = NSClassFromString(@"SBTimerEventSwitcherEventResponse");
    SEL ti = @selector(initWithDelay:validator:reason:);
    if (!tc || ![tc instancesRespondToSelector:ti]) return nil;
    return ((id (*)(id, SEL, double, id, id))objc_msgSend)([tc alloc], ti, delay, nil, reason);
}
static NSArray *G1C_AsArray(id o) {
    if ([o isKindOfClass:[NSArray class]]) return o;
    if ([o isKindOfClass:[NSOrderedSet class]]) return [(NSOrderedSet *)o array];
    if ([o isKindOfClass:[NSSet class]]) return [(NSSet *)o allObjects];
    return @[];
}

// ---- the event (type 35): 16.2 init / getters on top of the 16.0 class (so every 16.0 reader keeps working) --------------------------
// 16.2 0x1c76f4a58: ivars _animated +0x18, _previousContinuousExposeIdentifiersInSwitcher +0x20, ...InStrip +0x28, _transitioningFromAppLayout +0x30,
// _transitioningToAppLayout +0x38; NSAssert on the two lists (lines 0x12, 0x13). 16.0 0x1c625d8f4 has ONE list + generationCount.
static Class gIdsEventCls, gIdsEventBase;
static char kIdsPrevSwitcher, kIdsPrevStrip, kIdsAnimated, kIdsGen;
static id G1C_IdsEv_Init(id self, SEL _cmd, NSArray *prevSw, NSArray *prevStrip, id from, id to, BOOL animated) {
    if (!prevSw || !prevStrip) return nil;
    NSOrderedSet *os = [NSOrderedSet orderedSetWithArray:prevSw];
    SEL oldInit = @selector(initWithPreviousContinuousExposeIdentifiers:transitioningFromAppLayout:transitioningToAppLayout:generationCount:);
    id me = G1B_SUPER(id, gIdsEventBase, self, oldInit, (struct objc_super *, SEL, id, id, id, unsigned long long), os, from, to, 0ULL);
    if (!me) return nil;
    G1B_SET(me, kIdsPrevSwitcher, [prevSw copy]);
    G1B_SET(me, kIdsPrevStrip, [prevStrip copy]);
    G1B_SET(me, kIdsAnimated, @(animated));
    return me;
}
static id G1C_IdsEv_PrevSw(id self, SEL _cmd) { return G1B_GET(self, kIdsPrevSwitcher) ?: @[]; }
static id G1C_IdsEv_PrevStrip(id self, SEL _cmd) { return G1B_GET(self, kIdsPrevStrip) ?: @[]; }
static BOOL G1C_IdsEv_Animated(id self, SEL _cmd) { return [G1B_GET(self, kIdsAnimated) boolValue]; }
static unsigned long long G1C_IdsEv_Gen(id self, SEL _cmd) { return [G1B_GET(self, kIdsGen) unsignedLongLongValue]; }
static void G1C_IdsEv_SetGen(id self, SEL _cmd, unsigned long long g) { G1B_SET(self, kIdsGen, @(g)); }
// copy-family IMP: must return +1 (ARC does not know that for a plain C function; the missing retain over-released the event, crash in autorelease pool pop)
static __attribute__((ns_returns_retained)) id G1C_IdsEv_Copy(id self, SEL _cmd, NSZone *z) {
    id from = G1B_Send0(self, @selector(transitioningFromAppLayout)), to = G1B_Send0(self, @selector(transitioningToAppLayout));
    return ((id (*)(id, SEL, id, id, id, id, BOOL))objc_msgSend)([object_getClass(self) alloc],
        @selector(initWithPreviousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:transitioningFromAppLayout:transitioningToAppLayout:animated:),
        G1C_IdsEv_PrevSw(self, 0), G1C_IdsEv_PrevStrip(self, 0), from, to, G1C_IdsEv_Animated(self, 0));
}
static BOOL G1C_BuildIdsEvent(void) {
    Class base = NSClassFromString(@"SBContinuousExposeIdentifiersChangedModifierEvent");
    SEL oldInit = @selector(initWithPreviousContinuousExposeIdentifiers:transitioningFromAppLayout:transitioningToAppLayout:generationCount:);
    if (!base || ![base instancesRespondToSelector:oldInit]) return NO;
    gIdsEventBase = base;
    const G1BMethod m[] = {
        { "initWithPreviousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:transitioningFromAppLayout:transitioningToAppLayout:animated:", (IMP)G1C_IdsEv_Init, "@52@0:8@16@24@32@40B48" },
        { "previousContinuousExposeIdentifiersInSwitcher", (IMP)G1C_IdsEv_PrevSw, "@16@0:8" },
        { "previousContinuousExposeIdentifiersInStrip", (IMP)G1C_IdsEv_PrevStrip, "@16@0:8" },
        { "isAnimated", (IMP)G1C_IdsEv_Animated, "B16@0:8" },
        { "animated", (IMP)G1C_IdsEv_Animated, "B16@0:8" },
        { "generationCount", (IMP)G1C_IdsEv_Gen, "Q16@0:8" },          // 16.0 reader compat (value = the 16.2 counter after the bump)
        { "setBPGenerationCount:", (IMP)G1C_IdsEv_SetGen, "v24@0:8Q16" },
        { "copyWithZone:", (IMP)G1C_IdsEv_Copy, "@24@0:8^{_NSZone=}16" },
    };
    gIdsEventCls = G1B_MakeClass("BP162ContinuousExposeIdentifiersChangedModifierEvent", base, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
    return gIdsEventCls != Nil;
}
// Plain 16.0 events (posted by a 16.0 code path that we do not replace) get the 16.2 getters too: lists from the old single list, isAnimated YES (16.0 posts only animated).
static BOOL G1C_Ev16_IsAnimated(id self, SEL _cmd) { return YES; }
static id G1C_Ev16_PrevSw(id self, SEL _cmd) { return G1C_AsArray(G1B_Send0(self, @selector(previousContinuousExposeIdentifiers))); }
static id G1C_Ev16_PrevStrip(id self, SEL _cmd) { return G1C_AsArray(G1B_Send0(self, @selector(previousContinuousExposeIdentifiers))); }
static void G1C_InstallEvent16Compat(void) {
    Class b = NSClassFromString(@"SBContinuousExposeIdentifiersChangedModifierEvent");
    if (!b) return;
    if (!class_getInstanceMethod(b, @selector(isAnimated))) class_addMethod(b, @selector(isAnimated), (IMP)G1C_Ev16_IsAnimated, "B16@0:8");
    if (!class_getInstanceMethod(b, @selector(previousContinuousExposeIdentifiersInSwitcher))) class_addMethod(b, @selector(previousContinuousExposeIdentifiersInSwitcher), (IMP)G1C_Ev16_PrevSw, "@16@0:8");
    if (!class_getInstanceMethod(b, @selector(previousContinuousExposeIdentifiersInStrip))) class_addMethod(b, @selector(previousContinuousExposeIdentifiersInStrip), (IMP)G1C_Ev16_PrevStrip, "@16@0:8");
}

// ---- SBOverrideContinuousExposeIdentifiersSwitcherModifier: upgrade of the group1b class to the two-list contexts -------------------------------
// 16.2: 0x1c798bda8 continuousExposeIdentifiersInStrip = override ?: [super ...]; 0x1c798bd44 ...InSwitcher likewise. Only meaningful when the
// extended context protocol (group2 section 0) is active; the methods are added to the class created by G1B_BuildOverrideIds BEFORE its first message.
static id G1C_OvrIds_InSwitcher(id self, SEL _cmd) {
    id o = G1B_Send0(self, @selector(overrideContinuousExposeIdentifiersInSwitcher));
    if (o) return o;
    return G1B_HasSuper(gOverrideIdsSuper, _cmd) ? G1B_SUPER(id, gOverrideIdsSuper, self, _cmd, (struct objc_super *, SEL)) : nil;
}
static id G1C_OvrIds_InStrip(id self, SEL _cmd) {
    id o = G1B_Send0(self, @selector(overrideContinuousExposeIdentifiersInStrip));
    if (o) return o;
    return G1B_HasSuper(gOverrideIdsSuper, _cmd) ? G1B_SUPER(id, gOverrideIdsSuper, self, _cmd, (struct objc_super *, SEL)) : nil;
}
// 16.0 consumers of -continuousExposeIdentifiers expect an NSOrderedSet; the group1b IMP returned the stored object unchanged.
static id G1C_OvrIds_Legacy(id self, SEL _cmd) {
    id o = G1B_Send0(self, @selector(overrideContinuousExposeIdentifiersInSwitcher));
    if (!o) return G1B_HasSuper(gOverrideIdsSuper, _cmd) ? G1B_SUPER(id, gOverrideIdsSuper, self, _cmd, (struct objc_super *, SEL)) : nil;
    if ([o isKindOfClass:[NSOrderedSet class]]) return o;
    return [NSOrderedSet orderedSetWithArray:G1C_AsArray(o)];
}
static void G1C_UpgradeOverrideIds(void) {
    if (!gOverrideIdsCls || !gOverrideIdsSuper) return;
    SEL sw = sel_registerName("continuousExposeIdentifiersInSwitcher"), strip = sel_registerName("continuousExposeIdentifiersInStrip");
    // the 2-list selectors only get a chain trampoline when the extended protocol is active; adding the IMP is harmless otherwise
    if (!class_getInstanceMethod(gOverrideIdsCls, sw)) class_addMethod(gOverrideIdsCls, sw, (IMP)G1C_OvrIds_InSwitcher, "@16@0:8");
    if (!class_getInstanceMethod(gOverrideIdsCls, strip)) class_addMethod(gOverrideIdsCls, strip, (IMP)G1C_OvrIds_InStrip, "@16@0:8");
    Method legacy = class_getInstanceMethod(gOverrideIdsCls, @selector(continuousExposeIdentifiers));
    if (legacy) method_setImplementation(legacy, (IMP)G1C_OvrIds_Legacy);
}

// ---- SBContinuousExposeIdentifierSlideModifier (16.2 form; the 16.0 class stays for 16.0 creators) ------------------------------
// Direction: 0 = group added (slides in from the strip edge), 1 = group removed (slides out from its previous slot).
// 16.2 ivars: _isWaitingToPrepareLayout +0x60, _isWaitingToBeginAnimation +0x61, _uniqueAnimationIdentifier +0x68, _continuousExposeIdentifier +0x70,
// _previousContinuousExposeIdentifiersInSwitcher +0x78, ...InStrip +0x80, _direction +0x88. Addresses: init 0x1c78701f0, frameForIndex: 0x1c7870404,
// anchorPointForIndex: 0x1c78706ac, scaleForIndex: 0x1c78708c8, adjustedSpaceAccessoryViewFrame:forAppLayout: 0x1c7870ad0, animationAttributesForLayoutElement:
// 0x1c7870da4, handleContinuousExposeIdentifiersChangedEvent: 0x1c7870e9c, handleTimerEvent: 0x1c7871040, _beginAnimation 0x1c78711b4, reasons 0x1c78712c4/0x1c7871308,
// _performBlockWithIdentifiersInSwitcher:identifiersInStrip:block: 0x1c787134c.
static Class gSlideCls, gSlideSuper;
static ptrdiff_t gSlPrepOff = -1, gSlBeginOff = -1, gSlDirOff = -1;
static char kSlIdent, kSlPrevSw, kSlPrevStrip, kSlUid;
static BOOL G1C_Sl_Bool(id s, ptrdiff_t off) { return off >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)s + off); }
static void G1C_Sl_SetBool(id s, ptrdiff_t off, BOOL v) { if (off >= 0) *(BOOL *)((uint8_t *)(__bridge void *)s + off) = v; }
static unsigned long long G1C_Sl_Dir(id s) { return gSlDirOff < 0 ? 0 : *(unsigned long long *)((uint8_t *)(__bridge void *)s + gSlDirOff); }

static id G1C_Sl_Init(id self, SEL _cmd, NSString *ident, NSArray *prevSw, NSArray *prevStrip, unsigned long long dir) {
    if (!ident || !prevSw || !prevStrip) return nil;                      // 16.2 NSAssert (SBContinuousExposeIdentifierSlideModifier.m lines 0x20..0x22)
    id me = G1B_SUPER(id, gSlideSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me || gSlDirOff < 0) return nil;
    G1B_SET(me, kSlIdent, [ident copy]);
    G1B_SET(me, kSlPrevSw, [prevSw copy]);
    G1B_SET(me, kSlPrevStrip, [prevStrip copy]);
    *(unsigned long long *)((uint8_t *)(__bridge void *)me + gSlDirOff) = dir;
    G1B_SET(me, kSlUid, [[NSUUID UUID] UUIDString]);
    return me;
}
static id G1C_Sl_Ident(id self, SEL _cmd) { return G1B_GET(self, kSlIdent); }
static id G1C_Sl_PrevSw(id self, SEL _cmd) { return G1B_GET(self, kSlPrevSw); }
static id G1C_Sl_PrevStrip(id self, SEL _cmd) { return G1B_GET(self, kSlPrevStrip); }
static unsigned long long G1C_Sl_DirGetter(id self, SEL _cmd) { return G1C_Sl_Dir(self); }
static NSString *G1C_Sl_PrepReason(id self, SEL _cmd) { return [NSString stringWithFormat:@"%@-WaitingToPrepareLayout", G1B_GET(self, kSlUid)]; }
static NSString *G1C_Sl_AnimReason(id self, SEL _cmd) { return [NSString stringWithFormat:@"%@-WaitingToAnimate", G1B_GET(self, kSlUid)]; }

static void G1C_Sl_Perform(id self, SEL _cmd, NSArray *sw, NSArray *strip, void (^block)(void)) {
    SEL oi = @selector(initWithContinuousExposeIdentifiersInSwitcher:continuousExposeIdentifiersInStrip:);
    if (!gOverrideIdsCls || !block || ![gOverrideIdsCls instancesRespondToSelector:oi] || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)]) { if (block) block(); return; }
    id ovr = ((id (*)(id, SEL, id, id))objc_msgSend)([gOverrideIdsCls alloc], oi, sw, strip);
    if (!ovr) { block(); return; }
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), ovr, block);
}
static BOOL G1C_Sl_IsMine(id self, id layout) {
    NSString *mine = G1B_GET(self, kSlIdent);
    id cid = (layout && [layout respondsToSelector:@selector(continuousExposeIdentifier)]) ? G1B_Send0(layout, @selector(continuousExposeIdentifier)) : nil;
    return [cid isKindOfClass:[NSString class]] && [cid isEqualToString:mine];
}
static id G1C_Sl_LayoutAtIndex(id self, unsigned long long i) {
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    return i < a.count ? a[i] : nil;
}
// the x of the off-screen slot (frameForIndex: and adjustedSpaceAccessoryViewFrame: share it): LTR -(strip+pad) - w/2 ; RTL maxX + pad + strip - w/2
static double G1C_Sl_OffscreenX(id self, double width) {
    id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    double strip = G1B_Dbl0(attrs, @selector(stripWidth)), pad = G1B_Dbl0(attrs, @selector(screenEdgePadding));
    BOOL rtl = [self respondsToSelector:@selector(isRTLEnabled)] && G1B_SendB0(self, @selector(isRTLEnabled));
    double base;
    if (rtl) { CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds)); base = pad + (cb.origin.x + cb.size.width) + strip; }
    else base = -(strip + pad);
    return base + (-0.5 * width);
}
// mode: 0 = untouched, 1 = group still has to be placed at the off-screen slot (adding), 2 = group animates from its previous slot (removing)
static int G1C_Sl_Mode(id self, id layout) {
    if (!G1C_Sl_IsMine(self, layout)) return 0;
    if (G1C_Sl_Bool(self, gSlPrepOff) && G1C_Sl_Dir(self) == 0) return 1;
    if (G1C_Sl_Bool(self, gSlBeginOff) && G1C_Sl_Dir(self) == 1) return 2;
    return 0;
}
static char kSlLogMode;
static CGRect G1C_Sl_Frame(id self, SEL _cmd, unsigned long long i) {
    CGRect r = G1B_SUPER(CGRect, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    int mode = G1C_Sl_Mode(self, G1C_Sl_LayoutAtIndex(self, i));
    if (mode != 0 && BP_LogEnabled()) {
        NSNumber *seen = G1B_GET(self, kSlLogMode);
        if (!seen || seen.intValue != mode) {
            G1B_SET(self, kSlLogMode, @(mode));
            BP_Log(@"GLITCH slide frame ident=%@ mode=%d (1=off-screen start, 2=from previous slot) index=%llu super frame=%@", G1B_GET(self, kSlIdent), mode, i, NSStringFromCGRect(r));
        }
    }
    if (mode == 1) { r.origin.x = G1C_Sl_OffscreenX(self, r.size.width); return r; }
    if (mode == 2) {
        __block CGRect pr = r;
        G1C_Sl_Perform(self, _cmd, G1B_GET(self, kSlPrevSw), G1B_GET(self, kSlPrevStrip), ^{
            pr = G1B_SUPER(CGRect, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
        });
        return pr;
    }
    return r;
}
static CGPoint G1C_Sl_Anchor(id self, SEL _cmd, unsigned long long i) {
    CGPoint p = G1B_SUPER(CGPoint, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    if (G1C_Sl_Mode(self, G1C_Sl_LayoutAtIndex(self, i)) == 2) {
        __block CGPoint pp = p;
        G1C_Sl_Perform(self, _cmd, G1B_GET(self, kSlPrevSw), G1B_GET(self, kSlPrevStrip), ^{
            pp = G1B_SUPER(CGPoint, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
        });
        return pp;
    }
    return p;
}
static double G1C_Sl_Scale(id self, SEL _cmd, unsigned long long i) {
    double s = G1B_SUPER(double, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    if (G1C_Sl_Mode(self, G1C_Sl_LayoutAtIndex(self, i)) == 2) {
        __block double ps = s;
        G1C_Sl_Perform(self, _cmd, G1B_GET(self, kSlPrevSw), G1B_GET(self, kSlPrevStrip), ^{
            ps = G1B_SUPER(double, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
        });
        return ps;
    }
    return s;
}
static CGRect G1C_Sl_AccFrame(id self, SEL _cmd, CGRect f, id layout) {
    CGRect r = G1B_SUPER(CGRect, gSlideSuper, self, _cmd, (struct objc_super *, SEL, CGRect, id), f, layout);
    int mode = G1C_Sl_Mode(self, layout);
    if (mode == 1) { r.origin.x = G1C_Sl_OffscreenX(self, r.size.width); return r; }
    if (mode == 2) {
        __block CGRect pr = r;
        G1C_Sl_Perform(self, _cmd, G1B_GET(self, kSlPrevSw), G1B_GET(self, kSlPrevStrip), ^{
            pr = G1B_SUPER(CGRect, gSlideSuper, self, _cmd, (struct objc_super *, SEL, CGRect, id), f, layout);
        });
        return pr;
    }
    return r;
}
static id G1C_Sl_AnimAttrs(id self, SEL _cmd, id element) {
    id base = G1B_SUPER(id, gSlideSuper, self, _cmd, (struct objc_super *, SEL, id), element);
    if (!G1C_Sl_Bool(self, gSlBeginOff)) return base;
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    if (!a) return base;
    if ([a respondsToSelector:@selector(setLayoutUpdateMode:)]) G1B_SendVLL(a, @selector(setLayoutUpdateMode:), 3);
    id ss = [self respondsToSelector:@selector(switcherSettings)] ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id ch = (ss && [ss respondsToSelector:@selector(chamoisSettings)]) ? G1B_Send0(ss, @selector(chamoisSettings)) : nil;
    id a2a = (ch && [ch respondsToSelector:@selector(appToAppLayoutSettings)]) ? G1B_Send0(ch, @selector(appToAppLayoutSettings)) : nil;
    if (a2a && [a respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(a, @selector(setLayoutSettings:), a2a);
    return a;
}
static id G1C_Sl_BeginAnimation(id self, SEL _cmd) {
    id r = G1B_NewUpdateLayoutResponse(0xc, 3);
    id ss = [self respondsToSelector:@selector(switcherSettings)] ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id ch = (ss && [ss respondsToSelector:@selector(chamoisSettings)]) ? G1B_Send0(ss, @selector(chamoisSettings)) : nil;
    id a2a = (ch && [ch respondsToSelector:@selector(appToAppLayoutSettings)]) ? G1B_Send0(ch, @selector(appToAppLayoutSettings)) : nil;
    double delay = G1B_Dbl0(a2a, @selector(response)) * 0.5;
    id timer = G1C_NewTimerResponse(delay, G1C_Sl_AnimReason(self, 0));
    if (timer) r = G1B_Append(timer, r);
    G1C_Sl_SetBool(self, gSlBeginOff, YES);
    return r;
}
static id G1C_Sl_HandleChanged(id self, SEL _cmd, id event) {
    id r = G1B_HasSuper(gSlideSuper, _cmd) ? G1B_SUPER(id, gSlideSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    BOOL animated = [event respondsToSelector:@selector(isAnimated)] ? G1B_SendB0(event, @selector(isAnimated)) : NO;
    if (!animated) return r;
    unsigned long long dir = G1C_Sl_Dir(self);
    if (dir == 1) {
        if (!G1C_Sl_Bool(self, gSlBeginOff)) { id b = G1C_Sl_BeginAnimation(self, 0); if (b) r = G1B_Append(b, r); }
    } else if (dir == 0 && !G1C_Sl_Bool(self, gSlPrepOff) && !G1C_Sl_Bool(self, gSlBeginOff)) {
        id upd = G1B_NewUpdateLayoutResponse(2, 2);
        if (upd) r = G1B_Append(upd, r);
        id timer = G1C_NewTimerResponse(0.0, G1C_Sl_PrepReason(self, 0));
        if (timer) r = G1B_Append(timer, r);
        G1C_Sl_SetBool(self, gSlPrepOff, YES);
    }
    return r;
}
static id G1C_Sl_HandleTimer(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gSlideSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    NSString *reason = [event respondsToSelector:@selector(reason)] ? G1B_Send0(event, @selector(reason)) : nil;
    if (![reason isKindOfClass:[NSString class]]) return r;
    if (G1C_Sl_Dir(self) != 0) {
        if (G1C_Sl_Bool(self, gSlBeginOff) && [reason isEqualToString:G1C_Sl_AnimReason(self, 0)]) {
            G1C_Sl_SetBool(self, gSlBeginOff, NO);
            G1B_SendVLL(self, @selector(setState:), 1);
        }
    } else if (G1C_Sl_Bool(self, gSlPrepOff) && [reason isEqualToString:G1C_Sl_PrepReason(self, 0)]) {
        G1C_Sl_SetBool(self, gSlPrepOff, NO);
        id b = G1C_Sl_BeginAnimation(self, 0);
        if (b) r = G1B_Append(b, r);
    }
    return r;
}
static BOOL G1C_BuildSlide(void) {
    Class old = NSClassFromString(@"SBContinuousExposeIdentifierSlideModifier");
    gSlideSuper = old ? class_getSuperclass(old) : NSClassFromString(@"SBSwitcherModifier");
    if (!gSlideSuper || !gOverrideIdsCls) return NO;
    const G1BIvar iv[] = {
        { "_isWaitingToPrepareLayout", sizeof(BOOL), 0, "B" }, { "_isWaitingToBeginAnimation", sizeof(BOOL), 0, "B" },
        { "_direction", sizeof(unsigned long long), 3, "Q" },
    };
    const G1BMethod m[] = {
        { "initWithContinuousExposeIdentifier:previousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:direction:", (IMP)G1C_Sl_Init, "@48@0:8@16@24@32Q40" },
        { "continuousExposeIdentifier", (IMP)G1C_Sl_Ident, "@16@0:8" },
        { "previousContinuousExposeIdentifiersInSwitcher", (IMP)G1C_Sl_PrevSw, "@16@0:8" },
        { "previousContinuousExposeIdentifiersInStrip", (IMP)G1C_Sl_PrevStrip, "@16@0:8" },
        { "direction", (IMP)G1C_Sl_DirGetter, "Q16@0:8" },
        { "_waitingToPrepareLayoutReason", (IMP)G1C_Sl_PrepReason, "@16@0:8" },
        { "_waitingToAnimateReason", (IMP)G1C_Sl_AnimReason, "@16@0:8" },
        { "_beginAnimation", (IMP)G1C_Sl_BeginAnimation, "@16@0:8" },
        { "frameForIndex:", (IMP)G1C_Sl_Frame, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
        { "anchorPointForIndex:", (IMP)G1C_Sl_Anchor, "{CGPoint=dd}24@0:8Q16" },
        { "scaleForIndex:", (IMP)G1C_Sl_Scale, "d24@0:8Q16" },
        { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1C_Sl_AccFrame, "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48" },
        { "animationAttributesForLayoutElement:", (IMP)G1C_Sl_AnimAttrs, "@24@0:8@16" },
        { "handleContinuousExposeIdentifiersChangedEvent:", (IMP)G1C_Sl_HandleChanged, "@24@0:8@16" },
        { "handleTimerEvent:", (IMP)G1C_Sl_HandleTimer, "@24@0:8@16" },
    };
    BOOL made = NO;
    gSlideCls = G1B_MakeClass("BP162ContinuousExposeIdentifierSlideModifier", gSlideSuper, iv, 3, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) {
        gSlPrepOff = G1B_IvarOffset(gSlideCls, "_isWaitingToPrepareLayout");
        gSlBeginOff = G1B_IvarOffset(gSlideCls, "_isWaitingToBeginAnimation");
        gSlDirOff = G1B_IvarOffset(gSlideCls, "_direction");
    }
    return gSlideCls != Nil && gSlPrepOff >= 0 && gSlBeginOff >= 0 && gSlDirOff >= 0;
}
// factory used by the Root's handleContinuousExposeIdentifiersChangedEvent: (item 2)
static id G1C_NewSlideModifier(NSString *ident, NSArray *prevSw, NSArray *prevStrip, unsigned long long dir) {
    SEL s = @selector(initWithContinuousExposeIdentifier:previousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:direction:);
    if (!gSlideCls || !ident || ![gSlideCls instancesRespondToSelector:s]) return nil;
    if (BP_LogEnabled()) BP_Log(@"GLITCH slide created ident=%@ dir=%llu (0=slide in, 1=slide out) prevSw=%@ prevStrip=%@", ident, dir, G1C_DbgIds(prevSw), G1C_DbgIds(prevStrip));
    return ((id (*)(id, SEL, id, id, id, unsigned long long))objc_msgSend)([gSlideCls alloc], s, ident, prevSw ?: @[], prevStrip ?: @[], dir);
}

// ---- SBFluidSwitcherViewController -_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated: (162 0x1c7457450, 69 insns; 160 0x1c5fde0d0) ----
// WHOLE-METHOD REPLACEMENT (installed after the group 2 hook of the same method, so it is the outermost and its `%orig` is never called):
//   16.2: prevSw = ivar InSwitcher ?: @[]; prevStrip = ivar InStrip ?: @[]; InStrip = [root adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:prevStrip];
//         InSwitcher = [root adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:prevSw identifiersInStrip:InStrip];
//         [self newContinuousExposeIdentifiersGenerationCount]; _appLayoutsForContinuousExposeIdentifiers = nil;
//         dispatch SBContinuousExposeIdentifiersChangedModifierEvent(prevSw, prevStrip, from, to, animated)  -- ALWAYS (16.0: only when animated).
// The 16.0 single list ivar `_continuousExposeIdentifiers` (NSOrderedSet) is kept in sync with the new switcher list for 16.0-only readers.
static NSArray *G1C_AskRootIds(id root, SEL sel, id a, id b, BOOL two) {
    if (!root || ![root respondsToSelector:sel]) return nil;
    id r = two ? ((id (*)(id, SEL, id, id))objc_msgSend)(root, sel, a, b) : ((id (*)(id, SEL, id))objc_msgSend)(root, sel, a);
    return [r isKindOfClass:[NSArray class]] ? r : nil;
}
%group G1C_VCIds
%hook SBFluidSwitcherViewController
- (void)_updateContinuousExposeIdentifiersTransitioningFromAppLayout:(id)from toAppLayout:(id)to animated:(BOOL)animated {
    BOOL ok = G1C_ON() && gIdsEventCls && [self respondsToSelector:@selector(isChamoisWindowingUIEnabled)] && [self respondsToSelector:@selector(_dispatchEventAndHandleAction:)];
    if (!ok) {
        %orig;
        return;
    }
    if (!G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled))) return;
    BP162VCState *st = BP_G2_VCStateFor(self);
    if (!st) {
        %orig;
        return;
    }
    NSArray *prevSw = st.idsInSwitcher ?: @[], *prevStrip = st.idsInStrip ?: @[];
    id root = G1C_IvarObj(self, "_rootModifier");
    NSArray *strip = G1C_AskRootIds(root, sel_registerName("adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:"), prevStrip, nil, NO);
    NSArray *sw = nil;
    if (strip) sw = G1C_AskRootIds(root, sel_registerName("adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:"), prevSw, strip, YES);
    if (!strip || !sw) {                                               // root does not answer (yet): the group 2 list builders are the fallback
        id stage = [root respondsToSelector:@selector(appLayoutOnContinuousExposeStage)] ? G1B_Send0(root, @selector(appLayoutOnContinuousExposeStage)) : nil;
        id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
        NSUInteger cap = (attrs && [attrs respondsToSelector:@selector(numberOfRowsWhileInApp)]) ? ((NSUInteger (*)(id, SEL))objc_msgSend)(attrs, @selector(numberOfRowsWhileInApp)) : 0;
        strip = BP_G2_ComputeStripIds(self, stage, prevStrip, cap);
        sw = BP_G2_ComputeSwitcherIds(self, stage, strip);
    }
    st.idsInStrip = strip;
    st.idsInSwitcher = sw;
    st.idsGeneration += 1;
    // keep the 16.0 state coherent: single ordered set, group cache cleared, 16.0 generation counter bumped
    Ivar ivSet = class_getInstanceVariable(object_getClass(self), "_continuousExposeIdentifiers");
    if (ivSet) object_setIvar(self, ivSet, [NSOrderedSet orderedSetWithArray:sw ?: @[]]);
    Ivar ivMap = class_getInstanceVariable(object_getClass(self), "_appLayoutsForContinuousExposeIdentifiers");
    if (ivMap) object_setIvar(self, ivMap, nil);
    long long g16 = 0;
    if (G1C_IvarRaw(self, "_continuousExposeIdentifiersChangedGenerationCount", &g16, sizeof g16, NO)) { g16 += 1; G1C_IvarRaw(self, "_continuousExposeIdentifiersChangedGenerationCount", &g16, sizeof g16, YES); }
    SEL ini = @selector(initWithPreviousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:transitioningFromAppLayout:transitioningToAppLayout:animated:);
    id ev = ((id (*)(id, SEL, id, id, id, id, BOOL))objc_msgSend)([gIdsEventCls alloc], ini, prevSw, prevStrip, from, to, animated);
    if (ev && [ev respondsToSelector:@selector(setBPGenerationCount:)]) ((void (*)(id, SEL, unsigned long long))objc_msgSend)(ev, @selector(setBPGenerationCount:), st.idsGeneration);
    if (BP_LogEnabled()) BP_Log(@"GLITCH VC ids update: from=%@ to=%@ animated=%d root=%@ stage=%@ strip %@ -> %@ switcher %@ -> %@", G1C_DbgLayout(from), G1C_DbgLayout(to), animated, G1C_DbgCls(root),
                                G1C_DbgLayout([root respondsToSelector:@selector(appLayoutOnContinuousExposeStage)] ? G1B_Send0(root, @selector(appLayoutOnContinuousExposeStage)) : nil), G1C_DbgIds(prevStrip), G1C_DbgIds(strip), G1C_DbgIds(prevSw), G1C_DbgIds(sw));
    if (ev) G1B_SendV1(self, @selector(_dispatchEventAndHandleAction:), ev);
}
%end
%end

// ============================================================================================================
// 5d  SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier (keyboard window cycling inside a Stage Manager group)      DONE
// ============================================================================================================
// 16.2 vs 16.0 (structural diff, 4 methods): 
//   handleContinuousExposeIdentifiersChangedEvent: 162 0x1c758977c: r = [super ...]; ONLY if [event isAnimated]: _generationCount = [self continuousExposeIdentifiersGenerationCount]
//       (16.0 0x1c6104180: event.generationCount); if (_generationCount == _initialGenerationCount) r = Append(Timer(1.5 s, [self _timeoutReason]), r);
//       if ([[event transitioningToAppLayout].continuousExposeIdentifier isEqual:_appLayout.continuousExposeIdentifier]) { _appLayoutToOrderFront = [event transitioningToAppLayout];
//             if ([_appLayout isEqual:_behindAppLayout] || [to isEqual:_behindAppLayout]) r = Append([self _completeIfNeededIgnoringHover:YES], r); }
//       else { _appLayoutToOrderFront = nil; r = Append([self _completeIfNeededIgnoringHover:YES], r); }
//   _timeoutReason: 162 0x1c7589cb4 "%@-%ld" with (class name, _initialGenerationCount)  [16.0: _generationCount, so a later ids event invalidated the reason]
//   _completeIfNeededIgnoringHover: 162 0x1c7589b7c: new first test `if ([self state] == 1) return nil;` (no second completion), rest identical
//   handleTransitionEvent: NEW 0x1c75896c8: if [[event appLayoutsWithRemovalContexts] containsObject:_appLayoutToOrderFront] _appLayoutToOrderFront = nil; then [super].
// The init (0x1c75892d0 initWithAppLayout:behindAppLayout:generationCount:) is unchanged. The creator is the Root (item 2).
%group G1C_Cycle
%hook SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier
- (id)handleContinuousExposeIdentifiersChangedEvent:(id)event {
    Class me = %c(SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier);
    if (!G1C_ON() || !me) {
        return %orig;
    }
    Class sup = class_getSuperclass(me);
    id r = G1B_HasSuper(sup, _cmd) ? G1B_SUPER(id, sup, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    BOOL animated = [event respondsToSelector:@selector(isAnimated)] ? G1B_SendB0(event, @selector(isAnimated)) : YES;
    if (!animated) return r;
    unsigned long long gen = 0;
    SEL gs = sel_registerName("continuousExposeIdentifiersGenerationCount");
    if ([self respondsToSelector:gs]) gen = ((unsigned long long (*)(id, SEL))objc_msgSend)(self, gs);
    else if ([event respondsToSelector:@selector(generationCount)]) gen = ((unsigned long long (*)(id, SEL))objc_msgSend)(event, @selector(generationCount));
    G1C_IvarRaw(self, "_generationCount", &gen, sizeof gen, YES);
    unsigned long long initial = 0;
    G1C_IvarRaw(self, "_initialGenerationCount", &initial, sizeof initial, NO);
    if (gen == initial) {
        id timer = G1C_NewTimerResponse(1.5, [self respondsToSelector:@selector(_timeoutReason)] ? G1B_Send0(self, @selector(_timeoutReason)) : nil);
        if (timer) r = G1B_Append(timer, r);
    }
    id appLayout = G1C_IvarObj(self, "_appLayout"), behind = G1C_IvarObj(self, "_behindAppLayout");
    id to = [event respondsToSelector:@selector(transitioningToAppLayout)] ? G1B_Send0(event, @selector(transitioningToAppLayout)) : nil;
    id toId = to ? G1B_Send0(to, @selector(continuousExposeIdentifier)) : nil, myId = appLayout ? G1B_Send0(appLayout, @selector(continuousExposeIdentifier)) : nil;
    Ivar ivFront = class_getInstanceVariable(object_getClass(self), "_appLayoutToOrderFront");
    SEL complete = @selector(_completeIfNeededIgnoringHover:);
    BOOL doComplete = NO;
    if ((toId == myId) || (toId && [toId isEqual:myId])) {
        if (ivFront) object_setIvar(self, ivFront, to);
        doComplete = [appLayout isEqual:behind] || [to isEqual:behind];
    } else {
        if (ivFront) object_setIvar(self, ivFront, nil);
        doComplete = YES;
    }
    if (doComplete && [self respondsToSelector:complete]) {
        id c = ((id (*)(id, SEL, BOOL))objc_msgSend)(self, complete, YES);
        r = G1B_AppendTo(c, r);
    }
    return r;
}
- (id)_timeoutReason {
    if (!G1C_ON()) {
        return %orig;
    }
    unsigned long long initial = 0;
    G1C_IvarRaw(self, "_initialGenerationCount", &initial, sizeof initial, NO);
    return [NSString stringWithFormat:@"%@-%ld", NSStringFromClass([self class]), (long)initial];
}
- (id)_completeIfNeededIgnoringHover:(BOOL)ignoreHover {
    if (G1C_ON() && [self respondsToSelector:@selector(state)] && G1B_SendLL0(self, @selector(state)) == 1) return nil;
    return %orig;
}
- (id)handleTransitionEvent:(id)event {
    if (G1C_ON() && [event respondsToSelector:@selector(appLayoutsWithRemovalContexts)]) {
        id front = G1C_IvarObj(self, "_appLayoutToOrderFront");
        id removed = G1B_Send0(event, @selector(appLayoutsWithRemovalContexts));
        if (front && [removed isKindOfClass:[NSArray class]] && [removed containsObject:front]) {
            Ivar iv = class_getInstanceVariable(object_getClass(self), "_appLayoutToOrderFront");
            if (iv) object_setIvar(self, iv, nil);
        }
    }
    return %orig;
}
%end
%end

// ============================================================================================================
// 5e  SBRevealContinuousExposeStripsGestureModifier (strip reveal pan; 16.2: pointer aware, strip-width based progress, own transition completion)
//     and SBRevealContinuousExposeStripOverflowGestureModifier / ...RootSwitcherModifier                                  DONE
// ============================================================================================================
// Added to the 16.0 class (ivars identical in both builds: _progress +0x78, _initialAppLayout +0x80). NOTE: classes that receive new query
// methods are never messaged from this file (class_getInstanceMethod / class_addMethod only), so +initialize has not run when we add them.
static Class gRevealCls, gRevealSuper;
// true when `c` itself (not a superclass) implements `s`
static BOOL G1C_HasOwn(Class c, SEL s) {
    unsigned int n = 0; BOOL found = NO;
    Method *ms = class_copyMethodList(c, &n);
    for (unsigned int i = 0; ms && i < n; i++) if (method_getName(ms[i]) == s) { found = YES; break; }
    free(ms);
    return found;
}
static void G1C_AddLike(Class c, const char *sel, IMP imp, const char *fallback, BOOL replace) {
    SEL s = sel_registerName(sel);
    const char *t = G1B_TypesFor(s, fallback);
    if (!c || !t) return;
    if (replace) class_replaceMethod(c, s, imp, t);
    else if (!G1C_HasOwn(c, s)) class_addMethod(c, s, imp, t);
}
// 16.2 SBSwitcherModifierEvent -isIndirectPanGestureEvent  NO (0x1c7878cf8); SBIndirectPanGestureSwitcherModifierEvent YES (0x1c7878b28). Absent in 16.0.
static BOOL G1C_EvNo(id s, SEL c) { return NO; }
static BOOL G1C_EvYes(id s, SEL c) { return YES; }
static void G1C_InstallEventPredicates(void) {
    Class base = objc_getClass("SBSwitcherModifierEvent"), ind = objc_getClass("SBIndirectPanGestureSwitcherModifierEvent");
    if (base && !class_getInstanceMethod(base, @selector(isIndirectPanGestureEvent))) class_addMethod(base, @selector(isIndirectPanGestureEvent), (IMP)G1C_EvNo, "B16@0:8");
    if (ind) class_replaceMethod(ind, @selector(isIndirectPanGestureEvent), (IMP)G1C_EvYes, "B16@0:8");
}

static double G1C_Rv_Progress(id self, SEL _cmd) { return G1C_IvarD(self, "_progress"); }
// 162 0x1c781783c.  delta = indirect ? (rtl ? tx : -tx) : (rtl ? -tx : tx); range = indirect ? 0.1 : 0.2 (rubber band);
// _progress = BSUIConstrainValueToIntervalWithRubberBand(max(delta, 0) / stripWidth, range, [0, 1]);   phase 3 decides show/hide:
//   indirect: canceled ? (endReason == 5) : (endReason == 3 || progress >= 0.25);   touch: !canceled && progress >= 0.25
//   -> UpdateContinuousExposeStripsPresentation(show ? (1, 0) : (0, 1)), UpdateLayout(0xc, 3), Perform(requestForActivatingAppLayout:_initialAppLayout, gestureInitiated YES).
// 16.0 0x1c63706d4: progress = constrained |tx| / 100, show threshold 0.5, and `setState:1` at the end (16.2 completes in handleTransitionEvent:).
static double G1C_RubberBand(double v, double range) {
    // BSUIConstrainValueToIntervalWithRubberBand with interval [0,1] both ends rubber-banded: inside the interval -> v; outside -> asymptotic
    // within `range` (Apple's curve; the exact curve is not needed for the decision logic, only for the visual overshoot). UNSURE: compare visually.
    if (v >= 0 && v <= 1) return v;
    double over = v < 0 ? -v : v - 1.0, lim = range;
    if (lim <= 0) return v < 0 ? 0 : 1;
    double banded = (1.0 - 1.0 / (over * 0.55 / lim + 1.0)) * lim;
    return v < 0 ? -banded : 1.0 + banded;
}
typedef double (*G1CConstrainFn)(double value, double range, const void *interval);
static double G1C_Constrain01(double v, double range) {
    // the real function takes an interval struct on the stack {double lower; BOOL lowerRubber; double upper; BOOL upperRubber} (see 0x1c7817910..0x1c7817920)
    struct { double lo; BOOL loRb; double hi; BOOL hiRb; } iv = { 0.0, YES, 1.0, YES };
    static G1CConstrainFn fn; static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (G1CConstrainFn)dlsym(RTLD_DEFAULT, "BSUIConstrainValueToIntervalWithRubberBand"); });
    if (fn) return fn(v, range, &iv);
    return G1C_RubberBand(v, range);
}
static id G1C_NewStripsPresentationResponse(unsigned long long present, unsigned long long dismiss) {
    Class c = NSClassFromString(@"SBUpdateContinuousExposeStripsPresentationResponse");
    SEL s = @selector(initWithPresentationOptions:dismissalOptions:);
    if (!c || ![c instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, unsigned long long, unsigned long long))objc_msgSend)([c alloc], s, present, dismiss);
}
static id G1C_NewPerformActivate(id appLayout, BOOL gesture) {
    Class rc = NSClassFromString(@"SBSwitcherTransitionRequest"), pc = NSClassFromString(@"SBPerformTransitionSwitcherEventResponse");
    SEL rs = NSSelectorFromString(@"requestForActivatingAppLayout:"), ps = @selector(initWithTransitionRequest:gestureInitiated:);
    if (!rc || !pc || !appLayout || ![rc respondsToSelector:rs] || ![pc instancesRespondToSelector:ps]) return nil;
    id req = G1B_Send1((id)rc, rs, appLayout);
    return req ? ((id (*)(id, SEL, id, BOOL))objc_msgSend)([pc alloc], ps, req, gesture) : nil;
}
static NSString *const kG1CRevealTimeout = @"BP162RevealStripsCompletionTimeout";
static IMP gRevealOrigHandle;      // the 16.0 handleGestureEvent: of the class (NULL when it was inherited): used when the group is switched off (review B8)
static id G1C_Rv_HandleGesture(id self, SEL _cmd, id event) {
    if (!G1C_ON()) {
        if (gRevealOrigHandle) return ((id (*)(id, SEL, id))gRevealOrigHandle)(self, _cmd, event);
        return G1B_SUPER(id, gRevealSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    }
    id resp = G1B_SUPER(id, gRevealSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!event || ![event respondsToSelector:@selector(phase)]) return resp;
    BOOL indirect = [event respondsToSelector:@selector(isIndirectPanGestureEvent)] && G1B_SendB0(event, @selector(isIndirectPanGestureEvent));
    BOOL rtl = [self respondsToSelector:@selector(isRTLEnabled)] && G1B_SendB0(self, @selector(isRTLEnabled));
    double tx = G1C_SendPoint0(event, @selector(translationInContainerView)).x;
    double delta = indirect ? (rtl ? tx : -tx) : (rtl ? -tx : tx);
    double range = indirect ? 0.1 : 0.2;
    id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    double strip = G1B_Dbl0(attrs, @selector(stripWidth));
    double raw = strip > 0 ? (delta > 0 ? delta : 0.0) / strip : 0.0;
    double progress = G1C_Constrain01(raw, range);
    G1C_SetIvarD(self, "_progress", progress);
    if (G1B_SendLL0(event, @selector(phase)) != 3) return resp;
    BOOL canceled = [event respondsToSelector:@selector(isCanceled)] && G1B_SendB0(event, @selector(isCanceled));
    BOOL show;
    if (indirect) {
        unsigned long long reason = [event respondsToSelector:@selector(indirectPanEndReason)] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(event, @selector(indirectPanEndReason)) : 0;
        show = canceled ? (reason == 5) : (reason == 3 || progress >= 0.25);
    } else show = !canceled && progress >= 0.25;
    if (BP_LogEnabled()) BP_Log(@"GLITCH strip reveal gesture ended: show=%d canceled=%d indirect=%d progress=%.3f initial layout=%@", show, canceled, indirect, progress, G1C_DbgLayout(G1C_IvarObj(self, "_initialAppLayout")));
    id pres = show ? G1C_NewStripsPresentationResponse(1, 0) : G1C_NewStripsPresentationResponse(0, 1);
    if (pres) resp = G1B_Append(pres, resp);
    id upd = G1B_NewUpdateLayoutResponse(0xc, 3);
    if (upd) resp = G1B_Append(upd, resp);
    id perform = G1C_NewPerformActivate(G1C_IvarObj(self, "_initialAppLayout"), YES);
    if (perform) resp = G1B_Append(perform, resp);
    // safety net (not in 16.2): if no transition event ever reaches this modifier (the activate request can be a no-op) it would never complete
    id timer = G1C_NewTimerResponse(2.0, kG1CRevealTimeout);
    if (timer) resp = G1B_Append(timer, resp);
    return resp;
}
static id G1C_Rv_HandleTransition(id self, SEL _cmd, id event) {
    id resp = G1B_SUPER(id, gRevealSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    if (event && [event respondsToSelector:@selector(phase)] && G1B_SendLL0(event, @selector(phase)) >= 2) G1B_SendVLL(self, @selector(setState:), 1);
    return resp;
}
static id G1C_Rv_HandleTimer(id self, SEL _cmd, id event) {
    id resp = G1B_HasSuper(gRevealSuper, _cmd) ? G1B_SUPER(id, gRevealSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    id reason = [event respondsToSelector:@selector(reason)] ? G1B_Send0(event, @selector(reason)) : nil;
    if ([reason isKindOfClass:[NSString class]] && [reason isEqualToString:kG1CRevealTimeout]) G1B_SendVLL(self, @selector(setState:), 1);
    return resp;
}
typedef struct { double tl, bl, br, tr; } G1CRadii;          // UIRectCornerRadii {topLeft, bottomLeft, bottomRight, topRight}
// 162 0x1c7817530: initial layout -> radius = [self displayCornerRadius] (0 -> chamoisLayoutAttributes.stageCornerRaddii) / [self scaleForIndex:i], all four corners; else [super]
static G1CRadii G1C_Rv_Radii(id self, SEL _cmd, unsigned long long i) {
    NSArray *layouts = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id l = i < layouts.count ? layouts[i] : nil;
    id initial = G1C_IvarObj(self, "_initialAppLayout");
    if (l && initial && [l isEqual:initial]) {
        double r = [self respondsToSelector:@selector(displayCornerRadius)] ? G1C_SendD0(self, @selector(displayCornerRadius)) : 0.0;
        if (r == 0.0) { id a = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil; r = G1B_Dbl0(a, @selector(stageCornerRaddii)); }
        double sc = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), i);
        double v = sc != 0 ? r / sc : r;
        return (G1CRadii){ v, v, v, v };
    }
    return G1B_SUPER(G1CRadii, gRevealSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
// 162 0x1c7817638: s = [super ...]; if the initial layout's [super frameForIndex:] size equals containerViewBounds.size: s = clamp(s * _progress, 0, 1)
static double G1C_Rv_Shadow(id self, SEL _cmd, long long role, unsigned long long i) {
    double s = G1B_SUPER(double, gRevealSuper, self, _cmd, (struct objc_super *, SEL, long long, unsigned long long), role, i);
    NSArray *layouts = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id l = i < layouts.count ? layouts[i] : nil;
    id initial = G1C_IvarObj(self, "_initialAppLayout");
    if (l && initial && [l isEqual:initial]) {
        CGRect f = G1B_SUPER(CGRect, gRevealSuper, self, @selector(frameForIndex:), (struct objc_super *, SEL, unsigned long long), i);
        CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
        if (f.size.width == cb.size.width && f.size.height == cb.size.height) {
            double v = s * G1C_IvarD(self, "_progress");
            s = v < 0 ? 0 : (v > 1 ? 1 : v);
        }
    }
    return s;
}
// 162 0x1c7817744: mutableCopy of super; for layout elements (switcherLayoutElementType == 0): SBFFluidBehaviorSettings(trackingResponse 0.15, trackingDampingRatio 0.85)
//                  as layout / position / opacity settings and updateMode 5
static id G1C_Rv_AnimAttrs(id self, SEL _cmd, id element) {
    id base = G1B_SUPER(id, gRevealSuper, self, _cmd, (struct objc_super *, SEL, id), element);
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    if (!a || ![element respondsToSelector:@selector(switcherLayoutElementType)] || G1B_SendLL0(element, @selector(switcherLayoutElementType)) != 0) return a;
    Class fc = NSClassFromString(@"SBFFluidBehaviorSettings");
    if (!fc || ![fc instancesRespondToSelector:@selector(initWithDefaultValues)]) return a;
    id s = G1B_Send0([fc alloc], @selector(initWithDefaultValues));
    if (!s) return a;
    G1C_SendVD(s, @selector(setTrackingResponse:), 0.15);
    G1C_SendVD(s, @selector(setTrackingDampingRatio:), 0.85);
    if ([a respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(a, @selector(setLayoutSettings:), s);
    if ([a respondsToSelector:@selector(setPositionSettings:)]) G1B_SendV1(a, @selector(setPositionSettings:), s);
    if ([a respondsToSelector:@selector(setOpacitySettings:)]) G1B_SendV1(a, @selector(setOpacitySettings:), s);
    if ([a respondsToSelector:@selector(setUpdateMode:)]) G1B_SendVLL(a, @selector(setUpdateMode:), 5);
    return a;
}
static void G1C_InstallRevealStrips(void) {
    Class c = objc_getClass("SBRevealContinuousExposeStripsGestureModifier");
    if (!c) return;
    gRevealCls = c; gRevealSuper = class_getSuperclass(c);
    G1C_AddLike(c, "continuousExposeStripProgress", (IMP)G1C_Rv_Progress, "d16@0:8", NO);                 // 16.2 name of continuousExposeAppStripUnoccludedProgress
    {
        SEL hg = sel_registerName("handleGestureEvent:");
        const char *ht = G1B_TypesFor(hg, "@24@0:8@16");
        if (ht) gRevealOrigHandle = class_replaceMethod(c, hg, (IMP)G1C_Rv_HandleGesture, ht);
    }
    G1C_AddLike(c, "handleTransitionEvent:", (IMP)G1C_Rv_HandleTransition, "@24@0:8@16", NO);
    G1C_AddLike(c, "handleTimerEvent:", (IMP)G1C_Rv_HandleTimer, "@24@0:8@16", NO);
    G1C_AddLike(c, "cornerRadiiForIndex:", (IMP)G1C_Rv_Radii, "{UIRectCornerRadii=dddd}24@0:8Q16", NO);
    G1C_AddLike(c, "shadowOpacityForLayoutRole:atIndex:", (IMP)G1C_Rv_Shadow, "d32@0:8q16Q24", NO);
    G1C_AddLike(c, "animationAttributesForLayoutElement:", (IMP)G1C_Rv_AnimAttrs, "@24@0:8@16", NO);
}

// ============================================================================================================
// 5f  SBContinuousExposeAppToAppModifier (16.2 form, complete) + its Root wiring helper                              DONE
//     (supersedes the opt-in hook G1B_AppToApp of group1b 4.8, which read flags that nothing ever set)
// ============================================================================================================
// 16.2 ivars: _continuousExposeConfigurationChangeTransition +0x88, _commandTabTransition +0x89, _launchingFromDockTransition +0x8a, _fromAppLayout +0x90,
// _fromInterfaceOrientation +0x98, _toAppLayout +0xa0, _toInterfaceOrientation +0xa8, _fromDisplayItemLayoutAttributesMap +0xb0, _toDisplayItemLayoutAttributesMap +0xb8.
// (16.0: +0x88 _shouldSendFromIdentifierToBack, +0x89 _shouldSendToIdentifierToFront, +0x8a _continuousExposeConfigurationChangeTransition; removed methods:
//  adjustedContinuousExposeIdentifiersForIdentifiers:, visibleAppLayouts; the identifier re-ordering that 16.0's transitionWillBegin did moved into the strip/identifier model.)
// Superclass SBTransitionSwitcherModifier. A NEW class (direct subclass of the base) so none of the 16.0 overrides above are inherited.
static Class gA2ACls, gA2ASuper;
static ptrdiff_t gA2AConfOff = -1, gA2ACmdOff = -1, gA2ADockOff = -1, gA2AFromOriOff = -1, gA2AToOriOff = -1;
static char kA2AFrom, kA2ATo, kA2AFromMap, kA2AToMap;
static BOOL G1C_A2A_B(id s, ptrdiff_t off) { return off >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)s + off); }
static void G1C_A2A_SetB(id s, ptrdiff_t off, BOOL v) { if (off >= 0) *(BOOL *)((uint8_t *)(__bridge void *)s + off) = v; }

static id G1C_A2A_Init(id self, SEL _cmd, id tid, id from, long long fromOri, id to, long long toOri, id fromMap, id toMap) {
    if (!from || !to) return nil;                                           // 16.2 NSAssert (SBContinuousExposeAppToAppModifier.m lines 0x18 / 0x19)
    id me = G1B_SUPER(id, gA2ASuper, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (!me) return nil;
    G1B_SET(me, kA2AFrom, from); G1B_SET(me, kA2ATo, to);
    G1B_SET(me, kA2AFromMap, [fromMap copy]); G1B_SET(me, kA2AToMap, [toMap copy]);
    if (gA2AFromOriOff >= 0) *(long long *)((uint8_t *)(__bridge void *)me + gA2AFromOriOff) = fromOri;
    if (gA2AToOriOff >= 0) *(long long *)((uint8_t *)(__bridge void *)me + gA2AToOriOff) = toOri;
    return me;
}
static id G1C_A2A_From(id s, SEL c) { return G1B_GET(s, kA2AFrom); }
static id G1C_A2A_To(id s, SEL c) { return G1B_GET(s, kA2ATo); }
static id G1C_A2A_FromMap(id s, SEL c) { return G1B_GET(s, kA2AFromMap); }
static id G1C_A2A_ToMap(id s, SEL c) { return G1B_GET(s, kA2AToMap); }
static long long G1C_A2A_FromOri(id s, SEL c) { return gA2AFromOriOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)s + gA2AFromOriOff); }
static long long G1C_A2A_ToOri(id s, SEL c) { return gA2AToOriOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)s + gA2AToOriOff); }
static BOOL G1C_A2A_GetConf(id s, SEL c) { return G1C_A2A_B(s, gA2AConfOff); }
static BOOL G1C_A2A_GetCmd(id s, SEL c) { return G1C_A2A_B(s, gA2ACmdOff); }
static BOOL G1C_A2A_GetDock(id s, SEL c) { return G1C_A2A_B(s, gA2ADockOff); }
static void G1C_A2A_SetConf(id s, SEL c, BOOL v) { G1C_A2A_SetB(s, gA2AConfOff, v); }
static void G1C_A2A_SetCmd(id s, SEL c, BOOL v) { G1C_A2A_SetB(s, gA2ACmdOff, v); }
static void G1C_A2A_SetDock(id s, SEL c, BOOL v) { G1C_A2A_SetB(s, gA2ADockOff, v); }

// 162 0x1c759598c: children replace the 16.0 SBContinuousExposeCrossblurModifier
static void G1C_A2A_DidMove(id self, SEL _cmd, id parent) {
    G1B_SUPER(void, gA2ASuper, self, _cmd, (struct objc_super *, SEL, id), parent);
    id to = G1B_GET(self, kA2ATo), from = G1B_GET(self, kA2AFrom);
    if (!parent || !to || !from) return;
    SEL any = @selector(containsAnyItemFromAppLayout:);
    if (![to respondsToSelector:any] || G1B_SendB1(to, any, from)) return;
    NSArray *layouts = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    if (![layouts containsObject:to]) return;
    BOOL cross = G1C_A2A_B(self, gA2ACmdOff) || G1C_A2A_B(self, gA2ADockOff);
    id tid = [self respondsToSelector:@selector(transitionID)] ? G1B_Send0(self, @selector(transitionID)) : nil;
    id child = nil;
    if (cross && gXBCls && [gXBCls instancesRespondToSelector:@selector(initWithTransitionID:toAppLayout:fromAppLayout:)])
        child = ((id (*)(id, SEL, id, id, id))objc_msgSend)([gXBCls alloc], @selector(initWithTransitionID:toAppLayout:fromAppLayout:), tid, to, from);
    else if (!cross && gF2SCls && [gF2SCls instancesRespondToSelector:@selector(initWithTransitionID:outgoingAppLayout:)])
        child = ((id (*)(id, SEL, id, id))objc_msgSend)([gF2SCls alloc], @selector(initWithTransitionID:outgoingAppLayout:), tid, from);
    if (child && [self respondsToSelector:@selector(addChildModifier:)]) G1B_SendV1(self, @selector(addChildModifier:), child);
}
static BOOL G1C_A2A_AsyncDisabled(id self, SEL _cmd) {                                          // 0x1c7595acc
    id from = G1B_GET(self, kA2AFrom), to = G1B_GET(self, kA2ATo);
    if (from == to || [from isEqual:to]) return YES;
    return [from respondsToSelector:@selector(containsAllItemsFromAppLayout:)] ? G1B_SendB1(from, @selector(containsAllItemsFromAppLayout:), to) : NO;
}
static id G1C_A2A_WillBegin(id self, SEL _cmd) {                                                // 0x1c7595b40
    id r = G1B_SUPER(id, gA2ASuper, self, _cmd, (struct objc_super *, SEL));
    id upd = G1B_NewUpdateLayoutResponse(2, 2);
    return upd ? G1B_Append(upd, r) : r;
}
static id G1C_NewFluid(double response, double damping) {
    Class fc = NSClassFromString(@"SBFFluidBehaviorSettings");
    if (!fc || ![fc instancesRespondToSelector:@selector(initWithDefaultValues)]) return nil;
    id s = G1B_Send0([fc alloc], @selector(initWithDefaultValues));
    if (!s) return nil;
    if ([s respondsToSelector:@selector(setResponse:)]) G1C_SendVD(s, @selector(setResponse:), response);
    if ([s respondsToSelector:@selector(setDampingRatio:)]) G1C_SendVD(s, @selector(setDampingRatio:), damping);
    return s;
}
static id G1C_A2A_AnimAttrs(id self, SEL _cmd, id el) {                                         // 0x1c7595bd8
    id base = G1B_SUPER(id, gA2ASuper, self, _cmd, (struct objc_super *, SEL, id), el);
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    if (!a) return base;
    id to = G1B_GET(self, kA2ATo), from = G1B_GET(self, kA2AFrom);
    long long type = [el respondsToSelector:@selector(switcherLayoutElementType)] ? G1B_SendLL0(el, @selector(switcherLayoutElementType)) : 0;
    BOOL mine = type != 0 || (to && [to isEqual:el]) || (from && [from isEqual:el]);       // the two layouts and every accessory element
    if (mine) {
        if ([a respondsToSelector:@selector(setLayoutUpdateMode:)]) G1B_SendVLL(a, @selector(setLayoutUpdateMode:), 3);
        id s = G1C_NewFluid(0.4, 1.0);
        if (s && [a respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(a, @selector(setLayoutSettings:), s);
    } else {
        id s = G1C_NewFluid(0.54, 0.92);
        if (s) {
            if ([a respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(a, @selector(setLayoutSettings:), s);
            if ([a respondsToSelector:@selector(setPositionSettings:)]) G1B_SendV1(a, @selector(setPositionSettings:), s);
            if ([a respondsToSelector:@selector(setOpacitySettings:)]) G1B_SendV1(a, @selector(setOpacitySettings:), s);
        }
        if ([a respondsToSelector:@selector(setUpdateMode:)]) G1B_SendVLL(a, @selector(setUpdateMode:), 3);
    }
    return a;
}
static id G1C_A2A_TopMost(id self, SEL _cmd) {                                                  // 0x1c7595d44 (from centre leaf under, to centre leaf on top)
    id r = G1B_SUPER(id, gA2ASuper, self, _cmd, (struct objc_super *, SEL));
    id from = G1B_GET(self, kA2AFrom), to = G1B_GET(self, kA2ATo);
    SEL leaf = @selector(leafAppLayoutForRole:), ins = NSSelectorFromString(@"sb_arrayByInsertingOrMovingObject:toIndex:");
    id A = (from && [from respondsToSelector:leaf]) ? G1C_SendLL1x(from, leaf, 4) : nil;       // SBLayoutRoleCenter == 4
    id B = (to && [to respondsToSelector:leaf]) ? G1C_SendLL1x(to, leaf, 4) : nil;
    if (!A || ![r respondsToSelector:ins]) return r;
    if (B) {
        if ([A isEqual:B]) return r;
        r = ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(r, ins, A, 0);
        return ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(r, ins, B, 0);
    }
    return ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(r, ins, A, 0);
}
static double G1C_A2A_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long i) {   // 0x1c7595e68
    if ([self respondsToSelector:@selector(isPreparingLayout)] && G1B_SendB0(self, @selector(isPreparingLayout))) return 0.0;
    return G1B_SUPER(double, gA2ASuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, i);
}
static double G1C_A2A_Perspective(id self, SEL _cmd, id layout) {                               // 0x1c7595ef4
    id to = G1B_GET(self, kA2ATo);
    if (layout && to && [layout isEqual:to] && [self respondsToSelector:@selector(transitionPhase)] && G1B_SendLL0(self, @selector(transitionPhase)) == 1) return 0.0;
    return G1B_SUPER(double, gA2ASuper, self, _cmd, (struct objc_super *, SEL, id), layout);
}
// 0x1c7595f80. The size test needs the 16.2 attributes API (sizeInBounds:defaultSize:screenEdgePadding:) -> data layer requirement DM1.
static BOOL G1C_A2A_MatchMoved(id self, SEL _cmd, long long role, id layout) {
    if (G1B_SUPER(BOOL, gA2ASuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout)) return YES;
    id to = G1B_GET(self, kA2ATo), from = G1B_GET(self, kA2AFrom);
    if (layout && to && [layout isEqual:to]) return G1C_A2A_B(self, gA2AConfOff);
    id item = [layout respondsToSelector:@selector(itemForLayoutRole:)] ? G1C_SendLL1x(layout, @selector(itemForLayoutRole:), role) : nil;
    if (!item || ![from respondsToSelector:@selector(containsItem:)] || !G1B_SendB1(from, @selector(containsItem:), item) || !G1B_SendB1(to, @selector(containsItem:), item)) return NO;
    id fa = [G1B_GET(self, kA2AFromMap) objectForKey:item], ta = [G1B_GET(self, kA2AToMap) objectForKey:item];
    if (!fa || !ta || fa == ta) return NO;
    id ca = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    CGSize def = [ca respondsToSelector:@selector(defaultWindowSize)] ? G1C_SendSize0(ca, @selector(defaultWindowSize)) : CGSizeZero;
    double pad = G1B_Dbl0(ca, @selector(screenEdgePadding));
    CGSize s1 = G1C_DM_SizeInBounds(fa, b, def, pad), s2 = G1C_DM_SizeInBounds(ta, b, def, pad);
    if (s1.width != s2.width || s1.height != s2.height) return YES;
    return G1B_SendLL0(fa, @selector(sizingPolicy)) != G1B_SendLL0(ta, @selector(sizingPolicy));
}
static id G1C_A2A_LayoutSettings(id self, SEL _cmd) {                                           // 0x1c75961bc: switcherSettings.chamoisSettings.appToAppLayoutSettings
    id ss = [self respondsToSelector:@selector(switcherSettings)] ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id ch = [ss respondsToSelector:@selector(chamoisSettings)] ? G1B_Send0(ss, @selector(chamoisSettings)) : nil;
    return [ch respondsToSelector:@selector(appToAppLayoutSettings)] ? G1B_Send0(ch, @selector(appToAppLayoutSettings)) : nil;
}
static BOOL G1C_BuildAppToApp(void) {
    Class old = NSClassFromString(@"SBContinuousExposeAppToAppModifier");
    gA2ASuper = old ? class_getSuperclass(old) : NSClassFromString(@"SBTransitionSwitcherModifier");
    if (!gA2ASuper || !G1B_HasSuper(gA2ASuper, @selector(initWithTransitionID:))) return NO;
    const G1BIvar iv[] = {
        { "_continuousExposeConfigurationChangeTransition", sizeof(BOOL), 0, "B" }, { "_commandTabTransition", sizeof(BOOL), 0, "B" },
        { "_launchingFromDockTransition", sizeof(BOOL), 0, "B" },
        { "_fromInterfaceOrientation", sizeof(long long), 3, "q" }, { "_toInterfaceOrientation", sizeof(long long), 3, "q" },
    };
    const G1BMethod m[] = {
        { "initWithTransitionID:fromAppLayout:fromInterfaceOrientation:toAppLayout:toInterfaceOrientation:fromDisplayItemLayoutAttributesMap:toDisplayItemLayoutAttributesMap:", (IMP)G1C_A2A_Init, "@72@0:8@16@24q32@40q48@56@64" },
        { "fromAppLayout", (IMP)G1C_A2A_From, "@16@0:8" }, { "toAppLayout", (IMP)G1C_A2A_To, "@16@0:8" },
        { "fromDisplayItemLayoutAttributesMap", (IMP)G1C_A2A_FromMap, "@16@0:8" }, { "toDisplayItemLayoutAttributesMap", (IMP)G1C_A2A_ToMap, "@16@0:8" },
        { "fromInterfaceOrientation", (IMP)G1C_A2A_FromOri, "q16@0:8" }, { "toInterfaceOrientation", (IMP)G1C_A2A_ToOri, "q16@0:8" },
        { "isContinuousExposeConfigurationChangeTransition", (IMP)G1C_A2A_GetConf, "B16@0:8" }, { "continuousExposeConfigurationChangeTransition", (IMP)G1C_A2A_GetConf, "B16@0:8" },
        { "setContinuousExposeConfigurationChangeTransition:", (IMP)G1C_A2A_SetConf, "v20@0:8B16" },
        { "isCommandTabTransition", (IMP)G1C_A2A_GetCmd, "B16@0:8" }, { "setCommandTabTransition:", (IMP)G1C_A2A_SetCmd, "v20@0:8B16" },
        { "isLaunchingFromDockTransition", (IMP)G1C_A2A_GetDock, "B16@0:8" }, { "setLaunchingFromDockTransition:", (IMP)G1C_A2A_SetDock, "v20@0:8B16" },
        { "didMoveToParentModifier:", (IMP)G1C_A2A_DidMove, "v24@0:8@16" },
        { "asyncRenderingDisabled", (IMP)G1C_A2A_AsyncDisabled, "B16@0:8" },
        { "transitionWillBegin", (IMP)G1C_A2A_WillBegin, "@16@0:8" },
        { "animationAttributesForLayoutElement:", (IMP)G1C_A2A_AnimAttrs, "@24@0:8@16" },
        { "topMostLayoutElements", (IMP)G1C_A2A_TopMost, "@16@0:8" },
        { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_A2A_Opacity, "d40@0:8q16@24Q32" },
        { "perspectiveAngleForAppLayout:", (IMP)G1C_A2A_Perspective, "d24@0:8@16" },
        { "isLayoutRoleMatchMovedToScene:inAppLayout:", (IMP)G1C_A2A_MatchMoved, "B32@0:8q16@24" },
        { "_layoutSettings", (IMP)G1C_A2A_LayoutSettings, "@16@0:8" },
    };
    BOOL made = NO;
    gA2ACls = G1B_MakeClass("BP162ContinuousExposeAppToAppModifier", gA2ASuper, iv, 5, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) {
        gA2AConfOff = G1B_IvarOffset(gA2ACls, "_continuousExposeConfigurationChangeTransition");
        gA2ACmdOff = G1B_IvarOffset(gA2ACls, "_commandTabTransition");
        gA2ADockOff = G1B_IvarOffset(gA2ACls, "_launchingFromDockTransition");
        gA2AFromOriOff = G1B_IvarOffset(gA2ACls, "_fromInterfaceOrientation");
        gA2AToOriOff = G1B_IvarOffset(gA2ACls, "_toInterfaceOrientation");
    }
    return gA2ACls != Nil && gA2AConfOff >= 0 && gA2ACmdOff >= 0 && gA2ADockOff >= 0;
}
// factory used by the Root (16.2 0x1c78185a0..0x1c7818b38): all arguments come from the transition event
static id G1C_NewAppToApp(id event) {
    SEL ini = @selector(initWithTransitionID:fromAppLayout:fromInterfaceOrientation:toAppLayout:toInterfaceOrientation:fromDisplayItemLayoutAttributesMap:toDisplayItemLayoutAttributesMap:);
    if (!gA2ACls || !event || ![gA2ACls instancesRespondToSelector:ini]) return nil;
    id m = ((id (*)(id, SEL, id, id, long long, id, long long, id, id))objc_msgSend)([gA2ACls alloc], ini,
        G1B_Send0(event, @selector(transitionID)), G1B_Send0(event, @selector(fromAppLayout)), G1B_SendLL0(event, @selector(fromInterfaceOrientation)),
        G1B_Send0(event, @selector(toAppLayout)), G1B_SendLL0(event, @selector(toInterfaceOrientation)),
        G1B_Send0(event, @selector(fromDisplayItemLayoutAttributesMap)), G1B_Send0(event, @selector(toDisplayItemLayoutAttributesMap)));
    if (!m) return nil;
    if ([event respondsToSelector:@selector(isContinuousExposeConfigurationChangeEvent)]) G1C_A2A_SetConf(m, 0, G1B_SendB0(event, @selector(isContinuousExposeConfigurationChangeEvent)));
    if ([event respondsToSelector:@selector(isCommandTabTransition)]) G1C_A2A_SetCmd(m, 0, G1B_SendB0(event, @selector(isCommandTabTransition)));
    if ([event respondsToSelector:@selector(isLaunchingFromDockTransition)]) G1C_A2A_SetDock(m, 0, G1B_SendB0(event, @selector(isLaunchingFromDockTransition)));
    return m;
}

// ============================================================================================================
// 2b  SBContinuousExposeSwitcherToAppModifier (16.2: direction + stage-group filtering)                          DONE
// ============================================================================================================
// 16.0: animationAttributesForLayoutElement:, _layoutSettings only. 16.2 adds ivar _direction (+0x88), initWithTransitionID:direction: (0x1c771daec),
// direction, and appLayoutsForContinuousExposeIdentifier: (0x1c771db40): r = [super ...]; stage = [self appLayoutOnContinuousExposeStage];
// if (direction == 0 && stage && BSEqualStrings(stage.continuousExposeIdentifier, identifier)) r = [r bs_filter:^(l){ return ![stage isOrContainsAppLayout:l] && ![l isOrContainsAppLayout:stage]; }]
// i.e. while switching from the all-windows switcher to an app (direction 0) the stage window is not part of its own group's pile. Direction 1 = app -> switcher.
// Run-time SUBCLASS of the 16.0 class (animationAttributes / _layoutSettings are identical in both builds and inherited).
static Class gS2ACls, gS2ABase;
static ptrdiff_t gS2ADirOff = -1;
static id G1C_S2A_Init(id self, SEL _cmd, id tid, long long dir) {
    id me = G1B_SUPER(id, gS2ABase, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (me && gS2ADirOff >= 0) *(long long *)((uint8_t *)(__bridge void *)me + gS2ADirOff) = dir;
    return me;
}
static long long G1C_S2A_Dir(id self, SEL _cmd) { return gS2ADirOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)self + gS2ADirOff); }
static id G1C_S2A_GroupLayouts(id self, SEL _cmd, id ident) {
    id r = G1B_SUPER(id, gS2ABase, self, _cmd, (struct objc_super *, SEL, id), ident);
    SEL stageSel = NSSelectorFromString(@"appLayoutOnContinuousExposeStage");
    id stage = [self respondsToSelector:stageSel] ? G1B_Send0(self, stageSel) : nil;
    if (G1C_S2A_Dir(self, 0) != 0 || !stage || ![r isKindOfClass:[NSArray class]]) return r;
    id sid = [stage respondsToSelector:@selector(continuousExposeIdentifier)] ? G1B_Send0(stage, @selector(continuousExposeIdentifier)) : nil;
    if (!(sid == ident || (sid && [sid isEqual:ident]))) return r;
    NSMutableArray *out = [NSMutableArray array];
    SEL oc = @selector(isOrContainsAppLayout:);
    for (id l in (NSArray *)r) {
        BOOL stageHasL = [stage respondsToSelector:oc] && G1B_SendB1(stage, oc, l);
        BOOL lHasStage = [l respondsToSelector:oc] && G1B_SendB1(l, oc, stage);
        if (!stageHasL && !lHasStage) [out addObject:l];
    }
    return out;
}
static BOOL G1C_BuildSwitcherToApp(void) {
    gS2ABase = NSClassFromString(@"SBContinuousExposeSwitcherToAppModifier");
    if (!gS2ABase || !G1B_HasSuper(gS2ABase, @selector(initWithTransitionID:))) return NO;
    const G1BIvar iv[] = { { "_direction", sizeof(long long), 3, "q" } };
    const G1BMethod m[] = {
        { "initWithTransitionID:direction:", (IMP)G1C_S2A_Init, "@32@0:8@16q24" },
        { "direction", (IMP)G1C_S2A_Dir, "q16@0:8" },
        { "appLayoutsForContinuousExposeIdentifier:", (IMP)G1C_S2A_GroupLayouts, "@24@0:8@16" },
    };
    BOOL made = NO;
    gS2ACls = G1B_MakeClass("BP162ContinuousExposeSwitcherToAppModifier", gS2ABase, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gS2ADirOff = G1B_IvarOffset(gS2ACls, "_direction");
    return gS2ACls != Nil && gS2ADirOff >= 0;
}
static id G1C_NewSwitcherToApp(id tid, long long dir) {
    SEL s = @selector(initWithTransitionID:direction:);
    if (!gS2ACls || ![gS2ACls instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, id, long long))objc_msgSend)([gS2ACls alloc], s, tid, dir);
}
// Overflow root: its transition child uses direction 1 (162 0x1c78bbf18; 16.0 plain initWithTransitionID:)
%group G1C_OverflowRoot
%hook SBRevealContinuousExposeStripOverflowRootSwitcherModifier
- (id)transitionChildModifierForMainTransitionEvent:(id)event activeGestureModifier:(id)modifier {
    id r = %orig;
    if (!G1C_ON() || !gS2ACls || !r || ![r isKindOfClass:gS2ABase]) return r;
    id tid = [event respondsToSelector:@selector(transitionID)] ? G1B_Send0(event, @selector(transitionID)) : nil;
    id n = tid ? G1C_NewSwitcherToApp(tid, 1) : nil;
    return n ?: r;
}
%end
%end

// ============================================================================================================
// 3   Peek family: SBContinuousExposePeekSwitcherModifier, _SBContinuousExposePeekContentSwitcherModifier, SBContinuousExposePeekTransitionModifier        DONE
//     (+ SBSwitcherModifier -frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:, +[SBSwitcherTransitionRequest requestForTapAppLayoutEvent:])
// ============================================================================================================
static id G1C_NewAppSwitcherModifier(void);                       // chunk 80 (AppSwitcherCE rewrite; falls back to the 16.0 class)
static id G1C_NewFullScreenModifier(id appLayout);                 // chunk 90 helper (initWithFullScreenAppLayout:)
static id G1C_NewWindowDragModifier(id gid, id initial, id item);   // chunk 80
static Class gPeekCls, gPeekContentCls, gPeekTransCls, gPeekSuper, gPeekTransSuper;
static ptrdiff_t gPeekCfgOff = -1, gPeekContentCfgOff = -1, gPeekTransDirOff = -1;
static char kPkContent, kPkDismissal, kPkLayout, kPkcFS, kPkcAS, kPkcLayout, kPtFromFS, kPtToFS, kPtFrom, kPtTo;

// ---- SBSwitcherModifier -frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole: (162 0x1c76530f8) ----
// Places a peeking window mostly off-screen on its side: onLeft = (item is the stage's first (front) item) == (first item centre is left of the model's container centre)
//   x = onLeft ? (containerViewBounds.minX + 2*pad - default.w) : (containerViewBounds.maxX - 2*pad), then x += -0.5 * (containerViewBounds.w - bounds.w); y/w/h from the default frame.
static CGRect G1C_Peek_FrameForPeekingItem(id self, SEL _cmd, id item, id layout, CGRect bounds, CGRect def) {
    id model = [self respondsToSelector:@selector(overlappingModelForAppLayout:)] ? G1B_Send1(self, @selector(overlappingModelForAppLayout:), layout) : nil;
    NSArray *z = [model respondsToSelector:@selector(zOrderedItems)] ? G1B_Send0(model, @selector(zOrderedItems)) : nil;
    id first = z.firstObject;
    CGRect cvb = G1C_SendRect0(self, @selector(containerViewBounds));
    double firstX = 0, cx = cvb.origin.x + cvb.size.width * 0.5;
    if (first && [model respondsToSelector:@selector(centerForItem:)]) firstX = ((CGPoint (*)(id, SEL, id))objc_msgSend)(model, @selector(centerForItem:), first).x;
    CGRect mb = [model respondsToSelector:@selector(containerBounds)] ? G1C_SendRect0(model, @selector(containerBounds)) : cvb;
    cx = mb.origin.x + mb.size.width * 0.5;
    BOOL isFirst = item && first && [item isEqual:first];
    BOOL onLeft = (firstX < cx) ? isFirst : !isFirst;
    id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    double pad2 = 2.0 * G1B_Dbl0(attrs, @selector(screenEdgePadding));
    double x = onLeft ? (cvb.origin.x - def.size.width + pad2) : (cvb.origin.x + cvb.size.width - pad2);
    x += -0.5 * (cvb.size.width - bounds.size.width);
    return CGRectMake(x, def.origin.y, def.size.width, def.size.height);
}
// +[SBSwitcherTransitionRequest requestForTapAppLayoutEvent:] (162 0x1c740d6fc): new mutable request, appLayout = event.appLayout, activatingDisplayItem = item for the tapped role,
// source 0x33 when event.source == 1. 16.0 requests have no activatingDisplayItem: it is kept as an associated object (consumed by the FullScreen port / coordinator when present).
static char kReqActItem;
static id G1C_Req_ForTap(id cls, SEL _cmd, id event) {
    id l = [event respondsToSelector:@selector(appLayout)] ? G1B_Send0(event, @selector(appLayout)) : nil;
    long long role = [event respondsToSelector:@selector(layoutRole)] ? G1B_SendLL0(event, @selector(layoutRole)) : 0;
    Class mc = NSClassFromString(@"SBMutableSwitcherTransitionRequest");
    id r = mc ? [[mc alloc] init] : nil;
    if (!r || !l) return r;
    if ([r respondsToSelector:@selector(setAppLayout:)]) G1B_SendV1(r, @selector(setAppLayout:), l);
    id item = [l respondsToSelector:@selector(itemForLayoutRole:)] ? G1C_SendLL1x(l, @selector(itemForLayoutRole:), role) : nil;
    if ([r respondsToSelector:NSSelectorFromString(@"setActivatingDisplayItem:")]) G1B_SendV1(r, NSSelectorFromString(@"setActivatingDisplayItem:"), item);
    else if (item) G1B_SET(r, kReqActItem, item);
    if ([event respondsToSelector:@selector(source)] && G1B_SendLL0(event, @selector(source)) == 1 && [r respondsToSelector:@selector(setSource:)]) G1B_SendVLL(r, @selector(setSource:), 0x33);
    return r;
}
static long long G1C_TapEv_Zero(id s, SEL c) { return 0; }
static void G1C_InstallPeekSupport(void) {
    Class sm = objc_getClass("SBSwitcherModifier");
    if (sm && !class_getInstanceMethod(sm, NSSelectorFromString(@"frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:")))
        class_addMethod(sm, NSSelectorFromString(@"frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:"), (IMP)G1C_Peek_FrameForPeekingItem,
            "{CGRect={CGPoint=dd}{CGSize=dd}}104@0:8@16@24{CGRect={CGPoint=dd}{CGSize=dd}}32{CGRect={CGPoint=dd}{CGSize=dd}}64");
    Class rq = objc_getClass("SBSwitcherTransitionRequest");
    if (rq && !class_getClassMethod(rq, NSSelectorFromString(@"requestForTapAppLayoutEvent:"))) class_addMethod(object_getClass(rq), NSSelectorFromString(@"requestForTapAppLayoutEvent:"), (IMP)G1C_Req_ForTap, "@24@0:8@16");
    Class te = objc_getClass("SBTapAppLayoutSwitcherModifierEvent");
    if (te) {
        if (!G1C_HasOwn(te, @selector(source))) class_addMethod(te, @selector(source), (IMP)G1C_TapEv_Zero, "q16@0:8");
        if (!G1C_HasOwn(te, @selector(modifierFlags))) class_addMethod(te, @selector(modifierFlags), (IMP)G1C_TapEv_Zero, "q16@0:8");
    }
}

// ---- SBContinuousExposePeekTransitionModifier (16.2 ivars: _fromFullScreenContinuousExposeModifier +0x88, _toFull... +0x90, _fromAppLayout +0x98, _toAppLayout +0xa0, _direction +0xa8) ----
// direction 0 = peek presentation (only animationAttributesForLayoutElement: differs from the base), 1 = dismissal (everything below, phase >= 2).
static id G1C_PT_From(id s) { return G1B_GET(s, kPtFrom); }
static id G1C_PT_To(id s) { return G1B_GET(s, kPtTo); }
static long long G1C_PT_Dir(id s) { return gPeekTransDirOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)s + gPeekTransDirOff); }
static BOOL G1C_PT_Phase2(id s) { return [s respondsToSelector:@selector(transitionPhase)] && G1B_SendLL0(s, @selector(transitionPhase)) >= 2; }
static BOOL G1C_PT_Any(id a, id b) { return a && b && [a respondsToSelector:@selector(containsAnyItemFromAppLayout:)] && G1B_SendB1(a, @selector(containsAnyItemFromAppLayout:), b); }
static id G1C_PT_Init(id self, SEL _cmd, id tid, id from, id to, long long dir) {
    if (!from) return nil;                                                                      // NSAssert fromAppLayout (SBContinuousExposePeekTransitionModifier.m:0x18)
    id me = G1B_SUPER(id, gPeekTransSuper, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (!me || gPeekTransDirOff < 0) return nil;
    G1B_SET(me, kPtFrom, from); G1B_SET(me, kPtTo, to);
    *(long long *)((uint8_t *)(__bridge void *)me + gPeekTransDirOff) = dir;
    id fs = G1C_NewFullScreenModifier(from);
    G1B_SET(me, kPtFromFS, fs);
    if (dir == 1 && to) G1B_SET(me, kPtToFS, G1C_NewFullScreenModifier(to));
    return me;
}
static id G1C_PT_FromGetter(id s, SEL c) { return G1C_PT_From(s); }
static id G1C_PT_ToGetter(id s, SEL c) { return G1C_PT_To(s); }
static long long G1C_PT_DirGetter(id s, SEL c) { return G1C_PT_Dir(s); }
static id G1C_PT_Visible(id self, SEL _cmd) {
    id r = G1B_SUPER(id, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL));
    if (G1C_PT_Dir(self) == 1 && G1C_PT_From(self) && [r respondsToSelector:@selector(setByAddingObject:)]) return G1B_Send1(r, @selector(setByAddingObject:), G1C_PT_From(self));
    return r;
}
// evaluate `[child sel:args]` with `child` attached temporarily (blocks 0x1c76edea0 / 0x1c76edee8 / 0x1c76ee198 / 0x1c76ee1dc / 0x1c76ee510 / 0x1c76ee6f0)
static void G1C_PT_With(id self, id child, void (^b)(void)) {
    if (!child || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)]) return;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), child, b);
}
static id G1C_PT_Layout(id self, unsigned long long i) {
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    return i < a.count ? a[i] : nil;
}
// which full-screen modifier answers per-index queries in the dismissal: 1 = from (the dismissed window, not in `to`), 2 = to (windows in both), 0 = base
static int G1C_PT_Pick(id self, id layout) {
    if (G1C_PT_Dir(self) != 1 || !G1C_PT_Phase2(self)) return 0;
    id from = G1C_PT_From(self), to = G1C_PT_To(self);
    if (layout && from && [layout isEqual:from] && !G1C_PT_Any(layout, to)) return 1;
    if (G1B_GET(self, kPtToFS) && G1C_PT_Any(layout, to) && G1C_PT_Any(layout, from)) return 2;
    return 0;
}
static CGRect G1C_PT_Frame(id self, SEL _cmd, unsigned long long i) {
    int p = G1C_PT_Pick(self, G1C_PT_Layout(self, i));
    if (p) {
        id fs = objc_getAssociatedObject(self, p == 1 ? &kPtFromFS : &kPtToFS);
        __block CGRect r = CGRectZero; __block BOOL got = NO;
        G1C_PT_With(self, fs, ^{ r = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(fs, @selector(frameForIndex:), i); got = YES; });
        if (got) return r;
    }
    return G1B_SUPER(CGRect, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_PT_Scale(id self, SEL _cmd, unsigned long long i) {
    int p = G1C_PT_Pick(self, G1C_PT_Layout(self, i));
    if (p) {
        id fs = objc_getAssociatedObject(self, p == 1 ? &kPtFromFS : &kPtToFS);
        __block double r = 1; __block BOOL got = NO;
        G1C_PT_With(self, fs, ^{ r = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(fs, @selector(scaleForIndex:), i); got = YES; });
        if (got) return r;
    }
    return G1B_SUPER(double, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGRect G1C_PT_FrameRole(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    CGRect r = G1B_SUPER(CGRect, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds);
    if (G1C_PT_Dir(self) != 1 || !G1C_PT_Phase2(self)) return r;
    id from = G1C_PT_From(self), to = G1C_PT_To(self);
    if (layout && from && [layout isEqual:from] && !G1C_PT_Any(layout, to)) {
        id item = [layout respondsToSelector:@selector(itemForLayoutRole:)] ? G1C_SendLL1x(layout, @selector(itemForLayoutRole:), role) : nil;
        SEL ps = NSSelectorFromString(@"frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:");
        if ([self respondsToSelector:ps]) r = ((CGRect (*)(id, SEL, id, id, CGRect, CGRect))objc_msgSend)(self, ps, item, layout, bounds, r);
        // slide outward toward the nearer screen edge by 4 * screenEdgePadding
        CGRect cvb = G1C_SendRect0(self, @selector(containerViewBounds));
        id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
        double off = 4.0 * G1B_Dbl0(attrs, @selector(screenEdgePadding));
        double cx = r.origin.x + r.size.width * 0.5, ccx = cvb.origin.x + cvb.size.width * 0.5;
        r.origin.x += (cx < ccx) ? -off : off;
        return r;
    }
    if (G1B_GET(self, kPtToFS) && G1C_PT_Any(layout, to) && G1C_PT_Any(layout, from)) {
        id fs = G1B_GET(self, kPtToFS);
        __block CGRect b2 = r;
        G1C_PT_With(self, fs, ^{ b2 = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(fs, @selector(frameForLayoutRole:inAppLayout:withBounds:), role, layout, bounds); });
        return b2;
    }
    return r;
}
static double G1C_PT_ScaleRole(id self, SEL _cmd, long long role, id layout) {
    id from = G1C_PT_From(self), to = G1C_PT_To(self);
    if (G1C_PT_Dir(self) == 1 && G1C_PT_Phase2(self) && G1B_GET(self, kPtToFS) && G1C_PT_Any(layout, to) && G1C_PT_Any(layout, from)) {
        id fs = G1B_GET(self, kPtToFS);
        __block double s = 1;
        G1C_PT_With(self, fs, ^{ s = ((double (*)(id, SEL, long long, id))objc_msgSend)(fs, @selector(scaleForLayoutRole:inAppLayout:), role, layout); });
        return s;
    }
    return G1B_SUPER(double, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static id G1C_PT_TopMost(id self, SEL _cmd) {
    id r = G1B_SUPER(id, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL));
    id from = G1C_PT_From(self), to = G1C_PT_To(self);
    if (G1C_PT_Dir(self) != 1 || !to || !from || G1B_SendB1(from, @selector(containsAllItemsFromAppLayout:), to)) return r;
    SEL pass = @selector(appLayoutWithItemsPassingTest:), ins = NSSelectorFromString(@"sb_arrayByInsertingOrMovingObject:toIndex:");
    if (![to respondsToSelector:pass] || ![r respondsToSelector:ins]) return r;
    id peeked = ((id (*)(id, SEL, BOOL (^)(id)))objc_msgSend)(to, pass, ^BOOL(id item) { return ![from respondsToSelector:@selector(containsItem:)] || !G1B_SendB1(from, @selector(containsItem:), item); });
    return peeked ? ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(r, ins, peeked, 0) : r;
}
static BOOL G1C_PT_MatchMoved(id self, SEL _cmd, long long role, id layout) {
    id from = G1C_PT_From(self), to = G1C_PT_To(self);
    if (G1C_PT_Dir(self) == 1 && G1C_PT_Any(to, from) && (G1C_PT_Any(to, layout) || G1C_PT_Any(from, layout))) return YES;
    return G1B_SUPER(BOOL, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static id G1C_PT_Anim(id self, SEL _cmd, id element) {                  // 0x1c76ee958: does NOT call super
    Class mc = NSClassFromString(@"SBMutableSwitcherAnimationAttributes");
    id a = mc ? [[mc alloc] init] : nil;
    if (!a) return G1B_SUPER(id, gPeekTransSuper, self, _cmd, (struct objc_super *, SEL, id), element);
    if ([a respondsToSelector:@selector(setUpdateMode:)]) G1B_SendVLL(a, @selector(setUpdateMode:), 3);
    id ss = [self respondsToSelector:@selector(switcherSettings)] ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id ch = [ss respondsToSelector:@selector(chamoisSettings)] ? G1B_Send0(ss, @selector(chamoisSettings)) : nil;
    id a2a = [ch respondsToSelector:@selector(appToAppLayoutSettings)] ? G1B_Send0(ch, @selector(appToAppLayoutSettings)) : nil;
    if (a2a && [a respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(a, @selector(setLayoutSettings:), a2a);
    return a;
}
static BOOL G1C_BuildPeekTransition(void) {
    gPeekTransSuper = NSClassFromString(@"SBTransitionSwitcherModifier");
    if (!gPeekTransSuper || !G1B_HasSuper(gPeekTransSuper, @selector(initWithTransitionID:))) return NO;
    const G1BIvar iv[] = { { "_direction", sizeof(long long), 3, "q" } };
    const G1BMethod m[] = {
        { "initWithTransitionID:fromAppLayout:toAppLayout:direction:", (IMP)G1C_PT_Init, "@48@0:8@16@24@32q40" },
        { "fromAppLayout", (IMP)G1C_PT_FromGetter, "@16@0:8" }, { "toAppLayout", (IMP)G1C_PT_ToGetter, "@16@0:8" }, { "direction", (IMP)G1C_PT_DirGetter, "q16@0:8" },
        { "visibleAppLayouts", (IMP)G1C_PT_Visible, "@16@0:8" },
        { "frameForIndex:", (IMP)G1C_PT_Frame, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
        { "scaleForIndex:", (IMP)G1C_PT_Scale, "d24@0:8Q16" },
        { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_PT_FrameRole, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32" },
        { "scaleForLayoutRole:inAppLayout:", (IMP)G1C_PT_ScaleRole, "d32@0:8q16@24" },
        { "topMostLayoutElements", (IMP)G1C_PT_TopMost, "@16@0:8" },
        { "isLayoutRoleMatchMovedToScene:inAppLayout:", (IMP)G1C_PT_MatchMoved, "B32@0:8q16@24" },
        { "animationAttributesForLayoutElement:", (IMP)G1C_PT_Anim, "@24@0:8@16" },
    };
    BOOL made = NO;
    gPeekTransCls = G1B_MakeClass("SBContinuousExposePeekTransitionModifier", gPeekTransSuper, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gPeekTransDirOff = G1B_IvarOffset(gPeekTransCls, "_direction");
    return gPeekTransCls != Nil && gPeekTransDirOff >= 0;
}

// ---- _SBContinuousExposePeekContentSwitcherModifier (ivars: _fullScreenContinuousExposeAppLayoutModifier +0x60, _appSwitcherModifier +0x68, _appLayout +0x70, _configuration +0x78) ----
static id G1C_PC_Init(id self, SEL _cmd, id layout, long long cfg) {
    if (!layout) return nil;                                                                    // NSAssert appLayout (SBContinuousExposePeekSwitcherModifier.m:0xaf)
    id me = G1B_SUPER(id, gPeekSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kPkcLayout, layout);
    if (gPeekContentCfgOff >= 0) *(long long *)((uint8_t *)(__bridge void *)me + gPeekContentCfgOff) = cfg;
    SEL add = @selector(addChildModifier:atLevel:key:), noTap = @selector(setHandlesTapAppLayoutEvents:), noHdr = @selector(setHandlesTapAppLayoutHeaderEvents:);
    id fs = G1C_NewFullScreenModifier(layout);
    if (fs) {
        G1B_SET(me, kPkcFS, fs);
        if ([fs respondsToSelector:noTap]) G1C_SendVB(fs, noTap, NO);
        if ([fs respondsToSelector:noHdr]) G1C_SendVB(fs, noHdr, NO);
        ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, add, fs, 0, nil);
    }
    id as = G1C_NewAppSwitcherModifier();
    if (as) {
        G1B_SET(me, kPkcAS, as);
        if ([as respondsToSelector:noTap]) G1C_SendVB(as, noTap, NO);
        if ([as respondsToSelector:noHdr]) G1C_SendVB(as, noHdr, NO);
        ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, add, as, 1, nil);
    }
    return me;
}
static id G1C_PC_Layout(id s, SEL c) { return G1B_GET(s, kPkcLayout); }
static long long G1C_PC_Cfg(id s, SEL c) { return gPeekContentCfgOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)s + gPeekContentCfgOff); }
static id G1C_PC_Adjusted(id self, SEL _cmd, id layouts) {                  // peeked layout first, then the rest (blocks 0x1c78e5cc0 / 0x1c78e5cd8)
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id), layouts);
    id mine = G1B_GET(self, kPkcLayout);
    if (![r isKindOfClass:[NSArray class]] || !mine) return r;
    NSMutableArray *a = [NSMutableArray array], *b = [NSMutableArray array];
    for (id l in (NSArray *)r) [([mine isEqual:l] ? a : b) addObject:l];
    return [a arrayByAddingObjectsFromArray:b];
}
static CGRect G1C_PC_FrameRole(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    CGRect r = G1B_SUPER(CGRect, gPeekSuper, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds);
    id mine = G1B_GET(self, kPkcLayout);
    if (mine && layout && [layout isEqual:mine]) {
        id item = [layout respondsToSelector:@selector(itemForLayoutRole:)] ? G1C_SendLL1x(layout, @selector(itemForLayoutRole:), role) : nil;
        SEL ps = NSSelectorFromString(@"frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:");
        if ([self respondsToSelector:ps]) r = ((CGRect (*)(id, SEL, id, id, CGRect, CGRect))objc_msgSend)(self, ps, item, layout, bounds, r);
    }
    return r;
}
static double G1C_PC_ScaleRole(id self, SEL _cmd, long long role, id layout) {
    id mine = G1B_GET(self, kPkcLayout);
    if (mine && layout && [layout isEqual:mine]) return 1.0;
    return G1B_SUPER(double, gPeekSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static BOOL G1C_PC_AllowTouches(id self, SEL _cmd, long long role, id layout) {
    id mine = G1B_GET(self, kPkcLayout);
    if (mine && layout && [layout isEqual:mine]) return NO;
    return G1B_SUPER(BOOL, gPeekSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static BOOL G1C_PC_Selectable(id self, SEL _cmd, long long role, id layout) { return YES; }
static BOOL G1C_PC_Opaque(id self, SEL _cmd) { return NO; }
static id G1C_PC_Tap(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    Class rq = NSClassFromString(@"SBSwitcherTransitionRequest"), pc = NSClassFromString(@"SBPerformTransitionSwitcherEventResponse");
    SEL rs = NSSelectorFromString(@"requestForTapAppLayoutEvent:"), ps = @selector(initWithTransitionRequest:gestureInitiated:);
    if (!rq || !pc || ![rq respondsToSelector:rs] || ![pc instancesRespondToSelector:ps]) return r;
    id req = G1B_Send1((id)rq, rs, event);
    if (!req) return r;
    if ([req respondsToSelector:@selector(setPeekConfiguration:)]) G1B_SendVLL(req, @selector(setPeekConfiguration:), 1);
    id perform = ((id (*)(id, SEL, id, BOOL))objc_msgSend)([pc alloc], ps, req, NO);
    return perform ? G1B_Append(perform, r) : r;
}
static id G1C_PC_ChildResponse(id self, SEL _cmd, id proposed, id child, id event) {
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id, id, id), proposed, child, event);
    id fs = G1B_GET(self, kPkcFS), as = G1B_GET(self, kPkcAS);
    if (fs && child == fs && [event respondsToSelector:@selector(type)] && G1B_SendLL0(event, @selector(type)) == 18) return nil;      // tap-app-layout events never leave the peek
    if (as && child == as) return nil;                                                                                                    // the app switcher child is only there for geometry
    return r;
}
static id G1C_PC_Keyboard(id self, SEL _cmd) { return G1C_Cls0(@"SBSwitcherKeyboardSuppressionMode", NSSelectorFromString(@"suppressionModeForAllScenes")); }
static BOOL G1C_BuildPeekContent(void) {
    if (!gPeekSuper) return NO;
    const G1BIvar iv[] = { { "_configuration", sizeof(long long), 3, "q" } };
    const G1BMethod m[] = {
        { "initWithAppLayout:configuration:", (IMP)G1C_PC_Init, "@32@0:8@16q24" },
        { "appLayout", (IMP)G1C_PC_Layout, "@16@0:8" }, { "configuration", (IMP)G1C_PC_Cfg, "q16@0:8" },
        { "adjustedAppLayoutsForAppLayouts:", (IMP)G1C_PC_Adjusted, "@24@0:8@16" },
        { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_PC_FrameRole, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32" },
        { "scaleForLayoutRole:inAppLayout:", (IMP)G1C_PC_ScaleRole, "d32@0:8q16@24" },
        { "shouldAllowContentViewTouchesForLayoutRole:inAppLayout:", (IMP)G1C_PC_AllowTouches, "B32@0:8q16@24" },
        { "isLayoutRoleSelectable:inAppLayout:", (IMP)G1C_PC_Selectable, "B32@0:8q16@24" },
        { "switcherHitTestsAsOpaque", (IMP)G1C_PC_Opaque, "B16@0:8" },
        { "handleTapAppLayoutEvent:", (IMP)G1C_PC_Tap, "@24@0:8@16" },
        { "responseForProposedChildResponse:childModifier:event:", (IMP)G1C_PC_ChildResponse, "@40@0:8@16@24@32" },
        { "keyboardSuppressionMode", (IMP)G1C_PC_Keyboard, "@16@0:8" },
    };
    BOOL made = NO;
    gPeekContentCls = G1B_MakeClass("_SBContinuousExposePeekContentSwitcherModifier", gPeekSuper, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gPeekContentCfgOff = G1B_IvarOffset(gPeekContentCls, "_configuration");
    return gPeekContentCls != Nil && gPeekContentCfgOff >= 0;
}

// ---- SBContinuousExposePeekSwitcherModifier (ivars: _contentModifier +0x60, _dismissalTransitionModifier +0x68, _appLayout +0x70, _configuration +0x78) ----
static NSString *const kG1CUserScrollKey = @"UserScrollingModifier";
static id G1C_PK_Init(id self, SEL _cmd, id layout, long long cfg) {
    if (!layout || !gPeekContentCls || !gFilteringCls) return nil;                              // 16.2 NSAssert (SBContinuousExposePeekSwitcherModifier.m:0x2c)
    id me = G1B_SUPER(id, gPeekSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kPkLayout, layout);
    if (gPeekCfgOff >= 0) *(long long *)((uint8_t *)(__bridge void *)me + gPeekCfgOff) = cfg;
    id content = ((id (*)(id, SEL, id, long long))objc_msgSend)([gPeekContentCls alloc], @selector(initWithAppLayout:configuration:), layout, cfg);
    if (!content) return nil;
    G1B_SET(me, kPkContent, content);
    id filt = ((id (*)(id, SEL, id, id))objc_msgSend)([gFilteringCls alloc], @selector(initWithAppLayouts:modifier:), @[ layout ], content);
    if (filt && [me respondsToSelector:@selector(addChildModifier:)]) G1B_SendV1(me, @selector(addChildModifier:), filt);
    return me;
}
static id G1C_PK_Layout(id s, SEL c) { return G1B_GET(s, kPkLayout); }
static long long G1C_PK_Cfg(id s, SEL c) { return gPeekCfgOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)s + gPeekCfgOff); }
static id G1C_PK_DebugChildren(id s, SEL c) { id m = G1B_GET(s, kPkContent); return m ? @[ m ] : @[]; }
static id G1C_PK_Ensure(id s, SEL c, id e) { return @[]; }
static void G1C_PK_SetState(id self, SEL _cmd, long long st) {
    if (st == 1 && G1B_SendLL0(self, @selector(state)) != 1 && [self respondsToSelector:@selector(newAppLayoutsGenCount)]) (void)G1B_SendLL0(self, @selector(newAppLayoutsGenCount));
    G1B_SUPER(void, gPeekSuper, self, _cmd, (struct objc_super *, SEL, long long), st);
}
static id G1C_NewInvalidateAdjusted(void) {
    Class c = NSClassFromString(@"SBInvalidateAdjustedAppLayoutsSwitcherEventResponse");
    return c ? [[c alloc] init] : nil;
}
static id G1C_PK_HandleEvent(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    id d = G1B_GET(self, kPkDismissal);
    if (d && G1B_SendLL0(d, @selector(state)) == 1) {
        id inv = G1C_NewInvalidateAdjusted();
        if (inv) r = G1B_Append(inv, r);
        G1B_SendVLL(self, @selector(setState:), 1);
    }
    return r;
}
static BOOL G1C_PeekValid(long long cfg) { return (cfg & ~1LL) == 2; }   // _SBPeekConfigurationIsValid 162 0x1c77229fc: (cfg & ~1) == 2, i.e. configurations 2 and 3
static BOOL (*gPeekIsValidFn)(long long);
static BOOL G1C_PeekIsValid(long long cfg) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gPeekIsValidFn = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "SBPeekConfigurationIsValid"); });
    return gPeekIsValidFn ? gPeekIsValidFn(cfg) : G1C_PeekValid(cfg);
}
// 0x1c78e5410 (decoded registers: x25 animated, x27 toPeekValid, x26 fromPeekValid)
static id G1C_PK_HandleTransition(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    long long phase = G1B_SendLL0(event, @selector(phase));
    BOOL animated = G1B_SendB0(event, @selector(isAnimated));
    BOOL toValid = [event respondsToSelector:@selector(toPeekConfiguration)] && G1C_PeekIsValid(G1B_SendLL0(event, @selector(toPeekConfiguration)));
    BOOL fromValid = [event respondsToSelector:@selector(fromPeekConfiguration)] && G1C_PeekIsValid(G1B_SendLL0(event, @selector(fromPeekConfiguration)));
    id from = G1B_Send0(event, @selector(fromAppLayout)), to = G1B_Send0(event, @selector(toAppLayout));
    id tid = G1B_Send0(event, @selector(transitionID));
    SEL ini = @selector(initWithTransitionID:fromAppLayout:toAppLayout:direction:);
    if (gPeekTransCls && phase == 2 && animated && toValid && !fromValid) {                      // presentation
        id t = ((id (*)(id, SEL, id, id, id, long long))objc_msgSend)([gPeekTransCls alloc], ini, tid, from, to, 0);
        if (t) G1B_SendV1(self, @selector(addChildModifier:), t);
    } else if (gPeekTransCls && phase == 2 && animated && !toValid && fromValid) {               // dismissal
        id t = ((id (*)(id, SEL, id, id, id, long long))objc_msgSend)([gPeekTransCls alloc], ini, tid, from, to, 1);
        G1B_SET(self, kPkDismissal, t);
        if (t) G1B_SendV1(self, @selector(addChildModifier:), t);
    }
    if (phase == 3 && !animated && !toValid) {                                                   // non-animated end
        id inv = G1C_NewInvalidateAdjusted();
        if (inv) r = G1B_Append(inv, r);
        G1B_SendVLL(self, @selector(setState:), 1);
    }
    if ((phase == 2 || !animated) && toValid && !fromValid) {                                    // start of a presentation (also the non-animated one)
        id inv = G1C_NewInvalidateAdjusted();
        if (inv) r = G1B_Append(inv, r);
    }
    return r;
}
static id G1C_PK_HandleScroll(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1B_SendLL0(event, @selector(phase)) == 0 && [event respondsToSelector:@selector(isUserInitiated)] && G1B_SendB0(event, @selector(isUserInitiated))
        && [self respondsToSelector:@selector(childModifierByKey:)] && !G1B_Send1(self, @selector(childModifierByKey:), kG1CUserScrollKey)) {
        Class sc = NSClassFromString(@"SBScrollingSwitcherModifier");
        id s = sc ? [[sc alloc] init] : nil;
        if (s) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(self, @selector(addChildModifier:atLevel:key:), s, 0, kG1CUserScrollKey);
    }
    return r;
}
static id G1C_PK_GroupLayouts(id self, SEL _cmd, id ident) {                // block 0x1c78e591c: drop layouts sharing an item with the peeked layout
    id r = G1B_SUPER(id, gPeekSuper, self, _cmd, (struct objc_super *, SEL, id), ident);
    id mine = G1B_GET(self, kPkLayout);
    id myId = [mine respondsToSelector:@selector(continuousExposeIdentifier)] ? G1B_Send0(mine, @selector(continuousExposeIdentifier)) : nil;
    if (!(myId == ident || (myId && [myId isEqual:ident])) || ![r isKindOfClass:[NSArray class]]) return r;
    NSMutableArray *out = [NSMutableArray array];
    for (id l in (NSArray *)r) if (!G1C_PT_Any(l, mine)) [out addObject:l];
    return out;
}
static BOOL G1C_PK_Visible(id self, SEL _cmd) { return YES; }
static unsigned long long G1C_PK_CompletionOptions(id self, SEL _cmd) {
    return ([self respondsToSelector:@selector(isReduceMotionEnabled)] && G1B_SendB0(self, @selector(isReduceMotionEnabled))) ? 6 : 2;
}
static BOOL G1C_BuildPeekFamily(void) {
    gPeekSuper = NSClassFromString(@"SBSwitcherModifier");
    if (!gPeekSuper || !gFilteringCls) return NO;
    G1C_InstallPeekSupport();
    BOOL a = G1C_BuildPeekTransition(), b = G1C_BuildPeekContent();
    if (!a || !b) return NO;
    const G1BIvar iv[] = { { "_configuration", sizeof(long long), 3, "q" } };
    const G1BMethod m[] = {
        { "initWithAppLayout:configuration:", (IMP)G1C_PK_Init, "@32@0:8@16q24" },
        { "appLayout", (IMP)G1C_PK_Layout, "@16@0:8" }, { "configuration", (IMP)G1C_PK_Cfg, "q16@0:8" },
        { "debugPotentialChildModifiers", (IMP)G1C_PK_DebugChildren, "@16@0:8" },
        { "appLayoutsToEnsureExistForMainTransitionEvent:", (IMP)G1C_PK_Ensure, "@24@0:8@16" },
        { "setState:", (IMP)G1C_PK_SetState, "v24@0:8q16" },
        { "handleEvent:", (IMP)G1C_PK_HandleEvent, "@24@0:8@16" },
        { "handleTransitionEvent:", (IMP)G1C_PK_HandleTransition, "@24@0:8@16" },
        { "handleScrollEvent:", (IMP)G1C_PK_HandleScroll, "@24@0:8@16" },
        { "appLayoutsForContinuousExposeIdentifier:", (IMP)G1C_PK_GroupLayouts, "@24@0:8@16" },
        { "isSwitcherWindowVisible", (IMP)G1C_PK_Visible, "B16@0:8" },
        { "transactionCompletionOptions", (IMP)G1C_PK_CompletionOptions, "Q16@0:8" },
    };
    BOOL made = NO;
    gPeekCls = G1B_MakeClass("SBContinuousExposePeekSwitcherModifier", gPeekSuper, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gPeekCfgOff = G1B_IvarOffset(gPeekCls, "_configuration");
    return gPeekCls != Nil && gPeekCfgOff >= 0;
}
// factory used by the Root's handleTransitionEvent: (item 2)
static id G1C_NewPeekModifier(id appLayout, long long cfg) {
    SEL s = @selector(initWithAppLayout:configuration:);
    if (!gPeekCls || !appLayout || ![gPeekCls instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, id, long long))objc_msgSend)([gPeekCls alloc], s, appLayout, cfg);
}

// ============================================================================================================
// 4   App drag-and-drop family: SBContinuousExposeDragAndDropGestureRootSwitcherModifier, SBContinuousExposeAppDragAndDropGestureSwitcherModifier,
//     _SBContinuousExposeWindowDragContentSwitcherModifier                                                              DONE
// ============================================================================================================
// 16.0 gesture type 7 = SBContinuousExposePendingEvictionRootSwitcherModifier (removed in 16.2). Events of type 5 (SBDragAndDropGestureSwitcherModifierEvent),
// 22 (resize progress), 23 (blur progress) and 25 (scene ready) and SBUpdateDragPlatterBlurSwitcherEventResponse exist in both builds (event class diff: identical).
static id G1C_NewWindowDragContentFor(id gid, id initial, id item);                 // chunk 80
static Class gDndRootCls, gDndRootSuper, gDndCls, gDndSuper, gWdContentCls, gWdContentSuper;
static ptrdiff_t gDndOff[24];
enum { DND_SHOULD_PUSH, DND_RESIZING, DND_RESIZED_ENOUGH, DND_BLURRING, DND_BLURRED, DND_NEEDS_BLUR, DND_ENDED, DND_HAS_PLATTER, DND_HAS_LIFTED, DND_DROP_ACTION, DND_SCENE_ROLE, DND_PLATTER_FRAME, DND_LOCATION };
static char kDndInitial, kDndLayout, kDndEvict, kDndDropFrom, kDndTrans, kDndSceneId;
static BOOL G1C_Dnd_B(id s, int k) { return gDndOff[k] >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)s + gDndOff[k]); }
static void G1C_Dnd_SetB(id s, int k, BOOL v) { if (gDndOff[k] >= 0) *(BOOL *)((uint8_t *)(__bridge void *)s + gDndOff[k]) = v; }
static long long G1C_Dnd_LL(id s, int k) { return gDndOff[k] >= 0 ? *(long long *)((uint8_t *)(__bridge void *)s + gDndOff[k]) : 0; }
static BOOL G1C_FIsOne(double v) { return fabs(v - 1.0) < 1e-6; }

// ---- gesture root (gesture type 7; ivar _appLayout +0x80; 162 0x1c7970ed8) ----
static char kDndRootLayout;
static id G1C_DndRoot_Init(id self, SEL _cmd, long long mode, id layout) {
    if (mode == 3 && !layout) return nil;                                          // NSAssert (…DragAndDropGestureRootSwitcherModifier.m:0x1d)
    id me = G1B_SUPER(id, gDndRootSuper, self, @selector(initWithStartingEnvironmentMode:), (struct objc_super *, SEL, long long), mode);
    if (me) G1B_SET(me, kDndRootLayout, layout);
    return me;
}
static long long G1C_DndRoot_Type(id self, SEL _cmd) { return 7; }
// 0x1c7970fc4: when the stage is full (items on stage >= chamoisSettings.maximumNumberOfAppsOnStage) the item with the oldest lastInteractionTime would be evicted by a drop
static id G1C_DndRoot_Child(id self, SEL _cmd, id event, id activeTransition) {
    id evicted = nil, layout = G1B_GET(self, kDndRootLayout);
    if (!gDndCls || ![self respondsToSelector:@selector(currentEnvironmentMode)] || G1B_SendLL0(self, @selector(currentEnvironmentMode)) != 3 || !layout) return nil;
    id dom = G1C_Cls0(@"SBAppSwitcherDomain", NSSelectorFromString(@"rootSettings"));
    id ch = [dom respondsToSelector:@selector(chamoisSettings)] ? G1B_Send0(dom, @selector(chamoisSettings)) : nil;
    unsigned long long maxApps = [ch respondsToSelector:@selector(maximumNumberOfAppsOnStage)] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(ch, @selector(maximumNumberOfAppsOnStage)) : 0;
    NSArray *items = [layout respondsToSelector:@selector(allItems)] ? G1B_Send0(layout, @selector(allItems)) : nil;
    if (maxApps && items.count >= maxApps) {
        NSArray *sorted = [items sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
            SEL la = @selector(layoutAttributesForItem:), lt = @selector(lastInteractionTime);
            id aa = [layout respondsToSelector:la] ? G1B_Send1(layout, la, a) : nil, bb = [layout respondsToSelector:la] ? G1B_Send1(layout, la, b) : nil;
            long long ta = [aa respondsToSelector:lt] ? G1B_SendLL0(aa, lt) : 0, tb = [bb respondsToSelector:lt] ? G1B_SendLL0(bb, lt) : 0;
            return [@(ta) compare:@(tb)];
        }];
        evicted = sorted.firstObject;
    }
    SEL ini = @selector(initWithGestureID:appLayout:displayItemThatWouldBeEvicted:);
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)([gDndCls alloc], ini, G1B_Send0(event, @selector(gestureID)), layout, evicted);
}
static id G1C_DndRoot_Transition(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gDndRootSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    SEL hw = NSSelectorFromString(@"handleWithReason:");
    if ([event respondsToSelector:hw]) G1B_SendV1(event, hw, [NSString stringWithFormat:@"%@ handling drag and drop initiated transition.", NSStringFromClass([self class])]);
    return r;
}
static id G1C_DndRoot_TransChild(id self, SEL _cmd, id event, id activeGesture) { return nil; }

// ---- the gesture modifier (superclass SBGestureSwitcherModifier) ----
static id G1C_Dnd_Layout(id s) { return G1B_GET(s, kDndLayout); }
static NSUInteger G1C_Dnd_Index(id self) {
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    NSUInteger i = [a indexOfObject:G1C_Dnd_Layout(self)];
    return i == NSNotFound ? 0 : i;
}
static id G1C_Dnd_Init(id self, SEL _cmd, id gid, id layout, id evicted) {
    if (!layout) return nil;                                                        // NSAssert appLayout (…AppDragAndDropGestureSwitcherModifier.m:0x3c)
    id me = G1B_SUPER(id, gDndSuper, self, @selector(initWithGestureID:), (struct objc_super *, SEL, id), gid);
    if (!me) return nil;
    G1B_SET(me, kDndLayout, layout); G1B_SET(me, kDndInitial, layout); G1B_SET(me, kDndEvict, evicted);
    return me;
}
static BOOL G1C_Dnd_Completes(id s, SEL c) { return G1B_GET(s, kDndTrans) != nil; }
static BOOL G1C_Dnd_PushForEvent(id self, SEL _cmd, id event) {
    long long a = [event respondsToSelector:@selector(dropAction)] ? G1B_SendLL0(event, @selector(dropAction)) : 0;
    if (a >= 1 && a <= 5) return YES;
    if (a >= 6 && a <= 9) return ([event respondsToSelector:@selector(isWindowDrag)] && G1B_SendB0(event, @selector(isWindowDrag))) ? (BOOL)G1B_SendB0(event, @selector(hasPlatterized)) : YES;
    return NO;
}
static BOOL G1C_Dnd_ShowResizeUI(id self, SEL _cmd) { return !G1C_Dnd_B(self, DND_ENDED) && (G1C_Dnd_LL(self, DND_DROP_ACTION) & ~1LL) == 4; }
// 0x1c7639cf8. The block at 0x1c7639ed8 computes `everything ready` over the roles of _appLayout:
//   per role: contentReady ? YES : (!ended ? NO : switch (dropAction) { 2,3: !_isBlurred; 4,5: NO; 6,7: YES; default(0,1): item.uniqueIdentifier == _draggedSceneIdentifier })
static void G1C_Dnd_Recompute(id self, SEL _cmd, void (^completion)(id)) {
    BOOL wasBlurred = G1C_Dnd_B(self, DND_BLURRED);
    id layout = G1C_Dnd_Layout(self);
    __block BOOL allReady = YES;
    if ([layout respondsToSelector:NSSelectorFromString(@"enumerate:")]) {
        id me = self;
        ((void (*)(id, SEL, void (^)(long long, id, BOOL *)))objc_msgSend)(layout, NSSelectorFromString(@"enumerate:"), ^(long long role, id item, BOOL *stop) {
            id leaf = [layout respondsToSelector:@selector(leafAppLayoutForRole:)] ? G1C_SendLL1x(layout, @selector(leafAppLayoutForRole:), role) : nil;
            SEL cr = @selector(isLayoutRoleContentReady:inAppLayout:);
            BOOL ready = [me respondsToSelector:cr] && ((BOOL (*)(id, SEL, long long, id))objc_msgSend)(me, cr, role, leaf);
            BOOL v;
            if (ready) v = YES;
            else if (!G1C_Dnd_B(me, DND_ENDED)) v = NO;
            else {
                long long a = G1C_Dnd_LL(me, DND_DROP_ACTION);
                if (a == 2 || a == 3) v = !G1C_Dnd_B(me, DND_BLURRED);
                else if (a == 4 || a == 5) v = NO;
                else if (a == 6 || a == 7) v = YES;
                else { id uid = [item respondsToSelector:@selector(uniqueIdentifier)] ? G1B_Send0(item, @selector(uniqueIdentifier)) : nil; NSString *dsi = G1B_GET(me, kDndSceneId); v = [uid isKindOfClass:[NSString class]] && [uid isEqualToString:dsi]; }
            }
            allReady = allReady && v;
        });
    }
    BOOL ended = G1C_Dnd_B(self, DND_ENDED), blurred = G1C_Dnd_B(self, DND_BLURRED), part;
    if (ended) part = blurred ? !G1C_Dnd_B(self, DND_RESIZED_ENOUGH) : NO;
    else part = blurred ? G1C_Dnd_B(self, DND_RESIZING) : NO;
    BOOL nb;
    if (!allReady) nb = YES;
    else if (G1C_Dnd_ShowResizeUI(self, 0) || part) nb = YES;
    else nb = G1C_Dnd_B(self, DND_NEEDS_BLUR);
    if (G1C_Dnd_B(self, DND_BLURRED) != nb) G1C_Dnd_SetB(self, DND_BLURRED, nb);
    if (G1C_Dnd_B(self, DND_ENDED) && wasBlurred && !G1C_Dnd_B(self, DND_BLURRED) && completion) {
        Class uc = NSClassFromString(@"SBUpdateDragPlatterBlurSwitcherEventResponse");
        id resp = uc ? [[uc alloc] init] : nil;
        if (resp) completion(G1B_Append(resp, nil));
    }
}
static id G1C_Dnd_HandleGesture(id self, SEL _cmd, id event) {                              // 0x1c7638164
    __block id acc = G1B_SUPER(id, gDndSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    if ([event respondsToSelector:@selector(isCanceled)] && G1B_SendB0(event, @selector(isCanceled))) { G1B_SendVLL(self, @selector(setState:), 1); return acc; }
    CGSize oldSize = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), G1C_Dnd_Index(self)).size;
    BOOL push = G1C_Dnd_PushForEvent(self, 0, event);
    G1C_Dnd_SetB(self, DND_SHOULD_PUSH, push);
    if (gDndOff[DND_DROP_ACTION] >= 0) *(long long *)((uint8_t *)(__bridge void *)self + gDndOff[DND_DROP_ACTION]) = [event respondsToSelector:@selector(dropAction)] ? G1B_SendLL0(event, @selector(dropAction)) : 0;
    G1B_SET(self, kDndSceneId, [event respondsToSelector:@selector(draggedSceneIdentifier)] ? G1B_Send0(event, @selector(draggedSceneIdentifier)) : nil);
    G1C_Dnd_SetB(self, DND_HAS_PLATTER, [event respondsToSelector:@selector(hasPlatterized)] && G1B_SendB0(event, @selector(hasPlatterized)));
    G1C_Dnd_SetB(self, DND_HAS_LIFTED, [event respondsToSelector:@selector(hasPreviewLifted)] && G1B_SendB0(event, @selector(hasPreviewLifted)));
    if (gDndOff[DND_SCENE_ROLE] >= 0) *(long long *)((uint8_t *)(__bridge void *)self + gDndOff[DND_SCENE_ROLE]) = [event respondsToSelector:@selector(draggedSceneLayoutRole)] ? G1B_SendLL0(event, @selector(draggedSceneLayoutRole)) : 0;
    if (gDndOff[DND_PLATTER_FRAME] >= 0 && [event respondsToSelector:@selector(platterViewFrame)]) *(CGRect *)((uint8_t *)(__bridge void *)self + gDndOff[DND_PLATTER_FRAME]) = G1C_SendRect0(event, @selector(platterViewFrame));
    if (gDndOff[DND_LOCATION] >= 0 && [event respondsToSelector:@selector(locationInContainerView)]) *(CGPoint *)((uint8_t *)(__bridge void *)self + gDndOff[DND_LOCATION]) = G1C_SendPoint0(event, @selector(locationInContainerView));
    G1C_Dnd_SetB(self, DND_ENDED, G1B_SendLL0(event, @selector(phase)) == 3);
    CGSize newSize = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), G1C_Dnd_Index(self)).size;
    BOOL same = oldSize.width == newSize.width && oldSize.height == newSize.height;
    G1C_Dnd_SetB(self, DND_NEEDS_BLUR, same ? NO : !G1C_Dnd_B(self, DND_ENDED));
    G1C_Dnd_Recompute(self, 0, ^(id r) { acc = G1B_Append(r, acc); });
    return acc;
}
static id G1C_Dnd_ProgressCommon(id self, SEL _cmd, id event, int which) {                        // 0x1c7638500 resize / 0x1c7638748 blur / 0x1c763894c scene ready
    __block id acc = G1B_SUPER(id, gDndSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    if (which == 0 || which == 1) {
        double p = [event respondsToSelector:@selector(progress)] ? G1C_SendD0(event, @selector(progress)) : 0;
        if (which == 0) {
            G1C_Dnd_SetB(self, DND_RESIZING, !G1C_FIsOne(p));
            id ms = [self respondsToSelector:@selector(medusaSettings)] ? G1B_Send0(self, @selector(medusaSettings)) : nil;
            double thr = G1B_Dbl0(ms, NSSelectorFromString(@"dropAnimationUnblurThresholdPercentage"));
            G1C_Dnd_SetB(self, DND_RESIZED_ENOUGH, p >= thr || fabs(p - thr) < 1e-6);
        } else G1C_Dnd_SetB(self, DND_BLURRING, !G1C_FIsOne(p));
    }
    G1C_Dnd_Recompute(self, 0, ^(id r) { acc = G1B_Append(r, acc); });
    id upd = G1B_NewUpdateLayoutResponse(0x20, 2);
    if (upd) acc = G1B_Append(upd, acc);
    return acc;
}
static id G1C_Dnd_HandleResize(id s, SEL c, id e) { return G1C_Dnd_ProgressCommon(s, c, e, 0); }
static id G1C_Dnd_HandleBlur(id s, SEL c, id e) { return G1C_Dnd_ProgressCommon(s, c, e, 1); }
static id G1C_Dnd_HandleSceneReady(id s, SEL c, id e) { return G1C_Dnd_ProgressCommon(s, c, e, 2); }
static id G1C_Dnd_HandleTransition(id self, SEL _cmd, id event) {                              // 0x1c7638b30
    BOOL ended = G1C_Dnd_B(self, DND_ENDED);
    id trans = G1B_GET(self, kDndTrans);
    if (ended && !trans) {
        G1B_SET(self, kDndDropFrom, G1B_Send0(event, @selector(fromAppLayout)));
        id t = (gDndToAppCls && [gDndToAppCls instancesRespondToSelector:@selector(initWithTransitionID:)]) ? ((id (*)(id, SEL, id))objc_msgSend)([gDndToAppCls alloc], @selector(initWithTransitionID:), G1B_Send0(event, @selector(transitionID))) : nil;
        G1B_SET(self, kDndTrans, t);
        if (t) G1B_SendV1(self, @selector(addChildModifier:), t);
    } else if (G1B_SendB0(event, @selector(isGestureInitiated)) && !trans) G1B_SendVLL(self, @selector(setState:), 1);
    G1B_SET(self, kDndLayout, G1B_Send0(event, @selector(toAppLayout)));
    __block id acc = G1B_SUPER(id, gDndSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    G1C_Dnd_Recompute(self, 0, ^(id r) { acc = G1B_Append(r, acc); });
    return acc;
}
static BOOL G1C_Dnd_AnyShared(id a, id b) {                                                     // [a containsAnyItemFromSet:set(b.allItems)]
    if (!a || !b || ![a respondsToSelector:@selector(containsAnyItemFromSet:)] || ![b respondsToSelector:@selector(allItems)]) return NO;
    id items = G1B_Send0(b, @selector(allItems));
    return G1B_SendB1(a, @selector(containsAnyItemFromSet:), [NSSet setWithArray:[items isKindOfClass:[NSArray class]] ? items : @[]]);
}
static CGRect G1C_Dnd_FrameIndex(id self, SEL _cmd, unsigned long long i) {                   // 0x1c7638da8
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < a.count ? a[i] : nil, mine = G1C_Dnd_Layout(self), from = G1B_GET(self, kDndDropFrom);
    if (G1C_Dnd_B(self, DND_ENDED) && from != mine && G1C_Dnd_AnyShared(from, layout)) {
        NSUInteger idx = [a indexOfObject:mine];
        return G1B_SUPER(CGRect, gDndSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), (unsigned long long)idx);
    }
    return G1B_SUPER(CGRect, gDndSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static BOOL G1C_Dnd_Blurred(id self, SEL _cmd, long long role, id layout) {                    // 0x1c7638f04
    id mine = G1C_Dnd_Layout(self);
    if (layout != mine) return G1B_SUPER(BOOL, gDndSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    if (G1C_Dnd_B(self, DND_ENDED) && [mine respondsToSelector:@selector(allItems)]) {
        NSString *dsi = G1B_GET(self, kDndSceneId);
        for (id item in (NSArray *)G1B_Send0(mine, @selector(allItems))) {
            long long r = [mine respondsToSelector:@selector(layoutRoleForItem:)] ? ((long long (*)(id, SEL, id))objc_msgSend)(mine, @selector(layoutRoleForItem:), item) : -1;
            id uid = [item respondsToSelector:@selector(uniqueIdentifier)] ? G1B_Send0(item, @selector(uniqueIdentifier)) : nil;
            if (r == role && [uid isKindOfClass:[NSString class]] && [uid isEqualToString:dsi]) return NO;
        }
    }
    return G1C_Dnd_B(self, DND_BLURRED);
}
static double G1C_Dnd_BackgroundOpacity(id self, SEL _cmd, unsigned long long i) {
    if (!([self respondsToSelector:@selector(isChamoisWindowingUIEnabled)] && G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled)))) return 0.0;
    return G1B_SUPER(double, gDndSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_Dnd_HomeDim(id self, SEL _cmd) {
    // chamois: [super]; non-chamois: UNSURE (0x1c7639120: transition-modifier phase test returning 1.0 early)
    return G1B_SUPER(double, gDndSuper, self, _cmd, (struct objc_super *, SEL));
}
static BOOL G1C_Dnd_GrabberVisible(id self, SEL _cmd, id layout) {
    if (layout == G1C_Dnd_Layout(self)) return NO;
    return G1B_SUPER(BOOL, gDndSuper, self, _cmd, (struct objc_super *, SEL, id), layout);
}
static BOOL G1C_Dnd_StatusBar(id self, SEL _cmd, unsigned long long i) { return G1B_GET(self, kDndTrans) != nil; }
static double G1C_Dnd_Dimming(id self, SEL _cmd, long long role, id layout) {
    id evict = G1B_GET(self, kDndEvict), mine = G1C_Dnd_Layout(self);
    if (evict && layout == mine && [layout respondsToSelector:@selector(itemForLayoutRole:)]) {
        id it = G1C_SendLL1x(layout, @selector(itemForLayoutRole:), role);
        if ([it isEqual:evict] && G1C_Dnd_LL(self, DND_DROP_ACTION) != 0) return 0.5;     // preview of the window that the drop would push out
    }
    return G1B_SUPER(double, gDndSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static BOOL G1C_Dnd_Opaque(id self, SEL _cmd) { return YES; }
static CGRect G1C_Dnd_SizedRect(CGRect f) { return CGRectMake(0, 0, f.size.width, f.size.height); }        // SBRectWithSize
// 0x1c76392f4  (decoded branch by branch, see the md)
static CGRect G1C_Dnd_FrameRole(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    id mine = G1C_Dnd_Layout(self), initial = G1B_GET(self, kDndInitial), from = G1B_GET(self, kDndDropFrom);
    BOOL ended = G1C_Dnd_B(self, DND_ENDED);
    SEL fi = @selector(frameForIndex:);
    NSArray *all = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    #define SUPERF(R, L, B) G1B_SUPER(CGRect, gDndSuper, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), (R), (L), (B))
    if (layout == mine && !ended) {                                                            // A: the incoming window while the drag is in progress
        if (role == 1 /* SBLayoutRolePrimary */ && !G1C_SendLL1x(layout, @selector(itemForLayoutRole:), 2 /* SBLayoutRoleSide */) && (G1C_Dnd_LL(self, DND_DROP_ACTION) & ~1LL) == 4) {
            CGRect r = SUPERF(role, layout, bounds);
            id ms = [self respondsToSelector:@selector(medusaSettings)] ? G1B_Send0(self, @selector(medusaSettings)) : nil;
            double gutter = G1B_Dbl0(ms, NSSelectorFromString(@"draggingPlatterSideActivationGutterPadding"));
            CGRect pf = gDndOff[DND_PLATTER_FRAME] >= 0 ? *(CGRect *)((uint8_t *)(__bridge void *)self + gDndOff[DND_PLATTER_FRAME]) : CGRectZero;
            double w = 2.0 * gutter + pf.size.width;
            double scale = [self respondsToSelector:@selector(screenScale)] ? G1C_SendD0(self, @selector(screenScale)) : 2.0;
            if (scale > 0) w = round(w * scale) / scale;                                       // BSFloatRoundForScale
            BOOL rtl = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
            long long act = G1C_Dnd_LL(self, DND_DROP_ACTION);
            if (rtl ? (act != 4) : (act == 4)) r.origin.x += w;
            r.size.width -= w;
            return r;
        }
        return SUPERF(role, layout, bounds);
    }
    if (initial && [initial respondsToSelector:@selector(isOrContainsAppLayout:)] && G1B_SendB1(initial, @selector(isOrContainsAppLayout:), layout) && !ended) {    // B
        id item = G1C_SendLL1x(layout, @selector(itemForLayoutRole:), 1);
        long long r2 = [initial respondsToSelector:@selector(layoutRoleForItem:)] ? ((long long (*)(id, SEL, id))objc_msgSend)(initial, @selector(layoutRoleForItem:), item) : role;
        NSUInteger idx = [all indexOfObject:layout]; if (idx == NSNotFound) idx = 0;
        CGRect cur = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, fi, (unsigned long long)idx);
        return SUPERF(r2, initial, G1C_Dnd_SizedRect(cur));
    }
    if (layout != mine && ended && from && from != layout && G1C_Dnd_AnyShared(from, layout) && G1C_Dnd_AnyShared(from, mine)) {                                  // C
        __block long long foundRole = role; __block BOOL found = NO;
        if ([from respondsToSelector:NSSelectorFromString(@"enumerate:")])
            ((void (*)(id, SEL, void (^)(long long, id, BOOL *)))objc_msgSend)(from, NSSelectorFromString(@"enumerate:"), ^(long long rl, id item, BOOL *stop) {
                if (!(mine && [mine respondsToSelector:@selector(containsItem:)] && G1B_SendB1(mine, @selector(containsItem:), item))) { foundRole = rl; found = YES; *stop = YES; }
            });
        NSUInteger idx = [all indexOfObject:layout]; if (idx == NSNotFound) idx = 0;
        CGRect cur = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, fi, (unsigned long long)idx);
        return SUPERF(found ? foundRole : role, from, G1C_Dnd_SizedRect(cur));
    }
    return SUPERF(role, layout, bounds);
    #undef SUPERF
}
static BOOL G1C_Dnd_MatchMoved(id self, SEL _cmd, long long role, id layout) {
    return G1C_Dnd_B(self, DND_RESIZING) && [G1C_Dnd_Layout(self) respondsToSelector:@selector(itemForLayoutRole:)] && G1C_SendLL1x(G1C_Dnd_Layout(self), @selector(itemForLayoutRole:), role) != nil;
}
static double G1C_Dnd_Scale(id self, SEL _cmd, unsigned long long i) {
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < a.count ? a[i] : nil;
    if (layout == G1C_Dnd_Layout(self) && G1C_Dnd_B(self, DND_SHOULD_PUSH) && !G1C_Dnd_B(self, DND_ENDED)) return 0.98;
    return G1B_SUPER(double, gDndSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static G1CRadii G1C_Dnd_Radii(id self, SEL _cmd, unsigned long long i) {
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < a.count ? a[i] : nil, initial = G1B_GET(self, kDndInitial), from = G1B_GET(self, kDndDropFrom);
    SEL oc = @selector(isOrContainsAppLayout:);
    BOOL mineGroup = (initial && [initial respondsToSelector:oc] && G1B_SendB1(initial, oc, layout)) || (from && [from respondsToSelector:oc] && G1B_SendB1(from, oc, layout));
    if (mineGroup) {
        id ca = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
        double r = [self respondsToSelector:@selector(displayCornerRadius)] ? G1C_SendD0(self, @selector(displayCornerRadius)) : 0.0;
        if (fabs(r) < 1e-9) r = G1B_Dbl0(ca, @selector(stageCornerRaddii));
        double sc = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), i);
        double v = sc != 0 ? r / sc : r;
        return (G1CRadii){ v, v, v, v };
    }
    return G1B_SUPER(G1CRadii, gDndSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static id G1C_Dnd_Anim(id self, SEL _cmd, id el) {
    id base = G1B_SUPER(id, gDndSuper, self, _cmd, (struct objc_super *, SEL, id), el);
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    id ms = [self respondsToSelector:@selector(medusaSettings)] ? G1B_Send0(self, @selector(medusaSettings)) : nil;
    id rs = [ms respondsToSelector:@selector(resizeAnimationSettings)] ? G1B_Send0(ms, @selector(resizeAnimationSettings)) : nil;
    if (a && rs && [a respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(a, @selector(setLayoutSettings:), rs);
    if (a && [a respondsToSelector:@selector(setUpdateMode:)]) G1B_SendVLL(a, @selector(setUpdateMode:), 3);
    return a;
}
static id G1C_Dnd_ResizeNotifs(id self, SEL _cmd, long long role, id layout) {
    id s = G1B_SUPER(id, gDndSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    if (layout == G1C_Dnd_Layout(self) && [s respondsToSelector:@selector(setByAddingObjectsFromArray:)]) {
        id ms = [self respondsToSelector:@selector(medusaSettings)] ? G1B_Send0(self, @selector(medusaSettings)) : nil;
        double thr = G1B_Dbl0(ms, NSSelectorFromString(@"dropAnimationUnblurThresholdPercentage"));
        return G1B_Send1(s, @selector(setByAddingObjectsFromArray:), @[ @0.0, @(thr), @1.0 ]);     // 0x1c7639afc (constants: objc_doubleobj 0.0 / 1.0, order UNSURE)
    }
    return s;
}
static BOOL G1C_BuildDnd(void) {
    gDndSuper = NSClassFromString(@"SBGestureSwitcherModifier"); gDndRootSuper = NSClassFromString(@"SBGestureRootSwitcherModifier");
    if (!gDndSuper || !gDndRootSuper || !G1B_HasSuper(gDndSuper, @selector(initWithGestureID:))) return NO;
    for (int i = 0; i < 24; i++) gDndOff[i] = -1;
    const G1BIvar iv[] = {
        { "_shouldPushInFullScreenContent", 1, 0, "B" }, { "_isResizing", 1, 0, "B" }, { "_hasResizedEnoughToUnblur", 1, 0, "B" }, { "_isBlurring", 1, 0, "B" },
        { "_isBlurred", 1, 0, "B" }, { "_needsBlurBecauseFramesWillMismatch", 1, 0, "B" }, { "_gestureEnded", 1, 0, "B" }, { "_hasPlatterized", 1, 0, "B" }, { "_hasPreviewLifted", 1, 0, "B" },
        { "_dropAction", 8, 3, "q" }, { "_draggedSceneOriginalLayoutRole", 8, 3, "q" },
        { "_platterFrame", sizeof(CGRect), 3, "{CGRect={CGPoint=dd}{CGSize=dd}}" }, { "_location", sizeof(CGPoint), 3, "{CGPoint=dd}" },
    };
    const G1BMethod m[] = {
        { "initWithGestureID:appLayout:displayItemThatWouldBeEvicted:", (IMP)G1C_Dnd_Init, "@40@0:8@16@24@32" },
        { "completesWhenChildrenComplete", (IMP)G1C_Dnd_Completes, "B16@0:8" },
        { "_shouldPushInFullScreenContentForEvent:", (IMP)G1C_Dnd_PushForEvent, "B24@0:8@16" },
        { "_showResizeUI", (IMP)G1C_Dnd_ShowResizeUI, "B16@0:8" },
        { "_recomputeBlurStateWithCompletion:", (IMP)G1C_Dnd_Recompute, "v24@0:8@?16" },
        { "handleGestureEvent:", (IMP)G1C_Dnd_HandleGesture, "@24@0:8@16" },
        { "handleResizeProgressEvent:", (IMP)G1C_Dnd_HandleResize, "@24@0:8@16" }, { "handleBlurProgressEvent:", (IMP)G1C_Dnd_HandleBlur, "@24@0:8@16" },
        { "handleSceneReadyEvent:", (IMP)G1C_Dnd_HandleSceneReady, "@24@0:8@16" }, { "handleTransitionEvent:", (IMP)G1C_Dnd_HandleTransition, "@24@0:8@16" },
        { "frameForIndex:", (IMP)G1C_Dnd_FrameIndex, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
        { "isLayoutRoleBlurred:inAppLayout:", (IMP)G1C_Dnd_Blurred, "B32@0:8q16@24" },
        { "backgroundOpacityForIndex:", (IMP)G1C_Dnd_BackgroundOpacity, "d24@0:8Q16" }, { "homeScreenDimmingAlpha", (IMP)G1C_Dnd_HomeDim, "d16@0:8" },
        { "isResizeGrabberVisibleForAppLayout:", (IMP)G1C_Dnd_GrabberVisible, "B24@0:8@16" }, { "isContentStatusBarVisibleForIndex:", (IMP)G1C_Dnd_StatusBar, "B24@0:8Q16" },
        { "dimmingAlphaForLayoutRole:inAppLayout:", (IMP)G1C_Dnd_Dimming, "d32@0:8q16@24" }, { "switcherHitTestsAsOpaque", (IMP)G1C_Dnd_Opaque, "B16@0:8" },
        { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_Dnd_FrameRole, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32" },
        { "isLayoutRoleMatchMovedToScene:inAppLayout:", (IMP)G1C_Dnd_MatchMoved, "B32@0:8q16@24" }, { "scaleForIndex:", (IMP)G1C_Dnd_Scale, "d24@0:8Q16" },
        { "cornerRadiiForIndex:", (IMP)G1C_Dnd_Radii, "{UIRectCornerRadii=dddd}24@0:8Q16" }, { "animationAttributesForLayoutElement:", (IMP)G1C_Dnd_Anim, "@24@0:8@16" },
        { "resizeProgressNotificationsForLayoutRole:inAppLayout:", (IMP)G1C_Dnd_ResizeNotifs, "@32@0:8q16@24" },
    };
    BOOL made = NO;
    gDndCls = G1B_MakeClass("SBContinuousExposeAppDragAndDropGestureSwitcherModifier", gDndSuper, iv, sizeof iv / sizeof iv[0], m, sizeof m / sizeof m[0], NULL, &made);
    if (made) {
        const char *n[] = { "_shouldPushInFullScreenContent", "_isResizing", "_hasResizedEnoughToUnblur", "_isBlurring", "_isBlurred", "_needsBlurBecauseFramesWillMismatch", "_gestureEnded", "_hasPlatterized", "_hasPreviewLifted", "_dropAction", "_draggedSceneOriginalLayoutRole", "_platterFrame", "_location" };
        int idx[] = { DND_SHOULD_PUSH, DND_RESIZING, DND_RESIZED_ENOUGH, DND_BLURRING, DND_BLURRED, DND_NEEDS_BLUR, DND_ENDED, DND_HAS_PLATTER, DND_HAS_LIFTED, DND_DROP_ACTION, DND_SCENE_ROLE, DND_PLATTER_FRAME, DND_LOCATION };
        for (size_t i = 0; i < sizeof idx / sizeof idx[0]; i++) gDndOff[idx[i]] = G1B_IvarOffset(gDndCls, n[i]);
    }
    const G1BMethod rm[] = {
        { "initWithStartingEnvironmentMode:appLayout:", (IMP)G1C_DndRoot_Init, "@32@0:8q16@24" }, { "gestureType", (IMP)G1C_DndRoot_Type, "q16@0:8" },
        { "gestureChildModifierForGestureEvent:activeTransitionModifier:", (IMP)G1C_DndRoot_Child, "@32@0:8@16@24" },
        { "handleTransitionEvent:", (IMP)G1C_DndRoot_Transition, "@24@0:8@16" },
        { "transitionChildModifierForMainTransitionEvent:activeGestureModifier:", (IMP)G1C_DndRoot_TransChild, "@32@0:8@16@24" },
    };
    gDndRootCls = G1B_MakeClass("SBContinuousExposeDragAndDropGestureRootSwitcherModifier", gDndRootSuper, NULL, 0, rm, sizeof rm / sizeof rm[0], NULL, NULL);
    for (int k = 0; k <= DND_LOCATION; k++) if (gDndOff[k] < 0) return NO;
    return gDndCls != Nil && gDndRootCls != Nil;
}
static id G1C_NewDndRoot(long long mode, id layout) {
    SEL s = @selector(initWithStartingEnvironmentMode:appLayout:);
    if (!gDndRootCls || !gDndCls || ![gDndRootCls instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, long long, id))objc_msgSend)([gDndRootCls alloc], s, mode, layout);
}

// ---- _SBContinuousExposeWindowDragContentSwitcherModifier (ivar _selectedDisplayItem +0x60; 162 0x1c762a3b0) ----
static char kWdcItem;
static id G1C_Wdc_Init(id self, SEL _cmd, id gid, id initial, id item) {
    id me = G1B_SUPER(id, gWdContentSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kWdcItem, item);
    SEL add = @selector(addChildModifier:atLevel:key:), noTap = @selector(setHandlesTapAppLayoutEvents:), noHdr = @selector(setHandlesTapAppLayoutHeaderEvents:);
    id drag = G1C_NewWindowDragModifier(gid, initial, item);
    if (drag) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, add, drag, 0, nil);
    id fs = G1C_NewFullScreenModifier(initial);
    if (fs) {
        if ([fs respondsToSelector:noTap]) G1C_SendVB(fs, noTap, NO);
        if ([fs respondsToSelector:noHdr]) G1C_SendVB(fs, noHdr, NO);
        ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, add, fs, 1, nil);
    }
    id as = G1C_NewAppSwitcherModifier();
    if (as) {
        if ([as respondsToSelector:noTap]) G1C_SendVB(as, noTap, NO);
        if ([as respondsToSelector:noHdr]) G1C_SendVB(as, noHdr, NO);
        ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, add, as, 2, nil);
    }
    return me;
}
static id G1C_Wdc_Item(id s, SEL c) { return G1B_GET(s, kWdcItem); }
static id G1C_Wdc_Adjusted(id self, SEL _cmd, id layouts) {                      // layouts containing the dragged item first (0x1c762a510)
    id r = G1B_SUPER(id, gWdContentSuper, self, _cmd, (struct objc_super *, SEL, id), layouts);
    id item = G1B_GET(self, kWdcItem);
    if (![r isKindOfClass:[NSArray class]] || !item) return r;
    NSMutableArray *a = [NSMutableArray array], *b = [NSMutableArray array];
    for (id l in (NSArray *)r) [([l respondsToSelector:@selector(containsItem:)] && G1B_SendB1(l, @selector(containsItem:), item) ? a : b) addObject:l];
    return [a arrayByAddingObjectsFromArray:b];
}
static BOOL G1C_BuildWindowDragContent(void) {
    gWdContentSuper = NSClassFromString(@"SBSwitcherModifier");
    if (!gWdContentSuper) return NO;
    const G1BMethod m[] = {
        { "initWithGestureID:initialAppLayout:selectedDisplayItem:", (IMP)G1C_Wdc_Init, "@40@0:8@16@24@32" },
        { "selectedDisplayItem", (IMP)G1C_Wdc_Item, "@16@0:8" },
        { "adjustedAppLayoutsForAppLayouts:", (IMP)G1C_Wdc_Adjusted, "@24@0:8@16" },
    };
    gWdContentCls = G1B_MakeClass("_SBContinuousExposeWindowDragContentSwitcherModifier", gWdContentSuper, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
    return gWdContentCls != Nil;
}
static id G1C_NewWindowDragContentFor(id gid, id initial, id item) {
    SEL s = @selector(initWithGestureID:initialAppLayout:selectedDisplayItem:);
    if (!gWdContentCls || ![gWdContentCls instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)([gWdContentCls alloc], s, gid, initial, item);
}


// ============================================================================================================
// 1d  Window drag family (SBContinuousExposeWindowDragSwitcherModifier / ...DestinationSwitcherModifier / ...RootSwitcherModifier)
//     DONE for the drag modifier + root; Destination = UNSURE (composition over the 16.0 algorithm, see md 1d.3)
// ============================================================================================================
// Design: BP162 subclasses of the 16.0 classes. The 16.0 ivars (_location, _anchorPoint, ...) are reached by name; the new 16.2
// ivars are added to the subclass with class_addIvar. Only the 11 changed + 10 new methods are overridden.

static void G1C_SetIvarObj(id o, const char *name, id v) {
    if (!o) return;
    Ivar iv = class_getInstanceVariable(object_getClass(o), name);
    if (iv) object_setIvar(o, iv, v);
}
static BOOL G1C_IsInvalidPoint(CGPoint p) { return p.x == DBL_MAX && p.y == DBL_MAX; }      // SBInvalidPoint = {DBL_MAX, DBL_MAX} (0x1c7a92f20)
static CGSize G1C_IvarSize(id o, const char *n) { CGSize v = CGSizeZero; G1C_IvarRaw(o, n, &v, sizeof v, NO); return v; }
static void G1C_SetIvarSize(id o, const char *n, CGSize v) { G1C_IvarRaw(o, n, &v, sizeof v, YES); }

static Class gWdParent, gWdGrand, gWdCls, gWddParent, gWddCls, gWdrParent, gWdrGrand, gWdrCls;

// --- context queries with a single-display fallback (the data layer / extended protocols answer the real ones, DM7) ---
static NSArray *G1C_WdDragging(id self, id initial) {
    SEL s = NSSelectorFromString(@"draggingAppLayoutsForContinuousExposeWindowDrag");
    id r = G1C_Resp(self, s) ? G1B_Send0(self, s) : nil;
    if ([r isKindOfClass:[NSArray class]] && [(NSArray *)r count]) return r;
    return initial ? @[ initial ] : @[];
}
static NSArray *G1C_WdProposedAll(id self, id dest) {
    SEL s = NSSelectorFromString(@"proposedAppLayoutsForContinuousExposeWindowDrag");
    id r = G1C_Resp(self, s) ? G1B_Send0(self, s) : nil;
    if ([r isKindOfClass:[NSArray class]] && [(NSArray *)r count]) return r;
    id p = dest ? G1B_Send0(dest, @selector(proposedAppLayout)) : nil;
    return p ? @[ p ] : @[];
}
static BOOL G1C_LayoutHas(id layout, id item) { return layout && item && G1C_Resp(layout, @selector(containsItem:)) && G1B_SendB1(layout, @selector(containsItem:), item); }

static id G1C_Wd_Sel(id s)  { return G1C_IvarObj(s, "_selectedDisplayItem"); }
static id G1C_Wd_Dest(id s) { return G1C_IvarObj(s, "_destinationModifier"); }
static id G1C_Wd_Init0(id s) { return G1C_IvarObj(s, "_initialAppLayout"); }
static id G1C_Wd_Proposed(id s) { id d = G1C_Wd_Dest(s); return d && G1C_Resp(d, @selector(proposedAppLayout)) ? G1B_Send0(d, @selector(proposedAppLayout)) : nil; }
static BOOL G1C_Wd_AnyProposedHas(id self) {
    id sel = G1C_Wd_Sel(self);
    for (id l in G1C_WdProposedAll(self, G1C_Wd_Dest(self))) if (G1C_LayoutHas(l, sel)) return YES;
    return NO;
}
static id G1C_Wd_LayoutContaining(id self, id item) {
    if (!item || !G1C_Resp(self, @selector(appLayouts))) return nil;
    for (id l in (NSArray *)G1B_Send0(self, @selector(appLayouts))) if (G1C_LayoutHas(l, item)) return l;
    return nil;
}

// 1d.1 init  (16.2 0x1c76092bc; same shape as 16.0 but the destination is the BP162 subclass)
static id G1C_Wd_Init(id self, SEL _cmd, id gid, id initial, id item) {
    id me = G1B_SUPER(id, gWdGrand, self, @selector(initWithGestureID:), (struct objc_super *, SEL, id), gid);
    if (!me) return nil;
    G1C_SetIvarObj(me, "_initialAppLayout", initial);
    G1C_SetIvarObj(me, "_selectedDisplayItem", item);
    CGPoint inv = CGPointMake(DBL_MAX, DBL_MAX);
    G1C_SetIvarPoint(me, "_anchorPoint", inv);
    G1C_SetIvarPoint(me, "_initialAnchorPoint", inv);
    Class dc = gWddCls ?: gWddParent;
    SEL di = @selector(initWithSelectedDisplayItem:initialAppLayout:delegate:);
    if (dc && [dc instancesRespondToSelector:di]) {
        id dest = ((id (*)(id, SEL, id, id, id))objc_msgSend)([dc alloc], di, item, initial, me);
        if (dest) {
            G1C_SetIvarObj(me, "_destinationModifier", dest);
            if ([me respondsToSelector:@selector(addChildModifier:)]) G1B_SendV1(me, @selector(addChildModifier:), dest);
            else if ([me respondsToSelector:@selector(addChildModifier:atLevel:key:)]) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, @selector(addChildModifier:atLevel:key:), dest, 0, nil);
        }
    }
    return me;
}

// 1d.2 preferredCenterForSelectedItemInDestinationModifier:  (0x1c7609494)
static CGPoint G1C_Wd_PreferredCenter(id self, SEL _cmd, id dm) {
    CGPoint loc = G1C_IvarPoint(self, "_location");
    id layout = G1C_Wd_LayoutContaining(self, G1C_Wd_Sel(self));
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    NSUInteger idx = (layout && ls) ? [ls indexOfObject:layout] : NSNotFound;
    if (idx == NSNotFound) return loc;
    CGRect fr = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), idx);
    double sc = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), idx);
    CGPoint a = G1C_IvarPoint(self, "_anchorPoint");
    if (G1C_IsInvalidPoint(a)) a = CGPointMake(0.5, 0.5);
    return CGPointMake(loc.x + fr.size.width * sc * (0.5 - a.x), loc.y + fr.size.height * sc * (0.5 - a.y));
}

// 1d.3 handleGestureEvent:  (0x1c7609578, 650 instrs) - phases 1 (begin), 3 (end); other phases only track _location
static id G1C_Wd_Gesture(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gWdGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event) return r;
    G1C_SetIvarPoint(self, "_location", G1C_Resp(event, @selector(locationInContainerView)) ? G1C_SendPoint0(event, @selector(locationInContainerView)) : CGPointZero);
    id dest = G1C_Wd_Dest(self), sel = G1C_Wd_Sel(self), initial = G1C_Wd_Init0(self);
    long long destProposed = dest ? G1B_SendLL0(dest, @selector(proposedDestination)) : 0;
    G1C_SetIvarBool(self, "_gestureWasCanceled", destProposed == 0);
    long long phase = G1B_SendLL0(event, @selector(phase));
    if (phase == 1) {
        id layout = G1C_Wd_LayoutContaining(self, sel);
        id dragged = nil;
        for (id l in G1C_WdDragging(self, initial)) if (G1C_LayoutHas(l, sel)) { dragged = l; break; }
        SEL sz = NSSelectorFromString(@"sizeOfSelectedDisplayItem");
        CGSize size = G1C_Resp(event, sz) ? G1C_SendSize0(event, sz) : CGSizeZero;
        G1C_SetIvarSize(self, "_bp_sizeOfSelectedDisplayItem", size);
        long long myOrd = G1C_Resp(self, @selector(displayOrdinal)) ? G1B_SendLL0(self, @selector(displayOrdinal)) : 0;
        long long itsOrd = (dragged && G1C_Resp(dragged, @selector(preferredDisplayOrdinal))) ? G1B_SendLL0(dragged, @selector(preferredDisplayOrdinal)) : myOrd;
        BOOL other = itsOrd != myOrd;
        BOOL strips = G1C_Resp(event, @selector(isDraggingFromContinuousExposeStrips)) && G1B_SendB0(event, @selector(isDraggingFromContinuousExposeStrips));
        G1C_SetIvarBool(self, "_bp_dragBeganInOtherSwitcher", other);
        G1C_SetIvarBool(self, "_bp_dragBeganInAnyStrip", strips);
        G1C_SetIvarBool(self, "_bp_dragBeganOnAnyStage", !strips);
        if (layout) {
            CGPoint inItem = G1C_Resp(event, @selector(locationInSelectedDisplayItem)) ? G1C_SendPoint0(event, @selector(locationInSelectedDisplayItem)) : CGPointZero;
            long long role = G1C_Resp(layout, @selector(layoutRoleForItem:)) ? G1C_SendLLId(layout, @selector(layoutRoleForItem:), sel) : 0;
            CGRect bounds = G1C_Resp(self, @selector(containerViewBounds)) ? G1C_SendRect0(self, @selector(containerViewBounds)) : CGRectZero;
            CGSize fs = (other && size.width > 0 && size.height > 0) ? size : CGSizeZero;
            if (fs.width <= 0 || fs.height <= 0) {                                   // [super frameForLayoutRole:inAppLayout:withBounds:].size
                CGRect fr = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(self, @selector(frameForLayoutRole:inAppLayout:withBounds:), role, layout, bounds);
                fs = fr.size;
            }
            if (fs.width > 0 && fs.height > 0) {
                CGPoint a = CGPointMake(inItem.x / fs.width, inItem.y / fs.height);
                G1C_SetIvarPoint(self, "_anchorPoint", a);
                G1C_SetIvarPoint(self, "_initialAnchorPoint", a);
            }
        }
        id u1 = G1B_NewUpdateLayoutResponse(2, 2);
        r = G1B_AppendTo(u1, r);
        id u2 = G1B_NewUpdateLayoutResponse(8, 3);
        r = G1B_AppendTo(u2, r);
    } else if (phase == 3) {
        BOOL canceled = G1C_IvarBool(self, "_gestureWasCanceled");
        id target = G1C_Wd_Proposed(self);
        if (canceled) {
            if (initial) r = G1B_AppendTo(G1C_NewPerformActivate(initial, YES), r);
        } else {
            CGPoint vel = G1C_Resp(event, @selector(velocityInContainerView)) ? G1C_SendPoint0(event, @selector(velocityInContainerView)) : CGPointZero;
            id attrs = G1C_Resp(self, @selector(chamoisLayoutAttributes)) ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
            BOOL toHome = NO;
            if (target && G1C_LayoutHas(target, sel) && vel.y > 2500.0 && vel.y > fabs(vel.x) && G1C_Resp(self, @selector(appLayouts))) {
                // flick-down: fling past the bottom limit (maximumWindowHeightWithDock + screenEdgePadding) removes the window from the stage
                NSArray *ls = G1B_Send0(self, @selector(appLayouts));
                id mine = G1C_Wd_LayoutContaining(self, sel);
                NSUInteger idx = mine ? [ls indexOfObject:mine] : NSNotFound;
                if (idx != NSNotFound) {
                    CGRect fr = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), idx);
                    CGPoint ap = ((CGPoint (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(anchorPointForIndex:), idx);
                    CGPoint c = CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr));
                    double bottom = c.y + fr.size.height * (1.0 - ap.y);
                    double limit = G1B_Dbl0(attrs, NSSelectorFromString(@"maximumWindowHeightWithDock")) + G1C_DM_ScreenEdgePadding(attrs);
                    if (bottom >= limit) toHome = YES;
                }
            }
            if (toHome && target) {
                id selCopy = sel;
                id without = nil;
                if (G1C_Resp(target, @selector(appLayoutWithItemsPassingTest:))) {
                    BOOL (^pass)(id) = ^BOOL(id item) { return ![item isEqual:selCopy]; };
                    without = ((id (*)(id, SEL, id))objc_msgSend)(target, @selector(appLayoutWithItemsPassingTest:), pass);
                }
                target = without;
            } else if (target && G1C_LayoutHas(target, sel) && G1C_Resp(self, @selector(appLayoutByBringingItemToFront:inAppLayout:))) {
                id fronted = G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), sel, target);
                if (fronted) target = fronted;
            }
            id finalTarget = target;
            if (!finalTarget) {
                Class al = NSClassFromString(@"SBAppLayout");
                id home = (al && [al respondsToSelector:@selector(homeScreenAppLayout)]) ? G1B_Send0((id)al, @selector(homeScreenAppLayout)) : nil;
                long long ord = G1C_Resp(self, @selector(displayOrdinal)) ? G1B_SendLL0(self, @selector(displayOrdinal)) : 0;
                SEL mo = NSSelectorFromString(@"appLayoutByModifyingPreferredDisplayOrdinal:");
                if (home && [home respondsToSelector:mo]) home = G1C_SendLL1(home, mo, ord);
                finalTarget = home;
            }
            if (finalTarget) r = G1B_AppendTo(G1C_NewPerformActivate(finalTarget, YES), r);
            double prog = G1C_Resp(self, @selector(continuousExposeStripProgress)) ? G1C_SendD0(self, @selector(continuousExposeStripProgress)) : 0;
            if (prog != 0.0 && !(finalTarget && G1C_LayoutHas(finalTarget, sel))) r = G1B_AppendTo(G1C_NewStripsPresentationResponse(0, 1), r);
        }
    }
    return r;
}

// 1d.4 simple queries (decoded, see md)
static id G1C_Wd_AppLayoutContainingAppLayout(id self, SEL _cmd, id l) {
    id p = G1C_Wd_Proposed(self);
    if (p && l && G1C_Resp(p, @selector(containsAnyItemFromAppLayout:)) && G1B_SendB1(p, @selector(containsAnyItemFromAppLayout:), l)) return p;
    return G1B_SUPER(id, gWdGrand, self, _cmd, (struct objc_super *, SEL, id), l);
}
static id G1C_Wd_AppLayoutOnStage(id self, SEL _cmd) { return G1C_Wd_Proposed(self); }
static BOOL G1C_Wd_AnyExceeds(id self, SEL _cmd) {
    id p = G1C_Wd_Proposed(self);
    SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:");
    id model = (p && G1C_Resp(self, om)) ? G1B_Send1(self, om, p) : nil;
    SEL vis = NSSelectorFromString(@"isContinuousExposeStripVisible");
    if (!model || ![model respondsToSelector:vis]) return NO;
    return !G1B_SendB0(model, vis);
}
static BOOL G1C_Wd_AnyProposedHasQ(id self, SEL _cmd) { return G1C_Wd_AnyProposedHas(self); }
static double G1C_Wd_StripProgress(id self, SEL _cmd) {
    // 16.0 has no continuousExposeStripProgress anywhere in the chain; the trampoline exists only when the group 2b extended protocol is active
    double v = G1B_HasSuper(gWdGrand, _cmd) ? G1B_SUPER(double, gWdGrand, self, _cmd, (struct objc_super *, SEL)) : 0.0;
    if (G1C_Wd_AnyExceeds(self, 0)) {
        id sel = G1C_Wd_Sel(self);
        if (!G1C_LayoutHas(G1C_Wd_Proposed(self), sel) && G1C_LayoutHas(G1C_Wd_Init0(self), sel)) v = 1.0;
    }
    return v;
}
static CGRect G1C_Wd_FrameForIndex(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < ls.count ? ls[i] : nil;
    id sel = G1C_Wd_Sel(self);
    CGPoint anchor = G1C_IvarPoint(self, "_anchorPoint");
    if (!G1C_LayoutHas(layout, sel) || G1C_IsInvalidPoint(anchor)) return G1B_SUPER(CGRect, gWdGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    BOOL a = G1C_Wd_AnyProposedHas(self);
    id proposed = G1C_Wd_Proposed(self);
    BOOL b = G1C_LayoutHas(proposed, sel);
    BOOL other = G1C_IvarBool(self, "_bp_dragBeganInOtherSwitcher");
    CGSize size;
    if (other && a && !b) {
        size = G1C_IvarSize(self, "_bp_sizeOfSelectedDisplayItem");
    } else {
        id al = b ? proposed : layout;
        id calc = G1C_Resp(self, @selector(displayItemLayoutAttributesCalculator)) ? G1B_Send0(self, @selector(displayItemLayoutAttributesCalculator)) : nil;
        SEL fs = NSSelectorFromString(@"frameForLayoutRole:inAppLayout:containerBounds:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:isChamoisWindowingUIEnabled:prefersStripHidden:prefersDockHidden:");
        size = CGSizeZero;
        if (calc && [calc respondsToSelector:fs] && G1C_Resp(al, @selector(layoutRoleForItem:))) {
            long long role = G1C_SendLLId(al, @selector(layoutRoleForItem:), sel);
            CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
            long long orient = G1B_SendLL0(self, @selector(switcherInterfaceOrientation));
            id ca = G1B_Send0(self, @selector(chamoisLayoutAttributes));
            double fdh = G1B_Dbl0(self, @selector(floatingDockHeight)), scale = G1B_Dbl0(self, @selector(screenScale));
            BOOL sh = G1B_SendB0(self, @selector(prefersStripHidden)), dh = G1B_SendB0(self, @selector(prefersDockHidden));
            CGRect fr = ((CGRect (*)(id, SEL, long long, id, CGRect, long long, id, double, double, BOOL, BOOL, BOOL))objc_msgSend)(calc, fs, role, al, cb, orient, ca, fdh, scale, YES, sh, dh);
            size = fr.size;
        }
    }
    if (size.width == 0 && size.height == 0) {
        CGRect sf = G1B_SUPER(CGRect, gWdGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
        size = sf.size;
    }
    CGPoint loc = G1C_IvarPoint(self, "_location");
    return CGRectMake(loc.x - size.width / 2.0, loc.y - size.height / 2.0, size.width, size.height);   // UIRectCenteredAboutPoint(SBRectWithSize(size), _location)
}
static double G1C_Wd_ScaleForIndex(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < ls.count ? ls[i] : nil;
    id sel = G1C_Wd_Sel(self);
    if (!G1C_LayoutHas(layout, sel) || G1C_IsInvalidPoint(G1C_IvarPoint(self, "_anchorPoint")))
        return G1B_SUPER(double, gWdGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    BOOL strip = G1C_IvarBool(self, "_bp_dragBeganInAnyStrip"), stage = G1C_IvarBool(self, "_bp_dragBeganOnAnyStage"), other = G1C_IvarBool(self, "_bp_dragBeganInOtherSwitcher");
    BOOL a = G1C_Wd_AnyProposedHas(self);
    double v;
    if (strip) {
        if (a) return 0.6;
    } else if (stage) {
        BOOL b = G1C_LayoutHas(G1C_Wd_Proposed(self), sel);
        v = other ? (b ? 0.6 : 1.0) : (b ? 1.0 : 0.6);
        if (a || b) return v;
    } else {
        return G1B_SUPER(double, gWdGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    }
    id ca = G1C_Resp(self, @selector(chamoisLayoutAttributes)) ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    return G1B_Dbl0(ca, NSSelectorFromString(@"stripCardScale"));
}
static BOOL G1C_Wd_UseAnchorPin(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < ls.count ? ls[i] : nil;
    if (G1C_LayoutHas(layout, G1C_Wd_Sel(self))) return NO;
    return G1B_SUPER(BOOL, gWdGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static BOOL G1C_Wd_PinRoles(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < ls.count ? ls[i] : nil;
    if (G1C_LayoutHas(layout, G1C_Wd_Sel(self)) && !G1C_IsInvalidPoint(G1C_IvarPoint(self, "_anchorPoint"))) return YES;
    return G1B_SUPER(BOOL, gWdGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGRect G1C_Wd_FrameForRole(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    if (G1C_LayoutHas(layout, G1C_Wd_Sel(self)) && !G1C_IsInvalidPoint(G1C_IvarPoint(self, "_anchorPoint"))) return bounds;
    return G1B_SUPER(CGRect, gWdGrand, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds);
}
static double G1C_Wd_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long i) {
    if (G1C_LayoutHas(layout, G1C_Wd_Sel(self))) return 1.0;
    return G1B_SUPER(double, gWdGrand, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, i);
}
static id G1C_Wd_Visible(id self, SEL _cmd) {
    id s = G1B_SUPER(id, gWdGrand, self, _cmd, (struct objc_super *, SEL));
    id l = G1C_Wd_LayoutContaining(self, G1C_Wd_Sel(self));
    if (l && [s respondsToSelector:@selector(setByAddingObject:)]) return G1B_Send1(s, @selector(setByAddingObject:), l);
    return s;
}
static double G1C_Wd_Perspective(id self, SEL _cmd, id layout) {
    if (!G1C_LayoutHas(layout, G1C_Wd_Sel(self))) return G1B_SUPER(double, gWdGrand, self, _cmd, (struct objc_super *, SEL, id), layout);
    if (G1C_Wd_AnyProposedHas(self)) return 0.0;
    BOOL rtl = G1C_Resp(self, @selector(isRTLEnabled)) ? G1B_SendB0(self, @selector(isRTLEnabled)) : ([[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft);
    id ca = G1C_Resp(self, @selector(chamoisLayoutAttributes)) ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    double a = G1B_Dbl0(ca, NSSelectorFromString(@"stripTiltAngle"));
    return rtl ? -a : a;
}
static id G1C_Wd_AnimAttrs(id self, SEL _cmd, id element) {
    id base = G1B_SUPER(id, gWdGrand, self, _cmd, (struct objc_super *, SEL, id), element);
    if (!G1C_ON() || !element || !base) return base;
    SEL tp = NSSelectorFromString(@"switcherLayoutElementType");
    if (!G1C_Resp(element, tp) || G1B_SendLL0(element, tp) != 0) return base;
    if (!G1C_LayoutHas(element, G1C_Wd_Sel(self))) return base;
    id ms = G1C_Resp(self, @selector(medusaSettings)) ? G1B_Send0(self, @selector(medusaSettings)) : nil;
    Class fc = NSClassFromString(@"SBFFluidBehaviorSettings");
    id tracking = (fc && [fc instancesRespondToSelector:@selector(initWithDefaultValues)]) ? G1B_Send0([fc alloc], @selector(initWithDefaultValues)) : nil;
    id rs = G1C_Resp(ms, @selector(resizeAnimationSettings)) ? G1B_Send0(ms, @selector(resizeAnimationSettings)) : nil;
    if (tracking && rs) {
        if ([tracking respondsToSelector:@selector(setTrackingDampingRatio:)] && [rs respondsToSelector:@selector(dampingRatio)]) G1C_SendVD(tracking, @selector(setTrackingDampingRatio:), G1C_SendD0(rs, @selector(dampingRatio)));
        if ([tracking respondsToSelector:@selector(setTrackingResponse:)] && [rs respondsToSelector:@selector(response)]) G1C_SendVD(tracking, @selector(setTrackingResponse:), G1C_SendD0(rs, @selector(response)));
    }
    id m = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : nil;
    if (!m) return base;
    if (tracking && [m respondsToSelector:@selector(setLayoutSettings:)]) G1B_SendV1(m, @selector(setLayoutSettings:), tracking);
    id ws = G1C_Resp(ms, @selector(windowDragAnimationSettings)) ? G1B_Send0(ms, @selector(windowDragAnimationSettings)) : nil;
    if (ws && [m respondsToSelector:@selector(setPositionSettings:)]) G1B_SendV1(m, @selector(setPositionSettings:), ws);
    return m;
}
static BOOL G1C_Wd_WindowVisible(id self, SEL _cmd) { return YES; }

// ---- WindowDragDestination (UNSURE: composition over the 16.0 algorithm) ----
static char kWddLast, kWddInitAttrs;
static id G1C_Wdd_Gesture(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gWddParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event) return r;
    id prop = G1C_IvarObj(self, "_proposedAppLayout");
    if (G1B_SendLL0(event, @selector(phase)) == 1) {
        id al = G1C_Resp(self, @selector(_appLayoutContainingDisplayItem:)) ? G1B_Send1(self, @selector(_appLayoutContainingDisplayItem:), G1C_IvarObj(self, "_selectedDisplayItem")) : nil;
        id at = (al && G1C_Resp(al, @selector(layoutAttributesForItem:))) ? G1B_Send1(al, @selector(layoutAttributesForItem:), G1C_IvarObj(self, "_selectedDisplayItem")) : nil;
        G1B_SET(self, kWddInitAttrs, at);
        SEL dg = NSSelectorFromString(@"draggingAppLayoutsForContinuousExposeWindowDrag");
        id initial = G1C_IvarObj(self, "_initialAppLayout");
        NSArray *dragging = G1C_Resp(self, dg) ? G1B_Send0(self, dg) : (initial ? @[ initial ] : @[]);
        id first = nil;
        for (id l in dragging) if (G1C_LayoutHas(l, G1C_IvarObj(self, "_selectedDisplayItem"))) { first = l; break; }
        long long mine = G1C_Resp(self, @selector(displayOrdinal)) ? G1B_SendLL0(self, @selector(displayOrdinal)) : 0;
        long long its = (first && G1C_Resp(first, @selector(preferredDisplayOrdinal))) ? G1B_SendLL0(first, @selector(preferredDisplayOrdinal)) : mine;
        G1C_SetIvarBool(self, "_bp_dragBeganInOtherSwitcher", its != mine);
    }
    id last = G1B_GET(self, kWddLast);
    BOOL same = last && prop && G1C_Resp(last, @selector(containsAllItemsFromAppLayout:)) && G1B_SendB1(last, @selector(containsAllItemsFromAppLayout:), prop) && G1B_SendB1(prop, @selector(containsAllItemsFromAppLayout:), last);
    if (prop && !same && gInvalidateRespCls) {
        G1B_SET(self, kWddLast, prop);
        SEL ii = @selector(initWithTransitioningFromAppLayout:transitioningToAppLayout:animated:);
        id resp = ((id (*)(id, SEL, id, id, BOOL))objc_msgSend)([gInvalidateRespCls alloc], ii, last, prop, YES);
        if (resp) r = G1B_AppendTo(resp, r);
    }
    return r;
}
static double G1C_Wdd_WidthThreshold(id self, SEL _cmd) {
    id p = G1C_IvarObj(self, "_proposedAppLayout") ?: G1C_IvarObj(self, "_initialAppLayout");
    SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:");
    SEL wt = NSSelectorFromString(@"widthThresholdToHideStrip");
    id model = (p && G1C_Resp(self, om)) ? G1B_Send1(self, om, p) : nil;
    if (model && [model respondsToSelector:wt]) return G1C_SendD0(model, wt);
    return G1B_SUPER(double, gWddParent, self, _cmd, (struct objc_super *, SEL));
}
static id G1C_Wdd_ProposedForDrag(id self, SEL _cmd) { return G1C_IvarObj(self, "_proposedAppLayout"); }
static BOOL G1C_Wdd_AnyProposed(id self, SEL _cmd) { return G1C_LayoutHas(G1C_IvarObj(self, "_proposedAppLayout"), G1C_IvarObj(self, "_selectedDisplayItem")); }

// ---- WindowDragRoot ----
static id G1C_Wdr_Init(id self, SEL _cmd, long long mode, id initial) {
    SEL gi = NSSelectorFromString(@"initWithStartingEnvironmentMode:");
    id me = nil;
    if (class_getInstanceMethod(gWdrGrand, gi)) me = G1B_SUPER(id, gWdrGrand, self, gi, (struct objc_super *, SEL, long long), mode);
    else me = G1B_SUPER(id, gWdrGrand, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1C_SetIvarObj(me, "_initialAppLayout", initial);
    return me;
}
static id G1C_Wdr_GestureChild(id self, SEL _cmd, id event, id activeTransition) {
    id sel = G1C_Resp(event, @selector(selectedAppLayout)) ? G1B_Send0(event, @selector(selectedAppLayout)) : nil;
    id item = (sel && G1C_Resp(sel, @selector(itemForLayoutRole:))) ? G1C_SendLL1(sel, @selector(itemForLayoutRole:), 1) : nil;
    id gid = G1C_Resp(event, @selector(gestureID)) ? G1B_Send0(event, @selector(gestureID)) : nil;
    id content = G1C_NewWindowDragContentFor(gid, G1C_IvarObj(self, "_initialAppLayout"), item);
    if (!content || !sel || !gFilteringCls) return G1B_SUPER(id, gWdrParent, self, _cmd, (struct objc_super *, SEL, id, id), event, activeTransition);
    SEL fi = NSSelectorFromString(@"initWithAppLayouts:modifier:");
    if (![gFilteringCls instancesRespondToSelector:fi]) return nil;
    return G1C_Send2([gFilteringCls alloc], fi, @[ sel ], content) ;
}
static id G1C_Wdr_Gesture(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gWdrGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    if (event && G1B_SendLL0(event, @selector(phase)) == 1) { id inv = G1C_NewInvalidateAdjusted(); if (inv) r = G1B_AppendTo(inv, r); }
    return r;
}
static id G1C_Wdr_Transition(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gWdrGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    id to = G1C_Resp(event, @selector(toAppLayout)) ? G1B_Send0(event, @selector(toAppLayout)) : nil;
    if (!to) {
        Class al = NSClassFromString(@"SBAppLayout");
        id home = (al && [al respondsToSelector:@selector(homeScreenAppLayout)]) ? G1B_Send0((id)al, @selector(homeScreenAppLayout)) : nil;
        SEL mo = NSSelectorFromString(@"appLayoutByModifyingPreferredDisplayOrdinal:");
        if (home && [home respondsToSelector:mo] && G1C_Resp(event, @selector(displayOrdinal))) home = G1C_SendLL1(home, mo, G1B_SendLL0(event, @selector(displayOrdinal)));
        to = home;
    }
    G1C_SetIvarObj(self, "_initialAppLayout", to);
    long long phase = G1C_Resp(event, @selector(phase)) ? G1B_SendLL0(event, @selector(phase)) : 0;
    if (phase == 1) { id gm = G1C_Resp(self, @selector(gestureModifier)) ? G1B_Send0(self, @selector(gestureModifier)) : nil; if (gm && G1C_Resp(gm, @selector(setState:))) G1B_SendVLL(gm, @selector(setState:), 1); }
    if (phase == 3 && G1C_Resp(self, @selector(setState:))) G1B_SendVLL(self, @selector(setState:), 1);
    return r;
}
static id G1C_Wdr_Anim(id self, SEL _cmd, id element) {
    id base = G1B_SUPER(id, gWdrGrand, self, _cmd, (struct objc_super *, SEL, id), element);
    id gm = G1C_Resp(self, @selector(gestureModifier)) ? G1B_Send0(self, @selector(gestureModifier)) : nil;
    if (!gm || !base || !element) return base;
    SEL tp = NSSelectorFromString(@"switcherLayoutElementType");
    if (!G1C_Resp(element, tp) || G1B_SendLL0(element, tp) != 0) return base;
    id selLayout = G1C_Resp(self, @selector(selectedAppLayout)) ? G1B_Send0(self, @selector(selectedAppLayout)) : nil;
    if (selLayout && G1C_Resp(element, @selector(containsAnyItemFromAppLayout:)) && G1B_SendB1(element, @selector(containsAnyItemFromAppLayout:), selLayout)) return base;
    id m = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : nil;
    id ms = G1C_Resp(self, @selector(medusaSettings)) ? G1B_Send0(self, @selector(medusaSettings)) : nil;
    id rs = G1C_Resp(ms, @selector(resizeAnimationSettings)) ? G1B_Send0(ms, @selector(resizeAnimationSettings)) : nil;
    if (!m || !rs) return base;
    G1B_SendV1(m, @selector(setLayoutSettings:), rs);
    G1B_SendVLL(m, @selector(setUpdateMode:), 3);
    return m;
}
static id G1C_Wdr_Resign(id self, SEL _cmd) { return @{}; }

// ---- event: sizeOfSelectedDisplayItem (new field) + producer ----
static char kEvSize;
static CGSize G1C_Wdev_GetSize(id self, SEL _cmd) { NSValue *v = G1B_GET(self, kEvSize); return v ? [v CGSizeValue] : CGSizeZero; }
static void G1C_Wdev_SetSize(id self, SEL _cmd, CGSize s) { G1B_SET(self, kEvSize, [NSValue valueWithCGSize:s]); }

static BOOL G1C_BuildWindowDragFamily(void) {
    gWdParent = NSClassFromString(@"SBContinuousExposeWindowDragSwitcherModifier");
    gWddParent = NSClassFromString(@"SBContinuousExposeWindowDragDestinationSwitcherModifier");
    gWdrParent = NSClassFromString(@"SBContinuousExposeWindowDragRootSwitcherModifier");
    if (!gWdParent || !gWddParent || !gWdrParent) return NO;
    gWdGrand = class_getSuperclass(gWdParent);
    gWdrGrand = class_getSuperclass(gWdrParent);
    // event field (adds methods only when the class lacks them: 16.2 already has them)
    Class ev = NSClassFromString(@"SBContinuousExposeWindowDragModifierEvent");
    if (ev && !class_getInstanceMethod(ev, @selector(sizeOfSelectedDisplayItem))) {
        class_addMethod(ev, @selector(sizeOfSelectedDisplayItem), (IMP)G1C_Wdev_GetSize, "{CGSize=dd}16@0:8");
        class_addMethod(ev, NSSelectorFromString(@"setSizeOfSelectedDisplayItem:"), (IMP)G1C_Wdev_SetSize, "v32@0:8{CGSize=dd}16");
    }
    {   // destination
        const G1BIvar iv[] = { { "_bp_dragBeganInOtherSwitcher", 1, 0, "B" } };
        const G1BMethod m[] = {
            { "handleGestureEvent:", (IMP)G1C_Wdd_Gesture, "@24@0:8@16" },
            { "_widthThresholdToHideStrips", (IMP)G1C_Wdd_WidthThreshold, "d16@0:8" },
            { "proposedAppLayoutForContinuousExposeWindowDrag", (IMP)G1C_Wdd_ProposedForDrag, "@16@0:8" },
            { "_anyProposedAppLayoutContainsSelectedDisplayItem", (IMP)G1C_Wdd_AnyProposed, "B16@0:8" },
        };
        gWddCls = G1B_MakeClass("BP162ContinuousExposeWindowDragDestinationSwitcherModifier", gWddParent, iv, 1, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    {   // drag modifier
        const G1BIvar iv[] = {
            { "_bp_sizeOfSelectedDisplayItem", sizeof(CGSize), 3, "{CGSize=dd}" },
            { "_bp_dragBeganInOtherSwitcher", 1, 0, "B" }, { "_bp_dragBeganInAnyStrip", 1, 0, "B" }, { "_bp_dragBeganOnAnyStage", 1, 0, "B" },
        };
        const G1BMethod m[] = {
            { "initWithGestureID:initialAppLayout:selectedDisplayItem:", (IMP)G1C_Wd_Init, "@40@0:8@16@24@32" },
            { "preferredCenterForSelectedItemInDestinationModifier:", (IMP)G1C_Wd_PreferredCenter, "{CGPoint=dd}24@0:8@16" },
            { "handleGestureEvent:", (IMP)G1C_Wd_Gesture, "@24@0:8@16" },
            { "appLayoutContainingAppLayout:", (IMP)G1C_Wd_AppLayoutContainingAppLayout, "@24@0:8@16" },
            { "appLayoutOnContinuousExposeStage", (IMP)G1C_Wd_AppLayoutOnStage, "@16@0:8" },
            { "continuousExposeStripProgress", (IMP)G1C_Wd_StripProgress, "d16@0:8" },
            { "frameForIndex:", (IMP)G1C_Wd_FrameForIndex, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
            { "scaleForIndex:", (IMP)G1C_Wd_ScaleForIndex, "d24@0:8Q16" },
            { "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)G1C_Wd_UseAnchorPin, "B24@0:8Q16" },
            { "shouldPinLayoutRolesToSpace:", (IMP)G1C_Wd_PinRoles, "B24@0:8Q16" },
            { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_Wd_FrameForRole, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32" },
            { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_Wd_Opacity, "d40@0:8q16@24Q32" },
            { "visibleAppLayouts", (IMP)G1C_Wd_Visible, "@16@0:8" },
            { "perspectiveAngleForAppLayout:", (IMP)G1C_Wd_Perspective, "d24@0:8@16" },
            { "animationAttributesForLayoutElement:", (IMP)G1C_Wd_AnimAttrs, "@24@0:8@16" },
            { "isSwitcherWindowVisible", (IMP)G1C_Wd_WindowVisible, "B16@0:8" },
            { "_anyItemExceedsWidthThresholdToHideStrip", (IMP)G1C_Wd_AnyExceeds, "B16@0:8" },
            { "_anyProposedAppLayoutContainsSelectedDisplayItem", (IMP)G1C_Wd_AnyProposedHasQ, "B16@0:8" },
        };
        gWdCls = G1B_MakeClass("BP162ContinuousExposeWindowDragSwitcherModifier", gWdParent, iv, 4, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    {   // root
        const G1BMethod m[] = {
            { "initWithStartingEnvironmentMode:initialAppLayout:", (IMP)G1C_Wdr_Init, "@32@0:8q16@24" },
            { "gestureChildModifierForGestureEvent:activeTransitionModifier:", (IMP)G1C_Wdr_GestureChild, "@32@0:8@16@24" },
            { "handleGestureEvent:", (IMP)G1C_Wdr_Gesture, "@24@0:8@16" },
            { "handleTransitionEvent:", (IMP)G1C_Wdr_Transition, "@24@0:8@16" },
            { "animationAttributesForLayoutElement:", (IMP)G1C_Wdr_Anim, "@24@0:8@16" },
            { "appLayoutsToResignActive", (IMP)G1C_Wdr_Resign, "@16@0:8" },
        };
        gWdrCls = G1B_MakeClass("BP162ContinuousExposeWindowDragRootSwitcherModifier", gWdrParent, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    return gWdCls && gWdrCls;
}
static id G1C_NewWindowDragModifier(id gid, id initial, id item) {
    Class c = gWdCls ?: gWdParent;
    SEL s = @selector(initWithGestureID:initialAppLayout:selectedDisplayItem:);
    if (!c || ![c instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, id, id, id))objc_msgSend)([c alloc], s, gid, initial, item);
}
static id G1C_NewWindowDragRoot(long long mode, id initial) {
    Class c = gWdrCls;
    SEL s = @selector(initWithStartingEnvironmentMode:initialAppLayout:);
    if (!c || ![c instancesRespondToSelector:s]) return nil;
    return ((id (*)(id, SEL, long long, id))objc_msgSend)([c alloc], s, mode, initial);
}

// event copy + producer of the size (hooks on 16.0 classes)
%group G1C_WdEvent
%hook SBContinuousExposeWindowDragModifierEvent
- (id)copyWithZone:(NSZone *)zone {
    id c = %orig;
    id v = G1B_GET(self, kEvSize);
    if (c && v) G1B_SET(c, kEvSize, v);
    return c;
}
%end
%hook SBFluidSwitcherGestureWorkspaceTransaction
- (id)_currentGestureEventForGesture:(id)gesture {
    id ev = %orig;
    if (G1C_ON() && ev && [ev respondsToSelector:@selector(isContinuousExposeWindowDragEvent)] && G1B_SendB0(ev, @selector(isContinuousExposeWindowDragEvent))) {
        SEL ts = NSSelectorFromString(@"sizeOfSelectedDisplayItem"), es = NSSelectorFromString(@"setSizeOfSelectedDisplayItem:");
        if ([self respondsToSelector:ts] && [ev respondsToSelector:es]) {
            CGSize sz = G1C_SendSize0(self, ts);
            ((void (*)(id, SEL, CGSize))objc_msgSend)(ev, es, sz);
        }
    }
    return ev;
}
%end
%end

// ============================================================================================================
// 1b / 1f  SBInlineAppExposeContinuousExposeSwitcherModifier and SBHomeScreenContinuousExposeSwitcherModifier
//     BP162 subclasses of the 16.0 classes (only the changed / new methods). DONE for behaviour, UNSURE for the geometry details
//     listed in the md (frameForLayoutRole / scaleForLayoutRole / homeScreenDimmingAlpha keep the 16.0 maths).
// ============================================================================================================
static Class gInlParent, gInlCls, gHsParent, gHsCls;
static char kInlHidden, kInlShowing;

static id G1C_NewPerformFromRequest(id req, BOOL gesture) {
    Class pc = NSClassFromString(@"SBPerformTransitionSwitcherEventResponse");
    SEL ps = @selector(initWithTransitionRequest:gestureInitiated:);
    if (!req || !pc || ![pc instancesRespondToSelector:ps]) return nil;
    return ((id (*)(id, SEL, id, BOOL))objc_msgSend)([pc alloc], ps, req, gesture);
}
static id G1C_NewBareRequest(void) {
    Class rc = NSClassFromString(@"SBSwitcherTransitionRequest");
    return rc ? [[rc alloc] init] : nil;
}
static void G1C_HandleEvent(id event, NSString *reason) {
    SEL h = NSSelectorFromString(@"handleWithReason:");
    if (event && [event respondsToSelector:h]) G1B_SendV1(event, h, reason);
}

// request for "bring the tapped item to front inside its layout and activate it" (shared by the tap and header-tap handlers)
static id G1C_Inl_ActivationRequest(id self, id layout, id item) {
    id req = G1C_NewBareRequest();
    if (!req || !layout || !item) return nil;
    id containing = G1C_Resp(self, @selector(appLayoutContainingAppLayout:)) ? G1B_Send1(self, @selector(appLayoutContainingAppLayout:), layout) : layout;
    id fronted = G1C_Resp(self, @selector(appLayoutByBringingItemToFront:inAppLayout:)) ? G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), item, containing) : containing;
    if ([req respondsToSelector:@selector(setAppLayout:)]) G1B_SendV1(req, @selector(setAppLayout:), fronted ?: containing);
    if ([req respondsToSelector:@selector(setActivatingDisplayItem:)]) G1B_SendV1(req, @selector(setActivatingDisplayItem:), item);
    return req;
}
static id G1C_Inl_Tap(id self, SEL _cmd, id event) {                      // 0x1c7686a58
    id r = G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event || (G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled)))) return r;
    id layout = G1B_Send0(event, @selector(appLayout));
    id active = G1C_IvarObj(self, "_activeAppLayout");
    id resp = nil;
    if (layout && active && [layout isEqual:active]) {
        Class rq = NSClassFromString(@"SBSwitcherTransitionRequest");
        SEL rs = NSSelectorFromString(@"requestForTapAppLayoutEvent:");
        id req = (rq && [rq respondsToSelector:rs]) ? G1B_Send1((id)rq, rs, event) : nil;
        resp = G1C_NewPerformFromRequest(req, NO);
    } else if (layout) {
        long long role = G1B_SendLL0(event, @selector(layoutRole));
        id item = G1C_Resp(layout, @selector(itemForLayoutRole:)) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
        resp = G1C_NewPerformFromRequest(G1C_Inl_ActivationRequest(self, layout, item), NO);
    }
    if (resp) { r = G1B_AppendTo(resp, r); G1C_HandleEvent(event, @"I"); }
    return r;
}
static id G1C_Inl_HeaderTap(id self, SEL _cmd, id event) {                // 0x1c7686bf8 (new)
    if (!G1C_ON() || !event || (G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled)))) return nil;
    id layout = G1B_Send0(event, @selector(appLayout));
    long long role = G1B_SendLL0(event, @selector(layoutRole));
    id item = (layout && G1C_Resp(layout, @selector(itemForLayoutRole:))) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
    SEL multi = NSSelectorFromString(@"displayItemSupportsMultipleWindowsIndicator:");
    if (!item || !G1C_Resp(self, multi) || !G1B_SendB1(self, multi, item)) return nil;
    NSString *bid = G1C_Resp(item, @selector(bundleIdentifier)) ? G1B_Send0(item, @selector(bundleIdentifier)) : nil;
    NSString *expose = G1C_IvarObj(self, "_appExposeBundleIdentifier");
    id active = G1C_IvarObj(self, "_activeAppLayout");
    id out = nil;
    if (bid && expose && [bid isEqualToString:expose]) {
        if (active && [layout isEqual:active]) {                                     // header of the active window: pulse it
            Class pc = NSClassFromString(@"SBPulseDisplayItemSwitcherModifier");
            id pulse = (pc && [pc instancesRespondToSelector:@selector(initWithDisplayItem:)]) ? G1B_Send1([pc alloc], @selector(initWithDisplayItem:), item) : nil;
            Class cc = NSClassFromString(@"SBChildModifierEventResponse");
            SEL ci = NSSelectorFromString(@"initWithModifier:level:");
            id add = (pulse && cc && [cc instancesRespondToSelector:ci]) ? ((id (*)(id, SEL, id, long long))objc_msgSend)([cc alloc], ci, pulse, 3) : nil;
            out = add;
        } else {
            out = G1C_NewPerformFromRequest(G1C_Inl_ActivationRequest(self, layout, item), NO);
        }
    } else {
        id req = G1C_NewBareRequest();
        if (req) {
            if ([req respondsToSelector:@selector(setSource:)]) G1B_SendVLL(req, @selector(setSource:), 3);
            if ([req respondsToSelector:@selector(setBundleIdentifierForAppExpose:)]) G1B_SendV1(req, @selector(setBundleIdentifierForAppExpose:), bid);
            out = G1C_NewPerformFromRequest(req, NO);
        }
    }
    if (out) G1C_HandleEvent(event, @"I");
    return out;
}
static id G1C_Inl_ReopenResponse(id self) {                                 // _responseToUpdateReopenClosedWindowsButtonPresenceIfNeeded (0x1c7688f84)
    NSNumber *prevN = G1B_GET(self, kInlHidden);
    BOOL could = prevN.longLongValue != 0;
    SEL q = NSSelectorFromString(@"numberOfHiddenAppLayoutsForBundleIdentifier:");
    long long n = G1C_Resp(self, q) ? G1C_SendLLId(self, q, G1C_IvarObj(self, "_appExposeBundleIdentifier")) : 0;
    G1B_SET(self, kInlHidden, @(n));
    if (n != 0 && !could) {
        G1B_SET(self, kInlShowing, @NO);
        return G1C_NewTimerResponse(0.5, @"SBInlineAppExposeContinuousExposeSwitcherModifierTimerEventReason");     // delay = animationSettings.reopenButtonFadeInDelay (UNSURE default)
    }
    return nil;
}
static id G1C_Inl_Insertion(id self, SEL _cmd, id event) {                 // 0x1c7686824
    id r = G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1C_ON() && event && G1B_SendLL0(event, @selector(phase)) == 2) r = G1B_AppendTo(G1C_Inl_ReopenResponse(self), r);
    return r;
}
static id G1C_Inl_Transition(id self, SEL _cmd, id event) {                // 0x1c76868e0
    id r = G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event) return r;
    long long phase = G1B_SendLL0(event, @selector(phase));
    if (phase == 2) {
        NSString *from = G1C_Resp(event, @selector(fromAppExposeBundleID)) ? G1B_Send0(event, @selector(fromAppExposeBundleID)) : nil;
        NSString *to = G1C_Resp(event, @selector(toAppExposeBundleID)) ? G1B_Send0(event, @selector(toAppExposeBundleID)) : nil;
        if (to && (!from || ![from isEqualToString:to])) {
            r = G1B_AppendTo(G1C_Inl_ReopenResponse(self), r);
            Class ir = NSClassFromString(@"SBInvalidateReopenButtonTextSwitcherEventResponse");
            if (ir) r = G1B_AppendTo([[ir alloc] init], r);
        }
    }
    return r;
}
static id G1C_Inl_Timer(id self, SEL _cmd, id event) {                    // 0x1c7686f34
    id r = G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
    NSString *reason = G1C_Resp(event, @selector(reason)) ? G1B_Send0(event, @selector(reason)) : nil;
    if ([reason isEqualToString:@"SBInlineAppExposeContinuousExposeSwitcherModifierTimerEventReason"]) {
        G1B_SET(self, kInlShowing, @YES);
        r = G1B_AppendTo(G1B_NewUpdateLayoutResponse(8, 3), r);
    }
    return r;
}
static BOOL G1C_Inl_CanShow(id self) { return [(NSNumber *)G1B_GET(self, kInlHidden) longLongValue] != 0; }
static double G1C_Inl_ReopenAlpha(id self, SEL _cmd) {
    if (G1C_Inl_CanShow(self) && [(NSNumber *)G1B_GET(self, kInlShowing) boolValue]) return 1.0;
    return 0.0;
}
static double G1C_Inl_ReopenScale(id self, SEL _cmd) {
    if ([(NSNumber *)G1B_GET(self, kInlShowing) boolValue]) return 1.0;
    id s = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id a = G1C_Resp(s, @selector(animationSettings)) ? G1B_Send0(s, @selector(animationSettings)) : nil;
    double v = G1B_Dbl0(a, NSSelectorFromString(@"reopenButtonInitialScale"));
    return v > 0 ? v : 1.0;
}
static BOOL G1C_Inl_IsShowing(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kInlShowing) boolValue]; }
static void G1C_Inl_SetShowing(id self, SEL _cmd, BOOL v) { G1B_SET(self, kInlShowing, @(v)); }
static long long G1C_Inl_NumHidden(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kInlHidden) longLongValue]; }
static void G1C_Inl_SetNumHidden(id self, SEL _cmd, long long v) { G1B_SET(self, kInlHidden, @(v)); }
static double G1C_Inl_TitleOpacity(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id l = i < ls.count ? ls[i] : nil;
    id active = G1C_IvarObj(self, "_activeAppLayout");
    return (l && active && [l isEqual:active]) ? 0.0 : 1.0;
}
static BOOL G1C_Inl_Focus(id self, SEL _cmd, id layout) { id a = G1C_IvarObj(self, "_activeAppLayout"); return layout && a && [layout isEqual:a]; }
static BOOL G1C_Inl_NoGrabber(id self, SEL _cmd, id layout) { return NO; }
static BOOL G1C_Inl_Pointer(id self, SEL _cmd) { return YES; }
static CGRect G1C_Inl_FrameForIndex(id self, SEL _cmd, unsigned long long i) {
    // 16.2 mirrors the inline App Expose grid for right-to-left layouts; the vertical maths is identical to 16.0.
    CGRect f = G1B_SUPER(CGRect, gInlParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    if (!G1C_ON() || [[UIApplication sharedApplication] userInterfaceLayoutDirection] != UIUserInterfaceLayoutDirectionRightToLeft) return f;
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    id layout = i < ls.count ? ls[i] : nil;
    SEL inl = NSSelectorFromString(@"_inlineAppExposeAppLayouts");
    id set = G1C_Resp(self, inl) ? G1B_Send0(self, inl) : nil;
    if (!layout || ![set respondsToSelector:@selector(containsObject:)] || ![set containsObject:layout]) return f;
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    f.origin.x = b.origin.x + b.origin.x + b.size.width - f.origin.x - f.size.width;       // mirror about the container bounds
    return f;
}
static BOOL G1C_Inl_Occluded(id self, SEL _cmd, long long role, id layout) {
    BOOL v = G1B_SUPER(BOOL, gInlParent, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    if (v || !G1C_ON()) return v;
    SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:"), cov = NSSelectorFromString(@"isItemCoveredByFullyOccludedPeekingItem:");
    id model = (layout && G1C_Resp(self, om)) ? G1B_Send1(self, om, layout) : nil;
    id item = (layout && G1C_Resp(layout, @selector(itemForLayoutRole:))) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
    return (model && item && [model respondsToSelector:cov]) ? G1B_SendB1(model, cov, item) : NO;
}
static id G1C_Inl_Highlight(id self, SEL _cmd, id event) {
    if (G1C_ON() && event && G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled))) return nil;      // 16.2 ignores handled highlight events
    return G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
}

// ---- HomeScreen ----
static char kHsStrip;       // retained by the object (the run-time ivar "_stripModifier" below is unretained: object_setIvar on a class_addIvar'ed ivar has no ARC layout)
static id G1C_Hs_Init(id self, SEL _cmd) {
    id me = G1B_SUPER(id, gHsParent, self, _cmd, (struct objc_super *, SEL));
    Class sc = NSClassFromString(@"SBStripContinuousExposeSwitcherModifier");        // the ported / real strip modifier (FullScreen-Strip package)
    if (BP_LogEnabled()) BP_Log(@"GLITCH home floor created (strip modifier class %@)", sc ? @"PRESENT: strip child will be attached" : @"absent (16.0 has none): no strip child");
    if (me && sc && [me respondsToSelector:@selector(addChildModifier:)]) {
        id strip = [[sc alloc] init];
        if (strip) { G1B_SET(me, kHsStrip, strip); G1B_SendV1(me, @selector(addChildModifier:), strip); }
    }
    return me;
}
// 6.8 diagnostics only (answers are the 16.0 Home floor's own, via super): what the Home floor says about the first cards once the transition modifier is gone
static NSString *gHsLastOffset;
static NSString *gHsLastOpacity[2];
static CGPoint G1C_Hs_ContentOffset(id self, SEL _cmd) {
    CGPoint p = G1B_SUPER(CGPoint, gHsParent, self, _cmd, (struct objc_super *, SEL));
    if (BP_LogEnabled()) {
        NSString *sig = NSStringFromCGPoint(p);
        BOOL changed = NO;
        @synchronized(@"BP162.hs") { if (![gHsLastOffset isEqualToString:sig]) { gHsLastOffset = sig; changed = YES; } }
        if (changed) BP_Log(@"GLITCH home floor scrollViewContentOffset=%@", sig);
    }
    return p;
}
static double G1C_Hs_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long idx) {
    double o = G1B_SUPER(double, gHsParent, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, idx);
    if (idx < 2 && BP_LogEnabled()) {
        SEL fs = @selector(frameForIndex:), vs = @selector(visibleAppLayouts);
        CGRect f = G1C_Resp(self, fs) ? ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, fs, idx) : CGRectZero;
        id vis = G1C_Resp(self, vs) ? G1B_Send0(self, vs) : nil;
        BOOL inVis = layout && [vis respondsToSelector:@selector(containsObject:)] && ((BOOL (*)(id, SEL, id))objc_msgSend)(vis, @selector(containsObject:), layout);
        NSString *sig = [NSString stringWithFormat:@"%.2f %@ v%d", o, NSStringFromCGRect(f), inVis];
        BOOL changed = NO;
        @synchronized(@"BP162.hs") { if (![gHsLastOpacity[idx] isEqualToString:sig]) { gHsLastOpacity[idx] = sig; changed = YES; } }
        if (changed) BP_Log(@"GLITCH home floor idx=%llu role=%lld layout=%@ opacity/frame/inVisible: %@", idx, role, G1C_DbgLayout(layout), sig);
    }
    return o;
}
static double G1C_Hs_StripProgress(id self, SEL _cmd) { return 0.0; }
static BOOL G1C_Hs_Grabber(id self, SEL _cmd, id layout) { return NO; }
static id G1C_Hs_ChildResponse(id self, SEL _cmd, id proposed, id child, id event) {
    // UNSURE: 16.2 additionally rewrites type-31 (perform transition) responses coming from the peek transition modifier when a peek
    // ends (appLayoutWithItemsPassingTest: filter, block 0x1c77f3e04). Without the peek-ended event nothing is rewritten here.
    return G1B_SUPER(id, gHsParent, self, _cmd, (struct objc_super *, SEL, id, id, id), proposed, child, event);
}

static BOOL G1C_BuildFloors(void) {
    gInlParent = NSClassFromString(@"SBInlineAppExposeContinuousExposeSwitcherModifier");
    gHsParent = NSClassFromString(@"SBHomeScreenContinuousExposeSwitcherModifier");
    if (gInlParent) {
        const G1BMethod m[] = {
            { "handleTapAppLayoutEvent:", (IMP)G1C_Inl_Tap, "@24@0:8@16" },
            { "handleTapAppLayoutHeaderEvent:", (IMP)G1C_Inl_HeaderTap, "@24@0:8@16" },
            { "handleInsertionEvent:", (IMP)G1C_Inl_Insertion, "@24@0:8@16" },
            { "handleTransitionEvent:", (IMP)G1C_Inl_Transition, "@24@0:8@16" },
            { "handleTimerEvent:", (IMP)G1C_Inl_Timer, "@24@0:8@16" },
            { "handleHighlightEvent:", (IMP)G1C_Inl_Highlight, "@24@0:8@16" },
            { "reopenClosedWindowsButtonAlpha", (IMP)G1C_Inl_ReopenAlpha, "d16@0:8" },
            { "reopenClosedWindowsButtonScale", (IMP)G1C_Inl_ReopenScale, "d16@0:8" },
            { "isShowingReopenClosedWindowsButton", (IMP)G1C_Inl_IsShowing, "B16@0:8" },
            { "setShowingReopenClosedWindowsButton:", (IMP)G1C_Inl_SetShowing, "v20@0:8B16" },
            { "numberOfHiddenAppLayouts", (IMP)G1C_Inl_NumHidden, "Q16@0:8" },
            { "setNumberOfHiddenAppLayouts:", (IMP)G1C_Inl_SetNumHidden, "v24@0:8Q16" },
            { "titleAndIconOpacityForIndex:", (IMP)G1C_Inl_TitleOpacity, "d24@0:8Q16" },
            { "isFocusEnabledForAppLayout:", (IMP)G1C_Inl_Focus, "B24@0:8@16" },
            { "isResizeGrabberVisibleForAppLayout:", (IMP)G1C_Inl_NoGrabber, "B24@0:8@16" },
            { "isItemContainerPointerInteractionEnabled", (IMP)G1C_Inl_Pointer, "B16@0:8" },
            { "frameForIndex:", (IMP)G1C_Inl_FrameForIndex, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
            { "_isLayoutRoleOccluded:inAppLayout:", (IMP)G1C_Inl_Occluded, "B32@0:8q16@24" },
        };
        gInlCls = G1B_MakeClass("BP162InlineAppExposeContinuousExposeSwitcherModifier", gInlParent, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    if (gHsParent) {
        const G1BIvar iv[] = { { "_stripModifier", sizeof(id), 3, "@" } };
        const G1BMethod m[] = {
            { "init", (IMP)G1C_Hs_Init, "@16@0:8" },
            { "continuousExposeStripProgress", (IMP)G1C_Hs_StripProgress, "d16@0:8" },
            { "scrollViewContentOffset", (IMP)G1C_Hs_ContentOffset, "{CGPoint=dd}16@0:8" },
            { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_Hs_Opacity, "d40@0:8q16@24Q32" },
            { "isResizeGrabberVisibleForAppLayout:", (IMP)G1C_Hs_Grabber, "B24@0:8@16" },
            { "responseForProposedChildResponse:childModifier:event:", (IMP)G1C_Hs_ChildResponse, "@40@0:8@16@24@32" },
        };
        gHsCls = G1B_MakeClass("BP162HomeScreenContinuousExposeSwitcherModifier", gHsParent, iv, 1, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    return gInlCls || gHsCls;
}
static id G1C_NewInlineAppExpose(id activeLayout, NSString *bundleID) {
    Class c = gInlCls ?: gInlParent;
    SEL s = NSSelectorFromString(@"initWithActiveAppLayout:appExposeBundleIdentifier:");
    if (!c || ![c instancesRespondToSelector:s]) return nil;
    return G1C_Send2([c alloc], s, activeLayout, bundleID);
}
static id G1C_NewHomeModifier(void) {
    Class c = gHsCls ?: gHsParent;
    return c ? [[c alloc] init] : nil;
}

// ============================================================================================================
// 1a  SBAppSwitcherContinuousExposeSwitcherModifier  (the Stage Manager "all windows" switcher)
//     BP162AppSwitcherContinuousExposeSwitcherModifier : SBAppSwitcherContinuousExposeSwitcherModifier (16.0)
//     Behaviour layer (tap / header tap / tap outside / removal / flags / resign-active / pile opacity): DONE.
//     Pile layout (buildLayoutCalculationsForCache:, frameForIndex:, scaleForIndex:, fitted size): UNSURE, OFF by default
//     (G1C_PILES_DEFAULT 0). The 16.0 scrolling maths (contentOffsetForIndex:alignment: etc.) is kept and reads our frames.
// ============================================================================================================
#ifndef G1C_PILES_DEFAULT
#define G1C_PILES_DEFAULT 0
#endif
static Class gAsParent, gAsCls;
static char kAsCalc, kAsToken;

static BOOL G1C_PilesOn(void) { return G1C_ON() && BP_On(F_G1C_PILES); }     // opt-in (Backport162.on.g1c_piles): review B2 - the 16.0 role frames (frameForLayoutRole:...withBounds:) are not ported, so windows land off their cards
static BOOL G1C_As_Handles(id self, const char *iv) {
    Ivar v = class_getInstanceVariable(object_getClass(self), iv);
    return v ? G1C_IvarBool(self, iv) : YES;
}

// --- pile layout (reconstruction of buildLayoutCalculationsForCache: 0x1c7812acc) ---
static NSString *G1C_As_Token(id self) {
    SEL g1 = NSSelectorFromString(@"appLayoutsGenerationCount"), g2 = NSSelectorFromString(@"continuousExposeIdentifiersGenerationCount");
    CGRect b = G1C_Resp(self, @selector(containerViewBounds)) ? G1C_SendRect0(self, @selector(containerViewBounds)) : CGRectZero;
    return [NSString stringWithFormat:@"%lld/%lld/%lld/%@/%lld", G1C_Resp(self, g1) ? G1B_SendLL0(self, g1) : 0, G1C_Resp(self, g2) ? G1B_SendLL0(self, g2) : 0,
            G1C_Resp(self, @selector(switcherInterfaceOrientation)) ? G1B_SendLL0(self, @selector(switcherInterfaceOrientation)) : 0, NSStringFromCGRect(b),
            G1C_IvarLL(self, "_bp_eventGen")];
}
static double G1C_RoundForScale(double v, double scale) { return scale > 0 ? round(v * scale) / scale : round(v); }
static double G1C_As_CardHeight(id self) {
    id ca = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    double pad = G1B_Dbl0(ca, @selector(screenEdgePadding)), vEdge = G1B_Dbl0(ca, NSSelectorFromString(@"switcherVerticalEdgeSpacing")), vInter = G1B_Dbl0(ca, NSSelectorFromString(@"switcherVerticalInterItemSpacing"));
    long long rows = G1C_Resp(self, NSSelectorFromString(@"numberOfRowsInGridSwitcher")) ? G1B_SendLL0(self, NSSelectorFromString(@"numberOfRowsInGridSwitcher")) : 1;
    if (rows < 1) rows = 1;
    CGRect vb = G1C_Resp(self, @selector(switcherViewBounds)) ? G1C_SendRect0(self, @selector(switcherViewBounds)) : CGRectZero;
    double dock = G1B_Dbl0(self, @selector(floatingDockHeight)), status = G1B_Dbl0(self, NSSelectorFromString(@"statusBarHeight")), sc = G1B_Dbl0(self, @selector(screenScale));
    double avail = vb.size.height - dock - pad - status - 2 * vEdge;
    return G1C_RoundForScale((avail - vInter * (rows - 1)) / rows, sc);
}
static NSDictionary *G1C_As_Build(id self) {
    NSMutableDictionary *frames = [NSMutableDictionary dictionary], *scales = [NSMutableDictionary dictionary], *piles = [NSMutableDictionary dictionary];
    id ca = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    double pad = G1B_Dbl0(ca, @selector(screenEdgePadding)), hEdge = G1B_Dbl0(ca, NSSelectorFromString(@"switcherHorizontalEdgeSpacing")),
           hInter = G1B_Dbl0(ca, NSSelectorFromString(@"switcherHorizontalInterItemSpacing")), vEdge = G1B_Dbl0(ca, NSSelectorFromString(@"switcherVerticalEdgeSpacing")),
           vInter = G1B_Dbl0(ca, NSSelectorFromString(@"switcherVerticalInterItemSpacing")), peek = G1B_Dbl0(ca, NSSelectorFromString(@"switcherPileCardMinimumPeekAmount"));
    long long rows = G1C_Resp(self, NSSelectorFromString(@"numberOfRowsInGridSwitcher")) ? G1B_SendLL0(self, NSSelectorFromString(@"numberOfRowsInGridSwitcher")) : 1;
    if (rows < 1) rows = 1;
    BOOL rtl = G1C_Resp(self, @selector(isRTLEnabled)) && G1B_SendB0(self, @selector(isRTLEnabled));
    CGRect vb = G1C_SendRect0(self, @selector(switcherViewBounds));
    double cardH = G1C_As_CardHeight(self);
    NSArray *ids = G1C_Resp(self, @selector(continuousExposeIdentifiersInSwitcher)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInSwitcher)) : @[];
    ids = [ids isKindOfClass:[NSArray class]] ? ids : [(NSOrderedSet *)ids array];
    SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), om = NSSelectorFromString(@"overlappingModelForAppLayout:");
    double x = hEdge, colW = 0, y = pad + vEdge;
    long long i = 0;
    for (id ident in ids) {
        long long row = i % rows;
        if (row == 0 && i > 0) { x += colW + hInter; colW = 0; }
        y = pad + vEdge + (cardH + vInter) * row;
        NSArray *ls = G1C_Resp(self, byId) ? G1B_Send1(self, byId, ident) : nil;
        CGRect pileBox = CGRectNull;
        double pileW = 0;
        NSUInteger k = 0;
        for (id l in ls) {
            id model = G1C_Resp(self, om) ? G1B_Send1(self, om, l) : nil;
            CGSize sz = (model && [model respondsToSelector:@selector(compactedBoundingBox)]) ? G1C_SendRect0(model, @selector(compactedBoundingBox)).size : CGSizeZero;
            if (sz.height <= 0 || sz.width <= 0) { k++; continue; }
            double s = cardH / sz.height - 0.01 * (double)k;                       // const 0x1c7a916c0 = -0.01 per stacked card
            double w = sz.width * s, h = sz.height * s;
            double cx = x + w / 2.0 + peek * (double)k, cy = y + cardH / 2.0;
            CGRect scaled = CGRectMake(cx - w / 2.0, cy - h / 2.0, w, h);
            CGRect unscaled = CGRectMake(cx - sz.width / 2.0, cy - sz.height / 2.0, sz.width, sz.height);
            frames[l] = [NSValue valueWithCGRect:unscaled];
            scales[l] = @(s);
            pileBox = CGRectUnion(pileBox, scaled);
            if (cx + w / 2.0 - x > pileW) pileW = cx + w / 2.0 - x;
            k++;
        }
        if (!CGRectIsNull(pileBox)) piles[ident] = [NSValue valueWithCGRect:pileBox];
        if (pileW > colW) colW = pileW;
        i++;
    }
    double total = x + colW + hEdge;
    if (rtl) {                                                                      // mirror inside the content width
        for (id l in [frames allKeys]) { CGRect f = [frames[l] CGRectValue]; f.origin.x = total - f.origin.x - f.size.width; frames[l] = [NSValue valueWithCGRect:f]; }
        for (id p in [piles allKeys]) { CGRect f = [piles[p] CGRectValue]; f.origin.x = total - f.origin.x - f.size.width; piles[p] = [NSValue valueWithCGRect:f]; }
    }
    return @{ @"frames": frames, @"scales": scales, @"piles": piles, @"fitted": [NSValue valueWithCGSize:CGSizeMake(total, vb.size.height)] };
}
static NSDictionary *G1C_As_Calc(id self) {
    NSString *tok = G1C_As_Token(self);
    NSDictionary *c = G1B_GET(self, kAsCalc);
    if (c && [G1B_GET(self, kAsToken) isEqualToString:tok]) return c;
    c = G1C_As_Build(self);
    G1B_SET(self, kAsCalc, c);
    G1B_SET(self, kAsToken, tok);
    return c;
}
static id G1C_As_LayoutAt(id self, unsigned long long i) { NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil; return i < ls.count ? ls[i] : nil; }
static CGRect G1C_As_FrameForIndex(id self, SEL _cmd, unsigned long long i) {
    id l = G1C_As_LayoutAt(self, i);
    NSValue *v = (G1C_PilesOn() && l) ? G1C_As_Calc(self)[@"frames"][l] : nil;
    if (!v) return G1B_SUPER(CGRect, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    CGRect f = [v CGRectValue];
    if (G1C_Resp(self, @selector(scrollViewContentOffset))) f.origin.x -= G1C_SendPoint0(self, @selector(scrollViewContentOffset)).x;
    return f;
}
static double G1C_As_ScaleForIndex(id self, SEL _cmd, unsigned long long i) {
    id l = G1C_As_LayoutAt(self, i);
    NSNumber *v = (G1C_PilesOn() && l) ? G1C_As_Calc(self)[@"scales"][l] : nil;
    return v ? v.doubleValue : G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGSize G1C_As_Fitted(id self, SEL _cmd) {
    if (G1C_PilesOn()) return [G1C_As_Calc(self)[@"fitted"] CGSizeValue];
    return G1B_SUPER(CGSize, gAsParent, self, _cmd, (struct objc_super *, SEL));
}
static long long G1C_As_IndexInPile(id self, SEL _cmd, id layout) {
    id ident = G1C_Resp(layout, @selector(continuousExposeIdentifier)) ? G1B_Send0(layout, @selector(continuousExposeIdentifier)) : nil;
    SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:");
    NSArray *ls = (ident && G1C_Resp(self, byId)) ? G1B_Send1(self, byId, ident) : nil;
    NSUInteger n = ls ? [ls indexOfObject:layout] : NSNotFound;
    return n == NSNotFound ? 0 : (long long)n;
}
static double G1C_As_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long i) {
    if (!G1C_PilesOn()) return G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, i);
    id s = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id cs = G1C_Resp(s, @selector(chamoisSettings)) ? G1B_Send0(s, @selector(chamoisSettings)) : nil;
    long long vis = (cs && [cs respondsToSelector:@selector(numberOfVisibleItemsPerGroup)]) ? G1B_SendLL0(cs, @selector(numberOfVisibleItemsPerGroup)) : 3;
    return G1C_As_IndexInPile(self, 0, layout) < vis ? 1.0 : 0.0;
}
static double G1C_As_DefaultCardScale(id self, SEL _cmd) {                      // 0x1c78132d4
    double h = G1C_As_CardHeight(self);
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    return b.size.height == 0 ? 1.0 : h / b.size.height;
}
static double G1C_As_SnapshotScale(id self, SEL _cmd, id layout) { return G1C_PilesOn() ? G1C_As_DefaultCardScale(self, 0) : G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, id), layout); }

// --- behaviour ---
static id G1C_As_Init(id self, SEL _cmd) {
    id me = G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL));
    if (!me) return nil;
    G1C_SetIvarBool(me, "_bp_handlesTap", YES);
    G1C_SetIvarBool(me, "_bp_handlesHeaderTap", YES);
    Class dc = NSClassFromString(@"SBDefaultImplementationsSwitcherModifier");
    if (dc && [me respondsToSelector:@selector(addChildModifier:atLevel:key:)]) {
        id d = [[dc alloc] init];
        if (d) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, @selector(addChildModifier:atLevel:key:), d, 1, nil);
    }
    return me;
}
static id G1C_As_Event(id self, SEL _cmd, id event) {
    G1C_SetIvarLL(self, "_bp_eventGen", G1C_IvarLL(self, "_bp_eventGen") + 1);
    return G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL, id), event);
}
static id G1C_As_Tap(id self, SEL _cmd, id event) {                              // 0x1c780f96c
    id r = G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event || !G1C_IvarBool(self, "_bp_handlesTap") || (G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled)))) return r;
    id l = G1B_Send0(event, @selector(appLayout));
    id p = l ? G1C_NewPerformActivate(l, NO) : nil;
    if (!p) return r;
    G1C_HandleEvent(event, @"App Switcher Continuous Expose");
    return G1B_AppendTo(p, r);
}
static id G1C_As_HeaderTap(id self, SEL _cmd, id event) {                        // 0x1c780fa84
    id r = G1B_HasSuper(gAsParent, _cmd) ? G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL, id), event) : nil;   // not in 16.0
    if (!G1C_ON() || !event || !G1C_IvarBool(self, "_bp_handlesHeaderTap") || (G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled)))) return r;
    id layout = G1B_Send0(event, @selector(appLayout));
    id item = (layout && G1C_Resp(layout, @selector(itemForLayoutRole:))) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), G1B_SendLL0(event, @selector(layoutRole))) : nil;
    SEL multi = NSSelectorFromString(@"displayItemSupportsMultipleWindowsIndicator:");
    if (!item || !G1C_Resp(self, multi)) return r;
    if (G1B_SendB1(self, multi, item)) {
        id req = G1C_NewBareRequest();
        if (req) {
            if ([req respondsToSelector:@selector(setSource:)]) G1B_SendVLL(req, @selector(setSource:), 3);
            if ([req respondsToSelector:@selector(setBundleIdentifierForAppExpose:)]) G1B_SendV1(req, @selector(setBundleIdentifierForAppExpose:), G1B_Send0(item, @selector(bundleIdentifier)));
            r = G1B_AppendTo(G1C_NewPerformFromRequest(req, NO), r);
        }
    } else {
        Class pc = NSClassFromString(@"SBPulseDisplayItemSwitcherModifier"), cc = NSClassFromString(@"SBChildModifierEventResponse");
        SEL ci = NSSelectorFromString(@"initWithModifier:level:");
        id pulse = (pc && [pc instancesRespondToSelector:@selector(initWithDisplayItem:)]) ? G1B_Send1([pc alloc], @selector(initWithDisplayItem:), item) : nil;
        id add = (pulse && cc && [cc instancesRespondToSelector:ci]) ? ((id (*)(id, SEL, id, long long))objc_msgSend)([cc alloc], ci, pulse, 3) : nil;
        if (add) r = G1B_AppendTo(add, r);
    }
    return r;
}
static id G1C_As_TapOutside(id self, SEL _cmd, id event) {                       // 0x1c780fc0c
    id r = G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event || (G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled)))) return r;
    Class rq = NSClassFromString(@"SBSwitcherTransitionRequest");
    SEL hs = NSSelectorFromString(@"requestForActivatingHomeScreen");
    id req = (rq && [rq respondsToSelector:hs]) ? G1B_Send0((id)rq, hs) : nil;
    return G1B_AppendTo(G1C_NewPerformFromRequest(req, NO), r);
}
static id G1C_As_Removal(id self, SEL _cmd, id event) {                          // 0x1c780fcf8
    id r = G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (!G1C_ON() || !event) return r;
    long long phase = G1B_SendLL0(event, @selector(phase));
    long long n = G1C_IvarLL(self, "_bp_ongoingRemovals");
    if (phase == 1) G1C_SetIvarLL(self, "_bp_ongoingRemovals", n + 1);
    else if (phase == 2) {
        n = MAX(0, n - 1);
        G1C_SetIvarLL(self, "_bp_ongoingRemovals", n);
        NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
        if (ls.count == 0 && n == 0) {                                            // last window removed: go home with auto-PIP disabled
            id req = G1C_NewBareRequest();
            Class al = NSClassFromString(@"SBAppLayout");
            id home = (al && [al respondsToSelector:@selector(homeScreenAppLayout)]) ? G1B_Send0((id)al, @selector(homeScreenAppLayout)) : nil;
            if (req && home) {
                G1B_SendV1(req, @selector(setAppLayout:), home);
                if ([req respondsToSelector:@selector(setAutoPIPDisabled:)]) G1C_SendVB(req, @selector(setAutoPIPDisabled:), YES);
                r = G1B_AppendTo(G1C_NewPerformFromRequest(req, NO), r);
            }
        }
    }
    return r;
}
static id G1C_As_Resign(id self, SEL _cmd) {
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
    return @{ @3: [NSSet setWithArray:ls ?: @[]] };
}
static BOOL G1C_As_GetTap(id self, SEL _cmd) { return G1C_IvarBool(self, "_bp_handlesTap"); }
static void G1C_As_SetTap(id self, SEL _cmd, BOOL v) { G1C_SetIvarBool(self, "_bp_handlesTap", v); }
static BOOL G1C_As_GetHdr(id self, SEL _cmd) { return G1C_IvarBool(self, "_bp_handlesHeaderTap"); }
static void G1C_As_SetHdr(id self, SEL _cmd, BOOL v) { G1C_SetIvarBool(self, "_bp_handlesHeaderTap", v); }
static id G1C_As_AdjustedIds(id self, SEL _cmd, id a, id b) { return a; }          // UNSURE: identity (the 579-instr strip variant orders the "forward" pile first)
static id G1C_As_AdjustedStrip(id self, SEL _cmd, id a) { return a; }
static BOOL G1C_As_ReturnNO(id self, SEL _cmd) { return NO; }
static BOOL G1C_As_ReturnYES(id self, SEL _cmd) { return YES; }
static BOOL G1C_As_NoGrab(id self, SEL _cmd, id l) { return NO; }

static BOOL G1C_BuildAppSwitcher(void) {
    gAsParent = NSClassFromString(@"SBAppSwitcherContinuousExposeSwitcherModifier");
    if (!gAsParent) return NO;
    const G1BIvar iv[] = {
        { "_bp_handlesTap", 1, 0, "B" }, { "_bp_handlesHeaderTap", 1, 0, "B" },
        { "_bp_ongoingRemovals", sizeof(long long), 3, "q" }, { "_bp_eventGen", sizeof(long long), 3, "q" },
    };
    const G1BMethod m[] = {
        { "init", (IMP)G1C_As_Init, "@16@0:8" },
        { "handleEvent:", (IMP)G1C_As_Event, "@24@0:8@16" },
        { "handleTapAppLayoutEvent:", (IMP)G1C_As_Tap, "@24@0:8@16" },
        { "handleTapAppLayoutHeaderEvent:", (IMP)G1C_As_HeaderTap, "@24@0:8@16" },
        { "handleTapOutsideToDismissEvent:", (IMP)G1C_As_TapOutside, "@24@0:8@16" },
        { "handleRemovalEvent:", (IMP)G1C_As_Removal, "@24@0:8@16" },
        { "appLayoutsToResignActive", (IMP)G1C_As_Resign, "@16@0:8" },
        { "handlesTapAppLayoutEvents", (IMP)G1C_As_GetTap, "B16@0:8" }, { "setHandlesTapAppLayoutEvents:", (IMP)G1C_As_SetTap, "v20@0:8B16" },
        { "handlesTapAppLayoutHeaderEvents", (IMP)G1C_As_GetHdr, "B16@0:8" }, { "setHandlesTapAppLayoutHeaderEvents:", (IMP)G1C_As_SetHdr, "v20@0:8B16" },
        { "adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:", (IMP)G1C_As_AdjustedIds, "@32@0:8@16@24" },
        { "adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:", (IMP)G1C_As_AdjustedStrip, "@24@0:8@16" },
        { "isResizeGrabberVisibleForAppLayout:", (IMP)G1C_As_NoGrab, "B24@0:8@16" },
        { "isItemContainerPointerInteractionEnabled", (IMP)G1C_As_ReturnYES, "B16@0:8" },
        { "isSwitcherWindowVisible", (IMP)G1C_As_ReturnYES, "B16@0:8" },
        { "isSwitcherWindowUserInteractionEnabled", (IMP)G1C_As_ReturnYES, "B16@0:8" },
        { "frameForIndex:", (IMP)G1C_As_FrameForIndex, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
        { "scaleForIndex:", (IMP)G1C_As_ScaleForIndex, "d24@0:8Q16" },
        { "_fittedContentSize", (IMP)G1C_As_Fitted, "{CGSize=dd}16@0:8" },
        { "_indexOfAppLayoutInItsPile:", (IMP)G1C_As_IndexInPile, "Q24@0:8@16" },
        { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_As_Opacity, "d40@0:8q16@24Q32" },
        { "_defaultCardScale", (IMP)G1C_As_DefaultCardScale, "d16@0:8" },
        { "snapshotScaleForAppLayout:", (IMP)G1C_As_SnapshotScale, "d24@0:8@16" },
    };
    gAsCls = G1B_MakeClass("BP162AppSwitcherContinuousExposeSwitcherModifier", gAsParent, iv, 4, m, sizeof m / sizeof m[0], NULL, NULL);
    return gAsCls != Nil;
}
static id G1C_NewAppSwitcherModifier(void) {
    Class c = gAsCls ?: gAsParent;
    return c ? [[c alloc] init] : nil;
}
static id G1C_NewFullScreenModifier(id appLayout) {
    Class c = NSClassFromString(@"SBFullScreenContinuousExposeSwitcherModifier");
    SEL s = NSSelectorFromString(@"initWithFullScreenAppLayout:");
    if (!c || !appLayout || ![c instancesRespondToSelector:s]) return nil;
    return G1B_Send1([c alloc], s, appLayout);
}

// ============================================================================================================
// 2 / 2b  SBContinuousExposeRootSwitcherModifier: factories, gesture roots, peek child, slide/cycle spawning, tongue, stage bookkeeping
//     DONE (floor factories UNSURE:state carry-over; see md 2.x). New Root ivars of 16.2 are associated objects (the class is
//     allocated by the 16.0 controller, so it cannot be subclassed).
// ============================================================================================================
typedef struct { long long state; long long direction; } G1CTongueAttrs;
static char kRootEffStage, kRootTongue, kRootInitialFloor;
static NSString *const kG1CPeekKey = @"SBContinuousExposePeekModifierKey";

static BOOL G1C_Kind(id o, NSString *n) { Class c = NSClassFromString(n); return c && o && [o isKindOfClass:c]; }
static NSString *G1C_StrProp(id o, SEL s) { id v = G1C_Resp(o, s) ? G1B_Send0(o, s) : nil; return [v isKindOfClass:[NSString class]] ? v : nil; }
static id G1C_RootCurrentLayout(id root) { return G1C_IvarObj(root, "_currentAppLayout"); }
static id G1C_HomeLayoutFor(id root) {
    Class al = NSClassFromString(@"SBAppLayout");
    id home = (al && [al respondsToSelector:@selector(homeScreenAppLayout)]) ? G1B_Send0((id)al, @selector(homeScreenAppLayout)) : nil;
    SEL mo = NSSelectorFromString(@"appLayoutByModifyingPreferredDisplayOrdinal:");
    if (home && [home respondsToSelector:mo] && G1C_Resp(root, @selector(displayOrdinal))) home = G1C_SendLL1(home, mo, G1B_SendLL0(root, @selector(displayOrdinal)));
    return home;
}
static NSArray *G1C_ArrayOf(id o) {
    if ([o isKindOfClass:[NSArray class]]) return o;
    if ([o respondsToSelector:@selector(array)]) return G1B_Send0(o, @selector(array));
    if ([o respondsToSelector:@selector(allObjects)]) return G1B_Send0(o, @selector(allObjects));
    return @[];
}
static NSArray *G1C_FilterIds(NSArray *src, NSArray *notIn, NSString *skip) {
    NSMutableArray *out = [NSMutableArray array];
    for (id i in src) if (![notIn containsObject:i] && !(skip && [i isEqual:skip])) [out addObject:i];
    return out;
}

%group G1C_Root
%hook SBContinuousExposeRootSwitcherModifier

// ---- floorModifierForTransitionEvent: (0x1c78180e8) -- reuse / create floors, with the 16.2 state carry-over ----
- (id)floorModifierForTransitionEvent:(id)event {
    if (!G1C_ON() || !event) return %orig;
    Class homeC = NSClassFromString(@"SBHomeScreenContinuousExposeSwitcherModifier"), expC = NSClassFromString(@"SBAppExposeContinuousExposeSwitcherModifier"),
          fsC = NSClassFromString(@"SBFullScreenContinuousExposeSwitcherModifier");
    if (!homeC || !expC || !fsC) return %orig;
    id floor = G1C_Resp(self, @selector(floorModifier)) ? G1B_Send0(self, @selector(floorModifier)) : nil;
    long long mode = G1B_SendLL0(event, @selector(toEnvironmentMode));
    id toAL = G1B_Send0(event, @selector(toAppLayout));
    NSString *exposeID = G1C_Resp(event, @selector(toAppExposeBundleID)) ? G1B_Send0(event, @selector(toAppExposeBundleID)) : nil;
    switch (mode) {
        case 1: {
            if (floor && [floor isKindOfClass:homeC]) return floor;
            id h = G1C_NewHomeModifier();
            return h ?: %orig;
        }
        case 2: {
            if (!exposeID) {
                id m = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
                if (m) return m;
                return %orig;
            }
            if (floor && [floor isKindOfClass:expC] && [G1C_StrProp(floor, @selector(bundleIdentifier)) isEqualToString:exposeID]) return floor;
            SEL ii = @selector(initWithBundleIdentifier:);
            return [expC instancesRespondToSelector:ii] ? G1B_Send1([expC alloc], ii, exposeID) : %orig;
        }
        case 3: {
            if (!exposeID) {
                NSString *amb = G1C_Resp(event, @selector(ambiguouslyLaunchedBundleIDIfAny)) ? G1B_Send0(event, @selector(ambiguouslyLaunchedBundleIDIfAny)) : nil;
                NSString *pile = (floor && G1C_Resp(floor, @selector(appPileBundleIDToBringForwardIfAny))) ? G1B_Send0(floor, @selector(appPileBundleIDToBringForwardIfAny)) : nil;
                if (floor && [floor isKindOfClass:fsC] && toAL && G1C_Resp(floor, @selector(fullScreenAppLayout)) && [G1B_Send0(floor, @selector(fullScreenAppLayout)) isEqual:toAL]
                    && (pile == amb || [pile isEqualToString:amb])) return floor;
                id fs = toAL ? G1C_NewFullScreenModifier(toAL) : nil;
                if (!fs) return %orig;
                if (floor && [floor isKindOfClass:fsC]) {                                                  // carry the highlight sets
                    id t = G1C_Resp(floor, @selector(highlightedByTouchAppLayouts)) ? G1B_Send0(floor, @selector(highlightedByTouchAppLayouts)) : nil;
                    id h = G1C_Resp(floor, @selector(highlightedByHoverAppLayouts)) ? G1B_Send0(floor, @selector(highlightedByHoverAppLayouts)) : nil;
                    if (t && [fs respondsToSelector:@selector(setHighlightedByTouchAppLayouts:)]) G1B_SendV1(fs, @selector(setHighlightedByTouchAppLayouts:), t);
                    if (h && [fs respondsToSelector:@selector(setHighlightedByHoverAppLayouts:)]) G1B_SendV1(fs, @selector(setHighlightedByHoverAppLayouts:), h);
                }
                if ([fs respondsToSelector:@selector(setAppPileBundleIDToBringForwardIfAny:)]) G1B_SendV1(fs, @selector(setAppPileBundleIDToBringForwardIfAny:), amb);
                if (floor && [fs respondsToSelector:@selector(setFullScreenAppDisplacementState:)] && G1C_Resp(floor, @selector(fullScreenAppDisplacementState)))
                    G1B_SendVLL(fs, @selector(setFullScreenAppDisplacementState:), G1B_SendLL0(floor, @selector(fullScreenAppDisplacementState)));
                return fs;
            }
            Class inl = gInlCls ?: gInlParent;
            if (floor && gInlParent && [floor isKindOfClass:gInlParent] && [G1C_StrProp(floor, @selector(appExposeBundleIdentifier)) isEqualToString:exposeID]) return floor;
            id n = (inl && toAL) ? G1C_NewInlineAppExpose(toAL, exposeID) : nil;
            return n ?: %orig;
        }
        default: return %orig;
    }
}

// ---- floorModifierForGestureEvent: (0x1c78183f0, new) ----
- (id)floorModifierForGestureEvent:(id)event {
    id floor = G1C_Resp(self, @selector(floorModifier)) ? G1B_Send0(self, @selector(floorModifier)) : nil;
    if (!G1C_ON() || !event || !G1C_Resp(event, @selector(isContinuousExposeWindowDragEvent)) || !G1B_SendB0(event, @selector(isContinuousExposeWindowDragEvent))) return floor;
    Class fsC = NSClassFromString(@"SBFullScreenContinuousExposeSwitcherModifier");
    long long phase = G1B_SendLL0(event, @selector(phase));
    id selected = G1B_Send0(event, @selector(selectedAppLayout));
    SEL pq = NSSelectorFromString(@"proposedAppLayoutForContinuousExposeWindowDrag");
    id proposed = G1C_Resp(self, pq) ? G1B_Send0(self, pq) : nil;
    BOOL has = proposed && selected && G1B_SendB1(proposed, @selector(containsAnyItemFromAppLayout:), selected);
    if (phase == 1) { G1B_SET(self, kRootInitialFloor, floor); return floor; }
    id initial = G1B_GET(self, kRootInitialFloor);
    if (phase == 3) G1B_SET(self, kRootInitialFloor, nil);
    if (has) {
        if (floor && fsC && [floor isKindOfClass:fsC]) return floor;
        id fs = G1C_NewFullScreenModifier(proposed);
        return fs ?: floor;
    }
    if (initial && ![initial isEqual:floor]) {                                 // dragged window left the stage again: restore the floor we started with
        if ([initial respondsToSelector:@selector(setState:)]) G1B_SendVLL(initial, @selector(setState:), 0);
        return initial;
    }
    return floor;
}

// ---- gestureModifierForGestureEvent: (0x1c7818d78) ----
- (id)gestureModifierForGestureEvent:(id)event {
    if (!G1C_ON() || !event || !G1C_Resp(event, @selector(gestureType))) return %orig;
    long long t = G1B_SendLL0(event, @selector(gestureType));
    id eff = nil;
    long long mode = G1C_Resp(self, @selector(_effectiveEnvironmentMode)) ? G1B_SendLL0(self, @selector(_effectiveEnvironmentMode)) : 3;
    switch (t) {
        case 3:  eff = G1C_NewGridSwipeUpRoot(mode, G1C_NewAppSwitcherModifier()); break;
        case 7:  eff = G1C_NewDndRoot(3, G1C_RootCurrentLayout(self)); break;
        case 9:  eff = G1C_NewWindowDragRoot(mode, G1C_RootCurrentLayout(self) ?: G1C_HomeLayoutFor(self)); break;
        default: break;
    }
    if (eff) {
        if (BP_LogEnabled()) BP_Log(@"GLITCH gesture modifier: type=%lld effMode=%lld -> %@", t, mode, G1C_DbgCls(eff));
        return eff;
    }
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"GLITCH gesture modifier: type=%lld effMode=%lld -> %@ (stock)", t, mode, G1C_DbgCls(r));
    if (t == 1 && r && [r respondsToSelector:@selector(setEnsuresSelectedAppLayoutUsesAnchorPointSpacePinning:)]) G1C_SendVB(r, @selector(setEnsuresSelectedAppLayoutUsesAnchorPointSpacePinning:), YES);
    return r;
}

// ---- handleGestureEvent: floor update during window drags (phase != 1) ----
- (id)handleGestureEvent:(id)event {
    id r = %orig;
    if (G1C_ON() && event && G1C_Resp(event, @selector(isContinuousExposeWindowDragEvent)) && G1B_SendB0(event, @selector(isContinuousExposeWindowDragEvent))
        && G1B_SendLL0(event, @selector(phase)) != 1 && [self respondsToSelector:@selector(_updateFloorModifierWithGestureEvent:)]) {
        G1B_SendV1(self, @selector(_updateFloorModifierWithGestureEvent:), event);       // void in 16.0
    }
    return r;
}

// ---- handleEvent: _effectiveAppLayoutOnStage bookkeeping (0x1c7819254) ----
- (id)handleEvent:(id)event {
    id r = %orig;
    if (!G1C_ON() || !event || !G1C_Resp(event, @selector(isTransitionEvent)) || !G1B_SendB0(event, @selector(isTransitionEvent))) return r;
    id to = G1B_Send0(event, @selector(toAppLayout)), from = G1B_Send0(event, @selector(fromAppLayout));
    BOOL animated = G1B_SendB0(event, @selector(isAnimated));
    long long phase = G1B_SendLL0(event, @selector(phase));
    if (to && from) { if (phase == 2 || !animated) G1B_SET(self, kRootEffStage, to); }
    else if (!to && from) { if (phase == 3 || !animated) G1B_SET(self, kRootEffStage, nil); }
    else if (to && !from) { if (phase == 1 || !animated) G1B_SET(self, kRootEffStage, to); }
    else if (phase == 1 || !animated) G1B_SET(self, kRootEffStage, nil);
    if (BP_LogEnabled()) BP_Log(@"GLITCH stage bookkeeping: phase=%lld animated=%d from=%@ to=%@ -> effective stage layout=%@", phase, animated, G1C_DbgLayout(from), G1C_DbgLayout(to), G1C_DbgLayout(G1B_GET(self, kRootEffStage)));
    return r;      // 16.2 also returns an Invalidate response here; the 16.0 controller already updates the identifiers inline (blocks 0x1c5fc50c4 / 0x1c5fc5d9c)
}

// ---- handleTransitionEvent: peek child (0x1c7819470) ----
- (id)handleTransitionEvent:(id)event {
    id r = %orig;
    if (!G1C_ON() || !event || !G1C_Resp(event, @selector(toPeekConfiguration))) return r;
    long long phase = G1B_SendLL0(event, @selector(phase));
    BOOL animated = G1B_SendB0(event, @selector(isAnimated));
    long long cfg = G1B_SendLL0(event, @selector(toPeekConfiguration));
    if (BP_LogEnabled()) {
        id fl = G1C_Resp(self, @selector(floorModifier)) ? G1B_Send0(self, @selector(floorModifier)) : nil;
        BP_Log(@"GLITCH transition event: phase=%lld animated=%d gesture=%d modes %lld->%lld from=%@ to=%@ peek %lld->%lld floor=%@ effMode=%lld stage=%@", phase, animated,
               G1C_Resp(event, @selector(isGestureInitiated)) && G1B_SendB0(event, @selector(isGestureInitiated)), G1B_SendLL0(event, @selector(fromEnvironmentMode)), G1B_SendLL0(event, @selector(toEnvironmentMode)),
               G1C_DbgLayout(G1B_Send0(event, @selector(fromAppLayout))), G1C_DbgLayout(G1B_Send0(event, @selector(toAppLayout))), G1B_SendLL0(event, @selector(fromPeekConfiguration)), cfg,
               G1C_DbgCls(fl), G1C_Resp(self, @selector(_effectiveEnvironmentMode)) ? G1B_SendLL0(self, @selector(_effectiveEnvironmentMode)) : -1, G1C_DbgLayout(G1B_GET(self, kRootEffStage)));
    }
    if ((phase == 2 || !animated) && G1C_PeekIsValid(cfg)) {
        SEL by = NSSelectorFromString(@"childModifierByKey:");
        id existing = G1C_Resp(self, by) ? G1B_Send1(self, by, kG1CPeekKey) : nil;
        id to = G1B_Send0(event, @selector(toAppLayout));
        id peek = (!existing && to) ? G1C_NewPeekModifier(to, cfg) : nil;
        if (BP_LogEnabled()) BP_Log(@"GLITCH peek child %@ for %@ cfg=%lld", peek ? @"created" : @"not created", G1C_DbgLayout(to), cfg);
        if (peek && [self respondsToSelector:@selector(addChildModifier:atLevel:key:)]) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(self, @selector(addChildModifier:atLevel:key:), peek, 2, kG1CPeekKey);
    }
    return r;
}

// ---- handleContinuousExposeIdentifiersChangedEvent: (0x1c78195b8) slide / cycle spawning with the two-list API ----
- (id)handleContinuousExposeIdentifiersChangedEvent:(id)event {
    Class rootC = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
    Class cycC = NSClassFromString(@"SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier");
    if (!G1C_ON() || !event || !rootC || !gSlideCls) return %orig;
    id r = G1B_SUPER(id, class_getSuperclass(rootC), self, _cmd, (struct objc_super *, SEL, id), event);
    long long mode = G1C_Resp(self, @selector(_effectiveEnvironmentMode)) ? G1B_SendLL0(self, @selector(_effectiveEnvironmentMode)) : 0;
    // the identifiers-changed event names them transitioningFrom/ToAppLayout (it has no fromAppLayout/toAppLayout: the crash seen on 0.6.0 at launch)
    if (!G1C_Resp(event, @selector(transitioningFromAppLayout)) || !G1C_Resp(event, @selector(transitioningToAppLayout))) return r;
    id from = G1B_Send0(event, @selector(transitioningFromAppLayout)), to = G1B_Send0(event, @selector(transitioningToAppLayout));
    BOOL animated = G1C_Resp(event, @selector(isAnimated)) ? G1B_SendB0(event, @selector(isAnimated)) : YES;
    if (BP_LogEnabled()) {
        id fl = G1C_Resp(self, @selector(floorModifier)) ? G1B_Send0(self, @selector(floorModifier)) : nil;
        BP_Log(@"GLITCH ids-changed event: effMode=%lld floor=%@ animated=%d from=%@ to=%@ prevSw=%@ prevStrip=%@ curStrip=%@ -> %@", mode, G1C_DbgCls(fl), animated, G1C_DbgLayout(from), G1C_DbgLayout(to),
               G1C_DbgIds(G1C_Resp(event, @selector(previousContinuousExposeIdentifiersInSwitcher)) ? G1B_Send0(event, @selector(previousContinuousExposeIdentifiersInSwitcher)) : nil),
               G1C_DbgIds(G1C_Resp(event, @selector(previousContinuousExposeIdentifiersInStrip)) ? G1B_Send0(event, @selector(previousContinuousExposeIdentifiersInStrip)) : nil),
               G1C_DbgIds(G1C_Resp(self, @selector(continuousExposeIdentifiersInStrip)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInStrip)) : nil),
               (!animated || mode != 3 || !from || !to) ? @"no slide/cycle (needs animated, effective mode 3, from and to)" : @"slide/cycle spawning allowed");
    }
    if (!animated || mode != 3 || !from || !to) return r;
    NSArray *prevSw = G1C_ArrayOf(G1C_Resp(event, @selector(previousContinuousExposeIdentifiersInSwitcher)) ? G1B_Send0(event, @selector(previousContinuousExposeIdentifiersInSwitcher)) : nil);
    NSArray *prevStrip = G1C_ArrayOf(G1C_Resp(event, @selector(previousContinuousExposeIdentifiersInStrip)) ? G1B_Send0(event, @selector(previousContinuousExposeIdentifiersInStrip)) : nil);
    NSArray *curStrip = G1C_ArrayOf(G1C_Resp(self, @selector(continuousExposeIdentifiersInStrip)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInStrip)) : nil);
    NSString *toId = G1C_Resp(to, @selector(continuousExposeIdentifier)) ? G1B_Send0(to, @selector(continuousExposeIdentifier)) : nil;
    NSString *fromId = G1C_Resp(from, @selector(continuousExposeIdentifier)) ? G1B_Send0(from, @selector(continuousExposeIdentifier)) : nil;
    SEL add = @selector(addChildModifier:atLevel:key:);
    for (NSString *ident in G1C_FilterIds(prevStrip, curStrip, toId)) {                       // left the strip: slide out (direction 1)
        id m = G1C_NewSlideModifier(ident, prevSw, prevStrip, 1);
        if (m && [self respondsToSelector:add]) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(self, add, m, 5, nil);
    }
    for (NSString *ident in G1C_FilterIds(curStrip, prevStrip, fromId)) {                     // entered the strip: slide in (direction 0)
        id m = G1C_NewSlideModifier(ident, prevSw, prevStrip, 0);
        if (m && [self respondsToSelector:add]) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(self, add, m, 5, nil);
    }
    if (cycC && toId && fromId && [fromId isEqual:toId] && !G1B_SendB1(from, @selector(containsAnyItemFromAppLayout:), to)) {
        SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:");
        NSArray *group = G1C_Resp(self, byId) ? G1C_ArrayOf(G1B_Send1(self, byId, toId)) : @[];
        SEL ci = NSSelectorFromString(@"initWithAppLayout:behindAppLayout:generationCount:");
        if ([group containsObject:from] && group.lastObject && [cycC instancesRespondToSelector:ci]) {
            unsigned long long gen = G1C_Resp(self, @selector(continuousExposeIdentifiersGenerationCount)) ? (unsigned long long)G1B_SendLL0(self, @selector(continuousExposeIdentifiersGenerationCount)) : 0;
            id cyc = ((id (*)(id, SEL, id, id, unsigned long long))objc_msgSend)([cycC alloc], ci, from, group.lastObject, gen);
            if (cyc && [self respondsToSelector:add]) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(self, add, cyc, 5, nil);
        }
    }
    return r;
}

// ---- transitionModifierForMainTransitionEvent: (0x1c781859c): post-process %orig for the cases that changed ----
- (id)transitionModifierForMainTransitionEvent:(id)event {
    id orig = %orig;
    if (!G1C_ON() || !event) return orig;
    if (BP_LogEnabled()) BP_Log(@"GLITCH main transition: from mode %lld to mode %lld animated=%d gesture=%d from=%@ to=%@ stock modifier=%@", G1B_SendLL0(event, @selector(fromEnvironmentMode)), G1B_SendLL0(event, @selector(toEnvironmentMode)),
                                G1B_SendB0(event, @selector(isAnimated)), G1C_Resp(event, @selector(isGestureInitiated)) && G1B_SendB0(event, @selector(isGestureInitiated)),
                                G1C_DbgLayout(G1B_Send0(event, @selector(fromAppLayout))), G1C_DbgLayout(G1B_Send0(event, @selector(toAppLayout))), G1C_DbgCls(orig));
    if (G1C_Resp(event, @selector(isiPadOSWindowingModeChangeEvent)) && G1B_SendB0(event, @selector(isiPadOSWindowingModeChangeEvent))) return nil;    // the iPadOS platform modifier handles it
    if (!G1B_SendB0(event, @selector(isAnimated)) || (G1C_Resp(event, @selector(isGestureInitiated)) && G1B_SendB0(event, @selector(isGestureInitiated)))) return orig;
    long long f = G1B_SendLL0(event, @selector(fromEnvironmentMode)), t = G1B_SendLL0(event, @selector(toEnvironmentMode));
    if (!orig && !(f == 2 && t == 1)) return orig;      // 16.0 returns nil only for animated non-gesture 2->1 (the SwitcherDismissFix case): fill just that one
    id tid = G1C_Resp(event, @selector(transitionID)) ? G1B_Send0(event, @selector(transitionID)) : nil;
    id n = nil;
    if (f == 2 && t == 3) n = G1C_NewSwitcherToApp(tid, 0);
    else if (f == 3 && t == 2) n = G1C_NewSwitcherToApp(tid, 1);
    else if ((f == 2 && t == 1) || (f == 1 && t == 2)) {
        id mm = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
        SEL ci = NSSelectorFromString(@"initWithTransitionID:direction:continuousExposeModifier:");
        if (mm && gCEToHomeCls && [gCEToHomeCls instancesRespondToSelector:ci]) n = ((id (*)(id, SEL, id, long long, id))objc_msgSend)([gCEToHomeCls alloc], ci, tid, f == 1 ? 1 : 0, [mm copy]);
    } else if (f == 3 && t == 3 && G1C_Kind(orig, @"SBContinuousExposeAppToAppModifier")) n = G1C_NewAppToApp(event);
    if (BP_LogEnabled() && n) BP_Log(@"GLITCH main transition replaced: %@ -> %@", G1C_DbgCls(orig), G1C_DbgCls(n));
    return n ?: orig;
}

// ---- 16.2-only answers ----
%new
- (id)appLayoutOnContinuousExposeStage { return G1B_GET(self, kRootEffStage); }
%new
- (id)handleContinuousExposeStripEdgeProtectTongueEvent:(id)event {
    SEL s = NSSelectorFromString(@"handleContinuousExposeStripEdgeProtectTongueEvent:");
    id r = nil;
    Class rootC = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
    if (class_getInstanceMethod(class_getSuperclass(rootC), s)) r = G1B_SUPER(id, class_getSuperclass(rootC), self, s, (struct objc_super *, SEL, id), event);
    BOOL presented = G1C_Resp(event, @selector(isTonguePresented)) && G1B_SendB0(event, @selector(isTonguePresented));
    G1B_SET(self, kRootTongue, @(presented));
    return G1B_AppendTo(G1B_NewUpdateLayoutResponse(4, 2), r);
}
- (BOOL)shouldUseWallpaperGradientTreatment { return YES; }
%new
- (BOOL)shouldScaleContentToFillBoundsAtIndex:(unsigned long long)i { return NO; }
%new
- (BOOL)shouldUseNonuniformSnapshotScalingForLayoutRole:(long long)role inAppLayout:(id)layout { return NO; }
%new
- (G1CTongueAttrs)continuousExposeStripTongueAttributes {
    G1CTongueAttrs a;
    a.state = [(NSNumber *)G1B_GET(self, kRootTongue) boolValue] ? 2 : 1;
    BOOL rtl = G1C_Resp(self, @selector(isRTLEnabled)) && G1B_SendB0(self, @selector(isRTLEnabled));
    a.direction = rtl ? 2 : 1;
    return a;
}
%end
%end

// ============================================================================================================
// 5.x  Producers of the two 16.2 responses whose consumers are in group1b (1.7 grabber, 1.10 orientation)   DONE
// ============================================================================================================
// Grabber (response type 39): produced by -[SBFullScreenContinuousExposeSwitcherModifier handlePointerCrossedDisplayBoundaryEvent:] 0x1c75c5144:
//   response = [super handle...]; if (event.edge == _continuousExposeStripEdge /* RTL ? 2 : 0 */ && BSFloatIsZero(continuousExposeStripProgress)) and
//   event.direction is 1 (initial presentation YES) or 0 (NO): append SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse initForInitialPresentation:.
// Event type 38 reaches the handler through the 1b _handleEvent: hook (0.1). The 16.0 FullScreen class has no such method, so it is added here (%new);
// the Strip package, when installed, defines its own and this one is then never reached (class_addMethod would fail on an existing selector).
// Orientation (response type 38): produced by -[SBItemResizeGestureSwitcherModifier _responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:] 0x1c76bf0bc:
//   item = [_currentAppLayout itemForLayoutRole:_selectedLayoutRole]; if ([[self layoutRestrictionInfoForItem:item] layoutRestrictions] & 0xa) == 2
//   (the item may only be resized in one orientation family) -> desired content orientation = size.width > size.height ? 3 : 1, added with -addChildResponse:.
%group G1C_Producers
%hook SBFullScreenContinuousExposeSwitcherModifier
%new
- (id)handlePointerCrossedDisplayBoundaryEvent:(id)event {
    Class fsC = NSClassFromString(@"SBSwitcherModifier");
    SEL me = NSSelectorFromString(@"handlePointerCrossedDisplayBoundaryEvent:");
    id response = (fsC && class_getInstanceMethod(fsC, me)) ? G1B_SUPER(id, fsC, self, me, (struct objc_super *, SEL, id), event) : nil;
    if (!G1C_ON() || !event || !gGrabberRespCls) return response;
    BOOL rtl = [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft;
    unsigned int stripEdge = rtl ? 2u : 0u;
    unsigned int edge = G1C_Resp(event, @selector(edge)) ? (unsigned int)G1B_SendLL0(event, @selector(edge)) : 0xffu;
    SEL ps = NSSelectorFromString(@"continuousExposeStripProgress");
    double progress = G1C_Resp(self, ps) ? G1C_SendD0(self, ps) : 1.0;
    if (edge != stripEdge || fabs(progress) > 1e-9) return response;
    long long dir = G1C_Resp(event, @selector(direction)) ? G1B_SendLL0(event, @selector(direction)) : -1;
    if (dir != 0 && dir != 1) return response;
    id grab = ((id (*)(id, SEL, BOOL))objc_msgSend)([gGrabberRespCls alloc], @selector(initForInitialPresentation:), dir == 1);
    return grab ? G1B_AppendTo(grab, response) : response;
}
%end
%hook SBItemResizeGestureSwitcherModifier
- (id)_responseForSceneSizeUpdateToSize:(CGSize)size center:(CGPoint)center sceneUpdatesOnly:(BOOL)only {
    id r = %orig;
    if (!G1C_ON() || !r || !gOrientRespCls) return r;
    id layout = G1C_IvarObj(self, "_currentAppLayout");
    id item = (layout && G1C_Resp(layout, @selector(itemForLayoutRole:))) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), G1C_IvarLL(self, "_selectedLayoutRole")) : nil;
    SEL li = NSSelectorFromString(@"layoutRestrictionInfoForItem:");
    id info = (item && [self respondsToSelector:li]) ? G1B_Send1(self, li, item) : nil;
    SEL lr = NSSelectorFromString(@"layoutRestrictions");
    if (!info || ![info respondsToSelector:lr]) return r;
    if ((G1B_SendLL0(info, lr) & 0xa) != 2) return r;
    long long orient = size.width > size.height ? 3 : 1;
    id resp = ((id (*)(id, SEL, id, long long))objc_msgSend)([gOrientRespCls alloc], @selector(initWithDisplayItem:desiredContentOrientation:), item, orient);
    if (resp && [r respondsToSelector:@selector(addChildResponse:)]) G1B_SendV1(r, @selector(addChildResponse:), resp);
    return r;
}
%end
%end
// ============================================================================================================
// 6.8  switcher -> home (ToHome / HomeToGrid): the first group's cards linger on screen at the left edge (specs/AUDIT-HOMEFLASH-0.6.8.md)
// ============================================================================================================
// The 16.0 SBHomeToGridSwitcherModifier (identical in 16.2) hides the Stage Manager cards when the transition is "effectively home" (direction 0 and
// updating layout) ONLY by sliding the whole grid left by [multi distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreen...:index] (16.0: row-chain over
// visibleAppLayouts, 16.2: pile based, see audit) and by opacity 0 for layouts missing from the copy's visibleAppLayouts. In our build the first group (grid
// index 0/1, rightmost column) ends at x = 0..card width, still drawn, until the ToHome modifier is removed (video: ~0.9 s).
// Invariant enforced here: in the effectively-home end state of a switcher -> home transition of the Stage Manager switcher no card is visible
// (16.2: all cards are off screen there). Opacity 0 is animated together with the slide, so cards that do slide off are unaffected.
// Off switch: Backport162.off.g1c_homeflash. Logging (opt-in debug): per-answer lines "GLITCH h2g ..." for grid indices 0..3, one line per change.
static IMP gH2GOrigOpacity;
static NSString *gH2GLastSig[4][3];
static BOOL G1C_H2G_HideActive(id self) {
    if (!G1C_ON() || !BP_OnName("g1c_homeflash")) return NO;
    if (!G1C_Resp(self, @selector(direction)) || G1B_SendLL0(self, @selector(direction)) != 0) return NO;      // 0 = switcher -> home
    if (!G1B_SendB0(self, @selector(isEffectivelyHome))) return NO;
    id multi = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
    return G1C_Kind(multi, @"SBAppSwitcherContinuousExposeSwitcherModifier");
}
static double G1C_H2G_Distance(id self, unsigned long long idx) {
    SEL ds = NSSelectorFromString(@"distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch:");
    id multi = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
    if (!G1C_Resp(multi, ds) || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)]) return -1.0;
    __block double d = -1.0;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), multi, ^{
        d = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(multi, ds, idx);
    });
    return d;
}
static void G1C_H2G_Log(id self, long long role, id layout, unsigned long long idx, double stock, double out) {
    if (idx > 3 || !BP_LogEnabled()) return;
    long long dir = G1B_SendLL0(self, @selector(direction));
    BOOL eff = G1B_SendB0(self, @selector(isEffectivelyHome)), prep = G1B_SendB0(self, @selector(isPreparingLayout)), upd = G1B_SendB0(self, @selector(isUpdatingLayout));
    SEL fs = @selector(frameForIndex:), ss = @selector(scaleForIndex:), vs = @selector(visibleAppLayouts);
    CGRect f = G1C_Resp(self, fs) ? ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, fs, idx) : CGRectZero;
    double sc = G1C_Resp(self, ss) ? ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, ss, idx) : -1.0;
    id vis = G1C_Resp(self, vs) ? G1B_Send0(self, vs) : nil;
    NSUInteger visN = [vis respondsToSelector:@selector(count)] ? (NSUInteger)((unsigned long long (*)(id, SEL))objc_msgSend)(vis, @selector(count)) : 0;
    BOOL inVis = layout && [vis respondsToSelector:@selector(containsObject:)] && ((BOOL (*)(id, SEL, id))objc_msgSend)(vis, @selector(containsObject:), layout);
    double dist = G1C_H2G_Distance(self, idx);
    NSString *sig = [NSString stringWithFormat:@"%lld %d%d%d %.2f>%.2f %.0f,%.0f %.0fx%.0f s%.3f v%d/%lu d%.1f", dir, eff, prep, upd, stock, out, f.origin.x, f.origin.y, f.size.width, f.size.height, sc, inVis, (unsigned long)visN, dist];
    NSUInteger ri = role >= 0 && role < 3 ? (NSUInteger)role : 2;
    @synchronized(@"BP162.h2g") {
        if ([gH2GLastSig[idx][ri] isEqualToString:sig]) return;
        gH2GLastSig[idx][ri] = sig;
    }
    BP_Log(@"GLITCH h2g idx=%llu role=%lld layout=%@ dir/eff/prep/upd/opacity(stock>out)/frame/scale/inVisible(count)/distance: %@", idx, role, G1C_DbgLayout(layout), sig);
}
static double G1C_H2G_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long idx) {
    double o = gH2GOrigOpacity ? ((double (*)(id, SEL, long long, id, unsigned long long))gH2GOrigOpacity)(self, _cmd, role, layout, idx) : 1.0;
    double out = (o > 0.0 && G1C_H2G_HideActive(self)) ? 0.0 : o;
    G1C_H2G_Log(self, role, layout, idx, o, out);
    return out;
}
static void G1C_InstallHomeFlashGuard(void) {
    Class c = NSClassFromString(@"SBHomeToGridSwitcherModifier");
    SEL s = @selector(opacityForLayoutRole:inAppLayout:atIndex:);
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) return;
    const char *types = method_getTypeEncoding(m);
    IMP old = class_replaceMethod(c, s, (IMP)G1C_H2G_Opacity, types);
    gH2GOrigOpacity = old ?: method_getImplementation(m);        // old is NULL when the method was inherited: the pre-replace implementation is then the inherited one
}
// ============================================================================================================
// setup
// ============================================================================================================
void G1C_Setup(void) {
    G1C_InstallEventPredicates();
    G1C_BuildGridGesture();
    G1C_BuildCEToHome();
    G1C_InstallHomeFlashGuard();
    G1C_BuildGridRoot();
    G1C_BuildTransactions();
    %init(G1C_Txn);
    G1C_BuildIdsEvent();
    G1C_InstallEvent16Compat();
    G1C_UpgradeOverrideIds();
    G1C_BuildSlide();
    G1C_BuildAppToApp();
    G1C_BuildSwitcherToApp();
    G1C_BuildPeekFamily();
    G1C_BuildDnd();
    G1C_BuildWindowDragContent();
    G1C_BuildAppSwitcher();
    G1C_BuildFloors();
    G1C_BuildWindowDragFamily();
    %init(G1C_WdEvent);
    %init(G1C_Root);
    %init(G1C_Producers);
    %init(G1C_OverflowRoot);
    G1C_InstallRevealStrips();
    %init(G1C_Cycle);
    %init(G1C_VCIds);        // MUST be after the group 2 %init(G2B): it replaces the same method
}
#pragma clang diagnostic pop
