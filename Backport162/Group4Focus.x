// group4-disconnect-focus-pointer.hooks.m
//
// DRAFT. Logos source (rename to .xm or paste into Tweak.x). Backports the portable parts of the iPadOS 16.2 (20C65)
// external display DISCONNECT handling, active-display / keyboard focus tracking and pointer routing to 16.0 (20A8372).
// Behaviour is specified in group4-disconnect-focus-pointer.md (section numbers in the comments refer to it).
//
// Every piece is tagged  // PORTABLE,  // PARTIAL: <why>  or  // NOT PORTABLE: <why>.
//
// Integration with Tweak.x (do not paste blindly, Tweak.x is not edited by this draft):
//   1. enum { ..., F_DISCONNECT, F_DISCSWITCH, F_ACTIVEDISPLAY, F_GESTUREGATE, F_LOCKEDPTR, F_COUNT };
//      kFeatureNames: "disconnect", "discswitch", "activedisplay", "gesturegate", "lockedptr"
//      (switch files <jbroot>/tmp/Backport162.off.<name>, as for the existing features).
//      F_DISCSWITCH is OPT-IN: it only runs if <jbroot>/tmp/Backport162.on.discswitch exists.
//   2. Call BP_G4_Setup() from the %ctor after the existing %init (it does %init(G4) and the direct-function hook).
//   3. Uses MSHookFunction (link CydiaSubstrate / ElleKit like the other hooks) for ONE direct (non-ObjC) function.
//   4. Compile with ARC (-fobjc-arc), like Tweak.x.
//   For a standalone syntax check define BP_G4_STANDALONE (supplies stand-ins for BP_On / BP_Log / the enum).
//
// Safety rules followed here:
//   * No ivar of a system class is touched by a hard-coded offset. State that 16.2 keeps in new ivars is kept in
//     associated objects; the two system ivars that are read (SBFluidSwitcherGestureManager._switcherController) are
//     found by name with class_getInstanceVariable + object_getIvar and the code does nothing if they are missing.
//   * Every selector sent to a private object is checked with respondsToSelector: first (or is a selector the 16.0 binary
//     itself sends to that class, verified in the disassembly).
//   * Every hook is a no-op when its feature switch is off, and calls %orig first/last as noted.
//   * The one inline function hook verifies the first 7 instruction words of its target and refuses to patch on mismatch.
//   * The 16.2 hard crash in -[SBWindowScene setInvalidating:NO] is deliberately NOT reproduced (it logs and ignores).

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

#import <Foundation/Foundation.h>
#import <rootless.h>
#import "BP.h"
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#import <unistd.h>

// ------------------------------------------------------------------------------------------------ host integration

#ifdef BP_G4_STANDALONE
enum { F_DISCONNECT, F_DISCSWITCH, F_ACTIVEDISPLAY, F_GESTUREGATE, F_LOCKEDPTR, F_COUNT };
static BOOL BP_On(int f) { (void)f; return YES; }
static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) { (void)fmt; }
#endif

// Opt-in switch: <jbroot>/tmp/Backport162.on.<name>, checked at most once a second per name.
static BOOL BP_G4_OptIn(const char *name) {
#ifdef BP_G4_STANDALONE
    (void)name;
    return NO;
#else
    static char base[1024];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *tmp = ROOT_PATH_NS(@"/tmp");               // same helper Tweak.x uses (<rootless.h>)
        snprintf(base, sizeof base, "%s/Backport162.on.", tmp.fileSystemRepresentation);
    });
    static uint64_t next;
    static BOOL last;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < next) return last;
    next = t + 1000000000ull;
    char path[1200];
    snprintf(path, sizeof path, "%s%s", base, name);
    last = access(path, F_OK) == 0;
    return last;
#endif
}

// ------------------------------------------------------------------------------------------------ private interfaces
// Informal declarations on NSObject so that messages to `id` compile without UIKit headers. Only selectors that exist
// in the 16.0 binaries (verified) are declared here.

typedef struct __IOHIDEvent *BPIOHIDEventRef;

