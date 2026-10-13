# VIDEO-EXTDISPLAY-0.7.4: video playback with an extended display, 16.0 (20A8372) vs 16.2 (20C65)

Static analysis only (dyld caches, callee-sequence diff as in PORT-BRIEF.md; tooling in scratchpad `vx/`: `img.py`, `an.py`, `sh2.py`). Addresses are unslid vm addresses, 16.0 / 16.2.
Confidence tags: [H] read straight from code, [M] inferred from code, [L] guess / not checkable statically.

## 0. Verdict on the hypothesis

* CONFIRMED in part [H]: on BOTH builds AVKit classifies the extended display as a "second screen" video target. `-[UIWindowScene avkit_screenType]` 0x1aa0a46e4 / 0x1aa82b8ec is byte-for-byte the same logic:
  scene.screen == mainScreen or `displayConfiguration.name` hasPrefix "LCD" -> 2; `[screen _isCarScreen]` -> 1; lowercased name hasPrefix "wireless" -> 4 (AirPlay); hasPrefix "TVOut" -> 3 (wired); else 0.
  `+[UIScene avkit_secondScreenScenes]` 0x1aa0971b8 / 0x1aa81e428 keeps connectedScenes whose type is 3 or 4 (predicate block 16.0 0x1aa0a46bc: `type - 3 < 2`). `-[AVSecondScreen initWithScene:]` 0x1aa0cdf88 / 0x1aa855cc0 ignores types <= 1, `isTVOutScreen` = (type == 3),
  initial `state` = 1 (available) only when `scene.activationState <= 1` and the scene has no other windows (`-[UIScene avkit_screenHasWindowsExcludingWindow:]` is per scene, `[windowScene windows]`).
* What 16.2 does differently is NOT "mark the screen differently" and NOT in SpringBoard/mediaserverd/backboardd/WebKit/AVFCore. It is an iPad-only gate in AVKit that stops AVKit from ever connecting video to a second screen while an extended display is active (section 2). [H]
* Checked and unchanged between builds (callee sequences identical or only unrelated deltas): AVFCore `AVPlayer` `_updateConnectionToSecondScreen` 0x1961e192c / 0x1965c34f0, `_isConnectedToPhysicalSecondScreen`, `setUsesExternalPlaybackWhileExternalScreenIsActive:`, `AVPlayerLayer` `startRedirectingVideoToLayer:forMode:` / `_enterSecondScreenModeRedirectingVideoToLayer:`
  (0x19620a088 / 0x1965eb7ec), `AVExternalPlaybackMonitor`; WebKit (no external-screen term in the string diff, only `VideoFullscreenManager_FailedToEnterFullscreen` added); MediaExperience / BackBoardServices (`videoTVOut*`, `ExternalScreenType`) strings identical; SpringBoard has no video/second-screen code. UIKitCore diffs found (`UIScreen _connectScreen` 0x18902b55c / 0x189161788 now sets orientation for external "main like" screens; screen/scene classes renamed `_UIScreenFrameSpecification` -> `_UIScreenBasedSceneSpecification`; `UIWindow _canDisableMirroring`) do not touch AVKit's decision.

## 1. Mechanism on 16.0 (why it is flaky) [M, code paths are [H]]

