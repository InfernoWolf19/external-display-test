# FINDINGS: strip reveal, hide, reveal again: the strip disappears and the display freezes until a tap (0.7.9)

Evidence: device log u11 (11.log, 16:34-16:37), screen recording RPReplay_Final1793119024.mp4 (15.6 s, 60 fps), IMG_0133.png. PROVEN = read from a log line, a source line or a measured video frame. INFERRED = follows from facts.

## 1. What the video shows (PROVEN, measured per frame at 20 fps)
iPad built-in display, Reynard (a browser) full screen under Stage Manager (effective mode 3), strip hidden. Video time t = log time - 47.77 s (fits three anchors: first reveal begin, freeze start = GUARD line, freeze end = the tap transition).
* t 1.4 - 3.3 and 6.8 - 7.7 and 13.7 - 14.4: reveals that work (window scales down to about 0.98 .. 0.93, strip thumbnails visible at the left edge, window returns to full size).
* t 8.1 - 12.0 (3.9 s): the window sits at a constant geometry (left edge x=44, right 469, top 19, bottom 316 of a 480 x 336 frame, i.e. scaled and pushed right by the reveal) with NO strip visible and no movement at all; at t 12.0 it animates back to full size. This is the freeze. It starts at log 16:36:55.93 (the GUARD line) and ends at log 16:36:59.82 (the transition caused by the user's tap at 16:36:59.764).

## 2. Root cause (PROVEN by timing, 4 of 4 occurrences; mechanism PROVEN by the code)
G1C.x `G1C_Rv_HandleGesture` armed a 2 s safety net timer when a strip reveal gesture ended, with the constant reason `BP162RevealStripsCompletionTimeout`; `G1C_Rv_HandleTimer` finished every reveal modifier that saw that reason. A timer event is delivered to all modifiers of the stack, so the timer of reveal N (fires 2.1 s after N's end) finished the modifier of reveal N+1 when N+1 had begun in between and was still being dragged:

| reveal N end | reveal N+1 begin | GUARD line | end + GUARD delta | txn of N+1 cleared |
|---|---|---|---|---|
| 16:34:35.660 | 16:34:35.784 | 16:34:37.757 | 2.097 s | 16:34:39.356 (tap) |
| 16:34:45.758 | 16:34:47.558 | 16:34:47.882 | 2.124 s | 16:35:01.640 (tap) |
| 16:35:32.797 | 16:35:33.073 | 16:35:34.928 | 2.131 s | 16:35:41.173 (tap) |
| 16:36:53.810 | 16:36:55.770 | 16:36:55.930 | 2.120 s | 16:36:59.816 (tap) |

In the last one the log shows reveal progress still rising (0.82 at 55.911) when the GUARD line fires and the progress drops to 0.0 (modifier gone); there is no `GLITCH strip reveal gesture ended` line for that gesture, no `txn complete`, no transition. Without a modifier the end event of the gesture has nothing to land in: no transition request, so the shared gesture transaction (P1Drag) stays open and the window stays at the last reveal progress until a new touch interrupts the transaction (the AppToApp transition 'gesture=0' after the tap). Every other reveal in the log (the ones that begin more than 2.1 s after the previous end, or end before the stale timer fires) completes: `ended` -> `txn complete` -> transition phases 1-3 -> `coordinator clears`.

16.2 has no such timer; its other timers carry per-instance reasons (`_timeoutReason` 0x1c7589cb4, slide modifier `<uid>-WaitingToAnimate`), our own mistake.

## 3. Fix
* `g1c_revealtimer`: the reason is `BP162RevealStripsCompletionTimeout-<serial>`, one serial per modifier instance (associated object). The timer of a gesture can only finish its own modifier; a timer of an earlier gesture is logged and ignored.
* `g1c_revealwatch` (last line, never alone): `G1C_RevealRecognizerEvent` (called from G1D `_handleContinuousExposeStripRevealGesture:`) logs each recognizer begin / end / cancel / fail with the shared transaction; 3 s after an end / cancel / fail, when no newer reveal event happened, the manager's active transaction is the same strip reveal transaction (`_gestureType` 0xb) and it never received its complete (`_completedGestureWithTransitionRequest` NO), it is completed with `SBPerformTransitionSwitcherEventResponse(requestForActivatingAppLayout:initial, gestureInitiated YES)` through `-[SBFluidSwitcherViewController _performModifierPerformTransitionResponse:]` (16.0 0x1c5fe2428 / 16.2 0x1c745bb4c: both do `[delegate switcherContentController:self performTransitionWithRequest:[response transitionRequest] gestureInitiated:[response isGestureInitiated]]`). Logged `GUARD(reveal txn)`.
* Diagnostics: `g1c: strip reveal modifier <p> begins`, `GLITCH strip reveal gesture ended ... modifier= reason=`, `g1c: strip reveal modifier ... ignores the completion timer`, `GLITCH strip reveal modifier ... finished by a transition event ... before its own gesture ended`.

## 4. Unproven / open
* Case 1 of the table (16:34:35): reveal N+1 began 110 ms after N ended, while N's transition was still running (phases 1 and 2 logged, phase 3 never came, `animation done` only after the tap). The timer fix removes the kill of N+1, but whether N's transition then finishes by itself is not provable from the log. 16.2's modifier also finishes on ANY transition event of phase >= 2 (0x1c7817abc), so a late phase 3 of N could still finish N+1 early; this now logs (`finished by a transition event ... before its own gesture ended`).
* The watchdog leaves a transaction that HAS its complete but keeps running (logged), because completing it again would add a second animation controller.
* Why the first two taps of the user (58.53, 59.37) did not release the transaction and the third did is not explained by the log.
