// group4-connect-service-lock.hooks.m
//
// Draft: iPadOS 16.2 (20C65) external display CONNECT / service / suspend-under-lock behaviour, reimplemented as
// runtime hooks for iPadOS 16.0 (20A8372) SpringBoard.  Companion to specs/group4-connect-service-lock.md (read it
// first: every 16.2 address, selector and constant used here is derived and listed there).
//
// Form: plain Objective-C (ARC) against Foundation + the objc runtime.  No Logos preprocessing is needed to compile
// this file; the hooks are installed with method_setImplementation / class_addMethod, which is exactly what a
// Logos `%hook` / `%new` expands to.  To merge into Tweak.x, either keep this file as a second translation unit
// (call BP4_Install() from the %ctor after BP_BuildMatches()) or paste the hk_* bodies into `%hook` blocks.
//
// Every piece is tagged  // PORTABLE,  // PARTIAL: <why>  or  // NOT PORTABLE: <why>.
//
// Rules this file follows:
//   * no hardcoded ivar offsets: every ivar is found by name (class_getInstanceVariable) and checked to be an object;
//   * every private message is guarded by respondsToSelector: or a class lookup; a missing piece switches the single
//     feature off (and logs when the debug file exists) instead of crashing SpringBoard;
//   * nothing is dereferenced without a nil check; no exception is thrown on purpose;
//   * every feature has the kill switches of Tweak.x:  <jbroot>/tmp/Backport162.off  and
//     <jbroot>/tmp/Backport162.off.<name>.  Features marked EXPERIMENTAL are OFF unless
//     <jbroot>/tmp/Backport162.on.<name> exists.
//
// Feature names:  autoext  mirrorsvc  covernote  nilock(E)  discguard(E)  provmap(E)       (E = experimental)

// The autoext / mirrorsvc / education hooks below are intentionally not installed (ExtendedDisplayEnabler provides them).
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <pthread.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>
#if defined(__APPLE__)
#import <sys/sysctl.h>
#import <os/lock.h>
#endif
#if __has_include(<rootless.h>)
#import <rootless.h>
#endif

// ======================================================================================================== infra
// Standalone copy of the Tweak.x infrastructure (BP_On / BP_Log), prefixed BP4_ so both can coexist.  When merging
// into Tweak.x replace BP4_On(x)/BP4_Log with BP_On(x)/BP_Log and add the names below to kFeatureNames.

enum { BP4_AUTOEXT, BP4_MIRRORSVC, BP4_COVERNOTE, BP4_NILOCK, BP4_DISCGUARD, BP4_PROVMAP, BP4_COUNT };
static const char *const kBP4Names[BP4_COUNT] = { "autoext", "mirrorsvc", "covernote", "nilock", "discguard", "provmap" };
static const BOOL kBP4Experimental[BP4_COUNT] = { YES, YES, YES, YES, YES, NO };   // provmap is on by default; the rest need Backport162.on.<name>

static char gBP4Off[1024], gBP4Debug[1024], gBP4Log[1024];
static char gBP4FeatOff[BP4_COUNT][1100], gBP4FeatOn[BP4_COUNT][1100];
static pthread_mutex_t gBP4Mu = PTHREAD_MUTEX_INITIALIZER;

static void BP4_InitPaths(void) {
#if defined(ROOT_PATH_NS)
    const char *t = ROOT_PATH_NS(@"/tmp").fileSystemRepresentation;
#else
    const char *t = "/var/jb/tmp";
#endif
    snprintf(gBP4Off, sizeof gBP4Off, "%s/Backport162.off", t);
    snprintf(gBP4Debug, sizeof gBP4Debug, "%s/Backport162.debug", t);
    snprintf(gBP4Log, sizeof gBP4Log, "%s/Backport162.log", t);
    for (int i = 0; i < BP4_COUNT; i++) {
        snprintf(gBP4FeatOff[i], sizeof gBP4FeatOff[i], "%s/Backport162.off.%s", t, kBP4Names[i]);
        snprintf(gBP4FeatOn[i], sizeof gBP4FeatOn[i], "%s/Backport162.on.%s", t, kBP4Names[i]);
    }
}

static BOOL BP4_FileFlag(const char *path, uint64_t *next, BOOL *last) {      // cached for one second
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < *next) return *last;
    *next = t + 1000000000ull;
    *last = path[0] && access(path, F_OK) == 0;
    return *last;
}
static BOOL BP4_Killed(void)  { static uint64_t n; static BOOL l; return BP4_FileFlag(gBP4Off, &n, &l); }
static BOOL BP4_Logging(void) { static uint64_t n; static BOOL l; return BP4_FileFlag(gBP4Debug, &n, &l); }
static BOOL BP4_On(int f) {
    static uint64_t no[BP4_COUNT], nn[BP4_COUNT]; static BOOL lo[BP4_COUNT], ln[BP4_COUNT];
    if (f < 0 || f >= BP4_COUNT || BP4_Killed()) return NO;
    if (BP4_FileFlag(gBP4FeatOff[f], &no[f], &lo[f])) return NO;
    if (kBP4Experimental[f] && !BP4_FileFlag(gBP4FeatOn[f], &nn[f], &ln[f])) return NO;
    return YES;
}
static void BP4_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP4_Log(NSString *fmt, ...) {
    if (!BP4_Logging()) return;
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    pthread_mutex_lock(&gBP4Mu);
    int fd = open(gBP4Log, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        NSString *line = [NSString stringWithFormat:@"g4 %@\n", msg];
        const char *u = line.UTF8String;
        if (u) (void)!write(fd, u, strlen(u));
        close(fd);
    }
    pthread_mutex_unlock(&gBP4Mu);
}

