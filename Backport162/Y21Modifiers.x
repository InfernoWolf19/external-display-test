// Y21Modifiers.x : delta sweep pass 2, switcher modifiers (F3).  Setup: constructor.  Log prefix "[y21]".
//
//  y17_centerwindow  SBWindowDeclineSwitcherModifier / SBWindowCommitSwitcherModifier (16.2 0x1c74ed85c.. / 0x1c770222c..; 16.0 0x1c606b4d8 / 0x1c626aadc).  In 16.2 the three classes
//                    SBWindowDelete / Decline / Commit are clones (same ivars at the same offsets, bodies identical up to ivar slot numbers: the normalised raw diffs of transitionWillBegin
//                    and the five queries Decline vs Delete and Commit vs Delete differ only in ivar slot numbers and the class names).  G1B.x ports the Delete class (G1B_WD_*); the other two
//                    got the same change set and are ported here with the same code:
//                      -transitionWillBegin   super + SBInvalidateAdjustedAppLayoutsSwitcherEventResponse + SBUpdateLayoutSwitcherEventResponse(2, 2); with _fullScreenAppLayout == nil the
//                                              closing / declined window (_centerWindowAppLayout) is the subject (inserted at 0 when it is not in the layouts) and the temporary
//                                              SBOverrideAppLayoutsSwitcherModifier block captures _initialFrame and the NEW _initialCornerRadii
//                      NEW queries            -appLayoutContainingAppLayout: (0x1c74edaf0 / 0x1c77024c0), -titleAndIconOpacityForIndex: (0x1c74ee534 / 0x1c7702ef4),
//                                              -cornerRadiiForIndex: (0x1c74ee5d8 / 0x1c7702f98), -isLayoutRoleMatchMovedToScene:inAppLayout: (0x1c74ee96c / 0x1c770332c),
//                                              -adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip: (0x1c74edbb8 / 0x1c7702588), all gated on Stage Manager
//                                              (isChamoisWindowingUIEnabled) exactly like the Delete versions.
//  y17_resizestrip   -[SBItemResizeGestureSwitcherModifier _anyItemExceedsWidthThresholdToHideStrip] 16.2 0x1c76bfd40 (16.0 0x1c622d588): 16.0 compares the bounding box of the overlapping
//                    model with -_widthThresholdToHideStrip; 16.2 answers !model.isContinuousExposeStripVisible, and -[SBChamoisOverlappingModel isContinuousExposeStripVisible]
//                    (16.2 0x1c797a558) is YES when NO item of the model has a width >= the model's widthThresholdToHideStrip (BSFloatGreaterThanOrEqualToFloat of -sizeForItem: width), i.e. the
//                    rule is per item.  A stage of two windows that are each narrower than the threshold but together wider keeps its strip while one of them is resized.  Ported: the same
//                    model (same calculator call as 16.0, the app layout is the _currentAppLayout ivar) and the per item loop; the threshold is the modifier's own -_widthThresholdToHideStrip
//                    (16.0 and 16.2 both read the model threshold from it).
//  y17_splitbounds   -[SBSplitDisplayItemSwitcherModifier frameForLayoutRole:inAppLayout:withBounds:] 16.2 0x1c753da84 (16.0 0x1c60b9374): under Stage Manager 16.0 used the bounds of the call and only for
//                    layout environment 3; 16.2 uses the bounding box of the overlapping model of the wrapped layout (appLayoutContainingAppLayout:) for every environment.  Ported (block below).
// Needs a device: (centerwindow) a center window declined / committed under Stage Manager animates from its own frame and radii; (resizestrip) resize one of two stage windows past half the
// width: the strip stays while each window is still narrower than the threshold.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"
#import "G1BKit.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double tl, bl, br, tr; } Y21Radii;          // UIRectCornerRadii
typedef struct { double x, y, w, h; } Y21Rect;
typedef struct { double w, h; } Y21Size;

static Class gY21Super;
static const char kY21Radii = 0;
static IMP gY21OrigDecline, gY21OrigCommit, gY21OrigResize;

