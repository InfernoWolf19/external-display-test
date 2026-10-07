# Group 4b: external display disconnect, keyboard focus across displays, pointer lock

Build under test: 20A8372 (iPadOS 16.0). Reference: 20C65 (iPadOS 16.2). Addresses are `16.0 / 16.2` vm addresses
(dyld shared cache, unslid). All selectors below were read from the stub-resolved disassembly (`annot162.py` /
`annot3.py` equivalents), not guessed; strings and constants were decoded from the cache. Companion file:
`group4-disconnect-focus-pointer.hooks.m` (drafted hooks, every piece tagged PORTABLE / PARTIAL / NOT PORTABLE).
Earlier notes: `group4-external-display-notes.md` (section 3 there is superseded by this file).

Confidence words: HIGH = read directly from code or strings; MEDIUM = inferred from code plus log strings;
LOW = inference without a direct witness.

## 0. Summary

16.2 reworks how SpringBoard tracks "the display the user is working on" and how it tears a display down. Four
cooperating changes, all absent in 16.0:

1. A window scene can be flagged invalidating / invalidated (`SBWindowScene` gets `_isInvalidating`, `_isInvalidated`).
   Anything that picks "the active display scene" refuses a scene that is going away and falls back to the embedded
   display's scene.
2. `SBWorkspaceKeyboardFocusController` gets a counted assertion, `suppressKeyboardFocusEvaluationForReason:`,
   that freezes keyboard-focus policy re-evaluation while a scene tears down, then re-evaluates exactly once.
   Both `-[SBExternalDisplayWindowSceneDelegate sceneDidDisconnect:]` and `-[SBAbstractWindowSceneDelegate
   sceneDidDisconnect:]` hold it for the whole teardown. The kfc also now does real work in
   `windowSceneDidDisconnect:` (empty in 16.0).
3. A new object, `SBMultiDisplayUserInteractionCoordinator`, fed by a new `-[SpringBoard sendEvent:]` override,
   tracks the window scene of the last touch / pointer interaction. `SBWindowSceneManager.activeDisplayWindowScene`
   now follows that by default (setting `activeDisplayTrackingMethodology`, default 1 = "touch + pointer") instead of
   following keyboard focus (16.0 behaviour, methodology 0 = "keyboard"). It also records which scene a pointer
   touch-down started in, which two gesture managers use to reject cross-display pan gestures.
