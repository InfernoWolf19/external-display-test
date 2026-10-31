# REVIEW display side (0.7.9, branch claude/backport162, head fa3b283)

Static differential review of the display-side hooks written after REVIEW-PLUMBING-0.7.9.md / REVIEW-SENDLOGS-0.7.9.md (those rows are not repeated). Sources: 16.0 (20A8372) and 16.2 (20C65) dyld caches, the device logs of the user (u6, u10, u11), the git history. Nothing ran on a device. Verdicts: VERIFIED (equal to 16.2 / safe by reading), FIXED (sha), DEVIATION (documented and justified), DEFECT-OPEN (why).

Scope read completely: Tweak.x, Group4Focus.x, G4B.x, X2Overlay.x, X3Mode.x, X5Recording.x, X6InCall.x, X7Keyboard.x, X9Pin.x, G2D.x, G2G.x, Z1Diag.x, BBD.x, PTR.x, BPDaemon.h, BPCrash.m, and the changed parts of G3B.x (kbhosthere, kbmedusa, l10n), G3.x (l10n), Group4Connect.m (discguard). Not re-read (unchanged since REVIEW-PLUMBING, or reviewed there): SMT.x, SPK.c (only 30ed585 read), RPT.x / Backport162Prefs (secret handling re-checked, see section 3), the rest of G3B.x / G3.x / EDE.x.

## 1. Defects found

