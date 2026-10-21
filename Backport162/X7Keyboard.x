// X7Keyboard.x : gap G7 / audit row S2 "keyboard focus tracker and display scoped suppression" (specs/GAPS-IMPLEMENTED-0.7.9.md section G7).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).  Switches: kbtracker, kbsuppress, kbextscenes.  Setup: X7_Setup().  Log prefix "[x7]" (Backport162.debug only).
//
// 16.2 mechanism
//  1. _SBActiveDisplayKeyboardFocusTracker (new class, conforms to SBActiveWindowSceneTracking): -activeWindowScene 0x1c74bfb9c = [[[SBMainWorkspace sharedInstanceIfExists] keyboardFocusController]
//     windowSceneWithFocus]; if that scene isInvalidated the controller's -explainWhyYouAreFocusingAnInvalidatedScene (0x1c77c3f4c, log only) runs.  SBWindowSceneManager owns it (ivar
//     _keyboardFocusTracker, created in -initWithUserInteractionCoordinator: 0x1c74bf0f4) and -activeDisplayWindowSceneFollowingKeyboard 0x1c74bf244 is
//     [self _validateSuggestedActiveWindowScene:[tracker activeWindowScene] usingMethodology:0].  (16.0 reads the controller directly.)
//  2. Display scoped keyboard suppression.  SBKeyboardSuppressionManager grows startSuppressingKeyboardWithReason:predicate:displayIdentity: 0x1c75376dc,
//     acquireKeyboardSuppressionAssertionWithReason:predicate:displayIdentity: 0x1c75376f0 and _setKeyboardSuppressed:forReason:withPredicate:displayIdentity: 0x1c75378ac, which is the 16.0 body
//     (0x1c5e309f0: a reason 8 UIApplicationSceneDeactivationAssertion acquired with a 0.25 s transition context) with the acquire replaced by
//     -[UIApplicationSceneDeactivationAssertion sb_acquireWithPredicate:transitionContext:displayIdentity:] (0x1c77af7b0): UIKit's acquireWithPredicate:transitionContext: with the predicate
//     (scene, settings) -> (predicate == nil || predicate(scene, settings)) && (identity == nil || [settings.sb_displayIdentityForSceneManagers isEqual:identity]) (block 0x1c77af874), and
//     sb_acquireForDisplayIdentity: 0x1c77af7a0 = that with nil predicate / context.  So the scene deactivation only reaches the scenes of ONE display.
//     Callers with a display (16.2 -> identity):  suppression start: SBSystemGestureWorkspaceTransaction _begin 0x1c72cc550, SBModalUIFluidDismissGestureWorkspaceTransaction _begin 0x1c747bc3c,
//       SBDragAndDropWorkspaceTransaction _begin 0x1c770cff0, SBSpotlightTransientOverlayInteractiveGestureTransaction _begin 0x1c7426320 (all [[self transitionRequest] displayIdentity]),
//       SBLockScreenManager _lockUI 0x1c72fa818 (the cover sheet root view controller's window scene's switcherController displayIdentity), SBSystemNotesManager
//       interactionManager:requestsStartSuppressingKeyboardForReason: 0x1c750b570 ([_sceneManager displayIdentity]), acquire: SBUniversalControlServer block 0x1c776d698 (active display scene).
//       Callers that pass nil (= every display, identical to 16.0): SBFluidSwitcherViewController _acquireKeyboardSuppressionAssertionForMode: 0x1c7459fdc, SBMoveFloatingApplicationGesture...
//       _startSuppressingKeyboardForFloatingApplication 0x1c796f3e4, SBPIPSceneContentContainerAdapter 0x1c783b6c4.
//     sb_acquireForDisplayIdentity: callers (the "resign active" assertions, reason 5): SBToAppsWorkspaceTransaction _acquireResignActiveAssertion 0x1c72e721c ([[transitionRequest] displayIdentity]),
//       SBCoverSheetSceneManager updateForegroundScenesForCoverSheetAnimationActive: 0x1c72f1064 ([coverSheetWindow _fbsDisplayIdentity]), SBControlCenterController _willPresent 0x1c7301748
//       ([_window _fbsDisplayIdentity]), SBNotificationBannerDestination longLookWillPresentForNotificationViewController: 0x1c7308ad8 ([controller _fbsDisplayIdentity]),
//       SBFluidSwitcherViewController layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext: 0x1c743d6f0 ([[self _sbWindowScene] _fbsDisplayIdentity]), SBCommandTabController
//       _showWindow: 0x1c7574cf8 ([[windowSceneManager activeDisplayWindowScene] _fbsDisplayIdentity]), SBAssistantSession _viewWillAppear: 0x1c761ae4c ([[[self assistantWindow] windowScene]
//       _fbsDisplayIdentity]), SBModalLibraryController _evaluateResignActiveAssertion 0x1c78008b0 ([[self sceneManager] displayIdentity]).  16.0 calls plain -acquire in all of them (every display's
//       apps resign active, e.g. when Control Centre opens on the iPad).
//  3. External scene identities: SBSKeyboardFocusService (client, SpringBoardServices) -setExternalSceneIdentities:forReason: -> SBKeyboardFocusService (server) -setExternalSceneIdentities:
//     0x1c733696c (authenticate the audit token, per connection map _lock_externalSceneIdentitiesByConnection, union by -_lock_updateExternalSceneIdentities 0x1c73372d4) -> SBWorkspaceKeyboardFocusController
//     setExternalSceneIdentities: 0x1c77c8f94; _handleDisconnectForServiceConnection: 0x1c7336f1c also drops the connection's entry.  The controller reads the set in
//     _filterFocusedSceneIdentityToken:focusedPID:resultBlock: (0x1c77c4590, "arbiter advice (known external scene)").
//
// Port.  1: class BPActiveDisplayKeyboardFocusTracker (a 16.0 runtime must not carry the 16.2 class name) + SBWindowSceneManager keyboardFocusTracker; Group4Focus.x asks it through X7_TrackerScene().
//  2: the three manager methods and the two assertion methods are added (class_addMethod, same selectors as 16.2).  The 16.0 body of _setKeyboardSuppressed:... is REUSED for the new variant: the new
//  method sets a thread local identity that a hook of -acquireWithPredicate:transitionContext: turns into sb_acquireWithPredicate:...displayIdentity: for the reason 8 assertion it creates (the
//  rest of that body is identical in both builds).  The callers listed above are 16.0 methods that call the old API: each is wrapped by a hook that sets a thread local "scope" evaluated lazily when
//  the old API (start / acquire) or the assertion's -acquire is reached, which then takes the 16.2 route.  One shot per wrapper call.
//  3: the service / controller API and the disconnect clean-up, as 16.2.
//
// NOT ported / unreachable on 16.0: the client SBSKeyboardFocusService -setExternalSceneIdentities:forReason: (no 16.0 process sends it, the 16.0 SBS interface protocol does not list it, so
// the XPC dispatch never reaches the server method) and the consumer branch in _filterFocusedSceneIdentityToken: (a 98-instruction rewrite of an 345 instruction method with objc_direct helpers of
// _SBRecentlyUsedSceneIdentityCache; it only acts on a non-empty external set).  The SBUniversalControlServer block is a plain block of the class (not hookable by selector): its suppression keeps
// the 16.0 meaning (all displays).  Needs a device: open Control Centre / start a window drag / the Spotlight pull-down on the iPad with an app on the monitor in front: the monitor app must not
// resign active / lose its keyboard.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define X7_SUPPRESS_ON() BP_OnName("kbsuppress")