Chain: AVKit `AVPlayerViewController` (WebKit uses it: WebCore `WebAVPlayerViewController`, `initWithPlayerLayerView:`) -> `_setUpSecondScreenConnectionIfNeeded` 0x1aa0e4d70 creates `AVSecondScreenContentViewConnection` (`requiresTVOutScreen = YES`, `addConnection:` on `+[AVSecondScreenController sharedInstance]`)
-> `_updateSecondScreenConnectionReadyToConnect` 0x1aa0e4b68 sets `readyToConnect` = showsPlaybackControls && view.window && playerController.allowsExternalPlayback && externalPlaybackType != 1 (AirPlay) && (isBeingDismissed ? conn.isReadyToConnect : YES)
-> `-[AVSecondScreenController _updateActiveConnection]` 0x1aa0a3674 -> `_targetScreen` 0x1aa0a3880 (last `AVSecondScreen` with `isAvailable`, i.e. state != 0) -> `-[AVSecondScreen connectWithSecondScreenConnection:]` 0x1aa0cdb04 creates a UIWindow on that scene ("Created second window %p on %@") and moves the content view into `AVSecondScreenViewController`.
-> `playingOnSecondScreen = YES` -> `-[AVPlayerViewController _updateExternalPlaybackIndicatorView]` 0x1aa0e3c1c shows the placeholder: `EXTERNAL_PLAYBACK_INDICATOR_VIEW_AIRPLAY_TITLE` only if externalPlaybackType == 1, else `EXTERNAL_PLAYBACK_INDICATOR_VIEW_TV_OUT_TITLE/_SUBTITLE`. (Same bodies in 16.2 0x1aa86c0e4.)
PiP-only second route: `-[AVPictureInPicturePlatformAdapter _startObservation]` 0x1aa0b1390, observation block 0x1aa0b16dc (16.2 0x1aa8386e8): `_removeSecondScreenConnection`, then if `managesWiredSecondScreenPlayback` and a player exists: `[[AVSecondScreenController sharedInstance] addConnectionForPlayer:playerLayer:]` 0x1aa0c2050 (its only caller) -> `setSecondScreenConnection:`. `avkit_wantsManagedSecondScreenPlayback` is YES only for `AVPlayerLayer` (0x1aa88f410); NO for AVPlayerViewController / PiP content VCs, so Safari's PiP goes through the AVPlayerViewController route above [M], the adapter route matters for apps with an AVPlayerLayer PiP (YouTube app etc.).
Why it matches the report: the extended display is a type 3/4 `AVSecondScreen` in every AVKit process. Availability toggles with scene activation and with "no other window on that scene", so the same video is redirected or not depending on timing and on which display the browser window is on:
(1) window on the iPad: the external screen has no window of this app -> available -> video is moved to a window on the extended display's scene; SpringBoard's Stage Manager display (`_shouldAutoHostScene:` NO for app processes) normally does not present that scene -> iPad shows the placeholder, audio only; "rarely full screen on the extended display" when something does present it [L: reason for "rare" is inferred]. (2) window on the extended display: that scene has windows -> unavailable -> normal playback; placeholder when activation/visibility races make it available. (3) home swipe -> window leaves the display -> scene becomes available and the connection activates while the PiP morph runs -> content view is re-parented to the other window during the morph (jitter) [L].
Unverified [L]: that Safari's inline YouTube playback owns an AVPlayerViewController at that moment (WebKit "fullscreen standby" keeps one); if the placeholder text is the AIRPLAY title instead of the TV_OUT title, this chain is not the cause (that branch is `externalPlaybackType == 1`, decided by the GPU-process AVPlayer / mediaserverd, unchanged between builds).

## 2. What stock 16.2 does (the actual delta) [H]

