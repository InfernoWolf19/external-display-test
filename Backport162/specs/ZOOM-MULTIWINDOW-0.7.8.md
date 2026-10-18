# Zoom with several windows on the stage: the window centres first and zooms about a second later (G3C.x, switch g3c_stagesync)

Status: FACT = read from the binaries (static, dyld caches, 16.0 = 20A8372, 16.2 = 20C65) or from the device log ca2ee0fc; INFERENCE = deduced; UNSURE = needs the device.
Device-unverified.

## Report
Top-affordance Zoom of a window on a stage of two windows (Photos + Sileo, log 01:12:49.161 and 01:13:15.232): the window "centres" and only about a second later
zooms. With one window the zoom is immediate. Log of the failing press:

    01:12:49.162 [g3c] zoom: policy mask 5, committed 0 requested-base 0 -> 2, size {0, 0}
    01:12:49.196 transition slideshow&Sileo -> slideshow (BP162ContinuousExposeAppToAppModifier), Sileo goes to the strip
    01:12:50.234 addwin: transition end ... N = slideshow, sizingPolicy: snap-to-grid; size {0.637, 0.8225}; center {0.5, 0.416}; user size unspecified; lastInteractionTime 92
    01:12:50.833 [g3c] zoom request had no effect (committed policy still 0), repeating once
    01:12:50.834 [g3c] zoom: policy mask 5, committed 0 requested-base 2 -> 2     <- second request: zooms at once (N: maximized {1,1}, lastInteractionTime 93)

## What the state manager does with the request (FACT)
- `setEntities:@[e] withPolicy:0 centerEntity:nil floatingEntity:nil` is the same code in both builds (`-setEntities:withPolicy:...` 16.0 0x1c61cc3b4 -> `...startingAtLayoutRole:...` 0x1c61cc3d0,
  role block 0x1c61cc65c; 16.2 0x1c765b0b4 / 0x1c765b0d0 / 0x1c765b35c, instruction for instruction). Policy 0 puts the empty-workspace placeholder into every role that has no
  entity (policy 1 would use the previous entities), so the other windows of the stage are dropped from the new stage; they go to the strip.
- `-[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:]` (16.0 0x1c5e23430, 16.2 0x1c72952ec): the element attribute loop (16.0 0x1c5e2551c..0x1c5e256c0,
  16.2 0x1c7298454..0x1c7298628) takes, per element, (1) `[ctx requestedEntityIdentifierToLayoutAttributes][uid]` (16.0 load 0x1c5e254b8, lookup 0x1c5e25554), else (2) the previous
  state's `elementIdentifiersToLayoutAttributes[uid]` (0x1c5e254a4), else (3) the most recent recents layout containing the item, `layoutAttributesForItemInRole:` (0x1c5e255e4..0x1c5e25680),
  else (4) `[SBDisplayItemLayoutAttributes init]` (0x1c5e256b8). The requested attributes WIN over the previous element's. 16.2 is the same loop (requested 0x1c72983f4, previous
  0x1c72983e0, recents 0x1c7298528 with the extra `chamoisWindowingUIEnabled:`). `_updateSizingPoliciesForLayoutElements:` (0x1c6289588) only rewrites the policy (kept when the
  app supports it: mask 5 contains 2). So the new state's element dictionary holds the request.
- The second request proves it: its base `requestedLayoutAttributesForEntity:` is 2 although the displayed ("committed") layout still says 0. `_setRequestedFrontmostEntity:`
  (0x1c61ccc80 / 16.2 0x1c765b980) takes the base from the previous state's element dictionary (0x1c61ccdf4), which is where the first request was stored verbatim.
- The 16.2 state method has a NEW tail (0x1c7298d50..0x1c7298e88): after `_updateSizingPoliciesForLayoutElements:` it asks a calculator for `frameForLayoutRole:inAppLayout:
  containerOrientation:windowScene:` of the state's `appLayout` and writes the auto layout resolved attributes of every item back into the state dictionary with the new
  `-[SBMainDisplayLayoutState _setLayoutAttributes:forLayoutElement:]`. 16.0 has no such tail. It only makes the DICTIONARY hold resolved values; it does not touch the stage layout
  that is shown (see next section), so it is not a fix for this report and was not ported (specs/AUDIT-REOPEN-0.6.7.md reached the same conclusion for another question).

