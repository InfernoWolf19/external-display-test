# AUDIT-ADDWINDOW-0.6.4: NSInternalInconsistencyException "The appLayouts array MUST contain the app layout we're transitioning to." after three-dots > "Add Another Window"

Static analysis only (no device, no log of the failing transition). 16.0 = 20A8372 (annot3.py / ipsw), 16.2 = 20C65 (annot162.py). All addresses are 16.0 unless marked 162.
Crash: thrown from `-[SBMainSwitcherControllerCoordinator layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:]` +2924 (0x1c62388d8, assertion line 0x42b = 1067),
reached from `-[SBSceneLayoutWorkspaceTransaction _completeTransition]` -> `-[SBLayoutStateTransitionCoordinator endTransitionWithError:]` (animation-finished path).

## 1. Result in one paragraph

* The assertion tests `[self->_appLayouts containsObject:N]` with `N = [S appLayout]`, `S = [ctx error] ? ctx.fromLayoutState : ctx.toLayoutState`. In the crashing path the error is NIL
  (`_completeTransition` calls `endTransitionWithError:` with x2 = 0, 0x1c5e48ee0), so `S` is the TO layout state: N is the app layout of the new layout state (mode 3, elements non-empty).
* `_appLayouts` has exactly ONE writer: `-[SBMainSwitcherControllerCoordinator _buildAppLayoutCache]` 0x1c6245ff0 (store `str x24,[x22,#0x18]` at 0x1c6246660; grep over the whole coordinator range of
  the 16.0 text: no other store to +0x18). It is reached only through `-_rebuildAppListCache` 0x1c6246bd0.
