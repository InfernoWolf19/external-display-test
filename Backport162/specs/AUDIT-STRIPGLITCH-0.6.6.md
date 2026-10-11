# AUDIT-STRIPGLITCH-0.6.6: a narrow app window flashes at the LEFT edge of the home screen after a partial swipe-up / app switcher dismissal

Reports (device, never on stock 16.0): (1) "a random app window flies in about 10 s after dismissing the app switcher"; (2) screen recording: partial swipe up on the
home screen, quick release -> home blurs (switcher half open) -> a narrow app window (Sileo, "ShapeManagerToggle" list) slides in from the left edge, the blur fades,
the window stays about 0.5-1 s over the un-blurred home screen and disappears. Repeats on every partial swipe.
Method: static (16.0 = 20A8372 `g1b/160`, 16.2 = 20C65 `g1b/162` annotated dumps, `sb*_objc.txt`), frames `vid/g_005..g_016`.

## What the recording shows (frame by frame, 6 fps)
* g_008, g_015: blurred home, NO card (switcher open, nothing laid out in view).
* g_016: blurred, a tall card (y 14..355 of 419) at the far left, only ~18 px of it on screen.
* g_009/g_010: blurred -> less blurred, card at the left edge, x 0..~110, top clipped.
* g_011..g_013: no blur, card x 0..125 of 600 (about 250 pt), y 0..270 (about 540 pt), CRISP text = scale about 1 (not a scaled strip thumbnail), top-left corner of the screen.
* g_014: home only. So: the window is laid out at scale 1 at its un-scaled frame (0,0,w,h) and slides in from x < 0.
* A real Stage Manager strip card is a small scaled thumbnail; this is NOT one. It is a full-size window frame for a layout the home floor should keep hidden.

## Findings, by candidate (what each one can and cannot do)

### 1. Slide modifiers (`G1C_NewSlideModifier`, "entered the strip: slide in")  -> ruled out for the HOME screen, still the best fit for report (1)
* Spawned only in `-[Root handleContinuousExposeIdentifiersChangedEvent:]` and only when `[self _effectiveEnvironmentMode] == 3 && isAnimated && from && to` (G1C.x, same gate as 16.2 0x1c78195b8,
  and as 16.0). `_effectiveEnvironmentMode` (G1B 4.1 hook over 16.0 0x1c6372a88): no floor / Home floor = 1, AppSwitcher / AppExpose floor = 2, FullScreen floor = 3. During a swipe on the home
  screen the floor is the Home modifier (BP162 subclass of SBHomeScreenContinuousExposeSwitcherModifier) or the AppSwitcher modifier (`multitaskingModifier`) -> mode 1 / 2 -> no slide, no cycle.
* Visibility: the slide modifier overrides only frame / anchor / scale / accessory frame / animation attributes. It cannot make a hidden window visible.
* Frame: mode 1 puts the window at x = -(stripWidth + pad) - w/2 (off-screen left) and lets the layout animate it to the frame given by the chain below it; that is exactly the "flies in from
  the left" look of report (1) (an app on stage, ids list changes without a transition to hide it). In report (1) the ids event comes from `_update...Identifiers...` which G1C replaces and now
  dispatches ALWAYS (16.0: only when animated); `animated` is still checked for the spawn, but any later layout invalidation that calls the VC update (16.2 does it from
  `_performInvalidateContinuousExposeIdentifiersResponse`) with stage in mode 3 and a changed strip list re-creates a slide-in. Not provable statically; the new log shows it.
* Timers: slide "WaitingToPrepareLayout" 0.0 s, "WaitingToAnimate" 0.5 * appToAppLayoutSettings.response; Cycle 1.5 s; Reveal safety net 2.0 s. There is NO 10 s timer anywhere in G1B/G1C/G2/G2B.

