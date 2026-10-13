// G1D.x : 16.2 SpringBoard coordinator / switcher controller / gesture manager / VC-side differences that G1B, G1C, G2, G2B and G3 did not cover.
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Findings and the fallbacks removed: specs/PORT-G1D-0.7.0.md.
//
// Integration: call G1D_Setup() from the %ctor after G1B_Setup() / BP2B_Setup() / G1C_Setup() (it adds methods and replaces a few VC methods that G2.x / G2B.m
// stubbed, so it must run after them; it is harmless when it runs earlier because every installer re-checks what exists).
// Every part is default-on; Backport162.off.<name> switches one off. Names: g1d (whole file), g1d_model, g1d_request, g1d_removal, g1d_newwindow, g1d_gesture,
// g1d_vcdrag, g1d_pointer, g1d_tongue, g1d_gmtouch, g1d_windowdrag, g1d_updatemode, g1d_pip, g1d_pipframes, g1d_piprestore, g1d_pipkeyboard, g1d_pipinsets, g1d_extgestures.

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

static BOOL G1D_TongueUsable(id gestureManager);                      // section 4
static void G1D_GM_Update(id gestureManager, BOOL enabled);           // section 4
@interface SBMainSwitcherControllerCoordinator : NSObject @end
@interface SBSwitcherController : NSObject @end
@interface SBSwitcherTransitionRequest : NSObject @end
@interface SBFluidSwitcherViewController : UIViewController @end
@interface SBFluidSwitcherGestureManager : NSObject @end
@interface SBMainWorkspace : NSObject @end
@interface SBFloatingDockController : NSObject @end

// ------------------------------------------------------------------------------------------------ helpers

static id G1D_IvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return BP_ObjIvar(o, iv);
}
static void G1D_SetIvarObj(id o, const char *name, id v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) BP_SetObjIvar(o, iv, v);
}
static unsigned long long G1D_IvarULL(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) return 0;
    const uint8_t *p = (const uint8_t *)(__bridge void *)o + ivar_getOffset(iv);
    const char *e = ivar_getTypeEncoding(iv);                       // read exactly the ivar's size (an int ivar read as 8 bytes returned the neighbour's bits too)
    switch (e ? e[0] : 'Q') {
        case 'c': case 'C': case 'B': return *(const uint8_t *)p;
        case 's': case 'S': return *(const uint16_t *)p;
        case 'i': case 'I': return *(const uint32_t *)p;
        default: return *(const unsigned long long *)p;
    }
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
                    if (idx == NSNotFound) continue;                  // an equal layout was already replaced: inserting at NSNotFound + i raises NSRangeException
                    [medusaList removeObject:l];
                    NSUInteger i = 0;
                    for (id s in split) { [medusaList insertObject:s atIndex:MIN(idx + i, medusaList.count)]; i++; }
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
    if (G1D_TongueUsable(self)) { G1D_GM_Update(self, enabled); return; }      // the 16.2 body (section 4)
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
// 2b. SBFluidSwitcherViewController -_performModifierUpdateLayoutResponse: with an UNSPECIFIED update mode
// ============================================================================================================
// 16.2 (0x1c745c7dc) wraps the update in -_performWithFixedUpdateMode:usingBlock: only when the response's updateMode is not 0 and otherwise runs the very same block directly.
// 16.0 (0x1c5fe30b8) always wraps, i.e. it fixes the update mode to 0 (SBAnimationUpdateModeUnspecified) and the layout / style animation then dies in sb_animateWithSettings with
// "needs a explicit update mode, not SBAnimationUpdateModeUnspecified" for every attribute that has no mode of its own. 16.2 modifiers (the strip's highlight / handle-event responses,
// SBUpdateLayoutSwitcherEventResponse with mode 0, ported verbatim by G1C) rely on this: pressing / dragging a strip window crashed SpringBoard. The thread local is set only for the
// dynamic extent of the response (the 16.2 branch), a mode 0 request from anywhere else keeps the 16.0 behaviour.
static __thread BOOL tInUpdateLayoutResponse;
%group G1D_VCUpdateMode
%hook SBFluidSwitcherViewController
- (void)_performModifierUpdateLayoutResponse:(id)response {
    if (!G1D_ON("g1d_updatemode") || G1B_SendLL0(response, NSSelectorFromString(@"updateMode")) != 0) {
        %orig;
        return;
    }
    BOOL saved = tInUpdateLayoutResponse;
    tInUpdateLayoutResponse = YES;
    %orig;
    tInUpdateLayoutResponse = saved;
}
- (void)_performWithFixedUpdateMode:(long long)mode usingBlock:(id)block {
    if (mode == 0 && tInUpdateLayoutResponse && block) {
        tInUpdateLayoutResponse = NO;
        ((void (^)(void))block)();
        return;
    }
    %orig;
}
%end
%end

// ============================================================================================================
// 4. SBFluidSwitcherGestureManager: the continuous expose strip reveal grabber tongue (touch edge pull + pointer edge pull)
// ============================================================================================================
// 16.0 reveals the strip only with a pointer (SBIndirectPanGestureRecognizer `indirectRevealContinuousExposeStripsGestureRecognizer`, ivar +0x138, action
// -_handleFluidGesture:, system gesture 0x34). 16.2 replaces it with an SBGrabberTongue (type 0x37, edge = -_continuousExposeStripEdge, name
// "ContinuousExposeStripRevealGrabberTongue", ivar +0x140) that owns BOTH recognizers: a touch SBScreenEdgePanGestureRecognizer (delegate method
// -customGestureRecognizerForGrabberTongue:) and the pointer SBIndirectPanGestureRecognizer (-indirectPanGestureRecognizerForGrabberTongue:, system gesture 0x34), the
// tongue view itself is suppressed because the view controller hosts the SBContinuousExposeStripTongueView (-shouldSuppressTongueViewForGrabberTongue:).
// 16.2 addresses: -_configureChamoisGestureRecognizersIfNeeded 0x1c78f0c08 (16.0 0x1c643eea4), -updateForChamoisWindowingUIEnabled: 0x1c78f0fe8 (0x1c643f408),
// -_continuousExposeStripEdge 0x1c78fbe50, -customGestureRecognizerForGrabberTongue: 0x1c78fa7e8, -indirectPanGestureRecognizerForGrabberTongue: 0x1c78faa00 (+ block
// 0x1c78faca0), -indirectPanSystemGestureTypeForGrabberTongue: 0x1c78fad3c, -shouldSuppressTongueViewForGrabberTongue: 0x1c78fada0, -grabberTongueOrPullEnabled:
// forGestureRecognizer: 0x1c78fa3c0, -_grabberTongueForGestureRecognizer: 0x1c78fb8c0, -grabberTongue:shouldReceiveTouch: 0x1c72c4d40, -grabberTongue:
// shouldShowTongueOnFirstSwipeWithEdgeLocation: 0x1c72c90ac, -grabberTongue:shouldAllowSecondSwipeWithEdgeLocation: 0x1c72ca7a0, -grabberTongueBegan/Updated/Ended/
// CanceledPulling: 0x1c78fa480 / 55c / 630 / 70c, -grabberTongueWillPresent: 0x1c78fae14, -grabberTongueWillDismiss: 0x1c78fb0a4, -_handleContinuousExposeStripReveal
// Gesture: 0x1c78f27e8, -_shouldBeginContinuousExposeStripRevealGesture: 0x1c78f95c4, -_shouldBeginContinuousExposeStripOverflowGesture: 0x1c78f9738,
// -_areContinuousExposeStripsAvailableWithReason: 0x1c78fba84, -_areContinuousExposeStripsOccludedOrHiddenWithOutReason: 0x1c78fbc38, -_shouldContinuousExposeStrip
// OverflowPanGesture:receiveTouch: 0x1c78f5ef0, -_gestureTypeForGestureRecognizer: 0x1c72cad14, -invalidate 0x1c78f16c0, -[SBFluidSwitcherViewController
// presentContinuousExposeStripEdgeProtectTongue / dismiss...] 0x1c744f4e0 / 0x1c744f540, -isEdgeProtectedForHomeGestureAtEdgeLocation:edge: 0x1c744c954 (16.0
// 1-argument form 0x1c5fd3a74), -[SBMainDisplaySystemGestureManager _shouldEnableSystemGestureWithType:] 0x1c72e9590 (16.0 0x1c5e76c00).
// The 16.0 SBGrabberTongue already speaks the same delegate protocol (same init, same install / pull / present callbacks); it only lacks the `name` and `screenEdge`
// accessors.  The system gesture type 0x37 is unused in 16.0 (16.2 inserted it, which shifts every later type by one), and the 16.0 type tables answer for 0x37 like
// for the hover gesture 0x33 on the main display after the one-line hook below.
static char kG1DStripTongue, kG1DTongueName;
enum { G1DStripTongueGestureType = 0x37, G1DStripIndirectGestureType = 0x34, G1DStripRevealFluidGestureType = 0xb };

static id G1D_GMWeak(id gm, const char *name) {
    Ivar iv = gm ? class_getInstanceVariable(object_getClass(gm), name) : NULL;
    return BP_ObjIvar(gm, iv);                    // a weak ivar holds the raw pointer, the runtime zeroes it on dealloc
}
static id G1D_GM_SC(id gm) { return G1D_GMWeak(gm, "_switcherController"); }
static id G1D_GM_VC(id gm) { return G1D_GMWeak(gm, "_switcherContentController"); }
static id G1D_GM_Scene(id gm) { return G1B_Send0(G1D_GM_SC(gm), NSSelectorFromString(@"windowScene")); }

static id G1D_StripTongue(id gm) {
    id t = G1B_Send0(gm, NSSelectorFromString(@"continuousExposeStripRevealGrabberTongue"));      // G1B's accessor (same object), else our own key
    return t ?: objc_getAssociatedObject(gm, &kG1DStripTongue);
}
static void G1D_SetStripTongue(id gm, id t) {
    objc_setAssociatedObject(gm, &kG1DStripTongue, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    G1B_SendV1(gm, NSSelectorFromString(@"setContinuousExposeStripRevealGrabberTongue:"), t);
}
static BOOL G1D_IsStripTongue(id gm, id tongue) { return tongue && tongue == G1D_StripTongue(gm); }
static BOOL G1D_TongueOn(void) { return G1D_ON("g1d_tongue"); }

// -[SBFluidSwitcherGestureManager _continuousExposeStripEdge] 0x1c78fbe50: right-to-left layout = right edge (8), else left edge (2)
static unsigned long long G1D_StripEdge(void) {
    return [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft ? 8 : 2;
}

static BOOL G1D_TongueUsable(id gm) {
    if (!gm || !G1D_TongueOn()) return NO;
    Class tc = NSClassFromString(@"SBGrabberTongue");
    if (!tc || ![tc instancesRespondToSelector:NSSelectorFromString(@"initWithDelegate:edge:type:windowScene:")]) return NO;
    static const char *needed[] = { "_liveWindowResizeGestureRecognizer", "_hoverGestureRecognizer", "_indirectRevealContinuousExposeStripsGestureRecognizer",
                                    "_indirectRevealContinuousExposeStripOverflowGestureRecognizer", "_dragRevealContinuousExposeStripOverflowGestureRecognizer" };
    for (size_t i = 0; i < sizeof needed / sizeof needed[0]; i++) if (!class_getInstanceVariable(object_getClass(gm), needed[i])) return NO;
    return YES;
}

static BOOL G1D_FloatEqual(double a, double b) {
    static BOOL (*fn)(double, double); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (BOOL (*)(double, double))dlsym(RTLD_DEFAULT, "BSFloatEqualToFloat"); });
    return fn ? fn(a, b) : fabs(a - b) < 0.0000001;
}
static BOOL G1D_FloatIsZero(double a) {
    static BOOL (*fn)(double); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (BOOL (*)(double))dlsym(RTLD_DEFAULT, "BSFloatIsZero"); });
    return fn ? fn(a) : fabs(a) < 0.0000001;
}

// ---- availability (16.2 0x1c78fba84 / 0x1c78fbc38). The reason strings are logged only.
static BOOL G1D_StripsAvailable(id gm, NSString **reason) {
    id sc = G1D_GM_SC(gm);
    id state = G1B_Send0(gm, NSSelectorFromString(@"_currentLayoutState"));
    SEL chamois = NSSelectorFromString(@"isChamoisWindowingUIEnabled");
    NSString *r = @"Available"; BOOL ok = YES;
    if (!G1B_SendB0(sc, chamois)) { ok = NO; r = @"FeatureNotEnabled"; }
    else if (G1B_SendLL0(state, NSSelectorFromString(@"unlockedEnvironmentMode")) != 3) { ok = NO; r = @"NotInApplication"; }
    else if (G1B_SendB0(state, NSSelectorFromString(@"isFloatingSwitcherVisible"))) { ok = NO; r = @"FloatingSwitcherVisible"; }
    else {
        id participant = G1D_IvarObj(gm, "_zStackParticipant");
        if (participant && G1B_SendLL0(participant, NSSelectorFromString(@"activationState")) != 0) { ok = NO; r = @"NotForegroundActiveInZStack"; }
        else if (!G1B_SendB0(sc, chamois)) { ok = NO; r = @"ChamoisNotEnabled"; }
        else {
            id layout = G1B_Send0(state, NSSelectorFromString(@"appLayout"));
            SEL ifr = NSSelectorFromString(@"itemForLayoutRole:");
            id item = [layout respondsToSelector:ifr] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(layout, ifr, 1) : nil;     // _SBLayoutRolePrimary
            NSString *bundle = G1B_Send0(item, NSSelectorFromString(@"bundleIdentifier"));
            Class ac = NSClassFromString(@"SBApplicationController");
            id app = bundle ? G1B_Send1(G1B_Send0((id)ac, NSSelectorFromString(@"sharedInstance")), NSSelectorFromString(@"applicationWithBundleIdentifier:"), bundle) : nil;
            if (app && G1B_SendB0(app, NSSelectorFromString(@"alwaysMaximizedInChamois"))) { ok = NO; r = @"ApplicationAlwaysMaximized"; }
        }
    }
    if (reason) *reason = r;
    return ok;
}

