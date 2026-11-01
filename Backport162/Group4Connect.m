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

// autoext and mirrorsvc are installed from 0.7.0 on (kill switches Backport162.off.autoext / .mirrorsvc).  Since 0.7.5 they are the ONE
// implementation of what ExtendedDisplayEnabler 0.2.2 did on these selectors (that package is merged into this one: EDE.x has its provider
// registration, this file has the rest): the user's saved mirror / extended choice (CFPreferences, migrated from the EDE domain), the
// beta-5 default, the setDisplayMirroringEnabled:forDisplay: fix incl. the "ever enabled" flag.  See specs/EDE-MERGE-0.7.5.md.
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
#import <mach-o/dyld.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
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
static const BOOL kBP4Experimental[BP4_COUNT] = { NO, NO, NO, NO, NO, NO };   // nothing is opt-in: every installed feature is on unless Backport162.off.<name> exists

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

// ======================================================================================================== saved choice
// Ported from ExtendedDisplayEnabler 0.2.2 (EDEPrefGet / EDEPrefSet / EDELoadChoice / EDESaveChoice): the user's last explicit choice,
// "extended" or "mirror", stored by cfprefsd (not a jailbreak file).  It beats the automatic decision on every connect.
// Domain: com.infernowolf19.backport162, key "choice".  First start after the merge: when that key is absent the value of the old
// ExtendedDisplayEnabler domain (com.infernowolf19.extendeddisplayenabler, key "choice") is read and copied over, so the user's setting
// survives; the old domain is left untouched.

static NSString *const kBP4PrefsDomain  = @"com.infernowolf19.backport162";
static NSString *const kBP4LegacyDomain = @"com.infernowolf19.extendeddisplayenabler";
enum { BP4_ChoiceNone = 0, BP4_ChoiceExtended = 1, BP4_ChoiceMirror = 2 };
static int gBP4Choice;                        // BP4_Choice*; written on the main queue (and once from the constructor), read in the connect hook

