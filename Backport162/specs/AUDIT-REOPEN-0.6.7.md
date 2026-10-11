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
