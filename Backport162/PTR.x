// PTR.x - pointeruid side of iPadOS 16.1 / 16.2 (multi display pointer rendering), loaded only into the pointeruid executable
// (Backport162PTR.plist: Filter Executables = pointeruid; arm64e only; build 20A8372 only).
// Spec: specs/POINTER-PIXELS-0.7.4.md (sections 3, 6). Compared real 16.0 pointeruid (user's file) with 16.1 / 16.2:
//   the transition / hide path is byte identical, 16.1 changed how the pointer layers are set up. Three of the four 16.1 changes are ported here,
//   per display AX zoom is skipped on purpose. Addresses are 16.0 / 16.1 / 16.2 of /System/Library/PrivateFrameworks/PointerUIServices.framework/Support/pointeruid.
//
// A (ptr_layerclass)  +[PUIDPointerShapeView layerClass]: 16.0 0x1000054b8 returns CABackdropLayer, 16.1 / 16.2 have no such method (plain CALayer).
//                     The gaussianBlur filter of the hide / show animation (-[PUIDPointerShapeView initWithFrame:] 16.0 0x100004390, setBlurRadius: 0x100004ca8) then acts
//                     on the pointer subtree instead of on a backdrop. Hook: return +[CALayer class] (what UIView's default gives 16.1 / 16.2).
// B (ptr_hidden)      16.1 hiddenForPerformanceReasons: -[PUIDDisplayContextFactoryImpl newDisplayContextForDisplay:pointerRenderingScene:systemPointerScene:]
//                     (16.0 0x100010c4c, 16.1 0x100010ac8: `cmp x20,#0; cset w23,ne` at 0x100010b60) passes (systemPointerScene != nil) to
//                     -[PUIDPointerRenderingRootViewController initWithDisplay:hiddenForPerformanceReasons:] (16.1 0x10001e7f0); its viewDidLoad (16.1 0x10001e9dc,
//                     0x10001ea70) does [self.view setHidden:hidden]. The pointer is then visible only through the system pointer window's _UIPortalView.
//                     16.0 has no such flag and nothing ever unhides the root view. Hook: the factory sets the system window first and the controller second
//                     (16.0 0x100010df4 setSystemPointerWindow:, 0x100010e00 setSystemPointerRenderingController:), so -[PUIDDisplayContext setSystemPointerRenderingController:]
//                     with a non-nil controller and a non-nil systemPointerWindow == "the display has a system pointer scene": hide the rendering controller's view there
//                     (its window is already un-hidden and the root view loaded by then, 0x100010d44). The factory itself is not hooked ("new" family: ARC +1 rules).
// C (ptr_scene)       nil systemPointerScene (16.1): the factory skips the system pointer window ("skipped creating system pointer window", 16.1 0x100010c40 cbz x20) and
//                     -[PUIDPointerController displayAttached:pointerRenderingScene:systemPointerScene:] (16.0 0x100008060, 16.1 0x100007ee0 `cbz x21` at 0x100007fac) skips
//                     the system client's portal source collection (createPointerPortalSourceCollectionForClient:, setShouldBeInvalidatedIfPointerLeavesDisplay:NO,
//                     setSystemPointerPortalSourceCollection:, hover region setPointerPortalSourceCollection:). Hooks: PUIDSystemPointerWindow initWithWindowScene: with a nil
//                     scene returns nil (no system window; the unused system controller of 16.0 stays, harmless), and displayAttached: with a nil system scene runs the 16.0 code
//                     with createPointerPortalSourceCollectionForClient: answering nil (the nil collection reaches exactly the setters 16.1 does not call, all nil safe:
//                     16.0 0x10001e188 isEqual/copy/portalLayer, hover region setter). Dead path on a normal setup: SpringBoard prepares both scenes for every display.
//
// D (ptr_hover)     STUCK RESIZE ARROWS (specs/POINTER-HOVER-0.7.6.md).  Hover regions are per CLIENT in pointeruid (_PUIDPointerControllerClientState.activeHoverRegion, held in
//                     -[PUIDPointerController _pointerClientToClientStateMap]), not per display.  -[PUIDPointerController _movePointerToDisplay:] (16.0 0x10000cb60, identical 16.1 / 16.2) only
//                     hides the pointer of the old display; the region SpringBoard's single _UIPointerArbiter sent while the pointer was on the old display stays and
//                     -[PUIDPointerController _updatePointerWithOptions:updateHandlerCollection:] (16.0 0x10000ead4, 0x10000eb3c .. 0x10000ed2c) picks it again for the new display (first client with the
//                     pid of the new display's system pointer interaction context and a non-nil activeHoverRegion), its automatic exit (0.2 s, 0x10000f1a8) is only armed on a hit state 1 -> 2
//                     change measured with the NEW display's transform.  DELIBERATE FIX (no stock build does this): after -_movePointerToDisplay: changed the active display, clear the active
//                     hover region (and its exit timer / hit state) of every non-system client; the next update then uses the new display's system pointer client.
// E (ptr_edge)       STALE PIXELS at the display edge (same spec).  DELIBERATE FIX: (1) the hide of the display the pointer LEFT is not animated (-[PUIDPointerRenderingRootViewController hidePointer]
//                     16.0 0x100023ab8 passes options 3 = animated; options 0 is what the controller itself uses for the first, non animated, state) so the blur / scale / alpha springs do not
//                     run while the pointer is clamped half off the display, (2) once a pointer is hidden (immediately for (1), 0.7 s after an animated autohide) every CABackdropLayer of its
//                     view tree gets enabled = NO and is enabled again before the next visible state.
//
// Switches (checked at most once a second, in <jbroot>/tmp and /tmp; any access() failure means ON): Backport162.off.ptr_layerclass, .off.ptr_hidden, .off.ptr_scene, Backport162.off.
// A is evaluated when a shape view is created, B when a display context is created (display attach), C when a display attaches; a switch needs `killall pointeruid` to take
// effect on pointers that already exist.
// Log: NSLog with prefix [Backport162PTR]; additionally (when Backport162.debug exists) appended to Backport162.daemon.log in a directory pointeruid can write to (BPDaemon.h); SpringBoard copies it into Backport162.log.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <math.h>
#import <sys/sysctl.h>
#import <string.h>
#import <stdio.h>
#import <notify.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import <time.h>
#import "BPDaemon.h"

