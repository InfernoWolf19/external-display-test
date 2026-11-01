// Y38SceneWorkspace.x : S1 system UI scene family, step 1 (DELTA-SWEEP-0.7.9.md Pass 4 section 1): SpringBoardFoundation SBFSceneWorkspaceDefaultDelegate (a class that exists only in 16.2) and the
// slimmed SBFSceneWorkspaceController of 16.2.  Setup: constructor.  Log prefix "[y38]".  Switch y38_scenews (default ON, kill file Backport162.off.y38_scenews).
//
// 16.2 SpringBoardFoundation:
//   SBFSceneWorkspaceController is a thin shell (ivars _sceneWorkspace, _delegate): -initWithIdentifier:delegate: 0x18edfc8ec makes the FBSceneWorkspace and sets the DELEGATE it was given as the workspace
//   delegate (16.0 0x18eb5cd6c made itself the workspace delegate and kept three bookkeeping sets), -createSceneForProcessIdentity:withOptions:completion: 0x18edfca44 (scene = [workspace createScene:block],
//   block 0x18edfcc90: setIdentifier:[options identifier], setSpecification:[options specification], setClientIdentity:[FBSSceneClientIdentity identityForProcessIdentity:identity]; completion(scene, nil);
//   16.0 0x18eb5ced8 additionally recorded the scene / process in its three sets), -invalidate 0x18edfd178 (every scene of [workspace allScenes]: setDelegate:nil, invalidate; then the workspace:
//   setDelegate:nil, invalidate), -enumerateScenesWithBlock: / -sceneFromIdentityToken...: unchanged.
//   SBFSceneWorkspaceDefaultDelegate (NEW; ivars _scenesActivatedUponClientConnection, _scenesKeptActiveWhileForeground, _scenesWithActivationContextGeneratorBlock = scene identifier -> block): the bookkeeping that
//   16.0 kept inside the controller: -init 0x18edf3fc0, -setScene:shouldActivateUponClientConnection:withContextGenerator: 0x18edf405c, -setScene:shouldBeKeptActiveWhileForeground:withContextGenerator: 0x18edf4134,
//   -_setScene:cached:inContainer:withContextGenerator: 0x18edf420c, -_setScene:activatesWithTransitionContextGeneratorBlock: 0x18edf4374, -_cleanupTransitionContextGeneratorBlockForSceneIfNeeded: 0x18edf44f4,
//   -_activateScene: 0x18edf457c (generator block -> [scene activateWithTransitionContext:ctx]), the FBSceneWorkspaceDelegate / FBSceneDelegate callbacks -workspace:clientDidConnectWithHandshake: 0x18edf4670
//   (a scene kept for client connection whose client identity matches and that is not active is activated), -workspace:didAddScene: 0x18edf4938 (scene setDelegate:self), -workspace:willRemoveScene: 0x18edf4a54
//   (setDelegate:nil), -sceneDidActivate: 0x18edf4b70, -sceneDidDeactivate:withError: 0x18edf4c4c (a foreground scene kept active is re-activated), -sceneContentStateDidChange: 0x18edf4e50 (log only).
//
// Port: the class is created at run time (never shadowing a real one); the controller hooks only act on controllers that were given a SBFSceneWorkspaceDefaultDelegate (the 16.2 construction, made by
// Y40SystemUIScenes.x); every other controller (16.0 construction) keeps its 16.0 behaviour.  Nothing uses the new class before Y40 installs the 16.2 scene controllers.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static char kY38Act, kY38Kept, kY38Gens, kY38NewStyle;
#define Y38_SET(o, k, v) objc_setAssociatedObject((o), &(k), (v), OBJC_ASSOCIATION_RETAIN_NONATOMIC)
#define Y38_GET(o, k)    objc_getAssociatedObject((o), &(k))
#define Y38_NEWRET __attribute__((ns_returns_retained))
#define Y38_CONSUMED __attribute__((ns_consumed))
#define Y38_INIT(...) ((Y38_NEWRET id (*)(Y38_CONSUMED id, SEL, __VA_ARGS__))objc_msgSend)
#define ADD(c, sel, imp, types) class_addMethod((c), sel_registerName(sel), (IMP)(imp), (types))

static Class gY38Delegate;
static IMP gY38OrigInit, gY38OrigCreate, gY38OrigInvalidate;
static BOOL Y38_On(void) { return BP_OnName("y38_scenews"); }

static NSString *Y38_SceneID(id scene) { return BPX_Obj0(scene, "identifier"); }

