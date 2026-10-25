// Y14Open.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): opening an application for a URL picks the display.  Setup: constructor.  Log prefix "[y14]".
//
//  y14_openurl  -[SpringBoard _openURLCore:display:animating:activationSettings:origin:withResult:] 16.2 0x1c735d6c4 (16.0 0x1c5ee955c).  16.0 asks the main workspace for the transition with
//               -requestTransitionWithBuilder:, i.e. on the main display (the iPad) whichever display the link was tapped on.  16.2 first asks
//               -[SBMainWorkspace _targetWindowSceneForApplication:preferringDisplay:requireForeground:options:] (16.2 0x1c7378764, 16.0 0x1c5f04228, the same method that the 16.0 open application request
//               path uses) for the window scene: preferringDisplay nil, requireForeground = !application.info.shouldLaunchSuspendedAlways, options = {FBSOpenApplicationOptionKeyPayloadURL: url}
//               (the scene that already shows the application / the URL's content identifier, then the scene with keyboard focus, else the active display's) and requests the transition for
//               [scene _fbsDisplayConfiguration] with -requestTransitionWithOptions:0 displayConfiguration:builder:.  The builder block is the 16.0 one.
//               Ported: while the 16.0 body runs (thread local: application, URL, suspended flag) -requestTransitionWithBuilder: is answered with the display aware request.  A link tapped in a window
//               on the monitor opens its target on the monitor.
// Needs a device with the monitor: tap a web link / universal link in an app window on the monitor so that another app opens: that app opens on the monitor (and without this switch on the iPad).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static __thread __unsafe_unretained id tY14App;
static __thread __unsafe_unretained id tY14URL;
static __thread BOOL tY14Armed;
static IMP gY14OrigOpen, gY14OrigRequest;

static NSString *Y14_URLKey(void) {
    static NSString *key;
    if (!key) {
        NSString *const *p = (NSString *const *)dlsym(RTLD_DEFAULT, "FBSOpenApplicationOptionKeyPayloadURL");
        key = (p && *p) ? *p : @"__PayloadURL";
    }
    return key;
}

// -[SpringBoard _openURLCore:display:animating:activationSettings:origin:withResult:]
static void Y14_OpenURLCore(id self, SEL _cmd, id url, id app, BOOL animating, id settings, id origin, id result) {
    BOOL sArm = tY14Armed; id sApp = tY14App, sURL = tY14URL;
    tY14Armed = BP_OnName("y14_openurl") && app && settings;
    tY14App = app; tY14URL = url;
    if (gY14OrigOpen) ((void (*)(id, SEL, id, id, BOOL, id, id, id))gY14OrigOpen)(self, _cmd, url, app, animating, settings, origin, result);
    tY14Armed = sArm; tY14App = sApp; tY14URL = sURL;
}
// -[SBMainWorkspace requestTransitionWithBuilder:]
static BOOL Y14_RequestWithBuilder(id self, SEL _cmd, id builder) {
    if (tY14Armed && tY14App) {
        tY14Armed = NO;                                                  // only the one request of that open
        id app = tY14App, url = tY14URL;
        BOOL suspended = BPX_Bool0(BPX_Obj0(app, "info"), "shouldLaunchSuspendedAlways");
        NSMutableDictionary *opts = [NSMutableDictionary dictionary];
        if (url) opts[Y14_URLKey()] = url;
        id scene = BPY_SEND(id, (id, id, BOOL, id), self, "_targetWindowSceneForApplication:preferringDisplay:requireForeground:options:", app, nil, !suspended, opts);
        id config = BPX_Obj0(scene, "_fbsDisplayConfiguration");
        if (config && BPY_Responds(self, "requestTransitionWithOptions:displayConfiguration:builder:")) {
            BPY_LOG(@"[y14] open %@ for URL: display %@ (scene %@)", app, config, scene);
            return BPY_SEND(BOOL, (unsigned long long, id, id), self, "requestTransitionWithOptions:displayConfiguration:builder:", 0ULL, config, builder);
        }
    }
    return gY14OrigRequest ? ((BOOL (*)(id, SEL, id))gY14OrigRequest)(self, _cmd, builder) : NO;
}

__attribute__((constructor)) static void Y14_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class sb = NSClassFromString(@"SpringBoard"), wk = NSClassFromString(@"SBMainWorkspace");
        if (sb && wk && class_getInstanceMethod(sb, sel_registerName("_openURLCore:display:animating:activationSettings:origin:withResult:")) &&
            class_getInstanceMethod(wk, sel_registerName("requestTransitionWithBuilder:")) &&
            class_getInstanceMethod(wk, sel_registerName("_targetWindowSceneForApplication:preferringDisplay:requireForeground:options:")) &&
            class_getInstanceMethod(wk, sel_registerName("requestTransitionWithOptions:displayConfiguration:builder:"))) {
            gY14OrigOpen = BPX_Replace(sb, "_openURLCore:display:animating:activationSettings:origin:withResult:", (IMP)Y14_OpenURLCore);
            gY14OrigRequest = BPX_Replace(wk, "requestTransitionWithBuilder:", (IMP)Y14_RequestWithBuilder);
            BP_Log(@"[y14] installed (switch y14_openurl): URL opens choose the display");
        } else BP_Log(@"[y14] NOT installed (class or selector missing)");
    }
}
#pragma clang diagnostic pop
