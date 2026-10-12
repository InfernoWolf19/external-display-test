# PORT-G1D-0.7.0: coordinator, gesture manager, view controller side and PIP morph of 16.2 in `G1D.x`

16.0 = 20A8372, 16.2 = 20C65. All addresses are unslid dyld shared cache addresses of SpringBoard. Static analysis only (no device): every method was decoded in both builds
and compared by selector sequence / listing; `G1D.x` passes `logos.pl` and a clang `-fsyntax-only -fobjc-arc` check against stub headers.

Everything is default-on. Kill switches (`Backport162.off.<name>`): `g1d` (whole file) and `g1d_model`, `g1d_request`, `g1d_removal`, `g1d_newwindow`, `g1d_gesture`,
`g1d_vcdrag`, `g1d_pointer`, `g1d_tongue`, `g1d_gmtouch`, `g1d_pip`, `g1d_pipframes`, `g1d_piprestore`, `g1d_pipkeyboard`, `g1d_pipinsets`, `g1d_extgestures`.

Wiring (lead): add `G1D.x` to the Makefile, declare `void G1D_Setup(void);` in `Tweak.x` and call it AFTER `G1B_Setup()`, `BP2B_Setup()` and `G1C_Setup()` (it relies on the
accessors G1B adds for the strip tongue and on `didSelectContainer:modifierFlags:` from G2B; every use re-checks `respondsToSelector:` so an earlier call only loses features).

## 1. Fallbacks / stand-ins found in the existing code and what replaced them (14)
1. `-_adjustedGestureEventForGestureEvent:fromGestureManager:` (G2B.m stand-in): ignored the manager and passed `me`, so a window drag over a second display was never converted
   into the coordinates of the switcher that handles it. Replaced by the 16.2 body (section 2.3).
2. `draggingAppLayoutsForContinuousExposeWindowDrag` / `proposedAppLayoutsForContinuousExposeWindowDrag` (G2.x stubs): answered for the one display. Real coordinator state (2.2).
3. G1C's private `kReqActItem` associated key for `activatingDisplayItem` on `SBSwitcherTransitionRequest`: G1D adds the real accessors (`activatingDisplayItem` / `setActivatingDisplayItem:`)
   and the coordinator code that consumes them (1.4). G1C's key can be deleted.
4. G1B's `presentContinuousExposeStripRevealGrabberTongueImmediately` / `tickle...` were no-ops (no tongue existed): the tongue now exists (section 4).
5. Missing VC methods `presentContinuousExposeStripEdgeProtectTongue` / `dismiss...` (G2B only tested `respondsToSelector:`): provided (4.4).
6. Missing producer of `morphingPIPLayoutRole` / `morphFromPIPTransition` on the transition event (G1C item 3 of its open list): produced by the coordinator (6.1).
7. The `SBSwitcherController` window-management-style callbacks `switcherControllerWill/DidUpdateWindowManagementStyle:` (G3 listed the Did callback as CANNOT): ported with the coordinator ivars as associated state (1.1, 1.5).
8. Strip reveal: 16.0 only had the pointer recognizer; touch reveal, edge protect tongue and the 16.2 availability rules did not exist (section 4).
9. Overflow strip recognizers: 16.0 consulted the MAIN display gesture manager / main window scene attributes and lacked the `hidden` half of the availability (4.3).
10. `-_gestureTypeForGestureRecognizer:` NSAsserts for any recognizer it does not know: the tongue's two recognizers would have crashed it (4.2).
11. Live resize, tap-to-bring-forward: judged by `[SBMainDisplaySystemGestureManager sharedInstance]` / `_SBIsMainDisplaySystemGestureAllowed` (4.5).
12. PIP morph: the VC never passed appLayout / layoutRole / appLayoutBoundingBox, the data source used window frames converted by the animator, no per-display request for the
    PIP restore and no per-display environment mode (section 6).
13. `isEdgeProtectedForHomeGestureAtEdgeLocation:` was bottom edge only and ignored occluded windows (4.4).
14. External display gesture manager did not arm the 16.2 transient UI types 0x1e-0x21 (4.6).