// ---------------------------------------------------------------------------------------------- 1: the tracker

static Class gX7TrackerClass;
static char kX7TrackerKey;

// -[_SBActiveDisplayKeyboardFocusTracker activeWindowScene] 16.2 0x1c74bfb9c
static id X7_TrackerActiveWindowScene(id self, SEL _cmd) {
    Class mw = NSClassFromString(@"SBMainWorkspace");
    id ws = mw ? BPX_Obj0((id)mw, "sharedInstanceIfExists") : nil;
    id kfc = BPX_Obj0(ws, "keyboardFocusController");
    id scene = BPX_Obj0(kfc, "windowSceneWithFocus");
    if (BPX_Bool0(scene, "isInvalidated")) {
        // -[SBWorkspaceKeyboardFocusController explainWhyYouAreFocusingAnInvalidatedScene] 0x1c77c3f4c: log only
        BPX_LOG(@"[x7] keyboard focus controller focuses the invalidated window scene %@ (display %@)", scene, BPX_Obj0(scene, "_fbsDisplayIdentity"));
    }
    return scene;
}

static id X7_ManagerTracker(id self, SEL _cmd) {
    id t = objc_getAssociatedObject(self, &kX7TrackerKey);
    if (!t && gX7TrackerClass) {                       // 16.2 creates it in the manager's init; the 16.0 manager is made earlier than this tweak
        t = [[gX7TrackerClass alloc] init];
        objc_setAssociatedObject(self, &kX7TrackerKey, t, OBJC_ASSOCIATION_RETAIN);
    }
    return t;
}
static void X7_ManagerSetTracker(id self, SEL _cmd, id t) { objc_setAssociatedObject(self, &kX7TrackerKey, t, OBJC_ASSOCIATION_RETAIN); }

