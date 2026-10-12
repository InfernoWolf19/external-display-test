// G1D.x : 16.2 SpringBoard coordinator / switcher controller / gesture manager / VC-side differences that G1B, G1C, G2, G2B and G3 did not cover.
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Findings and the fallbacks removed: specs/PORT-G1D-0.7.0.md.
//
// Integration: call G1D_Setup() from the %ctor after G1B_Setup() / BP2B_Setup() / G1C_Setup() (it adds methods and replaces a few VC methods that G2.x / G2B.m
// stubbed, so it must run after them; it is harmless when it runs earlier because every installer re-checks what exists).
// Every part is default-on; Backport162.off.<name> switches one off. Names: g1d (whole file), g1d_model, g1d_request, g1d_removal, g1d_newwindow, g1d_gesture,
// g1d_vcdrag, g1d_tongue, g1d_pip.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <string.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#include "G1BKit.h"

#define G1D_ON(n) (BP_OnName("g1d") && BP_OnName(n))

@interface SBMainSwitcherControllerCoordinator : NSObject @end
@interface SBSwitcherController : NSObject @end
@interface SBSwitcherTransitionRequest : NSObject @end
@interface SBFluidSwitcherViewController : UIViewController @end
@interface SBFluidSwitcherGestureManager : NSObject @end

// ------------------------------------------------------------------------------------------------ helpers

static id G1D_IvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? object_getIvar(o, iv) : nil;
}
static void G1D_SetIvarObj(id o, const char *name, id v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) object_setIvar(o, iv, v);
}
static unsigned long long G1D_IvarULL(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? *(unsigned long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : 0;
}
static id G1D_Msg1(id o, SEL s, id a) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil; }
static id G1D_Msg2(id o, SEL s, id a, id b) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b) : nil; }
static id G1D_MsgLL(id o, SEL s, long long a) { return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, long long))objc_msgSend)(o, s, a) : nil; }

// SBFIsChamoisWindowingUIAvailable (16.2 SpringBoardFoundation 0x18ee09820 = feature "SBChamoisWindowingUI" availability). The 16.0 equivalent of the very same
// flag is SBFFeatureFlagsIsChamoisWindowingUIEnabled (16.0 0x18eb692c4: device is Chamois capable and the os_feature is on); it is what the 16.0 switcher controller
// derives -isChamoisWindowingUIEnabled from. When neither symbol resolves the tweak runs on a Stage Manager device by construction, so the answer is YES.
static BOOL G1D_ChamoisAvailable(void) {
    static BOOL (*fn)(void); static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFIsChamoisWindowingUIAvailable");
        if (!fn) fn = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFFeatureFlagsIsChamoisWindowingUIEnabled");
    });
    return fn ? fn() : YES;
}

