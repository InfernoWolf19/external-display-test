# REVIEW plumbing / display lifecycle / pointer (0.7.9, head 1ec6584 + merge e8a0299)

Scope: G3.x, G3B.x, G4B.x, Group4Connect.m, Group4Focus.x, G2D.x, G2G.x, PTR.x, BBD.x, BPDaemon.h, EDE.x, AV.x, PIPStop.x, Tweak.x, BPCrash.m, BP.h/BPShared.h, Makefile/control/CI, plus the newly merged SMT.x and SPK.c.
Method: every file read completely; hook targets checked against the 16.0 class dump (script `hookcheck2.py`: every non-`%new` Logos hook resolves to an existing 16.0 method or an inherited one; no missing selector); WORKLIST rows of the area diffed against the hooks (`wl_cov.py`) and, where a method is not hooked, the 16.0/16.2 call sequences diffed (`plumb_seqdiff.py`); the BBD addresses re-verified in the 16.0 backboardd binary (all prologue words, subsystem start id 6001000 = 0x5b9168, class/ivar names present); 16.2 bodies compared by hand for `_launchingInterfaceOrientationForOrientation:` (0x1c72e6e94: IDENTICAL logic), cover sheet `_setScreenOn:` / `_updateExternalDisplayCoverSheetExistence` / backlight handler, `windowSceneDidConnect:` of the PiP manager, `SBExternalDisplayWindowSceneDelegate _configureForConnectingWindowScene:`. Nothing was run on a device; "unverified" below means static reading only.

## 1. Fixed defects (commits on claude/backport162)

| sha | what / why |
|---|---|
| 2e619c0 | SPK.c crash guard (see 4): was a silent permanent switch-off and counted both audio daemons in one file (two strikes per userspace restart, tripped after about three quick restarts). Now one counter per daemon, 8 strikes within 600 s, forgets itself 600 s after the last strike, loud (`os_log_error`, opt-in file log, Darwin note `...load.spk.crash_guard_tripped` that G2D.x writes into Backport162.log). README row updated. |
| 19af489 | G4B.x clonemirror transport: the single line "backboardd did not answer ..." covered four different failures. Now logged separately: bootstrap look-up failure, mach_msg failure (timed out or error), reply id mismatch (a send-once notification, id 70, is what the stock demux produces when the BBD handler hook is NOT active). Receive timeout 0.5 s -> 2.5 s (backboardd runs the display service on one workload; the request is executed even when the reply is late). |
| df33142 | BBD.x crash guard re-arms itself (strikes older than 30 minutes forgotten); before, three strikes kept the backboardd half out until the file was removed or the build changed. |

## 2. The question "SpringBoard logs `backboardd did not answer the set/remove request` although the BBD dylib is injected"

Verified from the code and the binaries, no defect found on the path:
* Transport (G4B.x `G4B_SendCloneMsg`): MIG-shaped message id 0x5b9fa0 (set) / 0x5b9fa1 (remove) to `com.apple.backboard.display.services`, `COPY_SEND` + `MAKE_SEND_ONCE`, header 24 + NDR 8 + len 4 + padded uuid (+4 mode), reply buffer 44 bytes + 64 pad, id check `request + 100`.
* Daemon (BBD.x): 16.0 backboardd 0x100026c30 creates the dispatch_mach channel with handler 0x100026d14 and context = the mig_subsystem (`adr x2` -> 0x1000e56a8, start id at +8 = 6001000 = 0x5b9168, read from the file). The stock handler passes `ctx` as the single subsystem pointer to `dispatch_mach_mig_demux`, so `hk_handler`'s `ctx == gSubsystem` test is right, `reason == 2` (MESSAGE_RECEIVED) is what the stock code compares to. Prologues of all patched functions equal the words in BBD.x. The reply is built like libdispatch's demux (bits `& 0x1f` = MOVE_SEND_ONCE, id + 100, KERN_SUCCESS reply, failure replies keep the reply right). The proxy object put into `_queue_currentCloneMirroringClient` is only sent one selector by the 16.0 `updateClone` (`mode`).
* So an answer CAN arrive. The remaining ways to get "no answer": (a) the hook is not installed (crash guard tripped; `BPD_InstallCloneMirror` returned early; the dylib not loaded into THIS backboardd instance, e.g. the daemon was not restarted after the install): then the stock demux drops the unknown id and destroys the reply right = reply id 70 (now logged as such); (b) timeout (now 2.5 s and logged as such); (c) look-up failure (now logged). The `install result: updateClone N handler N pointer process N link exit N` line of the daemon marker (always written, copied into Backport162.log by G2D.x with the prefix `daemon:`) says which hooks are live. NEXT STEP FOR THE USER: send the log lines `clonemirror: ...` and `daemon: ctor / install result` of the new build; with them the case is decided.
* What 16.2 does: `_BKSDisplaySetCloneMirroringModeForDestinationDisplay` is a plain MIG call (id 0x5b9174/5) on the BKS port; its client function ignores the failure (the BSSimpleAssertion token is created regardless). Our behaviour (log only, no fallback to the global per-process API) is the same.

