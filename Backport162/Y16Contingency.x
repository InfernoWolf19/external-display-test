// Y16Contingency.x : delta sweep family F4 (specs/DELTA-SWEEP-0.7.9.md): the fallback transition of a failed / exited application entity keeps the other Stage Manager windows.
// Setup: constructor.  Log prefix "[y16]".  Switches y16_stagefail, y16_cmdtab, y16_shotcorner, y16_snaporient, y16_platter, y16_overlaykb, y16_overlaydismiss.
//
//  -[SBMainWorkspaceLayoutStateContingencyPlan transitionContextForLayoutContext:failedEntities:]  16.2 0x1c7904c94 (16.0 0x1c6450ce8) is asked for the transition that replaces entities that failed (launch
//  failure, crash) or exited (Y1Workspace.x Y1_Select asks it for an exited window).  With the layout state NOT in the switcher mode (unlockedEnvironmentMode != 2, i.e. apps / Stage Manager) 16.0 sends
//  the display HOME: the primary role becomes the Home Screen entity and every other role is cleared, so one window of a Stage Manager stage that crashes closed the whole stage.  16.2 for a display whose
//  switcher controller has the windowing UI (-isChamoisWindowingUIEnabled):  setEntities:(every layout element's workspace entity whose unique identifier is not one of the failed entities)
//  withPolicy:0 centerEntity:Previous floatingEntity:Previous, then the removal context of the failed entities (below), then returns.  16.2 also takes the display's windowing mode into account
//  (sb_displayWindowingMode == 1, instead of 16.0 "main root display" only) so a windowed extended display is handled like the iPad.
//  Ported: the Stage Manager branch above, for the iPad and for a display with sb_displayWindowingMode == 1; the remaining entities are ordered by their layout role (16.2 passes -allObjects of a set,
//  unspecified order) so the frontmost / primary window keeps its role.  Removal context (16.0 and 16.2): failedLaunchCount >= 2 -> SBWorkspaceEntityRemovalContext(animationStyle 0, removalActionType 1).
//  Not ported (documented, NOT PORTED in the sweep): the 16.2 switcher-mode (unlockedEnvironmentMode == 2) flow for a windowed extended display (16.0 sends that display Home: no visible difference, there
//  is no stage to keep), the privacy preflight leg of the removal rule (G3B: no preflight exists in 16.0), the floating-switcher tail (Slide Over is not part of this port).
//
//  y16_cmdtab      -[SBCommandTabController init] 16.2 0x1c75731a8 / dealloc 0x1c75734cc (16.0 0x1c60ee7e8 / 0x1c60eead4) add and remove a notification observer for the new -_sceneDidDisconnect: (16.2 0x1c757481c):
//                  when the scene that disconnected is the window scene of the Command-Tab window ([[self _window] _sbWindowScene]), log and -dismiss.  16.0 leaves the Command-Tab overlay of an unplugged
//                  monitor up.  Ported with UISceneDidDisconnectNotification (the 16.2 name is read through a pointer that cannot be resolved here; the handler compares the notification's object with a
//                  window scene, which only the UIKit scene notification carries: UNSURE, the observer is harmless when the name differs).
//
//  y16_shotcorner  -[SBInteractiveScreenshotGestureManager gestureRecognizerShouldBegin:] 16.2 0x1c77934fc (16.0 0x1c62f621c): for an SBCornerFingerPanGestureRecognizer the touch-type mask that
//                  is matched against the bottom corner gesture settings is `!chamoisWindowingEnabled` (16.0: always 1).  With Stage Manager on a FINGER swipe from a bottom corner therefore never starts
//                  the corner (screenshot / quick note) gesture, the corner belongs to the window resize handle; 16.0 let the two gestures compete.  Ported: the finger recognizer answers NO while
//                  -[[[SBDefaults localDefaults] appSwitcherDefaults] chamoisWindowingEnabled] is on (Apple Pencil corner swipes are unchanged).
//
//  y16_snaporient  -[SBAppSwitcherReusableSnapshotView _contentOrientationForSnapshotCacheEntry:] 16.2 0x1c7921eec (16.0 0x1c646c7f0): for a scene that supports mixed orientation 16.0 always answers the
//                  view's orientation.  16.2, when the view was created for a windowing-UI switcher (init: [[containerVC _sbWindowScene] switcherController].isChamoisWindowingUIEnabled, ivar
//                  _isChamoisWindowingEnabled), looks at the item's layout attribute contentOrientation (the window's own orientation under Stage Manager): when it is neither the view's orientation
//                  nor the snapshot's, the snapshot's (flipped-if-opposite) orientation is kept.  Ported with the flag read from the container view controller at call time.
//
//  y16_platter     -[SBDragAndDropWorkspaceTransaction _platterSizeForDropAction:proposedDropLayoutState:setDown:] 16.2 0x1c770aea8 (16.0 0x1c6272d10): with the windowing UI the drag platter of a drop action
//                  1..5 has the size of the item in the PROPOSED layout ([[[self windowScene] switcherController] frameForItemWithRole:1 inMainAppLayout:[state appLayout] interfaceOrientation:...]
//                  size); 16.0 sized actions 1, 4 and 5 from a generic full screen layout and gave 0 for 2 and 3.  Scaled by -_platterScale unless set down, like both builds.
//                  Ported as a wrapper that answers for the windowing UI and actions 1..5 when the proposed layout gives a non empty frame, the 16.0 body otherwise.
//
//  y16_overlaykb   -[SBMainWorkspace isKeyboardVisibleForSpringBoardForTransientOverlayScenePresenter:] 16.2 0x1c73808a4 (16.0 0x1c5f0c1dc): 16.0 asks the MAIN display scene manager, 16.2 the hosted keyboard
//                  controller of the presenter's window scene.  Ported with -[SBWindowScene medusaHostedKeyboardWindowController] (G3B.x, kbmedusa) for a presenter of another display.
//  y16_overlaydismiss  -[SBMainWorkspace transientOverlayScenePresenter:didDismissViewController:wasTopmostPresentation:] 16.2 0x1c73811ac (16.0 0x1c5f0cad0): the primary element it tests after the
//                  dismissal (idle timer / clock reset when an app is in front) is the one of the presenter's switcher controller, 16.0 reads the coordinator's ACTIVE controller.  Ported: Y3_PushActive
//                  of the presenter scene's switcher controller around the 16.0 body.
// Needs a device: make an app crash (or kill its process from a debugger) while two or more windows are on the stage of the iPad or of the monitor: only that window disappears, the others stay.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y16Rect;      // CGRect (HFA, d0..d3)
typedef struct { double w, h; } Y16Size;        // CGSize (HFA, d0..d1)
static IMP gY16Orig, gY16CtInit, gY16CtDealloc, gY16Shot, gY16Snap, gY16Platter, gY16OvKb, gY16OvDis;