| id | where | defect | impact | status |
|---|---|---|---|---|
| D1 | Group4Focus.x `_pointerMovedInScene:` (p5_holdflip, e105de9) | the guard compared `[touch locationInView:[touch view]]` (the space of the touch's own view) with the bounds of the WINDOW. A touch view that sits at an offset in its window (or any non-full-window view) gives a shifted location: a pointer inside its window near the top-left edge reads as negative and the move is ignored, so a real crossing flips late (or a move is dropped). Device logs show view = window sized (no visible effect there). | late display flip / dropped pointer move at the window edge, only while a button is held | FIXED ac633da: `locationInView:nil` (window coordinates) in the guard and in the P5 probe |
| D2 | G3B.x `updateMedusaHostedKeyboardWindowForScene:` (7e26771) | the SHOW / HIDE debug line built its ten arguments (strings, rect descriptions, five message sends) on every evaluation, with logging off | needless work on every keyboard scene change on every display (rule: no log cost without Backport162.debug) | FIXED 8be2cdd (`if (BP_LogEnabled())`) |
| D3 | BPDaemon.h `BPDW_Line` | a line longer than the 1400 byte buffer lost its newline; the next line was glued to it (daemon log read by G2D) | garbled `daemon:` lines in Backport162.log, only for very long lines | FIXED fa3b283 (syntax checked with clang -Wall -Werror) |
| D4 | X7Keyboard.x `X7_Acquire` | the one-shot "resign active" scope armed by a caller wrapper is consumed by the FIRST `-[UIApplicationSceneDeactivationAssertion acquire]` inside the wrapped method, whatever the assertion's reason. If a wrapped 16.0 method acquires another assertion first, that one is display scoped and the resign-active assertion stays global. Reason 5 verified for `SBToAppsWorkspaceTransaction _acquireResignActiveAssertion` (16.2 0x1c72e718c, `newAssertionWithReason:5`) and the fluid switcher (0x1c743d6ac); not provable for the other six wrapped callers (their assertion is made elsewhere). | hypothetical: wrong display scope of a deactivation assertion | DEFECT-OPEN (no evidence of a wrong first acquire; a `reason == 5` test would silently disable the scoping for any caller whose reason is not 5, which is worse). To close on a device: log line `[x7] resign active assertion (kind N) acquired for display` must be followed by exactly one line per wrapped call |
| O1 | SPK.c `is_session_object` (30ed585) | `object_getClass` / `class_getName` on a malloc'd non-object would read a garbage isa | only if the argument of CMSUtility_IsAllowedToStartPlaying is not an ObjC object (the disassembly says it is) | DEFECT-OPEN, residual, previous M4 narrowed by the check |
| O2 | Tweak.x `_embeddedLockStateDidChange:` | 16.0 registers the handler for two notifications (device lock state AND aggregate lock state), 16.2 only the aggregate one; the extra call is an idempotent `_updateExternalDisplayCoverSheetExistence` | none observable | VERIFIED as harmless (not changed) |

No defect that explains a device symptom was left unfixed. Questions (a) (b) (c) are answered in section 3.

## 2. Table per hook / function

### Tweak.x (16.0 / 16.2)

| symbol | 16.0 / 16.2 | verdict | evidence |
|---|---|---|---|
| BP_Log, BP_OnName, BP_OptInName, BP_On, BP_SlotFor (780b69a) | - | VERIFIED | lock-free read path: name pointer cache verified with strcmp before use, slot index published with release store after the name is written; rotation / reopen test once a second; all names <= 30 chars (slot name 40); write(2) per line under gMu |
| `_preferredSizeInPixelsForTargetCADisplay:` (scale) | 0x1c633a7a8 / inlined in 0x1c73bb2b8 | VERIFIED | per-axis clamp min(max, max(min, v)), display type 2 uses the mode size; the same arithmetic as X3_CtlTransform |
| `_shouldAutoHostScene:` (autohost) | 0x1c63ae320 / 0x1c7858710 | VERIFIED | 16.2 adds `usesInputSystemUI` and `[scene.identifier isEqualToString:arbiter id]` returning NO; hook does exactly that after %orig |
| `_shouldEnableSystemGestureWithType:` (type 0x42 -> YES) | 0x1c6365c28 / 0x1c780bf58 | VERIFIED | 16.2 mask accepts 0x43 (bit 50); the types after 0x34 are shifted by one between builds, 0x42 (16.0) = 0x43 (16.2); 16.0 enables only types <= 0x39 and 0x68/0x69 |
| `_initWithWindowScene:...` wake gesture | 0x1c62f2b4c / 0x1c778fc38 | VERIFIED | 16.2 creates `SBFMouseButtonDownGestureRecognizer` after the window and `_updateExternalDisplayCoverSheetExistence`, type 0x43, `setEnabled:!screenOn`; hook creates it after the 16.0 init with type 0x42, same enabled state; `@catch` for the 16.0 duplicate type assert |
| `_setScreenOn:` | 0x1c62f367c / 0x1c7790b4c | VERIFIED | 16.2: return if unchanged, store, `BKSDisplayServicesSetDisplayBlanked(hw, !on)`, `[gesture setEnabled:!on]`, assert on nil hardware id; 16.0 stores and calls `_setBlankingWindowVisible:!on 0.5`; hook = %orig then the 16.2 steps, nil hw logs and returns instead of asserting |
| `_setBlankingWindowVisible:fadeDuration:` (nowindow) | 0x1c62f369c / absent | DEVIATION (documented) | 16.2 has no window; suppressed while `nowindow` and `blank` are on; Backport162.off.nowindow restores the 16.0 window |
| `_updateExternalDisplayCoverSheetExistence` | 0x1c62f34d4 / 0x1c77908f8 | VERIFIED | hide path: will(NO), `_setScreenOn:YES` FIRST, window hidden, `setSuspendedUnderLock:NO`, notification (16.2 adds it), layout element, did(NO); `_shouldShowExternalCoverSheet` = `[lockStateProvider hasAnyLockState]` (0x1c7790f9c) = 16.0 `_embeddedHasAnyLockState` |
| `backlightController:willAnimateBacklightToFactor:source:` | 0x1c62f333c / 0x1c77905f8 | VERIFIED | 16.2 ignores the call when invalidated (main queue assert + `_shouldIgnoreEmbeddedBacklightChangingSource:`), else factor >= 5.96e-8 -> `_setScreenOn:` |
| `_embeddedLockStateDidChange:` | 0x1c62f3408 / 0x1c7790784 | VERIFIED | 16.2 logs and, unless invalidated, calls the existence update; see O2 |
| `invalidate`, `dealloc` | absent / 0x1c77901fc, 0x1c7790028 | VERIFIED | 16.2 invalidate: center removeObserver, backlight removeObserver, assertion invalidate + nil, `_isInvalidated = YES`; 16.0 dealloc (0x1c62f2ee0) does the first three, the hook sets the flag and removes the dismissal observer; dealloc assert of 16.2 is not needed in 16.0 |
| `coverSheetPresentationManagerDidChangeDismissedSinceKeyBagLock:` + SBCoverSheetPresentationManager add/removeDismissalObserver | absent / 0x1c7790898 | VERIFIED | callback runs the existence update when the manager is the controller's and it is not invalidated |

### Group4Focus.x

| symbol | address | verdict | evidence |
|---|---|---|---|
| `_pointerMovedInScene:` hold-flip guard (p5_holdflip) | 16.2 0x1c795e838 (stores unconditionally) | DEVIATION (documented) + FIXED ac633da | ignores a move whose location lies outside the bounds of its own window while a pointer button is held. Fixed to compare window coordinates. Device log u6/3 `hold-flip guard` lines: location (-3.9, 2.9), the press scene itself, at the display edge |
| flip probe (P5 step 1, 60db6ce / aeac0c2) | - | VERIFIED | log only, `BP_LogEnabled()` gated, bounded to 12 per press, CI green (the file declares `_contextId`) |
| `handleSendEvent:` sniffers | 0x1c795eb54 / 0x1c795ed7c / 0x1c795ef94 | VERIFIED | unchanged since 0.7.0 |
| `sceneDidDisconnect:` step 8 (cover sheet) | 0x1c746826c | VERIFIED | calls the ported `-invalidate` before the controller is released |
| `BP_G4_ActiveMethodology` | 0x1c74bf1c4 | VERIFIED | note: `NSClassFromString` + `rootSettings` per call (about 60 callers); correct, a few hundred ns |

### G4B.x

| symbol | 16.0 / 16.2 | verdict | evidence |
|---|---|---|---|
| `G4B_SendCloneMsg` (7197fbc) | MIG 0x5b9fa0 / 0x5b9fa1 | VERIFIED | reply read from the receive buffer (same buffer as the request); size, id + 100, complex bit, RetCode; timeouts drop the reply port; runs on the private serial queue (never the main thread); device log u6/3 `<<< reply id 6004740, MIG code 0 after 0 ms` |
| clonemirror token / request cache | 16.2 0x1c79917ac | VERIFIED | reviewed in REVIEW-PLUMBING; transport no longer waits on the main thread (dispatch_async) |
| edu native alert (eduauto, a02046e) | 16.2 app `SBEExternalDisplayContentViewController` | DEVIATION (documented) | memmem on the installed app's executable; absent or unreadable = native alert with the 16.2 strings (BPL10NEdu.h); completion results 1 / 2 map to `setMirroringEnabled:` like 16.2; main thread via G4B_Main; the 16.0 app cannot be inspected here (device unproven) |
| pill view controller, session logic | 0x1c77e8104 | VERIFIED | strings through BPLoc_String (bundle, embedded 16.2 table, 16.0 key, English) |
| lockedptr2 `invalidate` / `clientWithSceneIdentifier:suppressPreferredLockStatus:` | 0x1c76b9298 / 0x1c76b8fc4 | VERIFIED | both are `dispatch_sync` onto `_stateSerialQueue` in 16.2 too (disassembly); 19f760d removed the extra main-thread syncs: `G4B_LPMInv` reads the associated flag set once in `invalidate` |
| `_queue_lockPointerForSceneIdentifier:` etc. | 0x1c76ba3dc | VERIFIED | unchanged since REVIEW-PLUMBING |
| migrate / migrate_stage | 0x1c76c85e0 | VERIFIED | reviewed there (section 5); unchanged |
| focuslock policy hook | 0x1c6324e5c / 0x1c77c58c8 | VERIFIED | 16.2 0x1c77c5f34..0x1c77c62c4 decoded: stealing window on the ACTIVE scene when `pid != getpid && ext.display != active.display`, else the 16.0 search on ext's display; hook condition identical (also for a nil display); prologue and caller word compared before patching; BSCompoundAssertion `reasons` / `orderedContext` answers only while the thread-local context is armed |
| focuslock apply hook | 0x1c6325d8c / 0x1c77c6994 | VERIFIED | writes the weak ivar at 0xa0 through `objc_storeWeak` (offset checked), advice 0 -> last lock whose scene is the active scene, else nil |
| `lockFocusToSpringBoardWindowScene:forReason:`, `multiDisplayUserInteractionCoordinator:updatedActiveWindowScene:` | 0x1c6321c94 / 0x1c77c19f0, 0x1c77c56d8 | VERIFIED | map pruned at each policy / apply run; `updateKeyboardFocusDeferringRules` exists in 16.0 (0x1c6321b70) |
| MSHookFunction use (policy, apply) | - | VERIFIED | stripped target / replacement, resigned trampoline (same pattern as BBD.x, live on the device) |
| siriexception | 0x1c5ee6ca0 / 0x1c735acb8 | VERIFIED | thread-local state restored; setter hook replaces YES by NO only when armed |
| discextras | 0x1c616ca94 / 0x1c75f45c0; 0x1c5fc335c / 0x1c743bc98 | VERIFIED | the ivars torn down in `G4B_FluidTeardown` are all object ivars in 16.0 (checked in the class dump), idempotent with dealloc |
| `_noteSceneDestroyed:` guard (y1_scenedestroyguard, e37ee15) | SpringBoardUI 0x1f1185b3c | VERIFIED | returns before the assertion only when the destroyed scene is not the tracked one; probe only on a mismatch |
| native edu / pill / session timers | - | VERIFIED | `_isPresenting` guards; disconnect dismisses the native window |

### Group4Connect.m

| symbol | address | verdict | evidence |
|---|---|---|---|
| discguard entry points `displayIdentityDidDisconnect:`, `_enqueueEvaluateAndApplyPresentationUpdate`, `_runRootUpdateTransactionWithLabel:completion:` | 16.2 0x1c73be... | VERIFIED | fire-and-forget callers only are skipped |
| discguard block hooks | 16.0 0x1c5f47584 (connect completion), 0x1c5f4972c, 0x1c5f49970 / 16.2 0x1c73bbfac, 0x1c73be154, 0x1c73be3c0 | VERIFIED | prologue words equal the disassembly; connect completion reads the controller at block+0x20 (`ldr x8,[x0,#0x20]` then `strb [x8,#0x58]`), update blocks signal at +0x20 (hasBeenSignalled) and controller at +0x28; the 16.2 signalled path logs and ends without doing the work, as the skip does |

### G3B.x / G3.x

| symbol | address | verdict | evidence |
|---|---|---|---|
| hosted keyboard window controller `updateMedusaHostedKeyboardWindowForScene:isForeground:` | 16.2 0x1c76275f4 | VERIFIED / DEVIATION (kbhosthere) | first return, host lookup and the three branches are the 16.2 sequence; kbhosthere refuses the resizable branch when the host scene's own display differs from the controller's display (16.2 has no such test) |
| kbhosthere | - | DEVIATION (documented) + FIXED 8be2cdd (log cost) | see question (a) |
| `medusaHostedKeyboardWindowController` (kbmedusa, d586333) | 0x1c77f80e4 | VERIFIED | returns the per-scene associated controller, nil with the switch off; the controller implements `isUsingMedusaHostedKeyboardWindow` |
| `newMedusaHostedKeyboardWindowLevelAssertionWithPriority:windowLevel:` | 0x1c762726c | VERIFIED | +1 handling (new family) with CFRetain |
| zoom / full screen / banner labels (l10n162, 237c8ef) | loctable | VERIFIED | BPLoc_String order: bundle, embedded 16.2 table (41 languages), 16.0 key, English; language candidates incl. zh_HK, pt_PT, es_419 |

### X2Overlay.x, X3Mode.x, X5Recording.x, X6InCall.x, X7Keyboard.x, X9Pin.x

| symbol | address | verdict | evidence |
|---|---|---|---|
| overlay getters (CC module, in call, passcode, voice control) | 0x1c7567e88, 0x1c75da010, ... | VERIFIED | `mov w0,#1; ret` in 16.2 |
| Spotlight getter | 0x1c76bb71c | VERIFIED | `presentationSource == 1 || == 7`; `presentationSource` exists in 16.0 |
| `modifyTransientOverlayContext:` on SBMainWorkspaceTransitionRequest | 0x1c7893a84 | VERIFIED | super, transitionType 0, `prefersEmbeddedDisplayPresentation`, `workspace.mainWindowScene` -> `setWindowScene:` (disassembly) |
| interactive Spotlight request, `_executeTransientOverlayTransitionRequest:` env mode | 0x1c7352bf8 / 0x1c7375028 | VERIFIED | one-shot thread-local arming, restored on return; the four argument request exists in 16.0 |
| X3 preferences class, `_preferredModeForDisplay...`, controller transform, `_preferredLogicalScale`, cloning supported | 0x1c73bb2b8, 0x1c77dd034, 0x1c78e9674, 0x19cad6920 | VERIFIED (arithmetic by reading) | `logicalScaleForDisplayScale:` takes unsigned long long and returns double in both builds; `_contentScale` ivar double; `_copyWithOverrideSize:scale:` is copy family (+1); clamp order min(max, max(min, v)); not re-decoded instruction by instruction (device unproven) |
| X5 per scene recording indicator manager | 0x1c7467ed8 / 0x1c77f82ac / 0x1c75bc7c4 | VERIFIED | thread-local scene around `_configureStatusBarWithCurrentStyleRequest`; alloc / init through an objc_msgSend cast is refcount balanced (init returns self) |
| X6 in-call session follows the scene handle's display | 0x1c7575954, 0x1c757a10c, 0x1c766ba00, 0x1c76696ac | VERIFIED | 16.0 session has `_sceneHandle` 0x170, `_windowScene` 0x178 (weak, `object_setIvar` stores weakly), `_sceneManager` 0x78, `_screen` 0x80; residual: `_sceneManager` is typed SBMainDisplaySceneManager in 16.0, the selectors the 16.0 session sends to it were not enumerated (LOW, device) |
| X7 tracker, display scoped suppression, external identities | 0x1c74bfb9c, 0x1c75376dc, 0x1c77af7b0, 0x1c77c4590 | VERIFIED except D4 | `-acquire` = `acquireWithPredicate:nil transitionContext:nil` in 16.0 (0x189301444), so `sb_acquireForDisplayIdentity:` is equivalent; `_filterFocusedSceneIdentityToken:` reads `_highPrioritySceneToFocusInNextPolicyUpdate` outside the lock exactly like the 16.0 body (0x1c6323f3c) |
| X7 UCS block by address | 0x1c62d2588 / 0x1c776d5b8 | VERIFIED | prologue words and the adrp/add pair are compared before patching; flag at block+0x28 |
| X9 pinOnButtonDown | 0x1c6319b88 / 0x1c77b937c | VERIFIED | `SBFFeatureFlagsIsChamoisExternalDisplayControllerEnabled` is exported by 16.0 SpringBoardFoundation (0x18eb68fd4); options built through `BKSMousePointerGlobalContextOptions build:` only inside `_configureForNewSystemGestureWindowIfNecessary` |

### G2D.x, G2G.x, Z1Diag.x, BPCrash.m, daemons

| symbol | verdict | evidence |
|---|---|---|
| G2D `_updateCancelsTouchesWithRecognizer:` (g2d_homecancel) | DEVIATION (documented) | unchanged; edge 4 / type 0x2b only |
| G2D daemon log ingest, daemon load notes | VERIFIED | only whole lines, 64 KiB per tick; with logging off only one cached `access()` per 2 s; re-ingests the old daemon log after each SpringBoard start (cosmetic) |
| G2G observer, stale enter filter, arbiter trace | VERIFIED | trace arguments are built only under `BP_LogEnabled()`; pending-exit list bounded to 16 |
| Z1Diag sampler `Z1_TakeSample` | VERIFIED | between `thread_suspend` and `thread_resume`: only function pointers resolved earlier by dlsym, `thread_get_state`, integer arithmetic, reads of the main thread's own stack inside [sp, hi); `thread_info` before the suspend; resume on the only path that follows a successful suspend; formatting, file writes and dladdr after the resume; no malloc in the window |
| Z1Diag watchdog, touch probe, vitals, state dump | VERIFIED | ping is one block per 250 ms and none while one is outstanding; probe stacks above the other `SpringBoard sendEvent:` hook; vitals / dump on the main queue, every ObjC access guarded, files capped at 256 KiB / 1 MiB |
| BPCrash.m | VERIFIED | async-signal-safe writers, 3 s alarm against a dladdr hang, SA_RESETHAND re-raise |
| BBD.x `hk_handler`, `BPD_Serve`, `hk_updateClone`, pointer exit hooks | VERIFIED | prologue words and IMPs compared; `gHookLock` is initialised (recursive) before the hooks are installed; reply built like libdispatch's demux; crash guard re-arms after 30 min |
| PTR.x ptr_layerclass / ptr_hidden / ptr_scene / ptr_hover / ptr_edge | VERIFIED | `BPPTR_Log` and `NSLog` only with Backport162.debug; installs are retried for 5 s on the main queue |
| BPDaemon.h | FIXED fa3b283 | see D3 |

## 3. Answers to the specific questions

(a) Do the deviations break a 16.2 behaviour the user needs?

* kbhosthere (typing into a monitor app with only a mouse): no. The monitor's own controller shows its hosted keyboard window for a host on the monitor: u11/11.log has `hosted keyboard window 0x124dd6b00 SHOWING` (the monitor's window scene) at 16:24:23, 16:24:31, 16:24:54, 16:25:08 ..., while the iPad window no longer shows the keyboard of a monitor host. A host on the iPad is unchanged (u10 iPad windows SHOWING 4 s while an iPad app was typed into). Residual: if the keyboard scene's display stayed the iPad while the focused host is on the monitor, no window would show the keyboard; no log shows that state (the new debug line prints both displays and the host's display, so one recording decides it). `Backport162.off.kbhosthere` restores the 16.2 decision.
* p5_holdflip (a drag that starts on one display and continues): no. The guard drops only a move whose location lies outside the window of the scene it is reported for while a button is held; the pinned duplicate has such a location, the first event of the other display inside its own window still switches the display. D1 made the test use window coordinates. A stale `_touchDownWS` (touch cancelled, phase 4) cannot hurt: events outside their own window do not exist without a pinned button.
* blank / nowindow: the lock behaviour is the 16.2 one (BKS blank + mouse wake gesture, no window); `Backport162.off.nowindow` brings the 16.0 black window back. No lock event is in the logs yet (DISPLAY-LEFTOVERS section 8 test recipe).
* eduauto: only replaces the remote alert when the installed SpringBoardEducation.app has no external display content controller (the class name is searched in its executable); otherwise the 16.2 remote alert path runs. A wrong "absent" only gives the native alert with the same texts and answers.

