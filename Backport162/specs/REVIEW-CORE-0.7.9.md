# REVIEW-CORE-0.7.9 - code review of the Stage Manager core against 16.0 (20A8372) and 16.2 (20C65)

Scope: G1B.x, G1C.x, G1D.x, G2.x, G2B.m, G2C.x, G2E.x, G2F.x, G2H.x, G2I.x, G3C.x, G1BKit.h at head 1ec6584 (+ later commits of other agents, all re-read where they touched
these files). Method: independent code review of the sources against the two binaries (annotated disassembly, selector-sequence diffs, caller diffs). Device logs of old builds
were NOT used as evidence. Nothing here was run on a device; "verified" means: read in the 16.2 disassembly and compared with the port line by line.

## 0. Result in one screen

* Coverage of the WORKLIST (16.0 -> 16.2 logic-changed methods) in the core classes: **246 methods in 38 classes**. 193 have a direct hit in the sources (hook, added method or
  replaced IMP with the 16.2 body). The other 53 were each diffed by hand: 12 runtime-only (`.cxx_destruct`, protobuf, description), 7 ported under another name/file, 15 proven
  equivalent (rename, assertion, logging, allocation order), **19 NOT ported** (1 of them fixed in this review). So **92 % of the 234 logic methods are ported or equivalent; the 18
  open ones are listed in 2.1 / 4** (12 of them cosmetic or LOW).
* **The WORKLIST itself is incomplete** (section 5): it only diffed a hand-picked set of 66 classes. A size sweep of every other 16.0/16.2 method pair in the Stage Manager related
  class families found 463 more methods whose size changed. Triage of the ones in the core area found **four real defects, all fixed (section 3)**, plus the open items of section 4.
* Fixed (5 commits, all pushed, kill switches + README rows where they change behaviour):
  `g1c_modelmap`, `g1d_scenehandle`, `g1d_failgestures`, VC `_scrollToAppLayout` (with `g1c_piles`), stale comment (65690f3).
* **Open HIGH**: none that I could prove from the code alone. Two defects that I rate HIGH-impact but could only document, because the fix cannot be done locally and safely:
  H1 the base gesture workspace transaction is not multi-display aware (partial port), H2 the 16.0 inline ids updates still run next to the 16.2 invalidate response.

## 1. What was reviewed, and how

1. Every hook / added method / class of the owned files against the 16.2 method it ports and the 16.0 method it replaces. Read line by line: G1B, G1C (except 3330-3675 strip
   modifier class body and 4700-5000 AppSwitcher tail, which were read in the earlier pass only), G1D (except 1230-1530 tongue/touch rules and 2300-2540 trace/emptydismiss, spot-read),
   G2C, G2E, G2F, G2H, G2I, G3C, G2.x (except 930-1290, the overlapping controller port, checked against the 16.2 algorithm only where it is called), G2B.m (1596-1860 line by line; 120-560, 960-1100
   and 1860-2585 spot-read).
2. Bug-class hunt (a)-(i) of the brief with greps over all owned files (main display lookups, `sharedInstance`, unguarded `objc_msgSend` casts, timers, caches) and with caller diffs
   16.0 vs 16.2 of the global lookups (`activeDisplayWindowScene`, `mainDisplaySceneManager`, `sharedInstance`...). No unguarded wrong-cast `objc_msgSend`, no enumeration-while-mutating,
   no timer that outlives a display in the owned files (the `dispatch_after` blocks of G2F/G2H/G2I/G3C only run when logging is on or hold weak refs).
3. Systematic gap search outside the WORKLIST: every same-named 16.0/16.2 method pair in the Switcher/Fluid/Chamois/DisplayItem/AppLayout/ContinuousExpose/Medusa/LayoutState/
   MainDisplay/Home/PIP/Peek/FullScreen/Floating/Deck/ItemContainer/Overlap/SceneHandle/Transaction families with a different instruction count, minus WORKLIST methods, minus methods the
   sources already mention (scratchpad `rev/unref.txt`). 176 are not mentioned in any source; the ones in the core area were diffed (selector sequence) and are classified below.