// For Group4Focus.x -activeDisplayWindowSceneFollowingKeyboard: YES and *out set when the tracker answered.
BOOL X7_TrackerScene(id manager, id *out);
BOOL X7_TrackerScene(id manager, id *out) {
    if (!gX7TrackerClass || !BP_OnName("kbtracker")) return NO;
    id t = X7_ManagerTracker(manager, NULL);
    if (!t) return NO;
    *out = ((id (*)(id, SEL))objc_msgSend)(t, sel_registerName("activeWindowScene"));
    return YES;
}

static void X7_InstallTracker(void) {
    Class mgr = NSClassFromString(@"SBWindowSceneManager");
    if (!mgr) { BP_Log(@"[x7] SBWindowSceneManager not found, tracker not installed"); return; }
    Class c = objc_allocateClassPair([NSObject class], "BPActiveDisplayKeyboardFocusTracker", 0);
    if (!c) { c = NSClassFromString(@"BPActiveDisplayKeyboardFocusTracker"); }
    else {
        class_addMethod(c, sel_registerName("activeWindowScene"), (IMP)X7_TrackerActiveWindowScene, "@16@0:8");
        Protocol *p = objc_getProtocol("SBActiveWindowSceneTracking");
        if (p) class_addProtocol(c, p);
        objc_registerClassPair(c);
    }
    gX7TrackerClass = c;
    class_addMethod(mgr, sel_registerName("keyboardFocusTracker"), (IMP)X7_ManagerTracker, "@16@0:8");
    class_addMethod(mgr, sel_registerName("setKeyboardFocusTracker:"), (IMP)X7_ManagerSetTracker, "v24@0:8@16");
    BP_Log(@"[x7] keyboard focus tracker %s installed (SBActiveWindowSceneTracking %s)", class_getName(c), objc_getProtocol("SBActiveWindowSceneTracking") ? "adopted" : "absent in 16.0");
}

// ---------------------------------------------------------------------------------------------- 2: scene deactivation scoped to a display

static IMP gX7OrigAcquireWith, gX7OrigAcquire;

// 16.2 0x1c77af874: (predicate == nil || predicate(scene, settings)) && (identity == nil || [settings.sb_displayIdentityForSceneManagers isEqual:identity])
static id X7_ScopedPredicate(id predicate, id identity) {
    id pred = predicate ? [predicate copy] : nil;
    BOOL (^blk)(id, id) = ^BOOL(id scene, id settings) {
        if (pred && !((BOOL (^)(id, id))pred)(scene, settings)) return NO;
        if (!identity) return YES;
        return [BPX_Obj0(settings, "sb_displayIdentityForSceneManagers") isEqual:identity];
    };
    return blk;
}

// -[UIApplicationSceneDeactivationAssertion(SBWindowScene) sb_acquireWithPredicate:transitionContext:displayIdentity:] 16.2 0x1c77af7b0
static void X7_SBAcquireWith(id self, SEL _cmd, id predicate, id ctx, id identity) {
    id scoped = X7_ScopedPredicate(predicate, identity);
    SEL s = sel_registerName("acquireWithPredicate:transitionContext:");
    if (gX7OrigAcquireWith) ((void (*)(id, SEL, id, id))gX7OrigAcquireWith)(self, s, scoped, ctx);
    else ((void (*)(id, SEL, id, id))objc_msgSend)(self, s, scoped, ctx);
}
// -[... sb_acquireForDisplayIdentity:] 16.2 0x1c77af7a0
static void X7_SBAcquireFor(id self, SEL _cmd, id identity) { X7_SBAcquireWith(self, NULL, nil, nil, identity); }

typedef struct { int kind; void *obj; void *arg; void *eager; } X7Scope;
static __thread X7Scope gX7Resign, gX7Suppress;      // armed by the caller wrappers below
static __thread void *gX7KbIdentity;                  // identity of the reason 8 assertion that -_setKeyboardSuppressed:...displayIdentity: is about to create (unretained, alive in that frame)
static __thread int gX7KbIdentityArmed;

