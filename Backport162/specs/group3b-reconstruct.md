# Group 3b: reconstruction of the "NOT PORTABLE" pieces of group 3 (iPadOS 16.2 20C65 -> 16.0 20A8372)

Directive: nothing is left undone; "not portable" in group3-plumbing.md only meant "needs a full reimplementation". This file
reconstructs those pieces from the 16.2 disassembly. Companion code: `group3b-reconstruct.hooks.m` (Logos, same conventions as the
other hooks files). Addresses are `16.0 / 16.2` unslid vm addresses. Tags: **DONE** (behaviour fully decoded and reimplemented),
**UNSURE:<what to check>**.

Written incrementally, one section per work item (the numbering follows the work package, not the order of writing):
1 user-resize orientation chain, 2 hosted keyboard window controller, 3 PiP per display, 4 privacy preflight, 5 status bar `options:` /
`screenBoundsIgnoresSceneOrientation`, 6 new traits roles, 7 key shortcut 0x15 + banners, 8 lower-confidence items.
See the SUMMARY at the end (only present when the whole package is finished).

Tooling used for this file (scratchpad `g3b/`): `fd.sh <160|162> <addr> [n]` filtered annotated disassembly, `cls.sh` method lists,
`selxref2.py` finds the code that references a selector by name (needed because selectors used as `@selector()` literals are direct
`__objc_methname` pointers in the cache, not selrefs).

---

## 7. Key shortcut action 0x15 deletion and the relocated error toasts (DONE)

### 7.1 Toasts -> system banner types 2 and 3  (DONE; wording UNSURE:compare with a 16.2 device)

What 16.0 does: `-[SBMedusaDecoratedDeviceApplicationSceneViewController layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:]`
ends with `_presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:` (0x1c632fc04). It picks the first true predicate of
`_shouldShowSplitViewNotAvailableYetMessage...` (0x1c632fe9c), `_shouldShowSplitViewNotSupportedMessage...` (0x1c632fff8),
`_shouldShowMultipleWindowsNotSupportedMessage...` (0x1c6330230) and calls
`[_topAffordanceViewController presentTransientMessageWithImage:title:subtitle:duration:animated:YES]` with the SF symbols
`rectangle.split.2x1.slash` (first two) / `rectangle.on.rectangle.slash`, titles `TOP_AFFORDANCE_ERROR_TITLE_{NOT_AVAILABLE_YET,SPLIT_VIEW,MULTIPLE_WINDOWS}`,
subtitles `TOP_AFFORDANCE_ERROR_SUBTITLE_USE_DRAG_AND_DROP` (not-available-yet) / `TOP_AFFORDANCE_ERROR_SUBTITLE`.

What 16.2 does: the decorated VC no longer presents anything. `-[SBFullScreenSwitcherLiveContentOverlayCoordinator
_presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:medusaViewController:]` (0x1c74cc740), called with the medusa view
controller, runs (decoded instruction by instruction):

