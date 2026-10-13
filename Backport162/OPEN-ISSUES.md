# Backport162 - open issues (single source of truth; updated every time something changes)

Last CI-green build: `4f8667a` (0.7.3). Last build the user ran: `c83357c` (retain-crash fix; add-window still failed there).

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
