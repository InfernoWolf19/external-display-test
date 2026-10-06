# SpeakerPicker 1.0.0 (iPadOS 16.0, build 20A8372, arm64e, Dopamine / rootless)

Keeps the iPad's built-in speaker selectable in the audio picker (Control Centre / Now Playing) while a USB-C monitor
or wired headphones are connected, and lets you switch between the speaker and the wired output and back.

It is the finished form of `AudioRouteProbe` (same branch), which established how this works on the device. **Do not
install both** (remove AudioRouteProbe first): they hook the same function.

## What it does
The daemon's list of pickable routes holds Bluetooth ports, AirPlay endpoints and **one** slot for the active
non-wireless route, so a wired route displaces the speaker. Choosing the speaker was also refused, because the daemon
marks playback categories `CannotOverride` for the speaker override the picker requests.

Inside `mediaserverd` / `audiomxd` only:
1. **One hook**, on `cmsmCopyPickableRoutesForRouteConfiguration`. For the plain Audio/Video or MediaPlayback list in
   Default mode it returns a copy of the daemon's list with the route of any connected speaker (`pspk`), display
   (`pdsp`) or wired-headphone (`phpw`) port that is missing from it appended. The daemon builds that route
   description itself, the same way it builds Bluetooth entries; its cached list is never modified.
2. **One table swap**, once: the daemon's category -> overridability table (a 35-entry CFDictionary global) is replaced
   by a copy where every `CannotOverride` says `CanOverride` (21 of the 35 entries on this build), so the speaker
   override is accepted. The original is kept and restored by the kill switch.

Using it: start any audio, open the picker, tap **iPad** (sound moves to the speaker), tap the monitor / headphones
row to move back. Speaker selection applies to a playing audio session; with nothing playing there is nothing to move.

## Resource use and logging
* One hook, no timers, no threads, no polling, no file writes while running.
* A call that is not the Audio/Video or MediaPlayback default list costs two string comparisons.
* A matching call reads the daemon's connected-port list at most once per 200 ms.
* Logging goes to the unified log (`os_log`, subsystem `com.infernowolf19.speakerpicker`): a few lines per boot.
  Read with Console / `log stream --predicate 'subsystem == "com.infernowolf19.speakerpicker"'`.
* A file log is written **only** while `/var/tmp/SpeakerPicker.debug` exists, only when the outcome changes, and
  restarts at 256 KiB: `/var/tmp/SpeakerPicker.log`.

## Safety
* Active only on build `20A8372` and only if the first three instructions of every private function it uses match
  what was disassembled from that build; otherwise it does nothing and says so in the unified log.
* The policy table is touched only if it is a 35-entry CFDictionary in writable memory.
* Crash guard: five launches in a row that die within 25 s disable it for this version
  (`/var/tmp/SpeakerPicker.1.0.0.boot`, touched only at launch; delete to re-arm; a new version starts fresh).
* Kill switch: `touch /var/tmp/SpeakerPicker.off`. Takes effect within a second (lists return to stock, original
  policy table restored). Remove the file to enable again.
* If the audio daemon ever crash-loops: Dopamine safe mode, remove the package.

## Paths
The audio daemon is sandboxed and cannot see the jailbreak root, so its few files are in the system temp directory
`/var/tmp` (kill switch, debug flag, debug log, launch counter). The package itself is an ordinary rootless package.

## Limits
* iPadOS 16.0 / 20A8372 only (private functions are located by address).
* Affects the Audio/Video and MediaPlayback pickers; calls with filters, and the PlayAndRecord families, are untouched.
* Relaxing the overridability table also lets apps in playback categories request the speaker override.

## Build
`.github/workflows/build-speaker-picker.yml` builds a rootless `.deb` (artifact `SpeakerPicker-<short sha>`), or locally:
`cd SpeakerPicker && make package FINALPACKAGE=1`.
