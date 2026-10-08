// group3-plumbing.hooks.m
//
// DRAFT. Logos source (rename to .xm or paste into Tweak.x). Backports the portable parts of the iPadOS 16.2 (20C65)
// scene / window / input plumbing under Stage Manager to 16.0 (20A8372). Behaviour is specified in
// group3-plumbing.md (section numbers in the comments refer to it).
//
// Every piece is tagged  // PORTABLE,  // PARTIAL: <why>  or  // NOT PORTABLE: <why>.
//
// Integration with Tweak.x (do not paste blindly):
//   1. Feature switches (<jbroot>/tmp/Backport162.off.<name> turns one off): "g3handle", "g3snapshot", "g3topaff", "g3switcher", "g3canvas",
//      "g3embedded", "g3pip", "g3kbwindow", "g3statusbar", "g3preflight" ... see BP_G3_On() below (names are strings, no enum edit needed).
//   2. Call BP_G3_Setup() from the %ctor after the build check; it %init()s every group at the end of this file.
//   3. Compile with ARC (-fobjc-arc), like Tweak.x.
//
// Safety rules followed here (same as group4): no hard-coded ivar offsets (ivars are read by name with
// class_getInstanceVariable/object_getIvar and the code does nothing if missing), every private selector is guarded with
// respondsToSelector:, nil is never passed to objc_setAssociatedObject as an object, hooks are no-ops when their switch is off.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <dlfcn.h>
#import <unistd.h>

// ------------------------------------------------------------------------------------------------ host integration
#ifndef BP_G3_STANDALONE
// provided by BP.h / Tweak.x
#else
static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) { (void)fmt; }
#endif

// Per-feature switch, on by default, off when <jbroot>/tmp/Backport162.off(.<name>) exists. Checked at most once a second.
static BOOL BP_G3_On(const char *name) {
#ifdef BP_G3_STANDALONE
    (void)name; return YES;
#else
    static char base[1024];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *tmp = ROOT_PATH_NS(@"/tmp");               // helper from <rootless.h>, as Tweak.x
        snprintf(base, sizeof base, "%s/Backport162.off", tmp.fileSystemRepresentation);
    });
    static uint64_t next; static BOOL all;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t >= next) { next = t + 1000000000ull; all = access(base, F_OK) == 0; }
    if (all) return NO;
    char path[1200]; snprintf(path, sizeof path, "%s.%s", base, name);   // per-name, not cached (rare call sites)
    return access(path, F_OK) != 0;
#endif
}

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
- (void)_updateSceneHostingInfoForSnapshottingWithView:(id)v;   // SBDeviceApplicationSceneHandle (16.0)
- (id)sceneHandle;                                              // SBDeviceApplicationSceneView
@end

@interface SBDeviceApplicationSceneHandle : NSObject @end
@interface SBDeviceApplicationSceneView : UIView @end
@interface SBTraitsSceneParticipantDelegate : NSObject @end

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
static char kBPG3HostView;
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

// ---- orientation selection (section 1.2). PARTIAL: inert until something calls _setInterfaceOrientationFromUserResizing: with a
// nonzero value (the switcher event-response chain is a different group). With the value 0 these are exactly the 16.0 methods.

// 16.0 0x1c5e73fe0 / 16.2 0x1c72e6e94: classic (non-Medusa) apps launch into the user-resize orientation.
- (long long)_launchingInterfaceOrientationForOrientation:(long long)o {
    if (BP_G3_On("g3handle")) {
        id app = [self application];
        if ([app respondsToSelector:@selector(isMedusaCapable)] && ![app isMedusaCapable] && [self currentInterfaceOrientation] == 0) {
            long long r = [self _interfaceOrientationFromUserResizing];
            if (r != 0) return r;
        }
    }
    return %orig;
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

// 16.2 0x1c72b9430: when the app's supported orientations no longer contain the user-resize orientation, forget it.
// PARTIAL: re-implemented as a post-%orig check instead of a UIApplicationSceneClientSettingsDiffInspector observer (same effect, no inspector).
- (void)_didUpdateClientSettingsWithDiff:(id)diff transitionContext:(id)ctx {
    %orig;
    if (!BP_G3_On("g3handle") || ![NSThread isMainThread]) return;
    long long r = [self _interfaceOrientationFromUserResizing];
    if (r == 0) return;
    id scene = [self sceneIfExists];
    id cs = [scene respondsToSelector:@selector(uiClientSettings)] ? [scene uiClientSettings] : nil;
    if (![cs respondsToSelector:@selector(supportedInterfaceOrientations)]) return;
    unsigned long long sup = [(id)cs supportedInterfaceOrientations];
    if (!(sup & (1ull << r))) [self _setInterfaceOrientationFromUserResizing:0];         // _SBFInterfaceOrientationMaskContainsInterfaceOrientation
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
// 16.0 sets the scene's hostContextIdentifierForSnapshotting / renderId once, in -_configureSceneLiveHostView:. 16.2 refreshes it from
// -[SBDeviceApplicationSceneView didMoveToWindow], so moving a scene view to another window (other display, other portal) no longer
// leaves a stale context id. PARTIAL: single hosting value instead of 16.2's assertion stack (the stack only matters when two
// views host one scene at once and the older one goes away).
%group G3_Snapshot

%hook SBDeviceApplicationSceneView
- (void)_configureSceneLiveHostView:(id)host {
    %orig;
    if (host) BP_G3_SetWeak(self, &kBPG3HostView, host);
}
- (void)_invalidateSceneLiveHostView:(id)host {
    BP_G3_SetWeak(self, &kBPG3HostView, nil);
    %orig;
}
- (void)didMoveToWindow {
    %orig;
    if (!BP_G3_On("g3snapshot")) return;
    id host = BP_G3_GetWeak(self, &kBPG3HostView);
    id h = [self respondsToSelector:@selector(sceneHandle)] ? [self sceneHandle] : nil;
    if (host && [h respondsToSelector:@selector(_updateSceneHostingInfoForSnapshottingWithView:)])
        [h _updateSceneHostingInfoForSnapshottingWithView:host];
}
%end

%end // G3_Snapshot

// ================================================================================================ SECTION 2: decorated scene VC
// opt-in switch <jbroot>/tmp/Backport162.on.<name>
static BOOL BP_G3_OptIn(const char *name) {
#ifdef BP_G3_STANDALONE
    (void)name; return NO;
#else
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    char path[1200]; snprintf(path, sizeof path, "%s/Backport162.on.%s", tmp.fileSystemRepresentation, name);
    return access(path, F_OK) == 0;
#endif
}
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
    static BOOL (*isSplit)(long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ isSplit = (BOOL (*)(long long))dlsym(RTLD_DEFAULT, "SBSpaceConfigurationIsSplitView"); });
    if (!isSplit) return;                                    // cannot evaluate: keep the 16.0 result
    BOOL splitOrFloating = isSplit(space) || (unsigned long long)(floating - 1) < 2;
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

// ==== SETUP BEGIN
void BP_G3_Setup(void) {
    %init(G3_Handle);
    %init(G3_Snapshot);
    %init(G3_DecoratedVC);
    %init(G3_Switcher);
}
// ==== SETUP END
