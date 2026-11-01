// Y37RemoteAlert.x : the remote alert presentation target PREDICATE of 16.2 (DELTA-SWEEP-0.7.9.md rows SpringBoard -remoteTransientOverlaySessionManager:shouldActivateOverlayWithContext:forSession: /
// -performPresentationRequest:forSession:, SBDeviceApplicationRemoteTransientOverlayViewProvider (3 rows), SBDeviceApplicationSceneViewController display mode callouts (3 rows); Pass 4).
// Setup: constructor.  Log prefix "[y37]".  Switch y37_alerttarget (default ON, kill file Backport162.off.y37_alerttarget).
//
// 16.2 SpringBoardServices (the library every client AND SpringBoard load, dyld cache):
//   SBSRemoteAlertPresentationTargetPredicate (new class, 16.2 0x191f0398c .. 0x191f0406c): ivars _scenePersistentIdentifier, _process (BSProcessHandle), _launchingApplicationIdentity (LSApplicationIdentity);
//     +predicateForProcess: / +predicateForLaunchingApplicationIdentity: (alloc + _init + setter), NSSecureCoding (+supportsSecureCoding), XPC (initWithXPCDictionary: 0x191f03a7c: key "process" (BSXPCEncodable)
//     else "launchingIdentity" (NSSecureCoding LSApplicationIdentity), then "scenePersistentIdentifier" (string); encodeWithXPCDictionary: 0x191f03b60 the same keys), NSXPCCoder coding (0x191f03bf8 / 0x191f03db0).
//   SBSRemoteAlertPresentationTarget: ivars _shouldDismissOnUILock, _shouldDismissInSwitcher (new), _requiresFullscreenPresentation, _targetPredicate (the 16.0 ivars _targetProcess / _scenePersistentIdentifier are gone):
//     -initWithTargetProcess: 0x191f032fc = initWithTargetPredicate:[Predicate predicateForProcess:process]; -initWithTargetPredicate: 0x191f03348; -targetProcess / -scenePersistentIdentifier /
//     -setScenePersistentIdentifier: forward to the predicate (0x191f037d8 / e0 / e8); XPC 0x191f03490 / 0x191f033c4: "targetPredicate" (BSXPCEncodable), "shouldDismissOnUILock", "shouldDismissInSwitcher",
//     "requiresFullscreenPresentation".
// SpringBoard 16.2: category SBSRemoteAlertPresentationTargetPredicate(SpringBoard) 0x1c7787d68 .. 0x1c7788054: -targetApplicationWithController: (process: applicationWithPid:; launching identity:
//   the application only while it is NOT running yet), -matchesOverlayViewController: (isPresentedByProcess: / isPresentedByBundleIdentifier:), -configureTransientOverlayContext: (setOriginatingProcess:),
//   -_launchingApplicationRecord; -[SBRemoteTransientOverlayViewController isPresentedByBundleIdentifier:] 0x1c7505584 (serviceBundleIdentifier isEqualToString:), SBTransientOverlayViewController NO 0x1c798d770;
//   -[SpringBoard remoteTransientOverlaySessionManager:shouldActivateOverlayWithContext:forSession:] 0x1c735a4b4 (16.0 0x1c5ee6488): the target application is resolved through the predicate;
//   -performPresentationRequest:forSession: 0x1c735acb8 (16.0 0x1c5ee6ca0): the embedded path (target scene) resolves the application through the predicate, so a launching-application predicate (no process) takes
//   it too (16.0 needed a process); SBDeviceApplicationRemoteTransientOverlayViewProvider: -initWithSceneHandle:delegate: 0x1c78b0d94 no longer registers with SpringBoard, -noteDisplayModeChange: 0x1c78b1624
//   registers (display mode 4 = live) / unregisters, -_handleAppSwitcherWillPresent: 0x1c78b1b88 dismisses only contexts whose target has shouldDismissInSwitcher; SBDeviceApplicationSceneViewController
//   tells its providers about display mode changes (setDisplayMode:animationFactory:completion: 0x1c75bb1f0, _createSceneOverlayViewProvidersIfNecessary 0x1c75bbb70, _configureForSecureDisplay: 0x1c75bd6b4).
//
// Port: the predicate class is created at run time in every process that loads the tweak (SpringBoard); the 16.0 target class keeps its ivars and the 16.2 accessors are layered on them: once a predicate
// exists (made by -targetPredicate from the 16.0 state, or handed in by -initWithTargetPredicate:) it is the single source of truth for process / scene identifier.  The XPC encoding keeps the 16.0 keys and
// adds the 16.2 keys; the decoding accepts both.  What a 16.0 CLIENT process can supply: only what its 16.0 SpringBoardServices encodes (process, scene id, two flags): a client never sends a predicate nor
// shouldDismissInSwitcher, so those are only reachable from SpringBoard's own code.  The only 16.2 producer of a launching-application predicate is PrivacyDisclosureCore's presenter (Y36Preflight.x), which
// shows a native alert here instead of a remote alert, so no launching predicate is created by anything on 16.0; the code for it is complete and used when something does.
//
// Needs a device: remote alerts (Siri, call UI, share sheet) still present in the app window; with several displays only the live scene's provider takes embedded requests (log "[y37] provider ... registered").

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static char kY37PProc, kY37PLaunch, kY37PScene;           // predicate state
static char kY37TPred, kY37TSwitcher;                      // target state
#define Y37_SET(o, k, v) objc_setAssociatedObject((o), &(k), (v), OBJC_ASSOCIATION_RETAIN_NONATOMIC)
#define Y37_GET(o, k)    objc_getAssociatedObject((o), &(k))
#define Y37_NEWRET __attribute__((ns_returns_retained))
#define Y37_CONSUMED __attribute__((ns_consumed))
#define Y37_INIT(...) ((Y37_NEWRET id (*)(Y37_CONSUMED id, SEL, __VA_ARGS__))objc_msgSend)
#define Y37_INIT0 ((Y37_NEWRET id (*)(Y37_CONSUMED id, SEL))objc_msgSend)
#define ADD(c, sel, imp, types) class_addMethod((c), sel_registerName(sel), (IMP)(imp), (types))

