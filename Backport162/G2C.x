// G2C.x : 16.2 auto-hide of the Stage Manager window resize grabbers (the small dark corner marks).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Findings, evidence and what is identical in both builds: specs/GRABBER-AUTOHIDE-0.7.4.md.
//
// How the marks are shown / hidden (identical in 16.0 and 16.2, nothing to port there):
//   -[SBFluidSwitcherViewController _updateAutoHide...] -> -[SBAffordancePresenceController setAutoHideAffordance:] (16.0 0x1c5ebcf3c / 16.2 0x1c732fd84)
//   -> -_updateIdleTouchAwarenessClient: YES enables an SBAttentionAwarenessClient (event mask 8, attentionLostTimeout = SBFHomeGrabberSettings autoHideTime = 2.0 s in
//      both builds, setDefaultValues 0x18ebabbd4 / 0x18ee4b60c) -> AWAttentionLostEvent after 2.0 s without user touches -> touchState 1 -> _calculatePresence = hidden
//   -> -[SBFluidSwitcherItemContainer affordancePresenceController:didChangeToPresence:] (0x1c615b8bc / 0x1c75e28d8) -> -[SBAppSwitcherPageView setResizeGrabbersVisible:(presence == 0)]
//   A tap (UITouchTypeDirect, system gesture types 0x20 / 0x21 of the SBTransientUIInteractionManager) unhides again (_unhideIfAutoHidden, delayForUnhideOnTouch 0.1 s).
//   The flag handed to setAutoHideAffordance: is the app's own home indicator auto hide (-[SBFullScreenSwitcherLiveContentOverlayCoordinator
//   wantsHomeAffordanceAutoHideForAppLayout:] -> -[SBDeviceApplicationSceneHandle isAutoHideEnabledForHomeAffordance] = uiClientSettings.homeIndicatorAutoHidden).
//   The touch / pointer resize start region (-[SBFluidSwitcherGestureManager _shouldLiveResizeItemContainerGestureWithTouch:receiveTouch:], -[SBAppSwitcherPageView
//   shouldBeginPointerInteraction...]) is purely geometric in both builds: it never looks at the presence of the grabbers.
//
// What 16.2 does differently and is ported here (default on, master switch g2c_autohide):
//  1. NEW -[SBFluidSwitcherViewController _updateAutoHideForItemContainer:appLayout:] 16.2 0x1c743c65c
//       setAutoHideAffordance:[liveContentOverlayCoordinator wantsHomeAffordanceAutoHideForAppLayout:layout]  on  [container affordancePresenceController]
//     and -_updateAutoHideForGrabberAffordancesInAppLayout:withResetDelay:unhideDelay: 16.2 0x1c743c5f0 (16.0 0x1c5fc3b2c, same logic inline) now forwards to it (the delays were
//     never used in either build).
//  2. -_setupLiveContentOverlayForAppLayout:itemContainer:overlay: 16.2 0x1c7456a64 (16.0 0x1c5fdd720) calls -_updateAutoHideForItemContainer:appLayout: after
//     -_applyStyleToLiveContentOverlay:... (also when the layout is not in -appLayouts) and ends with -_unblurItemContainer:[SBBlurItemContainerParameters
//     defaultCrossblurBlurParameters] withAnimationUpdateMode:2. 16.0 only set the flag when the app's client settings changed, so a RECYCLED item container kept the
//     auto-hide flag of the app it showed before (a window whose app never asked for auto hide still lost its marks after 2 s), and a container never got its flag
//     when the settings had been delivered before the overlay existed.
//  3. (g2c_scenemgr) tap to unhide per window scene: 16.2 -[SBAffordancePresenceController initWithDelegate:windowScene:] 0x1c732fb2c registers with
//     [windowScene transientUIInteractionManager] (16.2 SBTransientUIInteractionManager initWithSystemGestureManager: 0x1c74f6e90, registerParticipantForTapToUnhide:
//     0x1c74f74d8, unregister... 0x1c74f7678, viewForSystemGestureRecognizer: 0x1c74f7328: the gesture recognizers go to the manager's own SBSystemGestureManager);
//     16.0 initWithDelegate: 0x1c5ebcd04 always registers with [SpringBoard systemTransientUIInteractionManager] whose recognizers sit in the MAIN display's manager, so
//     a window on another display never saw a tap to unhide. Here: the main display scene keeps the SpringBoard manager (it is the main display's, = 16.2's), every other
//     scene gets its own SBTransientUIInteractionManager bound to that scene's system gesture manager, and the presence controller of an item container is registered with
//     the manager of the container's window scene. (Other consumers of the manager, e.g. the top affordance, are not touched.)
//  Identical in both builds (verified instruction by instruction): all of SBAffordancePresenceController except init / dealloc, SBAttentionAwarenessClient,
//  SBFluidSwitcherItemContainer affordancePresenceController:didChangeToPresence:, SBAppSwitcherPageView grabber code, SBAppResizeGrabberView (16.2 only adds an
//  accessibility identifier), -liveContentOverlayDidUpdateHomeAffordanceEdgeProtectOrAutoHide:, SBFHomeGrabberSettings defaults, the touch types of the unhide taps.
//
// Switches: g2c_autohide (everything), g2c_scenemgr (item 3 only). Setup: G2C_Setup(), called after G2B / G1C / G1D setup. Log lines (Backport162.debug): "[g2c] ...".

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#include "G1BKit.h"

