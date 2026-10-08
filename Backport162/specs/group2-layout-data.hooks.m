// group2-layout-data.hooks.m
//
// DRAFT. Logos source (rename to .xm or paste into Tweak.x). Backports the portable parts of the iPadOS 16.2 (20C65)
// switcher layout / data layer to 16.0 (20A8372). Behaviour is specified in group2-layout-data.md; the item numbers in
// the comments (A1, A2, ...) are the section numbers of that file.
//
// Every piece is tagged  // PORTABLE,  // PARTIAL: <why>  or  // NOT PORTABLE: <why>.
//
// Integration (Tweak.x is not edited by this draft):
//   * Call BP_G2_Early() from the very first line of the %ctor (it does %init(G2): the protocol hooks must be installed before
//     SBSwitcherModifier receives its first message) and BP_G2_Setup() after the existing %init (later groups).
//   * Compile with ARC (-fobjc-arc). For a standalone syntax check define BP_G2_STANDALONE.
//
// Safety rules followed here:
//   * No ivar of a system class is touched by a hard-coded offset: ivars are found by name (class_getInstanceVariable +
//     ivar_getOffset / object_getIvar). State that 16.2 keeps in ivars that do not exist in 16.0 is kept in associated objects.
//   * Every selector sent to a private object is checked with respondsToSelector: (or class lookup is nil-checked).
//   * Nothing here can crash on nil: every helper returns a neutral value when something is missing.

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

#ifdef BP_G2_STANDALONE
enum { F_G2_COUNT };
static BOOL BP_On(int f) { (void)f; return YES; }
static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) { (void)fmt; }
#else
#import <rootless.h>
#import "BP.h"
#endif

// ------------------------------------------------------------------------------------------------ small runtime helpers

// Read an object ivar by NAME (never by offset). Returns nil if the class has no such ivar or it is not an object.
static id BP_G2_GetIvarObj(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || (enc[0] != '@' && enc[0] != '#')) return nil;
    return object_getIvar(obj, iv);
}

// Read a scalar ivar by name (BOOL / integer / double / CGRect ...) into buf. Returns NO if missing or size mismatch.
static BOOL BP_G2_GetIvarRaw(id obj, const char *name, void *buf, size_t size) {
    if (!obj || !buf) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NO;
    ptrdiff_t off = ivar_getOffset(iv);
    NSUInteger sz = 0;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc) return NO;
    @try { NSGetSizeAndAlignment(enc, &sz, NULL); } @catch (...) { return NO; }
    if (sz != size) return NO;
    memcpy(buf, (const char *)(__bridge void *)obj + off, size);
    return YES;
}

static BOOL BP_G2_SetIvarRaw(id obj, const char *name, const void *buf, size_t size) {
    if (!obj || !buf) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return NO;
    ptrdiff_t off = ivar_getOffset(iv);
    NSUInteger sz = 0;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc) return NO;
    @try { NSGetSizeAndAlignment(enc, &sz, NULL); } @catch (...) { return NO; }
    if (sz != size) return NO;
    memcpy((char *)(__bridge void *)obj + off, buf, size);
    return YES;
}

