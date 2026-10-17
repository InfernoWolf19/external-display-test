# ExtendedDisplayEnabler 0.2.2 merged into Backport162 0.7.5

Sources compared: `ExtendedDisplayEnabler/Tweak.x` (branch `origin/claude/kind-volta-3s800y`, 474 lines, read completely), `Group4Connect.m`, `G4B.x`, `Tweak.x` of this package, and the user's logs (`*ExtendedDisplayEnabler.log`, `*Backport162.log`, read only). Evidence from logs is quoted by file id. Anything that comes from reading code only, not from a log, is marked CODE.

## 1. Selector by selector

EDE hooks five selectors. Load order with both packages installed (stated by the user, not verified here): ElleKit loads the TweakInject dylibs in ascending name order, so `Backport162.dylib` first and `ExtendedDisplayEnabler.dylib` after it, which makes EDE's hook the OUTER one on every selector both hook (EDE calls `%orig` = the Backport162 hook = the 16.0 body). "Order A" below is that real order, "order B" is the reverse (would happen if the dylibs were renamed or loaded differently).

| # | selector | EDE | Backport162 (0.7.4) |
|---|---|---|---|
| 1 | `-[SBDisplayManager registerDisplayControllerProvider:]` | `EDEEarlyInstall`: builds and registers the Extended provider before the others | nothing hooks it (G4B.x hooks only the clone-mirroring methods of `SBDisplayManager`) |
| 2 | `-[SpringBoard _completeStartupAfterMainSceneConnect:]` | `%orig`, then `EDEAttempt` (late install, retried 40 x 0.5 s) | nothing |
| 3 | `-[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:]` | `EDEApplyMirroring`: both values, main-queue hop, saves the choice, "ever enabled" flag, `_notifyOfPropertyChanges...`; returns without `%orig` when it handled the request | `hk_setMirroring` (Group4Connect.m, `mirrorsvc`): only the NO half, no saved choice, no flag. Also `preferredArrangementOfDisplay:relativeTo:` etc. are *added* to the class by G4B.x (`%new`, other selectors) |
| 4 | `-[SBSystemShellExtendedDisplayControllerPolicy connectToDisplayController:displayConfiguration:]` | `%orig`, then saved choice, else beta-5 default `!_areRuntimeAvailabilityRequirementsMet` (`EDEAfterPolicyConnect`, `EDEApplyDesired`) | `hk_policyConnect` (Group4Connect.m, `autoext`, runtime swizzle): `%orig`, then the 16.2 rule `setMirroringEnabled:!met`, 4 s window, user-preference observer, 16.2 notifications; plus G4B.x:955 (`edu` group, `%hook`, outside the swizzle chain: `%orig` then passive notifications if autoext does not own the policy). Tweak.x:205 hooks a different selector of the same class (`_preferredSizeInPixelsForTargetCADisplay:`), G4B.x:1048 another one (`displayController:updatePresentationWithSceneManager:...`) |
| 5 | `-[SBExternalDisplayEducationObserver displayManager:didConnectToRootDisplay:]` | `%orig` (16.0 body: forces `mirroringEnabled = YES` while neither "ever enabled" flag is set), then `EDEApplyDesired` | `hk_eduConnect`: when `autoext` is on does NOT call the original |

EDE's `EDEInstall` is the only thing Backport162 never had: nothing in Backport162 builds `SBSceneHostingDisplayControllerProvider`, so Backport162 alone cannot produce windowing mode 1 for an external display (that is why 0.7.4 said "needs ExtendedDisplayEnabler").

### What happens when both run

**Provider registration (1, 2).** Only EDE touches it, so no double registration is possible. EDE guards itself anyway: `EDEInstall` returns when `SpringBoard._extendedDisplayControllerProvider` is already set or `gProvider` exists. Log 40a519ba (EDE, 17 Oct): `registered Extended display provider ... (early, before the other providers)` at 08:48:24.329, then `Extended provider already present; nothing to do` at 08:48:24.774 (the late attempt found the early one). One registration per launch. Backport162's `provmap` (hook on `SBSceneHostingDisplayControllerProvider displayManager:didDisconnectIdentity:`) acts on EDE's provider too (same class): Backport162.log 62856308 line 554-571, `g4 provmap: dropped controller entry for AirPlay[2-3]...` at the disconnect 08:58:49, next connect works. Harmless, in fact the reason a quick replug works.

