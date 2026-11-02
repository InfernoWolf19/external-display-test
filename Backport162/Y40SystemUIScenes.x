// Y40SystemUIScenes.x : S1 system UI scene family, steps 5 and 6 (DELTA-SWEEP-0.7.9.md Pass 4 section 1): SBSystemUISceneController with the scene vending policy, the Input / Overlay / AccessibilityUIServer
// controller changes, the two controller classes that exist only in 16.2 (SBEyedropperUISceneController, SBMomentsUISceneController) and the data driven SBSystemUIScenesCoordinator of 16.2.
// Setup: constructor.  Log prefix "[y40]".  Switches: y40_sysui (controllers, coordinator; default ON, kill file Backport162.off.y40_sysui), y40_traitsroles (the two new traits roles in the four role
// lists, kill file Backport162.off.y40_traitsroles).  The coordinator -init is replaced LAST and only when every class / selector / symbol this file needs exists (each missing one is named by a BP_Anomaly
// "y40-install ... NOT installed ... needs ..."); with the kill file the 16.0 -init (and so the 16.0 construction of the controllers) is called.
//
// 16.2 SBSystemUISceneController (16.0 in brackets; 16.2 adds the ivars _clientProcess FBProcess, _sceneVendingPolicy, _sceneWorkspaceControllerDelegate: associated objects here, the 16.0 ivars are used by name):
//   -initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level: 0x1c7965d48 [0x1c64ad968 without the policy]: [super init], copies of jobLabel / traitsRole,
//   _sceneControllers = [NSMutableArray array], _sceneControllersByWindowScene = [NSMapTable weakToStrongObjectsMapTable] (keyed by the DISPLAY IDENTITY now), _sceneWorkspaceControllerDelegate =
//   [SBFSceneWorkspaceDefaultDelegate new], _sceneWorkspaceController = [[SBFSceneWorkspaceController alloc] initWithIdentifier:delegate:] (the delegate is the controller's delegate, Y38SceneWorkspace.x), policy 1:
//   _clientProcess = [[FBProcessManager sharedInstance] processForIdentity:], [_clientProcess addObserver:self], [FBProcessManager addObserver:self]; the state capture "SpringBoard - SystemUISceneController - %@";
//   -dealloc 0x1c796614c removes the observers first; -windowSceneDidConnect: 0x1c79661cc (map key = [scene _fbsDisplayIdentity]; policy 1 vends scenes for a new display only when controllers already exist; the
//   scene options of the first non empty controller array are the blueprint of the new ones); -windowSceneDidDisconnect: 0x1c796647c -> NEW -_invalidateSceneControllersForWindowScene: 0x1c79668d4;
//   NEW -_newAppSceneRequestOptionsForWindowScene:withBlueprintOptions: 0x1c7966748 (UISceneRequestOptions: identifier, specification of the blueprint or a UIApplicationSceneSpecification, actions);
//   -__newSceneIdentifierForWindowScene: 0x1c7966834 ("SystemUIScene-[jobLabel] - display - generation"); NEW -_newSceneControllerForWindowScene:withSceneRequestOptions: 0x1c79668c8;
//   -_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level: 0x1c7966524 (SBSingleSceneController, setShouldForegroundForDisplayConfiguration:YES, setShouldActivateUponClientConnection:YES, kept in the
//   map under [[cfg identity]] and in _sceneControllers); -createSceneForProcessIdentity:withOptions:completion: 0x1c7966a6c (at most 5 scenes per display, error code 3; setSceneActive:YES; completion(scene, nil));
//   -destroyScenesWithPersistentIdentifiers:processIdentity:completion: 0x1c7966de0 (UIDestroySceneAction sent through _clientProcess's workspace; error code 2 with the unknown identifiers);
//   NEW -processManager:didAddProcess: 0x1c7967744, -processManager:didRemoveProcess: 0x1c79677cc, -processDidExit: 0x1c7967538 (main queue: every connected window scene's controllers invalidated);
//   NEW -sceneVendingPolicy 0x1c7967abc, -sceneWorkspaceControllerDelegate 0x1c7967adc / set 0x1c7967ae4, -setSceneControllersByWindowScene: 0x1c7967af8, -description / -debugDescription 0x1c7967850 / 0x1c7967854;
//   -descriptionBuilderWithMultilinePrefix: 0x1c7967950 (Traits Role, then one body section: Client Process Identity, Scene Workspace Controller, "Scene controllers by window scene" dictionary section).
//   The 16.0 only methods (_createNewSceneControllerForWindowScene:withSceneRequestOptions: and the four _newAppSceneRequestOptions... variants) stay on the class and are not called by anything that is ported.
//   -sceneWorkspaceControllerForProcessIdentity: 0x1c7967488 is the 16.0 body plus an assertion on nil (a nil identity is announced by the coordinator port below).
// Subclasses: SBInputUISceneController 0x1c7422458 (new init with the policy, keyboard observers + -_createInputUIScene 0x1c7422608: UISceneRequestOptions, setShouldBeKeptActiveWhileForeground:YES instead of
//   setShouldActivateUponClientConnection:NO); SBOverlayUISceneController -windowSceneDidConnect: 0x1c7950d50 (UISceneRequestOptions, controller kept in _subterraneanScene, setSceneActive:YES; no windowSceneDidDisconnect:
//   override any more: the base class one); SBAccessibilityUIServerUISceneController +_setupInfo 0x1c73347e0 (vendingStrategy 1) and NEW -_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:
//   0x1c7334940 (super, then setShouldActivateUponClientConnection:NO); NEW SBEyedropperUISceneController +_setupInfo 0x1c779f7f0, SBMomentsUISceneController +_setupInfo 0x1c75a3228 (runtime classes).
// SBSystemUIScenesCoordinator 0x1c77a8f64: +_sceneControllersConfigurations 0x1c77a86ac (11 dictionaries: the +_setupInfo of Druid, Overlay, Input, Ensemble, Eyedropper, Moments, AccessibilityUIServer, AssistiveTouch,
//   LiveTranscription, FullKeyboardAccess, VoiceControl + "setter" + "processIdentity" = identityForDaemonJobLabel: / identityForAngelJobLabel: by "isDaemon"), +_allKnownProcessIdentities 0x1c77a8d58,
//   +isSystemUISceneClientPID: 0x1c77a928c, +isSystemUISceneClientIdentity: 0x1c77a930c, -init (loops the table: enabled, class, jobLabel, traitsRole, workspaceID, setter, hostLevel (float) or
//   UISpringBoardLockScreenWindowLevel + 255, processIdentity, vendingStrategy; initWithSceneWorkspaceIdentifier:...sceneVendingPolicy:...; performSelector:setter; _sceneControllers addObject:), NEW eyedropper /
//   moments controller accessors (associated objects: the 16.0 class has no such ivars).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Wformat-nonliteral"

static char kY40New, kY40Policy, kY40Process, kY40Delegate, kY40Eye, kY40Moments;
#define Y40_NEWRET __attribute__((ns_returns_retained))
#define Y40_CONSUMED __attribute__((ns_consumed))
#define ADD(c, sel, imp, types) class_addMethod((c), sel_registerName(sel), (IMP)(imp), (types))
#define Y40_GET(o, k) objc_getAssociatedObject((o), &(k))
#define Y40_SET(o, k, v) objc_setAssociatedObject((o), &(k), (v), OBJC_ASSOCIATION_RETAIN_NONATOMIC)