New in 16.2 AVKit: protocol method `-[AVSharedPreferencesProtocol extendedDisplayActive:]` (reply block signature `v12@?0B8`), service name string "com.apple.avkit.SharedPreferences" (absent from the 16.0 AVKit binary), new `AVPlayerViewController` members `_isReadyToConnectSynchronousChecks` 0x1aa86d424, `_setSecondScreenConnectionReadyToConnect:` 0x1aa86d0c4, ivar/property `isUpdatingSecondScreenConnectionReadyToConnect`.
`-[AVPlayerViewController _updateSecondScreenConnectionReadyToConnect]` 16.2 0x1aa86d1d8:
```
if (![self _isReadyToConnectSynchronousChecks])      { [self _setSecondScreenConnectionReadyToConnect:NO]; return; }   // 16.0 inline conditions; dismissed branch additionally needs playerController.usesExternalPlaybackWhileExternalScreenIsActive
if ([[self traitCollection] userInterfaceIdiom] != UIUserInterfaceIdiomPad) { [self _setSecondScreenConnectionReadyToConnect:YES]; return; }
if (self.isUpdatingSecondScreenConnectionReadyToConnect) return;
self.isUpdatingSecondScreenConnectionReadyToConnect = YES;                                   // byte ivar, offset var at 0x1dab29558
NSXPCConnection *c = [[NSXPCConnection alloc] initWithServiceName:@"com.apple.avkit.SharedPreferences"];
c.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AVSharedPreferencesProtocol)]; [c resume];
[c.remoteObjectProxy extendedDisplayActive:^(BOOL active){                                   // block invoke 0x1aa86d3a0
    AVPlayerViewController *s = weakSelf; if (!s) return;
    [s _setSecondScreenConnectionReadyToConnect: active ? NO : [s _isReadyToConnectSynchronousChecks]];
    s.isUpdatingSecondScreenConnectionReadyToConnect = NO; }];
```
`_setSecondScreenConnectionReadyToConnect:` 0x1aa86d0c4 = `conn = _secondScreenConnection; if (conn && conn.isReadyToConnect != v) AVLog("readyToConnect NO/YES"); [conn setReadyToConnect:v];`.
PiP adapter observation block 16.2 0x1aa8386e8: same shape, `_removeSecondScreenConnection` first; creates the connection (`addConnectionForPlayer:playerLayer:` + `setSecondScreenConnection:`) directly on non-iPad idiom, on iPad only inside the `extendedDisplayActive:` reply when `!active` (block at 0x1aa838860..0x1aa8388f8).
Net effect: on an iPad with an extended display no second-screen connection is ever made, regardless of `AVSecondScreen` availability. Mirrored/AirPlay display: service answers NO (assumed) -> old behaviour.
What the service answers is NOT checkable here [L]: `SharedPreferences.xpc` is an executable of the root filesystem, not in the dyld cache. The 16.0 service has no such method.

## 3. Faithful port (AVKit side): app processes, not SpringBoard

Must run in every process that loads AVKit (MobileSafari, SafariViewService, third party video apps). Backport162.plist currently filters only `com.apple.springboard` (and Backport162BBD only backboardd): a new filter / small package (`Filter = { Bundles = ( "com.apple.AVKit" ); }`, same 20A8372-only check) is required. Nothing in Tweak.x/G1D/G3B hooks AVKit, so no collision there; ExtendedDisplayEnabler hooks SpringBoard/backboardd (not checked for AVKit).
Do NOT call the XPC service on 16.0 (16.0 service lacks the method: the reply block would never run and `isUpdating...` would stay YES).
```
static BOOL BP_ExtendedDisplayActive(void) {          // local replacement for the service answer [L: semantics assumed]
    for (UIScreen *s in UIScreen.screens) if (s != UIScreen.mainScreen && [s _isMainLikeScreen]) return YES;
    return NO; }   // SBSystemShellExtendedDisplayControllerPolicyFactory sets setUIKitMainLike on the extended display identity: 16.0 0x1c6061288 (+0x28 at 0x1c60612b0), 16.2 0x1c74e0548 (0x1c74e0570)
%hook AVPlayerViewController
- (void)_updateSecondScreenConnectionReadyToConnect {            // 16.0 0x1aa0e4b68
    if (pad && BP_ExtendedDisplayActive()) { id c = ivar(_secondScreenConnection); if (c && [c isReadyToConnect]) [c setReadyToConnect:NO]; return; }
    %orig; }
%end
%hook AVSecondScreenController
- (id)addConnectionForPlayer:(id)p playerLayer:(id)l {            // 16.0 0x1aa0c2050; only caller = PiP adapter block 0x1aa0b16dc
    if (pad && BP_ExtendedDisplayActive()) return nil;  return %orig; }   // adapter then stores secondScreenConnection = nil, same end state as 16.2
%end
```
Faithful = gate at the two creation/readiness sites as above. A re-evaluation when the display connects/disconnects (UIScreenDidConnect/DisconnectNotification -> `[AVPlayerViewController _updateSecondScreenConnectionReadyToConnect]` on live instances) is needed because 16.2 re-runs the check from its observers; an optional last-line guard `-[AVSecondScreenController _targetScreen]` (0x1aa0a3880) returning nil while the display is extended is a deviation (log it under BP_LogEnabled()).

## 4. PiP in SpringBoard: unported 16.2 changes that explain "expand PiP -> half on iPad, half on extended" [M]