## 2. Coverage matrix (WORKLIST methods of the core classes)

"No direct hit" = no definition / replaced IMP / selector string with that name in any source file (`scratchpad/rev/cov2.py`). Every such method was then diffed by hand.

| Class | WORKLIST | no direct hit | what those are |
|---|---|---|---|
| SBFluidSwitcherViewController | 60 | 22 | 1 runtime, 9 equivalent, 11 not ported + `_scrollToAppLayout:` (fixed): table 2.1 |
| SBFullScreenContinuousExposeSwitcherModifier | 37 | 1 | `.cxx_destruct` |
| SBAppSwitcherContinuousExposeSwitcherModifier | 18 | 0 | |
| SBContinuousExposeWindowDragSwitcherModifier | 11 | 0 | |
| SBInlineAppExposeContinuousExposeSwitcherModifier | 11 | 0 | |
| SBFluidSwitcherItemContainer | 9 | 3 | NOT ported: `_addPageView` 0x1c72ced9c, `initWithCoder:` 0x1c75e101c, `didUpdateFocusInContext:` 0x1c75e2f2c (LOW, section 4) |
| SBContinuousExposeRootSwitcherModifier | 9 | 1 | `.cxx_destruct` |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | 8 | 1 | `.cxx_destruct` |
| SBContinuousExposeIdentifierSlideModifier | 6 | 1 | `.cxx_destruct` |
| SBSwitcherChamoisSettings | 6 | 5 | ported in G2.x under the long selector (`layoutAttributesForContainerBounds:...`, `_shouldPreferDockHiddenForWindowScene:`, `_shouldPreferStripHiddenForWindowScene:interfaceOrientation:`); `.cxx_destruct`; `settingsControllerModule` (debug settings UI, not ported) |
| SBContinuousExposeAppToAppModifier, ...WindowDragRootSwitcherModifier, ...CycleGroupAppLayouts, SBHomeScreenContinuousExposeSwitcherModifier, SBRevealContinuousExposeStripsGestureModifier, ...StripOverflowRoot, SBContinuousExposeWindowDragModifierEvent, SBDisplayItemLayoutGrid, _SBDisplayItemFixedAspectGrid, SBSwitcherController (2), SBSwitcherChamoisLayoutAttributes (2), SBFluidSwitcherGestureManager (2), SBLayoutState(SBAppLayoutConversion) | 25 | 0 | all ported |
| SBMedusaDecoratedDeviceApplicationSceneViewController | 5 | 2 | `layoutStateTransitionCoordinator:...` ported in G1B/G1D/G3/G4B; `viewWillLayoutSubviews`: only `contentInterfaceOrientation` -> `contentOrientation` (UIKit-side rename) |
| SBDisplayItemLayoutAttributesCalculator | 5 | 1 | `frameForLayoutRole:...containerOrientation:window...` is in G1D (long selector) |
| SBAppLayout | 5 | 2 | equivalent: `preferredDisplayIdentity` (4.LOW), `appLayoutByModifyingHiddenState:` (alloc order) |
| SBAppLayoutOverlappingModelCacheKey | 4 | 1 | `.cxx_destruct` |
| SBFluidSwitcherItemContainerFooterView | 3 | 2 | NOT ported: `_handleTapGestureRecognizer:` 0x1c7587b90, `_makeSubtitleLabel` 0x1c7587ff4 (LOW) |
| SBDisplayItem | 2 | 1 | description builder |
| SBRevealContinuousExposeStripOverflowGestureModifier | 2 | 1 | equivalent: `_finalScaleForFullScreenAppLayout` (`_overlappingModelForAppLayout:` -> `overlappingModelForAppLayout:`; the 16.0 private copy is instruction-identical to the 16.2 shared body) |
| SBContinuousExposeIdentifiersChangedModifierEvent | 2 | 1 | `.cxx_destruct` |
| SBChamoisOverlappingModel / SBChamoisOverlappingController | 2 / 1 | 1 / 1 | `.cxx_destruct`; `_snapPositionToNearestEdgesIfNecessary:draggingItem:` identical except bs_reverse |
| _SBDisplayItemFlexibleGrid | 2 | 1 | `_gridWidthsForSafeWidth:minimumWidth:` in G2.x (`BP_G2_...`) |
| SBFluidSwitcherItemContainerLayer | 1 | 1 | NOT ported: `setTransform:` 0x1c75e5304 (mirrors the transform to the page view for pointer hit testing; LOW) |
| SBDisplayItemLayoutAttributes | 13 | 2 | protobuf read/write (persistence, not needed) |
| SBMainDisplayLayoutState(SBDisplayItemConversion) | 1 | 1 | `floatingItem` ported in G1B/G1C/G1D/G3C |
| SBSceneLayoutWorkspaceTransaction | 1 | 1 | equivalent: `_runningOnMainRootOrExtendedExternalDisplay` (16.0 already calls the availability function through a pointer, `blraaz`) |