4. `SBLockedPointerManager` is no longer one global object on the main display. It is one instance per window
   scene (owned by the scene's `SBWindowSceneContext`), has an explicit `invalidate`, and acts on its own display.

Portability verdict (details and confidence per item in section 9):

| item | verdict |
|---|---|
| SBWindowScene invalidating/invalidated state, `SBWindowSceneManager` validation + embedded fallback | PORTABLE (HIGH) |
| `suppressKeyboardFocusEvaluationForReason:` API surface | PORTABLE as a `%new` method with an associated `BSCompoundAssertion` |
| Making the suppression actually freeze evaluation | PARTIAL: `_reevaluatePolicyAndUpdateRulesIfNeeded` is a direct (non-ObjC) method; needs an address-gated function hook |
| kfc `windowSceneDidDisconnect:` real implementation | PORTABLE (16.0 method is an empty ObjC method, hookable) |
| External delegate disconnect sequence (flags, suppression, coordinator, cover sheet observer) | PARTIAL (wrapper; cannot move the `super` call to the end) |
| Coordinator + touch/pointer active display | PARTIAL (new class + `sendEvent:` hook; pointer sniffer decode needs an on-device check) |
| Cross-display gesture rejection (`activeTouchDownOriginatedWindowScene`) | PARTIAL (two `gestureRecognizerShouldBegin:` hooks) |
| Per-display pointer-lock assertion (BKS display argument) | PARTIAL (one hook on `BKSMousePointerService`) |
| Per-scene `SBLockedPointerManager`, pointer-unlock action, suppress-preferred-status | NOT PORTABLE as hooks (re-implementation of a 14-method class and of the layout/transition plumbing) |
| Moving the external display's windows to the iPad on disconnect (`SBMainSwitcherControllerCoordinator windowSceneDidDisconnect:`) | NOT PORTABLE (belongs with the Stage Manager groups; needs the 16.2 model changes) |
| Per-display focus-lock reasons in `_keyboardFocusPolicyForCurrentUIStateWithAppFocusTarget:` / `_applyDeferringRulesForPolicy:` | NOT PORTABLE (two ~750 / ~1070 instruction direct methods) |

## 1. How 16.0 decides "which display is active" and who has keyboard focus (baseline)

* `-[SBWindowSceneManager activeDisplayWindowScene]` (0x1c6043bec), HIGH:

  ```objc
  - (SBWindowScene *)activeDisplayWindowScene {
      SBWorkspaceKeyboardFocusController *kfc = [[SBMainWorkspace sharedInstanceIfExists] keyboardFocusController];
      SBWindowScene *s = [kfc windowSceneWithFocus];
      if (!s) s = [self _embeddedDisplayWindowScene];
      return s;
  }
  ```
  So "active display" == "display of the keyboard-focused scene" == `kfc._windowSceneWithFocus`. That ivar is
  recomputed inside `_applyDeferringRulesForPolicy:` (16.0 0x1c6325d8c; it calls
  `_notifyObserversFocusedWindowSceneChangedFrom:to:` when the value changes) on every policy evaluation, from the
  policy's app focus target (taps, `userFocusRequestForScene:reason:completion:`) or, while SpringBoard holds a focus
  lock / focus-steal (`lockFocusToSpringBoardWindowScene:forReason:`, `requestFocusStealingForSpringBoardWindow:forReason:`),
  from `preferredSBFocusWindowScene`.
  A tap on SpringBoard UI that is not an app (wallpaper, dock, home screen of the external display) does not move
  keyboard focus, so it does not move the active display. Pointer hovering never moves it.
* `activeDisplayWindowScene` is a very widely used selector (about 90 call sites in 16.2): app launch target
  (`-[SBMainWorkspace _targetWindowSceneForApplication:preferringDisplay:requireForeground:options:]`), every
  hardware-keyboard shortcut handler in `SpringBoard` (`_handleOpenAppSwitcherShortcut:` ...), banners
  (`SBBannerManager`), Siri, home/lock/volume button actions, Control Center, App Library service,
  `SBTransientOverlayPresentationManager`, PIP. In 16.0 all of them follow keyboard focus.
* `-[SBWorkspaceKeyboardFocusController windowSceneDidDisconnect:]` (0x1c6323a98) is a single `ret`. The kfc only
  learns that a scene disappeared when its `SBSceneManagerObserver` callbacks
  (`sceneManager:willRemove/didRemoveExternalForegroundApplicationSceneHandle:`) fire for individual app scenes.
  `windowSceneDidConnect:` (0x1c6323a44) does `[[ws sceneManager] addObserver:self]`; nothing ever removes it.
* Pointer lock in 16.0: one `SBLockedPointerManager`, created in `-[SpringBoard _initializeDeferredItems]` with
  `-initWithSceneManager:[[SBSceneManagerCoordinator mainDisplaySceneManager]]` and kept in the `SpringBoard`
  ivar `_lockedPointerManager`. It observes the main display scene manager and the main display
  `_layoutStateTransitionCoordinator`, reads the main display `currentLayoutState`, and creates the lock as a
  BackBoard pointer-suppression assertion with `display:nil`. The only client is the main display scene manager's
  `_appClientSettingsDiffInspector` block (`clientWithSceneIdentifier:prefersPointerLockStatus:`). It is never
  invalidated.

## 2. External display scene disconnect

### 2.1 `-[SBExternalDisplayWindowSceneDelegate sceneDidDisconnect:]` (0x1c5fed4f8 / 0x1c746826c)

(a) 16.0 behaviour (HIGH). The super call runs first:

```objc
- (void)sceneDidDisconnect:(UIScene *)scene {
    [super sceneDidDisconnect:scene];                                   // SBAbstractWindowSceneDelegate, see 2.2
    SBWindowScene *ws = __BSSafeCast(scene, NSClassFromString(@"SBWindowScene"));
    if ([[ws screen] displayConfiguration])                             // gate
        [[SBMainSwitcherControllerCoordinator sharedInstance] windowSceneDidDisconnect:scene];
    [_showStatusBarAssertion invalidate];  _showStatusBarAssertion = nil;
    [[ws systemGestureManager] invalidate];
    [[SBAlertItemsController sharedInstance] windowSceneDidDisconnect:ws];
    [[SBAppInteractionEventSourceManager sharedInstance] windowSceneDidDisconnect:ws];
}
```

(b) 16.2 behaviour (HIGH). The super call moved to the end; the gate disappeared; five new steps:

```objc
- (void)sceneDidDisconnect:(UIScene *)scene {
    SBWindowScene *ws = __BSSafeCast(scene, NSClassFromString(@"SBWindowScene"));
    SBWorkspaceKeyboardFocusController *kfc = [[SBMainWorkspace sharedInstanceIfExists] keyboardFocusController];
    NSString *reason = [NSString stringWithFormat:@"%@ - %@",
                        NSStringFromClass([self class]), [[ws screen] displayIdentity]];
    id<BSInvalidatable> suppress = [kfc suppressKeyboardFocusEvaluationForReason:reason];   // NEW
    [ws setInvalidating:YES];                                                               // NEW
    [[SBMainSwitcherControllerCoordinator sharedInstance] windowSceneDidDisconnect:ws];     // gate removed
    [_showStatusBarAssertion invalidate];  _showStatusBarAssertion = nil;
    [[ws systemGestureManager] invalidate];
    [[SBAlertItemsController sharedInstance] windowSceneDidDisconnect:ws];
    [[SBAppInteractionEventSourceManager sharedInstance] windowSceneDidDisconnect:ws];
    [[SBApp multiDisplayUserInteractionCoordinator] windowSceneDidDisconnect:ws];           // NEW
    [_coverSheetController invalidate];  _coverSheetController = nil;                       // NEW
    [super sceneDidDisconnect:scene];                                                       // moved from first to near-last
    [suppress invalidate];                                                                  // NEW: lets kfc re-evaluate once
    [ws invalidate];                                                                        // NEW: _isInvalidated = YES
    [self setInvalidated:YES];                                                              // NEW (SBAbstractWindowSceneDelegate._invalidated)
}
```
(`SBApp` is the global `_SBApp` at 0x1dd7eeb0 / the SpringBoard application object.)

Constants: `invalidating` ivar offsets inside `SBWindowScene` are 0x1a0 / 0x1a1 (16.2 only). The reason string
for the assertion is `"<delegate class> - <FBSDisplayIdentity description>"`.

Side effects of the reordering (HIGH): in 16.2 `[SBWindowSceneManager _sceneDidDisconnect:]` (which removes the
scene from `connectedWindowScenes`; it is called from the super method) runs after the switcher, system
gesture manager, alert items and event-source teardown, and while the scene is already flagged invalidating.

(c) User-visible bug fixed.
* Focus stuck on a dead display (MEDIUM-HIGH). The strings `"[%@] focus scene <%p> on display %@ is in the process
  of invalidating, falling back to reporting the embedded scene as the active scene"` and `"... is invalidated!?!?!?!?"`
  (in `_validateSuggestedActiveWindowScene`) and the whole diagnostic method
  `-[SBWorkspaceKeyboardFocusController explainWhyYouAreFocusingAnInvalidatedScene]` show Apple hit the case "kfc
  still reports the disconnecting display as the focused / active scene". In 16.0 that state makes
  `activeDisplayWindowScene` return a dead scene, so keyboard shortcuts, banners, Siri, App Library, Control Center,
  Spotlight and app launches target a display that no longer exists (nothing appears), and hardware keyboard
  events can stay deferred to a scene that is gone, until some other focus change happens. The explain method names
  the two usual culprits: a SpringBoard focus-lock assertion (`lockFocusToSpringBoardWindowScene:forReason:`) or a
  focus-stealing SpringBoard window whose window scene is the dead one.
* Transient focus decisions during teardown (MEDIUM). Every scene removed during teardown triggers
  `_reevaluatePolicyAndUpdateRulesIfNeeded`; the policy is computed against a half-torn-down scene graph.
  Freezing evaluation until the end and re-evaluating once avoids that churn (and the associated deferring-rule
  updates against a nil `FBScene`).
* Switcher teardown skipped (MEDIUM, not verified at runtime). 16.0 only calls
  `SBMainSwitcherControllerCoordinator windowSceneDidDisconnect:` when `[[ws screen] displayConfiguration]` is non-nil.
  At disconnect time the screen may already have lost its configuration; in that case the external switcher
  controller, its content view controller, its per-scene observers and its gesture manager stay alive. 16.2 calls
  it unconditionally.
* Cover sheet observer leak (MEDIUM). `-[SBExternalDisplayCoverSheetController invalidate]` is new in 16.2; it
  removes the controller from `NSNotificationCenter` (in 16.0 that only happens in `dealloc`, and the delegate keeps
  the controller alive in `_coverSheetController` until the delegate itself dies). A stale controller keeps reacting
  to `_embeddedLockStateDidChange:` after the display is gone.

(d) Dependencies absent in 16.0: `-[SBWorkspaceKeyboardFocusController suppressKeyboardFocusEvaluationForReason:]`;
`-[SBWindowScene setInvalidating:]`, `-invalidate`, `-isInvalidating`, `-isInvalidated`;
`-[SBAbstractWindowSceneDelegate setInvalidated:]`/`isInvalidated` (ivar `_invalidated` at 0x40, which shifts every
`SBExternalDisplayWindowSceneDelegate` ivar by 8: `_coverSheetController` is 0x60 in 16.0, 0x68 in 16.2);
`-[SpringBoard multiDisplayUserInteractionCoordinator]` and the class `SBMultiDisplayUserInteractionCoordinator`;
`-[SBExternalDisplayCoverSheetController invalidate]`.

### 2.2 `-[SBAbstractWindowSceneDelegate sceneDidDisconnect:]` (0x1c600cab8 / 0x1c748772c)

Not in WORKLIST.md (the worklist body-diffed only some classes) but it is the `super` of 2.1 and changed.

(a) 16.0 (HIGH): `[_pointerAssertion invalidate]`, `[[SBApp windowSceneManager] _sceneDidDisconnect:scene]`, then, if the
cast to `SBWindowScene` is non-nil: `pictureInPictureManager windowSceneDidDisconnect:`, `assistantController
dismissAssistantViewIfNecessary`, `[[SBMainWorkspace transientOverlayPresentationManager] windowSceneDidDisconnect:]`,
`[kfc windowSceneDidDisconnect:]` (empty), `[[SBApp bannerManager] dismissAllBannersInWindowScene:ws animated:NO
reason:@"sceneDidDisconnect"]`, `[[NSNotificationCenter defaultCenter] removeObserver:self]`,
`[[SBApp systemUIScenesCoordinator] windowSceneDidDisconnect:]`, `[[SBIconController sharedInstanceIfExists]
windowSceneDidDisconnect:]`.

(b) 16.2 (HIGH): same list, but wrapped by the same suppression assertion (reason `"<class> - <displayIdentity>"`,
taken first, invalidated last), the nil guard removed, `removeObserver:` moved up, and two invalidations added:
`[[ws lockedPointerManager] invalidate]` and `[[ws medusaHostedKeyboardWindowController] invalidate]`.
Because the BSCompoundAssertion is counted, the nested hold taken here by the external delegate's `super` call
does not release evaluation; only the outermost `[suppress invalidate]` does.

(c) Bug: same as 2.1; additionally `SBLockedPointerManager` assertions (pointer suppression, hidden pointer) were
never released for a scene that went away because 16.0 has no per-scene manager.

(d) Dependencies: kfc suppression API; `SBWindowScene lockedPointerManager`, `medusaHostedKeyboardWindowController`
(`SBMedusaHostedKeyboardWindowController` is a 16.2-only class).

### 2.3 `_configureForConnectingWindowScene:windowSceneContext:` (connect path)

`-[SBExternalDisplayWindowSceneDelegate ...]` 0x1c5fed084 / 0x1c7467d5c; `-[SBEmbeddedDisplayWindowSceneDelegate ...]`
0x1c63a0e20 / 0x1c784b1b8; `-[SBAbstractWindowSceneDelegate ...]` 0x1c600c4e8 / 0x1c74870c8. Diff 16.0 -> 16.2 (HIGH):

* External and Embedded: `SBSystemPointerInteractionManager` is created with
  `[[SBSystemPointerInteractionManager alloc] initWithMultiDisplayUserInteractionCoordinator:[SBApp
  multiDisplayUserInteractionCoordinator]]` instead of `alloc/init`; `SBTransientUIInteractionManager
  initWithSystemGestureManager:` and `SBRecordingIndicatorManager initWithWindowScene:` are created and stored in the
  context; and, as the last step, `[[SBApp multiDisplayUserInteractionCoordinator] windowSceneDidConnect:ws]`.
  (The Embedded delegate also loses its `SBChamoisUISceneLifecycleIsEnabled` branches; that is a Stage Manager item.)
* Abstract: after `[kfc windowSceneDidConnect:ws]` it creates `[[SBLockedPointerManager alloc]
  initWithWindowScene:ws]` and stores it with `-[SBWindowSceneContext setLockedPointerManager:]` (new context ivar
  `_lockedPointerManager` at 0x50). It also replaces `isMainDisplayWindowScene` with a display-count based test and
  calls `_initialLayoutStateWithDisplayOrdinal:isDisplayExternal:` (layout work, not this group).
* So the connect-side callers of the coordinator are exactly the Embedded and External delegates (not Abstract).

## 3. `SBWindowScene` invalidation state

(a) 16.0: none. `SBWindowScene` (UIWindowScene subclass) has no ivars.

(b) 16.2 (HIGH). Two BOOL ivars `_isInvalidating` @0x1a0 and `_isInvalidated` @0x1a1:

```objc
- (BOOL)isInvalidating { return _isInvalidating && !_isInvalidated; }     // 0x1c77f77f0
- (BOOL)isInvalidated  { return _isInvalidated; }                         // 0x1c77f7820
- (void)invalidate     { _isInvalidated = YES; }                          // 0x1c77f86d4
- (void)setInvalidating:(BOOL)v {                                         // 0x1c77f768c
    if (_isInvalidating && !v) {
        NSString *m = [NSString stringWithFormat:@"Can't unvalidate an invalidating scene!"];
        os_log_error(... "SBWindowScene.m" ...);  __bs_set_crash_log_message(m.UTF8String);  __builtin_trap();
    }
    _isInvalidating = v;
}
```
Note the asymmetry: `isInvalidating` becomes NO once the scene is invalidated, and un-setting `invalidating` is a hard
crash in 16.2 (a port must NOT copy the trap).

Consumers (HIGH): only `-[SBWindowSceneManager _validateSuggestedActiveWindowScene:usingMethodology:]` and
`-[_SBActiveDisplayKeyboardFocusTracker activeWindowScene]` (see 5). Producer: only the External delegate's
`sceneDidDisconnect:`.

(c) Bug fixed: see 2.1 (active display must never resolve to a dying scene).

(d) Dependencies: none beyond the class itself. Port: associated objects (do not touch the ivar area of a UIKit
subclass), `%new` methods.

## 4. Keyboard focus controller: suppression, disconnect, re-evaluation

Class: `SBWorkspaceKeyboardFocusController` (singleton owned by `SBMainWorkspace`, ivar `_keyboardFocusController`
@0xa0). 16.2 ivar additions that matter here: `_windowSceneManager` @0x38, `_externalDisplaySettings` @0x40,
`_suppressKeyboardFocusEvaluationAssertion` @0xd0, `_windowSceneForSpringBoardFocusLockReasonMap` @0xb8 (all
offsets 16.2; 16.0 layout differs, never hard-code).

### 4.1 `-suppressKeyboardFocusEvaluationForReason:` (0x1c77c27fc, block 0x1c77c294c) - 16.2 only

(b) Reconstruction (HIGH):

```objc
- (id<BSInvalidatable>)suppressKeyboardFocusEvaluationForReason:(NSString *)reason {
    if (!_suppressKeyboardFocusEvaluationAssertion) {
        __weak typeof(self) weakSelf = self;
        _suppressKeyboardFocusEvaluationAssertion =
            [BSCompoundAssertion assertionWithIdentifier:@"SBWorkspaceKeyboardFocusSuppressEvaluation"
                                  stateDidChangeHandler:^(BSCompoundAssertion *a) {
                if (![a isActive]) {
                    os_log_debug(SBLogKeyboardFocus(), "finished suppressing keyboard focus evaluation, time to re-evaluate");
                    [weakSelf _reevaluatePolicyAndUpdateRulesIfNeeded];       // direct method 0x1c77c1810
                }
            }];
        [_suppressKeyboardFocusEvaluationAssertion setLog:SBLogKeyboardFocus()];
    }
    return [_suppressKeyboardFocusEvaluationAssertion acquireForReason:reason];   // autoreleased BSInvalidatable
}
```

(c) Use: `-[...] _reevaluatePolicyAndUpdateRulesIfNeeded` (0x1c77c1810, 22 -> 64 instructions):

```objc
- (void)_reevaluatePolicyAndUpdateRulesIfNeeded {            // direct method; main queue only
    if (!self) return;
    dispatch_assert_queue(dispatch_get_main_queue());
    if ([_suppressKeyboardFocusEvaluationAssertion isActive]) {                 // NEW
        os_log(SBLogKeyboardFocus(), "supressing evaluation due to reasons: %{public}@",
               [_suppressKeyboardFocusEvaluationAssertion reasons]);
        return;
    }
    id policy = [self _updateFocusPolicy];                                       // 0x1c77c43cc
    [self _applyDeferringRulesForPolicy:policy];                                 // 0x1c77c6994
    [self _updateAccessibilityDeferringRulesUnderstandingSpringBoardIsForeground:(_keyboardFocusTarget == nil)];
}
```
16.0 (0x1c6321b74) is the same minus the `isActive` early return. All 11 internal callers (lock/steal/redirect/
prevent/defer blocks, `_applyNewKeyboardFocusTarget:identityToken:fromSource:`,
`_reevaluatePolicyAndUpdateRulesFromKeyWindowNotification`, `updateKeyboardFocusDeferringRules`) go through it, and
its only 16.0 ObjC-visible entry is `-updateKeyboardFocusDeferringRules` (0x1c6321b70, a one-instruction `b`).
These `_...` methods are `objc_direct`: they are NOT in the class method list (the class dump omits them), so a
Logos `%hook` cannot reach them.

Who takes the assertion (HIGH): exactly two callers, both in `sceneDidDisconnect:` (2.1, 2.2).

(c) Bug: see 2.1.

(d) Dependencies: `BSCompoundAssertion` (exists in 16.0: the 16.0 kfc already builds `springBoardFocusLockAssertions`
with `assertionWithIdentifier:stateDidChangeHandler:` / `setLog:` / `acquireForReason:`), `SBLogKeyboardFocus`
(logging only).

### 4.2 `-windowSceneDidDisconnect:` (0x1c6323a98 / 0x1c77c3b14)

16.0: `ret`. 16.2 (HIGH):

```objc
- (void)windowSceneDidDisconnect:(SBWindowScene *)ws {
    os_log_debug(SBLogKeyboardFocus(), "windowSceneDidDisconnect: <%p> on display %{public}@ %{public}@ focused window scene",
                 ws, [ws _fbsDisplayIdentity], ([self windowSceneWithFocus] == ws) ? @"is" : @"is NOT");
    SBSceneManager *sm = [ws sceneManager];
    for (SBDeviceApplicationSceneHandle *h in [sm externalForegroundApplicationSceneHandles])
        [self _removeSceneFromRecentsAndUpdateKeyboardFocusTargetIfNeeded:[h scene]
                           reevaluatePolicyAndUpdateRulesIfNeeded:NO reason:@"windowSceneDidDisconnect"];
    [sm removeObserver:self];                                  // undoes windowSceneDidConnect:
    [self _reevaluatePolicyAndUpdateRulesIfNeeded];            // suppressed if the delegate still holds its assertion
    if ([self windowSceneWithFocus] == ws)
        [self explainWhyYouAreFocusingAnInvalidatedScene];     // diagnostic only (logs the lock / steal assertions' contexts)
}
```
`_removeSceneFromRecentsAndUpdateKeyboardFocusTargetIfNeeded:reason:` (0x1c632303c / 0x1c77c32a4) became a 4-instruction
wrapper that calls the new 3-arg variant (0x1c77c3d3c) with `reevaluate:YES`; the only functional difference is the
BOOL that gates the final `_reevaluatePolicyAndUpdateRulesIfNeeded`. `sceneManager:will/didRemoveExternal...:` only adapt to
the new signature.
(c) Bug: scenes of a vanished display (that never got their `didRemove` callback) stay in the recents cache and as
`_keyboardFocusTarget` / `_externalSceneWithFocus`; and the observer registered in `windowSceneDidConnect:` leaks.
MEDIUM-HIGH.
(d) Dependencies: only 16.0-existing selectors (`externalForegroundApplicationSceneHandles`, `scene`,
`removeObserver:`, `windowSceneWithFocus`) plus the direct `_removeSceneFromRecents...` (use the ObjC-visible
`removeKeyboardFocusFromScene:` instead in a port; it passes the reason "removeKeyboardFocusFromScene" where 16.2 passes
"windowSceneDidDisconnect", which only changes log text).

### 4.3 What else changed in the kfc (context; not ported)

* `-initWithWorkspace:` -> `-initWithWorkspace:windowSceneManager:` (designated: `_initWithWorkspace:sceneCoordinator:
  frontBoardSceneManager:windowSceneManager:installUIKitDependencies:initializeKeyboardArbiter:
  defaultSpringBoardLayoutSceneIdentityToken:`, 0x1c77c0e6c). It stores the manager, caches
  `[SBExternalDisplaySettingsDomain rootSettings]`, adds itself as observer of every connected window scene's scene
  manager, and, when `activeDisplayTrackingMethodology == 1`, registers as active-window-scene observer:
  `[[SBApp multiDisplayUserInteractionCoordinator] addActiveDisplayWindowSceneObserver:self]`.
* `-settings:changedValueForKey:` (0x1c77c5724, PTSettingsKeyObserver): when `activeDisplayTrackingMethodology`
  changes it adds/removes that observer registration and re-evaluates.
* `-multiDisplayUserInteractionCoordinator:updatedActiveWindowScene:` (0x1c77c56d8): re-evaluates the policy, but only
  if `_springBoardFocusLockAssertions` is active (i.e. SpringBoard currently holds a focus lock somewhere).
* Per-display focus locks. `lockFocusToSpringBoardWindowScene:forReason:` (0x1c6321c94 / 0x1c77c19f0, 101 -> 223
  insns) replaces the single `_springBoardFocusLockWindowScene` by a reason -> window-scene `NSMapTable`.
  `_keyboardFocusPolicyForCurrentUIStateWithAppFocusTarget:` (0x1c6324e5c / 0x1c77c58c8) now counts a lock reason only
  if its window scene is the display of the app focus target or the active (user-interaction) display
  (`activeDisplayWindowSceneFollowingUserInteraction`, call sites 0x1c77c5b38 and 0x1c77c5f5c);
  `_applyDeferringRulesForPolicy:` (0x1c6325d8c / 0x1c77c6994) picks `preferredSBFocusWindowScene` from the lock
  contexts the same way. Effect (MEDIUM): a Spotlight / Control Center / alert focus lock on display A no longer
  steals the hardware keyboard from an app on display B.
* `shouldKeyboardBeWindowSizedForHostWithIdentity:`, `externalSceneIdentities`, `_filterFocusedSceneIdentityToken:`
  additions and an overlay-UI special case in `removeKeyboardFocusFromScene:` relate to the input-system-UI /
  Medusa hosted keyboard path (other group); not analysed here.

## 5. Active display tracking: `SBWindowSceneManager`, tracker, coordinator

### 5.1 Who creates what (HIGH)

* `-[SpringBoard applicationDidFinishLaunching:]` (0x1c5ed74d8 / 0x1c734ba64), after `SBSystemUIScenesCoordinator`:

  ```objc
  _multiDisplayUserInteractionCoordinator = [[SBMultiDisplayUserInteractionCoordinator alloc] init];   // SpringBoard ivar @0x650 (16.2)
  _windowSceneManager = [[SBWindowSceneManager alloc] initWithUserInteractionCoordinator:_multiDisplayUserInteractionCoordinator];
  [_multiDisplayUserInteractionCoordinator setDelegate:_windowSceneManager];     // delegate protocol: windowSceneForDisplayIdentity:
  ```
  16.0 only did `_windowSceneManager = [SBWindowSceneManager new]` there.
* `-[SBWindowSceneManager initWithUserInteractionCoordinator:]` (0x1c74bf0f4): `_mutableConnectedWindowScenes =
  [NSMutableSet new]`, `_keyboardFocusTracker = [_SBActiveDisplayKeyboardFocusTracker new]` (ivar @0x10),
  `_userInteractionCoordinator = coordinator` (@0x18). The 16.0 `-init` is gone.
* `_SBActiveDisplayKeyboardFocusTracker` has no ivars and one method (0x1c74bfb9c):

  ```objc
  - (SBWindowScene *)activeWindowScene {            // protocol SBActiveWindowSceneTracking
      SBWorkspaceKeyboardFocusController *kfc = [[SBMainWorkspace sharedInstanceIfExists] keyboardFocusController];
      SBWindowScene *s = [kfc windowSceneWithFocus];
      if ([s isInvalidated]) [kfc explainWhyYouAreFocusingAnInvalidatedScene];
      return s;
  }
  ```
  i.e. it is exactly the 16.0 notion of "active scene" wrapped in an object so that it can sit behind the same
  protocol as the coordinator.

### 5.2 Who calls the coordinator

| call | callers (16.2) |
|---|---|
| `windowSceneDidConnect:` | `-[SBEmbeddedDisplayWindowSceneDelegate _configureForConnectingWindowScene:windowSceneContext:]`, `-[SBExternalDisplayWindowSceneDelegate _configureForConnectingWindowScene:windowSceneContext:]` (last statement of both) |
| `windowSceneDidDisconnect:` | `-[SBExternalDisplayWindowSceneDelegate sceneDidDisconnect:]` only |
| `handleSendEvent:` | new `-[SpringBoard sendEvent:]` override (0x1c7356bb8): `[_multiDisplayUserInteractionCoordinator handleSendEvent:event]; [super sendEvent:event];` (16.0 has no override) |
| `activeWindowScene` | `-[SBWindowSceneManager activeDisplayWindowSceneFollowingUserInteraction]` |
| `activeTouchDownOriginatedWindowScene` | `-[SBControlCenterController gestureRecognizerShouldBegin:]`, `-[SBFluidSwitcherGestureManager gestureRecognizerShouldBegin:]` |
| `addActiveDisplayWindowSceneObserver:` | kfc (when methodology == 1) |
| `addPointerInteractionObserver:` | `-[SBSystemPointerInteractionManager initWithMultiDisplayUserInteractionCoordinator:]` (it forwards to its own `SBSystemPointerInteractionObserver`s, e.g. `-[SBFluidSwitcherViewController pointerDidMoveToFromWindowScene:toWindowScene:]` at 0x1c745f938, which consults `externalDisplayService preferredArrangementOfDisplay:relativeTo:`) |

### 5.3 The coordinator (class `SBMultiDisplayUserInteractionCoordinator`, size 0x40; all HIGH unless noted)

Conforms to `_SBPointerTouchDownEventSnifferDelegate`, `_SBTouchInteractionEventSnifferDelegate`,
`_SBPointerInteractionEventSnifferDelegate`, `SBActiveWindowSceneTracking`, `SBWindowSceneAttachmentObserving`.
Ivars: `_activeDisplayWindowScene` @0x8 (weak), `_activePointerWindowScene` @0x10 (weak), `_delegate` @0x18 (weak),
`_activeTouchDownOriginatedWindowScene` @0x20 (weak), `_sceneToEventSniffers` @0x28 (`weakToStrongObjectsMapTable`),
`_activeWindowSceneObservers` @0x30 (`weakObjectsHashTable`, created lazily), `_pointerInteractionObservers` @0x38.

```objc
- (void)windowSceneDidConnect:(SBWindowScene *)ws {            // 0x1c795e314
    id td = [_SBPointerTouchDownEventSniffer new];      td.delegate = self; td.windowScene = ws;
    id ti = [_SBTouchInteractionEventSniffer new];      ti.delegate = self; ti.windowScene = ws;
    id pi = [_SBPointerInteractionEventSniffer new];    pi.delegate = self; pi.windowScene = ws;
    [_sceneToEventSniffers setObject:@[td, ti, pi] forKey:ws];
}
- (void)windowSceneDidDisconnect:(SBWindowScene *)ws {          // 0x1c795e43c
    [_sceneToEventSniffers removeObjectForKey:ws];
    if (_activeTouchDownOriginatedWindowScene == ws) {
        os_log_debug(SBLogPointer(), "Clearing pointer touch down window scene: %{public}@ - scene disconnected", [ws _sceneIdentifier]);
        _activeTouchDownOriginatedWindowScene = nil;
    }
    if (_activeDisplayWindowScene == ws) _activeDisplayWindowScene = nil;
    if (_activePointerWindowScene == ws) _activePointerWindowScene = nil;
}
- (void)handleSendEvent:(UIEvent *)event {                      // 0x1c795dd70
    SBWindowScene *ws = [self _windowSceneForEvent:event];
    if (!ws) return;
    for (id sniffer in [_sceneToEventSniffers objectForKey:ws]) [sniffer handleEvent:event];   // order: touchDown, touch, pointer
}
- (SBWindowScene *)_windowSceneForEvent:(UIEvent *)event {      // 0x1c795df4c
    BKSHIDEventBaseAttributes *attrs = BKSHIDEventGetBaseAttributes([event _hidEvent]);
    unsigned ctx = [attrs contextID];
    UIWindow *w = ctx ? [UIWindow _windowWithContextId:ctx] : nil;
    FBSDisplayIdentity *ident = [w _fbsDisplayIdentity];
    return ident ? [_delegate windowSceneForDisplayIdentity:ident] : nil;
}
- (void)_handleActiveDisplayQualifyingEventInWindowScene:(SBWindowScene *)ws source:(NSString *)src {   // 0x1c795e014
    SBWindowScene *old = _activeDisplayWindowScene;
    if (!ws) return;
    _activeDisplayWindowScene = ws;
    if (old == ws) return;
    os_log_debug(SBLogActiveDisplay(), "[%{public}@] updating active display from: %{public}@ to %{public}@ source: %{public}@",
                 @"touch + pointer", [old _sceneIdentifier], [ws _sceneIdentifier], src);
    for (id o in _activeWindowSceneObservers)
        [o multiDisplayUserInteractionCoordinator:self updatedActiveWindowScene:ws];
}
```
Delegate callbacks, with the three sniffers' qualifying tests decoded from `handleEvent:` (0x1c795eb54, 0x1c795ed7c,
0x1c795ef94). UITouchPhase: Began 0, Stationary 2, Ended 3, Cancelled 4. UITouchType: Direct 0, Indirect 1,
Pencil 2, IndirectPointer 3:

* `_SBPointerTouchDownEventSniffer`: only for `[event type] == 0` (touches); takes the first touch with
  `_isPointerTouch`; phase 0 -> `eventSnifferHandledPointerTouchDown:`, phase 3 -> `eventSnifferHandledPointerTouchUp:`.
  Coordinator: TouchDown sets `_activeTouchDownOriginatedWindowScene = sniffer.windowScene` (logs
  "Setting pointer touch down window scene: %@", or "Pointer touch down window scene: %@ but we're already tracking
  it down in scene" if one was already set; it overwrites either way). TouchUp logs "Clearing pointer touch down
  window scene: %@ - touch up" and nils it. Cancelled (4) is not handled (the field can stay set; it is cleared
  by the next touch-up or by scene disconnect).
* `_SBTouchInteractionEventSniffer`: first non-pointer touch with `type != Indirect(1)`, `type != IndirectPointer(3)`,
  `phase != Cancelled`, `phase != Stationary` -> `eventSnifferHandledTouchInteractionQualifyingEvent:` ->
  `_handleActiveDisplayQualifyingEventInWindowScene:sniffer.windowScene source:@"touch"`.
* `_SBPointerInteractionEventSniffer`: first touch with `_isPointerTouch`, `phase != Cancelled/Stationary`,
  location changed (`previousLocationInView:` != `locationInView:` against `touch.view`), and `[touch type] == 0`
  (as decoded; see open question 3) -> `eventSnifferHandledPointerInteractionQualifyingEvent:`. Coordinator: sets
  `_activePointerWindowScene` (weak) and, if it changed, logs `"[%@] updating active pointer display from: %@ to %@"`
  and calls `pointerDidMoveToFromWindowScene:toWindowScene:` on a copy of `_pointerInteractionObservers`; in all
  cases it then calls `_handleActiveDisplayQualifyingEventInWindowScene:... source:@"pointer"`.

