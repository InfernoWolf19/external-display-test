// Y36Preflight.x : the privacy preflight gate of 16.2 (DELTA-SWEEP-0.7.9.md rows SBToAppsWorkspaceTransaction -_willBegin, SBApplicationSceneUpdateTransaction (3 rows), FrontBoard
// FBApplicationUpdateScenesTransaction, SBMainWorkspaceLayoutStateContingencyPlan preflight leg; Pass 4).  Setup: constructor.  Log prefix "[y36]".  Switches y36_preflight (everything
// except the FrontBoard launch scheduling), y36_fblaunch (FrontBoard launch scheduling).  Both default ON.
//
// WHAT 16.2 DOES.  When an app that carries Info.plist NSRegulatoryPrivacyDisclosureVersion is about to be shown in the foreground and the user has not consented to that disclosure
// version, SpringBoard does not let the app process launch until a consent UI (the remote alert service com.apple.PDUIApp / PDURemoteViewController) has been answered:
//   * PrivacyDisclosureCore (a 16.2 only framework, absent from the 16.0 cache): +[PDCPreflightManager isPreflightFeatureEnabled] 0x20e63dea0 =
//       (os_feature PrivacyDisclosure/preflightInAllRegions || MGGetBoolAnswer("green-tea")) && (os_feature PrivacyDisclosure/preflight || ct_green_tea_logging_enabled()).
//     The shipped FeatureFlags domain PrivacyDisclosure.plist of 20C65 is EMPTY, so on a retail device the gate is on exactly where MobileGestalt green-tea and CoreTelephony's green tea
//     logging are on (regulated regions); everywhere else 16.2 answers NO and launches at once, and so does this port (same inputs).
//     -[PDCPreflightManager _requiresPreflightForApplication:] 0x20e63db50 -> -_requiresPreflightForApplicationRecord: 0x20e63dc00: feature enabled && record.regulatoryPrivacyDisclosureVersion != nil
//       && ![version isEqual:[consentStore userConsentedRegulatoryDisclosureVersionForBundleIdentifier:record.bundleIdentifier]].
//     -[PDCPreflightManager _preflightLaunchForApplication:withCompletionHandler:] 0x20e63dccc: not required -> dispatch_async(queue, completion(1)) and the already completed handle; required ->
//       PDCPreflightRequestHandle initWithQueue:completionHandler: + [PDCPrivacyAlertPresenter activateRemoteAlertWithIdentity:requestHandle:forcePresent:NO completionHandler:] whose answer
//       a in {1,2,3} is mapped through the table {1,0,2} (0x20e63f4a0) indexed by a-1 (anything else: 0) and completes the handle.
//     PDCFileBackedConsentStore (/var/mobile/Library/com.apple.PrivacyDisclosure/consents/<bundleID>, UTF-8 text = consented version), PDCPreflightRequestHandle (atomic complete-once, completion
//       dispatched on the manager's queue), PDCPrivacyAlertPresenter (serial queue com.apple.PrivacyDisclosure.PrivacyAlertPresenter, request -> alert map).
//   * SpringBoard: SBPrivacyPreflightController 0x1c7422008 (PDCPreflightManager on the main queue, one SBApplicationPrivacyPreflightController per application identity),
//     SBApplicationPrivacyPreflightController 0x1c78b43a8..0x1c78b4ac4 (pending completions per scene id, one PDC request at a time, results {0,1,2}: 0 -> 0, 1 -> 1, other -> 2, delivered
//     to the completions in reverse order with isLast for the first registered), -[SpringBoard privacyPreflightController] 0x1c7363a5c.
//   * SBApplicationSceneUpdateTransaction (16.2 0x1c78fdf4c init with delegate, 0x1c78fe4a8 _willBegin + blocks 0x1c78fe68c / 0x1c78fe818, 0x1c72baf2c _didComplete, 0x1c78fea60
//     _isReadyToLaunch, 0x1c78fef68 _createUpdateTransactionForPreflightCompletion, 0x1c78feae0 description): ivars _applicationIdentity, _privacyPreflightController, _requiresPreflight, _delegate
//     (the 16.0 class has no room for them: kept as associated objects).  _requiresPreflight = scene settings isForeground ? [controller requiresPreflightForApplication:identity] : NO.
//     _willBegin with _requiresPreflight: [super _willBegin], audit "running preflight for %@", preflightLaunch...: result (isLast): 0 -> _SBWorkspaceDestroyApplicationEntity + delegate
//     finishedApplyingUpdate:NO; 1 -> a NEW SBApplicationSceneUpdateTransaction from a request labelled AfterPreflightSceneUpdateTransaction (same source and application context) runs and reports
//     to the delegate; 2 -> delegate finished:NO; a non-last completion reports (result == 1).  Without _requiresPreflight the 16.0 body (scene update in progress, live resize milestone) runs.
//     _didComplete additionally tells the delegate (!isFailed) when no preflight was involved.  SBAppViewController is the delegate (0x1c781b468: on failure it tells ITS delegate
//     appViewControllerDidFailToActivateApplication:), SBDashBoardHostedAppViewController forwards to dashBoardHostedAppViewControllerDidFailToActivateApplication:, the camera page dismisses.
//   * FrontBoard (16.2 only changes): FBApplicationUpdateScenesTransaction no longer adds the process launch child in its init; -_executeProcessLaunchIfAppropriate 0x1a3665490 adds it (and observes
//     it) once -_isReadyToLaunch 0x1a3665488 (YES; SBApplicationSceneUpdateTransaction answers !_requiresPreflight) holds; -_willBegin 0x1a3665120, -_childTransactionDidComplete: 0x1a36653a4,
//     -_childTransactionDidFinishWork: 0x1a36653f0 and -_didSatisfyMilestone: 0x1a366543c call super and then re-evaluate.  16.2 init 0x1a363a504 differs from 16.0 0x1a3022820 ONLY in the missing
//     addObserver: / addChildTransaction: (everything else of the class is call-for-call identical, checked with the body diff).  New ivar _hasScheduledProcessLaunch (associated object here).
//   * SBToAppsWorkspaceTransaction -_willBegin 16.2 0x1c729b83c (16.0 0x1c5e28ffc): the PRELAUNCH of apps that are not running is skipped for apps that require preflight (audit "%@ requires
//     preflight. Skipping prelaunch."); the rest is the 16.0 body.
//   * SBMainWorkspaceLayoutStateContingencyPlan -transitionContextForLayoutContext:failedEntities: 16.2 0x1c7904c94 (preflight leg 0x1c79051f8): an application entity with failedLaunchCount <= 1 that
//     requires preflight gets the same removal context (animationStyle 0, removalActionType 1) as one with failedLaunchCount >= 2 (a refused / failed preflight goes back instead of retrying).
//
// WHAT IS DIFFERENT HERE.  The consent UI com.apple.PDUIApp does not exist on 16.0 (it is a 16.2 system app; PrivacyDisclosureUI.framework is absent from the 16.0 cache).  The remote alert
// transport (SBSRemoteAlertHandle to PDURemoteViewController, BSAction answer with the integer in setting 0) is replaced by a native SpringBoard alert on the iPad window scene that returns the
// same integers (1 continue, 2 do not continue) and writes the consent record (PDUIApp does that write in 16.2) when the answer is 1; the text is the app name + the disclosure version.
// -[SpringBoard privacyPreflightController] is created on first use (16.2 creates it in SpringBoard's init): never message live singletons from a constructor.
//
// Every guard that falls back to 16.0 behaviour logs through BP_Anomaly("y36-..."), always on.  Kill files: Backport162.off.y36_preflight, Backport162.off.y36_fblaunch.
//
// Needs a device with MobileGestalt green-tea (a regulated region) or Backport162.on.y36_forcepreflight (opt-in test switch, reads as os_feature PrivacyDisclosure/preflight + green tea): launch an app that carries
// NSRegulatoryPrivacyDisclosureVersion; the consent alert appears before the app process is launched, "Continue" opens the app, the second launch does not ask again.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <errno.h>
#import <unistd.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

// ------------------------------------------------------------------------------------------------ small helpers
@interface Y36Weak : NSObject { @public __weak id obj; }
@end
@implementation Y36Weak
@end

