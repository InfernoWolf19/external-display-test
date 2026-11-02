// Y41SystemUIClients.x : S1 system UI scene family, step 7 (DELTA-SWEEP-0.7.9.md Pass 4 section 1): the application support service / scene request side of the system UI scene clients (the clients of
// Y40SystemUIScenes.x: eyedropperd, MomentsUIService, AccessibilityUIServer, ...).  Setup: constructor.  Log prefix "[y41]".  Switch y41_sysuiclients (default ON, kill file Backport162.off.y41_sysuiclients).
//
// 16.2 (16.0 in brackets):
//   +[SBApplicationSupportServiceRequestContext initializationContextForClient:] 0x1c77ea600 [0x1c6345d28]: a client for which +[SBSystemUIScenesCoordinator isSystemUISceneClientPID:] answers YES gets
//   +[UISApplicationInitializationContext sb_embeddedDisplayDefaultContextForSystemUIScenes] (a nil context is logged as an error) BEFORE the sequence that 16.0 has too (application of the pid / bundle id, Spotlight /
//   PaperBoard, _initializationContext, host process); NEW +shouldOverrideClientInitialization: 0x1c77ea5bc (= isSystemUISceneClientPID:[client pid]);
//   -[SBApplicationSupportServiceDelegate service:overrideClientInitialization:] 0x1c764ee7c [0x1c61c050c: NO] answers that class method;
//   NEW +[UISApplicationInitializationContext(SpringBoard) sb_embeddedDisplayDefaultContextForSystemUIScenes] 0x1c7536608 ([[self alloc] initWithMainDisplayContext:[UISDisplayContext
//   sb_mainThreadFree_embeddedDisplayDefaultContext] launchDisplayContext:nil deviceContext:[UISDeviceContext sb_defaultContext] persistedSceneIdentifiers:nil supportAppSceneRequests:YES]) and NEW
//   +[UISDisplayContext(SpringBoard) sb_mainThreadFree_embeddedDisplayDefaultContext] 0x1c753646c (sb_embeddedDisplayDefaultContext 0x1c7536290 without the user interface style);
//   -destroyScenesWithPersistentIdentifiers:animationType:destroySessions:forClient:completion: 0x1c764f3f4 [0x1c61c0a7c]: a system UI scene client is handled first (main queue: [[SBApp systemUIScenesCoordinator]
//   sceneWorkspaceControllerForProcessIdentity:[process identity]] destroyScenesWithPersistentIdentifiers:processIdentity:completion:, error code 1 "SpringBoard has not finished booting yet." without a coordinator),
//   every other client takes the application block;
//   -[SBSceneManagerCoordinator workspace:didReceiveSceneRequestWithOptions:completion:] 0x1c77ad8dc [0x1c630f438]: a system UI scene client (isSystemUISceneClientIdentity:[[options process] identity]) is
//   served on the main queue by the system UI controller of its identity (options must be a UISceneRequestOptions, else error code 1 "Unexpected type of scene request options: [%@]. Expected type
//   [UISceneRequestOptions]."), an application process only creates scenes for its application (error "Scene creation failed, invalid application" instead of the 16.0 fall back to the system UI coordinator),
//   the entitlement branch is unchanged;
//   +[SpringBoard _newApplicationInitializationContext] 0x1c7363804 [0x1c5eef658]: only [UISMutableApplicationInitializationContext sb_embeddedDisplayDefaultContext] (16.0 also set the default scene token of the
//   SpringBoard bundle id when SBChamoisUISceneLifecycleIsEnabled() was NO).
//
// Not ported (exact): the application branch of -destroyScenesWithPersistentIdentifiers:... of 16.2 (block_invoke_2 0x1c764f860) looks the running application up INSIDE the block, 16.0 before the dispatch; the port
// leaves that branch to the 16.0 method (same lookups, same SBWorkspaceDestroyApplicationSceneHandlesWithIntent), so a client that is neither an application nor a system UI scene client gets the 16.0 system UI
// coordinator path instead of the 16.2 error code 2 "No scene handles found for provided persistence IDs." (the lookup _SBRunningApplicationForAuditToken is a SpringBoard internal function that has no exported name).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define Y41_NEWRET __attribute__((ns_returns_retained))
static IMP gY41InitCtx, gY41Destroy, gY41SceneRequest;
static long long (*gY41ArtworkSubtype)(void);                                                // SBFEffectiveArtworkSubtype (SpringBoardFoundation)
static BOOL Y41_On(void) { return BP_OnName("y41_sysuiclients"); }
static id Y41_Send0(id o, const char *sel) { SEL s = sel_registerName(sel); return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static id Y41_SystemUICoordinator(void) { return Y41_Send0(BPX_App(), "systemUIScenesCoordinator"); }
static BOOL Y41_IsSystemUIClientPID(int pid) {
    Class c = objc_getClass("SBSystemUIScenesCoordinator");
    SEL s = sel_registerName("isSystemUISceneClientPID:");
    return c && class_getClassMethod(c, s) && ((BOOL (*)(id, SEL, int))objc_msgSend)((id)c, s, pid);
}
static BOOL Y41_IsSystemUIClientIdentity(id identity) {
    Class c = objc_getClass("SBSystemUIScenesCoordinator");
    SEL s = sel_registerName("isSystemUISceneClientIdentity:");
    return c && class_getClassMethod(c, s) && ((BOOL (*)(id, SEL, id))objc_msgSend)((id)c, s, identity);
}

// ------------------------------------------------------------------------------------------------ the contexts
// +[UISDisplayContext sb_mainThreadFree_embeddedDisplayDefaultContext] 0x1c753646c
static id Y41_MainThreadFreeDisplayContext(id cls, SEL _cmd) {
    id c = BPX_Obj0((id)objc_getClass("UISMutableDisplayContext"), "defaultContext");
    BPX_SetObj1(c, "setDisplayConfiguration:", BPX_Obj0(BPX_Obj0((id)objc_getClass("FBDisplayManager"), "sharedInstance"), "mainConfiguration"));
    BPX_SetObj1(c, "setDisplayEdgeInfo:", BPX_Obj0((id)objc_getClass("UISApplicationSupportDisplayEdgeInfo"), "sb_thisDeviceDisplayEdgeInfo"));
    BPX_SetObj1(c, "setExclusionArea:", BPX_Obj0((id)objc_getClass("UISDisplaySingleRectShape"), "sb_thisDeviceDisplayShape"));
    ((void (*)(id, SEL, long long))objc_msgSend)(c, sel_registerName("setArtworkSubtype:"), gY41ArtworkSubtype());
    return c;
}
// +[UISApplicationInitializationContext sb_embeddedDisplayDefaultContextForSystemUIScenes] 0x1c7536608
static id Y41_SystemUIContext(id cls, SEL _cmd) {
    id main = BPX_Obj0((id)objc_getClass("UISDisplayContext"), "sb_mainThreadFree_embeddedDisplayDefaultContext");
    id dev = BPX_Obj0((id)objc_getClass("UISDeviceContext"), "sb_defaultContext");
    return ((id (*)(id, SEL, id, id, id, id, BOOL))objc_msgSend)([cls alloc], sel_registerName("initWithMainDisplayContext:launchDisplayContext:deviceContext:persistedSceneIdentifiers:supportAppSceneRequests:"), main, nil, dev, nil, YES);
}
// +[SBApplicationSupportServiceRequestContext shouldOverrideClientInitialization:] 0x1c77ea5bc
static BOOL Y41_ClientPID(id client, int *pid) {
    SEL s = sel_registerName("pid");
    if (!client || ![client respondsToSelector:s]) return NO;
    *pid = ((int (*)(id, SEL))objc_msgSend)(client, s);
    return YES;
}
static BOOL Y41_ShouldOverride(id cls, SEL _cmd, id client) { int pid = 0; return Y41_ClientPID(client, &pid) && Y41_IsSystemUIClientPID(pid); }
// -[SBApplicationSupportServiceDelegate service:overrideClientInitialization:] 0x1c764ee7c
static BOOL Y41_OverrideInit(id self, SEL _cmd, id service, id client) {
    int pid = 0;
    return Y41_On() && Y41_ClientPID(client, &pid) && Y41_IsSystemUIClientPID(pid);
}
// +[SBApplicationSupportServiceRequestContext initializationContextForClient:] 0x1c77ea600
static id Y41_InitContext(id cls, SEL _cmd, id client) {
    int pid = 0;
    if (Y41_On() && Y41_ClientPID(client, &pid) && Y41_IsSystemUIClientPID(pid)) {
        id ctx = BPX_Obj0((id)objc_getClass("UISApplicationInitializationContext"), "sb_embeddedDisplayDefaultContextForSystemUIScenes");
        if (!ctx) BP_Anomaly("y41-context", @"sb_embeddedDisplayDefaultContextForSystemUIScenes answered nil for pid %d (16.2 logs an error)", pid);
        BPY_LOG(@"[y41] system UI scene client pid %d gets the system UI scenes initialization context", pid);
        return ctx;
    }
    return gY41InitCtx ? ((id (*)(id, SEL, id))gY41InitCtx)(cls, _cmd, client) : nil;
}
// +[SpringBoard _newApplicationInitializationContext] 0x1c7363804 (new family: +1)
static Y41_NEWRET id Y41_NewAppInitContext(id cls, SEL _cmd) {
    return BPX_Obj0((id)objc_getClass("UISMutableApplicationInitializationContext"), "sb_embeddedDisplayDefaultContext");
}

// ------------------------------------------------------------------------------------------------ the destroy request of the application support service
static NSError *Y41_Error(NSString *domain, NSInteger code, NSString *key, NSString *msg) { return [NSError errorWithDomain:domain code:code userInfo:@{ key: msg }]; }
static void Y41_Destroy(id self, SEL _cmd, id ids, unsigned long long type, BOOL sessions, id client, void (^completion)(NSError *)) {
    int pid = 0;
    if (!Y41_On() || !Y41_ClientPID(client, &pid) || !Y41_IsSystemUIClientPID(pid)) {
        if (gY41Destroy) ((void (*)(id, SEL, id, unsigned long long, BOOL, id, id))gY41Destroy)(self, _cmd, ids, type, sessions, client, completion);
        return;
    }
    id process = ((id (*)(id, SEL, int))objc_msgSend)(BPX_Obj0((id)objc_getClass("FBProcessManager"), "sharedInstance"), sel_registerName("processForPID:"), pid);
    dispatch_async(dispatch_get_main_queue(), ^{                                                                          // block 0x1c764f72c
        id coord = Y41_SystemUICoordinator();
        if (!coord) { if (completion) completion(Y41_Error(@"SBApplicationSupportService", 1, NSDebugDescriptionErrorKey, @"SpringBoard has not finished booting yet.")); return; }
        id identity = BPX_Obj0(process, "identity");
        id ctl = BPX_Obj1(coord, "sceneWorkspaceControllerForProcessIdentity:", identity);
        if (ctl) ((void (*)(id, SEL, id, id, id))objc_msgSend)(ctl, sel_registerName("destroyScenesWithPersistentIdentifiers:processIdentity:completion:"), ids, identity, completion);
        else BP_Anomaly("y41-destroy", @"no system UI scene controller for %@", identity);
    });
}

// ------------------------------------------------------------------------------------------------ the scene request of the workspace
static void Y41_SceneRequest(id self, SEL _cmd, id workspace, id options, void (^completion)(id, NSError *)) {
    id process = BPX_Obj0(options, "process");
    id identity = BPX_Obj0(process, "identity");
    if (!Y41_On() || !Y41_IsSystemUIClientIdentity(identity)) {
        if (Y41_On() && BPX_Bool0(process, "isApplicationProcess")) {                                                       // block 0x1c77addc8
            __weak id wself = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                id app = ((id (*)(id, SEL, int))objc_msgSend)(BPX_Obj0((id)objc_getClass("SBApplicationController"), "sharedInstance"), sel_registerName("applicationWithPid:"), ({ int pp = 0; Y41_ClientPID(process, &pp); pp; }));
                if (app) ((void (*)(id, SEL, id, id, id))objc_msgSend)(wself, sel_registerName("_createSceneForApplication:withOptions:completion:"), app, options, completion);
                else if (completion) completion(nil, Y41_Error(@"SBSceneManagerDomain", 1, NSDebugDescriptionErrorKey, @"Scene creation failed, invalid application"));
            });
            return;
        }
        if (gY41SceneRequest) ((void (*)(id, SEL, id, id, id))gY41SceneRequest)(self, _cmd, workspace, options, completion);                // the entitlement branch (0x1c77adef8 = 16.0 block 2)
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{                                                                          // block 0x1c77adbb0
        id coord = Y41_SystemUICoordinator();
        if (!coord) { if (completion) completion(nil, Y41_Error(@"SBSceneManagerDomain", 1, NSDebugDescriptionErrorKey, @"SpringBoard has not finished booting yet.")); return; }
        id ctl = BPX_Obj1(coord, "sceneWorkspaceControllerForProcessIdentity:", identity);
        Class oc = objc_getClass("UISceneRequestOptions");
        if (oc && [options isKindOfClass:oc]) {
            if (ctl) ((void (*)(id, SEL, id, id, id))objc_msgSend)(ctl, sel_registerName("createSceneForProcessIdentity:withOptions:completion:"), identity, options, completion);
            else BP_Anomaly("y41-request", @"no system UI scene controller for %@: the request is not answered (as 16.2: message to nil)", identity);
        } else if (completion) {
            completion(nil, Y41_Error(@"SBSceneManagerDomain", 1, NSLocalizedFailureReasonErrorKey, [NSString stringWithFormat:@"Unexpected type of scene request options: [%@]. Expected type [UISceneRequestOptions].", NSStringFromClass([options class])]));
        }
    });
}