enum { R_TOAPPS = 1, R_COVER, R_CC, R_NBD, R_FLUID, R_CMDTAB, R_ASSIST, R_MODALLIB, S_TRANSACTION, S_LOCK, S_NOTES };

static id X7_Identity(int kind, id obj, id arg, id eager) {
    switch (kind) {
        case R_TOAPPS: case S_TRANSACTION: return BPX_Obj0(BPX_Obj0(obj, "transitionRequest"), "displayIdentity");
        case R_COVER:   return BPX_Obj0(BPX_Obj0(obj, "coverSheetWindow"), "_fbsDisplayIdentity");
        case R_CC:      return BPX_Obj0(BPX_IvarObj(obj, "_window"), "_fbsDisplayIdentity");
        case R_NBD:     return BPX_Obj0(arg, "_fbsDisplayIdentity");
        case R_FLUID:   return BPX_Obj0(BPX_Obj0(obj, "_sbWindowScene"), "_fbsDisplayIdentity");
        case R_CMDTAB:  return eager;
        case R_ASSIST:  return BPX_Obj0(BPX_Obj0(BPX_Obj0(obj, "assistantWindow"), "windowScene"), "_fbsDisplayIdentity");
        case R_MODALLIB:return BPX_Obj0(BPX_Obj0(obj, "sceneManager"), "displayIdentity");
        case S_LOCK: {
            id env = BPX_Obj0(obj, "lockScreenEnvironment");
            return BPX_Obj0(BPX_Obj0(BPX_Obj0(BPX_Obj0(env, "rootViewController"), "_sbWindowScene"), "switcherController"), "displayIdentity");
        }
        case S_NOTES:   return BPX_Obj0(BPX_IvarObj(obj, "_sceneManager"), "displayIdentity");
        default:        return nil;
    }
}

// UIKit -acquire: the caller wrappers made it a 16.2 sb_acquireForDisplayIdentity: for the first call inside the wrapped method
static void X7_Acquire(id self, SEL _cmd) {
    if (gX7Resign.kind && X7_SUPPRESS_ON()) {
        X7Scope s = gX7Resign;
        gX7Resign.kind = 0;
        id ident = X7_Identity(s.kind, (__bridge id)s.obj, (__bridge id)s.arg, (__bridge id)s.eager);
        BPX_LOG(@"[x7] resign active assertion (kind %d) acquired for display %@", s.kind, ident);
        X7_SBAcquireFor(self, NULL, ident);
        return;
    }
    if (gX7OrigAcquire) ((void (*)(id, SEL))gX7OrigAcquire)(self, _cmd);
}

// UIKit -acquireWithPredicate:transitionContext: : the reason 8 assertion of -_setKeyboardSuppressed:...displayIdentity:
static void X7_AcquireWith(id self, SEL _cmd, id predicate, id ctx) {
    if (gX7KbIdentityArmed && X7_SUPPRESS_ON() && BPX_LL0(self, "reason") == 8) {
        id ident = (__bridge id)gX7KbIdentity;
        gX7KbIdentityArmed = 0;
        BPX_LOG(@"[x7] keyboard suppression assertion acquired for display %@", ident);
        X7_SBAcquireWith(self, NULL, predicate, ctx, ident);
        return;
    }
    if (gX7OrigAcquireWith) ((void (*)(id, SEL, id, id))gX7OrigAcquireWith)(self, _cmd, predicate, ctx);
}

// ---------------------------------------------------------------------------------------------- 2b: SBKeyboardSuppressionManager

static IMP gX7OrigStart, gX7OrigAcquireKb;