`-[SBPIPPegasusAdapter _postEnsuredInSwitcher_pictureInPictureController:didRequestStopForPictureInPictureViewController:sourceSceneSessionIdentifier:animated:]` 16.0 0x1c60b5d10 / 16.2 0x1c753a46c (177 -> 234 callees) is the "user expands PiP" path. It is NOT in WORKLIST.md, not in any spec, not hooked (grep `_postEnsuredInSwitcher`, `entityWithApplicationForMainDisplay`: nothing).
16.0 is main-display only: `[SBMainSwitcherControllerCoordinator sharedInstance] isAnySwitcherVisible`, `[[SBSceneManagerCoordinator mainDisplaySceneManager] existingSceneHandleForPersistenceIdentifier:]`, `+[SBDeviceApplicationSceneEntity entityWithApplicationForMainDisplay:withScenePersistenceIdentifier:]` 0x1c6062ce8 (both entity creations, 0x1c60b60e8 and 0x1c60b6314), then `restoreContentViewController:appSceneEntity:morphAnimatorConfigurationBlock:completion:` 0x1c6474958.
16.2 is per display: `windowScene = [pipVC _sbWindowScene]`; `_layoutStateContainsSceneForSourceSceneSessionIdentifier:bundleIdentifier:windowScene:` (new 0x1c753bdac, uses `[windowScene switcherController]`); `[sc isAnySwitcherVisible/isInAnyPeekState/unlockedEnvironmentMode/isChamoisWindowingUIEnabled]` on that scene's controller; handle via `[[SBSceneManagerCoordinator sharedInstance] sceneManagerForPersistenceIdentifier:sid]`; entity via `+entityWithApplication:scenePersistenceIdentifier:sceneHandleProvider:displayIdentity:` (16.0 0x1c60623d0, exists) with `[sceneHandle displayIdentity]`; then
`targetWS = scene.settings.isForeground ? [[windowSceneManager] windowSceneForDisplayIdentity:scene.settings.displayIdentity] : nil` (0x1c753a8c0..0x1c753a908). If `targetWS && targetWS != pipWindowScene` (cross display, 0x1c753a920..0x1c753a9d4): no morph; `[pipController stopPictureInPictureForApplication:sceneSessionPersistentIdentifier:animated:(!layoutContainsScene on targetWS) completionHandler:]` whose block (0x1c753af5c / 0x1c753af6c) calls `showAllContentOnWindowScene:animated:` and `setActivatingEntity:`; otherwise the 16.0 flow with the scene's own controller, plus new `_activateSceneWithPersistenceIdentifier:pictureInPictureViewController:completion:` 0x1c753c584 (`createRequestWithOptions:displayConfiguration:` of the scene's display, entity with display identity) and `restoreContentViewController...` at 0x1c753ae74. Exact branch conditions at 0x1c753a9ec..0x1c753ad54 not decoded [L].
Companion: `-[SBPIPPegasusContainerAdapter performStopAnimationWithFinalInterfaceOrientation:finalLayerFrame:completionHandler:]` 16.0 0x1c64312bc / 16.2 0x1c78e11bc: 16.2 resolves the source scene's window scene (`sourceSceneSessionPersistentIdentifier` -> handle -> `sceneIfExists.settings`) and, inside the `performAfterInFlightAnimationsComplete:` block (0x1c78e145c), if that window scene exists and differs from the PiP's `_sbWindowScene` it hides the PiP container view (`[[vc view] setHidden:YES]`) before `_performStopAnimation...` (16.0 0x1c6431440 / 16.2 0x1c78e14e8, same name in both). 16.0 never hides it: the PiP layer morphs on its own display while the restored window appears on the other one = the reported split image.
Also new in 16.2, no 16.0 counterpart: `-[SBPIPPegasusAdapter pictureInPictureController:requestActivationOfSceneWithPersistenceIdentier:pictureInPictureViewController:completion:]` 0x1c753c574 (delegate callback; consumer is PegasusUI, not present in 16.0).
Relation to existing G1D groups: `g1d_piprestore` (G1D.x `SBMainWorkspace createRequestWithOptions:` + `tPipRestoreEntity`) takes the display from the entity's scene handle, but 16.0 builds the entity with `entityWithApplicationForMainDisplay:` so the display is always the main one: that group cannot fix this. `g1d_pipinsets` already overrides `+[SBMainSwitcherControllerCoordinator sharedInstanceIfExists]` through the thread local `tOverlayInsetsSC`; the new hook needs the same trick for `sharedInstance` and `sharedInstanceIfExists` (both are used in 0x1c60b5dcc..0x1c60b5fd0) and for `mainDisplaySceneManager` (0x1c60b5e5c) with its own thread local (do not reuse `tOverlayInsetsSC`).
Port shape (SpringBoard, new group in G1D.x, kill switch e.g. `g1d_pipstop`): (a) add `_layoutStateContainsSceneForSourceSceneSessionIdentifier:bundleIdentifier:windowScene:` (16.0 body 0x1c60b7228 with the switcher controller of the given window scene instead of the coordinator) and `_activateSceneWithPersistenceIdentifier:...` via class_addMethod; (b) replace `_postEnsuredInSwitcher_...` completely following the 16.2 listing above (it is ~560 instructions, a hook that only swaps the main-display calls is not enough because of the new cross-display branch); (c) prepend the hide step to `performStopAnimation...`.

