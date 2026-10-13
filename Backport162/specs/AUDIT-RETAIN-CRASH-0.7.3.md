# AUDIT-RETAIN-CRASH-0.7.3: SpringBoard SIGSEGV in objc_retain / objc_release on a freed modifier (tap on a strip title, pointer crossing between displays)

Status: root cause found in the 16.0 disassembly and fixed in `G1B.x` section 0.1 (+ a second, independent bug found on the way: `G1BKit.h` `G1B_INIT`, used by `G1B.x` / `G1C.x`).
Evidence: crash records `c3e82660-Backport162.crash` (9 entries) and `6e36f52e-Backport162.crash` (4 entries), builds d89e4f3 and 0c1bc38; debug logs `99449bc8` / `8394d5ce`.
Tooling: 16.0 (20A8372) dyld cache, SpringBoard image base 0x1c5e16000 (runtime slide 0x20e0b2000: `SpringBoard+0xNNN` = `0x1c5e16000 + 0xNNN`), full SpringBoard text disassembled with `ipsw dsc disass`.

## 1. Symptom, exactly

SIGSEGV (code 2) at `objc_retain+16` (entries with 0x612ec0) - the fault address is the garbage isa of a FREED object (`x0` is a plausible heap address in the nano zone, its first word is a scrambled free-list pointer).

```
 0 libobjc objc_retain
 1 SpringBoard+0x612ec0   -[SBChainableModifier enumerateChildModifiersWithBlock:]+144     retain of  x22.nextQueryModifier  (0x1c6428eb8..ec0)
 2 SpringBoard+0x61242c   -[SBChainableModifier handleEvent:]+440                           2nd enumerate = the event-forwarding enumerate (block 0x1c6428a80)
 3 ours  +0x498e0/+0x49c48 G1C_FS_Fwd1  (FullScreen floor: handleEvent: -> [super handleEvent:])      (absent when the floor is the stock HomeScreen floor)
 4 SpringBoard+0x613db8   -[SBChainableModifier _forwardEvent:toChildModifier:]+52  -> [child handleEvent:]
 5 SpringBoard+0x612aa8   forwarding block;  6 +0x612eb0 the enumerate's block call;  7 +0x61242c handleEvent: of the Stage Manager root's floor level
 8 SpringBoard+0x3d17a8   -[SBFluidSwitcherRootSwitcherModifier handleEvent:]+104
 9 ours  +0x220fc         G1C root  -handleEvent:  (%orig)
10-13                      the same four SpringBoard frames one level up (iPadOS platform root)
14 SpringBoard+0x1cb928   -[SBFluidSwitcherViewController _dispatchEventAndHandleAction:]+324
15 ours  +0x933b4         G2B tongue block around that method (oDisp)
16/17 pointer variant:  G1D_VC_PointerMoved (0x68de0) <- Group4Focus observer notification (0x5eb58) <- BP4/BP_G4 pointer coordinator <- UIKit
      finger variant:   G1B header-tap hook (0x13e68 / 0x119xx) <- SBFluidSwitcherSpaceOverlayAccessoryView itemContainerFooterView:didSelectTitleItem: (0x2f059c)
                         <- SBFluidSwitcherItemContainerFooterView _handleTapGestureRecognizer: (0x2ec7fc) <- UIKit
```

Both triggers dispatch an event of a type the 16.0 binary never sends: 37 (SBTapAppLayoutHeaderSwitcherModifierEvent, tap on a strip window title) and 38 (SBPointerCrossedDisplayBoundarySwitcherModifierEvent, pointer moves between the two displays; the debug log shows the crash right after the second "coordinator: updating active pointer display from A to B"). Type 36 (strip edge-protect tongue) behaves the same. Single-display pointer movement (log 99449bc8 18:33:47-18:34:21) never crashed: no crossing, no type-38 event.

## 2. Root cause

`-[SBSwitcherModifier _handleEvent:]` (16.0 0x1c63e8a98, SpringBoard+0x5d2a98), disassembly:

```
3e8aac  mov  x20, x0                    ; x20 = self (borrowed, never retained)
3e8ab0  x19 = objc_retain(event)
3e8ad4  objc_msgSendSuper2(...)         ; [super _handleEvent:], result unsafe-claimed and dropped
3e8ae4  x0 = [event type];  cmp x0,#0x23 ; b.hi 0x3e8b50          ; type > 35 -> default
        jump table 0x1c63e8dac, 36 entries (types 0..35); no entry targets the default exit
3e8b1c  case: x0 = [self handleXEvent:event]; claimARV; mov x20, x0       ; x20 = the handler's OWNED (+1) response
3e8b50  default: b 0x3e8b28                                              ; x20 is STILL self
3e8b28  objc_release(x19)               ; the event
3e8b2c  mov x0, x20 ; ... ; b objc_autoreleaseReturnValue                ; consumes a +1 that is owned for the cases and NOT owned for the default
```