static char kY36Req, kY36Ctl, kY36Ident, kY36Delegate;                         // SBApplicationSceneUpdateTransaction state
static char kY36HasScheduled;                                                  // FBApplicationUpdateScenesTransaction _hasScheduledProcessLaunch
static char kY36MQueue, kY36MStore;                                            // PDCPreflightManager
static char kY36HDone, kY36HQueue, kY36HHandler;                               // PDCPreflightRequestHandle
static char kY36SURL, kY36SObs;                                                // PDCFileBackedConsentStore
static char kY36PQueue, kY36PMap, kY36PCurrent;                                              // PDCPrivacyAlertPresenter
static char kY36CMgr, kY36CDict, kY36CIdent, kY36CPending, kY36CToken;         // controllers

#define Y36_SET(o, k, v) objc_setAssociatedObject((o), &(k), (v), OBJC_ASSOCIATION_RETAIN_NONATOMIC)
#define Y36_GET(o, k)    objc_getAssociatedObject((o), &(k))
#define Y36_NEWRET __attribute__((ns_returns_retained))
#define Y36_CONSUMED __attribute__((ns_consumed))

static IMP gY36OrigSceneInit, gY36OrigWillBegin, gY36OrigDidComplete, gY36OrigDesc, gY36OrigToAppsWillBegin, gY36OrigPlan, gY36OrigAppVCCreate, gY36OrigFBInit;
static Class gY36PDCStore, gY36PDCManager, gY36PDCHandle, gY36PDCPresenter, gY36SBCtl, gY36SBAppCtl;

static BOOL Y36_On(void) { return BP_OnName("y36_preflight"); }

// init-family call: the receiver is consumed and the result is +1 (G1B_INIT contract): a plain cast would double release the alloc'd object
#define Y36_INIT(...) ((Y36_NEWRET id (*)(Y36_CONSUMED id, SEL, __VA_ARGS__))objc_msgSend)

static BOOL Y36_BoolArg(id o, const char *sel, id a) {                  // BOOL result, one object argument; a miss is logged once and reads NO
    SEL s = sel_registerName(sel);
    if (!o) return NO;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-y36", o, s); return NO; }
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(o, s, a);
}
static void Y36_Finished(id delegate, id txn, BOOL ok) {               // -[<SBApplicationSceneUpdateTransactionDelegate> sceneUpdateTransaction:finishedApplyingUpdate:]
    SEL s = sel_registerName("sceneUpdateTransaction:finishedApplyingUpdate:");
    if (delegate && [delegate respondsToSelector:s]) ((void (*)(id, SEL, id, BOOL))objc_msgSend)(delegate, s, txn, ok);
    else if (delegate) BP_SelMiss("sel-y36", delegate, s);
}
static void Y36_SetObj2(id o, const char *sel, id a, id b) {
    SEL s = sel_registerName(sel);
    if (!o) return;
    if (![o respondsToSelector:s]) { BP_SelMiss("sel-y36", o, s); return; }
    ((void (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b);
}

static BOOL Y36_AuditOn(id txn) {
    SEL s = sel_registerName("isAuditHistoryEnabled");
    return txn && [txn respondsToSelector:s] && ((BOOL (*)(id, SEL))objc_msgSend)(txn, s);
}
static void Y36_AuditAdd(id txn, NSString *text) {                    // -[BSTransaction _addAuditHistoryItem:] takes a format; the text is passed as an argument
    SEL s = sel_registerName("_addAuditHistoryItem:");
    if (txn && [txn respondsToSelector:s]) ((void (*)(id, SEL, id, ...))objc_msgSend)(txn, s, @"%@", text);
}

// ------------------------------------------------------------------------------------------------ PrivacyDisclosureCore : the consent store
// 16.2 _PDCGlobalConsentStoreInstance 0x20e63ceb0: one PDCFileBackedConsentStore at this URL (the change observer feeds _PDCGlobalBackupManager = nil in 16.2: none)
static id Y36_GlobalStore(void) {
    static id store; static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!gY36PDCStore) return;
        NSURL *u = [NSURL fileURLWithPath:@"/var/mobile/Library/com.apple.PrivacyDisclosure/consents/"];
        store = Y36_INIT(id)([gY36PDCStore alloc], sel_registerName("initWithConsentStoreURL:"), u);
    });
    return store;
}