#define G2C_ON() BP_OnName("g2c_autohide")
#define G2C_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

// ------------------------------------------------------------------------------------------------ helpers

static id G2C_IvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return BP_ObjIvar(o, iv);
}

// weak box (the presence controller must not keep its window scene alive; 16.2 stores the scene in a weak ivar)
@interface G2CWeakBox : NSObject { @public __weak id obj; } @end
@implementation G2CWeakBox @end

static const void *kG2CMgrSGM = &kG2CMgrSGM;         // on an SBTransientUIInteractionManager that was created for a window scene: that scene's SBSystemGestureManager
static const void *kG2CSceneMgr = &kG2CSceneMgr;     // on an SBWindowScene: its SBTransientUIInteractionManager
static const void *kG2CCtrlScene = &kG2CCtrlScene;   // on an SBAffordancePresenceController: G2CWeakBox of the window scene it registered with (non main display only)

static IMP gOrigSetupOverlay, gOrigPresInit, gOrigPresDealloc, gOrigPresChanged;
static IMP gOrigMgrRegister, gOrigMgrUnregister, gOrigMgrView;

// ============================================================================================================
// 1. _updateAutoHideForItemContainer:appLayout:  16.2 0x1c743c65c
// ============================================================================================================
static void G2C_UpdateAutoHideForContainer(id vc, SEL _cmd, id container, id layout) {
    id coordinator = G2C_IvarObj(vc, "_liveContentOverlayCoordinator");                         // 16.2 ivar load [vc + 0xea0]
    SEL want = NSSelectorFromString(@"wantsHomeAffordanceAutoHideForAppLayout:");
    BOOL autoHide = [coordinator respondsToSelector:want] ? ((BOOL (*)(id, SEL, id))objc_msgSend)(coordinator, want, layout) : NO;
    id controller = G1B_Send0(container, NSSelectorFromString(@"affordancePresenceController"));
    if (BP_LogEnabled()) {
        BOOL was = G1B_SendB0(controller, NSSelectorFromString(@"autoHideAffordance"));
        if (was != autoHide || !controller) BP_Log(@"[g2c] auto hide of the resize grabbers: container=%p controller=%p %d -> %d (%@)", container, controller, was, autoHide, layout);
    }
    if (controller) ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, NSSelectorFromString(@"setAutoHideAffordance:"), autoHide);
}

// 16.2 0x1c743c5f0: [self _updateAutoHideForItemContainer:[self _itemContainerForAppLayoutIfExists:layout] appLayout:layout]; the two delays are not used
static void G2C_UpdateAutoHideForGrabbers(id vc, SEL _cmd, id layout, double resetDelay, double unhideDelay) {
    id container = G1B_Send1(vc, NSSelectorFromString(@"_itemContainerForAppLayoutIfExists:"), layout);
    SEL s = NSSelectorFromString(@"_updateAutoHideForItemContainer:appLayout:");
    if ([vc respondsToSelector:s]) ((void (*)(id, SEL, id, id))objc_msgSend)(vc, s, container, layout);
}

