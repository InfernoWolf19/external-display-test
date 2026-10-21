// X5Recording.x : gap G5 / audit row R1 "per display recording indicator" (specs/GAPS-IMPLEMENTED-0.7.9.md section G5).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).  Switch: recindicator.  Setup: X5_Setup().  Log prefix "[x5]" (Backport162.debug only).
//
// 16.0: ONE SBRecordingIndicatorManager, for the main display window scene only.  -[SpringBoard _startRecordingIndicatorForMainDisplayWindowScene:] 0x1c5edc0e8 creates it
// ([[SBRecordingIndicatorManager alloc] initWithSensorActivityDataProvider:[SBApp sensorActivityDataProvider] windowScene:scene], kept by the SBEmbeddedDisplayWindowSceneDelegate:
// -recordingIndicatorManager 0x1c63a1564) and -[SpringBoard recordingIndicatorManagerForMainDisplay] 0x1c5eecae0 (the embedded scene's delegate's manager) is what the
// status bar code asks: SBDeviceApplicationSceneViewController _configureStatusBarWithCurrentStyleRequest 0x1c6131a18 (updateRecordingIndicatorForStatusBarChanges), SBStatusBarStateAggregator
// _updateSensorActivityItem, SBMainDisplaySceneLayoutStatusBarView (x2), SBTransientOverlayScenePresenter _updateStatusBarWithCurrentExternalStatusBarSettings:animated: 0x1c6496498,
// SBRecordingIndicatorSystemApertureElement (x2).
// 16.2: every window scene delegate makes its own manager in _configureForConnectingWindowScene:windowSceneContext: (SBEmbeddedDisplayWindowSceneDelegate 0x1c784b4b4,
// SBExternalDisplayWindowSceneDelegate 0x1c7467ed8: [[SBRecordingIndicatorManager alloc] initWithWindowScene:scene], stored with SBWindowSceneContext setRecordingIndicatorManager:), and
// -[SBWindowScene recordingIndicatorManager] 0x1c77f82ac hands it out; the manager's init (0x1c74617f0) no longer takes a provider (it uses the shared one).  The per scene consumers ask their own
// scene: SBDeviceApplicationSceneViewController _configureStatusBarWithCurrentStyleRequest 0x1c75bc7c4 ([[self _sbWindowScene] recordingIndicatorManager]); the aggregator, the layout status
// bar view and the system aperture element keep the main display (16.2 asks [mainDisplayWindowScene recordingIndicatorManager]); SBTransientOverlayScenePresenter no longer calls it.
// -[SBRecordingIndicatorViewController _screenTypeForcesFastFadeAnimations] 16.0 0x1c62d3774 / 16.2 0x1c776e7f4 changes from "screen type in 0x15..0x18" to the Jindo (Dynamic Island) artwork
// subtypes 0xaec / 0x9fc: iPhone only, not ported.  The manager class itself is unchanged apart from its init (body diff: only _createRecordingIndicatorForStatusBarLocation 62 -> 66 insns).
//
// Port: a manager per external display window scene (16.0 initializer, same provider), kept by the external delegate (associated object; the 16.0 class has no such ivar), handed out by
// SBWindowScene -recordingIndicatorManager, and the one per scene consumer (the device application scene view controller) asks its own scene: its call is wrapped, and
// -[SpringBoard recordingIndicatorManagerForMainDisplay] answers the wrapped scene's manager while the wrapper runs.  The indicator window of an external manager is made by the manager itself in
// its window scene (the status bar / standalone location code of the 16.0 manager), nothing display specific was changed in that class.  Needs a device: start a camera / microphone app
// with the monitor connected: the indicator dot should appear on the monitor too.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define X5_ON() BP_OnName("recindicator")

static char kX5ManagerKey;
static IMP gX5OrigConfigure, gX5OrigForMain, gX5OrigStatusBarCfg;
static __thread void *gX5Scene;                    // unretained window scene while the wrapped status bar configuration runs

