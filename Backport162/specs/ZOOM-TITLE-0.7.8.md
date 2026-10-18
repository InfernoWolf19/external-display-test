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

## Cause (FACT from log 51d61751 + binaries; first analysis revised)
First attempt (c1b1736, refresh of the title from the committed layout state at transition end) was wrong: the committed state still holds the OLD attributes at
`transitionDidEnd` (`transition end (VC): committed policy 0 ... REFRESH` flipped a correct 'Unzoom' back to 'Zoom' at 04:01:38.518; the press verification reads 2 only ~0.6 s
later), and it did not help because the data was never the problem: stock 16.2 passes isZoomed correctly at the begin of the transition (`updateContextMenu: isZoomed passed 1 ... Unzoom`
16 ms after the press, `passed 0` after the unzoom).

The displayed menu lagged ONE update behind the UIAction title (6 menu opens in the video: Zoom, Zoom, Unzoom, Zoom, Unzoom, Zoom against action titles Zoom, Unzoom, Zoom, Unzoom, Zoom, Unzoom).
Reason: `-[SBTopAffordanceViewController updateContextMenuWithLayoutRole:...isZoomed:]` rebuilds the whole menu on every call and UIMenu keeps what its actions showed at that moment:
- 16.2 0x1c790cac4: Chamois branch (0x1c790cb3c): `imageForAction:` -> title key by isZoomed -> `_localizedMenuTitleForKey:` -> `setTitle:` (0x1c790cba8) / `setImage:` (0x1c790cbb4) on the existing
  `_maximizationAction` (a new action with that title when nil, 0x1c790cce8) ... then all other actions, `menuWithTitle:...children:` "top-affordance-context-menu" (0x1c790d9cc), `setHidden:`,
  `setShowsMenuAsPrimaryAction:YES`, `setMenu:` on the dots view (0x1c790da04..0x1c790da1c). The title is set BEFORE the menu is built.
- 16.0 0x1c6459bd0: same structure (`menuWithTitle:` "top-affordance-context-menu" 0x1c645aa68, `setShowsMenuAsPrimaryAction:` 0x1c645aa94, `setMenu:` 0x1c645aaa0) but only `setImage:` (0x1c6459c7c),
  the title is the fixed key TOP_AFFORDANCE_MENU_TITLE_MAXIMIZATION set when the action is created.
- Our hook (G3_ZoomTitle, from the first port) ran `%orig` and called `setTitle:` AFTER it, i.e. after the menu had been built from the action: the menu got the title of the previous update, the
  UIAction (and the next rebuild) got the right one. That is the one-late title; presses flipped it because every update shows the title of the one before (the single stock-visible symptom was the
  first zoom cycle of a fresh window, where the 16.0 creation title 'Zoom' met isZoomed = 1; later cycles alternate and the lag hid behind the toggling). Unlike the setLayoutRole analysis in
  the first version of this spec (cached `_isZoomed`, 16.2 0x1c77cbcec; still correct, still logged) the data was right all along.
- The dots view is a UIButton with a primary-action menu (`SBTopAffordanceDotsView`, 16.2 0x1c7794300, `contextMenuInteraction:willDisplayMenuForConfiguration:animator:` 0x1c7794f0c,
  `topAffordanceDotsViewWillPresentMenu:` 0x1c790e164 -> delegate `topAffordanceViewControllerWillPresentMenu:` 0x1c77ceea8); there is no menu provider that reads the live action.

## Fix (G3.x group G3_ZoomTitle, switch `g3zoomtitle`, default on)
Port of the 16.2 order: the title (16.2 keys, fallback to the 16.0 key / "Unzoom") is set on the existing `_maximizationAction` BEFORE the original builds the menu, with the isZoomed argument the
stock caller passes. When the original had to create the action itself (first call, 16.0's own title) the title is set afterwards and the original is called once more so the menu is rebuilt
from the action with the right title (logged as "menu rebuilt after the action got it"). With the switch off the old order (title after the original) is back; `g3c` off disables the hook.
The transition-end / menu-presented refreshes from the committed state (c1b1736) and the overlay coordinator hook are removed. Zoom request, direction and `G3C_SendZoom` are untouched.

## Debug log (Backport162.debug)
- `[g3zoomtitle] setLayoutRole: sizingPolicy argument P -> _isZoomed Z (committed policy C, largest L, mask M, ...)`: the stock writer of isZoomed.
- `[g3zoomtitle] updateContextMenu: isZoomed passed Z, committed policy C largest L (mask M) -> action title was 'A', menu built with 'B', title 'T'[ (menu rebuilt ...)], dots view menu now: ...`:
  every call; 'menu built with' must equal 'title' and the dots view menu list (children titles, nested menus in brackets) must contain it.
- `[g3zoomtitle] menu presented: _isZoomed Z, committed policy C largest L, action title 'A', presented menu: ...`: what the dots view holds when the menu opens. The old behaviour showed here
  the title of the previous update.
- `[g3zoomtitle] transition end: _isZoomed Z, committed policy ...`: logging only (the committed policy lags here).

## UNSURE
- That UIMenu (or the UIKit button) really keeps the action title from build time is inferred from the 6-open video/log match, not read from UIKit; the new `presented menu` log line shows the
  titles the dots view's menu carries and decides it. If the presented menu still shows the old title with the right action title, the next step is `-[UIContextMenuInteraction updateVisibleMenuWithBlock:]`
  from `contextMenuInteraction:willDisplayMenuForConfiguration:animator:` (0x1c7794f0c).
- 16.2's menu is built with the same order, so on a real 16.2 the title is right at the first open.
