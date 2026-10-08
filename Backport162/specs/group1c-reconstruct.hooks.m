// group1c-reconstruct.hooks.m
//
// DRAFT. Logos source (same conventions as group1b-modifiers.hooks.m, whose helper kit it uses). Reconstructs, as new run-time
// classes / whole-method replacements, the iPadOS 16.2 (20C65) Stage Manager pieces that group1b tagged NOT PORTABLE, for
// iPadOS 16.0 (20A8372) SpringBoard. Behaviour and every address are in group1c-reconstruct.md (item numbers in the comments).
//
// INTEGRATION
//   * This file is appended to the SAME translation unit as group1b-modifiers.hooks.m (after it): it uses G1B_MakeClass, G1B_SUPER,
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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

#ifndef F_G1C
#define F_G1C F_G1B
#endif
#define G1C_ON() BP_On(F_G1C)

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
    if (!G1C_GridGest_Delay(self, 0)) G1B_SendVLL(self, @selector(setState:), 1);      // 16.0: always; 16.2: only when not delayed
    return resp;
}
static id G1C_GridGest_HandleTransition(id self, SEL _cmd, id event) {
    id resp = G1B_SUPER(id, gGridGestBase, self, _cmd, (struct objc_super *, SEL, id), event);
    if (G1C_GridGest_Delay(self, 0) && event && [event respondsToSelector:@selector(phase)] && G1B_SendLL0(event, @selector(phase)) >= 2)
        G1B_SendVLL(self, @selector(setState:), 1);                                    // complete when the transition that the gesture requested has begun
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
static CGPoint G1C_CEH_Anchor(id self, SEL _cmd, unsigned long long i) {
    if (G1C_CEH_IsHome(self)) return CGPointMake(0.5, 0.5);
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
static id G1C_IdsEv_Copy(id self, SEL _cmd, NSZone *z) {
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
static CGRect G1C_Sl_Frame(id self, SEL _cmd, unsigned long long i) {
    CGRect r = G1B_SUPER(CGRect, gSlideSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    int mode = G1C_Sl_Mode(self, G1C_Sl_LayoutAtIndex(self, i));
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
        r = G1B_Append(c, r);
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
static id G1C_Rv_HandleGesture(id self, SEL _cmd, id event) {
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
    id s = [[fc alloc] initWithDefaultValues];
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
    G1C_AddLike(c, "handleGestureEvent:", (IMP)G1C_Rv_HandleGesture, "@24@0:8@16", YES);
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
    id s = [[fc alloc] initWithDefaultValues];
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
// setup
// ============================================================================================================
static void G1C_Setup(void) {
    G1C_InstallEventPredicates();
    G1C_BuildGridGesture();
    G1C_BuildCEToHome();
    G1C_BuildGridRoot();
    G1C_BuildTransactions();
    %init(G1C_Txn);
    G1C_BuildIdsEvent();
    G1C_InstallEvent16Compat();
    G1C_UpgradeOverrideIds();
    G1C_BuildSlide();
    G1C_BuildAppToApp();
    G1C_BuildSwitcherToApp();
    %init(G1C_OverflowRoot);
    G1C_InstallRevealStrips();
    %init(G1C_Cycle);
    %init(G1C_VCIds);        // MUST be after the group 2 %init(G2B): it replaces the same method
}
#pragma clang diagnostic pop
