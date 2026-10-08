# Group 2b: reconstruction of the pieces group2-layout-data.md called NOT PORTABLE / PARTIAL (16.2 20C65 -> 16.0 20A8372)

Companion code: `group2b-reconstruct.hooks.m` (same item numbers in comments). Conventions as in group2-layout-data.md
(160 = 20A8372, 162 = 20C65; addresses unslid). Tags per piece: DONE or UNSURE:<what to check on a device>.
Directive: nothing is skipped; "not portable" = "needs a full reimplementation".

Items: (4) CGRegion SPI [done first, smallest] -> (1) layout attributes data model -> (3) calculator hook + fixer ->
(2) `_layoutAppLayout:roleMask:completion:` -> (5) keyboard/shift-select/gesture/aperture/per-display/pointer/tongue -> (6) extended protocols.

---------------------------------------------------------------------------------------------------

## ITEM 4. CoreGraphics CGRegion* SPI: DONE

Question: do the 9 CGRegion functions the 162 `SBChamoisOverlappingController` uses resolve in the 16.0 process?

Method: `./bin/ipsw dsc symaddr <cache> _<name> -i CoreGraphics` (the leading underscore is required: the plain name returns nothing), against both caches, plus the import list of the SpringBoard binaries (`sb_syms.txt` = 160, `sb162_syms.txt` = 162).

| function | 160 CoreGraphics addr | in 160 SpringBoard imports | in 162 SpringBoard imports |
|---|---|---|---|
| CGRegionCreateWithRect | 0x188b024d4 | yes | yes |
| CGRegionCreateUnionWithRegion | 0x188b02cf0 | yes | yes |
| CGRegionCreateDifferenceWithRegion | 0x188b02d98 (export) | yes | yes |
| CGRegionCreateIntersectionWithRegion | 0x188b02aec | **no** | yes |
| CGRegionIsEmpty | 0x188b03618 (export) | yes | yes |
| CGRegionGetBoundingBox | 0x188b021d0 | yes | yes |
| CGRegionEqualToRegion | 0x188b039a0 (export) | yes | yes |
| CGRegionIntersectsRegion | 0x188b04014 (export) | yes | yes |
| CGRegionContainsPoint | 0x188b03b84 | **no** | yes (unused by the controller as far as read) |
Also present in 160: CGRegionCreateEmptyRegion 0x188b02398, CGRegionRelease 0x188b03994, CGRegionCreateCopy 0x188b02798, CGRegionCreateWithRects 0x188b025ac, CGRegionCreateXORWithRegion, CGRegionIsRect. NOT present in either cache: CGRegionGetRects / EnumerateRects / GetRectCount (so there is no public way to iterate the rectangles of a region; the 162 controller only needs bbox/empty/equal/intersects, as in the 162 code).

Result: 7 of the 9 are imported by the 160 SpringBoard itself (so `dlsym(RTLD_DEFAULT)` of them works, they are in the CoreGraphics export trie); `CreateIntersectionWithRegion` and `ContainsPoint` exist in the 160 CoreGraphics image (symtab entry flagged external; whether they are in the export trie, i.e. visible to dlsym, is not provable offline). The ipsw "symtab|external" tag only says which table matched first (160 `CGRegionCreateWithRect` shows symtab while 162 shows export, yet both SpringBoards bind it).

Decision (DONE): the draft in group2-layout-data.hooks.m already had `gRgn` function pointers that disable the controller when one is missing. Item 4 replaces that with: resolve with dlsym; if ALL resolve use CoreGraphics (bit-exact with 16.2), otherwise install a self-contained fallback `BP2BRegion` (canonical banded rectangle set: coordinate-compressed cell grid -> merged rects; supports create-with-rect, union, difference, intersection, isEmpty, bounding box, equality, intersects). The fallback objects are NSObjects so the existing `CFAutorelease`/`CFTypeRef` plumbing of the controller keeps working unchanged (`CFBridgingRetain`). The fallback is also what the unit self-test (`BP2B_RegionSelfTest`) exercises, so both implementations can be compared on device by creating the debug file `Backport162.on.regiontest` (logs mismatches). Region semantics checked against the controller's use: `CGRegionGetBoundingBox` of empty region = CGRectNull-like (we return CGRectZero; the controller tests isEmpty first - re-verify if a UNSURE `_snap` path ever shows odd results), `CGRegionEqualToRegion` is structural equality of the canonical form.