**Mirroring toggle (3).**
* Order A (real): EDE handles every valid request and returns; Backport162's `hk_setMirroring` and everything behind it never see it. Nothing is lost: the state that Backport162 keeps (the policy's `userPref`, the 16.2 display control decision) is driven by the `mirroringEnabled` default through `observeDefault:`, not by the service hook, and EDE writes that default (`setMirroringEnabled:`). The clone-mirror group of G4B.x (`bp_cloneMirroringMode`, `_setCloneMirroringMode:forDisplay:`) is driven by the display assertion preferences of the controller that ends up in charge, again a consequence of the default, not of the hook. HARMLESS. When EDE is disabled (its crash guard, its off file) the request falls through to `hk_setMirroring`, which then handles the NO half itself (without saving a choice).
* Order B: Backport162 outer. For a request "extended" (value 0) `hk_setMirroring` handles it and never calls the original, so EDE never sees it: its saved choice and the "ever enabled" flag are not updated. For "mirror" (value 1) Backport162 calls the original, EDE sees it and saves `mirror`. Result: a saved choice that lags behind what the user did. REAL CONFLICT in order B (see policy connect).
* Switches: `Backport162.off.mirrorsvc` does nothing while EDE is installed (EDE answers first). HARMLESS but confusing.

**Policy connect (4).**
* Order A: Backport162's `hk_policyConnect` runs inside EDE's. The 16.0 body sets YES, Backport162 sets `!met` (met = keyboard + pointer present) and builds its state, then EDE: no saved choice -> `gAutoDecision = met ? extended : mirror` and `EDEApplyDesired` finds the default already at the wanted value; saved choice -> EDE writes the choice (last writer wins), Backport162's `observeDefault:` fires on the main queue and sets `userPref` from the new value, so the 16.2 control decision follows. The final state is always EDE's. Log evidence for the "no choice" branch: EDE log 40a519ba 08:59:00.163 `Extended policy connect: mirroring already 0`, with Backport162.log 62856308 at the same connect `g4 autoext: connect, requirements met=1 -> mirroringEnabled=0` and `edu: display connected` at 08:59:00.158. Before 0.7.0 (EDE alone, 5 Oct) the same line read `mirroring was 1, setting 0 (saved choice)`: the inner hook had already done the work. Every one of the 18 `g4 autoext: connect` lines in the user's Backport162 logs (some logs overlap) shows `met=1`, so the two never disagreed on a real connect; the "saved choice differs from `!met`" case is CODE only. HARMLESS: same value, or the user's saved value wins; the default is written twice in one pass (YES by the 16.0 body, `!met`, then the choice), expected to be invisible but not measured.
* Order B: EDE inner (saved choice applied after the 16.0 body), Backport162 outer then runs `setMirroringEnabled:!met` over it and records `userPref = 0` (automatic). The saved choice is lost at every connect where it differs from `!met`. REAL CONFLICT in order B (CODE).

**Education observer (5).**
* Order A: EDE calls the original, which reaches `hk_eduConnect`; with `autoext` on that returns without the 16.0 body, then EDE's `EDEApplyDesired` finds nothing to correct. HARMLESS.
* The hook is dead in practice with `edu` on: the `edu` group of G4B.x makes `-[SBExternalDisplayDefaults hasShownAllExtendedDisplayEducations]` answer YES, so the 16.0 launch code never creates the old observer and nobody receives the callback. Log evidence: EDE logs of 5 Oct (before `edu`) have `education observer connect ...` lines on every connect; the log of 17 Oct (40a519ba) has four `Extended policy connect` lines (08:48:25, 08:49:29, 08:49:54, 08:59:00) and none for the observer, while Backport162.log shows `edu: display connected`.
* Order B: Backport162 outer returns without the original; EDE inner is never called. Harmless.

**Other differences found while comparing.**
* Education alert (`G4B.x` `_presentEducationAlert:`): the answer is written straight to the `mirroringEnabled` default. With EDE installed a saved choice from earlier would put the old value back at the next connect, so the alert's answer would not stick. REAL (CODE; no alert was shown in the logs). Fixed in the merge, see 2.
* `SBExternalDisplayService` hooks: EDE stores `gChoice` from the first valid request only after `_extendedModeDisplayIdentityForHardwareIdentifier:` and `_defaults` were found (nothing is saved for a request that could not be applied). Kept.

### Files, preferences, guards

