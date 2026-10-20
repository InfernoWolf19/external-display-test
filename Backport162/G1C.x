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
@interface SBSwitcherModifier : NSObject @end
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
static inline double  G1C_SendD0Q(id o, SEL s, unsigned long long i) { return ((double (*)(id, SEL, unsigned long long))objc_msgSend)(o, s, i); }
static inline unsigned long long G1C_SendULL0(id o, SEL s)           { return ((unsigned long long (*)(id, SEL))objc_msgSend)(o, s); }
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
    return CGSizeZero;       // the 1-argument sizeInBounds: of 16.0 has different semantics (no default size / edge padding): never used
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
            BP_Log(@"GLITCH ToHome effectively home dir=%lld idx=%llu: anchor forced to (0.5,0.5)", G1C_CEH_Dir(self), i);   // the detached switcher copy is not asked: with piles on that would query containerViewBounds without a delegate (crash)
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
static void G1C_GR_Guard(id self, id event);
static char kGridRootMulti;
static id G1C_GridRoot_Init(id self, SEL _cmd, long long mode, id multi) {
    if (!multi) return nil;                                                               // 16.2 asserts (SBGridSwipeUpGestureRootSwitcherModifier.m:0x1a)
    id me = G1B_SUPER(id, gGridRootSuper, self, @selector(initWithStartingEnvironmentMode:), (struct objc_super *, SEL, long long), mode);
    if (me) G1B_SET(me, kGridRootMulti, multi);                                           
    return me;
}
static long long G1C_GridRoot_Type(id self, SEL _cmd) { return 3; }
static id G1C_GridRoot_Gesture(id self, SEL _cmd, id event) {
    G1C_GR_Guard(self, event);
    return G1B_SUPER(id, gGridRootSuper, self, _cmd, (struct objc_super *, SEL, id), event);
}
// `_newMultitaskingModifier` is a NEW-family selector (ARC ignores the leading underscore): the callers (stock ARC code) own the result (+1). A plain C IMP returns +0
// (autoreleased), which made the callers over-release the copy. ns_returns_retained makes ARC hand the copy's +1 to the caller.
static __attribute__((ns_returns_retained)) id G1C_GridRoot_NewMulti(id self, SEL _cmd) { id m = G1B_GET(self, kGridRootMulti); return m ? [m copy] : nil; }
// Caller side of the NEW-family `_newMultitaskingModifier` (+1): the cast type carries ns_returns_retained so that ARC consumes the owned reference.
static id G1C_NewMultiOf(id root) {
    SEL s = NSSelectorFromString(@"_newMultitaskingModifier");
    if (!root || ![root respondsToSelector:s]) return nil;
    return ((__attribute__((ns_returns_retained)) id (*)(id, SEL))objc_msgSend)(root, s);
}
static id G1C_GridRoot_GestureChild(id self, SEL _cmd, id event, id activeTransition) {
    id gid = (event && [event respondsToSelector:@selector(gestureID)]) ? G1B_Send0(event, @selector(gestureID)) : nil;
    Class g = gGridGestCls ?: gGridGestBase;
    if (!g || !gid) return nil;
    SEL withDelay = @selector(initWithGestureID:delayCompletionUntilTransitionBegins:);
    if ([g instancesRespondToSelector:withDelay]) return ((id (*)(id, SEL, id, BOOL))objc_msgSend)([g alloc], withDelay, gid, YES);
    return ((id (*)(id, SEL, id))objc_msgSend)([g alloc], @selector(initWithGestureID:), gid);
}
// The 'Gesture' child of a gesture root: 16.2 property gestureModifier (== childModifierByKey:@"Gesture", 0x1c74d3df4); 16.0 calls it _gestureModifier.
static id G1C_GR_GM(id self) {
    if (G1C_Resp(self, @selector(gestureModifier))) return G1B_Send0(self, @selector(gestureModifier));
    if (G1C_Resp(self, @selector(_gestureModifier))) return G1B_Send0(self, @selector(_gestureModifier));
    return G1C_Resp(self, @selector(childModifierByKey:)) ? G1B_Send1(self, @selector(childModifierByKey:), @"Gesture") : nil;
}
// 16.2 SBGestureRootSwitcherModifier -handleGestureEvent: (0x1c74d3b60, the same shape in 16.0) adds the new gesture child with addChildModifier:atLevel:1 key:@"Gesture" and
// SBChainableModifier throws NSInternalInconsistencyException when that key is still taken. In 16.2 the previous 'Gesture' child is always finished before a new gesture
// begins: the gesture's last phase produces a perform-transition response, the transition's phase 1 reaches the root's handleTransitionEvent: (gestureModifier setState:1) and
// the base class removes finished children. A gesture whose touch ended on another display never produced that transition here (crash log: pointer drag whose touch up came
// from the external scene, no end event, no transition; the next drag crashed the root), so the child was still active when the next gesture began.
// Last-line guard (16.2 itself has none): finish and remove the stale child exactly like the base class' removal pass would, and say so in the debug log.
static void G1C_GR_Guard(id self, id event) {
    if (!G1C_ON() || !event || !G1C_Resp(event, @selector(phase)) || G1B_SendLL0(event, @selector(phase)) != 1) return;
    if (!G1C_Resp(event, @selector(gestureType)) || !G1C_Resp(self, @selector(gestureType)) || G1B_SendLL0(event, @selector(gestureType)) != G1B_SendLL0(self, @selector(gestureType))) return;
    id stale = G1C_GR_GM(self);
    if (!stale) return;
    if (BP_LogEnabled()) BP_Log(@"GUARD gesture root %@: a new gesture began while the previous 'Gesture' child %@ was still active (its gesture never produced a transition) -> finishing and removing it", G1C_DbgCls(self), G1C_DbgCls(stale));
    if (G1C_Resp(stale, @selector(setState:))) G1B_SendVLL(stale, @selector(setState:), 1);
    if (G1C_Resp(self, @selector(removeChildModifier:))) G1B_SendV1(self, @selector(removeChildModifier:), stale);
}
static id G1C_GridRoot_TransitionChild(id self, SEL _cmd, id event, id activeGesture) {
    if (!event || ![event respondsToSelector:@selector(fromEnvironmentMode)]) return nil;
    if (G1B_SendLL0(event, @selector(fromEnvironmentMode)) != 2 || G1B_SendLL0(event, @selector(toEnvironmentMode)) != 1) return nil;
    Class ceC = NSClassFromString(@"SBAppSwitcherContinuousExposeSwitcherModifier");
    id multi = G1C_NewMultiOf(self);
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
        { "handleGestureEvent:", (IMP)G1C_GridRoot_Gesture, "@24@0:8@16" },
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
    if (BP_LogEnabled()) {                                              // one-time dump of the live modifier tree (levels, keys, classes): shows where the id queries are answered
        static dispatch_once_t once;
        dispatch_once(&once, ^{ if (G1C_Resp(root, @selector(stackDescription))) BP_Log(@"g1c: modifier stack at the first ids update:\n%@", G1B_Send0(root, @selector(stackDescription))); });
    }
    NSArray *strip = G1C_AskRootIds(root, sel_registerName("adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:"), prevStrip, nil, NO);
    NSArray *sw = strip ? G1C_AskRootIds(root, sel_registerName("adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:"), prevSw, strip, YES) : nil;
    if (!strip || !sw) {                                               // last-line guard: the root's query chain always ends in G2's BP_G2_Adjusted*Ids now
        if (BP_LogEnabled()) BP_Log(@"GUARD identifiers update: the root modifier did not answer the adjusted identifier queries -> stock update");
        %orig;
        return;
    }
    st.idsInStrip = strip;
    st.idsInSwitcher = sw;
    st.idsGeneration += 1;
    // keep the 16.0 state coherent: single ordered set, group cache cleared, 16.0 generation counter bumped
    Ivar ivSet = class_getInstanceVariable(object_getClass(self), "_continuousExposeIdentifiers");
    if (ivSet) BP_SetObjIvar(self, ivSet, [NSOrderedSet orderedSetWithArray:sw ?: @[]]);
    Ivar ivMap = class_getInstanceVariable(object_getClass(self), "_appLayoutsForContinuousExposeIdentifiers");
    if (ivMap) BP_SetObjIvar(self, ivMap, nil);
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
        if (ivFront) BP_SetObjIvar(self, ivFront, to);
        doComplete = [appLayout isEqual:behind] || [to isEqual:behind];
    } else {
        if (ivFront) BP_SetObjIvar(self, ivFront, nil);
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
            if (iv) BP_SetObjIvar(self, iv, nil);
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
    if ([reason isKindOfClass:[NSString class]] && [reason isEqualToString:kG1CRevealTimeout]) {
        if (BP_LogEnabled() && G1B_SendLL0(self, @selector(state)) != 1) BP_Log(@"GUARD strip reveal gesture: no transition began within 2 s of the gesture end -> completing the gesture modifier (16.2 has no such timeout)");
        G1B_SendVLL(self, @selector(setState:), 1);
    }
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
static id G1C_DndRoot_Gesture(id self, SEL _cmd, id event) {
    G1C_GR_Guard(self, event);
    return G1B_SUPER(id, gDndRootSuper, self, _cmd, (struct objc_super *, SEL, id), event);
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
static double G1C_Dnd_HomeDim(id self, SEL _cmd) {                                       // 0x1c7639120
    if (!G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled))) {
        id t = G1B_GET(self, kDndTrans);                                                 // _transitionModifier: past phase 1 the home screen is fully dimmed
        if (t && (unsigned long long)G1B_SendLL0(t, NSSelectorFromString(@"transitionPhase")) > 1) return 1.0;
    }
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
        { "handleGestureEvent:", (IMP)G1C_DndRoot_Gesture, "@24@0:8@16" },
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
    if (iv) BP_SetObjIvar(o, iv, v);
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
    Class dc = gWddCls;
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
    BOOL evCanceled = G1C_Resp(event, @selector(isCanceled)) && G1B_SendB0(event, @selector(isCanceled));       // 16.2 0x1c760960c: canceled = event.isCanceled || proposedDestination == 0
    G1C_SetIvarBool(self, "_gestureWasCanceled", evCanceled || destProposed == 0);
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
    }
    {   // every phase (16.2 0x1c76098b4..0x1c7609928): anchor point follows where the proposed layouts put the dragged item
        BOOL anyProp = G1C_Wd_AnyProposedHas(self);
        BOOL hasSel = G1C_LayoutHas(G1C_Wd_Proposed(self), sel);
        BOOL other = G1C_IvarBool(self, "_bp_dragBeganInOtherSwitcher"), strip = G1C_IvarBool(self, "_bp_dragBeganInAnyStrip"), stage = G1C_IvarBool(self, "_bp_dragBeganOnAnyStage");
        if ((other && hasSel) || (strip && !anyProp)) G1C_SetIvarPoint(self, "_anchorPoint", CGPointMake(0.5, 0.5));
        else if (stage && !anyProp) G1C_SetIvarPoint(self, "_anchorPoint", CGPointMake(0.4, 0.4));       // 0x3fd999999999999a
        else G1C_SetIvarPoint(self, "_anchorPoint", G1C_IvarPoint(self, "_initialAnchorPoint"));
    }
    if (phase == 3) {
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
            }
            if (target && G1C_LayoutHas(target, sel)) {                                // 16.2 0x1c7609ba0..0x1c7609df4
                // write every item's current on-screen centre (overlapping model) back into the layout as a normalized centre
                id calc = G1C_Resp(self, @selector(displayItemLayoutAttributesCalculator)) ? G1B_Send0(self, @selector(displayItemLayoutAttributesCalculator)) : nil;
                SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:");
                id model = nil;
                CGRect cb = G1C_Resp(self, @selector(containerViewBounds)) ? G1C_SendRect0(self, @selector(containerViewBounds)) : CGRectZero;
                if (calc && [calc respondsToSelector:om]) {
                    long long orient = G1B_SendLL0(self, @selector(switcherInterfaceOrientation));
                    double fdh = G1B_Dbl0(self, @selector(floatingDockHeight)), scale = G1B_Dbl0(self, @selector(screenScale));
                    BOOL sh = G1B_SendB0(self, @selector(prefersStripHidden)), dh = G1B_SendB0(self, @selector(prefersDockHidden));
                    model = ((id (*)(id, SEL, id, long long, id, double, double, CGRect, BOOL, BOOL))objc_msgSend)(calc, om, target, orient, attrs, fdh, scale, cb, sh, dh);
                }
                if (model && [model respondsToSelector:@selector(centerForItem:)] && G1C_Resp(target, @selector(allItems))) {
                    for (id item in [G1B_Send0(target, @selector(allItems)) copy]) {
                        CGPoint c = ((CGPoint (*)(id, SEL, id))objc_msgSend)(model, @selector(centerForItem:), item);
                        id a0 = G1C_Resp(target, @selector(layoutAttributesForItem:)) ? G1B_Send1(target, @selector(layoutAttributesForItem:), item) : nil;
                        id a1 = G1C_DM_AttrsByModifyingCenter(a0, c, cb);
                        id nt = (a1 && G1C_Resp(target, @selector(appLayoutByModifyingLayoutAttributes:forItem:))) ? G1C_Send2(target, @selector(appLayoutByModifyingLayoutAttributes:forItem:), a1, item) : nil;
                        if (nt) target = nt;
                    }
                }
                if (!toHome && G1C_Resp(self, @selector(appLayoutByBringingItemToFront:inAppLayout:))) {
                    id fronted = G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), sel, target);
                    if (fronted) target = fronted;
                }
            }
            id finalTarget = target;
            if (!finalTarget) {                                                          // 16.2 0x1c7609e04: [SBAppLayout homeScreenAppLayout], no ordinal rewrite
                Class al = NSClassFromString(@"SBAppLayout");
                finalTarget = (al && [al respondsToSelector:@selector(homeScreenAppLayout)]) ? G1B_Send0((id)al, @selector(homeScreenAppLayout)) : nil;
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
// 0x1c760b400  isSwitcherWindowUserInteractionEnabled = [self isSwitcherWindowVisible]  (16.2 tail call)
static BOOL G1C_Wd_WindowInteraction(id self, SEL _cmd) { return G1B_SendB0(self, @selector(isSwitcherWindowVisible)); }
// 0x1c760adb0  topMostLayoutElements: the layout holding the dragged item moves to the top
static id G1C_Wd_TopMost(id self, SEL _cmd) {
    id r = G1B_SUPER(id, gWdGrand, self, _cmd, (struct objc_super *, SEL));
    id l = G1B_Send1(self, @selector(_appLayoutContainingDisplayItem:), G1C_Wd_Sel(self));
    if (!l) return r;
    return ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(r, NSSelectorFromString(@"sb_arrayByInsertingOrMovingObject:toIndex:"), l, 0);
}
// 0x1c760b404  _appLayoutContainingDisplayItem: = first of -appLayouts containing the item (the 16.0 body logged; 16.2 does not)
static id G1C_Wd_LayoutForItem(id self, SEL _cmd, id item) {
    for (id l in (NSArray *)G1B_Send0(self, @selector(appLayouts))) if (G1C_LayoutHas(l, item)) return l;
    return nil;
}

// ---- WindowDragDestination: faithful port of 16.2 (20C65) -----------------------------------------------------------------------------------------
// BP162ContinuousExposeWindowDragDestinationSwitcherModifier subclasses the 16.0 class and replaces the five methods 16.2 changed; none of the 16.0
// bodies runs (handleGestureEvent: starts at SBSwitcherModifier, as the 16.2 -[super handleGestureEvent:] does).
//   handleGestureEvent:                    16.2 0x1c74f3330 (160 0x1c6070880)   _widthThresholdToHideStrips           0x1c74f3d8c
//   _frameForSelectedDisplayItem           16.2 0x1c74f3dd8                     _appLayoutByAddingItem:toAppLayout:size:center:  0x1c74f406c
//   proposedAppLayoutForContinuousExposeWindowDrag 0x1c74f3d7c                  _anyProposedAppLayoutContainsSelectedDisplayItem 0x1c74f46e0
// 16.2 ivars the 16.0 class lacks: _initialSelectedDisplayItemLayoutAttributes +0x90, _dragBeganInOtherSwitcher +0x98, _lastAppLayoutForStripCalculation +0xb0
// (the two objects live in associated objects: runtime-added ivars are unretained). _translation / _draggingFromStrips / _hasForegroundedSelectedDisplayItem
// of 16.0 are not touched any more. The cross-display queries (draggingAppLayouts... / proposedAppLayouts...) are answered by SBMainSwitcherControllerCoordinator in
// 16.2; that class does not exist in 16.0 (G2 stubs them), so a single display answers with its own layouts (the one documented non-portable part).
static Class gWddGrand;
static char kWddLast, kWddInitAttrs;
static BOOL G1C_Wdd_GT(double a, double b) { return a > b && fabs(a - b) >= 0.0001; }                                                // BSFloatGreaterThanFloat
static BOOL G1C_Wdd_RoleValid(long long r) { return (unsigned long long)(r - 1) < 10 && ((1u << (r & 31)) & 0xfffffc19u) == 0; }   // _SBLayoutRoleIsValidForSplitView 0x1c7894a30
static id G1C_Wdd_OverlapModel(id self, id layout, id attrs, CGRect cb) {
    id calc = G1B_Send0(self, @selector(displayItemLayoutAttributesCalculator));
    SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:");
    if (!calc || ![calc respondsToSelector:om]) { if (BP_LogEnabled()) BP_Log(@"GUARD WindowDragDestination: calculator lacks the overlapping-model query"); return nil; }
    return ((id (*)(id, SEL, id, long long, id, double, double, CGRect, BOOL, BOOL))objc_msgSend)(calc, om, layout, G1B_SendLL0(self, @selector(switcherInterfaceOrientation)), attrs,
        G1B_Dbl0(self, @selector(floatingDockHeight)), G1B_Dbl0(self, @selector(screenScale)), cb, G1B_SendB0(self, @selector(prefersStripHidden)), G1B_SendB0(self, @selector(prefersDockHidden)));
}
static id G1C_Wdd_ByDragging(id self, id item, id layout, id attrs, CGRect cb) {
    id calc = G1B_Send0(self, @selector(displayItemLayoutAttributesCalculator));
    SEL ds = NSSelectorFromString(@"appLayoutByDraggingItem:inAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:");
    if (!calc || ![calc respondsToSelector:ds]) { if (BP_LogEnabled()) BP_Log(@"GUARD WindowDragDestination: calculator lacks appLayoutByDraggingItem:..."); return layout; }
    return ((id (*)(id, SEL, id, id, long long, id, double, double, id, CGRect, BOOL, BOOL))objc_msgSend)(calc, ds, item, layout, G1B_SendLL0(self, @selector(switcherInterfaceOrientation)), attrs,
        G1B_Dbl0(self, @selector(floatingDockHeight)), G1B_Dbl0(self, @selector(screenScale)), G1C_IvarObj(self, "_initialOverlappingModel"), cb,
        G1B_SendB0(self, @selector(prefersStripHidden)), G1B_SendB0(self, @selector(prefersDockHidden)));
}
static G1CAttributedSize G1C_Wdd_AttrSize(id a) {                                                  // -[SBDisplayItemLayoutAttributes attributedSize] (zeros for nil, as the 16.2 code)
    G1CAttributedSize z; memset(&z, 0, sizeof z);
    SEL s = NSSelectorFromString(@"attributedSize");
    return (a && [a respondsToSelector:s]) ? ((G1CAttributedSize (*)(id, SEL))objc_msgSend)(a, s) : z;
}
static id G1C_Wdd_FirstDragging(id self) {                                                         // bs_firstObjectPassingTest: [l containsItem:_selectedDisplayItem]
    id sel = G1C_IvarObj(self, "_selectedDisplayItem");
    for (id l in G1C_WdDragging(self, G1C_IvarObj(self, "_initialAppLayout"))) if (G1C_LayoutHas(l, sel)) return l;
    return nil;
}

// 0x1c74f2fe8  init: 16.0 additionally set _draggingFromStrips from the delegate (ivar gone in 16.2); 16.2 seeds _lastAppLayoutForStripCalculation with the initial layout
extern id G1C_storeWeak(void *location, id obj) __asm__("_objc_storeWeak");        // ARC runtime entry (not declared by the public headers)
static id G1C_Wdd_Init(id self, SEL _cmd, id item, id initial, id delegate) {
    id me = G1B_SUPER(id, gWddGrand, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    if (!item || !initial || !delegate) return nil;                      // 16.2 NSAssert (SBContinuousExposeWindowDragDestinationSwitcherModifier.m lines 0x2c..0x2e)
    G1C_SetIvarObj(me, "_selectedDisplayItem", item);
    G1C_SetIvarObj(me, "_initialAppLayout", initial);
    Ivar dv = class_getInstanceVariable(object_getClass(me), "_destinationDelegate");
    if (dv) G1C_storeWeak((uint8_t *)(__bridge void *)me + ivar_getOffset(dv), delegate);
    G1C_SetIvarLL(me, "_proposedDestination", 0);
    G1C_SetIvarObj(me, "_proposedAppLayout", initial);
    G1B_SET(me, kWddLast, initial);
    return me;
}
// 0x1c74f46e0  [[self proposedAppLayoutsForContinuousExposeWindowDrag] bs_containsObjectPassingTest:^(l){ [l containsItem:_selectedDisplayItem] }]
static BOOL G1C_Wdd_AnyProposed(id self, SEL _cmd) {
    id sel = G1C_IvarObj(self, "_selectedDisplayItem");
    for (id l in G1C_WdProposedAll(self, self)) if (G1C_LayoutHas(l, sel)) return YES;
    return NO;
}
// 0x1c74f3d7c
static id G1C_Wdd_ProposedForDrag(id self, SEL _cmd) { return G1C_IvarObj(self, "_proposedAppLayout"); }
// 0x1c74f3d8c  [[self overlappingModelForAppLayout:_proposedAppLayout] widthThresholdToHideStrip]
static double G1C_Wdd_WidthThreshold(id self, SEL _cmd) {
    return G1C_DM_WidthThresholdToHideStrip(G1B_Send1(self, NSSelectorFromString(@"overlappingModelForAppLayout:"), G1C_IvarObj(self, "_proposedAppLayout")));
}
// 0x1c74f3dd8
static CGRect G1C_Wdd_Frame(id self, SEL _cmd) {
    id sel = G1C_IvarObj(self, "_selectedDisplayItem"), prop = G1C_IvarObj(self, "_proposedAppLayout");
    id layout = G1C_LayoutHas(prop, sel) ? prop : G1B_Send1(self, @selector(appLayoutContainingAppLayout:), G1B_Send1(self, @selector(_appLayoutContainingDisplayItem:), sel));
    BOOL any = G1B_SendB0(self, @selector(_anyProposedAppLayoutContainsSelectedDisplayItem));
    CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
    id attrs = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    CGSize size;
    if (G1C_IvarBool(self, "_dragBeganInOtherSwitcher") && any && !G1C_LayoutHas(prop, sel)) {             // dragged in from another switcher: its own size
        size = G1C_DM_SizeInBounds(G1B_GET(self, kWddInitAttrs), cb, G1C_DM_DefaultWindowSize(attrs), G1C_DM_ScreenEdgePadding(attrs));
    } else {
        id calc = G1B_Send0(self, @selector(displayItemLayoutAttributesCalculator));
        SEL fs = NSSelectorFromString(@"frameForLayoutRole:inAppLayout:containerBounds:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:isChamoisWindowingUIEnabled:prefersStripHidden:prefersDockHidden:");
        CGRect f = CGRectZero;
        if (calc && [calc respondsToSelector:fs])
            f = ((CGRect (*)(id, SEL, long long, id, CGRect, long long, id, double, double, BOOL, BOOL, BOOL))objc_msgSend)(calc, fs, G1C_SendLLId(layout, @selector(layoutRoleForItem:), sel), layout, cb,
                G1B_SendLL0(self, @selector(switcherInterfaceOrientation)), attrs, G1B_Dbl0(self, @selector(floatingDockHeight)), G1B_Dbl0(self, @selector(screenScale)), YES,
                G1B_SendB0(self, @selector(prefersStripHidden)), G1B_SendB0(self, @selector(prefersDockHidden)));
        else if (BP_LogEnabled()) BP_Log(@"GUARD WindowDragDestination._frameForSelectedDisplayItem: calculator lacks frameForLayoutRole:...");
        size = f.size;
    }
    id delegate = G1B_Send0(self, @selector(destinationDelegate));
    CGPoint c = (delegate && G1C_Resp(delegate, @selector(preferredCenterForSelectedItemInDestinationModifier:))) ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(delegate, @selector(preferredCenterForSelectedItemInDestinationModifier:), self) : CGPointZero;
    return CGRectMake(c.x - size.width * 0.5, c.y - size.height * 0.5, size.width, size.height);     // _UIRectCenteredAboutPoint(SBRectWithSize(size), center)
}
// 0x1c74f406c
static id G1C_Wdd_AddItem(id self, SEL _cmd, id item, id layout, CGSize size, CGPoint center) {
    id selItem = G1C_IvarObj(self, "_selectedDisplayItem");
    if (G1C_LayoutHas(layout, item)) return layout;
    if (!layout) return G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), item, G1C_IvarObj(self, "_initialAppLayout"));
    NSMutableArray *items = [(NSArray *)G1B_Send0(layout, @selector(allItems)) mutableCopy];
    [items addObject:item];
    id attrs = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
    Class dla = NSClassFromString(@"SBDisplayItemLayoutAttributes");
    CGPoint norm = ((CGPoint (*)(id, SEL, CGPoint, CGRect))objc_msgSend)((id)dla, @selector(normalizedPointForPoint:inBounds:), center, cb);
    id first = G1C_Wdd_FirstDragging(self);
    G1CAttributedSize as;
    if (!first || G1B_SendLL0(first, @selector(preferredDisplayOrdinal)) == G1B_SendLL0(self, @selector(displayOrdinal)))
        as = G1C_DM_InferAttributedSize(size, cb, G1C_DM_DefaultWindowSize(attrs), G1C_DM_ScreenEdgePadding(attrs));       // _SBDisplayItemAttributedSizeInfer 0x1c75cedfc
    else
        as = G1C_Wdd_AttrSize(G1B_Send1(first, @selector(layoutAttributesForItem:), selItem));                              // dragged in from another switcher: that window's size
    SEL ia = NSSelectorFromString(@"initWithContentOrientation:lastInteractionTime:sizingPolicy:attributedSize:normalizedCenter:");
    id na = ((id (*)(id, SEL, long long, long long, long long, G1CAttributedSize, CGPoint))objc_msgSend)([dla alloc], ia, 0, 0, 0, as, norm);
    NSMutableDictionary *map = [(NSDictionary *)G1B_Send0(layout, @selector(itemsToLayoutAttributesMap)) mutableCopy];
    if (na) [map addEntriesFromDictionary:@{ item : na }];
    Class alc = NSClassFromString(@"SBAppLayout");
    SEL ini = NSSelectorFromString(@"initWithItems:centerItem:floatingItem:configuration:itemsToLayoutAttributes:centerConfiguration:environment:hidden:preferredDisplayOrdinal:");
    id nl = G1B_INIT(id, id, id, long long, id, long long, long long, BOOL, long long)([alc alloc], ini, items,      // SBAppLayout interns: init consumes the alloc (G1BKit.h)
        G1C_SendLL1(layout, @selector(itemForLayoutRole:), 4), G1C_SendLL1(layout, @selector(itemForLayoutRole:), 3), 3, map,
        G1B_SendLL0(layout, @selector(centerConfiguration)), G1B_SendLL0(layout, @selector(environment)), G1B_SendB0(layout, @selector(isHidden)), G1B_SendLL0(layout, @selector(preferredDisplayOrdinal)));
    id fronted = G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), item, nl);
    return G1C_Wdd_ByDragging(self, item, fronted, G1B_Send0(self, @selector(chamoisLayoutAttributes)), G1C_SendRect0(self, @selector(containerViewBounds)));
}
// 0x1c74f3330
static id G1C_Wdd_Gesture(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gWddGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    CGPoint loc = G1C_SendPoint0(event, @selector(locationInContainerView)), vel = G1C_SendPoint0(event, @selector(velocityInContainerView));
    G1C_SetIvarPoint(self, "_location", loc);
    G1C_SetIvarPoint(self, "_velocity", vel);
    id attrs = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
    double W = cb.size.width;
    long long phase = G1B_SendLL0(event, @selector(phase));
    id sel = G1C_IvarObj(self, "_selectedDisplayItem"), initial = G1C_IvarObj(self, "_initialAppLayout");
    if (phase == 1) {
        G1C_SetIvarPoint(self, "_initialLocation", loc);
        id model = G1C_Wdd_OverlapModel(self, G1C_IvarObj(self, "_proposedAppLayout"), attrs, cb);
        double th = G1C_DM_WidthThresholdToHideStrip(model);
        double bbW = (model && G1C_Resp(model, @selector(boundingBox))) ? G1C_SendRect0(model, @selector(boundingBox)).size.width : 0.0;
        double sw = G1B_Dbl0(attrs, @selector(stripWidth)), cz;
        if (G1C_LayoutHas(initial, sel)) cz = sw + G1B_Dbl0(attrs, @selector(screenEdgePadding));
        else {
            double d = MIN(sw, (W - bbW) * 0.5);
            if (G1C_Wdd_GT(G1C_SendD0(self, @selector(continuousExposeStripProgress)), 0.0)) d = MAX(d, sw);
            cz = G1C_Wdd_GT(th, 0.0) ? MAX(d, (W - th) * 0.5) : d;
        }
        G1C_SetIvarD(self, "_stripsWidthForCancelZone", cz);
        id inLayout = G1B_Send1(self, @selector(_appLayoutContainingDisplayItem:), sel);
        G1B_SET(self, kWddInitAttrs, G1B_Send1(inLayout, @selector(layoutAttributesForItem:), sel));
        id first = G1C_Wdd_FirstDragging(self);
        G1C_SetIvarBool(self, "_dragBeganInOtherSwitcher", G1B_SendLL0(first, @selector(preferredDisplayOrdinal)) != G1B_SendLL0(self, @selector(displayOrdinal)));
        return r;
    }
    CGRect fr = G1C_SendRect0(self, @selector(_frameForSelectedDisplayItem));
    CGPoint il = G1C_IvarPoint(self, "_initialLocation");
    BOOL outside;                                                           // w23: the finger is in the stage part of the container (not over the strips' cancel zone)
    if (!CGRectContainsPoint(cb, loc)) outside = NO;
    else if (!CGRectContainsPoint(cb, il)) outside = YES;
    else {
        BOOL inItem = G1C_LayoutHas(initial, sel);
        if ([(NSArray *)G1B_Send0(initial, @selector(allItems)) count] == 1 && inItem) outside = YES;
        else {
            BOOL rtl = G1B_SendB0(self, @selector(isRTLEnabled));
            double cz = G1C_IvarD(self, "_stripsWidthForCancelZone");
            outside = (inItem || (rtl ? il.x >= W * 0.5 : il.x < W * 0.5)) && (rtl ? loc.x < W - cz : loc.x > cz);
        }
    }
    if (phase == 3 && (fabs(vel.x) > 1000.0 || fabs(vel.y) > 1000.0)) { fr.origin.x += vel.x * 0.15; fr.origin.y += vel.y * 0.15; }     // 0x1c7a90e18 / 0x1c7a90d70
    id prop = G1C_IvarObj(self, "_proposedAppLayout");
    BOOL has = G1C_LayoutHas(prop, sel);
    long long dest;
    if (outside) {
        if (has) {                                                                                     // 0x1c74f39d4: bring to front, keep the dragged centre
            id p = G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), sel, prop);
            CGPoint c = CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr));
            Class dla = NSClassFromString(@"SBDisplayItemLayoutAttributes");
            CGPoint norm = ((CGPoint (*)(id, SEL, CGPoint, CGRect))objc_msgSend)((id)dla, @selector(normalizedPointForPoint:inBounds:), c, cb);
            id na = ((id (*)(id, SEL, CGPoint))objc_msgSend)(G1B_Send1(p, @selector(layoutAttributesForItem:), sel), NSSelectorFromString(@"attributesByModifyingNormalizedCenter:"), norm);
            p = G1C_Send2(p, @selector(appLayoutByModifyingLayoutAttributes:forItem:), na, sel);
            p = G1C_Wdd_ByDragging(self, sel, p, G1B_Send0(self, @selector(chamoisLayoutAttributes)), cb);
            G1C_SetIvarObj(self, "_proposedAppLayout", p);
            G1C_SetIvarLL(self, "_proposedDestination", 1);
            return r;
        }
        id cs = G1B_Send0(G1B_Send0(self, @selector(switcherSettings)), @selector(chamoisSettings));       // 0x1c74f3874: a window coming in from the strips / elsewhere
        unsigned long long mx = (unsigned long long)G1B_SendLL0(cs, @selector(maximumNumberOfAppsOnStage));
        NSUInteger cnt = 0;                                                                                    // bs_filter: items of the initial layout in a split-view-valid role (block 0x1c74f3d10)
        for (id it in (NSArray *)G1B_Send0(initial, @selector(allItems))) if (G1C_Wdd_RoleValid(G1C_SendLLId(initial, @selector(layoutRoleForItem:), it))) cnt++;
        if (cnt >= mx && G1B_SendB0(cs, NSSelectorFromString(@"rejectDropsWhenStageIsFull"))) return r;
        G1C_SetIvarObj(self, "_proposedAppLayout", ((id (*)(id, SEL, id, id, CGSize, CGPoint))objc_msgSend)(self, @selector(_appLayoutByAddingItem:toAppLayout:size:center:), sel, prop, fr.size, CGPointMake(CGRectGetMidX(fr), CGRectGetMidY(fr))));
        dest = 2;
    } else {
        if (!has) return r;
        if (!G1C_LayoutHas(initial, sel)) { G1C_SetIvarObj(self, "_proposedAppLayout", initial); dest = 0; }       // 0x1c74f3bfc: back to where it came from
        else {                                                                                                 // 0x1c74f3944: drop on the strips: leaves the stage
            BOOL (^notSel)(id) = ^BOOL(id item) { return ![item isEqual:sel]; };                              // block 0x1c74f3d4c
            G1C_SetIvarObj(self, "_proposedAppLayout", G1B_Send1(prop, @selector(appLayoutWithItemsPassingTest:), notSel));
            dest = 3;
        }
    }
    G1C_SetIvarLL(self, "_proposedDestination", dest);
    id np = G1C_IvarObj(self, "_proposedAppLayout");
    Class rc = NSClassFromString(@"SBSwitcherTransitionRequest"), pc = NSClassFromString(@"SBPerformTransitionSwitcherEventResponse");
    id req = G1B_Send1((id)rc, @selector(requestForActivatingAppLayout:), np);
    ((void (*)(id, SEL, long long))objc_msgSend)(req, @selector(setUnlockedEnvironmentMode:), np ? 3 : 1);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(req, @selector(setSceneUpdatesOnly:), YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(req, @selector(setFenceSceneUpdate:), NO);
    r = G1B_AppendTo(((id (*)(id, SEL, id, BOOL))objc_msgSend)([pc alloc], @selector(initWithTransitionRequest:gestureInitiated:), req, YES), r);
    id last = G1B_GET(self, kWddLast);
    if (G1B_SendB1(last, @selector(containsAllItemsFromAppLayout:), np)) return r;
    G1B_SET(self, kWddLast, np);
    SEL ii = @selector(initWithTransitioningFromAppLayout:transitioningToAppLayout:animated:);
    if (gInvalidateRespCls && [gInvalidateRespCls instancesRespondToSelector:ii])
        r = G1B_AppendTo(((id (*)(id, SEL, id, id, BOOL))objc_msgSend)([gInvalidateRespCls alloc], ii, nil, nil, YES), r);          // (nil, nil, animated) as 16.2
    return r;
}

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
    G1C_GR_Guard(self, event);
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
        if (home && [home respondsToSelector:mo] && G1C_Resp(self, @selector(displayOrdinal))) home = G1C_SendLL1(home, mo, G1B_SendLL0(self, @selector(displayOrdinal)));     // 16.2 0x1c74614dc: `displayOrdinal` is a CONTEXT query of the modifier (x20 = self), not of the event
        to = home;
    }
    G1C_SetIvarObj(self, "_initialAppLayout", to);
    long long phase = G1C_Resp(event, @selector(phase)) ? G1B_SendLL0(event, @selector(phase)) : 0;
    if (phase == 1) { id gm = G1C_GR_GM(self); if (gm && G1C_Resp(gm, @selector(setState:))) G1B_SendVLL(gm, @selector(setState:), 1); }
    if (phase == 3 && G1C_Resp(self, @selector(setState:))) G1B_SendVLL(self, @selector(setState:), 1);
    return r;
}
static id G1C_Wdr_Anim(id self, SEL _cmd, id element) {
    id base = G1B_SUPER(id, gWdrGrand, self, _cmd, (struct objc_super *, SEL, id), element);
    id gm = G1C_GR_GM(self);
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
    {   // destination (faithful 16.2 port: see the block above G1C_Wdd_Gesture)
        gWddGrand = class_getSuperclass(gWddParent);
        const G1BIvar iv[] = { { "_dragBeganInOtherSwitcher", 1, 0, "B" } };
        const G1BMethod m[] = {
            { "initWithSelectedDisplayItem:initialAppLayout:delegate:", (IMP)G1C_Wdd_Init, "@40@0:8@16@24@32" },
            { "handleGestureEvent:", (IMP)G1C_Wdd_Gesture, "@24@0:8@16" },
            { "_widthThresholdToHideStrips", (IMP)G1C_Wdd_WidthThreshold, "d16@0:8" },
            { "_frameForSelectedDisplayItem", (IMP)G1C_Wdd_Frame, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8" },
            { "_appLayoutByAddingItem:toAppLayout:size:center:", (IMP)G1C_Wdd_AddItem, "@64@0:8@16@24{CGSize=dd}32{CGPoint=dd}48" },
            { "proposedAppLayoutForContinuousExposeWindowDrag", (IMP)G1C_Wdd_ProposedForDrag, "@16@0:8" },
            { "_anyProposedAppLayoutContainsSelectedDisplayItem", (IMP)G1C_Wdd_AnyProposed, "B16@0:8" },
        };
        gWddCls = G1B_MakeClass("BP162ContinuousExposeWindowDragDestinationSwitcherModifier", gWddParent, iv, 1, m, sizeof m / sizeof m[0], NULL, NULL);
        if (!gWddCls) return NO;
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
            { "isSwitcherWindowUserInteractionEnabled", (IMP)G1C_Wd_WindowInteraction, "B16@0:8" },
            { "topMostLayoutElements", (IMP)G1C_Wd_TopMost, "@16@0:8" },
            { "_appLayoutContainingDisplayItem:", (IMP)G1C_Wd_LayoutForItem, "@24@0:8@16" },
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
static Class gInlParent, gInlCls, gInlGrand;
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
    id fronted = G1C_Send2(self, @selector(appLayoutByBringingItemToFront:inAppLayout:), item, G1B_Send1(self, @selector(appLayoutContainingAppLayout:), layout));
    G1B_SendV1(req, @selector(setAppLayout:), fronted);
    G1B_SendV1(req, @selector(setActivatingDisplayItem:), item);
    return req;
}
static id G1C_Inl_Tap(id self, SEL _cmd, id event) {                      // 0x1c7686a58 (160 0x1c61f8000: the same request building without the super call)
    id r = G1B_SUPER(id, gInlGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1B_SendB0(event, @selector(isHandled))) return r;
    id layout = G1B_Send0(event, @selector(appLayout));
    id req;
    if ([layout isEqual:G1C_IvarObj(self, "_activeAppLayout")]) req = G1B_Send1((id)NSClassFromString(@"SBSwitcherTransitionRequest"), NSSelectorFromString(@"requestForTapAppLayoutEvent:"), event);
    else req = G1C_Inl_ActivationRequest(self, layout, G1C_SendLL1(layout, @selector(itemForLayoutRole:), G1B_SendLL0(event, @selector(layoutRole))));
    r = G1B_AppendTo(G1C_NewPerformFromRequest(req, NO), r);
    G1C_HandleEvent(event, @"I");
    return r;
}
static id G1C_Inl_HeaderTap(id self, SEL _cmd, id event) {                // 0x1c7686bf8 (new in 16.2)
    id r = G1B_SUPER(id, gInlGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1B_SendB0(event, @selector(isHandled))) return r;
    id layout = G1B_Send0(event, @selector(appLayout));
    id item = G1C_SendLL1(layout, @selector(itemForLayoutRole:), G1B_SendLL0(event, @selector(layoutRole)));
    id resp = nil;
    if (!G1B_SendB1(self, NSSelectorFromString(@"displayItemSupportsMultipleWindowsIndicator:"), item)) {          // single window: pulse the header
        Class pc = NSClassFromString(@"SBPulseDisplayItemSwitcherModifier"), cc = NSClassFromString(@"SBAddModifierSwitcherEventResponse");
        id pulse = G1B_Send1([pc alloc], @selector(initWithDisplayItem:), item);
        resp = ((id (*)(id, SEL, id, long long))objc_msgSend)([cc alloc], NSSelectorFromString(@"initWithModifier:level:"), pulse, 3);
    } else {
        Class rq = NSClassFromString(@"SBSwitcherTransitionRequest");
        NSString *bid = G1B_Send0(item, @selector(bundleIdentifier));
        id req;
        if ([bid isEqualToString:G1C_IvarObj(self, "_appExposeBundleIdentifier")]) {                         // the App Expose app's own window
            if ([layout isEqual:G1C_IvarObj(self, "_activeAppLayout")]) req = G1B_Send1((id)rq, NSSelectorFromString(@"requestForTapAppLayoutHeaderEvent:"), event);
            else req = G1C_Inl_ActivationRequest(self, layout, item);
        } else {                                                                                             // another app's header: App Expose of that app
            req = [[rq alloc] init];
            G1B_SendVLL(req, @selector(setSource:), 3);
            G1B_SendV1(req, @selector(setBundleIdentifierForAppExpose:), bid);
        }
        resp = G1C_NewPerformFromRequest(req, NO);
    }
    r = G1B_AppendTo(resp, r);
    G1C_HandleEvent(event, @"I");
    return r;
}
static id G1C_Inl_ReopenResponse(id self) {                                 // _responseToUpdateReopenClosedWindowsButtonPresenceIfNeeded (0x1c7688f84)
    BOOL could = [(NSNumber *)G1B_GET(self, kInlHidden) longLongValue] != 0;
    long long n = G1C_SendLLId(self, NSSelectorFromString(@"numberOfHiddenAppLayoutsForBundleIdentifier:"), G1C_IvarObj(self, "_appExposeBundleIdentifier"));
    G1B_SET(self, kInlHidden, @(n));
    if (n == 0 || could) return nil;
    G1B_SET(self, kInlShowing, @NO);
    double delay = G1B_Dbl0(G1B_Send0(G1B_Send0(self, @selector(switcherSettings)), @selector(animationSettings)), NSSelectorFromString(@"reopenButtonFadeInDelay"));
    __weak id wself = self;
    BOOL (^valid)(void) = ^BOOL{ id s = wself; return G1B_Send0(s, @selector(parentModifier)) != nil; };
    Class tc = NSClassFromString(@"SBTimerEventSwitcherEventResponse");
    SEL ti = @selector(initWithDelay:validator:reason:);
    if (!tc || ![tc instancesRespondToSelector:ti]) return nil;
    return ((id (*)(id, SEL, double, id, id))objc_msgSend)([tc alloc], ti, delay, valid, @"SBInlineAppExposeContinuousExposeSwitcherModifierTimerEventReason");
}
static id G1C_Inl_Insertion(id self, SEL _cmd, id event) {                 // 0x1c7686824
    id r = G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1C_ON() && event && G1B_SendLL0(event, @selector(phase)) == 2) r = G1B_AppendTo(G1C_Inl_ReopenResponse(self), r);
    return r;
}
static id G1C_Inl_Transition(id self, SEL _cmd, id event) {                // 0x1c76868e0 (160 0x1c61f81fc: super + the invalidate only)
    id r = G1B_SUPER(id, gInlGrand, self, _cmd, (struct objc_super *, SEL, id), event);
    G1C_SetIvarObj(self, "_activeAppLayout", G1B_Send0(event, @selector(toAppLayout)));
    long long phase = G1B_SendLL0(event, @selector(phase));
    if (phase == 2 || !G1B_SendB0(event, @selector(isAnimated))) {
        Class c = NSClassFromString(@"SBInvalidateAdjustedAppLayoutsSwitcherEventResponse");
        r = G1B_AppendTo([[c alloc] init], r);
    }
    if (phase == 2) {
        NSString *bid = G1B_Send0(event, @selector(fromAppExposeBundleID)) ?: G1B_Send0(event, @selector(toAppExposeBundleID));
        if (bid) {
            r = G1B_AppendTo(G1C_Inl_ReopenResponse(self), r);
            Class ir = NSClassFromString(@"SBInvalidateReopenButtonTextSwitcherEventResponse");
            r = G1B_AppendTo([[ir alloc] init], r);
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
static BOOL G1C_Inl_RTL(void) { return [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft; }
static double G1C_Inl_RS(double v, double s) { return s > 0 ? (s == 1.0 ? round(v) : round(v * s) / s) : v; }                                  // _UIRectRoundToScale component
static id G1C_Inl_Model(id self, id layout) { return G1B_Send1(self, NSSelectorFromString(@"overlappingModelForAppLayout:"), layout); }       // 16.2 query (the 16.0 private _overlappingModelForAppLayout: is gone)
static BOOL G1C_Inl_ModelBool(id model, NSString *sel, id item) { SEL s = NSSelectorFromString(sel); return G1B_SendB1(model, s, item); }
// 0x1c7688f6c  _canShowReopenClosedWindowsButton = (_numberOfHiddenAppLayouts != 0)
static BOOL G1C_Inl_CanShowSel(id self, SEL _cmd) { return G1C_Inl_CanShow(self); }
// 0x1c76883a4  reopenClosedWindowsButtonAlpha
static double G1C_Inl_ReopenAlpha(id self, SEL _cmd) {
    if (G1C_Inl_CanShow(self) && [(NSNumber *)G1B_GET(self, kInlShowing) boolValue]) return 1.0;
    return G1B_SUPER(double, gInlGrand, self, _cmd, (struct objc_super *, SEL));
}
// 0x1c7688400  reopenClosedWindowsButtonScale
static double G1C_Inl_ReopenScale(id self, SEL _cmd) {
    if ([(NSNumber *)G1B_GET(self, kInlShowing) boolValue]) return 1.0;
    id s = G1B_Send0(self, @selector(switcherSettings));
    return G1B_Dbl0(G1B_Send0(s, @selector(animationSettings)), NSSelectorFromString(@"reopenButtonInitialScale"));
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
static BOOL G1C_Inl_Focus(id self, SEL _cmd, id layout) { return ![layout isEqual:G1C_IvarObj(self, "_activeAppLayout")]; }          // 0x1c7688470 (NOT equal to the active window)
static BOOL G1C_Inl_NoGrabber(id self, SEL _cmd, id layout) { return NO; }
static BOOL G1C_Inl_Pointer(id self, SEL _cmd) { return YES; }
// 0x1c7688908  the other windows of the App Expose app (identifiers containing the bundle id, minus the active window)
static id G1C_Inl_InlineLayouts(id self, SEL _cmd) {
    NSMutableArray *out = [[NSMutableArray alloc] init];
    NSString *bid = G1C_IvarObj(self, "_appExposeBundleIdentifier");
    id active = G1C_IvarObj(self, "_activeAppLayout");
    for (id ident in (id<NSFastEnumeration>)G1B_Send0(self, NSSelectorFromString(@"continuousExposeIdentifiersInSwitcher")))
        if ([ident containsString:bid])
            for (id l in (id<NSFastEnumeration>)G1B_Send1(self, NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), ident))
                if (![l isEqual:active]) [out addObject:l];
    return out;
}
// 0x1c7688ea8
static double G1C_Inl_ScaleActive(id self, SEL _cmd) {
    double h = G1C_SendRect0(self, @selector(containerViewBounds)).size.height;
    double avail = h - G1B_Dbl0(self, @selector(floatingDockPresentedHeight)) + (-192.0);
    id model = G1C_Inl_Model(self, G1C_IvarObj(self, "_activeAppLayout"));
    double bh = model ? G1C_SendRect0(model, @selector(boundingBox)).size.height : 0.0;
    return fmin(avail / bh, 1.0);
}
// 0x1c76885fc  homeScreenDimmingAlpha: grows with the stage area covered by the active window
static double G1C_Inl_HomeDim(id self, SEL _cmd) {
    CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
    CGRect st = G1C_DM_StageArea(G1C_Inl_Model(self, G1C_IvarObj(self, "_activeAppLayout")));
    double x = (((st.size.width * st.size.height) / (cb.size.width * cb.size.height) + (-0.7)) * 0.5) / 0.30000000000000004;       // 0x1c7a91c50 / 0x1c7a91c58
    x = fmin(fmax(x, 0.0), 1.0);
    return x * 0.5;
}
// 0x1c7687b9c  the active window is pulled toward the overlapping model's bounding box when it is scaled
static CGRect G1C_Inl_FrameForRole(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    CGRect f = G1B_SUPER(CGRect, gInlGrand, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds);
    if (![layout isEqual:G1C_IvarObj(self, "_activeAppLayout")]) return f;
    id model = G1C_Inl_Model(self, layout);
    CGRect bb = model ? G1C_SendRect0(model, @selector(boundingBox)) : CGRectZero;
    double sc = ((double (*)(id, SEL, long long, id))objc_msgSend)(self, @selector(scaleForLayoutRole:inAppLayout:), role, layout);
    BOOL rtl = G1C_Inl_RTL();
    double k = 1.0 - sc;
    double dx = k * (CGRectGetMidX(f) - (rtl ? CGRectGetMinX(bb) : CGRectGetMaxX(bb)));
    double dy = k * (CGRectGetMidY(f) - CGRectGetMidY(bb));
    f.origin.x -= dx;
    f.origin.y -= dy;
    double x = CGRectGetMinX(f);
    CGRect sw = G1C_SendRect0(self, NSSelectorFromString(@"_inlineAppExposeSwitcherFrame"));
    if (rtl) { double lim = CGRectGetMinX(sw) - CGRectGetWidth(bb); if (x > lim) x = lim; }
    else     { double lim = CGRectGetMaxX(sw) - CGRectGetMinX(bb); if (x < lim) x = lim; }
    f.origin.x = x;
    double ss = G1B_Dbl0(self, @selector(screenScale));
    return CGRectMake(G1C_Inl_RS(f.origin.x, ss), G1C_Inl_RS(f.origin.y, ss), G1C_Inl_RS(f.size.width, ss), G1C_Inl_RS(f.size.height, ss));
}
// 0x1c7687eb4
static double G1C_Inl_ScaleForRole(id self, SEL _cmd, long long role, id layout) {
    double s = G1B_SUPER(double, gInlGrand, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    id attrs = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    id model = G1C_Inl_Model(self, layout);
    id item = G1C_SendLL1(layout, @selector(itemForLayoutRole:), role);
    if (G1C_Inl_ModelBool(model, @"isItemFullyOccluded:", item)) s *= G1B_Dbl0(attrs, NSSelectorFromString(@"stageOcclusionDodgingPeekScale"));
    else if (G1C_Inl_ModelBool(model, @"isItemPartiallyOccluded:", item)) {
        CGSize sz = ((CGSize (*)(id, SEL, id))objc_msgSend)(model, @selector(sizeForItem:), item);
        s *= ((double (*)(id, SEL, CGSize))objc_msgSend)(attrs, NSSelectorFromString(@"partiallyOccludedStageScaleForItemWithSize:"), sz);
    }
    if ([layout isEqual:G1C_IvarObj(self, "_activeAppLayout")]) return s * G1C_SendD0(self, NSSelectorFromString(@"_scaleForActiveAppLayoutLeafAppLayouts"));
    BOOL hover = [(NSSet *)G1B_Send0(self, @selector(highlightedByHoverAppLayouts)) containsObject:layout], touch = [(NSSet *)G1B_Send0(self, @selector(highlightedByTouchAppLayouts)) containsObject:layout];
    if (hover && touch) return s * 0.98;               // 0x1c7a91a38
    if (hover) return s * 1.1;                         // 0x1c7a90e60
    return touch ? s * 0.9 : s;                        // 0x1c7a90ee0
}
// 0x1c7687820  the windows of the App Expose app form a grid of columns (right to left in LTR) x rows, centred vertically
static CGRect G1C_Inl_FrameForIndex(id self, SEL _cmd, unsigned long long i) {
    CGRect f = G1B_SUPER(CGRect, gInlGrand, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    NSArray *inl = G1C_Inl_InlineLayouts(self, 0);
    NSArray *all = G1B_Send0(self, @selector(appLayouts));
    id layout = i < all.count ? all[i] : nil;
    if (![inl containsObject:layout]) return f;
    CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
    double a = round(cb.size.height * 0.0625), b = round(cb.size.height * 0.0625);          // both pads are height / 16 (0x3fb0000000000000)
    double gap = G1B_SendB0(self, NSSelectorFromString(@"isDisplayEmbedded")) ? 192.0 : 132.0;      // 0x1c7a91ff0 = 132.0
    double top = cb.size.height - G1B_Dbl0(self, @selector(floatingDockPresentedHeight)) + (-128.0);
    unsigned long long maxRows = G1C_SendULL0(self, NSSelectorFromString(@"_maximumNumberOfInlineAppExposeRows")), rows = G1C_SendULL0(self, NSSelectorFromString(@"_numberOfInlineAppExposeRows"));
    double rowH = round((top + (-128.0) - gap * (double)(maxRows - 1)) / (double)maxRows);
    double yOff = floor((gap * (double)(rows - 1) + rowH * (double)rows) * 0.5 - top * 0.5);
    unsigned long long idx = [inl indexOfObject:layout], col = rows ? idx / rows : 0, row = idx - col * rows;
    double cardW = G1C_DM_DefaultWindowSize(G1B_Send0(self, @selector(chamoisLayoutAttributes))).width * G1C_SendD0(self, NSSelectorFromString(@"_scaleForInlineAppExposeAppLayouts"));
    unsigned long long cols = G1C_SendULL0(self, NSSelectorFromString(@"_numberOfInlineAppExposeColumns"));
    double n = (double)(cols + ~col), xc;
    if (G1C_Inl_RTL()) xc = (CGRectGetMaxX(cb) - a + cardW * -0.5) - cardW * n - b * n;
    else               xc = (cardW * 0.5 + (a + CGRectGetMinX(cb))) + cardW * n + b * n;
    double yc = rowH * 0.5 + (CGRectGetMinX(cb) + 64.0) + (gap + rowH) * (double)row - yOff;      // CGRectGetMinX sic (16.2 uses MinX here)
    return CGRectMake(xc - f.size.width * 0.5, yc - f.size.height * 0.5, f.size.width, f.size.height);
}
// 0x1c7688c70  occluded = fully | partially | covered by a fully occluded peeking item (the 16.0 private model helper is gone)
static BOOL G1C_Inl_Occluded(id self, SEL _cmd, long long role, id layout) {
    id model = G1C_Inl_Model(self, layout), item = G1C_SendLL1(layout, @selector(itemForLayoutRole:), role);
    return G1C_Inl_ModelBool(model, @"isItemFullyOccluded:", item) || G1C_Inl_ModelBool(model, @"isItemPartiallyOccluded:", item) || G1C_Inl_ModelBool(model, @"isItemCoveredByFullyOccludedPeekingItem:", item);
}
// trivial 16.2-only queries
static double G1C_Inl_IconOutset(id self, SEL _cmd, id layout) { return 10.0; }                                          // 0x1c768823c
static id G1C_Inl_AccBundle(id self, SEL _cmd) { return G1C_IvarObj(self, "_appExposeBundleIdentifier"); }               // 0x1c768837c
static long long G1C_Inl_AccStyle(id self, SEL _cmd) { return 1; }                                                      // 0x1c768838c (UIUserInterfaceStyleLight)
static double G1C_Inl_PlusAlpha(id self, SEL _cmd) { return 1.0; }                                                      // 0x1c7688394
static long long G1C_Inl_PlusStyle(id self, SEL _cmd) { return 0; }                                                     // 0x1c768839c
static id G1C_Inl_Highlight(id self, SEL _cmd, id event) {
    if (G1C_ON() && event && G1C_Resp(event, @selector(isHandled)) && G1B_SendB0(event, @selector(isHandled))) return nil;      // 16.2 ignores handled highlight events
    return G1B_SUPER(id, gInlParent, self, _cmd, (struct objc_super *, SEL, id), event);
}

// ============================================================================================================
// 1g  SBStripContinuousExposeSwitcherModifier  (NEW in 16.2: the Stage Manager strip, split out of the FullScreen floor)         PORTED
// ============================================================================================================
// Faithful port of specs/SBStripContinuousExposeSwitcherModifier.md (16.2 class 0x1de230be8, methods 0x1c75de0cc..0x1c75e0770). 16.0 has no such class: it is built here with the
// 16.2 name (G1B_MakeClass never shadows a real one), superclass SBSwitcherModifier, 16.2 ivars as run-time ivars (scalars) / associated objects (object ivars, unretained
// otherwise). Parents (the FullScreen and HomeScreen floors, see 1h / 1i) add it as a child and reach it through `[super X]`, exactly like 16.2.
// The layout cache is the real SBSwitcherLayoutCalculationsCache (16.0 API names frameForKey:validityToken:fallback: / scaleForKey:... are the same; the 16.0 delegate selector
// is buildLayoutCalculations, 16.2's is buildLayoutCalculationsForCache: - both are implemented here).
static Class gStripCls, gStripSuper;
static char kStripCache, kStripTouch, kStripHover;
static BOOL G1C_RTL(void) { return [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft; }
static id G1C_Chamois(id s) { return G1C_Resp(s, @selector(chamoisLayoutAttributes)) ? G1B_Send0(s, @selector(chamoisLayoutAttributes)) : nil; }
static id G1C_ChamoisSettings(id s) { id sw = G1C_Resp(s, @selector(switcherSettings)) ? G1B_Send0(s, @selector(switcherSettings)) : nil; return G1C_Resp(sw, @selector(chamoisSettings)) ? G1B_Send0(sw, @selector(chamoisSettings)) : nil; }
static unsigned long long G1C_PerGroup(id s) { id cs = G1C_ChamoisSettings(s); return G1C_Resp(cs, @selector(numberOfVisibleItemsPerGroup)) ? (unsigned long long)G1B_SendLL0(cs, @selector(numberOfVisibleItemsPerGroup)) : 3; }
static id G1C_LayoutAtIdx(id s, unsigned long long i) { NSArray *ls = G1C_Resp(s, @selector(appLayouts)) ? G1B_Send0(s, @selector(appLayouts)) : nil; return i < ls.count ? ls[i] : nil; }
static NSString *G1C_CEId(id layout) { id v = G1C_Resp(layout, @selector(continuousExposeIdentifier)) ? G1B_Send0(layout, @selector(continuousExposeIdentifier)) : nil; return [v isKindOfClass:[NSString class]] ? v : nil; }
static BOOL G1C_FloatEq(double a, double b) { return fabs(a - b) < 0.0001; }

static id G1C_Strip_Init(id self, SEL _cmd) {
    id me = G1B_SUPER(id, gStripSuper, self, _cmd, (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kStripTouch, [NSMutableSet set]);
    G1B_SET(me, kStripHover, [NSMutableSet set]);
    Class cc = NSClassFromString(@"SBSwitcherLayoutCalculationsCache");
    id cache = cc ? [[cc alloc] init] : nil;
    if (cache) { G1B_SET(me, kStripCache, cache); G1B_SendV1(cache, @selector(setDelegate:), me); }
    return me;
}
static id G1C_Strip_GetTouch(id s, SEL c) { return G1B_GET(s, kStripTouch); }
static void G1C_Strip_SetTouch(id s, SEL c, id v) { G1B_SET(s, kStripTouch, v); }
static id G1C_Strip_GetHover(id s, SEL c) { return G1B_GET(s, kStripHover); }
static void G1C_Strip_SetHover(id s, SEL c, id v) { G1B_SET(s, kStripHover, v); }

static BOOL G1C_Strip_OnStage(id self, SEL _cmd, id layout) {                          // 0x1c75e0584
    id stage = G1C_Resp(self, @selector(appLayoutOnContinuousExposeStage)) ? G1B_Send0(self, @selector(appLayoutOnContinuousExposeStage)) : nil;
    if (!stage) return NO;
    if (G1B_SendB1(stage, @selector(containsAllItemsFromAppLayout:), layout) || G1B_SendB1(layout, @selector(containsAllItemsFromAppLayout:), stage)) return YES;
    id cs = G1C_ChamoisSettings(self);
    NSUInteger max = G1C_Resp(cs, @selector(maximumNumberOfAppsOnStage)) ? (NSUInteger)G1B_SendLL0(cs, @selector(maximumNumberOfAppsOnStage)) : 0;
    if (G1C_AsArray(G1B_Send0(stage, @selector(allItems))).count != max) return NO;
    NSArray *items = G1C_AsArray(G1B_Send0(layout, @selector(allItems)));
    if (items.count != max) return NO;
    NSUInteger shared = 0;
    for (id it in items) if (G1B_SendB1(stage, @selector(containsItem:), it)) shared++;
    return shared == max - 1;
}
static BOOL G1C_Strip_IsOnStage(id self, id layout) { return G1C_Strip_OnStage(self, NSSelectorFromString(@"_isAppLayoutEffectivelyOnStage:"), layout); }
static id G1C_Strip_LayoutsForId(id self, SEL _cmd, id ident) {                         // 0x1c75de180
    id layouts = G1B_HasSuper(gStripSuper, _cmd) ? G1B_SUPER(id, gStripSuper, self, _cmd, (struct objc_super *, SEL, id), ident) : @[];
    id stage = G1C_Resp(self, @selector(appLayoutOnContinuousExposeStage)) ? G1B_Send0(self, @selector(appLayoutOnContinuousExposeStage)) : nil;
    if (stage && [G1C_CEId(stage) isEqualToString:ident]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id l in G1C_AsArray(layouts)) if (!G1C_Strip_IsOnStage(self, l)) [out addObject:l];
        return out;
    }
    return layouts;
}
static unsigned long long G1C_Strip_PileIndex(id self, SEL _cmd, id layout) {           // 0x1c75dff60
    NSArray *pile = G1C_AsArray(G1C_Strip_LayoutsForId(self, NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), G1C_CEId(layout)));
    NSUInteger i = layout ? [pile indexOfObject:layout] : NSNotFound;
    return i == NSNotFound ? 0 : i;
}
static unsigned long long G1C_Strip_PileIdx(id self, id layout) { return G1C_Strip_PileIndex(self, 0, layout); }
static id G1C_Strip_Anim(id self, SEL _cmd, id element) {                               // 0x1c75dfa58
    id base = G1B_HasSuper(gStripSuper, _cmd) ? G1B_SUPER(id, gStripSuper, self, _cmd, (struct objc_super *, SEL, id), element) : nil;
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    G1B_SendVLL(a, @selector(setUpdateMode:), 3);
    return a;
}
static double G1C_Strip_StripProgress(id self) { return G1C_Resp(self, @selector(continuousExposeStripProgress)) ? G1C_SendD0(self, @selector(continuousExposeStripProgress)) : 0.0; }
static double G1C_Strip_OriginX(id self, SEL _cmd) {                                    // 0x1c75dffd4
    double progress = G1C_Strip_StripProgress(self);
    double cx = G1C_IvarD(self, "_cached_appStripOriginX"), cp = G1C_IvarD(self, "_cached_appStripUnocclusionProgress");
    if (cx == 0.0 || !G1C_FloatEq(cp, progress)) {
        G1C_SetIvarD(self, "_cached_appStripUnocclusionProgress", progress);
        id a = G1C_Chamois(self);
        double sw = G1B_Dbl0(a, @selector(stripWidth));
        double x = progress * (sw + G1B_Dbl0(a, @selector(screenEdgePadding))) - sw;
        if (G1C_RTL()) x = G1C_SendRect0(self, @selector(containerViewBounds)).size.width - x;
        G1C_SetIvarD(self, "_cached_appStripOriginX", x);
        cx = x;
    }
    return cx;
}
static void G1C_Strip_InvalidateOriginX(id self, SEL _cmd) { G1C_SetIvarD(self, "_cached_appStripOriginX", 0.0); G1C_SetIvarD(self, "_cached_appStripUnocclusionProgress", -1.0); }   // 0x1c75e0098
static CGRect G1C_Strip_StripFrame(id self, SEL _cmd) {                                 // 0x1c75e00b8
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    return CGRectMake(G1C_RTL() ? b.size.width : 0.0, 0.0, G1B_Dbl0(G1C_Chamois(self), @selector(stripWidth)), b.size.height);
}
static id G1C_Strip_Token(id self, SEL _cmd) {                                          // 0x1c75dfacc
    Class tc = NSClassFromString(@"BP162LayoutCalcValidityToken");
    SEL ini = NSSelectorFromString(@"initWithAppLayoutsGenCount:continuousExposeIdentifiersGenCount:switcherInterfaceOrientation:containerViewBounds:modifierEventGenCount:");
    unsigned long long a = (unsigned long long)G1B_SendLL0(self, @selector(appLayoutsGenerationCount)), c = (unsigned long long)G1B_SendLL0(self, NSSelectorFromString(@"continuousExposeIdentifiersGenerationCount"));
    long long o = G1B_SendLL0(self, @selector(switcherInterfaceOrientation));
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    unsigned long long g = (unsigned long long)G1C_IvarLL(self, "_modifierEventGenCount");
    if (tc && [tc instancesRespondToSelector:ini]) return ((id (*)(id, SEL, unsigned long long, unsigned long long, long long, CGRect, unsigned long long))objc_msgSend)([tc alloc], ini, a, c, o, b, g);
    return [NSString stringWithFormat:@"%llu/%llu/%lld/%@/%llu", a, c, o, NSStringFromCGRect(b), g];     // equal tokens compare equal
}
typedef CGRect (^G1CRectBlk)(void);
typedef double (^G1CDblBlk)(void);
static CGRect G1C_Strip_CacheFrame(id self, id key, id token, G1CRectBlk fb) {
    id cache = G1B_GET(self, kStripCache);
    SEL s = NSSelectorFromString(@"frameForKey:validityToken:fallback:");
    return G1C_Resp(cache, s) ? ((CGRect (*)(id, SEL, id, id, G1CRectBlk))objc_msgSend)(cache, s, key, token, fb) : fb();
}
static double G1C_Strip_CacheScale(id self, id key, id token, G1CDblBlk fb) {
    id cache = G1B_GET(self, kStripCache);
    SEL s = NSSelectorFromString(@"scaleForKey:validityToken:fallback:");
    return G1C_Resp(cache, s) ? ((double (*)(id, SEL, id, id, G1CDblBlk))objc_msgSend)(cache, s, key, token, fb) : fb();
}
static CGRect G1C_Strip_Frame(id self, SEL _cmd, unsigned long long index) {            // 0x1c75de2cc
    CGSize sz = G1B_SUPER(CGRect, gStripSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), index).size;
    id layout = G1C_LayoutAtIdx(self, index);
    NSString *ident = G1C_CEId(layout);
    id token = G1C_Strip_Token(self, 0);
    __unsafe_unretained id us = self;
    CGRect cached = G1C_Strip_CacheFrame(self, ident, token, ^CGRect{
        CGSize sf = G1B_SUPER(CGRect, gStripSuper, us, _cmd, (struct objc_super *, SEL, unsigned long long), index).size;
        double stripWidth = G1B_Dbl0(G1C_Chamois(us), @selector(stripWidth));
        CGRect bounds = G1C_SendRect0(us, @selector(containerViewBounds));
        double x = G1C_RTL() ? (0.5 * sf.width + bounds.size.width) : (0.0 - stripWidth - 0.5 * sf.width);
        return CGRectMake(x, 0.5 * bounds.size.height, sf.width, sf.height);
    });
    double x = cached.origin.x, y = cached.origin.y;                                       // the cache stores centre-form frames
    NSArray *stripIds = G1C_AsArray(G1C_Resp(self, @selector(continuousExposeIdentifiersInStrip)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInStrip)) : nil);
    if (ident && [stripIds containsObject:ident]) x = G1C_Strip_OriginX(self, 0);
    return CGRectMake(x - 0.5 * sz.width, y - 0.5 * sz.height, sz.width, sz.height);
}
static CGPoint G1C_Strip_Anchor(id self, SEL _cmd, unsigned long long index) {          // 0x1c75de53c
    id layout = G1C_LayoutAtIdx(self, index);
    NSArray *group = G1C_AsArray(G1C_Strip_LayoutsForId(self, NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), G1C_CEId(layout)));
    unsigned long long n = MIN((unsigned long long)group.count, G1C_PerGroup(self));
    double ax = 0.0;
    if (n >= 2) {
        id a = G1C_Chamois(self);
        double cardScale = G1B_Dbl0(a, @selector(stripCardScale)), stackDist = G1B_Dbl0(a, @selector(stripStackDistance));
        id token = G1C_Strip_Token(self, 0);
        NSString *ident = G1C_CEId(layout);
        CGRect gf = G1C_Strip_CacheFrame(self, ident, token, ^CGRect{
            if (BP_LogEnabled()) BP_Log(@"strip: group frame not in cache");           // 16.2 os_log_error "group frame not in cache"
            return CGRectMake(0, 0, 400, 400);
        });
        double cached = G1C_Strip_CacheScale(self, ident, token, ^double{ return cardScale; });
        NSUInteger pi = [group indexOfObject:layout];
        if (pi == NSNotFound) pi = 0;
        double unit = (stackDist / gf.size.width) * (cardScale / cached);
        ax = unit * (double)pi - ((double)n - 1.0) * unit;
    }
    if (G1C_RTL()) ax = 1.0 - ax;
    return CGPointMake(ax, 0.5);
}
static double G1C_Strip_HighlightScale(id self, SEL _cmd, id layout);
static double G1C_Strip_Scale(id self, SEL _cmd, unsigned long long index) {            // 0x1c75de7e8
    id layout = G1C_LayoutAtIdx(self, index);
    id token = G1C_Strip_Token(self, 0);
    NSString *ident = G1C_CEId(layout);
    __unsafe_unretained id us = self;
    double scale = G1C_Strip_CacheScale(self, ident, token, ^double{ return G1B_Dbl0(G1C_Chamois(us), @selector(stripCardScale)); });
    NSArray *group = G1C_AsArray(G1C_Strip_LayoutsForId(self, NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), ident));
    if (group.count >= 2) {
        double itemH = G1C_Strip_Frame(self, @selector(frameForIndex:), index).size.height;
        NSUInteger pi = [group indexOfObject:layout];
        if (pi == NSNotFound) pi = 0;
        double cachedH = G1C_Strip_CacheFrame(self, ident, token, ^CGRect{ return CGRectZero; }).size.height;
        double denom = (itemH == 0.0) ? 400.0 : itemH;
        scale = (scale * cachedH) / denom + (double)pi * -0.01;
    }
    return scale * G1C_Strip_HighlightScale(self, 0, layout);
}
static BOOL G1C_Strip_GroupHighlighted(id self, id set, id layout) {
    if (G1C_Strip_IsOnStage(self, layout)) return NO;
    NSString *ident = G1C_CEId(layout);
    for (id l in set) if ([G1C_CEId(l) isEqualToString:ident]) return YES;
    return NO;
}
static BOOL G1C_Strip_HighlightedTouch(id self, SEL _cmd, id layout) { return G1C_Strip_GroupHighlighted(self, G1B_GET(self, kStripTouch), layout); }   // 0x1c75e02b4
static BOOL G1C_Strip_HighlightedHover(id self, SEL _cmd, id layout) { return G1C_Strip_GroupHighlighted(self, G1B_GET(self, kStripHover), layout); }   // 0x1c75e041c
static double G1C_Strip_HighlightScale(id self, SEL _cmd, id layout) {                  // 0x1c75dea24
    if (G1C_Strip_PileIdx(self, layout) != 0) return 1.0;
    BOOL hover = G1C_Strip_HighlightedHover(self, 0, layout), touch = G1C_Strip_HighlightedTouch(self, 0, layout);
    if (hover && touch) return 0.98;
    if (!hover || touch) return touch ? 0.9 : 1.0;
    return 1.1;
}
static CGRect G1C_Strip_AccFrame(id self, SEL _cmd, CGRect frame, id layout) {          // 0x1c75dead4
    NSArray *ids = G1C_AsArray(G1C_Resp(self, @selector(continuousExposeIdentifiersInStrip)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInStrip)) : nil);
    NSString *ident = G1C_CEId(layout);
    if (ident && [ids indexOfObject:ident] != NSNotFound) frame.origin.x = G1C_Strip_OriginX(self, 0) + (-0.5 * frame.size.width);
    return frame;
}
static CGPoint G1C_Strip_AccAnchor(id self, SEL _cmd, CGPoint p, id layout) { return CGPointMake(G1C_RTL() ? 1.0 : 0.0, p.y); }          // 0x1c75deb90
static double G1C_Strip_AccScale(id self, SEL _cmd, double s, id layout) { return s / G1C_Strip_HighlightScale(self, 0, layout); }        // 0x1c75debd4
static G1CRadii G1C_Strip_Corner(id self, SEL _cmd, unsigned long long index) {          // 0x1c75def2c
    id layout = G1C_LayoutAtIdx(self, index);
    if (G1C_Strip_IsOnStage(self, layout)) return G1B_SUPER(G1CRadii, gStripSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), index);
    double r = G1B_Dbl0(G1C_Chamois(self), @selector(stripCornerRaddii)) / G1C_SendD0Q(self, @selector(scaleForIndex:), index);
    return (G1CRadii){ r, r, r, r };
}
static unsigned long long G1C_Strip_Masked(id self, SEL _cmd, unsigned long long i) { return 0xF; }                // 0x1c75df018
static double G1C_Strip_ShadowOpacity(id self, SEL _cmd, long long role, unsigned long long i) { return 1.0; }     // 0x1c75df020
static long long G1C_Strip_ShadowStyle(id self, SEL _cmd, long long role, id l) { return 5; }                       // 0x1c75df028
static long long G1C_Strip_HeaderStyle(id self, SEL _cmd, unsigned long long i) { return 1; }                       // 0x1c75df48c
static double G1C_Strip_PageScale(id self, SEL _cmd, id l, double s) { return s; }                                  // 0x1c75df494
static double G1C_Strip_Zero1(id self, SEL _cmd, unsigned long long i) { return 0.0; }                              // titleOpacity 0x1c75df510 / backgroundOpacity 0x1c75df520
static double G1C_Strip_Dimming(id self, SEL _cmd, long long role, id l) { return 0.0; }                            // 0x1c75df518
static BOOL G1C_Strip_NoHomeAffordance(id self, SEL _cmd, id l) { return NO; }                                      // 0x1c75df5dc
static double G1C_Strip_TitleIcon(id self, SEL _cmd, unsigned long long index) { return G1C_Strip_PileIdx(self, G1C_LayoutAtIdx(self, index)) == 0 ? 1.0 : 0.0; }   // 0x1c75df498
static double G1C_Strip_Perspective(id self, SEL _cmd, id layout) {                      // 0x1c75df528
    double tilt = G1B_Dbl0(G1C_Chamois(self), @selector(stripTiltAngle));
    return G1C_RTL() ? -tilt : tilt;
}
static double G1C_Strip_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long index) {      // 0x1c75dee60
    double o = G1B_HasSuper(gStripSuper, _cmd) ? G1B_SUPER(double, gStripSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, index) : 1.0;
    return G1C_Strip_PileIdx(self, layout) > G1C_PerGroup(self) ? 0.0 : o;
}
static double G1C_Strip_WallpaperDimming(id self, SEL _cmd, unsigned long long index) { // 0x1c75df3e4
    id layout = G1C_LayoutAtIdx(self, index);
    BOOL hover = G1C_Strip_HighlightedHover(self, 0, layout);
    unsigned long long pi = G1C_Strip_PileIdx(self, layout);
    if (hover && pi == 0) return 0.0;
    double d = (double)pi * 0.25 + 0.1;
    return hover ? d + 0.1 : d;
}
// 0x1c75e0174: QuartzCore's CAPointApplyTransform on the layer transform, then the container perspective (m34 = -1/perspective)
static CGPoint G1C_Strip_Project(id self, CGPoint space, CGPoint position, CGSize size, CGPoint anchor, CATransform3D T, double perspective) {
    CGRect bounds = G1C_SendRect0(self, @selector(containerViewBounds));
    double ptX = space.x + size.width * (0.5 - anchor.x), ptY = space.y + size.height * (0.5 - anchor.y);
    double px = T.m11 * ptX + T.m21 * ptY + T.m41, py = T.m12 * ptX + T.m22 * ptY + T.m42, pz = T.m13 * ptX + T.m23 * ptY + T.m43;
    double halfW = bounds.size.width * 0.5, halfH = bounds.size.height * 0.5;
    double x1 = px + (position.x - halfW), y1 = py + (position.y - halfH);
    double qw = 1.0 + (-1.0 / perspective) * pz;
    return CGPointMake(halfW + x1 / qw, halfH + y1 / qw);
}
typedef struct { double lead, trail; } G1CGrad;
static G1CGrad G1C_Strip_Gradient(id self, SEL _cmd, unsigned long long index) {         // 0x1c75df030
    id layout = G1C_LayoutAtIdx(self, index);
    double dimming = G1C_Strip_WallpaperDimming(self, 0, index), lead = 0.0, trail = 0.0;
    if (dimming > 0.0001) {
        double angle = ((double (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"perspectiveAngleForAppLayout:"), layout);
        lead = trail = dimming;
        if (!G1C_FloatEq(angle, 0.0)) {
            id a = G1C_Chamois(self);
            double edgePad = G1B_Dbl0(a, @selector(screenEdgePadding)), stripWidth = G1B_Dbl0(a, @selector(stripWidth)), persp = G1B_Dbl0(a, @selector(containerPerspective));
            CGRect f = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), index);
            double sc = G1C_SendD0Q(self, @selector(scaleForIndex:), index);
            CGPoint ap = ((CGPoint (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(anchorPointForIndex:), index);
            CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
            CATransform3D T = CATransform3DConcat(CATransform3DMakeScale(sc, sc, 1.0), CATransform3DMakeRotation(angle, 0.0, 1.0, 0.0));
            double leftX = G1C_Strip_Project(self, CGPointMake(-0.5 * f.size.width, 0.0), c, f.size, ap, T, persp).x;
            double rightX = G1C_Strip_Project(self, CGPointMake(0.5 * f.size.width, 0.0), c, f.size, ap, T, persp).x;
            double extra = 0.25;
            CGSize mdw = G1C_Resp(a, @selector(minimumDefaultWindowSize)) ? G1C_SendSize0(a, @selector(minimumDefaultWindowSize)) : CGSizeZero;
            if (!G1C_FloatEq(mdw.width, 0.0)) extra = G1B_SendB0(self, @selector(prefersStripHidden)) ? 0.25 : 0.6;
            double maxDim = dimming + extra, range = maxDim - dimming, span = stripWidth - edgePad, dLeft, dRight;
            if (G1C_RTL()) {
                double maxX = CGRectGetMaxX(G1C_SendRect0(self, @selector(containerViewBounds)));
                dLeft = range * ((maxX - leftX) - edgePad) / span; dRight = range * ((maxX - rightX) - edgePad) / span;
            } else { dLeft = range * (leftX - edgePad) / span; dRight = range * (rightX - edgePad) / span; }
            trail = MAX(dimming, MIN(dimming + dLeft, maxDim));
            lead = MAX(dimming, MIN(dimming + dRight, maxDim));
        }
    }
    return (G1CGrad){ lead, trail };
}
static id G1C_Strip_Ordered(id self, BOOL ignoring) {                                    // 0x1c75dec4c
    NSMutableOrderedSet *result = [NSMutableOrderedSet orderedSetWithArray:@[]];
    if (G1C_Strip_StripProgress(self) > 0.0001 || G1B_SendB0(self, @selector(requireStripContentsInViewHierarchy)) || ignoring) {
        NSArray *ids = G1C_AsArray(G1C_Resp(self, @selector(continuousExposeIdentifiersInStrip)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInStrip)) : nil);
        unsigned long long per = G1C_PerGroup(self);
        NSCountedSet *seen = [[NSCountedSet alloc] init];
        for (NSString *ident in ids)
            for (id l in G1C_AsArray(G1C_Strip_LayoutsForId(self, NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), ident))) {
                [seen addObject:ident];
                if ([seen countForObject:ident] <= per) [result addObject:l];
            }
    }
    return result;
}
static id G1C_Strip_Visible(id self, SEL _cmd) { return [(NSOrderedSet *)G1C_Strip_Ordered(self, NO) set]; }                          // 0x1c75debfc
static id G1C_Strip_TopMost(id self, SEL _cmd) { return [G1C_Strip_Ordered(self, NO) array]; }                       // 0x1c75df58c
static id G1C_Strip_Inactive(id self, SEL _cmd) { return [G1C_Strip_Ordered(self, YES) array]; }                      // 0x1c75df5e4 (ignores the strip progress: the strip may be hidden)
static id G1C_Strip_HandleEvent(id self, SEL _cmd, id event) {                           // 0x1c75df634
    G1C_Strip_InvalidateOriginX(self, 0);
    G1C_SetIvarLL(self, "_modifierEventGenCount", G1C_IvarLL(self, "_modifierEventGenCount") + 1);
    BOOL require = G1B_SendB0(self, @selector(requireStripContentsInViewHierarchy));
    id response = nil;
    if (G1C_IvarBool(self, "_requireStripContentsInViewHierarchy") != require) {
        G1C_SetIvarBool(self, "_requireStripContentsInViewHierarchy", require);
        response = G1B_AppendTo(G1B_NewUpdateLayoutResponse(2, 0), nil);
    }
    id sup = G1B_HasSuper(gStripSuper, _cmd) ? G1B_SUPER(id, gStripSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    return response ? G1B_AppendTo(response, sup) : sup;
}
static id G1C_Strip_HandleHighlight(id self, SEL _cmd, id event) {                       // 0x1c75df73c
    id response = G1B_HasSuper(gStripSuper, _cmd) ? G1B_SUPER(id, gStripSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    id layout = G1B_Send0(event, @selector(appLayout));
    if (!G1B_SendB0(event, @selector(isHandled)) && layout) {
        long long phase = G1B_SendLL0(event, @selector(phase));
        BOOL onStage = G1C_Strip_IsOnStage(self, layout), isHover = G1B_SendB0(event, @selector(isHoverEvent)), phaseEnd = (unsigned long long)(phase - 1) < 2;
        NSMutableSet *hover = G1B_GET(self, kStripHover), *touch = G1B_GET(self, kStripTouch);
        if (!onStage && !phaseEnd) {
            [(isHover ? hover : touch) addObject:layout];
        } else {
            NSMutableSet *set = (isHover && phaseEnd) ? hover : touch;                 // as compiled: a hover event that is on stage / not 1,2 uses the TOUCH set
            if ([set containsObject:layout]) [set removeObject:layout];
            else for (id m in [set copy]) if (G1B_SendB1(m, @selector(containsAnyItemFromAppLayout:), layout)) [set removeObject:m];
        }
        response = G1B_AppendTo(G1B_NewUpdateLayoutResponse(0xc, 0), response);
        G1C_HandleEvent(event, @"Full Screen Continuous Expose");
    }
    return response;
}
static id G1C_Strip_Build(id self, SEL _cmd, id cache) {                                // 0x1c75dfb68
    NSArray *ids = G1C_AsArray(G1C_Resp(self, @selector(continuousExposeIdentifiersInStrip)) ? G1B_Send0(self, @selector(continuousExposeIdentifiersInStrip)) : nil);
    NSUInteger n = ids.count;
    id a = G1C_Chamois(self);
    double stripWidth = G1B_Dbl0(a, @selector(stripWidth)), stackDist = G1B_Dbl0(a, @selector(stripStackDistance)), cardScale = G1B_Dbl0(a, @selector(stripCardScale)), spacing = G1B_Dbl0(a, @selector(stripInterItemSpacing));
    CGRect bounds = G1C_SendRect0(self, @selector(containerViewBounds));
    unsigned long long perGroup = G1C_PerGroup(self);
    double availH = bounds.size.height;
    if (!G1B_SendB0(self, @selector(prefersDockHidden))) availH -= G1B_Dbl0(self, @selector(floatingDockHeight));
    double (^limitFor)(NSUInteger) = ^double(NSUInteger count) { return bounds.size.width - 2.0 * stripWidth + stackDist * (double)((long long)perGroup - (long long)count); };
    Class cc = NSClassFromString(@"SBSwitcherLayoutCalculations");
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:n];
    double y = 0.0;
    for (NSUInteger i = 0; i < n; i++) {
        NSString *ident = ids[i];
        NSArray *group = G1C_AsArray(G1C_Strip_LayoutsForId(self, NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), ident));
        id first = group.firstObject;
        id m = first && G1C_Resp(self, @selector(overlappingModelForAppLayout:)) ? G1B_Send1(self, @selector(overlappingModelForAppLayout:), first) : nil;
        CGRect bb = G1C_Resp(m, @selector(boundingBox)) ? G1C_SendRect0(m, @selector(boundingBox)) : CGRectZero;
        double limit = limitFor(group.count), scale = cardScale;
        if (bb.size.width > limit) scale = cardScale * (limit / bb.size.width);
        double scaledH = bb.size.height * scale;
        id calc = cc ? [[cc alloc] init] : nil;
        G1C_SendVD(calc, @selector(setScale:), scale);
        if (calc && [calc respondsToSelector:@selector(setFrame:)]) ((void (*)(id, SEL, CGRect))objc_msgSend)(calc, @selector(setFrame:), CGRectMake(0.0, y + scaledH * 0.5, bb.size.width, bb.size.height));
        if (calc) dict[ident] = calc;
        y = (i + 1 < n) ? y + scaledH + spacing : y + scaledH;
    }
    double yOff = (availH + 0.0) * 0.5 - (y * 0.5);
    for (NSString *k in dict) {
        id c = dict[k];
        CGRect f = ((CGRect (*)(id, SEL))objc_msgSend)(c, @selector(frame));
        f.origin.y += yOff;
        ((void (*)(id, SEL, CGRect))objc_msgSend)(c, @selector(setFrame:), f);
    }
    return dict;
}
static id G1C_Strip_Build0(id self, SEL _cmd) { return G1C_Strip_Build(self, _cmd, nil); }      // 16.0 delegate selector buildLayoutCalculations
static BOOL G1C_BuildStrip(void) {
    gStripSuper = NSClassFromString(@"SBSwitcherModifier");
    if (!gStripSuper) return NO;
    const G1BIvar iv[] = {
        { "_requireStripContentsInViewHierarchy", 1, 0, "B" }, { "_modifierEventGenCount", 8, 3, "Q" },
        { "_cached_appStripOriginX", 8, 3, "d" }, { "_cached_appStripUnocclusionProgress", 8, 3, "d" },
    };
    const G1BMethod m[] = {
        { "init", (IMP)G1C_Strip_Init, "@16@0:8" },
        { "highlightedByTouchAppLayouts", (IMP)G1C_Strip_GetTouch, "@16@0:8" }, { "setHighlightedByTouchAppLayouts:", (IMP)G1C_Strip_SetTouch, "v24@0:8@16" },
        { "highlightedByHoverAppLayouts", (IMP)G1C_Strip_GetHover, "@16@0:8" }, { "setHighlightedByHoverAppLayouts:", (IMP)G1C_Strip_SetHover, "v24@0:8@16" },
        { "appLayoutsForContinuousExposeIdentifier:", (IMP)G1C_Strip_LayoutsForId, "@24@0:8@16" },
        { "_indexInContinuousExposeIdentifierPileForAppLayout:", (IMP)G1C_Strip_PileIndex, "Q24@0:8@16" },
        { "_isAppLayoutEffectivelyOnStage:", (IMP)G1C_Strip_OnStage, "B24@0:8@16" },
        { "animationAttributesForLayoutElement:", (IMP)G1C_Strip_Anim, "@24@0:8@16" },
        { "_appStripOriginX", (IMP)G1C_Strip_OriginX, "d16@0:8" }, { "_invalidateAppStripOriginX", (IMP)G1C_Strip_InvalidateOriginX, "v16@0:8" },
        { "_stripFrame", (IMP)G1C_Strip_StripFrame, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8" },
        { "frameForIndex:", (IMP)G1C_Strip_Frame, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
        { "anchorPointForIndex:", (IMP)G1C_Strip_Anchor, "{CGPoint=dd}24@0:8Q16" },
        { "scaleForIndex:", (IMP)G1C_Strip_Scale, "d24@0:8Q16" },
        { "_highlightScaleForAppLayout:", (IMP)G1C_Strip_HighlightScale, "d24@0:8@16" },
        { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1C_Strip_AccFrame, "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48" },
        { "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (IMP)G1C_Strip_AccAnchor, "{CGPoint=dd}40@0:8{CGPoint=dd}16@32" },
        { "adjustedSpaceAccessoryViewScale:forAppLayout:", (IMP)G1C_Strip_AccScale, "d32@0:8d16@24" },
        { "cornerRadiiForIndex:", (IMP)G1C_Strip_Corner, "{UIRectCornerRadii=dddd}24@0:8Q16" },
        { "maskedCornersForIndex:", (IMP)G1C_Strip_Masked, "Q24@0:8Q16" },
        { "shadowOpacityForLayoutRole:atIndex:", (IMP)G1C_Strip_ShadowOpacity, "d32@0:8q16Q24" },
        { "shadowStyleForLayoutRole:inAppLayout:", (IMP)G1C_Strip_ShadowStyle, "q32@0:8q16@24" },
        { "headerStyleForIndex:", (IMP)G1C_Strip_HeaderStyle, "q24@0:8Q16" },
        { "contentPageViewScaleForAppLayout:withScale:", (IMP)G1C_Strip_PageScale, "d32@0:8@16d24" },
        { "titleOpacityForIndex:", (IMP)G1C_Strip_Zero1, "d24@0:8Q16" },
        { "dimmingAlphaForLayoutRole:inAppLayout:", (IMP)G1C_Strip_Dimming, "d32@0:8q16@24" },
        { "backgroundOpacityForIndex:", (IMP)G1C_Strip_Zero1, "d24@0:8Q16" },
        { "isHomeAffordanceSupportedForAppLayout:", (IMP)G1C_Strip_NoHomeAffordance, "B24@0:8@16" },
        { "titleAndIconOpacityForIndex:", (IMP)G1C_Strip_TitleIcon, "d24@0:8Q16" },
        { "perspectiveAngleForAppLayout:", (IMP)G1C_Strip_Perspective, "d24@0:8@16" },
        { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_Strip_Opacity, "d40@0:8q16@24Q32" },
        { "_wallpaperDimmingForIndex:", (IMP)G1C_Strip_WallpaperDimming, "d24@0:8Q16" },
        { "wallpaperGradientAttributesForIndex:", (IMP)G1C_Strip_Gradient, "{SBSwitcherGradientWallpaperAttributes=dd}24@0:8Q16" },
        { "visibleAppLayouts", (IMP)G1C_Strip_Visible, "@16@0:8" },
        { "topMostLayoutElements", (IMP)G1C_Strip_TopMost, "@16@0:8" },
        { "inactiveAppLayoutsReachableByKeyboardShortcut", (IMP)G1C_Strip_Inactive, "@16@0:8" },
        { "_isGroupForAppLayoutHighlightedFromTouch:", (IMP)G1C_Strip_HighlightedTouch, "B24@0:8@16" },
        { "_isGroupForAppLayoutHighlightedFromHover:", (IMP)G1C_Strip_HighlightedHover, "B24@0:8@16" },
        { "handleEvent:", (IMP)G1C_Strip_HandleEvent, "@24@0:8@16" },
        { "handleHighlightEvent:", (IMP)G1C_Strip_HandleHighlight, "@24@0:8@16" },
        { "_currentLayoutCalculationsValidityToken", (IMP)G1C_Strip_Token, "@16@0:8" },
        { "buildLayoutCalculationsForCache:", (IMP)G1C_Strip_Build, "@24@0:8@16" },
        { "buildLayoutCalculations", (IMP)G1C_Strip_Build0, "@16@0:8" },
    };
    gStripCls = G1B_MakeClass("SBStripContinuousExposeSwitcherModifier", gStripSuper, iv, sizeof iv / sizeof iv[0], m, sizeof m / sizeof m[0], NULL, NULL);
    return gStripCls != Nil;
}
// ============================================================================================================
// 1h  SBFullScreenContinuousExposeSwitcherModifier  (16.2 form: a thin floor with two children, SBFullScreenAppLayoutSwitcherModifier + the Strip)       PORTED
// ============================================================================================================
// specs/SBFullScreenContinuousExposeSwitcherModifier.md. The 16.0 class does the stage AND the whole strip inline; 16.2 splits the strip out (1g). The class is allocated
// by 16.0 code paths too, so it is converted IN PLACE: the 37 logic-changed 16.0 methods and the 16.2-only ones get the 16.2 implementation (class_replaceMethod /
// class_addMethod before the first instance), and the 16.0-only protocol / event methods that would shadow the strip child are turned into plain `[super]` pass-throughs.
// 16.2 object state: _stripModifier / _zOrderedLeafAppLayoutsForKeyboardNavigation / the two handle flags are associated objects (the class cannot get ivars);
// _fullScreenAppLayout and _fullScreenAppLayoutModifier are the 16.0 ivars of the same name.
static Class gFsCls, gFsSuper;
static char kFsStrip, kFsZ, kFsTap, kFsHdr;
static id G1C_FS_Layout(id s) { return G1C_IvarObj(s, "_fullScreenAppLayout"); }
static id G1C_FS_Child(id s) { return G1C_IvarObj(s, "_fullScreenAppLayoutModifier"); }
static BOOL G1C_FS_OnStage(id s, id layout) {                                          // 0x1c75c5334
    id fs = G1C_FS_Layout(s);
    if (G1B_SendB1(fs, @selector(containsAllItemsFromAppLayout:), layout) || G1B_SendB1(layout, @selector(containsAllItemsFromAppLayout:), fs)) return YES;
    id cs = G1C_ChamoisSettings(s);
    NSUInteger max = G1C_Resp(cs, @selector(maximumNumberOfAppsOnStage)) ? (NSUInteger)G1B_SendLL0(cs, @selector(maximumNumberOfAppsOnStage)) : 0;
    if (G1C_AsArray(G1B_Send0(fs, @selector(allItems))).count != max) return NO;
    NSArray *items = G1C_AsArray(G1B_Send0(layout, @selector(allItems)));
    if (items.count != max) return NO;
    NSUInteger shared = 0;
    for (id it in items) if (G1B_SendB1(fs, @selector(containsItem:), it)) shared++;
    return shared == max - 1;
}
static BOOL G1C_FS_OnStageIMP(id self, SEL _cmd, id layout) { return G1C_FS_OnStage(self, layout); }
static BOOL G1C_FS_Maximized(id s, id layout) { return G1B_SendB1(s, NSSelectorFromString(@"appLayoutContainsAnUnoccludedMaximizedDisplayItem:"), layout); }
static id G1C_FS_Model(id s, id layout) { return layout && G1C_Resp(s, @selector(overlappingModelForAppLayout:)) ? G1B_Send1(s, @selector(overlappingModelForAppLayout:), layout) : nil; }
static BOOL G1C_FS_Exceeds(id self, SEL _cmd) {                                        // 0x1c75c5244
    id m = G1C_FS_Model(self, G1C_FS_Layout(self));
    return G1C_Resp(m, @selector(isContinuousExposeStripVisible)) ? !G1B_SendB0(m, @selector(isContinuousExposeStripVisible)) : NO;
}
static double G1C_FS_RevealProgress(id self, SEL _cmd) {                               // 0x1c75c2d6c: [super continuousExposeStripProgress]
    SEL q = NSSelectorFromString(@"continuousExposeStripProgress");
    return G1B_HasSuper(gFsSuper, q) ? G1B_SUPER(double, gFsSuper, self, q, (struct objc_super *, SEL)) : 0.0;
}
static double G1C_FS_Reveal(id s) { return G1C_FS_RevealProgress(s, 0); }
static double G1C_FS_StripProgress(id self, SEL _cmd) {                                // 0x1c75c2d14
    if (G1C_FS_Exceeds(self, 0) || G1B_SendB0(self, @selector(prefersStripHidden))) {
        double r = G1C_FS_Reveal(self);
        if (BP_LogEnabled()) {                                                         // diagnostics: why the strip is (partly) hidden, logged when the reveal value changes
            static double last = -1; static BOOL lastEx;
            BOOL ex = G1C_FS_Exceeds(self, 0);
            if (!G1C_FloatEq(r, last) || ex != lastEx) {
                last = r; lastEx = ex;
                id m = G1C_FS_Model(self, G1C_FS_Layout(self));
                BP_Log(@"g1c: strip hidden: exceedsWidth=%d prefersStripHidden=%d reveal=%.4f threshold=%.1f container=%.1f", ex, G1B_SendB0(self, @selector(prefersStripHidden)), r,
                       m ? G1C_DM_WidthThresholdToHideStrip(m) : -1.0, G1C_SendRect0(self, @selector(containerViewBounds)).size.width);
            }
        }
        return r;
    }
    return 1.0;
}
static BOOL G1C_FS_RevealedFromHidden(id self, SEL _cmd) {                              // 0x1c75c54c4
    if (G1C_FS_Exceeds(self, 0) || G1B_SendB0(self, @selector(prefersStripHidden))) return G1C_FS_Reveal(self) > 0.0001;
    return NO;
}
static BOOL G1C_FS_IsFullScreenLayout(id self, SEL _cmd, id layout) { return [layout isEqual:G1C_FS_Layout(self)] && G1C_FS_Maximized(self, layout); }   // 0x1c75c4378
static unsigned int G1C_FS_StripEdge(id self, SEL _cmd) { return G1C_RTL() ? 2 : 0; }  // 0x1c75c5520
static BOOL G1C_FS_WantsHideHover(id self, SEL _cmd) { return G1C_FS_Reveal(self) > 0.0001; }       // 0x1c75c4600
static BOOL G1C_FS_WantsHover(id self, SEL _cmd) {                                      // 0x1c75c45ac
    SEL q = NSSelectorFromString(@"wantsContinuousExposeHoverGesture");
    BOOL s = G1B_HasSuper(gFsSuper, q) ? G1B_SUPER(BOOL, gFsSuper, self, q, (struct objc_super *, SEL)) : NO;
    return s | G1C_FS_WantsHideHover(self, 0);
}
static void G1C_FS_ResetZ(id self, SEL _cmd) {                                          // 0x1c75c5550
    id fs = G1C_FS_Layout(self);
    G1B_SET(self, kFsZ, G1C_Resp(fs, @selector(zOrderedLeafAppLayouts)) ? G1B_Send0(fs, @selector(zOrderedLeafAppLayouts)) : nil);
}
static id G1C_FS_ActiveLeafs(id self, SEL _cmd) { return G1B_GET(self, kFsZ); }          // 0x1c75c3f14
static BOOL G1C_FS_CanSelectLeaf(id self, SEL _cmd, id layout) { return !G1B_SendB1(G1C_FS_Layout(self), NSSelectorFromString(@"isOrContainsAppLayout:"), layout); }       // 0x1c75c3eec
static id G1C_FS_Init(id self, SEL _cmd, id appLayout) {                                // 0x1c75c2990
    id me = G1B_SUPER(id, gFsSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    if (!appLayout) { BP_Log(@"fullscreen floor: initWithFullScreenAppLayout: nil (16.2 asserts, line 45)"); return nil; }
    G1C_SetIvarObj(me, "_fullScreenAppLayout", appLayout);
    G1C_FS_ResetZ(me, 0);
    G1B_SET(me, kFsTap, @YES);
    G1B_SET(me, kFsHdr, @YES);
    Class fc = NSClassFromString(@"SBFullScreenAppLayoutSwitcherModifier");
    SEL fi = NSSelectorFromString(@"initWithActiveAppLayout:");
    id fm = (fc && [fc instancesRespondToSelector:fi]) ? G1B_Send1([fc alloc], fi, appLayout) : nil;
    if (fm) { G1C_SetIvarObj(me, "_fullScreenAppLayoutModifier", fm); G1B_SendV1(me, @selector(addChildModifier:), fm); }
    id strip = gStripCls ? [[gStripCls alloc] init] : nil;
    if (strip) { G1B_SET(me, kFsStrip, strip); G1B_SendV1(me, @selector(addChildModifier:), strip); }
    return me;
}
static id G1C_FS_GetTouch(id s, SEL c) { return G1B_Send0(G1B_GET(s, kFsStrip), @selector(highlightedByTouchAppLayouts)); }
static void G1C_FS_SetTouch(id s, SEL c, id v) { G1B_SendV1(G1B_GET(s, kFsStrip), @selector(setHighlightedByTouchAppLayouts:), v); }
static id G1C_FS_GetHover(id s, SEL c) { return G1B_Send0(G1B_GET(s, kFsStrip), @selector(highlightedByHoverAppLayouts)); }
static void G1C_FS_SetHover(id s, SEL c, id v) { G1B_SendV1(G1B_GET(s, kFsStrip), @selector(setHighlightedByHoverAppLayouts:), v); }
static BOOL G1C_FS_GetTapFlag(id s, SEL c) { return [(NSNumber *)G1B_GET(s, kFsTap) boolValue]; }
static void G1C_FS_SetTapFlag(id s, SEL c, BOOL v) { G1B_SET(s, kFsTap, @(v)); }
static BOOL G1C_FS_GetHdrFlag(id s, SEL c) { return [(NSNumber *)G1B_GET(s, kFsHdr) boolValue]; }
static void G1C_FS_SetHdrFlag(id s, SEL c, BOOL v) { G1B_SET(s, kFsHdr, @(v)); }

// ---- geometry ----
static CGRect G1C_FS_Frame(id self, SEL _cmd, unsigned long long i) {                   // 0x1c75c2da4
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(G1C_FS_Child(self), _cmd, i);
    return G1B_SUPER(CGRect, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGPoint G1C_FS_Anchor(id self, SEL _cmd, unsigned long long i) {                 // 0x1c75c2e74
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_FS_Scale(id self, SEL _cmd, unsigned long long i) {                   // 0x1c75c2f1c
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return G1C_SendD0Q(G1C_FS_Child(self), _cmd, i);
    return G1B_SUPER(double, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGRect G1C_FS_AccFrame(id self, SEL _cmd, CGRect f, id layout) {                 // 0x1c75c2fcc
    if (!G1C_FS_OnStage(self, layout)) return G1B_SUPER(CGRect, gFsSuper, self, _cmd, (struct objc_super *, SEL, CGRect, id), f, layout);
    return f;
}
static CGPoint G1C_FS_AccAnchor(id self, SEL _cmd, CGPoint p, id layout) {              // 0x1c75c3080
    if (!G1C_FS_OnStage(self, layout)) return G1B_SUPER(CGPoint, gFsSuper, self, _cmd, (struct objc_super *, SEL, CGPoint, id), p, layout);
    return p;
}
// stage squeeze when the strip is revealed from the hidden state: shared fit factor of the stage's bounding box
static BOOL G1C_FS_Squeeze(id self, double *outFit, CGRect *outBB, id *outModel, double *outStrip, double *outPad, double *outCW) {
    double progress = G1C_FS_Reveal(self);
    if (!(progress > 0.0001)) return NO;
    double cw = G1C_SendRect0(self, @selector(containerViewBounds)).size.width;
    id a = G1C_Chamois(self), model = G1C_FS_Model(self, G1C_FS_Layout(self));
    CGRect bb = G1C_Resp(model, @selector(boundingBox)) ? G1C_SendRect0(model, @selector(boundingBox)) : CGRectZero;
    double sw = G1B_Dbl0(a, @selector(stripWidth)), pad = G1B_Dbl0(a, @selector(screenEdgePadding));
    *outFit = bb.size.width > 0 ? MIN((cw - sw - pad) / bb.size.width, 1.0) : 1.0;
    *outBB = bb; *outModel = model; *outStrip = sw; *outPad = pad; *outCW = cw;
    return YES;
}
static CGRect G1C_FS_RoleFrame(id self, SEL _cmd, long long role, id layout, CGRect bounds) {      // 0x1c75c310c
    CGRect frame = G1B_SUPER(CGRect, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds);
    if (!G1C_FS_OnStage(self, layout)) return frame;
    double fit, sw, pad, cw; CGRect bb; id model;
    if (!G1C_FS_Squeeze(self, &fit, &bb, &model, &sw, &pad, &cw)) return frame;
    double progress = G1C_FS_Reveal(self);
    double bbCx = bb.origin.x + bb.size.width * 0.5, bbCy = bb.origin.y + bb.size.height * 0.5;
    double mid = (sw + (cw - pad)) * 0.5, leftC = MIN(mid, sw + bb.size.width * fit * 0.5);
    double targetCx = (bbCx - bb.size.width * 0.5 * fit > sw) ? bbCx : leftC;
    double s = 1.0 + progress * (fit - 1.0), dx = (targetCx - bbCx) * progress + 0.0;
    if (G1B_SendB0(self, @selector(isRTLEnabled))) dx = -dx;
    id item = G1C_Resp(layout, @selector(itemForLayoutRole:)) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
    CGPoint c = (item && G1C_Resp(model, @selector(centerForItem:))) ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(model, @selector(centerForItem:), item) : CGPointMake(bbCx, bbCy);
    frame.origin.x = (frame.origin.x - (1.0 - s) * (c.x - bbCx)) + dx;
    frame.origin.y = frame.origin.y - (1.0 - s) * (c.y - bbCy);
    return frame;
}
static double G1C_FS_RoleScale(id self, SEL _cmd, long long role, id layout) {          // 0x1c75c3360
    double scale = G1B_SUPER(double, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    if (G1C_FS_OnStage(self, layout)) {
        double fit, sw, pad, cw; CGRect bb; id model;
        if (G1C_FS_Squeeze(self, &fit, &bb, &model, &sw, &pad, &cw)) scale *= 1.0 + G1C_FS_Reveal(self) * (fit - 1.0);
    }
    return scale;
}
static id G1C_FS_Visible(id self, SEL _cmd) {                                           // 0x1c75c34c0
    id sup = G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL));
    NSSet *set = [sup isKindOfClass:[NSSet class]] ? sup : [NSSet set];
    id fs = G1C_FS_Layout(self);
    return fs ? [set setByAddingObject:fs] : set;
}
static id G1C_FS_CacheSnapshots(id self, SEL _cmd) { return [G1B_Send0(self, @selector(visibleAppLayouts)) allObjects] ?: @[]; }     // 0x1c75c353c
static id G1C_FS_CacheFullsize(id self, SEL _cmd) { return @[]; }                         // 0x1c75c3588
static id G1C_FS_TopMost(id self, SEL _cmd) {                                           // 0x1c75c4284
    id sup = G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL));
    id fs = G1C_FS_Layout(self);
    SEL ins = NSSelectorFromString(@"sb_arrayByInsertingOrMovingObject:toIndex:");
    id elems = ([sup respondsToSelector:ins] && fs) ? ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(sup, ins, fs, 0) : sup;
    id tongue = G1C_Resp(self, @selector(continuousExposeStripTongueBackdropCaptureLayoutElement)) ? G1B_Send0(self, @selector(continuousExposeStripTongueBackdropCaptureLayoutElement)) : nil;
    if (tongue && elems) {
        NSMutableArray *m = [elems mutableCopy];
        [m removeObject:fs]; [m insertObject:tongue atIndex:0]; [m insertObject:fs atIndex:0];
        elems = m;
    }
    return elems;
}
static G1CRadii G1C_FS_Corner(id self, SEL _cmd, unsigned long long i) {                // 0x1c75c3594
    id layout = G1C_LayoutAtIdx(self, i);
    if (G1C_FS_OnStage(self, layout)) {
        double r = G1B_Dbl0(self, @selector(displayCornerRadius));
        if (G1C_FloatEq(r, 0.0) && !G1C_FS_Maximized(self, layout)) r = G1B_Dbl0(G1C_Chamois(self), @selector(stageCornerRaddii));
        r = r / G1C_SendD0Q(self, @selector(scaleForIndex:), i);
        return (G1CRadii){ r, r, r, r };
    }
    return G1B_SUPER(G1CRadii, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static unsigned long long G1C_FS_Masked(id self, SEL _cmd, unsigned long long i) {       // 0x1c75c36a4
    id layout = G1C_LayoutAtIdx(self, i);
    if (G1C_FS_OnStage(self, layout)) return G1C_FS_Maximized(self, layout) ? 0 : 0xf;
    return G1B_SUPER(unsigned long long, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_FS_ShadowOpacity(id self, SEL _cmd, long long role, unsigned long long i) {   // 0x1c75c3750
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return 1.0;
    return G1B_SUPER(double, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, unsigned long long), role, i);
}
static G1CGrad G1C_FS_Gradient(id self, SEL _cmd, unsigned long long i) {                // 0x1c75c380c
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return (G1CGrad){ 0.0, 0.0 };     // SBSwitcherGradientWallpaperAttributesMakeEmpty
    return G1B_SUPER(G1CGrad, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_FS_TitleIcon(id self, SEL _cmd, unsigned long long i) {                // 0x1c75c38c0
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return 0.0;
    return G1B_SUPER(double, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_FS_Perspective(id self, SEL _cmd, id layout) {                         // 0x1c75c420c
    if (G1C_FS_OnStage(self, layout)) return 0.0;
    return G1B_SUPER(double, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), layout);
}
static BOOL G1C_FS_PinRoles(id self, SEL _cmd, unsigned long long i) {                   // 0x1c75c4498
    if (G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i))) return YES;
    return G1B_SUPER(BOOL, gFsSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static BOOL G1C_FS_AnchorPin(id self, SEL _cmd, unsigned long long i) { return !G1C_FS_OnStage(self, G1C_LayoutAtIdx(self, i)); }      // 0x1c75c4530
static BOOL G1C_FS_NO1(id self, SEL _cmd, id a) { return NO; }                           // isResizeGrabberVisible / shouldAllowGroupOpacity / shouldAccessoryDrawShadow ...
static double G1C_FS_HitTestOutset(id self, SEL _cmd, id a) { return 10.0; }             // 0x1c75c459c
// ---- touch / selection / resize ----
static BOOL G1C_FS_Occluded(id self, SEL _cmd, long long role, id layout) {              // 0x1c75c3e48
    id m = G1C_FS_Model(self, layout);
    id item = G1C_Resp(layout, @selector(itemForLayoutRole:)) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
    return G1B_SendB1(m, @selector(isItemFullyOccluded:), item) || G1B_SendB1(m, @selector(isItemPartiallyOccluded:), item) || G1B_SendB1(m, NSSelectorFromString(@"isItemCoveredByFullyOccludedPeekingItem:"), item);
}
static long long G1C_FS_Touch(id self, SEL _cmd, long long role, id layout) {            // 0x1c75c3974
    id item = G1C_Resp(layout, @selector(itemForLayoutRole:)) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
    if (G1B_SendB1(G1C_FS_Layout(self), @selector(containsItem:), item)) return G1C_FS_Occluded(self, 0, role, layout) ? 1 : 2;
    return G1B_SUPER(long long, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static BOOL G1C_FS_ResizingAllowed(id self, SEL _cmd, long long role, id layout) {       // 0x1c75c3a44
    return G1B_SendB1(self, @selector(appLayoutContainsOnlyResizableApps:), layout) && G1C_FloatEq(G1C_FS_Reveal(self), 0.0) && G1C_FS_OnStage(self, layout);
}
static BOOL G1C_FS_ShouldEnableGrabbers(id self, SEL _cmd, long long role, id layout) {  // 0x1c75c5288
    BOOL strip = !G1C_FloatEq(G1C_FS_Reveal(self), 0.0) && G1C_FS_Exceeds(self, 0);
    BOOL embedded = G1B_SendB0(self, @selector(isDisplayEmbedded));
    BOOL onStage = G1C_FS_OnStage(self, layout);
    BOOL resizable = G1B_SendB1(self, @selector(appLayoutContainsOnlyResizableApps:), layout);
    BOOL roleOK = G1C_Wdd_RoleValid(role);                                                 // _SBLayoutRoleIsValidForSplitView 0x1c7894a30: roles 1, 2 and 5..9 (every window of a stage of up to 4 windows), NOT only primary / side
    BOOL occluded = roleOK ? G1C_FS_Occluded(self, 0, role, layout) : NO;
    BOOL r = !strip && embedded && onStage && resizable && roleOK && !occluded;
    if (BP_LogEnabled()) {                                                                 // diagnostics: logged when the answer for a layout changes (resize corner dead after tapping a window)
        static __unsafe_unretained id lastLayout; static long long lastRole = -1; static int lastR = -1; static int n;
        if ((lastLayout != layout || lastRole != role || lastR != (int)r) && n < 300) {
            lastLayout = layout; lastRole = role; lastR = r; n++;
            BP_Log(@"g1c: resize grabbers enabled=%d role %lld: stripHides=%d embedded=%d onStage=%d resizable=%d roleOK=%d occluded=%d stage=%@ layout=%@", r, role, strip, embedded, onStage, resizable, roleOK, occluded, G1C_DbgLayout(G1C_FS_Layout(self)), G1C_DbgLayout(layout));
        }
    }
    return r;
}
static unsigned long long G1C_FS_ActiveCorners(id self, SEL _cmd, long long role, id layout) {   // 0x1c75c3aac
    if (!G1C_FS_ShouldEnableGrabbers(self, 0, role, layout)) return G1B_SUPER(unsigned long long, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    NSUInteger idx = [G1B_Send0(self, @selector(appLayouts)) indexOfObject:layout];
    if (idx == NSNotFound) return G1B_SUPER(unsigned long long, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    CGRect lf = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), idx);
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    CGRect rect = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(self, @selector(frameForLayoutRole:inAppLayout:withBounds:), role, layout, b);
    id cs = G1C_ChamoisSettings(self);
    double margin = G1B_Dbl0(cs, NSSelectorFromString(@"pinWindowEdgeForResizeMargin"));
    if (CGRectGetMaxX(rect) < CGRectGetWidth(lf) - margin) return 8;
    if (CGRectGetMaxY(rect) < CGRectGetHeight(lf) - margin) return 4;
    if (CGRectGetMinY(rect) > margin) return 4;
    if (CGRectGetMinX(rect) > margin) return 4;
    return G1C_RTL() ? 4 : 8;
}
static BOOL G1C_FS_ContentTouches(id self, SEL _cmd, long long role, id layout) {        // 0x1c75c3cf4
    if (!G1C_FS_OnStage(self, layout) || G1C_FS_RevealedFromHidden(self, 0)) return NO;
    return G1B_SUPER(BOOL, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static BOOL G1C_FS_Selectable(id self, SEL _cmd, long long role, id layout) {            // 0x1c75c3d84
    if (!G1C_FS_OnStage(self, layout) || G1C_FS_RevealedFromHidden(self, 0)) return YES;
    if (G1B_SUPER(BOOL, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout)) return YES;
    return G1C_FS_Occluded(self, 0, role, G1B_Send1(self, @selector(appLayoutContainingAppLayout:), layout));
}
static BOOL G1C_FS_SpringLoading(id self, SEL _cmd, long long role, id layout) {         // 0x1c75c4150
    return G1C_FS_OnStage(self, layout) ? G1C_FS_Occluded(self, 0, role, layout) : YES;
}
// ---- dock / home screen / status bar ----
static double G1C_FS_HomeDimming(id self, SEL _cmd) {                                    // 0x1c75c3f74
    CGRect cb = G1C_SendRect0(self, @selector(containerViewBounds));
    id m = G1C_FS_Model(self, G1C_FS_Layout(self));
    CGRect stage = G1C_Resp(m, NSSelectorFromString(@"stageArea")) ? G1C_SendRect0(m, NSSelectorFromString(@"stageArea")) : CGRectZero;
    double ratio = (stage.size.width * stage.size.height) / (cb.size.width * cb.size.height);
    double d = fmin(fmax(((ratio + -0.7) * 0.5) / 0.3 + 0.0, 0.0), 1.0);
    double strip = G1C_FS_StripProgress(self, 0);
    return d + (d * 0.5 - d) * strip;
}
static BOOL G1C_FS_StatusBar(id self, SEL _cmd) { return !G1C_FS_Maximized(self, G1C_FS_Layout(self)); }       // 0x1c75c4034
static BOOL G1C_FS_DockHidden(id self, SEL _cmd) {                                       // 0x1c75c405c
    id m = G1C_FS_Model(self, G1C_FS_Layout(self));
    double bbH = G1C_Resp(m, @selector(boundingBox)) ? G1C_SendRect0(m, @selector(boundingBox)).size.height : 0.0;
    double contH = G1C_SendRect0(self, @selector(containerViewBounds)).size.height;
    double dockH = G1B_Dbl0(self, @selector(floatingDockHeight)), top = G1B_Dbl0(self, NSSelectorFromString(@"floatingDockViewTopMargin"));
    if (G1B_SendB0(self, NSSelectorFromString(@"isSoftwareKeyboardVisible"))) return YES;
    if ((contH - bbH) < (dockH + top)) return YES;
    return G1B_SendB0(self, @selector(prefersDockHidden));
}
// 16.0 -shouldConfigureInAppDockVisibleAssertion (0x1c613f9a0) = !(_anyDisplayItemsExceedDock || isSoftwareKeyboardVisible). 16.2 removed it (the new VC consumer
// _updateFloatingDockBehaviorAssertion 0x1c745a058 uses wantsDockBehaviorAssertion / dockUpdateMode instead) but the 16.0 VC consumer that is still running
// (-_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext: 0x1c5fc8890) asks the root for both the hidden and the VISIBLE assertion: forwarding
// the visible one down the chain (no answer) dropped the in-app floating dock assertion -> the dock disappeared / reappeared on every window open / close.
static BOOL G1C_FS_DockVisible(id self, SEL _cmd) {
    id m = G1C_FS_Model(self, G1C_FS_Layout(self));
    double bbH = G1C_Resp(m, @selector(boundingBox)) ? G1C_SendRect0(m, @selector(boundingBox)).size.height : 0.0;
    double contH = G1C_SendRect0(self, @selector(containerViewBounds)).size.height;
    double dockH = G1B_Dbl0(self, @selector(floatingDockHeight)), top = G1B_Dbl0(self, NSSelectorFromString(@"floatingDockViewTopMargin"));
    BOOL exceed = (contH - bbH) < (dockH + top);
    return !(exceed || G1B_SendB0(self, NSSelectorFromString(@"isSoftwareKeyboardVisible")));
}
static BOOL G1C_FS_WantsDockAssertion(id self, SEL _cmd) { return !G1C_FS_DockHidden(self, 0); }               // 0x1c75c411c
static double G1C_FS_DockProgress(id self, SEL _cmd) { return 1.0; }                     // 0x1c75c4138
static long long G1C_FS_DockUpdateMode(id self, SEL _cmd) { return 3; }                  // 0x1c75c4140
static BOOL G1C_FS_HomeAffordance(id self, SEL _cmd, id layout) {                        // 0x1c75c43d4
    return G1C_FS_IsFullScreenLayout(self, 0, layout) && G1B_SendB0(self, @selector(isDisplayEmbedded)) && G1B_SendB0(G1B_Send0(self, @selector(homeGrabberSettings)), @selector(isEnabled));
}
static id G1C_FS_VisibleHomeAffordance(id self, SEL _cmd) {                              // 0x1c75c4430
    id fs = G1C_FS_Layout(self);
    return G1C_FS_HomeAffordance(self, 0, fs) ? [NSSet setWithObject:fs] : [NSSet set];
}
// ---- events ----
static id G1C_FS_Hover(id self, SEL _cmd, id event) {                                    // 0x1c75c462c
    id response = G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    if (G1C_FS_WantsHideHover(self, 0) && G1C_Resp(event, @selector(position))) {
        double x = G1C_SendPoint0(event, @selector(position)).x;
        id a = G1C_Chamois(self);
        double sw = G1B_Dbl0(a, @selector(stripWidth));
        if (x > sw + 0.0001 && x < G1C_SendRect0(self, @selector(containerViewBounds)).size.width - sw - 0.0001) {
            response = G1B_AppendTo(G1C_NewStripsPresentationResponse(0, 1), response);
            response = G1B_AppendTo(G1B_NewUpdateLayoutResponse(0xc, 3), response);
        }
    }
    return response;
}
static id G1C_FS_ActivateStageResponse(id self) {
    return G1C_NewPerformActivate(G1C_FS_Layout(self), NO);
}
static id G1C_FS_Tap(id self, SEL _cmd, id event) {                                       // 0x1c75c4780
    id response = G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    if (G1C_FS_GetTapFlag(self, 0) && !G1B_SendB0(event, @selector(isHandled))) {
        id tapped = G1B_Send0(event, @selector(appLayout));
        id fs = G1C_FS_Layout(self);
        if (G1C_FS_OnStage(self, tapped)) {
            if (G1C_FS_RevealedFromHidden(self, 0)) {
                response = G1B_AppendTo(G1C_NewStripsPresentationResponse(0, 1), response);
                response = G1B_AppendTo(G1C_FS_ActivateStageResponse(self), response);
            } else {
                long long role = G1B_SendLL0(event, @selector(layoutRole));
                id item = G1C_Resp(tapped, @selector(itemForLayoutRole:)) ? G1C_SendLL1(tapped, @selector(itemForLayoutRole:), role) : nil;
                id req = G1C_NewBareRequest();
                SEL bf = @selector(appLayoutByBringingItemToFront:inAppLayout:);
                id fronted = G1C_Resp(self, bf) ? G1C_Send2(self, bf, item, tapped) : nil;
                G1B_SendV1(req, @selector(setAppLayout:), fronted ?: tapped);
                G1B_SendV1(req, @selector(setActivatingDisplayItem:), item);
                if (G1C_Resp(event, @selector(source)) && G1B_SendLL0(event, @selector(source)) == 1) G1B_SendVLL(req, @selector(setSource:), 0x33);
                response = G1B_AppendTo(G1C_NewPerformFromRequest(req, NO), response);
            }
        } else {
            id req = G1C_NewBareRequest();
            G1B_SendV1(req, @selector(setAppLayout:), tapped);
            if (G1C_Resp(event, @selector(modifierFlags)) && (G1B_SendLL0(event, @selector(modifierFlags)) & (1 << 17))) G1B_SendVLL(req, NSSelectorFromString(@"setEntityInsertionPolicy:"), 1);
            if ([G1C_CEId(tapped) isEqualToString:G1C_CEId(fs)]) G1B_SendVLL(req, @selector(setSource:), 0x3f);
            response = G1B_AppendTo(G1C_NewPerformFromRequest(req, NO), response);
        }
        G1C_HandleEvent(event, @"Full Screen Continuous Expose");
    }
    return response;
}
static id G1C_FS_HeaderTap(id self, SEL _cmd, id event) {                                 // 0x1c75c4a28
    id response = G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    if (G1C_FS_GetHdrFlag(self, 0) && !G1B_SendB0(event, @selector(isHandled))) {
        id layout = G1B_Send0(event, @selector(appLayout));
        long long role = G1B_SendLL0(event, @selector(layoutRole));
        id item = G1C_Resp(layout, @selector(itemForLayoutRole:)) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
        id r = nil;
        if (G1B_SendB1(self, NSSelectorFromString(@"displayItemSupportsMultipleWindowsIndicator:"), item)) {
            id req = G1C_NewBareRequest();
            G1B_SendVLL(req, @selector(setSource:), 3);
            G1B_SendV1(req, @selector(setBundleIdentifierForAppExpose:), G1B_Send0(item, @selector(bundleIdentifier)));
            r = G1C_NewPerformFromRequest(req, NO);
        } else {
            Class pc = NSClassFromString(@"SBPulseDisplayItemSwitcherModifier"), cc = NSClassFromString(@"SBAddModifierSwitcherEventResponse");
            SEL ci = NSSelectorFromString(@"initWithModifier:level:");
            id pulse = (pc && [pc instancesRespondToSelector:@selector(initWithDisplayItem:)]) ? G1B_Send1([pc alloc], @selector(initWithDisplayItem:), item) : nil;
            r = (pulse && cc && [cc instancesRespondToSelector:ci]) ? ((id (*)(id, SEL, id, long long))objc_msgSend)([cc alloc], ci, pulse, 3) : nil;
        }
        response = G1B_AppendTo(r, response);
        G1C_HandleEvent(event, @"Full Screen Continuous Expose");
    }
    return response;
}
static id G1C_FS_TapOutside(id self, SEL _cmd, id event) {                                // 0x1c75c4bc0
    id response = G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    if (G1C_FS_RevealedFromHidden(self, 0)) {
        response = G1B_AppendTo(G1C_NewStripsPresentationResponse(0, 1), response);
        response = G1B_AppendTo(G1C_FS_ActivateStageResponse(self), response);
    }
    return response;
}
static id G1C_FS_SortedKeys(NSDictionary *map) {
    return [[map allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [@(G1C_SendD0(map[a], @selector(lastInteractionTime))) compare:@(G1C_SendD0(map[b], @selector(lastInteractionTime)))];
    }];
}
static id G1C_FS_Transition(id self, SEL _cmd, id event) {                               // 0x1c75c4cc8
    id response = G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    id from = G1B_Send0(event, @selector(fromAppLayout)), to = G1B_Send0(event, @selector(toAppLayout));
    if (G1B_SendLL0(event, @selector(phase)) == 2 && G1C_AsArray(G1B_Send0(to, @selector(allItems))).count > 2 && [from isEqual:to]) {
        BOOL kb = G1C_Resp(event, NSSelectorFromString(@"isKeyboardShortcutInitiated")) && G1B_SendB0(event, NSSelectorFromString(@"isKeyboardShortcutInitiated"));
        if (!kb) G1C_FS_ResetZ(self, 0);
        else {
            id lastFrom = [G1C_FS_SortedKeys(G1B_Send0(event, @selector(fromDisplayItemLayoutAttributesMap))) lastObject];
            id lastTo = [G1C_FS_SortedKeys(G1B_Send0(event, @selector(toDisplayItemLayoutAttributesMap))) lastObject];
            if (![lastFrom isEqual:lastTo]) {
                NSArray *z = G1B_GET(self, kFsZ);
                NSUInteger idx = NSNotFound;
                for (NSUInteger k = 0; k < z.count; k++) if (G1B_SendB1(z[k], @selector(containsItem:), lastFrom)) { idx = k; break; }
                if (z.count) {
                    NSUInteger next = (idx + 1) % z.count;
                    NSUInteger prev1 = ((NSInteger)idx > 0) ? idx : z.count;
                    BOOL reset;
                    if (G1B_SendB1(z[next], @selector(containsItem:), lastTo)) reset = NO;
                    else reset = !G1B_SendB1(z[prev1 - 1], @selector(containsItem:), lastTo);
                    if (reset) G1C_FS_ResetZ(self, 0);
                }
            }
        }
    }
    return response;
}
// 16.0-only protocol / event methods of the old inline strip: the strip child answers these in 16.2 -> plain pass-throughs to the chain
static id G1C_FS_Fwd0(id self, SEL _cmd) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL)) : nil; }
static id G1C_FS_Fwd1(id self, SEL _cmd, id a) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(id, gFsSuper, self, _cmd, (struct objc_super *, SEL, id), a) : nil; }
static CGPoint G1C_FS_FwdPoint(id self, SEL _cmd) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(CGPoint, gFsSuper, self, _cmd, (struct objc_super *, SEL)) : CGPointZero; }
static unsigned long long G1C_FS_FwdULL0(id self, SEL _cmd) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(unsigned long long, gFsSuper, self, _cmd, (struct objc_super *, SEL)) : 0; }
static unsigned long long G1C_FS_FwdULL2(id self, SEL _cmd, long long a, id b) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(unsigned long long, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id), a, b) : 0; }
static double G1C_FS_FwdOpacity(id self, SEL _cmd, long long a, id b, unsigned long long c) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(double, gFsSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), a, b, c) : 1.0; }
static BOOL G1C_FS_FwdBool0(id self, SEL _cmd) { return G1B_HasSuper(gFsSuper, _cmd) ? G1B_SUPER(BOOL, gFsSuper, self, _cmd, (struct objc_super *, SEL)) : NO; }

typedef struct { const char *sel; IMP imp; const char *types; } G1CPatch;
static void G1C_PatchClass(Class c, const G1CPatch *p, size_t n, const char *tag) {
    for (size_t i = 0; i < n; i++) {
        SEL s = sel_registerName(p[i].sel);
        Method m = class_getInstanceMethod(c, s);
        const char *t = m ? method_getTypeEncoding(m) : G1B_TypesFor(s, p[i].types);
        if (!t) t = p[i].types;
        class_replaceMethod(c, s, p[i].imp, t);
    }
    if (BP_LogEnabled()) BP_Log(@"%s: %zu methods converted to the 16.2 form on %s", tag, n, class_getName(c));
}
#define R4 "{CGRect={CGPoint=dd}{CGSize=dd}}"
static void G1C_InstallFullScreen(void) {
    gFsCls = NSClassFromString(@"SBFullScreenContinuousExposeSwitcherModifier");
    gFsSuper = gFsCls ? class_getSuperclass(gFsCls) : Nil;
    if (!gFsCls || !gStripCls || !BP_OnName("g1c_strip")) return;
    const G1CPatch p[] = {
        { "initWithFullScreenAppLayout:", (IMP)G1C_FS_Init, "@24@0:8@16" },
        { "highlightedByTouchAppLayouts", (IMP)G1C_FS_GetTouch, "@16@0:8" }, { "setHighlightedByTouchAppLayouts:", (IMP)G1C_FS_SetTouch, "v24@0:8@16" },
        { "highlightedByHoverAppLayouts", (IMP)G1C_FS_GetHover, "@16@0:8" }, { "setHighlightedByHoverAppLayouts:", (IMP)G1C_FS_SetHover, "v24@0:8@16" },
        { "handlesTapAppLayoutEvents", (IMP)G1C_FS_GetTapFlag, "B16@0:8" }, { "setHandlesTapAppLayoutEvents:", (IMP)G1C_FS_SetTapFlag, "v20@0:8B16" },
        { "handlesTapAppLayoutHeaderEvents", (IMP)G1C_FS_GetHdrFlag, "B16@0:8" }, { "setHandlesTapAppLayoutHeaderEvents:", (IMP)G1C_FS_SetHdrFlag, "v20@0:8B16" },
        { "continuousExposeStripProgress", (IMP)G1C_FS_StripProgress, "d16@0:8" },
        { "_continuousExposeStripRevealProgress", (IMP)G1C_FS_RevealProgress, "d16@0:8" },
        { "_isFullScreenAppLayout:", (IMP)G1C_FS_IsFullScreenLayout, "B24@0:8@16" },
        { "_isAppLayoutEffectivelyOnStage:", (IMP)G1C_FS_OnStageIMP, "B24@0:8@16" },
        { "_isStripRevealedFromHidden", (IMP)G1C_FS_RevealedFromHidden, "B16@0:8" },
        { "_continuousExposeStripEdge", (IMP)G1C_FS_StripEdge, "I16@0:8" },
        { "_anyItemExceedsWidthThresholdToHideStrip", (IMP)G1C_FS_Exceeds, "B16@0:8" },
        { "_wantsContinuousExposeHoverGestureForDismissingStrip", (IMP)G1C_FS_WantsHideHover, "B16@0:8" },
        { "wantsContinuousExposeHoverGesture", (IMP)G1C_FS_WantsHover, "B16@0:8" },
        { "_resetKeyboardNavigationZOrder", (IMP)G1C_FS_ResetZ, "v16@0:8" },
        { "activeLeafAppLayoutsReachableByKeyboardShortcut", (IMP)G1C_FS_ActiveLeafs, "@16@0:8" },
        { "canSelectLeafWithModifierKeysInAppLayout:", (IMP)G1C_FS_CanSelectLeaf, "B24@0:8@16" },
        { "frameForIndex:", (IMP)G1C_FS_Frame, R4 "24@0:8Q16" }, { "anchorPointForIndex:", (IMP)G1C_FS_Anchor, "{CGPoint=dd}24@0:8Q16" }, { "scaleForIndex:", (IMP)G1C_FS_Scale, "d24@0:8Q16" },
        { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1C_FS_AccFrame, R4 "56@0:8" R4 "16@48" },
        { "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (IMP)G1C_FS_AccAnchor, "{CGPoint=dd}40@0:8{CGPoint=dd}16@32" },
        { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_FS_RoleFrame, R4 "64@0:8q16@24" R4 "32" },
        { "scaleForLayoutRole:inAppLayout:", (IMP)G1C_FS_RoleScale, "d32@0:8q16@24" },
        { "visibleAppLayouts", (IMP)G1C_FS_Visible, "@16@0:8" }, { "appLayoutsToCacheSnapshots", (IMP)G1C_FS_CacheSnapshots, "@16@0:8" },
        { "appLayoutsToCacheFullsizeSnapshots", (IMP)G1C_FS_CacheFullsize, "@16@0:8" }, { "topMostLayoutElements", (IMP)G1C_FS_TopMost, "@16@0:8" },
        { "cornerRadiiForIndex:", (IMP)G1C_FS_Corner, "{UIRectCornerRadii=dddd}24@0:8Q16" }, { "maskedCornersForIndex:", (IMP)G1C_FS_Masked, "Q24@0:8Q16" },
        { "shadowOpacityForLayoutRole:atIndex:", (IMP)G1C_FS_ShadowOpacity, "d32@0:8q16Q24" },
        { "wallpaperGradientAttributesForIndex:", (IMP)G1C_FS_Gradient, "{SBSwitcherGradientWallpaperAttributes=dd}24@0:8Q16" },
        { "titleAndIconOpacityForIndex:", (IMP)G1C_FS_TitleIcon, "d24@0:8Q16" }, { "perspectiveAngleForAppLayout:", (IMP)G1C_FS_Perspective, "d24@0:8@16" },
        { "shouldPinLayoutRolesToSpace:", (IMP)G1C_FS_PinRoles, "B24@0:8Q16" }, { "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)G1C_FS_AnchorPin, "B24@0:8Q16" },
        { "shouldAllowGroupOpacityForAppLayout:", (IMP)G1C_FS_NO1, "B24@0:8@16" }, { "spaceAccessoryViewIconHitTestOutsetForAppLayout:", (IMP)G1C_FS_HitTestOutset, "d24@0:8@16" },
        { "isResizeGrabberVisibleForAppLayout:", (IMP)G1C_FS_NO1, "B24@0:8@16" },
        { "_layoutRoleIsOccluded:inAppLayout:", (IMP)G1C_FS_Occluded, "B32@0:8q16@24" }, { "touchBehaviorForLayoutRole:inAppLayout:", (IMP)G1C_FS_Touch, "q32@0:8q16@24" },
        { "isItemResizingAllowedForLayoutRole:inAppLayout:", (IMP)G1C_FS_ResizingAllowed, "B32@0:8q16@24" },
        { "_shouldEnableItemResizeGrabbersForLayoutRole:inAppLayout:", (IMP)G1C_FS_ShouldEnableGrabbers, "B32@0:8q16@24" },
        { "activeCornersForTouchResizeForLayoutRole:inAppLayout:", (IMP)G1C_FS_ActiveCorners, "Q32@0:8q16@24" },
        { "shouldAllowContentViewTouchesForLayoutRole:inAppLayout:", (IMP)G1C_FS_ContentTouches, "B32@0:8q16@24" },
        { "isLayoutRoleSelectable:inAppLayout:", (IMP)G1C_FS_Selectable, "B32@0:8q16@24" },
        { "isLayoutRoleEligibleForContentDragSpringLoading:inAppLayout:", (IMP)G1C_FS_SpringLoading, "B32@0:8q16@24" },
        { "homeScreenDimmingAlpha", (IMP)G1C_FS_HomeDimming, "d16@0:8" }, { "isContainerStatusBarVisible", (IMP)G1C_FS_StatusBar, "B16@0:8" },
        { "shouldConfigureInAppDockHiddenAssertion", (IMP)G1C_FS_DockHidden, "B16@0:8" }, { "wantsDockBehaviorAssertion", (IMP)G1C_FS_WantsDockAssertion, "B16@0:8" },
        { "dockProgress", (IMP)G1C_FS_DockProgress, "d16@0:8" }, { "dockUpdateMode", (IMP)G1C_FS_DockUpdateMode, "q16@0:8" },
        { "isHomeAffordanceSupportedForAppLayout:", (IMP)G1C_FS_HomeAffordance, "B24@0:8@16" }, { "visibleHomeAffordanceLayoutElements", (IMP)G1C_FS_VisibleHomeAffordance, "@16@0:8" },
        { "handleHoverEvent:", (IMP)G1C_FS_Hover, "@24@0:8@16" }, { "handleTapAppLayoutEvent:", (IMP)G1C_FS_Tap, "@24@0:8@16" },
        { "handleTapAppLayoutHeaderEvent:", (IMP)G1C_FS_HeaderTap, "@24@0:8@16" }, { "handleTapOutsideToDismissEvent:", (IMP)G1C_FS_TapOutside, "@24@0:8@16" },
        { "handleTransitionEvent:", (IMP)G1C_FS_Transition, "@24@0:8@16" },
        // 16.0-only members that would shadow the strip child
        { "scrollViewContentOffset", (IMP)G1C_FS_FwdPoint, "{CGPoint=dd}16@0:8" }, { "numberOfRowsInGridSwitcher", (IMP)G1C_FS_FwdULL0, "Q16@0:8" },
        { "continuousExposeIdentifiers", (IMP)G1C_FS_Fwd0, "@16@0:8" }, { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_FS_FwdOpacity, "d40@0:8q16@24Q32" },
        { "hiddenContentStatusBarPartsForLayoutRole:inAppLayout:", (IMP)G1C_FS_FwdULL2, "Q32@0:8q16@24" }, { "shouldConfigureInAppDockVisibleAssertion", (IMP)G1C_FS_DockVisible, "B16@0:8" },
        { "handleEvent:", (IMP)G1C_FS_Fwd1, "@24@0:8@16" }, { "handleTimerEvent:", (IMP)G1C_FS_Fwd1, "@24@0:8@16" },
        { "handleHighlightEvent:", (IMP)G1C_FS_Fwd1, "@24@0:8@16" }, { "handleSwitcherSettingsChangedEvent:", (IMP)G1C_FS_Fwd1, "@24@0:8@16" },
    };
    G1C_PatchClass(gFsCls, p, sizeof p / sizeof p[0], "strip");
}
// ============================================================================================================
// 1i  SBHomeScreenContinuousExposeSwitcherModifier  (16.2 form: SBHomeScreenSwitcherModifier child + the Strip child)                 PORTED
// ============================================================================================================
// init 0x1c77f3898 (children: SBHomeScreenSwitcherModifier, then the Strip), continuousExposeStripProgress 0.0 (0x1c77f3e60), isResizeGrabberVisibleForAppLayout: NO,
// responseForProposedChildResponse:childModifier:event: 0x1c77f393c (+ transformer block 0x1c77f3a6c). Converted in place like the FullScreen floor; the members 16.2 removed
// (appLayoutsToCacheSnapshots, topMostLayoutElements, dimmingAlphaForLayoutRole:inAppLayout:, scrollViewContentOffset) become pass-throughs, the strip child answers them.
static Class gHsParent, gSbSwitcherModifierCls;
static char kHsStrip, kHsHome;
static id G1C_Hs_Init(id self, SEL _cmd) {
    id me = G1B_SUPER(id, gSbSwitcherModifierCls, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    Class hc = NSClassFromString(@"SBHomeScreenSwitcherModifier");
    id home = hc ? [[hc alloc] init] : nil;
    if (home) { G1C_SetIvarObj(me, "_homeScreenModifier", home); G1B_SET(me, kHsHome, home); G1B_SendV1(me, @selector(addChildModifier:), home); }
    id strip = gStripCls ? [[gStripCls alloc] init] : nil;
    if (strip) { G1C_SetIvarObj(me, "_stripModifier", strip); G1B_SET(me, kHsStrip, strip); G1B_SendV1(me, @selector(addChildModifier:), strip); }
    return me;
}
static double G1C_Hs_Dimming(id self, SEL _cmd, long long role, id layout) { return G1B_HasSuper(gSbSwitcherModifierCls, _cmd) ? G1B_SUPER(double, gSbSwitcherModifierCls, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout) : 0.0; }
static double G1C_Hs_StripProgress(id self, SEL _cmd) { return 0.0; }
static BOOL G1C_Hs_Grabber(id self, SEL _cmd, id layout) { return NO; }
// the peek-end transformer: a type-31 (add modifier) response of the transition that ends a peek is replaced by the matching zoom / app-to-app transition (level 3)
static id G1C_Hs_Transform(id self, id event, id resp) {
    if (G1B_SendLL0(resp, @selector(type)) != 0x1f) return resp;
    id mod = G1B_Send0(resp, @selector(modifier));
    Class izc = NSClassFromString(@"SBFullScreenToHomeIconZoomSwitcherModifier"), a2a = NSClassFromString(@"SBContinuousExposeAppToAppModifier");
    id newMod = nil;
    id tid = G1B_Send0(event, @selector(transitionID));
    if (izc && mod && [mod isKindOfClass:izc]) {
        id layout = G1B_Send0(mod, @selector(appLayout));
        id from = G1B_Send0(event, @selector(fromAppLayout));
        id filtered = nil;
        if (G1C_Resp(layout, @selector(appLayoutWithItemsPassingTest:))) {
            BOOL (^pass)(id) = ^BOOL(id item) { return !G1B_SendB1(from, @selector(containsItem:), item); };
            filtered = ((id (*)(id, SEL, id))objc_msgSend)(layout, @selector(appLayoutWithItemsPassingTest:), pass);
        }
        CGRect frame = CGRectNull;
        if (filtered && !G1B_SendB0(event, NSSelectorFromString(@"isIconZoomDisabled")) && G1C_Resp(self, NSSelectorFromString(@"homeScreenIconFrameForAppLayout:")))
            frame = ((CGRect (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"homeScreenIconFrameForAppLayout:"), filtered);
        if (!CGRectIsNull(frame)) {
            SEL ii = NSSelectorFromString(@"initWithTransitionID:appLayout:direction:");
            if ([izc instancesRespondToSelector:ii]) {
                newMod = ((id (*)(id, SEL, id, id, long long))objc_msgSend)([izc alloc], ii, tid, filtered, 0);
                G1B_SendVLL(newMod, NSSelectorFromString(@"setShouldForceDefaultAnchorPointForTransition:"), 1);
                id loc = G1C_Resp(self, NSSelectorFromString(@"homeScreenIconLocationForAppLayout:")) ? G1B_Send1(self, NSSelectorFromString(@"homeScreenIconLocationForAppLayout:"), filtered) : nil;
                static BOOL (*contains)(id, id); static dispatch_once_t once;
                dispatch_once(&once, ^{ contains = (BOOL (*)(id, id))dlsym(RTLD_DEFAULT, "SBIconLocationGroupContainsLocation"); });
                void *grp = dlsym(RTLD_DEFAULT, "SBIconLocationGroupRoot");           // global NSSet of root locations (0x1d840bbc8)
                BOOL upd = (contains && grp && loc) ? contains((__bridge id)*(void **)grp, loc) : YES;
                G1B_SendVLL(newMod, NSSelectorFromString(@"setShouldUpdateIconViewVisibility:"), upd);
            }
        }
    }
    if (!newMod && a2a) {
        SEL ai = NSSelectorFromString(@"initWithTransitionID:fromAppLayout:fromInterfaceOrientation:toAppLayout:toInterfaceOrientation:fromDisplayItemLayoutAttributesMap:toDisplayItemLayoutAttributesMap:");
        if ([a2a instancesRespondToSelector:ai])
            newMod = ((id (*)(id, SEL, id, id, long long, id, long long, id, id))objc_msgSend)([a2a alloc], ai, tid, G1B_Send0(event, @selector(fromAppLayout)), G1B_SendLL0(event, @selector(fromInterfaceOrientation)),
                        G1B_Send0(event, @selector(toAppLayout)), G1B_SendLL0(event, @selector(toInterfaceOrientation)), G1B_Send0(event, @selector(fromDisplayItemLayoutAttributesMap)), G1B_Send0(event, @selector(toDisplayItemLayoutAttributesMap)));
    }
    Class cc = NSClassFromString(@"SBAddModifierSwitcherEventResponse");
    SEL ci = NSSelectorFromString(@"initWithModifier:level:");
    if (!newMod || !cc || ![cc instancesRespondToSelector:ci]) return resp;
    return ((id (*)(id, SEL, id, long long))objc_msgSend)([cc alloc], ci, newMod, 3);
}
static id G1C_Hs_ChildResponse(id self, SEL _cmd, id proposed, id child, id event) {
    id r = G1B_SUPER(id, gSbSwitcherModifierCls, self, _cmd, (struct objc_super *, SEL, id, id, id), proposed, child, event);
    if (G1B_SendLL0(event, @selector(type)) == 1 && G1C_PeekIsValid(G1B_SendLL0(event, @selector(fromPeekConfiguration))) && !G1C_PeekIsValid(G1B_SendLL0(event, @selector(toPeekConfiguration)))
        && G1C_Resp(r, @selector(responseByTransformingResponseWithTransformer:))) {
        __unsafe_unretained id us = self;
        id (^tf)(id) = ^id(id resp) { return G1C_Hs_Transform(us, event, resp); };
        return ((id (*)(id, SEL, id))objc_msgSend)(r, @selector(responseByTransformingResponseWithTransformer:), tf);
    }
    return r;
}
static void G1C_InstallHomeScreen(void) {
    if (!gHsParent || !gStripCls || !BP_OnName("g1c_strip")) return;
    const G1CPatch p[] = {
        { "init", (IMP)G1C_Hs_Init, "@16@0:8" },
        { "continuousExposeStripProgress", (IMP)G1C_Hs_StripProgress, "d16@0:8" },
        { "isResizeGrabberVisibleForAppLayout:", (IMP)G1C_Hs_Grabber, "B24@0:8@16" },
        { "responseForProposedChildResponse:childModifier:event:", (IMP)G1C_Hs_ChildResponse, "@40@0:8@16@24@32" },
        { "appLayoutsToCacheSnapshots", (IMP)G1C_FS_Fwd0, "@16@0:8" }, { "topMostLayoutElements", (IMP)G1C_FS_Fwd0, "@16@0:8" },
        { "scrollViewContentOffset", (IMP)G1C_FS_FwdPoint, "{CGPoint=dd}16@0:8" },
    };
    gSbSwitcherModifierCls = NSClassFromString(@"SBSwitcherModifier");
    G1C_PatchClass(gHsParent, p, sizeof p / sizeof p[0], "strip(home)");
    // dimmingAlphaForLayoutRole:inAppLayout: (double, q @) has a different shape
    SEL ds = NSSelectorFromString(@"dimmingAlphaForLayoutRole:inAppLayout:");
    Method dm = class_getInstanceMethod(gHsParent, ds);
    if (dm) class_replaceMethod(gHsParent, ds, (IMP)G1C_Hs_Dimming, method_getTypeEncoding(dm));
}
// 16.0-only members that 16.2 removed from the Root and Inline floors (the strip / the VC answer them now): pass-through to the superclass so they stop shadowing the chain.
static void G1C_ForwardRemoved(Class c, const char *selName, BOOL boolShape) {
    SEL s = sel_registerName(selName);
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    Class sup = c ? class_getSuperclass(c) : Nil;
    if (!m) return;
    Method sm = class_getInstanceMethod(sup, s);
    if (sm && method_getImplementation(sm) == method_getImplementation(m)) return;            // inherited, not defined here
    IMP imp;
    if (boolShape) imp = imp_implementationWithBlock(^BOOL(__unsafe_unretained id me, long long role, id layout) {
        if (!sm) return NO;
        struct objc_super sp = { me, sup };
        return ((BOOL (*)(struct objc_super *, SEL, long long, id))objc_msgSendSuper)(&sp, s, role, layout);
    });
    else imp = imp_implementationWithBlock(^id(__unsafe_unretained id me, id a) {
        if (!sm) return nil;
        struct objc_super sp = { me, sup };
        return ((id (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sp, s, a);
    });
    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
}
static void G1C_InstallRemovedForwarders(void) {
    if (!gStripCls || !BP_OnName("g1c_strip")) return;
    Class root = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier"), inl = NSClassFromString(@"SBInlineAppExposeContinuousExposeSwitcherModifier");
    G1C_ForwardRemoved(root, "appLayoutsForContinuousExposeIdentifier:", NO);
    G1C_ForwardRemoved(root, "adjustedAppLayoutsForAppLayouts:", NO);
    G1C_ForwardRemoved(root, "adjustedContinuousExposeIdentifiersForIdentifiers:", NO);
    G1C_ForwardRemoved(inl, "adjustedContinuousExposeIdentifiersForIdentifiers:", NO);
    G1C_ForwardRemoved(inl, "shouldSuppressHighlightEffectForLayoutRole:inAppLayout:", YES);
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
            { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_Inl_FrameForRole, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32" },
            { "scaleForLayoutRole:inAppLayout:", (IMP)G1C_Inl_ScaleForRole, "d32@0:8q16@24" },
            { "_scaleForActiveAppLayoutLeafAppLayouts", (IMP)G1C_Inl_ScaleActive, "d16@0:8" },
            { "_inlineAppExposeAppLayouts", (IMP)G1C_Inl_InlineLayouts, "@16@0:8" },
            { "homeScreenDimmingAlpha", (IMP)G1C_Inl_HomeDim, "d16@0:8" },
            { "_canShowReopenClosedWindowsButton", (IMP)G1C_Inl_CanShowSel, "B16@0:8" },
            { "spaceAccessoryViewIconHitTestOutsetForAppLayout:", (IMP)G1C_Inl_IconOutset, "d24@0:8@16" },
            { "appExposeAccessoryButtonsBundleIdentifier", (IMP)G1C_Inl_AccBundle, "@16@0:8" },
            { "appExposeAccessoryButtonsOverrideUserInterfaceStyle", (IMP)G1C_Inl_AccStyle, "q16@0:8" },
            { "plusButtonAlpha", (IMP)G1C_Inl_PlusAlpha, "d16@0:8" },
            { "plusButtonStyle", (IMP)G1C_Inl_PlusStyle, "Q16@0:8" },
        };
        gInlGrand = class_getSuperclass(gInlParent);
        gInlCls = G1B_MakeClass("BP162InlineAppExposeContinuousExposeSwitcherModifier", gInlParent, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    return gInlCls != Nil;
}
static id G1C_NewInlineAppExpose(id activeLayout, NSString *bundleID) {
    Class c = gInlCls ?: gInlParent;
    SEL s = NSSelectorFromString(@"initWithActiveAppLayout:appExposeBundleIdentifier:");
    if (!c || ![c instancesRespondToSelector:s]) return nil;
    return G1C_Send2([c alloc], s, activeLayout, bundleID);
}
static id G1C_NewHomeModifier(void) {
    return gHsParent ? [[gHsParent alloc] init] : nil;
}

// ============================================================================================================
// 1a  SBAppSwitcherContinuousExposeSwitcherModifier  (the Stage Manager "all windows" switcher)
//     BP162AppSwitcherContinuousExposeSwitcherModifier : SBAppSwitcherContinuousExposeSwitcherModifier (16.0)
//     Behaviour layer (tap / header tap / tap outside / removal / flags / resign-active / pile opacity): DONE.
//     Pile layout (g1c_piles, ON by default; kill switch Backport162.off.g1c_piles): 16.2 buildLayoutCalculationsForCache: 0x1c7812acc (G1C_As_Build) and
//     every 16.0 AppSwitcherCE query that used the 16.0 grid maths is overridden so that frames, scales, role frames, anchor, visible set, scroll range
//     and scroll targets all come from ONE cache (review B2):
//       frameForIndex: 0x1c780fe78, scaleForIndex: 0x1c780ff80, frameForLayoutRole:inAppLayout:withBounds: 0x1c780fe84, anchorPointForIndex: (16.2: not
//       overridden -> DefaultImplementations 0x1c788b08c = (0.5,0.5); 16.0 returned the pile-stack anchor 0x1c636a844 and shifted the frame by -0.5*scale*w),
//       visibleAppLayouts 0x1c7810118 (+ _visiblePileIdentifiers 0x1c781345c), 16.0 visibleSpaceRangeForContentOffset: (feeds snapshot caching / leading
//       index; it was the 16.0 column maths), _contentSize 0x1c78124c8, _fittedContentSize 0x1c7812504, contentOffsetForIndex:alignment: 0x1c7812518.
//     Layout direction (verified 0x1c7812acc): LTR lays the first pile at the RIGHT end of the content (cursor starts at -hEdge, piles extend leftwards,
//     everything is shifted by the content width afterwards), RTL starts at hEdge at the LEFT and extends rightwards; two rows by pile parity, each row has
//     its own cursor. The 16.0 maths agrees (RTL: index grows with x; LTR: index 0 at the right end).
//     The persistent switcher floor is the same class (16.2 Root multitaskingModifierForEvent: 0x1c7818560 == 16.0 0x1c63711ec: `multitaskingModifier ?:
//     [AppSwitcherCE new]`; G1C hooks it, see G1C_NewAppSwitcherFloorModifier) so the layout does not jump between the gesture and the floor.
// ============================================================================================================
static Class gAsParent, gAsCls;
static char kAsCalc, kAsToken;

static BOOL G1C_PilesOn(void) { return G1C_ON() && BP_On(F_G1C_PILES); }     // kill switch: Backport162.off.g1c_piles (every override below is then an exact [super])
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
// Layout cache = the 16.2 _appLayoutLayoutCalculationsCache + _cachedPileBoundingFrameByPileIdentifier + _cachedFittedContentSize:
//   @"frames" appLayout -> NSValue(CGRect)  card at its compacted size, centred on the scaled card, content coordinates, scroll offset NOT applied
//   @"srects" appLayout -> NSValue(CGRect)  the scaled card (the `frame` of the 16.2 calculation object)
//   @"scales" appLayout -> NSNumber         the `scale` of the 16.2 calculation object
//   @"piles"  identifier -> NSValue(CGRect) union of the pile's scaled card rects (CGRectZero when empty)
//   @"ids"    identifiers in layout order;  @"fitted" NSValue(CGSize)
// Exact port of 0x1c7812acc (see the section header for the direction): per pile parity one cursor; a pile's cards are anchored at the cursor (k = 0) and
// each further card is pushed `peek` beyond the previous card's far edge but never past the previous anchor; the cursor then moves to the far edge of the
// last card that counts as visible (k < numberOfVisibleItemsPerGroup) plus the inter-item spacing.
static NSDictionary *G1C_As_Build(id self) {
    NSMutableDictionary *frames = [NSMutableDictionary dictionary], *srects = [NSMutableDictionary dictionary], *scales = [NSMutableDictionary dictionary], *piles = [NSMutableDictionary dictionary];
    id ca = G1B_Send0(self, @selector(chamoisLayoutAttributes));
    double pad = G1B_Dbl0(ca, @selector(screenEdgePadding)), hEdge = G1B_Dbl0(ca, NSSelectorFromString(@"switcherHorizontalEdgeSpacing")),
           hInter = G1B_Dbl0(ca, NSSelectorFromString(@"switcherHorizontalInterItemSpacing")), vEdge = G1B_Dbl0(ca, NSSelectorFromString(@"switcherVerticalEdgeSpacing")),
           vInter = G1B_Dbl0(ca, NSSelectorFromString(@"switcherVerticalInterItemSpacing")), peek = G1B_Dbl0(ca, NSSelectorFromString(@"switcherPileCardMinimumPeekAmount"));
    long long rows = G1C_Resp(self, NSSelectorFromString(@"numberOfRowsInGridSwitcher")) ? G1B_SendLL0(self, NSSelectorFromString(@"numberOfRowsInGridSwitcher")) : 1;
    if (rows < 1) rows = 1;
    id sw = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id cs = G1C_Resp(sw, @selector(chamoisSettings)) ? G1B_Send0(sw, @selector(chamoisSettings)) : nil;
    unsigned long long nVis = (cs && [cs respondsToSelector:@selector(numberOfVisibleItemsPerGroup)]) ? (unsigned long long)G1B_SendLL0(cs, @selector(numberOfVisibleItemsPerGroup)) : 3;
    BOOL rtl = G1C_Resp(self, @selector(isRTLEnabled)) && G1B_SendB0(self, @selector(isRTLEnabled));
    CGRect vb = G1C_SendRect0(self, @selector(switcherViewBounds));
    double containerH = G1C_Resp(self, @selector(containerViewBounds)) ? G1C_SendRect0(self, @selector(containerViewBounds)).size.height : vb.size.height;    // fitted height = [super containerViewBounds].size.height
    double cardH = G1C_As_CardHeight(self);
    NSArray *ids = G1C_Resp(self, @selector(continuousExposeIdentifiersInSwitcher)) ? G1C_AsArray(G1B_Send0(self, @selector(continuousExposeIdentifiersInSwitcher))) : @[];
    SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:"), om = NSSelectorFromString(@"overlappingModelForAppLayout:");
    const double A = rtl ? hEdge : -hEdge, B = rtl ? -hInter : hInter;                  // LTR: cursor starts at -hEdge and moves left; RTL: starts at +hEdge and moves right
    double cursor[2] = { A, A };
    const double rowTop[2] = { pad + vEdge, pad + vEdge + vInter + cardH };
    NSUInteger pi = 0;
    for (id ident in ids) {
        const int par = rows >= 2 ? (int)(pi & 1) : 0;                                  // 16.2 hard-codes two rows by pile parity (tst x28,#1); with one row (not seen) a single cursor avoids overlap
        const double cur = cursor[par];
        const double cy = rowTop[par] + cardH / 2.0;
        NSArray *ls = G1C_Resp(self, byId) ? G1C_AsArray(G1B_Send1(self, byId, ident)) : @[];
        CGRect acc = CGRectNull;
        double anchor = cur, prevEdge = cur, lastVisEdge = cur;
        NSUInteger k = 0;
        for (id l in ls) {
            id model = G1C_Resp(self, om) ? G1B_Send1(self, om, l) : nil;
            CGSize sz = (model && [model respondsToSelector:@selector(compactedBoundingBox)]) ? G1C_SendRect0(model, @selector(compactedBoundingBox)).size : CGSizeZero;
            if (sz.height <= 0 || sz.width <= 0) { k++; continue; }                     // (16.2 has no guard; a model-less layout would give NaN there)
            double s = cardH / sz.height + (double)k * -0.01;                          // const 0x1c7a916c0 = -0.01 per stacked card
            double w = sz.width * s, h = sz.height * s;
            if (k != 0) anchor = rtl ? MAX(anchor, prevEdge + peek - w) : MIN(anchor, prevEdge - peek + w);
            double cx = rtl ? anchor + w / 2.0 : anchor - w / 2.0;
            CGRect r = CGRectMake(cx - w / 2.0, cy - h / 2.0, w, h);
            frames[l] = [NSValue valueWithCGRect:CGRectMake(cx - sz.width / 2.0, cy - sz.height / 2.0, sz.width, sz.height)];
            srects[l] = [NSValue valueWithCGRect:r];
            scales[l] = @(s);
            prevEdge = rtl ? CGRectGetMaxX(r) : CGRectGetMinX(r);
            if (k < nVis) lastVisEdge = prevEdge;
            acc = CGRectUnion(acc, r);
            k++;
        }
        if (ident) piles[ident] = [NSValue valueWithCGRect:CGRectIsNull(acc) ? CGRectZero : acc];
        cursor[par] = lastVisEdge - B;
        pi++;
    }
    double m = rtl ? MAX(cursor[0], cursor[1]) : MIN(cursor[0], cursor[1]);
    double fittedW = (hEdge - hInter) + (rtl ? m : -m);
    if (!rtl) {                                                                         // LTR: shift everything right by _contentSize.width (= max(fitted, view width))
        double dx = MAX(fittedW, vb.size.width);
        for (id key in [frames allKeys]) { CGRect f = [frames[key] CGRectValue]; f.origin.x += dx; frames[key] = [NSValue valueWithCGRect:f]; }
        for (id key in [srects allKeys]) { CGRect f = [srects[key] CGRectValue]; f.origin.x += dx; srects[key] = [NSValue valueWithCGRect:f]; }
        for (id key in [piles allKeys]) { CGRect f = [piles[key] CGRectValue]; f.origin.x += dx; piles[key] = [NSValue valueWithCGRect:f]; }
    }
    return @{ @"frames": frames, @"srects": srects, @"scales": scales, @"piles": piles, @"ids": ids, @"fitted": [NSValue valueWithCGSize:CGSizeMake(fittedW, containerH)] };
}
// nil when the modifier cannot answer the protocol queries: the ToHome / HomeToGrid transitions hold detached copies (no delegate at the end of the query chain),
// where the first query raises "couldn't find implementor for ...". Every caller then takes its 16.0 [super] path.
static NSDictionary *G1C_As_Calc(id self) {
    @try {
        NSString *tok = G1C_As_Token(self);
        NSDictionary *c = G1B_GET(self, kAsCalc);
        if (c && [G1B_GET(self, kAsToken) isEqualToString:tok]) return c;
        c = G1C_As_Build(self);
        G1B_SET(self, kAsCalc, c);
        G1B_SET(self, kAsToken, tok);
        return c;
    } @catch (NSException *e) {
        static BOOL logged;
        if (!logged && BP_LogEnabled()) { logged = YES; BP_Log(@"piles: detached switcher copy (%@), using the 16.0 layout for it", e.reason); }
        return nil;
    }
}
static id G1C_As_LayoutAt(id self, unsigned long long i) { NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil; return i < ls.count ? ls[i] : nil; }
// ---- everything below answers from the cache above when piles are on and the layout was laid out; otherwise it is the 16.0 [super] ----
static double G1C_As_ScrollX(id self) { return G1C_Resp(self, @selector(scrollViewContentOffset)) ? G1C_SendPoint0(self, @selector(scrollViewContentOffset)).x : 0.0; }
// 16.2 -_frameForIndex:withScaleApplied:scrollOffsetApplied: 0x1c78135dc. NO when the layout has no pile calculation.
static BOOL G1C_As_Frame(id self, unsigned long long i, BOOL scaled, BOOL scroll, CGRect *out) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    id l = c ? G1C_As_LayoutAt(self, i) : nil;
    NSValue *v = l ? c[scaled ? @"srects" : @"frames"][l] : nil;
    if (!v) return NO;
    CGRect f = [v CGRectValue];
    if (scroll) f.origin.x -= G1C_As_ScrollX(self);
    *out = f;
    return YES;
}
static CGRect G1C_As_FrameForIndex(id self, SEL _cmd, unsigned long long i) {            // 0x1c780fe78: withScaleApplied:NO scrollOffsetApplied:YES
    CGRect f;
    if (G1C_As_Frame(self, i, NO, YES, &f)) return f;
    return G1B_SUPER(CGRect, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_As_ScaleForIndex(id self, SEL _cmd, unsigned long long i) {            // 0x1c780ff80
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    id l = c ? G1C_As_LayoutAt(self, i) : nil;
    NSNumber *v = l ? c[@"scales"][l] : nil;
    return v ? v.doubleValue : G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
// 16.2 has no override: the DefaultImplementations answer (0.5, 0.5). The 16.0 override returns a pile-stack anchor (0.0 for a single window) and its
// frameForIndex: compensates with -0.5*scale*w, which the pile frames above do not do.
static CGPoint G1C_As_Anchor(id self, SEL _cmd, unsigned long long i) {
    CGRect f;
    if (G1C_As_Frame(self, i, NO, NO, &f)) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
// 16.2 0x1c780fe84: a window sits at compactedCenterForItem - compactedBoundingBox.origin with sizeForItem (the card canvas is the compacted bounding box);
// UIRectCenteredAboutPointScale(SBRectWithSize(size), center, screenScale) rounds the origin to the screen scale (0x1893a3324). `bounds` is ignored by 16.2.
// 16.0 0x1c636a5a8 positioned the window on a container-sized canvas.
static CGRect G1C_As_FrameForRole(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    NSDictionary *c = (layout && G1C_PilesOn()) ? G1C_As_Calc(self) : nil;
    SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:"), cc = NSSelectorFromString(@"compactedCenterForItem:"), sf = NSSelectorFromString(@"sizeForItem:");
    id item = (c[@"frames"][layout] && G1C_Resp(layout, @selector(itemForLayoutRole:))) ? G1C_SendLL1(layout, @selector(itemForLayoutRole:), role) : nil;
    id model = (item && G1C_Resp(self, om)) ? G1B_Send1(self, om, layout) : nil;
    if (!model || !G1C_Resp(model, cc) || !G1C_Resp(model, sf) || !G1C_Resp(model, @selector(compactedBoundingBox)))
        return G1B_SUPER(CGRect, gAsParent, self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds);
    CGPoint ctr = ((CGPoint (*)(id, SEL, id))objc_msgSend)(model, cc, item);
    CGRect box = G1C_SendRect0(model, @selector(compactedBoundingBox));
    CGSize size = ((CGSize (*)(id, SEL, id))objc_msgSend)(model, sf, item);
    double sc = G1B_Dbl0(self, @selector(screenScale));
    return CGRectMake(G1C_RoundForScale(ctr.x - box.origin.x - size.width / 2.0, sc), G1C_RoundForScale(ctr.y - box.origin.y - size.height / 2.0, sc), size.width, size.height);
}
static CGSize G1C_As_Fitted(id self, SEL _cmd) {                                          // 0x1c7812504
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (c) return [c[@"fitted"] CGSizeValue];
    return G1B_SUPER(CGSize, gAsParent, self, _cmd, (struct objc_super *, SEL));
}
static CGSize G1C_As_ContentSize(id self, SEL _cmd) {                                     // 0x1c78124c8: (max(fitted.width, view width), view height); 16.0 added _horizontalSpacing
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (!c) return G1B_SUPER(CGSize, gAsParent, self, _cmd, (struct objc_super *, SEL));
    CGRect vb = G1C_SendRect0(self, @selector(switcherViewBounds));
    return CGSizeMake(MAX([c[@"fitted"] CGSizeValue].width, vb.size.width), vb.size.height);
}
// 0x1c7812518: the offset that puts the (scaled) card at hEdge from one edge (alignment 0/3: the LTR trailing / RTL leading edge, 1: the other edge) or centred (2),
// clamped to [0, contentWidth - viewWidth]; y is always 0.
static CGPoint G1C_As_ContentOffsetForIndex(id self, SEL _cmd, unsigned long long i, long long align) {
    CGRect f;
    if (!G1C_As_Frame(self, i, YES, NO, &f)) return G1B_SUPER(CGPoint, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long, long long), i, align);
    BOOL rtl = G1C_Resp(self, @selector(isRTLEnabled)) && G1B_SendB0(self, @selector(isRTLEnabled));
    double hEdge = G1B_Dbl0(G1B_Send0(self, @selector(chamoisLayoutAttributes)), NSSelectorFromString(@"switcherHorizontalEdgeSpacing"));
    double vbW = G1C_SendRect0(self, @selector(switcherViewBounds)).size.width, off = 0.0;
    switch (align) {
        case 0: case 3: off = rtl ? hEdge : vbW - f.size.width - hEdge; break;
        case 1: off = rtl ? vbW - f.size.width - hEdge : hEdge; break;
        case 2: off = (vbW - f.size.width) * 0.5; break;
        default: break;
    }
    double x = MAX(CGRectGetMinX(f) - off, 0.0), limit = G1C_As_ContentSize(self, 0).width - vbW;
    return CGPointMake(limit > x ? x : limit, 0.0);
}
// _visibleSwitcherBoundsIncludingShadow 0x1c78133f4 (const 0xc006666666666666 = -2.8) and the pile bounding frame of 0x1c7813800 with the scroll offset applied
static CGRect G1C_As_VisibleBounds(id self) {
    CGRect vb = G1C_SendRect0(self, @selector(switcherViewBounds));
    double r = G1B_Dbl0(G1B_Send0(self, @selector(switcherSettings)), NSSelectorFromString(@"switcherCardShadowRadius"));
    return CGRectInset(vb, r * -2.8, r * -2.8);
}
static BOOL G1C_As_PileVisible(NSDictionary *c, id ident, double scrollX, CGRect visible) {
    NSValue *v = ident ? c[@"piles"][ident] : nil;
    if (!v) return NO;
    CGRect r = [v CGRectValue];
    r.origin.x -= scrollX;
    return CGRectIntersectsRect(visible, r);
}
// 0x1c7810118: the first numberOfVisibleItemsPerGroup windows of every pile whose bounding frame touches the (shadow-extended) view (_visiblePileIdentifiers 0x1c781345c);
// a plain new set, no 16.0 contribution.
static id G1C_As_VisibleAppLayouts(id self, SEL _cmd) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (!c) return G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL));        // piles off / detached copy (logged by G1C_As_Calc)
    NSMutableSet *out = [NSMutableSet set];
    id sw = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id cs = G1C_Resp(sw, @selector(chamoisSettings)) ? G1B_Send0(sw, @selector(chamoisSettings)) : nil;
    NSUInteger nVis = (cs && [cs respondsToSelector:@selector(numberOfVisibleItemsPerGroup)]) ? (NSUInteger)G1B_SendLL0(cs, @selector(numberOfVisibleItemsPerGroup)) : 3;
    SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:");
    CGRect vis = G1C_As_VisibleBounds(self);
    double sx = G1C_As_ScrollX(self);
    for (id ident in c[@"ids"]) {
        if (!G1C_As_PileVisible(c, ident, sx, vis)) continue;
        NSUInteger n = 0;
        for (id l in (G1C_Resp(self, byId) ? G1C_AsArray(G1B_Send1(self, byId, ident)) : @[])) { if (n++ >= nVis) break; [out addObject:l]; }
    }
    return out;
}
// 16.0 visibleSpaceRangeForContentOffset: (column maths) feeds visibleAppLayouts, appLayoutsToCacheSnapshots, topMostLayoutElements and _indexOfLeadingAppLayout.
// The answer is the contiguous range of piles that touch the view at that offset (16.2 _visiblePileRange 0x1c7810c9c tracks the two parity rows separately and
// ends one row short for 1-2 piles; its only consumer is the snapshot cache, so the plain contiguous range is the safe superset).
static NSRange G1C_As_VisibleSpaceRange(id self, SEL _cmd, CGPoint offset) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (![c[@"frames"] count]) return G1B_SUPER(NSRange, gAsParent, self, _cmd, (struct objc_super *, SEL, CGPoint), offset);
    NSArray *ids = c[@"ids"];
    CGRect vis = G1C_As_VisibleBounds(self);
    NSUInteger lo = NSNotFound, hi = 0;
    for (NSUInteger p = 0; p < ids.count; p++) if (G1C_As_PileVisible(c, ids[p], offset.x, vis)) { if (lo == NSNotFound) lo = p; hi = p; }
    return lo == NSNotFound ? NSMakeRange(0, 0) : NSMakeRange(lo, hi - lo + 1);
}
// ---- 16.2 pile queries on the pile cache: _boundingFrameForPileAtIndex:withScrollOffsetApplied: 0x1c781376c / ...WithIdentifier: 0x1c7813800, _visiblePileRange 0x1c7810c9c,
//      distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch: 0x1c781264c (HomeToGrid slides the switcher copy off screen by this) ----
static CGRect G1C_As_PileBox(id self, NSDictionary *c, NSUInteger idx, BOOL scroll) {
    NSArray *ids = c[@"ids"];
    id ident = idx < ids.count ? ids[idx] : nil;
    NSValue *v = ident ? c[@"piles"][ident] : nil;
    CGRect r = v ? [v CGRectValue] : CGRectZero;
    if (scroll) r.origin.x -= G1C_As_ScrollX(self);
    return r;
}
static NSRange G1C_As_VisiblePileRange(id self, NSDictionary *c) {
    const NSUInteger NF = NSNotFound;
    NSUInteger n = [c[@"ids"] count];
    CGRect vis = G1C_As_VisibleBounds(self);
    NSUInteger firstEven = NF, firstOdd = NF, endEven = NF, endOdd = NF;
    for (NSUInteger p = 0; p < n; p++) {
        if (endEven != NF && endOdd != NF) break;
        BOOL even = (p & 1) == 0, v = CGRectIntersectsRect(vis, G1C_As_PileBox(self, c, p, YES));
        NSUInteger visIdx = v ? p : NF, invIdx = v ? NF : p;
        if (even && firstEven == NF) firstEven = visIdx;
        if (!even && firstOdd == NF) firstOdd = visIdx;
        if (even && firstEven != NF && endEven == NF) endEven = invIdx;
        if (!even && firstOdd != NF && endOdd == NF) endOdd = invIdx;
    }
    if (n == 0) return NSMakeRange(0, 0);
    NSUInteger lo = MIN(firstEven, firstOdd);
    NSUInteger lastEven = (endEven == NF ? n : endEven) - 2, lastOdd = (endOdd == NF ? n : endOdd) - 2;
    NSUInteger last = MAX(lastEven, lastOdd);
    if (lo == NF || last == NF) return NSMakeRange(0, 0);
    return NSMakeRange(lo, last - lo + 1);
}
static double G1C_As_Distance(id self, SEL _cmd, unsigned long long idx) {
    NSDictionary *c = (G1C_PilesOn() && BP_OnName("g1c_homeslide")) ? G1C_As_Calc(self) : nil;
    if (!c) return G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), idx);        // piles off / detached copy (logged by G1C_As_Calc)
    NSUInteger n = [c[@"ids"] count];
    if (n == 0) return 0.0;                                                          // 16.2 would raise on objectAtIndex: of an empty id list
    NSRange rg = G1C_As_VisiblePileRange(self, c);
    NSUInteger pick = rg.location;
    if (rg.length >= 2 && pick + 1 < n && CGRectGetMaxX(G1C_As_PileBox(self, c, pick + 1, NO)) > CGRectGetMaxX(G1C_As_PileBox(self, c, pick, NO))) pick = pick + 1;
    if (pick >= n) pick = 0;
    CGRect f = G1C_As_PileBox(self, c, pick, YES);
    BOOL rtl = G1C_Resp(self, @selector(isRTLEnabled)) && G1B_SendB0(self, @selector(isRTLEnabled));
    double x = rtl ? G1C_SendRect0(self, @selector(switcherViewBounds)).size.width - f.origin.x : CGRectGetMaxX(f);
    return x + G1B_Dbl0(G1B_Send0(self, @selector(chamoisLayoutAttributes)), NSSelectorFromString(@"switcherHorizontalInterItemSpacing"));
}
static long long G1C_As_IndexInPile(id self, SEL _cmd, id layout);
// _visiblePileIdentifiers 0x1c781345c: the identifiers whose pile box (scroll applied) touches the shadow-extended view
static NSArray *G1C_As_VisibleIdents(id self, NSDictionary *c) {
    NSMutableArray *out = [NSMutableArray array];
    CGRect vis = G1C_As_VisibleBounds(self);
    double sx = G1C_As_ScrollX(self);
    for (id ident in c[@"ids"]) if (G1C_As_PileVisible(c, ident, sx, vis)) [out addObject:ident];
    return out;
}
static NSUInteger G1C_As_NumVisibleItems(id self) {
    id sw = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id cs = G1C_Resp(sw, @selector(chamoisSettings)) ? G1B_Send0(sw, @selector(chamoisSettings)) : nil;
    return (cs && [cs respondsToSelector:@selector(numberOfVisibleItemsPerGroup)]) ? (NSUInteger)G1B_SendLL0(cs, @selector(numberOfVisibleItemsPerGroup)) : 3;
}
static NSArray *G1C_As_PileLayouts(id self, id ident) {
    SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:");
    return G1C_Resp(self, byId) ? G1C_AsArray(G1B_Send1(self, byId, ident)) : @[];
}
// 0x1c7810410: z-order / hit-test list = the first numberOfVisibleItemsPerGroup + 1 windows (index <= n) of every visible pile
static id G1C_As_TopMost(id self, SEL _cmd) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (!c) return G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL));
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger nVis = G1C_As_NumVisibleItems(self);
    for (id ident in G1C_As_VisibleIdents(self, c)) {
        NSUInteger k = 0;
        for (id l in G1C_As_PileLayouts(self, ident)) { if (k++ > nVis) break; [out addObject:l]; }
    }
    return out;
}
// 0x1c78106d4: on-screen radius 10 (7 when the display has no corner radius), counter-scaled by the card scale
static G1CRadii G1C_As_Corner(id self, SEL _cmd, unsigned long long i) {
    if (!G1C_PilesOn()) return G1B_SUPER(G1CRadii, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    double r = (G1B_Dbl0(self, NSSelectorFromString(@"displayCornerRadius")) > 0.0 ? 10.0 : 7.0) / G1C_SendD0Q(self, @selector(scaleForIndex:), i);
    G1CRadii v = { r, r, r, r };
    return v;
}
// 0x1c7810020
static double G1C_As_TitleIconOpacity(id self, SEL _cmd, unsigned long long i) {
    if (!G1C_PilesOn()) return G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    id l = G1C_As_LayoutAt(self, i);
    return G1C_As_IndexInPile(self, 0, l) == 0 ? 1.0 : 0.0;
}
// 0x1c78115d4: the first window of the first pile that is on screen
static unsigned long long G1C_As_LeadingIndex(id self, SEL _cmd) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (!c) return G1B_SUPER(unsigned long long, gAsParent, self, _cmd, (struct objc_super *, SEL));
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : @[];
    for (id ident in G1C_As_VisibleIdents(self, c)) {
        id first = [G1C_As_PileLayouts(self, ident) firstObject];
        if (first) return (unsigned long long)[ls indexOfObject:first];
    }
    return (unsigned long long)NSNotFound;
}
// 0x1c7811564 (indexToScrollToAfterInsertingAtIndex: 0x1c7811540 is unchanged: leading index, 0 when none)
static unsigned long long G1C_As_ScrollAfterRemoving(id self, SEL _cmd, unsigned long long i) {
    if (!G1C_PilesOn()) return G1B_SUPER(unsigned long long, gAsParent, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    NSArray *ls = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : @[];
    if (ls.count < 2) return (unsigned long long)NSNotFound;
    return G1C_SendULL0(self, NSSelectorFromString(@"_indexOfLeadingAppLayout"));
}
// 0x1c780f7dc: remembers the scroll direction for the snapshot cache window
static id G1C_As_HandleScroll(id self, SEL _cmd, id event) {
    if (G1C_PilesOn()) {
        CGPoint off = G1C_Resp(self, @selector(contentOffset)) ? G1C_SendPoint0(self, @selector(contentOffset)) : CGPointZero;
        CGPoint prev = G1C_IvarPoint(self, "_previousContentOffset");
        if (!G1C_IsInvalidPoint(off) && fabs(prev.x - off.x) > 0.0001) G1C_SetIvarBool(self, "_isScrollingForward", prev.x > off.x);      // BSFloatEqualToFloat
        G1C_SetIvarPoint(self, "_previousContentOffset", off);
    }
    return G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL, id), event);
}
// 0x1c7810e7c: snapshot cache window = the visible piles (ascending when scrolling forward, else descending), then batches of 2 piles in the scroll direction and
// 1 in the other direction until every pile is listed; the windows of those piles (at most numberOfVisibleItemsPerGroup each) up to numberOfSnapshotsToCache.
static NSArray *G1C_As_SnapshotWindow(id self, NSDictionary *c, NSRange range, NSUInteger total, BOOL forward) {
    if (range.length == 0) return @[];
    NSArray *ids = c[@"ids"];
    NSInteger n = (NSInteger)ids.count;
    NSMutableArray *order = [NSMutableArray array];
    NSInteger end = (NSInteger)(range.location + range.length), loc = (NSInteger)range.location;
    if (forward) { for (NSInteger i = loc; i < end; i++) [order addObject:@(i)]; }
    else { for (NSInteger i = end - 1; i >= loc; i--) [order addObject:@(i)]; }
    NSInteger capFwd = forward ? 2 : 1, capBack = forward ? 1 : 2;
    NSInteger fwd = end, back = loc - 1;
    while (fwd < n || back >= 0) {
        for (int pass = 0; pass < 2; pass++) {
            BOOL doFwd = forward ? (pass == 0) : (pass == 1);
            if (doFwd) { NSInteger k = MAX((NSInteger)0, n - fwd); k = MIN(k, capFwd); while (k-- > 0) { [order addObject:@(fwd)]; fwd++; } }
            else { NSInteger k = MIN(back + 1, capBack); while (k-- > 0) { [order addObject:@(back)]; back--; } }
        }
    }
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger nVis = G1C_As_NumVisibleItems(self);
    for (NSNumber *idx in order) {
        NSUInteger have = out.count;
        if (have >= total) break;
        NSUInteger remaining = total - have, i = idx.unsignedIntegerValue;
        NSArray *ls = G1C_As_PileLayouts(self, i < ids.count ? ids[i] : nil);
        NSUInteger take = MIN(MIN(ls.count, nVis), remaining);
        [out addObjectsFromArray:[ls subarrayWithRange:NSMakeRange(0, take)]];
    }
    return out;
}
static id G1C_As_SnapshotsWithRange(id self, SEL _cmd, NSRange range, unsigned long long total, BOOL forward) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    return c ? G1C_As_SnapshotWindow(self, c, range, (NSUInteger)total, forward) : @[];
}
static id G1C_As_CacheSnapshots(id self, SEL _cmd) {
    NSDictionary *c = G1C_PilesOn() ? G1C_As_Calc(self) : nil;
    if (!c) return G1B_SUPER(id, gAsParent, self, _cmd, (struct objc_super *, SEL));
    id sw = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    NSUInteger total = (NSUInteger)G1B_SendLL0(sw, NSSelectorFromString(@"numberOfSnapshotsToCacheInSwitcher"));
    return G1C_As_SnapshotWindow(self, c, G1C_As_VisiblePileRange(self, c), total, G1C_IvarBool(self, "_isScrollingForward"));
}
static BOOL G1C_As_Usable(id self) {                                                      // can this (possibly detached) modifier answer protocol queries?
    @try { (void)G1C_SendRect0(self, @selector(containerViewBounds)); return YES; } @catch (NSException *e) { (void)e; return NO; }
}
static long long G1C_As_IndexInPile(id self, SEL _cmd, id layout) {
    id ident = G1C_Resp(layout, @selector(continuousExposeIdentifier)) ? G1B_Send0(layout, @selector(continuousExposeIdentifier)) : nil;
    SEL byId = NSSelectorFromString(@"appLayoutsForContinuousExposeIdentifier:");
    NSArray *ls = (ident && G1C_Resp(self, byId)) ? G1B_Send1(self, byId, ident) : nil;
    NSUInteger n = ls ? [ls indexOfObject:layout] : NSNotFound;
    return n == NSNotFound ? 0 : (long long)n;
}
static double G1C_As_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long i) {
    if (!G1C_PilesOn() || !G1C_As_Usable(self)) return G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, i);
    id s = G1C_Resp(self, @selector(switcherSettings)) ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id cs = G1C_Resp(s, @selector(chamoisSettings)) ? G1B_Send0(s, @selector(chamoisSettings)) : nil;
    long long vis = (cs && [cs respondsToSelector:@selector(numberOfVisibleItemsPerGroup)]) ? G1B_SendLL0(cs, @selector(numberOfVisibleItemsPerGroup)) : 3;
    return G1C_As_IndexInPile(self, 0, layout) < vis ? 1.0 : 0.0;
}
static double G1C_As_CardScale(id self) {                                         // 0x1c78132d4
    double h = G1C_As_CardHeight(self);
    CGRect b = G1C_SendRect0(self, @selector(containerViewBounds));
    return b.size.height == 0 ? 1.0 : h / b.size.height;
}
static double G1C_As_DefaultCardScale(id self, SEL _cmd) {
    if (!G1C_PilesOn() || !G1C_As_Usable(self)) return G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL));
    return G1C_As_CardScale(self);
}
static double G1C_As_SnapshotScale(id self, SEL _cmd, id layout) { return (G1C_PilesOn() && G1C_As_Usable(self)) ? G1C_As_CardScale(self) : G1B_SUPER(double, gAsParent, self, _cmd, (struct objc_super *, SEL, id), layout); }

