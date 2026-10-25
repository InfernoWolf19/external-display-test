// Y9Misc.x : delta sweep (specs/DELTA-SWEEP-0.7.9.md): small per window scene answers outside the core files.  Setup: constructor.  Log prefix "[y9]".
//
//  y9_ccscene   SBControlCenterController (the window of the Control Center is always the iPad's, FEATURES T1) reads the layout of the switcher controller of ITS window scene in 16.2:
//               -canBePresented 0x1c7657c38, -_shouldShowGrabberOnFirstSwipe 0x1c72c5518, -_isStatusBarHiddenIgnoringControlCenter 0x1c7658b9c ([[self._window _sbWindowScene] switcherController],
//               -_switcherController).  The 16.0 bodies read the coordinator's forwarders (isAnySwitcherVisible, layoutStateApplicationSceneHandles, unlockedEnvironmentMode,
//               layoutStatePrimaryElement / SideElement), which answer for the ACTIVE display: with the pointer on the monitor, the Control Center of the iPad was allowed or suppressed by the
//               monitor's top app.  Ported with Y3StatusBar.x's controller override (the three methods run with -_activeDisplaySwitcherController answering the controller of the Control Center's scene).
//  y9_overlayfocus  16.2 SBTransientOverlayScenePresenter -performPresentationRequest: 0x1c7947cf4 (at 0x1c7948780 .. 0x1c794879c) takes focus stealing for the new overlay window from the workspace keyboard
//               focus controller (-requestFocusStealingForSpringBoardWindow:forReason: "activeTransientOverlay") and keeps it in the new _SBTransientOverlayPresentedEntity.keyFocusStealingAssertion;
//               -_dismissEntity:animated:completion: 0x1c794b24c invalidates it first.  16.0 had none, so a hardware keyboard kept typing into the app below while an overlay (Control Center
//               search, Spotlight, in-call UI, alerts hosted in a transient overlay window) was up.  Ported: the entity property (associated object) and the two wrappers.
// Needs a device: put the pointer on the monitor with an app that suppresses the Control Center on top there, swipe down for Control Center on the iPad: it opens.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern void *Y3_PushActive(id ctl);
extern void Y3_PopActive(void *prev);

static IMP gY9OrigCan, gY9OrigGrabber, gY9OrigStatus, gY9OrigPresent, gY9OrigDismiss;
static const void *kY9Focus = &kY9Focus;

static id Y9_CCController(id cc) {
    if (!BP_OnName("y9_ccscene")) return nil;
    id scene = BPX_Obj0(BPX_IvarObj(cc, "_window"), "windowScene");
    if (!scene) scene = BPX_Obj0(BPX_IvarObj(cc, "_window"), "_sbWindowScene");
    if (!scene) return nil;
    Class coc = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
    id coord = coc ? BPX_Obj0((id)coc, "sharedInstance") : nil;
    return BPX_Obj1(coord, "switcherControllerForWindowScene:", scene);
}
#define Y9_CC_WRAP(NAME, ORIG) \
static BOOL NAME(id self, SEL _cmd) { \
    void *prev = Y3_PushActive(Y9_CCController(self)); \
    BOOL r = ORIG ? ((BOOL (*)(id, SEL))ORIG)(self, _cmd) : NO; \
    Y3_PopActive(prev); \
    return r; \
}
Y9_CC_WRAP(Y9_CanBePresented, gY9OrigCan)
Y9_CC_WRAP(Y9_ShouldShowGrabber, gY9OrigGrabber)
Y9_CC_WRAP(Y9_StatusBarHidden, gY9OrigStatus)

