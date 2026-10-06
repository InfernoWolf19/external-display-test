# SwitcherDismissFix 0.1.0

iPadOS 16.0, build 20A8372, rootless. Gives the iPad grid app switcher a closing animation.

## The problem
Leaving the app switcher for the Home Screen (tap on empty space, or the automatic dismissal of an empty switcher after
`emptySwitcherDismissDelay` = 0.2 s) is a one-frame cut: the icons pop back and the wallpaper snaps. A trace of the
transitions (SwitcherTrace) showed every switcher -> home transition completes in 4-15 ms because SpringBoard creates
no transition modifier for it, while all other transitions take 0.6-1.0 s.

## The cause
`-[SBFullScreenFluidSwitcherRootSwitcherModifier transitionModifierForMainTransitionEvent:]` has a switcher -> home
case only for `effectiveSwitcherStyle == 1` (the iPhone deck: `SBHomeToDeckSwitcherModifier`, direction 1). The iPad's
style is 2 (grid) and falls through to `nil`. The opposite direction exists for the grid
(`SBHomeToGridSwitcherModifier`, direction 0, used when opening). The 16.2 code has the same gap.

## The fix
When the original returns `nil` for an animated, non-gesture switcher -> home transition on the grid style, return
`SBHomeToGridSwitcherModifier initWithTransitionID:direction:1 multitaskingModifier:[root _newMultitaskingModifier]`,
built exactly like the deck case. Everything else is left as SpringBoard returned it.

Not verified on a device: whether the grid modifier looks right when run in reverse. If it does not, switch it off
(below) and send a screen recording.

## Files (under the jailbreak root, e.g. `/var/jb/tmp`)
* `SwitcherDismissFix.off`: kill switch. Create it and the tweak returns the original result (checked once a second).
* `SwitcherDismissFix.debug`: create it to log each time the fix is applied to `SwitcherDismissFix.log` (rotated at
  256 KiB). Without it the tweak writes nothing.