// --- behaviour (only on the full class; the floor class below has the layout overrides and nothing else) ---
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
        Class pc = NSClassFromString(@"SBPulseDisplayItemSwitcherModifier"), cc = NSClassFromString(@"SBAddModifierSwitcherEventResponse");
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
    if (BP_LogEnabled()) {
        NSArray *dl = G1C_Resp(self, @selector(appLayouts)) ? G1B_Send0(self, @selector(appLayouts)) : nil;
        BP_Log(@"g1c: app switcher removal event phase %lld ongoing %lld appLayouts %lu (last-window dismiss fires at phase 2 with 0 layouts and 0 ongoing)", phase, n, (unsigned long)dl.count);
    }
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
extern NSArray *BP_G2_AdjustedStripIds(id modifier, NSArray *prev);                          // G2.x, 162 0x1c7811a50
extern NSArray *BP_G2_AdjustedSwitcherIds(id modifier, NSArray *prev, NSArray *strip);       // G2.x, 162 0x1c7811880
static id G1C_As_AdjustedIds(id self, SEL _cmd, id a, id b) { return BP_G2_AdjustedSwitcherIds(self, a, b); }
static id G1C_As_AdjustedStrip(id self, SEL _cmd, id a) { return BP_G2_AdjustedStripIds(self, a); }
static BOOL G1C_As_ReturnNO(id self, SEL _cmd) { return NO; }
static BOOL G1C_As_ReturnYES(id self, SEL _cmd) { return YES; }
static BOOL G1C_As_NoGrab(id self, SEL _cmd, id l) { return NO; }

