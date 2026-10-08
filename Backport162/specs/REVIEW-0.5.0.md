# Backport162 0.5.0 adversarial review

Target: iPadOS 16.0 (20A8372) SpringBoard, arm64e, rootless Dopamine. Reference: 16.2 (20C65).
Sources read in full: Tweak.x, Group4Connect.m, Group4Focus.x, BP.h, Makefile, control, STATUS.md, README.md, the group4 specs and the 0.5.0 diff.
All addresses are unslid cache vmaddrs. "16.0 x" = 20A8372, "16.2 x" = 20C65. No device was available, so everything marked UNVERIFIED is a reading of the binaries only.
Logos output for Tweak.x and Group4Focus.x was generated and read (`scratchpad/rv/Tweak.x.mm`, `rv/G4.mm`).

Severity key: CRASH = can bring SpringBoard down (respring loop if it happens at launch), WRONG-BEHAVIOUR = feature does the wrong thing or nothing, MINOR.

---------------------------------------------------------------------------------------------------

## Ranked findings

| # | sev | where | one line |
|---|-----|-------|----------|
| F1 | CRASH (latent, conditional) | Group4Connect.m:619-628 (nilock) | `SBNonInteractiveDisplaySceneManager` is made a `SBSuspendedUnderLockManagerDelegate` but does not implement the required `runningApplicationScenes:`; the first un-lock after a lock sends an unrecognised selector. |
| F2 | CRASH-risk at launch (UNVERIFIED), default ON | Group4Focus.x:404-439 (directhook) | Inline hook of a function whose first instruction is a PC-relative `cbz x0`; relocation and arm64e signing of the returned trampoline pointer depend on the hooking library. A failure kills SpringBoard on the first keyboard-focus evaluation. |
| F3 | WRONG-BEHAVIOUR (feature dead), high confidence | Tweak.x:226,285 (blank wake gesture) | 16.0's `SBExternalDisplaySystemGestureManager` refuses to enable system-gesture type 0x42, so the click-to-wake gesture is registered but never armed. With `nowindow` now on by default there is no fallback. |
| F4 | WRONG-BEHAVIOUR + thread-safety, default ON | Group4Focus.x:693-707 (lockedptr) | Runs on SBLockedPointerManager's private serial queue yet walks SBWindowSceneManager / UIKit objects; also swaps 16.0's `<main>` display key for the hardware identifier, which gains nothing and may break the existing lock. |
| F5 | WRONG-BEHAVIOUR, default ON | Group4Focus.x:541-552, 282-327 (activedisplay) | After any finger touch on the iPad the active display sticks to the iPad; the pointer sniffer path is probably dead, so mouse use on the external display no longer moves it. Baseline 16.0 follows keyboard focus. |
| F6 | MINOR/WRONG-BEHAVIOUR | Group4Focus.x:335-339, 442-447 (gesturegate) | Pointer touch-down scene is never cleared on a cancelled touch, so Control Center / switcher pans from the iPad are rejected until the next pointer touch-up. |
| F7 | MINOR | Tweak.x:285 | `addGestureRecognizer:withType:` asserts (NSInternalInconsistencyException) on a duplicate type; not wrapped. |
| F8 | MINOR | several | Unlocked static cache races, post-suppression refocus skipped if `disconnect` toggled mid-teardown, see section 8. |

---------------------------------------------------------------------------------------------------

## F1  nilock: missing required delegate method  (CRASH, latent)

File: Group4Connect.m:619-628 (BP4_AddMethod list), :446-515.

Scenario
1. `SBNonInteractiveDisplaySceneManager` (NI) exists (it is a real 16.0 class, `sb160n_objc.txt:78267`, only `_shouldAutoHostScene:`).
2. `hk_niInit` (Group4Connect.m:508) registers observers on the new NI manager for `SBExternalDisplayCoverSheetDidPresent/Dismiss` (now on by default, `covernote` posts them from `_setCoverSheetWindowVisible:fadeDuration:`).
3. Cover sheet Present -> `BP4_NI_SetLockedFull(YES)` -> creates `SBSuspendedUnderLockManager` with the NI manager as delegate. Works (VisibleScenes is implemented).
4. Cover sheet Dismiss -> `setSuspendedUnderLock:NO` -> 16.0 manager queues an event whose block, when the new lock state is NO, calls `[delegate runningApplicationScenes:]`.
5. NI manager has no such method -> `-[SBNonInteractiveDisplaySceneManager runningApplicationScenes:]: unrecognized selector` on the workspace event queue (main). SpringBoard dies.

Evidence
* 16.0 delegate protocol marks it @required: `sb160n_objc.txt:10666-10676` (`- (id)runningApplicationScenes:(id)scenes;`).
* 16.0 block at 0x1c63e76a8: at 0x1c63e7888-0x1c63e7890 `ldrb w8,[x2,#0x19]; cbnz w8,0x1c63e7994` (skip when locking), otherwise 0x1c63e78a8 `bl msgSend:runningApplicationScenes:`.
* 16.2 NI implements it: `sb162_objc.txt` NI list, `-runningApplicationScenes:` 0x1c7703898 = `b externalApplicationSceneHandles` (and `externalApplicationSceneHandles` 0x1c7703654).
* `SBSceneManager` (16.0 super) has neither `runningApplicationScenes:` nor anything that would catch it (`awk` over `sb160n_objc.txt` SBSceneManager block).

