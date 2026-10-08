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
| SBMedusaBannerViewController | 1 | pending | |
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

