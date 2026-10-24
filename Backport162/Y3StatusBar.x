// Y3StatusBar.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): coordinator state per window scene, status bar container hide.  Setup: constructor.  Log prefix "[y3]".
//
// 1. The coordinator's per window scene queries read the ACTIVE display's controller in 16.0: -[SBMainSwitcherControllerCoordinator _currentLayoutState / _currentAppLayout /
//    _currentFloatingAppLayout] forward to -_activeDisplaySwitcherController (16.0 0x1c6245340 / 0x1c624525c / 0x1c62452a8, all `[self _activeDisplaySwitcherController]` + the
//    controller method).  16.2 asks [self switcherControllerForWindowScene:scene] in the methods that already take the scene (status bar insets / style / overlay data / actions
//    / in-app hidden / avoidance frame 0x1c76ceb90 .. 0x1c76cf444, focused icon shortcut action 0x1c76cdb38, neighbouring app layout 0x1c76ce4xx).  With a window on the second
//    display the status bar of display B was built from display A's layout whenever A was the active display.
//      y3_scenectl   those ten methods run with -_activeDisplaySwitcherController answering the controller of the scene they were given (thread local, restored on return).
// 2. -statusBarAvoidanceFrameForLayoutRole:layoutState:windowScene: 16.2 0x1c76ceca8 (16.0 0x1c623b6fc): with Stage Manager on, the item frame is asked for the layout
//    state's own interface orientation instead of -interfaceOrientationForLayoutRole: (the only change of the body).
//      y3_avoidorient  while the call runs, -[SBMainDisplayLayoutState interfaceOrientationForLayoutRole:] answers -interfaceOrientation for THAT layout state (thread local).
// 3. -_setContainerStatusBarHidden:animationDuration:usingAssertion:reason:windowScene: 16.2 0x1c76d6164 (block 0x1c76d6358; 16.0 0x1c6242754 used UIView animation and always
//    took a level 6 assertion when hiding): the assertion is only held while -_shouldTakeStatusBarAssertionForSwitcherController: (16.2 0x1c76d6120, new:
//    (unlockedEnvironmentMode & ~1) == 2 of the controller's layout state) says so, the hide / show is a status bar settings change (alpha 0 / 1) with
//    UIStatusBarStyleAnimationParameters (duration = the requested one) through the assertion (modifySettingsWithBlock:animationParameters: / acquireWithAnimationParameters: /
//    invalidateWithAnimationParameters:), and the assertion manager is the one of the scene's statusBarManager.
//      y3_containersb  the 16.2 body, new method added.
// Needs a device: with Stage Manager on both displays hide the status bar in an app on the monitor (full screen video, status bar hidden app): the bar of the OTHER display
// keeps its state; go to the home screen: the hidden-bar request no longer holds an assertion there.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

@interface NSObject (Y3Decl)       // declarations only (ARC needs the method families: new... / init... return +1)
- (id)newSettingsAssertionWithStatusBarHidden:(BOOL)hidden atLevel:(unsigned long long)level reason:(id)reason;
- (id)initWithDefaultParameters;
- (void)setDuration:(double)duration;
- (void)modifySettingsWithBlock:(id)block animationParameters:(id)parameters;
- (void)acquireWithAnimationParameters:(id)parameters;
- (void)invalidateWithAnimationParameters:(id)parameters;
@end

typedef struct { double a, b, c, d; } Y3Quad;       // CGRect / UIEdgeInsets: four doubles, returned in d0..d3 like the originals

static __thread void *tY3Active;        // unretained: the controller -_activeDisplaySwitcherController answers while a wrapped call runs
static __thread void *tY3Layout;        // unretained: the layout state whose interfaceOrientationForLayoutRole: answers interfaceOrientation
static IMP gY3OrigActive, gY3OrigRoleOrient;
static IMP gY3OrigInApp, gY3OrigAvoid1, gY3OrigAvoid2, gY3OrigInsets, gY3OrigLead, gY3OrigTrail, gY3OrigOverlay, gY3OrigActions, gY3OrigShortcut, gY3OrigNeighbor, gY3OrigContainer;

// -[SBMainSwitcherControllerCoordinator _activeDisplaySwitcherController]
static id Y3_Active(id self, SEL _cmd) {
    void *p = tY3Active;
    if (p) return (__bridge id)p;
    return gY3OrigActive ? ((id (*)(id, SEL))gY3OrigActive)(self, _cmd) : nil;
}
// the controller of a window scene when the override should apply (nil = run unchanged)
static id Y3_CtlFor(id coord, id scene) {
    if (!BP_OnName("y3_scenectl") || !scene) return nil;
    id ctl = BPX_Obj1(coord, "switcherControllerForWindowScene:", scene);
    if (BP_LogEnabled() && ctl && ctl != BPX_Obj0(coord, "_activeDisplaySwitcherController"))
        BPY_LOG(@"[y3] %@ for the scene %p runs with its own controller %p (the active display's differs)", @"coordinator query", (__bridge void *)scene, (__bridge void *)ctl);
    return ctl;
}
#define Y3_BEGIN(SCENE) \
    id y3ctl = Y3_CtlFor(self, (SCENE)); \
    void *y3prev = tY3Active; \
    if (y3ctl) tY3Active = (__bridge void *)y3ctl;