// -_setKeyboardSuppressed:forReason:withPredicate:displayIdentity: 16.2 0x1c75378ac: the 16.0 body with the display scoped acquire
static void X7_MgrSet(id self, SEL _cmd, BOOL suppressed, id reason, id predicate, id identity) {
    SEL old = sel_registerName("_setKeyboardSuppressed:forReason:withPredicate:");
    void *prevId = gX7KbIdentity; int prevArm = gX7KbIdentityArmed;
    if (suppressed && identity) { gX7KbIdentity = (__bridge void *)identity; gX7KbIdentityArmed = 1; }
    ((void (*)(id, SEL, BOOL, id, id))objc_msgSend)(self, old, suppressed, reason, predicate);
    gX7KbIdentity = prevId; gX7KbIdentityArmed = prevArm;
}
// 0x1c75376dc
static void X7_MgrStart(id self, SEL _cmd, id reason, id predicate, id identity) { X7_MgrSet(self, NULL, YES, reason, predicate, identity); }
// 0x1c75376f0 (the 16.0 body 0x1c60b3130 with the displayIdentity variant of _set...; invalidation: stopSuppressingKeyboardWithReason:reason on the weak manager)
static id X7_MgrAcquire(id self, SEL _cmd, id reason, id predicate, id identity) {
    Class sa = NSClassFromString(@"BSSimpleAssertion");
    SEL init = sel_registerName("initWithIdentifier:forReason:invalidationBlock:");
    if (!sa || ![sa instancesRespondToSelector:init]) return nil;
    __weak id weakSelf = self;
    NSString *r = [reason copy];
    void (^inv)(id) = ^(id a) {
        id m = weakSelf;
        if (m) ((void (*)(id, SEL, id))objc_msgSend)(m, sel_registerName("stopSuppressingKeyboardWithReason:"), r);
    };
    id assertion = ((id (*)(id, SEL, id, id, id))objc_msgSend)([sa alloc], init, @"SBKeyboardSuppressionManager", r, inv);
    X7_MgrSet(self, NULL, YES, r, predicate, identity);
    return assertion;
}

// old 16.0 API called from the wrapped callers: take the 16.2 route with the wrapper's display
static void X7_OldStart(id self, SEL _cmd, id reason, id predicate) {
    if (gX7Suppress.kind && X7_SUPPRESS_ON()) {
        X7Scope s = gX7Suppress;
        gX7Suppress.kind = 0;
        id ident = X7_Identity(s.kind, (__bridge id)s.obj, (__bridge id)s.arg, (__bridge id)s.eager);
        BPX_LOG(@"[x7] startSuppressingKeyboardWithReason:%@ for display %@", reason, ident);
        X7_MgrStart(self, NULL, reason, predicate, ident);
        return;
    }
    if (gX7OrigStart) ((void (*)(id, SEL, id, id))gX7OrigStart)(self, _cmd, reason, predicate);
}
static id X7_OldAcquire(id self, SEL _cmd, id reason, id predicate) {
    if (gX7Suppress.kind && X7_SUPPRESS_ON()) {
        X7Scope s = gX7Suppress;
        gX7Suppress.kind = 0;
        id ident = X7_Identity(s.kind, (__bridge id)s.obj, (__bridge id)s.arg, (__bridge id)s.eager);
        BPX_LOG(@"[x7] acquireKeyboardSuppressionAssertionWithReason:%@ for display %@", reason, ident);
        return X7_MgrAcquire(self, NULL, reason, predicate, ident);
    }
    return gX7OrigAcquireKb ? ((id (*)(id, SEL, id, id))gX7OrigAcquireKb)(self, _cmd, reason, predicate) : nil;
}

// ---------------------------------------------------------------------------------------------- caller wrappers
// Each wrapped 16.0 method keeps its own body; the scope is armed around the original call and restored afterwards.

static inline void *X7_Ptr(id o) { return (__bridge void *)o; }      // nil is a plain (void *)0 on Apple platforms: never write (__bridge void *)(nil) in a macro
#define X7_ARM(TLS, KIND, OBJ, ARG) X7Scope prev_ = TLS; if (X7_SUPPRESS_ON()) { TLS.kind = (KIND); TLS.obj = X7_Ptr(OBJ); TLS.arg = X7_Ptr(ARG); TLS.eager = NULL; }
#define X7_DISARM(TLS) TLS = prev_

