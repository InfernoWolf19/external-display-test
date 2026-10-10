# AUDIT-ZOOM-0.6.5: "Zoom" in the three-dots menu of a full-screen Stage Manager app does nothing with the tweak

Static analysis only (no device). Addresses: 16.0 = 20A8372, 16.2 = 20C65. Fix: new file `G3C.x`, switch `g3c` (BP.h `F_G3C`, Tweak.x `kFeatureNames` "g3c", README row, Makefile).

## 1. The code path of the "Zoom" item

* Menu builder `-[SBTopAffordanceViewController updateContextMenuWithLayoutRole:spaceConfiguration:floatingConfiguration:interfaceOrientation:isZoomed:]` 16.0 0x1c6459bd0 / 16.2 0x1c790cac4.
  Stage Manager (`_isChamoisWindowingUIEnabled`) menu = `_maximizationAction` (title key `TOP_AFFORDANCE_MENU_TITLE_MAXIMIZATION` in 16.0,
  `..._MAXIMIZATION_ZOOM` / `..._MAXIMIZATION_UNZOOM` in 16.2, picked with `isZoomed`), `_addToSetAction` ("Add Another Window"), `_removeFromSetAction`
  (the item the user calls "Minimise"), `_closeAction`, `_moveToDisplayAction` (only with more than one display).
* The UIAction blocks send `[delegate topAffordanceViewController:self handleActionType:N]`; N: maximization 9 (block 16.0 0x1c645abb8 / 16.2 0x1c790db38), add-to-set 12,
  remove-from-set 13, full screen 1 (non-Stage-Manager menu), split 2, slide over 5, left 3, right 4, move to display 14, close 17 (blocks `_block_invoke_N`, `mov w3,#N`).
* Delegate: `-[SBMedusaDecoratedDeviceApplicationSceneViewController topAffordanceViewController:handleActionType:]` (16.0 0x1c632b9cc / 16.2 0x1c77ccae8) -> with Stage Manager
  `_topAffordanceViewController:handleActionType:transitionSource:` (16.0 0x1c632ba50 / 16.2 0x1c77ccb6c, `transitionSource` = 0x32), jump table on `type-9` (9 entries; 16.0 table at 0x1c632be54).
  Type 9: `SBLogTopAffordance`, `[menu dismissAnimated:YES]`, `[[SBWorkspace mainWorkspace] requestTransitionWithOptions:0 displayConfiguration:builder:validator:nil]`, builder
  (16.0 `_block_invoke.64` 0x1c632c0ec / 16.2 `_block_invoke.66` 0x1c77cd238) = `request.source = transitionSource; [request modifyApplicationContext:^(ctx){...}]`.

## 2. What the request block does (16.0 vs 16.2)

16.0 `_block_invoke_2.65` 0x1c632c18c:
```
e = [[SBDeviceApplicationSceneEntity alloc] initWithApplicationSceneHandle:handle];
[ctx _setRequestedFrontmostEntity:e];                       // 0x1c61ccc80: copies the item's CURRENT attributes into the context
mask = [handle _supportedSizingPolicies];                   // 0x1c6866060
p = [ctx requestedLayoutAttributesForEntity:e];             // 0x1c61cca60: dict[e.uniqueIdentifier]
p = [p attributesByModifyingSizingPolicy:([p sizingPolicy] == SBDisplayItemSizingPolicyAllowingLargestSize(mask) ? ...AllowingSmallestSize(mask) : ...LargestSize(mask))];  // 0x1c632c20c/218/224..234
[ctx setRequestedLayoutAttributes:p forEntity:e]; [ctx setFencesAnimations:YES];
```
i.e. 16.0 Zoom TOGGLES only the sizing policy and leaves the stored size/centre alone.

Sizing policies (0x1c79542a8 NSStringFromDisplayItemSizingPolicy; masks 1/2/4): 0 "snap-to-grid", 1 "zoomed-to-fill", 2 "maximized".
`...AllowingLargestSize` 16.0 0x1c649d490 / 16.2 0x1c795431c = highest supported policy, `...Smallest` 0x1c649d470 / 0x1c79542fc = lowest.
Frame code (16.0 `_frameForLayoutRole:...` 0x1c61197b8): policy 2 -> whole container (0x1c6119bc4), policy 1 -> nearestGridSize, otherwise
`sizeInBounds:`; if `requiresFullScreen` -> `defaultWindowSize`; if `_SBDisplayItemSizeIsUnspecified(size)` (0x1c6119d38) -> centre-window frame or
`[chamoisLayoutAttributes defaultWindowSize]` (0x1c6119d20/0x1c6119dac) snapped by `nearestGridSizeForProposedSize:` (0x1c6119df4).
16.2 equivalent (`0x1c75a3614`): size <= 0 -> `defaultWindowSize` + `sizeInBounds:defaultSize:screenEdgePadding:` (0x1c75a3b34..0x1c75a3b8c, 0x1c75a3aac).