Totals: 246 methods, 53 without a direct hit = 12 runtime-only, 7 ported under another name, 15 equivalent, 19 not ported (1 fixed here).

### 2.1 SBFluidSwitcherViewController - the 22 methods with no direct hit

| Method (16.2 addr) | Verdict | Effect |
|---|---|---|
| `_scrollToAppLayout:animated:alignment:completion:` 0x1c7452ff0 | **was N, FIXED** (G1C, section 3) | scroll target of the app switcher with multi-window apps |
| `prefersDockHidden` 0x1c74379ac, `prefersStripHidden` 0x1c743794c | E (verified: both ask the same defaults/attributes; 16.2 inlines the observer ivars) | none |
| `clickReceivedForHomeGrabberView:` 0x1c743a460 | E (G2B 5e; nothing needs installing) | none |
| `_updateContinuousExposeIdentifiers...` 0x1c7457450 | P (G1C VCIds). Chamois-off early return verified against 0x1c7457450 | see H2 |
| `performKeyboardShortcutAction:` 0x1c743ace4 (377 -> 169) | **partial** | the 16.0 body is kept; G2B replaces the helpers it calls (`_navigateFromFocusedAppWindowSceneToNextScene:matchFocusedApp:`, `_keyboardFocusableLive...`, can-perform) under `g2bkeys`. 16.2 additionally (a) routes the next/previous-window actions straight to the new `_navigate...InForwardDirection:matchFocusedApp:` and (b) has a new action that opens App Expose of the focused app (`bundleIDShowingAppExpose` compare, request source 3). The 16.0 inline cycling code (ids based) still serves the other window-cycling actions. MED/LOW |
| `gestureHandlingModifierRequestsUpdate:` 0x1c7452bdc | **N** | 16.2 sends `[[switcherController gestureManager] handleFluidSwitcherGestureManager:didUpdateGesture:]` (reaches the coordinator broadcast); 16.0 calls `handleGestureDidUpdate:` directly, so modifier-requested updates of a window drag are not broadcast to the neighbouring display. MED (cross-display drag only) |
| `_acquireKeyboardSuppressionAssertionForMode:` 0x1c7459e50 | **N** (spec group2b-reconstruct.md 5.5 still says "waits for group3b") | the assertion goes to the main display's keyboard manager (`mainDisplaySceneManager`, `_isUsingMedusaHostedKeyboardWindow`), 16.2 uses the VC's window scene and `startSuppressingKeyboardWithReason:predicate:displayIdentity:` (0x1c75376dc). Keyboard suppression during switcher gestures of the extended display. MED, owner G3B |
| `_updateAsyncRenderingAndResizesHostedContext` 0x1c745929c | **N** | 16.2 keeps async rendering on while a window of THIS display is being dragged from the other display (`switcherCoordinator draggingAppLayouts containsObject:`), 16.0 does not know the cross-display drag. LOW-MED |
| `_performModifierIconViewVisibilityUpdateResponse:` 0x1c745cd90 | **N** (16.0 additionally tests `_isPerformingMatchMoveToIconView` under Stage Manager) | icon visibility during the match-move of an icon zoom; LOW |
| `_updatePlusButtonPresence` 0x1c74575b8 | N | tint of the plus button (image tint instead of tintColor), cosmetic |
| `_leafAppLayoutInLiveContentOverlaysWithLayoutRole:` 0x1c7439f84 | N | uses the layout state's app layout `leafAppLayoutForRole:` when the overlay list has none; LOW |
| `_updateFloatingDockWindowLevelAssertion` 0x1c745a234 | N | 16.2 builds the dock level assertion with a priority/level (`initWithFloatingDockController:priority:level:reason:`); the port sets the 16.2 level in G1D_DockHidden for the hidden assertion only. LOW |
| `_updateHomeScreenPointerInteractions` 0x1c74583f4 | N | 16.2 no longer tells the data source `setPointerInteractionsEnabled:`, asks `_controlsHomeScreenContents`. LOW |
| `_updateForegroundAppLayoutsList` 0x1c745b368 | N | `_SBFIsMoreForegroundAppsAvailable` gate; LOW |
| `overlayAccessoryViewFrameForIconOverlayView:fullPresented:` 0x1c7451420 | N | uses `containerViewBounds` instead of home/switcher interface orientation; only differs while rotating; LOW |
| `appLayoutByBringingItemToFront:inAppLayout:` 0x1c7438794 | E | 16.2 dropped the "already front" early exit and asserts; same result |
| `underlayAccessoryView:didSelectHeaderForRole:` 0x1c7451034 | E | the event gets `modifierFlags:0`; the port's tap handlers guard `modifierFlags` |
| `_applyRootContentViewBlurRadiusWithCompletion:`, `_orderedViewsForLayoutElement:...`, `_blurItemContainer:...`, `_addVisibleItemContainerForAppLayout:...` | E / cosmetic | animation order, `shouldRasterize`, windowScene init argument (G2B 5f derives it from the delegate) |
| `.cxx_destruct` | R | |

