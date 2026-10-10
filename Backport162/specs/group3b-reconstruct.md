# Group 3b: reconstruction of the "NOT PORTABLE" pieces of group 3 (iPadOS 16.2 20C65 -> 16.0 20A8372)

Directive: nothing is left undone; "not portable" in group3-plumbing.md only meant "needs a full reimplementation". This file
reconstructs those pieces from the 16.2 disassembly. Companion code: `group3b-reconstruct.hooks.m` (Logos, same conventions as the
other hooks files). Addresses are `16.0 / 16.2` unslid vm addresses. Tags: **DONE** (behaviour fully decoded and reimplemented),
**UNSURE:<what to check>**.

Written incrementally, one section per work item (the numbering follows the work package, not the order of writing):
1 user-resize orientation chain, 2 hosted keyboard window controller, 3 PiP per display, 4 privacy preflight, 5 status bar `options:` /
`screenBoundsIgnoresSceneOrientation`, 6 new traits roles, 7 key shortcut 0x15 + banners, 8 lower-confidence items.
See the SUMMARY at the end.

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

## 4. Privacy preflight (`PDCPreflightManager` is absent in 16.0)  (DONE as a REPLACEMENT; UNSURE:region, see 4.4)

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

---

## 1. The user-resize orientation chain (DONE as an adapter + guide; UNSURE items listed per subsection)

What 16.2 does (all decoded from 20C65): while the user drags a window edge of a *classic* app (not Medusa/resizable) that is restricted to a fixed
aspect ratio but supports both portrait and landscape, the window may snap to the transposed ("orthogonal") fixed size, and the app's interface
orientation follows the window shape (wider than tall: landscape, else portrait). The orientation is stored per scene (`_interfaceOrientationFromUserResizing`,
group 3 section 1.1, already implemented by `G3_Handle`), read by the handle's orientation selection methods and by the traits glue, which turns it into a
"follow guiding participant" orientation policy. 16.0 has none of the producer, consumer, grid or guide code. Files: `group3b-reconstruct.hooks.m`, groups
`G3B_Orient` (+ classes `BPG3BTraitsGuide`, the overlay classes, `BPG3BO_InstallAdapters`). Switches (`Backport162.off.<name>`): `g3b_orient` (producer, consumer,
handle semantics), `g3b_grid` (orthogonal grid), `g3b_guide` (traits guide), `g3b_split` (content/container adapter + overlay protocol hookup).

### 1.1 Consumer `-[SBMainSwitcherControllerCoordinator switcherContentController:setInterfaceOrientationFromUserResizing:forDisplayItem:]` (16.2 0x1c76d71d0)  DONE
Both parameters asserted non-nil (`SBMainSwitcherControllerCoordinator.m:0xd9d/0xd9e`). Decoded body:
```objc
handle = [self switcherContentController:c deviceApplicationSceneHandleForDisplayItem:item];
app = [handle application];
if ([app isMedusaCapable]) return;                                   // resizable apps never follow the window shape
if (![app classicAppPhoneAppRunningOnPad]) {
    sc = [self _switcherControllerForContentViewController:c];
    if (![[sc windowScene] isExternalDisplayWindowScene] && [c contentOrientation] == o) o = 0;   // already that orientation: forget the override
}
[handle _setInterfaceOrientationFromUserResizing:o];
```
Every selector exists in 16.0 (`_switcherControllerForContentViewController:` 0x1c624d9a0, `SBFluidSwitcherViewController contentOrientation` 0x1c5fe5b98,
`SBWindowScene isExternalDisplayWindowScene` 0x1c6351b24, `switcherContent...deviceApplicationSceneHandleForDisplayItem:` 0x1c623fa88). Ported as a `%new` on the
coordinator (the `_performEventResponse:` branch of group 1b already calls it through the delegate). After the store the port asks the traits guide of that
switcher controller to refresh (1.4); 16.2 has no explicit call because its next layout evaluation does it.