// resign active (reason 5) assertions
static IMP gW_ToApps, gW_Cover, gW_CC, gW_NBD, gW_Fluid, gW_CmdTab, gW_Assist, gW_ModalLib;
static void X7_W_ToApps(id self, SEL _cmd)            { X7_ARM(gX7Resign, R_TOAPPS, self, nil);  ((void (*)(id, SEL))gW_ToApps)(self, _cmd); X7_DISARM(gX7Resign); }
static void X7_W_Cover(id self, SEL _cmd, BOOL a)     { X7_ARM(gX7Resign, R_COVER, self, nil);   ((void (*)(id, SEL, BOOL))gW_Cover)(self, _cmd, a); X7_DISARM(gX7Resign); }
static void X7_W_CC(id self, SEL _cmd)                { X7_ARM(gX7Resign, R_CC, self, nil);      ((void (*)(id, SEL))gW_CC)(self, _cmd); X7_DISARM(gX7Resign); }
static void X7_W_NBD(id self, SEL _cmd, id vc)        { X7_ARM(gX7Resign, R_NBD, self, vc);      ((void (*)(id, SEL, id))gW_NBD)(self, _cmd, vc); X7_DISARM(gX7Resign); }
static void X7_W_Fluid(id self, SEL _cmd, id c, id x) { X7_ARM(gX7Resign, R_FLUID, self, nil);   ((void (*)(id, SEL, id, id))gW_Fluid)(self, _cmd, c, x); X7_DISARM(gX7Resign); }
static void X7_W_CmdTab(id self, SEL _cmd, BOOL show) {
    // 16.2 0x1c7574bd0: the display is that of the ACTIVE display's window scene, read at the top of the method
    id eager = BPX_Obj0(BPX_Obj0(BPX_WindowSceneManager(), "activeDisplayWindowScene"), "_fbsDisplayIdentity");
    X7_ARM(gX7Resign, R_CMDTAB, self, nil);
    if (gX7Resign.kind) gX7Resign.eager = (__bridge void *)eager;
    ((void (*)(id, SEL, BOOL))gW_CmdTab)(self, _cmd, show);
    X7_DISARM(gX7Resign);
}
static void X7_W_Assist(id self, SEL _cmd, BOOL a)    { X7_ARM(gX7Resign, R_ASSIST, self, nil);  ((void (*)(id, SEL, BOOL))gW_Assist)(self, _cmd, a); X7_DISARM(gX7Resign); }
static void X7_W_ModalLib(id self, SEL _cmd)          { X7_ARM(gX7Resign, R_MODALLIB, self, nil);((void (*)(id, SEL))gW_ModalLib)(self, _cmd); X7_DISARM(gX7Resign); }

// keyboard suppression start
static IMP gW_SysGesture, gW_ModalDismiss, gW_DragDrop, gW_SpotGesture, gW_Lock, gW_Notes;
#define X7_BEGIN_WRAP(NAME, ORIG) static void NAME(id self, SEL _cmd) { X7_ARM(gX7Suppress, S_TRANSACTION, self, nil); ((void (*)(id, SEL))ORIG)(self, _cmd); X7_DISARM(gX7Suppress); }
X7_BEGIN_WRAP(X7_W_SysGesture, gW_SysGesture)
X7_BEGIN_WRAP(X7_W_ModalDismiss, gW_ModalDismiss)
X7_BEGIN_WRAP(X7_W_DragDrop, gW_DragDrop)
X7_BEGIN_WRAP(X7_W_SpotGesture, gW_SpotGesture)
static BOOL X7_W_Lock(id self, SEL _cmd)                       { X7_ARM(gX7Suppress, S_LOCK, self, nil);  BOOL r = ((BOOL (*)(id, SEL))gW_Lock)(self, _cmd); X7_DISARM(gX7Suppress); return r; }
static void X7_W_Notes(id self, SEL _cmd, id mgr, id reason)   { X7_ARM(gX7Suppress, S_NOTES, self, nil); ((void (*)(id, SEL, id, id))gW_Notes)(self, _cmd, mgr, reason); X7_DISARM(gX7Suppress); }

static void X7_Wrap(const char *cls, const char *sel, IMP imp, IMP *orig) {
    Class c = NSClassFromString([NSString stringWithUTF8String:cls]);
    IMP o = c ? BPX_Replace(c, sel, imp) : NULL;
    if (o) *orig = o;
    else BP_Log(@"[x7] -[%s %s] not found, not wrapped", cls, sel);
}

// ---------------------------------------------------------------------------------------------- 3: external scene identities

static char kX7ExtIdsKey, kX7ExtMapKey;

static id X7_KfcExternalIds(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kX7ExtIdsKey); }                       // 16.2 0x1c77c8f88 (atomic copy property)
static void X7_KfcSetExternalIds(id self, SEL _cmd, id ids) { objc_setAssociatedObject(self, &kX7ExtIdsKey, ids, OBJC_ASSOCIATION_COPY); }   // 0x1c77c8f94