static BOOL Y16_Windowed(id ident) {
    if (!ident) return NO;
    if (BPX_Bool0(ident, "isMainRootDisplay")) return YES;
    return BPY_Responds(ident, "sb_displayWindowingMode") && BPX_LL0(ident, "sb_displayWindowingMode") == 1;
}

// -[SBMainWorkspaceLayoutStateContingencyPlan transitionContextForLayoutContext:failedEntities:]
static id Y16_Plan(id self, SEL _cmd, id layoutContext, id failed) {
    id (*call)(id, SEL, id, id) = (id (*)(id, SEL, id, id))gY16Orig;
    if (!BP_OnName("y16_stagefail") || !layoutContext || ![failed isKindOfClass:[NSSet class]]) return call ? call(self, _cmd, layoutContext, failed) : nil;
    id state = BPX_Obj0(layoutContext, "layoutState");
    id ident = BPX_Obj0(layoutContext, "displayIdentity");
    NSMutableSet *ids = [NSMutableSet set];
    BOOL any = NO;
    for (id e in (NSSet *)failed) {
        id uid = BPX_Obj0(e, "uniqueIdentifier");
        if (uid) [ids addObject:uid];
        if (uid && BPX_Obj1(state, "elementWithIdentifier:", uid)) any = YES;
    }
    id scene = BPY_SceneForIdentity(ident);
    id ctl = BPX_Obj0(scene, "switcherController");
    Class ctxC = NSClassFromString(@"SBWorkspaceApplicationSceneTransitionContext"), prevC = NSClassFromString(@"SBPreviousWorkspaceEntity");
    BOOL ok = any && Y16_Windowed(ident) && state && BPX_LL0(state, "unlockedEnvironmentMode") != 2 && BPX_Bool0(ctl, "isChamoisWindowingUIEnabled") && ctxC && prevC &&
              [ctxC instancesRespondToSelector:sel_registerName("setEntities:withPolicy:centerEntity:floatingEntity:")];
    if (!ok) return call ? call(self, _cmd, layoutContext, failed) : nil;
    id ctx = BPX_Obj0((id)ctxC, "context");
    if (!ctx) return call ? call(self, _cmd, layoutContext, failed) : nil;
    BPX_SetBool1(ctx, "setAnimationDisabled:", YES);
    NSMutableArray *keep = [NSMutableArray array];
    for (id el in [BPX_Obj0(state, "elements") allObjects]) {
        id ent = BPX_Obj0(el, "workspaceEntity");
        id uid = BPX_Obj0(ent, "uniqueIdentifier");
        if (ent && !(uid && [ids containsObject:uid])) [keep addObject:el];
    }
    [keep sortUsingComparator:^NSComparisonResult(id a, id b) {
        long long x = BPX_LL0(a, "layoutRole"), y = BPX_LL0(b, "layoutRole");
        return x == y ? NSOrderedSame : (x < y ? NSOrderedAscending : NSOrderedDescending);
    }];
    NSMutableArray *ents = [NSMutableArray array];
    for (id el in keep) [ents addObject:BPX_Obj0(el, "workspaceEntity")];
    id prev = BPX_Obj0((id)prevC, "entity");
    BPY_SEND(void, (id, long long, id, id), ctx, "setEntities:withPolicy:centerEntity:floatingEntity:", ents, 0LL, prev, prev);
    Class rc = NSClassFromString(@"SBWorkspaceEntityRemovalContext");
    SEL ini = sel_registerName("initWithAnimationStyle:removalActionType:");
    for (id e in (NSSet *)failed) {
        if (!BPX_Bool0(e, "isApplicationSceneEntity")) continue;
        if (BPX_LL0(BPX_Obj0(e, "application"), "failedLaunchCount") < 2 || !rc || ![rc instancesRespondToSelector:ini]) continue;
        id rem = BPY_SEND(id, (long long, long long), [rc alloc], "initWithAnimationStyle:removalActionType:", 0LL, 1LL);
        BPY_SEND(void, (id, id), ctx, "setRemovalContext:forEntity:", rem, e);
    }
    BPY_LOG(@"[y16] failed entities %@ on display %@: fallback keeps %lu other window(s) (%@)", ids, ident, (unsigned long)ents.count, ents);
    return ctx;
}