static id BP4_PrefGet(NSString *domain, NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)domain));
}
static void BP4_PrefSet(NSString *domain, NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
}
static int BP4_ParseChoice(id v) {
    if ([v isKindOfClass:[NSString class]]) {
        if ([v isEqualToString:@"extended"]) return BP4_ChoiceExtended;
        if ([v isEqualToString:@"mirror"]) return BP4_ChoiceMirror;
    }
    return BP4_ChoiceNone;
}
static void BP4_SaveChoice(int choice) {
    NSString *text = choice == BP4_ChoiceExtended ? @"extended" : (choice == BP4_ChoiceMirror ? @"mirror" : nil);
    BP4_PrefSet(kBP4PrefsDomain, @"choice", text);
}
static int BP4_LoadChoice(void) {
    int c = BP4_ParseChoice(BP4_PrefGet(kBP4PrefsDomain, @"choice"));
    if (c != BP4_ChoiceNone) return c;
    c = BP4_ParseChoice(BP4_PrefGet(kBP4LegacyDomain, @"choice"));
    if (c != BP4_ChoiceNone) {
        BP4_SaveChoice(c);
        BP4_Log(@"saved choice %d migrated from the ExtendedDisplayEnabler domain", c);
    }
    return c;
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
- (id)externalApplicationSceneHandles;
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
static BOOL gBP4AutoextInstalled;
static BP4ExtState *BP4_State(id policy) { return policy ? objc_getAssociatedObject(policy, &kBP4ExtStateKey) : nil; }
// G4B.x posts the same four policy notifications passively when this one does not own the policy (no autoext state)
BOOL BP4_PolicyPostsNotifications(id policy);
BOOL BP4_PolicyPostsNotifications(id policy) { return BP4_State(policy) != nil; }

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

    // 16.2: [_externalDisplayDefaults setMirroringEnabled:!met]   (done BEFORE the observer below is installed).  ExtendedDisplayEnabler's beta-5
    // rule (mirroringEnabled = !_areRuntimeAvailabilityRequirementsMet) is the same value; on top of it the user's saved choice (EDEApplyDesired)
    // wins, and it is also the user preference of the 16.2 state (userPref 1 mirror / 2 extend), otherwise shouldHaveControl would answer with
    // the automatic flag and the display would not follow the choice.  Compare first, like EDEApplyDesired (the 16.0 body set YES just before).
    BOOL wantMirror = !met;
    if (gBP4Choice != BP4_ChoiceNone) {
        wantMirror = (gBP4Choice == BP4_ChoiceMirror);
        st.userPref = wantMirror ? 1 : 2;
    }
    BOOL wasMirror = [defaults isMirroringEnabled];
    if (wasMirror != wantMirror) [defaults setMirroringEnabled:wantMirror];
    BP4_Log(@"autoext: connect, requirements met=%d -> mirroringEnabled=%d (was %d, %s)", met, wantMirror, wasMirror, gBP4Choice != BP4_ChoiceNone ? "saved choice" : "beta-5 default");

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
// ExtendedDisplayEnabler ran the original and then put the desired state back (EDEApplyDesired: saved choice, else the beta-5 default of the last policy
// connect).  Skipping the original ends in the same state without the detour: the forced YES is the only thing the 16.0 body does to the mirroring
// default, and the state it would have to be restored to is what the policy connect above already wrote (saved choice or !met).  Skipping also keeps the
// defaults observer of the policy (user preference) from seeing a YES that nobody chose.
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

// ExtendedDisplayEnabler 0.2.2 (EDEApplyMirroring) is merged here: the requested value is applied for BOTH values (the 16.0 original only does the
// "turn on" half), the request is remembered as the user's saved choice (it beats the automatic decision at the next connect), and a request for
// "extended" also sets the "extended display ever enabled with hardware requirements satisfied" flag of the defaults.  Like EDE the original is not
// called when the request is handled (arguments of the expected kind and an extended identity + defaults found).
// Runs on the main queue: SBDisplayManager asserts the main thread and the service calls this on its XPC queue.

// PORTABLE
static void (*orig_setMirroring)(id, SEL, id, id);
static void hk_setMirroring(id self, SEL _cmd, id enabled, id hardwareIdentifier) {
    BP4_Log(@"mirrorsvc: setDisplayMirroringEnabled hook hit: enabled=%@ display=%@", enabled, hardwareIdentifier);
    if (!BP4_On(BP4_MIRRORSVC) || ![enabled isKindOfClass:[NSNumber class]] || ![hardwareIdentifier isKindOfClass:[NSString class]] ||
        ![self respondsToSelector:@selector(_extendedModeDisplayIdentityForHardwareIdentifier:error:)]) {
        orig_setMirroring(self, _cmd, enabled, hardwareIdentifier);
        return;
    }
    BOOL want = [enabled boolValue];

    id process = nil;                                              // 16.0: [[BSServiceConnection currentContext] remoteProcess]
    @try {
        Class bsc = objc_getClass("BSServiceConnection");          // by name: no link against BoardServices
        if (bsc && [(id)bsc respondsToSelector:@selector(currentContext)]) {
            id ctx = [(id)bsc currentContext];
            if ([ctx respondsToSelector:@selector(remoteProcess)]) process = ((id (*)(id, SEL))objc_msgSend)(ctx, @selector(remoteProcess));
        }
    } @catch (NSException *ex) {
        process = nil;
    }
    NSString *hw = [hardwareIdentifier copy];
    BP4_Main(^{                                                    // 16.0/16.2: BSDispatchMain
        @try {
            id identity = [self _extendedModeDisplayIdentityForHardwareIdentifier:hw error:NULL];
            id defaults = BP4_Ivar(self, "_defaults");
            if (!identity || ![defaults respondsToSelector:@selector(isMirroringEnabled)] || ![defaults respondsToSelector:@selector(setMirroringEnabled:)]) {
                BP4_Log(@"mirrorsvc: mirroring request: no extended identity/defaults for %@", hw);
                return;
            }
            // The request is valid: remember it so the connect handlers can't undo it later.
            gBP4Choice = want ? BP4_ChoiceMirror : BP4_ChoiceExtended;
            BP4_SaveChoice(gBP4Choice);

            BOOL cur = [defaults isMirroringEnabled];
            BP4_Log(@"mirrorsvc: mirroring request: want=%d current=%d display=%@", want, cur, hw);
            if (cur == want) return;
            [defaults setMirroringEnabled:want];
            if (BP4_Logging()) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    BP4_Log(@"mirrorsvc: 1s after the change: isMirroringEnabled=%d (wanted %d)", [defaults isMirroringEnabled], want);
                });
            }
            if (!want) {
                // The education observer only forces mirroring while neither "ever enabled" flag is set.
                SEL ever = NSSelectorFromString(@"setExtendedDisplayEverEnabledWithHardwareReqsSatisfied:");
                if ([defaults respondsToSelector:ever]) ((void (*)(id, SEL, BOOL))objc_msgSend)(defaults, ever, YES);
            }
            if ([self respondsToSelector:@selector(_notifyOfPropertyChangesForDisplayIdentity:requestingProcess:)])
                [self _notifyOfPropertyChangesForDisplayIdentity:identity requestingProcess:process];
        } @catch (NSException *ex) {
            BP4_Log(@"mirrorsvc: exception applying mirroring change: %@", ex);
        }
    });
}