---------------------------------------------------------------------------------------------------

## ITEM 1. SBDisplayItemLayoutAttributes: attributedSize / normalizedCenter data model: DONE (UNSURE:protobuf round trip)

### 1.1 Correction of group2 A7.1 (important)
group2 said "16.0 has absolute size/center". Disassembly says otherwise. 160 `sizeInBounds:` (0x1c614b874), `centerInBounds:` (0x1c614b920), `userConfiguredSizeBeforeOverlappingInBounds:` (0x1c614b9cc) all do
`if (v.x <= 1.0 && v.y <= 1.0 (BSFloatLessThanOrEqualToFloat)) return v * bounds.size else return v` and the class methods `normalizedSizeForSize:inBounds:` / `normalizedPointForPoint:inBounds:` (0x1c614b45c / 0x1c614b4d4) divide by the bounds. So the 16.0 ivars `_size`, `_center`, `_userConfiguredSizeBeforeOverlapping` are ALREADY container-relative fractions (absolute points only as a legacy fallback). The 16.2 change is much smaller than the group2 text suggested.

### 1.2 Exact layouts
| field | 160 ivar (offset) | 162 ivar (offset) |
|---|---|---|
| hash | `_hash` 0x38 | `_hash` 0x8 |
| contentOrientation / lastInteractionTime / sizingPolicy / occlusionState | 0x50 / 0x40 / 0x48 / 0x58 | 0x10 / 0x18 / 0x20 / 0x28 |
| size | `_size` CGSize 0x8 | `_attributedSize` struct {normalizedSize CGSize; referenceBounds CGRect; semanticSizeType q} 0x50..0x88 (56 B) |
| center | `_center` 0x18 | `_normalizedCenter` 0x30 |
| user size | `_userConfiguredSizeBeforeOverlapping` CGSize 0x28 | `_attributedUserSizeBeforeOverlapping` 0x88..0xc0 |
| peek | `_fullyOccludedPeekingCenter` 0x60 | `_unoccludedPeekingCenter` 0x40 |
Object size 0x70 -> 0xc0. 160 hash = `[BSHashBuilder builder]` over orientation, lastInteractionTime, sizingPolicy, size, center, occlusionState, userSize, peek (0x1c614b564); 162 hash covers the same plus referenceBounds/semanticType of both sizes (0x1c75cf1c8). Both `copyWithZone:` allocate a new object through the designated init (not `return self`).
So: 16.0 `_size` == 16.2 `normalizedSize` with `referenceBounds = CGRectNull` and `semanticSizeType = 0`.
`SBDisplayItemAttributedSizeUnspecified()` (162 0x1c75cedc4) = {normalizedSize (0,0), referenceBounds = `CGRectNull` (the constant pointer at 0x1d83e1c78 resolves into CoreGraphics), type 0}; `SizeIsUnspecified` (0x1c75cf03c) = normalizedSize == (0,0).

### 1.3 Algorithms (all decoded instruction by instruction)
`_SBDisplayItemAttributedSizeInfer(size, bounds, defaultSize, screenEdgePadding)` 162 0x1c75cedfc (args: d0,d1 size; d2-d5 bounds; d6,d7 default; stack padding):
```
fw = size.w == bounds.w; fh = size.h == bounds.h          (BSFloatEqualToFloat)
t = fw ? (fh ? 3 : 1) : 2 ;  if (fw || fh) done            // 1 full width, 2 full height, 3 full both
dw = size.w == def.w; dh = size.h == def.h
t = dw ? (dh ? 6 : 4) : 5 ;  if (dw || dh) done            // 4 default width, 5 default height, 6 default size
pw = size.w == bounds.w - 2p; ph = size.h == bounds.h - 2p
t = pw ? (ph ? 9 : 7) : (ph ? 8 : 0)                       // 7 padded width, 8 padded height, 9 padded both, 0 none
result = { size / bounds.size, bounds, t }
```
(group2 A7.1 had the type table wrong: 1 is NOT "unspecified".)