// Two run-time classes:
//   BP162AppSwitcherFloorContinuousExposeSwitcherModifier : SBAppSwitcherContinuousExposeSwitcherModifier  - the pile LAYOUT only (+ the cache invalidation tick).
//       This is what the persistent switcher floor uses (G1C_NewAppSwitcherFloorModifier): its tap / removal / flag answers stay exactly the stock 16.0 ones
//       (those come from the SBGridSwitcherModifier child that the 16.0 init adds), so the working switcher keeps working and only the geometry changes.
//   BP162AppSwitcherContinuousExposeSwitcherModifier : the floor class  - adds the 16.2 behaviour layer; used by the swipe-up gesture root, peek and drag content.
static Class gAsFloorCls;
static BOOL G1C_BuildAppSwitcher(void) {
    gAsParent = NSClassFromString(@"SBAppSwitcherContinuousExposeSwitcherModifier");
    if (!gAsParent) return NO;
    {
        const G1BIvar iv[] = { { "_bp_eventGen", sizeof(long long), 3, "q" } };
        const G1BMethod m[] = {
            { "handleEvent:", (IMP)G1C_As_Event, "@24@0:8@16" },
            { "frameForIndex:", (IMP)G1C_As_FrameForIndex, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
            { "scaleForIndex:", (IMP)G1C_As_ScaleForIndex, "d24@0:8Q16" },
            { "anchorPointForIndex:", (IMP)G1C_As_Anchor, "{CGPoint=dd}24@0:8Q16" },
            { "frameForLayoutRole:inAppLayout:withBounds:", (IMP)G1C_As_FrameForRole, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32" },
            { "_fittedContentSize", (IMP)G1C_As_Fitted, "{CGSize=dd}16@0:8" },
            { "_contentSize", (IMP)G1C_As_ContentSize, "{CGSize=dd}16@0:8" },
            { "contentOffsetForIndex:alignment:", (IMP)G1C_As_ContentOffsetForIndex, "{CGPoint=dd}32@0:8Q16q24" },
            { "visibleAppLayouts", (IMP)G1C_As_VisibleAppLayouts, "@16@0:8" },
            { "visibleSpaceRangeForContentOffset:", (IMP)G1C_As_VisibleSpaceRange, "{_NSRange=QQ}32@0:8{CGPoint=dd}16" },
            { "_indexOfAppLayoutInItsPile:", (IMP)G1C_As_IndexInPile, "Q24@0:8@16" },
            { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_As_Opacity, "d40@0:8q16@24Q32" },
            { "_defaultCardScale", (IMP)G1C_As_DefaultCardScale, "d16@0:8" },
            { "snapshotScaleForAppLayout:", (IMP)G1C_As_SnapshotScale, "d24@0:8@16" },
            { "distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch:", (IMP)G1C_As_Distance, "d24@0:8Q16" },
            { "topMostLayoutElements", (IMP)G1C_As_TopMost, "@16@0:8" },
            { "cornerRadiiForIndex:", (IMP)G1C_As_Corner, "{UIRectCornerRadii=dddd}24@0:8Q16" },
            { "titleAndIconOpacityForIndex:", (IMP)G1C_As_TitleIconOpacity, "d24@0:8Q16" },
            { "_indexOfLeadingAppLayout", (IMP)G1C_As_LeadingIndex, "Q16@0:8" },
            { "indexToScrollToAfterRemovingIndex:", (IMP)G1C_As_ScrollAfterRemoving, "Q24@0:8Q16" },
            { "handleScrollEvent:", (IMP)G1C_As_HandleScroll, "@24@0:8@16" },
            { "appLayoutsToCacheSnapshots", (IMP)G1C_As_CacheSnapshots, "@16@0:8" },
            { "_appLayoutsToCacheSnapshotsWithVisiblePileRange:numberOfSnapshotsToCache:biasForward:", (IMP)G1C_As_SnapshotsWithRange, "@48@0:8{_NSRange=QQ}16Q32B40" },
        };
        gAsFloorCls = G1B_MakeClass("BP162AppSwitcherFloorContinuousExposeSwitcherModifier", gAsParent, iv, 1, m, sizeof m / sizeof m[0], NULL, NULL);
    }
    const G1BIvar iv[] = {
        { "_bp_handlesTap", 1, 0, "B" }, { "_bp_handlesHeaderTap", 1, 0, "B" },
        { "_bp_ongoingRemovals", sizeof(long long), 3, "q" },
    };
    const G1BMethod m[] = {
        { "init", (IMP)G1C_As_Init, "@16@0:8" },
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
    };
    gAsCls = G1B_MakeClass("BP162AppSwitcherContinuousExposeSwitcherModifier", gAsFloorCls ?: gAsParent, iv, 3, m, sizeof m / sizeof m[0], NULL, NULL);
    return gAsCls != Nil;
}
static id G1C_NewAppSwitcherModifier(void) {
    Class c = gAsCls ?: (gAsFloorCls ?: gAsParent);
    return c ? [[c alloc] init] : nil;
}
// The persistent switcher floor (see the section header): layout class only; stock 16.0 class when piles are off or the class could not be built.
static id G1C_NewAppSwitcherFloorModifier(void) {
    Class c = G1C_PilesOn() ? gAsFloorCls : Nil;
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

// ============================================================================================================
// 0  -[SBSwitcherModifier _handleEvent:] default exit  (16.0 returns SELF for event types > 35)                         PORTED (crash fix)
// ============================================================================================================
// ROOT CAUSE of "-[SBStripContinuousExposeSwitcherModifier responseByTransformingResponseWithTransformer:]: unrecognized selector".
// 16.0 -[SBSwitcherModifier _handleEvent:] (0x1c63e8a98) keeps self in x20 and switches on the event type (cases 0...35). For every type > 35 it branches (b.hi 0x1c63e8b50) to the common
// exit 0x1c63e8b28 with x20 STILL = self, and returns it: the "response" of an unhandled type 36 / 37 / 38 event is the MODIFIER itself (16.2 0x1c7895274 returns the handler's result, nil
// when there is none). G1B routes those new types to handle<X>Event: and returns `orig` for every modifier that has no such handler - the Strip, the FullScreenAppLayout child, ... - so a
// header tap (37) / pointer-crossed-display (38) / edge-protect-tongue (36) event made the whole child tree return modifiers as responses, and SBChainableModifier -handleEvent: composed
// them into the composite whose responseByTransformingResponseWithTransformer: then died. Ours wraps whatever is below (G1B's routing hook or the original): a result that is the
// receiver is the 16.0 quirk, the 16.2 value is nil. Never a legitimate response (a modifier is not a response), so this is exactly the one place the value is wrong.
// 0.7.3: THIS HOOK ALONE WAS NOT ENOUGH. The same default exit also returns `self` through objc_autoreleaseReturnValue without ever having retained it, i.e. the stock body over-releases
// the receiving modifier once per type > 35 event (the real cause of the freed-modifier crash in enumerateChildModifiersWithBlock:, specs/AUDIT-RETAIN-CRASH-0.7.3.md). The 16.0 body is
// now never run for those types (G1B.x section 0.1 does what 16.2 does itself: [super _handleEvent:] + handler), so `r == self` cannot happen any more. This hook stays as the
// last-line guard for a stock body reached by some other path (logged; the reference cannot be repaired from here, the value is only turned into nil).
%group G1C_EventDefault
%hook SBSwitcherModifier
- (id)_handleEvent:(id)event {
    id r = %orig;
    if (r != (id)self) return r;
    static int logged;
    if (BP_LogEnabled() && logged++ < 20) BP_Log(@"g1c: _handleEvent: type %lld returned the modifier itself (16.0 default exit of SBSwitcherModifier _handleEvent:) -> nil as 16.2 [%@]", G1B_SendLL0(event, @selector(type)), NSStringFromClass(object_getClass(self)));
    return nil;
}
%end
%end

// ---- -[SBSwitcherModifier(SharedModifierUtilities) overlappingModelForAppLayout:]  16.2 0x1c7652fc4 (16.0 0x1c61c4450)                                            switch g1c_modelmap
// 16.2 asks the calculator for the model of [self appLayoutContainingAppLayout:layout] (the query is answered down the chain: WindowDelete / WindowDrag / Split overrides, at the end the
// view controller: the first unadjusted layout that is or contains the layout, else the layout itself, never nil: 0x1c7435e54). 16.0 passes `layout` unchanged, and in 16.0 this public method
// has NO caller at all: the four classes that needed a model (FullScreen / Inline / AppSwitcher CE, strip overflow reveal) each had a private _overlappingModelForAppLayout: that already
// did the mapping (16.0 0x1c5f1ee28 / 0x1c6141330 / 0x1c61fa2f4 / 0x1c636c1c4, instruction sequence identical to the 16.2 body). The ported 16.2 callers (FullScreen floor, Strip, Inline, F2S / XB
// transitions via G1B_OverlapBBox, PIP morph transitionWillBegin, HomeScreen floor ...) call only the public one, so on 16.0 they got the model of the UNMAPPED layout (e.g. a leaf or
// the closing window's own layout instead of the stage it belongs to: wrong bounding box / stage area / occlusion for exactly those). Wrapped in @try: a detached modifier copy that cannot
// answer the mapping query gets the 16.0 answer.
%group G1C_ModelMap
%hook SBSwitcherModifier
- (id)overlappingModelForAppLayout:(id)layout {
    if (!G1C_ON() || !BP_OnName("g1c_modelmap") || !layout) {
        return %orig;
    }
    id contained = layout;
    @try {
        id c = G1B_Send1(self, @selector(appLayoutContainingAppLayout:), layout);
        if (c) contained = c;
    } @catch (NSException *e) {
        if (BP_LogEnabled()) BP_Log(@"GUARD overlappingModelForAppLayout: no implementor for appLayoutContainingAppLayout: (%@) -> unmapped layout", e.reason);
    }
    return %orig(contained);
}
%end
%end

// ---- SBFluidSwitcherViewController -_scrollToAppLayout:animated:alignment:completion:  16.2 0x1c7452ff0 (16.0 0x1c5fd9c44)                                          with g1c_piles
// 16.2 always scrolls to the index of the layout in -appLayouts. 16.0 under Stage Manager used the index of the layout's continuousExposeIdentifier in the VC's identifier list (one entry
// per pile, an app's windows are one pile), and its AppSwitcherCE contentOffsetForIndex:alignment: counted piles too. The port answers contentOffsetForIndex:alignment: the 16.2 way
// (G1C_As_ContentOffsetForIndex: index into appLayouts, the pile layout of 0x1c7812518), so the 16.0 VC body asked for the offset of the wrong window as soon as an app had more than
// one window (reopen-closed-windows button, every scroll-to-layout response of the modifiers). The rest of the method is the same in both builds. With piles off the 16.0 pair is consistent: stock.
%group G1C_VCScroll
%hook SBFluidSwitcherViewController
- (void)_scrollToAppLayout:(id)layout animated:(BOOL)animated alignment:(long long)alignment completion:(void (^)(BOOL))completion {
    id root = G1C_IvarObj(self, "_rootModifier"), scroll = G1C_IvarObj(self, "_scrollView");
    SEL co = NSSelectorFromString(@"contentOffsetForIndex:alignment:"), so = NSSelectorFromString(@"setContentOffset:animated:completion:");
    if (!G1C_PilesOn() || !layout || !G1C_Resp(root, co) || !G1C_Resp(scroll, so) || !G1C_Resp(self, @selector(appLayouts))) {
        %orig;
        return;
    }
    NSUInteger idx = [G1C_AsArray(G1B_Send0(self, @selector(appLayouts))) indexOfObject:layout];
    if (idx == NSNotFound) {
        if (completion) completion(YES);
        return;
    }
    if (G1C_Resp(self, @selector(_updateScrollViewSizeAndSpacing))) ((void (*)(id, SEL))objc_msgSend)(self, @selector(_updateScrollViewSizeAndSpacing));
    CGPoint off = ((CGPoint (*)(id, SEL, unsigned long long, long long))objc_msgSend)(root, co, idx, alignment);
    ((void (*)(id, SEL, CGPoint, BOOL, id))objc_msgSend)(scroll, so, off, animated, completion);
}
%end
%end

// ---- close trace (diagnostics only, BP_LogEnabled; user video 0dee8146 = Dopamine window, size jump at the start of the home-swipe close): what the composed root answers for the closing stage window during the home swipe ----
// Armed when a home gesture starts in mode 3 (G1C_HGR_GestureChild), disarmed at phase 3 of the next transition.  Every line starts with "[g1c] close", carries the transition phase
// (g = gesture still running, 1/2/3 = transition phases) and is logged only when the answer changed.  The values are exactly what the layout block (G2B BP2B_LayoutAppLayoutImpl) reads.
static BOOL gCloseTraceOn;
static int gCloseTracePhase;                                                          // 0 = gesture
static NSString *gCloseTraceSig[8];
static unsigned gCloseTraceSerial;                                                    // counts the armed home swipe closes (read by G2F.x for its per-close dump)
// G2F.x: -1 = no traced close running, else the current phase (0 = gesture, 1..3 = transition phases) and the close's serial number.
int G1C_CloseTraceState(unsigned *serial) {
    if (!gCloseTraceOn) return -1;
    if (serial) *serial = gCloseTraceSerial;
    return gCloseTracePhase;
}
static void G1C_CloseTraceArm(long long mode) {
    if (!BP_LogEnabled() || mode != 3) return;
    gCloseTraceOn = YES; gCloseTracePhase = 0; gCloseTraceSerial++;
    for (int k = 0; k < 8; k++) gCloseTraceSig[k] = nil;
    BP_Log(@"[g1c] close: trace armed (home gesture in mode 3)");
}
static void G1C_CloseTraceLine(int slot, NSString *what, unsigned long long idx, NSString *vals) {
    NSString *sig = [NSString stringWithFormat:@"%d|%llu|%@", gCloseTracePhase, idx, vals];
    BOOL changed = NO;
    @synchronized(@"BP162.closetrace") { if (![gCloseTraceSig[slot] isEqualToString:sig]) { gCloseTraceSig[slot] = sig; changed = YES; } }
    if (changed) BP_Log(@"[g1c] close %@ phase=%@ idx=%llu %@", what, gCloseTracePhase ? [NSString stringWithFormat:@"%d", gCloseTracePhase] : @"g", idx, vals);
}
static BOOL G1C_CloseTraceIsStage(id root, id layout) {
    id stage = G1B_GET(root, kRootEffStage);
    return gCloseTraceOn && layout && stage && [layout isEqual:stage];
}
static void G1C_CloseTraceTransition(id root, id event, long long phase) {
    if (!gCloseTraceOn || !BP_LogEnabled()) return;
    gCloseTracePhase = (int)phase;
    id fl = G1C_Resp(root, @selector(floorModifier)) ? G1B_Send0(root, @selector(floorModifier)) : nil;
    BP_Log(@"[g1c] close transition phase=%lld modes %lld->%lld floor=%@ stage=%@", phase, G1B_SendLL0(event, @selector(fromEnvironmentMode)), G1B_SendLL0(event, @selector(toEnvironmentMode)),
           G1C_DbgCls(fl), G1C_DbgLayout(G1B_GET(root, kRootEffStage)));
    if (phase == 3) gCloseTraceOn = NO;
}

%group G1C_Root
%hook SBContinuousExposeRootSwitcherModifier

// close trace: the composed answers (log only; the values are returned untouched)
- (CGRect)frameForIndex:(unsigned long long)i {
    CGRect r = %orig;
    if (gCloseTraceOn && G1C_CloseTraceIsStage(self, G1C_LayoutAtIdx(self, i))) G1C_CloseTraceLine(0, @"frame", i, NSStringFromCGRect(r));
    return r;
}
- (double)scaleForIndex:(unsigned long long)i {
    double r = %orig;
    if (gCloseTraceOn && G1C_CloseTraceIsStage(self, G1C_LayoutAtIdx(self, i))) G1C_CloseTraceLine(1, @"scale", i, [NSString stringWithFormat:@"%.4f", r]);
    return r;
}
- (CGPoint)anchorPointForIndex:(unsigned long long)i {
    CGPoint r = %orig;
    if (gCloseTraceOn && G1C_CloseTraceIsStage(self, G1C_LayoutAtIdx(self, i))) G1C_CloseTraceLine(2, @"anchor", i, NSStringFromCGPoint(r));
    return r;
}
- (CGRect)frameForLayoutRole:(long long)role inAppLayout:(id)layout withBounds:(CGRect)bounds {
    CGRect r = %orig;
    if (gCloseTraceOn && G1C_CloseTraceIsStage(self, layout)) G1C_CloseTraceLine(3, @"roleFrame", (unsigned long long)role, [NSString stringWithFormat:@"%@ in bounds %@", NSStringFromCGRect(r), NSStringFromCGSize(bounds.size)]);
    return r;
}
- (double)scaleForLayoutRole:(long long)role inAppLayout:(id)layout {
    double r = %orig;
    if (gCloseTraceOn && G1C_CloseTraceIsStage(self, layout)) G1C_CloseTraceLine(4, @"roleScale", (unsigned long long)role, [NSString stringWithFormat:@"%.4f", r]);
    return r;
}

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
                if (floor && [floor isKindOfClass:fsC] && toAL && G1C_Resp(floor, @selector(fullScreenAppLayout)) && [G1B_Send0(floor, @selector(fullScreenAppLayout)) isEqual:toAL]) return floor;      // 16.2 FullScreen has no pile / displacement state
                id fs = toAL ? G1C_NewFullScreenModifier(toAL) : nil;
                if (!fs) return %orig;
                if (floor && [floor isKindOfClass:fsC]) {                                                  // carry the highlight sets
                    id t = G1C_Resp(floor, @selector(highlightedByTouchAppLayouts)) ? G1B_Send0(floor, @selector(highlightedByTouchAppLayouts)) : nil;
                    id h = G1C_Resp(floor, @selector(highlightedByHoverAppLayouts)) ? G1B_Send0(floor, @selector(highlightedByHoverAppLayouts)) : nil;
                    if (t && [fs respondsToSelector:@selector(setHighlightedByTouchAppLayouts:)]) G1B_SendV1(fs, @selector(setHighlightedByTouchAppLayouts:), t);
                    if (h && [fs respondsToSelector:@selector(setHighlightedByHoverAppLayouts:)]) G1B_SendV1(fs, @selector(setHighlightedByHoverAppLayouts:), h);
                }
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

// ---- multitaskingModifierForEvent: (16.2 0x1c7818560; 16.0 0x1c63711ec is the same two lines) -- `self.multitaskingModifier ?: [AppSwitcherCE new]` ----
// With piles on the persistent switcher must be laid out by the same pile geometry as the swipe-up gesture / peek / drag instances (G1C_NewAppSwitcherModifier),
// otherwise the layout snaps from the stock grid to the piles at the hand-off. The floor class carries the layout only (see G1C_BuildAppSwitcher).
- (id)multitaskingModifierForEvent:(id)event {
    if (!G1C_PilesOn()) return %orig;
    id current = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
    if (current) return current;
    id n = G1C_NewAppSwitcherFloorModifier();
    return n ?: %orig;
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
        case 1: {                                         // 16.2 0x1c7818d78 (same shape as 16.0 0x1c6371688): the home gesture root carries a NEW AppSwitcherCE; here that one lays out in piles like the floor
            id multi = G1C_NewAppSwitcherFloorModifier();
            Class hc = NSClassFromString(@"SBHomeGestureRootSwitcherModifier");
            SEL hi = NSSelectorFromString(@"initWithStartingEnvironmentMode:multitaskingModifier:");
            if (multi && hc && [hc instancesRespondToSelector:hi]) {
                eff = ((id (*)(id, SEL, long long, id))objc_msgSend)([hc alloc], hi, mode, multi);
                if (eff && [eff respondsToSelector:@selector(setEnsuresSelectedAppLayoutUsesAnchorPointSpacePinning:)]) G1C_SendVB(eff, @selector(setEnsuresSelectedAppLayoutUsesAnchorPointSpacePinning:), YES);
            }
            break;
        }
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
    BOOL fire = NO;
    if (to && from) { if (phase == 2 || !animated) { G1B_SET(self, kRootEffStage, to); fire = YES; } }
    else if (!to && from) { if (phase == 3 || !animated) { G1B_SET(self, kRootEffStage, nil); fire = YES; } }
    else if (to && !from) { if (phase == 1 || !animated) { G1B_SET(self, kRootEffStage, to); fire = YES; } }
    else if (phase == 1 || !animated) { G1B_SET(self, kRootEffStage, nil); fire = YES; }
    if (BP_LogEnabled()) BP_Log(@"GLITCH stage bookkeeping: phase=%lld animated=%d from=%@ to=%@ -> effective stage layout=%@", phase, animated, G1C_DbgLayout(from), G1C_DbgLayout(to), G1C_DbgLayout(G1B_GET(self, kRootEffStage)));
    // 16.2 0x1c78192e8..0x1c78193f0: right AFTER the stage bookkeeping the handler appends SBInvalidateContinuousExposeIdentifiersEventResponse(from, to, animated) to [super handleEvent:]'s
    // result (_SBAppendSwitcherModifierResponse 0x1c773a35c), so the strip / switcher identifier lists are recomputed with the NEW stage layout in the same phase (the strip then
    // slides, animated for an animated transition).  The 16.0 controller updates the identifiers inline BEFORE this handler runs (blocks 0x1c5fc50c4 / 0x1c5fc5d9c), i.e. while the
    // stage still holds the old layout: the strip kept the old window until the final non-animated update at the end of the transition and popped (the 0.1 s flicker after an
    // app-to-app switch, log 19479b05 20:35:59-20:36:00: "ids update from=Reynard to=Filza animated=1 strip [.. Filza ..] -> [.. Filza ..]", then at phase 3 end "[.. Filza ..] -> [.. Reynard ..]").
    if (fire && gInvalidateRespCls && BP_OnName("g1c_invalidate")) {
        SEL ii = @selector(initWithTransitioningFromAppLayout:transitioningToAppLayout:animated:);
        if ([gInvalidateRespCls instancesRespondToSelector:ii]) {
            id inv = ((id (*)(id, SEL, id, id, BOOL))objc_msgSend)([gInvalidateRespCls alloc], ii, from, to, animated);
            if (inv) r = G1B_AppendTo(inv, r);
        }
    }
    return r;
}

// ---- handleTransitionEvent: peek child (0x1c7819470) ----
- (id)handleTransitionEvent:(id)event {
    id r = %orig;
    if (!G1C_ON() || !event || !G1C_Resp(event, @selector(toPeekConfiguration))) return r;
    long long phase = G1B_SendLL0(event, @selector(phase));
    BOOL animated = G1B_SendB0(event, @selector(isAnimated));
    long long cfg = G1B_SendLL0(event, @selector(toPeekConfiguration));
    if (BP_LogEnabled()) G1C_CloseTraceTransition(self, event, phase);
    if (BP_LogEnabled()) {
        id fl = G1C_Resp(self, @selector(floorModifier)) ? G1B_Send0(self, @selector(floorModifier)) : nil;
        BP_Log(@"GLITCH transition event: phase=%lld animated=%d gesture=%d modes %lld->%lld from=%@ to=%@ peek %lld->%lld floor=%@ effMode=%lld stage=%@", phase, animated,
               G1C_Resp(event, @selector(isGestureInitiated)) && G1B_SendB0(event, @selector(isGestureInitiated)), G1B_SendLL0(event, @selector(fromEnvironmentMode)), G1B_SendLL0(event, @selector(toEnvironmentMode)),
               G1C_DbgLayout(G1B_Send0(event, @selector(fromAppLayout))), G1C_DbgLayout(G1B_Send0(event, @selector(toAppLayout))), G1B_SendLL0(event, @selector(fromPeekConfiguration)), cfg,
               G1C_DbgCls(fl), G1C_Resp(self, @selector(_effectiveEnvironmentMode)) ? G1B_SendLL0(self, @selector(_effectiveEnvironmentMode)) : -1, G1C_DbgLayout(G1B_GET(self, kRootEffStage)));
    }
    if (phase == 3 && !G1C_PeekIsValid(cfg)) {
        // The peek is over: 16.2 retires the peek modifier through its own state (SBContinuousExposePeekSwitcherModifier -setState: after its dismissal transition modifier ended, 0x1c78e5354).
        // The log of a stage built by the add-window pick (43f88b77: "g1b: filtering: layout mixes peeked and other items" on every layout pass for the next 20 s in plain mode 3) shows our
        // peek child was never retired once the pick merged the new window into the peeked stage: its content modifier (pile layout of the app switcher child) kept laying out the whole stage,
        // so dragging one window moved the whole stack as a pile and the resize grabber never stayed (resize grabber visibility = NO in the app switcher modifier).  Retire it here.
        SEL by0 = NSSelectorFromString(@"childModifierByKey:");
        id stale = G1C_Resp(self, by0) ? G1B_Send1(self, by0, kG1CPeekKey) : nil;
        if (stale && [self respondsToSelector:@selector(removeChildModifier:)]) {
            if (BP_LogEnabled()) BP_Log(@"GLITCH peek child retired at the end of the transition (peek %lld -> none)", G1B_SendLL0(event, @selector(fromPeekConfiguration)));
            G1B_SendV1(self, @selector(removeChildModifier:), stale);
        }
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
// 16.2 0x1c7819ca8 and 0x1c7819cb0 are both `mov w0, #1 ; ret` (raw bytes 20 00 80 52 c0 03 5f d6): YES / YES.  The first port read them as NO ("UNSURE: returns 0", specs/group1b-modifiers.md).
// G2B's layout block hands them to the item container's content view (setShouldStretchToBounds: / setUsesNonuniformScaling:), i.e. the window's snapshot is stretched with the container bounds while
// the zoom-down / icon-zoom transitions animate them (SBFullScreenToHomeIconZoom frame = icon-shaped box) instead of keeping its size and snapping at the first update.
// Kill switch Backport162.off.g1c_fillbounds restores the old NO answers.
%new
- (BOOL)shouldScaleContentToFillBoundsAtIndex:(unsigned long long)i {
    BOOL r = BP_OnName("g1c_fillbounds");
    if (gCloseTraceOn && G1C_CloseTraceIsStage(self, G1C_LayoutAtIdx(self, i))) G1C_CloseTraceLine(5, @"fillBounds", i, r ? @"YES (16.2)" : @"NO (g1c_fillbounds off)");
    return r;
}
%new
- (BOOL)shouldUseNonuniformSnapshotScalingForLayoutRole:(long long)role inAppLayout:(id)layout { return BP_OnName("g1c_fillbounds"); }
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
// switcher -> home (ToHome / HomeToGrid): the Stage Manager cards leave the screen by HomeToGrid's own slide (specs/AUDIT-HOMEFLASH-0.6.8.md)
// ============================================================================================================
// HomeToGrid itself is byte-identical in 16.0 and 16.2 for frameForIndex:/scaleForIndex:/opacity (0x1c5f64fe8 / 0x1c73dafc4): the cards are hidden ONLY by the slide
// distance of the Stage Manager switcher copy (G1C_As_Distance, the exact 16.2 arithmetic on the pile cache) and by opacity 0 for layouts outside visibleAppLayouts.
// The 6.8 opacity guard and the "never stop short of the screen edge" floor that were added before the real causes were found (the 16.0 distance maths and the
// fly-in card, see below) are gone: 16.2 has neither.
// New in 16.2 on HomeToGrid: frameForLayoutRole:inAppLayout:withBounds: 0x1c73db18c and scaleForLayoutRole:inAppLayout: 0x1c73db488, plain pass-throughs to the multitasking
// modifier asked as a temporary child (the role frame inside a pile card comes from the pile cache of the switcher copy). 16.0 has neither (the chain's default answered).
static CGRect G1C_H2G_RoleFrame(id self, SEL _cmd, long long role, id layout, CGRect bounds) {
    id multi = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
    __block CGRect r = CGRectZero;
    if (!G1C_ON() || !multi || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)])
        return G1B_HasSuper(class_getSuperclass(NSClassFromString(@"SBHomeToGridSwitcherModifier")), _cmd) ? G1B_SUPER(CGRect, class_getSuperclass(NSClassFromString(@"SBHomeToGridSwitcherModifier")), self, _cmd, (struct objc_super *, SEL, long long, id, CGRect), role, layout, bounds) : r;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), multi, ^{
        r = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(multi, _cmd, role, layout, bounds);
    });
    return r;
}
static double G1C_H2G_RoleScale(id self, SEL _cmd, long long role, id layout) {
    id multi = G1C_Resp(self, @selector(multitaskingModifier)) ? G1B_Send0(self, @selector(multitaskingModifier)) : nil;
    __block double r = 1.0;
    if (!G1C_ON() || !multi || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)])
        return G1B_HasSuper(class_getSuperclass(NSClassFromString(@"SBHomeToGridSwitcherModifier")), _cmd) ? G1B_SUPER(double, class_getSuperclass(NSClassFromString(@"SBHomeToGridSwitcherModifier")), self, _cmd, (struct objc_super *, SEL, long long, id), role, layout) : r;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), multi, ^{
        r = ((double (*)(id, SEL, long long, id))objc_msgSend)(multi, _cmd, role, layout);
    });
    return r;
}
static void G1C_InstallHomeToGrid(void) {
    Class c = NSClassFromString(@"SBHomeToGridSwitcherModifier");
    if (!c) return;
    SEL fr = @selector(frameForLayoutRole:inAppLayout:withBounds:), sc = @selector(scaleForLayoutRole:inAppLayout:);
    class_addMethod(c, fr, (IMP)G1C_H2G_RoleFrame, "{CGRect={CGPoint=dd}{CGSize=dd}}64@0:8q16@24{CGRect={CGPoint=dd}{CGSize=dd}}32");      // no-op when the class defines it itself
    class_addMethod(c, sc, (IMP)G1C_H2G_RoleScale, "d32@0:8q16@24");
}
// ============================================================================================================
// 7.0  home gesture that ends on the home screen: the 16.0 "fly-in" card of SBHomeGestureToHomeSwitcherModifier
// ============================================================================================================
// ROOT CAUSE of "a dark window card (first group, NewTerm) clipped at the left edge of the home screen for ~0.75 s after a partial / quick home swipe":
//  * SBHomeGestureToHomeSwitcherModifier is the transition modifier for home-gesture 1 -> 1 (swipe up on the home screen, released back to home). Its answers
//    16.0 (0x1c5f44d40..0x1c5f44e48): visibleAppLayouts = { appLayouts.firstObject }, opacity = (index == 0 ? 1 : 0), scaleForIndex: = switcherSettings.offscreenCardScaleForFlyIn
//    (0.8, 0x1c65cdb48), frameForIndex: = [super frameForIndex:] with x - 1 -- ALL UNCONDITIONAL (the ivar _showingOrAnimatingCardsForFlyIn at +0x88 is only stored).
//  * 16.2 (0x1c73b93a4..0x1c73b9508) makes scale and the x - 1 conditional on that ivar (flag NO -> [super scaleForIndex:] / [super frameForIndex:]), and the Home gesture root
//    builds the modifier with flag = gesture.isShowingOrAnimatingCardsForFlyIn ? !isChamoisWindowingUIEnabled : NO (16.2 0x1c78ede2c..0x1c78ede40; 16.0 0x1c643c314 passes the raw flag).
//    So with Stage Manager the 16.2 card keeps the home floor's own scale (grid page scale 0.3 here / strip scale there) and stays off screen.
//  * On the port the flag is YES, the card (grid index 0 = most recent window, opacity 1) is drawn at the home floor frame (centre x ~ -227 after the 16.0 home floor's grid
//    slot, size 1056x646 with g2defsize) at scale 0.8: right edge -227 + 528 * 0.8 = 195 pt, bottom 210.5 + 323 * 0.8 = 469 pt, top above the screen = exactly the video.
// Fix: (a) the root's transition child gets flag = flag && !chamois in the 1 -> 1 branch (the only branch 16.2 masks), (b) the modifier's frameForIndex: / scaleForIndex: honour
// the flag like 16.2. Off switch: Backport162.off.g1c_flyin.   Logging (debug): "GLITCH home gesture ..." lines.
static IMP gFlyFrameOrig, gFlyScaleOrig;
static Class gFlyCls;
static NSString *gFlyLastSig[2];
static BOOL G1C_Fly_Stock(id self) {
    return !G1C_ON() || !BP_OnName("g1c_flyin") || G1C_IvarBool(self, "_showingOrAnimatingCardsForFlyIn");
}
static CGRect G1C_Fly_Frame(id self, SEL _cmd, unsigned long long i) {
    BOOL stock = G1C_Fly_Stock(self);
    CGRect f = stock ? ((CGRect (*)(id, SEL, unsigned long long))gFlyFrameOrig)(self, _cmd, i)
                     : G1B_SUPER(CGRect, class_getSuperclass(gFlyCls), self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    if (i < 2 && BP_LogEnabled()) {
        double sc = G1C_Resp(self, @selector(scaleForIndex:)) ? ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), i) : 0.0;
        NSString *sig = [NSString stringWithFormat:@"flyIn=%d frame=%@ scale=%.3f", (int)G1C_IvarBool(self, "_showingOrAnimatingCardsForFlyIn"), NSStringFromCGRect(f), sc];
        BOOL changed = NO;
        @synchronized(@"BP162.fly") { if (![gFlyLastSig[i] isEqualToString:sig]) { gFlyLastSig[i] = sig; changed = YES; } }
        if (changed) BP_Log(@"GLITCH home gesture to home idx=%llu: %@ (answered by %@)", i, sig, stock ? @"16.0 fly-in" : @"home floor (16.2)");
    }
    return f;
}
static double G1C_Fly_Scale(id self, SEL _cmd, unsigned long long i) {
    if (G1C_Fly_Stock(self)) return ((double (*)(id, SEL, unsigned long long))gFlyScaleOrig)(self, _cmd, i);
    return G1B_SUPER(double, class_getSuperclass(gFlyCls), self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static void G1C_InstallFlyInFix(void) {
    gFlyCls = NSClassFromString(@"SBHomeGestureToHomeSwitcherModifier");
    if (!gFlyCls || !class_getInstanceVariable(gFlyCls, "_showingOrAnimatingCardsForFlyIn")) return;
    struct { SEL sel; IMP imp; IMP *orig; Class cls; } t[] = {
        { @selector(frameForIndex:), (IMP)G1C_Fly_Frame, &gFlyFrameOrig, gFlyCls },
        { @selector(scaleForIndex:), (IMP)G1C_Fly_Scale, &gFlyScaleOrig, gFlyCls },
    };
    for (size_t k = 0; k < sizeof t / sizeof t[0]; k++) if (!class_getInstanceMethod(t[k].cls, t[k].sel)) { gFlyCls = Nil; return; }      // not the expected 16.0 shape: stay stock
    for (size_t k = 0; k < sizeof t / sizeof t[0]; k++) {
        Method m = class_getInstanceMethod(t[k].cls, t[k].sel);
        IMP old = class_replaceMethod(t[k].cls, t[k].sel, t[k].imp, method_getTypeEncoding(m));
        *t[k].orig = old ?: method_getImplementation(m);
    }
}
// ============================================================================================================
// 7.1  Home gesture family and the PIP transitions                                          (switches: g1c_homegesture, g1c_pip)
// ============================================================================================================
// 16.2 ported 1:1 (20C65 / 20A8372 addresses in the comments):
//   SBHomeGestureRootSwitcherModifier.gestureChildModifierForGestureEvent:activeTransitionModifier:  0x1c78edb44 (160 0x1c643c05c)
//   SBHomeGestureRootSwitcherModifier.transitionChildModifierForMainTransitionEvent:activeGestureModifier: 0x1c78edd24 (160 0x1c643c20c)
//   SBHomeGestureSwitcherModifier.didMoveToParentModifier: 0x1c74b4138 (insertion over identical 16.0 code), appLayoutsToCacheSnapshots 0x1c74b7b80, appLayoutsToCacheFullsizeSnapshots 0x1c74b7c54
//   SBReduceMotionHomeGestureSwitcherModifier: scaleForIndex: 0x1c78692d4, cornerRadiiForIndex: 0x1c7869470, homeScreenBackdropBlurType 0x1c78694d8 + shouldProvideBlur / laysOutNeighboringCards
//   SBFullScreenToHomePIPSwitcherModifier (init 0x1c77ded80, transitionWillBegin 0x1c77def90, clippingFrameForLayoutRole.. 0x1c77df4b8, clipsToBoundsAtIndex: 0x1c77df5f8, visibleAppLayouts 0x1c77df5fc,
//     anchorPointForIndex: .. adjustedSpaceAccessoryView* 0x1c77df894..0x1c77dfb90, force flag 0x1c77dff8c)
//   SBPIPRestoreToFullScreenSwitcherModifier (init 0x1c764d4ac, transitionWillBegin 0x1c764d5d0, frameForIndex: 0x1c764d6fc, clippingFrameForIndex: 0x1c764d7d4, clippingFrameForLayoutRole.. 0x1c764d8d8,
//     _insetFrameForDiffuseShadowRadius: 0x1c764da68, animationAttributesForLayoutElement: 0x1c764dc18, opacityForLayoutRole.. 0x1c764e140, _is{From,To,ToOrFrom}AppLayout[Index]: 0x1c764e1d0..0x1c764e324, flags, anchor family)
// Methods 16.2 left byte-identical (verified by annotated listing diffs: PIP completesWhenChildrenComplete / didMoveToParentModifier: / handleHideMorphToPIPAppLayoutEvent: / scaleForIndex: / rotationAngleForIndex: /
// cornerRadiiForIndex: / opacity.. / topMostLayoutElements; PIPRestore scaleForIndex: / visibleAppLayouts / cornerRadiiForIndex:(reordered only) / _layoutSettings) stay the 16.0 methods of the same class. The 16.0
// private `_isToAppLayout:` / `_isFromAppLayout:` (index form) stay too, because the unchanged 16.0 methods call them; the 16.2 object form `_isToAppLayout:` is a static helper here (nobody else calls it).
static Class gHgRootC, gHgSwC, gHgRmC, gPipC, gPipRC;
static IMP gHgRootTransOrig, gHgRootChildOrig, gHgSwDidMoveOrig;
static BOOL G1C_HG_On(void) { return G1C_ON() && BP_OnName("g1c_homegesture"); }
static void G1C_SendVRect(id o, SEL s, CGRect r) { if (o && [o respondsToSelector:s]) ((void (*)(id, SEL, CGRect))objc_msgSend)(o, s, r); }

// ---- event / response data the 16.0 classes lack ----
static char kEvPipRole, kSetupBBox;
static long long G1C_Ev_GetPipRole(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kEvPipRole) longLongValue]; }
static void G1C_Ev_SetPipRole(id self, SEL _cmd, long long v) { G1B_SET(self, kEvPipRole, @(v)); }
static CGRect G1C_Setup_GetBBox(id self, SEL _cmd) { NSValue *v = G1B_GET(self, kSetupBBox); return v ? [v CGRectValue] : CGRectZero; }
static void G1C_Setup_SetBBox(id self, SEL _cmd, CGRect r) { G1B_SET(self, kSetupBBox, [NSValue valueWithCGRect:r]); }

