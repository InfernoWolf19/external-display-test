// X2Overlay.x : gap G2 / audit row T1 "overlays on the embedded display" (specs/GAPS-IMPLEMENTED-0.7.9.md section G2).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).  Switches: embedoverlay (everything below), embedoverlay_envmode (the per display switcher mode read of 5).  Setup: X2_Setup().
// Log prefix "[x2]" (Backport162.debug only).
//
// 16.2 mechanism (all read from the 16.2 cache; the 16.0 consumers already exist, what is missing in 16.0 is the answer of the view controllers and three consumer details):
//  1. -[SBTransientOverlayViewController prefersEmbeddedDisplayPresentation] (16.0 0x1c64d32e8 / 16.2 0x1c798ea64) reads the ivar _prefersEmbeddedDisplayPresentation (always NO for the
//     local overlays).  16.0 only SBPowerDownViewController overrides it (YES, 0x1c5ed0e28).  16.2 adds overrides in exactly these classes (every class of the 16.2 cache with its own getter,
//     grep of the class dump + disassembly of each):
//        SBPowerDownViewController                          0x1c7344e94  mov w0,#1                                  (already in 16.0)
//        SBControlCenterModuleTransientOverlayViewController 0x1c7567e88  mov w0,#1
//        SBInCallTransientOverlayViewController             0x1c75da010  mov w0,#1
//        SBPasscodeEntryTransientOverlayViewController      0x1c76fb2c4  mov w0,#1
//        SBVoiceControlTransientOverlayViewController       0x1c7841a2c  mov w0,#1
//        SBSpotlightTransientOverlayViewController          0x1c76bb71c  presentationSource == 1 || presentationSource == 7   (NOT a constant: ivar _presentationSource 0x540;
//            the sources written in 16.2: 1 by the interactive gesture (SpringBoard beginInteractiveSpotlight... block_invoke_3 0x1c7352f30), 5 / 6 by -toggleSearchFromBreadcrumbSource:... (0x1c7352218:
//            5 from the breadcrumb, 6 otherwise, i.e. the keyboard shortcut), 7 is never written by SpringBoard itself.  So the Cmd-Space shortcut presents Spotlight on the ACTIVE display, the
//            pull-down gesture and source 7 on the iPad; the audit's "Cmd-Space always opens on the iPad" was wrong for Spotlight)
//  2. Consumers of the property.  16.0 has (a) -[SBMainWorkspace presentTransientOverlayViewController:animated:completion:] 0x1c5f0d924 (YES -> [mainWindowScene _fbsDisplayConfiguration], NO ->
//     [transientOverlayPresentationManager defaultDisplayConfigurationForTransientOverlayPresentation] = the ACTIVE display's configuration) and its builder block (0x1c5f0dc64: windowScene of the context),
//     (b) the activate block of SBRemoteTransientOverlaySession (0x1c63c0c00 / 0x1c63c0c88; 16.2 0x1c786b3c0 / 0x1c786b534 is the same logic plus log lines).  16.2 adds:
//     a. -[SpringBoard beginInteractiveSpotlightTransientOverlayPresentationWithValidator:beginHandler:] 0x1c7352bf8 (16.0 0x1c5edeaa8): the request is made with
//        requestTransitionWithOptions:displayConfiguration:builder:validator: and the configuration chosen by the spotlight view controller's answer (16.2 0x1c7352cb4); 16.0 used
//        requestTransitionWithOptions:builder:validator: (no configuration = the main workspace default).
//     b. NEW -[SBMainWorkspaceTransitionRequest modifyTransientOverlayContext:] 0x1c7893a84 (16.0: only SBWorkspaceTransitionRequest 0x1c5f42304, which 16.2 left unchanged 0x1c73b6920):
//        super, then context = transientOverlayContext; vc = context.transientOverlay.viewController; if context.transitionType == 0 (present) and vc.prefersEmbeddedDisplayPresentation:
//        context.windowScene = [request.workspace mainWindowScene].  16.0 did this only in the builder block of presentTransientOverlayViewController (above); 16.2 moved it into the request, so
//        every user of modifyTransientOverlayContext: gets it: SBSpotlightTransientOverlayInteractiveGestureTransaction _presentTransientOverlayViewController: (0x1c7426958) and
//        SBInCallPresentationSession (blocks 0x1c757ba7c / 0x1c757c620, _configureTransitionRequest:forPresentingTransientOverlay:animated: 0x1c7580ff4), the paths that 16.0 never sent to the iPad.
//     c. -[SBMainWorkspace _executeTransientOverlayTransitionRequest:] 0x1c7375028 (16.0 0x1c5f00d54): when the context preserves the app switcher, the switcher's unlocked environment mode that
//        decides whether requestedUnlockedEnvironmentMode is set to 2 is read from the switcher controller of the REQUEST's display
//        ([[windowSceneManager windowSceneForDisplayIdentity:request.displayIdentity] switcherController] unlockedEnvironmentMode, "expected a switcherController!" NSLog when there is none;
//        nil -> 0), 16.0 read [SBMainSwitcherControllerCoordinator sharedInstance unlockedEnvironmentMode] = the ACTIVE display's switcher (0x1c623a020 -> _activeDisplaySwitcherController).  Matters
//        exactly for an overlay that is forced onto the iPad while the monitor is active.
//     Other differences of the same functions that are NOT display related and stay 16.0: -toggleSearchFromBreadcrumbSource:... (419 -> 403 insns) looks the lock screen's switcher controller up
//     per window scene only to log "expected a switcherController!".
//
// Port: 1 = class_replaceMethod of the five getters (Spotlight with the 16.2 formula; the original IMP answers when the switch is off); 2a = a hook of the SpringBoard method that arms a one-shot
// redirect inside SBMainWorkspace -requestTransitionWithOptions:builder:validator: to the 4-argument method with the 16.2 configuration; 2b = the new override (super IMP = the inherited one);
// 2c = a one-shot override of -[SBMainSwitcherControllerCoordinator unlockedEnvironmentMode] armed by a hook of _executeTransientOverlayTransitionRequest: only when
// context.shouldPreserveAppSwitcher (the only call that sync code makes before the value is used).  Nothing is guessed: no fallback to another display is added; a missing class or selector is
// logged and that piece is skipped.
// Needs a device: with the pointer on the monitor open Control Centre (module overlay), unlock (passcode), call (in-call overlay), voice control, the Spotlight pull-down: all on the iPad;
// Cmd-Space: on the monitor.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define X2_ON() BP_OnName("embedoverlay")