// ============================================================================================================
// 2. _setupLiveContentOverlayForAppLayout:itemContainer:overlay:  16.2 0x1c7456a64 (16.0 0x1c5fdd720)
// ============================================================================================================
static void G2C_SetupLiveContentOverlay(id vc, SEL _cmd, id layout, id container, id overlay) {
    static SEL sDelegate, sStatus, sLayouts, sStyle, sTouch, sAsync, sEnh, sUnblur, sAutoHide;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sDelegate = NSSelectorFromString(@"setDelegate:");
        sStatus = NSSelectorFromString(@"_updateStatusBarAndHomeGrabberVisibilityForAppLayout:animated:");
        sLayouts = NSSelectorFromString(@"appLayouts");
        sStyle = NSSelectorFromString(@"_applyStyleToLiveContentOverlay:forItemContainer:atIndex:");
        sTouch = NSSelectorFromString(@"_applyTouchBehaviorToLiveContentOverlay:forAppLayout:");
        sAsync = NSSelectorFromString(@"_updateAsyncRenderingAndResizesHostedContext");
        sEnh = NSSelectorFromString(@"_updateWantsEnhancedWindowingEnabledState");
        sUnblur = NSSelectorFromString(@"_unblurItemContainer:blurParameters:withAnimationUpdateMode:");
        sAutoHide = NSSelectorFromString(@"_updateAutoHideForItemContainer:appLayout:");
    });
    Class blur = NSClassFromString(@"SBBlurItemContainerParameters");
    SEL cross = NSSelectorFromString(@"defaultCrossblurBlurParameters");
    BOOL ok = [overlay respondsToSelector:sDelegate] && [vc respondsToSelector:sStatus] && [vc respondsToSelector:sLayouts] && [vc respondsToSelector:sStyle] &&
              [vc respondsToSelector:sTouch] && [vc respondsToSelector:sAsync] && [vc respondsToSelector:sEnh] && [vc respondsToSelector:sUnblur] &&
              [vc respondsToSelector:sAutoHide] && [blur respondsToSelector:cross];
    if (!ok) {                                                                                    // last line guard: a selector of the 16.2 body is missing, run the 16.0 body
        G2C_LOG(@"[g2c] setup overlay: 16.2 selector missing, running the 16.0 body");
        if (gOrigSetupOverlay) ((void (*)(id, SEL, id, id, id))gOrigSetupOverlay)(vc, _cmd, layout, container, overlay);
        return;
    }
    ((void (*)(id, SEL, id))objc_msgSend)(overlay, sDelegate, vc);                                // [overlay setDelegate:self]
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(vc, sStatus, layout, YES);                        // _updateStatusBarAndHomeGrabberVisibilityForAppLayout:animated:YES
    NSUInteger index = [(NSArray *)((id (*)(id, SEL))objc_msgSend)(vc, sLayouts) indexOfObject:layout];
    if (index != NSNotFound) ((void (*)(id, SEL, id, id, NSUInteger))objc_msgSend)(vc, sStyle, overlay, container, index);
    ((void (*)(id, SEL, id, id))objc_msgSend)(vc, sAutoHide, container, layout);                  // NEW in 16.2 (0x1c7456b08)
    ((void (*)(id, SEL, id, id))objc_msgSend)(vc, sTouch, overlay, layout);
    ((void (*)(id, SEL))objc_msgSend)(vc, sAsync);
    ((void (*)(id, SEL))objc_msgSend)(vc, sEnh);
    id params = ((id (*)(id, SEL))objc_msgSend)((id)blur, cross);
    ((void (*)(id, SEL, id, id, long long))objc_msgSend)(vc, sUnblur, container, params, 2);      // NEW in 16.2 (0x1c7456b50)
}

