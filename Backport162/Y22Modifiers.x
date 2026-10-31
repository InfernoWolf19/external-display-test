// Y22Modifiers.x : delta sweep pass 2, switcher modifiers (F3), second file.  Setup: constructor.  Log prefix "[y22]".
//
//  y17_gridtap      -[SBGridSwitcherModifier handleTapAppLayoutEvent:] 16.2 0x1c78b8620 (16.0 0x1c640b234): super, then a SBPerformTransitionSwitcherEventResponse(gestureInitiated NO) appended whose
//                   request is +[SBSwitcherTransitionRequest requestForTapAppLayoutEvent:event] (appLayout + activatingDisplayItem of the tapped role + pointer source; G1C.x adds the class method to
//                   16.0) instead of a fresh SBMutableSwitcherTransitionRequest with only the app layout (16.0).  Same family as y11_tapreq of Y11Modifiers.x.
//  y17_floortap     -[_SBFullScreenAppFloorSwitcherModifier handleTapAppLayoutEvent:] 16.2 0x1c75cc850 (16.0 0x1c6148ef4): after super, for a tap on the floor's own layout that is not handled:
//                     leaf = [layout leafAppLayoutForRole:4 (center)]; no leaf, or the tapped role is the center role: Stage Manager off and the tap came from the pointer (event.source == 1):
//                       a tap transition with requestForTapAppLayoutEvent: (16.0 did nothing); otherwise nothing
//                     leaf exists and the tapped role is not the center role: the request is requestForTapAppLayoutEvent: (mutable) whose appLayout keeps the items that are not
//                       [leaf itemForLayoutRole:1], and (Stage Manager off) bundleIdentifierForAppExpose = bundle id of that item (16.0 started from an empty mutable request).
//  y17_homeflyin    -[SBHomeGestureToHomeSwitcherModifier frameForIndex:] / -scaleForIndex: 16.2 0x1c73b941c / 0x1c73b947c (16.0 0x1c5f44db8 / 0x1c5f44df8): the card fly-in offset of the frame and the
//                   offscreenCardScaleForFlyIn scale only apply while _showingOrAnimatingCardsForFlyIn is YES (init argument showingOrAnimatingCardsForFlyIn:); with NO 16.2 answers super's frame and
//                   scale.  16.0 applied the fly-in values always (cards slid / shrank to the fly-in position although no cards fly in: the odd animation when going home by gesture).
//  y17_windragpin   -[SBWindowDragTransitionSwitcherModifier shouldUseAnchorPointToPinLayoutRolesToSpace:] 16.2 has no override (0x1c796e3b4 is the class's end), 16.0 0x1c64b4e74 answered YES for layouts
//                   that contain an item of the dragged layout.  Ported: the override answers super's value.
// Needs a device: home gesture from an app with Stage Manager: the stage cards stay in place while no cards fly in; click an app card in the Exposé grid on the monitor.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "G1BKit.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y22Rect;

static id Y22_Ivar(id me, const char *name) { return BP_ObjIvar(me, class_getInstanceVariable(object_getClass(me), name)); }

static id Y22_Transition(id request) {
    Class pc = NSClassFromString(@"SBPerformTransitionSwitcherEventResponse");
    SEL s = sel_registerName("initWithTransitionRequest:gestureInitiated:");
    if (!request || !pc || ![pc instancesRespondToSelector:s]) return nil;
    return ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id, BOOL))objc_msgSend)([pc alloc], s, request, NO);
}
static id Y22_TapRequest(Class cls, id event) {
    SEL s = sel_registerName("requestForTapAppLayoutEvent:");
    if (!cls || ![(id)cls respondsToSelector:s]) { Y17_GuardOnce("tapreq", (id)cls, "requestForTapAppLayoutEvent:"); return nil; }
    return ((id (*)(id, SEL, id))objc_msgSend)((id)cls, s, event);
}

