# AudioRouteProbe 0.2.2 (iPadOS 16.0, build 20A8372, arm64e, Dopamine / rootless)

**Passive diagnostics only.** Every hook calls the original function first and then writes a log line;
nothing about audio routing is changed. Its purpose is to find out why the iPad's built-in speaker disappears
from Control Centre's audio picker as soon as a wired output (USB-C monitor, wired AirPods Max) is connected.

## Background (from static analysis of 20A8372)
* The picker list is built in `MediaExperience.framework`, hosted by `audiomxd`, not in SpringBoard.
* `_cmsmCopyPickableRoutesForRouteConfiguration` assembles it from the *connected ports* of the current route
  configuration (category + mode), which `_vaemCopyConnectedPortsListForRouteConfiguration` reads from the
  `VirtualAudio.plugin` HAL plug-in (VAD property `'cprc'`), plus wireless endpoints.
* `_vaemShouldIncludePortTypeForRouteConfiguration` asks the plug-in (property `'prsp'`) whether a port type
  belongs to a route configuration.
* Overriding to a port is a separate mechanism (`MXCoreSession.overridePortsList`, "output overridability").

## What gets logged
| tag | function | meaning |
|---|---|---|
| `conn` | `vaemCopyConnectedPortsListForRouteConfiguration(cat, mode, arr, isInput)` | port IDs + 4CC port type + "is headphones" for every connected port |
| `incl` | `vaemShouldIncludePortTypeForRouteConfiguration(cat, mode, arr, portType)` | whether a port type is included, yes/no |
| `pick` | `cmsmCopyPickableRoutesForRouteConfiguration(category, mode, …)` | the route descriptions the picker will show |
| `rchg` | `vaemVADRouteChangeListener` | which VAD properties changed (selector/scope/element) |

The question it answers: with a wired output connected, is the built-in speaker **absent from `conn`**
(the plug-in does not report it), **present in `conn` but `incl` says no**, or **present in both but removed
before `pick`**? Each case points at a different fix.

## Safety
* Hooks are installed only if `kern.osversion` is exactly `20A8372` **and** the first three instructions of each
  target match what was disassembled from that build. Anything else is left alone and logged.
* Runs only inside `audiomxd` / `mediaserverd`.
* Kill switch: create any of these files and restart the daemon (or reboot):
  `/var/jb/tmp/AudioRouteProbe.off`, `/var/jb/var/mobile/Library/Preferences/AudioRouteProbe.off`, `/var/jb/var/log/AudioRouteProbe.off`.