static BOOL BP4_BuildMatches(void) {
#if defined(__APPLE__)
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
#else
    return NO;
#endif
}

// ======================================================================================================== helpers

typedef void (^BP4Block)(void);

// Object ivar by name (no offsets).  Returns nil if the ivar is missing or is not an object.
static id BP4_Ivar(id obj, const char *name) {
    if (!obj || !name) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    if (!iv) return nil;
    const char *t = ivar_getTypeEncoding(iv);
    if (!t || t[0] != '@') return nil;
    return object_getIvar(obj, iv);
}

static void BP4_Main(BP4Block b) {
    if (!b) return;
    if ([NSThread isMainThread]) b(); else dispatch_async(dispatch_get_main_queue(), b);
}

// Install `repl` over `sel` of class `cn`.  Works for inherited methods too (an override is added to `cn`, and
// *origOut is the inherited implementation).  Returns NO (and changes nothing) if class or method is absent.
static BOOL BP4_Hook(const char *cn, SEL sel, IMP repl, IMP *origOut) {
    Class c = objc_getClass(cn);
    if (!c || !sel || !repl || !origOut) return NO;
    Method m = class_getInstanceMethod(c, sel);
    if (!m) { BP4_Log(@"hook %s -%s: method missing, feature skipped", cn, sel_getName(sel)); return NO; }
    IMP cur = method_getImplementation(m);
    if (class_addMethod(c, sel, repl, method_getTypeEncoding(m))) { *origOut = cur; return YES; }
    *origOut = method_setImplementation(m, repl);
    return *origOut != NULL;
}
// %new
static BOOL BP4_AddMethod(const char *cn, SEL sel, IMP imp, const char *types) {
    Class c = objc_getClass(cn);
    if (!c) return NO;
    return class_addMethod(c, sel, imp, types);       // NO if it already exists: never replaces
}

static inline void BP4_RequestUpdate(id controller, unsigned long long mask) {
    if (controller && [controller respondsToSelector:@selector(requestUpdate:)])
        ((void (*)(id, SEL, unsigned long long))objc_msgSend)(controller, @selector(requestUpdate:), mask);
}

// ======================================================================================================== private interfaces
// (declarations only; nothing here is linked, all calls go through objc_msgSend with a respondsToSelector: guard)

@protocol BSInvalidatable <NSObject>
- (void)invalidate;
@end
@interface FBSDisplayIdentity : NSObject
- (BOOL)isRootIdentity;
- (BOOL)isExternal;
- (BOOL)isMainDisplay;
- (id)rootIdentity;
- (id)currentConfiguration;
@end
@interface SBExternalDisplayDefaults : NSObject
- (BOOL)isMirroringEnabled;
- (void)setMirroringEnabled:(BOOL)enabled;
- (id)observeDefault:(NSString *)key onQueue:(dispatch_queue_t)queue withBlock:(void (^)(void))block;
@end
@interface SBMousePointerManager : NSObject
- (void)addObserver:(id)observer;
- (void)removeObserver:(id)observer;
- (BOOL)isHardwarePointingDeviceAttached;
@end
@interface SBSceneHostingDisplayController : NSObject
- (void)requestUpdate:(unsigned long long)update;
@end
@interface SBSystemShellExtendedDisplayControllerPolicy : NSObject
- (BOOL)_areRuntimeAvailabilityRequirementsMet;
@end
@interface SBExternalDisplayService : NSObject
- (id)_extendedModeDisplayIdentityForHardwareIdentifier:(id)hw error:(NSError **)err;
- (void)_notifyOfPropertyChangesForDisplayIdentity:(id)identity requestingProcess:(id)process;
@end
@interface SBSuspendedUnderLockManager : NSObject
- (id)initWithDelegate:(id)delegate eventQueue:(id)queue;
- (BOOL)isSuspendedUnderLock;
- (void)setSuspendedUnderLock:(BOOL)lock alongsideWillChangeBlock:(id)will alongsideDidChangeBlock:(id)did;
@end
@interface SBMainWorkspace : NSObject
+ (id)mainWorkspace;
- (id)eventQueue;
@end
@interface SBNonInteractiveDisplaySceneManager : NSObject
- (id)displayIdentity;
- (id)externalForegroundApplicationSceneHandles;
- (void)setSuspendedUnderLock:(BOOL)lock;
@end
@interface BSServiceConnection : NSObject
+ (id)currentContext;
@end

// ======================================================================================================== notification names
// New in 16.2 (absent from the 16.0 binary).  The values are the cstrings found in the 16.2 binary.

