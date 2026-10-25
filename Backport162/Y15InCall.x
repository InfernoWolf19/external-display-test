// Y15InCall.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): an In-Call presentation session (FaceTime / call UI) follows the display of its scene.  Setup: constructor.  Log prefix "[y15]".
// X6InCall.x already keeps the session's scene manager / screen / window scene on the display of the scene handle (G6); these are the places of the session and its manager that still asked
// the MAIN display (or the ACTIVE display) in 16.0:
//
//  y15_incallreq   -[SBInCallPresentationSession _performBannerToFullScreenPresentationTransitionAnimated:analyticsSource:completion:] 16.2 0x1c757bbd8 (16.0 0x1c60f6ca4) and
//                  -[...  _performSwitcherDismissalTransitionAnimated:shouldDestroyScene:analyticsSource:completion:] 16.2 0x1c757d4c4 (16.0 0x1c60f8338) request their workspace transition with
//                  -requestTransitionWithOptions:displayConfiguration:builder:validator: for the display of the session's window scene ([[self windowScene] _fbsDisplayConfiguration], the banner to full
//                  screen one through -[windowSceneManager windowSceneForSceneHandle:]); 16.0 uses -requestTransitionWithOptions:builder:validator:, the main display, so expanding a call banner or
//                  dismissing the call UI of a call that lives on the monitor changed the iPad's layout.  Ported: while the 16.0 body of either method runs (thread local) the one request it makes is
//                  redirected to the 16.2 variant of the same call.
//  y15_bannerscene -[SBInCallPresentationSession _performBannerPresentationTransitionWithAnalyticsSource:completion:] 16.2 0x1c757c7f0 (16.0 0x1c60f783c) measures the banner in the session's own window scene
//                  ([self windowScene]); 16.0 in the ACTIVE display's scene ([[springBoard windowSceneManager] activeDisplayWindowScene]).  Ported: -_presentedBannerBoundsInWindowScene: is given the
//                  session's scene while that method runs.
//  y15_bannerorient  -[SBInCallPresentationManager inCallClientPresentationSessionInterfaceOrientationForBannerPresentation:] 16.2 0x1c766...(16.0 0x1c61da180) asks the delegate
//                  -inCallPresentationManager:interfaceOrientationForBannerPresentationInWindowScene: with the session's scene; the answer (SBMainWorkspace 16.2 0x1c7373010) is the active interface orientation
//                  for the main display scene and [scene interfaceOrientation] for any other.  16.0 asks the delegate for the main display's orientation only.  Ported: the other display's scene answers
//                  with its own interface orientation.
// Needs a device with the monitor: start a FaceTime / call app on the monitor, tap the banner to expand it, then dismiss the call UI: only the monitor changes.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y15Rect;      // CGRect (HFA, d0..d3)

static __thread __unsafe_unretained id tY15Config;              // display configuration for the next workspace request of the wrapped session method
static __thread __unsafe_unretained id tY15BannerSession;       // session whose banner presentation runs
static IMP gY15OrigFull, gY15OrigDismiss, gY15OrigBanner, gY15OrigBounds, gY15OrigReq, gY15OrigOrient;

static id Y15_Config(id session, BOOL viaHandle) {
    if (!BP_OnName("y15_incallreq")) return nil;
    id scene = nil;
    if (viaHandle) scene = BPX_Obj1(BPX_WindowSceneManager(), "windowSceneForSceneHandle:", BPX_IvarObj(session, "_sceneHandle"));
    if (!scene) scene = BPX_Obj0(session, "windowScene");
    return BPX_Obj0(scene, "_fbsDisplayConfiguration");
}

