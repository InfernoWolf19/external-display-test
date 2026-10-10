# Backport162 0.6.0 adversarial review, area B (G1B.x, G1BKit.h, G1C.x)

Target 16.0 (20A8372) SpringBoard, arm64e. All addresses are unslid cache vmaddrs. "160" = 20A8372, "162" = 20C65.
Nothing was run on a device; every claim is from the binaries or the sources. Confidence is given per finding.
Written incrementally: sections are appended as each checklist item is finished.

Severity: CRASH / WRONG-BEHAVIOUR / MINOR.

## Ranked findings (summary, updated at the end)

| # | sev | where | one line | conf |
|---|-----|-------|----------|------|
| B1 | CRASH (default on, cross-area G2/G2B/G1C) | G1C.x:771-818 (G1C_AskRootIds + VCIds hook), G2.x:1606-1621, G2B.m:1177,1434,1471 + G2B.m:2014-2025 | The extended query protocol makes 10 16.2-only query selectors answerable on every modifier, but no 160 modifier implements them. The first send hits `SBChainableModifierMethodCache.m: couldn't find implementor for <sel>` (NSAssert). | 65% |
| B2 | WRONG-BEHAVIOUR (default on) | G1C.x:2948-3070, 3196 | `g1c_piles` changes only card frames/scales/fitted size; 160 `frameForLayoutRole:inAppLayout:withBounds:` (0x1c636a5a8) still places windows for a full-container canvas -> windows displaced out of the smaller card. And the pile modifier is only instantiated for gestures/transitions, never for the real switcher floor, so the layout snaps at hand-off. Recommend default OFF. | 70% |
| B3 | WRONG-BEHAVIOUR (regression of the documented plan) | G1C.x:3418 | `transitionModifierForMainTransitionEvent:` hook returns nil when `%orig` is nil, so the ported `SBContinuousExposeToHomeSwitcherModifier` is never created for the plain 2->1 transition. Removing SwitcherDismissFix (as INTEGRATION-NOTES/STATUS say) brings back the one-frame cut. | 90% |
| B4 | WRONG-BEHAVIOUR | G1C.x:3245-3295 (Root `floorModifierForTransitionEvent:`, case 3 at :3270) | mode 3 drops `setAppPileBundleIDToBringForwardIfAny:`/`setFullScreenAppDisplacementState:`/pile-reuse test that 160 does (0x1c63711a0-0x1c63711e4) while the 160 FullScreen class still consumes them. | 85% |
| B5 | MINOR (latent CRASH) | G1C.x:3097-3120 (`G1C_As_HeaderTap`) | `G1C_As_HeaderTap` sends unguarded `[super handleTapAppLayoutHeaderEvent:]`; `SBSwitcherModifier` has no such method in 160. Dead today (type-37 event never emitted). | 95% |
| B6 | WRONG-BEHAVIOUR | G1C.x:3324 | Root type-3 gesture is replaced by the 16.2 grid-swipe root with the BP162 pile AppSwitcher; its gesture modifier is "delayed" and has no timeout. | 40% |
| B7 | MINOR | G1C.x:3340 | `_updateFloorModifierWithGestureEvent:` is `void` in 160; return value used as `id`. Works by accident. | 70% |
| B8 | MINOR | G1C.x:1060-1070 (`G1C_InstallRevealStrips`) | Reveal strip methods installed with `class_replaceMethod` and no `G1C_ON()` check: `Backport162.off.group1c` is not a pass-through for the strip-reveal gesture. | 90% |
| B9 | MINOR | INTEGRATION-NOTES.md | Note says SDF builds `SBContinuousExposeToHomeSwitcherModifier`; SDF 0.3.0 names it `SDFContinuousExposeToHomeSwitcherModifier`. Both coexist, G1C wins, no crash. | 95% |

PASS items are listed per checklist section below.

---------------------------------------------------------------------------------------------------

## Checklist 1: runtime class creation   (PASS with notes)