### 5.4 `SBWindowSceneManager` (16.2)

```objc
- (SBWindowScene *)activeDisplayWindowScene {                    // 0x1c74bf1c4
    switch ([[SBExternalDisplaySettingsDomain rootSettings] activeDisplayTrackingMethodology]) {
        case 0:  return [self activeDisplayWindowSceneFollowingKeyboard];
        case 1:  return [self activeDisplayWindowSceneFollowingUserInteraction];
        default: return nil;     // undefined result register; treat as nil
    }
}
- (SBWindowScene *)activeDisplayWindowSceneFollowingKeyboard {   // 0x1c74bf244
    return [self _validateSuggestedActiveWindowScene:[_keyboardFocusTracker activeWindowScene] usingMethodology:0];
}
- (SBWindowScene *)activeDisplayWindowSceneFollowingUserInteraction {   // 0x1c74bf2a4
    return [self _validateSuggestedActiveWindowScene:[_userInteractionCoordinator activeWindowScene] usingMethodology:1];
}
- (SBWindowScene *)_validateSuggestedActiveWindowScene:(SBWindowScene *)s usingMethodology:(long long)m {   // 0x1c74bf960
    if ([s isInvalidating]) {
        os_log_debug(SBLogActiveDisplay(), "[%{public}@] focus scene <%p> on display %{public}@ is in the process of invalidating, "
                     "falling back to reporting the embedded scene as the active scene",
                     _SBStringForActiveDisplayTrackingMethodology(m), s, [s _fbsDisplayIdentity]);
        return [self _embeddedDisplayWindowScene];
    }
    if ([s isInvalidated]) {
        os_log_debug(SBLogKeyboardFocus(), "[%{public}@] focus scene <%p> on display %{public}@ is invalidated!?!?!?!?, "
                     "falling back to reporting the embedded scene as the active scene", ...);
        return [self _embeddedDisplayWindowScene];
    }
    return s ?: [self _embeddedDisplayWindowScene];
}
```
`_SBStringForActiveDisplayTrackingMethodology` (0x1c74241b8): 0 -> "keyboard", 1 -> "touch + pointer".
`SBExternalDisplaySettings.activeDisplayTrackingMethodology` is a PTSettings key ("Active Display Tracking" in the
internal settings UI, `setDefaultValues` sets it to 1 at 0x1c7423688); on a customer device nothing but
`setDefaultValues` writes it, so the effective value is 1 (HIGH for the code, MEDIUM that no persisted override
exists).

