# DELTA-SWEEP-0.7.9 - every logic-changed method of SpringBoard 16.0 (20A8372) -> 16.2 (20C65), triaged

Progress log of the backlog sweep (generated from the scratchpad data; the table below is the source of truth, a resume re-reads it).

## Method

* Population: the body diff of ALL 36 330 ObjC methods present in both SpringBoard binaries (selector present in both): instruction sequence mnemonics + called selectors / symbols compared (offset-only, frame-only and constant-only differences already dropped = "same" 23 688 / "const" 11 176) -> **1 466 "logic" methods in 361 classes** (this table has exactly these 1 466 rows, incl. `.cxx_destruct` / description / protobuf rows, which are marked EXCLUDED, not dropped). The older WORKLIST.md (318 of them) and the 463 size-changed methods are subsets.
* Per row: 16.0 / 16.2 unslid cache addresses, then the verdict. `PORTED already` = an existing hook / added method / runtime class with that selector, or the 16.2 address cited in a source file; `IRRELEVANT` = not part of iPad windowing (iPhone, lock screen, Siri, CarPlay, Dynamic Island); `EQUIVALENT` = decoded, same behaviour (reason given); `TO PORT` = open; `PORTED NOW` = ported by this sweep (commit sha); `OPEN` = needs an edit in a file owned by another agent (see "NEEDS EDIT IN").
* Decoding tools (scratchpad, not in the repo): `ds/dis.py` pseudo-decompiler of one function, `ds/dd.py` normalised 16.0 -> 16.2 diff of one method; rows with the same called-selector multiset were diffed for constants / branches.

## Counts

| verdict | rows |
|---|---|
| PORTED already | 396 |
| PORTED NOW | 50 |
| EQUIVALENT | 186 |
| IRRELEVANT | 278 |
| EXCLUDED | 117 |
| TO PORT | 16 |
| OPEN | 21 |
| CANNOT | 1 |
| not yet triaged (this sweep is in progress) | 334 |
| **total** | **1466** |

Per family: F1: CANNOT 1, EQUIVALENT 40, EXCLUDED 18, IRRELEVANT 6, NOT PORTED 10, OPEN 2, PENDING 38, PORTED 36, PORTED NOW 10, TO PORT 4; F2: EQUIVALENT 27, EXCLUDED 3, IRRELEVANT 24, OPEN 2, PENDING 18, PORTED 5, PORTED NOW 7, TO PORT 2; F3: EQUIVALENT 63, EXCLUDED 41, IRRELEVANT 8, NOT PORTED 40, OPEN 1, PENDING 191, PORTED 286, PORTED NOW 26, TO PORT 10; F4: EQUIVALENT 18, EXCLUDED 8, OPEN 16, PENDING 4, PORTED 24, PORTED NOW 4; F5: EXCLUDED 1, PENDING 5, PORTED 2; F6: EQUIVALENT 15, EXCLUDED 8, IRRELEVANT 22, NOT PORTED 12, PENDING 31, PORTED 11, PORTED NOW 3; F7: EXCLUDED 9, IRRELEVANT 6, PENDING 34, PORTED 23; F8: EQUIVALENT 23, EXCLUDED 29, IRRELEVANT 212, NOT PORTED 5, PENDING 13, PORTED 9