### 1.2 Producer `-[SBItemResizeGestureSwitcherModifier _responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:]` (16.0 0x1c622c5dc / 16.2 0x1c76bed98)  DONE
16.2 additionally: `info = [self layoutRestrictionInfoForItem:item]` (the modifier's own override, below); `if ((info.layoutRestrictions & 0xA) == 0x2)` the performTransition response
is wrapped: `o = size.width > size.height ? 3 : 1` (csinc idiom, d9/d8 are width/height), `r = [[SBSetInterfaceOrientationFromUserResizingEventResponse alloc] initWithDisplayItem:item desiredContentOrientation:o]; [r addChildResponse:perform]; return r`.
The modifier override `-layoutRestrictionInfoForItem:` (16.2 0x1c76bf73c, absent in 16.0): `info = [super ...]; if (info.layoutRestrictions & 0xA) { sup = [self supportedContentInterfaceOrientationsForItem:item]; if ((sup & 0x6) && (sup & 0x18)) info = [SBDisplayItemGridLayoutRestrictionInfo layoutRestrictionInfoWithLayoutRestrictions:(r & ~8) restrictedSize:info.restrictedSize]; }`.
Mask encoding: the 16.2 calculator (`layoutRestrictionInfoForItem:` 0x1c75a4670) returns 0 (resizable / no app), 0xC (maximized) or 0xA (fixed), 16.0 (0x1c611a5f0) returns 0 / 4 / 2. So 16.2 `0x2` (fixed, bit 8 cleared) is "fixed with orthogonal sizes" and bit 8 is "no orthogonal". The port does **not** change the calculator (every 16.0 consumer compares `== 2` / `== 4`); it keeps 16.0's encoding and
replaces the override by the predicate `BPG3BO_ItemAllowsOrthogonal` = (16.0 mask == 2) && both orientation families supported, evaluated per call of the gesture modifier
(`handleGestureEvent:`, `_responseForGestureUpdateAtGestureEnd:`, `_responseForSceneSizeUpdateToSize:...`) and exposed to the grid code through a thread-local depth counter. The item is
`[_currentAppLayout itemForLayoutRole:_selectedLayoutRole]` (ivars read by name). The producer hook calls `%orig` first and only then wraps, so a missing response class (group 1b not installed) leaves the 16.0 behaviour.
Only the gesture modifier consults the orthogonal info in 16.2 (`_responseForGestureUpdateAtGestureEnd:` 0x1c76e9b8 calls `nearestGridSizeForProposedSize:...layoutRestrictionInfo:` with it); the calculator's own `_frameForLayoutRole:` calls (0x1c75a38e0/3bdc) use the non-orthogonal info, which is why the TLS scope is the modifier call and nothing else.
UNSURE: the sizes 3/1 are UIInterfaceOrientationLandscapeRight / Portrait from the immediates (`mov w8,#3; csinc`), confirmed; the lifetime of an orthogonal choice after the gesture ends (the handle keeps the value until `o == contentOrientation` resets it) was not observed on a device.

### 1.3 Orthogonal fixed-aspect grid  (DONE; UNSURE:candidate set and sort key, MEDIUM-LOW)
16.2 `_SBDisplayItemFixedAspectGrid` gets ivar `_supportsOrthogonalSizes` (+0x28c, set by `initWithBounds:fixedSize:supportsOrthogonalSizes:...`, computed in `-[SBDisplayItemLayoutGrid _gridForBounds:...]` as `!(mask & 8)`),
and `_buildFixedGridWithScreenScale:` (0x1c791ed14, 405 insns vs 312) rebuilds the width/height candidate list a second time with the fixed size's width and height swapped when the flag is set, then sorts
(`sortUsingComparator:`) and splits into `allWidths`/`allHeights`. The 16.0 build (0x1c6469854) fills two parallel NSNumber arrays `_widths`/`_heights` (class `_SBDisplayItemFlexibleGrid`) pairwise.
Port: `-[SBDisplayItemLayoutGrid _gridForBounds:...]` (hook): when the TLS says "orthogonal-capable modifier call" and the info mask is 2, the grid is created against a *private cache dictionary* (the 16.0 cache key `_SBDisplayItemGridCacheKey` has no orthogonal bit; the private
dictionary is swapped into the `_gridCache` ivar for the call and cleared by `clearCachedGrids`), and `-[_SBDisplayItemFixedAspectGrid _buildFixedGridWithScreenScale:]` (hook) runs `%orig`, then temporarily swaps `_fixedSize`'s width/height (ivar by name), re-runs the build through normal dispatch (guarded by a TLS re-entrancy counter), restores the size and replaces `_widths`/`_heights` with the union of both candidate sets (dedupe within 0.5 pt, sorted by width then height).
Why it is only an approximation: 16.2 also applies per-candidate fit tests that differ between the two passes (`fcmp` chains at 0x1c791ee90..0x1c791f0e8) and its comparator key is not recoverable offline.
Check on a device: resize an iPhone-only app window that supports both orientations (for example a calculator-like app); the snap points must include the landscape and the portrait window sizes; set `Backport162.off.g3b_grid` to compare.

### 1.4 Traits guiding participants (`SBSwitcherTraitsAssistant`)  (DONE; UNSURE:LiveOverlay policy interplay)
16.2 moved the 16.0 `SBSwitcherController` participant code into `SBSwitcherTraitsAssistant` and added "guiding" participants. Decoded: ivars `_guidingPortraitOnlyParticipant`(+0x20), `_guidingLandscapeOnlyParticipant`(+0x28), `_guidingSceneOrientationRequestParticipantsMap`(+0x30), `_participantUniqueIDToAssociatedParticipantMap`(+0x38), `_blockBasedPolicySpecifier`(+0x40).
* `_guidingPortraitOnlyLiveOverlay` (0x1c74d775c) / `_guidingLandscapeOnlyLiveOverlay` (0x1c74d76ec): lazily `[arbiter acquireParticipantWithRole:_SBTraitsParticipantRoleSwitcherLiveOverlay delegate:self]` (the role constant exists in 16.0 too: `SBTraitsParticipantRoleSwitcherLiveOverlay`).
* Delegate preferences (`updatePreferencesForParticipant:updater:` 0x1c74d6f68): `[updater updateOrientationPreferencesWithBlock:^(p){ [p setSupportedOrientations:0x18] }]` for the landscape guide, `0x6` for the portrait guide (and the request mask for scene-orientation-request guides). `didChangeSettingsForParticipant:context:` is empty.
* `_setupGuidingRelationshipIfNeededForParticipant:withSceneHandle:` (0x1c74d71ac): selection table in the header comment of the code (medusa: none; phone-on-pad: portrait or, with old-style mixed orientation and prefers-landscape, landscape; classic app on external display: by `contentContainerAspectRatio <= 1`; then for non-medusa apps Stage Manager on: user-resize 3/4 landscape guide else portrait guide, Stage Manager off: store `participant.currentOrientation` as the user-resize orientation); result stored `map[participant.uniqueIdentifier] = guide.uniqueIdentifier` or removed.
* `_updateAcquiredParticipantsPolicies:` (0x1c74d80d0): for each element participant with an association `participant.orientationResolutionPolicyInfo = [SBFTraitsOrientationResolutionPolicyInfo resolutionPolicyInfoForAssociatedParticipantWithUniqueID:guideID]`. It runs from `SBTraitsPipelineBlockBasedPolicySpecifier` created by `_addGuidingSpecifierIfNeeded` (0x1c74d73ec) with description `@"Switcher Traits Assistant"` and component order 6 (`NSConstantIntegerNumber`), invalidated by `_evaluateIfGuidingSpecifierIsSillNeeded` (0x1c74d7560) when the map is empty.
* `_handleUpdateRequest:` (0x1c74d7a2c), fired by notifications `SBClassicPhoneSceneOrientationPreferenceChanged` and `SBSceneGeometryOrientationRequestChanged`: `[arbiter setNeedsUpdateArbitrationWithContext:[[SBFTraitsArbiterUpdateContext alloc] initWithBuilder:^(b){ reason, forceOrientationResolution }]]`.
Port (`BPG3BTraitsGuide`, one per `SBSwitcherController`, associated object, created after `_setupSwitcherTraitsParticipantAndPolicySpecifiers`): the same two guides, the same selection table, the same policy specifier (class and init selector exist in 16.0, checked), the same notification names and update context; element participants/handles are read from the 16.0 ivars `_traitsParticipantsByElementIdentifier` and `_traitsDelegateByParticipant` (names from the 16.0 class dump, found with `class_getInstanceVariable`), scene handle via the traits delegate's `sceneHandle` (0x1c62dac00). The policy block's argument is assumed to be the acquired participant array (16.2 forwards it to `_updateAcquiredParticipantsPolicies:` which fast-enumerates it; guarded by `NSFastEnumeration`). A policy we set is taken back when the association disappears (16.2 never clears it).
Not ported: the scene-orientation-request guide map (16.2 `_guidingSceneOrientationRequestParticipantWithMask:` 0x1c74d77cc). On 16.0 the AlterEgo path in `SBTraitsSceneParticipantDelegate` (`_supportedOrientationsOverride`) keeps doing the equivalent and the handle's `_supportedInterfaceOrientationsFromSceneOrientationRequestSetup` stays 0 unless group 3's `_startAlterEgo...` hook is extended to fill it. `SBTraitsSceneOrientationRequestAssistant` itself is therefore NOT created (it is a pure refactor of AlterEgo, group 3 section 1.3).
UNSURE: (a) whether the 16.0 `SBTraitsSwitcherLiveOverlayPolicySpecifier` also assigns a resolution policy to *our* LiveOverlay guide participants (16.2's assistant sets `_liveOverlaysPolicySpecifier` policies in `updateAllParticipants:...ownPolicy:`; the port relies on the existing 16.0 specifier doing it for every participant of that role, as it does for real live overlays); if guided windows stay in the device orientation, log `[arbiter description]` and check the guide's `orientationResolutionPolicy`. (b) `contentContainerAspectRatio` (new in 16.2 `SBSwitcherController`) is approximated by the window scene coordinate space aspect.

### 1.5 Handle orientation selection  (DONE)
Group 3 `G3_Handle` already adds the user-resize read-outs to `_launching...`, `activation...`, `_resuming...`. The part that was still missing is the removal of 16.0's phone-on-pad special cases for Medusa-capable apps (group 3 section 1.2):
`_launchingInterfaceOrientationForOrientation:` runs `%orig` with `classicAppPhoneAppRunningOnPad` forced to NO (TLS-scoped hook on `SBApplication`), which makes the 16.0 code take its `goto USE_O` path exactly like 16.2 (the 16.0 branch is `chamois && phoneOnPad && !landscapeOnly -> portrait`);
`_mainSceneSupportedInterfaceOrientations` returns `0x1e` for Medusa-capable apps (16.2 0x1c72aa11c). Classic apps keep the 16.0 mask unions (rare `UIRequiresFullScreen` apps). Both hooks are inert for classic apps and live behind `g3b_orient`.
These can be installed together with `G3_Handle`: for classic apps they add nothing, for Medusa-capable apps G3's hook does not fire.

### 1.6 Content vs container orientation  (DONE as an adapter; UNSURE:rendering on a rotated container)
16.2 `SBSceneViewController -setContentReferenceSize:withContentOrientation:andContainerOrientation:` (0x1c7964bc0) stores the content orientation as before, stores the container orientation in the new ivar `_containerOrientation`, and still calls `[_sceneView _updateReferenceSize:andOrientation:]` with the **content** orientation only; `containerOrientation` is read by `SBAppContainerViewController`, the transient overlays and `SBDeviceApplicationSceneView`. 16.0 already contains the content/container split in `SBOrientationTransformWrapperView`, so the change is an API rename:
`setContentReferenceSize:withInterfaceOrientation:` -> the new 3-argument form, `contentInterfaceOrientation` -> `contentOrientation` + `containerOrientation`, `SBDeviceApplicationSceneView initWithSceneHandle:referenceSize:orientation:hostRequester:` -> `...contentOrientation:containerOrientation:hostRequester:`, handle `newSceneViewWithReferenceSize:orientation:hostRequester:` -> `newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:`.
Port (`BPG3BO_InstallAdapters`): adds `contentOrientation`, `containerOrientation` (associated object, default = content orientation) and the 3-argument setter (forwarding to the 16.0 setter) to `SBSceneViewController`, `SBAppContainerViewController` and `SBMedusaDecoratedDeviceApplicationSceneViewController` when they lack them, and the new-style scene view factory on `SBSceneHandle` (+1 return, `ns_returns_retained`).
The 5-argument `SBDeviceApplicationSceneView` init is **not** added on purpose: it would have to be an init-family override under ARC with no 16.0 caller; the portaled overlay class below calls the 16.0 factory when the new one is missing. `didMoveToWindow` of the scene view is in group 3 `G3_Snapshot`; `_windowManagementStyleDidChange:` in group 3 (`g3switcher` poster). `-_anyOverlayViewNeedsCounterRotation` (16.2 only, used by the host counter-rotation view) is NOT ported (UNSURE: only matters once the overlay wrapper classes of 1.7 are instantiated).
UNSURE: nothing in 16.0 reads our stored container orientation; that is correct for parity (16.2 callers of `containerOrientation` are the overlays below), but a window shown rotated inside a container of another orientation relies on the 16.0 transform wrapper being driven by the scene's `interfaceOrientation` from the layout state; check one portrait iPhone app in a landscape Stage Manager window.

### 1.7 Overlay classes  (DONE as classes; creator not in this package, UNSURE)
* `SBDeviceApplicationSceneOverlayBasicWrapperView : UIView` (16.2 0x1c7951818..0x1c7951864): `needsCounterRotation` NO, `addObserver:`/`removeObserver:` no-ops, properties `hostOrientation` and `shouldLayoutOverlayImmediatelyForContainerGeometryChange`.
* `SBDeviceApplicationSceneOverlayBasicWrapperViewController` (0x1c7951424..0x1c79517c4): `initWithContentViewController:`, `loadView` (creates the wrapper view, `self.view = wrapper`), `overlayView` (`loadViewIfNeeded`, wrapper), `viewWillAppear:` (`beginAppearanceTransition:YES`, `addChildViewController:`, `addSubview:` of the content view, `didMoveToParentViewController:`), `viewDidAppear:` (`endAppearanceTransition`), `viewWillDisappear:`/`viewDidDisappear:` (the mirror image), `viewDidLayoutSubviews` (content view frame = wrapper bounds). The 16.0 overlay protocols (`SBDeviceApplicationSceneOverlayView` / `...ViewController`) are attached with `class_addProtocol` when 16.0 has them; the creator is `SBDeviceApplicationSceneOverlayViewProvider -_activateIfPossible` (0x1c7951208) which asks `overlayViewProviderIsHostedInNonrotatingWindow:` (new 16.2 SBDeviceApplicationSceneViewController method, not ported: UNSURE:only used to pick this wrapper).
* `SBFluidSwitcherPortaledSceneLiveContentOverlay` (0x1c78a6520..0x1c78a6880): all 40 methods decoded; 30 are constants/no-ops (`supportedInterfaceOrientations` 0x1e, `overlayType` 4, `touchBehavior` 0, `requiresLegacyRotationSupport` NO, ...), the init creates the scene view through the handle factory (content+container orientation), forwards `setInsetForHomeAffordance:`, `setCustomContentView:livePortalView`, `setDisplayMode:1`, builds an `SBUISizeObservingView` with itself as delegate containing the portal view, and `sizeObservingView:didChangeSize:` resizes the portal to the observer's bounds. It exists for the **cross-display window drag**: the creator `SBFullScreenSwitcherLiveContentOverlayCoordinator -_updatePortaledSceneLiveContentOverlays` (0x1c74ce070) enumerates the switcher controllers of all displays (`enumerateSwitcherControllersWithBlock:`), converts the dragged app layout between them (`convertAppLayout:fromSwitcherController:toSwitcherController:`), asks the origin overlay for `newPortaledLiveContentOverlayView` (a `CAPortalLayer` with `setCrossDisplay:YES`; this protocol method already exists in 16.0) and adds the new overlay to the target display. That coordinator code needs the multi-display window-drag model (group 5, not part of this package), so the class is provided but nothing instantiates it. UNSURE:`currentStatusBarHeight` (16.2 loads a global constant) returns 0 here.

---

## 8. The lower-confidence items

**8.1 `_topAffordanceViewController:handleActionType:transitionSource:` (16.0 0x1c632ba50 / 16.2 0x1c77ccb6c)  decoded jump table (UNSURE:names of the menu items).**
`type - 9` indexes a 9-entry table at 0x1c77ccfa0 (offsets relative to 0x1c77ccc48): type 9 -> 0x1c77ccc54, 10/11/15/16 -> default 0x1c77ccf34 (no request; falls to the epilogue), 12 -> 0x1c77ccd50, 13 -> 0x1c77cce38, 14 -> 0x1c77ccf20, 17 -> 0x1c77ccf48. Each of 9, 12, 13 first calls `dismissAnimated:` on the menu and then `[[SBWorkspace mainWorkspace] requestTransitionWithOptions:displayConfiguration:builder:validator:]`; the builder blocks (symbols `..._block_invoke.66/.70/.74`):
* type 9 -> block `.66` + `_2.67`: **maximize/"Full Screen"** (the changed block already described in group 3 section 2.5: `setEntities:withPolicy:centerEntity:floatingEntity:`, `_setRequestedFrontmostEntity:`, sizing policy `AllowingLargestSize(_supportedSizingPoliciesForContentOrientation:currentInterfaceOrientation containerOrientation:switcher.interfaceOrientation)`, `attributesByModifyingAttributedSize:Unspecified`, `attributesByModifyingAttributedUserSizeBeforeOverlapping:`, `setFencesAnimations:YES`);
* type 12 -> block `.70` + `_2.71`: `setSource:` + `modifyApplicationContext:` whose body sets `requestedPeekConfiguration` (a Split View / Slide Over entry);
* type 13 -> block `.74` + `_2.75` + `_3.76`: swaps the layout roles using `SBPreviousWorkspaceEntity` (`entityWithPreviousLayoutRole:`, `setEntity:forLayoutRole:`) - the "move to the other side / swap" item;
* type 14 -> `_topAffordanceViewControllerHandleMoveToDisplayAction:transitionSource:`; type 17 -> `_topAffordanceViewControllerHandleCloseAction`.
Only the type 9 body differs from 16.0 (16.0 toggles smallest/largest, 16.2 always maximizes). **Decision: not hooked.** The only observable change is that a second tap of "Full Screen" no longer shrinks the window; replacing it needs the validator block of the request (shape not recoverable without the block descriptor) and a mistake would break the menu item that works in 16.0. If wanted later: hook the method for `type == 9`, build the request with the entity/attributes sequence above, `source = transitionSource`.
**8.2 `setChamoisWindowingUIEnabled:` `Did` half** (`-[SBMainSwitcherControllerCoordinator _rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary]`, 16.2 0x1c76db498): rewrites the per-window-scene cache `_currentWindowingModeCompatibleAppLayoutsByWindowScene` (new ivar +0x18) for every switcher whose `windowScene.windowManagementStyle` equals the new style, replacing each layout by `+_filterAppLayoutForChamois:`. 16.0 has no such cache (`_appLayouts` is filtered when read, 16.0 ivar list checked), so there is nothing to rebuild: DONE as a deliberate no-op; the `Will` half is the existing `G3_Switcher` hook of group 3.
**8.3 Fixed-grid candidate set / comparator**: see 1.3 (UNSURE, with the device test).
**8.4 `SBSwitcherController -_presentMedusaBanner:` timers, `PDCPreflightManager` region, keyboard focus display, `screenBoundsIgnoresSceneOrientation` readers**: handled in sections 7, 4, 2 and 5 with their own UNSURE notes.

---

## SUMMARY

**Complete (DONE)**: 7 (system banner types 2/3, action 0x15 deletion), 4 (privacy preflight replacement), 6 (AX / Eyedropper / Moments roles), 3 (PiP per display), 2 (per-scene hosted keyboard controller + external-display answer), 5 (status bar `options:`, per-display frontmost status bar, `screenBoundsIgnoresSceneOrientation` set but unread), 1 (user-resize chain: consumer, producer, orthogonal grid, traits guide, handle semantics, content/container adapter, overlay classes), 8 (every low-confidence item either reconstructed or decided with a reason).
**Confidence**: HIGH for 7, 2, 3, 5, 6 and the consumer/producer/handle parts of 1 (read from code, selectors verified present in 16.0); MEDIUM for 4 (region rule), 1.4 (guide: the arbiter-side behaviour depends on the 16.0 LiveOverlay policy specifier), 1.6; MEDIUM-LOW for 1.3 (candidate set and comparator are an approximation).
**Not done on purpose** (UNSURE, each with a check): scene-orientation-request guiding (stays on AlterEgo), creator of the portaled overlay (cross-display drag), top-affordance "Full Screen" no-toggle change, a native 5-argument `SBDeviceApplicationSceneView` init.
**Install order**: group 4 (active display, scale), group 1b (response class type 38 and `_performEventResponse:`), group 2 (`%new` `layoutRestrictionInfoForItem:` / `supportedContentInterfaceOrientationsForItem:` on `SBSwitcherModifier`), group 3 (`G3_Handle`, `g3switcher` poster, `G3_Snapshot`), then this file: call `BP_G3B_Setup()` once. `G3B_Orient` needs group 1b + group 2 + `G3_Handle`'s `%new` handle accessors; without them every piece degrades to the 16.0 behaviour (guards on selectors/classes). The handle hooks of 1.5 and `G3_Handle` can coexist; `G3B_Banner`/`G3B_Menu` replace the 16.0 toast path only on 16.2-style switcher controllers.
**Switches**: `Backport162.off` (all) or `Backport162.off.<g3b_banner|g3b_menu|g3b_pip|g3b_kbwindow|g3b_statusbar|g3b_orient|g3b_grid|g3b_guide|g3b_split>`; opt-ins `g3b_preflightlog`, `g3b_axroles`.
**Open questions (device checks)**: banner wording on 16.2 (7), green-tea region rule (4), keyboard focus display with focus on the external display (2), the orthogonal snap point set (1.3), guided windows follow the shape (1.4a), rotated container rendering (1.6), `currentStatusBarHeight` of the portaled overlay.
**Verification done**: `perl logos/bin/logos.pl` translates the whole hooks file without errors; no SDK compiler is available on this host, so `-Wall -Werror` was applied by review only (casts through `objc_msgSend`, `%orig` on its own line, no hard-coded ivar offsets: all ivars by name).