(c) Bugs fixed / behaviour changed:
* Keyboard-tracking mode (methodology 0) gains the invalidation fallback (same bug as 2.1).
* Default mode 1 decouples the active display from keyboard focus (HIGH for mechanism, MEDIUM for user impact).
  After 16.2, touching or moving the pointer onto the external display makes it the display that receives
  keyboard shortcuts, new windows, banners, Siri, Control Center and App Library actions, even if keyboard focus
  is still in an app on the iPad (and conversely focus-follows-nothing on the home screen of a display). The log
  source strings are `"touch"` and `"pointer"`.
* `activeTouchDownOriginatedWindowScene` filters gestures (see 8).

(d) Dependencies: everything in 5.1 - 5.3.

## 6. Pointer lock: `SBLockedPointerManager` (14 changed methods)

Lifetime: one per window scene, created in `SBAbstractWindowSceneDelegate _configureForConnectingWindowScene:...`
(`[[SBLockedPointerManager alloc] initWithWindowScene:ws]`), held in `SBWindowSceneContext._lockedPointerManager`,
reached through `-[SBWindowScene lockedPointerManager]` (0x1c77f804c), invalidated from
`SBAbstractWindowSceneDelegate sceneDidDisconnect:`. It now conforms to `BSInvalidatable` and `SBSceneManagerObserver`
(was `SBMainDisplaySceneManagerObserver`). Ivars added: `_queue_sceneIdentifiersThatSuppressPreferredLockStatus`
(NSMutableSet @0x30), `_windowScene` (weak @0x48), `_queue_isInvalidated` (@0x50).

