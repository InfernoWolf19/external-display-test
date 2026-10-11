# AUDIT-REOPEN-0.6.7: does 16.2 remember a window across Close + relaunch? (written incrementally)

Symptom: window an app, three-dots > Close, reopen from Dock/Home -> full screen (stock 16.0 and tweak). User wants 16.2 behaviour.

## Step 1 findings so far
* Close path (both builds identical in shape): `-[SBMainSwitcherControllerCoordinator _switcherModelRemovalResultsForRequest:forReason:]` (16.0 0x1c624b4b0, 16.2 0x1c76e0660),
  block_invoke_2 (16.0 0x1c624bafc, 16.2 0x1c76e0cc0): for a closed layout it calls `SBAppSwitcherModel hide:` (16.2 0x1c76e0da8) / `appLayoutByModifyingHiddenState:YES` + `addToFront:`
  (0x1c76e0d6c/0x1c76e0d84) or removes; `setHide:forDisplayItem:` (0x1c76e0910) is set only when the app `supportsMultiwindow` and reason == 1 (0x1c76e0890..0x1c76e089c) and the
  scene's `uiClientSettings discardSessionOnUserDisconnect` is NO. The only diff 16.0->16.2 in this function is `switcherControllerForAppLayout:` (multi-display) instead of one switcher.
* `-[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:]` (16.0 0x1c5e23430, 16.2 0x1c72952ec): 16.2 calls
  `_mostRecentAppLayoutMatchingAnyUniqueIdentifier:chamoisWindowingUIEnabled:` where 16.0 has `_mostRecentAppLayoutMatchingAnyUniqueIdentifier:`; 16.2 additionally consults
  `_recentAppLayouts recentsIncludingHiddenAppLayouts:` (new). To be decoded in detail below.

## Step 2 findings (Close path, where memory could live) - all by disassembly, 16.0 20A8372 vs 16.2 20C65
* There is NO new store class in 16.2 (class diff: 66 new classes, none is a store/archive; SBRecentAppLayouts LOST its two `_continuousExposeIdentifiers*` ivars; no new ivar of
  SBAppSwitcherModel / SBMainSwitcherControllerCoordinator / SBMainDisplayLayoutStateManager / SBSwitcherController / SBFluidSwitcherViewController holds sizes or attributes;
  SBSwitcherChamoisSettings 16.2 has only `rasterizeScaledApps` + cached chamois defaults, SBAppSwitcherDefaults has no new key; no NSUserDefaults key for window size).
* "Close" in the three-dots menu (both builds): `-[SBMedusaDecoratedDeviceApplicationSceneViewController _topAffordanceViewControllerHandleCloseAction]` (16.0 0x1c632d1fc, 16.2 0x1c77ce3cc) ->
  `_SBApplicationSceneEntityDestructionMakeIntent(1,1)` + `_SBWorkspaceDestroyApplicationSceneHandlesWithIntent` -> `-[SBMainWorkspace _removeApplicationEntities:withDestructionIntent:completion:]`
  -> `-[SBMainSwitcherControllerCoordinator handleApplicationSceneEntityDestructionIntent:forEntities:]` (16.0 0x1c6247de0, 16.2 0x1c76dcca8; body identical in shape) -> workspace transition with
  `SBWorkspaceEntityRemovalContext` -> `layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` (16.0 0x1c62362ec / 16.2 0x1c76c9354, 0.99 similar) builds the removal request
  (`entitiesWithRemovalContexts`, removalActionType 1/2 -> intent 2/1) and calls `_switcherModelRemovalResultsForRequest:forReason:` with reason 3 (16.2 0x1c76c96f8 `mov w3,#3`).
* `_switcherModelRemovalResultsForRequest:forReason:` (16.0 0x1c624b4b0 / 16.2 0x1c76e0660; body equal except `switcherControllerForAppLayout:`): the layout is HIDDEN (`appLayoutByModifyingHiddenState:YES`
  + `addToFront:` + `SBAppSwitcherModel hide:`, 16.2 0x1c76e0d6c/0x1c76e0da8) only when `reason == 1 && application.info.supportsMultiwindow && !scene.uiClientSettings.discardSessionOnUserDisconnect`
  (16.2 0x1c76e0890..0x1c76e0900: `cmp w0,#0; ccmp x22,#1,#0,ne`; x22 = arg `forReason`). Reason 1 comes from the card swipe-kill path (`killContainer:forReason:`), not from Close.
  The Close transition uses reason 3 => `-[SBAppSwitcherModel remove:]` (= `SBRecentAppLayouts remove:`/`removeAppLayouts:`, byte-identical in both builds) => the app layout and its
  SBDisplayItemLayoutAttributes are DROPPED from the recents model and from the persisted protobuf (`SBRecentAppLayoutsPersister`, identical class in both builds), and
  `_performSceneDestructionForModelRemovalResults:` (0.99 similar) destroys the scene. Nothing keyed by bundle id or scene id survives.