## 3. COVERAGE MATRIX (area: plumbing / display lifecycle / pointer)

Status: PORTED = 16.2 logic reproduced from the disassembly; DEVIATION = deliberate, documented; PARTIAL; NOT = not ported. "Eff" = user-visible effect of the gap.

### 3.1 External display lifecycle
| item (16.2 address) | status | where | eff / note |
|---|---|---|---|
| Extended provider registration (beta-5 behaviour, 20A8372 lacks it) | PORTED (merged EDE) | EDE.x | verified on device |
| autoext / saved mirror-extended choice, mirrorsvc fix | PORTED + DEVIATION (saved choice from EDE) | Group4Connect.m | verified on device (EDE merged) |
| `connectToDisplayController:` policy (0x1c77dba48): 4 s window, user pref, notifications | PORTED | Group4Connect.m hk_policyConnect | teardown is hooked at `DidDisconnect` (16.2: `WillDisconnect`), tiny ordering difference |
| `SBSceneHostingDisplayController transformDisplayConfiguration:withBuilder:` (0x1c73bb2b8, 70->278) | PORTED (0.7.9: `modetransform`, `cloningsupported`, criteria, `keepOtherModes`, SBSceneHostingDisplayPreferences class) | X3Mode.x + Tweak.x `scale` | specs/DISPLAY-LEFTOVERS-0.7.9.md section 3; device-unproven |
| `_ensureCADisplayUpToDate:completion:`, `displayIdentityDidUpdate:`, `_updatePolicyForPresentation:` (0x1c73bd620, gate `shouldUpdatePresentation` dropped in 16.2) | NOT (refactor + hardening) | - | `discguard` guards the two entry points (PARTIAL) |
| `_displayDisconnectedSignal`, `WillDisconnect` phase (0x1c73bc47c) | PORTED (0.7.9: the three signal blocks are guarded by address; the `WillDisconnect` policy phase is only a callback name, the guard flag is set before the 16.0 body runs) | Group4Connect.m discguard | DISPLAY-LEFTOVERS section 11; device-unproven |
| `_createDisplayAssertionPreferences` asks the policy | PORTED (equivalent) | G4B.x | the 16.0 `_connectionCompleted` gate stays (16.2 dropped it) |
| provider map cleanup on disconnect (0x1c7345fe0) | PORTED | Group4Connect.m provmap | |
| `SBDisplayManager displayMonitor:didConnectIdentity:` 346->88 / per-display record refactor | NOT (refactor) | - | no behaviour; 16.2 per-display power log/arrangement/idle-sleep setters are done by the 16.0 aggregate |
| window scene delegate `sceneDidDisconnect:` (0x1c746826c) | PORTED | Group4Focus.x | |
| `SBWindowScene invalidating/invalidated`, kfc `suppressKeyboardFocusEvaluation` | PORTED | Group4Focus.x | the suppression only advisory unless `directhook` installs (prologue verified) |
| kfc `windowSceneDidDisconnect:` (0x1c77c3b14) | COMPLETE (same sequence through the 16.0 public methods, see DISPLAY-LEFTOVERS section 11) | Group4Focus.x |  |
| `SBMultiDisplayUserInteractionCoordinator` + 3 sniffers | PORTED as a stand-in class | Group4Focus.x | not the 16.2 class name on purpose |
| `activeDisplayWindowScene` (0x1c74bf1c4), methodology setting | PORTED; settings UI row `settingsControllerModule` (0x1c74236a8, 221->252) NOT (PTSettings internal UI) | Group4Focus.x / G4B.x | methodology not persisted; default 1 |
| window migration on unplug (0x1c76c85e0) | PORTED (owner switcher lookup, builder 0x11, validator) | G4B.x | verified on device (lookup); end state in the strip = 16.2 |
| migrate_stage | DEVIATION (documented, see 5) | G4B.x | device-unverified |
| per-display clone mirroring (client + backboardd) | PORTED | G4B.x + BBD.x | reply path see 2; device-unverified |
| education session / pill / observer rework | PORTED, UNSURE (SpringBoardEducation.app type 1) | G4B.x | observer is created in `applicationDidFinishLaunching:`; a display plugged in BEFORE that point would miss the connect note (LOW) |
| `presubset`, `deferact` (100 ms), `focuslock` | PORTED / PORTED / PORTED BY ADDRESS (0.7.9: MSHookFunction on the two objc_direct functions, prologue and caller words verified) | G4B.x | DISPLAY-LEFTOVERS section 1; device-unproven |
| `SBNonInteractiveDisplayControllerPolicy updatePresentation...` (0x1c78e92ec, 105->192) | EQUAL by construction (16.0 gate `shouldUpdatePresentation...` does the comparison 16.2 folded into the update) | - | DISPLAY-LEFTOVERS section 11 |
| nilock (SBNonInteractiveDisplaySceneManager suspended-under-lock, 15 methods) | COMPLETE (15 of 15 methods; the only notification poster is the external cover sheet in both builds) | Group4Connect.m | DISPLAY-LEFTOVERS section 11 |
| cover sheet: BKS blanking instead of a black window, wake-on-click (0x1c7790b4c, 0x1c7790fa4) | PORTED | Tweak.x `blank` / `nowindow` | |
| cover sheet: `_setScreenOn:YES` before the window is hidden in `_updateExternalDisplayCoverSheetExistence` (0x1c77909e8), presentation-manager observer `coverSheetPresentationManagerDidChangeDismissedSinceKeyBagLock:` (0x1c7790898), `_isInvalidated` + dealloc assert, main-queue assert | PORTED (0.7.9) | Tweak.x `blank` | DISPLAY-LEFTOVERS section 8 |
| `SBExternalDisplayWindowSceneDelegate _configureForConnectingWindowScene:` additions (0x1c7467d5c): `SBSystemPointerInteractionManager initWithMultiDisplayUserInteractionCoordinator:` + `SBSystemPointerInteractionDelegate initWithDisplayIdentity:` | NOT (16.0 has no class; hover regions handled by G2G/PTR deviations instead) | - | pointer-interaction callbacks per display (16.2 `shouldBeginPointerInteractionRequest:atLocation:forView:`) not ported |
| same method: per-scene `SBTransientUIInteractionManager initWithSystemGestureManager:` (0x1c7467e9c) | PORTED by Y2Gestures.x `y2_tuiscene` (other agent) | G2C.x / Y2Gestures.x | not duplicated |
| same method: per-scene `SBRecordingIndicatorManager` (0x1c7467ec0..ed8; 16.0 has `initWithSensorActivityDataProvider:windowScene:` and creates it for the main display only: `_startRecordingIndicatorForMainDisplayWindowScene:` 0x1c5edc0e8) | NOT | - | Eff: no camera / microphone indicator dot on the extended display. Proposed patch: hook `SBExternalDisplayWindowSceneDelegate _configureForConnectingWindowScene:...` after `%orig`, `[[SBRecordingIndicatorManager alloc] initWithSensorActivityDataProvider:[SpringBoard sensorActivityDataProvider] windowScene:scene]` and keep it in an associated object of the delegate (invalidate on disconnect). Not done: untested, new visible UI |
| Settings pane `DBSMultitasking...`, `SBExternalDisplayService` small deltas (0.97) | NOT (identical sequences) | - | |
| 16.2 disconnect extras (PiP controller `_windowSceneDidDisconnect:`, VC `invalidate`, transient overlay manager, assertion coordinator `rootDisplayDidDisconnect:`, `takeScene` observer callout, compat map key) | PORTED / EQUAL (0.7.9: transient overlay manager and switcher view controller `invalidate` ported as `discextras`; PiP controller, assertion coordinator `rootDisplayDidDisconnect:` equal; `takeScene` callout and compat map key are in-call only, see DISCONNECT-MIGRATE 5.3) | G4B.x `discextras` | DISPLAY-LEFTOVERS section 11 |