`-_sizeForAttributedSize:inBounds:defaultSize:screenEdgePadding:` 162 0x1c75d0a3c (`sizeInBounds:...` 0x1c75cf618 and `userSizeBeforeOverlappingInBounds:...` 0x1c75cf6b8 are one-line wrappers that pass the struct at +0x50 resp. +0x88):
```
if !(n.w <= 10 && n.h <= 10) return n                       // legacy absolute value, returned unclamped
ref = CGRectIsEmpty(referenceBounds) ? bounds.size : referenceBounds.size
scaled = ref * n
if (cur.w == ref.h && cur.h == ref.w)                       // container is the exact transpose of the reference (rotation)
    switch (type) { 1: W=cur.w; 2: H=cur.h; 3: both; 4: W=def.w; 5: H=def.h; 6: both def; 7: W=cur.w-2p; 8: H=cur.h-2p; 9: both; default scaled }
else if (cur.w*cur.h < ref.w*ref.h && def.w > 0 && def.h > 0)
    return ( min(def.w, max(scaled.w,0)), min(def.h, max(scaled.h,0)) )      // container shrank: never above the default size (no further clamp)
return ( min(cur.w, max(W,0)), min(cur.h, max(H,0)) )
```
Consequences (this is the behaviour change 16.2 buys): in an ordinary resize the window keeps its absolute size (normalized x reference = the size it had), clamped to the new container; only on an exact rotation the semantic type decides (maximized stays maximized, "default width" follows the default, padded stays padded); a shrinking container clamps to the default size.
`centerInBounds:` 162 0x1c75cf654: if `n.x <= 10 && n.y <= 10` -> `(bounds.size.w * n.x, bounds.size.h * n.y)` else unchanged. NOTE the 16.0 threshold is 1.0: a centre whose normalised x/y exceeds 1 (window partly off screen) is mistaken for an absolute point in 16.0. 16.2 fixes it with 10.0; the port replaces 16.0 `centerInBounds:` accordingly.

Persistence: 162 `plistRepresentation` (0x1c75d0200) keys: contentOrientation, lastInteractionTime, sizingPolicy, size (= normalizedSize), referenceBounds, semanticSizeType, center, userConfiguredSizeBeforeOverlapping, referenceBoundsBeforeOverlapping, semanticSizeTypeBeforeOverlapping. `initWithPlistRepresentation:` (0x1c75cfcec) reads each key independently with defaults (missing referenceBounds -> unspecified): THAT is the whole "migration". Protobuf: `SBPBDisplayItemLayoutAttributes` has 15 setters in 162 vs 9 in 160 (new proto fields); the 16.0 proto class cannot carry them.

