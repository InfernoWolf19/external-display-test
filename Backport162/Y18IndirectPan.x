// Y18IndirectPan.x : delta sweep pass 2, family SBIndirectPanGestureRecognizer (pointer / trackpad edge pan: the recognizer behind the indirect bottom edge pan of the Stage Manager switcher, the
// strip reveal, the floating dock, the control center / notification pulls).  Setup: constructor.  Log prefix "[y18]".
//
// What 16.2 changed (class SBIndirectPanGestureRecognizer, 16.0 0x1c63988a8.. / 16.2 0x1c7841c6c..; the normalised raw diff of every method was read, see the table below):
//  y17_indirectpan  the hover state machine of the recognizer:
//     -_hoverEntered:withEvent:   16.2 0x1c78423f8 (16.0 0x1c6399018): 16.0 only stored the event and its touch.  16.2, when no hover event is held and the event has exactly one touch:
//                                 -_resetTranslationState, stores event + touch, captures _gestureStartLocation (the pointer model location) when it is nil; then ALWAYS
//                                 -_setUpIdleTimersIfNeededForEvent: (new in 16.2: the 0.1 s repeating idle timers that 16.0 created inside -_hoverMoved:).
//     -_hoverMoved:withEvent:     16.2 0x1c784251c (16.0 0x1c63990c4): same state machine as 16.0 with these differences: (1) bails when the held touch is nil or its phase is not
//                                 UITouchPhaseRegionMoved (6); (2) the idle timers are only (re)created for TRACKPAD events here (mouse timers moved to -_hoverEntered:); (3) when the gesture goes
//                                 from Began to Changed it cancels the touches of the display of the container view, [[[view _fbsDisplayConfiguration] hardwareIdentifier]] ->
//                                 BKSHIDServicesCancelTouchesOnDisplay (16.0: BKSHIDServicesCancelTouchesOnMainDisplay: a pointer gesture on the monitor cancelled the touches of the iPad).
//     -_hoverExited:withEvent: / -_hoverCancelled:withEvent:   16.2 0x1c7842d20 / 0x1c7842d88: 16.0 just dropped the event and the touch.  16.2 -_resetTranslationState (which drops them) and then
//                                 moves the gesture: Began or Changed -> Ended (exited) / Cancelled (cancelled), Possible -> Failed.  A pointer that leaves the window (crossing to the other
//                                 display, unplug) therefore ends a running edge gesture instead of leaving it half way.
//     -_resetTranslationState     16.2 0x1c78420bc (16.0 0x1c6398d80): the 16.0 body plus dropping _currentHoverEvent and _currentTouch (weak in 16.2).
//     -_shouldReceiveEvent:       NOT changed here: 16.2 0x1c78421e0 only answers [event type] == 11 (UIEventTypeHover) and moved the edge gate into -_shouldReceiveTouch:withEvent: (0x1c7842204,
//                                 the same logic plus -_startWatchdogTimerIfNecessary).  16.0 UIKit evaluates -_shouldReceiveEvent: once per event before the delegate and -_shouldReceiveTouch:withEvent:,
//                                 the 16.0 gate (edge test with 30 pt / 100 pt insets, same code) is kept where it is: a deliberate deviation of the delivery path, not of the logic (README row y17_indirectpan).
//  y17_pancancel    the cancel of the touches on the display of the view (3) above, own switch: off = BKSHIDServicesCancelTouchesOnMainDisplay like 16.0.
//  Guard (logged, last line): when -_hoverMoved: arrives while no touch is held (16.2 relies on UIKit delivering -_hoverEntered: again after a reset; 16.0 UIKit did not need that because the
//  16.0 recognizer kept the touch across resets) and the event carries exactly one hover touch in the moved phase, the touch is captured first (the -_hoverEntered: work), log line GUARD(indirectpan).
//  Rows decided without code (normalised raw diff of 16.0 -> 16.2, DELTA-SWEEP):
//     -_mouseIdleTimerFired: / -_mouseIdleTimerElapsed / -_trackpadIdleTimerFired: / -_trackpadIdleTimerElapsed / -trackpadDidTouchUpWithEvent:  identical code, only audit history lines added.
//     -_updateTranslationWithPointerEventAttributes:activeEdge: / -_pointerModelLocation  16.2 passes the container's screen to _SBPointerEventAcceleratedRelativePositionForOrientation and reads
//                 the orientation provider through a weak ivar: the function converts the unit vectors (1,0) (0,1) minus the converted origin, the bounds of the screen cancel, the factor
//                 stays 0.3 (0x1c65cda48 / 0x1c7a90d48): numerically identical.
//     -dealloc / -currentHoverEvent / -currentTouch / initWithTarget:action:edges: / watchdog (-_startWatchdogTimerIfNecessary, -_watchdogFired, -setState:): 16.2 removed the
//                 system gesture manager parameter (the manager registers the recognizer in -_enableSystemGesture:withType:, DELTA-SWEEP SBSystemGestureManager rows), made the two refs weak and
//                 added a diagnostics watchdog that only exists for the recognizers named indirectPresentCoverSheetGestureRecognizer / indirectPresentControlCenterGestureRecognizer: after 2 s
//                 -_watchdogFired dumps the BSAuditHistory (last 8 items) to os_log; it never changes the gesture state.
// The four private C helpers of 16.0 (_SBPointerHIDSubEventFromEvent 0x1c6497ae4, _SBPointerEventIsTrackpadEvent 0x1c6497c60, _SBPointerEventRepresentsTrackpadTouchUp 0x1c6497bec,
// _SBPointerEventHasMovementOnAxis 0x1c6497c88) are not exported: they are re-implemented below from their 16.0 disassembly.
// Needs a device: push the pointer to the bottom edge of the monitor (dock / switcher reveal), to the top edge (control center), fast across the display border: the log shows
// "[y18] hoverMoved ..." lines; a gesture on the monitor no longer cancels the touches of the iPad.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y; } Y18Pt;

