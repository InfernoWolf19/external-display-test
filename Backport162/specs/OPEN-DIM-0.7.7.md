# Window shadow pops in after the open, out at the start of the close (G2H.x, switches g2h_maskshadow and g2h_dimdiag)

Status legend: FACT = read from a binary / log / recording, INFERENCE = deduced from facts, UNPROVEN = needs the device.
16.0 = 20A8372, 16.2 = 20C65, unslid cache addresses. Recording: `8227294a-RPReplay_Final1792262963.mp4` (= `a045f096`, byte identical), a windowed web app (Reynard, claude.ai page,
window about 785 x 909 pt) opened from its Home Screen icon and closed three times in 6.5 s. NB: the file is stored rotated (stream 1920 x 1342 with a display matrix); ffmpeg delivers
1342 x 1920 portrait frames and every crop below is in those frames (1 pt = 1.609 px).

## 1. The user's observation, measured (FACT)

User: "the area around the window darkens like a sec after the window fully opens". Mean luma (ffmpeg signalstats YAVG, 60 fps, timestamps = pts of the file) of strips next to the
window (window rectangle at rest: x 39..1302, y 145..1607 px):

* right strip x 1306..1336, y 500..1300; below strip x 300..1100, y 1640..1740; left strip x 0..30, y 500..1300; top strip x 300..1100, y 50..130; dock strip y 1775..1875.
* Open 1 (the other two are the same, see the table): the home screen blurs and the wallpaper dims smoothly from t = 1.64 s (right strip 125.9 -> 101.2 by t = 1.95 s, below 129.8 -> 96.4,
  top 107.9 -> 88.1, no step). The window's first frame is t = 1.70 s; it is within 1 px of its final rectangle at t = 2.09 s and settled at t = 2.24 s (left edge 239 -> 39 px, top 856 -> 145 px).
* t = 2.077 -> 2.093 s, ONE frame: right 101.3 -> 86.4, below 96.4 -> 82.7, left 114.3 -> 98.2, top 88.2 -> 83.7, dock 174.3 -> 173.2. Spatial profile of that frame step
  (frame 94 -> 95): right strip, from the window edge outwards (3 px bins): -16.9 at the edge ... -12.7 at 40 px; below strip (8 px bins from y = 1598): -21.9 at the edge,
  -17.6, -15.0 ... -9.4 at 120 px; top strip: -8.3 at the edge ... -2.0 at 100 px. That is a large blurred drop shadow (stronger below the window: positive y offset), switched on
  in a single frame. Nothing else changes in that frame (the wallpaper far from the window does not move: the dock strip -1.0 is the dock's own shadow region).
* Pops: 2.093, 3.793, 5.577 s. Open start (first dimming frame) 1.64 / 3.34 / 5.12 s, so pop - open start = 0.45 s each time.
* Close: the shadow is gone again within two frames of the first frame of the close: right strip 86.6 (2.710) -> 89.9 (2.727) -> 101.6 (2.743 s), below 82.4 -> 88.5 -> 95.2, i.e. it
  disappears abruptly at the very start of the shrinking. Second and third close the same (4.493 s: 86.7 -> 101.7).
* So: no fade, no ramp, on both directions; shadow absent for the whole open animation and present for the whole time the window sits at rest; the "area around the window darkens"
  is this shadow (the margin is dark navy wallpaper, a shadow over it reads as darkening). The earlier rough measurement (YAVG 173 -> 105 -> 115..117 -> 113 -> 100) was of the
  home screen blur, not of this step.

## 2. What produces the shadow in stock (FACT, identical in 16.0 and 16.2)

* The window's drop shadow is the CALayer shadow (radius / opacity / offset) of two views below the item container: `SBAppSwitcherPageView _updateShadowPresence` (16.0 0x1c5f1afd8,
  16.2 0x1c738f690) adds an `SBAppSwitcherPageShadowView` (`initWithFrame:style:` 0x1c5ed38c4) whose `_updateShadowViews` (0x1c5ed3d00) / `_updateShadowParameters` (0x1c5ed43fc) create a
  diffuse and a rim shadow view and set `layer.shadowRadius / shadowOpacity / shadowOffset` on them (`setShadowPathIsBounds:`). So it is drawn OUTSIDE the container bounds.
  `SBFluidSwitcherItemContainer initialDiffuseShadowParameters` (0x1c615d1b8 / 0x1c75e41f8) reads back those layer values. Call sequences of `setShadowAlpha:` (0x1c5e36424 / 0x1c72a8894),
  `_updateShadowVisibility` (0x1c615c240 / 0x1c75e3270), `_updateShadowPresence` identical in both builds (`cmpseq`: same calls).