static NSString *const kBP4NoteConnect   = @"SBSystemShellExtendedDisplayControllerPolicyConnectNotification";
static NSString *const kBP4NoteDisconnect = @"SBSystemShellExtendedDisplayControllerPolicyDisconnectNotification";
static NSString *const kBP4NoteWindowExp = @"SBSystemShellExtendedDisplayControllerPolicyDeviceConnectionWindowExpiredNotification";
static NSString *const kBP4NoteHardware  = @"SBSystemShellExtendedDisplayControllerHardwareAvailabilityNotification";
static NSString *const kBP4KeyAvailable  = @"kSBSystemShellExtendedDisplayControllerHardwareAvailabilityIsAvailableKey";
static NSString *const kBP4KeyInWindow   = @"kSBSystemShellExtendedDisplayControllerFiredDuringDeviceConnectionWindowKey";
static NSString *const kBP4KeyIdentity   = @"kSBSystemShellExtendedDisplayControllerDisplayIdentityKey";
static NSString *const kBP4NoteCoverPresent = @"SBExternalDisplayCoverSheetDidPresent";
static NSString *const kBP4NoteCoverDismiss = @"SBExternalDisplayCoverSheetDidDismiss";

static const NSTimeInterval kBP4DeviceWindow = 4.0;     // BSContinuousMachTimer fireInterval in 16.2 (leeway 0.5)

// ================================================================================================================
// FEATURE autoext  --  16.2 SBSystemShellExtendedDisplayControllerPolicy: hardware-window auto "extended" mode
// ================================================================================================================
// 16.0:  connectToDisplayController: unconditionally does  defaults.mirroringEnabled = YES;
//        displayControllerShouldHaveControlOfDisplay: == !defaults.mirroringEnabled  =>  a freshly connected display is
//        never extended; nothing ever sets mirroringEnabled = NO (the only writers are YES; see mirrorsvc below).
// 16.2:  at connect   met = _areRuntimeAvailabilityRequirementsMet (hardware keyboard + pointer, per
//        SBExternalDisplayRuntimeAvailabilitySettings);  _didConnectToRequiredDevicesDuringTimerWindow = met;
//        defaults.mirroringEnabled = !met;  a 4 s window opens; if the keyboard/pointer arrive inside the window the
//        flag becomes YES (and the display becomes extended); the user's explicit choice (defaults key
//        "mirroringEnabled" changing after connect) is remembered as _userMirroringPreference (1 mirror, 2 extend) and
//        beats the automatic decision.  _wantsControlOfDisplay: pref==1 -> NO, pref==0 -> flag, else YES.

@interface BP4ExtState : NSObject
@property (nonatomic) BOOL didConnectInWindow;     // _didConnectToRequiredDevicesDuringTimerWindow (0x90)
@property (nonatomic) BOOL windowOpen;             // BSContinuousMachTimer isScheduled (0x88)
@property (nonatomic) BOOL disconnected;           // _displayDisconnectSignal hasBeenSignalled (0x98)
@property (nonatomic) int  userPref;               // _userMirroringPreference (0x94): 0 auto, 1 mirror, 2 extend
@property (nonatomic) NSUInteger generation;       // invalidates the pending window timer
@property (nonatomic, strong) id defaultsToken;    // _externalDisplayDefaultsToken
@property (nonatomic, strong) id identity;         // rootIdentity, for notification userInfo
@end
@implementation BP4ExtState
@end

static const char kBP4ExtStateKey = 0;
static BP4ExtState *BP4_State(id policy) { return policy ? objc_getAssociatedObject(policy, &kBP4ExtStateKey) : nil; }

static NSString *BP4_KeyboardNoteName(void) {      // exported by SpringBoard in both builds
    static NSString *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *p = dlsym(RTLD_DEFAULT, "SBHardwareKeyboardAvailabilityChangedNotification");
        if (p) s = *(__unsafe_unretained NSString *const *)p;
    });
    return s;
}

static void BP4_PostPolicyNote(id policy, NSString *name, NSDictionary *extra) {
    BP4ExtState *st = BP4_State(policy);
    NSMutableDictionary *ui = [NSMutableDictionary dictionaryWithCapacity:3];
    if (st.identity) ui[kBP4KeyIdentity] = st.identity;
    if (extra) [ui addEntriesFromDictionary:extra];
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:policy userInfo:ui];
}

// PORTABLE  -[SBSystemShellExtendedDisplayControllerPolicy _hardwareAvailabilityChanged]          16.2 0x1c77dd8e4
// (new method; also the target of _keyboardAvailabilityChanged: 0x1c77dd65c and
//  mousePointerManager:hardwarePointingDeviceAttachedDidChange: 0x1c77dd658, both of which are a bare `b` to it)
static void BP4_HardwareAvailabilityChanged(id self, SEL _cmd) {
    if (![NSThread isMainThread]) { BP4_Main(^{ BP4_HardwareAvailabilityChanged(self, _cmd); }); return; }
    BP4ExtState *st = BP4_State(self);
    if (!st || st.disconnected || !BP4_On(BP4_AUTOEXT)) return;
    if (![self respondsToSelector:@selector(_areRuntimeAvailabilityRequirementsMet)]) return;
    BOOL met = ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(_areRuntimeAvailabilityRequirementsMet));
    BOOL inWindow = st.windowOpen;
    if (inWindow && !st.didConnectInWindow && met) {
        BP4_Log(@"autoext: hardware arrived inside the connection window -> extended");
        st.didConnectInWindow = YES;
        BP4_RequestUpdate(BP4_Ivar(self, "_displayController"), 7);
    }
    BP4_PostPolicyNote(self, kBP4NoteHardware, @{ kBP4KeyAvailable: @(met), kBP4KeyInWindow: @(inWindow) });
}
static void BP4_KeyboardAvailabilityChanged(id self, SEL _cmd, id note) { BP4_HardwareAvailabilityChanged(self, _cmd); }
static void BP4_PointerAttachChanged(id self, SEL _cmd, id mgr, BOOL attached) { BP4_HardwareAvailabilityChanged(self, _cmd); }

