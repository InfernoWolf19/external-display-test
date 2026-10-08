# Group 3: scene, window and input plumbing under Stage Manager

Build under test: 20A8372 (iPadOS 16.0). Reference: 20C65 (iPadOS 16.2). Addresses are `16.0 / 16.2` vm addresses
(dyld shared cache, unslid) unless a single address is marked. Selectors were read from stub-resolved disassembly
(`fa.py`, a faster variant of `annot162.py` that also resolves class refs, ivar names, float literals), strings and
constants were decoded from the cache. Companion file: `group3-plumbing.hooks.m` (drafted hooks, each piece tagged
PORTABLE / PARTIAL / NOT PORTABLE).

This file is written incrementally: the triage table comes first, every class section is appended when it is finished.
Confidence words: HIGH = read directly from code or strings; MEDIUM = inferred from code plus strings; LOW = inference
without a direct witness.

## 0. Triage

"refactor" = code moved/renamed/regenerated, no behaviour change (offset-only, struct-layout-only, debug description,
inlined helper). "user-visible" = observable behaviour changes. Portability: HOOK = existing class can be hooked,
NEW = new class / category required, IVAR = 16.2 added ivars (impossible on the real class, associated objects or
the scene data store used instead).

| class | logic-changed | verdict | one-line reason |
|---|---|---|---|
| SBDeviceApplicationSceneHandle | 13 (+17 new methods, 3 new ivars) | user-visible | iPhone-only ("classic phone on pad") apps get a user-resizing orientation; orientation request state per scene; client-settings inspector |
| SBDeviceApplicationSceneEntity(ChamoisDevelopmentShimming) | 0 | no change | same 10 methods in both builds, not in the worklist |
| SBDisplayItem | 2 | refactor | only `descriptionBuilderWithMultilinePrefix:` / `succinctDescriptionBuilder` (debug output); gains `+displayItemForLayoutElement:` (moved from SBLayoutState) |
| SBDisplayItemLayoutGrid | 1 | user-visible (small) | passes `supportsOrthogonalSizes:` (from the layout restriction mask) to the fixed-aspect grid; adds description methods |
| _SBDisplayItemFlexibleGrid | 2 | user-visible, but lives in SBSwitcherChamoisSettings | grid widths/heights are now computed by `SBSwitcherChamoisSettings` and read from `SBSwitcherChamoisLayoutAttributes.gridWidths/gridHeights` (other group); `_gridWidthsForSafeWidth:minimumWidth:` guards a zero divisor and logs |
| _SBDisplayItemFixedAspectGrid | 1 | user-visible | orthogonal (portrait + landscape) grid sizes for fixed-aspect windows |
| SBLayoutState(SBAppLayoutConversion) | 1 | refactor | `displayItemFromLayoutElement:` -> `+[SBDisplayItem displayItemForLayoutElement:]`, same logic |
| SBMainDisplayLayoutState(SBDisplayItemConversion) | 1 | refactor | `floatingItem` calls the new class method, same logic |
| SBSceneLayoutWorkspaceTransaction | 1 | refactor | `_SBFIsChamoisExternalDisplayControllerAvailable` now called directly instead of through a function pointer |
| SBApplicationController | +1 (`applicationForDisplayItem:`) | user-visible (tiny) | web-clip display items (type 5) resolve to `-webApplication` instead of a bundle-id lookup |
| _SBDeviceApplicationSceneHandleSnapshottingAssertion (new) | n/a | user-visible | see section 1.6 |
| SBDeviceApplicationSceneOverlayBasicWrapperView(+ViewController) (new) | n/a | user-visible | see section 1.7 |
| SBFluidSwitcherPortaledSceneLiveContentOverlay (new) | n/a | user-visible | see section 1.8 |
| SBMedusaDecoratedDeviceApplicationSceneViewController | 5 (+133 offset-only) | user-visible | contentOrientation/containerOrientation split, top-affordance highlight with several displays, 3 split-view/multi-window error toasts removed |
| SBMedusaHostedKeyboardWindow | 3 | user-visible (external display) | ownership moved from the scene manager to a per-window-scene controller |
| SBMedusaHostedKeyboardWindowController (new) | n/a | user-visible (external display) | per-scene owner of the hosted keyboard window |
| SBMedusaBannerViewController | 1 | user-visible (relocated error banner) | types 2/3 for the split-view / multiple-window messages; NOT PORTABLE, 16.0 toast equivalent (section 2.4) |
| SBSwitcherController | 2 (+ ~25 new/removed) | user-visible | delegate callbacks around a window-management-style change; traits code extracted into SBSwitcherTraitsAssistant |
| SBFluidSwitcherGestureManager | 2 (+ many renames) | pending | |
| SBWindowSceneManager | 2 | user-visible | covered in group4 spec (active display tracking); only restated here |
| SBWindowSceneContext | 2 logic, 52 offset-only | refactor + 4 new properties | ivars re-ordered (all offset-only); `sceneManager` now read from the FBSScene transient local settings |
| SBWindowSceneStatusBarManager / StatusBarAssertionManager / StatusBarLayoutManager / StatusBarSettingsAssertion | 2 + 1 + 0 + 0 | pending | |
| SBWindowScenePIPManager | 3 | user-visible | per-scene PiP "end stash tab" suppression gesture manager, window-management-style observer |
| SBTransientUIInteractionManager | init changed | pending | |
| SBTraitsSceneOrientationRequestAssistant / SBSwitcherTraitsAssistant (new), SBTraitsExternalDisplay* | 1 + 2 new | pending | |
| SBPrivacyPreflightController / SBApplicationPrivacyPreflightController (new) | n/a | pending | |
| SBSystemShellEmbeddedDisplayController | 5 | user-visible (small) | SystemApp scene gets `enhancedWindowingEnabled` and tracks the Stage Manager default |
| SpringBoard (app delegate) | see 7 | pending | |
| SBMedusaSettings | 280 "changed" | refactor / prototype only | method sets identical, bodies identical modulo relocation, all default values identical (section 8) |
| SBMedusa1oSettings | 17 | refactor / prototype only | same |

(rows marked "pending" are replaced by the analysis in the sections below)


## 1. Theme A: scene content orientation, "user resizing" orientation, snapshot hosting info

Everything in this theme is one feature: **iPhone-only ("classic phone on pad") apps in a Stage Manager window can be
resized by the user, and the window's shape (portrait or landscape aspect) now picks the orientation the app scene is
given**. 16.0 had no such concept: `-[SBDeviceApplicationSceneHandle _launchingInterfaceOrientationForOrientation:]`
forced portrait for those apps in Stage Manager and all other state was derived from the device orientation. 16.2
adds a per-scene "interface orientation from user resizing", splits the single "interface orientation" of the scene
view into a *content* orientation and a *container* orientation (the app is drawn in `contentOrientation` inside a
container that is in `containerOrientation`), renames the 16.0 "AlterEgo" mechanism to "scene orientation request"
(UIKit `requestGeometryUpdate` with an orientation mask) and moves its state onto the scene handle.

Chain that sets the new state (all 16.2, HIGH):

```
modifier (group 1/2) -> SBSetInterfaceOrientationFromUserResizingEventResponse (new class, other group)
  -> -[SBFluidSwitcherViewController _performSetInterfaceOrientationFromUserResizingResponse:] 0x1c745ed18
  -> -[SBMainSwitcherControllerCoordinator switcherContentController:setInterfaceOrientationFromUserResizing:forDisplayItem:] 0x1c76d71d0
  -> -[SBDeviceApplicationSceneHandle _setInterfaceOrientationFromUserResizing:] 0x1c76b87f4
```

The consumers are in this group (scene handle, traits participant delegate, switcher traits) and are specified below.

### 1.1 SBDeviceApplicationSceneHandle: new state, stored in the scene data store (PORTABLE as category methods)

The 16.2 class gains three ivars (`_clientSettingsInspector` 0xd8, `_snapshottingInfoAssertions` 0x100,
`_currentSnapshottingInfoAssertion` 0x108; later ivars shift) but **all the orientation state is NOT in ivars**: it is
in the handle's scene data store, `-[SBSceneHandle _sceneDataStoreCreatingIfNecessary:]` (exists in 16.0; returns an
NSMutableDictionary-like store), under five string keys. This is what makes the state portable. Accessors
(16.2 addresses; categories `ClassicSupport`, `SwitcherCapabilities`, `TraitsSceneDelegateStateTracking`), all HIGH:

| accessor (16.2) | data store key (extern NSString const) | type | 16.2 body |
|---|---|---|---|
| `-_classicAppPhoneOnPadPrefersLandscape` 0x1c76b8288 | `_SBSceneDataKeyClassicPhoneAppPrefersLandscape` | NSNumber BOOL | `[[self application] _classicAppScaledPhoneOnPad] ? [[[self _sceneDataStoreCreatingIfNecessary:NO] safeObjectForKey:K ofType:NSNumber.class] boolValue] : NO` |
| `-_setClassicAppPhoneOnPadPrefersLandscape:` 0x1c76b832c | same | | `if ([[self application] _classicAppScaledPhoneOnPad]) [[self _sceneDataStoreCreatingIfNecessary:YES] setObject:@(v) forKey:K]` |
| `-_classicAppPhoneOnPadSupportsOldStyleMixedOrientation` 0x1c76b83ec | n/a | BOOL | `[[self application] _classicAppScaledPhoneOnPad] ? ![[[self _windowScene] switcherController] isChamoisWindowingUIEnabled] : NO` |
| `-_interfaceOrientationFromUserResizing` 0x1c76b876c | `_SBSceneDataKeyInterfaceOrientationFromUserResizing` | NSNumber integer | `[[store(create:YES)] safeObjectForKey:K ofType:NSNumber] integerValue`, nil gives 0 |
| `-_setInterfaceOrientationFromUserResizing:` 0x1c76b87f4 | same | | `store[K] = @(o)` (creates the store) |
| `-_isSettingUpSceneOrientationRequest` 0x1c76b8a44 | `_SBSceneDataKeySettingUpSceneOrientationRequest` | NSNumber | `[n integerValue] != 0` (nil gives NO) |
| `-_setSettingUpSceneOrientationRequest:` 0x1c76b88c0 | same | | store[K] = @(v) |
| `-_initialDeviceOrientationFromSceneOrientationRequestSetup` 0x1c76b8ad0 | `_SBSceneDataKeyInitialDeviceOrientationFromSceneOrientationRequestSetup` | NSNumber integer | |
| `-_supportedInterfaceOrientationsFromSceneOrientationRequestSetup` 0x1c76b8b58 | `_SBSceneDataKeySupportedInterfaceOrientationsFromSceneOrientationRequestSetup` (key inferred from the symmetric pair, getter not decoded) | NSNumber unsigned | |
| `-_resetSceneOrientationRequestState` 0x1c76b8874 | n/a | void | `_setSettingUpSceneOrientationRequest:NO; _setInitialDeviceOrientationFromSceneOrientationRequestSetup:0; _setSupportedInterfaceOrientationsFromSceneOrientationRequestSetup:0` |

`_sceneDataStoreCreatingIfNecessary:` takes the create flag as argument 2 (the getters pass 0 except
`_interfaceOrientationFromUserResizing`, which passes 1). `safeObjectForKey:ofType:` is the BaseBoard category on
NSDictionary. The setters write unconditionally. 16.0 kept `classicAppPhoneOnPadPrefersLandscape` on `SBApplication`
(getter 0x1c5ec4994: `[self _classicAppScaledPhoneOnPad] ? [[[self _dataStore] sceneStoreForIdentifier:[self _baseSceneIdentifier]
creatingIfNecessary:NO] safeObjectForKey:_SBSceneDataKeyClassicPhoneAppPrefersLandscape ofType:NSNumber] boolValue : NO`; that key
already exists in 16.0), i.e. per application, so two windows of one app share it; 16.2 deletes the `SBApplication`
property and keeps the same key in the per-scene store of the handle. Its 16.0 users (`SBDeviceApplicationSceneClassicAccessoryView
_rotateApplicationScene:`, `SBSceneLayoutWorkspaceTransaction _orientationForFollowOnRotationIfNeeded`,
`SBTraitsSceneParticipantDelegate _sanitizedMask:forApplication:`, `_classicPhoneOnPadActivationOrientationForOrientation:`) all
keep working unchanged on 16.0, so the 16.0 shim for the handle accessor simply forwards to the application (no behaviour change,
no storage). The other four keys (`...InterfaceOrientationFromUserResizing`, `...SettingUpSceneOrientationRequest`,
`...InitialDeviceOrientationFromSceneOrientationRequestSetup`, `...SupportedInterfaceOrientationsFromSceneOrientationRequestSetup`)
are new exported constants in 16.2; a port defines its own key strings.

Portability: PORTABLE. These are new methods on an existing class (Logos `%new`/`class_addMethod`), no ivars needed.
A 16.0 build can use the exact same keys (the keys are just dictionary keys, nothing reads them except the 16.2-style
code we add).

Reset hook: 16.2 `-_didUpdateSettingsWithDiff:previousSettings:` (0x1c72afca0) calls `-_resetSceneOrientationRequestState`
whenever `_isEffectivelyForeground` becomes NO (the new `tbnz w20,#0` skip around the call); 16.0 has nothing to
reset because the state lived in the traits participant delegate. Hookable (PARTIAL: needs the 16.0 `_isEffectivelyForeground`
ivar, found by name).

### 1.2 Orientation selection methods (HOOK, PARTIAL: only useful together with the setter chain above)

All reconstructed from annotated disassembly, selectors verified. `mask` values: `1<<UIInterfaceOrientation`
(portrait 2, upside-down 4, landscape-right 8, landscape-left 0x10, all 0x1e).

**`-_launchingInterfaceOrientationForOrientation:`** 16.0 0x1c5e73fe0, 16.2 0x1c72e6e94 (HIGH)

16.0:
```objc
- (long long)_launchingInterfaceOrientationForOrientation:(long long)o {      // arg is the proposed orientation, 0 = none
    NSAssert([self currentInterfaceOrientation] == 0, @"Don't calculate a launch orientation for a running app. Really."); // SBDeviceApplicationSceneHandle.m:0x3a4
    SBApplication *app = [self application];
    if (o == 0) o = [OrientationClass interfaceOrientationForCurrentDeviceOrientation:YES];    // class ref 0x1dd685928 (same in 16.2)
    if ([app isMedusaCapable]) {
        BOOL phoneOnPad    = [app classicAppPhoneAppRunningOnPad];
        BOOL landscapeOnly = [self _classicPhoneAppInPadSupportsLandscapeOnly:[[app info] supportedInterfaceOrientations]];
        BOOL chamois       = [[[self _windowScene] switcherController] isChamoisWindowingUIEnabled];
        if (chamois && phoneOnPad && !landscapeOnly) return UIInterfaceOrientationPortrait;       // 0x5e74248: mov w21,#1
        goto USE_O;                                                                                // (!chamois || !phoneOnPad || landscapeOnly)
    }
    BOOL rotStyle = [OrientationClass homeScreenRotationStyle] != 0;
    BOOL sdkOK    = rotStyle || [[app info] builtOnOrAfterSDKVersion:@"8.0"];
    BOOL anyOK    = [self _currentClassicModeAllowsLaunchingToAnySupportedOrientation];
    BOOL supports = [self _mainSceneSupportsInterfaceOrientation:o];
    if (sdkOK && anyOK) {
        if (supports) goto USE_O;
        // proposed orientation not supported: honour a user orientation lock by trying the raw device orientation
        if ([[SBOrientationLockManager sharedInstance] isUserLocked]) {
            long long raw = [OrientationClass rawDeviceOrientationIgnoringOrientationLocks];
            if (raw >= 1 && raw <= 4 && raw != o && [self _mainSceneSupportsInterfaceOrientation:raw]) return raw;
        }
        goto DEFAULT;
    }
    if ([app classicAppPhoneAppRunningOnPad]) { o = [self _classicPhoneOnPadActivationOrientationForOrientation:o]; goto USE_O; }
    goto DEFAULT;
  USE_O:   if (o != 0) return o;
  DEFAULT: o = [self defaultInterfaceOrientation];
           if (o == 0) { NSLog(@"No fallback orientation for '%@'!", [self sceneIdentifier]); o = 1; }
           return o;
}
```
16.2 (0x1c72e6e94; same prologue and assertion, line number 0x39a):
```objc
- (long long)_launchingInterfaceOrientationForOrientation:(long long)o {
    NSAssert([self currentInterfaceOrientation] == 0, @"Don't calculate a launch orientation for a running app. Really.");
    SBApplication *app = [self application];
    if (o == 0) o = [OrientationClass interfaceOrientationForCurrentDeviceOrientation:YES];
    if ([app isMedusaCapable]) goto USE_O;                                    // 16.0's chamois/phone-on-pad special case is gone
    long long r = [self _interfaceOrientationFromUserResizing];               // NEW: wins over everything for classic apps
    if (r != 0) return r;
    BOOL sdkOK = ([OrientationClass homeScreenRotationStyle] != 0) || [[app info] builtOnOrAfterSDKVersion:@"8.0"];
    BOOL anyOK = [self _currentClassicModeAllowsLaunchingToAnySupportedOrientation];
    if (sdkOK && anyOK) { ...unchanged from 16.0: supports ? USE_O : user-lock raw-orientation fallback ... }
    else if ([app classicAppPhoneAppRunningOnPad]) { o = [self _classicPhoneOnPadActivationOrientationForOrientation:o]; goto USE_O; }
    goto DEFAULT;                                                              // identical tail
}
```
Net behaviour change: (a) the Stage-Manager "phone app on pad launches portrait unless landscape-only" special case is
gone for Medusa-capable apps (they just get the requested/default orientation), (b) user-resizing orientation overrides
launch orientation for classic apps. The `_classicPhoneAppInPadSupportsLandscapeOnly:` helper is deleted in 16.2.