// Message helpers with explicit types (private selectors are not declared anywhere).
static inline id BP_G2_Obj(id o, SEL s) {
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static inline id BP_G2_Obj1(id o, SEL s, id a) {
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil;
}
static inline BOOL BP_G2_Bool(id o, SEL s) {
    return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO;
}
static inline double BP_G2_Dbl(id o, SEL s) {
    return (o && [o respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(o, s) : 0.0;
}
static inline unsigned long long BP_G2_ULL(id o, SEL s) {
    return (o && [o respondsToSelector:s]) ? ((unsigned long long (*)(id, SEL))objc_msgSend)(o, s) : 0ull;
}
static inline CGRect BP_G2_Rect(id o, SEL s) {
    return (o && [o respondsToSelector:s]) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, s) : CGRectZero;
}
static inline BOOL BP_G2_Equal(id a, id b) { return a == b || (a && b && [a isEqual:b]); }

// Associated-object boxes (state that 16.2 keeps in new ivars of system classes).
static const void *kBP_G2_Box = &kBP_G2_Box;
static id BP_G2_GetAssoc(id obj, const void *key) { return obj ? objc_getAssociatedObject(obj, key) : nil; }
static void BP_G2_SetAssoc(id obj, const void *key, id val) { if (obj) objc_setAssociatedObject(obj, key, val, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

// =================================================================================================================
// Section 0 (framework): extended SBSwitcherModifier protocols, so that 16.2-only query/context selectors get
// chain trampolines (see the md, section 0).
//
// PARTIAL: relies on (1) being installed before +[SBChainableModifier initialize] has run for SBSwitcherModifier,
//          (2) the type encodings below being in SpringBoard's static trampoline table (checked against the 162 table:
//              all of them are).  If a selector is already present in the original protocol it is not added twice.
// =================================================================================================================

typedef struct { const char *sel; const char *types; } BPG2MethodSpec;

// SBSwitcherContextProviding additions (162 protocol dump).
static const BPG2MethodSpec kBPG2NewContext[] = {
    { "appLayoutOnContinuousExposeStage",                         "@16@0:8" },
    { "continuousExposeIdentifiersGenerationCount",               "Q16@0:8" },
    { "continuousExposeIdentifiersInStrip",                       "@16@0:8" },
    { "continuousExposeIdentifiersInSwitcher",                    "@16@0:8" },
    { "continuousExposeStripProgress",                            "d16@0:8" },
    { "continuousExposeStripTongueBackdropCaptureLayoutElement",  "@16@0:8" },
    { "draggingAppLayoutsForContinuousExposeWindowDrag",          "@16@0:8" },
    { "layoutRestrictionInfoForItem:",                            "@24@0:8@16" },
    { "newContinuousExposeIdentifiersGenerationCount",            "Q16@0:8" },
    { "proposedAppLayoutsForContinuousExposeWindowDrag",          "@16@0:8" },
    { "requireStripContentsInViewHierarchy",                      "B16@0:8" },
    { "supportedContentInterfaceOrientationsForItem:",            "Q24@0:8@16" },
};
// Query protocol additions (SBSwitcherQueryProviding + MultitaskingQueryProviding + QueryDefaultImplementationProviding).
static const BPG2MethodSpec kBPG2NewQuery[] = {
    { "activeLeafAppLayoutsReachableByKeyboardShortcut",          "@16@0:8" },
    { "canSelectLeafWithModifierKeysInAppLayout:",                "B24@0:8@16" },
    { "inactiveAppLayoutsReachableByKeyboardShortcut",            "@16@0:8" },
    { "shouldAllowGroupOpacityForAppLayout:",                     "B24@0:8@16" },
    { "adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:", "@24@0:8@16" },
    { "adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:", "@32@0:8@16@24" },
    { "adjustedSpaceAccessoryViewScale:forAppLayout:",            "d32@0:8d16@24" },
    { "isContinuousExposeStripVisible",                           "B16@0:8" },
    { "proposedAppLayoutForContinuousExposeWindowDrag",           "@16@0:8" },
    { "spaceAccessoryViewIconHitTestOutsetForAppLayout:",         "d24@0:8@16" },
    { "wantsContinuousExposeHoverGesture",                        "B16@0:8" },
};

static BOOL BP_G2_ProtocolHasSel(Protocol *p, SEL s) {
    struct objc_method_description d = protocol_getMethodDescription(p, s, YES, YES);
    return d.name != NULL;
}

// Builds a registered protocol "name" = every method of `base` (required+optional instance methods) + `adds`,
// adopting the same single parent protocol list as `base` (the chain walker asserts "at most one sub protocol").
static Protocol *BP_G2_BuildExtendedProtocol(Protocol *base, const char *name, const BPG2MethodSpec *adds, size_t nAdds) {
    if (!base) return nil;
    Protocol *existing = objc_getProtocol(name);
    if (existing) return existing;
    Protocol *np = objc_allocateProtocol(name);
    if (!np) return nil;
    unsigned pc = 0;
    Protocol * __unsafe_unretained *plist = protocol_copyProtocolList(base, &pc);
    for (unsigned i = 0; i < pc; i++) protocol_addProtocol(np, plist[i]);
    free(plist);
    for (int req = 1; req >= 0; req--) {
        unsigned n = 0;
        struct objc_method_description *ms = protocol_copyMethodDescriptionList(base, req ? YES : NO, YES, &n);
        for (unsigned i = 0; i < n; i++) protocol_addMethodDescription(np, ms[i].name, ms[i].types, req ? YES : NO, YES);
        free(ms);
    }
    for (size_t i = 0; i < nAdds; i++) {
        SEL s = sel_registerName(adds[i].sel);
        if (BP_G2_ProtocolHasSel(base, s)) continue;
        protocol_addMethodDescription(np, s, adds[i].types, YES, YES);
    }
    objc_registerProtocol(np);
    return np;
}

// Built lazily from inside the hooked +contextProtocol / +queryProtocol (they are first sent from
// +[SBChainableModifier _initalizeIMPCaching], i.e. during +initialize, so %orig is safe there). We deliberately do NOT
// message SBSwitcherModifier from the %ctor: the first message would run +initialize with the unpatched 16.0 protocols.
static Protocol *gBPG2ExtContext, *gBPG2ExtQuery;

// Walk to the root modifier and return its delegate (the SBFluidSwitcherViewController, which is the final context provider).
// Used by the cheap strategy (B) and by any new class that needs a context value without the chain.
static id BP_G2_RootContextProvider(id modifier) {
    id m = modifier;
    for (int guard = 0; m && guard < 64; guard++) {
        id parent = BP_G2_Obj(m, @selector(parentModifier));
        if (!parent) break;
        m = parent;
    }
    return BP_G2_Obj(m, @selector(delegate));
}

// =================================================================================================================
// A1. SBSwitcherLayoutCalculationsCacheValidityToken (16.2: 5-argument token) as a NEW class.
// PORTABLE: new class, no system class touched. 162 0x1c779f184 (init) / 0x1c779f210 (isEqual:).
// =================================================================================================================

@interface BP162LayoutCalcValidityToken : NSObject
@property (nonatomic) unsigned long long appLayoutsGenCount;
@property (nonatomic) unsigned long long continuousExposeIdentifiersGenCount;
@property (nonatomic) long long switcherInterfaceOrientation;
@property (nonatomic) CGRect containerViewBounds;
@property (nonatomic) unsigned long long modifierEventGenCount;
- (instancetype)initWithAppLayoutsGenCount:(unsigned long long)appLayoutsGen
       continuousExposeIdentifiersGenCount:(unsigned long long)ceIdsGen
              switcherInterfaceOrientation:(long long)orientation
                       containerViewBounds:(CGRect)bounds
                     modifierEventGenCount:(unsigned long long)eventGen;
@end

@implementation BP162LayoutCalcValidityToken
- (instancetype)initWithAppLayoutsGenCount:(unsigned long long)appLayoutsGen
       continuousExposeIdentifiersGenCount:(unsigned long long)ceIdsGen
              switcherInterfaceOrientation:(long long)orientation
                       containerViewBounds:(CGRect)bounds
                     modifierEventGenCount:(unsigned long long)eventGen {
    if ((self = [super init])) {
        _appLayoutsGenCount = appLayoutsGen;
        _continuousExposeIdentifiersGenCount = ceIdsGen;
        _switcherInterfaceOrientation = orientation;
        _containerViewBounds = bounds;
        _modifierEventGenCount = eventGen;
    }
    return self;
}
// 162 0x1c779f210
- (BOOL)isEqual:(id)other {
    if (self == other) return YES;
    if (![other isKindOfClass:[BP162LayoutCalcValidityToken class]]) return NO;
    BP162LayoutCalcValidityToken *o = other;
    return _appLayoutsGenCount == o->_appLayoutsGenCount
        && _continuousExposeIdentifiersGenCount == o->_continuousExposeIdentifiersGenCount
        && _switcherInterfaceOrientation == o->_switcherInterfaceOrientation
        && CGRectEqualToRect(_containerViewBounds, o->_containerViewBounds)
        && _modifierEventGenCount == o->_modifierEventGenCount;
}
- (NSUInteger)hash { return (NSUInteger)(_appLayoutsGenCount * 31u + _continuousExposeIdentifiersGenCount); }   // 16.2 has none; harmless
@end

// =================================================================================================================
// Hook group
// =================================================================================================================

%group G2

// -----------------------------------------------------------------------------------------------------------------
// A1. SBSwitcherLayoutCalculationsCache: 16.2 API names on the 16.0 class.
// PORTABLE
// -----------------------------------------------------------------------------------------------------------------
%hook SBSwitcherLayoutCalculationsCache

// 162 0x1c779eeb8. 160 name: _updateLayoutCalculationsIfNecessaryForValidityToken: (0x1c630158c, same body, delegate gets
// buildLayoutCalculations instead of buildLayoutCalculationsForCache:).
%new
- (void)rebuildIfNecessaryForValidityToken:(id)token {
    if ([self respondsToSelector:@selector(_updateLayoutCalculationsIfNecessaryForValidityToken:)])
        ((void (*)(id, SEL, id))objc_msgSend)(self, @selector(_updateLayoutCalculationsIfNecessaryForValidityToken:), token);
}

// 162 0x1c779efdc readonly getter. The ivar is at 0x10 in 16.0 (0x18 in 16.2): looked up by name.
%new
- (id)validityToken {
    return BP_G2_GetIvarObj(self, "_validityToken");
}

%end // SBSwitcherLayoutCalculationsCache

// -----------------------------------------------------------------------------------------------------------------
// Section 0. Return the extended protocols so the 16.2-only selectors get trampolines.
// PARTIAL: see md section 0 (must be active before the first SBChainableModifier +initialize).
// -----------------------------------------------------------------------------------------------------------------
%hook SBSwitcherModifier

+ (id)contextProtocol {
    id orig = %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gBPG2ExtContext = BP_G2_BuildExtendedProtocol((Protocol *)orig, "BP162_SBSwitcherContextProviding",
                                                      kBPG2NewContext, sizeof kBPG2NewContext / sizeof kBPG2NewContext[0]);
        BP_Log(@"G2: extended context protocol %p (orig %p)", (__bridge void *)gBPG2ExtContext, (__bridge void *)orig);
    });
    return gBPG2ExtContext ?: orig;
}

+ (id)queryProtocol {
    id orig = %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gBPG2ExtQuery = BP_G2_BuildExtendedProtocol((Protocol *)orig, "BP162_SBSwitcherMultitaskingQueryProviding",
                                                    kBPG2NewQuery, sizeof kBPG2NewQuery / sizeof kBPG2NewQuery[0]);
        BP_Log(@"G2: extended query protocol %p (orig %p)", (__bridge void *)gBPG2ExtQuery, (__bridge void *)orig);
    });
    return gBPG2ExtQuery ?: orig;
}

