# Backport162 0.6.0 adversarial review, area C (G3.x, G3B.x, G4B.x, Backport162BBD)

Target: iPadOS 16.0 (20A8372) SpringBoard / backboardd, arm64e. Reference 16.2 (20C65). Nothing was run on a device; every
claim is a reading of the binaries unless marked UNVERIFIED. Addresses are unslid cache vmaddrs (SpringBoard) or file
vmaddrs of `bbd/backboardd`. Source not edited. Method: all hooks of the three files were extracted by script and checked
against `sb160n_objc.txt` (class present, selector present, arg count/kinds); the high-risk ones were disassembled.

Severity: CRASH / WRONG-BEHAVIOUR / MINOR.

## Ranked findings

| # | sev | where | one line |
|---|-----|-------|----------|
| C1 | WRONG-BEHAVIOUR (severe, default ON, also single display) | G4B.x:1743-1753 (arrange) | `SBWindowSceneManager -activeDisplayWindowScene` returns nil whenever Group4Focus' coordinator has no scene yet (boot until first touch/pointer move, after unplug of the active display, any key-only use). Stock never returns nil. |
| C2 | WRONG-BEHAVIOUR (dead feature, high confidence) | Backport162BBD/Tweak.x:259-262, 317 | the MIG hook on `0x1000997f4` is never called: backboardd serves the port with `dispatch_mach_mig_demux`, which range-checks `subsystem->start/end` and never calls `->server`. Ids 0x5b9fa0/1 are destroyed unanswered. |
| C3 | WRONG-BEHAVIOUR (regression, high confidence on the code defect) | G3.x:261-268 (g3snapshot) | `didMoveToWindow` calls `_updateSceneHostingInfoForSnapshottingWithView:` also when the view LEFT its window, which writes contextId 0 into the scene's snapshot hosting info. 16.2 returns nil for that case. |
| C4 | WRONG-BEHAVIOUR (multi display) | G4B.x:1633 (focuslock) | `active` (user-interaction scene) is nil as in C1, so SpringBoard focus locks on the iPad are deferred while an app on the monitor has keyboard focus. |
| C5 | WRONG-BEHAVIOUR risk (UNVERIFIED) | G4B.x:1024-1060 (presubset) | stock updates `allScenes`; replacement updates only pointer-UI scenes + `_currentScene`. |
| C6 | WRONG-BEHAVIOUR (clone fallback) | G4B.x:287-313 | with stock/no-working BBD the legacy fallback sets the GLOBAL BKS mirroring mode 2 (sticky, also blocks AirPlay mirroring); SpringBoard main thread may block up to 500 ms per message. |
| C7 | CRASH (latent, low probability) | G3B.x:657, 665 (pip) | provider keeps an `OBJC_ASSOCIATION_ASSIGN` pointer to the per-scene PiP manager. Use after free if the scene dies first. |
| C8 | MINOR | G4B.x:1437 | lockedptr2 unsuppress only works through G2B's added `didSelectContainer:modifierFlags:` (16.0 has only the 1-arg form), dead when `g2b`/`g2bkeys` is off. |
| C9 | MINOR | G3B.x:1641 | `_gridForBounds:` hook does `class_getInstanceVariable` before the cheap TLS test on a layout hot path. |
| C10 | MINOR/UNVERIFIED | G4B edu | remote alert is sent EducationType 1 (16.0 sends 0); the 16.0 service may not know it. |

PASS list (checklist items with no finding) is at the end of each section below.

---------------------------------------------------------------------------------------------------

## C1  arrange: `activeDisplayWindowScene` can return nil  (WRONG-BEHAVIOUR, severe)

File: G4B.x:1743-1753 (`%hook SBWindowSceneManager`), interplay with Group4Focus.x:563-586.

Scenario (default config, no switch files):
1. `BP_G4_Setup` always runs `%init(G4)`, so Group4Focus adds `%new activeDisplayWindowSceneFollowingKeyboard/UserInteraction` to `SBWindowSceneManager` (Group4Focus.x:577-585). `respondsToSelector:` in the G4B hook is therefore TRUE.
2. `G4B_Methodology()` returns 1 (the `%new` getter defaults to 1, `methodology0` is opt-in), so the hook returns `[self activeDisplayWindowSceneFollowingUserInteraction]` = `BP_ValidateActiveScene(self, [coordinator activeWindowScene], 1)`.
3. `coordinator.activeWindowScene` (`_activeDisplayWS`, a weak ivar) is set only by a qualifying touch/pointer-move event (Group4Focus.x:331-364) and is CLEARED when that scene disconnects (Group4Focus.x:271-273). Key events return early in `handleSendEvent:` (touches.count == 0). Until the first event it is nil, and `BP_ValidateActiveScene(nil)` returns nil.
4. Group4Focus' own `activeDisplayWindowScene` hook deliberately keeps keyboard following until the first event ("deviation", Group4Focus.x:569-572). G4B is installed later, so it is the OUTER hook and bypasses it completely; `%orig` is reached only when `arrange` is off.

