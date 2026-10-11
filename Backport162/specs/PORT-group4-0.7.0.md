# PORT group 4 / BBD (0.7.0): fallbacks found and what was done

Files: Backport162/G4B.x, Group4Focus.x, Group4Connect.m, Backport162BBD/. Addresses are 16.0 / 16.2 SpringBoard cache vmaddrs unless
"bbd" (backboardd file vmaddrs; 16.2 backboardd was extracted from the 16.2 IPSW for this work, `usr/libexec/backboardd`).
Nothing was run on a device; PORTED = code now follows the 16.2 disassembly, CANNOT = no faithful port possible.

## 1. Clone mirroring (BBD + G4B "clonemirror")

| # | item | state |
|---|------|-------|
| 1 | BBD hook of the MIG lookup 0x1000997f4 never ran (`dispatch_mach_mig_demux` selects routines by the subsystem start/end range, bbd 0x100026d58 / libdispatch 0x18e12c4ac) | PORTED: hook the dispatch_mach handler function bbd 0x100026d14 `(ctx = subsystem 0x1000e56a8, reason, dmsg, error)`; for reason 2 and ids 0x5b9fa0/1 it validates, updates the cache and sends the reply exactly like the demux (reply setup 0x18e12c570..0x18e12c694); everything else goes to the original |
| 2 | BBD had an invented per-display table and "0 = remove" | PORTED: 16.2 `BKDisplayCloneMirrorRequestCache` (bbd16.2 0x10004f7e0 set, 0x10004faf8 remove, 0x10002f23c rebuild, 0x10002f524 pid exit): pid -> uuid -> request, ordered list, prevailing table (oldest request of another pid wins, same pid replaces itself), rebuild on removal, requests dropped when the pid exits; mode 0 is an explicit request that beats the global (AirPlay) mode; modes > 3 rejected like 16.2 |
| 3 | `updateClone` | PORTED: 16.2 0x10004d094: mode = prevailing[display.uniqueId] ?: global client ?: 0, rest of the tree unchanged (16.0 0x10004c930). The prevailing request is presented to the unchanged 16.0 body through `_queue_currentCloneMirroringClient` (NSObject proxy, lock-protected swap) |
| 4 | SB transport fell back to the 16.0 GLOBAL `BKSDisplayServicesSetCloneMirroringMode` (C6) | PORTED: fallback deleted (per process, not per display; blocked AirPlay for every display). Requests go on a serial queue (no main-thread blocking, order kept); a daemon that does not answer is logged only |
| 5 | `SBMirroredDisplayController _updateDisplayAssertion` (16.2 0x1c7466510 sets cloneMirroringMode 1, 16.0 0x1c5feb828 does not) | PORTED: TLS-marked hook on `SBDisplayAssertion updateWithPreferences:` |
| 6 | `_createDisplayAssertionPreferences` asks the policy (16.2) instead of building inline (16.0) | equivalent kept (set after %orig); policies return 2 / 1 as in 16.2 |

Safety of the BBD: build string 20A8372, image 0 is backboardd, prologue words of the 4 patched functions, subsystem start id 0x5b9168,
`dispatch_mach_msg_get_msg` resolvable, `BKTVOutController` present; otherwise it logs and installs nothing. updateClone is hooked
before the handler. Sender must be /SpringBoard (euid 0/501); trailer parsed like the stock stubs (audit token at trailer+0x14).
Kill switch: `Backport162.off.clonemirror` (daemon answers KERN_FAILURE, overrides are ignored).

## 2. Active display / focus (Group4Focus.x, G4B "arrange")