// ------------------------------------------------------------------------------------------------ switches / log

static const char *const kBPPTRDirs[2] = { "/var/jb/tmp", "/tmp" };

static BOOL BPPTR_FileExists(const char *name) {
    for (int i = 0; i < 2; i++) {
        char p[1200];
        snprintf(p, sizeof p, "%s/%s", kBPPTRDirs[i], name);
        if (access(p, F_OK) == 0) return YES;        // failure (ENOENT, sandbox EPERM) = not found = switch is not set
    }
    return NO;
}

typedef struct { uint64_t next; BOOL last; } BPPTRCache;

static BOOL BPPTR_Killed(BPPTRCache *c, const char *name) {
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (c->next && t < c->next) return c->last;
    c->next = t + 1000000000ull;
    c->last = BPPTR_FileExists("Backport162.off") || BPPTR_FileExists(name);
    return c->last;
}
static BOOL BPPTR_OnLayerClass(void) { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_layerclass"); }
static BOOL BPPTR_OnHidden(void)     { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_hidden"); }
static BOOL BPPTR_OnScene(void)      { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_scene"); }
static BOOL BPPTR_OnHover(void)      { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_hover"); }
static BOOL BPPTR_OnEdge(void)       { static BPPTRCache c; return !BPPTR_Killed(&c, "Backport162.off.ptr_edge"); }
static BOOL BPPTR_DebugOn(void) {
    static BPPTRCache c;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (c.next && t < c.next) return c.last;
    c.next = t + 1000000000ull;
    c.last = BPPTR_FileExists("Backport162.debug");
    return c.last;
}

static void BPPTR_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BPPTR_Log(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[Backport162PTR] %@", m);
    if (!BPPTR_FileExists("Backport162.debug")) return;
    const char *u = m.UTF8String;                                   // pointeruid is sandboxed: BPDaemon.h picks a directory it can write to, SpringBoard copies the lines into Backport162.log
    if (u) BPDW_Line("ptr", u);
}

// ------------------------------------------------------------------------------------------------ hooks

static __thread int gBPPTRNoPortal;      // >0 while displayAttached: runs for a display without system pointer scene

// ------------------------------------------------------------------------------------------------ runtime helpers

static id BPPTR_Ivar(id o, const char *name) {
    if (!o) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(o), name);
    return iv ? object_getIvar(o, iv) : nil;                            // strong ivars only (the weak _display of PUIDDisplayContext is read through the rendering controller)
}
static BOOL BPPTR_BoolIvar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) return NO;
    BOOL b = NO;
    memcpy(&b, (const char *)(__bridge void *)o + ivar_getOffset(iv), 1);
    return b;
}
static id BPPTR_Send0(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static int BPPTR_Pid(id client) {
    SEL s = sel_registerName("pid");
    return (client && [client respondsToSelector:s]) ? ((int (*)(id, SEL))objc_msgSend)(client, s) : -1;
}
static NSString *BPPTR_Trunc(id o, NSUInteger n) {
    NSString *d = o ? [NSString stringWithFormat:@"%@", o] : @"nil";
    d = [d stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return d.length > n ? [[d substringToIndex:n] stringByAppendingString:@"..."] : d;
}
static NSString *BPPTR_DisplayName(id displayContext) {
    id rc = BPPTR_Ivar(displayContext, "_pointerRenderingController");
    id disp = BPPTR_Send0(rc, "display");
    id hw = BPPTR_Send0(disp, "hardwareIdentifier");
    return hw ? [NSString stringWithFormat:@"%@", hw] : (disp ? BPPTR_Trunc(disp, 60) : @"?");
}
// The pointer button mask of the controller's last pointer event: IOHIDEventGetIntegerValue(event, kIOHIDEventFieldPointerButtonMask = 0x110003), the field the controller itself reads
// in -pointerEventStreamProvider:didReceivePointerEvent: (0x100008878) to derive _isButtonPressDownTransition (+0x119).  NOTE: _isFingerDown (+0x118) is NOT a button state: it is
// (fingerDownCount > 0) of the pointer attributes (0x100008b54 .. 0x100008b80), i.e. TRUE the whole time a finger rests on a trackpad (the 0.7.6 guard read it as "button held" and never cleared).
typedef long long (*BPPTR_GetInt)(void *, uint32_t);
typedef double (*BPPTR_GetFloat)(void *, uint32_t);
static void *BPPTR_LastEvent(id controller) {
    Ivar iv = class_getInstanceVariable(object_getClass(controller), "_lastPointerEvent");
    void *e = NULL;
    if (iv) memcpy(&e, (const char *)(__bridge void *)controller + ivar_getOffset(iv), sizeof e);
    return e;
}
static long long BPPTR_ButtonMask(id controller) {
    static BPPTR_GetInt fn; static BOOL tried;
    if (!tried) { tried = YES; fn = (BPPTR_GetInt)dlsym(RTLD_DEFAULT, "IOHIDEventGetIntegerValue"); }
    void *e = BPPTR_LastEvent(controller);
    return (fn && e) ? fn(e, 0x110003) : -1;
}
static BOOL BPPTR_EventPosition(id controller, CGPoint *out) {
    static BPPTR_GetFloat fn; static BOOL tried;
    if (!tried) { tried = YES; fn = (BPPTR_GetFloat)dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue"); }
    void *e = BPPTR_LastEvent(controller);
    if (!fn || !e) return NO;
    out->x = fn(e, 0x110000); out->y = fn(e, 0x110001);                 // the two fields the controller reads for the model position (0x10000eb64)
    return YES;
}
static uint64_t gBPPTRChangeAt;           // uptime ns of the last display change (for the "ms after the display change" of the hover region trace)
static uint64_t gBPPTRWatchUntil;         // after a display change the next pointer updates are traced for 1.5 s (debug only)
static unsigned gBPPTRWatchLines;
static char kBPPTRBackdropsOff;           // associated object on a rendering controller: its CABackdropLayers were disabled by ptr_edge
static char kBPPTRBackdropsKeptNote;      // associated object on a rendering controller: "backdrops stay disabled" was logged since they were switched off
static __thread int gBPPTRMoving;         // >0 while -_movePointerToDisplay: runs (its hidePointer is the one of the display that was left)

static void BPPTR_Walk(CALayer *l, int depth, void (^visit)(CALayer *, int)) {
    if (!l || depth > 14) return;
    visit(l, depth);
    for (CALayer *c in [l.sublayers copy]) BPPTR_Walk(c, depth + 1, visit);
}

// ptr_edge (2): every CABackdropLayer below the rendering controller's view (shape view backdrops, shape morphing backdrop, specular copy, portal sources) on / off.
static void BPPTR_SetBackdrops(id rc, BOOL enabled) {
    if (![rc isKindOfClass:[UIViewController class]] || !((UIViewController *)rc).isViewLoaded) return;
    Class bl = NSClassFromString(@"CABackdropLayer");
    SEL se = sel_registerName("setEnabled:");
    if (!bl) return;
    __block int n = 0;
    BPPTR_Walk(((UIViewController *)rc).view.layer, 0, ^(CALayer *l, int d) {
        if ([l isKindOfClass:bl] && [l respondsToSelector:se]) { ((void (*)(id, SEL, BOOL))objc_msgSend)(l, se, enabled); n++; }
    });
    objc_setAssociatedObject(rc, &kBPPTRBackdropsOff, enabled ? nil : @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(rc, &kBPPTRBackdropsKeptNote, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (BPPTR_DebugOn()) BPPTR_Log(@"ptr_edge: %d backdrop layer(s) of %@ %@", n, BPPTR_Trunc(rc, 80), enabled ? @"enabled" : @"disabled");
}

// YES when a visible backdrop layer of the controller's view tree is cut by the bounds of its window (model frames: the target of the pointer's current state).
static BOOL BPPTR_BackdropCutByEdge(id rc, NSString **why) {
    if (![rc isKindOfClass:[UIViewController class]] || !((UIViewController *)rc).isViewLoaded) return NO;
    UIView *v = ((UIViewController *)rc).view;
    UIWindow *w = v.window;
    Class bl = NSClassFromString(@"CABackdropLayer");
    if (!w || !bl) return NO;
    CGRect wb = w.bounds;
    __block BOOL cut = NO;
    BPPTR_Walk(v.layer, 0, ^(CALayer *l, int d) {
        if (cut || ![l isKindOfClass:bl] || l.hidden || l.opacity <= 0.01f) return;
        CGRect fr = [l convertRect:l.bounds toLayer:w.layer];
        if (!CGRectIsEmpty(fr) && CGRectIntersectsRect(wb, fr) && !CGRectContainsRect(wb, fr)) {
            cut = YES;
            if (why) *why = [NSString stringWithFormat:@"%@ frame %@ in window %@", NSStringFromClass([l class]), NSStringFromCGRect(fr), NSStringFromCGRect(wb)];
        }
    });
    return cut;
}

// Diagnostics: every layer that can paint the pointer: frame in the window (= display points) against the window bounds, hidden / alpha / presentation alpha, backdrop enabled, filters.
static void BPPTR_DumpLayers(id rc, NSString *tag) {
    if (!BPPTR_DebugOn() || ![rc isKindOfClass:[UIViewController class]] || !((UIViewController *)rc).isViewLoaded) return;
    UIView *v = ((UIViewController *)rc).view;
    UIWindow *w = v.window;
    CGRect wb = w ? w.bounds : CGRectZero;
    Class bl = NSClassFromString(@"CABackdropLayer");
    __block int lines = 0, total = 0;
    BPPTR_Log(@"edge-dump [%@] %@ display %@ window %@ view hidden %d alpha %.2f", tag, BPPTR_Trunc(rc, 60), BPPTR_Send0(rc, "display") ? @"set" : @"nil", NSStringFromCGRect(wb), (int)v.hidden, v.alpha);
    BPPTR_Walk(v.layer, 0, ^(CALayer *l, int d) {
        total++;
        BOOL isBd = bl && [l isKindOfClass:bl];
        CGRect fr = [l convertRect:l.bounds toLayer:w.layer];
        BOOL straddle = w && !CGRectIsEmpty(fr) && !CGRectContainsRect(wb, fr) && CGRectIntersectsRect(wb, fr);
        if (!(isBd || straddle || d <= 2) || lines >= 24) return;
        lines++;
        CALayer *pl = l.presentationLayer;
        NSString *bd = isBd ? [NSString stringWithFormat:@" backdrop-enabled %d", (int)((BOOL (*)(id, SEL))objc_msgSend)(l, sel_registerName("isEnabled"))] : @"";
        BPPTR_Log(@"edge-dump [%@]  d%d %@ frame %@ %@ hidden %d op %.2f pres %.2f%@ filters %@", tag, d, NSStringFromClass([l class]), NSStringFromCGRect(fr),
                  straddle ? @"STRADDLES-EDGE" : @"", (int)l.hidden, l.opacity, pl ? pl.opacity : -1.0f, bd, l.filters.count ? [l.filters valueForKey:@"name"] : @"-");
    });
    BPPTR_Log(@"edge-dump [%@] %d layers total, %d listed", tag, total, lines);
}
static void BPPTR_DumpLater(id rc, NSString *tag, double delay) {
    __weak id wrc = rc;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ id r = wrc; if (r) BPPTR_DumpLayers(r, tag); });
}

// ptr_hover (the fix) and its diagnostics: called after -_movePointerToDisplay: changed the active display context.
static void BPPTR_DisplayChanged(id controller, id before, id after) {
    BOOL dbg = BPPTR_DebugOn();
    BOOL fix = BPPTR_OnHover();
    id map = BPPTR_Ivar(controller, "_pointerClientToClientStateMap");
    NSArray *clients = [BPPTR_Send0(map, "keyEnumerator") allObjects];
    Class sysState = NSClassFromString(@"_PUIDPointerControllerSystemClientState");
    SEL setRegion = sel_registerName("setActiveHoverRegion:"), invTimer = sel_registerName("invalidateAutomaticRegionExitTimer"), setHit = sel_registerName("setPreviousPointerEventActiveHoverRegionHitTestState:");
    if (dbg) {
        gBPPTRWatchUntil = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + 1500000000ull;
        gBPPTRWatchLines = 0;
        BPPTR_Log(@"hover: pointer display %@ -> %@: %lu client state(s), fix %@", BPPTR_DisplayName(before), BPPTR_DisplayName(after), (unsigned long)clients.count, fix ? @"ON" : @"off (switch)");
    }
    long long buttons = BPPTR_ButtonMask(controller);
    BOOL held = buttons > 0;                                           // a pointer button is down (a drag or resize that crosses the display edge): the region belongs to the drag, keep it
    gBPPTRChangeAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (dbg) {
        Ivar fd = class_getInstanceVariable(object_getClass(controller), "_isFingerDown");
        BPPTR_Log(@"hover: raw state: button mask %lld (held %d), _isFingerDown byte %d (ivar offset 0x%lx type %s: trackpad finger contact, not a button), _isButtonPressDownTransition %d, _latchingState %lld, _lockedContext %@",
                  buttons, (int)held, (int)BPPTR_BoolIvar(controller, "_isFingerDown"), fd ? (unsigned long)ivar_getOffset(fd) : 0ul, fd ? ivar_getTypeEncoding(fd) : "?", (int)BPPTR_BoolIvar(controller, "_isButtonPressDownTransition"),
                  ({ long long v = -1; Ivar li = class_getInstanceVariable(object_getClass(controller), "_latchingState"); if (li) memcpy(&v, (const char *)(__bridge void *)controller + ivar_getOffset(li), sizeof v); v; }),
                  BPPTR_Ivar(controller, "_lockedContext") ? @"set" : @"nil");
        if (held && fix) BPPTR_Log(@"hover: a pointer button is held, hover regions are kept");
    }
    int cleared = 0;
    for (id client in clients) {
        id state = [(NSMapTable *)map objectForKey:client];
        id region = BPPTR_Send0(state, "activeHoverRegion");
        if (!region) {
            if (dbg) BPPTR_Log(@"hover:   client pid %d (%@) has no active hover region", BPPTR_Pid(client), NSStringFromClass([client class]));
            continue;
        }
        BOOL sys = sysState && [state isKindOfClass:sysState];
        id shape = BPPTR_Send0(region, "pointerShape");
        if (dbg) BPPTR_Log(@"hover:   client pid %d (%@, state %@%@) active hover region: shape %@ coordinateSpaceSourceContextID 0x%x hitTestState %lld | %@",
                           BPPTR_Pid(client), NSStringFromClass([client class]), NSStringFromClass([state class]), sys ? @", system client: kept" : @"",
                           BPPTR_Trunc(shape, 90), [region respondsToSelector:sel_registerName("coordinateSpaceSourceContextID")] ? ((unsigned (*)(id, SEL))objc_msgSend)(region, sel_registerName("coordinateSpaceSourceContextID")) : 0u,
                           [state respondsToSelector:sel_registerName("previousPointerEventActiveHoverRegionHitTestState")] ? ((long long (*)(id, SEL))objc_msgSend)(state, sel_registerName("previousPointerEventActiveHoverRegionHitTestState")) : -1LL,
                           BPPTR_Trunc(region, 140));
        if (!fix || held || sys || ![state respondsToSelector:setRegion]) continue;
        if ([state respondsToSelector:invTimer]) ((void (*)(id, SEL))objc_msgSend)(state, invTimer);
        ((void (*)(id, SEL, id))objc_msgSend)(state, setRegion, nil);
        if ([state respondsToSelector:setHit]) ((void (*)(id, SEL, long long))objc_msgSend)(state, setHit, 0);
        cleared++;
    }
    if (dbg) BPPTR_Log(@"hover: cleared %d active hover region(s) of the clients (the display left: %@)", cleared, BPPTR_DisplayName(before));
}

%group BPPTR_Display
%hook PUIDPointerController
- (void)_movePointerToDisplay:(id)display {
    id before = BPPTR_Ivar(self, "_activeDisplayContext");
    gBPPTRMoving++;
    @try {
        %orig;
    } @finally {
        gBPPTRMoving--;
    }
    id after = BPPTR_Ivar(self, "_activeDisplayContext");
    if (!before || !after || before == after) return;
    @try {
        BPPTR_DisplayChanged(self, before, after);
        id oldRc = BPPTR_Ivar(before, "_pointerRenderingController");
        if (BPPTR_DebugOn()) { BPPTR_DumpLayers(oldRc, @"left+0"); BPPTR_DumpLater(oldRc, @"left+0.1s", 0.1); BPPTR_DumpLater(oldRc, @"left+0.4s", 0.4); BPPTR_DumpLater(oldRc, @"left+1.2s", 1.2); }
    } @catch (NSException *e) {
        BPPTR_Log(@"display change handling raised %@", e);
    }
}
- (void)_updatePointerWithOptions:(unsigned long long)options updateHandlerCollection:(id)collection {
    %orig;
    if (gBPPTRWatchUntil == 0) return;
    if (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) > gBPPTRWatchUntil || gBPPTRWatchLines >= 20) { gBPPTRWatchUntil = 0; return; }
    gBPPTRWatchLines++;
    id client = BPPTR_Ivar(self, "_previousPointerClient");
    id state = client ? [(NSMapTable *)BPPTR_Ivar(self, "_pointerClientToClientStateMap") objectForKey:client] : nil;
    id region = BPPTR_Send0(state, "activeHoverRegion");
    // pointer position: event position (what the model uses) against what the active display's rendering controller has on screen (model and presentation position of the shape view)
    CGPoint ev = CGPointZero; BOOL haveEv = BPPTR_EventPosition(self, &ev);
    id rc = BPPTR_Ivar(BPPTR_Ivar(self, "_activeDisplayContext"), "_pointerRenderingController");
    id sv = BPPTR_Ivar(rc, "_pointerShapeView");
    CALayer *sl = [sv isKindOfClass:[UIView class]] ? ((UIView *)sv).layer : nil;
    CGPoint mp = sl ? sl.position : CGPointZero, pp = sl.presentationLayer ? sl.presentationLayer.position : CGPointMake(-1, -1);
    BPPTR_Log(@"hover: update %.0f ms after the display change: pointer client pid %d (%@) hover region %@ autohidden %d active display %@ | event position %@ shape view model %@ presentation %@ (jump %.1f pt)",
              (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - gBPPTRChangeAt) / 1e6, BPPTR_Pid(client), NSStringFromClass([client class]), region ? BPPTR_Trunc(BPPTR_Send0(region, "pointerShape"), 80) : @"none",
              (int)BPPTR_BoolIvar(self, "_pointerIsAutohidden"), BPPTR_DisplayName(BPPTR_Ivar(self, "_activeDisplayContext")), haveEv ? NSStringFromCGPoint(ev) : @"?", NSStringFromCGPoint(mp), NSStringFromCGPoint(pp),
              haveEv && sl ? hypot(pp.x - ev.x, pp.y - ev.y) : -1.0);
}
- (void)xpcClientContextController:(id)xpc didUpdateHoverRegion:(id)region forClient:(id)client transitionCompletion:(id)completion {
    %orig;
    if (!BPPTR_DebugOn()) return;
    static uint64_t sec; static int n;
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000000ull;
    if (now != sec) { sec = now; n = 0; }
    if (++n > 20) return;
    SEL cs = sel_registerName("coordinateSpaceSourceContextID"), cb = sel_registerName("contentBounds");
    unsigned ctx = (region && [region respondsToSelector:cs]) ? ((unsigned (*)(id, SEL))objc_msgSend)(region, cs) : 0u;
    CGRect bounds = (region && [region respondsToSelector:cb]) ? ((CGRect (*)(id, SEL))objc_msgSend)(region, cb) : CGRectZero;
    BPPTR_Log(@"hover: client pid %d sent hover region %@ ctx 0x%x contentBounds %@ (active display %@, %.0f ms after the last display change)", BPPTR_Pid(client),
              region ? BPPTR_Trunc(BPPTR_Send0(region, "pointerShape"), 80) : @"NIL (hover ended)", ctx, NSStringFromCGRect(bounds), BPPTR_DisplayName(BPPTR_Ivar(self, "_activeDisplayContext")),
              gBPPTRChangeAt ? (clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - gBPPTRChangeAt) / 1e6 : -1.0);
}
%end

%hook PUIDPointerRenderingRootViewController
- (void)hidePointer {
    if (gBPPTRMoving > 0 && BPPTR_OnEdge()) {
        id st = BPPTR_Ivar(self, "_pointerState");
        id m = [st mutableCopy];
        SEL sh = sel_registerName("setPointerAutoHidden:");
        if (m && [m respondsToSelector:sh]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(m, sh, YES);
            if (BPPTR_DebugOn()) BPPTR_Log(@"ptr_edge: hiding the pointer of the display that was left without animation (stock: options 3, animated, while the pointer is clamped on the edge)");
            ((BOOL (*)(id, SEL, id, unsigned long long, id, id *))objc_msgSend)((id)self, sel_registerName("setPointerState:options:updateHandlerCollection:error:"), m, 0ull, nil, NULL);
            BPPTR_SetBackdrops(self, NO);
            return;
        }
    }
    %orig;
}
- (BOOL)setPointerState:(id)state options:(unsigned long long)options updateHandlerCollection:(id)collection error:(id *)error {
    BOOL edge = BPPTR_OnEdge();
    BOOL hidden = edge && BPPTR_BoolIvar(state, "_pointerAutoHidden");
    BOOL r = %orig;
    // The pointer comes back onto a display it had left: its backdrops stay off while any of them is cut by the display edge (the entering pointer is clamped half off the display), the
    // first frames of a backdrop that reaches beyond the display painted coloured specks into the last pixel rows (monitor bottom edge, pointer arriving from the iPad).  They are
    // enabled by the first state whose backdrop frames are all inside the window.
    if (edge && !hidden && objc_getAssociatedObject(self, &kBPPTRBackdropsOff)) {
        NSString *cut = nil;
        if (!BPPTR_BackdropCutByEdge(self, &cut)) {
            BPPTR_SetBackdrops(self, YES);
            if (BPPTR_DebugOn()) BPPTR_Log(@"ptr_edge: backdrops enabled, no backdrop layer is cut by the display edge any more");
        } else if (BPPTR_DebugOn() && !objc_getAssociatedObject(self, &kBPPTRBackdropsKeptNote)) {
            objc_setAssociatedObject(self, &kBPPTRBackdropsKeptNote, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            BPPTR_Log(@"ptr_edge: backdrops stay disabled, cut by the display edge: %@", cut);
        }
    }
    if (hidden && options != 0 && !objc_getAssociatedObject(self, &kBPPTRBackdropsOff)) {                                        // animated hide (autohide): turn the backdrops off when the animation is over, if the pointer is still hidden
        __weak id wself = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(700 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            id me = wself;
            if (me && BPPTR_OnEdge() && BPPTR_BoolIvar(BPPTR_Ivar(me, "_pointerState"), "_pointerAutoHidden")) BPPTR_SetBackdrops(me, NO);
        });
    }
    return r;
}
%end
%end


%group BPPTR_LayerClass
%hook PUIDPointerShapeView
+ (Class)layerClass {
    if (!BPPTR_OnLayerClass()) return %orig;
    return [CALayer class];
}
%end
%end

%group BPPTR_Hidden
%hook PUIDDisplayContext
- (void)setSystemPointerRenderingController:(id)controller {
    %orig;
    if (!controller || !BPPTR_OnHidden()) return;
    // PUIDDisplayContext declares its property getters objc_direct (they are not in the method list: the first build asked respondsToSelector: for systemPointerWindow and never installed),
    // so the ivars are read. 16.0 factory 0x100010c4c: setSystemPointerWindow: (0x100010df4) runs before setSystemPointerRenderingController: (0x100010e00).
    if (!BPPTR_Ivar(self, "_systemPointerWindow")) return;                // 16.1: no system pointer scene -> not hidden
    id rc = BPPTR_Ivar(self, "_pointerRenderingController");
    if (![rc isKindOfClass:[UIViewController class]]) return;
    [((UIViewController *)rc).view setHidden:YES];                       // 16.1 viewDidLoad: [self.view setHidden:_hiddenForPerformanceReasons]
    BPPTR_Log(@"hiddenForPerformanceReasons: pointer rendering view of %@ hidden (system pointer window present)", self);
}
%end
%end

%group BPPTR_Scene
%hook PUIDSystemPointerWindow
- (id)initWithWindowScene:(id)scene {
    if (!scene && BPPTR_OnScene()) {
        BPPTR_Log(@"skipped creating system pointer window (nil system pointer scene)");
        return nil;                                                      // 16.1 factory: `cbz x20` skips window + controller creation
    }
    return %orig;
}
%end

%hook PUIDPointerController
- (void)displayAttached:(id)display pointerRenderingScene:(id)renderingScene systemPointerScene:(id)systemScene {
    if (systemScene || !BPPTR_OnScene()) {
        %orig;
        return;
    }
    BPPTR_Log(@"displayAttached: nil system pointer scene, no system portal source collection (16.1 cbz)");
    gBPPTRNoPortal++;
    %orig;
    gBPPTRNoPortal--;
}
%end

%hook PUIDPointerRenderingRootViewController
- (id)createPointerPortalSourceCollectionForClient:(id)client {
    if (gBPPTRNoPortal > 0) return nil;
    return %orig;
}
%end
%end

// ------------------------------------------------------------------------------------------------ install

static BOOL BPPTR_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

static BOOL BPPTR_HasInstance(const char *cls, SEL sel) {
    Class c = objc_getClass(cls);
    return c && class_getInstanceMethod(c, sel) != NULL;
}

static BOOL gBPPTRDoneA, gBPPTRDoneB, gBPPTRDoneC, gBPPTRDoneD;

// returns YES when everything is installed (or impossible)
static BOOL BPPTR_TryInstall(void) {
    if (!gBPPTRDoneA) {
        Class sv = objc_getClass("PUIDPointerShapeView");
        if (sv) {
            Method own = class_getClassMethod(sv, @selector(layerClass));
            Method base = class_getClassMethod([UIView class], @selector(layerClass));
            if (own && base && method_getImplementation(own) != method_getImplementation(base)) {
                %init(BPPTR_LayerClass);
                BPPTR_Log(@"ptr_layerclass installed (+[PUIDPointerShapeView layerClass] -> CALayer)");
            } else {
                BPPTR_Log(@"ptr_layerclass: PUIDPointerShapeView has no own layerClass, not installing");
            }
            gBPPTRDoneA = YES;
        }
    }
    if (!gBPPTRDoneB) {
        if (objc_getClass("PUIDDisplayContext")) {
            // the getters of PUIDDisplayContext are objc_direct (not in the method list), the hook reads the ivars
            Class dc = objc_getClass("PUIDDisplayContext");
            if (BPPTR_HasInstance("PUIDDisplayContext", @selector(setSystemPointerRenderingController:)) &&
                class_getInstanceVariable(dc, "_systemPointerWindow") && class_getInstanceVariable(dc, "_pointerRenderingController")) {
                %init(BPPTR_Hidden);
                BPPTR_Log(@"ptr_hidden installed");
            } else {
                BPPTR_Log(@"ptr_hidden: setSystemPointerRenderingController: or the ivars _systemPointerWindow / _pointerRenderingController missing, not installing");
            }
            gBPPTRDoneB = YES;
        }
    }
    if (!gBPPTRDoneC) {
        if (objc_getClass("PUIDPointerController") && objc_getClass("PUIDSystemPointerWindow") && objc_getClass("PUIDPointerRenderingRootViewController")) {
            if (BPPTR_HasInstance("PUIDPointerController", @selector(displayAttached:pointerRenderingScene:systemPointerScene:)) &&
                BPPTR_HasInstance("PUIDSystemPointerWindow", @selector(initWithWindowScene:)) &&
                BPPTR_HasInstance("PUIDPointerRenderingRootViewController", @selector(createPointerPortalSourceCollectionForClient:))) {
                %init(BPPTR_Scene);
                BPPTR_Log(@"ptr_scene installed");
            } else {
                BPPTR_Log(@"ptr_scene: selectors missing, not installing");
            }
            gBPPTRDoneC = YES;
        }
    }
    if (!gBPPTRDoneD) {
        Class pc = objc_getClass("PUIDPointerController"), rv = objc_getClass("PUIDPointerRenderingRootViewController");
        if (pc && rv) {
            if (BPPTR_HasInstance("PUIDPointerController", @selector(_movePointerToDisplay:)) &&
                BPPTR_HasInstance("PUIDPointerController", @selector(_updatePointerWithOptions:updateHandlerCollection:)) &&
                BPPTR_HasInstance("PUIDPointerController", @selector(xpcClientContextController:didUpdateHoverRegion:forClient:transitionCompletion:)) &&
                BPPTR_HasInstance("PUIDPointerRenderingRootViewController", @selector(hidePointer)) &&
                BPPTR_HasInstance("PUIDPointerRenderingRootViewController", @selector(setPointerState:options:updateHandlerCollection:error:)) &&
                class_getInstanceVariable(pc, "_activeDisplayContext") && class_getInstanceVariable(pc, "_pointerClientToClientStateMap") && class_getInstanceVariable(pc, "_previousPointerClient") &&
                class_getInstanceVariable(rv, "_pointerState") && objc_getClass("_PUIDPointerControllerClientState") &&
                class_getInstanceVariable(objc_getClass("PUIDDisplayContext"), "_pointerRenderingController")) {
                %init(BPPTR_Display);
                BPPTR_Log(@"ptr_hover / ptr_edge installed (_movePointerToDisplay:, hidePointer, setPointerState:options:...)");
            } else {
                BPPTR_Log(@"ptr_hover / ptr_edge: selectors or ivars missing, not installing");
            }
            gBPPTRDoneD = YES;
        }
    }
    return gBPPTRDoneA && gBPPTRDoneB && gBPPTRDoneC && gBPPTRDoneD;
}

static void BPPTR_RetryInstall(int attempt) {
    if (BPPTR_TryInstall()) return;
    if (attempt >= 100) {
        BPPTR_Log(@"classes still missing after %d attempts (A=%d B=%d C=%d D=%d), giving up", attempt, gBPPTRDoneA, gBPPTRDoneB, gBPPTRDoneC, gBPPTRDoneD);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{ BPPTR_RetryInstall(attempt + 1); });
}

// Darwin notifications to SpringBoard (its tweak logs them into Backport162.log): a stage of the start-up, readable even when the daemon cannot write files.
static void BPPTR_NotifySlug(const char *prefix, const char *what) {
    char name[200]; size_t n = (size_t)snprintf(name, sizeof name, "com.infernowolf19.backport162.load.%s.", prefix);
    BOOL lastUnderscore = YES;
    for (const char *c = what; *c && n < sizeof name - 2; c++) {
        char ch = (*c >= 'A' && *c <= 'Z') ? (char)(*c + 32) : *c;
        BOOL alnum = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9');
        if (alnum) { name[n++] = ch; lastUnderscore = NO; }
        else if (!lastUnderscore) { name[n++] = '_'; lastUnderscore = YES; }
    }
    while (n > 0 && name[n - 1] == '_') n--;
    name[n] = 0;
    int tok = 0;                                                   // the state (our pid) survives until SpringBoard registers: the daemon starts before SpringBoard
    if (notify_register_check(name, &tok) == NOTIFY_STATUS_OK) notify_set_state(tok, (uint64_t)getpid());
    notify_post(name);
}
// Marker so that the user can see whether the dylib was injected at all (one line per process start; the daemon may be sandboxed: then nothing is written).
static void BPPTR_Marker(const char *what) {
    BPPTR_NotifySlug("ptr", what);
    char ver[64] = {0}; size_t vn = sizeof ver; sysctlbyname("kern.osversion", ver, &vn, NULL, 0);
    const char *img = BPDW_MainName();
    const char *img0 = _dyld_get_image_name(0);
    int di = BPDW_DirIndex();
    char line[700]; snprintf(line, sizeof line, "ctor: %s (main image %s, image 0 %s, build %s, log dir %s)", what, img ? img : "(null)", img0 ? img0 : "(null)", ver, di >= 0 ? kBPDWDirs[di] : "NONE writable");
    BPDW_Line("ptr", line);                                                          // always written: it is the proof that the dylib was injected
}

%ctor {
    @autoreleasepool {
        BPPTR_Marker("ctor entered");
        if (!BPDW_MainIs("pointeruid")) { BPPTR_Marker("not pointeruid, leaving"); return; }                           // belt and braces next to the Filter
        if (!BPPTR_BuildMatches()) { BPPTR_Marker("build mismatch, leaving"); BPPTR_Log(@"build does not match 20A8372, not installing"); return; }
        BPPTR_Marker("installing");
        BPPTR_Log(@"loaded in pointeruid (20A8372)");
        BPPTR_RetryInstall(0);
    }
}
