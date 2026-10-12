// group3-plumbing.hooks.m
//
// DRAFT. Logos source (rename to .xm or paste into Tweak.x). Backports the portable parts of the iPadOS 16.2 (20C65)
// scene / window / input plumbing under Stage Manager to 16.0 (20A8372). Behaviour is specified in
// group3-plumbing.md (section numbers in the comments refer to it).
//
// Every piece is tagged  // PORTABLE,  // PARTIAL: <why>  or  // NOT PORTABLE: <why>.
//
// Integration with Tweak.x (do not paste blindly):
//   1. Feature switches (<jbroot>/tmp/Backport162.off.<name> turns one off): "g3handle", "g3snapshot", "g3topaff", "g3switcher", "g3canvas", "g3embedded"; opt-in (Backport162.on.<name>): "g3bootorient",
//      "g3embedded", "g3pip", "g3kbwindow", "g3statusbar", "g3preflight" ... see BP_G3_On() below (names are strings, no enum edit needed).
//   2. Call BP_G3_Setup() from the %ctor after the build check; it %init()s every group at the end of this file.
//   3. Compile with ARC (-fobjc-arc), like Tweak.x.
//
// Safety rules followed here (same as group4): no hard-coded ivar offsets (ivars are read by name with
// class_getInstanceVariable/object_getIvar and the code does nothing if missing), every private selector is guarded with
// respondsToSelector:, nil is never passed to objc_setAssociatedObject as an object, hooks are no-ops when their switch is off.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <dlfcn.h>
#import <unistd.h>
#import <time.h>

#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wunused-variable"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#import "BP.h"

// INTEGRATION: interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
// END INTEGRATION interfaces

// Per-feature switch, on by default, off when <jbroot>/tmp/Backport162.off(.<name>) exists. Checked at most once a second.
static BOOL BP_G3_On(const char *name) { return BP_OnName(name); }     // INTEGRATION: shared switches (BP.h)

// ------------------------------------------------------------------------------------------------ private interfaces
@interface NSObject (BPG3Private)
- (id)application;                                              // SBSceneHandle subclasses
- (id)info;                                                     // SBApplication
- (BOOL)isMedusaCapable;                                        // SBApplication
- (BOOL)_classicAppScaledPhoneOnPad;                            // SBApplication
- (BOOL)classicAppPhoneOnPadPrefersLandscape;                   // SBApplication (16.0 only)
- (BOOL)classicAppPhoneAppRunningOnPad;                         // SBApplication
- (id)_sceneDataStoreCreatingIfNecessary:(BOOL)create;          // SBSceneHandle (exists in 16.0)
- (id)bs_safeObjectForKey:(id)key ofType:(Class)type;           // BaseBoard NSDictionary category
- (id)safeObjectForKey:(id)key ofType:(Class)type;              // SpringBoard-local alias used by the 16.2 code
- (id)sceneIfExists;                                            // SBSceneHandle
- (id)_windowScene;                                             // SBDeviceApplicationSceneHandle
- (id)switcherController;                                       // SBWindowScene
- (BOOL)isChamoisWindowingUIEnabled;                            // SBSwitcherController
- (long long)currentInterfaceOrientation;                       // SBDeviceApplicationSceneHandle
- (long long)_interfaceOrientationFromUserResizing;             // %new below
- (void)_setInterfaceOrientationFromUserResizing:(long long)o;  // %new below
- (id)sceneHandle;                                              // SBDeviceApplicationSceneView
// INTEGRATION: selectors the draft sends to its own %new methods / to private classes
- (void)_setClassicAppPhoneOnPadPrefersLandscape:(BOOL)v;
- (void)_setSettingUpSceneOrientationRequest:(BOOL)v;
- (void)_setInitialDeviceOrientationFromSceneOrientationRequestSetup:(long long)o;
- (void)_setSupportedInterfaceOrientationsFromSceneOrientationRequestSetup:(unsigned long long)m;
- (void)_resetSceneOrientationRequestState;
- (id)uiClientSettings;
+ (id)mainWorkspace;
@end

// Classes we hook (declaration only; no @implementation, nothing is registered with the runtime).
@interface SBDeviceApplicationSceneHandle : NSObject
- (id)sceneIdentifier;
@end
@interface SBDeviceApplicationSceneView : UIView @end
@interface SBTraitsSceneParticipantDelegate : NSObject @end
@interface SBMedusaDecoratedDeviceApplicationSceneViewController : UIViewController @end
@interface SBSwitcherController : NSObject @end
@interface SBAbstractWindowSceneDelegate : NSObject @end
@interface SBSystemShellEmbeddedDisplayController : NSObject @end
@interface SpringBoard : UIApplication @end

// ------------------------------------------------------------------------------------------------ helpers
static id BP_G3_Ivar(id obj, const char *name) {
    if (!obj) return nil;
    Ivar iv = class_getInstanceVariable([obj class], name);
    if (!iv) return nil;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || enc[0] != '@') return nil;                       // object ivars only
    return object_getIvar(obj, iv);
}