* In stock 16.0 the assertion is protected twice (model add at transition begin and again at the end, and the rebuild always re-inserts the CURRENT layout state's app layout, section 3).
  It can only fail if the end handler does not add N AND no rebuild ran after `transitionDidBegin` set the provider's layout state. I could not find, in any of our hooks, a change to the
  selectors that decide this (section 4). I therefore could NOT prove which input of that decision differs on the device. Root cause: NOT PINNED statically (confidence in any single
  hypothesis < 30 %). What is delivered is a safety net that repairs the exact stock expectation at the exact failure point (section 5), plus a log line per transition end so the next
  occurrence identifies the cause (section 6).

## 2. The failing method, decoded (0x1c6237d6c, 700 insns read; annotated file in the scratchpad coord_ann.s)

```
0x1c6237dc4  x28 = [ctx isInterrupted]                       0x1c6237e2c..e5c: [sp,#0x60] = [ctx error] ? from (after [provider setLayoutState:from], 0x1c6237e4c) : to
0x1c623806c  if (isInterrupted) goto 0x1c6238568             // the whole block below, including the NSAssert, is skipped
0x1c62383e8  x19 = [sp,#0x60]; if ([x19 unlockedEnvironmentMode] != 3) goto 0x1c6238564
0x1c62383fc  x28 = [x19 appLayout]                           // N
0x1c623842c  if (N) { if ([vc shouldAddAppLayoutToFront:N forTransitionWithContext:[ctx applicationTransitionContext] transitionCompleted:YES])   // 0x1c6238440
                       { x24 = (N.environment == 1) ? [_appLayouts bs_firstObjectPassingTest:^(l){ l.environment == 2 && [l.allItems isEqual:N.allItems] }] : nil;   // block 0x1c6238908
                         [self _addAppLayoutToFront:N removeAppLayout:x24] }                                                                                  // 0x1c62384d8
                     if ([[x19 elements] count]) NSAssert([self->_appLayouts containsObject:N], @"The appLayouts array MUST contain ...")                   // 0x1c62384e0..0x1c623850c, fail 0x1c62388a4
                   }
0x1c62388d4  bl handleFailureInMethod:object:file:lineNumber:description:   (file SBMainSwitcherControllerCoordinator.m, line 0x42b)
0x1c62388dc  b 0x1c6238510                                    // NSAssert does not abort: execution continues after a returning handler
```
x22 (the `object:` argument) is `self`. The tested object is therefore exactly `[S appLayout]` where S is the effective layout state; the safety net recomputes it the same way.

## 3. Where `_appLayouts` comes from in 16.0

`_buildAppLayoutCache` 0x1c6245ff0 (callers of `_rebuildAppListCache`: viewDidLoad/viewWillAppear, `_addAppLayoutToFront:removeAppLayout:` 0x1c6245548/0x1c6245594, the begin-of-animation block
0x1c6239264, the end handler 0x1c6238800, window-drag begin/end, reopen-hidden, `_switcherModelChanged:` ...):
1. `list = [[_mainSwitcherModel appLayoutsIncludingHiddenAppLayouts:NO] mutableCopy]` (SBAppSwitcherModel -> SBRecentAppLayouts).
2. `_enumerateSwitcherControllersWithBlock:` (block 0x1c6246790): for EVERY switcher controller: main = `[sc _currentMainAppLayout]` (0x1c617db54 = `[[sc _currentLayoutState] appLayout]`, i.e. the
   provider's CURRENT layout state), its items, floating = `_currentFloatingAppLayout`; plus `flag |= isMainSwitcherVisible && [gestureManager isDragAndDropTransactionRunning]`.
3. `list enumerateObjectsUsingBlock:` (block 0x1c62468a8) marks for removal: env-2 layouts sharing an item with a main layout, env-1 layouts sharing an item with the floating layout (both only when
   !flag), layouts for which `[self _shouldPrioritizeSortOrderForAppLayout:]` (single-item app layouts whose scene handle `shouldPrioritizeForSwitcherOrdering`; re-inserted at the front later) and
   `_demoFilteringHiddenAppLayouts` members.
4. Second loop over (floating layouts + main layouts): every one that is not already in the list and shares no item with `_liveDisplayItemsBeingTerminated` (ivar +0x78) and not (flag) is INSERTED AT INDEX 0
   (for env 1 the overlapping items are stripped from the other layouts first, block 0x1c6246a70).
5. services, `_testItemForInsertion`, transient overlay layouts / prioritized layouts are re-inserted; `self->_appLayouts = list`.
=> After any rebuild that runs after `[provider setLayoutState:to]` (done in `transitionDidBegin` 0x1c623717c, `x21 = toLayoutState`), the current layout's app layout is in `_appLayouts`
(unless it overlaps `_liveDisplayItemsBeingTerminated`, or a drag-and-drop transaction is running while the switcher is visible).

The model add: `-[SBRecentAppLayouts addAppLayout:atIndex:]` 0x1c64ebd84 (type must be 0, items filtered by `_isDisplayItemRestrictedOrUnsupported:` 0x1c64eef20, an early return when
`recents.firstObject == filtered layout`, delegate `appSwitcherModel:willAddAppLayout:...` of the coordinator returns the layout unchanged 0x1c624c2c0).
`_addAppLayoutToFront:removeAppLayout:` 0x1c62453b8: `if ([self _shouldAddAppLayoutToFront:N] /* N.type == 0, 0x1c624538c */) { model remove:/addToFront:; _rebuildAppListCache }`.

`shouldAddAppLayoutToFront:forTransitionWithContext:transitionCompleted:` = `-[SBFluidSwitcherViewController ...]` 0x1c5fc0f90 -> `-[SBFluidSwitcherLayoutContext shouldAdd...currentAppLayouts:transitionCompleted:]` 0x1c5e4a6e0
with `currentAppLayouts = [vc _unadjustedAppLayouts]` = `[coordinator appLayoutsForSwitcherController:]` 0x1c624d488 (`_appLayouts` itself with one switcher controller, filtered by preferredDisplayOrdinal with several).
Decoded decision (src = `[ctx.request source]`, done = transitionCompleted; read from 0x1c5e4a6e0, branch targets of the 0xb/0xc case only partly verified):
* NO: `first(cur) == N` and `from.elements == to.elements`; src 0xf && !done; both modes 2 && src 0x1b; src 0x3f; src 0x34 && N has no item for role 1.
* YES: src 0x38; `[context _shouldUpdateSwitcherModelBasedOnTimeOrUserInteraction]` for src not in {0xb,0xc}; N not in `cur`; (done) N in `cur` and src not in {0xb,0xc}; (done, src 0xb/0xc, N in cur) returns `to.elements.count == 0`.
* done == NO, N in cur: depends on environment/modes (YES for 3 -> 3 with src >= 0x10).
Sources seen in 16.0: 0x3f = `SBFullScreenContinuousExposeSwitcherModifier -handleTapAppLayoutEvent:` and `SBFluidSwitcherViewController handleTapToBringItemContainerForward:` (tap an EXISTING window, deliberately
never added); 0x23 = `requestNewWindowForBundleIdentifier:`, `SBUIController _activateWorkspaceEntity:fromIcon:...`, shelf new-window; 0x1b = drag and drop; 0x34 = shelf; 0x32 = top-affordance menu; 0x21 / 0x33 only appear in the end handler's app-expose special case (0x1c62380e8..0x1c6238110).

## 4. "Add Another Window" and what of ours touches the decision

* Menu item = `_addToSetAction` (`TOP_AFFORDANCE_MENU_TITLE_ADD_TO_SET`), action type 12 (UIAction block 0x1c645ac18) -> `-[SBMedusaDecoratedDeviceApplicationSceneViewController _topAffordanceViewController:handleActionType:transitionSource:]`
  0x1c632ba50, jump-table entry for type 12 -> `[[SBWorkspace mainWorkspace] requestTransitionWithOptions:0 displayConfiguration:builder:validator:nil]`, builder block 0x1c632c290:
  `request.source = 0x32; [request modifyApplicationContext:^(ctx){ ctx.requestedPeekConfiguration = 2; ctx.requestedUnlockedEnvironmentMode = 3; }]` (inner block 0x1c632c2ec).
  16.2 (0x1c77cd4a0 / 0x1c77cd4fc): same source 0x32, only `requestedPeekConfiguration = 2` (no explicit environment mode). No hook of ours touches this path (grep handleActionType: no hit).
  So the first transition is a "peek" of the current stage (same elements, peekConfiguration 2); the user then picks an app/window and a second transition adds it to the stage (new, merged app layout).
* 16.0's `SBContinuousExposeRootSwitcherModifier -floorModifierForTransitionEvent:` 0x1c6370db8 case mode 3 creates `SBPeekHomeScreenContinuousExposeSwitcherModifier initWithAppLayout:configuration:`
  when `_SBPeekConfigurationIsValid(toPeekConfiguration)`; `G1C.x:3244-3290` (16.2 factory) has no peek case: the peek is a child (`G1C_NewPeekModifier`, `handleTransitionEvent:` hook) and the floor stays FullScreen. Behavioural
  difference for the UI of the peek, but it only changes MODIFIERS; the coordinator model does not read any modifier.
* Selectors that decide the coordinator state, and whether any Backport162 code hooks/replaces them (grep over G1B/G1C/G2/G2B/G3/G3B/G3C/G4B/Group4*/Tweak): `_buildAppLayoutCache`, `_rebuildAppListCache`,
  `_addAppLayoutToFront:[removeAppLayout:]`, `_shouldAddAppLayoutToFront:`, `shouldAddAppLayoutToFront:forTransitionWithContext:transitionCompleted:`, `_unadjustedAppLayouts`,
  `appLayoutsForSwitcherController:`, `appLayoutsForSwitcherContentController:`, `_currentMainAppLayout`, `_currentLayoutState`, `layoutStateProvider`, SBAppSwitcherModel / SBRecentAppLayouts,
  `isDragAndDropTransactionRunning`, `isMainSwitcherVisible`, `_liveDisplayItemsBeingTerminated`, `shouldPrioritizeForSwitcherOrdering`, `SBLayoutState appLayout`: NO HIT. Hooks on the coordinator:
  G1B.x `transitionEventForContext:identifier:phase:animated:` (adds event flags only), G3B.x:1131 `layoutState` / `unlockedEnvironmentMode` (thread-local override that is only set inside
  `-[SBWindowSceneStatusBarAssertionManager isFrontmostStatusBarPartHidden:]`), G4B.x:1480 `windowSceneDidDisconnect:` (external display), `%new` methods. Hooks on SBAppLayout (G2.x:1441): only
  `continuousExposeIdentifier` (+ `%new zOrderedLeafAppLayouts`); that selector is read by modifiers and the VC, never by the model (callers of the stub: SBFluidSwitcherViewController, modifiers).
* Explicit checks of the leads named in the task:
  - `appLayoutsToEnsureExistForMainTransitionEvent:` (G2.x:1595): returns `@[]` instead of nil; its only caller in 16.0 is `-[SBTransitionSwitcherModifier handleTransitionEvent:]` (0x1c5fefaa8) which stores it in the modifier's own
    ivar (`_appLayoutsToEnsureExist`, +0x68, used by that modifier's `adjustedAppLayoutsForAppLayouts:`, a VC-side list). The coordinator never calls it. Not involved.
  - VC `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:` replacement (G1C.x:783-826): the 16.0 original (0x1c5fde0d0, read completely) only maps `_unadjustedAppLayouts`
    to `continuousExposeIdentifier`s, runs `adjustedContinuousExposeIdentifiersForIdentifiers:` on the root modifier, bumps a counter and dispatches the ids event (when animated). It writes no coordinator state, so
    dropping/changing it cannot remove an app layout from `_appLayouts`.
  - G1B `_performEventResponse:` consumers (G1B.x:524-545, 781-795): handle only types 38-40 / the invalidate response and ALWAYS call `%orig`; nothing is swallowed. The 16.0 switch has no "insert app layout" response type
    (response classes in 16.0: no insertion class; model insertion is done by the coordinator only).
  - G1B_Handled (`handleWithReason:` ignored the second time): bookkeeping flag of the event, no logic skipped.
  - G2B layout cache, `appLayoutContainingAppLayout:`, G3 handle hooks, G4B hooks: modifier/view/scene level; none feeds the coordinator model.
* Therefore the stock decision inputs that remain are the transition request (source, entities, peek/mode) and the layout state it produces; both are created by 16.0 code (`SBMainDisplayLayoutStateManager`,
  `SBToAppsWorkspaceTransaction`) from a request that 16.0 itself built for this menu item. The only code of ours that creates ADDITIONAL requests are the ported modifiers (`SBPerformTransitionSwitcherEventResponse`,
  G1C.x:214 / 963 / 1598 / 2702, sources 3 / 0x33 / none) and `G1C_Req_ForTap` (G1C.x:1366). If a ported modifier (the peek or the full-screen one) activates a layout that is not in the coordinator model
  (e.g. a synthesized layout of the 16.2 peek content, or a tap request with a source for which 16.0 never adds, 0x3f in stock) the end handler asserts exactly as observed.
  That is the most plausible mechanism (hypothesis H1) but I could not confirm which request it was.

## 5. Safety net (G1B.x, group `G1B_AddWin`, switch: global kill switch / `BP_OnName("addwinnet")`)

* `-[SBMainSwitcherControllerCoordinator layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:]`: computes N exactly like the stock code (not interrupted; `[ctx error] ? from : to`; mode 3;
  `[S appLayout]`; `[[S elements] count] != 0`), stores coordinator and N thread-locally for the duration of the method, and calls `%orig` inside `@try`. It does NOT touch `_appLayouts` before the method: a pre-patch would
  make the layout "contained" for `shouldAddAppLayoutToFront` and, for sources 0xb/0xc, suppress the model add the stock code would still have performed (section 3), i.e. change behaviour in the cases that work today.
* `-[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:]` (variadic hook; installed only when the switch is on): when it is called with `object == the coordinator in flight` and the
  description starts with "The appLayouts array MUST contain", it repairs and RETURNS (the stock code then continues at 0x1c6238510 as if the condition had held; nothing after the assertion is skipped). Every other
  failure is forwarded unchanged (the message is formatted with the va_list and passed as `@"%@"`).
* Repair `G1B_AW_Repair`: if `_appLayouts` still lacks N, first `[coordinator _addAppLayoutToFront:N]` (the official model add + `_rebuildAppListCache`); if N is still missing (type != 0, filtered, excluded by the rebuild rules)
  the `_appLayouts` ivar (strong, ARC) is replaced by `[N] + existing` via `object_setIvar`. The next stock rebuild replaces the array again, so the original array semantics are unchanged.
* Fallback: if the handler is not reached for some reason and the exception is raised, the `@catch` in the end hook recognises name+reason, repairs and returns (the rest of the method after the assertion is lost in that case).
* Debug log (`Backport162.debug`): one line per mode-3 transition end `addwin: transition end src=.. error=.. modes a->b peek a->b N <layout> in _appLayouts=0/1`, and `addwin net (...)` lines when it intervenes.

## 6. How to confirm / next evidence to ask for

With `Backport162.debug` present, after "Add Another Window" (peek) and picking an app, Backport162.log shows the `addwin: transition end ...` lines of both transitions. If a line has `in _appLayouts=0`, the following
`addwin net (assert|exception)` line proves the net acted. Read `src`: 0x3f / 0x34 mean the stock code deliberately did not add (the request came from a tap or shelf path: look for the ported modifier that built it);
`error=1` would mean a failed transition (then N is the FROM layout, which the begin-of-transition model add had replaced); any other `src` with `in _appLayouts=0` points to the rebuild rules (section 3 step 3/4:
`_liveDisplayItemsBeingTerminated`, drag-and-drop flag) or to `_shouldAddAppLayoutToFront:` (N.type != 0). The `N` description printed in the line contains items, environment and configuration.

## 7. Confidence

* Facts (x28 = `[effective state appLayout]`, single writer of `_appLayouts`, assertion falls through, error nil in the crashing path, decision table): HIGH (code read, addresses above).
* "No Backport162 hook alters the coordinator model path": HIGH (source grep + the 16.0 callers of each selector).
* Which input differs on the device (root cause): UNKNOWN; H1 (a ported modifier requests a transition to a layout that the 16.0 model does not contain, with a source for which the stock end handler does not add) about 30 %.
* The net: MEDIUM-HIGH that it prevents the crash (the assertion call site and the fall-through were verified in the disassembly); it was not run on a device. The variadic hook is compiled for arm64e: if the
  handler is not reached the `@catch` fallback still prevents the termination.