static BOOL G1D_StripsOccludedOrHidden(id gm, NSString **reason) {
    id sc = G1D_GM_SC(gm), vc = G1D_GM_VC(gm);
    NSString *r; BOOL result;
    if (!G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"))) { r = @"FeatureNotEnabled"; result = NO; }
    else if (G1B_SendB0(vc, NSSelectorFromString(@"_areContinuousExposeStripsUnoccluded"))) { r = @"StripsManuallyUnoccluded"; result = NO; }
    else if (G1B_SendB0(vc, NSSelectorFromString(@"prefersStripHidden"))) { r = @"PrefersStripHidden"; result = YES; }
    else {
        id state = G1B_Send0(gm, NSSelectorFromString(@"_currentLayoutState"));
        id layout = G1B_Send0(state, NSSelectorFromString(@"appLayout"));
        id view = G1B_Send0(vc, NSSelectorFromString(@"view"));
        CGRect bounds = [view respondsToSelector:@selector(bounds)] ? ((CGRect (*)(id, SEL))objc_msgSend)(view, @selector(bounds)) : CGRectZero;
        id cla = G1B_Send0(vc, NSSelectorFromString(@"chamoisLayoutAttributes"));
        id ws = G1B_Send0(sc, NSSelectorFromString(@"windowScene"));
        long long orientation = G1B_SendLL0(state, NSSelectorFromString(@"interfaceOrientation"));
        id calc = G1D_IvarObj(gm, "_displayItemLayoutAttributesCalculator");
        id dock = G1B_Send0(ws, NSSelectorFromString(@"floatingDockController"));
        double dockHeight = G1B_Dbl0(dock, NSSelectorFromString(@"floatingDockHeight"));
        double scale = G1B_Dbl0(G1B_Send0(ws, NSSelectorFromString(@"screen")), NSSelectorFromString(@"scale"));
        BOOL hideStrip = G1B_SendB0(vc, NSSelectorFromString(@"prefersStripHidden")), hideDock = G1B_SendB0(vc, NSSelectorFromString(@"prefersDockHidden"));
        SEL om = NSSelectorFromString(@"overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:");
        id model = (calc && [calc respondsToSelector:om])
            ? ((id (*)(id, SEL, id, long long, id, double, double, CGRect, BOOL, BOOL))objc_msgSend)(calc, om, layout, orientation, cla, dockHeight, scale, bounds, hideStrip, hideDock) : nil;
        result = !G1B_SendB0(model, NSSelectorFromString(@"isContinuousExposeStripVisible"));
        r = @"AnyItemExceedStrip";
    }
    if (reason) *reason = r;
    return result;
}

// 16.2 0x1c78f95c4: begin when the strips are available AND occluded or hidden (the reveal gesture brings them back)
static BOOL G1D_ShouldBeginStripReveal(id gm, id gr) {
    NSString *r = nil;
    if (!G1D_StripsAvailable(gm, &r)) { if (BP_LogEnabled()) BP_Log(@"g1d: Won't begin strip reveal gesture: %@", r); return NO; }
    NSString *r2 = nil;
    BOOL hidden = G1D_StripsOccludedOrHidden(gm, &r2);
    if (BP_LogEnabled()) BP_Log(@"g1d: %s begin strip reveal gesture: occludedOrHidden=%d (%@)", hidden ? "Will" : "Won't", hidden, r2);
    return hidden;
}
// 16.2 0x1c78f9738: the overflow gestures begin when the strips are available and NOT occluded or hidden
static BOOL G1D_ShouldBeginStripOverflow(id gm, id gr) {
    NSString *r = nil;
    if (!G1D_StripsAvailable(gm, &r)) { if (BP_LogEnabled()) BP_Log(@"g1d: Won't begin strip overflow gesture: %@", r); return NO; }
    NSString *r2 = nil;
    BOOL hidden = G1D_StripsOccludedOrHidden(gm, &r2);
    if (BP_LogEnabled()) BP_Log(@"g1d: %s begin strip overflow gesture: occludedOrHidden=%d (%@)", hidden ? "Won't" : "Will", hidden, r2);
    return !hidden;
}

// _SBPeekConfigurationIsValid(NSInteger) is byte-identical in 16.0 (0x1c6289f84) and 16.2 (0x1c77229fc): (configuration & ~1) == 2. The private symbol is not exported, so
// it is re-implemented. SBMainDisplayLayoutStateFloatingConfigurationIsStashed (16.2 0x1c7722a84, 16.0 0x1c628a00c) is (configuration - 3) < 2.
static BOOL G1D_PeekValid(long long configuration) { return (configuration & ~1LL) == 2; }
static BOOL G1D_FloatingConfigurationIsStashed(long long configuration) { return (unsigned long long)(configuration - 3) < 2; }

// UIKit's _UISystemGestureLocationForTouchInView(gestureRecognizer, touch, view) (16.0 and 16.2 call it the same way)
static CGPoint G1D_SystemGestureLocation(id gr, id touch, id view) {
    static CGPoint (*fn)(id, id, id); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (CGPoint (*)(id, id, id))dlsym(RTLD_DEFAULT, "_UISystemGestureLocationForTouchInView"); });
    if (fn) return fn(gr, touch, view);
    return [touch respondsToSelector:@selector(locationInView:)] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(touch, @selector(locationInView:), view) : CGPointZero;
}