// Associated-object slots.
static char kBPG3HostView, kBPG3Inspector;
@interface BPG3WeakBox : NSObject @property (nonatomic, weak) id obj; @end
@implementation BPG3WeakBox @end
static void BP_G3_SetWeak(id owner, const void *key, id obj) {
    if (!owner) return;
    if (!obj) { objc_setAssociatedObject(owner, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); return; }
    BPG3WeakBox *b = [BPG3WeakBox new]; b.obj = obj;
    objc_setAssociatedObject(owner, key, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static id BP_G3_GetWeak(id owner, const void *key) { return [(BPG3WeakBox *)objc_getAssociatedObject(owner, key) obj]; }

// ================================================================================================ SECTION 1: scene handle
// Section 1.1: new orientation state. Backed by the handle's scene data store (_sceneDataStoreCreatingIfNecessary: exists in 16.0).
static NSString *const kBPKeyUserResizing  = @"BP_SceneDataKeyInterfaceOrientationFromUserResizing";
static NSString *const kBPKeySettingUpReq  = @"BP_SceneDataKeySettingUpSceneOrientationRequest";
static NSString *const kBPKeyInitialDevOri = @"BP_SceneDataKeyInitialDeviceOrientationFromSceneOrientationRequestSetup";
static NSString *const kBPKeySupportedReq  = @"BP_SceneDataKeySupportedInterfaceOrientationsFromSceneOrientationRequestSetup";

static NSNumber *BP_G3_StoreGet(id handle, NSString *key) {
    if (![handle respondsToSelector:@selector(_sceneDataStoreCreatingIfNecessary:)]) return nil;
    id store = [handle _sceneDataStoreCreatingIfNecessary:NO];
    id v = [store respondsToSelector:@selector(objectForKey:)] ? [store objectForKey:key] : nil;
    return [v isKindOfClass:[NSNumber class]] ? v : nil;         // == safeObjectForKey:ofType:NSNumber
}
static void BP_G3_StoreSet(id handle, NSString *key, NSNumber *val) {
    if (!val || ![handle respondsToSelector:@selector(_sceneDataStoreCreatingIfNecessary:)]) return;
    id store = [handle _sceneDataStoreCreatingIfNecessary:YES];
    if ([store respondsToSelector:@selector(setObject:forKey:)]) [store setObject:val forKey:key];
}

static id BP_G3_SpringBoardApp(void) {
    Class c = NSClassFromString(@"UIApplication");
    return [c respondsToSelector:@selector(sharedApplication)] ? [c sharedApplication] : nil;
}
@interface NSObject (BPG3Launch)
- (long long)interfaceOrientationForCurrentDeviceOrientation:(BOOL)b;
- (long long)homeScreenRotationStyle;
- (long long)rawDeviceOrientationIgnoringOrientationLocks;
- (BOOL)builtOnOrAfterSDKVersion:(NSString *)v;
- (BOOL)_currentClassicModeAllowsLaunchingToAnySupportedOrientation;
- (BOOL)_mainSceneSupportsInterfaceOrientation:(long long)o;
- (long long)defaultInterfaceOrientation;
- (long long)_classicPhoneOnPadActivationOrientationForOrientation:(long long)o;
- (BOOL)classicAppPhoneAppRunningOnPad;
- (BOOL)isUserLocked;
+ (id)sharedInstance;
- (unsigned long long)supportedInterfaceOrientations;
- (long long)_defaultClassicMode;
- (BOOL)wantsLegacyFullscreenInterfaceOrientationBehaviors;
- (BOOL)supportsChamoisSceneResizing;
- (id)uiPresentationManager;
- (void)modifyDefaultPresentationContext:(id)block;
- (void)setPresentedLayerTypes:(unsigned long long)t;
@end


%group G3_Handle

%hook SBDeviceApplicationSceneHandle

// PORTABLE (16.2 0x1c76b8288 / 0x1c76b832c). On 16.0 the app-level value is the source of truth (all 16.0 consumers read it), so
// the handle accessor forwards to it; no per-scene storage.
%new
- (BOOL)_classicAppPhoneOnPadPrefersLandscape {
    id app = [self application];
    return [app respondsToSelector:@selector(classicAppPhoneOnPadPrefersLandscape)] ? [app classicAppPhoneOnPadPrefersLandscape] : NO;
}
%new
- (void)_setClassicAppPhoneOnPadPrefersLandscape:(BOOL)v {
    id app = [self application];
    if ([app respondsToSelector:@selector(_setClassicAppPhoneOnPadPrefersLandscape:)]) [app _setClassicAppPhoneOnPadPrefersLandscape:v];
}
// PORTABLE (16.2 0x1c76b83ec)
%new
- (BOOL)_classicAppPhoneOnPadSupportsOldStyleMixedOrientation {
    id app = [self application];
    if (![app respondsToSelector:@selector(_classicAppScaledPhoneOnPad)] || ![app _classicAppScaledPhoneOnPad]) return NO;
    id sc = [[self _windowScene] respondsToSelector:@selector(switcherController)] ? [[self _windowScene] switcherController] : nil;
    return ![sc respondsToSelector:@selector(isChamoisWindowingUIEnabled)] || ![sc isChamoisWindowingUIEnabled];
}

// PORTABLE (16.2 0x1c76b876c / 0x1c76b87f4)
%new
- (long long)_interfaceOrientationFromUserResizing { return [BP_G3_StoreGet(self, kBPKeyUserResizing) integerValue]; }
%new
- (void)_setInterfaceOrientationFromUserResizing:(long long)o { BP_G3_StoreSet(self, kBPKeyUserResizing, @(o)); }

// PORTABLE (16.2 0x1c76b8a44 .. 0x1c76b8b58, reset 0x1c76b8874)
%new
- (BOOL)_isSettingUpSceneOrientationRequest { return [BP_G3_StoreGet(self, kBPKeySettingUpReq) integerValue] != 0; }
%new
- (void)_setSettingUpSceneOrientationRequest:(BOOL)v { BP_G3_StoreSet(self, kBPKeySettingUpReq, @(v ? 1 : 0)); }
%new
- (long long)_initialDeviceOrientationFromSceneOrientationRequestSetup { return [BP_G3_StoreGet(self, kBPKeyInitialDevOri) integerValue]; }
%new
- (void)_setInitialDeviceOrientationFromSceneOrientationRequestSetup:(long long)o { BP_G3_StoreSet(self, kBPKeyInitialDevOri, @(o)); }
%new
- (unsigned long long)_supportedInterfaceOrientationsFromSceneOrientationRequestSetup { return [BP_G3_StoreGet(self, kBPKeySupportedReq) unsignedLongLongValue]; }
%new
- (void)_setSupportedInterfaceOrientationsFromSceneOrientationRequestSetup:(unsigned long long)m { BP_G3_StoreSet(self, kBPKeySupportedReq, @(m)); }
%new
- (void)_resetSceneOrientationRequestState {
    [self _setSettingUpSceneOrientationRequest:NO];
    [self _setInitialDeviceOrientationFromSceneOrientationRequestSetup:0];
    [self _setSupportedInterfaceOrientationsFromSceneOrientationRequestSetup:0];
}

// ---- orientation selection (section 1.2).  The user-resize value is set by the G3B chain (g3b_orient / g3b_guide) and by G1B/G1C responses.

// 16.0 0x1c5e73fe0 / 16.2 0x1c72e6e94.  FULL 16.2 body (not %orig + a flag): 16.2 dropped the 16.0 "Stage Manager + phone app on pad -> portrait" branch for
// Medusa-capable apps and gives classic apps the user-resize orientation first.  Everything else is the 16.0 algorithm, restated here.
- (long long)_launchingInterfaceOrientationForOrientation:(long long)o {
    if (!BP_G3_On("g3handle") || [self currentInterfaceOrientation] != 0) {       // a running app: 16.0 and 16.2 both raise the same NSAssert, keep it
        return %orig;
    }
    id app = [self application];
    id sbApp = BP_G3_SpringBoardApp();
    if (o == 0) o = [sbApp interfaceOrientationForCurrentDeviceOrientation:YES];
    BOOL useO = NO;
    if ([app isMedusaCapable]) {
        useO = YES;
    } else {
        BOOL rotStyle = [sbApp homeScreenRotationStyle] != 0;
        BOOL sdkOK = rotStyle || [[app info] builtOnOrAfterSDKVersion:@"8.0"];
        BOOL anyOK = [self _currentClassicModeAllowsLaunchingToAnySupportedOrientation];
        BOOL supports = [self _mainSceneSupportsInterfaceOrientation:o];
        long long r = [self _interfaceOrientationFromUserResizing];                // NEW in 16.2
        if (r != 0) return r;
        if (sdkOK && anyOK) {
            if (supports) {
                useO = YES;
            } else {
                Class lockC = NSClassFromString(@"SBOrientationLockManager");
                if ([[lockC sharedInstance] isUserLocked]) {
                    long long raw = [sbApp rawDeviceOrientationIgnoringOrientationLocks];
                    if (raw >= 1 && raw <= 4 && raw != o && [self _mainSceneSupportsInterfaceOrientation:raw]) return raw;
                }
            }
        } else if ([app classicAppPhoneAppRunningOnPad]) {
            o = [self _classicPhoneOnPadActivationOrientationForOrientation:o];
            useO = YES;
        }
    }
    if (useO && o != 0) return o;
    o = [self defaultInterfaceOrientation];
    if (o == 0) { NSLog(@"No fallback orientation for '%@'!", [self sceneIdentifier]); o = 1; }
    return o;
}
// 16.0 0x1c5e37cc0 / 16.2 0x1c72aa11c.  FULL 16.2 body: Medusa-capable apps always support all four orientations (16.0 narrowed this for phone apps in
// Stage Manager and unioned the legacy-fullscreen / Monarch masks for classic apps).
- (unsigned long long)_mainSceneSupportedInterfaceOrientations {
    if (!BP_G3_On("g3handle")) return %orig;
    id app = [self application];
    unsigned long long mask = [[app info] supportedInterfaceOrientations];
    if ([app isMedusaCapable]) return 0x1e;
    id scene = [self sceneIfExists];
    if (scene) mask = [[scene uiClientSettings] supportedInterfaceOrientations];
    return mask;
}
// 16.0 0x1c62253b4 / 16.2 0x1c76b5e24 and 16.0 0x1c6225328 / 16.2 0x1c76b5dac: with no scene yet 16.2 derives mode/events from the classic mode only
// (16.0 also consulted wantsLegacyFullscreenInterfaceOrientationBehaviors and _SBPostModernRotationEnabled).  _SBApplicationClassicModeIsClassic(m) = (m + 1) > 1.
- (long long)_interfaceOrientationMode {
    if (!BP_G3_On("g3handle") || [self sceneIfExists]) return %orig;
    unsigned long long m = (unsigned long long)[(id)[self application] _defaultClassicMode];
    return (m + 1 > 1) ? 1 : 2;
}
- (BOOL)wantsDeviceOrientationEventsEnabled {
    if (!BP_G3_On("g3handle") || [self sceneIfExists]) return %orig;
    unsigned long long m = (unsigned long long)[(id)[self application] _defaultClassicMode];
    return m + 1 > 1;
}
// 16.0 0x1c5e3df60 / 16.2 0x1c72b0354: the early-out is "app cannot be resized in Stage Manager" (16.0: "app is classic").
- (void)setKeyboardContextMaskStyle:(unsigned long long)style {
    if (!BP_G3_On("g3handle")) {
        %orig;
        return;
    }
    if (![[self application] supportsChamoisSceneResizing] && style == 2) return;
    Ivar iv = class_getInstanceVariable([self class], "_keyboardLayerMaskStyle");
    if (iv) *(unsigned long long *)((char *)(__bridge void *)self + ivar_getOffset(iv)) = style;
    [[[self sceneIfExists] uiPresentationManager] modifyDefaultPresentationContext:^(id ctx) { [ctx setPresentedLayerTypes:style]; }];   // 16.2 block 0x1c76b60f0
}
// 16.0 0x1c5e58d94 / 16.2 0x1c72cb524: with a user-resize orientation set, an already running scene keeps its current orientation.
- (long long)activationInterfaceOrientationForOrientation:(long long)o {
    if (BP_G3_On("g3handle")) {
        long long cur = [self currentInterfaceOrientation];
        if (cur != 0 && [self _interfaceOrientationFromUserResizing] != 0) return cur;
    }
    return %orig;
}
// 16.0 0x1c5e9d524 / 16.2 0x1c73101d0: user-resize orientation wins when resuming (scene must exist, o != 0, as the 16.2 asserts).
- (long long)_resumingInterfaceOrientationForOrientation:(long long)o {
    if (BP_G3_On("g3handle") && o != 0 && [self sceneIfExists]) {
        long long r = [self _interfaceOrientationFromUserResizing];
        if (r != 0) return r;
    }
    return %orig;
}

// 16.2 0x1c72afca0: reset the orientation-request state when the scene stops being effectively foreground.
// PARTIAL: reads the 16.0 ivar _isEffectivelyForeground by name before/after %orig.
- (void)_didUpdateSettingsWithDiff:(id)diff previousSettings:(id)prev {
    BOOL was = NO; Ivar iv = class_getInstanceVariable([self class], "_isEffectivelyForeground");
    if (iv) { ptrdiff_t off = ivar_getOffset(iv); was = *((BOOL *)((char *)(__bridge void *)self + off)); }
    %orig;
    if (iv && BP_G3_On("g3handle")) {
        ptrdiff_t off = ivar_getOffset(iv); BOOL now = *((BOOL *)((char *)(__bridge void *)self + off));
        if (was != now && !now) [self _resetSceneOrientationRequestState];
    }
}

// 16.0 0x1c5e473d0 / 16.2 0x1c72b9430: 16.2 drives the client-settings handling from a UIApplicationSceneClientSettingsDiffInspector kept on the handle
// (ivar _clientSettingsInspector, not available on 16.0: associated object).  Its supportedInterfaceOrientations observer (block type v16@?0^v8) forgets the
// user-resize orientation when the app stops supporting it.  The visibleMiniAlertCount observer of 16.2 does what 16.0's own body already does (%orig).
- (void)_didUpdateClientSettingsWithDiff:(id)diff transitionContext:(id)ctx {
    %orig;
    if (!BP_G3_On("g3handle")) return;
    Class inspC = NSClassFromString(@"UIApplicationSceneClientSettingsDiffInspector");
    if (!inspC || ![inspC instancesRespondToSelector:@selector(observeSupportedInterfaceOrientationsWithBlock:)]) return;
    id insp = objc_getAssociatedObject(self, &kBPG3Inspector);
    if (!insp) {
        insp = [inspC new];
        __weak id w = self;
        ((void (*)(id, SEL, id))objc_msgSend)(insp, @selector(observeSupportedInterfaceOrientationsWithBlock:), ^(void *unused) {
            id me = w;
            if (!me) return;
            id scene = [me sceneIfExists];
            unsigned long long sup = [[scene uiClientSettings] supportedInterfaceOrientations];
            if (!(sup & (1ull << [me _interfaceOrientationFromUserResizing]))) [me _setInterfaceOrientationFromUserResizing:0];   // _SBFInterfaceOrientationMaskContainsInterfaceOrientation
        });
        objc_setAssociatedObject(self, &kBPG3Inspector, insp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    ((void (*)(id, SEL, id, void *))objc_msgSend)(insp, NSSelectorFromString(@"inspectDiff:withContext:"), diff, (__bridge void *)ctx);
}

%end // SBDeviceApplicationSceneHandle

// Section 1.3. 16.2 -[SBTraitsSceneOrientationRequestAssistant _startSceneOrientationRequestWithDesiredOrientations:error:]
// clears the user-resize orientation. PARTIAL: only meaningful together with the setter chain.
%hook SBTraitsSceneParticipantDelegate
- (void)_startAlterEgoWithDesiredOrientations:(unsigned long long)m error:(id *)err {
    %orig;
    if (!BP_G3_On("g3handle")) return;
    id h = BP_G3_Ivar(self, "_sceneHandle");
    if ([h respondsToSelector:@selector(_setInterfaceOrientationFromUserResizing:)]) [h _setInterfaceOrientationFromUserResizing:0];
}
%end

%end // G3_Handle

// ================================================================================================ SECTION 1.6: snapshot hosting info
// 16.0 sets the scene's hostContextIdentifierForSnapshotting / renderId once, in -_configureSceneLiveHostView: (via the handle's
// -_updateSceneHostingInfoForSnapshottingWithView: 0x1c6226eb4, which reads [[host _window] _contextId]).  16.2 replaces that by an ASSERTION STACK on the
// handle (_snapshottingInfoAssertions / _currentSnapshottingInfoAssertion) and refreshes it from -[SBDeviceApplicationSceneView didMoveToWindow]:
//   handle  -_sceneHostingInfoForSnapshottingAssertionWithView:  0x1c76b7acc  (nil when the view or its window is nil; ctx = [[view window] _contextId],
//                                                                   render id = CALayerGetRenderId([view layer]); name "%@-%lu-%lu"; adds it to the stack)
//   handle  -_addSnapshottingInfoAssertion:                       0x1c76b7ce8  (append, current = a, update(force:YES))
//   handle  -_removeSnapshottingInfoAssertion:                    0x1c76b7d90  (remove; only if it was current: current = lastObject, update(force:NO))
//   handle  -_updateSceneHostingInfoForSnapshottingWithAssertion:forceUpdate: 0x1c76b7964 (scene valid; write ctx/render id unless unchanged and !force)
//   view    -_configureSceneLiveHostView: 0x1c773ef38  : invalidate the old assertion, assertion = [handle ...WithView:host]
//   view    -_invalidateSceneLiveHostView: 0x1c773f00c : host = nil, [assertion invalidate]
//   view    -didMoveToWindow 0x1c773d7c8              : if host: new = [handle ...WithView:host]; old = assertion; assertion = new; [old invalidate]
// The handle's 16.0 method is replaced by the above (it is only called from the two view methods), the whole 16.2 stack is implemented.
// The 16.2 value of "contextId 0 when the last hosting view left its window" is reproduced: removing the current assertion with an empty stack
// updates the settings with a nil assertion (ctx 0, render id 0).

@interface BPG3SnapAssertion : NSObject
@property (nonatomic) unsigned int contextId;
@property (nonatomic) unsigned long long renderId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) void (^invalidationBlock)(BPG3SnapAssertion *);
- (void)invalidate;
@end
@implementation BPG3SnapAssertion {
    BOOL _invalidated;
}
- (void)invalidate {                       // BSSimpleAssertion semantics: the invalidation block runs once
    if (_invalidated) return;
    _invalidated = YES;
    void (^b)(BPG3SnapAssertion *) = _invalidationBlock;
    _invalidationBlock = nil;
    if (b) b(self);
}
@end

static char kBPG3SnapStack, kBPG3SnapCurrent, kBPG3SnapViewAssertion;

@interface NSObject (BPG3Snapshot)
- (id)sceneIdentifier;
- (id)uiSettings;
- (BOOL)isValid;
- (unsigned int)_contextId;
- (void)updateUISettingsWithBlock:(id)block;
- (unsigned int)hostContextIdentifierForSnapshotting;
- (unsigned long long)scenePresenterRenderIdentifierForSnapshotting;
- (void)setHostContextIdentifierForSnapshotting:(unsigned int)c;
- (void)setScenePresenterRenderIdentifierForSnapshotting:(unsigned long long)r;
- (id)_sceneHostingInfoForSnapshottingAssertionWithView:(id)v;
- (void)_addSnapshottingInfoAssertion:(id)a;
- (void)_removeSnapshottingInfoAssertion:(id)a;
- (void)_updateSceneHostingInfoForSnapshottingWithAssertion:(id)a forceUpdate:(BOOL)f;
@end

static unsigned long long BP_G3_LayerRenderId(id layer) {
    static unsigned long long (*fn)(id); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (unsigned long long (*)(id))dlsym(RTLD_DEFAULT, "CALayerGetRenderId"); });
    if (!fn) { BP_Log(@"[g3snapshot] CALayerGetRenderId not found, render id 0"); return 0; }
    return fn(layer);
}

%group G3_Snapshot
%hook SBDeviceApplicationSceneHandle

// 16.0 0x1c6226eb4.  Replaced by the 16.2 assertion stack (the view hooks below drive it); only called from the view's configure/invalidate.
- (void)_updateSceneHostingInfoForSnapshottingWithView:(id)v {
    if (!BP_G3_On("g3snapshot")) {
        %orig;
        return;
    }
}

%new
- (id)_sceneHostingInfoForSnapshottingAssertionWithView:(id)view {          // 16.2 0x1c76b7acc
    id w = [view respondsToSelector:@selector(window)] ? [view window] : nil;
    if (!view || !w) return nil;
    unsigned int ctx = [w _contextId];
    unsigned long long rid = BP_G3_LayerRenderId([view layer]);
    NSString *name = [NSString stringWithFormat:@"%@-%lu-%lu", [self sceneIdentifier], (unsigned long)ctx, (unsigned long)rid];
    __weak id ws = self;
    BPG3SnapAssertion *a = [BPG3SnapAssertion new];
    a.name = name; a.contextId = ctx; a.renderId = rid;
    a.invalidationBlock = ^(BPG3SnapAssertion *x) { id me = ws; if (me) [me _removeSnapshottingInfoAssertion:x]; };
    [self _addSnapshottingInfoAssertion:a];
    return a;
}
%new
- (void)_addSnapshottingInfoAssertion:(id)a {                                  // 16.2 0x1c76b7ce8
    NSMutableArray *stack = objc_getAssociatedObject(self, &kBPG3SnapStack);
    if (!stack) { stack = [NSMutableArray array]; objc_setAssociatedObject(self, &kBPG3SnapStack, stack, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    [stack addObject:a];
    BP_G3_SetWeak(self, &kBPG3SnapCurrent, a);
    [self _updateSceneHostingInfoForSnapshottingWithAssertion:a forceUpdate:YES];
}
%new
- (void)_removeSnapshottingInfoAssertion:(id)a {                               // 16.2 0x1c76b7d90
    NSMutableArray *stack = objc_getAssociatedObject(self, &kBPG3SnapStack);
    [stack removeObject:a];
    id cur = BP_G3_GetWeak(self, &kBPG3SnapCurrent);
    if (cur != a) return;
    id last = [stack lastObject];
    BP_G3_SetWeak(self, &kBPG3SnapCurrent, last);
    [self _updateSceneHostingInfoForSnapshottingWithAssertion:last forceUpdate:NO];
}
%new
- (void)_updateSceneHostingInfoForSnapshottingWithAssertion:(id)a forceUpdate:(BOOL)force {   // 16.2 0x1c76b7964
    id scene = [self respondsToSelector:@selector(sceneIfExists)] ? [self sceneIfExists] : nil;
    if (![scene isValid]) return;
    unsigned int ctx = a ? [(BPG3SnapAssertion *)a contextId] : 0;
    unsigned long long rid = a ? [(BPG3SnapAssertion *)a renderId] : 0;
    id ui = [scene uiSettings];
    if (!force && [ui hostContextIdentifierForSnapshotting] == ctx && [ui scenePresenterRenderIdentifierForSnapshotting] == rid) return;
    [scene updateUISettingsWithBlock:^(id s) {                                   // 16.2 block 0x1c76b7a70
        [s setHostContextIdentifierForSnapshotting:ctx];
        [s setScenePresenterRenderIdentifierForSnapshotting:rid];
    }];
}

%end

%hook SBDeviceApplicationSceneView
- (void)_configureSceneLiveHostView:(id)host {                                  // 16.2 0x1c773ef38
    %orig;
    if (host) BP_G3_SetWeak(self, &kBPG3HostView, host);
    if (!BP_G3_On("g3snapshot")) return;
    id h = [self respondsToSelector:@selector(sceneHandle)] ? [self sceneHandle] : nil;
    if (![h respondsToSelector:@selector(_sceneHostingInfoForSnapshottingAssertionWithView:)]) return;
    [(BPG3SnapAssertion *)objc_getAssociatedObject(self, &kBPG3SnapViewAssertion) invalidate];
    id a = [h _sceneHostingInfoForSnapshottingAssertionWithView:host];
    objc_setAssociatedObject(self, &kBPG3SnapViewAssertion, a, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)_invalidateSceneLiveHostView:(id)host {                                 // 16.2 0x1c773f00c
    %orig;
    BP_G3_SetWeak(self, &kBPG3HostView, nil);
    BPG3SnapAssertion *a = objc_getAssociatedObject(self, &kBPG3SnapViewAssertion);
    [a invalidate];
    objc_setAssociatedObject(self, &kBPG3SnapViewAssertion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (void)didMoveToWindow {                                                       // 16.2 0x1c773d7c8
    %orig;
    if (!BP_G3_On("g3snapshot")) return;
    id host = BP_G3_GetWeak(self, &kBPG3HostView);
    if (!host) return;
    id h = [self respondsToSelector:@selector(sceneHandle)] ? [self sceneHandle] : nil;
    if (![h respondsToSelector:@selector(_sceneHostingInfoForSnapshottingAssertionWithView:)]) return;
    id nw = [h _sceneHostingInfoForSnapshottingAssertionWithView:host];
    BPG3SnapAssertion *old = objc_getAssociatedObject(self, &kBPG3SnapViewAssertion);
    objc_setAssociatedObject(self, &kBPG3SnapViewAssertion, nw, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [old invalidate];
}
%end

%end // G3_Snapshot

// ================================================================================================ SECTION 2: decorated scene VC
// opt-in switch <jbroot>/tmp/Backport162.on.<name>
static BOOL BP_G3_OptIn(const char *name) { return BP_OnName(name); }     // default ON (kill switch Backport162.off.<name>)
static NSString *const kBPG3WMStyleNote = @"SBSwitcherControllerWindowManagementStyleDidChangeNotification";   // 16.2 extern NSString const

static id BP_G3_SBApp(void) {
    Class c = NSClassFromString(@"UIApplication");
    return [c respondsToSelector:@selector(sharedApplication)] ? [c sharedApplication] : nil;
}
static id BP_G3_KVC(id obj, NSString *key) {      // ivar by name, never throws
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

@interface NSObject (BPG3Decorated)
- (BOOL)isViewLoaded;
- (id)topAffordanceView;
- (id)view;
- (void)setHighlighted:(BOOL)h;
- (BOOL)isHardwareKeyboardAttached;
- (id)windowSceneManager;
- (id)connectedWindowScenes;
- (void)_createOrDestroyTopAffordanceViewControllerAnimated:(BOOL)a;
- (void)updateTopAffordanceOverrideUserInterfaceStyle;
- (void)updateContextMenuWithLayoutRole:(long long)r spaceConfiguration:(long long)s floatingConfiguration:(long long)f interfaceOrientation:(long long)o isZoomed:(BOOL)z;
- (void)_windowManagementStyleDidChange:(NSNotification *)n;
@end

%group G3_DecoratedVC

%hook SBMedusaDecoratedDeviceApplicationSceneViewController

// PORTABLE, section 2.3 (16.2 0x1c77d0de8): top affordance highlight also when more than one display is connected.
- (void)_updateTopAffordanceHighlight {
    %orig;
    if (!BP_G3_On("g3topaff") || ![self isViewLoaded]) return;
    id vc = BP_G3_KVC(self, @"_topAffordanceViewController");
    if (!vc || [self topAffordanceView] == [vc view] || ![vc respondsToSelector:@selector(setHighlighted:)]) return;
    BOOL nub = [BP_G3_KVC(self, @"_nubViewHighlighted") boolValue];
    long long space = [BP_G3_KVC(self, @"_spaceConfiguration") longLongValue];
    long long floating = [BP_G3_KVC(self, @"_floatingConfiguration") longLongValue];
    BOOL isSplit = (unsigned long long)(space - 2) < 3;             // SBSpaceConfigurationIsSplitView (16.0 0x1c6289f58 / 16.2 0x1c77229d0)
    BOOL splitOrFloating = isSplit || (unsigned long long)(floating - 1) < 2;
    id app = BP_G3_SBApp();
    id wsm = [app respondsToSelector:@selector(windowSceneManager)] ? [app windowSceneManager] : nil;
    NSUInteger displays = [[wsm respondsToSelector:@selector(connectedWindowScenes)] ? [wsm connectedWindowScenes] : nil count];
    BOOL hw = [app respondsToSelector:@selector(isHardwareKeyboardAttached)] ? [app isHardwareKeyboardAttached] : NO;
    [vc setHighlighted:(nub && ((hw && splitOrFloating) || displays > 1))];
}

// PARTIAL, section 2.1: refresh the top affordance when Stage Manager is toggled (needs the poster in G3_SwitcherController).
- (id)initWithDeviceApplicationSceneHandle:(id)h layoutRole:(long long)r workspace:(id)w setupManager:(id)m {
    id me = %orig;
    if (me && BP_G3_On("g3topaff"))
        [[NSNotificationCenter defaultCenter] addObserver:me selector:@selector(_windowManagementStyleDidChange:) name:kBPG3WMStyleNote object:nil];
    return me;
}
%new
- (void)_windowManagementStyleDidChange:(NSNotification *)n {
    if (![self respondsToSelector:@selector(_createOrDestroyTopAffordanceViewControllerAnimated:)]) return;
    [self _createOrDestroyTopAffordanceViewControllerAnimated:YES];
    if ([self respondsToSelector:@selector(updateTopAffordanceOverrideUserInterfaceStyle)]) [self updateTopAffordanceOverrideUserInterfaceStyle];
    id vc = BP_G3_KVC(self, @"_topAffordanceViewController");
    id h = BP_G3_KVC(self, @"_deviceApplicationSceneHandle");
    if ([vc respondsToSelector:@selector(updateContextMenuWithLayoutRole:spaceConfiguration:floatingConfiguration:interfaceOrientation:isZoomed:)] && h)
        [vc updateContextMenuWithLayoutRole:[BP_G3_KVC(self, @"_layoutRole") longLongValue]
                          spaceConfiguration:[BP_G3_KVC(self, @"_spaceConfiguration") longLongValue]
                       floatingConfiguration:[BP_G3_KVC(self, @"_floatingConfiguration") longLongValue]
                        interfaceOrientation:[h currentInterfaceOrientation]
                                    isZoomed:[BP_G3_KVC(self, @"_isZoomed") boolValue]];
}

%end
%end // G3_DecoratedVC

// ================================================================================================ SECTION 3: SBSwitcherController
static NSString *const kBPG3CanvasNote = @"SBWindowSceneCanvasSizeDidChangeNotification";    // 16.2 extern NSString const

static BOOL BP_G3_BoolIvar(id obj, const char *name, BOOL *out) {
    Ivar iv = obj ? class_getInstanceVariable([obj class], name) : NULL;
    if (!iv) return NO;
    const char *enc = ivar_getTypeEncoding(iv);
    if (!enc || (enc[0] != 'B' && enc[0] != 'c')) return NO;
    *out = *((BOOL *)((char *)(__bridge void *)obj + ivar_getOffset(iv)));
    return YES;
}
static CGSize BP_G3_CanvasSize(long long orientation, id coordinateSpace) {      // block 16.2 0x1c7487b84
    CGSize sz = CGSizeZero;
    if ([coordinateSpace respondsToSelector:@selector(bounds)]) sz = ((CGRect (*)(id, SEL))objc_msgSend)(coordinateSpace, @selector(bounds)).size;
    return (orientation == 3 || orientation == 4) ? CGSizeMake(sz.height, sz.width) : sz;
}

@interface NSObject (BPG3Switcher)
- (void)failMultitaskingGesturesForReason:(NSString *)r;
- (id)layoutState;
- (long long)unlockedEnvironmentMode;
- (id)_fbsDisplayConfiguration;
- (id)coordinateSpace;
- (long long)interfaceOrientation;
- (void)setEventLabel:(NSString *)l;
- (void)modifyApplicationContext:(id)block;
- (void)setRequestedUnlockedEnvironmentMode:(long long)m;
- (BOOL)requestTransitionWithOptions:(unsigned long long)o displayConfiguration:(id)c builder:(id)b validator:(id)v;
- (void)_handleDisplayCanvasSizeChange:(NSNotification *)n;
@end

%group G3_Switcher

%hook SBSwitcherController

// PARTIAL, section 3.1. Will-callback of 16.2 (the "Did" rebuild does not exist in 16.0) plus the style-change poster that
// 16.2's SBFluidSwitcherViewController default-change handler provides to the observers added in section 2.1.
- (void)setChamoisWindowingUIEnabled:(BOOL)enabled {
    BOOL cur = NO;
    BOOL known = BP_G3_BoolIvar(self, "_chamoisWindowingUIEnabled", &cur);
    BOOL changing = known && cur != enabled;
    if (changing && BP_G3_On("g3switcher")) {
        id coord = BP_G3_Ivar(self, "_switcherCoordinator");
        if ([coord respondsToSelector:@selector(failMultitaskingGesturesForReason:)])
            [coord failMultitaskingGesturesForReason:@"Window management style is changing"];
    }
    %orig;
    if (changing && BP_G3_On("g3switcher")) {
        __weak id weakSelf = self;
        void (^post)(void) = ^{ id me = weakSelf; if (me) [[NSNotificationCenter defaultCenter] postNotificationName:kBPG3WMStyleNote object:me]; };
        if ([NSThread isMainThread]) post(); else dispatch_async(dispatch_get_main_queue(), post);
    }
}

// PORTABLE, section 3.2: observer for canvas size changes of this switcher's window scene.
- (id)initWithWindowScene:(id)scene switcherCoordinator:(id)coordinator {
    id me = %orig;
    if (me && scene && BP_G3_On("g3canvas"))
        [[NSNotificationCenter defaultCenter] addObserver:me selector:@selector(_handleDisplayCanvasSizeChange:) name:kBPG3CanvasNote object:scene];
    return me;
}
%new
- (void)_handleDisplayCanvasSizeChange:(NSNotification *)n {                                  // 16.2 0x1c7607898
    if (!BP_G3_On("g3canvas")) return;
    id scene = BP_G3_Ivar(self, "_windowScene");
    Class wsC = NSClassFromString(@"SBWorkspace");
    id ws = [wsC respondsToSelector:@selector(mainWorkspace)] ? [wsC mainWorkspace] : nil;
    if (!scene || ![ws respondsToSelector:@selector(requestTransitionWithOptions:displayConfiguration:builder:validator:)]
        || ![scene respondsToSelector:@selector(_fbsDisplayConfiguration)]) return;
    __weak id weakSelf = self;
    [ws requestTransitionWithOptions:0 displayConfiguration:[scene _fbsDisplayConfiguration]
        builder:^(id req) { if ([req respondsToSelector:@selector(setEventLabel:)]) [req setEventLabel:@"DisplayCanvasSizeChange"]; }
        validator:^BOOL(id req) {
            id me = weakSelf;
            if (![me respondsToSelector:@selector(isChamoisWindowingUIEnabled)] || ![me isChamoisWindowingUIEnabled]) return NO;
            id ls = [me respondsToSelector:@selector(layoutState)] ? [me layoutState] : nil;
            if (ls && [req respondsToSelector:@selector(modifyApplicationContext:)] && [ls respondsToSelector:@selector(unlockedEnvironmentMode)]) {
                long long mode = [ls unlockedEnvironmentMode];
                [req modifyApplicationContext:^(id ctx) { if ([ctx respondsToSelector:@selector(setRequestedUnlockedEnvironmentMode:)]) [ctx setRequestedUnlockedEnvironmentMode:mode]; }];
            }
            return YES; }];
}
%end

// Poster for the canvas notification: UIKit calls this UIWindowSceneDelegate method; 16.0 SBAbstractWindowSceneDelegate does not implement it.
%hook SBAbstractWindowSceneDelegate
%new
- (void)windowScene:(id)scene didUpdateCoordinateSpace:(id)space interfaceOrientation:(long long)orientation traitCollection:(id)traits {   // 16.2 0x1c74879ac
    if (!scene || !BP_G3_On("g3canvas")) return;
    // UIKit's parameters are the PREVIOUS space/orientation; the scene's own properties are the current ones (16.2 compares them the same way)
    CGSize newSz = BP_G3_CanvasSize([scene interfaceOrientation], [scene coordinateSpace]);
    CGSize oldSz = BP_G3_CanvasSize(orientation, space);
    if (!CGSizeEqualToSize(oldSz, newSz)) {
        BP_Log(@"canvas size %@ -> %@", NSStringFromCGSize(oldSz), NSStringFromCGSize(newSz));
        [[NSNotificationCenter defaultCenter] postNotificationName:kBPG3CanvasNote object:scene];
    }
}
%end

%end // G3_Switcher

// ================================================================================================ SECTION 6: embedded display controller, boot orientation
@interface NSObject (BPG3Embedded)
- (BOOL)chamoisWindowingEnabled;                    // SBAppSwitcherDefaults
- (void)updateSettingsWithBlock:(id)block;          // FBScene
- (id)settings;
- (BOOL)enhancedWindowingEnabled;
- (void)setEnhancedWindowingEnabled:(BOOL)e;
- (void)_bpUpdateSceneSettings;
@end

static void BP_G3_ApplyEnhancedWindowing(id controller, id scene) {
    if (!scene) return;
    id defaults = BP_G3_Ivar(controller, "_appSwitcherDefaults");
    if (![defaults respondsToSelector:@selector(chamoisWindowingEnabled)]) return;
    BOOL e = [defaults chamoisWindowingEnabled];
    id cur = [scene respondsToSelector:@selector(settings)] ? [scene settings] : nil;
    if (![cur respondsToSelector:@selector(enhancedWindowingEnabled)] || [cur enhancedWindowingEnabled] == e) return;   // already in sync
    if (![scene respondsToSelector:@selector(updateSettingsWithBlock:)]) return;
    [scene updateSettingsWithBlock:^(id s) { if ([s respondsToSelector:@selector(setEnhancedWindowingEnabled:)]) [s setEnhancedWindowingEnabled:e]; }];
}

%group G3_Embedded
%hook SBSystemShellEmbeddedDisplayController

// PORTABLE, section 6.1 (16.2 block 0x1c75ace88)
- (id)_createSystemShellSceneWithOrientation:(long long)o {
    id scene = %orig;
    if (BP_G3_On("g3embedded")) BP_G3_ApplyEnhancedWindowing(self, scene);
    return scene;
}
// PORTABLE, section 6.1: follow Stage Manager toggles (16.2 _updateSceneSettings 0x1c75ad1c0, called from the defaults observer block)
- (void)connectToDisplayIdentity:(id)identity configuration:(id)cfg displayManager:(id)dm sceneManager:(id)sm caDisplayQueue:(id)q assertion:(id)a {
    %orig;
    if (BP_G3_On("g3embedded"))
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_bpUpdateSceneSettings) name:kBPG3WMStyleNote object:nil];
}
%new
- (void)_bpUpdateSceneSettings { if (BP_G3_On("g3embedded")) BP_G3_ApplyEnhancedWindowing(self, BP_G3_Ivar(self, "_scene")); }
%end

// Section 6.2: 16.2 -[SpringBoard _bootOrientation] 0x1c734a544 and -[SBTraitsEmbeddedDisplayPipelineManager _bootOrientation] 0x1c75b74a0 (same body):
//   switch (MGGetSInt32Answer("DisplayBootRotation", -1)) { 0: 1; 90: 3; 180: 2; 270: 4; default: 0 }   (the compiled form is: w > 0xb3 ? (w == 270 ? 4 : 0) : (w == 180 ? 2 : (w == 0 ? 1 : (w == 90 ? 3 : 0))))
// -[SpringBoard startupInterfaceOrientation]: 16.0 0x1c5ed5ba0 / 16.2 0x1c734a2d4 are the same function except for the iPad idiom branch (idiom 1 or 5):
//   16.0: o = overlay orientation (BKSDisplayRenderOverlay existingOverlayForDisplay:[CADisplay mainDisplay]), 0 if none; if BSInterfaceOrientationIsValid(o) use it, else BKHIDServicesGetNonFlatDeviceOrientation()
//   16.2: the same, but the not-valid case is  b = [self _bootOrientation]; o = b ? b : BKHIDServicesGetNonFlatDeviceOrientation()
// i.e. a valid boot-progress overlay orientation still wins in 16.2; the panel's boot rotation replaces only the non-flat fallback.  Other idioms: unchanged (%orig).
// -[SBTraitsEmbeddedDisplayPipelineManager setupDefaultPipelineForArbiter:] (16.2 0x1c75b52bc, tail at 0x1c75b55c0): on the iPad idiom
//   b = [self _bootOrientation]; if (b) { [self _addLastNonFlatOverrideInputsValidatorIfNeeded]; [_lastNonFlatOverrideInputsValidator setLastNonFlatOrientationOverride:b]; }
static long long BP_G3_BootOrientationValue(void) {
    static int32_t (*mg)(CFStringRef, int32_t); static dispatch_once_t once;
    dispatch_once(&once, ^{ mg = (int32_t (*)(CFStringRef, int32_t))dlsym(RTLD_DEFAULT, "MGGetSInt32Answer"); });
    if (!mg) { BP_Log(@"[g3bootorient] MGGetSInt32Answer not found"); return 0; }
    int32_t w = mg(CFSTR("DisplayBootRotation"), -1);
    if (w > 0xb3) return w == 270 ? 4 : 0;
    if (w == 180) return 2;
    if (w == 0) return 1;
    return w == 90 ? 3 : 0;
}
static BOOL BP_G3_IsPadIdiom(void) {
    long long idiom = (long long)[[UIDevice currentDevice] userInterfaceIdiom];
    return (idiom & ~4ll) == 1;
}
@interface NSObject (BPG3Boot)
- (long long)_bootOrientation;
- (void)_addLastNonFlatOverrideInputsValidatorIfNeeded;
- (void)setLastNonFlatOrientationOverride:(long long)o;
+ (id)existingOverlayForDisplay:(id)d;
+ (id)mainDisplay;
@end
@interface SBTraitsEmbeddedDisplayPipelineManager : NSObject @end

%hook SpringBoard
%new
- (long long)_bootOrientation { return BP_G3_BootOrientationValue(); }
- (long long)startupInterfaceOrientation {
    if (!BP_G3_On("g3bootorient") || !BP_G3_IsPadIdiom()) return %orig;
    Class ovC = NSClassFromString(@"BKSDisplayRenderOverlay"), dispC = NSClassFromString(@"CADisplay");
    id overlay = ([ovC respondsToSelector:@selector(existingOverlayForDisplay:)] && [dispC respondsToSelector:@selector(mainDisplay)])
        ? [ovC existingOverlayForDisplay:[dispC mainDisplay]] : nil;
    long long o = [overlay respondsToSelector:@selector(interfaceOrientation)] ? [(id)overlay interfaceOrientation] : 0;
    if (o >= 1 && o <= 4) return o;                                    // BSInterfaceOrientationIsValid
    long long b = BP_G3_BootOrientationValue();
    if (b) return b;
    static long long (*nonFlat)(void); static dispatch_once_t once;
    dispatch_once(&once, ^{ nonFlat = (long long (*)(void))dlsym(RTLD_DEFAULT, "BKHIDServicesGetNonFlatDeviceOrientation"); });
    if (nonFlat) return nonFlat();
    BP_Log(@"[g3bootorient] BKHIDServicesGetNonFlatDeviceOrientation not found, stock startup orientation");
    return %orig;
}
%end

%hook SBTraitsEmbeddedDisplayPipelineManager
%new
- (long long)_bootOrientation { return BP_G3_BootOrientationValue(); }
- (void)setupDefaultPipelineForArbiter:(id)arbiter {
    %orig;
    if (!BP_G3_On("g3bootorient") || !BP_G3_IsPadIdiom()) return;
    long long b = [self _bootOrientation];
    if (!b) return;
    [self _addLastNonFlatOverrideInputsValidatorIfNeeded];
    id v = BP_G3_Ivar(self, "_lastNonFlatOverrideInputsValidator");
    if ([v respondsToSelector:@selector(setLastNonFlatOrientationOverride:)]) [v setLastNonFlatOrientationOverride:b];
}
%end
%end // G3_Embedded

// ==== SETUP BEGIN
void BP_G3_Setup(void) {
    %init(G3_Handle);
    %init(G3_Snapshot);
    %init(G3_DecoratedVC);
    %init(G3_Switcher);
    %init(G3_Embedded);
}
// ==== SETUP END