static id Y21_Ivar(id me, const char *name) { return BP_ObjIvar(me, class_getInstanceVariable(object_getClass(me), name)); }
static BOOL Y21_Chamois(id me) { return BPX_Bool0(me, "isChamoisWindowingUIEnabled"); }
static BOOL Y21_On(void) { return BP_OnName("y17_centerwindow"); }

// -appLayoutContainingAppLayout:
static id Y21_ContainingLayout(id self, SEL _cmd, id layout) {
    if (Y21_On() && Y21_Chamois(self) && [layout isEqual:Y21_Ivar(self, "_centerWindowAppLayout")]) {
        id full = Y21_Ivar(self, "_fullScreenAppLayout");
        return (BPX_LL0(self, "transitionPhase") >= 2 && full) ? full : Y21_Ivar(self, "_fromAppLayout");
    }
    return G1B_HasSuper(gY21Super, _cmd) ? G1B_SUPER(id, gY21Super, self, _cmd, (struct objc_super *, SEL, id), layout) : nil;
}
// -titleAndIconOpacityForIndex:
static double Y21_TitleOpacity(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = BPX_Obj0(self, "appLayouts");
    if (Y21_On() && i < ls.count && [ls[i] isEqual:Y21_Ivar(self, "_centerWindowAppLayout")]) return 0.0;
    return G1B_HasSuper(gY21Super, _cmd) ? G1B_SUPER(double, gY21Super, self, _cmd, (struct objc_super *, SEL, unsigned long long), i) : 1.0;
}
// -cornerRadiiForIndex:
static Y21Radii Y21_CornerRadii(id self, SEL _cmd, unsigned long long i) {
    NSArray *ls = BPX_Obj0(self, "appLayouts");
    if (Y21_On() && i < ls.count && [ls[i] isEqual:Y21_Ivar(self, "_centerWindowAppLayout")]) {
        NSValue *v = objc_getAssociatedObject(self, &kY21Radii);
        Y21Radii r = { 0, 0, 0, 0 };
        if (v) [v getValue:&r size:sizeof r];
        return r;
    }
    Y21Radii z = { 0, 0, 0, 0 };
    return G1B_HasSuper(gY21Super, _cmd) ? G1B_SUPER(Y21Radii, gY21Super, self, _cmd, (struct objc_super *, SEL, unsigned long long), i) : z;
}
// -isLayoutRoleMatchMovedToScene:inAppLayout:
static BOOL Y21_MatchMoved(id self, SEL _cmd, long long role, id layout) {
    BOOL s = G1B_HasSuper(gY21Super, _cmd) ? G1B_SUPER(BOOL, gY21Super, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout) : NO;
    if (s) return YES;
    return Y21_On() && Y21_Chamois(self) && [layout isEqual:Y21_Ivar(self, "_fullScreenAppLayout")];
}
// -adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:
static id Y21_AdjustedStrip(id self, SEL _cmd, id strip) {
    id (^sup)(void) = ^id{ return G1B_HasSuper(gY21Super, _cmd) ? G1B_SUPER(id, gY21Super, self, _cmd, (struct objc_super *, SEL, id), strip) : nil; };
    if (!Y21_On() || !Y21_Chamois(self) || BPX_LL0(self, "transitionPhase") < 2 || Y21_Ivar(self, "_fullScreenAppLayout")) return sup();
    id stage = BPX_Obj0(self, "appLayoutOnContinuousExposeStage");
    if (!stage) return sup();
    id center = Y21_Ivar(self, "_centerWindowAppLayout");
    NSMutableArray *kept = [NSMutableArray array];
    for (id l in (NSArray *)(G1B_HasSuper(gY21Super, @selector(appLayouts)) ? G1B_SUPER(id, gY21Super, self, @selector(appLayouts), (struct objc_super *, SEL)) : BPX_Obj0(self, "appLayouts")))
        if (![l isEqual:center] && ![l isEqual:stage]) [kept addObject:l];
    Class oc = NSClassFromString(@"SBOverrideAppLayoutsSwitcherModifier");
    SEL oi = @selector(initWithAppLayouts:);
    id override = (oc && [oc instancesRespondToSelector:oi]) ? G1B_INIT(id)([oc alloc], oi, [kept copy]) : nil;
    if (!override || ![self respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)]) return sup();
    __block id result = nil;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(self, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), override, ^{ result = sup(); });
    return result;
}