// 16.2 0x1c78f5ef0: the drag overflow recognizer takes the touch of ITS display (16.0 asked the main display gesture manager and the main window scene's layout attributes)
static BOOL G1D_StripOverflowReceiveTouch(id gm, id gr, id touch) {
    id sc = G1D_GM_SC(gm);
    CGPoint loc = [touch respondsToSelector:@selector(locationInView:)] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(touch, @selector(locationInView:), nil) : CGPointZero;
    id ws = G1B_Send0(sc, NSSelectorFromString(@"windowScene"));
    id sgm = G1B_Send0(ws, NSSelectorFromString(@"systemGestureManager"));
    SEL recv = NSSelectorFromString(@"shouldSystemGestureReceiveTouchWithLocation:"), allowed = NSSelectorFromString(@"isGestureWithTypeAllowed:");
    BOOL sgReceives = [sgm respondsToSelector:recv] ? ((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(sgm, recv, loc) : NO;
    BOOL sgAllowed = [sgm respondsToSelector:allowed] ? ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(sgm, allowed, 0x36) : NO;
    id state = G1B_Send0(gm, NSSelectorFromString(@"_currentLayoutState"));
    long long env = G1B_SendLL0(state, NSSelectorFromString(@"unlockedEnvironmentMode"));
    long long peek = G1B_SendLL0(state, NSSelectorFromString(@"peekConfiguration"));        // an NSInteger, not an object
    BOOL chamois = G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"));
    if (!(chamois && sgReceives && sgAllowed && env == 3)) return NO;
    if (G1D_PeekValid(peek)) return NO;
    id vc = G1D_GM_VC(gm);
    id view = G1B_Send0(vc, NSSelectorFromString(@"view"));
    CGPoint pt = G1D_SystemGestureLocation(gr, touch, view);
    double stripWidth = G1B_Dbl0(G1B_Send0(vc, NSSelectorFromString(@"chamoisLayoutAttributes")), NSSelectorFromString(@"stripWidth"));
    if ([[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft) {
        CGRect fr = ((CGRect (*)(id, SEL))objc_msgSend)(view, @selector(frame));
        if (pt.x < CGRectGetMaxX(fr) - stripWidth) return NO;
    } else if (pt.x > stripWidth) return NO;
    SEL ica = NSSelectorFromString(@"_itemContainerAtLocation:environment:");
    id hit = [vc respondsToSelector:ica] ? ((id (*)(id, SEL, CGPoint, long long))objc_msgSend)(vc, ica, pt, 0) : nil;
    return hit == nil;
}

// 16.2 0x1c78f9a5c -_shouldProtectEdgeLocation:edge:
static BOOL G1D_ShouldProtectEdge(id gm, double loc, unsigned long long edge) {
    if (G1B_SendB0(gm, NSSelectorFromString(@"_shouldSuppressEdgeProtect"))) return NO;
    // -[SBFHomeGrabberSettings edgeProtectOverride] returns a BSSettingFlag (long long, NOT an object): 16.2 passes x0 straight to BSSettingFlagIsYes / BSSettingFlagIsExplicitNo (0x1c78f9a8c-0x1c78f9aa8).
    static BOOL (*isYes)(long long), (*isExplicitNo)(long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ isYes = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "BSSettingFlagIsYes"); isExplicitNo = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "BSSettingFlagIsExplicitNo");
        if ((!isYes || !isExplicitNo) && BP_LogEnabled()) BP_Log(@"g1d: BSSettingFlagIsYes/IsExplicitNo not exported (%p %p): edgeProtectOverride is ignored", isYes, isExplicitNo); });
    long long flag = G1B_SendLL0(G1D_IvarObj(gm, "_homeGrabberSettings"), NSSelectorFromString(@"edgeProtectOverride"));
    if (isYes && isYes(flag)) return YES;
    if (isExplicitNo && isExplicitNo(flag)) return NO;
    id vc = G1D_GM_VC(gm);
    SEL s = NSSelectorFromString(@"isEdgeProtectedForHomeGestureAtEdgeLocation:edge:");
    return [vc respondsToSelector:s] ? ((BOOL (*)(id, SEL, double, unsigned long long))objc_msgSend)(vc, s, loc, edge) : NO;
}

// 16.2 -grabberTongue:shouldShowTongueOnFirstSwipeWithEdgeLocation: strip branch (0x1c72c91c0): the first swipe on the strip edge shows the tongue (instead of revealing the
// strip) when a window touches the strip edge and its app defers system gestures on that edge.
static BOOL G1D_StripFirstSwipe(id gm) {
    id vc = G1D_GM_VC(gm);
    unsigned long long edge = G1D_StripEdge();
    id state = G1B_Send0(gm, NSSelectorFromString(@"_currentLayoutState"));
    id layout = G1B_Send0(state, NSSelectorFromString(@"appLayout"));
    id containers = G1B_Send0(vc, NSSelectorFromString(@"visibleItemContainers"));
    id view = G1B_Send0(vc, NSSelectorFromString(@"view"));
    SEL ifr = NSSelectorFromString(@"itemForLayoutRole:");
    id found = nil;
    for (id leaf in (G1B_Send0(layout, NSSelectorFromString(@"leafAppLayouts")) ?: @[])) {
        id container = G1B_Send1(containers, NSSelectorFromString(@"objectForKey:"), leaf);
        CGRect f = [container respondsToSelector:@selector(frame)] ? ((CGRect (*)(id, SEL))objc_msgSend)(container, @selector(frame)) : CGRectZero;
        if (edge == 8) {
            CGRect vf = ((CGRect (*)(id, SEL))objc_msgSend)(view, @selector(frame));
            if (G1D_FloatEqual(f.origin.x + f.size.width, vf.origin.x + vf.size.width)) { found = leaf; break; }
        } else if (edge == 2) {
            if (G1D_FloatIsZero(f.origin.x)) { found = leaf; break; }
        }
    }
    if (!found) return NO;
    id item = [found respondsToSelector:ifr] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(found, ifr, 1) : nil;
    SEL lri = NSSelectorFromString(@"layoutRoleForItem:");
    long long role = [layout respondsToSelector:lri] ? ((long long (*)(id, SEL, id))objc_msgSend)(layout, lri, item) : 0;
    SEL ewr = NSSelectorFromString(@"elementWithRole:");
    id element = [state respondsToSelector:ewr] ? ((id (*)(id, SEL, long long))objc_msgSend)(state, ewr, role) : nil;
    id entity = G1B_Send0(element, NSSelectorFromString(@"workspaceEntity"));
    id deviceEntity = G1B_Send0(entity, NSSelectorFromString(@"deviceApplicationSceneEntity"));
    if (!deviceEntity) return NO;
    id handle = G1B_Send0(deviceEntity, NSSelectorFromString(@"sceneHandle"));
    unsigned long long edges = (unsigned long long)G1B_SendLL0(handle, NSSelectorFromString(@"screenEdgesDeferringSystemGestures"));
    return (edge & edges) != 0;
}

// ---- recognizers owned by the strip tongue
static id G1D_MakeStripEdgePan(id gm) {
    Class c = NSClassFromString(@"SBScreenEdgePanGestureRecognizer");
    SEL ini = NSSelectorFromString(@"initWithTarget:action:");
    if (!c || ![c instancesRespondToSelector:ini]) return nil;
    id gr = ((id (*)(id, SEL, id, SEL))objc_msgSend)([c alloc], ini, nil, NULL);
    G1B_SendVLL(gr, NSSelectorFromString(@"setEdges:"), (long long)G1D_StripEdge());
    G1B_SendV1(gr, NSSelectorFromString(@"setAllowedTouchTypes:"), @[ @0 ]);                 // UITouchTypeDirect (constant array 0x1e18f86e8)
    G1B_SendV1(gr, NSSelectorFromString(@"setName:"), @"revealContinuousExposeStripsGestureRecognizer");
    return gr;
}
static id G1D_MakeStripIndirectPan(id gm) {
    Class c = NSClassFromString(@"SBIndirectPanGestureRecognizer");
    if (!c) return nil;
    SEL act = NSSelectorFromString(@"_handleContinuousExposeStripRevealGesture:");
    SEL i3 = NSSelectorFromString(@"initWithTarget:action:edges:"), i4 = NSSelectorFromString(@"initWithTarget:action:edges:systemGestureManager:");
    unsigned long long edge = G1D_StripEdge();
    id gr = nil;
    if ([c instancesRespondToSelector:i3]) gr = ((id (*)(id, SEL, id, SEL, unsigned long long))objc_msgSend)([c alloc], i3, gm, act, edge);
    else if ([c instancesRespondToSelector:i4]) {                            // 16.0 has only the long form (the old reveal recognizer was created with the scene's system gesture manager)
        id sgm = G1B_Send0(G1D_GM_Scene(gm), NSSelectorFromString(@"systemGestureManager"));
        gr = ((id (*)(id, SEL, id, SEL, unsigned long long, id))objc_msgSend)([c alloc], i4, gm, act, edge, sgm);
    }
    if (!gr) return nil;
    G1B_SendV1(gr, NSSelectorFromString(@"setName:"), @"indirectRevealContinuousExposeStripsGestureRecognizer");
    G1B_SendV1(gr, NSSelectorFromString(@"setDelegate:"), gm);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(gr, NSSelectorFromString(@"setShouldRequireGestureToStartAtEdge:"), YES);
    SEL hy = NSSelectorFromString(@"setHysteresis:forInputType:");
    if ([gr respondsToSelector:hy]) {
        ((void (*)(id, SEL, double, long long))objc_msgSend)(gr, hy, 30.0, 0);
        ((void (*)(id, SEL, double, long long))objc_msgSend)(gr, hy, 10.0, 1);
    }
    // translation adjustment block 0x1c78faca0 (same body as the 16.0 block of the old reveal recognizer 0x1c643f2d0)
    __weak id weakVC = G1D_GM_VC(gm);
    CGPoint (^adjust)(unsigned long long, CGPoint, CGPoint, CGPoint) = ^CGPoint(unsigned long long edgeArg, CGPoint t, CGPoint unused, CGPoint location) {
        id vc = weakVC;
        if (!vc) return t;
        id view = G1B_Send0(vc, NSSelectorFromString(@"view"));
        CGRect b = [view respondsToSelector:@selector(bounds)] ? ((CGRect (*)(id, SEL))objc_msgSend)(view, @selector(bounds)) : CGRectZero;
        double v = t.x - fabs(t.y);
        double x = (location.x >= b.size.width * 0.5) ? fmax(v, 0.0) : fmin(v, 0.0);
        return CGPointMake(x, t.y);
    };
    G1B_SendV1(gr, NSSelectorFromString(@"setTranslationAdjustmentBlock:"), (id)adjust);
    return gr;
}

// ---- 16.2 -_configureChamoisGestureRecognizersIfNeeded / -updateForChamoisWindowingUIEnabled: (the 16.0 versions create/register the same recognizers except the reveal one)
static void G1D_ConfigureStripTongue(id gm) {
    G1B_SendV1(gm, NSSelectorFromString(@"setIndirectRevealContinuousExposeStripsGestureRecognizer:"), nil);     // 16.0's reveal recognizer: never registered, the tongue's own ones replace it
    Class tc = NSClassFromString(@"SBGrabberTongue");
    SEL ini = NSSelectorFromString(@"initWithDelegate:edge:type:windowScene:");
    id tongue = ((id (*)(id, SEL, id, unsigned long long, unsigned long long, id))objc_msgSend)([tc alloc], ini, gm, G1D_StripEdge(), G1DStripTongueGestureType, G1D_GM_Scene(gm));
    G1B_SendV1(tongue, NSSelectorFromString(@"setName:"), @"ContinuousExposeStripRevealGrabberTongue");
    G1D_SetStripTongue(gm, tongue);
}

static void G1D_GM_Update(id gm, BOOL enabled) {
    id sc = G1D_GM_SC(gm);
    id sgm = G1B_Send0(G1D_GM_Scene(gm), NSSelectorFromString(@"systemGestureManager"));
    id live = G1D_IvarObj(gm, "_liveWindowResizeGestureRecognizer");
    id liveView = G1B_Send0(live, NSSelectorFromString(@"view"));
    SEL add = NSSelectorFromString(@"addGestureRecognizer:withType:"), rem = NSSelectorFromString(@"removeGestureRecognizer:");
    id hover = G1D_IvarObj(gm, "_hoverGestureRecognizer"), overflow = G1D_IvarObj(gm, "_indirectRevealContinuousExposeStripOverflowGestureRecognizer");
    id drag = G1D_IvarObj(gm, "_dragRevealContinuousExposeStripOverflowGestureRecognizer");
    if (enabled) {
        if (liveView) return;
        G1B_SendV0(gm, NSSelectorFromString(@"_configureChamoisGestureRecognizersIfNeeded"));
        live = G1D_IvarObj(gm, "_liveWindowResizeGestureRecognizer"); hover = G1D_IvarObj(gm, "_hoverGestureRecognizer");
        overflow = G1D_IvarObj(gm, "_indirectRevealContinuousExposeStripOverflowGestureRecognizer"); drag = G1D_IvarObj(gm, "_dragRevealContinuousExposeStripOverflowGestureRecognizer");
        void (^reg)(id, unsigned long long) = ^(id gr, unsigned long long type) {
            if (gr && [sgm respondsToSelector:add]) ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(sgm, add, gr, type);
        };
        reg(live, 0x22); reg(hover, 0x33); reg(overflow, 0x35); reg(drag, 0x36);
        id tongue = G1D_StripTongue(gm);
        id vc = G1D_GM_VC(gm);
        SEL inst = NSSelectorFromString(@"installInView:withColorStyle:");
        if ([tongue respondsToSelector:inst]) ((void (*)(id, SEL, id, long long))objc_msgSend)(tongue, inst, G1B_Send0(vc, NSSelectorFromString(@"view")), 0);
        id indirect = G1B_Send0(tongue, NSSelectorFromString(@"indirectEdgePullGestureRecognizer"));
        if (overflow && indirect) G1B_SendV1(overflow, NSSelectorFromString(@"requireGestureRecognizerToFail:"), indirect);
    } else if (liveView) {
        void (^unreg)(id) = ^(id gr) { if (gr && [sgm respondsToSelector:rem]) ((void (*)(id, SEL, id))objc_msgSend)(sgm, rem, gr); };
        if (!G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"))) unreg(live);
        unreg(hover); unreg(overflow); unreg(drag);
        G1B_SendV0(G1D_StripTongue(gm), NSSelectorFromString(@"uninstall"));
    }
}

// ---- view controller side
static void G1D_VC_StripTongueEvent(id vc, BOOL presented) {          // 16.2 0x1c744f4e0 / 0x1c744f540
    Class c = NSClassFromString(@"SBContinuousExposeStripEdgeProtectTongueSwitcherModifierEvent");
    SEL ini = NSSelectorFromString(@"initWithTonguePresented:");
    if (!c || ![c instancesRespondToSelector:ini]) return;
    id ev = ((id (*)(id, SEL, BOOL))objc_msgSend)([c alloc], ini, presented);
    G1B_SendV1(vc, NSSelectorFromString(@"_dispatchEventAndHandleAction:"), ev);
}

// 16.2 -[SBFluidSwitcherViewController isEdgeProtectedForHomeGestureAtEdgeLocation:edge:] 0x1c744c954. 16.0 (0x1c5fd3a74) only asked: does any visible container span the
// location along the bottom edge and does its app protect the edge. 16.2 skips containers that are occluded in the stage, requires the container to touch the asked edge
// of the container view and handles all four edges (location runs along the edge: x for top/bottom, y for left/right).
static BOOL G1D_VC_IsEdgeProtected(id vc, double loc, unsigned long long edge) {
    id ds = G1B_Send0(vc, NSSelectorFromString(@"dataSource"));
    SEL kb = NSSelectorFromString(@"switcherContentControllerIsKeyboardHomeAffordanceAssertionCurrentlyBeingTaken:");
    if ([ds respondsToSelector:kb] && ((BOOL (*)(id, SEL, id))objc_msgSend)(ds, kb, vc)) return NO;
    SEL cvb = NSSelectorFromString(@"containerViewBounds");
    CGRect bounds = [vc respondsToSelector:cvb] ? ((CGRect (*)(id, SEL))objc_msgSend)(vc, cvb) : CGRectZero;
    id containers = G1D_IvarObj(vc, "_visibleItemContainers");
    SEL handleSel = NSSelectorFromString(@"switcherContentController:deviceApplicationSceneHandleForDisplayItem:");
    SEL occl = NSSelectorFromString(@"isOccludedInContinuousExposeStage");
    for (id key in [containers respondsToSelector:@selector(keyEnumerator)] ? [[containers keyEnumerator] allObjects] : @[]) {
        id container = G1B_Send1(containers, NSSelectorFromString(@"objectForKey:"), key);
        if (G1B_SendB0(container, occl)) continue;
        CGRect f = [container respondsToSelector:@selector(frame)] ? ((CGRect (*)(id, SEL))objc_msgSend)(container, @selector(frame)) : CGRectZero;
        BOOL touchesEdge; double along;
        switch (edge) {
            case 1:  if (CGRectGetMinX(f) > loc) continue; touchesEdge = CGRectGetMinY(f) <= CGRectGetMinY(bounds); along = CGRectGetMaxX(f); break;
            case 2:  if (CGRectGetMinY(f) > loc) continue; touchesEdge = CGRectGetMinX(f) <= CGRectGetMinX(bounds); along = CGRectGetMaxY(f); break;
            case 4:  if (CGRectGetMinX(f) > loc) continue; touchesEdge = CGRectGetMaxY(f) >= CGRectGetMaxY(bounds); along = CGRectGetMaxX(f); break;
            case 8:  if (CGRectGetMinY(f) > loc) continue; touchesEdge = CGRectGetMaxX(f) >= CGRectGetMaxX(bounds); along = CGRectGetMaxY(f); break;
            default: continue;
        }
        if (!touchesEdge || along < loc) continue;
        if (![ds respondsToSelector:handleSel]) continue;
        SEL ifr = NSSelectorFromString(@"itemForLayoutRole:");
        id item = [key respondsToSelector:ifr] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(key, ifr, 1) : nil;
        id handle = ((id (*)(id, SEL, id, id))objc_msgSend)(ds, handleSel, vc, item);
        return G1B_SendB0(handle, NSSelectorFromString(@"isEdgeProtectEnabledForHomeGesture"));
    }
    return NO;
}

// SBGrabberTongue: 16.2 adds the `name` and `screenEdge` accessors (0x1c784ccf8 / 0x1c784cd00 / 0x1c784cd08); the ivars exist (screenEdge) or are kept as associated state (name)
%group G1D_Tongue
%hook SBGrabberTongue
%new
- (unsigned long long)screenEdge { return G1D_IvarULL(self, "_screenEdge"); }
%new
- (id)name { return objc_getAssociatedObject(self, &kG1DTongueName); }
%new
- (void)setName:(id)name { objc_setAssociatedObject(self, &kG1DTongueName, [name copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
%end

%hook SBFluidSwitcherGestureManager
- (void)_configureChamoisGestureRecognizersIfNeeded {
    BOOL first = G1D_TongueUsable(self) && G1D_IvarObj(self, "_liveWindowResizeGestureRecognizer") == nil;       // the 16.0 body returns at once when it exists
    %orig;
    if (first) G1D_ConfigureStripTongue(self);
}
- (void)invalidate {
    %orig;
    id t = G1D_TongueOn() ? G1D_StripTongue(self) : nil;
    G1B_SendV0(t, NSSelectorFromString(@"invalidate"));                       // 16.2 0x1c78f179c
}

// 16.2 0x1c78f27e8: the strip reveal gesture action (touch pull, pointer pull)
%new
- (void)_handleContinuousExposeStripRevealGesture:(id)gesture {
    id tongue = ((id (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"_grabberTongueForGestureRecognizer:"), gesture);
    SEL dis = NSSelectorFromString(@"dismissWithStyle:animated:");
    if ([tongue respondsToSelector:dis]) ((BOOL (*)(id, SEL, long long, BOOL))objc_msgSend)(tongue, dis, 0, YES);
    G1B_SendV1(self, NSSelectorFromString(@"_handleFluidGesture:"), gesture);
}

// overflow gestures: availability / touch rules of 16.2 (the 16.0 versions miss the `hidden` half and use the main display)
- (BOOL)_shouldBeginRevealContinuousExposeStripOverflowGesture:(id)gesture {
    if (G1D_TongueUsable(self)) return G1D_ShouldBeginStripOverflow(self, gesture);
    return %orig;
}
- (BOOL)_shouldRevealContinuousExposeStripOverflowPanGesture:(id)gesture receiveTouch:(id)touch {
    if (G1D_TongueUsable(self)) return G1D_StripOverflowReceiveTouch(self, gesture, touch);
    return %orig;
}

// tongue delegate
- (id)customGestureRecognizerForGrabberTongue:(id)tongue {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) return G1D_MakeStripEdgePan(self);
    return %orig;
}
- (id)indirectPanGestureRecognizerForGrabberTongue:(id)tongue {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) return G1D_MakeStripIndirectPan(self);
    return %orig;
}
- (unsigned long long)indirectPanSystemGestureTypeForGrabberTongue:(id)tongue {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) return G1DStripIndirectGestureType;
    return %orig;
}
- (BOOL)shouldSuppressTongueViewForGrabberTongue:(id)tongue {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) return YES;                   // the view controller hosts the strip tongue view
    return %orig;
}
- (BOOL)grabberTongueOrPullEnabled:(id)tongue forGestureRecognizer:(id)gesture {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) return G1D_ShouldBeginStripReveal(self, gesture);
    return %orig;
}
- (id)_grabberTongueForGestureRecognizer:(id)gesture {
    id r = %orig;
    if (r || !gesture || !G1D_TongueOn()) return r;
    id t = G1D_StripTongue(self);
    if (t && (gesture == G1B_Send0(t, NSSelectorFromString(@"edgePullGestureRecognizer")) || gesture == G1B_Send0(t, NSSelectorFromString(@"indirectEdgePullGestureRecognizer")))) return t;
    return r;
}
- (unsigned long long)_gestureTypeForGestureRecognizer:(id)gesture {
    if (gesture && G1D_TongueOn()) {                                                      // an unknown recognizer would hit the 16.0 NSAssert; both tongue recognizers are strip reveal (0xb)
        id t = G1D_StripTongue(self);
        if (t && (gesture == G1B_Send0(t, NSSelectorFromString(@"edgePullGestureRecognizer")) || gesture == G1B_Send0(t, NSSelectorFromString(@"indirectEdgePullGestureRecognizer"))))
            return G1DStripRevealFluidGestureType;
    }
    return %orig;
}
- (BOOL)grabberTongue:(id)tongue shouldReceiveTouch:(id)touch {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) {
        if (!G1B_SendB0(G1D_IvarObj(self, "_zStackParticipant"), NSSelectorFromString(@"ownsHomeGesture"))) return NO;
        if (G1B_SendLL0(G1B_Send0(self, NSSelectorFromString(@"_currentLayoutState")), NSSelectorFromString(@"unlockedEnvironmentMode")) != 3) return NO;
        if (!G1B_SendB0(tongue, NSSelectorFromString(@"isVisible"))) return YES;
        SEL el = NSSelectorFromString(@"edgeLocationForTouch:"), rg = NSSelectorFromString(@"isEdgeLocationInGrabberRegion:");
        double loc = [tongue respondsToSelector:el] ? ((double (*)(id, SEL, id))objc_msgSend)(tongue, el, touch) : 0.0;
        return [tongue respondsToSelector:rg] ? ((BOOL (*)(id, SEL, double))objc_msgSend)(tongue, rg, loc) : YES;
    }
    return %orig;
}
- (BOOL)grabberTongue:(id)tongue shouldShowTongueOnFirstSwipeWithEdgeLocation:(double)location {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) return G1D_StripFirstSwipe(self);
    return %orig;
}
- (BOOL)grabberTongue:(id)tongue shouldAllowSecondSwipeWithEdgeLocation:(double)location {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) {
        unsigned long long edge = (unsigned long long)G1B_SendLL0(tongue, NSSelectorFromString(@"screenEdge"));
        if (!G1D_ShouldProtectEdge(self, location, edge)) return YES;
        SEL rg = NSSelectorFromString(@"isEdgeLocationInGrabberRegion:");
        return [tongue respondsToSelector:rg] ? ((BOOL (*)(id, SEL, double))objc_msgSend)(tongue, rg, location) : YES;
    }
    return %orig;
}
// the pulls of the strip tongue's touch recognizer are strip reveal gestures
- (void)grabberTongueBeganPulling:(id)tongue withDistance:(double)distance andVelocity:(double)velocity andGesture:(id)gesture {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) { ((void (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"_handleContinuousExposeStripRevealGesture:"), G1B_Send0(tongue, NSSelectorFromString(@"edgePullGestureRecognizer"))); return; }
    %orig;
}
- (void)grabberTongueUpdatedPulling:(id)tongue withDistance:(double)distance andVelocity:(double)velocity andGesture:(id)gesture {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) { ((void (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"_handleContinuousExposeStripRevealGesture:"), G1B_Send0(tongue, NSSelectorFromString(@"edgePullGestureRecognizer"))); return; }
    %orig;
}
- (void)grabberTongueEndedPulling:(id)tongue withDistance:(double)distance andVelocity:(double)velocity andGesture:(id)gesture {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) { ((void (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"_handleContinuousExposeStripRevealGesture:"), G1B_Send0(tongue, NSSelectorFromString(@"edgePullGestureRecognizer"))); return; }
    %orig;
}
- (void)grabberTongueCanceledPulling:(id)tongue withDistance:(double)distance andVelocity:(double)velocity andGesture:(id)gesture {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) { ((void (*)(id, SEL, id))objc_msgSend)(self, NSSelectorFromString(@"_handleContinuousExposeStripRevealGesture:"), G1B_Send0(tongue, NSSelectorFromString(@"edgePullGestureRecognizer"))); return; }
    %orig;
}
- (void)grabberTongueWillPresent:(id)tongue {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) { G1B_SendV0(G1D_GM_VC(self), NSSelectorFromString(@"presentContinuousExposeStripEdgeProtectTongue")); return; }
    %orig;
}
- (void)grabberTongueWillDismiss:(id)tongue {
    if (G1D_TongueOn() && G1D_IsStripTongue(self, tongue)) { G1B_SendV0(G1D_GM_VC(self), NSSelectorFromString(@"dismissContinuousExposeStripEdgeProtectTongue")); return; }
    %orig;
}
%end

// the system gesture type of the strip tongue's touch recognizer is enabled on the main display like the hover gesture (16.2: same case of the jump table, 0x1c72e9590)
%hook SBMainDisplaySystemGestureManager
- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
    if (type == G1DStripTongueGestureType && G1D_TongueOn()) return %orig(0x33);
    return %orig;
}
%end

// -[SBExternalDisplaySystemGestureManager _shouldEnableSystemGestureWithType:] 16.2 0x1c780bf58 (16.0 0x1c6365c28): the set of types the external display arms also holds
// 0x1e / 0x1f / 0x20 / 0x21 (the SBTransientUIInteractionManager tap to dismiss, indirect pan to dismiss and tap to unhide gestures, registered at 0x1c74f7414 / 0x1c74f77e8 /
// 0x1c74f75b8 / 0x1c74f764c) and 0x43 (external display cover sheet / lock screen, = 16.0 0x42, handled by the wake gesture code in Tweak.x). The 16.2 table is the 16.0
// one plus these; every type below 0x37 keeps its number.
%hook SBExternalDisplaySystemGestureManager
- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
    if (type >= 0x1e && type <= 0x21 && G1D_ON("g1d_extgestures")) return YES;
    return %orig;
}
%end

// view controller side of the strip edge protect tongue and the edge-aware home gesture protection
%hook SBFluidSwitcherViewController
%new
- (void)presentContinuousExposeStripEdgeProtectTongue { G1D_VC_StripTongueEvent(self, YES); }
%new
- (void)dismissContinuousExposeStripEdgeProtectTongue { G1D_VC_StripTongueEvent(self, NO); }
%new
- (BOOL)isEdgeProtectedForHomeGestureAtEdgeLocation:(double)location edge:(unsigned long long)edge { return G1D_VC_IsEdgeProtected(self, location, edge); }
- (BOOL)isEdgeProtectedForHomeGestureAtEdgeLocation:(double)location {
    if (G1D_TongueOn()) return G1D_VC_IsEdgeProtected(self, location, 4);              // 16.0's only callers ask for the bottom edge (UIRectEdgeBottom)
    return %orig;
}
%end
%end // G1D_Tongue