For a type > 35 the function returns `self` through `objc_autoreleaseReturnValue` without ever having retained it: an unmatched release of the receiving modifier. 16.0 never sends such an event, so the path was dead code there. With the port's events 36 / 37 / 38 every modifier that receives the event (SBChainableModifier -handleEvent: forwards it to ALL children, depth first, then runs `[self _handleEvent:]` on each) loses one reference per event:

* G1B's `-_handleEvent:` hook did `id orig = %orig;` (ARC local, `retainAutoreleasedReturnValue` handshake: the stock `objc_autoreleaseReturnValue` sets the "+1 transferred" flag, no autorelease and no retain take place; the local is released at the end of the hook): the reference is gone immediately. (Without the handshake it would be an extra autorelease: the same loss at the next pool pop.)
* SBChainableModifier keeps its children ONLY as a flat chain: `parent.nextQueryModifier = firstChild`, every element's `nextQueryModifier` (strong, `objc_storeStrong`) = the next element, `previousContextModifier` / `parentModifier` are assign. A modifier whose only owner is its predecessor's link is therefore deallocated by the extra release while that link still points at it.
* `enumerateChildModifiersWithBlock:` (0x1c6428e30) walks the WHOLE rest of the flat chain with `x22 = [x22 nextQueryModifier]`, retaining each step. It runs once per `handleEvent:` before the forwarding enumerate, once for the forwarding itself and once more for the completed-children pass, and again at every ancestor. As soon as one element has been over-released (and freed when its iteration ends: owner link 1 + enumerate retain 1 + `_forwardEvent` retain 1 - the unmatched release - the two releases), a later step reads `predecessor.nextQueryModifier` = the freed element and `objc_retain`s it: the observed crash. Which element dies first depends on the extra owners of each class (ivars / associations), which is why the stack moves around between FullScreen floor, HomeScreen floor and AppSwitcher floor subtrees and why a crash can also show up later in unrelated code (e.g. `release` of freed memory in the window-drag code after a tongue event).
* The remaining register values of the entries (`x2`, `x3 = 0x747d8001dd127a84`, `x4` = 4..6, `x8 = ...ee0`) are leftovers of the surrounding calls and carry no information about the object.

Why the earlier "fixes" did not help: (a) G1C section 0 only replaced the RETURN value (`r == self` -> nil) after the stock body had already consumed the reference; (b) the `_newMultitaskingModifier` +1 fix addressed another (real but different) imbalance. The first crash entries with 0x612ec0 are from d89e4f3; the earlier crash records (signal 6) are other, already fixed problems.

Checked on the 0c1bc38 dylib (dis.txt): the `G1C_FS_Fwd1` frame (0x49be8) is a plain `[super handleEvent:]` with balanced retain/release; nothing in the frames releases a modifier. The over-release is entirely inside the stock `_handleEvent:`.

## 3. Fix

`G1B.x`, section 0.1, `%hook SBSwitcherModifier -_handleEvent:` (group G1B_Base): for every event type > 35 the 16.0 body is NEVER run; the hook does what 16.2 itself does (16.2 0x1c7895274): `[super _handleEvent:]` (SBChainableModifier: returns nil, result discarded), then the handler's result (`handleContinuousExposeStripEdgeProtectTongueEvent:` / `handleTapAppLayoutHeaderEvent:` / `handlePointerCrossedDisplayBoundaryEvent:` when the modifier implements it and G1B is on) or nil. Independent of the feature switches (the stock body is wrong for these types with or without our handlers). Types <= 35 call `%orig` exactly as before. Debug log (BP_LogEnabled, first 40): `g1b: _handleEvent: type 38 on <class> -> <handler|no handler, nil> (the 16.0 body is skipped ...)`.
`G1C.x` section 0 (`G1C_EventDefault`) stays as the last-line guard (`r == self` -> nil, logged); its comment now states the real cause. No feature is switched off; the handlers of 36 / 37 / 38 are unchanged.

## 4. Second bug found while mapping the old entry (crash record pid 92376, objc_release <- G1C_Setup+203504)