### 1.4 Conversion design (answers "16.2 consumers on 16.0 persisted state and the other way round")
* 16.0 state -> 16.2 consumers: a 16.0 object is a valid 16.2 object with unspecified extras. The added 16.2 getters/algorithms treat it exactly like 16.2 treats an old plist (ref bounds empty -> normalised x CURRENT bounds, or absolute when > 10). Lossless, no migration pass.
* 16.2-style state -> 16.0 consumers: every 16.0 reader of size/center is replaced by the same algorithm (`sizeInBounds:`, `userConfiguredSizeBeforeOverlappingInBounds:` with an unknown default size: types 4/5/6 degrade to "scaled"; `centerInBounds:` with the 10.0 threshold). A 16.0-format plist reader ignores the new keys; the written `size` is `size/referenceBounds` (<= 1 normally) which 16.0 interprets against the then-current bounds (acceptable downgrade behaviour).
* Where the extras (reference bounds + type) live: an immutable associated object `BP2BAttrExtras` (hooks file). Why not a runtime subclass + `+allocWithZone:` swizzle: instances are created by SpringBoard code we do not control (copy, plist, protobuf, SBAppLayout rebuilds); with associated objects every creator that is ours attaches the extras and every creator that is not (protobuf) yields a valid "unspecified" object. Why not hold nothing: the semantic type is what keeps a maximized window maximized across rotation.
* All methods that construct a new instance are fully reimplemented (`attributesByModifying*` x13 incl. the four 16.2 names, `copyWithZone:`, the two 16.2 designated initialisers) on top of the ORIGINAL 16.0 designated init (so `_hash` stays valid), and `isEqual:` / `plistRepresentation` / `initWithPlistRepresentation:` are wrapped. 16.0 setters of a size reset that size's extras (new value has no semantic info), others carry them.
* Helpers for the rest of the port: `BP2B_AttrSizeInfer`, `BP2B_AttrsSizeInBounds`, `BP2B_AttrsUserSizeInBounds`, `BP2B_AttrsCenterInBounds`, `BP2B_AttrsBySettingAbsolute` (= what the 16.2 calculator does at the end of auto layout: infer the semantic type for the size just computed and store size + centre normalised to the container).
* UNSURE (device): (a) protobuf-restored attributes lose the extras (graceful: they become unspecified, the next ported auto layout re-infers; check by rotating after a SpringBoard respring); (b) `description` is unchanged (does not print the extras).

---------------------------------------------------------------------------------------------------

## ITEM 3. The calculator hook (`_appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...`) + routing to the ported controller: DONE (UNSURE:see 3.5)

