# FINDINGS: slow touch / dead system gestures after hours of use (0.7.9)

Written by an investigator subagent (read-only analysis of the user's device logs and of the sources); saved here by the main session. PROVEN = read from a log line or source line. INFERRED = follows from facts but is not shown by them. UNKNOWN = the data cannot say. Code: branch claude/backport162 at 004fd24.

User constraint: the freeze happened with NO external display connected. Hypotheses are ranked built-in display first; the external display only matters as a source of leftover state from earlier in the same boot.

Log refs: L1 = u1/L1.txt (29,236 lines); B1 = u1/2-Backport162.log.1 (same file one pull later, continues past 00:03:44). Times are BST clock times. Day labels: D0 = Oct 22, D1 = Oct 23, D2 = Oct 24 (L1 lines 1-11159 / 11160-26919 / 26920-29236). Source refs are file:line under Backport162/.

## 0. Summary

1. The log does NOT contain a stall, runaway loop or overload on the built-in display. In the one episode that matches the user's report (D2 00:01:46 - 00:04:38) SpringBoard's main thread ran at 120 Hz (8.0 ms median frame interval, p90 9 ms) while the user was fighting the iPad. "Main thread saturated by our code or logging" is not supported by the data. The slowness sits where the log has no sensor: gesture recognition and event delivery.
2. The 08:34:08 loop (2-/3-Backport162 logs) is not what happened in L1: L1 has 0 `routing162` lines, the highest `GLITCH VC ids update` rate is 24/s (D1 19:00:38) against ~125/s in the loop, no repeated identical sequence. Such a loop WOULD give "everything seconds late" but did not cause the two reported episodes.
3. SpringBoard pid 69053, backboardd pid 69084, pointeruid pid 69433 (from D0 11:16:18) ran 37+ h without restart (PROVEN). The audit found no unbounded per-touch/per-frame growth and no assertion of ours without a release path, but nothing counts anything, so slow accumulation is not excluded.
4. Best fit for the symptom set (taps and the Face ID prompt fine, swipes dead, Spotlight late by seconds): stuck state in SpringBoard's system gesture machinery (UIKit gesture environment / SBSystemGestureManager), H1. A fit, not a proof.
5. Next occurrence made decisive by: a respring-then-userspace-reboot test order (5.2), an always-on stall watchdog and touch-latency probe (5.1 items 1-2), a one-shot gesture state dump (5.1 item 4).

## 1. Abnormal-load periods

### 1.1 Setup facts (PROVEN)
- L1 runs 10:30:38.083 D0 to 00:03:44.112 D2 (`[g3zoomtitle] menu presented`). That is the end of the first pull, not a stall: B1 continues with 00:04:20.458, 00:04:21.164 (Filza window removed), 00:04:29.226 (Spotlight swipe), 00:04:31.7 (Dopamine opened), 00:04:38.461 `Backport162 0.7.9 loaded` (B1:668): the user's userspace reboot, the only SpringBoard start in the data.
- One SpringBoard instance throughout (pid 69053); backboardd pid 69084; pointeruid pid 69433 started D0 11:16:18 and restarted alone at D2 03:04:10 (pid 70682).
- Our log has no heartbeat and its lines are per event: silence means "no event". Home/lock screen touches are not logged at all: G1D_WD_ReceiveTouch (G1D.x:1705) returns NO without a line unless the layout is mode 3 and the display is external.
- External display connected only D1 17:54:06 - 19:05:18 (8 connect/disconnect pairs). All of D0, D1 before 17:54, D1 after 19:05 and D2 is built-in display only.

### 1.2 Gaps > 10 min
22 gaps (screen off, INFERRED). Long ones: D0 11:16->14:15, D0 19:40->22:16, D1 01:48->06:01, D1 07:40->14:06 (6h26), D1 20:39:39 -> D2 00:01:46 (3h22). Each starts with a lock burst and ends with a wake sequence. Nothing suggests a stall inside a gap.

### 1.3 Bursts >= 60 lines/s
Single-display maximum 265/s (home swipe close, one line per card per frame). External bursts up to 435/s (ptr edge-dump, hover, g2g). Daemon lines are ingested every 2 s (G2D.x:107-141). `hiddenForPerformanceReasons` (pointeruid, 17 lines): built-in contexts rebuilt 7 times; whether old ones are freed is UNKNOWN; none near the failures.

### 1.4 Loops
None in L1: 628 `GLITCH VC ids update` lines, max 24/s; `routing162` count 0. (B1 has the loop; other investigation.)

### 1.5 The D2 episode (best match to the second report)
- D1 20:39:38.949 cover sheet animation kind 2 = lock. Silence 3h22.
- D2 00:01:46.844 first line; 46.872 first interaction (`coordinator: updating active pointer display from 0x0`).
- 00:01:49.588 `interactive Spotlight request` (swipe down began); 00:01:50.572 YouTube opened from Spotlight; 00:01:51.778 cover sheet kind 2 again = unlock (Face ID path). INFERRED (strong).
- 00:01:52.748-55.06 in-app swipe up, home reached; frame timing PROVEN: median 8.0 ms, p90 9.0 ms (outliers 48 ms, 19 ms). The main thread was not starved 6 s after wake. The dead swipes were on the lock and home screens, where nothing is logged.
- 00:01:58 -> 00:02:08 10.65 s with zero lines (home screen). 00:02:08 Calendar launched by icon tap. 00:03:16-00:03:38 five Spotlight requests in 21.7 s (user retrying). 00:04:29 Spotlight, 00:04:31 Dopamine, 00:04:38 userspace reboot.

### 1.6 Logging cost (from code, not measured)
BP_Log (Tweak.x:147-170): format, localtime_r, stat() for rotation, open(O_APPEND), write, close under one mutex: ~30-80 us per line (estimate). Peak 435 lines/s is about 3 % of a core. No fsync; the daemon log is read on its own serial queue with a 2 s timer, 64 KiB per tick (G2D.x:107-141). Cost alone cannot make seconds of delay.

## 2. Audit of our code

No unbounded per-touch/per-frame allocation, no leaked observer, no assertion acquired by our code without a release path (every addObserver, timer, dispatch_after, static collection, associated object, assertion, requireGestureRecognizerToFail and addGestureRecognizer:withType: grepped; touch/gesture/event path read).

- S1 System gesture recognizers and failure requirements we add: G1D.x:1211-1239 G1D_GM_Update registers live-resize 0x22, hover 0x33, overflow 0x35, drag 0x36 with the main display's SBSystemGestureManager, creates a second SBGrabberTongue (0x37) and ties `overflow requireGestureRecognizerToFail: indirect` (G1D.x:1233). The requirement is never undone on disable (G1D.x:1234-1239) and a new tongue / indirect recognizer is built on the next enable. Runs only on Stage Manager toggles. Also G3B.x:506-516 (PiP stash tab 0x77/0x78), G2C.x:193-200 (unhide tap 0x20 / double tap 0x21; external only), Tweak.x:344-372 (wake gesture, external cover sheet only). UIKit's UIGestureEnvironment keeps _gestureRecognizersBlockedFromReset, _delayedTouches and a dependency graph: one recognizer that never resets delays later touches (seconds-scale delays fit). Against: the in-app home swipe (same manager) worked at 00:01:52, so a dead lock/home-screen swipe needs a more specific stuck recognizer.
- S2 Main thread blocked by a synchronous call into a queue that waits on backboardd: G4B.x:1267-1279 G4B_SyncOnQueue / G4B_LPMInv does dispatch_sync on SBLockedPointerManager._stateSerialQueue from the main thread at eight guards (G4B.x:1395-1445): every layout transition begin/end, scene settings update, _updateLockForLayoutState:. If that queue is blocked on backboardd, the main thread waits at the next guard. Against: 8 ms cadence, responsive taps/Face ID. Safe fix regardless: use G4B_LPMInvOnQueue (atomic associated-object read, G4B.x:1279) at the guards.
- S3 Display leftovers in the same boot: focus on a disconnected scene (L1:26326-26330), ghost SBDisplayItem with a gone display enumerated by the snapshot cache at every lock/wake (L1:26899-26931), focus-lock map (G4B.x:1967-1976), 8 rebuilt built-in pointer contexts in pointeruid. These concern keyboard focus and pointer rendering, not the touch path.
- S4 X7Keyboard assertions: acquire side hook-only and bounded (X7Keyboard.x:173-283); release is stock. 44 resign-active acquisitions and 15 suppression acquisitions in L1; releases are logged nowhere, pairing UNKNOWN. A leaked assertion would only affect one display's keyboard/scene deactivation, not touch delivery.
- S5 Hooks that change transition flow: G1B NSAssertionHandler swallowing (never fired in L1), G1D empty-dismiss timer (external only), G1C identifier-invalidation response appended to every transition event (the bounded `ids update` pairs).
- S6 backboardd / pointeruid halves: BBD.x hk_processOne (per pointer event, lock held, cheap); clone-mirror handler with timeouts; G4B_SendCloneMsg on its own queue, 2.5 s timeout, only at connect/disconnect; PTR.x edge dump debug only. No touch-event hook in backboardd.
- S7 Others bounded (G1D receiveTouch, X9Pin, G2 Spotlight hooks).
- Collections all bounded (gG2GPendingExit cap 16; weak tables; BBD maps removed on client exit; selector observers weak; one dispatch timer G2D.x:110).

## 3. Ranked hypotheses

- H1 Stuck state in SpringBoard's gesture machinery. For: symptom set, cured by userspace reboot, we add >= 6 system-gesture recognizers and failure requirements. Against: no proof; in-app home swipe worked; stock 16.0 could do it alone.
- H2 Main thread blocked in dispatch_sync on the locked-pointer queue. For: watchdog history, guards on every transition. Against: 8 ms cadence, responsive taps/Face ID.
- H3 Stock 16.0 bug after 37 h uptime. Test: control session without the tweak.
- H4 Resource growth (memory/fds/ports/threads). Test: vitals line.
- H5 backboardd/hidd delivers touches late. Against: no touch-path hook in BBD. Test: HID latency probe, respring test.
- H6 pointeruid accumulation. Against: not in the touch path. Test: killall pointeruid.
- H7 Logging cost with debug ON. Against: ~3 % of a core. Test: next long session with debug OFF.

3.1 Could the 08:34:08 loop explain slow touch? In mechanism yes (a main thread busy with ~125 ids-update pairs/s makes everything seconds late), in these two reports no: L1 has no such loop and the 8 ms cadence at 00:01:52 excludes a hidden one. A single-display variant is possible in principle (transition event -> identifier-invalidation response append G1C.x:5283, plus the routing162 guard G1B.x:419-486 when a window-drag child owns no index); in L1 the guard never fired.

## 4. UNKNOWN
Whether any recognizer is stuck (nothing logs recognizer state); whether events or the main loop were late 00:01:46-00:01:49 on the lock screen; whether the first report looked the same (its log rotated away); whether X7 assertions, focus locks and system-gesture disable assertions are released in pairs.

## 5. Diagnostic plan

### 5.1 Code to add (ALWAYS = no debug flag)
1. Main run loop stall watchdog (SpringBoard): plain pthread. Every 250 ms, if no ping outstanding: record time, dispatch_async(main) a block that records the pong. If a ping stays outstanding > 1.0 s: take ONE sample and append to <jbroot>/tmp/Backport162.stall.log (truncate at 256 KiB): pc, lr and a frame-pointer backtrace (max 16 frames) of the main thread plus image names/slides once per process start; on return write `stall ended after <ms>`. Side-effect-free sampling: keep mach_thread_self() of the main thread from %ctor; thread_suspend, thread_get_state, copy pc/lr/fp, walk the fp chain only through 16-aligned addresses inside the stack bounds, ptrauth_strip each return address, thread_resume immediately; format and write only after the resume. One sample per stall, max 20 per hour. The same watchdog (no sampler) can go into pointeruid/backboardd later.
2. Touch latency probe: hook -[UIApplication sendEvent:]; for a touches event with a Began touch compute uptime_now - event.timestamp; above 0.30 s append `touchlat <ms> window=<class> loc=<pt> mainStall=<state>` to the stall file, max 1 line/s. Separates events-late (H5) from events-on-time-but-no-gesture (H1) from main-thread-late (H2).
3. Vitals once a minute (~200 bytes): process uptime, phys_footprint (TASK_VM_INFO), thread count, open fd count, mach port count, UIWindow count, gestureRecognizers.count of each system gesture window, sizes of SBSystemGestureManager._recognizingTouchGestures / ._gesturesDisabledAssertions / ._typeToGesture and UIGestureEnvironment._gestureRecognizersBlockedFromReset / ._delayedTouches (ivars by name). Truncate at 256 KiB.
4. On request (darwin notification com.infernowolf19.backport162.dumpstate, handled on the main queue): write <jbroot>/tmp/Backport162.state.txt: per window scene SBSystemGestureManager table (type -> recognizer class/name/state/enabled/view/numberOfTouches), _typeToState, _recognizingTouchGestures, each _gesturesDisabledAssertions entry (reason), isGestureWithTypeAllowed: for 0x13, 0x16, 0x22, 0x2b; the UIGestureEnvironment of the system gesture window and cover sheet window; the main workspace's current transaction chain; focus controller lock assertion reasons; X7 counters.
5. Debug only: log the releases that pair the existing acquisitions (X7 invalidate/relinquish, focus-lock removals in G4B_PruneLocks, G1D_GM_Update calls, every addGestureRecognizer:withType: / requireGestureRecognizerToFail: made by our code).
6. Housekeeping: the G1D log caps `sResizeLogged < 400` / `sLogged < 400` (G1D.x:1496, 1527) are per process and never reset; BP_Log opens/closes per line (optional to change).

### 5.2 What the user does when it happens (plain words)
Do not restart anything first; the order tells us where the fault lives.
1. Note the time; film the frozen screen if possible.
2. Open NewTerm on the iPad (Spotlight still works, only late) or SSH in. Run one line at a time and copy the output: `uptime`; `ps -axo pid,etime,pcpu,rss,stat,comm | grep -E "SpringBoard|backboardd|pointeruid|hidd|mediaserverd"`; `ls -la /var/jb/tmp/Backport162.* /var/jb/var/mobile/Library/Caches/Backport162.*`.
3. Hold both volume buttons and the top button ~1.5 s until a buzz: this starts a system report (sysdiagnose, about 10 minutes; Settings > Privacy & Security > Analytics & Improvements > Analytics Data). Do this BEFORE any restart.
4. Test 1: `killall -9 pointeruid`, wait 10 s, try swipe up on the home screen; note better or same.
5. Test 2 (if still bad): `sbreload`; try the swipes; note better or same. If this fixes it, the fault is inside SpringBoard.
6. Test 3 (if still bad): userspace reboot. If only this fixes it, the fault is in backboardd or another system process.
7. Send /var/jb/tmp/Backport162.log and .log.1, Backport162.stall.log and Backport162.state.txt (after the 5.1 build), the newest 10 files of /var/mobile/Library/Logs/CrashReporter, the sysdiagnose archive, and the better/same answers. Use "Send logs" first if the screen allows.
8. A/B for the logging hypothesis: for the next long session `rm /var/jb/tmp/Backport162.debug`; the always-on stall file and vitals still record what is needed.
Before the 5.1 build exists, steps 2-6 plus the sysdiagnose already answer SpringBoard vs pointeruid vs backboardd.

## 6. Minimal fixes
- S2 (safe regardless): G4B_LPMInv (G4B.x:1273-1278) returns G4B_LPMInvOnQueue(m) with no dispatch_sync.
- S1 (after diagnosis confirms H1): make G1D_GM_Update idempotent and symmetric (reuse the tongue; add the failure requirement only when the tongue was created in this call; remove it or rebuild the overflow recognizer on disable).
- The 5.1 instrumentation is itself the fix for missing observability.