@interface NSObject (BPG4Private)
+ (id)sharedApplication;
+ (id)sharedInstance;
+ (id)sharedInstanceIfExists;
+ (id)_windowWithContextId:(unsigned int)contextId;
- (id)windowSceneManager;                                   // SpringBoard
- (id)keyboardFocusController;                              // SBMainWorkspace
- (id)windowSceneWithFocus;                                 // SBWorkspaceKeyboardFocusController
- (void)updateKeyboardFocusDeferringRules;                  // SBWorkspaceKeyboardFocusController (tail-branches to _reevaluate...)
- (void)removeKeyboardFocusFromScene:(id)scene;             // SBWorkspaceKeyboardFocusController (takes an FBScene)
- (id)embeddedDisplayWindowScene;                           // SBWindowSceneManager
- (id)connectedWindowScenes;                                // SBWindowSceneManager
- (id)windowSceneForDisplayIdentity:(id)identity;           // SBWindowSceneManager
- (id)sceneManager;                                         // SBWindowScene
- (id)externalForegroundApplicationSceneHandles;            // SBSceneManager
- (void)removeObserver:(id)observer;                        // SBSceneManager / NSNotificationCenter
- (id)scene;                                                // SBSceneHandle
- (id)screen;                                               // UIWindowScene
- (id)displayIdentity;                                      // UIScreen
- (id)displayConfiguration;                                 // UIScreen
- (id)_fbsDisplayIdentity;                                  // UIWindow / UIWindowScene categories in SpringBoard
- (id)_fbsDisplayConfiguration;                             // UIWindowScene category in SpringBoard
- (id)hardwareIdentifier;                                   // FBSDisplayConfiguration
- (id)allTouches;                                           // UIEvent
- (BPIOHIDEventRef)_hidEvent;                               // UIEvent
- (long long)type;                                          // UIEvent / UITouch
- (long long)phase;                                         // UITouch
- (BOOL)_isPointerTouch;                                    // UITouch
- (id)view;                                                 // UITouch
- (CGPoint)locationInView:(id)view;                         // UITouch
- (CGPoint)previousLocationInView:(id)view;                 // UITouch
- (id)window;                                               // UITouch
- (id)windowScene;                                          // UIWindow
- (id)_controlCenterWindow;                                 // SBControlCenterController
- (unsigned int)contextID;                                  // BKSHIDEvent*Attributes
- (BOOL)isActive;                                           // BSCompoundAssertion
- (id)reasons;                                              // BSCompoundAssertion
- (id)acquireForReason:(id)reason;                          // BSCompoundAssertion
- (void)invalidate;                                         // BSInvalidatable
- (void)windowSceneDidDisconnect:(id)windowScene;
- (BOOL)isInvalidating;                                     // %new on SBWindowScene below
- (BOOL)isInvalidated;                                      // %new on SBWindowScene / SBAbstractWindowSceneDelegate below
- (void)setInvalidating:(BOOL)invalidating;                 // %new on SBWindowScene below
- (void)setInvalidated:(BOOL)invalidated;                   // %new on SBAbstractWindowSceneDelegate below
- (void)pointerDidMoveToFromWindowScene:(id)from toWindowScene:(id)to;
- (void)multiDisplayUserInteractionCoordinator:(id)c updatedActiveWindowScene:(id)scene;
@end

// Classes we hook (declaration only; no @implementation, so nothing is registered with the runtime on any build).
@interface SpringBoard : NSObject @end
@interface SBWindowScene : NSObject @end
@interface SBWindowSceneManager : NSObject @end
@interface SBAbstractWindowSceneDelegate : NSObject @end
@interface SBExternalDisplayWindowSceneDelegate : NSObject @end
@interface SBEmbeddedDisplayWindowSceneDelegate : NSObject @end
@interface SBWorkspaceKeyboardFocusController : NSObject @end
@interface SBControlCenterController : NSObject @end
@interface SBFluidSwitcherGestureManager : NSObject @end
@interface BKSMousePointerService : NSObject @end

// ------------------------------------------------------------------------------------------------ small helpers

static char kBPInvalidating, kBPInvalidated, kBPDelegateInvalidated, kBPSuppressAssertion, kBPCoordinator;