// ---------------------------------------------------------------------------------------------- 1: the getters

static IMP gX2OrigCC, gX2OrigInCall, gX2OrigPasscode, gX2OrigVoice, gX2OrigSpot;

static inline BOOL X2_CallOrig(IMP o, id self, SEL c) { return o ? ((BOOL (*)(id, SEL))o)(self, c) : NO; }

static BOOL X2_CC(id self, SEL _cmd)       { return X2_ON() ? YES : X2_CallOrig(gX2OrigCC, self, _cmd); }
static BOOL X2_InCall(id self, SEL _cmd)   { return X2_ON() ? YES : X2_CallOrig(gX2OrigInCall, self, _cmd); }
static BOOL X2_Passcode(id self, SEL _cmd) { return X2_ON() ? YES : X2_CallOrig(gX2OrigPasscode, self, _cmd); }
static BOOL X2_Voice(id self, SEL _cmd)    { return X2_ON() ? YES : X2_CallOrig(gX2OrigVoice, self, _cmd); }
// 16.2 0x1c76bb71c: presentationSource == 1 || presentationSource == 7
static BOOL X2_Spotlight(id self, SEL _cmd) {
    if (!X2_ON()) return X2_CallOrig(gX2OrigSpot, self, _cmd);
    SEL ps = sel_registerName("presentationSource");
    unsigned long long src = [self respondsToSelector:ps] ? ((unsigned long long (*)(id, SEL))objc_msgSend)(self, ps) : 0;
    return src == 1 || src == 7;
}