static id X5_DelegateManager(id self, SEL _cmd) { return objc_getAssociatedObject(self, &kX5ManagerKey); }
static void X5_DelegateSetManager(id self, SEL _cmd, id m) { objc_setAssociatedObject(self, &kX5ManagerKey, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

// -[SBWindowScene recordingIndicatorManager] 16.2 0x1c77f82ac
static id X5_SceneManager(id self, SEL _cmd) { return BPX_Obj0(BPX_Obj0(self, "delegate"), "recordingIndicatorManager"); }

// SBExternalDisplayWindowSceneDelegate _configureForConnectingWindowScene:windowSceneContext: 16.2 0x1c7467ed8
static void X5_Configure(id self, SEL _cmd, id scene, id context) {
    if (gX5OrigConfigure) ((void (*)(id, SEL, id, id))gX5OrigConfigure)(self, _cmd, scene, context);
    if (!X5_ON() || !scene) return;
    Class mc = NSClassFromString(@"SBRecordingIndicatorManager");
    SEL init = sel_registerName("initWithSensorActivityDataProvider:windowScene:");
    id provider = BPX_Obj0(BPX_App(), "sensorActivityDataProvider");
    if (!mc || ![mc instancesRespondToSelector:init] || !provider) {
        BP_Log(@"[x5] recording indicator manager for %@ not made (class %p, provider %@)", scene, (__bridge void *)mc, provider);
        return;
    }
    id mgr = ((id (*)(id, SEL, id, id))objc_msgSend)([mc alloc], init, provider, scene);
    X5_DelegateSetManager(self, NULL, mgr);
    BP_Log(@"[x5] recording indicator manager %@ for external window scene %@", mgr, scene);
}

// -[SpringBoard recordingIndicatorManagerForMainDisplay]: while the per scene consumer runs, the manager of ITS scene
static id X5_ForMainDisplay(id self, SEL _cmd) {
    void *p = gX5Scene;
    if (p && X5_ON()) return BPX_Obj0((__bridge id)p, "recordingIndicatorManager");
    return gX5OrigForMain ? ((id (*)(id, SEL))gX5OrigForMain)(self, _cmd) : nil;
}
// SBDeviceApplicationSceneViewController _configureStatusBarWithCurrentStyleRequest 16.0 0x1c6131834 (16.2 0x1c75bc5ec: [[self _sbWindowScene] recordingIndicatorManager] at 0x1c75bc7c4)
static void X5_StatusBarCfg(id self, SEL _cmd) {
    void *prev = gX5Scene;
    if (X5_ON()) gX5Scene = (__bridge void *)BPX_Obj0(self, "_sbWindowScene");
    if (gX5OrigStatusBarCfg) ((void (*)(id, SEL))gX5OrigStatusBarCfg)(self, _cmd);
    gX5Scene = prev;
}

void X5_Setup(void) {
    Class ext = NSClassFromString(@"SBExternalDisplayWindowSceneDelegate");
    Class ws = NSClassFromString(@"SBWindowScene");
    Class sb = NSClassFromString(@"SpringBoard");
    Class vc = NSClassFromString(@"SBDeviceApplicationSceneViewController");
    const char *kCfg = "_configureForConnectingWindowScene:windowSceneContext:", *kMain = "recordingIndicatorManagerForMainDisplay", *kSB = "_configureStatusBarWithCurrentStyleRequest";
    BOOL ok = ext && ws && sb && vc && class_getInstanceMethod(ext, sel_registerName(kCfg)) && class_getInstanceMethod(sb, sel_registerName(kMain))
           && class_getInstanceMethod(vc, sel_registerName(kSB)) && NSClassFromString(@"SBRecordingIndicatorManager");
    if (!ok) { BP_Log(@"[x5] per display recording indicator NOT installed (class or selector missing)"); return; }
    class_addMethod(ext, sel_registerName("recordingIndicatorManager"), (IMP)X5_DelegateManager, "@16@0:8");
    class_addMethod(ext, sel_registerName("setRecordingIndicatorManager:"), (IMP)X5_DelegateSetManager, "v24@0:8@16");
    class_addMethod(ws, sel_registerName("recordingIndicatorManager"), (IMP)X5_SceneManager, "@16@0:8");
    gX5OrigConfigure = BPX_Replace(ext, kCfg, (IMP)X5_Configure);
    gX5OrigForMain = BPX_Replace(sb, kMain, (IMP)X5_ForMainDisplay);
    gX5OrigStatusBarCfg = BPX_Replace(vc, kSB, (IMP)X5_StatusBarCfg);
    BP_Log(@"[x5] per display recording indicator installed (switch recindicator)");
}
#pragma clang diagnostic pop