## Why the displayed layout is old (FACT for the mechanism, INFERENCE for the order of the writes)
`SBAppLayout` is interned. `-[SBAppLayout initWithItems:centerItem:floatingItem:configuration:itemsToLayoutAttributes:centerConfiguration:environment:hidden:preferredDisplayOrdinal:]`
(16.0 0x1c628a6c0, 16.2 0x1c7723388, same body) builds the object, hashes configuration / environment / ordinal / items (NOT the attributes, 0x1c628a9a0..0x1c628aab8), takes
`member:` from a global NSHashTable whose pointer functions use a value equality (0x1c628acd8, equality block 0x1c628af34), adds the object when there is none, and then
**stores a copy of the new attribute dictionary into the cached instance** (`[x26 + 0x50] = [new copy]`, 0x1c628ab34..0x1c628ab40; 16.2 0x1c7723800..0x1c7723808) and returns the cached
instance. All equal layouts therefore share one attribute map, the last `init` wins. (`-[SBAppLayout isEqual:]` 0x1c5e31cac is a pointer compare, as expected for an interned class.)
Everything that is derived later from an old layout writes the old attributes back: `-[SBAppLayout leafAppLayouts]` (0x1c628cc5c) / `leafAppLayoutForItem:`,
`-[SBFluidSwitcherViewController _unadjustedLeafAppLayouts]` + `_rebuildCachedAdjustedAppLayouts` (16.0 0x1c5fddb6c / 0x1c5fddca8, 16.2 0x1c7456eec / 0x1c7457028, identical call
sequences), `appLayoutByModifyingLayoutAttributes...` (0x1c628d78c / 0x1c628d91c) and the calculator's auto layout write-back (`appLayoutByModifyingLayoutAttributesForItems:`).
Evidence in the log that this is what happened:
- the committed layout after the first transition is exactly "the OLD leaf of the stage after the single-window auto layout": policy 0, size {0.637, 0.8225}, lastInteractionTime 92 (the
  request would carry 93, as the second request's result does), centre moved to 0.5 and user size before overlapping Unspecified (the count == 1 branch of the ported auto layout,
  G2B.m `BP2B_AutoLayout`, resets both). The creation-time attributes of the same window in the earlier two-window state (01:12:45.404 "endpeek: result") were centre 0.5 / user Unspecified
  as well, but the end-of-transition layout of that transition (01:12:46.413) shows centre 0.661 / user {0.637, 0.775} / occlusion states: the shown layout is the shared object that the
  auto layout rewrote in place, not the dictionary of the state.
- One window on the stage: the stage and the new layout are the same interned instance, the request is the last writer, nothing re-derives an older version. Second request: from and to are
  both `[slideshow]`, same.

## Answers
1. Which attributes win: in the state the requested ones (loop above); in what is shown the last writer of the interned layout. With several windows that is the leaf re-derivation of
   the old stage, which carries the previous element's attributes. 16.2 differs in: the tail above (state dictionary only), `chamoisWindowingUIEnabled:` helpers, the
   peek/pick branch (G3C_EndPeekPick). The `policy` argument and the role fill are identical.
2. The second request works because the shown layout and the new layout are then the same interned instance. The requested attributes are stored in the previous state's element
   dictionary (`elementIdentifiersToLayoutAttributes`), which is why its base is 2 while the shown layout still says 0.
3. Is "centre first, zoom later" stock 16.2 behaviour? NOT provable from the code. The collapse animation itself (Sileo to the strip, 1.0 s) is the stock transition. The shown
   layout being overwritten by the old leaf is a property of the shared data model that exists byte for byte in 16.2 (interning init, leaf derivation, VC cache rebuild, state loop,
   `setEntities`, coordinator "transition did begin" 16.0 0x1c62362ec vs 16.2 0x1c76c9354 differ only by `setPreviousLayoutState:`), and the only new 16.2 code on the path (the tail)
   does not protect it. So stock 16.2 is exposed to the same order of writes; whether its model/coordinator code (not fully ported: `_filterAppLayoutForChamois:`,
   `_buildAppLayoutCache` item stripping) happens to avoid it was not decided. Hence the fix below is a deliberate addition.

## Fix (G3C.x, switch `g3c_stagesync`, default on, kill switch `Backport162.off.g3c_stagesync`)
In the request builder, after the 16.2 attributes are computed and stored in the context, the same attributes are written into the SHOWN stage layout
(`[[[windowScene switcherController] layoutState] appLayout]`) with `appLayoutByModifyingLayoutAttributes:forItem:`; that goes through the interning init and updates the shared map, so
every later leaf derivation of the old stage yields the request instead of the old attributes and the new layout ends up with the request as the last writer. Only when the stage has more
than one window (one window: nothing changes, same instance). If `requestTransitionWithOptions:...` refuses the request, the old attributes are written back. The 1.6 s verification
stays as the last line; it now logs `zoom request verified` when it was not needed.

Unzoom of a maximized window on a multi-window stage is the same request in the other direction and gets the same treatment.

## Log lines for the next device log (Backport162.debug)
- `[g3c] zoom: stage of 2 windows synced, policy 0 -> 2 (same shared layout 1)` at the press.
- `[g3c] zoom state built: element sceneID:... holds sizing policy 2` (proves the state dictionary holds the request, the premise above).
- `[g3c] zoom request verified: committed policy 0 -> 2, no repeat needed (first request)` 1.6 s later. If instead `zoom request had no effect ... repeating once` appears, the stage
  sync was not enough: send the log, the other writer of the shared layout has to be found (candidates: the model's pre-transition insertion in the coordinator).
- Single window: none of the `stage ... synced` lines, `verified` as before.

## Unproven
- Order of the writes (that the leaf re-derivation of the old stage is the LAST writer and not another path). The fix does not depend on which function does it as long as the old
  attributes come from the old stage layout; a stale source other than the old stage layout would need another sync.
- Whether the window now animates from its old frame to the zoomed frame (from / to maps come from the state dictionaries, `-[SBMainSwitcherControllerCoordinator
  _displayItemLayoutAttributesMapFromLayoutState:]` 16.0 0x1c62414e4) or snaps; visual check needed.
- Stock 16.2 behaviour for the same gesture.
