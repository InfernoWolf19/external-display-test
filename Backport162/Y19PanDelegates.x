// Y19PanDelegates.x : delta sweep pass 2, delegates / owners of SBIndirectPanGestureRecognizer instances (companion of Y18IndirectPan.x).  Setup: constructor.  Log prefix "[y19]".
//
//  y17_indirectgate  -[SBIndirectPanGestureRecognizer _shouldReceiveEvent:] 16.2 0x1c78421e0 answers only [event type] == 11 (UIEventTypeHover) and the delegates of the owners no longer refuse the
//                    recognizer: 16.0 refused it in the owner's delegate instead (the 16.0 recognizer received every event type and relied on its owner to turn the others away).  Ported together:
//                    (a) the recognizer: not a hover event -> NO, hover events go through the unchanged 16.0 edge gate (see the Y18IndirectPan.x header: the gate stays in -_shouldReceiveEvent:);
//                    (b) -[SBFloatingDockController gestureRecognizer:shouldReceiveTouch:] 16.2 0x1c72c5038 (16.0 0x1c5e52bcc): 16.0 answered NO for _presentFloatingDockIndirectPanGestureRecognizer
//                        (0x1c5e52c28), 16.2 answers YES (anything but the dismiss recognizer is accepted once _allowGestureRecognizers is YES);
//                    (c) -[SBControlCenterController gestureRecognizer:shouldReceiveTouch:] 16.2 0x1c72c574c (16.0 0x1c5e532dc): 16.0 answered NO for _indirectStatusBarPullGestureRecognizer (0x70),
//                        16.2 answers YES (only the finger status bar pull recognizer is judged by the touch location).
//  y17_dockfolder    -[SBFloatingDockController requireFloatingDockOverFolder] 16.0 0x1c6254d54 (Stage Manager && main display scene && a folder is open in the dock) is gone in 16.2 (no symbol, no caller):
//                    its two 16.0 callers, gestureRecognizer:shouldReceiveTouch: (the dismiss recognizer refused touches while a folder was open, 0x1c5e52c70) and
//                    layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext: (App Expose no longer dismissed the dock while a folder was open, 0x1c6256784), decide as if it answered NO
//                    (16.2 0x1c72c5038 / 0x1c76ebcdc): the dock and its open folder are dismissed by a tap outside / by App Expose like on any other dock.  Ported: the method answers NO.
//  y17_dockclip      -[SBFloatingDockController _initWithWindowScene:...] 16.2 0x1c76e9528 calls -setClipsToBounds:NO on the new SBFloatingDockWindow (16.0 left the window as created, 0x1c6253e60).  Ported
//                    on first access of -floatingDockWindow (an init family method cannot be wrapped from C under ARC without leaking self).
//  Rows decided without code:
//     SBFluidSwitcherGestureManager -configureIndirectBottomEdgePanGestureRecognizer (16.0 0x1c643e4a8 / 16.2 0x1c78f01d4): the same configuration; only the init selector lost its systemGestureManager:
//        argument (16.0 registers the recognizer with the scene's indirect touch lifecycle monitor in the init, 16.2 in -[SBSystemGestureManager _enableSystemGesture:withType:], same observer set).
//     SBFluidSwitcherGestureManager -_configureTapToBringItemContainerForwardGesture (16.0 0x1c643e5f0 / 16.2 0x1c78f0318): the inline feature test (blraaz) became an out of line call, same recognizer.
//     SBControlCenterController -_setupGestureRecognizersForUpdatedWindowScene (16.0 0x1c61c8bfc / 16.2 0x1c76578d8): additionally +[SBSystemGestureManager gestureRecognizerOfType:128
//        shouldBeRequiredToFailByGestureRecognizer:] for both pull recognizers; type 128 is the Dynamic Island (SBSystemApertureViewController -initWithWindowScene: 16.2 0x1c7692628 is the only owner
//        of type 128): no recognizer of that type exists on an iPad.  The remaining diff is the removed systemGestureManager: argument of the indirect recognizer init.
// Needs a device: with the pointer at the bottom edge of the monitor the floating dock appears (log "[y18]" lines), a tap outside the dock with a folder open dismisses the folder and the dock.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY19OrigRecvEvent, gY19OrigDockTouch, gY19OrigCCTouch, gY19OrigFolder, gY19OrigDockWindow;

// -[SBIndirectPanGestureRecognizer _shouldReceiveEvent:]
static BOOL Y19_RecvEvent(id self, SEL _cmd, id event) {
    if (BP_OnName("y17_indirectgate") && event && BPX_LL0(event, "type") != 11) return NO;
    return gY19OrigRecvEvent ? ((BOOL (*)(id, SEL, id))gY19OrigRecvEvent)(self, _cmd, event) : YES;
}

static BOOL Y19_IsIvar(id self, const char *ivarName, id gr) {
    Ivar iv = class_getInstanceVariable(object_getClass(self), ivarName);
    if (!BP_IvarIsObj(iv)) { Y17_GuardOnce("indirectgate", self, ivarName); return NO; }
    return gr && object_getIvar(self, iv) == gr;
}