static Class gY37Pred;
static IMP gY37TInitXPC, gY37TEncXPC, gY37TProcess, gY37TScene, gY37TSetScene, gY37Should, gY37Perform, gY37PInit, gY37VCCreate, gY37VCSecure;

static BOOL Y37_On(void) { return BP_OnName("y37_alerttarget"); }
static BOOL Y37_B1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    if (!o) return NO;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-y37", o, s); return NO; }
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(o, s, a);
}

// ------------------------------------------------------------------------------------------------ BaseBoard XPC helpers (BSXPCCoding), resolved once
typedef id (*Y37DeserObj)(id xdict, const char *key);
typedef id (*Y37DeserSecure)(Class c, id xdict, const char *key);
typedef id (*Y37DeserStr)(id xdict, const char *key);
typedef void (*Y37SerObj)(id obj, id xdict, const char *key);
typedef void (*Y37SetBool)(id xdict, const char *key, bool v);
typedef bool (*Y37GetBool)(id xdict, const char *key);
static struct { Y37DeserObj deserObj; Y37DeserSecure deserSecure; Y37DeserStr deserStr; Y37SerObj serObj, serSecure, serStr; Y37SetBool setBool; Y37GetBool getBool; BOOL ok; } gY37X;
static BOOL Y37_XPC(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gY37X.deserObj = (Y37DeserObj)dlsym(RTLD_DEFAULT, "BSCreateDeserializedBSXPCEncodableObjectFromXPCDictionaryWithKey");
        gY37X.deserSecure = (Y37DeserSecure)dlsym(RTLD_DEFAULT, "BSCreateDeserializedNSSecureEncodableObjectOfClassFromXPCDictionaryWithKey");
        gY37X.deserStr = (Y37DeserStr)dlsym(RTLD_DEFAULT, "BSCreateDeserializedStringFromXPCDictionaryWithKey");
        gY37X.serObj = (Y37SerObj)dlsym(RTLD_DEFAULT, "BSSerializeBSXPCEncodableObjectToXPCDictionaryWithKey");
        gY37X.serSecure = (Y37SerObj)dlsym(RTLD_DEFAULT, "BSSerializeNSSecureEncodableObjectToXPCDictionaryWithKey");
        gY37X.serStr = (Y37SerObj)dlsym(RTLD_DEFAULT, "BSSerializeStringToXPCDictionaryWithKey");
        gY37X.setBool = (Y37SetBool)dlsym(RTLD_DEFAULT, "xpc_dictionary_set_bool");
        gY37X.getBool = (Y37GetBool)dlsym(RTLD_DEFAULT, "xpc_dictionary_get_bool");
        gY37X.ok = gY37X.deserObj && gY37X.deserSecure && gY37X.deserStr && gY37X.serObj && gY37X.serSecure && gY37X.serStr && gY37X.setBool && gY37X.getBool;
        if (!gY37X.ok) BP_Anomaly("y37-xpc", @"BaseBoard XPC coding helpers missing (deserObj %p deserSecure %p deserStr %p serObj %p serSecure %p serStr %p): predicate XPC coding is not available", gY37X.deserObj, gY37X.deserSecure, gY37X.deserStr, gY37X.serObj, gY37X.serSecure, gY37X.serStr);
    });
    return gY37X.ok;
}

