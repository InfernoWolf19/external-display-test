# Backport162 status (read this first when resuming)

Goal (user's instruction): port iPadOS 16.2 (20C65) Stage Manager and extended display behaviour, "fully fleshed", to iPadOS 16.0 (20A8372), rootless Dopamine, M2 iPad Pro. Existing code is updated and new classes are added; the user wants it all, tested in builds after each group.

User rules: separate branches per project (this one is `claude/backport162`), no PR unless asked, never force-push, logging opt-in only, kill switch + build guard on every build, commit trailers as in git log, no model identifier in commits. The user tests on the device and sends logs.

## Groups
1. Stage Manager core logic (new strip/peek/filtering/drag-drop/full-screen-to-strip modifiers, reworked full-screen and app-switcher modifiers). Specs written: `specs/SBStripContinuousExposeSwitcherModifier.md`, `specs/SBFullScreenContinuousExposeSwitcherModifier.md`. No code yet.
2. Switcher view + layout data (SBFluidSwitcherViewController 60 changed methods, item containers, layout attributes, Chamois settings/overlapping model). Not read yet.
3. Window/scene/input plumbing (scene handles, app layouts, hosted keyboard, SBMultiDisplayUserInteractionCoordinator, pointer events). Not read yet. Groups 1-3 depend on each other and ship together.
4. External display lifecycle. In progress.

## Group 4 progress (all agent work integrated)
Package 0.4.0 (CI run for commit "Backport162 0.4.0"): `Tweak.x` (scale, autohost, blank), `Group4Connect.m` (provmap on by default; nilock/discguard/covernote opt-in), `Group4Focus.x` (disconnect on by default; activedisplay/gesturegate/lockedptr/discswitch/directhook opt-in). Shared enum/helpers in `BP.h`. Opt-in = file `<jbroot>/tmp/Backport162.on.<name>`.
Not installed on purpose: autoext + mirrorsvc (ExtendedDisplayEnabler 0.2.2 already does both). Not portable: clone-mirroring, education rework, per-scene SBLockedPointerManager, window migration on unplug, per-display focus locks (see specs/group4-*.md).
Nothing in group 4 has been run on a device yet. Next: tell the user group 4 is done and give them the 0.4.0 artifact; they test; fix issues; then start groups 1-3 (specs for group 1 exist).

## Facts worth keeping
* SwitcherDismissFix 0.3.0 already ports one 16.2 Stage Manager class (SBContinuousExposeToHomeSwitcherModifier); remove it once the Stage Manager group ships.
* Tools and how to rebuild the caches: `tools/README.md`. Worklist of changed methods: `WORKLIST.md`. Class-level delta: `CLASS_DELTA_NAMES.txt`.
* CI: `.github/workflows/build-backport162.yml`, artifact `Backport162-<short sha>`.
