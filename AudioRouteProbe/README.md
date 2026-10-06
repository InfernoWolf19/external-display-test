# AudioRouteProbe 0.4.1 (iPadOS 16.0, build 20A8372, arm64e, Dopamine / rootless)

**Superseded by `SpeakerPicker` (same branch); do not install both.** Diagnostics for the audio daemon plus **one opt-in experiment**. Without the opt-in file the tweak changes nothing:
every hook calls the original function first and forwards all argument registers unchanged.

The question: why does the iPad's built-in speaker disappear from Control Centre's audio picker as soon as a wired
output (USB-C monitor, wired AirPods Max) is connected?

## What the logs showed (0.2.2, device-verified)
* The daemon hosting audio is `mediaserverd` (user `mobile`); it can only write under `/private/var/tmp`, not the jbroot.
* The connected-port list (`conn`) **still contains the speaker** (`pspk`, id 115) next to the display (`pdsp`) or
  the wired AirPods Max. The `incl` filter is only ever asked about Bluetooth/AirPlay port types.
* The picker list from `cmsmCopyPickableRoutesForRouteConfiguration` has no speaker. Static reading of the
  function: it concatenates Bluetooth ports, AirPlay endpoints and **one** slot for the active non-wireless route.
  A wired route therefore displaces the speaker; the speaker is not filtered out of the port list.
* `Audio/Video`, `MediaPlayback` and `PlayAndRecord(_WithBluetooth)/Default` show this. `PlayAndRecord/VideoChat`
  keeps the speaker (and drops the display).

## The experiment: append the speaker row (off by default)
```
touch /private/var/tmp/AudioRouteProbe.append     # on  (takes effect on the next picker query, no reboot)
rm    /private/var/tmp/AudioRouteProbe.append     # off
```
When the file exists and the category is `Audio/Video` or `MediaPlayback` with mode `Default`, and the speaker is
missing from the list, the pick hook appends the speaker's route description. The description is built by the
daemon's own `cmsmCreateRouteDescriptionFromPortIDOrRouteConfiguration(speakerPortID, 0, 0, 0, 0)`, the same call the
daemon makes for port IDs, and marked `RouteCurrentlyPicked` only if the audio device reports the speaker as the
active route. The daemon's cached list is never modified: the hook returns a copy.

**Unknown, and what the experiment is for:** whether choosing that row moves audio to the speaker. That is decided
by `FigRoutingManagerPickRouteDescriptorForContext` and the audio device, not by the list. The `tap` log lines show
the descriptor that was chosen and the function's result.

Result of the 0.3.1 test: the daemon receives the tap (`tap2`), finds an endpoint for the speaker (`tap3`) and the pick
returns success (`tap4 -> 0`), yet nothing changes and no route-change event follows. Static reading of
`vaeRouteToSelectedPort` (what activating a local port endpoint calls): for a built-in port that is not the active one
it does **nothing at all** unless a controlling audio session exists, and with one it only sets that session's
`OverrideRoute` property. **So the experiment must be run while audio is playing** (Music, a video, anything that
holds an audio session); with silence there is nothing to override. 0.3.2 logs `rts` (is there a session?) and
`prop` (the OverrideRoute request and the result) to show what the audio stack answers.

0.4.1: 0.4.0 listed no extra rows at all (`append: skipped ... no speaker/display in the connected-port list`) because the
connected-port list's CFNumbers are arm64 tagged pointers, which my object check rejected. Fixed; nothing else changed.

### 0.3.2 device result and what 0.4.0 does about it
With audio playing, tapping the row makes the daemon call `MXCoreSessionSetProperty(session, OverrideRoute, "Speaker")`,
which returns **-12981**. In the disassembly that case looks the session's audio category up in a 35-entry table
(a CFDictionary global) and returns -12981 when the entry is `kCMSessionOutputOverridability_CannotOverride`.
Playback categories are `CannotOverride`; that is the policy that stops the speaker being chosen.

**Experiment 2 (second opt-in file):**
```
touch /private/var/tmp/AudioRouteProbe.override     # on: a patched copy of that table says CanOverride everywhere
rm    /private/var/tmp/AudioRouteProbe.override     # off: the original table is restored on the next override request
```
It only swaps the table pointer (after checking it is a 35-entry CFDictionary in writable memory) and only when the
daemon is about to evaluate an `OverrideRoute` request. Whether the audio device then actually moves the audio is the
open question; the log shows `override-policy`, `prop` (result) and the route/pick changes that follow.