static Y36_NEWRET id Y36_StoreInit(Y36_CONSUMED id self, SEL _cmd, NSURL *url) {            // 0x20e63cab0
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) Y36_SET(me, kY36SURL, url);
    return me;
}
static id Y36_StoreURL(id self, SEL _cmd) { return Y36_GET(self, kY36SURL); }                       // 0x20e63ce54
static id Y36_StoreObserver(id self, SEL _cmd) { return Y36_GET(self, kY36SObs); }
static void Y36_StoreSetObserver(id self, SEL _cmd, id blk) { objc_setAssociatedObject(self, &kY36SObs, blk, OBJC_ASSOCIATION_COPY_NONATOMIC); }
static id Y36_StoreRecordURL(id self, SEL _cmd, NSString *bundleID) {                              // 0x20e63cda4: nil bundle id -> nil
    NSURL *base = Y36_GET(self, kY36SURL);
    return bundleID ? [base URLByAppendingPathComponent:bundleID] : nil;
}
static id Y36_StoreRead(id self, SEL _cmd, NSString *bundleID) {                                   // 0x20e63cb2c
    if (!bundleID) return nil;
    NSURL *u = ((id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("consentRecordURLForBundleIdentifier:"), bundleID);
    if (!u) return nil;
    NSError *err = nil;
    NSString *s = [NSString stringWithContentsOfURL:u encoding:NSUTF8StringEncoding error:&err];
    if (err && BP_LogEnabled()) BP_Log(@"[y36] consent record of %@ not readable: %@", bundleID, err);
    return s;
}
static id Y36_StoreWrite(id self, SEL _cmd, NSString *version, NSString *bundleID) {              // 0x20e63cc04: version nil removes the record
    NSURL *u = ((id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("consentRecordURLForBundleIdentifier:"), bundleID);
    if (version) {
        NSError *e1 = nil;
        BOOL ok = [[NSFileManager defaultManager] createDirectoryAtURL:[u URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&e1];
        if (!ok) return e1;
        NSError *e2 = nil;
        ok = [version writeToURL:u atomically:YES encoding:NSUTF8StringEncoding error:&e2];
        if (!ok) return e2;
    } else {
        if (unlink(u.fileSystemRepresentation) != 0 && errno != ENOENT) return [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    }
    void (^obs)(id, id, id) = Y36_GET(self, kY36SObs);
    if (obs) obs(self, bundleID, version);
    return nil;
}
static id Y36_StoreAll(id self, SEL _cmd) {                                                         // 0x20e63cdac
    NSURL *u = Y36_GET(self, kY36SURL);
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[NSString stringWithUTF8String:u.fileSystemRepresentation] error:NULL];
    return [NSSet setWithArray:items ?: @[]];
}

// ------------------------------------------------------------------------------------------------ PrivacyDisclosureCore : the request handle
static Y36_NEWRET id Y36_HandleInit(Y36_CONSUMED id self, SEL _cmd, id queue, id handler) {         // 0x20e63c7cc
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        Y36_SET(me, kY36HDone, @NO);
        Y36_SET(me, kY36HQueue, queue);
        objc_setAssociatedObject(me, &kY36HHandler, handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return me;
}
static id Y36_HandleAlready(id cls, SEL _cmd) {                                                      // 0x20e63c724 (singleton, 0x20e63c778 flags it complete)
    static id h; static dispatch_once_t once;
    dispatch_once(&once, ^{
        h = Y36_INIT(id, id)([gY36PDCHandle alloc], sel_registerName("initWithQueue:completionHandler:"), nil, nil);
        Y36_SET(h, kY36HDone, @YES);
    });
    return h;
}
static void Y36_HandleComplete(id self, SEL _cmd, unsigned long long response) {                  // 0x20e63c870 (atomic complete-once, handler runs on the queue)
    void (^handler)(unsigned long long) = nil; dispatch_queue_t q = nil;
    @synchronized (self) {
        if ([Y36_GET(self, kY36HDone) boolValue]) return;
        Y36_SET(self, kY36HDone, @YES);
        handler = Y36_GET(self, kY36HHandler);
        q = Y36_GET(self, kY36HQueue);
        objc_setAssociatedObject(self, &kY36HHandler, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        Y36_SET(self, kY36HQueue, nil);
    }
    if (handler && q) dispatch_async(q, ^{ handler(response); });
}
static void Y36_HandleCancel(id self, SEL _cmd) {                                                    // 0x20e63c954
    if (BP_LogEnabled()) BP_Log(@"[y36] Disclosure alert cancelled by client.");
    id pres = ((id (*)(id, SEL))objc_msgSend)((id)gY36PDCPresenter, sel_registerName("sharedPresenter"));
    ((void (*)(id, SEL, id))objc_msgSend)(pres, sel_registerName("didCancelRequestHandle:"), self);
    ((void (*)(id, SEL, unsigned long long))objc_msgSend)(self, sel_registerName("completeRequestWithResponse:"), 0ULL);
}

// ------------------------------------------------------------------------------------------------ PrivacyDisclosureCore : the manager
static BOOL Y36_OsFeature(const char *domain, const char *feature) {
    static BOOL (*fn)(const char *, const char *); static dispatch_once_t once;
    dispatch_once(&once, ^{      // the Mach-O symbol is __os_feature_enabled_impl (libsystem_featureflags), i.e. dlsym name "_os_feature_enabled_impl"
        fn = (BOOL (*)(const char *, const char *))dlsym(RTLD_DEFAULT, "_os_feature_enabled_impl");
        if (!fn) fn = (BOOL (*)(const char *, const char *))dlsym(RTLD_DEFAULT, "os_feature_enabled_impl");
    });
    if (!fn) { BP_Anomaly("y36-feature", @"_os_feature_enabled_impl (libsystem_featureflags) not found by dlsym: PrivacyDisclosure/%s reads NO", feature); return NO; }
    return fn(domain, feature);
}
// 0x20e63dea0 + blocks 0x20e63dee4 / the green tea once: (allRegions || green-tea) && (preflight || ct_green_tea_logging_enabled())
static BOOL Y36_ManagerFeature(id cls, SEL _cmd) {
    static BOOL result; static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL (*mg)(CFStringRef) = (BOOL (*)(CFStringRef))dlsym(RTLD_DEFAULT, "MGGetBoolAnswer");
        BOOL (*ct)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "ct_green_tea_logging_enabled");
        if (!mg) BP_Anomaly("y36-feature", @"MGGetBoolAnswer not found: green-tea reads NO");
        if (!ct) BP_Anomaly("y36-feature", @"ct_green_tea_logging_enabled not found: reads NO");
        BOOL preflight = Y36_OsFeature("PrivacyDisclosure", "preflight");
        BOOL allRegions = Y36_OsFeature("PrivacyDisclosure", "preflightInAllRegions");
        BOOL greenTea = mg ? mg(CFSTR("green-tea")) : NO;
        BOOL ctLog = ct ? ct() : NO;
        if (BP_OptInName("y36_forcepreflight")) { BP_Log(@"[y36] Backport162.on.y36_forcepreflight: gate forced on"); preflight = YES; greenTea = YES; }
        result = (allRegions || greenTea) && (preflight || ctLog);
        BP_Log(@"[y36] preflight feature: preflight=%d allRegions=%d green-tea=%d ctGreenTeaLogging=%d -> %d", preflight, allRegions, greenTea, ctLog, result);
    });
    return result;
}
static Y36_NEWRET id Y36_ManagerInitStore(Y36_CONSUMED id self, SEL _cmd, dispatch_queue_t target, id store) {      // 0x20e63da50
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        NSString *label = [NSString stringWithFormat:@"PDCPreflightManager.0x%p", me];
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_INHERIT);
        dispatch_queue_t q = dispatch_queue_create_with_target(label.UTF8String, attr, target);
        Y36_SET(me, kY36MQueue, q);
        Y36_SET(me, kY36MStore, store);
    }
    return me;
}
static Y36_NEWRET id Y36_ManagerInit(Y36_CONSUMED id self, SEL _cmd, dispatch_queue_t target) {                    // 0x20e63d9f4
    return Y36_INIT(id, id)(self, sel_registerName("initWithTargetQueue:consentStore:"), target, Y36_GlobalStore());
}
static id Y36_ManagerQueue(id self, SEL _cmd) { return Y36_GET(self, kY36MQueue); }
static id Y36_ManagerStore(id self, SEL _cmd) { return Y36_GET(self, kY36MStore); }
static void Y36_ManagerSetStore(id self, SEL _cmd, id s) { Y36_SET(self, kY36MStore, s); }
static void Y36_ManagerSetQueue(id self, SEL _cmd, id q) { Y36_SET(self, kY36MQueue, q); }
static BOOL Y36_ManagerReqRecord(id self, SEL _cmd, id record) {                                    // 0x20e63dc00
    if (!Y36_ManagerFeature(nil, NULL)) return NO;
    NSString *version = BPX_Obj0(record, "regulatoryPrivacyDisclosureVersion");
    if (!version) return NO;
    id store = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("consentStore"));
    NSString *consented = BPX_Obj1(store, "userConsentedRegulatoryDisclosureVersionForBundleIdentifier:", BPX_Obj0(record, "bundleIdentifier"));
    return ![version isEqual:consented];
}
static BOOL Y36_ManagerReqRecordPub(id self, SEL _cmd, id record) {                                 // 0x20e63dbfc thunk
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_requiresPreflightForApplicationRecord:"), record);
}
static id Y36_FindRecord(id identity, NSError **err) {
    SEL s = sel_registerName("findApplicationRecordWithError:");
    if (!identity || ![identity respondsToSelector:s]) { Y17_GuardOnce("y36-find", identity, "findApplicationRecordWithError:"); return nil; }
    return ((id (*)(id, SEL, NSError **))objc_msgSend)(identity, s, err);
}
static BOOL Y36_ManagerReqApp(id self, SEL _cmd, id identity) {                                    // 0x20e63db50
    if (!Y36_ManagerFeature(nil, NULL)) return NO;           // identical result to evaluating the record first: the record test starts with the same feature test
    NSError *err = nil;
    id record = Y36_FindRecord(identity, &err);
    if (!record) {
        if (BP_LogEnabled()) BP_Log(@"[y36] no application record for %@: %@", identity, err);
        return NO;
    }
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_requiresPreflightForApplicationRecord:"), record);
}
static BOOL Y36_ManagerReqAppPub(id self, SEL _cmd, id identity) {                                  // 0x20e63db4c thunk
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_requiresPreflightForApplication:"), identity);
}
static NSUInteger Y36_AnswerToResult(NSUInteger a) { return a == 1 ? 1 : (a == 2 ? 0 : (a == 3 ? 2 : 0)); }   // table {1,0,2} at 0x20e63f4a0 indexed by a-1, out of range -> 0
static id Y36_ManagerPreflight(id self, SEL _cmd, id identity, void (^handler)(unsigned long long)) {   // 0x20e63dccc
    dispatch_queue_t q = Y36_GET(self, kY36MQueue);
    if (!((BOOL (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_requiresPreflightForApplication:"), identity)) {
        void (^h)(unsigned long long) = [handler copy];
        dispatch_async(q, ^{ if (h) h(1); });
        return ((id (*)(id, SEL))objc_msgSend)((id)gY36PDCHandle, sel_registerName("alreadyCompletedRequestHandle"));
    }
    id req = Y36_INIT(id, id)([gY36PDCHandle alloc], sel_registerName("initWithQueue:completionHandler:"), q, handler);
    id pres = ((id (*)(id, SEL))objc_msgSend)((id)gY36PDCPresenter, sel_registerName("sharedPresenter"));
    void (^answer)(unsigned long long) = ^(unsigned long long a) {
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(req, sel_registerName("completeRequestWithResponse:"), (unsigned long long)Y36_AnswerToResult((NSUInteger)a));
    };
    ((void (*)(id, SEL, id, id, BOOL, id))objc_msgSend)(pres, sel_registerName("activateRemoteAlertWithIdentity:requestHandle:forcePresent:completionHandler:"), identity, req, NO, answer);
    return req;
}
static id Y36_ManagerPreflightPub(id self, SEL _cmd, id identity, id handler) {                     // 0x20e63dcc8 thunk
    return ((id (*)(id, SEL, id, id))objc_msgSend)(self, sel_registerName("_preflightLaunchForApplication:withCompletionHandler:"), identity, handler);
}

// ------------------------------------------------------------------------------------------------ PrivacyDisclosureCore : the alert presenter (native alert instead of the PDUIApp remote alert)
@interface Y36ConsentAlert : NSObject {
    @public
    UIWindow *window;
    __weak UIAlertController *alert;
}
- (void)invalidate;
@end
@implementation Y36ConsentAlert
- (void)invalidate {
    UIWindow *w = window; UIAlertController *a = alert;
    dispatch_async(dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:NO completion:nil]; w.hidden = YES; });
}
@end

static id Y36_IPadScene(void) {
    id wsm = BPX_WindowSceneManager();
    return BPX_Obj0(wsm, "embeddedDisplayWindowScene");
}
// the native consent alert: answers 1 (Continue; the consent is recorded) or 2 (Don't continue)
static Y36ConsentAlert *Y36_ShowAlert(id identity, BOOL force, void (^answer)(NSUInteger)) {
    Y36ConsentAlert *h = [Y36ConsentAlert new];
    NSError *err = nil;
    id record = Y36_FindRecord(identity, &err);
    NSString *bundleID = BPX_Obj0(record, "bundleIdentifier");
    NSString *name = BPX_Obj0(record, "localizedName") ?: bundleID ?: @"";
    NSString *version = BPX_Obj0(record, "regulatoryPrivacyDisclosureVersion");
    dispatch_async(dispatch_get_main_queue(), ^{
        id scene = Y36_IPadScene();
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            BP_Anomaly("y36-alert", @"no embedded window scene: the consent alert for %@ cannot be shown, answering 3 (dismissed)", bundleID);
            answer(3);
            return;
        }
        UIWindow *w = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
        w.windowLevel = UIWindowLevelAlert + 20;
        w.rootViewController = [UIViewController new];
        w.hidden = NO;
        h->window = w;
        UIAlertController *a = [UIAlertController alertControllerWithTitle:name message:[NSString stringWithFormat:@"%@ must show you a privacy disclosure before it opens (disclosure version %@).", name, version ?: @"?"] preferredStyle:UIAlertControllerStyleAlert];
        h->alert = a;
        void (^finish)(NSUInteger) = ^(NSUInteger r) {
            if (r == 1 && bundleID && version) {
                id store = Y36_GlobalStore();
                id werr = ((id (*)(id, SEL, id, id))objc_msgSend)(store, sel_registerName("writeUserConsentedRegulatoryDisclosureVersion:forBundleIdentifier:"), version, bundleID);
                if (werr) BP_Anomaly("y36-consent", @"consent record of %@ could not be written: %@", bundleID, werr);
            }
            w.hidden = YES;
            answer(r);
        };
        [a addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { finish(1); }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) { finish(2); }]];
        [w.rootViewController presentViewController:a animated:YES completion:nil];
        BP_Log(@"[y36] consent alert for %@ (version %@, force %d)", bundleID, version, (int)force);
    });
    return h;
}
static id Y36_PresenterShared(id cls, SEL _cmd) {                                                    // 0x20e63b158
    static id p; static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[gY36PDCPresenter alloc] init]; });
    return p;
}
static Y36_NEWRET id Y36_PresenterInit(Y36_CONSUMED id self, SEL _cmd) {                             // 0x20e63b1e8
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_autorelease_frequency(DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_INHERIT);
        Y36_SET(me, kY36PQueue, dispatch_queue_create("com.apple.PrivacyDisclosure.PrivacyAlertPresenter", attr));
        Y36_SET(me, kY36PMap, [NSMapTable weakToWeakObjectsMapTable]);
    }
    return me;
}
// 0x20e63b28c: on the presenter queue: log, show the alert, remember it per request, and report the integer answer to the completion handler
static void Y36_PresenterActivate(id self, SEL _cmd, id identity, id handle, BOOL force, void (^completion)(unsigned long long)) {
    dispatch_queue_t q = Y36_GET(self, kY36PQueue);
    NSMapTable *map = Y36_GET(self, kY36PMap);
    void (^c)(unsigned long long) = [completion copy];
    dispatch_async(q, ^{
        BP_Log(@"[y36] Request privacy remote alert for bundle: [%@]", identity);
        __block Y36ConsentAlert *h = nil;
        h = Y36_ShowAlert(identity, force, ^(NSUInteger a) {
            dispatch_async(q, ^{ if (Y36_GET(self, kY36PCurrent) == h) Y36_SET(self, kY36PCurrent, nil); });      // 0x20e63bed4 remoteAlertHandleDidDeactivate: clears _alertHandle
            if (c) c(a);
        });
        Y36_SET(self, kY36PCurrent, h);                                          // _alertHandle (+8): the presenter keeps the alert alive, the request map is weak
        [map setObject:h forKey:handle];
    });
}
static void Y36_PresenterCancel(id self, SEL _cmd, id handle) {                                       // 0x20e63bd50: [map[handle] invalidate]
    dispatch_queue_t q = Y36_GET(self, kY36PQueue);
    NSMapTable *map = Y36_GET(self, kY36PMap);
    dispatch_async(q, ^{ [[map objectForKey:handle] invalidate]; });
}