// ------------------------------------------------------------------------------------------------ SBSRemoteAlertPresentationTargetPredicate
static Y37_NEWRET id Y37_PredInit(Y37_CONSUMED id self, SEL _cmd) {                                 // 0x191f0398c (_init)
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    return ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
}
static id Y37_PredForProcess(id cls, SEL _cmd, id process) {                                        // 0x191f039c4
    id p = Y37_INIT0([cls alloc], sel_registerName("_init"));
    Y37_SET(p, kY37PProc, process);
    return p;
}
static id Y37_PredForLaunching(id cls, SEL _cmd, id identity) {                                     // 0x191f03a20
    id p = Y37_INIT0([cls alloc], sel_registerName("_init"));
    Y37_SET(p, kY37PLaunch, identity);
    return p;
}
static id Y37_PredProcess(id self, SEL _cmd) { return Y37_GET(self, kY37PProc); }
static void Y37_PredSetProcess(id self, SEL _cmd, id v) { Y37_SET(self, kY37PProc, v); }
static id Y37_PredLaunch(id self, SEL _cmd) { return Y37_GET(self, kY37PLaunch); }
static void Y37_PredSetLaunch(id self, SEL _cmd, id v) { Y37_SET(self, kY37PLaunch, v); }
static id Y37_PredScene(id self, SEL _cmd) { return Y37_GET(self, kY37PScene); }
static void Y37_PredSetScene(id self, SEL _cmd, NSString *v) { objc_setAssociatedObject(self, &kY37PScene, v, OBJC_ASSOCIATION_COPY_NONATOMIC); }
static BOOL Y37_Yes(id cls, SEL _cmd) { return YES; }
static Y37_NEWRET id Y37_PredInitXPC(Y37_CONSUMED id self, SEL _cmd, id xdict) {                    // 0x191f03a7c
    if (!Y37_XPC()) return nil;
    id proc = gY37X.deserObj(xdict, "process");
    id ident = gY37X.deserSecure(NSClassFromString(@"LSApplicationIdentity"), xdict, "launchingIdentity");
    id pred = nil;
    Class cls = object_getClass(self);
    if (proc) pred = ((id (*)(id, SEL, id))objc_msgSend)((id)cls, sel_registerName("predicateForProcess:"), proc);
    else if (ident) pred = ((id (*)(id, SEL, id))objc_msgSend)((id)cls, sel_registerName("predicateForLaunchingApplicationIdentity:"), ident);
    if (pred) objc_setAssociatedObject(pred, &kY37PScene, gY37X.deserStr(xdict, "scenePersistentIdentifier"), OBJC_ASSOCIATION_COPY_NONATOMIC);
    return pred;
}
static void Y37_PredEncXPC(id self, SEL _cmd, id xdict) {                                           // 0x191f03b60
    if (!Y37_XPC()) return;
    id proc = Y37_GET(self, kY37PProc), ident = Y37_GET(self, kY37PLaunch);
    if (proc) gY37X.serObj(proc, xdict, "process");
    else if (ident) gY37X.serSecure(ident, xdict, "launchingIdentity");
    gY37X.serStr(Y37_GET(self, kY37PScene), xdict, "scenePersistentIdentifier");
}
// NSXPCCoder coding 0x191f03bf8 / 0x191f03db0: the same keys; only an NSXPCCoder can carry a BSProcessHandle
static Y37_NEWRET id Y37_PredInitCoder(Y37_CONSUMED id self, SEL _cmd, id coder) {
    Class cls = object_getClass(self);
    id pred = nil;
    SEL has = sel_registerName("containsValueForKey:"), dec = sel_registerName("decodeObjectOfClass:forKey:");
    if (((BOOL (*)(id, SEL, id))objc_msgSend)(coder, has, @"process")) {
        id proc = ((id (*)(id, SEL, Class, id))objc_msgSend)(coder, dec, NSClassFromString(@"BSProcessHandle"), @"process");
        pred = ((id (*)(id, SEL, id))objc_msgSend)((id)cls, sel_registerName("predicateForProcess:"), proc);
    } else if (((BOOL (*)(id, SEL, id))objc_msgSend)(coder, has, @"launchingIdentity")) {
        id ident = ((id (*)(id, SEL, Class, id))objc_msgSend)(coder, dec, NSClassFromString(@"LSApplicationIdentity"), @"launchingIdentity");
        pred = ((id (*)(id, SEL, id))objc_msgSend)((id)cls, sel_registerName("predicateForLaunchingApplicationIdentity:"), ident);
    }
    if (pred) objc_setAssociatedObject(pred, &kY37PScene, ((id (*)(id, SEL, Class, id))objc_msgSend)(coder, dec, [NSString class], @"scenePersistentIdentifier"), OBJC_ASSOCIATION_COPY_NONATOMIC);
    return pred;
}
static void Y37_PredEncCoder(id self, SEL _cmd, id coder) {
    SEL enc = sel_registerName("encodeObject:forKey:");
    id proc = Y37_GET(self, kY37PProc), ident = Y37_GET(self, kY37PLaunch);
    if (proc) ((void (*)(id, SEL, id, id))objc_msgSend)(coder, enc, proc, @"process");
    else if (ident) ((void (*)(id, SEL, id, id))objc_msgSend)(coder, enc, ident, @"launchingIdentity");
    ((void (*)(id, SEL, id, id))objc_msgSend)(coder, enc, Y37_GET(self, kY37PScene), @"scenePersistentIdentifier");
}
static id Y37_PredDesc(id self, SEL _cmd) {
    return [NSString stringWithFormat:@"<SBSRemoteAlertPresentationTargetPredicate: %p process: %@ launchingApplicationIdentity: %@ scenePersistentIdentifier: %@>", self, Y37_GET(self, kY37PProc), Y37_GET(self, kY37PLaunch), Y37_GET(self, kY37PScene)];
}

