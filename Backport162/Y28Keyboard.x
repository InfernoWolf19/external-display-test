// Y28Keyboard.x : delta sweep pass 3, keyboard home grabber (F5).  Setup: constructor.  Log prefix "[y28]".
//
//  y24_kbgrabber  SBKeyboardHomeAffordanceController (the home grabber drawn on the hosted software keyboard).  16.0 asks the MAIN display scene manager for everything (+[SBSceneManagerCoordinator
//                 mainDisplaySceneManager]: _isUsingMedusaHostedKeyboardWindow / _medusaHostedKeyboardWindow / _isUsingInputUI / _inputUIContainerView, addObserver:), 16.2 asks the window scene the
//                 keyboard belongs to: scene = SBSafeCast(SBWindowScene, [[topMostAssertion sourceWindow] windowScene]).
//      -_getHomeGrabberContainingView:isAlwaysPortrait:  16.2 0x1c78bc418 (16.0 0x1c640ebdc), replaced:
//             no scene -> nothing is written;  [[scene medusaHostedKeyboardWindowController] isUsingMedusaHostedKeyboardWindow] -> view of that controller's hosted keyboard window root view controller;
//             else [UIKeyboard usesInputSystemUI] -> SBSafeCast(UIView, [[[SBApp systemUIScenesCoordinator] inputUISceneController] hostingWindow]) (all three exist in 16.0);  both set
//             isAlwaysPortrait = [scene isMainDisplayWindowScene] (16.0: constant YES);  else [[UIKeyboardArbiterManager sharedArbiterManager] keyboardWindow] root view, isAlwaysPortrait NO (as 16.0).
//      -_updateHomeAffordance  16.2 0x1c78bc648 (16.0 0x1c640ed54): the observer is registered on the scene's medusaHostedKeyboardWindowController (G3B.x BPMedusaHostedKeyboardWindowController, calls
//             -usingMedusaHostedKeyboardWindowDidChange on its observers, also for the scenes of other displays), 16.0 registers on the main display scene manager.  Ported: while the 16.0 body runs,
//             the one -addObserver: it sends to the main display scene manager for this controller goes to the scene's controller instead (thread local, consumed at the first use).  When the scene
//             has no controller (switch kbmedusa off) the 16.0 registration stays.
//      -usingMedusaHostedKeyboardWindowDidChange (new, 16.2 0x1c78bcca8) = -_updateHomeAffordance, like 16.0 -sceneManagerUsingMedusaHostedKeyboardWindowDidChange: (0x1c640f368).
// Needs a device: software keyboard in a Stage Manager window on the iPad: the home grabber appears at the keyboard bottom like before; with the monitor the keyboard grabber follows the scene of
// the window that owns the keyboard.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY28OrigGet, gY28OrigUpdate, gY28OrigAddObserver;
static __thread void *tY28Self;          // the controller whose -_updateHomeAffordance runs (unretained)

static id Y28_SceneOf(id controller) {
    Ivar iv = class_getInstanceVariable(object_getClass(controller), "_topMostAssertion");
    id assertion = BP_ObjIvar(controller, iv);
    id window = Y17_Obj0("kbgrabber", assertion, "sourceWindow");
    id scene = Y17_Obj0("kbgrabber", window, "windowScene");
    Class sbws = NSClassFromString(@"SBWindowScene");
    return (sbws && [scene isKindOfClass:sbws]) ? scene : nil;          // SBSafeCast
}

