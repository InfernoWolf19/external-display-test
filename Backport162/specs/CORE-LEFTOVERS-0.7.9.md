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
