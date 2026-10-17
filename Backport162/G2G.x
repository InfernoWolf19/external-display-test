// G2G.x : SpringBoard half of the "stuck resize arrows when the pointer changes display" fix (DELIBERATE, switchable; no stock build does this).
// Spec: specs/POINTER-HOVER-0.7.6.md.  Switch: g2g_hoverexit (default ON, kill switch file Backport162.off.g2g_hoverexit).  Setup: G2G_Setup().  Log prefix "g2g:" (needs Backport162.debug).
//
// Why: the hover region (resize arrows, lift, highlight ...) of every SpringBoard window of EVERY display is held by ONE process wide object, +[_UIPointerArbiter sharedArbiter] ->
// _UIPointerArbiterCore_iOS (ivars _activePointerRegion 0x20, _activePointerStyle 0x18, _lastSentHoverRegion 0x28, _pointerClientController 0x40; UIKit 16.0 class at 0x1dcf7cec8).  It sends its
// region to pointeruid with -[PSPointerClientController setActiveHoverRegion:transitionCompletion:] (-_setActiveHoverRegion:style:forPointerRegion:transactionID:completion: 0x1897991e0) and
// takes it back only through -exitRegion:removeStyle:completion: (0x189798fd0 -> block 0x189799108: when the region is still the active one, sends nil).  That call is made by the hover driver
// (-[_UIPointerInteractionHoverDriver _updateHover:forced:] 0x1897b6848, gesture state 3 / 4 or arbiter pointerState 3 -> driverDidExit:) when the UIHoverGestureRecognizer of the window that owns
// the region ends.  When the pointer leaves a display the only thing that ends that hover is the pointer exit event of the window's context (backboardd, BBD.x "pointer exit") and the
// digitizer range 0 the UIKit event pipeline derives from it; the user's device still shows the arrows of the display that was left on the other display with that exit posted, and
// whether UIKit ends the hover could not be proven statically.  So SpringBoard ends it itself, at the one place that knows the pointer changed display:
//   the multi display user interaction coordinator (Group4Focus.x, 16.2 -_pointerMovedInScene: 0x1c795e838) tells its pointer observers pointerDidMoveToFromWindowScene:toWindowScene:.
//   This file registers one observer.  If the arbiter's active region belongs to a view of the window scene the pointer LEFT (region.referenceView, else the coordinate space source view of
//   the arbiter core), the region is exited with -[_UIPointerArbiter exitRegion:removeStyle:completion:] (the very call the hover driver makes).  A second exit from UIKit's own
//   hover end is harmless (block 0x189799108 only acts when the region is still the active one).
// Second fix (switch g2g_staleenter, default ON), found in the user's log db230d53 (21:41:14 .. 21:42:23, 102 display changes): around EVERY display change UIKit sends the hover region of a
// region it had already asked to exit: "arbiter exitRegion <R> (active no)" then "arbiter sends hover region <shape of R>" then "sends hover region NIL" 1 to 12 ms apart, also while the
// pointer is on the other display.  Cause: -[_UIPointerArbiterCore_iOS applyStyle:forRegion:effectSourceHandler:completion:] (0x18979883c) and -exitRegion:removeStyle:completion: (0x189798fd0)
// both run through the FIFO -_performTransactionUsingBlock: (0x18979a068); the hover end of the pointer leaving the display (backboardd's hit-test exit) calls exitRegion for R while the
// enter of R is still queued, so the queued enter runs afterwards (-_setActiveHoverRegion:style:forPointerRegion:transactionID:completion: 0x1897991e0, which sends the shape of R to
// pointeruid) and the exit block (0x189799108) then sends nil.  pointeruid applies the shape for a few ms on the display the pointer is now on: for the resize corner (RoundedRect /
// CustomPath region of the iPad's window) the pointer morphs to the old region's geometry and snaps back = the jump the user sees.  Fix: remember regions with an exit requested after
// their enter (exitRegion marks, applyStyle:forRegion: unmarks); when the queued enter executes for a marked region it is called with hover = nil / style = nil, i.e. the arbiter state stays
// "no region" (exactly what the exit block leaves behind) and no shape is sent.  Decision by identity of the UIPointerRegion, so a real re-enter (applyStyle after the exit) is untouched.
// Diagnostics (Backport162.debug): the observer logs the arbiter state on every display change; the arbiter's exit / set-region / interaction state calls are traced (rate limited), so one
// recording shows whether UIKit exited the region by itself (an "exitRegion" line before the display change line) or not.
//
// 16.0 = 20A8372 unslid cache addresses.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import <time.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2G_ON() BP_OnName("g2g_hoverexit")
#define G2G_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static id G2G_Ivar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? object_getIvar(o, iv) : nil;
}
static id G2G_Send0(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static NSString *G2G_Short(id o) {
    NSString *d = o ? [NSString stringWithFormat:@"%@", o] : @"nil";
    d = [d stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return d.length > 160 ? [[d substringToIndex:160] stringByAppendingString:@"..."] : d;
}
static BOOL G2G_Rate(void) {                  // at most 30 trace lines per second
    static uint64_t sec; static int n;
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000000ull;
    if (now != sec) { sec = now; n = 0; }
    return ++n <= 30;
}

static id G2G_Core(void) {
    Class ac = NSClassFromString(@"_UIPointerArbiter");
    id arbiter = ac ? G2G_Send0((id)ac, "sharedArbiter") : nil;
    return G2G_Ivar(arbiter, "_core");
}

// ---------------------------------------------------------------------------------------------- the display change observer

static id gG2GObserver;

static void G2G_PointerMoved(id self, SEL _cmd, id from, id to) {
    @try {
        id core = G2G_Core();
        id region = G2G_Send0(core, "activePointerRegion");
        id style = G2G_Send0(core, "activePointerStyle");
        id last = G2G_Send0(core, "lastSentHoverRegion");
        long long state = core && [core respondsToSelector:@selector(pointerState)] ? ((long long (*)(id, SEL))objc_msgSend)(core, @selector(pointerState)) : -1;
        id view = G2G_Send0(region, "referenceView");
        if (!view && region && style && [core respondsToSelector:sel_registerName("_coordinateSpaceSourceViewForRegion:withStyle:")])
            view = ((id (*)(id, SEL, id, id))objc_msgSend)(core, sel_registerName("_coordinateSpaceSourceViewForRegion:withStyle:"), region, style);
        id window = [view isKindOfClass:[UIView class]] ? ((UIView *)view).window : nil;
        id scene = G2G_Send0(window, "windowScene");
        G2G_LOG(@"g2g: SpringBoard pid %d: pointer moved from window scene %p to %p; arbiter: active region %@ (view %@ in window scene %p) lastSent %@ pointerState %lld",
                (int)getpid(), from, to, G2G_Short(region), view ? NSStringFromClass([view class]) : @"nil", scene, last ? @"yes" : @"nil", state);
        if (!G2G_ON() || !region || !from || from == to) return;
        if (scene != from) { G2G_LOG(@"g2g: active region does not belong to the window scene that was left (%p): kept", from); return; }
        __weak id wcore = core;
        dispatch_async(dispatch_get_main_queue(), ^{
            id c = wcore;
            if (!c || G2G_Send0(c, "activePointerRegion") != region) { G2G_LOG(@"g2g: region already ended by UIKit, nothing to do"); return; }
            Class ac = NSClassFromString(@"_UIPointerArbiter");
            id arbiter = ac ? G2G_Send0((id)ac, "sharedArbiter") : nil;
            SEL ex = sel_registerName("exitRegion:removeStyle:completion:");
            if (!arbiter || ![arbiter respondsToSelector:ex]) { G2G_LOG(@"g2g: _UIPointerArbiter exitRegion:removeStyle:completion: missing"); return; }
            G2G_LOG(@"g2g: exiting the hover region of the display the pointer left (UIKit did not): %@", G2G_Short(region));
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(arbiter, ex, region, YES, nil);
        });
    } @catch (NSException *e) {
        BP_Log(@"g2g: exception in pointer observer: %@", e);
    }
}

static int gG2GTries;
static void G2G_Register(void) {
    UIApplication *app = [UIApplication sharedApplication];
    SEL cs = NSSelectorFromString(@"multiDisplayUserInteractionCoordinator");
    id coord = (app && [app respondsToSelector:cs]) ? ((id (*)(id, SEL))objc_msgSend)(app, cs) : nil;
    SEL add = NSSelectorFromString(@"addPointerInteractionObserver:");
    if (coord && [coord respondsToSelector:add]) {
        ((void (*)(id, SEL, id))objc_msgSend)(coord, add, gG2GObserver);
        BP_Log(@"g2g: observer registered at the multi display user interaction coordinator (SpringBoard pid %d)", (int)getpid());
        return;
    }
    if (++gG2GTries > 60) { BP_Log(@"g2g: coordinator / addPointerInteractionObserver: not found after %d tries, observer not registered", gG2GTries); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ G2G_Register(); });
}

// ---------------------------------------------------------------------------------------------- arbiter trace (debug only)

static IMP gG2GOrigExit, gG2GOrigSet, gG2GOrigState, gG2GOrigApply;
static NSMutableArray *gG2GPendingExit;           // regions for which exitRegion was requested after their (possibly still queued) enter; identity compared
static BOOL G2G_StaleOn(void) { return BP_OnName("g2g_staleenter"); }
static void G2G_MarkExit(id region, BOOL on) {
    if (!region) return;
    @synchronized ([NSObject class]) {
        if (!gG2GPendingExit) gG2GPendingExit = [NSMutableArray array];
        NSUInteger i = [gG2GPendingExit indexOfObjectIdenticalTo:region];
        if (on && i == NSNotFound) { [gG2GPendingExit addObject:region]; if (gG2GPendingExit.count > 16) [gG2GPendingExit removeObjectAtIndex:0]; }
        else if (!on && i != NSNotFound) [gG2GPendingExit removeObjectAtIndex:i];
    }
}
static BOOL G2G_IsMarked(id region) {
    if (!region) return NO;
    @synchronized ([NSObject class]) { return gG2GPendingExit && [gG2GPendingExit indexOfObjectIdenticalTo:region] != NSNotFound; }
}

static void G2G_Exit(id self, SEL _cmd, id region, BOOL removeStyle, id completion) {
    if (BP_LogEnabled() && G2G_Rate()) G2G_LOG(@"g2g: arbiter exitRegion removeStyle %d region %@ (active %@)", (int)removeStyle, G2G_Short(region), G2G_Send0(self, "activePointerRegion") == region ? @"yes" : @"no");
    if (G2G_StaleOn()) G2G_MarkExit(region, YES);
    ((void (*)(id, SEL, id, BOOL, id))gG2GOrigExit)(self, _cmd, region, removeStyle, completion);
}
static void G2G_Apply(id self, SEL _cmd, id style, id region, id handler, id completion) {
    G2G_MarkExit(region, NO);                                                       // a real (re)enter after an exit request
    ((void (*)(id, SEL, id, id, id, id))gG2GOrigApply)(self, _cmd, style, region, handler, completion);
}
static void G2G_SetRegion(id self, SEL _cmd, id hover, id style, id pointerRegion, unsigned long long tid, id completion) {
    if (hover && G2G_StaleOn() && G2G_IsMarked(pointerRegion)) {
        G2G_LOG(@"g2g: queued enter of a region whose exit was already requested: shape NOT sent (stale enter, would show the old display's region on the new one): %@", G2G_Short(pointerRegion));
        G2G_MarkExit(pointerRegion, NO);
        ((void (*)(id, SEL, id, id, id, unsigned long long, id))gG2GOrigSet)(self, _cmd, nil, nil, pointerRegion, tid, completion);
        return;
    }
    if (BP_LogEnabled() && G2G_Rate()) G2G_LOG(@"g2g: arbiter sends hover region %@ to pointeruid (pointerState %lld)", hover ? G2G_Short(G2G_Send0(hover, "pointerShape")) : @"NIL (hover ended)",
                                              [self respondsToSelector:@selector(pointerState)] ? ((long long (*)(id, SEL))objc_msgSend)(self, @selector(pointerState)) : -1LL);
    ((void (*)(id, SEL, id, id, id, unsigned long long, id))gG2GOrigSet)(self, _cmd, hover, style, pointerRegion, tid, completion);
}
static void G2G_ClientState(id self, SEL _cmd, id controller) {
    if (BP_LogEnabled() && G2G_Rate()) {
        SEL cs = sel_registerName("clientInteractionState");
        G2G_LOG(@"g2g: pointeruid client interaction state now %lld (0 hidden, 1 normal, 2 fast)", [controller respondsToSelector:cs] ? ((long long (*)(id, SEL))objc_msgSend)(controller, cs) : -1LL);
    }
    ((void (*)(id, SEL, id))gG2GOrigState)(self, _cmd, controller);
}

static IMP G2G_Replace(Class c, const char *sel, IMP imp) {
    SEL s = sel_registerName(sel);
    Method m = class_getInstanceMethod(c, s);
    if (!m) { BP_Log(@"g2g: -[%s %s] not found, trace not installed", class_getName(c), sel); return NULL; }
    IMP orig = method_getImplementation(m);
    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
    return orig;
}

void G2G_Setup(void) {
    BP_Log(@"g2g: SpringBoard pid %d (compare with the global route pids in the g4b-bbd pointerexit lines to see which route is SpringBoard's)", (int)getpid());
    Class core = NSClassFromString(@"_UIPointerArbiterCore_iOS");
    if (core) {
        gG2GOrigExit = G2G_Replace(core, "exitRegion:removeStyle:completion:", (IMP)G2G_Exit);
        gG2GOrigSet = G2G_Replace(core, "_setActiveHoverRegion:style:forPointerRegion:transactionID:completion:", (IMP)G2G_SetRegion);
        gG2GOrigApply = G2G_Replace(core, "applyStyle:forRegion:effectSourceHandler:completion:", (IMP)G2G_Apply);
        gG2GOrigState = G2G_Replace(core, "pointerClientControllerClientInteractionStateDidChange:", (IMP)G2G_ClientState);
    } else {
        BP_Log(@"g2g: _UIPointerArbiterCore_iOS not found, arbiter trace not installed");
    }
    if (!gG2GOrigApply || !gG2GOrigSet || !gG2GOrigExit) BP_Log(@"g2g: arbiter methods missing (exit %p set %p apply %p): stale enter filter cannot work", gG2GOrigExit, gG2GOrigSet, gG2GOrigApply);
    Class oc = objc_allocateClassPair([NSObject class], "BPG2GPointerObserver", 0);
    if (!oc) { BP_Log(@"g2g: observer class could not be created"); return; }
    class_addMethod(oc, NSSelectorFromString(@"pointerDidMoveToFromWindowScene:toWindowScene:"), (IMP)G2G_PointerMoved, "v@:@@");
    objc_registerClassPair(oc);
    gG2GObserver = [[oc alloc] init];
    dispatch_async(dispatch_get_main_queue(), ^{ G2G_Register(); });
    BP_Log(@"g2g: installed (hover exit at pointer display change %s)", G2G_ON() ? "ON" : "off by switch");
}

#pragma clang diagnostic pop
