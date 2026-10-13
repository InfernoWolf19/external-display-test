# ROUTING-162-0.7.4: SBRoutingSwitcherModifier 16.0 -> 16.2 and why a split layout is safe

Static analysis (annot3.py / annot162.py, whole class diffed method by method and block by block). 16.0 = 20A8372 (0x1c609cee8..0x1c60b1dd0), 16.2 = 20C65 (0x1c7520028..0x1c7536214).
Code: G1B.x section 1.1b (group `G1B_Routing162`, kill switch `g1b_routing162`, under the G1B master). The window-drag / peek filtering modifier is G1B.x section 1.1.

## 1. What 16.2 does NOT change (the part the old workaround got wrong)

Identical instruction sequences, callees and constants: `initWithModifiers:delegate:`, `didMoveToParentModifier:`, `handleEvent:` (+block), `_lastIndexForModifier:` (160 0x1c60b18f4 = 162 0x1c7535d38),
the helpers `_SBRoutingSwitcherModifierRouteToModifier` / `...ContainingAppLayout` / `...ContainingIndex` (160 0x1c609d860 / 0x1c609ddec / 0x1c609f440 = 162 0x1c75209ec / 0x1c7521034 / 0x1c752236c,
ContainingIndex still raises "%@ with delegate %@ couldn't find a modifier among (%@) for index %lu", `NSAssertionHandler handleFailureInFunction:file:lineNumber:description:`, line 0x52d), every index based
forward (backgroundOpacityForIndex:, maskedCornersForIndex:, opacityForLayoutRole:inAppLayout:atIndex:, shadowOpacityForLayoutRole:atIndex:, fullyPresentedFrameForIndex:frame:, ...), and the
filtering modifier's delegate methods (event 0x1c77f0d48, filteredAppLayouts 0x1c77f1084 + blocks, modifierForAppLayout 0x1c77f12ac, animation attributes 0x1c77f13d8; all match G1B.x).
So 16.2 has no special mapping for a split layout. The mapping is the same as 16.0's and it works because of WHAT it is applied to:

* `_lastIndexForModifier:` = `indexOfObject:` of the child's LAST filtered layout in `[super appLayouts]`; NSNotFound = "owns nothing" (skipped); ContainingIndex walks the children in order, child i owns (L(i-1), L(i)].
* `-[SBAppLayout isEqual:]` is identity (160 0x1c5e31cac) but SBAppLayout instances are interned (init returns the equal instance from a global NSHashTable, 160 0x1c628ab00) and
  `-appLayoutWithItemsPassingTest:` (160 0x1c5e4ab78) returns self when every item passes.
* `[super appLayouts]` is the view controller's context list = `_cachedAdjustedAppLayouts` (162 getter 0x1c72a33a8, written by `_rebuildCachedAdjustedAppLayouts` 0x1c7457028 from
  `[modifier adjustedAppLayoutsForAppLayouts:unadjusted]`; 160 0x1c5e30f3c / 0x1c5fddcd0, same ivar), the list that already contains the halves, ordered [content halves, passthrough halves]
  (routing `adjustedAppLayoutsForAppLayouts:` 160 0x1c609e6c8 concatenates in child order). Filtering a split list again is the identity, every child's last layout is found, and the indices the
  view controller derives from that list (162 `_applyStyleToAppLayout:` block 0x1c744e5c4: `[[self appLayouts] indexOfObject:layout]`) land on the right child.
  Example drag: stage [R,S,D], D dragged, list [stage, A, B] -> adjusted [D, [R,S], A, B]; content last = D (idx 0), passthrough last = B (idx 3); idx 0 -> content, idx 1..3 -> passthrough sub 0..2.
* Layout based queries use `modifierForAppLayout:` (any item in the set -> content) on the same list: a half is entirely in or out, consistent.

Consequence: the split `appLayoutWithItemsPassingTest:` result is the straight 16.2 behaviour, the content modifier of a window drag only sees (and moves) the dragged window.
The old workaround (route a mixed layout WHOLE to the content modifier) was removed from `G1B_Filtering_FilteredLayouts`; it made the content modifier lay out the whole stage.

