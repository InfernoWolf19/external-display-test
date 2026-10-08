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

---

## 3. PiP per display (SBWindowScenePIPManager and friends)  (DONE)

16.0 facts (decoded): `_SBPIPEndStashTabSuppressionGestureManager` is a process-wide singleton (`+sharedInstance` 0x1c635d400). `addTarget:` (0x1c635d490) adds the target to a set and, on the first target, `_addSystemRecognizers` (0x1c635d6c0) creates two
`UITapGestureRecognizer`s (`pip.stashtab.endsuppression.tap`, `pip.stashtab.endsuppression.doubletap` with 2 taps required; both `cancelsTouchesInView/delaysTouchesBegan/delaysTouchesEnded = NO`, `allowedTouchTypes = @[@0]` (direct touches only), delegate = manager, tap requires double tap to fail) and registers them with
**`[SBSystemGestureManager mainDisplayManager]`** as system gesture types `0x77` / `0x78`; `removeTarget:` removes the target, and when the set empties `_removeGestureRecognizers` removes both from the main display manager (asserting no targets are left). The delegate method returns YES for simultaneous recognition. The only client is
`SBPIPStashTabSuppressionPolicyProvider setStashTabCanBeHidden:` (0x1c635cb2c) which adds/removes itself as target (action `_tapRecognized:`) and as active-orientation observer, and which `SBPIPPegasusContainerAdapter _createOrInvalidateStashTabVisibilityPolicyProvider` (0x1c643226c) creates with `[SBSceneManagerCoordinator mainDisplaySceneManager]`.
Consequence on an external display: a stashed PiP window that is moved to display 2 can never be un-suppressed with a tap because the recognizers only exist on display 1's gesture manager.

16.2 facts (decoded):
* the manager is per scene: `initWithSystemGestureManager:` (0x1c734020c), recognizers go to that scene's `SBSystemGestureManager` with gesture types **0x78 / 0x79** (the system gesture enum was renumbered by one in 16.2; the 16.0 port keeps 0x77/0x78), `addTarget:action:` (0x1c73402e0, action is now a parameter), `removeTarget:action:` (0x1c7340400), `dealloc` removes everything.
* `SBWindowScenePIPManager` (ivars: `_stashTabSuppressionGestureManager` 0x40 new, `_globalCoordinator` 0x48, `_windowScene` 0x50): `windowSceneDidConnect:` creates it from `[scene systemGestureManager]` and registers `_windowManagementStyleDidChange:` for `SBSwitcherControllerWindowManagementStyleDidChangeNotification` with object `scene.switcherController` on every display (the three other observers stay main-display-only); `windowSceneDidDisconnect:` releases the manager;
  `addStashTabSuppressionTarget:action:` / `removeStashTabSuppressionTarget:action:` forward to it; `_windowManagementStyleDidChange:` (0x1c73400a4) enumerates the coordinator's controllers `_enumerateControllersByDescendingPriority:` and calls `-[SBPIPController setEnhancedWindowingModeEnabled:windowScene:]` (0x1c792c2ec: if the adapter responds to `pipController:didUpdateEnhancedWindowingModeEnabled:windowScene:`, forward to it).
* `SBPIPSceneContentAdapter pipController:didUpdateEnhancedWindowingModeEnabled:windowScene:` (0x1c77eff9c): for each `containerViewControllersOnWindowScene:`, `hostedAppSceneHandle` gets `setWantsEnhancedWindowingEnabled:` and the live scene `updateSettingsWithBlock:` sets `UIMutableApplicationSceneSettings.enhancedWindowingEnabled` (block 0x1c77f015c) -> PiP-hosted app scenes follow the Stage Manager state of their display.
* `SBPIPPegasusContainerAdapter _createOrInvalidateStashTabVisibilityPolicyProvider` (0x1c78e23d4): creates the provider with `[[pipVC _sbWindowScene] sceneManager]` and `[[pipVC _sbWindowScene] pictureInPictureManager]` (`initWithObserver:bannerManager:sceneManager:pipManager:`, new weak ivar `_pipManager` +0x48; asserts both non-nil). `setStashTabCanBeHidden:` (0x1c7802b6c) uses `[_pipManager addStashTabSuppressionTarget:self action:@selector(_tapRecognized:)]`.

