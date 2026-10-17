# Home swipe close: the nested outer card (G2F.x, switches g2f_closepivot and g2f_closecrop)

Status legend: FACT = read from a binary / log / recording, INFERENCE = deduced from facts, UNPROVEN = needs the device.
16.0 = 20A8372, 16.2 = 20C65, unslid cache addresses. Covers both parts of G2F.x: the pivot (0.7.6, earlier commit) and the crop (this commit).

## 1. What the screenshot shows (FACT)

`24.webp` is a screenshot of Photos playing recording 83f40670 (RPReplay_Final1792246553, 1920x1342, 60 fps, 1920 px = 1194 pt, 1 pt = 1.608 px). The frame in it is t = 2.276 s of
that recording, the Dopamine window (1056 x 646 pt, log: `DEFAULT WINDOW SIZE 16.2 = {1056, 646}`) closing to its icon. Two nested shapes, concentric:

* outer: the card, window aspect, darker, 641 x 392 px (1.64);
* inner: lighter, 478 x 392 px (1.22), carrying the icon glyph (a circular ring) and a faint copy of the app content.

The user's reading ("the content is narrower than the card") is right, but it is the icon overlay that is narrower, not the app content: the app's own text sits at the same relative position (22 % from
the left) in the card and in the overlay.

## 2. Measurements over the close (recording 83f40670, close starting t = 2.126 s; unique frames, 16.67 ms apart; pure-python pixel scans of the rows through the card)

Outer card (the window, uniform scale):

| t (s) | 2.126 | 2.143 | 2.160 | 2.176 | 2.193 | 2.210 | 2.226 | 2.243 | 2.260 | 2.277 | 2.293 | 2.310 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| outer width px | 1664 | 1664 | 1522 | 1370 | 1222 | 1082 | 952 | 834 | 730 | 640 | 563 | 495 |
| left edge x | 132 | 132 | 232 | 342 | 454 | 560 | 660 | 752 | 834 | 905 | 967 | 1022 |
| right edge x | 1796 | 1796 | 1754 | 1712 | 1676 | 1642 | 1612 | 1586 | 1564 | 1545 | 1530 | 1517 |
| frame ratio | | 1.0 | .915 | .900 | .892 | .885 | .880 | .876 | .875 | .877 | .880 | .879 |

The card keeps its aspect (1.63-1.64) in every frame; its centre travels from x = 964 to the icon (the left edge moves in faster than the right one only because the centre moves right; with
g2f_closepivot the shrink is about the window's own centre).

Inner shape (icon overlay), measured where it is visible:

| t (s) | 2.243 | 2.260 | 2.277 | 2.293 | 2.310 |
|---|---|---|---|---|---|
| inner width px | 674 | 566 | 478 | 407 | 350 |
| inner / outer width | 0.81 | 0.775 | 0.747 | 0.72 | 0.707 |
| crop progress p = (1 - ratio) / (1 - 646/1056) | 0.49 | 0.58 | 0.65 | 0.72 | 0.755 |
| scale progress q = (1 - S) / (1 - 0.1176), S = outer / 1698 | 0.58 | 0.65 | 0.71 | 0.76 | 0.80 |

* inner height = outer height from t = 2.277 on (392 px); at 2.243 inner 477 / outer 511 px.
* The inner shape is not visible before t = 2.243: at 2.143 ... 2.226 the card shows the app alone (contrast-stretched frames confirm), because the overlay at that time still shows the same pixels
  as the card (crossfade not started). Its clip edge was moving inward all that time, unseen; it becomes visible when the icon fades in, i.e. when it already has p = 0.49. That is why it looks like a
  sudden narrowing "popping in" inside the window.
* The ratio converges towards 646 / 1056 = 0.612 = icon box / window, p follows q with a lag of 0.04-0.09: same spring family.
* The glyph ring is circular (130 x 132 px at 2.310) inside a 224 x 195 px light rounded rectangle: an icon image, not a stretched one.
* Recording 0dee8146 (made before g1c_fillbounds and g2f_closepivot) shows the same nested pair (outer 1.63, a lighter inner 0.77 of its width near the end of the close, frames 0.95-1.1 s). So neither hook causes it.

## 3. Mechanism (FACT from the binaries unless marked)

1. The card: the item container (`SBFluidSwitcherItemContainer`) keeps the window size. Log, every close: `[g1c] close roleFrame phase=2 idx=1 {{0, -0.5}, {1056, 646}} in bounds {646, 646}` (windowed) and
   `{{0,0},{1194,834}} in bounds {834,834}` (full screen): the zoom hands the icon box as bounds, the answer is the window frame. Block 0x1c744326c / `block_invoke_19` 0x1c744634c (16.0 0x1c5fca514)
   sets `bounds = R.size`. Scale is uniform, so the card's aspect stays constant: the outer shape.
2. The icon overlay: `-[SBFluidSwitcherViewController _performModifierIconOverlayVisibilityUpdateResponse:]` (16.2 0x1c745cb0c, 16.0 0x1c5fe3358) takes the icon view and the page views of the layout's leaf
   containers and calls `-[SBFluidSwitcherSpaceOverlayAccessoryView configureOverlayForIconZoomWithView:crossfadeViews:]` (0x1c758c308), which builds a `SBFluidSwitcherIconOverlayView`
   (`initWithIconView:crossfadeViews:crossfadeViewFrame:...` 0x1c7736470) at `overlayAccessoryViewFrameForIconOverlayView:fullPresented:YES` (0x1c7451420 = size of
   `fullyPresentedFrameForIndex:frame:` = the window, 1056 x 646).
3. The layout block animates the accessory view's bounds (block "accessory bounds", `layoutSettings` / layout update mode, 16.2 0x1c7445248 ..., 16.0 call of
   `adjustedSpaceAccessoryViewFrame:forAppLayout:` 0x1c5fcc624) to `adjustedSpaceAccessoryViewFrame:forAppLayout:` = `frameForIndex:` = the icon box (16.2 `SBFullScreenToHomeIconZoomSwitcherModifier`
   0x1c75b2f78 answers `frameForIndex:` for its own layout; the 16.0 class has no override and the default returns the passed frame, which is the same box). The accessory centre is the box centre = icon
   centre, concentric with the card.