**`-activationInterfaceOrientationForOrientation:`** 16.0 0x1c5e58d94, 16.2 0x1c72cb524 (HIGH)
```objc
// both: cur = [self currentInterfaceOrientation]; if (cur == 0) return [self _launchingInterfaceOrientationForOrientation:o];
// 16.2 adds, right after that:
if ([self _interfaceOrientationFromUserResizing] != 0) return cur;                  // resizing wins, keep current
// then as 16.0:
if ([[self application] classicAppPhoneAppRunningOnPad]) { long long r = [self _classicPhoneOnPadActivationOrientationForOrientation:o]; if (r) return r; }
return cur;
```

**`-_resumingInterfaceOrientationForOrientation:`** 16.0 0x1c5e9d524, 16.2 0x1c73101d0 (HIGH)
```objc
- (long long)_resumingInterfaceOrientationForOrientation:(long long)o {
    NSAssert([self sceneIfExists] != nil, @"Don't calculate a resuming orientation for a non-running app. Really.");   // .m:0x379 (16.0) / 0x36c (16.2)
    if (o == 0) return [self currentInterfaceOrientation];
    SBApplication *app = [self application];
    BOOL sdk8     = [[app info] builtOnOrAfterSDKVersion:@"8.0"];
    BOOL supports = [self _mainSceneSupportsInterfaceOrientation:o];
    long long r = [self _interfaceOrientationFromUserResizing];                       // 16.2 ONLY, inserted here
    if (r != 0) return r;
    if ([app classicAppPhoneAppRunningOnPad]) {
        r = [self _classicPhoneOnPadActivationOrientationForOrientation:o];
        return r ? r : [self currentInterfaceOrientation];
    }
    BOOL useEffective;                      // identical in both builds
    if (!__sb__runningInSpringBoard())      useEffective = !([[UIDevice currentDevice] userInterfaceIdiom] != 0 || sdk8);
    else switch (SBFEffectiveDeviceClass()) { case 0: case 1: useEffective = !sdk8; break; default: useEffective = NO; }
    if (useEffective) {
        r = [[[self sceneIfExists] uiClientSettings] sb_effectiveInterfaceOrientation];
        return r ? r : [self currentInterfaceOrientation];
    }
    if (!supports) return [self currentInterfaceOrientation];
    if ([[self application] isMedusaCapable]) return o;
    unsigned long long sup = [[[self sceneIfExists] uiClientSettings] supportedInterfaceOrientations];
    if (sup != 0 && (_XBInterfaceOrientationMaskForInterfaceOrientation(o) & sup)) return o;
    return [self currentInterfaceOrientation];
}
```
The only functional difference between the builds is the inserted `_interfaceOrientationFromUserResizing` early return (the rest is register
renumbering and branch re-layout; I diffed the control flow by hand).

**`-_classicPhoneOnPadActivationOrientationForOrientation:`** 16.0 0x1c62262d8, 16.2 0x1c76b6c78: identical algorithm;
only the source of the "prefers landscape" bit changes: 16.0 `[[self application] classicAppPhoneOnPadPrefersLandscape]`,
16.2 `[self _classicAppPhoneOnPadPrefersLandscape]` (per scene, section 1.1). Algorithm (decoded, MEDIUM-HIGH): `supported` =
client settings `supportedInterfaceOrientations`; if `supported && prefersLandscape`: take current orientation if it is
landscape and supported; else the proposed one if landscape and supported; else landscape-right (3)/left (4) chosen from
`supported` bits (0x10 then 0x8); else fall back to portrait 1 if supported (via `_mainSceneSupportsInterfaceOrientation:1`)
else `_bestSupportedInterfaceOrientationForOrientation:0`.

**`-_mainSceneSupportedInterfaceOrientations`** 16.0 0x1c5e37cc0, 16.2 0x1c72aa11c (HIGH)
```objc
// 16.2
- (unsigned long long)_mainSceneSupportedInterfaceOrientations {
    SBApplication *app = [self application];
    unsigned long long mask = [[app info] supportedInterfaceOrientations];
    if ([app isMedusaCapable]) return 0x1e;
    FBScene *s = [self sceneIfExists];
    if (s) mask = [[s uiClientSettings] supportedInterfaceOrientations];
    return mask;
}
```
16.0 differed: for Medusa-capable apps it returned 0x1e only when Stage Manager was off or the app was not phone-on-pad, and
for phone-on-pad windows in Stage Manager returned `landscapeOnly ? mask : 2` (portrait only); for classic apps the
`wantsLegacyFullscreenInterfaceOrientationBehaviors` / `isMonarchLinked` / `deviceOrientationEventsEnabled` mask unions
were applied. 16.2 removes all of that (those SBApplication selectors have zero callers in 16.2).

**`-_interfaceOrientationMode`** 16.0 0x1c62253b4, 16.2 0x1c76b5e24; **`-wantsDeviceOrientationEventsEnabled`**
16.0 0x1c6225328, 16.2 0x1c76b5dac (HIGH):
```objc
// both: if scene exists use scene.uiSettings.interfaceOrientationMode / .deviceOrientationEventsEnabled
// no scene yet:
// 16.0: mode   = (IsClassic([app _defaultClassicMode]) || [app wantsLegacyFullscreenInterfaceOrientationBehaviors])
//                  ? (_SBPostModernRotationEnabled() ? 1 : 100) : 2;
//       events = IsClassic(...) ? YES : [app wantsLegacyFullscreenInterfaceOrientationBehaviors];
// 16.2: mode   = IsClassic([app _defaultClassicMode]) ? 1 : 2;
//       events = IsClassic([app _defaultClassicMode]);
```
(`_SBPostModernRotationEnabled` returns YES on a Stage Manager capable 16.0 iPad because the `PostModernRotation` feature flag
or `_SBTraitsArbiterActuationEnabled()` is on, so the visible 16.0/16.2 difference is limited to apps for which
`wantsLegacyFullscreenInterfaceOrientationBehaviors` was true: iPad apps that do not support modern rotation and do not
declare multi-window support, i.e. `UIRequiresFullScreen` apps. These lose mode 1/"events enabled" before their scene exists.)

**`-setKeyboardContextMaskStyle:`** 16.0 0x1c5e3df60, 16.2 0x1c72b0354: the early-out `[app isClassic] && style == 2` is now
`![app supportsChamoisSceneResizing] && style == 2` (`supportsChamoisSceneResizing` is literally `isMedusaCapable`, the two
SBApplication methods are one `b` to the same stub). LOW impact.

**`-_didUpdateClientSettingsWithDiff:transitionContext:`** 16.0 0x1c5e473d0, 16.2 0x1c72b9430 (HIGH)
```objc
// 16.0: [super ...]; [_modalAlertPresenter setVisibleModalAlertCount:[[[scene uiClientSettings] visibleMiniAlertCount]]];
// 16.2:
- (void)_didUpdateClientSettingsWithDiff:(id)diff transitionContext:(id)ctx {
    [super _didUpdateClientSettingsWithDiff:diff transitionContext:ctx];
    NSAssert([NSThread isMainThread], @"this call must be made on the main thread");   // SBDeviceApplicationSceneHandle.m:0x46d
    if (!_clientSettingsInspector) {
        _clientSettingsInspector = [UIApplicationSceneClientSettingsDiffInspector new];
        __weak typeof(self) w = self;
        [_clientSettingsInspector observeVisibleMiniAlertCountWithBlock:^{ [w->_modalAlertPresenter setVisibleModalAlertCount:[[[[w scene] uiClientSettings] visibleMiniAlertCount]]]; }];
        [_clientSettingsInspector observeSupportedInterfaceOrientationsWithBlock:^{
            // NEW: when the app stops supporting the orientation the user resized into, forget it
            unsigned long long sup = [[[w scene] uiClientSettings] supportedInterfaceOrientations];
            if (!_SBFInterfaceOrientationMaskContainsInterfaceOrientation(sup, [w _interfaceOrientationFromUserResizing]))
                [w _setInterfaceOrientationFromUserResizing:0];
        }];
    }
    [_clientSettingsInspector inspectDiff:diff withContext:ctx];
}
```
(`dealloc` 16.2 0x1c76b4fb0 additionally `removeAllObservers` and nils the inspector.) The inspector class
`UIApplicationSceneClientSettingsDiffInspector` and `observeSupportedInterfaceOrientationsWithBlock:` exist in 16.0 UIKitCore
(verified in the class dump). PORTABLE with an associated object for the inspector.