static BOOL BP_GetFlag(id obj, const void *key) {
    if (!obj) return NO;
    return [objc_getAssociatedObject(obj, key) boolValue];
}
static void BP_SetFlag(id obj, const void *key, BOOL v) {
    if (!obj) return;                                         // objc_setAssociatedObject(nil, k, non-nil) would crash
    objc_setAssociatedObject(obj, key, v ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// SBWindowScene._isInvalidating / _isInvalidated (16.2 0x1a0 / 0x1a1) live in associated objects here.
static BOOL BP_IsInvalidated(id ws)  { return BP_GetFlag(ws, &kBPInvalidated); }
static BOOL BP_IsInvalidating(id ws) { return BP_GetFlag(ws, &kBPInvalidating) && !BP_GetFlag(ws, &kBPInvalidated); }  // as 16.2 0x1c77f77f0

static NSString *BP_MethodologyString(long long m) { return m == 0 ? @"keyboard" : @"touch + pointer"; }     // 16.2 0x1c74241b8

static id BP_CastTo(id obj, NSString *className) {
    Class c = NSClassFromString(className);
    return (c && [obj isKindOfClass:c]) ? obj : nil;
}
static id BP_WindowSceneOf(id scene) { return BP_CastTo(scene, @"SBWindowScene"); }

static id BP_Application(void) {
    Class ua = NSClassFromString(@"UIApplication");
    return [ua respondsToSelector:@selector(sharedApplication)] ? [ua sharedApplication] : nil;
}
static id BP_WindowSceneManager(void) {
    id app = BP_Application();
    return [app respondsToSelector:@selector(windowSceneManager)] ? [app windowSceneManager] : nil;
}
static id BP_KeyboardFocusController(void) {
    Class mw = NSClassFromString(@"SBMainWorkspace");
    id ws = [mw respondsToSelector:@selector(sharedInstanceIfExists)] ? [mw sharedInstanceIfExists] : nil;
    return [ws respondsToSelector:@selector(keyboardFocusController)] ? [ws keyboardFocusController] : nil;
}

// ================================================================================================ coordinator
// PARTIAL: stands in for SBMultiDisplayUserInteractionCoordinator (+ its three event sniffers), 16.2 section 5.3.
// Not a subclass of anything private and deliberately NOT named like the 16.2 class (a duplicate class name would
// misbehave if the dylib were ever loaded into a 16.2 SpringBoard).
// PARTIAL because the pointer-interaction qualifying test is decoded literally from 16.2 (`[touch type] == 0` for a
// pointer touch) and has not been observed on a device; touch-driven tracking does not depend on it.

@interface BPMultiDisplayCoordinator : NSObject
@property (nonatomic, weak) id delegate;                    // object answering windowSceneForDisplayIdentity: (SBWindowSceneManager)
@property (nonatomic, weak, readonly) id activeWindowScene;                           // 16.2 +0x8
@property (nonatomic, weak, readonly) id activePointerWindowScene;                    // 16.2 +0x10
@property (nonatomic, weak, readonly) id activeTouchDownOriginatedWindowScene;        // 16.2 +0x20
- (void)windowSceneDidConnect:(id)windowScene;
- (void)windowSceneDidDisconnect:(id)windowScene;
- (void)handleSendEvent:(id)event;
- (void)addActiveDisplayWindowSceneObserver:(id)observer;
- (void)removeActiveDisplayWindowSceneObserver:(id)observer;
- (void)addPointerInteractionObserver:(id)observer;
- (void)removePointerInteractionObserver:(id)observer;
@end

@implementation BPMultiDisplayCoordinator {
    __weak id _activeDisplayWS;
    __weak id _activePointerWS;
    __weak id _touchDownWS;
    NSHashTable *_connected;                                // weak set of scenes that "have sniffers" (16.2: _sceneToEventSniffers keys)
    NSHashTable *_activeObservers;                          // weak
    NSHashTable *_pointerObservers;                         // weak
}

- (instancetype)init {
    if ((self = [super init])) {
        _connected = [NSHashTable weakObjectsHashTable];
        _activeObservers = [NSHashTable weakObjectsHashTable];
        _pointerObservers = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (id)activeWindowScene { return _activeDisplayWS; }
- (id)activePointerWindowScene { return _activePointerWS; }
- (id)activeTouchDownOriginatedWindowScene { return _touchDownWS; }

- (void)addActiveDisplayWindowSceneObserver:(id)o { if (o) [_activeObservers addObject:o]; }
- (void)removeActiveDisplayWindowSceneObserver:(id)o { if (o) [_activeObservers removeObject:o]; }
- (void)addPointerInteractionObserver:(id)o { if (o) [_pointerObservers addObject:o]; }
- (void)removePointerInteractionObserver:(id)o { if (o) [_pointerObservers removeObject:o]; }

// 16.2 0x1c795e314
- (void)windowSceneDidConnect:(id)ws {
    if (ws) [_connected addObject:ws];
}

// 16.2 0x1c795e43c
- (void)windowSceneDidDisconnect:(id)ws {
    if (!ws) return;
    [_connected removeObject:ws];
    if (_touchDownWS == ws) {
        BP_Log(@"coordinator: clearing pointer touch down window scene %p - scene disconnected", ws);
        _touchDownWS = nil;
    }
    if (_activeDisplayWS == ws) _activeDisplayWS = nil;
    if (_activePointerWS == ws) _activePointerWS = nil;
}

// 16.2 0x1c795df4c. Deviation: falls back to the first touch's window when the HID context id cannot be resolved.
- (id)_windowSceneForEvent:(id)event {
    id window = nil;
    static void *(*getAttrs)(BPIOHIDEventRef);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ getAttrs = (void *(*)(BPIOHIDEventRef))dlsym(RTLD_DEFAULT, "BKSHIDEventGetBaseAttributes"); });
    if (getAttrs && [event respondsToSelector:@selector(_hidEvent)]) {
        BPIOHIDEventRef hid = [event _hidEvent];
        id attrs = hid ? (__bridge id)getAttrs(hid) : nil;
        unsigned int ctx = [attrs respondsToSelector:@selector(contextID)] ? [attrs contextID] : 0;
        Class uw = NSClassFromString(@"UIWindow");
        if (ctx && [uw respondsToSelector:@selector(_windowWithContextId:)]) window = [uw _windowWithContextId:ctx];
    }
    id identity = [window respondsToSelector:@selector(_fbsDisplayIdentity)] ? [window _fbsDisplayIdentity] : nil;
    id d = self.delegate;
    id ws = (identity && [d respondsToSelector:@selector(windowSceneForDisplayIdentity:)]) ? [d windowSceneForDisplayIdentity:identity] : nil;
    if (!ws && [event respondsToSelector:@selector(allTouches)]) {
        for (id t in [event allTouches]) {
            id w = [t respondsToSelector:@selector(window)] ? [t window] : nil;
            ws = [w respondsToSelector:@selector(windowScene)] ? [w windowScene] : nil;
            if (ws) break;
        }
    }
    return ws;
}

// 16.2 0x1c795dd70 (handleSendEvent:) + the three sniffers' handleEvent: (0x1c795eb54 / 0x1c795ed7c / 0x1c795ef94).
- (void)handleSendEvent:(id)event {
    if (!event) return;
    @try {
        if (![event respondsToSelector:@selector(allTouches)]) return;
        NSArray *touches = [[event allTouches] allObjects];
        if (!touches.count) return;                               // non-touch events (keys, scroll, ...) stop here, cheaply
        id ws = [self _windowSceneForEvent:event];
        if (!ws || ![_connected containsObject:ws]) return;
        // UITouchPhase: Began 0, Stationary 2, Ended 3, Cancelled 4.  UITouchType: Direct 0, Indirect 1, Pencil 2, IndirectPointer 3.

        // sniffer 1: _SBPointerTouchDownEventSniffer (touch events only; first pointer touch decides)
        if ([event type] == 0) {
            for (id t in touches) {
                if (![t _isPointerTouch]) continue;
                long long ph = [t phase];
                if (ph == 0) [self _pointerTouchDownInScene:ws];
                else if (ph == 3) [self _pointerTouchUp];
                break;
            }
        }
        // sniffer 2: _SBTouchInteractionEventSniffer
        for (id t in touches) {
            if ([t _isPointerTouch]) continue;
            long long ph = [t phase], ty = [t type];
            BOOL activePhase = (ph == 4) ? NO : (ph != 2);
            if (ty == 1 || !activePhase || ty == 3) continue;
            [self _handleActiveDisplayQualifyingEventInWindowScene:ws source:@"touch"];
            break;
        }
        // sniffer 3: _SBPointerInteractionEventSniffer
        for (id t in touches) {
            if (![t _isPointerTouch]) continue;
            id v = [t view];
            CGPoint prev = [t previousLocationInView:v], cur = [t locationInView:v];
            BOOL same = (prev.x == cur.x) && (prev.y == cur.y);
            long long ph = [t phase];
            BOOL activePhase = (ph == 4) ? NO : (ph != 2);
            if (same || !activePhase) continue;
            if ([t type] != 0) continue;                    // as decoded from 16.2; see file header (PARTIAL)
            [self _pointerMovedInScene:ws];
            break;
        }
    } @catch (NSException *e) {
        BP_Log(@"coordinator: exception in handleSendEvent: %@", e);
    }
}

// 16.2 0x1c795e598 / 0x1c795e6f0
- (void)_pointerTouchDownInScene:(id)ws {
    if (!ws) return;
    BP_Log(@"coordinator: %s pointer touch down window scene %p (previous %p)", _touchDownWS ? "re-setting" : "setting", ws, _touchDownWS);
    _touchDownWS = ws;
}
- (void)_pointerTouchUp {
    if (!_touchDownWS) return;
    BP_Log(@"coordinator: clearing pointer touch down window scene %p - touch up", _touchDownWS);
    _touchDownWS = nil;
}

// 16.2 0x1c795e838
- (void)_pointerMovedInScene:(id)ws {
    id old = _activePointerWS;
    if (!ws) return;
    _activePointerWS = ws;
    if (ws != old) {
        BP_Log(@"coordinator: updating active pointer display from %p to %p", old, ws);
        for (id o in [_pointerObservers allObjects])
            if ([o respondsToSelector:@selector(pointerDidMoveToFromWindowScene:toWindowScene:)])
                [o pointerDidMoveToFromWindowScene:old toWindowScene:ws];
    }
    [self _handleActiveDisplayQualifyingEventInWindowScene:ws source:@"pointer"];
}

// 16.2 0x1c795e014
- (void)_handleActiveDisplayQualifyingEventInWindowScene:(id)ws source:(NSString *)source {
    id old = _activeDisplayWS;
    if (!ws) return;
    _activeDisplayWS = ws;
    if (old == ws) return;
    BP_Log(@"[%@] updating active display from %p to %p source: %@", BP_MethodologyString(1), old, ws, source);
    for (id o in [_activeObservers allObjects])
        if ([o respondsToSelector:@selector(multiDisplayUserInteractionCoordinator:updatedActiveWindowScene:)])
            [o multiDisplayUserInteractionCoordinator:self updatedActiveWindowScene:ws];
}

@end

// Lazily created, owned (associated) by the window scene manager, like 16.2's SpringBoard ivar (section 5.1).
// Main thread only. When created late it registers the scenes that are already connected.
static BPMultiDisplayCoordinator *BP_Coordinator(BOOL create) {
    id mgr = BP_WindowSceneManager();
    if (!mgr) return nil;
    BPMultiDisplayCoordinator *c = objc_getAssociatedObject(mgr, &kBPCoordinator);
    if (c || !create) return c;
    if (![NSThread isMainThread]) return nil;
    c = [[BPMultiDisplayCoordinator alloc] init];
    c.delegate = mgr;
    objc_setAssociatedObject(mgr, &kBPCoordinator, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([mgr respondsToSelector:@selector(connectedWindowScenes)])
        for (id ws in [mgr connectedWindowScenes]) [c windowSceneDidConnect:ws];
    BP_Log(@"coordinator created (%p) for window scene manager %p", c, mgr);
    return c;
}

// Scene validation shared by the active-display paths: 16.2 -[SBWindowSceneManager _validateSuggestedActiveWindowScene:
// usingMethodology:] (0x1c74bf960). Deviation: if there is no embedded scene the suggestion is returned unchanged.
static id BP_ValidateActiveScene(id mgr, id scene, long long methodology) {
    BOOL ing = BP_IsInvalidating(scene), ed = BP_IsInvalidated(scene);
    if (!ing && !ed) return scene;
    id embedded = [mgr respondsToSelector:@selector(embeddedDisplayWindowScene)] ? [mgr embeddedDisplayWindowScene] : nil;
    BP_Log(@"[%@] focus scene <%p> is %s, falling back to the embedded scene <%p> as the active scene",
           BP_MethodologyString(methodology), scene, ed ? "invalidated" : "invalidating", embedded);
    return embedded ?: scene;
}

// ================================================================================================ direct-function hook
// PARTIAL: -[SBWorkspaceKeyboardFocusController _reevaluatePolicyAndUpdateRulesIfNeeded] is an objc_direct method in
// 16.0: not in the class method list, called with `bl` from 11 sites, signature (id self) with NO _cmd.
// 16.0 (20A8372) unslid cache address 0x1c6321b74. 16.2 adds, at its top, "if suppression assertion active: log + return".
// This function hook adds exactly that. Without it suppressKeyboardFocusEvaluationForReason: is advisory only (the
// final re-evaluation still happens, evaluation during teardown is just not frozen), which is also what 16.0 does today.

extern void MSHookFunction(void *symbol, void *replace, void **result);

static void (*orig_reevaluate)(id self);
static BOOL BP_SuppressionActive(id kfc) {
    id a = kfc ? objc_getAssociatedObject(kfc, &kBPSuppressAssertion) : nil;
    return a && [a respondsToSelector:@selector(isActive)] && [a isActive];
}
static void hook_reevaluate(id self) {
    if (self && BP_On(F_DISCONNECT) && BP_SuppressionActive(self)) {
        BP_Log(@"kfc: suppressing evaluation due to reasons: %@", [objc_getAssociatedObject(self, &kBPSuppressAssertion) reasons]);
        return;
    }
    orig_reevaluate(self);
}

static BOOL BP_InstallReevaluateHook(void) {
    static const uintptr_t kVm = 0x1c6321b74;                 // 20A8372 vmaddr (unslid)
    static const uint32_t kPrologue[7] = {                    // cbz x0,..; pacibsp; sub sp,sp,#0x30; stp x20,x19,[sp,#0x10];
        0xb4000440, 0xd503237f, 0xd100c3ff, 0xa9014ff4,       // stp fp,lr,[sp,#0x20]; add fp,sp,#0x20; mov x19,x0
        0xa9027bfd, 0x910083fd, 0xaa0003f3 };
    intptr_t slide = 0;
    BOOL found = NO;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "/SpringBoard.framework/SpringBoard")) { slide = _dyld_get_image_vmaddr_slide(i); found = YES; break; }
    }
    if (!found) { BP_Log(@"direct hook: SpringBoard.framework image not found, not hooking"); return NO; }
    uintptr_t addr = kVm + (uintptr_t)slide;
    if (memcmp((const void *)addr, kPrologue, sizeof kPrologue) != 0) {
        BP_Log(@"direct hook: prologue mismatch at %p, not hooking (suppression stays advisory)", (void *)addr);
        return NO;
    }
    MSHookFunction((void *)addr, (void *)hook_reevaluate, (void **)&orig_reevaluate);   // arm64e: raw code address, no PAC signing
    BP_Log(@"direct hook: _reevaluatePolicyAndUpdateRulesIfNeeded hooked at %p", (void *)addr);
    return orig_reevaluate != NULL;
}

