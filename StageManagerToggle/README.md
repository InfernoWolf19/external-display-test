# StageManagerToggle 1.0.0 (iPadOS 16.0, build 20A8372, Dopamine / rootless)

Makes the **Control Centre Stage Manager button** and the **Settings > Multitasking > Stage Manager switch** turn Stage
Manager on and off directly, without the first-run introduction.

## What was wrong
Stage Manager has two booleans in the `com.apple.springboard` defaults domain:

| key | meaning |
|---|---|
| `SBChamoisWindowingEnabled` | Stage Manager is on. SpringBoard observes it and re-lays-out the windows. |
| `SBChamoisWindowingEverEnabled` | Stage Manager has been turned on at least once. |

Both switches only write `Enabled` when `EverEnabled` is already true. While it is false they write `EverEnabled` instead
and leave `Enabled` alone. SpringBoard observes that write, dismisses Control Centre and presents the Stage Manager
introduction (`com.apple.SpringBoardEducation`). So on a device where `EverEnabled` is false, the switches never switch
anything by themselves; `defaults write com.apple.springboard SBChamoisWindowingEnabled -bool true` does.

(Read from the disassembly: `-[SBContinuousExposeModuleController setContinuousExposeEnabled:]` in
`ContinuousExposeModule.bundle`, `-[DBSMultitaskingContinuousExposeController setContinuousExposeEnabled:specifier:]` in
DisplayAndBrightnessSettings, and the SpringBoard observer block on `chamoisEverEnabled` in
`-[SBFluidSwitcherViewController initWithSwitcherController:...]`.)

## What this tweak does
Two hooks, nothing else:

* **SpringBoard** (Control Centre module): `-[SBContinuousExposeModuleController setContinuousExposeEnabled:]` writes
  `SBChamoisWindowingEnabled` with the new value. Both the tile and the expanded-panel button call this method.
* **Settings** (`Preferences`): `-[DBSMultitaskingContinuousExposeController setContinuousExposeEnabled:specifier:]`
  does what the original does once Stage Manager has been enabled before: writes the switch's own preference and posts
  `DBSMultitaskingContinuousExposeEnablementChanged`.

`SBChamoisWindowingEverEnabled` is never written, so the introduction is never triggered.

## Resource use
No timers, threads, polling or files. The classes live in lazily loaded code, so the hooks are installed when the class
first appears (bundle-load notification and a dyld image callback that only looks at the image name). Logging: two
`os_log` lines (subsystem `com.infernowolf19.stagemanagertoggle`) when a hook is installed.

## Notes
* If `SBChamoisWindowingEverEnabled` is already true on your device, the stock switches already behave like this; the tweak
  then changes nothing visible.
* To remove: uninstall the package. Nothing is stored. Stage Manager's own state stays as the switches left it.
* Build: `.github/workflows/build-stagemanager-toggle.yml` (artifact `StageManagerToggle-<short sha>`).
