# GRABBER-AUTOHIDE-0.7.4: why the corner resize mark vanishes, and what 16.2 does differently

16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Code: G2C.x (switches `g2c_autohide`, `g2c_scenemgr`). Evidence = instruction-by-instruction diffs of both SpringBoards.

## Report
Main display, Stage Manager, window not maximised (video: Files window over Calendar): the small dark corner mark disappears after a moment; dragging where it was does nothing; touching the window's top strip makes it come back briefly.

## The chain (identical in 16.0 and 16.2 unless marked)
1. `-[SBFluidSwitcherViewController _updateAutoHide...]` calls `-[SBAffordancePresenceController setAutoHideAffordance:]` (16.0 0x1c5ebcf3c, 16.2 0x1c732fd84, same) with
   `[liveContentOverlayCoordinator wantsHomeAffordanceAutoHideForAppLayout:]` (16.0 0x1c605071c, 16.2 0x1c74cc648; 16.2 only reads the scene manager through `_sceneManager` instead of an ivar)
   = `-[SBDeviceApplicationSceneHandle isAutoHideEnabledForHomeAffordance]` (0x1c5e37648 / 0x1c72a9a34, same) = the app's `uiClientSettings.homeIndicatorAutoHidden`.
   The `resetDelay` / `unhideDelay` arguments of the old method are never used (16.0 0x1c5fc3b2c).
2. YES enables an `SBAttentionAwarenessClient` (event mask 8, `_updateIdleTouchAwarenessClient` 0x1c5ebd160 / 0x1c732ffa8) with `attentionLostTimeout = SBFHomeGrabberSettings autoHideTime`.
   **Timer value: 2.0 s in both builds** (`-[SBFHomeGrabberSettings setDefaultValues]` 16.0 0x18ebabbd4 / 16.2 0x18ee4b60c: `setAutoHideTime:` fmov #2.0, `setAutoHideTimeOnAppRequest:` 1.5,
   `setDelayForUnhideOnTouch:` / `OnAppRequest:` 0.1 (pool double 0x18ebd0738 / 0x18ee70878 = 0.1); iPads without a home button take this branch). SBAttentionAwarenessClient is identical (system wide: the 2 s count restarts on every user touch anywhere).
3. `AWAttentionLostEvent` -> `client:attentionLostTimeoutDidExpire:...` (0x1c5ebd988) sets touchState 1 -> `_calculatePresence` (0x1c5ebcf54) = hidden -> `-[SBFluidSwitcherItemContainer
   affordancePresenceController:didChangeToPresence:]` (0x1c615b8bc / 0x1c75e28d8, same) -> `-[SBAppSwitcherPageView setResizeGrabbersVisible:(presence == 0)]` (0x1c5f1a9e8 / 0x1c738f098, same).
4. Unhide: `SBTransientUIInteractionManager` tap recognizer ("transientUI.unhide.tap", system gesture 0x20, double tap 0x21, `allowedTouchTypes` = [UITouchTypeDirect] in both) ->
   `-[SBAffordancePresenceController transientUI:wasTappedToUnhideFromGestureRecognizer:]` -> `_unhideIfAutoHidden` (0x1c5ebd528 / 0x1c7330370, same; 0.1 s delay). A drag is not a tap and does not unhide.
5. Whole class `SBAffordancePresenceController` diffed: only `initWithDelegate:` (16.0 0x1c5ebcd04) vs `initWithDelegate:windowScene:` (16.2 0x1c732fb2c) and `dealloc` differ (window scene ivar).

## Is the timeout the stock timer? Yes.
2.0 s after the last touch, for windows whose app asks for home indicator auto hide, in 16.0 and in 16.2. Nothing to change in the timer.

## Does a touch on the hidden corner resize in stock 16.2? Yes, the start region does not depend on the mark.
- Touch: `-[SBFluidSwitcherGestureManager _shouldLiveResizeItemContainerGestureWithTouch:receiveTouch:` 16.0 0x1c6443064 / 16.2 0x1c78f51a4 = `_itemContainerNearestLocation`, `_appLayoutContainsOnlyResizableApps:`,
  `[container allowedTouchResizeCorners]`, then four corner squares (side `screenEdgePadding + 50`, 100 for sizing policy 2) centred 10 pt inside the corner. No presence / visibility read in either build
  (16.2 only takes the attributes from `chamoisLayoutAttributes`, see PORT-G1D-0.7.0.md section 5).