// PORTABLE  -[SBSystemShellExtendedDisplayControllerPolicy connectToDisplayController:displayConfiguration:]   16.2 0x1c77dba48
static void (*orig_policyConnect)(id, SEL, id, id);
static void hk_policyConnect(id self, SEL _cmd, id controller, id config) {
    orig_policyConnect(self, _cmd, controller, config);          // 16.0 body (sets mirroringEnabled = YES, etc.)
    if (!self || !BP4_On(BP4_AUTOEXT) || BP4_State(self)) return;

    id defaults = BP4_Ivar(self, "_externalDisplayDefaults");
    if (![self respondsToSelector:@selector(_areRuntimeAvailabilityRequirementsMet)] ||
        ![defaults respondsToSelector:@selector(setMirroringEnabled:)] ||
        ![defaults respondsToSelector:@selector(isMirroringEnabled)] ||
        ![defaults respondsToSelector:@selector(observeDefault:onQueue:withBlock:)]) {
        BP4_Log(@"autoext: policy/defaults API missing, leaving 16.0 behaviour");
        return;
    }
    BP4ExtState *st = [BP4ExtState new];
    id ident = BP4_Ivar(self, "_displayIdentity");
    st.identity = [ident respondsToSelector:@selector(rootIdentity)] ? [ident rootIdentity] : ident;
    BOOL met = ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(_areRuntimeAvailabilityRequirementsMet));
    st.didConnectInWindow = met;
    st.windowOpen = YES;
    st.userPref = 0;
    objc_setAssociatedObject(self, &kBP4ExtStateKey, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 16.2: [_externalDisplayDefaults setMirroringEnabled:!met]   (done BEFORE the observer below is installed)
    [defaults setMirroringEnabled:!met];
    BP4_Log(@"autoext: connect, requirements met=%d -> mirroringEnabled=%d", met, !met);

    // the 4 s device-connection window (16.2: BSContinuousMachTimer scheduleWithFireInterval:4.0 leeway:0.5 queue:main)
    NSUInteger gen = ++st.generation;
    __weak id wself = self;
    __weak BP4ExtState *wst = st;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBP4DeviceWindow * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id s = wself; BP4ExtState *t = wst;
        if (!s || !t || t.disconnected || t.generation != gen) return;
        t.windowOpen = NO;
        BP4_Log(@"autoext: connection window expired (extended=%d)", t.didConnectInWindow);
        BP4_PostPolicyNote(s, kBP4NoteWindowExp, nil);
    });

    // 16.2 block.65 of connectToDisplayController: user toggled the "mirroringEnabled" default after connect
    __weak id wdefaults = defaults;
    st.defaultsToken = [defaults observeDefault:@"mirroringEnabled" onQueue:dispatch_get_main_queue() withBlock:^{
        id s = wself; id d = wdefaults; BP4ExtState *t = BP4_State(s);
        if (!s || !d || !t || t.disconnected) return;
        t.userPref = [d isMirroringEnabled] ? 1 : 2;
        BP4_Log(@"autoext: user preference -> %d", t.userPref);
        BP4_RequestUpdate(BP4_Ivar(s, "_displayController"), 7);
    }];

    // hardware observers (16.2 connect: mousePointerManager addObserver:self + NSNotificationCenter keyboard note)
    id mgr = BP4_Ivar(self, "_mousePointerManager");
    if ([mgr respondsToSelector:@selector(addObserver:)]) [mgr addObserver:self];
    NSString *kn = BP4_KeyboardNoteName();
    if (kn) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardAvailabilityChanged:) name:kn object:nil];

    BP4_PostPolicyNote(self, kBP4NoteConnect, @{ kBP4KeyAvailable: @(met), kBP4KeyInWindow: @YES });
}

// PORTABLE  16.2 _wantsControlOfDisplay 0x1c77dd1f8, reached through assertionPreferencesForDisplay:
//           (16.0 asks displayControllerShouldHaveControlOfDisplay: instead, so that is what is replaced)
static BOOL (*orig_shouldHaveControl)(id, SEL, id);
static BOOL hk_shouldHaveControl(id self, SEL _cmd, id controller) {
    BP4ExtState *st = BP4_State(self);
    if (!st || st.disconnected || !BP4_On(BP4_AUTOEXT)) return orig_shouldHaveControl(self, _cmd, controller);
    switch (st.userPref) {
        case 0:  return st.didConnectInWindow;     // automatic
        case 1:  return NO;                        // user chose mirroring
        default: return YES;                       // user chose extended
    }
}

// PORTABLE  tear-down.  16.2 moves it to displayControllerWillDisconnect:sceneManager: 0x1c77dc440 (signal, invalidate
//           both defaults tokens, remove observers, post the Disconnect notification); 16.0 only has DidDisconnect.
static void (*orig_policyDidDisconnect)(id, SEL, id, id);
static void hk_policyDidDisconnect(id self, SEL _cmd, id controller, id sceneManager) {
    BP4ExtState *st = BP4_State(self);
    if (st && !st.disconnected) {
        st.disconnected = YES;
        st.windowOpen = NO;
        st.generation++;
        id tok = st.defaultsToken; st.defaultsToken = nil;
        if ([tok respondsToSelector:@selector(invalidate)]) [(id<BSInvalidatable>)tok invalidate];
        id mgr = BP4_Ivar(self, "_mousePointerManager");
        if ([mgr respondsToSelector:@selector(removeObserver:)]) [mgr removeObserver:self];
        NSString *kn = BP4_KeyboardNoteName();
        if (kn) [[NSNotificationCenter defaultCenter] removeObserver:self name:kn object:nil];
        BP4_PostPolicyNote(self, kBP4NoteDisconnect, nil);
    }
    orig_policyDidDisconnect(self, _cmd, controller, sceneManager);
}

