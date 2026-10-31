// Y25Workspace.x : delta sweep pass 3, workspace / button / gesture manager rows (F1, F3, F4).  Setup: constructor.  Log prefix "[y25]".
//
//  y24_homebutton   -[SBHomeHardwareButton _acceleratedSinglePressRecognizerShouldBegin]  16.2 0x1c730c620 (16.0 0x1c5e99958).  The only behavioural difference of the two bodies (the rest are log
//                   arguments): the "unlocked environment mode == 2 (Switcher)" test.  16.0 reads +[SBMainSwitcherControllerCoordinator sharedInstance] unlockedEnvironmentMode, which answers the mode
//                   of the coordinator's ACTIVE display controller (16.0 0x1c623a020 -> _activeDisplaySwitcherController); 16.2 reads [[[SBWorkspace mainWorkspace] mainWindowScene] switcherController]
//                   unlockedEnvironmentMode, the iPad's own switcher.  Ported: the 16.0 body runs with the main window scene's controller as the coordinator's active one (Y3_PushActive); this is the
//                   body's only coordinator read.  (Reached through AssistiveTouch Home: the M2 iPad Pro has no home button.)
//                   SBHomeHardwareButtonActions -performSinglePressUpActionsWithSourceType: is NOT ported on purpose: 16.2 0x1c75c8670 replaces the coordinator read by
//                   +[SBMainSwitcherControllerCoordinator _shim_activeSwitcherController] (16.2 0x1c76c7bd4 = [[coordinator sharedInstanceIfExists] _activeDisplaySwitcherController]), the active display
//                   controller again, i.e. the same value as the 16.0 read (EQUIVALENT).
//  y24_retainssiri  -[SBMainWorkspaceTransitionRequest copyMainWorkspaceTransitionRequest]  16.2 0x1c7892f40 (16.0 0x1c63e6878): the copy's application context also gets retainsSiri of the original's
//                   (16.0 SBWorkspaceApplicationSceneTransitionContext has the property: ivar _retainsSiri +0x1, accessors present).
//  y24_suspendedctx -[SBSuspendedWorkspaceTransaction _childTransactionDidComplete:]  16.2 0x1c7313a68 (16.0 0x1c5ea0d90, one 108 / 105 instruction body with the former blocks inlined).  16.0 builds the
//                   scene transition context (_createApplicationSceneTransitionContextFromContext:entity:, with the animation fence assertion) only when [[request displayIdentity] isMainDisplay]; for any
//                   other display the context stays nil, so the scene update of a suspended launch goes without transition context and the actions of a scene-less launch (open URL ...) are lost.  16.2
//                   (0x1c7313b44..b84) builds it for every display.  Ported without copying the inlined body: the request's displayIdentity answers the MAIN identity exactly once, for the one call the 16.0
//                   body makes before it creates the context (0x1c5ea0e90), while the request names another display; the override is thread local, armed around the call only and consumed by the first
//                   displayIdentity read of that request.  16.0 reads the identity nowhere else in the body (checked: the single isMainDisplay at 0x1c5ea0e9c).
//  y24_gmbanner     SBFluidSwitcherGestureManager and the In-Call banner (scene backed banners)  -initWithSwitcherController:delegate: 16.2 0x1c78efafc, -invalidate 0x1c78f16c0, new
//                   -bannerManager:willPresentPresentable:withTransitionCoordinator: 0x1c78fb590 / -bannerManager:willDismissPresentable:withTransitionCoordinator: 0x1c78fb6a4, reader
//                   -_shouldTapToBringItemContainerForward:receiveTouch: 0x1c78f5ac0 (G1D.x ports its 16.0 part; the extra rule is applied around it here).  The gesture manager registers as transition observer of
//                   [SBApp bannerManager] (when Stage Manager is available), collects the presentables of its own window scene that have a `scene` (the In-Call banner) in a weak table and clears the table
//                   when the last one is dismissed; while the table is not empty "tap to bring an item container forward" is refused.  The observer protocol SBBannerManagerTransitionObserver, the banner
//                   manager's addTransitionObserver: / removeTransitionObserver: / windowSceneForPresentable: exist in 16.0 (sb160 listing; SBPIPPegasusAdapter and others observe the same callbacks), the table
//                   is an associated object (16.0 has no ivar for it, 16.2 +0xd0).
// Needs a device: receive a call banner while a Stage Manager window is behind it, tap a background window: no bring-forward while the banner shows; (suspendedctx) background-launch an app onto the
// monitor via an Open URL / Shortcuts action: the URL arrives; (homebutton) AssistiveTouch Home with the monitor active and the iPad in the app switcher.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY25OrigBtn, gY25OrigCopy, gY25OrigChild, gY25OrigIdent, gY25OrigInit, gY25OrigInval, gY25OrigTap;