__attribute__((constructor)) static void Y41_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        NSMutableArray *missing = [NSMutableArray array];
        Class ctxCls = objc_getClass("SBApplicationSupportServiceRequestContext"), delegate = objc_getClass("SBApplicationSupportServiceDelegate"), mgr = objc_getClass("SBSceneManagerCoordinator");
        Class sb = objc_getClass("SpringBoard"), dctx = objc_getClass("UISDisplayContext"), actx = objc_getClass("UISApplicationInitializationContext");
        gY41ArtworkSubtype = (long long (*)(void))dlsym(RTLD_DEFAULT, "SBFEffectiveArtworkSubtype");
        if (!gY41ArtworkSubtype) [missing addObject:@"symbol SBFEffectiveArtworkSubtype (SpringBoardFoundation)"];
        if (!ctxCls || !class_getClassMethod(ctxCls, sel_registerName("initializationContextForClient:"))) [missing addObject:@"+[SBApplicationSupportServiceRequestContext initializationContextForClient:]"];
        if (!delegate || !class_getInstanceMethod(delegate, sel_registerName("service:overrideClientInitialization:"))) [missing addObject:@"-[SBApplicationSupportServiceDelegate service:overrideClientInitialization:]"];
        if (!delegate || !class_getInstanceMethod(delegate, sel_registerName("destroyScenesWithPersistentIdentifiers:animationType:destroySessions:forClient:completion:"))) [missing addObject:@"-[SBApplicationSupportServiceDelegate destroyScenesWithPersistentIdentifiers:...]"];
        if (!mgr || !class_getInstanceMethod(mgr, sel_registerName("workspace:didReceiveSceneRequestWithOptions:completion:"))) [missing addObject:@"-[SBSceneManagerCoordinator workspace:didReceiveSceneRequestWithOptions:completion:]"];
        if (!mgr || !class_getInstanceMethod(mgr, sel_registerName("_createSceneForApplication:withOptions:completion:"))) [missing addObject:@"-[SBSceneManagerCoordinator _createSceneForApplication:withOptions:completion:]"];
        if (!sb || !class_getClassMethod(sb, sel_registerName("_newApplicationInitializationContext"))) [missing addObject:@"+[SpringBoard _newApplicationInitializationContext]"];
        if (!dctx || !objc_getClass("UISMutableDisplayContext") || !objc_getClass("UISDeviceContext") || !objc_getClass("FBDisplayManager")) [missing addObject:@"classes UISDisplayContext / UISMutableDisplayContext / UISDeviceContext / FBDisplayManager"];
        if (!actx || !objc_getClass("UISMutableApplicationInitializationContext") || !class_getInstanceMethod(actx, sel_registerName("initWithMainDisplayContext:launchDisplayContext:deviceContext:persistedSceneIdentifiers:supportAppSceneRequests:"))) [missing addObject:@"UISApplicationInitializationContext initWithMainDisplayContext:..."];
        if (!objc_getClass("SBSystemUIScenesCoordinator") || !class_getClassMethod(objc_getClass("SBSystemUIScenesCoordinator"), sel_registerName("isSystemUISceneClientPID:"))) [missing addObject:@"+[SBSystemUIScenesCoordinator isSystemUISceneClientPID:] (Y40SystemUIScenes.x)"];
        if ([missing count]) {
            BP_Anomaly("y41-install", @"[y41] system UI scene client side NOT installed (16.0 behaviour stays), needs: %@", [missing componentsJoinedByString:@", "]);
            return;
        }
        class_addMethod(object_getClass(dctx), sel_registerName("sb_mainThreadFree_embeddedDisplayDefaultContext"), (IMP)Y41_MainThreadFreeDisplayContext, "@16@0:8");
        class_addMethod(object_getClass(actx), sel_registerName("sb_embeddedDisplayDefaultContextForSystemUIScenes"), (IMP)Y41_SystemUIContext, "@16@0:8");
        class_addMethod(object_getClass(ctxCls), sel_registerName("shouldOverrideClientInitialization:"), (IMP)Y41_ShouldOverride, "B24@0:8@16");
        gY41InitCtx = BPX_Replace(object_getClass(ctxCls), "initializationContextForClient:", (IMP)Y41_InitContext);
        BPX_Replace(delegate, "service:overrideClientInitialization:", (IMP)Y41_OverrideInit);
        gY41Destroy = BPX_Replace(delegate, "destroyScenesWithPersistentIdentifiers:animationType:destroySessions:forClient:completion:", (IMP)Y41_Destroy);
        gY41SceneRequest = BPX_Replace(mgr, "workspace:didReceiveSceneRequestWithOptions:completion:", (IMP)Y41_SceneRequest);
        BPX_Replace(object_getClass(sb), "_newApplicationInitializationContext", (IMP)Y41_NewAppInitContext);
        BP_Log(@"[y41] installed: system UI scene client side (switch y41_sysuiclients)");
    }
}
#pragma clang diagnostic pop
