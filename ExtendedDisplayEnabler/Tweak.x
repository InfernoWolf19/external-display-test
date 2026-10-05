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
            BOOL cur = ((BOOL (*)(id, SEL))objc_msgSend)(defaults, NSSelectorFromString(@"isMirroringEnabled"));
            EDELog(@"mirroring request: want=%d current=%d display=%@", want, cur, hardwareIdentifier);
            if (cur == want) return;
            ((void (*)(id, SEL, BOOL))objc_msgSend)(defaults, NSSelectorFromString(@"setMirroringEnabled:"), want);
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
    id queue = EDEIvar(service, "_serviceQueue");
    if (queue) dispatch_async((dispatch_queue_t)queue, apply);
    else apply();
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