Reachability (honest): needs an NI scene manager alive while an extended display's cover sheet toggles, e.g. two external displays or an NI display next to the system-shell one. On a single extended monitor the NI manager is probably never instantiated (the extended policy creates `SBSystemShellExternalDisplaySceneManager`). Confidence in the code defect 95%, in reachability ~25%.

Patch
```diff
--- a/Backport162/Group4Connect.m
+++ b/Backport162/Group4Connect.m
@@ static id   BP4_NI_VisibleScenes(id self, SEL _cmd, id mgr) {
+// 16.2 0x1c7703898: required delegate method, tail-calls externalApplicationSceneHandles
+static id   BP4_NI_RunningScenes(id self, SEL _cmd, id mgr) {
+    return [self respondsToSelector:@selector(externalApplicationSceneHandles)] ? [self externalApplicationSceneHandles] : nil;
+}
@@ BP4_Install
         BP4_AddMethod(ni, @selector(suspendedUnderLockManagerVisibleScenes:), (IMP)BP4_NI_VisibleScenes, "@@:@");
+        BP4_AddMethod(ni, @selector(runningApplicationScenes:), (IMP)BP4_NI_RunningScenes, "@@:@");
```
(`externalApplicationSceneHandles` is declared on NSObject(BPG4Private)? It is not; add `- (id)externalApplicationSceneHandles;` to the `SBNonInteractiveDisplaySceneManager` interface at Group4Connect.m:203.)

Other nilock checks (PASS): type encodings are right (`v@:B`, `B@:`, `v@:B@?@?`, `B@:@@`, `@@:@`; BOOL is `B` on arm64). `[super existingSceneHandleForScene:]` exists in 16.0 (`sb160n_objc.txt:92199`). `displayIdentity` exists (`:92119`); `FBSDisplayIdentity` has no `currentConfiguration` in 16.0 (grep of FrontBoardServices_160.txt), so `suspendedUnderLockManagerDisplayConfiguration:` returns nil (guarded, harmless but the NI "lock" then runs with a nil configuration). Selector-based NSNotificationCenter observers need no dealloc hook on iOS 16.

---------------------------------------------------------------------------------------------------

## F2  directhook: MSHookFunction on 0x1c6321b74  (CRASH-risk, UNVERIFIED)

File: Group4Focus.x:404-439, :713-718. Now ON by default (0.5.0 flipped it, comment at :715 still says "opt-in until it has been seen working on Dopamine/arm64e").

Verified facts
* The 7 prologue words match 16.0 bytes at 0x1c6321b74 exactly: `b4000440 d503237f d100c3ff a9014ff4 a9027bfd 910083fd aa0003f3` (`ipsw dsc dump`).
* Takes only `self` in x0. No `_cmd` is used; the first thing after the prologue is `mov x19,x0`.
* All callers use direct branches: 10 x `bl 0x1c6321b74` (0x1c6321eec, 0x1c6322168, 0x1c6322418, 0x1c632265c, 0x1c63227ac, 0x1c6322820, 0x1c63231fc, 0x1c63233e8, 0x1c6323590, 0x1c6324cc8) plus a `b` tail-call at 0x1c6328170 (11 sites, matching the source comment), and the ObjC method `updateKeyboardFocusDeferringRules` whose whole body is `b +4` at 0x1c6321b70. So a code patch at the entry catches every caller. The objc_direct claim holds. (`grep 0x1c6321b74 sb_text.s`.)
* Image lookup: `/SpringBoard.framework/SpringBoard` matches only the shared-cache framework image, not `SpringBoard.app/SpringBoard`. Slide use is right.