- Pointer: `-[SBAppSwitcherPageView shouldBeginPointerInteraction...]` 0x1c5f1b610 / 0x1c738fcc8: same geometry, same.
- `allowedTouchResizeCorners` is set from `-activeCornersForTouchResizeForLayoutRole:inAppLayout:` in `_applyStyleToAppLayout:` (block 0x1c5fd5504 / 0x1c744e5c4); 0 when the window is occluded / not on stage
  (`G1C_FS_ShouldEnableGrabbers`, port of 0x1c75c5288).
=> A refused corner drag is NOT caused by the timer or by the hidden mark in 16.2 logic. In our build the remaining suspects are (a) allowed corners = 0 (occluded / not frontmost until the top strip is
touched: 16.2 `isItemFullyOccluded` family, G1C.x) or (b) the system gesture type 0x22 / `_shouldLiveResizeGesture:receiveTouch:` (G1D.x `g1d_gmtouch`). G2C.x logs both (see below). Not provable without a log.

## Real 16.2 differences (ported in G2C.x)
| 16.0 | 16.2 | G2C |
|---|---|---|
| `_updateAutoHideForGrabberAffordancesInAppLayout:withResetDelay:unhideDelay:` 0x1c5fc3b2c does the work inline; its only caller is `liveContentOverlayDidUpdateHomeAffordanceEdgeProtectOrAutoHide:` (app client settings changed) | 0x1c743c5f0 forwards to NEW `_updateAutoHideForItemContainer:appLayout:` 0x1c743c65c | added + replaced |
| `_setupLiveContentOverlayForAppLayout:itemContainer:overlay:` 0x1c5fdd720 never touches the auto-hide flag | 0x1c7456a64 calls `_updateAutoHideForItemContainer:appLayout:` after `_applyStyleToLiveContentOverlay:...` (0x1c7456b08) and ends with `_unblurItemContainer:[SBBlurItemContainerParameters defaultCrossblurBlurParameters] withAnimationUpdateMode:2` (0x1c7456b50) | replaced, full body |
| presence controller registers with `[SpringBoard systemTransientUIInteractionManager]` (main display gesture manager, `mainDisplayManager`) | registers with `[windowScene transientUIInteractionManager]` (0x1c77f8688); manager = `initWithSystemGestureManager:` 0x1c74f6e90, register / unregister 0x1c74f74d8 / 0x1c74f7678, view 0x1c74f7328 use the manager's own `SBSystemGestureManager` | `g2c_scenemgr`: scenes other than the main display get an own manager (16.0 class + associated system gesture manager) |
Consequence of row 2 in 16.0: the flag is only refreshed when the app's client settings change, so a recycled item container keeps the flag of the app it showed before (e.g. a browser / video app that asks for auto hide) and a window of an app that never asks still loses its marks after 2 s; 16.2 recomputes it at every overlay setup.
Row 3 only matters off the main display (tap to unhide never reached windows on the extended display; G1D already arms gesture types 0x1e-0x21 there).

## Not ported / differences judged irrelevant
- `SBTopAffordanceViewController` keeps the SpringBoard manager (16.2 passes its window scene too; not part of the grabber chain).
- 16.2 `SBAppResizeGrabberView initWithCorner:` adds `setAccessibilityIdentifier:` (cosmetic).
- Rest of `SBTransientUIInteractionManager` (tap to dismiss / indirect pan registrations use the scene's manager in 16.2, still the main display manager here).

## Uncertain
- Whether the Files window really asks for home indicator auto hide (then the hiding is exactly stock) or got a stale flag from a recycled container (then row 2 fixes it): decided by the new log line `[g2c] auto hide of the resize grabbers: ... A -> B`.
- `allowedTouchTypes` constant read as NSNumber 0 (value word of the constant) in both builds; identical either way.
- G2C.x is untested on device and has only had the logos syntax check.

## Debug lines (Backport162.debug)
`[g2c] auto hide of the resize grabbers: container=.. controller=.. was -> want (layout)`, `[g2c] grabber presence N (grabbers visible|hidden) container=.. allowedTouchResizeCorners=0x..`,
`[g2c] scene manager .. created for <window scene>`, `[g2c] presence controller .. registered for tap to unhide with the manager of <scene>`.
