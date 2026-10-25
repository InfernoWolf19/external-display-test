// Y12Dock.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): the floating dock of each display.  Setup: constructor.  Log prefix "[y12]".
//
//  y12_dockmode  SBFloatingDockRootViewController -_setPresentedProgress:animated:interactive:completion: 16.2 0x1c72d2368 (16.0 0x1c5e5fe74) and
//                -isFloatingDockViewControllerPresentedOverApplication: 16.2 0x1c77db110 (16.0 0x1c6337d74) ask the switcher controller of the dock's OWN window scene
//                ([[dockViewController _sbWindowScene] switcherController]; the root view controller's delegate answers -unlockedEnvironmentMode with it) whether the environment mode is 3 (apps);
//                16.0 asks [SBMainSwitcherControllerCoordinator sharedInstance], which answers for the ACTIVE display.  With the monitor connected the dock of the display that is not active
//                (pointer on the other display) decided its presentation (whether it may hide / is shown over an application) with the other display's environment mode.
//                Ported: the 16.0 bodies run with the dock's switcher controller as the coordinator's active one (Y3_PushActive).
//  y12_dockwin   -[SBFloatingDockWindow isContentHidden] 16.2 0x1c7930c24 (16.0 0x1c647b034): the content of the dock window is hidden unless the super class says it is shown, the dock is presented, a folder is
//                presented, OR the library is presented in the dock window (-[SBFloatingDockController isPresentingLibraryInFloatingDockWindow], present in both builds, read through the window scene's
//                -floatingDockController); 16.0 hid the window while the dock was not presented even when the library popover of the dock was open.  Ported: wrapper with the 16.2 sequence.
// Not ported (decoded, same behaviour or no effect here):
//  * SBFloatingDockRootViewController -viewDidLayoutSubviews 16.2 sets bounds + centre of the dock view controller's view where 16.0 sets the frame (identical while the view has no transform) and calls
//    -_layoutFloatingDockPresentationProgress: 0x1c77da724, which is -_layoutFloatingDockViewWithProgress: 0x1c5e3b3e8 renamed (instruction for instruction the same).
//  * SBFloatingDockController -gestureRecognizer:shouldReceiveTouch: 16.2 0x1c72c5038: the touch test of the dismiss recognizer lost the requireFloatingDockOverFolder test and the present
//    indirect pan recognizer is no longer refused (SBIndirectPanGestureRecognizer is the OPEN item of DELTA-SWEEP).
// Needs a device with the monitor: put the pointer on the monitor, then drag the pointer to the iPad's edge so that the iPad's display is active: the dock of the monitor keeps its state.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY12OrigProgress, gY12OrigOver, gY12OrigHidden, gY12SuperHidden;

static id Y12_SceneController(id dockVC) {
    id scene = BPX_Obj0(dockVC, "_sbWindowScene");
    return BPX_Obj0(scene, "switcherController");
}
// -[SBFloatingDockRootViewController _setPresentedProgress:animated:interactive:completion:]
static void Y12_SetProgress(id self, SEL _cmd, double progress, BOOL animated, BOOL interactive, id completion) {
    void *prev = NULL;
    id sc = BP_OnName("y12_dockmode") ? Y12_SceneController(BPX_Obj0(self, "floatingDockViewController")) : nil;
    if (sc) prev = Y3_PushActive(sc);
    if (gY12OrigProgress) ((void (*)(id, SEL, double, BOOL, BOOL, id))gY12OrigProgress)(self, _cmd, progress, animated, interactive, completion);
    if (sc) Y3_PopActive(prev);
}
// -[SBFloatingDockRootViewController isFloatingDockViewControllerPresentedOverApplication:]
static BOOL Y12_Over(id self, SEL _cmd, id dockVC) {
    void *prev = NULL;
    id sc = BP_OnName("y12_dockmode") ? Y12_SceneController(dockVC) : nil;
    if (sc) prev = Y3_PushActive(sc);
    BOOL r = gY12OrigOver ? ((BOOL (*)(id, SEL, id))gY12OrigOver)(self, _cmd, dockVC) : NO;
    if (sc) Y3_PopActive(prev);
    return r;
}
// -[SBFloatingDockWindow isContentHidden]
static BOOL Y12_Hidden(id self, SEL _cmd) {
    if (BP_OnName("y12_dockwin") && gY12SuperHidden) {
        if (((BOOL (*)(id, SEL))gY12SuperHidden)(self, _cmd)) return YES;
        id root = BPX_Obj0(self, "floatingDockRootViewController");
        if (BPX_Bool0(root, "isFloatingDockPresented") || BPX_Bool0(root, "isPresentingFolder")) return NO;
        id dock = BPX_Obj0(BPX_Obj0(self, "_sbWindowScene"), "floatingDockController");
        if (dock && BPY_Responds(dock, "isPresentingLibraryInFloatingDockWindow")) return !BPX_Bool0(dock, "isPresentingLibraryInFloatingDockWindow");
    }
    return gY12OrigHidden ? ((BOOL (*)(id, SEL))gY12OrigHidden)(self, _cmd) : NO;
}

__attribute__((constructor)) static void Y12_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class rv = NSClassFromString(@"SBFloatingDockRootViewController"), wn = NSClassFromString(@"SBFloatingDockWindow");
        if (rv && class_getInstanceMethod(rv, sel_registerName("_setPresentedProgress:animated:interactive:completion:")) &&
            class_getInstanceMethod(rv, sel_registerName("isFloatingDockViewControllerPresentedOverApplication:")) && class_getInstanceMethod(rv, sel_registerName("floatingDockViewController"))) {
            gY12OrigProgress = BPX_Replace(rv, "_setPresentedProgress:animated:interactive:completion:", (IMP)Y12_SetProgress);
            gY12OrigOver = BPX_Replace(rv, "isFloatingDockViewControllerPresentedOverApplication:", (IMP)Y12_Over);
            n++;
        }
        if (wn && class_getInstanceMethod(wn, sel_registerName("isContentHidden")) && class_getInstanceMethod(class_getSuperclass(wn), sel_registerName("isContentHidden"))) {
            gY12SuperHidden = method_getImplementation(class_getInstanceMethod(class_getSuperclass(wn), sel_registerName("isContentHidden")));
            gY12OrigHidden = BPX_Replace(wn, "isContentHidden", (IMP)Y12_Hidden);
            n++;
        }
        BP_Log(@"[y12] installed %d of 2 floating dock groups (switches y12_dockmode, y12_dockwin)", n);
    }
}
#pragma clang diagnostic pop
