# DIAG (0.7.9): always-on instruments for the slow-touch / dead-gesture report

Implements section 5.1 items 1-4 of `FINDINGS-SLOWTOUCH-0.7.9.md`. Code: `Z1Diag.x` (one file, `Z1_Setup()` is the last call of the `%ctor` in `Tweak.x`). Switch `diag`, default ON; kill file `<jbroot>/tmp/Backport162.off.diag` (or the global `Backport162.off`), tested once a second, so it works at run time without a respring. No `Backport162.debug` is needed for anything below. Nothing was run on a device; section 6 lists what is unproven.

`<jbroot>` is `/var/jb` on Dopamine rootless; the files are in the directory `BP_Log` writes to (`ROOT_PATH_NS(@"/tmp")`), so SpringBoard may write them.

## 1. Files

| file | written when | content | cap |
|---|---|---|---|
| `Backport162.stall.log` | process start; every stall; late touches; dump requests | process header, watchdog and touchlat lines (section 2) | 256 KiB: truncated to zero, then the process header is written again |
| `Backport162.vitals.log` | every 60 s (first line 30 s after the start), main queue | one `vitals` line (section 3) | 256 KiB, same rule |
| `Backport162.state.txt` | on request (section 4) | the gesture / workspace state dump, replaced on every request | 1 MiB |

## 2. Backport162.stall.log

Process header (once per process start, text of the LAST header belongs to the running process):
```
--- process start pid=69053 os=20A8372 (...) ---
image (main) SpringBoard hdr=0x... slide=0x... path=...
image UIKitCore hdr=0x... slide=0x... path=...
image BackBoardServices ...
image Backport162.dylib ...
watchdog started (period 250 ms, stall > 1000 ms, sampler ready)
touchlat hook installed (SpringBoard sendEvent:, threshold 300 ms, 1 line/s)
```
`slide` is the shared-cache slide for the system images: unslid address = address - slide, which is the address in the cache of build 20A8372 (the addresses in the other specs, e.g. `0x1c6319958`).

Stall sample (watchdog; max 20 per hour, one per stall, only after a 20 s start-up grace):
```
HH:MM:SS.mmm stall begin: main queue did not answer for 1013 ms; main thread run=WAITING cpu=0/1000 suspendCount=0 ok=1
   pc=0x... lr=0x... sp=0x... fp=0x...
   bt(12): 0x... 0x... ...
   sym: UIKitCore+0x1a2b3c(sym+0x10) ... 
HH:MM:SS.mmm stall ended after 4210 ms
```
* `run` / `cpu` come from `thread_info` taken just before the sample: `RUNNING` with a high cpu = the main thread is busy (a loop or heavy work); `WAITING` with cpu 0 = it is blocked (lock, `dispatch_sync`, mach message): the `bt` says on what.
* `bt` = frame-pointer chain, at most 16 return addresses, PAC-stripped. `pc`/`lr` are separate (`lr` repeats the first `bt` entry except in leaf functions).
* `sym:` is the same addresses as `image+offset(symbol+offset)` through `dladdr`, written as a SECOND line (it takes dyld locks; if the main thread holds one the first line is still there). System symbols are mostly stripped: symbolicate offline with `address - slide` against the cache of 20A8372; offsets in `Backport162.dylib` against the CI build of the same commit.
* `stall begin: ... (no sample: 20 per hour used)`: the hourly sample budget is used; at most 60 begin lines per hour.
* `stall ended after N ms` = time from the ping to the answer of the main queue.

Touch latency (hook of `SpringBoard -sendEvent:`; touches events whose `now - event.timestamp` exceeds 0.30 s; max 1 line/s, `suppressed=N` counts the lines skipped):
```
HH:MM:SS.mmm touchlat 812 ms phase=began window=SBSystemGestureWindow loc=(512,1190) touches=1 suppressed=0 mainStall(inStall=0 pingAge=3ms last=1432ms endedAgo=5210ms total=3)
```
`mainStall(...)`: `inStall` = a stall is open; `pingAge` = age of the watchdog's pending ping on the main queue (0 = none pending); `last` / `endedAgo` / `total` = last stall length, time since it ended, count since process start. One extra line proves the clock: `touchlat first touch event seen: latency X ms (...)`: X must be a few ms; if it is hours, `event.timestamp` is on another clock and every touchlat verdict is void.

How to read it (the three-way split of the findings, section 5.1 item 2):
* touchlat lines with a stall in `mainStall` / a `stall begin` in the same second: the main thread was late (H2 family); the sample says where.
* touchlat lines with `pingAge` ~0 and no stall: the main thread was free but the event arrived late: delivery (backboardd / hidd, H5).
* NO touchlat lines while the swipes are dead and the vitals show a stuck gesture collection: events arrive on time and the gesture machinery does not act on them (H1).

## 3. Backport162.vitals.log