// ------------------------------------------------------------------------------------------------ SBFSceneWorkspaceDefaultDelegate
static Y38_NEWRET id Y38_DInit(Y38_CONSUMED id self, SEL _cmd) {                                                        // 0x18edf3fc0
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        Y38_SET(me, kY38Kept, [NSMutableSet set]);
        Y38_SET(me, kY38Act, [NSMutableSet set]);
        Y38_SET(me, kY38Gens, [NSMutableDictionary dictionary]);
    }
    return me;
}
static void Y38_DSetScene(id self, SEL _cmd, id scene, BOOL cached, NSMutableSet *container, id gen);
static void Y38_DSetActivateOnConnect(id self, SEL _cmd, id scene, BOOL v, id gen) {                                    // 0x18edf405c
    if (!scene) { BP_Anomaly("y38-delegate", @"setScene:shouldActivateUponClientConnection: with a nil scene (16.2 asserts)"); return; }
    Y38_DSetScene(self, sel_registerName("_setScene:cached:inContainer:withContextGenerator:"), scene, v, Y38_GET(self, kY38Act), gen);
}
static void Y38_DSetKeptActive(id self, SEL _cmd, id scene, BOOL v, id gen) {                                           // 0x18edf4134
    if (!scene) { BP_Anomaly("y38-delegate", @"setScene:shouldBeKeptActiveWhileForeground: with a nil scene (16.2 asserts)"); return; }
    Y38_DSetScene(self, sel_registerName("_setScene:cached:inContainer:withContextGenerator:"), scene, v, Y38_GET(self, kY38Kept), gen);
}
static void Y38_DSetGen(id self, SEL _cmd, id scene, id block);
static void Y38_DCleanup(id self, SEL _cmd, id scene);
static void Y38_DSetScene(id self, SEL _cmd, id scene, BOOL cached, NSMutableSet *container, id gen) {                  // 0x18edf420c
    if (!scene || !container) { BP_Anomaly("y38-delegate", @"_setScene:cached:inContainer: with a nil scene / container (16.2 asserts)"); return; }
    if (cached) {
        if (![container containsObject:scene]) {
            [container addObject:scene];
            if (gen) Y38_DSetGen(self, sel_registerName("_setScene:activatesWithTransitionContextGeneratorBlock:"), scene, gen);
        }
    } else {
        [container removeObject:scene];
        Y38_DCleanup(self, sel_registerName("_cleanupTransitionContextGeneratorBlockForSceneIfNeeded:"), scene);
    }
}
static void Y38_DSetGen(id self, SEL _cmd, id scene, id block) {                                                        // 0x18edf4374
    if (!scene || !block) { BP_Anomaly("y38-delegate", @"_setScene:activatesWithTransitionContextGeneratorBlock: with a nil scene / block (16.2 asserts)"); return; }
    NSMutableDictionary *d = Y38_GET(self, kY38Gens);
    NSString *sid = Y38_SceneID(scene);
    if (!d[sid]) d[sid] = [block copy];
}
static void Y38_DCleanup(id self, SEL _cmd, id scene) {                                                                 // 0x18edf44f4
    if ([Y38_GET(self, kY38Act) containsObject:scene] || [Y38_GET(self, kY38Kept) containsObject:scene]) return;
    NSMutableDictionary *d = Y38_GET(self, kY38Gens);
    NSString *sid = Y38_SceneID(scene);
    if (sid) [d removeObjectForKey:sid];
}
static void Y38_DActivate(id self, SEL _cmd, id scene) {                                                                // 0x18edf457c
    if (!scene) { BP_Anomaly("y38-delegate", @"_activateScene: with a nil scene (16.2 asserts)"); return; }
    NSDictionary *d = Y38_GET(self, kY38Gens);
    id (^gen)(void) = d[Y38_SceneID(scene)];
    id ctx = gen ? gen() : nil;                                                                                         // 16.2 calls the block unchecked: every scene in a set was registered with its generator
    if (!gen) BP_Anomaly("y38-delegate", @"scene %@ has no activation context generator: activated without a transition context", Y38_SceneID(scene));
    ((void (*)(id, SEL, id))objc_msgSend)(scene, sel_registerName("activateWithTransitionContext:"), ctx);
}
static void Y38_DClientConnected(id self, SEL _cmd, id workspace, id handshake) {                                       // 0x18edf4670
    BPY_LOG(@"[y38] client did connect: %@", BPX_Obj0(workspace, "identifier"));
    for (id scene in [Y38_GET(self, kY38Act) allObjects]) {
        id procID = BPX_Obj0(BPX_Obj0(BPX_Obj0(scene, "definition"), "clientIdentity"), "processIdentity");
        id hsID = BPX_Obj0(BPX_Obj0(handshake, "handle"), "identity");
        if (procID && [procID isEqual:hsID] && !BPX_Bool0(scene, "isActive")) {
            BPY_LOG(@"[y38] activating scene %@ upon client connection", Y38_SceneID(scene));
            Y38_DActivate(self, NULL, scene);
        }
    }
}
static void Y38_DDidAdd(id self, SEL _cmd, id workspace, id scene) {                                                   // 0x18edf4938
    BPY_LOG(@"[y38] workspace %@ did add scene %@", BPX_Obj0(workspace, "identifier"), Y38_SceneID(scene));
    BPX_SetObj1(scene, "setDelegate:", self);
}
static void Y38_DWillRemove(id self, SEL _cmd, id workspace, id scene) {                                                // 0x18edf4a54
    BPY_LOG(@"[y38] workspace %@ will remove scene %@", BPX_Obj0(workspace, "identifier"), Y38_SceneID(scene));
    BPX_SetObj1(scene, "setDelegate:", nil);
}
static void Y38_DDidActivate(id self, SEL _cmd, id scene) { BPY_LOG(@"[y38] scene %@ did activate", Y38_SceneID(scene)); }               // 0x18edf4b70
static void Y38_DDidDeactivate(id self, SEL _cmd, id scene, id error) {                                                 // 0x18edf4c4c
    BPY_LOG(@"[y38] scene %@ did deactivate: %@", Y38_SceneID(scene), BPX_Obj0(error, "localizedDescription"));
    if (BPX_Bool0(BPX_Obj0(scene, "settings"), "isForeground") && [Y38_GET(self, kY38Kept) containsObject:scene]) {
        BPY_LOG(@"[y38] re-activating foreground scene %@ that is kept active", Y38_SceneID(scene));
        Y38_DActivate(self, NULL, scene);
    }
}
static void Y38_DContentState(id self, SEL _cmd, id scene) { BPY_LOG(@"[y38] scene %@ content state %lld", Y38_SceneID(scene), BPX_LL0(scene, "contentState")); }   // 0x18edf4e50