## 3. Defects fixed (one commit each, all pushed to claude/backport162)

| sha | what | why (addresses) |
|---|---|---|
| 65690f3 (committed by the coordinator) | G1C comment | the comment above `G1C_Pip_DidMove` said the 16.2 home/app transition creators 0x1c762c998 / 0x1c750c194 are not ported; they are (G1B_FluidRoot / G1B_HomeFloor). No code change |
| fc6e206 | `g1c_modelmap`: `-[SBSwitcherModifier(SharedModifierUtilities) overlappingModelForAppLayout:]` asks for the model of `appLayoutContainingAppLayout:` | 16.2 0x1c7652fc4 maps the layout through the query chain before asking the calculator (view controller 0x1c7435e54: first unadjusted layout that is or contains it, else the layout itself; WindowDelete 0x1c78e7078 and the window-drag modifiers override it). 16.0 0x1c61c4450 has no mapping and **no caller** in 16.0: the four classes that needed a model had private `_overlappingModelForAppLayout:` copies (0x1c5f1ee28 / 0x1c6141330 / 0x1c61fa2f4 / 0x1c636c1c4, instruction-identical to the 16.2 body, verified by sdiff). Every ported 16.2 caller (FullScreen floor, Strip, Inline, F2S/XB transitions via `G1B_OverlapBBox`, PIP morph `transitionWillBegin`, peek frame, home floor) therefore got the model of the UNMAPPED layout. @try around the mapping query, original on failure. Switch `Backport162.off.g1c_modelmap`. Regression-guard check: for a layout that is itself in `appLayouts` the mapping returns an equal layout, so the cache key and model are unchanged; only layouts that are not a stage entry (leaf, closing window, merged peek layout) change, exactly as in 16.2 |
| 968f1cf | `g1d_scenehandle`: scene handle of a display item looked up on the display that owns it | 16.0 `SBMainSwitcherControllerCoordinator _deviceApplicationSceneHandleForDisplayItem:` 0x1c623fa90 uses `[windowSceneManager activeDisplayWindowScene]`'s scene manager; the data source query `switcherContentController:deviceApplicationSceneHandleForDisplayItem:` 0x1c623fa88 is a tail call into it. Windows of the non-active display had no handle: G2B's auto layout write-back (`BP2B_PreferredSizingPolicy` / supported sizing policies, `supportsCenterWindow` default size, G2B.m 880/976), supported orientations (G2.x 369), home-gesture edge protection (G1D) skipped them. 16.2: owner controller via `_switcherControllerForContentViewController:` (0x1c76d3288), `SBSwitcherController _deviceApplicationSceneHandleForDisplayItem:` 0x1c76065ec, calculator = first handle of any controller (0x1c75a5784 + block 0x1c75a58dc); `applicationForDisplayItem:` 0x1c742fdb0. Switch `Backport162.off.g1d_scenehandle`. Possibly related to OPEN-ISSUES #4 (zoom state) |
| cbdfb2a | `g1d_failgestures`: `failMultitaskingGesturesForReason:` fails every display's gestures | 16.0 0x1c623adb8 only the active display's gesture manager; 16.2 0x1c76ce304 + block 0x1c76ce398 every switcher controller (callers: `setTypingActive:auditToken:`, window-management-style change 0x1c76e2bc4). Switch `Backport162.off.g1d_failgestures` |
| 946d44b | VC `_scrollToAppLayout:animated:alignment:completion:` scrolls to the index in `appLayouts` (only with `g1c_piles` on) | 16.0 0x1c5fd9c44 passed the pile index (`continuousExposeIdentifiers` index of the layout's identifier) to the root modifier's `contentOffsetForIndex:alignment:`, 16.2 0x1c7452ff0 the `appLayouts` index. The port answers `contentOffsetForIndex:alignment:` the 16.2 way (G1C_As_ContentOffsetForIndex = 0x1c7812518, index into `appLayouts`), so every app with more than one window made "reopen closed windows" (0x1c7458334) and each modifier scroll response (0x1c745cadc) scroll to the wrong window. Stock when piles are off or a selector is missing |

## 4. Open defects (ranked)

### HIGH (impact high, not fixed - fix not local or not safe)

**H1. Base gesture workspace transaction is only partly ported** (`SBFluidSwitcherGestureWorkspaceTransaction`, 16.2 0x1c74ae6f4.. / 16.0 0x1c60339d8..).
16.2 made the transaction multi-display: per-switcher-controller layout-state maps (`originalLayoutStatesBySwitcherController`, `activeLayoutStatesBySwitcherController`),
`_workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:` 0x1c74b1478 picks the controller of `request.appLayout` (so a window dropped on the OTHER display is
requested on that display), `_updateMainDisplayIfNecessaryForWorkspaceTransitionRequests:` 0x1c74b0e90, `_runSceneLayoutTransactionForTransitionRequest:updateScenes:`
0x1c72d771c (95 -> 298 insns: ancillary layout transactions for the other displays), `transaction:performTransitionWithCompletion:` 0x1c72dbcc0 (38 -> 191), `transactionDidComplete:`
(336 -> 439), `handleTransitionRequestForGestureUpdate/Complete:fromGestureManager:` 0x1c74afba4 / 0x1c74b0490 (283 / 549). G1C.x 5b only adds the two new entry points as forwarders
to the 16.0 methods (`updateGestureWithTransitionRequest:` / `completeGestureWithTransitionRequest:`), so the 16.0 single-display transaction runs.
User-visible: dragging a window from one display onto the other lands it through the source display's request (16.0 `_transitionRequestForSwitcherTransitionRequest:` 0x1c6036044 uses the
transaction's own window scene) and the other display's scene layout is not updated by the gesture's transaction. Single-display gestures are unaffected.
Proposed patch: port 0x1c74b1478/0x1c74b0e90 first (small): in `G1C_Txn_Complete` pick `sc = [coordinator switcherControllerForAppLayout:request.appLayout]` (exists, G1D) and, when it
differs from the transaction's own controller, build the request with `[sc.windowScene._fbsDisplayConfiguration]` (the same `createRequestWithOptions:displayConfiguration:` the 16.0 body already
uses) instead of the own scene. The ancillary transactions of 0x1c72d771c are the larger part. Unverifiable without a cross-display drag log.