### 3.1 Who invokes auto layout in 16.0 (answer to "which 16.0 method")
`-[SBDisplayItemLayoutAttributesCalculator _appLayoutByPerformingAutoLayoutIfNeededInAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:draggingItem:overlappingModelBeforeDragging:bounds:prefersStripHidden:prefersDockHidden:]` (160 0x1c611a81c, 828 insns: group2's "636" counted only up to the first block) has the SAME selector and arguments in 160 and 162 (162 0x1c75a4848, 907 insns). Callers: `_frameForLayoutRole:...skipAutoLayout:` (162 0x1c75a36dc; passes draggingItem/modelBefore = nil when `isChamoisWindowingUIEnabled && !skipAutoLayout`), `appLayoutByDraggingItem:...`, `overlappingModelForAppLayout:...`. 160 got the controller through `-_chamoisOverlappingControllerCache` and `modelForPreferredModel:initialStageFrame:layoutAttributes:draggingItem:modelBeforeDragging:`; 162 calls `modelByPerformingAutoLayoutForModel:chamoisLayoutAttributes:draggingItem:modelBeforeDragging:floatingDockHeight:bounds:screenScale:prefersStripHidden:prefersDockHidden:` (the group2 A4 class). So the hook is a replacement of exactly that method.

### 3.2 160 algorithm (for the record; everything 16.0 does that 16.2 drops is gone from the replacement)
1. `key = [SBAppLayoutOverlappingModelCacheKey cacheKeyForSnapshotOfAppLayout:containerBounds:containerOrientation:hideStrips:hideDock:draggingItem:]`; return `layout` when `layout.cachedLastOverlappingModelKey isEqual:key`.
2. grid = `_chamoisLayoutGridCache`; `gridMax = [grid nearestGridSizeForProposedSize:(attrs.maximumWindowWidthForOverlapping, bounds.height) inBounds:bounds contentOrientation:orientation layoutRestrictionInfo:[SBDisplayItemGridLayoutRestrictionInfo layoutRestrictionInfoWithLayoutRestrictions:0 restrictedSize:(-1,-1)] screenScale:scale chamoisLayoutAttributes:attrs]` (the constants: restrictedSize 0xbff0... = (-1,-1), compare constant = CGSizeZero, primary role constant = 1: all dumped).
3. Pre-pass (>= 2 items): for each item whose role is valid for split view: if `userConfiguredSizeBeforeOverlappingInBounds:` == (0,0) (never recorded): `frame = _frameForLayoutRole(..., skipAutoLayout:YES)`, user size := frame.size; if frame exceeds gridMax in either axis: size := min(gridMax, frame.size). One item: if its user size is non-zero: when above gridMax then size := user size; then user size := (0,0) (restored).
4. Build the preferred model: valid items sorted by their index in `zOrderedItems`; centers/sizes from `_frameForLayoutRole(... skipAutoLayout:YES)`; `[SBChamoisOverlappingModel initWithItems:centersForItems:sizesForItems:userConfiguredSizesBeforeAutoResizingForItems:containerBounds:boundingBox:]` with `initialStageFrameForAppLayout:...` as boundingBox; `modelForPreferredModel:initialStageFrame:layoutAttributes:draggingItem:modelBeforeDragging:` and a `modelByModifyingModelWithBlock:` post step.
5. Write back every item: NEW attributes built with the 160 full init from the model (size, centre, occlusion 3/2/1, user size, peek), `appLayoutByModifyingLayoutAttributesForItems:`, `setCachedLastOverlappingModel:`, `setCachedLastOverlappingModelKey:(key of the new layout)`; ends with an NSAssert "Expected appLayout and newAppLayout to be equal" (pointer compare, line 0x1c9 in 160 / 0x1f2 in 162; not reproduced: the reimplementation does not assert).

### 3.3 162 algorithm (decoded; this is what the replacement implements)
Differences, in order: (a) cache key carries `floatingDockHeight` (group2 A8 `+cacheKeyForSnapshotOfAppLayout:containerBounds:containerOrientation:floatingDockHeight:hideStrips:hideDock:draggingItem:`; the replacement bails out to the original 16.0 body when that factory shim is missing); (b) the pre-pass is the same shape but works on the attributed user size: `userSizeBeforeOverlappingInBounds:defaultSize:screenEdgePadding:` (defaultSize / padding from `chamoisLayoutAttributes.defaultWindowSize`/`screenEdgePadding`), writes `attributesByModifyingAttributedUserSizeBeforeOverlapping:(_SBDisplayItemAttributedSizeInfer(frame.size, bounds, defaultSize, padding))`, `attributesByModifyingAttributedSize:(Infer(min(gridMax, frame.size), ...))`, and in the single-window case resets with `_SBDisplayItemAttributedSizeUnspecified()`; (c) no `initialStageFrameForAppLayout:`, the model is created with the 4 argument init (`initWithItems:centersForItems:sizesForItems:containerBounds:`: no user-size dictionary, no bounding box: the user sizes live in the attributes now), no `modelByModifyingModelWithBlock:` post step; (d) the controller call is the A4 one; (e) the write-back no longer rebuilds attributes with an init: it modifies the existing attributes object step by step:
```
policy = attrs.sizingPolicy
handle = [calc _deviceApplicationSceneHandleForDisplayItem:item]
if (handle) policy = _SBPreferredDisplayItemSizingPolicy(normalizedSizeForSize:modelSize inBounds:bounds, policy, [handle _supportedSizingPoliciesForContentOrientation:attrs.contentOrientation containerOrientation:containerOrientation])
a = [[[[attrs byModifyingSizingPolicy:policy] byModifyingNormalizedCenter:normalizedPoint(center)] byModifyingOcclusionState:(fully?3:partially?2:1)] byModifyingUnoccludedPeekingCenter:normalizedPoint(unoccludedPeekingCenterForItem)]
if (SizeIsUnspecified(a.attributedSize.normalizedSize) || CGRectIsNull(ref) || CGRectIsEmpty(ref)) a = [a byModifyingAttributedSize:Infer(modelSize, bounds, defaultSize, padding)]
```
i.e. 16.2 NEVER rewrites the size of a window that already has an attributed size: auto layout only moves/occludes windows; sizes change only through the user or the pre-pass clamps. (This, with the data model of item 1, is why windows keep their size across container changes.) (f) `setCachedLastOverlappingModelKey:` gets the key of the layout BEFORE the attribute write-back (`[sp,#0x68]` = the layout after the pre-pass), exactly reproduced.
`_SBPreferredDisplayItemSizingPolicy(CGSize normalizedSize, long policy, unsigned long supported)` (162 0x1c7954330) decoded: `both1 = n == (1,1)`; `t = (policy != 2 || both1) ? (policy == 0 ? (both1 ? 2 : 0) : policy) : 0`; `return (t != 2 || (supported & 4)) ? t : ((supported >> 1) & 1)`.
`-[SBDeviceApplicationSceneHandle _supportedSizingPoliciesForContentOrientation:containerOrientation:]` (162 0x1c76b8534) = 160 `_supportedSizingPolicies` (0x1c6227470) with the two orientations as parameters instead of `currentInterfaceOrientation` / `switcherController.interfaceOrientation`; chain `windowScene.switcherController.windowManagementStyle`, `sceneIfExists.settings.sb_displayIdentityForSceneManagers`, `[application supportedSizingPoliciesForSwitcherWindowManagementStyle:displayIdentity:contentOrientation:containerOrientation:]` (selector exists in 160). Added as a `%new` method.
Also decoded for the helpers: `SBLayoutRoleIsValidForSplitView` (160 0x1c63e827c, exported, dlsym works) = roles 1,2,5,6,7,8,9.

### 3.4 Routing (answers "route to BP162ChamoisOverlappingController")
* `-[SBDisplayItemLayoutAttributesCalculator _chamoisOverlappingControllerCache]` is replaced: returns one `BP162ChamoisOverlappingController` per calculator (associated object `kBP2B_CalcController`); nothing in the process uses the 160 controller any more (its only caller was the replaced method).
* the replaced auto layout returns `nil` from `BP2B_AutoLayout` (and then calls the saved original 16.0 IMP) when anything is missing: controller class absent, cache-key shim absent, grid cache / restriction-info class absent, model 4-arg init (and 6-arg init) absent, bounds empty, or the `g2b` kill switch. The controller itself returning nil (region SPI missing) keeps the preferred model (no overlapping adjustments but still a valid layout).
* thread-local context `gBP2B_Ctx`: the unchanged 160 `_frameForLayoutRole:` (wrapped) sets `{defaultWindowSize, screenEdgePadding}` of its `chamoisLayoutAttributes` argument; the replaced legacy `sizeInBounds:` / `userConfiguredSizeBeforeOverlappingInBounds:` use them, so the 160 frame code evaluates semantic types 4/5/6 (default size) and 7/8/9 (padding) exactly as 16.2's `sizeInBounds:defaultSize:screenEdgePadding:` call sites do, without copying the 671-instruction 162 body.

### 3.5 What is NOT identical (honest list)
* 162 `_frameForLayoutRole:` (0x1c75a3614, 662 filtered insns; 160: 379) was read to the end but not copied. Its Stage Manager branch additionally (i) clamps the proposed size height by `CGRectInset(bounds, pad, pad)`, (ii) calls `[grid nearestGridSizeForProposedSize:...]` with `layoutRestrictionInfoForItem:` (min/max sizes of the app) when the sizing policy is 1, (iii) for `requiresFullScreen` returns `defaultWindowSize`, (iv) positions new windows centred (`UIRectCenteredAboutPointScale(SBRectWithSize(size), centre, scale)`), RTL-mirrored offsets for the side/center roles (+-10 pt, 0.5 factors), plus os_log warnings when a frame has zero size. UNSURE:check on device that a freshly opened window gets the 16.2 grid-snapped default size (16.0 uses its own default-size logic); if not, port 0x1c75a3614 next (control flow is already listed above: the pieces are `layoutAttributesForItemInRole:`, `sizingPolicy == 1` branch, `cachedLastOverlappingModel sizeForItem:`, `sizeInBounds:defaultSize:screenEdgePadding:`, `centerInBounds:`).
* `appLayoutByDraggingItem:` / `overlappingModelForAppLayout:` pass through unchanged (they call the replaced method).
* the pointer-equality NSAssert is dropped (it would crash if `appLayoutByModifyingLayoutAttributesForItems:` returned a new object; 160's returns `self` only when the merged map `isEqual:`s the old one).