// 16.2 -[SBCommandTabController _sceneDidDisconnect:]
static void Y16_CtDisc(id self, SEL _cmd, id note) {
    if (!BP_OnName("y16_cmdtab")) return;
    id scene = BPX_Obj0(BPX_Obj0(self, "window"), "_sbWindowScene");
    if (!scene || [note object] != scene) return;
    BPY_LOG(@"[y16] command tab: its window scene %@ disconnected, dismissing", scene);
    BPY_SEND(void, (), self, "dismiss");
}
static id Y16_CtInit(id self, SEL _cmd) {
    id r = gY16CtInit ? ((id (*)(id, SEL))gY16CtInit)(self, _cmd) : self;
    if (r && BP_OnName("y16_cmdtab")) [[NSNotificationCenter defaultCenter] addObserver:r selector:sel_registerName("_sceneDidDisconnect:") name:@"UISceneDidDisconnectNotification" object:nil];
    return r;
}
static void Y16_CtDealloc(id self, SEL _cmd) {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (gY16CtDealloc) ((void (*)(id, SEL))gY16CtDealloc)(self, _cmd);
}

// -[SBInteractiveScreenshotGestureManager gestureRecognizerShouldBegin:]
static BOOL Y16_Shot(id self, SEL _cmd, id gr) {
    BOOL r = gY16Shot ? ((BOOL (*)(id, SEL, id))gY16Shot)(self, _cmd, gr) : NO;
    if (!r || !BP_OnName("y16_shotcorner")) return r;
    Class fc = NSClassFromString(@"SBCornerFingerPanGestureRecognizer"), dc = NSClassFromString(@"SBDefaults");
    if (!fc || ![gr isKindOfClass:fc]) return r;
    id defs = BPX_Obj0(BPX_Obj0((id)dc, "localDefaults"), "appSwitcherDefaults");
    if (!BPX_Bool0(defs, "chamoisWindowingEnabled")) return r;
    BPY_LOG(@"[y16] finger corner swipe %@ does not start the corner gesture under Stage Manager (the corner is the resize handle)", gr);
    return NO;
}

