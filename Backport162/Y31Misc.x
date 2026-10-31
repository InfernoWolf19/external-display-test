// Y31Misc.x : delta sweep pass 3, small rows (F3, F4).  Setup: constructor.  Log prefix "[y31]".
//
//  y24_centerpage  SBCenterWindowPagePresentationSwitcherModifier (the centre window presentation G1B.x creates for new centre windows / morphs).  16.2 0x1c78392a8 (16.0 0x1c638ff88): the init also
//                  creates a default critically damped SBFFluidBehaviorSettings (new ivar), and the NEW method -animationAttributesForLayoutElement: (16.2 0x1c78398e4, absent in 16.0) answers, unless
//                  the transition is the in app morph (ivar _isInAppMorphAnimation = the isMorph argument, 16.0 ivar +0x90), a mutable copy of super's attributes whose layout, position and scale
//                  settings are that object.  Ported: the method is added (class_addMethod, super's IMP called through the superclass), the settings object is an associated object created on first use.
//  y24_minviable   -[SBMinimumViableSwitcherTableViewController isWindowVisible]  16.2 0x1c74eeebc (16.0 0x1c606c49c): "unlocked environment mode == 2" is read from the switcher controller of
//                  the view's own window scene ([[self _sbWindowScene] switcherController]); 16.0 reads +[SBMainSwitcherControllerCoordinator sharedInstance] unlockedEnvironmentMode, the ACTIVE display's
//                  (0x1c623a020).  Ported with the coordinator's active controller set to the scene's controller for the call (Y3_PushActive).  The other row of the class,
//                  -clickReceivedForHomeGrabberView: (16.0 tail _SBWorkspaceSuspendAllDisplays, 16.2 _SBWorkspaceSuspendActiveDisplay) is EQUIVALENT: both entries end in
//                  __SBWorkspaceActivateSpringBoardWithResult with the same boolean arguments (1, 1, 0) and the active display (see DELTA-SWEEP, SBMainWorkspace transactionDidComplete:).
//  y24_classicsb   +[SBUIController(SBUIAnimationController) statusBarFrameForDeviceApplicationSceneHandle:displayConfiguration:interfaceOrientation:statusBarStyleRequest:withinBounds:inReferenceSpace:]
//                  16.2 0x1c77b523c (16.0 0x1c63166d8): the status bar frame inside the classic jail of an iPhone-only app (classic mode that represents the pad, non full screen with home affordance)
//                  is computed for every display; 16.0 gated the branch with [[displayConfiguration identity] isMainRootDisplay] (0x1c6316828, the only use of the identity in the body).  Ported:
//                  during the 16.0 body the first -isMainRootDisplay sent to that identity answers YES (thread local, one shot).
// Needs a device: an iPhone-only app on the monitor in a window: status bar inside its window like on the iPad; call banner / zoom animation of a new centre window is critically damped.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY31OrigWindowVisible, gY31OrigStatusFrame, gY31OrigMainRoot;
static char kY31Settings;