// diagnostic only (16.2's body is the same as 16.0's: presence 0 = visible): which presence the container reported and what the touch resize start would see
static void G2C_PresenceChanged(id container, SEL _cmd, id controller, long long presence) {
    if (gOrigPresChanged) ((void (*)(id, SEL, id, long long))gOrigPresChanged)(container, _cmd, controller, presence);
    if (BP_LogEnabled()) {
        unsigned long long corners = (unsigned long long)G1B_SendLL0(container, NSSelectorFromString(@"allowedTouchResizeCorners"));
        BP_Log(@"[g2c] grabber presence %lld (grabbers %s) container=%p allowedTouchResizeCorners=0x%llx", presence, presence == 0 ? "visible" : "hidden", container, corners);
    }
}

// ============================================================================================================
// 3. tap to unhide per window scene
// ============================================================================================================
static BOOL G2C_IsMainScene(id scene) { return G1B_SendB0(scene, NSSelectorFromString(@"isMainDisplayWindowScene")); }
static id G2C_SpringBoardMgr(void) { return G1B_Send0([UIApplication sharedApplication], NSSelectorFromString(@"systemTransientUIInteractionManager")); }

// -[SBWindowScene transientUIInteractionManager] 16.2 0x1c77f8688 (= [[scene _abstractWindowSceneDelegate] transientUIInteractionManager])
static id G2C_SceneManager(id scene, SEL _cmd) {
    if (!G2C_ON() || !BP_OnName("g2c_scenemgr")) return G2C_SpringBoardMgr();
    if (G2C_IsMainScene(scene)) return G2C_SpringBoardMgr();                                      // the main display's manager already exists (created by SpringBoard)
    id m = G1B_GET(scene, kG2CSceneMgr);
    if (m) return m;
    id sgm = G1B_Send0(scene, NSSelectorFromString(@"systemGestureManager"));
    id window = G1B_Send0(sgm, NSSelectorFromString(@"windowForSystemGestures"));
    Class cls = NSClassFromString(@"SBTransientUIInteractionManager");
    SEL init = NSSelectorFromString(@"initWithWindow:");
    if (!sgm || !cls || ![cls instancesRespondToSelector:init]) {
        G2C_LOG(@"[g2c] scene manager: no system gesture manager for %@, using the SpringBoard manager", scene);
        return G2C_SpringBoardMgr();                                                              // last line guard
    }
    m = G1B_INIT(id)([cls alloc], init, window);
    G1B_SET(m, kG2CMgrSGM, sgm);
    G1B_SET(scene, kG2CSceneMgr, m);
    G2C_LOG(@"[g2c] scene manager %p created for %@ (system gesture manager %@)", m, scene, sgm);
    return m;
}

static id G2C_MgrSGM(id mgr) { return G1B_GET(mgr, kG2CMgrSGM); }

static UITapGestureRecognizer *G2C_NewTap(id mgr, NSInteger taps, SEL action) {
    UITapGestureRecognizer *t = action ? [[UITapGestureRecognizer alloc] initWithTarget:mgr action:action] : [[UITapGestureRecognizer alloc] init];
    if (taps) t.numberOfTapsRequired = taps;
    t.cancelsTouchesInView = NO;
    t.delaysTouchesBegan = NO;
    t.delaysTouchesEnded = NO;
    t.allowedTouchTypes = @[@(UITouchTypeDirect)];
    t.delegate = (id)mgr;
    return t;
}

