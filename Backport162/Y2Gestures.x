// Y2Gestures.x : delta sweep family F4 (specs/DELTA-SWEEP-0.7.9.md): transient UI gesture registrations per window scene.  Setup: constructor.  Log prefix "[y2]".
//
// 16.0 registers every "tap outside to dismiss" / "indirect pan to dismiss" recognizer of the transient UI in the MAIN display's SBSystemGestureManager
// (+[SBSystemGestureManager mainDisplayManager], through the SpringBoard singleton -[SpringBoard systemTransientUIInteractionManager]); a window on the extended display
// registered its top affordance menu / shelf there, so a tap on the monitor never dismissed them.  16.2: the top affordance and the shelf ask THEIR window scene's manager
// (-[SBWindowScene transientUIInteractionManager], 16.2 0x1c77f8688; top affordance topAffordanceDotsViewWillPresentMenu: 0x1c790e164 / WillDismissMenu: 0x1c790e20c, shelf
// viewWillAppear: 0x1c7986a98 / viewWillDisappear: 0x1c7986bb4) and the manager keeps its own SBSystemGestureManager (ivar +0x48; register/unregister ...TapToDismiss:
// 0x1c74f736c / 0x1c74f7440, ...IndirectPanToDismiss: 0x1c74f7724 / 0x1c74f7814 use it instead of mainDisplayManager).
//
//  y2_tuiscene  (a) the four SBTransientUIInteractionManager register / unregister methods run with +mainDisplayManager answering the system gesture manager of the manager's window
//                   (the G2C.x per-scene manager of a non-main display: its window is that display's system gesture window), (b) the 16.0 callers of the SpringBoard singleton
//                   (-[SBTopAffordanceViewController topAffordanceDotsViewWillPresentMenu: / WillDismissMenu: / _setTopAffordanceMode:animated:],
//                   -[SBSwitcherShelfViewController viewWillAppear: / viewWillDisappear:]) run with -[SpringBoard systemTransientUIInteractionManager] answering the manager of
//                   their window scene (top affordance: the scene of its scene handle; shelf: the scene of its switcher controller), (c) the top affordance's own
//                   SBAffordancePresenceController (tap to unhide, 16.2 initWithDelegate:windowScene: 0x1c732fb2c) registers with its scene's manager as well (G2C.x does it for
//                   the item containers only) and unregisters when the view controller goes away.
// Main display objects keep the singleton (= 16.2's main manager).  Needs a device: open the window menu (title dots) of a window on the monitor, tap on the monitor outside
// the menu: it dismisses; a top affordance that auto hid on the monitor shows again on a tap.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define Y2_ON() BP_OnName("y2_tuiscene")

static __thread void *tY2SGM;      // unretained: the system gesture manager +mainDisplayManager answers while a wrapped call runs
static __thread void *tY2TUI;      // unretained: the manager -[SpringBoard systemTransientUIInteractionManager] answers while a wrapped call runs
static IMP gY2OrigMainMgr, gY2OrigGlobalTUI;
static IMP gY2OrigReg, gY2OrigUnreg, gY2OrigRegPan, gY2OrigUnregPan;
static IMP gY2OrigTAMenuIn, gY2OrigTAMenuOut, gY2OrigTAMode, gY2OrigShelfIn, gY2OrigShelfOut, gY2OrigTAInit, gY2OrigTADealloc;
static const void *kY2PresScene = &kY2PresScene;

static BOOL Y2_IsMain(id scene) { return BPX_Bool0(scene, "isMainDisplayWindowScene"); }

// +[SBSystemGestureManager mainDisplayManager]
static id Y2_MainDisplayManager(id self, SEL _cmd) {
    void *p = tY2SGM;
    if (p) return (__bridge id)p;
    return gY2OrigMainMgr ? ((id (*)(id, SEL))gY2OrigMainMgr)(self, _cmd) : nil;
}
// -[SpringBoard systemTransientUIInteractionManager]
static id Y2_GlobalTUI(id self, SEL _cmd) {
    void *p = tY2TUI;
    if (p) return (__bridge id)p;
    return gY2OrigGlobalTUI ? ((id (*)(id, SEL))gY2OrigGlobalTUI)(self, _cmd) : nil;
}