// _SBTransientOverlayPresentedEntity.keyFocusStealingAssertion (new in 16.2)
static id Y9_EntGet(id self, SEL _cmd) { return objc_getAssociatedObject(self, kY9Focus); }
static void Y9_EntSet(id self, SEL _cmd, id v) { objc_setAssociatedObject(self, kY9Focus, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

// -[SBTransientOverlayScenePresenter performPresentationRequest:]
static void Y9_Present(id self, SEL _cmd, id request) {
    if (gY9OrigPresent) ((void (*)(id, SEL, id))gY9OrigPresent)(self, _cmd, request);
    if (!BP_OnName("y9_overlayfocus")) return;
    id vc = BPX_Obj0(request, "viewController");
    for (id e in [BPX_IvarObj(self, "_entities") copy]) {
        if (BPX_Obj0(e, "viewController") != vc) continue;
        if (!BPX_Obj0(e, "keyFocusStealingAssertion")) {
            id win = BPX_Obj0(e, "window");
            if (win) {
                id fc = BPX_Obj0(BPX_MainWorkspace(), "keyboardFocusController");
                id a = BPX_Obj2(fc, "requestFocusStealingForSpringBoardWindow:forReason:", win, @"activeTransientOverlay");
                BPX_SetObj1(e, "setKeyFocusStealingAssertion:", a);
                BPY_LOG(@"[y9] overlay window %p: key focus stealing %p", (__bridge void *)win, (__bridge void *)a);
            }
        }
        break;
    }
}
// -[SBTransientOverlayScenePresenter _dismissEntity:animated:completion:]
static void Y9_Dismiss(id self, SEL _cmd, id entity, BOOL animated, id completion) {
    if (BP_OnName("y9_overlayfocus") && entity) {
        id a = BPX_Obj0(entity, "keyFocusStealingAssertion");
        if (a) {
            BPX_SetObj1(entity, "setKeyFocusStealingAssertion:", nil);
            ((void (*)(id, SEL))objc_msgSend)(a, sel_registerName("invalidate"));
        }
    }
    if (gY9OrigDismiss) ((void (*)(id, SEL, id, BOOL, id))gY9OrigDismiss)(self, _cmd, entity, animated, completion);
}

__attribute__((constructor)) static void Y9_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class cc = NSClassFromString(@"SBControlCenterController");
        if (!cc || !class_getInstanceMethod(cc, sel_registerName("canBePresented")) || !class_getInstanceMethod(cc, sel_registerName("_shouldShowGrabberOnFirstSwipe")) ||
            !class_getInstanceMethod(cc, sel_registerName("_isStatusBarHiddenIgnoringControlCenter"))) {
            BP_Log(@"[y9] NOT installed (class or selector missing)");
            return;
        }
        gY9OrigCan = BPX_Replace(cc, "canBePresented", (IMP)Y9_CanBePresented);
        gY9OrigGrabber = BPX_Replace(cc, "_shouldShowGrabberOnFirstSwipe", (IMP)Y9_ShouldShowGrabber);
        gY9OrigStatus = BPX_Replace(cc, "_isStatusBarHiddenIgnoringControlCenter", (IMP)Y9_StatusBarHidden);
        Class ent = NSClassFromString(@"_SBTransientOverlayPresentedEntity"), pr = NSClassFromString(@"SBTransientOverlayScenePresenter");
        if (ent && pr && class_getInstanceMethod(pr, sel_registerName("performPresentationRequest:")) && class_getInstanceMethod(pr, sel_registerName("_dismissEntity:animated:completion:"))) {
            if (!class_getInstanceMethod(ent, sel_registerName("keyFocusStealingAssertion"))) {
                class_addMethod(ent, sel_registerName("keyFocusStealingAssertion"), (IMP)Y9_EntGet, "@16@0:8");
                class_addMethod(ent, sel_registerName("setKeyFocusStealingAssertion:"), (IMP)Y9_EntSet, "v24@0:8@16");
            }
            gY9OrigPresent = BPX_Replace(pr, "performPresentationRequest:", (IMP)Y9_Present);
            gY9OrigDismiss = BPX_Replace(pr, "_dismissEntity:animated:completion:", (IMP)Y9_Dismiss);
        }
        BP_Log(@"[y9] installed (switches y9_ccscene, y9_overlayfocus)");
    }
}
#pragma clang diagnostic pop