// -transitionWillBegin (Decline and Commit; orig = the 16.0 body, used only with the switch off)
static id Y21_WillBegin(id me, SEL _cmd, IMP orig) {
    if (!Y21_On() || !gY21Super) return orig ? ((id (*)(id, SEL))orig)(me, _cmd) : nil;
    id r = G1B_SUPER(id, gY21Super, me, _cmd, (struct objc_super *, SEL));
    Class inv = NSClassFromString(@"SBInvalidateAdjustedAppLayoutsSwitcherEventResponse");
    r = G1B_AppendTo(inv ? [[inv alloc] init] : nil, r);
    r = G1B_AppendTo(G1B_NewUpdateLayoutResponse(2, 2), r);
    NSMutableArray *layouts = [(NSArray *)BPX_Obj0(me, "appLayouts") mutableCopy];
    id full = Y21_Ivar(me, "_fullScreenAppLayout"), from = Y21_Ivar(me, "_fromAppLayout"), center = Y21_Ivar(me, "_centerWindowAppLayout");
    NSUInteger idx = NSNotFound;
    if (full) {
        idx = [layouts indexOfObject:full];
        if (idx != NSNotFound) [layouts replaceObjectAtIndex:idx withObject:from];
        else idx = from ? [layouts indexOfObject:from] : NSNotFound;
    } else if (center) {
        idx = [layouts indexOfObject:center];
        if (idx == NSNotFound) { [layouts insertObject:center atIndex:0]; idx = 0; }
    }
    Class oc = NSClassFromString(@"SBOverrideAppLayoutsSwitcherModifier");
    SEL oi = @selector(initWithAppLayouts:);
    if (idx == NSNotFound || !oc || ![oc instancesRespondToSelector:oi] || ![me respondsToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)]) {
        BP_Log(@"[y21] GUARD(centerwindow) %@ transitionWillBegin: no subject layout (full %@, from %@, center %@): super response only", NSStringFromClass(object_getClass(me)), full, from, center);
        return r;
    }
    id override = G1B_INIT(id)([oc alloc], oi, layouts);
    Ivar ivFrame = class_getInstanceVariable(object_getClass(me), "_initialFrame");
    unsigned long long index = idx;
    ((void (*)(id, SEL, id, void (^)(void)))objc_msgSend)(me, @selector(performTransactionWithTemporaryChildModifier:usingBlock:), override, ^{
        Y21Rect f = G1B_SUPER(Y21Rect, gY21Super, me, @selector(frameForIndex:), (struct objc_super *, SEL, unsigned long long), index);
        if (ivFrame) *(Y21Rect *)((uint8_t *)(__bridge void *)me + ivar_getOffset(ivFrame)) = f;
        Y21Radii rr = G1B_SUPER(Y21Radii, gY21Super, me, @selector(cornerRadiiForIndex:), (struct objc_super *, SEL, unsigned long long), index);
        objc_setAssociatedObject(me, &kY21Radii, [NSValue valueWithBytes:&rr objCType:@encode(Y21Radii)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
    BPY_LOG(@"[y21] %@ transitionWillBegin: subject index %lu (full %d)", NSStringFromClass(object_getClass(me)), (unsigned long)idx, (int)(full != nil));
    return r;
}
static id Y21_DeclineBegin(id self, SEL _cmd) { return Y21_WillBegin(self, _cmd, gY21OrigDecline); }
static id Y21_CommitBegin(id self, SEL _cmd) { return Y21_WillBegin(self, _cmd, gY21OrigCommit); }

// ---- y17_resizestrip ----
typedef BOOL (*Y21GEFn)(double, double);
static BOOL Y21_FloatGE(double a, double b) {
    static Y21GEFn fn; static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (Y21GEFn)dlsym(RTLD_DEFAULT, "BSFloatGreaterThanOrEqualToFloat"); });
    if (fn) return fn(a, b);
    Y17_GuardOnce("resizestrip", nil, "BSFloatGreaterThanOrEqualToFloat");
    return a >= b || fabs(a - b) < 1e-9;
}
static BOOL Y21_AnyExceeds(id self, SEL _cmd) {
    if (!BP_OnName("y17_resizestrip")) return gY21OrigResize ? ((BOOL (*)(id, SEL))gY21OrigResize)(self, _cmd) : NO;
    double threshold = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("_widthThresholdToHideStrip"));
    id calc = BPX_Obj0(self, "displayItemLayoutAttributesCalculator");
    id layout = Y21_Ivar(self, "_currentAppLayout");
    long long ori = BPX_LL0(self, "switcherInterfaceOrientation");
    id attrs = BPX_Obj0(self, "chamoisLayoutAttributes");
    double dock = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("floatingDockHeight"));
    double scale = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("screenScale"));
    Y21Rect bounds = ((Y21Rect (*)(id, SEL))objc_msgSend)(self, sel_registerName("containerViewBounds"));
    BOOL strip = BPX_Bool0(self, "prefersStripHidden"), dockH = BPX_Bool0(self, "prefersDockHidden");
    id model = (calc && layout) ? ((id (*)(id, SEL, id, long long, id, double, double, Y21Rect, BOOL, BOOL))objc_msgSend)(calc, sel_registerName("overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:"), layout, ori, attrs, dock, scale, bounds, strip, dockH) : nil;
    if (!model || !BPY_Responds(model, "sizeForItem:")) {
        BP_Log(@"[y21] GUARD(resizestrip) no overlapping model (calc %@, layout %@): the 16.0 bounding box rule stays", calc, layout);
        return gY21OrigResize ? ((BOOL (*)(id, SEL))gY21OrigResize)(self, _cmd) : NO;
    }
    BOOL any = NO;
    for (id item in (NSArray *)BPX_Obj0(model, "items")) {
        Y21Size s = ((Y21Size (*)(id, SEL, id))objc_msgSend)(model, sel_registerName("sizeForItem:"), item);
        if (Y21_FloatGE(s.w, threshold)) { any = YES; break; }
    }
    BPY_LOG(@"[y21] resize strip: any item >= %.1f -> %d", threshold, (int)any);
    return any;
}

