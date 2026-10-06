// ExtendedDisplayEnabler
//
// iPadOS 16.0 build 20A8372 still contains the whole Extended-display stack
// (SBSystemShellExtended* resolver/policy/controller classes, the
// SpringBoard._extendedDisplayControllerProvider ivar, Settings UI), but three
// pieces of glue were removed or neutered compared with betas 2-5:
//
//  1. -[SpringBoard _completeStartupAfterMainSceneConnect:] no longer builds and
//     registers the Extended provider (it did, behind
//     SBChamoisExternalDisplayControllerIsEnabled()). Without it nothing reports
//     windowing mode 1 for an external display, so the display only mirrors and
//     Settings hides Arrangement / Display Zoom.
//        -> we recreate the beta-5 registration (see EDEInstall).
//  2. -[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:] ignores the
//     requested value and can only turn mirroring ON.
//        -> we restore the beta-5 behaviour (see EDEApplyMirroring).
//  3. The Extended policy's connect and the education observer's connect handler
//     hardcode mirroringEnabled = YES. Beta 5 used !_areRuntimeAvailabilityRequirementsMet
//     in the policy and had a full education presenter instead of the observer stub.
//        -> after those handlers run we put back the user's saved choice, or, if there
//           is none, beta 5's default.
//
// Files (all under the jailbreak root; paths are resolved at runtime with libroot, see EDEInitPaths):
//   <jbroot>/var/mobile/Library/Logs/ExtendedDisplayEnabler.log          log (rotated at 256 KiB)
//   <jbroot>/var/mobile/Library/Preferences/ExtendedDisplayEnabler.off   kill switch: disables every hook
//   <jbroot>/tmp/ExtendedDisplayEnabler.off                              kill switch (alternative location)
//   <jbroot>/var/mobile/Library/Preferences/ExtendedDisplayEnabler.choice  saved "extended" / "mirror" choice
//   <jbroot>/var/mobile/Library/Preferences/ExtendedDisplayEnabler.boot    crash-loop strike counter

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <pthread.h>
#import <rootless.h>        // ROOT_PATH_NS(): jailbreak-root prefix resolved at runtime via libroot

// Rootless convention: every file this tweak creates lives under the jailbreak root, never at a rootful
// path (a leftover rootful file can be used to detect the jailbreak). The prefix is resolved at runtime by
// libroot via ROOT_PATH_NS, so relocated jbroots keep working. Resolved once in EDEInitPaths().
//   saved choice / crash counter : CFPreferences domain kPrefsDomain (stored by cfprefsd, not a jailbreak file)
//   log and kill switch          : <jbroot>/tmp (<jbroot>/var/mobile/Library/Logs does not exist on every setup)
static NSString *const kPrefsDomain = @"com.infernowolf19.extendeddisplayenabler";
static NSString *kLogPath;
static NSString *kLogOldPath;
static NSString *kOffPath;

static void EDEInitPaths(void) {
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    kLogPath    = [tmp stringByAppendingPathComponent:@"ExtendedDisplayEnabler.log"];
    kLogOldPath = [kLogPath stringByAppendingString:@".1"];
    kOffPath    = [tmp stringByAppendingPathComponent:@"ExtendedDisplayEnabler.off"];
}

static id EDEPrefGet(NSString *key) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kPrefsDomain));
    return v;
}

static void EDEPrefSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kPrefsDomain);
}

static const unsigned long long kMaxLogBytes = 256 * 1024;
static const int kMaxAttempts = 40;           // late-install retries, x 0.5 s
static const int kMaxBootStrikes = 5;         // launches that died inside the stability window
static const double kStableAfterSeconds = 25.0;

enum { EDEChoiceNone = 0, EDEChoiceExtended = 1, EDEChoiceMirror = 2 };

static id gProvider;                          // keeps the provider alive
static id gResolverFactory, gPolicyFactory;
static BOOL gInstalling;                      // re-entrancy guard for the early-install hook
static BOOL gGuardTripped;                    // crash-loop guard disabled the tweak
static int gChoice;                           // EDEChoice*, main thread only after %ctor
static int gAutoDecision = -1;                // beta-5 default: -1 unknown, 0 mirror, 1 extended

// ---------------------------------------------------------------- logging