16.2 `_block_invoke_2.67` 0x1c77cd2e8 (type 9, decoded also in specs/group3-plumbing.md 2.5 and group3b-reconstruct.md 8.1): `setEntities:@[e] withPolicy:0 centerEntity:nil floatingEntity:nil`,
`_setRequestedFrontmostEntity:`, `pol = AllowingLargestSize([handle _supportedSizingPoliciesForContentOrientation:containerOrientation:])`,
`attributesByModifyingSizingPolicy:pol`, `attributesByModifyingAttributedSize:SBDisplayItemAttributedSizeUnspecified()` (0x1c75cedc4),
`attributesByModifyingAttributedUserSizeBeforeOverlapping:Unspecified`, `setFencesAnimations:YES`.
**16.2 never toggles back**: there is no `AllowingSmallestSize` in the block (the only 16.2 callers of 0x1c79542fc / 0x1c795431c are `SBItemResizeGestureSwitcherModifier
_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:`, `setLayoutRole:...sizingPolicy:` 0x1c77cbdf4 (`_isZoomed = policy == Largest`, the menu title) and this block). The "UNZOOM" item
of 16.2 therefore re-requests the maximized state; I could not find any 16.2 code that turns a maximized window back into a window through this item.
**So "Zoom on a full-screen app -> window" is the 16.0 toggle direction, not something the 16.2 handler does. This cannot be reconstructed from 16.2 and I did not invent it.**

## 3. Why stock 16.0 only toggles the status bar, and why the tweak turns it into a complete no-op

* A window that the user never resized has the stored size (1,1) / the whole container (written by the auto layout write-back). 16.0 Zoom changes only the policy (2 -> 0), so the item
  is a snap-to-grid window of FULL size: the only visible difference is the status bar (policy 2 hides it / policy 0 shows it; `appLayoutContainsAnUnoccludedMaximizedDisplayItem:`). Stock behaviour of the report.
* Once the user has resized the window the stored size is a smaller window: Zoom (policy 2: frame = container) and Zoom again (policy 0 + stored size) works, as the user observes.
* With the tweak: `G2B.m:BP2B_AutoLayout` write-back (G2B.m:871-877) re-derives the policy after every auto layout with `BP2B_PreferredSizingPolicy(nSize, policy, supported)`
  (= 16.2 `_SBPreferredDisplayItemSizingPolicy` 0x1c7954330, called from 16.2 calculator 0x1c75a5338): policy 0 with normalized size (1,1) gives 2 again. The Zoom toggle is undone in
  the same layout pass: no size change AND no status bar change. For a window with a smaller stored size the derived policy is 0 and the toggle survives (user observation).
  No hook of ours touches the menu, the delegate method or the request: G1B (G1B_Handled), G1C, G3 (g3topaff only the highlight / context menu refresh), G4B are not involved
  (grep for `handleActionType`, `setRequestedLayoutAttributes`, `requestedLayoutAttributes` over all sources: no hit).

## 4. Implementation (G3C.x, switch `g3c`)

* Hook 1 `-[SBMedusaDecoratedDeviceApplicationSceneViewController _topAffordanceViewController:handleActionType:transitionSource:]`: for `type == 9` arms the fix for 3 s (the builder
  block runs inside `requestTransitionWithOptions:...builder:`, possibly a turn later), then `%orig`.
* Hook 2 `-[SBWorkspaceApplicationSceneTransitionContext setRequestedLayoutAttributes:forEntity:]` (16.0 0x1c61ccac4): while armed, if the context's CURRENT requested attributes
  (`requestedLayoutAttributesForEntity:`, filled by `_setRequestedFrontmostEntity:` 0x1c61ccc80) have a sizing policy != 0, the new ones have policy 0 and the stored `_size` is the whole
  container ((1,1), or the absolute screen size in either orientation, 0.5 % tolerance), the new attributes get the size reset with `attributesByModifyingSize:CGSizeZero`
  (16.0 data model of `SBDisplayItemAttributedSizeUnspecified()`, which 16.2's own Zoom block uses at 0x1c77cd404). The frame code then resolves it to the LIVE chamois
  `defaultWindowSize` snapped to the grid (sections 2/frame code above), the write-back stores the real window size and the derived policy stays 0.
* No constant is introduced: the window size comes from `chamoisLayoutAttributes.defaultWindowSize` (live settings value, 16.0 0x1c6119d20, 16.2 0x1c75a3aac / 0x1c75a3b58) and `nearestGridSizeForProposedSize:`.
  A window with a stored smaller size is untouched (the stored size is kept, as on 16.0). Policy 1 and 2 results (maximize direction) are untouched.
* Fallbacks: every selector is `respondsToSelector:`-guarded; the `_size` ivar is read by name and only if its type encoding is `{CGSize`; on any miss the original attributes are stored (= previous behaviour).
  `attributesByModifyingSize:` returns an autoreleased object (not a copy-family selector). No void/ID mismatch: both hooks are void.

## 5. Confidence and open points

* Root cause (policy re-derived by the G2B write-back, plus a stored full size): HIGH for the mechanism (code read in 16.0 and 16.2, matches both user observations: stock = status bar only, tweak =
  nothing, manual window first = works). The assumption that a never-windowed item stores a full-size (1,1)/screen-size `_size` is inferred (consistent with the observations), not read from a log.
* The fix: MEDIUM (static; not run). Device check: `Backport162.debug`, press Zoom on a fresh full-screen app; the log line `[g3c] zoom: full-size item leaves policy ...` must appear and the app must come back
  with the default window size. If no line appears, the stored size is not full-size (then `_size` is something else) - send the log.
* Not done / cannot be exact: 16.2 has no un-zoom in this item (above). The keyboard shortcut `-[SpringBoard _handleToggleMaximizationKeyShortcut:]` (16.0 0x1c5ee5a54 ->
  `performKeyboardShortcutAction:0x11`) does not exist in 16.2 and takes a different path (switcher action 0x11); not covered by this fix.
* If the apps supported-policy mask has no policy 0 (smallest = 1) the toggle stays as on 16.0 (not touched).