Port (group `G3B_PiP`, switch `g3b_pip`, all APIs used exist in 16.0: `systemGestureManager`, `containerViewControllersOnWindowScene:`, `hostedAppSceneHandle`, `setWantsEnhancedWindowingEnabled:`, `_enumerateControllersByDescendingPriority:`, `UIViewController(FBSDisplayConfiguration) _sbWindowScene`):
* new class `BPPIPEndStashTabSuppressionManager` (verbatim behaviour above, 16.0 gesture numbers 0x77/0x78), stored as an associated object of `SBWindowScenePIPManager` (the 16.0 class has no ivar for it);
* hooks on `SBWindowScenePIPManager` windowSceneDidConnect:/Disconnect:, `%new` add/remove target and `_windowManagementStyleDidChange:`;
* `%new SBPIPController setEnhancedWindowingModeEnabled:windowScene:` and `%new SBPIPSceneContentAdapter pipController:didUpdateEnhancedWindowingModeEnabled:windowScene:`;
* `SBPIPPegasusContainerAdapter _createOrInvalidate...` re-creates the provider with the scene's own scene manager and stores the scene's PiP manager as an assign-association on the provider; `SBPIPStashTabSuppressionPolicyProvider setStashTabCanBeHidden:` is replaced for providers that carry that association (others fall back to `%orig`).
UNSURE: (a) the notification poster is `g3switcher` of group3-plumbing.hooks.m (without it the Stage Manager toggle never reaches `_windowManagementStyleDidChange:`); (b) `SBSystemGestureManager` ownership: if a scene's system gesture manager is nil at connect time the gesture manager is not created and the provider quietly falls back to the 16.0 singleton path only when `%orig` is taken; check on a device with a stashed PiP window on display 2 (tap on the tab must un-hide it).

---

## 2. Per-window-scene hosted keyboard window controller (SBMedusaHostedKeyboardWindowController)  (DONE; UNSURE:keyboard focus display, see 2.5)

### 2.1 16.0 structure (decoded)
`SBMainDisplaySceneManager` owns `_medusaHostedKeyboardWindow` (+0x118) and `_isUsingMedusaHostedKeyboardWindow` (+0x158). Every use of these two ivars is inside five methods (found with an adrp/ldrsw scan of the whole binary: `addrxref.py`): `_medusaHostedKeyboardWindow`, `_isUsingMedusaHostedKeyboardWindow`,
`newMedusaHostedKeyboardWindowLevelAssertionWithPriority:windowLevel:`, `_updateMedusaHostedKeyboardWindowForScene:isForeground:` (0x1c63d7070) and `.cxx_destruct`. Callers: `SBSpotlightMultiplexingViewController viewDidAppear:`, `SBModalLibraryController _evaluateKeyboardWindowLevelAssertion` (level assertion),
`SBKeyboardHomeAffordanceController _getHomeGrabberContainingView:isAlwaysPortrait:` (window + using flag, and it is the only observer: `sceneManagerUsingMedusaHostedKeyboardWindowDidChange:`), `SBFluidSwitcherViewController _acquireKeyboardSuppressionAssertionForMode:`, and the update triggers (`SBSceneLayoutWorkspaceTransaction _updateScenesForTransitionCompletion`, PiP transactions/adapter, `SBMoveFloatingApplicationGestureWorkspaceTransaction _begin`, `_updateLevelAndBackgroundSettingsForScene:transitionContext:`, the keyboard-layers diff inspector block).
`SBSystemShellExternalDisplaySceneManager _updateMedusaHostedKeyboardWindow` (0x1c63aeb94) is an empty stub.