// ---- (a) the manager's own register / unregister
static id Y2_MgrSGM(id mgr) {
    id scene = BPX_Obj0(BPX_Obj0(mgr, "window"), "windowScene");
    if (!scene || Y2_IsMain(scene)) return nil;                                   // the main manager = mainDisplayManager already
    return BPX_Obj0(scene, "systemGestureManager");
}
#define Y2_MGR_WRAP(NAME, ORIG) \
static void NAME(id self, SEL _cmd, id p) { \
    id sgm = Y2_ON() ? Y2_MgrSGM(self) : nil; \
    void *prev = tY2SGM; \
    if (sgm) tY2SGM = (__bridge void *)sgm; \
    if (ORIG) ((void (*)(id, SEL, id))ORIG)(self, _cmd, p); \
    tY2SGM = prev; \
}
Y2_MGR_WRAP(Y2_MgrReg, gY2OrigReg)
Y2_MGR_WRAP(Y2_MgrUnreg, gY2OrigUnreg)
Y2_MGR_WRAP(Y2_MgrRegPan, gY2OrigRegPan)
Y2_MGR_WRAP(Y2_MgrUnregPan, gY2OrigUnregPan)

// ---- (b) callers of the singleton
static id Y2_SceneTUI(id scene) {
    if (!scene || Y2_IsMain(scene)) return nil;
    return BPX_Obj0(scene, "transientUIInteractionManager");                      // G2C.x (g2c_scenemgr): the manager bound to that scene's gesture manager
}
static id Y2_TAScene(id vc) { return BPX_Obj0(BPX_IvarObj(vc, "_sceneHandle"), "_windowScene"); }
static id Y2_ShelfScene(id vc) { return BPX_Obj0(BPX_IvarObj(vc, "_switcherController"), "windowScene"); }
static void Y2_TAMenuIn(id self, SEL _cmd, id dots) {
    id mgr = Y2_ON() ? Y2_SceneTUI(Y2_TAScene(self)) : nil;
    void *prev = tY2TUI;
    if (mgr) tY2TUI = (__bridge void *)mgr;
    if (gY2OrigTAMenuIn) ((void (*)(id, SEL, id))gY2OrigTAMenuIn)(self, _cmd, dots);
    tY2TUI = prev;
}
static void Y2_TAMenuOut(id self, SEL _cmd, id dots) {
    id mgr = Y2_ON() ? Y2_SceneTUI(Y2_TAScene(self)) : nil;
    void *prev = tY2TUI;
    if (mgr) tY2TUI = (__bridge void *)mgr;
    if (gY2OrigTAMenuOut) ((void (*)(id, SEL, id))gY2OrigTAMenuOut)(self, _cmd, dots);
    tY2TUI = prev;
}
static void Y2_TAMode(id self, SEL _cmd, long long mode, BOOL animated) {
    id mgr = Y2_ON() ? Y2_SceneTUI(Y2_TAScene(self)) : nil;
    void *prev = tY2TUI;
    if (mgr) tY2TUI = (__bridge void *)mgr;
    if (gY2OrigTAMode) ((void (*)(id, SEL, long long, BOOL))gY2OrigTAMode)(self, _cmd, mode, animated);
    tY2TUI = prev;
}
static void Y2_ShelfIn(id self, SEL _cmd, BOOL animated) {
    id mgr = Y2_ON() ? Y2_SceneTUI(Y2_ShelfScene(self)) : nil;
    void *prev = tY2TUI;
    if (mgr) tY2TUI = (__bridge void *)mgr;
    if (gY2OrigShelfIn) ((void (*)(id, SEL, BOOL))gY2OrigShelfIn)(self, _cmd, animated);
    tY2TUI = prev;
}
static void Y2_ShelfOut(id self, SEL _cmd, BOOL animated) {
    id mgr = Y2_ON() ? Y2_SceneTUI(Y2_ShelfScene(self)) : nil;
    void *prev = tY2TUI;
    if (mgr) tY2TUI = (__bridge void *)mgr;
    if (gY2OrigShelfOut) ((void (*)(id, SEL, BOOL))gY2OrigShelfOut)(self, _cmd, animated);
    tY2TUI = prev;
}

// ---- (c) the top affordance's presence controller (tap to unhide) follows its scene
@interface Y2WeakScene : NSObject { @public __weak id scene; } @end
@implementation Y2WeakScene @end