**H2. The 16.0 inline `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:` calls still run.** 16.2 removed them from the
`performTransitionWithContext:` blocks (its ids update is the `SBInvalidateAdjustedAppLayouts`-style response + the generation count, G1C VCIds ported as the 16.2 method);
the 16.0 blocks (they are blocks of `performTransitionWithContext:animated:completion:`, not hookable by name) still call it with the stale from/to layouts, each call bumps
`_continuousExposeIdentifiersGenerationCount`, rebuilds the two lists and posts an ids-changed event, so a transition produces one or two extra non-animated layout passes.
Candidate cause of OPEN-ISSUES #7 (window flicker ~0.1 s after app-to-app) and of part of #6. Not fixed: the blocks cannot be hooked, and suppressing the calls changes the
close/zoom timing that is under the regression guard.
Proposed patch (needs a device A/B): in the `performTransitionWithContext:animated:completion:` hook set a thread-local `tInTransitionBlock` around `%orig` and make the VC ids update
return early when it is set AND the call comes from the 16.0 block (distinguish by the animated flag / `from == to`), leaving the response-driven calls untouched; keep `g1c_ids16` as kill
switch. Do not combine with other timing changes.

### MED

* **M1 gesture update path** (`gestureHandlingModifierRequestsUpdate:` 0x1c7452bdc): hook it to send `[[[self switcherController] gestureManager] handleFluidSwitcherGestureManager:didUpdateGesture:]`
  (the G2B 5c forwarder exists) so window-drag updates requested by the modifier reach the coordinator broadcast (G1D `fluidSwitcherGestureManager:didUpdateGesture:`).