### 2.2 16.2 structure
`SBMedusaHostedKeyboardWindowController` (ivars: `_windowScene` weak +0x10, `_keyboardLayersClientSettingsDiffInspector` +0x18, `_isUsingMedusaHostedKeyboardWindow` +0x20, `_medusaHostedKeyboardWindow` +0x28, `_observers` +0x8) is owned per window scene (`SBWindowSceneContext medusaHostedKeyboardWindowController`, forwarded by `SBWindowScene`).
Methods (all decoded): `initWithWindowScene:`, `invalidate` (window `invalidate`, nil it, `removeAllObservers`), `isKeyboardVisibleForSpringBoard` (= 16.0 `_isKeyboardVisibleForSpringBoard`, global), `shouldKeyboardBeWindowSizedForHostWithIdentity:` (host scene of the identity token, its app, `uiSettings.enhancedWindowingEnabled && ![app supportsChamoisSceneResizing]`), `newMedusaHostedKeyboardWindowLevelAssertion...` (forward to the window unless `[UIKeyboard usesInputSystemUI]`),
`updateMedusaHostedKeyboardWindow` (look up the keyboard scene `__UIKeyboardArbiter_SceneIdentifier` = `com.apple.UIKit.remote-keyboard`, call the ForScene variant), `add/removeObserver:` (weak hash table, main queue asserted; callouts `usingMedusaHostedKeyboardWindowDidChange`), `_keyboardLayersClientSettingsDiffInspector` (`FBSSceneClientSettingsDiffInspector` observing layers and `preferredSceneHostIdentity` -> update),
`scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` (for the keyboard scene id, `!usesInputSystemUI`, scene foreground -> build `SBKeyboardClientSettingObserverContext{scene,diff,settings}` and evaluate the inspector), `scene:didCompleteUpdateWithContext:error:` (keyboard scene, `!usesInputSystemUI` -> `updateMedusaHostedKeyboardWindowForScene:isForeground:&scene.settings.isForeground`).

`updateMedusaHostedKeyboardWindowForScene:isForeground:` (0x1c76275f4) compared line by line with 16.0 (the log strings of the 16.2 version name every decision, verified in the disassembly):
1. return if `[UIKeyboard usesInputSystemUI]`; **new:** return unless `kbScene.settings.sb_displayIdentityForSceneManagers isEqual: windowScene._fbsDisplayIdentity`.
2. `fg = kbScene.settings.isForeground`; `hostId`/`hostToken` = client settings `preferredSceneHostIdentifier` / `preferredSceneHostIdentity`; **scene manager = `[SBSceneManagerCoordinator sceneManagerForDisplayIdentity:displayIdentity]`** (16.0: the main display scene manager).
3. host scene = `sceneFromIdentityToken:` (token), else the scene with a keyboard-proxy layer owned by the token among `externalForegroundApplicationSceneHandles` of that scene manager, else `sceneWithIdentifier:hostId` (if `hostId.length`).
4. no host -> forMedusa NO. Otherwise `handle = [sceneMgr existingSceneHandleForScene:host]`; hostFg = handle in `externalForegroundApplicationSceneHandles` ? YES : (`handle.sceneIfExists.workspaceIdentifier` ? `handle.scene.settings.isForeground` : NO); `app` = application of the host's client process; presented layer types of `host.uiPresentationManager.defaultPresentationContext`.
   * `hostFg && (types & ~2) == 0` -> YES, out foreground = YES ("keyboardIsForMedusa is YES because the scene is foreground and can't present the keyboard itself");
   * else `hostId == FBSystemAppBundleID()` -> NO, out foreground = YES ("preferredHostIdentifier is SpringBoard");
   * else if `windowScene.switcherController.isChamoisWindowingUIEnabled && host.uiSettings.enhancedWindowingEnabled && [app supportsChamoisSceneResizing]` (16.0: `!isClassic`) -> YES, out foreground unchanged ("Chamois window UI is enabled");
   * else NO, out foreground = NO ("preferredHostIdentifier's scene can host keyboard itself").
5. `[[SBWorkspace mainWorkspace] pipCoordinator] isPresentingPictureInPictureRequiringMedusaKeyboard` -> YES, out foreground = YES.
6. create `SBMedusaHostedKeyboardWindow initWithWindowScene:[windowSceneManager windowSceneForDisplayIdentity:...] keyboardScene:` once; `window setHidden:!forMedusa`; `[SBMainSwitcherControllerCoordinator sharedInstance] noteKeyboardIsForMedusaWithOwningScene:host` / `noteKeyboardIsNotForMedusa` (still global in 16.2); if the using flag changed, update it and call the observers; write the out parameter.

`SBMedusaHostedKeyboardWindow` (3 changed methods + 3 new): `initWithWindowScene:keyboardScene:` registers `medusaHostedKeyboardWindowWillShow:` / `...WillHide:` for `_SBMedusaHostedKeyboardWindowWillShowNotification` / `...WillHideNotification` (object nil); `setHidden:` posts `WillHide(self)` before deactivating the presenter, `WillShow(self)` before activating it;
both handlers have the same body: `if (note.object != self && presenter.isActive) [presenter deactivate]`; `invalidate` invalidates the presenter and `_defaultWindowLevelAssertion`.