(b) First fatal errors of the daemons: BBD.x and PTR.x compile with -Wall -Werror in the same CI run as everything else (run for ac633da green, both jobs). Device log u6/3 (backboardd): `ctor: install result: updateClone 1 handler 1 pointer process 1 link exit 1` on every backboardd launch, and the clone mirror request answered (`<<< reply id 6004740, MIG code 0`). The build string (20A8372), the prologue words of every patched function, the subsystem start id and the ivar offsets are compared before any patch; every failure leaves the daemon unpatched with a marker line. The only silent-off cases: the crash guard (3 short-lived launches within 30 min, re-arms), no writable log directory (the guard cannot count and stays out: BPD_CrashGuardTripped returns YES), and a different iPadOS build.

(c) Send logs token: no secret in the repository (git grep for GitHub token formats over the tree finds only the instruction text of SEND-LOGS-0.7.9.md; the history search for `github_pat_` hits the commit that added that text). The token is read in RPT.x only for the Authorization header of the one upload and for the scrub (every collected section is scanned and replaced by `[removed]` before gzip, D5 of REVIEW-SENDLOGS); the only logging is `RPT_LOG` (status, GitHub's message, ids), no `NSLog`; Settings only tests it for emptiness; the CI workflow uses no secret of the tweak.

## 4. Device checks that remain

keyboard on the monitor window while the pointer is on the iPad (kbhosthere line shows both displays); lock / unlock with the monitor (`blank:` lines); native education alert (`edu:` lines); the X7 resign-active scope lines (D4); X5 indicator dot on the monitor; X6 session after an unplug.