static IMP gY18OrigEntered, gY18OrigMoved, gY18OrigExited, gY18OrigCancelled, gY18OrigReset;
static BOOL gY18Ok;
static void *(*gY18HIDChildren)(void *);
static int (*gY18HIDType)(void *);
static id (*gY18PtrAttrs)(void *);
static double (*gY18Now)(void);
static void (*gY18CancelDisplay)(id);
static void (*gY18CancelMain)(void);

// ivars of the 16.0 class, resolved once by name (a missing one keeps the 16.0 recognizer, logged)
static struct {
    ptrdiff_t edges, avoid, cancelAway, paused, thresh, reqEdge, passed, inputType, endReason, activatedEdge, origin, lastPoint, lastMouseTs, mouseEntered, lastMouseAct, actDist;
    Ivar hoverEv, touch, mouseTimer, trackpadTimer, startLoc;
} gIv;

#define Y18_B(o, off)  (*(BOOL *)((char *)(__bridge void *)(o) + (off)))
#define Y18_Q(o, off)  (*(unsigned long long *)((char *)(__bridge void *)(o) + (off)))
#define Y18_D(o, off)  (*(double *)((char *)(__bridge void *)(o) + (off)))
#define Y18_P(o, off)  (*(Y18Pt *)((char *)(__bridge void *)(o) + (off)))

static ptrdiff_t Y18_Off(Class c, const char *name, char enc) {
    Ivar iv = class_getInstanceVariable(c, name);
    const char *e = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!iv || !e || e[0] != enc) { BP_Log(@"[y18] GUARD(indirectpan) ivar %s missing or of another type (%s) on SBIndirectPanGestureRecognizer: 16.0 recognizer stays", name, e ? e : "none"); return -1; }
    return ivar_getOffset(iv);
}
static Ivar Y18_ObjIvar(Class c, const char *name) {
    Ivar iv = class_getInstanceVariable(c, name);
    if (!BP_IvarIsObj(iv)) { BP_Log(@"[y18] GUARD(indirectpan) object ivar %s missing on SBIndirectPanGestureRecognizer: 16.0 recognizer stays", name); return NULL; }
    return iv;
}