| what | EDE | Backport162 | clash? |
|---|---|---|---|
| log | `<jbroot>/tmp/ExtendedDisplayEnabler.log` (+ `.1`), only while `.debug` exists | `<jbroot>/tmp/Backport162.log` (+ `.1`), only while `Backport162.debug` exists | no (different names); two debug files are needed to see both sides |
| kill switch | `<jbroot>/tmp/ExtendedDisplayEnabler.off` (disables all five hooks) | `Backport162.off`, `Backport162.off.<feature>` | no clash, but two independent switches: `Backport162.off` leaves EDE running and the other way round, and `off.autoext` / `off.mirrorsvc` have no effect on EDE's copy of the same behaviour |
| saved choice | CFPreferences domain `com.infernowolf19.extendeddisplayenabler`, key `choice` (`extended` / `mirror`) | none (the 16.2 `userPref` is per policy instance and dies with the display) | no clash; the behaviour differs: with EDE a toggle survives reconnects and relaunches, without it every connect starts from `!met` |
| crash guard | same domain, key `bootStrikes`: +1 at every launch, cleared after 25 s; 5 strikes disable every hook (including the provider install) | `BPCrash.m` recorder (no disabling), `g2bproto` breadcrumb, `Backport162BBD.strikes` (daemon directory, own file) | no shared name or key, but see below |
| other domains | none | `com.apple.springboard` key `SBExternalDisplayEducationReasons` (G4B.x) | no |

The header comment of EDE's Tweak.x still lists `Preferences/*.off`, `.choice`, `.boot` files; that is stale since 0.2.1 (the code uses `<jbroot>/tmp` and CFPreferences).

**The crash guard is a real interference.** It counts every SpringBoard launch that dies within 25 s, whatever the cause. Backport162 builds under test do crash SpringBoard (and a crash inside backboardd restarts userspace, which relaunches SpringBoard; BBD.x:706 records exactly this: the EDE log of the first install of the merged package showed five strikes). EDE log 40a519ba: `crash guard: 5 consecutive short-lived launches; tweak disabled` at 08:47:28 and 08:48:03, `disabled (kill switch or crash guard); not installing` at 08:47:32 and 08:48:04, until the user reset the counter (`loaded; saved choice=1 strikes=0` at 08:48:20). While tripped EDE installs no provider, and Backport162 has none, so the external display silently falls back to mirror-only although nothing is wrong with the display code. The counter lives in cfprefsd and survives reinstalling the package. It also contradicts the standing rule "never gate or disable features, no auto-disable safeguards" (OPEN-ISSUES), which is why the guard is not carried into the merge.

### Verdict