static Class gY40Base, gY40Single, gY40Coord;
static IMP gY40Dealloc, gY40Connect, gY40Disconnect, gY40NewCtl, gY40NewId, gY40DescBuilder, gY40Create, gY40Destroy;
static IMP gY40InputCreate, gY40OverlayConnect, gY40AXSetup, gY40CoordInit;
static double *gY40LockLevel;                                                                  // UISpringBoardLockScreenWindowLevel
static double *gY40NormalLevel;                                                                // UIWindowLevelNormal
static BOOL (*gY40Feature)(const char *, const char *);                                         // __os_feature_enabled_impl
static id (*gY40StateCapture)(dispatch_queue_t, NSString *, id);                               // BSLogAddStateCaptureBlockWithTitle
static BOOL Y40_On(void) { return BP_OnName("y40_sysui"); }
static BOOL Y40_Flag(id o) { return o && [Y40_GET(o, kY40New) boolValue]; }
static long long Y40_Policy(id o) { return [Y40_GET(o, kY40Policy) longLongValue]; }

// ------------------------------------------------------------------------------------------------ ivar helpers (16.0 layout, by name)
static void *Y40_Slot(id o, const char *name, BOOL announce) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) { if (announce) BP_Anomaly("y40-ivar", @"ivar %s missing on %s", name, o ? class_getName(object_getClass(o)) : "nil"); return NULL; }
    return (char *)(__bridge void *)o + ivar_getOffset(iv);
}
static id Y40_Obj(id o, const char *name) { return BPX_IvarObj(o, name); }
static void Y40_SetObj(id o, const char *name, id v) { Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL; if (iv) object_setIvar(o, iv, v); else BP_Anomaly("y40-ivar", @"ivar %s missing on %s", name, o ? class_getName(object_getClass(o)) : "nil"); }
static void Y40_SetDouble(id o, const char *name, double v) { double *p = (double *)Y40_Slot(o, name, YES); if (p) *p = v; }
static unsigned long long Y40_NextGeneration(id o) { unsigned long long *p = (unsigned long long *)Y40_Slot(o, "_sceneIDGeneration", YES); return p ? ++*p : 0; }
static id Y40_Send0(id o, const char *sel) { SEL s = sel_registerName(sel); return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static id Y40_Class(const char *n) { return (id)objc_getClass(n); }
static id Y40_PM(void) { return BPX_Obj0(Y40_Class("FBProcessManager"), "sharedInstance"); }
static id Y40_DisplayIdentity(id windowScene) { return Y40_Send0(windowScene, "_fbsDisplayIdentity"); }

// ------------------------------------------------------------------------------------------------ SBSystemUISceneController
// -initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level: 0x1c7965d48
static Y40_NEWRET id Y40_BaseInit(Y40_CONSUMED id self, SEL _cmd, id wsid, id identity, long long policy, id role, id label, double level) {
    if (!wsid || !identity || !role) { BP_Anomaly("y40-init", @"SBSystemUISceneController init with a nil workspace identifier / client identity / traits role (16.2 asserts, lines 75..77)"); return nil; }
    struct objc_super sup = { self, class_getSuperclass(gY40Base) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (!me) return nil;
    Y40_SetDouble(me, "_level", level);
    Y40_SetObj(me, "_jobLabel", [label copy]);
    Y40_SetObj(me, "_traitsRole", [role copy]);
    Y40_SET(me, kY40Policy, @(policy));
    Y40_SetObj(me, "_sceneControllers", [NSMutableArray array]);
    Y40_SetObj(me, "_clientProcessIdentity", identity);
    Y40_SetObj(me, "_sceneControllersByWindowScene", [NSMapTable weakToStrongObjectsMapTable]);
    Class dc = objc_getClass("SBFSceneWorkspaceDefaultDelegate");
    id delegate = dc ? [[dc alloc] init] : nil;
    if (!delegate) BP_Anomaly("y40-init", @"SBFSceneWorkspaceDefaultDelegate (Y38SceneWorkspace.x) is missing: the workspace controller gets no 16.2 delegate");
    Y40_SET(me, kY40Delegate, delegate);
    Class wc = objc_getClass("SBFSceneWorkspaceController");
    id ctl = ((Y40_NEWRET id (*)(Y40_CONSUMED id, SEL, id, id))objc_msgSend)([wc alloc], sel_registerName("initWithIdentifier:delegate:"), wsid, delegate);
    Y40_SetObj(me, "_sceneWorkspaceController", ctl);
    if (policy == 1) {
        id pm = Y40_PM();
        id proc = BPX_Obj1(pm, "processForIdentity:", identity);
        Y40_SET(me, kY40Process, proc);
        if (proc) BPX_SetObj1(proc, "addObserver:", me);
        BPX_SetObj1(pm, "addObserver:", me);
    }
    if (gY40StateCapture) {
        __weak id w = me;
        id inv = gY40StateCapture(dispatch_get_main_queue(), [NSString stringWithFormat:@"SpringBoard - SystemUISceneController - %@", wsid], ^id{
            id s = w;
            return s ? ((id (*)(id, SEL, id))objc_msgSend)(s, sel_registerName("descriptionWithMultilinePrefix:"), nil) : nil;
        });
        Y40_SetObj(me, "_stateCaptureInvalidatable", inv);
    }
    Y40_SET(me, kY40New, @YES);
    BPY_LOG(@"[y40] %@ controller %@ (job %@, policy %lld, level %g)", NSStringFromClass(object_getClass(me)), wsid, label, policy, level);
    return me;
}
// -dealloc 0x1c796614c: the observers go first, then the 16.0 body (invalidates the state capture and the workspace controller, super dealloc)
static void Y40_Dealloc(id self, SEL _cmd) {
    if (Y40_Flag(self)) {
        BPX_SetObj1(Y40_PM(), "removeObserver:", self);
        id proc = Y40_GET(self, kY40Process);
        if (proc) BPX_SetObj1(proc, "removeObserver:", self);
    }
    if (gY40Dealloc) ((void (*)(id, SEL))gY40Dealloc)(self, _cmd);
}
static id Y40_SinglesOfFirstBlueprint(id self) {
    id map = Y40_Obj(self, "_sceneControllersByWindowScene");
    for (id arr in BP_AsArray([[map objectEnumerator] allObjects])) if ([arr count]) return arr;                    // block 0x1c7966458: count != 0
    return nil;
}
// -_newAppSceneRequestOptionsForWindowScene:withBlueprintOptions: 0x1c7966748 (new family: +1)
static Y40_NEWRET id Y40_NewOptions(id self, SEL _cmd, id windowScene, id blueprint) {
    Class oc = objc_getClass("UISceneRequestOptions");
    if (!oc) { BP_Anomaly("y40-options", @"UISceneRequestOptions missing: the scene options cannot be built"); return nil; }
    id o = [[oc alloc] init];
    NSString *sid = ((Y40_NEWRET id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("__newSceneIdentifierForWindowScene:"), windowScene);
    BPX_SetObj1(o, "setIdentifier:", sid);
    id spec = Y40_Send0(blueprint, "specification");
    if (!spec) spec = [[NSClassFromString(@"UIApplicationSceneSpecification") alloc] init];
    BPX_SetObj1(o, "setSpecification:", spec);
    BPX_SetObj1(o, "setActions:", Y40_Send0(blueprint, "actions"));
    return o;
}
// -__newSceneIdentifierForWindowScene: 0x1c7966834
static Y40_NEWRET id Y40_NewSceneId(id self, SEL _cmd, id windowScene) {
    if (!Y40_Flag(self)) return gY40NewId ? ((Y40_NEWRET id (*)(id, SEL, id))gY40NewId)(self, _cmd, windowScene) : nil;
    unsigned long long gen = Y40_NextGeneration(self);
    return [NSString stringWithFormat:@"SystemUIScene-[%@] - %@ - %lu", Y40_Obj(self, "_jobLabel"), [Y40_DisplayIdentity(windowScene) description], (unsigned long)gen];
}
// -_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level: 0x1c7966524
static Y40_NEWRET id Y40_NewCtl(id self, SEL _cmd, id windowScene, id options, id role, double level) {
    if (!Y40_Flag(self)) return gY40NewCtl ? ((Y40_NEWRET id (*)(id, SEL, id, id, id, double))gY40NewCtl)(self, _cmd, windowScene, options, role, level) : nil;
    if (!windowScene || !options || !role) { BP_Anomaly("y40-newctl", @"_newSceneControllerForWindowScene:... with a nil window scene / options / role (16.2 asserts, lines 151..153)"); return nil; }
    id cfg = Y40_Send0(windowScene, "_fbsDisplayConfiguration");
    id ident = Y40_Send0(cfg, "identity");
    id ctl = ((Y40_NEWRET id (*)(Y40_CONSUMED id, SEL, id, id, id, id, id, double))objc_msgSend)([gY40Single alloc],
        sel_registerName("initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level:"), cfg, Y40_Obj(self, "_sceneWorkspaceController"), options, Y40_Obj(self, "_clientProcessIdentity"), role, level);
    BPX_SetBool1(ctl, "setShouldForegroundForDisplayConfiguration:", YES);
    BPX_SetBool1(ctl, "setShouldActivateUponClientConnection:", YES);
    NSMapTable *map = Y40_Obj(self, "_sceneControllersByWindowScene");
    NSMutableArray *arr = ident ? [map objectForKey:ident] : nil;
    if (arr) [arr addObject:ctl];
    else if (ident) [map setObject:[NSMutableArray arrayWithObject:ctl] forKey:ident];
    [(NSMutableArray *)Y40_Obj(self, "_sceneControllers") addObject:ctl];
    return ctl;
}
// -_newSceneControllerForWindowScene:withSceneRequestOptions: 0x1c79668c8 (tail call with _traitsRole / _level)
static Y40_NEWRET id Y40_NewCtl2(id self, SEL _cmd, id windowScene, id options) {
    double *lv = (double *)Y40_Slot(self, "_level", YES);
    return ((Y40_NEWRET id (*)(id, SEL, id, id, id, double))objc_msgSend)(self, sel_registerName("_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:"), windowScene, options, Y40_Obj(self, "_traitsRole"), lv ? *lv : 0);
}
// -windowSceneDidConnect: 0x1c79661cc
static void Y40_Connect(id self, SEL _cmd, id windowScene) {
    if (!Y40_Flag(self)) { if (gY40Connect) ((void (*)(id, SEL, id))gY40Connect)(self, _cmd, windowScene); return; }
    NSMapTable *map = Y40_Obj(self, "_sceneControllersByWindowScene");
    id ident = Y40_DisplayIdentity(windowScene);
    if (ident && [map objectForKey:ident]) { BP_Anomaly("y40-connect", @"SBSystemUISceneController should be the first one to handle a new window scene connecting (16.2 asserts, line 116): %@", ident); return; }
    NSEnumerator *keys = [map keyEnumerator];
    if (Y40_Policy(self) == 1 && ![keys nextObject]) return;                                                          // vended per process: nothing to copy yet
    id first = Y40_SinglesOfFirstBlueprint(self);
    SEL newCtl = sel_registerName("_newSceneControllerForWindowScene:withSceneRequestOptions:"), newOpt = sel_registerName("_newAppSceneRequestOptionsForWindowScene:withBlueprintOptions:");
    if (first) {
        for (id single in [first copy]) {
            id opts = ((Y40_NEWRET id (*)(id, SEL, id, id))objc_msgSend)(self, newOpt, windowScene, Y40_Send0(single, "sceneOptions"));
            id c = ((Y40_NEWRET id (*)(id, SEL, id, id))objc_msgSend)(self, newCtl, windowScene, opts);
            (void)c;
        }
    } else {
        id opts = ((Y40_NEWRET id (*)(id, SEL, id, id))objc_msgSend)(self, newOpt, windowScene, nil);
        id c = ((Y40_NEWRET id (*)(id, SEL, id, id))objc_msgSend)(self, newCtl, windowScene, opts);
        (void)c;
    }
}
// -_invalidateSceneControllersForWindowScene: 0x1c79668d4
static void Y40_Invalidate(id self, SEL _cmd, id windowScene) {
    NSMapTable *map = Y40_Obj(self, "_sceneControllersByWindowScene");
    NSMutableArray *all = Y40_Obj(self, "_sceneControllers");
    id ident = Y40_DisplayIdentity(windowScene);
    NSMutableArray *arr = ident ? [map objectForKey:ident] : nil;
    for (id ctl in [arr filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id c, NSDictionary *b) { return [all containsObject:c]; }]]) BPX_Obj0(ctl, "invalidate");   // block 0x1c7966a5c
    if (arr) [all removeObjectsInArray:arr];
    if (ident) [map removeObjectForKey:ident];
}
// -windowSceneDidDisconnect: 0x1c796647c
static void Y40_Disconnect(id self, SEL _cmd, id windowScene) {
    if (!Y40_Flag(self)) { if (gY40Disconnect) ((void (*)(id, SEL, id))gY40Disconnect)(self, _cmd, windowScene); return; }
    if (!Y40_Obj(self, "_sceneControllers")) { BP_Anomaly("y40-disconnect", @"_sceneControllers expected at scene disconnect (16.2 asserts, line 144)"); return; }
    ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_invalidateSceneControllersForWindowScene:"), windowScene);
}
// -createSceneForProcessIdentity:withOptions:completion: 0x1c7966a6c
static NSError *Y40_Error(NSInteger code, NSDictionary *info) { return [NSError errorWithDomain:@"SBSystemUISceneControllerErrorDomain" code:code userInfo:info]; }
static void Y40_Create(id self, SEL _cmd, id identity, id options, void (^completion)(id, NSError *)) {
    if (!Y40_Flag(self)) { if (gY40Create) ((void (*)(id, SEL, id, id, id))gY40Create)(self, _cmd, identity, options, completion); return; }
    if (!options || !identity) { BP_Anomaly("y40-create", @"createSceneForProcessIdentity:withOptions:completion: with nil identity / options (16.2 asserts, lines 218 / 219)"); return; }
    NSMapTable *map = Y40_Obj(self, "_sceneControllersByWindowScene");
    for (id ws in BPY_ConnectedScenes()) {
        id ident = Y40_DisplayIdentity(ws);
        if ([[map objectForKey:ident] count] <= 4) {
            id opts = ((Y40_NEWRET id (*)(id, SEL, id, id))objc_msgSend)(self, sel_registerName("_newAppSceneRequestOptionsForWindowScene:withBlueprintOptions:"), ws, options);
            id ctl = ((Y40_NEWRET id (*)(id, SEL, id, id))objc_msgSend)(self, sel_registerName("_newSceneControllerForWindowScene:withSceneRequestOptions:"), ws, opts);
            BPX_SetBool1(ctl, "setSceneActive:", YES);
            if (completion) completion(BPX_Obj0(ctl, "scene"), nil);
        } else if (completion) {
            completion(nil, Y40_Error(3, @{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Reached maximum allowed number of scenes per display (%d)", 5] }));
        }
    }
}
// -destroyScenesWithPersistentIdentifiers:processIdentity:completion: 0x1c7966de0
static void Y40_Destroy(id self, SEL _cmd, id ids, id identity, void (^completion)(NSError *)) {
    if (!Y40_Flag(self)) { if (gY40Destroy) ((void (*)(id, SEL, id, id, id))gY40Destroy)(self, _cmd, ids, identity, completion); return; }
    if (!ids || !identity) { BP_Anomaly("y40-destroy", @"destroyScenesWithPersistentIdentifiers:... with nil identifiers / identity (16.2 asserts, lines 247 / 248)"); return; }
    NSMapTable *map = Y40_Obj(self, "_sceneControllersByWindowScene");
    NSMutableArray *all = Y40_Obj(self, "_sceneControllers");
    NSMutableArray *destroyed = [NSMutableArray arrayWithCapacity:[ids count]];
    for (id key in [[map keyEnumerator] allObjects]) {
        NSMutableArray *arr = [map objectForKey:key];
        NSArray *hit = [arr filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id c, NSDictionary *b) { return [ids containsObject:BPX_Obj0(c, "scenePersistentIdentifier")]; }]];   // block 0x1c796734c
        if (![hit count]) continue;
        for (id ctl in hit) { id pid = BPX_Obj0(ctl, "scenePersistentIdentifier"); if (pid) [destroyed addObject:pid]; BPX_Obj0(ctl, "invalidate"); }
        [all removeObjectsInArray:hit];
        [arr removeObjectsInArray:hit];
    }
    if ([destroyed count]) {
        id proc = Y40_GET(self, kY40Process);
        if (proc) {
            Class da = objc_getClass("UIDestroySceneAction");
            NSMutableSet *actions = [NSMutableSet setWithCapacity:[destroyed count]];
            for (id pid in destroyed) {
                id a = ((id (*)(id, SEL, id, long long, id, id))objc_msgSend)([da alloc], sel_registerName("initWithPersistedIdentifiers:preferredAnimationType:callbackQueue:completion:"), [NSSet setWithObject:pid], 1LL, nil, nil);
                if (a) [actions addObject:a];
            }
            BPX_SetObj1(BPX_Obj0(proc, "workspace"), "sendActions:", actions);
        } else BP_Anomaly("y40-destroy", @"%@: no client process to send the destroy actions to (16.2 logs an error)", Y40_Obj(self, "_jobLabel"));
    }
    if (completion) {
        if ([destroyed count] == [ids count]) completion(nil);
        else {
            NSMutableArray *unknown = [NSMutableArray arrayWithArray:ids];
            [unknown removeObjectsInArray:destroyed];
            completion(Y40_Error(2, @{ NSLocalizedDescriptionKey: @"Unknown persistent identifiers", @"SBUnknownPersistentIdentifiersList": unknown }));
        }
    }
}
// FBProcessManagerObserver / FBProcessObserver
static void Y40_DidAddProcess(id self, SEL _cmd, id pm, id process) {                                                   // 0x1c7967744
    if ([BPX_Obj0(process, "identity") isEqual:Y40_Obj(self, "_clientProcessIdentity")]) { BPX_SetObj1(process, "addObserver:", self); Y40_SET(self, kY40Process, process); }
}
static void Y40_DidRemoveProcess(id self, SEL _cmd, id pm, id process) {                                                 // 0x1c79677cc
    if ([BPX_Obj0(process, "identity") isEqual:Y40_Obj(self, "_clientProcessIdentity")]) BPX_SetObj1(process, "removeObserver:", self);
}
static void Y40_ProcessDidExit(id self, SEL _cmd, id process) {                                                          // 0x1c7967538
    if (![BPX_Obj0(process, "identity") isEqual:Y40_Obj(self, "_clientProcessIdentity")]) { BP_Anomaly("y40-exit", @"processDidExit: for a process that is not the client (16.2 asserts, line 332)"); return; }
    __weak id w = self;
    void (^work)(void) = ^{                                                                                              // block 0x1c7967628
        id s = w;
        for (id ws in BPY_ConnectedScenes()) ((void (*)(id, SEL, id))objc_msgSend)(s, sel_registerName("_invalidateSceneControllersForWindowScene:"), ws);
    };
    if ([NSThread isMainThread]) work(); else dispatch_async(dispatch_get_main_queue(), work);                          // BSDispatchMain
}
static long long Y40_VendingPolicy(id self, SEL _cmd) { return Y40_Policy(self); }
static id Y40_GetDelegate(id self, SEL _cmd) { return Y40_GET(self, kY40Delegate); }
static void Y40_SetDelegate(id self, SEL _cmd, id d) { Y40_SET(self, kY40Delegate, d); }
static void Y40_SetByScene(id self, SEL _cmd, id m) { Y40_SetObj(self, "_sceneControllersByWindowScene", m); }
static id Y40_Description(id self, SEL _cmd) { return Y40_Send0(self, "succinctDescription"); }
static id Y40_DebugDescription(id self, SEL _cmd) { return ((id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("descriptionWithMultilinePrefix:"), nil); }
// -descriptionBuilderWithMultilinePrefix: 0x1c7967950
static id Y40_DescBuilder(id self, SEL _cmd, id prefix) {
    if (!Y40_Flag(self)) return gY40DescBuilder ? ((id (*)(id, SEL, id))gY40DescBuilder)(self, _cmd, prefix) : nil;
    id b = Y40_Send0(self, "succinctDescriptionBuilder");
    ((id (*)(id, SEL, id, id))objc_msgSend)(b, sel_registerName("appendString:withName:"), Y40_Obj(self, "_traitsRole"), @"Traits Role");
    __unsafe_unretained id u = self;
    ((id (*)(id, SEL, id, id, id))objc_msgSend)(b, sel_registerName("appendBodySectionWithName:multilinePrefix:block:"), nil, nil, ^{
        ((id (*)(id, SEL, id, id))objc_msgSend)(b, sel_registerName("appendObject:withName:"), Y40_Obj(u, "_clientProcessIdentity"), @"Client Process Identity");
        ((id (*)(id, SEL, id, id))objc_msgSend)(b, sel_registerName("appendObject:withName:"), Y40_Obj(u, "_sceneWorkspaceController"), @"Scene Workspace Controller");
        ((id (*)(id, SEL, id, id, BOOL))objc_msgSend)(b, sel_registerName("appendDictionarySection:withName:skipIfEmpty:"), [Y40_Obj(u, "_sceneControllersByWindowScene") dictionaryRepresentation], @"Scene controllers by window scene", YES);
    });
    return b;
}

// ------------------------------------------------------------------------------------------------ SBInputUISceneController
static Y40_NEWRET id Y40_InputInit(Y40_CONSUMED id self, SEL _cmd, id wsid, id identity, long long policy, id role, id label, double level) {          // 0x1c7422458
    struct objc_super sup = { self, gY40Base };
    id me = ((Y40_NEWRET id (*)(struct objc_super *, SEL, id, id, long long, id, id, double))objc_msgSendSuper)(&sup, sel_registerName("initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level:"), wsid, identity, policy, role, label, level);
    if (!me) return nil;
    __unsafe_unretained id u = me;
    void (^work)(void) = ^{                                                                                              // block 0x1c7422500
        id nc = BPX_Obj0(Y40_Class("NSNotificationCenter"), "defaultCenter");
        ((void (*)(id, SEL, id, SEL, id, id))objc_msgSend)(nc, sel_registerName("addObserver:selector:name:object:"), u, sel_registerName("_keyboardWillShow:"), @"UIKeyboardWillShowNotification", nil);
        ((void (*)(id, SEL, id, SEL, id, id))objc_msgSend)(nc, sel_registerName("addObserver:selector:name:object:"), u, sel_registerName("_keyboardWillHide:"), @"UIKeyboardWillHideNotification", nil);
        ((void (*)(id, SEL))objc_msgSend)(u, sel_registerName("_createInputUIScene"));
    };
    if ([NSThread isMainThread]) work(); else { id keep = me; dispatch_async(dispatch_get_main_queue(), ^{ (void)keep; work(); }); }
    return me;
}
static void Y40_InputCreate(id self, SEL _cmd) {                                                                          // 0x1c7422608
    if (!Y40_Flag(self)) { if (gY40InputCreate) ((void (*)(id, SEL))gY40InputCreate)(self, _cmd); return; }
    Class oc = objc_getClass("UISceneRequestOptions");
    id opts = [[oc alloc] init];
    BPX_SetObj1(opts, "setSpecification:", [[NSClassFromString(@"UIApplicationSceneSpecification") alloc] init]);
    BPX_SetObj1(opts, "setIdentifier:", BPX_Obj0(self, "jobLabel"));
    id ctl = ((Y40_NEWRET id (*)(Y40_CONSUMED id, SEL, id, id, id, id, id, double))objc_msgSend)([gY40Single alloc],
        sel_registerName("initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level:"), nil, BPX_Obj0(self, "sceneWorkspaceController"), opts, BPX_Obj0(self, "clientProcessIdentity"), BPX_Obj0(self, "traitsRole"), *gY40LockLevel + 255.0);
    Y40_SetObj(self, "_sceneController", ctl);
    BPX_SetBool1(ctl, "setWindowHosting:", YES);
    BPX_SetBool1(ctl, "setShouldActivateForDisplayConfiguration:", YES);
    BPX_SetBool1(ctl, "setShouldForegroundForDisplayConfiguration:", YES);
    BPX_SetBool1(ctl, "setShouldBeKeptActiveWhileForeground:", YES);
    Y40_SetObj(self, "_inputUIScene", BPX_Obj0(ctl, "scene"));
}

// ------------------------------------------------------------------------------------------------ SBOverlayUISceneController
static void Y40_OverlayConnect(id self, SEL _cmd, id windowScene) {                                                       // 0x1c7950d50
    if (!Y40_Flag(self)) { if (gY40OverlayConnect) ((void (*)(id, SEL, id))gY40OverlayConnect)(self, _cmd, windowScene); return; }
    struct objc_super sup = { self, gY40Base };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, windowScene);
    if (!gY40Feature("SpringBoard", "SystemUISceneOverlayUISubterranean")) return;
    id opts = [[objc_getClass("UISceneRequestOptions") alloc] init];
    BPX_SetObj1(opts, "setSpecification:", [[NSClassFromString(@"UIApplicationSceneSpecification") alloc] init]);
    BPX_SetObj1(opts, "setIdentifier:", BPX_Obj1(self, "_subterraneanSceneIdentifierForWindowScene:", windowScene));
    id ctl = ((Y40_NEWRET id (*)(id, SEL, id, id, id, double))objc_msgSend)(self, sel_registerName("_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:"), windowScene, opts, BPX_Obj0(self, "traitsRole"), *gY40NormalLevel - 3.0 - 1.0);
    Y40_SetObj(self, "_subterraneanScene", ctl);
    BPX_SetBool1(ctl, "setSceneActive:", YES);
}
static void Y40_OverlayDisconnect(id self, SEL _cmd, id windowScene) {                                                    // 16.2 has no override: the base class implementation
    IMP base = class_getMethodImplementation(gY40Base, _cmd);
    ((void (*)(id, SEL, id))base)(self, _cmd, windowScene);
}

// ------------------------------------------------------------------------------------------------ SBAccessibilityUIServerUISceneController
static id Y40_AXSetup(id cls, SEL _cmd) {                                                                                  // 0x1c73347e0: + vendingStrategy
    id info = gY40AXSetup ? ((id (*)(id, SEL))gY40AXSetup)(cls, _cmd) : nil;
    if (![info isKindOfClass:[NSDictionary class]] || !Y40_On()) return info;
    NSMutableDictionary *m = [info mutableCopy];
    m[@"vendingStrategy"] = @1;
    return m;
}
static Y40_NEWRET id Y40_AXNewCtl(id self, SEL _cmd, id windowScene, id options, id role, double level) {                // 0x1c7334940
    struct objc_super sup = { self, gY40Base };
    id ctl = ((Y40_NEWRET id (*)(struct objc_super *, SEL, id, id, id, double))objc_msgSendSuper)(&sup, _cmd, windowScene, options, role, level);
    if (ctl) BPX_SetBool1(ctl, "setShouldActivateUponClientConnection:", NO);
    return ctl;
}

// ------------------------------------------------------------------------------------------------ SBEyedropperUISceneController / SBMomentsUISceneController (16.2 only classes)
static id Y40_EyedropperSetup(id cls, SEL _cmd) {                                                                          // 0x1c779f7f0
    return @{ @"class": (id)objc_getClass("SBEyedropperUISceneController"), @"enabled": @YES, @"isDaemon": @YES, @"jobLabel": @"com.apple.uikit.eyedropperd",
              @"traitsRole": @"SBTraitsParticipantRoleEyedropperUI", @"workspaceID": @"com.apple.SpringBoard.SceneWorkspace.EyedropperUI" };
}
static id Y40_MomentsSetup(id cls, SEL _cmd) {                                                                             // 0x1c75a3228
    return @{ @"class": (id)objc_getClass("SBMomentsUISceneController"), @"enabled": @YES, @"jobLabel": @"com.apple.MomentsUIService",
              @"traitsRole": @"SBTraitsParticipantRoleMomentsUI", @"workspaceID": @"com.apple.SpringBoard.SceneWorkspace.Moments" };
}

// ------------------------------------------------------------------------------------------------ SBSystemUIScenesCoordinator
static const char *const kY40Order[11][2] = {
    { "SBDruidUISceneController", "setDruidUISceneController:" }, { "SBOverlayUISceneController", "setOverlayUISceneController:" }, { "SBInputUISceneController", "setInputUISceneController:" },
    { "SBEnsembleUISceneController", "setEnsembleUISceneController:" }, { "SBEyedropperUISceneController", "setEyedropperUISceneController:" }, { "SBMomentsUISceneController", "setMomentsUISceneController:" },
    { "SBAccessibilityUIServerUISceneController", "setAccessibilityUIServerUISceneController:" }, { "SBAssistiveTouchUISceneController", "setAssistiveTouchUISceneController:" },
    { "SBLiveTranscriptionUISceneController", "setLiveTranscriptionUISceneController:" }, { "SBFullKeyboardAccessUISceneController", "setFullKeyboardAccessUISceneController:" },
    { "SBVoiceControlUISceneController", "setVoiceControlUISceneController:" },
};
static id Y40_Configs(id cls, SEL _cmd) {                                                                                  // 0x1c77a86ac (dispatch_once)
    static NSArray *cfg; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *out = [NSMutableArray array];
        for (int i = 0; i < 11; i++) {
            id c = (id)objc_getClass(kY40Order[i][0]);
            id info = c ? BPX_Obj0(c, "_setupInfo") : nil;
            if (![info isKindOfClass:[NSDictionary class]]) { BP_Anomaly("y40-config", @"%s +_setupInfo missing: the controller is not in the table", kY40Order[i][0]); continue; }
            NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:info];
            m[@"setter"] = [NSValue valueWithPointer:sel_registerName(kY40Order[i][1])];
            [out addObject:m];
        }
        Class rbs = objc_getClass("RBSProcessIdentity");
        for (NSMutableDictionary *m in out) {                                                                              // block tail 0x1c77a8bd4
            NSString *label = m[@"jobLabel"];
            id ident = [m[@"isDaemon"] boolValue] ? BPX_Obj1((id)rbs, "identityForDaemonJobLabel:", label) : BPX_Obj1((id)rbs, "identityForAngelJobLabel:", label);
            if (ident) m[@"processIdentity"] = ident;
        }
        cfg = [out copy];
    });
    return cfg;
}
static id Y40_AllIdentities(id cls, SEL _cmd) {                                                                           // 0x1c77a8d58
    static NSArray *all; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *a = [NSMutableArray array];
        for (NSDictionary *c in BP_AsArray(Y40_Configs(cls, NULL))) { id i = c[@"processIdentity"]; if (i) [a addObject:i]; }
        all = [a copy];
    });
    return all;
}
static BOOL Y40_IsClientIdentity(id cls, SEL _cmd, id identity) { return [Y40_AllIdentities(cls, NULL) containsObject:identity]; }          // 0x1c77a930c
static BOOL Y40_IsClientPID(id cls, SEL _cmd, int pid) {                                                                  // 0x1c77a928c
    id proc = ((id (*)(id, SEL, int))objc_msgSend)(Y40_PM(), sel_registerName("processForPID:"), pid);
    return Y40_IsClientIdentity(cls, NULL, BPX_Obj0(proc, "identity"));
}
static Y40_NEWRET id Y40_CoordInit(Y40_CONSUMED id self, SEL _cmd) {                                                      // 0x1c77a8f64
    if (!Y40_On()) return gY40CoordInit ? ((Y40_NEWRET id (*)(Y40_CONSUMED id, SEL))gY40CoordInit)(self, _cmd) : nil;
    struct objc_super sup = { self, class_getSuperclass(gY40Coord) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (!me) return nil;
    NSArray *configs = BP_AsArray(Y40_Configs((id)object_getClass(me), NULL));
    NSMutableArray *ctls = [NSMutableArray arrayWithCapacity:[configs count]];
    Y40_SetObj(me, "_sceneControllers", ctls);
    double baseLevel = *gY40LockLevel + 255.0;
    for (NSDictionary *info in configs) {
        if (![info[@"enabled"] boolValue]) continue;
        Class cls = info[@"class"];
        SEL setter = (SEL)(void *)[info[@"setter"] pointerValue];
        double level = info[@"hostLevel"] ? (double)[info[@"hostLevel"] floatValue] : baseLevel;
        id strategy = info[@"vendingStrategy"];
        id ctl = ((Y40_NEWRET id (*)(Y40_CONSUMED id, SEL, id, id, long long, id, id, double))objc_msgSend)([cls alloc],
            sel_registerName("initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level:"), info[@"workspaceID"], info[@"processIdentity"], strategy ? (long long)[strategy integerValue] : 0LL, info[@"traitsRole"], info[@"jobLabel"], level);
        if (!ctl) { BP_Anomaly("y40-coord", @"%@: the controller could not be created", info[@"jobLabel"]); continue; }
        ((id (*)(id, SEL, SEL, id))objc_msgSend)(me, sel_registerName("performSelector:withObject:"), setter, ctl);
        [ctls addObject:ctl];
    }
    BPY_LOG(@"[y40] coordinator: %lu system UI scene controllers", (unsigned long)[ctls count]);
    return me;
}
static id Y40_GetEye(id self, SEL _cmd) { return Y40_GET(self, kY40Eye); }
static void Y40_SetEye(id self, SEL _cmd, id c) { Y40_SET(self, kY40Eye, c); }
static id Y40_GetMoments(id self, SEL _cmd) { return Y40_GET(self, kY40Moments); }
static void Y40_SetMoments(id self, SEL _cmd, id c) { Y40_SET(self, kY40Moments, c); }

// ------------------------------------------------------------------------------------------------ traits roles of the two new controllers (the four role lists of 16.2)
static IMP gY40RolesExt, gY40RolesEmb, gY40RolesStage, gY40RolesBelow;
static id Y40_AppendRoles(id coll) {
    if (!coll || !BP_OnName("y40_traitsroles")) return coll;
    NSArray *add = @[@"SBTraitsParticipantRoleEyedropperUI", @"SBTraitsParticipantRoleMomentsUI"];
    if ([coll isKindOfClass:[NSOrderedSet class]]) { NSMutableOrderedSet *m = [coll mutableCopy]; [m addObjectsFromArray:add]; return [m copy]; }
    if ([coll isKindOfClass:[NSSet class]]) return [coll setByAddingObjectsFromArray:add];
    if ([coll isKindOfClass:[NSArray class]]) { NSMutableArray *m = [coll mutableCopy]; for (NSString *r in add) if (![m containsObject:r]) [m addObject:r]; return [m copy]; }
    return coll;
}
static id Y40_RolesExt(id self, SEL _cmd) { return Y40_AppendRoles(((id (*)(id, SEL))gY40RolesExt)(self, _cmd)); }
static id Y40_RolesEmb(id self, SEL _cmd) { return Y40_AppendRoles(((id (*)(id, SEL))gY40RolesEmb)(self, _cmd)); }
static id Y40_RolesStage(id self, SEL _cmd) { return Y40_AppendRoles(((id (*)(id, SEL))gY40RolesStage)(self, _cmd)); }
static id Y40_RolesBelow(id self, SEL _cmd) { return Y40_AppendRoles(((id (*)(id, SEL))gY40RolesBelow)(self, _cmd)); }

// ------------------------------------------------------------------------------------------------ installation
static Class Y40_MakeSubclass(const char *name, Class sup, IMP setupInfo) {
    Class c = objc_getClass(name);
    if (c) return c;
    c = objc_allocateClassPair(sup, name, 0);
    if (!c) { BP_Anomaly("y40-class", @"objc_allocateClassPair(%s) failed", name); return Nil; }
    class_addMethod(object_getClass(c), sel_registerName("_setupInfo"), setupInfo, "@16@0:8");
    objc_registerClassPair(c);
    return c;
}
#define Y40_NEED(cond, what) do { if (!(cond)) { [missing addObject:@what]; } } while (0)

__attribute__((constructor)) static void Y40_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        NSMutableArray *missing = [NSMutableArray array];
        gY40Base = objc_getClass("SBSystemUISceneController");
        gY40Single = objc_getClass("SBSingleSceneController");
        Class coord = gY40Coord = objc_getClass("SBSystemUIScenesCoordinator");
        gY40LockLevel = (double *)dlsym(RTLD_DEFAULT, "UISpringBoardLockScreenWindowLevel");
        gY40NormalLevel = (double *)dlsym(RTLD_DEFAULT, "UIWindowLevelNormal");
        gY40Feature = (BOOL (*)(const char *, const char *))dlsym(RTLD_DEFAULT, "_os_feature_enabled_impl");
        gY40StateCapture = (id (*)(dispatch_queue_t, NSString *, id))dlsym(RTLD_DEFAULT, "BSLogAddStateCaptureBlockWithTitle");
        Y40_NEED(gY40Base, "class SBSystemUISceneController");
        Y40_NEED(gY40Single, "class SBSingleSceneController");
        Y40_NEED(coord, "class SBSystemUIScenesCoordinator");
        Y40_NEED(gY40LockLevel, "symbol UISpringBoardLockScreenWindowLevel (UIKitCore)");
        Y40_NEED(gY40NormalLevel, "symbol UIWindowLevelNormal (UIKitCore)");
        Y40_NEED(gY40Feature, "symbol _os_feature_enabled_impl (libsystem_featureflags)");
        Y40_NEED(objc_getClass("SBFSceneWorkspaceDefaultDelegate"), "class SBFSceneWorkspaceDefaultDelegate (Y38SceneWorkspace.x)");
        Y40_NEED(objc_getClass("SBFSceneWorkspaceController"), "class SBFSceneWorkspaceController");
        Y40_NEED(objc_getClass("FBProcessManager"), "class FBProcessManager");
        Y40_NEED(objc_getClass("UISceneRequestOptions"), "class UISceneRequestOptions");
        Y40_NEED(objc_getClass("UIApplicationSceneSpecification"), "class UIApplicationSceneSpecification");
        Y40_NEED(objc_getClass("UIDestroySceneAction"), "class UIDestroySceneAction");
        Y40_NEED(objc_getClass("RBSProcessIdentity"), "class RBSProcessIdentity");
        if (!gY40StateCapture) BP_Anomaly("y40-install", @"[y40] symbol BSLogAddStateCaptureBlockWithTitle (BaseBoard) not found: the controllers have no state capture (diagnostics only)");
        if (gY40Base) {
            const char *sels[] = { "windowSceneDidConnect:", "windowSceneDidDisconnect:", "dealloc", "_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:", "__newSceneIdentifierForWindowScene:",
                                   "createSceneForProcessIdentity:withOptions:completion:", "destroyScenesWithPersistentIdentifiers:processIdentity:completion:", "descriptionBuilderWithMultilinePrefix:", "succinctDescription",
                                   "succinctDescriptionBuilder", "sceneWorkspaceController", "clientProcessIdentity" };
            for (size_t i = 0; i < sizeof sels / sizeof *sels; i++) if (!class_getInstanceMethod(gY40Base, sel_registerName(sels[i]))) [missing addObject:[NSString stringWithFormat:@"-[SBSystemUISceneController %s]", sels[i]]];
        }
        if (gY40Single && !class_getInstanceMethod(gY40Single, sel_registerName("initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level:"))) [missing addObject:@"-[SBSingleSceneController initWithTargetDisplayConfiguration:...]"];
        if (coord && !class_getInstanceMethod(coord, sel_registerName("init"))) [missing addObject:@"-[SBSystemUIScenesCoordinator init]"];
        const char *ctlNames[] = { "SBDruidUISceneController", "SBOverlayUISceneController", "SBInputUISceneController", "SBEnsembleUISceneController", "SBAccessibilityUIServerUISceneController",
                                   "SBAssistiveTouchUISceneController", "SBLiveTranscriptionUISceneController", "SBFullKeyboardAccessUISceneController", "SBVoiceControlUISceneController" };
        for (size_t i = 0; i < sizeof ctlNames / sizeof *ctlNames; i++) {
            Class c = objc_getClass(ctlNames[i]);
            if (!c) [missing addObject:[NSString stringWithFormat:@"class %s", ctlNames[i]]];
            else if (!class_getClassMethod(c, sel_registerName("_setupInfo"))) [missing addObject:[NSString stringWithFormat:@"+[%s _setupInfo]", ctlNames[i]]];
        }
        for (int i = 0; i < 11 && coord; i++) {
            const char *s = kY40Order[i][1];
            if (i != 4 && i != 5 && !class_getInstanceMethod(coord, sel_registerName(s))) [missing addObject:[NSString stringWithFormat:@"-[SBSystemUIScenesCoordinator %s]", s]];
        }
        if (objc_getClass("RBSProcessIdentity") && !class_getClassMethod(objc_getClass("RBSProcessIdentity"), sel_registerName("identityForAngelJobLabel:"))) [missing addObject:@"+[RBSProcessIdentity identityForAngelJobLabel:]"];
        if (objc_getClass("RBSProcessIdentity") && !class_getClassMethod(objc_getClass("RBSProcessIdentity"), sel_registerName("identityForDaemonJobLabel:"))) [missing addObject:@"+[RBSProcessIdentity identityForDaemonJobLabel:]"];
        if ([missing count]) {
            BP_Anomaly("y40-install", @"[y40] system UI scene controllers / coordinator NOT installed (16.0 construction stays), needs: %@", [missing componentsJoinedByString:@", "]);
            return;
        }
        // 1. the base class
        ADD(gY40Base, "initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level:", Y40_BaseInit, "@64@0:8@16@24q32@40@48d56");
        gY40Dealloc = BPX_Replace(gY40Base, "dealloc", (IMP)Y40_Dealloc);
        gY40Connect = BPX_Replace(gY40Base, "windowSceneDidConnect:", (IMP)Y40_Connect);
        gY40Disconnect = BPX_Replace(gY40Base, "windowSceneDidDisconnect:", (IMP)Y40_Disconnect);
        gY40NewCtl = BPX_Replace(gY40Base, "_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:", (IMP)Y40_NewCtl);
        gY40NewId = BPX_Replace(gY40Base, "__newSceneIdentifierForWindowScene:", (IMP)Y40_NewSceneId);
        gY40Create = BPX_Replace(gY40Base, "createSceneForProcessIdentity:withOptions:completion:", (IMP)Y40_Create);
        gY40Destroy = BPX_Replace(gY40Base, "destroyScenesWithPersistentIdentifiers:processIdentity:completion:", (IMP)Y40_Destroy);
        gY40DescBuilder = BPX_Replace(gY40Base, "descriptionBuilderWithMultilinePrefix:", (IMP)Y40_DescBuilder);
        ADD(gY40Base, "_newAppSceneRequestOptionsForWindowScene:withBlueprintOptions:", Y40_NewOptions, "@32@0:8@16@24");
        ADD(gY40Base, "_newSceneControllerForWindowScene:withSceneRequestOptions:", Y40_NewCtl2, "@32@0:8@16@24");
        ADD(gY40Base, "_invalidateSceneControllersForWindowScene:", Y40_Invalidate, "v24@0:8@16");
        ADD(gY40Base, "processManager:didAddProcess:", Y40_DidAddProcess, "v32@0:8@16@24");
        ADD(gY40Base, "processManager:didRemoveProcess:", Y40_DidRemoveProcess, "v32@0:8@16@24");
        ADD(gY40Base, "processDidExit:", Y40_ProcessDidExit, "v24@0:8@16");
        ADD(gY40Base, "sceneVendingPolicy", Y40_VendingPolicy, "q16@0:8");
        ADD(gY40Base, "sceneWorkspaceControllerDelegate", Y40_GetDelegate, "@16@0:8");
        ADD(gY40Base, "setSceneWorkspaceControllerDelegate:", Y40_SetDelegate, "v24@0:8@16");
        ADD(gY40Base, "setSceneControllersByWindowScene:", Y40_SetByScene, "v24@0:8@16");
        ADD(gY40Base, "description", Y40_Description, "@16@0:8");
        ADD(gY40Base, "debugDescription", Y40_DebugDescription, "@16@0:8");
        const char *protos[] = { "FBProcessManagerObserver", "FBProcessObserver" };
        for (int i = 0; i < 2; i++) { Protocol *p = objc_getProtocol(protos[i]); if (p) class_addProtocol(gY40Base, p); else BP_Anomaly("y40-install", @"[y40] protocol %s not found (not added to SBSystemUISceneController)", protos[i]); }
        // 2. subclasses
        Class input = objc_getClass("SBInputUISceneController"), overlay = objc_getClass("SBOverlayUISceneController"), ax = objc_getClass("SBAccessibilityUIServerUISceneController");
        ADD(input, "initWithSceneWorkspaceIdentifier:clientProcessIdentity:sceneVendingPolicy:traitsRole:jobLabel:level:", Y40_InputInit, "@64@0:8@16@24q32@40@48d56");
        if (class_getInstanceMethod(input, sel_registerName("_createInputUIScene"))) gY40InputCreate = BPX_Replace(input, "_createInputUIScene", (IMP)Y40_InputCreate); else BP_Anomaly("y40-install", @"[y40] -[SBInputUISceneController _createInputUIScene] missing");
        if (class_getInstanceMethod(overlay, sel_registerName("windowSceneDidConnect:"))) gY40OverlayConnect = BPX_Replace(overlay, "windowSceneDidConnect:", (IMP)Y40_OverlayConnect); else BP_Anomaly("y40-install", @"[y40] -[SBOverlayUISceneController windowSceneDidConnect:] missing");
        if (class_getInstanceMethod(overlay, sel_registerName("windowSceneDidDisconnect:"))) BPX_Replace(overlay, "windowSceneDidDisconnect:", (IMP)Y40_OverlayDisconnect);
        ADD(ax, "_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:", Y40_AXNewCtl, "@48@0:8@16@24@32d40");
        gY40AXSetup = BPX_Replace(object_getClass(ax), "_setupInfo", (IMP)Y40_AXSetup);
        // 3. the classes that exist only in 16.2
        Y40_MakeSubclass("SBEyedropperUISceneController", gY40Base, (IMP)Y40_EyedropperSetup);
        Y40_MakeSubclass("SBMomentsUISceneController", gY40Base, (IMP)Y40_MomentsSetup);
        // 4. the coordinator (last)
        Class cmeta = object_getClass(coord);
        class_addMethod(cmeta, sel_registerName("_sceneControllersConfigurations"), (IMP)Y40_Configs, "@16@0:8");
        class_addMethod(cmeta, sel_registerName("_allKnownProcessIdentities"), (IMP)Y40_AllIdentities, "@16@0:8");
        class_addMethod(cmeta, sel_registerName("isSystemUISceneClientPID:"), (IMP)Y40_IsClientPID, "B20@0:8i16");
        class_addMethod(cmeta, sel_registerName("isSystemUISceneClientIdentity:"), (IMP)Y40_IsClientIdentity, "B24@0:8@16");
        ADD(coord, "eyedropperUISceneController", Y40_GetEye, "@16@0:8");
        ADD(coord, "setEyedropperUISceneController:", Y40_SetEye, "v24@0:8@16");
        ADD(coord, "momentsUISceneController", Y40_GetMoments, "@16@0:8");
        ADD(coord, "setMomentsUISceneController:", Y40_SetMoments, "v24@0:8@16");
        gY40CoordInit = BPX_Replace(coord, "init", (IMP)Y40_CoordInit);
        // 5. traits roles of the two new controllers
        Class ext = objc_getClass("SBExternalDisplayWindowSceneDelegate"), emb = objc_getClass("SBEmbeddedDisplayWindowSceneDelegate");
        Class stage = objc_getClass("SBTraitsExternalDisplayRolesAndDefaultPoliciesProvider"), below = objc_getClass("SBTraitsEmbeddedDisplayRolesAndDefaultPoliciesProvider");
        if (ext && class_getClassMethod(ext, sel_registerName("_individuallyManagedRoles"))) gY40RolesExt = BPX_Replace(object_getClass(ext), "_individuallyManagedRoles", (IMP)Y40_RolesExt); else BP_Anomaly("y40-install", @"[y40] +[SBExternalDisplayWindowSceneDelegate _individuallyManagedRoles] missing: no Eyedropper / Moments role there");
        if (emb && class_getClassMethod(emb, sel_registerName("_individuallyManagedRoles"))) gY40RolesEmb = BPX_Replace(object_getClass(emb), "_individuallyManagedRoles", (IMP)Y40_RolesEmb); else BP_Anomaly("y40-install", @"[y40] +[SBEmbeddedDisplayWindowSceneDelegate _individuallyManagedRoles] missing");
        if (stage && class_getInstanceMethod(stage, sel_registerName("orientationStageRoles"))) gY40RolesStage = BPX_Replace(stage, "orientationStageRoles", (IMP)Y40_RolesStage); else BP_Anomaly("y40-install", @"[y40] -[SBTraitsExternalDisplayRolesAndDefaultPoliciesProvider orientationStageRoles] missing");
        if (below && class_getInstanceMethod(below, sel_registerName("defaultActiveOrientationBelowDrivenRoles"))) gY40RolesBelow = BPX_Replace(below, "defaultActiveOrientationBelowDrivenRoles", (IMP)Y40_RolesBelow); else BP_Anomaly("y40-install", @"[y40] -[SBTraitsEmbeddedDisplayRolesAndDefaultPoliciesProvider defaultActiveOrientationBelowDrivenRoles] missing");
        BP_Log(@"[y40] installed: SBSystemUISceneController (vending policy), Input / Overlay / AccessibilityUIServer, SBEyedropperUISceneController, SBMomentsUISceneController, SBSystemUIScenesCoordinator table (switch y40_sysui)");
    }
}
#pragma clang diagnostic pop