// 16.2 0x1c74f74d8
static void G2C_MgrRegisterTapToUnhide(id mgr, SEL _cmd, id participant) {
    id sgm = G2C_MgrSGM(mgr);
    if (!sgm) { if (gOrigMgrRegister) ((void (*)(id, SEL, id))gOrigMgrRegister)(mgr, _cmd, participant); return; }          // the SpringBoard manager: 16.0 code, main display manager
    NSHashTable *parts = G1B_Send0(mgr, NSSelectorFromString(@"tapToUnhideParticipants"));
    if (![parts containsObject:participant]) [parts addObject:participant];
    if (![parts count]) return;
    if (!G1B_Send0(mgr, NSSelectorFromString(@"unhideTapRecognizer"))) {
        UITapGestureRecognizer *tap = G2C_NewTap(mgr, 0, NSSelectorFromString(@"_screenWasTappedToUnhide:"));
        tap.name = @"transientUI.unhide.tap";
        G1B_SendV1(mgr, NSSelectorFromString(@"setUnhideTapRecognizer:"), tap);
        ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(sgm, NSSelectorFromString(@"addGestureRecognizer:withType:"), tap, 0x20);
    }
    if (!G1B_Send0(mgr, NSSelectorFromString(@"unhideDoubleTapRecognizer"))) {
        UITapGestureRecognizer *dbl = G2C_NewTap(mgr, 2, NULL);
        dbl.name = @"transientUI.unhide.doubleTap";
        G1B_SendV1(mgr, NSSelectorFromString(@"setUnhideDoubleTapRecognizer:"), dbl);
        [dbl requireGestureRecognizerToFail:G1B_Send0(mgr, NSSelectorFromString(@"unhideTapRecognizer"))];
        ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(sgm, NSSelectorFromString(@"addGestureRecognizer:withType:"), dbl, 0x21);
    }
}
// 16.2 0x1c74f7678
static void G2C_MgrUnregisterTapToUnhide(id mgr, SEL _cmd, id participant) {
    id sgm = G2C_MgrSGM(mgr);
    if (!sgm) { if (gOrigMgrUnregister) ((void (*)(id, SEL, id))gOrigMgrUnregister)(mgr, _cmd, participant); return; }
    NSHashTable *parts = G1B_Send0(mgr, NSSelectorFromString(@"tapToUnhideParticipants"));
    if (![parts containsObject:participant]) return;
    [parts removeObject:participant];
    if ([parts count]) return;
    SEL rm = NSSelectorFromString(@"removeGestureRecognizer:");
    id tap = G1B_Send0(mgr, NSSelectorFromString(@"unhideTapRecognizer"));
    if (tap) G1B_SendV1(sgm, rm, tap);
    G1B_SendV1(mgr, NSSelectorFromString(@"setUnhideTapRecognizer:"), nil);
    id dbl = G1B_Send0(mgr, NSSelectorFromString(@"unhideDoubleTapRecognizer"));
    if (dbl) G1B_SendV1(sgm, rm, dbl);
    G1B_SendV1(mgr, NSSelectorFromString(@"setUnhideDoubleTapRecognizer:"), nil);
}
// 16.2 0x1c74f7328: [[manager systemGestureManager] windowForSystemGestures]
static id G2C_MgrViewForRecognizer(id mgr, SEL _cmd, id recognizer) {
    id sgm = G2C_MgrSGM(mgr);
    if (!sgm) return gOrigMgrView ? ((id (*)(id, SEL, id))gOrigMgrView)(mgr, _cmd, recognizer) : nil;
    return G1B_Send0(sgm, NSSelectorFromString(@"windowForSystemGestures"));
}

static id G2C_ContainerScene(id container) {
    id scene = G1B_Send0(container, NSSelectorFromString(@"windowScene"));                         // added by G2B (assoc object / the switcher's scene)
    if (!scene) scene = G1B_Send0(G1B_Send0(container, NSSelectorFromString(@"delegate")), NSSelectorFromString(@"_sbWindowScene"));
    return scene;
}

// 16.2 initWithDelegate:windowScene: 0x1c732fb2c: registers with [windowScene transientUIInteractionManager]. The 16.0 initialiser registered with the SpringBoard manager
// already; for a container on another display that registration is moved to the scene's manager.
__attribute__((ns_returns_retained)) static id G2C_PresenceInit(__attribute__((ns_consumed)) id self, SEL _cmd, id delegate) {
    id r = ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id))gOrigPresInit)(self, _cmd, delegate);
    if (!r || !G2C_ON() || !BP_OnName("g2c_scenemgr")) return r;
    Class ic = NSClassFromString(@"SBFluidSwitcherItemContainer");
    if (!ic || ![delegate isKindOfClass:ic]) return r;                                             // the top affordance keeps the SpringBoard manager
    id scene = G2C_ContainerScene(delegate);
    if (!scene || G2C_IsMainScene(scene)) return r;
    id mgr = G2C_SceneManager(scene, NULL);
    id global = G2C_SpringBoardMgr();
    if (!mgr || mgr == global) return r;
    SEL reg = NSSelectorFromString(@"registerParticipantForTapToUnhide:"), unreg = NSSelectorFromString(@"unregisterParticipantForTapToUnhide:");
    G1B_SendV1(global, unreg, r);
    G1B_SendV1(mgr, reg, r);
    G2CWeakBox *box = [G2CWeakBox new];
    box->obj = scene;
    G1B_SET(r, kG2CCtrlScene, box);
    G2C_LOG(@"[g2c] presence controller %p of container %p registered for tap to unhide with the manager of %@", r, delegate, scene);
    return r;
}
static void G2C_PresenceDealloc(__unsafe_unretained id self, SEL _cmd) {
    G2CWeakBox *box = G1B_GET(self, kG2CCtrlScene);
    id scene = box ? box->obj : nil;
    if (scene) G1B_SendV1(G1B_Send0(scene, NSSelectorFromString(@"transientUIInteractionManager")), NSSelectorFromString(@"unregisterParticipantForTapToUnhide:"), self);
    if (gOrigPresDealloc) ((void (*)(id, SEL))gOrigPresDealloc)(self, _cmd);
}