// ---- SpringBoard category (0x1c7787d68 ..)
static id Y37_LaunchRecord(id self, SEL _cmd) {                                                      // 0x1c7787fb4
    id ident = Y37_GET(self, kY37PLaunch);
    SEL s = sel_registerName("findApplicationRecordWithError:");
    if (!ident || ![ident respondsToSelector:s]) { Y17_GuardOnce("y37", ident, "findApplicationRecordWithError:"); return nil; }
    NSError *err = nil;
    id rec = ((id (*)(id, SEL, NSError **))objc_msgSend)(ident, s, &err);
    if (err) BP_Anomaly("y37-record", @"launching application record of %@ not found: %@", ident, err);
    return rec;
}
static id Y37_TargetApp(id self, SEL _cmd, id controller) {                                          // 0x1c7787d68
    id proc = Y37_GET(self, kY37PProc), ident = Y37_GET(self, kY37PLaunch);
    if (proc) return ((id (*)(id, SEL, int))objc_msgSend)(controller, sel_registerName("applicationWithPid:"), (int)BPX_LL0(proc, "pid"));
    if (!ident) return nil;
    NSString *bid = BPX_Obj0(((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("_launchingApplicationRecord")), "bundleIdentifier");
    id app = BPX_Obj1(controller, "applicationWithBundleIdentifier:", bid);
    return BPX_Bool0(BPX_Obj0(app, "processState"), "isRunning") ? nil : app;                       // a launching application identity matches only an application that is not running yet
}
static BOOL Y37_MatchesVC(id self, SEL _cmd, id vc) {                                                // 0x1c7787e8c
    id proc = Y37_GET(self, kY37PProc), ident = Y37_GET(self, kY37PLaunch);
    if (proc) return Y37_B1(vc, "isPresentedByProcess:", proc);
    if (!ident) return NO;
    NSString *bid = BPX_Obj0(((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("_launchingApplicationRecord")), "bundleIdentifier");
    return Y37_B1(vc, "isPresentedByBundleIdentifier:", bid);
}
static void Y37_ConfigureContext(id self, SEL _cmd, id ctx) {                                        // 0x1c7787f4c
    id proc = Y37_GET(self, kY37PProc);
    if (proc) BPX_SetObj1(ctx, "setOriginatingProcess:", proc);
}
static BOOL Y37_VCPresentedByBundle(id self, SEL _cmd, NSString *bid) {                              // 0x1c7505584
    id host = BPX_IvarObj(self, "_contentViewController");
    return [BPX_Obj0(host, "serviceBundleIdentifier") isEqualToString:bid];
}
static BOOL Y37_VCPresentedByBundleBase(id self, SEL _cmd, NSString *bid) { return NO; }            // 0x1c798d770

// ------------------------------------------------------------------------------------------------ SBSRemoteAlertPresentationTarget (16.0 class + 16.2 accessors)
static id Y37_TPredicate(id self, SEL _cmd) {                                                         // -targetPredicate: single source of truth once it exists
    id p = Y37_GET(self, kY37TPred);
    if (!p && gY37Pred) {
        id proc = BPX_IvarObj(self, "_targetProcess");
        p = ((id (*)(id, SEL, id))objc_msgSend)((id)gY37Pred, sel_registerName("predicateForProcess:"), proc);
        objc_setAssociatedObject(p, &kY37PScene, BPX_IvarObj(self, "_scenePersistentIdentifier"), OBJC_ASSOCIATION_COPY_NONATOMIC);
        Y37_SET(self, kY37TPred, p);
    }
    return p;
}
static Y37_NEWRET id Y37_TInitPredicate(Y37_CONSUMED id self, SEL _cmd, id predicate) {              // 0x191f03348
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        Y37_SET(me, kY37TPred, predicate);
        Ivar ip = BP_IvarLookup(object_getClass(me), "_targetProcess"), is = BP_IvarLookup(object_getClass(me), "_scenePersistentIdentifier");
        BP_SetObjIvar(me, ip, BPX_Obj0(predicate, "process"));                                         // keep the 16.0 ivars readable for the 16.0 code that reads them directly
        BP_SetObjIvar(me, is, BPX_Obj0(predicate, "scenePersistentIdentifier"));
    }
    return me;
}
static id Y37_TProcess(id self, SEL _cmd) {                                                           // 0x191f037d8
    id p = Y37_GET(self, kY37TPred);
    return p ? BPX_Obj0(p, "process") : (gY37TProcess ? ((id (*)(id, SEL))gY37TProcess)(self, _cmd) : nil);
}
static id Y37_TScene(id self, SEL _cmd) {                                                             // 0x191f037e0
    id p = Y37_GET(self, kY37TPred);
    return p ? BPX_Obj0(p, "scenePersistentIdentifier") : (gY37TScene ? ((id (*)(id, SEL))gY37TScene)(self, _cmd) : nil);
}
static void Y37_TSetScene(id self, SEL _cmd, id v) {                                                  // 0x191f037e8
    id p = Y37_GET(self, kY37TPred);
    if (p) BPX_SetObj1(p, "setScenePersistentIdentifier:", v);
    if (gY37TSetScene) ((void (*)(id, SEL, id))gY37TSetScene)(self, _cmd, v);
}
static BOOL Y37_TDismissSwitcher(id self, SEL _cmd) { return [Y37_GET(self, kY37TSwitcher) boolValue]; }
static void Y37_TSetDismissSwitcher(id self, SEL _cmd, BOOL v) { Y37_SET(self, kY37TSwitcher, @(v)); }
static Y37_NEWRET id Y37_TInitXPC(Y37_CONSUMED id self, SEL _cmd, id xdict) {                         // 0x191f033c4 (16.2 format); 16.0 format falls through to the 16.0 decoder
    if (Y37_On() && Y37_XPC()) {
        id pred = gY37X.deserObj(xdict, "targetPredicate");
        if (pred) {
            id me = Y37_INIT(id)(self, sel_registerName("initWithTargetPredicate:"), pred);
            if (!me) return nil;
            BPX_SetBool1(me, "setShouldDismissOnUILock:", gY37X.getBool(xdict, "shouldDismissOnUILock"));
            BPX_SetBool1(me, "setShouldDismissInSwitcher:", gY37X.getBool(xdict, "shouldDismissInSwitcher"));
            BPX_SetBool1(me, "setRequiresFullscreenPresentation:", gY37X.getBool(xdict, "requiresFullscreenPresentation"));
            return me;
        }
    }
    return gY37TInitXPC ? ((Y37_NEWRET id (*)(Y37_CONSUMED id, SEL, id))gY37TInitXPC)(self, _cmd, xdict) : nil;
}
static void Y37_TEncXPC(id self, SEL _cmd, id xdict) {                                                // 0x191f03490: the 16.0 keys, plus the 16.2 keys
    if (gY37TEncXPC) ((void (*)(id, SEL, id))gY37TEncXPC)(self, _cmd, xdict);
    if (!Y37_On() || !Y37_XPC()) return;
    id p = Y37_TPredicate(self, NULL);
    gY37X.serObj(p, xdict, "targetPredicate");
    gY37X.setBool(xdict, "shouldDismissOnUILock", BPX_Bool0(self, "shouldDismissOnUILock"));
    gY37X.setBool(xdict, "shouldDismissInSwitcher", BPX_Bool0(self, "shouldDismissInSwitcher"));
    gY37X.setBool(xdict, "requiresFullscreenPresentation", BPX_Bool0(self, "requiresFullscreenPresentation"));
}

// ------------------------------------------------------------------------------------------------ SpringBoard
// -remoteTransientOverlaySessionManager:shouldActivateOverlayWithContext:forSession:  16.2 0x1c735a4b4: YES unless the target application is blocked for Screen Time expiration and is not a hidden system app
static BOOL Y37_ShouldActivate(id self, SEL _cmd, id manager, id context, id session) {
    if (!Y37_On()) return gY37Should ? ((BOOL (*)(id, SEL, id, id, id))gY37Should)(self, _cmd, manager, context, session) : YES;
    id pred = BPX_Obj0(BPX_Obj0(context, "presentationTarget"), "targetPredicate");
    id app = pred ? ((id (*)(id, SEL, id))objc_msgSend)(pred, sel_registerName("targetApplicationWithController:"), BPX_Obj0((id)NSClassFromString(@"SBApplicationController"), "sharedInstance")) : nil;
    if (!app) return YES;
    if (!BPX_Bool0(BPX_Obj0(app, "info"), "isBlockedForScreenTimeExpiration")) return YES;
    if (BPX_Bool0(app, "isSystemApplication") && BPX_Bool0(BPX_Obj0(app, "info"), "hasHiddenTag")) return YES;
    BP_Log(@"[y37] remote alert for %@ refused: blocked for Screen Time expiration", BPX_Obj0(app, "bundleIdentifier"));
    return NO;
}
// -performPresentationRequest:forSession:  16.2 0x1c735acb8, embedded path (0x1c735ad9c .. 0x1c735b070) for a target whose predicate has no process
static BOOL Y37_Perform(id self, SEL _cmd, id manager, id request, id session) {
    BOOL (*orig)(id, SEL, id, id, id) = (BOOL (*)(id, SEL, id, id, id))gY37Perform;
    if (!Y37_On()) return orig ? orig(self, _cmd, manager, request, session) : NO;
    id pred = BPX_Obj0(BPX_Obj0(request, "presentationTarget"), "targetPredicate");
    if (!pred || BPX_Obj0(pred, "process") || !BPX_Obj0(pred, "launchingApplicationIdentity") || !BPX_Bool0(request, "shouldPresentEmbeddedInTargetScene"))
        return orig ? orig(self, _cmd, manager, request, session) : NO;                      // process predicates: the 16.0 body is the same code
    BOOL (^finish)(BOOL) = ^BOOL(BOOL handled) {                                               // block 0x1c735b468
        if (handled && BPX_Bool0(request, "shouldDismissPresentedBanners")) {
            id bm = BPX_Obj0(self, "bannerManager");
            SEL s = sel_registerName("dismissAllBannersInAllWindowScenesAnimated:reason:");
            if (bm && [bm respondsToSelector:s]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(bm, s, YES, @"Remote alert presentation requests dismiss all banners");
        }
        return handled;
    };
    SEL hs = sel_registerName("handleRemoteTransientOverlayPresentationRequest:forSession:");
    if ([self respondsToSelector:hs] && ((BOOL (*)(id, SEL, id, id))objc_msgSend)(self, hs, request, session)) return finish(YES);
    id app = ((id (*)(id, SEL, id))objc_msgSend)(pred, sel_registerName("targetApplicationWithController:"), BPX_Obj0((id)NSClassFromString(@"SBApplicationController"), "sharedInstance"));
    id mw = BPX_Obj0((id)NSClassFromString(@"SBWorkspace"), "mainWorkspace");
    id vc = BPX_Obj0(request, "viewController");
    BOOL presenting = Y37_B1(BPX_Obj0(mw, "transientOverlayPresentationManager"), "isPresentingViewController:", vc);
    id ps = BPX_Obj0(app, "processState");
    BOOL visible = BPX_LL0(ps, "taskState") == 2 && BPX_LL0(ps, "visibility") == 2;
    id provider = nil;
    if (presenting) {
        BP_Anomaly("y37-embedded", @"embedded remote alert request %@: its view controller is already being presented; generic path", request);
    } else if (app) {
        typedef BOOL (*HasSceneFn)(id);
        HasSceneFn hasScene = (HasSceneFn)dlsym(RTLD_DEFAULT, "SBWorkspaceHasApplicationSceneInLockedOrUnlockedEnvironmentLayoutStateMatchingApplication");
        BOOL ok = visible || (hasScene ? hasScene(app) : NO);
        if (!hasScene) BP_Anomaly("y37-embedded", @"SBWorkspaceHasApplicationSceneInLockedOrUnlockedEnvironmentLayoutStateMatchingApplication not found");
        if (!ok && !Y37_B1(mw, "isApplicationRunningAsViewService:", app)) {
            BP_Anomaly("y37-embedded", @"embedded remote alert request %@: target application %@ is neither visible, in the layout state nor a view service: request refused", request, BPX_Obj0(app, "bundleIdentifier"));
            return finish(NO);
        }
        NSArray *providers = BPX_Obj0(BPX_IvarObj(self, "_activeRemoteTransientOverlayViewProviders"), "allObjects");
        id reqScene = BPX_Obj0(request, "windowScene");
        NSIndexSet *idx = [providers indexesOfObjectsPassingTest:^BOOL(id p, NSUInteger i, BOOL *stop) {            // block 0x1c735b4c4
            id other = BPX_Obj0(BPX_Obj0(p, "sceneHandle"), "application");
            if (!Y37_B1(other, "isSameExecutableAsApplication:", app)) return NO;
            if (!reqScene) return YES;
            id del = BPX_Obj0(p, "delegate");
            SEL ws = sel_registerName("windowSceneForOverlayViewProvider:");
            id scene = (del && [del respondsToSelector:ws]) ? ((id (*)(id, SEL, id))objc_msgSend)(del, ws, p) : nil;
            return [scene isEqual:reqScene];
        }];
        if (idx.count == 1) provider = providers[idx.firstIndex];
        else if (idx.count > 1) BP_Anomaly("y37-embedded", @"embedded remote alert request %@ matches %lu providers %@: generic path", request, (unsigned long)idx.count, [providers objectsAtIndexes:idx]);
    }
    if (provider) {
        Class rc = NSClassFromString(@"SBRemoteTransientOverlayViewController");
        id rvc = [vc isKindOfClass:rc] ? vc : nil;
        if (rvc) ((void (*)(id, SEL, id, id))objc_msgSend)(provider, sel_registerName("presentRemoteTransientOverlayViewController:presentationRequest:"), rvc, request);
        return finish(rvc != nil);
    }
    return orig ? orig(self, _cmd, manager, request, session) : NO;                          // 16.2 continues with the generic path (0x1c735b070), which is the 16.0 tail
}

// ------------------------------------------------------------------------------------------------ SBDeviceApplicationRemoteTransientOverlayViewProvider
// -initWithSceneHandle:delegate: 16.2 0x1c78b0d94: super init and the two observers (cover sheet did present, app switcher will reveal); NO registration with SpringBoard (16.0 0x1c6403db8 registered here)
static Y37_NEWRET id Y37_ProviderInit(Y37_CONSUMED id self, SEL _cmd, id handle, id delegate) {
    if (!Y37_On()) return ((Y37_NEWRET id (*)(Y37_CONSUMED id, SEL, id, id))gY37PInit)(self, _cmd, handle, delegate);
    Class sup = class_getSuperclass(NSClassFromString(@"SBDeviceApplicationRemoteTransientOverlayViewProvider"));
    IMP simp = sup ? method_getImplementation(class_getInstanceMethod(sup, _cmd)) : NULL;
    if (!simp) { BP_Anomaly("y37-provider", @"superclass init missing: the 16.0 init runs"); return ((Y37_NEWRET id (*)(Y37_CONSUMED id, SEL, id, id))gY37PInit)(self, _cmd, handle, delegate); }
    id me = ((Y37_NEWRET id (*)(Y37_CONSUMED id, SEL, id, id))simp)(self, _cmd, handle, delegate);
    if (me) {
        void *cs = dlsym(RTLD_DEFAULT, "SBCoverSheetDidPresentNotification"), *sw = dlsym(RTLD_DEFAULT, "SBUIAppSwitcherWillRevealNotification");
        NSString *csn = cs ? *(__unsafe_unretained NSString *const *)cs : nil, *swn = sw ? *(__unsafe_unretained NSString *const *)sw : nil;
        if (!csn || !swn) BP_Anomaly("y37-provider", @"notification names missing (cover sheet %@, app switcher %@)", csn, swn);
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        if (csn) [nc addObserver:me selector:sel_registerName("_handleCoverSheetDidPresent:") name:csn object:nil];
        if (swn) [nc addObserver:me selector:sel_registerName("_handleAppSwitcherWillPresent:") name:swn object:nil];
    }
    return me;
}
static void Y37_ProviderNoteMode(id self, SEL _cmd, long long mode) {                                  // 0x1c78b1624
    id sb = BPX_App();
    if (!Y37_On()) mode = 4;                                                                          // switch off: registered for the life of the provider (16.0)
    SEL s = sel_registerName(mode == 4 ? "registerRemoteAlertSceneViewProvider:" : "unregisterRemoteAlertSceneViewProvider:");
    if (sb && [sb respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(sb, s, self);
    BPY_LOG(@"[y37] provider %p display mode %lld: %s", (__bridge void *)self, mode, mode == 4 ? "registered" : "unregistered");
}
static void Y37_BaseNoteMode(id self, SEL _cmd, long long mode) {}                                      // 0x1c79510d8: empty
static void Y37_ProviderAppSwitcher(id self, SEL _cmd, id note) {                                       // 0x1c78b1b88: only targets that ask for it are dismissed
    NSArray *ctxs = [BPX_IvarObj(self, "_activePresentationContexts") copy];
    for (id c in ctxs) {
        if (!BPX_Bool0(BPX_Obj0(c, "presentationTarget"), "shouldDismissInSwitcher")) continue;
        id rvc = BPX_Obj0(c, "remoteViewController");
        ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("dismissRemoteTransientOverlayViewController:"), rvc);
    }
}

// ------------------------------------------------------------------------------------------------ SBDeviceApplicationSceneViewController: display mode callouts to the overlay providers
static void Y37_NotifyProviders(id vc, long long mode) {
    for (id p in [BPX_IvarObj(vc, "_overlayViewProviders") copy]) {
        SEL s = sel_registerName("noteDisplayModeChange:");
        if ([p respondsToSelector:s]) ((void (*)(id, SEL, long long))objc_msgSend)(p, s, mode);
    }
}
static void Y37_VCSetDisplayMode(id self, SEL _cmd, long long mode, id factory, id completion) {        // 0x1c75bb1f0: super, then the providers
    Class sup = class_getSuperclass(NSClassFromString(@"SBDeviceApplicationSceneViewController"));
    IMP simp = sup ? method_getImplementation(class_getInstanceMethod(sup, _cmd)) : NULL;
    if (simp) ((void (*)(id, SEL, long long, id, id))simp)(self, _cmd, mode, factory, completion);
    else BP_Anomaly("y37-vc", @"setDisplayMode:animationFactory:completion: has no superclass implementation");
    if (Y37_On()) Y37_NotifyProviders(self, mode);
}
static void Y37_VCCreateProviders(id self, SEL _cmd) {                                                  // 0x1c75bbb70: after the first creation each provider is told the current mode
    BOOL had = BPX_IvarObj(self, "_overlayViewProviders") != nil;
    if (gY37VCCreate) ((void (*)(id, SEL))gY37VCCreate)(self, _cmd);
    if (!had && Y37_On()) Y37_NotifyProviders(self, BPX_LL0(self, "displayMode"));
}
static void Y37_VCSecure(id self, SEL _cmd, BOOL secure) {                                              // 0x1c75bd6b4
    if (gY37VCSecure) ((void (*)(id, SEL, BOOL))gY37VCSecure)(self, _cmd, secure);
    if (Y37_On() && BPX_Bool0(self, "rendersWhileLocked") != secure) Y37_NotifyProviders(self, BPX_LL0(BPX_Obj0(self, "_sceneView"), "effectiveDisplayMode"));
}

// ------------------------------------------------------------------------------------------------ setup
static Class Y37_NewClass(const char *name, const char *p1, const char *p2, const char *p3, void (^fill)(Class c, Class m)) {
    Class existing = objc_getClass(name);
    if (existing) return existing;
    Class cls = objc_allocateClassPair([NSObject class], name, 0);
    if (!cls) { BP_Anomaly("y37-class", @"objc_allocateClassPair(%s) failed", name); return Nil; }
    fill(cls, object_getClass(cls));
    const char *ps[3] = { p1, p2, p3 };
    for (int i = 0; i < 3; i++) if (ps[i]) { Protocol *p = objc_getProtocol(ps[i]); if (p) class_addProtocol(cls, p); }
    objc_registerClassPair(cls);
    return cls;
}
__attribute__((constructor)) static void Y37_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        gY37Pred = Y37_NewClass("SBSRemoteAlertPresentationTargetPredicate", "BSDescriptionProviding", "BSXPCCoding", "NSSecureCoding", ^(Class c, Class m) {
            ADD(m, "supportsSecureCoding", Y37_Yes, "B16@0:8");
            ADD(m, "predicateForProcess:", Y37_PredForProcess, "@24@0:8@16");
            ADD(m, "predicateForLaunchingApplicationIdentity:", Y37_PredForLaunching, "@24@0:8@16");
            ADD(c, "_init", Y37_PredInit, "@16@0:8");
            ADD(c, "process", Y37_PredProcess, "@16@0:8");
            ADD(c, "setProcess:", Y37_PredSetProcess, "v24@0:8@16");
            ADD(c, "launchingApplicationIdentity", Y37_PredLaunch, "@16@0:8");
            ADD(c, "setLaunchingApplicationIdentity:", Y37_PredSetLaunch, "v24@0:8@16");
            ADD(c, "scenePersistentIdentifier", Y37_PredScene, "@16@0:8");
            ADD(c, "setScenePersistentIdentifier:", Y37_PredSetScene, "v24@0:8@16");
            ADD(c, "initWithXPCDictionary:", Y37_PredInitXPC, "@24@0:8@16");
            ADD(c, "encodeWithXPCDictionary:", Y37_PredEncXPC, "v24@0:8@16");
            ADD(c, "initWithCoder:", Y37_PredInitCoder, "@24@0:8@16");
            ADD(c, "encodeWithCoder:", Y37_PredEncCoder, "v24@0:8@16");
            ADD(c, "description", Y37_PredDesc, "@16@0:8");
            ADD(c, "succinctDescription", Y37_PredDesc, "@16@0:8");
            ADD(c, "targetApplicationWithController:", Y37_TargetApp, "@24@0:8@16");
            ADD(c, "matchesOverlayViewController:", Y37_MatchesVC, "B24@0:8@16");
            ADD(c, "configureTransientOverlayContext:", Y37_ConfigureContext, "v24@0:8@16");
            ADD(c, "_launchingApplicationRecord", Y37_LaunchRecord, "@16@0:8");
        });
        // the target (16.0 class)
        Class tg = NSClassFromString(@"SBSRemoteAlertPresentationTarget");
        if (tg && gY37Pred && class_getInstanceMethod(tg, sel_registerName("targetProcess")) && class_getInstanceMethod(tg, sel_registerName("initWithXPCDictionary:"))) {
            ADD(tg, "targetPredicate", Y37_TPredicate, "@16@0:8");
            ADD(tg, "initWithTargetPredicate:", Y37_TInitPredicate, "@24@0:8@16");
            ADD(tg, "shouldDismissInSwitcher", Y37_TDismissSwitcher, "B16@0:8");
            ADD(tg, "setShouldDismissInSwitcher:", Y37_TSetDismissSwitcher, "v20@0:8B16");
            gY37TProcess = BPX_Replace(tg, "targetProcess", (IMP)Y37_TProcess);
            gY37TScene = BPX_Replace(tg, "scenePersistentIdentifier", (IMP)Y37_TScene);
            gY37TSetScene = BPX_Replace(tg, "setScenePersistentIdentifier:", (IMP)Y37_TSetScene);
            gY37TInitXPC = BPX_Replace(tg, "initWithXPCDictionary:", (IMP)Y37_TInitXPC);
            gY37TEncXPC = BPX_Replace(tg, "encodeWithXPCDictionary:", (IMP)Y37_TEncXPC);
            n++;
        } else BP_Anomaly("y37-install", @"[y37] SBSRemoteAlertPresentationTarget / predicate class missing: target not extended");
        // SpringBoard-side category on the predicate class already added above; overlay VC helpers
        Class rc = NSClassFromString(@"SBRemoteTransientOverlayViewController"), tc = NSClassFromString(@"SBTransientOverlayViewController");
        if (rc && !class_getInstanceMethod(rc, sel_registerName("isPresentedByBundleIdentifier:"))) ADD(rc, "isPresentedByBundleIdentifier:", Y37_VCPresentedByBundle, "B24@0:8@16");
        if (tc && !class_getInstanceMethod(tc, sel_registerName("isPresentedByBundleIdentifier:"))) ADD(tc, "isPresentedByBundleIdentifier:", Y37_VCPresentedByBundleBase, "B24@0:8@16");
        // SpringBoard
        Class sb = NSClassFromString(@"SpringBoard");
        if (sb && class_getInstanceMethod(sb, sel_registerName("remoteTransientOverlaySessionManager:shouldActivateOverlayWithContext:forSession:")) &&
            class_getInstanceMethod(sb, sel_registerName("remoteTransientOverlaySessionManager:performPresentationRequest:forSession:"))) {
            gY37Should = BPX_Replace(sb, "remoteTransientOverlaySessionManager:shouldActivateOverlayWithContext:forSession:", (IMP)Y37_ShouldActivate);
            gY37Perform = BPX_Replace(sb, "remoteTransientOverlaySessionManager:performPresentationRequest:forSession:", (IMP)Y37_Perform);
            n++;
        } else BP_Anomaly("y37-install", @"[y37] SpringBoard remote transient overlay session manager selectors missing: not installed");
        // providers
        Class pv = NSClassFromString(@"SBDeviceApplicationRemoteTransientOverlayViewProvider"), bp = NSClassFromString(@"SBDeviceApplicationSceneOverlayViewProvider");
        Class vc = NSClassFromString(@"SBDeviceApplicationSceneViewController");
        if (pv && bp && vc && class_getInstanceMethod(pv, sel_registerName("initWithSceneHandle:delegate:")) && class_getInstanceMethod(pv, sel_registerName("_handleAppSwitcherWillPresent:")) &&
            class_getInstanceMethod(vc, sel_registerName("_createSceneOverlayViewProvidersIfNecessary")) && class_getInstanceMethod(vc, sel_registerName("_configureForSecureDisplay:"))) {
            if (!class_getInstanceMethod(bp, sel_registerName("noteDisplayModeChange:"))) ADD(bp, "noteDisplayModeChange:", Y37_BaseNoteMode, "v24@0:8q16");
            ADD(pv, "noteDisplayModeChange:", Y37_ProviderNoteMode, "v24@0:8q16");
            gY37PInit = BPX_Replace(pv, "initWithSceneHandle:delegate:", (IMP)Y37_ProviderInit);
            BPX_Replace(pv, "_handleAppSwitcherWillPresent:", (IMP)Y37_ProviderAppSwitcher);
            if (!class_getInstanceMethod(vc, sel_registerName("setDisplayMode:animationFactory:completion:"))) BP_Anomaly("y37-install", @"[y37] SBDeviceApplicationSceneViewController has no setDisplayMode:animationFactory:completion: at all");
            else class_addMethod(vc, sel_registerName("setDisplayMode:animationFactory:completion:"), (IMP)Y37_VCSetDisplayMode, "v40@0:8q16@24@?32");   // a 16.0 override on this class itself is left alone (class_addMethod fails)
            gY37VCCreate = BPX_Replace(vc, "_createSceneOverlayViewProvidersIfNecessary", (IMP)Y37_VCCreateProviders);
            gY37VCSecure = BPX_Replace(vc, "_configureForSecureDisplay:", (IMP)Y37_VCSecure);
            n++;
        } else BP_Anomaly("y37-install", @"[y37] overlay provider / scene view controller selectors missing: provider registration stays as in 16.0");
        BP_Log(@"[y37] installed %d group(s) (switch y37_alerttarget)", n);
    }
}
#pragma clang diagnostic pop
