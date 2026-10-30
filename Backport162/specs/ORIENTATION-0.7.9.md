# ORIENTATION-0.7.9 - port of the 16.2 orientation re-architecture (16.0 = 20A8372, 16.2 = 20C65, unslid cache addresses)

Nothing here was run on a device. "Decoded" means read in the disassembly of both builds (the scratchpad helpers a160.sh / a162.sh). Code: `Z2OrientTraits.m` (area 1 + 2).
Debug lines: `Backport162.debug`, grep `z2o:`. Kill files: `<jbroot>/tmp/Backport162.off.<switch>`.

## 0. Acceptance criterion (user, 30 Oct): 16.2 reflective rotation and cross display moves

Checklist, each item verified against the 16.2 disassembly. Status words: PORTED (code + decoded), PARTIAL, OPEN (named reason), UNPROVEN (needs a device log).

| # | behaviour | 16.2 mechanism | status |
|---|---|---|---|
| R1 | the switcher's container orientation of the main display follows the device rotation through the traits arbiter | `switcherOrientation:...` (16.2 0x1c7600950) = switcher participant `currentOrientation` after `updateAllParticipants:` | PORTED (section 1) |
| R2 | rotating from a stage / switcher / home: follow-up rotation transition | `_needsOrientationReevaluation` set by the decision rules, consumed by the validator of `FollowupRotation` enqueued in `transitionDidBegin` (0x1c76042cc) | PORTED (section 1) |
| R3 | phone-only (iPhone) app on the iPad: orientation animation settings, policies 3 / 4 | decision rules + `animationSettingsForRotation...` only while not live resizing and with a scene on the primary delegate | PORTED (section 1) |
| R4 | portrait-only / landscape-only windows under Stage Manager (guiding participants) | `SBSwitcherTraitsAssistant` guides | PORTED earlier as `BPG3BTraitsGuide` (G3B.x, switch g3b_guide); this file keeps the 16.0 participant creation and feeds it the 16.2 policies |
| R5 | the external display never rotates; its orientation is fixed by the display | arbiter input of the external pipeline (`SBTraitsExternalDisplayPipelineManager -inputs`) | PORTED as a deviation (section 2), UNPROVEN |
| R6 | "Move to display" / "Move to iPad": orientation of the moved window on the target | the moved scene resolves its orientation against the TARGET display's arbiter (R5) and the take-over of the scene (CORE-LEFTOVERS 10) | PARTIAL: data path fixed by R5, take-over by the core agent (`p1_toappstake`), UNPROVEN |
| R7 | frames / sizes / positions of windows when the container rotates (strip, dock, stage) | calculator `_frameForLayoutRole:...containerOrientation:...` (ported G2B.m), reference frames from `[layoutState interfaceOrientation]` | PARTIAL: depends on R1/R5 data; content / container split of the scene view stack OPEN (section 4) |
| R8 | status bar, corner radii, shadows while rotating | `SBFluidSwitcherViewController` rotation methods, page shadow views (G2H.x) | OPEN: shadow / corner code is identical in both releases (section 4.3), the 16.0 difference is the orientation data they are fed |
| R9 | sideways on screen keyboard | keyboard follows the traits participant of the keyboard role and `SBMedusaHostedKeyboardWindowController` | display agent (G3B.x / X7Keyboard.x); this file only guarantees R1 / R5 data |

## 1. SBSwitcherController traits flow (`Z2OrientTraits.m`, switches `or_traits`, `or_label`)