// ---- the four private C helpers of 16.0, re-implemented ----
static void *Y18_HIDSubEvent(id event) {            // _SBPointerHIDSubEventFromEvent 0x1c6497ae4: the first child of the HID event of type 0x11 (pointer)
    if (!gY18HIDChildren || !gY18HIDType) return NULL;
    void *hid = ((void *(*)(id, SEL))objc_msgSend)(event, sel_registerName("_hidEvent"));
    if (!hid) return NULL;
    NSArray *kids = (__bridge NSArray *)gY18HIDChildren(hid);
    for (id child in kids) if (gY18HIDType((__bridge void *)child) == 0x11) return (__bridge void *)child;
    return NULL;
}
static BOOL Y18_IsTrackpad(id attrs) { return attrs && BPX_LL0(attrs, "source") == 0xc; }                       // 0x1c6497c60
static BOOL Y18_TouchUp(id attrs) {                                                                             // 0x1c6497bec
    return attrs && BPX_LL0(attrs, "source") == 0xc && BPX_LL0(attrs, "fingerDownCount") == 0 && (BPX_LL0(attrs, "options") & 2);
}
static BOOL Y18_HasMovement(id attrs, long long axis) {                                                         // 0x1c6497c88
    double x = 0, y = 0;
    if (BPY_Responds(attrs, "acceleratedRelativePositionX")) x = ((double (*)(id, SEL))objc_msgSend)(attrs, sel_registerName("acceleratedRelativePositionX"));
    if (BPY_Responds(attrs, "acceleratedRelativePositionY")) y = ((double (*)(id, SEL))objc_msgSend)(attrs, sel_registerName("acceleratedRelativePositionY"));
    BOOL mx = x != 0, my = y != 0;
    BOOL r = (axis != 2) ? YES : my;
    if (axis == 3) r = mx || my;
    if (axis == 1) r = mx;
    return r;
}

static Y18Pt Y18_Loc(id self) { return ((Y18Pt (*)(id, SEL))objc_msgSend)(self, sel_registerName("_pointerModelLocation")); }
static unsigned long long Y18_Edge(id self, Y18Pt p, id view, double inset) {
    return ((unsigned long long (*)(id, SEL, Y18Pt, id, double))objc_msgSend)(self, sel_registerName("_edgeForPointerModelLocation:inView:inset:"), p, view, inset);
}
static long long Y18_State(id self) { return BPX_LL0(self, "state"); }
static void Y18_SetState(id self, long long s) { ((void (*)(id, SEL, long long))objc_msgSend)(self, sel_registerName("setState:"), s); }
static id Y18_Obj(id self, Ivar iv) { return BP_ObjIvar(self, iv); }

// -_setUpIdleTimersIfNeededForEvent: (16.2 0x1c7842dec): the 0.1 s repeating idle timers, trackpad or mouse by the source of the pointer attributes
static void Y18_SetUpTimers(id self, id event) {
    void *hid = Y18_HIDSubEvent(event);
    id attrs = (hid && gY18PtrAttrs) ? gY18PtrAttrs(hid) : nil;
    BOOL trackpad = Y18_IsTrackpad(attrs);
    Ivar tv = trackpad ? gIv.trackpadTimer : gIv.mouseTimer;
    if (Y18_Obj(self, tv)) return;
    BPY_LOG(@"[y18] Creating a new %s idle timer.", trackpad ? "trackpad" : "mouse");
    __weak id weakSelf = self;
    SEL fired = sel_registerName(trackpad ? "_trackpadIdleTimerFired:" : "_mouseIdleTimerFired:");
    NSTimer *t = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        id s = weakSelf;
        if (s) ((void (*)(id, SEL, id))objc_msgSend)(s, fired, timer);
    }];
    object_setIvar(self, tv, t);
    [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
}

