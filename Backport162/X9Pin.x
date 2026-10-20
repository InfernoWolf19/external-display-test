// X9Pin.x : gap G9 / audit row P1 "pinOnButtonDown for system-gesture windows" (specs/GAPS-IMPLEMENTED-0.7.9.md section G9, specs/POINTER-CROSS-0.7.4.md 2.2 / 4.3).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).  Switch: pinbuttondown.  Setup: X9_Setup().  Log prefix "[x9]" (Backport162.debug only).
//
// 16.2 -[SBSystemGestureManager _configureForNewSystemGestureWindowIfNecessary] (0x1c77b912c; 16.0 0x1c6319958) registers the system gesture window of a display for global mouse events
// (the pointer events the window gets wherever the pointer is on that display, used by the edge / pointer system gestures):
//     16.0 0x1c6319b88   [[BKSMousePointerService sharedInstance] requestGlobalMouseEventsForDisplay:hardwareIdentifier targetContextID:contextId]
//     16.2 0x1c77b937c   [[BKSMousePointerService sharedInstance] requestGlobalMouseEventsForDisplay:hardwareIdentifier targetContextID:contextId
//                                                                  options:[BKSMousePointerGlobalContextOptions build:^(m){ [m setPinOnButtonDown:SBFIsChamoisExternalDisplayControllerAvailable()]; }]]
//                        (block 0x1c77b9458: _SBFIsChamoisExternalDisplayControllerAvailable, then setPinOnButtonDown:); the returned assertion is stored in the same ivar (+0x60) in both builds.
// BackBoardServices 16.0 has the whole options API already (BKSMousePointerGlobalContextOptions +build:, BKSMutableMousePointerGlobalContextOptions setPinOnButtonDown:, the 3-argument
// request method 0x18e204d9c; the 2-argument method 0x18e2051d8 is a tail call of it with options nil), and backboardd 16.0 reads the flag (bbd 0x100050f28, "pinning global destination": a
// button-down drag keeps going to the contexts pinned at the button-down, across displays).  So the SpringBoard half is: pass the options.
// 16.0 flag: SBFIsChamoisExternalDisplayControllerAvailable is the graduated 16.2 name of SBFFeatureFlagsIsChamoisExternalDisplayControllerEnabled (16.0 SpringBoardFoundation 0x18eb68fd4;
// 16.2 0x18ee096e4); on 16.0 the plist has the flag ON (FEATURES-0.7.9 section 1), so the value is YES wherever the port runs.
//
// Port: a hook of the one caller (a thread local marks "inside _configureForNew...") and a hook of the 3-argument BackBoardServices method that replaces a nil options argument, only while
// marked, by the 16.2 options.  The only caller of the 2- and 3-argument methods in SpringBoard 16.0 and 16.2 is that method (stub caller scan), so nothing else is touched.
// Needs a device: drag a window by the pointer across the display boundary; the pointer log of backboardd ("pinning global destination") shows the pin.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define X9_ON() BP_OnName("pinbuttondown")

static __thread int gX9InConfigure;
static IMP gX9OrigConfigure, gX9OrigRequest;

static BOOL X9_ChamoisAvailable(void) {
    static BOOL (*fn)(void); static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFIsChamoisExternalDisplayControllerAvailable");                 // 16.2 name
        if (!fn) fn = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFFeatureFlagsIsChamoisExternalDisplayControllerEnabled");   // 16.0 name of the same flag
        if (!fn) BP_Log(@"[x9] neither SBFIsChamoisExternalDisplayControllerAvailable nor SBFFeatureFlagsIsChamoisExternalDisplayControllerEnabled found: pinOnButtonDown stays NO");
    });
    return fn ? fn() : NO;
}

static void X9_Configure(id self, SEL _cmd) {
    gX9InConfigure++;
    if (gX9OrigConfigure) ((void (*)(id, SEL))gX9OrigConfigure)(self, _cmd);
    gX9InConfigure--;
}

// -[BKSMousePointerService requestGlobalMouseEventsForDisplay:targetContextID:options:] 16.0 0x18e204d9c
static id X9_Request(id self, SEL _cmd, id display, unsigned int ctx, id options) {
    if (gX9InConfigure > 0 && !options && X9_ON()) {
        Class oc = NSClassFromString(@"BKSMousePointerGlobalContextOptions");
        SEL build = sel_registerName("build:");
        if (oc && [oc respondsToSelector:build]) {
            BOOL pin = X9_ChamoisAvailable();
            void (^blk)(id) = ^(id m) { BPX_SetBool1(m, "setPinOnButtonDown:", pin); };
            id opts = ((id (*)(id, SEL, id))objc_msgSend)((id)oc, build, blk);
            if (opts) {
                options = opts;
                BPX_LOG(@"[x9] global mouse events for display %@ context %u: options %@ (pinOnButtonDown %d)", display, ctx, opts, (int)pin);
            } else {
                BP_Log(@"[x9] BKSMousePointerGlobalContextOptions build: returned nil, request left without options");
            }
        } else {
            BP_Log(@"[x9] BKSMousePointerGlobalContextOptions build: missing, request left without options");
        }
    }
    return gX9OrigRequest ? ((id (*)(id, SEL, id, unsigned int, id))gX9OrigRequest)(self, _cmd, display, ctx, options) : nil;
}

void X9_Setup(void) {
    Class sg = NSClassFromString(@"SBSystemGestureManager");
    Class bk = NSClassFromString(@"BKSMousePointerService");
    const char *kCfg = "_configureForNewSystemGestureWindowIfNecessary", *kReq = "requestGlobalMouseEventsForDisplay:targetContextID:options:";
    BOOL ok = sg && bk && class_getInstanceMethod(sg, sel_registerName(kCfg)) && class_getInstanceMethod(bk, sel_registerName(kReq));
    if (ok) {
        gX9OrigConfigure = BPX_Replace(sg, kCfg, (IMP)X9_Configure);
        gX9OrigRequest = BPX_Replace(bk, kReq, (IMP)X9_Request);
    }
    BP_Log(@"[x9] pinOnButtonDown for system gesture windows: %s", ok ? "installed" : "NOT installed (class or selector missing)");
}
#pragma clang diagnostic pop