#define Y3_END tY3Active = y3prev;

static BOOL Y3_InApp(id self, SEL _cmd, id scene) {
    Y3_BEGIN(scene)
    BOOL r = gY3OrigInApp ? ((BOOL (*)(id, SEL, id))gY3OrigInApp)(self, _cmd, scene) : NO;
    Y3_END
    return r;
}
static Y3Quad Y3_Avoid1(id self, SEL _cmd, long long role, id scene) {
    Y3_BEGIN(scene)
    Y3Quad r = {0, 0, 0, 0};
    if (gY3OrigAvoid1) r = ((Y3Quad (*)(id, SEL, long long, id))gY3OrigAvoid1)(self, _cmd, role, scene);
    Y3_END
    return r;
}
static Y3Quad Y3_Avoid2(id self, SEL _cmd, long long role, id state, id scene) {
    Y3_BEGIN(scene)
    void *prevLayout = tY3Layout;
    if (state && BP_OnName("y3_avoidorient") && BPX_Bool0(BPX_Obj1(self, "switcherControllerForWindowScene:", scene), "isChamoisWindowingUIEnabled")) tY3Layout = (__bridge void *)state;
    Y3Quad r = {0, 0, 0, 0};
    if (gY3OrigAvoid2) r = ((Y3Quad (*)(id, SEL, long long, id, id))gY3OrigAvoid2)(self, _cmd, role, state, scene);
    tY3Layout = prevLayout;
    Y3_END
    return r;
}
static Y3Quad Y3_Insets(id self, SEL _cmd, id scene) {
    Y3_BEGIN(scene)
    Y3Quad r = {0, 0, 0, 0};
    if (gY3OrigInsets) r = ((Y3Quad (*)(id, SEL, id))gY3OrigInsets)(self, _cmd, scene);
    Y3_END
    return r;
}
#define Y3_ID_WRAP(NAME, ORIG) \
static id NAME(id self, SEL _cmd, id scene) { \
    Y3_BEGIN(scene) \
    id r = ORIG ? ((id (*)(id, SEL, id))ORIG)(self, _cmd, scene) : nil; \
    Y3_END \
    return r; \
}
Y3_ID_WRAP(Y3_Lead, gY3OrigLead)
Y3_ID_WRAP(Y3_Trail, gY3OrigTrail)
Y3_ID_WRAP(Y3_Overlay, gY3OrigOverlay)
Y3_ID_WRAP(Y3_Actions, gY3OrigActions)

static void Y3_Shortcut(id self, SEL _cmd, long long action, id bundleID, id scene) {
    Y3_BEGIN(scene)
    if (gY3OrigShortcut) ((void (*)(id, SEL, long long, id, id))gY3OrigShortcut)(self, _cmd, action, bundleID, scene);
    Y3_END
}
static void Y3_Neighbor(id self, SEL _cmd, BOOL requireActive, long long env, BOOL forward, id scene, id label) {
    Y3_BEGIN(scene)
    if (gY3OrigNeighbor) ((void (*)(id, SEL, BOOL, long long, BOOL, id, id))gY3OrigNeighbor)(self, _cmd, requireActive, env, forward, scene, label);
    Y3_END
}

// -[SBMainDisplayLayoutState interfaceOrientationForLayoutRole:]: Stage Manager asks the state's own orientation (see 2.)
static long long Y3_RoleOrient(id self, SEL _cmd, long long role) {
    if (tY3Layout == (__bridge void *)self) return BPX_LL0(self, "interfaceOrientation");
    return gY3OrigRoleOrient ? ((long long (*)(id, SEL, long long))gY3OrigRoleOrient)(self, _cmd, role) : 0;
}

