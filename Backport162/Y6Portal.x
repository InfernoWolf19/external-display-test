// Y6Portal.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): the cross display window drag shows the window on the display under the pointer.  Setup: constructor.  Log prefix "[y6]".
//
// 16.2: while a Stage Manager window is dragged with the pointer / finger, the display that is NOT the window's own gets a live copy of it: the coordinator of the target display's live
// content overlays (SBFullScreenSwitcherLiveContentOverlayCoordinator) makes an overlay of a new kind (overlay type 4, SBFluidSwitcherPortaledSceneLiveContentOverlay, the class is G3B.x)
// whose content is a CA portal (SBPortalView with CAPortalLayer.crossDisplay = YES) onto the source display's live scene view.  Without it the window stays on the source display until the
// drop (P1Drag.m moves the scene), the other display shows nothing.  G3B.x has the overlay class and G1D.x the plumbing (enumerateSwitcherControllersWithBlock:,
// convertAppLayout:fromSwitcherController:toSwitcherController:); the creator and its three small helpers were missing ("no creator", G3B 1.7):
//   * -[SBFullScreenSwitcherLiveContentOverlayCoordinator _updatePortaledSceneLiveContentOverlays]  16.2 0x1c74ce070 (+ blocks 0x1c74ce5ac, 0x1c74ce650).  The source switcher controller is the one
//     whose layout state display ordinal equals the drag's selected layout's preferred display ordinal; for a continuous expose window drag whose source is not this display the layout is converted,
//     a portal of the source overlay (-[SBFluidSwitcherViewController liveContentOverlayForAppLayout:], new, = the _liveContentOverlays entry) is wrapped in a portaled overlay and added; type 4
//     overlays that are not for the current layout are removed again.
//   * -[SBFullScreenSwitcherSceneLiveContentOverlay newPortaledLiveContentOverlayView] 0x1c74cfa28 (SBPortalView sourced from the scene content view).
//   * called after -_updateAlwaysLiveSceneContentOverlays in transitionDidBegin / transitionDidEnd / appLayoutWillBecomeVisible: / appLayoutDidBecomeHidden: (16.2 0x1c74cad34 / 0x1c74cb848 /
//     0x1c74cc2f0 / 0x1c74cc388); here after the saved 16.0 body, unless live content overlay updates are suspended (the 16.2 early exit).
//   * -_removeOverlayForAppLayout:animated: 16.2 0x1c74cdbd8: type 4 is removed like types 1 and 2 (16.0 0x1c6051704 did not know it).
//   * -_updateAlwaysLiveSceneContentOverlays 16.2 0x1c74cdd38 sizes the always-live overlay (SBFullScreenAlwaysLiveLiveContentOverlay initWithSceneHandle:referenceSize:containerOrientation:)
//     with the reference bounds of the coordinator's OWN window scene screen (16.0 0x1c6051854: [[UIScreen mainScreen] _referenceBounds], wrong on the monitor).  Ported: while the saved 16.0
//     method runs the overlay initialiser gets the scene's screen size (switch y6_alwayslive).
// Switch y6_portal (all of the portal part).  Needs a device with the monitor: drag a window from the iPad over to the monitor: while the pointer is on the monitor the window follows it there (a live copy),
// the iPad side keeps the placeholder; dropping works as before (P1Drag.m).  With the switch off nothing here runs.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y6Rect;       // CGRect (HFA, d0..d3)
typedef struct { double w, h; } Y6Size;             // CGSize (HFA, d0..d1)

@interface NSObject (Y6Decl)       // declaration only: ARC treats new... as +1
- (id)newPortaledLiveContentOverlayView;
@end

static IMP gY6Begin, gY6End, gY6Visible, gY6Hidden, gY6Remove, gY6AlwaysUpdate, gY6AlwaysInit;
static __thread void *tY6AlwaysScene;               // unretained: the window scene whose screen sizes always-live overlays while -_updateAlwaysLiveSceneContentOverlays runs

static id Y6_Controller(id coord) {                 // 16.2 -[... switcherController] (weak ivar +0x20): the controller of this coordinator's window scene
    Class cc = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
    id shared = cc ? BPX_Obj0((id)cc, "sharedInstance") : nil;
    return BPX_Obj1(shared, "switcherControllerForWindowScene:", BPX_Obj0(coord, "_sbWindowScene"));
}
static BOOL Y6_Suspended(id coord) { return BPX_Bool0(coord, "areLiveContentOverlayUpdatesSuspended"); }

