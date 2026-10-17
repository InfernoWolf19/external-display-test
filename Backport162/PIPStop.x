// PIPStop.x : 16.2 per display "stop / expand" path of Picture in Picture in SpringBoard (specs/VIDEO-EXTDISPLAY-0.7.4.md section 4).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).
//
// Symptom: a window lives on the extended display, the user swipes home (video goes to PiP), expanding the PiP restores the window half on the iPad display and half on the
// extended one. Cause: 16.0 -[SBPIPPegasusAdapter _postEnsuredInSwitcher_pictureInPictureController:didRequestStopForPictureInPictureViewController:
// sourceSceneSessionIdentifier:animated:] (0x1c60b5d10) only knows the main display (coordinator wide -isAnySwitcherVisible, [SBMainSwitcherControllerCoordinator sharedInstance],
// mainDisplaySceneManager, +entityWithApplicationForMainDisplay:withScenePersistenceIdentifier:), 16.2 (0x1c753a46c) works per display and has a cross display branch.
//
// Ported (full replacements of the 16.2 bodies, no %orig on the switch-on path):
//  1. -[SBPIPPegasusAdapter _postEnsuredInSwitcher_...] 16.2 0x1c753a46c..0x1c753af50 and every block it creates:
//       0x1c753af54 / 0x1c753b028 / 0x1c753b100  stop completion (showAllContentOnWindowScene:pipWindowScene animated:YES)
//       0x1c753af64 / 0x1c753c950                 modifyApplicationContext block (setActivatingEntity:)           (16.0 block 0x1c60b64c4 used setEntity:forLayoutRole:)
//       0x1c753af70 / 0x1c753b038                 activation completion handlers (stop the PiP, then show all content)
//       0x1c753b110 -> 0x1c753b24c -> 0x1c753b3c0 -> 0x1c753b5ac -> 0x1c753b6e0   morph configuration block and its nested two stage stop blocks (same shape as 16.0)
//       0x1c753b7fc                               restore completion (failure: layout state check on the PiP's window scene; Chamois branch cancels + shows all content)
//       0x1c753ba68, global blocks 0x1c753bae0 / 0x1c753bb40  hide the content view of the PiP container view controllers
//  2. new -[SBPIPPegasusAdapter _layoutStateContainsSceneForSourceSceneSessionIdentifier:bundleIdentifier:windowScene:] 16.2 0x1c753bdac (+ block 0x1c753bf28); 16.0 has the two
//     argument form (0x1c60b7228, coordinator wide) which stays untouched.
//  3. new -[SBPIPPegasusAdapter _activateSceneWithPersistenceIdentifier:pictureInPictureViewController:completion:] 16.2 0x1c753c584 (+ block 0x1c753c950) and the delegate
//     callback -[SBPIPPegasusAdapter pictureInPictureController:requestActivationOfSceneWithPersistenceIdentier:pictureInPictureViewController:completion:] 16.2 0x1c753c574
//     (16.0 PegasusKit never sends it; added for completeness, it forwards to the activation method exactly like 16.2).
//  4. -[SBPIPPegasusContainerAdapter performStopAnimationWithFinalInterfaceOrientation:finalLayerFrame:completionHandler:] 16.2 0x1c78e11bc (16.0 0x1c64312bc) with block
//     0x1c78e145c: when the source scene's window scene differs from the PiP's own, the PiP container view is hidden before _performStopAnimation... runs.
//
// Not used (not needed): the thread local trick of g1d_pipinsets (tOverlayInsetsSC). The only coordinator wide call that 16.2 still makes in the stop method is
// +[SBMainSwitcherControllerCoordinator sharedInstanceIfExists] -> _recentAppLayoutsController, exactly as here.
// Switch: g1d_pipstop (default on, under the master g1d; off = the 16.0 bodies). Setup: PIPStop_Setup(), called next to G1D_Setup().
// Log lines (Backport162.debug): "pipstop: ...".

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

#define PIPS_ON() (BP_OnName("g1d") && BP_OnName("g1d_pipstop"))
#define PIPS_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

@interface SBPIPPegasusAdapter : NSObject @end
@interface SBPIPPegasusContainerAdapter : NSObject @end

typedef void (^PIPSStopDone)(BOOL success, NSError *error);   // "v20@?0B8@\"NSError\"12"
typedef void (^PIPSVoid)(void);                               // "v8@?0"

// ------------------------------------------------------------------------------------------------ helpers

