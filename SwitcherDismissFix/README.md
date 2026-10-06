# SwitcherDismissFix 0.3.0 (wrapper port, experimental)

iPadOS 16.0, build 20A8372, rootless. Gives the app switcher a closing animation.

## The problem
Leaving the app switcher for the Home Screen (tap on empty space, or the automatic dismissal of an empty switcher after
`emptySwitcherDismissDelay` = 0.2 s) is a one-frame cut: the icons pop back and the wallpaper snaps. A trace of the
transitions (SwitcherTrace) showed every switcher -> home transition completes in 4-15 ms because SpringBoard creates
no transition modifier for it, while all other transitions take 0.6-1.0 s.

## The cause
The transition-modifier factories (`SBMainSwitcherRootSwitcherModifier` / `SBFullScreenFluidSwitcherRootSwitcherModifier`
`transitionModifierForMainTransitionEvent:`, also reached from `SBContinuousExposeRootSwitcherModifier`, which defers to
the Main one) have a switcher -> home case only for a valid peek (`SBHomeToGridSwitcherModifier`) or the iPhone deck
(`SBHomeToDeckSwitcherModifier`). Both are built `initWithTransitionID:direction:0 multitaskingModifier:...`
(direction 0 = toward home, 1 = toward the switcher). Everything else, including your Stage Manager root with Stage
Manager off, returns `nil`. 16.2 fixes this for the Stage Manager root with a new class,
`SBContinuousExposeToHomeSwitcherModifier`, which wraps `SBHomeToGridSwitcherModifier` with direction 0 and a copy of the
root's multitasking modifier (plus anchor-point / perspective / shadow adjustments).

## The fix
When the original returns `nil` for an animated, non-gesture switcher -> home transition, return
`SBHomeToGridSwitcherModifier initWithTransitionID:direction:0 multitaskingModifier:<copy of the root's multitasking
modifier>`: the inner modifier that 16.2 builds, without its wrapper's extra adjustments.

* **0.1.0** passed direction 1 (the wrong way round): windows flew off to the right and the cut remained.
* **0.2.0** passes direction 0 and, for the Stage Manager root, 16.2's copy of `multitaskingModifier`.

* **0.3.0** (branch `claude/switcher-dismiss-fix-ce-port`) ports the wrapper itself. 16.0 has no
  `SBContinuousExposeToHomeSwitcherModifier`, so the tweak creates `SDFContinuousExposeToHomeSwitcherModifier` at run
  time, a subclass of `SBTransitionSwitcherModifier`, with the behaviour decoded from the 16.2 binary:
  it adds the `SBHomeToGridSwitcherModifier` child (direction 0, copy of the Stage Manager modifier) and, when the
  transition is "effectively home" (`isPreparingLayout` with direction 1, or `isUpdatingLayout` with direction 0), it
  answers anchor point (0.5, 0.5), pin-to-space YES, perspective angle 0, accessory frame unchanged and accessory
  anchor (0.5, 0.5); header style, shadow style and backdrop blur come from the Stage Manager modifier, attached
  temporarily. Anything it cannot resolve makes it fall back to the 0.2.0 behaviour (the debug log says why).

Not verified on a device. `touch /var/jb/tmp/SwitcherDismissFix.plain` switches back to the 0.2.0 behaviour (no
wrapper) without reinstalling, for an A/B comparison.

## Files (under the jailbreak root, e.g. `/var/jb/tmp`)
* `SwitcherDismissFix.off`: kill switch. Create it and the tweak returns the original result (checked once a second).
* `SwitcherDismissFix.plain`: use the 0.2.0 behaviour (plain `SBHomeToGridSwitcherModifier`, no ported wrapper).
* `SwitcherDismissFix.debug`: create it to log each time the fix is applied to `SwitcherDismissFix.log` (rotated at
  256 KiB). Without it the tweak writes nothing.
