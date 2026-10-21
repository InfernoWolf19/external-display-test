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
