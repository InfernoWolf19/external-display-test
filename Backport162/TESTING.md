# Backport162 - exhaustive device test list

Setup: install the CI `.deb` (`Backport162-<sha>`), respring. Do NOT install Backport162BBD yet. For anything odd: create an empty file `/var/jb/tmp/Backport162.debug`, repeat, then send `/var/jb/tmp/Backport162.log` (+ `.log.1`), `/var/jb/tmp/Backport162.crash`, and a screen recording. A kill switch for any feature is an empty file `/var/jb/tmp/Backport162.off.<name>` (README table).

Mark each item: OK / BUG (what happened) / N/A.

## 0. Install and boot
- [ ] Respring completes, no crash loop, no Dopamine safe-mode popup. `Backport162.log` (with .debug) shows "Backport162 0.7.x loaded".
- [ ] `Backport162.crash` is empty / not created after 10 minutes of normal use.
- [ ] Full userspace reboot, then wait 3 minutes at the home screen: no "Watchdog Timeout" popup.
- [ ] Plug in / unplug the charger, lock and unlock, sleep and wake: no crash.

## 1. Opening apps and default window size (16.2: apps open windowed)
- [ ] Open 6+ different apps from the home screen icons: each opens as a window (about 1056x646 landscape), not full screen.
- [ ] Open apps from the dock, Spotlight, App Library, a notification, a link: same.
- [ ] Open an app already open in the strip: it comes forward with its last size.
- [ ] Open a compatibility (iPhone-only) app: sensible size, no crash.
- [ ] Close an app (3-dots > Close) then reopen: opens at the default size (16.2 does not remember a closed window), no blur on the window, interactive.
- [ ] Rotate to portrait: default size is the portrait one; rotate back.

## 2. Zoom and the 3-dots menu
- [ ] Menu items: Zoom, Add Another Window, Minimise, Close all work.
- [ ] Zoom on a windowed app: goes full screen.
- [ ] Press Zoom again (menu title should now say Unzoom): returns to a window of the default size.
- [ ] Zoom a window you resized by hand, un-zoom: returns to its previous size or the default (report which).
- [ ] Zoom shortcut from the hardware keyboard (Enter Full Screen, ctrl+cmd+F): same result as the button.
- [ ] Zoom with 3 windows open; zoom then open another app; zoom then go to switcher.
- [ ] Minimise: window goes to the strip/home as expected.

## 3. Moving and resizing windows
- [ ] Drag a window by its top bar (finger and pointer): follows smoothly, no snap-back, no crash, strip stays correct.
- [ ] Resize from each corner and each edge (finger and pointer): snaps to grid sizes, no jumping.
- [ ] Widen a window to the full width: strip hides only when it should (width at or above about 1056 with 2+ windows, about 1125 with 1 window); shrink it: strip returns.
- [ ] Windows overlap and cascade when you open 2, 3, 4, 5 windows; the front window is the last used.
- [ ] Drag a window to the left and right screen edges and to the bottom (dock area).
- [ ] Release a drag very quickly (flick); start a drag and cancel it; drag with two fingers.

## 4. The left strip
- [ ] With 1 and 2 windows open: strip shows the other apps, neat spacing, correct icons/cards.
- [ ] With 3+ windows: strip hides when the windows do not fit (expected), reveals when you swipe in from the left edge with a finger.
- [ ] Pointer: move the pointer all the way to the left edge: strip reveals. Move away: it hides again after the same delay as 16.2.
- [ ] Tap an app in the revealed strip 20 times in a row (different apps): every tap swaps the app, no missed taps, no crash.
- [ ] Drag an app out of the strip into the stage 15 times: always works; also drag onto the stage while another window is open.
- [ ] Tap the strip when it is only partly revealed; tap and hold.
- [ ] Strip order is most-recent first and updates when you switch apps.
- [ ] No tiny leftover card at the left edge when the strip should be hidden.

## 5. App switcher (swipe up and hold)
- [ ] Opens with a smooth animation, windows shown as piles with correct frames, no blank cards.
- [ ] Scroll left/right through all piles (8+ apps); piles' visible cards and shadows look right.
- [ ] Tap a card: opens that app. Tap empty space: returns home (no crash, no glitch, even with debug on).
- [ ] Swipe a card up to close it; close the last card (switcher should auto-dismiss about 0.3 s after it is empty).
- [ ] Dismiss quickly, dismiss halfway and release, dismiss slowly: no cards flying left, no lingering windows, no cards stuck on the home screen.
- [ ] Open the switcher with nothing open: opens with the normal animation and dismisses itself.
- [ ] Switcher from a full-screen (zoomed) app, from a windowed app with 3 windows.
- [ ] Open and close the switcher 30 times quickly: no hang, no crash.