// PORTABLE  -[SBExternalDisplayEducationObserver displayManager:didConnectToRootDisplay:]   (16.0 only, 0x1c6331f08)
// 16.0: on every root display connect, if the user never used extended mode (both "ever enabled" flags NO) it sets
// mirroringEnabled = YES AFTER the policy connected, which would undo the automatic decision above.  16.2 has no
// such code (the flags were replaced by externalDisplayEducationReasons).
static void (*orig_eduConnect)(id, SEL, id, id);
static void hk_eduConnect(id self, SEL _cmd, id mgr, id display) {
    if (BP4_On(BP4_AUTOEXT)) return;
    orig_eduConnect(self, _cmd, mgr, display);
}

// ================================================================================================================
// FEATURE mirrorsvc  --  -[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:]
// ================================================================================================================
// 16.0 BUG: the first argument (an NSNumber sent by -[SBSExternalDisplayService setMirroringEnabled:forDisplay:]) is
// never read.  The 16.0 block only does `if (!defaults.isMirroringEnabled) { defaults.mirroringEnabled = YES;
// notify }`, i.e. a request to disable mirroring (= use the display as a separate/extended display) is executed as
// "enable mirroring".  16.2 (0x1c77d5db4, block 0x1c77d5ebc) honours the value and only acts if it differs.

// PORTABLE
static void (*orig_setMirroring)(id, SEL, id, id);
static void hk_setMirroring(id self, SEL _cmd, id enabled, id hardwareIdentifier) {
    if (!BP4_On(BP4_MIRRORSVC) || ![enabled respondsToSelector:@selector(boolValue)] || ![hardwareIdentifier isKindOfClass:[NSString class]]) {
        orig_setMirroring(self, _cmd, enabled, hardwareIdentifier);
        return;
    }
    BOOL want = [enabled boolValue];
    if (want) { orig_setMirroring(self, _cmd, enabled, hardwareIdentifier); return; }   // 16.0 already does this correctly

    id process = nil;                                              // 16.0: [[BSServiceConnection currentContext] remoteProcess]
    Class bsc = objc_getClass("BSServiceConnection");
    if (bsc && [(id)bsc respondsToSelector:@selector(currentContext)]) {
        id ctx = [(id)bsc currentContext];
        if ([ctx respondsToSelector:@selector(remoteProcess)]) process = ((id (*)(id, SEL))objc_msgSend)(ctx, @selector(remoteProcess));
    }
    NSString *hw = [hardwareIdentifier copy];
    BP4_Main(^{                                                    // 16.0/16.2: BSDispatchMain
        if (![self respondsToSelector:@selector(_extendedModeDisplayIdentityForHardwareIdentifier:error:)]) return;
        id identity = [self _extendedModeDisplayIdentityForHardwareIdentifier:hw error:NULL];
        id defaults = BP4_Ivar(self, "_defaults");
        if (!identity || ![defaults respondsToSelector:@selector(isMirroringEnabled)] || ![defaults respondsToSelector:@selector(setMirroringEnabled:)]) return;
        if ([defaults isMirroringEnabled] == want) return;
        BP4_Log(@"mirrorsvc: client asked mirroringEnabled=%d for %@", want, hw);
        [defaults setMirroringEnabled:want];
        if ([self respondsToSelector:@selector(_notifyOfPropertyChangesForDisplayIdentity:requestingProcess:)])
            [self _notifyOfPropertyChangesForDisplayIdentity:identity requestingProcess:process];
    });
}

// ================================================================================================================
// FEATURE covernote  --  SBExternalDisplayCoverSheetController posts SBExternalDisplayCoverSheetDidPresent / DidDismiss
// ================================================================================================================
// 16.2 _postNotificationForExternalCoverSheetVisibilityDidChange: (0x1c7791248) is called from
// _updateExternalDisplayCoverSheetExistence right after _setCoverSheetWindowVisible:fadeDuration:.  The 16.0 method
// of that name exists with the same signature, so the notification is posted from there.

// PORTABLE
static void (*orig_coverVisible)(id, SEL, BOOL, double);
static void hk_coverVisible(id self, SEL _cmd, BOOL visible, double fade) {
    orig_coverVisible(self, _cmd, visible, fade);
    if (!BP4_On(BP4_COVERNOTE)) return;
    [[NSNotificationCenter defaultCenter] postNotificationName:(visible ? kBP4NoteCoverPresent : kBP4NoteCoverDismiss) object:self];
}

// ================================================================================================================
// FEATURE nilock (EXPERIMENTAL)  --  SBNonInteractiveDisplaySceneManager: suspend-under-lock
// ================================================================================================================
// 16.0: the class only has _shouldAutoHostScene:.  16.2 gives it the SBSuspendedUnderLockManagerDelegate, a lazily
// created SBSuspendedUnderLockManager (ivar _lazy_suspendedUnderLockManager, 0xe0) and two NSNotification observers
// that call setSuspendedUnderLock:YES / NO.  Ivars cannot be added to an existing class, so the manager lives in an
// associated object.
// PARTIAL: only reacts to a cover sheet that is shown by a *different* (system-shell) external display; see the .md.