// ------------------------------------------------------------------------------------------------ SBFSceneWorkspaceController (16.0 class) with a 16.2 style delegate
static BOOL Y38_NewStyle(id ctl) { return [Y38_GET(ctl, kY38NewStyle) boolValue]; }
// -initWithIdentifier:delegate: 16.2 0x18edfc8ec: the workspace delegate is the delegate that was passed in
static Y38_NEWRET id Y38_CtlInit(Y38_CONSUMED id self, SEL _cmd, id identifier, id delegate) {
    id me = ((Y38_NEWRET id (*)(Y38_CONSUMED id, SEL, id, id))gY38OrigInit)(self, _cmd, identifier, delegate);
    if (me && gY38Delegate && delegate && [delegate isKindOfClass:gY38Delegate] && Y38_On()) {
        id ws = BPX_Obj0(me, "sceneWorkspace");
        if (ws) { BPX_SetObj1(ws, "setDelegate:", delegate); Y38_SET(me, kY38NewStyle, @YES); BPY_LOG(@"[y38] scene workspace controller %@: workspace delegate is %@", identifier, delegate); }
        else BP_Anomaly("y38-ctl", @"controller %@ has no sceneWorkspace: the 16.0 construction stays", identifier);
    }
    return me;
}
// -createSceneForProcessIdentity:withOptions:completion: 16.2 0x18edfca44
static void Y38_CtlCreate(id self, SEL _cmd, id processIdentity, id options, void (^completion)(id, id)) {
    if (!Y38_NewStyle(self) || !Y38_On()) { if (gY38OrigCreate) ((void (*)(id, SEL, id, id, id))gY38OrigCreate)(self, _cmd, processIdentity, options, completion); return; }
    if (!processIdentity || !options) { BP_Anomaly("y38-ctl", @"createSceneForProcessIdentity:withOptions:completion: with nil identity / options (16.2 asserts)"); return; }
    id ws = BPX_Obj0(self, "sceneWorkspace");
    id scene = ((id (*)(id, SEL, id))objc_msgSend)(ws, sel_registerName("createScene:"), ^(id creating) {                 // block 0x18edfcc90
        BPX_SetObj1(creating, "setIdentifier:", BPX_Obj0(options, "identifier"));
        BPX_SetObj1(creating, "setSpecification:", BPX_Obj0(options, "specification"));
        id ci = BPX_Obj1((id)NSClassFromString(@"FBSSceneClientIdentity"), "identityForProcessIdentity:", processIdentity);
        BPX_SetObj1(creating, "setClientIdentity:", ci);
    });
    BPY_LOG(@"[y38] workspace %@ created scene %@", BPX_Obj0(self, "sceneWorkspaceIdentifier"), scene);
    if (completion) completion(scene, nil);
}
// -invalidate 16.2 0x18edfd178
static void Y38_CtlInvalidate(id self, SEL _cmd) {
    if (!Y38_NewStyle(self) || !Y38_On()) { if (gY38OrigInvalidate) ((void (*)(id, SEL))gY38OrigInvalidate)(self, _cmd); return; }
    id ws = BPX_Obj0(self, "sceneWorkspace");
    for (id scene in BP_AsArray(BPX_Obj0(ws, "allScenes"))) { BPX_SetObj1(scene, "setDelegate:", nil); BPX_Obj0(scene, "invalidate"); }
    BPX_SetObj1(ws, "setDelegate:", nil);
    BPX_Obj0(ws, "invalidate");
}