* Launch side (both builds, byte-identical): `-[SBWorkspaceApplicationSceneTransitionContext _setRequestedFrontmostEntity:]` (16.0 0x1c61ccc80 / 16.2 0x1c765b980): requested attributes =
  already requested -> previousLayoutState.elementIdentifiersToLayoutAttributes[scene uniqueIdentifier] -> `[SBAppSwitcherModel/_recentAppLayoutsController mostRecentAppLayoutIncludingHiddenAppLayouts:YES
  passingTest:(contains item with that uniqueIdentifier)] layoutAttributesForItem:` -> `[SBDisplayItemLayoutAttributes init]` (policy 0, size Unspecified, centre 0), with `_nextInteractionTime`.
  After Close there is no previous-state entry and no recent layout => the default attributes. `SBMainDisplayLayoutStateManager defaultSceneIdentifierForBundleIdentifier:...` (16.0 0x1c625a1b0 /
  16.2 0x1c76f09f4) only re-uses scene ids of layouts still present in recents (hidden ones included; 15 s double-kill rule `_hasAppLayoutBeenUserKilledWithinThresholdToCreateNewScene:` identical).

## Step 3: other candidates checked and ruled out
* `_layoutStateForApplicationTransitionContext:` (16.0 0x1c5e23430 / 16.2 0x1c72952ec, 2995 -> 3568 insns): the 16.2 changes are (a) `isDisplayExternal`/display ordinal, (b) `previousEntities`/
  `isPreviousWorkspaceEntity`/`isEmptyWorkspaceEntity` (empty/previous placeholder entities), (c) the `chamoisWindowingUIEnabled:` flavour of the two `_mostRecentAppLayout...` helpers (16.2
  0x1c76f1c40 / 0x1c76f2118: additionally split medusa-incompatible items with `appLayoutsBySplittingMedusaIncompatibleItemsWithApplicationController:`; they still search the same recents
  model, `…MatchingAnyUniqueIdentifier` INCLUDING hidden layouts, `…ForBundleIdentifier:ignoringUniqueIdentifiers:` WITHOUT hidden ones, as in 16.0 0x1c625b298 / 0x1c625b534), and (d) a NEW tail
  block (16.2 0x1c7298d50..0x1c7298e88): after `_updateSizingPoliciesForLayoutElements:` it asks the calculator `frameForLayoutRole:inAppLayout:containerOrientation:windowScene:` once and writes
  the (auto-layout resolved) attributes of every item back with the new `-[SBMainDisplayLayoutState _setLayoutAttributes:forLayoutElement:]` (16.2 method, 67 insns). That only resolves
  Unspecified sizes into explicit ones for the CURRENT state; it reads nothing that survives a Close.
* `_configureRequest:forSwitcherTransitionRequest:withEventLabel:` (16.0 0x1c623e164 / 16.2 0x1c76d174c): new in 16.2 (0x1c76d246c) for switcher requests with chamois on: the requested
  attributes of an app-layout item keep the interaction time already requested (`requestedLayoutAttributesForEntity:` -> `lastInteractionTime` -> `attributesByModifyingLastInteractionTime:`).
  Recency only; applies to tapping an EXISTING layout, not to a relaunch.
* `SBRecentAppLayouts _validateAndUpdateRecents:` (16.2 0x1c79aa0ec) only adds splitting of medusa-incompatible layouts; `_stashModelToPath:` only debug stash. The persister
  (`SBRecentAppLayoutsPersister`, protobuf `SBPBDisplayItemLayoutAttributes`) is the same shape; the 16.2 protobuf has the new attributed-size fields (G2B), it persists RECENTS across respring,
  never a closed window.
* `_performSceneDestructionForModelRemovalResults:` (16.0 0x1c624a104 / 16.2 0x1c76df2a0): same selector sequence (only `_appForDisplayItem:` -> `[SBApplicationController sharedInstance]
  applicationForDisplayItem:`).
* No UserDefaults: `SBAppSwitcherDefaults` has no new key; `SBSwitcherChamoisSettings` (16.2) new members are `_gridWidths/HeightsForSafeWidth...`, `_minimumDefaultWindowSizeForContainerBounds:stripWidth:`,
  `_nearestGridSizeForSize:gridWidths:gridHeights:bounds:`, `rasterizeScaledApps`, pile/peek numbers and cached chamois defaults (hide strips / hide dock): no remember/restore flag.

## CONCLUSION
16.2 (20C65) does NOT persist or restore an app's window attributes across a three-dots > Close and relaunch. Close removes the layout from SBRecentAppLayouts (reason 3 => `remove:`, only the
swipe-kill reason 1 of a multiwindow app hides and keeps it for "Reopen Closed Windows"), the scene is destroyed, and the relaunch starts from `[SBDisplayItemLayoutAttributes init]`
(policy 0, size Unspecified) exactly like 16.0. Confidence: high (about 90 %) - every function on the path was diffed; the only unread part is UIKit/app-side state (the app, not SpringBoard).
The difference the user WILL see on 16.2 after relaunch is the DEFAULT window size: 16.2 `-[SBSwitcherChamoisSettings layoutAttributesForContainerBounds:...]` (0x1c78c0f50) sets
`defaultWindowSize` = `_nearestGridSizeForSize:gridWidths:gridHeights:bounds:` of the SECOND-LARGEST grid column (index count-2; count-1 only with prefersStripHidden, 0x1c78c1524..0x1c78c1548),
i.e. a window one grid step below full screen, whereas 16.0 (0x1c6413524/0x1c641391c) returns an almost full-screen window. This is the open item AUDIT-ZOOM-0.6.5 R2.3/R2.4 already
named (port of 0x1c78c0f50 + `_gridWidths/HeightsForSafeWidth...` 0x1c78c18fc/0x1c78c1b54 into the G2.x chamois-settings hook). No G3D.x / `g3d` switch was added because there is nothing to port.