## 2. PORTED: coordinator and cross display window drag
### 2.1 Model (`g1d_model`)
`SBMainSwitcherControllerCoordinator` 16.2 `-appLayoutsForSwitcherController:` 0x1c76e2354 (16.0 0x1c624d488), `-_rebuildAppListCache` 0x1c76dba90,
`-_rebuildCurrentWindowingModeCompatibleAppLayoutsIfNecessary` 0x1c76db498 (block 0x1c76db5f8), `-_buildAppLayoutCache` 0x1c76da530 (16.0 0x1c6245ff0: the only delta is stripping the
first model layout's items from the other main layouts), new `enumerateSwitcherControllersWithBlock:` 0x1c76e2214, `convertAppLayout:fromSwitcherController:toSwitcherController:` 0x1c76e2b1c,
`switcherControllerForAppLayout:` 0x1c76e291c, `draggingAppLayouts` 0x1c76e2df8, `switcherControllerWill/DidUpdateWindowManagementStyle:` 0x1c76e2bbc / 0x1c76e2bc8.
16.2 ivars that 16.0 lacks (`_currentWindowingModeCompatibleAppLayoutsByWindowScene` +0x18, `_draggingAppLayouts` +0x40) are associated objects. The Stage Manager list is
`+_filterAppLayoutForChamois:` (G1B, re-verified against 0x1c76db2b8, no duplicate added), the Medusa list `appLayoutsBySplittingMedusaIncompatibleItemsWithApplicationController:`.
`SBFIsChamoisWindowingUIAvailable` (16.2 only) is answered with `SBFFeatureFlagsIsChamoisWindowingUIEnabled` (same flag, 16.0 name).
### 2.2 Gesture begin / update / end broadcast and the drag state (`g1d_gesture`, `g1d_vcdrag`)
Coordinator `fluidSwitcherGestureManager:didBegin/Update/EndGesture:` 0x1c76d79e4 / 0x1c76d7ba8 / 0x1c76d7d18: broadcast to every switcher controller (origin controller always,
others only for gesture type 9 with the same window management style); begin/end add/remove the selected layout in `_draggingAppLayouts` and rebuild the list cache.
`SBSwitcherController fluidSwitcherGestureManager:didBegin/Update/EndGesture:` 0x1c76070cc / 0x1c7607148 / 0x1c76071c4 forward to the VC (the window drag begin/platterize/willEnd
methods 0x1c7607240.. are bare `ret`). VC `draggingAppLayoutsForContinuousExposeWindowDrag` 0x1c74388d8 = `[[[vc switcherController] switcherCoordinator] draggingAppLayouts]`,
`proposedAppLayoutsForContinuousExposeWindowDrag` 0x1c7438944 collects each controller's root modifier proposal over `enumerateSwitcherControllersWithBlock:`.
### 2.3 VC handlers
`handleFluidSwitcherGestureManager:didBegin/Update/EndGesture:` 0x1c7438ad0 / 0x1c7439048 / 0x1c7439258 = the 16.0 `handleGestureDid*` bodies plus the assertion, dispatching
`_adjustedGestureEventForGestureEvent:fromGestureManager:` (= `[self _convertContinuousExposeWindowDragEvent:event fromSwitcherContentViewController:[[manager switcherController] contentViewController]]`
for window drag events). The 16.0 handlers run with `-[SBFluidSwitcherGesture gestureEvent]` answering the adjusted event (thread local).
### 2.4 Request / removal / new window / transition end
* `-_configureRequest:forSwitcherTransitionRequest:withEventLabel:` 0x1c76d174c (16.0 0x1c623e164): Stage Manager env 2 layout converted to env 1, `activatingDisplayItem` handling
  (home item -> home entity, contained item -> `_entityForDisplayItem:sceneHandleProvider:displayIdentity:`, `setActivatingEntity:`, completion `userFocusRequestForScene:reason:@"SwitcherTransitionRequest"`) (`g1d_request`).
* `-_switcherModelRemovalResultsForRequest:forReason:` 0x1c76e0660 (16.0 0x1c624b4b0): 16.2 reads `_currentMainAppLayout` / `_currentFloatingAppLayout` of the switcher controller OF EACH
  removed layout; 16.0 read the coordinator's (= the active display's). This is the cause of the close-window-on-extended-display icon overlay assertion (`g1d_removal`).
* `-switcherContentController:requestNewWindowForBundleIdentifier:` 0x1c76d5ce0: entity from the controller's scene manager and display identity,
  `requestTransitionWithOptions:displayConfiguration:builder:` instead of the main display builder (`g1d_newwindow`).
