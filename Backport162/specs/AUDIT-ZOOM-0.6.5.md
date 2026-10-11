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

## Round 2 (device log: Sileo, never windowed, Zoom x6) - static trace, written incrementally

### R2.1 What the log proves
* G3C hook sees prev/new (0,{0,0}) -> (2,{0,0}) -> (0,{0,0}) ... : the stored size of a never-windowed item is **Unspecified** (not (1,1)): section 3/5 premise of round 1 ("stored full size") is WRONG, `G3C_IsFullSize` can never fire.
* Source of `prev` (16.0 `-[SBWorkspaceApplicationSceneTransitionContext _setRequestedFrontmostEntity:]` 0x1c61ccc80): previous layout state `elementIdentifiersToLayoutAttributes[uid]` -> else most recent app layout's `layoutAttributesForItem:` -> else `[SBDisplayItemLayoutAttributes init]` (0x1c614b6e8 = policy 0, size 0, centre 0). The policy alternation 0/2/0/2 across presses proves the requested attributes are stored verbatim in the next layout state.
* Requested attributes -> layout state: `-[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:]` 0x1c5e23430 (loop at 0x1c5e2551c: `requested[uid]` wins, else previous state dict, else recent app layout, else default) -> `_updateSizingPoliciesForLayoutElements:` 0x1c6289588 via `-[SBSwitcherController layoutElementSizingPoliciesForLayoutState:]` 0x1c617b708 -> `-[SBDisplayItemLayoutAttributesCalculator sizingPolicyForDisplayItem:...proposedSizingPolicy:]` 0x1c611a728 (keeps the policy when `supported & (1<<policy)`, else `preferredSizingPolicy...`). Policy only; size/centre untouched. `-[SBMainDisplayLayoutState appLayout]` 0x1c62898e4 builds the SBAppLayout with those attributes unchanged (SBAppLayout init 0x1c628a498/0x1c628a6c0 passes them through). Nothing in this chain turns policy 0 into 2 or writes (1,1).
* So the displayed full screen comes from the CALCULATOR for the input (policy 0, size Unspecified, centre 0): same input before the first press (baseline) and after every press, which is why Zoom "does nothing" (stock 16.0: the same, only the status bar differs because policy 2 hides it).

### R2.2 Calculator path for (policy 0, Unspecified), single item - compared 16.0 / 16.2 / ours (no divergence found in these)
* auto layout: 16.2 0x1c75a4848 vs `BP2B_AutoLayout`: cache check (0x1c75a48e8), grid max (0x1c75a49d4), count>=2 pre-pass (0x1c75a4a1c..4ecc), count==1 branch (0x1c75a4d20..4ec8: only acts when the *user size before overlapping* is non-zero; ours matches), preferred model from skip-auto-layout frames (0x1c75a5060), controller, write-back (0x1c75a51c8..54f0). `_SBPreferredDisplayItemSizingPolicy` 0x1c7954330 re-decoded: our `BP2B_PreferredSizingPolicy` is exact (args: policy x0, supported x1, normalized size d0/d1 from `normalizedSizeForSize:inBounds:`). The write-back sets the attributed size only if Unspecified / empty reference (0x1c75a53e0..54a8): ours matches.
* frame code: 16.0 `_frameForLayoutRole:...` 0x1c61197b8 (policy 2 -> container 0x1c6119bc4; policy 1 -> grid; else `sizeInBounds:`; `[attrs requiresFullScreen]` -> `defaultWindowSize` 0x1c6119d14; `_SBDisplayItemSizeIsUnspecified` (0x1c614b404, identical to 16.2 0x1c75cf03c) -> `supportsCenterWindow` centre frame or `defaultWindowSize` 0x1c6119dac; then ALWAYS `nearestGridSizeForProposedSize:` 0x1c6119df4) vs 16.2 0x1c75a3614 (same shape: policy 0, size<=0 -> `defaultWindowSize` 0x1c75a3b58 / requiresFullScreen 0x1c75a3bf0 / Unspecified 0x1c75a3c14, then grid snap 0x1c75a3f78). `sizeInBounds:` of an Unspecified size is (0,0) in both (16.2 `_sizeForAttributedSize` 0x1c75d0a3c final clamp), ours (`BP2B_SizeForAttributedSize`) equal. The controller G2.x `_perform` (16.2 0x1c73c9b6c) centres a single window (hCenter/vCenter) and cannot enlarge it. => For this input the size that reaches the write-back is `nearestGrid( chamoisLayoutAttributes.defaultWindowSize )`; if that equals the container exactly, nSize==(1,1) and `_SBPreferredDisplayItemSizingPolicy` returns 2: exactly the logged "maximized {1,1}".
* 16.0 write-back (0x1c611b2bc..): rewrites the size of every item from the model and keeps the policy; so stock 16.0 gives policy 0 + full size (status bar only), as the user observed.

