# BOOTGUARD (0.7.9): a bad build can no longer leave the iPad on the Apple logo

Code: `BPGuard.c` (the loader), `Makefile` (two dylibs instead of one), `layout/DEBIAN/postinst`, host test `tools/bpguard_test.c`, CI step "Verify the boot guard packaging".

## 1. Why

Build 50bd5e8 had a constructor that created SpringBoard singletons while SpringBoard was still loading its images. SpringBoard never finished starting, the iPad sat on the Apple logo, and the only way out was booting stock and re-jailbreaking with tweak injection disabled. Fixed in b6d6599 / a905444, but the next bug of that kind must not cost the same.

## 2. Design

Before: one dylib, `Backport162.dylib`, with the SpringBoard filter plist; the injector loaded it into every SpringBoard launch.

Now:

| file (under `/var/jb`) | what | filter plist |
|---|---|---|
| `Library/MobileSubstrate/DynamicLibraries/Backport162.dylib` | the LOADER (`BPGuard.c`). Pure C, libSystem only (open / read / write / unlink / stat / dlopen / dispatch). No Objective-C, no CydiaSubstrate, no libroot, no tweak code, no message to any SpringBoard object | `Backport162.plist`, `Bundles = com.apple.springboard`: the ONLY SpringBoard filter plist of the tweak proper |
| `usr/lib/Backport162/Backport162Core.dylib` | the real tweak: exactly what `Backport162.dylib` used to be | none (the injector never sees it; the placeholder `Backport162Core.plist` that Theos insists on is deleted from the package by `after-stage` in the Makefile) |

The loader's constructor is the whole logic (`bpg_launch`). It resolves the jailbreak root like Tweak.x (`THEOS_PACKAGE_INSTALL_PREFIX` = `/var/jb`, i.e. what `ROOT_PATH_NS` gives; the first of that and the absolute `/var/jb` that has a `tmp` directory) and works in `<jbroot>/tmp`.

### 2.1 States

| situation at launch | loader does | core loaded | marker `Backport162.booting` afterwards | logged (`Backport162.log`) |
|---|---|---|---|---|
| `Backport162.off.all` exists | removes a stale marker, nothing else | NO | none | only with `Backport162.debug` |
| not SpringBoard (never happens with the plist; for safety) | loads the core, no marker | yes | untouched | debug only |
| `Backport162.noguard` exists | removes a stale marker | yes, always | none | debug only |
| marker exists (the previous launch loaded the core and never finished booting) | TRIPPED: removes the marker, writes `Backport162.tripped` (timestamp + the old marker text) | NO (this launch boots stock) | none: the next launch retries | ALWAYS, one line `BOOT GUARD TRIPPED ...` (it is the only silent-disable event) |
| none of the above | creates the marker (`pid=.. t=..`), schedules its removal, loads the core | yes | until the clear (2.2) | nothing (debug only) |
| marker cannot be created (tmp missing / read-only) | fails open | yes | none | debug only |
| core file missing / `dlopen` fails | logs the `dlerror()` line, carries on | no | cleared normally | ALWAYS |
| marker exists but cannot be removed | reports it; every launch skips the tweak until the file is deleted by hand | NO | stays | ALWAYS |

Consequences: a crash or hang BEFORE the clear gives exactly one skipped launch, the next one tries again (a persistent bug alternates "tweak crashes" / "stock SpringBoard that boots"; it never loops). A SpringBoard crash AFTER the clear does not trip anything.

### 2.2 When the marker is cleared

From the constructor the loader only enqueues a plain C function on the main queue (`dispatch_async_f(dispatch_get_main_queue(), ...)`: no SpringBoard object is touched). The first time the main queue is serviced, i.e. SpringBoard's main run loop is up and turning, that callback arms `dispatch_after_f(45 s)` on the main queue again; its callback `unlink`s the marker. So:

* a hang or crash while SpringBoard is loading (the 50bd5e8 failure) never reaches the main queue: marker stays;
* a main thread that is stuck later (deadlock, never returns to the run loop) does not service the timer: marker stays;
* a crash or watchdog kill inside the first 45 s of a turning run loop: marker stays;
* a SpringBoard that has been up 45 s with a turning main loop is "booted".

Limit: a hang that leaves the main run loop turning (a background-thread deadlock, SpringBoard waiting for a service forever) is cleared as "booted" after 45 s. That case shows a stuck UI, not a boot loop, and a respring retries. The 45 s are not tied to a SpringBoard notification on purpose (an unverified notification name that never fires would make the guard skip every second launch).

### 2.3 Escape hatches (all in `<jbroot>/tmp`, `/var/jb/tmp` on Dopamine)

* `Backport162.noguard`: guard off, the core is always loaded.
* `Backport162.off.all`: the core is never loaded (stock SpringBoard; the other dylibs are not covered, see 4). Wins over `noguard`.
* `Backport162.off` (existing): the core is loaded and every hook answers "off".
* `Backport162.debug` (existing): the loader also logs what it decides.