* It is driven by the switcher view controller's style pass: `-[SBFluidSwitcherViewController _applyStyleToAppLayout:roleMask:completion:]` (16.0 0x1c5fd5448, block 0x1c5fd5504; 16.2 0x1c744e508,
  block 0x1c744e5c4) asks the root `shadowOpacityForLayoutRole:atIndex:` and `shadowStyleForLayoutRole:inAppLayout:` (plus `opacityForLayoutRole:...`, `dimmingAlphaForLayoutRole:...`,
  `wallpaperOverlayAlphaForIndex:`, `lighteningAlphaForIndex:`) and applies them in block_invoke_2 (16.0 0x1c5fd5f30, `setShadowAlpha:` at 0x1c5fd5ff8; 16.2 0x1c744f040, 0x1c744f108)
  under `sb_animateWithSettings:mode:animations:completion:` with the opacity / layout settings of `animationAttributesForLayoutElement:` ("style" animation). Differences 16.2 vs 16.0 in
  that block: `chamoisLayoutAttributes stageInterItemSpacing`, `spaceAccessoryViewIconHitTestOutsetForAppLayout:`, `setPointerInteractionHitTestPadding:`, `setOccludedInContinuousExposeStage:`
  (renamed); nothing about the shadow.
* The values: `_SBHomeScreenFloorSwitcherModifier shadowOpacity...` = 0.0 (16.0 0x1c6089a98, 16.2 0x1c750cbf0), shadowStyle 1; `SBFullScreenContinuousExposeSwitcherModifier shadowOpacity...` 16.0
  0x1c613ed00 = constant 1.0, 16.2 0x1c75c3750 = 1.0 if `_isAppLayoutEffectivelyOnStage:` else `[super]` (ported: `G1C_FS_ShadowOpacity`, G1C.x), shadowStyle 5 (16.0 0x1c613ed08, 16.2 0x1c75c37fc).
  The home screen floor is replaced by the full screen floor at phase 2 of the transition (`SBFluidSwitcherRootSwitcherModifier handleTransitionEvent:` 16.0 0x1c61e7c14 calls
  `_updateFloorModifierWithTransitionEvent:` 0x1c61e8d74 at phase 2, and at phase 3 only for a non animated transition); the logs show phase 2 only 29 / 10 / 10 ms after phase 1
  (291a0cf5 19:40:25.653 -> .682, 26.993 -> 27.003). So in stock the shadow is requested (1.0, style 5) from ~30 ms into the open and faded in by the "style" animation; nothing in stock
  switches it on after the animation. 16.2's new `SBContinuousExposeToHomeSwitcherModifier shadowStyleForLayoutRole:inAppLayout:` (0x1c7412f50) is for the modes 1 <-> 2 transition only.
* Wallpaper / home screen dimming of the open (the smooth part of the curves above): `SBHomeScreenZoomSwitcherModifier` (16.2 0x1c7894c10 ...: homeScreenAlpha 0x1c7894d64,
  homeScreenBackdropBlurProgress 0x1c7894dec, homeScreenDimmingAlpha 0x1c7894e98, homeScreenScale, wallpaperScale 0x1c7894fb8, wallpaperStyle 0x1c7895040), driven by the same spring as the
  zoom; no step in the recording, not touched by our hooks (only `G1C_Hs_Dimming` for the home floor of the switcher).

## 3. The cause (INFERENCE, strong; our port, not stock)

G2F.x `g2f_closecrop` (0.7.6, build 24816c1, the build of this recording): during an icon zoom of a single window the item container gets a rounded `maskView` over the container bounds whose
bounds animate to the icon box and, after the zoom, back to the container bounds, where it is dropped (`[g2f] crop: mask released`). A layer mask clips the whole composite of the container
including everything drawn outside its bounds, that is the shadow. So:

| | log (291a0cf5 / 8025ca8b, same build) | recording |
|---|---|---|
| open: mask created over container bounds in the first layout pass (phase 1 + 14 / 10 ms), animation back to container bounds starts at "zoom over" (phase 1 + 33 ms) | Dopamine 19:40:25.653 / .661 / .686; Filza (1056 x 646 window) 36.366 / .380 / .402 | shadow absent from the first frame |
| open: "[g2f] crop: mask released" = the settle of that spring | +562 ms (291a0cf5) and +572 ms (8025ca8b) (Dopamine), +579 ms (Filza) after phase 1 | shadow appears 0.45 s after the first dimming frame (first dimming ~0.1 s after phase 1) |
| close: mask created over the container bounds in the first layout pass (phase 1 + 11 ms) and animated to the icon box | 26.381 / 26.392 | shadow gone within 2 frames of the first frame of the close |

