# GAPS-IMPLEMENTED-0.7.9: what was done for the gaps of FEATURES-0.7.9.md

Static analysis only (16.0 = 20A8372 and 16.2 = 20C65 dyld caches), nothing has run on a device. Addresses are unslid vm addresses of the SpringBoard image. New source files carry the full 16.2 reading in their header comments; this document lists, per gap, the 16.2 mechanism, what was implemented, the switch, the log lines and what is unproven. Log lines are written with `BP_Log` and therefore only while `<jbroot>/tmp/Backport162.debug` exists. Every switch is default ON and has a kill file `<jbroot>/tmp/Backport162.off.<switch>`.

Shared helper header: `BPX.h` (nil-safe `objc_msgSend` helpers, `BPX_Replace`).

## G2 Overlays on the embedded display (audit T1) — X2Overlay.x

### 16.2 mechanism

The 16.0 consumers of `-[SBTransientOverlayViewController prefersEmbeddedDisplayPresentation]` exist already; what 16.0 lacks is the answer of the view controllers and three consumer details.

| piece | 16.0 | 16.2 |
|---|---|---|
| base getter (ivar `_prefersEmbeddedDisplayPresentation` 0x3f8, never set for local overlays) | 0x1c64d32e8 | 0x1c798ea64 (same) |
| `SBPowerDownViewController` | YES 0x1c5ed0e28 | YES 0x1c7344e94 |
| `SBControlCenterModuleTransientOverlayViewController` | base | YES 0x1c7567e88 |
| `SBInCallTransientOverlayViewController` | base | YES 0x1c75da010 |
| `SBPasscodeEntryTransientOverlayViewController` | base | YES 0x1c76fb2c4 |
| `SBVoiceControlTransientOverlayViewController` | base | YES 0x1c7841a2c |
| `SBSpotlightTransientOverlayViewController` | base | `presentationSource == 1 \|\| presentationSource == 7` 0x1c76bb71c (ivar `_presentationSource` 0x540) |

These are all the classes of the 16.2 cache with their own getter (class dump grep plus a disassembly of each). The Spotlight getter is NOT a constant YES as the audit said. The sources SpringBoard writes in 16.2: 1 by the interactive pull-down gesture (`beginInteractiveSpotlight...` block 3, 0x1c7352f30), 5 or 6 by `-toggleSearchFromBreadcrumbSource:withWillBeginHandler:completionHandler:` 0x1c7352218 (`mov w8,#5; cinc x8,x8,eq` on the breadcrumb flag: breadcrumb 5, otherwise 6, which is what `-_toggleSearch` (the keyboard shortcut) passes), 7 is never written by SpringBoard itself. So in 16.2 the Cmd-Space shortcut opens Spotlight on the ACTIVE display (the monitor when the pointer is there), only the pull-down gesture and source 7 force the iPad. The audit's remark "Cmd-Space always opens on the iPad" was wrong for Spotlight.