### 2.3 Port (group `G3B_KbWindow`, switch `g3b_kbwindow`)
* New class `BPMedusaHostedKeyboardWindowController` = the controller above (decoded logic, 16.0 selectors only), stored as an associated object on the `SBWindowScene` (created lazily, so the 16.0 scene class needs no ivar).
* `SBMainDisplaySceneManager` (the only 16.0 owner) keeps its public methods but they forward to the controller of the main display's window scene: `_updateMedusaHostedKeyboardWindow`, `_updateMedusaHostedKeyboardWindowForScene:isForeground:` (then fan out to the controllers of every other connected window scene, which is how the external display gets its window), `_medusaHostedKeyboardWindow`, `_isUsingMedusaHostedKeyboardWindow`, `newMedusaHostedKeyboardWindowLevelAssertion...`. The "using" flag flip is bridged to the 16.0 observer callout (`sceneManagerUsingMedusaHostedKeyboardWindowDidChange:`), so `SBKeyboardHomeAffordanceController` keeps working unchanged, and the new `usingMedusaHostedKeyboardWindowDidChange` observer API exists on the controller for code ported from 16.2.
* `SBSystemShellExternalDisplaySceneManager _updateMedusaHostedKeyboardWindow` (empty stub in 16.0) refreshes that display's controller.
* `SBMedusaHostedKeyboardWindow`: the notification pair, `%new` handlers, `%new invalidate`.
Everything is skipped (the 16.0 methods run) when `Backport162.off.g3b_kbwindow` exists.

### 2.4 Answer: where does the external-display app keyboard come from under ExtendedDisplayEnabler on 16.0?
From the single hosted keyboard window of `SBMainDisplaySceneManager`. It is created once, on the first update, with `windowScene = [windowSceneManager windowSceneForDisplayIdentity:kbScene.settings.sb_displayIdentityForSceneManagers]` and never again (`cbnz x8` around 0x1c63d77e8 skips creation when the ivar is set), and the show/hide decision uses the MAIN display scene manager's `externalForegroundApplicationSceneHandles`, which are the scene handles of apps shown on external displays by the main manager's external-display path. So the keyboard of an app running on the external display is rendered in whichever display window scene the keyboard scene was on when the window was first created, in practice the iPad panel: the keyboard appears on the iPad screen, not on the external screen. With 2.3 the keyboard scene's display identity selects the window.

### 2.5 Check on a device
UNSURE: (a) which display identity the keyboard scene reports when focus is on a window of display 2 on 16.0 (group 4 sets the active display; `SBKeyboardFocusController` has to update the keyboard scene settings: if the identity stays main the display-2 window is never shown, behaviour = 16.0); (b) `BSEqualObjects(layer.keyboardOwner, token)` receiver pair was inferred from the argument registers (token = `preferredSceneHostIdentity`); (c) tap into a text field on the external window and confirm one window shows the keyboard and the other presenter is inactive (log `hosted keyboard window` lines with `Backport162.on.log`).

---

## 5. Status bar: `options:`, per-display frontmost status bar, `screenBoundsIgnoresSceneOrientation`  (DONE)