static id Y25_MainSceneController(const char *tag) {
    id ws = BPX_MainWorkspace();
    id scene = Y17_Obj0(tag, ws, "mainWindowScene");
    return Y17_Obj0(tag, scene, "switcherController");
}

// ---- y24_homebutton ----
static BOOL Y25_BtnBegin(id self, SEL _cmd) {
    if (!BP_OnName("y24_homebutton")) return gY25OrigBtn ? ((BOOL (*)(id, SEL))gY25OrigBtn)(self, _cmd) : NO;
    id ctl = Y25_MainSceneController("homebutton");
    void *prev = Y3_PushActive(ctl);
    BOOL r = gY25OrigBtn ? ((BOOL (*)(id, SEL))gY25OrigBtn)(self, _cmd) : NO;
    Y3_PopActive(prev);
    BPY_LOG(@"[y25] accelerated home press: environment mode read from the main display controller %p -> begin %d", (__bridge void *)ctl, (int)r);
    return r;
}

// ---- y24_retainssiri ----
static __attribute__((ns_returns_retained)) id Y25_CopyRequest(id self, SEL _cmd) {
    id r = gY25OrigCopy ? ((__attribute__((ns_returns_retained)) id (*)(id, SEL))gY25OrigCopy)(self, _cmd) : nil;
    if (r && BP_OnName("y24_retainssiri")) {
        id src = Y17_Obj0("retainssiri", self, "applicationContext");
        id dst = Y17_Obj0("retainssiri", r, "applicationContext");
        if (src && dst && BPY_Responds(src, "retainsSiri") && BPY_Responds(dst, "setRetainsSiri:")) {
            BOOL v = BPY_SEND(BOOL, (), src, "retainsSiri");
            BPY_SEND(void, (BOOL), dst, "setRetainsSiri:", v);
        } else Y17_GuardOnce("retainssiri", src, "retainsSiri / setRetainsSiri:");
    }
    return r;
}

// ---- y24_suspendedctx ----
static __thread void *tY25Req;          // unretained: the request whose displayIdentity answers the main identity once
static __thread BOOL tY25Armed;
static id Y25_Identity(id self, SEL _cmd) {
    if (tY25Armed && tY25Req == (__bridge void *)self) {
        tY25Armed = NO;
        id main = Y17_Obj0("suspendedctx", Y17_Obj0("suspendedctx", BPX_MainWorkspace(), "mainWindowScene"), "_fbsDisplayIdentity");
        if (main) return main;
    }
    return gY25OrigIdent ? ((id (*)(id, SEL))gY25OrigIdent)(self, _cmd) : nil;
}
static void Y25_ChildDone(id self, SEL _cmd, id child) {
    if (!BP_OnName("y24_suspendedctx") || !gY25OrigIdent) {
        if (gY25OrigChild) ((void (*)(id, SEL, id))gY25OrigChild)(self, _cmd, child);
        return;
    }
    id req = Y17_Obj0("suspendedctx", self, "transitionRequest");
    id ident = req ? ((id (*)(id, SEL))gY25OrigIdent)(req, sel_registerName("displayIdentity")) : nil;
    BOOL arm = NO;
    if (ident && BPY_Responds(ident, "isMainDisplay") && !BPY_SEND(BOOL, (), ident, "isMainDisplay")) arm = YES;
    void *prevReq = tY25Req; BOOL prevArmed = tY25Armed;
    if (arm) { tY25Req = (__bridge void *)req; tY25Armed = YES; BPY_LOG(@"[y25] suspended launch of a non main display: the transition context is built (16.2)"); }
    if (gY25OrigChild) ((void (*)(id, SEL, id))gY25OrigChild)(self, _cmd, child);
    tY25Req = prevReq; tY25Armed = prevArmed;
}

