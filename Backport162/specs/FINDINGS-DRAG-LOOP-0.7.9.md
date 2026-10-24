# FINDINGS-DRAG-LOOP-0.7.9 (Backport162 0.7.9, iPadOS 16.0 20A8372)

Written by an investigator subagent (static analysis plus the user's device logs of 24 Oct 2026); saved here by the main session. Tags: **[PROVEN]** = read in a log line, disassembly or source. **[INFERRED]** = follows from proven facts with one link not observed. **[UNKNOWN]** = not decidable from the data. Device logs were treated as data only. Function names are the anchors (line numbers drift while other agents edit).

Log times are BST (UTC+1); the crash header is UTC (07:34:23 UTC = 08:34:23 BST). Data: u1/2-Backport162.log.1 (18280 lines, pid 70281, loaded 00:04:38), u1/2-Backport162.log (08:34:08-08:34:46), u4/4-Backport162.log.1 + 4-Backport162.log (08:34:08-08:54:14; new SpringBoard loaded at 08:34:23.210), u3 videos IMG_4219.mov / IMG_4220.mov.

## 0. Answers in one screen

1. **There is no runaway loop.** [PROVEN]
   - Every burst of "defsize / auto layout / setKillable / GLITCH ids" lines is bracketed by a pointer button press and release (`coordinator: setting/clearing pointer touch down window scene`). It runs at the input rate while the button is held and ends about 0.6 s after release.
   - After the last burst there is silence: 08:34:12.2 to 08:34:19.6 has no log line.
   - Nothing re-triggers itself: `GLITCH gesture modifier: type=9` appears twice per drag (one root per display); `GLITCH VC ids update` appears only in groups of 8-17 lines at transition phases, never per frame.
   - What the log shows is the normal per-input-event cost of a window drag (about 120 Hz, two displays), amplified by debug logging. Peak 1344 lines/s in the crashed process and 1677 lines/s after the restart. Each line costs stat + open + write + close on the main thread (Tweak.x BP_Log).
   - Two real defects ride along: (a) a second, pointer-driven event stream (the "active pointer display" flips A<->B while a pointer button is held across displays), (b) a stale drag-root child on the other display, caught only by our GUARD at the next drag.
2. **The main thread is loaded but not saturated; touches are served within 12 ms** (backboardd vs SpringBoard timestamps). The 3-day logs contain no such storm, so this does not explain the "slow after hours" report (see FINDINGS-SLOWTOUCH-0.7.9.md).
3. **The crash is a stock 16.0 assertion, not one our hook created.** Site: `-[SBSceneHandle _noteSceneDestroyed:]`, assertion line 0x120 in SBSceneHandle.m: the destroyed FBScene is not the scene the handle tracks. It happened when the close animation of a Clock window ended; that window had earlier been dragged to the other display and lost (section 5). The Backport162.dylib frame (G1B_Setup+7324) is only our `%hook NSAssertionHandler` calling `%orig`. Do NOT "repair" it in the NSAssertionHandler hook: after the handler returns stock continues into `[self _setScene:nil]` on the handle that tracks the other, live scene, which would blank that window. The only safe last line is a hook on `_noteSceneDestroyed:` itself (P6).
4. **The two videos show a lost window, not a black or white one.** In both clips a window dropped on the other display disappears from both displays. The log shows the drop runs as a transition on the source display only (`modes 1->1 from=nil to=nil`); nothing is requested for the target display. No black-with-grid or white frame is visible in the clips. The fix for the lost window, the stale root child and the crash precondition is the multi-display gesture transaction (P1Drag.m, item 1 of CORE-LEFTOVERS). It was not in the build the user ran (no `p1:` lines in the logs).

## 1. Session timeline (u1/2-Backport162.log.1 line numbers) [PROVEN]

Scenes in the crashed process: embedded iPad 0x1049510c0, external (2560x1440) 0x10cafd6c0.

- 08:33:17-18 Clock opened on the iPad (layout 0x283be0000).
- 08:33:23.09-24.31 pointer drag iPad -> external; receiveTouch REFUSED at {1085.7, 1439} (that is the external scene), 86 flips, touch up delivered to the external scene.
- 08:33:29.045 Clock window appears on the external (new layout 0x283adfc00). 08:33:33.834 closed on the external, no crash.
- 08:33:40.507 Clock opened on the iPad again. 08:33:47.87-51.34 second drag iPad -> external: 197 flips; drop = `transition event: phase=1 animated=1 gesture=1 modes 1->1 from=nil to=nil ... effMode=3 stage=com.apple.mobiletimer`.
- 08:33:57.148 window opened again on the external from the dock.
- 08:34:00.33-01.88 drag of the external window inside the external display: two drag roots start (`type=9`): effMode=1 and effMode=3. Completion logs `addwin: transition end src=11 modes 3->3` twice, 25 ms apart.
- 08:34:08.05-11.54 dragged again. `GUARD gesture root ... a new gesture began while the previous 'Gesture' child ... was still active`; only the effMode=3 root is re-begun, so the effMode=1 root is the stale one.
- 08:34:12.2 -> 19.6 no log line. 08:34:22.045 user closes the Clock window. 08:34:23.113-.128 end of the close animation, last line before the crash.

Cycle 1 (opened 08:33:17, closed 08:33:33.8) closed without a crash; cycle 2 additionally has two more drags of the external window, the GUARD, doubled completes and a 3.5 s cross-display pointer drag with 197 flips.

## 2. What the "loop" is

### 2.1 Per-drag facts (scripted over both logs) [PROVEN]
Drag held 1.0-7.0 s: 64-197 pointer flips (0 flips in two drags inside the external display, so the flips are not what drives the layouts), 226-645 layout passes (the `DEFAULT WINDOW SIZE` count undercounts, see 2.4), 1500-4300 log lines (357-860 lines/s). Inside the final burst: 194 passes, intervals 8 ms (92) and 9 ms (46) = the 120 Hz input/display rate; 13 pauses over 40 ms (max 575 ms). Touch up at 08:34:11.536, last layout 08:34:12.165, then 7.4 s of nothing. Nothing self-sustains.

### 2.2 Per-input-event chain in our sources [PROVEN by reading]
1. `SpringBoard -sendEvent:` (Group4Focus.x) -> `BPMultiDisplayCoordinator handleSendEvent:` (cheap, logs only on a scene change).
2. The window-drag recognizer drives SBFluidSwitcherGestureManager. Its delegate `SBMainSwitcherControllerCoordinator -fluidSwitcherGestureManager:didUpdateGesture:` (G1D.x, 16.2 window drag broadcast) forwards the update to the switcher controller of every display with the same window-management style (type 9): G1D_SC_Gesture -> `handleFluidSwitcherGestureManager:didUpdateGesture:` -> the 16.0 handleGestureDidUpdate: body on both displays. This is the 16.2 design (the neighbouring display shows the proposed drop), so two layout passes per input event are expected.
3. Each pass calls: SBSwitcherChamoisSettings layoutAttributesForContainerBounds (G2.x BP_G2_ApplyDefaultSize, source of `[defsize]`); the calculator _appLayoutByPerformingAutoLayoutIfNeededInAppLayout (G2B.m BP2B_AutoLayout; returns nil on every call here = `[g2b] auto layout: a prerequisite is missing`); SBFluidSwitcherItemContainer setKillable: per card (G1D.x, `exttrace: card ... setKillable`).
4. Routing queries log `g1b: routing162: (N identical lines suppressed)` (G1B.x G1B_RT_GuardLastIndex / G1B_RT_GuardLog). N counts guard hits that tried to log, not iterations: 14570 between 08:34:00.660 and 08:34:08.330 (about 54 hits per layout pass).

### 2.3 Second stream: active pointer display flips [PROVEN effect, INFERRED source]
While a pointer button is held and the pointer is on the other display than where it was pressed, `coordinator: updating active pointer display from A to B` / `B to A` alternates, twice per input event. Chain: Group4Focus.x _pointerMovedInScene: -> observers -> G1D_VC_PointerMoved -> SBPointerCrossedDisplayBoundarySwitcherModifierEvent (type 38) -> _dispatchEventAndHandleAction: on the VC of A and of B (28 `g1b: _handleEvent: type 38` lines per flip). backboardd lines show the SpringBoard pid holds global routes on both displays at the button-held display change; the 0.7.9 X9Pin.x requests those routes with pinOnButtonDown: YES. INFERRED: the log does not show which route produced which flip. 16.2 itself pins hit-test contexts on button down (POINTER-CROSS-0.7.4.md 2.1), so 16.2 gets two streams as well; what it does downstream is not decoded.

### 2.4 Logging artefacts that inflate the picture [PROVEN]
- `[defsize]` is logged "once per change" but gBPG2DSLastLog (G2.x) is one global string shared by both displays, so the 4 lines are reprinted every pass.
- `[g2b] auto layout: a prerequisite is missing` and `exttrace: card ... setKillable` are logged unconditionally per call.
- BP_Log (Tweak.x) does stat(gLogPath) + open + write + close per line on the calling (main) thread under a global mutex, plus two NSString formats: 5400-6700 syscalls/s while layouts run.
- BP_OnName (Tweak.x) takes a global mutex and does a linear strcmp scan of up to 160 slot names per call; the routing guard (G1B_RT_On) calls it about 12000 times/s during a drag.
- G1B_RT_GuardLastIndex (G1B.x) builds both NSStrings before G1B_RT_GuardLog decides to suppress them (14570 times in 1.2 s).
None of these is a loop; together they are the load.

### 2.5 Comparison with 16.2
- **REVIEW-CORE-0.7.9.md H1 is wrong on one point** [PROVEN, register flow of 16.2 _workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel: at 0x1c74b1478]: x23 = manager (arg 3), `sc = [manager switcherController]`, display = [[sc windowScene] _fbsDisplayIdentity].currentConfiguration, then createRequestWithOptions:0 displayConfiguration:. 16.2 does NOT pick the controller of request.appLayout; request.appLayout is only used for layout-state map lookups. Do not apply H1's proposed patch as written. The cross-display placement in 16.2 is done by +[SBMainWorkspaceTransitionRequest ancillaryTransitionRequestsForTransitionRequest:] (0x1c7892c18) -> -[SBSwitcherController _ancillaryTransitionRequestForTransitionRequest:] (0x1c76066fc) and the per-display child transactions in _runSceneLayoutTransactionForTransitionRequest:updateScenes: (0x1c72d771c: ancillaryTransitionRequestsForTransitionRequest: -> one initWithTransitionRequest:delegate: child per other display). That is what P1Drag.m ports.
- _pointerMovedInScene: and the sniffers are ported literally, so the flip logic is 16.2's code; what differs is which events backboardd feeds it.
- 16.2 keeps async rendering on during a cross-display drag (REVIEW-CORE M7); P1Drag p1_asyncdrag covers it.

### 2.6 Stale drag-root child (GUARD) [PROVEN symptom, INFERRED mechanism]
Each drag starts a BP162ContinuousExposeWindowDragRootSwitcherModifier gesture child on both displays. The child is finished only when a transition of its own display reaches the root (comment above G1C_GR_Guard). A drag that starts and ends on display B transitions only B; A's child gets didEndGesture through the broadcast but no transition, so it stays until the next drag. Evidence: the guard fires at 08:34:08.326 and only one new root is begun. Every drop also runs two extra non-animated transitions with gesture=1 (phase 2/3 pairs at 02.444-02.470 and 12.131/12.156, each followed by `addwin: transition end src=11`), so a drop runs three layout transitions per display; cause UNKNOWN (REVIEW-CORE H2 or a double completion). GUARD fired once in the logs, intermittent.

## 3. Saturation, touch service, the 3-day log
- Duty cycle cannot be measured from the logs (no signposts): inside a burst, visible work spans 4-8 ms of each 8.3 ms frame; load high, saturation not proven.
- Touches are served promptly [PROVEN]: display change with button held 08:33:44.711 backboardd vs 44.719 SpringBoard (8 ms); 48.495 vs 48.502 (7 ms); releases 51.323 vs 51.335, 45.309 vs 45.321, 24.297 vs 24.308 (11-12 ms). No backlog at either end of a burst.
- Pauses of 0.14-0.56 s inside bursts: afterwards the passes resume at normal 8 ms spacing, not faster, which fits "no input" better than "main thread blocked" [INFERRED].
- The 3-day logs contain no storm [PROVEN]: 0 `identical lines suppressed`, no run of 40+ DEFAULT WINDOW SIZE passes, largest dense `VC ids update` run 24 lines in 50 ms, 31 flips in total. It is an older build. This loop does not explain "slow after some hours"; cause UNKNOWN.
- Discriminators for the next slow phase: (1) does it still happen with Backport162.off present; (2) sample SpringBoard during the slowness; (3) slot exhaustion: kSlotMax = 160 in Tweak.x; when exceeded BP_SlotFor returns -1 and BP_OnName answers YES forever, so kill switches silently stop working; verify the number of distinct BP_OnName strings stays below 160.

## 4. The crash

### 4.1 What the assertion is [PROVEN, 16.0 SpringBoardUI / SpringBoard disassembly]
The string at 0x1f119e115 belongs to `-[SBSceneHandle _noteSceneDestroyed:]` at 0x1f1185b3c (SpringBoardUI 16.0, SBSceneHandle.m). Crash frame 4 is return address 0x1f1185c20 (0x2260c1c20 minus slide 0x34F3C000). Pseudocode:

```
- (void)_noteSceneDestroyed:(FBScene *)destroyed {
    NSAssert(_manuallyControlsLifecycle, @"Cannot have scene creation/destruction invoked when using a scene monitor for lifecycle events.");  // line 0x11f
    NSAssert(_scene == destroyed, @"Scene destroyed did not match the scene being tracked.");                                                   // line 0x120  <- the crash
    [self _setScene:nil];
}
```

"Tracked scene" is the handle's _scene ivar (+0x10). After a failed NSAssert the handler returns and the code continues into _setScene:nil.

Call path: FBSceneManager destroyScene:withTransitionContext: (0x1a3064e88) -> FBScene _deactivateAndInvalidate -> FBSceneWorkspace scene:deactivateAndInvalidate:withError:block: -> BSEventQueue flushAllEvents -> FBSceneManagerObserver sceneManager:didDestroyScene: -> **SBSceneManagerCoordinator sceneManager:didDestroyScene:** (0x1c5ea300c; picks the manager from [[scene settings] sb_displayIdentityForSceneManagers] via sceneManagerForDisplayIdentity:) -> SBSceneManager _removeScene:forDestroyEvent: (0x1c5f75e88; finds the handle by scene identity via existingSceneHandleForSceneIdentity: 0x1c5e3d058 and calls [handle _noteSceneDestroyed:scene]) -> SBMainWorkspace _destroyApplicationSceneEntity: -> SBMainSwitcherControllerCoordinator _performSceneDestructionForModelRemovalResults: -> switcherContentController:layoutStateTransitionDidEndWithTransitionContext: -> end of the close animation.

So the window close finished, the scene was destroyed, and the manager the coordinator chose holds a handle for the same scene identity whose _scene is a different FBScene object.

### 4.2 Ours or stock?
- The assertion is stock [PROVEN]: no hook of ours touches _scene, _setScene:, _noteSceneDestroyed: or existingSceneHandleForScene:. Our only related hooks: sceneHandle:didDestroyScene: (G4B.x) and takeScene:fromSceneManager: (G4B.x G4B_Migrate, Y1Workspace.x; Y1Workspace.x is not in the 0.7.9 build).
- What our port changes that reaches it: (1) a window dragged to the other display is removed from the source layout but its scene lives on and nothing places it on the target; (2) the same app is then reopened on the target display from the dock; (3) scenes move between SBSceneManagers with takeScene:fromSceneManager: (16.0 body 0x1c5f72cf4).
- Candidate mechanisms [INFERRED; each leaves handle._scene != destroyed scene]: **C1** an orphan scene/handle on display A (the dropped window laid out nowhere) plus a handle for the same identity on display B after the dock reopen; **C2** the scene's settings display identity differs from the manager that tracks it at destroy time (settings update async, every drop runs 3 transitions); **C3** stale _draggingAppLayouts in G1D.x (didEndGesture: removes selectedAppLayout; a drag whose end is not broadcast leaves it, and appLayoutsForSwitcherController: keeps serving it to the other display). Cycle 1 closed without a crash, so the trigger is the extra state of cycle 2; favours C2/C3 over C1, n = 1.

### 4.3 Minimal safe fix
Root fix: land P1Drag.m (P0). Logged last line: P6, with the probe that settles C1/C2/C3.

## 5. Lost windows; black grid / white blank windows

### 5.1 What the data shows [PROVEN]
- Videos: in 4219 the Clock window is dragged off the iPad and vanishes from both displays (iPad ends on its home screen with a 4-card strip, monitor shows wallpaper only). In 4220 the window on the monitor is dragged back towards the iPad and is gone from the monitor and not on the iPad. Reopened from the dock it appears normally with the zoom animation. No frame shows a black screen with grid or a white window.
- Drop iPad -> external: `phase=1 ... modes 1->1 from=nil to=nil ... effMode=3 stage=com.apple.mobiletimer`, then `phase=2 ... effMode=1 stage=nil`; the iPad goes from "Clock on stage" to nothing and no transition is requested for the target display. Drop external -> iPad: the same on the external. In both directions the dropped window ends up in no layout while its scene still exists = absence of the 16.2 ancillary request (REVIEW-CORE H1 with the corrected selection rule).

### 5.2 Candidates for the black-grid / white window [INFERRED, no frame of it in the data]
1. A handle whose _scene was cleared while its scene is alive: _noteSceneDestroyed: ends in _setScene:nil; if a destroy (or a repaired assertion) reaches the handle that now tracks the reopened scene, the window's host view has no scene and shows a blank host. The only mechanism found that produces a blank window from a stock path our port can reach. Probe: the P6 log line.
2. A container created for a scene still managed by the other display's scene manager (reopen before or without takeScene, or takeScene run twice because of the doubled completes). The container would show the placeholder/snapshot host (the grids) until the content state is ready. Probe: at every `transition end`, per layout item log [handle contentState], isContentReady, [[scene settings] sb_displayIdentityForSceneManagers] against the container's window-scene display, host view window non-nil, hidden, layer context id.
3. Async rendering not kept on for the destination during the cross-display drag (REVIEW-CORE M7); P1Drag p1_asyncdrag covers it (unverified).

## 6. Patch proposals (owner marked; order = value)

**P0 (core agent): land P1Drag.m and re-test before anything else.** After the change the log must show a transition on the target display with `to=<bundle>` (not `modes 1->1 from=nil to=nil`), `p1:` lines for the ancillary request and takeScene, no GUARD at the next drag, exactly one `addwin: transition end` per display per drop.

**P1 (core agent), G1B.x G1B_RT_GuardLastIndex / G1B_RT_GuardLog: do not format strings that will be suppressed.** Build the key/message lazily in a block; test the suppression condition first:
```objc
static void G1B_RT_GuardLogL(int kind, Class cls, const void *all, NSUInteger idx, NSString *(^msg)(void)) {
    static int lk; static Class lc; static const void *la; static NSUInteger li; static double lt; static unsigned suppressed;
    double now = CFAbsoluteTimeGetCurrent();
    if (lk == kind && lc == cls && la == all && li == idx && now - lt < 2.0) { suppressed++; return; }
    if (suppressed) BP_Log(@"g1b: routing162: (%u identical lines suppressed)", suppressed);
    suppressed = 0; lk = kind; lc = cls; la = all; li = idx; lt = now;
    BP_Log(@"%@", msg());
}
```
At the three call sites pass (kind, object_getClass(modifier), (__bridge const void *)all, i, block returning the stringWithFormat). Keep BP_LogEnabled() as the outer test.

**P2 (core agent): per-display or throttled logging in the layout hot path.** G2.x BP_G2_ApplyDefaultSize: replace gBPG2DSLastLog by a static NSMutableDictionary keyed by NSStringFromCGRect(bounds), changed = ![dict[k] isEqualToString:sig] (removes about 4 lines per pass). G2B.m `[g2b] auto layout: a prerequisite is missing`: log the first occurrence, then at most once per 2 s with a count. Separate task for the G2B owner: BP2B_AutoLayout returns nil on every call; no success path of `auto layout` appears in either log, so the ported 16.2 auto layout (overlap avoidance on drop) never runs and the 16.0 body is skipped: add a one-time log naming the failing check. G1D.x setKillable: log only when the value changed since the last call on that card.

**P3 (display agent, owner of Tweak.x): BP_Log and BP_OnName.** BP_Log: keep a static log fd opened O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC; do the stat() rotation test at most once per second; on rotation rename and reopen; no close per line; optionally append through a serial dispatch queue so the main thread does not block on disk, flushing on the crash path of BP_InstallCrashRecorder. BP_OnName / BP_SlotFor: cache the slot index per call site (static int s = -2 plus a cached lookup macro); make kSlotMax overflow loud (log once) instead of silently answering YES.

**P4 (core agent), G1D.x fluidSwitcherGestureManager:didEndGesture: plus G1C.x: finish the other display's drag root when the drag ends.** After the broadcast, for every other controller with a different switcher and type == 9, call a G1C_FinishStaleGestureChild (the body of G1C_GR_Guard without the phase test: stale = G1C_GR_GM(root); if (stale) { setState:1; [root removeChildModifier:stale]; BP_Log "GUARD(end) ..." }). Keep the existing GUARD. If P1Drag's shared transaction already completes the other display's child this is redundant and can be dropped; needs a device check that the destination root is not needed after didEnd.

**P5 (display agent), Group4Focus.x _pointerMovedInScene: stop the flips while a pointer button is held. Probe first.** Step 1, log-only (about 5 lines, next build): log the first 12 flips of a press with ws, _touchDownWS, [t locationInView:[t view]], window bounds, contextID, [t phase]. Expected if the diagnosis is right: the events whose scene is the press scene have a location outside that window's bounds (the pinned route). Step 2, only if confirmed: `if (_touchDownWS && !CGRectContainsPoint(window.bounds, loc)) return;` before updating _activePointerWS (use the location test, not scene equality, which would block the legitimate first crossing). Fast A/B without code: create <jbroot>/tmp/Backport162.off.pinbuttondown (X9Pin.x switch); if the flips disappear the pin option is the cause.

**P6 (display agent; scene tracking is G4B/Y1Workspace territory): logged last line for the crash.** New %hook SBSceneHandle (SpringBoardUI, hookable by name; ivars _scene +0x10, _manuallyControlsLifecycle +0x20), switch y1_scenedestroyguard:
```objc
- (void)_noteSceneDestroyed:(id)destroyed {
    id tracked = object_getIvar(self, class_getInstanceVariable([self class], "_scene"));
    if (BP_OnName("y1_scenedestroyguard") && tracked != destroyed) {   // stock asserts (SBSceneHandle.m:0x120) then runs _setScene:nil on the live handle
        BP_Log(@"GUARD scene handle %p tracks scene %p (%@), destroy of %p (%@) ignored; display of destroyed scene %@", self, tracked, [tracked identifier], destroyed, [destroyed identifier], [[destroyed settings] sb_displayIdentityForSceneManagers]);
        return;
    }
    %orig;
}
```
Probe, log-only, before the skip, to settle C1/C2/C3: handle pointer, _scene pointer and identifier, destroyed scene pointer; [[destroyed settings] sb_displayIdentityForSceneManagers]; the manager that owns the handle; existingSceneHandleForSceneIdentity: of both displays' managers; the contents of G1D_Dragging. Never repair through NSAssertionHandler.

**P7 (core agent, only after P0): the two extra instant gesture transitions per drop (2.6).** Log a one-time [NSThread callStackSymbols] (first 8 frames) at `addwin: transition end src=11`; decide whether they come from our G1C_Txn_Complete forwarder (the 16.0 manager already calls completeGestureWithTransitionRequest:, and our 16.2 entry point forwards again when gTxnFwdDepth == 0) or from the 16.0 ids-update blocks (REVIEW-CORE H2).

## 7. Proven / inferred / unknown

- Bursts are input-driven, end 0.6 s after release, no self-sustaining cycle: PROVEN (9 drags, 2 processes, silence 08:34:12.2-19.6).
- About 120 layout passes/s on two displays during a drag: PROVEN. Debug logging cost: PROVEN (code and rates); share of main thread UNKNOWN.
- Touch events served within 12 ms at both ends of every burst: PROVEN. Main thread saturated: NOT proven.
- 3-day slowness related to this: NOT supported; cause UNKNOWN.
- Flips alternate scenes twice per input event while a button is held across displays: PROVEN; caused by pinOnButtonDown routes: INFERRED.
- Stale drag-root child / GUARD: PROVEN symptom; mechanism INFERRED.
- Crash site = SBSceneHandle _noteSceneDestroyed: assertion 0x120, stock code, _scene != destroyed: PROVEN. Which handle/scene pair mismatched: UNKNOWN (C1/C2/C3); probe in P6.
- Dropping a window on the other display loses it (no target-display request): PROVEN (log and both videos).
- Black grid / white window cause: UNKNOWN; not visible in the 2 clips; candidates in 5.2.
- REVIEW-CORE H1 wording (request display = appLayout's controller): WRONG for 16.2; 0x1c74b1478 uses [manager switcherController]; placement is via the ancillary-request mechanism.

Next device test that would settle most UNKNOWNs: a build with P1, P2, P3, P5 step 1 and the P6 probe, Backport162.debug on. Drag iPad -> external -> iPad twice, reopen from the dock, close. Send the log pair and a screen recording that includes the monitor at the moment a blank or black window appears, and note the wall-clock time shown in the iPad status bar.