// Gesture gating helper (section 7): reject a pan gesture when the pointer touch-down started on another display.
static BOOL BP_PanFromOtherDisplay(id gesture, id ownScene) {
    Class pan = NSClassFromString(@"UIPanGestureRecognizer");
    if (!pan || ![gesture isKindOfClass:pan] || !ownScene) return NO;      // deviation: nil own scene does not reject
    id td = [BP_Coordinator(NO) activeTouchDownOriginatedWindowScene];
    return td && ![ownScene isEqual:td];
}

// ================================================================================================ the hooks

%group G4

// ---------------------------------------------------------------------------------------------- SBWindowScene state
// PORTABLE (section 3). Selector names match 16.2 so later code can use them. No -invalidate is added on purpose (see
// BP_MarkInvalidated); setInvalidating:NO after YES is ignored instead of trapping like 16.2.
%hook SBWindowScene

%new
- (BOOL)isInvalidating { return BP_IsInvalidating(self); }

%new
- (BOOL)isInvalidated { return BP_IsInvalidated(self); }

%new
- (void)setInvalidating:(BOOL)invalidating {
    if (BP_GetFlag(self, &kBPInvalidating) && !invalidating) {
        BP_Log(@"ignoring setInvalidating:NO on invalidating scene %p (16.2 would crash here)", self);
        return;
    }
    BP_SetFlag(self, &kBPInvalidating, invalidating);
}