// ============================================================================================================
// 4b. SBFluidSwitcherGestureManager: touch rules that 16.0 evaluates against the MAIN display (SBMainDisplaySystemGestureManager / _SBIsMainDisplaySystemGestureAllowed)
// ============================================================================================================
// 16.2 asks the system gesture manager of the switcher's OWN window scene and the per-scene _SBIsSystemGestureAllowed(windowScene, type) (0x1c74d1424), so a pointer
// resize or a click on a window of the external display is no longer judged by the iPad's cover sheet / control center / alert state.
// Ported here: -_shouldLiveResizeGesture:receiveTouch: 0x1c78f5920 (16.0 0x1c6443518), -_shouldTapToBringItemContainerForward:receiveTouch: 0x1c78f5ac0 (0x1c6443604),
// -_shouldBeginTapToBringItemContainerForwardGesture: 0x1c78f7064 (0x1c644493c), -_handleTapToBringItemContainerForward: 0x1c78f2690 (0x1c6440998).
// Verified equivalent and left alone: -_shouldLiveResizeItemContainerGestureWithPointer:receiveTouch: (log only), ...WithTouch:receiveTouch: (16.0 asks the view controller's
// own window scene for the same layout attributes that 16.2 reads from -chamoisLayoutAttributes).
// Not ported (Medusa only, never active on an external display): the Slide Over move / pin gestures (spec 4.4). The Split View unpin pair is the Stage Manager window drag: section 4c.
static BOOL G1D_IsSystemGestureAllowed(id ws, unsigned long long type) {                // _SBIsSystemGestureAllowed(ws, type) 0x1c74d1424
    id sgm = G1B_Send0(ws, NSSelectorFromString(@"systemGestureManager"));
    SEL allowedSel = NSSelectorFromString(@"isGestureWithTypeAllowed:");
    BOOL allowed = [sgm respondsToSelector:allowedSel] ? ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(sgm, allowedSel, type) : NO;
    SEL vis = NSSelectorFromString(@"isVisible"), pres = NSSelectorFromString(@"isPresented"), wsSel = NSSelectorFromString(@"windowScene");
    id cs = G1B_Send0((id)NSClassFromString(@"SBCoverSheetPresentationManager"), NSSelectorFromString(@"sharedInstance"));
    BOOL coverSheet = [G1B_Send0(G1B_Send0(cs, NSSelectorFromString(@"coverSheetWindow")), wsSel) isEqual:ws] ? G1B_SendB0(cs, vis) : NO;
    id cc = G1B_Send0((id)NSClassFromString(@"SBControlCenterController"), NSSelectorFromString(@"sharedInstance"));
    BOOL controlCenter = [G1B_Send0(G1B_Send0(cc, NSSelectorFromString(@"_controlCenterWindow")), wsSel) isEqual:ws] ? G1B_SendB0(cc, pres) : NO;
    id wk = G1B_Send0((id)NSClassFromString(@"SBWorkspace"), NSSelectorFromString(@"mainWorkspace"));
    id tom = G1B_Send0(wk, NSSelectorFromString(@"transientOverlayPresentationManager"));
    SEL hap = NSSelectorFromString(@"hasActivePresentationForWindowScene:");
    BOOL transient = [tom respondsToSelector:hap] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(tom, hap, ws) : G1B_SendB0(tom, NSSelectorFromString(@"hasActivePresentation"));
    id alerts = G1B_Send0((id)NSClassFromString(@"SBAlertItemsController"), NSSelectorFromString(@"sharedInstance"));
    SEL hva = NSSelectorFromString(@"hasVisibleAlertForWindowScene:");
    BOOL alert = [alerts respondsToSelector:hva] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(alerts, hva, ws) : G1B_SendB0(alerts, NSSelectorFromString(@"hasVisibleModalAlert"));
    BOOL switcher = G1B_SendB0(G1B_Send0(ws, NSSelectorFromString(@"switcherController")), NSSelectorFromString(@"isAnySwitcherVisible"));
    id assistant = G1B_Send0((id)NSClassFromString(@"SBAssistantController"), NSSelectorFromString(@"sharedInstance"));
    SEL ivw = NSSelectorFromString(@"isVisibleInWindowScene:");
    BOOL assistantVisible = [assistant respondsToSelector:ivw] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(assistant, ivw, ws) : G1B_SendB0(assistant, vis);
    BOOL locked = G1B_SendB0(G1B_Send0((id)NSClassFromString(@"SBLockStateAggregator"), NSSelectorFromString(@"sharedInstance")), NSSelectorFromString(@"hasAnyLockState"));
    return allowed && !(coverSheet || controlCenter || transient || alert || switcher || assistantVisible || locked);
}
static BOOL G1D_GM_LocationReceivable(id gm, id touch, id *outScene, id *outSGM, CGPoint *outLoc) {
    id ws = G1D_GM_Scene(gm);
    id sgm = G1B_Send0(ws, NSSelectorFromString(@"systemGestureManager"));
    CGPoint loc = [touch respondsToSelector:@selector(locationInView:)] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(touch, @selector(locationInView:), nil) : CGPointZero;
    SEL recv = NSSelectorFromString(@"shouldSystemGestureReceiveTouchWithLocation:");
    if (outScene) *outScene = ws; if (outSGM) *outSGM = sgm; if (outLoc) *outLoc = loc;
    return [sgm respondsToSelector:recv] ? ((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(sgm, recv, loc) : NO;
}

%group G1D_GMTouch
%hook SBFluidSwitcherGestureManager
- (BOOL)_shouldLiveResizeGesture:(id)gesture receiveTouch:(id)touch {
    if (!G1D_ON("g1d_gmtouch")) return %orig;
    id sc = G1D_GM_SC(self);
    if (!G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"))) return NO;
    id ws = nil, sgm = nil;
    if (!G1D_GM_LocationReceivable(self, touch, &ws, &sgm, NULL)) return NO;
    SEL allowedSel = NSSelectorFromString(@"isGestureWithTypeAllowed:");
    if (![sgm respondsToSelector:allowedSel] || !((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(sgm, allowedSel, 0x22)) return NO;
    SEL ptr = NSSelectorFromString(@"_shouldLiveResizeItemContainerGestureWithPointer:receiveTouch:"), tch = NSSelectorFromString(@"_shouldLiveResizeItemContainerGestureWithTouch:receiveTouch:");
    if ([self respondsToSelector:ptr] && ((BOOL (*)(id, SEL, id, id))objc_msgSend)(self, ptr, gesture, touch)) return YES;
    return [self respondsToSelector:tch] ? ((BOOL (*)(id, SEL, id, id))objc_msgSend)(self, tch, gesture, touch) : NO;
}

- (BOOL)_shouldTapToBringItemContainerForward:(id)gesture receiveTouch:(id)touch {
    if (!G1D_ON("g1d_gmtouch")) return %orig;
    id sc = G1D_GM_SC(self), vc = G1D_GM_VC(self);
    if (!G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"))) return NO;
    BOOL receivable = G1D_GM_LocationReceivable(self, touch, NULL, NULL, NULL);
    CGPoint pt = G1D_SystemGestureLocation(gesture, touch, G1B_Send0(vc, NSSelectorFromString(@"view")));
    SEL ica = NSSelectorFromString(@"_itemContainerAtLocation:environment:");
    id container = [vc respondsToSelector:ica] ? ((id (*)(id, SEL, CGPoint, long long))objc_msgSend)(vc, ica, pt, 1) : nil;
    id state = G1B_Send0(self, NSSelectorFromString(@"_currentLayoutState"));
    id containerLayout = G1B_Send0(container, NSSelectorFromString(@"appLayout"));
    id adjusted = G1B_Send1(vc, NSSelectorFromString(@"adjustedAppLayoutForLeafAppLayout:"), containerLayout);
    SEL ifr = NSSelectorFromString(@"itemForLayoutRole:");
    id item = [containerLayout respondsToSelector:ifr] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(containerLayout, ifr, 1) : nil;
    id stateLayout = G1B_Send0(state, NSSelectorFromString(@"appLayout"));
    id top = [G1B_Send0(stateLayout, NSSelectorFromString(@"zOrderedItems")) firstObject];
    // 16.2 also refuses while a scene backed banner is presented (_presentedSceneBackedBanners count != 0): the banners are a 16.2 feature that does not exist in 16.0
    if (!container || item == top || !receivable) return NO;
    if (!G1B_SendB1(stateLayout, NSSelectorFromString(@"isOrContainsAppLayout:"), containerLayout)) return NO;
    id apps = G1B_Send0((id)NSClassFromString(@"SBApplicationController"), NSSelectorFromString(@"sharedInstance"));
    return G1B_SendB1(apps, NSSelectorFromString(@"_appLayoutContainsOnlyResizableApps:"), adjusted);
}

- (BOOL)_shouldBeginTapToBringItemContainerForwardGesture:(id)gesture {
    if (!G1D_ON("g1d_gmtouch")) return %orig;
    id sc = G1D_GM_SC(self);
    if (!G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"))) { if (BP_LogEnabled()) BP_Log(@"g1d: Won't begin tap to bring forward: ChamoisNotEnabled"); return NO; }
    id participant = G1D_IvarObj(self, "_zStackParticipant");
    if (participant && !G1B_SendB0(participant, NSSelectorFromString(@"ownsHomeGesture"))) return NO;
    id sgm = G1B_Send0(G1D_GM_Scene(self), NSSelectorFromString(@"systemGestureManager"));
    SEL allowedSel = NSSelectorFromString(@"isGestureWithTypeAllowed:");
    if (![sgm respondsToSelector:allowedSel] || !((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(sgm, allowedSel, 0x13)) return NO;
    id icons = G1B_Send0((id)NSClassFromString(@"SBIconController"), NSSelectorFromString(@"sharedInstance"));
    if (G1B_SendB0(icons, NSSelectorFromString(@"areAnyIconViewContextMenusShowing"))) return NO;       // 16.2 only: not while an icon context menu is up
    return G1B_SendLL0(G1B_Send0(self, NSSelectorFromString(@"_currentLayoutState")), NSSelectorFromString(@"unlockedEnvironmentMode")) == 3;
}

// 16.2 0x1c78f2690: a command-modified tap is no longer filtered out here (16.0 skipped the forward call when -tapWasCommandModified)
- (void)_handleTapToBringItemContainerForward:(id)gesture {
    if (!G1D_ON("g1d_gmtouch")) {
        %orig;
        return;
    }
    if (BP_LogEnabled()) BP_Log(@"g1d: tap to bring forward, command modified: %d", G1B_SendB0(gesture, NSSelectorFromString(@"tapWasCommandModified")));
    G1B_SendV1(G1D_GM_VC(self), NSSelectorFromString(@"handleTapToBringItemContainerForward:"), gesture);
}
%end
%end // G1D_GMTouch

// VC -handleTapToBringItemContainerForward: 16.2 0x1c7439690 (16.0 0x1c5fc0b10): the tap's modifier flags go to -didSelectContainer:modifierFlags: (shift-select of Stage Manager
// windows, G2B.m) and the explicit keyboard focus move of 16.0 is gone (the activating entity of the transition request takes the focus, see _configureRequest: above).
%group G1D_TapForward
%hook SBFluidSwitcherViewController
- (void)handleTapToBringItemContainerForward:(id)gesture {
    SEL didSelect = NSSelectorFromString(@"didSelectContainer:modifierFlags:");
    if (!G1D_ON("g1d_gmtouch") || ![self respondsToSelector:didSelect]) {
        %orig;
        return;
    }
    id contentView = G1D_IvarObj(self, "_contentView");
    CGPoint loc = [gesture respondsToSelector:@selector(locationInView:)] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(gesture, @selector(locationInView:), contentView) : CGPointZero;
    SEL ica = NSSelectorFromString(@"_itemContainerAtLocation:environment:");
    id container = [self respondsToSelector:ica] ? ((id (*)(id, SEL, CGPoint, long long))objc_msgSend)(self, ica, loc, 0) : nil;
    long long flags = G1B_SendLL0(gesture, NSSelectorFromString(@"modifierFlags"));
    ((void (*)(id, SEL, id, long long))objc_msgSend)(self, didSelect, container, flags);
}
%end
%end // G1D_TapForward


// ============================================================================================================
// 4c. Stage Manager window drag (gesture type 9): touch rules of the drag recognizer and the drag's workspace transaction
// ============================================================================================================
// The window drag is driven by the recognizer that 16.0 names _unpinSplitViewApplicationGestureRecognizer (a SBFluidSwitcherPanGestureRecognizer; its delegate methods are
// -_shouldSplitViewApplicationUnpinGesture:receiveTouch: and -_shouldBeginSplitViewApplicationUnpinGesture:, 16.0 0x1c6442888 / 0x1c6446a7c, 16.2 0x1c78f46e8 / 0x1c78f92b8).
// 16.2 decides WHICH window the touch grabbed once, in receiveTouch, and stores it in the recognizer (new property -initialTouchLeafAppLayout, ivar +0x8 of
// SBFluidSwitcherPanGestureRecognizer, cleared in -reset 0x1c763f334); shouldBegin and the workspace transaction (-[SBWindowDragGestureWorkspaceTransaction
// _beginWithGesture:] 16.2 0x1c733da30) then reuse that answer, so a window of ANOTHER display (or one of the strip) can be dragged, and the transaction learns the window's
// size (-sizeOfSelectedDisplayItem, new in 16.2, consumed by G1C's modifier event producer). 16.0 re-derived the window from the touch location in every step against the
// main display only.
// receiveTouch (16.2): gate = per-scene system gesture manager shouldReceive + _SBIsSystemGestureAllowed(scene, 0x16) + no banner under the point + unlocked environment 3 +
// no peek. Then, walking the stage layout's items front to back, the item's container hit rect (Stage Manager: the full container width, the nub height; a touch gets a rect
// that reaches one nub height above the window, a pointer does not; floating windows always the wide edge swipe width) is tested against the touch, containers in front occlude
// (their frames are collected in a region, 16.0 had no z order), and when no stage window is hit the touch may still land in a strip window (hit test + isDescendantOfView,
// "drag a window out of the strip"). The non Stage Manager Medusa width rules (Split View / Slide Over) are ported as well; the 16.2 jump table is at 0x1c78f4e08.
// shouldBegin (16.2): identical to 16.0 except for where the leaf layout comes from (initialTouchLeafAppLayout + -adjustedAppLayoutForLeafAppLayout:) and the calculator ivar.
// -[SBWindowDragGestureWorkspaceTransaction _finishWithGesture:] (16.2 0x1c733df84) only runs when a window was selected (16.0 had no override, and the base class
// asserted on a nil selected layout: the "lost drag end" crash path when the begin failed).
static char kG1DInitialTouchLeaf, kG1DDragItemSize;
static id G1D_Pan_GetLeaf(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kG1DInitialTouchLeaf); }
static void G1D_Pan_SetLeaf(id self, SEL _cmd, id leaf) { objc_setAssociatedObject(self, &kG1DInitialTouchLeaf, leaf, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static CGSize G1D_Txn_GetSize(id self, SEL _cmd) {
    NSValue *v = objc_getAssociatedObject(self, &kG1DDragItemSize);
    return v ? [v CGSizeValue] : CGSizeZero;
}
static void G1D_InstallWindowDragProperties(void) {
    Class pan = NSClassFromString(@"SBFluidSwitcherPanGestureRecognizer");
    if (pan) {
        if (!class_getInstanceMethod(pan, NSSelectorFromString(@"initialTouchLeafAppLayout"))) class_addMethod(pan, NSSelectorFromString(@"initialTouchLeafAppLayout"), (IMP)G1D_Pan_GetLeaf, "@16@0:8");
        if (!class_getInstanceMethod(pan, NSSelectorFromString(@"setInitialTouchLeafAppLayout:"))) class_addMethod(pan, NSSelectorFromString(@"setInitialTouchLeafAppLayout:"), (IMP)G1D_Pan_SetLeaf, "v24@0:8@16");
    }
    Class txn = NSClassFromString(@"SBWindowDragGestureWorkspaceTransaction");
    if (txn && !class_getInstanceMethod(txn, NSSelectorFromString(@"sizeOfSelectedDisplayItem")))
        class_addMethod(txn, NSSelectorFromString(@"sizeOfSelectedDisplayItem"), (IMP)G1D_Txn_GetSize, "{CGSize=dd}16@0:8");
}

static id G1D_InitialLeaf(id gr) { return objc_getAssociatedObject(gr, &kG1DInitialTouchLeaf); }
static void G1D_SetInitialLeaf(id gr, id leaf) { objc_setAssociatedObject(gr, &kG1DInitialTouchLeaf, leaf, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static id G1D_ItemForRole(id layout, long long role) {
    SEL s = NSSelectorFromString(@"itemForLayoutRole:");
    return [layout respondsToSelector:s] ? ((id (*)(id, SEL, long long))objc_msgSend)(layout, s, role) : nil;
}
static long long G1D_RoleForItem(id layout, id item) {
    SEL s = NSSelectorFromString(@"layoutRoleForItem:");
    return (item && [layout respondsToSelector:s]) ? ((long long (*)(id, SEL, id))objc_msgSend)(layout, s, item) : 0;
}
static CGRect G1D_FrameOf(id o) {
    return [o respondsToSelector:@selector(frame)] ? ((CGRect (*)(id, SEL))objc_msgSend)(o, @selector(frame)) : CGRectZero;
}
static CGRect G1D_BoundsOf(id o) {
    return [o respondsToSelector:@selector(bounds)] ? ((CGRect (*)(id, SEL))objc_msgSend)(o, @selector(bounds)) : CGRectZero;
}
// _SBRectContainsPoint (SpringBoardUIServices 0x1a4509f6c: all four edges are inclusive, a null rect contains nothing)
static BOOL G1D_RectContainsPointInclusive(CGRect r, CGPoint p) {
    return !CGRectIsNull(r) && p.x >= CGRectGetMinX(r) && p.x <= CGRectGetMaxX(r) && p.y >= CGRectGetMinY(r) && p.y <= CGRectGetMaxY(r);
}
static CGPoint G1D_LocationInView(id touchOrGesture, id view) {
    return [touchOrGesture respondsToSelector:@selector(locationInView:)] ? ((CGPoint (*)(id, SEL, id))objc_msgSend)(touchOrGesture, @selector(locationInView:), view) : CGPointZero;
}
// the visible item container whose app layout contains the item (block 0x1c78f4e1c)
static id G1D_ContainerContainingItem(id vc, id item) {
    id containers = G1B_Send0(G1B_Send0(vc, NSSelectorFromString(@"visibleItemContainers")), NSSelectorFromString(@"allValues"));
    for (id c in (containers ?: @[])) if (G1B_SendB1(G1B_Send0(c, NSSelectorFromString(@"appLayout")), NSSelectorFromString(@"containsItem:"), item)) return c;
    return nil;
}

// hit rect of one container (16.2 0x1c78f4a74 - 0x1c78f4c50)
static CGRect G1D_WD_HitRect(id touch, CGRect f, long long role, BOOL chamois, id stateLayout, id state) {
    double nub = G1B_Dbl0((id)NSClassFromString(@"SBNubView"), NSSelectorFromString(@"height"));
    id settings = G1B_Send0((id)NSClassFromString(@"SBMedusaDomain"), NSSelectorFromString(@"rootSettings"));
    double wide = G1B_Dbl0(settings, NSSelectorFromString(@"wideEdgeSwipeHitTestWidth")), narrow = G1B_Dbl0(settings, NSSelectorFromString(@"narrowEdgeSwipeHitTestWidth"));
    double width;
    if (chamois) width = f.size.width;
    else if (role == 4) width = wide;
    else {
        long long cfg = G1B_SendLL0(stateLayout, NSSelectorFromString(@"configuration")), floating = G1B_SendLL0(state, NSSelectorFromString(@"floatingConfiguration"));
        double w = 0;
        switch (cfg) {
            case 0: case 1: case 3: w = wide; break;
            case 2: w = role == 1 ? narrow : wide; break;
            case 4: w = role == 1 ? wide : narrow; break;
            default: w = 0; break;
        }
        BOOL rtl = [[UIApplication sharedApplication] userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft;
        long long edgeRole = rtl ? 2 : 1, oppositeRole = rtl ? 1 : 2;
        if (role == edgeRole && cfg != 1 && floating == 1) width = 0;
        else width = (floating == 2 && cfg != 1 && role == oppositeRole) ? 0 : w;
    }
    double y = f.origin.y, h = nub;
    if (role == 4) { y = f.origin.y - nub; h = nub * 2; }
    else if (chamois) {
        BOOL pointer = G1B_SendB0(touch, NSSelectorFromString(@"_isPointerTouch"));
        if (!pointer) { y = f.origin.y - nub; h = nub * 2; }
    }
    return CGRectMake(CGRectGetMidX(f) - width * 0.5, y, width, h);
}

// -_shouldSplitViewApplicationUnpinGesture:receiveTouch: (16.2 0x1c78f46e8)
static BOOL G1D_WD_ReceiveTouch(id gm, id gr, id touch) {
    id vc = G1D_GM_VC(gm), sc = G1D_GM_SC(gm);
    id view = G1B_Send0(vc, NSSelectorFromString(@"view"));
    CGPoint pt = G1D_SystemGestureLocation(gr, touch, view);
    id state = G1B_Send0(gm, NSSelectorFromString(@"_currentLayoutState"));
    CGPoint wloc = G1D_LocationInView(touch, nil);
    id ws = G1B_Send0(sc, NSSelectorFromString(@"windowScene"));
    id sgm = G1B_Send0(ws, NSSelectorFromString(@"systemGestureManager"));
    SEL recv = NSSelectorFromString(@"shouldSystemGestureReceiveTouchWithLocation:"), ban = NSSelectorFromString(@"_isBannerOccludingRegionAtReferencePoint:");
    BOOL receives = [sgm respondsToSelector:recv] ? ((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(sgm, recv, wloc) : NO;
    BOOL allowed = G1D_IsSystemGestureAllowed(ws, 0x16);
    BOOL banner = [gm respondsToSelector:ban] ? ((BOOL (*)(id, SEL, CGPoint))objc_msgSend)(gm, ban, wloc) : NO;
    BOOL chamois = G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"));
    id stateLayout = G1B_Send0(state, NSSelectorFromString(@"appLayout"));
    long long env = G1B_SendLL0(state, NSSelectorFromString(@"unlockedEnvironmentMode"));
    long long peek = G1B_SendLL0(state, NSSelectorFromString(@"peekConfiguration"));
    if (!(receives && allowed && !banner && env == 3 && !G1D_PeekValid(peek))) {
        G1D_SetInitialLeaf(gr, nil);
        if (BP_LogEnabled() && view && ((CGRect (*)(id, SEL))objc_msgSend)(view, @selector(bounds)).size.width > 1400)      // the external display: report why the window drag refuses the touch
            BP_Log(@"g1d: window drag receiveTouch REFUSED at %@ (window loc %@): receives %d allowed(0x16) %d banner %d env %lld peek %lld scene %@ sgm %@", NSStringFromCGPoint(pt), NSStringFromCGPoint(wloc), receives, allowed, banner, env, peek, ws, [sgm class]);
        return NO;
    }
    NSMutableArray *occluders = [NSMutableArray array];       // CGRegion of the frames of the windows in front
    id hit = nil;
    for (id item in (G1B_Send0(stateLayout, NSSelectorFromString(@"zOrderedItems")) ?: @[])) {
        id container = G1D_ContainerContainingItem(vc, item);
        if (!container) continue;
        CGRect f = G1D_FrameOf(container);
        long long role = G1D_RoleForItem(stateLayout, G1D_ItemForRole(G1B_Send0(container, NSSelectorFromString(@"appLayout")), 1));
        if (role == 0) continue;
        BOOL reject = YES;
        if (pt.x >= CGRectGetMinX(f) && pt.x <= CGRectGetMaxX(f) && G1D_RectContainsPointInclusive(G1D_WD_HitRect(touch, f, role, chamois, stateLayout, state), pt)) {
            reject = NO;
            if (chamois) for (NSValue *o in occluders) if (G1D_RectContainsPointInclusive([o CGRectValue], pt)) { reject = YES; break; }
        }
        if (!reject) { hit = container; break; }
        if (chamois) [occluders addObject:[NSValue valueWithCGRect:f]];
    }
    if (!hit && chamois) {                                              // a window of the strip (not in the stage layout): block 0x1c78f4e60
        SEL ht = NSSelectorFromString(@"hitTest:withEvent:"), desc = NSSelectorFromString(@"isDescendantOfView:");
        id containers = G1B_Send0(G1B_Send0(vc, NSSelectorFromString(@"visibleItemContainers")), NSSelectorFromString(@"allValues"));
        for (id c in (containers ?: @[])) {
            id leaf = G1B_Send0(c, NSSelectorFromString(@"appLayout"));
            if (G1D_RoleForItem(stateLayout, G1D_ItemForRole(leaf, 1)) != 0) continue;
            id hv = [view respondsToSelector:ht] ? ((id (*)(id, SEL, CGPoint, id))objc_msgSend)(view, ht, pt, nil) : nil;
            if (hv && [hv respondsToSelector:desc] && ((BOOL (*)(id, SEL, id))objc_msgSend)(hv, desc, c)) { hit = c; break; }
        }
    }
    G1D_SetInitialLeaf(gr, G1B_Send0(hit, NSSelectorFromString(@"appLayout")));
    if (BP_LogEnabled()) BP_Log(@"g1d: window drag receiveTouch at %@ -> %@", NSStringFromCGPoint(pt), hit ? G1D_InitialLeaf(gr) : @"no window");
    return hit != nil;
}

// -_shouldBeginSplitViewApplicationUnpinGesture: (16.2 0x1c78f92b8)
static BOOL G1D_WD_ShouldBegin(id gm, id gr) {
    id state = G1B_Send0(gm, NSSelectorFromString(@"_currentLayoutState"));
    id vc = G1D_GM_VC(gm), sc = G1D_GM_SC(gm);
    id leaf = G1D_InitialLeaf(gr);
    id adjusted = G1B_Send1(vc, NSSelectorFromString(@"adjustedAppLayoutForLeafAppLayout:"), leaf);
    if (!leaf || !adjusted) return NO;
    id item = G1D_ItemForRole(leaf, 1);
    id apps = G1B_Send0((id)NSClassFromString(@"SBApplicationController"), NSSelectorFromString(@"sharedInstance"));
    id app = G1B_Send1(apps, NSSelectorFromString(@"applicationWithBundleIdentifier:"), G1B_Send0(item, NSSelectorFromString(@"bundleIdentifier")));
    id element = G1B_Send1(state, NSSelectorFromString(@"elementWithIdentifier:"), G1B_Send0(item, NSSelectorFromString(@"uniqueIdentifier")));
    id handle = G1B_Send0(G1B_Send0(G1B_Send0(element, NSSelectorFromString(@"workspaceEntity")), NSSelectorFromString(@"deviceApplicationSceneEntity")), NSSelectorFromString(@"sceneHandle"));
    id stateLayout = G1B_Send0(state, NSSelectorFromString(@"appLayout"));
    id ws = G1B_Send0(sc, NSSelectorFromString(@"windowScene"));
    long long orientation = G1B_SendLL0(state, NSSelectorFromString(@"interfaceOrientation"));
    id calc = G1D_IvarObj(gm, "_displayItemLayoutAttributesCalculator");
    SEL frameSel = NSSelectorFromString(@"frameForLayoutRole:inAppLayout:containerOrientation:windowScene:");
    CGRect frame = [calc respondsToSelector:frameSel] ? ((CGRect (*)(id, SEL, long long, id, long long, id))objc_msgSend)(calc, frameSel, 1, stateLayout, orientation, ws) : CGRectZero;
    CGRect bounds = G1D_BoundsOf(G1B_Send0(vc, NSSelectorFromString(@"view")));
    BOOL sameSize = G1D_FloatEqual(frame.size.width, bounds.size.width) && G1D_FloatEqual(frame.size.height, bounds.size.height);     // BSSizeEqualToSize
    BOOL chamois = G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"));
    long long style = G1B_SendLL0(sc, NSSelectorFromString(@"windowManagementStyle"));       // both belong to the SWITCHER CONTROLLER (SBWindowScene has neither); asking the scene gave style 0 / no identity
    id identity = G1B_Send0(sc, NSSelectorFromString(@"displayIdentity"));                    // and made shouldBegin refuse every window drag
    SEL sup = NSSelectorFromString(@"supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:displayIdentity:");
    BOOL supports = [app respondsToSelector:sup] ? ((BOOL (*)(id, SEL, long long, id))objc_msgSend)(app, sup, style, identity) : NO;
    BOOL ok = NO;
    if (supports) {
        unsigned long long edges = (unsigned long long)G1B_SendLL0(handle, NSSelectorFromString(@"screenEdgesDeferringSystemGestures"));
        BOOL deferred = (edges & 1) != 0;
        if (!deferred || (chamois && !sameSize)) {
            id ga = G1B_Send0((id)NSClassFromString(@"SBGuidedAccessListener"), NSSelectorFromString(@"sharedGuidedAccessListener"));
            ok = !G1B_SendB0(ga, NSSelectorFromString(@"isGuidedAccessActive"));
        }
    }
    if (!ok && BP_LogEnabled()) BP_Log(@"g1d: Won't begin window drag gesture (supportsMulti=%d)", supports);
    return ok;
}

// -[SBWindowDragGestureWorkspaceTransaction _beginWithGesture:] (16.2 0x1c733da30, 16.0 0x1c5eca434)
static void G1D_SetIvarBool(id o, const char *name, BOOL v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) *(BOOL *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) = v;
}
static void G1D_SetIvarPoint(id o, const char *name, CGPoint v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) *(CGPoint *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) = v;
}
static void G1D_WD_Begin(id txn, id gesture, Class sup) {
    id vc = G1B_Send0(txn, NSSelectorFromString(@"switcherViewController"));
    id sc = G1B_Send0(vc, NSSelectorFromString(@"switcherController"));
    if (!sc) sc = G1B_Send0(G1B_Send0(txn, NSSelectorFromString(@"windowScene")), NSSelectorFromString(@"switcherController"));
    id layoutState = G1B_Send0(G1B_Send0(vc, NSSelectorFromString(@"layoutContext")), NSSelectorFromString(@"layoutState"));
    id contentView = G1B_Send0(vc, NSSelectorFromString(@"contentView")), view = G1B_Send0(vc, NSSelectorFromString(@"view"));
    CGPoint loc = G1D_LocationInView(gesture, contentView);
    Class panClass = NSClassFromString(@"SBFluidSwitcherPanGestureRecognizer");
    BOOL isPan = panClass && [gesture isKindOfClass:panClass];
    if (isPan) {
        SEL itl = NSSelectorFromString(@"initialTouchLocation");
        if ([gesture respondsToSelector:itl]) loc = ((CGPoint (*)(id, SEL))objc_msgSend)(gesture, itl);
    }
    CGRect vb = G1D_BoundsOf(view);
    if (loc.y > vb.size.height - 1) loc.y = vb.size.height - 1;
    id selected = nil;
    id leaf = isPan ? G1D_InitialLeaf(gesture) : nil;
    if (leaf && G1B_Send1(vc, NSSelectorFromString(@"adjustedAppLayoutForLeafAppLayout:"), leaf)) selected = leaf;
    if (!selected) {
        SEL lcr = NSSelectorFromString(@"layoutContainsRole:");
        long long floatingCfg = G1B_SendLL0(layoutState, NSSelectorFromString(@"floatingConfiguration"));
        if ([layoutState respondsToSelector:lcr] && ((BOOL (*)(id, SEL, long long))objc_msgSend)(layoutState, lcr, 3) && !G1D_FloatingConfigurationIsStashed(floatingCfg)) {
            double narrow = G1B_Dbl0(G1B_Send0((id)NSClassFromString(@"SBMedusaDomain"), NSSelectorFromString(@"rootSettings")), NSSelectorFromString(@"narrowEdgeSwipeHitTestWidth"));
            SEL ff = NSSelectorFromString(@"frameForFloatingAppLayoutInInterfaceOrientation:floatingConfiguration:");
            long long orientation = G1B_SendLL0(layoutState, NSSelectorFromString(@"interfaceOrientation"));
            CGRect fr = [sc respondsToSelector:ff] ? ((CGRect (*)(id, SEL, long long, long long))objc_msgSend)(sc, ff, orientation, floatingCfg) : CGRectZero;
            CGRect band = CGRectMake(fr.origin.x + (fr.size.width - narrow) * 0.5, 0, narrow, fr.size.height);
            if (CGRectContainsPoint(band, loc)) selected = G1B_Send0(layoutState, NSSelectorFromString(@"floatingAppLayout"));
        }
    }
    if (!selected) {
        SEL adj = NSSelectorFromString(@"_adjustedAppLayoutForItemContainerAtLocation:environment:"), lf = NSSelectorFromString(@"_leafAppLayoutForItemContainerAtLocation:environment:");
        id adjusted = [vc respondsToSelector:adj] ? ((id (*)(id, SEL, CGPoint, long long))objc_msgSend)(vc, adj, loc, 0) : nil;
        selected = G1D_MsgLL(adjusted, NSSelectorFromString(@"leafAppLayoutForRole:"), 4);
        if (!selected) selected = [vc respondsToSelector:lf] ? ((id (*)(id, SEL, CGPoint, long long))objc_msgSend)(vc, lf, loc, 0) : nil;
        if (!selected) {                                                // 16.2 logs a fault, bounces the recognizer and fails the transaction
            BP_Log(@"g1d: %@ no app layout for the window drag at %@, failing the gesture", NSStringFromClass(object_getClass(txn)), NSStringFromCGPoint(loc));
            if ([gesture respondsToSelector:@selector(setEnabled:)]) {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(gesture, @selector(setEnabled:), NO);
                ((void (*)(id, SEL, BOOL))objc_msgSend)(gesture, @selector(setEnabled:), YES);
            }
            SEL fin = NSSelectorFromString(@"finishWithCompletionType:");
            if ([txn respondsToSelector:fin]) ((void (*)(id, SEL, long long))objc_msgSend)(txn, fin, -1);
            return;
        }
    }
    G1B_SendV1(txn, NSSelectorFromString(@"setSelectedAppLayout:"), selected);
    if (G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"))) {
        id stateLayout = G1B_Send0(layoutState, NSSelectorFromString(@"appLayout"));
        BOOL inStage = G1B_SendB1(stateLayout, NSSelectorFromString(@"containsItem:"), G1D_ItemForRole(selected, 1));
        G1D_SetIvarBool(txn, "_draggingFromContinuousExposeStrips", !inStage);
        id container = nil;
        id all = G1B_Send0(G1B_Send0(vc, NSSelectorFromString(@"visibleItemContainers")), NSSelectorFromString(@"allValues"));
        for (id c in (all ?: @[])) if ([G1B_Send0(c, NSSelectorFromString(@"appLayout")) isEqual:selected]) { container = c; break; }
        SEL cp = NSSelectorFromString(@"convertPoint:fromView:");
        G1D_SetIvarPoint(txn, "_locationInSelectedDisplayItem", [container respondsToSelector:cp] ? ((CGPoint (*)(id, SEL, CGPoint, id))objc_msgSend)(container, cp, loc, contentView) : CGPointZero);
        SEL fr = NSSelectorFromString(@"frameForItemWithRole:inMainAppLayout:interfaceOrientation:");
        if ([sc respondsToSelector:fr]) {
            CGRect itemFrame = ((CGRect (*)(id, SEL, long long, id, long long))objc_msgSend)(sc, fr, 1, selected, G1B_SendLL0(layoutState, NSSelectorFromString(@"interfaceOrientation")));
            objc_setAssociatedObject(txn, &kG1DDragItemSize, [NSValue valueWithCGSize:itemFrame.size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    G1B_SUPER(void, sup, txn, NSSelectorFromString(@"_beginWithGesture:"), (struct objc_super *, SEL, id), gesture);
}

%group G1D_WindowDrag
%hook SBFluidSwitcherGestureManager
- (BOOL)_shouldSplitViewApplicationUnpinGesture:(id)gesture receiveTouch:(id)touch {
    if (!G1D_ON("g1d_windowdrag")) return %orig;
    if (BP_LogEnabled()) { CGPoint wl = G1D_LocationInView(touch, nil); if (wl.x > 1250) BP_Log(@"g1d: window drag gesture asked about a touch at %@ (gesture manager %p, scene %@)", NSStringFromCGPoint(wl), self, G1D_GM_Scene(self)); }
    return G1D_WD_ReceiveTouch(self, gesture, touch);
}
- (BOOL)_shouldBeginSplitViewApplicationUnpinGesture:(id)gesture {
    if (!G1D_ON("g1d_windowdrag")) return %orig;
    return G1D_WD_ShouldBegin(self, gesture);
}
%end
%hook SBFluidSwitcherPanGestureRecognizer
- (void)reset {
    %orig;
    G1D_SetInitialLeaf(self, nil);                                  // 16.2 0x1c763f334 clears the new property
}
%end
%hook SBWindowDragGestureWorkspaceTransaction
- (void)_beginWithGesture:(id)gesture {
    if (!G1D_ON("g1d_windowdrag")) {
        %orig;
        return;
    }
    G1D_WD_Begin(self, gesture, class_getSuperclass(%c(SBWindowDragGestureWorkspaceTransaction)));
}
- (void)_finishWithGesture:(id)gesture {
    if (!G1D_ON("g1d_windowdrag")) {
        %orig;
        return;
    }
    if (G1B_Send0(self, NSSelectorFromString(@"selectedAppLayout"))) {
        %orig;
    }
}
%end
%end // G1D_WindowDrag



// ============================================================================================================
// 5. Picture in Picture morph in a Stage Manager window (view controller side)
// ============================================================================================================
// 16.2 -[SBFluidSwitcherViewController _performEventResponse:] 0x1c745b6f0 hands the SBSetupPIPMorphingSwitcherEventResponse to
// -_setupPIPMorphingIfNeededForTransitionContext:response: 0x1c745a944 (16.0: -_setupMorphToPIPIfNeededForTransitionContext: 0x1c5fe130c, same body) which passes the
// response's appLayoutBoundingBox on to -_setupMorphAnimatorIfNeededForEntity:pipCoordinator:appLayout:appLayoutBoundingBox:uniqueID:direction:gestureInitiated:
// 0x1c745a420 (16.0 0x1c5fe0e6c without the box). That method stores appLayout / layoutRole / appLayoutBoundingBox on the SBPIPMorphAnimatorController (new properties,
// 0x1c78c0b2c..0x1c78c0b5c) either at creation (direction 0, createAndRegisterPictureInPictureMorphAnimatorController...appLayout:layoutRole:appLayoutBoundingBox:
// gestureInitiated:direction: 0x1c792d744) or on the already registered controller (direction != 0). The data source reads them (section 5b).
static __thread __unsafe_unretained id tPipResponse;                      // the SBSetupPIPMorphingSwitcherEventResponse being performed
static __thread __unsafe_unretained id tPipSetupLayout;                   // values for the controller while the 16.0 setup body runs
static __thread long long tPipSetupRole;
static __thread CGRect tPipSetupBox;
static __thread BOOL tPipSetupOn;
static char kPipLayout, kPipRole, kPipBox;
static void G1D_PIPC_SetLayout(id self, SEL _cmd, id l) { objc_setAssociatedObject(self, &kPipLayout, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static id G1D_PIPC_Layout(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kPipLayout); }
static void G1D_PIPC_SetRole(id self, SEL _cmd, long long r) { objc_setAssociatedObject(self, &kPipRole, @(r), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static long long G1D_PIPC_Role(id self, SEL _cmd) { return [objc_getAssociatedObject(self, &kPipRole) longLongValue]; }
static void G1D_PIPC_SetBox(id self, SEL _cmd, CGRect r) { objc_setAssociatedObject(self, &kPipBox, [NSValue valueWithBytes:&r objCType:@encode(CGRect)], OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static CGRect G1D_PIPC_Box(id self, SEL _cmd) {
    NSValue *v = objc_getAssociatedObject(self, &kPipBox); CGRect r = CGRectZero;
    if (v) [v getValue:&r];
    return r;
}
static void G1D_PIPC_Apply(id controller) {
    if (!controller || !tPipSetupOn) return;
    ((void (*)(id, SEL, id))objc_msgSend)(controller, NSSelectorFromString(@"setAppLayout:"), tPipSetupLayout);
    ((void (*)(id, SEL, long long))objc_msgSend)(controller, NSSelectorFromString(@"setLayoutRole:"), tPipSetupRole);
    ((void (*)(id, SEL, CGRect))objc_msgSend)(controller, NSSelectorFromString(@"setAppLayoutBoundingBox:"), tPipSetupBox);
}
static void G1D_InstallPIPAnimatorProperties(void) {
    Class c = NSClassFromString(@"SBPIPMorphAnimatorController");
    if (!c) return;
    class_addMethod(c, NSSelectorFromString(@"setAppLayout:"), (IMP)G1D_PIPC_SetLayout, "v24@0:8@16");
    class_addMethod(c, NSSelectorFromString(@"appLayout"), (IMP)G1D_PIPC_Layout, "@16@0:8");
    class_addMethod(c, NSSelectorFromString(@"setLayoutRole:"), (IMP)G1D_PIPC_SetRole, "v24@0:8q16");
    class_addMethod(c, NSSelectorFromString(@"layoutRole"), (IMP)G1D_PIPC_Role, "q16@0:8");
    class_addMethod(c, NSSelectorFromString(@"setAppLayoutBoundingBox:"), (IMP)G1D_PIPC_SetBox, "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16");
    class_addMethod(c, NSSelectorFromString(@"appLayoutBoundingBox"), (IMP)G1D_PIPC_Box, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8");
}

%group G1D_PIP
%hook SBFluidSwitcherViewController
- (void)_performEventResponse:(id)response {
    Class pc = NSClassFromString(@"SBSetupPIPMorphingSwitcherEventResponse");
    if (pc && [response isKindOfClass:pc] && G1D_ON("g1d_pip")) {
        id saved = tPipResponse;
        tPipResponse = response;
        %orig;
        tPipResponse = saved;
        return;
    }
    %orig;
}
- (void)_setupMorphAnimatorIfNeededForEntity:(id)entity pipCoordinator:(id)coordinator appLayout:(id)appLayout uniqueID:(id)uniqueID direction:(long long)direction gestureInitiated:(BOOL)gesture {
    id response = tPipResponse;
    if (!response || !G1D_ON("g1d_pip")) {
        %orig;
        return;
    }
    // 16.2 hands appLayout / layoutRole / appLayoutBoundingBox to the controller before anything can ask for them: on creation (init) or right after the lookup of the
    // registered one. The 16.0 body creates / looks the controller up itself, so the three values wait in thread local state until SBPIPController returns it (below).
    id handle = G1B_Send0(entity, NSSelectorFromString(@"sceneHandle"));
    NSString *sceneId = G1B_Send0(handle, NSSelectorFromString(@"sceneIdentifier"));
    id item = nil;
    for (id it in (G1B_Send0(appLayout, NSSelectorFromString(@"allItems")) ?: @[]))      // 16.2 block 0x1c745a8d0: item.uniqueIdentifier == entity.sceneHandle.sceneIdentifier
        if ([[G1B_Send0(it, NSSelectorFromString(@"uniqueIdentifier")) description] isEqualToString:sceneId]) { item = it; break; }
    SEL lri = NSSelectorFromString(@"layoutRoleForItem:");
    SEL bb = NSSelectorFromString(@"appLayoutBoundingBox");
    id savedLayout = tPipSetupLayout; long long savedRole = tPipSetupRole; CGRect savedBox = tPipSetupBox; BOOL savedOn = tPipSetupOn;
    tPipSetupLayout = appLayout;
    tPipSetupRole = [appLayout respondsToSelector:lri] ? ((long long (*)(id, SEL, id))objc_msgSend)(appLayout, lri, item) : 0;
    tPipSetupBox = [response respondsToSelector:bb] ? ((CGRect (*)(id, SEL))objc_msgSend)(response, bb) : CGRectZero;
    tPipSetupOn = YES;
    %orig;
    tPipSetupLayout = savedLayout; tPipSetupRole = savedRole; tPipSetupBox = savedBox; tPipSetupOn = savedOn;
}
%end

%hook SBPIPController
- (id)createAndRegisterPictureInPictureMorphAnimatorControllerWithTargetProcessIdentifier:(int)pid uuid:(id)uuid scenePersistenceIdentifier:(id)persistence direction:(long long)direction gestureInitiated:(BOOL)gesture {
    id c = %orig;
    G1D_PIPC_Apply(c);
    return c;
}
- (id)pictureInPictureMorphAnimatorControllerForProcessIdentifier:(int)pid scenePersistenceIdentifier:(id)persistence {
    id c = %orig;
    G1D_PIPC_Apply(c);
    return c;
}
%end
%end // G1D_PIP

// ============================================================================================================
// 5b. Picture in Picture morph: data source, animator controller and view morph animator
// ============================================================================================================
// 16.2 SBPIPMorphAnimatorDataSource (the 16.0 one is initialised with pid / persistence id / gesture flag, 16.2 with the morph animator controller and reads those from it):
//   -sourceContentContainerFrameForAnimator: 0x1c783031c  new (replaces sourceAppLayoutFrameForAnimator: 0x1c60b7e50): the item's frame in the main app layout of the display
//      (-[SBSwitcherController frameForItemWithRole:inMainAppLayout:interfaceOrientation:]) moved by the app layout bounding box origin
//   -sourceContentFrameForAnimator: 0x1c782fdc0 (16.0 0x1c60b7c28): fits the PIP into that container (16.0: window frame converted by the animator, landscape swap), initial frames are cached per morph
//   -sourceSubviewFrame:inScreenSpaceForAnimator: 0x1c7830450 new, -shouldProvideSourceClippingFrameInFixedCoordinateSpace: 0x1c782fda4 new,
//   -_appLayoutBoundingBoxForAnimator: 0x1c782fd24 new, -_isChamoisWindowingUIEnabledForAnimator: 0x1c782fcd0 new,
//   -sourceBlackCurtainCornerRadiusForAnimator: 0x1c78307f8 (16.0 0x1c60b827c, + the Stage Manager branch).
//   -targetFinalFrameForAnimator: 0x1c78304b0 only changed where the gesture flag comes from: left alone.
// SBPIPMorphAnimatorController -willRemoveTargeMatchMoveAnimationAtFrame:withinSourceFrame: 0x1c78c09c0 (16.0 0x1c6413054) converts both frames to screen space first.
// SBViewMorphAnimator: -_sourceContentFrameForSourceView:withTargetDataSource: (16.0 0x1c61f36a4) and -_sourceAppLayoutFrameForSourceView:withTargetDataSource: (0x1c61f3964)
//   converted the data source's window frames into the superview of the source view; 16.2 uses the data source frames as they are (the container frame inset by -1,
//   0x1c7681eac) and -_checkAnimationsDependencies: 0x1c7683580 re-parents the black curtain keeping its frame. -_source:finalCenterWithFinalScale:contentFrame:targetFinalFrame:
//   0x1c7681f9c only gained logging.  The SBPIPController side (-homeScreenInitialPIPFrameForWindowScene:... etc.) is section 5c.
static id G1D_PIPDS_Controller(id ds) {                                           // the morph animator controller the 16.2 data source holds (+0x20)
    id pip = G1D_IvarObj(ds, "_pipController");
    id persistence = G1D_IvarObj(ds, "_scenePersistenceIdentifier");
    int pid = (int)(G1D_IvarULL(ds, "_targetProcessIdentifier") & 0xffffffffu);
    SEL find = NSSelectorFromString(@"pictureInPictureMorphAnimatorControllerForProcessIdentifier:scenePersistenceIdentifier:");
    return [pip respondsToSelector:find] ? ((id (*)(id, SEL, int, id))objc_msgSend)(pip, find, pid, persistence) : nil;
}
static BOOL G1D_PIPDS_Chamois(id animator) {
    return G1B_SendB0(G1B_Send0(G1B_Send0(animator, NSSelectorFromString(@"windowScene")), NSSelectorFromString(@"switcherController")), NSSelectorFromString(@"isChamoisWindowingUIEnabled"));
}
static CGRect G1D_PIPDS_Box(id ds, id animator) {
    if (!G1D_PIPDS_Chamois(animator)) return CGRectZero;
    id c = G1D_PIPDS_Controller(ds);
    return [c respondsToSelector:NSSelectorFromString(@"appLayoutBoundingBox")] ? ((CGRect (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"appLayoutBoundingBox")) : CGRectZero;
}
static CGRect G1D_PIPDS_ContainerFrame(id ds, id animator) {
    CGRect box = G1D_PIPDS_Box(ds, animator);
    id c = G1D_PIPDS_Controller(ds);
    id sc = G1B_Send0(G1B_Send0(animator, NSSelectorFromString(@"windowScene")), NSSelectorFromString(@"switcherController"));
    SEL fr = NSSelectorFromString(@"frameForItemWithRole:inMainAppLayout:interfaceOrientation:");
    long long role = G1B_SendLL0(c, NSSelectorFromString(@"layoutRole"));
    id layout = G1B_Send0(c, NSSelectorFromString(@"appLayout"));
    long long orientation = G1B_SendLL0(animator, NSSelectorFromString(@"toOrientation"));
    CGRect f = [sc respondsToSelector:fr] ? ((CGRect (*)(id, SEL, long long, id, long long))objc_msgSend)(sc, fr, role, layout, orientation) : CGRectZero;
    return CGRectOffset(f, -box.origin.x, -box.origin.y);
}
static id G1D_PIPApplicationForPID(id pip, int pid) {                          // _SBPIPApplicationForProcessIdentifier 0x1c60b4008 / 0x1c78301f4
    for (id app in (G1B_Send0(pip, NSSelectorFromString(@"pictureInPictureApplications")) ?: @[]))
        if ((int)G1B_SendLL0(app, NSSelectorFromString(@"processIdentifier")) == pid) return app;
    return nil;
}
static char kPipInitialFrames;

%group G1D_PIPDS
%hook SBPIPMorphAnimatorDataSource
%new
- (CGRect)sourceContentContainerFrameForAnimator:(id)animator { return G1D_PIPDS_ContainerFrame(self, animator); }
%new
- (CGRect)sourceSubviewFrame:(CGRect)frame inScreenSpaceForAnimator:(id)animator {
    CGRect box = G1D_PIPDS_Box(self, animator);
    return CGRectOffset(frame, box.origin.x, box.origin.y);
}
%new
- (BOOL)shouldProvideSourceClippingFrameInFixedCoordinateSpace:(id)animator { return !G1D_PIPDS_Chamois(animator); }

- (CGRect)sourceContentFrameForAnimator:(id)animator {
    if (!G1D_ON("g1d_pipframes")) return %orig;
    CGRect container = G1D_PIPDS_ContainerFrame(self, animator);
    long long direction = G1B_SendLL0(animator, NSSelectorFromString(@"direction"));
    id pegasus = G1D_IvarObj(self, "_pegasusController");
    id persistence = G1D_IvarObj(self, "_scenePersistenceIdentifier");
    int pid = (int)(G1D_IvarULL(self, "_targetProcessIdentifier") & 0xffffffffu);
    id app = G1D_PIPApplicationForPID(pegasus, pid);
    CGRect result;
    if (direction != 0) {                                                             // restoring from PIP: fit the PIP into the container, centred
        SEL pref = NSSelectorFromString(@"preferredContentSizeForActivePictureInPictureWithApplication:sceneSessionPersistentIdentifier:");
        CGSize size = [pegasus respondsToSelector:pref] ? ((CGSize (*)(id, SEL, id, id))objc_msgSend)(pegasus, pref, app, persistence) : CGSizeZero;
        if (size.width == 0 || size.height == 0) {
            id pip = G1D_IvarObj(self, "_pipController");
            SEL any = NSSelectorFromString(@"anyContentViewPresentedOnWindowScene:");
            id view = [pip respondsToSelector:any] ? ((id (*)(id, SEL, id))objc_msgSend)(pip, any, G1B_Send0(animator, NSSelectorFromString(@"windowScene"))) : nil;
            CGRect vf = [view respondsToSelector:@selector(frame)] ? ((CGRect (*)(id, SEL))objc_msgSend)(view, @selector(frame)) : CGRectZero;
            size = CGSizeMake(fmax(vf.size.width, 1.0), fmax(vf.size.height, 1.0));
        }
        double scale = fmin(container.size.width / size.width, container.size.height / size.height);
        size = CGSizeMake(size.width * scale, size.height * scale);
        CGPoint center = CGPointMake(CGRectGetMidX(container), CGRectGetMidY(container));
        result = CGRectMake(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height);
    } else {                                                                          // morphing to PIP: the PIP's initial frame, cached per morph, relative to the container
        SEL initial = NSSelectorFromString(@"initialFrameForInteractivePictureInPictureAnimationEnteringBackgroundForApplication:sceneSessionPersistentIdentifier:");
        CGRect f = [pegasus respondsToSelector:initial] ? ((CGRect (*)(id, SEL, id, id))objc_msgSend)(pegasus, initial, app, persistence) : CGRectZero;
        NSValue *value = [NSValue valueWithBytes:&f objCType:@encode(CGRect)];
        id uuid = G1B_Send0(animator, NSSelectorFromString(@"uuid"));
        if (uuid) {
            NSMutableDictionary *cache = objc_getAssociatedObject(self, &kPipInitialFrames);
            if (!cache) { cache = [NSMutableDictionary dictionary]; objc_setAssociatedObject(self, &kPipInitialFrames, cache, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            NSValue *cached = cache[uuid];
            if (cached) value = cached; else cache[uuid] = value;
        }
        CGRect r = CGRectZero; [value getValue:&r];
        result = CGRectIsEmpty(r) ? CGRectNull : CGRectOffset(r, container.origin.x, container.origin.y);
    }
    if (BP_LogEnabled()) BP_Log(@"g1d: pip -sourceContentFrameForAnimator: %@ (direction %lld, container %@)", NSStringFromCGRect(result), direction, NSStringFromCGRect(container));
    return result;
}

- (CGFloat)sourceBlackCurtainCornerRadiusForAnimator:(id)animator {
    if (!G1D_ON("g1d_pipframes")) return %orig;
    static double (*displayRadius)(void); static BOOL (*isZero)(double); static dispatch_once_t once;
    dispatch_once(&once, ^{ displayRadius = (double (*)(void))dlsym(RTLD_DEFAULT, "SBScreenDisplayCornerRadius"); isZero = (BOOL (*)(double))dlsym(RTLD_DEFAULT, "BSFloatIsZero"); });
    if (!displayRadius) return %orig;
    double d = displayRadius();
    if (isZero ? isZero(d) : fabs(d) < 0.000001) return 0;
    if (G1D_PIPDS_Chamois(animator)) {
        id screen = G1B_Send0(G1B_Send0(animator, NSSelectorFromString(@"windowScene")), NSSelectorFromString(@"screen"));
        return G1B_Dbl0(G1B_Send0(screen, NSSelectorFromString(@"traitCollection")), NSSelectorFromString(@"displayCornerRadius"));
    }
    return %orig;                                                                     // 16.0 and 16.2 agree here: SBMedusaDomain rootSettings cornerRadiusForInnerCorners
}
%end

%hook SBPIPMorphAnimatorController
- (void)willRemoveTargeMatchMoveAnimationAtFrame:(CGRect)frame withinSourceFrame:(CGRect)sourceFrame {
    if (G1D_ON("g1d_pipframes")) {
        id animator = G1B_Send0(self, NSSelectorFromString(@"viewMorphAnimator"));
        id ds = G1B_Send0(animator, NSSelectorFromString(@"targetDataSource"));
        SEL conv = NSSelectorFromString(@"sourceSubviewFrame:inScreenSpaceForAnimator:");
        if ([ds respondsToSelector:conv]) {
            frame = ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(ds, conv, frame, animator);
            sourceFrame = ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(ds, conv, sourceFrame, animator);
        }
    }
    %orig(frame, sourceFrame);
}
%end

%hook SBViewMorphAnimator
- (CGRect)_sourceContentFrameForSourceView:(id)sourceView withTargetDataSource:(id)ds {
    if (!G1D_ON("g1d_pipframes")) return %orig;
    SEL s = NSSelectorFromString(@"sourceContentFrameForAnimator:");
    return (ds && [ds respondsToSelector:s]) ? ((CGRect (*)(id, SEL, id))objc_msgSend)(ds, s, self) : CGRectNull;
}
- (CGRect)_sourceAppLayoutFrameForSourceView:(id)sourceView withTargetDataSource:(id)ds {
    if (!G1D_ON("g1d_pipframes")) return %orig;
    SEL s = NSSelectorFromString(@"sourceContentContainerFrameForAnimator:");
    if (!ds || ![ds respondsToSelector:s]) return %orig;
    return CGRectInset(((CGRect (*)(id, SEL, id))objc_msgSend)(ds, s, self), -1, -1);   // 0x1c7681eac
}
- (void)_checkAnimationsDependencies:(id)dependencies {
    if (!G1D_ON("g1d_pipframes")) {
        %orig;
        return;
    }
    UIView *curtain = G1D_IvarObj(self, "_sourceBlackCurtainView");
    UIView *oldSuper = curtain.superview;
    CGRect oldFrame = curtain.frame;
    %orig;
    UIView *newSuper = curtain.superview;
    if (curtain && oldSuper && newSuper && oldSuper != newSuper)                      // 16.2 0x1c76837a8..0x1c7683800: re-parenting keeps the frame on screen
        curtain.frame = [oldSuper convertRect:oldFrame toView:newSuper];
}
%end
%end // G1D_PIPDS

// ============================================================================================================
// 5c. SBPIPController: the pieces of the PIP controller that look at ONE display in 16.0
// ============================================================================================================
// -restoreContentViewController:appSceneEntity:morphAnimatorConfigurationBlock:completion: 16.2 0x1c792a2a4 (16.0 0x1c6474958): the restore transition request is created with
//   -[SBMainWorkspace createRequestWithOptions:displayConfiguration:] for the display of the PIP scene ([[entity sceneHandle] displayIdentity].currentConfiguration)
//   (16.0: -createRequestWithOptions:, i.e. the main display); the rest of the body is identical (verified by selector sequence).
// -keyboardFocusController:externalSceneDidAcquireFocus: 16.2 0x1c792efa4 (16.0 0x1c647944c): the environment mode remembered for the keyboard focus change is the one of the
//   switcher controller of the window scene that owns the scene (16.0: the main switcher coordinator's).
// Checked and left alone (selector sequences identical or only logging / resource usage timeouts / System Aperture): _acquireStashAssertion..., _createNewWindowForContainer
//   ViewController:onWindowScene:, _setAdapter:, updateZStackParticipantPreferencesIfNeeded:windowScene:, containerViewController:userDidUpdateStashState: (resources usage
//   reduction timeout override), _updateZStackIfNeededForDisappearingContainerViewController: (System Aperture), _moveContext:toWindowScene: (off screen hyperregion composers).
static __thread __unsafe_unretained id tPipRestoreEntity;
%group G1D_PIPCtl
%hook SBPIPController
- (void)restoreContentViewController:(id)contentViewController appSceneEntity:(id)entity morphAnimatorConfigurationBlock:(id)configBlock completion:(id)completion {
    id saved = tPipRestoreEntity;
    tPipRestoreEntity = G1D_ON("g1d_piprestore") ? entity : nil;
    %orig;
    tPipRestoreEntity = saved;
}
- (void)keyboardFocusController:(id)controller externalSceneDidAcquireFocus:(id)scene {
    if (!G1D_ON("g1d_pipkeyboard") || !class_getInstanceVariable(object_getClass(self), "_unlockedEnvironmentModeWhenKeyboardFocusChanged")) {
        %orig;
        return;
    }
    UIApplication *app = [UIApplication sharedApplication];
    id ws = G1B_Send1(G1B_Send0(app, NSSelectorFromString(@"windowSceneManager")), NSSelectorFromString(@"windowSceneForSceneIdentifier:"), G1B_Send0(scene, NSSelectorFromString(@"identifier")));
    if (!ws) return;                                                                  // 16.2 leaves the remembered mode alone
    id sc = G1B_Send0(ws, NSSelectorFromString(@"switcherController"));
    if (!sc) NSLog(@"expected a switcherController!");
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_unlockedEnvironmentModeWhenKeyboardFocusChanged");
    *(long long *)((uint8_t *)(__bridge void *)self + ivar_getOffset(iv)) = G1B_SendLL0(sc, NSSelectorFromString(@"unlockedEnvironmentMode"));
}
%end

// -_updatePictureInPictureOverlayInsetsOnWindowScene:withCurrentLayoutState:shouldUpdate: 16.2 0x1c792dd08 (16.0 0x1c6478320): the environment mode and layout role queries go to the
// switcher controller of the window scene (16.0: [SBMainSwitcherControllerCoordinator sharedInstanceIfExists], the main display). The only other 16.2 change, the Spotlight
// predicate, only reaches non iPad idioms (the iPad path sets the flag to 0). The 16.0 body is kept and the very same two sends are answered by the scene's controller
// (it responds to -unlockedEnvironmentMode and -layoutContainsRole: with the same meaning).
static __thread __unsafe_unretained id tOverlayInsetsSC;
%hook SBPIPController
- (UIEdgeInsets)_updatePictureInPictureOverlayInsetsOnWindowScene:(id)scene withCurrentLayoutState:(BOOL)current shouldUpdate:(BOOL)update {
    id saved = tOverlayInsetsSC;
    tOverlayInsetsSC = G1D_ON("g1d_pipinsets") ? G1B_Send0(scene, NSSelectorFromString(@"switcherController")) : nil;
    UIEdgeInsets r = %orig;
    tOverlayInsetsSC = saved;
    return r;
}
%end
%hook SBMainSwitcherControllerCoordinator
+ (id)sharedInstanceIfExists {
    id sc = tOverlayInsetsSC;
    return sc ?: %orig;
}
%end

%hook SBMainWorkspace
- (id)createRequestWithOptions:(unsigned long long)options {
    id entity = tPipRestoreEntity;
    if (entity) {
        tPipRestoreEntity = nil;                                                      // only the request of the restore transition itself
        id identity = G1B_Send0(G1B_Send0(entity, NSSelectorFromString(@"sceneHandle")), NSSelectorFromString(@"displayIdentity"));
        id config = G1B_Send0(identity, NSSelectorFromString(@"currentConfiguration"));
        SEL s = NSSelectorFromString(@"createRequestWithOptions:displayConfiguration:");
        if (config && [self respondsToSelector:s]) return ((id (*)(id, SEL, unsigned long long, id))objc_msgSend)(self, s, options, config);
    }
    return %orig;
}
%end
%end // G1D_PIPCtl

// ============================================================================================================
// 3. SBFluidSwitcherViewController: the pointer crossing the boundary between two displays
// ============================================================================================================
// 16.2 -[SBFluidSwitcherViewController pointerDidMoveToFromWindowScene:toWindowScene:] (0x1c745f938): the view controller is an observer of the
// SBSystemPointerInteractionManager (registered in -initWithSwitcherController:... 0x1c743475c, removed in -invalidate 0x1c743be28). When the pointer leaves or
// enters the display of its switcher controller it dispatches SBPointerCrossedDisplayBoundarySwitcherModifierEvent(direction, edge): direction 1 = left this
// display, 0 = entered it; edge = edge of the OTHER display relative to this one according to -[SBExternalDisplayService preferredArrangementOfDisplay:relativeTo:]
// (ported in G4B.x). 16.0 has no SBSystemPointerInteractionManager; the observer list lives on the multi display user interaction coordinator (Group4Focus.x) that
// reports the very same transition (16.2 0x1c795e838 -_pointerMovedInScene:), and the view controllers register there at the same two places.
static id G1D_PointerCoordinator(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL s = NSSelectorFromString(@"multiDisplayUserInteractionCoordinator");
    return [app respondsToSelector:s] ? G1B_Send0(app, s) : nil;
}
static id G1D_ExternalDisplayService(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL s = NSSelectorFromString(@"externalDisplayService");
    return [app respondsToSelector:s] ? G1B_Send0(app, s) : nil;
}
static id G1D_FBSIdentity(id windowScene) { return G1B_Send0(windowScene, NSSelectorFromString(@"_fbsDisplayIdentity")); }

static void G1D_VC_PointerMoved(id self, SEL _cmd, id from, id to) {
    if (!G1D_ON("g1d_pointer")) return;
    id sc = G1B_Send0(self, NSSelectorFromString(@"switcherController")) ?: G1D_IvarObj(self, "_switcherController");
    id mine = G1B_Send0(sc, sWindowScene);
    if (!mine || !from || !to) return;                                                   // 16.2: all three must be non-nil
    unsigned long long direction;
    id display, relative;
    if (mine == from)      { direction = 1; display = G1D_FBSIdentity(to);   relative = G1D_FBSIdentity(from); }
    else if (mine == to)   { direction = 0; display = G1D_FBSIdentity(from); relative = G1D_FBSIdentity(to); }
    else return;
    id service = G1D_ExternalDisplayService();
    SEL arr = NSSelectorFromString(@"preferredArrangementOfDisplay:relativeTo:");
    id arrangement = (service && [service respondsToSelector:arr]) ? ((id (*)(id, SEL, id, id))objc_msgSend)(service, arr, display, relative) : nil;
    unsigned int edge = [arrangement respondsToSelector:@selector(edge)] ? ((unsigned int (*)(id, SEL))objc_msgSend)(arrangement, @selector(edge)) : 0;   // nil arrangement: edge 0
    Class ec = NSClassFromString(@"SBPointerCrossedDisplayBoundarySwitcherModifierEvent");
    SEL ini = NSSelectorFromString(@"initWithDirection:edge:");
    if (!ec || ![ec instancesRespondToSelector:ini]) return;
    id ev = ((id (*)(id, SEL, unsigned long long, unsigned int))objc_msgSend)([ec alloc], ini, direction, edge);
    if (ev) G1B_SendV1(self, NSSelectorFromString(@"_dispatchEventAndHandleAction:"), ev);
}

%group G1D_VCPointer
%hook SBFluidSwitcherViewController
- (id)initWithSwitcherController:(id)controller rootModifier:(id)modifier liveContentOverlayCoordinator:(id)coordinator delegate:(id)delegate dataSource:(id)source debugName:(id)name {
    id me = %orig;
    if (me && G1D_ON("g1d_pointer")) G1B_SendV1(G1D_PointerCoordinator(), NSSelectorFromString(@"addPointerInteractionObserver:"), me);
    return me;
}
- (void)invalidate {
    if (G1D_ON("g1d_pointer")) G1B_SendV1(G1D_PointerCoordinator(), NSSelectorFromString(@"removePointerInteractionObserver:"), self);
    %orig;
}
%new
- (void)pointerDidMoveToFromWindowScene:(id)from toWindowScene:(id)to { G1D_VC_PointerMoved(self, _cmd, from, to); }
%end
%end

// ============================================================================================================
// setup
// ============================================================================================================
// ============================================================================================================
// 6. SBFloatingDockController: which dock behaviour assertions lock keyboard focus to SpringBoard (hardware keyboard could not type while the Stage Manager dock was visible)
// ============================================================================================================
// -_updateFocusAssertion (identical in 16.0 0x1c6254fe0 and 16.2 0x1c76ea75c) takes -[SBWorkspaceKeyboardFocusController lockFocusToSpringBoardWindowScene:forReason:@"FloatingDock"]
// while the dock is presented and -_isActiveAssertionInOrAboveApp (16.0 0x1c62550dc) / -_isActiveAssertionInDesiredLevel (16.2 0x1c76ea858) says YES. The 16.0 predicate is
// `level > 4` (Stage Manager) or `level > 4 || in an app` (Medusa); the 16.2 one raises the Stage Manager threshold to 0xb:
//     threshold = isChamoisWindowingUIEnabled ? 0xb : 5;  r = level >= threshold;  if (!chamois) r |= unlockedEnvironmentMode == 3.
// The in-app dock visibility assertions of Stage Manager have level 5 / 6 (16.0 consumer, still running) or 9 (16.2), i.e. below 0xb: with the 16.2 predicate the visible dock never takes the
// keyboard focus from the front window; only the user interactions at level 0xb (modifyProgress:interactive:) and 0xc (setup) do.
%group G1D_DockFocus
%hook SBFloatingDockController
- (BOOL)_isActiveAssertionInOrAboveApp {
    if (!G1D_ON("g1d_dockfocus")) return %orig;
    id ws = G1D_IvarObj(self, "_windowScene");
    id sc = G1B_Send0(ws, NSSelectorFromString(@"switcherController"));
    id assertion = G1D_IvarObj(self, "_activeAssertion");
    BOOL chamois = G1B_SendB0(sc, NSSelectorFromString(@"isChamoisWindowingUIEnabled"));
    unsigned long long level = (unsigned long long)G1B_SendLL0(assertion, NSSelectorFromString(@"level"));
    BOOL r = level >= (chamois ? 0xbULL : 5ULL);
    if (!chamois) r = r || G1B_SendLL0(sc, NSSelectorFromString(@"unlockedEnvironmentMode")) == 3;
    return r;
}
%end
%end

// ============================================================================================================
// 7. SBFluidSwitcherViewController: the in-app "dock hidden" assertion of the Stage Manager floor (dock stayed visible over the keyboard / over a window covering it)
// ============================================================================================================
// FloatingDockController keeps its behaviour assertions in 13 level slots; -_deriveActiveAssertion:dockProgress: (16.2 0x1c76ea47c, 16.0 0x1c6254e44) takes the HIGHEST
// non-empty level and, inside a level, the LAST added assertion. The switcher's visible assertion that -_updateFloatingDockBehaviorAssertion (identical in 16.0 0x1c5fe0a84 and
// 16.2 0x1c745a058) creates from the floor's wantsDockBehaviorAssertion is progress 1 at level 9. 16.2's -_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext:
// (0x1c74414e4, run on every keyboard visibility change and transition) creates the in-app HIDDEN assertion (progress 0, animated, gesture possible, reason "in app") at level 9 too,
// added later, so it wins while -shouldConfigureInAppDockHiddenAssertion is YES (software keyboard visible, window covering the dock, ...) and is invalidated when it turns NO.
// The 16.0 body (0x1c5fc8890) creates the same assertion at level 5, which the level 9 visible assertion outranks: with the keyboard up (or a window over the dock) the dock stayed
// presented, over the lower keyboard rows (the dock window level is base+25, the hosted keyboard window base+20) until the next event removed the visible assertion.
// The 16.0 body stays as is (transient overlay part, folder branch, invalidation when no longer hidden); a level 5 hidden assertion it just created is replaced by the 16.2 one at
// level 9 (new one first, then the old one is invalidated, so the dock progress never flickers).
%group G1D_DockHidden
%hook SBFluidSwitcherViewController
- (void)_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext:(id)context {
    %orig;
    if (!G1D_ON("g1d_dockhidden")) return;
    id root = G1D_IvarObj(self, "_rootModifier");
    SEL hiddenSel = NSSelectorFromString(@"shouldConfigureInAppDockHiddenAssertion");
    if (!root || ![root respondsToSelector:hiddenSel] || !G1B_SendB0(root, hiddenSel)) return;
    SEL getSel = NSSelectorFromString(@"inAppFloatingDockBehaviorAssertion"), setSel = NSSelectorFromString(@"setInAppFloatingDockBehaviorAssertion:");
    id old = G1B_Send0(self, getSel);
    if (!old || G1B_SendLL0(old, NSSelectorFromString(@"level")) == 9) return;
    Class ac = NSClassFromString(@"SBFloatingDockBehaviorAssertion");
    SEL ini = NSSelectorFromString(@"initWithFloatingDockController:visibleProgress:animated:gesturePossible:atLevel:reason:withCompletion:");
    id dock = G1B_Send0(self, NSSelectorFromString(@"_floatingDockController"));
    if (!ac || !dock || ![ac instancesRespondToSelector:ini] || ![self respondsToSelector:setSel]) return;
    id fresh = ((id (*)(id, SEL, id, double, BOOL, BOOL, unsigned long long, id, id))objc_msgSend)([ac alloc], ini, dock, 0.0, YES, YES, 9ULL, @"in app", nil);
    if (!fresh) return;
    G1B_SendV1(self, setSel, fresh);
    G1B_SendV0(old, NSSelectorFromString(@"invalidate"));
    if (BP_LogEnabled()) BP_Log(@"dock: in-app hidden assertion level %lld -> 9 (16.2)", (long long)G1B_SendLL0(old, NSSelectorFromString(@"level")));
}
%end
%end

// ============================================================================================================
// Extended display diagnostics (debug log only): the empty app switcher on an external display (user: status bar hides, no blur and no animation,
// dismissed only by clicking, no auto-dismiss).  Both 16.0 and 16.2 decide the empty-switcher auto-dismiss in the same three transition modifiers
// (SBHomeToSwitcher 0x1c7346fd0 / SBForcePressToSwitcher 0x1c788bac4 / SBHomeGestureToSwitcher 0x1c794f844: emptySwitcherDismissDelay + a timer that
// emits SBDismissForEmptySwitcherSwitcherEventResponse).  These hooks only LOG what each of them returns and when its timer fires, so the log of an
// empty switcher on the external display shows which transition modifier ran and whether the dismiss timer was ever scheduled or delivered.
// ============================================================================================================
static NSString *G1D_TraceResp(id r) {
    if (!r) return @"nil";
    NSString *d = [r description];
    return d.length > 400 ? [[d substringToIndex:400] stringByAppendingString:@"..."] : d;
}
%group G1D_ExtTrace
%hook SBHomeToSwitcherSwitcherModifier
- (id)transitionWillUpdate {
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: SBHomeToSwitcher transitionWillUpdate -> %@", G1D_TraceResp(r)); return r;
}
- (id)handleTimerEvent:(id)event {
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: SBHomeToSwitcher handleTimerEvent %@ -> %@", event, G1D_TraceResp(r)); return r;
}
%end
%hook SBHomeGestureToSwitcherSwitcherModifier
- (id)transitionWillBegin {
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: SBHomeGestureToSwitcher transitionWillBegin -> %@", G1D_TraceResp(r)); return r;
}
- (id)handleTimerEvent:(id)event {
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: SBHomeGestureToSwitcher handleTimerEvent %@ -> %@", event, G1D_TraceResp(r)); return r;
}
%end
%hook SBForcePressToSwitcherSwitcherModifier
- (id)transitionWillBegin {
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: SBForcePressToSwitcher transitionWillBegin -> %@", G1D_TraceResp(r)); return r;
}
- (id)handleTimerEvent:(id)event {
    id r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: SBForcePressToSwitcher handleTimerEvent %@ -> %@", event, G1D_TraceResp(r)); return r;
}
%end
%hook SBSwitcherController
- (BOOL)toggleMainSwitcherNoninteractivelyWithSource:(long long)source animated:(BOOL)animated {
    BOOL r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: toggleMainSwitcherNoninteractively source %lld animated %d display %@ -> %d", source, animated, G1B_Send0(self, NSSelectorFromString(@"displayIdentity")), r);
    return r;
}
%end
// card close by a two-finger trackpad swipe up (the card's own kill scroll view): where does it stop on the external display?
%hook SBFluidSwitcherItemContainer
- (void)setKillable:(BOOL)killable {
    %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: card %p setKillable %d (killAxis %lld)", self, killable, G1B_SendLL0((id)self, NSSelectorFromString(@"killAxis")));
}
- (BOOL)_scrollViewShouldPanGestureTryToBegin:(id)scrollView {
    BOOL r = %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: card %p kill scroll view asked to begin a pan -> %d (killable %d, killingProgress %f)", self, r, G1B_SendB0((id)self, NSSelectorFromString(@"isKillable")), G1B_Dbl0((id)self, NSSelectorFromString(@"killingProgress")));
    return r;
}
- (void)scrollViewWillBeginDragging:(id)scrollView {
    %orig;
    if (BP_LogEnabled()) BP_Log(@"exttrace: card %p kill scroll view began dragging (killable %d)", self, G1B_SendB0((id)self, NSSelectorFromString(@"isKillable")));
}
%end
%end // G1D_ExtTrace

// ---- empty switcher on an external display: the dismiss timer outlives its transition modifier ----
// 16.0 and 16.2 are identical here: SBHomeToSwitcher / SBForcePressToSwitcher / SBHomeGestureToSwitcher schedule a timer (reason
// "DismissForEmptySwitcher-<modifier>", delay = emptySwitcherDismissDelay) in -transitionWillBegin/-transitionWillUpdate and ANSWER it in their own
// -handleTimerEvent: (16.2 0x1c794f8f0: reason == -_dismissForEmptySwitcherResponseName and appLayouts.count == 0 -> append
// SBDismissForEmptySwitcherSwitcherEventResponse).  The log (ee0a4eef) shows that on the external display the empty-switcher transition runs 1 -> 3 in 4 ms
// (nothing to animate: no home screen content there, so no blur and no animation, with apps it takes 0.72 s as on the main display), the transition
// modifier is removed at phase 3, the 0.2 s timer then fires at a chain that no longer contains the modifier that answers it, and the switcher stays open
// until a click.  Whoever is still in the chain answers it now, exactly as the transition modifier would have (same reason test, same response).
static NSHashTable *gG1DLiveEmptyTransitions;
static id G1D_EmptyLock(void) { static id l; static dispatch_once_t o; dispatch_once(&o, ^{ l = [NSObject new]; }); return l; }
static __unsafe_unretained id gG1DLastEmptyDismissEvent;
static BOOL G1D_IsEmptyTransition(id m) {
    static Class a, b, c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = NSClassFromString(@"SBHomeToSwitcherSwitcherModifier"); b = NSClassFromString(@"SBForcePressToSwitcherSwitcherModifier"); c = NSClassFromString(@"SBHomeGestureToSwitcherSwitcherModifier"); });
    return (a && [m isKindOfClass:a]) || (b && [m isKindOfClass:b]) || (c && [m isKindOfClass:c]);
}
%group G1D_EmptyDismiss
%hook SBTransitionSwitcherModifier
- (id)transitionWillBegin {
    id r = %orig;
    if (G1D_IsEmptyTransition(self)) {
        @synchronized (G1D_EmptyLock()) {
            if (!gG1DLiveEmptyTransitions) gG1DLiveEmptyTransitions = [NSHashTable weakObjectsHashTable];
            [gG1DLiveEmptyTransitions addObject:self];
        }
    }
    return r;
}
- (id)transitionDidEnd {
    id r = %orig;
    @synchronized (G1D_EmptyLock()) { [gG1DLiveEmptyTransitions removeObject:self]; }
    return r;
}
%end
%hook SBSwitcherModifier
- (id)handleTimerEvent:(id)event {
    id r = %orig;
    if (!event || event == gG1DLastEmptyDismissEvent || ![event respondsToSelector:@selector(reason)]) return r;
    NSString *reason = [event reason];
    if (![reason isKindOfClass:[NSString class]] || ![reason hasPrefix:@"DismissForEmptySwitcher-"]) return r;
    @synchronized (G1D_EmptyLock()) { if (gG1DLiveEmptyTransitions.count) return r; }       // a transition modifier is alive: it answers
    NSUInteger n = 1;
    @try { n = [(NSArray *)[(id)self valueForKey:@"appLayouts"] count]; } @catch (NSException *e) { n = 1; }
    if (n) return r;
    Class dc = NSClassFromString(@"SBDismissForEmptySwitcherSwitcherEventResponse");
    id d = dc ? [[dc alloc] init] : nil;
    if (!d) return r;
    gG1DLastEmptyDismissEvent = event;
    if (BP_LogEnabled()) BP_Log(@"g1d: empty switcher dismiss timer arrived after its transition modifier was gone (%@ on %@) -> dismissing", reason, NSStringFromClass(object_getClass(self)));
    return G1B_AppendTo(d, r);
}
%end
%end // G1D_EmptyDismiss


void G1D_Setup(void) {
    if (!BP_OnName("g1d")) return;
    G1D_InitSels();
    G1D_InstallWindowDragSupport();
    %init(G1D_Model);
    %init(G1D_Coord);
    %init(G1D_Gesture);
    %init(G1D_VCUpdateMode);
    %init(G1D_VCPointer);
    %init(G1D_Tongue);
    %init(G1D_GMTouch);
    %init(G1D_TapForward);
    G1D_InstallWindowDragProperties();
    %init(G1D_WindowDrag);
    G1D_InstallPIPAnimatorProperties();
    %init(G1D_PIP);
    %init(G1D_PIPDS);
    %init(G1D_PIPCtl);
    %init(G1D_DockFocus);
    %init(G1D_DockHidden);
    %init(G1D_ExtTrace);
    if (BP_OnName("g1d_emptydismiss")) { %init(G1D_EmptyDismiss); }
}
#pragma clang diagnostic pop
