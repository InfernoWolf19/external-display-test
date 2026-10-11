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

# Round 2 (static, caches: 16.0 20A8372 / 16.2 20C65; selmap + ipsw disass; scratchpad helper fn.sh)

## R2.1 What HomeToGrid asks the Stage Manager copy (identical bytes in both caches)
* `-[SBHomeToGridSwitcherModifier frameForIndex:]` 16.0 0x1c5f64fe8 / 16.2 0x1c73dafc4 (block 0x1c5f6511c / 0x1c73db0f8, same 0x134 bytes): `[multi frameForIndex:i]`, then if `[self isEffectivelyHome]`
  `CGRectOffset(f, isRTL ? +d : -d, 0)` with `d = [multi distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch:i]` (all inside `performTransactionWithTemporaryChildModifier:usingBlock:` with the multitasking modifier).
  This is the ONLY slide/anchor query HomeToGrid sends. `scaleForIndex:` (0x1c5f651b0 / 0x1c73db34c) = multi's; opacity (0x1c5f65590 / 0x1c73db89c) = `[self visibleAppLayouts] containsObject:layout ? [multi opacity...] : 0`;
  `visibleAppLayouts` (0x1c5f652ec / 0x1c73db5f8) = `[multi visibleAppLayouts]`.
* NEW in 16.2 on HomeToGrid: `frameForLayoutRole:inAppLayout:withBounds:` 0x1c73db18c and `scaleForLayoutRole:inAppLayout:` 0x1c73db488: both are plain pass-throughs to the multi (no slide in the role frame; the container frame carries the slide). 16.0 has neither (the 16.0 role frame comes from the multi copy / default impl).
* ToHome init (16.2 0x1c7412cf0) is exactly what G1C_CEH_Init does (`_newContinuousExposeModifier` = `[ivar copy]`, child `initWithTransitionID:direction:(dir!=0) multitaskingModifier:`); `_isEffectivelyHome` 0x1c7413420 as ported.

## R2.2 The distance: 16.0 vs 16.2 (the divergence)
* 16.0 `-[SBAppSwitcherContinuousExposeSwitcherModifier distance...WithVisibleIndexToStartSearch:]` 0x1c636c158 = tail call of the shared utility `-[SBSwitcherModifier(SharedModifierUtilities) distance...:numberOfRows:padding:layoutDirection:]`
  0x1c61c375c with (start=i, rows=`numberOfRowsInGridSwitcher`, padding=`_horizontalSpacing` 0x1c636c8a8, dir=0).
  Utility (decoded): `vis=[self visibleAppLayouts]`; if i == NSNotFound or `appLayouts[i]` not in vis -> start = count-1; chain walk start, start-rows, start-2*rows ... while idx >= start%rows && idx < count and layout visible; `lead` = last visible of that chain
  (lowest index); if none -> 0; `f=[self frameForIndex:lead]`, `s=[self scaleForIndex:lead]`, `r = scaled-about-centre(f,s)`; return `(RTL ? bounds.w - r.x : maxX(r)) + padding`.
* 16.2 0x1c781264c IGNORES the index argument: `range=[self _visiblePileRange]` (0x1c7810c9c), pile A = `_boundingFrameForPileAtIndex:range.loc withScrollOffsetApplied:NO`; if range.len >= 2 and maxX(pile loc+1, NO) > maxX(A) then idx = loc+1;
  (loc == NSNotFound -> 0); `F = _boundingFrameForPileAtIndex:idx withScrollOffsetApplied:YES`; `x = RTL ? switcherViewBounds.size.width - F.origin.x : maxX(F)`; return `x + [chamoisLayoutAttributes switcherHorizontalInterItemSpacing]`.
  Pile bbox = cache (build 0x1c7812acc) union of the pile's scaled card rects minus scrollViewContentOffset.x; visible pile = bbox (scroll applied) intersects `_visibleSwitcherBoundsIncludingShadow` (0x1c78133f4 = CGRectInset(switcherViewBounds, -2.8*cardShadowRadius), constant 0xc006666666666666, same as 16.0 `_isIndexVisible:` 0x1c636b0f0).
  16.2 `visibleAppLayouts` (0x1c7810118) = first `numberOfVisibleItemsPerGroup` layouts of each visible pile ONLY (16.0 0x1c636ae50 = `[super visibleAppLayouts]` + visible spaces).