// ---- 3. container status bar hide
// -[SBMainSwitcherControllerCoordinator _shouldTakeStatusBarAssertionForSwitcherController:]  16.2 0x1c76d6120
static BOOL Y3_ShouldTake(id self, SEL _cmd, id sc) {
    unsigned long long mode = (unsigned long long)BPX_LL0(BPX_Obj0(sc, "layoutState"), "unlockedEnvironmentMode");
    return (mode & ~1ULL) == 2;
}
// -[SBMainSwitcherControllerCoordinator _setContainerStatusBarHidden:animationDuration:usingAssertion:reason:windowScene:]  16.2 0x1c76d6164
static void Y3_Container(id self, SEL _cmd, BOOL hidden, double duration, id __strong *assertionPtr, id reason, id scene) {
    if (!BP_OnName("y3_containersb") || !assertionPtr) {
        if (gY3OrigContainer) ((void (*)(id, SEL, BOOL, double, id __strong *, id, id))gY3OrigContainer)(self, _cmd, hidden, duration, assertionPtr, reason, scene);
        return;
    }
    id assertion = *assertionPtr;
    id sc = BPX_Obj0(scene, "switcherController");
    BOOL shouldTake = ((BOOL (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_shouldTakeStatusBarAssertionForSwitcherController:"), sc);
    BOOL alphaZero = NO;
    if (assertion) {
        id alpha = BPX_Obj0(BPX_Obj0(assertion, "settings"), "alpha");
        alphaZero = alpha && [(NSNumber *)alpha doubleValue] == 0.0;
    }
    BOOL changed = ((assertion != nil) != shouldTake) || (alphaZero != hidden);
    if (changed) {
        Class pc = NSClassFromString(@"UIStatusBarStyleAnimationParameters");
        id params = pc ? [[pc alloc] initWithDefaultParameters] : nil;
        if (params) [params setDuration:duration];
        if (shouldTake) {
            if (assertion) {
                BOOL h = hidden;
                void (^blk)(id) = ^(id settings) { BPX_SetObj1(settings, "setAlpha:", [NSNumber numberWithInt:h ? 0 : 1]); };
                [assertion modifySettingsWithBlock:blk animationParameters:params];
            } else {
                id am = BPX_Obj0(BPX_Obj0(scene, "statusBarManager"), "assertionManager");
                id na = [am newSettingsAssertionWithStatusBarHidden:hidden atLevel:6 reason:reason];
                [na acquireWithAnimationParameters:params];
                assertion = na;
            }
        } else {
            [assertion invalidateWithAnimationParameters:params];
            assertion = nil;
        }
        BPY_LOG(@"[y3] container status bar %@ for the scene %p: assertion %@ (take=%d)", hidden ? @"hidden" : @"shown", (__bridge void *)scene, assertion ? @"held" : @"released", (int)shouldTake);
    }
    *assertionPtr = assertion;
}

__attribute__((constructor)) static void Y3_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class co = NSClassFromString(@"SBMainSwitcherControllerCoordinator"), ls = NSClassFromString(@"SBMainDisplayLayoutState");
        if (!co || !ls || !class_getInstanceMethod(co, sel_registerName("_activeDisplaySwitcherController")) ||
            !class_getInstanceMethod(co, sel_registerName("switcherControllerForWindowScene:")) ||
            !class_getInstanceMethod(ls, sel_registerName("interfaceOrientationForLayoutRole:")) ||
            !class_getInstanceMethod(co, sel_registerName("_setContainerStatusBarHidden:animationDuration:usingAssertion:reason:windowScene:"))) {
            BP_Log(@"[y3] NOT installed (class or selector missing)");
            return;
        }
        gY3OrigActive = BPX_Replace(co, "_activeDisplaySwitcherController", (IMP)Y3_Active);
        gY3OrigInApp = BPX_Replace(co, "isInAppStatusBarHiddenForWindowScene:", (IMP)Y3_InApp);
        gY3OrigAvoid1 = BPX_Replace(co, "statusBarAvoidanceFrameForLayoutRole:windowScene:", (IMP)Y3_Avoid1);
        gY3OrigAvoid2 = BPX_Replace(co, "statusBarAvoidanceFrameForLayoutRole:layoutState:windowScene:", (IMP)Y3_Avoid2);
        gY3OrigInsets = BPX_Replace(co, "statusBarEdgeInsetsForWindowScene:", (IMP)Y3_Insets);
        gY3OrigLead = BPX_Replace(co, "leadingStatusBarStyleRequestForWindowScene:", (IMP)Y3_Lead);
        gY3OrigTrail = BPX_Replace(co, "trailingStatusBarStyleRequestForWindowScene:", (IMP)Y3_Trail);
        gY3OrigOverlay = BPX_Replace(co, "statusBarOverlayDataForWindowScene:", (IMP)Y3_Overlay);
        gY3OrigActions = BPX_Replace(co, "statusBarActionsByPartIdentifierForWindowScene:", (IMP)Y3_Actions);
        gY3OrigShortcut = BPX_Replace(co, "_handleFocusedIconSwitcherShortcutAction:bundleIdentifier:windowScene:", (IMP)Y3_Shortcut);
        gY3OrigNeighbor = BPX_Replace(co, "_activateNeighboringAppLayoutRequiringActiveAppLayout:appLayoutEnvironment:inForwardDirection:windowScene:eventLabel:", (IMP)Y3_Neighbor);
        gY3OrigRoleOrient = BPX_Replace(ls, "interfaceOrientationForLayoutRole:", (IMP)Y3_RoleOrient);
        class_addMethod(co, sel_registerName("_shouldTakeStatusBarAssertionForSwitcherController:"), (IMP)Y3_ShouldTake, "B24@0:8@16");
        gY3OrigContainer = BPX_Replace(co, "_setContainerStatusBarHidden:animationDuration:usingAssertion:reason:windowScene:", (IMP)Y3_Container);
        BP_Log(@"[y3] installed (switches y3_scenectl, y3_avoidorient, y3_containersb): coordinator status bar state per window scene");
    }
}
#pragma clang diagnostic pop
