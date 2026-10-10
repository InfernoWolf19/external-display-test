# Backport162 0.6.0 adversarial review, area B (G1B.x, G1BKit.h, G1C.x)

Target 16.0 (20A8372) SpringBoard, arm64e. All addresses are unslid cache vmaddrs. "160" = 20A8372, "162" = 20C65.
Nothing was run on a device; every claim is from the binaries or the sources. Confidence is given per finding.
Written incrementally: sections are appended as each checklist item is finished.

Severity: CRASH / WRONG-BEHAVIOUR / MINOR.

## Ranked findings (summary, updated at the end)

| # | sev | where | one line | conf |
|---|-----|-------|----------|------|
| B1 | CRASH (default on, cross-area G2/G2B/G1C) | G1C.x:777-818 (VCIds), G2.x:1606-1621, G2B.m:1177,1434,1471 + G2B.m:2014-2025 | The extended query protocol makes 10 16.2-only query selectors answerable on every modifier, but no 160 modifier implements them. The first send hits `SBChainableModifierMethodCache.m: couldn't find implementor for <sel>` (NSAssert). | 65% |
| B2 | WRONG-BEHAVIOUR (default on) | G1C.x:3183-3191, 2976-3016 | `g1c_piles` changes only card frames/scales/fitted size; 160 `frameForLayoutRole:inAppLayout:withBounds:` (0x1c636a5a8) still places windows for a full-container canvas -> windows displaced out of the smaller card. And the pile modifier is only instantiated for gestures/transitions, never for the real switcher floor, so the layout snaps at hand-off. Recommend default OFF. | 70% |
| B3 | WRONG-BEHAVIOUR (regression of the documented plan) | G1C.x:3396-3398 | `transitionModifierForMainTransitionEvent:` hook returns nil when `%orig` is nil, so the ported `SBContinuousExposeToHomeSwitcherModifier` is never created for the plain 2->1 transition. Removing SwitcherDismissFix (as INTEGRATION-NOTES/STATUS say) brings back the one-frame cut. | 90% |
| B4 | WRONG-BEHAVIOUR | G1C.x:3283-3293 (Root `floorModifierForTransitionEvent:`) | mode 3 drops `setAppPileBundleIDToBringForwardIfAny:`/`setFullScreenAppDisplacementState:`/pile-reuse test that 160 does (0x1c63711a0-0x1c63711e4) while the 160 FullScreen class still consumes them. | 85% |
| B5 | MINOR (latent CRASH) | G1C.x:3139-3141 | `G1C_As_HeaderTap` sends unguarded `[super handleTapAppLayoutHeaderEvent:]`; `SBSwitcherModifier` has no such method in 160. Dead today (type-37 event never emitted). | 95% |
| B6 | WRONG-BEHAVIOUR | G1C.x:3283-3300 | Root type-3 gesture is replaced by the 16.2 grid-swipe root with the BP162 pile AppSwitcher; its gesture modifier is "delayed" and has no timeout. | 40% |
| B7 | MINOR | G1C.x:3348-3356 | `_updateFloorModifierWithGestureEvent:` is `void` in 160; return value used as `id`. Works by accident. | 70% |
| B8 | MINOR | G1C.x:3513-3539, 1019-1060 | Reveal strip methods installed with `class_replaceMethod` and no `G1C_ON()` check: `Backport162.off.group1c` is not a pass-through for the strip-reveal gesture. | 90% |
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
  * G1C.x:793-796 (`G1C_AskRootIds`) -> the two `adjustedContinuousExposeIdentifiersIn...` selectors on EVERY `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:...` (app launch/switch/close in Stage Manager). The "root does not answer" fallback at G1C.x:797-803 is only taken when `respondsToSelector:` is NO, i.e. NOT when the protocol extension succeeded.
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
* Every `[super X]` selector used by G1B/G1C runtime classes was checked against the 160 protocols and class chains (supverify.py): all exist EXCEPT `handleTapAppLayoutHeaderEvent:` (B5) and `continuousExposeStripProgress` (16.2 context selector, G1C_Wd_StripProgress G1C.x:2405). The latter is covered: G2 `BP_G2_InstallContextForwardersIfMissing` (G2.x:395-416, called from `BP_G2_Setup` after G1B_Setup but before any message) adds a forwarder on SBSwitcherModifier when the extended protocol is off, and the extended protocol supplies the trampoline (terminal provider = VC `%new` at G2.x:341). PASS.
* `WindowDragRoot initWithStartingEnvironmentMode:initialAppLayout:` does not exist in 160 (160 has `initWithInitialAppLayout:`); G1C_Wdr_Init (G1C.x:2562) falls back to the SBGestureRootSwitcherModifier `initWithStartingEnvironmentMode:` which exists (160 0x1c6056564). PASS. It skips the 160 `initWithInitialAppLayout:` body (0x1c5fe6888) which only stores `_initialAppLayout`, set via `object_setIvar`. PASS.
* All `%hook` targets (G1B, G1C) exist in 160 (hookcheck.py: no ABSENT). `floorModifierForGestureEvent:` exists in 160 as `b floorModifier` (0x1c61a2518) so the Root override returning `[self floorModifier]` when off/not a window drag is identical to stock. PASS.
* `SBRoutingSwitcherModifierDelegate` (160 required set = 10 methods) is fully implemented by `SBFilteringSwitcherModifier` (G1B.x:203-225); `fallbackModifierForRoutingModifier:` is an extra that 160 never calls. `initWithModifiers:delegate:` exists in 160. PASS.
