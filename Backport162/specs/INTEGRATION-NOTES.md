# Backport162 0.6.0 integration notes (integrator agent)

## Status
* SpringBoard tweak `Backport162` 0.6.0: all seven packages compile and link on CI (macos-latest, Xcode SDK, `make package FINALPACKAGE=1`, arm64 + arm64e).
* backboardd tweak `Backport162BBD` 0.6.0 (`../Backport162BBD`): compiles on CI.
* Nothing has been run on a device. An independent adversarial review is still to be done (STATUS.md).
* Last green runs: see the bottom of this file (updated after each push).

## Layout
| file | package | entry (called once from the single %ctor in Tweak.x, after the build guard) |
|---|---|---|
| Tweak.x | shared switches/log (BP_On, BP_OnName, BP_OptInName, BP_Log) + group 4 scale/autohost/blank | `%ctor` |
| Group4Connect.m / Group4Focus.x | group 4 (0.5.x) | `BP4_InstallIfSupported()`, `BP_G4_Setup()` |
| G1BKit.h, G1B.x | group 1b (run-time class kit shared with G1C as a static header) | `G1B_Setup()` |
| G2.x | group 2 (layout data) | `BP_G2_Setup()` |
| G2B.m | group 2b (plain ObjC, no Logos) | `BP2B_Early()` FIRST, `BP2B_Setup()` |
| G1C.x | group 1c | `G1C_Setup()` (its `%init(G1C_VCIds)` is last, after group 2's `%init(G2B)`) |
| G3.x | group 3 | `BP_G3_Setup()` |
| G3B.x | group 3b | `BP_G3B_Setup()` |
| G4B.x | group 4b | `G4B_Setup()` |
| BPShared.h | `BP162VCState` + three group-2 id helpers used by G1C | |

Order in the %ctor: BP2B_Early, %init (group 4 scale/autohost/blank), BP4_Install, BP_G4_Setup, G1B_Setup, BP_G2_Setup, BP2B_Setup, G1C_Setup, BP_G3_Setup, BP_G3B_Setup, G4B_Setup.

## Changes made to the drafts (all marked `// INTEGRATION`)
* Private switch/log helpers (`BP_G3_On`, `BP_G3B_On`, `BP2B_Enabled`, `G4B_On`, `G4B_OptIn`, `G1B_OptIn`, `BP_G3_OptIn`, `BP_G3B_OptIn`) now forward to `BP_OnName` / `BP_OptInName` (BP.h/Tweak.x): the global kill switch and `Backport162.off.<name>` apply to everything; BP.h has an enum entry and `kFeatureNames` entry for every switch.
* Cross-package rules: group 2 section 0 (`+contextProtocol`/`+queryProtocol` hooks) deleted (`BP_G2_Early` removed, group 2b `BP2B_Early` owns the protocols); the `adjustedSpaceAccessoryViewScale:forAppLayout:` entry removed from `kBPG2NewQuery` (that builder is dead code now, kept only for reference); `%init(G2)` (layout cache API) moved into `BP_G2_Setup`. The 0.5.0 `lockedptr` hook of group 4 had already been deleted in 0.5.1; `lockedptr2` (G4B) replaces it.
* G1B's helper kit moved to `G1BKit.h` (static, one copy per TU); G1B class globals used by G1C are exported (`gFilteringCls`, `gOverrideIdsCls`, `gOverrideIdsSuper`, `gGrabberRespCls`, `gOrientRespCls`, `gInvalidateRespCls`, `gF2SCls`, `gXBCls`, `gDndToAppCls`); group 2's `BP162VCState`, `BP_G2_VCStateFor`, `BP_G2_ComputeStripIds`, `BP_G2_ComputeSwitcherIds` are exported for G1C.
* Symbol collisions: the only duplicated class name was `SBContinuousExposeStripTongueView` (G1B builds a run-time class, G2B has a compiled class): `G1B_MakeClass` returns an already existing class, so the compiled G2B class wins and G1B's run-time build is skipped (G1B tongue hooks then use the G2B class). `SBContinuousExposeToHomeSwitcherModifier` is built by G1C and also by SwitcherDismissFix: whichever loads first creates it (the other `G1B_MakeClass` returns the existing class); remove SwitcherDismissFix when testing.
* Logos fixes: `%orig` followed by anything else on the same line (Logos drops the rest of the line) split onto its own lines (G1B x3, G1C x1, G2 x1, G4B x3); hooked classes need a visible `@interface` (ARC) -> a generated block of `@interface X : NSObject @end` (UIViewController for *ViewController) per file, marked `INTEGRATION: interface declarations`.
* Compile fixes: `G1B_GET` with a conditional key (G1C) -> `objc_getAssociatedObject` with `&key`; `[[cls alloc] initWithDefaultValues]` -> objc_msgSend (G1C, G2B); `[[A ?: @[]] firstObject]` parse error (G2B); `-[NSXPCListener activate]` -> `resume` (G4B, not in the iOS SDK headers); G3 selectors added to the NSObject category; `UIMenu` duplicate interface removed (G3B); `UIKit` imported in G4B before first use; backboardd tweak: `(__bridge dispatch_queue_t)object_getIvar` -> plain cast.
* Behaviour decisions (user directive "everything on"): `g1c_piles` (the pile layout, compile-time `G1C_PILES_DEFAULT 0` in the draft) is now a runtime switch that is ON by default (`Backport162.off.g1c_piles` to disable) although the spec marks its arithmetic UNSURE. Group 2 had no switch: every behaviour-changing hook of G2.x now checks `BP_On(F_G2)` (`Backport162.off.group2`).
* Opt-in (need `Backport162.on.<name>`): `group1b.apptoapp` (conflicts with G1C's Root), `g3bootorient`, `g3b_preflightlog`, `g3b_axroles`, `edunative`, `methodology0` (spec-marked opt-ins). Everything else is on.

## Stubbed / #if 0'd
* Group 2 section 0 hooks (deleted on purpose, see above). `BP_G2_BuildExtendedProtocol` and the `kBPG2New*` tables stay as unused code.
* Nothing else was disabled; no draft piece failed to compile.

## Known overlaps / things the reviewer should look at
* `SBItemResizeGestureSwitcherModifier _responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:` is hooked by G1C (adds an orientation response when `(layoutRestrictions & 0xa) == 2`) and by G3B_Orient (wraps the response in an orientation response when the item allows orthogonal): both can fire for the same gesture (same orientation value, idempotent).
* `SBDeviceApplicationSceneHandle _launchingInterfaceOrientationForOrientation:` hooked by G3 (g3handle) and G3B (g3b_orient).
* `SBWindowSceneManager activeDisplayWindowScene` hooked by Group4Focus and G4B_Arrange (G4B falls back to %orig).
* `SBFluidSwitcherViewController _updateContinuousExposeIdentifiersTransitioningFromAppLayout:...` hooked by G2 (%init(G2B)) and G1C (VCIds, replaces it; install order matters and is respected).
* `BP2B_Early()` forces `+initialize` of SBSwitcherModifier under a crash breadcrumb; it auto-writes `Backport162.off.g2bproto` if the previous launch died inside it.

## CI
