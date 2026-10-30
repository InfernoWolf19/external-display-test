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
//      F_DISCSWITCH was OPT-IN in the draft; it is default ON now (kill switch Backport162.off.discswitch).
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

// `type` is declared with different return types in Foundation, so message it explicitly.
static inline long long BP_G4_Type(id obj) {
    return ((long long (*)(id, SEL))objc_msgSend)(obj, @selector(type));
}

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
    // one cache slot per name (a shared slot would hand one name's answer to another)
    static struct { const char *name; uint64_t next; BOOL last; } slots[8];
    int i = 0;
    while (i < 8 && slots[i].name && strcmp(slots[i].name, name) != 0) i++;
    if (i == 8) return NO;
    if (!slots[i].name) slots[i].name = name;            // names are string literals
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < slots[i].next) return slots[i].last;
    slots[i].next = t + 1000000000ull;
    char path[1200];
    snprintf(path, sizeof path, "%s%s", base, name);
    slots[i].last = access(path, F_OK) == 0;
    return slots[i].last;
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
- (id)activeDisplayWindowSceneFollowingKeyboard;            // %new on SBWindowSceneManager below
- (id)activeDisplayWindowSceneFollowingUserInteraction;     // %new on SBWindowSceneManager below
- (id)systemGestureManager;                                 // SBWindowScene
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
// The sniffer tests are the literal 16.2 ones (checked against 0x1c795eb54 / 0x1c795ed7c / 0x1c795ef94 in 0.7.0), including
// `[touch type] == 0` for the pointer-interaction sniffer.

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
    NSUInteger _holdFlipLogged;                             // P5 step 2: ignored moves logged since the last touch down (first 12)
    NSUInteger _flipProbeCount;                             // P5 step 1 (specs/FINDINGS-DRAG-LOOP-0.7.9.md): flips of the active pointer display since the last pointer touch down (log-only probe)
    __unsafe_unretained id _probeTouch;                     // the touch whose move is being handled (valid only inside handleSendEvent:)
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

