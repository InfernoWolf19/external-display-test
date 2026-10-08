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
#import <dlfcn.h>
#import <float.h>
#import <math.h>

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
// A4. SBChamoisOverlappingController (16.2 auto-layout) as a NEW class.
// PORTABLE (no system class is modified). Requires the A3 model extras and the A5 attribute extras.
// Reconstruction of 162 0x1c73c9b2c..0x1c73cf6.. ; section numbers refer to the md (A4.1 / A4.2).
// UNSURE spots are marked and also listed in the md.
// =================================================================================================================

// ---- CoreGraphics region SPI (resolved lazily; if anything is missing the controller refuses to run) ------------------
typedef CFTypeRef BPG2Region;
static struct {
    BPG2Region (*withRect)(CGRect);
    BPG2Region (*unionR)(BPG2Region, BPG2Region);
    BPG2Region (*diffR)(BPG2Region, BPG2Region);
    BPG2Region (*interR)(BPG2Region, BPG2Region);
    bool (*isEmpty)(BPG2Region);
    CGRect (*bbox)(BPG2Region);
    bool (*equalR)(BPG2Region, BPG2Region);
    bool (*intersects)(BPG2Region, BPG2Region);
    BOOL ok;
} gRgn;
static int (*gBSEq)(double, double), (*gBSGT)(double, double), (*gBSLT)(double, double), (*gBSGE)(double, double), (*gBSLE)(double, double);

static BOOL BP_G2_ResolveRegionSPI(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gRgn.withRect   = dlsym(RTLD_DEFAULT, "CGRegionCreateWithRect");
        gRgn.unionR     = dlsym(RTLD_DEFAULT, "CGRegionCreateUnionWithRegion");
        gRgn.diffR      = dlsym(RTLD_DEFAULT, "CGRegionCreateDifferenceWithRegion");
        gRgn.interR     = dlsym(RTLD_DEFAULT, "CGRegionCreateIntersectionWithRegion");
        gRgn.isEmpty    = dlsym(RTLD_DEFAULT, "CGRegionIsEmpty");
        gRgn.bbox       = dlsym(RTLD_DEFAULT, "CGRegionGetBoundingBox");
        gRgn.equalR     = dlsym(RTLD_DEFAULT, "CGRegionEqualToRegion");
        gRgn.intersects = dlsym(RTLD_DEFAULT, "CGRegionIntersectsRegion");
        gBSEq = dlsym(RTLD_DEFAULT, "BSFloatEqualToFloat");
        gBSGT = dlsym(RTLD_DEFAULT, "BSFloatGreaterThanFloat");
        gBSLT = dlsym(RTLD_DEFAULT, "BSFloatLessThanFloat");
        gBSGE = dlsym(RTLD_DEFAULT, "BSFloatGreaterThanOrEqualToFloat");
        gBSLE = dlsym(RTLD_DEFAULT, "BSFloatLessThanOrEqualToFloat");
        gRgn.ok = gRgn.withRect && gRgn.unionR && gRgn.diffR && gRgn.interR && gRgn.isEmpty && gRgn.bbox && gRgn.equalR && gRgn.intersects;
    });
    return gRgn.ok;
}
// BaseBoard float compares (exported functions); epsilon fallbacks when dlsym fails.
static inline BOOL FEq(double a, double b) { return gBSEq ? gBSEq(a, b) : fabs(a - b) < 1e-9; }
static inline BOOL FGT(double a, double b) { return gBSGT ? gBSGT(a, b) : (a > b && !FEq(a, b)); }
static inline BOOL FLT(double a, double b) { return gBSLT ? gBSLT(a, b) : (a < b && !FEq(a, b)); }
static inline BOOL FGE(double a, double b) { return gBSGE ? gBSGE(a, b) : (a > b || FEq(a, b)); }
static inline BOOL FLE(double a, double b) { return gBSLE ? gBSLE(a, b) : (a < b || FEq(a, b)); }

// Autoreleased region helper == SBSafeAutoreleasedRegionFromCGRect (162 0x1c77fd474): nil-safe.
static BPG2Region RgnR(CGRect r) {
    BPG2Region g = gRgn.withRect(r);
    return g ? (BPG2Region)CFAutorelease(g) : NULL;
}
static BPG2Region RgnUnion(BPG2Region a, BPG2Region b) { BPG2Region g = gRgn.unionR(a, b); return g ? (BPG2Region)CFAutorelease(g) : NULL; }
static BPG2Region RgnDiff(BPG2Region a, BPG2Region b)  { BPG2Region g = gRgn.diffR(a, b);  return g ? (BPG2Region)CFAutorelease(g) : NULL; }
static BPG2Region RgnInter(BPG2Region a, BPG2Region b) { BPG2Region g = gRgn.interR(a, b); return g ? (BPG2Region)CFAutorelease(g) : NULL; }