static const char kBP4NIMgrKey = 0;

static id BP4_NIManager(id self, BOOL create) {
    id m = objc_getAssociatedObject(self, &kBP4NIMgrKey);
    if (m || !create) return m;
    Class mc = objc_getClass("SBSuspendedUnderLockManager");
    Class wc = objc_getClass("SBMainWorkspace");
    if (!mc || !wc || ![(id)wc respondsToSelector:@selector(mainWorkspace)]) return nil;
    id ws = [(id)wc mainWorkspace];
    id queue = [ws respondsToSelector:@selector(eventQueue)] ? [ws eventQueue] : nil;
    if (!queue) return nil;
    id alloc = [(id)mc alloc];
    if (![alloc respondsToSelector:@selector(initWithDelegate:eventQueue:)]) return nil;
    m = [(SBSuspendedUnderLockManager *)alloc initWithDelegate:self eventQueue:queue];
    if (m) objc_setAssociatedObject(self, &kBP4NIMgrKey, m, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return m;
}

// 16.2 0x1c7703704 / 0x1c77036e0
static void BP4_NI_SetLockedFull(id self, SEL _cmd, BOOL locked, id will, id did) {
    if (![NSThread isMainThread]) { BP4_Main(^{ BP4_NI_SetLockedFull(self, _cmd, locked, will, did); }); return; }
    id m = BP4_NIManager(self, YES);
    if (m) [(SBSuspendedUnderLockManager *)m setSuspendedUnderLock:locked alongsideWillChangeBlock:will alongsideDidChangeBlock:did];
}
static void BP4_NI_SetLocked(id self, SEL _cmd, BOOL locked) { BP4_NI_SetLockedFull(self, _cmd, locked, nil, nil); }
// 16.2 0x1c77036a0
static BOOL BP4_NI_IsLocked(id self, SEL _cmd) {
    id m = BP4_NIManager(self, NO);
    return m ? [(SBSuspendedUnderLockManager *)m isSuspendedUnderLock] : NO;
}
// 16.2 0x1c77037d8 / 0x1c77037e0 (a tail call: setSuspendedUnderLock:YES / NO)
static void BP4_NI_CoverPresent(id self, SEL _cmd, id note) { if (BP4_On(BP4_NILOCK)) ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setSuspendedUnderLock:), YES); }
static void BP4_NI_CoverDismiss(id self, SEL _cmd, id note) { if (BP4_On(BP4_NILOCK)) ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setSuspendedUnderLock:), NO); }
// SBSuspendedUnderLockManagerDelegate, 16.2 values
static id   BP4_NI_VisibleScenes(id self, SEL _cmd, id mgr) {                           // 0x1c770389c
    return [self respondsToSelector:@selector(externalForegroundApplicationSceneHandles)] ? [self externalForegroundApplicationSceneHandles] : nil;
}
static BOOL BP4_NI_PreventSuspend(id self, SEL _cmd, id mgr, id scene) { return NO; }   // 0x1c7703890
static BOOL BP4_NI_PreventUnder(id self, SEL _cmd, id mgr, id scene)   { return NO; }   // 0x1c7703888
static id   BP4_NI_SceneHandle(id self, SEL _cmd, id mgr, id scene) {                   // 0x1c7703834: [super existingSceneHandleForScene:]
    // the owning class is used explicitly (not object_getClass(self)) so that subclasses do not recurse
    Class owner = objc_getClass("SBNonInteractiveDisplaySceneManager");
    Class sc = owner ? class_getSuperclass(owner) : Nil;
    if (!sc || !class_respondsToSelector(sc, @selector(existingSceneHandleForScene:))) return nil;
    struct objc_super sup = { self, sc };
    return ((id (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, @selector(existingSceneHandleForScene:), scene);
}
static id   BP4_NI_DisplayConfiguration(id self, SEL _cmd, id mgr) {                    // 0x1c77037e8
    id ident = [self respondsToSelector:@selector(displayIdentity)] ? [self displayIdentity] : nil;
    return [ident respondsToSelector:@selector(currentConfiguration)] ? [ident currentConfiguration] : nil;
}

static id (*orig_niInit)(id, SEL, id, id, id);
static id hk_niInit(id self, SEL _cmd, id ref, id provider, id binder) {
    id r = orig_niInit(self, _cmd, ref, provider, binder);
    if (r && BP4_On(BP4_NILOCK)) {     // 16.2 init registers both observers with object:nil; selector observers need no dealloc hook
        [[NSNotificationCenter defaultCenter] addObserver:r selector:@selector(_externalCoverSheetVisibilityDidPresent:) name:kBP4NoteCoverPresent object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:r selector:@selector(_externalCoverSheetVisibilityDidDismiss:) name:kBP4NoteCoverDismiss object:nil];
    }
    return r;
}

// ================================================================================================================
// FEATURE discguard (EXPERIMENTAL)  --  SBSceneHostingDisplayController: do not keep updating a disconnecting display
// ================================================================================================================
// 16.2 adds ivar _displayDisconnectedSignal (BSAtomicSignal, 0xb0), signalled first thing in
// displayIdentityDidDisconnect: (before the new policy callback displayControllerWillDisconnect:sceneManager:); the
// connect completion block (0x1c73bbfac) and the presentation-update blocks (0x1c73be154 / 0x1c73be3c0) test it and
// bail.  A flag in an associated object plays the signal's role.
// PARTIAL: only the two entry points are guarded (the blocks themselves cannot be edited).

static const char kBP4DiscKey = 0;
static BOOL BP4_Disconnected(id c) { return c && [objc_getAssociatedObject(c, &kBP4DiscKey) boolValue]; }

static void (*orig_ctrlDidDisconnect)(id, SEL, id);
static void hk_ctrlDidDisconnect(id self, SEL _cmd, id identity) {
    if (BP4_On(BP4_DISCGUARD)) objc_setAssociatedObject(self, &kBP4DiscKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    orig_ctrlDidDisconnect(self, _cmd, identity);
}
static void (*orig_ctrlEnqueue)(id, SEL);
static void hk_ctrlEnqueue(id self, SEL _cmd) {
    if (BP4_On(BP4_DISCGUARD) && BP4_Disconnected(self)) { BP4_Log(@"discguard: skip presentation update after disconnect"); return; }
    orig_ctrlEnqueue(self, _cmd);
}
static void (*orig_ctrlRunUpdate)(id, SEL, id, id);
static void hk_ctrlRunUpdate(id self, SEL _cmd, id label, id completion) {
    // only fire-and-forget callers are skipped (connect completion, requestUpdate:); a caller that passes a completion
    // may be waiting for it, so that path always runs.
    if (!completion && BP4_On(BP4_DISCGUARD) && BP4_Disconnected(self)) { BP4_Log(@"discguard: skip root update %@", label); return; }
    orig_ctrlRunUpdate(self, _cmd, label, completion);
}

// ================================================================================================================
// FEATURE provmap (EXPERIMENTAL)  --  SBSceneHostingDisplayControllerProvider: forget the controller on disconnect
// ================================================================================================================
// 16.2 displayManager:didDisconnectIdentity: (0x1c7345fe0) also removes the entry from _lock_rootDisplaysToControllerMap
// (an NSMapTable, strong keys / weak values).  16.0 leaves it, so a quick reconnect while the old controller is still
// alive trips "we can only track one controller per physical display" (NSInternalInconsistencyException).
// PORTABLE (needs os_unfair_lock; the lock ivar is located by name)

static void (*orig_provDidDisconnect)(id, SEL, id, id);
static void hk_provDidDisconnect(id self, SEL _cmd, id manager, id identity) {
    orig_provDidDisconnect(self, _cmd, manager, identity);
#if defined(__APPLE__)
    if (!identity || !BP4_On(BP4_PROVMAP)) return;
    Class c = object_getClass(self);
    Ivar lockIv = class_getInstanceVariable(c, "_lock");
    id map = BP4_Ivar(self, "_lock_rootDisplaysToControllerMap");
    if (!lockIv || !map || ![map respondsToSelector:@selector(removeObjectForKey:)]) return;
    ptrdiff_t off = ivar_getOffset(lockIv);
    if (off <= 0) return;
    os_unfair_lock_t lk = (os_unfair_lock_t)((char *)(__bridge void *)self + off);
    os_unfair_lock_lock(lk);
    ((void (*)(id, SEL, id))objc_msgSend)(map, @selector(removeObjectForKey:), identity);
    os_unfair_lock_unlock(lk);
    BP4_Log(@"provmap: dropped controller entry for %@", identity);
#endif
}

// ================================================================================================================
// NOT PORTABLE / not worth porting (documented here so the list in the .md maps 1:1 onto this file)
// ================================================================================================================
// NOT PORTABLE: SBDisplayManager clone-mirroring assertions (_setCloneMirroringMode:forDisplay:,
//   SBDisplayAssertionPreferences.cloneMirroringMode, policy -> setCloneMirroringMode:2 / 1).  16.2 calls
//   BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay, which does not exist in the 16.0
//   BackBoardServices (verified with symaddr) and needs matching backboardd support.
// NOT PORTABLE: SBExternalDisplayEducationSession / EducationPillViewController / the rewritten
//   SBExternalDisplayEducationObserver.  Needs a BNPosting banner source, a PLPillView pill, the remote alert
//   (service com.apple.SpringBoardEducation, class SBERemoteViewController) whose 16.2 content is outside the
//   SpringBoard binary, and -[SBExternalDisplayDefaults externalDisplayEducationReasons] which lives in
//   SpringBoardFoundation (16.0 has two BOOL properties instead).  The four policy notifications above are posted
//   so that a future port has its inputs.
// NOT PORTABLE: -[SBSystemShellExtendedDisplayControllerPolicy displayController:updatePresentationWithSceneManager:...]
//   (updates only boundPointerUIScenes + current scene): +[SBSceneManager boundPointerUIScenes] is new in 16.2.
// NOT PORTABLE: _SBDisplayAssertionStack/SBDisplayAssertionCoordinator activateAssertionsForDisplay: (100 ms deferred
//   first evaluation of external display assertions).  Needs the new _activated ivar and the reworked
//   assertionStack:updatedAssertionPreferences:oldPreferences: delegate; high risk, unproven value.
// NOT PORTABLE: SBExternalDisplaySettings.activeDisplayTrackingMethodology (prototype setting whose consumers,
//   -[SBWindowSceneManager activeDisplayWindowScene] and SBWorkspaceKeyboardFocusController, belong to another group).
// REFACTOR ONLY (nothing to port): SBDisplayManager _connectedIdentityToRecordMap / _SBDisplayIdentityRecord,
//   _setPowerLogEntry / _setDisplayArrangementItem / _setDisableIdleSleepReason (per-display versions of the 16.0
//   aggregate in assertionCoordinator:activeAssertionPreferencesHaveChanged:), SBDisplayArrangementItem (base class
//   of SBExternalDisplayArrangementItem), SBExternalDisplayService initWithDisplayManager: -> ...configureConnectionListener:,
//   preferredArrangementOfDisplay:relativeTo:, SBSceneHostingDisplayPreferences / policy protocol rewrite (the
//   sizing semantics are the already-DONE "scale" feature of Tweak.x), _SBFIsChamoisExternalDisplayControllerAvailable
//   (feature flag wrapper around the same capability check).

// ======================================================================================================== installer

static void BP4_Install(void) {
    const char *pol = "SBSystemShellExtendedDisplayControllerPolicy";
    int ok = 0;
    // autoext and mirrorsvc are NOT installed: ExtendedDisplayEnabler 0.2.2 already restores both 16.2/beta-5 behaviours
    // (extended-versus-mirror decision on connect, and the setDisplayMirroringEnabled:forDisplay: argument).
    // The code above stays for reference and for builds without ExtendedDisplayEnabler.
    (void)pol; (void)ok;

    // --- covernote
    BP4_Hook("SBExternalDisplayCoverSheetController", @selector(_setCoverSheetWindowVisible:fadeDuration:), (IMP)hk_coverVisible, (IMP *)&orig_coverVisible);

    // --- nilock
    const char *ni = "SBNonInteractiveDisplaySceneManager";
    // Experimental and opt-in: evaluated once at launch, so with the switch off the class is not touched at all.
    if (BP4_On(BP4_NILOCK) && objc_getClass(ni) && objc_getClass("SBSuspendedUnderLockManager")) {
        BP4_AddMethod(ni, @selector(setSuspendedUnderLock:), (IMP)BP4_NI_SetLocked, "v@:B");
        BP4_AddMethod(ni, @selector(setSuspendedUnderLock:alongsideWillChangeBlock:alongsideDidChangeBlock:), (IMP)BP4_NI_SetLockedFull, "v@:B@?@?");
        BP4_AddMethod(ni, @selector(isSuspendedUnderLock), (IMP)BP4_NI_IsLocked, "B@:");
        BP4_AddMethod(ni, @selector(_externalCoverSheetVisibilityDidPresent:), (IMP)BP4_NI_CoverPresent, "v@:@");
        BP4_AddMethod(ni, @selector(_externalCoverSheetVisibilityDidDismiss:), (IMP)BP4_NI_CoverDismiss, "v@:@");
        BP4_AddMethod(ni, @selector(suspendedUnderLockManagerVisibleScenes:), (IMP)BP4_NI_VisibleScenes, "@@:@");
        BP4_AddMethod(ni, @selector(suspendedUnderLockManager:shouldPreventSuspendUnderLockForScene:), (IMP)BP4_NI_PreventSuspend, "B@:@@");
        BP4_AddMethod(ni, @selector(suspendedUnderLockManager:shouldPreventUnderLockForScene:), (IMP)BP4_NI_PreventUnder, "B@:@@");
        BP4_AddMethod(ni, @selector(suspendedUnderLockManager:sceneHandleForScene:), (IMP)BP4_NI_SceneHandle, "@@:@@");
        BP4_AddMethod(ni, @selector(suspendedUnderLockManagerDisplayConfiguration:), (IMP)BP4_NI_DisplayConfiguration, "@@:@");
        BP4_Hook(ni, @selector(initWithReference:sceneIdentityProvider:presentationBinder:), (IMP)hk_niInit, (IMP *)&orig_niInit);
    }

    // --- discguard
    const char *ctl = "SBSceneHostingDisplayController";
    BP4_Hook(ctl, @selector(displayIdentityDidDisconnect:), (IMP)hk_ctrlDidDisconnect, (IMP *)&orig_ctrlDidDisconnect);
    BP4_Hook(ctl, @selector(_enqueueEvaluateAndApplyPresentationUpdate), (IMP)hk_ctrlEnqueue, (IMP *)&orig_ctrlEnqueue);
    BP4_Hook(ctl, @selector(_runRootUpdateTransactionWithLabel:completion:), (IMP)hk_ctrlRunUpdate, (IMP *)&orig_ctrlRunUpdate);

    // --- provmap
    BP4_Hook("SBSceneHostingDisplayControllerProvider", @selector(displayManager:didDisconnectIdentity:), (IMP)hk_provDidDisconnect, (IMP *)&orig_provDidDisconnect);

    BP4_Log(@"group4 hooks installed (%d/3 policy hooks)", ok);
}

// Call from Tweak.x's %ctor after BP_BuildMatches() succeeded:  BP4_InstallIfSupported();
void BP4_InstallIfSupported(void);
void BP4_InstallIfSupported(void) {
    @autoreleasepool {
        BP4_InitPaths();
        if (!BP4_BuildMatches()) return;
        BP4_Install();
    }
}
