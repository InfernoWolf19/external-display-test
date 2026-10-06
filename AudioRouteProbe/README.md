# AudioRouteProbe (iPadOS 16.0, build 20A8372, arm64e, Dopamine / rootless)

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

## Use
1. Install the `.deb` (rootless), then reboot or respring and wait ~20 s. The daemon is restarted by launchd; if
   unsure, reboot.
2. Reproduce, in this order, noting the time of each step:
   1. Nothing connected: open Control Centre, play audio, open the audio picker (tap the icon), close it.
   2. Plug in the USB-C monitor. Wait 5 s. Open the picker, close it.
   3. Unplug the monitor, plug in the wired AirPods Max. Wait 5 s. Open the picker, close it.
3. Collect the log. The daemon may be sandboxed, so every location is tried; check all of them:
   ```
   ls -la /var/jb/tmp/AudioRouteProbe.log /var/jb/var/mobile/Library/Logs/AudioRouteProbe.log \
          /var/jb/var/log/AudioRouteProbe.log 2>/dev/null
   ```
   and send whichever exist (the first lines say which files were opened).

   **If none of those exist** (0.1.0 behaviour), the daemon's sandbox blocks writes under the jailbreak root. From
   0.1.1 the probe then falls back to the daemon's own temp/cache directory, which every sandbox allows, and says so
   at the top of the log. Find it as root:
   ```
   sudo find /private/var/folders -name 'AudioRouteProbe.log' 2>/dev/null
   ```
   (that fallback is used only when no jbroot location can be opened; the OS cleans those directories itself).

   **If still nothing exists**, the tweak is not being loaded into the daemon. Check, in this order:
   ```
   ls -la /var/jb/Library/MobileSubstrate/DynamicLibraries/ | grep -i AudioRoute      # installed?
   ps aux | grep -E 'audiomxd|mediaserverd' | grep -v grep                           # which daemon runs, since when
   ls -lt /var/mobile/Library/Logs/CrashReporter | head -5                           # did the daemon crash?
   ```
   The daemon must be restarted *after* installing the package (reboot, or userspace reboot) for the tweak to load.

## Build
`.github/workflows/build-audio-probe.yml` builds a rootless `.deb`, or locally: `cd AudioRouteProbe && make package FINALPACKAGE=1`.
