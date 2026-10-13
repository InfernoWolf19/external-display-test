# ADDWINDOW-PICK-0.7.4: why the app picked after "Add Another Window" replaces the stage on 16.0 and joins it on 16.2

Static analysis only (no device). 16.0 = 20A8372 (`annot3.py`), 16.2 = 20C65 (`annot162.py`). Addresses of 16.0 are marked "160", of 16.2 "162".
Both functions were disassembled completely (160: 0x1c5e23430..0x1c5e25cec; 162: 0x1c72952ec..0x1c7298f18) and compared.

## 0. Answer in five lines

* The code that turns "previous stage windows + picked window" is NOT in the switcher, not in the request builders and not in the app-layout code. It is a new branch inside
  `-[SBMainDisplayLayoutStateManager _layoutStateForApplicationTransitionContext:]` (162 0x1c72952ec): the **end-of-peek branch**, 162 0x1c7296020..0x1c7296f6c (entry condition at 0x1c7295ffc..0x1c7296030).
* It runs when: chamois on for the display, `ctx.requestedPeekConfiguration == 0`, previous layout state has a valid peek, request not background / source != 0xe. It mutates the transition context:
  picked entity -> role 1, then every previous entity not already in the request is put into the first free role of {2,5,6,7,8,9}, then peek := 1 (none), mode := 3.
  The layout state is then built by the unchanged main body from `ctx.entities`, so the added windows also stay activated (they are in the transaction's "to" set).
* 16.0 has no such branch. For the same input 16.0 runs the old Split View peek code (160 0x1c5e241fc..0x1c5e260e4 == the 162 code that is now only reached with chamois OFF): it can keep ONE previous window
  (prevPrimary + picked as side for peek 2, picked + prevPrimary for peek 3) and the stock `supportsSplitView` gate (160 0x1c5e24888 / 162 0x1c7297664) then collapses the pair to the picked app alone
  whenever one of the apps is `alwaysMaximizedInChamois`. Picking a multi-window stage does not enter that code at all (request taken as is) - which is the "stage replaced by Docs&Reynard" case.
* Port: hook the 16.0 method, do exactly the 16.2 ctx mutation BEFORE `%orig` (previous entities -> free roles, picked -> role 1), set `ctx.requestedPeekConfiguration = 1` for the duration of `%orig`
  (this makes 16.0 skip its legacy peek code through its own "explicit none" path, 160 0x1c5e2418c) and verify peek == 1 / mode == 3 on the result. New kill switch `g3c_endpeek`.
* Everything else that reads the peek (coordinator begin/end, gesture transaction, peek modifiers, `_isGoingToHomeScreenForTransitionRequest:`, `cancelAnyPeekToHomescreenFromSource:`) is identical or already ported.

## 1. The 16.2 mechanism, decoded (addresses 162)

Variables used below (register / stack slot in 0x1c72952ec): `ctx` = arg (sp+0x190), `prev` = `[ctx previousLayoutState]` (sp+0x160), `A` = activating entity (sp+0x138), `E1..E4` = `[ctx entityForLayoutRole:1..4]`,
`prevPeek` = `[prev peekConfiguration]` read once at 0x1c72955b0 (sp+0x78), `reqPeek` = `[ctx requestedPeekConfiguration]` (sp+0x128), `reqMode` (sp+0x180), `chamois` (sp+0x188) =
`[[self _switcherControllerForDisplayIdentity:[[ctx request] displayIdentity]] isChamoisWindowingUIEnabled]` (0x1c72953d4). Roles (const table 0x1c7a93390): 0 none, 1 Primary, 2 Side, 3 Floating, 4 Center,
5 AdditionalSideRangeMin (0x1c7a933b8), 0x19 AdditionalSideRangeMax. `_SBLayoutRoleIsValidForSplitView` (0x1c7894a30) is true for {1,2,5..9}. `_SBLayoutRoleEnumerateValidRoles` (0x1c789491c) calls its block for 1,2,4,5,6,7,8,9 and then 3.

```
0x1c7295398  if ([ctx isBackground] || [request source] == 0xe) -> 0x1c7295714   (separate background path, not touched)
0x1c72953e0  A = [ctx activatingEntity]; E1..E4 = entityForLayoutRole:1..4
0x1c7295470  if (!A && E1 && !E2 && !E3) { A = E1; E1 = nil; }                  // single-entity request: it becomes the activating entity
0x1c72954bc  req* = requestedSpace/Center/Floating/Peek/UnlockedEnvironmentMode/... ; prev* = previousEntityForLayoutRole:1..4, prev state space/floating/center/peek/mode
0x1c72955f8..0x1c7295960  chamois && E4 present: E4 moved to the first free valid role (block 0x1c76f2904)       (same in 160, 0x1c5e23810)
0x1c7295ffc  reqPeekValid = _SBPeekConfigurationIsValid(reqPeek)                  // 0x1c77229fc: (cfg & ~1) == 2
0x1c7296008  if (!chamois) goto 0x1c729612c                                       // LEGACY (Split View / slide over) code, 0x1c7296168..0x1c7296c20
0x1c7296014  if (reqPeekValid && !_SBPeekConfigurationIsValid(prevPeek)) goto 0x1c72961cc   // START of a peek: mode = 1 + (recents.count >= 2), peek = req   (already ported, G3C)
0x1c7296020  if (reqPeek != 0 || !_SBPeekConfigurationIsValid(prevPeek)) goto 0x1c729646c    // generic: peek := 1 (none), nothing merged
             ------------- END-OF-PEEK BRANCH (chamois, reqPeek == 0, prevPeek valid) -------------
0x1c7296044  entities = [ctx entities]; prevEntities = [ctx previousEntities]            // both NSSet
0x1c7296068  if (_BSEqualSets(entities, prevEntities)) {                                  // case 1: request == previous stage
0x1c729607c      for (E in prevEntities) [ctx setEntity:E forLayoutRole:[E layoutRole]];   // restore
0x1c72963ac      peek stays prevPeek (x24 = [sp+0x78] at 0x1c72963bc) -> tail 0x1c7296f6c   // the peek is kept
             }
0x1c72962c0  E1x = (E1 ? E1 : [SBPreviousWorkspaceEntity entity]) (sp+0x148);  real(x) := x && !x.isEmptyWorkspaceEntity && !x.isPreviousWorkspaceEntity
0x1c72962c8  if (!real(E1x) && !real(A)) {                                               // case 2: nothing real in the request
0x1c7296300      restore previousEntities as in case 1; peek stays prevPeek; -> 0x1c7296f6c
             }
0x1c729660c  if ([A isHomeScreenEntity]) {                                               // case 3: Home pressed while peeking (A may be nil -> NO)
                 if (prevMode != 2) { reqMode = 1; peek := 1 (leave peek, plain Home)           // 0x1c7296c20 -> 0x1c7296f48
                 } else { restore previousEntities; [ctx setActivatingEntity:nil]; reqMode = 1; peek stays prevPeek }   // 0x1c7296624..0x1c72966f0: switcher peek -> home screen peek
             }
0x1c7296908  // case 4: THE PICK
             if (real(A))        [ctx setEntity:A forLayoutRole:Primary(1)];                          // 0x1c7296d70
             else if (E1x)       [ctx _setRequestedFrontmostEntity:E1x];                              // 0x1c729693c   (multi-window pick: request already has roles 1/2/..)
0x1c7296da4  for (E in [ctx previousEntities]) {                                          // NSSet order, not sorted
                 if (E.isHomeScreenEntity || E.isPreviousWorkspaceEntity || E.isEmptyWorkspaceEntity) continue;      // 0x1c7296e1c..0x1c7296e38
                 if ([[ctx entities] containsObject:E]) continue;                                                      // 0x1c7296e40..0x1c7296e64
                 role = first role r in enumeration order 1,2,4,5,..,9,3 with IsValidForSplitView(r) && (!entityForLayoutRole:r || it.isEmptyWorkspaceEntity)   // block 0x1c76f2bb8, called via 0x1c7296ed0
                 if (role != 0) [ctx setEntity:E forLayoutRole:role];                                                  // 0x1c7296eec   (no free role: window dropped silently)
             }
0x1c7296f40  reqMode = 3 (overrides the request's mode); newPeek = 1 (none)  -> tail
0x1c7296f6c  tail: E1 = [ctx entityForLayoutRole:1] (or EmptyWorkspaceEntity), E2 = role 2, E3/E4 = Empty; -> generic main body (0x1c7297054..)
```

Why this yields "previous windows + picked":
1. The request of a switcher-card tap / icon / dock launch contains only the picked entity (role 1 and/or activatingEntity) or a picked multi-window stage (roles 1,2,..). The previous stage lives in `ctx.previousEntities`, which the wrapper
   `-[SBLayoutStateManager layoutStateForApplicationTransitionContext:]` (162 0x1c7294ac8, 160 0x1c5e22c0c, identical) fills for ALL valid roles from the previous layout state (block 162 0x1c7703940) before calling the underscore method.
2. The branch copies the previous entities into free roles of the SAME ctx. The main body (identical in 160/162, see section 2) writes roles 1-4 back (162 0x1c7298174..0x1c72981bc), builds `SBLayoutElement`s for roles 1,2, all additional roles (block 162 0x1c76f2ef8 over
   `_SBLayoutRoleEnumerateValidRoles`) and floating/center, and finally builds the state from `[ctx entities] bs_map:` (162 0x1c7298a48..0x1c7298b8c, 160 0x1c5e25914..0x1c5e25ac8). So roles 5..9 become stage elements 3,4,...
3. Because the entities are in the ctx, `toApplicationSceneEntities` of the request contains them and the transaction does not deactivate the previous windows.
4. Result: elements = [picked (role 1), previous#1 (role 2), previous#2 (role 5), ...], peek 1, mode 3. The picked multi-window stage case: request roles 1,2 stay, previous windows go to 5,6,... -> stage grows to 3/4.
   The 4-window cap is not enforced in this function (7 free roles); I did not find where (if) a cap exists; the type-12 menu item is the only entry that can create a 5th window.

Candidates from the task, checked and ruled out as the mechanism:
* Switcher side: `+[SBSwitcherTransitionRequest requestForTapAppLayoutEvent:]` (162 0x1c740d6fc) sets appLayout + `activatingDisplayItem` (+ source 0x33 when event.source==1); `-[SBMainSwitcherControllerCoordinator _configureRequest:forSwitcherTransitionRequest:withEventLabel:]`
  (162 0x1c76d174c, 160 0x1c623e164) only converts env 2 -> 1, copies `activatingDisplayItem` into `setActivatingEntity:` (+ keyboard-focus completion) and applies `setEntities:withPolicy:` with `request.entityInsertionPolicy` (0 default; 1 only from shift-click on a strip card in
  `SBFullScreenContinuousExposeSwitcherModifier handleTapAppLayoutEvent:`). Neither adds previous windows. Both are already in G1C/G1D except the insertion policy (see (e)).
* `_isGoingToHomeScreenForTransitionRequest:` (162 0x1c784d004), coordinator begin/end (162 0x1c76c9354 / 0x1c76cb178), `cancelAnyPeekToHomescreenFromSource:` (162 0x1c76cd560): call sequences identical to 160.
* Callers of `_SBPeekConfigurationIsValid` / `peekConfiguration` / `toPeekConfiguration`: the 160 and 162 sets are the same up to renames (160 `completeGestureWithTransitionRequest:` = 162 `handleTransitionRequestForGestureComplete:fromGestureManager:`, 160 ContinuousExposeRoot floor/transition = 162 `handleTransitionEvent:`,
  160 Medusa-VC "not supported" checks = 162 `SBFullScreenSwitcherLiveContentOverlayCoordinator`). Genuinely new in 162: `-[SBContinuousExposePeekSwitcherModifier handleTransitionEvent:]` (0x1c78e5410) and `-[SBHomeScreenContinuousExposeSwitcherModifier responseForProposedChildResponse:childModifier:event:]` (0x1c77f393c)
  (both ported in G1C), `-[SBSwitcherController _presentMedusaBanner:fireInterval:dismissInterval:]` (banner only). The only model-level peek consumer that changed is the layout-state manager.

## 2. The 16.0 behaviour and where it differs

160 `_layoutStateForApplicationTransitionContext:` 0x1c5e23430. Same prologue/role reads as 162 (0x1c5e234e4..0x1c5e23664; initial `[prev peekConfiguration]` at 0x1c5e236dc -> sp+0xa8, later direct reads of the previous state's peek at 0x1c5e24d00 and 0x1c5e24f6c
exist in 162 too: 0x1c7297bf0, 0x1c7297ed0).

| step | 160 | 162 |
|---|---|---|
| requested peek valid (type-12 request) | 0x1c5e240e8: `if (elements.count > 1 && chamois) { peek = none; mode = prev mode }` (the "no-op for 2+ windows") | no element-count test; start-of-peek branch 0x1c72961cc (mode `1 + (recents >= 2)`) - ported in G3C |
| requested peek == 1 | 0x1c5e2418c: `w25 = 1` (peek none), request roles as is | chamois: 0x1c7296020 -> 0x1c729646c (same) |
| requested peek == 0, prev peek valid, chamois | falls into the LEGACY peek merge 0x1c5e241fc..0x1c5e260e4 | **END-OF-PEEK BRANCH** 0x1c7296020..0x1c7296f6c (section 1); legacy only for chamois OFF (0x1c729612c, 0x1c7296168..0x1c7296c20) |
| everything after (roles -> elements -> state, supportsSplitView gate, mode rule, `setEntities:withPolicy:` write-back) | identical shape (160 0x1c5e24888/0x1c5e248f4, 0x1c5e258e4..0x1c5e25ac8) | 162 0x1c7297664/0x1c72976c8, 0x1c729896c..0x1c7298b8c |

Legacy merge (identical code in both, decoded from 162 0x1c7296168..0x1c7296c20; 160 0x1c5e241fc..0x1c5e260e4 has the same shape):
```
if (prevPeek valid && A && !A.isHome && reqMode != 2) {            // A nil (multi-window pick) -> generic path, request is used AS IS: [Docs,Reynard] replaces [Filza]
    w19 = prevPrimary real && !prevSide.isEmpty (nil counts as non-empty!);  w20 = prevSide real;  w21 = prevFloating real
    if (w19 | w20) {                                                // true for ANY previous stage with a primary (1 window too: prevSide is nil)
        prevPeek == 3: primary = A, side = prevPrimary;  prevPeek == 2: primary = prevPrimary, side = A;  else primary kept, center = Empty; peek := 1
    }
}
```
Only the previous PRIMARY survives (the 2nd..4th previous windows are lost by construction). Then the shared gate (162 0x1c7297660 / 160 0x1c5e24888): `if (!side.isEmpty && !(primary.supportsSplitView && side.supportsSplitView)) { if ([side isEqual:A]) primary = side; side = Empty }`.
`-[SBDeviceApplicationSceneEntity supportsSplitView]` (162 0x1c74e42c8 = 160 0x1c6062af8) = `[app supportsMultiWindowLayoutsForSwitcherWindowManagementStyle:displayIdentity:]` (162 0x1c75f6c64 = 160 0x1c616ef84), which for style 2 (Stage Manager) is `!alwaysMaximizedInChamois`.
This reproduces both reported logs: `from=[Docs&Reynard] to=[Filza]` -> legacy merge gives primary Docs, side Filza, the gate collapses it ("side isEqual A -> primary = Filza, side = Empty") and the result is Filza alone, peek 2 -> 1;
`from=[Filza] to=[Docs&Reynard stage]` -> A nil, no merge, request as is.
Honest limit: I cannot prove statically WHICH of the two (gate collapse vs. the legacy path not being reached because e.g. `requestedUnlockedEnvironmentMode == 2` at 0x1c5e24220) happened on the device; both are bypassed by the port below.
If it is the gate: it exists identically in 16.2, but there it only looks at roles 1 and 2 (the added windows in roles 5+ survive), so a picked `alwaysMaximizedInChamois` app would still collapse role 2 in 16.2.

## 3. Port plan (Logos / ObjC, file G3C.x, group G3C_Peek, same hook as the start-of-peek correction)

Hook: `%hook SBMainDisplayLayoutStateManager - (id)_layoutStateForApplicationTransitionContext:(id)ctx` (already there). Add, BEFORE `%orig`:

```objc
// all selectors exist on 16.0: ctx = SBWorkspaceApplicationSceneTransitionContext (entities/previousEntities come from SBWorkspaceTransitionContext)
@interface NSObject (BPG3CEnd)
- (id)activatingEntity;  - (void)setEntity:(id)e forLayoutRole:(long long)role;  - (id)entityForLayoutRole:(long long)role;
- (void)_setRequestedFrontmostEntity:(id)e;  - (id)entities;  - (id)previousEntities;  - (void)setRequestedPeekConfiguration:(long long)c;
- (BOOL)isBackground;  - (long long)source;  - (long long)layoutRole;
- (BOOL)isHomeScreenEntity;  - (BOOL)isPreviousWorkspaceEntity;  - (BOOL)isEmptyWorkspaceEntity;
@end
static BOOL G3C_Real(id e) { return e && ![e isEmptyWorkspaceEntity] && ![e isPreviousWorkspaceEntity]; }
static BOOL G3C_EndPeekPick(id self, id ctx) {                 // returns YES when the ctx was merged; mirrors 162 0x1c7296020..0x1c7296f40, case 4 only
    if (!BP_OnName("g3c_endpeek") || !ctx) return NO;
    id rq = [ctx request];
    if ([ctx isBackground] || [rq source] == 0xe) return NO;                                       // 0x1c7295398
    if (!chamois(self, rq)) return NO;                                                              // existing code of the start-of-peek correction
    id prev = [ctx previousLayoutState];
    if (!prev || !G3C_PeekValid([prev peekConfiguration]) || [ctx requestedPeekConfiguration] != 0) return NO;   // 0x1c7295ffc..0x1c7296030
    NSSet *ents = [ctx entities], *pents = [ctx previousEntities];
    if ([ents isEqualToSet:pents]) return NO;                                                       // case 1 (not ported, see (e))
    id A = [ctx activatingEntity], E1 = [ctx entityForLayoutRole:1], E2 = [ctx entityForLayoutRole:2], E3 = [ctx entityForLayoutRole:3];
    if (!A && E1 && !E2 && !E3) { A = E1; E1 = nil; }                                               // 0x1c7295470
    if (!G3C_Real(E1) && !G3C_Real(A)) return NO;                                                   // case 2 (not ported)
    if (A && [A isHomeScreenEntity]) return NO;                                                     // case 3 (not ported)
    if (G3C_Real(A)) [ctx setEntity:A forLayoutRole:1];                                             // 0x1c7296d70
    else if (E1)     [ctx _setRequestedFrontmostEntity:E1];                                         // 0x1c729693c
    NSArray *prevs = [[pents allObjects] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) { long long x = [a layoutRole], y = [b layoutRole]; return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame; }];
    static const long long kRoles[] = { 1, 2, 5, 6, 7, 8, 9 };                                      // enumeration order of the 162 block 0x1c76f2bb8 filtered by IsValidForSplitView
    for (id e in prevs) {
        if ([e isHomeScreenEntity] || [e isPreviousWorkspaceEntity] || [e isEmptyWorkspaceEntity]) continue;
        if ([[ctx entities] containsObject:e]) continue;
        for (size_t i = 0; i < sizeof kRoles / sizeof *kRoles; i++) {
            id cur = [ctx entityForLayoutRole:kRoles[i]];
            if (!cur || [cur isEmptyWorkspaceEntity]) { [ctx setEntity:e forLayoutRole:kRoles[i]]; break; }
        }
    }
    return YES;
}
```
In the hook:
```objc
BOOL merged = G3C_EndPeekPick(self, ctx);
long long savedReq = merged ? [ctx requestedPeekConfiguration] : 0;
if (merged) [ctx setRequestedPeekConfiguration:1];            // 160 0x1c5e2418c: "explicit none" -> w25 = 1, legacy block skipped (also reproduces 162's peek := 1)
id r;
@try { r = %orig; } @finally { if (merged) [ctx setRequestedPeekConfiguration:savedReq]; }     // ctx is left as in 16.2 (reqPeek untouched)
if (merged && r) { /* last-line guard: expect [r peekConfiguration] == 1 && [r unlockedEnvironmentMode] == 3; else copy via _initWithLayoutState: + ivar writes (code already in this hook) and BP_Log */ }
```
Why `requestedPeekConfiguration = 1` and not an override of `-[SBMainDisplayLayoutState peekConfiguration]`: 160 and 162 both read the previous state's peek DIRECTLY a second/third time (160 0x1c5e24d00, 0x1c5e24f6c; 162 0x1c7297bf0, 0x1c7297ed0: skips the app-expose / ambiguous-launch logic while peeking). Those must keep seeing the real peek to stay equal to 16.2,
so only the first snapshot (legacy gate) may change, and the explicit-none request does exactly that. Alternative (B) if (A) shows side effects: thread-local "first `peekConfiguration` read of `prev` during `%orig` returns 1" hook on `SBMainDisplayLayoutState`.
Pitfalls:
* Mutation must happen before `%orig` (the roles are read at the top of the stock method; `-[SBWorkspaceApplicationSceneTransitionContext layoutState]` caches the first result, 162 0x1c72949a8 - so the merge happens once; a second call is idempotent anyway because the previous entities are then already contained).
* No ARC problem: `ctx`, `ents`, `pents`, `prevs` are plain autoreleased/strong locals; `setEntity:forLayoutRole:` sets the entity's `layoutRole` (the previous entities belong to this ctx). Never call `[prev peekConfiguration]` through an `id`-returning cast; declare `long long` (as above).
* Do not mutate while iterating `pents` (we iterate a sorted array copy; `setEntity:` mutates `ctx._entities`, not `_previousEntities`).
* The previous-entity order is an NSSet order in 16.2 (unspecified). Sorting by previous role is a deliberate deterministic choice inside 16.2's behaviour (strip order later follows the stage/`lastInteractionTime`, not the role).
* Keep the existing start-of-peek correction after `%orig` (it returns early for `reqPeek` not valid, so no interaction).
* Apps that are `alwaysMaximizedInChamois` still lose role 2 in the stock gate (identical in 16.2); log `supportsSplitView` of A and of role 2 in the debug line so the device log explains a partial result.
* The coordinator end assertion "appLayouts array MUST contain the app layout" (AUDIT-ADDWINDOW-0.6.4) will now see a NEW multi-window app layout `[A, W1, W2...]` as `N`; the model add (`_addAppLayoutToFront:`, type 0) handles it as for any stage; the G1B_AddWin net stays.
* Debug line (BP_Log): `[g3c] endpeek: A=<..> E1=<..> prev=[..] -> roles {1:..,2:..,5:..} reqPeek 0->1 result elements=%lu peek=%lld mode=%lld`.
* Switch: `Backport162.off.g3c_endpeek` (BP_OnName("g3c_endpeek")). Default on.

Expected on device: peek of a 2-window stage -> pick Filza from switcher/home/dock -> stage `[Filza, Docs, Reynard]` (3 windows), peek 2 -> 1, mode 3; 1-window stage -> `[Filza, P]`; picking a 2-window stage over a 1-window peek -> `[Docs, Reynard, P]`.

## 4. Confidence per claim

| claim | basis | confidence |
|---|---|---|
| End-of-peek branch exists at 162 0x1c7296020 with entry condition chamois && reqPeek == 0 && prevPeek valid | read in disassembly (0x1c7295ffc..0x1c7296030), string "Peek configuration should not be undefined at this point" (0x1c72995a8) confirms x24 is the peek | high |
| The pick case (case 4) puts A in role 1 and previous entities into the first free role of {2,5..9}, mode 3, peek 1 | read (0x1c7296908..0x1c7296f48), block 0x1c76f2bb8 and role table decoded | high (registers traced by hand; role numbering from the symbol table and `_SBLayoutRoleIsValidForSplitView`) |
| Cases 1-3 (equal sets, nothing real, Home) semantics | read, but x24/[sp+0x78] reuse makes the "peek stays" reading inferred | medium |
| Previous entities of all roles are available in ctx.previousEntities on 16.0 | wrapper 162 0x1c7294ac8 vs 160 0x1c5e22c0c: identical call sequence; block 162 0x1c7703940 read | high |
| Main body builds elements from `[ctx entities]` incl. roles 5+ in 16.0 | 160 0x1c5e25914..0x1c5e25ac8 vs 162; additional-role block at 162 0x1c72982ec / 160 0x1c5e253b4 (not fully decoded) | medium-high |
| 16.0 runs the legacy peek merge for chamois and it can keep only the previous primary | shape-identical code in both; the 160 register map of the legacy block was NOT fully traced, the 162 non-chamois block was | medium |
| The reported `[Filza]` results are the legacy merge + `supportsSplitView` gate collapse | consistent with both logs; not provable statically (alternative: legacy not reached, e.g. reqMode == 2) | medium-low, but irrelevant for the fix (legacy is bypassed) |
| `requestedPeekConfiguration = 1` makes 16.0 skip the legacy block and set peek none | 160 0x1c5e2413c..0x1c5e24194 | high |
| `requestedPeekConfiguration` restore after `%orig` is harmless | only readers: the manager, 16.0 Medusa VC "not available yet" check, `copyMainWorkspaceTransitionRequest` | medium-high |
| No other 16.2 code (switcher/request/app layout) is involved in the merge | call-sequence comparison of the listed functions; 162 `_configureRequest` only adds insertion policy / activating entity | medium-high (every switcher function was not diffed) |
| 4-window cap | not found | unknown |

## 5. (e) Other 16.2 add-window behaviour noticed, not ported by this change

* Case 1/2/3 of the end-of-peek branch: request == previous stage or nothing real in the request keeps the peek (entities restored from `previousEntities`, peek = prevPeek); Home while peeking in the switcher (prev mode 2) turns the switcher peek into a Home-screen peek (mode 1, peek kept), Home while peeking over the Home screen leaves the peek. 16.0 ends/mangles the peek in these cases through its legacy code. Port sketch: restore previous entities pre-`%orig`, then rebuild the result with peek = prevPeek via the existing `_initWithLayoutState:` + ivar code (the explicit-none trick cannot keep a peek).
* New window size / position: the picked window has no requested attributes, so it gets the default window attributes (`-[SBSwitcherChamoisSettings layoutAttributesForContainerBounds:...]` 162 0x1c78c0f50, see AUDIT-DEFSIZE-0.6.9). Previous windows keep their frames: attributes are copied from the previous state's `elementIdentifiersToLayoutAttributes` by element id in the shared main body. The merge itself calls `_setRequestedFrontmostEntity:` only for a multi-window pick (E1); for a single pick the frontmost marker comes from the activating entity/role 1. Strip order after the merge was not decoded (roles: picked 1, others 2,5,6.. in NSSet order).
* `entityInsertionPolicy` (162 `_configureRequest` 0x1c76d21f0, shift-click on strip card sets 1): `setEntities:withPolicy:1` fills unused roles with `entityWithPreviousLayoutRole:` placeholders and, in chamois, `_setRequestedFrontmostEntity:[entities firstObject]` plus `attributesByModifyingLastInteractionTime:`. 16.0 has no such property; G1D's `_configureRequest` port does not implement it (shift-click insertion is unported).
* `-[SBMainWorkspaceLayoutStateContingencyPlan transitionContextForLayoutContext:failedEntities:]` is new in 162 (fallback transition when picked entities fail to launch): not looked at.
* `_mostRecentAppLayoutMatchingAnyUniqueIdentifier:chamoisWindowingUIEnabled:` / `_mostRecentAppLayoutForBundleIdentifier:ignoringUniqueIdentifiers:chamoisWindowingUIEnabled:` (162 0x1c76f1c40 / 0x1c76f2118): with chamois (and `_SBFIsChamoisWindowingUIAvailable`) the recents are first split with `appLayoutsBySplittingMedusaIncompatibleItemsWithApplicationController:`; 160 returns the first match. Not ported; it only affects which recent layout supplies the requested space configuration.
* Banner: `-[SBSwitcherController _presentMedusaBanner:fireInterval:dismissInterval:]` (162) reads peek validity; the gesture transaction dismisses the banner when the peek ends (162 0x1c74b08e8 `_dismissMedusaBanner`). UI only.
* Dismissal of the peek by tapping the peek content (request peek 1 via `requestForTapAppLayoutEvent:`), `cancelAnyPeekToHomescreenFromSource:` and the peek modifiers are already equal/ported (G1C).
