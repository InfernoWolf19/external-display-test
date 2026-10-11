# AUDIT-HOMEFLASH-0.6.8: first group's cards drawn at the left/top-left after the switcher is dismissed (and variants)

Evidence: video RPReplay_Final1791680095 (7.25 s) + debug log 98f96ad7-Backport162.log (GLITCH lines). User correction: the glitch is AFTER DISMISSING the switcher:
two windows (Sileo "Packages" + "New Window") animate to the LEFT and stay drawn ~1 s, then vanish. 3 glitches in the session: (1) switcher cards randomly on
home, (2) partial swipe-up + quick dismissal: a window at the left edge, (3) this video.

## Step 1 (static + video, 20 fps frames in scratchpad/hf/mb.png)
* Dismiss = log `main transition: from mode 2 to mode 1 animated=1 gesture=0` -> `ToHome init direction=0` -> phase 2 at +5 ms -> phase 3 at +0.92 s.
  The cards remain visible exactly until phase 3 (ToHome removed), i.e. they are visible for the WHOLE life of the ToHome transition after sliding left.
* Frames: the whole switcher grid slides LEFT as one block; the column holding the two most recent cards (grid index 0 and 1, rightmost column: the grid fills
  right-to-left, ids list [Sileo, Documents, Reynard, Terminal, Prefs, News, Filza, Shirox] = columns (0,1),(2,3),(4,5),(6,7), rows=2) ends at x = 0.02..0.32 W (still on
  screen, same size as in the grid = switcher scale, NOT scale 1), other columns end at x < 0 (off screen). Shift ~ 0.70 W.
* So the glitch is NOT the Home floor frame (the Home floor does not answer while the ToHome transition modifier answers frames); it is the HomeToGrid slide-out.

## Step 2: how stock slides the cards out (16.0 HomeToGrid = 16.2 HomeToGrid, unchanged)
* `-[SBHomeToGridSwitcherModifier frameForIndex:]` 0x1c5f64fe8 (block 0x1c5f6511c): frame = `[multitaskingModifier frameForIndex:i]` (temp child);
  if `[self isEffectivelyHome]` (ToHome `_isEffectivelyHome` / HomeToSwitcher: prepare&&dir==1 || update&&dir==0) frame = CGRectOffset(frame, isRTL ? +d : -d, 0)
  with d = `[multi distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch:i]`  => the grid is slid fully off the screen.
  scale/opacity: `scaleForIndex:` = multi's; `opacityForLayoutRole:inAppLayout:atIndex:` = (layout in HomeToGrid.visibleAppLayouts = multi's visibleAppLayouts) ? multi's opacity : 0.
  There is NO fade: hiding is only by the slide distance being large enough (all cards off screen) plus non-visible layouts.

## Step 3: evidence from the stills (s1 = settled switcher, s2 = glitch, 1200 px wide = 1194 pt)
* Settled grid: cards 360 px wide (0.30 W), pitch 407 px, rows y 63..315 and 385..635. The grid fills RIGHT-TO-LEFT (16.0 `_frameForIndex:ignoringScrollOffset:` 0x1c636c5b0: x measured from the
  fitted content width; `_columnForIndex` = index / rows, `_rowForIndex` = index % rows, rows = 2): column 0 = grid index 0,1 = (SileoStore "Packages", DocumentsApp "Files"), column 1 = (Reynard, Terminal)...
* Glitch frame s2: exactly those two cards (index 0 and 1) at x = 0..360 with their normal rows, crisp, drawn over the home icons. All other columns are left of x = 0.
  Their final shift (~ -1200 px) equals maxX(column 1 card = 1152) + padding (48): i.e. the slide distance used for cards 0/1 was computed from column 1, not from column 0 (which is what 16.0's
  `distanceToLeadingEdge...:numberOfRows:padding:layoutDirection:` (0x1c61c375c, SharedModifierUtilities) does when the card itself is not in `visibleAppLayouts`: start the row-chain walk at count-1,
  stop at the first invisible card; lead = lowest visible index of that chain).