// G4B.x (education alert): the answer of the alert writes the mirroring default itself; it is the user's explicit choice as much as the Settings
// switch is, so it replaces the saved choice (else the next connect would put the older saved choice back over it).
void BP4_NoteUserMirroringChoice(BOOL mirror);
void BP4_NoteUserMirroringChoice(BOOL mirror) {
    if (!BP4_On(BP4_AUTOEXT)) return;
    BP4_Main(^{
        gBP4Choice = mirror ? BP4_ChoiceMirror : BP4_ChoiceExtended;
        BP4_SaveChoice(gBP4Choice);
        BP4_Log(@"autoext: education alert answered, saved choice -> %s", mirror ? "mirror" : "extended");
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
// 16.2 0x1c7703898: a REQUIRED SBSuspendedUnderLockManagerDelegate method; 16.0's manager calls it on every un-lock.
static id   BP4_NI_RunningScenes(id self, SEL _cmd, id mgr) {
    if ([self respondsToSelector:@selector(externalApplicationSceneHandles)]) return [self externalApplicationSceneHandles];
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
// The two entry points are guarded below, and the three blocks that 16.2 gives the signal test are guarded by address (BP4_InstallBlockGuards).

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

// The three blocks that 16.2 gives the signal test (by address; 16.0 SpringBoard, verified by prologue words; the blocks are static functions, so a function hook is the
// only way).  Same semantics as 16.2: a block that finds the controller disconnected logs and ends without doing its work (16.2 connect completion 0x1c73bbfac
// "log, then return" before `_connectionCompleted = YES`; 16.2 presentation update blocks 0x1c73be154 / 0x1c73be3c0 test the controller's signal next to the update's
// own cancel signal and end the same way).  16.0 equivalents: connect completion 0x1c5f47584 (controller at block+0x20), update blocks 0x1c5f4972c / 0x1c5f49970
// (update signal at +0x20, controller at +0x28).  Not ported: the second signal test in the middle of 16.2's block 2 (after updateWithPreferences:, invalidates the
// transition assertion): both ends run on the main thread, only a re-entrant disconnect from inside updateWithPreferences: could flip it.
typedef void (*BP4MSHookFn)(void *symbol, void *replace, void **result);
#if __has_feature(ptrauth_calls)
#define BP4_STRIP(p)   ptrauth_strip((p), ptrauth_key_function_pointer)
#define BP4_SIGN(p)    ptrauth_sign_unauthenticated(ptrauth_strip((p), ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0)
#else
#define BP4_STRIP(p)   (p)
#define BP4_SIGN(p)    (p)
#endif
static void (*orig_blkConnect)(void *);
static void (*orig_blkUpdate2)(void *);
static void (*orig_blkUpdate3)(void *);
static id BP4_BlockController(void *blk, size_t off) { return (__bridge id)*(void *const *)((const char *)blk + off); }
static void hk_blkConnect(void *blk) {
    id c = BP4_BlockController(blk, 0x20);
    if (BP4_On(BP4_DISCGUARD) && BP4_Disconnected(c)) { BP4_Log(@"discguard: connect completion block ran after the disconnect of %p, skipped (16.2 behaviour)", (__bridge void *)c); return; }
    orig_blkConnect(blk);
}
static void hk_blkUpdate2(void *blk) {
    id c = BP4_BlockController(blk, 0x28);
    if (BP4_On(BP4_DISCGUARD) && BP4_Disconnected(c)) { BP4_Log(@"discguard: presentation update block (apply) skipped, controller %p is disconnected (16.2 behaviour)", (__bridge void *)c); return; }
    orig_blkUpdate2(blk);
}
static void hk_blkUpdate3(void *blk) {
    id c = BP4_BlockController(blk, 0x28);
    if (BP4_On(BP4_DISCGUARD) && BP4_Disconnected(c)) { BP4_Log(@"discguard: presentation update block (finish) skipped, controller %p is disconnected (16.2 behaviour)", (__bridge void *)c); return; }
    orig_blkUpdate3(blk);
}
static BOOL BP4_HookBlock(const char *what, uintptr_t vm, const uint32_t *words, int n, intptr_t slide, BP4MSHookFn hookFn, void *repl, void **origOut) {
    uintptr_t entry = vm + (uintptr_t)slide;
    if (memcmp((const void *)entry, words, (size_t)n * 4) != 0) { BP4_Log(@"discguard: block %s prologue mismatch at %p, not installing", what, (void *)entry); return NO; }
    void *orig = NULL;
    hookFn(BP4_STRIP((void *)entry), BP4_STRIP(repl), &orig);
    if (!orig) { BP4_Log(@"discguard: block %s: MSHookFunction returned no trampoline, not installing", what); return NO; }
    *origOut = BP4_SIGN(orig);
    BP4_Log(@"discguard: block %s hooked at %p (16.0 0x%lx)", what, (void *)entry, (unsigned long)vm);
    return YES;
}
static void BP4_InstallBlockGuards(void) {
    static const uint32_t kConnect[7] = { 0xd503237f, 0xd100c3ff, 0xa9014ff4, 0xa9027bfd, 0x910083fd, 0xaa0003f3, 0xf9401008 };
    static const uint32_t kUpd2[7]    = { 0xd503237f, 0xd10283ff, 0xa90757f6, 0xa9084ff4, 0xa9097bfd, 0x910243fd, 0xaa0003f3 };
    static const uint32_t kUpd3[7]    = { 0xd503237f, 0xd10143ff, 0xa90257f6, 0xa9034ff4, 0xa9047bfd, 0x910103fd, 0xaa0003f3 };
    BP4MSHookFn hookFn = (BP4MSHookFn)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (!hookFn) { BP4_Log(@"discguard: MSHookFunction not available, the three presentation blocks are not guarded (entry points still are)"); return; }
    intptr_t slide = 0;
    BOOL found = NO;
    for (uint32_t i = 0, n = _dyld_image_count(); i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "/SpringBoard.framework/SpringBoard")) { slide = _dyld_get_image_vmaddr_slide(i); found = YES; break; }
    }
    if (!found) { BP4_Log(@"discguard: SpringBoard.framework image not found, blocks not guarded"); return; }
    BOOL a = BP4_HookBlock("connect completion", 0x1c5f47584, kConnect, 7, slide, hookFn, (void *)hk_blkConnect, (void **)&orig_blkConnect);
    BOOL b = BP4_HookBlock("update apply", 0x1c5f4972c, kUpd2, 7, slide, hookFn, (void *)hk_blkUpdate2, (void **)&orig_blkUpdate2);
    BOOL c = BP4_HookBlock("update finish", 0x1c5f49970, kUpd3, 7, slide, hookFn, (void *)hk_blkUpdate3, (void **)&orig_blkUpdate3);
    BP4_Log(@"discguard: block guards connect %d apply %d finish %d (slide 0x%lx)", (int)a, (int)b, (int)c, (long)slide);
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
    gBP4Choice = BP4_LoadChoice();
    BP4_Log(@"saved choice=%d", gBP4Choice);
    // --- autoext / mirrorsvc (0.7.0; since 0.7.5 the one implementation, ExtendedDisplayEnabler is merged into the package)
    if (BP4_On(BP4_AUTOEXT) && objc_getClass(pol)) {
        BP4_AddMethod(pol, @selector(_keyboardAvailabilityChanged:), (IMP)BP4_KeyboardAvailabilityChanged, "v@:@");
        BP4_AddMethod(pol, @selector(mousePointerManager:hardwarePointingDeviceAttachedDidChange:), (IMP)BP4_PointerAttachChanged, "v@:@B");
        if (BP4_Hook(pol, @selector(connectToDisplayController:displayConfiguration:), (IMP)hk_policyConnect, (IMP *)&orig_policyConnect)) ok++;
        if (BP4_Hook(pol, @selector(displayControllerShouldHaveControlOfDisplay:), (IMP)hk_shouldHaveControl, (IMP *)&orig_shouldHaveControl)) ok++;
        if (BP4_Hook(pol, @selector(displayControllerDidDisconnect:sceneManager:), (IMP)hk_policyDidDisconnect, (IMP *)&orig_policyDidDisconnect)) ok++;
        BP4_Hook("SBExternalDisplayEducationObserver", @selector(displayManager:didConnectToRootDisplay:), (IMP)hk_eduConnect, (IMP *)&orig_eduConnect);
        gBP4AutoextInstalled = (ok == 3);
    }
    if (BP4_On(BP4_MIRRORSVC))
        BP4_Hook("SBExternalDisplayService", @selector(setDisplayMirroringEnabled:forDisplay:), (IMP)hk_setMirroring, (IMP *)&orig_setMirroring);

    // --- covernote
    BP4_Hook("SBExternalDisplayCoverSheetController", @selector(_setCoverSheetWindowVisible:fadeDuration:), (IMP)hk_coverVisible, (IMP *)&orig_coverVisible);

    // --- nilock
    const char *ni = "SBNonInteractiveDisplaySceneManager";
    // Evaluated once at launch: with Backport162.off.nilock present the class is not touched at all.
    if (BP4_On(BP4_NILOCK) && objc_getClass(ni) && objc_getClass("SBSuspendedUnderLockManager")) {
        BP4_AddMethod(ni, @selector(setSuspendedUnderLock:), (IMP)BP4_NI_SetLocked, "v@:B");
        BP4_AddMethod(ni, @selector(setSuspendedUnderLock:alongsideWillChangeBlock:alongsideDidChangeBlock:), (IMP)BP4_NI_SetLockedFull, "v@:B@?@?");
        BP4_AddMethod(ni, @selector(isSuspendedUnderLock), (IMP)BP4_NI_IsLocked, "B@:");
        BP4_AddMethod(ni, @selector(_externalCoverSheetVisibilityDidPresent:), (IMP)BP4_NI_CoverPresent, "v@:@");
        BP4_AddMethod(ni, @selector(_externalCoverSheetVisibilityDidDismiss:), (IMP)BP4_NI_CoverDismiss, "v@:@");
        BP4_AddMethod(ni, @selector(suspendedUnderLockManagerVisibleScenes:), (IMP)BP4_NI_VisibleScenes, "@@:@");
        BP4_AddMethod(ni, @selector(runningApplicationScenes:), (IMP)BP4_NI_RunningScenes, "@@:@");
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
    if (BP4_On(BP4_DISCGUARD)) BP4_InstallBlockGuards();      // evaluated once at launch: with Backport162.off.discguard the blocks are not touched

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
