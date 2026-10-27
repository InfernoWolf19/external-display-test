// Y13Fluid.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): small behaviour differences of the Stage Manager switcher view controller, its item containers and its gesture manager.
// Setup: constructor.  Log prefix "[y13]".
//
//  y13_bringfront  -[SBFluidSwitcherViewController appLayoutByBringingItemToFront:inAppLayout:] 16.2 0x1c7438794 (16.0 0x1c5fc0130): 16.0 returns the layout unchanged when the item is already the first of
//                  -zOrderedItems; 16.2 has no such early out, so clicking the window that is already in front still stamps it with the controller's next interaction time
//                  ([[[switcherController switcherCoordinator] _recentAppLayoutsController] _nextInteractionTime] through -attributesByModifyingLastInteractionTime:) like any other bring to front.  The stamp
//                  decides which window of a stage / pile counts as the most recently used one (strip order, recents).  Ported: wrapper for exactly that case, everything else runs the 16.0 body.
//  y13_reuse       -[SBFluidSwitcherItemContainer prepareForReuse] 16.2 0x1c72e3220 (16.0 0x1c5e704c8) additionally resets -setPreferredPointerLockStatusSuppressed:NO, -_updateForPointerHoveringOverEdge:0 and
//                  toggles one gesture recognizer's enabled state off and on (cancels an in flight recognizer; it sits next to the pointer state in the ivar order, the hover recognizer).  16.0 left a recycled
//                  container with the previous window's edge hover / pointer lock suppression / hover highlight.  Ported: the same three calls after the 16.0 body (the container is inactive and has no
//                  app layout at that point, 16.2 does them just before -setAppLayout:nil).
//  y13_failgestures  -[SBFluidSwitcherGestureManager failMultitaskingGesturesForReason:] 16.2 0x1c73136e0 (16.0 0x1c5ea0a20) also resets _unpinSplitViewApplicationGestureRecognizer (the recognizer of the Stage Manager
//                  window drag, see G1D.x section 4c) by disabling and enabling it, the way it resets the fluid scrunch recognizer; 16.0 only reset the scrunch recognizer, so a window drag could survive
//                  an event that fails all multitasking gestures (alert, lock, rotation).  Ported: the same two calls after the 16.0 body.
// Needs a device: (reuse) hover over the edge of a window, close it and open another one in the same container: no resize cursor / hover highlight on the new window; (failgestures) start dragging a
// window and trigger an alert: the drag ends.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY13OrigBring, gY13OrigReuse, gY13OrigFail;

// -[SBFluidSwitcherViewController appLayoutByBringingItemToFront:inAppLayout:]
static id Y13_BringFront(id self, SEL _cmd, id item, id layout) {
    if (BP_OnName("y13_bringfront") && item && layout && BPY_SEND(BOOL, (id), layout, "containsItem:", item)) {
        id first = [BPX_Obj0(layout, "zOrderedItems") firstObject];
        if (first && [first isEqual:item]) {
            id sc = BPX_Obj0(self, "switcherController");
            id ctl = BPX_Obj0(BPX_Obj0(sc, "switcherCoordinator"), "_recentAppLayoutsController");
            if (ctl && BPY_Responds(ctl, "_nextInteractionTime")) {
                long long t = BPX_LL0(ctl, "_nextInteractionTime");
                id attrs = BPX_Obj1(layout, "layoutAttributesForItem:", item);
                id stamped = attrs ? BPY_SEND(id, (long long), attrs, "attributesByModifyingLastInteractionTime:", t) : nil;
                id r = stamped ? BPX_Obj2(layout, "appLayoutByModifyingLayoutAttributes:forItem:", stamped, item) : nil;
                if (r) {
                    static long long lastLogged = -1;                   // logged when the stamp changes only: during a window drag this runs twice per input event (the log line, a 5 line item description, was 20 % of a drag's log)
                    if (t != lastLogged) { lastLogged = t; BPY_LOG(@"[y13] bring to front of the front window %@: interaction time stamped (%lld)", item, t); }
                    return r;
                }
            }
        }
    }
    return gY13OrigBring ? ((id (*)(id, SEL, id, id))gY13OrigBring)(self, _cmd, item, layout) : layout;
}

// -[SBFluidSwitcherItemContainer prepareForReuse]
static void Y13_Reuse(id self, SEL _cmd) {
    if (gY13OrigReuse) ((void (*)(id, SEL))gY13OrigReuse)(self, _cmd);
    if (!BP_OnName("y13_reuse")) return;
    if (BPY_Responds(self, "setPreferredPointerLockStatusSuppressed:")) BPY_SEND(void, (BOOL), self, "setPreferredPointerLockStatusSuppressed:", NO);
    if (BPY_Responds(self, "_updateForPointerHoveringOverEdge:")) BPY_SEND(void, (unsigned long long), self, "_updateForPointerHoveringOverEdge:", 0ULL);
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_hoverGestureRecognizer");
    id r = iv ? object_getIvar(self, iv) : nil;
    if (r && BPY_Responds(r, "setEnabled:")) {
        BPY_SEND(void, (BOOL), r, "setEnabled:", NO);
        BPY_SEND(void, (BOOL), r, "setEnabled:", YES);
    }
}

// -[SBFluidSwitcherGestureManager failMultitaskingGesturesForReason:]
static void Y13_Fail(id self, SEL _cmd, id reason) {
    if (gY13OrigFail) ((void (*)(id, SEL, id))gY13OrigFail)(self, _cmd, reason);
    if (!BP_OnName("y13_failgestures")) return;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_unpinSplitViewApplicationGestureRecognizer");
    id r = iv ? object_getIvar(self, iv) : nil;
    if (r && BPY_Responds(r, "setEnabled:")) {
        BPY_SEND(void, (BOOL), r, "setEnabled:", NO);
        BPY_SEND(void, (BOOL), r, "setEnabled:", YES);
    }
}

__attribute__((constructor)) static void Y13_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class vc = NSClassFromString(@"SBFluidSwitcherViewController"), ic = NSClassFromString(@"SBFluidSwitcherItemContainer"), gm = NSClassFromString(@"SBFluidSwitcherGestureManager");
        if (vc && class_getInstanceMethod(vc, sel_registerName("appLayoutByBringingItemToFront:inAppLayout:"))) {
            gY13OrigBring = BPX_Replace(vc, "appLayoutByBringingItemToFront:inAppLayout:", (IMP)Y13_BringFront); n++;
        }
        if (ic && class_getInstanceMethod(ic, sel_registerName("prepareForReuse"))) {
            gY13OrigReuse = BPX_Replace(ic, "prepareForReuse", (IMP)Y13_Reuse); n++;
        }
        if (gm && class_getInstanceMethod(gm, sel_registerName("failMultitaskingGesturesForReason:"))) {
            gY13OrigFail = BPX_Replace(gm, "failMultitaskingGesturesForReason:", (IMP)Y13_Fail); n++;
        }
        BP_Log(@"[y13] installed %d of 3 (switches y13_bringfront, y13_reuse, y13_failgestures)", n);
    }
}
#pragma clang diagnostic pop