* `G1B_MakeClass` (G1BKit.h:48-79): `[sup class]` first (runs +initialize of the base), `objc_allocateClassPair`, all `class_addIvar` and `class_addMethod` BEFORE `objc_registerClassPair`. PASS. Method type encodings come from the trampoline donors (`G1B_TypesFor`), so the per-class cache comparison in `+newCacheWithSelectorList:` (160 0x1c642acc0, compares `instanceMethodForSelector:` of the class against the base class) sees an override. PASS.
* Ivar alignment is log2 and used correctly (0 for BOOL, 2 for uint, 3 for 8-byte). Offsets are looked up with `ivar_getOffset`, never hard-coded. PASS.
* Query cache is per class and built at the FIRST instance `init` (0x1c642acc0), so `class_addMethod`/`method_setImplementation` after registration but before the first alloc is fine (G1C_UpgradeOverrideIds, G1C_AddLike). Reveal/Cycle/etc. get replacements at launch before any instance exists. PASS.
* `object_setIvar` on a parent's ARC ivar from a runtime subclass (G1C_SetIvarObj on `_initialAppLayout`, `_selectedDisplayItem`, `_destinationModifier`): objc4 `_class_lookUpIvar` walks to the class that declares the ivar and uses ITS ARC layout, so the store is retained. PASS. For ivars added by G1C (`_stripModifier`) the store is unretained, but that code path is dead (no `SBStripContinuousExposeSwitcherModifier` anywhere in the tree: `NSClassFromString` is nil).
* `copyWithZone:` of `SBChainableModifier` is `[[[self class] alloc] init]` (160 0x1c6429d5c): `[ce copy]` on a BP162 AppSwitcher re-runs `G1C_As_Init` (adds a Defaults child again) - harmless.
* ARE THE BP162 SUBCLASSES EVER INSTANTIATED, AND BY WHICH FACTORY?
  * `BP162AppSwitcherContinuousExposeSwitcherModifier`: only via `G1C_NewAppSwitcherModifier()` (G1C.x:1554 peek content, :2134 window-drag content, :3324 Root `gestureModifierForGestureEvent:` type 3). The persistent switcher floor is created by 160 `-[SBContinuousExposeRootSwitcherModifier multitaskingModifierForEvent:]` (0x1c6371208, plain `alloc/init` of the stock class, found with users.py) and by the type-1 gesture root (0x1c6371688); G1C hooks neither. So the tap/header/removal/tap-outside handlers and the pile layout of the BP162 class are dead for the real "all windows" switcher. (-> B2)
  * BP162 InlineAppExpose / HomeScreen: created by the hooked Root `floorModifierForTransitionEvent:` (case 1 and 3 with expose id). If G1C_ON() is off or a class is missing it falls back to `%orig` (stock class), no missing-ivar crash because all BP162 state is in associated objects or ivars added with the class.
  * BP162 WindowDrag / Destination / Root: the Root hook (type 9) builds `BP162...WindowDragRoot`; its `gestureChildModifierForGestureEvent:` builds the drag modifier through `_SBContinuousExposeWindowDragContent...` and the Filtering modifier; on any nil it falls to `[super ...]` (the 160 root's own child). OK as a pass-through fallback.
  * BP162 AppToApp / SwitcherToApp / Slide / Peek / ToHome: created only from the Root hooks (post-processing of `%orig`), so a missing factory = stock 160 object. No crash path.
* Name collisions: `SBContinuousExposeStripTongueView` exists as a compiled G2B class, G1B's run-time build is skipped (`made == NO`, all `gTv*Off == -1`), all Tv functions are unreachable. PASS.

## Checklist 2: query/context machinery   (FINDING B1 + notes)

How the 160 chain works (decoded):
* `+[SBChainableModifier _initalizeIMPCaching]` (0x1c642a6c0): on the base class of `+queryProtocol` (SBSwitcherModifier) every protocol selector that the class does not already implement gets a query trampoline (`_SBChainableModifierMethodCacheQueryTrampolineForMethod` 0x1c62acb8c); if the class already implements one it asserts "Cannot implement %@ on an implementer of +queryProtocol".
* Dispatch (`_MethodCacheDispatchDataForSelectorIndex` 0x1c62afe50): walks `nextQueryModifier` (`_nextFunc` 0x1c642aebc loads `modifier->_nextQueryModifier` ivar +0x40) to the next modifier whose class IMP differs from the trampoline. When the chain ends it uses `[cache.modifier delegate]`; if that delegate is nil it raises the NSAssert `SBChainableModifierMethodCache.m: couldn't find implementor for %@` (0x1c62aff74-0x1c62affc4). Only the root has a delegate (the VC); `setDelegate:` is never propagated to children (0x1c64281ec, `_addChildModifier:` 0x1c6429060 does not set it).
* So a query selector that is in the protocol but implemented by NO modifier in the live stack aborts SpringBoard.

### B1. CRASH (default on) - 16.2-only query selectors have no 16.0 implementer

Facts:
* G2B `kBP2B_PQry` (G2B.m:2014-2025) adds to the extended `+queryProtocol` these selectors: `activeLeafAppLayoutsReachableByKeyboardShortcut`, `canSelectLeafWithModifierKeysInAppLayout:`, `inactiveAppLayoutsReachableByKeyboardShortcut`, `shouldAllowGroupOpacityForAppLayout:`, `adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:`, `adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:`, `isContinuousExposeStripVisible`, `proposedAppLayoutForContinuousExposeWindowDrag`, `spaceAccessoryViewIconHitTestOutsetForAppLayout:`, `wantsContinuousExposeHoverGesture`.
* None of them exists in any 160 class (`grep` of sb160n_objc.txt: 0 hits for all ten). In 162 they are implemented by SBDefaultImplementationsSwitcherModifier or by every concrete floor (sb162_objc.txt: e.g. `isContinuousExposeStripVisible` on Defaults and Routing; `shouldAllowGroupOpacityForAppLayout:` on FullScreenCE, AppSwitcherCE, Deck, Grid floors ...). Nothing in the port adds them to a modifier class (grep over G1B/G1C/G2/G2B/G3/G3B/G4B: only the BP162 AppSwitcher gets the two `adjusted...` ones, and it is not in the live stack, see checklist 1). G2B's fallbacks (`BP2B_SetupProtocolFallbacks`, G2B.m:2186-2227) cover only the three selectors that are NOT in the protocol.
* Because the selectors are in the protocol, SBSwitcherModifier gets trampolines, so `[root respondsToSelector:sel]` is YES.
* Callers that guard only with `respondsToSelector:` and then send through the chain:
  * G2.x:1606-1612 `-[SBFluidSwitcherViewController _areContinuousExposeStripsUnoccluded]` -> `isContinuousExposeStripVisible` (called on every strip/layout evaluation),
  * G2.x:1615-1621 hover gesture -> `wantsContinuousExposeHoverGesture`,
  * G2B.m:1177 `shouldAllowGroupOpacityForAppLayout:` (layout), :1434 `canSelectLeafWithModifierKeysInAppLayout:`, :1471/:1524/:1565 keyboard-shortcut reachability,
  * G1C.x:771-796 (`G1C_AskRootIds`) -> the two `adjustedContinuousExposeIdentifiersIn...` selectors on EVERY `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:...` (app launch/switch/close in Stage Manager). The "root does not answer" fallback at G1C.x:797-805 is only taken when `respondsToSelector:` is NO, i.e. NOT when the protocol extension succeeded.
Scenario: Stage Manager on, `BP2B_Early` succeeded (default), launch any app -> VC calls `_updateContinuousExposeIdentifiers...` -> G1C hook -> `objc_msgSend(root, adjustedContinuousExposeIdentifiersInStrip...)` -> trampoline -> no modifier overrides -> last modifier has no delegate -> NSAssert `couldn't find implementor for adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:` -> uncaught exception, SpringBoard dies (respring loop if it happens at launch with apps already in the layout state).
Not proven: the identity of the LAST modifier in the 160 CE stack and that its delegate is nil (children never get a delegate, so almost certainly nil); and that the Root's own class has no implementer. If BP2B_Early auto-disabled (breadcrumb) or `g2bproto` is off, `respondsToSelector:` is NO and none of this triggers. Confidence 65%.
Fix options (pick one, smallest first):
```diff
--- a/Backport162/G2B.m  (in BP2B_SetupProtocolFallbacks, same style as the three NoChain ones)
+    // 162 defaults for the 10 in-protocol additions: nobody in 160 implements them, the chain would assert
+    static const struct { const char *sel; const char *types; } kDef[] = {
+        {"isContinuousExposeStripVisible","B16@0:8"}, {"wantsContinuousExposeHoverGesture","B16@0:8"},
+        {"proposedAppLayoutForContinuousExposeWindowDrag","@16@0:8"}, {"spaceAccessoryViewIconHitTestOutsetForAppLayout:","d24@0:8@16"},
+        {"shouldAllowGroupOpacityForAppLayout:","B24@0:8@16"}, {"canSelectLeafWithModifierKeysInAppLayout:","B24@0:8@16"},
+        {"activeLeafAppLayoutsReachableByKeyboardShortcut","@16@0:8"}, {"inactiveAppLayoutsReachableByKeyboardShortcut","@16@0:8"},
+        {"adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:","@24@0:8@16"},
+        {"adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:","@32@0:8@16@24"} };
+    // add to the stock leaf classes that exist in every stack (SBFullScreenContinuousExposeSwitcherModifier,
+    // SBHomeScreenContinuousExposeSwitcherModifier, SBAppSwitcherContinuousExposeSwitcherModifier, SBTransitionSwitcherModifier,
+    // SBGestureSwitcherModifier, SBSwitcherModifier-direct classes) with class_addMethod (never on SBSwitcherModifier: that asserts).
```
Cheaper alternative inside G1C: in `G1C_AskRootIds` and the G2 call sites do not trust `respondsToSelector:`; gate on a registry of "selector has a real implementer" (walk `-[root enumerateChildModifiersWithBlock:]` recursively and test `class_getMethodImplementation(object_getClass(m), sel) != class_getMethodImplementation(SBSwitcherModifier, sel)`), exactly like `BP2B_FindOverrider` does for the NoChain selectors.

Other chain notes (PASS):
* Every `[super X]` selector used by G1B/G1C runtime classes was checked against the 160 protocols and class chains (supverify.py): all exist EXCEPT `handleTapAppLayoutHeaderEvent:` (B5) and `continuousExposeStripProgress` (16.2 context selector, G1C_Wd_StripProgress G1C.x:2364). The latter is covered: G2 `BP_G2_InstallContextForwardersIfMissing` (G2.x:395-416, called from `BP_G2_Setup` after G1B_Setup but before any message) adds a forwarder on SBSwitcherModifier when the extended protocol is off, and the extended protocol supplies the trampoline (terminal provider = VC `%new` at G2.x:341). PASS.
* `WindowDragRoot initWithStartingEnvironmentMode:initialAppLayout:` does not exist in 160 (160 has `initWithInitialAppLayout:`); G1C_Wdr_Init (G1C.x:~2562) falls back to the SBGestureRootSwitcherModifier `initWithStartingEnvironmentMode:` which exists (160 0x1c6056564). PASS. It skips the 160 `initWithInitialAppLayout:` body (0x1c5fe6888) which only stores `_initialAppLayout`, set via `object_setIvar`. PASS.
* All `%hook` targets (G1B, G1C) exist in 160 (hookcheck.py: no ABSENT). `floorModifierForGestureEvent:` exists in 160 as `b floorModifier` (0x1c61a2518) so the Root override returning `[self floorModifier]` when off/not a window drag is identical to stock. PASS.
* `SBRoutingSwitcherModifierDelegate` (160 required set = 10 methods) is fully implemented by `SBFilteringSwitcherModifier` (G1B.x:203-225); `fallbackModifierForRoutingModifier:` is an extra that 160 never calls. `initWithModifiers:delegate:` exists in 160. PASS.

---------------------------------------------------------------------------------------------------

## Checklist 3: event / response numbering   (PASS)

* 160 `-[SBSwitcherModifier _handleEvent:]` (0x1c63e8a98): `[super _handleEvent:]` first, then `cmp type,#0x23; b.hi default` -> types 36..38 fall through and return nil (confirmed). The G1B hook (G1B.x:70-80) calls `%orig`, then routes 36/37/38 only when `respondsToSelector:` the handler. Types 1..35 are returned untouched. PASS.
* 160 `-[SBFluidSwitcherViewController _performEventResponse:]` (0x1c5fe2024): `sub #1; cmp #0x23; b.hi 0x1c5fe2258`. Responses of type 37+ (the port uses 38/39/40) skip the jump table and go to `enumerateChildResponsesUsingBlock:` (0x1c5fe22a8), which re-enters `_performEventResponse:` for children. So stock ignores unknown types, and a response appended to a chain is handled once (the container is ignored, each child passes through the hook). The port correctly avoids 34 (160 RequestSystemApertureElementSuppression). PASS.
* Three G1B hooks of `_performEventResponse:` (G1B_VC, G1B_VCInvalidate and any G3/G2B ones) stack as ordinary %orig chains; each reacts to a different type; no double application.
* Event types 36..38 are never emitted at all: the header-tap hook is gated on `SBFullScreenContinuousExposeSwitcherModifier` responding to `handleTapAppLayoutHeaderEvent:` (nothing defines it; there is no Strip/FullScreen port in the tree), the pointer-boundary event class has no producer, the tongue event has none either. So the 16.2 header-tap/peek-pulse/grabber code is currently dead. Not a crash, a feature gap (INTEGRATION-NOTES does not say so).
* `SBTransitionSwitcherModifierEvent` flags (isiPadOSWindowingModeChangeEvent etc.) are set from `[[context request] source]`; the source numbers (0x40, 0x10, 0x18/0x19) are the same constants 160 itself compares in the same method (160 0x1c6240e90.. compares 0x23, 0x3e, 0x41 identical to 162). The flags live in associated objects, so the `[event copy]` in `G1B_Filtering_Event` (Transition branch) drops them (MINOR: a Filtering-wrapped content modifier never sees windowing-mode/command-tab flags).

## Checklist 4: Root factories vs stock   (B3, B4, B6 + PASS)

Stage Manager OFF / non-Chamois: `SBContinuousExposeRootSwitcherModifier` is only instantiated for Chamois, so the Root hooks cannot run. Hooks that run everywhere are pass-through: `_handleEvent:` (non-36..38), `_performEventResponse:`, `overlayAccessoryView:didSelectHeaderForRole:` (`%orig` unless the unreachable condition holds), `transitionEventForContext:...` (only sets flags), the VC ids hook (160 itself returns at `isChamoisWindowingUIEnabled == NO`, 0x1c5fde124-0x1c5fde128, and the hook does the same without `%orig`: identical), `_fluidSwitcherGestureTransactionClassForGestureType:` (only types 0xb/0xc). PASS.

Stage Manager ON, case by case against 160 `floorModifierForTransitionEvent:` (0x1c6370db8):
* nil event -> `%orig` (160: new Home). PASS.
* mode 1: reuse Home floor else new Home. Same as 160. PASS.
* mode 2: no expose id -> `[self multitaskingModifier]`; expose id -> reuse AppExpose floor with equal bundle id else `initWithBundleIdentifier:`. Same as 160 (0x1c6370f20-0x1c6371068). PASS.
* mode 3, expose id: reuse/new Inline AppExpose. PASS.
* mode 3, no expose id: B4 below. Also the 160 peek floor (`SBPeekHomeScreenContinuousExposeSwitcherModifier initWithAppLayout:configuration:`, class 0x1db4d6f20) for a valid `toPeekConfiguration` is no longer created; peek is moved to a level-2 child in `handleTransitionEvent:` (16.2 design). Intentional, but it is a behaviour change for 160's peek.

### B4. WRONG-BEHAVIOUR - mode 3 drops state the 160 FullScreen class still consumes
160 (0x1c6371194-0x1c63711e4): `[[FS alloc] initWithFullScreenAppLayout:]; setAppPileBundleIDToBringForwardIfAny:[event ambiguouslyLaunchedBundleIDIfAny]; setHighlightedByTouchAppLayouts:; setHighlightedByHoverAppLayouts:; setFullScreenAppDisplacementState:`, and the floor is reused only if `fullScreenAppLayout isEqual:toAL` AND `floor.appPileBundleIDToBringForwardIfAny isEqualToString:ambiguouslyLaunched...` (0x1c6370ea8-0x1c6370ed4). G1C (G1C.x:3270-3285) reuses on layout equality alone and copies only the two highlight sets. 162 removed those two FS members (m162 has no `appPileBundleIDToBringForwardIfAny`/`fullScreenAppDisplacementState`), but the tree keeps the 160 FullScreen class (no Strip port), so the pile bring-forward for an ambiguous launch (dock tap on an app with several windows) and the displacement state are silently lost.
```diff
--- a/Backport162/G1C.x
@@ case 3: (no expose id)
-                if (floor && [floor isKindOfClass:fsC] && toAL && G1C_Resp(floor, @selector(fullScreenAppLayout)) && [G1B_Send0(floor, @selector(fullScreenAppLayout)) isEqual:toAL]) return floor;
+                NSString *amb = G1C_Resp(event, @selector(ambiguouslyLaunchedBundleIDIfAny)) ? G1B_Send0(event, @selector(ambiguouslyLaunchedBundleIDIfAny)) : nil;
+                NSString *pile = (floor && G1C_Resp(floor, @selector(appPileBundleIDToBringForwardIfAny))) ? G1B_Send0(floor, @selector(appPileBundleIDToBringForwardIfAny)) : nil;
+                if (floor && [floor isKindOfClass:fsC] && toAL && G1C_Resp(floor, @selector(fullScreenAppLayout)) && [G1B_Send0(floor, @selector(fullScreenAppLayout)) isEqual:toAL]
+                    && (pile == amb || [pile isEqualToString:amb])) return floor;
@@ after creating fs
+                if ([fs respondsToSelector:@selector(setAppPileBundleIDToBringForwardIfAny:)]) G1B_SendV1(fs, @selector(setAppPileBundleIDToBringForwardIfAny:), amb);
+                if (floor && [fs respondsToSelector:@selector(setFullScreenAppDisplacementState:)] && G1C_Resp(floor, @selector(fullScreenAppDisplacementState)))
+                    G1B_SendVLL(fs, @selector(setFullScreenAppDisplacementState:), G1B_SendLL0(floor, @selector(fullScreenAppDisplacementState)));
```
Confidence 85% (static); user-visible effect needs a device.

### B3. WRONG-BEHAVIOUR - ported ToHome modifier never fills the nil case
G1C.x:3418 `if (!orig || ...) return orig;`. 160 Root `transitionModifierForMainTransitionEvent:` (0x1c6371228) returns nil for animated, non-gesture 2->1 (that is the SwitcherDismissFix bug), so `orig` is nil and the `(f == 2 && t == 1)` branch below is unreachable; it only ever REPLACES a modifier that someone else (SDF) already supplied. The md (group1c 5a: "this port's Root hook calls %orig first and only fills a nil, exactly like SDF") and INTEGRATION-NOTES/STATUS ("remove SwitcherDismissFix") are therefore wrong.
```diff
--- a/Backport162/G1C.x
-    if (!orig || !G1B_SendB0(event, @selector(isAnimated)) || (...isGestureInitiated...)) return orig;
+    if (!G1B_SendB0(event, @selector(isAnimated)) || (...isGestureInitiated...)) return orig;
+    if (!orig && !(fromMode == 2 && toMode == 1)) return orig;      // only the 2->1 nil case may be filled
```
(compute `f`,`t` before the check; the other branches keep requiring `orig`). With SDF installed both run: G1C's `%orig` returns SDF's wrapper (SDF hooks the superclass `SBFullScreenFluidSwitcherRootSwitcherModifier`, which the CE root calls via super), G1C then replaces it with its own `SBContinuousExposeToHomeSwitcherModifier`; the SDF wrapper is discarded unattached. No crash, no double application. The two classes have different names (`SDF...` vs `SB...`, B9). 90%.

### B6. gesture type 3 / 7 / 9 replacement (low confidence)
160 jump table of `gestureModifierForGestureEvent:` (0x1c6371600): 1 HomeGestureRoot(+stock AppSwitcher), 3 `SBGridSwipeUpGestureSwitcherModifier initWithGestureID:` (a plain gesture modifier, not a root), 7 PendingEvictionRoot, 9 WindowDragRoot, 10 ItemResizeRoot, 11/12 Reveal roots. G1C returns for 3 a 16.2 root wrapping a delayed-completion gesture modifier (`delayCompletionUntilTransitionBegins:YES`, completes only in `handleTransitionEvent:` phase>=2, G1C.x:225-234). If the requested transition never begins (no-op request, cancelled by the coordinator) the gesture modifier never completes (G1C added a 2 s safety timer for the Reveal gesture but not here). The root also hands the BP162 PILE AppSwitcher copy to the ToHome wrapper (B2). 40% (needs device). Suggested: add the same `G1C_NewTimerResponse(2.0, reason)` -> `setState:1` safety net to `G1C_GridGest_HandleGesture` when `delay` is set.
Other gesture types: 1, 10, 11, 12 -> `%orig`; 7 -> DnD root, 9 -> BP162 window drag root, each falling back to `%orig` when the factory returns nil. PASS.

### B7. MINOR - `_updateFloorModifierWithGestureEvent:` is void in 160
160 0x1c61e8e1c ends with `ldr x0,[sp,#8]; b _objc_release` (returns whatever x0 holds, the floor). G1C.x:3340 does `id extra = G1B_Send1(...)` (ARC retains it) and then `isKindOfClass:` on it; with the observed code x0 is the live floor modifier, so it is ignored. Fragile; use a `void` cast and drop the append. Also confirmed: stock `SBFluidSwitcherRootSwitcherModifier handleGestureEvent:` calls it only at phase 1 (0x1c61e7afc), so the phase!=1 call added by G1C is NOT a double application. 70%.

---------------------------------------------------------------------------------------------------

## Checklist 5: `g1c_piles`   (B2)

### B2. WRONG-BEHAVIOUR, default ON - pile layout is internally inconsistent and mostly in the wrong place
What is overridden (G1C.x:3033-3070, 3196): `frameForIndex:`, `scaleForIndex:`, `_fittedContentSize`, `_indexOfAppLayoutInItsPile:`, `opacityForLayoutRole:...`, `_defaultCardScale`, `snapshotScaleForAppLayout:` (all gated by `G1C_PilesOn()`; with piles off every one is `[super]`, so the switch is an exact pass-through for these). What is NOT overridden:
1. `frameForLayoutRole:inAppLayout:withBounds:`. 160 (0x1c636a5a8) takes `[super frame]` and then shifts every window by `((containerBounds.w - boundingBox.w)/2, containerBounds.h - boundingBox.h)` (0x1c636a72c-0x1c636a758), i.e. it positions windows on a CONTAINER-SIZED canvas. 162 (0x1c780fe84) instead places each window at `compactedCenterForItem - compactedBoundingBox.origin` with `sizeForItem:` (card canvas = compacted bounding box). G1C makes the card canvas the compacted box (G1C.x:3003-3007: `sz = compactedBoundingBox.size`) but keeps the 160 role frames, so windows are displaced by up to (cb - bb) toward the right/bottom of a smaller card (partially outside, overlapping neighbours; clipping depends on the item container). 70%.
2. 160 private geometry that other 160 methods still use: `_frameForIndex:ignoringScrollOffset:` (0x1c636c5b0) calls `_fittedContentSize`, `_scaledCardSize`, `_horizontalSpacing`, `_contentSize`; `visibleAppLayouts`/`_isIndexVisible:`/`contentOffsetForIndex:alignment:`/`visibleSpaceRangeForContentOffset:` use those, not the pile frames. A different fitted size + different card positions means the visible set and scroll limits are computed for the OLD layout: cards missing (blank) or unreachable by scrolling.
3. `frameForIndex:` scroll handling is right (160 0x1c636a55c passes the flag that subtracts `scrollViewContentOffset`, 162 0x1c780fe78 does the same), so no double scroll. PASS.
Where the pile modifier is used (see checklist 1): only the swipe-up gesture root (G1C.x:3324), the peek content (:1554) and DnD content (:2134). The real switcher floor is the stock modifier from `multitaskingModifierForEvent:`, so with piles ON the swipe-up-from-switcher transition starts from a pile layout while the screen shows the stock grid: a visible jump at gesture end. Piles never appear in the persistent switcher at all.
Degenerate inputs (no crash found): empty id list -> `frames` empty -> `[super]` frames but `fitted = (2*hEdge, h)` (G1C.x:3017-3022) which the 160 math then uses; `compactedBoundingBox` zero (model not produced by the ported controller) -> every card `continue`s (G1C.x:3003) with the same tiny fitted size; division guarded (`sz.height <= 0`, `rows >= 1`, `b.size.height == 0`); negative `cardH` when `switcherViewBounds` is zero gives negative scales but no NaN. `ids` from `continuousExposeIdentifiersInSwitcher` must be NSArray/NSOrderedSet (an NSSet would raise unrecognized `array`).
Recommended safe default: make `g1c_piles` opt-in (needs `Backport162.on.g1c_piles`), and port item 1 before turning it on.
```diff
--- a/Backport162/Tweak.x
 static const BOOL kOptIn[F_COUNT] = {
-    [F_G1B_APPTOAPP] = YES, [F_G3BOOTORIENT] = YES, ...
+    [F_G1B_APPTOAPP] = YES, [F_G1C_PILES] = YES, [F_G3BOOTORIENT] = YES, ...
```
and add to the BP162 AppSwitcher method table an override equivalent to 162 0x1c780fe84 (when `G1C_PilesOn()`): `center = [model compactedCenterForItem:item] - [model compactedBoundingBox].origin; size = [model sizeForItem:item]; return UIRectCenteredAboutPointScale(SBRectWithSize(size), center, screenScale)`.

## Checklist 6: stacked hooks   (PASS with notes)

Stacked on the same method (install order = Setup order: G4 -> G1B -> G2 -> G2B -> G1C -> G3 -> G3B -> G4B; the LAST installed is outermost):
* VC `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:`: G2B hook (`%orig` then derive lists) is inner, G1C hook is outer and never calls `%orig` when active (G1C.x:781-818); when inactive it calls `%orig` = G2B -> stock. No double application. G1C replacement dispatches the ids event ALWAYS (160 only when animated, 0x1c5fde244); the only 160 handlers are the Root (replaced), Cycle (hooked, checks `isAnimated`), Slide (160 class no longer created), base. PASS.
* VC `_performEventResponse:`: G1B_VC, G1B_VCInvalidate (+ any later) are independent %orig chains. PASS.
* `SBItemResizeGestureSwitcherModifier _responseForSceneSizeUpdateToSize:...`: G1C adds a child orientation response (type 38 class `SBSetInterfaceOrientationFromUserResizing...`), G3B wraps. Both reach the delegate `setInterfaceOrientationFromUserResizing:forDisplayItem:` with the same orientation: idempotent, extra work only. MINOR.
* Root `transitionModifierForMainTransitionEvent:` (G1C) over SDF's hooks on the superclass: see B3. PASS (no recursion).
* Root `handleEvent:` hook adds a Root override of `SBChainableModifier -handleEvent:` (inherited); MSHookMessageEx adds the method and returns the super IMP as `%orig`. PASS.
* `Reveal*` methods replaced by `class_replaceMethod` (B8) are not stackable with `%orig`, but nobody else hooks that class.

## Checklist 7: SwitcherDismissFix 0.3.0   (B3, B9)

SDF hooks `SBFullScreenFluidSwitcherRootSwitcherModifier` and `SBMainSwitcherRootSwitcherModifier`, fills a nil `orig` for animated, non-gesture 2->1, wraps in `SDFContinuousExposeToHomeSwitcherModifier` (different class name from G1C's `SBContinuousExposeToHomeSwitcherModifier`, so `G1B_MakeClass`'s existing-class shortcut never triggers; INTEGRATION-NOTES is wrong, B9). Order on the CE root: G1C hook -> CE root original -> `[super transitionModifierForMainTransitionEvent:]` (0x1c637159x tail) -> SDF hook -> SDF wrapper -> back in G1C: non-nil, animated, non-gesture, 2->1 -> replaced by G1C's own wrapper. SDF's object is created (incl. `[[root multitaskingModifier] copy]`, one child) and dropped: wasted work, no crash, no double effect. Without SDF, 2->1 gets NO animation (B3). Recommendation: keep SDF installed until B3 is fixed; document it.

## Checklist 8: threading / ARC / lifetimes / nil guards / off switches   (PASS with notes)

* All modifier code runs on the main thread (SpringBoard switcher). `BP_On` takes a mutex and a `clock_gettime` per call; it is called from per-index queries (frameForIndex, scaleForIndex, opacity ... x layouts x frames): small constant cost, no deadlock (no re-entrancy into BP_On under the lock). MINOR perf only.
* Associated objects use RETAIN_NONATOMIC and are released with the owner; keys are file-static chars. Runtime scalar ivars are plain memory in the instance. `[ce copy]` / `copyWithZone:` of runtime classes: the base copy is `alloc/init` so per-instance state (associated objects, ivars) is NOT copied; BP162 AppSwitcher flags are reset by its own `init` (YES), ToHome/AppToApp etc. are never copied. `G1B_HeaderEv_Copy`/Tongue copy are dead.
* Init functions that return nil after `alloc` without calling `[super init]` (e.g. `G1C_A2A_Init`, `G1B_Filtering_Init`): ARC releases an uninitialised `SBChainableModifier`, whose `dealloc`/`.cxx_destruct` only touch nil ivars (`_queryCache` nil). PASS.
* No `@try`; all private selectors are guarded by `respondsToSelector:` / `class_getInstanceMethod` EXCEPT the three unguarded `[super]` cases (B1 context for 10 query selectors, B5).
* Off switches: `BP_On` is evaluated per call. `Backport162.off` (global) and `off.group1b` make every G1B hook a pass-through (checked: all hooks begin with `G1B_ON()` or equivalent; class building and `class_addMethod` of the event-flag setters still happen but are inert). `off.group1c`: every Root/VC/Cycle/Txn hook checks `G1C_ON()`; the exception is B8. `off.g1c_piles`: exact pass-through for the overridden pile methods. BP162 run-time classes remain registered but are only reachable through G1C factories, which are all inside gated hooks (G1C_ON() false -> `%orig` -> stock classes). `shouldUseWallpaperGradientTreatment` hook returns YES, identical to 160 (0x1c637277c `mov w0,#1`). PASS.
* A toggle of an off file takes effect mid-session (1 s cache): a gesture started with G1C on and finished with it off mixes classes; not a crash.

### B5. MINOR (latent CRASH) - unguarded `[super handleTapAppLayoutHeaderEvent:]`
G1C.x:3097 `G1C_As_HeaderTap` -> `G1B_SUPER(..., gAsParent, self, _cmd, ...)`. `SBSwitcherModifier` has no `handleTapAppLayoutHeaderEvent:` in 160 (162 added it, sb162_objc `SBSwitcherModifier - handleTapAppLayoutHeaderEvent:`), and G1B adds none. It would be reached by `_handleEvent:` type 37, which nothing emits today. Patch: `id r = G1B_HasSuper(gAsParent, _cmd) ? G1B_SUPER(...) : nil;` (same as G1B_Pulse_HandleHeader).

### B8. MINOR - replaced Reveal methods ignore the off switch
G1C.x:1060-1070: `G1C_AddLike(c, "handleGestureEvent:", ..., YES)` (replace) plus added `handleTransitionEvent:`, `cornerRadiiForIndex:`, `shadowOpacityForLayoutRole:atIndex:`, `animationAttributesForLayoutElement:` on `SBRevealContinuousExposeStripsGestureModifier` run unconditionally, so `Backport162.off.group1c` does not restore the 160 strip-reveal pan (threshold 0.5 of 100 pt, `setState:1` at end). Patch: capture the old IMP with `class_replaceMethod` and have each new IMP call it when `!G1C_ON()`.

### B9. MINOR - documentation
INTEGRATION-NOTES says G1C and SwitcherDismissFix share `SBContinuousExposeToHomeSwitcherModifier`; SDF names its class `SDFContinuousExposeToHomeSwitcherModifier`. Also "remove SwitcherDismissFix" must wait for B3.

---------------------------------------------------------------------------------------------------

## Final ranking

1. B1 CRASH (65%): the ten 16.2-only query selectors have no implementer in 160; G1C's ids hook and several G2/G2B call sites send them through the chain whenever the extended protocol is active (default). Fix before shipping; cheapest safe mitigation: treat `respondsToSelector:` as insufficient and check for a real overrider, or add default IMPs to the stock leaf classes.
2. B2 WRONG-BEHAVIOUR (70%): set `g1c_piles` opt-in until `frameForLayoutRole:` is ported; the pile modifier is not even used by the real switcher.
3. B3 WRONG-BEHAVIOUR (90%): ToHome never fills nil; keep SDF or fix the hook.
4. B4 WRONG-BEHAVIOUR (85%): FullScreen floor loses pile bring-forward/displacement state.
5. B6 (40%), B7 (70%), B8 (90%), B5 (95%, latent), B9.
Cross-checks that PASSED: class creation order, ivar alignment and ARC handling of parent ivars, `_handleEvent:` and `_performEventResponse:` out-of-range handling, Routing delegate completeness, all `%hook` targets exist in 160, VC ids hook equals stock when Stage Manager is off, `_effectiveEnvironmentMode` fix matches 162 (0x1c7819cb8 vs 160 0x1c6372a88), `floorModifierForGestureEvent:` pass-through equals 160 (`b floorModifier`).
