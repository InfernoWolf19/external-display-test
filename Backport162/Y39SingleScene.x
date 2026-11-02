// Y39SingleScene.x : S1 system UI scene family, step 4 (DELTA-SWEEP-0.7.9.md Pass 4 section 1): SBSingleSceneController of 16.2.  Setup: constructor.  Log prefix "[y39]".
// Switch y39_singlescene (default ON, kill file Backport162.off.y39_singlescene).
//
// SBSingleSceneController, 16.2 (16.0 in brackets).  16.2 ivars: new _clientIdentity (RBSProcessIdentity, 0x8, every other ivar shifts by 8; an associated object here), _sceneOptions is a UISceneRequestOptions
// [FBSWorkspaceSceneRequestOptions: the scene creation reads only -identifier / -specification, both classes have them].
//   -initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level: 0x1c790e804 [0x1c645b9d4]: the same sequence, stores _clientIdentity, creates the scene through
//   -[SBFSceneWorkspaceController createSceneForProcessIdentity:withOptions:completion:] and the updater with updatesGeometry:YES (Y38SceneUpdater.x);
//   -_newActivationContext 0x1c790f8d0 (NEW): the first action of the options' actions that passes the activity continuation test is rebuilt as a UIActivityContinuationAction from
//   {7: userActivityData, 5: activityType, 6: lastUpdateTime} (the UISActivityContinuationAction setting ids) and wrapped in a UIApplicationSceneTransitionContext (setActions:); nil without such an action;
//   -_isClientProcessRunning 0x1c790fa9c (NEW): [[[FBProcessManager sharedInstance] processForIdentity:_clientIdentity] isRunning];
//   -setSceneActive: 0x1c790f0fc (NEW): [updater setActive:a withTransitionContext:(a ? [self _newActivationContext] : nil)];  -isSceneActive reads the updater as before;
//   -_evaluateSceneActivationState 0x1c790fb30 [0x1c645c60c: setActive:YES]: setActive:YES withTransitionContext:[self _newActivationContext] when _shouldActivateForDisplayConfiguration && _targetDisplayConfiguration;
//   -setShouldActivateUponClientConnection: 0x1c790edfc [0x1c645bf44: [workspaceController setScene:shouldActivateUponClientConnection:]]: the DELEGATE of the workspace controller gets
//   setScene:shouldActivateUponClientConnection:withContextGenerator: (block: weak self -> _newActivationContext), then, when the flag is set, the scene is inactive and the client process runs: setSceneActive:YES;
//   -setShouldBeKeptActiveWhileForeground: 0x1c790ef64 [0x1c645bf58]: the same with ...KeptActiveWhileForeground:withContextGenerator:, and the immediate activation also needs the scene to be foreground;
//   -_setVisible: 0x1c790f448 [0x1c645c150]: unchanged but for the presentation binder calls: -addSingleSceneToPresentationBinder: / -removeSingleSceneFromPresentationBinder: instead of
//   -addSceneToPresentationBinder: / -removeSceneFromPresentationBinder: (tracked collection _boundSingleScenes, Y38SceneUpdater.x); -invalidate / -sceneDidInvalidate: only add a log line.
//
// Port: the 16.0 class is hooked method by method with the 16.2 bodies; -_setVisible: runs the 16.0 body with the two SBSceneManager binder methods redirected to the single scene variants for the duration
// of the call (thread local), which is what 16.2 calls.  A controller whose workspace controller delegate is not a 16.2 style delegate (a 16.0 construction, e.g. before Y40) keeps the 16.0 setters
// (the 16.0 workspace controller does that bookkeeping itself).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static char kY39Client;
#define Y39_NEWRET __attribute__((ns_returns_retained))
#define Y39_CONSUMED __attribute__((ns_consumed))
#define ADD(c, sel, imp, types) class_addMethod((c), sel_registerName(sel), (IMP)(imp), (types))

static IMP gY39Init, gY39Eval, gY39SetUpon, gY39SetKept, gY39SetVisible, gY39BinderAdd, gY39BinderRemove;
static __thread int tY39InSetVisible;
static BOOL Y39_On(void) { return BP_OnName("y39_singlescene"); }

static BOOL Y39_Flag(id self, const char *name) {
    Ivar iv = BP_IvarLookup(object_getClass(self), name);
    return iv ? *(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(iv)) : NO;
}
static BOOL Y39_NewDelegate(id self, id *outDelegate) {                       // a delegate that implements the 16.2 delegate API
    id ctl = BPX_IvarObj(self, "_sceneWorkspaceController");
    id d = BPX_Obj0(ctl, "delegate");
    if (outDelegate) *outDelegate = d;
    return d && [d respondsToSelector:sel_registerName("setScene:shouldActivateUponClientConnection:withContextGenerator:")];
}

