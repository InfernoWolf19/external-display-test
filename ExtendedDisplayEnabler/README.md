# ExtendedDisplayEnabler (iPadOS 16.0, build 20A8372, M2 iPad Pro, Dopamine / rootless)

## Why a USB-C monitor only mirrors on this build
`-[SpringBoard _completeStartupAfterMainSceneConnect:]` in betas 2 and 5 contains

    if (<capable> && SBChamoisExternalDisplayControllerIsEnabled()) {
        build SBSystemShellExtendedDisplayResolverFactory + ...PolicyFactory,
        wrap them in an SBSceneHostingDisplayControllerProvider,
        [SBDisplayManager registerDisplayControllerProvider:]   // stored in _extendedDisplayControllerProvider
    }

In 20A8372 that branch is gone: no code in SpringBoard references the flag or the Extended factory
classes. Only the Mirrored and NonInteractive providers are registered, so no external display ever
reports windowing mode 1 and Settings hides Arrangement / Resolution / Scaling.
The Extended classes and the `_extendedDisplayControllerProvider` ivar are still present.

This tweak re-creates that registration after startup. See the header of `Tweak.x`.

## Build
* GitHub Actions: `.github/workflows/build-tweak.yml` produces a rootless `.deb` artifact, or
* locally with Theos: `cd ExtendedDisplayEnabler && make package FINALPACKAGE=1`

## Use
1. **Unplug the monitor first**, install the `.deb`, respring.
2. Plug the monitor in. Settings → Display & Brightness → (monitor) should now show Arrangement /
   Resolution / Scaling. If it still mirrors, turn mirroring off there: the Extended policy
   deliberately sets `mirroringEnabled = YES` on first connect.
3. Log: `/var/mobile/Library/Logs/ExtendedDisplayEnabler.log`
4. Kill switch: `touch /var/mobile/Library/Preferences/ExtendedDisplayEnabler.off`, then respring.
   If SpringBoard crash-loops, boot Dopamine safe mode and remove the package.

## Mirroring on this build
20A8372 hardcodes `mirroringEnabled = YES` in two places: the Extended policy's connect and the
education observer's connect handler (beta 5 used `!_areRuntimeAvailabilityRequirementsMet` there).
Its service method `setDisplayMirroringEnabled:forDisplay:` also ignores the requested value, so
Settings' "Mirror Display" switch could only ever turn mirroring on. The tweak restores the service
method, remembers when you switch mirroring off (`/var/mobile/Library/Preferences/ExtendedDisplayEnabler.extended`)
and puts that choice back after either connect handler runs.

## Status
Not compiled or run: written from static analysis only. Expect to iterate from the log / crash report.