static pthread_mutex_t gLogMutex = PTHREAD_MUTEX_INITIALIZER;

static void EDELogLocked(NSString *msg) {
    if (!kLogPath) return;                           // paths not resolved yet
    static NSDateFormatter *fmt;
    if (!fmt) {
        fmt = [[NSDateFormatter alloc] init];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:kLogPath error:NULL];
    if (attrs && [attrs fileSize] > kMaxLogBytes) {
        [fm removeItemAtPath:kLogOldPath error:NULL];
        [fm moveItemAtPath:kLogPath toPath:kLogOldPath error:NULL];
    }
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [fmt stringFromDate:[NSDate date]], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!fh) {
        [fm createFileAtPath:kLogPath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static void EDELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void EDELog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ExtendedDisplayEnabler] %@", msg);
    pthread_mutex_lock(&gLogMutex);
    @try {
        EDELogLocked(msg);
    } @catch (NSException *e) {
        // logging must never take SpringBoard down
    }
    pthread_mutex_unlock(&gLogMutex);
}

// ---------------------------------------------------------------- helpers

#define MSG(ret, obj, sel, ...) ((ret (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)((obj), NSSelectorFromString(sel), ##__VA_ARGS__)

static BOOL EDEDisabled(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    return gGuardTripped || (kOffPath && [fm fileExistsAtPath:kOffPath]);
}

static id EDEIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static BOOL EDEIsMirroring(id defaults) {
    SEL s = NSSelectorFromString(@"isMirroringEnabled");
    if (![defaults respondsToSelector:s]) return YES;   // unknown: assume the stock behaviour
    return ((BOOL (*)(id, SEL))objc_msgSend)(defaults, s);
}

static void EDESetMirroring(id defaults, BOOL v) {
    SEL s = NSSelectorFromString(@"setMirroringEnabled:");
    if ([defaults respondsToSelector:s]) ((void (*)(id, SEL, BOOL))objc_msgSend)(defaults, s, v);
}

static id EDELocalExternalDisplayDefaults(void) {
    Class d = NSClassFromString(@"SBDefaults");
    id local = d ? MSG(id, d, @"localDefaults") : nil;
    return local ? MSG(id, local, @"externalDisplayDefaults") : nil;
}

// ---------------------------------------------------------------- saved choice

static int EDELoadChoice(void) {
    id v = EDEPrefGet(@"choice");
    if ([v isKindOfClass:[NSString class]]) {
        if ([v isEqualToString:@"extended"]) return EDEChoiceExtended;
        if ([v isEqualToString:@"mirror"]) return EDEChoiceMirror;
    }
    return EDEChoiceNone;
}

static void EDESaveChoice(int choice) {
    NSString *text = choice == EDEChoiceExtended ? @"extended" : (choice == EDEChoiceMirror ? @"mirror" : nil);
    EDEPrefSet(@"choice", text);
}

// -1 = no opinion, 0 = mirror, 1 = extended
static int EDEDesired(void) {
    if (gChoice == EDEChoiceExtended) return 1;
    if (gChoice == EDEChoiceMirror) return 0;
    return gAutoDecision;
}

// 20A8372 forces mirroringEnabled = YES in the Extended policy's connect and in the education
// observer's connect handler. Put back the user's choice (or beta 5's default) after they ran.
static void EDEApplyDesired(id defaults, const char *why) {
    @try {
        int want = EDEDesired();
        if (want < 0 || !defaults) return;
        BOOL wantMirror = (want == 0);
        if (EDEIsMirroring(defaults) != wantMirror) {
            EDELog(@"%s: mirroring was %d, setting %d (%s)", why, !wantMirror, wantMirror,
                   gChoice != EDEChoiceNone ? "saved choice" : "beta-5 default");
            EDESetMirroring(defaults, wantMirror);
        } else {
            EDELog(@"%s: mirroring already %d", why, wantMirror);
        }
    } @catch (NSException *e) {
        EDELog(@"%s: exception %@", why, e);
    }
}

// ---------------------------------------------------------------- provider install

