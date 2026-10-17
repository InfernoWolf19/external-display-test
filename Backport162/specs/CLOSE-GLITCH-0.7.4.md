# Close glitch on the iPad display (0.7.4 build, home swipe on Sileo): white window-shaped rectangle with a chevron

Evidence: RPReplay_Final1792221811.mp4 (120 fps, 7.6 s), Backport162.log (debug on), frame sheets in the scratchpad (v6/c1.png, c2.png, v7/all.png, v7/open1.png).
Status legend: FACT = read from the log / frames / sources; INFERENCE = deduced; UNSURE = not provable statically.

## Verdict

The rectangle is NOT a SpringBoard layer. It is part of the Sileo app's own rendered content: Sileo's "Queued / No Packages" popup (downloads view) that the app opens in
reaction to the home swipe, because the swipe starts ON Sileo's popup bar. No faithful-16.2 difference in our ported pieces was found that explains it; no code was changed.
Confidence: high that it is app content (several independent facts below); medium that stock 16.0/16.2 would behave the same (UNSURE, see "Open question" and probes).

## Facts

1. Time base. Video t0 = log 08:23:22.74 (the five video closes at t = 1.0 / 2.75 / 4.0 / 5.5 / 7.0 s match the five home gestures in the log at 23.738, 25.385, 26.746, 28.231,
   29.572; the four opens at t = 2.0 / 3.5 / 4.75 / 6.25 match 24.649, 26.163, 27.535, 28.913). So the close studied in c2.png (t = 0.93-1.08) is the FIRST one, log 23.595 touch,
   23.679 gesture begin, 23.738 gesture end / phase=1 (not 25.385). Sileo is shown clean before it.
2. Every close in the log starts with a touch at the very bottom, x = 522 / 536.5 / 553.5 / 563 / 561, y = 1181.5 / 1178 / 1178.5 / 1175.5 / 1176 (iPad 834x1194 pt; 63-67 % of the width,
   16-19 pt above the bottom edge). In the frames Sileo's own bar "Queued / No Packages" sits at x = 58-72 % of the width, in the tab bar at the bottom. The touch lands on that bar.