// -initWithTargetDisplayConfiguration:...: 16.2 0x1c790e804 (the 16.0 body is the same sequence; _clientIdentity is kept as an associated object)
static Y39_NEWRET id Y39_Init(Y39_CONSUMED id self, SEL _cmd, id cfg, id ctl, id options, id identity, id role, double level) {
    id me = ((Y39_NEWRET id (*)(Y39_CONSUMED id, SEL, id, id, id, id, id, double))gY39Init)(self, _cmd, cfg, ctl, options, identity, role, level);
    if (me && identity) objc_setAssociatedObject(me, &kY39Client, identity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return me;
}
static id Y39_ClientIdentity(id self) { return objc_getAssociatedObject(self, &kY39Client); }

static id Y39_FindAction(id options) {
    Class base = NSClassFromString(@"UISActivityContinuationAction");
    for (id a in BP_AsArray(BPX_Obj0(options, "actions"))) if (base && [a isKindOfClass:base]) return a;      // block 0x1e18f1fc0
    return nil;
}
static Y39_NEWRET id Y39_NewActivationContext(id self, SEL _cmd) {                                                  // 0x1c790f8d0 (-_new...: new family, +1)
    id action = Y39_FindAction(BPX_IvarObj(self, "_sceneOptions"));
    if (!action) return nil;
    NSDictionary *settings = @{ @7: BPX_Obj0(action, "userActivityData") ?: (id)[NSNull null], @5: BPX_Obj0(action, "activityType") ?: (id)[NSNull null], @6: BPX_Obj0(action, "lastUpdateTime") ?: (id)[NSNull null] };
    Class ac = NSClassFromString(@"UIActivityContinuationAction"), tc = NSClassFromString(@"UIApplicationSceneTransitionContext");
    if (!ac || !tc) { BP_Anomaly("y39-ctx", @"UIActivityContinuationAction / UIApplicationSceneTransitionContext missing: no activation context"); return nil; }
    id na = ((Y39_NEWRET id (*)(Y39_CONSUMED id, SEL, id))objc_msgSend)([ac alloc], sel_registerName("initWithSettings:"), settings);
    id ctx = [[tc alloc] init];
    BPX_SetObj1(ctx, "setActions:", [NSSet setWithObject:na]);
    return ctx;
}
static BOOL Y39_ClientRunning(id self, SEL _cmd) {                                                                   // 0x1c790fa9c
    id pm = BPX_Obj0((id)NSClassFromString(@"FBProcessManager"), "sharedInstance");
    return BPX_Bool0(BPX_Obj1(pm, "processForIdentity:", Y39_ClientIdentity(self)), "isRunning");
}
static void Y39_SetSceneActive(id self, SEL _cmd, BOOL active) {                                                     // 0x1c790f0fc
    id ctx = active ? ((Y39_NEWRET id (*)(id, SEL))objc_msgSend)(self, sel_registerName("_newActivationContext")) : nil;
    id up = BPX_IvarObj(self, "_sceneSettingsUpdater");
    SEL s = sel_registerName("setActive:withTransitionContext:");
    if (up && [up respondsToSelector:s]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(up, s, active, ctx);
    else if (up) { BP_Anomaly("y39-active", @"SBSceneSettingsUpdater setActive:withTransitionContext: missing: 16.0 setActive: used"); ((void (*)(id, SEL, BOOL))objc_msgSend)(up, sel_registerName("setActive:"), active); }
}
static void Y39_Eval(id self, SEL _cmd) {                                                                            // 0x1c790fb30
    if (!Y39_On()) { if (gY39Eval) ((void (*)(id, SEL))gY39Eval)(self, _cmd); return; }
    if (Y39_Flag(self, "_shouldActivateForDisplayConfiguration") && BPX_IvarObj(self, "_targetDisplayConfiguration")) ((void (*)(id, SEL, BOOL))objc_msgSend)(self, sel_registerName("setSceneActive:"), YES);
}
static id (^Y39_Generator(id self))(void) {
    __weak id w = self;
    return ^id{ id s = w; return s ? ((Y39_NEWRET id (*)(id, SEL))objc_msgSend)(s, sel_registerName("_newActivationContext")) : nil; };
}
static void Y39_SetUpon(id self, SEL _cmd, BOOL v) {                                                                 // 0x1c790edfc
    id d = nil;
    if (!Y39_On() || !Y39_NewDelegate(self, &d)) { if (gY39SetUpon) ((void (*)(id, SEL, BOOL))gY39SetUpon)(self, _cmd, v); return; }
    id scene = BPX_IvarObj(self, "_scene");
    ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(d, sel_registerName("setScene:shouldActivateUponClientConnection:withContextGenerator:"), scene, v, Y39_Generator(self));
    if (v && !BPX_Bool0(scene, "isActive") && Y39_ClientRunning(self, NULL)) Y39_SetSceneActive(self, NULL, YES);
}
static void Y39_SetKept(id self, SEL _cmd, BOOL v) {                                                                 // 0x1c790ef64
    id d = nil;
    if (!Y39_On() || !Y39_NewDelegate(self, &d)) { if (gY39SetKept) ((void (*)(id, SEL, BOOL))gY39SetKept)(self, _cmd, v); return; }
    id scene = BPX_IvarObj(self, "_scene");
    ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(d, sel_registerName("setScene:shouldBeKeptActiveWhileForeground:withContextGenerator:"), scene, v, Y39_Generator(self));
    if (v && !BPX_Bool0(scene, "isActive") && BPX_Bool0(BPX_Obj0(scene, "settings"), "isForeground") && Y39_ClientRunning(self, NULL)) Y39_SetSceneActive(self, NULL, YES);
}
// -_setVisible: : the 16.0 body with the binder calls redirected
static void Y39_SetVisible(id self, SEL _cmd, BOOL v) {
    if (!Y39_On()) { if (gY39SetVisible) ((void (*)(id, SEL, BOOL))gY39SetVisible)(self, _cmd, v); return; }
    tY39InSetVisible++;
    @try { ((void (*)(id, SEL, BOOL))gY39SetVisible)(self, _cmd, v); } @finally { tY39InSetVisible--; }
}
static void Y39_BinderAdd(id self, SEL _cmd, id scene) {
    if (tY39InSetVisible > 0 && [self respondsToSelector:sel_registerName("addSingleSceneToPresentationBinder:")]) { ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("addSingleSceneToPresentationBinder:"), scene); return; }
    if (gY39BinderAdd) ((void (*)(id, SEL, id))gY39BinderAdd)(self, _cmd, scene);
}
static void Y39_BinderRemove(id self, SEL _cmd, id scene) {
    if (tY39InSetVisible > 0 && [self respondsToSelector:sel_registerName("removeSingleSceneFromPresentationBinder:")]) { ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("removeSingleSceneFromPresentationBinder:"), scene); return; }
    if (gY39BinderRemove) ((void (*)(id, SEL, id))gY39BinderRemove)(self, _cmd, scene);
}