postinst (`configure`) deletes `Backport162.booting` and `Backport162.tripped`, so every install / update starts clean. It never touches `noguard` / `off.all`.

## 3. Recovery in plain words

If the iPad hangs on the Apple logo or SpringBoard keeps crashing after an update:

1. Do nothing clever: force restart (volume up, volume down, hold the side button) and jailbreak with Dopamine as usual. The next SpringBoard launch sees the marker of the failed launch and boots WITHOUT the tweak; the iPad reaches the home screen. Check `/var/jb/tmp/Backport162.tripped` (exists = the guard fired) and the last lines of `/var/jb/tmp/Backport162.log`.
2. Respring / reboot userspace again: the tweak is tried once more. If it hangs again, repeat step 1 (it alternates, it does not loop).
3. To keep the tweak OUT until a fixed build is installed: create the empty file `/var/jb/tmp/Backport162.off.all` (Filza, NewTerm, SSH: `touch /var/jb/tmp/Backport162.off.all`), then install the fixed build, then delete the file and respring.
4. If even that does not help (the loader itself is suspected): delete `/var/jb/Library/MobileSubstrate/DynamicLibraries/Backport162.plist` (nothing of the tweak is injected into SpringBoard any more), or boot with tweak injection disabled as before.
5. To test a build with the guard off (e.g. to collect a crash with the tweak loaded every time): create `/var/jb/tmp/Backport162.noguard`.

Where the files are written: `/var/jb/tmp` is under the jailbreak root and survives a reboot; if a future jailbreak wipes it at boot, a hang followed by a hard reboot would lose the marker (the guard then simply does not fire; nothing else is affected).

## 4. What is NOT covered

Only the SpringBoard filter of the main dylib is guarded. Other dylibs of the package keep their own filter plists and are injected independently of the loader:

| dylib | filter | can it hang a boot? | recommendation |
|---|---|---|---|
| `Backport162BBD` (BBD.x) | `Executables = backboardd`, arm64e, addresses of 20A8372 | the highest risk (backboardd starts before SpringBoard; a hang there is a black screen / Apple logo and the SpringBoard marker is never created). It has its OWN crash loop guard (`BPD_CrashGuardTripped`: 3 strikes of short-lived backboardd launches keep the hooks out, forgotten after 30 min), which covers crashes but not a hang | keep the BBD guard; a hang in backboardd is not caught by either guard: if that ever happens, remove `Backport162BBD.plist` from DynamicLibraries (the userspace reboot then boots without it) |
| `Backport162PTR` (PTR.x) | `Executables = pointeruid`, arm64e | low (hangs there stop the pointer, not the boot), a crash is respawned by launchd | same as BBD if needed |
| `Backport162SPK` (SPK.c) | `Executables = audiomxd, mediaserverd` | low; it already has its own crash guard (8 short-lived launches keep the hooks out) | none |
| `Backport162SMT` (SMT.x) | `Bundles = com.apple.springboard, com.apple.Preferences` | it IS injected into SpringBoard, but its constructor only looks classes up and registers hooks, no singleton | move its SpringBoard half behind the loader (the loader would dlopen a second core) if it is ever extended |
| `Backport162AV` (AV.x) | `Bundles = com.apple.AVKit` | loaded wherever AVKit loads (apps, possibly SpringBoard); constructor only installs hooks | none |
| `Backport162UIK` (UIK.m) | `Bundles = com.apple.UIKit, com.apple.UIKitCore` | its constructor returns at once in SpringBoard (apps only) | none |

None of these was changed: moving them behind the guard is not trivial and safe without a device.

## 5. What CI verifies (workflow step "Verify the boot guard packaging", before the package is uploaded and published)

* the deb has `Backport162.dylib` and `Backport162.plist` in `Library/MobileSubstrate/DynamicLibraries` and the plist filters `com.apple.springboard`;
* `usr/lib/Backport162/Backport162Core.dylib` exists; nothing called `Backport162Core.*` is in TweakInject and no `Backport162Core.plist` is anywhere in the package;
* the loader has an arm64 and an arm64e slice and `otool -L` of each slice lists only `/usr/lib/...` and `/System/Library/...` (libSystem present; no libobjc, Foundation, CydiaSubstrate, libroot);
* the loader contains the core path, postinst deletes `Backport162.booting` and `Backport162.tripped`;
* `tools/bpguard_test.c` (host test of the state machine: first launch, crash before the clear -> tripped, retry, clean boot, crash after the clear, noguard, off.all, debug logging, dlopen failure, missing core, missing tmp, unremovable marker, log appended) builds with `-Wall -Wextra -Werror` and passes.

A red step stops the job before the publish job, so a package that would not load the tweak, or that has a core with a SpringBoard filter, never reaches the Sileo repo.

## 6. Symbolication

Crash recorder and Z1Diag offsets of the tweak are now offsets in `Backport162Core.dylib` (`image Backport162Core.dylib ...` in the stall log header); `Backport162.dylib` is only the loader.