4. The icon morph is driven by that bounds' ASPECT: `-[SBFluidSwitcherIconOverlayView _currentFadeValue]` 0x1c7736730 = (bounds.w / bounds.h - a0) / (a1 - a0), a0 = initial icon view aspect, a1 = crossfade
   frame aspect (window); `layoutSubviews` 0x1c72d74b0 feeds it to `setMorphFraction:`, `_iconOverlayScale` 0x1c72d73f0 (lerp by the same value) and the page views' alpha
   (`_setCrossfadeViewsAlpha:` 0x1c7736b28). So the overlay (not the card) is cropped from the window aspect to the box aspect, and the card's content fades out under it. The numbers in section 2 fit:
   ratio -> 0.612, the overlay becomes visible when the aspect crossfade passes ~0.5.
5. 16.0 and 16.2 identical: the overlay view methods are not in WORKLIST.md's diff list; `overlayAccessoryViewFrameForIconOverlayView:fullPresented:` differs only in the fallback for a missing container
   (`bounds` vs `containerViewBounds` + a log line); the VC layout block is the same up to the 16.2 additions (role clipping, group opacity, accessory scale ratio) that the zoom does not answer.
   Stock iPadOS therefore shows the same nested pair (INFERENCE from identical code; consistent with the user's earlier statement that stock has the glitch).

## 4. Which of our hooks matter (answers to the brief)

* g1c_fillbounds YES (`shouldScaleContentToFillBounds`, `shouldUseNonuniformSnapshotScaling`): sets `setShouldStretchToBounds:` / `setUsesNonuniformScaling:` of the snapshot view
  (`SBAppSwitcherReusableSnapshotView` 16.2 0x1c792107c / 0x1c7921104). With bounds fixed at the window size it has nothing to stretch: it does not change the visible aspect. 0dee8146 (without it) shows the same.
* G1B pin YES: this is the stock 16.2 answer (0x1c75b2e00 / 0x1c75b2e74); it makes G2B fall back to the 16.0 layout block for the zoom (pinned branch not ported), which has the same accessory bounds animation.
* g2f_closepivot: changes only the layer anchor / position of the card; the outer shape stays symmetric. It does not change aspect or the overlay.
* g2e_closesmooth: changes the gesture phase spring only; before the zoom.

## 5. Fix (g2f_closecrop, default ON, DELIBERATE deviation from stock 16.0 / 16.2)

The cheapest consistent design: crop the card with the overlay, so the silhouette is one shape that goes from the window's aspect to the icon box together with the zoom (the outer card disappears).
`G2F_Layout` wraps `-[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:]` after G2B (whatever IMP is installed runs first, unchanged). For an icon zoom (the pivot's test: pin through the
anchor and fullyPresented size != frame size) of a layout with ONE leaf (several windows keep the stock look), it
* creates a black rounded `UIView` as `maskView` of the item container (nothing in the switcher touches `maskView`; the mask lives in container coordinates, i.e. before the layer scale), over the container
  bounds, initial corner radius = the container's presentation radius read before the pass;
* animates `mask.bounds` to the centred box `min(frame.w, bounds.w) x min(frame.h, bounds.h)` (646 x 646 pt) with the SAME `sb_animateWithSettings:mode:` call the layout block uses for the accessory
  bounds (`layoutSettings`, `layoutUpdateMode` else `updateMode` of `animationAttributesForLayoutElement:`), so card mask and overlay bounds run the same spring from the same instant; the corner
  radius with `cornerRadiusSettings` toward the container's new `contentCornerRadii` minimum (the radius the accessory gets);
* when a later pass has no zoom answers (e.g. phase 2 of an open from the icon) animates the mask back to the full bounds and removes it; `prepareForReuse` of the container removes it too.
Needs the centred pivot (g2f_closepivot ON), because only then the card is concentric with the box. Roles: only the roles of the pass's role mask. Classic switcher: untouched.
Kill switch: `<jbroot>/tmp/Backport162.off.g2f_closecrop`.

Expected (computed from the measured series, not observed): inner and card share the silhouette; the silhouette's width ratio follows the same p curve as the overlay (0.81 at the frame the overlay used to
appear, 0.61 at the end); the card edges outside the box are gone from the first frame instead of fading under the overlay. The crop starts with the transition, so the silhouette narrows gradually
(p at 50 / 100 ms of a critically damped spring with response 0.425 s, an approximation of the layout spring z 1.1 r 0.375-0.425, is about 0.17 / 0.43) instead of the inner shape popping in at p = 0.49.