// ------------------------------------------------------------------------------------------------ SpringBoard : SBPrivacyPreflightController / SBApplicationPrivacyPreflightController
static Y36_NEWRET id Y36_AppCtlInit(Y36_CONSUMED id self, SEL _cmd, id manager, id identity) {      // 0x1c78b43a8
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        Y36_SET(me, kY36CMgr, manager);
        Y36_SET(me, kY36CIdent, identity);
        Y36_SET(me, kY36CPending, [NSMutableDictionary new]);
    }
    return me;
}
static void Y36_AppCtlNote(id self, SEL _cmd, unsigned long long result, id token);
static void Y36_AppCtlAdd(id self, SEL _cmd, void (^completion)(unsigned long long, BOOL), NSString *sceneID) {      // 0x1c78b4458
    if (![NSThread isMainThread]) BP_Anomaly("y36-appctl", @"addPendingCompletion:forSceneIdentifier: called off the main thread (16.2 asserts)");
    NSMutableDictionary *pending = Y36_GET(self, kY36CPending);
    NSMutableArray *list = pending[sceneID];
    if (!list) { list = [NSMutableArray new]; pending[sceneID] = list; }
    [list addObject:[completion copy]];
    id tok = Y36_GET(self, kY36CToken);
    if (tok) { ((void (*)(id, SEL))objc_msgSend)(tok, sel_registerName("cancel")); Y36_SET(self, kY36CToken, nil); }
    id mgr = Y36_GET(self, kY36CMgr);
    __weak id wself = self;
    Y36Weak *box = [Y36Weak new];
    id newTok = ((id (*)(id, SEL, id, id))objc_msgSend)(mgr, sel_registerName("preflightLaunchForApplication:withCompletionHandler:"), Y36_GET(self, kY36CIdent), ^(unsigned long long r) {
        unsigned long long res = r == 0 ? 0 : (r == 1 ? 1 : 2);
        Y36_AppCtlNote(wself, sel_registerName("_notePreflightFinishedWithResult:cancelToken:"), res, box->obj);
    });
    box->obj = newTok;
    Y36_SET(self, kY36CToken, newTok);
}
static void Y36_AppCtlNote(id self, SEL _cmd, unsigned long long result, id token) {                  // 0x1c78b4810
    if (!self) return;
    if (![NSThread isMainThread]) BP_Anomaly("y36-appctl", @"_notePreflightFinishedWithResult:cancelToken: off the main thread (16.2 asserts)");
    if (Y36_GET(self, kY36CToken) != token) return;                       // stale token (a newer request replaced it)
    NSMutableDictionary *pending = [Y36_GET(self, kY36CPending) mutableCopy];
    NSDictionary *snapshot = [pending copy];
    for (id key in snapshot) {
        NSArray *list = snapshot[key];
        [pending removeObjectForKey:key];
        id last = list.lastObject;
        for (void (^blk)(unsigned long long, BOOL) in list.reverseObjectEnumerator) blk(result, (__bridge void *)blk == (__bridge void *)last);
    }
    Y36_SET(self, kY36CPending, pending);
    Y36_SET(self, kY36CToken, nil);
}
static void Y36_AppCtlNotePub(id self, SEL _cmd, unsigned long long result) {                        // 0x1c78b46e8
    Y36_AppCtlNote(self, sel_registerName("_notePreflightFinishedWithResult:cancelToken:"), result, Y36_GET(self, kY36CToken));
}
static id Y36_DescObj(id self, SEL _cmd) { return [NSString stringWithFormat:@"<%@: %p>", NSStringFromClass(object_getClass(self)), self]; }