## 6. Home gestures and transitions
- [ ] Swipe up from an app to go home (full, partial, quick): smooth, no 0.8x card at the left edge, no windows lingering.
- [ ] Go home and open an app again 20 times.
- [ ] Open and close apps repeatedly: the floating dock must stay visible with a windowed app (no vanish and reappear flicker).
- [ ] App to app (cmd+tab, strip tap, dock tap): correct transition, no crash.
- [ ] Opening an app from the home screen while another window is open.
- [ ] Icon zoom animation when opening from the home screen and when closing back to it.

## 7. Keyboard (on-screen and hardware)
- [ ] On-screen keyboard with a windowed app (Notes, Safari): the keyboard is never behind the dock (report whether the dock hides while the keyboard is up); the window lifts above the keyboard.
- [ ] Dock never covers the keyboard keys; keyboard never ends up behind the dock; repeat 20 times (show/hide, switch fields).
- [ ] Magic Keyboard: type in a window at EVERY size (small windowed with the dock visible, medium, full width, zoomed): typing always works.
- [ ] Connect and disconnect the Magic Keyboard repeatedly (5 times): no crash, no respring loop.
- [ ] Hold cmd: the shortcut overlay appears; next/previous app window (cmd+`) is listed and works; Enter Full Screen listed.
- [ ] cmd+tab app switching, cmd+H, cmd+space (Spotlight) while windows are open.
- [ ] Keyboard focus follows the front window after switching windows and after dragging.

## 8. Dock
- [ ] Floating dock visible with windowed apps, hides appropriately for a zoomed app (swipe up from the bottom edge shows it).
- [ ] Dock stays visible while opening/closing apps and while the switcher opens/closes.
- [ ] Drag an app out of the dock into the stage; open an app from the dock while 3 windows are open.

## 9. Multiple windows of one app
- [ ] Safari / Files / Notes: Add Another Window opens a second window of the app.
- [ ] Switch between the app's windows, close one, close all, reopen.
- [ ] An app that does not support multiple windows: Add Another Window shows the 'multiple windows not supported' message and does not crash.

## 10. Picture in Picture
- [ ] Start a video in Safari/YouTube, go home: PiP appears; return to the app: PiP restores smoothly (PiP morph).
- [ ] When the app backgrounds, the PiP window must not shift position at all before settling (known: it moves slightly then settles).
- [ ] PiP while a window is open; PiP on rotation; drag the PiP to each corner; PiP with the keyboard up.
- [ ] Note: Split View and Slide Over do not exist while Stage Manager is on (Apple: Stage Manager replaces them), so the 3-dots menu correctly has no Slide Over / Split View items. Not a test item.

## 11. Orientation
- [ ] Rotate with 1, 3 windows open and with the switcher open: layout recovers, no crash.
- [ ] Rotation lock on/off.

## 12. System UI with windows open
- [ ] Control Center, Notification Center, Lock Screen, Spotlight, App Library, Siri, notification banners, volume HUD with windows open: all draw above, no dock/strip glitches.
- [ ] Screenshot (power+volume) and screen recording while windows open.

## 13. Extended display (external monitor)
- [ ] Connect the display: extended mode is chosen, pill appears, no crash loop. Tap the pill: no crash.
- [ ] Windows open on the external display; dock, strip, switcher on the external display behave like the main one.
- [ ] Open the switcher on the external display with nothing open: animation and auto-dismiss.
- [ ] Drag a window from the iPad to the external display and back (pointer and finger): no crash, window keeps size.
- [ ] Drag a strip app onto the external display stage.
- [ ] Close a window on the external display (3 dots > Close): no crash.
- [ ] Pointer crossing between displays during a drag: no stuck gesture, next drag works.
- [ ] Keyboard focus follows the pointer to the display it is on; typing goes to the right window.
- [ ] Disconnect while apps are on it: they return to the iPad; reconnect: layout restored.
- [ ] Mirroring toggle in Settings: switches between mirror and extended.
- [ ] Display connected before boot; connected after.

## 14. Stability and regressions
- [ ] 30+ minutes of mixed use with 8+ apps: no crash, no hang, no watchdog popup.
- [ ] Memory: SpringBoard does not slow down over time (repeat the switcher test at the end).
- [ ] Stock features still work: AirPlay, rotation, app launches from the App Library, drag and drop between apps, Stage Manager toggle in Control Center.
- [ ] `Backport162.crash` empty at the end of the session.

## What to send after a bad run
`Backport162.crash`, `Backport162.log` and `.log.1` (with `.debug` on), a screen recording, and what you were doing in the last 10 seconds.