// object ivar by name (the adapters keep their PIP controller (weak), Pegasus controller and container view controller (weak) in ivars: object_getIvar reads the pointer)
static id PIPS_Ivar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return BP_ObjIvar(o, iv);
}
static id PIPS_Class(NSString *name) { return NSClassFromString(name); }
static id PIPS_WindowSceneManager(void) {                      // [SBApp windowSceneManager] (SBApp = the UIApplication of SpringBoard)
    return G1B_Send0([UIApplication sharedApplication], NSSelectorFromString(@"windowSceneManager"));
}
static id PIPS_WindowSceneForDisplayIdentity(id identity) {    // [[SBApp windowSceneManager] windowSceneForDisplayIdentity:identity]
    return G1B_Send1(PIPS_WindowSceneManager(), NSSelectorFromString(@"windowSceneForDisplayIdentity:"), identity);
}
static id PIPS_SceneManagerCoordinator(void) { return G1B_Send0(PIPS_Class(@"SBSceneManagerCoordinator"), NSSelectorFromString(@"sharedInstance")); }
static id PIPS_MainWorkspace(void) { return G1B_Send0(PIPS_Class(@"SBMainWorkspace"), NSSelectorFromString(@"sharedInstance")); }

// [pc showAllContentOnWindowScene:ws animated:YES]  (every call in the 16.2 method passes YES)
static void PIPS_ShowAll(id pc, id ws) {
    SEL s = NSSelectorFromString(@"showAllContentOnWindowScene:animated:");
    if (pc && [pc respondsToSelector:s]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(pc, s, ws, YES);
}
// -[PGPictureInPictureController stopPictureInPictureForApplication:sceneSessionPersistentIdentifier:animated:completionHandler:]
static void PIPS_Stop(id pegasus, id app, id sid, BOOL animated, PIPSStopDone done) {
    SEL s = NSSelectorFromString(@"stopPictureInPictureForApplication:sceneSessionPersistentIdentifier:animated:completionHandler:");
    if (pegasus && [pegasus respondsToSelector:s]) ((void (*)(id, SEL, id, id, BOOL, PIPSStopDone))objc_msgSend)(pegasus, s, app, sid, animated, done);
    else PIPS_LOG(@"pipstop: no Pegasus controller to stop %@ (%@)", sid, pegasus);          // last line guard: 16.2 would message nil here as well
}
// the stop completion block of 16.2 (0x1c753af54 / 0x1c753b028 / 0x1c753b100): show all content on the PiP's window scene
static PIPSStopDone PIPS_ShowAllDone(id pc, id pipWS) {
    return ^(BOOL success, NSError *error) { PIPS_ShowAll(pc, pipWS); };
}
// -[PGPictureInPictureController cancelPictureInPictureForApplication:sceneSessionPersistentIdentifier:]
static void PIPS_Cancel(id pegasus, id app, id sid) {
    SEL s = NSSelectorFromString(@"cancelPictureInPictureForApplication:sceneSessionPersistentIdentifier:");
    if (pegasus && [pegasus respondsToSelector:s]) ((void (*)(id, SEL, id, id))objc_msgSend)(pegasus, s, app, sid);
}
// the global blocks 0x1c753bb40 / 0x1c753bae0 enumerate with: hide the content view of the container's content view controller
static void PIPS_HideContainers(id adapter, id app, id sid) {
    SEL s = NSSelectorFromString(@"_enumerateContainerViewControllersForApplication:scenePersistenceIdentifier:usingBlock:");
    if (!adapter || ![adapter respondsToSelector:s]) return;
    void (^hide)(id) = ^(id containerVC) {
        UIView *v = G1B_Send0(G1B_Send0(containerVC, NSSelectorFromString(@"contentViewController")), NSSelectorFromString(@"viewIfLoaded"));
        [v setHidden:YES];
    };
    ((void (*)(id, SEL, id, id, void (^)(id)))objc_msgSend)(adapter, s, app, sid, hide);
}
static id PIPS_Entity(id app, id sid, id provider, id identity) {   // +[SBDeviceApplicationSceneEntity entityWithApplication:scenePersistenceIdentifier:sceneHandleProvider:displayIdentity:]
    id c = PIPS_Class(@"SBDeviceApplicationSceneEntity");
    SEL s = NSSelectorFromString(@"entityWithApplication:scenePersistenceIdentifier:sceneHandleProvider:displayIdentity:");
    if (!c || ![c respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(c, s, app, sid, provider, identity);
}
static BOOL PIPS_LayoutContains(id adapter, id sid, id bid, id windowScene) {   // the 16.2 selector (added below), through the runtime
    SEL s = NSSelectorFromString(@"_layoutStateContainsSceneForSourceSceneSessionIdentifier:bundleIdentifier:windowScene:");
    return (adapter && [adapter respondsToSelector:s]) ? ((BOOL (*)(id, SEL, id, id, id))objc_msgSend)(adapter, s, sid, bid, windowScene) : NO;
}

// ============================================================================================================
// 2. -_layoutStateContainsSceneForSourceSceneSessionIdentifier:bundleIdentifier:windowScene:  16.2 0x1c753bdac
// ============================================================================================================
// 16.0 0x1c60b7228 asks [[SBMainSwitcherControllerCoordinator sharedInstance] isAnySwitcherVisible] / layoutState; 16.2 asks the switcher controller of the window scene.
// Result: YES when no switcher is visible on that scene and one of its layout elements is the scene (persistence identifier equal to sid; without sid: bundle identifier equal).
static BOOL PIPS_LayoutContainsImp(id self, SEL _cmd, id sid, id bid, id windowScene) {
    if (!sid) return NO;                                                   // 0x1c753bde8: cbz x19
    __block BOOL found = NO;
    id sc = G1B_Send0(windowScene, NSSelectorFromString(@"switcherController"));
    if (!G1B_SendB0(sc, NSSelectorFromString(@"isAnySwitcherVisible"))) {
        id state = G1B_Send0(sc, NSSelectorFromString(@"layoutState"));
        id elements = G1B_Send0(state, NSSelectorFromString(@"elements"));
        SEL en = NSSelectorFromString(@"enumerateObjectsUsingBlock:");
        if (elements && [elements respondsToSelector:en]) {
            void (^blk)(id, BOOL *) = ^(id element, BOOL *stop) {          // 0x1c753bf28 "v24@?0@\"SBLayoutElement\"8^B16"
                id entity = G1B_Send0(G1B_Send0(element, NSSelectorFromString(@"workspaceEntity")), NSSelectorFromString(@"deviceApplicationSceneEntity"));
                BOOL r;
                if (sid) {
                    id pid = G1B_Send0(G1B_Send0(entity, NSSelectorFromString(@"sceneHandle")), NSSelectorFromString(@"persistenceIdentifier"));
                    r = pid ? [pid isEqualToString:sid] : NO;
                } else {
                    id app = G1B_Send0(entity, NSSelectorFromString(@"application"));
                    id eb = G1B_Send0(app, NSSelectorFromString(@"bundleIdentifier"));
                    r = [eb isEqualToString:bid];
                }
                found = r;
                *stop = r;
            };
            ((void (*)(id, SEL, void (^)(id, BOOL *)))objc_msgSend)(elements, en, blk);
        }
    }
    return found;
}

// ============================================================================================================
// 3. -_activateSceneWithPersistenceIdentifier:pictureInPictureViewController:completion:  16.2 0x1c753c584
// ============================================================================================================
static void PIPS_ActivateImp(id self, SEL _cmd, id sid, id pipVC, void (^completion)(BOOL)) {
    id pc = PIPS_Ivar(self, "_pipController");
    id sceneManager = G1B_Send1(PIPS_SceneManagerCoordinator(), NSSelectorFromString(@"sceneManagerForPersistenceIdentifier:"), sid);
    id handle = G1B_Send1(sceneManager, NSSelectorFromString(@"existingSceneHandleForPersistenceIdentifier:"), sid);
    id pipWS = G1B_Send0(pipVC, NSSelectorFromString(@"_sbWindowScene"));
    id pipConfig = G1B_Send0(pipWS, NSSelectorFromString(@"_sbDisplayConfiguration"));
    id handleIdentity = G1B_Send0(G1B_Send0(G1B_Send0(handle, NSSelectorFromString(@"sceneIfExists")), NSSelectorFromString(@"settings")), NSSelectorFromString(@"displayIdentity"));
    id targetWS = handleIdentity ? PIPS_WindowSceneForDisplayIdentity(handleIdentity) : nil;
    BOOL foreground = G1B_SendB0(G1B_Send0(G1B_Send0(handle, NSSelectorFromString(@"scene")), NSSelectorFromString(@"settings")), NSSelectorFromString(@"isForeground"));
    if (foreground && targetWS) {
        id bid = G1B_Send0(G1B_Send0(handle, NSSelectorFromString(@"application")), NSSelectorFromString(@"bundleIdentifier"));
        if (PIPS_LayoutContains(self, sid, bid, targetWS)) {                // the scene is already part of the layout of its own display: nothing to activate
            PIPS_LOG(@"pipstop: activate %@: already in the layout state of %@", sid, targetWS);
            if (completion) completion(YES);
            return;
        }
    }
    if (!sid || !pipConfig) {
        PIPS_LOG(@"pipstop: activate %@: no display configuration of the PiP window scene (%@)", sid, pipWS);
        if (completion) completion(NO);
        return;
    }
    id app = G1B_Send0(handle, NSSelectorFromString(@"application"));
    id entity = PIPS_Entity(app, sid, sceneManager, G1B_Send0(pipConfig, NSSelectorFromString(@"identity")));
    SEL sf = NSSelectorFromString(@"setFlag:forActivationSetting:"), so = NSSelectorFromString(@"setObject:forActivationSetting:");
    if ([entity respondsToSelector:sf]) ((void (*)(id, SEL, long long, unsigned int))objc_msgSend)(entity, sf, 1, 0x34);
    id contentType = [NSNumber numberWithInteger:(NSInteger)G1B_SendLL0(pc, NSSelectorFromString(@"contentType"))];
    if ([entity respondsToSelector:so]) ((void (*)(id, SEL, id, unsigned int))objc_msgSend)(entity, so, contentType, 0x35);
    id workspace = PIPS_MainWorkspace();
    SEL cr = NSSelectorFromString(@"createRequestWithOptions:displayConfiguration:");
    id request = [workspace respondsToSelector:cr] ? ((id (*)(id, SEL, unsigned long long, id))objc_msgSend)(workspace, cr, 0, pipConfig) : nil;
    G1B_SendV1(request, NSSelectorFromString(@"setOriginatingProcess:"), G1B_Send0(PIPS_Class(@"BSProcessHandle"), NSSelectorFromString(@"processHandle")));
    SEL mc = NSSelectorFromString(@"modifyApplicationContext:");
    if ([request respondsToSelector:mc]) {
        void (^modify)(id) = ^(id context) { G1B_SendV1(context, NSSelectorFromString(@"setActivatingEntity:"), entity); };   // 0x1c753c950
        ((void (*)(id, SEL, void (^)(id)))objc_msgSend)(request, mc, modify);
    }
    SEL ac = NSSelectorFromString(@"addCompletionHandler:");
    if ([request respondsToSelector:ac]) (void)((id (*)(id, SEL, void (^)(BOOL)))objc_msgSend)(request, ac, completion);
    G1B_SendB1(PIPS_MainWorkspace(), NSSelectorFromString(@"executeTransitionRequest:"), request);
}
static void PIPS_Activate(id adapter, id sid, id pipVC, void (^completion)(BOOL)) {
    SEL s = NSSelectorFromString(@"_activateSceneWithPersistenceIdentifier:pictureInPictureViewController:completion:");
    if (adapter && [adapter respondsToSelector:s]) ((void (*)(id, SEL, id, id, void (^)(BOOL)))objc_msgSend)(adapter, s, sid, pipVC, completion);
    else PIPS_LOG(@"pipstop: activation method missing on %@", adapter);                      // last line guard (the method is added by PIPStop_Setup)
}
// 16.2 0x1c753c574: the delegate callback only forwards (x3 -> x2, x4 -> x3, x5 -> x4)
static void PIPS_RequestActivationImp(id self, SEL _cmd, id controller, id sid, id pipVC, void (^completion)(BOOL)) {
    PIPS_Activate(self, sid, pipVC, completion);
}

// ============================================================================================================
// 1. -_postEnsuredInSwitcher_...  16.2 0x1c753a46c
// ============================================================================================================
// the "morph" branch (0x1c753ad54..0x1c753aecc): the PiP expands with the morph animator; configuration block 0x1c753b110, restore completion 0x1c753b7fc
static void PIPS_Morph(id adapter, id ctrl, id pipApp, id bid, id sid, id pc, id pipWS, id pipVC, id entity, BOOL chamois) {
    void (^config)(id) = ^(id morphController) {                                                // 0x1c753b110 "v16@?0@\"SBPIPMorphAnimatorController\"8"
        __weak id weakController = morphController;
        PIPSVoid setup = ^{                                                                     // 0x1c753b24c: setupCompletionBlock
            PIPS_LOG(@"pipstop: morph setup completed, begin two stage stop of %@", sid);
            SEL begin = NSSelectorFromString(@"beginTwoStageStopPictureInPictureForApplication:withSceneSessionPersistentIdentifier:animated:byRestoringUserInterfaceWithCompletionHandler:");
            PIPSStopDone restored = ^(BOOL success, NSError *error) {                           // 0x1c753b3c0
                PIPS_LOG(@"pipstop: two stage stop restoring handler success=%d error=%@", success, error);
                id c = weakController;
                if (success) {
                    PIPSVoid waiting = ^{                                                       // 0x1c753b5ac: animatorWaitingForExternalAnimationActionBlock
                        PIPS_LOG(@"pipstop: morph animator waiting, end two stage stop of %@", sid);
                        SEL end = NSSelectorFromString(@"endTwoStageStopPictureInPictureForApplication:withSceneSessionPersistentIdentifier:animated:completionHandler:");
                        PIPSStopDone ended = ^(BOOL ok, NSError *err) {                         // 0x1c753b6e0
                            PIPS_LOG(@"pipstop: end two stage stop error=%@", err);
                            id c2 = weakController;
                            id morphAnimator = G1B_Send0(c2, NSSelectorFromString(@"viewMorphAnimator"));
                            G1B_SendV1(morphAnimator, NSSelectorFromString(@"setTargetView:"), nil);
                            morphAnimator = G1B_Send0(c2, NSSelectorFromString(@"viewMorphAnimator"));
                            G1B_SendV1(morphAnimator, NSSelectorFromString(@"setTargetContentView:"), nil);
                            PIPS_ShowAll(pc, pipWS);
                        };
                        if ([ctrl respondsToSelector:end]) ((void (*)(id, SEL, id, id, BOOL, PIPSStopDone))objc_msgSend)(ctrl, end, pipApp, sid, YES, ended);
                    };
                    SEL aw = NSSelectorFromString(@"setAnimatorWaitingForExternalAnimationActionBlock:");
                    if ([c respondsToSelector:aw]) ((void (*)(id, SEL, PIPSVoid))objc_msgSend)(c, aw, waiting);
                } else {
                    PIPS_Cancel(PIPS_Ivar(adapter, "_pegasusController"), pipApp, sid);        // 0x1c753b544
                    G1B_SendV0(c, NSSelectorFromString(@"cancel"));
                }
            };
            if ([ctrl respondsToSelector:begin]) ((void (*)(id, SEL, id, id, BOOL, PIPSStopDone))objc_msgSend)(ctrl, begin, pipApp, sid, YES, restored);
        };
        SEL ss = NSSelectorFromString(@"setSetupCompletionBlock:");
        if ([morphController respondsToSelector:ss]) ((void (*)(id, SEL, PIPSVoid))objc_msgSend)(morphController, ss, setup);
    };
    void (^completion)(BOOL) = ^(BOOL success) {                                                // 0x1c753b7fc
        if (success) { PIPS_LOG(@"pipstop: restore of %@ completed", sid); return; }
        PIPS_LOG(@"pipstop: restore of %@ failed", sid);
        BOOL contains = PIPS_LayoutContains(adapter, sid, bid, pipWS);
        if (contains) {
            if (chamois) {
                PIPS_Cancel(ctrl, pipApp, sid);                                                 // 0x1c753b914
                PIPS_ShowAll(pc, pipWS);
            } else {
                id pegasus = PIPS_Ivar(adapter, "_pegasusController");                          // 0x1c753b99c
                PIPS_Stop(pegasus, pipApp, sid, YES, ^(BOOL ok, NSError *error) {               // 0x1c753ba68
                    if (ok) return;
                    PIPS_LOG(@"pipstop: stop after failed restore of %@ failed: %@", sid, error);
                    PIPS_Cancel(PIPS_Ivar(adapter, "_pegasusController"), pipApp, sid);
                    PIPS_HideContainers(adapter, pipApp, sid);
                });
            }
        } else {
            PIPS_Cancel(PIPS_Ivar(adapter, "_pegasusController"), pipApp, sid);                 // 0x1c753b934
            PIPS_HideContainers(adapter, pipApp, sid);
        }
    };
    SEL restore = NSSelectorFromString(@"restoreContentViewController:appSceneEntity:morphAnimatorConfigurationBlock:completion:");
    if ([pc respondsToSelector:restore]) ((void (*)(id, SEL, id, id, void (^)(id), void (^)(BOOL)))objc_msgSend)(pc, restore, pipVC, entity, config, completion);
}

// the "activation" branch (0x1c753aafc..0x1c753acc4): a transition request on the main workspace activates the scene, the completion stops the PiP
static void PIPS_ActivateViaWorkspace(id entity, id pc, id ctrl, id pipApp, id sid, id pipWS) {
    SEL sf = NSSelectorFromString(@"setFlag:forActivationSetting:"), so = NSSelectorFromString(@"setObject:forActivationSetting:");
    if ([entity respondsToSelector:sf]) ((void (*)(id, SEL, long long, unsigned int))objc_msgSend)(entity, sf, 1, 0x34);
    id contentType = [NSNumber numberWithInteger:(NSInteger)G1B_SendLL0(pc, NSSelectorFromString(@"contentType"))];
    if ([entity respondsToSelector:so]) ((void (*)(id, SEL, id, unsigned int))objc_msgSend)(entity, so, contentType, 0x35);
    SEL cr = NSSelectorFromString(@"createRequestWithOptions:");
    id workspace = PIPS_MainWorkspace();
    id request = [workspace respondsToSelector:cr] ? ((id (*)(id, SEL, unsigned long long))objc_msgSend)(workspace, cr, 0) : nil;
    G1B_SendV1(request, NSSelectorFromString(@"setOriginatingProcess:"), G1B_Send0(PIPS_Class(@"BSProcessHandle"), NSSelectorFromString(@"processHandle")));
    SEL mc = NSSelectorFromString(@"modifyApplicationContext:");
    if ([request respondsToSelector:mc]) {
        void (^modify)(id) = ^(id context) { G1B_SendV1(context, NSSelectorFromString(@"setActivatingEntity:"), entity); };   // 0x1c753af64
        ((void (*)(id, SEL, void (^)(id)))objc_msgSend)(request, mc, modify);
    }
    SEL ac = NSSelectorFromString(@"addCompletionHandler:");
    if ([request respondsToSelector:ac]) {
        void (^done)(BOOL) = ^(BOOL success) { PIPS_Stop(ctrl, pipApp, sid, YES, PIPS_ShowAllDone(pc, pipWS)); };                // 0x1c753af70
        (void)((id (*)(id, SEL, void (^)(BOOL)))objc_msgSend)(request, ac, done);
    }
    G1B_SendB1(PIPS_MainWorkspace(), NSSelectorFromString(@"executeTransitionRequest:"), request);
}

static void PIPS_PostEnsured(id adapter, id ctrl, id pipVC, id sid) {
    id pc = PIPS_Ivar(adapter, "_pipController");                                                // SBPIPController (weak ivar +0x8)
    id pipApp = G1B_Send0(pipVC, NSSelectorFromString(@"application"));
    id bid = G1B_Send0(pipApp, NSSelectorFromString(@"bundleIdentifier"));
    id pipWS = G1B_Send0(pipVC, NSSelectorFromString(@"_sbWindowScene"));
    BOOL layoutContains = PIPS_LayoutContains(adapter, sid, bid, pipWS);                         // on the PiP's own window scene
    id sc = G1B_Send0(pipWS, NSSelectorFromString(@"switcherController"));
    BOOL anyVisible = G1B_SendB0(sc, NSSelectorFromString(@"isAnySwitcherVisible"));
    BOOL anyPeek = G1B_SendB0(sc, NSSelectorFromString(@"isInAnyPeekState"));
    long long envMode = G1B_SendLL0(sc, NSSelectorFromString(@"unlockedEnvironmentMode"));
    BOOL chamois = G1B_SendB0(G1B_Send0(pipWS, NSSelectorFromString(@"switcherController")), NSSelectorFromString(@"isChamoisWindowingUIEnabled"));
    id sceneManager = G1B_Send1(PIPS_SceneManagerCoordinator(), NSSelectorFromString(@"sceneManagerForPersistenceIdentifier:"), sid);
    id handle = G1B_Send1(sceneManager, NSSelectorFromString(@"existingSceneHandleForPersistenceIdentifier:"), sid);

    // the scene's layout on the recents list (0x1c753a5c8..0x1c753a7e0): occluded flag (w25) and "not floating" (w24); the last matching layout wins
    BOOL occluded = NO, floating = NO;
    if (sid && bid) {
        id coordinator = G1B_Send0(PIPS_Class(@"SBMainSwitcherControllerCoordinator"), NSSelectorFromString(@"sharedInstanceIfExists"));
        id recentsController = G1B_Send0(coordinator, NSSelectorFromString(@"_recentAppLayoutsController"));
        SEL rs = NSSelectorFromString(@"recentsForBundleIdentifier:includingHiddenAppLayouts:");
        id recents = [recentsController respondsToSelector:rs] ? ((id (*)(id, SEL, id, BOOL))objc_msgSend)(recentsController, rs, bid, NO) : nil;
        SEL ai = NSSelectorFromString(@"allItems");
        for (id layout in (NSArray *)recents) {
            for (id item in (NSArray *)G1B_Send0(layout, ai)) {
                id uid = G1B_Send0(item, NSSelectorFromString(@"uniqueIdentifier"));
                id sceneID = G1B_Send0(handle, NSSelectorFromString(@"sceneIdentifier"));
                if (![uid isEqualToString:sceneID]) continue;
                floating = G1B_SendLL0(layout, NSSelectorFromString(@"environment")) == 2;
                if (chamois) {
                    id attributes = G1B_Send1(layout, NSSelectorFromString(@"layoutAttributesForItem:"), item);
                    occluded = G1B_SendLL0(attributes, NSSelectorFromString(@"occlusionState")) != 1;
                } else occluded = NO;
                break;
            }
        }
    }
    BOOL notFloating = !floating;
    BOOL transaction = G1B_Send0(PIPS_MainWorkspace(), NSSelectorFromString(@"currentTransaction")) != nil;
    BOOL locked = G1B_SendB0(G1B_Send0(PIPS_Class(@"SBLockScreenManager"), NSSelectorFromString(@"sharedInstanceIfExists")), NSSelectorFromString(@"isUILocked"));
    SEL hide = NSSelectorFromString(@"hideContainersExcludingContainerForContentViewControllerAndTetheredOnes:animated:");
    if ([pc respondsToSelector:hide]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(pc, hide, pipVC, YES);

    id scene = G1B_Send0(handle, NSSelectorFromString(@"sceneIfExists"));
    // 16.2: [handle displayIdentity] is the display of the scene manager that owns the scene, which is the display the scene is shown on.  Here a scene can live in the MAIN display's
    // scene manager while its FBScene is shown on the extended display (device log f7965a9c 08:55:37: handle identity Main, scene settings identity AirPlay.main): the restore then opened
    // the window on the iPad.  The display of the scene itself is what 16.2's identity stands for.
    id handleIdentity = G1B_Send0(handle, NSSelectorFromString(@"displayIdentity"));
    id sceneIdentity = G1B_Send0(G1B_Send0(scene, NSSelectorFromString(@"settings")), NSSelectorFromString(@"displayIdentity"));
    id entityIdentity = sceneIdentity ?: handleIdentity;
    if (sceneIdentity && handleIdentity && ![sceneIdentity isEqual:handleIdentity]) PIPS_LOG(@"pipstop: scene shown on %@ but owned by the scene manager of %@: restoring on the scene's display", sceneIdentity, handleIdentity);
    id entity = PIPS_Entity(G1B_Send0(handle, NSSelectorFromString(@"application")), sid, sceneManager, entityIdentity);
    if (BP_LogEnabled()) {
        id hid = G1B_Send0(handle, NSSelectorFromString(@"displayIdentity"));
        id eh = G1B_Send0(entity, NSSelectorFromString(@"sceneHandle"));
        BP_Log(@"pipstop: expand display: handle identity %@ (config %@), scene manager %@ identity %@, entity %@ sceneHandle %@ identity %@ config %@, scene settings identity %@",
               hid, G1B_Send0(hid, NSSelectorFromString(@"currentConfiguration")), sceneManager, G1B_Send0(sceneManager, NSSelectorFromString(@"displayIdentity")),
               entity, eh, G1B_Send0(eh, NSSelectorFromString(@"displayIdentity")), G1B_Send0(G1B_Send0(G1B_Send0(eh, NSSelectorFromString(@"displayIdentity")), NSSelectorFromString(@"currentConfiguration")), NSSelectorFromString(@"identity")),
               G1B_Send0(G1B_Send0(scene, NSSelectorFromString(@"settings")), NSSelectorFromString(@"displayIdentity")));
    }
    id targetWS = nil;
    if (G1B_SendB0(G1B_Send0(scene, NSSelectorFromString(@"settings")), NSSelectorFromString(@"isForeground")))
        targetWS = PIPS_WindowSceneForDisplayIdentity(G1B_Send0(G1B_Send0(scene, NSSelectorFromString(@"settings")), NSSelectorFromString(@"displayIdentity")));
    if (BP_LogEnabled())
        BP_Log(@"pipstop: expand %@ (%@): pipWS %@ target %@ handle %@ layoutContains %d notFloating %d occluded %d visible %d peek %d mode %lld chamois %d transaction %d locked %d",
               sid, bid, pipWS, targetWS, handle, layoutContains, notFloating, occluded, anyVisible, anyPeek, envMode, chamois, transaction, locked);

    if (targetWS && targetWS != pipWS) {                                                         // 0x1c753a920..0x1c753a9d4: the scene is on another display than the PiP
        BOOL animated = !PIPS_LayoutContains(adapter, sid, bid, targetWS);
        PIPS_LOG(@"pipstop: cross display stop (animated %d)", animated);
        PIPS_Stop(PIPS_Ivar(adapter, "_pegasusController"), pipApp, sid, animated, PIPS_ShowAllDone(pc, pipWS));
        return;
    }
    if (!(notFloating || layoutContains) || (envMode == 3 && chamois && !layoutContains)) {      // 0x1c753a9ec..0x1c753aa14 (mode 3 = Stage Manager)
        PIPS_LOG(@"pipstop: branch activate through the workspace");
        PIPS_ActivateViaWorkspace(entity, pc, ctrl, pipApp, sid, pipWS);
        return;
    }
    if (anyPeek || anyVisible || layoutContains || transaction || locked) {                      // 0x1c753aa34..0x1c753aa40
        if (occluded) {                                                                          // 0x1c753aa48
            PIPS_LOG(@"pipstop: branch activate the occluded scene, then stop");
            void (^done)(BOOL) = ^(BOOL success) { PIPS_Stop(ctrl, pipApp, sid, YES, PIPS_ShowAllDone(pc, pipWS)); };   // 0x1c753b038
            PIPS_Activate(adapter, sid, pipVC, done);
        } else {                                                                                 // 0x1c753aed0
            PIPS_LOG(@"pipstop: branch stop");
            PIPS_Stop(ctrl, pipApp, sid, YES, PIPS_ShowAllDone(pc, pipWS));
        }
        return;
    }
    PIPS_LOG(@"pipstop: branch morph");
    PIPS_Morph(adapter, ctrl, pipApp, bid, sid, pc, pipWS, pipVC, entity, chamois);              // 0x1c753ad54
}

// ============================================================================================================
// 4. -[SBPIPPegasusContainerAdapter performStopAnimationWithFinalInterfaceOrientation:finalLayerFrame:completionHandler:]  16.2 0x1c78e11bc
// ============================================================================================================
static void PIPS_PerformStop(id adapter, long long orientation, CGRect frame, id handler) {
    id container = PIPS_Ivar(adapter, "_containerViewController");                                // weak ivar +0x8
    id pipWS = G1B_Send0(container, NSSelectorFromString(@"_sbWindowScene"));
    id pipVC = PIPS_Ivar(adapter, "_pictureInPictureViewController");                             // +0x50
    id sid = G1B_Send0(pipVC, NSSelectorFromString(@"sourceSceneSessionPersistentIdentifier"));
    id sceneManager = G1B_Send1(PIPS_SceneManagerCoordinator(), NSSelectorFromString(@"sceneManagerForPersistenceIdentifier:"), sid);
    id handle = G1B_Send1(sceneManager, NSSelectorFromString(@"existingSceneHandleForPersistenceIdentifier:"), sid);
    id settings = G1B_Send0(G1B_Send0(handle, NSSelectorFromString(@"sceneIfExists")), NSSelectorFromString(@"settings"));
    id targetWS = G1B_SendB0(settings, NSSelectorFromString(@"isForeground")) ? PIPS_WindowSceneForDisplayIdentity(G1B_Send0(settings, NSSelectorFromString(@"displayIdentity"))) : nil;
    __weak id weakAdapter = adapter;
    PIPSVoid afterAnimations = ^{                                                                 // 0x1c78e145c
        if (targetWS && targetWS != pipWS) {                                                      // the source scene is on another display: the PiP view must not morph here
            PIPS_LOG(@"pipstop: stop animation: hide the PiP container view (source scene on %@, PiP on %@)", targetWS, pipWS);
            UIView *view = G1B_Send0(container, NSSelectorFromString(@"view"));
            [view setHidden:YES];
        }
        id strongAdapter = weakAdapter;
        SEL s = NSSelectorFromString(@"_performStopAnimationWithFinalInterfaceOrientation:finalLayerFrame:completionHandler:");
        if (strongAdapter && [strongAdapter respondsToSelector:s])
            ((void (*)(id, SEL, long long, CGRect, id))objc_msgSend)(strongAdapter, s, orientation, frame, handler);
    };
    SEL pa = NSSelectorFromString(@"performAfterInFlightAnimationsComplete:");
    if (container && [container respondsToSelector:pa]) ((void (*)(id, SEL, PIPSVoid))objc_msgSend)(container, pa, afterAnimations);
}

%group PIPStop
%hook SBPIPPegasusAdapter
- (void)_postEnsuredInSwitcher_pictureInPictureController:(id)controller didRequestStopForPictureInPictureViewController:(id)viewController sourceSceneSessionIdentifier:(id)identifier animated:(BOOL)animated {
    if (!PIPS_ON()) {
        %orig;
        return;
    }
    PIPS_PostEnsured(self, controller, viewController, identifier);
}
%end
%hook SBPIPPegasusContainerAdapter
- (void)performStopAnimationWithFinalInterfaceOrientation:(long long)orientation finalLayerFrame:(CGRect)frame completionHandler:(id)handler {
    if (!PIPS_ON()) {
        %orig;
        return;
    }
    PIPS_PerformStop(self, orientation, frame, handler);
}
%end
%end // PIPStop

// the three methods that exist in 16.2 only (16.0 has the two argument -_layoutStateContainsScene... which is left alone)
static void PIPS_AddMethod(Class cls, const char *sel, IMP imp, const char *types) {
    if (!class_addMethod(cls, sel_registerName(sel), imp, types)) PIPS_LOG(@"pipstop: %s already implemented by %s, left alone", sel, class_getName(cls));
}

void PIPStop_Setup(void) {
    if (!PIPS_ON()) return;
    Class adapter = NSClassFromString(@"SBPIPPegasusAdapter");
    if (adapter) {
        PIPS_AddMethod(adapter, "_layoutStateContainsSceneForSourceSceneSessionIdentifier:bundleIdentifier:windowScene:", (IMP)PIPS_LayoutContainsImp, "B40@0:8@16@24@32");
        PIPS_AddMethod(adapter, "_activateSceneWithPersistenceIdentifier:pictureInPictureViewController:completion:", (IMP)PIPS_ActivateImp, "v40@0:8@16@24@?32");
        PIPS_AddMethod(adapter, "pictureInPictureController:requestActivationOfSceneWithPersistenceIdentier:pictureInPictureViewController:completion:", (IMP)PIPS_RequestActivationImp, "v48@0:8@16@24@32@?40");
    }
    %init(PIPStop);
}
#pragma clang diagnostic pop
