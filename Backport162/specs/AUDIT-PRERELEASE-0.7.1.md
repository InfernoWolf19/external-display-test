# Pre-release static audit 0.7.1 (selector / receiver / return-shape / ARC / hang audit)

Tools (kept outside the repo, in the session scratchpad `aud2/`): `extract.py` (bracket sends + selector literals of all 14 sources), `sels.py`/`mentions.py` (every selector mentioned vs the
16.0 class dumps: SpringBoard, UIKitCore, FrontBoard, BaseBoard, BackBoardServices, FrontBoardServices, SpringBoardServices, SpringBoardFoundation, SpringBoardUI, SpringBoardHome,
SpringBoardUIServices, Pegasus, BoardServices, ... 9.8k classes), `idhelp.py` (id-returning helper calls vs the real return type), `casts.py` (objc_msgSend casts vs the real signature: return kind, arity,
argument kinds), `stubs3.py` (every private @interface declaration of ours vs the dump), `selfcheck.py` (every send to `self` inside a %hook vs the hooked class chain incl. the SBSwitcherModifier
protocol trampolines), `hooks2.py` (every %hook target exists), `rettypes.py`, `ivars.py` (every raw ivar read/write size vs the dump).

## Findings (file:line at the time of the fix, class, severity, fix)

| # | where | class | sev | finding | fix |
|---|---|---|---|---|---|
| 1 | G1D.x `G1D_ShouldProtectEdge` | (a)/(2) id helper on a scalar | CRASH (device, SIGSEGV objc_retain x0=0x7fff..., strip tap) | `G1B_Send0(_homeGrabberSettings, edgeProtectOverride)`: `-[SBFHomeGrabberSettings edgeProtectOverride]` returns a BSSettingFlag (long long). ARC retained the scalar. 16.2 0x1c78f9a8c passes x0 straight to BSSettingFlagIsYes / IsExplicitNo | read with `G1B_SendLL0`, the two C functions are called with `long long` |
| 2 | BP.h + 40 call sites (G1B/G1C/G1D/G2/G3B/G4B/Group4Focus) | (4) object_getIvar on a possible scalar ivar | HIGH latent | `G1D_IvarObj`, `G1B_WD_Ivar`, `object_getIvar(self, iv)` (G1B x7, G1D, G2, G3B, G4B, Group4Focus) did not check the ivar encoding: a non-object ivar returns raw bits that ARC retains | new `BP_ObjIvar` / `BP_SetObjIvar` (BP.h) check `@` / `#` encoding; every raw `object_getIvar` / `object_setIvar` outside the already checking helpers uses them |
| 3 | G1C.x `G1C_Wdr_Transition` (~2872) | (b) wrong receiver | MED (feature silently off) | `displayOrdinal` is a modifier CONTEXT query; it was sent to the transition EVENT (never responds, so the home layout never got the display ordinal). 16.2 0x1c74614dc: x0 = self | sent to `self` |
| 4 | G1C.x `G1C_GridRoot_NewMulti` (IMP of `_newMultitaskingModifier`) | (2) ARC family | HIGH | `new`-family selector (leading underscore ignored by ARC) implemented as a C IMP returning +0: the stock ARC callers own the result (+1) and over-release the copy: use-after-free of modifier copies | `__attribute__((ns_returns_retained))` |
| 5 | G3B.x `-newMedusaHostedKeyboardWindowLevelAssertion...` (hook) | (2) ARC family | HIGH | Logos hook is a C function: `return [c new...]` returned a +1 object at +0 | extra `CFRetain` hands the +1 to the stock caller |
| 6 | G3B.x:835, G4B.x:767 | (2) ARC family | LOW (leak) | `new...` sends through plain `id (*)` casts: ARC retained an already +1 result | `ns_returns_retained` function-pointer casts |
| 7 | G3B.x:207, G4B.x:816 | (2) return shape | LOW | `postPresentable:withOptions:userInfo:error:` returns BOOL, cast as `id` | cast as `BOOL` |
| 8 | G2B.m:1581, G2B.m:1745 | (2)/(1) | LOW | void selector through an `id` cast; `initWithGestureID:` object argument passed as `long long` read through `BP2B_LL` | exact casts |
| 9 | G1D.x `_rebuildCurrentWindowingModeCompatibleAppLayouts...` | (4) NSNotFound index | HIGH latent | `[medusaList insertObject:s atIndex:idx + i]` with `idx == NSNotFound` raises NSRangeException | skip when not found, clamp |
| 10 | G1D.x `G1D_IvarULL` | (4) over-wide read | LOW | 8-byte read of 4-byte `int` ivars (`_targetProcessIdentifier`) | size from the ivar encoding |
| 11 | G4B.x LockedPtr (`G4B_LPMInv`, `invalidate`, `clientWithSceneIdentifier:suppress...`) | (5) dispatch_sync on own serial queue | HIGH (watchdog) | `dispatch_sync(_stateSerialQueue)` from a block already running on that queue deadlocks the main thread forever | `G4B_SyncOnQueue`: queue-specific marker, inline when already on the queue |
| 12 | G4B.x `%hook didSelectContainer:modifierFlags:` | (7) hook of a method 16.0 lacks | MED | the method exists only when G2B adds it; this Logos build calls `_logos_orig` unguarded (NULL when G2B did not add it) | run-time wrapper `G4B_WrapDidSelectContainer` (only when the method exists) |
| 13 | BPCrash.m | (5) crash recorder | MED | handler used snprintf (locks / allocation), dladdr under dyld lock can hang; no re-entrancy guard: a hang inside the handler = 180 s watchdog | async-signal-safe number writers, re-entrancy guard, `alarm(3)` + default SIGALRM so a hang becomes a crash, handler reset before return |
| 14 | G1D.x `%hook SBFloatingDockController -_isActiveAssertionInOrAboveApp` (group `G1D_DockFocus`, switch `g1d_dockfocus`) | (d) 16.0 predicate vs 16.2 | HIGH (device: hardware keyboard dead while the floating dock is shown) | see analysis A | 16.2 predicate: level >= 0xb under Stage Manager (16.0: level > 4) |
| 15 | G1C.x three callers of `_newMultitaskingModifier` (`G1C_NewMultiOf`) | (2) ARC family, caller side | LOW (leak, appears once #4 returns +1) | the callers read the +1 result through an `id (*)` helper: ARC retains again | `ns_returns_retained` cast helper, ARC consumes the owned reference |

## Analysis of the device findings

### A. Hardware keyboard cannot type while the floating dock is visible (logs 24e400bd / f8d059f3)
`-[SBFloatingDockController _updateFocusAssertion]` (both OS versions) takes a keyboard-focus lock with the reason "FloatingDock" whenever its predicate is YES. The predicate is
`_isActiveAssertionInOrAboveApp` in 16.0 and `_isActiveAssertionInDesiredLevel` in 16.2. 16.0 compares the dock assertion level with 4 (`level > 4`, a number that means "above the app" in
the old level scale); 16.2 compares with 0xb under Stage Manager (`isChamoisWindowingUIEnabled` of the switcher controller) and only falls back to the old compare plus
`unlockedEnvironmentMode == 3` without it. With Stage Manager enabled through our port the 16.0 compare was true for every level the Stage Manager dock uses (5..10) and locked focus to the dock,
so key events went to the dock scene. Fix: hook the 16.0 predicate with the 16.2 one (ivars `_windowScene`, `_activeAssertion`, read with the encoding-checked helpers). The G4B `focuslock` wrapper
(an invented "want" filter, see residuals) is unchanged; the real 16.2 policy lives in two objc_direct methods (~750 / ~1070 instructions) that are not ported.

### B. Crashes #2/#3: retain of a freed object in `-[SBChainableModifier enumerateChildModifiersWithBlock:]`, reached through `G1C_FS_Fwd1` (dylib+0x498e0)
`G1C_FS_Fwd1` is only the pass-through of the FS floor's `handleEvent:` to its superclass; the faulting `objc_retain` is the `[x nextQueryModifier]` step of the child walk. In 16.0 the children of
a modifier are found by walking the flattened, STRONG `_nextQueryModifier` chain of the whole tree (children = entries whose `parentModifier` is the receiver), so a modifier that was released
once too often while still linked is retained from freed memory by every walk that crosses it (the walk of the FS floor crosses everything after it).
Root cause (static, highest confidence): finding #4. `_newMultitaskingModifier` is a NEW-family selector; our IMP returned `[m copy]` as a plain C function, i.e. autoreleased. The stock callers
(`SBHomeGestureSwitcherModifier initWithGestureID:...multitaskingModifier:`, `SBHomeGestureToSwitcherSwitcherModifier`, the grid root's ToHome child) own the result, hand it to the chain
(`addChildModifier:`), release their own reference, and the autorelease pool then released the chain's reference: a Stage Manager multitasking modifier freed while linked into the chain.
The first walk after the pool drain crashes in the walk. This explains why the crash is intermittent and only after gesture / transition activity. Fixed by `ns_returns_retained` (#4) and
the caller side (#15).
Other candidates examined and ruled out: pulse (G1B `addChildModifier:...` 1725 / `removeChildModifier:` 1748: remove after the child finished, retained by the local `mod`); slide
(`G1C_Sl_*`, temporary child under `performTransactionWithTemporaryChildModifier:`: removed by the base class); `G1C_GR_Guard` (removes the stale gesture child from `handleGestureEvent:` before the
forward walk, not during it); `handleUpdateWindowingModeEvent:` (removes `child` then adds the new root: both outside any walk); S2AE `willUpdate` (removal of its own child, outside a walk).
Not resolvable statically: whether a second, independent over-release exists in a path that only runs on device (every other `new`/`copy`/`init` IMP and hook was checked against ARC families, see
the ARC rows above and AUDIT-MEMORY-0.6.2). To be device-tested: repeat the tap / drag / 3-window sequences of crashes #2/#3 on a build with #4 + #15.

### C. Strip hidden with three windows; reveal; strip flakiness
* Threshold: `G1C_FS_Exceeds` was compared with the 16.2 code, same constants and window counting (leaf layouts of the full-screen layout vs the strip's
  `maximumNumberOfRows` x per-group count). The hide behaviour is 16.2's: with three windows the strip is auto-hidden by `prefersStripHidden` rules, not by a port bug. Nothing was changed.
* Reveal: finger path (edge pan + `_handleContinuousExposeStripRevealGesture:` -> `_handleFluidGesture:` type 0xb) matches 16.2 0x1c78f27e8; `G1C_FS_RevealedFromHidden` /
  `G1C_FS_WantsHideHover` / `G1C_FS_StripEdge` match 16.2. The peeking left-edge card is not leftover reveal progress: it is the hidden strip's resting origin (`G1C_Strip_OriginX`
  uses the reveal progress only through `G1C_FS_Reveal`, which is 0 after dismissal; `G1C_FS_RevealedFromHidden` returns NO at 0). Not reproducible statically.
* Pointer / trackpad: the pointer recognizer (`G1D_MakeStripIndirectPan`: edges = strip edge, hysteresis 30/10, `setShouldRequireGestureToStartAtEdge:YES`, translation adjust block 0x1c78faca0,
  system gesture type 0x34 via `indirectPanSystemGestureTypeForGrabberTongue:`), the hover recognizer (0x33) and `wantsContinuousExposeHoverGesture` (FS, Strip, Hs, Rt) were
  compared with 16.2 and match. Nondeterministic / device-only candidates for "pointer does not reveal while the finger does": (1) `G1D_ShouldBeginStripReveal` / `grabberTongueOrPullEnabled:` evaluates the
  first-swipe tongue rule (`G1D_StripFirstSwipe`: a window touching the strip edge whose app defers the edge gesture) and shows the tongue instead of revealing: by design in 16.2 as well, the second swipe
  reveals; (2) the 16.0 `SBMainDisplaySystemGestureManager` has to accept type 0x34 on the display the pointer is on (external display scene: its own manager); (3) `shouldRequireGestureToStartAtEdge`
  needs the pointer to start at the edge pixel; (4) the tongue's `grabberTongueBegan/Updated/Ended/CanceledPulling` hooks forward `edgePullGestureRecognizer` (touch) rather than the `andGesture:` argument, which would feed
  the wrong recognizer if the tongue ever reports an indirect pull through them (not the case with the recognizer created here: its own action is `_handleContinuousExposeStripRevealGesture:`).
* Flaky tap / drag-out: the first cause is #1 (crash on the very tap of a strip card through `edgeProtectOverride`, which also dropped the tap), fixed. Remaining nondeterministic candidates: receiveTouch second pass logging
  "no window" for strip-region taps (the touch landed outside every container frame while the strip was animating: 16.2 identical), highlight/tap responses gated by `isHandled` (16.2 identical).

### D. Animation update mode (task part 3)
All constructions of `SBUpdateLayoutSwitcherEventResponse` / `setUpdateMode:` / `setLayoutUpdateMode:` use an explicit mode (2, 3, 5), except `G1C_Strip_HandleEvent` (2,0) and `G1C_Strip_HandleHighlight` (0xc,0), which
are 16.2's own compiled constants (mode 0 = Unspecified). They are consumed safely: `G1D_VCUpdateMode` replaces 16.0's `_performWithFixedUpdateMode:` (always wraps with mode 0 and asserts
"needs a explicit update mode") by 16.2's (only wraps when the response's mode is not 0).

## Counts by category
(a) wrong class / 16.2-only selector on 16.0: 2 (#1, #3) + 1 hook of a missing method (#12).  (b) wrong receiver: 2 (#3, #1).  (c) missing explicit update mode: 0 (D).  (d) invented / guessed value: 2 (#14, edgeProtectOverride).
ARC / return shape: 6 (#4, #5, #6, #7, #8, #15).  nil / ivar / bounds: 3 (#2, #9, #10).  hang / deadlock: 2 (#11, #13).  Crash root causes: 3 (#1, #4 = crash B, #14 for the keyboard).

## Residuals (not resolvable statically)
* Pointer reveal failure and strip flakiness: candidate lists in C; need device logs with `BP_LogEnabled`.
* G4B `focuslock` wrapper remains the invented "want" filter; 16.2's real policy (two objc_direct methods) is not ported. With #14 the dock no longer takes the lock; typing in other cases to be checked.
* Crash B: #4 is the statically proven over-release; confirm on device.
* Linux stub headers cannot compile most files; verified by logos.pl (all 10 .x files pass) + clang syntax checks of G1C.x / G1D.x (stub warnings only).
