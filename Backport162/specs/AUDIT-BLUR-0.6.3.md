# AUDIT-BLUR-0.6.3: whole window blurred after three-dots Close and opening the same app again (build 4033278)

Symptom: Stage Manager window (windowed) closed through the three-dots menu > Close, then the same app is opened again: the whole window (toolbar included)
is rendered blurred, touches still work. Killing the app from the app switcher and opening it again fixes it. Stock 16.0 does not show it.
Method: static. 16.0 = 20A8372 (annot3.py), 16.2 = 20C65 (annot162.py). All addresses below are 16.0 unless marked 162.

## Two different blurs exist (this explains "elements still respond to touch")
1. Container/live-overlay blur driven by the layout pass: `-[SBFluidSwitcherItemContainer setBlurred:duration:blurDelay:iconViewScale:began:completion:]` (0x1c615a70c;
   SBApplicationBlurContentView snapshot blur, `_blurred` byte ivar, early return when unchanged) and `-setLiveContentBlurEnabled:...` on the live-content overlay
   (`_liveContentOverlays[leaf]`). Both are fed by `-[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:]` block 0x1c5fca514.
2. A CAFilter "gaussianBlur" + shouldRasterize on the item container's LAYER: `-[SBFluidSwitcherViewController _blurItemContainer:blurParameters:withAnimationUpdateMode:]`
   (0x1c5fc6858: filterWithType:, name "gaussianBlur", inputRadius, setFilters:, setShouldRasterize:YES). Driven by SBBlurItemContainerSwitcherEventResponse
   (-[VC _performBlurItemContainerResponse:] 0x1c5fe4678 blur / 0x1c5fe4680 unblur). The unblur (0x1c5fc6b1c) animates `filters.gaussianBlur.inputRadius` to 0 and, in its
   completion (0x1c5fc6c9c), does setFilters:nil + setShouldRasterize:NO. This blur covers the whole container (toolbar included) and the live scene stays touchable. This is the one in the report.