Stock 16.0 `-[SBWindowSceneManager activeDisplayWindowScene]` (0x1c6043bec) is `kfc.windowSceneWithFocus ?: _embeddedDisplayWindowScene`, never nil (`cbnz x20 ... bl _embeddedDisplayWindowScene` at 0x1c6043c38-0x1c6043c40).
Consumers (callers16.0 script, ~60 sites): `SBHomeHardwareButtonActions performSinglePressUpActionsWithSourceType:` (0x1c61451f0), `SBLockHardwareButtonActions performInitialButtonDownActions` (0x1c5eab430, the top button), `SpringBoard _handle*KeyShortcut:` (0x1c5ee556c...), `SBMainWorkspace _targetWindowSceneForApplication:...` (0x1c5f0459c), `SBAlertItemPresenterWindowSceneResolver` (0x1c60450c4), `SBTransientOverlayPresentationManager` (0x1c616c91c, 0x1c616d7d0), `SBInCallPresentationManager` (0x1c61da784), `SpringBoard _initializeDeferredItems` block (0x1c5edce74). After a respring, pressing the top button or a key shortcut before touching the screen, or unplugging the monitor that was last touched, sends these to a nil scene (button actions no-op, alerts/overlays/app launch target nil).
Also with `Backport162.off.activedisplay` the coordinator is never fed, so `ui` is nil permanently.
Confidence 90% (all steps read in the source; nil result not observed on a device).

Patch (keeps the 16.2 selection when it has an answer, otherwise the existing chain = G4F hook = stock):
```diff
--- a/Backport162/G4B.x
+++ b/Backport162/G4B.x
@@ %hook SBWindowSceneManager
-        long long m = G4B_Methodology();
-        if (m == 0) return G4B_Obj(self, kb);
-        if (m == 1) return G4B_Obj(self, ui);
-        BP_Log(@"arrange: undefined methodology %@", G4B_StringForMethodology(m));
-        return nil;
+        long long m = G4B_Methodology();
+        id r = nil;
+        if (m == 0) r = G4B_Obj(self, kb);
+        else if (m == 1) r = G4B_Obj(self, ui);
+        else BP_Log(@"arrange: undefined methodology %@", G4B_StringForMethodology(m));
+        if (r) return r;          // never return nil: stock falls back to the embedded scene
     }
     return %orig;
```
Also: the two `NSSelectorFromString` calls run before `G4B_On` on every call (`activeDisplayWindowScene` is a hot getter); move them under a `static` once.

---------------------------------------------------------------------------------------------------

## C2  Backport162BBD: the MIG hook never fires  (WRONG-BEHAVIOUR, feature dead)

File: Backport162BBD/Tweak.x:259-262 (`hk_lookup`), :317 (`MSHookFunction(... kVM_lookup ...)`).

Evidence (backboardd 16.0):
* The display-services port is created at 0x10000e8f4: strings "BKDisplayServices MiG Server" / "com.apple.backboard.display.services", subsystem `0x1000e56a8` passed to helper 0x100026c30.
* 0x100026c30 builds a `dispatch_mach` channel (`bl 0x10009acc0` = `_dispatch_mach_create_f`), handler block at 0x100026d14. For event 2 (message received) it calls `bl 0x10009acd0` = `_dispatch_mach_mig_demux(NULL, &subsystem, 1, dmsg)` (0x100026d58); if it returns false: `_dispatch_mach_msg_get_msg` + `bl 0x10009aea0` = `_mach_msg_destroy` (0x100026d60-0x100026d6c).
* libdispatch `dispatch_mach_mig_demux` (16.0 cache 0x18e12c458) selects the routine by range: `ldr w9,[x8,#8]` (start), `ldr w10,[x8,#0xc]` (end), `msgid - start >= 0 && end > msgid`, then `routine = [x8 + idx*0x28 + 0x28]` (0x18e12c4ac-0x18e12c514). It never calls `subsystem->server` (the field at +0, whose value is the auth pointer to 0x1000997f4, fixup at 0x1000e56a8).
* Subsystem header (read from the file): start 6001000 (0x5b9168), end 6001027 (0x5b9183). Ids 0x5b9fa0/1 are out of range, so the demux returns false without ever calling the hooked lookup.
Result: the tweak's `BPD_Routine` is dead code. `updateClone` is hooked but no override can ever be installed, so it is a pass-through. The SpringBoard side always takes the fallback (see C6).