%end

// PORTABLE (section 2.1): SBAbstractWindowSceneDelegate._invalidated (16.2 0x40), informational only.
%hook SBAbstractWindowSceneDelegate

%new
- (BOOL)isInvalidated { return BP_GetFlag(self, &kBPDelegateInvalidated); }

%new
- (void)setInvalidated:(BOOL)invalidated { BP_SetFlag(self, &kBPDelegateInvalidated, invalidated); }

%end

// ---------------------------------------------------------------------------------------------- keyboard focus controller
%hook SBWorkspaceKeyboardFocusController

// PORTABLE (API), PARTIAL (effect needs BP_InstallReevaluateHook): section 4.1, 16.2 0x1c77c27fc.
%new
- (id)suppressKeyboardFocusEvaluationForReason:(NSString *)reason {
    id assertion = objc_getAssociatedObject(self, &kBPSuppressAssertion);
    if (!assertion) {
        Class BSCA = NSClassFromString(@"BSCompoundAssertion");
        SEL make = NSSelectorFromString(@"assertionWithIdentifier:stateDidChangeHandler:");
        if (![BSCA respondsToSelector:make]) return nil;
        __weak id weakSelf = self;
        void (^handler)(id) = ^(id a) {
            if ([a isActive]) return;
            BP_Log(@"kfc: finished suppressing keyboard focus evaluation, time to re-evaluate");
            dispatch_block_t go = ^{ id s = weakSelf; if (s && BP_On(F_DISCONNECT)) [s updateKeyboardFocusDeferringRules]; };
            if ([NSThread isMainThread]) go(); else dispatch_async(dispatch_get_main_queue(), go);
        };
        assertion = ((id (*)(id, SEL, id, id))objc_msgSend)(BSCA, make, @"SBWorkspaceKeyboardFocusSuppressEvaluation", handler);
        if (!assertion) return nil;
        objc_setAssociatedObject(self, &kBPSuppressAssertion, assertion, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [assertion acquireForReason:reason ?: @"(nil reason)"];
}

// PORTABLE: section 4.2. 16.0 implementation is a single `ret`, so there is nothing to preserve; %orig is kept anyway.
// Uses the ObjC-visible removeKeyboardFocusFromScene: instead of the direct _removeSceneFromRecents... methods.
- (void)windowSceneDidDisconnect:(id)ws {
    %orig;
    if (!ws || !BP_On(F_DISCONNECT)) return;
    BP_Log(@"kfc: windowSceneDidDisconnect: <%p> %s the focused window scene", ws, [self windowSceneWithFocus] == ws ? "is" : "is NOT");
    void (^work)(void) = ^{
        id sm = [ws respondsToSelector:@selector(sceneManager)] ? [ws sceneManager] : nil;
        NSMutableArray *scenes = [NSMutableArray array];
        if ([sm respondsToSelector:@selector(externalForegroundApplicationSceneHandles)]) {
            Class fbScene = NSClassFromString(@"FBScene");
            for (id h in [sm externalForegroundApplicationSceneHandles]) {
                id s = [h respondsToSelector:@selector(scene)] ? [h scene] : nil;
                if (s && fbScene && [s isKindOfClass:fbScene]) [scenes addObject:s];      // 16.0 asserts non-nil FBScene
            }
        }
        for (id s in scenes) [self removeKeyboardFocusFromScene:s];
        if ([sm respondsToSelector:@selector(removeObserver:)]) [sm removeObserver:self];   // undo windowSceneDidConnect:
        [self updateKeyboardFocusDeferringRules];                                           // suppressed while the delegate holds its assertion
        if ([self windowSceneWithFocus] == ws) BP_Log(@"kfc: still focusing the disconnected window scene %p", ws);
    };
    if ([NSThread isMainThread]) work(); else dispatch_async(dispatch_get_main_queue(), work);
}

%end

// ---------------------------------------------------------------------------------------------- window scene manager
%hook SBWindowSceneManager

// PORTABLE (invalidation fallback) + PARTIAL (touch + pointer methodology): sections 5.3 / 5.4.
- (id)activeDisplayWindowScene {
    id keyboardScene = %orig;                                   // 16.0: kfc.windowSceneWithFocus ?: embedded
    BOOL fix = BP_On(F_DISCONNECT), touch = BP_On(F_ACTIVEDISPLAY);
    if (!fix && !touch) return keyboardScene;
    id suggestion = keyboardScene;
    long long methodology = 0;
    if (touch) {
        id fromUser = [BP_Coordinator(NO) activeWindowScene];
        if (fromUser) { suggestion = fromUser; methodology = 1; }   // deviation: until the first qualifying event, keep keyboard-following
    }
    return BP_ValidateActiveScene(self, suggestion, methodology);
}

// Fidelity helpers with the 16.2 selectors (used by other groups' hooks if any).
%new
- (id)activeDisplayWindowSceneFollowingKeyboard {
    return BP_ValidateActiveScene(self, [BP_KeyboardFocusController() windowSceneWithFocus], 0);
}

%new
- (id)activeDisplayWindowSceneFollowingUserInteraction {
    return BP_ValidateActiveScene(self, [BP_Coordinator(YES) activeWindowScene], 1);
}

%new
- (id)userInteractionCoordinator { return BP_Coordinator(YES); }

%end

// ---------------------------------------------------------------------------------------------- SpringBoard application
%hook SpringBoard

// PARTIAL: section 5.2. 16.0 SpringBoard has no sendEvent: override (inherited from UIApplication; Logos adds the
// override). Runs before %orig like 16.2. Cost per event is a couple of selector sends; exceptions are contained.
- (void)sendEvent:(id)event {
    if (BP_On(F_ACTIVEDISPLAY)) {
        BPMultiDisplayCoordinator *c = BP_Coordinator(YES);
        [c handleSendEvent:event];
    }
    %orig;
}

%new
- (id)multiDisplayUserInteractionCoordinator { return BP_Coordinator(YES); }

%end

// ---------------------------------------------------------------------------------------------- connect path
// PARTIAL: section 2.3. 16.2 calls [coordinator windowSceneDidConnect:] as the last statement of both configure methods.
%hook SBEmbeddedDisplayWindowSceneDelegate
- (void)_configureForConnectingWindowScene:(id)scene windowSceneContext:(id)context {
    %orig;
    if (BP_On(F_ACTIVEDISPLAY)) [BP_Coordinator(YES) windowSceneDidConnect:BP_WindowSceneOf(scene)];
}
%end

// ---------------------------------------------------------------------------------------------- disconnect path
// PARTIAL: section 2.1. Wrapper around the 16.0 method. What the wrapper reproduces: the focus-evaluation assertion
// for the whole teardown, the invalidating flag before and the invalidated flag after, the coordinator hand-off, the
// cover sheet controller observer removal / release. What it cannot reproduce: 16.2 calls [super sceneDidDisconnect:]
// near the END (16.0 calls it FIRST, so in 16.0 SBWindowSceneManager._sceneDidDisconnect: removes the scene from
// connectedWindowScenes before the external-specific teardown). The invalidating flag makes that ordering safe for
// every consumer that goes through activeDisplayWindowScene.
%hook SBExternalDisplayWindowSceneDelegate

// connect side of the coordinator hand-off (16.2: last statement of _configureForConnectingWindowScene:windowSceneContext:)
- (void)_configureForConnectingWindowScene:(id)scene windowSceneContext:(id)context {
    %orig;
    if (BP_On(F_ACTIVEDISPLAY)) [BP_Coordinator(YES) windowSceneDidConnect:BP_WindowSceneOf(scene)];
}

- (void)sceneDidDisconnect:(id)scene {
    if (!BP_On(F_DISCONNECT)) { %orig; return; }

    id ws = BP_WindowSceneOf(scene);
    id kfc = BP_KeyboardFocusController();
    id assertion = nil;
    if ([kfc respondsToSelector:@selector(suppressKeyboardFocusEvaluationForReason:)]) {
        id ident = ([[ws screen] respondsToSelector:@selector(displayIdentity)]) ? [[ws screen] displayIdentity] : ws;
        NSString *reason = [NSString stringWithFormat:@"%@ - %@", NSStringFromClass([self class]), ident];   // 16.2 reason format
        assertion = [kfc suppressKeyboardFocusEvaluationForReason:reason];
    }
    if (ws && [ws respondsToSelector:@selector(setInvalidating:)]) [ws setInvalidating:YES];
    BOOL hadDisplayConfiguration = ![[ws screen] respondsToSelector:@selector(displayConfiguration)] || [[ws screen] displayConfiguration] != nil;
    [BP_Coordinator(NO) windowSceneDidDisconnect:ws];

    %orig;

    // PARTIAL (opt-in, MEDIUM confidence): 16.0 only tells the switcher coordinator when the screen still has a display
    // configuration; 16.2 always does. If it was skipped, do it now.
    if (!hadDisplayConfiguration && ws && BP_G4_OptIn("discswitch")) {
        Class sc = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
        id coord = [sc respondsToSelector:@selector(sharedInstance)] ? [sc sharedInstance] : nil;
        if ([coord respondsToSelector:@selector(windowSceneDidDisconnect:)]) {
            BP_Log(@"disconnect: switcher coordinator was skipped by the displayConfiguration gate, calling it now");
            [coord windowSceneDidDisconnect:scene];
        }
    } else if (!hadDisplayConfiguration) {
        BP_Log(@"disconnect: display configuration was nil, 16.0 skipped the switcher coordinator (opt-in discswitch not enabled)");
    }

    // 16.2 -[SBExternalDisplayCoverSheetController invalidate] (new) = removeObserver:, then the delegate drops the controller.
    @try {
        id cover = [self valueForKey:@"coverSheetController"];             // ivar _coverSheetController through KVC (no offsets)
        if (cover) {
            [[NSNotificationCenter defaultCenter] removeObserver:cover];
            [self setValue:nil forKey:@"coverSheetController"];
        }
    } @catch (NSException *e) {
        BP_Log(@"disconnect: cover sheet controller release skipped: %@", e);
    }

    [assertion invalidate];                                                // lets the kfc re-evaluate exactly once
    BP_SetFlag(ws, &kBPInvalidated, YES);                                  // 16.2 [ws invalidate]
    if ([self respondsToSelector:@selector(setInvalidated:)]) [self setInvalidated:YES];
}

%end

// ---------------------------------------------------------------------------------------------- gesture gating
// PARTIAL: section 7. Needs the coordinator; the helper is defined above %group G4.

%hook SBControlCenterController
- (BOOL)gestureRecognizerShouldBegin:(id)gesture {
    if (BP_On(F_GESTUREGATE) && BP_On(F_ACTIVEDISPLAY) && [self respondsToSelector:@selector(_controlCenterWindow)]) {
        id own = [[self _controlCenterWindow] respondsToSelector:@selector(windowScene)] ? [[self _controlCenterWindow] windowScene] : nil;
        if (BP_PanFromOtherDisplay(gesture, own)) { BP_Log(@"gesture gate: control center gesture NotForCurrentDisplay"); return NO; }
    }
    return %orig;
}
%end

%hook SBFluidSwitcherGestureManager
- (BOOL)gestureRecognizerShouldBegin:(id)gesture {
    if (BP_On(F_GESTUREGATE) && BP_On(F_ACTIVEDISPLAY)) {
        Ivar iv = class_getInstanceVariable([self class], "_switcherController");     // 16.2 offset 0x10; found by name only
        id sw = iv ? object_getIvar(self, iv) : nil;
        id own = [sw respondsToSelector:@selector(windowScene)] ? [sw windowScene] : nil;
        if (BP_PanFromOtherDisplay(gesture, own)) { BP_Log(@"gesture gate: switcher gesture NotForCurrentDisplay"); return NO; }
    }
    return %orig;
}
%end

// ---------------------------------------------------------------------------------------------- pointer lock display
// PARTIAL: section 6, -[SBLockedPointerManager _queue_lockPointerForSceneIdentifier:]. 16.0 passes display:nil
// to BKSMousePointerService; 16.2 passes the manager's own window scene's display (hardwareIdentifier). The 16.0 manager
// only ever serves the embedded display, so substitute the embedded display's identifier. Matches only the manager's
// reason string and options mask 2. MEDIUM confidence that nil meant "all displays".
%hook BKSMousePointerService
- (id)pointerSuppressionAssertionOnDisplay:(id)display forReason:(NSString *)reason withOptionsMask:(unsigned long long)mask {
    if (!display && mask == 2 && BP_On(F_LOCKEDPTR) && [reason hasPrefix:@"Scene "] && [reason hasSuffix:@" requested locked pointer"]) {
        id mgr = BP_WindowSceneManager();
        id embedded = [mgr respondsToSelector:@selector(embeddedDisplayWindowScene)] ? [mgr embeddedDisplayWindowScene] : nil;
        id cfg = [embedded respondsToSelector:@selector(_fbsDisplayConfiguration)] ? [embedded _fbsDisplayConfiguration] : nil;
        id hw = [cfg respondsToSelector:@selector(hardwareIdentifier)] ? [cfg hardwareIdentifier] : nil;
        if ([hw isKindOfClass:[NSString class]]) {
            BP_Log(@"pointer lock: scoping suppression assertion to embedded display %@", hw);
            return %orig(hw, reason, mask);
        }
    }
    return %orig;
}
%end

%end // %group G4

// ================================================================================================ entry
// Call from Tweak.x's %ctor, after the build check and the existing %init.
void BP_G4_Setup(void) {
    %init(G4);
    // MSHookFunction on a non-ObjC function: opt-in until it has been seen working on Dopamine/arm64e.
    if (BP_G4_OptIn("directhook")) BP_InstallReevaluateHook();
    else BP_Log(@"direct hook not installed (create Backport162.on.directhook to enable); suppression is advisory");
}

// ================================================================================================ NOT PORTABLE
// Documented, deliberately not implemented. See the .md sections for the 16.2 behaviour.
#if 0

// NOT PORTABLE: per-window-scene SBLockedPointerManager (section 6): initWithWindowScene:, invalidate,
// _notInvalidated_updateLockForLayoutState:, clientWithSceneIdentifier:suppressPreferredLockStatus:,
// sceneHandle:didDestroyScene:, creation in SBAbstractWindowSceneDelegate _configureForConnectingWindowScene: and storage
// in SBWindowSceneContext. The 16.0 class is hard-wired to SBMainDisplaySceneManager (-initWithSceneManager:,
// _layoutStateTransitionCoordinator, currentLayoutState) and to a SpringBoard ivar; an external display needs its own
// layout-state provider / transition coordinator observers that only exist after the 16.2 Stage Manager plumbing.
// Re-implementing 14 methods (about 600 instructions) as a new class is possible but touches PSPointerClientController,
// BKS assertions and layout transitions on the main queue: too risky for a draft.

// NOT PORTABLE: _UIPointerUnlockAction (UIActionType 0x32) handling in SBSceneManager _handleAction:forScene: and the
// "suppress preferred lock status until the user selects the window" behaviour (SBFluidSwitcherViewController
// didSelectContainer:modifierFlags:). Depends on the per-scene manager above.

// NOT PORTABLE: per-display SpringBoard focus locks (kfc lockFocusToSpringBoardWindowScene:forReason: reason->scene map,
// _keyboardFocusPolicyForCurrentUIStateWithAppFocusTarget: and _applyDeferringRulesForPolicy: filtering lock reasons by
// the app target's display / activeDisplayWindowSceneFollowingUserInteraction). Both are direct methods of 750 and
// 1070 instructions with no ObjC entry point to wrap.

// NOT PORTABLE: moving the disconnected display's windows to the iPad (SBMainSwitcherControllerCoordinator
// windowSceneDidDisconnect: 106 -> 275 instructions; takeScene:fromSceneManager: callouts; main-workspace transition
// with windowPickerRole / unlockedEnvironmentMode). Belongs with the Stage Manager groups.

// NOT PORTABLE: SBSystemPointerInteractionManager -initWithMultiDisplayUserInteractionCoordinator: /
// activePointerWindowScene / pointer observers, and the changed delegate selector
// shouldBeginPointerInteractionRequest:atLocation:forView:; every registering view would have to adopt it.
// The coordinator above already offers addPointerInteractionObserver: for a future port.

#endif