// -[SBInCallPresentationSession _performBannerToFullScreenPresentationTransitionAnimated:analyticsSource:completion:]
static void Y15_Full(id self, SEL _cmd, BOOL animated, long long source, id completion) {
    id saved = tY15Config;
    tY15Config = Y15_Config(self, YES);
    if (gY15OrigFull) ((void (*)(id, SEL, BOOL, long long, id))gY15OrigFull)(self, _cmd, animated, source, completion);
    tY15Config = saved;
}
// -[SBInCallPresentationSession _performSwitcherDismissalTransitionAnimated:shouldDestroyScene:analyticsSource:completion:]
static void Y15_Dismiss(id self, SEL _cmd, BOOL animated, BOOL destroy, long long source, id completion) {
    id saved = tY15Config;
    tY15Config = Y15_Config(self, NO);
    if (gY15OrigDismiss) ((void (*)(id, SEL, BOOL, BOOL, long long, id))gY15OrigDismiss)(self, _cmd, animated, destroy, source, completion);
    tY15Config = saved;
}
// -[SBMainWorkspace requestTransitionWithOptions:builder:validator:]
static BOOL Y15_Request(id self, SEL _cmd, unsigned long long options, id builder, id validator) {
    id cfg = tY15Config;
    if (cfg && BPY_Responds(self, "requestTransitionWithOptions:displayConfiguration:builder:validator:")) {
        tY15Config = nil;                                                // the one request of the wrapped method
        BPY_LOG(@"[y15] call transition request goes to display %@", cfg);
        return BPY_SEND(BOOL, (unsigned long long, id, id, id), self, "requestTransitionWithOptions:displayConfiguration:builder:validator:", options, cfg, builder, validator);
    }
    return gY15OrigReq ? ((BOOL (*)(id, SEL, unsigned long long, id, id))gY15OrigReq)(self, _cmd, options, builder, validator) : NO;
}
// -[SBInCallPresentationSession _performBannerPresentationTransitionWithAnalyticsSource:completion:]
static void Y15_Banner(id self, SEL _cmd, long long source, id completion) {
    id saved = tY15BannerSession;
    tY15BannerSession = BP_OnName("y15_bannerscene") ? self : nil;
    if (gY15OrigBanner) ((void (*)(id, SEL, long long, id))gY15OrigBanner)(self, _cmd, source, completion);
    tY15BannerSession = saved;
}
// -[SBInCallPresentationSession _presentedBannerBoundsInWindowScene:]
static Y15Rect Y15_Bounds(id self, SEL _cmd, id scene) {
    if (tY15BannerSession == self) {
        id own = BPX_Obj0(self, "windowScene");
        if (own) scene = own;
    }
    Y15Rect z = {0, 0, 0, 0};
    return gY15OrigBounds ? ((Y15Rect (*)(id, SEL, id))gY15OrigBounds)(self, _cmd, scene) : z;
}
// -[SBInCallPresentationManager inCallClientPresentationSessionInterfaceOrientationForBannerPresentation:]
static long long Y15_Orient(id self, SEL _cmd, id session) {
    if (BP_OnName("y15_bannerorient")) {
        id scene = BPX_Obj0(session, "windowScene");
        if (scene && !BPX_Bool0(scene, "isMainDisplayWindowScene") && BPY_Responds(scene, "interfaceOrientation")) return BPX_LL0(scene, "interfaceOrientation");
    }
    return gY15OrigOrient ? ((long long (*)(id, SEL, id))gY15OrigOrient)(self, _cmd, session) : 0;
}

__attribute__((constructor)) static void Y15_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class ss = NSClassFromString(@"SBInCallPresentationSession"), wk = NSClassFromString(@"SBMainWorkspace"), mg = NSClassFromString(@"SBInCallPresentationManager");
        if (ss && wk && class_getInstanceMethod(wk, sel_registerName("requestTransitionWithOptions:builder:validator:")) &&
            class_getInstanceMethod(ss, sel_registerName("_performBannerToFullScreenPresentationTransitionAnimated:analyticsSource:completion:")) &&
            class_getInstanceMethod(ss, sel_registerName("_performSwitcherDismissalTransitionAnimated:shouldDestroyScene:analyticsSource:completion:"))) {
            gY15OrigFull = BPX_Replace(ss, "_performBannerToFullScreenPresentationTransitionAnimated:analyticsSource:completion:", (IMP)Y15_Full);
            gY15OrigDismiss = BPX_Replace(ss, "_performSwitcherDismissalTransitionAnimated:shouldDestroyScene:analyticsSource:completion:", (IMP)Y15_Dismiss);
            gY15OrigReq = BPX_Replace(wk, "requestTransitionWithOptions:builder:validator:", (IMP)Y15_Request);
            n++;
        }
        if (ss && class_getInstanceMethod(ss, sel_registerName("_performBannerPresentationTransitionWithAnalyticsSource:completion:")) && class_getInstanceMethod(ss, sel_registerName("_presentedBannerBoundsInWindowScene:"))) {
            gY15OrigBanner = BPX_Replace(ss, "_performBannerPresentationTransitionWithAnalyticsSource:completion:", (IMP)Y15_Banner);
            gY15OrigBounds = BPX_Replace(ss, "_presentedBannerBoundsInWindowScene:", (IMP)Y15_Bounds);
            n++;
        }
        if (mg && class_getInstanceMethod(mg, sel_registerName("inCallClientPresentationSessionInterfaceOrientationForBannerPresentation:"))) {
            gY15OrigOrient = BPX_Replace(mg, "inCallClientPresentationSessionInterfaceOrientationForBannerPresentation:", (IMP)Y15_Orient);
            n++;
        }
        BP_Log(@"[y15] installed %d of 3 In-Call groups (switches y15_incallreq, y15_bannerscene, y15_bannerorient)", n);
    }
}
#pragma clang diagnostic pop
