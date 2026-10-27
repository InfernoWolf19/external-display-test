# CORE-LEFTOVERS-0.7.9 - the open items of REVIEW-CORE-0.7.9.md, ported

Status per item (16.0 = 20A8372, 16.2 = 20C65, unslid cache addresses). Nothing here was run on a device; "decoded" means read in the disassembly of both builds.
New code: `P1Drag.m` (item 1), further files per item. Debug lines: `Backport162.debug`, grep `p1:`.

## 1. H1 + M1 + M7: multi-display gesture workspace transaction (P1Drag.m)  - ported, device-unverified

### 16.2 mechanism (what the review's one-line description missed)
* The gesture transaction is **shared by all displays**. `-[SBFluidSwitcherGestureManager _startFluidSwitcherTransactionForGestureRecognizer:]` (block 0x1c78f37bc) creates the
  transaction and hands it to the coordinator: `-[SBMainSwitcherControllerCoordinator setActiveGestureTransaction:]` 0x1c76e2bd4 stores it (strong), observes it
  (`transactionDidComplete:` 0x1c76e2164 clears it) and gives it to the gesture manager of EVERY switcher controller (block 0x1c76e2ca4). 16.0: only the starting manager has it.
* `-[SBFluidSwitcherGestureManager handleTransitionRequestForGestureUpdate:]` 0x1c78f17f0 / `...Complete:` 0x1c78f17fc (16.0 `updateGesture...` / `completeGesture...`
  0x1c643fb94 / 0x1c643fb9c, bare thunks) send `[txn handleTransitionRequestForGesture{Update,Complete}:req fromGestureManager:self]`. So a request produced by the view controller of
  display B while the window drag of display A runs reaches A's transaction through B's manager (`switcherContentController:performTransitionWithRequest:gestureInitiated:`
  0x1c76d5a58 picks the manager of the VC that asked, same in 16.0).
* The transaction (0x1c74afba4 update, 0x1c74b0490 complete) takes the target display from the manager (`[manager switcherController]`), builds a workspace request for that display
  with `_workspaceTransitionRequestForSwitcherTransitionRequest:fromGestureManager:withEventLabel:` 0x1c74b1478 (16.0 `_transitionRequestForSwitcherTransitionRequest:eventLabel:` 0x1c6036044
  used the transaction's own window scene), reads the original / active layout state of that controller from two `NSMapTable`s (ivars +0x140 / +0x148, filled for every connected scene
  in init 0x1c74ae6f4), and the animation controller from `[switcherCoordinator animationControllerForTransitionRequest:]`. The main-display housekeeping that 16.0 did inline (orientation note,
  home screen content requirement, icon manager modal / folder UI) is `_updateMainDisplayIfNecessaryForWorkspaceTransitionRequests:` 0x1c74b0e90 and only acts for the main display's request (block 0x1c74b1128).
* `_runSceneLayoutTransactionForTransitionRequest:updateScenes:` 0x1c72d771c (95 -> 298 insns) creates the layout transaction of the request PLUS one per ancillary request
  (`+[SBMainWorkspaceTransitionRequest ancillaryTransitionRequestsForTransitionRequest:]` 0x1c7892c18 = the 16.0 `+[SBToAppsWorkspaceTransaction _ancillary...]` 0x1c63a4608: every connected scene's
  switcher controller answers `-_ancillaryTransitionRequestForTransitionRequest:` 0x1c76066fc). That answer is how the SOURCE display loses the window: for a request of another display it returns
  a request whose layout is its own elements minus those the request's layout contains (16.0 0x1c617e6e0 worked on unique identifier lists and `setEntity:forLayoutRole:`).
