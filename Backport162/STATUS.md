# Backport162 status (read this first when resuming)

Goal (user's instruction): port iPadOS 16.2 (20C65) Stage Manager and extended display behaviour, "fully fleshed", to iPadOS 16.0 (20A8372), rootless Dopamine, M2 iPad Pro. Existing code is updated and new classes are added; the user wants it all, tested in builds after each group.

User rules: separate branches per project (this one is `claude/backport162`), no PR unless asked, never force-push, logging opt-in only, kill switch + build guard on every build, commit trailers as in git log, no model identifier in commits. The user tests on the device and sends logs.

## Groups
1. Stage Manager core logic (new strip/peek/filtering/drag-drop/full-screen-to-strip modifiers, reworked full-screen and app-switcher modifiers). Specs written: `specs/SBStripContinuousExposeSwitcherModifier.md`, `specs/SBFullScreenContinuousExposeSwitcherModifier.md`. No code yet.
2. Switcher view + layout data (SBFluidSwitcherViewController 60 changed methods, item containers, layout attributes, Chamois settings/overlapping model). Not read yet.
3. Window/scene/input plumbing (scene handles, app layouts, hosted keyboard, SBMultiDisplayUserInteractionCoordinator, pointer events). Not read yet. Groups 1-3 depend on each other and ship together.
4. External display lifecycle. In progress.

## Group 4 progress
Done in `Tweak.x` 0.2.0 (CI green, untested on device): `scale` (per-axis clamp of logical scale), `autohost` (keyboard arbiter scene), `blank` (real display blanking + mouse-click wake instead of a black blanking window; gesture type 0x42 on 16.0).
Findings: `specs/group4-external-display-notes.md`.
Two agents were reading the rest (disconnect/focus/pointer lock/multi-display coordinator; connect path/service/suspend-under-lock/education/mirroring) and writing `specs/group4-*.md` plus `specs/group4-*.hooks.m` drafts. Integrate the portable parts into `Tweak.x` as new features (add to the `F_*` enum and README), build, then ask the user to test.

## Facts worth keeping
* SwitcherDismissFix 0.3.0 already ports one 16.2 Stage Manager class (SBContinuousExposeToHomeSwitcherModifier); remove it once the Stage Manager group ships.
* Tools and how to rebuild the caches: `tools/README.md`. Worklist of changed methods: `WORKLIST.md`. Class-level delta: `CLASS_DELTA_NAMES.txt`.
* CI: `.github/workflows/build-backport162.yml`, artifact `Backport162-<short sha>`.