// ---- typed message helpers on model / attributes ----------------------------------------------------------------------
static CGPoint M_Center(id m, id item) { return ((CGPoint (*)(id, SEL, id))objc_msgSend)(m, @selector(centerForItem:), item); }
static CGSize  M_Size(id m, id item)   { return ((CGSize (*)(id, SEL, id))objc_msgSend)(m, @selector(sizeForItem:), item); }
static void    M_SetCenter(id m, CGPoint p, id item) { ((void (*)(id, SEL, CGPoint, id))objc_msgSend)(m, @selector(setCenter:forItem:), p, item); }
static BOOL    M_Full(id m, id item)    { return ((BOOL (*)(id, SEL, id))objc_msgSend)(m, @selector(isItemFullyOccluded:), item); }
static BOOL    M_Partial(id m, id item) { return ((BOOL (*)(id, SEL, id))objc_msgSend)(m, @selector(isItemPartiallyOccluded:), item); }
static CGPoint M_PeekCenter(id m, id item)   { return ((CGPoint (*)(id, SEL, id))objc_msgSend)(m, sel_registerName("unoccludedPeekingCenterForItem:"), item); }
static CGPoint M_AnchorCenter(id m, id item) { return ((CGPoint (*)(id, SEL, id))objc_msgSend)(m, sel_registerName("overlappingScaleAnchorCenterForItem:"), item); }
static NSArray *M_Items(id m) { return ((NSArray *(*)(id, SEL))objc_msgSend)(m, @selector(items)) ?: @[]; }
static CGRect  M_Rect(id m, id item) {
    CGPoint c = M_Center(m, item); CGSize s = M_Size(m, item);
    return CGRectMake(c.x - s.width * 0.5, c.y - s.height * 0.5, s.width, s.height);
}
static double A_D(id a, const char *sel, double dflt) {
    SEL s = sel_registerName(sel);
    return (a && [a respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(a, s) : dflt;
}
static CGSize A_Size(id a, const char *sel) {
    SEL s = sel_registerName(sel);
    return (a && [a respondsToSelector:s]) ? ((CGSize (*)(id, SEL))objc_msgSend)(a, s) : CGSizeZero;
}
static BOOL A_B(id a, const char *sel) {
    SEL s = sel_registerName(sel);
    return (a && [a respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(a, s) : NO;
}
static double A_PartialScale(id a, CGSize size) {            // 162 0x1c78c336c, A5
    SEL s = sel_registerName("partiallyOccludedStageScaleForItemWithSize:");
    return (a && [a respondsToSelector:s]) ? ((double (*)(id, SEL, CGSize))objc_msgSend)(a, s, size) : 1.0;
}
static NSArray *ArrInsertOrMove(NSArray *arr, id obj, NSUInteger idx) {
    SEL s = sel_registerName("sb_arrayByInsertingOrMovingObject:toIndex:");
    if ([arr respondsToSelector:s]) return ((NSArray *(*)(id, SEL, id, NSUInteger))objc_msgSend)(arr, s, obj, idx) ?: arr;
    NSMutableArray *m = [arr mutableCopy]; [m removeObject:obj]; [m insertObject:obj atIndex:MIN(idx, m.count)]; return m;
}
static NSArray *ArrAddOrMove(NSArray *arr, id obj) {
    SEL s = sel_registerName("sb_arrayByAddingOrMovingObject:");
    if ([arr respondsToSelector:s]) return ((NSArray *(*)(id, SEL, id))objc_msgSend)(arr, s, obj) ?: arr;
    NSMutableArray *m = [arr mutableCopy]; [m removeObject:obj]; [m addObject:obj]; return m;
}
static NSArray *ArrReverse(NSArray *arr) { return [[arr reverseObjectEnumerator] allObjects]; }          // == bs_reverse
static CGRect RectRoundToScale(CGRect r, double scale) {                                                  // UIRectRoundToScale
    if (scale <= 0) return r;
    double x0 = round(r.origin.x * scale) / scale, y0 = round(r.origin.y * scale) / scale;
    double x1 = round((r.origin.x + r.size.width) * scale) / scale, y1 = round((r.origin.y + r.size.height) * scale) / scale;
    return CGRectMake(x0, y0, x1 - x0, y1 - y0);
}

@interface BP162ChamoisOverlappingController : NSObject {
    BOOL _reentrancyGuard;                                  // 162 +0x8
}
- (id)modelByPerformingAutoLayoutForModel:(id)model chamoisLayoutAttributes:(id)attrs draggingItem:(id)dragging modelBeforeDragging:(id)before
                       floatingDockHeight:(double)dockH bounds:(CGRect)bounds screenScale:(double)scale
                       prefersStripHidden:(BOOL)ps prefersDockHidden:(BOOL)pd;
@end

@implementation BP162ChamoisOverlappingController

// 162 0x1c73c9b2c
- (id)modelByPerformingAutoLayoutForModel:(id)model chamoisLayoutAttributes:(id)attrs draggingItem:(id)dragging modelBeforeDragging:(id)before
                       floatingDockHeight:(double)dockH bounds:(CGRect)bounds screenScale:(double)scale
                       prefersStripHidden:(BOOL)ps prefersDockHidden:(BOOL)pd {
    return [self _perform:model attrs:attrs dragging:dragging before:before dockH:dockH bounds:bounds scale:scale ps:ps pd:pd inset:UIEdgeInsetsZero];
}

// 162 0x1c73c9b6c (A4.1)
- (id)_perform:(id)model attrs:(id)attrs dragging:(id)dragging before:(id)before dockH:(double)dockH bounds:(CGRect)bounds scale:(double)scale
            ps:(BOOL)ps pd:(BOOL)pd inset:(UIEdgeInsets)inset {
    if (!model || !attrs || !BP_G2_ResolveRegionSPI()) return nil;
    if (M_Items(model).count == 0) return nil;
    id mc = [model mutableCopy];
    if (!mc) return nil;
    double thr = [self _widthThresholdForModel:mc attrs:attrs bounds:bounds];
    CGRect r = [self _stageAreaForModel:mc attrs:attrs dockH:dockH bounds:bounds ps:ps pd:pd threshold:thr];
    CGRect stage = CGRectMake(r.origin.x + inset.left, r.origin.y + inset.top, r.size.width - (inset.left + inset.right), r.size.height - (inset.top + inset.bottom));
    ((void (*)(id, SEL, CGRect))objc_msgSend)(mc, @selector(setContainerBounds:), bounds);
    ((void (*)(id, SEL, CGRect))objc_msgSend)(mc, sel_registerName("setStageArea:"), stage);
    ((void (*)(id, SEL, double))objc_msgSend)(mc, sel_registerName("setWidthThresholdToHideStrip:"), thr);
    [self _snap:mc dragging:dragging];
    NSArray *sorted = [self _itemsSortedByXInModel:mc before:before dragging:dragging];
    [self _constrainH:mc stage:stage];
    NSArray *cols = [self _columnsInModel:mc sorted:sorted before:before attrs:attrs dragging:dragging];
    [self _constrainV:mc stage:stage];
    double tw = [self _totalWidthOfColumns:cols inModel:mc attrs:attrs];
    double stageX1 = stage.origin.x, stageW1 = stage.size.width;                  // saved for the stageAreaForResizing pass ([sp+0x38]/[sp+0x30])
    if (FLT(tw, stage.size.width)) {
        double rightGap = bounds.size.width - (stage.origin.x + stage.size.width);
        double shift = (stage.size.width - tw) * 0.5;
        if (FGT(stage.origin.x, rightGap)) shift -= (stage.origin.x - rightGap) * 0.5;
        stage.origin.x += shift;  stage.size.width = tw;
        stageX1 = stage.origin.x; stageW1 = stage.size.width;
    }
    ((void (*)(id, SEL, CGRect))objc_msgSend)(mc, sel_registerName("setStageArea:"), stage);
    [self _compactH:mc cols:cols attrs:attrs];                                      // _compactSpacingVertically is a no-op in 162
    [self _expandH:mc cols:cols before:before attrs:attrs dragging:dragging stage:stage];
    [self _expandV:mc cols:cols attrs:attrs stage:stage];
    [self _vCenter:mc cols:cols stage:stage];
    if (!dragging) {
        [self _hCenter:mc stage:stage];
        NSArray *its = M_Items(mc);
        if (its.count == 1) {
            id only = its.firstObject; CGPoint c = M_Center(mc, only);
            CGPoint sc = CGPointMake(CGRectGetMidX(stage), CGRectGetMidY(stage));
            M_SetCenter(mc, CGPointMake(c.x, sc.y), only);
        }
    }
    [self _dodge:mc attrs:attrs dragging:dragging bounds:bounds];

    if (!_reentrancyGuard) {
        NSArray *sorted2 = [self _itemsSortedByXInModel:mc before:before dragging:dragging];
        NSArray *cols2 = [self _columnsInModel:mc sorted:sorted2 before:before attrs:attrs dragging:dragging];
        if (![self _isColumns:cols equalTo:cols2]) {
            _reentrancyGuard = YES;
            id again = [self _perform:mc attrs:attrs dragging:dragging before:before dockH:dockH bounds:bounds scale:scale ps:ps pd:pd inset:inset];
            mc = [again mutableCopy] ?: mc;
            _reentrancyGuard = NO;
        }
        if (UIEdgeInsetsEqualToEdgeInsets(inset, UIEdgeInsetsZero)) {              // only the outermost pass
            BOOL anyFull = NO, anyFullScreen = NO;
            for (id item in M_Items(mc)) {
                anyFull |= M_Full(mc, item);
                CGSize s = M_Size(mc, item);
                anyFullScreen |= (s.width == bounds.size.width && s.height == bounds.size.height);
            }
            if (!anyFullScreen && anyFull) {
                double peekScale = A_D(attrs, "stageOcclusionDodgingPeekScale", 0), pad = A_D(attrs, "screenEdgePadding", 0), peekLen = A_D(attrs, "stageOcclusionDodgingPeekLength", 0);
                double leftInset = 0, rightInset = 0;
                for (id item in M_Items(mc)) {
                    if (!M_Full(mc, item)) continue;
                    CGPoint pc = M_PeekCenter(mc, item);
                    if (pc.x == 0 && pc.y == 0) continue;                         // CGPointZero (GOT 0x1d83e1c50): no peek position
                    double half = M_Size(mc, item).width * 0.5 * peekScale;
                    if (FLT(pc.x - half, pad)) leftInset = peekLen;
                    else if (FGT(pc.x + half, bounds.size.width - pad)) rightInset = peekLen;
                }
                if (leftInset != 0 || rightInset != 0) {
                    _reentrancyGuard = YES;
                    id again = [self _perform:mc attrs:attrs dragging:dragging before:before dockH:dockH bounds:bounds scale:scale ps:ps pd:pd
                                        inset:UIEdgeInsetsMake(0, leftInset, 0, rightInset)];
                    mc = [again mutableCopy] ?: mc;
                    _reentrancyGuard = NO;
                }
            }
        }
    }

    NSDictionary *anchors = [self _overlappingScaleAnchorCentersForModel:mc attrs:attrs];
    SEL setAnchor = sel_registerName("setOverlappingScaleAnchorCenter:forItem:");
    for (id item in M_Items(mc)) {
        NSValue *v = anchors[item];
        ((void (*)(id, SEL, CGPoint, id))objc_msgSend)(mc, setAnchor, v ? [v CGPointValue] : CGPointZero, item);
    }

    double compact = A_D(attrs, "switcherPileCompactingFactor", 1.0);
    CGPoint bc = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    double peekScale = A_D(attrs, "stageOcclusionDodgingPeekScale", 1.0);
    CGRect bb = CGRectNull, cbb = CGRectNull;
    SEL setCompacted = sel_registerName("setCompactedCenter:forItem:");
    for (id item in M_Items(mc)) {
        CGSize s = M_Size(mc, item); CGPoint c; double k;
        if (M_Full(mc, item)) { c = M_PeekCenter(mc, item); k = peekScale; }
        else {
            c = M_Center(mc, item); CGPoint a = M_AnchorCenter(mc, item);
            k = M_Partial(mc, item) ? A_PartialScale(attrs, s) : 1.0;
            c.x -= (c.x - a.x) * (1 - k);  c.y -= (c.y - a.y) * (1 - k);
        }
        CGRect rect = CGRectMake(c.x - s.width * k * 0.5, c.y - s.height * k * 0.5, s.width * k, s.height * k);
        bb = CGRectIsNull(bb) ? rect : CGRectUnion(bb, rect);
        CGPoint cc = CGPointMake(bc.x + compact * (c.x - bc.x), bc.y + compact * (c.y - bc.y));
        ((void (*)(id, SEL, CGPoint, id))objc_msgSend)(mc, setCompacted, cc, item);
        CGRect crect = CGRectMake(cc.x - s.width * k * 0.5, cc.y - s.height * k * 0.5, s.width * k, s.height * k);
        cbb = CGRectIsNull(cbb) ? crect : CGRectUnion(cbb, crect);
    }
    if (CGRectIsNull(bb)) bb = CGRectZero;
    if (CGRectIsNull(cbb)) cbb = CGRectZero;
    ((void (*)(id, SEL, CGRect))objc_msgSend)(mc, @selector(setBoundingBox:), RectRoundToScale(bb, scale));
    ((void (*)(id, SEL, CGRect))objc_msgSend)(mc, sel_registerName("setCompactedBoundingBox:"), RectRoundToScale(cbb, scale));
    [self _flagCoveredInModel:mc attrs:attrs];

    CGRect r2 = [self _stageAreaForModel:mc attrs:attrs dockH:dockH bounds:bounds ps:ps pd:pd threshold:thr];
    NSArray *s3 = [self _itemsSortedByXInModel:mc before:nil dragging:nil];
    NSArray *c3 = [self _columnsInModel:mc sorted:s3 before:nil attrs:attrs dragging:nil];
    double w3 = r2.size.width;
    if (c3.count >= 2 && FLT([self _totalWidthOfColumns:c3 inModel:mc attrs:attrs], r2.size.width)) {
        double rightGap2 = bounds.size.width - (stageX1 + stageW1);
        double shift = (r2.size.width - tw) * 0.5;
        if (FGT(r2.origin.x, rightGap2)) shift -= (r2.origin.x - rightGap2) * 0.5;
        r2.origin.x += shift;  w3 = tw;
    }
    ((void (*)(id, SEL, CGRect))objc_msgSend)(mc, sel_registerName("setStageAreaForResizing:"), CGRectMake(r2.origin.x, r2.origin.y, w3, r2.size.height));
    return mc;
}

// 162 0x1c73caf94
- (double)_widthThresholdForModel:(id)m attrs:(id)a bounds:(CGRect)b {
    if (A_B(a, "usesStripAreaForOverlapping") && M_Items(m).count >= 2) {
        NSArray *sorted = [self _itemsSortedByXInModel:m before:nil dragging:nil];
        NSArray *cols = [self _columnsInModel:m sorted:sorted before:nil attrs:a dragging:nil];
        if (FGT([self _totalWidthOfColumns:cols inModel:m attrs:a], b.size.width + A_D(a, "screenEdgePadding", 0) * -3.0)) return 0.0;
    }
    double s = MIN(A_D(a, "stripWidth", 0), (b.size.width - A_Size(a, "minimumDefaultWindowSize").width) * 0.5);
    double v = (M_Items(m).count > 1) ? s : s * 0.5;
    return b.size.width - 2 * v;
}

// 162 0x1c73cb104
- (CGRect)_stageAreaForModel:(id)m attrs:(id)a dockH:(double)dockH bounds:(CGRect)b ps:(BOOL)ps pd:(BOOL)pd threshold:(double)thr {
    double pad = A_D(a, "screenEdgePadding", 0), strip = A_D(a, "stripWidth", 0), minW = A_Size(a, "minimumDefaultWindowSize").width, maxHDock = A_D(a, "maximumWindowHeightWithDock", b.size.height);
    double twoPad = 2 * pad, maxItemW = -DBL_MAX;
    BOOL anyWide = NO, anyTall = NO, anyFull = NO;
    for (id item in M_Items(m)) {
        CGSize s = M_Size(m, item); maxItemW = MAX(maxItemW, s.width);
        if (!anyWide) anyWide = FGE(s.width, thr);
        if (!anyTall) anyTall = FGT(s.height, (b.size.height - dockH) - twoPad);
        if (!anyFull) anyFull = FGT(s.width, b.size.width - twoPad) ? FGT(s.height, b.size.height - twoPad) : NO;
    }
    if (anyFull) return b;
    double cap = MIN(strip, (b.size.width - minW) * 0.5);
    double stripSide = (ps && pd) ? 0 : pad;
    if (!ps) stripSide = anyWide ? pad : MIN(cap, (b.size.width - maxItemW) * 0.5);
    double otherSide = MIN(stripSide, pad);
    double height = pd ? (b.size.height - twoPad) : (anyTall ? (b.size.height - twoPad) : maxHDock);
    CGRect out;
    out.origin.y = (ps && pd) ? 0 : pad;
    out.size.height = (ps && pd) ? b.size.height : height;
    BOOL rtl = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    out.origin.x = rtl ? otherSide : stripSide;
    out.size.width = b.size.width - stripSide - otherSide;
    return out;
}

// 162 0x1c73cb40c (identical to 160 0x1c5f55404 except bs_reverse)
- (void)_snap:(id)m dragging:(id)dragging {
    NSArray *items = M_Items(m);
    if (items.count < 2) return;
    for (id a in ArrReverse(items)) {
        for (id b in items) {
            if (dragging && ([dragging isEqual:a] || [dragging isEqual:b])) break;        // UNSURE: break vs continue (both jump to the same target; identical in 160)
            if ([a isEqual:b]) continue;
            double aL = M_Center(m, a).x - M_Size(m, a).width * 0.5;
            double bL = M_Center(m, b).x - M_Size(m, b).width * 0.5;
            if (fabs(aL - bL) < 44.0) M_SetCenter(m, CGPointMake(aL + M_Size(m, b).width * 0.5, M_Center(m, b).y), b);
            double aR = M_Center(m, a).x + M_Size(m, a).width * 0.5;
            double bR = M_Center(m, b).x + M_Size(m, b).width * 0.5;
            if (fabs(aR - bR) < 44.0) M_SetCenter(m, CGPointMake(aR - M_Size(m, b).width * 0.5, M_Center(m, b).y), b);
            double aT = M_Center(m, a).y - M_Size(m, a).height * 0.5;
            double bT = M_Center(m, b).y - M_Size(m, b).height * 0.5;
            if (fabs(aT - bT) < 44.0) M_SetCenter(m, CGPointMake(M_Center(m, b).x, aT + M_Size(m, b).height * 0.5), b);
            double aB = M_Center(m, a).y + M_Size(m, a).height * 0.5;
            double bB = M_Center(m, b).y + M_Size(m, b).height * 0.5;
            if (fabs(aB - bB) < 44.0) M_SetCenter(m, CGPointMake(M_Center(m, b).x, aB - M_Size(m, b).height * 0.5), b);
        }
    }
}

// Shared "sort + pin the extreme-edge windows" logic of _itemsSortedByX (axis 0) and the per-column vertical pass (axis 1).
static NSArray *BP_G2_SortAxis(id m, NSArray *items, id before, id dragging, int axis) {
    if (items.count <= 1) return items;
    double (^cen)(id) = ^double(id i) { CGPoint c = M_Center(m, i); return axis == 0 ? c.x : c.y; };
    double (^len)(id) = ^double(id i) { CGSize s = M_Size(m, i); return axis == 0 ? s.width : s.height; };
    double (^lo)(id) = ^double(id i) { return cen(i) - len(i) * 0.5; };
    double (^hi)(id) = ^double(id i) { return cen(i) + len(i) * 0.5; };
    NSArray *byC = [items sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return [@(cen(a)) compare:@(cen(b))]; }];
    NSArray *byMin = [items sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return [@(lo(a)) compare:@(lo(b))]; }];
    NSArray *byMax = [items sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { return [@(hi(b)) compare:@(hi(a))]; }];   // descending
    id first = byMin.firstObject, last = byMax.firstObject;
    BOOL allow = YES;
    if (dragging && [items containsObject:dragging] && before && [M_Items(before) containsObject:dragging]) {
        CGPoint bc = M_Center(before, dragging), nc = M_Center(m, dragging);
        double bv = axis == 0 ? bc.x : bc.y, nv = axis == 0 ? nc.x : nc.y;
        if ([dragging isEqual:first] && FGT(bv, nv)) allow = YES;
        else if (![dragging isEqual:last]) allow = YES;
        else allow = !FLT(bv, nv);
    }
    NSArray *r = byC;
    if (allow && ![r.firstObject isEqual:first]) {
        if (!FEq(lo(r.firstObject), lo(first)) || (dragging && [dragging isEqual:first])) r = ArrInsertOrMove(r, first, 0);
    }
    if (![r.lastObject isEqual:last] && (!allow || ![first isEqual:last])) {
        if (!FEq(hi(r.lastObject), hi(last)) || (dragging && [dragging isEqual:last])) r = ArrAddOrMove(r, last);
    }
    return r;
}

// 162 0x1c73cb878
- (NSArray *)_itemsSortedByXInModel:(id)m before:(id)before dragging:(id)dragging {
    return BP_G2_SortAxis(m, M_Items(m), before, dragging, 0);
}

// 162 0x1c73cc00c / 0x1c73cc184
- (void)_constrainH:(id)m stage:(CGRect)st {
    for (id item in M_Items(m)) {
        CGPoint c = M_Center(m, item); double half = M_Size(m, item).width * 0.5;
        double x = (c.x - half < st.origin.x) ? st.origin.x + half : c.x;
        if (x + half > CGRectGetMaxX(st)) x = CGRectGetMaxX(st) - half;
        M_SetCenter(m, CGPointMake(x, c.y), item);
    }
}
- (void)_constrainV:(id)m stage:(CGRect)st {
    for (id item in M_Items(m)) {
        CGPoint c = M_Center(m, item); double half = M_Size(m, item).height * 0.5;
        double y = (c.y - half < st.origin.y) ? st.origin.y + half : c.y;
        if (y + half > CGRectGetMaxY(st)) y = CGRectGetMaxY(st) - half;
        M_SetCenter(m, CGPointMake(c.x, y), item);
    }
}

// 162 0x1c73cc2fc
- (NSArray *)_columnsInModel:(id)m sorted:(NSArray *)sorted before:(id)before attrs:(id)a dragging:(id)dragging {
    double gap = A_D(a, "stageInterItemSpacing", 0), limit = A_D(a, "maximumWindowHeightWithDock", 0) + 2 * gap;
    NSMutableArray *columns = [NSMutableArray new], *col = nil;
    BPG2Region colRegion = NULL;
    for (id item in sorted) {
        CGPoint c = M_Center(m, item); CGSize s = M_Size(m, item);
        BPG2Region reg = RgnR(CGRectMake(c.x - (s.width + gap) * 0.5, c.y - (s.height + gap) * 0.5, s.width + gap, s.height + gap));
        if (col && colRegion) {
            double iMin = c.x - s.width * 0.5, iMax = c.x + s.width * 0.5;
            CGRect bb = gRgn.bbox(colRegion); double cMin = bb.origin.x, cMax = bb.origin.x + bb.size.width;
            if ((FGE(cMin, iMin) && FLE(cMax, iMax)) || (FGE(iMin, cMin) && FLE(iMax, cMax))) {
                BPG2Region u = RgnUnion(colRegion, reg);
                if (u && !gRgn.equalR(u, colRegion) && !gRgn.equalR(u, reg) && !FGT(gRgn.bbox(u).size.height, limit)) {
                    [col addObject:item]; colRegion = u; continue;
                }
            }
        }
        col = [NSMutableArray arrayWithObject:item];
        [columns addObject:col];
        colRegion = reg;
    }
    for (NSMutableArray *column in columns) {
        [column sortUsingComparator:^NSComparisonResult(id x, id y) { return [@(M_Center(m, x).y) compare:@(M_Center(m, y).y)]; }];
        if (column.count < 2) continue;
        NSArray *r = BP_G2_SortAxis(m, column, before, dragging, 1);
        [column removeAllObjects];
        [column addObjectsFromArray:r];
    }
    return columns;
}

// 162 0x1c73cced8
- (double)_totalWidthOfColumns:(NSArray *)cols inModel:(id)m attrs:(id)a {
    double gap = A_D(a, "stageInterItemSpacing", 0), t = 0;
    for (NSUInteger i = 0; i < cols.count; i++) {
        double w = 0;
        for (id item in cols[i]) w = MAX(w, M_Size(m, item).width);
        t = (i == 0) ? t + w : t + w + gap;
    }
    return t;
}

// 162 0x1c73cd17c   (_compactSpacingVertically... 0x1c73cd068 is an empty loop and is intentionally not implemented)
- (void)_compactH:(id)m cols:(NSArray *)cols attrs:(id)a {
    if (cols.count < 2) return;
    double gap = A_D(a, "stageInterItemSpacing", 0);
    double (^minLeft)(NSArray *) = ^double(NSArray *c) { double v = DBL_MAX; for (id i in c) v = MIN(v, M_Center(m, i).x - M_Size(m, i).width * 0.5); return v; };
    NSArray *sorted = [cols sortedArrayUsingComparator:^NSComparisonResult(NSArray *x, NSArray *y) { return [@(minLeft(x)) compare:@(minLeft(y))]; }];
    double prevMax = -DBL_MAX;
    for (NSUInteger i = 0; i < sorted.count; i++) {
        double minL = DBL_MAX, maxR = -DBL_MAX;
        for (id item in sorted[i]) { CGPoint c = M_Center(m, item); double hw = M_Size(m, item).width * 0.5; minL = MIN(minL, c.x - hw); maxR = MAX(maxR, c.x + hw); }
        if (i != 0) {
            double g = minL - prevMax;
            if (FGT(g, gap)) { double d = gap - g; for (id item in sorted[i]) { CGPoint c = M_Center(m, item); M_SetCenter(m, CGPointMake(c.x + d, c.y), item); } maxR += d; }
        }
        prevMax = MAX(prevMax, maxR);
    }
}

// 162 0x1c73cd714
- (void)_expandH:(id)m cols:(NSArray *)cols before:(id)before attrs:(id)a dragging:(id)dragging stage:(CGRect)st {
    if (cols.count < 2) return;
    double gap = A_D(a, "stageInterItemSpacing", 0);
    for (NSArray *col in cols) for (id item in col) if (FGE(M_Size(m, item).width, st.size.width)) return;
    NSArray *fSorted = [cols.firstObject sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
        return [@(M_Center(m, x).x - M_Size(m, x).width * 0.5) compare:@(M_Center(m, y).x - M_Size(m, y).width * 0.5)]; }];
    NSArray *lSorted = [cols.lastObject sortedArrayUsingComparator:^NSComparisonResult(id x, id y) {
        return [@(M_Center(m, y).x + M_Size(m, y).width * 0.5) compare:@(M_Center(m, x).x + M_Size(m, x).width * 0.5)]; }];
    id firstItem = fSorted.firstObject, lastItem = lSorted.firstObject;
    if (!firstItem || !lastItem) return;
    double L = M_Center(m, firstItem).x - M_Size(m, firstItem).width * 0.5;
    double R = M_Center(m, lastItem).x + M_Size(m, lastItem).width * 0.5;
    if (dragging && [dragging isEqual:lastItem] && before && [M_Items(before) containsObject:dragging] && [M_Items(m) containsObject:dragging])
        R = MAX(R, M_Center(before, dragging).x + M_Size(m, lastItem).width * 0.5);
    if (FGT(L, st.origin.x)) {
        double d = L - st.origin.x;
        for (NSArray *col in cols) for (id item in col) { CGPoint c = M_Center(m, item); M_SetCenter(m, CGPointMake(c.x - d, c.y), item); }
        L -= d; R -= d;
    }
    double width = R - L;
    if (FLT(width, st.size.width) && cols.count) {
        double slack = st.size.width - width, prevMax = DBL_MAX;
        for (NSUInteger i = 0; i < cols.count; i++) {
            double minL = DBL_MAX, maxR = -DBL_MAX;
            for (id item in cols[i]) { CGPoint c = M_Center(m, item); double hw = M_Size(m, item).width * 0.5; minL = MIN(minL, c.x - hw); maxR = MAX(maxR, c.x + hw); }
            if (i != 0) {
                double g = prevMax - minL;
                if (FGT(g, -gap)) {
                    double d = MIN(gap + g, slack);
                    for (id item in cols[i]) { CGPoint c = M_Center(m, item); M_SetCenter(m, CGPointMake(c.x + d, c.y), item); }
                    maxR += d;
                }
            }
            prevMax = maxR;
        }
    }
}

// 162 0x1c73ce0e8
- (void)_expandV:(id)m cols:(NSArray *)cols attrs:(id)a stage:(CGRect)st {
    double gap = A_D(a, "stageInterItemSpacing", 0);
    for (NSArray *col in cols) {
        id first = col.firstObject, last = col.lastObject;
        if (!first || !last) continue;
        double top = M_Center(m, first).y - M_Size(m, first).height * 0.5;
        double colH = (M_Center(m, last).y + M_Size(m, last).height * 0.5) - top;
        if (!FLT(colH, st.size.height) || col.count < 2) continue;
        double slack = st.size.height - colH, prevBottom = DBL_MAX;
        for (NSUInteger j = 0; j < col.count; j++) {
            id item = col[j]; CGPoint c = M_Center(m, item); double hh = M_Size(m, item).height * 0.5;
            double bottom = c.y + hh;
            if (j != 0) {
                double g = prevBottom - (c.y - hh);
                if (FGT(g, -gap)) { double d = MIN(gap + g, slack); M_SetCenter(m, CGPointMake(c.x, c.y + d), item); prevBottom = bottom + d; }
                else prevBottom = bottom;
            } else prevBottom = bottom;
        }
    }
}

// 162 0x1c73ce3f0
- (void)_vCenter:(id)m cols:(NSArray *)cols stage:(CGRect)st {
    double mid = CGRectGetMidY(st);
    for (NSArray *col in cols) {
        if (col.count == 0) continue;
        if (col.count >= 2) {
            id first = col.firstObject, last = col.lastObject;
            double top = M_Center(m, first).y - M_Size(m, first).height * 0.5;
            double bot = M_Center(m, last).y + M_Size(m, last).height * 0.5;
            double shift = mid - (top + bot) * 0.5;
            for (id item in col) { CGPoint c = M_Center(m, item); M_SetCenter(m, CGPointMake(c.x, c.y + shift), item); }
        } else {
            id item = col.firstObject; CGPoint c = M_Center(m, item); double hh = M_Size(m, item).height * 0.5;
            double cTop = st.origin.y + hh, cBot = CGRectGetMaxY(st) - hh;
            double dM = round(fabs(mid - c.y)), dT = round(fabs(cTop - c.y)), dB = round(fabs(cBot - c.y));
            double y = (FLE(dM, dT) && FLE(dM, dB)) ? mid : ((FLE(dT, dM) && FLE(dT, dB)) ? cTop : cBot);
            M_SetCenter(m, CGPointMake(c.x, y), item);
        }
    }
}

// 162 0x1c73ce72c
- (void)_hCenter:(id)m stage:(CGRect)st {
    CGRect bb = [self _boundingBoxForModel:m];
    double shift = (st.origin.x + st.size.width * 0.5) - (bb.origin.x + bb.size.width * 0.5);
    for (id item in M_Items(m)) { CGPoint c = M_Center(m, item); M_SetCenter(m, CGPointMake(c.x + shift, c.y), item); }
}

// 162 0x1c73cf450
- (CGRect)_boundingBoxForModel:(id)m {
    CGRect acc = CGRectNull;
    for (id item in M_Items(m)) { CGRect r = M_Rect(m, item); acc = CGRectIsEmpty(acc) ? r : CGRectUnion(acc, r); }
    return CGRectIsNull(acc) ? CGRectZero : acc;                       // 162 starts from the global at GOT 0x1d83e1c78 (CGRectNull-like) and returns it unchanged if there are no items
}

// 162 0x1c73cf628
- (BOOL)_isColumns:(NSArray *)x equalTo:(NSArray *)y {
    if (x.count != y.count) return NO;
    for (NSUInteger i = 0; i < x.count; i++) {
        NSArray *p = x[i], *q = y[i];
        if (p.count != q.count) return NO;
        for (NSUInteger j = 0; j < p.count; j++) if (![p[j] isEqual:q[j]]) return NO;
    }
    return YES;
}

// 162 0x1c73cefcc
- (NSArray *)_fullyOccludedItemsInModel:(id)m attrs:(id)a {
    double gap = A_D(a, "stageInterItemSpacing", 0), peekLen = A_D(a, "stageOcclusionDodgingPeekLength", 0);
    NSMutableArray *out = [NSMutableArray new];
    BPG2Region acc = NULL;
    for (id item in M_Items(m)) {
        CGRect rect = M_Rect(m, item);
        BPG2Region reg = RgnR(rect);
        BPG2Region grown = RgnR(CGRectMake(rect.origin.x - gap * 0.5, rect.origin.y - gap * 0.5, rect.size.width + gap, rect.size.height + gap));
        if (acc) {
            BPG2Region vis = RgnDiff(reg, acc);
            if (!vis || gRgn.isEmpty(vis) || FLT(gRgn.bbox(vis).size.width, peekLen)) [out addObject:item];
            acc = RgnUnion(acc, grown);
        } else acc = grown;
    }
    return out;
}

// 162 0x1c73cf21c
- (void)_flagCoveredInModel:(id)mc attrs:(id)a {
    SEL setCovered = sel_registerName("setCoveredByFullyOccludedPeekingItem:forItem:");
    double peekScale = A_D(a, "stageOcclusionDodgingPeekScale", 1.0);
    BPG2Region acc = NULL;
    for (id item in M_Items(mc)) {
        CGSize s = M_Size(mc, item); BOOL full = M_Full(mc, item); CGPoint c; double k;
        if (full) { c = M_PeekCenter(mc, item); k = peekScale; }
        else { c = M_Center(mc, item); k = M_Partial(mc, item) ? A_PartialScale(a, s) : 1.0; }
        BPG2Region reg = RgnR(CGRectMake(c.x - s.width * 0.5 * k, c.y - s.height * 0.5 * k, s.width * k, s.height * k));
        if (acc) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(mc, setCovered, reg ? gRgn.intersects(reg, acc) : NO, item);
            if (full) acc = RgnUnion(acc, reg);
        } else {
            acc = full ? reg : NULL;
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(mc, setCovered, NO, item);
        }
    }
}