### 5.1 `setAvoidanceFrame:...options:` (UIKit side reconstructed)
16.2 UIKit renames the interactive flag to an option mask all the way down: `UIStatusBar_Base` (0x189d722a4 `...animationSettings:options:`, 0x189d7229c keeps `isInteractive:` as a wrapper), `UIStatusBar_Modern` (0x189d72854), `_UIStatusBar` (0x189d511a4, 16.0 0x189c073a8): same body as 16.0 (transform the rect by `_effectiveScaleTransform`, skip when equal to the stored frame, otherwise notify the visual provider when the flag bit 6 of `_statusBarFlags` is set)
but the provider message is now `avoidanceFrameUpdatedFromFrame:withAnimationSettings:options:` (was `...interactively:`). Option bits (decoded in `_UIStatusBarVisualProvider_DynamicSplit` 16.2 0x189c83010 vs 16.0 0x189b3ce7c): **bit 0 = interactive** (as before), **bit 1 = apply the new avoidance frame immediately**: without it, when an item
of the status bar is currently running the reposition animation (`__UIStatusBarVisualProviderRepositionAnimationIdentifier` among `__statusBarRunningAnimations`) the update is stored in the new `deferredAvoidanceFrameUpdateBlock` and run from `addTotalCompletionHandler:` of the animation; every call also clears the pending deferred block first.
`_UIStatusBarVisualProvider_Pad` (the iPad provider, 16.0 0x189bfb37c / 16.2 0x189d44ba0) ignores the settings and the flag in both builds (`[self _updateConstraintsForAvoidanceFrame:[statusBar avoidanceFrame]]`), so on an iPad the bits have no visible effect; the producer of non-zero options is `SBSystemApertureViewController` (Dynamic Island devices only).
SpringBoard side: `SBWindowSceneStatusBarManager setAvoidanceFrame:reason:statusBar:animationSettings:options:` (16.2 0x1c736bd6c; 4-argument form passes 0) and `_applyAvoidanceFrameToStatusBar:withGlobalAvoidanceFrame:animationSettings:reason:options:` (0x1c736c3d4) call `[statusBar setAvoidanceFrame:animationSettings:options:]` when the status bar responds to it.
Port (group `G3B_StatusBar`): `%new` `options:` methods on `UIStatusBar_Base`, `_UIStatusBar` and `SBWindowSceneStatusBarManager` that forward `options & 1` to the 16.0 `isInteractive:` methods, so any ported 16.2 caller (system aperture code, the 16.2 manager body) works unchanged. The bit-1 deferral of DynamicSplit is not ported: that provider class is only selected on Dynamic Island iPhones (never on an iPad, never on an external display).

### 5.2 `-[SBWindowSceneStatusBarAssertionManager isFrontmostStatusBarPartHidden:]` per display
16.0 0x1c63f8584 vs 16.2 0x1c78a5064: identical control flow and callee sequence; the only differences are `[[SBMainSwitcherControllerCoordinator sharedInstance] layoutState]` -> `[switcherController layoutState]` (the switcher controller of the manager's own `_windowScene`, already used earlier in the method for the primary/side elements) and
`[[SBMainSwitcherControllerCoordinator sharedInstance] unlockedEnvironmentMode]` -> `[switcherController unlockedEnvironmentMode]`. Effect: the status bar of an external display follows its own layout state instead of the iPad's. Port: the 16.0 body is kept; while it runs a thread-local override makes the coordinator's `layoutState` and `unlockedEnvironmentMode` return the window scene's switcher controller values (hooks on the two getters of `SBMainSwitcherControllerCoordinator` that consult the override, `%orig` otherwise). For the main display the values are identical. Switch `g3b_statusbar`.

### 5.3 `screenBoundsIgnoresSceneOrientation`
SpringBoard 16.2 (`-[SBDeviceApplicationSceneHandle _modifyApplicationSceneSettings:fromRequestContext:entity:]` 0x1c729dfb4) sets it to `chamoisUI && displayIdentity.isExternal && supportsChamoisOnExternalDisplay ? ![app supportsChamoisSceneResizing] : NO`. Client side, it is `UIMutableApplicationSceneSettings` setter 0x1898dd7c0 / `UIApplicationSceneSettings` getter 0x1898dc6a0 = `otherSettings` flag with setting id **0x2a**, plus a diff-inspector observer `observeScreenBoundsIgnoresSceneOrientation:` (0x1898de008).
Search for readers (scan of all 4.4 M instructions of the 16.2 UIKitCore text, direct selector slot loads and `objc_stubs` calls, plus the selector tables): **no code in UIKitCore 16.2 calls `screenBoundsIgnoresSceneOrientation` or the observer** (the selectors have no `__objc_stubs` entry and no slot load, unlike e.g. `enhancedWindowingEnabled` which does), and no other class dump of the 16.2 frameworks mentions it. So in 16.2.0 the flag is plumbing for a later release and has no client-visible effect; the correct reconstruction on 16.0 is therefore "nothing to add on the client side".
UNSURE: only UIKitCore's text was scanned; a reader in another image (for example through KVC) would not be visible here. The id 0x2a may be used by a different setting in 16.0 UIKit, so the port deliberately does not write it.