// -[SBFloatingDockController gestureRecognizer:shouldReceiveTouch:]
static BOOL Y19_DockTouch(id self, SEL _cmd, id gr, id touch) {
    if (BP_OnName("y17_indirectgate") && Y19_IsIvar(self, "_presentFloatingDockIndirectPanGestureRecognizer", gr)) {
        BOOL allow = BPX_Bool0(self, "_allowGestureRecognizers");
        BPY_LOG(@"[y19] dock delegate: present indirect pan %@ -> %d (16.2: accepted when gesture recognizers are allowed)", gr, (int)allow);
        return allow;
    }
    return gY19OrigDockTouch ? ((BOOL (*)(id, SEL, id, id))gY19OrigDockTouch)(self, _cmd, gr, touch) : YES;
}

// -[SBControlCenterController gestureRecognizer:shouldReceiveTouch:]
static BOOL Y19_CCTouch(id self, SEL _cmd, id gr, id touch) {
    if (BP_OnName("y17_indirectgate") && Y19_IsIvar(self, "_indirectStatusBarPullGestureRecognizer", gr)) {
        BPY_LOG(@"[y19] control center delegate: indirect status bar pull %@ -> 1 (16.2)", gr);
        return YES;
    }
    return gY19OrigCCTouch ? ((BOOL (*)(id, SEL, id, id))gY19OrigCCTouch)(self, _cmd, gr, touch) : YES;
}

// -[SBFloatingDockController requireFloatingDockOverFolder]
static BOOL Y19_Folder(id self, SEL _cmd) {
    if (BP_OnName("y17_dockfolder")) return NO;
    return gY19OrigFolder ? ((BOOL (*)(id, SEL))gY19OrigFolder)(self, _cmd) : NO;
}

// -[SBFloatingDockController floatingDockWindow]: the window of the dock does not clip to its bounds
static const char kY19Clip = 0;
static id Y19_DockWindow(id self, SEL _cmd) {
    id w = gY19OrigDockWindow ? ((id (*)(id, SEL))gY19OrigDockWindow)(self, _cmd) : nil;
    if (w && BP_OnName("y17_dockclip") && !objc_getAssociatedObject(w, &kY19Clip)) {
        objc_setAssociatedObject(w, &kY19Clip, @1, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        Class fw = NSClassFromString(@"SBFloatingDockWindow");
        if (fw && [w isKindOfClass:fw] && BPY_Responds(w, "setClipsToBounds:")) {
            BPY_SEND(void, (BOOL), w, "setClipsToBounds:", NO);
            BPY_LOG(@"[y19] floating dock window %@: clipsToBounds NO (16.2 0x1c76e9528)", w);
        }
    }
    return w;
}

__attribute__((constructor)) static void Y19_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class pan = NSClassFromString(@"SBIndirectPanGestureRecognizer"), dock = NSClassFromString(@"SBFloatingDockController"), cc = NSClassFromString(@"SBControlCenterController");
        if (pan && class_getInstanceMethod(pan, sel_registerName("_shouldReceiveEvent:"))) { gY19OrigRecvEvent = BPX_Replace(pan, "_shouldReceiveEvent:", (IMP)Y19_RecvEvent); n++; }
        else BP_Log(@"[y19] GUARD(indirectgate) SBIndirectPanGestureRecognizer _shouldReceiveEvent: missing: type filter not installed");
        if (dock && class_getInstanceMethod(dock, sel_registerName("gestureRecognizer:shouldReceiveTouch:"))) { gY19OrigDockTouch = BPX_Replace(dock, "gestureRecognizer:shouldReceiveTouch:", (IMP)Y19_DockTouch); n++; }
        else BP_Log(@"[y19] GUARD(indirectgate) SBFloatingDockController gestureRecognizer:shouldReceiveTouch: missing");
        if (cc && class_getInstanceMethod(cc, sel_registerName("gestureRecognizer:shouldReceiveTouch:"))) { gY19OrigCCTouch = BPX_Replace(cc, "gestureRecognizer:shouldReceiveTouch:", (IMP)Y19_CCTouch); n++; }
        else BP_Log(@"[y19] GUARD(indirectgate) SBControlCenterController gestureRecognizer:shouldReceiveTouch: missing");
        if (dock && class_getInstanceMethod(dock, sel_registerName("requireFloatingDockOverFolder"))) { gY19OrigFolder = BPX_Replace(dock, "requireFloatingDockOverFolder", (IMP)Y19_Folder); n++; }
        else BP_Log(@"[y19] GUARD(dockfolder) SBFloatingDockController requireFloatingDockOverFolder missing: nothing to neutralise");
        if (dock && class_getInstanceMethod(dock, sel_registerName("floatingDockWindow"))) { gY19OrigDockWindow = BPX_Replace(dock, "floatingDockWindow", (IMP)Y19_DockWindow); n++; }
        else BP_Log(@"[y19] GUARD(dockclip) SBFloatingDockController floatingDockWindow missing");
        BP_Log(@"[y19] installed %d of 5 (switches y17_indirectgate, y17_dockfolder, y17_dockclip)", n);
    }
}
#pragma clang diagnostic pop