// 16.2 coordinator ivars that 16.0 does not have (runtime-added ivars are not possible): associated objects.
static char kCompatMap;      // _currentWindowingModeCompatibleAppLayoutsByWindowScene (+0x18): NSMapTable weak->strong, window scene -> NSArray<SBAppLayout>
static char kDragging;       // _draggingAppLayouts (+0x40): NSCountedSet
static NSMapTable *G1D_CompatMap(id coord, BOOL create) {
    NSMapTable *m = objc_getAssociatedObject(coord, &kCompatMap);
    if (!m && create) { m = [NSMapTable weakToStrongObjectsMapTable]; objc_setAssociatedObject(coord, &kCompatMap, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return m;
}
static NSCountedSet *G1D_Dragging(id coord) {
    NSCountedSet *s = objc_getAssociatedObject(coord, &kDragging);
    if (!s) { s = [[NSCountedSet alloc] init]; objc_setAssociatedObject(coord, &kDragging, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return s;
}

// ============================================================================================================
// 1. SBMainSwitcherControllerCoordinator: per-scene app layout model
// ============================================================================================================
// 16.2 splits the model into the raw list (_appLayouts, +0x20 there / +0x18 in 16.0) and, per window scene, a list "compatible with the current window management
// style": Stage Manager scenes get +_filterAppLayoutForChamois: applied to every layout, non-Stage-Manager scenes (style 1) get layouts with Medusa incompatible items
// split (appLayoutsBySplittingMedusaIncompatibleItemsWithApplicationController:). -appLayoutsForSwitcherController: serves the per-scene list, filtered by display
// ordinal, and for Stage Manager scenes adds the layouts that are being dragged from another display (converted to this display's ordinal).
// 16.2 addresses: -appLayoutsForSwitcherController: 0x1c76e2354 (16.0 0x1c624d488), -_rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary 0x1c76db498 (+ block
// 0x1c76db5f8), -_rebuildAppListCache 0x1c76dba90, -_buildAppLayoutCache 0x1c76da530 (16.0 0x1c6245ff0), -enumerateSwitcherControllersWithBlock: 0x1c76e2214,
// -convertAppLayout:fromSwitcherController:toSwitcherController: 0x1c76e2b1c, -switcherControllerForAppLayout: 0x1c76e291c, -draggingAppLayouts 0x1c76e2df8,
// -switcherControllerWill/DidUpdateWindowManagementStyle: 0x1c76e2bbc / 0x1c76e2bc8.

static SEL sCurMain, sCurFloat, sWMStyle, sWindowScene, sLayoutState, sDisplayOrdinal, sPrefOrdinal;
static void G1D_InitSels(void) {
    sCurMain = NSSelectorFromString(@"_currentMainAppLayout"); sCurFloat = NSSelectorFromString(@"_currentFloatingAppLayout");
    sWMStyle = NSSelectorFromString(@"windowManagementStyle"); sWindowScene = NSSelectorFromString(@"windowScene");
    sLayoutState = NSSelectorFromString(@"layoutState"); sDisplayOrdinal = NSSelectorFromString(@"displayOrdinal"); sPrefOrdinal = NSSelectorFromString(@"preferredDisplayOrdinal");
}
// layoutState.displayOrdinal of a switcher controller (16.2 reads [sc layoutState] / [[ws layoutStateProvider] layoutState]; both are the provider's state)
static long long G1D_SCOrdinal(id sc) {
    id st = [sc respondsToSelector:sLayoutState] ? G1B_Send0(sc, sLayoutState) : nil;
    if (!st) st = G1B_Send0(G1B_Send0(G1B_Send0(sc, sWindowScene), NSSelectorFromString(@"layoutStateProvider")), sLayoutState);
    return G1B_SendLL0(st, sDisplayOrdinal);
}
static long long G1D_LayoutOrdinal(id layout) { return G1B_SendLL0(layout, sPrefOrdinal); }
static NSArray *G1D_AllSCs(id coord) {
    NSMapTable *byScene = G1D_IvarObj(coord, "_switcherControllersByWindowScene");
    return [[byScene objectEnumerator] allObjects] ?: @[];
}
// the display ordinal mask of -appLayoutsForSwitcherController: (block 0x1c76e2898: scenes that are NOT the main display window scene)
static long long G1D_OrdinalMask(id coord, id sc) {
    id ws = G1B_Send0(sc, sWindowScene);
    NSMapTable *byScene = G1D_IvarObj(coord, "_switcherControllersByWindowScene");
    if (G1B_SendB0(ws, NSSelectorFromString(@"isMainDisplayWindowScene"))) {
        long long mask = -1;
        for (id scene in [[byScene keyEnumerator] allObjects]) {
            if (G1B_SendB0(scene, NSSelectorFromString(@"isMainDisplayWindowScene"))) continue;
            id st = G1B_Send0(G1B_Send0(scene, NSSelectorFromString(@"layoutStateProvider")), sLayoutState);
            int ord = (int)G1B_SendLL0(st, sDisplayOrdinal);
            mask &= (long long)(int)~(1 << (ord + 1));
        }
        return mask;
    }
    int ord = (int)G1D_SCOrdinal(sc);
    return (long long)(int)(1 << (ord + 1));
}

%group G1D_Model
%hook SBMainSwitcherControllerCoordinator

// 16.2 0x1c76e2354
- (id)appLayoutsForSwitcherController:(id)sc {
    if (!G1D_ON("g1d_model")) return %orig;
    id me = (id)self;
    NSArray *base = G1D_IvarObj(me, "_appLayouts");
    id ws = G1B_Send0(sc, sWindowScene);
    if (G1D_ChamoisAvailable()) {
        NSArray *c = ws ? [G1D_CompatMap(me, NO) objectForKey:ws] : nil;
        if (c) base = c;
    }
    NSMapTable *byScene = G1D_IvarObj(me, "_switcherControllersByWindowScene");
    if (byScene.count == 1) return base;
    long long mask = G1D_OrdinalMask(me, sc);
    NSMutableArray *result = [[NSMutableArray alloc] init];
    for (id l in base) {
        int bit = (int)G1D_LayoutOrdinal(l) + 1;
        long long b = (long long)(int)(1 << bit);
        if ((b & ~mask) == 0) [result addObject:l];
    }
    if (G1B_SendLL0(sc, sWMStyle) == 2) {
        for (id l in [G1D_Dragging(me) allObjects]) {
            id item = G1D_MsgLL(l, @selector(itemForLayoutRole:), 1);
            BOOL present = NO;
            for (id r in result) if (G1B_SendB1(r, NSSelectorFromString(@"containsItem:"), item)) { present = YES; break; }
            if (present) continue;
            id from = nil;
            for (id s2 in G1D_AllSCs(me)) if (G1D_SCOrdinal(s2) == G1D_LayoutOrdinal(l)) { from = s2; break; }
            id conv = ((id (*)(id, SEL, id, id, id))objc_msgSend)(me, NSSelectorFromString(@"convertAppLayout:fromSwitcherController:toSwitcherController:"), l, from, sc);
            if (conv) [result addObject:conv];
        }
    }
    return result;
}

// 16.2 0x1c76dba90: build, rebuild the per-scene lists, notify
- (void)_rebuildAppListCache {
    if (!G1D_ON("g1d_model")) {
        %orig;
        return;
    }
    id me = (id)self;
    ((void (*)(id, SEL))objc_msgSend)(me, NSSelectorFromString(@"_buildAppLayoutCache"));
    ((void (*)(id, SEL))objc_msgSend)(me, NSSelectorFromString(@"_rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary"));
    ((void (*)(id, SEL))objc_msgSend)(me, NSSelectorFromString(@"_notifySwitcherControllersAppLayoutsDidChange"));
}

// 16.2 0x1c76da530. Same as 16.0 0x1c6245ff0 except for the front-layout item stripping (see the marked block).
- (void)_buildAppLayoutCache {
    if (!G1D_ON("g1d_model")) {
        %orig;
        return;
    }
    id me = (id)self;
    id model = G1D_IvarObj(me, "_mainSwitcherModel");
    NSMutableArray *list;
    {
        SEL s = NSSelectorFromString(@"appLayoutsIncludingHiddenAppLayouts:");
        id a = [model respondsToSelector:s] ? ((id (*)(id, SEL, BOOL))objc_msgSend)(model, s, NO) : nil;
        list = [a mutableCopy] ?: [NSMutableArray array];
    }
    NSMutableArray *mainLayouts = [NSMutableArray array], *floatingLayouts = [NSMutableArray array], *prioritized = [NSMutableArray array];
    NSMutableSet *mainItems = [NSMutableSet set], *floatingItems = [NSMutableSet set];
    __block BOOL dragFlag = NO;
    ((void (*)(id, SEL, id))objc_msgSend)(me, NSSelectorFromString(@"enumerateSwitcherControllersWithBlock:"), ^(id sc, BOOL *stop) {      // block 0x1c76daea4
        id main = G1B_Send0(sc, sCurMain);
        if (main) { [mainLayouts addObject:main]; NSArray *a = G1B_Send0(main, NSSelectorFromString(@"allItems")); if (a) [mainItems addObjectsFromArray:a]; }
        id fl = G1B_Send0(sc, sCurFloat);
        if (fl) { [floatingLayouts addObject:fl]; NSArray *a = G1B_Send0(fl, NSSelectorFromString(@"allItems")); if (a) [floatingItems addObjectsFromArray:a]; }
        if (G1B_SendB0(sc, NSSelectorFromString(@"isMainSwitcherVisible")))
            dragFlag |= G1B_SendB0(G1B_Send0(sc, NSSelectorFromString(@"gestureManager")), NSSelectorFromString(@"isDragAndDropTransactionRunning"));
    });
    NSMutableIndexSet *remove = [NSMutableIndexSet indexSet];
    NSSet *dragIds = G1D_IvarObj(me, "_windowDragSceneIdentifiers");
    NSArray *demoHidden = G1D_IvarObj(me, "_demoFilteringHiddenAppLayouts");
    SEL contAnySet = NSSelectorFromString(@"containsAnyItemFromSet:"), shouldPrio = NSSelectorFromString(@"_shouldPrioritizeSortOrderForAppLayout:");
    [list enumerateObjectsUsingBlock:^(id l, NSUInteger idx, BOOL *stop) {                                                                  // block 0x1c76dafbc
        long long env = G1B_SendLL0(l, @selector(environment));
        if (env == 2 && G1B_SendB1(l, contAnySet, mainItems) && !dragFlag) { [remove addIndex:idx]; return; }
        if (env == 1 && G1B_SendB1(l, contAnySet, floatingItems) && !dragFlag) { [remove addIndex:idx]; return; }
        if (G1B_SendB1(me, shouldPrio, l)) { [remove addIndex:idx]; [prioritized addObject:l]; }
        for (id sid in dragIds) {
            if (G1B_SendB1(l, NSSelectorFromString(@"containsItemWithUniqueIdentifier:"), sid)) { [remove addIndex:idx]; break; }
        }
        if ([demoHidden containsObject:l]) [remove addIndex:idx];
    }];
    [list removeObjectsAtIndexes:remove];
    // ---- 16.2 only: strip the items of the most recent layout from the other main layouts ----
    id first = list.firstObject;
    NSArray *mains = mainLayouts;
    if (first && [mainLayouts containsObject:first]) {
        NSMutableArray *stripped = [NSMutableArray arrayWithCapacity:mainLayouts.count];
        for (id l in mainLayouts) {
            if ([l isEqual:first]) { [stripped addObject:l]; continue; }
            if (G1B_SendB1(l, NSSelectorFromString(@"containsAnyItemFromAppLayout:"), first)) {
                BOOL (^test)(id) = ^BOOL(id item) { return !G1B_SendB1(first, NSSelectorFromString(@"containsItem:"), item); };     // block 0x1c76db184
                id s = ((id (*)(id, SEL, BOOL (^)(id)))objc_msgSend)(l, NSSelectorFromString(@"appLayoutWithItemsPassingTest:"), test);
                if (s) [stripped addObject:s];
            } else [stripped addObject:l];
        }
        mains = stripped;
    }
    // ---- main + floating layouts go to the front ----
    NSSet *terminating = G1D_IvarObj(me, "_liveDisplayItemsBeingTerminated");
    for (id l in [mains arrayByAddingObjectsFromArray:floatingLayouts]) {
        if (G1B_SendB1(l, contAnySet, terminating) || [list containsObject:l]) continue;
        if (dragFlag) continue;
        if ([prioritized containsObject:l]) continue;
        if (G1B_SendLL0(l, @selector(environment)) == 1) {
            NSMutableArray *mapped = [NSMutableArray array];
            for (id o in list) {                                                                                                         // bs_compactMap: block 0x1c76db1a8
                BOOL (^t)(id) = ^BOOL(id item) { return !G1B_SendB1(l, NSSelectorFromString(@"containsItem:"), item); };                 // block 0x1c76db230
                id r = ((id (*)(id, SEL, BOOL (^)(id)))objc_msgSend)(o, NSSelectorFromString(@"appLayoutWithItemsPassingTest:"), t);
                if (r) [mapped addObject:r];
            }
            list = [mapped mutableCopy];
        }
        [list insertObject:l atIndex:0];
    }
    // ---- app switcher services ----
    Class mgrC = NSClassFromString(@"SBAppSwitcherServiceManager"), diC = NSClassFromString(@"SBDisplayItem");
    id snapshot = G1B_Send0([mgrC respondsToSelector:@selector(sharedInstance)] ? G1B_Send0((id)mgrC, @selector(sharedInstance)) : nil, NSSelectorFromString(@"registeredServicesSnapshot"));
    G1D_SetIvarObj(me, "_switcherServices", snapshot);
    id services = G1D_IvarObj(me, "_switcherServices");
    NSUInteger n = (NSUInteger)G1B_SendLL0(services, @selector(count));
    for (NSUInteger i = 0; i < n; i++) {
        id svc = G1D_MsgLL(services, NSSelectorFromString(@"serviceAtIndex:"), (long long)i);
        NSString *sbid = G1B_Send0(svc, @selector(bundleIdentifier));
        id item = G1D_Msg1((id)diC, NSSelectorFromString(@"switcherServiceDisplayItemWithServiceIdentifier:"), sbid);
        SEL fromItem = NSSelectorFromString(@"_appLayoutFromPrimaryLayoutItem:sideLayoutElement:configuration:");
        id svcLayout = [me respondsToSelector:fromItem] ? ((id (*)(id, SEL, id, id, long long))objc_msgSend)(me, fromItem, item, nil, 1) : nil;
        NSMutableArray *removedBefore = G1D_IvarObj(me, "_servicesRemovedWhileAwayFromSwitcher");
        NSMutableArray *drop = [NSMutableArray array];
        for (id o in removedBefore) if ([G1B_Send0(o, @selector(bundleIdentifier)) isEqualToString:sbid]) [drop addObject:o];
        [removedBefore removeObjectsInArray:drop];
        if (svcLayout && ![list containsObject:svcLayout]) [list insertObject:svcLayout atIndex:0];
    }
    // ---- test item ----
    id testItem = G1D_IvarObj(me, "_testItemForInsertion");
    if (testItem) {
        unsigned long long idx = G1D_IvarULL(me, "_testItemInsertionIndex");
        if (idx <= list.count) { [list removeObject:testItem]; [list insertObject:testItem atIndex:idx]; }
    }
    // ---- transient overlay layouts and the prioritized layouts after the first non-prioritized layout ----
    NSUInteger at = [list indexOfObjectPassingTest:^BOOL(id l, NSUInteger idx, BOOL *stop) {                                            // block 0x1c76db254
        BOOL r = (G1B_SendLL0(l, @selector(type)) != 0) || !G1B_SendB1(me, shouldPrio, l);
        *stop = r;
        return r;
    }];
    if (at == NSNotFound) at = list.count;
    NSDictionary *eligible = G1D_IvarObj(me, "_appLayoutToEligibleTransientOverlayViewController");
    NSArray *overlayLayouts = [eligible allKeys];
    [list insertObjects:overlayLayouts atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, overlayLayouts.count)]];
    [list insertObjects:prioritized atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(at, prioritized.count)]];
    G1D_SetIvarObj(me, "_appLayouts", list);
}

%new
- (void)enumerateSwitcherControllersWithBlock:(id)block {                    // 16.2 0x1c76e2214 (16.0: the private name)
    ((void (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"_enumerateSwitcherControllersWithBlock:"), block);
}

%new
- (id)convertAppLayout:(id)layout fromSwitcherController:(id)from toSwitcherController:(id)to {       // 16.2 0x1c76e2b1c
    if ([from isEqual:to]) return layout;
    return G1D_MsgLL(layout, NSSelectorFromString(@"appLayoutByModifyingPreferredDisplayOrdinal:"), G1D_SCOrdinal(to));
}

%new
- (id)switcherControllerForAppLayout:(id)layout {                              // 16.2 0x1c76e291c
    NSMapTable *byScene = G1D_IvarObj(self, "_switcherControllersByWindowScene");
    if (byScene.count == 1) return [[byScene objectEnumerator] nextObject];
    for (id sc in G1D_AllSCs(self)) {
        NSArray *ls = ((id (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"appLayoutsForSwitcherController:"), sc);
        if ([ls containsObject:layout]) return sc;
    }
    return nil;
}

%new
- (id)draggingAppLayouts { return [G1D_Dragging(self) copy]; }               // 16.2 0x1c76e2df8

%new
- (void)switcherControllerWillUpdateWindowManagementStyle:(id)sc {           // 16.2 0x1c76e2bbc
    ((void (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"failMultitaskingGesturesForReason:"), @"Window management style is changing");
}

%new
- (void)switcherControllerDidUpdateWindowManagementStyle:(id)sc {            // 16.2 0x1c76e2bc8
    ((void (*)(id, SEL))objc_msgSend)(self, NSSelectorFromString(@"_rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary"));
}

// 16.2 0x1c76db498 + block 0x1c76db5f8
%new
- (void)_rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary {
    if (!G1D_ChamoisAvailable()) return;
    id me = (id)self;
    NSArray *appLayouts = G1D_IvarObj(me, "_appLayouts");
    __block NSMutableArray *stageManagerList = nil, *medusaList = nil;
    Class co = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
    SEL filter = NSSelectorFromString(@"_filterAppLayoutForChamois:");
    ((void (*)(id, SEL, id))objc_msgSend)(me, NSSelectorFromString(@"enumerateSwitcherControllersWithBlock:"), ^(id sc, BOOL *stop) {
        id ws = G1B_Send0(sc, sWindowScene);
        long long style = G1B_SendLL0(sc, sWMStyle);
        if (style == 2) {
            if (!stageManagerList) {
                for (id l in appLayouts) {
                    id f = [co respondsToSelector:filter] ? G1B_Send1((id)co, filter, l) : nil;
                    if (!f) continue;
                    if (!stageManagerList) stageManagerList = [appLayouts mutableCopy];
                    NSUInteger idx = [stageManagerList indexOfObject:l];
                    if (idx != NSNotFound) [stageManagerList replaceObjectAtIndex:idx withObject:f];
                }
            }
            if (stageManagerList) [G1D_CompatMap(me, YES) setObject:stageManagerList forKey:ws];
            else [G1D_CompatMap(me, NO) removeObjectForKey:ws];
        } else if (style == 1) {
            if (!medusaList) {
                id appC = G1B_Send0((id)NSClassFromString(@"SBApplicationController"), @selector(sharedInstance));
                for (id l in appLayouts) {
                    NSArray *split = G1D_Msg1(l, NSSelectorFromString(@"appLayoutsBySplittingMedusaIncompatibleItemsWithApplicationController:"), appC);
                    if (!split) continue;
                    if (!medusaList) medusaList = [appLayouts mutableCopy];
                    NSUInteger idx = [medusaList indexOfObject:l];
                    [medusaList removeObject:l];
                    NSUInteger i = 0;
                    for (id s in split) { [medusaList insertObject:s atIndex:idx + i]; i++; }
                }
            }
            if (medusaList) [G1D_CompatMap(me, YES) setObject:medusaList forKey:ws];
            else [G1D_CompatMap(me, NO) removeObjectForKey:ws];
        }
    });
    NSMapTable *m = G1D_CompatMap(me, NO);
    if (m && m.count == 0) objc_setAssociatedObject(me, &kCompatMap, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end
%end // G1D_Model

// ============================================================================================================
// 1b. Coordinator: window-style callbacks, request configuration, removal results, new window, window drag bookkeeping, mode 1 -> 3 add
// ============================================================================================================
static __thread __unsafe_unretained id tConnecting;                  // coordinator inside -windowSceneDidConnect:
static __thread __unsafe_unretained id tSetChamoisSC;               // SBSwitcherController inside -setChamoisWindowingUIEnabled: (when the value changes)
static __thread __unsafe_unretained id tCfgReq, tCfgLayout;         // SBSwitcherTransitionRequest and the layout it must report inside -_configureRequest:...
static __thread __unsafe_unretained id tRRSelf, tRRLayouts;         // coordinator and the removal request's app layouts inside -_switcherModelRemovalResultsForRequest:forReason:
static __thread NSUInteger tRRIdx;
static __thread __unsafe_unretained id tEndSelf, tEndTo;            // coordinator and the to-layout state inside the mode 1 -> 3 part of transitionDidEnd

@interface SBDeviceApplicationSceneEntity : NSObject
+ (id)newEntityWithApplication:(id)application sceneHandleProvider:(id)provider displayIdentity:(id)identity;
@end

%group G1D_Coord
%hook SBMainSwitcherControllerCoordinator

// 16.2 windowSceneDidConnect: 0x1c76c8410 calls -switcherControllerDidUpdateWindowManagementStyle: right after the new switcher controller is registered and
// before -setupSwitcherWindowIfNeeded; the hook of that method below runs the callback at exactly that point.
- (void)windowSceneDidConnect:(id)scene {
    if (!G1D_ON("g1d_model")) {
        %orig;
        return;
    }
    id saved = tConnecting;
    tConnecting = self;
    %orig;
    tConnecting = saved;
}

// ---- 16.2 -_configureRequest:forSwitcherTransitionRequest:withEventLabel: (0x1c76d174c; 16.0 0x1c623e164) ----
// New in 16.2: (1) in a Stage Manager scene an environment 2 request layout is converted with -appLayoutByModifyingEnvironment:1 before anything reads it;
// (2) the request's activatingDisplayItem becomes the context's activating entity (home screen item -> home entity; an item of the layout -> its scene entity, plus a
// completion handler that gives that scene keyboard focus after the transition).
- (void)_configureRequest:(id)wreq forSwitcherTransitionRequest:(id)req withEventLabel:(id)label {
    if (!G1D_ON("g1d_request") || !req) {
        %orig;
        return;
    }
    id me = (id)self;
    id layout = G1B_Send0(req, @selector(appLayout));
    id app = [UIApplication sharedApplication];
    id wsm = G1B_Send0(app, NSSelectorFromString(@"windowSceneManager"));
    id ws = G1D_Msg1(wsm, NSSelectorFromString(@"windowSceneForDisplayIdentity:"), G1B_Send0(wreq, NSSelectorFromString(@"displayIdentity")));
    id sc = G1D_Msg1(me, NSSelectorFromString(@"switcherControllerForWindowScene:"), ws);
    id conv = nil;
    if (layout && G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled")) && G1B_SendLL0(layout, @selector(environment)) == 2)
        conv = G1D_MsgLL(layout, NSSelectorFromString(@"appLayoutByModifyingEnvironment:"), 1);
    id savedReq = tCfgReq, savedLayout = tCfgLayout;
    tCfgReq = req; tCfgLayout = conv;
    %orig;
    tCfgReq = savedReq; tCfgLayout = savedLayout;
    // ---- activating display item ----
    SEL getAct = NSSelectorFromString(@"activatingDisplayItem");
    id act = [req respondsToSelector:getAct] ? G1B_Send0(req, getAct) : nil;
    id ctx = G1B_Send0(wreq, NSSelectorFromString(@"applicationContext"));
    if (!act || !ctx) return;
    id eff = conv ?: layout;
    long long mode = G1B_SendLL0(req, NSSelectorFromString(@"unlockedEnvironmentMode"));
    long long floatVisible = G1B_SendLL0(req, NSSelectorFromString(@"floatingSwitcherVisible"));
    BOOL fromTop = mode == 2 ? YES : (floatVisible == 1);                    // BSSettingFlagIsYes
    Class layoutC = NSClassFromString(@"SBAppLayout"), itemC = NSClassFromString(@"SBDisplayItem");
    id homeLayout = G1B_Send0((id)layoutC, NSSelectorFromString(@"homeScreenAppLayout"));
    if (mode == 1 || (eff && [eff isEqual:homeLayout])) return;                // the home path already set the home entity
    SEL setAct = NSSelectorFromString(@"setActivatingEntity:");
    if ([act isEqual:G1B_Send0((id)itemC, NSSelectorFromString(@"homeScreenDisplayItem"))]) {
        id home = G1B_Send0((id)NSClassFromString(@"SBHomeScreenEntity"), @selector(entity));
        G1B_SendV1(ctx, setAct, home);
        return;
    }
    if (fromTop || !eff || !G1B_SendB1(eff, NSSelectorFromString(@"containsItem:"), act)) return;
    id sm = G1B_Send0(ws, NSSelectorFromString(@"sceneManager"));
    id entity = ((id (*)(id, SEL, id, id, id))objc_msgSend)(me, NSSelectorFromString(@"_entityForDisplayItem:sceneHandleProvider:displayIdentity:"), act, sm, G1B_Send0(sm, NSSelectorFromString(@"displayIdentity")));
    G1B_SendV1(ctx, setAct, entity);
    SEL addCompletion = NSSelectorFromString(@"addCompletionHandler:");
    if ([wreq respondsToSelector:addCompletion]) {
        void (^done)(BOOL) = ^(BOOL success) {                                   // block 0x1c76d2840
            if (!success) return;
            id scene = G1B_Send0(G1B_Send0(G1B_Send0(entity, NSSelectorFromString(@"applicationSceneEntity")), NSSelectorFromString(@"sceneHandle")), NSSelectorFromString(@"sceneIfExists"));
            if (!scene) return;
            Class mw = NSClassFromString(@"SBMainWorkspace");
            id kfc = G1B_Send0(G1B_Send0((id)mw, NSSelectorFromString(@"mainWorkspace")), NSSelectorFromString(@"keyboardFocusController"));
            SEL focus = NSSelectorFromString(@"userFocusRequestForScene:reason:completion:");
            if ([kfc respondsToSelector:focus]) ((void (*)(id, SEL, id, id, id))objc_msgSend)(kfc, focus, scene, @"SwitcherTransitionRequest", nil);
        };
        ((id (*)(id, SEL, id))objc_msgSend)(wreq, addCompletion, done);
    }
}

// ---- 16.2 -_switcherModelRemovalResultsForRequest:forReason: (0x1c76e0660; 16.0 0x1c624b4b0) ----
// The "current main / floating app layout" of each removed layout is read from the switcher controller that owns the layout (-switcherControllerForAppLayout:),
// 16.0 read the ACTIVE display's (-_currentAppLayout / -_currentFloatingAppLayout), which is wrong for a window that is closed on the other display.
// The two reads happen once per removed layout, in request order (16.0 0x1c624b5xx: _currentAppLayout then _currentFloatingAppLayout inside the loop).
- (id)_switcherModelRemovalResultsForRequest:(id)req forReason:(long long)reason {
    if (!G1D_ON("g1d_removal")) return %orig;
    id sRRSelf = tRRSelf, sRRLayouts = tRRLayouts; NSUInteger sIdx = tRRIdx;
    NSArray *ls = [G1B_Send0(req, @selector(appLayouts)) isKindOfClass:[NSArray class]] ? G1B_Send0(req, @selector(appLayouts)) : [G1B_Send0(req, @selector(appLayouts)) respondsToSelector:@selector(allObjects)] ? [G1B_Send0(req, @selector(appLayouts)) allObjects] : nil;
    tRRSelf = self; tRRLayouts = ls; tRRIdx = 0;
    id r = %orig;
    tRRSelf = sRRSelf; tRRLayouts = sRRLayouts; tRRIdx = sIdx;
    return r;
}
- (id)_currentAppLayout {
    if (tRRSelf == (id)self && tRRLayouts && tRRIdx < [(NSArray *)tRRLayouts count]) {
        id l = [(NSArray *)tRRLayouts objectAtIndex:tRRIdx];
        id sc = G1D_Msg1((id)self, NSSelectorFromString(@"switcherControllerForAppLayout:"), l);
        return G1B_Send0(sc, sCurMain);
    }
    return %orig;
}
- (id)_currentFloatingAppLayout {
    if (tRRSelf == (id)self && tRRLayouts && tRRIdx < [(NSArray *)tRRLayouts count]) {
        id l = [(NSArray *)tRRLayouts objectAtIndex:tRRIdx];
        tRRIdx++;
        id sc = G1D_Msg1((id)self, NSSelectorFromString(@"switcherControllerForAppLayout:"), l);
        return G1B_Send0(sc, sCurFloat);
    }
    return %orig;
}

// ---- 16.2 -switcherContentController:requestNewWindowForBundleIdentifier: (0x1c76d5ce0; 16.0 0x1c624239c) ----
// The new window is requested for the display of the content controller's switcher (entity with that display's scene manager / identity, transition on that display)
// instead of always for the main display.
- (void)switcherContentController:(id)controller requestNewWindowForBundleIdentifier:(id)bundleIdentifier {
    if (!G1D_ON("g1d_newwindow")) {
        %orig;
        return;
    }
    id me = (id)self;
    id sc = G1D_Msg1(me, NSSelectorFromString(@"_switcherControllerForContentViewController:"), controller);
    id ws = G1B_Send0(sc, sWindowScene);
    id cfg = G1B_Send0(ws, NSSelectorFromString(@"_fbsDisplayConfiguration"));
    Class appC = NSClassFromString(@"SBApplicationController");
    id app = G1D_Msg1(G1B_Send0((id)appC, @selector(sharedInstance)), NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundleIdentifier);
    id sm = G1B_Send0(ws, NSSelectorFromString(@"sceneManager"));
    id ident = G1B_Send0(ws, NSSelectorFromString(@"_fbsDisplayIdentity"));
    Class entC = NSClassFromString(@"SBDeviceApplicationSceneEntity");
    id entity = [(Class)entC newEntityWithApplication:app sceneHandleProvider:sm displayIdentity:ident];
    Class wc = NSClassFromString(@"SBWorkspace");
    id workspace = G1B_Send0((id)wc, NSSelectorFromString(@"mainWorkspace"));
    SEL rt = NSSelectorFromString(@"requestTransitionWithOptions:displayConfiguration:builder:");
    if (![workspace respondsToSelector:rt]) {
        %orig;
        return;
    }
    void (^builder)(id) = ^(id request) {                                        // block 0x1c76d5e60
        G1B_SendVLL(request, NSSelectorFromString(@"setSource:"), 0x23);
        G1B_SendV1(request, NSSelectorFromString(@"setEventLabel:"), @"NewWindowRequest");
        void (^modify)(id) = ^(id context) { G1B_SendV1(context, NSSelectorFromString(@"setActivatingEntity:"), entity); };           // block 0x1c76d5f10
        G1B_SendV1(request, NSSelectorFromString(@"modifyApplicationContext:"), modify);
    };
    ((BOOL (*)(id, SEL, unsigned long long, id, id))objc_msgSend)(workspace, rt, 0, cfg, builder);
}

// ---- 16.2 window drag bookkeeping and broadcast (0x1c76d79e4 / 0x1c76d7ba8 / 0x1c76d7d18) ----
// The drag of a Stage Manager window (gesture type 9) is announced to every switcher controller with the same window management style, so the neighbouring display
// can show the proposed drop; the layout being dragged is kept in _draggingAppLayouts, which -appLayoutsForSwitcherController: serves to the other display.
- (void)fluidSwitcherGestureManager:(id)manager didBeginGesture:(id)gesture {
    if (!G1D_ON("g1d_gesture")) {
        %orig;
        return;
    }
    id me = (id)self;
    id sc = G1B_Send0(manager, NSSelectorFromString(@"switcherController"));
    long long type = G1B_SendLL0(gesture, @selector(type));
    if (type == 9 && G1B_SendLL0(sc, sWMStyle) == 2) {
        id sel = G1B_Send0(gesture, NSSelectorFromString(@"selectedAppLayout"));
        if (sel) [G1D_Dragging(me) addObject:sel];
        ((void (*)(id, SEL))objc_msgSend)(me, NSSelectorFromString(@"_rebuildAppListCache"));
    }
    SEL fwd = NSSelectorFromString(@"fluidSwitcherGestureManager:didBeginGesture:");
    ((void (*)(id, SEL, id))objc_msgSend)(me, NSSelectorFromString(@"enumerateSwitcherControllersWithBlock:"), ^(id other, BOOL *stop) {            // block 0x1c76d7b20
        if ([other isEqual:sc] || (type == 9 && G1B_SendLL0(other, sWMStyle) == G1B_SendLL0(sc, sWMStyle)))
            if ([other respondsToSelector:fwd]) ((void (*)(id, SEL, id, id))objc_msgSend)(other, fwd, manager, gesture);
    });
}
- (void)fluidSwitcherGestureManager:(id)manager didUpdateGesture:(id)gesture {
    if (!G1D_ON("g1d_gesture")) {
        %orig;
        return;
    }
    id sc = G1B_Send0(manager, NSSelectorFromString(@"switcherController"));
    long long type = G1B_SendLL0(gesture, @selector(type));
    SEL fwd = NSSelectorFromString(@"fluidSwitcherGestureManager:didUpdateGesture:");
    ((void (*)(id, SEL, id))objc_msgSend)((id)self, NSSelectorFromString(@"enumerateSwitcherControllersWithBlock:"), ^(id other, BOOL *stop) {
        if ([other isEqual:sc] || (type == 9 && G1B_SendLL0(other, sWMStyle) == G1B_SendLL0(sc, sWMStyle)))
            if ([other respondsToSelector:fwd]) ((void (*)(id, SEL, id, id))objc_msgSend)(other, fwd, manager, gesture);
    });
}
- (void)fluidSwitcherGestureManager:(id)manager didEndGesture:(id)gesture {
    if (!G1D_ON("g1d_gesture")) {
        %orig;
        return;
    }
    id me = (id)self;
    id sc = G1B_Send0(manager, NSSelectorFromString(@"switcherController"));
    long long type = G1B_SendLL0(gesture, @selector(type));
    SEL fwd = NSSelectorFromString(@"fluidSwitcherGestureManager:didEndGesture:");
    ((void (*)(id, SEL, id))objc_msgSend)(me, NSSelectorFromString(@"enumerateSwitcherControllersWithBlock:"), ^(id other, BOOL *stop) {
        if ([other isEqual:sc] || (type == 9 && G1B_SendLL0(other, sWMStyle) == G1B_SendLL0(sc, sWMStyle)))
            if ([other respondsToSelector:fwd]) ((void (*)(id, SEL, id, id))objc_msgSend)(other, fwd, manager, gesture);
    });
    if (type == 9 && G1B_SendLL0(sc, sWMStyle) == 2) {
        id sel = G1B_Send0(gesture, NSSelectorFromString(@"selectedAppLayout"));
        if (sel) [G1D_Dragging(me) removeObject:sel];
        ((void (*)(id, SEL))objc_msgSend)(me, NSSelectorFromString(@"_rebuildAppListCache"));
    }
}

// ---- PiP morph producers (16.2 0x1c76d4ea0 / 0x1c76d50e0, caller -transitionEventForContext:identifier:phase:animated: 0x1c76d3e1c) ----
// 16.2 asks "morph from PiP" first (request source 0x2d; the role of the activating entity is the PiP's layout role) and only when that is NO "morph to PiP" (the 16.0
// conditions, plus the entity that SBAutoPIPWorkspaceTransaction found: its layout role). The role goes to the event (morphingPIPLayoutRole), both flags are then
// exclusive. 16.0 evaluated the two independently and had no role.
%new
- (BOOL)_shouldMorphFromPIPForTransitionContext:(id)context outForLayoutRole:(long long *)outRole {
    long long source = G1B_SendLL0(G1B_Send0(context, NSSelectorFromString(@"request")), @selector(source));
    if (outRole) *outRole = source == 0x2d ? G1B_SendLL0(G1B_Send0(context, NSSelectorFromString(@"requestedActivatingWorkspaceEntity")), NSSelectorFromString(@"layoutRole")) : 0;
    return source == 0x2d;
}
%new
- (BOOL)_shouldMorphToPIPForTransitionContext:(id)context outForLayoutRole:(long long *)outRole {
    if (outRole) *outRole = 0;
    SEL old = NSSelectorFromString(@"_shouldMorphToPIPForTransitionContext:");
    BOOL r = [self respondsToSelector:old] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(self, old, context) : NO;     // the 16.0 body = 16.2's conditions up to the auto PiP query
    if (!r || !outRole) return r;
    Class apt = NSClassFromString(@"SBAutoPIPWorkspaceTransaction");
    SEL q = NSSelectorFromString(@"shouldAutoPIPEnteringBackgroundForRequest:foundEntity:transitionStyle:");
    if (![apt respondsToSelector:q]) return r;
    __autoreleasing id entity = nil; long long style = 0;
    ((BOOL (*)(id, SEL, id, id __autoreleasing *, long long *))objc_msgSend)((id)apt, q, G1B_Send0(context, NSSelectorFromString(@"request")), &entity, &style);
    if (entity) *outRole = G1B_SendLL0(entity, NSSelectorFromString(@"layoutRole"));
    return r;
}
- (id)transitionEventForContext:(id)context identifier:(id)identifier phase:(unsigned long long)phase animated:(BOOL)animated {
    id ev = %orig;
    if (!ev || !context || !G1D_ON("g1d_pip") || ![ev respondsToSelector:@selector(setMorphToPIPTransition:)]) return ev;
    id me = (id)self;
    long long role = 0;
    BOOL from = ((BOOL (*)(id, SEL, id, long long *))objc_msgSend)(me, NSSelectorFromString(@"_shouldMorphFromPIPForTransitionContext:outForLayoutRole:"), context, &role);
    BOOL to = NO;
    if (!from) to = ((BOOL (*)(id, SEL, id, long long *))objc_msgSend)(me, NSSelectorFromString(@"_shouldMorphToPIPForTransitionContext:outForLayoutRole:"), context, &role);
    G1B_SendVLL(ev, @selector(setMorphFromPIPTransition:), from);
    G1B_SendVLL(ev, @selector(setMorphToPIPTransition:), to);
    SEL sr = NSSelectorFromString(@"setMorphingPIPLayoutRole:");
    if ([ev respondsToSelector:sr]) G1B_SendVLL(ev, sr, role);
    return ev;
}

// ---- 16.2 mode 1 -> 3 part of -layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext: (0x1c76cb178, display ordinal check at 0x1c76cbbcc) ----
// When the transition goes from the home screen (mode 1) to Stage Manager (mode 3) and the new app layout is not in the model, the layout is added only if every one of its
// items lives, in the model, in a layout with the same preferred display ordinal (16.0 added it unconditionally). Implemented on the single add of that part.
- (void)layoutStateTransitionCoordinator:(id)coordinator transitionDidEndWithTransitionContext:(id)context {
    if (!G1D_ON("g1d_model")) {
        %orig;
        return;
    }
    id sSelf = tEndSelf, sTo = tEndTo;
    id from = G1B_Send0(context, NSSelectorFromString(@"fromLayoutState")), to = G1B_Send0(context, NSSelectorFromString(@"toLayoutState"));
    BOOL failed = G1B_Send0(context, NSSelectorFromString(@"error")) != nil;
    BOOL interrupted = G1B_SendB0(context, NSSelectorFromString(@"isInterrupted"));
    SEL mode = NSSelectorFromString(@"unlockedEnvironmentMode");
    BOOL part = !failed && !interrupted && G1B_SendLL0(from, mode) == 1 && G1B_SendLL0(to, mode) == 3;
    tEndSelf = part ? (id)self : nil; tEndTo = part ? to : nil;
    %orig;
    tEndSelf = sSelf; tEndTo = sTo;
}
- (void)_addAppLayoutToFront:(id)layout {
    if (tEndSelf == (id)self && tEndTo && layout && G1D_ON("g1d_model")) {
        id n = G1B_Send0(tEndTo, @selector(appLayout));
        if (n && [layout isEqual:n]) {
            id model = G1D_IvarObj((id)self, "_mainSwitcherModel");
            SEL inc = NSSelectorFromString(@"appLayoutContainingDisplayItem:includingHiddenAppLayouts:");
            for (id item in G1B_Send0(n, NSSelectorFromString(@"allItems"))) {
                id existing = [model respondsToSelector:inc] ? ((id (*)(id, SEL, id, BOOL))objc_msgSend)(model, inc, item, NO) : nil;
                if (G1D_LayoutOrdinal(existing) != G1D_LayoutOrdinal(n)) {
                    if (BP_LogEnabled()) BP_Log(@"g1d: mode 1->3 add of %@ skipped: item %@ lives on display ordinal %lld, layout wants %lld", n, item, G1D_LayoutOrdinal(existing), G1D_LayoutOrdinal(n));
                    return;
                }
            }
        }
    }
    %orig;
}

%end

// SBSwitcherController: the callbacks of the window management style (16.2 -setChamoisWindowingUIEnabled: 0x1c76006fc)
%hook SBSwitcherController
- (void)setupSwitcherWindowIfNeeded {
    id c = tConnecting;
    if (c) {                                   // the first call inside -windowSceneDidConnect: is for the controller that was just registered
        tConnecting = nil;
        ((void (*)(id, SEL, id))objc_msgSend)(c, NSSelectorFromString(@"switcherControllerDidUpdateWindowManagementStyle:"), self);
    }
    %orig;
}
- (void)setChamoisWindowingUIEnabled:(BOOL)enabled {
    id saved = tSetChamoisSC;
    tSetChamoisSC = (G1B_SendB0((id)self, NSSelectorFromString(@"isChamoisWindowingUIEnabled")) != enabled) ? (id)self : nil;
    %orig;
    tSetChamoisSC = saved;
}
%end

// the Did callback sits between the defaults update and -[gestureManager updateForChamoisWindowingUIEnabled:] in the 16.2 setter
%hook SBFluidSwitcherGestureManager
- (void)updateForChamoisWindowingUIEnabled:(BOOL)enabled {
    id sc = tSetChamoisSC;
    if (sc && G1D_ON("g1d_model")) {
        tSetChamoisSC = nil;
        id coord = G1B_Send0(sc, NSSelectorFromString(@"switcherCoordinator"));
        ((void (*)(id, SEL, id))objc_msgSend)(coord, NSSelectorFromString(@"switcherControllerDidUpdateWindowManagementStyle:"), sc);
    }
    %orig;
}
%end

// the request layout reported inside -_configureRequest:...
%hook SBSwitcherTransitionRequest
- (id)appLayout {
    if (tCfgReq == (id)self && tCfgLayout) return tCfgLayout;
    return %orig;
}
%end
%end // G1D_Coord

// ============================================================================================================
// 2. SBSwitcherController / SBFluidSwitcherViewController: window drag across displays, request activating item
// ============================================================================================================
// SBSwitcherController (16.2 0x1c76070cc / 0x1c7607148 / 0x1c76071c4): gesture manager delegate methods that forward to the content controller. The coordinator
// broadcasts the window drag gestures to the controllers of all displays (see the coordinator hooks above), 16.0 had no such methods on the controller.
static void G1D_SC_Gesture(id self, SEL _cmd, id manager, id gesture) {
    id vc = G1B_Send0(self, NSSelectorFromString(@"contentViewController"));
    NSString *n = NSStringFromSelector(_cmd);
    NSString *vcName = [n hasSuffix:@"didBeginGesture:"] ? @"handleFluidSwitcherGestureManager:didBeginGesture:" : [n hasSuffix:@"didUpdateGesture:"] ? @"handleFluidSwitcherGestureManager:didUpdateGesture:" : @"handleFluidSwitcherGestureManager:didEndGesture:";
    SEL vs = NSSelectorFromString(vcName);
    if (vc && [vc respondsToSelector:vs]) ((void (*)(id, SEL, id, id))objc_msgSend)(vc, vs, manager, gesture);
}
static void G1D_SC_Noop3(id self, SEL _cmd, id manager, id identifier) {}                 // 16.2 0x1c7607240 / 0x1c7607244 / 0x1c7607248 are bare `ret`

// SBFluidSwitcherGesture -gestureEvent while the 16.0 handlers run with the event the 16.2 handlers dispatch (-_adjustedGestureEventForGestureEvent:fromGestureManager:)
static __thread __unsafe_unretained id tAdjGesture, tAdjEvent;
%group G1D_Gesture
%hook SBFluidSwitcherGesture
- (id)gestureEvent {
    if (tAdjGesture == (id)self && tAdjEvent) return tAdjEvent;
    return %orig;
}
%end
%end

// SBFluidSwitcherViewController -handleFluidSwitcherGestureManager:didBegin/Update/EndGesture: (16.2 0x1c7438ad0 / 0x1c7439048 / 0x1c7439258).
// 16.2 bodies = the 16.0 handleGestureDid{Begin,Update,End}: bodies, with the dispatched event replaced by
// -_adjustedGestureEventForGestureEvent:fromGestureManager: (the event of a neighbouring display's window drag, re-expressed in this display's coordinates) and the
// assertion that the manager is this controller's own or the gesture is a Continuous Expose window drag.
static void G1D_VC_HandleGesture(id vc, NSString *oldName, id manager, id gesture) {
    SEL old = NSSelectorFromString(oldName);
    if (![vc respondsToSelector:old]) return;
    id sc = G1B_Send0(vc, NSSelectorFromString(@"switcherController"));
    id own = G1B_Send0(sc, NSSelectorFromString(@"gestureManager"));
    id ev = G1B_Send0(gesture, NSSelectorFromString(@"gestureEvent"));
    BOOL drag = G1B_SendB0(ev, NSSelectorFromString(@"isContinuousExposeWindowDragEvent"));
    if (manager != own && ![manager isEqual:own] && !drag) BP_Log(@"g1d: %@ from a foreign gesture manager for a non window-drag gesture (16.2 asserts)", oldName);
    SEL adj = NSSelectorFromString(@"_adjustedGestureEventForGestureEvent:fromGestureManager:");
    id adjusted = [vc respondsToSelector:adj] ? ((id (*)(id, SEL, id, id))objc_msgSend)(vc, adj, ev, manager) : ev;
    id sg = tAdjGesture, se = tAdjEvent;
    tAdjGesture = (adjusted && adjusted != ev) ? gesture : nil; tAdjEvent = adjusted;
    ((void (*)(id, SEL, id))objc_msgSend)(vc, old, gesture);
    tAdjGesture = sg; tAdjEvent = se;
}
// 16.2 -_adjustedGestureEventForGestureEvent:fromGestureManager: 0x1c745f2fc
static id G1D_VC_Adjusted(id self, SEL _cmd, id event, id manager) {
    if (!G1B_SendB0(event, NSSelectorFromString(@"isContinuousExposeWindowDragEvent"))) return event;
    id from = G1B_Send0(G1B_Send0(manager, NSSelectorFromString(@"switcherController")), NSSelectorFromString(@"contentViewController"));
    SEL conv = NSSelectorFromString(@"_convertContinuousExposeWindowDragEvent:fromSwitcherContentViewController:");
    return [self respondsToSelector:conv] ? ((id (*)(id, SEL, id, id))objc_msgSend)(self, conv, event, from) : event;
}
// 16.2 -draggingAppLayoutsForContinuousExposeWindowDrag 0x1c74388d8 and -proposedAppLayoutsForContinuousExposeWindowDrag 0x1c7438944
static id G1D_VC_DraggingLayouts(id self, SEL _cmd) {
    id coord = G1B_Send0(G1B_Send0(self, NSSelectorFromString(@"switcherController")), NSSelectorFromString(@"switcherCoordinator"));
    return G1B_Send0(coord, NSSelectorFromString(@"draggingAppLayouts"));
}
static id G1D_VC_ProposedLayouts(id self, SEL _cmd) {
    NSMutableSet *set = [[NSMutableSet alloc] init];
    id coord = G1B_Send0(G1B_Send0(self, NSSelectorFromString(@"switcherController")), NSSelectorFromString(@"switcherCoordinator"));
    SEL en = NSSelectorFromString(@"enumerateSwitcherControllersWithBlock:");
    if ([coord respondsToSelector:en]) ((void (*)(id, SEL, id))objc_msgSend)(coord, en, ^(id sc, BOOL *stop) {            // block 0x1c7438a24
        id vc = G1B_Send0(sc, NSSelectorFromString(@"contentViewController"));
        if (![vc isKindOfClass:NSClassFromString(@"SBFluidSwitcherViewController")]) vc = nil;
        id proposed = G1B_Send0(G1B_Send0(vc, NSSelectorFromString(@"rootModifier")), NSSelectorFromString(@"proposedAppLayoutForContinuousExposeWindowDrag"));
        if (proposed) [set addObject:proposed];
    });
    return set;
}

// SBSwitcherTransitionRequest activatingDisplayItem (16.2 ivar +0x18): associated object, same accessor names, so G1C's request producer stores it here
static char kActItem;
static id G1D_Req_GetAct(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kActItem); }
static void G1D_Req_SetAct(id self, SEL _cmd, id item) { objc_setAssociatedObject(self, &kActItem, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

static void G1D_InstallWindowDragSupport(void) {
    Class sc = NSClassFromString(@"SBSwitcherController");
    if (sc) {
        const G1BMethod m[] = {
            { "fluidSwitcherGestureManager:didBeginGesture:", (IMP)G1D_SC_Gesture, "v32@0:8@16@24" },
            { "fluidSwitcherGestureManager:didUpdateGesture:", (IMP)G1D_SC_Gesture, "v32@0:8@16@24" },
            { "fluidSwitcherGestureManager:didEndGesture:", (IMP)G1D_SC_Gesture, "v32@0:8@16@24" },
            { "fluidSwitcherGestureManager:didBeginDraggingWindowWithSceneIdentifier:", (IMP)G1D_SC_Noop3, "v32@0:8@16@24" },
            { "fluidSwitcherGestureManager:didPlatterizeWindowDragWithSceneIdentifier:", (IMP)G1D_SC_Noop3, "v32@0:8@16@24" },
            { "fluidSwitcherGestureManager:willEndDraggingWindowWithSceneIdentifier:", (IMP)G1D_SC_Noop3, "v32@0:8@16@24" },
        };
        G1B_AddMethods(sc, m, sizeof m / sizeof m[0]);
    }
    Class rq = NSClassFromString(@"SBSwitcherTransitionRequest");
    if (rq) {
        if (!class_getInstanceMethod(rq, NSSelectorFromString(@"activatingDisplayItem"))) class_addMethod(rq, NSSelectorFromString(@"activatingDisplayItem"), (IMP)G1D_Req_GetAct, "@16@0:8");
        if (!class_getInstanceMethod(rq, NSSelectorFromString(@"setActivatingDisplayItem:"))) class_addMethod(rq, NSSelectorFromString(@"setActivatingDisplayItem:"), (IMP)G1D_Req_SetAct, "v24@0:8@16");
    }
    Class vc = NSClassFromString(@"SBFluidSwitcherViewController");
    if (!vc || !G1D_ON("g1d_vcdrag")) return;
    // These replace what G2.x / G2B.m added as stand-ins ("add if missing" there, so the order of the setups does not matter).
    struct { const char *n, *old; } t[] = { { "handleFluidSwitcherGestureManager:didBeginGesture:", "handleGestureDidBegin:" }, { "handleFluidSwitcherGestureManager:didUpdateGesture:", "handleGestureDidUpdate:" }, { "handleFluidSwitcherGestureManager:didEndGesture:", "handleGestureDidEnd:" } };
    for (size_t i = 0; i < 3; i++) {
        NSString *old = [NSString stringWithUTF8String:t[i].old];
        IMP imp = imp_implementationWithBlock(^(id me, id manager, id gesture) { G1D_VC_HandleGesture(me, old, manager, gesture); });
        class_replaceMethod(vc, sel_registerName(t[i].n), imp, "v32@0:8@16@24");
    }
    class_replaceMethod(vc, NSSelectorFromString(@"_adjustedGestureEventForGestureEvent:fromGestureManager:"), (IMP)G1D_VC_Adjusted, "@32@0:8@16@24");
    class_replaceMethod(vc, NSSelectorFromString(@"draggingAppLayoutsForContinuousExposeWindowDrag"), (IMP)G1D_VC_DraggingLayouts, "@16@0:8");
    class_replaceMethod(vc, NSSelectorFromString(@"proposedAppLayoutsForContinuousExposeWindowDrag"), (IMP)G1D_VC_ProposedLayouts, "@16@0:8");
}

// ============================================================================================================
// setup
// ============================================================================================================
void G1D_Setup(void) {
    if (!BP_OnName("g1d")) return;
    G1D_InitSels();
    G1D_InstallWindowDragSupport();
    %init(G1D_Model);
    %init(G1D_Coord);
    %init(G1D_Gesture);
}
#pragma clang diagnostic pop