// the work of -_hoverEntered: that captures the first hover touch
static void Y18_Capture(id self, id touches, id event) {
    ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("_resetTranslationState"));
    object_setIvar(self, gIv.hoverEv, event);
    object_setIvar(self, gIv.touch, [touches anyObject]);
    Y18Pt loc = Y18_Loc(self);
    if (!Y18_Obj(self, gIv.startLoc)) {
        object_setIvar(self, gIv.startLoc, ((id (*)(id, SEL, Y18Pt))objc_msgSend)((id)[NSValue class], sel_registerName("valueWithCGPoint:"), loc));
    }
}

// -_hoverEntered:withEvent:
static void Y18_Entered(id self, SEL _cmd, id touches, id event) {
    if (!gY18Ok || !BP_OnName("y17_indirectpan")) { if (gY18OrigEntered) ((void (*)(id, SEL, id, id))gY18OrigEntered)(self, _cmd, touches, event); return; }
    BPY_LOG(@"[y18] hoverEntered:withEvent: (held event %d, %lu touches)", Y18_Obj(self, gIv.hoverEv) != nil, (unsigned long)[touches count]);
    if (!Y18_Obj(self, gIv.hoverEv) && [touches count] == 1) Y18_Capture(self, touches, event);
    Y18_SetUpTimers(self, event);
}

// -_hoverExited:withEvent: / -_hoverCancelled:withEvent:
static void Y18_Ended(id self, SEL _cmd, id touches, id event, BOOL cancelled) {
    ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("_resetTranslationState"));
    long long st = Y18_State(self), to;
    if (cancelled) to = (st == 1) ? 4 : ((st == 2) ? 4 : 5);
    else to = (st == 1) ? 3 : ((st == 2) ? 3 : 5);
    BPY_LOG(@"[y18] %s: state %lld -> %lld", cancelled ? "hoverCancelled" : "hoverExited", st, to);
    Y18_SetState(self, to);
}
static void Y18_Exited(id self, SEL _cmd, id touches, id event) {
    if (!gY18Ok || !BP_OnName("y17_indirectpan")) { if (gY18OrigExited) ((void (*)(id, SEL, id, id))gY18OrigExited)(self, _cmd, touches, event); return; }
    Y18_Ended(self, _cmd, touches, event, NO);
}
static void Y18_Cancelled(id self, SEL _cmd, id touches, id event) {
    if (!gY18Ok || !BP_OnName("y17_indirectpan")) { if (gY18OrigCancelled) ((void (*)(id, SEL, id, id))gY18OrigCancelled)(self, _cmd, touches, event); return; }
    Y18_Ended(self, _cmd, touches, event, YES);
}

// -_resetTranslationState: the 16.0 body, then the event and the touch are dropped
static void Y18_Reset(id self, SEL _cmd) {
    if (gY18OrigReset) ((void (*)(id, SEL))gY18OrigReset)(self, _cmd);
    if (gY18Ok && BP_OnName("y17_indirectpan")) { object_setIvar(self, gIv.hoverEv, nil); object_setIvar(self, gIv.touch, nil); }
}

static void Y18_Fail(id self, NSString *reason) {
    BPY_LOG(@"[y18] Moving to state Failed; shouldBegin is NO. Reason: %@", reason);
    Y18_SetState(self, 5);
}