The mask is exactly the container bounds at both ends, so the shadow (outside the bounds) is clipped for the whole time the mask exists and appears in the frame the mask is dropped; at the
close it is clipped from the first frame. A mask that stays after a close until the next open (the logs show "zoom over" without "created" for later opens) behaves the same. Before
g2f_closecrop (0.7.5 and earlier) there is no mask; the shadow then follows stock. I did not find a pre-crop recording of a window that does not fill the screen to check that directly
(0dee8146 / af7310bc / 83f40670 are full-screen Dopamine windows, where the shadow is off screen).

What else could switch a shadow on in one frame and was ruled out: the style animation (spring / update modes smooth, identical to stock); the floor swap (phase 2, 30 ms after the start, would
pop at the START of the open); the wallpaper dimming queries (smooth, and they would darken the whole screen, not a halo decaying with the distance from the window).

## 4. The fix (G2H.x, switch g2h_maskshadow, default ON, deliberate repair of our deviation)

The crop stays (the user confirmed it fixes the nested card, a62c5f6); the mask is given room for the shadow wherever it is not cropping. The plain `UIView` that G2F sets as the item container's
`maskView` (hook of `-[SBFluidSwitcherItemContainer setMaskView:]`, G2F.x untouched) is switched with `object_setClass` to the runtime subclass `BP162ShadowRoomMaskView` (no ivars added: the
instance size is unchanged), whose `-setBounds:` adds the slack on every side when the requested size covers the container (creation and the target of the "zoom over" animation) and keeps the
icon box exact, and whose `-bounds` returns the logical size, so G2F's comparisons of `mask.bounds` with the container bounds keep working. Slack =
`max over the layers that really shadow (radius > 0, opacity > 0) of 2.8 x shadowRadius + max(|offset.x|, |offset.y|)`, 2.8 being the factor stock uses for the shadow-inclusive bounds
(`_visibleSwitcherBoundsIncludingShadow` 16.2 0x1c78133f4, constant -2.8; see G1C.x). Result: close starts with a mask that clips nothing (no step in the first frame), the spring then shrinks it
to the icon box and the shadow is swept away with the zoom; open: the shadow is revealed with the growing mask and, when G2F drops the mask, nothing changes in that frame.
Log lines (Backport162.debug): `[g2h] mask adopted on container ... shadow slack <E> on every side (<n> shadow layers)`, `[g2h] mask removed ...`.
Kill switch: `<jbroot>/tmp/Backport162.off.g2h_maskshadow` (hot: checked at every bounds change; the hook itself needs no respring).

## 5. Diagnostics for the next test (G2H.x, g2h_dimdiag, default ON, only with Backport162.debug)

For every animated 1 -> 3 (open) and 3 -> 1 (close) transition of the root: a line per phase and one every 50 ms for 1.5 s after phase 1:
`[g2h] dim#N open|close t=+0.350 idx= role= | shadowOpacity= shadowStyle= opacity= dimming= wallpaperOverlay= lightening= background= | home alpha= dim= blur= blurType= scale=
wallpaperScale= wallpaperStyle= | container <ptr> shadowAlpha= shadowStyle= alpha= presBounds= shadows(n, extent) [shadowview r op off alpha pres] ... mask(class logical layer pres r)`.
Read it like this: if the shadow layers show `alpha 1` / `op > 0` and `shadowOpacity=1` from phase 2 on while the recording shows no shadow until the mask line disappears
(`mask(none)`), the mask is the cause. If the shadow layer values themselves jump at the pop (alpha 0 -> 1, or `shadowOpacity` 0 -> 1), the cause is in the root's answers and this fix
is not it (kill switch `g2h_maskshadow` to compare, `g2f_closecrop` off removes the mask altogether).

## 6. Unproven

* That the mask is the only thing hiding the shadow. The logs that came with the recording (`89646064` / `84256315`, 19:54:51 - 19:55:06, no `[g2f]` line, no mode 1 -> 3 transition, only
  3 -> 3 app-to-app transitions of a three window stage) do not belong to it (the recording's status bar says 19:49, the logs start at 19:54:51), so the log side of section 3 comes from
  other runs of the same build (291a0cf5, 8025ca8b). The recording itself fits the mask in time (0.45 s vs 0.56 - 0.58 s from phase 1, the first dimming frame lagging phase 1 by ~0.1 s)
  and in shape (a step to the full shadow, at the start of the close an immediate removal).
* The size of the shadow slack (the radius of the window shadow is not known; it comes from the layers at run time; if no shadow layer exists yet at the time the mask is adopted the slack
  is 0 for that call and the next bounds change looks again).
* That UIKit never reads `-bounds` of a mask view in a way that matters (the mask view has no subviews and is positioned only through its layer; G2F sets bounds and centre only).
* How the swept shadow looks on the device (the shadow around the full-width card is revealed / hidden by the moving mask edge; at the close the mask edge reaches the shadow of the card
  within the first ~100 ms).