`G1C_Wdd_AddItem` (`_appLayoutByAddingItem:toAppLayout:size:center:`, 0x4f58c is its caller G1C_Wdd_Gesture) crashed in `release(x27)` where x27 is the `[SBAppLayout alloc]` temporary. `-[SBAppLayout initWithItems:centerItem:floatingItem:configuration:itemsToLayoutAttributes:centerConfiguration:environment:hidden:preferredDisplayOrdinal:]` (16.0 0x1c628a6c0) INTERNS layouts: at 0x1c628aaf4..ab28 it takes `@synchronized(sCache) { x26 = [sCache member:self]; if (!x26) [sCache addObject:self]; }` and returns the cached equal instance, releasing the freshly allocated `self` (it is the only init in the whole SpringBoard text that calls `member:`; scan of every `-[X init*]`). Our call was `((id (*)(id, SEL, ...))objc_msgSend)([alc alloc], ini, ...)`: ARC does not know that init consumes its receiver and releases the `[alc alloc]` temporary after the call (verified in the arm64 output: `retainAutoreleasedReturnValue(result); release(temp)`), so every drag that produces a layout that already exists double-released the dead alloc.
Fix: new `G1B_INIT(argtypes...)` in `G1BKit.h` (`ns_returns_retained` + `ns_consumed` first parameter: the ARC contract of an init method, compiled and checked with clang for arm64-apple-ios), used at the two SBAppLayout alloc sites: `G1B.x` `G1B_FilterAppLayoutForChamois` and `G1C.x` `G1C_Wdd_AddItem`. Every other `[cls alloc]` + cast-init site in the tree builds a class whose init returns `self` (balanced under the old pattern, see AUDIT-MEMORY-0.6.2 section 4); `G1B_INIT` is correct for all inits and can be used anywhere.

## 5. Re-audit (same pattern: a dead 16.0 path reached by a 16.2-only value, and the ARC init contract)

* Stock `-[... _handleEvent:]` implementations with the "saved self returned through autoreleaseReturnValue" shape (scan of all 16.0 ObjC methods that contain a jump table, keep a copy of x0 in a callee-saved register and return it via `objc_autoreleaseReturnValue`): `-[SBSwitcherModifier _handleEvent:]` (fixed) and `-[SBDodgingModifier _handleEvent:]` (same code shape; the port never sends it an event, dodging types are 0..5).
* Consumers of `[event type]` / `[response type]` in the 16.0 text (all 261 call sites of the `type` stub filtered by the switch shape): only `-[SBSwitcherModifier _handleEvent:]` (events, fixed) and `-[SBFluidSwitcherViewController _performEventResponse:]` (responses 38 / 39 / 40 of the port take the default 0x1c5fe2258: walks the child responses, `x19` retained and released correctly: OK). `canLogEvent:` / `verifyInternalIntegrityAfterHandlingEvent:` compare against fixed types only. `-[SBFluidSwitcherRootSwitcherModifier _handleEvent:]` (0x1c61e77ec, the platform / CE roots) is `[super _handleEvent:]` + `_updateTransientlyVisibleSlideOverTongueModifierWithEvent:` and returns the super result owned: OK (it reaches our hook through `[super _handleEvent:]`).
* Inits that return another instance: SBAppLayout only (see 4). Inits implemented by our own C functions / blocks are not consuming self but return it through ARC's retain + autorelease: net balanced (AUDIT-MEMORY-0.6.2 section 4), unchanged.
* id-returning send helpers aimed at non-object selectors: scripted check of every `G1B_Send0/1`, `G1C_Send2`, `BP2B_Obj*`, `BP_G2_Obj*`, `G4B_Obj*`, `BP_G3B_Send*` call with a literal selector against the 16.0 and 16.2 class dumps: no scalar / void selector (the only hits, `reason` and `handleEvent:`, are id-returning on the receivers used).
* Chain surgery hazards (checked, NOT the cause, nothing changed): `_removeChildModifier:` relinks through `previousContextModifier`, `performTransactionWithTemporaryChildModifier:` splices the argument into the receiver's chain (sets parent, then clears it and marks it state 1) - every call site passes a fresh or per-transition modifier (`[ce copy]`, override-ids modifiers, the H2G copy), none a modifier that is also a permanent child elsewhere.

## 6. Not changed, found on the way (needs a decision, no crash relation)

`G1C_Setup` calls `G1C_InstallHomeScreen()` BEFORE `G1C_BuildFloors()`, which is the only place that sets `gHsParent`: the in-place 16.2 conversion of `SBHomeScreenContinuousExposeSwitcherModifier` (HomeScreen floor + Strip child) returns at its first line and never runs (the debug log has "strip: 74 methods converted ... FullScreen" but no "strip(home)" line; the live tree dump shows the stock `GridLayout` + `HomeScreen` children and no Strip). Moving `G1C_BuildFloors()` before `G1C_InstallHomeScreen()` would activate code that has never executed on a device, so it was left alone here.

## 7. What to test on the device (debug log on)

1. Connect the external display, move the pointer from the iPad onto it and back, several times, with and without app windows open: no crash; log shows `g1b: _handleEvent: type 38 on SBContinuousExposeRootSwitcherModifier ... ` style lines (one per modifier of both trees) and no `GUARD` line from G1C section 0.
2. Tap a window title in the strip (single window: pulse; multi window: App Expose): type 37 lines, no crash.
3. Open / close windows, drag a window from the strip onto the stage and drop it on a window group it already belongs to (the SBAppLayout interning path), repeat.
4. Leave SpringBoard idle after the above for a few minutes (a freed modifier would have crashed the next event).