## 5. Jitter into PiP and OPEN-ISSUES 8

Static result: the wobble in OPEN-ISSUES 8 (G1D `sourceContentFrameForAnimator:` / `_sourceAppLayoutFrameForSourceView:` container frames, `G1D_PIPDS_ContainerFrame`) is a different, already-ported layer: 16.2 `SBPIPController homeScreenInitialPIPFrameForWindowScene:...` 0x1c6478df8 / 0x1c792e814, `SBPIPMorphAnimatorDataSource targetFinalFrameForAnimator:` 0x1c60b7fec / 0x1c78304b0 and `SBViewMorphAnimator _source:finalCenterWithFinalScale:contentFrame:targetFinalFrame:` 0x1c61f3afc / 0x1c7681f9c differ only by logging and where `gestureInitiated` is read [M, selector sequences]; no display-dependent frame math was found in them.
Candidates for the jitter that a faithful 16.2 change DOES cover: the AVKit re-parenting during the morph (section 1, removed by section 3). Candidates it does not cover: the OPEN-ISSUES 8 centered/top-left container offset (cannot be settled statically).

## 6. Device probes that settle the open points

1. Which placeholder: note the exact text; it is `EXTERNAL_PLAYBACK_INDICATOR_VIEW_TV_OUT_*` (second screen route, this report) or `..._AIRPLAY_TITLE` (route unrelated to this report).
2. AVKit os_log, subsystem `com.apple.avkit` (`__AVLog` 0x1aa0a827c; default level, format strings in the binary), in the Safari process while the placeholder is shown: `-[AVPlayerViewController _updateSecondScreenConnectionReadyToConnect] readyToConnect YES|NO`, `-[AVSecondScreen setState:] %@ -> %@`, `-[AVSecondScreenController _updateActiveConnection] %@ %@`, `-[AVSecondScreen connectWithSecondScreenConnection:] Created second window %p on %@`, error "Attempted to connect with a screen that is not available.". Presence of `Created second window ... on <display>` with the placeholder proves section 1.
3. In-process probe (hook-free, one-line logger in the new AVKit package): `[UIScreen screens]` with `displayConfiguration.name`, `_isMainLikeScreen`, `mirroredScreen`, plus each scene's `[scene avkit_screenType]`; validates the `BP_ExtendedDisplayActive()` predicate.
4. SpringBoard (Backport162.debug): existing `g1d: pip -sourceContentFrameForAnimator:` lines already print direction and container; add one line at `_postEnsuredInSwitcher_...` printing pipVC `_sbWindowScene` display vs `[[handle displayIdentity]]`; if they differ on the failing "expand" the section 4 hypothesis holds.

## 7. Unsure list

Service semantics of `extendedDisplayActive:` (binary unavailable) [L]; whether Safari inline playback uses the AVPlayerViewController route at the moment of the placeholder [L]; "rarely full screen" and jitter explanations are inferences [L]; section 4 branch conditions only partly decoded [L]; the claim that 16.0 PiP expand puts both windows on screen rests on the main-display-only calls above [M].
