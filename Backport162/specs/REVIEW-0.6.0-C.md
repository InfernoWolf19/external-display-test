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
