# Backport162 - open issues (single source of truth; updated every time something changes)

Last CI-green build the user ran: `0c1bc38` (0.7.2). It still has the retain crash below.

## Crashes / hangs
1. **Retain crash (use-after-free)** when tapping the left strip area and when moving the pointer onto the extended display. Same bug, two entry paths. Earlier `_newMultitaskingModifier` +1 fix did NOT cure it. STATUS: agent investigating from the user's backtraces (specs/AUDIT-RETAIN-CRASH-0.7.3.md when done).
2. SpringBoard watchdog hang (Dopamine "no successful checkins in 180 s"): one cause fixed (G4B dispatch_sync deadlock); not seen since, not proven gone. Verify in the long session.
3. Crash loop with Magic Keyboard / display connect (`UICommand` selector): FIXED in 07f50ba. Strip tap `edgeProtectOverride`: FIXED in 07f50ba.

## Behaviour bugs reported, not fixed yet
4. **Zoom first press sometimes does nothing.** Stale-read half fixed; the dropped first press is only a 1.6 s repeat workaround (root cause not found). Test on device; if the repeat also fails the log line `[g3c] zoom request had no effect` tells where.
5. **Add Another Window only works with one window open.** Multi-window stages are `configuration = half/half` (16.0 split shape) instead of 16.2 Stage Manager shape. STATUS: agent (same root as 6).
6. **Going home with several windows**: windows land in a weird spot and hang ~0.5 s (also cmd+tab > Home Screen); GUARD "icon overlay response for an app layout without item container" fires. Same suspected root as 5.
7. Window flickers ~0.1 s after an app-to-app switch (log secondlog 20:35:59-20:36:00, a second non-animated layout pass).
8. PiP wobbles slightly when the app backgrounds: PiP animator source frame is computed against a centered container in some calls and top-left in others (offset = half the window size). G1D PiP frames.
9. Strip: taps/drags sometimes not registered (`receiveTouch -> no window` lines); needs a log of a failing tap.
10. Keyboard/dock: dock hidden assertion now at 16.2 level 9 (0c1bc38) - verify; window bottom under keyboard is app-side (UIKit).
11. Window flicker / glitch items from earlier lists (home-slide, fly-in) were fixed in 8fed7be - verify with the test list.

## Extended display
12. Gap list vs 16.2 (agent running, specs/GAPS-EXTDISPLAY-0.7.4.md): not ported / approximated: SBNonInteractiveDisplayControllerPolicy presentation, real focus-lock policy, nilock/discguard guards, settings methodology persistence, cross-display drag end event, BBD daemon (never run).
13. Empty switcher on the extended display: 16.2 auto-dismisses after 0.3 s; ours does not on the user's device. Needs a debug log of opening the empty switcher on the external display.

## Not ported / approximations still standing (the user wants these done)
14. Real 16.2 focus-lock policy (two large direct methods).
15. Zoom un-zoom is a reconstruction (16.2 has no un-zoom in the Zoom block).
16. Privacy preflight gate (not portable on 16.0: PrivacyDisclosureCore missing).
17. BBD tweak (backboardd clone mirroring) rewritten but never installed.

## Process rules from the user
- Everything default ON; never gate or disable features; no auto-disable safeguards.
- No "small steps" builds; target is bug free; every build gets the audit + test list.
- Commit and push often; keep this file up to date.