static os_unfair_lock_t X7_SvcLock(id svc) {
    Ivar iv = class_getInstanceVariable(object_getClass(svc), "_lock");
    return iv ? (os_unfair_lock_t)((char *)(__bridge void *)svc + ivar_getOffset(iv)) : NULL;
}
static NSMapTable *X7_SvcMap(id svc) {
    NSMapTable *m = objc_getAssociatedObject(svc, &kX7ExtMapKey);
    if (!m) { m = [NSMapTable strongToStrongObjectsMapTable]; objc_setAssociatedObject(svc, &kX7ExtMapKey, m, OBJC_ASSOCIATION_RETAIN); }
    return m;
}
// -_lock_updateExternalSceneIdentities 16.2 0x1c73372d4 (lock held): union of the per connection sets -> the controller
static void X7_SvcLockUpdate(id svc, SEL _cmd) {
    NSMutableSet *all = [NSMutableSet set];
    for (id set in [X7_SvcMap(svc) objectEnumerator]) if ([set isKindOfClass:[NSSet class]]) [all unionSet:set];
    BPX_LOG(@"[x7] external scene identities: %@", all);
    BPX_SetObj1(BPX_IvarObj(svc, "_keyboardFocusController"), "setExternalSceneIdentities:", all);
}
// -setExternalSceneIdentities: 16.2 0x1c733696c (oneway)
static void X7_SvcSetExternal(id svc, SEL _cmd, id identities) {
    id ctx = BPX_Obj0((id)NSClassFromString(@"BSServiceConnection"), "currentContext");
    id proc = BPX_Obj0(ctx, "remoteProcess");
    id token = BPX_Obj0(proc, "auditToken");
    id auth = BPX_IvarObj(svc, "_serviceClientAuthenticator");
    SEL as = sel_registerName("authenticateAuditToken:");
    BOOL ok = (auth && [auth respondsToSelector:as]) ? ((BOOL (*)(id, SEL, id))objc_msgSend)(auth, as, token) : NO;
    if (!ok) { BP_Log(@"[x7] setExternalSceneIdentities: from an unauthenticated client ignored"); return; }
    os_unfair_lock_t lk = X7_SvcLock(svc);
    if (!lk) { BP_Log(@"[x7] SBKeyboardFocusService has no _lock ivar"); return; }
    os_unfair_lock_lock(lk);
    if ([identities count] && ctx) [X7_SvcMap(svc) setObject:identities forKey:ctx];
    else if (ctx) [X7_SvcMap(svc) removeObjectForKey:ctx];
    X7_SvcLockUpdate(svc, NULL);
    os_unfair_lock_unlock(lk);
}
static IMP gX7OrigSvcDisconnect;
static void X7_SvcDisconnect(id svc, SEL _cmd, id connection) {
    if (gX7OrigSvcDisconnect) ((void (*)(id, SEL, id))gX7OrigSvcDisconnect)(svc, _cmd, connection);
    if (!BP_OnName("kbextscenes") || !connection) return;
    os_unfair_lock_t lk = X7_SvcLock(svc);
    if (!lk) return;
    os_unfair_lock_lock(lk);
    [X7_SvcMap(svc) removeObjectForKey:connection];                // 16.2 0x1c7337020
    X7_SvcLockUpdate(svc, NULL);
    os_unfair_lock_unlock(lk);
}

// ---------------------------------------------------------------------------------------------- setup