* Rootless: every file the probe creates lives under the jailbreak root. The prefix is resolved at runtime with
  libroot (`ROOT_PATH()` from Theos' `rootless.h`), not hard-coded, so relocated jbroots work; nothing is written to
  a rootful path.
* Crash guard: after 5 consecutive launches that did not stay up 25 s the probe disables itself (counter file
  `<logfile>.boot` next to the first log; delete it to re-arm).
* Worst case if a hook is wrong: the audio daemon crashes and launchd restarts it. If it crash-loops, use
  Dopamine safe mode and remove the package.

## Use (0.2.0)
0.2.0 has two parts in one dylib. The SpringBoard part is the reliable one: SpringBoard is not sandboxed like the
media daemon, so it can always write its log.

1. Install the `.deb` and **reboot** (the daemon only loads the tweak when it restarts).
2. Reproduce, noting the time of each step: nothing connected, then plug in the monitor, then unplug it and plug
   in the wired AirPods Max. Open the audio picker in Control Centre at each step (optional: the log updates on
   its own whenever the picker's data changes).
3. Read the **primary log** (written by SpringBoard):
   ```
   cat /var/jb/tmp/AudioRouteProbe.picker.log
   ```
   It contains:
   * `picker <category>/<mode> (...)`: the exact list the picker is offered, logged whenever it changes. This is the
     answer to "is the iPad speaker offered while the monitor / AirPods are connected?".
   * `daemon beacon ...`: Darwin notifications from the daemon side. `loaded` proves the probe is running inside
     mediaserverd/audiomxd (state = pid); `info` is 1 ok / 2 kill switch / 3 wrong OS build / 4 crash guard;
     `hooks` is the bitmask of installed hooks (15 = all four); `ev.*` count how often each hook fired.
   If there is **no** `loaded` beacon the probe is not loaded in the daemon (or the daemon may not post
   notifications); the picker lines still work.
4. Daemon-side log (`conn` / `incl` / `pick` / `rchg` lines). The daemon sandbox denies writes under the jbroot, so
   it writes to its own temp dir (confirmed on 20A8372):
   ```
   cat /private/var/tmp/AudioRouteProbe.log
   ```
   The first lines of each launch list every location tried and why it failed (uid, errno).
5. Crash guard: five daemon launches in a row that die within 25 s disable the probe for that version. The counter is
   `/private/var/tmp/AudioRouteProbe.log.<version>.boot` (a new version starts at zero; deleting the file re-arms).

0.2.2: the daemon log records a question only when its answer changes (0.2.1 filled 4 MB in 80 s and truncated away the
plug-in events) and rotates to `AudioRouteProbe.log.1` instead of truncating; send both files if `.1` exists.

0.2.0 note: `vaemVADRouteChangeListener` takes five register arguments, not the four I assumed, so the 0.2.0 hook
clobbered the fifth and crashed `mediaserverd` on the first route change. Since 0.2.1 every hook forwards x0..x7
unchanged.

Kill switch: create any of these files and restart the daemon (or reboot):
  `/var/jb/tmp/AudioRouteProbe.off`, `/var/jb/var/mobile/Library/Preferences/AudioRouteProbe.off`, `/var/jb/var/log/AudioRouteProbe.off`.
* Rootless: every file the probe creates lives under the jailbreak root. The prefix is resolved at runtime with
  libroot (`ROOT_PATH()` from Theos' `rootless.h`), not hard-coded, so relocated jbroots work; nothing is written to
  a rootful path.
* Crash guard: after 5 consecutive launches that did not stay up 25 s the probe disables itself (counter file
  `<logfile>.boot` next to the first log; delete it to re-arm).
* Worst case if a hook is wrong: the audio daemon crashes and launchd restarts it. If it crash-loops, use
  Dopamine safe mode and remove the package.

## Use (0.2.0)
0.2.0 has two parts in one dylib. The SpringBoard part is the reliable one: SpringBoard is not sandboxed like the
media daemon, so it can always write its log.

1. Install the `.deb` and **reboot** (the daemon only loads the tweak when it restarts).
2. Reproduce, noting the time of each step: nothing connected, then plug in the monitor, then unplug it and plug
   in the wired AirPods Max. Open the audio picker in Control Centre at each step (optional: the log updates on
   its own whenever the picker's data changes).
3. Read the **primary log** (written by SpringBoard):
   ```
   cat /var/jb/tmp/AudioRouteProbe.picker.log
   ```
   It contains:
   * `picker <category>/<mode> (...)`: the exact list the picker is offered, logged whenever it changes. This is the
     answer to "is the iPad speaker offered while the monitor / AirPods are connected?".
   * `daemon beacon ...`: Darwin notifications from the daemon side. `loaded` proves the probe is running inside
     mediaserverd/audiomxd (state = pid); `info` is 1 ok / 2 kill switch / 3 wrong OS build / 4 crash guard;
     `hooks` is the bitmask of installed hooks (15 = all four); `ev.*` count how often each hook fired.
   If there is **no** `loaded` beacon the probe is not loaded in the daemon (or the daemon may not post
   notifications); the picker lines still work.
4. Optional, richer daemon-side log (`conn` / `incl` / `pick` / `rchg` lines). The daemon may be sandboxed, so every
   location is tried:
   ```
   ls -la /var/jb/tmp/AudioRouteProbe.log /var/jb/var/log/AudioRouteProbe.log 2>/dev/null
   find /private/var/folders -name 'AudioRouteProbe.log' 2>/dev/null     # daemon temp-dir fallback (no sudo: it runs as mobile)
   ```
   The first lines say which locations were opened and why others failed (uid, errno).

Kill switch: `touch /var/jb/tmp/AudioRouteProbe.off` (SpringBoard side; respring). The daemon cannot see the jbroot, so for it use
`touch /private/var/tmp/AudioRouteProbe.off`, then reboot.

## Build
`.github/workflows/build-audio-probe.yml` builds a rootless `.deb`, or locally: `cd AudioRouteProbe && make package FINALPACKAGE=1`.