static void Y28_Get(id self, SEL _cmd, id __autoreleasing *outView, BOOL *outPortrait) {
    if (!BP_OnName("y24_kbgrabber")) { if (gY28OrigGet) ((void (*)(id, SEL, id __autoreleasing *, BOOL *))gY28OrigGet)(self, _cmd, outView, outPortrait); return; }
    id scene = Y28_SceneOf(self);
    if (!scene) return;                                                  // 16.2 0x1c78bc49c: nothing written
    id view = nil;
    BOOL portrait = NO;
    id ctlr = Y17_Obj0("kbgrabber", scene, "medusaHostedKeyboardWindowController");
    if (ctlr && BPY_Responds(ctlr, "isUsingMedusaHostedKeyboardWindow") && BPY_SEND(BOOL, (), ctlr, "isUsingMedusaHostedKeyboardWindow")) {
        view = Y17_Obj0("kbgrabber", Y17_Obj0("kbgrabber", Y17_Obj0("kbgrabber", ctlr, "medusaHostedKeyboardWindow"), "rootViewController"), "view");
        portrait = BPX_Bool0(scene, "isMainDisplayWindowScene");
    } else if (BPY_Responds((id)NSClassFromString(@"UIKeyboard"), "usesInputSystemUI") && BPY_SEND(BOOL, (), (id)NSClassFromString(@"UIKeyboard"), "usesInputSystemUI")) {
        id host = Y17_Obj0("kbgrabber", Y17_Obj0("kbgrabber", Y17_Obj0("kbgrabber", BPX_App(), "systemUIScenesCoordinator"), "inputUISceneController"), "hostingWindow");
        view = [host isKindOfClass:[UIView class]] ? host : nil;
        portrait = BPX_Bool0(scene, "isMainDisplayWindowScene");
    } else {
        id arbiterCls = (id)NSClassFromString(@"UIKeyboardArbiterManager");
        id arbiter = BPY_Responds(arbiterCls, "sharedArbiterManager") ? BPY_SEND(id, (), arbiterCls, "sharedArbiterManager") : nil;
        id kw = BPY_Responds(arbiter, "keyboardWindow") ? BPY_SEND(id, (), arbiter, "keyboardWindow") : nil;
        view = Y17_Obj0("kbgrabber", Y17_Obj0("kbgrabber", kw, "rootViewController"), "view");
        portrait = NO;
    }
    if (outView) *outView = view;
    if (outPortrait) *outPortrait = portrait;
}

static void Y28_AddObserver(id mgr, SEL _cmd, id observer) {
    if (BP_OnName("y24_kbgrabber") && tY28Self && observer && tY28Self == (__bridge void *)observer) {
        tY28Self = NULL;                                                 // consumed
        id ctlr = Y17_Obj0("kbgrabber", Y28_SceneOf(observer), "medusaHostedKeyboardWindowController");
        if (ctlr && BPY_Responds(ctlr, "addObserver:")) { BPY_SEND(void, (id), ctlr, "addObserver:", observer); BPY_LOG(@"[y28] home grabber observes the keyboard controller %p of its own scene", (__bridge void *)ctlr); return; }
        Y17_GuardOnce("kbgrabber", ctlr, "addObserver: (the scene has no medusaHostedKeyboardWindowController: 16.0 registration on the main scene manager)");
    }
    if (gY28OrigAddObserver) ((void (*)(id, SEL, id))gY28OrigAddObserver)(mgr, _cmd, observer);
}
static void Y28_Update(id self, SEL _cmd) {
    void *prev = tY28Self;
    tY28Self = (__bridge void *)self;
    if (gY28OrigUpdate) ((void (*)(id, SEL))gY28OrigUpdate)(self, _cmd);
    tY28Self = prev;
}
static void Y28_UsingChanged(id self, SEL _cmd) {
    if (BPY_Responds(self, "_updateHomeAffordance")) BPY_SEND(void, (), self, "_updateHomeAffordance");
}

__attribute__((constructor)) static void Y28_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBKeyboardHomeAffordanceController");
        Class coord = NSClassFromString(@"SBSceneManagerCoordinator");
        id mainMgr = coord ? BPX_Obj0((id)coord, "mainDisplaySceneManager") : nil;
        Class mgrClass = mainMgr ? object_getClass(mainMgr) : Nil;
        if (!c || !mgrClass || !class_getInstanceMethod(c, sel_registerName("_getHomeGrabberContainingView:isAlwaysPortrait:")) || !class_getInstanceMethod(c, sel_registerName("_updateHomeAffordance")) ||
            !class_getInstanceMethod(mgrClass, sel_registerName("addObserver:"))) {
            BP_Log(@"[y28] GUARD(kbgrabber) SBKeyboardHomeAffordanceController (%p) / main display scene manager class (%p) or their selectors missing: not installed", (__bridge void *)c, (__bridge void *)mgrClass);
            return;
        }
        gY28OrigGet = BPX_Replace(c, "_getHomeGrabberContainingView:isAlwaysPortrait:", (IMP)Y28_Get);
        gY28OrigUpdate = BPX_Replace(c, "_updateHomeAffordance", (IMP)Y28_Update);
        gY28OrigAddObserver = BPX_Replace(mgrClass, "addObserver:", (IMP)Y28_AddObserver);
        if (!class_getInstanceMethod(c, sel_registerName("usingMedusaHostedKeyboardWindowDidChange"))) class_addMethod(c, sel_registerName("usingMedusaHostedKeyboardWindowDidChange"), (IMP)Y28_UsingChanged, "v16@0:8");
        BP_Log(@"[y28] installed y24_kbgrabber");
    }
}
#pragma clang diagnostic pop
