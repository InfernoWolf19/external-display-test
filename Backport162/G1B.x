// group1b-modifiers.hooks.m
//
// DRAFT. Logos source (rename to .xm or paste into Tweak.x; the %hook / %group blocks need Logos, the rest is plain
// Objective-C). Backports the portable parts of the iPadOS 16.2 (20C65) Continuous Expose (Stage Manager) switcher
// modifiers, event / response classes, gesture modifiers and transitions to 16.0 (20A8372) SpringBoard.
// Behaviour is specified in group1b-modifiers.md (section numbers in the comments refer to it).
//
// Every piece is tagged  // PORTABLE,  // PARTIAL: <why>  or  // NOT PORTABLE: <why>.
//
// Integration (do not paste blindly, Tweak.x is not edited by this draft):
//   1. Add a feature F_G1B (switch file <jbroot>/tmp/Backport162.off.group1b) or call G1B_Setup() unconditionally.
//   2. Call G1B_Setup() from the %ctor after the existing %init. It builds the run-time classes (once) and does %init(G1B).
//   3. Compile with ARC (-fobjc-arc), like Tweak.x.
//   For a standalone syntax check define BP_G1B_STANDALONE (supplies stand-ins for BP_On / BP_Log).
//
// Safety rules followed here:
//   * No ivar of a system class is touched by a hard-coded offset. Offsets of ivars added to run-time classes with
//     class_addIvar are looked up with class_getInstanceVariable + ivar_getOffset. Object-valued state of run-time
//     classes lives in associated objects (OBJC_ASSOCIATION_RETAIN_NONATOMIC), so it is released automatically.
//   * Every selector sent to a private object is checked with respondsToSelector: / instancesRespondToSelector: first
//     (or is a selector the 16.0 binary itself sends to that class, verified in the disassembly).
//   * Run-time classes are only registered after every superclass / donor class / required selector was found; if
//     anything is missing the class is not created and the hooks that would need it stay inactive.
//   * Every hook is a no-op when its feature switch is off, and calls %orig first unless noted.
//   * [super sel] in a run-time class is always objc_msgSendSuper with the class's real superclass (G1B_SUPER).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>
#import <unistd.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

// ------------------------------------------------------------------------------------------------ host integration

#define G1B_ON() BP_On(F_G1B)

#include "G1BKit.h"

// INTEGRATION: interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
@interface SBSwitcherModifier : NSObject @end
@interface SBFluidSwitcherViewController : UIViewController @end
@interface SBMainSwitcherControllerCoordinator : NSObject @end
@interface SBiPadOSPlatformSwitcherModifier : NSObject @end
@interface SBContinuousExposeRootSwitcherModifier : NSObject @end
@interface SBContinuousExposeAppToAppModifier : NSObject @end
// END INTEGRATION interfaces

// ============================================================================================================
// 0.1  event types 36 / 37 / 38 reach 16.0 modifiers  (PORTABLE)
// ============================================================================================================
// 16.0 -[SBSwitcherModifier _handleEvent:] ignores types > 35. Route them to handle<X>Event: when the modifier implements it.
enum { G1BEventStripEdgeProtectTongue = 36, G1BEventTapAppLayoutHeader = 37, G1BEventPointerCrossedDisplayBoundary = 38 };

static SEL G1B_HandlerForEventType(long long t) {
    switch (t) {
        case G1BEventStripEdgeProtectTongue:        return sel_registerName("handleContinuousExposeStripEdgeProtectTongueEvent:");
        case G1BEventTapAppLayoutHeader:            return sel_registerName("handleTapAppLayoutHeaderEvent:");
        case G1BEventPointerCrossedDisplayBoundary: return sel_registerName("handlePointerCrossedDisplayBoundaryEvent:");
        default: return NULL;
    }
}

%group G1B_Base
%hook SBSwitcherModifier
- (id)_handleEvent:(id)event {
    id orig = %orig;
    if (!G1B_ON() || !event || ![event respondsToSelector:@selector(type)]) return orig;
    SEL h = G1B_HandlerForEventType(G1B_SendLL0(event, @selector(type)));
    if (!h || ![self respondsToSelector:h]) return orig;
    // 16.2 _handleEvent: (0x1c7895274) first calls [super _handleEvent:] and discards the result, then returns the handler's result.
    return G1B_Send1(self, h, event);
}
%end
%end

// ============================================================================================================
// 1.1  SBFilteringSwitcherModifier + _SBFilteringPassthroughTargetSwitcherModifier  (PORTABLE: new class)
// ============================================================================================================
Class gFilteringCls;     // shared with G1C.x
static Class gPassthroughCls, gFilteringSuper;
static char kFiltRouting, kFiltPassthrough, kFiltDisplayItems, kFiltAppLayouts, kFiltModifier;