%end // SBSwitcherModifier

%end // %group G2

// =================================================================================================================
// A2. Context-provider selectors on SBFluidSwitcherViewController (the final context provider).
// =================================================================================================================

// State that 16.2 keeps in NEW ivars of the VC (`_continuousExposeIdentifiersInStrip` 162 +0x630, `...InSwitcher` +0x628,
// `_continuousExposeIdentifiersGenerationCount` +0x4b8). ivars cannot be added: associated object.
@interface BP162VCState : NSObject
@property (nonatomic, copy) NSArray *idsInStrip;
@property (nonatomic, copy) NSArray *idsInSwitcher;
@property (nonatomic) unsigned long long idsGeneration;
@end
@implementation BP162VCState
@end

static const void *kBP_G2_VCState = &kBP_G2_VCState;

static BP162VCState *BP_G2_VCStateFor(id vc) {
    if (!vc) return nil;
    BP162VCState *st = objc_getAssociatedObject(vc, kBP_G2_VCState);
    if (!st) {
        st = [BP162VCState new];
        objc_setAssociatedObject(vc, kBP_G2_VCState, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return st;
}

%group G2VC

%hook SBFluidSwitcherViewController

// PORTABLE. 162 0x1c74373dc. Returns @[] instead of nil (162 returns the raw ivar, nil before the first update; every 162 caller
// treats nil like empty, an empty array is the safe superset).
%new
- (id)continuousExposeIdentifiersInStrip {
    return BP_G2_VCStateFor(self).idsInStrip ?: @[];
}

// PORTABLE. 162 0x1c74373cc.
%new
- (id)continuousExposeIdentifiersInSwitcher {
    return BP_G2_VCStateFor(self).idsInSwitcher ?: @[];
}

// PORTABLE. 162 0x1c74364a4 (getter) / 0x1c74364b4 (pre-increment).
%new
- (unsigned long long)continuousExposeIdentifiersGenerationCount {
    return BP_G2_VCStateFor(self).idsGeneration;
}
%new
- (unsigned long long)newContinuousExposeIdentifiersGenerationCount {
    BP162VCState *st = BP_G2_VCStateFor(self);
    if (!st) return 0;
    st.idsGeneration += 1;
    return st.idsGeneration;
}

// PORTABLE. 162 0x1c7436c2c == 160 -continuousExposeAppStripUnoccludedProgress 0x1c5fbe5c0 (identical body, same ivar
// _continuousExposeStripsPresentationOptions: (options & 1) ? 1.0 : 0.0).
%new
- (double)continuousExposeStripProgress {
    if ([self respondsToSelector:@selector(continuousExposeAppStripUnoccludedProgress)])
        return ((double (*)(id, SEL))objc_msgSend)(self, @selector(continuousExposeAppStripUnoccludedProgress));
    unsigned long long opts = 0;       // fallback: read the ivar by name, low byte, bit 0
    if (BP_G2_GetIvarRaw(self, "_continuousExposeStripsPresentationOptions", &opts, sizeof opts)) return (opts & 1) ? 1.0 : 0.0;
    return 0.0;
}

// PORTABLE. 162 0x1c7436c4c (`return NO`; the Transition and Gesture modifiers override it with YES).
%new
- (BOOL)requireStripContentsInViewHierarchy { return NO; }

// PORTABLE. 162 0x1c74388d0 (`return nil`; the Root CE modifier answers it first).
%new
- (id)appLayoutOnContinuousExposeStage { return nil; }

// PORTABLE. 162 0x1c74371c8.
%new
- (id)layoutRestrictionInfoForItem:(id)item {
    id calc = BP_G2_Obj(self, @selector(displayItemLayoutAttributesCalculator));
    return BP_G2_Obj1(calc, @selector(layoutRestrictionInfoForItem:), item);
}

// PORTABLE (if the data source implements the selector; checked). 162 0x1c7436408.
%new
- (unsigned long long)supportedContentInterfaceOrientationsForItem:(id)item {
    id ds = BP_G2_Obj(self, @selector(dataSource));
    SEL sel = @selector(switcherContentController:deviceApplicationSceneHandleForDisplayItem:);
    if (!ds || !item || ![ds respondsToSelector:sel]) return 0;
    id handle = ((id (*)(id, SEL, id, id))objc_msgSend)(ds, sel, self, item);
    SEL oSel = @selector(supportedInterfaceOrientations);
    if (!handle || ![handle respondsToSelector:oSel]) return 0;
    return ((unsigned long long (*)(id, SEL))objc_msgSend)(handle, oSel);
}

// NOT PORTABLE (faithfully): cross-display window drag needs SBMainSwitcherControllerCoordinator -draggingAppLayouts /
// -enumerateSwitcherControllersWithBlock: (162 0x1c76e2df8 / 0x1c76e2214, absent in 16.0). Neutral stubs so that ported
// modifiers can call them.
%new
- (id)draggingAppLayoutsForContinuousExposeWindowDrag { return nil; }
%new
- (id)proposedAppLayoutsForContinuousExposeWindowDrag { return [NSSet set]; }

// NOT PORTABLE: the strip tongue (SBContinuousExposeStripTongueView) does not exist in 16.0.
%new
- (id)continuousExposeStripTongueBackdropCaptureLayoutElement { return nil; }

%end // SBFluidSwitcherViewController

%end // %group G2VC

// PARTIAL fallback for strategy (B) of section 0: if the extended-protocol hook did not take effect (no trampoline was installed
// for a new selector), install forwarding implementations on SBSwitcherModifier that go straight to the root context provider
// (the VC). Chain overrides (stage layout, strip progress in FullScreen/WindowDrag, ...) are ignored by this fallback.
static void BP_G2_InstallContextForwardersIfMissing(void) {
    Class sm = objc_getClass("SBSwitcherModifier");
    if (!sm) return;
    struct { const char *sel; const char *types; int kind; } t[] = {
        { "continuousExposeStripProgress",                  "d16@0:8", 'd' },
        { "requireStripContentsInViewHierarchy",            "B16@0:8", 'B' },
        { "continuousExposeIdentifiersInStrip",             "@16@0:8", '@' },
        { "continuousExposeIdentifiersInSwitcher",          "@16@0:8", '@' },
        { "appLayoutOnContinuousExposeStage",               "@16@0:8", '@' },
        { "continuousExposeIdentifiersGenerationCount",     "Q16@0:8", 'Q' },
    };
    for (size_t i = 0; i < sizeof t / sizeof t[0]; i++) {
        SEL s = sel_registerName(t[i].sel);
        if ([sm instancesRespondToSelector:s]) continue;
        IMP imp = NULL;
        switch (t[i].kind) {
            case 'd': imp = imp_implementationWithBlock(^double(id me) { id p = BP_G2_RootContextProvider(me); return BP_G2_Dbl(p, s); }); break;
            case 'B': imp = imp_implementationWithBlock(^BOOL(id me) { id p = BP_G2_RootContextProvider(me); return BP_G2_Bool(p, s); }); break;
            case 'Q': imp = imp_implementationWithBlock(^unsigned long long(id me) { id p = BP_G2_RootContextProvider(me); return BP_G2_ULL(p, s); }); break;
            default:  imp = imp_implementationWithBlock(^id(id me) { id p = BP_G2_RootContextProvider(me); return BP_G2_Obj(p, s); }); break;
        }
        if (imp && !class_addMethod(sm, s, imp, t[i].types)) imp_removeBlock(imp);
    }
}

// =================================================================================================================
// A3. SBChamoisOverlappingModel / SBMutableChamoisOverlappingModel: 16.2 additions via associated storage.
// PORTABLE (associated object instead of the 8 new ivars; all accessors added with class_addMethod because several take /
// return CGRect / CGPoint, which %new would have to encode by itself).
// =================================================================================================================

@interface BP162OverlapExtras : NSObject {
@public
    NSMutableDictionary *unoccludedPeekingCenters;     // 162 +0x28
    NSMutableDictionary *covered;                      // 162 +0x30
    NSMutableDictionary *overlappingScaleAnchorCenters;// 162 +0x48
    double widthThresholdToHideStrip;                  // 162 +0x50
    NSMutableDictionary *compactedCenters;             // 162 +0x58
    CGRect stageArea;                                  // 162 +0x80
    CGRect compactedBoundingBox;                       // 162 +0xc0
    CGRect stageAreaForResizing;                       // 162 +0xe0
}
@end
@implementation BP162OverlapExtras
- (instancetype)init {
    if ((self = [super init])) {
        unoccludedPeekingCenters = [NSMutableDictionary new];
        covered = [NSMutableDictionary new];
        overlappingScaleAnchorCenters = [NSMutableDictionary new];
        compactedCenters = [NSMutableDictionary new];
    }
    return self;
}
- (BP162OverlapExtras *)deepCopy {
    BP162OverlapExtras *c = [BP162OverlapExtras new];
    c->unoccludedPeekingCenters = [unoccludedPeekingCenters mutableCopy];
    c->covered = [covered mutableCopy];
    c->overlappingScaleAnchorCenters = [overlappingScaleAnchorCenters mutableCopy];
    c->compactedCenters = [compactedCenters mutableCopy];
    c->widthThresholdToHideStrip = widthThresholdToHideStrip;
    c->stageArea = stageArea;
    c->compactedBoundingBox = compactedBoundingBox;
    c->stageAreaForResizing = stageAreaForResizing;
    return c;
}
@end

static const void *kBP_G2_OverlapExtras = &kBP_G2_OverlapExtras;
static BP162OverlapExtras *BP_G2_Extras(id model) {
    if (!model) return nil;
    BP162OverlapExtras *e = objc_getAssociatedObject(model, kBP_G2_OverlapExtras);
    if (!e) {
        e = [BP162OverlapExtras new];
        objc_setAssociatedObject(model, kBP_G2_OverlapExtras, e, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return e;
}

static CGPoint BP_G2_PointFor(NSDictionary *d, id key) {
    id v = key ? d[key] : nil;
    return v ? [v CGPointValue] : CGPointZero;      // 162 sends -CGPointValue to nil == {0,0}
}

#define BPG2_RECT  "{CGRect={CGPoint=dd}{CGSize=dd}}"
#define BPG2_POINT "{CGPoint=dd}"

// ---- getters / setters (Immutable class; the Mutable subclass inherits them) -----------------------------------
static id    imp_unoccludedPeekingCentersForItems(id self, SEL _cmd) { return BP_G2_Extras(self)->unoccludedPeekingCenters; }
static void  imp_setUnoccludedPeekingCentersForItems(id self, SEL _cmd, id v) { BP_G2_Extras(self)->unoccludedPeekingCenters = [v mutableCopy] ?: [NSMutableDictionary new]; }
static id    imp_coveredForItems(id self, SEL _cmd) { return BP_G2_Extras(self)->covered; }
static void  imp_setCoveredForItems(id self, SEL _cmd, id v) { BP_G2_Extras(self)->covered = [v mutableCopy] ?: [NSMutableDictionary new]; }
static id    imp_overlappingScaleAnchorCentersForItems(id self, SEL _cmd) { return BP_G2_Extras(self)->overlappingScaleAnchorCenters; }
static void  imp_setOverlappingScaleAnchorCentersForItems(id self, SEL _cmd, id v) { BP_G2_Extras(self)->overlappingScaleAnchorCenters = [v mutableCopy] ?: [NSMutableDictionary new]; }
static id    imp_compactedCentersForItems(id self, SEL _cmd) { return BP_G2_Extras(self)->compactedCenters; }
static void  imp_setCompactedCentersForItems(id self, SEL _cmd, id v) { BP_G2_Extras(self)->compactedCenters = [v mutableCopy] ?: [NSMutableDictionary new]; }
static double imp_widthThresholdToHideStrip(id self, SEL _cmd) { return BP_G2_Extras(self)->widthThresholdToHideStrip; }
static void  imp_setWidthThresholdToHideStrip(id self, SEL _cmd, double v) { BP_G2_Extras(self)->widthThresholdToHideStrip = v; }
static CGRect imp_stageArea(id self, SEL _cmd) { return BP_G2_Extras(self)->stageArea; }
static void  imp_setStageArea(id self, SEL _cmd, CGRect r) { BP_G2_Extras(self)->stageArea = r; }
static CGRect imp_compactedBoundingBox(id self, SEL _cmd) { return BP_G2_Extras(self)->compactedBoundingBox; }
static void  imp_setCompactedBoundingBox(id self, SEL _cmd, CGRect r) { BP_G2_Extras(self)->compactedBoundingBox = r; }
static CGRect imp_stageAreaForResizing(id self, SEL _cmd) { return BP_G2_Extras(self)->stageAreaForResizing; }
static void  imp_setStageAreaForResizing(id self, SEL _cmd, CGRect r) { BP_G2_Extras(self)->stageAreaForResizing = r; }

// ---- per item queries (162 0x1c797a37c / a3c8 / a6e0 / a4ec / a558) -------------------------------------------------
static CGPoint imp_unoccludedPeekingCenterForItem(id self, SEL _cmd, id item) { return BP_G2_PointFor(BP_G2_Extras(self)->unoccludedPeekingCenters, item); }
static CGPoint imp_overlappingScaleAnchorCenterForItem(id self, SEL _cmd, id item) { return BP_G2_PointFor(BP_G2_Extras(self)->overlappingScaleAnchorCenters, item); }
static CGPoint imp_compactedCenterForItem(id self, SEL _cmd, id item) { return BP_G2_PointFor(BP_G2_Extras(self)->compactedCenters, item); }
static BOOL imp_isItemCoveredByFullyOccludedPeekingItem(id self, SEL _cmd, id item) {
    id v = item ? BP_G2_Extras(self)->covered[item] : nil;
    return [v boolValue];
}
static BOOL imp_isContinuousExposeStripVisible(id self, SEL _cmd) {
    NSArray *items = BP_G2_Obj(self, @selector(items));
    if (![items isKindOfClass:[NSArray class]]) return YES;
    double thr = BP_G2_Extras(self)->widthThresholdToHideStrip;
    SEL szSel = @selector(sizeForItem:);
    if (![self respondsToSelector:szSel]) return YES;
    for (id item in items) {
        CGSize s = ((CGSize (*)(id, SEL, id))objc_msgSend)(self, szSel, item);
        // BSFloatGreaterThanOrEqualToFloat(width, threshold): epsilon compare in BaseBoard; plain >= with a tiny epsilon here.
        if (s.width >= thr - 1e-9) return NO;
    }
    return YES;
}

// ---- 162 4-argument init as a wrapper over the 16.0 6-argument init --------------------------------------------------
static id imp_initWithItems4(id self, SEL _cmd, id items, id centers, id sizes, CGRect containerBounds) {
    SEL old = sel_registerName("initWithItems:centersForItems:sizesForItems:userConfiguredSizesBeforeAutoResizingForItems:containerBounds:boundingBox:");
    if (![self respondsToSelector:old]) return nil;
    return ((id (*)(id, SEL, id, id, id, id, CGRect, CGRect))objc_msgSend)(self, old, items, centers, sizes, @{}, containerBounds, CGRectZero);
}

// ---- Mutable subclass mutators (162 0x1c797b378 / b410 / b4a8 / b658) ------------------------------------------------
static void imp_setUnoccludedPeekingCenter(id self, SEL _cmd, CGPoint p, id item) {
    if (item) BP_G2_Extras(self)->unoccludedPeekingCenters[item] = [NSValue valueWithCGPoint:p];
}
static void imp_setOverlappingScaleAnchorCenter(id self, SEL _cmd, CGPoint p, id item) {
    if (item) BP_G2_Extras(self)->overlappingScaleAnchorCenters[item] = [NSValue valueWithCGPoint:p];
}
static void imp_setCoveredByFullyOccludedPeekingItem(id self, SEL _cmd, BOOL b, id item) {
    if (item) BP_G2_Extras(self)->covered[item] = @(b);
}
static void imp_setCompactedCenter(id self, SEL _cmd, CGPoint p, id item) {
    if (item) BP_G2_Extras(self)->compactedCenters[item] = [NSValue valueWithCGPoint:p];
}

static void BP_G2_AddIfMissing(Class c, const char *sel, IMP imp, const char *types) {
    if (!c) return;
    SEL s = sel_registerName(sel);
    if (class_getInstanceMethod(c, s)) return;           // never override something that already exists
    class_addMethod(c, s, imp, types);
}

%group G2Model
%hook SBChamoisOverlappingModel

// 162 0x1c797a72c: the mutable copy carries the extras. (16.0 body: alloc_init SBMutableChamoisOverlappingModel + setters.)
- (id)mutableCopyWithZone:(NSZone *)zone {
    id copy = %orig;
    BP162OverlapExtras *e = objc_getAssociatedObject(self, kBP_G2_OverlapExtras);
    if (copy && e) objc_setAssociatedObject(copy, kBP_G2_OverlapExtras, [e deepCopy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return copy;
}

%end
%end // %group G2Model

static void BP_G2_SetupModel(void) {
    Class m  = objc_getClass("SBChamoisOverlappingModel");
    Class mm = objc_getClass("SBMutableChamoisOverlappingModel");
    if (!m) return;
    %init(G2Model);
    BP_G2_AddIfMissing(m, "unoccludedPeekingCentersForItems", (IMP)imp_unoccludedPeekingCentersForItems, "@16@0:8");
    BP_G2_AddIfMissing(m, "setUnoccludedPeekingCentersForItems:", (IMP)imp_setUnoccludedPeekingCentersForItems, "v24@0:8@16");
    BP_G2_AddIfMissing(m, "coveredForItems", (IMP)imp_coveredForItems, "@16@0:8");
    BP_G2_AddIfMissing(m, "setCoveredForItems:", (IMP)imp_setCoveredForItems, "v24@0:8@16");
    BP_G2_AddIfMissing(m, "overlappingScaleAnchorCentersForItems", (IMP)imp_overlappingScaleAnchorCentersForItems, "@16@0:8");
    BP_G2_AddIfMissing(m, "setOverlappingScaleAnchorCentersForItems:", (IMP)imp_setOverlappingScaleAnchorCentersForItems, "v24@0:8@16");
    BP_G2_AddIfMissing(m, "compactedCentersForItems", (IMP)imp_compactedCentersForItems, "@16@0:8");
    BP_G2_AddIfMissing(m, "setCompactedCentersForItems:", (IMP)imp_setCompactedCentersForItems, "v24@0:8@16");
    BP_G2_AddIfMissing(m, "widthThresholdToHideStrip", (IMP)imp_widthThresholdToHideStrip, "d16@0:8");
    BP_G2_AddIfMissing(m, "setWidthThresholdToHideStrip:", (IMP)imp_setWidthThresholdToHideStrip, "v24@0:8d16");
    BP_G2_AddIfMissing(m, "stageArea", (IMP)imp_stageArea, BPG2_RECT "16@0:8");
    BP_G2_AddIfMissing(m, "setStageArea:", (IMP)imp_setStageArea, "v48@0:8" BPG2_RECT "16");
    BP_G2_AddIfMissing(m, "compactedBoundingBox", (IMP)imp_compactedBoundingBox, BPG2_RECT "16@0:8");
    BP_G2_AddIfMissing(m, "setCompactedBoundingBox:", (IMP)imp_setCompactedBoundingBox, "v48@0:8" BPG2_RECT "16");
    BP_G2_AddIfMissing(m, "stageAreaForResizing", (IMP)imp_stageAreaForResizing, BPG2_RECT "16@0:8");
    BP_G2_AddIfMissing(m, "setStageAreaForResizing:", (IMP)imp_setStageAreaForResizing, "v48@0:8" BPG2_RECT "16");
    BP_G2_AddIfMissing(m, "unoccludedPeekingCenterForItem:", (IMP)imp_unoccludedPeekingCenterForItem, BPG2_POINT "24@0:8@16");
    BP_G2_AddIfMissing(m, "overlappingScaleAnchorCenterForItem:", (IMP)imp_overlappingScaleAnchorCenterForItem, BPG2_POINT "24@0:8@16");
    BP_G2_AddIfMissing(m, "compactedCenterForItem:", (IMP)imp_compactedCenterForItem, BPG2_POINT "24@0:8@16");
    BP_G2_AddIfMissing(m, "isItemCoveredByFullyOccludedPeekingItem:", (IMP)imp_isItemCoveredByFullyOccludedPeekingItem, "B24@0:8@16");
    BP_G2_AddIfMissing(m, "isContinuousExposeStripVisible", (IMP)imp_isContinuousExposeStripVisible, "B16@0:8");
    BP_G2_AddIfMissing(m, "initWithItems:centersForItems:sizesForItems:containerBounds:", (IMP)imp_initWithItems4,
                       "@72@0:8@16@24@32" BPG2_RECT "40");
    BP_G2_AddIfMissing(mm, "setUnoccludedPeekingCenterForItem:forItem:", (IMP)imp_setUnoccludedPeekingCenter, "v40@0:8" BPG2_POINT "16@32");
    BP_G2_AddIfMissing(mm, "setOverlappingScaleAnchorCenter:forItem:", (IMP)imp_setOverlappingScaleAnchorCenter, "v40@0:8" BPG2_POINT "16@32");
    BP_G2_AddIfMissing(mm, "setCoveredByFullyOccludedPeekingItem:forItem:", (IMP)imp_setCoveredByFullyOccludedPeekingItem, "v32@0:8B16@24");
    BP_G2_AddIfMissing(mm, "setCompactedCenter:forItem:", (IMP)imp_setCompactedCenter, "v40@0:8" BPG2_POINT "16@32");
}

// =================================================================================================================
// Entry points
// =================================================================================================================

// Call first thing in %ctor (before anything can message an SBChainableModifier subclass). The only requirement is that
// the +contextProtocol / +queryProtocol hooks are installed before SBSwitcherModifier's first message, so simply %init(G2) early.
static void BP_G2_Early(void) { %init(G2); }

// Call from %ctor after the build check and the existing %init.
static void BP_G2_Setup(void) {
    // G2 (protocol hooks) was initialised in BP_G2_Early; later groups are initialised here.
    %init(G2VC);
    BP_G2_InstallContextForwardersIfMissing();      // no-op when the extended protocols produced the trampolines
    BP_G2_SetupModel();                              // A3
}

// ===== END OF PART A1 (more sections are appended below as the analysis proceeds) =====