// 162 0x1c73ca8d4
- (NSDictionary *)_overlappingScaleAnchorCentersForModel:(id)m attrs:(id)a {
    double gap = A_D(a, "stageInterItemSpacing", 0);
    NSArray *items = M_Items(m);
    NSMutableArray *groups = [NSMutableArray new];
    [groups addObject:[NSMutableArray new]];
    BPG2Region acc = NULL;
    for (NSUInteger i = 0; i < items.count; i++) {
        id item = items[i]; CGRect rect = M_Rect(m, item);
        BPG2Region reg = RgnR(rect);
        NSMutableArray *last = groups.lastObject;
        if (!acc) { [last addObject:item]; acc = reg; continue; }
        id prev = items[i - 1];
        BOOL a1 = M_Partial(m, item) ? YES : M_Full(m, item);
        BOOL a2 = M_Partial(m, prev) ? YES : M_Full(m, prev);
        BOOL join = NO;
        if (a1 && a2) {
            BPG2Region ov = RgnInter(acc, reg);
            if (!ov || gRgn.isEmpty(ov)) {
                CGFloat gw = rect.size.width + 2 * gap + 1, gh = rect.size.height + 2 * gap + 1;
                BPG2Region near = RgnInter(acc, RgnR(CGRectMake(CGRectGetMidX(rect) - gw * 0.5, CGRectGetMidY(rect) - gh * 0.5, gw, gh)));
                double w = CGFLOAT_MAX, h = CGFLOAT_MAX;                                      // UNSURE: sentinel for an empty intersection (constants from GOT 0x1d83e1c78+0x10)
                if (near && !gRgn.isEmpty(near)) { CGRect nb = gRgn.bbox(near); w = nb.size.width; h = nb.size.height; }
                join = (FLT(w, 2.0) && FGT(h, 2.0)) || (FGT(w, 2.0) && FLT(h, 2.0));
            }
        }
        if (join) { acc = RgnUnion(acc, reg); [last addObject:item]; }
        else { [groups addObject:[[NSMutableArray alloc] initWithObjects:item, nil]]; acc = reg; }
    }
    CGRect bb = [self _boundingBoxForModel:m];
    NSMutableDictionary *result = [NSMutableDictionary new];
    for (NSArray *group in groups) {
        BPG2Region u = NULL;
        for (id item in group) { BPG2Region reg = RgnR(M_Rect(m, item)); u = u ? RgnUnion(u, reg) : reg; }
        if (!u) continue;
        CGRect g = gRgn.bbox(u);
        CGPoint ctr = CGPointMake(CGRectGetMidX(g), CGRectGetMidY(g));
        double dc = fabs(ctr.x - CGRectGetMidX(bb)), dl = fabs(CGRectGetMinX(g) - CGRectGetMinX(bb)), dr = fabs(CGRectGetMaxX(g) - CGRectGetMaxX(bb));
        double ax = ctr.x;
        if (!(FLE(dc, dl) && FLE(dc, dr))) ax = FLE(dl, dr) ? CGRectGetMinX(g) : CGRectGetMaxX(g);
        double ec = fabs(ctr.y - CGRectGetMidY(bb)), et = fabs(CGRectGetMinY(g) - CGRectGetMinY(bb)), eb = fabs(CGRectGetMaxY(g) - CGRectGetMaxY(bb));
        double ay = ctr.y;
        if (!(FLE(ec, et) && FLE(ec, eb)) && !FLE(fabs(ec - MAX(et, eb)), 12.0)) ay = FLE(et, eb) ? CGRectGetMinY(g) : CGRectGetMaxY(g);
        NSValue *v = [NSValue valueWithCGPoint:CGPointMake(ax, ay)];
        for (id item in group) result[item] = v;
    }
    return result;
}