Because choosing the speaker makes the daemon's own list show the speaker instead of the display, 0.4.0's append also
adds the display row ("Dock Connector") when the speaker is the active route, so you can switch back.

Earlier results: 0.3.0 showed the row but the picker reverted; the appended entry said `RouteType = Override` (the
daemon's own says `Default`) but the picker rebuilds descriptors itself, so that is not the cause (the `.default`
flag was removed in 0.4.0). 0.3.1 showed the pick reaches the daemon and succeeds on paper; with no audio playing
there is no session and `vaeRouteToSelectedPort` does nothing.

## What gets logged
| tag | function | meaning |
|---|---|---|
| `conn` | `vaemCopyConnectedPortsListForRouteConfiguration` | port IDs + 4CC type + "is headphones" |
| `incl` | `vaemShouldIncludePortTypeForRouteConfiguration` | whether a port type is included |
| `pick` | `cmsmCopyPickableRoutesForRouteConfiguration` | the route descriptions the picker will show (after the experiment, if on) |
| `rchg` | `vaemVADRouteChangeListener` | route-change events (raw register values only) |
| `tap` `tap2` `tap3` `tap4` | `FigRoutingManagerPickRouteDescriptorForContext`, `...DescriptorsForContext`, `FigEndpointDescriptorUtility_CopyEndpointFromDescriptor`, `FigRoutingManagerPickEndpointsForContext` | a route was chosen: descriptors, whether an endpoint exists, result |
| `append` | experiment | added / skipped and why |

Each question is logged only when its answer changes.

## Safety
* Hooks are installed only if `kern.osversion` is exactly `20A8372` **and** the first three instructions of each
  target match what was disassembled from that build. Anything else is left alone and logged.
* Every hook forwards all eight argument registers to the original, so the real arity of the hooked function does not
  matter (0.2.0 assumed four arguments for a five-argument function and crashed `mediaserverd`).
* Runs only inside `audiomxd` / `mediaserverd` (daemon part) and `SpringBoard` (logging part).
* Crash guard: five daemon launches in a row that die within 25 s disable the daemon part for that version. The
  counter is `/private/var/tmp/AudioRouteProbe.log.<version>.boot`; a new version starts at zero; deleting the file re-arms.
* Kill switches: `touch /private/var/tmp/AudioRouteProbe.off` (daemon, takes effect on its next launch, so reboot) and
  `touch /var/jb/tmp/AudioRouteProbe.off` (SpringBoard part, respring).
* Rootless: files under the jailbreak root are resolved with libroot (`ROOT_PATH`), never hard-coded. The daemon's own
  sandbox cannot see the jbroot, so its log, flag and counter live in `/private/var/tmp`.
* Worst case if something is wrong: the audio daemon crashes and launchd restarts it. If it crash-loops, use Dopamine
  safe mode and remove the package.

## Use
1. Install the `.deb` and **reboot**.
2. Logs:
   ```
   cat /var/jb/tmp/AudioRouteProbe.picker.log        # SpringBoard: what the picker is offered, plus daemon beacons
   cat /private/var/tmp/AudioRouteProbe.log          # daemon: conn / incl / pick / rchg / tap / append (and .log.1 after rotation)
   ```
   Beacons in the picker log: `loaded` = daemon pid, `info` 1 ok / 2 kill switch / 3 wrong build / 4 crash guard,
   `hooks` = bitmask of installed hooks (1023 = all ten), `ev.*` = how often each hook fired.
3. To try the experiments: plug in the monitor, `touch /private/var/tmp/AudioRouteProbe.append` and
   `touch /private/var/tmp/AudioRouteProbe.override`, **start audio playing**, open the picker, tap the Speaker row and
   note whether the sound moves to the iPad speaker. Then tap "Dock Connector" and note whether it moves back. Send both logs.

Log housekeeping: a question is logged only when its answer changes; the daemon log rotates to `.log.1` at 2 MB.

## Build
`.github/workflows/build-audio-probe.yml` builds a rootless `.deb`, or locally: `cd AudioRouteProbe && make package FINALPACKAGE=1`.