Per method (16.0 -> 16.2), HIGH:

* `initWithSceneManager:` (0x1c62276b0) -> `initWithWindowScene:` (0x1c76b8c68): same setup (PSPointerClientController,
  serial queue `com.apple.SpringBoardFramework.SBLockedPointerManager.stateSerialQueue`, two mutable collections), then
  `[[ws sceneManager] addObserver:self]`, `[[ws layoutStateTransitionCoordinator] addObserver:self]`, weak `_windowScene`.
* `invalidate` (new, 0x1c76b9298): removes itself from the scene manager and layout transition coordinator, then on the
  serial queue (sync): invalidates and nils `_queue_backboardLockedPointerAssertion` and `_queue_pointerHiddenAssertion`,
  sets `_queue_isInvalidated = YES`.
* Every entry point is guarded by a snapshot of `_queue_isInvalidated` taken with `dispatch_sync(_stateSerialQueue)`:
  `layoutStateTransitionCoordinator:transitionDidBegin/EndWithTransitionContext:` (0x1c76b93c4 / 0x1c76b9528, 10 -> 58
  insns, log "Ignoring layout state transition didBegin because I'm invalidated"),
  `sceneManager:didAdd/didRemoveExternalForegroundApplicationSceneHandle:` (0x1c76b968c / 0x1c76b9794, 3 -> 37 insns;
  the 3-instruction 16.0 bodies were just `[handle addObserver:self]` / `removeObserver:`),
  `clientWithSceneIdentifier:prefersPointerLockStatus:` (0x1c76b8d74 + block 0x1c76b8f24, log "Ignoring request from %@
  to set pointerLockStatus %@ because I'm invalidated"), `sceneHandle:didUpdateSettingsWithDiff:previousSettings:`
  (0x1c76b989c, weak-self blocks), `_queue_updateLockForLayoutState:` (0x1c76ba124).
* `_updateLockForLayoutState:` (0x1c6227ed4; nil state -> `[[SBSceneManagerCoordinator mainDisplaySceneManager] currentLayoutState]`)
  -> `_notInvalidated_updateLockForLayoutState:` (0x1c76ba034; nil state -> `[[ws layoutStateProvider] layoutState]`),
  both `dispatch_async` to the queue and call `_queue_updateLockForLayoutState:`.
* `_queue_updateLockForLayoutState:` (0x1c76ba124): early return when invalidated (log "Ignoring request to update
  pointer lock state for layout state: %@ because I'm invalidated"); otherwise:

  ```objc
  h = [self _possibleSceneHandleForLockingPointerFromLayoutState:state]; sid = h.sceneIdentifier;
  current = _queue_sceneIdentifierThatHasLockedPointer;
  prefers = [self _queue_prefersLockForSceneIdentifier:sid]
         && ![_queue_sceneIdentifiersThatSuppressPreferredLockStatus containsObject:sid]      // NEW
         && [self _shouldAllowPointerLockedForScene:h];
  if (prefers && !current)  [self _queue_lockPointerForSceneIdentifier:sid];
  else if (!prefers && current) [self _queue_unlockPointer];
  ```
* `clientWithSceneIdentifier:suppressPreferredLockStatus:` (new, 0x1c76b8fc4): invalidated guard; adds/removes the id in the
  suppression set (block 0x1c76b91f0), tells the scene's `SBFluidSwitcherViewController`
  `clientWithSceneIdentifier:suppressPreferredPointerLockStatusUpdated:` (also new), then
  `_notInvalidated_updateLockForLayoutState:nil`. Callers: `-[SBSceneManager _handleAction:forScene:]` when the action is a
  `_UIPointerUnlockAction` (UIActionType 0x32, present in UIKit 16.0 but not handled by 16.0 SpringBoard) with
  `suppress:YES`; `-[SBFluidSwitcherViewController didSelectContainer:modifierFlags:]` with `suppress:NO`.
  Interpretation (MEDIUM): when the app/user asks to release the locked pointer (UIKit
  `-[UIWindowScene _unlockPointerLockState:]`), SpringBoard stops honouring that scene's preference until the user
  selects that window again in the switcher.
* `sceneHandle:didDestroyScene:` (new, 0x1c76b9b80): when not invalidated, drops the scene's entries from the preferred
  status dictionary and the suppression set, then re-evaluates.
* `_queue_lockPointerForSceneIdentifier:` (0x1c6228214 / 0x1c76ba3dc): same `pointerSuppressionAssertionOnDisplay:forReason:
  withOptionsMask:2` call, but the display argument changed from `nil` to
  `[[[ws _fbsDisplayConfiguration] hardwareIdentifier]` (the window scene's own display), reason `"Scene %@ requested
  locked pointer"` unchanged, plus a "Locking ..." log line. The `persistentlyHidePointerAssertionForReason:` call is
  unchanged. Assertion ivar offsets moved by 8 (suppression set inserted).
* `_queue_unlockPointer` (0x1c6228318 / 0x1c76ba590): adds an "Unlocking ..." log line; same releases.
* `_shouldAllowPointerLockedForScene:` (0x1c6227d44 / 0x1c76b9e5c): the Control Center test changed from "Control Center is
  presented anywhere blocks the lock" to "Control Center blocks the lock only if its window
  (`[[SBControlCenterController sharedInstance] _controlCenterWindow]`) belongs to this manager's window scene".
  Cover sheet presented, scene not effectively foreground, and `settings.isUISubclass && (deactivationReasons & ~0x100) != 0`
  remain blocking, as in 16.0.
* `.cxx_destruct`: releases the new ivars.

(c) User-visible bugs fixed (MEDIUM): with an external display, pointer lock requested by an app on the iPad hid the
cursor everywhere (`display:nil`), an app on the external display could not lock the pointer at all (no manager on
that scene manager), a Control Center on one display blocked locking on another, and a lock/assertion owned by a
display that was unplugged could never be torn down (no `invalidate`, observers never removed). Plus the new "unlock
until reselected" behaviour for `_UIPointerUnlockAction` (feature, not a bug fix).

(d) Dependencies absent in 16.0: `initWithWindowScene:`, `invalidate`, `BSInvalidatable`, `_notInvalidated_updateLockForLayoutState:`,
`clientWithSceneIdentifier:suppressPreferredLockStatus:`, `sceneHandle:didDestroyScene:`, `SBWindowScene.lockedPointerManager`,
`SBWindowSceneContext.lockedPointerManager`, `SBFluidSwitcherViewController clientWithSceneIdentifier:
suppressPreferredPointerLockStatusUpdated:`, `SBSceneManager` handling of `_UIPointerUnlockAction`,
`SBSystemShellExternalDisplaySceneManager`'s diff-inspector call into `[windowScene lockedPointerManager]`
(0x1c78590dc), per-scene `layoutStateTransitionCoordinator` / `layoutStateProvider` (the 16.0 manager hard-wires the
main display's).

## 7. Pointer routing details

* `SBSystemPointerInteractionManager` (one per window scene) is now `initWithMultiDisplayUserInteractionCoordinator:`
  (0x1c73e8600; asserts a non-nil coordinator, builds a `weakToWeakObjectsMapTable`, registers itself with
  `addPointerInteractionObserver:`), has `activePointerWindowScene` (forwarded from the coordinator),
  `addObserver:/removeObserver:`, and `pointerDidMoveToFromWindowScene:toWindowScene:` which re-broadcasts to its own
  observers. `pointerInteraction:window:regionForRequest:defaultRegion:` (0x1c5f71c98 / 0x1c73e8a00) now asks a
  registered view's delegate `shouldBeginPointerInteractionRequest:atLocation:forView:` instead of
  `shouldBeginPointerInteractionAtLocation:forView:` (a delegate API change that every registering view has to
  adopt; not portable alone).
* Cross-display gesture rejection (HIGH): `-[SBControlCenterController gestureRecognizerShouldBegin:]`
  (0x1c5e8d6ec / 0x1c7300268) and `-[SBFluidSwitcherGestureManager gestureRecognizerShouldBegin:]` (0x1c6443b1c /
  0x1c78f61dc) now read `[[SBApp multiDisplayUserInteractionCoordinator] activeTouchDownOriginatedWindowScene]`; for a
  `UIPanGestureRecognizer` with a non-nil touch-down scene that is not this controller's window scene (CC: `_window.windowScene`;
  switcher: `_switcherController.windowScene`) the gesture fails (CC logs "Not ... " reason `NotForCurrentDisplay`).
  Bug fixed (MEDIUM-HIGH): a pointer drag that starts on one display and crosses to the other no longer starts the
  other display's Control Center pull-down or switcher edge gestures.

## 8. Moving the external display's windows to the iPad on disconnect (information; not ported here)

`-[SBMainSwitcherControllerCoordinator windowSceneDidDisconnect:]` (0x1c62359ec / 0x1c76c85e0, 106 -> 275 insns), HIGH:
for an external window scene whose display has `sb_displayWindowingMode == 1`, before the old teardown it walks
`[self appLayoutsForSwitcherController:externalSwitcher]` -> `allItems` -> `_deviceApplicationSceneHandleForDisplayItem:`,
and for each existing scene does `[[embeddedWindowScene sceneManager] takeScene:scene fromSceneManager:[ws sceneManager]]`
(`-[SBSceneManager takeScene:fromSceneManager:]`, 0x1c5f72cf4 / 0x1c73e9a3c, 33 -> 109 insns, now also fires observer
callouts and notes the replaced handle), then requests a main-workspace transition
(`[[SBMainWorkspace mainWorkspace] requestTransitionWithOptions:0 builder:validator:]`) whose builder copies the
current layout state's `windowPickerRole` and `unlockedEnvironmentMode` (`== 2` -> requested mode 2) into the request
context via `modifyApplicationContext:`. The old teardown follows. Visible effect (HIGH): unplugging an external display
running Stage Manager moves its apps to the iPad screen instead of closing/hiding them. Depends on the Stage Manager
model changes of the other groups; flagged NOT PORTABLE here.

## 9. Portability matrix, confidence, and dependency lists

(For each item: dependency list = classes/methods that do not exist in 16.0.)

| item | what a port needs | verdict | confidence |
|---|---|---|---|
| SBWindowScene invalidating state | `%new` methods + associated objects on `SBWindowScene` | PORTABLE | HIGH |
| `SBAbstractWindowSceneDelegate isInvalidated` | `%new` + associated object | PORTABLE (informational only) | HIGH |
| Active-scene validation + embedded fallback | hook `activeDisplayWindowScene`; read flags above | PORTABLE | HIGH |
| `suppressKeyboardFocusEvaluationForReason:` | `%new` on kfc; `BSCompoundAssertion` (exists) | PORTABLE (API) | HIGH |
| suppression takes effect | hook direct method `_reevaluatePolicyAndUpdateRulesIfNeeded` (0x1c6321b74) via `MSHookFunction`, gated on build + prologue bytes | PARTIAL | MEDIUM |
| kfc `windowSceneDidDisconnect:` | hook the empty 16.0 ObjC method; use `removeKeyboardFocusFromScene:` + `updateKeyboardFocusDeferringRules` | PORTABLE | MEDIUM-HIGH |
| External `sceneDidDisconnect:` wrapper | pre: assertion + `invalidating` + coordinator; post: release, `invalidate`, cover sheet observer removal, optional switcher call when the 16.0 gate skipped it | PARTIAL (cannot move `super` to the end) | MEDIUM |
| Coordinator, sniffers, `sendEvent:` | new class (`BP`-prefixed, not the 16.2 name, to avoid a clash if the tweak is ever loaded on 16.2) + hooks on `SpringBoard sendEvent:`, both delegates' `_configureForConnectingWindowScene:` | PARTIAL | MEDIUM (pointer sniffer type test needs a device check) |
| Methodology 1 for `activeDisplayWindowScene` | uses the coordinator; falls back to keyboard-following while the coordinator has seen nothing | PARTIAL, behaviour-changing | MEDIUM |
| Gesture rejection | two hooks | PARTIAL | MEDIUM-HIGH |
| Per-display BKS pointer-suppression display | hook `BKSMousePointerService pointerSuppressionAssertionOnDisplay:forReason:withOptionsMask:` | PARTIAL | MEDIUM |
| Per-scene lock manager, `_UIPointerUnlockAction`, suppress-preferred-status | re-implementation of the class, per-scene layout/transition plumbing, new `SBSceneManager` action handling | NOT PORTABLE | - |
| Per-display focus-lock reasons | rewrite of two direct methods | NOT PORTABLE | - |
| Window migration on disconnect | Stage Manager model | NOT PORTABLE here | - |
| `SBSystemPointerInteractionManager` coordinator init + new delegate selector | all registering views change | NOT PORTABLE | - |

Consolidated 16.2-only dependency list: classes `SBMultiDisplayUserInteractionCoordinator`,
`_SBActiveDisplayKeyboardFocusTracker`, `_SBPointerTouchDownEventSniffer`, `_SBTouchInteractionEventSniffer`,
`_SBPointerInteractionEventSniffer`, `SBMedusaHostedKeyboardWindowController`; protocols `SBActiveWindowSceneTracking`,
`SBWindowSceneAttachmentObserving`, `SBMultiDisplayPointerInteractionObserver`,
`SBMultiDisplayUserInteractionCoordinatorDelegate`, `SBMultiDisplayUserInteractionCoordinatorActiveWindowSceneObserver`,
`_SBEventSniffing` (+ three delegate protocols); selectors on existing classes:
`SBWorkspaceKeyboardFocusController {suppressKeyboardFocusEvaluationForReason:, explainWhyYouAreFocusingAnInvalidatedScene,
initWithWorkspace:windowSceneManager:, multiDisplayUserInteractionCoordinator:updatedActiveWindowScene:, externalSceneIdentities}`,
`SBWindowScene {invalidate, isInvalidated, isInvalidating, setInvalidating:, lockedPointerManager,
medusaHostedKeyboardWindowController}`, `SBAbstractWindowSceneDelegate {isInvalidated, setInvalidated:}`,
`SBWindowSceneManager {initWithUserInteractionCoordinator:, keyboardFocusTracker, userInteractionCoordinator,
activeDisplayWindowSceneFollowingKeyboard, activeDisplayWindowSceneFollowingUserInteraction,
_validateSuggestedActiveWindowScene:usingMethodology:}`, `SpringBoard {multiDisplayUserInteractionCoordinator,
sendEvent:}`, `SBExternalDisplaySettings {activeDisplayTrackingMethodology}`,
`SBExternalDisplayCoverSheetController {invalidate}`, `SBLockedPointerManager {initWithWindowScene:, invalidate,
_notInvalidated_updateLockForLayoutState:, clientWithSceneIdentifier:suppressPreferredLockStatus:,
sceneHandle:didDestroyScene:}`, `SBFluidSwitcherViewController {clientWithSceneIdentifier:suppressPreferredPointerLockStatusUpdated:}`,
`SBSystemPointerInteractionManager {initWithMultiDisplayUserInteractionCoordinator:, activePointerWindowScene}`,
function `_SBStringForActiveDisplayTrackingMethodology`, os_log accessors `SBLogActiveDisplay`, `SBLogPointer`.
Things the 16.0 binary already has and a port may rely on (verified): `BKSHIDEventGetBaseAttributes` (imported),
`+[UIWindow _windowWithContextId:]`, `-[UITouch _isPointerTouch]`, `-[UIEvent _hidEvent]`, `-[UIWindow _fbsDisplayIdentity]`,
`-[UIWindowScene _fbsDisplayIdentity/_fbsDisplayConfiguration]`, `-[SBWindowSceneManager windowSceneForDisplayIdentity:/
embeddedDisplayWindowScene/_embeddedDisplayWindowScene]`, `-[SBSceneManager externalForegroundApplicationSceneHandles]`,
`-[SBControlCenterController _controlCenterWindow]`, `-[SBSceneManager takeScene:fromSceneManager:]`, `sb_displayWindowingMode`,
`BSCompoundAssertion {assertionWithIdentifier:stateDidChangeHandler:, setLog:, acquireForReason:, isActive, reasons}`.

## 10. Open questions

1. `[[ws screen] displayConfiguration]` at disconnect time: nil or not? Decides whether the 16.0 gate really skipped the
   switcher teardown (the hooks log it so it can be checked on device).
2. Is hooking `_reevaluatePolicyAndUpdateRulesIfNeeded` by address acceptable on the target jailbreak (arm64e, function
   starts with `cbz x0, ...`, ElleKit/Substrate relocation)? The hooks verify the first 7 instruction words before patching.
3. `_SBPointerInteractionEventSniffer` requires `[touch type] == 0` for a `_isPointerTouch` touch. Decoded exactly from the
   code (the branch is `cbz x0` on the result of `type`), but intuitively pointer touches are `IndirectPointer(3)`. If the
   port never sets `activePointerWindowScene`, this test is the first thing to relax; touch-driven tracking does not
   depend on it.
4. What produces `_UIPointerUnlockAction` and whether 16.0 UIKit sends it (class and `_unlockPointerLockState:` exist in
   both); only needed for the NOT PORTABLE unlock-until-reselected feature.
5. Nothing else in 16.0 reads `activeDisplayTrackingMethodology`; confirm no tweak/pref path sets it to 0 (if so the
   16.2 behaviour on that device is keyboard-following).
6. The 16.2 kfc per-display lock reasons (4.3) interact with methodology 1. Porting only the coordinator changes
   `activeDisplayWindowScene` consumers but not the keyboard deferring rules; whether that mix is acceptable for the
   hardware keyboard on the external display needs on-device observation.
7. `SBWindowSceneManager activeDisplayWindowScene` for an out-of-range methodology returns an uninitialised register in
   16.2; irrelevant in practice.

## 11. Hooks file map and deliberate deviations (`group4-disconnect-focus-pointer.hooks.m`)

Feature switches proposed (add to the Tweak.x enum / name table): `disconnect`, `discswitch` (opt-in file
`Backport162.on.discswitch`), `activedisplay`, `gesturegate`, `lockedptr`.

| hooks.m piece | tag | 16.2 source it mirrors |
|---|---|---|
| `SBWindowScene` `%new isInvalidating/isInvalidated/setInvalidating:` (associated objects) | PORTABLE | 3 (no `invalidate` method is added; the flag is set by the disconnect wrapper) |
| `SBAbstractWindowSceneDelegate` `%new isInvalidated/setInvalidated:` | PORTABLE | 2.1 |
| kfc `%new suppressKeyboardFocusEvaluationForReason:` + `BSCompoundAssertion` | PORTABLE (API) | 4.1 |
| `MSHookFunction` on `_reevaluatePolicyAndUpdateRulesIfNeeded` (0x1c6321b74, prologue-verified) | PARTIAL | 4.1 |
| kfc `windowSceneDidDisconnect:` hook | PORTABLE | 4.2 |
| `SBWindowSceneManager activeDisplayWindowScene` hook (+ `%new` following-keyboard / following-user-interaction) | PORTABLE (fallback) / PARTIAL (touch + pointer) | 5.4 |
| `BPMultiDisplayCoordinator` (sniffers folded into `handleSendEvent:`), `SpringBoard sendEvent:` hook, connect hooks on both delegates | PARTIAL | 5.1 - 5.3, 2.3 |
| `SBExternalDisplayWindowSceneDelegate sceneDidDisconnect:` wrapper | PARTIAL | 2.1 |
| `SBControlCenterController` / `SBFluidSwitcherGestureManager gestureRecognizerShouldBegin:` | PARTIAL | 7 |
| `BKSMousePointerService pointerSuppressionAssertionOnDisplay:...` display scoping | PARTIAL | 6 |
| everything under `#if 0` | NOT PORTABLE | 6, 4.3, 8, 7 |

Deviations from 16.2 on purpose: the coordinator class is `BPMultiDisplayCoordinator` (no 16.2 class name is registered);
before the coordinator has seen any qualifying event `activeDisplayWindowScene` keeps its 16.0 keyboard-following value
(16.2 would return the embedded scene); a nil own window scene does not reject a gesture (16.2 rejects); the
coordinator falls back to the first touch's window when the HID context id cannot be resolved;
`setInvalidating:NO` is ignored instead of trapping; the kfc `windowSceneDidDisconnect:` loop uses
`removeKeyboardFocusFromScene:` and a final `updateKeyboardFocusDeferringRules` instead of the direct 3-argument remove method.

Verification status of the draft: the plain Objective-C parts and the hook bodies (Logos directives mechanically
rewritten) pass `clang -fsyntax-only -fobjc-arc` against hand-written stand-in Foundation / runtime headers
(`-DBP_G4_STANDALONE`). It has not been built with Theos/Logos nor run on a device. Selectors sent to private
classes are either guarded with `respondsToSelector:`, appear in the 16.0 disassembly sent to that same class, or are
long-standing BaseBoard API (`BSCompoundAssertion`).