* `-layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` 0x1c76cb178 (16.0 0x1c6237d6c): the mode 1 -> 3 add checks the preferredDisplayOrdinal of the model layout
  that contains each item (`g1d_model`). The 16.2 error branch `[provider setPreviousLayoutState:]` is not ported (no 16.0 provider API).
* `windowSceneDidConnect:` runs `Did` right before `setupSwitcherWindowIfNeeded`; `-[SBSwitcherController setChamoisWindowingUIEnabled:]` runs `Will` then (inside
  `-[SBFluidSwitcherGestureManager updateForChamoisWindowingUIEnabled:]`) `Did`. G3.x's direct `failMultitaskingGesturesForReason` call equals the body of `Will`.

## 3. PORTED: pointer crossing the display boundary (`g1d_pointer`)
VC `pointerDidMoveToFromWindowScene:toWindowScene:` 0x1c745f938 builds `SBPointerCrossedDisplayBoundarySwitcherModifierEvent(direction, edge)`: direction 1 when this display is the
`from` scene, 0 when it is the `to` scene; edge from `-[SBExternalDisplayService preferredArrangementOfDisplay:relativeTo:]` (G4B.x) of the OTHER display. 16.2 registers the VC as an
observer of `SBSystemPointerInteractionManager` (0x1c743475c, removed in `invalidate` 0x1c743be28); 16.0 has no such class, so the VC registers with the multi display coordinator of
Group4Focus.x (`multiDisplayUserInteractionCoordinator` `add/removePointerInteractionObserver:`) which reports the same transition (16.2 `-_pointerMovedInScene:` 0x1c795e838).