static void Y18_CancelTouches(id self, id view) {
    id cfg = Y17_Obj0("pancancel", view, "_fbsDisplayConfiguration");
    id hw = cfg ? Y17_Obj0("pancancel", cfg, "hardwareIdentifier") : nil;
    if (BP_OnName("y17_pancancel") && hw && gY18CancelDisplay) {
        gY18CancelDisplay(hw);
        BPY_LOG(@"[y18] cancelled the touches of display %@", hw);
    } else if (gY18CancelMain) {
        gY18CancelMain();
        BP_Log(@"[y18] cancelled the touches of the main display (switch %s, display identifier %@)", BP_OnName("y17_pancancel") ? "on, GUARD(pancancel) no display configuration" : "y17_pancancel off", hw);
    }
}

// -_hoverMoved:withEvent:  (16.2 0x1c784251c)
static void Y18_Moved(id self, SEL _cmd, id touches, id event) {
    if (!gY18Ok || !BP_OnName("y17_indirectpan")) { if (gY18OrigMoved) ((void (*)(id, SEL, id, id))gY18OrigMoved)(self, _cmd, touches, event); return; }
    id touch = Y18_Obj(self, gIv.touch), hover = Y18_Obj(self, gIv.hoverEv);
    if (!touch || !hover) {
        // guard: 16.2 bails here and waits for the next -_hoverEntered:; recapture when this event is the one moving hover touch
        id one = ([touches count] == 1) ? [touches anyObject] : nil;
        if (one && BPX_LL0(one, "phase") == 6) {
            BP_Log(@"[y18] GUARD(indirectpan) hoverMoved without a captured touch: capturing it (the work of hoverEntered)");
            Y18_Capture(self, touches, event);
            Y18_SetUpTimers(self, event);
            touch = Y18_Obj(self, gIv.touch);
            hover = Y18_Obj(self, gIv.hoverEv);
        }
    }
    BPY_LOG(@"[y18] hoverMoved:withEvent: - currentTouch is %snil - currentHoverEvent is %snil", touch ? "NOT " : "", hover ? "NOT " : "");
    long long phase = touch ? BPX_LL0(touch, "phase") : 0;
    if (phase != 6) { BPY_LOG(@"[y18] hoverMoved:withEvent: - bailing because current touch is: %@ with phase: %lld", touch, phase); return; }

    Y18Pt loc = Y18_Loc(self);
    id view = BPX_Obj0(self, "containerView");
    unsigned long long activeEdge = Y18_Edge(self, loc, view, 1.0);
    unsigned long long hit = Y18_Q(self, gIv.edges) & activeEdge;
    BOOL external = NO;
    if (hit && Y18_B(self, gIv.avoid)) {
        id srv = BPX_Obj0(BPX_MainWorkspace(), "universalControlServer");
        unsigned long long ext = srv ? (unsigned long long)BPX_LL0(srv, "externalProcessActiveOnScreenEdges") : 0;
        if ((activeEdge & ~ext) == 0) { external = YES; BPY_LOG(@"[y18] hoverMoved:withEvent: - externally controlled edges: %lu contains current edge %lu", (unsigned long)ext, (unsigned long)activeEdge); }
    }
    void *hid = Y18_HIDSubEvent(event);
    id attrs = (hid && gY18PtrAttrs) ? gY18PtrAttrs(hid) : nil;
    if (!attrs) { BPY_LOG(@"[y18] hoverMoved:withEvent: - bailing because pointer attributes is nil"); return; }
    BOOL trackpad = Y18_IsTrackpad(attrs), touchUp;
    if (trackpad) { Y18_Q(self, gIv.inputType) = 0; touchUp = Y18_TouchUp(attrs); } else { touchUp = NO; Y18_Q(self, gIv.inputType) = 1; }
    double now = gY18Now ? gY18Now() : 0;
    if (Y18_B(self, gIv.paused)) {
        if (hit == 0 || touchUp || (now - Y18_D(self, gIv.lastMouseTs)) >= 0.15) Y18_B(self, gIv.paused) = NO;
    }
    BOOL moved = Y18_HasMovement(attrs, 3);
    if (!trackpad && moved) Y18_D(self, gIv.lastMouseTs) = now;
    if (trackpad) {
        Y18_SetUpTimers(self, event);
        if (Y18_B(self, gIv.reqEdge) && hit == 0 && !Y18_B(self, gIv.passed)) {
            if ((Y18_Q(self, gIv.edges) & Y18_Edge(self, loc, view, 100.0)) == 0) Y18_B(self, gIv.passed) = YES;
        }
    }
    long long st = Y18_State(self);
    if (st == 0) {
        if (hit == 0 || touchUp) {
            if (!trackpad || touchUp) {
                BPY_LOG(@"[y18] Moving from Possible to Failed because %s", touchUp ? "of a touch-up" : "we're not on the correct edge");
                Y18_SetState(self, 5);
            } else BPY_LOG(@"[y18] hoverMoved: trackpad, no edge, no touch-up: stays Possible");
            return;
        }
        if (external || !moved || Y18_B(self, gIv.paused)) { BPY_LOG(@"[y18] Pointer event has a zero offset, moving to Failed"); Y18_SetState(self, 5); return; }
        Y18_P(self, gIv.origin) = loc;
        Y18_P(self, gIv.lastPoint) = loc;
        ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(self, sel_registerName("_updateTranslationWithPointerEventAttributes:activeEdge:"), attrs, activeEdge);
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("updateTouchHistoryWithTouches:"), BPX_Obj0(hover, "allTouches"));
        if (!view) { Y18_Fail(self, @"System gesture view is nil"); return; }
        if (Y18_B(self, gIv.reqEdge)) {
            if (trackpad) {
                id sv = Y18_Obj(self, gIv.startLoc);
                Y18Pt sp = {0, 0};
                if (sv && BPY_Responds(sv, "pointValue")) sp = ((Y18Pt (*)(id, SEL))objc_msgSend)(sv, sel_registerName("pointValue"));
                if (Y18_Edge(self, sp, view, 100.0) != activeEdge) { Y18_Fail(self, @"Trackpad gesture did not start near the edge."); return; }
                if (Y18_B(self, gIv.passed)) { Y18_Fail(self, @"Trackpad gesture started near the edge, but left the region before coming back."); return; }
            } else {
                double t = gY18Now ? gY18Now() : now;
                if (t - Y18_D(self, gIv.mouseEntered) <= 0.25) { Y18_Fail(self, @"Mouse pointer has not spent enough time on the edge to be considered a second pan."); return; }
            }
        }
        Y18_Q(self, gIv.activatedEdge) = activeEdge;
        BPY_LOG(@"[y18] Moving to state Began");
        Y18_SetState(self, 1);
        return;
    }
    if (st == 1) {
        if (hit == 0 || touchUp) {
            Y18_Q(self, gIv.endReason) = touchUp ? 1 : (unsigned long long)Y18_B(self, gIv.paused);
            BPY_LOG(@"[y18] Pointer either moved away from active edge, or got touch up. Moving from Began to Ended (reason %llu)", Y18_Q(self, gIv.endReason));
            Y18_SetState(self, 3);
            return;
        }
        ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(self, sel_registerName("_updateTranslationWithPointerEventAttributes:activeEdge:"), attrs, activeEdge);
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("updateTouchHistoryWithTouches:"), BPX_Obj0(hover, "allTouches"));
        Y18_CancelTouches(self, view);
        BPY_LOG(@"[y18] Pointer is on active edge; moving from state Began to Changed.");
        Y18_SetState(self, 2);
        return;
    }
    if (st == 2) {
        if (touchUp) {
            BPY_LOG(@"[y18] Moving to state Ended due to touch-up event");
            Y18_Q(self, gIv.endReason) = 1;
            Y18_SetState(self, 3);
            return;
        }
        if (Y18_B(self, gIv.cancelAway) && hit == 0) {
            BPY_LOG(@"[y18] Moving to state Cancelled; pointer moved away from active edge");
            Y18_Q(self, gIv.endReason) = 2;
            Y18_SetState(self, 4);
            return;
        }
        Y18_SetState(self, 2);
        ((void (*)(id, SEL, id, unsigned long long))objc_msgSend)(self, sel_registerName("_updateTranslationWithPointerEventAttributes:activeEdge:"), attrs, activeEdge);
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("updateTouchHistoryWithTouches:"), BPX_Obj0(hover, "allTouches"));
        if (!Y18_B(self, gIv.thresh) || trackpad) return;
        Y18Pt tr = ((Y18Pt (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("translationInView:"), view);
        BOOL reached = ((BOOL (*)(id, SEL, double, Y18Pt, unsigned long long))objc_msgSend)(self, sel_registerName("_hasTranslationReachedThreshold:withTranslation:forEdge:"), Y18_D(self, gIv.actDist), tr, activeEdge);
        if (reached) {
            BPY_LOG(@"[y18] Moving to state Ended because the mouse threshold was reached");
            Y18_Q(self, gIv.endReason) = 3;
            Y18_D(self, gIv.lastMouseAct) = gY18Now ? gY18Now() : now;
            Y18_SetState(self, 3);
            ((void (*)(id, SEL, BOOL))objc_msgSend)(self, sel_registerName("setPausedUntilTouchedUpOrMovedAwayFromEdge:"), YES);
        }
    }
}

