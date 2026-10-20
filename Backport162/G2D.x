// G2D.x : the home swipe cancels the touch stream of the app (DELIBERATE deviation from stock 16.0 and 16.2).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Switch: g2d_homecancel. Setup: G2D_Setup(). Log lines (Backport162.debug): "[g2d] ...".
//
// Symptom (user video RPReplay_Final1792221811, log bb3ea80d): in Sileo (own bottom popup bar, LNPopup style) a swipe up from the bottom edge that starts ON that bar closes the app,
// but the app keeps receiving the touch stream, its popup bar pan completes and the popup panel stays open inside the closing window and when the app is reopened.
//
// Cause (read from the binaries, same in 16.0 and 16.2, so it is stock behaviour):
//  * The home swipe is the edge pull recogniser of SBFluidSwitcherGestureManager's _deckGrabberTongue (SBGrabberTongue, edge bottom, system gesture type 0x2b,
//    installed by -_updateSwitcherBottomEdgeGesturePresence 16.0 0x1c643f760; -[SBFluidSwitcherGestureManager _gestureTypeForGestureRecognizer:] 0x1c5e585b4 maps it to the home gesture).
//  * -[SBGrabberTongue _createTongueAndGestureRecognizersIfNecessaryWithColorStyle:] 0x1c5e76524 creates it with setCancelsTouchesInView:NO (0x1c5e7662c), and
//    -[SBGrabberTongue gestureRecognizerShouldBegin:] 0x1c5e564a4 re-evaluates it through -_updateCancelsTouchesWithRecognizer: 0x1c5e56b18 right before the recogniser begins:
//        cancelsTouchesInView = (_tongueVisible || [delegate grabberTongue:shouldShowTongueOnFirstSwipeWithEdgeLocation:] (= edge protect, 0x1c5e56c48 -> _shouldProtectEdgeLocation: 0x1c5e56d8c))
//                               && BSFloatIsZero(_ambiguousActivationMarginIfHonored 0x1c5e56ed4)
//    so an ordinary home swipe (no edge protect, no visible tongue) has cancelsTouchesInView == NO.
//  * UIKit (__UISystemGestureManager -_externalGestureRecognizerChanged: 16.0 0x18926eb64) turns the recogniser's Began into
//    [BKSTouchStream setEventDispatchMode:(cancelsTouchesInView ? 3 : 2) ambiguityRecommendation:... lastTouchTimestamp:]; mode 3 makes backboardd cancel the touch for the app, mode 2
//    leaves the touch with the app. So an ordinary home swipe never cancels the touch of the app: the app that was touched first (touch-down 72-100 ms before the recogniser
//    begins; the bar is 12-19 pt above the edge, outside the edge-swipe hold-back zone) keeps seeing the finger move and its own pan completes.
//  * 16.2 (20C65): same logic (-[SBGrabberTongue _updateCancelsTouchesWithRecognizerIfNeeded:] 0x1c784cb54 is the same body plus a "skip the tap recogniser" test; gestureRecognizerShouldBegin:
//    0x1c72c890c only adds log strings; creation 0x1c72e9204 identical call sequence). Nothing to port: the fix is a deviation.
//
// Fix: after the stock update, when the recogniser is the bottom edge pull of the home swipe tongue (edge 4, type 0x2b), no ambiguity margin is in force and an app is in front, set
// cancelsTouchesInView = YES. The recogniser then reports mode 3 at Began, exactly like the edge protect case. Only the moment the home swipe actually begins is affected: normal
// in-app scrolling and gestures keep their touches until then (the recogniser does not begin without the upward swipe), a swipe that fails changes nothing.
// Not touched: tongue of floating applications (left / right edge), indirect (pointer) pan, the tap recogniser, anything while no app is in front.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import <objc/message.h>
#import <math.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2D_ON() BP_OnName("g2d_homecancel")
#define G2D_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static IMP gG2DOrigUpdate;

// scalar ivar read (object_getIvar must not be used for scalars)
static BOOL G2D_ScalarIvar(id o, const char *name, void *out, size_t size) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) return NO;
    memcpy(out, (const char *)(__bridge void *)o + ivar_getOffset(iv), size);
    return YES;
}

// -[SBGrabberTongue _updateCancelsTouchesWithRecognizer:]  16.0 0x1c5e56b18
static void G2D_UpdateCancels(id self, SEL _cmd, id recognizer) {
    if (gG2DOrigUpdate) ((void (*)(id, SEL, id))gG2DOrigUpdate)(self, _cmd, recognizer);
    if (!G2D_ON() || !recognizer) return;
    @try {
        Ivar pullIvar = class_getInstanceVariable(object_getClass(self), "_edgePullGestureRecognizer");
        if (BP_ObjIvar(self, pullIvar) != recognizer) return;                                         // only the touch edge pull (not the indirect pan, not the tap)
        unsigned long long edge = 0, type = 0;
        if (!G2D_ScalarIvar(self, "_screenEdge", &edge, sizeof edge) || !G2D_ScalarIvar(self, "_systemGestureType", &type, sizeof type)) return;
        if (edge != 4 || type != 0x2b) return;                                                        // bottom edge, the deck (home swipe) tongue
        SEL mS = NSSelectorFromString(@"_ambiguousActivationMarginIfHonored");
        double margin = [self respondsToSelector:mS] ? ((double (*)(id, SEL))objc_msgSend)(self, mS) : 0.0;
        if (fabs(margin) > 1e-9) return;                                                              // ambiguity margin honoured: stock keeps the touch with the app on purpose
        id app = nil;
        SEL fS = NSSelectorFromString(@"_accessibilityFrontMostApplication");
        id sharedApp = [UIApplication sharedApplication];
        if ([sharedApp respondsToSelector:fS]) {
            app = ((id (*)(id, SEL))objc_msgSend)(sharedApp, fS);
            if (!app) return;                                                                         // no app in front (home screen): leave the stock value
        }
        if (![recognizer respondsToSelector:@selector(cancelsTouchesInView)] || [recognizer cancelsTouchesInView]) return;   // already cancelling (edge protect / tongue visible)
        [recognizer setCancelsTouchesInView:YES];
        G2D_LOG(@"[g2d] home swipe recogniser %p: cancelsTouchesInView NO -> YES (front app %@): the app's touch is cancelled when the home swipe begins", recognizer, app);
    } @catch (NSException *e) {
        G2D_LOG(@"[g2d] exception %@", e);
    }
}


