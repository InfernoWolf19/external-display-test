# Home swipe close: abrupt start (G2E.x, switch g2e_closesmooth)

Status: FACT = read from the binaries / logs / video, INFERENCE = deduced, UNSURE = needs the device.

## Evidence
- Video af7310bc (60 unique fps), window area per frame (px): 93.9k, 92.9k, 91.4k, 80.4k, 71.1k, 62.8k, 52.2k, 41.7k, 33.5k, 27.2k, 22.9k. Scale per frame 1, .995, .987, .925, .870, .818, .746, .667, .597, .538, .494.
- Log 4e9ad132 (Dopamine, 3->1): gesture samples 08.019 0.9933, .041 0.9085, .052 0.8538, .061 0.8291, .069 0.8073, transition phase 1 at .077, phase 2 (target 0.1176) at .081.
  Second close of the same log: 0.9895 (09.002), 0.8171 (09.030), phase 1 at 09.045, phase 2 at 09.048. The model itself steps 0.9933 -> 0.9085 (and 0.9895 -> 0.8171) in ONE update: the finger travelled during the ~20-28 ms the main thread needed to prepare the gesture.
- The presentation follows the model with almost no lag (video scale .925 / .870 / .818 against model .9085 / ~.845 / ~.815), so the layer is not behind a spring during the gesture.

## Hand-off between two animation systems (FACT, identical in 16.0 and 16.2)
Update modes (+[UIView(SBFFluidBehaviorSettings) sb_animateWithSettings:mode:animations:completion:] 16.0 0x18eb3aab4, 16.2 0x18edd9a58; jump table 16.0 0x18eb8aa74): 0 assert, 1 run block without animation, 2 without retargeting, 3 animated spring (`sb_animateWithSettings:interactive:NO`), 4 retarget existing, 5 interactive (`interactive:YES` = tracking spring).
1. Interactive phase = update mode 5 (-[SBGestureSwitcherModifier animationAttributesForLayoutElement:] 16.0 0x1c63807a4, 16.2 0x1c7828718). Spring parameters: `-[SBHomeGestureSwitcherModifier _layoutSettingsForAppLayout:layoutSettings:]` 16.0 0x1c603b068, 16.2 0x1c74b665c:
   - `isEqual:_selectedAppLayout` and starting mode 2 with stackedProgress > 0: `stackedSwitcherTrackingSettings`;
   - `isEqual:_selectedAppLayout` otherwise: the passed default `layoutSettings` (`-[SBFFluidBehaviorSettings setDefaultValues]` 16.0 0x18eb3b248: response 0.531, damping 0.845, trackingResponse 0.15, trackingDamping 0.86);
   - everything else (and the selected card without the fly-in property): a fresh `SBFFluidBehaviorSettings` with `setDefaultValues` and `setTrackingResponse:0` (0x1c603b1fc), i.e. NO spring: the layer is set straight to every model value.
2. Transition = update mode 3. 3->1 with an icon: `SBHomeGestureToZoomDownSwitcherModifier` (16.0 0x1c646fbd0, 16.2 0x1c7925388) wraps `SBFullScreenToHomeIconZoomSwitcherModifier` and, with adjustAnimationAttributes, `SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier` (16.0 init 0x1c63f8e84, `_layoutSettings` 0x1c63f93b8, `_positionSettings` 0x1c63f9540, `_scaleSettings` 0x1c63f96ec, `_settingsByInterpolatingBetween:and:progress:` 0x1c63f97e0; 16.2 0x1c78a5934 ...). The liftOff velocity only scales the response (layout response x0.7 at -vy >= 5000, position x1.2 at |vx| >= 4000; thresholds `zoomDownVelocityY 3000..5000`, `X 1000..4000`, read from `_setHomeGestureAnimationDefaultValues` 0x1c5f106fc), it is NOT an initial velocity. iPad rows: layout z 1.1 r 0.425 (top) / 0.375 (bottom), position z 0.88 r 0.45 / z 0.86 r 0.50, scale z 0.96 r 0.40 / z 0.90 r 0.50 (retargetImpulse 0.016-0.02).
   The real initial velocity of that spring is the layer's own velocity when UIKit retargets it. After phase 1 (mode 5, response 0) the layer has none.
3. Verified identical in 16.0 and 16.2 (selector sequences / instruction diff, only registers and ivar offsets differ): `_layoutSettingsForAppLayout:layoutSettings:`, `SBHomeGestureSwitcherModifier animationAttributesForLayoutElement:`, `SBGestureSwitcherModifier animationAttributesForLayoutElement:`, `sb_animateWithSettings:mode:` / `interactive:`, the whole SBGestureInitiatedIconZoomAnimationAttributesSwitcherModifier, the VC layout block (16.2 only adds clipping / group opacity / accessory scale). The floors' attributes (`_SBFullScreenAppFloorSwitcherModifier` 16.2 0x1c75cce6c, `_SBHomeScreenFloorSwitcherModifier` 0x1c750cad0) are update mode 1 and not involved in the hand-off. So this is stock behaviour, not a port defect.

## Consequence (INFERENCE, matches the numbers)
With response 0 the layer jumps with the model (0.9933 -> 0.9085 in one update = one visible frame step) and carries no velocity into the zoom-down spring, which therefore restarts from rest (the dip of the area deltas after the step, then the rise): two animation systems, no velocity continuity.

## Fix (default ON, deviation)
`G2E_LayoutSettings` wraps `_layoutSettingsForAppLayout:layoutSettings:` of SBHomeGestureSwitcherModifier. Only when the result is the fresh instant object (not the passed settings), the gesture is running, the starting environment mode is 3 and its trackingResponse is 0: trackingResponse / trackingDampingRatio := the values of the passed default layoutSettings (0.15 / 0.86), the spring the same method uses for the selected card. Nothing else changes.

Expected numbers (spring integrated, layer = tracking spring following the logged samples, then scale spring z 0.93 r 0.45 toward 0.1176 with velocity continuity, worst case over the 60 fps frame phase; re-computed at start-up in the `[g2e] expected` log lines):

| series | trackingResponse | worst per-frame scale ratio | max change of the ratio between two frames |
|---|---|---|---|
| log fed63049 (0.9933 0.9085 0.8538 0.8291 0.8073, hand-off at +62 ms) | 0 (stock) | 0.860 | 0.140 |
| same | 0.15 | 0.880 | 0.026 |
| log 4e9ad132 (0.9895 0.8171, hand-off at +46 ms) | 0 (stock) | 0.826 | 0.174 |
| same | 0.15 | 0.879 | 0.037 |

## UNSURE / device checks
- That the closing stage window takes the instant branch (not the selected-card branch): the first `[g2e] home gesture (mode 3 start): card ... instant tracking` line per gesture shows it. If it never appears, the window is already on a spring and the cause is elsewhere.
- The window now trails the finger by ~25-30 ms (time constant 1/(zeta*omega) = 0.15/(2*pi*0.86)) during the gesture; this is the cost of the fix.
- The model step itself (finger distance during the gesture preparation) is untouched; a limit of the first update would be a separate change in the gesture modifier / G1C.
- Modes 1 (from home) and 2 (from the switcher) are not touched.
