# Zoom / Unzoom menu title stale for a fresh window (G3.x, switch g3zoomtitle)

Status: FACT = read from the binaries (static, dyld caches), INFERENCE = deduced, UNSURE = needs the device.

## Report
Fresh window (app just opened, never zoomed or resized): menu says Zoom (right), press, the window zooms. Opening the menu again says "Zoom" (WRONG, must be
"Unzoom") although pressing it unzooms. Next cycle: Zoom (right), zoom, "Unzoom" (right). From then on it is right. The device log of the failing session
(ca2ee0fc) has the presses (`[g3c] ... committed 0 -> 2`, later `committed 2 -> 0`) but no line about the title; the video shows only the multi-window zoom
delay, not the menu.

## Who computes and passes isZoomed (FACT, 16.0 == 16.2)
- `isZoomed` is not read when the menu is opened. It is the cached BOOL ivar `_isZoomed` (+0x420) of `SBMedusaDecoratedDeviceApplicationSceneViewController`.
- The only writer is `-setLayoutRole:spaceConfiguration:floatingConfiguration:sizingPolicy:` (16.2 0x1c77cbcec, 16.0 0x1c632ac5c, same code):
  `_isZoomed = (SBDisplayItemSizingPolicyAllowingLargestSize([app supportedSizingPoliciesForSwitcherWindowManagementStyle:displayIdentity:contentOrientation:containerOrientation:]) == sizingPolicy)`
  (16.2 0x1c77cbdd8..0x1c77cbe08, 0x1c795431c), then `_updateTopAffordanceHighlight` and `updateContextMenuWithLayoutRole:...isZoomed:` with the cached value (0x1c77cbe54).