static BOOL X2_Prefers(id vc) {
    SEL s = sel_registerName("prefersEmbeddedDisplayPresentation");
    return (vc && [vc respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(vc, s) : NO;
}

static void X2_InstallGetter(const char *clsName, IMP imp, IMP *orig) {
    Class c = NSClassFromString([NSString stringWithUTF8String:clsName]);
    if (!c) { BP_Log(@"[x2] class %s not found, getter not installed", clsName); return; }
    IMP o = BPX_Replace(c, "prefersEmbeddedDisplayPresentation", imp);
    if (!o) { BP_Log(@"[x2] %s has no prefersEmbeddedDisplayPresentation, not installed", clsName); return; }
    *orig = o;
    BP_Log(@"[x2] %s prefersEmbeddedDisplayPresentation installed", clsName);
}

// ---------------------------------------------------------------------------------------------- 2b: modifyTransientOverlayContext: on SBMainWorkspaceTransitionRequest (16.2 0x1c7893a84)

static IMP gX2OrigModify;
static void X2_ModifyContext(id self, SEL _cmd, id block) {
    if (gX2OrigModify) ((void (*)(id, SEL, id))gX2OrigModify)(self, _cmd, block);          // [super modifyTransientOverlayContext:block]
    if (!X2_ON()) return;
    id ctx = BPX_Obj0(self, "transientOverlayContext");
    if (!ctx) return;
    id vc = BPX_Obj0(BPX_Obj0(ctx, "transientOverlay"), "viewController");
    if (BPX_LL0(ctx, "transitionType") != 0) return;                                          // 0 = present
    if (!X2_Prefers(vc)) return;
    id scene = BPX_Obj0(BPX_Obj0(self, "workspace"), "mainWindowScene");
    BPX_SetObj1(ctx, "setWindowScene:", scene);
    BPX_LOG(@"[x2] modifyTransientOverlayContext: %@ prefers the embedded display: context.windowScene = %@", NSStringFromClass(object_getClass(vc)), scene);
}

// ---------------------------------------------------------------------------------------------- 2a: interactive Spotlight request with the 16.2 display configuration

static __thread void *gX2InBegin;           // the SpringBoard (unretained) while its beginInteractiveSpotlight... runs on this thread: armed one-shot redirect
static IMP gX2OrigBegin;
static void X2_Begin(id self, SEL _cmd, id validator, id handler) {
    void *prev = gX2InBegin;
    gX2InBegin = (__bridge void *)self;
    if (gX2OrigBegin) ((void (*)(id, SEL, id, id))gX2OrigBegin)(self, _cmd, validator, handler);
    gX2InBegin = prev;
}

static IMP gX2OrigRequest3;
static BOOL X2_Request3(id self, SEL _cmd, unsigned long long options, id builder, id validator) {
    void *app = gX2InBegin;
    if (app && X2_ON()) {
        gX2InBegin = NULL;                                                                    // one-shot: the request of the interactive Spotlight presentation
        id sb = (__bridge id)app;
        Ivar iv = class_getInstanceVariable(object_getClass(sb), "_spotlightTransientOverlayViewController");
        id vc = BP_ObjIvar(sb, iv);
        id config = nil;
        BOOL prefers = X2_Prefers(vc);
        if (prefers) {
            config = BPX_Obj0(BPX_Obj0(self, "mainWindowScene"), "_fbsDisplayConfiguration");                              // 16.2 0x1c7352cc0
        } else {
            config = BPX_Obj0(BPX_Obj0(self, "transientOverlayPresentationManager"), "defaultDisplayConfigurationForTransientOverlayPresentation");   // 0x1c7352cdc
        }
        SEL s4 = sel_registerName("requestTransitionWithOptions:displayConfiguration:builder:validator:");
        if ([self respondsToSelector:s4]) {
            BPX_LOG(@"[x2] interactive Spotlight request: spotlight vc %@ prefers embedded = %d, display configuration %@", vc, (int)prefers, config);
            return ((BOOL (*)(id, SEL, unsigned long long, id, id, id))objc_msgSend)(self, s4, options, config, builder, validator);
        }
        BP_Log(@"[x2] requestTransitionWithOptions:displayConfiguration:builder:validator: missing, interactive Spotlight request left as 16.0 made it");
    }
    return gX2OrigRequest3 ? ((BOOL (*)(id, SEL, unsigned long long, id, id))gX2OrigRequest3)(self, _cmd, options, builder, validator) : NO;
}

// ---------------------------------------------------------------------------------------------- 2c: per display switcher mode in _executeTransientOverlayTransitionRequest:

static __thread void *gX2ExecRequest;       // armed (unretained request) between the shouldPreserveAppSwitcher test and the first unlockedEnvironmentMode read
static IMP gX2OrigExec;
static BOOL X2_Exec(id self, SEL _cmd, id request) {
    void *prev = gX2ExecRequest;
    gX2ExecRequest = NULL;
    if (request && BP_OnName("embedoverlay_envmode") && X2_ON()) {
        id ctx = BPX_Obj0(request, "transientOverlayContext");
        if (BPX_Bool0(ctx, "shouldPreserveAppSwitcher")) gX2ExecRequest = (__bridge void *)request;
    }
    BOOL r = gX2OrigExec ? ((BOOL (*)(id, SEL, id))gX2OrigExec)(self, _cmd, request) : NO;
    gX2ExecRequest = prev;
    return r;
}

static IMP gX2OrigEnvMode;
static long long X2_EnvMode(id self, SEL _cmd) {
    void *rq = gX2ExecRequest;
    if (rq) {
        gX2ExecRequest = NULL;                                                                // one-shot
        id request = (__bridge id)rq;
        id scene = BPX_Obj1(BPX_WindowSceneManager(), "windowSceneForDisplayIdentity:", BPX_Obj0(request, "displayIdentity"));
        id switcher = BPX_Obj0(scene, "switcherController");
        if (!switcher) {
            NSLog(@"expected a switcherController!");                                          // the 16.2 message (0x1c7375128)
            BP_Log(@"[x2] no switcher controller for display %@ of the transient overlay request: mode 0 as 16.2", BPX_Obj0(request, "displayIdentity"));
            return 0;
        }
        long long m = BPX_LL0(switcher, "unlockedEnvironmentMode");
        BPX_LOG(@"[x2] transient overlay request preserves the app switcher: unlocked environment mode of its own display = %lld", m);
        return m;
    }
    return gX2OrigEnvMode ? ((long long (*)(id, SEL))gX2OrigEnvMode)(self, _cmd) : 0;
}

// ---------------------------------------------------------------------------------------------- setup

void X2_Setup(void) {
    X2_InstallGetter("SBControlCenterModuleTransientOverlayViewController", (IMP)X2_CC, &gX2OrigCC);
    X2_InstallGetter("SBInCallTransientOverlayViewController", (IMP)X2_InCall, &gX2OrigInCall);
    X2_InstallGetter("SBPasscodeEntryTransientOverlayViewController", (IMP)X2_Passcode, &gX2OrigPasscode);
    X2_InstallGetter("SBVoiceControlTransientOverlayViewController", (IMP)X2_Voice, &gX2OrigVoice);
    X2_InstallGetter("SBSpotlightTransientOverlayViewController", (IMP)X2_Spotlight, &gX2OrigSpot);

    Class req = NSClassFromString(@"SBMainWorkspaceTransitionRequest");
    gX2OrigModify = req ? BPX_Replace(req, "modifyTransientOverlayContext:", (IMP)X2_ModifyContext) : NULL;
    BP_Log(@"[x2] SBMainWorkspaceTransitionRequest modifyTransientOverlayContext: %s", gX2OrigModify ? "installed" : "NOT installed (class or super method missing)");

    Class sb = NSClassFromString(@"SpringBoard");
    Class mw = NSClassFromString(@"SBMainWorkspace");
    const char *kBegin = "beginInteractiveSpotlightTransientOverlayPresentationWithValidator:beginHandler:", *kReq3 = "requestTransitionWithOptions:builder:validator:";
    BOOL haveBegin = sb && mw && class_getInstanceMethod(sb, sel_registerName(kBegin)) && class_getInstanceMethod(mw, sel_registerName(kReq3))
                  && class_getInstanceMethod(mw, sel_registerName("requestTransitionWithOptions:displayConfiguration:builder:validator:"));
    if (haveBegin) {
        gX2OrigBegin = BPX_Replace(sb, kBegin, (IMP)X2_Begin);
        gX2OrigRequest3 = BPX_Replace(mw, kReq3, (IMP)X2_Request3);
    }
    BP_Log(@"[x2] interactive Spotlight display configuration: %s", haveBegin ? "installed" : "NOT installed (class or selector missing)");

    const char *kExec = "_executeTransientOverlayTransitionRequest:";
    Class coord = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
    BOOL haveExec = mw && coord && class_getInstanceMethod(mw, sel_registerName(kExec)) && class_getInstanceMethod(coord, sel_registerName("unlockedEnvironmentMode"));
    if (haveExec) {
        gX2OrigExec = BPX_Replace(mw, kExec, (IMP)X2_Exec);
        gX2OrigEnvMode = BPX_Replace(coord, "unlockedEnvironmentMode", (IMP)X2_EnvMode);
    }
    BP_Log(@"[x2] per display switcher mode for transient overlay requests: %s", haveExec ? "installed" : "NOT installed (class or selector missing)");
}
#pragma clang diagnostic pop