* HomeToGrid hides cards only by (a) that slide, (b) opacity 0 for layouts not in its `visibleAppLayouts` (= the copy's), nothing else. Both answers come from the 16.0 Stage Manager switcher COPY.
  16.0 itself NEVER ran HomeToGrid with this copy: 16.0 returns nil for the animated 2->1 main transition (that is why SwitcherDismissFix and G1C fill it). The pairing HomeToGrid(+ToHome anchor/pin overrides)
  + switcher copy is 16.2-only and relies on the 16.2 switcher's geometry: no `anchorPointForIndex:` override (16.0 answers x = 0 for single windows, 0.5 centred for piles), frames from the pile cache,
  `distanceToLeadingEdge...WithVisibleIndexToStartSearch:` = maxX(first visible PILE, scroll applied) + switcherHorizontalInterItemSpacing (0x1c781264c), uniform for all indices (16.0: per index/row chain).
  The 16.0 copy therefore gives a wrong slide distance for the first group (and ToHome's forced anchor 0.5 changes where the 16.0 frames land).
* The user rules out count/parity conditions (glitch also with exactly 4 windows): consistent with a geometry mismatch that does not depend on the count. NOT proven numerically (no device values yet).
* Candidate in the earlier audit (Home floor lays the first group out at the top-left slot) is NOT the cause for the recording: the Home floor does not answer frames while ToHome/HomeToGrid is active;
  it only explains what happens after ToHome is removed (cards vanish at phase 3, exactly as seen). It is still logged (see below).
* Glitch (2) (partial swipe-up, quick dismissal, window at the left edge) is the same 2->1 ToHome transition (switcher half open, then dismissed): same mechanism, same fix. Glitch (1) (cards randomly on home)
  is NOT explained by this; the Home floor logging below is for it.

## Fix (G1C.x, section "6.8")
* `-[SBHomeToGridSwitcherModifier opacityForLayoutRole:inAppLayout:atIndex:]` is wrapped (class_replaceMethod, original kept): when the modifier is direction 0 (switcher -> home), `isEffectivelyHome` (updating layout)
  and its multitasking modifier is an `SBAppSwitcherContinuousExposeSwitcherModifier`, the answer is 0.0, otherwise the stock answer. In 16.2 all cards are off screen in exactly that state, so the end state is identical;
  the opacity change animates together with the slide. Not invented behaviour beyond enforcing that end state. Off switch: `Backport162.off.g1c_homeflash` (BP_OnName, no BP.h change).
* This guard does not depend on the slide distance, the anchor, the scale or the visible set, i.e. on none of the unproven numbers.
* Not done (needs device values): reproducing 16.2's uniform slide distance with 16.0 grid maths (would also make the slide itself exact).

## Logging added (debug on, grep GLITCH)
* `GLITCH h2g idx=N role=R layout=ID dir/eff/prep/upd/opacity(stock>out)/frame/scale/inVisible(count)/distance: ...` for grid index 0..3, one line per change (each layout pass): direction, effectively-home flags,
  stock opacity > answered opacity, HomeToGrid's frame (after the slide), scale, whether the layout is in the copy's visibleAppLayouts and how many are, and the slide distance the copy returns for that index.
* `GLITCH ToHome effectively home dir=D idx=I: anchor forced to (0.5,0.5), the switcher copy's own anchor would be (x,y)` once per effectively-home state, idx 0 and 1.
* `GLITCH home floor scrollViewContentOffset=...` (on change) and `GLITCH home floor idx=I role=R layout=ID opacity/frame/inVisible: ...` (idx 0,1, on change): what the Home floor answers after ToHome is gone / on the home screen (glitch 1).
* What to read in a new log: during one dismissal, the `h2g` lines for idx 0/1 with eff=1 show frame.x (expected <= -card width if the slide worked), distance (idx 0/1 vs idx 2/3: if idx 0/1 equal idx 2/3, the lead card was column 1),
  inVisible (0 for idx 0/1 would mean stock 16.2 would also hide them via opacity, 1 means the copy considers them visible) and opacity stock>out (1.00>0.00 = the guard acted).