static id G1B_Filtering_Init(id self, SEL _cmd, NSArray *appLayouts, id modifier) {
    if (!appLayouts || !modifier || !gPassthroughCls) return nil;          // 16.2 asserts; we refuse instead of continuing with nil
    id me = G1B_SUPER(id, gFilteringSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    Class routingCls = NSClassFromString(@"SBRoutingSwitcherModifier");
    SEL routingInit = @selector(initWithModifiers:delegate:);
    if (!routingCls || ![routingCls instancesRespondToSelector:routingInit]
        || ![me respondsToSelector:@selector(addChildModifier:atLevel:key:)]) return nil;
    G1B_SET(me, kFiltAppLayouts, [appLayouts copy]);
    G1B_SET(me, kFiltModifier, modifier);
    id passthrough = [[gPassthroughCls alloc] init];
    G1B_SET(me, kFiltPassthrough, passthrough);
    id routing = ((id (*)(id, SEL, id, id))objc_msgSend)([routingCls alloc], routingInit, @[ modifier, passthrough ], me);
    if (!routing) return nil;
    G1B_SET(me, kFiltRouting, routing);
    ((void (*)(id, SEL, id, long long, id))objc_msgSend)(me, @selector(addChildModifier:atLevel:key:), routing, 0, nil);
    // displayItemsToFilter = set of flatten(compactMap(appLayouts, ^(l){ return [l allItems]; }))
    NSMutableSet *items = [NSMutableSet set];
    for (id l in appLayouts) {
        if ([l respondsToSelector:@selector(allItems)]) {
            id all = G1B_Send0(l, @selector(allItems));
            if ([all isKindOfClass:[NSArray class]] || [all isKindOfClass:[NSSet class]]) for (id i in all) [items addObject:i];
        }
    }
    G1B_SET(me, kFiltDisplayItems, items);
    return me;
}

static void G1B_Filtering_DidMove(id self, SEL _cmd, id parent) {
    G1B_SUPER(void, gFilteringSuper, self, _cmd, (struct objc_super *, SEL, id), parent);
    if (!parent) return;
    id pass = G1B_GET(self, kFiltPassthrough);
    if (pass && [pass respondsToSelector:@selector(delegate)] && G1B_Send0(pass, @selector(delegate))) {
        G1B_SendV1(pass, @selector(setDelegate:), nil);
        ((void (*)(id, SEL, id, long long, id))objc_msgSend)(self, @selector(addChildModifier:atLevel:key:), pass, 1, nil);
        if ([self respondsToSelector:@selector(newAppLayoutsGenCount)]) (void)G1B_SendLL0(self, @selector(newAppLayoutsGenCount));
    }
}

static void G1B_Filtering_SetState(id self, SEL _cmd, long long state) {
    long long old = G1B_SendLL0(self, @selector(state));
    if (state == 1 && old != 1 && [self respondsToSelector:@selector(newAppLayoutsGenCount)]) (void)G1B_SendLL0(self, @selector(newAppLayoutsGenCount));
    G1B_SUPER(void, gFilteringSuper, self, _cmd, (struct objc_super *, SEL, long long), state);
}

static BOOL G1B_AppLayoutsContain(NSArray *arr, id l) { return l && arr && [arr containsObject:l]; }

static id G1B_Filtering_Event(id self, SEL _cmd, id routing, id event, id forModifier) {
    if (!event || ![event respondsToSelector:@selector(type)]) return event;
    long long type = G1B_SendLL0(event, @selector(type));
    id mod = G1B_GET(self, kFiltModifier), pass = G1B_GET(self, kFiltPassthrough);
    NSArray *filter = G1B_GET(self, kFiltAppLayouts);
    if (type == 18 /* TapAppLayout */) {
        id l = [event respondsToSelector:@selector(appLayout)] ? G1B_Send0(event, @selector(appLayout)) : nil;
        if (forModifier == mod  && G1B_AppLayoutsContain(filter, l)) return event;
        if (forModifier == pass && !G1B_AppLayoutsContain(filter, l)) return event;
        return nil;
    }
    if (type == 1 /* Transition */) {
        SEL setFrom = @selector(setFromAppLayout:), setTo = @selector(setToAppLayout:);
        SEL setFromEnv = @selector(setFromEnvironmentMode:), setToEnv = @selector(setToEnvironmentMode:);
        id e = [event copy];
        if (!e || ![e respondsToSelector:setFrom] || ![e respondsToSelector:setTo] || ![e respondsToSelector:setFromEnv] || ![e respondsToSelector:setToEnv]) return event;
        SEL filt = @selector(routingModifier:filteredAppLayouts:forModifier:);
        id from = G1B_Send0(e, @selector(fromAppLayout)), to = G1B_Send0(e, @selector(toAppLayout));
        id rm = G1B_GET(self, kFiltRouting);
        if (from) G1B_SendV1(e, setFrom, [((NSArray *(*)(id, SEL, id, NSArray *, id))objc_msgSend)(self, filt, rm, @[ from ], forModifier) firstObject]);
        if (to)   G1B_SendV1(e, setTo,   [((NSArray *(*)(id, SEL, id, NSArray *, id))objc_msgSend)(self, filt, rm, @[ to ],   forModifier) firstObject]);
        long long fe = G1B_SendLL0(e, @selector(fromEnvironmentMode)), te = G1B_SendLL0(e, @selector(toEnvironmentMode));
        id nf = G1B_Send0(e, @selector(fromAppLayout)), nt = G1B_Send0(e, @selector(toAppLayout));
        if (fe == 3 && !nf) G1B_SendVLL(e, setFromEnv, 1); else if (fe == 1 && nf) G1B_SendVLL(e, setFromEnv, 3);
        if (te == 3 && !nt) G1B_SendVLL(e, setToEnv, 1);   else if (te == 1 && nt) G1B_SendVLL(e, setToEnv, 3);
        return e;
    }
    return event;
}

static NSArray *G1B_Filtering_FilteredLayouts(id self, SEL _cmd, id routing, NSArray *layouts, id forModifier) {
    id mod = G1B_GET(self, kFiltModifier);
    NSSet *items = G1B_GET(self, kFiltDisplayItems);
    BOOL keep = (forModifier == mod);                       // content modifier: only the filtered items; everyone else: the rest
    NSMutableArray *out = [NSMutableArray array];
    for (id l in layouts) {
        if (![l respondsToSelector:@selector(appLayoutWithItemsPassingTest:)]) continue;
        id f = ((id (*)(id, SEL, BOOL (^)(id)))objc_msgSend)(l, @selector(appLayoutWithItemsPassingTest:), ^BOOL(id item) { return [items containsObject:item] == keep; });
        if (f) [out addObject:f];
    }
    return out;
}

static id G1B_Filtering_ModifierForAppLayout(id self, SEL _cmd, id routing, id l) {
    NSSet *items = G1B_GET(self, kFiltDisplayItems);
    BOOL any = l && items && [l respondsToSelector:@selector(containsAnyItemFromSet:)] && G1B_SendB1(l, @selector(containsAnyItemFromSet:), items);
    return any ? G1B_GET(self, kFiltModifier) : G1B_GET(self, kFiltPassthrough);
}
static id G1B_Filtering_FilteredIdentifiers(id self, SEL _cmd, id routing, id ids, id forModifier) { return ids; }
static CGRect G1B_Filtering_ContainerBounds(id self, SEL _cmd, id routing, id forModifier) {
    return G1B_SUPER(CGRect, gFilteringSuper, self, @selector(containerViewBounds), (struct objc_super *, SEL));
}
static CGRect G1B_Filtering_SwitcherBounds(id self, SEL _cmd, id routing, id forModifier) {
    return G1B_SUPER(CGRect, gFilteringSuper, self, @selector(switcherViewBounds), (struct objc_super *, SEL));
}
static id G1B_Filtering_Passthrough(id self, SEL _cmd, id routing) { return G1B_GET(self, kFiltPassthrough); }
static id G1B_Filtering_AnimAttrsModifier(id self, SEL _cmd, id routing, id element) {
    BOOL isLayout = [element respondsToSelector:@selector(switcherLayoutElementType)] && G1B_SendLL0(element, @selector(switcherLayoutElementType)) == 0;
    return (isLayout && G1B_AppLayoutsContain(G1B_GET(self, kFiltAppLayouts), element)) ? G1B_GET(self, kFiltModifier) : G1B_GET(self, kFiltPassthrough);
}
static id G1B_Filtering_AppLayoutsToFilter(id self, SEL _cmd) { return G1B_GET(self, kFiltAppLayouts); }
static id G1B_Filtering_Modifier(id self, SEL _cmd) { return G1B_GET(self, kFiltModifier); }

static void G1B_BuildFiltering(void) {
    Class sup = NSClassFromString(@"SBSwitcherModifier");
    if (!sup || !NSClassFromString(@"SBRoutingSwitcherModifier")) return;
    gFilteringSuper = sup;
    gPassthroughCls = G1B_MakeClass("_SBFilteringPassthroughTargetSwitcherModifier", sup, NULL, 0, NULL, 0, NULL, NULL);
    const G1BMethod m[] = {
        { "initWithAppLayouts:modifier:",                               (IMP)G1B_Filtering_Init,            "@32@0:8@16@24" },
        { "didMoveToParentModifier:",                                   (IMP)G1B_Filtering_DidMove,         "v24@0:8@16" },
        { "setState:",                                                  (IMP)G1B_Filtering_SetState,        "v24@0:8q16" },
        { "routingModifier:event:forModifier:",                         (IMP)G1B_Filtering_Event,           "@40@0:8@16@24@32" },
        { "routingModifier:filteredAppLayouts:forModifier:",            (IMP)G1B_Filtering_FilteredLayouts, "@40@0:8@16@24@32" },
        { "routingModifier:modifierForAppLayout:",                      (IMP)G1B_Filtering_ModifierForAppLayout, "@32@0:8@16@24" },
        { "routingModifier:filteredContinuousExposeIdentifiers:forModifier:", (IMP)G1B_Filtering_FilteredIdentifiers, "@40@0:8@16@24@32" },
        { "routingModifier:containerViewBoundsForModifier:",            (IMP)G1B_Filtering_ContainerBounds, "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8@16@24" },
        { "routingModifier:switcherViewBoundsForModifier:",             (IMP)G1B_Filtering_SwitcherBounds,  "{CGRect={CGPoint=dd}{CGSize=dd}}32@0:8@16@24" },
        { "scrollModifierForRoutingModifier:",                          (IMP)G1B_Filtering_Passthrough,     "@24@0:8@16" },
        { "homeScreenModifierForRoutingModifier:",                      (IMP)G1B_Filtering_Passthrough,     "@24@0:8@16" },
        { "transactionCompletionOptionsModifierForRoutingModifier:",    (IMP)G1B_Filtering_Passthrough,     "@24@0:8@16" },
        { "routingModifier:animationAttributesModifierForLayoutElement:", (IMP)G1B_Filtering_AnimAttrsModifier, "@32@0:8@16@24" },
        { "fallbackModifierForRoutingModifier:",                        (IMP)G1B_Filtering_Passthrough,     "@24@0:8@16" },
        { "appLayoutsToFilter",                                         (IMP)G1B_Filtering_AppLayoutsToFilter, "@16@0:8" },
        { "modifier",                                                   (IMP)G1B_Filtering_Modifier,        "@16@0:8" },
    };
    gFilteringCls = G1B_MakeClass("SBFilteringSwitcherModifier", sup, NULL, 0, m, sizeof m / sizeof m[0], "SBRoutingSwitcherModifierDelegate", NULL);
}
// ---- end 1.1

// ============================================================================================================
// 1.2  SBOverrideContinuousExposeIdentifiersSwitcherModifier  (PARTIAL: 16.0 has one identifier list, see spec 1.2)
// ============================================================================================================
// 16.0 flavour: overrides the 16.0 context selector -continuousExposeIdentifiers (== 16.2 "InSwitcher"). The "InStrip" override is
// stored (so the getters work) but cannot be served: -continuousExposeIdentifiersInStrip is not a 16.0 context selector.
Class gOverrideIdsCls, gOverrideIdsSuper;     // shared with G1C.x
static char kOvrSwitcher, kOvrStrip;

static id G1B_OverrideIds_Init(id self, SEL _cmd, id sw, id strip) {
    id me = G1B_SUPER(id, gOverrideIdsSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kOvrSwitcher, [sw copy]);      // NSOrderedSet in 16.0 (NSArray in 16.2); copy works for both
    G1B_SET(me, kOvrStrip, [strip copy]);
    return me;
}
static void G1B_OverrideIds_DidMove(id self, SEL _cmd, id parent) {
    G1B_SUPER(void, gOverrideIdsSuper, self, _cmd, (struct objc_super *, SEL, id), parent);
    // 16.2: [self newContinuousExposeIdentifiersGenerationCount]. 16.0 has no such selector: invalidate through the closest equivalent.
    if (parent && [self respondsToSelector:@selector(newAppLayoutsGenCount)]) (void)G1B_SendLL0(self, @selector(newAppLayoutsGenCount));
}
static void G1B_OverrideIds_SetState(id self, SEL _cmd, long long state) {
    if (state == 1 && G1B_SendLL0(self, @selector(state)) != 1) {
        id parent = G1B_Send0(self, @selector(parentModifier)), del = G1B_Send0(self, @selector(delegate));
        if ((parent || del) && [self respondsToSelector:@selector(newAppLayoutsGenCount)]) (void)G1B_SendLL0(self, @selector(newAppLayoutsGenCount));
    }
    G1B_SUPER(void, gOverrideIdsSuper, self, _cmd, (struct objc_super *, SEL, long long), state);
}
static id G1B_OverrideIds_Ids(id self, SEL _cmd) {
    id o = G1B_GET(self, kOvrSwitcher);
    if (o) return o;
    return G1B_HasSuper(gOverrideIdsSuper, _cmd) ? G1B_SUPER(id, gOverrideIdsSuper, self, _cmd, (struct objc_super *, SEL)) : nil;
}
static id G1B_OverrideIds_GetSwitcher(id self, SEL _cmd) { return G1B_GET(self, kOvrSwitcher); }
static id G1B_OverrideIds_GetStrip(id self, SEL _cmd)    { return G1B_GET(self, kOvrStrip); }

static void G1B_BuildOverrideIds(void) {
    Class sup = NSClassFromString(@"SBSwitcherModifier");
    if (!sup || !G1B_HasSuper(sup, @selector(continuousExposeIdentifiers))) return;     // not a 16.0-style base
    gOverrideIdsSuper = sup;
    const G1BMethod m[] = {
        { "initWithContinuousExposeIdentifiersInSwitcher:continuousExposeIdentifiersInStrip:", (IMP)G1B_OverrideIds_Init, "@32@0:8@16@24" },
        { "didMoveToParentModifier:",                          (IMP)G1B_OverrideIds_DidMove,   "v24@0:8@16" },
        { "setState:",                                         (IMP)G1B_OverrideIds_SetState,  "v24@0:8q16" },
        { "continuousExposeIdentifiers",                       (IMP)G1B_OverrideIds_Ids,       "@16@0:8" },     // 16.0 context selector
        { "overrideContinuousExposeIdentifiersInSwitcher",     (IMP)G1B_OverrideIds_GetSwitcher, "@16@0:8" },
        { "overrideContinuousExposeIdentifiersInStrip",        (IMP)G1B_OverrideIds_GetStrip,  "@16@0:8" },
    };
    gOverrideIdsCls = G1B_MakeClass("SBOverrideContinuousExposeIdentifiersSwitcherModifier", sup, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
}
// ---- end 1.2

// ============================================================================================================
// 1.4  SBPulseDisplayItemSwitcherModifier  (PORTABLE: new class; stage layout is injected, see spec 1.4)
// ============================================================================================================
typedef struct { BOOL a; BOOL b; } G1BAsyncRendering;           // SBSwitcherAsyncRenderingAttributes {_Bool, _Bool}
static Class gPulseCls, gPulseSuper;
static char kPulseItem, kPulseToPulse, kPulseStage;
static NSString *const kG1BPulseReason = @"SBPulseDisplayItemSwitcherModifierTimerReason";

static id G1B_Pulse_Init(id self, SEL _cmd, id item) {
    id me = G1B_SUPER(id, gPulseSuper, self, @selector(init), (struct objc_super *, SEL));
    if (!me || !item) return nil;
    G1B_SET(me, kPulseItem, item);
    G1B_SET(me, kPulseToPulse, item);
    return me;
}
// Extra (not in 16.2): the creator tells the modifier which app layout is on the stage (16.2 asks the context).
static void G1B_Pulse_SetStage(id self, SEL _cmd, id stage) { G1B_SET(self, kPulseStage, stage); }

static id G1B_AnimSettings(id self) {
    if (![self respondsToSelector:@selector(switcherSettings)]) return nil;
    id ss = G1B_Send0(self, @selector(switcherSettings));
    return (ss && [ss respondsToSelector:@selector(animationSettings)]) ? G1B_Send0(ss, @selector(animationSettings)) : nil;
}

static id G1B_Pulse_HandleHeader(id self, SEL _cmd, id event) {
    id response = G1B_HasSuper(gPulseSuper, _cmd) ? G1B_SUPER(id, gPulseSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    id upd = G1B_NewUpdateLayoutResponse(4, 3);
    if (upd) response = G1B_Append(upd, response);
    Class tc = NSClassFromString(@"SBTimerEventSwitcherEventResponse");
    SEL ti = @selector(initWithDelay:validator:reason:);
    if (tc && [tc instancesRespondToSelector:ti]) {
        double delay = G1B_Dbl0(G1B_AnimSettings(self), NSSelectorFromString(@"pulseSecondStageDelay"));
        id timer = ((id (*)(id, SEL, double, id, id))objc_msgSend)([tc alloc], ti, delay, nil, kG1BPulseReason);
        if (timer) response = G1B_Append(timer, response);
    }
    return response;
}
static id G1B_Pulse_HandleTimer(id self, SEL _cmd, id event) {
    id response = G1B_SUPER(id, gPulseSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    id reason = [event respondsToSelector:@selector(reason)] ? G1B_Send0(event, @selector(reason)) : nil;
    if ([reason isKindOfClass:[NSString class]] && [reason isEqualToString:kG1BPulseReason]) {
        G1B_SET(self, kPulseToPulse, nil);
        id upd = G1B_NewUpdateLayoutResponse(4, 3);
        if (upd) response = G1B_Append(upd, response);
        G1B_SendVLL(self, @selector(setState:), 1);
    }
    return response;
}
static double G1B_Pulse_Scale(id self, SEL _cmd, long long role, id layout) {
    double s = G1B_SUPER(double, gPulseSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
    id toPulse = G1B_GET(self, kPulseToPulse);
    if (toPulse && layout && [layout respondsToSelector:@selector(itemForLayoutRole:)]) {
        id item = ((id (*)(id, SEL, long long))objc_msgSend)(layout, @selector(itemForLayoutRole:), role);
        if (item && [item isEqual:toPulse]) { double ps = G1B_Dbl0(G1B_AnimSettings(self), NSSelectorFromString(@"pulseScale")); if (ps > 0) s *= ps; }
    }
    return s;
}
static id G1B_Pulse_AnimAttrs(id self, SEL _cmd, id element) {
    id base = G1B_SUPER(id, gPulseSuper, self, _cmd, (struct objc_super *, SEL, id), element);
    id attrs = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    id toPulse = G1B_GET(self, kPulseToPulse);
    if (attrs && toPulse && [element respondsToSelector:@selector(switcherLayoutElementType)] && G1B_SendLL0(element, @selector(switcherLayoutElementType)) == 0
        && [element respondsToSelector:@selector(containsItem:)] && G1B_SendB1(element, @selector(containsItem:), toPulse)
        && [attrs respondsToSelector:@selector(setLayoutSettings:)]) {
        id settings = G1B_AnimSettings(self);
        id pss = (settings && [settings respondsToSelector:NSSelectorFromString(@"pulseScaleSettings")]) ? G1B_Send0(settings, NSSelectorFromString(@"pulseScaleSettings")) : nil;
        if (pss) G1B_SendV1(attrs, @selector(setLayoutSettings:), pss);
    }
    return attrs;
}
static G1BAsyncRendering G1B_Pulse_Async(id self, SEL _cmd, id layout) {
    id toPulse = G1B_GET(self, kPulseToPulse);
    if (toPulse && [layout respondsToSelector:@selector(containsItem:)] && G1B_SendB1(layout, @selector(containsItem:), toPulse)) return (G1BAsyncRendering){ NO, NO };
    return G1B_SUPER(G1BAsyncRendering, gPulseSuper, self, _cmd, (struct objc_super *, SEL, id), layout);
}
static id G1B_Pulse_TopMost(id self, SEL _cmd) {
    id base = G1B_SUPER(id, gPulseSuper, self, _cmd, (struct objc_super *, SEL));
    id stage = G1B_GET(self, kPulseStage), item = G1B_GET(self, kPulseItem);
    if (!stage || !item || ![self respondsToSelector:@selector(appLayouts)]) return base;
    id pulseLayout = nil;
    for (id l in (NSArray *)G1B_Send0(self, @selector(appLayouts))) {
        if ([l respondsToSelector:@selector(containsItem:)] && G1B_SendB1(l, @selector(containsItem:), item)) { pulseLayout = l; break; }
    }
    if (!pulseLayout || ![stage respondsToSelector:@selector(isOrContainsAppLayout:)] || !G1B_SendB1(stage, @selector(isOrContainsAppLayout:), pulseLayout)) return base;
    SEL ins = NSSelectorFromString(@"sb_arrayByInsertingOrMovingObject:toIndex:");
    if (![base respondsToSelector:ins]) return base;
    return ((id (*)(id, SEL, id, unsigned long long))objc_msgSend)(base, ins, pulseLayout, 0);
}
static id G1B_Pulse_GetItem(id self, SEL _cmd) { return G1B_GET(self, kPulseItem); }
static id G1B_Pulse_GetToPulse(id self, SEL _cmd) { return G1B_GET(self, kPulseToPulse); }

static void G1B_BuildPulse(void) {
    Class sup = NSClassFromString(@"SBSwitcherModifier");
    if (!sup) return;
    gPulseSuper = sup;
    const G1BMethod m[] = {
        { "initWithDisplayItem:",                          (IMP)G1B_Pulse_Init,        "@24@0:8@16" },
        { "setStageAppLayout:",                            (IMP)G1B_Pulse_SetStage,    "v24@0:8@16" },
        { "handleTapAppLayoutHeaderEvent:",                (IMP)G1B_Pulse_HandleHeader,"@24@0:8@16" },
        { "handleTimerEvent:",                             (IMP)G1B_Pulse_HandleTimer, "@24@0:8@16" },
        { "scaleForLayoutRole:inAppLayout:",               (IMP)G1B_Pulse_Scale,       "d32@0:8q16@24" },
        { "animationAttributesForLayoutElement:",          (IMP)G1B_Pulse_AnimAttrs,   "@24@0:8@16" },
        { "asyncRenderingAttributesForAppLayout:",         (IMP)G1B_Pulse_Async,       "{?=BB}24@0:8@16" },
        { "topMostLayoutElements",                         (IMP)G1B_Pulse_TopMost,     "@16@0:8" },
        { "displayItem",                                   (IMP)G1B_Pulse_GetItem,     "@16@0:8" },
        { "displayItemToPulse",                            (IMP)G1B_Pulse_GetToPulse,  "@16@0:8" },
    };
    gPulseCls = G1B_MakeClass("SBPulseDisplayItemSwitcherModifier", sup, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
}
// ---- end 1.4

// ============================================================================================================
// 1.5 / 1.6 / 1.8  event classes, 1.7 / 1.10 response classes  (PORTABLE as classes; consumers: see spec)
// ============================================================================================================
static Class gHeaderEventCls, gPointerEventCls, gTongueEventCls;
Class gGrabberRespCls, gOrientRespCls, gInvalidateRespCls;     // shared with G1C.x
static char kEvAppLayout, kEvRole, kRespItem;

enum { G1BRespSetInterfaceOrientationFromUserResizing = 38, G1BRespPresentStripEdgeProtectGrabber = 39,
       G1BRespInvalidateContinuousExposeIdentifiers = 40 /* 16.2 uses 34, which is RequestSystemApertureElementSuppression in 16.0 */ };

// --- header tap event (type 37)
static id G1B_HeaderEv_Init(id self, SEL _cmd, id appLayout, long long role) {
    Class sup = class_getSuperclass(gHeaderEventCls);
    id me = G1B_SUPER(id, sup, self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kEvAppLayout, appLayout);
    G1B_SET(me, kEvRole, @(role));
    return me;
}
static long long G1B_HeaderEv_Type(id self, SEL _cmd) { return G1BEventTapAppLayoutHeader; }
static id G1B_HeaderEv_AppLayout(id self, SEL _cmd) { return G1B_GET(self, kEvAppLayout); }
static long long G1B_HeaderEv_Role(id self, SEL _cmd) { return [(NSNumber *)G1B_GET(self, kEvRole) longLongValue]; }
// copy-family IMP: must return +1 (ARC does not know that for a plain C function)
static __attribute__((ns_returns_retained)) id G1B_HeaderEv_Copy(id self, SEL _cmd, NSZone *z) {
    id n = [gHeaderEventCls alloc];
    return ((id (*)(id, SEL, id, long long))objc_msgSend)(n, @selector(initWithAppLayout:layoutRole:), G1B_GET(self, kEvAppLayout), G1B_HeaderEv_Role(self, 0));
}

// --- pointer crossed display boundary event (type 38): scalar state in real ivars
static ptrdiff_t gPtrEdgeOff = -1, gPtrDirOff = -1;
static id G1B_PtrEv_Init(id self, SEL _cmd, unsigned long long dir, unsigned int edge) {
    id me = G1B_SUPER(id, class_getSuperclass(gPointerEventCls), self, @selector(init), (struct objc_super *, SEL));
    if (!me || gPtrEdgeOff < 0 || gPtrDirOff < 0) return me;
    *(unsigned long long *)((uint8_t *)(__bridge void *)me + gPtrDirOff) = dir;
    *(unsigned int *)((uint8_t *)(__bridge void *)me + gPtrEdgeOff) = edge;
    return me;
}
static long long G1B_PtrEv_Type(id self, SEL _cmd) { return G1BEventPointerCrossedDisplayBoundary; }
static unsigned long long G1B_PtrEv_Dir(id self, SEL _cmd) { return gPtrDirOff < 0 ? 0 : *(unsigned long long *)((uint8_t *)(__bridge void *)self + gPtrDirOff); }
static unsigned int G1B_PtrEv_Edge(id self, SEL _cmd) { return gPtrEdgeOff < 0 ? 0 : *(unsigned int *)((uint8_t *)(__bridge void *)self + gPtrEdgeOff); }
static void G1B_PtrEv_SetDir(id self, SEL _cmd, unsigned long long v) { if (gPtrDirOff >= 0) *(unsigned long long *)((uint8_t *)(__bridge void *)self + gPtrDirOff) = v; }
static void G1B_PtrEv_SetEdge(id self, SEL _cmd, unsigned int v) { if (gPtrEdgeOff >= 0) *(unsigned int *)((uint8_t *)(__bridge void *)self + gPtrEdgeOff) = v; }

// --- strip edge protect tongue event (type 36)
static ptrdiff_t gTongueFlagOff = -1;
static id G1B_TongueEv_Init(id self, SEL _cmd, BOOL presented) {
    id me = G1B_SUPER(id, class_getSuperclass(gTongueEventCls), self, @selector(init), (struct objc_super *, SEL));
    if (me && gTongueFlagOff >= 0) *(BOOL *)((uint8_t *)(__bridge void *)me + gTongueFlagOff) = presented;
    return me;
}
static long long G1B_TongueEv_Type(id self, SEL _cmd) { return G1BEventStripEdgeProtectTongue; }
static BOOL G1B_TongueEv_Presented(id self, SEL _cmd) { return gTongueFlagOff >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)self + gTongueFlagOff); }
static __attribute__((ns_returns_retained)) id G1B_TongueEv_Copy(id self, SEL _cmd, NSZone *z) {
    return ((id (*)(id, SEL, BOOL))objc_msgSend)([gTongueEventCls alloc], @selector(initWithTonguePresented:), G1B_TongueEv_Presented(self, 0));
}

// --- responses
static ptrdiff_t gGrabInitialOff = -1, gOrientDesiredOff = -1;
static long long G1B_GrabResp_Type(id self, SEL _cmd) { return G1BRespPresentStripEdgeProtectGrabber; }
static id G1B_GrabResp_Init(id self, SEL _cmd, BOOL initial) {
    id me = G1B_SUPER(id, class_getSuperclass(gGrabberRespCls), self, @selector(init), (struct objc_super *, SEL));
    if (me && gGrabInitialOff >= 0) *(BOOL *)((uint8_t *)(__bridge void *)me + gGrabInitialOff) = initial;
    return me;
}
static BOOL G1B_GrabResp_IsInitial(id self, SEL _cmd) { return gGrabInitialOff >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)self + gGrabInitialOff); }
static void G1B_GrabResp_SetInitial(id self, SEL _cmd, BOOL v) { if (gGrabInitialOff >= 0) *(BOOL *)((uint8_t *)(__bridge void *)self + gGrabInitialOff) = v; }

static long long G1B_OrientResp_Type(id self, SEL _cmd) { return G1BRespSetInterfaceOrientationFromUserResizing; }
static id G1B_OrientResp_Init(id self, SEL _cmd, id item, long long o) {
    id me = G1B_SUPER(id, class_getSuperclass(gOrientRespCls), self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kRespItem, item);
    if (gOrientDesiredOff >= 0) *(long long *)((uint8_t *)(__bridge void *)me + gOrientDesiredOff) = o;
    return me;
}
static id G1B_OrientResp_Item(id self, SEL _cmd) { return G1B_GET(self, kRespItem); }
static long long G1B_OrientResp_Desired(id self, SEL _cmd) { return gOrientDesiredOff < 0 ? 0 : *(long long *)((uint8_t *)(__bridge void *)self + gOrientDesiredOff); }

static void G1B_BuildEventsAndResponses(void) {
    Class evBase = NSClassFromString(@"SBSwitcherModifierEvent"), respBase = NSClassFromString(@"SBSwitcherModifierEventResponse");
    if (evBase) {
        const G1BMethod hm[] = {
            { "initWithAppLayout:layoutRole:", (IMP)G1B_HeaderEv_Init, "@32@0:8@16q24" }, { "type", (IMP)G1B_HeaderEv_Type, "q16@0:8" },
            { "appLayout", (IMP)G1B_HeaderEv_AppLayout, "@16@0:8" }, { "layoutRole", (IMP)G1B_HeaderEv_Role, "q16@0:8" },
            { "copyWithZone:", (IMP)G1B_HeaderEv_Copy, "@24@0:8^{_NSZone=}16" },
        };
        gHeaderEventCls = G1B_MakeClass("SBTapAppLayoutHeaderSwitcherModifierEvent", evBase, NULL, 0, hm, sizeof hm / sizeof hm[0], NULL, NULL);

        const G1BIvar pi[] = { { "_g1b_edge", sizeof(unsigned int), 2, "I" }, { "_g1b_direction", sizeof(unsigned long long), 3, "Q" } };
        const G1BMethod pm[] = {
            { "initWithDirection:edge:", (IMP)G1B_PtrEv_Init, "@28@0:8Q16I24" }, { "type", (IMP)G1B_PtrEv_Type, "q16@0:8" },
            { "direction", (IMP)G1B_PtrEv_Dir, "Q16@0:8" }, { "setDirection:", (IMP)G1B_PtrEv_SetDir, "v24@0:8Q16" },
            { "edge", (IMP)G1B_PtrEv_Edge, "I16@0:8" }, { "setEdge:", (IMP)G1B_PtrEv_SetEdge, "v20@0:8I16" },
        };
        BOOL made = NO;
        gPointerEventCls = G1B_MakeClass("SBPointerCrossedDisplayBoundarySwitcherModifierEvent", evBase, pi, 2, pm, sizeof pm / sizeof pm[0], NULL, &made);
        if (made) { gPtrEdgeOff = G1B_IvarOffset(gPointerEventCls, "_g1b_edge"); gPtrDirOff = G1B_IvarOffset(gPointerEventCls, "_g1b_direction"); }

        const G1BIvar ti[] = { { "_g1b_tonguePresented", sizeof(BOOL), 0, "B" } };
        const G1BMethod tm[] = {
            { "initWithTonguePresented:", (IMP)G1B_TongueEv_Init, "@20@0:8B16" }, { "type", (IMP)G1B_TongueEv_Type, "q16@0:8" },
            { "isTonguePresented", (IMP)G1B_TongueEv_Presented, "B16@0:8" }, { "copyWithZone:", (IMP)G1B_TongueEv_Copy, "@24@0:8^{_NSZone=}16" },
        };
        made = NO;
        gTongueEventCls = G1B_MakeClass("SBContinuousExposeStripEdgeProtectTongueSwitcherModifierEvent", evBase, ti, 1, tm, sizeof tm / sizeof tm[0], NULL, &made);
        if (made) gTongueFlagOff = G1B_IvarOffset(gTongueEventCls, "_g1b_tonguePresented");
    }
    if (respBase) {
        const G1BIvar gi[] = { { "_g1b_initialPresentation", sizeof(BOOL), 0, "B" } };
        const G1BMethod gm[] = {
            { "initForInitialPresentation:", (IMP)G1B_GrabResp_Init, "@20@0:8B16" }, { "type", (IMP)G1B_GrabResp_Type, "q16@0:8" },
            { "isInitialPresentation", (IMP)G1B_GrabResp_IsInitial, "B16@0:8" }, { "setInitialPresentation:", (IMP)G1B_GrabResp_SetInitial, "v20@0:8B16" },
        };
        BOOL made = NO;
        gGrabberRespCls = G1B_MakeClass("SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse", respBase, gi, 1, gm, sizeof gm / sizeof gm[0], NULL, &made);
        if (made) gGrabInitialOff = G1B_IvarOffset(gGrabberRespCls, "_g1b_initialPresentation");

        const G1BIvar oi[] = { { "_g1b_desiredOrientation", sizeof(long long), 3, "q" } };
        const G1BMethod om[] = {
            { "initWithDisplayItem:desiredContentOrientation:", (IMP)G1B_OrientResp_Init, "@32@0:8@16q24" }, { "type", (IMP)G1B_OrientResp_Type, "q16@0:8" },
            { "displayItem", (IMP)G1B_OrientResp_Item, "@16@0:8" }, { "desiredOrientation", (IMP)G1B_OrientResp_Desired, "q16@0:8" },
        };
        made = NO;
        gOrientRespCls = G1B_MakeClass("SBSetInterfaceOrientationFromUserResizingEventResponse", respBase, oi, 1, om, sizeof om / sizeof om[0], NULL, &made);
        if (made) gOrientDesiredOff = G1B_IvarOffset(gOrientRespCls, "_g1b_desiredOrientation");
    }
}

// --- consumers: -[SBFluidSwitcherViewController _performEventResponse:]  (PARTIAL: see spec 1.7 / 1.10)
// 16.0's switch ignores unknown types and then walks the child responses, so doing our work first and calling %orig is safe.
%group G1B_VC
%hook SBFluidSwitcherViewController
- (void)_performEventResponse:(id)response {
    if (G1B_ON() && response && [response respondsToSelector:@selector(type)]) {
        long long t = G1B_SendLL0(response, @selector(type));
        if (t == G1BRespPresentStripEdgeProtectGrabber && [response respondsToSelector:@selector(isInitialPresentation)]) {
            id sc = nil;
            Ivar iv = class_getInstanceVariable([self class], "_switcherController");
            if (iv) sc = object_getIvar(self, iv);       // weak ivar: object_getIvar returns the loaded value
            BOOL initial = ((BOOL (*)(id, SEL))objc_msgSend)(response, @selector(isInitialPresentation));
            SEL s = initial ? NSSelectorFromString(@"presentContinuousExposeStripRevealGrabberTongueImmediately")
                            : NSSelectorFromString(@"tickleContinuousExposeStripRevealGrabberTongueIfVisible");
            if (sc && [sc respondsToSelector:s]) G1B_SendV0(sc, s);          // void selectors (16.0 has neither: no-op until the strip-reveal grabber is ported)
        } else if (t == G1BRespSetInterfaceOrientationFromUserResizing && [response respondsToSelector:@selector(displayItem)]) {
            id item = G1B_Send0(response, @selector(displayItem));
            long long o = G1B_SendLL0(response, @selector(desiredOrientation));
            id d = [self respondsToSelector:@selector(delegate)] ? G1B_Send0(self, @selector(delegate)) : nil;
            SEL s = NSSelectorFromString(@"switcherContentController:setInterfaceOrientationFromUserResizing:forDisplayItem:");
            if (item && o && d && [d respondsToSelector:s]) ((void (*)(id, SEL, id, long long, id))objc_msgSend)(d, s, self, o, item);
        }
    }
    %orig;
}
%end
%end
// ---- end 1.5-1.8, 1.10 (header-tap emission: see 1.5 hook below)

// 1.5 emission. 16.0 always sends SBTapAppLayoutSwitcherModifierEvent (type 18) for a header tap. Send the new event only when the
// stage modifier in this process knows how to handle it (the FullScreen port defines -handleTapAppLayoutHeaderEvent:).
%group G1B_Header
%hook SBFluidSwitcherViewController
- (void)overlayAccessoryView:(id)view didSelectHeaderForRole:(long long)role {
    Class fs = NSClassFromString(@"SBFullScreenContinuousExposeSwitcherModifier");
    BOOL handled = G1B_ON() && gHeaderEventCls && fs && [fs instancesRespondToSelector:@selector(handleTapAppLayoutHeaderEvent:)]
                   && [self respondsToSelector:@selector(isChamoisWindowingUIEnabled)] && G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled))
                   && [self respondsToSelector:@selector(_dispatchEventAndHandleAction:)];
    if (!handled) {
        %orig;
        return;
    }
    Ivar iv = class_getInstanceVariable([self class], "_visibleOverlayAccessoryViews");
    NSDictionary *map = iv ? object_getIvar(self, iv) : nil;
    id layout = [map isKindOfClass:[NSDictionary class]] ? [[map allKeysForObject:view] firstObject] : nil;
    if (!layout) {
        %orig;
        return;
    }
    id ev = ((id (*)(id, SEL, id, long long))objc_msgSend)([gHeaderEventCls alloc], @selector(initWithAppLayout:layoutRole:), layout, role);
    if (!ev) {
        %orig;
        return;
    }
    G1B_SendV1(self, @selector(_dispatchEventAndHandleAction:), ev);
}
%end
%end
// ---- end 1.5