static Y36_NEWRET id Y36_CtlInit(Y36_CONSUMED id self, SEL _cmd) {                                   // 0x1c7422008
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (me) {
        id mgr = Y36_INIT(id)([gY36PDCManager alloc], sel_registerName("initWithTargetQueue:"), dispatch_get_main_queue());
        Y36_SET(me, kY36CMgr, mgr);
        Y36_SET(me, kY36CDict, [NSMutableDictionary new]);
    }
    return me;
}
static BOOL Y36_CtlRequires(id self, SEL _cmd, id identity) {                                         // 0x1c7422270
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(Y36_GET(self, kY36CMgr), sel_registerName("requiresPreflightForApplication:"), identity);
}
static void Y36_CtlPreflight(id self, SEL _cmd, id identity, NSString *sceneID, void (^completion)(unsigned long long, BOOL)) {      // 0x1c74220ac
    if (!identity || !sceneID || !completion) { BP_Anomaly("y36-ctl", @"preflightLaunchForApplication:sceneIdentifier:withCompletionHandler: with a nil argument (16.2 asserts): ignored"); return; }
    NSMutableDictionary *dict = Y36_GET(self, kY36CDict);
    id ac = dict[identity];
    if (!ac) {
        ac = Y36_INIT(id, id)([gY36SBAppCtl alloc], sel_registerName("initWithPreflightManager:applicationIdentity:"), Y36_GET(self, kY36CMgr), identity);
        dict[identity] = ac;
    }
    ((void (*)(id, SEL, id, id))objc_msgSend)(ac, sel_registerName("addPendingCompletion:forSceneIdentifier:"), completion, sceneID);
}
// -[SpringBoard privacyPreflightController] 0x1c7363a5c: the ivar is created on first use here
static char kY36SBCtl;
static id Y36_SpringBoardCtl(id self, SEL _cmd) {
    id c = Y36_GET(self, kY36SBCtl);
    if (!c) {
        if (!gY36SBCtl) { BP_Anomaly("y36-ctl", @"SBPrivacyPreflightController class missing"); return nil; }
        c = [[gY36SBCtl alloc] init];
        Y36_SET(self, kY36SBCtl, c);
    }
    return c;
}
static id Y36_Ctl(void) { return Y36_SpringBoardCtl(BPX_App(), NULL); }

// ------------------------------------------------------------------------------------------------ class construction
static Class Y36_NewClass(const char *name, const char *protocol, void (^fill)(Class cls, Class meta)) {
    Class existing = objc_getClass(name);
    if (existing) return existing;                                  // never shadow a real class (16.2+)
    Class cls = objc_allocateClassPair([NSObject class], name, 0);
    if (!cls) { BP_Anomaly("y36-class", @"objc_allocateClassPair(%s) failed", name); return Nil; }
    fill(cls, object_getClass(cls));
    if (protocol) { Protocol *p = objc_getProtocol(protocol); if (p) class_addProtocol(cls, p); }
    objc_registerClassPair(cls);
    return cls;
}
#define ADD(c, sel, imp, types) class_addMethod((c), sel_registerName(sel), (IMP)(imp), (types))

static void Y36_BuildClasses(void) {
    gY36PDCStore = Y36_NewClass("PDCFileBackedConsentStore", NULL, ^(Class c, Class m) {
        ADD(c, "initWithConsentStoreURL:", Y36_StoreInit, "@24@0:8@16");
        ADD(c, "storeURL", Y36_StoreURL, "@16@0:8");
        ADD(c, "changeObserver", Y36_StoreObserver, "@?16@0:8");
        ADD(c, "setChangeObserver:", Y36_StoreSetObserver, "v24@0:8@?16");
        ADD(c, "consentRecordURLForBundleIdentifier:", Y36_StoreRecordURL, "@24@0:8@16");
        ADD(c, "userConsentedRegulatoryDisclosureVersionForBundleIdentifier:", Y36_StoreRead, "@24@0:8@16");
        ADD(c, "writeUserConsentedRegulatoryDisclosureVersion:forBundleIdentifier:", Y36_StoreWrite, "@32@0:8@16@24");
        ADD(c, "consentedBundleIdentifiers", Y36_StoreAll, "@16@0:8");
    });
    gY36PDCHandle = Y36_NewClass("PDCPreflightRequestHandle", NULL, ^(Class c, Class m) {
        ADD(m, "alreadyCompletedRequestHandle", Y36_HandleAlready, "@16@0:8");
        ADD(c, "initWithQueue:completionHandler:", Y36_HandleInit, "@32@0:8@16@?24");
        ADD(c, "completeRequestWithResponse:", Y36_HandleComplete, "v24@0:8Q16");
        ADD(c, "cancel", Y36_HandleCancel, "v16@0:8");
    });
    gY36PDCPresenter = Y36_NewClass("PDCPrivacyAlertPresenter", NULL, ^(Class c, Class m) {
        ADD(m, "sharedPresenter", Y36_PresenterShared, "@16@0:8");
        ADD(c, "init", Y36_PresenterInit, "@16@0:8");
        ADD(c, "activateRemoteAlertWithIdentity:requestHandle:forcePresent:completionHandler:", Y36_PresenterActivate, "v44@0:8@16@24B32@?36");
        ADD(c, "didCancelRequestHandle:", Y36_PresenterCancel, "v24@0:8@16");
    });
    gY36PDCManager = Y36_NewClass("PDCPreflightManager", NULL, ^(Class c, Class m) {
        ADD(m, "isPreflightFeatureEnabled", Y36_ManagerFeature, "B16@0:8");
        ADD(c, "initWithTargetQueue:", Y36_ManagerInit, "@24@0:8@16");
        ADD(c, "initWithTargetQueue:consentStore:", Y36_ManagerInitStore, "@32@0:8@16@24");
        ADD(c, "queue", Y36_ManagerQueue, "@16@0:8");
        ADD(c, "setQueue:", Y36_ManagerSetQueue, "v24@0:8@16");
        ADD(c, "consentStore", Y36_ManagerStore, "@16@0:8");
        ADD(c, "setConsentStore:", Y36_ManagerSetStore, "v24@0:8@16");
        ADD(c, "requiresPreflightForApplicationRecord:", Y36_ManagerReqRecordPub, "B24@0:8@16");
        ADD(c, "_requiresPreflightForApplicationRecord:", Y36_ManagerReqRecord, "B24@0:8@16");
        ADD(c, "requiresPreflightForApplication:", Y36_ManagerReqAppPub, "B24@0:8@16");
        ADD(c, "_requiresPreflightForApplication:", Y36_ManagerReqApp, "B24@0:8@16");
        ADD(c, "preflightLaunchForApplication:withCompletionHandler:", Y36_ManagerPreflightPub, "@32@0:8@16@?24");
        ADD(c, "_preflightLaunchForApplication:withCompletionHandler:", Y36_ManagerPreflight, "@32@0:8@16@?24");
    });
    gY36SBAppCtl = Y36_NewClass("SBApplicationPrivacyPreflightController", "BSDescriptionStreamable", ^(Class c, Class m) {
        ADD(c, "initWithPreflightManager:applicationIdentity:", Y36_AppCtlInit, "@32@0:8@16@24");
        ADD(c, "addPendingCompletion:forSceneIdentifier:", Y36_AppCtlAdd, "v32@0:8@?16@24");
        ADD(c, "notePreflightFinishedWithResult:", Y36_AppCtlNotePub, "v24@0:8Q16");
        ADD(c, "_notePreflightFinishedWithResult:cancelToken:", Y36_AppCtlNote, "v32@0:8Q16@24");
        ADD(c, "description", Y36_DescObj, "@16@0:8");
    });
    gY36SBCtl = Y36_NewClass("SBPrivacyPreflightController", "BSDescriptionStreamable", ^(Class c, Class m) {
        ADD(c, "init", Y36_CtlInit, "@16@0:8");
        ADD(c, "requiresPreflightForApplication:", Y36_CtlRequires, "B24@0:8@16");
        ADD(c, "preflightLaunchForApplication:sceneIdentifier:withCompletionHandler:", Y36_CtlPreflight, "v40@0:8@16@24@?32");
        ADD(c, "description", Y36_DescObj, "@16@0:8");
    });
}