* **M2 per-display keyboard suppression** (`_acquireKeyboardSuppressionAssertionForMode:` 0x1c7459e50 + `layoutStateTransitionCoordinator:transitionDidBegin...` 0x1c743d59c
  `sb_acquireForDisplayIdentity:`): G3B has `SBMedusaHostedKeyboardWindowController`; wire the VC to `[[self _sbWindowScene] medusaHostedKeyboardWindowController]` and the 3-argument
  `startSuppressingKeyboardWithReason:predicate:displayIdentity:` (needs the 16.2 `SBKeyboardSuppressionManager` method added in G3B).
* **M3 `performKeyboardShortcutAction:`** (above): replace by the 16.2 jump table (actions 3..20, `performSwitcherKeyboardShortcutAction:`, `_navigate...InForwardDirection:` for actions 4/15,
  App Expose for the focused app).
* **M4 SBDefaultImplementationsSwitcherModifier role frame / scale** (16.2 0x1c788a480 / 0x1c788a930; 16.0 0x1c63df34c / 0x1c63df6b8): with Stage Manager on, the default
  `scaleForLayoutRole:inAppLayout:` returns the model-based scale (`stageOcclusionDodgingPeekScale` for a fully occluded item, `partiallyOccludedStageScaleForItemWithSize:` for a partially
  occluded one, else 1; 74 insns; 16.0 returns the constant 1.0) and the default `frameForLayoutRole:` adds the partially-occluded shift (`overlappingScaleAnchorCenterForItem:`) for
  stages with two or more windows. The FullScreen floor (G1C_FS_RoleScale/RoleFrame) already answers these, so the default is only reached by chains without a floor above it
  (HomeToGrid passes through to the multitasking modifier, G1C 5.x); effect is limited to peeking/occluded windows in such chains. specs/CLOSE-CROP-0.7.6.md decided not to touch the default
  (close animation under the regression guard); the missing multi-window shift is the part that spec calls "16.2 only". Patch: port both 16.2 bodies as `class_replaceMethod` on the default class
  guarded by `isChamoisWindowingUIEnabled`; verify the close/zoom videos before shipping.
