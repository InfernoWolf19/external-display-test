// EDE.x : the provider registration of ExtendedDisplayEnabler 0.2.2, merged into Backport162 (0.7.5).
// Switch: ede_provider (default on). Setup: EDE_Setup(). Log lines (Backport162.debug): "ede: ...". Analysis: specs/EDE-MERGE-0.7.5.md.
//
// iPadOS 16.0 build 20A8372 still contains the whole Extended-display stack (SBSystemShellExtended* resolver / policy / controller classes, the
// SpringBoard._extendedDisplayControllerProvider ivar, Settings UI), but -[SpringBoard _completeStartupAfterMainSceneConnect:] no longer builds
// and registers the Extended provider (beta 5 did, behind SBChamoisExternalDisplayControllerIsEnabled()). Without it nothing reports windowing mode 1
// for an external display, so the display only mirrors and Settings hides Arrangement / Display Zoom. This file recreates the beta-5 registration:
//   EDEInstall       builds the factories and the SBSceneHostingDisplayControllerProvider and registers it with the display manager
//   EDEEarlyInstall  from the hook on -[SBDisplayManager registerDisplayControllerProvider:]: registered before the other providers, so a display that
//                    is already plugged in when SpringBoard starts is claimed by it
//   EDEAttempt       from the hook on -[SpringBoard _completeStartupAfterMainSceneConnect:]: late fallback, retried every 0.5 s (40 times) until the
//                    dependencies exist
//
// The other three selectors ExtendedDisplayEnabler hooked are NOT hooked here (one implementation only, in Group4Connect.m):
//   -[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:]                                  Group4Connect.m hk_setMirroring (mirrorsvc)
//   -[SBSystemShellExtendedDisplayControllerPolicy connectToDisplayController:displayConfiguration:]    Group4Connect.m hk_policyConnect (autoext)
//   -[SBExternalDisplayEducationObserver displayManager:didConnectToRootDisplay:]                       Group4Connect.m hk_eduConnect (autoext)
// The saved mirror / extended choice, the beta-5 default and the "ever enabled" flag live there too.
//
// Not carried over from ExtendedDisplayEnabler: its crash-loop guard (a CFPreferences strike counter that switched every hook off after 5 launches
// that died within 25 s, whatever the cause) and its own log / kill-switch / debug files. Backport162.off, Backport162.off.ede_provider,
// Backport162.debug and Backport162.log do those jobs now.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import "BP.h"

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"

// ---------------------------------------------------------------- switch, logging

#define EDE_ON() BP_OnName("ede_provider")
#define EDELog(fmt, ...) do { if (BP_LogEnabled()) BP_Log(@"ede: " fmt, ##__VA_ARGS__); } while (0)

static const int kMaxAttempts = 40;           // late-install retries, x 0.5 s

static id gProvider;                          // keeps the provider alive
static id gResolverFactory, gPolicyFactory;
static BOOL gInstalling;                      // re-entrancy guard for the early-install hook

// ---------------------------------------------------------------- helpers

#define EDE_MSG(ret, obj, sel, ...) ((ret (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)((obj), NSSelectorFromString(sel), ##__VA_ARGS__)

static BOOL EDEDisabled(void) {
    return !EDE_ON();                         // Backport162.off or Backport162.off.ede_provider
}

// Object ivar by name; nil when the ivar is missing or not an object (BP.h: object_getIvar on a scalar returns raw bits that ARC would retain).
static id EDEIvar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(obj), name);
    return BP_ObjIvar(obj, iv);
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

        id registry  = EDE_MSG(id, Registry, @"sharedInstance");
        id queue     = EDE_MSG(id, Queue, @"sharedInstance");
        id sceneMgr  = EDE_MSG(id, SceneMgr, @"sharedInstance");
        id localDefs = EDE_MSG(id, Defaults, @"localDefaults");
        id extDefs   = localDefs ? EDE_MSG(id, localDefs, @"externalDisplayDefaults") : nil;
        id rootSet   = EDE_MSG(id, Domain, @"rootSettings");
        id availSet  = rootSet ? EDE_MSG(id, rootSet, @"availabilitySettings") : nil;
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

        NSSet *ids = EDE_MSG(id, displayManager, @"connectedIdentities");
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
    if (EDEDisabled()) { EDELog(@"disabled (kill switch); not installing"); return; }
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

// ---------------------------------------------------------------- hooks

// Logos only emits @class for the hooked classes; ARC needs a visible @interface to message them.
@interface SpringBoard : UIApplication
@end
@interface SBDisplayManager : NSObject
@end

%group EDE_Provider

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

%end // EDE_Provider

// Call from Tweak.x's %ctor after BP_BuildMatches() succeeded and after the other *_Setup() calls.
void EDE_Setup(void);
void EDE_Setup(void) {
    if (!EDE_ON()) { EDELog(@"switch ede_provider is off at launch; the provider is not installed"); return; }
    %init(EDE_Provider);
    EDELog(@"loaded; provider hooks installed");
}