// ---- y17_splitbounds ----
// -[SBSplitDisplayItemSwitcherModifier frameForLayoutRole:inAppLayout:withBounds:]  Stage Manager: wrapped = [super appLayoutContainingAppLayout:layout]; the frame of the item (role of the
// requested item inside the wrapped layout) is asked from super with the bounding box of [self overlappingModelForAppLayout:wrapped] as bounds, for EVERY layout environment (16.0: only
// environment 3, and with the bounds of the call).  Not Stage Manager: the 16.0 body.
static IMP gY21OrigSplit;
static Class gY21SplitSuper;
static Y21Rect Y21_SplitFrame(id self, SEL _cmd, long long role, id layout, Y21Rect bounds) {
    Y21Rect (*orig)(id, SEL, long long, id, Y21Rect) = (Y21Rect (*)(id, SEL, long long, id, Y21Rect))gY21OrigSplit;
    if (!BP_OnName("y17_splitbounds") || !Y21_Chamois(self) || !gY21SplitSuper) return orig ? orig(self, _cmd, role, layout, bounds) : bounds;
    SEL ac = sel_registerName("appLayoutContainingAppLayout:");
    id wrapped = G1B_HasSuper(gY21SplitSuper, ac) ? G1B_SUPER(id, gY21SplitSuper, self, ac, (struct objc_super *, SEL, id), layout) : nil;
    id model = (wrapped && BPY_Responds(self, "overlappingModelForAppLayout:")) ? BPX_Obj1(self, "overlappingModelForAppLayout:", wrapped) : nil;
    if (!model || !BPY_Responds(model, "boundingBox")) {
        BP_Log(@"[y21] GUARD(splitbounds) no wrapped layout / overlapping model (wrapped %@): the 16.0 body runs", wrapped);
        return orig ? orig(self, _cmd, role, layout, bounds) : bounds;
    }
    Y21Rect box = ((Y21Rect (*)(id, SEL))objc_msgSend)(model, sel_registerName("boundingBox"));
    long long role2;
    id item = ((id (*)(id, SEL, long long))objc_msgSend)(layout, sel_registerName("itemForLayoutRole:"), role);
    role2 = item ? ((long long (*)(id, SEL, id))objc_msgSend)(wrapped, sel_registerName("layoutRoleForItem:"), item) : role;
    BPY_LOG(@"[y21] split item frame: role %lld -> %lld in the wrapped layout, bounds replaced by the model bounding box", role, role2);
    return G1B_SUPER(Y21Rect, gY21SplitSuper, self, _cmd, (struct objc_super *, SEL, long long, id, Y21Rect), role2, wrapped, box);
}