3. Timing (log): touch-down -> SB home gesture begin = 72-100 ms; begin -> end = 49-65 ms (a short fast flick). The rectangle first appears in ONE 120 fps frame at t = 0.988 s, i.e.
   at gesture end / phase=1 (log 23.738), at full size, top edge ~65 % of the height (about where the finger ended), left edge at ~59 % of the width (= left edge of Sileo's bar), right/bottom
   edge = window edge.
4. It lives inside the window: it is clipped by the window's rounded corners, scales and moves with the window for the whole close (~0.5 s), and does not scale/move independently. Its
   chevron is centred on the rectangle (x ~79 % of the window), not on the window. SpringBoard's own top affordance (the "..." dots at the top left of the window) is visible and unchanged in
   every frame. A chevron "⌣" at the top centre of a content panel is the LNPopup close-button style (INFERENCE: Sileo uses LNPopupController for its queue bar; not verified in this repo).
5. State persists in the app. After the first close, every one of the 4 later opens shows the same panel FULLY open (right ~41 % of the width, full height, white, chevron at the top, the rest
   of the app dimmed) from the first open frame until the next close. So the popup really is open inside the app (a snapshot or a stale layer would not survive 4 open/close cycles with the
   dim on the left). The panel was never dismissed in the 7.6 s of video.
6. Layouts in the log: during all closes there is exactly one stage layout (org.coolstar.SileoStore:default), mode 3 -> 1, floor SBFullScreenContinuousExposeSwitcherModifier -> SBHomeScreenContinuousExposeSwitcherModifier,
   gesture root SBHomeGestureRootSwitcherModifier (type=1). The strip ids (Aidoku, Safari, Discord, YouTube) and the switcher list are identical before and after the begin/transition lines (no ids change,
   no "slide/cycle"). No second stage item, placeholder role or recents entry is created, so no second SBFluidSwitcherItemContainer exists for another layout. Nothing in the log refers to the window in
   a way that could produce a half-width layer.
7. Sources: the home swipe path is not touched by our hooks in a way that affects touch delivery to the app.
   - The only recognizer our G1D code answers on that touch is the window-drag one (G1D.x 1620-1665, _shouldSplitViewApplicationUnpinGesture:receiveTouch:); it returns NO ("-> no window") and does
     not cancel, delay or require failure of the home-swipe recognizer. The only requireGestureRecognizerToFail we add is overflow -> indirect pan (G1D.x 1174). G3B/G2C taps are cancelsTouchesInView = NO.
   - WORKLIST.md (body diff 16.0 vs 16.2 of both SpringBoards) lists no change in the touch routing / system-gesture classes of the home swipe; SBFluidSwitcherGestureManager differs only in
     _configureChamoisGestureRecognizersIfNeeded and updateForChamoisWindowingUIEnabled: (window drag / strip grabber recognizers).
   - The modifiers that answer frames during phase 1/2 (SBFullScreen... / SBHomeScreenContinuousExpose... / SBHomeGestureRootSwitcherModifier -> ToHome) only move the ONE container; there is no
     frame query for a second layout role. The window shrinking correctly toward the icon in the frames confirms they answer right.

## Why the other candidates are excluded

- Second item container / leftover container: no (fact 6); a container would also be the whole window size and would not carry an app-content-like text ghost "Queued No Packages".
- Live content overlay / snapshot layer: no (fact 5, the content survives cycles and has the app's own dim).
- SBTopAffordanceViewController: its visible form is the "..." dots at the top left (unchanged); not a chevron, not at the panel's centre.
- Wrong frames from our ported modifiers / strip modifier showing a hidden item: no (fact 6 and fact 4: the rectangle's geometry is fixed in the window's own coordinate space, a modifier-framed item would be sized
  and positioned in screen space and independent of the window's shrink).

## Likely mechanism (INFERENCE)

Touch-down on the popup bar; the finger dwells ~80-100 ms, then flicks up. Both Sileo's popup interaction pan (LNPopup) and SpringBoard's home-swipe pan recognise at about the same moment; Sileo reveals
its popup to the finger's position (~65 % height) and, when the system gesture takes the touch (cancelled/ended), completes the popup open. The app's content is frozen while it is shrunk (or the open
animation is not presented in the closing window), so the rectangle stays at 65 % during the close, and the popup is fully open on the next open (fact 5).

## Open question (UNSURE, cannot be settled statically)

Whether stock 16.0 / 16.2 cancels the app's touches earlier on such a swipe (so Sileo never sees the pan). Nothing we port touches that path (fact 7), and the 100 ms touch-down -> begin delay is
a recognizer threshold, not something our hooks add (nothing in G1B/G1C/G1D/G2/G3 mentions the home swipe recognizer or touch cancellation). So no "exact fix" exists in our files; any change would
be an invention (no 16.2 selector to port).

## Probes / tests to settle it (no code written)

1. Same close with the swipe starting at x < 40 % (left of Sileo's bar) and with `Backport162.off` (tweak off) starting at the bar: rectangle only with the bar -> app/stock behaviour, not a port difference.
2. A swipe from the bar in an app without a bottom popup bar (e.g. Filza window at x ~560): expected clean.
3. If wanted in SpringBoard: log (BP_LogEnabled) state changes with CACurrentMediaTime and location of the home recognizer (-[SBFluidSwitcherPanGestureRecognizer setState:], plus
   -[SBFluidSwitcherGestureManager handleGestureDidBegin:/End:] already traced) and the touch cancel to the app (BackBoard touch cancel / -[UIApplication _cancelTouches...] in SpringBoard's
   system gesture window path), to compare the begin time against the 16.0 value with the tweak off.
4. App side: attach to Sileo and log its popup pan recognizer state (LNPopupInteractionController) during the swipe: expect Began/Changed then Cancelled/Ended at the gesture end.