* **M5 SBSwitcherController orientation family** (not in the WORKLIST): `coordinateSpaceForLayoutElement:layoutState:` 0x1c7603a88 and `sceneEntityFrameForWorkspaceEntity:inLayoutState:`
  0x1c76073e4 use `[layoutState interfaceOrientation]` instead of the per-element orientation when Stage Manager is on; `switcherOrientation:elementsOrientations:forTransitionRequest:...`
  0x1c7600950 (traits participants per layout element), `_updateAppTransitionContext:withOrientationContext:...primaryDelegate:` 0x1c76026a4, `SBLayoutState interfaceOrientationForElementIdentifier:`
  -> `...unknownAllowed:` 0x1c766f7ac. Windows of orientation-locked apps in a Stage Manager window may get a rotated scene frame. Owner G3B (traits). Cheapest partial patch:
  hook `SBLayoutState -interfaceOrientationForLayoutElement:` and return `[self interfaceOrientation]` while a thread-local set by hooks of the two SBSwitcherController methods is on.
* **M6 `SBMainSwitcherControllerCoordinator -_evaluateAsynchronousRenderingEnablement`** (16.0 0x1c624ce08, 275 insns; 16.2 0x1c76e1fcc is `ret`): the 16.0 body still toggles async rendering of
  the EMBEDDED display switcher window during transitions (main display scene manager, `setAsyncRenderingDisabled:`). 16.2 moved this to per-display response flags. Making it a no-op
  would match 16.2 but changes timing of every transition on the iPad - needs a device A/B (regression guard).
* **M7 `_updateAsyncRenderingAndResizesHostedContext`** (above), **M8 `SBHomeGestureToSwitcherSwitcherModifier -_appLayoutToScrollToDuringTransition`** 0x1c795038c (16.2: start from home with Stage
  Manager scrolls to the first window of the first pile, no mode-3 index-0 special case): small, port as a class_replaceMethod (decoded in the review notes of this session: chamois && mode 1 ->
  `[self appLayoutsForContinuousExposeIdentifier:[ids.firstObject]].firstObject`; chamois otherwise skips the 16.0 `(mode != 3 || idx != 0)` selection tweak).

### LOW

* `SBFluidSwitcherItemContainer -_addPageView` 0x1c72ced9c: 16.0 still sets `pointerInteractionHitTestPadding` = `stageInterItemSpacing` on the page view (16.2 removed it; G2B 5f's pointer edge code
  assumes the 16.2 container). `didUpdateFocusInContext:` 0x1c75e2f2c (`allowedPressTypes` instead of `_setButtonType:`), `initWithCoder:`, layer `setTransform:` 0x1c75e5304 (mirrors the transform to
  the page view), footer view `_handleTapGestureRecognizer:` 0x1c7587b90 (convertPoint / pointInside instead of frame + inset hit test) and `_makeSubtitleLabel`.
* `SBAppLayout -preferredDisplayIdentity` 0x1c77273a8: 16.2 returns the main display's identity for ordinal 0 where 16.0 returned nil; both callers
  (`_entityForDisplayItem:displayIdentity:`) treat the two the same. Neutral.
* Comment drift: G1C.x header of section 5.x says G1C "Those two creators are not ported" (fixed in 65690f3); G2.x line ~378 says the coordinator's
  `enumerateSwitcherControllersWithBlock:` is absent in 16.0 (G1D adds it as `%new`, G1D.x 297).
* `G1C_Inl_InlineLayouts` (G1C.x 3167) calls `[ident containsString:bid]` with `bid == nil` when `_appExposeBundleIdentifier` is unset: raises. The inline App Expose modifier is only created with a bundle id,
  16.2 has the same call; kept as is (documented).