// -[SBFluidSwitcherViewController liveContentOverlayForAppLayout:]  16.2 0x1c743a450: [_liveContentOverlays objectForKey:layout]
static id Y6_VCOverlayFor(id self, SEL _cmd, id layout) {
    id d = BPX_IvarObj(self, "_liveContentOverlays");
    return layout ? [d objectForKey:layout] : nil;
}

// -[SBFullScreenSwitcherSceneLiveContentOverlay newPortaledLiveContentOverlayView]  16.2 0x1c74cfa28 (+1 return)
static __attribute__((ns_returns_retained)) id Y6_NewPortal(id self, SEL _cmd) {
    id content = BPX_Obj0(BPX_IvarObj(self, "_deviceApplicationSceneViewController"), "sceneContentView");
    Class pv = NSClassFromString(@"SBPortalView");
    if (!content || !pv) return nil;
    id v = [[pv alloc] init];
    BPX_SetObj1(v, "setSourceView:", content);
    return v;
}

// -[SBFullScreenSwitcherLiveContentOverlayCoordinator _updatePortaledSceneLiveContentOverlays]  16.2 0x1c74ce070
static void Y6_UpdatePortaled(id self, SEL _cmd) {
    if (!BP_OnName("y6_portal")) return;
    id sc = Y6_Controller(self);
    if (!sc) return;
    id coord = BPX_Obj0(sc, "switcherCoordinator");
    Class fvc = NSClassFromString(@"SBFluidSwitcherViewController");
    id vc = BPX_Obj0(sc, "contentViewController");
    if (!fvc || ![vc isKindOfClass:fvc]) vc = nil;
    id event = BPX_Obj0(BPX_Obj0(BPX_Obj0(vc, "layoutContext"), "activeGesture"), "gestureEvent");
    id selected = BPX_Obj0(event, "selectedAppLayout");
    long long ordinal = selected ? BPX_LL0(selected, "preferredDisplayOrdinal") : 0;
    __block id source = nil;
    if (coord) {
        void (^find)(id, BOOL *) = ^(id c, BOOL *stop) {
            if (BPX_LL0(BPX_Obj0(c, "layoutState"), "displayOrdinal") == ordinal) { source = c; if (stop) *stop = YES; }
        };
        BPY_SEND(void, (id), coord, "enumerateSwitcherControllersWithBlock:", find);
    }
    id converted = nil;
    if (event && BPX_Bool0(event, "isContinuousExposeWindowDragEvent") && source && source != sc) {
        converted = BPY_SEND(id, (id, id, id), coord, "convertAppLayout:fromSwitcherController:toSwitcherController:", selected, source, sc);
        long long existing = converted ? BPY_SEND(long long, (id), self, "_existingOverlayTypeForAppLayout:", converted) : 1;
        if (converted && existing != 1 && existing != 4) {
            id item = BPY_SEND(id, (long long), converted, "itemForLayoutRole:", 1LL);
            id sceneManager = BPX_Obj0(BPX_Obj0(source, "windowScene"), "sceneManager");
            id identity = item ? BPY_SEND(id, (id), (id)NSClassFromString(@"FBSSceneIdentity"), "identityForIdentifier:", BPX_Obj0(item, "uniqueIdentifier")) : nil;
            id handle = identity ? BPX_Obj1(sceneManager, "existingSceneHandleForSceneIdentity:", identity) : nil;
            Class hc = NSClassFromString(@"SBDeviceApplicationSceneHandle");
            if (!hc || ![handle isKindOfClass:hc]) handle = nil;
            id srcOverlay = BPX_Obj1(BPX_Obj0(source, "contentViewController"), "liveContentOverlayForAppLayout:", selected);
            id portal = nil;
            if (BPY_Responds(srcOverlay, "newPortaledLiveContentOverlayView")) {
                portal = [srcOverlay newPortaledLiveContentOverlayView];
                Class pl = NSClassFromString(@"CAPortalLayer");
                id layer = BPX_Obj0(portal, "layer");
                if (pl && [layer isKindOfClass:pl]) BPX_SetBool1(layer, "setCrossDisplay:", YES);
            }
            if (handle && srcOverlay && portal) {
                if (existing != 0) BPY_SEND(void, (id, BOOL), self, "_removeOverlayForAppLayout:animated:", converted, NO);
                Y6Rect f = ((Y6Rect (*)(id, SEL))objc_msgSend)(BPX_Obj0(srcOverlay, "contentOverlayView"), sel_registerName("frame"));
                id layoutState = BPX_Obj0(sc, "layoutState");
                long long contentOri = BPY_Responds(layoutState, "interfaceOrientationForElementIdentifier:") ? BPY_SEND(long long, (id), layoutState, "interfaceOrientationForElementIdentifier:", BPX_Obj0(handle, "sceneIdentifier")) : BPX_LL0(layoutState, "interfaceOrientation");
                long long containerOri = BPX_LL0(layoutState, "interfaceOrientation");
                BOOL inset = BPX_Bool0(converted, "isInsetForHomeAffordance");
                Class oc = NSClassFromString(@"SBFluidSwitcherPortaledSceneLiveContentOverlay");
                if (oc) {
                    id overlay = ((id (*)(id, SEL, id, Y6Size, long long, long long, id, BOOL))objc_msgSend)([oc alloc], sel_registerName("initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:livePortalView:isInsetForHomeAffordance:"),
                                                                                                           handle, (Y6Size){ f.w, f.h }, contentOri, containerOri, portal, inset);
                    if (overlay) {
                        BPY_SEND(void, (id, id, BOOL), self, "_addOverlay:forAppLayout:animated:", overlay, converted, NO);
                        BPY_LOG(@"[y6] portaled overlay %p for the layout dragged from the display of %p", (__bridge void *)overlay, (__bridge void *)source);
                    }
                }
            }
        }
    }
    id keep = converted;
    id contexts = BPX_IvarObj(self, "_appLayoutToLiveContentOverlayContext");
    NSDictionary *snap = [contexts copy];
    [snap enumerateKeysAndObjectsUsingBlock:^(id key, id ctx, BOOL *stop) {
        if (BPX_LL0(ctx, "overlayType") == 4 && (!keep || ![key isEqual:keep])) {
            BPY_SEND(void, (id, BOOL), self, "_removeOverlayForAppLayout:animated:", key, NO);
            BPY_LOG(@"[y6] portaled overlay for %p removed", (__bridge void *)key);
        }
    }];
}

