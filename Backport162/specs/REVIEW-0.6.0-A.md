# Backport162 0.6.0 adversarial review, area A (launch path + layout/data core)

Target: iPadOS 16.0 (20A8372) SpringBoard, rootless Dopamine, arm64e. Reference: 16.2 (20C65). Nothing was run on a device.
Read in full: Tweak.x, BP.h, BPShared.h, G2.x, G2B.m, STATUS.md, INTEGRATION-NOTES.md, REVIEW-0.5.0.md, group2b md (item 6 and summary). Read in part: G1B.x/G1BKit.h, G1C.x (VC ids hook, AskRootIds, AppSwitcher class), G4B.x (arrange, lockedptr2), Group4Focus.x (coordinator, activeDisplayWindowScene).
All addresses are unslid cache vmaddrs ("160" = 20A8372, "162" = 20C65). Tools used: `annot3.py`/`annot162.py`, `ipsw dsc dump`, `ipsw dsc macho -n`, `logos.pl` (all .x files generated; only Tweak.x emits a constructor, so nothing is hooked before the %ctor's build guard), clang 18 `-fobjc-arc -emit-llvm` for the ARC claim in F3.
Severity: CRASH = can take SpringBoard down, WRONG-BEHAVIOUR = regression or dead feature, MINOR.
Confidence is given per finding.

---------------------------------------------------------------------------------------------------

## Ranked findings

| # | sev | where | one line | conf |
|---|-----|-------|----------|------|
| F1 | CRASH (Stage Manager ON, default config) | G2B.m:1177,1434,1471,1524,1565,2014-2025; G2.x:1608,1616; G1C.x:771,792,794 | The 10 extended QUERY selectors get trampolines on SBSwitcherModifier but nothing in 16.0 answers them; every call ends in `unrecognized selector` / `couldn't find implementor`, and `respondsToSelector:` guards are defeated by the trampoline. | high (85%) |
| F2 | WRONG-BEHAVIOUR (possible crash), default ON | G4B.x:1743-1752 vs Group4Focus.x:229,563-574 | `arrange` hook returns the pointer/touch-following scene without `%orig`: nil until the first touch (stock 16.0 never returns nil) and permanently nil with `off.activedisplay`. | medium-high (70%) |
| F3 | WRONG-BEHAVIOUR/interplay | G2B.m:1446-1459 | Item container tap/return-key now call `didSelectContainer:modifierFlags:` in EVERY mode (classic switcher too) instead of the 16.0 `didSelectContainer:`; any tweak hooking the 16.0 selector is bypassed. | high (90%) that it happens, unknown which tweaks care |
| F4 | HANG risk (watchdog -> respring loop), low reachability | G2.x:1244-1253 | Unbounded `do/while` in `_dodge:`; never terminates if `peekLen <= 0`, a NaN rect, or an item narrower than `peekLen`. | low (25%) reachability |
| F5 | MINOR (memory leak, proven by IR) | G2B.m:444 | `BP2B_Make` leaks one object (+ its extras + association entry) per call; hit by every `attributesByModifying*`, i.e. several per item per layout pass. | high (90%) |
| F6 | MINOR (launch guard fails open) | G2B.m:2238-2282 | Breadcrumb write/remove results are not checked; if `<jbroot>/tmp` is not writable by SpringBoard the crash guard silently does nothing. | medium |
| F7 | MINOR/WRONG-BEHAVIOUR | G2B.m:1689-1693 vs G4B.x:1453-1457 | G2B and G4B both define `-[SBFluidSwitcherItemContainer setPreferredPointerLockStatusSuppressed:]`; G2B is installed first so G4B's side-effecting setter never installs. | high |
| F8 | WRONG-BEHAVIOUR (fallback incomplete) | G2B.m:1550-1553 | With the protocol extension off/failed, Stage Manager keyboard window navigation becomes a silent no-op instead of falling through to the 16.0 code. | high |
| F9 | MINOR (switch semantics) | G2B.m (all BP2B_Replace), Tweak.x BP_Killed, G2.x | `off` / `off.g2b` created AFTER launch do not revert the replaced attribute/calculator methods; `off.g2b` alone leaves the extended protocols and G2.x hooks live (F1 stays reachable); `off.cgregion` does nothing (README). | high |
| F10 | MINOR (performance) | Tweak.x:122-129; G2B.m:40-71,424-435 | `BP_OnName` takes a global mutex and scans up to 160 slots with strcmp on every call; `BP2B_ReadFields` does 8 by-name ivar lookups + `NSGetSizeAndAlignment` per attribute read. | high |
| F11 | MINOR (defensive) | G2B.m:733-735 | `BP2B_AutoLayout` has no `gBP2B_Init16` guard; if `BP2B_SetupAttributes` bailed out the unguarded `attributesByModifying*` sends crash. | medium |
| F12 | MINOR | G2B.m:1689-1690, 1385-1409, 1331-1341 | Smaller deviations (BOOL vs `unsigned long long edge`, missing frame-rate range on the keyboard animation, protobuf archive drops the attribute extras). | medium |

---------------------------------------------------------------------------------------------------

## Checklist

1. Launch-time safety. PASS with caveats F1 (post-launch crash caused by the extension), F6.
2. Hooked/replaced methods, signatures, encodings, IMP calling convention. PASS (details in section 2), one MINOR (F12).
3. Whole-method replacements, classic path and Stage Manager OFF. PASS for `_layoutAppLayout` and the calculator (falls back to the saved 16.0 IMP); FAIL for the item container selection path (F3).
4. Threading / ARC / lifetimes. One leak (F5), no cycles found; unbounded loop (F4).
5. `Backport162.off.<name>` files. PASS at launch for g2b/g2bproto/g2blayout/g2bkeys/g2btongue/g2baperture/group2 (hooks check their switch); F9 for run-time toggling and for `off.g2b` alone; F2 for `off.activedisplay`.
6. Hot paths. F10.
7. StageManagerToggle / ExtendedDisplayEnabler / stock iPhone-style switcher: F3 (bypass of `didSelectContainer:`), F2 (active display), otherwise PASS (every Stage Manager path is gated by `isChamoisWindowingUIEnabled` per call, so a runtime toggle works).

---------------------------------------------------------------------------------------------------

## 1. Launch path, in detail

### 1.1 What the %ctor does (Tweak.x:416-435), in order
`BP_InitPaths` (snprintf into static buffers) -> `BP_BuildMatches` (sysctl kern.osversion == "20A8372", returns before anything else otherwise) -> `BP_Log` (no-op unless `Backport162.debug`) -> `BP2B_Early` -> `%init` (Tweak.x hooks: policy scale, autohost, blank) -> `BP4_InstallIfSupported` -> `BP_G4_Setup` -> `G1B_Setup` -> `BP_G2_Setup` -> `BP2B_Setup` -> `G1C_Setup` -> `BP_G3_Setup` -> `BP_G3B_Setup` -> `G4B_Setup`.
* No dyld/image lookups happen before the build guard; later lookups are `objc_getClass`/`NSClassFromString`/`dlsym(RTLD_DEFAULT)`. All 16 `dlsym` targets of G2/G2B that matter exist and are exported in 20A8372: `_SBLayoutRoleIsValidForSplitView` 0x1c63e827c, `_SBLayoutRoleMaskContainsRole` 0x1c63e8414, `_SBLayoutRoleEnumerateValidRoles` 0x1c63e8168, `_SBEnableJindo` 0x1c6501260 (all "external" in `sb_syms.txt`), `_SBFAngleForRotation...` (SpringBoardFoundation), and all 8 `CGRegion*` functions are `external` in the 16.0 CoreGraphics (`ipsw dsc macho ... CoreGraphics -n`, including `_CGRegionCreateIntersectionWithRegion` 0x188b02aec which SpringBoard itself does not import). So the CGRegion fallback in G2B.m:95-288 is never used (and is not wired into G2.x, `BP2B_RegionTable` is unreferenced).
* The `SBLayoutRoleIsValidForSplitView` fallback formula in G2B.m:685 is exactly the 16.0 body: `(role-1) <u 10 && !((1<<role) & 0xfffffc19)` (0x1c63e827c).
* Hooks that exist in no 16.0 class are skipped by Logos (`objc_getClass` nil); all hooked classes of G2.x exist in 16.0 and the hooked selectors/arg types match the 16.0 dump (checked with a script against `sb160n_objc.txt`: `layoutAttributesForContainerBounds:...isEmbeddedDisplay:` (9 args), `continuousExposeIdentifier`, `mutableCopyWithZone:`, `cacheKeyForSnapshotOfAppLayout:containerBounds:containerOrientation:hideStrips:hideDock:draggingItem:`, `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:`, `_areContinuousExposeStripsUnoccluded`, `handleContinuousExposeHoverGesture:`, `setOccludedInCenterStage:`).
* `kFeatureNames` has exactly F_COUNT (50) entries, `kOptIn` designated initialisers match; all opt-in names (`group1b.apptoapp`, `g3bootorient`, `g3b_preflightlog`, `g3b_axroles`, `edunative`, `methodology0`) are only queried through `BP_OptInName` (grep over G1B/G3/G3B/G4B), so none can be switched on by the default-on `BP_OnName`.

### 1.2 BP2B_Early / the protocol-trampoline table: verified
* 160 `+[SBChainableModifier _initalizeIMPCaching]` 0x1c642a6c0: when `self == [self baseClassForQueryProtocol]` (0x1c642a4d8 compares the IMP of `queryProtocol` with the superclass', so SBSwitcherModifier is the base and subclasses inherit our replaced IMP, base stays stable), it walks `[self queryProtocol]`, then `[self contextProtocol]`, parent by parent (`protocol_copyProtocolList`, >1 parent -> assertion "Multiple sub protocols not currently supported", 0x1c642a944), stops at NSObject, and for every REQUIRED instance method: `instancesRespondToSelector:` -> assertion "Cannot implement %@ on an implementer of +queryProtocol" (0x1c642a89c, line 0x248) / "+contextProtocol" (0x1c642aae4, line 0x272), else `class_addMethod(self, sel, _SBChainableModifierMethodCache{Query,Context}TrampolineForMethod(sel, types, idx))`.
* The trampoline functions 0x1c62acb8c (query) and 0x1c62acc18 (context) scan a static table of 0x510/0x10 = 81 `{encoding, IMP}` pairs with `strcmp`; a miss calls `.cold.1` 0x1c654a2b4 = `handleFailureInFunction ... "unsupported method signature! Please add an entry for %s to SUPPORTED_METHOD_SIGNATURES"` followed by `brk #1`. So an unknown encoding does kill SpringBoard inside `+initialize`: claim CONFIRMED.
* The query table is at 0x1e16f1de0 and the context table at 0x1e16f22f0 (TWO separate arrays; the source comment only names the first). I dumped both (81 pointers each, `scratchpad/rvA/tramp160*.txt`): they are identical in content and order, and `kBP2B_Tramp160[]` (G2B.m:1913-1995) matches them string for string (script: 81 vs 81, 0 differences). Against the 16.2 table (`/tmp/claude-0/tramp162.txt`, 85 entries) the four new encodings are exactly `d32@0:8d16@24`, the 72-byte clippingFrame CGRect encoding, `{SBSwitcherContinuousExposeStripTongueAttributes=QQ}16@0:8` and `@40@0:8@16@24@32`. All 22 selectors of `kBP2B_PCtx` (12) and `kBP2B_PQry` (10) use encodings that are in the 160 table; the three `kBP2B_PNoChain` encodings are not, and are correctly kept out of the protocol and answered by plain methods added to SBSwitcherModifier AFTER the stock `+initialize` (so the assertion above cannot fire for them). Gating on 20A8372 (`BP2B_BuildIs20A8372`) plus the dynamic whitelist is sound.
* Forcing the initialisation: `objc_msgSend(sm, @selector(class))` runs `+initialize` for SBChainableModifier (base != self -> returns at 0x1c642a74c) then SBSwitcherModifier. `class_getClassMethod` on the five shape-check selectors does not initialise (all exist, so no `+resolveInstanceMethod:` message is sent).
* Breadcrumb order is right: written (G2B.m:2279) before the forced init, removed (2282) after verification; the next launch finds it, writes `Backport162.off.g2bproto`, removes the crumb and returns (2238-2243). A SIGABRT, an uncaught NSException out of the ctor and a jetsam/watchdog kill inside the window all leave the crumb. The window is milliseconds, so the watchdog is not a realistic case. Limitation: it only covers a crash INSIDE that window, not crashes later that are caused by the extension (F1), which is where this build is exposed.

### F1. Extended query selectors have no terminal implementer (CRASH)

Scenario (Stage Manager enabled, defaults):
1. `BP2B_Early` succeeds: `gBP2B_ProtoOK = YES`, 22 selectors added, log "added 22 skipped 0". `SBSwitcherModifier` now has trampoline IMPs for the 10 query selectors `activeLeafAppLayoutsReachableByKeyboardShortcut`, `canSelectLeafWithModifierKeysInAppLayout:`, `inactiveAppLayoutsReachableByKeyboardShortcut`, `shouldAllowGroupOpacityForAppLayout:`, `adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:`, `adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:`, `isContinuousExposeStripVisible`, `proposedAppLayoutForContinuousExposeWindowDrag`, `spaceAccessoryViewIconHitTestOutsetForAppLayout:`, `wantsContinuousExposeHoverGesture`. Every modifier, including `_rootModifier`, now answers `respondsToSelector:` YES for them.
2. Nothing in this tweak implements them for the query chain: grep over G1B/G1C/G2/G2B/G3/G3B/G4B finds only call sites and the table (G1C only implements the two `adjusted...` on the run-time AppSwitcher subclass, G1C.x:3182-3183, and `proposedAppLayoutForContinuousExposeWindowDrag` on the WindowDragDestination class, G1C.x:2608). In 16.0 no class declares any of the 10 (`sb160n_objc.txt`: zero hits). In 16.2 they are implemented by `SBDefaultImplementationsSwitcherModifier` (`isContinuousExposeStripVisible` 0x1c788b650 = `continuousExposeStripProgress > 0`, `wantsContinuousExposeHoverGesture` 0x1c788b648 = NO, `proposedAppLayout...` 0x1c788b67c = nil, `spaceAccessory...` 0x1c788b350) and `SBRoutingSwitcherModifier` (the other six, e.g. `shouldAllowGroupOpacityForAppLayout:` 0x1c752baec routes to the modifier containing the layout, default NO). Neither 16.2 class exists in that form in 16.0.
3. A trampoline call with no overriding modifier ends in `_MethodCacheDispatchDataForSelectorIndex` 0x1c62afe50: walk `_nextFunc` (= `[modifier.nextQueryModifier _queryCache]`, 0x1c642aebc); when it returns nil: `delegate = [cache.modifier delegate]` (0x1c62aff14-0x1c62aff34), `class_getMethodImplementation(object_getClass(delegate), sel)`; if delegate is nil -> `handleFailureInFunction ... "couldn't find implementor for %@"` (SBChainableModifierMethodCache.m:189, 0x1c62affc4); otherwise the IMP is `_objc_msgForward` for a delegate that lacks the selector -> `-[SBFluidSwitcherViewController shouldAllowGroupOpacityForAppLayout:]: unrecognized selector`. (Child modifiers do not inherit the delegate: `_addChildModifier:...` 0x1c6429060 never calls `setDelegate:`; only the root's delegate is the VC, which is why the CONTEXT chain works: the VC is the terminal there, confirmed by `appLayoutsToEnsureExistForMainTransitionEvent:` which is a context method implemented by the VC.) Either way it is an exception on the main thread.
4. Call sites reached with Stage Manager on:
   * G2B.m:1177-1181, inside the per-leaf loop of the replaced `_layoutAppLayout:roleMask:completion:`: guarded by `[root respondsToSelector:...]` which is YES -> first Stage Manager layout.
   * G2.x:1608-1613 `-_areContinuousExposeStripsUnoccluded` hook (called by `appLayoutContainsAnUnoccludedMaximizedDisplayItem:` 0x1c5fbdc78 <- FullScreenContinuousExposeSwitcherModifier `cornerRadiiForIndex:`/`isContainerStatusBarVisible`/`isHomeAffordanceSupportedForAppLayout:`) and G2.x:1616-1621 `handleContinuousExposeHoverGesture:` (any pointer hover).
   * G1C.x:771-795 `G1C_AskRootIds` in the replaced `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:...` (every transition); G1C.x:3299 (`proposedAppLayoutForContinuousExposeWindowDrag`).
   * G2B.m:1434 (shift-click), 1471/1524/1529 (keyboard window navigation), 1565 (menu validation).
   With Stage Manager OFF none of these run (the 16.0 non-chamois path of `_update...Identifiers...` is a pure no-op, verified at 0x1c5fde128/0x1c5fde2c8, and the VC replacements fall back to the 16.0 IMP).
Evidence for "nobody answers": `grep -n` of each selector over all sources (only G2.x/G2B.m tables and call sites + the two G1C classes above); `sb160n_objc.txt` has no declaration; 16.2 owners listed with `sb162_objc.txt` lines 11389,11406,39569-39671,93926-94180.

Interim workaround for the tester: create `<jbroot>/tmp/Backport162.off.g2bproto` before the next respring (the 12 context selectors are then served by `BP_G2_InstallContextForwardersIfMissing`, the 10 query selectors fail `respondsToSelector:` and every call site above skips). Caveat: F8.

Patch (G2B.m, call after `BP2B_SetupProtocolFallbacks()` in `BP2B_Setup`). `SBDefaultImplementationsSwitcherModifier` is where 16.0 puts the terminal defaults of the chain (it implements the 64 `SBSwitcherQueryDefaultImplementationProviding` selectors), so class_addMethod there terminates the chain exactly like 16.2. Defaults are the 16.2 ones except where noted (chosen to keep 16.0 behaviour):
```diff
+static void BP2B_InstallQueryDefaults(void) {
+    Class d = objc_getClass("SBDefaultImplementationsSwitcherModifier");
+    if (!d || !gBP2B_ProtoOK) return;                       // only needed when the trampolines exist
+#define DEF(sel, types, blk) BP2B_AddIfMissing(d, sel, imp_implementationWithBlock(blk), types)
+    DEF("wantsContinuousExposeHoverGesture", "B16@0:8", ^BOOL(id me) { return YES; });   // 16.2 default is NO; YES = 16.0 (G2.x:1619 would otherwise drop every hover)
+    DEF("isContinuousExposeStripVisible", "B16@0:8", ^BOOL(id me) { return BP2B_Dbl(me, sel_registerName("continuousExposeStripProgress")) > 0.0; });   // 0x1c788b650
+    DEF("proposedAppLayoutForContinuousExposeWindowDrag", "@16@0:8", ^id(id me) { return nil; });                                         // 0x1c788b67c
+    DEF("spaceAccessoryViewIconHitTestOutsetForAppLayout:", "d24@0:8@16", ^double(id me, id l) { return 0.0; });
+    DEF("shouldAllowGroupOpacityForAppLayout:", "B24@0:8@16", ^BOOL(id me, id l) { return YES; });                                        // 16.2 default NO; YES = untouched 16.0 layer
+    DEF("canSelectLeafWithModifierKeysInAppLayout:", "B24@0:8@16", ^BOOL(id me, id l) { return NO; });
+    DEF("activeLeafAppLayoutsReachableByKeyboardShortcut", "@16@0:8", ^id(id me) { return @[]; });
+    DEF("inactiveAppLayoutsReachableByKeyboardShortcut", "@16@0:8", ^id(id me) { return @[]; });
+    DEF("adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:", "@24@0:8@16", ^id(id me, id a) { return a; });
+    DEF("adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:", "@32@0:8@16@24", ^id(id me, id a, id b) { return a; });
+#undef DEF
+}
@@ void BP2B_Setup(void) {
     BP2B_SetupProtocolFallbacks();
+    BP2B_InstallQueryDefaults();
```
(Untested; the class must be given these methods before the first modifier instance exists, which is the case at ctor time.) Note the hover default: G2.x:1616 comment says "default YES when nobody answers" but the 16.2 default is NO, so a literal port would disable hover in Stage Manager.

### F6. Crash-guard fails open if the crumb cannot be written (MINOR)
`[@"1" writeToFile:...]` and `removeItemAtPath:` results are ignored (G2B.m:2279,2282,2240-2241). If `ROOT_PATH_NS(@"/tmp")` does not exist or is not writable for the SpringBoard process (UNVERIFIED on Dopamine; the log/off files of 0.5.x use the same directory and nobody has reported back), the forced `+initialize` runs unprotected and an abort there is a respring loop with no auto-disable.
```diff
-    [@"1" writeToFile:BP2B_CrumbPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
+    if (![@"1" writeToFile:BP2B_CrumbPath() atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
+        BP_Log(@"G2B: cannot write the crash breadcrumb, protocol extension not installed");
+        class_replaceMethod(meta, sel_registerName("contextProtocol"), gBP2B_OrigCtxProto, tc);     // undo the two hooks
+        class_replaceMethod(meta, sel_registerName("queryProtocol"), gBP2B_OrigQryProto, tq);
+        return;
+    }
```
Same for the `off.g2bproto` write at 2240 (if it fails the crumb should stay, which it does, so the extension stays off: fine).

---------------------------------------------------------------------------------------------------

## 2. Signatures, encodings, calling conventions (checked)

* Method-by-method check of every `BP2B_Replace` / `class_addMethod` target against `sb160n_objc.txt` (scripted): `_layoutAppLayout:roleMask:completion:` is `v@:@Q@?` and `BP2B_LayoutAppLayoutImpl(id, SEL, id, unsigned long long, id)` matches; `_dispatchEventAndHandleAction:`, `_updateLayoutWithCompletion:`, `_ensureSubviewOrdering`, aperture responders, `_navigate...`, `prepareForReuse`, `_handlePageViewTap:`, `_returnKeyPressed:` are `void`; the blocks that return `id` for the void ones (G2B.m:1868) are ABI-harmless. `canPerformKeyboardShortcutAction:forBundleIdentifier:` BOOL, `_keyboardFocusableLiveAppLayoutsMatchingFocusedApp:foundAtIndex:` id with `long long *`.
* `_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...` (160 0x1c611a81c): arguments `x2 layout, x3 orient, x4 attrs, d0 dockH, d1 scale, x5 dragging, x6 before, d2-d5 bounds, x7 ps, stack pd` (prologue at 0x1c611a850-0x1c611a884: `ldrb w26,[fp,#0x10]`). The block IMP (`imp_implementationWithBlock` moves self into x1) has the identical register/stack layout. Same for the `_frameForLayoutRole:...skipAutoLayout:` wrapper (CGRect return in d0-d3, `BOOL`s in w6/w7/stack). `_cmd` is not needed by any block (they use `sel_registerName` or captured SELs). `BP2B_LayoutAppLayoutImpl` is a real C IMP and takes `cmd`.
* Struct returns/args: `BP2BRadii` and the gradient pair are HFAs (d0-d3 / d0-d1) and go through `objc_msgSend` (no `_stret` on arm64); the 56-byte `BP2BAttrSize` is returned/passed indirectly consistently between the blocks and the typed casts.
* 16.0 init used for `BP2B_Make` matches `initWithContentOrientation:lastInteractionTime:sizingPolicy:size:center:occlusionState:userConfiguredSizeBeforeOverlapping:fullyOccludedPeekingCenter:` (sb160n_objc.txt), ivars `_size/_center/_userConfiguredSizeBeforeOverlapping/_hash/_lastInteractionTime/_sizingPolicy/_contentOrientation/_occlusionState/_fullyOccludedPeekingCenter` exist with the sizes `BP2B_ReadFields` demands.
* Unguarded selector sends in the `_layoutAppLayout` body (macros `BP2B_S0..S4`, 103 selectors): scripted check of every string against the union of the 16.0 dumps: all exist except `adjustedSpaceAccessoryViewScale:forAppLayout:` (guarded by `respondsToSelector:`; also answered by the fallback block), `clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:` (UNGUARDED `BP2B_S4` at G2B.m:1123; safe only because `BP2B_SetupProtocolFallbacks` adds it first, and `_layoutAppLayout` is only replaced under the same `g2b` switch) and `shouldAllowGroupOpacityForAppLayout:` (F1).
* Added/forwarded method with the wrong parameter type: `-_updateForPointerHoveringOverEdge:` / `-appSwitcherPageView:pointerIsHoveringOverEdge:` (G2B.m:1689-1690) take `BOOL` and forward to the 16.0 `pointerIsHoveringOverEdge:(unsigned long long)edge` (F12). No 16.0 caller uses the new names, so it is dormant.

### 3. Whole-method replacements
* `_layoutAppLayout`: falls back to the saved 16.0 IMP for: no app layout, `off.g2blayout`, no `_rootModifier`, `isChamoisWindowingUIEnabled == NO`, `shouldPerformRotationAnimationForOrientationChange`, `shouldPinLayoutRolesToSpace:`, missing `SBC2GroupCompletion`. So classic and Stage-Manager-off are exactly 16.0. The 16.0 stub 0x1c5fca458 is `[SBC2GroupCompletion perform:block finalCompletion:completion options:0 delegate:vc]`, same as the port. The 16.0 block does not read `isChamoisWindowingUIEnabled` at all (grep over the 2600-insn listing), 16.2 reads it twice (0x1c7443bac, 0x1c7443c14: the chamois-only position term), which is what the port adds. Selector sets of the 16.0 and 16.2 blocks (108 vs 115) are covered by the port; the only 16.2-only callee is `setFrameRateRange:highFrameRateReason:` on the keyboard-height animation (not set by the port, F12). The numeric port itself (UNSURE items 0x1c7a933c8 mask, icon alignment polarity, grabber width) cannot be proven without a device. Idx not found: port skips the body, 16.0 jumps to its epilogue (0x1c5fca594): same.
* Calculator hook: 16.0 cache hit returns `layout` unchanged; port does the same (G2B.m:746-748). Falls back to the 16.0 IMP when any prerequisite is missing; it does NOT check chamois itself, but its callers (`_frameForLayoutRole:...`, `overlappingModelForAppLayout:...`, `appLayoutByDraggingItem:...`, 160 0x1c611987c/0x1c611a574/0x1c611a5e0) are only used for the chamois layout, and `!attrs` returns nil -> 16.0.
* `-[SBDisplayItemLayoutAttributes sizeInBounds:]`, `userConfiguredSizeBeforeOverlappingInBounds:`, `centerInBounds:` are replaced unconditionally (no switch at run time). 16.0 0x1c614b874: `if (w <= 1 && h <= 1) return size*bounds else return size` with NO clamp. The port uses threshold 10.0 and clamps `min(cur, max(v,0))`. For genuinely normalised values (<= 1) the result is the same product; it differs only for 16.0 absolute sizes below 10 pt (impossible for windows) and the clamp is the 16.2 behaviour. Accepted.

### 4. Threading, ARC, lifetimes
* Associated objects: `BP162OverlapExtras`, `BP162VCState`, `BP2BAttrExtras`, calculator->controller, tongue views: all hang off the owning object with RETAIN_NONATOMIC, no back references that retain (delegate is weak), so no cycles. `BP162ChamoisOverlappingController._reentrancyGuard` is per calculator instance and only touched on the main thread.
* Weak/async: the tongue view's completion captures `__weak` self; `BP2B_CompletionFor` captures strong `prop`/`maker` only until the animation completes.
* F5 below. The `copyWithZone:` replacement (G2B.m:625) and the `SBTapAppLayoutSwitcherModifierEvent` copy wrapper (1401) are ownership-balanced only by accident: the former returns `BP2B_Make`'s result, which carries the same +1 that F5 leaks, so for a `-copy` the leak becomes the caller's +1. Fix F5 and fix this at the same time (make the copy path use `[x alloc]` and return with `__attribute__((ns_returns_retained))` on the block type, or `CFBridgingRetain`/`objc_retain` explicitly).

### F5. BP2B_Make leaks (MINOR)
```c
id o = ((id (*)(Class, SEL))objc_msgSend)(gBP2B_AttrClass, @selector(alloc));   // G2B.m:444
o = gBP2B_Init16(o, ..., f.peek);
```
ARC treats a call through a function pointer as +0 and retains the result; the `alloc` +1 is never balanced. Proof (clang 18, same shape, `-fobjc-arc -emit-llvm`): `call objc_msgSend; llvm.objc.retainAutoreleasedReturnValue` (rc +1 extra), `call init-fn; retainAutoreleasedReturnValue; objc.release(old)`, `storeStrong; autoreleaseReturnValue`. Net: one unreleased reference per call, plus the `BP2BAttrExtras` and association-table entry. Callers: all `attributesByModifying*` replacements (G2B.m:579-624) and `BP2B_AttrsBySettingAbsolute`; roughly 4-7 per item per layout pass in `BP2B_AutoLayout` (G2B.m:779-880), i.e. thousands per second while dragging a window.
```diff
-    id o = ((id (*)(Class, SEL))objc_msgSend)(gBP2B_AttrClass, @selector(alloc));
+    id o = [gBP2B_AttrClass alloc];                       // ObjC syntax: ARC knows alloc returns +1
```
(then `copyWithZone:` at 625 is no longer accidentally balanced; give that one block an explicit `objc_retain(result)` before returning, or declare it `NS_RETURNS_RETAINED`.) The `[X alloc]` + `msgSend(init...)` pattern used elsewhere in G2B (`BP2B_DispatchTap`, `modelClass alloc`) is balanced.

### F4. Unbounded loops in the ported controller (HANG risk)
G2.x:1244-1253:
```c
do { xL -= peekLen; vis = RgnDiff(RgnR(CGRectMake(xL - hw, c.y - hh, s.width, s.height)), occ); }
while (occ && (!vis || gRgn.isEmpty(vis) || FLT(gRgn.bbox(vis).size.width, peekLen)));
```
(same for `xR` and `yD`). It only terminates when a shifted copy of the item has `>= peekLen` visible width. Never terminates for `peekLen <= 0` (attribute 0), an item narrower than `peekLen`, or when `RgnR` returns NULL (NaN rect -> `!vis` stays true). A hang on the main thread during layout is a watchdog kill (0x8badf00d) and, with Stage Manager on, repeats at the next launch. Reachability needs odd input (zero-size scene or zero peek length); 16.0 `stageOcclusionDodgingPeekLength` is a settings value and normally positive.
```diff
+    int guardN = 0;
-    do { xL -= peekLen; ... } while (occ && (...));
+    do { xL -= peekLen; ... } while (occ && ++guardN < 128 && (...));
```
(repeat for xR, yD; also bail out when `peekLen <= 0` before the three loops.)

---------------------------------------------------------------------------------------------------

## F2. `arrange` replaces `activeDisplayWindowScene` without a fallback (WRONG-BEHAVIOUR)

Both Group4Focus.x (G4, installed first in `BP_G4_Setup`) and G4B.x (`G4B_Arrange`, installed last) hook `-[SBWindowSceneManager activeDisplayWindowScene]`. Hook order: G4B outermost. G4B.x:1743-1752:
```c
if (G4B_On("arrange") && [self respondsToSelector:kb] && [self respondsToSelector:ui]) {
    long long m = G4B_Methodology();            // default 1 (setDefaultValues hook, G4B.x:1732)
    if (m == 0) return G4B_Obj(self, kb);
    if (m == 1) return G4B_Obj(self, ui);       // no %orig, no fallback
```
`ui` = Group4Focus's `%new activeDisplayWindowSceneFollowingUserInteraction` = `BP_ValidateActiveScene(self, [coordinator activeWindowScene], 1)`; `BPMultiDisplayCoordinator._activeDisplayWS` is nil until the first qualifying touch/pointer event reaches `-[SpringBoard sendEvent:]` (Group4Focus.x:229, fed only while `BP_On(F_ACTIVEDISPLAY)`, :606), and `BP_ValidateActiveScene(nil)` returns nil (:388-395). Consequences:
1. After every respring, until the first touch, and again after the active scene disconnects (`windowSceneDidDisconnect:` sets it nil, :245), `activeDisplayWindowScene` returns nil on a single-display iPad. Stock 16.0 returns `kfc.windowSceneWithFocus ?: embedded`. Group4Focus.x:566-571 deliberately keeps keyboard-following "until the first qualifying event" (comment "deviation"), and the G4B hook skips exactly that.
2. `Backport162.off.activedisplay` (or `off.disconnect`) does not restore stock: the G4 hook becomes a pass-through, the coordinator is never fed (`sendEvent:` gated by `F_ACTIVEDISPLAY`), and G4B still returns the nil coordinator scene permanently.
16.2 itself passes nil through `_validateSuggestedActiveWindowScene:` (0x1c74bf960) too, but its coordinator is created and fed by the real sniffers unconditionally; the port's deviation was made precisely to avoid nil.
Unverified: which 16.0 callers dereference the result without a nil check (nil-messaging hides most); medium confidence in impact, high confidence in the nil.
```diff
--- a/Backport162/G4B.x
@@ %hook SBWindowSceneManager  - (id)activeDisplayWindowScene
-    if (G4B_On("arrange") && [self respondsToSelector:kb] && [self respondsToSelector:ui]) {
+    if (G4B_On("arrange") && BP_On(F_ACTIVEDISPLAY) && [self respondsToSelector:kb] && [self respondsToSelector:ui]) {
         long long m = G4B_Methodology();
         if (m == 0) return G4B_Obj(self, kb);
-        if (m == 1) return G4B_Obj(self, ui);
+        if (m == 1) { id s = G4B_Obj(self, ui); if (s) return s; }      // nil: fall through to the G4 hook / 16.0
         BP_Log(...)
-        return nil;
```
(keep the `%orig` at the bottom as the common exit.)

---------------------------------------------------------------------------------------------------

## F3. Item container selection bypasses `didSelectContainer:` in classic mode (interplay)

G2B.m:1446-1459 replaces `-[SBFluidSwitcherItemContainer _handlePageViewTap:]` and `_returnKeyPressed:`:
```c
if (isSelectable && [d respondsToSelector:didSelectContainer:modifierFlags:] && BP2B_Enabled("g2bkeys")) {
    ... [d didSelectContainer:me modifierFlags:flags];          // added to the VC at 1441
} else origTap(...)
```
There is no `isChamoisWindowingUIEnabled` check, so the classic iPad/iPhone-style switcher also takes this path. The 16.0 bodies (0x1c615c3a4, 0x1c615c03c) call `[delegate didSelectContainer:self]` (VC 0x1c5fd8d64). The port's VC method re-implements that body (`BP2B_DidSelectContainer`), which is equivalent for flags == 0 (it additionally falls back to the leaf when the adjusted layout is nil), but:
* any other tweak that hooks/observes `-[SBFluidSwitcherViewController didSelectContainer:]` (alternative switchers, StageManagerToggle-style tweaks that gate selection, switcher fixes) is no longer called for taps or the Return key;
* `modifierFlags` come from `-[UIGestureRecognizer modifierFlags]`, a plain tap yields 0, fine.
Patch: use the new path only when it is needed (Stage Manager and a modifier key), otherwise keep the 16.0 call:
```diff
-        if (BP2B_Bool(me, sel_registerName("isSelectable")) && [d respondsToSelector:sc] && BP2B_Enabled("g2bkeys")) {
-            long long flags = [gr respondsToSelector:@selector(modifierFlags)] ? ((long long (*)(id, SEL))objc_msgSend)(gr, @selector(modifierFlags)) : 0;
-            ((void (*)(id, SEL, id, long long))objc_msgSend)(d, sc, me, flags);
+        long long flags = [gr respondsToSelector:@selector(modifierFlags)] ? ((long long (*)(id, SEL))objc_msgSend)(gr, @selector(modifierFlags)) : 0;
+        if (flags != 0 && BP2B_Bool(me, sel_registerName("isSelectable")) && BP2B_Bool(d, sel_registerName("isChamoisWindowingUIEnabled")) && [d respondsToSelector:sc] && BP2B_Enabled("g2bkeys")) {
+            ((void (*)(id, SEL, id, long long))objc_msgSend)(d, sc, me, flags);
```
(same for `_returnKeyPressed:`; `BP2B_DidSelectContainer` can then stay as is.)

## F7. Duplicate definition of the suppressed-pointer-lock accessors (MINOR)
G2B.m:1692-1693 adds `isPreferredPointerLockStatusSuppressed` / `setPreferredPointerLockStatusSuppressed:` (assoc key `kBP2B_CSuppressed`, setter only stores the flag). G4B.x:1453-1457 `%new`s the same two selectors (assoc key `kLPMSupC`, setter re-applies `setContentViewBlocksTouches:`/`setSelectable:`). `BP2B_Setup` runs before `G4B_Setup`, `class_addMethod` fails for the second one, so G4B's setter with its side effects is never installed; G4B's `setContentViewBlocksTouches:`/`setSelectable:` hooks read the G2B getter, so the suppression is honoured only at the next unrelated update. Fix: delete G2B.m:1692-1693 (and the `prepareForReuse` reset or make it key-compatible), or make the G2B setter call the two re-apply lines.

## F8. Fallback route is incomplete for keyboard navigation (WRONG-BEHAVIOUR)
G2B.m:1550-1553: with Stage Manager on and `g2bkeys` on, `_navigateFromFocusedAppWindowSceneToNextScene:matchFocusedApp:` calls `BP2B_NavigateKbd` and returns without the 16.0 code. `BP2B_NavigateKbd` needs `[root activeLeafAppLayoutsReachableByKeyboardShortcut]`; when the extension is off/failed that query does not exist, `BP2B_KbdList` returns nil, `idx == NSNotFound`, and the method returns: keyboard window cycling silently stops working. Fix: have `BP2B_NavigateKbd` return a BOOL (handled) and call the saved 16.0 IMP when it did nothing.
```diff
-        if (BP2B_Chamois(me) && BP2B_Enabled("g2bkeys")) { BP2B_NavigateKbd(me, fwd, match); return; }
+        if (BP2B_Chamois(me) && BP2B_Enabled("g2bkeys") && BP2B_NavigateKbd(me, fwd, match)) return;
```
(and `static BOOL BP2B_NavigateKbd(...)` returning NO at the early returns).

## F9. Switch semantics
* Launch-time: `Backport162.off`, `off.g2b`, `off.g2bproto`, `off.g2blayout`, `off.g2bkeys`, `off.g2btongue`, `off.g2baperture`, `off.group2` all give the 16.0 behaviour for the code they gate (hooks test `BP_On`/`BP2B_Enabled` per call or the installer returns). `BP2B_Setup` returns before any `class_replaceMethod` when `g2b` is off, so exact stock.
* `off.g2b` alone leaves `BP2B_Early` active (separate `g2bproto`) and the unconditional `%init(G2VC)`/`%init(G2B)` of G2.x; with F1 present the crash path remains. `off.g2b` should also imply no protocol extension.
* Run-time toggling: the replaced SBDisplayItemLayoutAttributes methods (`sizeInBounds:`, `centerInBounds:`, `attributesByModifying*`, `copyWithZone:`, `isEqual:`, `plistRepresentation`, `initWithPlistRepresentation:`) have no per-call check; creating `Backport162.off` while SpringBoard runs only disables the Logos hooks. README promises "checked at most once a second".
* `off.cgregion` has no effect (nothing reads `F_CGREGION`; the CoreGraphics SPI is always used).

## F10. Performance
* `BP_OnName` (Tweak.x:122-129): `pthread_mutex_lock` + `BP_SlotFor` linear `strcmp` over up to 160 slots + `clock_gettime_nsec_np`, on every call. Called per frame from `_frameForLayoutRole:` wrapper and calculator hook (G2B.m:914,927), per event from `_dispatchEventAndHandleAction:` (1870, plus `isChamoisWindowingUIEnabled` send), `_updateLayoutWithCompletion:` (1875), every gesture/aperture call. Cheap per call, but it is a process-wide lock on the hot path. Patch: cache the slot index per call site.
```c
#define BP_OnNameC(n) ({ static int _i = -2; BP_OnNameCached(n, &_i); })
```
* `BP2B_ReadFields`: 8 x (`class_getInstanceVariable` + `ivar_getTypeEncoding` + `NSGetSizeAndAlignment` inside `@try`) per attribute read, and `sizeInBounds:`/`centerInBounds:`/`userConfiguredSizeBeforeOverlappingInBounds:` (all replaced) each call it; plus `objc_getAssociatedObject` (global lock) per read. Resolve the 8 ivar offsets once with `dispatch_once` and `memcpy` from the object.
* `BP2B_FindOverrider` (clipping/scale/tongue fallbacks) walks `nextQueryModifier` per call and, when that is nil, builds `NSMutableArray`s over the child tree (up to 512 nodes); called per leaf per layout. Only if `nextQueryModifier` of the root is nil (UNSURE in the md).

## F11. Missing guard
`BP2B_AutoLayout` (G2B.m:733) sends `attributesByModifyingAttributedSize:` etc. with plain `objc_msgSend`. They exist only if `BP2B_SetupAttributes` completed; its early returns (G2B.m:505, 515-516: not 16.0 layout, probe mismatch) leave `gBP2B_Init16 == NULL` and no such methods. Add `if (!gBP2B_Init16) return nil;` as the first line (falls back to the 16.0 IMP).

## F12. Minor deviations
* G2B.m:1689-1690: the shims take `BOOL hover` and forward it to `pointerIsHoveringOverEdge:` whose parameter is `unsigned long long edge` (16.0 dump). Pass the value through with the original type.
* G2B.m:1338-1341: `SBFluidBehaviorSettings` for the accessory keyboard-height animation lacks the 16.2 `setFrameRateRange:highFrameRateReason:` (0x1c744... listing `lay162.txt`); visual only.
* `SBDisplayItemLayoutAttributes` extras (reference bounds, semantic size type) are not carried through `protobufRepresentation`/`layoutAttributesWithProtobufRepresentation:` (only the plist path is extended), so a state restore via protobuf loses them; the plist path writes `CGRectNull` as `{inf,inf,0,0}` dictionaries, which read back identically.
* `BP2B_ApertureController` / `restrictSystemApertureToInertWithReason:` path is dead on 16.0 (`zoomToJindoCollapseToInert` does not exist in 16.0, the code returns first): harmless.
* The mixed-in test `SBAppLayout -continuousExposeIdentifier` replacement (G2.x:1432) changes the 16.0 identity (first bundle id + "&"+ following ids for valid split-view roles, 0x1c628d514/0x1c628d62c) to the 16.2 set-joined form, sorted for determinism; all in-process consumers go through the same method, so consistent, but it is a change of persisted-looking keys for classic multi-item layouts (nothing found that persists it).

---------------------------------------------------------------------------------------------------

## PASS list (explicit)
* Build guard exact (`kern.osversion == "20A8372"`), nothing registered before it; only Tweak.x has a Logos constructor.
* %ctor order: `BP2B_Early` is first and nothing before it messages a modifier class.
* Trampoline table claim: 81 entries, identical in the query and context tables, all 22 extension encodings present, 4 new 16.2 encodings correctly excluded; gating on 20A8372 + dynamic whitelist correct.
* Breadcrumb written before, cleared after, survives abort/exception/kill; auto-disables next launch (modulo F6).
* Hook signatures of G2.x (9-arg builder, cache key, model copy, `_update...Identifiers...`, hover, strips unoccluded), BP2B replaced methods and the ABI of the 11-argument calculator/12-argument frame blocks.
* Stage Manager OFF / classic: `_layoutAppLayout`, calculator, keyboard navigation, key list, can-perform, tongue, aperture, dispatch/layout/order wrappers are pass-through or call the saved 16.0 IMP first (F3 is the exception).
* `BP_OptInName` use for opt-in features; `kFeatureNames`/`kOptIn` consistent; slot table cannot overflow in practice (about 90 names).
* ARC: no retain cycles found; weak delegates; associated objects tied to owner lifetime. Exceptions: F5.

## UNSURE / not provable here
* F1 scenario 3 (delegate nil vs VC) does not change the verdict (both are exceptions), but I did not run it; confidence 85%.
* F2 impact on specific 16.0 callers.
* Arithmetic of the 2639-insn `_layoutAppLayout` port and of `BP162ChamoisOverlappingController` (spec's own UNSURE items) was only spot-checked (position term 0x1c7443b38-0x1c7443bd8 matches the port's `X`/`Y` formulas; selector sets match).