// ============================================================================================================
// 1.9  SBContinuousExposeStripTongueView  (PARTIAL: the view is portable, the hosting in the VC is not; spec 1.9)
// ============================================================================================================
typedef struct { unsigned long long state; unsigned long long direction; } G1BTongueAttrs;
static Class gTongueViewCls, gTongueViewSuper;
static ptrdiff_t gTvAttrsOff = -1, gTvAnimOff = -1, gTvMaskSizeOff = -1;
static char kTvContainer, kTvChevron, kTvMask, kTvBackdrop, kTvTap, kTvDelegate;

static id G1B_CAFilterConst(const char *symbol, NSString *fallback) {
    void *p = dlsym(RTLD_DEFAULT, symbol);
    id v = p ? (__bridge id)*(void **)p : nil;
    return v ?: fallback;
}
#define TV_PTR(self_, off_, T) ((T *)((uint8_t *)(__bridge void *)(self_) + (off_)))

static void G1B_Tv_UpdateContainerPosition(id self, SEL _cmd) {
    UIView *c = G1B_GET(self, kTvContainer); if (!c || gTvAttrsOff < 0) return;
    CGRect b = ((UIView *)self).bounds;
    c.center = CGPointMake(TV_PTR(self, gTvAttrsOff, G1BTongueAttrs)->direction == 1 ? 0 : b.size.width, b.size.height * 0.5);
}
static void G1B_Tv_UpdateContainerTransform(id self, SEL _cmd) {
    UIView *c = G1B_GET(self, kTvContainer); if (!c || gTvAttrsOff < 0) return;
    c.transform = TV_PTR(self, gTvAttrsOff, G1BTongueAttrs)->direction == 2 ? CGAffineTransformIdentity : CGAffineTransformMakeScale(-1, 1);
}
static void G1B_Tv_UpdateSubviewLayout(id self, SEL _cmd) {
    UIView *backdrop = G1B_GET(self, kTvBackdrop), *mask = G1B_GET(self, kTvMask), *chev = G1B_GET(self, kTvChevron);
    if (!backdrop || !mask || !chev || gTvAttrsOff < 0 || gTvMaskSizeOff < 0) return;
    BOOL collapsed = TV_PTR(self, gTvAttrsOff, G1BTongueAttrs)->state == 1;
    CGAffineTransform t = collapsed ? CGAffineTransformMakeScale(0, 1) : CGAffineTransformIdentity;
    backdrop.transform = t; mask.transform = t; chev.transform = t;
    CGSize ms = *TV_PTR(self, gTvMaskSizeOff, CGSize);
    CGPoint c = CGPointMake(collapsed ? ms.width : ms.width * 0.5, floor(ms.height * 0.5));
    backdrop.center = c; mask.center = c; chev.center = c;
}
static void G1B_Tv_UpdateSubviewOpacity(id self, SEL _cmd) {
    UIView *chev = G1B_GET(self, kTvChevron);
    if (chev && gTvAttrsOff >= 0) chev.alpha = TV_PTR(self, gTvAttrsOff, G1BTongueAttrs)->state == 2 ? 1.0 : 0.0;
}
static void G1B_Tv_LayoutSubviews(id self, SEL _cmd) {
    G1B_SUPER(void, gTongueViewSuper, self, _cmd, (struct objc_super *, SEL));
    G1B_Tv_UpdateContainerPosition(self, 0); G1B_Tv_UpdateContainerTransform(self, 0); G1B_Tv_UpdateSubviewLayout(self, 0);
}
static id G1B_Tv_Delegate(id self, SEL _cmd) { id (^get)(void) = G1B_GET(self, kTvDelegate); return get ? get() : nil; }
static void G1B_Tv_SetDelegate(id self, SEL _cmd, id d) {
    __weak id w = d; id (^get)(void) = ^id{ return w; };
    // weak holder: a copied block that returns the weak reference
    objc_setAssociatedObject(self, &kTvDelegate, [get copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
}
static void G1B_Tv_HandleTap(id self, SEL _cmd, id tap) {
    id d = G1B_Tv_Delegate(self, 0);
    SEL s = NSSelectorFromString(@"continuousExposeStripTongueViewTapped:");
    if (d && [d respondsToSelector:s]) G1B_SendV1(d, s, self);
}
static BOOL G1B_Tv_PointInside(id self, SEL _cmd, CGPoint p, id event) {
    UIView *c = G1B_GET(self, kTvContainer);
    if (!c) return NO;
    return [c pointInside:[(UIView *)self convertPoint:p toView:c] withEvent:event];
}
static G1BTongueAttrs G1B_Tv_Attributes(id self, SEL _cmd) { return gTvAttrsOff < 0 ? (G1BTongueAttrs){0, 0} : *TV_PTR(self, gTvAttrsOff, G1BTongueAttrs); }
static BOOL G1B_Tv_IsAnimating(id self, SEL _cmd) { return gTvAnimOff >= 0 && *TV_PTR(self, gTvAnimOff, BOOL); }

static void G1B_Tv_SetAttributes(id self, SEL _cmd, G1BTongueAttrs attrs, BOOL animated) {
    if (gTvAttrsOff < 0 || gTvAnimOff < 0) return;
    unsigned long long old = TV_PTR(self, gTvAttrsOff, G1BTongueAttrs)->state;
    *TV_PTR(self, gTvAttrsOff, G1BTongueAttrs) = attrs;
    if (old == attrs.state) return;
    id fs = nil;
    Class dom = NSClassFromString(@"SBAppSwitcherDomain");
    id root = (dom && [dom respondsToSelector:@selector(rootSettings)]) ? G1B_Send0((id)dom, @selector(rootSettings)) : nil;
    if (root && [root respondsToSelector:NSSelectorFromString(@"floatingSwitcherSettings")]) fs = G1B_Send0(root, NSSelectorFromString(@"floatingSwitcherSettings"));
    id settings = nil; long long mode = 2;
    if (animated) {
        SEL s = (attrs.state == 1) ? NSSelectorFromString(@"tongueExpandedToCollapsedAnimationSettings") : NSSelectorFromString(@"tongueCollapsedToExpandedAnimationSettings");
        settings = (fs && [fs respondsToSelector:s]) ? G1B_Send0(fs, s) : nil;
        mode = 3;
    }
    *TV_PTR(self, gTvAnimOff, BOOL) = YES;
    __weak id weakSelf = self;
    void (^anim)(void) = ^{ id v = weakSelf; if (v) { G1B_Tv_UpdateSubviewLayout(v, 0); G1B_Tv_UpdateSubviewOpacity(v, 0); } };
    void (^done)(BOOL) = ^(BOOL finished) {
        if (!finished) return;
        id v = weakSelf; if (!v || gTvAnimOff < 0) return;
        *TV_PTR(v, gTvAnimOff, BOOL) = NO;
        id d = G1B_Tv_Delegate(v, 0);
        SEL ds = NSSelectorFromString(@"continuousExposeStripTongueView:didFinishAnimatingToState:");
        if (d && [d respondsToSelector:ds]) ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(d, ds, v, TV_PTR(v, gTvAttrsOff, G1BTongueAttrs)->state);
    };
    SEL animSel = NSSelectorFromString(@"sb_animateWithSettings:mode:animations:completion:");
    if ([UIView respondsToSelector:animSel])
        ((void (*)(id, SEL, id, long long, id, id))objc_msgSend)((id)[UIView class], animSel, settings, mode, anim, done);
    else { anim(); done(YES); }
}

static id G1B_Tv_InitWithFrame(id self, SEL _cmd, CGRect frame) {
    id me = G1B_SUPER(id, gTongueViewSuper, self, _cmd, (struct objc_super *, SEL, CGRect), frame);
    if (!me || gTvAttrsOff < 0 || gTvMaskSizeOff < 0) return me;
    UIView *v = me;
    *TV_PTR(me, gTvAttrsOff, G1BTongueAttrs) = (G1BTongueAttrs){0, 0};
    UIImage *mask = [UIImage imageNamed:@"SlideOverTongueMask"];
    if (!mask) return me;                                                      // asset missing: leave an inert view
    CGSize ms = mask.size; *TV_PTR(me, gTvMaskSizeOff, CGSize) = ms;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, ms.width, ms.height)];
    container.layer.anchorPoint = CGPointMake(1.0, 0.5);
    [v addSubview:container]; G1B_SET(me, kTvContainer, container);
    Class bd = NSClassFromString(@"_UIBackdropView");
    if (bd && [bd instancesRespondToSelector:NSSelectorFromString(@"initWithPrivateStyle:")]) {
        UIView *backdrop = ((id (*)(id, SEL, long long))objc_msgSend)([bd alloc], NSSelectorFromString(@"initWithPrivateStyle:"), (long long)-2);
        id inputs = [backdrop respondsToSelector:NSSelectorFromString(@"inputSettings")] ? G1B_Send0(backdrop, NSSelectorFromString(@"inputSettings")) : nil;
        if (inputs) {
            ((void (*)(id, SEL, double))objc_msgSend)(inputs, NSSelectorFromString(@"setBlurRadius:"), 0.0);
            ((void (*)(id, SEL, double))objc_msgSend)(inputs, NSSelectorFromString(@"setScale:"), 1.0);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(inputs, NSSelectorFromString(@"setBackdropVisible:"), YES);
        }
        if ([backdrop respondsToSelector:NSSelectorFromString(@"setGroupName:")]) G1B_SendV1(backdrop, NSSelectorFromString(@"setGroupName:"), @"SBContinuousExposeStripTongueBackdropName");
        [container addSubview:backdrop]; G1B_SET(me, kTvBackdrop, backdrop);
    }
    UIImageView *maskView = [[UIImageView alloc] initWithImage:mask];
    maskView.contentMode = UIViewContentModeScaleToFill;
    maskView.layer.compositingFilter = G1B_CAFilterConst("kCAFilterDestOut", @"destOut");
    [container addSubview:maskView]; G1B_SET(me, kTvMask, maskView);
    UIImage *chevron = [UIImage systemImageNamed:@"chevron.compact.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44.0]];
    UIImageView *chevView = [[UIImageView alloc] initWithImage:chevron];
    chevView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    chevView.tintColor = [UIColor blackColor];
    Class cf = NSClassFromString(@"CAFilter");
    if (cf && [cf respondsToSelector:NSSelectorFromString(@"filterWithType:")]) {
        id f = ((id (*)(id, SEL, id))objc_msgSend)((id)cf, NSSelectorFromString(@"filterWithType:"), G1B_CAFilterConst("kCAFilterVibrantColorMatrix", @"vibrantColorMatrix"));
        static const float M[20] = { 1.3762500286f, -0.7345163822f, -0.1417334974f, 0.0f, 0.4999999106f,
                                     -0.3735119998f, 1.0163019896f, -0.1427904963f, 0.0f, 0.5f,
                                     -0.3745689988f, -0.7329310179f, 1.6074999571f, 0.0f, 0.4999999106f,
                                     0.0f, 0.0f, 0.0f, 1.0f, 0.0f };
        NSValue *mv = [NSValue valueWithBytes:M objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
        if (f) { [f setValue:mv forKey:@"inputColorMatrix"]; chevView.layer.filters = @[ f ]; }
    }
    [container addSubview:chevView]; G1B_SET(me, kTvChevron, chevView);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:me action:sel_registerName("_handleTap:")];
    [container addGestureRecognizer:tap]; G1B_SET(me, kTvTap, tap);
    v.isAccessibilityElement = YES;
    v.accessibilityIdentifier = @"continuous-expose-strip-tongue";
    return me;
}

static void G1B_BuildTongueView(void) {
    Class sup = NSClassFromString(@"UIView");
    if (!sup) return;
    gTongueViewSuper = sup;
    const G1BIvar iv[] = { { "_g1b_attributes", sizeof(G1BTongueAttrs), 3, "{?=QQ}" }, { "_g1b_animating", sizeof(BOOL), 0, "B" }, { "_g1b_bitmapMaskSize", sizeof(CGSize), 3, "{CGSize=dd}" } };
    const G1BMethod m[] = {
        { "initWithFrame:",                  (IMP)G1B_Tv_InitWithFrame,   "@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16" },
        { "layoutSubviews",                  (IMP)G1B_Tv_LayoutSubviews,  "v16@0:8" },
        { "pointInside:withEvent:",          (IMP)G1B_Tv_PointInside,     "B40@0:8{CGPoint=dd}16@32" },
        { "setAttributes:animated:",         (IMP)G1B_Tv_SetAttributes,   "v36@0:8{?=QQ}16B32" },
        { "attributes",                      (IMP)G1B_Tv_Attributes,      "{?=QQ}16@0:8" },
        { "isAnimating",                     (IMP)G1B_Tv_IsAnimating,     "B16@0:8" },
        { "delegate",                        (IMP)G1B_Tv_Delegate,        "@16@0:8" },
        { "setDelegate:",                    (IMP)G1B_Tv_SetDelegate,     "v24@0:8@16" },
        { "_handleTap:",                     (IMP)G1B_Tv_HandleTap,       "v24@0:8@16" },
        { "_updateContainerPosition",        (IMP)G1B_Tv_UpdateContainerPosition, "v16@0:8" },
        { "_updateContainerTransform",       (IMP)G1B_Tv_UpdateContainerTransform, "v16@0:8" },
        { "_updateSubviewLayoutForCollapsedOrExpandedState", (IMP)G1B_Tv_UpdateSubviewLayout, "v16@0:8" },
        { "_updateSubviewOpacityForCollapsedOrExpandedState", (IMP)G1B_Tv_UpdateSubviewOpacity, "v16@0:8" },
    };
    BOOL made = NO;
    gTongueViewCls = G1B_MakeClass("SBContinuousExposeStripTongueView", sup, iv, 3, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) {
        gTvAttrsOff = G1B_IvarOffset(gTongueViewCls, "_g1b_attributes");
        gTvAnimOff = G1B_IvarOffset(gTongueViewCls, "_g1b_animating");
        gTvMaskSizeOff = G1B_IvarOffset(gTongueViewCls, "_g1b_bitmapMaskSize");
    }
}
// ---- end 1.9

// ============================================================================================================
// 1.3  SBInvalidateContinuousExposeIdentifiersEventResponse  (PARTIAL: type 40 in 16.0, see spec 1.3)
// ============================================================================================================
static ptrdiff_t gInvAnimOff = -1;
static char kInvFrom, kInvTo;
static long long G1B_InvResp_Type(id self, SEL _cmd) { return G1BRespInvalidateContinuousExposeIdentifiers; }
static id G1B_InvResp_Init(id self, SEL _cmd, id from, id to, BOOL animated) {
    id me = G1B_SUPER(id, class_getSuperclass(gInvalidateRespCls), self, @selector(init), (struct objc_super *, SEL));
    if (!me) return nil;
    G1B_SET(me, kInvFrom, from); G1B_SET(me, kInvTo, to);
    if (gInvAnimOff >= 0) *(BOOL *)((uint8_t *)(__bridge void *)me + gInvAnimOff) = animated;
    return me;
}
static id G1B_InvResp_From(id self, SEL _cmd) { return G1B_GET(self, kInvFrom); }
static id G1B_InvResp_To(id self, SEL _cmd) { return G1B_GET(self, kInvTo); }
static BOOL G1B_InvResp_Animated(id self, SEL _cmd) { return gInvAnimOff >= 0 && *(BOOL *)((uint8_t *)(__bridge void *)self + gInvAnimOff); }
static void G1B_BuildInvalidateResponse(void) {
    Class respBase = NSClassFromString(@"SBSwitcherModifierEventResponse");
    if (!respBase) return;
    const G1BIvar iv[] = { { "_g1b_animated", sizeof(BOOL), 0, "B" } };
    const G1BMethod m[] = {
        { "initWithTransitioningFromAppLayout:transitioningToAppLayout:animated:", (IMP)G1B_InvResp_Init, "@36@0:8@16@24B32" },
        { "type", (IMP)G1B_InvResp_Type, "q16@0:8" }, { "transitioningFromAppLayout", (IMP)G1B_InvResp_From, "@16@0:8" },
        { "transitioningToAppLayout", (IMP)G1B_InvResp_To, "@16@0:8" }, { "animated", (IMP)G1B_InvResp_Animated, "B16@0:8" },
    };
    BOOL made = NO;
    gInvalidateRespCls = G1B_MakeClass("SBInvalidateContinuousExposeIdentifiersEventResponse", respBase, iv, 1, m, sizeof m / sizeof m[0], NULL, &made);
    if (made) gInvAnimOff = G1B_IvarOffset(gInvalidateRespCls, "_g1b_animated");
}
// consumer: add this to the _performEventResponse: hook above (kept separate so it can be switched off alone):
%group G1B_VCInvalidate
%hook SBFluidSwitcherViewController
- (void)_performEventResponse:(id)response {
    if (G1B_ON() && gInvalidateRespCls && [response isKindOfClass:gInvalidateRespCls]
        && [self respondsToSelector:@selector(_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:)]) {
        ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(self, @selector(_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:),
            G1B_InvResp_From(response, 0), G1B_InvResp_To(response, 0), G1B_InvResp_Animated(response, 0));
    }
    %orig;
}
%end
%end

// ============================================================================================================
// 2.0  transition-event flags (PORTABLE): isiPadOSWindowingModeChangeEvent / isCommandTabTransition / isLaunchingFromDockTransition
// ============================================================================================================
static char kEvFlagWin, kEvFlagCmdTab, kEvFlagDock;
static BOOL G1B_EvFlag(id ev, const char *key) { return [objc_getAssociatedObject(ev, key) boolValue]; }
static void G1B_EvSetFlag(id ev, const char *key, BOOL v) { objc_setAssociatedObject(ev, key, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static BOOL G1B_EvWin(id s, SEL c) { return G1B_EvFlag(s, &kEvFlagWin); }
static BOOL G1B_EvCmd(id s, SEL c) { return G1B_EvFlag(s, &kEvFlagCmdTab); }
static BOOL G1B_EvDock(id s, SEL c) { return G1B_EvFlag(s, &kEvFlagDock); }
static void G1B_EvSetWin(id s, SEL c, BOOL v) { G1B_EvSetFlag(s, &kEvFlagWin, v); }
static void G1B_EvSetCmd(id s, SEL c, BOOL v) { G1B_EvSetFlag(s, &kEvFlagCmdTab, v); }
static void G1B_EvSetDock(id s, SEL c, BOOL v) { G1B_EvSetFlag(s, &kEvFlagDock, v); }
static void G1B_InstallTransitionEventFlags(void) {
    Class ev = NSClassFromString(@"SBTransitionSwitcherModifierEvent");
    if (!ev) return;
    struct { const char *s; IMP i; const char *t; } m[] = {
        { "isiPadOSWindowingModeChangeEvent", (IMP)G1B_EvWin, "B16@0:8" }, { "setiPadOSWindowingModeChangeEvent:", (IMP)G1B_EvSetWin, "v20@0:8B16" },
        { "isCommandTabTransition", (IMP)G1B_EvCmd, "B16@0:8" }, { "setCommandTabTransition:", (IMP)G1B_EvSetCmd, "v20@0:8B16" },
        { "isLaunchingFromDockTransition", (IMP)G1B_EvDock, "B16@0:8" }, { "setLaunchingFromDockTransition:", (IMP)G1B_EvSetDock, "v20@0:8B16" },
    };
    for (size_t i = 0; i < sizeof m / sizeof m[0]; i++) { SEL s = sel_registerName(m[i].s); if (!class_getInstanceMethod(ev, s)) class_addMethod(ev, s, m[i].i, m[i].t); }
}
// Set the flags from the transition request source (values decoded from 16.2 @0x1c76d485c..: 0x40 / 0x10 / 0x18,0x19).
%group G1B_Coordinator
%hook SBMainSwitcherControllerCoordinator
- (id)transitionEventForContext:(id)context identifier:(id)identifier phase:(unsigned long long)phase animated:(BOOL)animated {
    id ev = %orig;
    if (G1B_ON() && ev && context && [ev respondsToSelector:@selector(setCommandTabTransition:)]) {
        id req = nil;
        for (NSString *n in @[ @"request", @"transitionRequest" ]) { SEL s = NSSelectorFromString(n); if ([context respondsToSelector:s]) { req = G1B_Send0(context, s); if (req) break; } }
        if (req && [req respondsToSelector:@selector(source)]) {
            long long src = G1B_SendLL0(req, @selector(source));
            G1B_SendVLL(ev, @selector(setiPadOSWindowingModeChangeEvent:), src == 0x40);     // BOOL args passed as long long: low byte is read
            G1B_SendVLL(ev, @selector(setCommandTabTransition:), src == 0x10);
            G1B_SendVLL(ev, @selector(setLaunchingFromDockTransition:), src == 0x18 || src == 0x19);
        }
    }
    return ev;
}
%end
%end

// ============================================================================================================
// 2.1 / 2.2  FullScreenToStrip + Crossblur transitions  (PARTIAL: see spec; needs the AppToApp hook 4.8)
// ============================================================================================================
typedef struct { double tl, bl, br, tr; } G1BRadii;             // UIRectCornerRadii
static ptrdiff_t gF2S_Phase = -1, gXB_Phase = -1, gXB_Frame = -1, gXB_Scale = -1, gXB_Radii = -1;
Class gF2SCls, gXBCls;     // shared with G1C.x
static Class gTransSuper;
static char kF2SOut, kF2SReason, kXBTo, kXBFrom, kXBReason;
#define LL_AT(o, off) (*(long long *)((uint8_t *)(__bridge void *)(o) + (off)))

static id G1B_Layout(id self, unsigned long long i) {
    NSArray *a = [self respondsToSelector:@selector(appLayouts)] ? G1B_Send0(self, @selector(appLayouts)) : nil;
    return (i < a.count) ? a[i] : nil;
}
static id G1B_Timer(double delay, NSString *reason) {
    Class c = NSClassFromString(@"SBTimerEventSwitcherEventResponse"); SEL s = @selector(initWithDelay:validator:reason:);
    return (c && [c instancesRespondToSelector:s]) ? ((id (*)(id, SEL, double, id, id))objc_msgSend)([c alloc], s, delay, nil, reason) : nil;
}
static NSString *G1B_ReasonFor(NSString *base) { return [NSString stringWithFormat:@"%@:%@", base, [[NSUUID UUID] UUIDString]]; }
static id G1B_AnimSettingsCopy(id self, double response, double damping) {
    id as = G1B_AnimSettings(self);
    id s = (as && [as respondsToSelector:NSSelectorFromString(@"crossblurDosidoSettings")]) ? [G1B_Send0(as, NSSelectorFromString(@"crossblurDosidoSettings")) copy] : nil;
    if (s && [s respondsToSelector:@selector(setResponse:)]) ((void (*)(id, SEL, double))objc_msgSend)(s, @selector(setResponse:), response);
    if (s && damping > 0 && [s respondsToSelector:@selector(setDampingRatio:)]) ((void (*)(id, SEL, double))objc_msgSend)(s, @selector(setDampingRatio:), damping);
    return s;
}
static double G1B_ASDouble(id self, NSString *name) { return G1B_Dbl0(G1B_AnimSettings(self), NSSelectorFromString(name)); }
static id G1B_Attrs(id self, SEL _cmd, id el, Class sup, double lResp, double lDamp, double oResp, BOOL separateOpacity) {
    id base = G1B_SUPER(id, sup, self, _cmd, (struct objc_super *, SEL, id), el);
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : nil;
    if (!a) return base;
    id ls = G1B_AnimSettingsCopy(self, lResp, lDamp);
    if (ls && [a respondsToSelector:@selector(setLayoutUpdateMode:)] && [a respondsToSelector:@selector(setLayoutSettings:)]) {
        G1B_SendVLL(a, @selector(setLayoutUpdateMode:), 3); G1B_SendV1(a, @selector(setLayoutSettings:), ls);
        id os = separateOpacity ? G1B_AnimSettingsCopy(self, oResp, 0) : ls;
        if (os && [a respondsToSelector:@selector(setOpacitySettings:)]) G1B_SendV1(a, @selector(setOpacitySettings:), os);
    }
    return a;
}
static CGRect G1B_OverlapBBox(id self, id layout) {
    SEL s = @selector(overlappingModelForAppLayout:);
    if (!layout || ![self respondsToSelector:s]) return CGRectZero;
    id model = G1B_Send1(self, s, layout);
    return (model && [model respondsToSelector:@selector(boundingBox)]) ? ((CGRect (*)(id, SEL))objc_msgSend)(model, @selector(boundingBox)) : CGRectZero;
}
static G1BRadii G1B_StageRadii(id self, double scale) {
    id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    double r = G1B_Dbl0(attrs, NSSelectorFromString(@"stageCornerRaddii"));
    double v = scale != 0 ? r / scale : r;
    return (G1BRadii){ v, v, v, v };                              // _SBRectCornerRadiiForRadius(v)
}
static double G1B_Tilt(id self) {
    id attrs = [self respondsToSelector:@selector(chamoisLayoutAttributes)] ? G1B_Send0(self, @selector(chamoisLayoutAttributes)) : nil;
    double t = G1B_Dbl0(attrs, NSSelectorFromString(@"stripTiltAngle"));
    return ([UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) ? -t : t;
}

// ---- FullScreenToStrip
#define F2S_O(self_, layout_) ([G1B_GET(self_, kF2SOut) isEqual:(layout_)])
#define F2S_PH(self_) LL_AT(self_, gF2S_Phase)
static id G1B_F2S_Init(id self, SEL _cmd, id tid, id outgoing) {
    id me = G1B_SUPER(id, gTransSuper, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (!me || gF2S_Phase < 0) return nil;
    G1B_SET(me, kF2SOut, outgoing); F2S_PH(me) = 0;
    G1B_SET(me, kF2SReason, G1B_ReasonFor(@"SBContinuousExposeFullScreenToStripTransitionSwitcherModifierTimerEventReason"));
    return me;
}
static id G1B_F2S_WillBegin(id self, SEL _cmd) {
    id r = G1B_SUPER(id, gTransSuper, self, _cmd, (struct objc_super *, SEL));
    if (gF2S_Phase >= 0 && F2S_PH(self) == 0) { NSString *re = G1B_GET(self, kF2SReason); r = G1B_AppendTo(G1B_Timer(0.14, re), r); r = G1B_AppendTo(G1B_Timer(0.14, re), r); }
    return r;
}
static id G1B_F2S_Timer(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    id reason = [event respondsToSelector:@selector(reason)] ? G1B_Send0(event, @selector(reason)) : nil;
    if (gF2S_Phase >= 0 && [reason isKindOfClass:[NSString class]] && [reason isEqualToString:G1B_GET(self, kF2SReason)] && (F2S_PH(self) == 0 || F2S_PH(self) == 1)) {
        long long mode = F2S_PH(self) == 0 ? 2 : 3; F2S_PH(self) = F2S_PH(self) == 0 ? 1 : 2;
        r = G1B_AppendTo(G1B_NewUpdateLayoutResponse(0x1e, mode), r);
    }
    return r;
}
#define F2S_SUPER_RECT(sel_, T_, v_) G1B_SUPER(CGRect, gTransSuper, self, sel_, (struct objc_super *, SEL, T_), v_)
static CGRect G1B_F2S_Frame(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (!l || gF2S_Phase < 0 || !F2S_O(self, l)) return F2S_SUPER_RECT(_cmd, unsigned long long, i);
    if (F2S_PH(self) == 0) return G1B_OverlapBBox(self, l);
    CGRect f = F2S_SUPER_RECT(_cmd, unsigned long long, i);
    return F2S_PH(self) == 1 ? CGRectMake(f.origin.x * 0.1, f.origin.y * 1.065, f.size.width, f.size.height) : f;
}
static CGRect G1B_F2S_IconOverlay(id self, SEL _cmd, id l) {
    if (l && gF2S_Phase >= 0 && F2S_O(self, l)) return G1B_OverlapBBox(self, l);
    return G1B_SUPER(CGRect, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), l);
}
static CGRect G1B_F2S_AccessoryFrame(id self, SEL _cmd, CGRect f, id l) { return f; }
static G1BRadii G1B_F2S_Radii(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gF2S_Phase >= 0 && F2S_O(self, l) && F2S_PH(self) == 0) {
        double sc = ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), i);
        return G1B_StageRadii(self, sc);
    }
    return G1B_SUPER(G1BRadii, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static CGPoint G1B_F2S_Anchor(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gF2S_Phase >= 0 && F2S_O(self, l) && F2S_PH(self) < 2) return CGPointMake(0.5, 0.5);
    return G1B_SUPER(CGPoint, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1B_F2S_Persp(id self, SEL _cmd, id l) {
    if (l && gF2S_Phase >= 0 && F2S_O(self, l) && F2S_PH(self) == 0) return 0.0;
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), l);
}
static double G1B_F2S_Scale(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gF2S_Phase >= 0 && F2S_O(self, l)) { if (F2S_PH(self) == 0) return G1B_ASDouble(self, @"crossblurDosidoSmallScale"); if (F2S_PH(self) == 1) return 0.32; }
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1B_F2S_Opacity(id self, SEL _cmd, long long role, id l, unsigned long long i) {
    if (l && gF2S_Phase >= 0 && F2S_O(self, l) && F2S_PH(self) < 2) return 0.0;
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, l, i);
}
static double G1B_F2S_TitleOpacity(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gF2S_Phase >= 0 && F2S_O(self, l) && F2S_PH(self) < 2) return 0.0;
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static id G1B_F2S_Attrs(id self, SEL _cmd, id el) { return G1B_Attrs(self, _cmd, el, gTransSuper, 0.4, 1.0, 0.15, YES); }

// ---- Crossblur
#define XB_PH(self_) LL_AT(self_, gXB_Phase)
#define XB_F(self_, l_) ([G1B_GET(self_, kXBFrom) isEqual:(l_)])
#define XB_T(self_, l_) ([G1B_GET(self_, kXBTo) isEqual:(l_)])
static id G1B_XB_Init(id self, SEL _cmd, id tid, id to, id from) {
    id me = G1B_SUPER(id, gTransSuper, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (!me || gXB_Phase < 0) return nil;
    G1B_SET(me, kXBTo, to); G1B_SET(me, kXBFrom, from); XB_PH(me) = 0;
    G1B_SET(me, kXBReason, G1B_ReasonFor(@"SBContinuousExposeFullScreenToStripCrossblurTransitionSwitcherModifierTimerEventReason"));
    return me;
}
static void G1B_XB_DidMove(id self, SEL _cmd, id parent) {
    G1B_SUPER(void, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), parent);
    if (!parent || gXB_Frame < 0 || gXB_Scale < 0 || gXB_Radii < 0 || ![self respondsToSelector:@selector(appLayouts)]) return;
    NSUInteger idx = [(NSArray *)G1B_Send0(self, @selector(appLayouts)) indexOfObject:G1B_GET(self, kXBTo)];
    if (idx == NSNotFound) { BP_Log(@"g1b: Crossblur: toAppLayout unknown"); return; }          // 16.2 asserts here
    *(CGRect *)((uint8_t *)(__bridge void *)self + gXB_Frame) = G1B_SUPER(CGRect, gTransSuper, self, @selector(frameForIndex:), (struct objc_super *, SEL, unsigned long long), (unsigned long long)idx);
    *(double *)((uint8_t *)(__bridge void *)self + gXB_Scale) = G1B_SUPER(double, gTransSuper, self, @selector(scaleForIndex:), (struct objc_super *, SEL, unsigned long long), (unsigned long long)idx);
    *(G1BRadii *)((uint8_t *)(__bridge void *)self + gXB_Radii) = G1B_SUPER(G1BRadii, gTransSuper, self, @selector(cornerRadiiForIndex:), (struct objc_super *, SEL, unsigned long long), (unsigned long long)idx);
}
static id G1B_XB_WillUpdate(id self, SEL _cmd) {
    id r = G1B_SUPER(id, gTransSuper, self, _cmd, (struct objc_super *, SEL));
    if (gXB_Phase >= 0 && XB_PH(self) == 0) r = G1B_AppendTo(G1B_Timer(0.045, G1B_GET(self, kXBReason)), r);
    return r;
}
static id G1B_XB_Timer(id self, SEL _cmd, id event) {
    id r = G1B_SUPER(id, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), event);
    id reason = [event respondsToSelector:@selector(reason)] ? G1B_Send0(event, @selector(reason)) : nil;
    if (gXB_Phase < 0 || ![reason isKindOfClass:[NSString class]] || ![reason isEqualToString:G1B_GET(self, kXBReason)]) return r;
    NSString *re = G1B_GET(self, kXBReason);
    long long ph = XB_PH(self), mode; double delay;
    switch (ph) { case 0: XB_PH(self) = 1; delay = 0.01; mode = 2; break; case 1: XB_PH(self) = 2; delay = 0.25; mode = 3; break;
                  case 2: XB_PH(self) = 3; delay = 0.01; mode = 2; break; case 3: XB_PH(self) = 4; delay = -1; mode = 3; break; default: return r; }
    if (delay >= 0) r = G1B_AppendTo(G1B_Timer(delay, re), r);
    return G1B_AppendTo(G1B_NewUpdateLayoutResponse(0xc, mode), r);
}
static CGRect G1B_XB_Frame(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l) && XB_PH(self) <= 2) return G1B_OverlapBBox(self, l);
        if (!XB_F(self, l) && XB_T(self, l) && XB_PH(self) == 0 && gXB_Frame >= 0) return *(CGRect *)((uint8_t *)(__bridge void *)self + gXB_Frame);
    }
    return G1B_SUPER(CGRect, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1B_XB_Scale(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l)) { if (XB_PH(self) <= 2) return G1B_ASDouble(self, @"crossblurDosidoLargeScale");
                              if (XB_PH(self) == 3) return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i) - 0.02; }
        else if (XB_T(self, l)) { if (XB_PH(self) == 0 && gXB_Scale >= 0) return *(double *)((uint8_t *)(__bridge void *)self + gXB_Scale);
                                  if (XB_PH(self) == 1) return G1B_ASDouble(self, @"crossblurDosidoSmallScale"); }
    }
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1B_XB_Opacity(id self, SEL _cmd, long long role, id l, unsigned long long i) {
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l) && XB_PH(self) < 4) return 0.0;
        if (!XB_F(self, l) && XB_T(self, l)) { if (XB_PH(self) == 0) return 0.0; if (XB_PH(self) == 1) return 0.1; }
    }
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, long long, id, unsigned long long), role, l, i);
}
static double G1B_XB_Persp(id self, SEL _cmd, id l) {
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l) && XB_PH(self) < 3) return 0.0;
        if (!XB_F(self, l) && XB_T(self, l) && XB_PH(self) == 0) return G1B_Tilt(self);
    }
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), l);
}
static CGPoint G1B_XB_Anchor(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l) && XB_PH(self) < 3) return CGPointMake(0.5, 0.5);
        if (!XB_F(self, l) && XB_T(self, l) && XB_PH(self) == 0) {
            BOOL rtl = [UIApplication sharedApplication].userInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
            return rtl ? CGPointMake(0.5, 0.0) : CGPointMake(0.0, 0.5);       // as shipped in 16.2 (RTL value looks like an Apple bug)
        }
    }
    return G1B_SUPER(CGPoint, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static G1BRadii G1B_XB_Radii(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l) && XB_PH(self) <= 2) return G1B_StageRadii(self, ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), i));
        if (!XB_F(self, l) && XB_T(self, l) && XB_PH(self) == 0 && gXB_Radii >= 0) return *(G1BRadii *)((uint8_t *)(__bridge void *)self + gXB_Radii);
    }
    return G1B_SUPER(G1BRadii, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static double G1B_XB_TitleOpacity(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    if (l && gXB_Phase >= 0) {
        if (XB_F(self, l) && XB_PH(self) < 3) return 0.0;
        if (!XB_F(self, l) && XB_T(self, l) && XB_PH(self) < 2) return 0.0;
    }
    return G1B_SUPER(double, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
}
static id G1B_XB_Attrs(id self, SEL _cmd, id el) { return G1B_Attrs(self, _cmd, el, gTransSuper, 0.45, 0.92, 0, NO); }

static void G1B_BuildFullScreenToStrip(void) {
    Class sup = NSClassFromString(@"SBTransitionSwitcherModifier");
    if (!sup || !G1B_HasSuper(sup, @selector(initWithTransitionID:)) || !G1B_HasSuper(sup, @selector(overlappingModelForAppLayout:))) return;
    gTransSuper = sup;
    const G1BIvar i1[] = { { "_g1b_phase", sizeof(long long), 3, "q" } };
    const G1BMethod m1[] = {
        { "initWithTransitionID:outgoingAppLayout:", (IMP)G1B_F2S_Init, "@32@0:8@16@24" }, { "transitionWillBegin", (IMP)G1B_F2S_WillBegin, "@16@0:8" },
        { "handleTimerEvent:", (IMP)G1B_F2S_Timer, "@24@0:8@16" }, { "frameForIndex:", (IMP)G1B_F2S_Frame, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" },
        { "frameForIconOverlayInAppLayout:", (IMP)G1B_F2S_IconOverlay, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8@16" },
        { "adjustedSpaceAccessoryViewFrame:forAppLayout:", (IMP)G1B_F2S_AccessoryFrame, "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48" },
        { "cornerRadiiForIndex:", (IMP)G1B_F2S_Radii, "{?=dddd}24@0:8Q16" }, { "anchorPointForIndex:", (IMP)G1B_F2S_Anchor, "{CGPoint=dd}24@0:8Q16" },
        { "perspectiveAngleForAppLayout:", (IMP)G1B_F2S_Persp, "d24@0:8@16" }, { "scaleForIndex:", (IMP)G1B_F2S_Scale, "d24@0:8Q16" },
        { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1B_F2S_Opacity, "d40@0:8q16@24Q32" }, { "titleAndIconOpacityForIndex:", (IMP)G1B_F2S_TitleOpacity, "d24@0:8Q16" },
        { "animationAttributesForLayoutElement:", (IMP)G1B_F2S_Attrs, "@24@0:8@16" },
    };
    BOOL made = NO;
    gF2SCls = G1B_MakeClass("SBContinuousExposeFullScreenToStripTransitionSwitcherModifier", sup, i1, 1, m1, sizeof m1 / sizeof m1[0], NULL, &made);
    if (made) gF2S_Phase = G1B_IvarOffset(gF2SCls, "_g1b_phase");

    const G1BIvar i2[] = { { "_g1b_phase", sizeof(long long), 3, "q" }, { "_g1b_initialFrame", sizeof(CGRect), 3, "{CGRect=dddd}" },
                           { "_g1b_initialScale", sizeof(double), 3, "d" }, { "_g1b_initialRadii", sizeof(G1BRadii), 3, "{?=dddd}" } };
    const G1BMethod m2[] = {
        { "initWithTransitionID:toAppLayout:fromAppLayout:", (IMP)G1B_XB_Init, "@40@0:8@16@24@32" }, { "didMoveToParentModifier:", (IMP)G1B_XB_DidMove, "v24@0:8@16" },
        { "transitionWillUpdate", (IMP)G1B_XB_WillUpdate, "@16@0:8" }, { "handleTimerEvent:", (IMP)G1B_XB_Timer, "@24@0:8@16" },
        { "frameForIndex:", (IMP)G1B_XB_Frame, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8Q16" }, { "scaleForIndex:", (IMP)G1B_XB_Scale, "d24@0:8Q16" },
        { "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)G1B_XB_Opacity, "d40@0:8q16@24Q32" }, { "perspectiveAngleForAppLayout:", (IMP)G1B_XB_Persp, "d24@0:8@16" },
        { "anchorPointForIndex:", (IMP)G1B_XB_Anchor, "{CGPoint=dd}24@0:8Q16" }, { "cornerRadiiForIndex:", (IMP)G1B_XB_Radii, "{?=dddd}24@0:8Q16" },
        { "titleAndIconOpacityForIndex:", (IMP)G1B_XB_TitleOpacity, "d24@0:8Q16" }, { "animationAttributesForLayoutElement:", (IMP)G1B_XB_Attrs, "@24@0:8@16" },
    };
    made = NO;
    gXBCls = G1B_MakeClass("SBContinuousExposeFullScreenToStripCrossblurTransitionSwitcherModifier", sup, i2, 4, m2, sizeof m2 / sizeof m2[0], NULL, &made);
    if (made) { gXB_Phase = G1B_IvarOffset(gXBCls, "_g1b_phase"); gXB_Frame = G1B_IvarOffset(gXBCls, "_g1b_initialFrame");
                gXB_Scale = G1B_IvarOffset(gXBCls, "_g1b_initialScale"); gXB_Radii = G1B_IvarOffset(gXBCls, "_g1b_initialRadii"); }
}
// ---- end 2.1 / 2.2

// ============================================================================================================
// Stock assertion removed: "Can't handle an event that has already been handled." (NSInternalInconsistencyException).
// With the ported modifiers more than one modifier of the chain can see the same event (device crash: highlight event reaching
// SBFullScreenContinuousExposeSwitcherModifier after another modifier handled it, hover/three-dots menu). A second handling is ignored.
// ============================================================================================================
%group G1B_Handled
%hook SBChainableModifierEvent
- (void)handleWithReason:(id)reason {
    id me = (id)self;      // SBChainableModifierEvent is only forward-declared in this file
    if ([me respondsToSelector:@selector(isHandled)] && ((BOOL (*)(id, SEL))objc_msgSend)(me, @selector(isHandled))) {
        BP_Log(@"event %@ already handled, ignoring second handleWithReason:%@", NSStringFromClass(object_getClass(me)), reason);
        return;
    }
    %orig;
}
%end
%end

// ============================================================================================================
// Safety net for the stock assertion "The appLayouts array MUST contain the app layout we're transitioning to." (device crash after
// "Add Another Window" in the three-dots menu; specs/AUDIT-ADDWINDOW-0.6.4.md has the whole analysis).
//   16.0 -[SBMainSwitcherControllerCoordinator layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:] 0x1c6237d6c:
//     if (![ctx isInterrupted]) { st = [ctx error] ? [ctx fromLayoutState] : [ctx toLayoutState];          // [sp,#0x60]
//       if ([st unlockedEnvironmentMode] == 3) { N = [st appLayout];                                         // x28
//         ... [self _addAppLayoutToFront:removeAppLayout:] (0x1c62384d8, when shouldAddAppLayoutToFront says so) ...
//         if ([[st elements] count]) NSAssert([self->_appLayouts containsObject:N], ...) } }                 // 0x1c62384e0..0x1c62388d4, line 0x42b
//   After the failure branch the code falls through to 0x1c6238510 (the NSAssert macro does not abort), so a handler that returns lets the
//   rest of the method (floating layout, medusa snapshots, _updateHomeScreenDisplayLayoutElement..., _endDisplayLayoutTransition...) run.
//   _appLayouts (ivar +0x18) is written in exactly one place, -_buildAppLayoutCache 0x1c6245ff0 (store at 0x1c6246660).
// What this does: remember (thread-local) the coordinator and N for the duration of that method; when the NSAssert fires for exactly that
// object, repair the state the stock code expected (model add through -_addAppLayoutToFront:, else prepend N to the ivar array) and return
// from the assertion handler instead of raising. A raised exception (handler not reached) is caught and repaired the same way. Everything
// else (other assertions, other coordinators, other methods) behaves exactly as before. Gate: the global kill switch (BP_OnName "addwinnet").
// ============================================================================================================
static __thread __unsafe_unretained id tAWCoordinator;      // coordinator inside the end-of-transition handler (nil outside)
static __thread __unsafe_unretained id tAWLayout;           // N: the app layout that handler asserts on (nil when the assertion cannot run)

static BOOL G1B_AW_Contains(id coord, id layout) {
    Ivar iv = class_getInstanceVariable(object_getClass(coord), "_appLayouts");
    id arr = iv ? object_getIvar(coord, iv) : nil;
    return [arr isKindOfClass:[NSArray class]] && [arr containsObject:layout];
}

// N exactly as the stock code computes it, nil when the assertion path is not taken (interrupted, not mode 3, no app layout, no elements).
static id G1B_AW_Layout(id coord, id ctx, BOOL *notInList) {
    *notInList = NO;
    if (!coord || !ctx || G1B_SendB0(ctx, NSSelectorFromString(@"isInterrupted"))) return nil;
    BOOL failed = G1B_Send0(ctx, NSSelectorFromString(@"error")) != nil;
    id st = G1B_Send0(ctx, NSSelectorFromString(failed ? @"fromLayoutState" : @"toLayoutState"));
    if (!st || G1B_SendLL0(st, NSSelectorFromString(@"unlockedEnvironmentMode")) != 3) return nil;
    id layout = G1B_Send0(st, @selector(appLayout));
    id elems = G1B_Send0(st, NSSelectorFromString(@"elements"));
    if (!layout || G1B_SendLL0(elems, @selector(count)) == 0) return nil;
    *notInList = !G1B_AW_Contains(coord, layout);
    id req = G1B_Send0(G1B_Send0(ctx, NSSelectorFromString(@"applicationTransitionContext")), NSSelectorFromString(@"request"));
    id from = G1B_Send0(ctx, NSSelectorFromString(@"fromLayoutState")), to = G1B_Send0(ctx, NSSelectorFromString(@"toLayoutState"));
    SEL sMode = NSSelectorFromString(@"unlockedEnvironmentMode"), sPeek = NSSelectorFromString(@"peekConfiguration");
    BP_Log(@"addwin: transition end src=%lld error=%d modes %lld->%lld peek %lld->%lld N %@ in _appLayouts=%d",
           G1B_SendLL0(req, @selector(source)), failed, G1B_SendLL0(from, sMode), G1B_SendLL0(to, sMode), G1B_SendLL0(from, sPeek), G1B_SendLL0(to, sPeek),
           layout, !*notInList);
    return layout;
}

// Make _appLayouts contain N. First the official way (model add + rebuild, what the stock code should have done), else the ivar.
static void G1B_AW_Repair(id coord, id layout, const char *how) {
    if (!coord || !layout || G1B_AW_Contains(coord, layout)) return;
    SEL add = NSSelectorFromString(@"_addAppLayoutToFront:");
    if ([coord respondsToSelector:add]) {
        ((void (*)(id, SEL, id))objc_msgSend)(coord, add, layout);
        if (G1B_AW_Contains(coord, layout)) {
            BP_Log(@"addwin net (%s): _addAppLayoutToFront: made _appLayouts contain %@", how, layout);
            return;
        }
    }
    Ivar iv = class_getInstanceVariable(object_getClass(coord), "_appLayouts");
    id cur = iv ? object_getIvar(coord, iv) : nil;
    if (!iv || (cur && ![cur isKindOfClass:[NSArray class]])) {
        BP_Log(@"addwin net (%s): cannot repair (ivar %p)", how, (void *)iv);
        return;
    }
    NSMutableArray *fixed = [NSMutableArray arrayWithObject:layout];
    if (cur) [fixed addObjectsFromArray:cur];
    object_setIvar(coord, iv, [fixed copy]);
    BP_Log(@"addwin net (%s): _appLayouts patched, %lu -> %lu layouts, added %@", how, (unsigned long)G1B_SendLL0(cur, @selector(count)), (unsigned long)fixed.count, layout);
}

%group G1B_AddWin
%hook SBMainSwitcherControllerCoordinator
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    if (!BP_OnName("addwinnet")) {
        %orig;
        return;
    }
    BOOL missing = NO;
    id layout = G1B_AW_Layout(self, context, &missing);
    id savedC = tAWCoordinator, savedL = tAWLayout;
    tAWCoordinator = self;
    tAWLayout = layout;
    @try {
        %orig;
    } @catch (NSException *e) {
        tAWCoordinator = savedC;
        tAWLayout = savedL;
        if (!layout || ![e.name isEqualToString:NSInternalInconsistencyException] || [e.reason rangeOfString:@"appLayouts array MUST contain"].location == NSNotFound) @throw;
        BP_Log(@"addwin net: assertion exception caught, N was %@ in the list at entry", missing ? @"NOT" : @"already");
        G1B_AW_Repair(self, layout, "exception");
        return;
    }
    tAWCoordinator = savedC;
    tAWLayout = savedL;
}
%end

// NSAssert in the method above ends in -[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:], which raises. For that one
// assertion, on that one object, repair and return (the stock code continues exactly as if the condition had held). Every other failure is
// forwarded to the original with the message formatted here (the variadic arguments cannot be forwarded from a hook).
%hook NSAssertionHandler
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName lineNumber:(NSInteger)line description:(NSString *)format, ... {
    if (!format) {
        %orig;
        return;
    }
    if (tAWLayout && object == tAWCoordinator && [format hasPrefix:@"The appLayouts array MUST contain"]) {
        BP_Log(@"addwin net: stock assertion intercepted (%@:%ld), N %@", fileName, (long)line, tAWLayout);
        G1B_AW_Repair(tAWCoordinator, tAWLayout, "assert");
        return;
    }
    va_list ap;
    va_start(ap, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    %orig(selector, object, fileName, line, @"%@", message);
}
%end
%end

// ============================================================================================================
// SBWindowDeleteSwitcherModifier -transitionDidEnd (16.2 0x1c78e702c, new): un-blur the deleted window's container.
// 16.0 -transitionWillUpdate (0x1c6435b6c) blurs the container of _centerWindowAppLayout (SBBlurItemContainerSwitcherEventResponse, shouldBlur YES, mode 3,
// a gaussianBlur CAFilter + rasterization on the container layer) and 16.0 has NO transitionDidEnd: it relies on -_removeVisibleItemContainerForAppLayout:
// (0x1c5e70268) un-blurring the container when it leaves the visible set. With the ported Stage Manager model the closed window's container stays alive
// (it can be reused for the same app layout), so the blur stayed and the app opened again from the same scene was completely blurred (touches worked).
// 16.2 sends shouldBlur NO, mode 2 at the end of the transition (transitionDidEnd 0x1c78e702c, same ivar _centerWindowAppLayout).
// ============================================================================================================
%group G1B_WindowDelete
%hook SBWindowDeleteSwitcherModifier
- (id)transitionDidEnd {
    id r = %orig;
    if (!G1B_ON()) return r;
    id me = (id)self;
    Ivar iv = class_getInstanceVariable(object_getClass(me), "_centerWindowAppLayout");
    id layout = iv ? object_getIvar(me, iv) : nil;
    Class rc = NSClassFromString(@"SBBlurItemContainerSwitcherEventResponse");
    SEL ini = @selector(initWithAppLayout:shouldBlur:animationUpdateMode:);
    if (!layout || !rc || ![rc instancesRespondToSelector:ini]) return r;
    id unblur = ((id (*)(id, SEL, id, BOOL, long long))objc_msgSend)([rc alloc], ini, layout, NO, 2);
    return G1B_AppendTo(unblur, r);
}
%end
%end

// ============================================================================================================
// 2.4  SBiPadOSWindowModeChangeTransitionModifier  (PORTABLE: new class + creator hook; needs 2.0 flags)
// ============================================================================================================
static Class gWinModeCls;
static char kWmFrom, kWmTo;
static id G1B_Wm_Init(id self, SEL _cmd, id tid, id from, id to) {
    if (!from || !to) return nil;                              // 16.2 asserts both
    id me = G1B_SUPER(id, gTransSuper, self, @selector(initWithTransitionID:), (struct objc_super *, SEL, id), tid);
    if (!me) return nil;
    G1B_SET(me, kWmFrom, from); G1B_SET(me, kWmTo, to);
    return me;
}
static BOOL G1B_Wm_MatchMoved(id self, SEL _cmd, long long role, id layout) {
    id from = G1B_GET(self, kWmFrom), to = G1B_GET(self, kWmTo);
    SEL c = @selector(containsAnyItemFromAppLayout:);
    if (layout && ((from && [from respondsToSelector:c] && G1B_SendB1(from, c, layout)) || (to && [to respondsToSelector:c] && G1B_SendB1(to, c, layout)))) return YES;
    return G1B_SUPER(BOOL, gTransSuper, self, _cmd, (struct objc_super *, SEL, long long, id), role, layout);
}
static unsigned long long G1B_Wm_MaskedCorners(id self, SEL _cmd, unsigned long long i) {
    id l = G1B_Layout(self, i);
    unsigned long long m = G1B_SUPER(unsigned long long, gTransSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    id to = G1B_GET(self, kWmTo);
    if (l && to && [to respondsToSelector:@selector(isOrContainsAppLayout:)] && G1B_SendB1(to, @selector(isOrContainsAppLayout:), l)) {
        BOOL chamois = [self respondsToSelector:@selector(isChamoisWindowingUIEnabled)] && G1B_SendB0(self, @selector(isChamoisWindowingUIEnabled));
        if (!chamois || ([self respondsToSelector:@selector(appLayoutContainsAnUnoccludedMaximizedDisplayItem:)] && G1B_SendB1(self, @selector(appLayoutContainsAnUnoccludedMaximizedDisplayItem:), l))) m = 0;
    }
    return m;
}
static void G1B_BuildWindowModeChange(void) {
    Class sup = NSClassFromString(@"SBTransitionSwitcherModifier");
    if (!sup || !G1B_HasSuper(sup, @selector(initWithTransitionID:))) return;
    gTransSuper = sup;
    const G1BMethod m[] = {
        { "initWithTransitionID:fromAppLayout:toAppLayout:", (IMP)G1B_Wm_Init, "@40@0:8@16@24@32" },
        { "isLayoutRoleMatchMovedToScene:inAppLayout:", (IMP)G1B_Wm_MatchMoved, "B32@0:8q16@24" },
        { "maskedCornersForIndex:", (IMP)G1B_Wm_MaskedCorners, "Q24@0:8Q16" },
    };
    gWinModeCls = G1B_MakeClass("SBiPadOSWindowModeChangeTransitionModifier", sup, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
}
%group G1B_Platform
%hook SBiPadOSPlatformSwitcherModifier
- (id)handleTransitionEvent:(id)event {
    id r = %orig;
    if (!G1B_ON() || !gWinModeCls || ![event respondsToSelector:@selector(isiPadOSWindowingModeChangeEvent)] || !G1B_SendB0(event, @selector(isiPadOSWindowingModeChangeEvent))) return r;
    if (G1B_SendLL0(event, @selector(phase)) != 1 || !G1B_SendB0(event, @selector(isAnimated))) return r;
    Ivar iv = class_getInstanceVariable([self class], "_currentUnlockedEnvironmentMode");
    if (!iv || *(long long *)((uint8_t *)(__bridge void *)self + ivar_getOffset(iv)) != 3) return r;
    id from = G1B_Send0(event, @selector(fromAppLayout)), to = G1B_Send0(event, @selector(toAppLayout));
    if (!from || !to || ![self respondsToSelector:@selector(addChildModifier:)]) return r;
    id m = ((id (*)(id, SEL, id, id, id))objc_msgSend)([gWinModeCls alloc], @selector(initWithTransitionID:fromAppLayout:toAppLayout:), G1B_Send0(event, @selector(transitionID)), from, to);
    if (m) G1B_SendV1(self, @selector(addChildModifier:), m);
    return r;
}
%end
%end

// ============================================================================================================
// 2.5  SBContinuousExposeDragAndDropToAppTransitionSwitcherModifier  (PORTABLE as a class; creator is NOT PORTABLE, 3.3)
// ============================================================================================================
Class gDndToAppCls;     // shared with G1C.x
static id G1B_Dnd_Attrs(id self, SEL _cmd, id el) {
    id base = G1B_SUPER(id, gTransSuper, self, _cmd, (struct objc_super *, SEL, id), el);
    id a = [base respondsToSelector:@selector(mutableCopy)] ? [base mutableCopy] : base;
    id ss = [self respondsToSelector:@selector(switcherSettings)] ? G1B_Send0(self, @selector(switcherSettings)) : nil;
    id med = (ss && [ss respondsToSelector:NSSelectorFromString(@"medusaSettings")]) ? G1B_Send0(ss, NSSelectorFromString(@"medusaSettings")) : nil;
    id rs = (med && [med respondsToSelector:NSSelectorFromString(@"resizeAnimationSettings")]) ? G1B_Send0(med, NSSelectorFromString(@"resizeAnimationSettings")) : nil;
    if (a && rs && [a respondsToSelector:@selector(setLayoutSettings:)] && [a respondsToSelector:@selector(setUpdateMode:)]) { G1B_SendV1(a, @selector(setLayoutSettings:), rs); G1B_SendVLL(a, @selector(setUpdateMode:), 3); }
    return a;
}
static id G1B_Dnd_Resign(id self, SEL _cmd) { return @{}; }
static id G1B_Dnd_Keyboard(id self, SEL _cmd) {
    Class c = NSClassFromString(@"SBSwitcherKeyboardSuppressionMode"); SEL s = NSSelectorFromString(@"suppressionModeNone");
    return (c && [c respondsToSelector:s]) ? G1B_Send0((id)c, s) : nil;
}
static G1BAsyncRendering G1B_Dnd_Async(id self, SEL _cmd, id l) { return (G1BAsyncRendering){ NO, NO }; }
static BOOL G1B_Dnd_Crossfade(id self, SEL _cmd) { return NO; }
static void G1B_BuildDndToApp(void) {
    Class sup = NSClassFromString(@"SBTransitionSwitcherModifier");
    if (!sup) return;
    gTransSuper = sup;
    const G1BMethod m[] = {
        { "animationAttributesForLayoutElement:", (IMP)G1B_Dnd_Attrs, "@24@0:8@16" }, { "appLayoutsToResignActive", (IMP)G1B_Dnd_Resign, "@16@0:8" },
        { "keyboardSuppressionMode", (IMP)G1B_Dnd_Keyboard, "@16@0:8" }, { "asyncRenderingAttributesForAppLayout:", (IMP)G1B_Dnd_Async, "{?=BB}24@0:8@16" },
        { "shouldPerformCrossfadeForReduceMotion", (IMP)G1B_Dnd_Crossfade, "B16@0:8" },
    };
    gDndToAppCls = G1B_MakeClass("SBContinuousExposeDragAndDropToAppTransitionSwitcherModifier", sup, NULL, 0, m, sizeof m / sizeof m[0], NULL, NULL);
}

// ============================================================================================================
// 4.1  SBContinuousExposeRootSwitcherModifier -_effectiveEnvironmentMode  (PORTABLE: real 16.0 bug)
// ============================================================================================================
// 16.0 answers 1 (home) for App Expose / inline App Expose floors; 16.2 answers 2 (switcher).
%group G1B_Root
%hook SBContinuousExposeRootSwitcherModifier
- (long long)_effectiveEnvironmentMode {
    long long r = %orig;
    if (!G1B_ON() || r != 1 || ![self respondsToSelector:@selector(floorModifier)]) return r;
    id floor = G1B_Send0(self, @selector(floorModifier));
    if (!floor) return r;
    for (NSString *n in @[ @"SBAppExposeContinuousExposeSwitcherModifier", @"SBInlineAppExposeContinuousExposeSwitcherModifier" ]) {
        Class c = NSClassFromString(n);
        if (c && [floor isKindOfClass:c]) return 2;
    }
    return r;
}
%end
%end

// ============================================================================================================
// 4.8  SBContinuousExposeAppToAppModifier -didMoveToParentModifier:  (PARTIAL: replaces the 16.0 crossblur child; opt-in)
// ============================================================================================================
// Switch file <jbroot>/tmp/Backport162.on.group1b.apptoapp (opt-in): changes the look of every app-to-app transition.
%group G1B_AppToApp
%hook SBContinuousExposeAppToAppModifier
- (void)didMoveToParentModifier:(id)parent {
    NSMutableSet *before = [NSMutableSet set];
    if (parent && [self respondsToSelector:@selector(enumerateChildModifiersWithBlock:)])
        ((void (*)(id, SEL, void (^)(id)))objc_msgSend)(self, @selector(enumerateChildModifiersWithBlock:), ^(id c) { [before addObject:c]; });
    %orig;
    if (!G1B_ON() || !parent || !gF2SCls || !gXBCls || gTransSuper == Nil) return;
    Ivar ivTo = class_getInstanceVariable([self class], "_toAppLayout"), ivFrom = class_getInstanceVariable([self class], "_fromAppLayout");
    id to = ivTo ? object_getIvar(self, ivTo) : nil, from = ivFrom ? object_getIvar(self, ivFrom) : nil;
    SEL cmdTab = @selector(isCommandTabTransition), dock = @selector(isLaunchingFromDockTransition);
    if (!to || !from || ![to respondsToSelector:@selector(containsAnyItemFromAppLayout:)] || ![self respondsToSelector:cmdTab] || ![self respondsToSelector:dock]
        || ![self respondsToSelector:@selector(transitionID)] || ![self respondsToSelector:@selector(appLayouts)]) return;
    // 16.2 condition: different apps (no shared item) and the target layout is known to the switcher.
    if (G1B_SendB1(to, @selector(containsAnyItemFromAppLayout:), from) || ![(NSArray *)G1B_Send0(self, @selector(appLayouts)) containsObject:to]) return;
    // remove the 16.0 crossblur child that %orig may have added
    Class old = NSClassFromString(@"SBContinuousExposeCrossblurModifier");
    if (old) ((void (*)(id, SEL, void (^)(id)))objc_msgSend)(self, @selector(enumerateChildModifiersWithBlock:), ^(id c) {
        if ([c isKindOfClass:old] && ![before containsObject:c]) G1B_SendV1(self, @selector(removeChildModifier:), c); });
    id tid = G1B_Send0(self, @selector(transitionID));
    id child = (G1B_SendB0(self, cmdTab) || G1B_SendB0(self, dock))
        ? ((id (*)(id, SEL, id, id, id))objc_msgSend)([gXBCls alloc], @selector(initWithTransitionID:toAppLayout:fromAppLayout:), tid, to, from)
        : ((id (*)(id, SEL, id, id))objc_msgSend)([gF2SCls alloc], @selector(initWithTransitionID:outgoingAppLayout:), tid, from);
    if (child) G1B_SendV1(self, @selector(addChildModifier:), child);
}
%end
%end

// ============================================================================================================
// setup
// ============================================================================================================
static BOOL G1B_OptIn(const char *name) { return BP_OptInName(name); }

void G1B_Setup(void) {
    G1B_BuildFiltering();
    G1B_BuildOverrideIds();
    G1B_BuildPulse();
    G1B_BuildEventsAndResponses();
    G1B_BuildInvalidateResponse();
    G1B_BuildTongueView();
    G1B_BuildFullScreenToStrip();
    G1B_BuildWindowModeChange();
    G1B_BuildDndToApp();
    G1B_InstallTransitionEventFlags();
    %init(G1B_Handled);                      // second handleWithReason: is ignored instead of asserting
    if (BP_OnName("addwinnet")) %init(G1B_AddWin);   // stock "appLayouts array MUST contain" assertion at the end of a transition: repair instead of crash
    %init(G1B_WindowDelete);                 // 16.2 transitionDidEnd: un-blur the closed window's container (blur after Close + relaunch)
    %init(G1B_Base);                         // 0.1  event types 36..38
    %init(G1B_VC);                           // 1.7 / 1.10 response consumers + 1.5 header-tap emission below
    %init(G1B_VCInvalidate);                 // 1.3 consumer
    %init(G1B_Header);                       // 1.5 (inert unless the FullScreen port defines handleTapAppLayoutHeaderEvent:)
    %init(G1B_Coordinator);                  // 2.0 transition-event flags
    %init(G1B_Platform);                     // 2.4 creator
    %init(G1B_Root);                         // 4.1 _effectiveEnvironmentMode fix
    if (G1B_OptIn("group1b.apptoapp")) %init(G1B_AppToApp);   // 4.8: opt-in, changes every app-to-app transition
}
// Not drafted (see spec): 1.1 users (peek / drag root), 1.9 hosting in the VC, 2.3, 2.6, 3.x, 4.2-4.7, 4.9.
#pragma clang diagnostic pop