## F1 Window scene / scene manager / main workspace / scene handles (165)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBAbstractWindowSceneDelegate | `-_configureForConnectingWindowScene:windowSceneContext:` | 0x1c600c4e8 | 0x1c74870c8 | TRIAGE PENDING |
| SBAbstractWindowSceneDelegate | `-sceneDidDisconnect:` | 0x1c600cab8 | 0x1c748772c | PORTED already: hook in G4B.x:1556 |
| SBApplication(Classic_Internal) | `-_calculateSupportedTypesLazilyIfNecessary` | 0x1c5ec6f58 | 0x1c7339fb0 | TO PORT: iPhone-only (classic) app window mode selection: 16.2 adds the 1024 supported type and isTigrisLinked / isSydneyLinked rules (652 insns); effect limited to the window shape of iPhone-only apps, decode pending |
| SBApplication(Classic_Internal) | `+_defaultLaunchingSizeForDisplayConfiguration:classicMode:` | 0x1c5ec8834 | 0x1c733bc90 | 7dd10ca: Y5Apps.x y5_classicsize (classic mode size table on every display) [sha eb694cd] |
| SBApplication(Classic_Internal) | `-_calculateSupportedTypesForSplashBoard` | 0x1c5ec8d2c | 0x1c733c13c | TO PORT: iPhone-only (classic) app window mode selection: 16.2 adds the 1024 supported type and isTigrisLinked / isSydneyLinked rules (652 insns); effect limited to the window shape of iPhone-only apps, decode pending |
| SBApplication(Classic_Internal) | `-_classicModeFromSupportedTypes` | 0x1c5ec8f44 | 0x1c733c334 | TO PORT: iPhone-only (classic) app window mode selection: 16.2 adds the 1024 supported type and isTigrisLinked / isSydneyLinked rules (652 insns); effect limited to the window shape of iPhone-only apps, decode pending |
| SBApplication(Classic_Private) | `+_niceScreenTypeForClassicType:matchingAValidDisplayZoomModeOnScreenType:` | 0x1c5ec6918 | 0x1c7339a44 | TRIAGE PENDING |
| SBApplicationSceneHandle | `-_createApplicationSceneSettingsFromContext:entity:` | 0x1c5e2b338 | 0x1c729d898 | TO PORT: M5 orientation family (REVIEW-CORE M5): interfaceOrientationForLayoutElement:unknownAllowed: |
| SBApplicationSceneUpdateTransaction | `-initWithApplicationSceneEntity:transitionRequest:` | 0x1c5e2ae9c | 0x1c729d788 | PORTED already: hook in G3B.x:369 |
| SBApplicationSceneUpdateTransaction | `-_didComplete` | 0x1c5e48cfc | 0x1c72baf2c | TRIAGE PENDING |
| SBApplicationSceneUpdateTransaction | `-.cxx_destruct` | 0x1c5e4ecb4 | 0x1c72c0ef8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBApplicationSceneUpdateTransaction | `-_willBegin` | 0x1c644ab4c | 0x1c78fe4a8 | TRIAGE PENDING |
| SBApplicationSceneUpdateTransaction | `-_customizedDescriptionProperties` | 0x1c644ac94 | 0x1c78feae0 | EXCLUDED: description / debug text only |
| SBApplicationSupportServiceDelegate | `-service:overrideClientInitialization:` | 0x1c61c050c | 0x1c764ee7c | TRIAGE PENDING |
| SBApplicationSupportServiceDelegate | `-destroyScenesWithPersistentIdentifiers:animationType:destroySessions:forClient:completion:` | 0x1c61c0a7c | 0x1c764f3f4 | TRIAGE PENDING |
| SBApplicationSupportServiceRequestContext | `+initializationContextForClient:` | 0x1c6345d28 | 0x1c77ea600 | TRIAGE PENDING |
| SBApplicationSupportServiceRequestContext | `-_main_launchDisplayContext` | 0x1c6346958 | 0x1c77eb2d8 | TRIAGE PENDING |
| SBDeviceApplicationSceneHandle | `-_modifyApplicationSceneSettings:fromRequestContext:entity:` | 0x1c5e2b9a8 | 0x1c729dfb4 | 7dd10ca: Y1Workspace.x y1_scenestyle (userInterfaceStyle on every display); the 16.2 screenBoundsIgnoresSceneOrientation property needs the 16.2 UIKit client in every app (absent in 16.0 UIMutableApplicationSceneSettings): CANNOT here, the isChamoisLinked rename and the _isInCallBanner removal are equivalent [sha 82bc14e] |
| SBDeviceApplicationSceneHandle | `-_mainSceneSupportedInterfaceOrientations` | 0x1c5e37cc0 | 0x1c72aa11c | PORTED already: hook in G3.x:244 |
| SBDeviceApplicationSceneHandle | `-_didUpdateSettingsWithDiff:previousSettings:` | 0x1c5e3d8b8 | 0x1c72afca0 | PORTED already: hook in G3.x:295 |
| SBDeviceApplicationSceneHandle | `-setKeyboardContextMaskStyle:` | 0x1c5e3df60 | 0x1c72b0354 | PORTED already: hook in G3.x:266 |
| SBDeviceApplicationSceneHandle | `-_didUpdateClientSettingsWithDiff:transitionContext:` | 0x1c5e473d0 | 0x1c72b9430 | PORTED already: hook in G3.x:308 |
| SBDeviceApplicationSceneHandle | `-.cxx_destruct` | 0x1c5e50f8c | 0x1c72c3380 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDeviceApplicationSceneHandle | `-activationInterfaceOrientationForOrientation:` | 0x1c5e58d94 | 0x1c72cb524 | PORTED already: hook in G3.x:277 |
| SBDeviceApplicationSceneHandle | `-_launchingInterfaceOrientationForOrientation:` | 0x1c5e73fe0 | 0x1c72e6e94 | PORTED already: hook in G3.x:205 |
| SBDeviceApplicationSceneHandle | `-_resumingInterfaceOrientationForOrientation:` | 0x1c5e9d524 | 0x1c73101d0 | PORTED already: hook in G3.x:285 |
| SBDeviceApplicationSceneHandle | `-dealloc` | 0x1c6224548 | 0x1c76b4fb0 | TRIAGE PENDING |
| SBDeviceApplicationSceneHandle | `-wantsDeviceOrientationEventsEnabled` | 0x1c6225328 | 0x1c76b5dac | PORTED already: hook in G3.x:260 |
| SBDeviceApplicationSceneHandle | `-_interfaceOrientationMode` | 0x1c62253b4 | 0x1c76b5e24 | PORTED already: hook in G3.x:255 |
| SBDeviceApplicationSceneHandle | `-_classicPhoneOnPadActivationOrientationForOrientation:` | 0x1c62262d8 | 0x1c76b6c78 | TRIAGE PENDING |
| SBEmbeddedDisplayWindowSceneDelegate | `-_configureForConnectingWindowScene:windowSceneContext:` | 0x1c63a0e20 | 0x1c784b1b8 | PORTED already: hook in Group4Focus.x:646 |
| SBEmbeddedDisplayWindowSceneDelegate | `-.cxx_destruct` | 0x1c63a1588 | 0x1c784b974 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBExternalDisplayWindowSceneDelegate | `-_configureForConnectingWindowScene:windowSceneContext:` | 0x1c5fed084 | 0x1c7467d5c | PORTED already: hook in Group4Focus.x:665 |
| SBExternalDisplayWindowSceneDelegate | `-sceneDidDisconnect:` | 0x1c5fed4f8 | 0x1c746826c | PORTED already: hook in Group4Focus.x:670 |
| SBLayoutState | `-interfaceOrientation` | 0x1c5e1f9a8 | 0x1c7291884 | 7dd10ca: Y8Layout.x y8_extorient (external display states default to portrait) together with P1SW.m unknownAllowed variants |
| SBLayoutState | `-interfaceOrientationForElementIdentifier:` | 0x1c61e1220 | 0x1c766f804 | PORTED already: 16.2 address cited in P1SW.m |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:` | 0x1c6036db4 | 0x1c74b2314 | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:uniqueIdentifier:` | 0x1c6036dfc | 0x1c74b235c | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:excludingIdentifiers:` | 0x1c6036e40 | 0x1c74b23a0 | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:targetContentIdentifier:` | 0x1c6036e88 | 0x1c74b23e8 | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:targetContentIdentifier:allowCanMatches:preferNewScene:visibleIdentifiers:` | 0x1c6036ed0 | 0x1c74b2430 | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:uniqueIdentifier:targetContentIdentifier:` | 0x1c6036f6c | 0x1c74b24cc | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBLayoutStateSceneIdentityProvider | `-sceneIdentityForApplication:uniqueIdentifier:targetContentIdentifier:sceneSessionRole:` | 0x1c6036fac | 0x1c74b250c | EQUIVALENT: selector rename preferedDisplay: -> preferredDisplay: only (same call, 16.0 spelling in the 16.0 helper) |
| SBMainDisplayLayoutState | `-isEqual:` | 0x1c5e2e28c | 0x1c72a0934 | 7dd10ca: Y8Layout.x y8_stateeq (display ordinal takes part in equality) |
| SBMainDisplayLayoutState | `-_initWithLayoutElements:interfaceOrientation:interfaceOrientationByLayoutElement:` | 0x1c62889b8 | 0x1c772119c | EQUIVALENT: 16.2 caches appLayout / floatingAppLayout (invalidateAppLayout / invalidateFloatingAppLayout calls, copies isDisplayExternal); 16.0 computes both on demand, so nothing to invalidate; displayItemFromLayoutElement: became +[SBDisplayItem displayItemForLayoutElement:] (same item); isDisplayExternal itself is Y8Layout.x y8_extorient |
| SBMainDisplayLayoutState | `-_initWithLayoutState:` | 0x1c6288a2c | 0x1c7721214 | EQUIVALENT: 16.2 caches appLayout / floatingAppLayout (invalidateAppLayout / invalidateFloatingAppLayout calls, copies isDisplayExternal); 16.0 computes both on demand, so nothing to invalidate; displayItemFromLayoutElement: became +[SBDisplayItem displayItemForLayoutElement:] (same item); isDisplayExternal itself is Y8Layout.x y8_extorient |
| SBMainDisplayLayoutState | `-hash` | 0x1c6289258 | 0x1c7721ad0 | EQUIVALENT: 16.2 mixes the display ordinal into the hash; equal states still hash equal with the 16.0 hash (only collision rate differs) |
| SBMainDisplayLayoutState | `-setInterfaceOrientationByLayoutElementIdentifier:` | 0x1c62894e0 | 0x1c7721d88 | EQUIVALENT: 16.2 caches appLayout / floatingAppLayout (invalidateAppLayout / invalidateFloatingAppLayout calls, copies isDisplayExternal); 16.0 computes both on demand, so nothing to invalidate; displayItemFromLayoutElement: became +[SBDisplayItem displayItemForLayoutElement:] (same item); isDisplayExternal itself is Y8Layout.x y8_extorient |
| SBMainDisplayLayoutState | `-_updateSizingPoliciesForLayoutElements:` | 0x1c6289588 | 0x1c7721e2c | EQUIVALENT: 16.2 caches appLayout / floatingAppLayout (invalidateAppLayout / invalidateFloatingAppLayout calls, copies isDisplayExternal); 16.0 computes both on demand, so nothing to invalidate; displayItemFromLayoutElement: became +[SBDisplayItem displayItemForLayoutElement:] (same item); isDisplayExternal itself is Y8Layout.x y8_extorient |
| SBMainDisplayLayoutState | `-appLayout` | 0x1c62898e4 | 0x1c7722290 | EQUIVALENT: 16.2 caches appLayout / floatingAppLayout (invalidateAppLayout / invalidateFloatingAppLayout calls, copies isDisplayExternal); 16.0 computes both on demand, so nothing to invalidate; displayItemFromLayoutElement: became +[SBDisplayItem displayItemForLayoutElement:] (same item); isDisplayExternal itself is Y8Layout.x y8_extorient |
| SBMainDisplayLayoutState | `-floatingAppLayout` | 0x1c6289ccc | 0x1c7722688 | EQUIVALENT: 16.2 caches appLayout / floatingAppLayout (invalidateAppLayout / invalidateFloatingAppLayout calls, copies isDisplayExternal); 16.0 computes both on demand, so nothing to invalidate; displayItemFromLayoutElement: became +[SBDisplayItem displayItemForLayoutElement:] (same item); isDisplayExternal itself is Y8Layout.x y8_extorient |
| SBMainDisplayLayoutStateManager | `-_layoutStateForApplicationTransitionContext:` | 0x1c5e23430 | 0x1c72952ec | PORTED already: hook in G3C.x:446, G4B.x:1903 |
| SBMainDisplayLayoutStateManager | `-defaultSceneIdentifierForBundleIdentifier:targetContentIdentifier:allowCanMatches:preferNewScene:visibleSceneIdentifiers:excludingSceneIdentifiers:sceneSessionRole:` | 0x1c625a188 | 0x1c76f09cc | TRIAGE PENDING |
| SBMainDisplaySceneManager | `-_scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` | 0x1c5e46a00 | 0x1c72b9050 | EQUIVALENT: 16.2 moved the app client-settings diff inspection to the SBSceneManager base (base inspector is nil; the extended manager's only inspector observes preferredPointerLockStatus = G4B.x lockedptr2 hook of the extended manager); the main manager keeps the 16.0 inspectors |
| SBMainDisplaySceneManager | `-_updateLevelAndBackgroundSettingsForScene:transitionContext:` | 0x1c5e6dc1c | 0x1c72e097c | EQUIVALENT: only the hosted keyboard window update moved to the SBSceneManager callbacks (G3B.x g3b_kbwindow covers every display) |
| SBMainDisplaySceneManager | `-_handleAction:forScene:` | 0x1c5e70a78 | 0x1c72e3838 | 7dd10ca: 16.2 moved UIDestroySceneAction / resize-finished handling into the SBSceneManager base; Y1Workspace.x y1_extaction gives the extended display manager the destroy action (the resize-finished 0x30 branch already exists in its 16.0 override 0x1c63ae37c) [sha 82bc14e] |
| SBMainDisplaySceneManager | `-dealloc` | 0x1c63d3d0c | 0x1c787fa2c | EQUIVALENT: removeAllObservers / foreground flag of a log line only |
| SBMainDisplaySceneManager | `-_scene:interceptUpdateWithNewSettings:` | 0x1c63d488c | 0x1c78804ac | EQUIVALENT: removeAllObservers / foreground flag of a log line only |
| SBMainDisplaySceneManager | `-.cxx_destruct` | 0x1c63d7ee8 | 0x1c7882e28 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBMainStatusBarStateProvider | `-_shouldPostForVisitedItem:withUpdates:toAggregatorData:lastPost:` | 0x1c5e1efbc | 0x1c7290fa0 | IRRELEVANT: status bar post data: lock screen / on-AC battery condition for the lock screen and item enum shift (iPhone status bar items) |
| SBMainStatusBarStateProvider | `-_composePostDataFromAggregatorData:` | 0x1c5e1f6d4 | 0x1c72915c8 | IRRELEVANT: status bar post data: lock screen / on-AC battery condition for the lock screen and item enum shift (iPhone status bar items) |
| SBMainWorkspace | `-_executeTransitionRequest:options:validator:` | 0x1c5e1ffe4 | 0x1c7291e98 | IRRELEVANT: 16.2 skips deactivateReachability for source 0xe: Reachability is an iPhone feature |
| SBMainWorkspace | `-transactionDidComplete:` | 0x1c5e4e4dc | 0x1c72c071c | OPEN: 16.2 passes a nil display identity to __SBWorkspaceActivateSpringBoardWithResult (suspend the ACTIVE display); G2B 5e documents that 16.0 has no single display entry and keeps the 16.0 all displays call: same decision applies here |
| SBMainWorkspace | `-init` | 0x1c5efd108 | 0x1c7371404 | EQUIVALENT: SBWorkspaceKeyboardFocusController initWithWorkspace:windowSceneManager: passes the window scene manager the 16.0 controller reads from SBApp (Group4Focus.x) |
| SBMainWorkspace | `-inCallPresentationManager:createPresentationSessionWithSceneHandle:` | 0x1c5efeb60 | 0x1c7372e7c | PORTED already: 16.2 address cited in X6InCall.x |
| SBMainWorkspace | `-_executeTransientOverlayTransitionRequest:` | 0x1c5f00d54 | 0x1c7375028 | PORTED already: 16.2 address cited in X2Overlay.x |
| SBMainWorkspace | `-_selectTransactionForAppEntityRemoved:` | 0x1c5f0191c | 0x1c7375c68 | 7dd10ca: Y1Workspace.x y1_appremoved (window scene of the dying scene's display) [sha 82bc14e] |
| SBMainWorkspace | `-setPipCoordinator:` | 0x1c5f021c4 | 0x1c73765b8 | EQUIVALENT: SBSystemNotesManager init no longer takes the transient UI manager: Quick Note is embedded display only (the manager it got is the main one); ivar renumbering |
| SBMainWorkspace | `-_destroyApplicationSceneEntity:` | 0x1c5f02cc4 | 0x1c737708c | 7dd10ca: Y1Workspace.x y1_appremoved (+ new _cleanupForRemovedAppEntity:, which also replaces the 16.0 _applicationEntityWasRemovedFromAppSwitcher: body) [sha 82bc14e] |
| SBMainWorkspace | `-_removeApplicationEntitiesFromWorkspace:error:` | 0x1c5f036fc | 0x1c7377ba0 | 7dd10ca: Y1Workspace.x y1_appremoved (any-display layout lookup) [sha 82bc14e] |
| SBMainWorkspace | `-_targetWindowSceneForApplication:preferringDisplay:requireForeground:options:` | 0x1c5f04228 | 0x1c7378764 | EQUIVALENT: 16.2 adds a consistency filter (scene settings display == manager's display) that only differs while a scene is being taken by another display; LOW, not ported |
| SBMainWorkspace | `-_handleOpenApplicationRequest:options:activationSettings:origin:withResult:` | 0x1c5f060d0 | 0x1c737a760 | EQUIVALENT: selector sequence identical; device capability gates (blraaz) became direct calls, register renumbering only |
| SBMainWorkspace | `-isKeyboardVisibleForSpringBoardForTransientOverlayScenePresenter:` | 0x1c5f0c1dc | 0x1c73808a4 | OPEN: NEEDS EDIT IN G3B.x: expose the per-window-scene hosted keyboard controller (BPKB_ControllerForWindowScene) as -[SBWindowScene medusaHostedKeyboardWindowController]; only matters for alerts on the extended display (LOW) |
| SBMainWorkspace | `-transientOverlayScenePresenter:didDismissViewController:wasTopmostPresentation:` | 0x1c5f0cad0 | 0x1c73811ac | EQUIVALENT: main display presenter: identical (switcherController of the window scene = the coordinator's active controller); extended display presenter only resets the idle timer / clock after a dismissal, LOW, not ported |
| SBMainWorkspaceLayoutStateContingencyPlan | `-transitionContextForLayoutContext:failedEntities:` | 0x1c6450ce8 | 0x1c7904c94 | TRIAGE PENDING |
| SBMainWorkspaceTransitionRequest | `-copyMainWorkspaceTransitionRequest` | 0x1c63e6878 | 0x1c7892f40 | TRIAGE PENDING |
| SBRecentAppLayouts | `-_setRecents:notifyForChangeDescription:` | 0x1c64eb650 | 0x1c79a8370 | EXCLUDED: description / debug text only |
| SBRecentAppLayouts | `-_validateAndUpdateRecents:` | 0x1c64ed538 | 0x1c79aa0ec | TRIAGE PENDING |
| SBRecentAppLayouts | `-_stashModelToPath:` | 0x1c64ee2b4 | 0x1c79ab11c | TRIAGE PENDING |
| SBRecentAppLayouts | `-.cxx_destruct` | 0x1c64ef86c | 0x1c79ac67c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSceneLayoutStateProvider | `-.cxx_destruct` | 0x1c615f7a4 | 0x1c75e6cb0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSceneLayoutWhitePointAdaptationController | `-_whitePointAdaptivityStylesForLayoutState` | 0x1c612efd0 | 0x1c75b9b58 | TRIAGE PENDING |
| SBSceneLayoutWorkspaceTransaction | `-_captureAppsForTransition` | 0x1c5e27b6c | 0x1c729a3c4 | EQUIVALENT: 16.2 only replaces the inlined SBEnableX feature check (blraaz) by an out of line call and renumbers helpers |
| SBSceneLayoutWorkspaceTransaction | `-_updateScenesForTransitionCompletion` | 0x1c5e49218 | 0x1c72bb488 | EQUIVALENT: 16.2 asks [windowScene medusaHostedKeyboardWindowController] updateMedusaHostedKeyboardWindow; 16.0 sends _updateMedusaHostedKeyboardWindow to the transaction scene manager, which is the window scene manager (SBMainDisplaySceneManager and SBSystemShellExternalDisplaySceneManager both implement it, 0x1c63d6fcc / 0x1c63aeb94) |
| SBSceneLayoutWorkspaceTransaction | `-_runningOnMainRootOrExtendedExternalDisplay` | 0x1c62a109c | 0x1c773aecc | EQUIVALENT: 16.2 only replaces the inlined SBEnableX feature check (blraaz) by an out of line call and renumbers helpers |
| SBSceneManager | `-_handleAction:forScene:` | 0x1c5e71060 | 0x1c72e3b58 | PORTED already: G4B.x hook (_UIPointerUnlockAction) + Y1Workspace.x y1_extaction (UIDestroySceneAction); snapshot / activation prewarm actions are in the 16.0 base already |
| SBSceneManager | `-initWithReference:sceneIdentityProvider:presentationBinder:` | 0x1c5f7230c | 0x1c73e904c | TRIAGE PENDING |
| SBSceneManager | `-takeScene:fromSceneManager:` | 0x1c5f72cf4 | 0x1c73e9a3c | 7dd10ca: G4B.x hook + Y1Workspace.x y1_takescene (new handle's wantsEnhancedWindowingEnabled follows the new display) [sha 82bc14e] |
| SBSceneManager | `-descriptionBuilderWithMultilinePrefix:` | 0x1c5f73af0 | 0x1c73ea6f8 | EXCLUDED: description / debug text only |
| SBSceneManager | `-_scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` | 0x1c5f74a9c | 0x1c73eb73c | EQUIVALENT: see SBMainDisplaySceneManager row: base inspector nil, extended manager inspector (pointer lock) ported in G4B.x |
| SBSceneManager | `-scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` | 0x1c5f761d4 | 0x1c73ed100 | EQUIVALENT: hosted keyboard window refresh per window scene = G3B.x g3b_kbwindow (fan-out controllers refreshed from the main and extended manager's _updateMedusaHostedKeyboardWindow) |
| SBSceneManager | `-scene:didCompleteUpdateWithContext:error:` | 0x1c5f76bdc | 0x1c73edb40 | EQUIVALENT: hosted keyboard window refresh per window scene = G3B.x g3b_kbwindow (fan-out controllers refreshed from the main and extended manager's _updateMedusaHostedKeyboardWindow) |
| SBSceneManager | `-.cxx_destruct` | 0x1c5f76d08 | 0x1c73edd1c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSceneManagerCoordinator | `-workspace:didReceiveSceneRequestWithOptions:completion:` | 0x1c630f438 | 0x1c77ad8dc | TRIAGE PENDING |
| SBSceneSettingsUpdater | `-setDisplayConfiguration:` | 0x1c605a75c | 0x1c74d93c8 | EQUIVALENT: 16.2 adds the updateGeometry: variant (the 16.0 form always updates geometry, _updatesGeometry defaults to the same) |
| SBSceneSettingsUpdater | `+safeUpdateScene:withDisplayConfiguration:` | 0x1c605a154 | 0x1c74d98ec | EQUIVALENT: 16.2 adds the updateGeometry: variant (the 16.0 form always updates geometry, _updatesGeometry defaults to the same) |
| SBSceneViewController | `-initWithSceneHandle:` | 0x1c5e7479c | 0x1c72e7614 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBSceneViewController | `-viewDidLoad` | 0x1c5e74f34 | 0x1c72e7db8 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBSingleSceneController | `-initWithTargetDisplayConfiguration:sceneWorkspaceController:sceneRequestOptions:clientIdentity:traitsRole:level:` | 0x1c645b9d4 | 0x1c790e804 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-invalidate` | 0x1c645be2c | 0x1c790ec58 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-setShouldActivateUponClientConnection:` | 0x1c645bf44 | 0x1c790edfc | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-setShouldBeKeptActiveWhileForeground:` | 0x1c645bf58 | 0x1c790ef64 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-sceneContentStateDidChange:` | 0x1c645bf84 | 0x1c790f170 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-sceneDidInvalidate:` | 0x1c645c0b0 | 0x1c790f318 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-_setVisible:` | 0x1c645c150 | 0x1c790f448 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-_evaluateSceneActivationState` | 0x1c645c60c | 0x1c790fb30 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSingleSceneController | `-.cxx_destruct` | 0x1c645c950 | 0x1c790fea0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBStatusBarStateProvider | `-endCoalescentBlock` | 0x1c5e1f2cc | 0x1c72911c4 | IRRELEVANT: status bar post data: lock screen / on-AC battery condition for the lock screen and item enum shift (iPhone status bar items) |
| SBSuspendedWorkspaceTransaction | `-_childTransactionDidComplete:` | 0x1c5ea0d90 | 0x1c7313a68 | TRIAGE PENDING |
| SBSystemShellExternalDisplaySceneManager | `-_shouldAutoHostScene:` | 0x1c63ae320 | 0x1c7858710 | PORTED already: hook in Tweak.x:292 |
| SBSystemShellExternalDisplaySceneManager | `-.cxx_destruct` | 0x1c63aeb98 | 0x1c7859118 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBToAppsWorkspaceTransaction | `-initWithTransitionRequest:` | 0x1c5e21e5c | 0x1c7293d24 | EQUIVALENT: ancillary-request helper moved from an instance method to +[SBMainWorkspaceTransitionRequest ancillaryTransitionRequestsForTransitionRequest:], delegate passed to SBSceneLayoutWorkspaceTransaction init (setDelegate: before): same objects, no behaviour change |
| SBToAppsWorkspaceTransaction | `-_willBegin` | 0x1c5e28ffc | 0x1c729b83c | CANNOT: privacy preflight gate (privacyPreflightController / requiresPreflightForApplication:) needs PrivacyDisclosureCore, absent in 16.0 (REVIEW-PLUMBING 'privacy preflight gate') |
| SBToAppsWorkspaceTransaction | `-transaction:performTransitionWithCompletion:` | 0x1c5e3e06c | 0x1c72b0460 | 7dd10ca: Y1Workspace.x y1_takescene (the 16.2 block 0x1c784e3f8 sets wantsEnhancedWindowingEnabled on the taken handle; done in the takeScene: hook) [sha 82bc14e] |
| SBToAppsWorkspaceTransaction | `-_completeCurrentTransition` | 0x1c5e4855c | 0x1c72ba764 | EQUIVALENT: 16.2 enumerates a copy of the completion blocks (mutation safety only) |
| SBToAppsWorkspaceTransaction | `-_acquireResignActiveAssertion` | 0x1c5e7434c | 0x1c72e718c | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBUIController | `-activateApplication:fromIcon:location:activationSettings:actions:` | 0x1c5e72ef4 | 0x1c72e5df8 | EQUIVALENT: icon launches come from the iPad Home Screen and Dock: the entity is made for the display identity of the activation setting (iPad) instead of initWithApplicationForMainDisplay:, the same display |
| SBUIController | `-handleHomeButtonDoublePressDown` | 0x1c5e9ca80 | 0x1c730f780 | EQUIVALENT: _shim_activeSwitcherController is the active display's controller, what the 16.0 coordinator forwarder answers; init / accessory / nil check bookkeeping |
| SBUIController | `-init` | 0x1c5ef0cf4 | 0x1c7364ddc | EQUIVALENT: _shim_activeSwitcherController is the active display's controller, what the 16.0 coordinator forwarder answers; init / accessory / nil check bookkeeping |
| SBUIController | `-getRotationContentSettings:forWindow:` | 0x1c5ef1d5c | 0x1c7365dd0 | EQUIVALENT: _shim_activeSwitcherController is the active display's controller, what the 16.0 coordinator forwarder answers; init / accessory / nil check bookkeeping |
| SBUIController | `-storeAttachedAccessory:` | 0x1c5ef54a8 | 0x1c73695f0 | EQUIVALENT: _shim_activeSwitcherController is the active display's controller, what the 16.0 coordinator forwarder answers; init / accessory / nil check bookkeeping |
| SBUIController | `-.cxx_destruct` | 0x1c5ef6ce8 | 0x1c736b0b4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBUserAgent | `-foregroundApplicationDisplayID` | 0x1c5ea5eec | 0x1c7318be8 | TRIAGE PENDING |
| SBWindow | `-initWithWindowScene:rootViewController:layoutStrategy:role:debugName:` | 0x1c64acb50 | 0x1c79650bc | TRIAGE PENDING |
| SBWindowSceneContext | `-sceneManager` | 0x1c6500ad4 | 0x1c79bdacc | TRIAGE PENDING |
| SBWindowSceneContext | `-.cxx_destruct` | 0x1c6500dec | 0x1c79bde30 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBWindowSceneManager | `-activeDisplayWindowScene` | 0x1c6043bec | 0x1c74bf1c4 | PORTED already: hook in Group4Focus.x:593 |
| SBWindowSceneManager | `-.cxx_destruct` | 0x1c60442d4 | 0x1c74bfb4c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBWindowScenePIPManager | `-windowSceneDidConnect:` | 0x1c5eca974 | 0x1c733e170 | PORTED already: hook in G3B.x:580 |
| SBWindowScenePIPManager | `-windowSceneDidDisconnect:` | 0x1c5ecab4c | 0x1c733e3c8 | PORTED already: hook in G3B.x:594 |
| SBWindowScenePIPManager | `-.cxx_destruct` | 0x1c5ecc7c0 | 0x1c7340174 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBWindowSceneStatusBarManager | `-setAvoidanceFrame:reason:statusBar:animationSettings:` | 0x1c5ef798c | 0x1c736bd64 | EQUIVALENT: 4-argument convenience forwards options 0 to ...options: (group3-plumbing) |
| SBWorkspaceApplicationSceneTransitionContext | `-frameForApplicationSceneEntity:` | 0x1c5e2b91c | 0x1c729dee0 | TRIAGE PENDING |
| SBWorkspaceKeyboardFocusController | `-lockFocusToSpringBoardWindowScene:forReason:` | 0x1c6321c94 | 0x1c77c19f0 | PORTED already: hook in G4B.x:2152 |
| SBWorkspaceKeyboardFocusController | `-userFocusRequestForScene:reason:completion:` | 0x1c6322844 | 0x1c77c29d8 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBWorkspaceKeyboardFocusController | `-removeKeyboardFocusFromScene:` | 0x1c6322ec4 | 0x1c77c3074 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBWorkspaceKeyboardFocusController | `-windowSceneDidDisconnect:` | 0x1c6323a98 | 0x1c77c3b14 | PORTED already: hook in Group4Focus.x:563 |
| SBWorkspaceKeyboardFocusController | `-sceneManager:willRemoveExternalForegroundApplicationSceneHandle:forDestroyEvent:` | 0x1c6323e00 | 0x1c77c4444 | TRIAGE PENDING |
| SBWorkspaceKeyboardFocusController | `-sceneManager:didRemoveExternalForegroundApplicationSceneHandle:` | 0x1c6323e94 | 0x1c77c44e0 | TRIAGE PENDING |
| SBWorkspaceKeyboardFocusController | `-_filterFocusedSceneIdentityToken:focusedPID:resultBlock:` | 0x1c6323f3c | 0x1c77c4590 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBWorkspaceKeyboardFocusController | `-.cxx_destruct` | 0x1c63285ac | 0x1c77c9334 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBWorkspaceTransitionRequest | `-applicationTransitionContext:frameForApplicationSceneEntity:` | 0x1c5f42650 | 0x1c73b6c6c | TRIAGE PENDING |
| SpringBoard | `-noteSceneLayoutDidUpdateOnDisplayWithIdentity:` | 0x1c5e4b7cc | 0x1c72bda18 | EQUIVALENT: still main display only (isMainDisplay gate kept); only the coordinator singleton became the window scene's switcher controller / presenter |
| SpringBoard | `-startupInterfaceOrientation` | 0x1c5ed5ba0 | 0x1c734a2d4 | PORTED already: hook in G3.x:923 |
| SpringBoard | `-application:configurationForConnectingSceneSession:options:` | 0x1c5ed6c24 | 0x1c734b1f8 | TRIAGE PENDING |
| SpringBoard | `-applicationDidFinishLaunching:` | 0x1c5ed74d8 | 0x1c734ba64 | PORTED already: hook in G4B.x:1042 |
| SpringBoard | `-_completeStartupAfterMainSceneConnect:` | 0x1c5ed81c4 | 0x1c734c5ac | PORTED already: hook in EDE.x:195 |
| SpringBoard | `-_initializeDeferredItems` | 0x1c5edc204 | 0x1c73503c4 | TRIAGE PENDING |
| SpringBoard | `-toggleSearchFromBreadcrumbSource:withWillBeginHandler:completionHandler:` | 0x1c5ede078 | 0x1c7352218 | PORTED already: 16.2 address cited in X2Overlay.x |
| SpringBoard | `-beginInteractiveSpotlightTransientOverlayPresentationWithValidator:beginHandler:` | 0x1c5edeaa8 | 0x1c7352bf8 | PORTED already: 16.2 address cited in X2Overlay.x |
| SpringBoard | `-languageChanged` | 0x1c5edf1c0 | 0x1c7353370 | TRIAGE PENDING |
| SpringBoard | `-buildMenuWithBuilder:` | 0x1c5ee2a40 | 0x1c7356c84 | PORTED already: hook in G3B.x:273 |
| SpringBoard | `-remoteTransientOverlaySessionManager:shouldActivateOverlayWithContext:forSession:` | 0x1c5ee6488 | 0x1c735a4b4 | TRIAGE PENDING |
| SpringBoard | `-remoteTransientOverlaySessionManager:performPresentationRequest:forSession:` | 0x1c5ee6ca0 | 0x1c735acb8 | PORTED already: hook in G4B.x:2358 |
| SpringBoard | `-_openURLCore:display:animating:activationSettings:origin:withResult:` | 0x1c5ee955c | 0x1c735d6c4 | TRIAGE PENDING |
| SpringBoard | `-_legacy_noteInterfaceOrientationChanged:duration:updateMirroredDisplays:force:logMessage:` | 0x1c5eeb79c | 0x1c735fa08 | TRIAGE PENDING |
| SpringBoard | `-_interfaceOrientationForRawOrientation:validOrientation:ignoringHomeScreenRotationStyle:` | 0x1c5eebfdc | 0x1c7360244 | TRIAGE PENDING |
| SpringBoard | `-addNowLocatingApp:` | 0x1c5eed0c8 | 0x1c736127c | TRIAGE PENDING |
| SpringBoard | `-removeNowLocatingApp:` | 0x1c5eed150 | 0x1c7361340 | TRIAGE PENDING |
| SpringBoard | `-_accessibilityFrontMostApplication` | 0x1c5eed77c | 0x1c73619b0 | TRIAGE PENDING |
| SpringBoard | `+_newApplicationInitializationContext` | 0x1c5eef658 | 0x1c7363804 | TRIAGE PENDING |
| SpringBoard | `-.cxx_destruct` | 0x1c5eefa5c | 0x1c7363b84 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SpringBoard(SBApplicationTesting) | `-_runHomeScreenSearchPresent` | 0x1c5f2a830 | 0x1c739eda4 | IRRELEVANT: internal test recipes |
| SpringBoard(SBApplicationTesting) | `-_runHomeScreenSearchDismiss` | 0x1c5f2a994 | 0x1c739ef08 | IRRELEVANT: internal test recipes |
| SpringBoard(StatusBar) | `-handleStatusBarHoverActionForRegion:` | 0x1c621a6f0 | 0x1c76ab100 | TRIAGE PENDING |

## F2 Home Screen / Icon / Dock / status bar (88)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBControlCenterController | `-_shouldShowGrabberOnFirstSwipe` | 0x1c5e530cc | 0x1c72c5518 | 7dd10ca: Y9Misc.x y9_ccscene (Control Center decides from the layout of its own window scene's switcher controller) |
| SBControlCenterController | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c5e532dc | 0x1c72c574c | OPEN: 16.2 builds the indirect status bar pull recognizer without a system gesture manager argument and registers failure requirements with the scene's gesture manager: tied to SBIndirectPanGestureRecognizer (regression guard item, see F4) |
| SBControlCenterController | `-gestureRecognizerShouldBegin:` | 0x1c5e8d6ec | 0x1c7300268 | PORTED already: hook in Group4Focus.x:742 |
| SBControlCenterController | `-_willPresent` | 0x1c5e8e900 | 0x1c730158c | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBControlCenterController | `-init` | 0x1c61c6340 | 0x1c7655018 | IRRELEVANT: test recipe registration / module visibility flag and a debug name of the grabber tongue |
| SBControlCenterController | `-_updateWindowForScene:` | 0x1c61c8a28 | 0x1c76576f4 | IRRELEVANT: test recipe registration / module visibility flag and a debug name of the grabber tongue |
| SBControlCenterController | `-_setupGestureRecognizersForUpdatedWindowScene` | 0x1c61c8bfc | 0x1c76578d8 | OPEN: 16.2 builds the indirect status bar pull recognizer without a system gesture manager argument and registers failure requirements with the scene's gesture manager: tied to SBIndirectPanGestureRecognizer (regression guard item, see F4) |
| SBControlCenterController | `-canBePresented` | 0x1c61c8f3c | 0x1c7657c38 | 7dd10ca: Y9Misc.x y9_ccscene (Control Center decides from the layout of its own window scene's switcher controller) |
| SBControlCenterController | `-_isStatusBarHiddenIgnoringControlCenter` | 0x1c61c9e80 | 0x1c7658b9c | 7dd10ca: Y9Misc.x y9_ccscene (Control Center decides from the layout of its own window scene's switcher controller) |
| SBFloatingDockController | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c5e52bcc | 0x1c72c5038 | TRIAGE PENDING |
| SBFloatingDockController | `-_initWithWindowScene:iconController:applicationController:recentsController:recentsDataStore:layoutStateTransitionCoordinator:appSuggestionManager:analyticsClient:` | 0x1c6253e60 | 0x1c76e9528 | TRIAGE PENDING |
| SBFloatingDockController | `-_deriveActiveAssertion:dockProgress:` | 0x1c6254e44 | 0x1c76ea47c | PORTED already: 16.2 address cited in G1D.x |
| SBFloatingDockController | `-_updateFocusAssertion` | 0x1c6254fe0 | 0x1c76ea75c | PORTED already: 16.2 address cited in G1D.x |
| SBFloatingDockController | `-registerForWindowScene:` | 0x1c6255510 | 0x1c76eac98 | TRIAGE PENDING |
| SBFloatingDockController | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c6256588 | 0x1c76ebcdc | TRIAGE PENDING |
| SBFloatingDockController | `-.cxx_destruct` | 0x1c6258080 | 0x1c76ed814 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFloatingDockRootViewController | `-viewDidLayoutSubviews` | 0x1c5e3b340 | 0x1c72ad6d8 | TRIAGE PENDING |
| SBFloatingDockRootViewController | `-_setPresentedProgress:animated:interactive:completion:` | 0x1c5e5fe74 | 0x1c72d2368 | TRIAGE PENDING |
| SBFloatingDockRootViewController | `-_beginPresentationTransition` | 0x1c5e6036c | 0x1c72d287c | TRIAGE PENDING |
| SBFloatingDockRootViewController | `-_endPresentationTransition` | 0x1c5e61c28 | 0x1c72d4114 | TRIAGE PENDING |
| SBFloatingDockRootViewController | `-isFloatingDockViewControllerPresentedOverApplication:` | 0x1c6337d74 | 0x1c77db110 | TRIAGE PENDING |
| SBFloatingDockSuggestionsModel | `-_initializeAndObserveDefaults` | 0x1c64a8d0c | 0x1c7961148 | TRIAGE PENDING |
| SBFloatingDockSuggestionsViewController | `-_emitPresentedEventInvolvingContinuity:fromModel:atIndex:` | 0x1c60e5d38 | 0x1c756a6b8 | TRIAGE PENDING |
| SBFloatingDockSuggestionsViewController | `-_shouldDeferUpdateInvolvingContinuity:` | 0x1c60e7988 | 0x1c756c2dc | TRIAGE PENDING |
| SBFloatingDockWindow | `-isContentHidden` | 0x1c647b034 | 0x1c7930c24 | TRIAGE PENDING |
| SBHomeGestureInteraction | `-initWithSystemGestureManager:delegate:` | 0x1c6132e20 | 0x1c75bdca0 | EQUIVALENT: 16.2 init asserts a gesture manager and builds SBIndirectPanGestureRecognizer without the manager argument (the manager registers the lifecycle monitor, see SBSystemGestureManager rows): same recognizer |
| SBHomeGestureInteraction | `-_configureIndirectPanGestureRecognizer` | 0x1c613315c | 0x1c75bdfc0 | EQUIVALENT: 16.2 init asserts a gesture manager and builds SBIndirectPanGestureRecognizer without the manager argument (the manager registers the lifecycle monitor, see SBSystemGestureManager rows): same recognizer |
| SBHomeHardwareButton | `-_acceleratedSinglePressRecognizerShouldBegin` | 0x1c5e99958 | 0x1c730c620 | TRIAGE PENDING |
| SBHomeHardwareButtonActions | `-performSinglePressUpActionsWithSourceType:` | 0x1c6144ea8 | 0x1c75c8670 | TRIAGE PENDING |
| SBHomeScreenBackdropView | `-_updateBackdropViewIfNeededInvalidatingSnapshot:` | 0x1c5ea20e8 | 0x1c7314d90 | IRRELEVANT: home screen blur snapshot / opaque layer only |
| SBHomeScreenBackdropView | `-homeScreenBlurredContentSnapshotImage` | 0x1c62977dc | 0x1c7731058 | IRRELEVANT: home screen blur snapshot / opaque layer only |
| SBHomeScreenContinuousExposeSwitcherModifier | `-init` | 0x1c634e174 | 0x1c77f3898 | PORTED already: 16.2 address cited in G1C.x |
| SBHomeScreenViewController | `-_acquireFloatingDockBehaviorAssertionIfNecessaryForFloatingDockController:` | 0x1c637a27c | 0x1c7821698 | TRIAGE PENDING |
| SBHomeScreenWindow | `-initWithWindowScene:rootViewController:layoutStrategy:role:debugName:` | 0x1c63e935c | 0x1c7895b98 | TRIAGE PENDING |
| SBIconController | `-_effectiveOrientation` | 0x1c5e65b1c | 0x1c72d83dc | EQUIVALENT: edge fallback only (view not loaded / no window orientation: 16.2 derives the orientation from allowedInterfaceOrientations); main display home screen |
| SBIconController | `-policyAggregator` | 0x1c601882c | 0x1c749107c | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-widgetMetricsServer` | 0x1c6032574 | 0x1c74910e4 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-_launchWidgetIcon:fromLocation:withContext:` | 0x1c6018380 | 0x1c7492dc8 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-_containerViewControllerForPresentingFromTodayViewControllerAllowingCoverSheet:` | 0x1c6018b68 | 0x1c7493538 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-_registerAnalytics` | 0x1c601a500 | 0x1c7494ecc | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-_mutateIconListsForInstalledAppsDidChangeWithController:added:modified:removed:` | 0x1c601cac4 | 0x1c7497490 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-setModel:` | 0x1c601d63c | 0x1c7497fec | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-_appLibraryListLayoutProviderForWindowScene:` | 0x1c60211c4 | 0x1c749bb60 | TRIAGE PENDING |
| SBIconController | `-iconManager:willOpenFolderController:` | 0x1c6021cb8 | 0x1c749c670 | EQUIVALENT: wallpaper suspension assertion per open folder moved from a map table ivar to the folder controller's extraAssertions dictionary (same assertion, same lifetime) |
| SBIconController | `-iconManager:willCloseFolderController:` | 0x1c6021dc0 | 0x1c749c790 | EQUIVALENT: wallpaper suspension assertion per open folder moved from a map table ivar to the folder controller's extraAssertions dictionary (same assertion, same lifetime) |
| SBIconController | `-distanceToTopOfSpotlightIconsForIconManager:` | 0x1c6021f64 | 0x1c749c940 | IRRELEVANT: main display home screen search pill / Spotlight pull-down layout (the pill moved into the scroll accessory container, rootViewController property): no windowing, display, keyboard focus or pointer behaviour |
| SBIconController | `-iconManagerCanUseSeparateWindowForRotation:` | 0x1c60220fc | 0x1c749ca70 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-isIconContentPossiblyVisibleOverApplicationForIconManager:` | 0x1c6022328 | 0x1c749cc94 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-iconManager:wantsLaunchForWidgetURL:` | 0x1c6022a0c | 0x1c749d370 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-searchPresenterCanPresent:` | 0x1c6025254 | 0x1c749fbb8 | IRRELEVANT: main display home screen search pill / Spotlight pull-down layout (the pill moved into the scroll accessory container, rootViewController property): no windowing, display, keyboard focus or pointer behaviour |
| SBIconController | `-searchAffordanceViewForSpotlightPresentableViewController:` | 0x1c60256f4 | 0x1c74a0078 | IRRELEVANT: main display home screen search pill / Spotlight pull-down layout (the pill moved into the scroll accessory container, rootViewController property): no windowing, display, keyboard focus or pointer behaviour |
| SBIconController | `-_isHostedByCoverSheet` | 0x1c6025c6c | 0x1c74a0714 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-iconManager:willDestroyRootViewController:` | 0x1c6027ca0 | 0x1c74a2740 | IRRELEVANT: main display home screen search pill / Spotlight pull-down layout (the pill moved into the scroll accessory container, rootViewController property): no windowing, display, keyboard focus or pointer behaviour |
| SBIconController | `-iconManager:willUseRootFolderControllerConfiguration:` | 0x1c6027d08 | 0x1c74a27b4 | IRRELEVANT: main display home screen search pill / Spotlight pull-down layout (the pill moved into the scroll accessory container, rootViewController property): no windowing, display, keyboard focus or pointer behaviour |
| SBIconController | `-iconManager:didCreateRootViewController:` | 0x1c6028434 | 0x1c74a2f30 | IRRELEVANT: main display home screen search pill / Spotlight pull-down layout (the pill moved into the scroll accessory container, rootViewController property): no windowing, display, keyboard focus or pointer behaviour |
| SBIconController | `-isRootFolderContentVisibleForIconManager:` | 0x1c60284f8 | 0x1c74a3018 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-isEditingAllowedForIconManager:` | 0x1c6028554 | 0x1c74a306c | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-iconManagerDidFinishInstallForIcon:` | 0x1c6028b2c | 0x1c74a3644 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-iconManager:homeScreenContentViewForModalInteractionFromIconView:` | 0x1c6029990 | 0x1c74a44a0 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-iconManager:wantsUninstallForIcon:location:` | 0x1c6029e08 | 0x1c74a4914 | 7dd10ca: Y4Home.x y4_alertscene (the hide / delete confirmation items prefer the home screen's own window scene) [sha f7e180d] |
| SBIconController | `-iconManagerWillPresentWidgetEditing:` | 0x1c602de98 | 0x1c74a89c8 | 7dd10ca: Y4Home.x y4_widgetfocus (focus stealing for the home screen window while the widget gallery is up, new ivar as associated object) [sha f7e180d] |
| SBIconController | `-iconManagerDidDismissWidgetEditing:` | 0x1c602df5c | 0x1c74a8b2c | 7dd10ca: Y4Home.x y4_widgetfocus (focus stealing for the home screen window while the widget gallery is up, new ivar as associated object) [sha f7e180d] |
| SBIconController | `-iconManager:displayFeatureIntroductionItemIfUnlocked:` | 0x1c602e7c4 | 0x1c74a93c0 | EQUIVALENT: 16.2 injects SpringBoard's singletons into SBIconController as properties (lockScreenManager, analyticsClient, coverSheetPresentationManager, mainDisplaySceneManager, policyAggregator, mainDisplayWindowScene ivar rename); the objects are the same ones the 16.0 code reaches through +sharedInstance / +[SBSceneManagerCoordinator mainDisplaySceneManager]; the icon controller is the main display's home screen in both builds |
| SBIconController | `-.cxx_destruct` | 0x1c603278c | 0x1c74ad430 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBMainDisplaySceneLayoutStatusBarView | `-_applyStatusBarHidden:withAnimation:toSceneWithIdentifier:` | 0x1c60bdb80 | 0x1c7542248 | TO PORT: 16.2 updates the recording indicator manager of the view's own window scene (16.0: the main display's); the manager is captured before the animation block, needs a block level change |
| SBMainDisplaySceneLayoutStatusBarView | `-_applyStatusBarAlpha:toSceneWithIdentifier:` | 0x1c60be3f8 | 0x1c7542ad0 | TO PORT: 16.2 updates the recording indicator manager of the view's own window scene (16.0: the main display's); the manager is captured before the animation block, needs a block level change |
| SBStatusBarForcedHiddenTestRecipe | `-_toggleWithAnimationSettings:` | 0x1c6261158 | 0x1c76f84e0 | IRRELEVANT: internal test recipes |
| SBStatusBarReusePool | `-getReusableStatusBarWithReason:withFrame:` | 0x1c63e4cb0 | 0x1c78911f4 | 7dd10ca: Y5Apps.x y5_sbpool (modern bar target screen = the pool's window scene screen) [sha eb694cd] |
| SBStatusBarStateAggregator | `-updateStatusBarItem:` | 0x1c5e1ccd8 | 0x1c728ecd4 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-endCoalescentBlock` | 0x1c5e1d3f0 | 0x1c728f3f8 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_updateActivityItem` | 0x1c5e1dad4 | 0x1c728fab8 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-initWithMainDisplayWindowScene:registerForNotifications:` | 0x1c647b360 | 0x1c7930f88 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_registerForNotifications` | 0x1c647bf48 | 0x1c7931b90 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_updateSignalStrengthItem:withData:SIMInfo:barsGetter:barsSetter:` | 0x1c647eb20 | 0x1c79349e0 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_updateServiceItem:withData:SIMInfo:otherSIMInfo:serviceStringGetter:serviceStringSetter:serviceCrossfadeStringGetter:serviceCrossfadeStringSetter:serviceContentTypeGetter:serviceContentTypeSetter:serviceBadgeStringGetter:serviceBadgeStringSetter:` | 0x1c647f6a0 | 0x1c7935574 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_updateBatteryItems` | 0x1c648040c | 0x1c7936414 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_updateAirplayItem` | 0x1c6481640 | 0x1c7937690 | EQUIVALENT: main display status bar data: singleton lookups became injected / shim lookups of the same objects (recording indicator manager of the main window scene = G5 manager, +sharedInstanceIfExists, active display controller) |
| SBStatusBarStateAggregator | `-_updateSensorActivityItem` | 0x1c648199c | 0x1c79379c8 | EQUIVALENT: main display status bar data: singleton lookups became injected / shim lookups of the same objects (recording indicator manager of the main window scene = G5 manager, +sharedInstanceIfExists, active display controller) |
| SBStatusBarStateAggregator | `-_updateStatusBarForSystemStatusDomainName:data:` | 0x1c6481bb4 | 0x1c7937be4 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_updateStatusBarStyleOverrideAssertionsForSystemStatusDomain:andData:` | 0x1c6481c40 | 0x1c7937c84 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-setBatteryChargingState:` | 0x1c64831d8 | 0x1c793949c | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-_invalidateSystemApertureChargingElementAssertionForReason:` | 0x1c6483390 | 0x1c7939638 | IRRELEVANT: main display status bar data model: new Stewie (satellite SOS) item, Live Activity / aperture charging element, battery and signal items (iPhone hardware); item enum 0x2c -> 0x2d; ivar offsets |
| SBStatusBarStateAggregator | `-activityDidChangeForSensorActivityDataProvider:` | 0x1c6483ec8 | 0x1c793a174 | EQUIVALENT: main display status bar data: singleton lookups became injected / shim lookups of the same objects (recording indicator manager of the main window scene = G5 manager, +sharedInstanceIfExists, active display controller) |
| SBStatusBarStateAggregator | `-_updateActiveAudioRecordingStatusBarStyleOverrideAssertionsForActiveSensorActivityAttributions:` | 0x1c6484110 | 0x1c793a3bc | EQUIVALENT: main display status bar data: singleton lookups became injected / shim lookups of the same objects (recording indicator manager of the main window scene = G5 manager, +sharedInstanceIfExists, active display controller) |
| SBStatusBarStateAggregator | `-.cxx_destruct` | 0x1c64843e8 | 0x1c793a6c4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBStatusBarTapManager | `-_foregroundApplicationDestinationsForApplications:` | 0x1c63f0490 | 0x1c789cd14 | IRRELEVANT: adds the apps that own an active System Aperture element (Dynamic Island, iPhone only) |
| SBTouchRegionManager | `-layoutMonitor:didUpdateDisplayLayout:withContext:` | 0x1c5e3b948 | 0x1c72adc2c | EQUIVALENT: queue ivar replaced by a global queue constant |
| _SBAppContainerStatusBarStateProxy | `-_fallbackInterfaceOrientation` | 0x1c62de730 | 0x1c77791b0 | EQUIVALENT: rename only (contentInterfaceOrientation -> contentOrientation on the same property) |

## F3 Switcher / Medusa / PiP / floating / deck / layout, transactions and modifiers (666)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBAppContainerViewController | `-configureWithWorkspaceEntity:forLayoutElement:layoutState:referenceFrame:` | 0x1c5e2f534 | 0x1c72a1c44 | TRIAGE PENDING |
| SBAppLayout | `-appLayoutByModifyingHiddenState:` | 0x1c628ce40 | 0x1c7725bb8 | TRIAGE PENDING |
| SBAppLayout | `-continuousExposeIdentifier` | 0x1c628d514 | 0x1c77265c4 | PORTED already: hook in G2.x:1733 |
| SBAppLayout | `-isInsetForHomeAffordance` | 0x1c628e03c | 0x1c77270e8 | 7dd10ca: Y8Layout.x y8_insethome (no home affordance inset under Stage Manager, new _preferredWindowScene) |
| SBAppLayout | `-preferredDisplayIdentity` | 0x1c628e1a0 | 0x1c77273a8 | EQUIVALENT: 16.2 only moves the scene search into the new helper _preferredWindowScene (same selection: ordinal 1 = external scene), added by Y8Layout.x |
| SBAppLayoutOverlappingModelCacheKey | `-hash` | 0x1c62ee438 | 0x1c778a400 | PORTED already: hook in G2.x:1808 |
| SBAppLayoutOverlappingModelCacheKey | `-isEqual:` | 0x1c62ee678 | 0x1c778a5e8 | PORTED already: hook in G2.x:1802 |
| SBAppLayoutOverlappingModelCacheKey | `-copyWithZone:` | 0x1c62ee78c | 0x1c778a6ec | PORTED already: hook in G2.x:1812 |
| SBAppLayoutOverlappingModelCacheKey | `-.cxx_destruct` | 0x1c62ee84c | 0x1c778ac40 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBAppResizeGrabberView | `-initWithCorner:` | 0x1c5faea68 | 0x1c7426e48 | TRIAGE PENDING |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-init` | 0x1c636a29c | 0x1c780f6bc | TRIAGE PENDING |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-handleScrollEvent:` | 0x1c636a3d4 | 0x1c780f7dc | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-frameForIndex:` | 0x1c636a53c | 0x1c780fe78 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-frameForLayoutRole:inAppLayout:withBounds:` | 0x1c636a5a8 | 0x1c780fe84 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-scaleForIndex:` | 0x1c636a9ec | 0x1c780ff80 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-titleAndIconOpacityForIndex:` | 0x1c636ab74 | 0x1c7810020 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-visibleAppLayouts` | 0x1c636ae50 | 0x1c7810118 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-topMostLayoutElements` | 0x1c636b3ac | 0x1c7810410 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-opacityForLayoutRole:inAppLayout:atIndex:` | 0x1c636b62c | 0x1c7810644 | TRIAGE PENDING |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-cornerRadiiForIndex:` | 0x1c636b654 | 0x1c78106d4 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-appLayoutsToCacheSnapshots` | 0x1c636b6a8 | 0x1c7810c28 | TRIAGE PENDING |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-indexToScrollToAfterRemovingIndex:` | 0x1c636bc6c | 0x1c7811564 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-_indexOfLeadingAppLayout` | 0x1c636bcbc | 0x1c78115d4 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-snapshotScaleForAppLayout:` | 0x1c636bda8 | 0x1c781239c | TRIAGE PENDING |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-_contentSize` | 0x1c636bed4 | 0x1c78124c8 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-_fittedContentSize` | 0x1c636bf40 | 0x1c7812504 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-contentOffsetForIndex:alignment:` | 0x1c636bfd8 | 0x1c7812518 | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherContinuousExposeSwitcherModifier | `-distanceToLeadingEdgeOfLeadingCardFromTrailingEdgeOfScreenWithVisibleIndexToStartSearch:` | 0x1c636c158 | 0x1c781264c | PORTED already: 16.2 address cited in G1C.x |
| SBAppSwitcherPageView | `-initWithFrame:` | 0x1c5e5cba4 | 0x1c72cf0a4 | TRIAGE PENDING |
| SBAppSwitcherPageView | `-willMoveToWindow:` | 0x1c5f1a404 | 0x1c738eac0 | TRIAGE PENDING |
| SBAppSwitcherPageView | `-invalidate` | 0x1c5f1ae98 | 0x1c738f548 | TRIAGE PENDING |
| SBAppSwitcherPageView | `-pointerWillExitRegion` | 0x1c5f1ba90 | 0x1c7390130 | TRIAGE PENDING |
| SBAppSwitcherPageView | `-styleForRegion:forView:` | 0x1c5f1bbd8 | 0x1c739027c | TRIAGE PENDING |
| SBAppSwitcherReusableSnapshotView | `-_snapshotImageFrameForCacheEntry:` | 0x1c5e35608 | 0x1c72a7a60 | TRIAGE PENDING |
| SBAppSwitcherReusableSnapshotView | `-prepareForReuse` | 0x1c5e70774 | 0x1c72e3504 | TRIAGE PENDING |
| SBAppSwitcherReusableSnapshotView | `-initWithDelegate:snapshotCache:lockoutVCProvider:appClipOverlayCoordinator:containerViewController:` | 0x1c646a704 | 0x1c791fdbc | TRIAGE PENDING |
| SBAppSwitcherReusableSnapshotView | `-dealloc` | 0x1c646ae1c | 0x1c792038c | TRIAGE PENDING |
| SBAppSwitcherReusableSnapshotView | `-_contentOrientationForSnapshotCacheEntry:` | 0x1c646c7f0 | 0x1c7921eec | TRIAGE PENDING |
| SBAppSwitcherSettings | `-chamoisSettings` | 0x1c6385014 | 0x1c782cf88 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-_loadSnapshotForRequest:withDisplayItem:inAppLayout:` | 0x1c5e45610 | 0x1c72b7a54 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-_representedApplicationSceneEntityForDisplayItem:` | 0x1c5e45fdc | 0x1c72b84f4 | PORTED already: hook in G1D.x:2562 |
| SBAppSwitcherSnapshotImageCache | `-_cacheSnapshotForRequest:withDisplayItem:inAppLayout:` | 0x1c5e4637c | 0x1c72b898c | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-_asynchronouslyLoadSnapshotFromRequest:` | 0x1c5e4f164 | 0x1c72c13e0 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-_snapshotImage:finishedLoadingForRequest:` | 0x1c5e4f994 | 0x1c72c1d64 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-setCachableAppLayouts:` | 0x1c6302dcc | 0x1c77a0818 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-cachableAppLayouts` | 0x1c6302ee4 | 0x1c77a0940 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-setFullSizeCachableAppLayouts:` | 0x1c6303038 | 0x1c77a0a98 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-fullSizeCachableAppLayouts` | 0x1c6303150 | 0x1c77a0bc0 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-reloadSnapshotsForInterfaceStyleChange:` | 0x1c6303860 | 0x1c77a12d4 | TRIAGE PENDING |
| SBAppSwitcherSnapshotImageCache | `-_createDownscaledVariantForRequest:snapshot:displayItem:sceneHandle:application:` | 0x1c6303e78 | 0x1c77a1a00 | TRIAGE PENDING |
| SBAppViewController | `-viewWillTransitionToSize:withTransitionCoordinator:` | 0x1c5ea7fa4 | 0x1c731acf4 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBAppViewController | `-_createSceneViewController` | 0x1c5eb715c | 0x1c7329f40 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBAppViewController | `-_deactivateHostedApp` | 0x1c5eb7440 | 0x1c732a234 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBAppViewController | `-_activateApp` | 0x1c5eb81d4 | 0x1c732afb8 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBAppViewController | `-_transformHostedAppViewForRotationToOrientation:` | 0x1c5eb8494 | 0x1c732b264 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBAppViewController | `-_createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:` | 0x1c5eb8824 | 0x1c732b5f8 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBArcSwipeSwitcherModifier | `-transitionWillBegin` | 0x1c648955c | 0x1c793f864 | TRIAGE PENDING |
| SBArcSwipeSwitcherModifier | `-.cxx_destruct` | 0x1c6489c68 | 0x1c79400c8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBAutoPIPWorkspaceTransaction | `+shouldAutoPIPEnteringBackgroundForRequest:foundEntity:tetheringMode:transitionStyle:reason:` | 0x1c622d8a0 | 0x1c76bfe88 | TRIAGE PENDING |
| SBBlurItemContainerParameters | `+defaultCrossblurBlurParameters` | 0x1c6396d94 | 0x1c7840144 | TRIAGE PENDING |
| SBCenterWindowPagePresentationSwitcherModifier | `-initWithTransitionID:toAppLayout:isMorph:` | 0x1c638ff88 | 0x1c78392a8 | TRIAGE PENDING |
| SBCenterWindowPagePresentationSwitcherModifier | `-.cxx_destruct` | 0x1c6390598 | 0x1c7839998 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBChamoisOverlappingController | `-_snapPositionToNearestEdgesIfNecessary:draggingItem:` | 0x1c5f55404 | 0x1c73cb40c | PORTED already: 16.2 address cited in G2.x |
| SBChamoisOverlappingModel | `-mutableCopyWithZone:` | 0x1c64bfd8c | 0x1c797a72c | PORTED already: hook in G2.x:569 |
| SBChamoisOverlappingModel | `-.cxx_destruct` | 0x1c64bff38 | 0x1c797b050 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBContinuousExposeAppToAppModifier | `-didMoveToParentModifier:` | 0x1c610b99c | 0x1c759598c | PORTED already: 16.2 address cited in G1C.x, G1B.x |
| SBContinuousExposeAppToAppModifier | `-asyncRenderingDisabled` | 0x1c610baa0 | 0x1c7595acc | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeAppToAppModifier | `-transitionWillBegin` | 0x1c610bac0 | 0x1c7595b40 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeAppToAppModifier | `-animationAttributesForLayoutElement:` | 0x1c610bd0c | 0x1c7595bd8 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeAppToAppModifier | `-isLayoutRoleMatchMovedToScene:inAppLayout:` | 0x1c610c154 | 0x1c7595f80 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeIdentifierSlideModifier | `-frameForIndex:` | 0x1c63c5954 | 0x1c7870404 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeIdentifierSlideModifier | `-adjustedSpaceAccessoryViewFrame:forAppLayout:` | 0x1c63c5ae8 | 0x1c7870ad0 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeIdentifierSlideModifier | `-handleContinuousExposeIdentifiersChangedEvent:` | 0x1c63c5d90 | 0x1c7870e9c | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeIdentifierSlideModifier | `-handleTimerEvent:` | 0x1c63c5eec | 0x1c7871040 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeIdentifierSlideModifier | `-_beginAnimation` | 0x1c63c6030 | 0x1c78711b4 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeIdentifierSlideModifier | `-.cxx_destruct` | 0x1c63c6108 | 0x1c7871434 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBContinuousExposeIdentifiersChangedModifierEvent | `-copyWithZone:` | 0x1c625da3c | 0x1c76f4c18 | TRIAGE PENDING |
| SBContinuousExposeIdentifiersChangedModifierEvent | `-.cxx_destruct` | 0x1c625dae4 | 0x1c76f4de8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBContinuousExposeRootSwitcherModifier | `-floorModifierForTransitionEvent:` | 0x1c6370db8 | 0x1c78180e8 | PORTED already: hook in G1C.x:5214 |
| SBContinuousExposeRootSwitcherModifier | `-transitionModifierForMainTransitionEvent:` | 0x1c6371228 | 0x1c781859c | PORTED already: hook in G1B.x:2086, G1C.x:5453 |
| SBContinuousExposeRootSwitcherModifier | `-gestureModifierForGestureEvent:` | 0x1c6371600 | 0x1c7818d78 | PORTED already: hook in G1C.x:5298 |
| SBContinuousExposeRootSwitcherModifier | `-handleTransitionEvent:` | 0x1c6371a34 | 0x1c7819470 | PORTED already: hook in G1C.x:5368 |
| SBContinuousExposeRootSwitcherModifier | `-handleContinuousExposeIdentifiersChangedEvent:` | 0x1c6371ad4 | 0x1c78195b8 | PORTED already: hook in G1C.x:5406 |
| SBContinuousExposeRootSwitcherModifier | `-_effectiveEnvironmentMode` | 0x1c6372a88 | 0x1c7819cb8 | PORTED already: hook in G1B.x:2114 |
| SBContinuousExposeRootSwitcherModifier | `-.cxx_destruct` | 0x1c6372b28 | 0x1c7819d98 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | `-initWithSelectedDisplayItem:initialAppLayout:delegate:` | 0x1c6070530 | 0x1c74f2fe8 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | `-handleGestureEvent:` | 0x1c6070880 | 0x1c74f3330 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | `-_widthThresholdToHideStrips` | 0x1c60710b4 | 0x1c74f3d8c | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | `-_frameForSelectedDisplayItem` | 0x1c607118c | 0x1c74f3dd8 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | `-_appLayoutByAddingItem:toAppLayout:size:center:` | 0x1c6071370 | 0x1c74f406c | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragDestinationSwitcherModifier | `-.cxx_destruct` | 0x1c60718bc | 0x1c74f47fc | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBContinuousExposeWindowDragModifierEvent | `-copyWithZone:` | 0x1c63ccf1c | 0x1c7878bfc | PORTED already: hook in G1C.x:3071 |
| SBContinuousExposeWindowDragRootSwitcherModifier | `-gestureChildModifierForGestureEvent:activeTransitionModifier:` | 0x1c5fe6910 | 0x1c7461188 | TRIAGE PENDING |
| SBContinuousExposeWindowDragRootSwitcherModifier | `-handleTransitionEvent:` | 0x1c5fe6abc | 0x1c7461458 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragSwitcherModifier | `-preferredCenterForSelectedItemInDestinationModifier:` | 0x1c6180d90 | 0x1c7609494 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragSwitcherModifier | `-handleGestureEvent:` | 0x1c6180e64 | 0x1c7609578 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragSwitcherModifier | `-frameForIndex:` | 0x1c6181744 | 0x1c760a1e0 | TRIAGE PENDING |
| SBContinuousExposeWindowDragSwitcherModifier | `-scaleForIndex:` | 0x1c6181970 | 0x1c760a4b4 | TRIAGE PENDING |
| SBContinuousExposeWindowDragSwitcherModifier | `-shouldPinLayoutRolesToSpace:` | 0x1c6181bb8 | 0x1c760a7e0 | TRIAGE PENDING |
| SBContinuousExposeWindowDragSwitcherModifier | `-frameForLayoutRole:inAppLayout:withBounds:` | 0x1c6181c58 | 0x1c760a8a8 | TRIAGE PENDING |
| SBContinuousExposeWindowDragSwitcherModifier | `-topMostLayoutElements` | 0x1c6181ffc | 0x1c760adb0 | PORTED already: 16.2 address cited in G1C.x |
| SBContinuousExposeWindowDragSwitcherModifier | `-animationAttributesForLayoutElement:` | 0x1c61820a0 | 0x1c760ae5c | TRIAGE PENDING |
| SBContinuousExposeWindowDragSwitcherModifier | `-perspectiveAngleForAppLayout:` | 0x1c618248c | 0x1c760b1fc | TRIAGE PENDING |
| SBContinuousExposeWindowDragSwitcherModifier | `-_appLayoutContainingDisplayItem:` | 0x1c6182694 | 0x1c760b404 | PORTED already: 16.2 address cited in G1C.x |
| SBCrossfadeDosidoSwitcherModifier | `-frameForIndex:` | 0x1c638c57c | 0x1c783537c | PORTED already: hook in G1B.x:2674 |
| SBCrossfadeDosidoSwitcherModifier | `-scaleForIndex:` | 0x1c638c5ec | 0x1c78353ec | PORTED already: hook in G1B.x:2679 |
| SBDeckFloatingSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c6312e6c | 0x1c77b19a4 | TRIAGE PENDING |
| SBDeckSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c642bc48 | 0x1c78dbad4 | TRIAGE PENDING |
| SBDeckSwitcherViewController | `-performTransitionWithContext:animated:completion:` | 0x1c5ea2514 | 0x1c73151d8 | TRIAGE PENDING |
| SBDeckSwitcherViewController | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c632894c | 0x1c77c97c0 | TRIAGE PENDING |
| SBDeckSwitcherViewController | `-layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` | 0x1c6328aec | 0x1c77c99cc | TRIAGE PENDING |
| SBDeckSwitcherViewController | `-.cxx_destruct` | 0x1c6328ee4 | 0x1c77c9f14 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDeviceApplicationSceneClassicAccessoryView | `-_rotateApplicationScene:` | 0x1c60e9b10 | 0x1c756e464 | TRIAGE PENDING |
| SBDeviceApplicationSceneClassicWrapperView | `+shouldUseWrapperViewForSceneHandle:` | 0x1c642041c | 0x1c78cfbac | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneClassicWrapperView | `-initWithSceneHandle:` | 0x1c64204b8 | 0x1c78cfc5c | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneClassicWrapperView | `-layoutSubviews` | 0x1c64207e0 | 0x1c78d0208 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneClassicWrapperView | `-.cxx_destruct` | 0x1c64210ec | 0x1c78d0e30 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDeviceApplicationSceneOverlayViewProvider | `-.cxx_destruct` | 0x1c5e688ac | 0x1c72db1ac | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDeviceApplicationSceneOverlayViewProvider | `-overlayViewController` | 0x1c649a6d4 | 0x1c7950fc0 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneOverlayViewProvider | `-bestHomeAffordanceOrientationForOrientation:` | 0x1c649a724 | 0x1c7951020 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneOverlayViewProvider | `-_activateIfPossible` | 0x1c649a894 | 0x1c79511d8 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneOverlayViewProvider | `-_deactivateIfPossible` | 0x1c649a97c | 0x1c7951310 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-layoutSubviews` | 0x1c5e3c390 | 0x1c72ae66c | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-dealloc` | 0x1c5e6a514 | 0x1c72dd094 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-.cxx_destruct` | 0x1c5e6a588 | 0x1c72dd138 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDeviceApplicationSceneView | `-_tearDownHostCounterRotationViewIfNecessary` | 0x1c5e763e4 | 0x1c72e8cf4 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-addOverlayView:withPriority:` | 0x1c62a2e4c | 0x1c773cd30 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-_createHostCounterRotationViewIfNecessary` | 0x1c62a35b4 | 0x1c773d4c4 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-_updateReferenceSize:andOrientation:` | 0x1c62a4210 | 0x1c773e23c | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView | `-_maybeStartTrackingRotationForOverlayFromOrientation:toOrientation:` | 0x1c62a42a8 | 0x1c773e2ec | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneViewController | `-.cxx_destruct` | 0x1c5e6a2e4 | 0x1c72dce54 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDeviceApplicationSceneViewController | `-_createSceneOverlayViewProvidersIfNecessary` | 0x1c6130e88 | 0x1c75bbb70 | IRRELEVANT: secure display (lock screen) rendersWhileLocked and display mode notifications to the overlay providers; same providers are created in 16.0 |
| SBDeviceApplicationSceneViewController | `-_createStatusBar` | 0x1c61312a0 | 0x1c75bc038 | 7dd10ca: Y5Apps.x y5_sbpool (the status bar goes back into the reuse pool it came from when the window moved to the other display) [sha eb694cd] |
| SBDeviceApplicationSceneViewController | `-_configureStatusBarWithCurrentStyleRequest` | 0x1c6131834 | 0x1c75bc5ec | PORTED already: 16.2 address cited in X5Recording.x |
| SBDeviceApplicationSceneViewController | `-_removeStatusBar` | 0x1c613214c | 0x1c75bcefc | 7dd10ca: Y5Apps.x y5_sbpool (the status bar goes back into the reuse pool it came from when the window moved to the other display) [sha eb694cd] |
| SBDeviceApplicationSceneViewController | `-_configureForSecureDisplay:` | 0x1c6132918 | 0x1c75bd6b4 | IRRELEVANT: secure display (lock screen) rendersWhileLocked and display mode notifications to the overlay providers; same providers are created in 16.0 |
| SBDeviceApplicationSceneViewPlaceholderContentViewProvider | `-sceneView:requestsPlaceholderContentViewWithContext:` | 0x1c5e3780c | 0x1c72a9bf8 | TRIAGE PENDING |
| SBDismissOverlaysAnimationController | `-initWithTransitionContextProvider:options:` | 0x1c5ea7524 | 0x1c731a220 | EQUIVALENT: display identity now read from the stored transition context instead of an ivar (same identity) |
| SBDismissOverlaysAnimationController | `-_startAnimation` | 0x1c5ea7634 | 0x1c731a36c | EQUIVALENT: display identity now read from the stored transition context instead of an ivar (same identity) |
| SBDisplayItem | `-descriptionBuilderWithMultilinePrefix:` | 0x1c5e4668c | 0x1c72b8cf8 | EXCLUDED: description / debug text only |
| SBDisplayItem | `-succinctDescriptionBuilder` | 0x1c5e46750 | 0x1c72b8cfc | EXCLUDED: description / debug text only |
| SBDisplayItemLayoutAttributes | `-init` | 0x1c614b6e8 | 0x1c75cf3c4 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-copyWithZone:` | 0x1c614b710 | 0x1c75cf424 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-isEqual:` | 0x1c614b768 | 0x1c75cf4ac | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-centerInBounds:` | 0x1c614b920 | 0x1c75cf654 | PORTED already: 16.2 address cited in G1C.x, G2B.m |
| SBDisplayItemLayoutAttributes | `-attributesByModifyingContentOrientation:` | 0x1c614ba78 | 0x1c75cf6f8 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-attributesByModifyingLastInteractionTime:` | 0x1c614baec | 0x1c75cf7a8 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-attributesByModifyingSizingPolicy:` | 0x1c614bb60 | 0x1c75cf858 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-attributesByModifyingOcclusionState:` | 0x1c614bd84 | 0x1c75cfaa4 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-initWithPlistRepresentation:` | 0x1c614bf00 | 0x1c75cfcec | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-plistRepresentation` | 0x1c614c1d8 | 0x1c75d0200 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `+layoutAttributesWithProtobufRepresentation:` | 0x1c614c344 | 0x1c75d0434 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-protobufRepresentation` | 0x1c614c474 | 0x1c75d05fc | TRIAGE PENDING |
| SBDisplayItemLayoutAttributes | `-descriptionBuilderWithMultilinePrefix:` | 0x1c614c5c8 | 0x1c75d0798 | EXCLUDED: description / debug text only |
| SBDisplayItemLayoutAttributesCalculator | `-frameForLayoutRole:inAppLayout:containerOrientation:windowScene:` | 0x1c611954c | 0x1c75a3390 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributesCalculator | `-_frameForLayoutRole:inAppLayout:containerBounds:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:isChamoisWindowingUIEnabled:prefersStripHidden:prefersDockHidden:skipAutoLayout:` | 0x1c61197b8 | 0x1c75a3614 | PORTED already: 16.2 address cited in G2B.m |
| SBDisplayItemLayoutAttributesCalculator | `-layoutRestrictionInfoForItem:` | 0x1c611a5f0 | 0x1c75a4670 | TRIAGE PENDING |
| SBDisplayItemLayoutAttributesCalculator | `-_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:draggingItem:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:` | 0x1c611a81c | 0x1c75a4848 | PORTED already: 16.2 address cited in G2B.m |
| SBDisplayItemLayoutAttributesCalculator | `-_deviceApplicationSceneHandleForDisplayItem:` | 0x1c611b7ec | 0x1c75a5784 | PORTED already: 16.2 address cited in G1D.x |
| SBDisplayItemLayoutGrid | `-_gridForBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:` | 0x1c6468bdc | 0x1c791e180 | PORTED already: hook in G3B.x:1688 |
| SBDragAndDropWorkspaceTransaction | `+_shouldTrackLocationOfDropSession:forSwitcherController:isCurrentlyTracking:` | 0x1c626e7a8 | 0x1c770691c | TO PORT: 16.2 asks the switcher view controller for _areContinuousExposeStripsUnoccluded and chamoisLayoutAttributes.stripWidth instead of the chamois settings for the window scene (strip hit area of drag and drop on each display) |
| SBDragAndDropWorkspaceTransaction | `-_platterSizeForDropAction:proposedDropLayoutState:setDown:` | 0x1c6272d10 | 0x1c770aea8 | TO PORT: 16.2 sizes the platter from [switcherController frameForItemWithRole:inMainAppLayout:interfaceOrientation:] for the layout state of the proposed drop (16.0 generic app layout path) |
| SBDragAndDropWorkspaceTransaction | `-_begin` | 0x1c6274da8 | 0x1c770cf64 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBDragAndDropWorkspaceTransaction | `-_transitionRequestForDropAction:` | 0x1c6277084 | 0x1c770f26c | TO PORT: 16.2: normalized center attributes (attributesByModifyingNormalizedCenter:) and content / container orientation for the platter scene view |
| SBDragAndDropWorkspaceTransaction | `-_configurePlatterPreview:forSceneHandle:completion:` | 0x1c62786e4 | 0x1c77108cc | TO PORT: 16.2: normalized center attributes (attributesByModifyingNormalizedCenter:) and content / container orientation for the platter scene view |
| SBEntityRemovalCrossblurSwitcherModifier | `-visibleAppLayouts` | 0x1c6182dc4 | 0x1c760bd3c | TRIAGE PENDING |
| SBEntityRemovalCrossblurSwitcherModifier | `-frameForIndex:` | 0x1c6182de0 | 0x1c760bdb8 | TRIAGE PENDING |
| SBEntityRemovalCrossblurSwitcherModifier | `-scaleForIndex:` | 0x1c6182de4 | 0x1c760becc | TRIAGE PENDING |
| SBEntityRemovalCrossblurSwitcherModifier | `-animationAttributesForLayoutElement:` | 0x1c6182e58 | 0x1c760c410 | TRIAGE PENDING |
| SBEntityRemovalCrossblurSwitcherModifier | `-opacityForLayoutRole:inAppLayout:atIndex:` | 0x1c6182f44 | 0x1c760c640 | TRIAGE PENDING |
| SBEntityRemovalSlideOffscreenSwitcherModifier | `-visibleAppLayouts` | 0x1c5f9ba5c | 0x1c7414268 | TRIAGE PENDING |
| SBEntityRemovalSlideOffscreenSwitcherModifier | `-frameForIndex:` | 0x1c5f9ba78 | 0x1c74142e4 | TRIAGE PENDING |
| SBEntityRemovalSlideOffscreenSwitcherModifier | `-scaleForIndex:` | 0x1c5f9bb18 | 0x1c741445c | TRIAGE PENDING |
| SBEntityRemovalSlideOffscreenSwitcherModifier | `-animationAttributesForLayoutElement:` | 0x1c5f9bb78 | 0x1c7414b2c | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-grabberTongue:shouldReceiveTouch:` | 0x1c5e52900 | 0x1c72c4d40 | PORTED already: hook in G1D.x:1363 |
| SBFluidSwitcherGestureManager | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c5e529d0 | 0x1c72c4e70 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-grabberTongue:shouldShowTongueOnFirstSwipeWithEdgeLocation:` | 0x1c5e56c48 | 0x1c72c90ac | PORTED already: hook in G1D.x:1374 |
| SBFluidSwitcherGestureManager | `-grabberTongue:shouldAllowSecondSwipeWithEdgeLocation:` | 0x1c5e58070 | 0x1c72ca7a0 | PORTED already: hook in G1D.x:1378 |
| SBFluidSwitcherGestureManager | `-_gestureTypeForGestureRecognizer:` | 0x1c5e585b4 | 0x1c72cad14 | PORTED already: hook in G1D.x:1355 |
| SBFluidSwitcherGestureManager | `-setActiveGestureTransaction:` | 0x1c5e58e5c | 0x1c72cb5f8 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-failMultitaskingGesturesForReason:` | 0x1c5ea0a20 | 0x1c73136e0 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-initWithSwitcherController:delegate:` | 0x1c643de04 | 0x1c78efafc | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:` | 0x1c643e1e0 | 0x1c78eff04 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-gestureRecognizer:shouldRequireFailureOfGestureRecognizer:` | 0x1c643e2fc | 0x1c78f0024 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-configureIndirectBottomEdgePanGestureRecognizer` | 0x1c643e4a8 | 0x1c78f01d4 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-_configureTapToBringItemContainerForwardGesture` | 0x1c643e5f0 | 0x1c78f0318 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-_configureFloatingApplicationGestureRecognizers` | 0x1c643e7fc | 0x1c78f0518 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-_configureChamoisGestureRecognizersIfNeeded` | 0x1c643eea4 | 0x1c78f0c08 | PORTED already: hook in G1D.x:1297 |
| SBFluidSwitcherGestureManager | `-updateForChamoisWindowingUIEnabled:` | 0x1c643f408 | 0x1c78f0fe8 | PORTED already: hook in G1D.x:759 |
| SBFluidSwitcherGestureManager | `-_updateSwitcherBottomEdgeGesturePresence` | 0x1c643f760 | 0x1c78f1380 | PORTED already: 16.2 address cited in G2D.x |
| SBFluidSwitcherGestureManager | `-invalidate` | 0x1c643fa90 | 0x1c78f16c0 | PORTED already: hook in G1D.x:1302 |
| SBFluidSwitcherGestureManager | `-_handleTapToBringItemContainerForward:` | 0x1c6440998 | 0x1c78f2690 | PORTED already: hook in G1D.x:1575 |
| SBFluidSwitcherGestureManager | `-_shouldFloatingApplicationMoveGesture:receiveTouch:` | 0x1c644236c | 0x1c78f4184 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-_shouldFloatingApplicationPinGesture:receiveTouch:` | 0x1c64426c0 | 0x1c78f44f8 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-_shouldSplitViewApplicationUnpinGesture:receiveTouch:` | 0x1c6442888 | 0x1c78f46e8 | PORTED already: hook in G1D.x:1872 |
| SBFluidSwitcherGestureManager | `-_shouldLiveResizeItemContainerGestureWithTouch:receiveTouch:` | 0x1c6443064 | 0x1c78f51a4 | PORTED already: hook in G1D.x:1524 |
| SBFluidSwitcherGestureManager | `-_shouldLiveResizeItemContainerGestureWithPointer:receiveTouch:` | 0x1c6443414 | 0x1c78f56d0 | EQUIVALENT: checked in G1D.x section 4b (log only change) |
| SBFluidSwitcherGestureManager | `-_shouldLiveResizeGesture:receiveTouch:` | 0x1c6443518 | 0x1c78f5920 | PORTED already: hook in G1D.x:1493 |
| SBFluidSwitcherGestureManager | `-_shouldTapToBringItemContainerForward:receiveTouch:` | 0x1c6443604 | 0x1c78f5ac0 | PORTED already: hook in G1D.x:1538 |
| SBFluidSwitcherGestureManager | `-gestureRecognizerShouldBegin:` | 0x1c6443b1c | 0x1c78f61dc | PORTED already: hook in Group4Focus.x:752 |
| SBFluidSwitcherGestureManager | `-_shouldBeginTapToBringItemContainerForwardGesture:` | 0x1c644493c | 0x1c78f7064 | PORTED already: hook in G1D.x:1560 |
| SBFluidSwitcherGestureManager | `-_shouldAllowFloatingApplicationGesture:gestureType:failureReason:` | 0x1c64457e8 | 0x1c78f7ff0 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-_shouldBeginSplitViewApplicationUnpinGesture:` | 0x1c6446a7c | 0x1c78f92b8 | PORTED already: hook in G1D.x:1877 |
| SBFluidSwitcherGestureManager | `-_updateSystemApertureZStackPolicyAssistantWithLayoutState:` | 0x1c64477f4 | 0x1c78fa178 | TRIAGE PENDING |
| SBFluidSwitcherGestureManager | `-grabberTongueOrPullEnabled:forGestureRecognizer:` | 0x1c6447a44 | 0x1c78fa3c0 | PORTED already: hook in G1D.x:1344 |
| SBFluidSwitcherGestureManager | `-grabberTongueBeganPulling:withDistance:andVelocity:andGesture:` | 0x1c6447ae8 | 0x1c78fa480 | PORTED already: hook in G1D.x:1388 |
| SBFluidSwitcherGestureManager | `-grabberTongueUpdatedPulling:withDistance:andVelocity:andGesture:` | 0x1c6447b9c | 0x1c78fa55c | PORTED already: hook in G1D.x:1392 |
| SBFluidSwitcherGestureManager | `-grabberTongueEndedPulling:withDistance:andVelocity:andGesture:` | 0x1c6447c44 | 0x1c78fa630 | PORTED already: hook in G1D.x:1396 |
| SBFluidSwitcherGestureManager | `-grabberTongueCanceledPulling:withDistance:andVelocity:andGesture:` | 0x1c6447cf8 | 0x1c78fa70c | PORTED already: hook in G1D.x:1400 |
| SBFluidSwitcherGestureManager | `-customGestureRecognizerForGrabberTongue:` | 0x1c6447dac | 0x1c78fa7e8 | PORTED already: hook in G1D.x:1328 |
| SBFluidSwitcherGestureManager | `-indirectPanGestureRecognizerForGrabberTongue:` | 0x1c6447f64 | 0x1c78faa00 | PORTED already: hook in G1D.x:1332 |
| SBFluidSwitcherGestureManager | `-indirectPanSystemGestureTypeForGrabberTongue:` | 0x1c6448114 | 0x1c78fad3c | PORTED already: hook in G1D.x:1336 |
| SBFluidSwitcherGestureManager | `-shouldSuppressTongueViewForGrabberTongue:` | 0x1c644813c | 0x1c78fada0 | PORTED already: hook in G1D.x:1340 |
| SBFluidSwitcherGestureManager | `-grabberTongueWillPresent:` | 0x1c64481a4 | 0x1c78fae14 | PORTED already: hook in G1D.x:1404 |
| SBFluidSwitcherGestureManager | `-grabberTongueWillDismiss:` | 0x1c644841c | 0x1c78fb0a4 | PORTED already: hook in G1D.x:1408 |
| SBFluidSwitcherGestureManager | `-_grabberTongueForGestureRecognizer:` | 0x1c6448b38 | 0x1c78fb8c0 | PORTED already: hook in G1D.x:1348 |
| SBFluidSwitcherGestureManager | `-.cxx_destruct` | 0x1c6449748 | 0x1c78fc5dc | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_beginWithGesture:` | 0x1c5e5a588 | 0x1c72ccd44 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-layoutStateForApplicationTransitionContext:` | 0x1c5e62cec | 0x1c72d51cc | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-previousLayoutStateForApplicationTransitionContext:` | 0x1c5e62d58 | 0x1c72d5260 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_runSceneLayoutTransactionForTransitionRequest:updateScenes:` | 0x1c5e651b0 | 0x1c72d771c | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_failRunningLayoutStateTransition` | 0x1c5e6532c | 0x1c72d7bc4 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-transaction:performTransitionWithCompletion:` | 0x1c5e693b4 | 0x1c72dbcc0 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-transactionDidComplete:` | 0x1c5e6aa38 | 0x1c72dd5fc | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_didComplete` | 0x1c5e6e9d4 | 0x1c72e16e0 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-.cxx_destruct` | 0x1c5e6fdbc | 0x1c72e2ad8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFluidSwitcherGestureWorkspaceTransaction | `-initWithTransitionRequest:fluidSwitcherViewController:delegate:` | 0x1c60339d8 | 0x1c74ae6f4 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_currentGestureEventForGesture:` | 0x1c6033be0 | 0x1c74aea30 | PORTED already: hook in G1C.x:3079 |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_willInterruptWithReason:` | 0x1c6034270 | 0x1c74af0d0 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_startSceneUpdateTransaction:forSceneIdentifier:` | 0x1c6034fe4 | 0x1c74b0128 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherGestureWorkspaceTransaction | `-_acquireBackgroundingScenesDeactivationAssertionForTransitionRequest:` | 0x1c6035d64 | 0x1c74b1168 | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherItemContainer | `-_addPageView` | 0x1c5e5c848 | 0x1c72ced9c | TRIAGE PENDING |
| SBFluidSwitcherItemContainer | `-prepareForReuse` | 0x1c5e704c8 | 0x1c72e3220 | TRIAGE PENDING |
| SBFluidSwitcherItemContainer | `-initWithFrame:` | 0x1c615a38c | 0x1c75e0f64 | TRIAGE PENDING |
| SBFluidSwitcherItemContainer | `-initWithCoder:` | 0x1c615a440 | 0x1c75e101c | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherItemContainer | `-setContentViewBlocksTouches:` | 0x1c615a6dc | 0x1c75e15c8 | PORTED already: hook in G4B.x:1596 |
| SBFluidSwitcherItemContainer | `-setSelectable:` | 0x1c615d654 | 0x1c75e15f4 | PORTED already: hook in G4B.x:1599 |
| SBFluidSwitcherItemContainer | `-didUpdateFocusInContext:withAnimationCoordinator:` | 0x1c615bf10 | 0x1c75e2f2c | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherItemContainer | `-_returnKeyPressed:` | 0x1c615c03c | 0x1c75e305c | TRIAGE PENDING |
| SBFluidSwitcherItemContainer | `-_handlePageViewTap:` | 0x1c615c3a4 | 0x1c75e33d4 | TRIAGE PENDING |
| SBFluidSwitcherItemContainerFooterView | `-layoutSubviews` | 0x1c61010d8 | 0x1c75865c0 | TRIAGE PENDING |
| SBFluidSwitcherItemContainerFooterView | `-_handleTapGestureRecognizer:` | 0x1c6102688 | 0x1c7587b90 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherItemContainerFooterView | `-_makeSubtitleLabel` | 0x1c6102b0c | 0x1c7587ff4 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherItemContainerLayer | `-setTransform:` | 0x1c615e2ac | 0x1c75e5304 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherPanGestureRecognizer | `-touchesBegan:withEvent:` | 0x1c61b130c | 0x1c763f01c | EQUIVALENT: 16.2 also stores the initial touch location in touchesBegan (16.0 stores it on the first touchesMoved); the initial leaf app layout is G1D.x |
| SBFluidSwitcherPanGestureRecognizer | `-reset` | 0x1c61b1600 | 0x1c763f334 | PORTED already: G1D.x (setInitialTouchLeafAppLayout:) |
| SBFluidSwitcherPanGestureRecognizer | `-.cxx_destruct` | 0x1c61b1728 | 0x1c763f48c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFluidSwitcherRootSwitcherModifier | `-handleGestureEvent:` | 0x1c61e7a88 | 0x1c7676094 | TRIAGE PENDING |
| SBFluidSwitcherSpaceOverlayAccessoryView | `-prepareForReuse` | 0x1c6106378 | 0x1c758c730 | TRIAGE PENDING |
| SBFluidSwitcherSpaceOverlayAccessoryView | `-layoutSubviews` | 0x1c61065c0 | 0x1c758c9c4 | TRIAGE PENDING |
| SBFluidSwitcherSpaceOverlayAccessoryView | `-pointInside:withEvent:` | 0x1c61068b4 | 0x1c758cc98 | TRIAGE PENDING |
| SBFluidSwitcherSpaceOverlayAccessoryView | `-hitTest:withEvent:` | 0x1c6106984 | 0x1c758cd6c | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_removeVisibleItemContainerForAppLayout:` | 0x1c5e70268 | 0x1c72e2f98 | PORTED already: hook in G1B.x:1769 |
| SBFluidSwitcherViewController | `-dealloc` | 0x1c5fbcc50 | 0x1c7434be0 | PORTED already: 16.2 address cited in G4B.x |
| SBFluidSwitcherViewController | `-viewDidLoad` | 0x1c5fbcdec | 0x1c7434dbc | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-appLayoutContainsAnUnoccludedMaximizedDisplayItem:` | 0x1c5fbdb84 | 0x1c74360dc | PORTED already: 16.2 address cited in G2B.m |
| SBFluidSwitcherViewController | `-chamoisLayoutAttributes` | 0x1c5fbea9c | 0x1c7437110 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-prefersStripHidden` | 0x1c5fbf280 | 0x1c743794c | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-prefersDockHidden` | 0x1c5fbf2f8 | 0x1c74379ac | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-appLayoutsToEnsureExistForMainTransitionEvent:` | 0x1c5fbf36c | 0x1c74379cc | PORTED already: hook in G2.x:1966 |
| SBFluidSwitcherViewController | `-appLayoutByBringingItemToFront:inAppLayout:` | 0x1c5fc0130 | 0x1c7438794 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-handleTapToBringItemContainerForward:` | 0x1c5fc0b10 | 0x1c7439690 | PORTED already: hook in G1D.x:1590 |
| SBFluidSwitcherViewController | `-handleContinuousExposeHoverGesture:` | 0x1c5fc0c28 | 0x1c7439724 | PORTED already: hook in G2.x:2002 |
| SBFluidSwitcherViewController | `-_leafAppLayoutInLiveContentOverlaysWithLayoutRole:` | 0x1c5fc1424 | 0x1c7439f84 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherViewController | `-clickReceivedForHomeGrabberView:` | 0x1c5fc1864 | 0x1c743a460 | PORTED already: 16.2 address cited in G2B.m |
| SBFluidSwitcherViewController | `-canPerformKeyboardShortcutAction:forBundleIdentifier:` | 0x1c5fc1b10 | 0x1c743a70c | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-performKeyboardShortcutAction:` | 0x1c5fc2070 | 0x1c743ace4 | PORTED already: 16.2 address cited in G3C.x, P1VC.m |
| SBFluidSwitcherViewController | `-_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:` | 0x1c5fc29c8 | 0x1c743b200 | PORTED already: 16.2 address cited in G2B.m |
| SBFluidSwitcherViewController | `-invalidate` | 0x1c5fc335c | 0x1c743bc98 | PORTED already: hook in G1D.x:2289, G4B.x:2463 |
| SBFluidSwitcherViewController | `-_updateAutoHideForGrabberAffordancesInAppLayout:withResetDelay:unhideDelay:` | 0x1c5fc3b2c | 0x1c743c5f0 | PORTED already: 16.2 address cited in G2C.x |
| SBFluidSwitcherViewController | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c5fc493c | 0x1c743d59c | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBFluidSwitcherViewController | `-_blurItemContainer:blurParameters:withAnimationUpdateMode:` | 0x1c5fc6858 | 0x1c743f438 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_configureApplicationAndTransientOverlayDockBehaviorAssertionsForContext:` | 0x1c5fc8890 | 0x1c74414e4 | PORTED already: hook in G1D.x:2340 |
| SBFluidSwitcherViewController | `-_applyRootContentViewBlurRadiusWithCompletion:` | 0x1c5fc9e04 | 0x1c74429e8 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_ensureSubviewOrdering` | 0x1c5fce534 | 0x1c74473b0 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_addVisibleItemContainerForAppLayout:reusingItemContainerIfExists:` | 0x1c5fcf9f8 | 0x1c7448894 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_orderedViewsForLayoutElement:excludeSwitcherHostedShelves:` | 0x1c5fd6eb8 | 0x1c7450094 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-underlayAccessoryView:didSelectHeaderForRole:` | 0x1c5fd7e2c | 0x1c7451034 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-overlayAccessoryView:didSelectHeaderForRole:` | 0x1c5fd8118 | 0x1c7451324 | PORTED already: hook in G1B.x:827 |
| SBFluidSwitcherViewController | `-overlayAccessoryViewFrameForIconOverlayView:fullPresented:` | 0x1c5fd8350 | 0x1c7451420 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_applicationForDisplayItem:` | 0x1c5fd9638 | 0x1c74529cc | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-gestureHandlingModifierRequestsUpdate:` | 0x1c5fd9860 | 0x1c7452bdc | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherViewController | `-_scrollToAppLayout:animated:alignment:completion:` | 0x1c5fd9c44 | 0x1c7452ff0 | PORTED already: hook in G1C.x:5126 |
| SBFluidSwitcherViewController | `-_areContinuousExposeStripsUnoccluded` | 0x1c5fda820 | 0x1c7453b80 | PORTED already: hook in G2.x:1994 |
| SBFluidSwitcherViewController | `-_setupLiveContentOverlayForAppLayout:itemContainer:overlay:` | 0x1c5fdd720 | 0x1c7456a64 | PORTED already: 16.2 address cited in G2C.x |
| SBFluidSwitcherViewController | `-_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:` | 0x1c5fde0d0 | 0x1c7457450 | PORTED already: hook in G1C.x:918, G2.x:1974 |
| SBFluidSwitcherViewController | `-_updatePlusButtonPresence` | 0x1c5fde30c | 0x1c74575b8 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherViewController | `-_updateHomeScreenPointerInteractions` | 0x1c5fdf11c | 0x1c74583f4 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherViewController | `-_updateAsyncRenderingAndResizesHostedContext` | 0x1c5fdffb4 | 0x1c745929c | PORTED already: 16.2 address cited in P1Drag.m |
| SBFluidSwitcherViewController | `-_acquireKeyboardSuppressionAssertionForMode:` | 0x1c5fe088c | 0x1c7459e50 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherViewController | `-_updateFloatingDockWindowLevelAssertion` | 0x1c5fe0c60 | 0x1c745a234 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherViewController | `-_dispatchEventAndHandleAction:` | 0x1c5fe17e4 | 0x1c745ae4c | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_updateForegroundAppLayoutsList` | 0x1c5fe1c90 | 0x1c745b368 | TRIAGE PENDING |
| SBFluidSwitcherViewController | `-_performEventResponse:` | 0x1c5fe2024 | 0x1c745b6f0 | PORTED already: hook in G1B.x:798, G1B.x:1108 |
| SBFluidSwitcherViewController | `-_performModifierUpdateLayoutResponse:` | 0x1c5fe30b8 | 0x1c745c7dc | PORTED already: hook in G1D.x:897 |
| SBFluidSwitcherViewController | `-_performModifierIconViewVisibilityUpdateResponse:` | 0x1c5fe35dc | 0x1c745cd90 | PORTED already: 16.2 address cited in P1VC.m |
| SBFluidSwitcherViewController | `-_performRequestSystemApertureElementSuppressionResponse:` | 0x1c5fe4df0 | 0x1c745e4f4 | PORTED already: 16.2 address cited in G2B.m |
| SBFluidSwitcherViewController | `-_performRelinquishSystemApertureElementSuppressionResponse:` | 0x1c5fe4fec | 0x1c745e788 | PORTED already: 16.2 address cited in G2B.m |
| SBFluidSwitcherViewController | `-_performSystemApertureBounceResponse:` | 0x1c5fe5114 | 0x1c745e8e8 | PORTED already: 16.2 address cited in G2B.m |
| SBFluidSwitcherViewController | `-.cxx_destruct` | 0x1c5fe5ff0 | 0x1c74606c8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFullScreenAlwaysLiveLiveContentOverlay | `-initWithSceneHandle:referenceSize:containerOrientation:` | 0x1c6053fdc | 0x1c74d0d24 | NOT PORTED: container orientation argument (orientation re-architecture, CORE-LEFTOVERS 3b Tier B) |
| SBFullScreenContinuousExposeSwitcherModifier | `-initWithFullScreenAppLayout:` | 0x1c613d3cc | 0x1c75c2990 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-highlightedByTouchAppLayouts` | 0x1c6141d9c | 0x1c75c2cd4 | TRIAGE PENDING |
| SBFullScreenContinuousExposeSwitcherModifier | `-setHighlightedByTouchAppLayouts:` | 0x1c6141dac | 0x1c75c2ce4 | TRIAGE PENDING |
| SBFullScreenContinuousExposeSwitcherModifier | `-highlightedByHoverAppLayouts` | 0x1c6141dc0 | 0x1c75c2cf4 | TRIAGE PENDING |
| SBFullScreenContinuousExposeSwitcherModifier | `-setHighlightedByHoverAppLayouts:` | 0x1c6141dd0 | 0x1c75c2d04 | TRIAGE PENDING |
| SBFullScreenContinuousExposeSwitcherModifier | `-frameForIndex:` | 0x1c613d7c0 | 0x1c75c2da4 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-anchorPointForIndex:` | 0x1c613daf0 | 0x1c75c2e74 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-scaleForIndex:` | 0x1c613ddb8 | 0x1c75c2f1c | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-adjustedSpaceAccessoryViewFrame:forAppLayout:` | 0x1c613e0d0 | 0x1c75c2fcc | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:` | 0x1c613e228 | 0x1c75c3080 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-frameForLayoutRole:inAppLayout:withBounds:` | 0x1c613e288 | 0x1c75c310c | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-scaleForLayoutRole:inAppLayout:` | 0x1c613e410 | 0x1c75c3360 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-visibleAppLayouts` | 0x1c613e5c0 | 0x1c75c34c0 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-cornerRadiiForIndex:` | 0x1c613ebf4 | 0x1c75c3594 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-maskedCornersForIndex:` | 0x1c613ecf8 | 0x1c75c36a4 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-shadowOpacityForLayoutRole:atIndex:` | 0x1c613ed00 | 0x1c75c3750 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-wallpaperGradientAttributesForIndex:` | 0x1c613ed18 | 0x1c75c380c | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-titleAndIconOpacityForIndex:` | 0x1c613f1a8 | 0x1c75c38c0 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-touchBehaviorForLayoutRole:inAppLayout:` | 0x1c613f254 | 0x1c75c3974 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-activeCornersForTouchResizeForLayoutRole:inAppLayout:` | 0x1c613f324 | 0x1c75c3aac | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-shouldAllowContentViewTouchesForLayoutRole:inAppLayout:` | 0x1c613f514 | 0x1c75c3cf4 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-isLayoutRoleSelectable:inAppLayout:` | 0x1c613f5a0 | 0x1c75c3d84 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-_layoutRoleIsOccluded:inAppLayout:` | 0x1c613f660 | 0x1c75c3e48 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-homeScreenDimmingAlpha` | 0x1c613f73c | 0x1c75c3f74 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-shouldConfigureInAppDockHiddenAssertion` | 0x1c613f944 | 0x1c75c405c | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-dockProgress` | 0x1c613f9d8 | 0x1c75c4138 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-isLayoutRoleEligibleForContentDragSpringLoading:inAppLayout:` | 0x1c613f9e8 | 0x1c75c4150 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-perspectiveAngleForAppLayout:` | 0x1c613faac | 0x1c75c420c | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-topMostLayoutElements` | 0x1c613fb28 | 0x1c75c4284 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-isHomeAffordanceSupportedForAppLayout:` | 0x1c613fb84 | 0x1c75c43d4 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-shouldPinLayoutRolesToSpace:` | 0x1c613fc78 | 0x1c75c4498 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-shouldUseAnchorPointToPinLayoutRolesToSpace:` | 0x1c613fd28 | 0x1c75c4530 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-handleHoverEvent:` | 0x1c61402f8 | 0x1c75c462c | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c613fe64 | 0x1c75c4780 | PORTED already: 16.2 address cited in G1C.x, Y7Requests.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-handleTapOutsideToDismissEvent:` | 0x1c6140048 | 0x1c75c4bc0 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-_anyItemExceedsWidthThresholdToHideStrip` | 0x1c61414bc | 0x1c75c5244 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenContinuousExposeSwitcherModifier | `-.cxx_destruct` | 0x1c6141e04 | 0x1c75c55f4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFullScreenFluidSwitcherRootSwitcherModifier | `-transitionModifierForMainTransitionEvent:` | 0x1c61a1440 | 0x1c762c998 | PORTED already: hook in G1B.x:2381 |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c604e570 | 0x1c74ca574 | 7dd10ca: Y6Portal.x y6_portal (the portaled overlay update after _updateAlwaysLiveSceneContentOverlays, overlay type 4 removal); the layout state invalidateAppLayout calls of the same methods are 16.2 caching of SBMainDisplayLayoutState.appLayout which 16.0 computes on demand [sha 7dd10ca] |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:` | 0x1c604ef44 | 0x1c74cafd0 | EQUIVALENT: 16.2 adds the Medusa error message presentation (_presentTransientErrorMessageIfNeededForLayoutStateTransitionContext:, G3B.x split view / multiple windows banner, _presentMedusaBanner:) after the loop; the loop itself is unchanged |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` | 0x1c604f1a8 | 0x1c74cb284 | 7dd10ca: Y6Portal.x y6_portal (the portaled overlay update after _updateAlwaysLiveSceneContentOverlays, overlay type 4 removal); the layout state invalidateAppLayout calls of the same methods are 16.2 caching of SBMainDisplayLayoutState.appLayout which 16.0 computes on demand [sha 7dd10ca] |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-noteKeyboardFocusDidChangeToSceneID:` | 0x1c604f9c8 | 0x1c74cbac4 | EQUIVALENT: _sceneManager ivar became a method (the window scene's scene manager), _sbWindowScene derives from the stored switcher controller (16.2 initWithSwitcherController:) instead of a stored scene: same objects |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-appLayoutWillBecomeVisible:` | 0x1c60502c0 | 0x1c74cc1ac | 7dd10ca: Y6Portal.x y6_portal (the portaled overlay update after _updateAlwaysLiveSceneContentOverlays, overlay type 4 removal); the layout state invalidateAppLayout calls of the same methods are 16.2 caching of SBMainDisplayLayoutState.appLayout which 16.0 computes on demand [sha 7dd10ca] |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-appLayoutDidBecomeHidden:` | 0x1c605041c | 0x1c74cc328 | 7dd10ca: Y6Portal.x y6_portal (the portaled overlay update after _updateAlwaysLiveSceneContentOverlays, overlay type 4 removal); the layout state invalidateAppLayout calls of the same methods are 16.2 caching of SBMainDisplayLayoutState.appLayout which 16.0 computes on demand [sha 7dd10ca] |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-wantsEdgeProtectForHomeGestureForAppLayout:` | 0x1c605063c | 0x1c74cc550 | EQUIVALENT: _sceneManager ivar became a method (the window scene's scene manager), _sbWindowScene derives from the stored switcher controller (16.2 initWithSwitcherController:) instead of a stored scene: same objects |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-wantsHomeAffordanceAutoHideForAppLayout:` | 0x1c605071c | 0x1c74cc648 | EQUIVALENT: _sceneManager ivar became a method (the window scene's scene manager), _sbWindowScene derives from the stored switcher controller (16.2 initWithSwitcherController:) instead of a stored scene: same objects |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-fullScreenSwitcherSceneLiveContentOverlay:tappedStatusBar:tapActionType:` | 0x1c6050908 | 0x1c74ccd9c | EQUIVALENT: _sceneManager ivar became a method (the window scene's scene manager), _sbWindowScene derives from the stored switcher controller (16.2 initWithSwitcherController:) instead of a stored scene: same objects |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-_newLiveContentOverlayForApplicationContext:layoutRole:` | 0x1c60510f8 | 0x1c74cd59c | EQUIVALENT: _sceneManager ivar became a method (the window scene's scene manager), _sbWindowScene derives from the stored switcher controller (16.2 initWithSwitcherController:) instead of a stored scene: same objects |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-_configureLiveContentOverlayView:forTransitionContext:layoutRole:` | 0x1c6051300 | 0x1c74cd7a8 | NOT PORTED: content / container orientation split of the overlay configuration (configureWithWorkspaceEntity:...contentOrientation:containerOrientation:): part of the 16.2 orientation re-architecture, CORE-LEFTOVERS 3b Tier B (documented there) |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-_removeOverlayForAppLayout:animated:` | 0x1c6051704 | 0x1c74cdbd8 | 7dd10ca: Y6Portal.x y6_portal (the portaled overlay update after _updateAlwaysLiveSceneContentOverlays, overlay type 4 removal); the layout state invalidateAppLayout calls of the same methods are 16.2 caching of SBMainDisplayLayoutState.appLayout which 16.0 computes on demand [sha 7dd10ca] |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-_updateAlwaysLiveSceneContentOverlays` | 0x1c6051854 | 0x1c74cdd38 | 7dd10ca: Y6Portal.x y6_alwayslive (always-live overlay sized with the window scene's screen bounds instead of the main screen) [sha 7dd10ca] |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-_sbWindowScene` | 0x1c6051bf8 | 0x1c74ce6cc | EQUIVALENT: _sceneManager ivar became a method (the window scene's scene manager), _sbWindowScene derives from the stored switcher controller (16.2 initWithSwitcherController:) instead of a stored scene: same objects |
| SBFullScreenSwitcherLiveContentOverlayCoordinator | `-.cxx_destruct` | 0x1c6051c24 | 0x1c74ce804 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFullScreenSwitcherSceneLiveContentOverlay | `-init` | 0x1c6051ca8 | 0x1c74ce87c | NOT PORTED: content / container orientation split of the live overlay (contentOrientation rename, container orientation argument) and the touch behavior update through the scene layer manager observer (_updateTouchBehaviorForScene:): CORE-LEFTOVERS 3b Tier B and the G3B 1.6 adapter keep the 16.0 behaviour |
| SBFullScreenSwitcherSceneLiveContentOverlay | `-_updateOrientationWrapper` | 0x1c6052af8 | 0x1c74cf72c | NOT PORTED: content / container orientation split of the live overlay (contentOrientation rename, container orientation argument) and the touch behavior update through the scene layer manager observer (_updateTouchBehaviorForScene:): CORE-LEFTOVERS 3b Tier B and the G3B 1.6 adapter keep the 16.0 behaviour |
| SBFullScreenSwitcherSceneLiveContentOverlay | `-setContentReferenceSize:interfaceOrientation:` | 0x1c6052de4 | 0x1c74cfa18 | NOT PORTED: content / container orientation split of the live overlay (contentOrientation rename, container orientation argument) and the touch behavior update through the scene layer manager observer (_updateTouchBehaviorForScene:): CORE-LEFTOVERS 3b Tier B and the G3B 1.6 adapter keep the 16.0 behaviour |
| SBFullScreenSwitcherSceneLiveContentOverlay | `-sceneHandle:didCreateScene:` | 0x1c60534a8 | 0x1c74d00f4 | NOT PORTED: content / container orientation split of the live overlay (contentOrientation rename, container orientation argument) and the touch behavior update through the scene layer manager observer (_updateTouchBehaviorForScene:): CORE-LEFTOVERS 3b Tier B and the G3B 1.6 adapter keep the 16.0 behaviour |
| SBFullScreenSwitcherSceneLiveContentOverlay | `-setTouchBehavior:` | 0x1c6053638 | 0x1c74d02cc | NOT PORTED: content / container orientation split of the live overlay (contentOrientation rename, container orientation argument) and the touch behavior update through the scene layer manager observer (_updateTouchBehaviorForScene:): CORE-LEFTOVERS 3b Tier B and the G3B 1.6 adapter keep the 16.0 behaviour |
| SBFullScreenToHomeIconZoomSwitcherModifier | `-initWithTransitionID:appLayout:direction:` | 0x1c61278d0 | 0x1c75b1dd0 | TRIAGE PENDING |
| SBFullScreenToHomeIconZoomSwitcherModifier | `-shouldAsyncRenderUntilDelay:` | 0x1c6127b18 | 0x1c75b2034 | PORTED already: hook in G1B.x:2212 |
| SBFullScreenToHomeIconZoomSwitcherModifier | `-wantsDockBehaviorAssertion` | 0x1c6128f18 | 0x1c75b3988 | PORTED already: 16.2 address cited in G1B.x |
| SBFullScreenToHomePIPSwitcherModifier | `-transitionWillBegin` | 0x1c633b640 | 0x1c77def90 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenToHomePIPSwitcherModifier | `-frameForIndex:` | 0x1c633b7e0 | 0x1c77df1ac | TRIAGE PENDING |
| SBFullScreenToHomePIPSwitcherModifier | `-scaleForIndex:` | 0x1c633b890 | 0x1c77df3a4 | TRIAGE PENDING |
| SBFullScreenToHomePIPSwitcherModifier | `-clipsToBoundsAtIndex:` | 0x1c633b9a4 | 0x1c77df5f8 | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenToHomePIPSwitcherModifier | `-visibleAppLayouts` | 0x1c633b9ac | 0x1c77df5fc | PORTED already: 16.2 address cited in G1C.x |
| SBFullScreenToHomePIPSwitcherModifier | `-rotationAngleForIndex:` | 0x1c633b9d4 | 0x1c77df684 | TRIAGE PENDING |
| SBFullScreenToHomePIPSwitcherModifier | `-cornerRadiiForIndex:` | 0x1c633bbe4 | 0x1c77dfc44 | TRIAGE PENDING |
| SBFullScreenToHomePIPSwitcherModifier | `-opacityForLayoutRole:inAppLayout:atIndex:` | 0x1c633bc7c | 0x1c77dfcdc | TRIAGE PENDING |
| SBFullScreenToHomeSlideOverSwitcherModifier | `-scaleForIndex:` | 0x1c638de94 | 0x1c7836d34 | PORTED already: hook in G1B.x:2235 |
| SBFullScreenToHomeSlideOverSwitcherModifier | `-visibleAppLayouts` | 0x1c638de9c | 0x1c783713c | PORTED already: hook in G1B.x:2240 |
| SBFullScreenToHomeSystemApertureSwitcherModifier | `-transitionWillBegin` | 0x1c6075a7c | 0x1c74f8a08 | IRRELEVANT: zoom out of the Dynamic Island (iPhone only) |
| SBFullScreenToHomeSystemApertureSwitcherModifier | `-_blurItemContainerParameters` | 0x1c60774fc | 0x1c74fa48c | IRRELEVANT: zoom out of the Dynamic Island (iPhone only) |
| SBGestureRootSwitcherModifier | `-handleEvent:` | 0x1c60565c0 | 0x1c74d3724 | TRIAGE PENDING |
| SBGridSwipeUpGestureSwitcherModifier | `-initWithGestureID:` | 0x1c64260d0 | 0x1c78d5e88 | PORTED already: 16.2 address cited in G1C.x |
| SBGridSwipeUpGestureSwitcherModifier | `-handleGestureEvent:` | 0x1c64265e0 | 0x1c78d63b0 | PORTED already: 16.2 address cited in G1C.x |
| SBGridSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c640b234 | 0x1c78b8620 | TRIAGE PENDING |
| SBHistorianSwitcherModifier | `-_querySnapshotFromModifier:` | 0x1c64b9b98 | 0x1c7973fb8 | TRIAGE PENDING |
| SBHomeGestureRootSwitcherModifier | `-gestureChildModifierForGestureEvent:activeTransitionModifier:` | 0x1c643c05c | 0x1c78edb44 | PORTED already: 16.2 address cited in G1C.x |
| SBHomeGestureRootSwitcherModifier | `-transitionChildModifierForMainTransitionEvent:activeGestureModifier:` | 0x1c643c20c | 0x1c78edd24 | PORTED already: 16.2 address cited in G1C.x |
| SBHomeGestureSwitcherModifier | `-didMoveToParentModifier:` | 0x1c6038bac | 0x1c74b4138 | PORTED already: 16.2 address cited in G1C.x |
| SBHomeGestureSwitcherModifier | `-appLayoutsToCacheSnapshots` | 0x1c603c58c | 0x1c74b7b80 | PORTED already: 16.2 address cited in G1C.x |
| SBHomeGestureSwitcherModifier | `-appLayoutsToCacheFullsizeSnapshots` | 0x1c603c6bc | 0x1c74b7c54 | PORTED already: 16.2 address cited in G1C.x |
| SBHomeGestureToHomeSwitcherModifier | `-frameForIndex:` | 0x1c5f44db8 | 0x1c73b941c | TRIAGE PENDING |
| SBHomeGestureToHomeSwitcherModifier | `-scaleForIndex:` | 0x1c5f44df8 | 0x1c73b947c | TRIAGE PENDING |
| SBHomeGestureToSwitcherSwitcherModifier | `-transitionWillBegin` | 0x1c6498dd8 | 0x1c794f6fc | PORTED already: hook in G1D.x:2386 |
| SBHomeGestureToSwitcherSwitcherModifier | `-_appLayoutToScrollToDuringTransition` | 0x1c6499a54 | 0x1c795038c | PORTED already: 16.2 address cited in P1SW.m |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-handleTransitionEvent:` | 0x1c61f81fc | 0x1c76868e0 | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c61f82bc | 0x1c7686a58 | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-handleHighlightEvent:` | 0x1c61f8528 | 0x1c7687024 | PORTED already: 16.2 address cited in G1B.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-frameForIndex:` | 0x1c61f8e90 | 0x1c7687820 | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-frameForLayoutRole:inAppLayout:withBounds:` | 0x1c61f91ac | 0x1c7687b9c | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-scaleForLayoutRole:inAppLayout:` | 0x1c61f9438 | 0x1c7687eb4 | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-titleAndIconOpacityForIndex:` | 0x1c61f9720 | 0x1c76881a8 | TRIAGE PENDING |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-homeScreenDimmingAlpha` | 0x1c61f99d4 | 0x1c76885fc | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-_inlineAppExposeAppLayouts` | 0x1c61f9d84 | 0x1c7688908 | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-_isLayoutRoleOccluded:inAppLayout:` | 0x1c61fa0cc | 0x1c7688c70 | PORTED already: 16.2 address cited in G1C.x |
| SBInlineAppExposeContinuousExposeSwitcherModifier | `-_scaleForActiveAppLayoutLeafAppLayouts` | 0x1c61fa428 | 0x1c7688ea8 | PORTED already: 16.2 address cited in G1C.x |
| SBInteractiveScreenshotCommitWorkspaceTransaction | `-_updateState` | 0x1c624ee80 | 0x1c76e4418 | TRIAGE PENDING |
| SBItemResizeGestureSwitcherModifier | `-handleGestureEvent:` | 0x1c622bcd8 | 0x1c76be31c | PORTED already: hook in G3B.x:1656 |
| SBItemResizeGestureSwitcherModifier | `-_responseForGestureUpdateAtGestureEnd:` | 0x1c622bf98 | 0x1c76be610 | PORTED already: hook in G3B.x:1663 |
| SBItemResizeGestureSwitcherModifier | `-_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:` | 0x1c622c5dc | 0x1c76bed98 | PORTED already: hook in G1C.x:5545, G3B.x:1670 |
| SBItemResizeGestureSwitcherModifier | `-_anyItemExceedsWidthThresholdToHideStrip` | 0x1c622d588 | 0x1c76bfd40 | TRIAGE PENDING |
| SBMainSwitcherControllerCoordinator | `-_init` | 0x1c6235168 | 0x1c76c7c20 | EQUIVALENT: ivar bookkeeping only: 16.2 adds _draggingAppLayouts (ported as an associated object, G1D.x kDragging) and moves the Stage Manager first-use education observer from the view controller to the coordinator (16.0 SBFluidSwitcherViewController already owns _chamoisWindowingUIEverEnabledObserver); the hidden UIWindow that forced windowSceneDidConnect: is gone because the scene manager connects scenes itself |
| SBMainSwitcherControllerCoordinator | `-dealloc` | 0x1c6235544 | 0x1c76c8124 | PORTED already: hook in G3B.x:1260 |
| SBMainSwitcherControllerCoordinator | `-windowSceneDidConnect:` | 0x1c6235828 | 0x1c76c8410 | PORTED already: hook in G1D.x:431 |
| SBMainSwitcherControllerCoordinator | `-windowSceneDidDisconnect:` | 0x1c62359ec | 0x1c76c85e0 | PORTED already: hook in G4B.x:1782 |
| SBMainSwitcherControllerCoordinator | `-_loadContentViewControllerIfNecessaryForAllWindowScenes` | 0x1c6235bf8 | 0x1c76c8c50 | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-_loadContentViewControllerIfNecessaryForWindowScene:` | 0x1c6235cbc | 0x1c76c8d14 | EQUIVALENT: 16.2 passes the switcher controller instead of the window scene to the live content overlay coordinator initialiser; the 16.0 initialiser takes the window scene and reaches the same controller through it |
| SBMainSwitcherControllerCoordinator | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c62362ec | 0x1c76c9354 | EQUIVALENT: 16.2 reads the request through the application transition context and also stores previousLayoutState on the per-scene layout state provider; the only readers of that field are 16.2 code (16.0 readers use the transition context, ported in P1Drag.m P1_PrevLayoutStateFor) and the ivar offsets moved (+0x58 -> +0x78); the main-display singleton lookups printed in the diff are per-scene in both builds |
| SBMainSwitcherControllerCoordinator | `-_focusNewlyAddedApplicationIfNeededTransitioningFromLayoutState:toLayoutState:windowScene:` | 0x1c623797c | 0x1c76cac38 | TRIAGE PENDING |
| SBMainSwitcherControllerCoordinator | `-layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` | 0x1c6237d6c | 0x1c76cb178 | PORTED already: hook in G1B.x:1562, G1D.x:704 |
| SBMainSwitcherControllerCoordinator | `-eventSource:userTouchedApplication:` | 0x1c6238a08 | 0x1c76cbf28 | EQUIVALENT: 16.2 reads the active display's controller explicitly; the 16.0 coordinator forwarders (layoutState, _currentLayoutState) forward to _activeDisplaySwitcherController, the same object |
| SBMainSwitcherControllerCoordinator | `-isAnySwitcherVisible` | 0x1c6239f20 | 0x1c76cd428 | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-hasVisibleElements` | 0x1c623a23c | 0x1c76cd744 | EQUIVALENT: 16.2 reads the active display's controller explicitly; the 16.0 coordinator forwarders (layoutState, _currentLayoutState) forward to _activeDisplaySwitcherController, the same object |
| SBMainSwitcherControllerCoordinator | `-performKeyboardShortcutAction:forBundleIdentifier:windowScene:` | 0x1c623a458 | 0x1c76cd978 | PORTED already: the action numbering and the handler are the view controller's performKeyboardShortcutAction: (M3, P1VC.m); the coordinator only range-checks and forwards to the scene's controller (16.0 0x16 upper bound, 16.2 0x14) |
| SBMainSwitcherControllerCoordinator | `-_handleFocusedIconSwitcherShortcutAction:bundleIdentifier:windowScene:` | 0x1c623a620 | 0x1c76cdb38 | 7dd10ca: Y3StatusBar.x y3_scenectl (the controller of the passed window scene answers the layout state / floating layout queries instead of the active display's) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-failMultitaskingGesturesForReason:` | 0x1c623adb8 | 0x1c76ce304 | PORTED already: hook in G1D.x:579 |
| SBMainSwitcherControllerCoordinator | `-_activateNeighboringAppLayoutRequiringActiveAppLayout:appLayoutEnvironment:inForwardDirection:windowScene:eventLabel:` | 0x1c623af6c | 0x1c76ce4f4 | 7dd10ca: Y3StatusBar.x y3_scenectl (the controller of the passed window scene answers the layout state / floating layout queries instead of the active display's) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-isInAppStatusBarHiddenForWindowScene:` | 0x1c623b5fc | 0x1c76ceb90 | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-statusBarAvoidanceFrameForLayoutRole:windowScene:` | 0x1c623b66c | 0x1c76cebfc | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-statusBarAvoidanceFrameForLayoutRole:layoutState:windowScene:` | 0x1c623b6fc | 0x1c76ceca8 | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-statusBarEdgeInsetsForWindowScene:` | 0x1c623b864 | 0x1c76cee4c | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-leadingStatusBarStyleRequestForWindowScene:` | 0x1c623bc38 | 0x1c76cf240 | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-trailingStatusBarStyleRequestForWindowScene:` | 0x1c623bce4 | 0x1c76cf2cc | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-statusBarOverlayDataForWindowScene:` | 0x1c623bd90 | 0x1c76cf358 | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-statusBarActionsByPartIdentifierForWindowScene:` | 0x1c623be70 | 0x1c76cf444 | 7dd10ca: Y3StatusBar.x y3_scenectl (per window scene state instead of the active display) + y3_avoidorient (Stage Manager uses the layout state's orientation for the avoidance frame) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-removeAppLayoutTransientOverlayViewController:windowScene:` | 0x1c623ce58 | 0x1c76d0440 | EQUIVALENT: 16.2 only renames the helper it calls (removeAcquiredTransientOverlayViewController: -> _removeAcquiredTransientOverlayViewController:), both are implemented in 16.0 with the same body |
| SBMainSwitcherControllerCoordinator | `-_configureRequest:forSwitcherTransitionRequest:withEventLabel:` | 0x1c623e164 | 0x1c76d174c | PORTED already: hook in G1D.x:446 |
| SBMainSwitcherControllerCoordinator | `-_entityForDisplayItem:sceneHandleProvider:displayIdentity:` | 0x1c623f6c4 | 0x1c76d2eac | EQUIVALENT: _appForDisplayItem: became [SBApplicationController applicationForDisplayItem:] (same lookup); rest is block / register renumbering |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:deviceApplicationSceneHandleForDisplayItem:` | 0x1c623fa88 | 0x1c76d3288 | PORTED already: hook in G1D.x:600 |
| SBMainSwitcherControllerCoordinator | `-settings:changedValueForKey:` | 0x1c623fc30 | 0x1c76d32fc | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-transitionEventForLayoutState:identifier:phase:animated:` | 0x1c624052c | 0x1c76d3bf8 | PORTED already: PiP morph layout role: G1B.x / G1C.x (morphingPIPLayoutRole on the transition event) and G1D.x (_shouldMorphTo/FromPIPForTransitionContext:outForLayoutRole:) |
| SBMainSwitcherControllerCoordinator | `-transitionEventForContext:identifier:phase:animated:` | 0x1c624073c | 0x1c76d3e1c | PORTED already: hook in G1B.x:1159, G1D.x:686 |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:shouldMorphToPIPForTransitionContext:` | 0x1c6241694 | 0x1c76d4e94 | PORTED already: PiP morph layout role: G1B.x / G1C.x (morphingPIPLayoutRole on the transition event) and G1D.x (_shouldMorphTo/FromPIPForTransitionContext:outForLayoutRole:) |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:shouldMorphFromPIPForTransitionContext:` | 0x1c6241874 | 0x1c76d50d4 | PORTED already: PiP morph layout role: G1B.x / G1C.x (morphingPIPLayoutRole on the transition event) and G1D.x (_shouldMorphTo/FromPIPForTransitionContext:outForLayoutRole:) |
| SBMainSwitcherControllerCoordinator | `-_shouldZoomFromSystemApertureForTransitionContext:` | 0x1c62418bc | 0x1c76d5174 | IRRELEVANT: Dynamic Island zoom (iPhone only) |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:supportsKillingOfAppLayout:` | 0x1c6241dcc | 0x1c76d568c | EQUIVALENT: 16.2 asks the controller that owns the item / content view controller; the 16.0 coordinator's scene handle lookup already resolves the owner display's handle (G1D.x scene handle owner lookup, switch g1d_scenehandle) and _medusaKeyboardSceneHandle only changed from the helper to the same active scene's sceneManager |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:displayItemSupportsCenterRole:` | 0x1c6241f34 | 0x1c76d581c | EQUIVALENT: 16.2 asks the controller that owns the item / content view controller; the 16.0 coordinator's scene handle lookup already resolves the owner display's handle (G1D.x scene handle owner lookup, switch g1d_scenehandle) and _medusaKeyboardSceneHandle only changed from the helper to the same active scene's sceneManager |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:supportsTitleItemsForAppLayout:` | 0x1c6241f80 | 0x1c76d589c | EQUIVALENT: 16.2 asks the controller that owns the item / content view controller; the 16.0 coordinator's scene handle lookup already resolves the owner display's handle (G1D.x scene handle owner lookup, switch g1d_scenehandle) and _medusaKeyboardSceneHandle only changed from the helper to the same active scene's sceneManager |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:performTransitionWithRequest:gestureInitiated:` | 0x1c6242114 | 0x1c76d5a58 | PORTED already: the manager of the asking view controller receives handleTransitionRequestForGestureUpdate: / Complete:; P1Drag.m P1_HandleUpdate / P1_HandleComplete replace the 16.0 manager methods |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:requestNewWindowForBundleIdentifier:` | 0x1c624239c | 0x1c76d5ce0 | PORTED already: hook in G1D.x:546 |
| SBMainSwitcherControllerCoordinator | `-_setContainerStatusBarHidden:animationDuration:usingAssertion:reason:windowScene:` | 0x1c6242754 | 0x1c76d6164 | 7dd10ca: Y3StatusBar.x y3_containersb (level 6 settings assertion with UIStatusBarStyleAnimationParameters, _shouldTakeStatusBarAssertionForSwitcherController:) [sha b1fc8da] |
| SBMainSwitcherControllerCoordinator | `-switcherContentController:reopenHiddenAppLayoutsWithBundleIdentifier:` | 0x1c6242ffc | 0x1c76d6a18 | EQUIVALENT: 16.2 only adds a weak self capture to the completion block |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:didBeginGesture:` | 0x1c6243d44 | 0x1c76d79e4 | PORTED already: hook in G1D.x:610 |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:didUpdateGesture:` | 0x1c6243dc4 | 0x1c76d7ba8 | PORTED already: hook in G1D.x:629 |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:didEndGesture:` | 0x1c6243e44 | 0x1c76d7d18 | PORTED already: hook in G1D.x:642 |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:didBeginDraggingWindowWithSceneIdentifier:` | 0x1c6243ec4 | 0x1c76d7edc | PORTED already: 16.2 additionally tells every switcher controller (the controller side of the delegate method); G1D.x adds the three controller methods (G1D_SC_Noop3) and the coordinator dragging set |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:didPlatterizeWindowDragWithSceneIdentifier:` | 0x1c6243fa8 | 0x1c76d8038 | PORTED already: 16.2 additionally tells every switcher controller (the controller side of the delegate method); G1D.x adds the three controller methods (G1D_SC_Noop3) and the coordinator dragging set |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:willEndDraggingWindowWithSceneIdentifier:` | 0x1c6243ff8 | 0x1c76d811c | PORTED already: 16.2 additionally tells every switcher controller (the controller side of the delegate method); G1D.x adds the three controller methods (G1D_SC_Noop3) and the coordinator dragging set |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:clickReceivedForHomeGrabberView:` | 0x1c62440cc | 0x1c76d8268 | EQUIVALENT: 16.2 enumerates all controllers and each controller forwards to its content view controller only when the manager is its own (isEqual: gestureManager, 0x1c7607290 / 0x1c7607330); 16.0 _switcherControllerForGestureManager: finds that one controller directly |
| SBMainSwitcherControllerCoordinator | `-fluidSwitcherGestureManager:tapReceivedForGrabberTongueAtEdge:` | 0x1c624414c | 0x1c76d8330 | EQUIVALENT: 16.2 enumerates all controllers and each controller forwards to its content view controller only when the manager is its own (isEqual: gestureManager, 0x1c7607290 / 0x1c7607330); 16.0 _switcherControllerForGestureManager: finds that one controller directly |
| SBMainSwitcherControllerCoordinator | `-_shouldPrioritizeSortOrderForAppLayout:` | 0x1c6245678 | 0x1c76d98a0 | EQUIVALENT: 16.2 asks the controller that owns the item / content view controller; the 16.0 coordinator's scene handle lookup already resolves the owner display's handle (G1D.x scene handle owner lookup, switch g1d_scenehandle) and _medusaKeyboardSceneHandle only changed from the helper to the same active scene's sceneManager |
| SBMainSwitcherControllerCoordinator | `-_medusaKeyboardSceneHandle` | 0x1c6245a14 | 0x1c76d9c50 | EQUIVALENT: 16.2 asks the controller that owns the item / content view controller; the 16.0 coordinator's scene handle lookup already resolves the owner display's handle (G1D.x scene handle owner lookup, switch g1d_scenehandle) and _medusaKeyboardSceneHandle only changed from the helper to the same active scene's sceneManager |
| SBMainSwitcherControllerCoordinator | `-_updateBestAppSuggestion` | 0x1c6245e54 | 0x1c76da394 | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-_buildAppLayoutCache` | 0x1c6245ff0 | 0x1c76da530 | PORTED already: hook in G1D.x:187 |
| SBMainSwitcherControllerCoordinator | `-_notifySwitcherControllersAppLayoutsDidChange` | 0x1c6246b80 | 0x1c76dba40 | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-_rebuildAppListCache` | 0x1c6246bd0 | 0x1c76dba90 | PORTED already: hook in G1D.x:175 |
| SBMainSwitcherControllerCoordinator | `-_cancelPIPForDisplayItem:` | 0x1c62492a8 | 0x1c76de3ec | EQUIVALENT: 16.2 asks the controller that owns the item / content view controller; the 16.0 coordinator's scene handle lookup already resolves the owner display's handle (G1D.x scene handle owner lookup, switch g1d_scenehandle) and _medusaKeyboardSceneHandle only changed from the helper to the same active scene's sceneManager |
| SBMainSwitcherControllerCoordinator | `-_persistenceIdentifiersForBundleIdentifier:onlyIncludeLaunchableIdentifiers:` | 0x1c624963c | 0x1c76de7ac | EQUIVALENT: _appForDisplayItem: became [SBApplicationController applicationForDisplayItem:] (same lookup); rest is block / register renumbering |
| SBMainSwitcherControllerCoordinator | `-_performSceneDestructionForModelRemovalResults:` | 0x1c624a104 | 0x1c76df2a0 | EQUIVALENT: _appForDisplayItem: became [SBApplicationController applicationForDisplayItem:] (same lookup); rest is block / register renumbering |
| SBMainSwitcherControllerCoordinator | `-_switcherModelRemovalResultsForRequest:forReason:` | 0x1c624b4b0 | 0x1c76e0660 | PORTED already: hook in G1D.x:505 |
| SBMainSwitcherControllerCoordinator | `-keyboardFocusController:externalSceneDidAcquireFocus:` | 0x1c624c078 | 0x1c76e123c | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-_evaluateAsynchronousRenderingEnablement` | 0x1c624ce08 | 0x1c76e1fcc | OPEN: 16.2 removed the method (async rendering of the container moved to the live content overlay coordinator, REVIEW-CORE M6/M7); M7 is in P1Drag.m, M6 is the remaining half, owner: core agent |
| SBMainSwitcherControllerCoordinator | `-appLayoutsForSwitcherController:` | 0x1c624d488 | 0x1c76e2354 | PORTED already: hook in G1D.x:141 |
| SBMainSwitcherControllerCoordinator | `-_enumerateSwitcherControllersWithBlock:` | 0x1c624df90 | 0x1c76e3714 | EQUIVALENT: rename only: _enumerateSwitcherControllersWithBlock: became enumerateSwitcherControllersWithBlock: (same loop over _switcherControllersByWindowScene, the 16.0 selector is still implemented) |
| SBMainSwitcherControllerCoordinator | `-.cxx_destruct` | 0x1c624e1f0 | 0x1c76e3740 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBMedusaAppsTestRecipe | `-_toggle` | 0x1c611d940 | 0x1c75a7ce8 | IRRELEVANT: internal test recipes |
| SBMedusaBannerViewController | `-_bannerView` | 0x1c637cd80 | 0x1c782418c | PORTED already: hook in G3B.x:146 |
| SBMedusaDecoratedDeviceApplicationSceneViewController | `-viewWillLayoutSubviews` | 0x1c5e3c200 | 0x1c72ae4fc | TRIAGE PENDING |
| SBMedusaDecoratedDeviceApplicationSceneViewController | `-initWithDeviceApplicationSceneHandle:layoutRole:workspace:setupManager:` | 0x1c6329ec4 | 0x1c77caf30 | PORTED already: hook in G3.x:724 |
| SBMedusaDecoratedDeviceApplicationSceneViewController | `-layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:` | 0x1c632b5e8 | 0x1c77cc710 | TRIAGE PENDING |
| SBMedusaDecoratedDeviceApplicationSceneViewController | `-_topAffordanceViewController:handleActionType:transitionSource:` | 0x1c632ba50 | 0x1c77ccb6c | PORTED already: hook in G3C.x:283 |
| SBMedusaDecoratedDeviceApplicationSceneViewController | `-_updateTopAffordanceHighlight` | 0x1c632fb04 | 0x1c77d0de8 | PORTED already: hook in G3.x:706 |
| SBMedusaHostedKeyboardWindow | `-initWithWindowScene:keyboardScene:` | 0x1c60ff268 | 0x1c75844cc | PORTED already: hook in G3B.x:1070 |
| SBMedusaHostedKeyboardWindow | `-dealloc` | 0x1c60ff55c | 0x1c7584824 | TRIAGE PENDING |
| SBMedusaHostedKeyboardWindow | `-setHidden:` | 0x1c60ff950 | 0x1c7584c48 | PORTED already: hook in G3B.x:1078 |
| SBMinimumViableSwitcherTableViewController | `-isWindowVisible` | 0x1c606c49c | 0x1c74eeebc | TRIAGE PENDING |
| SBMinimumViableSwitcherTableViewController | `-clickReceivedForHomeGrabberView:` | 0x1c606ca1c | 0x1c74ef4d4 | TRIAGE PENDING |
| SBMixedGridHomeGestureRootSwitcherModifier | `-handleGestureEvent:` | 0x1c5fffb88 | 0x1c747a708 | TRIAGE PENDING |
| SBModalUIFluidDismissGestureWorkspaceTransaction | `-_begin` | 0x1c6000e70 | 0x1c747ba18 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBMoveFloatingApplicationGestureWorkspaceTransaction | `-_begin` | 0x1c64b53fc | 0x1c796e88c | TRIAGE PENDING |
| SBMoveFloatingApplicationGestureWorkspaceTransaction | `-_startSuppressingKeyboardForFloatingApplication` | 0x1c64b5ec0 | 0x1c796f360 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBOverrideAppLayoutsSwitcherModifier | `-didMoveToParentModifier:` | 0x1c5f9a624 | 0x1c7412900 | TRIAGE PENDING |
| SBPIPContainerViewController | `-getRotationContentSettings:forWindow:` | 0x1c622254c | 0x1c76b2f5c | TRIAGE PENDING |
| SBPIPController | `-_setAdapter:` | 0x1c6471b8c | 0x1c79273b4 | EQUIVALENT: checked in G1D.x section 5c: selector sequences identical, only logging / resource usage timeout / System Aperture / off screen hyperregion differences |
| SBPIPController | `-_windowSceneDidDisconnect:` | 0x1c64721cc | 0x1c7927a24 | PORTED already: 16.2 address cited in G4B.x |
| SBPIPController | `-_moveContext:toWindowScene:` | 0x1c64722d0 | 0x1c7927bbc | EQUIVALENT: checked in G1D.x section 5c: selector sequences identical, only logging / resource usage timeout / System Aperture / off screen hyperregion differences |
| SBPIPController | `-containerViewController:userDidUpdateStashState:` | 0x1c6473548 | 0x1c7928e40 | EQUIVALENT: checked in G1D.x section 5c: selector sequences identical, only logging / resource usage timeout / System Aperture / off screen hyperregion differences |
| SBPIPController | `-_updateZStackIfNeededForDisappearingContainerViewController:` | 0x1c6474654 | 0x1c7929f8c | EQUIVALENT: checked in G1D.x section 5c: selector sequences identical, only logging / resource usage timeout / System Aperture / off screen hyperregion differences |
| SBPIPController | `-restoreContentViewController:appSceneEntity:morphAnimatorConfigurationBlock:completion:` | 0x1c6474958 | 0x1c792a2a4 | PORTED already: hook in G1D.x:2178 |
| SBPIPController | `-_acquireStashAssertionForWindowScene:withReason:identifier:customAllowedEnvironmentModes:` | 0x1c6475030 | 0x1c792a9dc | TRIAGE PENDING |
| SBPIPController | `-updateZStackParticipantPreferencesIfNeeded:windowScene:` | 0x1c64765bc | 0x1c792bf6c | EQUIVALENT: checked in G1D.x section 5c: selector sequences identical, only logging / resource usage timeout / System Aperture / off screen hyperregion differences |
| SBPIPController | `-_createNewWindowForContainerViewController:onWindowScene:` | 0x1c6477214 | 0x1c792cc0c | TRIAGE PENDING |
| SBPIPController | `-_updatePictureInPictureOverlayInsetsOnWindowScene:withCurrentLayoutState:shouldUpdate:` | 0x1c6478320 | 0x1c792dd08 | PORTED already: hook in G1D.x:2205 |
| SBPIPController | `-homeScreenInitialPIPFrameForWindowScene:withContentViewSize:position:padding:fromOrientation:toOrientation:shouldUpdate:gestureInitiated:` | 0x1c6478df8 | 0x1c792e814 | TRIAGE PENDING |
| SBPIPController | `-keyboardFocusController:externalSceneDidAcquireFocus:` | 0x1c647944c | 0x1c792efa4 | PORTED already: hook in G1D.x:2184 |
| SBPIPEnvironmentDependentOverrideAssertion | `-_layoutCoordinator` | 0x1c6331938 | 0x1c77d23d8 | TRIAGE PENDING |
| SBPIPEnvironmentDependentOverrideAssertion | `-descriptionBuilderWithMultilinePrefix:` | 0x1c6331af4 | 0x1c77d25ac | EXCLUDED: description / debug text only |
| SBPIPEnvironmentDependentOverrideAssertion | `-.cxx_destruct` | 0x1c6331ce0 | 0x1c77d27dc | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBPIPInteractionController | `-initWithInteractionTargetView:preferredContentSize:interactionSettings:dataSource:delegate:` | 0x1c619400c | 0x1c761d900 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-dealloc` | 0x1c619450c | 0x1c761ddfc | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-description` | 0x1c619494c | 0x1c761e230 | EXCLUDED: description / debug text only |
| SBPIPInteractionController | `-_setupForInitialFrame` | 0x1c619505c | 0x1c761e940 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_setupGestureRecognizers` | 0x1c61950f0 | 0x1c761e9d8 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_removeGestureRecognizers` | 0x1c6195484 | 0x1c761ed70 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_canonicalPositionForPoint:` | 0x1c6195a70 | 0x1c761f350 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-setPlatformMetrics:contentSize:animationBehavior:` | 0x1c6196040 | 0x1c761f930 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-setPreferredContentSize:` | 0x1c6196968 | 0x1c7620258 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_updatePreferredContentSize` | 0x1c6196dc8 | 0x1c76206b8 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-layoutInteractedTraits:withReason:source:` | 0x1c6196e70 | 0x1c7620760 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_noteStashProgress:withReason:` | 0x1c61979d8 | 0x1c76212b8 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_stashTabCompensationTransformForStashProgress:reason:` | 0x1c6197e90 | 0x1c762176c | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_adjustContentViewAnchorPointForGestureRecognizer:` | 0x1c6197fdc | 0x1c76218b4 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-_resetAnchorPoint` | 0x1c6198204 | 0x1c7621ac0 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-handleExternalPanGesture:` | 0x1c61986a8 | 0x1c7621f60 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-handlePinchGesture:` | 0x1c6198b04 | 0x1c76223b8 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c6199f0c | 0x1c76237c0 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-positionHyperregion` | 0x1c619ac64 | 0x1c7624504 | EQUIVALENT: 16.2 asks the data source for the gesture manager of the PiP (systemGestureManagerForInteractionControllerResizing:) instead of mainDisplayManager; the video PiP data source (SBPIPPegasusContainerAdapter 0x1c78e1d80 / 16.0 0x1c6431c18) answers nil / NO in both builds and only Quick Note's PiP (SBSystemNotesInteractionManager, embedded display) uses system gestures for resizing; the other rows are ivar offset shifts |
| SBPIPInteractionController | `-.cxx_destruct` | 0x1c619b8b8 | 0x1c7625168 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBPIPMorphAnimatorController | `-willRemoveTargeMatchMoveAnimationAtFrame:withinSourceFrame:` | 0x1c6413054 | 0x1c78c09c0 | PORTED already: hook in G1D.x:2122 |
| SBPIPMorphAnimatorController | `-scenePersistenceIdentifier` | 0x1c6412bf4 | 0x1c78c0b04 | TRIAGE PENDING |
| SBPIPMorphAnimatorController | `-.cxx_destruct` | 0x1c64131d0 | 0x1c78c0bf0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBPIPMorphAnimatorDataSource | `-sourceContentFrameForAnimator:` | 0x1c60b7c28 | 0x1c782fdc0 | PORTED already: hook in G1D.x:2065 |
| SBPIPMorphAnimatorDataSource | `-targetFinalFrameForAnimator:` | 0x1c60b7fec | 0x1c78304b0 | PORTED already: 16.2 address cited in G1D.x |
| SBPIPMorphAnimatorDataSource | `-sourceBlackCurtainCornerRadiusForAnimator:` | 0x1c60b827c | 0x1c78307f8 | PORTED already: hook in G1D.x:2106 |
| SBPIPMorphAnimatorDataSource | `-.cxx_destruct` | 0x1c60b8340 | 0x1c7830934 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBPIPPegasusAdapter | `-_postEnsuredInSwitcher_pictureInPictureController:didRequestStopForPictureInPictureViewController:sourceSceneSessionIdentifier:animated:` | 0x1c60b5d10 | 0x1c753a46c | PORTED already: hook in PIPStop.x:413 |
| SBPIPPegasusContainerAdapter | `-performStopAnimationWithFinalInterfaceOrientation:finalLayerFrame:completionHandler:` | 0x1c64312bc | 0x1c78e11bc | PORTED already: hook in PIPStop.x:422 |
| SBPIPPegasusContainerAdapter | `-shouldSuppressAssociatedElementsInSystemAperture` | 0x1c6431a28 | 0x1c78e1b2c | TRIAGE PENDING |
| SBPIPPegasusContainerAdapter | `-_createOrInvalidateStashTabVisibilityPolicyProvider` | 0x1c643226c | 0x1c78e23d4 | PORTED already: hook in G3B.x:663 |
| SBPIPRestoreToFullScreenSwitcherModifier | `-transitionWillBegin` | 0x1c61bf3d8 | 0x1c764d5d0 | PORTED already: 16.2 address cited in G1C.x |
| SBPIPRestoreToFullScreenSwitcherModifier | `-frameForIndex:` | 0x1c61bf4b0 | 0x1c764d6fc | PORTED already: 16.2 address cited in G1C.x |
| SBPIPRestoreToFullScreenSwitcherModifier | `-clippingFrameForIndex:withBounds:` | 0x1c61bf588 | 0x1c764d7d4 | PORTED already: 16.2 address cited in G1C.x |
| SBPIPRestoreToFullScreenSwitcherModifier | `-clipsToBoundsAtIndex:` | 0x1c61bf624 | 0x1c764daf0 | PORTED already: 16.2 address cited in G1C.x |
| SBPIPRestoreToFullScreenSwitcherModifier | `-scaleForIndex:` | 0x1c61bf62c | 0x1c764daf4 | EQUIVALENT: private helper rename (_isFromAppLayout: -> _isFromAppLayoutIndex:, _isToAppLayout: -> _isToAppLayoutIndex:), two pure conditions swapped |
| SBPIPRestoreToFullScreenSwitcherModifier | `-animationAttributesForLayoutElement:` | 0x1c61bf750 | 0x1c764dc18 | PORTED already: 16.2 address cited in G1C.x |
| SBPIPRestoreToFullScreenSwitcherModifier | `-cornerRadiiForIndex:` | 0x1c61bf874 | 0x1c764e0b0 | EQUIVALENT: private helper rename (_isFromAppLayout: -> _isFromAppLayoutIndex:, _isToAppLayout: -> _isToAppLayoutIndex:), two pure conditions swapped |
| SBPIPRestoreToFullScreenSwitcherModifier | `-opacityForLayoutRole:inAppLayout:atIndex:` | 0x1c61bf904 | 0x1c764e140 | PORTED already: 16.2 address cited in G1C.x |
| SBPIPRestoreToFullScreenSwitcherModifier | `-_isToAppLayout:` | 0x1c61bf9ec | 0x1c764e2a8 | PORTED already: 16.2 address cited in G1C.x |
| SBPIPSceneContentAdapter | `-pipController:didAddContainerViewController:` | 0x1c634af50 | 0x1c77ef8d0 | TRIAGE PENDING |
| SBPIPSceneContentContainerAdapter | `-containerViewController:didUpdateStashProgress:` | 0x1c6392180 | 0x1c783b5c0 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBPIPSceneContentSceneUpdateWorkspaceTransaction | `-_didComplete` | 0x1c6147208 | 0x1c75caaec | TRIAGE PENDING |
| SBPIPStashTabSuppressionPolicyProvider | `-setStashTabCanBeHidden:` | 0x1c635cb2c | 0x1c7802b6c | PORTED already: hook in G3B.x:694 |
| SBPIPStashTabSuppressionPolicyProvider | `-.cxx_destruct` | 0x1c635d390 | 0x1c780340c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBPeekSplitViewRoutingSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c6065940 | 0x1c74e7108 | TRIAGE PENDING |
| SBPeekSplitViewRoutingSwitcherModifier | `-responseForProposedChildResponse:childModifier:event:` | 0x1c6065a50 | 0x1c74e7210 | TRIAGE PENDING |
| SBPeekSplitViewRoutingSwitcherModifier | `-routingModifier:event:forModifier:` | 0x1c6066294 | 0x1c74e7a88 | TRIAGE PENDING |
| SBReduceMotionHomeGestureSwitcherModifier | `-scaleForIndex:` | 0x1c63bec44 | 0x1c78692d4 | PORTED already: 16.2 address cited in G1C.x |
| SBReduceMotionHomeGestureSwitcherModifier | `-cornerRadiiForIndex:` | 0x1c63bed9c | 0x1c7869470 | PORTED already: 16.2 address cited in G1C.x |
| SBReduceMotionHomeGestureSwitcherModifier | `-homeScreenBackdropBlurType` | 0x1c63bedc4 | 0x1c78694d8 | PORTED already: 16.2 address cited in G1C.x |
| SBRevealContinuousExposeStripOverflowGestureModifier | `-frameForIndex:` | 0x1c5f1ce60 | 0x1c7391508 | TRIAGE PENDING |
| SBRevealContinuousExposeStripOverflowGestureModifier | `-_finalScaleForFullScreenAppLayout` | 0x1c5f1ef5c | 0x1c73934d0 | TRIAGE PENDING |
| SBRevealContinuousExposeStripOverflowRootSwitcherModifier | `-transitionChildModifierForMainTransitionEvent:activeGestureModifier:` | 0x1c640e6e0 | 0x1c78bbf18 | PORTED already: hook in G1C.x:1489 |
| SBRevealContinuousExposeStripsGestureModifier | `-handleGestureEvent:` | 0x1c63706d4 | 0x1c781783c | PORTED already: 16.2 address cited in G1C.x |
| SBRoutingSwitcherModifier | `-stackDescriptionWithPrefix:` | 0x1c609d2f0 | 0x1c752045c | EXCLUDED: description / debug text only |
| SBRoutingSwitcherModifier | `-appLayouts` | 0x1c609d9b8 | 0x1c7520b44 | PORTED already: hook in G1B.x:432 |
| SBRoutingSwitcherModifier | `-containerViewBounds` | 0x1c609dbc4 | 0x1c7520d64 | PORTED already: hook in G1B.x:442 |
| SBRoutingSwitcherModifier | `-switcherViewBounds` | 0x1c609dc40 | 0x1c7520df8 | PORTED already: hook in G1B.x:448 |
| SBShelfCarouselSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c6434200 | 0x1c78e4460 | TRIAGE PENDING |
| SBShelfExpansionSwitcherModifier | `-scaleForIndex:` | 0x1c605bdec | 0x1c74db034 | TRIAGE PENDING |
| SBShelfLiveContentOverlayCoordinator | `-_addOverlaysIfNeededForTransitionContext:` | 0x1c64cf838 | 0x1c798ac94 | TRIAGE PENDING |
| SBSlideOverPeekSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c6159544 | 0x1c75dda00 | TRIAGE PENDING |
| SBSplitDisplayItemSwitcherModifier | `-frameForLayoutRole:inAppLayout:withBounds:` | 0x1c60b9374 | 0x1c753da84 | TRIAGE PENDING |
| SBSpotlightCrossblurToFullscreenSwitcherModifier | `-frameForIndex:` | 0x1c5ed32d8 | 0x1c734746c | 7dd10ca: Y8Layout.x y8_spotlight (Stage Manager: the opened window's own frame, other windows of the stage stay visible) |
| SBSpotlightCrossblurToFullscreenSwitcherModifier | `-visibleAppLayouts` | 0x1c5ed33f8 | 0x1c7347aac | 7dd10ca: Y8Layout.x y8_spotlight (Stage Manager: the opened window's own frame, other windows of the stage stay visible) |
| SBSwitcherChamoisLayoutAttributes | `-isEqual:` | 0x1c6414a48 | 0x1c78c3384 | PORTED already: hook in G2.x:1376 |
| SBSwitcherChamoisLayoutAttributes | `-copyWithZone:` | 0x1c6414d68 | 0x1c78c39e0 | PORTED already: hook in G2.x:1368 |
| SBSwitcherChamoisSettings | `-layoutAttributesForContainerBounds:nativeContainerReferencePixelBounds:interfaceOrientation:floatingDockHeight:statusBarHeight:requiresFullScreen:prefersStripHidden:prefersDockHidden:isEmbeddedDisplay:` | 0x1c6413524 | 0x1c78c0f50 | PORTED already: 16.2 address cited in G2.x |
| SBSwitcherChamoisSettings | `-_shouldPreferStripHiddenForWindowScene:interfaceOrientation:` | 0x1c6413fb0 | 0x1c78c22ec | TRIAGE PENDING |
| SBSwitcherChamoisSettings | `-_shouldPreferDockHiddenForWindowScene:` | 0x1c6414024 | 0x1c78c2358 | TRIAGE PENDING |
| SBSwitcherChamoisSettings | `-setDefaultValues` | 0x1c641407c | 0x1c78c26bc | TRIAGE PENDING |
| SBSwitcherChamoisSettings | `+settingsControllerModule` | 0x1c6414264 | 0x1c78c28dc | TRIAGE PENDING |
| SBSwitcherChamoisSettings | `-.cxx_destruct` | 0x1c64149a4 | 0x1c78c32b4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSwitcherController | `-initWithWindowScene:switcherCoordinator:` | 0x1c61781f8 | 0x1c75ffe28 | PORTED already: hook in G3.x:803 |
| SBSwitcherController | `-_orientationStateDescription` | 0x1c6178588 | 0x1c76001a8 | EXCLUDED: description / debug text only |
| SBSwitcherController | `-dealloc` | 0x1c6178718 | 0x1c7600360 | TRIAGE PENDING |
| SBSwitcherController | `-isChamoisWindowingUIEnabled` | 0x1c6178a54 | 0x1c760069c | TRIAGE PENDING |
| SBSwitcherController | `-setChamoisWindowingUIEnabled:` | 0x1c6178ac0 | 0x1c76006fc | PORTED already: hook in G1D.x:749, G3.x:785 |
| SBSwitcherController | `-switcherOrientation:elementsOrientations:forTransitionRequest:previousLayoutState:layoutState:` | 0x1c6178cec | 0x1c7600950 | TRIAGE PENDING |
| SBSwitcherController | `-_setupSwitcherTraitsParticipantAndPolicySpecifiers` | 0x1c6179fc8 | 0x1c7601458 | PORTED already: hook in G3B.x:1718 |
| SBSwitcherController | `-_invalidateLayoutElementsTraitsParticipants` | 0x1c617a190 | 0x1c76015ac | TRIAGE PENDING |
| SBSwitcherController | `-didChangeSettingsForParticipant:context:` | 0x1c617a610 | 0x1c7601ce0 | TRIAGE PENDING |
| SBSwitcherController | `-_enqueueOrientationTransitionWithActuationContext:suggestedAnimator:completionTask:validator:label:` | 0x1c617aa5c | 0x1c760212c | TRIAGE PENDING |
| SBSwitcherController | `-_updateAppTransitionContext:withOrientationActuationContext:` | 0x1c617af88 | 0x1c76026a4 | PORTED already: 16.2 address cited in P1SW.m |
| SBSwitcherController | `-layoutElementSizingPoliciesForLayoutState:` | 0x1c617b708 | 0x1c7602f8c | TRIAGE PENDING |
| SBSwitcherController | `-coordinateSpaceForLayoutElement:layoutState:` | 0x1c617c1c4 | 0x1c7603a88 | PORTED already: 16.2 address cited in P1SW.m |
| SBSwitcherController | `-frameForItemWithRole:inMainAppLayout:interfaceOrientation:` | 0x1c617c2cc | 0x1c7603bb0 | TRIAGE PENDING |
| SBSwitcherController | `-frameForFloatingAppLayoutInInterfaceOrientation:floatingConfiguration:` | 0x1c617c36c | 0x1c7603c98 | TRIAGE PENDING |
| SBSwitcherController | `-frameForCenterItemWithConfiguration:interfaceOrientation:` | 0x1c617c3f0 | 0x1c7603d64 | TRIAGE PENDING |
| SBSwitcherController | `-referenceFrameForForInterfaceOrientation:layoutRole:appLayout:isInsetForHomeAffordance:` | 0x1c617c474 | 0x1c7603e30 | TRIAGE PENDING |
| SBSwitcherController | `-referenceFrameForForInterfaceOrientation:floatingConfiguration:` | 0x1c617c64c | 0x1c760409c | TRIAGE PENDING |
| SBSwitcherController | `-referenceFrameForForInterfaceOrientation:centerConfiguration:` | 0x1c617c6f4 | 0x1c76041b4 | TRIAGE PENDING |
| SBSwitcherController | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c617c79c | 0x1c76042cc | TRIAGE PENDING |
| SBSwitcherController | `-_currentLayoutState` | 0x1c617dab8 | 0x1c7605754 | PORTED already: 16.2 address cited in P1Drag.m |
| SBSwitcherController | `-_presentMedusaEducationBanner` | 0x1c617ddac | 0x1c7605aa0 | TRIAGE PENDING |
| SBSwitcherController | `-_invalidateMedusaEducationBannerTimer` | 0x1c617e0dc | 0x1c7605fd4 | TRIAGE PENDING |
| SBSwitcherController | `-_ancillaryTransitionRequestForTransitionRequest:` | 0x1c617e6e0 | 0x1c76066fc | PORTED already: 16.2 address cited in P1Drag.m |
| SBSwitcherController | `-sceneEntityFrameForWorkspaceEntity:inLayoutState:` | 0x1c617ef24 | 0x1c76073e4 | PORTED already: 16.2 address cited in P1SW.m |
| SBSwitcherLayoutCalculationsCache | `-frameForKey:validityToken:fallback:` | 0x1c630132c | 0x1c779ec58 | TRIAGE PENDING |
| SBSwitcherLayoutCalculationsCache | `-scaleForKey:validityToken:fallback:` | 0x1c630146c | 0x1c779ed98 | TRIAGE PENDING |
| SBSwitcherLayoutCalculationsCache | `-.cxx_destruct` | 0x1c63016ac | 0x1c779efe4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSwitcherLayoutCalculationsCacheValidityToken | `-isEqual:` | 0x1c63018d4 | 0x1c779f210 | PORTED already: 16.2 address cited in G2.x |
| SBSwitcherModifier | `-_handleEvent:` | 0x1c63e8a98 | 0x1c7895274 | PORTED already: hook in G1B.x:96, G1C.x:5083 |
| SBSwitcherShelfViewController | `-initWithSwitcherController:shelf:delegate:` | 0x1c64caf2c | 0x1c798631c | TRIAGE PENDING |
| SBSwitcherShelfViewController | `-dealloc` | 0x1c64cb1b0 | 0x1c79865a8 | TRIAGE PENDING |
| SBSwitcherShelfViewController | `-viewWillAppear:` | 0x1c64cb658 | 0x1c7986a60 | PORTED already: 16.2 address cited in Y2Gestures.x |
| SBSwitcherShelfViewController | `-viewWillDisappear:` | 0x1c64cb730 | 0x1c7986b58 | PORTED already: 16.2 address cited in Y2Gestures.x |
| SBSwitcherSnapshotImageView | `-layoutSubviews` | 0x1c5e33de8 | 0x1c72a6254 | TRIAGE PENDING |
| SBSwitcherSnapshotImageView | `-setImage:` | 0x1c5e50750 | 0x1c72c2b48 | TRIAGE PENDING |
| SBSwitcherSystemApertureSettings | `-setDefaultValues` | 0x1c6147278 | 0x1c75cab6c | IRRELEVANT: Dynamic Island debug settings |
| SBSwitcherSystemApertureSettings | `+settingsControllerModule` | 0x1c61479f4 | 0x1c75cb300 | IRRELEVANT: Dynamic Island debug settings |
| SBSwitcherTransitionRequest | `-init` | 0x1c5f95aa0 | 0x1c740d4c8 | EQUIVALENT: ivar offset of _floatingSwitcherVisible (stur -> str) only |
| SBSwitcherTransitionRequest | `-descriptionBuilderWithMultilinePrefix:` | 0x1c5f95d24 | 0x1c740d8a8 | EXCLUDED: description / debug text only |
| SBSwitcherTransitionRequest | `-mutableCopyWithZone:` | 0x1c5f96074 | 0x1c740dc2c | 7dd10ca: Y7Requests.x y7_inspolicy (copies entityInsertionPolicy and the G1D activatingDisplayItem associated object) |
| SBSwitcherTransitionRequest | `-.cxx_destruct` | 0x1c5f962d4 | 0x1c740dee4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBTapAppLayoutSwitcherModifierEvent | `-copyWithZone:` | 0x1c6014910 | 0x1c748f1e0 | TRIAGE PENDING |
| SBTapAppLayoutSwitcherModifierEvent | `-descriptionBuilderWithMultilinePrefix:` | 0x1c6014990 | 0x1c748f280 | EXCLUDED: description / debug text only |
| SBTopAffordanceViewController | `-initWithDeviceApplicationSceneHandle:` | 0x1c64570ec | 0x1c790bbc4 | 7dd10ca: Y2Gestures.x y2_tuiscene (manager of the scene of the scene handle; presence controller registers with it). The 16.2 removal of the expanded-dots animation settings in init is the F3 top affordance row (TO PORT) [sha a557a56] |
| SBTopAffordanceViewController | `-viewDidLoad` | 0x1c6457330 | 0x1c790bdb0 | TO PORT: 16.2 drops the expanded-dots mode (_setTopAffordanceMode:animated: / _updateDotsForTopAffordanceMode:animated:): isExpanded = dotsView.isHeld, dismissAnimated: no longer collapses, setHidden:YES dismisses, viewDidLoad sets the dots alpha from the presence controller; visual / pointer behaviour of the window title dots (needs device A/B) |
| SBTopAffordanceViewController | `-isExpanded` | 0x1c64575e8 | 0x1c790c078 | TO PORT: 16.2 drops the expanded-dots mode (_setTopAffordanceMode:animated: / _updateDotsForTopAffordanceMode:animated:): isExpanded = dotsView.isHeld, dismissAnimated: no longer collapses, setHidden:YES dismisses, viewDidLoad sets the dots alpha from the presence controller; visual / pointer behaviour of the window title dots (needs device A/B) |
| SBTopAffordanceViewController | `-dismissAnimated:` | 0x1c6457810 | 0x1c790c0b0 | TO PORT: 16.2 drops the expanded-dots mode (_setTopAffordanceMode:animated: / _updateDotsForTopAffordanceMode:animated:): isExpanded = dotsView.isHeld, dismissAnimated: no longer collapses, setHidden:YES dismisses, viewDidLoad sets the dots alpha from the presence controller; visual / pointer behaviour of the window title dots (needs device A/B) |
| SBTopAffordanceViewController | `-updateContextMenuWithLayoutRole:spaceConfiguration:floatingConfiguration:interfaceOrientation:isZoomed:` | 0x1c6459bd0 | 0x1c790cac4 | PORTED already: hook in G3.x:622 |
| SBTopAffordanceViewController | `-_setSystemPointerInteractionEnabled:` | 0x1c645b028 | 0x1c790df38 | TO PORT: 16.2 drops the expanded-dots mode (_setTopAffordanceMode:animated: / _updateDotsForTopAffordanceMode:animated:): isExpanded = dotsView.isHeld, dismissAnimated: no longer collapses, setHidden:YES dismisses, viewDidLoad sets the dots alpha from the presence controller; visual / pointer behaviour of the window title dots (needs device A/B) |
| SBTopAffordanceViewController | `-setHidden:forReason:animated:` | 0x1c645b1e4 | 0x1c790e0e4 | TO PORT: 16.2 drops the expanded-dots mode (_setTopAffordanceMode:animated: / _updateDotsForTopAffordanceMode:animated:): isExpanded = dotsView.isHeld, dismissAnimated: no longer collapses, setHidden:YES dismisses, viewDidLoad sets the dots alpha from the presence controller; visual / pointer behaviour of the window title dots (needs device A/B) |
| SBTopAffordanceViewController | `-topAffordanceDotsViewWillPresentMenu:` | 0x1c645b1f4 | 0x1c790e164 | 7dd10ca: Y2Gestures.x y2_tuiscene (manager of the scene of the scene handle; presence controller registers with it). The 16.2 removal of the expanded-dots animation settings in init is the F3 top affordance row (TO PORT) [sha a557a56] |
| SBTopAffordanceViewController | `-topAffordanceDotsViewWillDismissMenu:` | 0x1c645b294 | 0x1c790e20c | 7dd10ca: Y2Gestures.x y2_tuiscene (manager of the scene of the scene handle; presence controller registers with it). The 16.2 removal of the expanded-dots animation settings in init is the F3 top affordance row (TO PORT) [sha a557a56] |
| SBTopAffordanceViewController | `-setAdditionalTopInset:` | 0x1c64578a0 | 0x1c790e410 | TO PORT: 16.2 drops the expanded-dots mode (_setTopAffordanceMode:animated: / _updateDotsForTopAffordanceMode:animated:): isExpanded = dotsView.isHeld, dismissAnimated: no longer collapses, setHidden:YES dismisses, viewDidLoad sets the dots alpha from the presence controller; visual / pointer behaviour of the window title dots (needs device A/B) |
| SBTopAffordanceViewController | `-.cxx_destruct` | 0x1c645b500 | 0x1c790e420 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBTraitsEmbeddedDisplayPipelineManager | `-setupDefaultPipelineForArbiter:` | 0x1c612a7f0 | 0x1c75b52bc | PORTED already: hook in G3.x:943 |
| SBTraitsEmbeddedDisplayPipelineManager | `-_orientationInputsForDeviceOrientation:` | 0x1c612b678 | 0x1c75b6198 | TRIAGE PENDING |
| SBTraitsSceneParticipantDelegate | `-initWithScene:` | 0x1c62d7d64 | 0x1c7772f48 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-initWithSceneHandle:` | 0x1c62d7e58 | 0x1c7772fc4 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-invalidate` | 0x1c62d7f48 | 0x1c7773038 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-_supportedOrientations` | 0x1c62d85c0 | 0x1c77736b8 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-_sanitizedMask:forApplication:` | 0x1c62d89b0 | 0x1c7773a88 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-actuateOrientationSettingsWithContext:` | 0x1c62d8bc4 | 0x1c7773c68 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-updateOrientationSceneSettingsForParticipant:` | 0x1c62d8f24 | 0x1c7773fc4 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-needsActuationForUpdateReasons:` | 0x1c62d933c | 0x1c77743e4 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-sceneContentStateDidChange:` | 0x1c62d980c | 0x1c77748a0 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` | 0x1c62d9a54 | 0x1c7774a98 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-_evaluateOrientationTransitionContext:` | 0x1c62da450 | 0x1c7774d78 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-_resetToInitialState` | 0x1c62da3b4 | 0x1c77750bc | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-didChangeSettingsForParticipant:context:` | 0x1c62da8f4 | 0x1c77752c8 | NOT PORTED: 16.2 removed the alter ego (pre modern rotation) path and moved orientation action handling to SBOrientationRequestActionAssistant: part of the traits participant / content-container orientation re-architecture documented as Tier B in CORE-LEFTOVERS 3b (needs the SBSwitcherTraitsAssistant world, 16.0 delegate keeps its own consistent alter ego; ivars shift by 8) |
| SBTraitsSceneParticipantDelegate | `-.cxx_destruct` | 0x1c62dad14 | 0x1c77757a0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBTransitionSwitcherModifierEvent | `-copyWithZone:` | 0x1c5fb9638 | 0x1c7431d04 | PORTED already: hook in G1B.x:1145 |
| SBTransitionSwitcherModifierEvent | `-descriptionBuilderWithMultilinePrefix:` | 0x1c5fb99f8 | 0x1c74320f4 | EXCLUDED: description / debug text only |
| SBUISwitcherAnimationController | `-_updatePPTsForAnimationEnd` | 0x1c5e6ee44 | 0x1c72e1b60 | TRIAGE PENDING |
| SBViewMorphAnimator | `-_updateParameters` | 0x1c61f2ca8 | 0x1c76812dc | TRIAGE PENDING |
| SBViewMorphAnimator | `-_source:finalCenterWithFinalScale:contentFrame:targetFinalFrame:` | 0x1c61f3afc | 0x1c7681f9c | PORTED already: 16.2 address cited in G1D.x |
| SBViewMorphAnimator | `-_checkAnimationsDependencies:` | 0x1c61f4fbc | 0x1c7683580 | PORTED already: hook in G1D.x:2148 |
| SBWindowCommitSwitcherModifier | `-transitionWillBegin` | 0x1c626aadc | 0x1c770222c | TRIAGE PENDING |
| SBWindowDeclineSwitcherModifier | `-transitionWillBegin` | 0x1c606b4d8 | 0x1c74ed85c | TRIAGE PENDING |
| SBWindowDeleteSwitcherModifier | `-transitionWillBegin` | 0x1c6435954 | 0x1c78e6c8c | PORTED already: hook in G1B.x:1689 |
| SBWindowDeleteSwitcherModifier | `-scaleForIndex:` | 0x1c6436218 | 0x1c78e7bf8 | PORTED already: hook in G1B.x:1722 |
| SBWindowDragGestureWorkspaceTransaction | `-_beginWithGesture:` | 0x1c5eca434 | 0x1c733da30 | PORTED already: hook in G1D.x:1889 |
| SBWindowDragTransitionSwitcherModifier | `-shouldUseAnchorPointToPinLayoutRolesToSpace:` | 0x1c64b4e74 | 0x1c796e3b4 | TRIAGE PENDING |
| _SBDisplayItemFixedAspectGrid | `-_buildFixedGridWithScreenScale:` | 0x1c6469854 | 0x1c791ed14 | PORTED already: hook in G3B.x:1710 |
| _SBDisplayItemFlexibleGrid | `-_buildGridWithScreenScale:` | 0x1c6468f0c | 0x1c791e5d4 | PORTED already: hook in G2.x:1720 |
| _SBDisplayItemFlexibleGrid | `-_gridWidthsForSafeWidth:minimumWidth:` | 0x1c64691b4 | 0x1c791e630 | TRIAGE PENDING |
| _SBFullScreenAppFloorSwitcherModifier | `-handleTapAppLayoutEvent:` | 0x1c6148ef4 | 0x1c75cc850 | TRIAGE PENDING |
| _SBFullScreenAppFloorSwitcherModifier | `-isItemResizingAllowedForLayoutRole:inAppLayout:` | 0x1c6149450 | 0x1c75cce18 | TRIAGE PENDING |
| _SBPIPEndStashTabSuppressionGestureManager | `-_addSystemRecognizers` | 0x1c635d6c0 | 0x1c7340510 | PORTED already: G3B.x BPPIPEndStashTabSuppressionManager (one manager per window scene bound to that scene's gesture manager) |
| _SBPIPEndStashTabSuppressionGestureManager | `-_removeGestureRecognizers` | 0x1c635d908 | 0x1c7340728 | PORTED already: G3B.x BPPIPEndStashTabSuppressionManager (one manager per window scene bound to that scene's gesture manager) |
| _SBPIPEndStashTabSuppressionGestureManager | `-.cxx_destruct` | 0x1c635da68 | 0x1c734085c | EXCLUDED: ivar teardown only (.cxx_destruct) |

## F4 System gestures / pointer / indirect pan (74)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBAffordancePresenceController | `-dealloc` | 0x1c5ebce7c | 0x1c732fcb8 | PORTED already: G2C.x G2C_PresenceDealloc (+ Y2Gestures.x for the top affordance's own controller) |
| SBAffordancePresenceController | `-.cxx_destruct` | 0x1c5ebdba4 | 0x1c73309ec | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBExternalDisplaySystemGestureManager | `-_shouldEnableSystemGestureWithType:` | 0x1c6365c28 | 0x1c780bf58 | PORTED already: hook in G1D.x:1427, Tweak.x:381 |
| SBGrabberTongue | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c5e52778 | 0x1c72c4ba4 | TRIAGE PENDING |
| SBGrabberTongue | `-gestureRecognizerShouldBegin:` | 0x1c5e564a4 | 0x1c72c890c | PORTED already: 16.2 address cited in G2D.x |
| SBGrabberTongue | `-_handlePullGesture:` | 0x1c5e57bf8 | 0x1c72ca25c | TRIAGE PENDING |
| SBGrabberTongue | `-uninstall` | 0x1c5e677fc | 0x1c72da0e0 | EQUIVALENT: 16.0 already asks the tongue's window scene for its manager; the 16.2 extra removal of the tap recognizer concerns a recognizer 16.0 keeps on the tongue view |
| SBGrabberTongue | `-.cxx_destruct` | 0x1c5e67cb4 | 0x1c72da5a8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBGrabberTongue | `-_createTongueAndGestureRecognizersIfNecessaryWithColorStyle:` | 0x1c5e76524 | 0x1c72e8e30 | PORTED already: 16.2 address cited in G2D.x |
| SBIndirectPanGestureRecognizer | `-dealloc` | 0x1c6398bac | 0x1c7841f1c | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-reset` | 0x1c6398cb8 | 0x1c7841fec | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_resetTranslationState` | 0x1c6398d80 | 0x1c78420bc | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_shouldReceiveEvent:` | 0x1c6398e7c | 0x1c78421e0 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_hoverEntered:withEvent:` | 0x1c6399018 | 0x1c78423f8 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_hoverMoved:withEvent:` | 0x1c63990c4 | 0x1c784251c | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_hoverExited:withEvent:` | 0x1c6399a1c | 0x1c7842d20 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_hoverCancelled:withEvent:` | 0x1c6399a74 | 0x1c7842d88 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_mouseIdleTimerFired:` | 0x1c6399acc | 0x1c7843108 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_trackpadIdleTimerFired:` | 0x1c6399c44 | 0x1c78432a8 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_updateTranslationWithPointerEventAttributes:activeEdge:` | 0x1c639a0b0 | 0x1c7843de0 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-_pointerModelLocation` | 0x1c639a364 | 0x1c78440c4 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-currentHoverEvent` | 0x1c639ad14 | 0x1c7844fd4 | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-currentTouch` | 0x1c639ad38 | 0x1c784501c | OPEN: not ported on purpose (regression guard: pointer crossing / indirect edge gestures are verified on the device): 16.2 adds an idle watchdog and logging, makes the tracked touch / hover event weak, simplifies _shouldReceiveEvent: to the event type 0xb and scales the pointer translation with the container's screen; needs a device A/B |
| SBIndirectPanGestureRecognizer | `-.cxx_destruct` | 0x1c639af38 | 0x1c7845264 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBInteractiveScreenshotGestureManager | `-_updateFailureRequirements` | 0x1c62f56f0 | 0x1c77929c8 | EQUIVALENT: gesture manager passed through a register (ivar), same call |
| SBInteractiveScreenshotGestureManager | `-gestureRecognizerShouldBegin:` | 0x1c62f621c | 0x1c77934fc | TRIAGE PENDING |
| SBKeyboardHomeAffordanceController | `-_getHomeGrabberContainingView:isAlwaysPortrait:` | 0x1c640ebdc | 0x1c78bc418 | OPEN: NEEDS EDIT IN G3B.x: 16.2 asks [[sourceWindow windowScene] medusaHostedKeyboardWindowController] (home grabber of the hosted keyboard on the extended display); needs -[SBWindowScene medusaHostedKeyboardWindowController] exported from G3B.x (BPKB_ControllerForWindowScene) |
| SBKeyboardHomeAffordanceController | `-_updateHomeAffordance` | 0x1c640ed54 | 0x1c78bc648 | OPEN: NEEDS EDIT IN G3B.x: 16.2 asks [[sourceWindow windowScene] medusaHostedKeyboardWindowController] (home grabber of the hosted keyboard on the extended display); needs -[SBWindowScene medusaHostedKeyboardWindowController] exported from G3B.x (BPKB_ControllerForWindowScene) |
| SBLockedPointerManager | `-clientWithSceneIdentifier:prefersPointerLockStatus:` | 0x1c6227784 | 0x1c76b8d74 | PORTED already: hook in G4B.x:1411 |
| SBLockedPointerManager | `-layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:` | 0x1c62278a4 | 0x1c76b93c4 | PORTED already: hook in G4B.x:1430 |
| SBLockedPointerManager | `-layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` | 0x1c62278fc | 0x1c76b9528 | PORTED already: hook in G4B.x:1434 |
| SBLockedPointerManager | `-sceneManager:didAddExternalForegroundApplicationSceneHandle:` | 0x1c6227954 | 0x1c76b968c | PORTED already: hook in G4B.x:1438 |
| SBLockedPointerManager | `-sceneManager:didRemoveExternalForegroundApplicationSceneHandle:` | 0x1c6227960 | 0x1c76b9794 | PORTED already: hook in G4B.x:1442 |
| SBLockedPointerManager | `-sceneHandle:didUpdateSettingsWithDiff:previousSettings:` | 0x1c622796c | 0x1c76b989c | PORTED already: hook in G4B.x:1446 |
| SBLockedPointerManager | `-_shouldAllowPointerLockedForScene:` | 0x1c6227d44 | 0x1c76b9e5c | PORTED already: hook in G4B.x:1492 |
| SBLockedPointerManager | `-_queue_updateLockForLayoutState:` | 0x1c6227fb4 | 0x1c76ba124 | PORTED already: hook in G4B.x:1452 |
| SBLockedPointerManager | `-_queue_lockPointerForSceneIdentifier:` | 0x1c6228214 | 0x1c76ba3dc | PORTED already: hook in G4B.x:1469 |
| SBLockedPointerManager | `-_queue_unlockPointer` | 0x1c6228318 | 0x1c76ba590 | TRIAGE PENDING |
| SBLockedPointerManager | `-.cxx_destruct` | 0x1c6228524 | 0x1c76ba824 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBMainDisplaySystemGestureManager | `-_shouldEnableSystemGestureWithType:` | 0x1c5e76c00 | 0x1c72e9590 | PORTED already: hook in G1D.x:1416 |
| SBMainDisplaySystemGestureManager | `-_evaluateEnablement` | 0x1c62c1be0 | 0x1c775cbf8 | EQUIVALENT: same selector sequence; ivar offsets only |
| SBMainDisplaySystemGestureManager | `-shouldSystemGestureReceiveTouchWithLocation:ignoringUCB:` | 0x1c62c1e34 | 0x1c775ce54 | PORTED already: hook in G1D.x:2517 |
| SBMousePointerManager | `-requestPointerActivationForScene:` | 0x1c607e954 | 0x1c7501e8c | PORTED already: POINTER-CROSS-0.7.4 (pointer scenes per display, verified on device); the 16.2 scene display configuration accessor (_sbDisplayConfiguration) equals the 16.0 sb_displayIdentityForSceneManagers + FBDisplayManager lookup |
| SBMousePointerManager | `-pointerClientController:sceneDidActivate:` | 0x1c607eed4 | 0x1c75023d8 | PORTED already: POINTER-CROSS-0.7.4 (pointer scenes per display, verified on device); the 16.2 scene display configuration accessor (_sbDisplayConfiguration) equals the 16.0 sb_displayIdentityForSceneManagers + FBDisplayManager lookup |
| SBMousePointerManager | `-pointerClientController:sceneWillDeactivate:` | 0x1c607ef74 | 0x1c7502478 | PORTED already: POINTER-CROSS-0.7.4 (pointer scenes per display, verified on device); the 16.2 scene display configuration accessor (_sbDisplayConfiguration) equals the 16.0 sb_displayIdentityForSceneManagers + FBDisplayManager lookup |
| SBMousePointerManager | `-_updatePointerAssertionsAndScenes` | 0x1c607f288 | 0x1c750278c | PORTED already: POINTER-CROSS-0.7.4 (pointer scenes per display, verified on device); the 16.2 scene display configuration accessor (_sbDisplayConfiguration) equals the 16.0 sb_displayIdentityForSceneManagers + FBDisplayManager lookup |
| SBSystemGestureManager | `-_disableSystemGesture:withType:` | 0x1c5e67a50 | 0x1c72da320 | EQUIVALENT: 16.2 registers SBIndirectPanGestureRecognizer with the manager's indirect touch lifecycle monitor in enable / disable; 16.0 does it in the recognizer's own init / dealloc (same observer set); +sharedInstance -> -systemGestureManager is the same _UISystemGestureManager |
| SBSystemGestureManager | `-addGestureRecognizer:withType:` | 0x1c5e76a28 | 0x1c72e9354 | EQUIVALENT: hardening (isInvalidated flag, assertion, XCTest) and singleton -> property; _isTouchGestureWithType: range 0x63 -> 0x64 is the 16.2 enum growing by one type at 116 (PiP gestures), all ported types are below it |
| SBSystemGestureManager | `-_enableSystemGesture:withType:` | 0x1c5e76db0 | 0x1c72e9740 | EQUIVALENT: 16.2 registers SBIndirectPanGestureRecognizer with the manager's indirect touch lifecycle monitor in enable / disable; 16.0 does it in the recognizer's own init / dealloc (same observer set); +sharedInstance -> -systemGestureManager is the same _UISystemGestureManager |
| SBSystemGestureManager | `-windowForSystemGestures` | 0x1c5e8fd50 | 0x1c73029f8 | EQUIVALENT: hardening (isInvalidated flag, assertion, XCTest) and singleton -> property; _isTouchGestureWithType: range 0x63 -> 0x64 is the 16.2 enum growing by one type at 116 (PiP gestures), all ported types are below it |
| SBSystemGestureManager | `-_initWithDisplayIdentity:` | 0x1c6317c20 | 0x1c77b7078 | EQUIVALENT: hardening (isInvalidated flag, assertion, XCTest) and singleton -> property; _isTouchGestureWithType: range 0x63 -> 0x64 is the 16.2 enum growing by one type at 116 (PiP gestures), all ported types are below it |
| SBSystemGestureManager | `-setGesturesPreventedByStylus:` | 0x1c6317e20 | 0x1c77b72a0 | EQUIVALENT: hardening (isInvalidated flag, assertion, XCTest) and singleton -> property; _isTouchGestureWithType: range 0x63 -> 0x64 is the 16.2 enum growing by one type at 116 (PiP gestures), all ported types are below it |
| SBSystemGestureManager | `-invalidate` | 0x1c63182b0 | 0x1c77b7978 | EQUIVALENT: hardening (isInvalidated flag, assertion, XCTest) and singleton -> property; _isTouchGestureWithType: range 0x63 -> 0x64 is the 16.2 enum growing by one type at 116 (PiP gestures), all ported types are below it |
| SBSystemGestureManager | `-_isTouchGestureWithType:` | 0x1c6319528 | 0x1c77b8c14 | EQUIVALENT: hardening (isInvalidated flag, assertion, XCTest) and singleton -> property; _isTouchGestureWithType: range 0x63 -> 0x64 is the 16.2 enum growing by one type at 116 (PiP gestures), all ported types are below it |
| SBSystemGestureManager | `-_configureForNewSystemGestureWindowIfNecessary` | 0x1c6319958 | 0x1c77b912c | PORTED already: 16.2 address cited in X9Pin.x |
| SBSystemGestureManager | `-.cxx_destruct` | 0x1c6319cbc | 0x1c77b96a8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemGestureWorkspaceTransaction | `-_begin` | 0x1c5e59cc8 | 0x1c72cc454 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBSystemNotesContentViewController | `-_acquireTraitsParticipantOnWindowSceneIfNecessary:` | 0x1c631ab14 | 0x1c77ba4e8 | EQUIVALENT: Quick Note exists on the embedded display only (SBSystemNotesManager is created with the main display scene manager, 16.0 0x1c5f021c4 / 16.2 0x1c73765b8); the 16.2 rows move its gestures to the manager's own gesture manager and drop the per scene transient UI manager argument |
| SBSystemNotesInteractionManager | `-_setupFingerGestureRecognizers` | 0x1c64a2804 | 0x1c79596f4 | EQUIVALENT: Quick Note exists on the embedded display only (SBSystemNotesManager is created with the main display scene manager, 16.0 0x1c5f021c4 / 16.2 0x1c73765b8); the 16.2 rows move its gestures to the manager's own gesture manager and drop the per scene transient UI manager argument |
| SBSystemNotesInteractionManager | `-_shouldEdgeProtectGestureRecognizer:` | 0x1c64a389c | 0x1c795a7ac | EQUIVALENT: Quick Note exists on the embedded display only (SBSystemNotesManager is created with the main display scene manager, 16.0 0x1c5f021c4 / 16.2 0x1c73765b8); the 16.2 rows move its gestures to the manager's own gesture manager and drop the per scene transient UI manager argument |
| SBSystemNotesManager | `-_createContentViewControllerForPresentationContext:error:` | 0x1c6086fd4 | 0x1c7509f80 | EQUIVALENT: Quick Note exists on the embedded display only (SBSystemNotesManager is created with the main display scene manager, 16.0 0x1c5f021c4 / 16.2 0x1c73765b8); the 16.2 rows move its gestures to the manager's own gesture manager and drop the per scene transient UI manager argument |
| SBSystemNotesManager | `-_addContentViewControllerToPIPHierarchy:contentViewLayoutSettings:` | 0x1c6087368 | 0x1c750a3a4 | EQUIVALENT: Quick Note exists on the embedded display only (SBSystemNotesManager is created with the main display scene manager, 16.0 0x1c5f021c4 / 16.2 0x1c73765b8); the 16.2 rows move its gestures to the manager's own gesture manager and drop the per scene transient UI manager argument |
| SBSystemNotesManager | `-interactionManager:requestsStartSuppressingKeyboardForReason:` | 0x1c60884ec | 0x1c750b528 | EQUIVALENT: Quick Note exists on the embedded display only (SBSystemNotesManager is created with the main display scene manager, 16.0 0x1c5f021c4 / 16.2 0x1c73765b8); the 16.2 rows move its gestures to the manager's own gesture manager and drop the per scene transient UI manager argument |
| SBSystemNotesManager | `-.cxx_destruct` | 0x1c608859c | 0x1c750b640 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemPointerInteractionManager | `-pointerInteraction:window:regionForRequest:defaultRegion:` | 0x1c5f71c98 | 0x1c73e8a00 | EQUIVALENT: 16.2 passes the UIPointerRegionRequest to the delegate (shouldBeginPointerInteractionRequest:atLocation:forView:) and drops the defensive copy of the registered views; 16.0 delegates implement the old API; per-display routing is G2G.x / PTR.x |
| SBSystemPointerInteractionManager | `-.cxx_destruct` | 0x1c5f72200 | 0x1c73e8f28 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBTransientUIInteractionManager | `-viewForSystemGestureRecognizer:` | 0x1c60743c4 | 0x1c74f7328 | PORTED already: G2C.x g2c_scenemgr (per window scene manager bound to that scene's gesture manager) |
| SBTransientUIInteractionManager | `-registerParticipantForTapToDismiss:` | 0x1c60743cc | 0x1c74f736c | 7dd10ca: Y2Gestures.x y2_tuiscene (+mainDisplayManager answers the gesture manager of the manager's own window) [sha a557a56] |
| SBTransientUIInteractionManager | `-unregisterParticipantForTapToDismiss:` | 0x1c60744a8 | 0x1c74f7440 | 7dd10ca: Y2Gestures.x y2_tuiscene (+mainDisplayManager answers the gesture manager of the manager's own window) [sha a557a56] |
| SBTransientUIInteractionManager | `-registerParticipantForTapToUnhide:` | 0x1c6074548 | 0x1c74f74d8 | PORTED already: G2C.x g2c_scenemgr (per window scene manager bound to that scene's gesture manager) |
| SBTransientUIInteractionManager | `-unregisterParticipantForTapToUnhide:` | 0x1c6074700 | 0x1c74f7678 | PORTED already: G2C.x g2c_scenemgr (per window scene manager bound to that scene's gesture manager) |
| SBTransientUIInteractionManager | `-registerParticipantForIndirectPanToDismiss:` | 0x1c60747c8 | 0x1c74f7724 | 7dd10ca: Y2Gestures.x y2_tuiscene (+mainDisplayManager answers the gesture manager of the manager's own window) [sha a557a56] |
| SBTransientUIInteractionManager | `-unregisterParticipantForIndirectPanToDismiss:` | 0x1c60748c0 | 0x1c74f7814 | 7dd10ca: Y2Gestures.x y2_tuiscene (+mainDisplayManager answers the gesture manager of the manager's own window) [sha a557a56] |
| SBTransientUIInteractionManager | `-.cxx_destruct` | 0x1c60749f4 | 0x1c74f7978 | EXCLUDED: ivar teardown only (.cxx_destruct) |

## F5 Keyboard / hardware keyboard / focus (8)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBCommandTabController | `-init` | 0x1c60ee7e8 | 0x1c75731a8 | TRIAGE PENDING |
| SBCommandTabController | `-dealloc` | 0x1c60eead4 | 0x1c75734cc | TRIAGE PENDING |
| SBCommandTabController | `-_showWindow:` | 0x1c60f00cc | 0x1c7574b90 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBInputUISceneController | `+_setupInfo` | 0x1c5faa034 | 0x1c7422300 | TRIAGE PENDING |
| SBInputUISceneController | `-_createInputUIScene` | 0x1c5faa338 | 0x1c7422608 | TRIAGE PENDING |
| SBKeyboardFocusService | `-_handleDisconnectForServiceConnection:` | 0x1c5ec3e0c | 0x1c7336f1c | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBKeyboardFocusService | `-.cxx_destruct` | 0x1c5ec41b0 | 0x1c733744c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBKeyboardSuppressionManager | `-stopSuppressingKeyboardWithReason:` | 0x1c5e309e0 | 0x1c72a2f9c | TRIAGE PENDING |

## F6 Transient overlays / banners / alerts / Control Center / Spotlight / in-call (102)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBAccessibilityUIServerUISceneController | `+_setupInfo` | 0x1c5ec1848 | 0x1c73347e0 | PORTED already: hook in G3B.x:439 |
| SBAlertItemPresenterWindowSceneResolver | `-resolvedSharedModalAlertItemPresenterForAlertItem:` | 0x1c6045050 | 0x1c74c0984 | 7dd10ca: Y4Home.x y4_alertscene (alert controller scene, else the item's preferred scene, else the active display) [sha f7e180d] |
| SBAlertLayoutPresentationVerifier | `-initWithScreen:` | 0x1c63419f4 | 0x1c77e5aa8 | TRIAGE PENDING |
| SBAlertLayoutPresentationVerifier | `-dealloc` | 0x1c6341cc4 | 0x1c77e5e20 | TRIAGE PENDING |
| SBAssistiveTouchUISceneController | `+_setupInfo` | 0x1c5ec16fc | 0x1c7334694 | PORTED already: hook in G3B.x:433 |
| SBBannerManager | `-bannerSourceListener:sceneSpecificationForBannerSceneWithIdentifier:forProcess:userInfo:` | 0x1c64180e4 | 0x1c78c6efc | IRRELEVANT: banner pan gesture is created per window scene on demand and extra authorized bundle id (banners present on the iPad, FEATURES T1) |
| SBBannerManager | `+_defaultAuthorizedBundleIDs` | 0x1c6419244 | 0x1c78c80cc | IRRELEVANT: banner pan gesture is created per window scene on demand and extra authorized bundle id (banners present on the iPad, FEATURES T1) |
| SBBannerManager | `-_updateGesturePriorityForGestureRecognizerInWindowScene:` | 0x1c641a000 | 0x1c78c8e94 | IRRELEVANT: banner pan gesture is created per window scene on demand and extra authorized bundle id (banners present on the iPad, FEATURES T1) |
| SBDeviceApplicationRemoteTransientOverlayViewProvider | `-initWithSceneHandle:delegate:` | 0x1c6403db8 | 0x1c78b0d94 | EQUIVALENT: 16.2 reads [[presentationTarget targetPredicate] process] and shouldDismissInSwitcher from SBS classes that 16.0 clients cannot send (GAPS-IMPLEMENTED G6 A1: the 16.0 target decodes the process directly, kept); the provider registration with the SpringBoard singleton is replaced by per scene predicate matching in 16.2 (A1) |
| SBDeviceApplicationRemoteTransientOverlayViewProvider | `-presentRemoteTransientOverlayViewController:presentationRequest:` | 0x1c6403f48 | 0x1c78b0f10 | EQUIVALENT: 16.2 reads [[presentationTarget targetPredicate] process] and shouldDismissInSwitcher from SBS classes that 16.0 clients cannot send (GAPS-IMPLEMENTED G6 A1: the 16.0 target decodes the process directly, kept); the provider registration with the SpringBoard singleton is replaced by per scene predicate matching in 16.2 (A1) |
| SBDeviceApplicationRemoteTransientOverlayViewProvider | `-_handleAppSwitcherWillPresent:` | 0x1c6404b7c | 0x1c78b1b88 | EQUIVALENT: 16.2 reads [[presentationTarget targetPredicate] process] and shouldDismissInSwitcher from SBS classes that 16.0 clients cannot send (GAPS-IMPLEMENTED G6 A1: the 16.0 target decodes the process directly, kept); the provider registration with the SpringBoard singleton is replaced by per scene predicate matching in 16.2 (A1) |
| SBDruidUISceneController | `+_setupInfo` | 0x1c5fa9b78 | 0x1c7421b4c | TRIAGE PENDING |
| SBEnsembleUISceneController | `+_setupInfo` | 0x1c5f467dc | 0x1c73bae98 | TRIAGE PENDING |
| SBFullKeyboardAccessUISceneController | `+_setupInfo` | 0x1c5ec1464 | 0x1c73343fc | PORTED already: hook in G3B.x:421 |
| SBInCallBannerPresentableViewController | `-viewDidLayoutSubviews` | 0x1c6049048 | 0x1c74c49d0 | TRIAGE PENDING |
| SBInCallBannerPresentableViewController | `-viewDidLoad` | 0x1c6049144 | 0x1c74c4acc | TRIAGE PENDING |
| SBInCallPresentationManager | `-initWithWindowSceneManager:applicationController:bannerManager:` | 0x1c61d9940 | 0x1c7667a28 | TRIAGE PENDING |
| SBInCallPresentationManager | `-inCallClientPresentationSessionInterfaceOrientationForBannerPresentation:` | 0x1c61da180 | 0x1c7668470 | TRIAGE PENDING |
| SBInCallPresentationManager | `-_runZombieChecksForScene:` | 0x1c61dd4c0 | 0x1c766ba00 | PORTED already: 16.2 address cited in X6InCall.x |
| SBInCallPresentationManager | `-.cxx_destruct` | 0x1c61dd8b4 | 0x1c766be34 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBInCallPresentationSession | `-invalidate` | 0x1c60f12dc | 0x1c7575f58 | TRIAGE PENDING |
| SBInCallPresentationSession | `-inCallTransientOverlayViewController:didDisappearAnimated:` | 0x1c60f24d8 | 0x1c7577168 | TRIAGE PENDING |
| SBInCallPresentationSession | `-layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` | 0x1c60f29d4 | 0x1c757767c | TRIAGE PENDING |
| SBInCallPresentationSession | `-activeInterfaceOrientationDidChangeToOrientation:willAnimateWithDuration:fromOrientation:` | 0x1c60f2f9c | 0x1c7577c84 | TRIAGE PENDING |
| SBInCallPresentationSession | `-inCallBannerPresentableViewController:viewWillTransitionSizeWithAnimationSettings:` | 0x1c60f3bb0 | 0x1c75788b0 | TRIAGE PENDING |
| SBInCallPresentationSession | `-inCallTransientOverlayViewController:viewWillTransitionSizeWithAnimationSettings:` | 0x1c60f4318 | 0x1c7579068 | TRIAGE PENDING |
| SBInCallPresentationSession | `-_insertIntoSwitcherAsDismissedWithAnalyticsSource:transitionValidator:completion:` | 0x1c60f61ac | 0x1c757af7c | TRIAGE PENDING |
| SBInCallPresentationSession | `-_performBannerToFullScreenPresentationTransitionAnimated:analyticsSource:completion:` | 0x1c60f6ca4 | 0x1c757bbd8 | TRIAGE PENDING |
| SBInCallPresentationSession | `-_performBannerPresentationTransitionWithAnalyticsSource:completion:` | 0x1c60f783c | 0x1c757c7f0 | TRIAGE PENDING |
| SBInCallPresentationSession | `-_createJindoElement` | 0x1c60f7d50 | 0x1c757cdb4 | TRIAGE PENDING |
| SBInCallPresentationSession | `-_performSwitcherDismissalTransitionAnimated:shouldDestroyScene:analyticsSource:completion:` | 0x1c60f8338 | 0x1c757d4c4 | TRIAGE PENDING |
| SBInCallPresentationSession | `-_uiLockStateDidChange:` | 0x1c60f957c | 0x1c757e73c | TRIAGE PENDING |
| SBInCallPresentationSession | `-.cxx_destruct` | 0x1c60fe348 | 0x1c75835c4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBInCallTransientOverlayViewController | `-viewDidLayoutSubviews` | 0x1c615461c | 0x1c75d8ae4 | TRIAGE PENDING |
| SBInCallTransientOverlayViewController | `-viewDidLoad` | 0x1c615471c | 0x1c75d8be4 | TRIAGE PENDING |
| SBInCallTransientOverlayViewController | `-setContainerOrientation:` | 0x1c61558bc | 0x1c75d9d8c | TRIAGE PENDING |
| SBLiveTranscriptionUISceneController | `+_setupInfo` | 0x1c6424960 | 0x1c78d4718 | TRIAGE PENDING |
| SBModalLibraryController | `-_evaluateKeyboardWindowLevelAssertion` | 0x1c635a714 | 0x1c780061c | TRIAGE PENDING |
| SBModalLibraryController | `-_evaluateResignActiveAssertion` | 0x1c635a878 | 0x1c78007c4 | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBNotificationBannerDestination | `-_notificationViewControllerForRequest:` | 0x1c5e93ac4 | 0x1c7306764 | IRRELEVANT: banner view controller class and screen of the look view (banners present on the iPad: FEATURES T1 prefersEmbeddedDisplayPresentation) |
| SBNotificationBannerDestination | `-longLookWillPresentForNotificationViewController:` | 0x1c5e95db0 | 0x1c7308a4c | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBNotificationBannerDestination | `-presentedBannerScreenFrame` | 0x1c61fbd80 | 0x1c768aa1c | IRRELEVANT: banner view controller class and screen of the look view (banners present on the iPad: FEATURES T1 prefersEmbeddedDisplayPresentation) |
| SBNotificationCarPlayDestination | `-presentableDidDisappearAsBanner:withReason:` | 0x1c63d9448 | 0x1c7884370 | IRRELEVANT: CarPlay |
| SBNotificationCarPlayDestination | `-didSelectBannerOfPresentableViewController:` | 0x1c63d9638 | 0x1c7884580 | IRRELEVANT: CarPlay |
| SBOverlayUISceneController | `+_setupInfo` | 0x1c649a2a8 | 0x1c7950c6c | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBOverlayUISceneController | `-windowSceneDidConnect:` | 0x1c649a38c | 0x1c7950d50 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBRecordingIndicatorManager | `-_createRecordingIndicatorForStatusBarLocation` | 0x1c5fe6fe0 | 0x1c7461b54 | TRIAGE PENDING |
| SBRecordingIndicatorViewController | `-_screenTypeForcesFastFadeAnimations` | 0x1c62d3774 | 0x1c776e7f4 | PORTED already: 16.2 address cited in X5Recording.x |
| SBRecordingIndicatorViewController | `-calculateInitialIndicatorPositionAndSize` | 0x1c62d3bcc | 0x1c776ed0c | TRIAGE PENDING |
| SBRecordingIndicatorViewController | `-updateIndicatorVisibility:` | 0x1c62d47a0 | 0x1c776f8dc | TRIAGE PENDING |
| SBRecordingIndicatorViewController | `-updateIndicatorVisibilityWithFastFadeAnimation:` | 0x1c62d4fe4 | 0x1c777017c | TRIAGE PENDING |
| SBRecordingIndicatorViewController | `-_updateIndicatorForBacklightLuminance:previousBacklightLuminance:` | 0x1c62d5d34 | 0x1c7770f20 | TRIAGE PENDING |
| SBSearchPresenter | `-presentSearchAnimated:` | 0x1c6078164 | 0x1c74fb524 | IRRELEVANT: home screen search presentation state bookkeeping (animated flag, interaction completions) |
| SBSearchPresenter | `-dismissSearchAnimated:` | 0x1c6078374 | 0x1c74fb7ec | IRRELEVANT: home screen search presentation state bookkeeping (animated flag, interaction completions) |
| SBSearchPresenter | `-scrollViewDidScroll:` | 0x1c60786c0 | 0x1c74fbbec | IRRELEVANT: home screen search presentation state bookkeeping (animated flag, interaction completions) |
| SBSpotlightMultiplexingViewController | `-viewDidAppear:` | 0x1c62aab00 | 0x1c7744f64 | EQUIVALENT: Spotlight presents on the iPad only (FEATURES T1): the 16.2 change replaces mainDisplaySceneManager / the main hosted keyboard controller by the view controller's own window scene, which is the embedded scene |
| SBSpotlightMultiplexingViewController | `-didBecomeActiveDelegate` | 0x1c62aae6c | 0x1c7745330 | EQUIVALENT: Spotlight presents on the iPad only (FEATURES T1): the 16.2 change replaces mainDisplaySceneManager / the main hosted keyboard controller by the view controller's own window scene, which is the embedded scene |
| SBSpotlightMultiplexingViewController | `-didResignActiveDelegate:` | 0x1c62ab1e8 | 0x1c774570c | EQUIVALENT: Spotlight presents on the iPad only (FEATURES T1): the 16.2 change replaces mainDisplaySceneManager / the main hosted keyboard controller by the view controller's own window scene, which is the embedded scene |
| SBSpotlightMultiplexingViewController | `-sceneManager:didCreateScene:` | 0x1c62ab344 | 0x1c77458c8 | EQUIVALENT: Spotlight presents on the iPad only (FEATURES T1): the 16.2 change replaces mainDisplaySceneManager / the main hosted keyboard controller by the view controller's own window scene, which is the embedded scene |
| SBSpotlightMultiplexingViewController | `-sceneManager:didDestroyScene:` | 0x1c62ab3d0 | 0x1c77459a0 | EQUIVALENT: Spotlight presents on the iPad only (FEATURES T1): the 16.2 change replaces mainDisplaySceneManager / the main hosted keyboard controller by the view controller's own window scene, which is the embedded scene |
| SBSpotlightPresentableViewController | `-viewDidLoad` | 0x1c641cb54 | 0x1c78cba54 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-updatePresentationProgress:withOffset:presentationState:` | 0x1c641cf08 | 0x1c78cbe58 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-spotlightMultiplexingViewController:externalKeyboardViewContainsKeyboardDidChange:` | 0x1c641e29c | 0x1c78cd81c | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-_setUpSearchAnimationSettings` | 0x1c641ee60 | 0x1c78ce778 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-_setUpSearchAffordance` | 0x1c641f09c | 0x1c78ce980 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-_setUpHomeAffordance` | 0x1c641f1f0 | 0x1c78ceacc | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-_setUpHostedContentMetrics` | 0x1c641f3b4 | 0x1c78cec9c | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-_beginRequiringSearchBarPortalViewForReason:` | 0x1c641f688 | 0x1c78ced88 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-_endRequiringSearchBarPortalViewForReason:` | 0x1c641fa34 | 0x1c78cf170 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBSpotlightPresentableViewController | `-.cxx_destruct` | 0x1c6420264 | 0x1c78cfa08 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSpotlightTransientOverlayInteractiveGestureTransaction | `-_begin` | 0x1c5fadef0 | 0x1c742629c | PORTED already: 16.2 address cited in X7Keyboard.x |
| SBSystemUISceneController | `-dealloc` | 0x1c64adce0 | 0x1c796614c | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-windowSceneDidConnect:` | 0x1c64add34 | 0x1c79661cc | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-windowSceneDidDisconnect:` | 0x1c64adf98 | 0x1c796647c | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-_newSceneControllerForWindowScene:sceneRequestOptions:traitsRole:level:` | 0x1c64ae234 | 0x1c7966524 | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-__newSceneIdentifierForWindowScene:` | 0x1c64ae564 | 0x1c7966834 | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-createSceneForProcessIdentity:withOptions:completion:` | 0x1c64aec88 | 0x1c7966a6c | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-destroyScenesWithPersistentIdentifiers:processIdentity:completion:` | 0x1c64ae678 | 0x1c7966de0 | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-sceneWorkspaceControllerForProcessIdentity:` | 0x1c64ae618 | 0x1c7967488 | NOT PORTED: same as SBSingleSceneController (FEATURES-0.7.9 S1): controllers keyed by display identity instead of window scene, _invalidateSceneControllersForWindowScene:, sceneVendingPolicy; behaviour differs only for display reconnect lifetime |
| SBSystemUISceneController | `-descriptionBuilderWithMultilinePrefix:` | 0x1c64af1c8 | 0x1c7967950 | EXCLUDED: description / debug text only |
| SBSystemUISceneController | `-.cxx_destruct` | 0x1c64af2a0 | 0x1c7967b0c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemUIScenesCoordinator | `-init` | 0x1c630a8a4 | 0x1c77a8f64 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSystemUIScenesCoordinator | `-sceneWorkspaceControllerForProcessIdentity:` | 0x1c630b18c | 0x1c77a9904 | NOT PORTED: system UI scenes keyed by display identity with a scene vending policy and activation context generators (16.2): FEATURES-0.7.9 S1 per display system UI scenes (accessibility UI server, eyedropper, Moments) stays PARTIAL; the 16.0 controllers already create scenes per connected window scene |
| SBSystemUIScenesCoordinator | `-.cxx_destruct` | 0x1c630baa0 | 0x1c77a9ef0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBTodayViewSpotlightPresenter | `-presentSpotlightAnimated:` | 0x1c62bf888 | 0x1c775a874 | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBTodayViewSpotlightPresenter | `-dismissSpotlightAnimated:` | 0x1c62bf894 | 0x1c775a87c | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| SBTransientOverlayPresentationManager | `-setCoverSheetPresentationManager:` | 0x1c616c2a0 | 0x1c75f3dcc | EQUIVALENT: 16.2: embedded scene connect no longer repeated inline (the scene manager connects it), in call presentation manager handed to every presenter (X6InCall.x per scene in call), the dismissal request waits for all presenters through a dispatch group (completion barrier only, G4B.x ports the in scene dismissal) |
| SBTransientOverlayPresentationManager | `-windowSceneDidConnect:` | 0x1c616c958 | 0x1c75f4450 | EQUIVALENT: 16.2: embedded scene connect no longer repeated inline (the scene manager connects it), in call presentation manager handed to every presenter (X6InCall.x per scene in call), the dismissal request waits for all presenters through a dispatch group (completion barrier only, G4B.x ports the in scene dismissal) |
| SBTransientOverlayPresentationManager | `-windowSceneDidDisconnect:` | 0x1c616ca94 | 0x1c75f45c0 | PORTED already: hook in G4B.x:2443 |
| SBTransientOverlayPresentationManager | `-performDismissalRequest:` | 0x1c616d570 | 0x1c75f52f4 | EQUIVALENT: 16.2: embedded scene connect no longer repeated inline (the scene manager connects it), in call presentation manager handed to every presenter (X6InCall.x per scene in call), the dismissal request waits for all presenters through a dispatch group (completion barrier only, G4B.x ports the in scene dismissal) |
| SBTransientOverlayScenePresenter | `-dealloc` | 0x1c648fda8 | 0x1c79462a4 | EQUIVALENT: ivar offset shift, the in call non modal suppression assertion is released in dealloc (X6InCall.x), System Aperture z stack policy (preventsSystemApertureSuppressionFromBelow, iPhone), banner suppression reason string |
| SBTransientOverlayScenePresenter | `-performPresentationRequest:` | 0x1c64914fc | 0x1c7947cf4 | 7dd10ca: Y9Misc.x y9_overlayfocus (focus stealing assertion for the overlay window, 16.2 keyFocusStealingAssertion); the rest is ivar renumbering (_inCallPresentationManager, _deviceOrientationUpdateDeferralAssertion) |
| SBTransientOverlayScenePresenter | `-zStackParticipant:updatePreferences:` | 0x1c64936c0 | 0x1c7949f20 | EQUIVALENT: ivar offset shift, the in call non modal suppression assertion is released in dealloc (X6InCall.x), System Aperture z stack policy (preventsSystemApertureSuppressionFromBelow, iPhone), banner suppression reason string |
| SBTransientOverlayScenePresenter | `-_dismissEntity:animated:completion:` | 0x1c64949c8 | 0x1c794b24c | 7dd10ca: Y9Misc.x y9_overlayfocus (focus stealing assertion for the overlay window, 16.2 keyFocusStealingAssertion); the rest is ivar renumbering (_inCallPresentationManager, _deviceOrientationUpdateDeferralAssertion) |
| SBTransientOverlayScenePresenter | `-_updateStatusBarWithCurrentExternalStatusBarSettings:animated:` | 0x1c6496020 | 0x1c794c8c8 | PORTED already: 16.2 address cited in X5Recording.x |
| SBTransientOverlayScenePresenter | `-_updateDeactivationAssertions` | 0x1c6496868 | 0x1c794d11c | EQUIVALENT: ivar offset shift, the in call non modal suppression assertion is released in dealloc (X6InCall.x), System Aperture z stack policy (preventsSystemApertureSuppressionFromBelow, iPhone), banner suppression reason string |
| SBTransientOverlayScenePresenter | `-_updateFeaturePolicies` | 0x1c6496c60 | 0x1c794d538 | EQUIVALENT: ivar offset shift, the in call non modal suppression assertion is released in dealloc (X6InCall.x), System Aperture z stack policy (preventsSystemApertureSuppressionFromBelow, iPhone), banner suppression reason string |
| SBTransientOverlayScenePresenter | `-.cxx_destruct` | 0x1c6497694 | 0x1c794dfac | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBUserNotificationAlert | `-_clearRemoteViewControllerIfPresent` | 0x1c5fa4e3c | 0x1c741dc08 | TRIAGE PENDING |
| SBVoiceControlUISceneController | `+_setupInfo` | 0x1c5ec15b0 | 0x1c7334548 | PORTED already: hook in G3B.x:427 |
| _SBTodaySpotlightViewController | `-_setDisplayLayoutElementActive:` | 0x1c62bfca8 | 0x1c775ac8c | IRRELEVANT: home screen / Today Spotlight pull down UI (animated flag, search pill reference view, display layout element level): iPad Home Screen only |
| _SBTransientOverlayPresentedEntity | `-.cxx_destruct` | 0x1c64979d4 | 0x1c794e318 | EXCLUDED: ivar teardown only (.cxx_destruct) |

## F7 Displays / external display / screens (72)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| SBDisplayAppInteractionEventSource | `-_notifyTransition:beginning:` | 0x1c63bb4b0 | 0x1c7865ba4 | TRIAGE PENDING |
| SBDisplayAssertionCoordinator | `-rootDisplayDidConnect:` | 0x1c633ae40 | 0x1c77de664 | TRIAGE PENDING |
| SBDisplayAssertionCoordinator | `-rootDisplayDidDisconnect:` | 0x1c633af88 | 0x1c77de838 | PORTED already: 16.2 address cited in G4B.x |
| SBDisplayAssertionPreferences | `-copyWithZone:` | 0x1c649c7d0 | 0x1c79535e0 | PORTED already: hook in G4B.x:417 |
| SBDisplayAssertionPreferences | `-isEqual:` | 0x1c649c830 | 0x1c795364c | PORTED already: hook in G4B.x:423 |
| SBDisplayAssertionPreferences | `-hash` | 0x1c649c8f0 | 0x1c795371c | PORTED already: hook in G4B.x:429 |
| SBDisplayAssertionPreferences | `-description` | 0x1c649c984 | 0x1c79537c4 | EXCLUDED: description / debug text only |
| SBDisplayManager | `-initWithDisplayManager:sceneManagerCoordinator:assertionCoordinator:powerLogReporter:` | 0x1c64d3e80 | 0x1c798f60c | TRIAGE PENDING |
| SBDisplayManager | `-displayMonitor:didConnectIdentity:withConfiguration:` | 0x1c64d47a4 | 0x1c798ff88 | TRIAGE PENDING |
| SBDisplayManager | `-displayMonitor:willDisconnectIdentity:` | 0x1c64d509c | 0x1c7990b4c | PORTED already: hook in G4B.x:528 |
| SBDisplayManager | `-.cxx_destruct` | 0x1c64d62dc | 0x1c79926a4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBDisplayPortalManager | `-_createPortalForSourceView:sourceWindowScene:targetWindowScene:traitsRole:` | 0x1c61c2bd8 | 0x1c765172c | TRIAGE PENDING |
| SBDisplayPowerLogEntry | `+forDisplay:mode:zoom:` | 0x1c63ca96c | 0x1c787663c | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBDisplayPowerLogReporter | `-reportPowerLogEntry:` | 0x1c63175f0 | 0x1c77b6a40 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBExternalDisplayCoverSheetController | `-initWithWindowScene:` | 0x1c62f2a98 | 0x1c778fb6c | TRIAGE PENDING |
| SBExternalDisplayCoverSheetController | `-dealloc` | 0x1c62f2ee0 | 0x1c7790028 | PORTED already: hook in Tweak.x:458 |
| SBExternalDisplayCoverSheetController | `-backlightController:willAnimateBacklightToFactor:source:` | 0x1c62f333c | 0x1c77905f8 | PORTED already: hook in Tweak.x:500 |
| SBExternalDisplayCoverSheetController | `-_embeddedLockStateDidChange:` | 0x1c62f3408 | 0x1c7790784 | PORTED already: hook in Tweak.x:486 |
| SBExternalDisplayCoverSheetController | `-_updateExternalDisplayCoverSheetExistence` | 0x1c62f34d4 | 0x1c77908f8 | PORTED already: hook in Tweak.x:492 |
| SBExternalDisplayCoverSheetController | `-_setScreenOn:` | 0x1c62f367c | 0x1c7790b4c | PORTED already: hook in Tweak.x:470 |
| SBExternalDisplayCoverSheetController | `-.cxx_destruct` | 0x1c62f40e8 | 0x1c77913d0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBExternalDisplayCoverSheetViewController | `-.cxx_destruct` | 0x1c62f29d0 | 0x1c778fab8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBExternalDisplayEducationObserver | `-dealloc` | 0x1c6331ebc | 0x1c77d2a70 | PORTED already: hook in G4B.x:1035 |
| SBExternalDisplayRuntimeAvailabilitySettings | `+_moduleWithSectionTitle:` | 0x1c5fabc44 | 0x1c7423fd8 | TRIAGE PENDING |
| SBExternalDisplayService | `-initWithDisplayManager:` | 0x1c63321d0 | 0x1c77d52a4 | TRIAGE PENDING |
| SBExternalDisplayService | `-setDisplayMirroringEnabled:forDisplay:` | 0x1c6332afc | 0x1c77d5db4 | PORTED already: 16.2 address cited in Group4Connect.m |
| SBExternalDisplayService | `-listener:didReceiveConnection:withContext:` | 0x1c6333130 | 0x1c77d63f4 | TRIAGE PENDING |
| SBExternalDisplayService | `-_supportedScalesForDisplay:error:` | 0x1c6333af0 | 0x1c77d6d98 | TRIAGE PENDING |
| SBExternalDisplaySettings | `-setDefaultValues` | 0x1c5fab324 | 0x1c74235f4 | PORTED already: hook in G4B.x:2218 |
| SBExternalDisplaySettings | `+settingsControllerModule` | 0x1c5fab3cc | 0x1c74236a8 | TRIAGE PENDING |
| SBMainDisplayInterfaceOrientationAggregator | `-_layoutOrientation` | 0x1c6038134 | 0x1c74b3694 | TRIAGE PENDING |
| SBMainScreenActiveInterfaceOrientationWindow | `-initWithWindowScene:role:debugName:` | 0x1c63633b8 | 0x1c7808d8c | TRIAGE PENDING |
| SBMirroredDisplayController | `-_ensureCADisplayModeForMirroring` | 0x1c5feb224 | 0x1c7465e30 | TRIAGE PENDING |
| SBMirroredDisplayController | `-_updateDisplayAssertion` | 0x1c5feb828 | 0x1c74664a0 | PORTED already: hook in G4B.x:451 |
| SBNonInteractiveDisplayControllerPolicy | `-connectToDisplayController:displayConfiguration:` | 0x1c643688c | 0x1c78e832c | TRIAGE PENDING |
| SBNonInteractiveDisplayControllerPolicy | `-displayController:updatePresentationWithSceneManager:displayConfiguration:completion:` | 0x1c6437860 | 0x1c78e92ec | TRIAGE PENDING |
| SBNonInteractiveDisplayControllerPolicy | `-_fetchOrCreateSceneForApplication:monitoredDisplayScene:fromSceneManager:displayConfiguration:deactivationReasons:` | 0x1c6438374 | 0x1c78e9e38 | TRIAGE PENDING |
| SBNonInteractiveDisplayControllerPolicy | `-.cxx_destruct` | 0x1c6438cac | 0x1c78ea79c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSceneHostingDisplayController | `-transformDisplayConfiguration:withBuilder:` | 0x1c5f46bf8 | 0x1c73bb2b8 | PORTED already: 16.2 address cited in X3Mode.x |
| SBSceneHostingDisplayController | `-connectToDisplayIdentity:configuration:displayManager:sceneManager:caDisplayQueue:assertion:` | 0x1c5f47120 | 0x1c73bbc30 | TRIAGE PENDING |
| SBSceneHostingDisplayController | `-displayIdentityDidUpdate:configuration:` | 0x1c5f476fc | 0x1c73bc150 | TRIAGE PENDING |
| SBSceneHostingDisplayController | `-displayIdentityDidDisconnect:` | 0x1c5f47a64 | 0x1c73bc47c | TRIAGE PENDING |
| SBSceneHostingDisplayController | `-_ensureCADisplayUpToDate:completion:` | 0x1c5f48424 | 0x1c73bce50 | PORTED already: 16.2 address cited in X3Mode.x |
| SBSceneHostingDisplayController | `-_updatePolicyForPresentation:` | 0x1c5f48b44 | 0x1c73bd620 | TRIAGE PENDING |
| SBSceneHostingDisplayController | `-_createDisplayAssertionPreferences` | 0x1c5f4a328 | 0x1c73bed8c | PORTED already: hook in G4B.x:468 |
| SBSceneHostingDisplayController | `-.cxx_destruct` | 0x1c5f4af84 | 0x1c73bf8dc | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSceneHostingDisplayControllerProvider | `-displayManager:didConnectIdentity:withConfiguration:` | 0x1c5ed1ea0 | 0x1c7345f0c | TRIAGE PENDING |
| SBSceneHostingDisplayControllerProvider | `-displayManager:didDisconnectIdentity:` | 0x1c5ed1f90 | 0x1c7345fe0 | PORTED already: 16.2 address cited in Group4Connect.m |
| SBSceneHostingDisplayControllerProvider | `-displayControllerInfoForConnectingDisplay:configuration:` | 0x1c5ed2044 | 0x1c73460b4 | TRIAGE PENDING |
| SBSceneHostingDisplayControllerProvider | `-transformDisplayConfiguration:` | 0x1c5ed2218 | 0x1c7346334 | PORTED already: 16.2 address cited in X3Mode.x |
| SBScreenSleepCoordinator | `-transitionToVisualState:fromVisualState:animated:completion:` | 0x1c6400e74 | 0x1c78adce8 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBScreenWakeAnimationController | `-_startWakeAnimationsForWaking:animationSettings:` | 0x1c5eade3c | 0x1c7320b90 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBScreenWakeAnimationController | `-prepareToWakeForSource:timeAlpha:statusBarAlpha:target:dateView:completion:` | 0x1c6251f2c | 0x1c76e756c | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBSystemShellEmbeddedDisplayController | `-connectToDisplayIdentity:configuration:displayManager:sceneManager:caDisplayQueue:assertion:` | 0x1c6122438 | 0x1c75ac7ec | PORTED already: hook in G3.x:880 |
| SBSystemShellEmbeddedDisplayController | `-_updateDisplayAssertionPreferences` | 0x1c6122c54 | 0x1c75ad068 | TRIAGE PENDING |
| SBSystemShellEmbeddedDisplayController | `-.cxx_destruct` | 0x1c6122dac | 0x1c75ad2a0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemShellExtendedDisplayControllerPolicy | `-dealloc` | 0x1c6338628 | 0x1c77db9d4 | TRIAGE PENDING |
| SBSystemShellExtendedDisplayControllerPolicy | `-connectToDisplayController:displayConfiguration:` | 0x1c63386b4 | 0x1c77dba48 | PORTED already: hook in G4B.x:1054 |
| SBSystemShellExtendedDisplayControllerPolicy | `-displayController:didBeginTransaction:sceneManager:displayConfiguration:deactivationReasons:` | 0x1c6339104 | 0x1c77dc984 | TRIAGE PENDING |
| SBSystemShellExtendedDisplayControllerPolicy | `-displayController:updatePresentationWithSceneManager:displayConfiguration:completion:` | 0x1c6339470 | 0x1c77dcbe0 | PORTED already: hook in G4B.x:1151 |
| SBSystemShellExtendedDisplayControllerPolicy | `-descriptionBuilderWithMultilinePrefix:` | 0x1c6339c60 | 0x1c77dd340 | EXCLUDED: description / debug text only |
| SBSystemShellExtendedDisplayControllerPolicy | `-settings:changedValueForKey:` | 0x1c633a1bc | 0x1c77ddad8 | TRIAGE PENDING |
| SBSystemShellExtendedDisplayControllerPolicy | `-.cxx_destruct` | 0x1c633aa1c | 0x1c77de0e0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBWallpaperController | `-initWithWindowScene:orientation:variant:wallpaperConfigurationManager:cachingIdentifier:` | 0x1c616fe78 | 0x1c75f7b58 | TRIAGE PENDING |
| SBWallpaperController | `-posterHandlesWakeAnimation` | 0x1c6171bf4 | 0x1c75f969c | TRIAGE PENDING |
| SBWallpaperServer | `-noteDidReceiveMessage:withType:fromClient:` | 0x1c631e2d8 | 0x1c77bdcc4 | IRRELEVANT: wallpaper poster server (iPhone lock screen posters) |
| _SBDisplayAssertionStack | `-acquireAssertionForDisplay:level:deactivationReasons:delegate:` | 0x1c6054abc | 0x1c74d1a78 | TRIAGE PENDING |
| _SBDisplayAssertionStack | `-invalidateForDisplayDisconnect` | 0x1c6054e98 | 0x1c74d1e5c | TRIAGE PENDING |
| _SBDisplayAssertionStack | `-invalidateAssertionForDerivedDisplayDisconnect:` | 0x1c605525c | 0x1c74d2228 | TRIAGE PENDING |
| _SBDisplayAssertionStack | `-_assertion:updatedPreferences:` | 0x1c605536c | 0x1c74d2340 | TRIAGE PENDING |
| _SBDisplayAssertionStack | `-_assertionDidInvalidate:` | 0x1c6055560 | 0x1c74d25a8 | TRIAGE PENDING |
| _SBDisplayAssertionStack | `-_evalAndApplyOldPreferences:newPreferences:` | 0x1c6055690 | 0x1c74d2744 | PORTED already: hook in G4B.x:1213 |

## F8 Everything else (iPhone / aperture / lock screen / Siri / misc) (291)

| class | method | 16.0 | 16.2 | verdict |
|---|---|---|---|---|
| FBSMutableSceneSettings(SBTransientLocal) | `-sb_displayIdentityForSceneManagers` | 0x1c60ee638 | 0x1c7573028 | TRIAGE PENDING |
| FBSSceneSettings(SBTransientLocal) | `-sb_displayIdentityForSceneManagers` | 0x1c60ee5bc | 0x1c7572f60 | TRIAGE PENDING |
| NCNotificationRequest(AlertSuppression) | `-sb_shouldSuppressAlert` | 0x1c5e9343c | 0x1c73060dc | TRIAGE PENDING |
| SBActivityBannerViewController | `-dealloc` | 0x1c5f9a018 | 0x1c7411c38 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityBannerViewController | `-requestIdentifier` | 0x1c5f9a0a8 | 0x1c7411cd4 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityBannerViewController | `-viewDidLoad` | 0x1c5f9a19c | 0x1c7411e40 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityBannerViewController | `-viewWillLayoutSubviews` | 0x1c5f9a2b8 | 0x1c7412038 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityBannerViewController | `-.cxx_destruct` | 0x1c5f9a538 | 0x1c7412800 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBActivityManager | `-init` | 0x1c6061344 | 0x1c74e0608 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityManager | `-dealloc` | 0x1c606153c | 0x1c74e08b0 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityManager | `-startObservingActivityUpdates` | 0x1c6061648 | 0x1c74e0ab8 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityManager | `-isActivitySupported` | 0x1c6061964 | 0x1c74e0dac | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityManager | `-_playSoundWithAlertOptions:` | 0x1c6062164 | 0x1c74e2f58 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivityManager | `-.cxx_destruct` | 0x1c60622a0 | 0x1c74e384c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBActivitySystemApertureElementObserver | `-init` | 0x1c6108534 | 0x1c758e930 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivitySystemApertureElementObserver | `-activityDidStart:` | 0x1c61085c0 | 0x1c758ea5c | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivitySystemApertureElementObserver | `-activityDidEnd:` | 0x1c6108948 | 0x1c758ef40 | IRRELEVANT: Live Activities (16.1, iPhone only: no Live Activity UI on iPad) |
| SBActivitySystemApertureElementObserver | `-.cxx_destruct` | 0x1c61092d8 | 0x1c7593224 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBAlwaysOnPolicyCoordinator | `-activate` | 0x1c6319e14 | 0x1c77b9808 | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBAlwaysOnTelemetryEmitter | `-dealloc` | 0x1c6163810 | 0x1c75ead5c | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBAlwaysOnTelemetryEmitter | `-completeIntializationAfterBLSStartup` | 0x1c6163874 | 0x1c75eadfc | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBAlwaysOnTelemetryEmitter | `-backlight:didChangeAlwaysOnEnabled:` | 0x1c6163978 | 0x1c75eaf40 | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBAlwaysOnTelemetryEmitter | `-.cxx_destruct` | 0x1c61654d4 | 0x1c75ecff4 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBAlwaysOnTelemetryMetrics | `-accumulateRenderHistogram:` | 0x1c6449f10 | 0x1c78fcdb0 | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBAlwaysOnTelemetryMetrics | `-dataForPowerlogEvent:` | 0x1c644a328 | 0x1c78fd594 | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBAlwaysOnTelemetryMetrics | `-.cxx_destruct` | 0x1c644aa50 | 0x1c78fde68 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBAppSuggestionManager | `-_evaluateSuggestionUpdates:` | 0x1c5e371ec | 0x1c72a965c | IRRELEVANT: app prediction / suggestions |
| SBAppSuggestionManager | `-_listenForNotifications` | 0x1c62dafdc | 0x1c7775a74 | IRRELEVANT: app prediction / suggestions |
| SBAppSuggestionManager | `-_stopListeningForNotifications` | 0x1c62db120 | 0x1c7775b74 | IRRELEVANT: app prediction / suggestions |
| SBAppVisibilityPreferences | `-update` | 0x1c5fabf8c | 0x1c7424330 | TRIAGE PENDING |
| SBApplicationInfo | `-_loadFromProxy:` | 0x1c5fb416c | 0x1c742c7ac | IRRELEVANT: app info plist loading (boolForKey: for a new key; no windowing) |
| SBAssistantController | `-assistantSession:viewWillAppearInWindowScene:` | 0x1c627abb0 | 0x1c7712e48 | IRRELEVANT: Siri |
| SBAssistantController | `-.cxx_destruct` | 0x1c627cf1c | 0x1c77151c0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBAssistantGestureManager | `-_setupSystemDismissalGestures` | 0x1c6282fcc | 0x1c771b438 | IRRELEVANT: Siri |
| SBAssistantSession | `-_viewWillAppear:` | 0x1c6191424 | 0x1c761acec | IRRELEVANT: Siri |
| SBAudioRecordingManager | `-setNowRecordingAppForActiveAudioRecordingAttributions:callDescriptors:` | 0x1c64ea440 | 0x1c79a70b0 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBAudioRecordingManager | `-_verifyBackgroundAudioActivityForApplication:withDelay:` | 0x1c64ea608 | 0x1c79a72f0 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBCoverSheetPresentationManager | `-setHasBeenDismissedSinceKeybagLock:` | 0x1c5e7cc58 | 0x1c72ef618 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-coverSheetSlidingViewController:committingToEndPresented:` | 0x1c5e84184 | 0x1c72f6c80 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-_cleanupATransition` | 0x1c5e84a0c | 0x1c72f7538 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-screenEdgesDeferringSystemGestures` | 0x1c5ea7db4 | 0x1c731aaf4 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-_authenticationChanged:` | 0x1c5eb3b98 | 0x1c7326930 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-init` | 0x1c61a2e0c | 0x1c762e448 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-setLockScreenEnvironment:` | 0x1c61a3760 | 0x1c762ee4c | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-secureAppOfTypeDidEnd:` | 0x1c61a5784 | 0x1c7630ff0 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-zStackParticipant:updatePreferences:` | 0x1c61a5a90 | 0x1c76312fc | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPresentationManager | `-.cxx_destruct` | 0x1c61a756c | 0x1c7633000 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBCoverSheetPrimarySlidingViewController | `-_createPanelWallpaperEffectViewIfNeeded` | 0x1c5e7e240 | 0x1c72f0d88 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPrimarySlidingViewController | `-_beginTransitionFromAppeared:` | 0x1c5e80e8c | 0x1c72f3974 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPrimarySlidingViewController | `-_endTransitionToAppeared:` | 0x1c5e86bfc | 0x1c72f971c | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPrimarySlidingViewController | `-loadView` | 0x1c628e8b8 | 0x1c7727a18 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPrimarySlidingViewController | `-_updateBackgroundIfNecessary` | 0x1c628fe18 | 0x1c7728f88 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetPrimarySlidingViewController | `-_setupPanelPartsIfNecessary` | 0x1c628fff8 | 0x1c7729174 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSceneManager | `-updateForegroundScenesForCoverSheetAnimationActive:` | 0x1c5e7e46c | 0x1c72f1014 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSlidingViewController | `-_handlePresentGesture:` | 0x1c5e7c590 | 0x1c72eef44 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSlidingViewController | `-_addSystemGestureRecognizers` | 0x1c5e7e814 | 0x1c72f13f8 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSlidingViewController | `-_updatePositionViewForProgress:forPresentationValue:` | 0x1c5e821b8 | 0x1c72f4cc0 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSlidingViewController | `-_studyLogForCompletionOfTransitionToPresented:` | 0x1c5e86dbc | 0x1c72f98f8 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSlidingViewController | `-initWithContentViewController:canBePulledDown:canBePulledUp:dismissalPreemptingGestureRecognizer:` | 0x1c60c5854 | 0x1c7549f34 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSlidingViewController | `-.cxx_destruct` | 0x1c60c7d30 | 0x1c754c4d0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBCoverSheetSpotlightViewController | `-updatePresentationProgress:withOffset:presentationState:` | 0x1c63b58cc | 0x1c785ffa8 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCoverSheetSystemGesturesDelegate | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c5e52e18 | 0x1c72c5274 | EQUIVALENT: cover sheet / lock screen exists on the embedded display only: the 16.2 change replaces global lookups (mainDisplayManager / sharedInstance) by the window scene's, which is the embedded scene for these objects (external display cover sheet = SBExternalDisplayCoverSheet*) |
| SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier | `-handleContinuousExposeIdentifiersChangedEvent:` | 0x1c6104180 | 0x1c758977c | PORTED already: hook in G1C.x:988 |
| SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier | `-_completeIfNeededIgnoringHover:` | 0x1c610455c | 0x1c7589b7c | PORTED already: hook in G1C.x:1035 |
| SBDashBoardCameraPageViewController | `-_addOrRemoveGestureForCurrentSettings` | 0x1c5eb9260 | 0x1c732c038 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBDashBoardEmergencyDialerController | `-isMakingEmergencyCall` | 0x1c60d8ba8 | 0x1c755d520 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBDashBoardHostedAppViewController | `-setHostedAppReferenceSize:withInterfaceOrientation:` | 0x1c630770c | 0x1c77a5448 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBDashBoardSetupView | `-_createDisplayLink` | 0x1c644f484 | 0x1c790342c | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBDefaultImplementationsSwitcherModifier | `-frameForLayoutRole:inAppLayout:withBounds:` | 0x1c63df34c | 0x1c788a480 | PORTED already: 16.2 address cited in P1SW.m |
| SBDefaultImplementationsSwitcherModifier | `-scaleForLayoutRole:inAppLayout:` | 0x1c63df6b8 | 0x1c788a930 | PORTED already: 16.2 address cited in P1SW.m |
| SBDeveloperBuildExpirationTrigger | `-_coverSheetDidDismiss:` | 0x1c62e5c20 | 0x1c7781398 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBDeviceApplicationSceneView(ClassicSupport) | `-noteApplicationClassicPhoneSceneOrientationPreferenceChangingForUserAction:` | 0x1c62a4ca0 | 0x1c773ecdc | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView(ClassicSupport) | `-_createClassicWrapperViewIfNecessaryForHostView:` | 0x1c62a4da0 | 0x1c773ed90 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView(ClassicSupport) | `-_configureSceneLiveHostView:` | 0x1c62a4f24 | 0x1c773ef38 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView(ClassicSupport) | `-_invalidateSceneLiveHostView:` | 0x1c62a4fa0 | 0x1c773f00c | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDeviceApplicationSceneView(ClassicSupport) | `-_transitionViewForHostView` | 0x1c62a4fe4 | 0x1c773f080 | NOT PORTED: content / container orientation split of the scene view stack (contentOrientation + containerOrientation, needsCounterRotation overlay views, basic overlay wrapper in non rotating windows, delegate wired scene update transactions): CORE-LEFTOVERS 3b Tier B and G3B 1.5 / 1.6 / 1.7 (classes and adapters exist, the 16.0 rotation path stays authoritative) |
| SBDisplayManager(FBDisplayManager) | `-connectedIdentities` | 0x1c64d63ac | 0x1c79927a4 | TRIAGE PENDING |
| SBElasticHUDViewController | `-elasticValueViewControllerNeedsDismissal:` | 0x1c5f6f468 | 0x1c73e5d9c | IRRELEVANT: volume / brightness HUD live-rendering assertion (no window management) |
| SBElasticValueViewController | `-viewWillAppear:` | 0x1c60ccc74 | 0x1c7551428 | IRRELEVANT: volume / brightness HUD live-rendering assertion (no window management) |
| SBElasticValueViewController | `-viewDidMoveToWindow:shouldAppearOrDisappear:` | 0x1c60cce40 | 0x1c75515fc | IRRELEVANT: volume / brightness HUD live-rendering assertion (no window management) |
| SBElasticValueViewController | `-viewDidDisappear:` | 0x1c60cd0c8 | 0x1c755188c | IRRELEVANT: volume / brightness HUD live-rendering assertion (no window management) |
| SBElasticValueViewController | `-.cxx_destruct` | 0x1c60d75d8 | 0x1c755bf3c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBFocusModeAlwaysOnPolicy | `-activateAlwaysOnPolicy` | 0x1c633d224 | 0x1c77e12a4 | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBFocusModeAlwaysOnPolicy | `-_updateFromDNDState:` | 0x1c633d4b8 | 0x1c77e153c | IRRELEVANT: Always-On display (iPhone 14 Pro only) |
| SBLayoutState(SBAppLayoutConversion) | `-appLayout` | 0x1c5e2a6bc | 0x1c729cfa4 | TRIAGE PENDING |
| SBLockElementViewProvider | `-init` | 0x1c5f5fe90 | 0x1c73d5e80 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:` | 0x1c5f60414 | 0x1c73d6398 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-setAuthenticated:` | 0x1c5f604d4 | 0x1c73d6484 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-_updateLockLayout` | 0x1c5f605a8 | 0x1c73d6564 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-setBloomed:` | 0x1c5f60838 | 0x1c73d678c | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-handleBiometricEvent:` | 0x1c5f60864 | 0x1c73d67ac | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-_elementFrameLeading:forLayoutMode:` | 0x1c5f60a88 | 0x1c73d6990 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-leadingLock` | 0x1c5f60af4 | 0x1c73d6a00 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-sizeThatFitsSize:forProvidedView:inLayoutMode:` | 0x1c5f60db4 | 0x1c73d6cc4 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-_updateTrailingGlyph` | 0x1c5f61420 | 0x1c73d7308 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockElementViewProvider | `-.cxx_destruct` | 0x1c5f61628 | 0x1c73d7538 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBLockScreenManager | `-_lockUI` | 0x1c5e87c28 | 0x1c72fa758 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-lockUIFromSource:withOptions:completion:` | 0x1c5eb04d8 | 0x1c732321c | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-_authenticationStateChanged:` | 0x1c5eb3dac | 0x1c7326b5c | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-extendedKeybagLockStateChanged:` | 0x1c5eb3fd8 | 0x1c7326da0 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-init` | 0x1c64e0494 | 0x1c799cb98 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-_setSystemApertureProudLockElementVisible:backlightState:withReason:` | 0x1c64e211c | 0x1c799e9f0 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-_shouldBeShowingLockElementForBacklightState:` | 0x1c64e24dc | 0x1c799ee80 | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenManager | `-.cxx_destruct` | 0x1c64e66e4 | 0x1c79a3104 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBLockScreenPreviewView | `-_setupDateViewWithOptions:` | 0x1c619be90 | 0x1c762574c | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenPreviewView | `-_layoutDateView` | 0x1c619c4f0 | 0x1c7625e1c | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLockScreenPreviewView | `-.cxx_destruct` | 0x1c619c7fc | 0x1c7626188 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBLockScreenTemperatureWarningView | `-initWithFrame:` | 0x1c6343a34 | 0x1c77e82cc | IRRELEVANT: lock screen (embedded display only; no Stage Manager involvement) |
| SBLoginAppContainerViewController | `-_reallyAcquireStatusBarAssertionIfNecessaryInitiallyVisible:` | 0x1c633e790 | 0x1c77e28d8 | IRRELEVANT: boot / user switch login UI |
| SBLoginAppContainerViewController | `-_setupLoginScene` | 0x1c633e8a8 | 0x1c77e2a08 | IRRELEVANT: boot / user switch login UI |
| SBLoginAppSceneHoster | `-sceneDidInvalidate:` | 0x1c5ec2cc4 | 0x1c7335cb4 | IRRELEVANT: boot / user switch login UI |
| SBLowPowerAlertItem | `-_createSystemApertureElement` | 0x1c5fe9820 | 0x1c74643a8 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBMainDisplayLayoutState(SBDisplayItemConversion) | `-floatingItem` | 0x1c5fb746c | 0x1c742fa84 | TRIAGE PENDING |
| SBNotchedStatusBarProximityBacklightPolicy | `-dealloc` | 0x1c607fae0 | 0x1c7502c90 | IRRELEVANT: proximity sensor / notch (iPhone only) |
| SBNotchedStatusBarProximityBacklightPolicy | `-proximitySensorManager:objectWithinProximityDidChange:` | 0x1c607fcc8 | 0x1c7502d84 | IRRELEVANT: proximity sensor / notch (iPhone only) |
| SBNotchedStatusBarProximityBacklightPolicy | `-windowSceneDidConnect:` | 0x1c607fe80 | 0x1c7502f3c | IRRELEVANT: proximity sensor / notch (iPhone only) |
| SBNotchedStatusBarProximityBacklightPolicy | `-condition:enablementDidChange:` | 0x1c60800d4 | 0x1c750315c | IRRELEVANT: proximity sensor / notch (iPhone only) |
| SBNotchedStatusBarProximityBacklightPolicy | `-.cxx_destruct` | 0x1c6080420 | 0x1c750340c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBPBDisplayItemLayoutAttributes | `-dictionaryRepresentation` | 0x1c62f0840 | 0x1c778cfac | EXCLUDED: protobuf persistence class |
| SBPBDisplayItemLayoutAttributes | `-writeTo:` | 0x1c62f0fb8 | 0x1c778db80 | EXCLUDED: protobuf persistence class |
| SBPBDisplayItemLayoutAttributes | `-copyWithZone:` | 0x1c62f1174 | 0x1c778de2c | EXCLUDED: protobuf persistence class |
| SBPBDisplayItemLayoutAttributes | `-isEqual:` | 0x1c62f1238 | 0x1c778df50 | EXCLUDED: protobuf persistence class |
| SBPBDisplayItemLayoutAttributes | `-hash` | 0x1c62f1368 | 0x1c778e110 | EXCLUDED: protobuf persistence class |
| SBPIPContentViewLayoutMetrics(Pegasus) | `+videoContentLandscapeSizePreferences:portraitSizePreferences:squareSizePreferences:` | 0x1c5f6f834 | 0x1c73e6150 | TRIAGE PENDING |
| SBPIPContentViewLayoutMetrics(Pegasus) | `+videoCallLandscapeSizePreferences:portraitSizePreferences:squareSizePreferences:` | 0x1c5f6fc98 | 0x1c73e662c | TRIAGE PENDING |
| SBPIPContentViewLayoutMetrics(Pegasus) | `+microPIPLandscapeSizePreferences:portraitSizePreferences:squareSizePreferences:` | 0x1c5f701c0 | 0x1c73e6c08 | TRIAGE PENDING |
| SBPowerAlertElement | `-initWithIdentifier:style:batteryPercentage:lowPowerModeEnabled:action:` | 0x1c605c728 | 0x1c74db988 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBProximitySensorManager | `-initWithHIDInterface:hardwareDefaults:interfaceOrientationProvider:` | 0x1c6453c80 | 0x1c79084b0 | IRRELEVANT: proximity sensor / notch (iPhone only) |
| SBProximitySensorManager | `-processHIDEvent:` | 0x1c64541cc | 0x1c7908a10 | IRRELEVANT: proximity sensor / notch (iPhone only) |
| SBProximitySensorManager | `-.cxx_destruct` | 0x1c6454ca4 | 0x1c790977c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBRequestSystemApertureElementSuppressionEventResponse | `-descriptionBuilderWithMultilinePrefix:` | 0x1c6103c3c | 0x1c7589150 | EXCLUDED: description / debug text only |
| SBRestartManager | `-initializeAndRunStartupTransition:` | 0x1c640569c | 0x1c78b26d4 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBRestartManagerWorkspaceDataSource | `-activePrimaryApplicationBundleID` | 0x1c61627c4 | 0x1c75e9d10 | IRRELEVANT: no windowing / display behaviour (audio recording indicator telemetry, developer build, restart, power log, wake animation) |
| SBRingerAlertElement | `-initWithSource:ringerSilent:` | 0x1c6451578 | 0x1c7905830 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerAlertElement | `-isProvidedViewConcentric:inLayoutMode:` | 0x1c6451974 | 0x1c7905c24 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerAlertElement | `-_updateVolumeSliderAnimated:` | 0x1c6451e04 | 0x1c7906104 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerAlertElement | `-_updateStateWithTransitionType:` | 0x1c6451e3c | 0x1c7906190 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerAlertElement | `-_shakeRingerBell` | 0x1c64528ac | 0x1c79068dc | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerAlertElement | `-.cxx_destruct` | 0x1c6452b5c | 0x1c79074ec | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBRingerControl | `-activateRingerHUD:withInitialVolume:fromSource:` | 0x1c611bdd4 | 0x1c75a6048 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerVolumeSliderView | `-initWithFrame:` | 0x1c5ebdc68 | 0x1c7330ab8 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBRingerVolumeSliderView | `-layoutSubviews` | 0x1c5ebe14c | 0x1c7331010 | IRRELEVANT: ringer / power HUD elements of the Dynamic Island (iPhone only) |
| SBSOSClawGestureObserver | `-_initWithSOSManager:workspace:` | 0x1c5ffa884 | 0x1c74750f0 | IRRELEVANT: Emergency SOS button gesture (iPhone only) |
| SBSOSClawGestureObserver | `-noteButtonPress:isDown:` | 0x1c5ffa9e4 | 0x1c7475268 | IRRELEVANT: Emergency SOS button gesture (iPhone only) |
| SBSOSClawGestureObserver | `-.cxx_destruct` | 0x1c5ffb87c | 0x1c74763f0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSimScrollToIconTestRecipe | `-_simulateScrollToIconWithDisplayIdentifier:` | 0x1c630d128 | 0x1c77ab590 | IRRELEVANT: internal test recipes |
| SBSnapshotTestRecipe | `-_sendRequestWithType:` | 0x1c60b9b54 | 0x1c753e21c | IRRELEVANT: internal test recipes |
| SBSwitcherModifier(SharedModifierUtilities) | `-overlappingModelForAppLayout:` | 0x1c61c4450 | 0x1c7652fc4 | PORTED already: 16.2 address cited in G1C.x |
| SBSystemApertureCaptureVisibilityShimViewController | `-initWithContentViewController:` | 0x1c5f9abb0 | 0x1c74134a8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureCaptureVisibilityShimViewController | `-newDefaultVisibilityAnimator` | 0x1c5f9b014 | 0x1c7413920 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureCaptureVisibilityShimViewController | `-_updateClonedVisibility` | 0x1c5f9b10c | 0x1c7413a1c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureCaptureVisibilityShimViewController | `-_updateSnapshotVisibility` | 0x1c5f9b17c | 0x1c7413a4c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureCaptureVisibilityShimViewController | `-_updatePortalVisibility` | 0x1c5f9b248 | 0x1c7413af4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureCaptureVisibilityShimViewController | `-observeValueForKeyPath:ofObject:change:context:` | 0x1c5f9b324 | 0x1c7413bec | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-initIncludingSensorRegion:` | 0x1c5f6646c | 0x1c73dc5a4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-isContentClippingEnabled` | 0x1c5f66c68 | 0x1c73dcd68 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-setContentClippingEnabled:` | 0x1c5f66c6c | 0x1c73dcd78 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-interSensorRegion` | 0x1c5f66c70 | 0x1c73dce34 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-setKeyLineTintColor:` | 0x1c5f670a4 | 0x1c73dd3d0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-_layoutContentWithBounds:referenceSize:` | 0x1c5f673e4 | 0x1c73dd82c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-layoutSubviews` | 0x1c5f67610 | 0x1c73dda84 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-willMoveToSuperview:` | 0x1c5f67a44 | 0x1c73dde68 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-sb_setID0CornerRadius:` | 0x1c5f67b30 | 0x1c73ddf5c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-setElementViewController:` | 0x1c5f67d44 | 0x1c73de24c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-setElementOrientationAuthority:` | 0x1c5f67ec8 | 0x1c73de3cc | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-elementOrientationDidChangeWithTransitionCoordinator:` | 0x1c5f67fb4 | 0x1c73de454 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-settings:changedValueForKey:` | 0x1c5f6821c | 0x1c73de718 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-_applySettingsValues` | 0x1c5f68254 | 0x1c73de7a8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-backgroundLumaView:didTransitionToLevel:` | 0x1c5f68984 | 0x1c73ded80 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `+_defaultCornerRadiusForBounds:inWindow:` | 0x1c5f689f8 | 0x1c73def5c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-_cornerRadiusForFrame:` | 0x1c5f68a84 | 0x1c73defb4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-_updateKeyLineStyle` | 0x1c5f68e94 | 0x1c73df6e4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureContainerView | `-.cxx_destruct` | 0x1c5f69978 | 0x1c73e036c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemApertureController | `-initWithWindowScene:` | 0x1c65012b4 | 0x1c79be310 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-createHighLevelWindowSceneWithDisplayConfiguration:` | 0x1c6501374 | 0x1c79be634 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-createSuperHighLevelCurtainWindowSceneWithDisplayConfiguration:` | 0x1c6501470 | 0x1c79be6d4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-createHighLevelSystemApertureWindowWithWindowScene:` | 0x1c65018d8 | 0x1c79beae0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-createSuperHighLevelCurtainWithWindowScene:` | 0x1c6501c98 | 0x1c79beef0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-systemApertureViewController:containsAnyContent:` | 0x1c6501f0c | 0x1c79bf424 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-_configureLegacyStatusBarPillElementProviderIfNecessary` | 0x1c6502834 | 0x1c79bfc80 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureController | `-.cxx_destruct` | 0x1c65028ec | 0x1c79bfd44 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemApertureController(Test) | `-stateDump` | 0x1c65029b4 | 0x1c79bfe30 | TRIAGE PENDING |
| SBSystemApertureElementAuthority | `-elementsOrderedByPromotionFromTemporallyOrderedElements:withPreviousOrdering:` | 0x1c6292a0c | 0x1c772c024 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemAperturePresentableManager | `-_invalidateElement:withReason:` | 0x1c5f92d1c | 0x1c740a5e8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemAperturePresentableManager | `-_noteElementDidInvalidate:reason:` | 0x1c5f93248 | 0x1c740ab28 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureProximityBacklightPolicy | `-proximitySensorManager:objectWithinProximityDidChange:` | 0x1c640d3dc | 0x1c78ba96c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureProximityBacklightPolicy | `-_scheduleBacklightFactorToZeroForTouchWithinSystemAperture` | 0x1c640dc84 | 0x1c78bb46c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureProximityBacklightPolicy | `-.cxx_destruct` | 0x1c640dde0 | 0x1c78bb5f0 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemApertureSceneElement | `-initWithScene:statusBarStyleOverridesSuppresser:readyForPresentationHandler:` | 0x1c645dcac | 0x1c79112f0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-invalidate` | 0x1c645e134 | 0x1c791177c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-dealloc` | 0x1c645e35c | 0x1c79119d0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-activateWithInitialOtherClientSettings:transitionRequestHandler:` | 0x1c645e40c | 0x1c7911b9c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_handleAlertingAssertionRequest` | 0x1c645ea24 | 0x1c7912540 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-setActivated:` | 0x1c645f198 | 0x1c7912cc0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-handleElementViewEvent:` | 0x1c645f1d4 | 0x1c7912ce0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_activateCorrespondingAppSceneIfPossible` | 0x1c645f2e0 | 0x1c7912f40 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-setReadyForPresentation:` | 0x1c645fcc4 | 0x1c7913920 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-setLayoutHost:` | 0x1c6463d00 | 0x1c79139b4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-setLayoutMode:reason:` | 0x1c645fd54 | 0x1c7913a34 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_isAssociatedWithBundleIdentifier:` | 0x1c6460194 | 0x1c7913e98 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_isAssociatedWithSceneWithPersistenceIdentifier:` | 0x1c64601fc | 0x1c7913f40 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-shouldSuppressElementWhilePresentingAppWithBundleId:` | 0x1c64603c8 | 0x1c7914154 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_calculateRequiresSuppressionFromSystemAperture` | 0x1c6460478 | 0x1c79142b4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-setAlerting:` | 0x1c6460a4c | 0x1c7914950 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-isRequestingLayoutUpdateForHostedClient` | 0x1c6460bac | 0x1c7914de0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` | 0x1c6460de0 | 0x1c7915578 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-sceneContentStateDidChange:` | 0x1c64615f0 | 0x1c7915c8c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_handleAction:` | 0x1c64616c0 | 0x1c7915d90 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_obstructedAreaFrame` | 0x1c6461aa4 | 0x1c79161f0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-contentProviderWillTransitionToSize:inContainerView:transitionCoordinator:` | 0x1c6461f48 | 0x1c79168d4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_sizeForSceneView` | 0x1c64627b4 | 0x1c7917290 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_updateReasonsForTransitionWithProposedParameters:excludingReasons:` | 0x1c64628fc | 0x1c7917350 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_proposeTransitionParametersForTransitionToFrameInSceneView:excludingParametersAssociatedWithReasons:usingCurrentAnimationParameters:` | 0x1c6462d84 | 0x1c7917840 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:` | 0x1c646306c | 0x1c7917c58 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-sizeThatFitsSize:forProvidedView:inLayoutMode:` | 0x1c6463170 | 0x1c7917d50 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_updateSceneWithTransitionParameters:` | 0x1c6463240 | 0x1c7917e44 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_updateMutableSceneSettings:withParameters:` | 0x1c64633e8 | 0x1c79182a4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_updateReadyForPresentationIfNeeded` | 0x1c64634ec | 0x1c79183b0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-_acquireOrUpdateAppStatusBarSessionsAssertionIfNeeded` | 0x1c64635d0 | 0x1c7918460 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSceneElement | `-.cxx_destruct` | 0x1c6463f00 | 0x1c7919110 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemApertureSettings | `-setDefaultValues` | 0x1c63c6d98 | 0x1c78720ec | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureSettings | `+settingsControllerModule` | 0x1c63c8258 | 0x1c78736ac | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElement | `-leadingView` | 0x1c61b453c | 0x1c76421f0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElement | `-activeTintColor` | 0x1c61b4854 | 0x1c7642938 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElement | `-activeSymbolName` | 0x1c61b4bec | 0x1c7642cd8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElement | `-.cxx_destruct` | 0x1c61b4e30 | 0x1c7642fa8 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemApertureStatusBarPillElementProvider | `-init` | 0x1c62e0a74 | 0x1c777b52c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElementProvider | `-invalidate` | 0x1c62e0ff8 | 0x1c777bf1c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElementProvider | `-setCurrentStyleOverrides:` | 0x1c62e128c | 0x1c777c758 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElementProvider | `-_updateActiveElementIfNeededForReason:` | 0x1c62e1360 | 0x1c777c9cc | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElementProvider | `-_updateActiveElementIfNeededWithLayoutState:reason:` | 0x1c62e14f4 | 0x1c777d1c0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureStatusBarPillElementProvider | `-.cxx_destruct` | 0x1c62e200c | 0x1c777d770 | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemApertureViewController | `-initWithWindowScene:` | 0x1c62036a4 | 0x1c76924d8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-minimumSensorRegionFrame` | 0x1c6203bec | 0x1c7692a38 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-isTransitionTargetForSceneIdentifier:bundleIdentifier:` | 0x1c6203d30 | 0x1c7692ba8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_animateNegativeResponseForElement:` | 0x1c6204188 | 0x1c7693054 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_triggerBounceAcceptResponse:triggeredBlock:` | 0x1c620503c | 0x1c7693fb4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-viewDidLoad` | 0x1c6205ea4 | 0x1c7694e6c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_indicatorContainerViewFrameInBounds:` | 0x1c6206494 | 0x1c76952b0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-viewWillLayoutSubviews` | 0x1c620659c | 0x1c76953d0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-viewDidLayoutSubviews` | 0x1c62068b8 | 0x1c7695768 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_updateKeyLineStyle` | 0x1c6206ee0 | 0x1c7695d3c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_updateRenderingStyle` | 0x1c62070d8 | 0x1c7695f1c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_updateElementViewControllerReferences:` | 0x1c6207cc8 | 0x1c7696bac | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_cleanupAfterLayout` | 0x1c62090b8 | 0x1c7697e7c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_shadowStyleForContainerView:targetingInert:frame:` | 0x1c620955c | 0x1c76984a8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_beginTargetingInertStateIfNecessaryWithOrderedElementViewControllers:` | 0x1c6209d80 | 0x1c7698cc0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_updateElementViewControllersAndPerformLayout` | 0x1c620a3f4 | 0x1c7699400 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_maximumContainerViewOutsetsInBounds:inLayoutMode:` | 0x1c620aa00 | 0x1c7699af0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_adjunctContainerMinimalViewSize` | 0x1c620ab24 | 0x1c7699c38 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_frameForSensorRegionInBounds:` | 0x1c620ab48 | 0x1c7699c7c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_viewScaleForOvershoot` | 0x1c620ad54 | 0x1c7699ea0 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_frameForContainerView:` | 0x1c620b610 | 0x1c769a790 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_updateVariableBlurVisibility` | 0x1c620bda0 | 0x1c769af24 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_shouldSuppressElement:allowsSuppressionForSystemChromeSuppression:` | 0x1c620cd14 | 0x1c769be98 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-preferredEdgeOutsetsForLayoutMode:suggestedOutsets:maximumOutsets:forTargetWithOverrider:isDefaultValue:` | 0x1c620d80c | 0x1c769c9bc | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-edgeOutsetsForSize:` | 0x1c620dfd0 | 0x1c769d1cc | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-interSensorRegionInContentView:` | 0x1c620e0d0 | 0x1c769d2e8 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-concentricPaddingForProvidedView:fromViewProvider:` | 0x1c620e144 | 0x1c769d368 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_containerViewWithRank:creatingIfNecessary:` | 0x1c620e964 | 0x1c769de44 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-systemApertureContainerView:cornerRadiusWithSuggestion:` | 0x1c620ef10 | 0x1c769e418 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-systemApertureContainerView:sampledLuminanceLevelChangedTo:` | 0x1c620eff0 | 0x1c769e4ec | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_isSystemGesture:` | 0x1c620f32c | 0x1c769ee58 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_containerViewForTouch:ofGestureRecognizer:initialLocation:` | 0x1c620f434 | 0x1c769ef14 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-gestureRecognizer:shouldReceiveTouch:` | 0x1c620f5d4 | 0x1c769f0ec | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_isAnyGestureRecognizerActive` | 0x1c620f8a0 | 0x1c769f33c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_frameForContainerView:resizedWithGesture:initialLocationInContainerView:initialContainerViewFrame:` | 0x1c620f9e8 | 0x1c769f484 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_didContainerViewForActiveGestureCollapseWithFrame:` | 0x1c620fd7c | 0x1c769fa54 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_handleResizePan:` | 0x1c620fe38 | 0x1c769fc14 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_interactionLongPressTimerDidEnd:` | 0x1c6210de8 | 0x1c76a1000 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_handleInteractionLongPress:` | 0x1c6210ee8 | 0x1c76a1178 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_axRegisterForZoomUpdatesIfNecessary` | 0x1c6211ab0 | 0x1c76a1d8c | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_newContainerViewHousingSensorRegion:` | 0x1c6211e30 | 0x1c76a2468 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-_updateStatusBarAvoidanceFrameWithAnimationSettings:` | 0x1c6212060 | 0x1c76a26ac | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| SBSystemApertureViewController | `-.cxx_destruct` | 0x1c6212b38 | 0x1c76a326c | EXCLUDED: ivar teardown only (.cxx_destruct) |
| SBSystemServiceServer | `-noteDidReceiveMessage:withType:fromClient:` | 0x1c62f91d0 | 0x1c77964d0 | TRIAGE PENDING |
| SBUIController(SBUIAnimationController) | `+statusBarFrameForDeviceApplicationSceneHandle:displayConfiguration:interfaceOrientation:statusBarStyleRequest:withinBounds:inReferenceSpace:` | 0x1c63166d8 | 0x1c77b523c | TRIAGE PENDING |
| SBUIStartupFromBlackAnimationController | `-_prepareAnimation` | 0x1c6388af8 | 0x1c78317e8 | IRRELEVANT: boot / user switch login UI |
| SBUIStartupFromOverlayAnimationController | `-_prepareAnimation` | 0x1c5f64a0c | 0x1c73da9b0 | IRRELEVANT: boot / user switch login UI |
| SBUIStartupToUserSetupAppZoomInAnimationController | `-_prepareAnimation` | 0x1c5f6d59c | 0x1c73e3e1c | IRRELEVANT: boot / user switch login UI |
| SBVolumeControl | `-_isHUDDisplayableWithReason:` | 0x1c5f62a94 | 0x1c73d8990 | IRRELEVANT: volume HUD backlight gating (iPhone always-on) |
| SBWindowSceneStatusBarAssertionManager(FrontmostStatusBarVisibility) | `-isFrontmostStatusBarPartHidden:` | 0x1c63f8584 | 0x1c78a5064 | PORTED already: 16.2 address cited in G3B.x |
| SBiPadOSPlatformSwitcherModifier | `-handleTransitionEvent:` | 0x1c611cd74 | 0x1c75a6fac | PORTED already: hook in G1B.x:1885 |
| SBiPadOSPlatformSwitcherModifier | `-handleUpdateWindowingModeEvent:` | 0x1c611d0bc | 0x1c75a73c4 | PORTED already: hook in G1B.x:1903 |
| _SBHomeScreenFloorSwitcherModifier | `-handleTransitionEvent:` | 0x1c60890fc | 0x1c750c194 | PORTED already: hook in G1B.x:2604 |
| _SBProximityTouchHandlingView | `-hitTest:withEvent:` | 0x1c607f634 | 0x1c780a170 | IRRELEVANT: proximity sensor / notch (iPhone only) |
| _SBProximityTouchHandlingViewController | `-loadView` | 0x1c607f998 | 0x1c780a514 | IRRELEVANT: proximity sensor / notch (iPhone only) |
| _SBSystemApertureGainMapView | `-initWithFrame:` | 0x1c5f69c34 | 0x1c73e06c4 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| _SBSystemApertureLayoutState | `-systemApertureLayoutStateByIncrementingPhase` | 0x1c62143c8 | 0x1c76a4c84 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| _SBSystemApertureMagiciansCurtainView | `-sizeThatFits:` | 0x1c5f6a208 | 0x1c73e0d04 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |
| _SBSystemApertureMagiciansCurtainView | `-layoutSubviews` | 0x1c5f6a214 | 0x1c73e0d54 | IRRELEVANT: Dynamic Island / system aperture (iPhone 14 Pro hardware only; iPad has no aperture) |