### 2. Strip visibility queries / strip list builders  -> not the cause on the home screen
* There is no `SBStripContinuousExposeSwitcherModifier` in 16.0 and nothing in the tree builds one (`grep`: the only reference is the `NSClassFromString` in `G1C_Hs_Init`, which therefore never attaches a
  strip child). So there is no strip layout at all, `isContinuousExposeStripVisible` (G2B default: `continuousExposeStripProgress > 0`) and `continuousExposeStripProgress` (Home subclass: 0.0, as 16.2
  0x1c77f3e60) are only consumed by the VC `_areContinuousExposeStripsUnoccluded` hook (corner radius / status bar of a maximized window), never by the layout of other groups.
* Lists: on the home screen the Root's `appLayoutOnContinuousExposeStage` (`kRootEffStage`, filled by `handleEvent:` exactly like 16.2) is the HOME layout (to != nil, from != nil, phase 2), so
  `BP_G2_ComputeStripIds` returns the first `numberOfRowsWhileInApp` groups (the recent apps, Sileo first) as the "strip" while on the home screen. The 16.2 Home modifier keeps those cards hidden with
  its own Strip child at progress 0; 16.0's Home modifier has no such child. Harmless by itself (nothing renders a strip), but it is the reason the log line "ids-changed" will list Sileo in the strip on home.
* `BP162AppSwitcher...` answers `adjustedContinuousExposeIdentifiersInStrip...` / `...InSwitcher...` with the IDENTITY (G1C_As_AdjustedStrip/Ids, marked UNSURE); 16.2 0x1c7811a50 / 0x1c7811880 recompute
  both lists in switcher mode. Divergence: ids lists freeze while the switcher is the floor. No visual effect found for it (no strip renderer); noted for the next round.

### 3. Gesture factories (type 3 root, delayed completion, ToHome)  -> best candidate for the home-screen flash, NOT proven
* `finalResponseForGestureEvent:` (16.0 0x1c6426754 = 16.2): returns 1 ("goes to switcher") when (-0.15 * velocityY - translationY) <= 0.25 * containerHeight, i.e. for a SHORT swipe. So a partial
  swipe + release is a request for the app switcher (unlocked env mode 2) = a 1->2 gesture-initiated transition, not a cancel. The blur in the recording is the real switcher opening.
  The follow-up dismissal (tap / second swipe) is a 2->1 transition: animated and non-gesture (tap outside), or gesture-initiated (swipe from the switcher).
* 2->1 non-gesture animated: 16.0 returns nil from `transitionModifierForMainTransitionEvent:`; G1C now fills it with `SBContinuousExposeToHomeSwitcherModifier(direction 0, [multitaskingModifier copy])`
  (16.2 0x1c78188e0..0x1c7818970, faithful). 2->1 gesture-initiated: `SBGridSwipeUpGestureRootSwitcherModifier.transitionChild...` builds the same ToHome (16.2 0x1c7407520, faithful). Its child
  `SBHomeToGridSwitcherModifier(direction 0, multitasking copy)` animates the switcher cards (the 16.0 `SBAppSwitcherContinuousExposeSwitcherModifier` copy) to their HOME-state frames.
* Home-state frames: 16.0 `-[SBHomeScreenContinuousExposeSwitcherModifier frameForIndex:]` (0x1c634e28c) returns, for every group, the overlapping model's bounding box centred on the chain's
  `frameForIndex:` = first grid slot (top-left, scale 1, un-scaled window size). In 16.2 the same Home floor ALSO owns the Strip child (`init` 0x1c77f3898; its `_stripModifier` ivar), which lays the
  other groups out in the (hidden, progress 0) strip, and `frameForIndex:` 0x1c77f3e68 is a different, strip-aware computation. Our Home floor has the 16.0 frames and no strip child, so during the
  switcher->home transition the first card (most recent group = Sileo) ends in the top-left slot at scale 1 and stays visible until the transition modifier is removed: that matches the recording
  (x 0..250 pt, y 0..540 pt, crisp, top-left, 0.5-1 s, then gone) better than anything else found. It has not been proven (no device log yet; whether HomeToGrid fades the cards in 16.0 was not traced).