Verified OK in the same tweak: all four prologue word tables match the binary (checked byte for byte: 0x1000997f4, 0x10004c930, 0x10004cffc, 0x10004ce50); build string check; Filter `Executables = ("backboardd")`; plist name matches `TWEAK_NAME`; every failure path in `%ctor` returns with only a log line, so a missing symbol/class cannot loop the boot. The lookup is a 12 instruction leaf, the patched span (<= 16 bytes = `ldr; mov; movk; add`) is position independent. Whether Dopamine's TweakLoader injects into backboardd for this plist cannot be checked here (UNVERIFIED; the plist form is the standard one).

Fix sketch (hook the demux instead of the table; the demux is the thing that sends the reply, so the hook must send it):
```diff
-        MSHookFunction(BPD_FnAt(kVM_lookup), (void *)hk_lookup, (void **)&orig_lookup);
+        void *dm = dlsym(RTLD_DEFAULT, "dispatch_mach_mig_demux");
+        MSHookFunction(dm, (void *)hk_demux, (void **)&orig_demux);
+// bool hk_demux(void *ctx, const struct mig_subsystem *const subs[], size_t n, dispatch_mach_msg_t dmsg):
+//   hdr = dispatch_mach_msg_get_msg(dmsg, NULL);
+//   if (n == 1 && (const char *)subs[0] == slide + 0x1000e56a8 && (hdr->msgh_id == SET || == REMOVE)) {
+//       BPD_Routine(hdr, &reply); mach_msg(&reply.Head, MACH_SEND_MSG|MACH_SEND_TIMEOUT, size, 0, 0, 0, 0); return true; }
+//   return orig_demux(ctx, subs, n, dmsg);
```
(the audit trailer lies behind the message inside the dmsg buffer; `BPD_Routine` already computes it that way). Alternative: drop the BBD tweak and rely on the legacy call.

What stock backboardd does with the unknown id (answers checklist item 3): `mach_msg_destroy`, no reply, no log, no hang. The send-once reply right is destroyed, so the kernel posts a `MACH_NOTIFY_SEND_ONCE` (id 0x46) to the sender's reply port; `G4B_SendCloneMsg` receives it immediately (not a 500 ms timeout), sees `msgh_id != req+100`, returns 0, sets `gG4BDaemon = 0` forever and falls to the legacy call. A bad message cannot crash backboardd.

---------------------------------------------------------------------------------------------------

## C3  g3snapshot: hosting info rewritten when the scene view leaves its window  (WRONG-BEHAVIOUR)

File: G3.x:261-268 (`-[SBDeviceApplicationSceneView didMoveToWindow]`).

16.0 `-[SBDeviceApplicationSceneHandle _updateSceneHostingInfoForSnapshottingWithView:]` (0x1c6226eb4): if the scene is valid, reads `[view _window]._contextId` (nil window gives 0) and `CALayerGetRenderId(view.layer)` and calls `updateUISettingsWithBlock:` to store both (0x1c6226ef8-0x1c6226f80). No window check.
16.2 `-[SBDeviceApplicationSceneHandle _sceneHostingInfoForSnapshottingAssertionWithView:]` (0x1c76b7acc) starts `cbz x19 (view) -> return nil; cbz x20 (view.window) -> return nil` (0x1c76b7b08-0x1c76b7b0c, return path 0x1c76b7c2c); the new assertion then replaces the old one and the old one's invalidation restores the previous info.
G3.x calls the 16.0 method unconditionally. `didMoveToWindow` also fires on removal (switcher dismissal, app close, layout change, display switch), where `host._window` is nil: the scene settings receive `hostContextIdentifierForSnapshotting = 0` (and a scene settings update is sent to the app on every window move). Snapshots taken after the view is gone may use context 0.
Confidence 95% on the unguarded call, 65% on user-visible harm (blank/wrong snapshots).

Patch:
```diff
-    id host = BP_G3_GetWeak(self, &kBPG3HostView);
+    id host = BP_G3_GetWeak(self, &kBPG3HostView);
+    if (![self window] || ![host window]) return;     // 16.2: no hosting info change without a window
```

PASS in group 3: handle accessors (store-backed, `_sceneDataStoreCreatingIfNecessary:` exists), orientation selectors (signatures match, pure pass-through with stored value 0), `_didUpdateSettingsWithDiff:previousSettings:` (`_isEffectivelyForeground` is `_Bool` @0xb1), `windowScene:didUpdateCoordinateSpace:...` as `%new` (no 16.0 SB class implements it, only the UIKit protocol), canvas poster, decorated VC hooks (all selectors exist in 16.0), embedded controller hooks.

