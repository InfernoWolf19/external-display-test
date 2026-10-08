# Group 1c: reconstruction of the Stage Manager pieces that group1b called NOT PORTABLE (16.2 / 20C65 -> 16.0 / 20A8372)

Package `group1c-reconstruct`. Written incrementally: every item below is appended when finished; tags are
**DONE** or **UNSURE:<what to check on a device>**. Companion code: `group1c-reconstruct.hooks.m` (same item numbers in comments).

Directive: nothing is "not portable"; it only ever meant "needs a full reimplementation". Every item is therefore a
reconstruction (new run-time classes, whole-method replacements, associated objects, categories).

Conventions (same as group1b): addresses are unslid vm addresses; "162" = 20C65, "160" = 20A8372. Framework facts (event / response
type numbers, query-protocol trampolines, run-time subclass contract, `G1B_*` helper kit) are in `group1b-modifiers.md` section 0 and
`group1b-modifiers.hooks.m`; the hooks file of this package is meant to be appended to the same translation unit as the 1b file and uses
its helpers (`G1B_MakeClass`, `G1B_SUPER`, `G1B_GET/G1B_SET`, `G1B_Send*`, `G1B_Append`, `G1B_HasSuper`, `G1B_IvarOffset`, `G1B_NewUpdateLayoutResponse`).

## Progress log
5a, 5b, 5c, 5d, 5e, 5f, 3, 4 (earlier sessions); 1d, 1f, 1b, 1a, 2/2b, 5.x producers, data-layer requirements, SUMMARY (this session). All items have a section; see SUMMARY for the tags.


---------------------------------------------------------------------------------------------------

## 5a. SBGridSwipeUpGestureRootSwitcherModifier + SBGridSwipeUpGestureSwitcherModifier (delay flag) + SBContinuousExposeToHomeSwitcherModifier   **DONE**

### What 16.2 changed in `SBGridSwipeUpGestureSwitcherModifier` (answers "check initWithGestureID:delayCompletionUntilTransitionBegins: in 16.0")
`initWithGestureID:delayCompletionUntilTransitionBegins:` does **not exist in 16.0** (16.0 class dump: only `initWithGestureID:`, ivars `_translation +0x78`,
`_isApplyingContentViewScaleToSwitcherViewBounds +0x88`, `_dismissSiriModifier +0x90`; 16.2 adds `_delayCompletionUntilTransitionBegins +0x98` and the
read-only property). Method-by-method structural diff of 160 vs 162 (`sd.py`): only these differ:

| method | 160 | 162 |
|---|---|---|
| `initWithGestureID:` | 0x1c64260d0 real init (super init, add `SBDismissSiriSwitcherModifier` child) | 0x1c78d5e88 thunk `initWithGestureID:delayCompletionUntilTransitionBegins:NO` |
| `initWithGestureID:delayCompletionUntilTransitionBegins:` | - | 0x1c78d5e90: super `initWithGestureID:`, store flag at +0x98, `_dismissSiriModifier = [SBDismissSiriSwitcherModifier new]`, `addChildModifier:` |
| `delayCompletionUntilTransitionBegins` | - | property getter |
| `handleGestureEvent:` | 0x1c64265e0: `r = [SBGestureSwitcherModifier handleGestureEvent:]`; phase 2/3: `_translation = [e translationInContainerView]`; phase 3: `final = [self finalResponseForGestureEvent:e]`; request = new `SBMutableSwitcherTransitionRequest`; `final ? setUnlockedEnvironmentMode:2 : setAppLayout:[SBAppLayout homeScreenAppLayout]`; `r = [SBSwitcherModifierEventResponse responseByAppendingResponse:[[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:YES] toResponse:r]`; **`[self setState:1]` unconditionally** | 0x1c78d63b0: identical, but `setState:1` only `if (![self delayCompletionUntilTransitionBegins])` |
| `handleTransitionEvent:` | - | 0x1c78d6530: `r = [super ...]; if (delay && [e phase] >= 2) [self setState:1]` |
| `finalResponseForGestureEvent:` | 0x1c6426754 | 0x1c78d65d0: same arithmetic (threshold `0.25*containerHeight` or `0.125*containerHeight` for mouse events, `velocityY * -0.15 - translationY <= threshold`) |

Effect: the gesture modifier stays alive until the transition it requested has actually begun, so the grid-swipe's visual state (scaled content view) does
not snap back for one frame between gesture end and transition start (the 16.0 `setState:1` at gesture end removed the modifier first).

**Reconstruction.** Run-time subclass `BP162GridSwipeUpGestureSwitcherModifier` of the 16.0 class (ivar `_bp_delayCompletionUntilTransitionBegins` added with `class_addIvar`),
overriding `initWithGestureID:delayCompletionUntilTransitionBegins:`, `delayCompletionUntilTransitionBegins`, `handleGestureEvent:` (whole replacement: the super call goes to
`SBGestureSwitcherModifier`, i.e. the grand-superclass, exactly like the 160/162 code; `_translation` is written through `ivar_getOffset` of the 16.0 ivar) and
`handleTransitionEvent:`. The root creates only this subclass (nobody else needs the delayed variant), so the 16.0 class is untouched.

### SBGridSwipeUpGestureRootSwitcherModifier (new, gesture type 3; superclass `SBGestureRootSwitcherModifier`)  
Methods as in group1b 3.4 (all re-verified against `g1b/162/SBGridSwipeUpGestureRootSwitcherModifier.txt`): `initWithStartingEnvironmentMode:multitaskingModifier:` (0x1c74073bc; NSAssert on the modifier,
line 0x1a, file name `SBGridSwipeUpGestureRootSwitcherModifier.m`), `gestureType` = 3, `gestureChildModifierForGestureEvent:activeTransitionModifier:` = `[[SBGridSwipeUpGestureSwitcherModifier alloc] initWithGestureID:[e gestureID] delayCompletionUntilTransitionBegins:YES]`,
`transitionChildModifierForMainTransitionEvent:activeGestureModifier:` = (`from == 2 && to == 1`) ? `[[SBContinuousExposeToHomeSwitcherModifier alloc] initWithTransitionID:[e transitionID] direction:0 continuousExposeModifier:_SBSafeCast([self _newMultitaskingModifier], SBAppSwitcherContinuousExposeSwitcherModifier)]` (nil when the cast fails) : nil,
`_newMultitaskingModifier` = `[_multitaskingModifier copy]`. Compared with 16.0's `SBHomeGestureRootSwitcherModifier` (0x1c643bf78 / 0x1c643c05c / 0x1c643c20c; same
base class, same `_multitaskingModifier +0x80` slot but an extra BOOL) the root is the Home root stripped down to this one transition.
Base-class API change: 16.2 `SBGestureRootSwitcherModifier` exposes the property `gestureModifier` (16.0: only the method `_gestureModifier` @0x1c6056ca4); a forwarding `gestureModifier` is added to the 16.0
base class when missing (used by the ported WindowDragRoot, item 1).
**Wiring**: `SBContinuousExposeRootSwitcherModifier -gestureModifierForGestureEvent:` type 3 returns this root (item 2). Without that, nothing changes.