// ------------------------------------------------------------------------------------------------ SBApplicationSceneUpdateTransaction
static BOOL Y36_Requires(id txn) { return [Y36_GET(txn, kY36Req) boolValue]; }
static id Y36_Delegate(id txn) { Y36Weak *w = Y36_GET(txn, kY36Delegate); return w ? w->obj : nil; }
static void Y36_SetDelegate(id txn, id d) {
    Y36Weak *w = [Y36Weak new]; w->obj = d;
    Y36_SET(txn, kY36Delegate, w);
}
// 16.2 0x1c78fdf4c, the part that the 16.0 body (which this wraps) does not do: identity, controller, requiresPreflight
static Y36_NEWRET id Y36_SceneInit(Y36_CONSUMED id self, SEL _cmd, id entity, id request) {
    id me = ((Y36_NEWRET id (*)(Y36_CONSUMED id, SEL, id, id))gY36OrigSceneInit)(self, _cmd, entity, request);
    if (!me || !Y36_On()) return me;
    id identity = BPX_Obj0(BPX_Obj0(BPX_Obj0(entity, "application"), "info"), "applicationIdentity");
    if (!identity) { BP_Anomaly("y36-scene", @"failed to find LSApplicationIdentity for scene entity %@ (16.2 asserts, line 95)", entity); return me; }
    id ctl = Y36_Ctl();
    BOOL foreground = BPX_Bool0(BPX_Obj0(BPX_IvarObj(me, "_sceneParameters"), "settings"), "isForeground");
    BOOL req = foreground ? Y36_BoolArg(ctl, "requiresPreflightForApplication:", identity) : NO;
    Y36_SET(me, kY36Ident, identity);
    Y36_SET(me, kY36Ctl, ctl);
    Y36_SET(me, kY36Req, @(req));
    if (req) BP_Log(@"[y36] scene update of %@ requires preflight", BPX_Obj0(BPX_Obj0(entity, "application"), "bundleIdentifier"));
    return me;
}
static Y36_NEWRET id Y36_SceneInitDelegate(Y36_CONSUMED id self, SEL _cmd, id entity, id request, id delegate) {      // 0x1c78fdf4c (the 16.0 init is the designated one here)
    id me = Y36_INIT(id, id)(self, sel_registerName("initWithApplicationSceneEntity:transitionRequest:"), entity, request);
    if (me) Y36_SetDelegate(me, delegate);
    return me;
}
static BOOL Y36_IsReadyToLaunch(id self, SEL _cmd) { return !Y36_Requires(self); }                                        // 0x1c78fea60
static id Y36_CreateAfterPreflight(id self, SEL _cmd) {                                                                   // 0x1c78fef68
    id request = BPX_IvarObj(self, "_request");
    id entity = BPX_IvarObj(self, "_applicationSceneEntity");
    id ctx = BPX_IvarObj(self, "_transitionContext");
    id workspace = BPX_Obj0(request, "workspace");
    id cfg = BPX_Obj0(request, "displayConfiguration");
    id fresh = ((id (*)(id, SEL, unsigned long long, id))objc_msgSend)(workspace, sel_registerName("createRequestWithOptions:displayConfiguration:"), 0ULL, cfg);
    Class mainReq = NSClassFromString(@"SBMainWorkspaceTransitionRequest");
    if (mainReq && [fresh isKindOfClass:mainReq] && [request isKindOfClass:mainReq]) {
        long long src = BPX_LL0(request, "source");
        ((void (*)(id, SEL, long long))objc_msgSend)(fresh, sel_registerName("setSource:"), src);
    }
    BPX_SetObj1(fresh, "setEventLabel:", @"AfterPreflightSceneUpdateTransaction");
    BPX_SetObj1(fresh, "setApplicationContext:", ctx);
    BPX_Obj0(fresh, "finalize");
    id txn = Y36_INIT(id, id)([object_getClass(self) alloc], sel_registerName("initWithApplicationSceneEntity:transitionRequest:"), entity, fresh);
    return txn;
}
static void Y36_SuperVoid(id self, SEL _cmd) {                       // [super <_cmd>] of the class that owns the 16.0 hook (FBApplicationUpdateScenesTransaction)
    Class sup = class_getSuperclass(NSClassFromString(@"SBApplicationSceneUpdateTransaction"));
    IMP imp = sup ? method_getImplementation(class_getInstanceMethod(sup, _cmd)) : NULL;
    if (imp) ((void (*)(id, SEL))imp)(self, _cmd);
}
static void Y36_SceneWillBegin(id self, SEL _cmd) {                                                                       // 0x1c78fe4a8
    if (!Y36_Requires(self)) { if (gY36OrigWillBegin) ((void (*)(id, SEL))gY36OrigWillBegin)(self, _cmd); return; }
    Y36_SuperVoid(self, _cmd);
    id identity = Y36_GET(self, kY36Ident), ctl = Y36_GET(self, kY36Ctl);
    NSString *sceneID = BPX_IvarObj(self, "_sceneIdentifier");
    if (Y36_AuditOn(self)) Y36_AuditAdd(self, [NSString stringWithFormat:@"running preflight for %@", sceneID]);
    __weak id wself = self;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(ctl, sel_registerName("preflightLaunchForApplication:sceneIdentifier:withCompletionHandler:"), identity, sceneID, ^(unsigned long long result, BOOL isLast) {
        id txn = wself;
        if (Y36_AuditOn(txn)) Y36_AuditAdd(txn, @"after-preflight update completed");
        if (!txn) return;
        id delegate = Y36_Delegate(txn);
        if (!isLast) {                                                                // not the last registered completion: report (result == 1)
            Y36_Finished(delegate, txn, result == 1);
            return;
        }
        if (result == 0) {                                                            // refused: destroy the entity, report NO
            typedef void (*DestroyFn)(id);
            DestroyFn destroy = (DestroyFn)dlsym(RTLD_DEFAULT, "SBWorkspaceDestroyApplicationEntity");
            if (destroy) destroy(BPX_IvarObj(txn, "_applicationSceneEntity"));
            else BP_Anomaly("y36-destroy", @"_SBWorkspaceDestroyApplicationEntity (SpringBoard 16.0 0x1c5efb30c) not found: the declined entity is not destroyed");
            Y36_Finished(delegate, txn, NO);
        } else if (result == 1) {                                                     // consented: run the scene update again
            id next = ((id (*)(id, SEL))objc_msgSend)(txn, sel_registerName("_createUpdateTransactionForPreflightCompletion"));
            id keepDelegate = delegate;
            __weak id wtxn = txn;
            void (^done)(BOOL) = ^(BOOL success) {
                id d = keepDelegate;
                if (d) { Y36_Finished(d, wtxn, success); return; }
                if (!success) {
                    id t = wtxn;
                    if (Y36_AuditOn(t)) Y36_AuditAdd(t, [NSString stringWithFormat:@"after-preflight update failed: %@", BPX_Obj0(next, "error")]);
                }
            };
            ((void (*)(id, SEL, id))objc_msgSend)(next, sel_registerName("setCompletionBlock:"), done);
            if (Y36_AuditOn(txn)) Y36_AuditAdd(txn, @"running after-preflight update");
            BPX_Obj0(next, "begin");
        } else if (result == 2) {
            Y36_Finished(delegate, txn, NO);
        }
    });
}
static void Y36_SceneDidComplete(id self, SEL _cmd) {                                                                      // 0x1c72baf2c
    if (gY36OrigDidComplete) ((void (*)(id, SEL))gY36OrigDidComplete)(self, _cmd);
    if (Y36_Requires(self)) return;
    id d = Y36_Delegate(self);
    if (d) Y36_Finished(d, self, !BPX_Bool0(self, "isFailed"));
}
static id Y36_SceneDesc(id self, SEL _cmd) {                                                                               // 0x1c78feae0: "Requires Preflight" after "Application"
    id r = gY36OrigDesc ? ((id (*)(id, SEL))gY36OrigDesc)(self, _cmd) : nil;
    if (r && Y36_On() && [r isKindOfClass:[NSMutableDictionary class]]) ((NSMutableDictionary *)r)[@"Requires Preflight"] = Y36_Requires(self) ? @"YES" : @"NO";
    return r;
}