* Review item B6 (gesture type 3: delayed completion without a timeout): checked against 16.2 0x1c78d63b0 / 0x1c78d6530, the port is exact. A stuck gesture would keep the gesture blur on,
  the recording shows the blur leaving, so it is not what is visible here. The 2 s safety net used for Reveal was NOT copied (would be invented behaviour); the log now shows whether the gesture
  ever completes (`grid swipe-up gesture completes on transition phase ...`).

### 4. Reveal strip gesture replacement (B8)  -> fixed (off switch), not the cause
* `handleGestureEvent:` of `SBRevealContinuousExposeStripsGestureModifier` is replaced with `class_replaceMethod` and ran even with `Backport162.off.group1c`. The original IMP is now kept in
  `gRevealOrigHandle` and used when `G1C_ON()` is false (falls back to the superclass implementation when the class had inherited it). Behaviour with the group on is unchanged.
  The gesture is a left-edge pan (type 11) that needs an app on stage; a bottom swipe on the home screen does not start it.

### 5. Peek child (`handleTransitionEvent:` adds `SBContinuousExposePeekSwitcherModifier` when `toPeekConfiguration` is 2/3)
* `SBPeekConfigurationIsValid` is byte-identical in 16.0 (0x1c6289f84) and 16.2 (0x1c77229fc): `(cfg & ~1) == 2`; a peek window is placed mostly off-screen on its side. Only for real peek transitions
  (not produced by the home gesture). Logged anyway.

## Conclusion
* Cause NOT pinned with confidence. Ranked: (a) ToHome / HomeToGrid ending on the 16.0 Home frames (no 16.2 strip child) ~45 percent for the recording; (b) slide-in of report (1) in an app ~50 percent for report (1);
  slide modifiers on the home screen ruled out (mode gate), strip visibility queries ruled out (no strip renderer exists).
* Per the task rules no behaviour was invented. Changes: B8 off-switch fix; `BP_LogEnabled()`; GLITCH log lines (G1C.x): slide created / first frame of each slide mode, ids-changed event (effective mode, floor
  class, from/to, prev and current lists, whether a slide may spawn), VC ids update (stage + lists before/after), Root transition event stream (phase, modes, gesture flag, floor class, stage), stage bookkeeping,
  main transition (stock modifier class and replacement), gesture modifier chosen per type, grid swipe-up gesture end (goesToSwitcher, translation, delay) and completion, grid-root ToHome, ToHome init
  (direction, multitasking class), Home floor creation (strip class present?), peek child, strip reveal end.

## What to look for in the next device log (`<jbroot>/tmp/Backport162.debug` on, grep `GLITCH`)
1. The line sequence around one flash: `gesture modifier: type=3`, `grid swipe-up gesture ended: goesToSwitcher=1`, `transition event ... modes 1->2`, later `main transition: from mode 2 to mode 1 ... stock modifier=nil`
   followed by `main transition replaced: nil -> SBContinuousExposeToHomeSwitcherModifier` or `grid root builds ToHome`. If the card appears exactly during that ToHome window -> cause (a); fix = give the Home floor
   the 16.2 behaviour for hidden groups (port of the Strip child / hide non-home layouts in the ToHome end state).
2. Any `GLITCH slide created` line while the previous `ids-changed event` shows `effMode=1` or `2` (impossible per the gate) or at the time of the card -> cause (b); the line prints ident, direction, lists.
3. `ids-changed event ... curStrip=[...]` on the home screen listing the recent apps (expected from the stage = home layout) and `VC ids update` lines: shows how often the update runs without a transition.
4. For report (1): a `VC ids update` / `ids-changed` pair about 10 s after the dismissal with `effMode=3` and `slide created ... dir=0`.
