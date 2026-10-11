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