// ---- y17_gridtap ----
static IMP gY22OrigGrid;
static Class gY22GridSuper;
static id Y22_GridTap(id self, SEL _cmd, id event) {
    if (!BP_OnName("y17_gridtap") || !gY22GridSuper) return gY22OrigGrid ? ((id (*)(id, SEL, id))gY22OrigGrid)(self, _cmd, event) : nil;
    id r = G1B_HasSuper(gY22GridSuper, _cmd) ? G1B_SUPER(id, gY22GridSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    id req = Y22_TapRequest(NSClassFromString(@"SBSwitcherTransitionRequest"), event);
    id resp = Y22_Transition(req);
    if (!resp) {
        BP_Log(@"[y22] GUARD(gridtap) no tap request / transition response: the 16.0 body runs");
        return gY22OrigGrid ? ((id (*)(id, SEL, id))gY22OrigGrid)(self, _cmd, event) : r;
    }
    BPY_LOG(@"[y22] grid tap on %@: request %@", BPX_Obj0(event, "appLayout"), req);
    return G1B_AppendTo(resp, r);
}

// ---- y17_floortap ----
static IMP gY22OrigFloor;
static Class gY22FloorSuper;
static id Y22_FloorTap(id self, SEL _cmd, id event) {
    if (!BP_OnName("y17_floortap") || !gY22FloorSuper) return gY22OrigFloor ? ((id (*)(id, SEL, id))gY22OrigFloor)(self, _cmd, event) : nil;
    id r = G1B_HasSuper(gY22FloorSuper, _cmd) ? G1B_SUPER(id, gY22FloorSuper, self, _cmd, (struct objc_super *, SEL, id), event) : nil;
    id layout = BPX_Obj0(event, "appLayout");
    BOOL chamois = BPX_Bool0(self, "isChamoisWindowingUIEnabled");
    if (BPX_Bool0(event, "isHandled")) return r;
    id active = Y22_Ivar(self, "_activeAppLayout");
    if (!layout || ![layout isEqual:active]) return r;
    id leaf = BPY_SEND(id, (long long), layout, "leafAppLayoutForRole:", 4LL);
    if (!leaf || BPX_LL0(event, "layoutRole") == 4) {
        if (chamois || BPX_LL0(event, "source") != 1) return r;
        id resp = Y22_Transition(Y22_TapRequest(NSClassFromString(@"SBSwitcherTransitionRequest"), event));
        BPY_LOG(@"[y22] floor tap (pointer, no center leaf / center role): transition appended");
        return resp ? G1B_AppendTo(resp, r) : r;
    }
    id req = Y22_TapRequest(NSClassFromString(@"SBMutableSwitcherTransitionRequest"), event);
    if (!req) { BP_Log(@"[y22] GUARD(floortap) no mutable tap request: the 16.0 body runs"); return gY22OrigFloor ? ((id (*)(id, SEL, id))gY22OrigFloor)(self, _cmd, event) : r; }
    id primary = BPY_SEND(id, (long long), leaf, "itemForLayoutRole:", 1LL);
    id kept = BPX_Obj1(layout, "appLayoutWithItemsPassingTest:", (id)^BOOL(id item) { return ![item isEqual:primary]; });
    BPX_SetObj1(req, "setAppLayout:", kept);
    if (!chamois) BPX_SetObj1(req, "setBundleIdentifierForAppExpose:", BPX_Obj0(primary, "bundleIdentifier"));
    id resp = Y22_Transition(req);
    BPY_LOG(@"[y22] floor tap on a layout with a center leaf: kept %@ (chamois %d)", kept, (int)chamois);
    return resp ? G1B_AppendTo(resp, r) : r;
}

// ---- y17_homeflyin ----
static IMP gY22OrigHomeFrame, gY22OrigHomeScale;
static Class gY22HomeSuper;
static BOOL Y22_FlyIn(id self) {
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_showingOrAnimatingCardsForFlyIn");
    if (!iv) { Y17_GuardOnce("homeflyin", self, "_showingOrAnimatingCardsForFlyIn"); return YES; }
    return *(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(iv));
}
static Y22Rect Y22_HomeFrame(id self, SEL _cmd, unsigned long long i) {
    if (BP_OnName("y17_homeflyin") && gY22HomeSuper && !Y22_FlyIn(self)) {
        Y22Rect f = G1B_SUPER(Y22Rect, gY22HomeSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
        BPY_LOG(@"[y22] home gesture frame index %lu: no fly-in, super frame", (unsigned long)i);
        return f;
    }
    return gY22OrigHomeFrame ? ((Y22Rect (*)(id, SEL, unsigned long long))gY22OrigHomeFrame)(self, _cmd, i) : (Y22Rect){0, 0, 0, 0};
}
static double Y22_HomeScale(id self, SEL _cmd, unsigned long long i) {
    if (BP_OnName("y17_homeflyin") && gY22HomeSuper && !Y22_FlyIn(self)) return G1B_SUPER(double, gY22HomeSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    return gY22OrigHomeScale ? ((double (*)(id, SEL, unsigned long long))gY22OrigHomeScale)(self, _cmd, i) : 1.0;
}

// ---- y17_windragpin ----
static IMP gY22OrigPin;
static Class gY22PinSuper;
static BOOL Y22_Pin(id self, SEL _cmd, unsigned long long i) {
    if (BP_OnName("y17_windragpin") && gY22PinSuper && G1B_HasSuper(gY22PinSuper, _cmd)) return G1B_SUPER(BOOL, gY22PinSuper, self, _cmd, (struct objc_super *, SEL, unsigned long long), i);
    return gY22OrigPin ? ((BOOL (*)(id, SEL, unsigned long long))gY22OrigPin)(self, _cmd, i) : NO;
}

__attribute__((constructor)) static void Y22_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class gc = NSClassFromString(@"SBGridSwitcherModifier"), fc = NSClassFromString(@"_SBFullScreenAppFloorSwitcherModifier"), hc = NSClassFromString(@"SBHomeGestureToHomeSwitcherModifier"), wc = NSClassFromString(@"SBWindowDragTransitionSwitcherModifier");
        if (gc && class_getInstanceMethod(gc, sel_registerName("handleTapAppLayoutEvent:"))) { gY22GridSuper = class_getSuperclass(gc); gY22OrigGrid = BPX_Replace(gc, "handleTapAppLayoutEvent:", (IMP)Y22_GridTap); n++; }
        else BP_Log(@"[y22] GUARD(gridtap) SBGridSwitcherModifier handleTapAppLayoutEvent: missing: not installed");
        if (fc && class_getInstanceMethod(fc, sel_registerName("handleTapAppLayoutEvent:")) && class_getInstanceVariable(fc, "_activeAppLayout")) { gY22FloorSuper = class_getSuperclass(fc); gY22OrigFloor = BPX_Replace(fc, "handleTapAppLayoutEvent:", (IMP)Y22_FloorTap); n++; }
        else BP_Log(@"[y22] GUARD(floortap) _SBFullScreenAppFloorSwitcherModifier handleTapAppLayoutEvent: or _activeAppLayout missing: not installed");
        if (hc && class_getInstanceMethod(hc, sel_registerName("frameForIndex:")) && class_getInstanceMethod(hc, sel_registerName("scaleForIndex:"))) {
            gY22HomeSuper = class_getSuperclass(hc);
            gY22OrigHomeFrame = BPX_Replace(hc, "frameForIndex:", (IMP)Y22_HomeFrame);
            gY22OrigHomeScale = BPX_Replace(hc, "scaleForIndex:", (IMP)Y22_HomeScale);
            n++;
        } else BP_Log(@"[y22] GUARD(homeflyin) SBHomeGestureToHomeSwitcherModifier frameForIndex: / scaleForIndex: missing: not installed");
        if (wc && class_getInstanceMethod(wc, sel_registerName("shouldUseAnchorPointToPinLayoutRolesToSpace:"))) { gY22PinSuper = class_getSuperclass(wc); gY22OrigPin = BPX_Replace(wc, "shouldUseAnchorPointToPinLayoutRolesToSpace:", (IMP)Y22_Pin); n++; }
        else BP_Log(@"[y22] GUARD(windragpin) SBWindowDragTransitionSwitcherModifier shouldUseAnchorPointToPinLayoutRolesToSpace: missing: not installed");
        BP_Log(@"[y22] installed %d of 4 (switches y17_gridtap, y17_floortap, y17_homeflyin, y17_windragpin)", n);
    }
}
#pragma clang diagnostic pop