| item | verdict |
|---|---|
| provider registration | no overlap; EDE-only; harmless |
| setDisplayMirroringEnabled, order A | redundant, harmless; Backport162's copy is dead while EDE is installed |
| policy connect, order A | harmless (same value or EDE's choice wins, state follows through the observer) |
| education observer connect | harmless and dead with `edu` on |
| setDisplayMirroringEnabled / policy connect, order B | real conflicts (saved choice lags or is lost), only reachable with another load order |
| crash guard | real interference (disables the provider install after a crash loop that has nothing to do with EDE) |
| education alert answer vs saved choice | real conflict (CODE) |
| two kill switches, two logs, two debug files | harmless, confusing |

Why one package is still the better answer: the three overlapping hooks are the same decision implemented twice, and which copy is outermost decides whose behaviour the user gets; the single implementation removes that dependency.

## 2. What the merge does

EDE.x (new file, `EDE_Setup()` from the `%ctor` in Tweak.x after `G4B_Setup()`, behind `BP_BuildMatches()`; Makefile `Backport162_FILES` and the CI loop list it):

| EDE | now |
|---|---|
| `EDEInstall`, `EDEAttempt` (40 x 0.5 s), `EDEEarlyInstall`, the hooks on `registerDisplayControllerProvider:` and `_completeStartupAfterMainSceneConnect:` | ported unchanged into EDE.x (`%group EDE_Provider`, `%init` in `EDE_Setup`). Same classes, selectors, messages, `@try` blocks, `CFRetain` balance of the ivar, early-install re-entrancy guard, quiet early attempts. Switch `ede_provider` (`<jbroot>/tmp/Backport162.off.ede_provider`), default on, checked at every call through `BP_OnName` (also covers `Backport162.off`). Log lines `ede: ...` through `BP_Log` |
| `EDEIvar` | `BP_ObjIvar` (BP.h): same lookup by name, but refuses a non-object ivar (EDE's `object_getIvar` would have ARC retain raw bits of a scalar). All six ivars read are objects, so no behaviour change |
| `EDEDisabled` (crash guard or `ExtendedDisplayEnabler.off`) | `!BP_OnName("ede_provider")` |
| crash-loop guard (`bootStrikes`, `kMaxBootStrikes`, `kStableAfterSeconds`) | DROPPED (user rule; real interference, see above) |
| own log, debug file, off file, log rotation | DROPPED; `Backport162.log` / `.debug` / `.off` do it |
| `EDELoadChoice` / `EDESaveChoice` / `EDEPrefGet` / `EDEPrefSet` | Group4Connect.m `BP4_LoadChoice` / `BP4_SaveChoice` / `BP4_PrefGet` / `BP4_PrefSet`: same CFPreferences calls, key `choice`, values `extended` / `mirror`. Domain `com.infernowolf19.backport162`. On first start with no own value the old domain `com.infernowolf19.extendeddisplayenabler` key `choice` is read and copied over (the old domain is not modified or deleted) |
| `EDEApplyMirroring` (3) | `hk_setMirroring` rewritten after it: both values applied, main-queue hop (`BP4_Main`), `BSServiceConnection currentContext remoteProcess` in a `@try`, saved choice written only after identity and defaults were found, compare with the current default, 1 s diagnostic log (only while logging), `setExtendedDisplayEverEnabledWithHardwareReqsSatisfied:YES` for the "extended" request, `_notifyOfPropertyChangesForDisplayIdentity:requestingProcess:`, `@try` around the block. The old Backport162 pass-through of the YES half is gone (EDE applied that half itself; log of 5 Oct 21:39:58 `want=1 current=0` ... `1s after the change: isMirroringEnabled=1`). Argument checks: EDE's `NSNumber` check plus Backport162's `NSString` check of the hardware identifier; failing either calls the original, as before |
| `EDEAfterPolicyConnect` + `EDEApplyDesired` (4) | `hk_policyConnect`: after the 16.0 body, desired state = saved choice, else `!_areRuntimeAvailabilityRequirementsMet` (the beta-5 default, identical to the 16.2 rule that was already there); written only when it differs from the current default (EDE's compare). With a saved choice the policy's `userPref` is set to 1 (mirror) / 2 (extend) at the same moment, so the 16.2 control decision (`displayControllerShouldHaveControlOfDisplay:`) follows the choice exactly as the 16.0 `!mirroringEnabled` did for EDE |
| `gAutoDecision` | not needed: it only existed to feed the education observer hook (below) |
| `EDEApplyDesired` after the education observer (5) | not carried: `hk_eduConnect` does not run the original, so the forced YES never happens and the state is what the policy connect wrote. Same end state as EDE's original-then-restore; it also keeps the policy's defaults observer (user preference) from seeing a YES nobody chose |
| (new, not in EDE) | `BP4_NoteUserMirroringChoice()` called by G4B.x when the education alert's answer is written: the answer replaces the saved choice (found in the interference analysis above). Gated by `autoext` |

The same selectors are therefore hooked once each, by Group4Connect.m (`autoext`, `mirrorsvc`). Nothing else of EDE exists any more.

Packaging: `control` version 0.7.5, `Conflicts` / `Replaces` `com.infernowolf19.extendeddisplayenabler` (installing Backport162 removes it; the two cannot run together), `Provides` the same name (anything that depended on it stays satisfied). The old package's preferences plist stays on disk; only its `choice` is read.

## 3. Not verified

* Nothing was run on a device. The ElleKit load order and the nesting of the hooks are taken from the user's description; the logs above are consistent with it (inner hook ran first) but do not prove it for the selectors that did not fire.
* Switching to extended from Settings with the merged hook (all branches of `hk_setMirroring`), a saved `mirror` choice against `met = 1`, the education alert path and the one-time migration of the old `choice` were not exercised by any log (all 18 `autoext: connect` lines in the Backport162 logs have `met=1` and none shows a toggle).
* Compile check: Logos (`logos.pl`) and `clang -fsyntax-only -Wall` against hand-written stub headers (no Apple SDK on this machine) pass for `EDE.x` and `Group4Connect.m`. `G4B.x` could not be compiled here (it needs CoreGraphics / UIKit headers); its edit is a declaration and one call inside an existing block. The CI workflow is the real build.
* Whether writing a second CFPreferences domain from SpringBoard behaves like the old one (EDE did it successfully, the log of 17 Oct shows `saved choice=1` after relaunches).