// 16.2 0x1c795df4c (literal: HID context id -> window -> display identity -> scene; no other fallback).
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
        if (BP_G4_Type(event) == 0) {
            for (id t in touches) {
                if (![t _isPointerTouch]) continue;
                long long ph = [t phase];
                if (ph == 0) [self _pointerTouchDownInScene:ws];
                else if (ph == 3) [self _pointerTouchUp];              // 16.2 0x1c795ec6c: only UITouchPhaseEnded
                break;
            }
        }
        // sniffer 2: _SBTouchInteractionEventSniffer
        for (id t in touches) {
            if ([t _isPointerTouch]) continue;
            long long ph = [t phase], ty = BP_G4_Type(t);
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
            if (BP_G4_Type(t) != 0) continue;                         // 16.2 0x1c795f0d4: `cbz type` is the qualifying case, literally
            _probeTouch = t;
            [self _pointerMovedInScene:ws];
            _probeTouch = nil;
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
    _flipProbeCount = 0;
    _holdFlipLogged = 0;
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
    // P5 step 2 (DEVIATION from 16.2, which has no such test: 16.2 0x1c795e838 stores the scene unconditionally).  While a pointer button is held the touch route is pinned to
    // the press scene (X9Pin `pinbuttondown`), and every move then arrives twice: once for the press scene (location inside its window) and once for the scene of the HID
    // context of the other display, with the location in THAT window's coordinates, outside its bounds (device log S/u6/3: 170 flips in 2 s, a cross-display drop ignored
    // because the gesture ran on the wrong display).  Such an event does not say that the pointer is over that display.  The test is by location, not by scene equality, so
    // the first real crossing (the other scene's event inside its own window) still switches the display.  Switch p5_holdflip (default on).
    if (_touchDownWS && _probeTouch && BP_OnName("p5_holdflip")) {
        id t = _probeTouch;
        id v = [t respondsToSelector:@selector(view)] ? [t view] : nil;
        id w = [v respondsToSelector:@selector(window)] ? [v window] : ([t respondsToSelector:@selector(window)] ? [t window] : nil);
        SEL bs = NSSelectorFromString(@"bounds");
        if (w && [w respondsToSelector:bs] && [t respondsToSelector:@selector(locationInView:)]) {
            CGRect wb = ((CGRect (*)(id, SEL))objc_msgSend)(w, bs);
            CGPoint loc = [t locationInView:nil];       // WINDOW coordinates (nil view), the space of `wb`: the touch's own view can sit at an offset inside the window (a location in a subview's space would be compared with the window bounds)
            if (!CGRectContainsPoint(wb, loc)) {
                if (_holdFlipLogged < 12) {
                    _holdFlipLogged++;
                    BP_Log(@"coordinator: hold-flip guard %lu/12: pointer move for window scene %p ignored while a button is held (touch down scene %p), location (%.1f, %.1f) is outside its window bounds (%.0f x %.0f)",
                           (unsigned long)_holdFlipLogged, ws, _touchDownWS, loc.x, loc.y, wb.size.width, wb.size.height);
                }
                return;
            }
        }
    }
    _activePointerWS = ws;
    if (ws != old) {
        BP_Log(@"coordinator: updating active pointer display from %p to %p", old, ws);
        if (BP_LogEnabled() && _flipProbeCount < 12) {       // P5 step 1, log only: where is the pointer (in the view of the event's touch) when the display flips while a button is held?
            _flipProbeCount++;
            id t = _probeTouch;
            id v = [t respondsToSelector:@selector(view)] ? [t view] : nil;
            id w = [v respondsToSelector:@selector(window)] ? [v window] : ([t respondsToSelector:@selector(window)] ? [t window] : nil);
            CGPoint loc = [t respondsToSelector:@selector(locationInView:)] ? [t locationInView:nil] : CGPointZero;
            CGRect wb = [w respondsToSelector:NSSelectorFromString(@"bounds")] ? ((CGRect (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"bounds")) : CGRectZero;
            unsigned int cid = [w respondsToSelector:@selector(_contextId)] ? ((unsigned int (*)(id, SEL))objc_msgSend)(w, @selector(_contextId)) : 0;
            BP_Log(@"coordinator: flip probe %lu/12: ws %p touchDownWS %p (press scene %s) location in view (%.1f, %.1f) window %p bounds (%.0f, %.0f, %.0f x %.0f) %s contextID %u phase %lld",
                   (unsigned long)_flipProbeCount, ws, _touchDownWS, (_touchDownWS == ws) ? "= event scene" : "!= event scene", loc.x, loc.y, w, wb.origin.x, wb.origin.y, wb.size.width, wb.size.height,
                   CGRectContainsPoint(wb, loc) ? "location INSIDE the window" : "location OUTSIDE the window", cid, t ? (long long)[t phase] : -1LL);
        }
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

BOOL X7_TrackerScene(id manager, id *out);          // X7Keyboard.x

// Scene validation shared by the active-display paths: 16.2 -[SBWindowSceneManager _validateSuggestedActiveWindowScene:
// usingMethodology:] (0x1c74bf960): an invalidating or invalidated scene, and ALSO a nil suggestion (0x1c74bfb0c `cbz x19`),
// is replaced by the embedded scene.  So 16.2 never answers nil for the active display (about 60 callers rely on it).
static id BP_ValidateActiveScene(id mgr, id scene, long long methodology) {
    BOOL ing = BP_IsInvalidating(scene), ed = BP_IsInvalidated(scene);
    if (scene && !ing && !ed) return scene;
    id embedded = [mgr respondsToSelector:@selector(embeddedDisplayWindowScene)] ? [mgr embeddedDisplayWindowScene] : nil;
    if (scene) BP_Log(@"[%@] focus scene <%p> is %s, falling back to the embedded scene <%p> as the active scene",
                      BP_MethodologyString(methodology), scene, ed ? "invalidated" : "invalidating", embedded);
    return embedded;
}

// 16.2 -[SBWindowSceneManager activeDisplayWindowScene] (0x1c74bf1c4) reads [[SBExternalDisplaySettings rootSettings]
// activeDisplayTrackingMethodology] (default 1 = touch + pointer, 16.2 setDefaultValues).  `methodology0` is an opt-in
// alternative that forces 0 = keyboard following, which is how 16.0 behaves.
long long BP_G4_ActiveMethodology(void);
long long BP_G4_ActiveMethodology(void) {
    if (BP_OptInName("methodology0")) return 0;
    Class dom = NSClassFromString(@"SBExternalDisplaySettingsDomain");
    id root = [(id)dom respondsToSelector:@selector(rootSettings)] ? ((id (*)(id, SEL))objc_msgSend)((id)dom, @selector(rootSettings)) : nil;
    SEL ms = NSSelectorFromString(@"activeDisplayTrackingMethodology");
    return [root respondsToSelector:ms] ? ((long long (*)(id, SEL))objc_msgSend)(root, ms) : 1;
}

// ================================================================================================ direct-function hook
// PARTIAL: -[SBWorkspaceKeyboardFocusController _reevaluatePolicyAndUpdateRulesIfNeeded] is an objc_direct method in
// 16.0: not in the class method list, called with `bl` from 11 sites, signature (id self) with NO _cmd.
// 16.0 (20A8372) unslid cache address 0x1c6321b74. 16.2 adds, at its top, "if suppression assertion active: log + return".
// This function hook adds exactly that. Without it suppressKeyboardFocusEvaluationForReason: is advisory only (the
// final re-evaluation still happens, evaluation during teardown is just not frozen), which is also what 16.0 does today.

// MSHookFunction is looked up at run time: if the hooking library does not export it the feature simply stays off.
typedef void (*BP_MSHookFunction_t)(void *symbol, void *replace, void **result);

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

// Pointer helpers for arm64e: the hooking library may or may not hand back a signed function pointer, and may or may not
// strip the pointers it is given, so give it stripped pointers and re-sign what it returns (signing an already-correct
// pointer yields the same value).
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#define BP_STRIP(p)   ptrauth_strip((p), ptrauth_key_function_pointer)
#define BP_SIGN(p)    ptrauth_sign_unauthenticated(ptrauth_strip((p), ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0)
#else
#define BP_STRIP(p)   (p)
#define BP_SIGN(p)    (p)
#endif

static BOOL BP_InstallReevaluateHook(void) {
    // Patch at entry+4, AFTER the PC-relative `cbz x0` (a nil self still short-circuits there), so only
    // position-independent instructions are copied into the hooking library's trampoline.
    static const uintptr_t kVmEntry = 0x1c6321b74;            // 20A8372 vmaddr (unslid) of the function
    static const uint32_t kPrologue[7] = {                    // cbz x0,..; pacibsp; sub sp,sp,#0x30; stp x20,x19,[sp,#0x10];
        0xb4000440, 0xd503237f, 0xd100c3ff, 0xa9014ff4,       // stp fp,lr,[sp,#0x20]; add fp,sp,#0x20; mov x19,x0
        0xa9027bfd, 0x910083fd, 0xaa0003f3 };
    BP_MSHookFunction_t hookFn = (BP_MSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (!hookFn) { BP_Log(@"direct hook: MSHookFunction not available, not hooking"); return NO; }
    intptr_t slide = 0;
    BOOL found = NO;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "/SpringBoard.framework/SpringBoard")) { slide = _dyld_get_image_vmaddr_slide(i); found = YES; break; }
    }
    if (!found) { BP_Log(@"direct hook: SpringBoard.framework image not found, not hooking"); return NO; }
    uintptr_t entry = kVmEntry + (uintptr_t)slide;
    if (memcmp((const void *)entry, kPrologue, sizeof kPrologue) != 0) {      // all 7 words, including the cbz
        BP_Log(@"direct hook: prologue mismatch at %p, not hooking (suppression stays advisory)", (void *)entry);
        return NO;
    }
    void *target = BP_STRIP((void *)(entry + 4));
    void *replacement = BP_STRIP((void *)hook_reevaluate);
    void *original = NULL;
    hookFn(target, replacement, &original);
    if (!original) { BP_Log(@"direct hook: MSHookFunction returned no trampoline"); return NO; }
    orig_reevaluate = (void (*)(id))BP_SIGN(original);
    BP_Log(@"direct hook: _reevaluatePolicyAndUpdateRulesIfNeeded hooked at %p (entry+4)", target);
    return YES;
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
            dispatch_block_t go = ^{ id s = weakSelf; if (s) [s updateKeyboardFocusDeferringRules]; };   // not gated: the refocus must follow the suppression it undoes
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

// PORTED (0.7.0): sections 5.3 / 5.4, 16.2 0x1c74bf1c4: methodology 1 -> following user interaction, 0 -> following keyboard,
// each validated (invalidating / invalidated / nil -> embedded scene).  Off switches (`activedisplay`, `arrange`) give the
// stock 16.0 answer.
- (id)activeDisplayWindowScene {
    if (!BP_On(F_ACTIVEDISPLAY) || !BP_OnName("arrange")) return %orig;
    long long m = BP_G4_ActiveMethodology();
    id r = nil;
    if (m == 0) r = [self activeDisplayWindowSceneFollowingKeyboard];
    else if (m == 1) r = [self activeDisplayWindowSceneFollowingUserInteraction];
    else BP_Log(@"activeDisplayWindowScene: undefined methodology <unknown:%lld>", m);
    if (r) return r;
    BP_Log(@"activeDisplayWindowScene: no embedded scene to answer with, using the stock answer");   // last-line guard only
    return %orig;
}

// Fidelity helpers with the 16.2 selectors (used by other groups' hooks if any).
// 16.2 0x1c74bf244: [self _validateSuggestedActiveWindowScene:[self.keyboardFocusTracker activeWindowScene] usingMethodology:0].  The tracker is X7Keyboard.x (gap G7); when it is not installed
// (switch kbtracker off) the focus controller is asked directly, which is what it does itself (same scene).
%new
- (id)activeDisplayWindowSceneFollowingKeyboard {
    id suggested = nil;
    if (!X7_TrackerScene(self, &suggested)) suggested = [BP_KeyboardFocusController() windowSceneWithFocus];
    return BP_ValidateActiveScene(self, suggested, 0);
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
// PORTED (0.7.0): the complete 16.2 -[SBExternalDisplayWindowSceneDelegate sceneDidDisconnect:] (0x1c746826c), in the 16.2
// order, replacing the 16.0 body (0x1c5fed4f8; it called [super sceneDidDisconnect:] FIRST, then only conditionally told the
// switcher coordinator, and did not touch the cover sheet controller or the interaction coordinator):
//   1 kfc suppressKeyboardFocusEvaluationForReason:"<class> - <display identity>"      2 ws.invalidating = YES
//   3 SBMainSwitcherControllerCoordinator windowSceneDidDisconnect:ws   (16.0: only if ws.screen.displayConfiguration != nil)
//   4 _showStatusBarAssertion invalidate + nil     5 ws.systemGestureManager invalidate
//   6 SBAlertItemsController / SBAppInteractionEventSourceManager windowSceneDidDisconnect:ws
//   7 multiDisplayUserInteractionCoordinator windowSceneDidDisconnect:ws     8 _coverSheetController invalidate + nil
//   9 [super sceneDidDisconnect:]    10 assertion invalidate    11 ws invalidate    12 self.invalidated = YES
%hook SBExternalDisplayWindowSceneDelegate

// connect side of the coordinator hand-off (16.2: last statement of _configureForConnectingWindowScene:windowSceneContext:)
- (void)_configureForConnectingWindowScene:(id)scene windowSceneContext:(id)context {
    %orig;
    if (BP_On(F_ACTIVEDISPLAY)) [BP_Coordinator(YES) windowSceneDidConnect:BP_WindowSceneOf(scene)];
}

- (void)sceneDidDisconnect:(id)scene {
    if (!BP_On(F_DISCONNECT)) {
        %orig;
        return;
    }

    id ws = BP_WindowSceneOf(scene);
    id kfc = BP_KeyboardFocusController();
    id assertion = nil;
    if ([kfc respondsToSelector:@selector(suppressKeyboardFocusEvaluationForReason:)]) {
        id ident = ([[ws screen] respondsToSelector:@selector(displayIdentity)]) ? [[ws screen] displayIdentity] : ws;
        NSString *reason = [NSString stringWithFormat:@"%@ - %@", NSStringFromClass([self class]), ident];   // 16.2 reason format
        assertion = ((id (*)(id, SEL, id))objc_msgSend)(kfc, @selector(suppressKeyboardFocusEvaluationForReason:), reason);
    }
    if (ws && [ws respondsToSelector:@selector(setInvalidating:)]) [ws setInvalidating:YES];

    // 3: always (16.2); 16.0 skipped it when the screen had no display configuration any more
    if (BP_OnName("discswitch")) {
        Class sc = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
        id coord = [(id)sc respondsToSelector:@selector(sharedInstance)] ? [(id)sc sharedInstance] : nil;
        if (ws && [coord respondsToSelector:@selector(windowSceneDidDisconnect:)]) [coord windowSceneDidDisconnect:ws];
    }

    // 4
    @try {
        id sba = [self valueForKey:@"showStatusBarAssertion"];            // ivar _showStatusBarAssertion through KVC (no offsets)
        if ([sba respondsToSelector:@selector(invalidate)]) [sba invalidate];
        [self setValue:nil forKey:@"showStatusBarAssertion"];
    } @catch (NSException *e) { BP_Log(@"disconnect: status bar assertion release skipped: %@", e); }

    // 5
    id sgm = [ws respondsToSelector:NSSelectorFromString(@"systemGestureManager")] ? ((id (*)(id, SEL))objc_msgSend)(ws, NSSelectorFromString(@"systemGestureManager")) : nil;
    if ([sgm respondsToSelector:@selector(invalidate)]) [sgm invalidate];

    // 6
    for (NSString *cn in @[@"SBAlertItemsController", @"SBAppInteractionEventSourceManager"]) {
        Class c = NSClassFromString(cn);
        id inst = [(id)c respondsToSelector:@selector(sharedInstance)] ? [(id)c sharedInstance] : nil;
        if (ws && [inst respondsToSelector:@selector(windowSceneDidDisconnect:)]) [inst windowSceneDidDisconnect:ws];
    }

    // 7 (16.2 also calls it from the delegate; the coordinator forgets the scene and clears the touch-down / active scene)
    [BP_Coordinator(NO) windowSceneDidDisconnect:ws];

    // 8: 16.2 -[SBExternalDisplayCoverSheetController invalidate] (new) = removeObserver:, then the delegate drops the controller
    @try {
        id cover = [self valueForKey:@"coverSheetController"];
        if (cover) {
            [[NSNotificationCenter defaultCenter] removeObserver:cover];
            if ([cover respondsToSelector:NSSelectorFromString(@"invalidate")]) ((void (*)(id, SEL))objc_msgSend)(cover, NSSelectorFromString(@"invalidate"));     // 16.2 -invalidate (Tweak.x)
            [self setValue:nil forKey:@"coverSheetController"];
        }
    } @catch (NSException *e) { BP_Log(@"disconnect: cover sheet controller release skipped: %@", e); }

    // 9: the superclass part, now at the 16.2 position
    Class base = NSClassFromString(@"SBAbstractWindowSceneDelegate");
    if (base && class_getInstanceMethod(base, @selector(sceneDidDisconnect:))) {
        struct objc_super sup = { self, base };
        ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, @selector(sceneDidDisconnect:), scene);
    }

    [assertion invalidate];                                                // 10: lets the kfc re-evaluate exactly once
    BP_SetFlag(ws, &kBPInvalidated, YES);                                  // 11: 16.2 [ws invalidate]
    if ([self respondsToSelector:@selector(setInvalidated:)]) [self setInvalidated:YES];   // 12
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
        id sw = BP_ObjIvar(self, iv);
        id own = [sw respondsToSelector:@selector(windowScene)] ? [sw windowScene] : nil;
        if (BP_PanFromOtherDisplay(gesture, own)) { BP_Log(@"gesture gate: switcher gesture NotForCurrentDisplay"); return NO; }
    }
    return %orig;
}
%end

// ---------------------------------------------------------------------------------------------- pointer lock display
// REMOVED (review F4): scoping the pointer-lock suppression assertion to the iPad display was a no-op on 16.0 (a nil
// display already means "<main>", the only display SBLockedPointerManager serves) and it ran on that manager's private
// queue while reading main-thread scene state. The switch name "lockedptr" is kept in the table but nothing uses it.

%end // %group G4

// ================================================================================================ entry
// Call from Tweak.x's %ctor, after the build check and the existing %init.
void BP_G4_Setup(void) {
    %init(G4);
    // MSHookFunction on a non-ObjC function: opt-in until it has been seen working on Dopamine/arm64e.
    if (BP_On(F_DIRECTHOOK)) BP_InstallReevaluateHook();
    else BP_Log(@"direct hook not installed (Backport162.off.directhook exists); suppression is advisory");
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
