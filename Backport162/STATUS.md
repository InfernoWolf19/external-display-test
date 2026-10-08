# Backport162 status (read this first when resuming)

Goal (user's instruction): port iPadOS 16.2 (20C65) Stage Manager and extended display behaviour, "fully fleshed", to iPadOS 16.0 (20A8372), rootless Dopamine, M2 iPad Pro. Existing code is updated and new classes are added; the user wants it all, tested in builds after each group.

User rules: separate branches per project (this one is `claude/backport162`), no PR unless asked, never force-push, logging opt-in only, kill switch + build guard on every build, commit trailers as in git log, no model identifier in commits. The user tests on the device and sends logs.

## Resume plan (written for a session that may be cut off by the user's usage limit)

State at 0.5.1: group 4 is DONE and built (artifact `Backport162-a7c8fe3`, CI run 37714563888); the user is testing it on the device. Everything is default-on; kill switches `<jbroot>/tmp/Backport162.off[.<feature>]`.
In flight when this note was written: three read-and-spec agents writing `specs/group1b-modifiers.{md,hooks.m}`, `specs/group2-layout-data.{md,hooks.m}`, `specs/group3-plumbing.{md,hooks.m}` incrementally. On resume: `git status` (uncommitted agent output), commit what exists, then see which of those specs are complete (the .md ends with a summary section when finished; otherwise re-launch an agent for the missing classes only).
Then implement groups 1-3 TOGETHER (they depend on each other; one build): order = data/layout layer (group 2 A: layout cache + validity token, overlapping model additions, SBAppLayout additions, context-provider selectors) -> new modifier classes (strip, filtering, override identifiers, pulse, events/responses) -> reworked full-screen / app-switcher / root factories -> transitions, peek, drag-drop -> plumbing (group 3). New classes are created at run time with objc_allocateClassPair (see SwitcherDismissFix 0.3.0 on branch claude/switcher-dismiss-fix-ce-port for the pattern). Ivars cannot be added to existing classes: use associated objects or a runtime subclass. Keep per-feature switches + build guard + opt-in logging; add the new features to `BP.h` (enum), `Tweak.x` (names) and README. After the Stage Manager port ships, tell the user to remove SwitcherDismissFix (it ports SBContinuousExposeToHomeSwitcherModifier, which the backport will include).
Do not spend usage on re-reading what the specs already contain.

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