// 162 0x1c73ce890
- (void)_dodge:(id)model attrs:(id)a dragging:(id)dragging bounds:(CGRect)bounds {
    id copy = [model mutableCopy];
    [self _snap:model dragging:nil];
    NSArray *fully = [self _fullyOccludedItemsInModel:model attrs:a];
    double gap = A_D(a, "stageInterItemSpacing", 0), peekLen = A_D(a, "stageOcclusionDodgingPeekLength", 0), pad = A_D(a, "screenEdgePadding", 0), pk = A_D(a, "stageOcclusionDodgingPeekScale", 1.0);
    BOOL strip = A_B(a, "usesStripAreaForOverlapping");
    SEL setPartial = sel_registerName("setPartiallyOccluded:forItem:"), setFull = sel_registerName("setFullyOccluded:forItem:"), setPeek = sel_registerName("setUnoccludedPeekingCenterForItem:forItem:");
    BPG2Region occ = NULL;
    for (id item in M_Items(model)) {
        CGPoint c = M_Center(model, item); CGSize s = M_Size(model, item);
        if (![fully containsObject:item]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(model, setPartial, NO, item);
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(model, setFull, NO, item);
            ((void (*)(id, SEL, CGPoint, id))objc_msgSend)(model, setPeek, CGPointZero, item);
            CGRect rect = CGRectMake(c.x - s.width * 0.5, c.y - s.height * 0.5, s.width, s.height);
            BPG2Region reg = RgnR(rect);
            BPG2Region grown = RgnR(CGRectMake(rect.origin.x - gap * 0.5, rect.origin.y - gap * 0.5, s.width + gap, s.height + gap));
            if (occ) {
                if (reg && gRgn.intersects(occ, reg)) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(model, setPartial, YES, item);
                occ = RgnUnion(occ, grown);
            } else occ = grown;
            continue;
        }
        double hw = s.width * 0.5, hh = s.height * 0.5;
        BPG2Region vis = NULL;
        double xL = c.x;
        do { xL -= peekLen; vis = RgnDiff(RgnR(CGRectMake(xL - hw, c.y - hh, s.width, s.height)), occ); }
        while (occ && (!vis || gRgn.isEmpty(vis) || FLT(gRgn.bbox(vis).size.width, peekLen)));
        double leftScore = xL + (vis ? gRgn.bbox(vis).size.width : 0) - peekLen;
        double xR = c.x;
        do { xR += peekLen; vis = RgnDiff(RgnR(CGRectMake(xR - hw, c.y - hh, s.width, s.height)), occ); }
        while (occ && (!vis || gRgn.isEmpty(vis) || FLT(gRgn.bbox(vis).size.width, peekLen)));
        double rightScore = xR - (vis ? gRgn.bbox(vis).size.width : 0) + peekLen;
        double yD = c.y;
        do { yD += peekLen * 0.5; vis = RgnDiff(RgnR(CGRectMake(c.x - hw, yD - hh, s.width, s.height)), occ); }
        while (occ && (!vis || gRgn.isEmpty(vis) || FLE(gRgn.bbox(vis).size.height, pad * 0.5)));
        double visH = vis ? gRgn.bbox(vis).size.height : 0;
        double kk = 1 - pk;
        double cxL = MAX((gap + leftScore) - kk * pad, pad * 0.5 + pk * pad);
        double cxR = MIN(kk * pad + (rightScore - gap), bounds.size.width - pad * 0.5 - pk * pad);
        double cyV = kk * hh + (pad * 0.5 + (yD - visH) - gap);
        BOOL leftOff = FLT(cxL - pk * pad, 0), rightOff = FGT(pk * pad + cxR, bounds.size.width), botOff = FGT(pk * pad + cyV, bounds.size.height);
        double dL = round(fabs(cxL - c.x)), dR = round(fabs(cxR - c.x)), dV = round(fabs(cyV - c.y));
        double bbW = [self _boundingBoxForModel:model].size.width;
        CGPoint pc;
        double eighth = bounds.size.width * 0.125;
        if (!strip && !botOff && FLT(dV, dR * 0.5) && FLT(dV, dL * 0.5) && FGT(dL, eighth) && FGT(dR, eighth)) pc = CGPointMake(c.x, cyV);
        else if (!leftOff && FLT(cxL - pad, -bbW * 0.5 + bounds.size.width * 0.5) && FLE(dL, dR * 1.5)) pc = CGPointMake(cxL, c.y);
        else if (rightOff) pc = CGPointMake(cxL, c.y);
        else if (FGT(pad + cxR, bounds.size.width * 0.5 + bbW * 0.5) && FLE(dR, dL * 1.5)) pc = CGPointMake(cxR, c.y);
        else pc = FLE(dR, dL) ? CGPointMake(cxR, c.y) : CGPointMake(cxL, c.y);
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(model, setPartial, NO, item);
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(model, setFull, YES, item);
        ((void (*)(id, SEL, CGPoint, id))objc_msgSend)(model, setPeek, pc, item);
    }
    if (copy) for (id item in M_Items(copy)) M_SetCenter(model, M_Center(copy, item), item);
}
@end