// ---- SBHomeGestureRootSwitcherModifier.gestureChildModifierForGestureEvent:activeTransitionModifier:  (0x1c78edb44) ----
static id G1C_HGR_GestureChild(id self, SEL _cmd, id event, id active) {
    if (!G1C_HG_On()) return ((id (*)(id, SEL, id, id))gHgRootChildOrig)(self, _cmd, event, active);
    id sel = G1B_Send0(self, @selector(selectedAppLayout));
    long long mode = G1B_SendLL0(self, @selector(currentEnvironmentMode));
    Class arc = NSClassFromString(@"SBArcSwipeSwitcherModifier");
    BOOL lastArc = active && arc && [active isKindOfClass:arc], continuing = active != nil;
    BOOL scrunch = G1B_SendLL0(event, @selector(type)) == 4, reduce = G1B_SendB0(self, @selector(isReduceMotionEnabled));
    id gid = G1B_Send0(event, @selector(gestureID));
    BOOL chamois = G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled));
    if (reduce) {
        Class c = NSClassFromString(@"SBReduceMotionHomeGestureSwitcherModifier");
        SEL i = NSSelectorFromString(@"initWithGestureID:selectedAppLayout:startingEnvironmentMode:scrunchInitiated:continuingGesture:lastGestureWasAnArcSwipe:");
        id o = (c && [c instancesRespondToSelector:i]) ? ((id (*)(id, SEL, id, id, long long, BOOL, BOOL, BOOL))objc_msgSend)([c alloc], i, gid, sel, mode, scrunch, continuing, lastArc) : nil;
        G1C_SendVB(o, NSSelectorFromString(@"setShouldProvideBlur:"), !chamois);
        G1C_SendVB(o, NSSelectorFromString(@"setLaysOutNeighboringCards:"), !chamois);
        return o;
    }
    G1C_CloseTraceArm(mode);                                                         // diagnostics only (BP_LogEnabled)
    id mm = G1C_NewMultiOf(self);
    Class c = NSClassFromString(@"SBHomeGestureSwitcherModifier");
    SEL i = NSSelectorFromString(@"initWithGestureID:selectedAppLayout:startingEnvironmentMode:multitaskingModifier:scrunchInitiated:continuingGesture:lastGestureWasAnArcSwipe:");
    id o = (c && [c instancesRespondToSelector:i]) ? ((id (*)(id, SEL, id, id, long long, id, BOOL, BOOL, BOOL))objc_msgSend)([c alloc], i, gid, sel, mode, mm, scrunch, continuing, lastArc) : nil;
    G1C_SendVB(o, NSSelectorFromString(@"setProvidesHomeScreenDimmingAlpha:"), !chamois);
    return o;
}