## 2. What 16.2 DOES change (ported, `g1b_routing162`)

| 16.2 | 16.0 | port |
|---|---|---|
| NEW `-_currentModifierOrFallback` 0x1c7520e8c: `_currentModifier ?: [delegate fallbackModifierForRoutingModifier:self]` | none | `class_addMethod` |
| `-appLayouts` 0x1c7520b44 looks up `_currentModifierOrFallback` | 0x1c609d9b8 `_currentModifier` (nil outside a routed call -> nil) | hook: current := fallback around `%orig` when nil |
| `-containerViewBounds` 0x1c7520d64 / `-switcherViewBounds` 0x1c7520df8 pass `_currentModifierOrFallback` to the delegate | 0x1c609dbc4 / 0x1c609dc40 pass the raw `_currentModifier` | replaced |
| delegate `fallbackModifierForRoutingModifier:`: Filtering 0x1c77f144c -> passthrough; Main router 0x1c7489128 -> its home screen modifier ivar; PeekSplit router 0x1c74e8ac4 -> its scroll modifier ivar | not in the 16.0 protocol | Main / PeekSplit: `class_addMethod` (forward to `homeScreenModifierForRoutingModifier:` / `scrollModifierForRoutingModifier:`, same ivars in 16.0 0x1c600e0f0 / 0x1c606714c); Filtering already had it |
| `_SBRoutingSwitcherModifierSubIndexFromIndexForModifier` 0x1c752fccc (only caller: block of `shouldAnimateInsertionOrRemovalOfAppLayout:atIndex:` 0x1c752fc60): offset = last+1 of the last preceding child whose last index < index | 0x1c60ac784: offset = sum of (last+1) over the preceding children | `shouldAnimateInsertionOrRemovalOfAppLayout:atIndex:` replaced (ContainingAppLayout + new SubIndex) |
| debug descriptions list only children whose delegate is the routing modifier (0x1c7520304, 0x1c752045c) | all children | not ported (debug text) |
| 13 new routed queries | - | G1C.x section 0b (already) |

## 3. The one case the design does not cover (identical in 16.2) and the guards

The context list still holds the UNSPLIT mixed layout while the filter is on the root: the cached adjusted list is rebuilt after the model changed (add-window pick: the picked app is merged into the peeked stage,
`g3c_endpeek`, while the peek filter is still on the root until phase 3). Neither half is an element, both children answer NSNotFound, ContainingIndex asserts
(crashes 0ee042c2, 7355cddc, c4bbd19b: "couldn't find a modifier among ((passthrough: 9223372036854775807), (peek content: 9223372036854775807)) for index 0"). 16.2 never gets there
(the peek is gone first); we do, so two last-line guards exist, both logged, both only reached where stock code throws, neither changes a faithful answer:

1. `-_lastIndexForModifier:` hook: only for a routing modifier whose delegate is a filtering modifier, only when the faithful lookup answered NSNotFound although the child has layouts: the index
   of the context layout that the child's last half was cut from (the child's filter applied to that layout gives that very interned half). Log `g1b: routing162 guard: last layout of ... taken from layout N`.
   For the merged stage this assigns index 0 to the content child, exactly what `modifierForAppLayout:` answers for that layout.
2. `NSAssertionHandler handleFailureInFunction:file:lineNumber:description:` hook: the "couldn't find a modifier among" assertion of SBRoutingSwitcherModifier.m returns instead of raising. The code after
   the call is the assertions-disabled path (160 0x1c609f70c: `_currentModifier` = nil, block runs with a nil modifier, answers 0/nil/NO, `_currentModifier` restored). Log `g1b: routing162 guard: no child modifier covers the index`.
   All other assertion failures are forwarded unchanged (message formatted in the hook, as in the existing `addwinnet` hook).

## 4. Uncertain

* Which exact transient puts the unsplit layout into the cached adjusted list is inferred (the crash message + `in _appLayouts=0` log), not traced on the device.
* The fallback behaviour of `appLayouts` outside a routed call (classic Main / Split View peek routers now answer the fallback child's list instead of nil) is 16.2's, not tested on 16.0 classic mode.