### SBContinuousExposeToHomeSwitcherModifier (needed by the root; also by the plain non-gesture 2 -> 1 transition)
Verbatim port of SwitcherDismissFix 0.3.0's decoded wrapper under its real 16.2 name (class does not exist in 16.0). **Install note**: with this class present the SwitcherDismissFix tweak
is redundant for Stage Manager; if both are loaded the first to answer wins (this port's Root hook calls `%orig` first and only fills a nil, exactly like SDF), so there is no conflict.
The Root hook that creates it for the non-gesture case is in item 2.

Confidence: high (all selectors and the one behavioural diff verified in the disassembly). UNSURE: none beyond the base-class (`SBGestureRootSwitcherModifier`) differences 16.0/16.2 (its `handleTransitionEvent:`/`handleGestureEvent:` bodies changed; the 16.0 versions are used).

---------------------------------------------------------------------------------------------------

## 5b. The two gesture workspace transactions and the base-class API change   **DONE**

group1b 3.5 said "nothing to port"; the 16.2 diff shows one real API change that any 16.2-shaped caller (the group2b gesture-manager port) relies on.

**What changed (decoded).** `SBFluidSwitcherGestureWorkspaceTransaction` (160 class 0x1dd670f38 / 162 0x1dd7d9618) was made multi-display aware:
* ivars: `_originalLayoutState`/`_activeLayoutState` (single `SBMainDisplayLayoutState`) -> `_originalLayoutStatesBySwitcherController` / `_activeLayoutStatesBySwitcherController` (`NSMapTable`); `_sceneLayoutTransaction` + `_layoutCompletion` ->
  `_layoutTransaction`, `_ancillaryLayoutTransactions`, `_layoutTransitionCompletions` (sets). Every later ivar shifts by +8 (`_gestureID` 0x180 -> 0x188, `_selectedAppLayout` 0x188 -> 0x190); subclass ivar `_completedGestureWithTransitionRequest` 0x190 -> 0x198 (this is why no code may use offsets).
* entry points: `updateGestureWithTransitionRequest:` (160 0x1c6034b4c) -> `handleTransitionRequestForGestureUpdate:fromGestureManager:` (162 0x1c74afba4); `completeGestureWithTransitionRequest:` (160 0x1c603530c) -> `handleTransitionRequestForGestureComplete:fromGestureManager:` (162 0x1c74b0490).
  The callers moved the same way: `-[SBFluidSwitcherGestureManager updateGestureWithTransitionRequest:]` / `completeGestureWithTransitionRequest:` (160 0x1c643fb98 / 0x1c643fba0: pure `b objc_msgSend$` thunks into the transaction; in 16.0 the other caller is `-[SBMainSwitcherControllerCoordinator switcherContentController:performTransitionWithRequest:gestureInitiated:]` 0x1c624217c / 0x1c6242238) became
  `handleTransitionRequestForGestureUpdate:` (162 0x1c78f17f0 -> thunk 0x1c78f17f8) and `handleTransitionRequestForGestureComplete:` (0x1c78f17fc) which sends `...Complete:fromGestureManager:self` (0x1c78f1870) after, when `[[request appLayout] isEqual:[SBAppLayout homeScreenAppLayout]]`, calling its own `_clearSystemApertureZStackPolicyAssistantSuppression` (0x1c78f1818..0x1c78f1860).
* body: the transition request is converted with `_workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel:` (0x1c74b1478; 160: `_transitionRequestForSwitcherTransitionRequest:eventLabel:`), the target `SBSwitcherController` comes from `[workspaceRequest windowScene]` / `_switcherControllerForWorkspaceTransitionRequest:` (0x1c74b1f5c), the animation controller from
  `[switcherController animationControllerForTransitionRequest:]` (a `switcherCoordinator` hop was added), and `_updateMainDisplayIfNecessaryForWorkspaceTransitionRequests:` (0x1c74b0e90) runs before the layout transaction. New delegate methods `transaction:shouldKeepSceneForeground:withReason:` (0x1c74afb5c). All of that is group2b's gesture-manager/transaction scope; it is NOT needed by the Stage Manager subclasses.
* subclass renames: `SBRevealContinuousExposeStripsGestureWorkspaceTransaction` (160 0x1de09abc8) -> `SBContinuousExposeStripRevealGestureWorkspaceTransaction` (162 0x1de22de48, `_gestureType` 0xb at 0x1c7420d2c, `handleTransitionRequestForGestureComplete:fromGestureManager:` 0x1c7420d34 = `_completedGestureWithTransitionRequest = YES; [super ...]`, `_canBeInterrupted` 0x1c7420d7c = `_completed ? [super _canBeInterrupted] : YES`, identical to 160 0x1c5fa7f98);
  `SBRevealContinuousExposeStripOverflowGestureWorkspaceTransaction` (160 0x1de0a0050) -> `SBContinuousExposeStripOverflowGestureWorkspaceTransaction` (162 0x1de233320; `_gestureType` 0xc). `-[SBFluidSwitcherGestureManager _fluidSwitcherGestureTransactionClassForGestureType:]` (160 0x1c5e58868 / 162 0x1c72caff8) maps 0xb / 0xc to them.

**Port (hooks 5b).** (a) `%new`-style `class_addMethod` of both 16.2 entry points on the 16.0 base class, forwarding to the 16.0 methods (re-entrancy guarded, so a later full port of the base class that routes the 16.0 name back into the 16.2 name cannot recurse);
the 16.0 Reveal subclass override of `completeGestureWithTransitionRequest:` therefore still sets the flag, which reproduces the 16.2 subclass method exactly. (b) The two 16.2 class names exist as run-time subclasses of the 16.0 classes (no ivars, no methods: `_gestureType`, `_canBeInterrupted` and the flag are inherited). (c) a hook on `_fluidSwitcherGestureTransactionClassForGestureType:` returns the alias classes for 0xb / 0xc so that `NSStringFromClass` and class checks written for 16.2 hold.
Requirement on group2b: if it replaces the gesture manager's two thunks with the 16.2 `handleTransitionRequestForGesture*:` methods, it only has to call `[txn handleTransitionRequestForGesture{Update,Complete}:req fromGestureManager:self]`; the transaction side is provided here.
Confidence: high.

---------------------------------------------------------------------------------------------------

## 5c. Identifier pipeline: ids-changed event, SBContinuousExposeIdentifierSlideModifier, SBOverrideContinuousExposeIdentifiersSwitcherModifier, VC update method   **DONE** (UNSURE: the root-side `adjustedContinuousExposeIdentifiersIn*` queries need the AppSwitcherCE rewrite, item 1a)

### Event `SBContinuousExposeIdentifiersChangedModifierEvent` (type 35 in both builds)
16.0 init `initWithPreviousContinuousExposeIdentifiers:transitioningFromAppLayout:transitioningToAppLayout:generationCount:` (0x1c625d8f4; ivars +0x18 prev set, +0x20 from, +0x28 to, +0x30 gen). 16.2 init
`initWithPreviousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:transitioningFromAppLayout:transitioningToAppLayout:animated:` (0x1c76f4a58; ivars `_animated +0x18`, InSwitcher +0x20, InStrip +0x28,
from +0x30, to +0x38; NSAssert on both lists, lines 0x12/0x13); `isAnimated`, `copyWithZone:` via the new init, `descriptionBuilderWithMultilinePrefix:`. 16.0's `previousContinuousExposeIdentifiers` / `generationCount` are gone.
**Reconstruction**: run-time subclass `BP162ContinuousExposeIdentifiersChangedModifierEvent` of the 16.0 class: the new init calls the 16.0 designated init (old set built from the switcher list, generation 0) so every 16.0 reader still works, and stores the two lists + `animated` (associated objects). `isAnimated`/`previousContinuousExposeIdentifiersInSwitcher/InStrip` are also added (guarded) to the plain 16.0 class
(YES / old list) for events a 16.0 path still creates.

### Slide modifier (16.2 form)
Fully decoded (see the code comments for every address). Logic: direction 0 = a group was added, 1 = removed.
* init asserts the three arguments (lines 0x20 ident, 0x21 InSwitcher, 0x22 InStrip), copies them, `_uniqueAnimationIdentifier = [[NSUUID UUID] UUIDString]`.
* reasons are per instance: `"%@-WaitingToPrepareLayout"`, `"%@-WaitingToAnimate"` (16.0: class-wide strings, so two slides running together answered each other's timers).
* `handleContinuousExposeIdentifiersChangedEvent:`: `r = [super ...]`; only if `[event isAnimated]`: direction 1 -> if not waiting-to-begin: `r = Append(_beginAnimation, r)`; direction 0 -> if neither flag: `r = Append(UpdateLayout(2,2), r)`, `r = Append(Timer(delay 0, reason PrepareLayout), r)`, `_isWaitingToPrepareLayout = YES` (phase 1: the new group is laid out OFF-screen for one pass).
* `handleTimerEvent:`: direction 0: reason == PrepareLayout and waiting-to-prepare -> clear it, `r = Append([self _beginAnimation], r)`; direction != 0: reason == Animate and waiting-to-begin -> clear it, `setState:1` (done).
* `_beginAnimation`: `UpdateLayout(options 0xc, mode 3)`, `Timer(delay = appToAppLayoutSettings.response * 0.5, reason Animate)`, `_isWaitingToBeginAnimation = YES`.
* geometry: the group whose `continuousExposeIdentifier` equals ours. adding & waiting to prepare: frame/accessory frame x = LTR `-(stripWidth + screenEdgePadding) - w/2`, RTL `containerBounds.maxX + screenEdgePadding + stripWidth - w/2` (w = the width the super returned; y, w, h unchanged); removing & waiting to begin: frame, anchor point, scale and accessory frame are the `[super ...]` answers evaluated inside
  `_performBlockWithIdentifiersInSwitcher:(previous InSwitcher) identifiersInStrip:(previous InStrip) block:` = `performTransactionWithTemporaryChildModifier:` of a new `SBOverrideContinuousExposeIdentifiersSwitcherModifier` (so the group is placed where it was before the removal).
  `animationAttributesForLayoutElement:` while waiting to begin: `[[super ...] mutableCopy]` with `layoutUpdateMode 3` and `layoutSettings = switcherSettings.chamoisSettings.appToAppLayoutSettings`.
* New class `BP162ContinuousExposeIdentifierSlideModifier` (direct subclass of the 16.0 class's superclass, so none of 16.0's override-flag logic is inherited). The 16.0 class stays for any 16.0 creator.

### Override modifier upgrade
group1b created `SBOverrideContinuousExposeIdentifiersSwitcherModifier` with the 16.0 selector `continuousExposeIdentifiers` returning the stored object as is. Now `continuousExposeIdentifiersInSwitcher` / `...InStrip` are added to that class (162 0x1c798bd44 / 0x1c798bda8) and the legacy method converts to `NSOrderedSet`
(16.0 readers use set API). The two new selectors only take part in the query chain when the extended context protocol (group2 section 0, approach A) is active; otherwise they are dead code and the temporary modifier still overrides the legacy list.

### VC `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:`
Whole-method replacement exactly as 16.2 (see A2.2 of group2) — asks the root modifier for the two adjusted lists (falls back to group2's builders if the root does not answer), bumps the 16.2 generation (group2's `BP162VCState`), keeps the 16.0 ivars (`_continuousExposeIdentifiersChangedGenerationCount`, `_continuousExposeIdentifiers`
as an ordered set, clears `_appLayoutsForContinuousExposeIdentifiers`) and ALWAYS dispatches the event (16.0: only when animated). It must be installed AFTER group2's `G2B` hook of the same method.
### Invalidate response (type 40 here, 34 in 16.2)
Consumer = group1b's `G1B_VCInvalidate` (calls the VC method above). Producers: drag destination (item 1d). The Root `handleEvent:` producer is NOT installed: the 16.0 VC already calls the update method inline from its transition blocks (0x1c5fc50c4 / 0x1c5fc5d9c) at the same phases, so emitting again would double-invalidate; the Root keeps only the `_effectiveAppLayoutOnStage` bookkeeping (item 2).

---------------------------------------------------------------------------------------------------

## 5d. SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier   **DONE** (the creator is in the Root, item 2)

Structural diff of all methods (`sd.py`) leaves four changed methods; all four are re-implemented as hooks on the 16.0 class (hooks 5d), with ivars accessed by name (`_generationCount` 0x88, `_initialGenerationCount` 0x68, `_appLayout` 0x78, `_behindAppLayout` 0x80, `_appLayoutToOrderFront` 0x70, `_isDelayingCompletionForHover` 0x60 in both builds):
1. `handleContinuousExposeIdentifiersChangedEvent:` (162 0x1c758977c / 160 0x1c6104180): `r = [super ...]`; **only for animated events**; `_generationCount` is now stored from the *context* `[self continuousExposeIdentifiersGenerationCount]` (16.0: `event.generationCount`); if it equals `_initialGenerationCount`, append a 1.5 s timer with reason `[self _timeoutReason]`; then
   same group id as `_appLayout` -> `_appLayoutToOrderFront = event.transitioningToAppLayout` and (if `[_appLayout isEqual:_behindAppLayout] || [to isEqual:_behindAppLayout]`) append `_completeIfNeededIgnoringHover:YES`; different group -> `_appLayoutToOrderFront = nil` and append `_completeIfNeededIgnoringHover:YES`.
2. `_timeoutReason` (162 0x1c7589cb4): `"%@-%ld"` with class name and **`_initialGenerationCount`** (16.0: `_generationCount`, which the handler changes, so a second ids event silently invalidated the timer).
3. `_completeIfNeededIgnoringHover:` (162 0x1c7589b7c): new first test `if ([self state] == 1) return nil;` (a finished modifier no longer re-issues the activate-transition request); rest identical (hover gate `_isDelayingCompletionForHover` + `anyHighlightedAppLayoutsForContinuousExposeIdentifier:`, then `Perform(requestForActivatingAppLayout:_appLayoutToOrderFront)` only if `_generationCount == _initialGenerationCount`, always `setState:1`).
4. NEW `handleTransitionEvent:` (162 0x1c75896c8): drops `_appLayoutToOrderFront` when `[[event appLayoutsWithRemovalContexts] containsObject:_appLayoutToOrderFront]` (the window was closed meanwhile), then `[super]`.
Effect: no double completion / stale order-front after closing a window during a keyboard cycle. The creator `SBContinuousExposeRootSwitcherModifier -handleContinuousExposeIdentifiersChangedEvent:` passes the generation (item 2).

---------------------------------------------------------------------------------------------------

## 5e. Strip-reveal / strip-overflow gesture modifiers and their roots   **DONE** (UNSURE: rubber-band curve, completion safety timer)

**SBRevealContinuousExposeStripsGestureModifier** (ivars identical in both builds: `_progress +0x78`, `_initialAppLayout +0x80`; the hooks therefore add methods to the 16.0 class).
Changes decoded from 160 0x1c63706d4 (handleGestureEvent:) vs 162 0x1c781783c plus 5 new methods:
* `isIndirectPanGestureEvent` is a new event predicate (162: `SBSwitcherModifierEvent` NO @0x1c7878cf8, `SBIndirectPanGestureSwitcherModifierEvent` YES @0x1c7878b28); added to both 16.0 classes.
* progress: 16.0 `|tx| / 100` constrained with no rubber band, show when `>= 0.5`. 16.2: `delta = indirect ? (rtl ? tx : -tx) : (rtl ? -tx : tx)`, `progress = BSUIConstrainValueToIntervalWithRubberBand(max(delta,0) / chamoisLayoutAttributes.stripWidth, range, interval [0,1] both ends rubber-banded)`,
  range 0.1 for indirect (pointer scroll) and 0.2 for touch. (group1b wrote the two constants the other way round; the `fcsel` at 0x1c78178d8 selects 0.1 for the indirect case.)
* end of gesture (phase 3): indirect -> `canceled ? (endReason == 5) : (endReason == 3 || progress >= 0.25)`; touch -> `!canceled && progress >= 0.25` (16.0: `>= 0.5`, `indirectPanEndReason` 5 / 3 special cases). Show = `SBUpdateContinuousExposeStripsPresentationResponse(presentation 1, dismissal 0)`, hide = `(0, 1)`; then `UpdateLayout(0xc, 3)` and `Perform(requestForActivatingAppLayout:_initialAppLayout, gestureInitiated YES)`.
  16.0 ended with `setState:1` inside handleGestureEvent:; 16.2 removed it: NEW `handleTransitionEvent:` does `[super]; if (phase >= 2) setState:1`.
* NEW `continuousExposeStripProgress` (= `_progress`, replaces 16.0's `continuousExposeAppStripUnoccludedProgress`, which stays), `cornerRadiiForIndex:` (initial layout: radius = `displayCornerRadius` or, if 0, `chamoisLayoutAttributes.stageCornerRaddii`, divided by `scaleForIndex:`; all four corners; else `[super]`),
  `shadowOpacityForLayoutRole:atIndex:` (initial layout whose `[super frameForIndex:]` size equals `containerViewBounds.size`: `clamp(superShadow * _progress, 0, 1)`), `animationAttributesForLayoutElement:` (layout elements: `SBFFluidBehaviorSettings` trackingResponse 0.15 / trackingDampingRatio 0.85 as layout, position and opacity settings, `updateMode 5`).
* Safety (not in 16.2): because completion now depends on a transition event reaching the modifier, a 2 s timer (`BP162RevealStripsCompletionTimeout`) also completes it. UNSURE: whether 16.2 can leave the modifier alive when the activate request is a no-op; on a device check that the strip reveal gesture ends cleanly (log line from the timer path).
* The rubber-band function is resolved with `dlsym("BSUIConstrainValueToIntervalWithRubberBand")` (it is exported by BaseBoardUI/ BSUI); a documented stand-in is used if it is missing.

**SBRevealContinuousExposeStripOverflowGestureModifier**: all 17 "changed" methods differ only by the selector `_overlappingModelForAppLayout:` -> `overlappingModelForAppLayout:` (16.0 had a private copy; its `SBSwitcherModifier -overlappingModelForAppLayout:` base method already exists in 16.0, 0x1c61c4450) — nothing to port.
**SBRevealContinuousExposeStripOverflowRootSwitcherModifier** `transitionChildModifierForMainTransitionEvent:activeGestureModifier:` (162 0x1c78bbf18): `[[SBContinuousExposeSwitcherToAppModifier alloc] initWithTransitionID:[e transitionID] direction:1]` (16.0: `initWithTransitionID:`) — the direction-aware SwitcherToApp class is item 2 (`BP162ContinuousExposeSwitcherToAppModifier`); the Overflow root is wired by a hook (item 2, "overflow root").
The Reveal-strips root needs no change.

---------------------------------------------------------------------------------------------------

## 5f. SBContinuousExposeAppToAppModifier, complete   **DONE** (UNSURE: `isLayoutRoleMatchMovedToScene:` needs DM1)

group1b 4.8 only swapped the 16.0 crossblur child and read `isCommandTabTransition` / `isLaunchingFromDockTransition` from the *modifier* — which nothing ever set (the flags were only put on the event). Complete reconstruction as a new class `BP162ContinuousExposeAppToAppModifier` (superclass `SBTransitionSwitcherModifier`, so 16.0's `adjustedContinuousExposeIdentifiersForIdentifiers:` / `visibleAppLayouts` overrides and the `_shouldSend*` flags are not inherited).
Every method (addresses 162): init 0x1c75957b4 (NSAssert on from/to), `didMoveToParentModifier:` 0x1c759598c (when the to-layout shares no item with the from-layout and is in `[self appLayouts]`: Crossblur child `initWithTransitionID:toAppLayout:fromAppLayout:` if command-tab or launching-from-dock, else `FullScreenToStrip initWithTransitionID:outgoingAppLayout:`), `asyncRenderingDisabled` 0x1c7595acc
(`from == to || [from containsAllItemsFromAppLayout:to]`), `transitionWillBegin` 0x1c7595b40 (`Append(UpdateLayout(2,2), [super])`), `animationAttributesForLayoutElement:` 0x1c7595bd8 (mutable copy; for the two layouts and every non-layout element: `layoutUpdateMode 3`, layout settings Fluid(response 0.4, damping 1.0); for all other layouts: Fluid(0.54, 0.92) as layout/position/opacity settings and `updateMode 3`),
`topMostLayoutElements` 0x1c7595d44 (A = from's centre leaf, B = to's centre leaf: both non-nil and different -> insert A at 0 then B at 0; only A -> insert A; A nil -> unchanged), `opacityForLayoutRole:inAppLayout:atIndex:` 0x1c7595e68 (`isPreparingLayout ? 0 : [super]`), `perspectiveAngleForAppLayout:` 0x1c7595ef4 (`to` layout during `transitionPhase == 1` -> 0), `isLayoutRoleMatchMovedToScene:inAppLayout:` 0x1c7595f80
(`[super]` YES wins; the to-layout -> `isContinuousExposeConfigurationChangeTransition`; otherwise item in both layouts, different attribute objects, and `sizeInBounds:defaultSize:screenEdgePadding:` of from and to differ or `sizingPolicy` differs), `_layoutSettings` 0x1c75961bc (`switcherSettings.chamoisSettings.appToAppLayoutSettings`), and the three BOOL properties (ivars `_continuousExposeConfigurationChangeTransition`, `_commandTabTransition`, `_launchingFromDockTransition`).
Creation: the Root (item 2) builds it from the transition event with `G1C_NewAppToApp(event)` and copies the three flags from the event (`isContinuousExposeConfigurationChangeEvent`, group1b's `isCommandTabTransition`/`isLaunchingFromDockTransition`). The group1b opt-in `G1B_AppToApp` hook is therefore NOT installed any more (its flags were never populated).
Interplay: FullScreenToStrip / Crossblur children come from group1b 2.1 / 2.2 (`gF2SCls`, `gXBCls`). Safe when they are missing (no child is added; the transition then animates without the extra choreography).

---------------------------------------------------------------------------------------------------

## 3. The peek family (fully decoded)   **DONE** (UNSURE: what produces a valid peek configuration while a Stage Manager app is frontmost; the peeked-window geometry numbers)

`SBPeekConfigurationIsValid(cfg)` (162 0x1c77229fc, exported) = `(cfg & ~1) == 2`, i.e. the values 2 and 3 are "peeking"; 0/1 are not. `setPeekConfiguration:1` on a request therefore means "end the peek".
16.0 keeps a *home-screen* peek (`SBPeekHomeScreenContinuousExposeSwitcherModifier`, floor of the root); 16.2 turns peek into a child of the Stage Manager Root so an app can peek over the stage.

### SBContinuousExposePeekSwitcherModifier (superclass SBSwitcherModifier; ivars `_contentModifier +0x60`, `_dismissalTransitionModifier +0x68`, `_appLayout +0x70`, `_configuration +0x78`)
* init 0x1c78e50c4: NSAssert(appLayout) (.m line 0x2c); `_contentModifier = [[_SBContinuousExposePeekContentSwitcherModifier alloc] initWithAppLayout:l configuration:c]`; `addChildModifier:[[SBFilteringSwitcherModifier alloc] initWithAppLayouts:@[l] modifier:_contentModifier]`.
* `debugPotentialChildModifiers` = `@[_contentModifier]`; `appLayoutsToEnsureExistForMainTransitionEvent:` = `@[]`; `setState:` (0x1c78e52ec): when going to 1 and not already 1: `[self newAppLayoutsGenCount]`, then super; `isSwitcherWindowVisible` YES; `transactionCompletionOptions` = reduce motion ? 6 : 2.
* `handleTransitionEvent:` (0x1c78e5410; registers decoded: animated = x25, toValid = x27, fromValid = x26):
  presentation `phase == 2 && animated && toValid && !fromValid` -> add `SBContinuousExposePeekTransitionModifier(tid, from, to, direction 0)`;
  dismissal `phase == 2 && animated && !toValid && fromValid` -> `_dismissalTransitionModifier = PeekTransition(..., direction 1)` and add it;
  `phase == 3 && !animated && !toValid` -> `Append(SBInvalidateAdjustedAppLayoutsSwitcherEventResponse, r)` and `setState:1`;
  `(phase == 2 || !animated) && toValid && !fromValid` -> `Append(SBInvalidateAdjustedAppLayoutsSwitcherEventResponse, r)`.
* `handleEvent:` (0x1c78e5354): after `[super]`, if `_dismissalTransitionModifier.state == 1`: `Append(InvalidateAdjustedAppLayouts, r)`, `setState:1` (the animated dismissal ends when its transition modifier ends).
* `handleScrollEvent:` (0x1c78e566c): super; `phase == 0 && [event isUserInitiated]` and no child with key `"UserScrollingModifier"` -> `addChildModifier:[SBScrollingSwitcherModifier new] atLevel:0 key:@"UserScrollingModifier"` (+ an os_log).
* `appLayoutsForContinuousExposeIdentifier:` (0x1c78e5800): `[super]`; if the identifier equals the peeked layout's group id, drop every layout that `containsAnyItemFromAppLayout:` the peeked layout (block 0x1c78e591c). (group1b had this as UNSURE.)

### _SBContinuousExposePeekContentSwitcherModifier (SBSwitcherModifier; `_fullScreenContinuousExposeAppLayoutModifier +0x60`, `_appSwitcherModifier +0x68`, `_appLayout +0x70`, `_configuration +0x78`)
init 0x1c78e5a04 (NSAssert line 0xaf): `SBFullScreenContinuousExposeSwitcherModifier initWithFullScreenAppLayout:l` with `setHandlesTapAppLayoutEvents:NO`, `setHandlesTapAppLayoutHeaderEvents:NO`, `addChildModifier:atLevel:0`; `SBAppSwitcherContinuousExposeSwitcherModifier new` with both flags NO at level 1.
Queries: `adjustedAppLayoutsForAppLayouts:` = `[super]` split by `isEqual:_appLayout` (peeked first) concatenated with the rest (blocks 0x1c78e5cc0 / 0x1c78e5cd8); `frameForLayoutRole:inAppLayout:withBounds:` = `[super]` then for the peeked layout `frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:`; `scaleForLayoutRole:` = 1.0 for the peeked layout; `shouldAllowContentViewTouchesForLayoutRole:` NO for it; `isLayoutRoleSelectable:inAppLayout:` YES; `switcherHitTestsAsOpaque` NO; `keyboardSuppressionMode` = `suppressionModeForAllScenes`;
`handleTapAppLayoutEvent:` = `[super]` + `Perform(requestForTapAppLayoutEvent:event with setPeekConfiguration:1, gestureInitiated NO)` (tapping the peeked window promotes it); `responseForProposedChildResponse:childModifier:event:` = nil when child == fullscreen modifier and `[event type] == 18` (TapAppLayout) or child == app-switcher modifier, else the super's response.

### SBContinuousExposePeekTransitionModifier (SBTransitionSwitcherModifier; `_fromFullScreenContinuousExposeModifier +0x88`, `_toFullScreen... +0x90`, `_fromAppLayout +0x98`, `_toAppLayout +0xa0`, `_direction +0xa8`) — block internals traced
init 0x1c76ed9e0: NSAssert(fromAppLayout) (line 0x18); `_fromFullScreen = FullScreenCE(from)`; when `direction == 1 && to`: `_toFullScreen = FullScreenCE(to)`.
Direction 0 (presentation): every override falls through to the base except `animationAttributesForLayoutElement:` (below). Direction 1 (dismissal, `transitionPhase >= 2`):
* `visibleAppLayouts` = `[[super] setByAddingObject:_fromAppLayout]` (direction 1 only).
* `frameForIndex:` / `scaleForIndex:` (0x1c76edbf4 / 0x1c76edf30; blocks 0x1c76edea0, 0x1c76edee8, 0x1c76ee198, 0x1c76ee1dc each just `return [capturedModifier frameForIndex:i]` / `scaleForIndex:` run inside `performTransactionWithTemporaryChildModifier:capturedModifier usingBlock:`):
  layout == from and shares no item with `to` -> answered by `_fromFullScreen`; else if `_toFullScreen`, layout shares an item with both `to` and `from` -> answered by `_toFullScreen`; else `[super]`.
* `frameForLayoutRole:inAppLayout:withBounds:` (0x1c76ee220): `r = [super]`; layout == from and not sharing with `to`: `r = frameForContinuousExposePeekingDisplayItem:(item for role) inAppLayout:bounds:defaultFrameForLayoutRole:r`, then `r.x += (r.centerX < containerViewBounds.centerX ? -off : off)` with `off = 4 * chamoisLayoutAttributes.screenEdgePadding` (slides out to the nearest edge); else shared-with-both layouts use `_toFullScreen` (block 0x1c76ee510).
  `scaleForLayoutRole:inAppLayout:` (0x1c76ee560): shared-with-both layouts -> `_toFullScreen` scale (block 0x1c76ee6f0), else super.
* `topMostLayoutElements` (0x1c76ee734): when `to` exists and `from` does not contain all of `to`'s items: `peeked = [to appLayoutWithItemsPassingTest:^(item){ return ![from containsItem:item]; }]` (block 0x1c76ee858); if non-nil `[r sb_arrayByInsertingOrMovingObject:peeked toIndex:0]`.
* `isLayoutRoleMatchMovedToScene:inAppLayout:` (0x1c76ee888): YES when `[to containsAnyItemFromAppLayout:from]` and (`[to containsAny: layout]` or `[from containsAny: layout]`), else super.
* `animationAttributesForLayoutElement:` (0x1c76ee958, both directions, no super call): new `SBMutableSwitcherAnimationAttributes`, `updateMode 3`, `layoutSettings = switcherSettings.chamoisSettings.appToAppLayoutSettings`.

### 16.2-only SBSwitcherModifier method `-frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:` (0x1c76530f8) — decoded
`model = [self overlappingModelForAppLayout:layout]`; `first = [[model zOrderedItems] firstObject]`; `onLeft = (first.centerInModel.x < model.containerBounds.centerX) ? [item isEqual:first] : ![item isEqual:first]`; `pad2 = 2 * screenEdgePadding`;
`x = onLeft ? cvb.minX + pad2 - default.w : cvb.maxX - pad2` (cvb = `containerViewBounds`), then `x += -0.5 * (cvb.w - bounds.w)`; result `(x, default.y, default.w, default.h)`. A peeking window therefore hangs mostly off-screen with `2*padding` visible. Added to the 16.0 `SBSwitcherModifier` as a plain method.
Also added: `+[SBSwitcherTransitionRequest requestForTapAppLayoutEvent:]` (0x1c740d6fc: mutable request, `appLayout`, `activatingDisplayItem = item for role` — 16.0 requests have no such property, kept as associated object —, `source = 0x33` when `event.source == 1`) and `source` / `modifierFlags` getters on the 16.0 tap event (0).
Wiring: the Root's `handleTransitionEvent:` (item 2) adds the peek modifier at level 2 with key `SBContinuousExposePeekModifierKey`. Peeks over the stage only appear if the system produces a transition event with a valid `toPeekConfiguration` while `toEnvironmentMode == 3`; UNSURE on a device: which 16.0 trigger does (log `toPeekConfiguration` from the Root hook).

---------------------------------------------------------------------------------------------------

## 4. App drag-and-drop gesture family   **DONE** (UNSURE: non-Stage-Manager branch of homeScreenDimmingAlpha; order of the three resize-notification thresholds)

16.0's gesture type 7 is `SBContinuousExposePendingEvictionRootSwitcherModifier` (+ `...GestureModifier`, removed in 16.2). The 16.2 pair replaces it. The event layer is identical in both builds (type 5 `SBDragAndDropGestureSwitcherModifierEvent` with `dropAction`, `draggedSceneIdentifier`, `draggedSceneLayoutRole`, `platterViewFrame`, `hasPlatterized`, `hasPreviewLifted`, `isWindowDrag`; type 22 resize progress, 23 blur progress, 25 scene ready; `SBUpdateDragPlatterBlurSwitcherEventResponse`), so the whole family is a pure modifier port.

### SBContinuousExposeDragAndDropGestureRootSwitcherModifier (SBGestureRootSwitcherModifier, `_appLayout +0x80`)
`initWithStartingEnvironmentMode:appLayout:` (0x1c7970ed8; NSAssert line 0x1d when mode == 3), `gestureType` 7, `transitionChildModifierForMainTransitionEvent:activeGestureModifier:` nil, `handleTransitionEvent:` (`[super]`, then `[event handleWithReason:@"<class> handling drag and drop initiated transition."]`).
`gestureChildModifierForGestureEvent:activeTransitionModifier:` (0x1c7970fc4): only when `currentEnvironmentMode == 3`: `max = [[[SBAppSwitcherDomain rootSettings] chamoisSettings] maximumNumberOfAppsOnStage]`; if `[[_appLayout allItems] count] >= max` the item that a drop would evict is the first of `allItems` sorted ascending by `[_appLayout layoutAttributesForItem:i].lastInteractionTime` (block 0x1c7971158: `[@(ta) compare:@(tb)]`), else nil; returns `[[SBContinuousExposeAppDragAndDropGestureSwitcherModifier alloc] initWithGestureID:[event gestureID] appLayout:_appLayout displayItemThatWouldBeEvicted:evicted]`; nil outside mode 3.

### SBContinuousExposeAppDragAndDropGestureSwitcherModifier (SBGestureSwitcherModifier; ivars listed in the code; all 25 methods decoded)
State machine: `_gestureEnded`, `_isResizing`, `_hasResizedEnoughToUnblur`, `_isBlurring`, `_isBlurred`, `_needsBlurBecauseFramesWillMismatch`, `_shouldPushInFullScreenContent`, `_dropAction`, `_platterFrame`, `_location`, `_draggedSceneIdentifier`, `_draggedSceneOriginalLayoutRole`.
* `handleGestureEvent:` (0x1c7638164): super; canceled -> `setState:1`; remembers the size of `frameForIndex:` of `_appLayout`, copies the event fields into the ivars (`_shouldPushInFullScreenContent` via `_shouldPushInFullScreenContentForEvent:`), `_gestureEnded = phase == 3`, re-reads the frame size: `_needsBlurBecauseFramesWillMismatch = sizesEqual ? NO : !_gestureEnded`; then `_recomputeBlurStateWithCompletion:` whose responses are appended.
* `_shouldPushInFullScreenContentForEvent:`: dropAction 1..5 YES; 6..9: windowDrag ? hasPlatterized : YES; else NO. `_showResizeUI`: `!_gestureEnded && (_dropAction & ~1) == 4`.
* `_recomputeBlurStateWithCompletion:` (0x1c7639cf8, block 0x1c7639ed8): `allReady` = for every role of `_appLayout`: `isLayoutRoleContentReady` YES -> YES; not ended -> NO; ended: dropAction 2/3 -> `!_isBlurred`, 4/5 -> NO, 6/7 -> YES, else `item.uniqueIdentifier == _draggedSceneIdentifier`.
  `part = ended ? (_isBlurred && !_hasResizedEnoughToUnblur) : (_isBlurred && _isResizing)`; `newBlurred = !allReady ? YES : (_showResizeUI || part) ? YES : _needsBlurBecauseFramesWillMismatch`; if the gesture ended, was blurred and is not any more, the completion gets `Append(SBUpdateDragPlatterBlurSwitcherEventResponse new, nil)`.
* `handleResizeProgressEvent:` (0x1c7638500): `_isResizing = !(progress == 1)`, `_hasResizedEnoughToUnblur = progress >= medusaSettings.dropAnimationUnblurThresholdPercentage`, recompute, then `Append(UpdateLayout(0x20, 2), r)`. `handleBlurProgressEvent:` (0x1c7638748): `_isBlurring = !(progress == 1)`, recompute, UpdateLayout(0x20,2). `handleSceneReadyEvent:` (0x1c763894c): recompute, UpdateLayout(0x20,2).
* `handleTransitionEvent:` (0x1c7638b30): if ended and no transition modifier: `_dropTransitionFromAppLayout = [event fromAppLayout]`, `_transitionModifier = [[SBContinuousExposeDragAndDropToAppTransitionSwitcherModifier alloc] initWithTransitionID:]` added as child; else if the event is gesture-initiated and there is no transition modifier: `setState:1`. Then `_appLayout = [event toAppLayout]`, super, recompute. `completesWhenChildrenComplete` = `_transitionModifier != nil`.
* queries: `frameForIndex:` (after the drop a layout sharing items with the pre-drop layout takes the frame of `_appLayout`), `frameForLayoutRole:inAppLayout:withBounds:` (0x1c76392f4; three branches: (A) incoming layout while dragging with dropAction 4/5 and no side item: the primary window is narrowed by `2*draggingPlatterSideActivationGutterPadding + platterWidth` (rounded for the screen scale) and shifted when the platter is on the leading side (RTL aware); (B) layouts of the initial group keep their initial roles/frames while dragging; (C) after the drop layouts that share items with the pre-drop layout and with the new layout are placed with the role of the first pre-drop item that is not in the new layout, in a bounds rect of their own frame size),
  `isLayoutRoleBlurred:inAppLayout:` (`_appLayout`: ended -> NO for the dragged scene's role, else `_isBlurred`), `dimmingAlphaForLayoutRole:` (0.5 for the would-be-evicted item while a drop action is set), `scaleForIndex:` (0.98 for `_appLayout` while "pushed in" and not ended), `cornerRadiiForIndex:` (display or stage corner radius / scale for the initial and pre-drop groups), `animationAttributesForLayoutElement:` (resize animation settings, updateMode 3), `isLayoutRoleMatchMovedToScene:` (`_isResizing && [_appLayout itemForLayoutRole:role] != nil`), `resizeProgressNotificationsForLayoutRole:` (adds {0, unblur threshold, 1}), `isResizeGrabberVisibleForAppLayout:` (NO for `_appLayout`), `isContentStatusBarVisibleForIndex:` (`_transitionModifier != nil`), `backgroundOpacityForIndex:` (0 when not chamois), `switcherHitTestsAsOpaque` YES.

### _SBContinuousExposeWindowDragContentSwitcherModifier (SBSwitcherModifier, `_selectedDisplayItem +0x60`)
init 0x1c762a3b0: children `SBContinuousExposeWindowDragSwitcherModifier initWithGestureID:initialAppLayout:selectedDisplayItem:` (level 0), `SBFullScreenContinuousExposeSwitcherModifier initWithFullScreenAppLayout:initialAppLayout` with tap flags NO (level 1), `SBAppSwitcherContinuousExposeSwitcherModifier new` with tap flags NO (level 2); `adjustedAppLayoutsForAppLayouts:` = layouts containing `_selectedDisplayItem` first.
Wiring: the Root's `gestureModifierForGestureEvent:` returns `G1C_NewDndRoot(3, _currentAppLayout)` for gesture type 7 (item 2); the 16.0 pending-eviction root is simply not created.


---------------------------------------------------------------------------------------------------

## 1d. Window drag family: SBContinuousExposeWindowDragSwitcherModifier, ...DestinationSwitcherModifier, ...RootSwitcherModifier, event size field   **DONE** (Destination = UNSURE: composition over the 16.0 algorithm)

Method used: class-by-class size/structure diff of 160 vs 162 (`sizes.py`), then symbolic decode (`dec.py`) and raw reading of every changed or new method. Design: **BP162 subclasses of the 16.0 classes**
(`BP162ContinuousExposeWindowDragSwitcherModifier`, `...DestinationSwitcherModifier`, `...RootSwitcherModifier`); only the changed and new methods are overridden, the 16.0 ivars are read by name
(`_location`, `_anchorPoint`, ...; no offsets) and the new 16.2 ivars are added with `class_addIvar` (`_bp_sizeOfSelectedDisplayItem`, `_bp_dragBeganInOtherSwitcher`, `_bp_dragBeganInAnyStrip`, `_bp_dragBeganOnAnyStage`).
Constants read from 162: `SBInvalidPoint = {DBL_MAX, DBL_MAX}` (0x1c7a92f20), fling threshold 2500 pt/s (0x1c7a91d40), drag scale 0.6 (0x1c7a90d98), velocity projection 0.15 (0x1c7a90d70).

### Drag modifier (superclass SBGestureSwitcherModifier; 16.0 had `_translation`, 16.2 `_sizeOfSelectedDisplayItem` and three flags)
| method (162 addr) | behaviour implemented |
|---|---|
| `initWithGestureID:initialAppLayout:selectedDisplayItem:` 0x1c76092bc | super `initWithGestureID:`, both anchors = SBInvalidPoint, creates the BP162 destination (`initWithSelectedDisplayItem:initialAppLayout:delegate:self`) and adds it as child |
| `handleGestureEvent:` 0x1c7609578 | `_location` = event location; `_gestureWasCanceled = (destination.proposedDestination == 0)`. Phase 1: size from `event.sizeOfSelectedDisplayItem`; `_dragBeganInOtherSwitcher = draggedLayout.preferredDisplayOrdinal != displayOrdinal` (draggedLayout from `draggingAppLayoutsForContinuousExposeWindowDrag`); `_dragBeganInAnyStrip = event.isDraggingFromContinuousExposeStrips`, `_dragBeganOnAnyStage = !that`; anchor = `locationInSelectedDisplayItem / frame size` (frame = the other display's size when the drag began elsewhere); appends `UpdateLayout(2,2)` then `UpdateLayout(8,3)`. Phase 3: cancelled -> perform transition activating the initial layout (gesture initiated); otherwise the proposed layout; a fling (velocity.y > 2500 and > abs(velocity.x)) whose bottom edge passes `maximumWindowHeightWithDock + screenEdgePadding` removes the dragged window (layout without it, or the home layout when nothing is left); else `appLayoutByBringingItemToFront:` ; strips presentation response `(0,1)` when `continuousExposeStripProgress != 0` and the final layout no longer contains the item |
| `scaleForIndex:` 0x1c760a4b4 | selected layout with valid anchor: from a strip -> 0.6 if any proposed layout contains the item else `chamoisLayoutAttributes.stripCardScale`; from a stage -> `began-in-other-switcher ? (inProposed ? 0.6 : 1.0) : (inProposed ? 1.0 : 0.6)` when any proposed layout holds the item, else `stripCardScale`; other layouts: super |
| `frameForIndex:` 0x1c760a1e0 | size = `_sizeOfSelectedDisplayItem` when (began in other switcher and any proposed holds item and the destination's proposed layout does not), else the calculator frame of the item in (proposed layout or current layout); size 0 -> super's size; result = `UIRectCenteredAboutPoint(SBRectWithSize(size), _location)` |
| `preferredCenterForSelectedItemInDestinationModifier:` 0x1c7609494 | `_location + size*scale*(0.5 - anchor)`; plain `_location` when the layout is not in `appLayouts` |
| `shouldUseAnchorPointToPinLayoutRolesToSpace:` (new) | NO for the selected layout, else super |
| `shouldPinLayoutRolesToSpace:` | YES for the selected layout with a valid anchor, else super |
| `frameForLayoutRole:inAppLayout:withBounds:` / `opacityForLayoutRole:...` (new) | selected layout: bounds / 1.0; others super |
| `visibleAppLayouts` (new) | super set plus the layout containing the selected item |
| `perspectiveAngleForAppLayout:` | selected layout: 0 if any proposed layout holds it, else `stripTiltAngle` negated for RTL; others super |
| `animationAttributesForLayoutElement:` | dragged app layout: `layoutSettings` = new `SBFFluidBehaviorSettings` with tracking damping/response copied from `medusaSettings.resizeAnimationSettings`, `positionSettings` = `windowDragAnimationSettings`; everything else = plain super (the 16.0 `updateMode 3` moved to the root) |
| `continuousExposeStripProgress`, `appLayoutOnContinuousExposeStage`, `appLayoutContainingAppLayout:`, `isSwitcherWindowVisible`, `_anyItemExceedsWidthThresholdToHideStrip` (= `!overlappingModel(proposed).isContinuousExposeStripVisible`), `_anyProposedAppLayoutContainsSelectedDisplayItem` | as in the code |

UNSURE: the home-fling branch and the anchor for drags that began on another display (an internal helper at 0x1c7609790 scales the in-item location; reconstructed as location / other-display size); `phase 3` order of the "strip hide" response.

### Event field and its producer
`SBContinuousExposeWindowDragModifierEvent.sizeOfSelectedDisplayItem` is added with associated storage (copied in `copyWithZone:`). Producer in 162: `-[SBFluidSwitcherGestureWorkspaceTransaction _currentGestureEventForGesture:]` (0x1c74aef3c) copies `[transaction sizeOfSelectedDisplayItem]` into the event; the 16.0 transaction has no such property, so the hook only fills it when the transaction answers (else CGSizeZero, which the drag modifier turns into "use the layout's own size" = the single-display behaviour).

### Destination (UNSURE)
`handleGestureEvent:` is 634 instructions in 162 against 500 in 160 and the 16.2 form no longer uses `translationInContainerView`. The reconstruction does not duplicate the 160 decision logic (cancel zone, `maximumNumberOfAppsOnStage` eviction, `rejectDropsWhenStageIsFull`, `appLayoutByDraggingItem:...`, destinations 0..3): the 16.0 algorithm already implements the same tree, so the subclass calls super and adds the 16.2 deltas: phase 1 stores `_initialSelectedDisplayItemLayoutAttributes` and `_dragBeganInOtherSwitcher`; every event compares the proposed layout with `_lastAppLayoutForStripCalculation` and, when it changed, appends `SBInvalidateContinuousExposeIdentifiersEventResponse(from: last, to: proposed, animated: YES)` (type 40 here). `_widthThresholdToHideStrips` = `overlappingModel(proposed).widthThresholdToHideStrip` (DM6). `_frameForSelectedDisplayItem` / `_appLayoutByAddingItem:` keep the 16.0 bodies; they use `attributesByModifyingCenter:` (absolute) and rely on the data layer (DM3/DM4) converting to `normalizedCenter`/`attributedSize`. Check on device: dragging a window out of the stage into the strip and back; the strip must open/close at the same x as 16.2.

### Root
`initWithStartingEnvironmentMode:initialAppLayout:` (0x1c7460f98), `gestureChildModifierForGestureEvent:activeTransitionModifier:` (0x1c7461188: `SBFilteringSwitcherModifier initWithAppLayouts:@[selectedAppLayout] modifier:[_SBContinuousExposeWindowDragContentSwitcherModifier ...]`), `handleGestureEvent:` (phase 1 -> `SBInvalidateAdjustedAppLayoutsSwitcherEventResponse`), `handleTransitionEvent:` (initial layout = toAppLayout or the home layout of the event's display; gesture modifier `state = 1` at phase 1, root `state = 1` at phase 3), `animationAttributesForLayoutElement:` (non-selected elements: `resizeAnimationSettings` + `updateMode 3`), `appLayoutsToResignActive` = `@{}`.

## 1f. SBHomeScreenContinuousExposeSwitcherModifier   **DONE** (UNSURE: the peek-end response transformer)
`BP162HomeScreenContinuousExposeSwitcherModifier` (subclass of the 16.0 class): `init` additionally creates `SBStripContinuousExposeSwitcherModifier` into `_stripModifier` **only when that class exists** (the FullScreen/Strip package or a real 16.2 build), `continuousExposeStripProgress` = 0.0, `isResizeGrabberVisibleForAppLayout:` = NO. `responseForProposedChildResponse:childModifier:event:` (0x1c77f393c): for transition events whose `fromPeekConfiguration` is valid and `toPeekConfiguration` is not, type-31 (perform transition) responses coming from a peek transition modifier have their app layout filtered with `appLayoutWithItemsPassingTest:` (block 0x1c77f3e04). The block's predicate was not resolved; the override passes the response through. Removed-in-162 methods (`appLayoutsToCacheSnapshots`, `dimmingAlphaForLayoutRole:...`, `scrollViewContentOffset`, `topMostLayoutElements`) stay as the 16.0 versions, because they are answered by the strip child only when it exists.

## 1b. SBInlineAppExposeContinuousExposeSwitcherModifier   **DONE** (UNSURE: `frameForLayoutRole:`/`scaleForLayoutRole:`/`homeScreenDimmingAlpha` keep the 16.0 maths; the reopen button has no view in 16.0)
`BP162InlineAppExposeContinuousExposeSwitcherModifier` (subclass). Implemented from the decode: `handleTapAppLayoutEvent:` (0x1c7686a58: unhandled tap on the active layout -> `requestForTapAppLayoutEvent:`; on another layout -> request with `appLayout` = item brought to front inside `appLayoutContainingAppLayout:`, `activatingDisplayItem`; event handled with reason "I"), `handleTapAppLayoutHeaderEvent:` (new, 0x1c7686bf8: multi-window item of the expose bundle: active layout -> `SBPulseDisplayItemSwitcherModifier` child at level 3, other layout -> activation request; item of another bundle -> request with `source 3` + `bundleIdentifierForAppExpose`), `handleTransitionEvent:` (phase 2 and differing expose bundle IDs -> reopen-button presence response + `SBInvalidateReopenButtonTextSwitcherEventResponse`), `handleInsertionEvent:`, `handleTimerEvent:` (reason `SBInlineAppExposeContinuousExposeSwitcherModifierTimerEventReason` -> showing = YES, `UpdateLayout(8,3)`), `titleAndIconOpacityForIndex:` (active layout 0.0, others 1.0; this settles the "UNSURE inversion" of group1b), `isFocusEnabledForAppLayout:` (= active layout), `handleHighlightEvent:` (ignores handled events), `_isLayoutRoleOccluded:` (adds `isItemCoveredByFullyOccludedPeekingItem:`), RTL mirroring of `frameForIndex:` (the grid maths is identical to 16.0, 16.2 only mirrors for `userInterfaceLayoutDirection == RTL`), the button accessors (`numberOfHiddenAppLayouts` etc. as associated state; the button never shows when `numberOfHiddenAppLayoutsForBundleIdentifier:` is 0 or unanswered).

## 1a. SBAppSwitcherContinuousExposeSwitcherModifier   **DONE** (behaviour); pile layout UNSURE and OFF by default
`BP162AppSwitcherContinuousExposeSwitcherModifier` (subclass; ivars `_bp_handlesTap`, `_bp_handlesHeaderTap`, `_bp_ongoingRemovals`, `_bp_eventGen`). Behaviour layer decoded and implemented: `init` (flags YES, `SBDefaultImplementationsSwitcherModifier` child at level 1), `handleEvent:` (generation counter), `handleTapAppLayoutEvent:` (gated by the flag; perform transition activating the layout; handled with reason "App Switcher Continuous Expose"), `handleTapAppLayoutHeaderEvent:` (multi-window item -> request `source 3` + expose bundle; otherwise pulse child level 3), `handleTapOutsideToDismissEvent:` (`requestForActivatingHomeScreen`), `handleRemovalEvent:` (counts phases 1/2; when the last window is gone and no removal is pending -> home with `autoPIPDisabled`), `appLayoutsToResignActive` = `@{ @3: set(appLayouts) }` (constant 3 read from the `NSConstantIntegerNumber` at 0x1e18f9ff0), the tap flags, `isResizeGrabberVisibleForAppLayout:` NO, `isSwitcherWindowVisible` YES.
Pile layout (`buildLayoutCalculationsForCache:` 0x1c7812acc, 516 instructions) reconstructed with an own cache (associated dictionary keyed by a token of generation counts + orientation + bounds + event generation), not with `SBSwitcherLayoutCalculationsCache`: card height = `(switcherViewBounds.h - floatingDockHeight - screenEdgePadding - statusBarHeight - 2*vEdge - vInter*(rows-1)) / rows` rounded for scale; piles fill rows alternately (`index % rows`), a column advances by its widest pile + `switcherHorizontalInterItemSpacing`; card k of a pile has scale `cardH/size.h - 0.01*k` (constant 0x1c7a916c0) and is offset by `k * switcherPileCardMinimumPeekAmount`; frames are stored unscaled and centred, the scale separately; `frameForIndex:` applies the scroll offset only; `opacityForLayoutRole:...` is 1 for `indexInPile < numberOfVisibleItemsPerGroup`, else 0; `_defaultCardScale` = card height / container height. Switch: `G1C_PILES_DEFAULT` (compile time, default 0). With 0 the 16.0 grid stays. UNSURE: direction of the peek offset, RTL cursor signs (the decode shows both signs of `hEdge`/`hInter` selected by `isRTLEnabled`; reconstructed as a mirror), the exact start of the column cursor; `adjustedContinuousExposeIdentifiersIn{Switcher,Strip}...` (118 and 579 instructions) are identity here, the 16.2 versions order the "forward" pile of a cycle first and are only consumed by the Slide/Override modifiers, which fall back to the plain identifiers.

## 2 / 2b. The Root: factories, gesture mapping, peek child, slide/cycle spawning   **DONE** (UNSURE: floor state carry-over)
All hooks are in `%group G1C_Root` on `SBContinuousExposeRootSwitcherModifier` (16.0 class; the 16.2 ivars `_effectiveAppLayoutOnStage`, `_isStripTonguePresented`, `_initialFloorModifierForContinuousExposeWindowDrag` are associated objects because the controller allocates the class).

| 162 method | what the hook does |
|---|---|
| `floorModifierForTransitionEvent:` 0x1c78180e8 | by `toEnvironmentMode`: 1 -> reuse the Home floor or `G1C_NewHomeModifier()`; 2 -> `multitaskingModifier` (no expose bundle) or reuse / new `SBAppExposeContinuousExposeSwitcherModifier initWithBundleIdentifier:`; 3 without expose bundle -> reuse the FullScreen floor when `fullScreenAppLayout isEqual:toAppLayout`, else new FullScreen (`initWithFullScreenAppLayout:`) with `highlightedByTouch/HoverAppLayouts` copied from the old FullScreen floor; 3 with expose bundle -> reuse the Inline floor with the same `appExposeBundleIdentifier`, else the BP162 inline class. Falls back to `%orig` whenever a needed class is missing |
| `floorModifierForGestureEvent:` 0x1c78183f0 (new) | window-drag events only: phase 1 stores the current floor; phase 2/3 with the proposed layout holding the dragged window -> FullScreen floor for the proposed layout (kept if already FullScreen); not holding it -> restores the stored floor (`setState:0`); phase 3 clears the stored floor |
| `gestureModifierForGestureEvent:` 0x1c7818d78 | type 3 -> `G1C_NewGridSwipeUpRoot(_effectiveEnvironmentMode, AppSwitcher modifier)`; 7 -> DnD root (mode 3, `_currentAppLayout`); 9 -> window-drag root (`initWithStartingEnvironmentMode:initialAppLayout:`, `_currentAppLayout` or the home layout of the display); type 1 root also gets `setEnsuresSelectedAppLayoutUsesAnchorPointSpacePinning:YES` when it has the setter; 10, 11, 12 unchanged |
| `handleGestureEvent:` | for window-drag events at phase != 1 additionally `_updateFloorModifierWithGestureEvent:` (16.0 already has the method) |
| `handleEvent:` 0x1c7819254 | keeps `_effectiveAppLayoutOnStage` (phase table of the decode); the Invalidate response of 162 is NOT emitted because the 16.0 controller calls `_updateContinuousExposeIdentifiers...` inline |
| `handleTransitionEvent:` 0x1c7819470 | peek child (`G1C_NewPeekModifier`, level 2, key `SBContinuousExposePeekModifierKey`) when `phase == 2 \|\| !animated`, valid `toPeekConfiguration` and no such child |
| `handleContinuousExposeIdentifiersChangedEvent:` 0x1c78195b8 | replaced (calls the base class, not the 16.0 body): animated, mode 3, both layouts -> Slide(direction 1) for ids that left the strip, Slide(direction 0) for ids that entered it (level 5), plus the Cycle modifier (level 5) when from/to share an identifier |
| `transitionModifierForMainTransitionEvent:` 0x1c781859c | `%orig`, then: windowing-mode-change events -> nil; animated, non-gesture events only: (2,3) SwitcherToApp(0), (3,2) SwitcherToApp(1), (2,1) / (1,2) CEToHome with a copy of `multitaskingModifier`, (3,3) the BP162 AppToApp with the three event flags. All pulse / window commit / decline / delete / entity-removal cases stay `%orig` (identical) |
| `appLayoutOnContinuousExposeStage`, `handleContinuousExposeStripEdgeProtectTongueEvent:` (stores the flag, `UpdateLayout(4,2)`), `continuousExposeStripTongueAttributes` (`{presented ? 2 : 1, RTL ? 2 : 1}`), `shouldUseWallpaperGradientTreatment` YES, `shouldScaleContentToFillBoundsAtIndex:` NO, `shouldUseNonuniformSnapshotScalingForLayoutRole:...` NO | added (`%new`) |

Not done on purpose: removing the 16.0 Root helpers (`adjustedAppLayoutsForAppLayouts:`, `_adjustedAppLayoutsForAppLayouts:`, `appLayoutsForContinuousExposeIdentifier:`, `adjustedContinuousExposeIdentifiersForIdentifiers:`): they are only dead code once the Strip package answers the same queries from the Strip modifier; with the 16.0 FullScreen modifier (strip inlined) they are still needed.
Coupling with the FullScreen/Strip port: the factories need `initWithFullScreenAppLayout:`, `fullScreenAppLayout`, `highlightedByTouch/HoverAppLayouts` (+ setters), `setHandlesTapAppLayoutEvents:`/`...HeaderEvents:` and the `appLayoutOnContinuousExposeStage` query; all exist on the 16.0 FullScreen class except the two handles setters (provided by the Strip package, or inert: the content modifiers check `respondsToSelector:`).

## Requirements on the data layer (what this package needs from group2 / group2b)
| id | need | used by |
|---|---|---|
| DM1 | `-[SBDisplayItemLayoutAttributes sizeInBounds:defaultSize:screenEdgePadding:]` (returns absolute size from `attributedSize`) | DnD, destination, AppToApp (`isLayoutRoleMatchMovedToScene:`) |
| DM2 | `centerInBounds:` (absolute centre from `normalizedCenter`) | DnD, destination |
| DM3 | `attributesByModifyingNormalizedCenter:` / absolute-centre shim on 16.0 attributes | destination (`_appLayoutByAddingItem:`), DnD |
| DM4 | `SBDisplayItemAttributedSizeInfer` + `attributesByModifyingAttributedSize:` | DnD drop sizing, destination |
| DM5 | `SBSwitcherChamoisLayoutAttributes`: `stripWidth`, `stripCardScale`, `stripTiltAngle`, `screenEdgePadding`, `defaultWindowSize`, `maximumWindowHeightWithDock`, `switcher{Horizontal,Vertical}{Edge,InterItem}Spacing`, `switcherPileCardMinimumPeekAmount` | drag modifier, AppSwitcher piles |
| DM6 | `SBChamoisOverlappingModel`: `widthThresholdToHideStrip`, `stageArea`, `compactedBoundingBox`, `isContinuousExposeStripVisible`, `isItemCoveredByFullyOccludedPeekingItem:`, `centerForItem:` | destination, drag modifier, inline expose, AppSwitcher |
| DM7 | the "extended protocols" (group2 section 0) must route these 16.2-only queries through the chain: `draggingAppLayoutsForContinuousExposeWindowDrag`, `proposedAppLayoutsForContinuousExposeWindowDrag`, `proposedAppLayoutForContinuousExposeWindowDrag`, `appLayoutOnContinuousExposeStage`, `continuousExposeStripProgress`, `isRTLEnabled`, `displayOrdinal`, `overlappingModelForAppLayout:`, `isResizeGrabberVisibleForAppLayout:`, `numberOfHiddenAppLayoutsForBundleIdentifier:`, `frameForContinuousExposePeekingDisplayItem:...`; the VC answers the three drag queries (`dragging` = the layout(s) being dragged, `proposed(s)` = the destination modifier's proposed layout) |
| DM8 | ordering: group2's `%init(G2B)` of `_updateContinuousExposeIdentifiers...` before `%init(G1C_VCIds)`; the FullScreen/Strip port API listed under section 2 |

## Install order
1. group2 / group2b data layer (DM1..DM7), 2. group1b setup (`G1B_Setup`), 3. `G1C_Setup()` (this file): event predicates -> grid swipe -> transactions -> ids/slide -> AppToApp -> SwitcherToApp -> peek -> DnD -> window-drag content -> AppSwitcher -> floors -> window-drag family -> window-drag event hooks -> Root hooks -> reveal -> Cycle -> VC ids. **Do not enable the group1b opt-in `group1b.apptoapp`** together with this file (it patches the 16.0 AppToApp class, which the Root now replaces).


## 5.x Producers of the grabber and orientation responses   **DONE**
Consumers are in group1b (1.7, 1.10); the producers are in `G1C_Producers`:
* Grabber (response type 39): `-[SBFullScreenContinuousExposeSwitcherModifier handlePointerCrossedDisplayBoundaryEvent:]` (0x1c75c5144): `r = [super ...]`; when `event.edge == _continuousExposeStripEdge` (0x1c75c5520: `userInterfaceLayoutDirection == RTL ? 2 : 0`) and `BSFloatIsZero(continuousExposeStripProgress)`: `event.direction == 1` -> `initForInitialPresentation:YES`, `== 0` -> `NO`, any other direction -> nothing. Event type 38 reaches it through the 1b `_handleEvent:` hook. Added with `%new` to the 16.0 FullScreen class.
* Orientation (response type 38): `-[SBItemResizeGestureSwitcherModifier _responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:]` (0x1c76bf0bc, present in both builds): item = `[_currentAppLayout itemForLayoutRole:_selectedLayoutRole]`; when `([[self layoutRestrictionInfoForItem:item] layoutRestrictions] & 0xa) == 2` the response gets a child `SBSetInterfaceOrientationFromUserResizingEventResponse initWithDisplayItem:desiredContentOrientation:` with orientation `size.width > size.height ? 3 : 1`. UNSURE: the meaning of restriction bits 0xa/2 on 16.0 (the bitmask is read from the same class in both builds; check that a resize-restricted app, e.g. an iPhone-only app, rotates its content while the window is dragged wider than tall).

---------------------------------------------------------------------------------------------------

## SUMMARY

### What is complete
All five parts of the brief have a reconstruction in `group1c-reconstruct.hooks.m` (3511 lines, `G1C_Setup()` at the end) and a section here.

| item | piece | tag |
|---|---|---|
| 1a | AppSwitcherCE: behaviour layer (tap, header tap, tap outside, removal, flags, resign-active, pile opacity) | DONE |
| 1a | AppSwitcherCE: pile layout / frames / scales / fitted size | UNSURE:direction of the card peek offset, RTL cursor, start of the column cursor; compile-time switch `G1C_PILES_DEFAULT` (0) |
| 1a | `adjustedContinuousExposeIdentifiersIn{Switcher,Strip}...` | UNSURE:identity here; compare the Slide animation of a pile that moves to the front |
| 1b | InlineAppExpose (tap, header tap, transition, insertion, timer, title opacity, focus, RTL mirror, occlusion, reopen button state) | DONE; UNSURE:`frameForLayoutRole:`, `scaleForLayoutRole:`, `homeScreenDimmingAlpha` use the 16.0 maths |
| 1d | WindowDrag modifier + event size field + Root | DONE; UNSURE:cross-display anchor scaling, fling-to-home threshold use |
| 1d | WindowDragDestination | UNSURE:composition over the 16.0 algorithm; Invalidate emission condition |
| 1f | HomeScreen | DONE; UNSURE:peek-end response transformer (passthrough) |
| 2/2b | Root factories (floor transition / gesture), gesture mapping, peek child, ids-changed (slide + cycle), transition post-processing, tongue, stage bookkeeping | DONE; UNSURE:floor state carry-over in `floorModifierForGestureEvent:` |
| 3 | peek family | DONE (UNSURE: producer of a valid peek configuration over Stage Manager) |
| 4 | app drag and drop family | DONE |
| 5a..5f | grid swipe-up, gesture transactions, ids pipeline, cycle, reveal / overflow, AppToApp | DONE (earlier sessions, with their own UNSURE lists) |
| 5.x | grabber and orientation producers | DONE; UNSURE:restriction bits |

### Confidence
High for everything tagged DONE whose logic is a direct decode (taps, requests, queries, constants, Root mapping, Cycle / Slide spawning). Medium for composition-based pieces (Destination) and for the pile arithmetic. Nothing was compiled or run: the environment has no Foundation / UIKit headers and no device. The code follows the brief's rules (ivars by name, guarded private calls, nil-safe, `%orig` on its own line, `objc_msgSend` casts, pragmas for unused statics); the first build on a machine with the SDK may still need small syntax fixes.

### Install order
group2 / group2b data layer (DM1..DM7) -> group1b `G1B_Setup()` (without the opt-in `group1b.apptoapp`) -> `G1C_Setup()` (order fixed in the trailer; `%init(G1C_VCIds)` last, after `%init(G2B)`).

### Open questions (to check on a device)
1. `proposedAppLayout(s)ForContinuousExposeWindowDrag` / `draggingAppLayoutsForContinuousExposeWindowDrag` must really be answered through the 16.0 query chain (DM7); without them the drag falls back to the single-display behaviour (`initial layout` as the dragged layout, destination layout as proposed), which is correct for one display.
2. Whether the 16.0 VC lets `SBItemResizeGestureSwitcherModifier` responses with child responses through (`addChildResponse:` order).
3. Pile layout on or off (`G1C_PILES_DEFAULT`): compare card positions against a 16.2 device; the 16.0 scroll maths (`contentOffsetForIndex:alignment:`) reads our frames.
4. Whether `SBStripContinuousExposeSwitcherModifier` exists at run time (FullScreen/Strip package): the HomeScreen subclass and the Root's `appLayoutOnContinuousExposeStage` rely on it only when present.
5. The two internal helpers not resolved by the tracer (0x1c7609790 anchor scaling, 0x1c77f3e04 predicate block) are the only places where behaviour was reconstructed instead of decoded.