### 1.1 What 16.2 changed (decoded; 16.0 method address / 16.2 address)
* `-switcherOrientation:elementsOrientations:forTransitionRequest:previousLayoutState:layoutState:` 0x1c6178cec / 0x1c7600950. Called from `-[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:]` (16.0 0x1c5e25c38, 16.2 0x1c7298d00) which stores the results with `setInterfaceOrientation:` / `setInterfaceOrientationByLayoutElementIdentifier:` on the NEW layout state: this is the ONLY place where a layout state gets its orientation, for every display (the switcher controller of the request's display answers).
  * `*outOrientation = [_traitsParticipant currentOrientation]` (the switcher participant) in both releases; elements: 16.0 `_currentElementsOrientationsForLayoutState:` (0x1c617b3fc), 16.2 `_orientationsForLayoutStateElements:withAssociatedParticipants:` (0x1c7602ba0) = `_elementsOrientationsForParticipantsByElementIdentifier:` (0x1c7602c8c, `participant.currentOrientation` per element id) + count assertion. Same map.
  * Rule 1, `_canDetermineActiveOrientation`: 16.0 `!inHomeScreen`; 16.2 `inHomeScreen ? old : YES` (ivar +0x89).
  * Rule 2 (chamois): 16.0 `own = inSwitcher ? 5 : 4`; 16.2 `systemGesture || (fromSwitcher && inApp)` -> own 5 and re-evaluate, else `inSwitcher ? 5 : 4`. Non primary / primary overlay policy 3 / 3.
  * Rule 3: non primary overlay policy of the stable-in-app and home paths = `phoneAppOnPad ? 3 : primaryPolicy` (16.0 always 3).
  * `_waitingFollowupTransition` (16.0 +0x79) is gone. 16.0 enqueued the `FollowupRotation` transition inside the method when its flag was set and then waited for it; 16.2 stores the flag in `_needsOrientationReevaluation` (+0x7a) and `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` (0x1c76042cc, 16.0 a 3 instruction stub 0x1c617c79c) enqueues the transition with a validator that returns and clears the flag (block 0x1c7604400); the same method sets `_canDetermineActiveOrientation = (toLayoutState.unlockedEnvironmentMode != 1)` and updates the publisher participant.
  * Event label check: 16.0 `isEqualToString:@"FollowupRotation"`, 16.2 `containsString:` (labels got a counter).
  * Actuation context: `accountForSceneState` = 16.0 `!phoneOnPad`, 16.2 `phoneOnPad ? NO : !chamois`; without a context and with a phone app on the pad 16.2 sets rotation animation settings only if the context is not in live resize and the primary delegate has a scene.
  * `-_enqueueOrientationTransitionWithActuationContext:...label:` 0x1c617aa5c / 0x1c760212c: label `"%@-%ld"` with a global counter; the 16.0 guard on `_waitingFollowupTransition` is gone; the app transition context update moved from the builder into the validator block (0x1c760250c). Ported: the label (switch `or_label`); the update stays at build time (16.0 order; only observable when the validator rejects the request, then 16.0 touched a request that never runs).
  * New `-actuateOrientationForTraitsDelegate:withContext:reasons:` 0x1c7601958: `animator = [[self _liveOverlayForTraitsDelegate:d] prepareOverlayForContentRotation]; [self updateOrientationForTraitsDelegate:d withUpdateReasons:r suggestedAnimator:animator actuationContext:c]`. Added with `class_addMethod`.
  * `_noteLayoutStateEvaluationBegan/Ended...` / `_areLayoutStateElements:matchedWithAssociatedParticipants:` / `_invalidateLayoutElementsTraitsParticipants` / `didChangeSettingsForParticipant:context:`: participant bookkeeping of the new assistant (evaluation counter, stale participant invalidation, ivar offsets); bodies decoded and equal in effect to the 16.0 `_evaluatingLayoutStateOrientation` flag + `_createTraitsParticipantsForLayoutElementsIfNeeded:` (the 16.0 helpers are kept, see 1.3).

### 1.2 What was ported
`Z2O_SwitcherOrientation` replaces the 16.0 IMP with the 16.2 body statement by statement: same guards (nil arguments fall back to the 16.0 body which raises the same assertion), same early outs (under UI lock / no participant while locked), same decision tree (`Z2O_Decide`, every branch labelled with its 16.2 address in the code), same order of calls. The ivars of the 16.0 layout are read / written by name (`class_getInstanceVariable`); the one new ivar is an associated object. `Z2O_TransitionDidBegin`, `Z2O_Enqueue`, `Z2O_Actuate` as above.
Log lines: `z2o: swo (main|ext) request '<label>' src N followup F chamois C phoneOnPad P: own policy ... reevaluate R`, `z2o: swo (...) -> container orientation N, element orientations {...}`, `z2o: transitionDidBegin (...): re-evaluation pending, enqueue FollowupRotation`, `z2o: enqueue orientation transition '<label>-<n>'`, `z2o: traits installed ...`.
Guards (never silent): a missing ivar / selector / class logs `z2o: GUARD ...` once and the 16.0 body runs.

### 1.3 Documented deviations
* Participant creation: 16.2 creates the participants in `SBSwitcherTraitsAssistant -createTraitsParticipantsForLayoutElements:outParticipantsByElementIdentifier:outDelegatesByParticipant:outPrimaryDelegate:` (0x1c7d5be20 stub) every time the elements differ, keeps the previous maps otherwise and invalidates participants that are not in the new set (`_noteLayoutStateEvaluationEnded...`). The port calls the 16.0 `_createTraitsParticipantsForLayoutElementsIfNeeded:shouldPerformFirstResolution:NO` (same participants, same delegates, kept in the 16.0 ivars read by `BPG3BTraitsGuide`). Effect-equal for the orientation results; the lifetime of participants of removed elements differs in timing only.
* Update of the app transition context at enqueue time (see 1.1).

### 1.4 Test
Rotate the iPad (all four orientations) in the home screen, the app switcher and with one / several Stage Manager windows; the log must show one `z2o: swo (main)` pair per layout state evaluation with `container orientation` equal to the device orientation and, for a swipe from an app into the switcher or a system gesture, `reevaluate 1` followed by `enqueue FollowupRotation`. Kill file `Backport162.off.or_traits` returns to the 16.0 body.

## 2. The display's real orientation in the traits flow (switches `or_extinputs`, `or_extreal`)

### 2.1 What the logs say
Every layout state of every display is created by section 1's method, so its orientation is the `currentOrientation` of the traits participant of the display's switcher. Layout states logged during monitor use show `UIInterfaceOrientationPortrait` / `contentOrientation portrait (1)` (CORE-LEFTOVERS 7, 10, 11) although the canvas is 2560 x 1440, and a window moved to the monitor comes out portrait.
### 2.2 Mechanism
The external window scene has its own traits arbiter (`SBTraitsExternalDisplayPipelineManager`, same class and same bodies in both releases: `inputs` 16.0 0x1c616fa60 / 16.2 0x1c75f7740, `setupDefaultPipelineForArbiter:` 0x1c616f898 / 0x1c75f7578). Its only orientation input is `SBFTraitsArbitrationDeviceOrientationInputs initWithCurrentDeviceOrientation:nonFlatDeviceOrientation:` with `[windowScene interfaceOrientation]`, built ONCE (lazy ivar `_inputs` at +0x28) at the first call of `-inputs`. Every role of the external pipeline (switcher, app windows, keyboard) resolves against that single snapshot. If the scene reported Portrait at that moment, the monitor is "Portrait" for the whole connection, and so is every layout state, every element orientation and the scene settings of a window moved there.
### 2.3 Port (deviation from the 16.2 body, which has the same lazy cache but a scene already in its final orientation)
`Z2O_ExtInputs` (switch `or_extinputs`): on every call compares the cached input with the display's real orientation (the scene's own orientation when it agrees with the shape of the canvas, else LandscapeRight for a landscape canvas / Portrait for a portrait one) and rebuilds the input object (same three classes and init selectors as the 16.0 body) when they differ. One log line per scene: `z2o: external display arbiter input kept|REFRESHED: device orientation N (scene orientation M, canvas shape S)`.
`Z2O_GuardExternal` (switch `or_extreal`, last line guard): after the participant answered, an external display's container orientation that contradicts the canvas shape is replaced by the real orientation: `z2o: GUARD(or_extreal) ...`. Every external evaluation also logs `z2o: ext display state orientation: participant N, scene orientation M, canvas shape S -> real R`.
### 2.4 Unproven
Whether the monitor's scene reports Portrait at the first `inputs` call (the new log lines answer it in one connection). If the cached input was already right and the participants still answer Portrait, the next suspects are the role policies of `SBTraitsExternalDisplayRolesAndDefaultPoliciesProvider` (orientation stage block 16.0 0x1c63b9858 / 16.2 0x1c7863f04, 215 vs 233 instructions; the extra instructions are the new roles of G3B 6) and the `_activeOrientationParticipant` of the pipeline manager.