---------------------------------------------------------------------------------------------------

## C4  focuslock: iPad locks deferred while `active` is nil  (WRONG-BEHAVIOUR, multi display)

File: G4B.x:1626-1633.
`want = (!appScene && !active) || (sc == appScene || sc == active)`. `active` comes from `activeDisplayWindowSceneFollowingUserInteraction`, which exists (Group4Focus %new) but is nil until the first touch/pointer event, after the active display is unplugged, and always with `Backport162.off.activedisplay`. With an app focused on the monitor (`appScene` = external) every SpringBoard lock request on the iPad scene (Spotlight, alerts, Control Center) is held back and never reaches `lockFocusToSpringBoardWindowScene:` (stock 16.0 always honours it: single `_springBoardFocusLockWindowScene`). Single display is unaffected (appScene or active equals embedded).
Patch: `id active = ui ? ... : nil; if (!active) active = [wsm activeDisplayWindowScene];` and treat "cannot determine" as qualifying:
```diff
-    BOOL want = (!appScene && !active) || (sc && (sc == appScene || sc == active));
+    BOOL want = (!appScene) || (!active) || (sc && (sc == appScene || sc == active));
```
Checked and fine: token is only ever sent `invalidate`; observer protocol (`externalSceneDidAcquireFocus:` required, `didUpdateWindowSceneWithFocusFrom:to:` optional) is implemented; `_externalSceneWithFocus` is an ivar; `updateKeyboardFocusDeferringRules` is an objc_direct stub (`b +4`) so that hook misses internal callers, harmless because the observer callbacks also trigger reconcile.

## C5  presubset replaces `allScenes` by a subset  (WRONG-BEHAVIOUR risk, UNVERIFIED, 35%)

File: G4B.x:1024-1060. 16.0 `-[SBSystemShellExtendedDisplayControllerPolicy displayController:updatePresentationWithSceneManager:displayConfiguration:completion:]` (0x1c6339470) enumerates `[manager allScenes]` and per scene (block 0x1c63395cc) does `mutableCopy; setDisplayConfiguration:; setFrame:[cfg bounds]; updateSettings:withTransitionContext:completion:` with a counting completion. The hook does the identical per-scene work but only for `boundPointerUIScenes ∪ _currentScene`; hosted app scenes on the monitor no longer get a new display configuration/frame when the configuration changes (resolution, scale, overscan). The static `fell` safety net (G4B.x:1036-1042) answers `completion()` without updating on every empty case after the first. Nothing found that updates app scenes elsewhere in 16.0. Safer default: union with `allScenes` (or keep opt-in).
```diff
-    if (bound) [scenes unionSet:bound];
+    if (bound) [scenes unionSet:bound];
+    NSSet *all0 = [sm respondsToSelector:@selector(allScenes)] ? G4B_Obj(sm, @selector(allScenes)) : nil;
+    if (all0) [scenes unionSet:all0];      // keep the 16.0 scope
```

## C6  clone-mirroring transport and fallback  (WRONG-BEHAVIOUR, medium)

File: G4B.x:249-313.
* With C2 the primary transport can never succeed; on every run the first message returns a send-once notification and `gG4BDaemon` is pinned to 0.
* Fallback `BKSDisplayServicesSetCloneMirroringMode(2)` is the GLOBAL 16.0 call (complex message, one owner process, 0x10004ecb4: "Ignoring request ... owned by vpid" for other owners). While an extended display exists, mediaserverd's AirPlay mirroring request (mode 1) is ignored and the daemon removes clones for EVERY TVOut/Wireless display. Whether SpringBoard holds `com.apple.backboardd.virtualDisplay` is unknown; without it the call is ignored (no effect, no crash).
* `G4B_Transport` is called from main-thread callbacks (`assertionCoordinator:activeAssertionPreferencesHaveChanged:`), under `@synchronized`, with a 500 ms send+receive timeout: a wedged backboardd stalls the main thread per request.
Recommendation: do not install `clonemirror` unless the daemon half works, or make the legacy fallback opt-in:
```diff
-    G4B_LegacyRecompute();
+    if (G4B_OptIn("clonelegacy")) G4B_LegacyRecompute();
```
Checked and fine: `assertionCoordinator:activeAssertionPreferencesHaveChanged:` is called with a dictionary copy (display identity -> prefs; 0x1c633b1e8-0x1c633b268), `_createDisplayAssertionPreferences`, `copyWithZone:`/`isEqual:`/`hash` hooks consistent, tokens invalidated on dealloc, request FIFO semantics.