### 3.2 Scene / window plumbing
| item | status | where | note |
|---|---|---|---|
| scene handle orientation state, `_launchingInterfaceOrientationForOrientation:` full body, supported orientations, mode, events, mask style, resuming, activation, client-settings inspector | PORTED (launching body compared instruction by instruction with 0x1c72e6e94: identical) | G3.x g3handle | |
| `_modifyApplicationSceneSettings:fromRequestContext:entity:` (0x1c729dfb4): `screenBoundsIgnoresSceneOrientation`, `supportsChamoisOnExternalDisplay` rename, `_isInCallBanner` removal | NOT (needs the UIKit client in every app; the property does not exist in the 16.0 `UIMutableApplicationSceneSettings`) | - | Eff: fixed-size (non-resizable) apps on the extended display are laid out against the scene orientation instead of the screen bounds. Needs an app-side dylib (AV.x shows the mechanism) |
| snapshot hosting-info assertion stack | PORTED | G3.x g3snapshot | |
| top affordance highlight, menu (zoom title before the menu is built, 16.2 keys with fallback) | PORTED; zoom title reviewed adversarially (see 6) | G3.x, G3B.x | |
| style change notification, canvas size notification, embedded display enhancedWindowing sync, boot orientation | PORTED | G3.x | |
| hosted keyboard window controller per scene | PORTED (fan-out controllers) | G3B.x | |
| system banners types 2/3, menu changes (0x15/0x16) | PORTED | G3B.x | wording UNSURE |
| PiP per display (stash tab manager, observers, adapter provider) | PORTED | G3B.x, PIPStop.x | PiP expand verified on device |
| status bar `options:` + per-display frontmost status bar | PORTED | G3B.x | |
| user-resize orientation chain, orthogonal grids, SBSwitcherTraitsAssistant guide | PORTED, UNSURE | G3B.x | `SBFluidSwitcherPortaledSceneLiveContentOverlay` has no creator (`_updatePortaledSceneLiveContentOverlays` 0x1c74ce070, cross-display window drag): NOT |
| AX / Eyedropper / Moments traits roles | PORTED for AX only; Eyedropper / Moments skipped; default ON although spec and code comments say opt-in | G3B.x g3b_axroles | see open defects |
| privacy preflight gate | CANNOT (PrivacyDisclosureCore absent); log of the decision only (`g3b_preflightlog`, default on) | G3B.x | |
| per-scene `SBLockedPointerManager`, `_UIPointerUnlockAction`, suppress-preferred-status | PORTED, UNSURE | G4B.x lockedptr2 | `initWithSceneManager:` of an external manager is safe: `_layoutStateTransitionCoordinator` is defined on the `SBSceneManager` base (nil for the external manager, `addObserver:nil` is a no-op) |