**`-_modifyApplicationSceneSettings:fromRequestContext:entity:`** 16.0 0x1c5e2b9a8, 16.2 0x1c729dfb4 (HIGH for the diff,
MEDIUM for intent). The diff in the "restricted classic mode display configuration" prologue:
* `isChamoisLinked` (SBApplication) is renamed `supportsChamoisOnExternalDisplay` (same body: `isSydneyLinked ? YES : supportsChamoisSceneResizing`);
* `-_isInCallBanner` (`SBSUIInCallSceneSettings.inCallPresentationMode == 1`) is deleted; in 16.0 it forced the same
  "not resizable" branch as activation setting 0x42;
* the scene-manager display bookkeeping changes from `displayIdentity`/`sb_setDisplayIdentityForSceneManagers:` to
  `displayConfiguration`/`sb_setDisplayConfigurationForSceneManagers:`;
* NEW: `settings.screenBoundsIgnoresSceneOrientation = (chamoisUI && [[sb_displayIdentityForSceneManagers] isExternal] &&
  supportsChamoisOnExternalDisplay) ? ![app supportsChamoisSceneResizing] : NO` -- **NOT PORTABLE**: the property exists only on 16.2's
  `UIMutableApplicationSceneSettings` (not in 16.0 UIKitCore, verified), so a 16.0 client never reads it;
* NEW: an os_log of the interface orientation after `updateOrientationSceneSettingsForParticipant:` (`SBLogTraitsArbiter`).
Verdict: do not port; the only visible piece (external-display UIScreen bounds ignoring scene orientation) needs UIKit client support.

### 1.3 SBTraitsSceneParticipantDelegate: AlterEgo -> SceneOrientationRequest (refactor + clear user-resize state)

16.0 (`SBTraitsSceneParticipantDelegate`, ivars `_isAlterEgoSetupUpdate` 0x8, `_alterEgoInitialDeviceOrientation` 0x10,
`_supportedOrientationsOverride` 0x18; methods `_startAlterEgoWithDesiredOrientations:error:` 0x1c62d9ea8,
`_checkAlterEgoValidityForUpdateReasons:` 0x1c62da074, `_resetAlterEgoState` 0x1c62da444,
`_performCoalescedBroadcastArbitrationUpdateWithReason:` 0x1c62da1e4) is replaced in 16.2 by the new helper object
`SBTraitsSceneOrientationRequestAssistant` (ivars `_traitsDelegate` (weak) 0x8, `_errorDomain` 0x10), owned by the delegate in a new
ivar `_orientationRequestActionAssistant`. The delegate class is not otherwise changed except for `participantWillInvalidate:`.

Behaviour of the assistant (16.2, HIGH):
* `-setUpForTransitionContextIfNeeded:` 0x1c7824a00: looks in the scene update's `actions` for the first action that passes a block
  (the geometry/orientation request action) and reads `requestedInterfaceOrientationMask` and `policy`. If `policy == 2` and
  `[[SBOrientationLockManager sharedInstance] isUserLocked]` it answers the action with an error
  ("NOOP: honoring user orientation lock", code 1). Else if the delegate's `sceneHandle` is an `SBDeviceApplicationSceneHandle`
  it calls `_startSceneOrientationRequestWithDesiredOrientations:error:`; otherwise error
  "The requesting scene [%@] is not supported". If the action `canSendResponse`, it sends `[[BSActionResponse alloc] initWithInfo:error:]`.
* `-_startSceneOrientationRequestWithDesiredOrientations:error:` 0x1c7824cfc: asserts sceneHandle/outError, then
  ```objc
  unsigned long long previous = [h _supportedInterfaceOrientationsFromSceneOrientationRequestSetup];
  [h _setInterfaceOrientationFromUserResizing:0];                      // NEW in 16.2: an app request cancels the user-resize orientation
  [h _setSettingUpSceneOrientationRequest:previous == 0];              // 16.0 _isAlterEgoSetupUpdate = (_supportedOrientationsOverride == 0)
  [h _setSupportedInterfaceOrientationsFromSceneOrientationRequestSetup:desired];
  [h _setInitialDeviceOrientationFromSceneOrientationRequestSetup:[[delegate participant] currentDeviceOrientation]]; // 16.0: only if the orientation lock is user-locked, else 0
  [self _performCoalescedBroadcastArbitrationUpdateWithReason:@"SceneOrientationRequest setup"];
  ```
  Note the 16.0 detail "store the device orientation only if `isUserLocked`" is dropped: 16.2 stores it unconditionally.
