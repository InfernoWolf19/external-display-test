// ExtendedDisplayEnabler
//
// iPadOS 16.0 build 20A8372 still contains the whole Extended-display stack
// (SBSystemShellExtended* resolver/policy/controller classes, the
// SpringBoard._extendedDisplayControllerProvider ivar, Settings UI), but
// -[SpringBoard _completeStartupAfterMainSceneConnect:] no longer builds and
// registers the Extended provider. Betas 2 and 5 did, behind
// SBChamoisExternalDisplayControllerIsEnabled(). Without it nothing ever
// reports windowing mode 1 for an external display, so SpringBoard falls back
// to mirroring and Settings hides Arrangement / Resolution / Scaling.
//
// This tweak re-creates the beta-5 registration after startup finishes:
//
//   resolverFactory = [SBSystemShellExtendedDisplayResolverFactory new];
//   policyFactory   = [[SBSystemShellExtendedDisplayControllerPolicyFactory alloc]
//                        initWithExternalDisplayService:   sb->_externalDisplayService
//                                externalDisplayDefaults:  [[SBDefaults localDefaults] externalDisplayDefaults]
//                                    mousePointerManager:  sb->_mousePointerManager
//                            runtimeAvailabilitySettings:  [[SBExternalDisplaySettingsDomain rootSettings] availabilitySettings]
//                                           sceneManager:  [FBSceneManager sharedInstance]];
//   provider        = [[SBSceneHostingDisplayControllerProvider alloc]
//                        initWithTransformerRegistry:  [SBDisplayTransformerRegistry sharedInstance]
//                                     displayManager:  sb->_displayManager
//                                workspaceEventQueue:  [FBWorkspaceEventQueue sharedInstance]
//                         displayModeResolverFactory:  resolverFactory
//                                      policyFactory:  policyFactory];
//   [sb->_displayManager registerDisplayControllerProvider:provider];
//   sb->_extendedDisplayControllerProvider = provider;
//
// Also restores setDisplayMirroringEnabled:forDisplay: (see bottom of file).
// Log: /var/mobile/Library/Logs/ExtendedDisplayEnabler.log
// Kill switch: create /var/mobile/Library/Preferences/ExtendedDisplayEnabler.off

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString *const kLogPath  = @"/var/mobile/Library/Logs/ExtendedDisplayEnabler.log";
static NSString *const kOffPath  = @"/var/mobile/Library/Preferences/ExtendedDisplayEnabler.off";
static const int kMaxAttempts = 40;           // x 0.5s
static id gProvider;                          // keep the provider alive
static id gResolverFactory, gPolicyFactory;

static void EDELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void EDELog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ExtendedDisplayEnabler] %@", msg);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:kLogPath contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static id EDEIvar(id obj, const char *name) {
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return iv ? object_getIvar(obj, iv) : nil;
}

static NSString *const kChoicePath = @"/var/mobile/Library/Preferences/ExtendedDisplayEnabler.extended";
static BOOL gUserChoseExtended;               // set when the user turns "Mirror Display" off in Settings

static BOOL EDEIsMirroring(id defaults) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(defaults, NSSelectorFromString(@"isMirroringEnabled"));
}
static void EDESetMirroring(id defaults, BOOL v) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(defaults, NSSelectorFromString(@"setMirroringEnabled:"), v);
}
// 20A8372 forces mirroringEnabled = YES in the Extended policy's connect and in the education
// observer's connect handler (beta 5 derived it from the runtime requirements instead).
// If the user already chose extended mode, put that choice back after those handlers ran.
static void EDEEnforceChoice(id defaults, const char *why) {
    if (!gUserChoseExtended || !defaults) return;
    if (EDEIsMirroring(defaults)) {
        EDELog(@"%s forced mirroring on; restoring the user's choice (extended)", why);
        EDESetMirroring(defaults, NO);
    } else {
        EDELog(@"%s left mirroring off", why);
    }
}
static id EDELocalExternalDisplayDefaults(void) {
    Class d = NSClassFromString(@"SBDefaults");
    id local = d ? ((id (*)(id, SEL))objc_msgSend)(d, NSSelectorFromString(@"localDefaults")) : nil;
    return local ? ((id (*)(id, SEL))objc_msgSend)(local, NSSelectorFromString(@"externalDisplayDefaults")) : nil;
}

#define MSG(ret, obj, sel, ...) ((ret (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)((obj), NSSelectorFromString(sel), ##__VA_ARGS__)