* `transaction:performTransitionWithCompletion:` 0x1c72dbcc0 (38 -> 191): completions of all layout transactions are collected (set), and when the main layout transaction starts with ancillary ones the scenes of its elements
  are moved to the target display's scene manager (`takeScene:fromSceneManager:`, `setWantsEnhancedWindowingEnabled:`, block 0x1c74af9ac). `transactionDidComplete:` 0x1c72dd5fc (336 -> 439), `_didComplete`,
  `_failRunningLayoutStateTransition`, `_willInterruptWithReason:`, `_beginWithGesture:` (interrupts the ancillary transactions too), `_startSceneUpdateTransaction:` (frame AND orientation compare),
  `_acquireBackgroundingScenesDeactivationAssertion...` (active state of the request's controller), `layoutStateFor... / previousLayoutStateFor...ApplicationTransitionContext:` (display of the context) and the new
  delegate method `transaction:shouldKeepSceneForeground:withReason:` 0x1c74afb5c ("window drag" for type 9) were decoded and ported.
* `-[SBSwitcherController _currentLayoutState]` 0x1c7605754: the active transaction's request counts only when it is for this controller's display.
* M1 `-[SBFluidSwitcherViewController gestureHandlingModifierRequestsUpdate:]` 0x1c7452bdc: `[self handleFluidSwitcherGestureManager:[[self switcherController] gestureManager] didUpdateGesture:[[self layoutContext] activeGesture]]`
  (the review described it as a coordinator broadcast; the disassembly shows the VC's own 16.2 handler, which converts a neighbouring display's window drag event with `_adjustedGestureEventForGestureEvent:fromGestureManager:`; 16.0 called `handleGestureDidUpdate:` directly).
* M7 `-_updateAsyncRenderingAndResizesHostedContext` 0x1c745929c: per live content overlay, async rendering is switched OFF for a layout in `[coordinator draggingAppLayouts]` (the review had it the other way round),
  `setResizesHostedContext:` is `isChamoisWindowingUIEnabled` unless async rendering is on (16.0: the modifier's `wantsSceneResizesHostedContextForAppLayout:`); the "async and resize both requested" error case renders synchronously.

### What was ported (all in P1Drag.m; the 16.0 ivars at +0x140.. cannot change because subclass ivars follow, so the new state is in associated objects and the 16.0 `_sceneLayoutTransaction` ivar plays `_layoutTransaction`)
Transaction: P1_Init, P1_WorkspaceRequest, P1_UpdateMain, P1_StartScene, P1_Acquire, P1_Run, P1_Perform, P1_TxnDidComplete, P1_HandleUpdate / P1_HandleComplete (replace G1C 5b's forwarders), P1_LayoutStateFor / P1_PrevLayoutStateFor,
P1_KeepForeground, wrappers (P1_Begin, P1_WillInterrupt, P1_Fail, P1_TxnComplete), the Reveal strip transaction override (flag, then base). Manager: P1_MgrUpdate / Complete / SetActive. Coordinator: setActiveGestureTransaction:,
activeGestureTransaction, transactionDidComplete:, setLiveContentOverlayUpdatesSuspended: (16.2 0x1c76e2d00, all displays). Switcher controller: P1_SCAncillary, P1_SCCurrentLayoutState, `_dismissMedusaBanner` (16.2 name of the education banner call).
`representsSameLayoutElementAsDescriptor:` on SBLayoutElement / SBWorkspaceEntity (uniqueIdentifier compare, 0x1c76f8374 / 0x1c7899d70), `+ancillaryTransitionRequestsForTransitionRequest:`. View controller: M1, M7.

### Switches (default on)
`p1_drag` (all), `p1_txn`, `p1_share`, `p1_ancillary`, `p1_modupdate`, `p1_asyncdrag`. The transaction mode (16.2 or 16.0 body) is fixed in init, so a kill file never mixes the two inside one gesture.

### Documented deviations (none changes a result)
(a) `_beginWithGesture:` keeps the 16.0 body; the 16.2 clean-up (interrupt the ancillary transactions with the "InterruptingGesture" request, clear the completions) runs from the `-_updateDigitizerSurfaceDimensions` call that follows it (16.2 has it directly before that call).
(b) The NSAssert "Got a nil animationController back from SBSwitcherController!" is a logged return (last-line guard, `p1: ... nil animationController`).
(c) `_layoutTransitionCompletions` is an array (16.2: set of blocks).
(d) `-[SBFluidSwitcherGestureManager _clearSystemApertureZStackPolicyAssistantSuppression]` (home layout completion) is not ported: it belongs to the System Aperture z-stack policy assistant (Dynamic Island hardware), the call is made when the selector exists.
(e) Not ported (not needed by the drag, listed so nothing is silent): the other changed `SBFluidSwitcherGestureManager` methods (`gestureRecognizerShouldBegin:`, strips overflow reveal gestures, tongue methods; owner: G2B/G1C ports where they exist) and the SBSwitcherController frame / traits / orientation family (item 3 M5).

### Log lines (a cross-display drag is decisive in the log)
`p1: txn <p> created (16.2 mode) ... own display <id>`, `p1: coordinator hands out the gesture transaction ... to N gesture manager(s)`, `p1: txn <p> update/complete from the manager of <display> (own display <display>), request layout ...`,
`p1: txn <p> layout transaction for the request of <display> + N ancillary layout transaction(s)`, `p1: ancillary request for <display>: N window(s) moved away to <display>`, `p1: scene <id> of window ... taken over by the scene manager of <display>`,
`p1: txn <p> animation done, final root transaction ...`. Expected for a window dropped on the other display: update/complete lines whose manager display differs from the transaction's own display, one ancillary request for the source display, one `taken over` line.

### What to look at when testing
Drag a window to the other display and drop it: it must land there, disappear on the source display (no ghost, strip updated), the source stage must re-layout. Single display gestures (app switch swipe, home swipe close, zoom, resize, strip) must behave as before; if anything regresses create `Backport162.off.p1_txn` (and `p1_share`) and send the log.

### Unproven
Everything cross-display (needs a run with an external display). The state sharing between managers is the 16.2 design but the 16.0 gesture manager code that reads `activeGestureTransaction` was not re-diffed method by method.


## 1b. FINDINGS-DRAG-LOOP patches applied (in this order, one commit each)
* P1 (G1B.x `G1B_RT_GuardLog`): suppression test first on scalars (kind, class, layout pointer, index), the message is a block that runs only for a line that is written.
* P2 (G2.x, G2B.m, G1D.x): `[defsize]` signature kept per display (bounds + embedded flag); the `[g2b] auto layout: a prerequisite is missing` line first time, then once per 2 s with a count, and `BP2B_AutoFail` names the failing check ONCE per distinct reason (the 16.2 auto layout port returned nil on every call in the user's log: the new line says which check); `setKillable:` is logged on change only.
* P4 (G1C.x `G1C_FinishStaleGestureChildren`, called from P1Drag.m): one run loop turn after the shared gesture transaction ended, a gesture root that still holds its 'Gesture' child finishes and removes it (`GUARD(end)` log, switch `g1c_endguard`). P1Drag does NOT complete the other display's child by itself when that display gets no layout transition (a drag inside one display), so P4 is needed; it runs only when no new transaction was handed out meanwhile, so a running gesture is never touched. The begin-time GUARD stays.
* P7 (G1B.x `G1B_AW_Layout`): a call stack (14 frames) of the first three `addwin: transition end src=11` lines. Source 11 is the source of every gesture transaction request, so the lines mark every layout transition end of a gesture. Decision about the doubled forward: the G1C 5b forwarders (16.2 name -> 16.0 name) were never called by 16.0 code (the 16.0 manager and coordinator call the 16.0 names) and are replaced by P1Drag; the 16.0 name -> 16.2 name direction exists only in P1Drag (manager thunk), once per request. Whether the doubled completes in the user's log are H2 (ids update) or another source stays open until a log with the stack exists.
* The user-visible check after P1Drag: the drop of a window on the other display logs `p1: txn ... complete from the manager of <target display> (own display <source display>)`, an ancillary request for the source display, `p1: scene ... taken over by the scene manager of <target>`, and a transition with `to=<bundle>` on the target display.

## 2. The remaining SBFluidSwitcherViewController / container / footer / layer methods (P1VC.m)  - ported, device-unverified
Per method (16.2 address; what the 16.0 method did differently; result):
| method | 16.2 | result |
|---|---|---|
| `performKeyboardShortcutAction:` (M3) | 0x1c743ace4 (jump table decoded: 3 App Expose of the focused app with the `bundleIDShowingAppExpose` toggle (same app again = request without bundle id, source 0x33), 4/5 next/previous window of the focused app, 6 toggle floating app, 15/16 next/previous window of any app, 7 8 11-14 17-20 overlay coordinator `performSwitcherKeyboardShortcutAction:`, 9/10 nothing) | ported (`p1_vckeys`); actions 21/22 (16.0 only, identifier based cycling) still run the saved 16.0 body; the `_navigate...InForwardDirection:` 16.2 names come from G2B (`g2bkeys`), the 16.0 name is the fallback |
| `_acquireKeyboardSuppressionAssertionForMode:` (M2) | 0x1c7459e50: hosted keyboard flag from `[[self _sbWindowScene] medusaHostedKeyboardWindowController]`, `startSuppressing...predicate:displayIdentity:` with a NIL identity (all displays; the review said "VC's window scene identity", the disassembly passes nil, X7Keyboard.x documents the same) | ported (`p1_kbsuppress`). The per scene controller accessor is not an SBWindowScene method on 16.0 (G3B keeps the controllers as associated objects): fallback order accessor, the scene manager's `_isUsingMedusaHostedKeyboardWindow`, the main display scene manager (= 16.0). Needs `-[SBWindowScene medusaHostedKeyboardWindowController]` from G3B for an exact external display answer: coordinator informed |
| `_performModifierIconViewVisibilityUpdateResponse:` | 0x1c745cd90: 16.0's tail (second animation `setAllIconElementsButLabelHidden:NO` when SBIconLocationGroupContainsLocation && chamois && !_isPerformingMatchMoveToIconView) is gone | 16.0 body kept, the match move query answers YES during its extent so the tail never runs (`p1_vcmisc`); equivalent result |
| `_updatePlusButtonPresence` | 0x1c74575b8: no plus button for com.apple.InCallService, weight 6, black always-original image instead of tintColor | ported |
| `_leafAppLayoutInLiveContentOverlaysWithLayoutRole:` | 0x1c7439f84: a leaf without an adjusted layout is matched through the controller's current app layout | ported |
| `_updateFloatingDockWindowLevelAssertion` | 0x1c745a234: `inAppOverFolderFloatingDockBehaviorAssertion` no longer cancels the window level assertion, order: new assertion first, then invalidate the old | ported |
| `_updateHomeScreenPointerInteractions` | 0x1c74583f4: gated by `[self _controlsHomeScreenContents]` (the review's description was wrong: the data source IS still told) | ported |
| `_updateForegroundAppLayoutsList` | 0x1c745b368 | **equivalent, nothing ported**: 16.0 calls the global function pointer `SBMoreForegroundApps` (0x18eb691f8) which is the very same function as 16.2's `SBFIsMoreForegroundAppsAvailable` (0x18ee09ba0, identical bodies) |
| `overlayAccessoryViewFrameForIconOverlayView:fullPresented:` | 0x1c7451420: without an adjusted layout the size comes from `containerViewBounds` | ported |
| `SBFluidSwitcherItemContainer _addPageView` | 0x1c72ced9c: 16.0 sets the page view's pointerInteractionHitTestPadding = stageInterItemSpacing itself; 16.2 forwards the container's stored padding, which the VC's `_applyStyleToAppLayout:` block (0x1c744f040, `stageInterItemSpacing` from block 0x1c744e5c4) sets | **kept (same final value)**: the value 16.2 delivers through the VC block is the one 16.0 sets here; porting only one half would leave the padding 0 |
| `initWithCoder:` | 0x1c75e101c: assertion "Override initWithFrame:delegate: instead", then the designated init with zeros and a nil window scene | ported (dead path) |
| `didUpdateFocusInContext:withAnimationCoordinator:` | 0x1c75e2f2c: return key recognizer lists press type Select (array literal `@[@4]`) instead of private `_setButtonType:4` | ported |
| footer `_handleTapGestureRecognizer:` | 0x1c7587b90: icon view hit test with convertPoint / pointInside (16.0: frames inset by switcherShelfSplitViewIconInset); style 0 splits the width evenly, mirrored for RTL | ported |
| footer `_makeSubtitleLabel` | 0x1c7587ff4: `setUserInteractionEnabled:YES` | ported |
| layer `setTransform:` | 0x1c75e5304: an equal transform (all 16 components, BSFloatEqualToFloat) is not set again; the review's "mirrors to the page view" is not what the disassembly shows | ported |
| `+[SBSwitcherChamoisSettings settingsControllerModule]` | 0x1c78c28dc: five more rows (Pile Compacting Factor, Rasterize Scaled Apps, Switcher Height for Icons and Labels Under Each Pile, Switcher Pile Card Peek Amount, Swticher Layout) in the internal Settings (PTSettings) UI | **not ported**: the module is only reachable from the Internal Settings app on an internal install; the settings keys behind the rows are consumed where they exist (G2 chamois settings port); nothing a retail device can show. Listed, not silent |

Switches: `p1_vc` (all), `p1_vckeys`, `p1_kbsuppress`, `p1_vcmisc`, `p1_container`.

## 3. M4 / M6 / M8: switcher modifier and coordinator leftovers (P1SW.m)  - ported, device-unverified

All three are `class_replaceMethod` bodies decoded from the 16.2 disassembly; each checks its switch at call time and runs the saved 16.0 IMP when the kill file is present.
Master switch `p1_sw` (nothing of this section is installed without it). Log: `p1sw:` (one install line at start-up, plus one line per one-time condition).

### M8 `SBHomeGestureToSwitcherSwitcherModifier -_appLayoutToScrollToDuringTransition` (16.2 0x1c795038c, 16.0 0x1c6499a54)  - switch `p1_homescroll`
* 16.2 reads `isChamoisWindowingUIEnabled` first. Start from the home screen (`_startingEnvironmentMode` +0x98 == 1) with Stage Manager: the first app layout of the FIRST
  continuous expose identifier (`[[self appLayoutsForContinuousExposeIdentifier:[[self continuousExposeIdentifiersInSwitcher] firstObject]] firstObject]`, nil without an identifier);
  16.0 (and 16.2 without Stage Manager) returns `[appLayouts firstObject]`.
* Every other mode: identical arithmetic (index of `_appLayout` +0x88, `_liftOffVelocity.x` +0xa0 / `_liftOffTranslation.x` +0xb0 against `velocityXThresholdForUnconditionalArcSwipe` x
  `_SBMainScreenPointsPerMillimeter` and half of the container width, clamp to 0..count-1) except the 16.0 selection tweak (mode 3 and new index 0 -> `w8 ^ 1`), which 16.2 skips with
  Stage Manager. The decode of the branch ladder was re-verified against both disassemblies (the two differ only by the chamois test).
* `_SBMainScreenPointsPerMillimeter` is a private static of SpringBoard (not exported). Reimplemented from its block (0x1c6396bb0): `(MGCopyAnswer("main-screen-pitch") / 25.4) / [[UIScreen mainScreen] nativeScale]`, once.
* Test: with Stage Manager on, open the switcher from the home screen with the home gesture (swipe up and hold): the first pile / window of the strip order is the scroll target,
  not simply the first app layout. A mode-3 (app switcher) swipe at index 0 no longer snaps to index 1.
* Unproven: the effect (needs device); the guard for an empty layout list returns nil (16.2 would raise on `objectAtIndex:-1`).

### M4 `SBDefaultImplementationsSwitcherModifier` role scale and frame (16.2 0x1c788a930 / 0x1c788a480; 16.0 0x1c63df6b8 / 0x1c63df34c)  - switch `p1_defroles`
* `scaleForLayoutRole:inAppLayout:`: 16.0 is the constant 1.0. 16.2 with Stage Manager: model scale of the item (fully occluded -> `stageOcclusionDodgingPeekScale`, partially occluded ->
  `partiallyOccludedStageScaleForItemWithSize:[model sizeForItem:]`, else 1.0). Without Stage Manager 1.0.
* `frameForLayoutRole:inAppLayout:withBounds:`: environment 2 / 3, Stage Manager off and role 4 are untouched (saved 16.0 body). The model path adds (a) **the peeking centre of a fully
  occluded item** (`unoccludedPeekingCenterForItem:` unless CGPointZero) - this was NOT in the review, it is in the 16.2 disassembly - and (b) for layouts with two or more items the
  scale about the overlapping anchor of a partially occluded item (`origin -= (centerForItem - overlappingScaleAnchorCenterForItem) * (1 - scale)`), then `UIRectIntegralWithScale`.
* The three model / attribute selectors of 16.2 (`unoccludedPeekingCenterForItem:`, `overlappingScaleAnchorCenterForItem:`, `partiallyOccludedStageScaleForItemWithSize:`) do not exist in
  16.0; G2 adds them. When any is missing the 16.0 bodies stay (one `p1sw: defroles` line says so).
* This is the **risky one for the regression guard** (close by home swipe, zoom, peek): the FullScreen floor (`G1C_FS_RoleScale` / `G1C_FS_RoleFrame`) answers these queries first in the Stage
  Manager chains, so the default is reached only by chains without a floor above it (HomeToGrid pass-through, transition modifiers whose parent does not answer). It has its own switch so
  that one kill file (`Backport162.off.p1_defroles`) isolates it.
* Test: close an app by home swipe from a stage with several overlapping windows, and drag a window over a stage so that others are partially occluded / peeking: the other windows keep
  their position and scale during the transition (16.2 shows them shifted toward their overlap anchor and scaled by the partial occlusion scale, not at full size). If the close animation
  of a single window changed, switch `p1_defroles` off first.
* Unproven: all of it on device.

### M6 `SBMainSwitcherControllerCoordinator -_evaluateAsynchronousRenderingEnablement` (16.2 0x1c76e1fcc is a bare `ret`; 16.0 0x1c624ce08, 275 instructions)  - switch `p1_asynceval`
* The 16.0 body toggled `setAsyncRenderingDisabled:` of the main display's switcher VC and the layer target's async rendering mode around every transition into / out of the switcher
  (unlocked environment mode 3). 16.2 does it only through the per-display VC response flags, `_updateAsyncRenderingAndResizesHostedContext` (ported in P1Drag.m, M7 / `p1_asyncdrag`).
  The port makes the coordinator method a no-op (one `p1sw:` line the first time).
* Behaviour risk (the reason it has its own switch): the timing of every switcher transition on the iPad can change (synchronous vs asynchronous rendering of the switcher window during
  the transition). Look for: snapshot / window flicker at the start or end of the app switcher open and close, and a change of animation smoothness. Kill file
  `Backport162.off.p1_asynceval` restores the 16.0 body.
* Unproven: that 16.0's VC code needs nothing the 16.0 coordinator body used to set (the 16.2 VC reads the response flags only).

Switches: `p1_sw` (all), `p1_homescroll`, `p1_defroles`, `p1_asynceval`.

## 3b. M5 orientation family (P1SW.m)  - Tier A ported (switch `p1_orient`), Tier B not ported (reasons below)

What the 16.2 disassembly shows for the five methods the review named, plus the callers it did not name:

| method | 16.2 | ported |
|---|---|---|
| `SBLayoutState -interfaceOrientationForLayoutElement:unknownAllowed:` / `-_interfaceOrientationForElementIdentifier:unknownAllowed:` (new) | 0x1c766f7ac / 0x1c766f80c; `-interfaceOrientationForElementIdentifier:` is the `NO` case (0x1c766f804). Element unknown or mapped to 0 -> `unknownAllowed ? 0 : [[self class] _defaultInterfaceOrientation]` | added (class_addMethod). The assertion for "known element not in the orientation map" (both releases) is not raised: answers 0, one `p1sw: orient:` log line |
| `SBApplicationSceneHandle -_createApplicationSceneSettingsFromContext:entity:` (the DELTA-SWEEP row marked "TO PORT: M5") | 0x1c729d898 vs 0x1c5e2b338: identical except that the element lookup of the context's layout state is `interfaceOrientationForLayoutElement:unknownAllowed:YES` (an element missing from that layout state answers 0, so the context / scene orientation is used; 16.0 answered the default orientation, which differs when a scene is created for a display whose layout state does not contain it yet, i.e. on a cross-display move). 16.2 also raises two assertions for a zero-size frame ("frame (%@) isn't valid", "Application scene settings frame should never be 0!") | wrapper around the 16.0 body: during the call the layout state of the context answers the lookup of this scene's element (once) with the `unknownAllowed:YES` answer. The two zero-frame assertions are crash paths and are **not ported** (16.0 behaviour kept) |
| `SBSwitcherController -coordinateSpaceForLayoutElement:layoutState:` | 0x1c7603a88: with Stage Manager the orientation is `[layoutState interfaceOrientation]` instead of the per-element one | ported (full body) |
| `SBSwitcherController -sceneEntityFrameForWorkspaceEntity:inLayoutState:` | 0x1c76073e4 vs 0x1c617ef24: same chamois orientation rule (`[layoutState interfaceOrientation]` replaces `-interfaceOrientationForSceneHandle:`); an error log for a zero-size result | wrapper: during the call `-interfaceOrientationForSceneHandle:` answers the layout state orientation once (the only use of that query in the body). The log is not ported |
| `SBSwitcherController -_updateAppTransitionContext:withOrientationActuationContext:` | 0x1c76026a4: forwards to the 4 argument form with `accountForSceneState = !isChamoisWindowingUIEnabled` (16.0: always YES) and the primary delegate ivar | ported (calls the 16.0 3 argument form, which reads the same ivar) |

Switch `p1_orient` (one kill file for all of Tier A). Log: one `p1sw: orient installed ...` line.
Test: move an app window from one display to the other and watch the log for `p1sw: orient` lines; with the main display, rotating the device with a Stage Manager window of an orientation-locked app open
(the window frame is computed from the layout state orientation instead of the app's own).
Unproven: every effect.

**Tier B, NOT ported: `SBSwitcherController -switcherOrientation:elementsOrientations:forTransitionRequest:previousLayoutState:layoutState:` (16.2 0x1c7600950) and its helper family.**
16.2 reorganised the whole switcher traits flow around a NEW class `SBSwitcherTraitsAssistant` (1769 instructions in 26 methods, `-createTraitsParticipantsForLayoutElements:outParticipantsByElementIdentifier:outDelegatesByParticipant:outPrimaryDelegate:`,
`-updateAllParticipants:withPrimaryDelegate:nonPrimaryPolicy:primaryPolicy:ownPolicy:`, "guiding" portrait-only / landscape-only participants for scenes that request an orientation, a policy specifier that is added and removed on demand),
the switcher controller got `_noteLayoutStateEvaluationBegan`, `_noteLayoutStateEvaluationEndedWithParticipantsByElementIdentifiers:...`, `_areLayoutStateElements:matchedWithAssociatedParticipants:`,
`_orientationsForLayoutStateElements:withAssociatedParticipants:`, `_elementsOrientationsForParticipantsByElementIdentifier:`, `actuateOrientationForTraitsDelegate:withContext:reasons:`, new ivars (assistant, evaluation counter,
`_needsOrientationReevaluation` instead of `_waitingFollowupTransition`, a second banner timer, a different order of the first 0x80 bytes), and the decision logic of `switcherOrientation:` changed in three places (the
`_canDetermineActiveOrientation` rule, a chamois rule "system gesture or from switcher into an app -> switcher policy 5 and re-evaluate", and the non-primary overlay policy = phone-app-on-pad ? 3 : primary policy).
Reasons it is left out: (1) the 16.0 SBSwitcherController ivar layout cannot change (subclasses follow it), so the new state would have to live in associated objects while every 16.0 method that still reads the old ivars keeps running next to it;
(2) the policy numbers feed `updateAllParticipants:` / the 16.0 `_updateParticipantsAndPoliciesWithSwitcherPolicy:...`, whose enum semantics were not shown to be the same, so porting only the decisions would mix two meanings;
(3) a mistake here breaks the traits arbiter of the MAIN display (device rotation, orientation lock) on the device the tweak runs on, and nothing of it is exercised by the external display path; (4) it cannot be verified without a device.
What the traits assistant gives in 16.2 (guiding participants for orientation-locked Stage Manager windows) is therefore absent. If a rotation problem with Stage Manager windows is seen, this is the first suspect.

## 4. H2: the 16.0 inline `_updateContinuousExposeIdentifiers...` calls next to the 16.2 response  - ported (scoped), device-unverified

**16.2 mechanism.** 16.2 has no inline call in the `performTransitionWithContext:animated:completion:` blocks. Its only caller is `-_performInvalidateContinuousExposeIdentifiersResponse:` (0x1c745ec0c: `[self _update...:[r transitioningFromAppLayout] toAppLayout:[r transitioningToAppLayout] animated:[r animated]]`),
driven by the `SBInvalidateContinuousExposeIdentifiersEventResponse` that the Root modifier appends AFTER its stage bookkeeping (G1C, switch `g1c_invalidate`, already ported). The 16.0 blocks (addresses of 20A8372, unslid):
* (A) `___82-[SBFluidSwitcherViewController performTransitionWithContext:animated:completion:]_block_invoke` 0x1c5fc4fc0 (181 instructions; 16.2 0x1c743dc4c has 165): for an animated transition, right after the begin event (phase 1) is dispatched,
  `update(event.fromAppLayout, event.toAppLayout, animated:YES)`.
* (B) `..._block_invoke_9` 0x1c5fc5cc0 (161; 16.2 0x1c743e90c has 134): for a NON animated transition, before the end event, `update([[ctx previousLayoutState] appLayout], [[ctx layoutState] appLayout], animated:NO)`.
Both run before the Root's handler has stored the new stage layout, so with the response path active they produce the interim list (log 19479b05: strip `[.. Filza ..] -> [.. Filza ..]` at phase 1, the real change only at the end) and one more ids event / layout pass per transition.

**What was ported.** The call is suppressed (G1C.x, the VC ids update replacement, switch `g1c_ids16supp`, default on, requires `g1c_invalidate`) when ALL hold: the caller is block (A) or (B) (identified by the return address against the unslid address ranges,
after the first two instruction words of both functions matched the 16.0 image: `pacibsp`, `sub sp, sp, #0xd0` / `#0x60`; another build logs `g1c: ids16supp: the 16.0 transition blocks are not at the expected addresses` once and nothing is suppressed),
the VC is in Stage Manager, and `from` AND `to` are both non-nil (app-to-app). Nothing needs hooking by address: the existing hook of the method looks at its own return address.
**Deliberately not suppressed (regression guard):** calls with a nil `from` or `to`, i.e. closing an app by the home swipe, going home, opening an app from the home screen, PiP and zoom transitions keep the 16.0 inline update and therefore their 16.0 timing.
Log lines: `g1c: ids16supp: the 16.0 transition blocks verified at ...` (once), `g1c: ids16supp: inline ids update of the 16.0 begin|end block suppressed (#n) from=.. to=.. animated=..` (first 12, then every 50th).
**Test.** (1) Switch from one app to another inside Stage Manager (dock, App Switcher, Cmd-Tab): the 0.1 s window flicker in the strip right after the switch (OPEN-ISSUES 7 / 6) should be gone; the log shows `ids16supp ... begin block suppressed`
and the `GLITCH VC ids update` lines of that switch show one update at phase 2 with the new stage instead of an interim and a final one. (2) Close an app with the home swipe, open an app from the home screen, pinch / zoom: identical to the build without this switch
(no `ids16supp` line for them). If anything in (2) differs, or the strip fails to update after an app-to-app switch, create `Backport162.off.g1c_ids16supp` and report.
**Unproven:** that the OPEN-ISSUES 6 / 7 flicker is caused by this (the review's hypothesis, supported by the log excerpt above); the suppression is logged and switchable so the next device log decides.

## 5. Crash: stack overflow when a window is resized from full screen (found on device, build eb694cd)  - fixed

**Evidence.** crash `5.crash` (pid 72981, SIGSEGV in `___chkstk_darwin`, main thread stack exhausted), log 00:40:24: `p1: txn ... created (16.2 mode), type 10` (live window resize) followed by 88 nested `p1: txn ... update` lines in 19 ms
without a single `layout transaction for the request` line (that line is logged after `addChildTransaction:`, which never returned) and a `transition end src=11 modes 3->3` between every two updates. The five P1 frames of the crash file are (symbolised
against the dylib of the CI artifact of eb694cd) `P1_V1` <- `P1_Run` (addChildTransaction:) <- `P1_HandleUpdate` <- `P1_MgrUpdate` <- `P1_VCModUpdate`, with BaseBoard BSTransaction frames between them.
**Root cause.** `P1_WorkspaceRequest` copied `setInLiveResize:` from `[request isLiveResize]`. The disassembly (16.0 0x1c6036318, 16.2 0x1c74b176c) sends `-isLiveResize` to the TRANSACTION (self): NO in `SBFluidSwitcherGestureWorkspaceTransaction`,
YES in `SBLiveWindowResizeGestureWorkspaceTransaction` (type 10). The SBSwitcherTransitionRequest has no such selector, so the update was treated as a normal Stage Manager window drag update (`chamois && !isInLiveResize`): a scene layout transaction per
update. Its synchronous completion made the resize modifier ask for the next update (`gestureHandlingModifierRequestsUpdate:` -> M1) from inside `addChildTransaction:`: unbounded nesting. Resize gestures did not use the cross-display
machinery by design; they only went down the wrong branch.
**Fix.** (a) `[self isLiveResize]` as in 16.0 / 16.2 (the root fix: resize updates only update the scene sizes, as before P1). (b) Re-entrancy guard, switch `p1_reentry`: an update that arrives while an update of the same transaction runs on this thread is
not nested; the newest request is kept and replayed after the outer update returns (max 3 replays), logged as `p1: re-entrant update refused (depth N, #n)`; a nested complete is refused with `p1: re-entrant complete refused`. (c) The other hand-offs
(completion forwarding in `P1_TxnDidComplete`, `p1_modupdate`, ancillary completion) were re-read: completions run once from the animation controller completion, nothing in them starts a gesture update; the guard covers the only synchronous
update -> layout transaction -> update cycle.
**Test.** Resize by the corner from full screen (the case of the crash), resize a window on the external monitor, resize a stage window: no `p1: re-entrant update refused` line should appear (it is the last line of defence); a normal window drag across
displays still shows `p1: txn ... update` / ancillary / `taken over by the scene manager`. Kill file for the guard only: `Backport162.off.p1_reentry`.

### 5b. Audit of every `P1_*` / `PV_*` / `PS_*` helper call (follow-up of the resize crash)
Method: all 426 helper calls (308 in P1Drag.m, 79 in P1VC.m, 68 in P1SW.m) were extracted with receiver expression and selector and checked against the class dumps of 16.0 and 16.2 (receiver class chain defines the selector?), with the receiver of each
ambiguous call checked in the disassembly of the method that is ported (hidden `mov x19, x3` style register moves included). Selectors that 16.0 lacks are all ones the port adds at run time (`handleTransitionRequestForGestureUpdate/Complete:fromGestureManager:`,
`setLiveContentOverlayUpdatesSuspended:` / `draggingAppLayouts` / `enumerateSwitcherControllersWithBlock:` on the coordinator, `_dismissMedusaBanner`, `representsSameLayoutElementAsDescriptor:`, `continuousExposeIdentifiersInSwitcher`, the G2 model selectors),
UIKit / FrontBoard / BaseBoard methods outside the SpringBoard dump, or the documented 16.2-only `medusaHostedKeyboardWindowController`. Return types were checked too (BOOL selectors through `B0`, `isFloatingSwitcherVisible` is a zero extended `ldrb`).
Defects found: (1) the resize crash (`isLiveResize` sent to the request instead of the transaction, fixed in 475993c); (2) **P1SW.m `PS_DefFrame` sent `-environment` to the modifier instead of the layout** (16.0 0x1c63df39c / 16.2 0x1c788a4d0 send it to x19 = the retained
layout argument): the environment 2 / 3 shortcut never applied, silently (fixed). No other wrong receiver found.
Non-silent helpers: every helper that reaches a missing selector on a NON-NIL receiver now logs once per selector and class, `p1: selector X missing on Y, treated as NO / nil / 0`; a missing ivar logs once as `p1: ivar X missing on Y, treated as nil / 0 / NO`
(nil receivers stay silent, they are normal). Expect exactly the documented absences in the log (medusaHostedKeyboardWindowController until G3B adds it).

## 6. Crash: NSInternalInconsistencyException "A floor modifier is required" (device logs u6, 3 crashes)  - guarded, root event to be named by the next log

**Where.** Crash stack (image offsets + `0x1c5e16000` = cache address of 20A8372): `-[SBFluidSwitcherRootSwitcherModifier _updateFloorModifierWithTransitionEvent:]` (0x1c61e8d74, assert at 0x1c61e8e0c, line 0x1a9) <- `handleTransitionEvent:` of the root (phase 2, or phase 3 of a non animated
event: 0x1c61e7c14 only updates the floor there) <- our CE-root `handleTransitionEvent:` hook (G1C stage bookkeeping) <- `SBSwitcherModifier _handleEvent:` <- `-[SBFluidSwitcherViewController _dispatchEventAndHandleAction:]` <- block_invoke_3 of
`performTransitionWithContext:animated:completion:` <- `_makeAppLayoutVisibleForTransitionWithContext:` <- `layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:` <- `SBLayoutStateTransitionCoordinator endTransitionWithError:` <-
`SBSceneLayoutWorkspaceTransaction _completeTransition`. I.e. the END of a layout transaction dispatches the late (non animated) phase 2 / 3 events of a transition. The assertion fires when `floorModifierForTransitionEvent:` (G1C's version of 16.2
0x1c78180e8) returns nil: environment mode outside 1..3 (16.0 and 16.2 both answer nil), or mode 2 without an App Expose bundle when `[self multitaskingModifier]` is nil (both releases).
**State at the crashes (logs).** crash 3 (16:34:59): a home gesture (txn type 1) on the EXTERNAL display went to the App Switcher of an empty display (`modes 1->2`, floor `BP162AppSwitcherFloor...`), the empty switcher was dismissed 0.2 s later
(`g1d: empty switcher dismiss timer ... -> dismissing`, floor back to `SBHomeScreen...`, effMode 1) and the layout transaction of the earlier mode 2 request ends afterwards: its late events say mode 2, the root now has the home floor and no
multitasking modifier -> nil. crash 1 (16:32:16): a home swipe closed the stage app (3->1) while the layout transaction of the previous window drag (`p1: txn ... layout transaction for the request of Main`) was still running; it ends after the
close with `transition end src=0 modes 3->3` -> stale mode 3 event against the home floor. Crash 2 is the same family. So: stale end events of an older transition against a root that has already moved to another floor. (16.2 has the same asserts and the
same blocks; its serial per-display transitions and the old transaction's interruption keep the stale end events away. The port's per-update layout transactions and the dismiss timer make them reachable.)
**Fix.** `-_updateFloorModifierWithTransitionEvent:` is replaced (G1C.x group G1C_FloorGuard, switch `g1c_floorguard`, default on) with the identical body plus a logged last line instead of the assertion: when the factory answers nil the CURRENT floor
stays (an event of an older transition must not change it), else a floor for the event's mode is built (full screen / multitasking / home); log `GUARD(floor) #n: ... event phase animated modes from->to gesture toAL toAppExpose current floor multitaskingModifier root -> floor (how)`.
That line names the exact event and state the next time it happens (the three crash logs could not, because the event is logged only after the handler returns). **Not fixed at the cause**: dropping the stale end events needs the guard's log to show which
transaction they belong to. Test: repeat the external display home swipe on an empty display, and a window drag followed quickly by a home swipe; no crash, `GUARD(floor)` lines in the log (send them).

## 7. "Finicky" drags between the extended display and the iPad: failure patterns in the u6 logs (build d586333 / dcef91c)

Method: every `p1: txn` line of the three log sets was folded per gesture transaction (type, display, updates, completion, layout transactions, ancillary requests); the successful drops were compared with the failing ones.
Successful: 4 cross-display drops in the u6/3 log (`taken over by the scene manager of ...`, ancillary request for the source display, final root transaction on the target, `GUARD(end)` finishing the stale gesture child of the display that got no
transition: P4 works as designed).
Failure patterns:
* **F1 SpringBoard dies right after a drop** (3 of 3 crashes): the `A floor modifier is required` assertion at the END of the layout transaction of the gesture (section 6). Evidence: all three crashes happen within 80 ms of an
  `addwin: transition end src=0 error=0 modes 3->3` that closes the layout transaction of an earlier drag while a second transition (home swipe 3->1 in crash 1; the source display going 3->1 with its last window gone, crash 2; the empty switcher of the
  monitor dismissed to home, crash 3) is already running on the same or the other display. Fixed by the guard `g1c_floorguard` (no crash; `GUARD(floor)` names the event the next time).
* **F2 a drop that does nothing / the window snaps back** (u6/3, 16:34:55 - 16:34:57, txn 0x10b913a10, iPad -> monitor): the gesture got ONE update (request layout `(null)`) in 1.3 s and completed from the manager of the monitor with an EMPTY request
  (`HomeScreenAppLayout`, `layoutItems = (empty)`, mode 0): nothing moves, the window stays on the iPad. Cause: during the whole drag the active pointer display flips between the two scenes about every 3 ms (170 `updating active pointer display`
  lines in 2 s, `flip probe 1/12 .. 12/12`: the SAME press is delivered once as scene 0x111ef6bf0 `location INSIDE the window` (988, 1426 in the 2560x1440 window) and once as scene 0x104f17c30 `location OUTSIDE the window` (848, 305 in the 834x1194
  window)). The drag updates therefore alternate between the two displays' recognizers, and the target display never sees a stable proposal. This is the pointer flip of FINDINGS-DRAG-LOOP P5 (display agent: G3.x / G4B pointer routing), not P1Drag.m;
  a successful drop in the same logs happened without flipping. P1Drag.m cannot make an empty drop request meaningful; it keeps the window where it is (the observed result).
* **F3 `addwin net: stock assertion intercepted (SBMainSwitcherControllerCoordinator.m:1067)` after a drop onto the iPad** (u6/3 16:34:34.894 and earlier logs): the coordinator's `_addAppLayoutToFront:` is called for a layout of another display; the G1B net
  makes `_appLayouts` contain it (works, logged). Not a failure; it is the same window the crash 2 follows 5 ms later.
* **F4 `g1d: window drag receiveTouch REFUSED`** (3 lines): the recognizer of the display that does not own the touch refuses it (`env 1`, no stage); expected.
* No `p1: no workspace request`, `nil animationController`, `last-line guard`, `re-entrant` or `selector missing` line in any of the logs (the three crashed builds predate the resize fix and the non-silent helpers).

## 8. Shadows of a windowed stage window, and after rotating the iPad (no log: reasoning from code)

How the shadow is made: the item container's page view hosts `SBAppSwitcherPageShadowView` with a child layer (radius 70, opacity 0.35, offset y +35, G2H.x notes); strength comes from the modifiers' `shadowOpacityForLayoutRole:atIndex:` (FullScreen floor 1.0 on stage,
G1C_FS_ShadowOpacity = 16.2 0x1c75c3750) and `shadowStyleForLayoutRole:inAppLayout:` (5), applied by `_applyStyleToAppLayout:roleMask:completion:` (identical in 16.0 and 16.2); its size follows the container, i.e. `frameForLayoutRole:` / `scaleForLayoutRole:`.
Findings:
1. `p1_defroles` DOES reach stage windows (the section 3 text saying the default is only reached without a floor was wrong): G1C_FS_RoleFrame / RoleScale call the stock chain, which ends in SBDefaultImplementationsSwitcherModifier. For ONE window on stage the result is the
   16.0 result (scale 1.0, same frame); for a stage with two or more windows the windows behind get the 16.2 partial-occlusion scale and shift (and the shadow follows the shrunken container). Environment 2 / 3 layouts (floating / center) took the wrong
   branch until e9afd3e (`environment` was sent to the modifier) - that build is older than the user's, so it is NOT the cause of the current report.
2. `p1_orient`: under Stage Manager the scene frame and coordinate space use `[layoutState interfaceOrientation]`. Every layout state in the logs (30 dumps, also the ones of the 2560x1440 monitor's transactions) says `UIInterfaceOrientationPortrait`; the 16.0 traits code
   does not publish a display's real orientation into them (that is the unported SBSwitcherTraitsAssistant work of section 3b). On a landscape display or after rotating the iPad the scene frame was then computed in a PORTRAIT reference frame while the container and its
   shadow are laid out in the display's real orientation: content and shadow disagree. **Fixed (this commit): the substitution is used only when the layout state orientation is valid and agrees with the shape of the switcher window; otherwise the per-element 16.0
   orientation is used and one `p1sw: orient: layout state orientation N contradicts the switcher window shape WxH` line is logged.** This is the most likely cause of the rotation report; if the log shows that line the next test tells.
3. `p1_asynceval` (M6, no-op like 16.2): the 16.0 body switched asynchronous rendering of the switcher window OFF around transitions into the Stage Manager; with the body gone the switcher window renders asynchronously during those transitions and a rotation. Asynchronous
   rendering of layers with CALayer shadows and no shadow path is a known source of flickering / lopsided shadows. 16.2 compensates through the per-display VC flags (`p1_asyncdrag`, M7), which are ported, but whether that is complete on 16.0 hardware paths is unproven.
Tests, cheapest first (each is one kill file in `<jbroot>/tmp/`, remove it again afterwards): (a) rotate the iPad with one windowed stage window: if the shadow is right, the orientation guard was the cause; (b) `Backport162.off.p1_asynceval`; (c) `Backport162.off.p1_orient`;
(d) `Backport162.off.p1_defroles` (only for stages with two or more windows). Send the log with `p1sw:` lines.

## 9. Blank windows after a drag back (u7 data, build 9fb6153 .. 8728cf0)

### 9.1 What a blank window shows (IMG_4264.heic, RPReplay 4093 / 4129)
The Settings window (com.apple.Preferences) on the extended display after it was dragged to the iPad: a normal window frame with title bar, the left half black, the right half white, row separators of the Settings table drawn over it, no content, no spinner. It is the placeholder of an item container whose scene is not hosted: the container exists, its host view has no remote context.

### 9.2 Which container [PROVEN from the log, 7.log 21:35:14-16, the same in 4 of 8 drops]
Drag 0x121d17900 (type 9, started on the extended display, window dropped on the iPad):
- 15.936 update of Main: ancillary request for AirPlay ("1 window moved away to Main"), scene `sceneID:com.apple.Preferences-default` taken over by the scene manager of Main (15.947).
- 16.347 `complete from the manager of Main`. The final root transaction of that complete finishes synchronously (`animation done` and `coordinator clears the gesture transaction` both at 16.388), the completion block 0x1c74af778 calls `finishWithCompletionType:`.
- There is NO `complete from the manager of AirPlay` for this drag. The end of a drag is broadcast to the controllers of all displays one after the other (G1D.x `fluidSwitcherGestureManager:didEndGesture:`, 16.2 block 0x1c76d7d18); the manager of the extended display calls `completeGesture...` after the transaction was cleared from it, `P1_MgrComplete` finds no `activeGestureTransaction` and the 16.0 body does nothing.
- 16.414 `GUARD(end) gesture root ... 'Gesture' child still active (no transition reached this display)`.
- The extended display never leaves its Preferences layout (`strip [] switcher [com.apple.Preferences]` in every ids update until the home gesture at 35:49.7, which is the first 3->1 transition there). Its item container hosts a scene that the scene manager of Main now owns = the blank window of the photo.
The drops where both completes ran (33:55, 34:00, 34:36, 35:12) show `complete from the manager of Main` followed 1 ms to 60 ms later by `complete from the manager of AirPlay` and a second final root transaction for the other display; those windows are fine. 4 of 4 broken drops are drags that were started on the extended display, 0 of 4 of those started on the iPad: the final root transaction of the iPad (the window arrives there) completes without waiting, the one of the extended display (the window leaves) is the long one.

### 9.3 Fix: switch `p1_endbcast` (P1Drag.m `P1_EndBroadcastBegin/End`, G1D.x) [documented deviation, no result differs from 16.2 when 16.2 completes all displays]
While the end broadcast of a window drag runs, the finish of the shared transaction (completion block 0x1c74af778) is held (`p1: ... finishing is held until every display delivered its complete`); when the broadcast returns and no further final root transaction or animation controller is pending, the transaction is finished (`p1: ... end broadcast returned, finishing the held transaction`). With the switch off the code is the faithful 16.2 completion block. 16.2 itself has the same ordering; there the final root transaction of the first complete is never this fast, so the race is not seen. Kill file `Backport162.off.p1_endbcast`.

### 9.4 Decisive container line (P1VC.m, switch `p1_ctrend`, logging only)
`p1ctr: container transition end: item <scene id> handle <p> scene <p> contentState <n> ready <b> | scene display <d1> container display <d2> -> same|MISMATCH | view window <b> hidden <b> alpha <a> | CALayerHost ctx <id> (xN) | portal source <p(window b)>|none | error <b>`, one line per container whenever its state changed at the end of a layout transition. A blank window shows as `MISMATCH` and/or `CALayerHost ctx 0 (x0)` / `contentState` not ready. Kill file `Backport162.off.p1_ctrend`.

## 10. "Move to Display" / "Move to iPad" makes the window portrait (and blank): the scene is never taken over (u9 / u10 logs, builds up to c4f1093)

### 10.1 What the user sees (RPReplay 9.mp4, 21:44:59 move of Reynard from the monitor to the iPad)
Home screen on the iPad, the window zooms up from its dock icon (16.2 icon zoom, see B), then stays as a WHITE rectangle of 646 x 646 pt at the place where a 1056 x 646 window was laid out (x 69 .. 715, y 24 .. 670 on the 1194 x 834 iPad); the dots menu of the window reads bottom-to-top (rotated 90 degrees). 646 is the height of the laid out window, 1056 its width: a portrait scene (646 x 1056) clipped to the landscape container.

### 10.2 Chain [PROVEN unless marked]
1. Handler: `-[SBMedusaDecoratedDeviceApplicationSceneViewController _topAffordanceViewControllerHandleMoveToDisplayAction:transitionSource:]` (16.0 0x1c632ccec = 16.2 0x1c77cdebc, instruction for instruction the same, blocks 0x1c632cef8 / cf58 / d008 / d158): first window scene that is not the window's own -> `requestTransitionWithOptions:0 displayConfiguration:[target _fbsDisplayConfiguration]`; the request gets `setSource:transitionSource` (62 = 0x3e "move displays"), a NEW `SBDeviceApplicationSceneEntity initWithApplication:uniqueIdentifier:sceneHandleProvider:[target sceneManager] displayIdentity:` as primary role, `requestedUnlockedEnvironmentMode 3`, empty entities for every other role. Nothing in our sources touches this path (no hook needed), and it is the same code in both releases.
2. The ancillary request for the display that loses the window comes from `+[SBMainWorkspaceTransitionRequest ancillaryTransitionRequestsForTransitionRequest:]` (our P1_ClsAncillary / P1_SCAncillary), the log line `p1: ancillary request for X: 1 window(s) moved away to Y` is there for every move.
3. The scene itself is moved to the scene manager of the target display by the block of `-[SBToAppsWorkspaceTransaction transaction:performTransitionWithCompletion:]` (16.0 block 0x1c63a3f80, 16.2 block 0x1c784e3f8). THE ONE DELTA: 16.0 matches `scene == [[entity sceneHandle] sceneIfExists]` (the entity's handle comes from the manager of the TARGET display and only references the scene when that manager already knew it), 16.2 matches `[scene identifier] isEqualToString:[[entity sceneHandle] sceneIdentifier]` and additionally sets `setWantsEnhancedWindowingEnabled:` = chamois of the target switcher controller on the new handle. Log proof: u10/a (the u9 test, 21:39-21:45) has 10 menu moves (`p1: ancillary request` + `transition end src=14`) and ONE `[y1] scene ... taken by` line (21:42:55, Reynard, towards the monitor); u10/b (26 Oct) has 10 moves and 2 take lines, none directly after a move (they follow drags); the scene of Reynard shows 3 different FBScene instances in the GUARD(scene handle) lines only because the user closed and reopened the window, not because of the moves.
4. A scene that stays with the OTHER display's scene manager keeps that display in its settings (`sb_displayIdentityForSceneManagers`), is not "windowed" for the new display and gets the settings logic of the display it came from: portrait reference frame (the monitor's traits say portrait, FINDINGS-DRAG-LOOP / p1_orient comment), scene frame swapped to 646 x 1056, the menu of the container asks the handle for `currentInterfaceOrientation` and gets 1 (`[g3zoomtitle] updateContextMenu ... orientation 1` right after every move to the iPad, 21:43:16.919, 21:43:33.780, 21:43:48.660, 21:44:59.087; the iPad's own value is 3), and the hosted context of a scene of another display is not rendered (white). The orientation reverts to 3 only at the next layout transaction that updates the window (21:43:30 / 16:09:16), which is why some moves look fine after a while.
5. Drags do not show it: P1_Perform (gesture transaction) already takes the scene by identifier (16.2 block 0x1c74af9ac), the 16.0 ToApps block is only on the menu path.

### 10.3 Fix: switch `p1_toappstake` (P1Drag.m `P1_ToAppsPerform`)
Pre-step before the 16.0 body of `-[SBToAppsWorkspaceTransaction transaction:performTransitionWithCompletion:]`: the 16.2 identifier match over `[[txn transitionRequest] toApplicationSceneEntities]` and all other scene managers, `takeScene:fromSceneManager:` then `setWantsEnhancedWindowingEnabled:` (Y1_Take sets it too, same value). The 16.0 body still runs afterwards and finds nothing left to move. Log line `p1: toapps: scene <id> taken over from <manager> by the scene manager of <display>`; with the fix every move shows it and `[y1] scene ... taken by`. Kill file `Backport162.off.p1_toappstake`. The container line of 9.4 (`p1ctr:`) now also prints the scene settings orientation / frame and the handle's windowed flag, so a remaining wrong orientation after the take-over is visible in the next log.

### 10.4 B: what the cross-display animations look like and what is ours (recordings 9.mp4, 4093, 4129; u9 log)
Menu move, as recorded and as logged (21:34:58.58, 21:43:16.9, 21:44:59.07 ...): the target display runs `main transition 1->3 stock modifier=nil` (the `_SBHomeScreenFloorSwitcherModifier` creator of G1B: icon zoom from the dock icon, async rendering disabled for `isMoveDisplaysTransition`, 16.2 0x1c750c3a8 ff.), the source display runs `3->1 SBFullScreenToHomeCenterZoomDownSwitcherModifier` (16.2 `isMoveDisplaysTransition` branch of the full-screen to home creator, G1B.x:2589) at the same moment, 40 ms later; the 16.2 root modifier of Stage Manager (`SBContinuousExposeRootSwitcherModifier`) does not read the flag, so the pair is what 16.2 plays too. What is wrong in the recordings is the content of that animation, not its choice: the window that zooms up is a black rectangle (4093 frame 10, Preferences) or a white one (9.mp4, Reynard) and 0.5 s later it is gone while the layout still holds it (`addwin: transition end src=62 modes 1->3 ... Preferences` at 21:34:59.41, the iPad then shows only wallpaper and the strip for 10 s until the next drag). A scene that is still hosted by the other display's scene manager (10.2) has no live context on the target display: black / white zoom, nothing afterwards. `p1_toappstake` is the fix of that; the 3 -> 1 zoom down on the source display shows the same scene, so it also showed a window that was already gone.
Drags: (a) the drop on the source display plays `1->1` with the Home floor for 1.3 s (21:34:00.225 phase 1 ... 21:34:01.550 phase 3) while the target display finishes after 0.74 s; during the drag the iPad shows an empty stage (wallpaper + strip, no icons: its layout is empty, `update from the manager of Main ... request layout (null)`, mode 3) which is what 16.2 does for a window that left; (b) every drop runs one animated and two non animated 3->3 transitions with `gesture=1` on the display that receives the window (`addwin: transition end src=11` three times, FINDINGS-DRAG-LOOP 2.6): the animated one is the layout transaction of the complete, the two others are the final root transactions of the two completes (`copied` request, animation disabled, P7); they re-lay out the same layout and are not visible; (c) ghost windows after a drag back: `p1_endbcast`; (d) load: a drag logged about 500 multi line records per second (`update from the manager` with the full app layout, `async rendering and resizing hosted content both requested` twice per update, `[y13] bring to front` with a 5 line item description twice per update), every BP_Log opens, writes and closes the file on the main thread: updates are now logged for the first 4 of a transaction and every 60th, the async line 3 times and every 500th, the bring-to-front line when the stamp changes. The async line itself is 16.2 behaviour: the drag modifier answers async rendering (16.0 0x1c61822cc = 16.2 0x1c760b03c: YES, YES for the selected item) AND resizes hosted content (0x1c6181f68 / 0x1c760ac74: YES for the initial layout / selected item), which in 0x1c745929c is the error branch that leaves async off and resizes = chamois, the same result as the dragging branch: p1_asyncdrag is faithful, nothing to change but the log volume.
Not provable from the logs: the length of the 1->1 drop animation of the source display (settings of the home floor / drop request, no 16.2 reference run); the next log with `p1ctr:` lines will show whether the container of the dropped window has a hosted context at the end of each of the three transitions.


## 11. Scan of the u10 logs (a = 25 Oct 21:3x-21:45 = the u9 test, b = 25 Oct 22:13 .. 26 Oct 20:12, c = 27 Oct 11:03-16:24)
What the older logs were for: u7 / u9 = the drag tests of builds 9fb6153 .. 8728cf0 (blank windows after dragging back, Move to Display portrait), b and c = ordinary use of later builds (one extended display connected part of the time).
- `p1ctr:` lines: none in b / c (the builds predate c4f1093; the first log with them is the next one). `finishing is held` / `end broadcast returned` lines: none (same reason).
- GUARD lines: b has 5 `GUARD scene handle ... destroy of scene [com.mac.virtual-default] ignored` (the Mac virtual display scene destroyed and recreated, display Main, 16:06-16:10, designed P6 behaviour) and 4 `GUARD(floor)` #27-#30 at 20:11:24 / 20:11:27 (modes 0->0 stale events after home swipes, kept floor, same as the u7 six); a has 2 `GUARD scene handle` for Reynard (window closed and reopened); no `GUARD(end)` in b or c: no ghost drop there (b and c have no cross-display drag at all: every transaction has 1 switcher controller or the extended display only).
- Moved windows ending portrait: every menu move to the monitor shows `contentOrientation portrait (1)` in the layout attributes of the monitor (all logged monitor layout states are portrait, FINDINGS-DRAG-LOOP / p1_orient), every move to the iPad shows `landscapeRight (3)` in the layout but the container menu line shows `orientation 1` for the moved scene (a: 21:43:16, 21:43:33, 21:43:48, 21:44:59; b: 16:09:11) = scene settings of the other display (10.2); b 19:28:09 `portrait (1) maximized` on Main is Aidoku opened from home (no ancillary request, single display; its scene reports orientation 1 on the landscape iPad, a different cause: the app's own orientation handling, the Z2Orient work), not a move; `src=14` also appears there, so `src=14` is not specific to the move path.
- Blank / ghost containers: u7 (4 of 8 drops) = 9.2; a: the menu moves = 10.2; b / c none.
