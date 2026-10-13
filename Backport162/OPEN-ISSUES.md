# Backport162 - open issues (single source of truth; updated every time something changes)

Last CI-green build: `b700f1c` (0.7.3); `130504d` building. Last build the user ran: `b700f1c`.

## Crashes / hangs
1. **Retain crash (use-after-free)** when tapping the left strip area and when moving the pointer onto the extended display. Same bug, two entry paths. Earlier `_newMultitaskingModifier` +1 fix did NOT cure it. STATUS: agent investigating from the user's backtraces (specs/AUDIT-RETAIN-CRASH-0.7.3.md when done).
2. SpringBoard watchdog hang (Dopamine "no successful checkins in 180 s"): one cause fixed (G4B dispatch_sync deadlock); not seen since, not proven gone. Verify in the long session.
3. Crash loop with Magic Keyboard / display connect (`UICommand` selector): FIXED in 07f50ba. Strip tap `edgeProtectOverride`: FIXED in 07f50ba.

## Behaviour bugs reported, not fixed yet
4. **Zoom first press sometimes does nothing.** Stale-read half fixed; the dropped first press is only a 1.6 s repeat workaround (root cause not found). Test on device; if the repeat also fails the log line `[g3c] zoom request had no effect` tells where.
5. **Add Another Window only works with one window open.** ROOT CAUSE FOUND (4f8667a): the G3C_Peek hook checked the chamois flag on SBMainWorkspace (does not respond), so it returned the stock result every time. 16.0 reads it from `[[self _switcherControllerForDisplayIdentity:[request displayIdentity]] isChamoisWindowingUIEnabled]` (0x1c5e23430..0x1c5e2351c). Fixed; verify on device (log line `[g3c] add window: stock layout state kept ...`).
6. **Going home with several windows**: windows land in a weird spot and hang ~0.5 s (also cmd+tab > Home Screen); GUARD "icon overlay response for an app layout without item container" fires. Same suspected root as 5.
7. Window flickers ~0.1 s after an app-to-app switch (log secondlog 20:35:59-20:36:00, a second non-animated layout pass).
8. PiP wobbles slightly when the app backgrounds: PiP animator source frame is computed against a centered container in some calls and top-left in others (offset = half the window size). G1D PiP frames.
9. Strip: taps/drags sometimes not registered (`receiveTouch -> no window` lines); needs a log of a failing tap.
10. Keyboard/dock: dock hidden assertion now at 16.2 level 9 (0c1bc38) - verify; window bottom under keyboard is app-side (UIKit).
11. Window flicker / glitch items from earlier lists (home-slide, fly-in) were fixed in 8fed7be - verify with the test list.

## Extended display
12. Gap list vs 16.2 (agent running, specs/GAPS-EXTDISPLAY-0.7.4.md): not ported / approximated: SBNonInteractiveDisplayControllerPolicy presentation, real focus-lock policy, nilock/discguard guards, settings methodology persistence, cross-display drag end event, BBD daemon (never run).
13. Empty switcher on the extended display (user: status bar hides, no blur/animation, only a click dismisses): 16.0 and 16.2 have the same auto-dismiss code (SBHomeToSwitcher/ForcePress/HomeGestureToSwitcher modifiers + SBDismissForEmptySwitcherSwitcherEventResponse), so the cause is which path runs on the external display. 4f8667a adds `exttrace:` debug lines for those modifiers and `toggleMainSwitcherNoninteractively`; needs a debug log of the empty switcher on the external display.
14b. **Strip glitch on rotation with several windows** (user video): cards were torn out of the hierarchy during the rotation and popped back tiny/blurred. 16.2 overrides `requireStripContentsInViewHierarchy` = YES in SBTransitionSwitcherModifier (0x1c746a124) and SBGestureSwitcherModifier (0x1c7828710); not ported before. Ported in 4f8667a (G2.x group G2StripRequire); verify on device.