// Returns YES when finished (installed, already installed, or impossible),
// NO when a dependency is not ready yet and the caller should retry.
static BOOL EDEInstall(id sb) {
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
            EDELog(@"Extended provider already present; nothing to do");
            return YES;
        }

        id displayManager = EDEIvar(sb, "_displayManager");
        id service        = EDEIvar(sb, "_externalDisplayService");
        id pointerMgr     = EDEIvar(sb, "_mousePointerManager");
        if (!displayManager || !service || !pointerMgr) {
            EDELog(@"dependencies not ready (displayManager=%@ service=%@ pointerManager=%@)",
                   displayManager ? @"ok" : @"nil", service ? @"ok" : @"nil", pointerMgr ? @"ok" : @"nil");
            return NO;
        }

        id registry  = MSG(id, Registry, @"sharedInstance");
        id queue     = MSG(id, Queue, @"sharedInstance");
        id sceneMgr  = MSG(id, SceneMgr, @"sharedInstance");
        id localDefs = MSG(id, Defaults, @"localDefaults");
        id extDefs   = MSG(id, localDefs, @"externalDisplayDefaults");
        id rootSet   = MSG(id, Domain, @"rootSettings");
        id availSet  = MSG(id, rootSet, @"availabilitySettings");
        if (!registry || !queue || !sceneMgr || !extDefs || !availSet) {
            EDELog(@"collaborators not ready (registry=%@ queue=%@ sceneMgr=%@ extDefaults=%@ availability=%@)",
                   registry ? @"ok" : @"nil", queue ? @"ok" : @"nil", sceneMgr ? @"ok" : @"nil",
                   extDefs ? @"ok" : @"nil", availSet ? @"ok" : @"nil");
            return NO;
        }

        id resFact = [[ResFact alloc] init];
        id polFact;
        polFact = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
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
        if (iv) object_setIvar(sb, iv, provider);

        ((void (*)(id, SEL, id))objc_msgSend)(displayManager, NSSelectorFromString(@"registerDisplayControllerProvider:"), provider);
        EDELog(@"registered Extended display provider %@", provider);

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

static void EDEAttempt(id sb, int n) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kOffPath]) { EDELog(@"kill switch present; not installing"); return; }
    if (EDEInstall(sb)) return;
    if (n >= kMaxAttempts) { EDELog(@"gave up after %d attempts", n); return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        EDEAttempt(sb, n + 1);
    });
}

@interface SpringBoard : UIApplication
@end

@interface SBExternalDisplayService : NSObject
- (id)_extendedModeDisplayIdentityForHardwareIdentifier:(id)hwid error:(NSError **)err;
- (void)_notifyOfPropertyChangesForDisplayIdentity:(id)identity requestingProcess:(id)process;
@end

// 20A8372's -[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:] ignores the requested
// value: its block only runs `if (!defaults.isMirroringEnabled) defaults.mirroringEnabled = YES`.
// Beta 5 compared the requested NSNumber with the current value and applied it. Restore that, so the
// Settings "Mirror Display" switch can actually turn mirroring off.
// Returns NO if the arguments are not what we expect (caller then runs the original).
static BOOL EDEApplyMirroring(id service, id enabled, id hardwareIdentifier) {
    EDELog(@"setDisplayMirroringEnabled hook hit: enabled=%@ display=%@", enabled, hardwareIdentifier);
    if (![enabled isKindOfClass:[NSNumber class]] || !hardwareIdentifier) return NO;
    BOOL want = [enabled boolValue];
    gUserChoseExtended = !want;
    if (gUserChoseExtended) [[NSFileManager defaultManager] createFileAtPath:kChoicePath contents:nil attributes:nil];
    else [[NSFileManager defaultManager] removeItemAtPath:kChoicePath error:NULL];
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
            BOOL cur = EDEIsMirroring(defaults);
            EDELog(@"mirroring request: want=%d current=%d display=%@", want, cur, hardwareIdentifier);
            if (cur == want) return;
            EDESetMirroring(defaults, want);
            // Trace whether anything flips it back.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                EDELog(@"1s after the change: isMirroringEnabled=%d (wanted %d)", EDEIsMirroring(defaults), want);
            });
            if (!want) {
                // The education observer re-forces mirroring on every connect until one of these is set.
                SEL ever = NSSelectorFromString(@"setExtendedDisplayEverEnabledWithHardwareReqsSatisfied:");
                if ([defaults respondsToSelector:ever]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(defaults, ever, YES);
                    EDELog(@"marked extendedDisplayEverEnabledWithHardwareReqsSatisfied");
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

%hook SpringBoard
- (void)_completeStartupAfterMainSceneConnect:(id)scene {
    %orig;
    // Let the rest of startup (service / pointer manager wiring) settle first.
    dispatch_async(dispatch_get_main_queue(), ^{ EDEAttempt(self, 0); });
}
%end

%hook SBExternalDisplayService
- (void)setDisplayMirroringEnabled:(id)enabled forDisplay:(id)hardwareIdentifier {
    if (EDEApplyMirroring(self, enabled, hardwareIdentifier)) return;
    %orig;
}
%end

%hook SBSystemShellExtendedDisplayControllerPolicy
- (void)connectToDisplayController:(id)controller displayConfiguration:(id)configuration {
    %orig;
    EDEEnforceChoice(EDEIvar(self, "_externalDisplayDefaults"), "Extended policy connect");
}
%end

%hook SBExternalDisplayEducationObserver
- (void)displayManager:(id)manager didConnectToRootDisplay:(id)display {
    %orig;
    EDEEnforceChoice(EDELocalExternalDisplayDefaults(), "education observer connect");
}
%end

%ctor {
    gUserChoseExtended = [[NSFileManager defaultManager] fileExistsAtPath:kChoicePath];
}