static long long Y16_Opposite(long long o) { return o == 1 ? 2 : (o == 2 ? 1 : (o == 3 ? 4 : (o == 4 ? 3 : o))); }
// -[SBAppSwitcherReusableSnapshotView _contentOrientationForSnapshotCacheEntry:]
static long long Y16_SnapOrient(id self, SEL _cmd, id entry) {
    long long base = gY16Snap ? ((long long (*)(id, SEL, id))gY16Snap)(self, _cmd, entry) : 0;
    if (!BP_OnName("y16_snaporient") || !entry) return base;
    long long role = BPX_LL0(entry, "role");
    id handle = BPY_SEND(id, (long long), self, "_sceneHandleForRole:", role);
    if (!BPX_Bool0(handle, "_supportsMixedOrientation")) return base;
    long long snap = BPX_LL0(BPX_Obj0(entry, "snapshot"), "interfaceOrientation"), view = BPX_LL0(self, "orientation");
    long long r = (view == Y16_Opposite(snap)) ? view : snap;
    id cvc = BPX_IvarObj(self, "_containerViewController");
    id ctl = BPX_Obj0(BPX_Obj0(cvc, "_sbWindowScene"), "switcherController");
    if (!BPX_Bool0(ctl, "isChamoisWindowingUIEnabled")) return view;
    id layout = BPX_Obj0(entry, "appLayout");
    if (!BPY_Responds(layout, "layoutAttributesForItemInRole:")) return view;
    id attrs = BPY_SEND(id, (long long), layout, "layoutAttributesForItemInRole:", role);
    long long co = BPX_LL0(attrs, "contentOrientation");
    return (co != view && co != snap) ? r : view;
}

// -[SBDragAndDropWorkspaceTransaction _platterSizeForDropAction:proposedDropLayoutState:setDown:]
static Y16Size Y16_Platter(id self, SEL _cmd, long long action, id state, BOOL setDown) {
    Y16Size fallback = {0, 0};
    if (BP_OnName("y16_platter") && state && action >= 1 && action <= 5) {
        id ctl = BPX_Obj0(BPX_Obj0(self, "windowScene"), "switcherController");
        id layout = BPX_Obj0(state, "appLayout");
        if (layout && BPX_Bool0(ctl, "isChamoisWindowingUIEnabled") && BPY_Responds(ctl, "frameForItemWithRole:inMainAppLayout:interfaceOrientation:")) {
            Y16Rect f = BPY_SEND(Y16Rect, (long long, id, long long), ctl, "frameForItemWithRole:inMainAppLayout:interfaceOrientation:", 1LL, layout, BPX_LL0(state, "interfaceOrientation"));
            if (f.w > 0 && f.h > 0) {
                Y16Size r = {f.w, f.h};
                if (!setDown) {
                    double sc = BPY_Responds(self, "_platterScale") ? BPY_SEND(double, (), self, "_platterScale") : 1.0;
                    r.w *= sc; r.h *= sc;
                }
                BPY_LOG(@"[y16] drag platter for action %lld: %.0f x %.0f (item size in the proposed layout)", action, r.w, r.h);
                return r;
            }
        }
    }
    return gY16Platter ? ((Y16Size (*)(id, SEL, long long, id, BOOL))gY16Platter)(self, _cmd, action, state, setDown) : fallback;
}