// ---- y24_centerpage ----
static id Y31_CenterAttrs(id self, SEL _cmd, id element) {
    Class own = NSClassFromString(@"SBCenterWindowPagePresentationSwitcherModifier");
    Class owner = own ? class_getSuperclass(own) : Nil;
    Method sm = owner ? class_getInstanceMethod(owner, _cmd) : NULL;
    id attrs = sm ? ((id (*)(id, SEL, id))method_getImplementation(sm))(self, _cmd, element) : nil;
    if (!BP_OnName("y24_centerpage")) return attrs;
    Ivar morph = class_getInstanceVariable(object_getClass(self), "_isInAppMorphAnimation");
    if (!morph) { Y17_GuardOnce("centerpage", self, "_isInAppMorphAnimation"); return attrs; }
    if (*(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(morph))) return attrs;
    id settings = objc_getAssociatedObject(self, &kY31Settings);
    if (!settings) {
        Class fb = NSClassFromString(@"SBFFluidBehaviorSettings");
        settings = (fb && [fb instancesRespondToSelector:sel_registerName("initWithDefaultValues")]) ? ((id (*)(id, SEL))objc_msgSend)([fb alloc], sel_registerName("initWithDefaultValues")) : nil;
        if (settings && BPY_Responds(settings, "setDefaultCriticallyDampedValues")) BPY_SEND(void, (), settings, "setDefaultCriticallyDampedValues");
        else { Y17_GuardOnce("centerpage", settings, "initWithDefaultValues / setDefaultCriticallyDampedValues"); return attrs; }
        objc_setAssociatedObject(self, &kY31Settings, settings, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    id copy = BPY_Responds(attrs, "mutableCopy") ? [attrs mutableCopy] : nil;
    if (!copy || !BPY_Responds(copy, "setLayoutSettings:") || !BPY_Responds(copy, "setPositionSettings:") || !BPY_Responds(copy, "setScaleSettings:")) { Y17_GuardOnce("centerpage", copy ?: attrs, "mutableCopy / setLayoutSettings: / setPositionSettings: / setScaleSettings:"); return attrs; }
    BPY_SEND(void, (id), copy, "setLayoutSettings:", settings);
    BPY_SEND(void, (id), copy, "setPositionSettings:", settings);
    BPY_SEND(void, (id), copy, "setScaleSettings:", settings);
    return copy;
}

// ---- y24_minviable ----
static BOOL Y31_WindowVisible(id self, SEL _cmd) {
    if (!BP_OnName("y24_minviable")) return gY31OrigWindowVisible ? ((BOOL (*)(id, SEL))gY31OrigWindowVisible)(self, _cmd) : NO;
    id ctl = Y17_Obj0("minviable", Y17_Obj0("minviable", self, "_sbWindowScene"), "switcherController");
    void *prev = Y3_PushActive(ctl);
    BOOL r = gY31OrigWindowVisible ? ((BOOL (*)(id, SEL))gY31OrigWindowVisible)(self, _cmd) : NO;
    Y3_PopActive(prev);
    return r;
}

// ---- y24_classicsb ----
static __thread void *tY31Identity;
static BOOL Y31_IsMainRoot(id self, SEL _cmd) {
    if (tY31Identity && tY31Identity == (__bridge void *)self) { tY31Identity = NULL; return YES; }
    return gY31OrigMainRoot ? ((BOOL (*)(id, SEL))gY31OrigMainRoot)(self, _cmd) : NO;
}
static CGRect Y31_StatusFrame(id cls, SEL _cmd, id handle, id config, long long orientation, id request, CGRect bounds, id space) {
    void *prev = tY31Identity;
    if (BP_OnName("y24_classicsb") && gY31OrigMainRoot) {
        id identity = Y17_Obj0("classicsb", config, "identity");
        if (identity) tY31Identity = (__bridge void *)identity;
    }
    CGRect r = gY31OrigStatusFrame ? ((CGRect (*)(id, SEL, id, id, long long, id, CGRect, id))gY31OrigStatusFrame)(cls, _cmd, handle, config, orientation, request, bounds, space) : CGRectZero;
    tY31Identity = prev;
    return r;
}

__attribute__((constructor)) static void Y31_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class cw = NSClassFromString(@"SBCenterWindowPagePresentationSwitcherModifier");
        SEL aa = sel_registerName("animationAttributesForLayoutElement:");
        Method ownM = cw ? class_getInstanceMethod(cw, aa) : NULL, supM = cw ? class_getInstanceMethod(class_getSuperclass(cw), aa) : NULL;
        if (cw && supM && (!ownM || ownM == supM)) {                       // 16.0: only inherited
            class_addMethod(cw, aa, (IMP)Y31_CenterAttrs, "@24@0:8@16"); n++;
        } else BP_Log(@"[y31] GUARD(centerpage) SBCenterWindowPagePresentationSwitcherModifier missing or already has animationAttributesForLayoutElement: (%p): not added", (__bridge void *)cw);
        Class mv = NSClassFromString(@"SBMinimumViableSwitcherTableViewController");
        if (mv && class_getInstanceMethod(mv, sel_registerName("isWindowVisible"))) { gY31OrigWindowVisible = BPX_Replace(mv, "isWindowVisible", (IMP)Y31_WindowVisible); n++; }
        else BP_Log(@"[y31] GUARD(minviable) SBMinimumViableSwitcherTableViewController isWindowVisible missing: not installed");
        Class ui = NSClassFromString(@"SBUIController");
        Class idc = NSClassFromString(@"FBSDisplayIdentity");
        SEL sf = sel_registerName("statusBarFrameForDeviceApplicationSceneHandle:displayConfiguration:interfaceOrientation:statusBarStyleRequest:withinBounds:inReferenceSpace:");
        Class meta = ui ? object_getClass((id)ui) : Nil;
        if (meta && idc && class_getInstanceMethod(meta, sf) && class_getInstanceMethod(idc, sel_registerName("isMainRootDisplay"))) {
            gY31OrigMainRoot = BPX_Replace(idc, "isMainRootDisplay", (IMP)Y31_IsMainRoot);
            gY31OrigStatusFrame = BPX_Replace(meta, "statusBarFrameForDeviceApplicationSceneHandle:displayConfiguration:interfaceOrientation:statusBarStyleRequest:withinBounds:inReferenceSpace:", (IMP)Y31_StatusFrame);
            n++;
        } else BP_Log(@"[y31] GUARD(classicsb) SBUIController statusBarFrame... or FBSDisplayIdentity isMainRootDisplay missing: not installed");
        BP_Log(@"[y31] installed %d group(s) (switches y24_centerpage, y24_minviable, y24_classicsb)", n);
    }
}
#pragma clang diagnostic pop