## 4. PORTED: continuous expose strip reveal grabber tongue (`g1d_tongue`)
16.2 replaces the pointer-only `indirectRevealContinuousExposeStripsGestureRecognizer` (16.0 ivar +0x138) with `SBGrabberTongue` type 0x37, edge `-_continuousExposeStripEdge`
(0x1c78fbe50: RTL 8, else 2), name `ContinuousExposeStripRevealGrabberTongue`, that owns a touch `SBScreenEdgePanGestureRecognizer` and a pointer `SBIndirectPanGestureRecognizer`
(system gesture 0x34). The 16.0 SBGrabberTongue speaks the same delegate protocol; it only lacks `name` and `screenEdge` (added). The tongue is kept in the associated slot G1B created
(`continuousExposeStripRevealGrabberTongue`).
### 4.1 Configure / enable
`_configureChamoisGestureRecognizersIfNeeded` 0x1c78f0c08 (16.0 0x1c643eea4): the 16.0 body runs, the (never registered) reveal recognizer is dropped and the tongue created.
`updateForChamoisWindowingUIEnabled:` 0x1c78f0fe8 (16.0 0x1c643f408) is replaced: registers live resize 0x22, hover 0x33, indirect overflow 0x35, drag overflow 0x36, installs the tongue
in the VC view (`installInView:withColorStyle:0`) and makes the indirect overflow recognizer wait for the tongue's indirect recognizer; disable removes them and `uninstall`s the tongue.
`invalidate` also invalidates the tongue (0x1c78f179c). `SBMainDisplaySystemGestureManager _shouldEnableSystemGestureWithType:` 0x37 behaves like 0x33 (16.2 jump table case of
0x1c72e9590; 16.0 0x37 is unused; types below 0x37 keep their numbers, the 16.2 numbering of later types is shifted by one).
### 4.2 Delegate methods (strip branches, everything else `%orig`)
`customGestureRecognizerForGrabberTongue:` 0x1c78fa7e8 (touch edge pan, allowed touch types @[@0]), `indirectPanGestureRecognizerForGrabberTongue:` 0x1c78faa00 (+ translation adjustment
block 0x1c78faca0: `x' = (loc.x >= w/2 ? max : min)(x - |y|, 0)`; the 16.0 long init with the scene's system gesture manager), `indirectPanSystemGestureTypeForGrabberTongue:` 0x34,
`shouldSuppressTongueViewForGrabberTongue:` YES, `grabberTongueOrPullEnabled:forGestureRecognizer:`, `_grabberTongueForGestureRecognizer:`, `grabberTongue:shouldReceiveTouch:` 0x1c72c4d40,
`...shouldShowTongueOnFirstSwipeWithEdgeLocation:` 0x1c72c90ac (window flush with the strip edge whose app defers system gestures on that edge), `...shouldAllowSecondSwipe...` 0x1c72ca7a0,
`grabberTongueBegan/Updated/Ended/CanceledPulling:` -> `_handleContinuousExposeStripRevealGesture:` 0x1c78f27e8, `WillPresent` / `WillDismiss` -> VC
`presentContinuousExposeStripEdgeProtectTongue` / `dismiss...` (0x1c744f4e0 / 0x1c744f540, dispatch `SBContinuousExposeStripEdgeProtectTongueSwitcherModifierEvent`),
`_gestureTypeForGestureRecognizer:` 0xb for both recognizers (0x1c72cad14; 16.0 would NSAssert).
### 4.3 Availability
`_areContinuousExposeStripsAvailableWithReason:` 0x1c78fba84 (adds `alwaysMaximizedInChamois`), `_areContinuousExposeStripsOccludedOrHiddenWithOutReason:` 0x1c78fbc38
(`overlappingModelForAppLayout:...` of `_displayItemLayoutAttributesCalculator`), reveal = available && occludedOrHidden (0x1c78f95c4), overflow = available && !occludedOrHidden (0x1c78f9738,
hooks the 16.0 `_shouldBeginReveal...OverflowGesture:`), drag overflow touch rule 0x1c78f5ef0 (per display gesture manager, `isGestureWithTypeAllowed:0x36`, VC `chamoisLayoutAttributes`).
### 4.4 VC edge protection
`isEdgeProtectedForHomeGestureAtEdgeLocation:edge:` 0x1c744c954 (16.0 1-argument form 0x1c5fd3a74 = bottom only): skips containers occluded in the stage, requires the container to touch the
asked edge of `containerViewBounds`, all four edges. The 16.0 selector forwards with edge 4. `_shouldProtectEdgeLocation:edge:` 0x1c78f9a5c is a local function.
### 4.5 Per display touch rules (`g1d_gmtouch`)
`_shouldLiveResizeGesture:receiveTouch:` 0x1c78f5920, `_shouldTapToBringItemContainerForward:receiveTouch:` 0x1c78f5ac0 (+ `item != frontmost item`), `_shouldBeginTapToBringItemContainerForwardGesture:`
0x1c78f7064 (+ no icon context menu), `_handleTapToBringItemContainerForward:` 0x1c78f2690 (command-modified taps are forwarded) and VC `handleTapToBringItemContainerForward:` 0x1c7439690
(passes `[gesture modifierFlags]` to `didSelectContainer:modifierFlags:`, no explicit keyboard focus move). `_SBIsSystemGestureAllowed(windowScene, type)` 0x1c74d1424 is a local function.
### 4.6 `g1d_extgestures`
`SBExternalDisplaySystemGestureManager` 0x1c780bf58 arms 0x1e-0x21 in addition to the 16.0 set (`SBTransientUIInteractionManager` tap-to-dismiss / indirect pan / tap-to-unhide); 0x43 is the
renumbered 0x42 that Tweak.x already enables.

## 5. Verified equivalent, deliberately NOT ported
* `_shouldLiveResizeItemContainerGestureWithPointer:receiveTouch:` (log only), `...WithTouch:receiveTouch:` (16.0 asks the VC's own window scene for the attributes 16.2 reads from
  `-chamoisLayoutAttributes`), `_shouldBeginHoverGesture:`, `gestureRecognizer:shouldReceiveTouch:` (dispatch shape only), `initWithSwitcherController:delegate:`, `setActiveGestureTransaction:`,
  `_updateSwitcherBottomEdgeGesturePresence`, `_configureTapToBringItemContainerForwardGesture` (16.2 only gates it on `SBFIsChamoisWindowingUIAvailable`, which is true on every Stage Manager device).
* Coordinator tap/click delegate methods (16.2 only broadcasts to the controllers; same effect as 16.0's `_switcherControllerForGestureManager:`).
* SBGrabberTongue `_createTongueAndGestureRecognizersIfNecessaryWithColorStyle:` / `uninstall` / `_handlePullGesture:`: 16.2 uses `name` for recognizer names and drops the main display manager
  fallback (the tongue always has a window scene here).
* Medusa only (Slide Over / Split View, never active on an external display): `_shouldFloatingApplicationMoveGesture:/PinGesture:receiveTouch:` (16.2 asks the scene's manager), `_shouldSplitView
  ApplicationUnpinGesture:receiveTouch:` (0x1c78f46e8, 138 vs 57 instructions: the Stage Manager hit region of the nub, `initialTouchLeafAppLayout`), `_shouldBeginSplitViewApplicationUnpinGesture:`,
  `_shouldAllowFloatingApplicationGesture:...`, `_configureFloatingApplicationGestureRecognizers` (names, one more registration). They keep the 16.0 behaviour on the iPad display.
* System Aperture / scene backed banners (iPhone only or 16.2 only): `_updateSystemApertureZStackPolicyAssistantWithLayoutState:`, `bannerManager:will(Present|Dismiss)...`, `presentedSceneBackedBanners`
  (the tap-to-bring-forward test also looks at the banner count; with no banner feature the count is always 0).
* `SBPIPController`: `_acquireStashAssertion...`, `_createNewWindowForContainerViewController:onWindowScene:`, `_setAdapter:`, `updateZStackParticipantPreferencesIfNeeded:windowScene:` (identical),
  `containerViewController:userDidUpdateStashState:` (resource usage timeout override), `_moveContext:toWindowScene:` (off screen hyperregions), `homeScreenInitialPIPFrame...` (logging),
  `_updateZStackIfNeededForDisappearingContainerViewController:` (System Aperture).

## 6. PORTED: PIP morph (view controller, controller, data source, animator)
### 6.1 Producer (`g1d_pip`)
`_shouldMorphFromPIPForTransitionContext:outForLayoutRole:` 0x1c76d50e0 (`source == 0x2d`, role = layoutRole of `requestedActivatingWorkspaceEntity`), `_shouldMorphToPIPForTransitionContext:
outForLayoutRole:` 0x1c76d4ea0 (16.0 conditions + `shouldAutoPIPEnteringBackgroundForRequest:foundEntity:transitionStyle:`), `transitionEventForContext:` 0x1c76d3e1c (from check first; `setMorphFromPIPTransition:`,
`setMorphingPIPLayoutRole:`).
### 6.2 View controller
`_performEventResponse:` for `SBSetupPIPMorphingSwitcherEventResponse` (0x1c745b920) -> `_setupPIPMorphingIfNeededForTransitionContext:response:` 0x1c745a944 which differs from the 16.0
`_setupMorphToPIPIfNeededForTransitionContext:` (0x1c5fe130c) only by `appLayoutBoundingBox`. The 16.0 `_setupMorphAnimatorIfNeededForEntity:...uniqueID:direction:gestureInitiated:` (0x1c5fe0e6c) keeps its
body; appLayout, layoutRole (`layoutRoleForItem:` of the entity's item, block 0x1c745a8d0) and the box wait in thread local state and are handed to the `SBPIPMorphAnimatorController` the moment
`SBPIPController` creates it (`createAndRegister...` 0x1c792d744 in 16.2) or looks it up, i.e. before `noteSourceAnimationsWillStart:` (new properties 0x1c78c0b2c..0x1c78c0b5c as associated state).
### 6.3 Data source / controller / animator (`g1d_pipframes`)
`SBPIPMorphAnimatorDataSource`: `sourceContentContainerFrameForAnimator:` 0x1c783031c (item frame in the main layout of the display via `frameForItemWithRole:inMainAppLayout:interfaceOrientation:`
minus the box origin; replaces `sourceAppLayoutFrameForAnimator:` 0x1c60b7e50), `sourceContentFrameForAnimator:` 0x1c782fdc0 (fit into the container, no landscape swap, initial frame cached per morph uuid),
`sourceSubviewFrame:inScreenSpaceForAnimator:` 0x1c7830450, `shouldProvideSourceClippingFrameInFixedCoordinateSpace:` 0x1c782fda4, `sourceBlackCurtainCornerRadiusForAnimator:` 0x1c78307f8 (Stage Manager branch).
`SBPIPMorphAnimatorController willRemoveTargeMatchMoveAnimationAtFrame:withinSourceFrame:` 0x1c78c09c0 converts both frames to screen space. `SBViewMorphAnimator`: the 16.0 helpers
`_sourceContentFrameForSourceView:withTargetDataSource:` / `_sourceAppLayoutFrameForSourceView:withTargetDataSource:` return the data source frames as they are (inset -1,-1 for the container, 0x1c7681eac)
and `_checkAnimationsDependencies:` 0x1c7683580 re-parents the black curtain keeping its frame. `targetFinalFrameForAnimator:` and `_source:finalCenterWithFinalScale:...` only gained logging.
### 6.4 SBPIPController per display (`g1d_piprestore`, `g1d_pipkeyboard`, `g1d_pipinsets`)
`restoreContentViewController:appSceneEntity:morphAnimatorConfigurationBlock:completion:` 0x1c792a2a4 creates the restore request with `createRequestWithOptions:displayConfiguration:` of the PIP scene's
display; `keyboardFocusController:externalSceneDidAcquireFocus:` 0x1c792efa4 remembers the environment mode of the scene's own switcher controller; `_updatePictureInPictureOverlayInsetsOnWindowScene:...`
0x1c792dd08 asks the scene's switcher controller (the Spotlight predicate only matters for non iPad idioms).

## 7. CANNOT (precise reason)
* The lost window drag end across displays (log: first type 9 drag starts on display A, pointer moves to display B "re-setting pointer touch down window scene", touch up happens on B, the drag
  transaction ends only 12 ms after the pointer returns to A; in the next drag the stale `BP162ContinuousExposeWindowDragRootSwitcherModifier` makes `addChildModifier:... key 'Gesture'` assert).
  `SBFluidSwitcherDragAndDropManager`, `SBWindowDragInteraction` are byte identical in 16.0 and 16.2, `SBDragAndDropWorkspaceTransaction` differs only in geometry, and the only 16.2 consumer of
  `activeTouchDownOriginatedWindowScene` is the gesture gate that Group4Focus.x already has. No SpringBoard code in 16.2 ends display A's gesture: A's touch simply gets neither Ended nor Cancelled
  when the pointer's Began arrives on B, so the 16.2 behaviour lives in the event routing below SpringBoard (backboardd pointer capture / UIKit touch delivery). Not fixable here without
  rewriting touch windows by hand (the coordinates would be in B's space); no mitigation was added so that no masked state survives.
* 16.2 error branch of `transitionDidEnd` (`-[provider setPreviousLayoutState:]`): the 16.0 provider has no such API.
* `SBFIsChamoisWindowingUIAvailable`, `_SBIsSystemGestureAllowed`, `_SBPIPApplicationForProcessIdentifier`: private C functions of the 16.2 binary; re-implemented locally (same bodies).

## 8. Unsure (static only)
* Tongue (high confidence on structure, medium on feel): the tongue's own pull thresholds are the 16.0 SBGrabberTongue ones (class differs only in names). The touch recognizer's system gesture
  type 0x37 relies on the 16.0 type tables answering like for 0x33 (verified in `_shouldEnableSystemGestureWithType:` and `_isTouchGestureWithType:`).
* PIP data source: container frame math is a direct transcription; the consumer of `shouldProvideSourceClippingFrameInFixedCoordinateSpace:` was not found in SpringBoard (provided anyway).
* `g1d_extgestures`: whether the external display scenes register the 0x1e-0x21 recognizers in 16.0 was not traced; enabling is a no-op if they do not.
* Switch-off behaviour: `g1d_tongue` off restores the 16.0 reveal recognizer path completely (the configure/update hooks check the switch before touching anything).

## 9. What other agents / the lead must do
* Lead: wire `G1D_Setup()` (above). G1C: `kReqActItem` in `G1C_Req_ForTap` can go (accessor exists). G2B: the `_adjustedGestureEventForGestureEvent:fromGestureManager:` and the two
  `...ForContinuousExposeWindowDrag` stand-ins are replaced by `class_replaceMethod` in `G1D_InstallWindowDragSupport()`; G2B may delete them (G1D must run after it while they exist).
* Tweak.x already hooks `SBExternalDisplaySystemGestureManager _shouldEnableSystemGestureWithType:` for 0x42; the G1D hook is independent (different types) and chains.
* Group4Focus.x must keep `multiDisplayUserInteractionCoordinator` and `add/removePointerInteractionObserver:` (G1D uses them for the VC pointer observer).