* Numeric check of the video (settled s1: cols 1,2,3 on screen at x 792/385/-22 px, col 0 = grid index 0,1 = Sileo+Files OFF SCREEN RIGHT at x 1199..1559; settled scroll offset ~22 px; card 360 px, pitch 407 px, hs ~ 47 px):
  `frameForIndex:` (16.0 0x1c636a53c) = container frame (full-size, centred on the card centre cx) with x -= 0.5*scale*W: it is built for the 16.0 anchor x=0 (anchorPointForIndex: 0x1c636a844 returns x=0 when the pile has < 2 windows) with position = frame centre.
  ToHome forces anchor (0.5,0.5) while effectively home (as 16.2 does, its frames are built for 0.5), so the RENDERED card rect is [cx-sW, cx] = scaled-about-frame-centre = exactly what the utility measures (`_SBTransformedRectWithScale` / UIRectGetCenter + scale).
  Rendered rects (anchor .5, scroll applied): col0 [1019,1379], col1 [612,972] ... With lead = col 1 (idx 2/3): d = 972 + 47 = 1019 -> col 0 ends at [0,360]. This is EXACTLY the observed x = 0..360 (while a lead of col 0 would give d = 1426 -> [-407,-47]).
  => the divergence is: the 16.0 utility starts its chain at `count-1` when the card itself is not in `visibleAppLayouts`, stops at the first invisible card, and therefore picks the lead from col 1 whenever col 0 (the most recent windows) is scrolled out of view (as in s1:
  col 0 is off screen to the right in the settled grid, offset ~22). 16.2's rule is the same idea (first VISIBLE pile; uniform) and ALSO ends with col 0 at [0,360] in that state: there the cards stay invisible because HomeToGrid opacity is 0 for layouts outside `visibleAppLayouts`.
  In our build col 0 is drawn anyway, so the opacity gate is not effective for them (HomeToGrid's opacity is not the answer that wins, or the 16.0 `visibleAppLayouts` contains them, see R2.3).

## R2.3 Proof of the lead column (independent of the anchor convention) and what was changed (G1C.x section 6.8, Round 2)
* Settled s1 (px): col 0 = grid index 0/1 at x 1199..1559 (off screen right), col 1 at 792..1152, pitch 407, card 360, grid gap hs = 407-360 = 47. Final left edge of a card with the slide d = R_lead + hs (R = right edge measured with the SAME rect convention the utility uses):
  left_final(col0) = (L0 - c) - ((R_lead - c) + hs) = L0 - R_lead - hs (c = convention shift, cancels). With lead = col 1: L0 - R1 - hs = 1199 - 1152 - 47 = 0  => x = 0..360 exactly as in the video. With lead = col 0 it would be L0 - R0 - hs = -407 (off screen).
  So the video proves: the lead column was column 1, i.e. `[copy visibleAppLayouts]` did not contain layouts 0/1 when the utility ran (chain start count-1, stop at the first invisible card), independent of any anchor details.
* Open (needs the new log): why those two cards were nevertheless DRAWN. HomeToGrid's own opacity is `visibleAppLayouts containsObject ? multi : 0` with the same set. The new `GLITCH h2g` line prints inVisible and opacity for idx 0/1.
* Changes:
  - NEW `G1C_Slide_Distance` replaces `-[SBAppSwitcherContinuousExposeSwitcherModifier distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch:]` (class_replaceMethod on the stock 16.0 class, so stock instances and BP162AppSwitcher... inherit it).
    Only HomeToGrid / HomeToDeck / MixedGridToHome / Routing call this selector (callers by xref: 16.0 0x1c5f6516c, 0x1c5febc34, 0x1c60afd8c, 0x1c610e060), none of them with this class in stock 16.0, so no other behaviour changes. Switch `Backport162.off.g1c_homeslide`.
    Arithmetic = 16.2 0x1c781264c on 16.0 primitives (see R2.2): piles = continuousExposeIdentifiers (16.0) with `appLayoutsForContinuousExposeIdentifier:`; pile box = union of each layout's `frameForIndex:` scaled about its centre by `scaleForIndex:` (scroll applied);
    visible = box intersects `CGRectInset(switcherViewBounds, -2.8*cardShadowRadius)`; `_visiblePileRange` state machine (even/odd runs, last = max(endEven-2, endOdd-2)) literally; pick loc or loc+1 by larger maxX; RTL uses bounds.w - box.x;
    gap = `chamoisLayoutAttributes.switcherHorizontalInterItemSpacing` (G2 adds the property; falls back to 16.0 `_horizontalSpacing` if 0). ADDED (not 16.2): result = max(result, ownRightEdge(idx) + gap) so no card can stop short of the screen edge.
    (When the lead column is the right-most one, e.g. col 0 visible, this max is a no-op = exactly 16.2.)
  - The 6.8 opacity guard stays, now only for cards whose slid frame still intersects switcherViewBounds (safety net, dormant when the distance is right).
  - Same fix covers home -> switcher (ToHome direction 1: `isEffectivelyHome` while preparing, the cards START slid off screen): before, col 0 started at x = 0..360.

## R2.4 Why 16.2 does not show the glitch, residual uncertainty, exact vs approximated
* Default `switcherCardShadowRadius` on iPad = 30 (16.0 `-[SBAppSwitcherSettings setDefaultValues]` 0x1c6381590: 30 unless device class 2 -> 16), so the visible bounds are the screen inflated by 2.8*30 = 84 pt: col 0 at x 1199.. IS "visible" by 16.2's `_visiblePileRange`
  (and by 16.0 `_isIndexVisible:`), hence in 16.2 the lead pile is col 0 (d = maxX(col 0) + gap, all cards leave the screen). Our G1C_Slide_Compute applies that same rule on its own data, so it picks col 0 as well.
  Unexplained: the stock 16.0 utility behaved as if layouts 0/1 were missing from `[copy visibleAppLayouts]` (proved by the 0..360 landing). Most likely `[super visibleAppLayouts]` / the visible run is evaluated in the temporary-child context with other data; the new log prints `inVisible`, the stock and the new distance per index to settle it.
  The replacement does not depend on that set, so the result is the same either way.
* EXACT 16.2 logic: query ignores its index for the lead; `_visiblePileRange` state machine; pick loc/loc+1 by larger maxX; pile edge (RTL: width - x) + switcherHorizontalInterItemSpacing; visibility = box vs bounds inset by -2.8*shadow radius; HomeToGrid itself (unchanged stock code).
* APPROXIMATED: pile box = union of the 16.0 `frameForIndex:` rects scaled about their centre (what a card renders as while ToHome forces anchor 0.5; 16.2 boxes come from its own cache); gap falls back to 16.0 `_horizontalSpacing` when G2's switcherHorizontalInterItemSpacing is 0;
  `continuousExposeIdentifiers` (16.0 name) stands for 16.2's `...InSwitcher`; the max(.., own edge + gap) safety is NOT in 16.2 (no-op whenever the lead column is the right-most visible one).
* Not changed: the settled switcher shows col 0 (most recent windows) scrolled off to the right (offset ~22 px); 16.2 scrolls differently (separate issue, `contentOffsetForIndex:alignment:`).
* Found while reading build 0x1c7812acc: 16.2 fills piles right-to-left in LTR (cursor starts at -hEdge, card extends left, final x += _contentSize.width), like 16.0; the opt-in G1C_As_Build (g1c_piles) fills left-to-right and mirrors for RTL = inverted direction. Not touched (opt-in, review B2), but it must be flipped before g1c_piles can be enabled.
* Log to read (debug on, grep GLITCH h2g): per idx 0..3 `d<new>(stock <old>)`: stock should show ~one column less than new for idx 0/1; `pile loc/len/pick/vis` = 16.2 range; `rendered[x0..x1]` after slide must end <= 0 (LTR); `opacity(stock>out)` 1.00>0.00 only if the safety net still had to act.