// Darwin notifications posted by the backboardd and pointeruid dylibs at the stages of their start-up (BBD.x / PTR.x): logged here because those daemons often cannot write files.
static void G2D_ListenForDaemonLoads(void) {
    static const char *names[] = {
        "com.infernowolf19.backport162.load.bbd.ctor_entered", "com.infernowolf19.backport162.load.bbd.not_backboardd_leaving", "com.infernowolf19.backport162.load.bbd.build_mismatch_leaving",
        "com.infernowolf19.backport162.load.bbd.crash_guard_tripped_leaving", "com.infernowolf19.backport162.load.bbd.installing",
        "com.infernowolf19.backport162.load.ptr.ctor_entered", "com.infernowolf19.backport162.load.ptr.not_pointeruid_leaving", "com.infernowolf19.backport162.load.ptr.build_mismatch_leaving",
        "com.infernowolf19.backport162.load.ptr.installing",
        "com.infernowolf19.backport162.load.spk.crash_guard_tripped",      // SPK.c (audio daemons): its crash guard kept the hooks out of a launch
    };
    for (size_t i = 0; i < sizeof names / sizeof names[0]; i++) {
        const char *nm = names[i];
        int token = 0;
        notify_register_dispatch(nm, &token, dispatch_get_main_queue(), ^(int t) { BP_Log(@"daemon load note: %s", nm + strlen("com.infernowolf19.backport162.load.")); });
        int chk = 0; uint64_t pid = 0;                                          // posted before SpringBoard started: the daemon left its pid as the state
        if (notify_register_check(nm, &chk) == NOTIFY_STATUS_OK && notify_get_state(chk, &pid) == NOTIFY_STATUS_OK && pid) BP_Log(@"daemon load note (earlier, pid %llu): %s", (unsigned long long)pid, nm + strlen("com.infernowolf19.backport162.load."));
    }
}

// The daemon halves (backboardd, pointeruid) cannot write to <jbroot>/tmp (see BPDaemon.h): they append to Backport162.daemon.log in a directory they can write to; copy their new lines
// into Backport162.log (prefix "daemon:") while logging is on.  Directories as in BPDaemon.h.  Every 2 s, at most 64 KiB per file and tick.
static void G2D_IngestDaemonLog(void) {
    static const char *const dirs[] = { "/var/jb/var/mobile/Library/Caches", "/var/jb/var/mobile/Library/Preferences", "/var/jb/var/mobile", "/var/jb/tmp", "/var/mobile/Library/Caches", "/var/mobile", "/tmp" };    // as in BPDaemon.h
    static off_t offsets[7];
    static dispatch_source_t t;                                                // kept: a timer source nobody references is released and never fires
    dispatch_queue_t q = dispatch_queue_create("com.infernowolf19.backport162.daemonlog", DISPATCH_QUEUE_SERIAL);
    t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, 500 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(t, ^{
        if (!BP_LogEnabled()) return;
        for (size_t i = 0; i < sizeof dirs / sizeof dirs[0]; i++) {
            char path[300]; snprintf(path, sizeof path, "%s/Backport162.daemon.log", dirs[i]);
            struct stat st;
            if (stat(path, &st) != 0) continue;
            if (st.st_size < offsets[i]) offsets[i] = 0;                       // truncated by the daemon
            if (st.st_size == offsets[i]) continue;
            int fd = open(path, O_RDONLY | O_CLOEXEC);
            if (fd < 0) { BP_Log(@"[g2d] cannot read %s (errno %d)", path, errno); continue; }
            size_t want = (size_t)(st.st_size - offsets[i]);
            if (want > 65536) want = 65536;
            char *buf = malloc(want + 1);
            ssize_t n = buf ? pread(fd, buf, want, offsets[i]) : -1;
            close(fd);
            if (n > 0) {
                size_t used = (size_t)n;
                while (used > 0 && buf[used - 1] != '\n') used--;               // only whole lines
                if (used == 0) used = (size_t)n;
                buf[used] = 0;
                offsets[i] += (off_t)used;
                NSString *text = [NSString stringWithUTF8String:buf] ?: @"(not UTF-8)";
                for (NSString *line in [text componentsSeparatedByString:@"\n"]) if (line.length) BP_Log(@"daemon: %@", line);
            }
            free(buf);
        }
    });
    dispatch_resume(t);
}

void G2D_Setup(void) {
    G2D_ListenForDaemonLoads();
    G2D_IngestDaemonLog();
    if (!G2D_ON()) return;
    Class c = NSClassFromString(@"SBGrabberTongue");
    SEL s = NSSelectorFromString(@"_updateCancelsTouchesWithRecognizer:");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) { BP_Log(@"[g2d] SBGrabberTongue _updateCancelsTouchesWithRecognizer: not found, not installed"); return; }
    gG2DOrigUpdate = method_getImplementation(m);
    class_replaceMethod(c, s, (IMP)G2D_UpdateCancels, method_getTypeEncoding(m));
    BP_Log(@"[g2d] installed (home swipe cancels the touch stream of the app)");
}
#pragma clang diagnostic pop