// the four callers: after the saved body, the 16.2 call that follows -_updateAlwaysLiveSceneContentOverlays
static void Y6_Begin(id self, SEL _cmd, id coordinator, id ctx) {
    if (gY6Begin) ((void (*)(id, SEL, id, id))gY6Begin)(self, _cmd, coordinator, ctx);
    if (!Y6_Suspended(self)) Y6_UpdatePortaled(self, NULL);
}
static void Y6_End(id self, SEL _cmd, id coordinator, id ctx) {
    if (gY6End) ((void (*)(id, SEL, id, id))gY6End)(self, _cmd, coordinator, ctx);
    if (!Y6_Suspended(self)) Y6_UpdatePortaled(self, NULL);
}
static void Y6_Visible(id self, SEL _cmd, id layout) {
    if (gY6Visible) ((void (*)(id, SEL, id))gY6Visible)(self, _cmd, layout);
    Y6_UpdatePortaled(self, NULL);
}
static void Y6_Hidden(id self, SEL _cmd, id layout) {
    if (gY6Hidden) ((void (*)(id, SEL, id))gY6Hidden)(self, _cmd, layout);
    Y6_UpdatePortaled(self, NULL);
}

// -[SBFullScreenSwitcherLiveContentOverlayCoordinator _removeOverlayForAppLayout:animated:]  16.2 0x1c74cdbd8 (16.0 0x1c6051704): type 4 like 1 and 2
static void Y6_Remove(id self, SEL _cmd, id layout, BOOL animated) {
    if (!BP_OnName("y6_portal")) {
        if (gY6Remove) ((void (*)(id, SEL, id, BOOL))gY6Remove)(self, _cmd, layout, animated);
        return;
    }
    id contexts = BPX_IvarObj(self, "_appLayoutToLiveContentOverlayContext");
    id ctx = [contexts objectForKey:layout];
    if (ctx) {
        long long type = BPX_LL0(ctx, "overlayType");
        id overlay = BPX_Obj0(ctx, "overlay");
        if (type == 3) {
            BPY_SEND(void, (), overlay, "invalidate");
        } else if (type == 2 || type == 1 || type == 4) {
            id vc = BPX_Obj0(overlay, "contentViewController");
            if (vc) {
                BPX_SetObj1(vc, "willMoveToParentViewController:", nil);
                BPY_SEND(void, (BOOL, BOOL), vc, "bs_beginAppearanceTransition:animated:", NO, NO);
                BPY_SEND(void, (), vc, "removeFromParentViewController");
                BPY_SEND(void, (), vc, "bs_endAppearanceTransition");
            }
            BPY_SEND(void, (), overlay, "invalidate");
        }
    }
    [contexts removeObjectForKey:layout];
    id delegate = BPX_Obj0(self, "delegate");
    BPY_SEND(void, (id, BOOL), delegate, "removeLiveContentOverlayForAppLayout:animated:", layout, animated);
}