```objc
SBSwitcherController *sc = [[self _sbWindowScene] switcherController];          // _sbWindowScene of the coordinator, i.e. THIS display
if      ([self _shouldShowSplitViewNotSupportedMessage...:ctx medusaViewController:vc])       [sc _presentMedusaBanner:2 fireInterval:0.0 dismissInterval:1.5];
else if ([self _shouldShowMultipleWindowsNotSupportedMessage...:ctx medusaViewController:vc]) [sc _presentMedusaBanner:3 fireInterval:0.0 dismissInterval:1.5];
```
The two predicates were diffed against the 16.0 ones (0x1c74cc800 / 0x1c74cca4c vs 0x1c632fff8 / 0x1c6330230): same calls in the same order,
same constants (lastActivationSource == 0x1b, spaceConfiguration == 1, peek validity, `supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:displayIdentity:`
using the *switcher controller of the window's scene*, `info.supportsMultiwindow`), only the receiver changed from the decorated VC to the
coordinator (which gets the VC as parameter). The "not available yet" variant is deleted. So the 16.0 predicates on the decorated VC can be
reused verbatim and only the presentation changes.

`-[SBSwitcherController _presentMedusaBanner:fireInterval:dismissInterval:]` (16.2 0x1c7605b58) generalises 16.0's
`_presentMedusaEducationBanner` (0x1c617ddac, still present in 16.2 at 0x1c7605aa0 as a wrapper: `_presentMedusaBanner:((peekConfigurationIsValid && [appLayout itemForLayoutRole:<const>] != nil) ? 0 : 1) fireInterval:0.7 dismissInterval:0`):
1. `ls = [self _currentLayoutState]`; `banner = [[SBMedusaBannerViewController alloc] initWithType:type orientation:ls.interfaceOrientation peekConfiguration:ls.peekConfiguration]` stored in the (existing) ivar `_medusaBannerViewController` (+0x18);
2. if `dismissInterval > 0` and the new ivar `_medusaBannerDismissTimer` (+0x28) is nil, create `BSAbsoluteMachTimer initWithIdentifier:@"SBMainSwitcherCoordinator.medusaBannerDismissTimer"`;
3. create the present timer (existing ivar +0x20, id `SBMainSwitcherCoordinator.medusaBannerPresentTimer`) if nil, `cancel`, then
   `scheduleWithFireInterval:fireInterval leewayInterval:0.05 queue:dispatch_get_main_queue() handler:^{ ... }`;
4. handler (0x1c7605d38): `[presentTimer invalidate]; presentTimer = nil; [[SBApp bannerManager] postPresentable:banner withOptions:1 userInfo:nil error:nil]`;
   `[dismissTimer cancel]; [dismissTimer scheduleWithFireInterval:dismissInterval leewayInterval:0.05 queue:main handler:^{ [self _dismissMedusaBanner]; }]` (handler 0x1c7605ed4). A nil `self` falls back to posting the banner from a stale pointer path (not reproduced).
`_dismissMedusaBanner` (0x1c7605f14): invalidate + nil both timers, `[[SBApp bannerManager] revokePresentablesWithIdentification:[BNPresentableIdentification uniqueIdentificationForPresentable:banner] reason:@"Dismiss Medusa Education Banner" options:0 userInfo:nil error:nil]`.

`-[SBMedusaBannerViewController _bannerView]` (16.2 0x1c782418c): jump table over `_type` 0..3 (16.0 0x1c637cd80 only distinguishes 0 and >=1).
Types 2/3 build the pill from: symbol (`rectangle.split.2x1.slash` for 2, `rectangle.on.rectangle.slash` for 3), title key
`MEDUSA_BANNER_ERROR_TITLE_SPLIT_VIEW` / `MEDUSA_BANNER_ERROR_TITLE_MULTIPLE_WINDOWS`, subtitle `MEDUSA_BANNER_ERROR_SUBTITLE` (table SpringBoard, `value:@""`),
then the common tail: `UIImageSymbolConfiguration configurationWithPointSize:15 weight:5(medium)`, `[[UIImage systemImageNamed:configuration:] imageWithRenderingMode:2]`,
a `UIImageView initWithImage:`, an empty spacer `UIView` with the image view's bounds, `PLPillView initWithLeadingAccessoryView:trailingAccessoryView:`, `tintColor = UIColor.labelColor`,
`setCenterContentItems:@[PLPillContentItem(text:title style:1), PLPillContentItem(text:subtitle style:2)]`. `initWithType:...` (0x1c7824054) stores type/orientation/peekConfiguration and
calls `loadViewIfNeeded` (so `_bannerView` runs with `_type` already set) then `setPreferredContentSize:[_pillView intrinsicContentSize]`.

Strings: the three 16.2 keys do not exist in the 16.0 `SpringBoard.loctable` (checked in the extracted 16.0 `SpringBoard.app`: only `MEDUSA_BANNER_EDUCATION_*` and `TOP_AFFORDANCE_ERROR_*` exist; English:
`TOP_AFFORDANCE_ERROR_TITLE_SPLIT_VIEW` = "Split View", `..._MULTIPLE_WINDOWS` = "Multiple Windows", `TOP_AFFORDANCE_ERROR_SUBTITLE` = "Not Supported", `..._USE_DRAG_AND_DROP` = "For now, please use drag and drop to add more windows.").
The port therefore looks up the 16.2 key first and falls back to the 16.0 key with identical wording (localised in all languages), then to English. UNSURE: the 16.2 English strings are not available offline; they are almost certainly the same words.

Port (hooks.m group `G3B_Banner`, switch `g3b_banner`): `%hook SBMedusaBannerViewController -_bannerView` (types 2/3 built as above, `%orig` otherwise);
`%new -[SBSwitcherController _bpPresentMedusaBanner:fireInterval:dismissInterval:]` / `_bpDismissMedusaBanner` (dismiss timer in an associated object, because the 16.0 class has no ivar for it; the two 16.0 ivars are set by name);
`%hook SBMedusaDecoratedDeviceApplicationSceneViewController -_presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:` replaced (not calling `%orig`): split view -> type 2, multiple windows -> type 3, "not available yet" dropped,
banner on the switcher controller of the *window's own scene* (so an external-display window shows the banner on the external display's banner host).