## 3. Switches added

| switch | file | meaning |
|---|---|---|
| or_traits | Z2OrientTraits.m | 16.2 body of `switcherOrientation:...`, `transitionDidBegin`, `actuateOrientationForTraitsDelegate:` |
| or_label | Z2OrientTraits.m | unique label of orientation transition requests |
| or_extinputs | Z2OrientTraits.m | external display arbiter input follows the display's real orientation |
| or_extreal | Z2OrientTraits.m | last line guard on the external container orientation (logged) |

## 4. Not yet ported (reasons, in the order they will be done)
### 4.1 Content / container orientation split of the scene view stack (SBAppViewController, SBSceneViewController, SBDeviceApplicationSceneView, ClassicSupport, live overlay, overlay view provider)
OPEN. 16.0 already splits content and container through `SBOrientationTransformWrapperView`; 16.2 renames the API and moves counter rotation into overlay views (`needsCounterRotation`). The classes and adapters exist (CORE-LEFTOVERS 3b, G3B 1.6 / 1.7). Not started in this file.
### 4.2 Dock rotation plumbing (`SBFloatingDockRootViewController _begin/_endPresentationTransition`, `SBWindow initWithWindowScene:...`)
OPEN. 16.0 calls `setNeedsUpdateOfSupportedInterfaceOrientations` around the dock presentation when traits arbiter actuation is enabled; 16.2 moved it to traits participants.
### 4.3 Shadows
The page shadow view, `shadowOpacityForLayoutRole:` and the container sizing are identical in both releases (CORE-LEFTOVERS 8); a lopsided shadow after rotating the iPad can only come from the frame / scale the container gets, i.e. from the orientation data of section 1 / 2 and the unported 4.1.
