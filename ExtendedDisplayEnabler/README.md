# ExtendedDisplayEnabler (iPadOS 16.0, build 20A8372, M2 iPad Pro, Dopamine / rootless)

Brings back Stage Manager–style **extended display** (separate display, arrangement, display zoom)
on a build where Apple left the classes in SpringBoard but removed the glue that used them.

## What was removed in 20A8372 and what this tweak puts back

| Where | 20A8372 | Beta 5 | Tweak |
|---|---|---|---|
| `-[SpringBoard _completeStartupAfterMainSceneConnect:]` | no Extended provider is built or registered; no code references `SBChamoisExternalDisplayControllerIsEnabled` or the Extended factories | builds `SBSystemShellExtendedDisplay{Resolver,ControllerPolicy}Factory`, wraps them in an `SBSceneHostingDisplayControllerProvider`, registers it *before* the other providers | recreates it, registered before the other providers when possible (hook on `-[SBDisplayManager registerDisplayControllerProvider:]`), otherwise right after startup |
| `-[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:]` | ignores the requested value, can only turn mirroring on | applies the requested value | restores that behaviour (runs on the main queue: `SBDisplayManager` asserts main thread) |
| Extended policy `connectToDisplayController:` | hardcodes `mirroringEnabled = YES` | `= !_areRuntimeAvailabilityRequirementsMet` | after it runs: your saved choice, else beta 5's rule |
| `SBExternalDisplayEducationObserver` connect handler | stub that sets `mirroringEnabled = YES` | full education presenter | after it runs: your saved choice |

Everything else behind the Settings screens (`_supportedScalesForDisplay:`, `_effectiveSettingsForDisplay:`,
`_displayInfoForDisplayIdentity:`, `setDisplayModeSettings:`, `setDisplayArrangement:`) is the same size as
beta 5, so it is left alone. This build has no separate "Resolution" screen; scaling is **Display Zoom**.

## Build
* GitHub Actions: `.github/workflows/build-tweak.yml` produces a rootless `.deb` artifact, or
* locally with Theos: `cd ExtendedDisplayEnabler && make package FINALPACKAGE=1`

## Use
1. Install the `.deb`, respring. Plug the monitor in (or leave it plugged in).
2. Settings → Display & Brightness → (monitor). Turn **Mirror Display** off and press **Set**.
   That choice is saved and re-applied after every connect. Turn it back on to go back to mirroring.
3. With no saved choice the tweak follows beta 5: mirror unless the runtime requirements are met.

## Files (all under `/var/mobile/Library`)
| File | Purpose |
|---|---|
| `Logs/ExtendedDisplayEnabler.log` (+ `.log.1`) | log, rotated at 256 KiB |
| `Preferences/ExtendedDisplayEnabler.off` | **kill switch**: `touch` it and respring; every hook becomes a pass-through |
| `Preferences/ExtendedDisplayEnabler.choice` | saved choice (`extended` / `mirror`); delete it to forget |
| `Preferences/ExtendedDisplayEnabler.boot` | crash-loop strike counter |

## Safety
* Crash-loop guard: a launch that does not stay up for 25 s counts as a strike; after 5 in a row the
  tweak disables itself (log line `crash guard: …`). Delete `ExtendedDisplayEnabler.boot` to re-arm it.
* If SpringBoard crash-loops anyway: boot Dopamine safe mode, or create the kill-switch file from Filza, then
  remove the package.

## Status
Verified on a real device (the log shows the toggle applied and persisted across reconnects; extended layout,
cursor and windows work). The early-registration path (0.2.0) and crash guard are new and less tested: the log line
`registered Extended display provider … (early, before the other providers)` shows which path ran.