Check on a device: the banner must appear on the display of the window (banner manager is a single SpringBoard object; a banner posted from the external display's switcher controller is shown by the banner host of the active scene: UNSURE whether it lands on the external screen).

### 7.2 Action 0x15 (`_handleNavigateAppWindowsInStripKeyShortcut:`) deletion  (DONE)

16.0: the Stage Manager menu (`STAGE_MANAGER_MENU_TITLE`) built in `-[SpringBoard buildMenuWithBuilder:]` (0x1c5ee2a40) contains a UICommand with the selector
`_handleNavigateAppWindowsInStripKeyShortcut:` (reference at 0x1c5ee3a68; found with `selxref2.py`; input "`", modifiers 0x180000 = command+option, shift alternate
`PREVIOUS_APP_WINDOW_DISCOVERABILITY` (alternate flags 0x20000), main title `NEXT_APP_WINDOW_DISCOVERABILITY`). The handler (0x1c5ee5bb0) calls
`[[[[SBApp windowSceneManager] activeDisplayWindowScene] switcherController] performKeyboardShortcutAction:(0x15 + shiftHeld) forBundleIdentifier:nil]` (0x15 next, 0x16 previous "app window in the strip").
The only other reference is the `selectorToSwitcherAction` table in `-[SpringBoard canPerformAction:withSender:]`'s block (0x1c5ee4988).

16.2: both references use `_handleNavigateAppWindowKeyShortcut:` (renamed in-space handler, action 4); the strip command, handler and table entry are gone; the other commands of the menu are kept
(16.2 renames some discoverability titles: `ZOOM_DISCOVERABILITY` -> `ENTER_FULL_SCREEN_DISCOVERABILITY`, `*_ON_STAGE_*` strings are only in the multitasking menu).

Port (group `G3B_Menu`, switch `g3b_menu`): while `-[SpringBoard buildMenuWithBuilder:]` runs (thread-local flag), `+[UIMenu menuWithTitle:children:]` drops any child whose `action` is
`_handleNavigateAppWindowsInStripKeyShortcut:` (that is exactly how the 16.0 code builds the Stage Manager menu, 0x1c5ee3b88). The orphan handler stays defined but is unreachable (a `UIKeyCommand` only exists through the menu).
The `0x15/0x16` cases of `performKeyboardShortcutAction:` belong to group 2b (keyboard navigation) and are not touched here.

---

## 4. Privacy preflight (`PDCPreflightManager` is absent in 16.0)  (DONE as a REPLACEMENT; UNSURE:region, see 4.5)

### 4.1 What it is (decoded, HIGH)

`PDCPreflightManager` lives in a **new private framework of the 16.2 cache, `/System/Library/PrivateFrameworks/PrivacyDisclosureCore.framework`** (image at
0x20e639000, 15 KB of code; absent from the 16.0 cache, which has no string `PDCPreflight`/`PrivacyDisclosure*` outside CoreServices/ClassKitUI). Classes: `PDCPreflightManager`,
`PDCPreflightRequestHandle`, `PDCPrivacyAlertPresenter`, `PDCFileBackedConsentStore`, `PDCApplicationEventListener`, `PDCApplicationEnvironmentMonitoringHandle`, `PDCLSBackedApplicationEnvironment`, categories on
`LSApplicationIdentity`/`LSApplicationRecord`/`NSUserDefaults`. It implements the **regulatory privacy disclosure ("green tea") gate**: before a *foreground launch* of an app whose Info.plist declares
`NSRegulatoryPrivacyDisclosureVersion`, the user must have consented to that disclosure version.

* `+isPreflightFeatureEnabled` (0x20e63dea0, block 0x20e63dee4): `( os_feature_enabled(PrivacyDisclosure, preflight) || ct_green_tea_logging_enabled() ) && ( MGGetBoolAnswer("green-tea") || os_feature_enabled(PrivacyDisclosure, preflightInAllRegions) )`.
  Decoded exactly: `w = (preflightInAllRegions || isGreenTea) && (preflight || ct_green_tea_logging_enabled())`. So on a device whose MobileGestalt `green-tea` answer is NO and without the `preflightInAllRegions` flag the whole thing is OFF.
* `-_requiresPreflightForApplication:` (0x20e63db50): `[identity findApplicationRecordWithError:&e]` then `_requiresPreflightForApplicationRecord:`; (0x20e63dc00) =
  `isPreflightFeatureEnabled && record.regulatoryPrivacyDisclosureVersion != nil && ![record.regulatoryPrivacyDisclosureVersion isEqual:[consentStore userConsentedRegulatoryDisclosureVersionForBundleIdentifier:record.bundleIdentifier]]`.
  `LSApplicationRecord.regulatoryPrivacyDisclosureVersion` (reads the Info.plist key) **already exists in the 16.0 CoreServices** (UIKitCore/CoreServices dumps), so apps can be tested in 16.0.
* `-_preflightLaunchForApplication:withCompletionHandler:` (0x20e63dccc): if not required -> `dispatch_async(queue, completion(1 /*proceed*/ ,...))` and returns `+[PDCPreflightRequestHandle alreadyCompletedRequestHandle]`; if required ->
  `PDCPreflightRequestHandle initWithQueue:completionHandler:` + `[[PDCPrivacyAlertPresenter sharedPresenter] activateRemoteAlertWithIdentity:requestHandle:forcePresent:NO completionHandler:]`; the completion block maps the remote alert answer
  `{1,2,3}` through the table `{1,0,2}` (0x20e63f4a0) to the result.
* Consent store: `PDCFileBackedConsentStore` at `/var/mobile/Library/com.apple.PrivacyDisclosure/consents/<bundleID>` (UTF-8 text file holding the consented version; `PDCApplicationEventListener` deletes stale records on uninstall).
* UI: `PDCPrivacyAlertPresenter _activateAlertHandleForIdentity:settings:repsonseHandler:` (0x20e63b734) builds an `SBSRemoteAlertDefinition initWithServiceName:@"com.apple.PDUIApp" viewControllerClassName:@"PDURemoteViewController"`, passes the identity string and a `forcePresent` BOOL in
  `BSMutableSettings` and shows it with `SBSRemoteAlertHandle` (the answer arrives as a `BSAction` info NSNumber). **The alert UI is the separate app/extension `com.apple.PDUIApp`, which does not exist in 16.0.**

### 4.2 SpringBoard side (16.2)

`-[SpringBoard privacyPreflightController]` (ivar of the app delegate, `SBPrivacyPreflightController`, init 0x1c7422008: `PDCPreflightManager initWithTargetQueue:main`, a dictionary identity -> `SBApplicationPrivacyPreflightController`).
* `-requiresPreflightForApplication:(LSApplicationIdentity)` forwards to the manager.
* `-preflightLaunchForApplication:sceneIdentifier:withCompletionHandler:` (0x1c74220ac): asserts non-nil args, gets/creates the per-identity `SBApplicationPrivacyPreflightController` and `addPendingCompletion:forSceneIdentifier:`.
* `SBApplicationPrivacyPreflightController addPendingCompletion:forSceneIdentifier:` (0x1c78b4458): main thread only; append to `_pendingCompletionsBySceneIdentifier[sceneID]`; cancel a previous token; call `preflightLaunchForApplication:withCompletionHandler:` once (block 0x1c78b4678 ->
  `notePreflightFinishedWithResult:`); store the returned cancel token. `_notePreflightFinishedWithResult:cancelToken:` (0x1c78b4810) ignores stale tokens, takes the pending map, and calls each completion `(result, isLast)` in reverse order (the last registered gets `isLast=YES`).

Consumers (all gated by `requiresPreflight`):
1. `-[SBApplicationSceneUpdateTransaction initWithApplicationSceneEntity:transitionRequest:delegate:]` (0x1c78fdf4c): `_requiresPreflight = scene.settings.isForeground ? [privacy requiresPreflightForApplication:app.info.applicationIdentity] : NO`; still performs the scene update. `-_isReadyToLaunch` (0x1c78fea60) = `!_requiresPreflight`.
   `-_willBegin` (0x1c78fe4a8): if `_requiresPreflight`: audit "running preflight for %@", `preflightLaunchForApplication:sceneIdentifier:withCompletionHandler:` with block 0x1c78fe68c; else the 16.0 body.
   Completion block `(result, cancelled)`: `cancelled` -> `delegate sceneUpdateTransaction:finishedApplyingUpdate:(result == 1)`; else result 0 -> `_SBWorkspaceDestroyApplicationEntity(entity)` then finished(NO); result 2 -> finished(NO);
   result 1 -> `t = [self _createUpdateTransactionForPreflightCompletion]` (0x1c78fef68: new `SBMainWorkspaceTransitionRequest` with `eventLabel "AfterPreflightSceneUpdateTransaction"`, same source/application context, `initWithApplicationSceneEntity:transitionRequest:` which now sees the app as already consented), `t.completionBlock = finished(YES)`, `[t begin]`.
2. FrontBoard (16.2 only): `-[FBApplicationUpdateScenesTransaction _executeProcessLaunchIfAppropriate]` only schedules the process launch when the children report `_isReadyToLaunch`; `_didSatisfyMilestone:` re-evaluates (0x1a366543c). So the process is not launched before consent.
3. `-[SBToAppsWorkspaceTransaction _willBegin]` (0x1c729b8a0..): skips the *pre*-launch (`launchProcessWithContext:`) of apps that require preflight ("%@ requires preflight. Skipping prelaunch.").
4. `-[SBMainWorkspaceLayoutStateContingencyPlan transitionContextForLayoutContext:failedEntities:]` (0x1c79051a8..): for failed application entities whose `failedLaunchCount <= 1` and that require preflight, set a `SBWorkspaceEntityRemovalContext(animationStyle 0, removalActionType 1)` (so a declined/failed preflight goes back home instead of the crash fallback).

### 4.3 Why it cannot be a hook, and the replacement

The mechanism needs (a) the framework, (b) the consent UI `com.apple.PDUIApp` (not shipped in 16.0, so there is nothing that could ask the user), (c) FrontBoard changes (launch scheduling) and (d) the restructured `SBApplicationSceneUpdateTransaction`.
Without (b) a gate could only ever block (app never launches) or auto-accept. The behaviour of 16.2 on every device where the feature is off (`green-tea` false, which is every device outside the regulated regions) is exactly "proceed immediately without any visible effect", which is what 16.0 already does.

**Replacement (DONE):** the 16.2 gate is reproduced as a decision function (`BP_G3B_PreflightFeatureEnabled`, `BP_G3B_PreflightRequiredForBundle`, same formulas, `MGGetBoolAnswer("green-tea")`, `LSApplicationRecord.regulatoryPrivacyDisclosureVersion`, consent file) used only for logging: `g3b_preflightlog` (opt-in `Backport162.on.g3b_preflightlog`) writes one `BP_Log` line per
app launch (`SBApplicationSceneUpdateTransaction -initWithApplicationSceneEntity:transitionRequest:` hook) saying "would require preflight" when the 16.2 rule says yes, so the user can see on a device whether any app of theirs would ever have been gated. No launch is delayed (auto-accept semantics = 16.0 behaviour).
If a regulated-region user ever needs the real thing, the out-of-process route is: ship `PrivacyDisclosureCore` + `PDUIApp` from the 16.2 IPSW (not possible in-cache), i.e. not available; therefore the replacement is final.

### 4.4 Check on a device
`MGGetBoolAnswer(CFSTR("green-tea"))` (if YES the 16.2 rule may apply to apps that carry `NSRegulatoryPrivacyDisclosureVersion`); the opt-in log lists the apps. UNSURE:region, because the exact set of green-tea devices is decided by MobileGestalt, not by code in the cache.

---

## 6. New traits roles / scenes: Eyedropper, Moments, AX roles  (DONE; AX split opt-in because behaviour-neutral)

16.2 adds six `NSString *const` roles in SpringBoard (`_SBTraitsParticipantRole<X>`, value == the symbol name without the underscore, e.g. `@"SBTraitsParticipantRoleAXAssistiveTouchUI"`; data at 0x1d7b31e48 AXAssistiveTouchUI, 0x1d7b31e50 AXFullKeyboardUI,
0x1d7b31e58 AXVoiceControlUI, 0x1d7b31e60 AXUIServer, 0x1d7b31eb8 EyedropperUI, 0x1d7b31f20 MomentsUI) and removes `SBTraitsParticipantRoleAccessibilityDaemonUI` (16.0 0x1d7b9d3e0, value `@"SBTraitsParticipantRoleAccessibilityDaemonUI"`).
Every user of the old constant was enumerated with `addrxref.py` (all 8 places in 16.0) and compared with 16.2:

| place | 16.0 | 16.2 |
|---|---|---|
| `+[SBFullKeyboardAccessUISceneController _setupInfo]` (`traitsRole` key) | AccessibilityDaemonUI | AXFullKeyboardUI |
| `+[SBVoiceControlUISceneController _setupInfo]` | AccessibilityDaemonUI | AXVoiceControlUI |
| `+[SBAssistiveTouchUISceneController _setupInfo]` | AccessibilityDaemonUI | AXAssistiveTouchUI |
| `+[SBAccessibilityUIServerUISceneController _setupInfo]` | AccessibilityDaemonUI | AXUIServer |
| `+[SBExternalDisplayWindowSceneDelegate _individuallyManagedRoles]` (block 0x1c5fecea0 / 0x1c7467b30) | 1 role | the 4 AX roles + EyedropperUI + MomentsUI |
| `+[SBEmbeddedDisplayWindowSceneDelegate _individuallyManagedRoles]` (0x1c63a0a54 / 0x1c784ada4) | same | same |
| `-[SBTraitsExternalDisplayRolesAndDefaultPoliciesProvider orientationStageRoles]` (0x1c63b9858 / 0x1c7863f04) | same | same |
| `-[SBTraitsEmbeddedDisplayRolesAndDefaultPoliciesProvider defaultActiveOrientationBelowDrivenRoles]` (0x1c600476c / 0x1c747f35c) | same | same |

Each of the new roles sits in exactly the lists the old one sat in, so the traits policy of an AX overlay scene is **identical** in 16.2 (the split only gives each overlay its own role string). EyedropperUI/MomentsUI belong to two new
scene controllers (`SBEyedropperUISceneController`, `SBMomentsUISceneController`, 16.2-only daemons/UI) with no Stage Manager or external-display involvement: **skipped, no 16.0 consumer** (they would only be listed in the same arrays).

Port (group `G3B_AXRoles`, OPT-IN `Backport162.on.g3b_axroles`, because it is behaviour-neutral on 16.0 and every hook is a risk): the four `+_setupInfo` return `%orig` with `traitsRole` replaced by the new string, and the four list getters return `%orig` plus the four AX role strings
(old role kept). Collection kind (NSArray/NSSet/NSOrderedSet) is preserved; the result is cached per original object so identity is stable. Check on device: `Backport162.on.g3b_axroles`, enable AssistiveTouch on the external display and verify that it still rotates/stages like before.