One line a minute, on the main queue (never from the watchdog thread), with a time stamp:
```
HH:MM:SS.mmm vitals up=48120 s(13h22m) awake=30100 s boot=91000 s footprint=210.5MB thr=61 fds=143(vn=90 so=20 kq=10 pipe=8 oth=15) ports=2210(recv=900 dead=12) scenes=1 uiwin=9 winrecs=[SBSystemGestureWindow:12,...] | sgm[main] sgwRecs=12 recognizing=0 touchGestures=7 disableAsserts=0 typeToGesture=23 typeToState=23 | uigenv blockedFromReset=0 delayedTouches=0 delayedTouchesToSend=0 delayedPresses=0 needUpdate=0 needReset=0 needRemoval=0 dirty=0 preUpdate=0 nodes=310 | stalls=0 touchlat=0
```
`up` counts sleep, `awake` does not; `boot` is the device uptime. `fds` split by type (vnode / socket / kqueue / pipe / other), `ports` with receive rights and dead names (a growing dead count is a leak signature). `winrecs` = windows with gesture recognizers (up to 8) and their count. `sgm[...]` = the `SBSystemGestureManager` of each window scene: its collection sizes read by ivar NAME (`_recognizingTouchGestures`, `_touchGestures`, `_gesturesDisabledAssertions`, `_typeToGesture`, `_typeToState`); `uigenv` = the `UIGestureEnvironment` of the application (`UIApplication.__gestureEnvironment`): `_gestureRecognizersBlockedFromReset`, `_delayedTouches`, ... A `-` means the ivar does not exist on this build. The interesting growth signs: `blockedFromReset` or `delayedTouches` above 0 for minutes, `disableAsserts` above 0 on an idle home screen, any counter that only grows.

## 4. Backport162.state.txt (on request)

From a terminal (SSH or NewTerm), as root or mobile:
```
notifyutil -p com.infernowolf19.backport162.dumpstate
cat /var/jb/tmp/Backport162.state.txt
```
The handler runs on the main queue (a stalled main thread answers late) and appends `state dump written ...` to the stall log. Content, per window scene (every section is guarded; one failing section prints `(section ... aborted)` and the rest continues):
* scene class, main / external, activation state; its windows (class, hidden, alpha, interaction, gesture recognizer count; recognizer lines for the cover sheet and system gesture windows);
* the scene's `SBSystemGestureManager`: `windowForSystemGestures` and its recognizers, the table `_typeToGesture` (type in hex -> recognizer class, name, state, enabled, view, touch count, delegate, and `env=same|DIFFERENT` = whether the recognizer's own `_gestureEnvironment` is the application one) with `_typeToState`, `_recognizingTouchGestures`, `_touchGestures`, every `_gesturesDisabledAssertions` entry (its description carries the reason), `_gestureTypesAllowedWhileDisableAssertionsExist`, `isGestureWithTypeAllowed:` for 0x13, 0x16, 0x22, 0x2b, `isAnyTouchGestureRunning`, accessibility disable, and the presence of the event deferring rule / pointer routing assertion / allowed token;
* the `UIGestureEnvironment`: counts of every list, the members of `_gestureRecognizersBlockedFromReset` (a recognizer that never resets delays later touches, the H1 candidate), `_lastBlockedResetEvaluationMachTime` as seconds ago, the first `_delayedTouches` entries;
* `SBMainWorkspace`: the current transaction chain (class, started / running / complete / failed, age, children, depth <= 8, 60 nodes), the main workspace and keyboard focus controller assertions with their reasons (`_springBoardFocusLockAssertions`, `_springBoardFocusRedirections`, `_appFocusRedirections`, `_springBoardWindowFocusStealingAssertions`, `_preventFocusForSceneAssertion`, `_lockKeyboardFocusAssertion`);
* the vitals line and the stall state at that moment. X7 counters: `X7Keyboard.x` exports none, so none are dumped.

Selectors and ivars were confirmed against the class dumps of 16.0 (`sb160n_objc.txt`, `UIKitCore160n.txt`): `SBWindowScene.systemGestureManager`, `isMainDisplayWindowScene`, `isExternalDisplayWindowScene`; `SBSystemGestureManager` ivars `_typeToGesture _gestureToType _typeToState _recognizingTouchGestures _touchGestures _gesturesDisabledAssertions _gestureTypesAllowedWhileDisableAssertionsExist _gesturesPreventedByStylus _stylusPriorityRecognizer _systemGestureEventDeferringRule _pointerEventRoutingAssertion _systemGesturesAllowedToken _systemPointerContextIDAssertion _indirectTouchLifecycleMonitor _displayIdentity`, methods `windowForSystemGestures isGestureWithTypeAllowed: isAnyTouchGestureRunning areSystemGesturesDisabledForAccessibility`; `UIApplication._gestureEnvironment` (ivar `__gestureEnvironment`) and the `UIGestureEnvironment` ivars listed above; `SBMainWorkspace` `+sharedInstanceIfExists`, `currentTransaction`, ivars `_keyboardFocusController _lockKeyboardFocusAssertion`; `SBWorkspaceKeyboardFocusController` ivars `_springBoard*Assertions`, `_appFocusRedirections`, `_preventFocusForSceneAssertion`, `_windowSceneWithFocus`, `_externalSceneWithFocus`; `BSTransaction` `childTransactions hasStarted isRunning isComplete isFinishedWorking isInterrupted isFailed _startTime`; `BSCompoundAssertion reasons isActive`.