- Callers of `setLayoutRole:...sizingPolicy:` (16.2): `-[SBMainWorkspaceApplicationSceneLayoutElementViewController _configureViewController:]` 0x1c72a25bc (full screen workspace, passes 0, 0, 0) and
  `-[SBFullScreenSwitcherSceneLiveContentOverlay configureWithWorkspaceEntity:...sizingPolicy:]` 0x1c74cebfc, whose only caller is
  `-[SBFullScreenSwitcherLiveContentOverlayCoordinator _configureLiveContentOverlayView:forTransitionContext:layoutRole:]` 0x1c74cd7a8 (16.0 0x1c6051300, identical):
  `sizingPolicy = [[[context layoutState] layoutAttributesForElement:[layoutState elementWithRole:role]] sizingPolicy]`
  (`SBMainDisplayLayoutState layoutAttributesForElement:` 16.2 0x1c7721c4c == 16.0 0x1c62893a4, the layout state's element dictionary), called from
  `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` 0x1c74ca574 (existing overlays) and `_newLiveContentOverlayForApplicationContext:layoutRole:`.
- All callers of `updateContextMenuWithLayoutRole:...isZoomed:` (16.2): `setLayoutRole:...` 0x1c77cbe54, `activeInterfaceOrientationDidChangeToOrientation:...` 0x1c77cf370,
  `_windowManagementStyleDidChange:` 0x1c77cfe90 (our %new port), `_createOrDestroyTopAffordanceViewControllerAnimated:` 0x1c77d0b24; 16.0 has the first, second and fourth.
  All pass the cached `_isZoomed`. `-topAffordanceViewControllerWillPresentMenu:` (16.2 0x1c77ceea8, called from `-[SBTopAffordanceViewController topAffordanceDotsViewWillPresentMenu:]`
  0x1c790e164) only requests a main workspace transition (non Chamois), it does not refresh anything.
- `updateContextMenu...` (16.2 0x1c790cac4) with Chamois windowing on: `setTitle:` (key `TOP_AFFORDANCE_MENU_TITLE_MAXIMIZATION_UNZOOM` / `_ZOOM` by isZoomed) and `setImage:`
  (`+imageForAction:interfaceOrientation:` 11 / 10) on the existing `_maximizationAction`, creating it with the same title when nil (0x1c790cce8).

## Cause (INFERENCE, the stale value is not visible in the log)
Stock 16.0 and 16.2 are identical: the title is only as right as the `sizingPolicy` argument that the overlay coordinator derived at the BEGIN of the last transition from
the layout state's element attributes, compared with the largest policy of the window's supported mask at that moment. Nothing re-reads the committed state when the
transition is over or when the menu opens. For a fresh window that argument (or the mask: content orientation / user resize orientation of a never resized window are not set
yet, `g3handle`) does not equal the displayed Largest policy on the first zoom (the committed app layout attributes did change: `[g3c] unzoom: ... committed 2` at the next
press), the cached `_isZoomed` stays NO and the title stays "Zoom"; by the second cycle every input is populated and the value is right. Stock iPadOS 16.2 has the same code path,
so this is probably stock behaviour (a fresh window on a device with identical inputs would behave the same) that the port exposes more often because 16.0 supplies some of the inputs
differently. UNSURE which of the two inputs (argument or mask) differs on the first cycle: the new debug log decides it (see below).

## Fix (DELIBERATE deviation, switch `g3zoomtitle`, default on; G3.x group G3_ZoomTitle)
The committed policy of the window (`BP_G3_ZoomState`: current layout state of the window scene's switcher controller, `appLayout` / `floatingAppLayout` `layoutAttributesForItem:` of the
handle's display item, the same data `G3C_CommittedPolicy` uses to decide the press direction, and the mask of `_supportedSizingPoliciesForContentOrientation:containerOrientation:`
as in `G3C_ZoomRequest`) is compared with `_isZoomed` and the shown title at:
1. end of every transition: `-[SBMedusaDecoratedDeviceApplicationSceneViewController layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:]` and
   `-[SBFullScreenSwitcherLiveContentOverlayCoordinator ...transitionDidEnd...]` (over the overlays' decorated VCs); full refresh;
2. `-topAffordanceViewControllerWillPresentMenu:` (menu about to be shown): title and image of the existing action only (the menu is not rebuilt while it opens).
Refresh = write the cached `_isZoomed` (so the rotation / style change callers pass the right value again) and run 16.2's own `updateContextMenu...isZoomed:` (title + image by 16.2's code).
Nothing happens when the committed attributes are unavailable (`no committed attributes`), when the VC has no maximization action (non Chamois) or when title and ivar already agree.
`g3c` off also disables it. Zoom request, direction and `G3C_SendZoom` are untouched.

## Debug log (Backport162.debug), proves the fix on the next device log
- `[g3zoomtitle] setLayoutRole: sizingPolicy argument P -> _isZoomed Z (committed policy C, largest L, mask M, ...)`: the stock writer (shows which input is wrong on the first cycle).
- `[g3zoomtitle] updateContextMenu: isZoomed passed Z, committed policy C largest L (mask M) -> title set 'T' (role ... orientation ...)`: every call, stock or ours.
- `[g3zoomtitle] <menu presented | transition end (VC) | transition end (overlay)>: committed policy C largest L (...) -> zoomed Z, cached _isZoomed Y, shown 'S' wanted 'W' (up to date | REFRESH)`.
Expected on the first cycle: `setLayoutRole` with Z 0 after the zoom, then `transition end ... REFRESH` and a following `updateContextMenu: isZoomed passed 1 ... title set 'Unzoom'`.

## UNSURE
- Whether the VC (or the coordinator) receives `transitionDidEnd` in Stage Manager on 16.0: the `menu presented` refresh is the fallback, but UIKit may not update an already displayed menu from a mutated UIAction (then the first open after the zoom still shows the old title and the second is right: the log lines tell).
- Whether `sc.layoutState` already holds the new attributes at the DidEnd callback (the press verification in G3C reads it 1.6 s later). If not, the `menu presented` refresh covers it.