// Returns YES when finished (installed, already installed, or impossible),
// NO when a dependency is not ready yet and the caller should retry.
// `quiet` suppresses the "not ready" logging for the early attempts.
static BOOL EDEInstall(id sb, BOOL early, BOOL quiet) {
    @try {
        Class Provider = NSClassFromString(@"SBSceneHostingDisplayControllerProvider");
        Class ResFact  = NSClassFromString(@"SBSystemShellExtendedDisplayResolverFactory");
        Class PolFact  = NSClassFromString(@"SBSystemShellExtendedDisplayControllerPolicyFactory");
        Class Registry = NSClassFromString(@"SBDisplayTransformerRegistry");
        Class Queue    = NSClassFromString(@"FBWorkspaceEventQueue");
        Class SceneMgr = NSClassFromString(@"FBSceneManager");
        Class Defaults = NSClassFromString(@"SBDefaults");
        Class Domain   = NSClassFromString(@"SBExternalDisplaySettingsDomain");
        if (!Provider || !ResFact || !PolFact || !Registry || !Queue || !SceneMgr || !Defaults || !Domain) {
            EDELog(@"required class missing (Provider=%@ ResFact=%@ PolFact=%@ Registry=%@ Queue=%@ SceneMgr=%@ Defaults=%@ Domain=%@); giving up",
                   Provider, ResFact, PolFact, Registry, Queue, SceneMgr, Defaults, Domain);
            return YES;
        }
        if (EDEIvar(sb, "_extendedDisplayControllerProvider") || gProvider) {
            if (!quiet) EDELog(@"Extended provider already present; nothing to do");
            return YES;
        }

        id displayManager = EDEIvar(sb, "_displayManager");
        id service        = EDEIvar(sb, "_externalDisplayService");
        id pointerMgr     = EDEIvar(sb, "_mousePointerManager");
        if (!displayManager || !service || !pointerMgr) {
            if (!quiet) {
                EDELog(@"dependencies not ready (displayManager=%@ service=%@ pointerManager=%@)",
                       displayManager ? @"ok" : @"nil", service ? @"ok" : @"nil", pointerMgr ? @"ok" : @"nil");
            }
            return NO;
        }

        id registry  = MSG(id, Registry, @"sharedInstance");
        id queue     = MSG(id, Queue, @"sharedInstance");
        id sceneMgr  = MSG(id, SceneMgr, @"sharedInstance");
        id localDefs = MSG(id, Defaults, @"localDefaults");
        id extDefs   = localDefs ? MSG(id, localDefs, @"externalDisplayDefaults") : nil;
        id rootSet   = MSG(id, Domain, @"rootSettings");
        id availSet  = rootSet ? MSG(id, rootSet, @"availabilitySettings") : nil;
        if (!registry || !queue || !sceneMgr || !extDefs || !availSet) {
            if (!quiet) {
                EDELog(@"collaborators not ready (registry=%@ queue=%@ sceneMgr=%@ extDefaults=%@ availability=%@)",
                       registry ? @"ok" : @"nil", queue ? @"ok" : @"nil", sceneMgr ? @"ok" : @"nil",
                       extDefs ? @"ok" : @"nil", availSet ? @"ok" : @"nil");
            }
            return NO;
        }

        id resFact = [[ResFact alloc] init];
        id polFact = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
            [PolFact alloc],
            NSSelectorFromString(@"initWithExternalDisplayService:externalDisplayDefaults:mousePointerManager:runtimeAvailabilitySettings:sceneManager:"),
            service, extDefs, pointerMgr, availSet, sceneMgr);
        if (!resFact || !polFact) { EDELog(@"factory creation failed"); return YES; }

        id provider = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
            [Provider alloc],
            NSSelectorFromString(@"initWithTransformerRegistry:displayManager:workspaceEventQueue:displayModeResolverFactory:policyFactory:"),
            registry, displayManager, queue, resFact, polFact);
        if (!provider) { EDELog(@"provider creation failed"); return YES; }

        gResolverFactory = resFact; gPolicyFactory = polFact; gProvider = provider;
        Ivar iv = class_getInstanceVariable(object_getClass(sb), "_extendedDisplayControllerProvider");
        if (iv) {
            object_setIvar(sb, iv, provider);
            // object_setIvar does not retain under ARC; balance the strong ivar we just filled.
            CFRetain((__bridge CFTypeRef)provider);
        }

        ((void (*)(id, SEL, id))objc_msgSend)(displayManager, NSSelectorFromString(@"registerDisplayControllerProvider:"), provider);
        EDELog(@"registered Extended display provider %@ (%@)", provider, early ? @"early, before the other providers" : @"after startup");

        NSSet *ids = MSG(id, displayManager, @"connectedIdentities");
        for (id ident in ids) {
            NSInteger mode = ((NSInteger (*)(id, SEL, id))objc_msgSend)(sb, NSSelectorFromString(@"windowingModeForDisplay:"), ident);
            EDELog(@"connected identity %@ windowingMode=%ld", ident, (long)mode);
        }
    } @catch (NSException *e) {
        EDELog(@"exception during install: %@", e);
    }
    return YES;
}