## Not ported / approximations still standing (the user wants these done)
14. Real 16.2 focus-lock policy (two large direct methods).
15. Zoom un-zoom is a reconstruction (16.2 has no un-zoom in the Zoom block).
16. Privacy preflight gate (not portable on 16.0: PrivacyDisclosureCore missing).
17. BBD tweak (backboardd clone mirroring) rewritten but never installed.

## Process rules from the user
- Everything default ON; never gate or disable features; no auto-disable safeguards.
- No "small steps" builds; target is bug free; every build gets the audit + test list.
- Commit and push often; keep this file up to date.

## Added in 0.7.3 (device-unverified)
- Add Another Window: the app picked while the stage peeks now JOINS the stage (16.2 end-of-peek branch, `g3c_endpeek`, specs/ADDWINDOW-PICK-0.7.4.md). Log lines `[g3c] endpeek: ...`. Not ported from that branch: request == previous stage / nothing real / Home while peeking (stock code runs), shift-click insertion policy, SBMainWorkspaceLayoutStateContingencyPlan, chamois-aware recents lookup.
- External display: empty switcher auto-dismiss now answered after the transition modifier is gone (`g1d_emptydismiss`); closing the last card on the external display does not dismiss (log shows no removal events; `g1c: app switcher removal event` lines added to find out why).
- External display has no switcher blur: the blur call goes to a shared singleton for the main display's home screen; identical in 16.0 and 16.2.

## Added after 0.7.3 first build (device-unverified)
- External display could not move/resize windows or drag from the strip: the manager of that display never answered `-shouldSystemGestureReceiveTouchWithLocation:` (new in 16.2 on SBSystemGestureManager). Ported (`g1d_sgmreceive`), also ANDs the PiP-content check into the Main flavour.
- Add-window crash 3->4 windows: the 16.0 routing modifier maps a child's last filtered layout back with indexOfObject:; the merged stage layout mixed peeked and other items so neither half was in the list. Layouts mixing peeked items now route whole to the content modifier (G1B filtering). `g1d_routingfresh` was tried and removed (did not help: log b12000a1).
- Empty switcher on the external display auto-dismisses (`g1d_emptydismiss`, confirmed in log 5081160a). Two-finger trackpad swipe-up to close a card on the external display: card kill scroll view trace added (`exttrace: card ...`), result pending.
- Pointer stuck as resize arrows on the external display: not investigated (likely the same refused gestures).

## Added after b700f1c
- Disconnecting the extended display with a window on it: crash fixed (`g1d_snapguard`, 16.2 snapshot cache guard). Confirmed on device in log 76c96b37 (guard line logged, no crash, windows migrated to the embedded scene).
- Windows bunched while dragging + resize grabber vanishing on the main display after Add Another Window (log 43f88b77): a stale `SBContinuousExposePeekSwitcherModifier` stayed on the root after the pick merged the window into the stage (`g1b: filtering: layout mixes peeked and other items` on every layout pass). Fixed in 130504d: root `handleTransitionEvent:` retires the peek child at phase 3 when the target peek configuration is invalid (log line `GLITCH peek child retired ...`). Device-unverified.
- Closing the last/only card on the extended display (two-finger swipe up): ROOT CAUSE (specs/KILL-EXTDISPLAY-0.7.4.md): the per-item removal action block of `_switcherModelRemovalResultsForRequest:` sends `removeLayoutRole:` to the MAIN display's content controller in 16.0 (16.2: the owner of the layout), so the external controller never dispatches the type-15 removal events. Ported as `g1d_removalowner` (G1D.x), device-unverified. Expect log lines `g1d: removal of ... runs on its own display's switcher`, `g1b: removal event (type 15)`.
- Disconnect with a window on the extended display: the scene migrates to the embedded scene manager and the layout enters the strip, but the user reports the window does NOT appear on the iPad display (it is not brought on stage; log 76c96b37 shows home screen mode 1 afterwards). Behaviour of 16.2 after disconnect still to be analysed.
- OPEN: pointer stuck as resize arrows on the extended display (uninvestigated, maybe fixed by `g1d_sgmreceive`).