// =================================================================================================================
// A5. SBSwitcherChamoisLayoutAttributes: 16.2 fields in an associated dictionary.   PARTIAL (see md A5)
// A6. SBSwitcherChamoisSettings: fill the extras from the 16.0 builder, new entry point, new constants.   PARTIAL (md A6)
// A8. SBAppLayout / SBAppLayoutOverlappingModelCacheKey.   PORTABLE / PARTIAL (md A8)
// =================================================================================================================

static const void *kBP_G2_AttrExtras = &kBP_G2_AttrExtras;
static NSMutableDictionary *BP_G2_AttrX(id attrs, BOOL create) {
    if (!attrs) return nil;
    NSMutableDictionary *d = objc_getAssociatedObject(attrs, kBP_G2_AttrExtras);
    if (!d && create) { d = [NSMutableDictionary new]; objc_setAssociatedObject(attrs, kBP_G2_AttrExtras, d, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return d;
}

// double-valued extras: name -> getter "name", setter "setName:"
static void BP_G2_AddDoubleProp(Class c, const char *getter, const char *setter, double dflt) {
    NSString *key = [NSString stringWithUTF8String:getter];
    IMP g = imp_implementationWithBlock(^double(id me) { NSNumber *n = BP_G2_AttrX(me, NO)[key]; return n ? n.doubleValue : dflt; });
    IMP s = imp_implementationWithBlock(^(id me, double v) { BP_G2_AttrX(me, YES)[key] = @(v); });
    if (!class_getInstanceMethod(c, sel_registerName(getter))) { if (!class_addMethod(c, sel_registerName(getter), g, "d16@0:8")) imp_removeBlock(g); } else imp_removeBlock(g);
    if (!class_getInstanceMethod(c, sel_registerName(setter))) { if (!class_addMethod(c, sel_registerName(setter), s, "v24@0:8d16")) imp_removeBlock(s); } else imp_removeBlock(s);
}
static void BP_G2_AddObjProp(Class c, const char *getter, const char *setter) {
    NSString *key = [NSString stringWithUTF8String:getter];
    IMP g = imp_implementationWithBlock(^id(id me) { return BP_G2_AttrX(me, NO)[key]; });
    IMP s = imp_implementationWithBlock(^(id me, id v) { if (v) BP_G2_AttrX(me, YES)[key] = [v copy]; else [BP_G2_AttrX(me, YES) removeObjectForKey:key]; });
    if (!class_getInstanceMethod(c, sel_registerName(getter))) { if (!class_addMethod(c, sel_registerName(getter), g, "@16@0:8")) imp_removeBlock(g); } else imp_removeBlock(g);
    if (!class_getInstanceMethod(c, sel_registerName(setter))) { if (!class_addMethod(c, sel_registerName(setter), s, "v24@0:8@16")) imp_removeBlock(s); } else imp_removeBlock(s);
}
static CGRect BP_G2_AttrContainerBounds(id me) { NSValue *v = BP_G2_AttrX(me, NO)[@"containerBounds"]; return v ? [v CGRectValue] : CGRectZero; }

static void BP_G2_SetupAttributes(void) {
    Class c = objc_getClass("SBSwitcherChamoisLayoutAttributes");
    if (!c) return;
    BP_G2_AddDoubleProp(c, "stageStatusBarClearingAppScale", "setStageStatusBarClearingAppScale:", 1.0);
    BP_G2_AddDoubleProp(c, "switcherHorizontalEdgeSpacing", "setSwitcherHorizontalEdgeSpacing:", 0);
    BP_G2_AddDoubleProp(c, "switcherHorizontalInterItemSpacing", "setSwitcherHorizontalInterItemSpacing:", 0);
    BP_G2_AddDoubleProp(c, "switcherVerticalEdgeSpacing", "setSwitcherVerticalEdgeSpacing:", 0);
    BP_G2_AddDoubleProp(c, "switcherVerticalInterItemSpacing", "setSwitcherVerticalInterItemSpacing:", 0);
    BP_G2_AddDoubleProp(c, "switcherHeightForIconAndLabelsUnderEachPile", "setSwitcherHeightForIconAndLabelsUnderEachPile:", 60.0);
    BP_G2_AddDoubleProp(c, "switcherPileCardMinimumPeekAmount", "setSwitcherPileCardMinimumPeekAmount:", 25.0);
    BP_G2_AddDoubleProp(c, "switcherPileCompactingFactor", "setSwitcherPileCompactingFactor:", 0.6);
    BP_G2_AddObjProp(c, "gridWidths", "setGridWidths:");
    BP_G2_AddObjProp(c, "gridHeights", "setGridHeights:");
    // BOOL usesStripAreaForOverlapping
    if (!class_getInstanceMethod(c, sel_registerName("usesStripAreaForOverlapping"))) {
        class_addMethod(c, sel_registerName("usesStripAreaForOverlapping"), imp_implementationWithBlock(^BOOL(id me) { return [BP_G2_AttrX(me, NO)[@"usesStripArea"] boolValue]; }), "B16@0:8");
        class_addMethod(c, sel_registerName("setUsesStripAreaForOverlapping:"), imp_implementationWithBlock(^(id me, BOOL v) { BP_G2_AttrX(me, YES)[@"usesStripArea"] = @(v); }), "v20@0:8B16");
    }
    // CGRect containerBounds / setContainerBounds:
    if (!class_getInstanceMethod(c, sel_registerName("containerBounds"))) {
        class_addMethod(c, sel_registerName("containerBounds"), imp_implementationWithBlock(^CGRect(id me) { return BP_G2_AttrContainerBounds(me); }), BPG2_RECT "16@0:8");
        class_addMethod(c, sel_registerName("setContainerBounds:"), imp_implementationWithBlock(^(id me, CGRect r) { BP_G2_AttrX(me, YES)[@"containerBounds"] = [NSValue valueWithCGRect:r]; }), "v48@0:8" BPG2_RECT "16");
    }
    // 162 0x1c78c336c
    if (!class_getInstanceMethod(c, sel_registerName("partiallyOccludedStageScaleForItemWithSize:"))) {
        class_addMethod(c, sel_registerName("partiallyOccludedStageScaleForItemWithSize:"), imp_implementationWithBlock(^double(id me, CGSize size) {
            CGSize cs = BP_G2_AttrContainerBounds(me).size;
            SEL s1 = sel_registerName("stageStatusBarClearingAppScale"), s2 = sel_registerName("stageOccludedAppScale");
            return CGSizeEqualToSize(size, cs) ? BP_G2_Dbl(me, s1) : BP_G2_Dbl(me, s2);
        }), "d32@0:8{CGSize=dd}16");
    }
}

%group G2Attr
%hook SBSwitcherChamoisLayoutAttributes
// 162 0x1c78c39e0: the copy carries the extras
- (id)copyWithZone:(NSZone *)zone {
    id c = %orig;
    NSMutableDictionary *d = BP_G2_AttrX(self, NO);
    if (c && d.count) objc_setAssociatedObject(c, kBP_G2_AttrExtras, [d mutableCopy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return c;
}
// 162 0x1c78c3384: isEqual also compares the new fields
- (BOOL)isEqual:(id)other {
    BOOL r = %orig;
    if (!r || other == self) return r;
    NSDictionary *a = BP_G2_AttrX(self, NO), *b = BP_G2_AttrX(other, NO);
    if (!a && !b) return r;
    return [a ?: @{} isEqualToDictionary:b ?: @{}];
}
%end
%end // G2Attr

// ---- A6: settings -------------------------------------------------------------------------------------------------------
%group G2Settings
%hook SBSwitcherChamoisSettings

// 160 0x1c6413524 builder: run it, then attach the 16.2 fields (formulas decoded from 162 0x1c78c0f50, see md A6)
- (id)layoutAttributesForContainerBounds:(CGRect)bounds nativeContainerReferencePixelBounds:(CGRect)nativeBounds interfaceOrientation:(long long)orientation
                      floatingDockHeight:(double)dockH statusBarHeight:(double)statusBarH requiresFullScreen:(BOOL)rfs
                      prefersStripHidden:(BOOL)ps prefersDockHidden:(BOOL)pd isEmbeddedDisplay:(BOOL)embedded {
    id attrs = %orig;
    if (!attrs) return attrs;
    double W = bounds.size.width, H = bounds.size.height;
    if (H <= 0) return attrs;
    NSMutableDictionary *x = BP_G2_AttrX(attrs, YES);
    x[@"containerBounds"] = [NSValue valueWithCGRect:bounds];
    x[@"usesStripArea"] = @(embedded);
    x[@"stageStatusBarClearingAppScale"] = @(1.0 - (2.0 * statusBarH) / H);
    double hEdge = round(H * 0.0625), vEdge = round(H * 0.10546875), vInter = round(H * 0.0859375);
    if (W > 1920.0) { hEdge = round(hEdge * 1.5); vEdge = round(vEdge * 1.5); }
    x[@"switcherHorizontalEdgeSpacing"] = @(hEdge);
    x[@"switcherHorizontalInterItemSpacing"] = @(round(H * 0.0625));       // 162 sets the inter-item spacing from the UNscaled hEdge
    x[@"switcherVerticalEdgeSpacing"] = @(vEdge);
    x[@"switcherVerticalInterItemSpacing"] = @(vInter);
    x[@"switcherHeightForIconAndLabelsUnderEachPile"] = @(60.0);
    x[@"switcherPileCardMinimumPeekAmount"] = @(25.0);
    x[@"switcherPileCompactingFactor"] = @(0.6);
    return attrs;
}

// 162 0x1c78c0d28 (new 4-argument entry point). PARTIAL: reproduces the bounds/orientation logic and calls the 16.0 9-arg builder.
%new
- (id)layoutAttributesForWindowScene:(id)scene interfaceOrientation:(long long)orientation requiresFullScreen:(BOOL)rfs floatingDockHeight:(double)dockH {
    if (!scene) return nil;
    SEL sPs = sel_registerName("_shouldPreferStripHiddenForWindowScene:interfaceOrientation:"), sPd = sel_registerName("_shouldPreferDockHiddenForWindowScene:");
    SEL sSb = sel_registerName("_statusBarHeight"), sBuild = sel_registerName("layoutAttributesForContainerBounds:nativeContainerReferencePixelBounds:interfaceOrientation:floatingDockHeight:statusBarHeight:requiresFullScreen:prefersStripHidden:prefersDockHidden:isEmbeddedDisplay:");
    if (![self respondsToSelector:sBuild]) return nil;
    BOOL ps = [self respondsToSelector:sPs] ? ((BOOL (*)(id, SEL, id, long long))objc_msgSend)(self, sPs, scene, orientation) : NO;
    BOOL pd = [self respondsToSelector:sPd] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(self, sPd, scene) : NO;
    id screen = BP_G2_Obj(scene, @selector(screen));
    id dc = BP_G2_Obj(screen, sel_registerName("displayConfiguration"));
    CGRect b = BP_G2_Rect(dc, @selector(bounds));
    CGRect nb = BP_G2_Rect(screen, sel_registerName("nativeBounds"));
    BOOL isMain = BP_G2_Bool(scene, sel_registerName("isMainDisplayWindowScene"));
    BOOL isExternal = BP_G2_Bool(scene, sel_registerName("isExternalDisplayWindowScene"));
    CGFloat w = b.size.width, h = b.size.height;
    if (isMain) { if (orientation - 1 < 2u) { CGFloat t = w; w = h; h = t; } }         // UIInterfaceOrientationPortrait(1)/UpsideDown(2): see md (swap only for those)
    else { CGFloat mx = MAX(w, h), mn = MIN(w, h); w = mx; h = mn; }                  // external display: landscape
    b.size = CGSizeMake(w, h);
    double sb = [self respondsToSelector:sSb] ? ((double (*)(id, SEL))objc_msgSend)(self, sSb) : 0;
    return ((id (*)(id, SEL, CGRect, CGRect, long long, double, double, BOOL, BOOL, BOOL, BOOL))objc_msgSend)(self, sBuild, b, nb, orientation, dockH, sb, rfs, ps, pd, !isExternal);
}

// new constants (PTSettings ivars cannot be added)
%new
- (double)switcherHeightForIconAndLabelsUnderEachPile { return 60.0; }
%new
- (double)switcherPileCardMinimumPeekAmount { return 25.0; }
%new
- (double)switcherPileCompactingFactor { return 0.6; }
%new
- (BOOL)rasterizeScaledApps { return NO; }
%end
%end // G2Settings

// ---- A8: SBAppLayout ------------------------------------------------------------------------------------------------------
%group G2AppLayout
%hook SBAppLayout

// 162 0x1c77265c4: identity = unique bundle identifiers of ALL items joined with "&" (160: split-view roles only, layout order). PORTABLE.
// Sorted for determinism (162 uses NSSet order).
- (id)continuousExposeIdentifier {
    NSMutableSet *set = [NSMutableSet set];
    SEL sAll = sel_registerName("allItems");
    NSArray *items = [self respondsToSelector:sAll] ? ((NSArray *(*)(id, SEL))objc_msgSend)(self, sAll) : nil;
    if (![items isKindOfClass:[NSArray class]] && ![items isKindOfClass:[NSSet class]] && ![items isKindOfClass:[NSOrderedSet class]]) return %orig;
    for (id item in items) {
        NSString *bid = BP_G2_Obj(item, sel_registerName("bundleIdentifier"));
        if ([bid isKindOfClass:[NSString class]] && bid.length) [set addObject:bid];
    }
    if (!set.count) return %orig;
    return [[[set allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"&"];
}

// 162 0x1c7725460. PORTABLE.
%new
- (id)zOrderedLeafAppLayouts {
    NSArray *z = BP_G2_Obj(self, sel_registerName("zOrderedItems"));
    SEL sLeaf = sel_registerName("leafAppLayoutForItem:");
    if (!z || ![self respondsToSelector:sLeaf]) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:z.count];
    for (id item in z) { id l = ((id (*)(id, SEL, id))objc_msgSend)(self, sLeaf, item); if (l) [out addObject:l]; }
    return out;
}
%end
%end // G2AppLayout

// ---- A8: cache key (floating dock height) ------------------------------------------------------------------------------------
static const void *kBP_G2_KeyDock = &kBP_G2_KeyDock;
static id BP_G2_NewCacheKey(Class kc, id layout, CGRect bounds, long long o, double dockH, BOOL hs, BOOL hd, id dragging) {
    SEL old = sel_registerName("cacheKeyForSnapshotOfAppLayout:containerBounds:containerOrientation:hideStrips:hideDock:draggingItem:");
    if (!kc || !class_getClassMethod(kc, old)) return nil;
    id key = ((id (*)(Class, SEL, id, CGRect, long long, BOOL, BOOL, id))objc_msgSend)(kc, old, layout, bounds, o, hs, hd, dragging);
    if (key) objc_setAssociatedObject(key, kBP_G2_KeyDock, @(dockH), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return key;
}
%group G2CacheKey
%hook SBAppLayoutOverlappingModelCacheKey
- (BOOL)isEqual:(id)other {
    BOOL r = %orig;
    if (!r || other == self) return r;
    NSNumber *a = objc_getAssociatedObject(self, kBP_G2_KeyDock), *b = objc_getAssociatedObject(other, kBP_G2_KeyDock);
    return (a == b) || [a isEqual:b];
}
- (NSUInteger)hash { return %orig; }          // equal keys keep equal hashes (dock height only refines isEqual:)
%end
%end // G2CacheKey

static void BP_G2_SetupCacheKeyFactory(void) {
    Class kc = objc_getClass("SBAppLayoutOverlappingModelCacheKey");
    if (!kc) return;
    Class meta = object_getClass(kc);
    SEL s = sel_registerName("cacheKeyForSnapshotOfAppLayout:containerBounds:containerOrientation:floatingDockHeight:hideStrips:hideDock:draggingItem:");
    if (class_getClassMethod(kc, s)) return;
    IMP imp = imp_implementationWithBlock(^id(Class me, id layout, CGRect bounds, long long o, double dockH, BOOL hs, BOOL hd, id dragging) {
        return BP_G2_NewCacheKey(kc, layout, bounds, o, dockH, hs, hd, dragging);
    });
    class_addMethod(meta, s, imp, "@96@0:8@16" BPG2_RECT "24q56d64B72B76@80");   // UNSURE exact frame offsets; only used for dispatch by our own code
}

// ---- hand-off to the calculator hook (A7.2) ----------------------------------------------------------------------------------
static BP162ChamoisOverlappingController *gBPG2Controller;
// Used by the (still to be written) hook of SBDisplayItemLayoutAttributesCalculator -_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...
// Returns the resolved 16.2 model for a preferred model, or nil when anything is missing (the caller then falls back to %orig).
static id BP_G2_ResolveModel(id model, id chamoisAttrs, id dragging, id before, double dockH, CGRect bounds, double scale, BOOL ps, BOOL pd) {
    if (!gBPG2Controller) gBPG2Controller = [BP162ChamoisOverlappingController new];
    return [gBPG2Controller modelByPerformingAutoLayoutForModel:model chamoisLayoutAttributes:chamoisAttrs draggingItem:dragging modelBeforeDragging:before
                                               floatingDockHeight:dockH bounds:bounds screenScale:scale prefersStripHidden:ps prefersDockHidden:pd];
}

static void BP_G2_SetupLayoutData(void) {
    BP_G2_SetupAttributes();
    BP_G2_SetupCacheKeyFactory();
    %init(G2Attr);
    %init(G2Settings);
    %init(G2AppLayout);
    %init(G2CacheKey);
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
    BP_G2_SetupLayoutData();                         // A5, A6, A8
}

// ===== END OF PART A1 (more sections are appended below as the analysis proceeds) =====
