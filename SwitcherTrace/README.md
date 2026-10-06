# SwitcherTrace 0.1.0 (diagnostic)

iPadOS 16.0, build 20A8372, rootless. Traces how SpringBoard's app switcher opens and closes, to find out why leaving the
switcher is a one-frame cut (no animation) both after "swipe up and hold with nothing running" and after "tap empty
space". It changes nothing: every hook calls the original method and only records.

## Use
1. Install, respring.
2. Switch tracing on: `touch /var/jb/tmp/SwitcherTrace.debug` (use your jailbreak root; with Dopamine `jbroot /tmp`).
3. Do the gesture once (swipe up and hold with nothing running, then release). Wait a couple of seconds. Then, with
   three apps open, open the switcher and tap empty space.
4. Send `/var/jb/tmp/SwitcherTrace.log` (and `.log.1` if it exists).
5. Switch tracing off: `rm /var/jb/tmp/SwitcherTrace.debug`. Without that file the tweak only does one `access()` per
   second from whichever hook fires.

## What the log lines mean
* `root.handleTransitionEvent > / <`: a transition event entering the switcher's root modifier (phase, `animated`,
  from/to environment mode) and the response that came back.
* `root.handleGestureEvent`: gesture phase changes only.
* `grid.handleTapOutsideToDismissEvent`, `viewController._handleDismissTapGesture`: the tap on empty space.
* `viewController._performModifierPerformTransitionResponse`: the transition request actually performed, with
  `animationDisabled` and the animation settings class.
* `coordinator.animationControllerForTransitionRequest`: which animation controller was chosen.
* `homeGestureToSwitcher.handleTimerEvent`, `settings.emptySwitcherDismissDelay`: the empty-switcher dismiss timer.
* `switcherController.performTransition`, `coordinator.dismiss...`: the `animated` flag on the way down.