* `-checkValidityAgainstUpdateReasons:` 0x1c7824818: if a setup is in progress (`_isSettingUpSceneOrientationRequest`), clear the flag and stop; else
  compare the stored initial device orientation with `currentDeviceOrientation`; if they differ and the stored value is a valid portrait/landscape (1...4 range check
  `x - 1 <= 3`), `BSRunLoopPerformAfterCACommit` a block that ends the request (calls back into the delegate's reset); a non-valid stored value is cleared.
* `-_performCoalescedBroadcastArbitrationUpdateWithReason:` 0x1c7824f3c: `BSRunLoopPerformRelativeToCACommit(-1, ^{ [traitsDelegate _broadcastArbitrationUpdate...] })`.
* `-invalidate` 0x1c782476c: resets the three setup values on the handle.

Portability: the 16.0 delegate already implements this with private ivars; the *behavioural* delta (clear
user-resize orientation on a request; always store the initial device orientation) is two lines inside an ObjC method.
PARTIAL: hook `-[SBTraitsSceneParticipantDelegate _startAlterEgoWithDesiredOrientations:error:]` and, after `%orig`, call
`[handle _setInterfaceOrientationFromUserResizing:0]` (only meaningful with the user-resize chain in place).


### 1.4 Display item / layout state / application controller (mostly refactor)

* `SBDisplayItem` (2 changed): `-descriptionBuilderWithMultilinePrefix:` (31->1 insn) and `-succinctDescriptionBuilder` (4->37) swap roles
  (the 16.2 succinct builder is `[BSDescriptionBuilder builderWithObject:self]` plus `appendString:(type name table)withName:@"type"`, `appendObject:@bundleIdentifier`,
  `appendObject:@uniqueIdentifier`). Debug text only. **refactor, NOT PORTABLE / not needed.** 16.2 also gains
  `+[SBDisplayItem displayItemForLayoutElement:]` 0x1c742ec60 (below).
* `-[SBLayoutState(SBDisplayItemConversion) displayItemFromLayoutElement:]` 16.0 0x1c5fb7364 became the class method above. Same logic:
  nil element -> nil; `workspaceEntity`; `isApplicationSceneEntity` -> `[[[entity applicationSceneEntity] sceneHandle] displayItemRepresentation]`
  (16.0 skipped the `applicationSceneEntity` cast); `isAppClipPlaceholderEntity` -> `+displayItemWithType:0 bundleIdentifier:[entity.appClipPlaceholderEntity bundleIdentifier]
  uniqueIdentifier:[...futureSceneIdentifier]`; else `+homeScreenDisplayItem`. `-[SBLayoutState appLayout]` and `-[SBMainDisplayLayoutState floatingItem]` merely call it.
  **refactor.**
* `-[SBSceneLayoutWorkspaceTransaction _runningOnMainRootOrExtendedExternalDisplay]` 16.0 0x1c62a109c / 16.2 0x1c773aecc:
  `mainRootDisplay ? YES : (sb_displayWindowingMode == 1 ? _SBFIsChamoisExternalDisplayControllerAvailable() : NO)`; 16.0 reached the same C function through a
  GOT function pointer (`blraaz`). **refactor.**
* `-[SBApplicationController applicationForDisplayItem:]` (new, category SBDisplayItemAdditions, 16.2 0x1c742fdb0), **user-visible (tiny), PORTABLE**:
  ```objc
  - (SBApplication *)applicationForDisplayItem:(SBDisplayItem *)item {
      long long t = [item type];
      if (t == 0 || t == 3) return [self applicationWithBundleIdentifier:[item bundleIdentifier]];
      if (t == 5)           return [self webApplication];       // web clip items: the single web application
      return nil;
  }
  ```
  It replaces the inline `[[SBApplicationController sharedInstance] applicationWithBundleIdentifier:[item bundleIdentifier]]` in
  `-[SBFluidSwitcherViewController _applicationForDisplayItem:]` (16.0 0x1c5fd9638, 16.2 0x1c74529cc) and 6 other callers (`SBDisplayItemLayoutAttributesCalculator`,
  `SBSwitcherController _deviceApplicationSceneHandleForDisplayItem:`, `SBMainSwitcherControllerCoordinator _entityForDisplayItem:...` etc.). `-webApplication` exists in 16.0.
  Fix: web-clip display items (type 5) resolved to nothing before (bundle id lookup of the clip). Hook plan: add the method (`%new`); hooking the 16.0 callers is NOT needed because they
  are other groups' methods. Effect on 16.0 without the callers: none. **PORTABLE as an unused helper; zero standalone value.**
* `_SBDisplayItemFixedAspectGrid` (init gains `supportsOrthogonalSizes:`, 16.2 0x1c791ec74; new ivar `_supportsOrthogonalSizes` at +0x59) and
  `SBDisplayItemLayoutGrid _gridForBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:` (16.0 0x1c6468bdc, 16.2 0x1c791e180):
  the layout creates the fixed-aspect grid with `supportsOrthogonalSizes = !(restrictionMask & 0x8)` (`tst x24,#0x8; cset eq`). With the flag the fixed grid adds the
  transposed size (width and height swapped) as an additional candidate in `_buildFixedGridWithScreenScale:` (16.0 0x1c6469854 -> 16.2 0x1c791ed14, ~+20 insns; the
  NSNumber arrays were replaced by CGSize-pair arrays and `allWidths`/`allHeights` were added). MEDIUM-LOW on the exact candidate set.
  `_SBDisplayItemFlexibleGrid _buildGridWithScreenScale:` (141->15 insns) now just copies `chamoisLayoutAttributes.gridWidths/gridHeights`; the arithmetic (strip width,
  edge padding, minimumWindowWidth, `stageInterItemSpacing`) moved to `SBSwitcherChamoisSettings _gridWidthsForSafeWidth:minimumWidth:stageInterItemSpacing:` (another group).
  `_gridWidthsForSafeWidth:minimumWidth:` itself only gets a `divisor > 0` guard and an `SBLogAppSwitcher` error log.
  **NOT PORTABLE** as hooks: direct ObjC methods exist, but the result has no effect without the layout-attributes change and the rotating user-resize chain (they are one feature).

### 1.5 SBDeviceApplicationSceneView / content vs container orientation (context for the rows below, NOT in the worklist)

16.2 `SBDeviceApplicationSceneView` gets `initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:` (16.0 had one `orientation:`),
`_anyOverlayViewNeedsCounterRotation`, `_windowManagementStyleDidChange:` and `didMoveToWindow`; `SBDeviceApplicationSceneHandle
newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:` (16.2 0x1c76b7e68) is the factory. `_preferredSizingPolicy` /
`_supportedSizingPolicies` (no args, they read `currentInterfaceOrientation` and `switcherController.interfaceOrientation`) became `_preferredSizingPolicyForContentOrientation:containerOrientation:` /
`_supportedSizingPoliciesForContentOrientation:containerOrientation:` (16.2 0x1c76b8464 / 0x1c76b8534), same `SBApplication preferredSizingPolicyForSwitcherWindowManagementStyle:displayIdentity:contentOrientation:containerOrientation:`
call underneath (that SBApplication method already exists in 16.0). **NOT PORTABLE**: signature change across SBSceneViewController / SBDeviceApplicationSceneView / decorated VC / overlays.

### 1.6 `_SBDeviceApplicationSceneHandleSnapshottingAssertion` and scene hosting info for snapshotting (user-visible, PARTIAL)

16.0: `-[SBDeviceApplicationSceneView(ClassicSupport) _configureSceneLiveHostView:]` (0x1c62a4f50) calls
`[handle _updateSceneHostingInfoForSnapshottingWithView:host]` once and `_invalidateSceneLiveHostView:` calls it with nil. The handle writes
`hostContextIdentifierForSnapshotting = [[host window] _contextId]` and `scenePresenterRenderIdentifierForSnapshotting = CALayerGetRenderId([host layer])` into the scene's UI settings
(`updateUISettingsWithBlock:`). If the view is later moved to another window (Stage Manager window moved to the external display, portal reparenting) the context id is stale and
snapshots of the scene are taken from the wrong/missing context.

16.2 (HIGH):
```objc
// new class, subclass of BSSimpleAssertion, ivars unsigned _contextId (+0x30), unsigned long long _renderId (+0x38)
- (id)_SBDeviceApplicationSceneHandleSnapshottingAssertion initWithIdentifier:reason:contextId:renderId:invalidationBlock:   // 0x1c76b8be0

- (id<BSInvalidatable>)_sceneHostingInfoForSnapshottingAssertionWithView:(UIView *)view {     // 0x1c76b7acc
    UIWindow *w = [view window];
    if (!view || !w) return nil;
    unsigned ctx = [w _contextId]; unsigned long long rid = CALayerGetRenderId([view layer]);
    NSString *name = [NSString stringWithFormat:@"%@-%lu-%lu", [self sceneIdentifier], (unsigned long)ctx, (unsigned long)rid];
    __weak typeof(self) ws = self;
    id a = [[_SBDeviceApplicationSceneHandleSnapshottingAssertion alloc] initWithIdentifier:name forReason:<const> contextId:ctx renderId:rid
                invalidationBlock:^(id a){ [ws _removeSnapshottingInfoAssertion:a]; }];
    [self _addSnapshottingInfoAssertion:a];            // 0x1c76b7ce8: append to _snapshottingInfoAssertions, _currentSnapshottingInfoAssertion = a (weak), update(force:YES)
    return a;
}
- (void)_removeSnapshottingInfoAssertion:(id)a {       // 0x1c76b7d90: remove; if it was current, current = lastObject, update(force:NO)
- (void)_updateSceneHostingInfoForSnapshottingWithAssertion:(id)a forceUpdate:(BOOL)f {        // 0x1c76b7964
    if (![[self sceneIfExists] isValid]) return;
    ctx = [a contextId]; rid = [a renderId]; ui = [scene uiSettings];
    if (f || [ui hostContextIdentifierForSnapshotting] != ctx || [ui scenePresenterRenderIdentifierForSnapshotting] != rid)
        [scene updateUISettingsWithBlock:^(UIMutableApplicationSceneSettings *s){ s.hostContextIdentifierForSnapshotting = ctx; s.scenePresenterRenderIdentifierForSnapshotting = rid; }];
}
// SBDeviceApplicationSceneView (16.2 0x1c773d7c8), new override:
- (void)didMoveToWindow { [super didMoveToWindow];
    UIView *host = _currentHostView (weak);
    if (host) { id old = _snapshottingInfoAssertion; _snapshottingInfoAssertion = [[self sceneHandle] _sceneHostingInfoForSnapshottingAssertionWithView:host]; [old invalidate]; } }
```
The assertion stack makes "last host view wins, previous restored when it goes away" correct when two views host one scene (a window mid-drag shown by the live overlay and its card).
Confidence: HIGH for mechanics, MEDIUM for "fixes stale snapshot after moving between displays" (inferred from the code, not observed).
Portability: **PARTIAL** (hooks.m `G3_Snapshot`): hook `-[SBDeviceApplicationSceneView didMoveToWindow]` (no override in 16.0, Logos hooks the inherited method), remember the host view passed to `_configureSceneLiveHostView:`,
and call the existing 16.0 `-_updateSceneHostingInfoForSnapshottingWithView:` after the move. The assertion stack is not reproduced.

### 1.7 SBDeviceApplicationSceneOverlayBasicWrapperView(+ViewController) (new, user-visible only through other 16.2 code; NOT PORTABLE as such)

Adapter that lets any `UIViewController` serve as a scene overlay (protocol `SBDeviceApplicationSceneOverlayViewController`/`...View`): the view controller owns a
`SBDeviceApplicationSceneOverlayBasicWrapperView` as its `view` (`loadView` = `initWithFrame:`), `-initWithContentViewController:` stores the child, `viewDidLayoutSubviews` sets
`contentViewController.view.frame = wrapperView.bounds`, `viewWill/DidAppear/Disappear` forward appearance; the wrapper view stubs the observer API (`addObserver:`/`removeObserver:` no-ops),
`needsCounterRotation` returns NO, and stores `hostOrientation` / `shouldLayoutOverlayImmediatelyForContainerGeometryChange` (ivars +0x1b8/+0x1b0). It exists because 16.2's
`SBDeviceApplicationSceneView` tracks overlays by priority in `_overlayViewsByPriority` and asks each for counter rotation when content and container orientations differ
(`_anyOverlayViewNeedsCounterRotation`). Only useful with 1.5. Pure new classes: a port would be a verbatim ~60-line reimplementation (NEW CLASS) with no consumer in 16.0.

### 1.8 SBFluidSwitcherPortaledSceneLiveContentOverlay (new; NOT PORTABLE)

New class conforming to `SBFullScreenSwitcherSceneLiveContentOverlay` / `SBSceneViewPresentationConfiguring` / `SBUISizeObservingViewDelegate`; ivars `_sceneHandle`, `_contentOrientation`,
`_containerOrientation`, `_livePortalView`, `_sizeObservingView`, `_sceneView`, `_referenceSize`. It shows the live scene through a portal (`_livePortalView`) instead of hosting the
scene view directly, so one scene can be visible in two places (window being dragged between displays / the card and the live window), with
`configureWithWorkspaceEntity:referenceFrame:contentOrientation:containerOrientation:layoutRole:spaceConfiguration:floatingConfiguration:hasClassicAppOrientationMismatch:sizingPolicy:`
(16.2 0x1c78a679c). Instantiated (`initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:livePortalView:isInsetForHomeAffordance:`, 16.2 0x1c78a6520) from
`-[SBFullScreenSwitcherLiveContentOverlayCoordinator _updatePortaledSceneLiveContentOverlays]` (0x1c74ce438) and `-[SBShelfLiveContentOverlayCoordinator _addOverlaysIfNeededForTransitionContext:]` (0x1c798b190): the overlay wraps a portal view supplied by the coordinator.
Verdict: NOT PORTABLE: both coordinators are 16.2-only code paths.

## 2. SBMedusaDecoratedDeviceApplicationSceneViewController (user-visible; 5 logic changes, 133 offset/const-only)

All 133 other changed methods are relocation (ivar offsets shifted by 16.2's removed/added ivars, `_blurView`, `_deviceApplicationSceneViewController` ...) and the renames below.

**2.1 Window-management-style notification (PARTIAL).** 16.2 init (16.0 0x1c6329ec4 / 16.2 0x1c77caf30) registers one more observer:
`addObserver:self selector:@selector(_windowManagementStyleDidChange:) name:SBSwitcherControllerWindowManagementStyleDidChangeNotification object:nil`.
The notification is posted by `-[SBFluidSwitcherViewController _chamoisWindowingUIEnabledDefaultChangeHandler]` (16.2 0x1c745fbd0, group 1/2) when Stage Manager is toggled.
Same observer is added by `SBWindowScenePIPManager windowSceneDidConnect:` (object = the scene's switcherController, section 4), `SBDeviceApplicationSceneView init...` and `SBAppSwitcherReusableSnapshotView`.
New handler (16.2 0x1c77cfde4), HIGH:
```objc
- (void)_windowManagementStyleDidChange:(NSNotification *)n {
    [self _createOrDestroyTopAffordanceViewControllerAnimated:YES];
    [self updateTopAffordanceOverrideUserInterfaceStyle];
    [_topAffordanceViewController updateContextMenuWithLayoutRole:_layoutRole spaceConfiguration:_spaceConfiguration
        floatingConfiguration:_floatingConfiguration interfaceOrientation:[_deviceApplicationSceneHandle currentInterfaceOrientation] isZoomed:_isZoomed];
}
```
Effect: toggling Stage Manager updates the "..." top affordance and its context menu of live windows immediately. All callees exist in 16.0. Port: `%new` handler + observer in init + a poster hooked on `-[SBSwitcherController setChamoisWindowingUIEnabled:]`. The 16.0 poster does not exist, so the port must post (object = the switcher controller, main thread, after the change). PARTIAL (the handler is correct; whether 16.0 already refreshes the affordance through its layout transition is unverified).

**2.2 `contentInterfaceOrientation` -> `contentOrientation` + `containerOrientation` (NOT PORTABLE)**: the decorated VC forwards both to `_deviceApplicationSceneViewController` (`SBDeviceApplicationSceneViewController`, not in the worklist);
`setContentReferenceSize:withContentOrientation:andContainerOrientation:` (16.2 0x1c77cc0f0) replaces `setContentReferenceSize:withInterfaceOrientation:`. `viewWillLayoutSubviews` (16.0 0x1c5e3c200, 16.2 0x1c72ae4fc) just calls the renamed getter to pick width/height. New `-applicationSceneViewControllerIsInNonrotatingWindow:` (0x1c77cff68) asks the delegate `medusaDecoratedDeviceApplicationSceneViewControllerIsInNonrotatingWindow:` (default NO). Needs the content/container split (section 1.5).

**2.3 `_updateTopAffordanceHighlight` (PORTABLE), 16.0 0x1c632fb04 / 16.2 0x1c77d0de8, HIGH.**
```objc
// 16.0
- (void)_updateTopAffordanceHighlight {
    if (![self isViewLoaded]) return;
    BOOL nub = _nubViewHighlighted;
    BOOL cond = [SBApp isHardwareKeyboardAttached] ? SBSpaceConfigurationIsSplitView(_spaceConfiguration)
                                                   : (unsigned long long)(_floatingConfiguration - 1) < 2;
    if ([self topAffordanceView] == [_topAffordanceViewController view]) return;
    [_topAffordanceViewController setHighlighted:nub && cond];
}
// 16.2
    BOOL splitOrFloating = SBSpaceConfigurationIsSplitView(_spaceConfiguration) || (unsigned long long)(_floatingConfiguration - 1) < 2;
    NSUInteger displays = [[[SBApp windowSceneManager] connectedWindowScenes] count];
    BOOL hw = [SBApp isHardwareKeyboardAttached];
    if ([self topAffordanceView] == [_topAffordanceViewController view]) return;
    [_topAffordanceViewController setHighlighted:nub && ((hw && splitOrFloating) || displays > 1)];
```
User-visible: with an external display connected the top affordance of a window is highlighted regardless of keyboard state; with a keyboard it is also highlighted for floating (Slide Over) windows. (Highlight = the nub is drawn in its "active" form; a pointer-friendly affordance.)
Portability: hook `_updateTopAffordanceHighlight`, call `%orig`, then re-apply `setHighlighted:` with the 16.2 formula using ivars read by name (`_nubViewHighlighted`, `_spaceConfiguration`, `_floatingConfiguration`, `_topAffordanceViewController`). `SBSpaceConfigurationIsSplitView` is a C function (dlsym; if missing skip). Group `G3_DecoratedVC` in hooks.m.

**2.4 The three "split view / multiple windows" toasts move out of the decorated VC into a system banner (RELOCATED, not removed; NOT PORTABLE, no parity value).**
16.0: `layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:` (0x1c632b5e8) ends with
`[self _presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:ctx]` (0x1c632fc04) which picks one of three predicates
(`_shouldShowSplitViewNotAvailableYetMessage...` 0x1c632fe9c, `...SplitViewNotSupportedMessage...` 0x1c632fff8, `...MultipleWindowsNotSupportedMessage...` 0x1c6330230) and calls
`[_topAffordanceViewController presentTransientMessageWithImage:title:subtitle:duration:animated:]` with SF symbols `rectangle.split.2x1.slash` / `rectangle.on.rectangle.slash`
and strings `TOP_AFFORDANCE_ERROR_TITLE_{NOT_AVAILABLE_YET,SPLIT_VIEW,MULTIPLE_WINDOWS}`, `TOP_AFFORDANCE_ERROR_SUBTITLE[_USE_DRAG_AND_DROP]`.
16.2: the decorated VC no longer calls it (0x1c77cc710 ends after forwarding to the child VC). The same decision now lives in
`-[SBFullScreenSwitcherLiveContentOverlayCoordinator _presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:medusaViewController:]` (0x1c74cc740):
```objc
SBSwitcherController *sc = [[self _sbWindowScene] switcherController];
if      ([self _shouldShowSplitViewNotSupportedMessageForLayoutStateTransitionContext:ctx medusaViewController:vc])        [sc _presentMedusaBanner:2 fireInterval:0 dismissInterval:1.5];
else if ([self _shouldShowMultipleWindowsNotSupportedMessageForLayoutStateTransitionContext:ctx medusaViewController:vc])  [sc _presentMedusaBanner:3 fireInterval:0 dismissInterval:1.5];
```
(the "not available yet" variant is dropped). `-[SBSwitcherController _presentMedusaBanner:fireInterval:dismissInterval:]` (0x1c7605b58) generalises 16.0's `_presentMedusaEducationBanner` (type 1, fire interval 0.7 s, leeway 0.05 s): it builds `SBMedusaBannerViewController initWithType:orientation:peekConfiguration:` with the current layout
state's orientation, cancels/re-arms `_medusaBannerPresentTimer` (`SBMainSwitcherCoordinator.medusaBannerPresentTimer`) with leeway 0.05 s, and (if dismissInterval > 0) arms a new ivar `_medusaBannerDismissTimer`; `_dismissMedusaBanner` (0x1c7605f14, was `_dismissMedusaEducationBanner`)
invalidates both timers and revokes the presentable (`bannerManager revokePresentablesWithIdentification:reason:@"Dismiss Medusa Education Banner"`). `SBMedusaBannerViewController _bannerView` (16.0 0x1c637cd80 -> 16.2 0x1c782418c, +77 insns) adds the
types 2/3 with strings `MEDUSA_BANNER_ERROR_TITLE_SPLIT_VIEW`, `MEDUSA_BANNER_ERROR_TITLE_MULTIPLE_WINDOWS`, `MEDUSA_BANNER_ERROR_SUBTITLE` (new in 16.2 SpringBoard localizations only) and the same two SF symbols.
Net user-visible effect: the same two messages now appear as a pill banner at the top of the screen (1.5 s) instead of an in-window toast, and also on the external display's switcher. Porting would need the banner types, new
strings (not present in 16.0 .strings) and a second SBSwitcherController ivar; 16.0's existing toast already tells the user the same thing. **Verdict: leave the 16.0 behaviour.** (Corrects an earlier reading in this file that said the messages were removed.)

**2.5 `_topAffordanceViewController:handleActionType:transitionSource:` (16.0 0x1c632ba50 / 16.2 0x1c77ccb6c), MEDIUM.** Action types are `type - 9` in a jump table of 9 entries; the log line prints the type. The full-screen/maximize
menu item's request block changed: 16.0 `{ entity = [[SBDeviceApplicationSceneEntity alloc] initWithApplicationSceneHandle:h]; [req _setRequestedFrontmostEntity:entity]; pol = [h _supportedSizingPolicies];
attrs = [req requestedLayoutAttributesForEntity:entity]; attrs = [attrs attributesByModifyingSizingPolicy:([attrs sizingPolicy] == SmallestOf(pol) ? LargestOf(pol) : SmallestOf(pol))]; [req setRequestedLayoutAttributes:attrs forEntity:entity]; [req setFencesAnimations:YES]; }`
(toggle between smallest and largest) ->
16.2 `{ entity...; [req setEntities:@[entity] withPolicy:0 centerEntity:nil floatingEntity:nil]; [req _setRequestedFrontmostEntity:entity]; pol = [h _supportedSizingPoliciesForContentOrientation:[h currentInterfaceOrientation] containerOrientation:[[scene switcherController] interfaceOrientation]];
attrs = [[req requestedLayoutAttributesForEntity:entity] attributesByModifyingSizingPolicy:SBDisplayItemSizingPolicyAllowingLargestSize(pol)]; attrs = [attrs attributesByModifyingAttributedSize:SBDisplayItemAttributedSizeUnspecified()]; ... }`
i.e. the menu item now always maximizes (no toggle) and resets the attributed size. Another action case wraps `[SBWorkspace mainWorkspace] requestTransitionWithOptions:displayConfiguration:builder:validator:` with `request.source = <captured>` and `modifyApplicationContext:`.
Which menu item each case is was not decoded (LOW). NOT PORTABLE here (block bodies inside a 9-way switch; hook would have to re-implement all cases).

## 3. SBSwitcherController (2 logic changes + traits extraction; user-visible)

**3.1 `setChamoisWindowingUIEnabled:` 16.0 0x1c6178ac0 / 16.2 0x1c76006fc, `isChamoisWindowingUIEnabled` 16.0 0x1c6178a54 / 16.2 0x1c760069c (HIGH).**
```objc
// 16.0
- (void)setChamoisWindowingUIEnabled:(BOOL)e {
    if (_chamoisWindowingUIEnabled == e) return;
    SBLogAppSwitcher(...);                                   // os_log, level 0x10 (error), removed in 16.2
    _chamoisWindowingUIEnabled = e;
    [[[SBDefaults localDefaults] appSwitcherDefaults] setChamoisWindowingEnabled:e];
    [_gestureManager updateForChamoisWindowingUIEnabled:e];
}
// 16.2
    if (_chamoisWindowingUIEnabled == e) return;
    id d = _switcherCoordinator;                              // weak ivar +0xb8
    [d switcherControllerWillUpdateWindowManagementStyle:self];
    _chamoisWindowingUIEnabled = e;
    [[[SBDefaults localDefaults] appSwitcherDefaults] setChamoisWindowingEnabled:e];
    [d switcherControllerDidUpdateWindowManagementStyle:self];
    [_gestureManager updateForChamoisWindowingUIEnabled:e];
```
Delegate (the main switcher coordinator, `SBMainSwitcherControllerCoordinator`): Will = `[self failMultitaskingGesturesForReason:@"Window management style is changing"]` (0x1c76e2bbc; the method exists in 16.0);
Did = `[self _rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary]` (0x1c76e2bc8; new in 16.2, group 1/2). `isChamoisWindowingUIEnabled`: only the availability test changes from a GOT function
pointer call to a direct call of `_SBFIsChamoisWindowingUIAvailable` (refactor): `available && (windowScene.isExternalDisplayWindowScene || _chamoisWindowingUIEnabled)`.
User-visible: toggling Stage Manager while a multitasking gesture is in flight no longer leaves the gesture running; app layouts are rebuilt for the new mode.
Portability: Will part PORTABLE (hook, existing method on the coordinator); Did part NOT PORTABLE here (method does not exist in 16.0; belongs with the app-layout model changes).
The 16.2 poster `SBSwitcherControllerWindowManagementStyleDidChangeNotification` (section 2.1) is emitted from the switcher VC's default-change handler; a 16.0 port posts it after `%orig`.

**3.2 Display canvas size changes re-run the layout (PORTABLE, HIGH for mechanism, MEDIUM for value).** New in 16.2:
```objc
// -[SBAbstractWindowSceneDelegate windowScene:didUpdateCoordinateSpace:interfaceOrientation:traitCollection:]  0x1c74879ac   (UIWindowSceneDelegate callback)
CGSize (^size)(orientation, space) = ^{ CGSize b = space.bounds.size; return (orientation == 3 || orientation == 4) ? BSSizeSwap(b) : b; };   // block 0x1c7487b84
CGSize cur = size(scene.interfaceOrientation, scene.coordinateSpace), prev = size(orientationParam, spaceParam);   // UIKit passes the PREVIOUS space/orientation
CGSize old = prev, nw = cur;
if (!CGSizeEqualToSize(old, nw)) {
    os_log(SBLogDisplayScaleMapping, "display %@ canvas size %@ -> %@", scene._sbDisplayConfiguration.identity, NSStringFromCGSize(old), NSStringFromCGSize(nw));
    [[NSNotificationCenter defaultCenter] postNotificationName:SBWindowSceneCanvasSizeDidChangeNotification object:scene];
}
// SBSwitcherController init (16.2 0x1c75ffe28): addObserver:self selector:@selector(_handleDisplayCanvasSizeChange:) name:SBWindowSceneCanvasSizeDidChangeNotification object:_windowScene
- (void)_handleDisplayCanvasSizeChange:(NSNotification *)n {                                  // 0x1c7607898
    id cfg = [_windowScene _fbsDisplayConfiguration];
    [[SBWorkspace mainWorkspace] requestTransitionWithOptions:0 displayConfiguration:cfg
        builder:^(id req){ [req setEventLabel:@"DisplayCanvasSizeChange"]; }                  // global block 0x1c7607984
        validator:^BOOL(id req){                                                                 // block 0x1c76079d0
            if (![self isChamoisWindowingUIEnabled]) return NO;
            id ls = [self layoutState];
            [req modifyApplicationContext:^(id ctx){ [ctx setRequestedUnlockedEnvironmentMode:[ls unlockedEnvironmentMode]]; }];   // block 0x1c7607a94
            return YES; }];
    [[SBFAnalyticsClient sharedInstance] emitEvent:60];
}
```
Fix: when the display canvas changes size (external display resolution / scale / zoom change, which group 4's `scale` feature now does) Stage Manager windows were left at their old geometry until the next unrelated layout pass; 16.2 forces one.
16.0 has the UIKit callback and every callee (`requestTransitionWithOptions:displayConfiguration:builder:validator:`, `setEventLabel:`, `modifyApplicationContext:`, `setRequestedUnlockedEnvironmentMode:`); the method is not implemented by `SBAbstractWindowSceneDelegate` (not in the 16.0 class dump). Portable as `%new` + observer (hooks.m `G3_Canvas`); the analytics event is skipped.

**3.3 Traits code extracted into `SBSwitcherTraitsAssistant` (NOT PORTABLE as a whole, 16.2 only).** 16.0 `SBSwitcherController` had `_createTraitsParticipantsForLayoutElementsIfNeeded:shouldPerformFirstResolution:` (0x1c6179530), `_updateParticipantsAndPoliciesWithSwitcherPolicy:nonPrimaryOverlayPolicy:primaryOverlayPolicy:` (0x1c6179c04), `_currentElementsOrientationsForLayoutState:`,
`_updateAppTransitionContext:withOrientationActuationContext:accountForSceneState:`; 16.2 moves them into `SBSwitcherTraitsAssistant` (ivars: policy specifiers, `_guidingPortraitOnlyParticipant`, `_guidingLandscapeOnlyParticipant`, `_guidingSceneOrientationRequestParticipantsMap`,
`_participantUniqueIDToAssociatedParticipantMap`) and adds the "guiding" relationship: for iPhone-only app windows the assistant creates extra portrait-only / landscape-only guiding participants chosen by `_isContentContainerAspectRatioPortrait` (window aspect), pairs them with the window's scene participant
(`_setupGuidingRelationshipIfNeededForParticipant:withSceneHandle:`, which also calls `_setInterfaceOrientationFromUserResizing:`), so the traits arbiter resolves the app's orientation from the window shape instead of the device. It observes `SBClassicPhoneSceneOrientationPreferenceChanged`
(posted by `-[SBDeviceApplicationSceneView(ClassicSupport) noteApplicationClassicPhoneSceneOrientationPreferenceChangingForUserAction:]`, 0x1c773ecdc) and `SBSceneGeometryOrientationRequestChanged`. SBSwitcherController itself gains `currentElementsParticipants`, `sceneHandleForTraitsParticipant:`,
`actuateOrientationForTraitsDelegate:withContext:reasons:`, `_noteLayoutStateEvaluationBegan/Ended...`, `isOnExternalDisplay`, `contentContainerAspectRatio`, and the `SBFluidSwitcherGestureManagerDelegate` methods listed in section 5.
Rewriting 16.0's participant creation to this design = a re-implementation of the whole traits glue; not a hook. Depends on 1.x.

## 4. Medusa hosted keyboard window: from "the main display scene manager" to a per-window-scene controller (user-visible on external displays; NOT PORTABLE)

16.0: `SBMainDisplaySceneManager` owned everything (ivars `_medusaHostedKeyboardWindow` +0x118, `_isUsingMedusaHostedKeyboardWindow` +0x158; methods `_updateMedusaHostedKeyboardWindow` 0x1c63d6fcc,
`_updateMedusaHostedKeyboardWindowForScene:isForeground:` 0x1c63d7070, `newMedusaHostedKeyboardWindowLevelAssertionWithPriority:windowLevel:` 0x1c63d6f54, `_isKeyboardVisibleForSpringBoard` 0x1c63d6dfc,
`_keyboardLayersClientSettingsDiffInspector` 0x1c63d51a0), and `SBSystemShellExternalDisplaySceneManager` had its own `_updateMedusaHostedKeyboardWindow` stub. The hosted keyboard window (a window in SpringBoard that presents the single
keyboard scene, `_SBHostedKeyboardViewController`, when Stage Manager is on or the foreground app is not classic) therefore only ever existed on the embedded display.

16.2: `SBMedusaHostedKeyboardWindowController` (new; ivars `_observers`, `_windowScene` (weak, set by `initWithWindowScene:` 0x1c7626c38), `_keyboardLayersClientSettingsDiffInspector`, `_isUsingMedusaHostedKeyboardWindow`, `_medusaHostedKeyboardWindow`)
is owned per window scene: `-[SBWindowSceneContext medusaHostedKeyboardWindowController]` / `-[SBWindowScene medusaHostedKeyboardWindowController]`. The 16.0 methods moved over with the same names minus the underscore
(`updateMedusaHostedKeyboardWindow`, `updateMedusaHostedKeyboardWindowForScene:isForeground:`, `isKeyboardVisibleForSpringBoard`, `newMedusaHostedKeyboardWindowLevelAssertion...`) and the observer set
(`addObserver:`/`removeObserver:`, protocol `SBMedusaHostedKeyboardWindowControllerObserver.usingMedusaHostedKeyboardWindowDidChange`; `SBKeyboardHomeAffordanceController` and `SBSpotlightMultiplexingViewController` now observe the controller instead of
`SBMainDisplaySceneManagerObserver`). I compared the call graph of `...ForScene:isForeground:` (16.0 611 insns vs 16.2 617): identical except
* the candidate scene must belong to this controller's display: `[[scene settings] sb_displayIdentityForSceneManagers] isEqual:[_windowScene _fbsDisplayIdentity]` (new first test), the external foreground app scenes come from
  `sceneManagerForDisplayIdentity:` of that display instead of the main display scene manager;
* `isClassic` -> `supportsChamoisSceneResizing` (= `isMedusaCapable`);
* the Stage Manager test uses the controller's own `_windowScene.switcherController` instead of `[handle _windowScene]`.
New `-shouldKeyboardBeWindowSizedForHostWithIdentity:` (0x1c7627434): `scene = [FBSceneManager sceneFromIdentityToken:id]; app = <application of the scene's client process>; return scene.uiSettings.enhancedWindowingEnabled && ![app supportsChamoisSceneResizing]` (an app that cannot be resized and runs in an enhanced-windowing scene gets a window-sized keyboard).
Client-settings trigger: `scene:didUpdateClientSettingsWithDiff:...` (0x1c76281dc) for the keyboard scene identifier while `![UIKeyboard usesInputSystemUI]` and the scene is foreground builds a `SBKeyboardClientSettingObserverContext` (new, 3 strong ivars: scene, diff, settings) and runs `_keyboardLayersClientSettingsDiffInspector evaluateWithInspector:context:` (that inspector then calls `updateMedusaHostedKeyboardWindow...`).

`SBMedusaHostedKeyboardWindow` (3 changed): `initWithWindowScene:keyboardScene:` (16.0 0x1c60ff268 / 16.2 0x1c75844cc) registers for two new notifications, `-setHidden:` (0x1c60ff950 / 0x1c7584c48) posts
`_SBMedusaHostedKeyboardWindowWillShowNotification` (before unhiding) / `..WillHideNotification` (before hiding) with itself as object, and the new handlers `medusaHostedKeyboardWindowWillShow:` (0x1c7584e00) / `...WillHide:` (0x1c7584eb4)
deactivate this window's `_remoteHostedKeyboardScenePresenter` if the sender is a different window and it is active. Purpose (MEDIUM): the one keyboard scene can only be presented in one display's window at a time, so showing it on display B deactivates the presenter on A.
New `-invalidate` (0x1c758486c) invalidates the presenter and `_defaultWindowLevelAssertion`; `-dealloc` now calls it (16.0 `dealloc` invalidated the same two objects inline).

Verdict: **NOT PORTABLE**. The 16.0 owner (`SBMainDisplaySceneManager`) calls its own private methods from ~10 places (observer fan-out, `SBKeyboardHomeAffordanceController`, spotlight, home affordance), and
`SBSystemShellExternalDisplaySceneManager` has no keyboard path at all. A port would be (a) a new `SBMedusaHostedKeyboardWindowController` class (~250 lines: copy of the 16.0 scene manager methods parametrised by window scene), (b) per-scene storage through an associated
object on `SBWindowSceneContext` (ivar impossible), (c) forwarding the 16.0 scene manager callbacks, (d) re-pointing all observers. The window-level changes alone (notifications + deactivate handlers + `invalidate`) are PORTABLE
(`%hook SBMedusaHostedKeyboardWindow`, three ObjC methods plus `%new`) but have no effect while only one such window exists, so they are not drafted. Open question: with ExtendedDisplayEnabler on 16.0, does an app on the external display get its keyboard from the iPad's window (16.0 behaviour) — needs a device.