// ------------------------------------------------------------------------------------------------ SBAppViewController (delegate of the transaction) and its chain
static id Y36_AppVCCreate(id self, SEL _cmd, id entity, BOOL actions) {                                                    // 0x1c732b5f8: initWith...:delegate:self
    id txn = ((id (*)(id, SEL, id, BOOL))gY36OrigAppVCCreate)(self, _cmd, entity, actions);
    if (txn && Y36_On()) Y36_SetDelegate(txn, self);
    return txn;
}
static void Y36_AppVCFinished(id self, SEL _cmd, id txn, BOOL update) {                                                   // 0x1c781b468
    if (update) return;
    id d = BPX_Obj0(self, "delegate");
    SEL s = sel_registerName("appViewControllerDidFailToActivateApplication:");
    if (d && [d respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(d, s, self);
}
static void Y36_DashHostedFailed(id self, SEL _cmd, id vc) {                                                               // 0x1c77a557c
    id d = BPX_Obj0(self, "delegate");
    SEL s = sel_registerName("dashBoardHostedAppViewControllerDidFailToActivateApplication:");
    if (d && [d respondsToSelector:s]) ((void (*)(id, SEL, id))objc_msgSend)(d, s, self);
}
static void Y36_CameraFailed(id self, SEL _cmd, id vc) { BPX_Obj0(self, "dismiss"); }                                     // 0x1c740eb04

// ------------------------------------------------------------------------------------------------ SBToAppsWorkspaceTransaction -_willBegin
static void Y36_ToAppsWillBegin(id self, SEL _cmd) {                                                                       // 16.2 0x1c729b83c
    if (!Y36_On()) { if (gY36OrigToAppsWillBegin) ((void (*)(id, SEL))gY36OrigToAppsWillBegin)(self, _cmd); return; }
    id request = BPX_Obj0(self, "transitionRequest");
    id appCtx = BPX_Obj0(request, "applicationContext");
    id ctl = Y36_Ctl();
    for (id entity in BP_AsArray(BPX_Obj0(self, "toApplicationSceneEntities"))) {
        id app = BPX_Obj0(entity, "application");
        BOOL requires = Y36_BoolArg(ctl, "requiresPreflightForApplication:", BPX_Obj0(BPX_Obj0(app, "info"), "applicationIdentity"));
        id state = BPX_Obj0(app, "processState");
        if (!state && !requires) {
            id handle = BPX_Obj0(entity, "sceneHandle");
            id ctxExec = ((id (*)(id, SEL, id, id))objc_msgSend)(handle, sel_registerName("_createProcessExecutionContextFromContext:entity:"), appCtx, entity);
            if (!ctxExec) continue;
            id display = BPX_Obj0(request, "displayConfiguration");
            ((id (*)(id, SEL, id))objc_msgSend)(app, sel_registerName("_prepareInitializationContextIfNecessaryForLaunchOnDisplayConfiguration:"), display);
            id pm = BPX_Obj0((id)NSClassFromString(@"FBProcessManager"), "sharedInstance");
            ((id (*)(id, SEL, id))objc_msgSend)(pm, sel_registerName("launchProcessWithContext:"), ctxExec);
        } else if (requires && Y36_AuditOn(self)) {
            Y36_AuditAdd(self, [NSString stringWithFormat:@"%@ requires preflight. Skipping prelaunch.", BPX_Obj0(app, "bundleIdentifier")]);
        }
    }
    // [super _willBegin]
    Class sup = class_getSuperclass(NSClassFromString(@"SBToAppsWorkspaceTransaction"));
    IMP simp = sup ? method_getImplementation(class_getInstanceMethod(sup, _cmd)) : NULL;
    if (simp) ((void (*)(id, SEL))simp)(self, _cmd);
    id ws = BPX_Obj0(BPX_Obj0(self, "transitionRequest"), "workspace");
    if (BPX_Bool0(self, "isGoingToLauncher") && !BPX_Bool0(BPX_Obj0(ws, "transientOverlayPresentationManager"), "hasActivePresentation")) {
        Ivar iv = BP_IvarLookup(object_getClass(self), "_gestureInitiated");
        BOOL gesture = iv ? *(BOOL *)((char *)(__bridge void *)self + ivar_getOffset(iv)) : NO;
        if (!gesture) {
            id wc = BPX_Obj0((id)NSClassFromString(@"SBWallpaperController"), "sharedInstance");
            ((void (*)(id, SEL, long long))objc_msgSend)(wc, sel_registerName("activateOrientationSource:"), 2LL);
        }
        void *p = dlsym(RTLD_DEFAULT, "SBHomescreenIconsWillAppearNotification");
        NSString *name = p ? *(__unsafe_unretained NSString *const *)p : nil;
        if (name) [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:nil];
        else BP_Anomaly("y36-toapps", @"SBHomescreenIconsWillAppearNotification not found: not posted");
    }
}

// ------------------------------------------------------------------------------------------------ contingency plan (preflight leg of the removal rule)
static id Y36_Plan(id self, SEL _cmd, id layoutContext, id failed) {
    id ctx = gY36OrigPlan ? ((id (*)(id, SEL, id, id))gY36OrigPlan)(self, _cmd, layoutContext, failed) : nil;
    if (!ctx || !Y36_On() || ![failed isKindOfClass:[NSSet class]]) return ctx;
    Class rc = NSClassFromString(@"SBWorkspaceEntityRemovalContext");
    SEL ini = sel_registerName("initWithAnimationStyle:removalActionType:");
    id ctl = nil;
    for (id e in (NSSet *)failed) {
        if (!BPX_Bool0(e, "isApplicationSceneEntity")) continue;
        id app = BPX_Obj0(e, "application");
        if (BPX_LL0(app, "failedLaunchCount") > 1) continue;                       // >= 2 is the 16.0 rule, already applied by the wrapped body
        ctl = ctl ?: Y36_Ctl();
        if (!Y36_BoolArg(ctl, "requiresPreflightForApplication:", BPX_Obj0(BPX_Obj0(app, "info"), "applicationIdentity"))) continue;
        if (!rc || ![rc instancesRespondToSelector:ini]) continue;
        id rem = Y36_INIT(long long, long long)([rc alloc], ini, 0LL, 1LL);
        Y36_SetObj2(ctx, "setRemovalContext:forEntity:", rem, e);
        BPY_LOG(@"[y36] failed entity %@ requires preflight: removal context set", e);
    }
    return ctx;
}

// ------------------------------------------------------------------------------------------------ FrontBoard : FBApplicationUpdateScenesTransaction
static BOOL Y36_FBOn(void) { return BP_OnName("y36_fblaunch"); }
static void Y36_FBSuper(id self, SEL _cmd) {
    Class sup = class_getSuperclass(NSClassFromString(@"FBApplicationUpdateScenesTransaction"));
    IMP imp = sup ? method_getImplementation(class_getInstanceMethod(sup, _cmd)) : NULL;
    if (imp) ((void (*)(id, SEL))imp)(self, _cmd);
}
static void Y36_FBSuper1(id self, SEL _cmd, id a) {
    Class sup = class_getSuperclass(NSClassFromString(@"FBApplicationUpdateScenesTransaction"));
    IMP imp = sup ? method_getImplementation(class_getInstanceMethod(sup, _cmd)) : NULL;
    if (imp) ((void (*)(id, SEL, id))imp)(self, _cmd, a);
}
static BOOL Y36_FBIsReady(id self, SEL _cmd) { return YES; }                                                              // 0x1a3665488
static void Y36_FBExecuteLaunch(id self, SEL _cmd) {                                                                       // 0x1a3665490
    if ([Y36_GET(self, kY36HasScheduled) boolValue]) return;
    if (!((BOOL (*)(id, SEL))objc_msgSend)(self, sel_registerName("_isReadyToLaunch"))) return;
    Y36_SET(self, kY36HasScheduled, @YES);
    id plt = BPX_IvarObj(self, "_processLaunchTransaction");
    BPX_SetObj1(plt, "addObserver:", self);
    BPX_SetObj1(self, "addChildTransaction:", plt);
}
static void Y36_FBWillBegin(id self, SEL _cmd) { Y36_FBSuper(self, _cmd); Y36_FBExecuteLaunch(self, NULL); }      // not tied to the switch: a transaction built without the launch child must still schedule it
static void Y36_FBChildDone(id self, SEL _cmd, id c) { Y36_FBSuper1(self, _cmd, c); Y36_FBExecuteLaunch(self, NULL); }
static void Y36_FBChildWork(id self, SEL _cmd, id c) { Y36_FBSuper1(self, _cmd, c); Y36_FBExecuteLaunch(self, NULL); }
static void Y36_FBMilestone(id self, SEL _cmd, id c) { Y36_FBSuper1(self, _cmd, c); Y36_FBExecuteLaunch(self, NULL); }
// 16.2 0x1a363a504 initWithClientIdentity:executionContextProvider: : the 16.0 init (0x1a3022820) without the addObserver: / addChildTransaction: of the launch transaction
static Y36_NEWRET id Y36_FBInit(Y36_CONSUMED id self, SEL _cmd, id identity, id provider) {
    Class cls = NSClassFromString(@"FBApplicationUpdateScenesTransaction");
    Ivar ivId = BP_IvarLookup(cls, "_clientIdentity"), ivWaits = BP_IvarLookup(cls, "_waitsForSceneCommits"), ivUpd = BP_IvarLookup(cls, "_updateSceneTransactions"),
         ivPend = BP_IvarLookup(cls, "_pendingUpdateTransactions"), ivPlt = BP_IvarLookup(cls, "_processLaunchTransaction");
    Class pltClass = NSClassFromString(@"FBApplicationProcessLaunchTransaction"), ctxClass = NSClassFromString(@"FBProcessExecutionContext");
    if (!Y36_FBOn() || !identity || !ivId || !ivWaits || !ivUpd || !ivPend || !ivPlt || !pltClass || !ctxClass) {
        if (Y36_FBOn()) BP_Anomaly("y36-fb", @"FBApplicationUpdateScenesTransaction init: identity %@ / ivars / classes missing: the 16.0 init (launch child added at init) runs", identity);
        id me = ((Y36_NEWRET id (*)(Y36_CONSUMED id, SEL, id, id))gY36OrigFBInit)(self, _cmd, identity, provider);
        if (me) Y36_SET(me, kY36HasScheduled, @YES);                      // the 16.0 init added the launch child itself
        return me;
    }
    struct objc_super sup = { self, class_getSuperclass(cls) };
    id me = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, sel_registerName("init"));
    if (!me) return nil;
    BP_SetObjIvar(me, ivId, [identity copy]);
    *(BOOL *)((char *)(__bridge void *)me + ivar_getOffset(ivWaits)) = YES;
    BP_SetObjIvar(me, ivUpd, [NSMutableArray new]);
    BP_SetObjIvar(me, ivPend, [NSMutableArray new]);
    id procIdentity = BPX_Obj0(identity, "processIdentity");
    if (!procIdentity && BPX_Bool0(identity, "isLocal")) procIdentity = BPX_Obj0((id)NSClassFromString(@"RBSProcessIdentity"), "identityOfCurrentProcess");
    __weak id wme = me;
    id (^provided)(void) = provider;
    id (^blk)(void) = ^id{                                                  // 0x1a3664f8c (identical to the 16.0 block 0x1a304d2f0)
        id strongMe = wme;
        id pend = strongMe ? BPX_IvarObj(strongMe, "_pendingUpdateTransactions") : nil;
        id ctx = provided ? provided() : nil;
        if (!ctx) ctx = Y36_INIT(id)([ctxClass alloc], sel_registerName("initWithIdentity:"), procIdentity);
        id settings = BPX_Obj0(BPX_Obj0(pend, "firstObject"), "settings");
        id out = ((Y36_NEWRET id (*)(id, SEL, id))objc_msgSend)(ctx, sel_registerName("copyOrUpdateForSceneActivationWithSettings:"), settings);       // copy family: +1, handed on as the result
        return out;
    };
    id plt = Y36_INIT(id, id)([pltClass alloc], sel_registerName("initWithProcessIdentity:executionContextProvider:"), procIdentity, blk);
    BP_SetObjIvar(me, ivPlt, plt);
    return me;                                                              // NOT added as a child here: -_executeProcessLaunchIfAppropriate does that at -_willBegin
}

// ------------------------------------------------------------------------------------------------ setup
__attribute__((constructor)) static void Y36_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Y36_BuildClasses();
        // SpringBoard -privacyPreflightController
        Class sb = NSClassFromString(@"SpringBoard");
        if (sb && gY36SBCtl && !class_getInstanceMethod(sb, sel_registerName("privacyPreflightController"))) {
            ADD(sb, "privacyPreflightController", Y36_SpringBoardCtl, "@16@0:8"); n++;
        } else if (sb && class_getInstanceMethod(sb, sel_registerName("privacyPreflightController"))) BP_Anomaly("y36-install", @"[y36] SpringBoard already has privacyPreflightController: not added");
        // SBApplicationSceneUpdateTransaction
        Class st = NSClassFromString(@"SBApplicationSceneUpdateTransaction");
        if (st && class_getInstanceMethod(st, sel_registerName("_willBegin")) && class_getInstanceMethod(st, sel_registerName("_didComplete")) &&
            class_getInstanceMethod(st, sel_registerName("initWithApplicationSceneEntity:transitionRequest:")) && gY36SBCtl) {
            gY36OrigSceneInit = BPX_Replace(st, "initWithApplicationSceneEntity:transitionRequest:", (IMP)Y36_SceneInit);
            gY36OrigWillBegin = BPX_Replace(st, "_willBegin", (IMP)Y36_SceneWillBegin);
            gY36OrigDidComplete = BPX_Replace(st, "_didComplete", (IMP)Y36_SceneDidComplete);
            gY36OrigDesc = BPX_Replace(st, "_customizedDescriptionProperties", (IMP)Y36_SceneDesc);
            ADD(st, "initWithApplicationSceneEntity:transitionRequest:delegate:", Y36_SceneInitDelegate, "@40@0:8@16@24@32");
            ADD(st, "_isReadyToLaunch", Y36_IsReadyToLaunch, "B16@0:8");
            ADD(st, "_createUpdateTransactionForPreflightCompletion", Y36_CreateAfterPreflight, "@16@0:8");
            n++;
        } else BP_Anomaly("y36-install", @"[y36] SBApplicationSceneUpdateTransaction selectors missing: preflight not installed");
        // SBAppViewController chain
        Class av = NSClassFromString(@"SBAppViewController");
        if (av && class_getInstanceMethod(av, sel_registerName("_createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:"))) {
            gY36OrigAppVCCreate = BPX_Replace(av, "_createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:", (IMP)Y36_AppVCCreate);
            ADD(av, "sceneUpdateTransaction:finishedApplyingUpdate:", Y36_AppVCFinished, "v28@0:8@16B24"); n++;
        } else BP_Anomaly("y36-install", @"[y36] SBAppViewController _createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions: missing: delegate not wired");
        Class dh = NSClassFromString(@"SBDashBoardHostedAppViewController");
        if (dh) ADD(dh, "appViewControllerDidFailToActivateApplication:", Y36_DashHostedFailed, "v24@0:8@16");
        Class cam = NSClassFromString(@"SBDashBoardCameraPageViewController");
        if (cam) ADD(cam, "dashBoardHostedAppViewControllerDidFailToActivateApplication:", Y36_CameraFailed, "v24@0:8@16");
        // SBToAppsWorkspaceTransaction
        Class ta = NSClassFromString(@"SBToAppsWorkspaceTransaction");
        if (ta && class_getInstanceMethod(ta, sel_registerName("_willBegin")) && gY36SBCtl) { gY36OrigToAppsWillBegin = BPX_Replace(ta, "_willBegin", (IMP)Y36_ToAppsWillBegin); n++; }
        else BP_Anomaly("y36-install", @"[y36] SBToAppsWorkspaceTransaction _willBegin missing: not installed");
        // contingency plan (hooked after Y16's wrapper: both chain)
        Class pl = NSClassFromString(@"SBMainWorkspaceLayoutStateContingencyPlan");
        if (pl && class_getInstanceMethod(pl, sel_registerName("transitionContextForLayoutContext:failedEntities:"))) { gY36OrigPlan = BPX_Replace(pl, "transitionContextForLayoutContext:failedEntities:", (IMP)Y36_Plan); n++; }
        else BP_Anomaly("y36-install", @"[y36] SBMainWorkspaceLayoutStateContingencyPlan transitionContextForLayoutContext:failedEntities: missing: preflight leg not installed");
        // FrontBoard
        Class fb = NSClassFromString(@"FBApplicationUpdateScenesTransaction");
        if (fb && class_getInstanceMethod(fb, sel_registerName("initWithClientIdentity:executionContextProvider:"))) {
            gY36OrigFBInit = BPX_Replace(fb, "initWithClientIdentity:executionContextProvider:", (IMP)Y36_FBInit);
            ADD(fb, "_isReadyToLaunch", Y36_FBIsReady, "B16@0:8");
            ADD(fb, "_executeProcessLaunchIfAppropriate", Y36_FBExecuteLaunch, "v16@0:8");
            ADD(fb, "_willBegin", Y36_FBWillBegin, "v16@0:8");
            ADD(fb, "_childTransactionDidComplete:", Y36_FBChildDone, "v24@0:8@16");
            ADD(fb, "_childTransactionDidFinishWork:", Y36_FBChildWork, "v24@0:8@16");
            ADD(fb, "_didSatisfyMilestone:", Y36_FBMilestone, "v24@0:8@16"); n++;
        } else BP_Anomaly("y36-install", @"[y36] FBApplicationUpdateScenesTransaction initWithClientIdentity:executionContextProvider: missing: launch scheduling not installed");
        BP_Log(@"[y36] installed %d group(s) (switches y36_preflight, y36_fblaunch)", n);
    }
}
#pragma clang diagnostic pop