// Late path: after startup finished, retry until the dependencies exist.
static void EDEAttempt(id sb, int n) {
    if (EDEDisabled()) { EDELog(@"disabled (kill switch or crash guard); not installing"); return; }
    if (EDEInstall(sb, NO, NO)) return;
    if (n >= kMaxAttempts) { EDELog(@"gave up after %d attempts", n); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        EDEAttempt(sb, n + 1);
    });
}

// Early path: beta 5 registered the Extended provider before the others, so a display that is
// already plugged in when SpringBoard starts gets claimed by it. Called from the hook on
// -[SBDisplayManager registerDisplayControllerProvider:]; it silently does nothing until the
// external-display service and pointer manager exist, then installs once.
static void EDEEarlyInstall(id manager) {
    if (gInstalling || gProvider || EDEDisabled() || ![NSThread isMainThread]) return;
    @try {
        id sb = [UIApplication sharedApplication];
        Class SB = NSClassFromString(@"SpringBoard");
        if (!sb || !SB || ![sb isKindOfClass:SB]) return;
        if (EDEIvar(sb, "_displayManager") != manager) return;
        gInstalling = YES;
        EDEInstall(sb, YES, YES);
        gInstalling = NO;
    } @catch (NSException *e) {
        gInstalling = NO;
        EDELog(@"exception in early install: %@", e);
    }
}

// ---------------------------------------------------------------- mirroring toggle

@interface SpringBoard : UIApplication
@end

@interface SBExternalDisplayService : NSObject
- (id)_extendedModeDisplayIdentityForHardwareIdentifier:(id)hwid error:(NSError **)err;
- (void)_notifyOfPropertyChangesForDisplayIdentity:(id)identity requestingProcess:(id)process;
@end

// Restores beta 5's -[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:]:
// compare the requested NSNumber with the current default and apply it.
// Returns NO if the arguments are not what we expect (caller then runs the original).
static BOOL EDEApplyMirroring(id service, id enabled, id hardwareIdentifier) {
    EDELog(@"setDisplayMirroringEnabled hook hit: enabled=%@ display=%@", enabled, hardwareIdentifier);
    if (![enabled isKindOfClass:[NSNumber class]] || !hardwareIdentifier) return NO;
    BOOL want = [enabled boolValue];
    id process = nil;
    @try {
        // Looked up by name: a direct class reference would need a link against BoardServices.
        Class connClass = NSClassFromString(@"BSServiceConnection");
        id ctx = connClass ? MSG(id, connClass, @"currentContext") : nil;
        process = [ctx valueForKey:@"remoteProcess"];
    } @catch (NSException *ex) {
        process = nil;
    }
    void (^apply)(void) = ^{
        @try {
            id identity = [service _extendedModeDisplayIdentityForHardwareIdentifier:hardwareIdentifier error:NULL];
            id defaults = EDEIvar(service, "_defaults");
            if (!identity || !defaults) {
                EDELog(@"mirroring request: no extended identity/defaults for %@", hardwareIdentifier);
                return;
            }
            // The request is valid: remember it so the connect handlers can't undo it later.
            gChoice = want ? EDEChoiceMirror : EDEChoiceExtended;
            EDESaveChoice(gChoice);

            BOOL cur = EDEIsMirroring(defaults);
            EDELog(@"mirroring request: want=%d current=%d display=%@", want, cur, hardwareIdentifier);
            if (cur == want) return;
            EDESetMirroring(defaults, want);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                EDELog(@"1s after the change: isMirroringEnabled=%d (wanted %d)", EDEIsMirroring(defaults), want);
            });
            if (!want) {
                // The education observer only forces mirroring while neither "ever enabled" flag is set.
                SEL ever = NSSelectorFromString(@"setExtendedDisplayEverEnabledWithHardwareReqsSatisfied:");
                if ([defaults respondsToSelector:ever]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(defaults, ever, YES);
                }
            }
            [service _notifyOfPropertyChangesForDisplayIdentity:identity requestingProcess:process];
        } @catch (NSException *ex) {
            EDELog(@"exception applying mirroring change: %@", ex);
        }
    };
    // SBDisplayManager (connectedIdentities / windowingModeForDisplay:) asserts main thread, and this
    // hook is called on the service's XPC queue, so hop to the main queue.
    if ([NSThread isMainThread]) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
    return YES;
}