// ---- y24_gmbanner ----
static char kY25Banners;
static BOOL Y25_ChamoisAvailable(void) {
    static BOOL (*fn)(void); static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFIsChamoisWindowingUIAvailable");
        if (!fn) fn = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFFeatureFlagsIsChamoisWindowingUIEnabled");
        if (!fn) BP_Log(@"[y25] GUARD(gmbanner) neither SBFIsChamoisWindowingUIAvailable nor SBFFeatureFlagsIsChamoisWindowingUIEnabled resolves: Stage Manager taken as available");
    });
    return fn ? fn() : YES;
}
static id Y25_GMWeak(id gm, const char *name) {
    Ivar iv = gm ? class_getInstanceVariable(object_getClass(gm), name) : NULL;
    return BP_ObjIvar(gm, iv);                 // a weak ivar holds the raw pointer
}
static NSHashTable *Y25_Banners(id gm) { return objc_getAssociatedObject(gm, &kY25Banners); }
static __attribute__((ns_returns_retained)) id Y25_InitGM(__attribute__((ns_consumed)) id self, SEL _cmd, id sc, id delegate) {
    id r = ((__attribute__((ns_returns_retained)) id (*)(__attribute__((ns_consumed)) id, SEL, id, id))gY25OrigInit)(self, _cmd, sc, delegate);
    if (r && BP_OnName("y24_gmbanner") && Y25_ChamoisAvailable()) {
        id bm = Y17_Obj0("gmbanner", BPX_App(), "bannerManager");
        if (bm && BPY_Responds(bm, "addTransitionObserver:")) BPY_SEND(void, (id), bm, "addTransitionObserver:", r);
        else Y17_GuardOnce("gmbanner", bm, "addTransitionObserver:");
    }
    return r;
}
static void Y25_InvalidateGM(id self, SEL _cmd) {
    if (gY25OrigInval) ((void (*)(id, SEL))gY25OrigInval)(self, _cmd);
    if (!BP_OnName("y24_gmbanner")) return;
    id bm = Y17_Obj0("gmbanner", BPX_App(), "bannerManager");
    if (bm && BPY_Responds(bm, "removeTransitionObserver:")) BPY_SEND(void, (id), bm, "removeTransitionObserver:", self);
    else Y17_GuardOnce("gmbanner", bm, "removeTransitionObserver:");
}
static void Y25_WillPresent(id self, SEL _cmd, id mgr, id presentable, id coordinator) {
    if (!BP_OnName("y24_gmbanner")) return;
    id bm = Y17_Obj0("gmbanner", BPX_App(), "bannerManager");
    id presenterScene = bm ? Y17_Obj1("gmbanner", bm, "windowSceneForPresentable:", presentable) : nil;
    id ownScene = Y17_Obj0("gmbanner", Y25_GMWeak(self, "_switcherController"), "windowScene");
    if (presenterScene && [presenterScene isEqual:ownScene] && [presentable respondsToSelector:sel_registerName("scene")]) {
        NSHashTable *t = Y25_Banners(self);
        if (!t) { t = [NSHashTable weakObjectsHashTable]; objc_setAssociatedObject(self, &kY25Banners, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        [t addObject:presentable];
        BPY_LOG(@"[y25] scene backed banner %@ presented on the gesture manager's scene (%lu)", presentable, (unsigned long)t.count);
    }
}
static void Y25_WillDismiss(id self, SEL _cmd, id mgr, id presentable, id coordinator) {
    if (!BP_OnName("y24_gmbanner")) return;
    NSHashTable *t = Y25_Banners(self);
    [t removeObject:presentable];
    if (t && t.count == 0) objc_setAssociatedObject(self, &kY25Banners, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL Y25_TapForward(id self, SEL _cmd, id gesture, id touch) {
    BOOL r = gY25OrigTap ? ((BOOL (*)(id, SEL, id, id))gY25OrigTap)(self, _cmd, gesture, touch) : NO;
    if (r && BP_OnName("y24_gmbanner") && Y25_Banners(self).count != 0) return NO;      // 16.2 0x1c78f5ccc: result &= (presented scene backed banners == 0)
    return r;
}

__attribute__((constructor)) static void Y25_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class hb = NSClassFromString(@"SBHomeHardwareButton");
        if (hb && class_getInstanceMethod(hb, sel_registerName("_acceleratedSinglePressRecognizerShouldBegin"))) {
            gY25OrigBtn = BPX_Replace(hb, "_acceleratedSinglePressRecognizerShouldBegin", (IMP)Y25_BtnBegin); n++;
        } else BP_Log(@"[y25] GUARD(homebutton) SBHomeHardwareButton _acceleratedSinglePressRecognizerShouldBegin missing: not installed");
        Class rq = NSClassFromString(@"SBMainWorkspaceTransitionRequest");
        if (rq && class_getInstanceMethod(rq, sel_registerName("copyMainWorkspaceTransitionRequest"))) {
            gY25OrigCopy = BPX_Replace(rq, "copyMainWorkspaceTransitionRequest", (IMP)Y25_CopyRequest); n++;
        } else BP_Log(@"[y25] GUARD(retainssiri) SBMainWorkspaceTransitionRequest copyMainWorkspaceTransitionRequest missing: not installed");
        Class base = NSClassFromString(@"SBWorkspaceTransitionRequest");
        Class st = NSClassFromString(@"SBSuspendedWorkspaceTransaction");
        if (base && st && class_getInstanceMethod(base, sel_registerName("displayIdentity")) && class_getInstanceMethod(st, sel_registerName("_childTransactionDidComplete:")) && class_getInstanceMethod(st, sel_registerName("transitionRequest"))) {
            gY25OrigIdent = BPX_Replace(base, "displayIdentity", (IMP)Y25_Identity);
            gY25OrigChild = BPX_Replace(st, "_childTransactionDidComplete:", (IMP)Y25_ChildDone); n++;
        } else BP_Log(@"[y25] GUARD(suspendedctx) SBWorkspaceTransitionRequest displayIdentity or SBSuspendedWorkspaceTransaction _childTransactionDidComplete: / transitionRequest missing: not installed");
        Class gm = NSClassFromString(@"SBFluidSwitcherGestureManager");
        Class bmc = NSClassFromString(@"SBBannerManager");
        if (gm && bmc && class_getInstanceMethod(bmc, sel_registerName("addTransitionObserver:")) && class_getInstanceMethod(bmc, sel_registerName("removeTransitionObserver:")) &&
            class_getInstanceMethod(bmc, sel_registerName("windowSceneForPresentable:")) && class_getInstanceMethod(gm, sel_registerName("initWithSwitcherController:delegate:")) &&
            class_getInstanceMethod(gm, sel_registerName("invalidate")) && class_getInstanceMethod(gm, sel_registerName("_shouldTapToBringItemContainerForward:receiveTouch:"))) {
            class_addMethod(gm, sel_registerName("bannerManager:willPresentPresentable:withTransitionCoordinator:"), (IMP)Y25_WillPresent, "v40@0:8@16@24@32");
            class_addMethod(gm, sel_registerName("bannerManager:willDismissPresentable:withTransitionCoordinator:"), (IMP)Y25_WillDismiss, "v40@0:8@16@24@32");
            gY25OrigInit = BPX_Replace(gm, "initWithSwitcherController:delegate:", (IMP)Y25_InitGM);
            gY25OrigInval = BPX_Replace(gm, "invalidate", (IMP)Y25_InvalidateGM);
            gY25OrigTap = BPX_Replace(gm, "_shouldTapToBringItemContainerForward:receiveTouch:", (IMP)Y25_TapForward); n++;
        } else BP_Log(@"[y25] GUARD(gmbanner) SBFluidSwitcherGestureManager / SBBannerManager selectors missing: not installed");
        BP_Log(@"[y25] installed %d group(s) (switches y24_homebutton, y24_retainssiri, y24_suspendedctx, y24_gmbanner)", n);
    }
}
#pragma clang diagnostic pop