__attribute__((constructor)) static void Y18_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBIndirectPanGestureRecognizer");
        if (!c) { BP_Log(@"[y18] GUARD(indirectpan) SBIndirectPanGestureRecognizer missing: nothing installed"); return; }
        const char *need[] = { "_hoverEntered:withEvent:", "_hoverMoved:withEvent:", "_hoverExited:withEvent:", "_hoverCancelled:withEvent:", "_resetTranslationState", "_pointerModelLocation",
            "_edgeForPointerModelLocation:inView:inset:", "_updateTranslationWithPointerEventAttributes:activeEdge:", "updateTouchHistoryWithTouches:", "translationInView:",
            "_hasTranslationReachedThreshold:withTranslation:forEdge:", "setPausedUntilTouchedUpOrMovedAwayFromEdge:", "_mouseIdleTimerFired:", "_trackpadIdleTimerFired:", "containerView" };
        for (size_t i = 0; i < sizeof need / sizeof need[0]; i++) {
            if (!class_getInstanceMethod(c, sel_registerName(need[i]))) { BP_Log(@"[y18] GUARD(indirectpan) method %s missing on SBIndirectPanGestureRecognizer: 16.0 recognizer stays", need[i]); return; }
        }
        gY18HIDChildren = (void *(*)(void *))dlsym(RTLD_DEFAULT, "IOHIDEventGetChildren");
        gY18HIDType = (int (*)(void *))dlsym(RTLD_DEFAULT, "IOHIDEventGetType");
        gY18PtrAttrs = (id (*)(void *))dlsym(RTLD_DEFAULT, "BKSHIDEventGetPointerAttributes");
        gY18Now = (double (*)(void))dlsym(RTLD_DEFAULT, "BSContinuousMachTimeNow");
        gY18CancelDisplay = (void (*)(id))dlsym(RTLD_DEFAULT, "BKSHIDServicesCancelTouchesOnDisplay");
        gY18CancelMain = (void (*)(void))dlsym(RTLD_DEFAULT, "BKSHIDServicesCancelTouchesOnMainDisplay");
        if (!gY18HIDChildren || !gY18HIDType || !gY18PtrAttrs || !gY18Now || !gY18CancelMain) {
            BP_Log(@"[y18] GUARD(indirectpan) C symbols missing (IOHIDEventGetChildren %p, IOHIDEventGetType %p, BKSHIDEventGetPointerAttributes %p, BSContinuousMachTimeNow %p, CancelTouchesOnMainDisplay %p): 16.0 recognizer stays",
                   (void *)gY18HIDChildren, (void *)gY18HIDType, (void *)gY18PtrAttrs, (void *)gY18Now, (void *)gY18CancelMain);
            return;
        }
        gIv.edges = Y18_Off(c, "_edges", 'Q'); gIv.avoid = Y18_Off(c, "_avoidActivatingForExternallyOwnedEdges", 'B'); gIv.cancelAway = Y18_Off(c, "_shouldCancelAfterMovingAwayFromEdge", 'B');
        gIv.paused = Y18_Off(c, "_pausedUntilTouchedUpOrMovedAwayFromEdge", 'B'); gIv.thresh = Y18_Off(c, "_shouldActivateWithThreshold", 'B'); gIv.reqEdge = Y18_Off(c, "_shouldRequireGestureToStartAtEdge", 'B');
        gIv.passed = Y18_Off(c, "_gesturePassedThroughScreenCenterRegion", 'B'); gIv.inputType = Y18_Off(c, "_currentInputType", 'Q'); gIv.endReason = Y18_Off(c, "_endReason", 'Q');
        gIv.activatedEdge = Y18_Off(c, "_activatedEdge", 'Q'); gIv.origin = Y18_Off(c, "_origin", '{'); gIv.lastPoint = Y18_Off(c, "_lastKnownPoint", '{');
        gIv.lastMouseTs = Y18_Off(c, "_lastKnownMouseEventTimestamp", 'd'); gIv.mouseEntered = Y18_Off(c, "_mouseEnteredNearEdgeRegionTimestamp", 'd');
        gIv.lastMouseAct = Y18_Off(c, "_lastMouseActivationTimestamp", 'd'); gIv.actDist = Y18_Off(c, "_activationRecognitionDistance", 'd');
        gIv.hoverEv = Y18_ObjIvar(c, "_currentHoverEvent"); gIv.touch = Y18_ObjIvar(c, "_currentTouch"); gIv.mouseTimer = Y18_ObjIvar(c, "_mouseIdleTimer");
        gIv.trackpadTimer = Y18_ObjIvar(c, "_trackpadIdleTimer"); gIv.startLoc = Y18_ObjIvar(c, "_gestureStartLocation");
        ptrdiff_t *offs[] = { &gIv.edges, &gIv.avoid, &gIv.cancelAway, &gIv.paused, &gIv.thresh, &gIv.reqEdge, &gIv.passed, &gIv.inputType, &gIv.endReason, &gIv.activatedEdge, &gIv.origin, &gIv.lastPoint,
            &gIv.lastMouseTs, &gIv.mouseEntered, &gIv.lastMouseAct, &gIv.actDist };
        for (size_t i = 0; i < sizeof offs / sizeof offs[0]; i++) if (*offs[i] < 0) return;
        if (!gIv.hoverEv || !gIv.touch || !gIv.mouseTimer || !gIv.trackpadTimer || !gIv.startLoc) return;
        gY18Ok = YES;
        gY18OrigEntered = BPX_Replace(c, "_hoverEntered:withEvent:", (IMP)Y18_Entered);
        gY18OrigMoved = BPX_Replace(c, "_hoverMoved:withEvent:", (IMP)Y18_Moved);
        gY18OrigExited = BPX_Replace(c, "_hoverExited:withEvent:", (IMP)Y18_Exited);
        gY18OrigCancelled = BPX_Replace(c, "_hoverCancelled:withEvent:", (IMP)Y18_Cancelled);
        gY18OrigReset = BPX_Replace(c, "_resetTranslationState", (IMP)Y18_Reset);
        BP_Log(@"[y18] installed (switches y17_indirectpan, y17_pancancel; display cancel %s)", gY18CancelDisplay ? "available" : "MISSING: main display cancel like 16.0");
    }
}
#pragma clang diagnostic pop