// ============================================================================================================
// setup
// ============================================================================================================
static IMP G2C_Replace(Class c, const char *sel, IMP imp) {
    if (!c || !imp) return NULL;
    Method m = class_getInstanceMethod(c, sel_registerName(sel));
    if (!m) { G2C_LOG(@"[g2c] %s missing on %s", sel, class_getName(c)); return NULL; }
    IMP old = method_getImplementation(m);
    class_replaceMethod(c, sel_registerName(sel), imp, method_getTypeEncoding(m));
    return old;
}

void G2C_Setup(void) {
    if (!G2C_ON()) return;
    Class vc = NSClassFromString(@"SBFluidSwitcherViewController");
    if (vc) {
        if (!class_addMethod(vc, sel_registerName("_updateAutoHideForItemContainer:appLayout:"), (IMP)G2C_UpdateAutoHideForContainer, "v32@0:8@16@24"))
            G2C_LOG(@"[g2c] _updateAutoHideForItemContainer:appLayout: already exists, left alone");
        G2C_Replace(vc, "_updateAutoHideForGrabberAffordancesInAppLayout:withResetDelay:unhideDelay:", (IMP)G2C_UpdateAutoHideForGrabbers);
        gOrigSetupOverlay = G2C_Replace(vc, "_setupLiveContentOverlayForAppLayout:itemContainer:overlay:", (IMP)G2C_SetupLiveContentOverlay);
    }
    Class ic = NSClassFromString(@"SBFluidSwitcherItemContainer");
    if (ic) gOrigPresChanged = G2C_Replace(ic, "affordancePresenceController:didChangeToPresence:", (IMP)G2C_PresenceChanged);
    if (BP_OnName("g2c_scenemgr")) {
        Class ws = NSClassFromString(@"SBWindowScene");
        if (ws) class_addMethod(ws, sel_registerName("transientUIInteractionManager"), (IMP)G2C_SceneManager, "@16@0:8");
        Class mg = NSClassFromString(@"SBTransientUIInteractionManager");
        if (mg) {
            gOrigMgrRegister = G2C_Replace(mg, "registerParticipantForTapToUnhide:", (IMP)G2C_MgrRegisterTapToUnhide);
            gOrigMgrUnregister = G2C_Replace(mg, "unregisterParticipantForTapToUnhide:", (IMP)G2C_MgrUnregisterTapToUnhide);
            gOrigMgrView = G2C_Replace(mg, "viewForSystemGestureRecognizer:", (IMP)G2C_MgrViewForRecognizer);
        }
        Class pc = NSClassFromString(@"SBAffordancePresenceController");
        if (pc) {
            gOrigPresInit = G2C_Replace(pc, "initWithDelegate:", (IMP)G2C_PresenceInit);
            gOrigPresDealloc = G2C_Replace(pc, "dealloc", (IMP)G2C_PresenceDealloc);
            if (!gOrigPresInit) G2C_LOG(@"[g2c] presence controller initWithDelegate: not found, windows on other displays keep the SpringBoard tap to unhide manager");
        }
    }
    BP_Log(@"[g2c] installed (auto hide update at overlay setup%s)", BP_OnName("g2c_scenemgr") ? ", tap to unhide per window scene" : "");
}
#pragma clang diagnostic pop