* `sharedInstanceIfExists` hook of G1D.x 2155 (`SBMainSwitcherControllerCoordinator`) returns an `SBSwitcherController` while inside `_updatePictureInPictureOverlayInsetsOnWindowScene:`;
  any other caller of `sharedInstanceIfExists` that runs inside that extent on the same thread would get the wrong class (the 16.0 body of that method only sends `unlockedEnvironmentMode` /
  `layoutContainsRole:`; verified). Safe today, fragile.

## 5. Why the WORKLIST missed things

`WORKLIST.md` says "Generated by body-diffing every method present in both builds for the Stage Manager / external display classes": 66 hand-picked classes. Not diffed:
`SBSwitcherModifier(SharedModifierUtilities)` (found: `overlappingModelForAppLayout:`), `SBMainSwitcherControllerCoordinator` (found: `_deviceApplicationSceneHandleForDisplayItem:`,
`failMultitaskingGesturesForReason:`, `_evaluateAsynchronousRenderingEnablement`), `SBFluidSwitcherGestureWorkspaceTransaction` (H1), `SBSwitcherController` beyond 2 methods (M5),
`SBDefaultImplementationsSwitcherModifier` (M4), `SBHomeGestureToSwitcherSwitcherModifier` (M8), the transition modifiers (EntityRemoval*, SpotlightCrossblur..., FullScreenToHomePIP
`frameForIndex:` 44 -> 126 insns), `SBLayoutState`, `SBRecentAppLayouts` (`_validateAndUpdateRecents:` 131 -> 266), `SBMainWorkspaceLayoutStateContingencyPlan`
(`transitionContextForLayoutContext:failedEntities:` 398 -> 524), `SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:` (3653 -> 4423 insns; G3C/G4B patch pieces of it).
The size sweep list (`rev/unref.txt`, 392 methods, REF/UNREF = mentioned in the sources or not) is the starting point for the next pass; the UNREF rows outside the core area (Spotlight,
In-call, cover sheet, Recents, auto PIP, snapshot cache) belong to other review areas and were not triaged here.

## 6. Cleared during the review (no defect)

* G1B `_handleEvent:` type > 35 (0x1c7895274): base handler nil in 16.2; only FullScreenCE handles 38, 36 only Root, 37 four classes - all present; the "no handler -> nil" exit is 16.2's.
* G1C VCIds chamois-off early return = 16.2 0x1c7457450 (`isChamoisWindowingUIEnabled` cbz skips the whole body).
* Pass-through `%hook` of copy/mutableCopy returning `%orig` is ARC balanced; returning a different object needs ns_returns_retained (G1B_INIT does).
* Reveal strips rubber band, grabber click, prefers*Hidden, header-tap/pointer-crossed producers, WindowDelete class, F2S/XB transitions, Strip class: bodies match the 16.2 disassembly where
  they were compared (addresses in the source comments; a mechanical check of all `-[Class sel] ... 0x1c...` comment pairs against the symbol table found no mismatch - 30 explicit pairs, 1
  truncated name).
* G2E/G2F/G2H/G2I/G3C: deliberate deviations (g2e_closesmooth, g2f_closepivot/closecrop, g2h_maskshadow, g3c_stagesync) and diagnostics are documented with switches; no stale-state read found.
* Bug class (g): no unguarded casts, no `NSNull` sources in the owned files; timers only in diagnostics.

## 7. Not verifiable from the static review

* Whether the extra ids update (H2) is the cause of OPEN-ISSUES #6/#7: needs a log with `g1c` tracing of one app-to-app switch.
* Whether `g1c_modelmap` changes any frame under the regression guard: for layouts that are entries of `appLayouts` the query returns an equal layout; for the closing-window/leaf layouts it now
  matches 16.2. Needs the close-by-home-swipe and zoom videos as a final check.
* Cross-display drop (H1), keyboard suppression per display (M2), orientation family (M5): need a device run with an external display.