// -[SBMainWorkspace isKeyboardVisibleForSpringBoardForTransientOverlayScenePresenter:]
static BOOL Y16_OvKb(id self, SEL _cmd, id presenter) {
    if (BP_OnName("y16_overlaykb")) {
        id scene = BPX_Obj0(presenter, "windowScene");
        if (scene && !BPX_Bool0(scene, "isMainDisplayWindowScene") && BPY_Responds(scene, "medusaHostedKeyboardWindowController")) {
            id kb = BPX_Obj0(scene, "medusaHostedKeyboardWindowController");
            if (kb && BPY_Responds(kb, "isKeyboardVisibleForSpringBoard")) return BPX_Bool0(kb, "isKeyboardVisibleForSpringBoard");
        }
    }
    return gY16OvKb ? ((BOOL (*)(id, SEL, id))gY16OvKb)(self, _cmd, presenter) : NO;
}
// -[SBMainWorkspace transientOverlayScenePresenter:didDismissViewController:wasTopmostPresentation:]
static void Y16_OvDis(id self, SEL _cmd, id presenter, id vc, BOOL top) {
    id ctl = BP_OnName("y16_overlaydismiss") ? BPX_Obj0(BPX_Obj0(presenter, "windowScene"), "switcherController") : nil;
    void *prev = ctl ? Y3_PushActive(ctl) : NULL;
    if (gY16OvDis) ((void (*)(id, SEL, id, id, BOOL))gY16OvDis)(self, _cmd, presenter, vc, top);
    if (ctl) Y3_PopActive(prev);
}

__attribute__((constructor)) static void Y16_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBMainWorkspaceLayoutStateContingencyPlan");
        if (c && class_getInstanceMethod(c, sel_registerName("transitionContextForLayoutContext:failedEntities:")))
            gY16Orig = BPX_Replace(c, "transitionContextForLayoutContext:failedEntities:", (IMP)Y16_Plan);
        Class ct = NSClassFromString(@"SBCommandTabController");
        if (ct && class_getInstanceMethod(ct, sel_registerName("init")) && class_getInstanceMethod(ct, sel_registerName("dismiss")) && class_getInstanceMethod(ct, sel_registerName("window"))) {
            class_addMethod(ct, sel_registerName("_sceneDidDisconnect:"), (IMP)Y16_CtDisc, "v24@0:8@16");
            gY16CtInit = BPX_Replace(ct, "init", (IMP)Y16_CtInit);
            gY16CtDealloc = BPX_Replace(ct, "dealloc", (IMP)Y16_CtDealloc);
        }
        Class sg = NSClassFromString(@"SBInteractiveScreenshotGestureManager");
        if (sg && class_getInstanceMethod(sg, sel_registerName("gestureRecognizerShouldBegin:"))) gY16Shot = BPX_Replace(sg, "gestureRecognizerShouldBegin:", (IMP)Y16_Shot);
        Class sv = NSClassFromString(@"SBAppSwitcherReusableSnapshotView");
        if (sv && class_getInstanceMethod(sv, sel_registerName("_contentOrientationForSnapshotCacheEntry:"))) gY16Snap = BPX_Replace(sv, "_contentOrientationForSnapshotCacheEntry:", (IMP)Y16_SnapOrient);
        Class dd = NSClassFromString(@"SBDragAndDropWorkspaceTransaction");
        if (dd && class_getInstanceMethod(dd, sel_registerName("_platterSizeForDropAction:proposedDropLayoutState:setDown:"))) gY16Platter = BPX_Replace(dd, "_platterSizeForDropAction:proposedDropLayoutState:setDown:", (IMP)Y16_Platter);
        Class mw = NSClassFromString(@"SBMainWorkspace");
        if (mw && class_getInstanceMethod(mw, sel_registerName("isKeyboardVisibleForSpringBoardForTransientOverlayScenePresenter:"))) gY16OvKb = BPX_Replace(mw, "isKeyboardVisibleForSpringBoardForTransientOverlayScenePresenter:", (IMP)Y16_OvKb);
        if (mw && class_getInstanceMethod(mw, sel_registerName("transientOverlayScenePresenter:didDismissViewController:wasTopmostPresentation:"))) gY16OvDis = BPX_Replace(mw, "transientOverlayScenePresenter:didDismissViewController:wasTopmostPresentation:", (IMP)Y16_OvDis);
        BP_Log(@"[y16] contingency plan hook %s (switches y16_stagefail, y16_cmdtab, y16_shotcorner, y16_snaporient, y16_platter, y16_overlaykb, y16_overlaydismiss)", gY16Orig ? "installed" : "NOT installed");
    }
}
#pragma clang diagnostic pop
