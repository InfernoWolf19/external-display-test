// P1Drag.m : multi-display gesture workspace transaction (16.2) on top of the 16.0 SBFluidSwitcherGestureWorkspaceTransaction.   specs/CORE-LEFTOVERS-0.7.9.md item 1 (H1, M1, M7)
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).
//
// What 16.2 changed (all decoded from the disassembly, addresses in the comments below):
//  * the gesture transaction is SHARED by the switcher controllers of all displays: the gesture manager that starts it hands it to the coordinator
//    (-[SBFluidSwitcherGestureManager _startFluidSwitcherTransactionForGestureRecognizer:] block 0x1c78f37bc -> -[SBMainSwitcherControllerCoordinator
//    setActiveGestureTransaction:] 0x1c76e2bd4), which observes it and gives it to EVERY display's gesture manager. A modifier request produced by the VC of display B while
//    the window drag of display A runs therefore reaches the transaction of A through B's manager: -[SBFluidSwitcherGestureManager handleTransitionRequestForGestureUpdate:]
//    0x1c78f17f0 / ...Complete: 0x1c78f17fc send [txn handleTransitionRequestForGesture{Update,Complete}:req fromGestureManager:self].
//  * the transaction picks the display of the request from the MANAGER ([manager switcherController]), converts the switcher request into a workspace request for that
//    display (_workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel: 0x1c74b1478), keeps the original / active layout state per
//    switcher controller (two NSMapTables) and runs one scene layout transaction for the request PLUS one ancillary layout transaction per other display
//    (+[SBMainWorkspaceTransitionRequest ancillaryTransitionRequestsForTransitionRequest:] 0x1c7892c18 -> -[SBSwitcherController _ancillaryTransitionRequestForTransitionRequest:]
//    0x1c76066fc: the source display gets a request without the windows that moved away) - _runSceneLayoutTransactionForTransitionRequest:updateScenes: 0x1c72d771c.
//  * when the layout transaction starts, the scenes of the layout elements are moved to the scene manager of the target display (block 0x1c74af9ac in -transaction:
//    performTransitionWithCompletion: 0x1c72dbcc0).
//
// Port (new code over the 16.0 class; the 16.0 ivars at +0x140.. cannot change because subclass ivars follow them, so the new state is kept in associated objects and the
// 16.0 ivar _sceneLayoutTransaction (+0x158) plays the role of 16.2's _layoutTransaction):
//   P1_Init .. P1_TxnDidComplete  the transaction methods;   P1_Mgr*  the manager entry points + sharing;   P1_Coord*  coordinator side;   P1_SC*  switcher controller side.
// A transaction is created in "16.2 mode" or "16.0 mode" (decided once in init from the switches), every replaced method is consistent per transaction.
// Switches: p1_drag (everything of this file), p1_txn (the transaction rewrite), p1_share (shared active transaction), p1_ancillary (ancillary requests + layout transactions,
// SBSwitcherController side), p1_modupdate (M1), p1_asyncdrag (M7). Logs: grep "p1:" in Backport162.log (needs Backport162.debug).
//
// Documented deviations from 16.2 (none changes a result): (a) -_beginWithGesture: runs the 16.0 body and the 16.2 ancillary / completion clean-up is done from the first
// -_updateDigitizerSurfaceDimensions that follows (16.2: the clean-up sits directly before that call); (b) the NSAssert "Got a nil animationController back from
// SBSwitcherController!" of -handleTransitionRequestForGestureComplete: is a logged return instead of an exception; (c) _layoutTransitionCompletions is an NSMutableArray
// (16.2: NSMutableSet of blocks; the order of a set is undefined, the array keeps the arrival order).

#import "G1BKit.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static BOOL P1_On(const char *n) { return BP_OnName("p1_drag") && BP_OnName(n); }

// ------------------------------------------------------------------------------------------------ helpers (all nil safe: a missing selector yields nil / 0)
static id P1_S0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((id (*)(id, SEL))objc_msgSend)(o, x) : nil; }
static id P1_S1(id o, const char *s, id a) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, x, a) : nil; }
static id P1_S2(id o, const char *s, id a, id b) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((id (*)(id, SEL, id, id))objc_msgSend)(o, x, a, b) : nil; }
static BOOL P1_B0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, x) : NO; }
static BOOL P1_B1(id o, const char *s, id a) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((BOOL (*)(id, SEL, id))objc_msgSend)(o, x, a) : NO; }
static long long P1_L0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((long long (*)(id, SEL))objc_msgSend)(o, x) : 0; }
static void P1_V0(id o, const char *s) { SEL x = sel_registerName(s); if (o && [o respondsToSelector:x]) ((void (*)(id, SEL))objc_msgSend)(o, x); }
static void P1_V1(id o, const char *s, id a) { SEL x = sel_registerName(s); if (o && [o respondsToSelector:x]) ((void (*)(id, SEL, id))objc_msgSend)(o, x, a); }
static void P1_VB(id o, const char *s, BOOL a) { SEL x = sel_registerName(s); if (o && [o respondsToSelector:x]) ((void (*)(id, SEL, BOOL))objc_msgSend)(o, x, a); }
static void P1_VL(id o, const char *s, long long a) { SEL x = sel_registerName(s); if (o && [o respondsToSelector:x]) ((void (*)(id, SEL, long long))objc_msgSend)(o, x, a); }
static double P1_Dbl(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((double (*)(id, SEL))objc_msgSend)(o, x) : 0.0; }
static CGRect P1_Rect0(id o, const char *s) { SEL x = sel_registerName(s); return (o && [o respondsToSelector:x]) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, x) : CGRectZero; }

static id P1_Ivar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return BP_ObjIvar(o, iv);
}
static void P1_SetIvar(id o, const char *name, id v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) BP_SetObjIvar(o, iv, v);
}
static long long P1_IvarLL(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? *(long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : 0;
}
static void P1_SetIvarLL(id o, const char *name, long long v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) *(long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) = v;
}
static BOOL P1_IvarB(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? *(BOOL *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) : NO;
}
static void P1_SetIvarB(id o, const char *name, BOOL v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (iv) *(BOOL *)((uint8_t *)(__bridge void *)o + ivar_getOffset(iv)) = v;
}

static id P1_WSM(void) { return P1_S0((id)[UIApplication sharedApplication], "windowSceneManager"); }
static id P1_SceneForDisplay(id displayIdentity) { return displayIdentity ? P1_S1(P1_WSM(), "windowSceneForDisplayIdentity:", displayIdentity) : nil; }
static NSArray *P1_ConnectedScenes(void) {
    id set = P1_S0(P1_WSM(), "connectedWindowScenes");
    return [set respondsToSelector:@selector(allObjects)] ? [set allObjects] : @[];
}
static id P1_CoordinatorOf(id switcherController) { return P1_S0(switcherController, "switcherCoordinator"); }
static NSString *P1_Disp(id sc) {                       // for the logs only
    id di = P1_S0(P1_S0(sc, "windowScene"), "_fbsDisplayIdentity");
    return [NSString stringWithFormat:@"%@", di ?: @"nil"];
}

// BSSettingFlagIsYes (BaseBoard): the flag values are 0 = unspecified, 1 = yes, 2 = no
static BOOL P1_FlagYes(long long f) {
    static BOOL (*fn)(long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "BSSettingFlagIsYes"); });
    return fn ? fn(f) : f == 1;
}
static BOOL P1_PeekValid(long long cfg) { return (cfg & ~1LL) == 2; }                       // _SBPeekConfigurationIsValid (16.0 0x1c6289f84 = 16.2 0x1c77229fc)
static BOOL P1_FloatingStashed(long long cfg) { return (unsigned long long)(cfg - 3) < 2; } // SBMainDisplayLayoutStateFloatingConfigurationIsStashed (16.2 0x1c7722a84)
// _SBLayoutRoleEnumerateValidRoles (16.2 0x1c789491c): roles 1, 2, 4 .. 9 (_SBLayoutRoleEnumerateAppLayoutRoles 0x1c7894974 skips 3), then 3
static void P1_EnumerateValidRoles(void (^blk)(long long)) {
    static const long long roles[] = { 1, 2, 4, 5, 6, 7, 8, 9, 3 };
    for (size_t i = 0; i < sizeof roles / sizeof roles[0]; i++) blk(roles[i]);
}