// ---- SBHomeGestureRootSwitcherModifier.transitionChildModifierForMainTransitionEvent:activeGestureModifier:  (0x1c78edd24) ----
static id G1C_HG_FlyInFallback(id tid) {                                              // 0x1c78ee144
    Class c = NSClassFromString(@"SBHomeGestureToHomeSwitcherModifier");
    SEL s = NSSelectorFromString(@"initWithTransitionID:showingOrAnimatingCardsForFlyIn:");
    return (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, BOOL))objc_msgSend)([c alloc], s, tid, YES) : nil;
}
static id G1C_HG_Wrap(id tid, id sel, id zoom, long long fromMode, CGPoint velocity, BOOL adjust) {            // 0x1c78ee194 / 0x1c78ee0bc: SBHomeGestureToZoomDownSwitcherModifier
    Class c = NSClassFromString(@"SBHomeGestureToZoomDownSwitcherModifier");
    SEL s = NSSelectorFromString(@"initWithTransitionID:appLayout:nonGestureInitiatedZoomModifier:effectiveStartingEnvironmentMode:liftOffVelocity:adjustAnimationAttributes:");
    return (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, id, long long, CGPoint, BOOL))objc_msgSend)([c alloc], s, tid, sel, zoom, fromMode, velocity, adjust) : nil;
}
static id G1C_PIP_New(id tid, id appLayout, long long role);
static id G1C_HGR_TransitionChild(id self, SEL _cmd, id event, id gestureMod) {
    if (!G1C_HG_On()) return ((id (*)(id, SEL, id, id))gHgRootTransOrig)(self, _cmd, event, gestureMod);
    long long to = G1B_SendLL0(event, @selector(toEnvironmentMode)), from = G1B_SendLL0(event, @selector(fromEnvironmentMode));
    id tid = G1B_Send0(event, @selector(transitionID)), sel = G1B_Send0(self, @selector(selectedAppLayout));
    long long cur = G1B_SendLL0(self, @selector(currentEnvironmentMode));
    long long style = G1B_SendLL0(G1B_Send0(self, @selector(switcherSettings)), NSSelectorFromString(@"effectiveSwitcherStyle"));
    BOOL reduce = G1B_SendB0(self, @selector(isReduceMotionEnabled)), chamois = G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled)), flyIn = NO;
    CGPoint velo = CGPointZero, trans = CGPointZero;
    if (!reduce) {
        Class hs = NSClassFromString(@"SBHomeGestureSwitcherModifier");
        if (!gestureMod || !hs || ![gestureMod isKindOfClass:hs]) {                  // 16.2 NSAssert (SBHomeGestureRootSwitcherModifier.m line 0x5f): "the gesture modifier should be an instance of SBHomeGestureSwitcherModifier"
            if (BP_LogEnabled()) BP_Log(@"GUARD home gesture root: gesture modifier %@ is not an SBHomeGestureSwitcherModifier (16.2 asserts)", G1C_DbgCls(gestureMod));
            return nil;
        }
        flyIn = G1B_SendB0(gestureMod, @selector(isShowingOrAnimatingCardsForFlyIn)) ? !chamois : NO;
        velo = G1C_SendPoint0(gestureMod, @selector(liftOffVelocityForGestureEnd));
        trans = G1C_SendPoint0(gestureMod, @selector(liftOffTranslationForGestureEnd));
    }
    BOOL pin = G1B_SendB0(self, NSSelectorFromString(@"ensuresSelectedAppLayoutUsesAnchorPointSpacePinning"));
    SEL setForce = NSSelectorFromString(@"setShouldForceDefaultAnchorPointForTransition:");
    if (to == 3) {                                                                   // -> app switcher
        Class c = NSClassFromString(@"SBArcSwipeSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:fromAppLayout:toAppLayout:pinSpaceCornerRadiiToDisplayCornerRadii:");
        return (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, id, BOOL))objc_msgSend)([c alloc], s, tid, G1B_Send0(event, @selector(fromAppLayout)), G1B_Send0(event, @selector(toAppLayout)), !chamois) : nil;
    }
    if (to == 2) {                                                                   // -> multitasking (0x1c78edf08)
        BOOL resigns = G1B_SendB0(self, @selector(resignsTransitionIntoAppSwitcher));
        if (resigns && style != 1 && !G1C_PeekIsValid(G1B_SendLL0(event, @selector(toPeekConfiguration)))) return nil;
        id mm = G1C_NewMultiOf(self);
        Class c = NSClassFromString(@"SBHomeGestureToSwitcherSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:multitaskingModifier:selectedAppLayout:startingEnvironmentMode:liftOffVelocity:liftOffTranslation:adjustAppLayoutsBeforeTransition:");
        return (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, id, long long, CGPoint, CGPoint, BOOL))objc_msgSend)([c alloc], s, tid, mm, sel, cur, velo, trans, chamois) : nil;
    }
    if (to != 1) return nil;
    if (from == 1) {                                                                 // 1 -> 1: the fly-in card
        Class c = NSClassFromString(@"SBHomeGestureToHomeSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:showingOrAnimatingCardsForFlyIn:");
        return (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, BOOL))objc_msgSend)([c alloc], s, tid, flyIn) : nil;
    }
    id zoom = nil; BOOL adjust = YES;
    if (G1B_SendB0(event, @selector(isMorphToPIPTransition))) {                      // 0x1c78edf94
        if (!sel) return G1C_HG_FlyInFallback(tid);
        zoom = G1C_PIP_New(tid, sel, G1B_SendLL0(event, NSSelectorFromString(@"morphingPIPLayoutRole")));
        if (chamois) G1C_SendVB(zoom, setForce, YES);
    } else if (((BOOL (*)(id, SEL, id, id))objc_msgSend)(self, NSSelectorFromString(@"shouldZoomToSystemApertureForEvent:activeLayout:"), event, sel)) {                                // shouldZoomToSystemApertureForEvent:activeLayout:  0x1c78edff8
        if (!sel) return G1C_HG_FlyInFallback(tid);
        NSArray *ls = G1B_Send0(self, @selector(appLayouts));
        unsigned long long idx = [ls indexOfObject:sel];
        CGRect fr = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), idx);
        double sc = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), idx);
        Class c = NSClassFromString(@"SBFullScreenToHomeSystemApertureSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:zoomModifier:appLayout:direction:expandedCardFrame:cardScale:cardVelocity:");
        zoom = (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, id, long long, CGRect, double, CGPoint))objc_msgSend)([c alloc], s, tid, nil, sel, 1, fr, sc, velo) : nil;
        adjust = NO;
    } else {
        CGRect icon = G1B_SendB0(event, NSSelectorFromString(@"isIconZoomDisabled")) ? CGRectNull
                      : ((CGRect (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"homeScreenIconFrameForAppLayout:"), sel);
        if (CGRectIsNull(icon) || reduce) {                                          // centre zoom down (0x1c78ee0f4): returned as is
            if (!sel) return G1C_HG_FlyInFallback(tid);
            double factor = G1B_Dbl0(G1B_Send0(self, NSSelectorFromString(@"homeGestureSettings")), NSSelectorFromString(@"homeGestureCenterZoomDownCenterYOffsetFactor"));
            Class c = NSClassFromString(@"SBFullScreenToHomeCenterZoomDownSwitcherModifier");
            SEL s = NSSelectorFromString(@"initWithTransitionID:appLayout:offsetYPercentOfScreenHeight:");
            id cz = (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, double))objc_msgSend)([c alloc], s, tid, sel, factor) : nil;
            G1C_SendVB(cz, setForce, pin);
            return cz;
        }
        Class c = NSClassFromString(@"SBFullScreenToHomeIconZoomSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:appLayout:direction:");
        if (!sel) return G1C_HG_FlyInFallback(tid);
        zoom = (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, long long))objc_msgSend)([c alloc], s, tid, sel, 1) : nil;
        G1C_SendVB(zoom, setForce, pin);
    }
    return G1C_HG_Wrap(tid, sel, zoom, from, velo, adjust);
}