## 6. Diagnostics (Backport162.debug)

Armed by G1C (`[g1c] close: trace armed`), for the stage layout only: right after the layout pass of phase 1 and phase 2 and, for phase 2, again after 50 ms and 100 ms (about 3 and 6 frames), lines
`[g2f] close dump p2+0 ...`, `p2+3f`, `p2+6f`: the root's answers (frame, fullyPresented, scale, anchor, adjusted accessory frame, clipsToBounds), then for the item container and every overlay / underlay
accessory view: class, frame, bounds, centre, alpha, hidden, clipsToBounds, corner radius, presentation bounds / position / scale / opacity / corner radius, content clipping state, mask view state, the
icon overlay's `_currentFadeValue`, and the subview tree (4 levels, 70 lines per dump). One recording + log shows which view is narrower and by how much even if the crop is wrong.
Crop lines: `[g2f] crop: mask created ...`, `crop: zoom over ...`, `crop: mask released`.

## 7. Unproven / device checks

* That the overlay's bounds animation is what produces the inner shape: derived from the aspect formula and the measured ratios, not yet logged. The `p2+0` dump shows the accessory view's bounds (expect
  1056 x 646 -> 646 x 646) and the icon overlay view's fade value.
* That animating `maskView.bounds` and `layer.cornerRadius` through `sb_animateWithSettings:mode:` animates (UIKit machinery on a mask view; expected, as the layout block animates accessory views the same
  way). If the mask jumps, the p2+3f dump shows its bounds / presentation bounds.
* That the item container's content (live scene overlay included) is fully inside the container's layer so the mask covers it. The dump's subview tree shows it.
* Whether real 16.2's calculator really answers the window size for `frameForLayoutRole:...withBounds:` {box}: our G2B port does (log), the default `SBDefaultImplementationsSwitcherModifier
  frameForLayoutRole:` 0x1c788a480 passes the `bounds` argument to the calculator as containerBounds (disassembled), so a 16.2 calculator that clamped the window to those bounds would make the
  container itself morph to the box with the snapshot stretched (g1c_fillbounds YES) and no nested card would exist in real 16.2. Not checked in the 16.2 calculator (0x1c75a3614).
* The open (home -> app) uses the same code: the mask is created at the box on phase 1 and removed with an animation on phase 2; unobserved. A container created inside the pass has no presentation
  radius (the mask starts at the target radius).
* Multi-window layouts keep the stock nested look.
