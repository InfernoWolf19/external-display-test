# Send logs (0.7.9): a Settings button that collects the tweak's logs and uploads them to a GitHub repository

Everything below comes from reading code and documentation; nothing was run on a device (section 8 lists what is unproven).

## 1. What it is, and what it is not

* A pane **Settings > Backport162** (Tweaks section) with two fields, **Repository** (`owner/name`) and **Token** (fine-grained GitHub token, Contents: write on that repository), and two buttons, **Send logs now** and **Share last report...**.
* **Nothing is automatic.** SpringBoard collects and sends a report only after the user taps *Send logs now* (or *Share instead*). No timer, no upload at boot, no upload on a crash. Without the tap the code in `RPT.x` does nothing but wait for a Darwin notification.
* The token is typed into Settings, stored in the preferences domain `com.infernowolf19.backport162` (key `reportToken`, readable only by the mobile user and system processes, not by sandboxed apps), read by SpringBoard at the moment of the upload and used only in the `Authorization` header of that one request. It is never logged (`BP_Log` prints only HTTP status + GitHub's `message` text), never part of the report, never put in the answer keys.
* The report contains the tweak's own files and some system facts (section 3); **no preferences contents**. The logs can contain bundle identifiers, scene names and similar of the apps that were open: use a **private** repository.

## 2. Architecture

```
Settings (Preferences.app, sandboxed)                SpringBoard (unsandboxed, RPT.x in Backport162.dylib)
 Backport162Prefs.bundle  (UI only)                   RPT_Setup(): notify_register_dispatch(request) on the main queue
   "Send logs now" ----- Darwin notification ------>   main queue: atomic flag test, hop to a private serial queue
        .report.request                                job: collect -> assemble -> gzip -> write local file -> upload (NSURLSession)
   spinner / "Collecting..."                           RPT_Finish: CFPreferences keys, clear the running flag, post ".report.done"
   <-------------- Darwin notification ------------
        .report.done           then reads the keys, shows the alert
```

Why two halves: Settings is sandboxed (Dopamine gives injected processes read access to the jailbreak root and write access only to `<jbroot>/var/mobile`; the crash reports and the log files are not all readable there, and a sandboxed Settings should not hold a network job). SpringBoard can read all of it and has the network. The Settings half stays tiny and is loaded by PreferenceLoader only when the pane is opened.

Files:

| file | role |
|---|---|
| `RPT.x` | SpringBoard half, plain C / Objective-C (no hooks), in `Backport162_FILES`; `RPT_Setup()` is the last call of the `%ctor` setup list in `Tweak.x` (so it only exists on the supported build 20A8372, like every other feature); `Backport162_LIBRARIES = z` |
| `Backport162Prefs/Backport162PrefsRootListController.{h,m}` | the pane (a `PSListController` subclass) |
| `Backport162Prefs/Resources/Info.plist`, `Root.plist` | bundle info (`NSPrincipalClass`), the specifier list (fields, buttons, footer text) |
| `layout/Library/PreferenceLoader/Preferences/Backport162.plist` | the PreferenceLoader entry (PSLinkCell, `bundle` Backport162Prefs, `detail` Backport162PrefsRootListController, `isController`); Theos moves `layout/` under the rootless prefix |
| `Makefile` | `BUNDLE_NAME = Backport162Prefs` next to the tweaks (`bundle.mk`); `BP_ONLY_PREFS=1` builds only the bundle, `BP_SKIP_PREFS=1` only the tweaks (used by the CI loops) |
| `control` | `Depends: mobilesubstrate, preferenceloader` |

The class is called `Backport162PrefsRootListController` (the same name in the entry plist `detail` and in `NSPrincipalClass`).

Linking the private Preferences framework: the Makefile links `-framework Preferences` when `$(SYSROOT)/System/Library/PrivateFrameworks/Preferences.framework` exists in the SDK that Theos selected, and otherwise passes `-Wl,-undefined,dynamic_lookup` (the superclass `PSListController` is then bound by dyld at load time; Preferences.app has the framework loaded). The three Preferences classes the pane touches are declared in `Backport162PrefsRootListController.h` instead of imported, so the compile does not depend on private headers (dry-run of both branches done against a checkout of Theos with fake SDK directories: the link command differs exactly in that flag).

## 3. Report format

One text document, gzip (RFC 1952, zlib `deflateInit2(level 6, windowBits 15+16)`), file name `report-<id>.txt.gz`. The id is `yyyymmdd-HHMMSS-xxxx` in the local time of the iPad (`xxxx` = 4 random hex digits).

```
Backport162 report <id> (format 1)
Made by the Send logs button ... Contains NO token and NO preferences.
NOTE: Backport162.debug did not exist ... (only when it did not)       <- the log is sparse without the debug flag
TRUNCATED FOR SIZE: ...                                                 <- only when the 4 MiB cap forced a cut
sections:
  <name> (<n> bytes)  ...
===== system (N bytes) =====
===== Backport162.crash (own crash recorder) (N bytes[; the file has M bytes, K leading (oldest) not included]) =====
===== Backport162.log ... =====          tail, at most 2 MiB
===== Backport162.log.1 ... =====        tail, at most 1 MiB
===== Backport162.daemon.log (<dir>) =====   tail, at most 256 KiB, first directory of BPDaemon.h kBPDWDirs that has the file (read only)
===== crash report index ... =====
===== crash report <file> ... =====      newest 4 of the last 3 days, head, at most 200 KiB each
===== end of report =====
```

* **system section:** report id, local time + time zone name, package version (field `Version` of the `com.infernowolf19.backport162` stanza of `<jbroot>/Library/dpkg/status`; the stanza is found by the exact line `Package: com.infernowolf19.backport162`, so `...backport162bbd` cannot match), `kern.osversion` (the build, e.g. 20A8372), `kern.osrelease`, `hw.machine`, `operatingSystemVersionString`, uptime (`kern.boottime`), pid, whether `Backport162.debug` exists (with the explanation that the log is sparse without it), the **names** of the `Backport162.*` files in `<jbroot>/tmp` (switch files `off.*`, `debug`, the logs; no contents), the **names** of the loaded images containing `Backport162` (dyld image list).
* **crash reports:** `/var/mobile/Library/Logs/CrashReporter` and its `Retired` folder, files `*.ips` / `*.crash` whose name starts with `SpringBoard`, `backboardd`, `pointeruid`, `mediaserverd`, `audiomxd` or `Preferences` followed by `-`, `_` or `.`, modified in the last 3 days; the index lists up to 20 candidates, the 4 newest overall are included. At most 2000 directory entries are looked at per directory.
* **size:** the compressed report must be at most 4 MiB. If it is larger, the oldest half of every log tail is dropped (whole lines), up to 10 passes, and the header says so (`TRUNCATED FOR SIZE`, and the section heading says how many oldest bytes are missing). In practice text compresses 8:1 and the cap is never reached.
* **memory:** about 4.3 MiB of text, the gzip (typically < 1 MiB), then for the upload base64 (x 1.34) + the JSON body (x 1.34) of the gzip: well below 12 MiB even at the 4 MiB worst case; the dpkg status file (read up to 6 MiB) is released before the logs are read (own autorelease pool).

## 4. Protocol

### Darwin notifications (no payload)

| name | from -> to | meaning |
|---|---|---|
| `com.infernowolf19.backport162.report.request` | Settings -> SpringBoard | "collect and send a report now" |
| `com.infernowolf19.backport162.report.done` | SpringBoard -> Settings | "the answer is in the preferences" |

### Preferences domain `com.infernowolf19.backport162` (`kCFPreferencesCurrentUser`, `kCFPreferencesAnyHost`)

| key | written by | meaning |
|---|---|---|
| `reportRepo` | Settings (the field) | `owner/name`; trimmed, validated by SpringBoard with `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` (and neither part `.` / `..`) |
| `reportToken` | Settings (the secure field) | trimmed; must be 8..255 printable ASCII characters without blanks |
| `reportStatus` | SpringBoard | `ok` or `error` |
| `reportMessage` | SpringBoard | human text (at most 600 characters) |
| `reportID` | SpringBoard | the id (removed when there is none) |
| `reportURL` | SpringBoard | `html_url` of the uploaded file from GitHub's answer (removed when there is none) |
| `reportFile` | SpringBoard | local path of the `.txt.gz` (removed when it could not be written) |
| `reportTime` | SpringBoard | seconds since 1970 (a number) of the answer |

Sequence in Settings: validate the fields (alert with *Share instead* if missing) -> `endEditing` -> register the observer for `.done` **first** -> post `.request` -> wait up to 150 s. On `.done` (main queue): read `reportTime`; an answer older than the request (minus 1 s) is a leftover of an earlier job and is ignored (keep waiting); otherwise show the alert. At the timeout the keys are read once more (the notification can be held back while Settings is in the background) before *"SpringBoard did not answer: is Backport162 loaded? Respring"* is shown. Leaving the pane (`viewDidDisappear`) cancels the observer and the pending timeout; the job keeps running in SpringBoard and its answer stays in the preferences for *Share last report...*.

Sequence in SpringBoard (`RPT.x`), on the private serial queue (QoS utility), after the main queue has won the atomic flag `gRPTRunning`:
1. `BP_OnName("report")` false (file `Backport162.off.report` or `Backport162.off`) -> answer `error`, "disabled: ...".
2. Less than 5 s after the start of the previous job -> answer `error`, "two requests less than 5 s apart".
3. Collect (section 3), assemble + gzip (<= 4 MiB).
4. Write `<jbroot>/var/mobile/Library/Caches/Backport162Reports/report-<id>.txt.gz` (directory 0755, file 0644, written as `.tmp` then renamed; the 5 newest `report-*.txt.gz` are kept, stale `*.tmp` removed). A write failure is not fatal: the upload still happens, `reportFile` is just not set.
5. Read `reportRepo` / `reportToken` (after `CFPreferencesAppSynchronize`). Missing -> answer `error` "no token / repository set: report saved only on the device, use Share" (with `reportFile`). Invalid repo name / token characters -> `error` with the matching text, also with `reportFile`.
6. Upload (section 5), then `RPT_Finish`: write the keys, `CFPreferencesSynchronize`, **clear the running flag, then post `.done`** (so an immediate second tap is not refused as "running").

### Upload

`PUT https://api.github.com/repos/<owner>/<name>/contents/reports/<yyyy-mm-dd>/<id>.txt.gz`, headers `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent: Backport162`, `Content-Type: application/json`, body `{"message":"report <id>","content":"<base64>"}`. Ephemeral `NSURLSession`, `timeoutIntervalForRequest` 30, `timeoutIntervalForResource` 120, `waitsForConnectivity` NO, no cookies, no cache, one upload task with a completion handler; the private queue waits on a semaphore for at most 130 s. Create the repository with at least one commit (e.g. an initial README) and a fine-grained token limited to that repository with *Contents: Read and write*.

## 5. Failure table

| situation | where handled | what the user sees |
|---|---|---|
| repository / token empty or repo malformed (Settings) | `bp_validateAndStart` | alert "Cannot upload" + *Share instead* (runs the same collection with no upload and opens the share sheet) |
| tapped twice / second request while a job runs | `_busy` in Settings; `gRPTRunning` in SpringBoard | the second tap is ignored; the one answer comes once |
| SpringBoard does not answer (tweak not loaded, build is not 20A8372, respring in the middle) | 150 s timeout in Settings (after one more read of the keys) | "SpringBoard did not answer: is Backport162 loaded? Respring and try again." |
| Settings closed / left while the job runs | observer cancelled in `viewDidDisappear` / `dealloc`; `.done` has no listener | nothing; *Share last report...* has the file |
| SpringBoard respring while the job runs | flag and queue are in memory only | the timeout above; at most a stale `report-*.tmp`, removed by the next write |
| `Backport162.off.report` / `Backport162.off` | RPT job step 1 | "disabled: ..." |
| second request < 5 s after a start | step 2 | "two requests less than 5 s apart: wait a moment and press again" |
| log missing / empty / unreadable / read error halfway | `RPT_ReadRange` + `RPT_FileSection` | a section that says "(not found: ...)", "(cannot read: ...)", "(empty)", or the bytes read before the error (heading shows the missing bytes) |
| huge logs | caps per file; halving passes for the 4 MiB cap | header says what was dropped |
| zlib error / out of memory | `RPT_Gzip` returns nil | `error` "compression failed (zlib N)" |
| cannot write the local file | `RPT_WriteLocal` | upload still happens; if it fails too the message names the write error |
| no token / repo | step 5 | `error` "no token / repository set: report saved only on the device, use Share" + file |
| token with blanks / newline | trimmed; inner blanks or non-ASCII rejected | `error` "token has blanks or unusual characters: ..." + file |
| HTTP 200 / 201 | upload completion | `ok`, "Report <id> sent" with *Copy id* |
| 401 / 403 | | "token rejected or missing Contents write permission" |
| 404 | | "repository not found or the token cannot see it" |
| 409 / 422 | | "file already exists / conflict, press again" |
| 413 | | "report too large" |
| other status | | "HTTP <code> (<GitHub message>)" |
| transport error | | `localizedDescription` + "(no network?)" |
| no completion within 130 s | semaphore timeout, task cancelled, session invalidated | "upload timed out (no network?)" |
| an exception anywhere in the job | `@try/@catch/@finally` in `RPT_RunJob`, `RPT_Finish` is idempotent per job (`gRPTSerial`) | `error` "internal error while collecting the report"; the running flag is always cleared |
| failure answers | `bp_presentResult` | alert with the message and *Share report...* when `reportFile` exists, is under `.../Backport162Reports/report-*.txt.gz`, regular, readable by Settings, <= 16 MiB |

Share sheet: the file is first copied into Settings' own temporary directory (share extensions cannot read the jailbreak root); on the iPad the sheet is a popover with an explicit source rect (a popover without a source throws). Presenting uses the top of the presented chain and does nothing when the pane is not on screen.

## 6. Switch

`report` (default ON): `<jbroot>/tmp/Backport162.off.report` makes SpringBoard answer "disabled" to a request; `Backport162.off` does the same. The pane itself cannot be switched off from the tmp directory (remove the package or `preferenceloader`'s entry). The check is made per request (cached one second like every `BP_OnName`).

## 7. Reading a report

Download `reports/<date>/<id>.txt.gz` from the repository (or take the shared file), `gunzip`, read the `system` section first, then `Backport162.crash`, then the log. The user tells the id; the file is found by `reports/*/<id>.txt.gz`.

## 8. Unproven / needs the device

* Everything: no line of this ran on a device; `RPT.x` and the controller were syntax-checked with clang against hand-written stubs of Foundation / UIKit / CoreFoundation / libdispatch / notify (no warnings with -Wall -Wextra), and the Makefile logic was dry-run with Theos's `make -n` (both link variants, `BP_ONLY_PREFS`); CI is the first real compile and link.
* Whether the Xcode SDK on the CI runner has the private `Preferences.framework` (decides between the two link variants); whether the `-undefined dynamic_lookup` variant loads cleanly with chained fixups on arm64e (Settings is arm64e).
* That PreferenceLoader (rootless) finds `Backport162.plist` in `/var/jb/Library/PreferenceLoader/Preferences` and the bundle in `/var/jb/Library/PreferenceBundles` (standard for rootless packages; Settings must be restarted once, a userspace reboot does it).
* That `PSEditTextCell` / `PSSecureEditTextCell` with `defaults` + `key` store the text before the button action runs (the button action ends editing and defers one run loop turn), and that the keys they write are visible to SpringBoard's `CFPreferencesCopyAppValue` (`CFPreferencesAppSynchronize` first).
* That the sandbox of Preferences.app allows `notify_post` / `notify_register_dispatch` for these names and reading the answer keys of that domain (the usual way tweak preference panes talk to SpringBoard), and that Settings can read the report under `<jbroot>/var/mobile/Library/Caches/Backport162Reports` (otherwise *Share report...* is simply not offered).
* That SpringBoard can use `NSURLSession` (network entitlements, DNS) and read `/var/mobile/Library/Logs/CrashReporter`; that the dpkg status file is at `<jbroot>/Library/dpkg/status` and readable (otherwise the package version reads "unknown ...").
* That the GitHub Contents API accepts the first file of a repository that has at least one commit as documented; an entirely empty repository may answer 404/409/422.
* Whether `Backport162.log` really holds what is needed without `Backport162.debug` (it is sparse by design; the report header says so).