// ---- SBHomeGestureSwitcherModifier ----
// didMoveToParentModifier: (16.2 0x1c74b4138): the 16.0 body (0x1c6038bac) is identical (annotated listing diff) except for ONE insertion in the "starting from home" branch: when the gesture does not provide the
// home screen dimming alpha (Stage Manager), _toHomeScreenAlpha = [super homeScreenAlpha] and _toHomeScreenBlurProgress = animationSettings.homeScreenBlurProgressForMode:2 replace the values read from the
// multitasking child. Nothing between the insertion and the end of the method reads those two ivars, so the insertion runs after the (identical) 16.0 code.
static void G1C_HGS_DidMove(id self, SEL _cmd, id parent) {
    ((void (*)(id, SEL, id))gHgSwDidMoveOrig)(self, _cmd, parent);
    if (!G1C_HG_On() || !parent || G1C_IvarLL(self, "_startingEnvironmentMode") != 1 || G1C_IvarBool(self, "_providesHomeScreenDimmingAlpha")) return;
    G1C_SetIvarD(self, "_toHomeScreenAlpha", G1B_SUPER(double, class_getSuperclass(gHgSwC), self, @selector(homeScreenAlpha), (struct objc_super *, SEL)));
    id anim = G1B_Send0(G1B_Send0(self, @selector(switcherSettings)), @selector(animationSettings));
    G1C_SetIvarD(self, "_toHomeScreenBlurProgress", ((double (*)(id, SEL, long long))objc_msgSend)(anim, NSSelectorFromString(@"homeScreenBlurProgressForMode:"), 2));
}
// 0x1c74b7b80  (the 16.0 version asserted that _selectedAppLayout is in appLayouts; 16.2 starts at 0)
static id G1C_HGS_CacheSnapshots(id self, SEL _cmd) {
    NSArray *ls = G1B_Send0(self, @selector(appLayouts));
    if (ls.count == 0) return @[];
    id sel = G1C_IvarObj(self, "_selectedAppLayout");
    unsigned long long idx = sel ? [ls indexOfObject:sel] : 0;
    if (idx == NSNotFound) idx = 0;
    id sw = G1B_Send0(self, @selector(switcherSettings));
    long long n = G1B_SendLL0(sw, NSSelectorFromString(@"numberOfSnapshotsToAlwaysKeepAround"));
    if (n == 0) n = G1B_SendLL0(sw, NSSelectorFromString(@"numberOfSnapshotsToCacheInSwitcher"));
    return ((id (*)(id, SEL, NSRange, long long, BOOL))objc_msgSend)(self, NSSelectorFromString(@"appLayoutsToCacheSnapshotsWithVisibleRange:numberOfSnapshotsToCache:biasForward:"), NSMakeRange(idx, 1), n, YES);
}
// 0x1c74b7c54  (NSNotFound -> the first layout only, like "no selection")
static id G1C_HGS_CacheFullsize(id self, SEL _cmd) {
    NSArray *ls = G1B_Send0(self, @selector(appLayouts));
    id sel = G1C_IvarObj(self, "_selectedAppLayout");
    NSUInteger loc = 0, len = 1;
    if (sel) {
        NSUInteger idx = [ls indexOfObject:sel];
        if (idx == 0) { loc = 0; len = 2; }
        else if (idx != NSNotFound) { loc = idx - 1; len = 3; }
    }
    return [ls subarrayWithRange:NSIntersectionRange(NSMakeRange(loc, len), NSMakeRange(0, ls.count))];
}