void X7_Setup(void) {
    if (BP_OnName("kbtracker")) X7_InstallTracker();

    {                                                               // installed unconditionally; every hook tests the switch per call
        Class ua = NSClassFromString(@"UIApplicationSceneDeactivationAssertion");
        Class km = NSClassFromString(@"SBKeyboardSuppressionManager");
        BOOL ok = ua && km && class_getInstanceMethod(ua, sel_registerName("acquireWithPredicate:transitionContext:")) && class_getInstanceMethod(ua, sel_registerName("acquire"))
               && class_getInstanceMethod(km, sel_registerName("_setKeyboardSuppressed:forReason:withPredicate:"))
               && class_getInstanceMethod(km, sel_registerName("startSuppressingKeyboardWithReason:predicate:"))
               && class_getInstanceMethod(km, sel_registerName("acquireKeyboardSuppressionAssertionWithReason:predicate:"));
        if (!ok) {
            BP_Log(@"[x7] display scoped suppression NOT installed (UIApplicationSceneDeactivationAssertion / SBKeyboardSuppressionManager selectors missing)");
        } else {
            class_addMethod(ua, sel_registerName("sb_acquireWithPredicate:transitionContext:displayIdentity:"), (IMP)X7_SBAcquireWith, "v40@0:8@16@24@32");
            class_addMethod(ua, sel_registerName("sb_acquireForDisplayIdentity:"), (IMP)X7_SBAcquireFor, "v24@0:8@16");
            class_addMethod(km, sel_registerName("startSuppressingKeyboardWithReason:predicate:displayIdentity:"), (IMP)X7_MgrStart, "v40@0:8@16@?24@32");
            class_addMethod(km, sel_registerName("acquireKeyboardSuppressionAssertionWithReason:predicate:displayIdentity:"), (IMP)X7_MgrAcquire, "@40@0:8@16@?24@32");
            class_addMethod(km, sel_registerName("_setKeyboardSuppressed:forReason:withPredicate:displayIdentity:"), (IMP)X7_MgrSet, "v44@0:8B16@20@?28@36");
            gX7OrigAcquireWith = BPX_Replace(ua, "acquireWithPredicate:transitionContext:", (IMP)X7_AcquireWith);
            gX7OrigAcquire = BPX_Replace(ua, "acquire", (IMP)X7_Acquire);
            gX7OrigStart = BPX_Replace(km, "startSuppressingKeyboardWithReason:predicate:", (IMP)X7_OldStart);
            gX7OrigAcquireKb = BPX_Replace(km, "acquireKeyboardSuppressionAssertionWithReason:predicate:", (IMP)X7_OldAcquire);

            X7_Wrap("SBToAppsWorkspaceTransaction", "_acquireResignActiveAssertion", (IMP)X7_W_ToApps, &gW_ToApps);
            X7_Wrap("SBCoverSheetSceneManager", "updateForegroundScenesForCoverSheetAnimationActive:", (IMP)X7_W_Cover, &gW_Cover);
            X7_Wrap("SBControlCenterController", "_willPresent", (IMP)X7_W_CC, &gW_CC);
            X7_Wrap("SBNotificationBannerDestination", "longLookWillPresentForNotificationViewController:", (IMP)X7_W_NBD, &gW_NBD);
            X7_Wrap("SBFluidSwitcherViewController", "layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:", (IMP)X7_W_Fluid, &gW_Fluid);
            X7_Wrap("SBCommandTabController", "_showWindow:", (IMP)X7_W_CmdTab, &gW_CmdTab);
            X7_Wrap("SBAssistantSession", "_viewWillAppear:", (IMP)X7_W_Assist, &gW_Assist);
            X7_Wrap("SBModalLibraryController", "_evaluateResignActiveAssertion", (IMP)X7_W_ModalLib, &gW_ModalLib);
            X7_Wrap("SBSystemGestureWorkspaceTransaction", "_begin", (IMP)X7_W_SysGesture, &gW_SysGesture);
            X7_Wrap("SBModalUIFluidDismissGestureWorkspaceTransaction", "_begin", (IMP)X7_W_ModalDismiss, &gW_ModalDismiss);
            X7_Wrap("SBDragAndDropWorkspaceTransaction", "_begin", (IMP)X7_W_DragDrop, &gW_DragDrop);
            X7_Wrap("SBSpotlightTransientOverlayInteractiveGestureTransaction", "_begin", (IMP)X7_W_SpotGesture, &gW_SpotGesture);
            X7_Wrap("SBLockScreenManager", "_lockUI", (IMP)X7_W_Lock, &gW_Lock);
            X7_Wrap("SBSystemNotesManager", "interactionManager:requestsStartSuppressingKeyboardForReason:", (IMP)X7_W_Notes, &gW_Notes);
            BP_Log(@"[x7] display scoped keyboard suppression / resign active installed");
        }
    }

    Class kfc = NSClassFromString(@"SBWorkspaceKeyboardFocusController");
    Class svc = NSClassFromString(@"SBKeyboardFocusService");
    if (kfc && svc) {
        class_addMethod(kfc, sel_registerName("externalSceneIdentities"), (IMP)X7_KfcExternalIds, "@16@0:8");
        class_addMethod(kfc, sel_registerName("setExternalSceneIdentities:"), (IMP)X7_KfcSetExternalIds, "v24@0:8@16");
        class_addMethod(svc, sel_registerName("setExternalSceneIdentities:"), (IMP)X7_SvcSetExternal, "v24@0:8@16");
        class_addMethod(svc, sel_registerName("_lock_updateExternalSceneIdentities"), (IMP)X7_SvcLockUpdate, "v16@0:8");
        gX7OrigSvcDisconnect = BPX_Replace(svc, "_handleDisconnectForServiceConnection:", (IMP)X7_SvcDisconnect);
        BP_Log(@"[x7] external scene identities API installed");
    } else {
        BP_Log(@"[x7] SBKeyboardFocusService / SBWorkspaceKeyboardFocusController missing, external scene identities not installed");
    }
}
#pragma clang diagnostic pop