## 5. Design and cost

Safety rules (the file header repeats them):
* The watchdog thread (plain pthread, 512 KiB stack, name `Backport162.stall`) pings with `dispatch_async(main)` of a capture-free block (no allocation). Sampler window: `thread_suspend` ... `thread_get_state` ... `thread_resume`; inside it only `thread_get_state`, integer arithmetic and reads of the suspended thread's own stack words. No malloc, no ObjC, no lock, no printf, no dladdr, no logging; the three mach calls are resolved with `dlsym` beforehand, so no lazy binding stub (dyld lock) can run there. The resume sits on the only path after a successful suspend (no early return). Frame walk: `sp` inside the stack bounds (`pthread_get_stackaddr_np` / `pthread_get_stacksize_np` of the main thread, taken on the main thread), `fp` 16-aligned, between `sp` and the stack top minus 16, strictly climbing, at most 16 frames; every return address `ptrauth_strip`-ped (arm64e only, `__has_feature(ptrauth_calls)`); `pc/lr/fp/sp` read with the `arm_thread_state64_get_*` accessors, which strip. Formatting and file writes happen after the resume.
* One sample per stall, 20 per hour; 20 s start-up grace. Disabled switch: the thread keeps sleeping, sends no ping, writes nothing.
* Touch probe: runs on the main thread; ordinary event = type test plus two clock reads (about 100 ns); the slow path (allTouches, one `open/write/close`) runs only for events later than 300 ms and at most once a second.
* Vitals and dump read UIKit / SpringBoard objects only on the main queue; every ObjC access goes through `respondsToSelector:` / `class_getInstanceVariable` with an object-type check (`BP_ObjIvar`) / `@try`; a missing ivar prints `-`.
* Why the touch hook is on `SpringBoard`, not `UIApplication`: `Group4Focus.x` already hooks `SpringBoard -sendEvent:` (an own override that captures UIApplication's implementation when added); a hook of `-[UIApplication sendEvent:]` installed after it would be bypassed by that captured pointer. A second hook of the same SpringBoard method from another group stacks as `%orig`, and being installed last it runs first, i.e. measures before any other code of ours. `-[UIWindow sendEvent:]` was rejected (per window, later in the chain, subclasses may not call super).

Cost estimate (from code, not measured): the watchdog wakes 4 times a second and posts one empty block to the main queue (about 20-50 us of main-thread time per ping, well below 0.05 % of a core; it does keep a periodic wake-up while the screen is off); the sampler window is a few microseconds and happens at most 20 times an hour; vitals about 1-3 ms per minute on the main queue (mach port listing and fd listing are the largest parts); the dump is on request only (tens of ms). Disk: at most 2 x 256 KiB + the dump.

## 6. Unproven (needs the device)

* That `UIEvent.timestamp` and `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` are the same clock: the `touchlat first touch event seen` line answers it.
* That `thread_suspend` / `thread_get_state` of the main thread of SpringBoard are allowed from inside the process on Dopamine (own-task thread ports; expected yes) and that the arm64e accessors return stripped values (a bad value would show as nonsense in `pc` or an empty `bt`; the walk is bounds checked, a wrong `pc` cannot crash). `ok=0` in the stall line = `thread_get_state` failed.
* That `pthread_get_stacksize_np` of the main thread matches the mapped stack (if it is too small the walk is skipped: empty `bt`, `pc/lr` still shown).
* That the hook of `SpringBoard -sendEvent:` receives the touch events of the system gesture windows in 16.0 (the first-touch line proves it receives touches at all).
* That `proc_pidinfo(PROC_PIDLISTFDS)` works for SpringBoard (else the fd count is a bounded `fcntl` probe, shown as `(probe<=N)`).
* The meaning of the values (which assertion description carries a readable reason, whether `_typeToState` values are numbers) is read from the first dump; the dump prints descriptions rather than guessing.
* The stall log is not collected by "Send logs" yet (section 7).

## 7. For RPT.x (owner: another agent; not changed here)

The Settings "Send logs" collector should include, in addition to what it collects today:
* `<jbroot>/tmp/Backport162.stall.log` (whole file, at most 256 KiB),
* `<jbroot>/tmp/Backport162.vitals.log` (whole file, at most 256 KiB; the last 60 lines are enough if a cap is needed),
* `<jbroot>/tmp/Backport162.state.txt` (at most 1 MiB; only exists after a dump request),
* optionally: before collecting, post the darwin notification `com.infernowolf19.backport162.dumpstate` and wait about 1 s, so a report taken in the broken state contains a fresh state dump (the handler runs on SpringBoard's main queue; it answers late when the main thread is stalled, which is itself information).

## 8. What the user does (addition to FINDINGS section 5.2, step 2)

After `uptime` and `ps`: `notifyutil -p com.infernowolf19.backport162.dumpstate; sleep 2; ls -la /var/jb/tmp/Backport162.*` and send `Backport162.stall.log`, `Backport162.vitals.log`, `Backport162.state.txt` together with the rest. Do this BEFORE `killall pointeruid` / `sbreload`, because the state dump is lost with the process.