// ---- SBReduceMotionHomeGestureSwitcherModifier ----
static char kRmBlur, kRmNeighbors;
static BOOL G1C_Rm_GetBlur(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kRmBlur) boolValue]; }
static void G1C_Rm_SetBlur(id self, SEL _cmd, BOOL v) { G1B_SET(self, kRmBlur, @(v)); }
static BOOL G1C_Rm_GetNeighbors(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kRmNeighbors) boolValue]; }
static void G1C_Rm_SetNeighbors(id self, SEL _cmd, BOOL v) { G1B_SET(self, kRmNeighbors, @(v)); }
static double G1C_Rm_Scale(id self, SEL _cmd, unsigned long long i) {                 // 0x1c78692d4
    if (G1C_Rm_GetNeighbors(self, 0)) return 1.0;
    return G1B_SUPER(double, class_getSuperclass(gHgRmC), self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static G1CRadii G1C_Rm_Radii(id self, SEL _cmd, unsigned long long i) {               // 0x1c7869470
    if (G1C_Rm_GetNeighbors(self, 0)) { double r = G1B_Dbl0(self, NSSelectorFromString(@"displayCornerRadius")); G1CRadii o = { r, r, r, r }; return o; }
    return G1B_SUPER(G1CRadii, class_getSuperclass(gHgRmC), self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static long long G1C_Rm_BlurType(id self, SEL _cmd) {                                 // 0x1c78694d8
    if (G1C_Rm_GetBlur(self, 0)) return G1C_IvarLL(self, "_startingEnvironmentMode") == 1 ? 2 : 1;
    return G1B_SUPER(long long, class_getSuperclass(gHgRmC), self, _cmd, (struct objc_super *, SEL));
}

// ---- SBFullScreenToHomePIPSwitcherModifier ----
static char kPipRole, kPipForce;
static Class gPipSuper;
static id G1C_PIP_New(id tid, id appLayout, long long role) {
    Class c = NSClassFromString(@"SBFullScreenToHomePIPSwitcherModifier");
    SEL s4 = NSSelectorFromString(@"initWithTransitionID:zoomModifier:appLayout:layoutRole:"), s3 = NSSelectorFromString(@"initWithTransitionID:zoomModifier:appLayout:");
    if (c && [c instancesRespondToSelector:s4]) return ((id (*)(id, SEL, id, id, id, long long))objc_msgSend)([c alloc], s4, tid, nil, appLayout, role);
    return (c && [c instancesRespondToSelector:s3]) ? ((id (*)(id, SEL, id, id, id))objc_msgSend)([c alloc], s3, tid, nil, appLayout) : nil;      // g1c_pip off: the stock 16.0 init
}
// 0x1c77ded80: the 16.0 3-argument init (0x1c633b448) is this body without the layout role (annotated listing diff); the role is write-only state in 16.2
static id G1C_Pip_Init4(id self, SEL _cmd, id tid, id zoom, id appLayout, long long role) {
    id me = ((id (*)(id, SEL, id, id, id))objc_msgSend)(self, NSSelectorFromString(@"initWithTransitionID:zoomModifier:appLayout:"), tid, zoom, appLayout);
    if (me) G1B_SET(me, kPipRole, @(role));
    return me;
}
static BOOL G1C_Pip_GetForce(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kPipForce) boolValue]; }
static void G1C_Pip_SetForce(id self, SEL _cmd, BOOL v) { G1B_SET(self, kPipForce, @(v)); }
static BOOL G1C_Pip_IsSel(id self, unsigned long long i) { return ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(self, NSSelectorFromString(@"_isIndexSelectedAppLayout:"), i); }
static id G1C_Pip_WillBegin(id self, SEL _cmd) {                                      // 0x1c77def90
    id r = G1B_SUPER(id, gPipSuper, self, _cmd, (struct objc_super *, SEL));
    Class gc = NSClassFromString(@"SBSwitcherModifierEventResponse"), sc = NSClassFromString(@"SBSetupPIPMorphingSwitcherEventResponse");
    id group = [[gc alloc] init], hide = G1C_NewStripsPresentationResponse(0, 1), setup = [[sc alloc] init];
    id model = G1B_Send1(self, NSSelectorFromString(@"overlappingModelForAppLayout:"), G1C_IvarObj(self, "_appLayout"));
    G1C_SendVRect(setup, NSSelectorFromString(@"setAppLayoutBoundingBox:"), model ? G1C_SendRect0(model, NSSelectorFromString(@"boundingBox")) : CGRectZero);
    id r2 = G1B_Append(hide, r);
    G1B_SendV1(group, NSSelectorFromString(@"addChildResponse:"), r2);
    G1B_SendV1(group, NSSelectorFromString(@"addChildResponse:"), G1B_NewUpdateLayoutResponse(2, 2));
    G1B_SendV1(group, NSSelectorFromString(@"addChildResponse:"), setup);
    return G1C_AppendResp(r, group);
}
static CGRect G1C_Pip_ClipRole(id self, SEL _cmd, long long role, id layout, unsigned long long idx, CGRect bounds) {      // 0x1c77df4b8
    if (!G1C_Pip_IsSel(self, idx) || G1B_SendB0(self, @selector(isPreparingLayout)))
        return G1B_SUPER(CGRect, gPipSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long, CGRect), role, layout, idx, bounds);
    CGRect clip = G1C_SendRect0(self, NSSelectorFromString(@"morphToPIPClippingFrame"));
    CGRect f = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(self, @selector(frameForLayoutRole:inAppLayout:withBounds:), role, layout, bounds);
    return CGRectOffset(clip, -f.origin.x, -f.origin.y);
}
static BOOL G1C_Pip_Clips(id self, SEL _cmd, unsigned long long i) { return G1C_Pip_IsSel(self, i); }                  // 0x1c77df5f8
static id G1C_Pip_Visible(id self, SEL _cmd) {                                                                          // 0x1c77df5fc
    id s = G1B_SUPER(id, gPipSuper, self, _cmd, (struct objc_super *, SEL));
    return G1B_Send1(s, @selector(setByAddingObject:), G1C_IvarObj(self, "_appLayout"));
}
static CGPoint G1C_Pip_Anchor(id self, SEL _cmd, unsigned long long i) {                                               // 0x1c77df894
    if (G1C_Pip_GetForce(self, 0) && G1C_Pip_IsSel(self, i)) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gPipSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static BOOL G1C_Pip_Pin(id self, SEL _cmd, unsigned long long i) {                                                      // 0x1c77df908 / 0x1c77df97c
    if (G1C_Pip_GetForce(self, 0) && G1C_Pip_IsSel(self, i)) return YES;
    return G1B_SUPER(BOOL, gPipSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_Pip_Persp(id self, SEL _cmd, id layout) {                                                             // 0x1c77df9f0
    if (G1C_Pip_GetForce(self, 0) && [layout isEqual:G1C_IvarObj(self, "_appLayout")]) return 0.0;
    return G1B_SUPER(double, gPipSuper, self, _cmd, (struct objc_super *, SEL, id), layout);
}
static CGRect G1C_Pip_AccFrame(id self, SEL _cmd, CGRect f, id layout) {                                                // 0x1c77dfa80
    id al = G1C_IvarObj(self, "_appLayout");
    if (G1C_Pip_GetForce(self, 0) && [layout isEqual:al]) {
        NSUInteger i = [(NSArray *)G1B_Send0(self, @selector(appLayouts)) indexOfObject:al];
        return ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), i);
    }
    return G1B_SUPER(CGRect, gPipSuper, self, _cmd, (struct objc_super *, SEL, CGRect, id), f, layout);
}
static CGPoint G1C_Pip_AccAnchor(id self, SEL _cmd, CGPoint p, id layout) {                                             // 0x1c77dfb90
    if (G1C_Pip_GetForce(self, 0) && [layout isEqual:G1C_IvarObj(self, "_appLayout")]) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gPipSuper, self, _cmd, (struct objc_super *, SEL, CGPoint, id), p, layout);
}

// ---- SBPIPRestoreToFullScreenSwitcherModifier ----
static char kPrRole, kPrBBox, kPrShadow, kPrForce;
static Class gPipRSuper;
static BOOL G1C_PipR_Flag(id self, char *k) { return [(NSNumber *)objc_getAssociatedObject(self, k) boolValue]; }
static id G1C_PipR_Init5(id self, SEL _cmd, id tid, id zoom, id from, id to, long long role) {                          // 0x1c764d4ac (16.0 init 0x1c61bf2cc is the same body without the role)
    id me = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(self, NSSelectorFromString(@"initWithTransitionID:zoomModifier:fromAppLayout:toAppLayout:"), tid, zoom, from, to);
    if (me) G1B_SET(me, kPrRole, @(role));
    return me;
}
static BOOL G1C_PipR_GetShadow(id self, SEL _cmd) { return G1C_PipR_Flag(self, &kPrShadow); }
static void G1C_PipR_SetShadow(id self, SEL _cmd, BOOL v) { G1B_SET(self, kPrShadow, @(v)); }
static BOOL G1C_PipR_GetForce(id self, SEL _cmd) { return G1C_PipR_Flag(self, &kPrForce); }
static void G1C_PipR_SetForce(id self, SEL _cmd, BOOL v) { G1B_SET(self, kPrForce, @(v)); }
static BOOL G1C_PipR_IsToObj(id self, id layout) { return [layout isEqual:G1C_IvarObj(self, "_toAppLayout")]; }                       // 0x1c764e2a8
static BOOL G1C_PipR_IsFromObj(id self, id layout) { return [layout isEqual:G1C_IvarObj(self, "_fromAppLayout")]; }
static BOOL G1C_PipR_IsToOrFromObj(id self, SEL _cmd, id layout) { return G1C_PipR_IsFromObj(self, layout) || G1C_PipR_IsToObj(self, layout); }      // 0x1c764e2c0 (from first)
static id G1C_PipR_LayoutAt(id self, unsigned long long i) { NSArray *ls = G1B_Send0(self, @selector(appLayouts)); return i < ls.count ? ls[i] : nil; }
static BOOL G1C_PipR_IsFromIdx(id self, SEL _cmd, unsigned long long i) { return G1C_PipR_IsFromObj(self, G1C_PipR_LayoutAt(self, i)); }          // 0x1c764e1d0
static BOOL G1C_PipR_IsToIdx(id self, SEL _cmd, unsigned long long i) { return G1C_PipR_IsToObj(self, G1C_PipR_LayoutAt(self, i)); }              // 0x1c764e23c
static BOOL G1C_PipR_IsToOrFromIdx(id self, SEL _cmd, unsigned long long i) { return G1C_PipR_IsToOrFromObj(self, 0, G1C_PipR_LayoutAt(self, i)); }  // 0x1c764e324
static id G1C_PipR_WillBegin(id self, SEL _cmd) {                                     // 0x1c764d5d0
    id r = G1B_SUPER(id, gPipRSuper, self, _cmd, (struct objc_super *, SEL));
    Class gc = NSClassFromString(@"SBSwitcherModifierEventResponse"), sc = NSClassFromString(@"SBSetupPIPMorphingSwitcherEventResponse");
    id group = [[gc alloc] init], setup = [[sc alloc] init];
    G1B_SendV1(group, NSSelectorFromString(@"addChildResponse:"), G1B_NewUpdateLayoutResponse(2, 2));
    id model = G1B_Send1(self, NSSelectorFromString(@"overlappingModelForAppLayout:"), G1C_IvarObj(self, "_toAppLayout"));
    CGRect bb = model ? G1C_SendRect0(model, NSSelectorFromString(@"boundingBox")) : CGRectZero;
    G1B_SET(self, kPrBBox, [NSValue valueWithCGRect:bb]);
    G1C_SendVRect(setup, NSSelectorFromString(@"setAppLayoutBoundingBox:"), bb);
    G1B_SendV1(group, NSSelectorFromString(@"addChildResponse:"), setup);
    return G1C_AppendResp(r, group);
}
static CGRect G1C_PipR_Frame(id self, SEL _cmd, unsigned long long i) {               // 0x1c764d6fc
    if (G1C_PipR_IsFromIdx(self, 0, i)) return G1C_SendRect0(self, @selector(containerViewBounds));
    if (G1B_SendB0(self, @selector(isPreparingLayout)) && G1C_PipR_IsToIdx(self, 0, i)) {
        NSValue *v = G1B_GET(self, kPrBBox);
        CGSize sz = v ? [v CGRectValue].size : CGSizeZero;
        CGPoint c = G1C_SendPoint0(self, NSSelectorFromString(@"morphToPIPTargetCenter"));
        return CGRectMake(c.x - sz.width * 0.5, c.y - sz.height * 0.5, sz.width, sz.height);      // _SBUnintegralizedRectCenteredAboutPoint(SBRectWithSize(size), center)
    }
    return G1B_SUPER(CGRect, gPipRSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGRect G1C_PipR_Inset(id self, SEL _cmd, CGRect r) {                           // 0x1c764da68
    double rad = G1B_Dbl0(G1C_ChamoisSettings(self), NSSelectorFromString(@"diffuseShadowRadius")), d = rad * -2.8;       // 0x1c7a91690
    return CGRectInset(CGRectMake(0, 0, r.size.width, r.size.height), d, d);
}
static CGRect G1C_PipR_ClipIdx(id self, SEL _cmd, unsigned long long i, CGRect bounds) {        // 0x1c764d7d4
    BOOL prep = G1B_SendB0(self, @selector(isPreparingLayout)), to = G1C_PipR_IsToIdx(self, 0, i);
    if (prep && to) return G1C_SendRect0(self, NSSelectorFromString(@"morphToPIPClippingFrame"));
    CGRect f = G1B_SUPER(CGRect, gPipRSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long, CGRect), i, bounds);
    if (!to) return f;
    CGRect r = CGRectMake(0, 0, f.size.width, f.size.height);
    return G1C_PipR_GetShadow(self, 0) ? G1C_PipR_Inset(self, 0, r) : r;
}
static CGRect G1C_PipR_ClipRole(id self, SEL _cmd, long long role, id layout, unsigned long long idx, CGRect bounds) {      // 0x1c764d8d8
    BOOL to = G1C_PipR_IsToObj(self, layout);
    if (G1B_SendB0(self, @selector(isPreparingLayout)) && to) {
        CGRect f = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(self, @selector(frameForLayoutRole:inAppLayout:withBounds:), role, layout, bounds);
        return CGRectOffset(G1C_SendRect0(self, NSSelectorFromString(@"morphToPIPClippingFrame")), -f.origin.x, -f.origin.y);
    }
    if (to) {
        CGRect f = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(self, @selector(frameForLayoutRole:inAppLayout:withBounds:), role, layout, bounds);
        CGRect r = CGRectMake(0, 0, f.size.width, f.size.height);
        return G1C_PipR_GetShadow(self, 0) ? G1C_PipR_Inset(self, 0, r) : r;
    }
    return G1B_SUPER(CGRect, gPipRSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long, CGRect), role, layout, idx, bounds);
}
static BOOL G1C_PipR_Clips(id self, SEL _cmd, unsigned long long i) { return G1C_PipR_IsToIdx(self, 0, i); }                  // 0x1c764daf0
static id G1C_PipR_Anim(id self, SEL _cmd, id element) {                                                                       // 0x1c764dc18
    id a = [(id)G1B_SUPER(id, gPipRSuper, self, _cmd, (struct objc_super *, SEL, id), element) mutableCopy];
    id ls = G1B_Send0(self, NSSelectorFromString(@"_layoutSettings"));
    G1B_SendV1(a, NSSelectorFromString(@"setLayoutSettings:"), ls);
    G1B_SendV1(a, NSSelectorFromString(@"setClippingSettings:"), G1B_Send0(self, NSSelectorFromString(@"_layoutSettings")));
    return a;
}
static double G1C_PipR_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long idx) {                         // 0x1c764e140
    if (G1C_PipR_IsToOrFromIdx(self, 0, idx)) return 1.0;
    return G1B_SUPER(double, gPipRSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, layout, idx);
}
static CGPoint G1C_PipR_Anchor(id self, SEL _cmd, unsigned long long i) {                                                      // 0x1c764dd18
    if (G1C_PipR_GetForce(self, 0) && G1C_PipR_IsToOrFromIdx(self, 0, i)) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gPipRSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static BOOL G1C_PipR_Pin(id self, SEL _cmd, unsigned long long i) {                                                            // 0x1c764dd8c / 0x1c764de00
    if (G1C_PipR_GetForce(self, 0) && G1C_PipR_IsToOrFromIdx(self, 0, i)) return YES;
    return G1B_SUPER(BOOL, gPipRSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1C_PipR_Persp(id self, SEL _cmd, id layout) {                                                                   // 0x1c764de74
    if (G1C_PipR_GetForce(self, 0) && G1C_PipR_IsToOrFromObj(self, 0, layout)) return 0.0;
    return G1B_SUPER(double, gPipRSuper, self, _cmd, (struct objc_super *, SEL, id), layout);
}
static CGRect G1C_PipR_AccFrame(id self, SEL _cmd, CGRect f, id layout) {                                                      // 0x1c764defc
    if (G1C_PipR_GetForce(self, 0) && G1C_PipR_IsToOrFromObj(self, 0, layout)) {
        NSUInteger i = [(NSArray *)G1B_Send0(self, @selector(appLayouts)) indexOfObject:layout];
        return ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(frameForIndex:), i);
    }
    return G1B_SUPER(CGRect, gPipRSuper, self, _cmd, (struct objc_super *, SEL, CGRect, id), f, layout);
}
static CGPoint G1C_PipR_AccAnchor(id self, SEL _cmd, CGPoint p, id layout) {                                                   // 0x1c764e004
    if (G1C_PipR_GetForce(self, 0) && G1C_PipR_IsToOrFromObj(self, 0, layout)) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gPipRSuper, self, _cmd, (struct objc_super *, SEL, CGPoint, id), p, layout);
}

// 16.2 creators (SBFullScreenFluidSwitcherRootSwitcherModifier.transitionModifierForMainTransitionEvent: 0x1c762c998, _SBHomeScreenFloorSwitcherModifier.handleTransitionEvent: 0x1c750c194) build the nested
// SBFullScreenToHomeIconZoomSwitcherModifier with setShouldForceDefaultAnchorPointForTransition:isChamoisWindowingUIEnabled and the SBPIPRestoreToFullScreenSwitcherModifier with
// setShouldForceDefaultAnchorPointForTransition: / setShouldClippingTakeShadowIntoAccount: of the same value. Those two creators ARE ported in G1B.x (G1B_FluidRoot / G1B_HomeFloor, 1.x creators) and set
// the flags there; the didMoveToParentModifier: hooks below are the belt-and-braces path for a modifier built by a 16.0 creator that is still reached (the query isChamoisWindowingUIEnabled resolves to the
// same root / floor value the creator used), so the two writes always agree.
static IMP gPipDidMoveOrig;
static void G1C_Pip_DidMove(id self, SEL _cmd, id parent) {
    ((void (*)(id, SEL, id))gPipDidMoveOrig)(self, _cmd, parent);
    if (!parent || !BP_OnName("g1c_pip")) return;
    id zoom = G1C_IvarObj(self, "_zoomModifier");
    if (zoom) G1C_SendVB(zoom, NSSelectorFromString(@"setShouldForceDefaultAnchorPointForTransition:"), G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled)));
}
static void G1C_PipR_DidMove(id self, SEL _cmd, id parent) {
    G1B_SUPER(void, gPipRSuper, self, _cmd, (struct objc_super *, SEL, id), parent);
    if (!parent || !BP_OnName("g1c_pip")) return;
    BOOL chamois = G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled));
    G1B_SET(self, kPrForce, @(chamois));
    G1B_SET(self, kPrShadow, @(chamois));
    id zoom = G1C_IvarObj(self, "_zoomModifier");
    if (zoom) G1C_SendVB(zoom, NSSelectorFromString(@"setShouldForceDefaultAnchorPointForTransition:"), chamois);
}