### 3.3 Pointer
| item | status | where |
|---|---|---|
| backboardd exit events for the global routes of the display left (16.2 0x100055a80 / 0x100051ea0) | PORTED (pointerState 3 wire value) | BBD.x |
| pointeruid 16.1 changes (layer class, hiddenForPerformanceReasons, nil system scene) | PORTED | PTR.x ptr_layerclass / ptr_hidden / ptr_scene |
| per-display AX zoom of pointeruid | NOT (on purpose) | - |
| stuck hover regions, edge specks, resize-corner jump | DEVIATIONS (documented, verified on device) | PTR.x ptr_hover / ptr_edge, G2G.x |
| SpringBoard pointer arbiter 16.2 per-display routing (`SBSystemPointerInteractionManager`) | NOT, replaced by G2G | see 3.1 |
| mouse-pointer controller mirrored pointer ("clone pointer") | n/a | |

### 3.4 Added packages (0.7.9)
SMT.x: PORTED from StageManagerToggle (no 16.2 counterpart; documented in MERGE-SMT-SPK-0.7.9.md). SPK.c: audio daemon half, no 16.2 counterpart.

## 4. SPK.c / SMT.x adversarial review

SPK.c (read completely, C on MSHook):
* Crash guard (fixed, 2e619c0). Decision: dropping it would leave an unprotected hook set in two audio daemons whose crash loop silences the whole device, so it stays but as a LOGGED, SELF-RE-ARMING last line: per-daemon counter (the two daemons are always restarted together), 8 strikes inside 600 s, stale counters ignored, trip reported by `os_log_error`, the opt-in file log and a Darwin note that G2D.x logs. Cannot distinguish a crash from an orderly userspace restart (both look like a short-lived launch); the threshold and window make the orderly case practically never reach it.
* Kill switch from a sandboxed daemon: reading `/var/jb/tmp` is covered by the Dopamine extension described in BPDaemon.h; unverified for these two daemons. If the read were denied the switch would silently never work (hooks keep running); not provable statically (LOW).
* Hook discipline OK: build string and 3-word prologue checks before any patch; the table swap is guarded (35 entries, CF types, writable page, failure counter); the replacement is restored when the switch appears.
* `hook_allow` retains `a0` assuming an Objective-C session object (`!(a0 & 7)` is the only check) and sends `isActive` / `audioCategory` later. If `CMSUtility_IsAllowedToStartPlaying` can be called with a non-object (the disassembly was done by the tweak's author, not re-read here) this is a crash in mediaserverd. UNVERIFIED (MED). Proposed patch if needed: check `object_getClass((id)a0)` is a registered class before `objc_retain`.
* `maybe_cf` uses `malloc_size` / `dladdr` on pointers that come from the daemon's own arguments; fine for the cases listed.
* The two idle hooks are observation-only; a failed install of one leaves the other forwarding. `static` caches (`killed`, `debug_on`) race benignly.
SMT.x (read completely): both hooks behind `SMT_On()` (2 `access()` per second), lazy install through bundle-load notification and add-image callback is idempotent (`@synchronized`, flags); no selector shared with the rest of the package (grep). `NSBundleDidLoadNotification` block runs on the posting thread (`installIfPossible` is synchronized, `%init` of a group is safe there). No defect.

## 5. migrate_stage adversarial review (1ec6584, written without device test)

Checked: `[SBSwitcherController layoutState]` returns an `SBMainDisplayLayoutState` (class dump 0x1dd679908), whose `appLayout` (0x1c62898e4) carries `elementIdentifiersToLayoutAttributes`, so the plan reads real window attributes (my concern that the generic `SBLayoutState(SBAppLayoutConversion) appLayout` 0x1c5e2a6bc would give none does not apply). All selectors used on the transition context exist in 16.0 (`setEntities:withPolicy:centerEntity:floatingEntity:`, `setRequestedLayoutAttributes:forEntity:`, `_setRequestedFrontmostEntity:`, `setActivatingEntity:`, `setRequestedUnlockedEnvironmentMode:`, `entityForLayoutRole:`, `setEntity:forLayoutRole:`; `previousEntities` is on the superclass `SBWorkspaceTransitionContext`). The validator reads the iPad's mode at execution time (no stale read), the stage is read before `%orig` tears the external switcher down, entities hold the EMBEDDED handles looked up right after `takeScene:`. Exceptions are contained by `@try` (the merge reads unguarded selectors on entities, a miss only skips the merge).
Not provable statically (device checks): (1) keyboard focus after the transition: kfc's `windowSceneDidDisconnect:` hook removes focus only for scenes still in the dead manager (the migrated ones already moved), `activeDisplayWindowScene` falls back to the embedded scene, so the stock re-evaluation should focus the new front window; (2) the old external `SBAppLayout`s stay in the recents with the external ordinal next to the new iPad stage layout with the same items (the SBAppLayout intern key was read: hash of three integers, a BOOL, one more integer and the items; whether the display ordinal is part of it was not decoded). If the strip shows every migrated window twice this is the cause; (3) attributes of a monitor-sized window on the iPad: relies on the G2B size conversion clamp; (4) the ambiguous-launch rule steering by explicit mode 3.

## 6. Zoom title hook (a8aca00 / 0bf49ce) adversarial review

Compared with 16.2 0x1c790cac4: the 16.2 body sets title (0x1c790cba8, key ..._ZOOM / ..._UNZOOM by `isZoomed`) and image (action 10/11, identical in 16.0 0x1c6459c4c) before the menu is built; the hook sets the title before `%orig`, and when the original created the action itself (first call) re-sets and calls `%orig` once more so the menu is rebuilt with the right title. `_localizedMenuTitleForKey:` exists in 16.0; the fallback key path calls it without a respondsToSelector (safe, it exists). The second `%orig` is the 16.0 body called twice for one update: it is the stock update routine (idempotent in the parts read). Logos syntax is fine (`%orig;` on its own line). No defect found.

## 7. Open defects (ranked)

HIGH
* H1 (unresolved, not provable statically): clone mirroring reply never observed on the device. All transport and daemon code checks out (section 2); the new log lines decide between "BBD hook not active", "timeout" and "look-up failure". If the hook is simply not installed, the daemon marker `install result:` line shows which check failed.

MED
* M1 (RESOLVED: stays ON by the standing directive; comments, spec and README corrected) G3B `g3b_axroles` is ON by default although the spec (group3b-reconstruct.md section 6) and the code comments call it opt-in "because every hook is a risk": it rewrites the traits role of four AX scene controllers (`+_setupInfo`) and appends four role strings to three provider lists. Unverified on a device (spec asks to test AssistiveTouch on the extended display). Decision needed: keep on (directive) or opt-in. Patch if opt-in: `BP_G3B_OptIn` -> `BP_OptInName` for "g3b_axroles" (one line) and a README note.
* M2 Recording indicator and transient-UI interaction manager are not created for the extended display (3.1). Patch proposal in the matrix.
* M3 `screenBoundsIgnoresSceneOrientation` not ported (3.2).
* M4 SPK `hook_allow` retains an unverified object type (4).
* M5 migrate_stage duplicate recents / focus (5), device only.

LOW
* L1 (closed in 0.7.9) `transformDisplayConfiguration` mode criteria / other-modes retention: X3Mode.x, DISPLAY-LEFTOVERS section 3.
* L2 (closed in 0.7.9) Cover sheet 16.2 extras (DISPLAY-LEFTOVERS section 8), 16.2 disconnect extras (section 11).
* L3 PTR.x writes every `BPPTR_Log` to NSLog even without `Backport162.debug` (a handful of lines per display attach); the standing rule says logging is opt-in. Switch to `if (!BPPTR_DebugOn()) return;` before `NSLog` if the system log should stay silent.
* L4 Stale texts: comments in G3B.x (`ITEM 6 ... OPT-IN`), G3.x (`BP_G3_OptIn`), `control` Version 0.7.5 and the Tweak.x "0.7.5 loaded" line against 0.7.9 packaging.
* L5 `G4B` education observer created only after `applicationDidFinishLaunching:`; `hasShownAllExtendedDisplayEducations` is forced to YES while `edu` is on (any other 16.0 reader sees "all shown").
* L6 EDE.x `object_setIvar` + `CFRetain` on a strong ivar retains the provider twice (leak of one reference, harmless: the provider lives for the process).
* L7 G2D daemon-log ingestion and the daemon load notifications run even with logging off (one cached `access()` per 2 s); no output.

## 8. Could not verify

Everything on a device (clone mirroring answer, migrate_stage, edu alert type 1, lockedptr2 external creation, AX roles, SPK idle selection and kill-switch reads in the audio daemons, SMT together with `g3switcher`). Not decoded: the SBAppLayout intern equality (section 5), the 16.2 `SBExternalDisplayCoverSheetController` `_isInvalidated` use beyond the backlight handler, `transformDisplayConfiguration` bodies (only the documented clamp), the contents of the two 750 / 1070 instruction kfc direct methods. The Makefile / control / workflow list of source files is consistent (CI loop file list equals `Backport162_FILES`; SMT.x and SPK.c have their own loops). Logos syntax check (`logos.pl`, rc 0) for G2D.x and G4B.x; BBD.x and SPK.c could only be reviewed by reading (no Apple SDK here), the changes use only constructs already present in those files.