__attribute__((constructor)) static void Y38_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        if (!objc_getClass("SBFSceneWorkspaceDefaultDelegate")) {
            Class c = objc_allocateClassPair([NSObject class], "SBFSceneWorkspaceDefaultDelegate", 0);
            if (c) {
                ADD(c, "init", Y38_DInit, "@16@0:8");
                ADD(c, "setScene:shouldActivateUponClientConnection:withContextGenerator:", Y38_DSetActivateOnConnect, "v36@0:8@16B24@?28");
                ADD(c, "setScene:shouldBeKeptActiveWhileForeground:withContextGenerator:", Y38_DSetKeptActive, "v36@0:8@16B24@?28");
                ADD(c, "_setScene:cached:inContainer:withContextGenerator:", Y38_DSetScene, "v44@0:8@16B24@28@?36");
                ADD(c, "_setScene:activatesWithTransitionContextGeneratorBlock:", Y38_DSetGen, "v32@0:8@16@?24");
                ADD(c, "_cleanupTransitionContextGeneratorBlockForSceneIfNeeded:", Y38_DCleanup, "v24@0:8@16");
                ADD(c, "_activateScene:", Y38_DActivate, "v24@0:8@16");
                ADD(c, "workspace:clientDidConnectWithHandshake:", Y38_DClientConnected, "v32@0:8@16@24");
                ADD(c, "workspace:didAddScene:", Y38_DDidAdd, "v32@0:8@16@24");
                ADD(c, "workspace:willRemoveScene:", Y38_DWillRemove, "v32@0:8@16@24");
                ADD(c, "sceneDidActivate:", Y38_DDidActivate, "v24@0:8@16");
                ADD(c, "sceneDidDeactivate:withError:", Y38_DDidDeactivate, "v32@0:8@16@24");
                ADD(c, "sceneContentStateDidChange:", Y38_DContentState, "v24@0:8@16");
                const char *protos[] = { "SBFSceneWorkspaceControllerDelegate", "FBSceneWorkspaceDelegate", "FBSceneDelegate" };
                for (int i = 0; i < 3; i++) { Protocol *p = objc_getProtocol(protos[i]); if (p) class_addProtocol(c, p); }
                objc_registerClassPair(c);
            } else BP_Anomaly("y38-class", @"objc_allocateClassPair(SBFSceneWorkspaceDefaultDelegate) failed");
        }
        gY38Delegate = objc_getClass("SBFSceneWorkspaceDefaultDelegate");
        Class cc = NSClassFromString(@"SBFSceneWorkspaceController");
        if (cc && gY38Delegate && class_getInstanceMethod(cc, sel_registerName("initWithIdentifier:delegate:")) && class_getInstanceMethod(cc, sel_registerName("createSceneForProcessIdentity:withOptions:completion:")) &&
            class_getInstanceMethod(cc, sel_registerName("invalidate")) && class_getInstanceMethod(cc, sel_registerName("sceneWorkspace"))) {
            gY38OrigInit = BPX_Replace(cc, "initWithIdentifier:delegate:", (IMP)Y38_CtlInit);
            gY38OrigCreate = BPX_Replace(cc, "createSceneForProcessIdentity:withOptions:completion:", (IMP)Y38_CtlCreate);
            gY38OrigInvalidate = BPX_Replace(cc, "invalidate", (IMP)Y38_CtlInvalidate);
            n++;
        } else BP_Anomaly("y38-install", @"[y38] SBFSceneWorkspaceController selectors missing or the delegate class could not be made: controller hooks not installed");
        BP_Log(@"[y38] installed %d group(s) (switch y38_scenews)", n);
    }
}
#pragma clang diagnostic pop