### R2.3 Root cause found: `defaultWindowSize` is NOT the 16.2 value
* 16.0 settings builder 0x1c6413524 computes `defaultWindowSize` with `_defaultAppSizeForContainerBounds:...` 0x1c641391c: requiresFullScreen -> bounds-2*pad; embedded display with native reference width < 2048 -> returns the FULL container (0x1c6413960..0x1c641396c); else `min(max(minW, min(W-2*strip, ...)), 1600)` x `H-2*pad-dock`. I.e. a never-windowed app is a window of (almost) the whole screen.
* 16.2 builder 0x1c78c0f50 has no such function: `defaultWindowSize` (setDefaultWindowSize: 0x1c78c1670) = `_nearestGridSizeForSize:gridWidths:gridHeights:bounds:` (0x1c7d2e280 stub, calls 0x1c78c1628/0x1c78c15f8) of a size taken from the sorted column-grid lists built by `_gridWidthsForSafeWidth:minimumWidth:stageInterItemSpacing:` 0x1c78c18fc / `_gridHeightsForSafeHeight:...` 0x1c78c1b54: index `count-2` (the SECOND LARGEST grid width; `count-1` only when prefersStripHidden) at 0x1c78c1534..0x1c78c1548. So in 16.2 the default window is one grid step below full screen.
* Our G2.x `%hook SBSwitcherChamoisSettings -layoutAttributesForContainerBounds:...` (G2.x ~1395) keeps `%orig` = the 16.0 value and only attaches extras (spacings...). This is the point where our path yields full size where 16.2 yields a smaller window (the group 2 A6 audit listed the builder as PARTIAL / not diffed).

### R2.4 Why 16.2 itself does not help here (and what is faithful)
* 16.2 Zoom request (block 0x1c77cd2e8) = (Largest, size Unspecified, user size Unspecified), centre untouched; unzoom is the same type 9 (only block with `mov w3,#9`: 0x1c790db38; handler jump table accepts 9,12,13,14,17,1..5 only). So 16.2 never "un-maximizes" through this item; there a freshly launched app is already a smaller default window (R2.3), so the problem does not exist there. The 16.0 toggle direction (policy 2 -> 0) is the only path that leaves maximized, and it hands the calculator (0, Unspecified).
* Faithful long-term fix (NOT done, too large for a static-only round): port the 16.2 default-window computation of 0x1c78c0f50 into the G2.x settings hook (column grids 0x1c78c18fc/0x1c78c1b54, pick `count-2` unless prefersStripHidden, `_nearestGridSizeForSize:gridWidths:gridHeights:bounds:`, plus 16.2 strip/min-size helpers 0x1c7d3fa20/0x1c7d3fa40/0x1c78c207c which G2 never diffed). It would change every new window's size; the 16.0 `SBDisplayItemLayoutGrid` (same API in 16.0 and 16.2) is already available and gives the same "one step below full" via `gridSizeAtIndexFromFullWidth:1` (16.0 0x1c6468ae8 -> `sizeAtIndexFromFullWidthForBounds:`).

### R2.5 G3C.x change (this round)
* Premise fixed: trigger = requested policy changes to/from 0 and the stored size is Unspecified (or full), not "full size only".
* Zoom leaving maximized (prev policy != 0, new 0, size Unspecified/full): store an explicit size = `[grid gridSizeAtIndexFromFullWidth:1 ...]` as fractions of `containerViewBounds` (`attributesByModifyingSize:`; the same primitive hand-resize ends with: policy 0 + explicit size).
* Zoom pressed while the item is (0, Unspecified) and `nearestGridSizeForProposedSize:(defaultWindowSize)` already equals the container (so maximize would change nothing visible): the press stores policy 0 + the index-1 grid size instead (one press -> window). If the default window is really smaller (as in 16.2) the press maximizes as usual.
* Inputs are all live: `SBFluidSwitcherViewController` (via handler `self._windowScene.switcherController.contentViewController`): calculator `_chamoisLayoutGridCache`, `chamoisLayoutAttributes`, `containerViewBounds`, `switcherInterfaceOrientation`, `screenScale`; item = `entity.sceneHandle.displayItemRepresentation`; restriction info = `[calc layoutRestrictionInfoForItem:]` (same call chain as 16.0 frame code 0x1c6119d00 / 16.2 0x1c75a3bdc). Deviation from 16.2 (documented): index 1 is used also when prefersStripHidden (16.2 would use index 0 = full there), because the request is explicitly "leave full screen". Any miss leaves the request untouched.

### R2.6 Confidence / what to check in the debug log
* Confidence: HIGH that the stored size is Unspecified and the display for it is calculator-derived (log + 0x1c5e23430 chain); MEDIUM-HIGH that the "full" result comes from defaultWindowSize/grid (16.0 0x1c641391c vs 16.2 0x1c78c0f50; not numerically evaluated, no device); MEDIUM for the new G3C code (static, not compiled here: no Apple SDK in the container).
* Expected lines on Zoom: `[g3c] setRequestedLayoutAttributes while armed: ... unspecified 1 ...`, then either `[g3c] zoom: default window {w, h} already fills the container ...` (press 1) and `[g3c] zoom: stored size {w, h} of {W, H} (grid index 1 from full width), policy 0`, and the transition-end line must then show `sizingPolicy: snap-to-grid; size: {<1, <1}`. If instead `no grid size below full screen (vc 0|1)` appears, send the log: `vc 0` = switcher not reached, `vc 1` = grid returned full (grid has a single cell).