__attribute__((constructor)) static void Y39_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class sc = NSClassFromString(@"SBSingleSceneController"), sm = NSClassFromString(@"SBSceneManager");
        if (sc && sm && class_getInstanceMethod(sc, sel_registerName("initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level:")) &&
            class_getInstanceMethod(sc, sel_registerName("_evaluateSceneActivationState")) && class_getInstanceMethod(sc, sel_registerName("setShouldActivateUponClientConnection:")) &&
            class_getInstanceMethod(sc, sel_registerName("setShouldBeKeptActiveWhileForeground:")) && class_getInstanceMethod(sc, sel_registerName("_setVisible:")) &&
            class_getInstanceMethod(sm, sel_registerName("addSceneToPresentationBinder:")) && class_getInstanceMethod(sm, sel_registerName("removeSceneFromPresentationBinder:"))) {
            gY39Init = BPX_Replace(sc, "initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level:", (IMP)Y39_Init);
            ADD(sc, "_newActivationContext", Y39_NewActivationContext, "@16@0:8");
            ADD(sc, "_isClientProcessRunning", Y39_ClientRunning, "B16@0:8");
            ADD(sc, "setSceneActive:", Y39_SetSceneActive, "v20@0:8B16");
            gY39Eval = BPX_Replace(sc, "_evaluateSceneActivationState", (IMP)Y39_Eval);
            gY39SetUpon = BPX_Replace(sc, "setShouldActivateUponClientConnection:", (IMP)Y39_SetUpon);
            gY39SetKept = BPX_Replace(sc, "setShouldBeKeptActiveWhileForeground:", (IMP)Y39_SetKept);
            gY39SetVisible = BPX_Replace(sc, "_setVisible:", (IMP)Y39_SetVisible);
            gY39BinderAdd = BPX_Replace(sm, "addSceneToPresentationBinder:", (IMP)Y39_BinderAdd);
            gY39BinderRemove = BPX_Replace(sm, "removeSceneFromPresentationBinder:", (IMP)Y39_BinderRemove);
            n++;
        } else BP_Anomaly("y39-install", @"[y39] SBSingleSceneController / SBSceneManager selectors missing: single scene controller port not installed");
        BP_Log(@"[y39] installed %d group(s) (switch y39_singlescene)", n);
    }
}
#pragma clang diagnostic pop