// ------------------------------------------------------------------------------------------------ per transaction state
static char kP1Mode, kP1Orig, kP1Active, kP1Anc, kP1Comp;
static BOOL P1_IsNew(id txn) { return [objc_getAssociatedObject(txn, &kP1Mode) boolValue]; }
static NSMapTable *P1_Map(id txn, char *key) {
    NSMapTable *m = objc_getAssociatedObject(txn, key);
    if (!m) { m = [NSMapTable weakToStrongObjectsMapTable]; objc_setAssociatedObject(txn, key, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return m;
}
static NSMapTable *P1_OrigMap(id txn) { return P1_Map(txn, &kP1Orig); }          // _originalLayoutStatesBySwitcherController (16.2 +0x140)
static NSMapTable *P1_ActiveMap(id txn) { return P1_Map(txn, &kP1Active); }      // _activeLayoutStatesBySwitcherController (16.2 +0x148)
static NSMutableSet *P1_Anc(id txn) {                                             // _ancillaryLayoutTransactions (16.2 +0x160)
    NSMutableSet *s = objc_getAssociatedObject(txn, &kP1Anc);
    if (!s) { s = [NSMutableSet set]; objc_setAssociatedObject(txn, &kP1Anc, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return s;
}
static NSMutableArray *P1_Comp(id txn) {                                          // _layoutTransitionCompletions (16.2 +0x168)
    NSMutableArray *s = objc_getAssociatedObject(txn, &kP1Comp);
    if (!s) { s = [NSMutableArray array]; objc_setAssociatedObject(txn, &kP1Comp, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return s;
}

// saved 16.0 IMPs
static IMP sOrigInit, sOrigBegin, sOrigWillInterrupt, sOrigDidComplete, sOrigFail, sOrigRun, sOrigPerform, sOrigTxnDone, sOrigStartScene, sOrigAcquire, sOrigLayoutStateFor, sOrigPrevLayoutStateFor;
static IMP sOrigReqForCtx, sOrigDigitizer;
static IMP sOrigMgrUpdate, sOrigMgrComplete, sOrigMgrSetActive;
static IMP sOrigAncillary, sOrigCurrentLayoutState, sOrigGestureModUpdate, sOrigAsyncRendering;

// ------------------------------------------------------------------------------------------------ init (16.2 0x1c74ae6f4)
// 16.2 additionally: both state maps get the layout state of EVERY connected window scene's switcher controller (original and active), plus the two sets.
static __attribute__((ns_returns_retained)) id P1_Init(__attribute__((ns_consumed)) id self, SEL _cmd, id request, id vc, id delegate) {
    id r = ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id, id, id))sOrigInit)(self, _cmd, request, vc, delegate);
    if (!r) return r;
    BOOL mode = P1_On("p1_txn");
    objc_setAssociatedObject(r, &kP1Mode, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (mode) {
        NSMapTable *orig = P1_OrigMap(r), *act = P1_ActiveMap(r);
        for (id scene in P1_ConnectedScenes()) {
            id sc = P1_S0(scene, "switcherController");
            id ls = P1_S0(sc, "layoutState");
            if (sc && ls) { [orig setObject:ls forKey:sc]; [act setObject:ls forKey:sc]; }
        }
        (void)P1_Anc(r); (void)P1_Comp(r);
        if (BP_LogEnabled()) BP_Log(@"p1: txn %p created (16.2 mode), type %lld, own display %@, %lu switcher controller layout states captured", (__bridge void *)r, P1_L0(r, "_gestureType"), P1_Disp(P1_S0(vc, "switcherController")), (unsigned long)orig.count);
    }
    return r;
}

// ------------------------------------------------------------------------------------------------ request -> scene / controller (16.2 0x1c74b1ed0 / 0x1c74b1f5c)
static id P1_WindowSceneForRequest(id self, SEL _cmd, id request) {
    return P1_SceneForDisplay(P1_S0(request, "displayIdentity"));
}
static id P1_SwitcherControllerForRequest(id self, SEL _cmd, id request) {
    return P1_S0(P1_WindowSceneForRequest(self, _cmd, request), "switcherController");
}

// modifyApplicationContext: block of 16.2 0x1c74b0010 / 0x1c74b005c: every application scene entity gets activation setting 9 = YES
static void P1_SetActivation9(id entity) {
    SEL s = sel_registerName("setFlag:forActivationSetting:");
    if (entity && [entity respondsToSelector:s]) ((void (*)(id, SEL, long long, unsigned long long))objc_msgSend)(entity, s, 1, 9);
}
static void P1_ActivateAll(id ctx) {
    id set = P1_S0(ctx, "applicationSceneEntities");
    if ([set conformsToProtocol:@protocol(NSFastEnumeration)]) for (id e in (id<NSFastEnumeration>)set) P1_SetActivation9(e);
}

// ------------------------------------------------------------------------------------------------ _workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel: (16.2 0x1c74b1478; 16.0 _transitionRequestForSwitcherTransitionRequest:eventLabel: 0x1c6036044)
// Same body as 16.0 with the switcher controller (and so the display, window scene and original layout state) taken from the gesture manager instead of the transaction.
static id P1_WorkspaceRequest(id self, SEL _cmd, id request, id manager, id label) {
    id appLayout = P1_S0(request, "appLayout");
    id sc = P1_S0(manager, "switcherController");
    id scene = P1_S0(sc, "windowScene");
    id config = P1_S0(P1_S0(scene, "_fbsDisplayIdentity"), "currentConfiguration");
    id txnReq = P1_S0(self, "transitionRequest");
    id workspace = P1_S0(txnReq, "workspace");
    SEL create = sel_registerName("createRequestWithOptions:displayConfiguration:");
    id wreq = [workspace respondsToSelector:create] ? ((id (*)(id, SEL, unsigned long long, id))objc_msgSend)(workspace, create, 0, config) : nil;
    if (!wreq) { BP_Log(@"p1: no workspace request could be created (workspace %@, display %@)", workspace, scene); return nil; }
    SEL conf = sel_registerName("configureRequest:forSwitcherTransitionRequest:withEventLabel:");
    if ([sc respondsToSelector:conf]) ((void (*)(id, SEL, id, id, id))objc_msgSend)(sc, conf, wreq, request, label);
    P1_VL(wreq, "setSource:", P1_L0(txnReq, "source"));
    id origState = [P1_OrigMap(self) objectForKey:sc];
    long long mode = P1_L0(request, "unlockedEnvironmentMode");
    BOOL home;
    if (mode == 1) home = YES;
    else home = [appLayout isEqual:P1_S0((id)NSClassFromString(@"SBAppLayout"), "homeScreenAppLayout")];
    id sel = P1_S0(self, "selectedAppLayout");
    id tctx = P1_S0(P1_S0(self, "transitionRequest"), "transientOverlayContext");
    if (mode == 2 || home) {
        id overlay = tctx ? P1_S0(tctx, "transientOverlay") : nil;
        if (tctx && overlay) {                                              // block 0x1c74b1834
            id copy = [overlay copy];
            void (^blk)(id) = ^(id c) { P1_V1(c, "setTransientOverlay:", copy); P1_VL(c, "setTransitionType:", 1); };
            P1_V1(wreq, "modifyTransientOverlayContext:", blk);
        } else if (P1_L0(sel, "type") == 2 && (home || P1_L0(origState, "unlockedEnvironmentMode") != 2)) {
            id created = P1_S1(self, "_createWorkspaceTransientOverlayForAppLayout:", sel);
            if (created) {                                                  // block 0x1c74b18b0
                void (^blk)(id) = ^(id c) { P1_V1(c, "setTransientOverlay:", created); P1_VL(c, "setTransitionType:", 1); };
                P1_V1(wreq, "modifyTransientOverlayContext:", blk);
            }
        }
    }
    id actx = P1_S0(wreq, "applicationContext");
    P1_VL(actx, "setRequestedFloatingConfiguration:", P1_L0(request, "floatingConfiguration"));
    P1_VB(actx, "setInLiveResize:", P1_B0(request, "isLiveResize"));
    P1_ActivateAll(P1_S0(wreq, "applicationContext"));
    P1_V1(P1_S0(wreq, "applicationContext"), "setDelegate:", self);
    return wreq;
}


// ------------------------------------------------------------------------------------------------ _updateMainDisplayIfNecessaryForWorkspaceTransitionRequests: (16.2 0x1c74b0e90; the same code was inline in completeGestureWithTransitionRequest: in 16.0)
// Only the request of the MAIN display window scene counts (block 0x1c74b1128). Home / empty target (or Stage Manager's mode 1): the app is told the orientation and the home
// screen content is required for a moment; a modal icon manager state is dismissed (popped when the target is the home screen).
static void P1_DismissIconManagerModal(BOOL popAllowed) {
    id icm = P1_S0(P1_S0((id)NSClassFromString(@"SBIconController"), "sharedInstance"), "iconManager");
    if (P1_B0(icm, "isFolderPageManagementUIVisible")) P1_V0(icm, "dismissFolderPageManagementUI");
    else if (P1_B0(icm, "isShowingModalInteraction")) { if (popAllowed) P1_V0(icm, "popModalInteraction"); else P1_V0(icm, "dismissModalInteractions"); }
    else P1_VB(icm, "setEditing:", NO);
}
static void P1_HomeRequirements(id layoutState) {
    id app = (id)[UIApplication sharedApplication];
    SEL note = sel_registerName("noteInterfaceOrientationChanged:logMessage:");
    if ([app respondsToSelector:note]) ((void (*)(id, SEL, long long, id))objc_msgSend)(app, note, P1_L0(layoutState, "interfaceOrientation"), @"SBFluidSwitcherGestureWorkspaceTransaction running animation to home screen");
    id ui = P1_S0((id)NSClassFromString(@"SBUIController"), "sharedInstance");
    id assertion = P1_S1(ui, "beginRequiringContentForReason:", @"SBUIHomeScreenActiveContentRequirementReason");
    (void)assertion;                                                            // 16.2 does not keep it either: it is invalidated when released
}
static void P1_UpdateMain(id self, SEL _cmd, id requests) {
    id first = nil;
    for (id r in (id<NSFastEnumeration>)requests)
        if (P1_B0(P1_WindowSceneForRequest(self, 0, r), "isMainDisplayWindowScene")) { first = r; break; }
    if (!first) return;
    id layoutState = P1_S0(P1_S0(first, "applicationContext"), "layoutState");
    id appLayout = P1_S0(layoutState, "appLayout");
    long long mode = P1_L0(layoutState, "unlockedEnvironmentMode");
    long long fcfg = P1_L0(layoutState, "floatingConfiguration");
    long long fvis = P1_L0(layoutState, "isFloatingSwitcherVisible");
    if (mode == 1) { P1_HomeRequirements(layoutState); P1_DismissIconManagerModal(YES); return; }
    BOOL A = (mode == 2) ? YES : P1_FlagYes(fvis);
    id items = P1_S0(appLayout, "allItems");
    NSUInteger n = [items respondsToSelector:@selector(count)] ? [items count] : 0;
    BOOL stashed = P1_FloatingStashed(fcfg);
    if (A || n == 0 || stashed) {
        if (n == 0) { P1_HomeRequirements(layoutState); P1_DismissIconManagerModal(YES); }
        else if (A) P1_DismissIconManagerModal(NO);
        return;
    }
    id sel = P1_S0(self, "selectedAppLayout");
    if (!P1_B1(appLayout, "isOrContainsAppLayout:", sel) && P1_L0(self, "_gestureType") != 9) P1_DismissIconManagerModal(NO);
}

// ------------------------------------------------------------------------------------------------ _startSceneUpdateTransaction:forSceneIdentifier: (16.2 0x1c74b0128; 16.0 0x1c6034fe4)
// 16.2 also compares the interface orientation (frame AND orientation equal: a live resize update is dropped).
static void P1_StartScene(id self, SEL _cmd, id upd, id ident) {
    if (!P1_IsNew(self)) { ((void (*)(id, SEL, id, id))sOrigStartScene)(self, _cmd, upd, ident); return; }
    id entity = P1_S0(upd, "applicationSceneEntity");
    id scene = P1_S0(P1_S0(entity, "sceneHandle"), "sceneIfExists");
    if (scene) {
        id cs = P1_S0(scene, "settings"), ns = P1_S0(upd, "sceneSettings");
        if (P1_B1(self, "_sceneUpdateTransactionIsForLiveResize:", upd) && CGRectEqualToRect(P1_Rect0(cs, "frame"), P1_Rect0(ns, "frame")) && P1_L0(cs, "interfaceOrientation") == P1_L0(ns, "interfaceOrientation")) return;
    }
    id inProgress = P1_Ivar(self, "_sceneIdentifiersWithSceneUpdateTransactionsInProgress");
    if (ident && [inProgress respondsToSelector:@selector(addObject:)]) [inProgress addObject:ident];
    SEL add = sel_registerName("addChildTransaction:withSchedulingPolicy:");
    if ([self respondsToSelector:add]) ((void (*)(id, SEL, id, long long))objc_msgSend)(self, add, upd, 0);
    id vc = P1_S0(self, "switcherViewController");
    id overlays = P1_S0(vc, "liveContentOverlays");
    if (![overlays isKindOfClass:[NSDictionary class]]) return;
    for (id key in [(NSDictionary *)overlays allKeys]) {
        if (P1_L0(key, "type") != 0) continue;
        SEL ifr = sel_registerName("itemForLayoutRole:");
        id item = [key respondsToSelector:ifr] ? ((id (*)(id, SEL, long long))objc_msgSend)(key, ifr, 1) : nil;
        if (![P1_S0(item, "uniqueIdentifier") isEqual:ident]) continue;
        id overlay = [(NSDictionary *)P1_S0(vc, "liveContentOverlays") objectForKey:key];
        SEL set = sel_registerName("setContentReferenceSize:interfaceOrientation:");
        if ([overlay respondsToSelector:set]) {
            id ss = P1_S0(upd, "sceneSettings");
            ((void (*)(id, SEL, CGSize, long long))objc_msgSend)(overlay, set, P1_Rect0(ss, "frame").size, P1_L0(ss, "interfaceOrientation"));
        }
        break;
    }
}

// ------------------------------------------------------------------------------------------------ _acquireBackgroundingScenesDeactivationAssertionForTransitionRequest: (16.2 0x1c74b1168; 16.0 0x1c6035d64)
// The elements of the ACTIVE layout state of the request's display that the new layout no longer has keep their scenes alive until the transition ends.
static void P1_Acquire(id self, SEL _cmd, id request) {
    if (!P1_IsNew(self)) { ((void (*)(id, SEL, id))sOrigAcquire)(self, _cmd, request); return; }
    id sc = P1_SwitcherControllerForRequest(self, 0, request);
    id active = sc ? [P1_ActiveMap(self) objectForKey:sc] : nil;
    id elems = P1_S0(active, "elements");
    NSMutableSet *gone = [elems respondsToSelector:@selector(mutableCopy)] ? [elems mutableCopy] : nil;
    id newElems = P1_S0(P1_S0(P1_S0(request, "applicationContext"), "layoutState"), "elements");
    if (gone && newElems) [gone minusSet:newElems];
    if (![gone count]) return;
    id assertion = P1_S0(self, "backgroundingScenesDeactivationAssertion");
    P1_V0(assertion, "relinquish");
    assertion = P1_S0(self, "backgroundingScenesDeactivationAssertion");
    BOOL (^pred)(id, id) = ^BOOL(id scene, id settings) {                       // block 0x1c74b12e8
        for (id e in gone) {
            id h = P1_S0(P1_S0(P1_S0(e, "workspaceEntity"), "applicationSceneEntity"), "sceneHandle");
            id s = P1_S0(h, "sceneIfExists");
            if ([P1_S0(s, "identifier") isEqual:P1_S0(scene, "identifier")]) return YES;
        }
        return NO;
    };
    SEL acq = sel_registerName("acquireWithPredicate:transitionContext:");
    if ([assertion respondsToSelector:acq]) ((void (*)(id, SEL, id, id))objc_msgSend)(assertion, acq, pred, nil);
}

// ------------------------------------------------------------------------------------------------ ancillary requests
// +[SBMainWorkspaceTransitionRequest ancillaryTransitionRequestsForTransitionRequest:] 16.2 0x1c7892c18 (16.0: +[SBToAppsWorkspaceTransaction _ancillaryTransitionRequestsForTransitionRequest:]
// 0x1c63a4608, same body): every connected window scene's switcher controller may answer one ancillary request.
static NSSet *P1_AncillaryRequests(id request) {
    NSMutableSet *out = [NSMutableSet set];
    for (id scene in P1_ConnectedScenes()) {
        id r = P1_S1(P1_S0(scene, "switcherController"), "_ancillaryTransitionRequestForTransitionRequest:", request);
        if (r) [out addObject:r];
    }
    return out;
}
static id P1_NewLayoutTransaction(id request, id delegate) {
    Class lc = NSClassFromString(@"SBSceneLayoutWorkspaceTransaction");
    SEL two = sel_registerName("initWithTransitionRequest:delegate:"), one = sel_registerName("initWithTransitionRequest:");
    id t = nil;
    if ([lc instancesRespondToSelector:two]) t = G1B_INIT(id, id)([lc alloc], two, request, delegate);
    else if ([lc instancesRespondToSelector:one]) { t = G1B_INIT(id)([lc alloc], one, request); P1_V1(t, "setDelegate:", delegate); }
    P1_V1(t, "addObserver:", delegate);
    SEL so = sel_registerName("setOptions:");
    if ([t respondsToSelector:so]) ((void (*)(id, SEL, unsigned long long))objc_msgSend)(t, so, 6);
    return t;
}

// ------------------------------------------------------------------------------------------------ _runSceneLayoutTransactionForTransitionRequest:updateScenes: (16.2 0x1c72d771c; 16.0 0x1c5e651b0)
static void P1_InterruptAll(id self, id request) {
    NSMutableSet *anc = P1_Anc(self);
    for (id t in [anc allObjects]) P1_V1(t, "interruptForTransitionRequest:", request);
    [anc removeAllObjects];
}
static void P1_Run(id self, SEL _cmd, id request, BOOL updateScenes) {
    if (!P1_IsNew(self)) { ((void (*)(id, SEL, id, BOOL))sOrigRun)(self, _cmd, request, updateScenes); return; }
    id lt = P1_Ivar(self, "_sceneLayoutTransaction");
    if (lt) { P1_V1(lt, "interruptForTransitionRequest:", request); P1_SetIvar(self, "_sceneLayoutTransaction", nil); }
    if ([P1_Anc(self) count]) P1_InterruptAll(self, request);
    P1_V0(self, "_failRunningLayoutStateTransition");
    id coord = P1_CoordinatorOf(P1_S0(P1_S0(self, "switcherViewController"), "switcherController"));
    P1_VB(coord, "setLiveContentOverlayUpdatesSuspended:", !updateScenes);
    if (updateScenes) {
        id layout = P1_NewLayoutTransaction(request, self);
        P1_SetIvar(self, "_sceneLayoutTransaction", layout);
        NSSet *ancReqs = P1_AncillaryRequests(request);
        for (id r in ancReqs) { id t = P1_NewLayoutTransaction(r, self); if (t) [P1_Anc(self) addObject:t]; }
        P1_V1(self, "addChildTransaction:", layout);
        for (id t in [P1_Anc(self) allObjects]) P1_V1(self, "addChildTransaction:", t);
        NSMutableSet *all = [NSMutableSet setWithObject:request];
        [all unionSet:ancReqs];
        for (id r in all) {
            id sc = P1_SwitcherControllerForRequest(self, 0, r);
            id ls = P1_S0(P1_S0(r, "applicationContext"), "layoutState");
            if (sc && ls) [P1_ActiveMap(self) setObject:ls forKey:sc];
        }
        if (BP_LogEnabled()) BP_Log(@"p1: txn %p layout transaction for the request of %@ + %lu ancillary layout transaction(s) (displays: %@)", (__bridge void *)self, P1_Disp(P1_SwitcherControllerForRequest(self, 0, request)), (unsigned long)ancReqs.count, [[[ancReqs allObjects] valueForKey:@"displayIdentity"] description]);
    } else {
        P1_SetIvar(self, "_transitionRequest", request);                          // storeStrong of the SBWorkspaceTransaction ivar (16.2 0x1c72d7b4c)
    }
    if (!P1_IvarB(self, "_hasActiveLayoutStateTransitionCoordinatorTransition")) {
        P1_SetIvarB(self, "_hasActiveLayoutStateTransitionCoordinatorTransition", YES);
        P1_V1(P1_S0(self, "layoutStateTransitionCoordinator"), "beginTransitionForWorkspaceTransaction:", self);
    }
}

// ------------------------------------------------------------------------------------------------ transaction:performTransitionWithCompletion: (16.2 0x1c72dbcc0; 16.0 0x1c5e693b4)
// Completions of every layout transaction are collected and run when the animation controller completes. When the MAIN layout transaction starts and there are ancillary ones,
// the scenes of the layout elements of the request move to the scene manager of the request's display (block 0x1c74af9ac) and get the enhanced windowing flag.
static void P1_Perform(id self, SEL _cmd, id txn, void (^completion)(void)) {
    if (!P1_IsNew(self)) { ((void (*)(id, SEL, id, id))sOrigPerform)(self, _cmd, txn, completion); return; }
    if (P1_S0(self, "animationController")) { if (completion) [P1_Comp(self) addObject:[completion copy]]; }
    else if (completion) completion();
    if (P1_Ivar(self, "_sceneLayoutTransaction") != txn || ![P1_Anc(self) count]) return;
    id scene = P1_SceneForDisplay(P1_S0(txn, "displayIdentity"));
    id sc = P1_S0(scene, "switcherController");
    BOOL chamois = P1_B0(sc, "isChamoisWindowingUIEnabled");
    id sm = P1_S0(scene, "sceneManager");
    id elements = P1_S0(P1_S0(P1_S0(P1_S0(txn, "transitionRequest"), "applicationContext"), "layoutState"), "elements");
    id scm = P1_S0((id)NSClassFromString(@"SBSceneManagerCoordinator"), "sharedInstance");
    SEL take = sel_registerName("takeScene:fromSceneManager:");
    if (![elements conformsToProtocol:@protocol(NSFastEnumeration)]) return;
    for (id elem in (id<NSFastEnumeration>)elements) {
        NSString *uid = P1_S0(elem, "uniqueIdentifier");
        void (^blk)(id) = ^(id m) {
            if (m == sm) return;
            id scenes = P1_S0(m, "allScenes");
            if (![scenes conformsToProtocol:@protocol(NSFastEnumeration)]) return;
            for (id scn in (id<NSFastEnumeration>)scenes) {
                if (![P1_S0(scn, "identifier") isEqualToString:uid]) continue;
                if ([sm respondsToSelector:take]) ((void (*)(id, SEL, id, id))objc_msgSend)(sm, take, scn, m);
                else BP_Log(@"p1: scene manager has no takeScene:fromSceneManager:");
                id h = P1_S1(sm, "existingSceneHandleForScene:", scn);
                if ([h isKindOfClass:NSClassFromString(@"SBDeviceApplicationSceneHandle")]) P1_VB(h, "setWantsEnhancedWindowingEnabled:", chamois);
                if (BP_LogEnabled()) BP_Log(@"p1: scene %@ of window %@ taken over by the scene manager of %@", uid, m, P1_Disp(sc));
                return;
            }
        };
        P1_V1(scm, "enumerateSceneManagersWithBlock:", blk);
    }
}

// ------------------------------------------------------------------------------------------------ transactionDidComplete: (16.2 0x1c72dd5fc; 16.0 0x1c5e6aa38) + final root transaction completion block 0x1c74af778
static double P1_ArcSettle(void) {
    id root = P1_S0((id)NSClassFromString(@"SBAppSwitcherDomain"), "rootSettings");
    id arc = P1_S0(P1_S0(root, "animationSettings"), "arcSwipeSettings");
    return P1_Dbl(arc, "settlingDuration") * 0.9;
}
static void P1_TxnDidComplete(id self, SEL _cmd, id txn) {
    if (!P1_IsNew(self)) { ((void (*)(id, SEL, id))sOrigTxnDone)(self, _cmd, txn); return; }
    if (P1_S0(self, "animationController") == txn) {
        id ac = P1_Ivar(self, "_animationController");
        id wreq = P1_S0(ac, "workspaceTransitionRequest");
        void (^done)(BOOL) = P1_S0(wreq, "completionBlock");
        if (done) done(YES);
        P1_SetIvar(self, "_animationController", nil);
        P1_SetIvar(self, "_autoPIPWorkspaceTransaction", nil);
        if (P1_B0(txn, "isInterrupted")) return;
        SEL cp = sel_registerName("_copiedTransitionRequestFromTransitionRequest:");
        id copied = [self respondsToSelector:cp] ? ((id (*)(id, SEL, id))objc_msgSend)(self, cp, wreq) : nil;
        P1_VB(P1_S0(copied, "applicationContext"), "setAnimationDisabled:", YES);
        P1_VB(P1_S0(copied, "transientOverlayContext"), "setAnimated:", NO);
        P1_V0(copied, "finalize");
        id finalState = P1_S0(P1_S0(copied, "applicationContext"), "layoutState");
        P1_V1(self, "_updatePPTsForAnimationEndedWithFinalLayoutState:", finalState);
        P1_V1(self, "setSelectedAppLayout:", nil);
        id timer = P1_Ivar(self, "_activateScenesTimer");
        P1_V0(timer, "invalidate");
        P1_SetIvar(self, "_activateScenesTimer", nil);
        NSMutableArray *comps = P1_Comp(self);
        if (comps.count) {
            for (id o in [comps copy]) { void (^b)(void) = o; b(); }
            [comps removeAllObjects];
        } else {
            P1_V0(self, "_failRunningLayoutStateTransition");
        }
        id lt = P1_Ivar(self, "_sceneLayoutTransaction");
        if (lt) { P1_V1(lt, "interruptForTransitionRequest:", copied); P1_SetIvar(self, "_sceneLayoutTransaction", nil); }
        if ([P1_Anc(self) count]) P1_InterruptAll(self, copied);
        if (P1_L0(finalState, "unlockedEnvironmentMode") == 1) {
            id app = (id)[UIApplication sharedApplication];
            SEL io = sel_registerName("interfaceOrientationForCurrentDeviceOrientation:"), un = sel_registerName("updateNativeOrientationWithOrientation:updateMirroredDisplays:animated:logMessage:");
            if ([app respondsToSelector:io] && [app respondsToSelector:un])
                ((void (*)(id, SEL, long long, BOOL, BOOL, id))objc_msgSend)(app, un, ((long long (*)(id, SEL, BOOL))objc_msgSend)(app, io, NO), YES, YES, @"SBFluidSwitcherGestureWorkspaceTransaction completed transition to home screen");
        }
        id finalTxn = P1_S1(P1_S0(P1_S0(self, "transitionRequest"), "workspace"), "transactionForTransitionRequest:", copied);
        P1_SetIvar(self, "_finalRootTransaction", finalTxn);
        if ([finalTxn isKindOfClass:NSClassFromString(@"SBToAppsWorkspaceTransaction")]) P1_VB(finalTxn, "_setShouldSerialDismissOverlays:", NO);
        __weak id weakSelf = self;
        void (^completion)(BOOL) = ^(BOOL finished) {                                    // block 0x1c74af778
            id s = weakSelf;
            if (!s) return;
            long long st = P1_L0(P1_S0(s, "gestureRecognizer"), "state");
            if (!((unsigned long long)(st - 1) < 2) && !P1_S0(s, "animationController")) P1_VL(s, "finishWithCompletionType:", 1);
            else {
                id sc = P1_SwitcherControllerForRequest(s, 0, copied);
                id ls = P1_S0(sc, "layoutState");
                if (sc && ls) [P1_ActiveMap(s) setObject:ls forKey:sc];
            }
            P1_SetIvar(s, "_finalRootTransaction", nil);
        };
        P1_V1(finalTxn, "setCompletionBlock:", completion);
        id sc = P1_SwitcherControllerForRequest(self, 0, copied);
        if (sc && finalState) [P1_ActiveMap(self) setObject:finalState forKey:sc];
        P1_V1(self, "_addChildWorkspaceTransaction:", finalTxn);
        if (BP_LogEnabled()) BP_Log(@"p1: txn %p animation done, final root transaction %@ for %@", (__bridge void *)self, NSStringFromClass([finalTxn class]), P1_Disp(sc));
        return;
    }
    if (P1_Ivar(self, "_sceneLayoutTransaction") == txn) {
        P1_V0(P1_S0(self, "backgroundingScenesDeactivationAssertion"), "relinquish");
        P1_SetIvar(self, "_sceneLayoutTransaction", nil);
        return;
    }
    if ([P1_Anc(self) containsObject:txn]) [P1_Anc(self) removeObject:txn];
}

// ------------------------------------------------------------------------------------------------ SBSceneLayoutWorkspaceTransactionDelegate (16.2 0x1c72d51cc / 0x1c72d5260 / 0x1c74afb5c)
static id P1_ContextCoordinator(id ctx) {
    return P1_S0(P1_SceneForDisplay(P1_S0(ctx, "displayIdentity")), "layoutStateTransitionCoordinator");
}
static id P1_LayoutStateFor(id self, SEL _cmd, id ctx) {
    if (!P1_IsNew(self)) return ((id (*)(id, SEL, id))sOrigLayoutStateFor)(self, _cmd, ctx);
    id c = P1_ContextCoordinator(ctx);
    return c ? P1_S1(c, "layoutStateForApplicationTransitionContext:", ctx) : ((id (*)(id, SEL, id))sOrigLayoutStateFor)(self, _cmd, ctx);
}
static id P1_PrevLayoutStateFor(id self, SEL _cmd, id ctx) {
    if (!P1_IsNew(self)) return ((id (*)(id, SEL, id))sOrigPrevLayoutStateFor)(self, _cmd, ctx);
    id sc = P1_S0(P1_SceneForDisplay(P1_S0(ctx, "displayIdentity")), "switcherController");
    return sc ? [P1_ActiveMap(self) objectForKey:sc] : nil;
}
static BOOL P1_KeepForeground(id self, SEL _cmd, id txn, id scene, id __autoreleasing *reason) {
    if (P1_L0(self, "_gestureType") != 9) return NO;
    if (reason) *reason = @"window drag";
    return YES;
}

// ------------------------------------------------------------------------------------------------ handleTransitionRequestForGestureUpdate:fromGestureManager: (16.2 0x1c74afba4; 16.0 updateGestureWithTransitionRequest: 0x1c6034b4c)
static void P1_HandleUpdate(id self, SEL _cmd, id request, id manager) {
    if (!P1_IsNew(self)) { P1_V1(self, "updateGestureWithTransitionRequest:", request); return; }
    id sc = P1_S0(manager, "switcherController");
    if (BP_LogEnabled()) BP_Log(@"p1: txn %p update from the manager of %@ (own display %@), request layout %@", (__bridge void *)self, P1_Disp(sc), P1_Disp(P1_S0(P1_S0(self, "switcherViewController"), "switcherController")), P1_S0(request, "appLayout"));
    id wreq = P1_WorkspaceRequest(self, 0, request, manager, @"UpdateFluidSwitcherGestureAction");
    if (!wreq) return;
    id appCtx = P1_S0(wreq, "applicationContext");
    BOOL chamois = P1_B0(sc, "isChamoisWindowingUIEnabled");
    if (chamois && !P1_B0(appCtx, "isInLiveResize")) {
        void (^blk)(id) = ^(id c) { P1_ActivateAll(c); };
        P1_V1(wreq, "modifyApplicationContext:", blk);
        P1_V0(wreq, "finalize");
        P1_Run(self, 0, wreq, YES);
        return;
    }
    P1_V0(wreq, "finalize");
    id entities = P1_S0(P1_S0(wreq, "applicationContext"), "entities");
    if (![entities conformsToProtocol:@protocol(NSFastEnumeration)]) return;
    Class updC = NSClassFromString(@"SBApplicationSceneUpdateTransaction");
    for (id e in (id<NSFastEnumeration>)entities) {
        if (!P1_B0(e, "isApplicationSceneEntity")) continue;
        id upd = G1B_INIT(id, id)([updC alloc], sel_registerName("initWithApplicationSceneEntity:transitionRequest:"), e, wreq);
        id handle = P1_S0(e, "sceneHandle");
        id scene = P1_S0(handle, "sceneIfExists");
        id ident = P1_S0(scene, "identifier") ?: P1_S0(handle, "sceneIdentifier");
        BOOL isLR = P1_B1(self, "_sceneUpdateTransactionIsForLiveResize:", upd);
        CGRect cur = P1_Rect0(P1_S0(scene, "settings"), "frame");
        CGRect nw;
        if (P1_B0(e, "supportsPresentationAtAnySize")) {
            SEL ff = sel_registerName("frameForApplicationSceneEntity:");
            nw = [appCtx respondsToSelector:ff] ? ((CGRect (*)(id, SEL, id))objc_msgSend)(appCtx, ff, e) : CGRectZero;
        } else nw = P1_Rect0(P1_S0(upd, "sceneSettings"), "frame");
        long long curO = P1_L0(P1_S0(scene, "settings"), "interfaceOrientation");
        SEL ifo = sel_registerName("interfaceOrientationForElementIdentifier:");
        id ls = P1_S0(appCtx, "layoutState");
        long long newO = [ls respondsToSelector:ifo] ? ((long long (*)(id, SEL, id))objc_msgSend)(ls, ifo, P1_S0(e, "uniqueIdentifier")) : 0;
        SEL start = sel_registerName("_startSceneUpdateTransaction:forSceneIdentifier:");
        if (!scene) { ((void (*)(id, SEL, id, id))objc_msgSend)(self, start, upd, ident); continue; }
        BOOL appLR = P1_B0(appCtx, "isInLiveResize");
        if (!(!appLR || isLR)) {                                                 // live resize of the request, but not of this update: skip when nothing changes
            if (CGRectEqualToRect(cur, nw) && curO == newO) continue;
        }
        if (!isLR) { ((void (*)(id, SEL, id, id))objc_msgSend)(self, start, upd, ident); continue; }
        id inProgress = P1_Ivar(self, "_sceneIdentifiersWithSceneUpdateTransactionsInProgress");
        if (![inProgress containsObject:ident]) { ((void (*)(id, SEL, id, id))objc_msgSend)(self, start, upd, ident); continue; }
        NSMutableDictionary *pending = P1_Ivar(self, "_pendingSceneUpdateTransactionsBySceneIdentifier");
        if (ident && upd) { [pending removeObjectForKey:ident]; [pending setObject:upd forKey:ident]; }
    }
}

// ------------------------------------------------------------------------------------------------ handleTransitionRequestForGestureComplete:fromGestureManager: (16.2 0x1c74b0490; 16.0 completeGestureWithTransitionRequest: 0x1c603530c)
static void P1_HandleComplete(id self, SEL _cmd, id request, id manager) {
    if (!P1_IsNew(self)) { P1_V1(self, "completeGestureWithTransitionRequest:", request); return; }
    id appLayout = P1_S0(request, "appLayout");
    long long mode = P1_L0(request, "unlockedEnvironmentMode");
    long long fcfg = P1_L0(request, "floatingConfiguration");
    long long fvis = P1_L0(request, "floatingSwitcherVisible");
    id pending = P1_Ivar(self, "_pendingSceneUpdateTransactionsBySceneIdentifier");
    if ([pending respondsToSelector:@selector(removeAllObjects)]) [pending removeAllObjects];
    id sc = P1_S0(manager, "switcherController");
    if (BP_LogEnabled()) BP_Log(@"p1: txn %p complete from the manager of %@ (own display %@), request layout %@ mode %lld interrupted %d", (__bridge void *)self, P1_Disp(sc), P1_Disp(P1_S0(P1_S0(self, "switcherViewController"), "switcherController")), appLayout, mode, (int)P1_B0(self, "isInterrupted"));
    if (P1_B0(self, "isInterrupted")) return;
    id wreq = P1_WorkspaceRequest(self, 0, request, manager, @"FinalFluidSwitcherGestureAction");
    if (!wreq) return;
    P1_V0(wreq, "finalize");
    id coord = P1_CoordinatorOf(sc);
    id ac = P1_S1(coord, "animationControllerForTransitionRequest:", wreq);
    if (![ac isKindOfClass:NSClassFromString(@"SBUISwitcherAnimationController")]) ac = nil;
    P1_SetIvar(self, "_animationController", ac);
    if (!ac) { BP_Log(@"p1: txn %p: nil animationController from the coordinator of %@ (16.2 asserts here)", (__bridge void *)self, P1_Disp(sc)); return; }
    P1_V1(ac, "addObserver:", self);
    P1_V1(self, "addChildTransaction:", ac);
    P1_UpdateMain(self, 0, [NSSet setWithObject:wreq]);
    // 16.2 0x1c74b07b4 .. 0x1c74b0880: E = target layout empty (or Stage Manager mode 1), X = "not a window drag and the selected layout is not in the target"
    BOOL E, X = NO, A;
    if (mode == 2) A = YES; else A = P1_FlagYes(fvis);
    if (mode == 1) { E = YES; }
    else {
        id items = P1_S0(appLayout, "allItems");
        NSUInteger n = [items respondsToSelector:@selector(count)] ? [items count] : 0;
        E = (n == 0);
        if (!A && n != 0 && !P1_FloatingStashed(fcfg)) {
            id sel = P1_S0(self, "selectedAppLayout");
            if (!P1_B1(appLayout, "isOrContainsAppLayout:", sel)) X = (P1_L0(self, "_gestureType") != 9);
        }
    }
    id actx = P1_S0(wreq, "applicationContext");
    id ls = P1_S0(actx, "layoutState");
    id prev = P1_S0(P1_S0(wreq, "applicationContext"), "previousLayoutState");
    if (P1_PeekValid(P1_L0(prev, "peekConfiguration")) && !P1_PeekValid(P1_L0(ls, "peekConfiguration"))) {
        if ([sc respondsToSelector:sel_registerName("_dismissMedusaBanner")]) P1_V0(sc, "_dismissMedusaBanner");
        else P1_V0(sc, "_dismissMedusaEducationBanner");
    }
    BOOL updateScenes = YES;
    id ac2 = P1_Ivar(self, "_animationController");
    if (ac2 && (E || X)) {
        id vc = P1_S0(sc, "contentViewController");
        if (![vc isKindOfClass:NSClassFromString(@"SBFluidSwitcherViewController")]) vc = nil;
        if (P1_B1(vc, "shouldMorphToPIPForTransitionContext:", P1_S0(wreq, "applicationContext"))) {
            id apt = G1B_INIT(id)([NSClassFromString(@"SBAutoPIPWorkspaceTransaction") alloc], sel_registerName("initWithTransitionRequest:"), wreq);
            P1_SetIvar(self, "_autoPIPWorkspaceTransaction", apt);
            id ovc = P1_S0(P1_S0(P1_S0(wreq, "transientOverlayContext"), "transientOverlay"), "viewController");
            if (ovc) { void (^pipDone)(BOOL) = ^(BOOL ok) { if (ok) P1_V0(ovc, "handlePictureInPictureDidBegin"); }; P1_V1(apt, "setCompletionBlock:", pipDone); }
            P1_V1(self, "addChildTransaction:", apt);
        } else {
            Class aptc = NSClassFromString(@"SBAutoPIPWorkspaceTransaction");
            SEL should = sel_registerName("shouldAutoPIPEnteringBackgroundForRequest:reason:");
            if (P1_Ivar(self, "_autoPIPWorkspaceTransaction") ||
                ([aptc respondsToSelector:should] && ((BOOL (*)(id, SEL, id, long long))objc_msgSend)((id)aptc, should, wreq, 1))) {
                P1_VB(ac2, "_setInterruptible:", NO);
                updateScenes = NO;
            }
        }
    }
    P1_V1(self, "_acquireBackgroundingScenesDeactivationAssertionForTransitionRequest:", wreq);
    id origState = [P1_OrigMap(self) objectForKey:sc];
    id activeState = [P1_ActiveMap(self) objectForKey:sc];
    if (P1_L0(activeState, "unlockedEnvironmentMode") == 3 && P1_L0(appLayout, "type") == 0 && X && P1_Ivar(self, "_animationController")) {
        P1_Run(self, 0, wreq, NO);
        long long n = P1_IvarLL(self, "_numberOfAppLayoutsTraveledWithArcSwipe") + 1;
        if ([appLayout isEqual:P1_S0(origState, "appLayout")]) n = 0;
        P1_SetIvarLL(self, "_numberOfAppLayoutsTraveledWithArcSwipe", n);
        double delay = (double)((n > 1 ? n : 1) - 1) * 0.5 + 0.1;
        double settle = P1_ArcSettle();
        if (delay > settle) delay = settle;
        __weak id weakSelf = self;
        BOOL flag = updateScenes;
        void (^fire)(NSTimer *) = ^(NSTimer *t) {                                       // block 0x1c74b0d34
            id s = weakSelf;
            if (!s) return;
            P1_EnumerateValidRoles(^(long long role) {                                   // block 0x1c74b0de0
                id actx3 = P1_S0(wreq, "applicationContext");
                SEL efr = sel_registerName("entityForLayoutRole:");
                id e = [actx3 respondsToSelector:efr] ? ((id (*)(id, SEL, long long))objc_msgSend)(actx3, efr, role) : nil;
                if (!e) {
                    SEL set = sel_registerName("setEntity:forLayoutRole:");
                    id empty = P1_S0((id)NSClassFromString(@"SBEmptyWorkspaceEntity"), "entity");
                    if (empty && [actx3 respondsToSelector:set]) ((void (*)(id, SEL, id, long long))objc_msgSend)(actx3, set, empty, role);
                }
            });
            P1_Run(s, 0, wreq, flag);
        };
        id timer = [NSTimer scheduledTimerWithTimeInterval:delay repeats:NO block:fire];
        P1_V1(self, "setActivateScenesTimer:", timer);
        return;
    }
    P1_Run(self, 0, wreq, updateScenes);
}

// ------------------------------------------------------------------------------------------------ wrappers around 16.0 bodies that only gain the 16.2 clean-up
static __thread __unsafe_unretained id tBeginTxn, tInterruptReq;
// -_transitionRequestForApplicationTransitionContext:eventLabel: is called once at the start of -_beginWithGesture: with the label "InterruptingGesture": that request interrupts the
// previous transaction's parts (16.2 0x1c72cce68)
static id P1_ReqForContext(id self, SEL _cmd, id ctx, id label) {
    id r = ((id (*)(id, SEL, id, id))sOrigReqForCtx)(self, _cmd, ctx, label);
    if (tBeginTxn == self && [label isEqual:@"InterruptingGesture"]) tInterruptReq = r;
    return r;
}
// 16.2 interrupts every ancillary layout transaction with that request and clears the completions right before -_updateDigitizerSurfaceDimensions (0x1c72ccfb8 .. 0x1c72ccff0)
static void P1_Digitizer(id self, SEL _cmd) {
    if (tBeginTxn == self && tInterruptReq && P1_IsNew(self)) {
        P1_InterruptAll(self, tInterruptReq);
        [P1_Comp(self) removeAllObjects];
        tInterruptReq = nil;
    }
    ((void (*)(id, SEL))sOrigDigitizer)(self, _cmd);
}
static void P1_Begin(id self, SEL _cmd, id gesture) {
    id sb = tBeginTxn, sr = tInterruptReq;
    tBeginTxn = self; tInterruptReq = nil;
    ((void (*)(id, SEL, id))sOrigBegin)(self, _cmd, gesture);
    tBeginTxn = sb; tInterruptReq = sr;
}
static void P1_WillInterrupt(id self, SEL _cmd, id reason) {
    ((void (*)(id, SEL, id))sOrigWillInterrupt)(self, _cmd, reason);
    if (P1_IsNew(self)) [P1_Comp(self) removeAllObjects];                       // 16.2 0x1c74af110
}
// the 16.0 bodies un-suspend the live content overlay updates of the transaction's own view controller; 16.2 asks the coordinator, which does it for every display
static void P1_UnsuspendAll(id self) {
    if (!P1_IsNew(self)) return;
    id coord = P1_CoordinatorOf(P1_S0(P1_S0(self, "switcherViewController"), "switcherController"));
    P1_VB(coord, "setLiveContentOverlayUpdatesSuspended:", NO);
}
static void P1_Fail(id self, SEL _cmd) { ((void (*)(id, SEL))sOrigFail)(self, _cmd); P1_UnsuspendAll(self); }          // 16.2 0x1c72d7bc4
static void P1_TxnComplete(id self, SEL _cmd) { ((void (*)(id, SEL))sOrigDidComplete)(self, _cmd); P1_UnsuspendAll(self); }   // 16.2 0x1c72e16e0

// Stage Manager strip reveal transaction: 16.2 0x1c7420d34 = flag, then super
static void P1_RevealComplete(id self, SEL _cmd, id request, id manager) {
    P1_SetIvarB(self, "_completedGestureWithTransitionRequest", YES);
    P1_HandleComplete(self, _cmd, request, manager);
}

// ------------------------------------------------------------------------------------------------ SBFluidSwitcherGestureManager (16.2 0x1c78f17f0 / 0x1c78f17fc; 16.0 0x1c643fb94 / 0x1c643fb9c are bare thunks into the transaction)
static BOOL P1_TxnIsNew(id txn) { return txn && P1_IsNew(txn) && [txn respondsToSelector:sel_registerName("handleTransitionRequestForGestureUpdate:fromGestureManager:")]; }
static void P1_MgrUpdate(id self, SEL _cmd, id request) {
    id txn = P1_S0(self, "activeGestureTransaction");
    if (P1_TxnIsNew(txn)) { P1_S2(txn, "handleTransitionRequestForGestureUpdate:fromGestureManager:", request, self); return; }
    if (sOrigMgrUpdate) ((void (*)(id, SEL, id))sOrigMgrUpdate)(self, _cmd, request);
}
static void P1_MgrComplete(id self, SEL _cmd, id request) {
    id txn = P1_S0(self, "activeGestureTransaction");
    if (P1_TxnIsNew(txn)) {
        if ([P1_S0(request, "appLayout") isEqual:P1_S0((id)NSClassFromString(@"SBAppLayout"), "homeScreenAppLayout")])
            P1_V0(self, "_clearSystemApertureZStackPolicyAssistantSuppression");   // 16.2 only; absent on 16.0 and a no-op without the aperture (iPad)
        P1_S2(txn, "handleTransitionRequestForGestureComplete:fromGestureManager:", request, self);
        return;
    }
    if (sOrigMgrComplete) ((void (*)(id, SEL, id))sOrigMgrComplete)(self, _cmd, request);
}
// The manager that starts a transaction hands it to the coordinator, which gives it to the managers of all displays (16.2 block 0x1c78f37bc -> coordinator 0x1c76e2bd4)
static __thread int tBroadcast;
static void P1_MgrSetActive(id self, SEL _cmd, id txn) {
    if (txn && !tBroadcast && P1_On("p1_share") && P1_IsNew(txn)) {
        id coord = P1_CoordinatorOf(P1_S0(self, "switcherController"));
        SEL set = sel_registerName("setActiveGestureTransaction:");
        if (coord && [coord respondsToSelector:set]) {
            ((void (*)(id, SEL, id))objc_msgSend)(coord, set, txn);
            if (P1_S0(self, "activeGestureTransaction") == txn) return;
            BP_Log(@"p1: the coordinator did not hand the transaction to the starting manager, setting it directly (last-line guard)");   // e.g. no switcher controller enumeration
        }
    }
    ((void (*)(id, SEL, id))sOrigMgrSetActive)(self, _cmd, txn);
}

// ------------------------------------------------------------------------------------------------ SBMainSwitcherControllerCoordinator (16.2 0x1c76e2bd4 / 0x1c76e2164 / 0x1c76e2bcc / 0x1c76e2d00)
static char kP1CoordTxn, kP1CoordSuspended;
static NSArray *P1_AllControllers(id coord) {
    NSMutableArray *out = [NSMutableArray array];
    SEL en = sel_registerName("enumerateSwitcherControllersWithBlock:");
    if ([coord respondsToSelector:en]) {
        void (^blk)(id, BOOL *) = ^(id sc, BOOL *stop) { if (sc) [out addObject:sc]; };
        ((void (*)(id, SEL, id))objc_msgSend)(coord, en, blk);
    } else {
        id byScene = P1_Ivar(coord, "_switcherControllersByWindowScene");
        if ([byScene respondsToSelector:@selector(objectEnumerator)]) for (id sc in [byScene objectEnumerator]) [out addObject:sc];
    }
    return out;
}
static id P1_CoordActive(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kP1CoordTxn); }
static void P1_CoordSetActive(id self, SEL _cmd, id txn) {
    id old = objc_getAssociatedObject(self, &kP1CoordTxn);
    if (old == txn) return;
    P1_V1(old, "removeObserver:", self);
    objc_setAssociatedObject(self, &kP1CoordTxn, txn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    P1_V1(txn, "addObserver:", self);
    tBroadcast++;
    NSUInteger n = 0;
    for (id sc in P1_AllControllers(self)) { P1_V1(P1_S0(sc, "gestureManager"), "setActiveGestureTransaction:", txn); n++; }
    tBroadcast--;
    if (BP_LogEnabled()) BP_Log(@"p1: coordinator %@ gesture transaction %p to %lu gesture manager(s)", txn ? @"hands out" : @"clears the", (__bridge void *)txn, (unsigned long)n);
}
static void P1_CoordTxnDone(id self, SEL _cmd, id txn) {
    if (objc_getAssociatedObject(self, &kP1CoordTxn) == txn) P1_CoordSetActive(self, 0, nil);
}
static void P1_CoordSetSuspended(id self, SEL _cmd, BOOL suspended) {
    if ([objc_getAssociatedObject(self, &kP1CoordSuspended) boolValue] == suspended) return;
    objc_setAssociatedObject(self, &kP1CoordSuspended, @(suspended), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (id sc in P1_AllControllers(self)) {
        id vc = P1_S0(sc, "contentViewController");
        if ([vc isKindOfClass:NSClassFromString(@"SBFluidSwitcherViewController")]) P1_VB(vc, "setLiveContentOverlayUpdatesSuspended:", suspended);
    }
}

// ------------------------------------------------------------------------------------------------ SBSwitcherController
// -_currentLayoutState 16.2 0x1c7605754: the transaction's request counts only for the display it is for
static id P1_SCCurrentLayoutState(id self, SEL _cmd) {
    if (!P1_On("p1_share")) return ((id (*)(id, SEL))sOrigCurrentLayoutState)(self, _cmd);
    id txn = P1_S0(P1_S0(self, "gestureManager"), "activeGestureTransaction");
    id wreq = P1_S0(P1_S0(txn, "animationController"), "workspaceTransitionRequest");
    id cfg = P1_S0(wreq, "displayConfiguration");
    id own = P1_S0(P1_S0(self, "windowScene"), "_fbsDisplayConfiguration");
    if (wreq && [cfg isEqual:own]) return P1_S0(P1_S0(wreq, "applicationContext"), "layoutState");
    return P1_S0(self, "layoutState");
}
// -_ancillaryTransitionRequestForTransitionRequest: 16.2 0x1c76066fc (blocks 0x1c7606934 .. 0x1c7606c34; 16.0 0x1c617e6e0 works on unique identifiers and one entity per role):
// for a request of ANOTHER display, this display answers a request without the windows that moved away (its elements that the request's layout contains).
static id P1_SCAncillary(id self, SEL _cmd, id request) {
    if (!P1_On("p1_ancillary")) return ((id (*)(id, SEL, id))sOrigAncillary)(self, _cmd, request);
    id ws = P1_S0(self, "windowScene");
    if ([P1_S0(request, "displayIdentity") isEqual:P1_S0(ws, "_fbsDisplayIdentity")]) return nil;
    id reqElems = P1_S0(P1_S0(P1_S0(request, "applicationContext"), "layoutState"), "elements");
    id ownLS = P1_S0(self, "layoutState");
    id ownElems = P1_S0(ownLS, "elements");
    if (![ownElems conformsToProtocol:@protocol(NSFastEnumeration)] || ![reqElems conformsToProtocol:@protocol(NSFastEnumeration)]) return nil;
    NSMutableSet *gone = [NSMutableSet set];
    for (id e in (id<NSFastEnumeration>)ownElems)
        for (id r in (id<NSFastEnumeration>)reqElems)
            if (P1_B1(r, "representsSameLayoutElementAsDescriptor:", e)) { [gone addObject:e]; break; }
    if (!gone.count) return nil;
    Class rc = NSClassFromString(@"SBMainWorkspaceTransitionRequest");
    id nreq = G1B_INIT(id)([rc alloc], sel_registerName("initWithDisplayConfiguration:"), P1_S0(ws, "_fbsDisplayConfiguration"));
    void (^mod)(id) = ^(id ctx) {                                                // block 0x1c76069e0
        NSMutableSet *kept = [NSMutableSet set];
        P1_EnumerateValidRoles(^(long long role) {                               // block 0x1c7606b5c
            SEL ewr = sel_registerName("elementWithRole:");
            id e = [ownLS respondsToSelector:ewr] ? ((id (*)(id, SEL, long long))objc_msgSend)(ownLS, ewr, role) : nil;
            if (e && ![gone containsObject:e]) [kept addObject:e];
        });
        id center = nil, floating = nil;
        NSMutableSet *entities = [NSMutableSet set];
        for (id e in kept) {
            long long role = P1_L0(e, "layoutRole");
            if (role == 4 && !center) center = e;                                 // 16.2 constants 0x1c7a933b0 = 4, 0x1c7a933a8 = 3
            if (role == 3 && !floating) floating = e;
            id we = P1_S0(e, "workspaceEntity");
            if (we) [entities addObject:we];
        }
        SEL se = sel_registerName("setEntities:withPolicy:centerEntity:floatingEntity:");
        if ([ctx respondsToSelector:se]) ((void (*)(id, SEL, id, long long, id, id))objc_msgSend)(ctx, se, entities, 0, P1_S0(center, "workspaceEntity"), P1_S0(floating, "workspaceEntity"));
    };
    P1_V1(nreq, "modifyApplicationContext:", mod);
    if (BP_LogEnabled()) BP_Log(@"p1: ancillary request for %@: %lu window(s) moved away to %@", P1_Disp(self), (unsigned long)gone.count, P1_S0(request, "displayIdentity"));
    return nreq;
}
static BOOL P1_RepresentsSame(id self, SEL _cmd, id descriptor) {                  // SBLayoutElement 0x1c76f8374 / SBWorkspaceEntity 0x1c7899d70
    return [P1_S0(self, "uniqueIdentifier") isEqualToString:P1_S0(descriptor, "uniqueIdentifier")];
}
static id P1_ClsAncillary(id self, SEL _cmd, id request) { return P1_AncillaryRequests(request); }
static void P1_SCDismissBanner(id self, SEL _cmd) { P1_V0(self, "_dismissMedusaEducationBanner"); }      // 16.2 renamed _dismissMedusaEducationBanner (0x1c617e030) to _dismissMedusaBanner (0x1c7605f14)

// ------------------------------------------------------------------------------------------------ SBFluidSwitcherViewController: M1 / M7
// M1 -gestureHandlingModifierRequestsUpdate: 16.2 0x1c7452bdc: [self handleFluidSwitcherGestureManager:[[self switcherController] gestureManager] didUpdateGesture:[[self layoutContext] activeGesture]]
// (16.0 0x1c5fd9860 called handleGestureDidUpdate: directly: the 16.2 entry converts a neighbouring display's window drag event into this display's coordinates first)
static void P1_VCModUpdate(id self, SEL _cmd, id modifier) {
    SEL h = sel_registerName("handleFluidSwitcherGestureManager:didUpdateGesture:");
    if (!P1_On("p1_modupdate") || ![self respondsToSelector:h]) { ((void (*)(id, SEL, id))sOrigGestureModUpdate)(self, _cmd, modifier); return; }
    id mgr = P1_S0(P1_S0(self, "switcherController"), "gestureManager");
    id gesture = P1_S0(P1_S0(self, "layoutContext"), "activeGesture");
    ((void (*)(id, SEL, id, id))objc_msgSend)(self, h, mgr, gesture);
}
// M7 -_updateAsyncRenderingAndResizesHostedContext 16.2 0x1c745929c (16.0 0x1c5fdffb4). Per live content overlay: async rendering is switched off for a layout that is being dragged
// (coordinator draggingAppLayouts) and a hosted content that is not asynchronously rendered resizes with the container whenever Stage Manager is on (16.0: whatever the modifier says).
static void P1_VCAsync(id self, SEL _cmd) {
    if (!P1_On("p1_asyncdrag")) { ((void (*)(id, SEL))sOrigAsyncRendering)(self, _cmd); return; }
    id sc = P1_S0(self, "switcherController");
    id dragging = P1_S0(P1_CoordinatorOf(sc), "draggingAppLayouts");
    id overlays = P1_Ivar(self, "_liveContentOverlays");
    if (![overlays isKindOfClass:[NSDictionary class]]) return;
    id adjustedMap = P1_Ivar(self, "_leafAppLayoutsToAdjustedAppLayouts");
    id root = P1_Ivar(self, "_rootModifier");
    BOOL disabled = P1_IvarB(self, "_asyncRenderingDisabled");
    BOOL chamois = P1_B0(self, "isChamoisWindowingUIEnabled");
    SEL asyncA = sel_registerName("asyncRenderingAttributesForAppLayout:"), wantsR = sel_registerName("wantsSceneResizesHostedContextForAppLayout:");
    SEL setAR = sel_registerName("setAsyncRenderingEnabled:withMinificationFilterEnabled:"), setRH = sel_registerName("setResizesHostedContext:");
    for (id key in [(NSDictionary *)overlays allKeys]) {
        id overlay = [(NSDictionary *)overlays objectForKey:key];
        id adjusted = [adjustedMap respondsToSelector:@selector(objectForKey:)] ? [adjustedMap objectForKey:key] : nil;
        BOOL min = NO, async = NO, resizes = chamois;
        if (disabled) {
            if ([root respondsToSelector:wantsR]) (void)((BOOL (*)(id, SEL, id))objc_msgSend)(root, wantsR, adjusted);
        } else {
            unsigned long long attrs = [root respondsToSelector:asyncA] ? ((unsigned long long (*)(id, SEL, id))objc_msgSend)(root, asyncA, adjusted) : 0;
            min = (attrs >> 8) & 1;
            BOOL wants = [root respondsToSelector:wantsR] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(root, wantsR, adjusted) : NO;
            if ((attrs & 1) && wants) {
                BP_Log(@"p1: async rendering and resizing hosted content both requested for %@ (16.2 logs this error and renders synchronously)", key);
            } else if (attrs & 1) {
                async = ![dragging containsObject:key];
                resizes = async ? NO : chamois;
            }
        }
        if ([overlay respondsToSelector:setAR]) ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(overlay, setAR, async, min);
        if ([overlay respondsToSelector:setRH]) ((void (*)(id, SEL, BOOL))objc_msgSend)(overlay, setRH, resizes);
    }
}

// ------------------------------------------------------------------------------------------------ installation
static IMP P1_Replace(const char *cls, const char *sel, IMP imp, IMP *orig) {
    Class c = NSClassFromString([NSString stringWithUTF8String:cls]);
    SEL s = sel_registerName(sel);
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) { BP_Log(@"p1: %s -%s not found, not replaced", cls, sel); return NULL; }
    IMP prev = method_getImplementation(m);
    if (orig) *orig = prev;
    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
    return prev;
}
static void P1_Add(const char *cls, const char *sel, IMP imp, const char *types, BOOL replaceExisting) {
    Class c = NSClassFromString([NSString stringWithUTF8String:cls]);
    if (!c) { BP_Log(@"p1: class %s missing, -%s not added", cls, sel); return; }
    SEL s = sel_registerName(sel);
    if (!class_addMethod(c, s, imp, types) && replaceExisting) class_replaceMethod(c, s, imp, types);   // G1C's forwarders for the 16.2 transaction names are replaced
}

void P1Drag_Setup(void) {
    if (!BP_OnName("p1_drag")) { BP_Log(@"p1: switch p1_drag is off at launch: the 16.0 gesture transaction stays (transactions created later still honour the switches)"); }
    const char *T = "SBFluidSwitcherGestureWorkspaceTransaction", *M = "SBFluidSwitcherGestureManager", *C = "SBMainSwitcherControllerCoordinator", *S = "SBSwitcherController", *V = "SBFluidSwitcherViewController";
    P1_Replace(T, "initWithTransitionRequest:fluidSwitcherViewController:delegate:", (IMP)P1_Init, &sOrigInit);
    P1_Replace(T, "_beginWithGesture:", (IMP)P1_Begin, &sOrigBegin);
    P1_Replace(T, "_transitionRequestForApplicationTransitionContext:eventLabel:", (IMP)P1_ReqForContext, &sOrigReqForCtx);
    P1_Replace(T, "_updateDigitizerSurfaceDimensions", (IMP)P1_Digitizer, &sOrigDigitizer);
    P1_Replace(T, "_willInterruptWithReason:", (IMP)P1_WillInterrupt, &sOrigWillInterrupt);
    P1_Replace(T, "_didComplete", (IMP)P1_TxnComplete, &sOrigDidComplete);
    P1_Replace(T, "_failRunningLayoutStateTransition", (IMP)P1_Fail, &sOrigFail);
    P1_Replace(T, "_runSceneLayoutTransactionForTransitionRequest:updateScenes:", (IMP)P1_Run, &sOrigRun);
    P1_Replace(T, "transaction:performTransitionWithCompletion:", (IMP)P1_Perform, &sOrigPerform);
    P1_Replace(T, "transactionDidComplete:", (IMP)P1_TxnDidComplete, &sOrigTxnDone);
    P1_Replace(T, "_startSceneUpdateTransaction:forSceneIdentifier:", (IMP)P1_StartScene, &sOrigStartScene);
    P1_Replace(T, "_acquireBackgroundingScenesDeactivationAssertionForTransitionRequest:", (IMP)P1_Acquire, &sOrigAcquire);
    P1_Replace(T, "layoutStateForApplicationTransitionContext:", (IMP)P1_LayoutStateFor, &sOrigLayoutStateFor);
    P1_Replace(T, "previousLayoutStateForApplicationTransitionContext:", (IMP)P1_PrevLayoutStateFor, &sOrigPrevLayoutStateFor);
    P1_Add(T, "handleTransitionRequestForGestureUpdate:fromGestureManager:", (IMP)P1_HandleUpdate, "v32@0:8@16@24", YES);
    P1_Add(T, "handleTransitionRequestForGestureComplete:fromGestureManager:", (IMP)P1_HandleComplete, "v32@0:8@16@24", YES);
    P1_Add(T, "_workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel:", (IMP)P1_WorkspaceRequest, "@40@0:8@16@24@32", NO);
    P1_Add(T, "_updateMainDisplayIfNecessaryForWorkspaceTransitionRequests:", (IMP)P1_UpdateMain, "v24@0:8@16", NO);
    P1_Add(T, "_windowSceneForWorkspaceTransitionRequest:", (IMP)P1_WindowSceneForRequest, "@24@0:8@16", NO);
    P1_Add(T, "_switcherControllerForWorkspaceTransitionRequest:", (IMP)P1_SwitcherControllerForRequest, "@24@0:8@16", NO);
    P1_Add(T, "transaction:shouldKeepSceneForeground:withReason:", (IMP)P1_KeepForeground, "B40@0:8@16@24^@32", NO);
    P1_Add("SBRevealContinuousExposeStripsGestureWorkspaceTransaction", "handleTransitionRequestForGestureComplete:fromGestureManager:", (IMP)P1_RevealComplete, "v32@0:8@16@24", YES);

    P1_Replace(M, "updateGestureWithTransitionRequest:", (IMP)P1_MgrUpdate, &sOrigMgrUpdate);
    P1_Replace(M, "completeGestureWithTransitionRequest:", (IMP)P1_MgrComplete, &sOrigMgrComplete);
    P1_Replace(M, "setActiveGestureTransaction:", (IMP)P1_MgrSetActive, &sOrigMgrSetActive);
    P1_Add(M, "handleTransitionRequestForGestureUpdate:", (IMP)P1_MgrUpdate, "v24@0:8@16", NO);
    P1_Add(M, "handleTransitionRequestForGestureComplete:", (IMP)P1_MgrComplete, "v24@0:8@16", NO);

    P1_Add(C, "setActiveGestureTransaction:", (IMP)P1_CoordSetActive, "v24@0:8@16", NO);
    P1_Add(C, "activeGestureTransaction", (IMP)P1_CoordActive, "@16@0:8", NO);
    P1_Add(C, "transactionDidComplete:", (IMP)P1_CoordTxnDone, "v24@0:8@16", NO);
    P1_Add(C, "setLiveContentOverlayUpdatesSuspended:", (IMP)P1_CoordSetSuspended, "v20@0:8B16", NO);

    P1_Replace(S, "_currentLayoutState", (IMP)P1_SCCurrentLayoutState, &sOrigCurrentLayoutState);
    P1_Replace(S, "_ancillaryTransitionRequestForTransitionRequest:", (IMP)P1_SCAncillary, &sOrigAncillary);
    P1_Add(S, "_dismissMedusaBanner", (IMP)P1_SCDismissBanner, "v16@0:8", NO);
    P1_Add("SBLayoutElement", "representsSameLayoutElementAsDescriptor:", (IMP)P1_RepresentsSame, "B24@0:8@16", NO);
    P1_Add("SBWorkspaceEntity", "representsSameLayoutElementAsDescriptor:", (IMP)P1_RepresentsSame, "B24@0:8@16", NO);
    Class mr = NSClassFromString(@"SBMainWorkspaceTransitionRequest");
    if (mr && !class_getClassMethod(mr, sel_registerName("ancillaryTransitionRequestsForTransitionRequest:")))
        class_addMethod(object_getClass(mr), sel_registerName("ancillaryTransitionRequestsForTransitionRequest:"), (IMP)P1_ClsAncillary, "@24@0:8@16");

    P1_Replace(V, "gestureHandlingModifierRequestsUpdate:", (IMP)P1_VCModUpdate, &sOrigGestureModUpdate);
    P1_Replace(V, "_updateAsyncRenderingAndResizesHostedContext", (IMP)P1_VCAsync, &sOrigAsyncRendering);
    BP_Log(@"p1: installed (transaction %p, manager %p, coordinator %p)", (__bridge void *)NSClassFromString([NSString stringWithUTF8String:T]), (__bridge void *)NSClassFromString([NSString stringWithUTF8String:M]), (__bridge void *)NSClassFromString([NSString stringWithUTF8String:C]));
}

#pragma clang diagnostic pop