Consumers:
* `-[SBMainWorkspace presentTransientOverlayViewController:animated:completion:]` 16.0 0x1c5f0d924 / 16.2 0x1c7382038: identical logic (YES -> `[[workspace mainWindowScene] _fbsDisplayConfiguration]`, NO -> `[transientOverlayPresentationManager defaultDisplayConfigurationForTransientOverlayPresentation]`, which is the active display's configuration in both builds, 0x1c616c908 / 0x1c75f4400). Complete in 16.0, nothing to port.
* `SBRemoteTransientOverlaySession activateWithContext:` block: 16.0 0x1c63c0b24 (prefers at 0x1c63c0c00 / 0x1c63c0c88) / 16.2 0x1c786b2d0 (0x1c786b3c0 / 0x1c786b534): same logic, 16.2 adds log lines. Complete in 16.0.
* NEW in 16.2: `-[SpringBoard beginInteractiveSpotlightTransientOverlayPresentationWithValidator:beginHandler:]` 0x1c7352bf8 (16.0 0x1c5edeaa8) asks the spotlight view controller (ivar `_spotlightTransientOverlayViewController`) and makes the request with `requestTransitionWithOptions:displayConfiguration:builder:validator:` (configuration as above); 16.0 used `requestTransitionWithOptions:builder:validator:` (nil configuration).
* NEW in 16.2: `-[SBMainWorkspaceTransitionRequest modifyTransientOverlayContext:]` 0x1c7893a84 (16.0 has only `SBWorkspaceTransitionRequest`'s, 0x1c5f42304, unchanged in 16.2 at 0x1c73b6920): super, then if `context.transitionType == 0` and `context.transientOverlay.viewController.prefersEmbeddedDisplayPresentation` then `context.windowScene = [request.workspace mainWindowScene]`. 16.0 did this only inside the builder block of `presentTransientOverlayViewController` (0x1c5f0dc64..0x1c5f0dc84); 16.2 removed it from that block and put it in the request class, so every caller of `modifyTransientOverlayContext:` gets it: `SBSpotlightTransientOverlayInteractiveGestureTransaction _presentTransientOverlayViewController:` (0x1c7426958), `SBInCallPresentationSession` (blocks 0x1c757ba7c, 0x1c757c620 and `_configureTransitionRequest:forPresentingTransientOverlay:animated:` 0x1c7580ff4). In 16.0 those paths never reached the iPad.
* NEW in 16.2: `-[SBMainWorkspace _executeTransientOverlayTransitionRequest:]` 0x1c7375028 (16.0 0x1c5f00d54): for a context that preserves the app switcher the unlocked environment mode that decides `applicationContext.requestedUnlockedEnvironmentMode = 2` is read from the switcher controller of the REQUEST's display (`[SBApp windowSceneManager] windowSceneForDisplayIdentity:[request displayIdentity]` -> `switcherController` -> `unlockedEnvironmentMode`; no controller: `NSLog(@"expected a switcherController!")` and mode 0). 16.0 read `[SBMainSwitcherControllerCoordinator sharedInstance] unlockedEnvironmentMode`, which is the ACTIVE display's switcher (0x1c623a020 -> `_activeDisplaySwitcherController`). 16.2's coordinator method is the same (0x1c76cd528).
* Not display related and left as in 16.0: `toggleSearchFromBreadcrumbSource:...` (419 -> 403 insns) only fetches the lock screen's switcher controller per window scene to log "expected a switcherController!".

### Implemented

* `class_replaceMethod` of the five getters (Spotlight with the 16.2 formula). With the switch off the original IMP (the inherited base getter) answers.
* `SBMainWorkspaceTransitionRequest modifyTransientOverlayContext:` override (the super IMP is `SBWorkspaceTransitionRequest`'s, found through the method lookup).
* `SpringBoard beginInteractive...` hook arming a one-shot redirect in `SBMainWorkspace requestTransitionWithOptions:builder:validator:` to the 4-argument method with the 16.2 configuration (a hook of the 3-argument method alone would not know the caller).
* `_executeTransientOverlayTransitionRequest:` hook that arms, only when the context preserves the app switcher, a one-shot override of `SBMainSwitcherControllerCoordinator unlockedEnvironmentMode` which returns the mode of the request display's switcher (16.2 semantics, nil switcher -> 0 plus the NSLog).

### Switches and logs

`embedoverlay` (everything; the getters and hooks are installed unconditionally at launch and test the switch on every call, so the kill file works without a respring) and `embedoverlay_envmode` (the per-display mode read only). Log lines: `[x2] <class> prefersEmbeddedDisplayPresentation installed` (launch), `[x2] modifyTransientOverlayContext: <vc class> prefers the embedded display: context.windowScene = ...`, `[x2] interactive Spotlight request: spotlight vc ... prefers embedded = N, display configuration ...`, `[x2] transient overlay request preserves the app switcher: unlocked environment mode of its own display = N`, and `NOT installed (...)` lines if a class or selector is missing.

### Unproven / needs a device

Nothing was run. Check with the pointer on the monitor: Control Centre swipe (module overlay), passcode, an incoming call banner / in-call overlay, voice control, the Spotlight pull-down (iPad) and Cmd-Space (monitor). The `NOT installed` log lines show whether any 16.0 selector was missing. The 16.2 `SBInCallPresentationSession` itself is only partly ported (gap G6).

## G8 Zoom / full-screen labels (audit Z1) — BPLoc.h, BPL10N.h (generated), G3.x, G3B.x, G4B.x

### 16.2 mechanism

16.2's SpringBoard.loctable (`SpringBoard.app/SpringBoard.loctable`, read from the 20C65 IPSW; 16.0's from the device) differs from 16.0's in 9 added keys and 9 removed keys, nothing else (428 keys identical):

| added in 16.2 (en) | removed vs 16.0 |
|---|---|
| `TOP_AFFORDANCE_MENU_TITLE_MAXIMIZATION_ZOOM` "Enter Full Screen" | `TOP_AFFORDANCE_MENU_TITLE_MAXIMIZATION` |
| `TOP_AFFORDANCE_MENU_TITLE_MAXIMIZATION_UNZOOM` "Zoom" | `ZOOM_DISCOVERABILITY`, `NEXT/PREVIOUS_APP_WINDOW_ON_STAGE_DISCOVERABILITY` |
| `ENTER_FULL_SCREEN_DISCOVERABILITY` "Enter Full Screen" | `TOP_AFFORDANCE_ERROR_TITLE_SPLIT_VIEW`, `_TITLE_MULTIPLE_WINDOWS`, `_SUBTITLE`, `_SUBTITLE_USE_DRAG_AND_DROP`, `_TITLE_NOT_AVAILABLE_YET` |
| `MEDUSA_BANNER_ERROR_TITLE_SPLIT_VIEW` "Split View", `_TITLE_MULTIPLE_WINDOWS` "Multiple Windows", `_SUBTITLE` "Not Supported" | |
| `STAGE_MANAGER_EXTENDED_DISPLAY` "External Display", `_ON` "Stage Manager On", `_OFF` "Stage Manager Off" | |

Consumers (all read the main bundle, table `SpringBoard`): `-[SBTopAffordanceViewController _localizedMenuTitleForKey:]` (16.0 0x1c645b064 / 16.2 0x1c790df64) for the three-dots menu (isZoomed NO -> `..._ZOOM` = "Enter Full Screen", YES -> `..._UNZOOM` = "Zoom", 16.2 0x1c790cba8); `-[SpringBoard buildMenuWithBuilder:]` (16.0 0x1c5ee2a40 ZOOM_DISCOVERABILITY at 0x1c5ee3870; 16.2 0x1c7356c84 ENTER_FULL_SCREEN_DISCOVERABILITY at 0x1c7357a60) sets `discoverabilityTitle` of the full-screen key command, which is the text of the Cmd-hold overlay; `SBMedusaBannerViewController` (G3B) for the banner texts; `-[SBExternalDisplayEducationPillViewController _pillSubtitleContentItem]` (16.2 0x1c77e8104) for `STAGE_MANAGER_EXTENDED_DISPLAY_ON/_OFF` (table `SpringBoard`).

### Implemented

* `tools/gen_bpl10n.py` generates `BPL10N.h` (never hand edited) from the 16.2 loctable: the 9 added keys x 41 languages (the loctable's own language codes, non-ASCII as universal character names). All languages were cheap, so no "English only" note.
* `BPLoc.h`: `BPLoc_String(key, key160, english)` asks the real bundle table first (a bundle that has the key wins), then the embedded table for the user's language (`[NSLocale preferredLanguages]` mapped to loctable codes: zh-Hant/TW -> zh_TW, HK/MO -> zh_HK, other zh -> zh_CN, pt-PT -> pt_PT, es-<non-ES region> -> es_419, en-GB/en-AU, fr-CA, nb/nn -> no, iw/in), then the English entry, then the optional 16.0 key, then the literal.
* G3.x `BP_G3_ZoomTitle`: the 16.2 keys through `BPLoc_String` (was: 16.0 key for Zoom, literal "Unzoom" for the zoomed state, so the label read "Zoom"/"Unzoom" instead of 16.2's "Enter Full Screen"/"Zoom").
* G3B.x `BP_G3B_Localized` (Stage Manager error banners) and the full-screen key command's `discoverabilityTitle` (Cmd-hold overlay) use it. Before, the discoverability title was only replaced when the bundle itself had the key (never on 16.0).
* G4B.x `G4B_Localized` (education pill) now reads the `SpringBoard` table through `BPLoc_String` and the 16.2 English fallbacks "External Display" / "Stage Manager On" / "Stage Manager Off" (it used `table:nil`, the Localizable table, which has none of these keys, and the made-up fallbacks "Extended Display" / "On" / "Off").

### Switch and logs

`l10n162` (default on). Off = the old behaviour of each call site. No log lines (pure lookups).

### Unproven

No device run. The Control Centre "External Display" tile text belongs to the SMT.x/Control Centre side and is stock. `NEXT/PREVIOUS_APP_WINDOW_ON_STAGE_DISCOVERABILITY` are removed keys of 16.2 and not used any more by the port (the plain titles already exist in 16.0). The `SpringBoardEducation.app` strings (`EXTERNAL_DISPLAY_*`, audit E1) live in another bundle and were not embedded.

## G9 pinOnButtonDown for the system gesture windows (audit P1) — X9Pin.x

### 16.2 mechanism

`-[SBSystemGestureManager _configureForNewSystemGestureWindowIfNecessary]` (16.0 0x1c6319958 / 16.2 0x1c77b912c) registers the display's system gesture window for global mouse events. 16.0 (call at 0x1c6319b88): `[[BKSMousePointerService sharedInstance] requestGlobalMouseEventsForDisplay:hardwareIdentifier targetContextID:contextId]`. 16.2 (call at 0x1c77b937c): the `options:` variant with `[BKSMousePointerGlobalContextOptions build:^(m){ [m setPinOnButtonDown:SBFIsChamoisExternalDisplayControllerAvailable()]; }]` (block 0x1c77b9458); the assertion is stored in the same ivar (+0x60). In BackBoardServices 16.0 the 2-argument method (0x18e2051d8) is a tail call of the 3-argument one (0x18e204d9c) with options nil, `+[BKSMousePointerGlobalContextOptions build:]` (0x18e228a68) and `-[BKSMutableMousePointerGlobalContextOptions setPinOnButtonDown:]` (0x18e2284b4) exist, and backboardd 16.0 reads the flag (bbd 0x100050f28, POINTER-CROSS-0.7.4 4.3). The only caller of both request methods in SpringBoard 16.0 and 16.2 is `_configureForNewSystemGestureWindowIfNecessary` (stub caller scan). The flag function is `SBFFeatureFlagsIsChamoisExternalDisplayControllerEnabled` in 16.0 (SpringBoardFoundation 0x18eb68fd4) and `SBFIsChamoisExternalDisplayControllerAvailable` in 16.2 (0x18ee096e4); the 16.0 plist has the feature ON, so the value is YES.

The audit's outline (hook the 2-argument method and forward) was adapted: because the 2-argument method forwards to the 3-argument one with options nil, the hook sits on the 3-argument method and substitutes a nil options argument.

### Implemented

X9Pin.x: `_configureForNewSystemGestureWindowIfNecessary` hook raising a thread local while the original runs; `-[BKSMousePointerService requestGlobalMouseEventsForDisplay:targetContextID:options:]` hook that, while raised and when options is nil, builds the 16.2 options (dlsym of the 16.2 flag name, then the 16.0 name; missing class or selector -> request unchanged plus a log line).

### Switch and logs

`pinbuttondown` (default on; the hooks test it per call). Logs: `[x9] pinOnButtonDown for system gesture windows: installed | NOT installed`, `[x9] global mouse events for display ... options ... (pinOnButtonDown N)` (one line per display when its gesture window is created), error lines if the class or the flag function is missing.

### Unproven

Nothing was run. Drag a window by the pointer from one display over the boundary: it should keep following the pointer; the daemon log (`Backport162.daemon.log`, lines `g4b-bbd`/stock "pinning global destination") shows the pin. Only matters for system gesture windows created after the tweak loaded (the window of a display that is connected later is configured after load; the main display's window may have been configured before the tweak loaded on a respring-less install, a respring fixes that).

## G7 Keyboard focus tracker and display scoped suppression (audit S2) — X7Keyboard.x, Group4Focus.x

### 16.2 mechanism (details and addresses in the X7Keyboard.x header)

* `_SBActiveDisplayKeyboardFocusTracker` (new, `SBActiveWindowSceneTracking`): `activeWindowScene` 0x1c74bfb9c = the keyboard focus controller's `windowSceneWithFocus` (+ a log-only `explainWhyYouAreFocusingAnInvalidatedScene` 0x1c77c3f4c when the scene is invalidated). Owned by `SBWindowSceneManager` (`initWithUserInteractionCoordinator:` 0x1c74bf0f4, ivar +0x10); `activeDisplayWindowSceneFollowingKeyboard` 0x1c74bf244 validates its answer.
* Display scoped scene deactivation: `SBKeyboardSuppressionManager` `startSuppressing...:displayIdentity:` 0x1c75376dc, `acquireKeyboardSuppressionAssertion...:displayIdentity:` 0x1c75376f0, `_setKeyboardSuppressed:forReason:withPredicate:displayIdentity:` 0x1c75378ac and `UIApplicationSceneDeactivationAssertion(SBWindowScene)` `sb_acquireForDisplayIdentity:` 0x1c77af7a0 / `sb_acquireWithPredicate:transitionContext:displayIdentity:` 0x1c77af7b0 (predicate block 0x1c77af874: user predicate AND `settings.sb_displayIdentityForSceneManagers isEqual:identity`). The 16.0 `_setKeyboardSuppressed:...` body (0x1c5e309f0) is otherwise identical. 6 suppression callers and 8 resign-active callers pass their display in 16.2 (table in the file header); three suppression callers pass nil (= 16.0 behaviour, nothing to port) and `SBUniversalControlServer`'s block passes the active display.
* External scene identities: client `SBSKeyboardFocusService setExternalSceneIdentities:forReason:` -> server `SBKeyboardFocusService setExternalSceneIdentities:` 0x1c733696c, `_lock_updateExternalSceneIdentities` 0x1c73372d4, `_handleDisconnectForServiceConnection:` 0x1c7336f1c, controller `externalSceneIdentities` 0x1c77c8f88 / 0x1c77c8f94.

### Implemented

* Tracker as the runtime class `BPActiveDisplayKeyboardFocusTracker` (a 16.0 runtime must not carry the 16.2 name) with `SBWindowSceneManager keyboardFocusTracker` / `setKeyboardFocusTracker:` (created lazily: the 16.0 manager exists before the tweak loads); `adopts SBActiveWindowSceneTracking` if the 16.0 runtime has that protocol. Group4Focus.x `activeDisplayWindowSceneFollowingKeyboard` goes through it (`X7_TrackerScene`), falling back to the controller read only when the tracker is switched off.
* The three manager methods and two assertion methods under their 16.2 selectors. The `displayIdentity:` suppression reuses the 16.0 `_setKeyboardSuppressed:` body: a thread local identity is turned by a hook of `acquireWithPredicate:transitionContext:` (reason 8 only) into `sb_acquireWithPredicate:...displayIdentity:`.
* The 14 callers are wrapped (class_replaceMethod): the wrapper arms a one-shot thread local scope (kind + object), evaluated lazily with the 16.2 expression for that caller when the old API (`startSuppressingKeyboardWithReason:predicate:` / `acquire...:predicate:`) or the assertion's `-acquire` is reached inside the wrapped method; that call is then redirected to the `displayIdentity:` / `sb_acquireForDisplayIdentity:` variant. CommandTab's identity is read eagerly at entry (16.2 reads the active scene at the top of the method).
* External scene identities server API, with the per-connection map as an associated object (a runtime cannot add ivars to the 16.0 class), authentication through `_serviceClientAuthenticator`, union into the controller, and the disconnect clean-up (16.2 does it inside the original lock; here after the original returns).

### Switches and logs

`kbtracker`, `kbsuppress`, `kbextscenes` (default on; hooks installed at launch, switches tested per call). Logs: `[x7] keyboard focus tracker ... installed`, `[x7] display scoped keyboard suppression / resign active installed` (or `... NOT installed` / `-[Class sel] not found, not wrapped` for each missing target), `[x7] resign active assertion (kind N) acquired for display ...`, `[x7] startSuppressingKeyboardWithReason:... for display ...`, `[x7] keyboard suppression assertion acquired for display ...`, `[x7] external scene identities: ...`, `[x7] keyboard focus controller focuses the invalidated window scene ...`.

### Not ported / unproven

* The client call `setExternalSceneIdentities:forReason:` cannot reach the server on 16.0 (no 16.0 process sends it, the 16.0 SBS interface lists no such method), so the set is always empty and the controller never uses it; the consumer branch in `_filterFocusedSceneIdentityToken:focusedPID:resultBlock:` (0x1c77c4590, +98 instructions: "arbiter advice (known external scene)", "ignoring non-focused OverlayUI request") is not ported (345 -> 443 instruction method built on objc_direct helpers of `_SBRecentlyUsedSceneIdentityCache`).
* `SBUniversalControlServer`'s suppression block is a block of the class (not hookable by selector): it keeps the 16.0 meaning (every display).
* Each wrapper assumes the wrapped 16.0 method acquires one deactivation assertion / starts one suppression (checked in the callers scan: one call site each); an earlier unrelated acquire inside the same call would take the scope. Needs a device: with an app in front on the monitor, open Control Centre, drag a window, use the Spotlight pull-down or Cmd-Tab on the iPad: the monitor app must neither resign active nor lose its keyboard.

## G6 Remote-alert targets and in-call per scene (audit A1 + A2) — X6InCall.x, G4B.x

### A2 In-call presentation per scene: implemented

16.0 `SBInCallPresentationSession` (init 0x1c60f0a10) gets a `UIScreen` and the MAIN display's scene manager from `-[SBMainWorkspace inCallPresentationManager:createPresentationSessionWithSceneHandle:]` (0x1c5efeb60) and registers everything in its init. 16.2 (0x1c7372e7c, init 0x1c75754c0) passes neither: `_screen` / `_sceneManager` are derived (`-_sceneManager` 0x1c7583494, `-_screen` 0x1c75834e0) from a weak window scene that `transitionToSceneHandleIfNeeded:` (0x1c7575954) sets from `[windowSceneManager windowSceneForDisplayIdentity:[handle displayIdentity]]`; `sceneHandle:replacedWithSceneHandle:` (0x1c757a10c) re-targets a session whose scene moved (sent by SpringBoardUI's `SBSceneHandle -_noteReplacedWithSceneHandle:` 0x1f2ccc7ec from `takeScene:fromSceneManager:` 0x1c73e9a3c); `SBInCallPresentationManager sceneManager:didTransferManagementOfScene:toSceneManager:` (0x1c76696ac, the only implementer of that observer callout) observes the new scene manager and runs the zombie checks; `_runZombieChecksForScene:` looks the handle up in the scene's own display scene manager (16.0 0x1c61dd4c0: always the main one, 16.2 0x1c766ba00).

Implemented (X6InCall.x, written against the 16.0 ivars because a runtime cannot remove them): after the workspace made a session its `_sceneManager` / `_screen` follow its window scene (layout transition observer moved; the ignore-suspended-under-lock assertion kept only for a main display scene manager, as 16.2); `transitionToSceneHandleIfNeeded:` and `sceneHandle:replacedWithSceneHandle:` as 16.2; `SBSceneHandle _noteReplacedWithSceneHandle:` (it was missing in 16.0, so the call G4B.x already made did nothing); the manager's `sessionForSceneIdentifier:`, `sceneManager:didTransferManagementOfScene:toSceneManager:` and the 16.2 `_runZombieChecksForScene:` (replacement); the observer callout at the top of the G4B.x `takeScene:fromSceneManager:` hook (before the original, like 16.2). Switch `incallscene`. Logs: `[x6] in-call session ... scene manager A -> B`, `... moved to scene handle ...`, `[x6] in-call manager: scene ... transferred ...`, `[x6] in-call per scene NOT installed (class or selector missing)`.

Not ported (not display related): the non modal call suppression (`acquireNonModalSuppressionAssertionForReason:`, `setNonModalPresentationsSuppressed:`, used by `SBTransientOverlayScenePresenter _updateFeaturePolicies`). The in-call overlay's own display choice is the G2 port (`SBInCallTransientOverlayViewController` answers YES).

### A1 Remote alert targets: smaller than the audit said, not implemented (recorded, no guessing)

`SBSRemoteAlertPresentationTarget` / `...Predicate` are SpringBoardServices classes: the objects SpringBoard 16.0 decodes are made by the 16.0 library from what 16.0 clients send (process, scene persistent identifier, flags), so the predicate's `launchingApplicationIdentity` and the target's `shouldDismissInSwitcher` can never be set. With a process predicate the SpringBoard side added by 16.2 reduces to what 16.0 already does: `-[SBSRemoteAlertPresentationTargetPredicate(SpringBoard) targetApplicationWithController:]` (0x1c7787d68) is `applicationWithPid:` for a process predicate, `matchesOverlayViewController:` (0x1c7787e8c) is `isPresentedByProcess:`, `configureTransientOverlayContext:` (0x1c7787f4c) is `setOriginatingProcess:`; `-[SpringBoard remoteTransientOverlaySessionManager:performPresentationRequest:forSession:]` 16.2 0x1c735acb8 vs 16.0 0x1c5ee6ca0 differs in (a) that resolution, (b) the Siri exception (`shouldDismissSiri` is cleared when the topmost presented view controller is Siri-activating and matches the target; Siri, not display related) and (c) the presenter of the request's display for that check. The display choice of the embedded path (window scene from the request, else the active display) is identical in both builds (0x1c5ee706c / 0x1c735b0d8). `shouldDismissInSwitcher` is read by `SBDeviceApplicationRemoteTransientOverlayViewProvider _handleAppSwitcherWillPresent:` (0x1c78b1b88), dead for 16.0 clients. A port would need a full replacement of that 429 instruction method and two of its blocks for the Siri exception only, plus inert SBS category methods; not done. `SBAlertItemPresenterWindowSceneResolver resolvedSharedModalAlertItemPresenterForAlertItem:` (16.0 0x1c6045050 / 16.2 0x1c74c0984, 43 -> 62 instructions) only gains a middle fallback between the alert controller's window scene and the active display: `SBAlertItem _preferredActivationWindowScene` (a SpringBoardUI property new in 16.2, ivar 0x58). Nothing in the 16.2 SpringBoard image ever sets it (no caller of its setter), and 16.0 has no such property, so on 16.0 the fallback is always the active display, as before. `_hasVisibleModalAlertOfType:forWindowScene:` was not decoded.

### Unproven

Nothing was run. Only observable with a call-capable app (FaceTime / Phone UI) whose scene is on the monitor while the monitor is unplugged or the scene is moved.

## G5 Per-display recording indicator (audit R1) — X5Recording.x

### 16.2 mechanism

16.0 has one `SBRecordingIndicatorManager`, made for the main display window scene by `-[SpringBoard _startRecordingIndicatorForMainDisplayWindowScene:]` (0x1c5edc0e8: `initWithSensorActivityDataProvider:windowScene:` with `[SBApp sensorActivityDataProvider]`, kept by `SBEmbeddedDisplayWindowSceneDelegate`, getter 0x1c63a1564); `-[SpringBoard recordingIndicatorManagerForMainDisplay]` (0x1c5eecae0) is what the status bar code asks (callers: `SBDeviceApplicationSceneViewController _configureStatusBarWithCurrentStyleRequest` 0x1c6131a18, `SBStatusBarStateAggregator _updateSensorActivityItem`, `SBMainDisplaySceneLayoutStatusBarView` x2, `SBTransientOverlayScenePresenter _updateStatusBarWithCurrentExternalStatusBarSettings:animated:` 0x1c6496498, `SBRecordingIndicatorSystemApertureElement` x2). 16.2: every window scene delegate makes its own manager (`SBEmbeddedDisplayWindowSceneDelegate` 0x1c784b4b4, `SBExternalDisplayWindowSceneDelegate` 0x1c7467ed8: `initWithWindowScene:` 0x1c74617f0, stored in the `SBWindowSceneContext`), `-[SBWindowScene recordingIndicatorManager]` (0x1c77f82ac) hands it out and the per scene consumer asks its own scene (the view controller: `[[self _sbWindowScene] recordingIndicatorManager]` 0x1c75bc7c4); the aggregator / layout view / aperture element keep the main display, the overlay presenter no longer calls it. `_screenTypeForcesFastFadeAnimations` changed to the Jindo artwork subtypes (iPhone only). The manager class body is unchanged (only its init and `_createRecordingIndicatorForStatusBarLocation` 62 -> 66 instructions).

### Implemented

A manager per external window scene (16.0 initializer and provider, made after the original `_configureForConnectingWindowScene:windowSceneContext:`), kept by the external delegate (associated object plus `recordingIndicatorManager` / `setRecordingIndicatorManager:`), `SBWindowScene recordingIndicatorManager`, and the view controller's status bar configuration wrapped so that `recordingIndicatorManagerForMainDisplay` answers the manager of the VC's own window scene while it runs. Switch `recindicator`. Logs: `[x5] recording indicator manager ... for external window scene ...`, `[x5] per display recording indicator installed | NOT installed`.

### Unproven

Whether the 16.0 manager's `_createRecordingIndicatorForStandaloneLocation` / status bar location choices place the indicator sensibly on a monitor was not analysed (the same class code runs in 16.2 for the external scene). The status-bar half inside apps (UIKit `registerSensorActivityIndicator:forScreen:`) is app side and not done. Needs a device: camera / microphone app with a monitor connected, dot on the monitor.

## G3 Monitor scale and mode choice (audit D1) — X3Mode.x

### 16.2 mechanism (full reading with addresses in the X3Mode.x header)

What was audited as "mapping, criteria, `_ensureCADisplayUpToDate`, cloningSupported not ported" turned out smaller once the 16.0 side was decoded:

* `SBDisplayScaleMapping` (SpringBoardFoundation): the new `initWithDisplayHardwareIdentifier:nativePPI:nativeSize:scaleMethod:supportedScales:displayScaleToLogicalScale:` (16.2 0x18ee470f8) and the `availableModes` walk in `+withDisplay:allowWirelessDisplays:` (0x18ee471c4) only feed an `os_log` in both builds; `logicalScaleForDisplayScale:` returns the same value, `_defaultScale` is the 16.0 inline closest-PPI rule. Nothing to port (correction of the audit row).
* The real change is the restructure around `SBSceneHostingDisplayPreferences` (16.2 policy `displayPreferencesForDisplayController:` 0x1c77dd034 -> init 0x1c788f4f4: logicalScale (L, L) from the mode settings scale, contentsScale ivar, `keepOtherModes` NO, `CADisplayModeCriteria` from a fresh `FBSMutableDisplayConfigurationRequest`: resolution (0,0), refresh rate 0, `hdrMode` = `_FBSDisplayHDRModeToCADisplayHDRMode(0)` = `kCADisplayModeSDR`). 16.0 computes the same inputs in the policy (`_preferredSizeInPixels...` 0x1c633a7a8, `_preferredSizeInPoints...` 0x1c633a890 = pixels / contents scale, `_preferredContentsScale` 0x1c633a94c, `_preferredModeForDisplayForTargetCADisplay:` 0x1c633a954) and the controller (`_preferredLogicalScale` 0x1c5f48360, which already clamps per axis). The apply block of `_ensureCADisplayUpToDate` is identical in both builds (0x1c5f487e4 / 0x1c73bd2c0), so only its inputs differ. Three differences:
  1. mode criteria: 16.0 uses an empty `CADisplayModeCriteria` (QuartzCore hdr type 0, "no preference"), 16.2 SDR (hdr type 1) in `-[CADisplay preferredModeWithCriteria:]` (16.0 0x188446048 / 16.2 0x188572570, same code apart from one `create_mode` argument);
  2. the published configuration copies the config's `preferredMode` in 16.0 (policy transform 0x1c633981c) but the `currentMode` in 16.2 (controller transform 0x1c73bb2b8, `_copyWithOverrideSize:scale:` at 0x1c73bb560), with `otherModes` nil in both (the policy's `keepOtherModes` is NO);
  3. for a display of type 2 16.2 `_ensureCADisplayUpToDate` uses logical scale (1, 1) (0x1c73bcf28), 16.0 clamps in all cases.

### Implemented (X3Mode.x, `X3_Setup()` from Tweak.x)

* `modecriteria`: `-[SBSystemShellExtendedDisplayControllerPolicy _preferredModeForDisplayForTargetCADisplay:]` builds the 16.2 criteria (fresh request, `FBSDisplayHDRModeToCADisplayHDRMode` through dlsym, fallback strings) and asks the display. That one method feeds the pixel and point size (so the existing per-axis clamp of Tweak.x `scale` keeps working on the same mode), `preferredDisplayModeForDisplayController:` and `_ensureCADisplayUpToDate`. When the criteria find no mode the 16.0 answer is returned and the case is logged (this is the last line of that path, not a silent switch).
* `modebase`: after the 16.0 policy transform, when `[config currentMode]` differs from `[config preferredMode]`, `setCurrentMode:preferredMode:otherModes:` is redone on the builder with `[currentMode _copyWithOverrideSize:<_preferredSizeInPoints...> scale:<_preferredContentsScale>]` for both modes, `otherModes` nil.
* `modelogical`: `-[SBSceneHostingDisplayController _preferredLogicalScale]` answers (1, 1) when the `_caDisplay`'s `displayType` is 2.

Unchanged and already in place: the per-axis clamp of the published pixel size (Tweak.x, switch `scale`).

### Switches and logs

`modecriteria`, `modebase`, `modelogical` (kill files `Backport162.off.<switch>`, README table). Debug log lines: `[x3] monitor mode choice installed ...`, `[x3] criteria preferred mode <new> instead of <default>`, `[x3] criteria preferred mode: no mode for ...`, `[x3] published mode is a copy of the current mode ...`, `[x3] logical scale ... -> 1x1 for display type 2`.

### Not ported / unproven

* Not ported (no SpringBoard part, or nothing observable): `SBDisplayScaleMapping` new initializer and mode walk (log only), `SBSceneHostingDisplayPreferences` as a class (its three consumers are covered), `-[CADisplayMode _initWithMode:display:rates:]` and `CAWindowServerDisplay maxLayerBandwidth` (QuartzCore of the system, not in SpringBoard), `setCloningSupported:` (clone mirroring is the `clonemirror` family), the "disconnect signal already signalled" early outs (identical in both builds).
* Unproven (no device): every effect depends on the monitor. On a monitor that offers no HDR modes `modecriteria` returns the same mode as 16.0 (the debug line is then absent); on a monitor with HDR modes it may select another resolution / refresh rate entry than 16.0 did, which is exactly what 16.2 does. `modebase` only matters when the CADisplay's current mode differs from its preferred mode (after a mode change by `_ensureCADisplayUpToDate`). The exact C++ `ModeSet::preferred_mode_with_criteria` was not decoded: only that hdr type 0 and 1 are passed differently was verified, so which mode a given monitor yields is unknown without `[x3]` lines from a device.

## Display leftovers (0.7.9) — pointer

The remaining display-side gaps (focuslock by address, X7 UCS block and `_filterFocusedSceneIdentityToken:`, monitor mode leftovers, plumbing PARTIAL rows, remote alert Siri exception, clone mirroring diagnostics, education capability and fallback, lock/blank on the monitor, scene destroy guard) are in specs/DISPLAY-LEFTOVERS-0.7.9.md with addresses, switches, log lines, test recipes and the unproven list. Rows of this file that say "not ported" for those items are superseded by that document. Still not done: the `SBFluidSwitcherPortaledSceneLiveContentOverlay` creator (core agent), `shouldDismissInSwitcher` consumer (dead for 16.0 clients), the second signal test inside 16.2's block 2 of the presentation update (re-entrant disconnect only).