// ---------------------------------------------------------------- connect handlers

static void EDEAfterPolicyConnect(id policy) {
    @try {
        id defaults = EDEIvar(policy, "_externalDisplayDefaults");
        if (gChoice == EDEChoiceNone) {
            // No saved choice: beta 5's rule was mirroringEnabled = !_areRuntimeAvailabilityRequirementsMet.
            SEL met = NSSelectorFromString(@"_areRuntimeAvailabilityRequirementsMet");
            if ([policy respondsToSelector:met]) {
                BOOL ok = ((BOOL (*)(id, SEL))objc_msgSend)(policy, met);
                gAutoDecision = ok ? 1 : 0;
                EDELog(@"no saved choice; runtime requirements met=%d -> default %@", ok, ok ? @"extended" : @"mirror");
            }
        }
        EDEApplyDesired(defaults, "Extended policy connect");
    } @catch (NSException *e) {
        EDELog(@"exception after policy connect: %@", e);
    }
}

// ---------------------------------------------------------------- hooks

%hook SBDisplayManager
- (void)registerDisplayControllerProvider:(id)provider {
    EDEEarlyInstall(self);
    %orig;
}
%end

%hook SpringBoard
- (void)_completeStartupAfterMainSceneConnect:(id)scene {
    %orig;
    // Fallback if the early install could not run: let the rest of startup settle, then retry.
    dispatch_async(dispatch_get_main_queue(), ^{ EDEAttempt(self, 0); });
}
%end

%hook SBExternalDisplayService
- (void)setDisplayMirroringEnabled:(id)enabled forDisplay:(id)hardwareIdentifier {
    if (!EDEDisabled() && EDEApplyMirroring(self, enabled, hardwareIdentifier)) return;
    %orig;
}
%end

%hook SBSystemShellExtendedDisplayControllerPolicy
- (void)connectToDisplayController:(id)controller displayConfiguration:(id)configuration {
    %orig;
    if (!EDEDisabled()) EDEAfterPolicyConnect(self);
}
%end

%hook SBExternalDisplayEducationObserver
- (void)displayManager:(id)manager didConnectToRootDisplay:(id)display {
    %orig;
    if (!EDEDisabled()) EDEApplyDesired(EDELocalExternalDisplayDefaults(), "education observer connect");
}
%end

// ---------------------------------------------------------------- crash-loop guard

%ctor {
    @autoreleasepool {
        EDEInitPaths();
        gChoice = EDELoadChoice();

        // Count launches that did not stay up for kStableAfterSeconds. If SpringBoard keeps dying
        // shortly after start (e.g. a crash when the monitor connects), stop touching it.
        id raw = EDEPrefGet(@"bootStrikes");
        int strikes = [raw respondsToSelector:@selector(intValue)] ? [raw intValue] : 0;
        if (strikes >= kMaxBootStrikes) {
            gGuardTripped = YES;
            EDELog(@"crash guard: %d consecutive short-lived launches; tweak disabled. Reset with: defaults delete %@ bootStrikes", strikes, kPrefsDomain);
            return;
        }
        EDEPrefSet(@"bootStrikes", @(strikes + 1));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kStableAfterSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            EDEPrefSet(@"bootStrikes", nil);
        });
        EDELog(@"loaded; saved choice=%d strikes=%d", gChoice, strikes);
    }
}