static id Y2_TAInit(id self, SEL _cmd, id handle) {
    id r = gY2OrigTAInit ? ((id (*)(id, SEL, id))gY2OrigTAInit)(self, _cmd, handle) : nil;
    if (!r || !Y2_ON()) return r;
    id scene = BPX_Obj0(handle, "_windowScene");
    id mgr = Y2_SceneTUI(scene);
    id pc = BPX_IvarObj(r, "_affordancePresenceController");
    id global = BPX_Obj0(BPX_App(), "systemTransientUIInteractionManager");
    if (!mgr || !pc || mgr == global) return r;
    BPX_SetObj1(global, "unregisterParticipantForTapToUnhide:", pc);
    BPX_SetObj1(mgr, "registerParticipantForTapToUnhide:", pc);
    Y2WeakScene *w = [Y2WeakScene new];
    w->scene = scene;
    objc_setAssociatedObject(r, kY2PresScene, w, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BPY_LOG(@"[y2] top affordance %p: tap to unhide registered with the manager of %@", r, scene);
    return r;
}
static void Y2_TADealloc(__unsafe_unretained id self, SEL _cmd) {
    Y2WeakScene *w = objc_getAssociatedObject(self, kY2PresScene);
    id scene = w ? w->scene : nil;
    id pc = BPX_IvarObj(self, "_affordancePresenceController");
    if (scene && pc) BPX_SetObj1(BPX_Obj0(scene, "transientUIInteractionManager"), "unregisterParticipantForTapToUnhide:", pc);
    if (gY2OrigTADealloc) ((void (*)(id, SEL))gY2OrigTADealloc)(self, _cmd);
}

__attribute__((constructor)) static void Y2_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class sgm = NSClassFromString(@"SBSystemGestureManager"), sb = NSClassFromString(@"SpringBoard");
        Class mg = NSClassFromString(@"SBTransientUIInteractionManager"), ta = NSClassFromString(@"SBTopAffordanceViewController"), sh = NSClassFromString(@"SBSwitcherShelfViewController");
        SEL mm = sel_registerName("mainDisplayManager");
        if (!sgm || !sb || !mg || !ta || !sh || !class_getClassMethod(sgm, mm) || !class_getInstanceMethod(sb, sel_registerName("systemTransientUIInteractionManager"))) {
            BP_Log(@"[y2] NOT installed (class or selector missing)");
            return;
        }
        Method cm = class_getClassMethod(sgm, mm);
        gY2OrigMainMgr = method_getImplementation(cm);
        class_replaceMethod(object_getClass(sgm), mm, (IMP)Y2_MainDisplayManager, method_getTypeEncoding(cm));
        gY2OrigGlobalTUI = BPX_Replace(sb, "systemTransientUIInteractionManager", (IMP)Y2_GlobalTUI);
        gY2OrigReg = BPX_Replace(mg, "registerParticipantForTapToDismiss:", (IMP)Y2_MgrReg);
        gY2OrigUnreg = BPX_Replace(mg, "unregisterParticipantForTapToDismiss:", (IMP)Y2_MgrUnreg);
        gY2OrigRegPan = BPX_Replace(mg, "registerParticipantForIndirectPanToDismiss:", (IMP)Y2_MgrRegPan);
        gY2OrigUnregPan = BPX_Replace(mg, "unregisterParticipantForIndirectPanToDismiss:", (IMP)Y2_MgrUnregPan);
        gY2OrigTAMenuIn = BPX_Replace(ta, "topAffordanceDotsViewWillPresentMenu:", (IMP)Y2_TAMenuIn);
        gY2OrigTAMenuOut = BPX_Replace(ta, "topAffordanceDotsViewWillDismissMenu:", (IMP)Y2_TAMenuOut);
        gY2OrigTAMode = BPX_Replace(ta, "_setTopAffordanceMode:animated:", (IMP)Y2_TAMode);
        gY2OrigShelfIn = BPX_Replace(sh, "viewWillAppear:", (IMP)Y2_ShelfIn);
        gY2OrigShelfOut = BPX_Replace(sh, "viewWillDisappear:", (IMP)Y2_ShelfOut);
        gY2OrigTAInit = BPX_Replace(ta, "initWithDeviceApplicationSceneHandle:", (IMP)Y2_TAInit);
        gY2OrigTADealloc = BPX_Replace(ta, "dealloc", (IMP)Y2_TADealloc);
        BP_Log(@"[y2] installed (switch y2_tuiscene): transient UI registrations per window scene");
    }
}
#pragma clang diagnostic pop