__attribute__((constructor)) static void Y21_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class dc = NSClassFromString(@"SBWindowDeclineSwitcherModifier"), cm = NSClassFromString(@"SBWindowCommitSwitcherModifier");
        if (dc && cm && class_getInstanceMethod(dc, sel_registerName("transitionWillBegin")) && class_getInstanceMethod(cm, sel_registerName("transitionWillBegin")) && class_getSuperclass(dc) == class_getSuperclass(cm)) {
            gY21Super = class_getSuperclass(dc);
            const G1BMethod m[] = {
                { "appLayoutContainingAppLayout:",  (IMP)Y21_ContainingLayout, "@24@0:8@16" },
                { "titleAndIconOpacityForIndex:",   (IMP)Y21_TitleOpacity,     "d24@0:8Q16" },
                { "cornerRadiiForIndex:",           (IMP)Y21_CornerRadii,      "{?=dddd}24@0:8Q16" },
                { "isLayoutRoleMatchMovedToScene:inAppLayout:", (IMP)Y21_MatchMoved, "B32@0:8q16@24" },
                { "adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:", (IMP)Y21_AdjustedStrip, "@24@0:8@16" },
            };
            G1B_AddMethods(dc, m, sizeof m / sizeof m[0]);
            G1B_AddMethods(cm, m, sizeof m / sizeof m[0]);
            gY21OrigDecline = BPX_Replace(dc, "transitionWillBegin", (IMP)Y21_DeclineBegin);
            gY21OrigCommit = BPX_Replace(cm, "transitionWillBegin", (IMP)Y21_CommitBegin);
            n++;
        } else BP_Log(@"[y21] GUARD(centerwindow) SBWindowDecline/CommitSwitcherModifier missing or with different super classes: not installed");
        Class rs = NSClassFromString(@"SBItemResizeGestureSwitcherModifier");
        if (rs && class_getInstanceMethod(rs, sel_registerName("_anyItemExceedsWidthThresholdToHideStrip")) && class_getInstanceVariable(rs, "_currentAppLayout")) {
            gY21OrigResize = BPX_Replace(rs, "_anyItemExceedsWidthThresholdToHideStrip", (IMP)Y21_AnyExceeds);
            n++;
        } else BP_Log(@"[y21] GUARD(resizestrip) SBItemResizeGestureSwitcherModifier _anyItemExceedsWidthThresholdToHideStrip or _currentAppLayout missing: not installed");
        Class sp = NSClassFromString(@"SBSplitDisplayItemSwitcherModifier");
        if (sp && class_getInstanceMethod(sp, sel_registerName("frameForLayoutRole:inAppLayout:withBounds:"))) {
            gY21SplitSuper = class_getSuperclass(sp);
            gY21OrigSplit = BPX_Replace(sp, "frameForLayoutRole:inAppLayout:withBounds:", (IMP)Y21_SplitFrame);
            n++;
        } else BP_Log(@"[y21] GUARD(splitbounds) SBSplitDisplayItemSwitcherModifier frameForLayoutRole:inAppLayout:withBounds: missing: not installed");
        BP_Log(@"[y21] installed %d group(s) (switches y17_centerwindow, y17_resizestrip, y17_splitbounds)", n);
    }
}
#pragma clang diagnostic pop