## Finding 1 (confirmed bug, fixed): inverted blur target test in the layout pass (G2B.m:1170)
* 160 block 0x1c5fcb5dc `blurTargetPreferenceForLayoutRole:inAppLayout:` -> x21; 0x1c5fcb764..0x1c5fcb774: `w24 = (live != nil)` (cmp x0,#0; cset ne), `w19 = (x21 != 1)` (cmp x21,#1; cset **ne**);
  0x1c5fcb9ac..0x1c5fcb9b8: `liveBlur(w20) = blurred & w24 & w19`, `container blur(w22) = blurred & !liveBlur`. Calls: 0x1c5fcb9fc setLiveContentBlurEnabled:(liveBlur) only if live != nil,
  0x1c5fcba1c setBlurred:(w22).
* 162 identical: 0x1c74444fc `cmp x25,#1; cset w27,ne`, 0x1c7444710..0x1c744471c, calls 0x1c744475c / 0x1c744477c.
* Defaults: SBDefaultImplementationsSwitcherModifier blurTargetPreference = 0 (0x1c63dfd64), SBCardDragAndDrop / SBCardDrop return 1 (0x1c639b874 ...), SBRouting forwards to the modifier that contains the layout.
* Ours (G2B.m:1170 before the fix) was `blurTarget == 1`: every blurred Stage Manager window got the container snapshot blur and the live overlay blur was only used for card drag-and-drop.
  Fix: `blurTarget != 1`. Nothing else in the blur section differs from 160 (arguments 0.25 / blurDelay / blurViewIconScale, began = BlurProgress(0.0), done = BlurProgress(1.0): block 0x1c5fcd0b8 initWithProgress:1.0 checked).
  `setBlurred:NO` and `setLiveContentBlurEnabled:NO` are still sent on every pass (live only when the overlay exists, as in 160), so this finding alone does not leave a blur on (it removes a divergence, not the stuck state).

## Finding 2 (most probable cause of the stuck blur, fixed): the Close transition blurs the container and 16.0 never un-blurs it at the end of the transition
* Close path in 16.0: -[SBContinuousExposeRootSwitcherModifier transitionModifierForMainTransitionEvent:] (0x1c6371228) for env mode 3->3 with a removal context
  (removalContextForAppLayout: / animationStyle) builds `SBWindowDeleteSwitcherModifier` (initWithTransitionID:fromAppLayout:layoutRole: at 0x1c63713ec / 0x1c63714f4). We do not replace it (G1C.x:3440 only replaces the SBContinuousExposeAppToAppModifier result).
* SBWindowDeleteSwitcherModifier (16.0) ivars: _fromAppLayout 0x88, _layoutRole 0x90, _centerWindowAppLayout 0x98 (= [from leafAppLayoutForRole:], the container key; init 0x1c643579c),
  _fullScreenAppLayout 0xa0. `-transitionWillUpdate` (0x1c6435b6c) appends `SBBlurItemContainerSwitcherEventResponse(appLayout=_centerWindowAppLayout, shouldBlur=YES, mode 3)` (0x1c6435bcc).
  16.0 has NO `-transitionDidEnd` in this class (class dump), i.e. nobody sends the un-blur.
* 16.0 relies on `-[VC _removeVisibleItemContainerForAppLayout:]` (0x1c5e70268, called from `_updateVisibleItems` 0x1c5e31940 when the layout leaves `visibleAppLayouts`): it calls
  `_unblurItemContainer:blurParameters:withAnimationUpdateMode:` (0x1c5e702f4, defaultCrossblurBlurParameters, mode 2) before recycling the container into `_hiddenRecycledItemContainers`.
  `-[SBFluidSwitcherItemContainer prepareForReuse]` (0x1c5e704c8) does not touch layer filters nor `_blurred` / `_blurView` (checked, 162 0x1c72e3220 neither).
* 16.2 changed exactly this: SBWindowDeleteSwitcherModifier got `-transitionDidEnd` (162 0x1c78e702c) = `[super transitionDidEnd]` + SBBlurItemContainerSwitcherEventResponse(appLayout=_centerWindowAppLayout (ivar index 0xc5c, set from leafAppLayoutForRole: at 162 0x1c78e6b58), shouldBlur=NO, mode 2),
  and `_removeVisibleItemContainerForAppLayout:` (162 0x1c72e2f98) un-blurs twice. `transitionWillUpdate` 162 0x1c78e6f80 is the same blur YES, mode 3.
  So in 16.2 the closed window's container may outlive the transition (it is reused for the same app layout later) and the transition itself clears the blur. The ported model (G1B/G1C/G2) behaves like 16.2 in that the container is not always removed
  by `_updateVisibleItems`, but the 16.0 WindowDelete modifier we still run has no DidEnd un-blur. The scene stays alive after "Close" (only the window is removed), so opening the app again gets the same display item = the same leaf app layout = the same
  container (or a recycled one whose async un-blur completion did not run first) that still has the gaussianBlur filter. Killing from the app switcher goes through SBSwipeToKill (handleSwipeToKillEvent blurs, the container is then removed with the 16.0 unblur path)
  and the app comes back with a new scene, so it is not affected.
* Why the 16.0 CrossBlur child does not help on relaunch: stock opens an app into Stage Manager through SBContinuousExposeAppToAppModifier whose 16.0 child SBContinuousExposeCrossblurModifier (0x1c63681dc blur YES mode 2 at transitionWillBegin, 0x1c63682b8 blur NO mode 3 at transitionWillUpdate,
  appLayout = _toAppLayout) explicitly un-blurs the incoming window. G1C.x:3440 replaces that modifier with BP162ContinuousExposeAppToAppModifier (16.2 children: no BlurItemContainer response at all), so the implicit "clear any stale blur of the target" of stock is gone.
* Other users of the response (16.0 callers of initWithAppLayout:shouldBlur:animationUpdateMode:): SBEntityRemovalDeleteFloating, SBCrossblurDosido, SBEntityRemovalCrossblur (all have transitionDidEnd with the NO), SBSwipeToKill, SBContinuousExposeCrossblurModifier, SBWindowDelete (the only one without the NO).
* Fix (G1B.x, group G1B_WindowDelete, installed from G1B_Setup): %hook SBWindowDeleteSwitcherModifier -transitionDidEnd: `%orig` + SBBlurItemContainerSwitcherEventResponse(_centerWindowAppLayout, NO, 2) appended with G1B_AppendTo. Gated by G1B_ON().

## Finding 3 (second, independent safety net, fixed): a recycled container must not keep a layer blur
* The async un-blur (animation completion 0x1c5fc6c9c) can lose against reuse: the container is recycled right after the un-blur starts and the same app layout can be re-added at once.
* Fix (G2B.m, BP2B_SetupContainerPointer, our existing prepareForReuse replacement): after the original, if the container layer still has a CAFilter named "gaussianBlur", `filters = nil; shouldRasterize = NO`.
  prepareForReuse is only called when the container is already hidden and queued (0x1c5e70340), so it cannot cut an on-screen blur animation.

## Ruled out
* G2B `_layoutAppLayout` not clearing `setBlurred:` / live blur: both are sent on every pass for every leaf with a container (G2B.m:1177-1181), `done` / `began` match 0x1c5fcd0b8.
* SBRemovalSwitcherModifier.isLayoutRoleBlurred (0x1c63eb6ec): YES only for the tracked layout (`_appLayout` while phase 1 and role != removed role, `_resultingAppLayoutIfAny` afterwards) until content ready and resized; for a one-window layout `_resultingAppLayoutIfAny` is nil and the removed role is excluded -> NO. Not the source for a windowed Close.
* G1B_Handled (ignoring a second handleWithReason:), G2 validity token / layout cache, the always-dispatched identifiers-changed event: none of them reads or writes blur state; no isLayoutRoleBlurred / blur response / container filter code in G1C/G2/G3 except the DnD modifier G1C_Dnd_Blurred (only active during a drag).
* The G1C isLayoutRoleBlurred (G1C.x:2088) belongs to the app drag-and-drop gesture modifier only.

## Files changed
* G2B.m: blur target test `!= 1`; prepareForReuse clears a stale gaussianBlur layer filter.
* G1B.x: new group G1B_WindowDelete (transitionDidEnd un-blur), `%init(G1B_WindowDelete)` in G1B_Setup. logos.pl run on G1B.x: OK.
Confidence: Finding 2 about 65 percent (mechanism fits every observation and 16.2 contains exactly this fix; the exact reason the container survives could not be proven statically), Finding 1 certain as a divergence, Finding 3 safety net.
