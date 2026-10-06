# SwitcherDismissFix 0.2.0

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

Not verified on a device. If the windows still look wrong, the missing piece is the wrapper's adjustments; send a
screen recording and the debug log.

## Files (under the jailbreak root, e.g. `/var/jb/tmp`)
* `SwitcherDismissFix.off`: kill switch. Create it and the tweak returns the original result (checked once a second).
* `SwitcherDismissFix.debug`: create it to log each time the fix is applied to `SwitcherDismissFix.log` (rotated at
  256 KiB). Without it the tweak writes nothing.
