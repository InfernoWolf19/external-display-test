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