| item | state |
|------|-------|
| C1 / C4: `activeDisplayWindowScene` returning nil | PORTED: 16.2 `_validateSuggestedActiveWindowScene:usingMethodology:` (0x1c74bf960) maps a nil suggestion (0x1c74bfb0c `cbz`) AND invalidating/invalidated scenes to the embedded scene. The "keep keyboard-following until the first event" deviation and the G4B duplicate hook were removed; one hook (Group4Focus) implements 16.2 0x1c74bf1c4 (methodology 1 -> user interaction, 0 -> keyboard) |
| `methodology0` | stays opt-in (forces 0 = 16.0 keyboard following); default path = 16.2. Methodology read through `BP_G4_ActiveMethodology()` (`[SBExternalDisplaySettingsDomain rootSettings].activeDisplayTrackingMethodology`, default 1) |
| coordinator sniffers | PORTED literally: `_windowSceneForEvent:` has no touch-window fallback (0x1c795df4c); pointer touch-up only for phase Ended (0x1c795ec6c); pointer sniffer qualifies only for `[touch type] == 0` (0x1c795f0d4) |
| `sceneDidDisconnect:` of the external window scene delegate (`disconnect`, `discswitch`) | PORTED as a complete replacement of 16.0 0x1c5fed4f8 following 16.2 0x1c746826c: kfc suppression, invalidating, switcher coordinator ALWAYS (discswitch is default on), status bar assertion + system gesture manager invalidate, SBAlertItemsController / SBAppInteractionEventSourceManager, interaction coordinator, cover sheet controller, [super] at the 16.2 position (16.0 called it first), assertion/ws invalidate, delegate invalidated |
| kfc `windowSceneDidDisconnect:` (16.2 0x1c77c3b14) | CANNOT exactly: 16.2 calls the objc_direct `-removeKeyboardFocus...reason:` (0x1c77c3d3c) and `_reevaluatePolicy...`; closest equivalent: the ObjC-visible `removeKeyboardFocusFromScene:` (same underlying removal) and `updateKeyboardFocusDeferringRules` |
| `directhook` (16.2 suppression check at the top of `_reevaluatePolicyAndUpdateRulesIfNeeded`) | unchanged (prologue-verified MSHookFunction); `UNSURE` on-device |
| settings UI row for the methodology (`+[SBExternalDisplaySettings settingsControllerModule]` 0x1c74236a8) | CANNOT: PTSettings module only reachable in the internal Settings UI; the value is not persisted (default 1) |
| `SBDisplayArrangementItem` hierarchy (16.2: base class of SBExternalDisplayArrangementItem) | CANNOT re-parent the 16.0 class; runtime subclass kept (instances answer both isKindOfClass checks that 16.2 code in this tweak makes) |
| focuslock (`G4BFocusReq`) | PARTIAL: 16.2 does it in the objc_direct `_keyboardFocusPolicyForCurrentUIStateWithAppFocusTarget:` / `_applyDeferringRulesForPolicy:` (750 / 1070 instructions, no ObjC entry); wrapper over the public lock API kept. The nil-active-scene hazard (C4) is gone with the 16.2 validation above |

## 3. Presentation update, locked pointer, migration

| item | state |
|------|-------|
| presubset (C5, "falls back once") | PORTED from 16.2 0x1c77dcbe0 / block 0x1c77dce6c: compare + store `_lastPresentationUpdateDisplayConfiguration`; updates `boundPointerUIScenes + _currentScene` only when the configuration changed and the set is non-empty; otherwise completion. The `fell`/allScenes safety net is gone. Residual risk: the pointer-UI producer (`pointerClientController:sceneDidActivate:` hook) must fire, as in 16.2 |
| `SBNonInteractiveDisplayControllerPolicy displayController:updatePresentation...` (16.2 0x1c78e92ec, 192 instr, new ivars) | NOT PORTED: new state and element/assertion logic; 16.0 body stays (mirrored non-interactive displays only) |
| lockedptr2 (C8) | 16.2 bodies of the 14 `SBLockedPointerManager` methods read: add/remove/begin/end/prefers/didUpdateSettings are the 16.0 bodies behind an `_queue_isInvalidated` snapshot (already matched by the guards); `_notInvalidated_updateLockForLayoutState:` nil state now resolves to `[[windowScene layoutStateProvider] layoutState]` (0x1c76ba034). C8: the one-argument `didSelectContainer:` is hooked as well |
| migrate (`windowSceneDidDisconnect:` 16.0 0x1c62359ec / 16.2 0x1c76c85e0) | verified against 16.2: loop, takeScene:fromSceneManager:, picker role / unlocked mode modifiers match. FIXED: the transition builder block returned void, 16.2's (0x1c76c8b2c) returns YES. 16.2 has one more `removeObjectForKey:` for a 16.2-only dictionary (no 16.0 counterpart) |

## 4. Connect path (Group4Connect.m)

| item | state |
|------|-------|
| `autoext`, `mirrorsvc` were not installed ("ExtendedDisplayEnabler provides them") | PORTED/installed (default on, kill switches `Backport162.off.autoext` / `.mirrorsvc`); the policy notifications are produced by autoext when it owns the policy, G4B's passive producer steps aside (`BP4_PolicyPostsNotifications`) |
| nilock / discguard | PARTIAL, unchanged: 16.2 tests a BSAtomicSignal inside blocks that cannot be edited (entry points guarded instead); nilock only reacts to the cover sheet of another external display |

## 5. Education (edu / edunative, C10)

Default path = 16.2 session logic with the SpringBoardEducation remote alert; `edunative` stays opt-in; the automatic native fallback now logs
and only triggers when the remote-alert classes are missing (they exist in 16.0). UNSURE (cannot be checked here): whether the 16.0
SpringBoardEducation.app understands EducationType 1 (the 16.2 app has `SBEExternalDisplayContentViewController` and the hardware-requirements
protocol; the 16.0 app was not extracted).

## New switches
`autoext`, `mirrorsvc` (Group4Connect, off-file only); `discswitch` is now default on (already). No new opt-ins.