// ---- SBContinuousExposeWindowDropSwitcherModifier (the transition after a window drag; 16.2 added both methods) ----
static Class gDropC;
static id G1C_Drop_Transition(id self, SEL _cmd, id event) {                           // 0x1c79a5eb4: a window dropped on the home screen zooms into its icon / centre
    id r = G1B_SUPER(id, class_getSuperclass(gDropC), self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1B_SendLL0(event, @selector(toEnvironmentMode)) != 1) return r;
    BOOL reduce = G1B_SendB0(self, @selector(isReduceMotionEnabled));
    id from = G1B_Send0(event, @selector(fromAppLayout)), tid = G1B_Send0(self, @selector(transitionID));
    CGRect icon = G1B_SendB0(event, NSSelectorFromString(@"isIconZoomDisabled")) ? CGRectNull : ((CGRect (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"homeScreenIconFrameForAppLayout:"), from);
    SEL setForce = NSSelectorFromString(@"setShouldForceDefaultAnchorPointForTransition:");
    if (CGRectIsNull(icon) || reduce) {
        if (!from) return r;
        double factor = G1B_Dbl0(G1B_Send0(self, NSSelectorFromString(@"homeGestureSettings")), NSSelectorFromString(@"homeGestureCenterZoomDownCenterYOffsetFactor"));
        Class c = NSClassFromString(@"SBFullScreenToHomeCenterZoomDownSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:appLayout:offsetYPercentOfScreenHeight:");
        id cz = (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, double))objc_msgSend)([c alloc], s, tid, from, factor) : nil;
        G1C_SendVB(cz, setForce, YES);
        if (cz) G1B_SendV1(self, @selector(addChildModifier:), cz);
    } else {
        Class c = NSClassFromString(@"SBFullScreenToHomeIconZoomSwitcherModifier");
        SEL s = NSSelectorFromString(@"initWithTransitionID:appLayout:direction:");
        id iz = (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, id, id, long long))objc_msgSend)([c alloc], s, tid, from, 1) : nil;
        G1C_SendVB(iz, setForce, G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled)));
        if (iz) G1B_SendV1(self, @selector(addChildModifier:), iz);
    }
    return r;
}
static BOOL G1C_Drop_UseAnchor(id self, SEL _cmd, unsigned long long i) {              // 0x1c79a5ce8: the dragged window itself is not pinned through the anchor point
    NSArray *ls = G1B_Send0(self, @selector(appLayouts));
    id l = i < ls.count ? ls[i] : nil;
    if (G1C_LayoutHas(l, G1C_IvarObj(self, "_selectedDisplayItem"))) return NO;
    return G1B_SUPER(BOOL, class_getSuperclass(gDropC), self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}

// +[SBSwitcherTransitionRequest requestForTapAppLayoutHeaderEvent:]  (16.2 0x1c740d7b8; 16.0 has only requestForTapAppLayoutEvent:)
static id G1C_Req_TapHeader(id cls, SEL _cmd, id event) {
    id layout = G1B_Send0(event, @selector(appLayout));
    long long role = G1B_SendLL0(event, @selector(layoutRole));
    id req = [[(Class)cls alloc] init];
    G1B_SendV1(req, @selector(setAppLayout:), layout);
    G1B_SendV1(req, @selector(setActivatingDisplayItem:), G1C_SendLL1(layout, @selector(itemForLayoutRole:), role));
    return req;
}
static void G1C_InstallHomeGesture(void) {
    gHgRootC = NSClassFromString(@"SBHomeGestureRootSwitcherModifier");
    gHgSwC = NSClassFromString(@"SBHomeGestureSwitcherModifier");
    gHgRmC = NSClassFromString(@"SBReduceMotionHomeGestureSwitcherModifier");
    gPipC = NSClassFromString(@"SBFullScreenToHomePIPSwitcherModifier");
    gPipRC = NSClassFromString(@"SBPIPRestoreToFullScreenSwitcherModifier");
    if (gHgRootC && BP_OnName("g1c_homegesture")) {
        SEL tc = NSSelectorFromString(@"transitionChildModifierForMainTransitionEvent:activeGestureModifier:"), gc = NSSelectorFromString(@"gestureChildModifierForGestureEvent:activeTransitionModifier:");
        Method mt = class_getInstanceMethod(gHgRootC, tc), mg = class_getInstanceMethod(gHgRootC, gc);
        if (mt && mg) {
            gHgRootTransOrig = class_replaceMethod(gHgRootC, tc, (IMP)G1C_HGR_TransitionChild, method_getTypeEncoding(mt)) ?: method_getImplementation(mt);
            gHgRootChildOrig = class_replaceMethod(gHgRootC, gc, (IMP)G1C_HGR_GestureChild, method_getTypeEncoding(mg)) ?: method_getImplementation(mg);
        }
        if (gHgSwC) {
            SEL dm = NSSelectorFromString(@"didMoveToParentModifier:");
            Method m = class_getInstanceMethod(gHgSwC, dm);
            if (m) gHgSwDidMoveOrig = class_replaceMethod(gHgSwC, dm, (IMP)G1C_HGS_DidMove, method_getTypeEncoding(m)) ?: method_getImplementation(m);
            const G1CPatch p[] = {
                { "appLayoutsToCacheSnapshots", (IMP)G1C_HGS_CacheSnapshots, "@16@0:8" },
                { "appLayoutsToCacheFullsizeSnapshots", (IMP)G1C_HGS_CacheFullsize, "@16@0:8" },
            };
            G1C_PatchClass(gHgSwC, p, sizeof p / sizeof p[0], "homegesture");
        }
        if (gHgRmC) {
            const G1CPatch p[] = {
                { "shouldProvideBlur", (IMP)G1C_Rm_GetBlur, "B16@0:8" }, { "setShouldProvideBlur:", (IMP)G1C_Rm_SetBlur, "v20@0:8B16" },
                { "laysOutNeighboringCards", (IMP)G1C_Rm_GetNeighbors, "B16@0:8" }, { "setLaysOutNeighboringCards:", (IMP)G1C_Rm_SetNeighbors, "v20@0:8B16" },
                { "scaleForIndex:", (IMP)G1C_Rm_Scale, "d24@0:8Q16" }, { "cornerRadiiForIndex:", (IMP)G1C_Rm_Radii, "{UIRectCornerRadii=dddd}24@0:8Q16" },
                { "homeScreenBackdropBlurType", (IMP)G1C_Rm_BlurType, "q16@0:8" },
            };
            G1C_PatchClass(gHgRmC, p, sizeof p / sizeof p[0], "reducemotion");
        }
    }
    {
        Class rq = NSClassFromString(@"SBSwitcherTransitionRequest");
        if (rq) class_addMethod(object_getClass(rq), NSSelectorFromString(@"requestForTapAppLayoutHeaderEvent:"), (IMP)G1C_Req_TapHeader, "@24@0:8@16");      // no-op when the class already has it
    }
    gDropC = NSClassFromString(@"SBContinuousExposeWindowDropSwitcherModifier");
    if (gDropC && BP_OnName("g1c_homegesture")) {
        const G1CPatch p[] = {
            { "handleTransitionEvent:", (IMP)G1C_Drop_Transition, "@24@0:8@16" },
            { "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)G1C_Drop_UseAnchor, "B24@0:8Q16" },
        };
        G1C_PatchClass(gDropC, p, sizeof p / sizeof p[0], "windowdrop");
    }
    if (BP_OnName("g1c_pip")) {
        Class ev = NSClassFromString(@"SBTransitionSwitcherModifierEvent"), sc = NSClassFromString(@"SBSetupPIPMorphingSwitcherEventResponse");
        if (ev && !class_getInstanceMethod(ev, NSSelectorFromString(@"morphingPIPLayoutRole"))) {                   // value written by the 16.2 coordinator (_shouldMorphToPIPForTransitionContext:outForLayoutRole:); write-only inside the modifiers
            class_addMethod(ev, NSSelectorFromString(@"morphingPIPLayoutRole"), (IMP)G1C_Ev_GetPipRole, "q16@0:8");
            class_addMethod(ev, NSSelectorFromString(@"setMorphingPIPLayoutRole:"), (IMP)G1C_Ev_SetPipRole, "v24@0:8q16");
        }
        if (sc && !class_getInstanceMethod(sc, NSSelectorFromString(@"appLayoutBoundingBox"))) {
            class_addMethod(sc, NSSelectorFromString(@"appLayoutBoundingBox"), (IMP)G1C_Setup_GetBBox, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8");
            class_addMethod(sc, NSSelectorFromString(@"setAppLayoutBoundingBox:"), (IMP)G1C_Setup_SetBBox, "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16");
        }
        if (gPipC) {
            gPipSuper = class_getSuperclass(gPipC);
            const G1CPatch p[] = {
                { "initWithTransitionID:zoomModifier:appLayout:layoutRole:", (IMP)G1C_Pip_Init4, "@48@0:8@16@24@32q40" },
                { "transitionWillBegin", (IMP)G1C_Pip_WillBegin, "@16@0:8" },
                { "clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:", (IMP)G1C_Pip_ClipRole, R4 "72@0:8q16@24Q32" R4 "40" },
                { "clipsToBoundsAtIndex:", (IMP)G1C_Pip_Clips, "B24@0:8Q16" }, { "visibleAppLayouts", (IMP)G1C_Pip_Visible, "@16@0:8" },
                { "anchorPointForIndex:", (IMP)G1C_Pip_Anchor, "{CGPoint=dd}24@0:8Q16" },
                { "shouldPinLayoutRolesToSpace:", (IMP)G1C_Pip_Pin, "B24@0:8Q16" }, { "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)G1C_Pip_Pin, "B24@0:8Q16" },
                { "perspectiveAngleForAppLayout:", (IMP)G1C_Pip_Persp, "d24@0:8@16" },
                { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1C_Pip_AccFrame, R4 "56@0:8" R4 "16@48" },
                { "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (IMP)G1C_Pip_AccAnchor, "{CGPoint=dd}40@0:8{CGPoint=dd}16@32" },
                { "shouldForceDefaultAnchorPointForTransition", (IMP)G1C_Pip_GetForce, "B16@0:8" }, { "setShouldForceDefaultAnchorPointForTransition:", (IMP)G1C_Pip_SetForce, "v20@0:8B16" },
            };
            G1C_PatchClass(gPipC, p, sizeof p / sizeof p[0], "pip");
            SEL dm = NSSelectorFromString(@"didMoveToParentModifier:");
            Method m = class_getInstanceMethod(gPipC, dm);
            if (m) gPipDidMoveOrig = class_replaceMethod(gPipC, dm, (IMP)G1C_Pip_DidMove, method_getTypeEncoding(m)) ?: method_getImplementation(m);
        }
        if (gPipRC) {
            gPipRSuper = class_getSuperclass(gPipRC);
            const G1CPatch p[] = {
                { "initWithTransitionID:zoomModifier:fromAppLayout:toAppLayout:toLayoutRole:", (IMP)G1C_PipR_Init5, "@56@0:8@16@24@32@40q48" },
                { "transitionWillBegin", (IMP)G1C_PipR_WillBegin, "@16@0:8" },
                { "frameForIndex:", (IMP)G1C_PipR_Frame, R4 "24@0:8Q16" },
                { "clippingFrameForIndex:withBounds:", (IMP)G1C_PipR_ClipIdx, R4 "56@0:8Q16" R4 "24" },
                { "clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:", (IMP)G1C_PipR_ClipRole, R4 "72@0:8q16@24Q32" R4 "40" },
                { "_insetFrameForDiffuseShadowRadius:", (IMP)G1C_PipR_Inset, R4 "48@0:8" R4 "16" },
                { "clipsToBoundsAtIndex:", (IMP)G1C_PipR_Clips, "B24@0:8Q16" },
                { "animationAttributesForLayoutElement:", (IMP)G1C_PipR_Anim, "@24@0:8@16" },
                { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1C_PipR_Opacity, "d40@0:8q16@24Q32" },
                { "_isFromAppLayoutIndex:", (IMP)G1C_PipR_IsFromIdx, "B24@0:8Q16" }, { "_isToAppLayoutIndex:", (IMP)G1C_PipR_IsToIdx, "B24@0:8Q16" },
                { "_isToOrFromAppLayout:", (IMP)G1C_PipR_IsToOrFromObj, "B24@0:8@16" }, { "_isToOrFromAppLayoutIndex:", (IMP)G1C_PipR_IsToOrFromIdx, "B24@0:8Q16" },
                { "anchorPointForIndex:", (IMP)G1C_PipR_Anchor, "{CGPoint=dd}24@0:8Q16" },
                { "shouldPinLayoutRolesToSpace:", (IMP)G1C_PipR_Pin, "B24@0:8Q16" }, { "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)G1C_PipR_Pin, "B24@0:8Q16" },
                { "perspectiveAngleForAppLayout:", (IMP)G1C_PipR_Persp, "d24@0:8@16" },
                { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1C_PipR_AccFrame, R4 "56@0:8" R4 "16@48" },
                { "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (IMP)G1C_PipR_AccAnchor, "{CGPoint=dd}40@0:8{CGPoint=dd}16@32" },
                { "shouldClippingTakeShadowIntoAccount", (IMP)G1C_PipR_GetShadow, "B16@0:8" }, { "setShouldClippingTakeShadowIntoAccount:", (IMP)G1C_PipR_SetShadow, "v20@0:8B16" },
                { "shouldForceDefaultAnchorPointForTransition", (IMP)G1C_PipR_GetForce, "B16@0:8" }, { "setShouldForceDefaultAnchorPointForTransition:", (IMP)G1C_PipR_SetForce, "v20@0:8B16" },
                { "didMoveToParentModifier:", (IMP)G1C_PipR_DidMove, "v24@0:8@16" },
            };
            G1C_PatchClass(gPipRC, p, sizeof p / sizeof p[0], "piprestore");
        }
    }
}
// ============================================================================================================
// 0b  SBRoutingSwitcherModifier: the 13 routed queries 16.2 added                                                          PORTED
// ============================================================================================================
// Faithful port of the 13 routed queries 16.2 added to SBRoutingSwitcherModifier (it owns the routed subtrees in `_modifiers` and answers every query by routing it explicitly;
// 16.0 has 198 such methods, 16.2 13 more). NOTE: this is NOT the cause of "[g2b] chain terminal reached ..." - Stage Manager's platform root has the CE root as its direct child, the
// Routing modifier only exists inside SBFilteringSwitcherModifier (window drag) and the classic Main root (see G1C_UndoDefaultTerminals for the real cause). The three routing
// helpers are ported 1:1 below (16.2 0x1c75209ec / 0x1c7521034 / 0x1c752236c): RouteToModifier / ...ContainingAppLayout / ...ContainingIndex.
typedef struct { unsigned long long a, b; } G1CRtTongue;
// The three routing helpers are PRIVATE C functions of SpringBoard (not in the export trie: dlsym cannot find them - that is why the first version of this section never took effect on
// the device). They are small, so they are ported 1:1 (16.2 0x1c75209ec / 0x1c7521034 / 0x1c752236c; 16.0 0x1c609d860 / 0x1c609ddec / 0x1c609f440): all three run a block with the
// Routing modifier's `_currentModifier` temporarily set to the routed modifier.
static void G1C_RtSetCurrent(id routing, id m) {
    Ivar iv = class_getInstanceVariable(object_getClass(routing), "_currentModifier");
    if (iv) BP_SetObjIvar(routing, iv, m);
}
static void G1C_RtRoute(id routing, id modifier, void (^block)(void)) {                               // _SBRoutingSwitcherModifierRouteToModifier
    id old = G1C_IvarObj(routing, "_currentModifier");
    G1C_RtSetCurrent(routing, modifier);
    block();
    G1C_RtSetCurrent(routing, old);
}
static id G1C_RtDelegate(id self);
static void G1C_RtRouteLayout(id routing, id layout, void (^block)(id m)) {                           // ...ContainingAppLayout: [delegate routingModifier:self modifierForAppLayout:layout]
    id old = G1C_IvarObj(routing, "_currentModifier");
    id delegate = G1C_RtDelegate(routing);
    SEL s = @selector(routingModifier:modifierForAppLayout:);
    id m = G1C_Resp(delegate, s) ? G1C_Send2(delegate, s, routing, layout) : nil;
    G1C_RtSetCurrent(routing, m);
    block(m);
    G1C_RtSetCurrent(routing, old);
}
static void G1C_RtRouteIndex(id routing, unsigned long long index, void (^block)(id m, unsigned long long local)) {   // ...ContainingIndex
    id old = G1C_IvarObj(routing, "_currentModifier");
    unsigned long long base = 0;
    id found = nil;
    SEL li = NSSelectorFromString(@"_lastIndexForModifier:");
    for (id m in G1C_IvarObj(routing, "_modifiers")) {
        unsigned long long cap = G1C_Resp(routing, li) ? (unsigned long long)G1C_SendLLId(routing, li, m) : NSNotFound;
        if (cap == NSNotFound) continue;                                      // 0x7fffffffffffffff
        if (cap >= index) { found = m; break; }
        base = cap + 1;
    }
    if (!found) {                                                              // 16.2 asserts ("couldn't find a modifier among (...) for index"); a logged last-line guard here
        if (BP_LogEnabled()) BP_Log(@"g1c: routing: no modifier for index %llu (16.2 asserts)", index);
        return;
    }
    G1C_RtSetCurrent(routing, found);
    block(found, index - base);
    G1C_RtSetCurrent(routing, old);
}
static void G1C_RtNote(SEL s) {                                                                            // first use of each routed query is logged (install-time logging happens before the log is on)
    static NSMutableSet *seen; static dispatch_once_t o; dispatch_once(&o, ^{ seen = [NSMutableSet set]; });
    if (!BP_LogEnabled()) return;
    NSString *n = NSStringFromSelector(s);
    @synchronized (seen) { if ([seen containsObject:n]) return; [seen addObject:n]; }
    BP_Log(@"g1c: routing: first routed answer for %@", n);
}
static Class gRtCls;
static id G1C_RtDelegate(id self) { return G1C_IvarObj(self, "_delegate"); }
// _arrayByCombiningArrays (0x1c751fcc8): nil+x -> x, x+nil -> x, else a new array a + b
static id G1C_RtCombine(id a, id b) {
    if (!a && b) return b;
    if (a && !b) return a;
    NSMutableArray *m = [NSMutableArray array];
    if (a) [m addObjectsFromArray:a];
    if (b) [m addObjectsFromArray:b];
    return m;
}
static id G1C_RtArrays(id self, SEL _cmd) {                                                                      // 0x1c7532594 (active) / 0x1c7532824 (inactive)
    G1C_RtNote(_cmd);
    id combined = nil; BOOL first = YES;
    for (id m in G1C_IvarObj(self, "_modifiers")) {
        __block id r = nil;
        G1C_RtRoute(self, m, ^{ r = G1B_Send0(m, _cmd); });
        combined = first ? r : G1C_RtCombine(combined, r);
        first = NO;
    }
    return combined;
}
static BOOL G1C_RtAny(id self, SEL _cmd) {                                                                       // 0x1c7535678 (hover gesture) / 0x1c7535894 (strip visible): OR of all modifiers
    G1C_RtNote(_cmd);
    BOOL res = NO, first = YES;
    for (id m in G1C_IvarObj(self, "_modifiers")) {
        __block BOOL b = NO;
        G1C_RtRoute(self, m, ^{ b = G1B_SendB0(m, _cmd); });
        res = first ? (b != NO) : (res | b);
        first = NO;
    }
    return res;
}
static id G1C_RtProposed(id self, SEL _cmd) {                                                                    // 0x1c7535ab0: the first non-nil answer
    G1C_RtNote(_cmd);
    id res = nil;
    for (id m in G1C_IvarObj(self, "_modifiers")) {
        __block id r = nil;
        G1C_RtRoute(self, m, ^{ r = G1B_Send0(m, _cmd); });
        if (!res) res = r;
    }
    return res;
}
static id G1C_RtScrollModifier(id self) {
    id delegate = G1C_RtDelegate(self);
    return G1C_Resp(delegate, @selector(scrollModifierForRoutingModifier:)) ? G1B_Send1(delegate, @selector(scrollModifierForRoutingModifier:), self) : nil;
}
static id G1C_RtAdjStrip(id self, SEL _cmd, id prev) {                                                          // 0x1c7532ca4
    G1C_RtNote(_cmd);
    id scroll = G1C_RtScrollModifier(self);
    __block id result = nil;
    G1C_RtRoute(self, scroll, ^{ result = G1B_Send1(scroll, _cmd, prev); });
    return result;
}
static id G1C_RtAdjSwitcher(id self, SEL _cmd, id prev, id strip) {                                              // 0x1c7532ab4
    G1C_RtNote(_cmd);
    id scroll = G1C_RtScrollModifier(self);
    __block id result = nil;
    G1C_RtRoute(self, scroll, ^{ result = (scroll && [scroll respondsToSelector:_cmd]) ? G1C_Send2(scroll, _cmd, prev, strip) : nil; });
    return result;
}
static G1CRtTongue G1C_RtTongue(id self, SEL _cmd) {                                                             // 0x1c75354f4: routed to the home screen modifier
    G1C_RtNote(_cmd);
    id delegate = G1C_RtDelegate(self);
    SEL hs = @selector(homeScreenModifierForRoutingModifier:);
    id home = G1C_Resp(delegate, hs) ? G1B_Send1(delegate, hs, self) : nil;
    __block G1CRtTongue r = { 0, 0 };
    __unsafe_unretained id us = self;
    G1C_RtRoute(self, home, ^{
        id d = G1C_RtDelegate(us);
        id h = G1C_Resp(d, hs) ? G1B_Send1(d, hs, us) : nil;
        if (G1C_Resp(h, _cmd)) r = ((G1CRtTongue (*)(id, SEL))objc_msgSend)(h, _cmd);
    });
    return r;
}
static double G1C_RtScale(id self, SEL _cmd, double scale, id layout) {                                          // 0x1c752610c
    G1C_RtNote(_cmd);
    __block double r = 0.0;
    G1C_RtRouteLayout(self, layout, ^(id m) { r = ((double (*)(id, SEL, double, id))objc_msgSend)(m, _cmd, scale, layout); });
    return r;
}
static double G1C_RtHitOutset(id self, SEL _cmd, id layout) {                                                    // 0x1c752b8ac
    G1C_RtNote(_cmd);
    __block double r = 0.0;
    G1C_RtRouteLayout(self, layout, ^(id m) { r = ((double (*)(id, SEL, id))objc_msgSend)(m, _cmd, layout); });
    return r;
}
static BOOL G1C_RtBoolLayout(id self, SEL _cmd, id layout) {                                                     // 0x1c752b9d0 (canSelectLeaf...) / 0x1c752baec (shouldAllowGroupOpacity...)
    G1C_RtNote(_cmd);
    __block BOOL r = NO;
    G1C_RtRouteLayout(self, layout, ^(id m) { r = G1B_SendB1(m, _cmd, layout); });
    return r;
}
static CGRect G1C_RtClipping(id self, SEL _cmd, long long role, id layout, unsigned long long index, CGRect bounds) {   // 0x1c75255d4
    G1C_RtNote(_cmd);
    __block CGRect r = CGRectNull;
    G1C_RtRouteIndex(self, index, ^(id m, unsigned long long local) { r = ((CGRect (*)(id, SEL, long long, id, unsigned long long, CGRect))objc_msgSend)(m, _cmd, role, layout, local, bounds); });
    return r;
}
// ROOT CAUSE (device log f8d059f3, 68 of 68 ids updates reach "[g2b] chain terminal"): the persistent AppSwitcherCE child of the CE root (16.2 implementer of both id-list queries) is
// DFS-later in the query chain than the SBDefaultImplementationsSwitcherModifier children that the floors / the strip add to themselves (16.0 AppSwitcherCE.init adds a Default child at
// level 1, the FullScreen floor tree has one too), and G2B's "chain terminal" methods made THAT modifier an implementer. 16.2's Default implements none of these six queries, so there it
// is skipped and the chain reaches the AppSwitcherCE. (SBRoutingSwitcherModifier is not even on the Stage Manager path: the platform root's child is the CE root itself, the Routing
// modifier only lives inside SBFilteringSwitcherModifier and the classic Main root, so section 0b alone could never change this log.) Undo G2B's six terminals on Default: restore the
// inherited trampoline IMP, which the per-class query cache (+newCacheWithSelectorList: compares instanceMethodForSelector: with the base class) treats as "does not implement".
static void G1C_UndoDefaultTerminals(void) {
    if (!BP_OnName("g1c_defaults")) return;
    Class d = NSClassFromString(@"SBDefaultImplementationsSwitcherModifier"), base = NSClassFromString(@"SBSwitcherModifier");
    if (!d || !base) return;
    NSArray *sels = @[ @"adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:",
                       @"adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:",
                       @"activeLeafAppLayoutsReachableByKeyboardShortcut", @"inactiveAppLayoutsReachableByKeyboardShortcut",
                       @"canSelectLeafWithModifierKeysInAppLayout:", @"shouldAllowGroupOpacityForAppLayout:" ];
    int n = 0;
    for (NSString *name in sels) {
        SEL s = NSSelectorFromString(name);
        Method bm = class_getInstanceMethod(base, s), dm = class_getInstanceMethod(d, s);
        if (!bm || !dm || method_getImplementation(dm) == method_getImplementation(bm)) continue;
        class_replaceMethod(d, s, method_getImplementation(bm), method_getTypeEncoding(bm));
        n++;
    }
    BP_Log(@"g1c: defaults: %d G2B terminal(s) removed from SBDefaultImplementationsSwitcherModifier (16.2 does not default these 6 queries)", n);
}
static void G1C_InstallRouting(void) {
    if (!BP_OnName("g1c_routing")) return;
    gRtCls = NSClassFromString(@"SBRoutingSwitcherModifier");
    if (!gSbSwitcherModifierCls) gSbSwitcherModifierCls = NSClassFromString(@"SBSwitcherModifier");
    if (!gRtCls) return;
    const G1CPatch p[] = {
        { "activeLeafAppLayoutsReachableByKeyboardShortcut", (IMP)G1C_RtArrays, "@16@0:8" },
        { "inactiveAppLayoutsReachableByKeyboardShortcut", (IMP)G1C_RtArrays, "@16@0:8" },
        { "adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:", (IMP)G1C_RtAdjStrip, "@24@0:8@16" },
        { "adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:", (IMP)G1C_RtAdjSwitcher, "@32@0:8@16@24" },
        { "continuousExposeStripTongueAttributes", (IMP)G1C_RtTongue, "{SBSwitcherContinuousExposeStripTongueAttributes=QQ}16@0:8" },
        { "wantsContinuousExposeHoverGesture", (IMP)G1C_RtAny, "B16@0:8" },
        { "isContinuousExposeStripVisible", (IMP)G1C_RtAny, "B16@0:8" },
        { "proposedAppLayoutForContinuousExposeWindowDrag", (IMP)G1C_RtProposed, "@16@0:8" },
        { "adjustedSpaceAccessoryViewScale:forAppLayout:", (IMP)G1C_RtScale, "d32@0:8d16@24" },
        { "spaceAccessoryViewIconHitTestOutsetForAppLayout:", (IMP)G1C_RtHitOutset, "d24@0:8@16" },
        { "canSelectLeafWithModifierKeysInAppLayout:", (IMP)G1C_RtBoolLayout, "B24@0:8@16" },
        { "shouldAllowGroupOpacityForAppLayout:", (IMP)G1C_RtBoolLayout, "B24@0:8@16" },
        { "clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:", (IMP)G1C_RtClipping, "{CGRect={CGPoint=dd}{CGSize=dd}}72@0:8q16@24Q32{CGRect={CGPoint=dd}{CGSize=dd}}40" },
    };
    G1C_PatchClass(gRtCls, p, sizeof p / sizeof p[0], "routing");
    BP_Log(@"g1c: routing: %zu routed queries installed on %s (ivars _modifiers %d _delegate %d _currentModifier %d, own helpers, no dlsym)", sizeof p / sizeof p[0], class_getName(gRtCls),
           class_getInstanceVariable(gRtCls, "_modifiers") != NULL, class_getInstanceVariable(gRtCls, "_delegate") != NULL, class_getInstanceVariable(gRtCls, "_currentModifier") != NULL);
}

// ============================================================================================================
// setup
// ============================================================================================================
void G1C_Setup(void) {
    G1C_UndoDefaultTerminals();
    G1C_InstallRouting();
    G1C_InstallEventPredicates();
    G1C_BuildGridGesture();
    G1C_BuildCEToHome();
    G1C_InstallHomeToGrid();
    G1C_InstallFlyInFix();
    G1C_InstallHomeGesture();
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
    G1C_BuildStrip();
    G1C_InstallFullScreen();
    G1C_InstallRemovedForwarders();
    G1C_BuildFloors();                   // sets gHsParent, which the Home screen conversion below needs (it used to run before this: the 16.2 Home floor never got installed)
    G1C_InstallHomeScreen();
    G1C_BuildWindowDragFamily();
    %init(G1C_WdEvent);
    %init(G1C_EventDefault);
    %init(G1C_ModelMap);
    %init(G1C_VCScroll);
    %init(G1C_Root);
    %init(G1C_Producers);
    %init(G1C_OverflowRoot);
    G1C_InstallRevealStrips();
    %init(G1C_Cycle);
    %init(G1C_VCIds);        // MUST be after the group 2 %init(G2B): it replaces the same method
}
#pragma clang diagnostic pop