// -[SBFullScreenSwitcherLiveContentOverlayCoordinator _updateAlwaysLiveSceneContentOverlays]
static void Y6_AlwaysUpdate(id self, SEL _cmd) {
    void *prev = tY6AlwaysScene;
    id scene = BP_OnName("y6_alwayslive") ? BPX_Obj0(self, "_sbWindowScene") : nil;
    tY6AlwaysScene = scene ? (__bridge void *)scene : NULL;
    if (gY6AlwaysUpdate) ((void (*)(id, SEL))gY6AlwaysUpdate)(self, _cmd);
    tY6AlwaysScene = prev;
}
// -[SBFullScreenAlwaysLiveLiveContentOverlay initWithSceneHandle:referenceSize:containerOrientation:]
static id Y6_AlwaysInit(id self, SEL _cmd, id handle, Y6Size size, long long orientation) {
    void *p = tY6AlwaysScene;
    if (p) {
        id screen = BPX_Obj0((__bridge id)p, "screen");
        if (screen && BPY_Responds(screen, "_referenceBounds")) {
            Y6Rect b = ((Y6Rect (*)(id, SEL))objc_msgSend)(screen, sel_registerName("_referenceBounds"));
            if (b.w > 0 && b.h > 0) size = (Y6Size){ b.w, b.h };
        }
    }
    return gY6AlwaysInit ? ((id (*)(id, SEL, id, Y6Size, long long))gY6AlwaysInit)(self, _cmd, handle, size, orientation) : nil;
}

__attribute__((constructor)) static void Y6_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class co = NSClassFromString(@"SBFullScreenSwitcherLiveContentOverlayCoordinator"), ov = NSClassFromString(@"SBFullScreenSwitcherSceneLiveContentOverlay"), vc = NSClassFromString(@"SBFluidSwitcherViewController");
        if (!co || !ov || !vc || !NSClassFromString(@"SBFluidSwitcherPortaledSceneLiveContentOverlay") || !NSClassFromString(@"SBPortalView") ||
            !class_getInstanceMethod(co, sel_registerName("_addOverlay:forAppLayout:animated:")) || !class_getInstanceMethod(co, sel_registerName("_existingOverlayTypeForAppLayout:")) ||
            !class_getInstanceMethod(co, sel_registerName("_removeOverlayForAppLayout:animated:")) || !class_getInstanceMethod(co, sel_registerName("_updateAlwaysLiveSceneContentOverlays"))) {
            BP_Log(@"[y6] NOT installed (class or selector missing)");
            return;
        }
        if (!class_getInstanceMethod(vc, sel_registerName("liveContentOverlayForAppLayout:"))) class_addMethod(vc, sel_registerName("liveContentOverlayForAppLayout:"), (IMP)Y6_VCOverlayFor, "@24@0:8@16");
        if (!class_getInstanceMethod(ov, sel_registerName("newPortaledLiveContentOverlayView"))) class_addMethod(ov, sel_registerName("newPortaledLiveContentOverlayView"), (IMP)Y6_NewPortal, "@16@0:8");
        if (!class_getInstanceMethod(co, sel_registerName("_updatePortaledSceneLiveContentOverlays"))) class_addMethod(co, sel_registerName("_updatePortaledSceneLiveContentOverlays"), (IMP)Y6_UpdatePortaled, "v16@0:8");
        gY6Begin = BPX_Replace(co, "layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:", (IMP)Y6_Begin);
        gY6End = BPX_Replace(co, "layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:", (IMP)Y6_End);
        gY6Visible = BPX_Replace(co, "appLayoutWillBecomeVisible:", (IMP)Y6_Visible);
        gY6Hidden = BPX_Replace(co, "appLayoutDidBecomeHidden:", (IMP)Y6_Hidden);
        gY6Remove = BPX_Replace(co, "_removeOverlayForAppLayout:animated:", (IMP)Y6_Remove);
        Class al = NSClassFromString(@"SBFullScreenAlwaysLiveLiveContentOverlay");
        if (al && class_getInstanceMethod(al, sel_registerName("initWithSceneHandle:referenceSize:containerOrientation:"))) {
            gY6AlwaysUpdate = BPX_Replace(co, "_updateAlwaysLiveSceneContentOverlays", (IMP)Y6_AlwaysUpdate);
            gY6AlwaysInit = BPX_Replace(al, "initWithSceneHandle:referenceSize:containerOrientation:", (IMP)Y6_AlwaysInit);
        }
        BP_Log(@"[y6] installed (switches y6_portal, y6_alwayslive): portaled live content overlay for the cross display window drag, always-live overlay size per display");
    }
}
#pragma clang diagnostic pop
