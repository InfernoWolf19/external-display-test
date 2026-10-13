# KILL-EXTDISPLAY-0.7.4: closing the only card on the extended display does not update the model (no type 15 removal event)

Scope: facts from the 16.0 (20A8372) vs 16.2 (20C65) SpringBoard disassembly (scratchpad `a160.sh` / `a162.sh` / `annot3.py` / `annot162.py`, text dumps `sb_text.s` / `sb162_text.s`, symbol lists `sb_syms.txt` / `sb162_syms.txt`). Nothing was run on a device; items marked UNCERTAIN are inference. No source file was edited. Per-function diff method: both versions annotated, addresses / ivar offsets / branch targets stripped, then `diff` of the mnemonic + callee sequence ("identical" below = no difference in that sequence; ivar offsets were checked by hand where they differ).

## 1. Result in one paragraph

The chain is byte-for-byte the same in 16.0 and 16.2 from `killContainer:forReason:` down to `-[SBSwitcherModelRemovalResults executeActionForAppLayout:]`, except for ONE per-display difference that our port has not covered: the per-window removal action block created inside `-[SBMainSwitcherControllerCoordinator _switcherModelRemovalResultsForRequest:forReason:]` (the block `___88-..._block_invoke`, 16.0 0x1c624b928, 16.2 0x1c76e0b00) removes the layout through `[[coordinator _embeddedDisplaySwitcherController] contentViewController]` in 16.0 (always the MAIN display's switcher view controller) but through `[[coordinator switcherControllerForAppLayout:layout] contentViewController]` in 16.2 (the switcher controller that owns the layout, captured when the results are built). `-[SBFluidSwitcherViewController removeLayoutRole:inSpace:mutationBlock:reason:]` (identical in both versions) is the only place that dispatches the SBRemovalSwitcherModifierEvent (type 15, phases 1 and 2) and it does so on `self`. With the main display's view controller as `self` and a layout that lives on the external display, the event is never dispatched to the external display's modifier chain. That matches the device observation (card vanishes through the kill scroll view, no type 15, no auto-dismiss, main display fine).

Our existing `g1d_removal` hook ported the first 16.2 per-display change of the same method (`_currentAppLayout` / `_currentFloatingAppLayout` read from `switcherControllerForAppLayout:`) but NOT this second one inside the block (the block runs unmodified inside `%orig`).

## 2. Step-by-step comparison (16.0 address / 16.2 address)

| # | Step | 16.0 | 16.2 | Verdict |
|---|------|------|------|---------|
| 1 | `-[SBFluidSwitcherViewController killContainer:forReason:]` (calls `[delegate switcherContentController:self deletedDisplayItem:item inAppLayout:layout forReason:1]` for every item when `isCenterOverFull`, else for the item of the role, then split-view enumerate) | 0x1c5fd8844 | 0x1c74519ec | identical; `delegate` is the coordinator for both displays (no display branch) |
| 2 | `-[SBMainSwitcherControllerCoordinator switcherContentController:deletedDisplayItem:inAppLayout:forReason:]` | 0x1c6242290 (12 bytes: `b _removeDisplayItem:forReason:preferredAppLayoutForRemovalAnimationIfAny:`) | 0x1c76d5bd4 (same 12 bytes) | identical, no display identity used |
| 3 | `_removeDisplayItem:forReason:preferredAppLayoutForRemovalAnimationIfAny:` (creates `SBSwitcherDisplayItemRemovalResolutionRequest`, `setRemovalIntentType:2`, then `_resultsForDisplayItemRemovalResolutionRequest:...` -> `_modelRemovalRequestForDisplayItemResolutionResults:` -> `_switcherModelRemovalResultsForRequest:forReason:` -> `_performSceneDestructionForModelRemovalResults:`) | 0x1c624bf44 | 0x1c76e1108 | identical (same 5 calls, same order); `_removeDisplayItem:forReason:` stub 0x1c624bf3c / 0x1c76e1100 |
| 4 | `_resultsForDisplayItemRemovalResolutionRequest:preferredAppLayoutForRemovalAnimationIfAny:` (+ `_nonHiddenAppLayoutsForDisplayItem:` 0x1c624b30c / 0x1c76e04bc, `SBSwitcherDisplayItemRemovalResolutionResultAction defaultRemovalPolicyActionWithAppLayout:` 0x1c63d37d0 / 0x1c787f4f0) | 0x1c624ada4 | 0x1c76dff54 | identical; no per-display input anywhere in these three |
| 5 | `_modelRemovalRequestForDisplayItemResolutionResults:` | 0x1c624bc24 | 0x1c76e0de8 | identical |
| 6 | `_switcherModelRemovalResultsForRequest:forReason:` body | 0x1c624b4b0 | 0x1c76e0660 | DIFFERS (already ported, `g1d_removal`): 16.0 reads `[self _currentAppLayout]` and `[self _currentFloatingAppLayout]` once, before the loop; 16.2 reads `[[self switcherControllerForAppLayout:layout] _currentMainAppLayout]` and `[sc _currentFloatingAppLayout]` per removed layout and keeps `sc` (stack slot [sp+0x68]) |
| 7 | the same method's per-item action block `_block_invoke` (the action executed later by `executeActionForAppLayout:`) | 0x1c624b928 | 0x1c76e0b00 | DIFFERS, NOT PORTED (see section 3) |
| 8 | the mutation block passed as `mutationBlock:` (`_block_invoke_2`: sets coordinator flag, `replaceAppLayout:withAppLayout:` / `hide:` / `remove:` on the coordinator's shared app switcher model, `_rebuildAppListCache`) | 0x1c624bafc | 0x1c76e0cc0 | identical; only the ivar offsets move (flag 0x80 -> 0xa0, model 0x78.. -> 0xd0) |
| 9 | `_block_invoke_3` (item predicate for the hidden-layout re-add) | 0x1c624bc14 | 0x1c76e0dd8 | identical (not listed in diff set, 16 bytes) |
| 10 | `_performSceneDestructionForModelRemovalResults:` | 0x1c624a104 | 0x1c76df2a0 | identical in all display related calls: both read `[self _currentAppLayout]` / `[self _currentFloatingAppLayout]` (ACTIVE display) once at entry, both call `[results executeActionForAppLayout:layout]` synchronously (16.2 0x1c76df5dc) right after `acquireWithPredicate:transitionContext:`. Only difference: 16.0 `[self _appForDisplayItem:]` (0x1c623f370) became `[[SBApplicationController sharedInstance] applicationForDisplayItem:]` in 16.2 (no display relevance, UNCERTAIN whether 16.0 selector exists on SBApplicationController, irrelevant here) |
| 11 | `-[SBSwitcherModelRemovalResults executeActionForAppLayout:]` (pops `actions[layout]`, calls the block, returns void) | 0x1c638e96c | 0x1c7837c8c | identical |
| 12 | `-[SBFluidSwitcherViewController removeLayoutRole:inSpace:mutationBlock:reason:]` (+ its 3 blocks) | 0x1c5fc80e4 | 0x1c7440d38 | identical |

### Step 12 detail (16.2 0x1c7440d38, same in 16.0), the step that produces type 15

```
leaf = [space leafAppLayoutForRole:role]                       // 0x1c7440d88
owned = [self->_(ivar +0xee0 in 16.2) objectForKey:leaf]        // 0x1c7440da4  (a per-view-controller map of the layouts this controller shows)
if (!owned) goto L_fb0                                          // 0x1c7440db0
idx = [[self appLayouts] indexOfObject:owned]
if (![self->_(ivar +0xe9c) shouldAnimateInsertionOrRemovalOfAppLayout:owned atIndex:idx]) goto L_fb0
ev1 = [[SBRemovalSwitcherModifierEvent alloc] initWithLayoutRole:... inAppLayout:owned reason:reason phase:1]
[self _dispatchEventAndHandleAction:ev1]                        // 0x1c7440e50
mutationBlock()                                                 // 0x1c7440e60 (shared model mutation)
ev2 = ... phase:2
[self _dispatchEventAndHandleAction:ev2]                        // 0x1c7440e8c
... perform:finalCompletion:options:delegate: (animation) ...
L_fb0: mutationBlock(); [self->_(ivar +0xef4) purgePageContentViewForAppLayout:leaf]   // 0x1c7440fb0..0x1c7440fd0
```
On the wrong view controller (`owned == nil`, UNCERTAIN: inferred from the code, the exact ivar name was not resolved) only the shared model mutation (`mutationBlock`) and a purge on the wrong controller run. That also explains "the card vanishes (kill scroll view) but the external switcher keeps its model entry and never gets phase 1/2".

## 3. The divergence, exactly

16.2 `_switcherModelRemovalResultsForRequest:forReason:` 0x1c76e0660, per removed `appLayout` (`x25`):
```
0x1c76e0740  sc  = [self switcherControllerForAppLayout:appLayout]          // x21, kept in [sp+0x68]
0x1c76e074c  main = [sc _currentMainAppLayout]
0x1c76e075c  float = [sc _currentFloatingAppLayout]
...  per display item: build the action block (0x1c76e0b00) capturing: coordinator(+0x20), item(+0x28), main(+0x30), float(+0x38),
     appLayout(+0x40), sc(+0x48)   <-- 16.2 only, replacement layout(+0x50), previous action block(+0x58), reason(+0x60), hide flag(+0x68)
[results setAction:block forAppLayout:appLayout]
```
16.2 block 0x1c76e0b00 (the part that matters):
```
[previousBlock invoke]                                         // chain, earlier items of the same layout first
if (reason == 1) { recent-layouts bookkeeping on coordinator ivar +0x158 ... }       // same as 16.0
if (main containsItem:item || float containsItem:item) [coordinator->_X addObject:item]   // same
role = [appLayout layoutRoleForItem:item]
vc   = [[block->sc] contentViewController]                      // 0x1c76e0c0c  <== captured owner of the layout
[vc removeLayoutRole:role inSpace:appLayout mutationBlock:mutate reason:reason]    // 0x1c76e0c9c
```
16.0 block 0x1c624b928 (same code but):
```
vc = [[coordinator _embeddedDisplaySwitcherController] contentViewController]   // 0x1c624ba3c, 0x1c624ba48
[vc removeLayoutRole:role inSpace:appLayout mutationBlock:mutate reason:reason]  // 0x1c624bad0
```
Corroboration: `_embeddedDisplaySwitcherController` (16.0 0x1c624e14c, 16.2 0x1c76e3698, both = `[switcherControllerForWindowScene:[[UIApplication sharedApplication].windowSceneManager embeddedDisplayWindowScene]]`) has 12 call sites in 16.0 (stub 0x1c6849f00: this block, `handleHomeButtonPress`, `...DoublePress`, `...LongPress`, `handleLockButtonPress`, `handleVoiceCommandButtonPress`, `handleVolumeUp/DownButtonPress`, `handleHeadsetButtonPress:`, `_overrideWindowActiveInterfaceOrientation`, `_insertCardForDisplayIdentifier:atIndex:`, `_contentControllerIsEmbeddedDisplayContentController:`) and 11 in 16.2 (stub 0x1c7d22d40: the same list without the removal block). So the removal block is the only caller 16.2 removed, i.e. an intentional per-display fix in 16.2.

The only other callers of `removeLayoutRole:inSpace:mutationBlock:reason:` are this block and `-[SBSwitcherShelfViewController switcherContentController:deletedDisplayItem:inAppLayout:forReason:]` block (16.0 0x1c64cd388, 16.2 0x1c79887d8), unrelated to the failing path.

Everything above step 7 is display neutral. There is no `isMainDisplay` branch, no `SBMainDisplayLayoutStateManager` lookup and no display-identity read in killContainer, the deletedDisplayItem forwarder, the resolution / request builders or `executeActionForAppLayout:`. The `preferredAppLayoutForRemovalAnimationIfAny` argument is passed through unchanged (nil from `deletedDisplayItem`, `x3` retained and released in 0x1c624bf74..0x1c624bfb8 / 0x1c76e1138..0x1c76e117c) and is not display related.

## 4. Faithful port

16.0 selector gap: `-[SBMainSwitcherControllerCoordinator switcherControllerForAppLayout:]` (16.2 0x1c76e291c) is already ported (`G1D.x` ~line 308, `%new`). `sc`'s `contentViewController` exists in both (16.0 0x1c617f3ac, 16.2 0x1c7607b6c).

Approach (exact semantics of the 16.2 capture, no hook on `killContainer` / `handleRemovalEvent:`):

Because the block cannot be edited, make its single receiver choice (the main display's controller) resolve to the owner. Two equivalent implementation points; recommended is B.

A. Hook `-[SBMainSwitcherControllerCoordinator _embeddedDisplaySwitcherController]` (no hook exists today): return the captured owner iff executing a removal action. Needs the action scope and a caller check (the other 11 callers must keep the embedded controller, `_contentControllerIsEmbeddedDisplayContentController:` could be reached while an action runs through the transition, UNCERTAIN) so it needs a return-address test against block 0x1c624ba3c (16.0), fragile. Not recommended.

B. (recommended) Redirect the receiver at `-[SBFluidSwitcherViewController removeLayoutRole:inSpace:mutationBlock:reason:]` inside the action scope:

```objc
// G1D.x, group G1D_Coord, shared state
static __thread __unsafe_unretained id tExecOwner;       // SBSwitcherController that owns the layout whose removal action runs
static __thread __unsafe_unretained id tExecLayout;      // that layout
static char kRemovalOwners;                              // associated object on the SBSwitcherModelRemovalResults

// 1) in the EXISTING hook -_switcherModelRemovalResultsForRequest:forReason: (G1D.x:474), BEFORE %orig (the layouts are still in the model, which is
//    exactly when 16.2 0x1c76e0740 reads them) build the map; AFTER %orig attach it to the returned results.
NSMapTable *owners = [NSMapTable strongToStrongObjectsMapTable];
for (id l in ls) { id sc = G1D_Msg1(self, @"switcherControllerForAppLayout:", l); if (sc) [owners setObject:sc forKey:l]; }
id r = %orig;                                            // existing code, own line
objc_setAssociatedObject(r, &kRemovalOwners, owners, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

// 2) new hook, runs the action (void, 16.0 0x1c638e96c / 16.2 0x1c7837c8c, same body)
%hook SBSwitcherModelRemovalResults
- (void)executeActionForAppLayout:(id)layout {
    if (!G1D_ON("g1d_removalowner")) { %orig; return; }
    id sO = tExecOwner, sL = tExecLayout;
    tExecOwner = [(NSMapTable *)objc_getAssociatedObject(self, &kRemovalOwners) objectForKey:layout];
    tExecLayout = layout;
    %orig;
    tExecOwner = sO; tExecLayout = sL;
}
%end

// 3) new hook on the receiver (16.0 0x1c5fc80e4 / 16.2 0x1c7440d38 are identical, no 16.2 delta to preserve)
%hook SBFluidSwitcherViewController
- (void)removeLayoutRole:(long long)role inSpace:(id)space mutationBlock:(id)mutation reason:(id)reason {   // arg types from the 16.0 header, check the real SDK header: role is a long long, reason is an id (NSString-like, compared == 1 in the block: so it may be a long long, check)
    id owner = (G1D_ON("g1d_removalowner") && tExecOwner && space == tExecLayout) ? G1B_Send0(tExecOwner, @selector(contentViewController)) : nil;
    if (owner && owner != (id)self) {                    // 16.2: [[sc contentViewController] removeLayoutRole:...]
        ((void (*)(id, SEL, long long, id, id, id))objc_msgSend)(owner, _cmd, role, space, mutation, reason);
        return;
    }
    %orig;
}
%end
```
Notes on the pseudocode: `reason` is compared with `cmp x8, #1` in the block (`[x19,#0x60]` in 16.2) and passed in `x5`, so it is an integer (`long long`), not an object; use the real 16.0 signature (`removeLayoutRole:(long long)inSpace:(id)mutationBlock:(id)reason:(long long)`), role also integer (`x2` from `layoutRoleForItem:`). Because the redirect happens inside the original call chain, the mutation block (shared model change, `_rebuildAppListCache`) still runs exactly once, now from the owner (`owned != nil` path), after phase 1 and before phase 2, as in 16.2.

Fidelity detail: in 16.2 a nil `sc` (layout in no display's list) makes `[nil contentViewController]` nil and the whole `removeLayoutRole` a no-op (mutation block not run). The redirect above falls back to stock (`%orig` on the main controller) when no owner is found; strictly faithful is no-op, but then the shared model would keep the layout. UNCERTAIN which is better, choose the 16.0 stock fallback and log it under `BP_LogEnabled()` (it is a last-line guard, per PORT-BRIEF rule 3).

Alternative to the associated map (equal result for the failing single window case): call `switcherControllerForAppLayout:space` inside step 3 at the time of the call. Not equal for layouts with several display items: the block chain runs earlier items first, the first call's mutation block `replaceAppLayout:withAppLayout:` changes the model, and the later lookup of the OLD layout can return nil. The map built before `%orig` avoids that, which is why 16.2 captures `sc`.

New kill switch: `g1d_removalowner` (BP_OnName), under the existing `g1d` master switch.

## 5. Collisions with existing hooks

- `G1D.x:474` `-[SBMainSwitcherControllerCoordinator _switcherModelRemovalResultsForRequest:forReason:]` plus `_currentAppLayout` / `_currentFloatingAppLayout` (G1D.x:484 / 491, thread-local `tRRSelf/tRRLayouts/tRRIdx`): extend this same hook (build owners before `%orig`, attach after). No conflict with the `tRR*` thread-locals (they are only read inside `%orig`; `tExec*` are read later in `executeActionForAppLayout:`, different scope and different names). The two `_current*AppLayout` overrides already call `switcherControllerForAppLayout:` for each layout, same value as stored in the map.
- No existing hook on `SBSwitcherModelRemovalResults` and none on `-[SBFluidSwitcherViewController removeLayoutRole:inSpace:mutationBlock:reason:]` (grep over all `*.x` / `*.m`). `_embeddedDisplaySwitcherController` is not hooked either (option A would be the first).
- No hook on `killContainer:forReason:` / `handleRemovalEvent:` is needed (`G1D.x` / `G1B.x` do not hook them; the earlier attempt that broke card removal is not part of this port). The only existing handler of the event is G1C `G1C_As_Removal` (G1C.x:4833, 16.2 0x1c780fcf8), registered for `handleRemovalEvent:` on the ported `SBAppSwitcherContinuousExposeSwitcherModifier`. It is the consumer of phases 1 and 2 (`_bp_ongoingRemovals` counter, dismiss at phase 2 with 0 layouts and 0 ongoing). The new redirect makes both phases reach it on the external chain; both always come from `removeLayoutRole` so the counter stays balanced.
- `G1B.x:109` (`SBSwitcherModifier _handleEvent:` trace for type 15) will start logging on the external chain; expected confirmation line: `g1b: removal event (type 15) on ...` then `g1c: app switcher removal event phase 1/2 ...` then the last-window dismiss path. G2B tongue wrapper around `_dispatchEventAndHandleAction:` (SBFluidSwitcherViewController) sees the new dispatch, read only.
- UNCERTAIN: `SBContinuousExposeRootSwitcherModifier removalModifierForRemovalEvent:` (16.2 only, 0x1c78190f4) was not found in our sources (no `removalModifierForRemovalEvent` hit). It is chain-wide, not per display, and the main display already works, so I did not treat it as a cause. `SBFluidSwitcherRootSwitcherModifier removalModifierForRemovalEvent:` (16.0 0x1c61e894c / 16.2 0x1c7676f80) is identical.

## 6. What stays uncertain

1. That the main display's controller returns `nil` for `objectForKey:leaf` (the ivar at +0xee0 in 16.2) when the layout is external. Supported by the log (no type 15 on ANY chain, including the main one) but not read from a device.
2. That nothing else on the external path (touch routing, `supportsKillingOfAppLayout`, `appLayoutsForSwitcherController:` membership at the time of the call) fails after this fix; the verification log lines in section 5 will show.
3. `_performSceneDestructionForModelRemovalResults:` reads the ACTIVE display's `_currentAppLayout` / `_currentFloatingAppLayout` at entry in both versions (not changed in 16.2), so there is nothing to port there; effect on a removal of an external-display layout while the pointer is on the main display is the same as on stock 16.2.