Risks (cannot be proven from the binaries)
1. The first instruction is `cbz x0, 0x1c6321bfc`, a PC-relative branch, and the second is `pacibsp`. Any inline hook that overwrites 12-16 bytes must relocate the `cbz` into its trampoline. Whether ElleKit (Dopamine's `mobilesubstrate` provider) relocates `cbz`/`cbnz` correctly was not verified. A wrong relocation makes `orig_reevaluate()` jump to garbage the first time the hook falls through, which is the first keyboard-focus evaluation after launch: respring loop.
2. arm64e: `orig_reevaluate` is a plain C function pointer; arm64e code calls it with `blraaz` (expects an IA/0-signed pointer). `MSHookFunction` hands back whatever the library produces. If the library does not sign the trampoline pointer, the call traps on authentication. Standard tweaks rely on the library signing it, so this is probably fine, but nothing here verifies it.
3. `pacibsp` inside the trampoline is fine (it runs with the caller's SP, `br` back to +N, the original `retab` then checks the same SP); the replacement itself is an ordinary arm64e function.

Suggested hardening (no relocation needed, PC-relative instruction left in place): patch at +4, after the `cbz`, so only position-independent instructions are copied. `cbz x0` still short-circuits nil self before the hook runs.
```diff
-    static const uintptr_t kVm = 0x1c6321b74;                 // 20A8372 vmaddr (unslid)
-    static const uint32_t kPrologue[7] = {
-        0xb4000440, 0xd503237f, 0xd100c3ff, 0xa9014ff4,
-        0xa9027bfd, 0x910083fd, 0xaa0003f3 };
+    static const uintptr_t kVm = 0x1c6321b78;                 // entry+4: skips the PC-relative cbz x0
+    static const uint32_t kPrologue[6] = {                    // pacibsp; sub sp; stp; stp; add fp; mov x19,x0
+        0xd503237f, 0xd100c3ff, 0xa9014ff4,
+        0xa9027bfd, 0x910083fd, 0xaa0003f3 };
```
and keep the feature opt-in until a log line shows it surviving one disconnect on the device (`kOptIn[F_DIRECTHOOK] = YES` in Tweak.x:47). Without the hook the suppression is "advisory" (documented at Group4Focus.x:399-402), which is what 16.0 does today, so turning it off loses little.

---------------------------------------------------------------------------------------------------

## F3  blank: wake gesture is never armed on 16.0  (WRONG-BEHAVIOUR)

File: Tweak.x:226 (`kMouseDownGestureType = 0x42`), :285 (`addGestureRecognizer:withType:`), :317-322 (`nowindow`).

The 0x42 mapping itself is right: `SBLockScreenManager init` (0x1c64e0494) does `mov w3,#0x42; addGestureRecognizer:withType:` at 0x1c64e0928, 16.2 uses `#0x43` (0x1c799d034 and the cover sheet at 0x1c778fef0). The mouse-button recognizer (`SBFMouseButtonDownGestureRecognizer`) is the same class in both builds.

What was missed: the external window scene's gesture manager is `SBExternalDisplaySystemGestureManager` (alloc'd by `SBExternalDisplayWindowSceneDelegate _configureForConnectingWindowScene:` at 0x1c5fed10c-0x1c5fed160, `sb160n_objc.txt:45265`). `addGestureRecognizer:withType:` (0x1c5e76a28) only stores the recognizer; it is wired into the system-gesture window only if `shouldEnableSystemGestureWithType:` is true (0x1c63196f0 -> `_shouldEnableSystemGestureWithType:`), and the external subclass decides that at 0x1c6365c28:

```
mov w0,#1; cmp x2,#0x39; b.hi L
...bitmask test for types 0x11,0x13,0x16,0x22,0x24,0x25,0x26,0x33,0x34,0x39 -> return 1...
L: sub x8,x2,#0x68; cmp x8,#2; csel w0,w0,wzr,cc      ; types 0x68/0x69 only
```
Type 0x42 > 0x39 and is not 0x68/0x69, so it returns NO. In 16.2 the same method (0x1c780bf58) has bit 50 of the mask set, i.e. type 0x43 returns YES (`mask 0x0004_020c_003b_e025`, type-0x11 = 0x32). So the 16.2 port of the cover sheet gesture needs this one extra predicate and it is absent from the tweak. Result: the gesture is created, registered, never attached to a window, `wake:` never fires. (Confidence 90%; single path I could not test: another code path enabling it. `_evaluateEnablement` 0x1c6318778 uses the same predicate.)

Consequence now that `nowindow` and `blank` are both default ON:
* While the iPad is off, the external display is only blanked by `BKSDisplayServicesSetDisplayBlanked` (exists in 16.0 BackBoardServices at 0x18e200948 with signature `(NSString*, BOOL)`; one-way MIG message id 0x5b916a to backboardd), and the 16.0 black window is suppressed. Nothing in 16.0 SpringBoard calls this function (it is not imported: `sb_syms.txt:52637-52643` lists only SetArrangement/WillUnblank/...). backboardd 16.0 does contain `_BKDisplayBlankingContext` and `_BKDisplayXXSetDisplayBlanked`, but I did not trace whether it resolves an external display's `hardwareIdentifier`. UNVERIFIED (60% it works). If it silently does nothing, the monitor keeps showing the last frame while the iPad sleeps (the old window fallback is gone).
* A click on the monitor cannot wake the iPad (F3), power button still can.

Patch (Tweak.x, new hook; the 16.0 method is the class's own, 0x1c6365c28):
```diff
+%hook SBExternalDisplaySystemGestureManager
+// 16.0 refuses type 0x42 (16.2 accepts 0x43), so the cover sheet's mouse-down gesture would never be armed.
+- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
+    if (type == 0x42 && BP_On(F_BLANK)) return YES;
+    return %orig;
+}
+%end
```
Also (F7) wrap the registration, and consider making `nowindow` opt-in again until blanking is seen to work:
```diff
-    ((void (*)(id, SEL, id, long long))objc_msgSend)(mgr, @selector(addGestureRecognizer:withType:), g, kMouseDownGestureType);
+    @try { ((void (*)(id, SEL, id, long long))objc_msgSend)(mgr, @selector(addGestureRecognizer:withType:), g, kMouseDownGestureType); }
+    @catch (NSException *e) { BP_Log(@"blank: gesture registration failed: %@", e); return me; }   // 16.0 NSAsserts on a duplicate type (0x1c5e76bd4)
```

Other blank checks
* `-[SBExternalDisplayCoverSheetController _setScreenOn:]` 0x1c62f367c: `if (_screenOn == on) return; _screenOn = on; [self _setBlankingWindowVisible:!on fadeDuration:0.5]`. The hook order (`was` read first, `%orig`, then act) is right and `_isScreenOn` (0x1c62f40d0) returns that ivar. PASS.
* The 16.0 init itself calls `[self _setScreenOn:[backlight screenIsOn]]` at 0x1c62f2c54, i.e. inside `%orig` of the init hook, so `BP_SetExternalBlanked(self, NO)` is issued once per connect (a harmless unblank request); `_sbWindowScene` is already stored (0x1c62f2bd8) so the `hardwareIdentifier` lookup works. At connect time the gesture does not exist yet; `g` is nil and `[nil setEnabled:]` is a no-op. MINOR note only.
* `_setBlankingWindowVisible:fadeDuration:` hook returns early for both YES and NO. If `nowindow` is switched on while a 16.0 blanking window is up, it stays until the controller dies. MINOR.
* 16.2 asserts when `hardwareIdentifier` is nil (0x1c7790c10); the port logs and skips. PASS.
* 16.2's `_setScreenOn:` compares the ivar at +0xa; the port goes through `_isScreenOn`, so offsets do not matter. PASS.
* `_initWithWindowScene:...` is an `init`-family selector (leading underscore ignored) and Logos treats it as a normal method (no `ns_consumed`/`ns_returns_retained`). Traced the refcounts: `retainAutoreleasedReturnValue` + `autoreleaseReturnValue` leave one extra +1 balanced by the autorelease, so net count is right (object lives until the pool drains). PASS.
* `static const char kWakeGestureKey = 0, kWakeHelperKey = 0, kWakeSceneKey = 0;` are three distinct addresses (internal non-`unnamed_addr` constants are not merged). PASS.
* Memory: helper retained by the gesture, scene held in a `__weak` box (loading a weak ref to a deallocating scene returns nil), dealloc hook runs before `%orig` (associated objects still valid), `removeGestureRecognizer:` (0x1c5e678f0) is a no-op if the recognizer is not in `_typeToGesture` and safe after `-[SBSystemGestureManager invalidate]` (0x1c63182b0 does not clear the dictionary). `%hook dealloc` under ARC: Logos emits a plain C function with `__unsafe_unretained self` (`_LOGOS_SELF_TYPE_NORMAL`), no retain of the dying object. PASS.

---------------------------------------------------------------------------------------------------

## F4  lockedptr: wrong thread, and the substitution is not neutral  (WRONG-BEHAVIOUR / thread safety)

File: Group4Focus.x:693-707.

* The 16.0 call site is `-[SBLockedPointerManager _queue_lockPointerForSceneIdentifier:]` (0x1c6228214). It starts with `dispatch_assert_queue(_stateSerialQueue)` (0x1c622823c) and calls `pointerSuppressionAssertionOnDisplay:forReason:withOptionsMask:` at 0x1c6228294, i.e. on a private serial queue, not main.
* The hook then calls `BP_WindowSceneManager()` (`[UIApplication sharedApplication] windowSceneManager]`), `embeddedDisplayWindowScene` (which enumerates `_mutableConnectedWindowScenes` via `bs_firstObjectPassingTest`, 0x1c6044274) and `_fbsDisplayConfiguration` (UIKit screen/scene accessors). The set is mutated on main in `_sceneWillConnect:` / `_sceneDidDisconnect:` (0x1c604417c / 0x1c60441f8). A pointer-lock request racing a display connect/disconnect enumerates a mutable set concurrently with a mutation: memory-unsafe, rare.
* Semantics: in 16.0 `BKSMousePointerService` treats a nil/empty display as the key `"<main>"` (0x18e205260-0x18e205268: `length == 0 -> "<main>"`), and sends that key as the display UUID (`_locked_sendCurrentAssertionParameters:forDisplayUUID:` 0x18e2054c0). Therefore nil already means the main/embedded display, which is the only display SBLockedPointerManager ever serves (it is wired to `SBMainDisplaySceneManager`, `sb160n_objc.txt:70593`). The hook replaces `<main>` with the embedded display's `hardwareIdentifier` ("Main"?), a different key (new per-display info entry, assertion id `mouse-pointer-suppression:<hw>`). Whether backboardd 16.0 treats that key the same as `<main>` was not traced (UNVERIFIED, 50%). If it does not, games that lock the pointer lose the lock/hiding on the iPad display. The change buys nothing in 16.0.

Patch: do not ship it.
```diff
-    static const BOOL kOptIn[F_COUNT] = { NO, NO, NO, NO, NO, NO, NO, NO, NO, NO };
+    static const BOOL kOptIn[F_COUNT] = { NO, NO, NO, NO, NO, YES/*activedisplay*/, YES/*gesturegate*/, YES/*lockedptr*/, NO, YES/*directhook*/ };
```
(or delete the `%hook BKSMousePointerService` block; if kept, resolve the identifier once on the main thread at `_configureForConnectingWindowScene:` and read the cached NSString here.)

---------------------------------------------------------------------------------------------------

## F5  activedisplay: default ON changes behaviour  (WRONG-BEHAVIOUR)

File: Group4Focus.x:282-327 (sniffers), :541-552, :575-581.

* 16.2 default is methodology 1 (touch + pointer): `-[SBExternalDisplaySettings setDefaultValues]` 0x1c74235f4 ends with `setActiveDisplayTrackingMethodology:1` (0x1c742368c). So enabling it is faithful on paper.
* In the port, pointer tracking is almost certainly dead: sniffer 3 requires `[touch type] == 0` for a pointer touch (decoded literally from 16.2 0x1c795ef94: `cbz x0` on `type`; for real mouse/trackpad touches `type` is UITouchTypeIndirectPointer == 3, which sniffer 2 explicitly skips, `ty == 3`), and it only fires on movement. Sniffer 2 skips pointer touches. Net: the active display moves only on finger/pencil touches.
* Failure: user touches the iPad (active = embedded), then uses keyboard + mouse on the monitor. 16.0 baseline: kfc.windowSceneWithFocus (monitor) -> `activeDisplayWindowScene` = monitor (0x1c6043bec: `kfc.windowSceneWithFocus ?: _embeddedDisplayWindowScene`). With the hook: `fromUser` = embedded stays set -> everything that asks `activeDisplayWindowScene` (about 90 callers: banners, Spotlight, Control Center, the switcher) now targets the iPad until the next finger touch on the monitor (not possible for a normal monitor).
* Nil/disconnected scene: the override returns a connected scene or what 16.0 would (nil only if there is no embedded scene). A disconnected external scene is filtered through the `invalidating`/`invalidated` flags (set in the `sceneDidDisconnect:` wrapper, :626 and :657), and `_activeDisplayWS` is a `__weak` ivar cleared on dealloc. If `disconnect` is switched off, the coordinator is not told about the disconnect (:628 is after the `BP_On` early return at :613), so a dead-but-alive scene could be returned; `.off.disconnect` and `activedisplay` together are an unsupported combination. MINOR.
* Hot path: `-[SpringBoard sendEvent:]` (:575). `SpringBoard : UISystemShellApplication` has no own `sendEvent:` (`sb160n_objc.txt:120873-122322`), so Logos adds an override whose `%orig` is the inherited implementation (the Logos output calls the saved pointer directly, so it depends on the hooking library supplying the super IMP for an inherited method, which Substrate/ElleKit do). Exceptions are contained by the `@try`. `-[UITouch _isPointerTouch]`, `-[UIEvent _hidEvent]`, `+[UIWindow _windowWithContextId:]`, `BKSHIDEventGetBaseAttributes` (0x18e1dde04) all exist in 16.0. Per-event cost: a couple of dictionary lookups, an array copy, window lookup; acceptable.

Recommendation: ship `activedisplay` (and with it `gesturegate`) opt-in until pointer-driven switching is observed on the device, or make sniffer 3 accept `type == 3`. Both are in the log as "updating active display from ... source: pointer", so one debug session decides it.

---------------------------------------------------------------------------------------------------

## F6  gesturegate: stale pointer touch-down scene

File: Group4Focus.x:293-301, :335-339, :442-447.

`_pointerTouchDownInScene:` sets `_touchDownWS`; only phase 3 (Ended) clears it. A cancelled pointer touch (phase 4: drag interrupted, window removed, hand-off to a gesture) leaves it set. `BP_PanFromOtherDisplay` then returns YES for every UIPanGestureRecognizer whose own scene differs, so `SBControlCenterController` / `SBFluidSwitcherGestureManager gestureRecognizerShouldBegin:` return NO for finger gestures on the iPad until the next pointer touch-up. Window-scene disconnect clears it only for the disconnected scene.
```diff
-                else if (ph == 3) [self _pointerTouchUp];
+                else if (ph == 3 || ph == 4) [self _pointerTouchUp];   // cancelled counts as up
```

---------------------------------------------------------------------------------------------------

## Checklist

### 1. Signatures and type encodings  -- PASS

| hook | 16.0 | verdict |
|---|---|---|
| `SBSystemShellExtendedDisplayControllerPolicy _preferredSizeInPixelsForTargetCADisplay:` | `(CGSize)(id)`, 0x1c633a7a8 | PASS: struct returned in d0/d1, Logos function pointer typed CGSize |
| `SBSystemShellExternalDisplaySceneManager _shouldAutoHostScene:` | `BOOL(id)`, 0x1c63ae320 | PASS |
| `SBExternalDisplayCoverSheetController _initWithWindowScene:lockStateProvider:backlightController:windowFactory:externalDisplayCoverSheetViewController:` | 5 x id, 0x1c62f2b4c | PASS |
| `_setScreenOn:` (BOOL) / `_setBlankingWindowVisible:fadeDuration:` (BOOL,double) | 0x1c62f367c / 0x1c62f369c | PASS (`double` in d0, `BOOL` in w2) |
| `_setCoverSheetWindowVisible:fadeDuration:` | (BOOL,double) 0x1c62f3a54 | PASS |
| SBSceneHostingDisplayController `displayIdentityDidDisconnect:` / `_enqueueEvaluateAndApplyPresentationUpdate` / `_runRootUpdateTransactionWithLabel:completion:` | 0x1c5f47a64 / 0x1c5f4927c / 0x1c5f4a79c | PASS (arg counts and types) |
| SBSceneHostingDisplayControllerProvider `displayManager:didDisconnectIdentity:` | 0x1c5ed1f90 | PASS |
| SBNonInteractiveDisplaySceneManager `initWithReference:sceneIdentityProvider:presentationBinder:` | inherited from SBSceneManager 0x1c5f7230c | PASS (installed via class_addMethod, orig = inherited IMP) |
| kfc `windowSceneDidDisconnect:` | `void(id)`, body is a single `ret` at 0x1c6323a98 | PASS; MSHookMessageEx swaps the method IMP, no inline patch, so a 4-byte function is fine |
| `SBWindowSceneManager activeDisplayWindowScene`, `SpringBoard sendEvent:`, `_configureForConnectingWindowScene:windowSceneContext:` (Embedded and External), `sceneDidDisconnect:` | all exist as in the dump | PASS |
| `SBControlCenterController` / `SBFluidSwitcherGestureManager gestureRecognizerShouldBegin:` | both own methods, BOOL(id) | PASS |
| `BKSMousePointerService pointerSuppressionAssertionOnDisplay:forReason:withOptionsMask:` | (id,id,ULL) 0x18e2051e0 | PASS (but see F4) |
| `%new` encodings (Logos) / `BP4_AddMethod` strings | `@encode(BOOL)` = `B` on arm64; `v@:B`, `B@:@@`, `v@:B@?@?`, `@@:@` | PASS |

No hooked class is missing in 20A8372, and none lives in a framework that is not loaded (`BKSMousePointerService` in BackBoardServices, `SBFMouseButtonDownGestureRecognizer` looked up at runtime via NSClassFromString). `MSHookMessageEx(NULL, ...)` is therefore never reached on this build.

### 2. Threading and locking  -- findings F4 only

* Hooked methods and where they run: `_preferredSizeInPixels…` (FBSDisplayTransformer path; same thread as the original, only extra CADisplay getters), `_shouldAutoHostScene:` (scene manager), the cover-sheet methods and `sceneDidDisconnect:` (main), `displayIdentityDidDisconnect:` (main, asserts `isMainThread` at 0x1c5f47aa0), `displayManager:didDisconnectIdentity:` (same SBDisplayManager callback `displayMonitor:willDisconnectIdentity:` 0x1c64d52e4/0x1c64d54e0, controller first, then observers).
* `removeKeyboardFocusFromScene:` (0x1c6322ec4) does `dispatch_assert_queue(main)` and asserts non-nil `FBScene` (`_bs_assert_object`, `isKindOfClass:FBScene`). The kfc hook only calls it on main (else `dispatch_async(main)`) and only with `FBScene`-filtered, non-nil arguments. `externalForegroundApplicationSceneHandles` returns an NSSet (`[… immutableSet]`, 0x1c5e1f9a0), so fast enumeration is valid; handles respond to `scene` (the kfc itself uses it at 0x1c6323ed4). PASS.
* provmap lock: `_lock` is an `os_unfair_lock_s` at +0x30 (`sb160n_objc.txt:91637`), the same lock the original uses (0x1c5ed1fb4). The 16.0 original only removes from `_lock_capableRootDisplaysToResolverMap` (+0x38, 0x1c5ed1fc8-0x1c5ed1fec); 16.2 additionally removes from `_lock_rootDisplaysToControllerMap` (+0x48, 0x1c7346040-0x1c7346064) under the same hold. The port takes the lock in a second critical section after the original has unlocked (0x1c5ed1ff4), so the lock is never already held (the original does `assert_not_owner` and releases before returning) and the hook cannot self-deadlock. The 16.0 connect path would trip its "one controller per physical display" NSAssert on the stale entry (0x1c5ed2044…0x1c5ed220c), which is exactly what provmap prevents. The only gap versus 16.2 is the window between the two critical sections; harmless as both callbacks arrive on the display-manager callback context. Keys are the identity passed in (16.2 does the same). PASS.
* BSCompoundAssertion: handler is invoked after `_dataLock` is released and under `_syncLock` (0x18e26f530 unlock data, 0x18e26f548 `blraa` handler, 0x18e26f570 unlock sync); `isActive` takes only `_dataLock` (0x18e273088). The handler's `[a isActive]` is safe. No lock-order cycle between BSCompoundAssertion, the provider lock and anything the tweak holds. PASS.

### 3. Memory / ARC  -- PASS (details in F3 and below)

* `BPMultiDisplayCoordinator`: ivars are `__weak`/weak hash tables, associated RETAIN to the manager, `delegate` weak. The NONATOMIC policies are only read where the values are never removed (`@YES`, coordinator, suppression assertion), so the lack of retain-on-read cannot race.
* kfc suppression handler captures `weakSelf` only; the `go` block re-loads it. The assertion is stored on the kfc, and the handler lives inside the assertion: no cycle.
* `BP_WindowSceneOf` etc. return +0 objects held by locals. `hook_reevaluate` takes `self` unretained (plain C function).
* Logos `%hook dealloc` with `%orig` under `-fobjc-arc` is fine, see F3.

### 4. Missing private pieces, and `.off` pass-through  -- PASS

Every private call is behind `respondsToSelector:`, a class lookup or a nil check; the exceptions are direct sends to selectors verified to exist in 16.0 (`systemGestureManager`, `_sbWindowScene`, `_sbDisplayConfiguration`, `hardwareIdentifier`, `_isScreenOn`, `[UITouch _isPointerTouch]`, `[UIEvent allTouches]`, `-[SBSceneManager removeObserver:]` guarded). With a feature's `.off` file: scale and autohost call `%orig` first and return its value untouched; `_initWithWindowScene` does `%orig` first; `_setScreenOn:` reads the old state, calls `%orig`, then only the "unblank if we blanked" branch remains; `sceneDidDisconnect:` is `%orig` + return; `activeDisplayWindowScene` returns `%orig` if both `disconnect` and `activedisplay` are off; `sendEvent:` skips the coordinator and calls `%orig`; BP4 hooks all call the original (discguard checks the flag only when ON). The two documented exceptions are `nowindow` (intended) and install-time gating of `nilock` (needs a respring, documented). `nilock` is installed once at launch; the rest are runtime-checked.

### 5. Translation claims

(a) blank: see F3. Confirmed: `_setScreenOn:` and `_setBlankingWindowVisible:fadeDuration:` semantics, the 0x42 value (but not its gating), `BKSDisplayServicesSetDisplayBlanked` exists and takes `(NSString*,BOOL)` (0x18e200948), nobody else in 16.0 SpringBoard calls it. Unknown/duplicate gesture type: unknown types are stored but not wired (`shouldEnable…` NO), duplicates hit an NSAssert (0x1c5e76bd4, string "Trying to add a system gesture with type %@, but we already have one: %@").

(b) scale: `_preferredSizeInPixelsForTargetCADisplay:` = `logicalScaleForDisplayScale:` (uniform) x preferred-mode width/height (0x1c633a7a8). Its only consumers are `displayController:transformDisplayConfiguration:withBuilder:` (0x1c6339894) and `_preferredSizeInPointsForTargetCADisplay:` (pixel/`_preferredContentsScale`, 0x1c633a8d4), both go through the hooked method, so pixel and point sizes stay consistent. The hook only changes the result when the 16.0 logical scale falls outside the monitor's `[minimumLogicalScale, maximumLogicalScale]`; every non-finite/zero/missing input returns the original. `CADisplay displayType`, `minimumLogicalScale`, `maximumLogicalScale`, `CADisplayMode width/height` exist in 16.0 QuartzCore (`QuartzCore_160.txt:1350-1370`). A monitor whose range excludes the current scale will change size, which is the 16.2 behaviour; a monitor reporting a range that excludes everything useful (e.g. min == max == 1.0) would be forced to native pixels. PASS with that caveat. autohost: `usesInputSystemUI` = `inputUIOOP && !isKeyboardProcess` (0x18998d66c), `_UIKeyboardArbiter_SceneIdentifier` is imported from KeyboardArbiter (`sb_syms.txt:55390`), a missing symbol returns the original. PASS.

(c) disconnect: the original (0x1c5fed4f8) is: `[super sceneDidDisconnect:]` first; `[switcherCoordinator windowSceneDidDisconnect:]` only if `[[ws screen] displayConfiguration]` is non-nil; invalidate `_showStatusBarAssertion` (+0x68); `[ws.systemGestureManager invalidate]`; three more `windowSceneDidDisconnect:` broadcasts. It does not touch `_coverSheetController` (+0x60) or any NSNotificationCenter registration, so the wrapper's cover-sheet cleanup cannot double-release or remove something the original already removed. The cover sheet controller is additionally retained by the window scene context (`setUILockStateProvider:` at 0x1c5fed280), so nil-ing the delegate ivar via KVC does not deallocate it; `removeObserver:` only removes its two NC registrations; the SBBacklightController registration remains until dealloc (harmless: `_sbWindowScene` is weak and `BP_SetExternalBlanked` bails out when `hardwareIdentifier` is nil). KVC finds the ivar `_coverSheetController` (no getter/setter exists) and is inside `@try`. The kfc `windowSceneDidDisconnect:` hook is itself called from the original's `[super sceneDidDisconnect:]` (5 call sites in `-[SBAbstractWindowSceneDelegate sceneDidDisconnect:]`, 0x1c600cb4c…0x1c600cc30), i.e. inside `%orig` and therefore while the suppression assertion is held, as intended. `discswitch` (now ON): calling `SBMainSwitcherControllerCoordinator windowSceneDidDisconnect:` (0x1c62359ec) after the original with a scene whose display is gone is safe: it looks the controller up by scene (`bs_firstObjectPassingTest`), the dictionaries it mutates are NSMapTables (nil key tolerated) and every other message goes to the possibly-nil controller. PASS.

(d) see F2.

(e) see F5 and F6. `UIApplication` behaviour is unchanged by the `sendEvent:` override (it forwards to the inherited implementation).

(f) nilock: F1. discguard: setting the flag before `%orig` is safe because the 16.0 disconnect transaction does not use the guarded functions (`_runRootTransaction:withLabel:completion:` -> `displayControllerDidDisconnect:sceneManager:`, 0x1c5f47c94…0x1c5f47cd8); only later fire-and-forget callers (`requestUpdate:` 0x1c5f470ac/0x1c5f470c0, displayAssertion callbacks 0x1c5f47fac/0x1c5f480a8/0x1c5f4816c) are suppressed, as in 16.2. A controller is created per connect (0x1c5ed20f8), so the permanent flag never leaks into a reconnect once provmap removes the stale map entry. covernote: posts from `_setCoverSheetWindowVisible:fadeDuration:` on main; nothing else listens in 16.0 except nilock. PASS (apart from F1).

(g) Tables: `kFeatureNames` has 10 entries and matches the 10-entry enum in BP.h in order (scale, autohost, blank, disconnect, discswitch, activedisplay, gesturegate, lockedptr, nowindow, directhook); all F_* uses are in range; `gFeatureOffPath[F_COUNT][1100]` fits `"%s/Backport162.off.%s"` for jbroot paths. Group4Connect.m keeps its own table (6 names) and its own switch cache, indices stay in range (`BP4_On` bounds-checks). Two translation units define their own `static` helpers with different names (`BP_*` vs `BP4_*`), no clashes. The `@interface X : NSObject` declarations of private classes in Tweak.x and Group4Focus.x have no `@implementation` and are only used as message targets/types, so they emit no class metadata and no `OBJC_CLASS_$_` references (Logos uses `objc_getClass`). The local `@implementation`s (`BPWeakBox`, `BPWakeTarget`, `BPMultiDisplayCoordinator`) have unique names.

### 6. Build

`Backport162_FILES = Tweak.x Group4Connect.m Group4Focus.x` lists everything. Theos adds `-Wall -Werror` unless `GO_EASY_ON_ME=1` (`theos_src/makefiles/common.mk:230-232`), regardless of FINALPACKAGE; FINALPACKAGE only changes `-O2`, so extra optimisation-dependent warnings are possible but the 0.4.x line built with the same flags. The 0.5.0 delta only flips table values and one call, `BP_G4_OptIn` becomes unused (covered by `-Wno-unused-function` pragma at Group4Focus.x:29), `kBP4Experimental` stays referenced. `ARCHS = arm64 arm64e`, rootless scheme, `Depends: mobilesubstrate` is satisfied by ElleKit. Not compiled here (no toolchain); risk of a new -Werror in 0.5.0 is low. I could not run the build.

### 7. Launch and connect/disconnect/sleep/wake paths

* `%ctor`: `BP_InitPaths` is inside an `@autoreleasepool` (the `fileSystemRepresentation` buffer is autoreleased bytes, not tied to `tmp`); build guard (`kern.osversion == "20A8372"`) runs before any hook; `%init` then `BP4_InstallIfSupported` then `BP_G4_Setup` (`%init(G4)` and the optional MSHookFunction). Everything installed is a method swap or, for F2, one inline patch.
* dyld image iteration (Group4Focus.x:426-429) is a plain loop over `_dyld_get_image_name`; a missing image just returns NO.
* connect: `_initWithWindowScene` hook (F3), `_configureForConnectingWindowScene` hooks (coordinator hand-off, main thread), provider/guard hooks.
* disconnect: wrapper order is suppress -> invalidating flag -> coordinator hand-off -> `%orig` (kfc hook runs inside) -> optional switcher hand-off -> cover sheet cleanup -> `[assertion invalidate]` (kfc re-evaluates once) -> invalidated flags. No path returns between acquire and invalidate. If the original were to raise, the assertion would leak and keyboard focus would stay frozen; the original does not raise on these paths.
* sleep/wake: `_setScreenOn:` on main; each transition does one one-way mach message to backboardd; wake gesture toggling is `setEnabled:` on main (F3).

---------------------------------------------------------------------------------------------------

## F8  Minor items

* `BP_FileFlag` / `BP4_FileFlag` mutate unlocked statics (`next`, `last`) from any thread: word-sized benign races, technically data races.
* Group4Focus.x:501: post-suppression refocus is skipped if `disconnect` is switched off between acquire and release; then the focus is never re-evaluated until the next event.
* Group4Focus.x:545: the `activeDisplayWindowSceneFollowingUserInteraction` helper calls `BP_Coordinator(YES)` which returns nil off-main; fine because nothing calls it in 16.0.
* Tweak.x:306: `gWeBlanked` is global across displays; with two external displays one unblank request clears it for both.
* Tweak.x:272-289 / dealloc: `kWakeGestureKey` association created before `addGestureRecognizer:` succeeds; harmless (remove is a no-op for an unregistered recognizer).
* 16.0 backboardd keeps the blanked state if SpringBoard dies while the monitor is blanked; the next controller init calls `_setScreenOn:` with the current backlight state and unblanks if the screen is on. If the iPad stays off the monitor stays blank until wake. Not a crash.
