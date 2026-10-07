# SBFullScreenContinuousExposeSwitcherModifier (iPadOS 16.2 build 20C65) vs 16.0 (20A8372)

Superclass: `SBSwitcherModifier` (-> `SBChainableModifier`).
16.2 class object 0x1de2306e8, 89 instance methods (incl. accessors, `descriptionBuilder...`, `.cxx_destruct`).
16.0 class object 0x1de09d5a8, 98 instance methods, protocol `SBSwitcherLayoutCalculationsCacheDelegate` (16.2: none).
All addresses are unslid dyld-cache VM addresses (16.2 unless stated).  Class dump: `sb162_objc.txt` line 55829 (16.2),
`sb160n_objc.txt` line 53588 (16.0).  Annotated disassembly used for this spec: `dis162/` and `dis160/` in the scratchpad
(generated with `ann.py`, which resolves ivar offsets, class refs, selectors, cstrings, literal-pool doubles).

## 0. TL;DR

* In 16.0 this class did *everything*: full-screen stage app layout + the whole Continuous Expose (Stage Manager) strip
  (layout cache, piles, displacement timer, highlight handling, wallpaper gradient, 3D transforms ...).
* In 16.2 it is a thin **floor modifier** with two children:
  1. `_fullScreenAppLayoutModifier` (`SBFullScreenAppLayoutSwitcherModifier`) - answers geometry for the stage app, added first;
  2. `_stripModifier` (`SBStripContinuousExposeSwitcherModifier`, NEW class, specced separately) - answers everything about the strip.
  Every per-index query is `if ([self _isAppLayoutEffectivelyOnStage:layout]) { answer here } else { return [super ...]; }`,
  where `[super ...]` falls into the SBChainableModifier child chain and ends at the strip modifier.
* New 16.2 behaviour owned by this class: (1) stage app is **scaled + translated** (not only shifted) when the strip is revealed
  from the hidden state (`_continuousExposeStripRevealProgress`), using the new `SBChamoisOverlappingModel` bounding box;
  (2) keyboard (cmd-`) window cycling z-order bookkeeping (`handleTransitionEvent:`); (3) tap/header/pointer-boundary handling;
  (4) new dock-behaviour queries (`dockProgress`=1.0, `dockUpdateMode`=3, `wantsDockBehaviorAssertion`);
  (5) `handlesTapAppLayoutEvents` / `handlesTapAppLayoutHeaderEvents` switches so embedding modifiers can disable tap handling.

Conventions in the code below: `UIApp` = `[UIApplication sharedApplication]`; "RTL" = `[UIApp userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft (1)`;
`SBAppendResponse(new, old)` = C function `_SBAppendSwitcherModifierResponse(new, old)` (16.2 0x1c773a35c, 16.0 0x1c62a07b4);
CGRect/CGPoint args and results travel in d0..d3 / d0..d1 exactly like normal AAPCS64 HFAs.  `[super X]` is a real `objc_msgSendSuper2`
to `SBSwitcherModifier`, whose dynamic implementation consults the child-modifier chain (see "Wiring").

---------------------------------------------------------------------------------------------------

## 1. Instance variables

### 16.2 (offsets from class dump; verified from the `__objc_ivar` offset words at 0x1db416010..0x1db416024)

| offset | type / name | purpose |
|---|---|---|
| 0x60 | `SBStripContinuousExposeSwitcherModifier *_stripModifier` | child created in init (`alloc/init`), added 2nd. All strip layout/highlight state lives there. `highlightedBy{Touch,Hover}AppLayouts` (+setters) forward to it. |
| 0x68 | `SBFullScreenAppLayoutSwitcherModifier *_fullScreenAppLayoutModifier` | child created with `initWithActiveAppLayout:fullScreenAppLayout`, added 1st. Supplies stage-app `frameForIndex:`/`scaleForIndex:`. |
| 0x70 | `NSArray *_zOrderedLeafAppLayoutsForKeyboardNavigation` | snapshot of `[_fullScreenAppLayout zOrderedLeafAppLayouts]` used to cycle windows with the keyboard; returned by `activeLeafAppLayoutsReachableByKeyboardShortcut`; reset by `_resetKeyboardNavigationZOrder`. |
| 0x78 | `BOOL _handlesTapAppLayoutEvents` | default YES (init). When NO, `handleTapAppLayoutEvent:` only calls super. Property `handlesTapAppLayoutEvents`. |
| 0x79 | `BOOL _handlesTapAppLayoutHeaderEvents` | default YES. Same for `handleTapAppLayoutHeaderEvent:`. |
| 0x80 | `SBAppLayout *_fullScreenAppLayout` | the app layout currently on stage. Readonly property `fullScreenAppLayout`. |

`@property (retain) NSMutableSet *highlightedByTouchAppLayouts / highlightedByHoverAppLayouts` have **no ivars** in 16.2 (forwarders).
Ivar total size = 0x88.

### 16.0

| offset | ivar | purpose (16.0) |
|---|---|---|
| 0x60 | `SBFullScreenAppLayoutSwitcherModifier *_fullScreenAppLayoutModifier` | same as 16.2 (now at 0x68) |
| 0x68 | `unsigned long long _timerEventGenerationCount` | counter for displacement timer reasons (`"SBFullScreenContinuousExposeSwitcherModifierDisplaceFullScreenAppLayoutTimerEventReason-%lu"`) |
| 0x70 | `NSString *_expectedTimerEventReason` | validates the 0.6 s timer |
| 0x78 | `double _cached_leftStripOriginX` | cache for `_leftStripOriginX` |
| 0x80 | `SBSwitcherLayoutCalculationsCache *_stripLayoutCache` | strip layout cache (delegate = self) -> now inside `SBStripContinuousExposeSwitcherModifier` |
| 0x88 | `unsigned long long _modifierEventGenCount` | cache invalidation token (bumped in `handleEvent:`) |
| 0x90 | `SBAppLayout *_fullScreenAppLayout` | (now 0x80) |
| 0x98 | `NSString *_appPileBundleIDToBringForwardIfAny` | bundle id whose pile should be brought forward (launch of ambiguous app) - **dropped in 16.2** |
| 0xa0 | `NSMutableSet *_highlightedByTouchAppLayouts` | -> strip modifier in 16.2 |
| 0xa8 | `NSMutableSet *_highlightedByHoverAppLayouts` | -> strip modifier in 16.2 |
| 0xb0 | `long long _fullScreenAppDisplacementState` | 0 none, 1 pending (timer running), 2 displaced (stage app shifted right by strip width) - **dropped in 16.2** (replaced by `_continuousExposeStripRevealProgress` driven scaling) |

Ivars new in 16.2: `_stripModifier`, `_zOrderedLeafAppLayoutsForKeyboardNavigation`, `_handlesTapAppLayoutEvents`, `_handlesTapAppLayoutHeaderEvents`.
Ivars removed: everything in the 16.0 table except `_fullScreenAppLayoutModifier` and `_fullScreenAppLayout` (both moved offsets).

---------------------------------------------------------------------------------------------------

## 2. Reconstruction of every 16.2 method (address order)

Header:

```objc
@interface SBFullScreenContinuousExposeSwitcherModifier : SBSwitcherModifier {
    SBStripContinuousExposeSwitcherModifier *_stripModifier;                 // 0x60
    SBFullScreenAppLayoutSwitcherModifier   *_fullScreenAppLayoutModifier;   // 0x68
    NSArray   *_zOrderedLeafAppLayoutsForKeyboardNavigation;                 // 0x70
    BOOL       _handlesTapAppLayoutEvents;                                   // 0x78
    BOOL       _handlesTapAppLayoutHeaderEvents;                             // 0x79
    SBAppLayout *_fullScreenAppLayout;                                       // 0x80
}
@property (readonly, nonatomic) SBAppLayout *fullScreenAppLayout;
@property (retain, nonatomic) NSMutableSet *highlightedByTouchAppLayouts;
@property (retain, nonatomic) NSMutableSet *highlightedByHoverAppLayouts;
@property (nonatomic) BOOL handlesTapAppLayoutEvents;
@property (nonatomic) BOOL handlesTapAppLayoutHeaderEvents;
@end
```

### 2.1 Init / description / forwarded properties

```objc
// 0x1c75c2990
- (instancetype)initWithFullScreenAppLayout:(SBAppLayout *)appLayout {
    self = [super init];                         // objc_msgSendSuper2 "init"
    if (self) {
        // Non-nil check.  asm: if (appLayout == nil) { [[NSAssertionHandler currentHandler]
        //   handleFailureInMethod:_cmd object:self file:@"SBFullScreenContinuousExposeSwitcherModifier.m"
        //   lineNumber:45 (0x2d) description:@"Invalid parameter not satisfying: %@", @"appLayout"]; }  (16.0: line 58 / 0x3a)
        NSParameterAssert(appLayout);
        _fullScreenAppLayout = appLayout;                      // objc_storeStrong ivar 0x80
        [self _resetKeyboardNavigationZOrder];                 // NEW in 16.2, must come after the store above
        _handlesTapAppLayoutEvents = YES;                      // strb 1 -> 0x78
        _handlesTapAppLayoutHeaderEvents = YES;                // strb 1 -> 0x79
        _fullScreenAppLayoutModifier = [[SBFullScreenAppLayoutSwitcherModifier alloc] initWithActiveAppLayout:appLayout]; // 0x1c75cc198
        [self addChildModifier:_fullScreenAppLayoutModifier];  // 0x1c78d8e40, child #1
        _stripModifier = [[SBStripContinuousExposeSwitcherModifier alloc] init]; // alloc_init
        [self addChildModifier:_stripModifier];                // child #2
    }
    return self;
}
// No gesture / transition / layout-cache delegate is set in 16.2 (16.0 did `_stripLayoutCache.delegate = self`
// and created NSMutableSet x2 + SBSwitcherLayoutCalculationsCache).  addChildModifier: is the plain variant (no level/key).

// 0x1c75c2ae8   (16.0: absent)
- (id)descriptionBuilderWithMultilinePrefix:(NSString *)prefix {
    BSDescriptionBuilder *b = [self succinctDescriptionBuilder];        // 0x1c78da354
    [b appendBodySectionWithName:nil multilinePrefix:prefix block:^{   // block 0x1c75c2bac
        [b appendObject:_fullScreenAppLayout withName:@"fullScreenAppLayout"];
        [b appendBool:_handlesTapAppLayoutEvents withName:@"handlesTapAppLayoutEvents"];
        [b appendBool:_handlesTapAppLayoutHeaderEvents withName:@"handlesTapAppLayoutHeaderEvents"];
        [b appendObject:[_stripModifier succinctDescription] withName:@"stripModifier"];
        [b appendObject:[_fullScreenAppLayoutModifier succinctDescription] withName:@"fullScreenAppLayoutModifier"];
    }];
    return b;
}   // (description only - not needed for a backport)

// 0x1c75c2cd4 / 0x1c75c2ce4 / 0x1c75c2cf4 / 0x1c75c2d04
- (NSMutableSet *)highlightedByTouchAppLayouts          { return [_stripModifier highlightedByTouchAppLayouts]; }   // tail call 0x1c7d6d440
- (void)setHighlightedByTouchAppLayouts:(NSMutableSet *)s { [_stripModifier setHighlightedByTouchAppLayouts:s]; }   // tail call 0x1c7dab1a0
- (NSMutableSet *)highlightedByHoverAppLayouts          { return [_stripModifier highlightedByHoverAppLayouts]; }   // 0x1c7d6d420
- (void)setHighlightedByHoverAppLayouts:(NSMutableSet *)s { [_stripModifier setHighlightedByHoverAppLayouts:s]; }   // 0x1c7dab180
// 16.0: plain ivar getters/setters (0x1c6141d9c/dac/dc0/dd0).  Used by SBContinuousExposeRootSwitcherModifier to carry
// highlight state over when it replaces one full-screen floor modifier with another.

// 0x1c75c55a4  0x1c75c55b4  0x1c75c55c4  0x1c75c55d4  0x1c75c55e4
- (SBAppLayout *)fullScreenAppLayout                      { return _fullScreenAppLayout; }
- (BOOL)handlesTapAppLayoutEvents                          { return _handlesTapAppLayoutEvents; }
- (void)setHandlesTapAppLayoutEvents:(BOOL)v               { _handlesTapAppLayoutEvents = v; }
- (BOOL)handlesTapAppLayoutHeaderEvents                    { return _handlesTapAppLayoutHeaderEvents; }
- (void)setHandlesTapAppLayoutHeaderEvents:(BOOL)v         { _handlesTapAppLayoutHeaderEvents = v; }

// 0x1c75c55f4  .cxx_destruct: objc_storeStrong(nil) on _fullScreenAppLayout(0x80), _zOrderedLeaf...(0x70),
//              _fullScreenAppLayoutModifier(0x68), _stripModifier(0x60), in that order.  (16.0 released 7 ivars.)
```

### 2.2 Strip progress / "effectively on stage" helpers

```objc
// 0x1c75c2d14   NEW (16.0 equivalent: -_effectiveStripVisibleProgress 0x1c6141464, which returned
//                [self continuousExposeAppStripUnoccludedProgress] -- same shape, renamed query)
- (double)continuousExposeStripProgress {
    if ([self _anyItemExceedsWidthThresholdToHideStrip] || [self prefersStripHidden])
        return [self _continuousExposeStripRevealProgress];
    return 1.0;                                                      // strip is permanently shown
}

// 0x1c75c2d6c   NEW
- (double)_continuousExposeStripRevealProgress {
    return [super continuousExposeStripProgress];                    // objc_msgSendSuper2; asks the children/gesture modifiers
}                                                                    // (e.g. the reveal-strip gesture modifier) for 0..1 progress

// 0x1c75c4378   NEW
- (BOOL)_isFullScreenAppLayout:(SBAppLayout *)appLayout {
    return [appLayout isEqual:_fullScreenAppLayout]
        && [self appLayoutContainsAnUnoccludedMaximizedDisplayItem:appLayout];      // 0x1c7d4ee00
}

// 0x1c75c5334   NEW  (16.0 inlined only the first clause inside frameForIndex: / scaleForIndex: etc.)
- (BOOL)_isAppLayoutEffectivelyOnStage:(SBAppLayout *)appLayout {
    if ([_fullScreenAppLayout containsAllItemsFromAppLayout:appLayout] ||
        [appLayout containsAllItemsFromAppLayout:_fullScreenAppLayout])
        return YES;
    NSUInteger max = [[[self switcherSettings] chamoisSettings] maximumNumberOfAppsOnStage];   // 0x1c78c3020
    if ([[_fullScreenAppLayout allItems] count] != max) return NO;
    NSArray *items = [appLayout allItems];
    if ([items count] != max) return NO;
    // block 0x1c75c54ac (captures self): ^BOOL(SBDisplayItem *i){ return [self->_fullScreenAppLayout containsItem:i]; }
    NSArray *shared = [items bs_filter:^BOOL(SBDisplayItem *i){ return [_fullScreenAppLayout containsItem:i]; }];
    return [shared count] == max - 1;       // full stage that differs from the stage layout by exactly one window
}

// 0x1c75c54c4   NEW
- (BOOL)_isStripRevealedFromHidden {
    if ([self _anyItemExceedsWidthThresholdToHideStrip] || [self prefersStripHidden])
        return BSFloatGreaterThanFloat([self _continuousExposeStripRevealProgress], 0.0);
    return NO;
}

// 0x1c75c5520   NEW
- (unsigned int)_continuousExposeStripEdge {
    return ([UIApp userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft) ? 2 : 0;  // CGRectMaxXEdge : CGRectMinXEdge
}

// 0x1c75c5244   (16.0 0x1c61414bc: 73 instr; walked _itemsValidForOverlapping, took frameForLayoutRole:...width of each role item of the
//                full-screen layout and compared with _widthThresholdToHideStrip)
- (BOOL)_anyItemExceedsWidthThresholdToHideStrip {
    SBChamoisOverlappingModel *m = [self overlappingModelForAppLayout:_fullScreenAppLayout];   // 0x1c7652fc4
    return ![m isContinuousExposeStripVisible];                                               // 0x1c797a558 (NEW)
}

// 0x1c75c4600   NEW
- (BOOL)_wantsContinuousExposeHoverGestureForDismissingStrip {
    return BSFloatGreaterThanFloat([self _continuousExposeStripRevealProgress], 0.0);   // tail call
}

// 0x1c75c45ac   NEW
- (BOOL)wantsContinuousExposeHoverGesture {
    BOOL s = [super wantsContinuousExposeHoverGesture];
    return s | [self _wantsContinuousExposeHoverGestureForDismissingStrip];
}

// 0x1c75c5550   NEW
- (void)_resetKeyboardNavigationZOrder {
    _zOrderedLeafAppLayoutsForKeyboardNavigation = [_fullScreenAppLayout zOrderedLeafAppLayouts];   // 0x1c7725460 (new in 16.2)
}

// 0x1c75c3f14   NEW
- (NSArray *)activeLeafAppLayoutsReachableByKeyboardShortcut { return _zOrderedLeafAppLayoutsForKeyboardNavigation; }

// 0x1c75c3eec   NEW
- (BOOL)canSelectLeafWithModifierKeysInAppLayout:(SBAppLayout *)appLayout {
    return ![_fullScreenAppLayout isOrContainsAppLayout:appLayout];
}
```

### 2.3 Geometry queries

```objc
// 0x1c75c2da4   (16.0 0x1c613d7c0, 123 instr)
- (CGRect)frameForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout])
        return [_fullScreenAppLayoutModifier frameForIndex:index];
    return [super frameForIndex:index];            // -> strip modifier
}
// 16.0: super frame (only .size used); if fullScreen contains-all(layout)||layout contains-all(fullScreen):
//   frame = [_fullScreenAppLayoutModifier frameForIndex:]; then shift origin.x by  +/-0.5*scaleForIndex*stripWidth*K
//   where K = 1 if _fullScreenAppDisplacementState==2 else (continuousExposeAppStripUnoccludedProgress if >0 &&
//   _anyItemExceedsWidthThresholdToHideStrip); sign by RTL.   else (strip item) frame computed from _stripLayoutCache and
//   re-centred (centre - size/2).  All strip work now lives in SBStripContinuousExposeSwitcherModifier.

// 0x1c75c2e74   (16.0 0x1c613daf0, 125 instr)
- (CGPoint)anchorPointForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout]) return CGPointMake(0.5, 0.5);
    return [super anchorPointForIndex:index];
}
// 16.0: stage layout -> [super anchorPointForIndex:]; strip layouts -> x=(pileIndex*stackDistance/..)/..., y=0.5 (RTL mirrored).

// 0x1c75c2f1c   (16.0 0x1c613ddb8, 151 instr)
- (double)scaleForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout])
        return [_fullScreenAppLayoutModifier scaleForIndex:index];
    return [super scaleForIndex:index];
}
// 16.0: for the stage layout additionally multiplied by 1+progress*(min((containerW-stripW-screenEdgePadding*(validItems>1?2:1))/overlappingModel.containerBounds.width,1)-1)
//   when stripUnoccludedProgress>0 && _anyItemExceedsWidth...; strip layouts: cached stripCardScale-based scale with -0.01*pileIndex.

// 0x1c75c2fcc  (16.0 0x1c613e0d0)
- (CGRect)adjustedSpaceAccessoryViewFrame:(CGRect)frame forAppLayout:(SBAppLayout *)appLayout {
    if (![self _isAppLayoutEffectivelyOnStage:appLayout])
        return [super adjustedSpaceAccessoryViewFrame:frame forAppLayout:appLayout];
    return frame;
}
// 16.0: if !fullScreen.isOrContains(layout): origin.x = _leftStripOriginX - (±stripWidth * floor(pileIdx/visiblePiles)) - 0.5*frame.width.

// 0x1c75c3080  (16.0 0x1c613e228)
- (CGPoint)adjustedSpaceAccessoryViewAnchorPoint:(CGPoint)p forAppLayout:(SBAppLayout *)appLayout {
    if (![self _isAppLayoutEffectivelyOnStage:appLayout])
        return [super adjustedSpaceAccessoryViewAnchorPoint:p forAppLayout:appLayout];
    return p;
}
// 16.0: if !fullScreen.isOrContains(layout): p.x = RTL ? 1.0 : 0.0.

// 0x1c75c310c  (16.0 0x1c613e288, 73 instr)   *** the new stage "squeeze" geometry ***
- (CGRect)frameForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout withBounds:(CGRect)bounds {
    CGRect frame = [super frameForLayoutRole:role inAppLayout:appLayout withBounds:bounds];     // origin x,y + size w,h
    if ([self _isAppLayoutEffectivelyOnStage:appLayout]) {
        double progress = [self _continuousExposeStripRevealProgress];                          // d12
        if (BSFloatGreaterThanFloat(progress, 0.0)) {
            double containerW = [self containerViewBounds].size.width;                          // d15
            SBSwitcherChamoisLayoutAttributes *attrs = [self chamoisLayoutAttributes];
            SBChamoisOverlappingModel *model = [self overlappingModelForAppLayout:_fullScreenAppLayout];
            CGRect bb = [model boundingBox];                                                   // 0x1c797afe4
            double stripW = [attrs stripWidth], pad = [attrs screenEdgePadding];
            double fit   = MIN((containerW - stripW - pad) / bb.size.width, 1.0);             // fminnm        (d8)
            double bbCx  = bb.origin.x + bb.size.width * 0.5;                                  // d14
            double bbCy  = bb.origin.y + bb.size.height * 0.5;
            double mid   = (stripW + (containerW - pad)) * 0.5;
            double leftC = MIN(mid, stripW + bb.size.width * fit * 0.5);                      // d15 (fcsel mi)
            // if the scaled bounding box would already clear the strip keep its centre, else slide it right of the strip
            double targetCx = BSFloatGreaterThanFloat(bbCx - bb.size.width * 0.5 * fit, stripW) ? bbCx : leftC;  // d13
            double s = 1.0 + progress * (fit - 1.0);                                          // interpolated scale, d8
            double dx = (targetCx - bbCx) * progress + 0.0;
            if ([self isRTLEnabled]) dx = -dx;
            SBDisplayItem *item = [appLayout itemForLayoutRole:role];
            CGPoint c = [model centerForItem:item];                                           // 0x1c797a298
            // keep the scale anchored on the bounding-box centre rather than on the item's own centre
            frame.origin.x = (frame.origin.x - (1.0 - s) * (c.x - bbCx)) + dx;
            frame.origin.y =  frame.origin.y - (1.0 - s) * (c.y - bbCy);
            // size is NOT modified (the shrink is applied by -scaleForLayoutRole:inAppLayout:)
        }
    }
    return frame;
}
// 16.0: frame = super; if [model isItemPartiallyOccluded:item] { c = UIRectGetCenter(frame); s = [self scaleForLayoutRole:...];
//   frame.origin -= (1-s)*((c + bb.origin) - 0.5*containerSize) } -> occlusion "dodge" compensation, no strip squeeze.

// 0x1c75c3360  (16.0 0x1c613e410, 91 instr)
- (double)scaleForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    double scale = [super scaleForLayoutRole:role inAppLayout:appLayout];
    if ([self _isAppLayoutEffectivelyOnStage:appLayout]) {
        double progress = [self _continuousExposeStripRevealProgress];
        if (BSFloatGreaterThanFloat(progress, 0.0)) {
            double containerW = [self containerViewBounds].size.width;
            SBSwitcherChamoisLayoutAttributes *attrs = [self chamoisLayoutAttributes];
            SBChamoisOverlappingModel *model = [self overlappingModelForAppLayout:_fullScreenAppLayout];
            CGRect bb = [model boundingBox];
            double fit = MIN((containerW - [attrs stripWidth] - [attrs screenEdgePadding]) / bb.size.width, 1.0);
            // (asm also evaluates BSFloatGreaterThanFloat(bbCx - bbW/2*fit, stripWidth) here but discards the result)
            scale *= 1.0 + progress * (fit - 1.0);
        }
    }
    return scale;
}
// 16.0: scale = super; layout=[self appLayoutContainingAppLayout:appLayout]; item role lookup; if model isItemFullyOccluded -> *= attrs.stageOcclusionDodgingPeekScale
//   elif isItemPartiallyOccluded -> *= attrs.stageOccludedAppScale; then, if _indexOfAppLayoutInAppLayoutsForContinuousExposeIdentifierIgnoringStage==0:
//   (pile highlight) hover&&touch -> *0.98 ; hover only -> *1.1 ; touch only -> *0.9 ; neither -> *1.0. (-> strip modifier _highlightScaleForAppLayout:)

// 0x1c75c34c0  (16.0 0x1c613e5c0)
- (NSSet *)visibleAppLayouts {
    return [[super visibleAppLayouts] setByAddingObject:_fullScreenAppLayout];
}
// 16.0: [[self _orderedVisibleAppLayouts] set]   (NSMutableOrderedSet: fullScreenAppLayout + up to numberOfVisibleContinuousExposeIdentifiersWhileInApp strip piles)

// 0x1c75c353c
- (NSArray *)appLayoutsToCacheSnapshots        { return [[self visibleAppLayouts] allObjects]; }
// 0x1c75c3588
- (NSArray *)appLayoutsToCacheFullsizeSnapshots { return @[]; }                       // _NSArray0__struct

// 0x1c75c4284  (16.0 0x1c613fb28)
- (NSArray *)topMostLayoutElements {
    NSArray *elems = [[super topMostLayoutElements] sb_arrayByInsertingOrMovingObject:_fullScreenAppLayout toIndex:0]; // 0x1c74dcbd4
    id tongue = [self continuousExposeStripTongueBackdropCaptureLayoutElement];       // NEW query (SBSwitcherAccessoryLayoutElement) may be nil
    if (tongue) {
        NSMutableArray *m = [elems mutableCopy];
        [m removeObject:_fullScreenAppLayout];
        [m insertObject:tongue atIndex:0];
        [m insertObject:_fullScreenAppLayout atIndex:0];     // => [fullScreenAppLayout, tongue, ...]
        elems = m;
    }
    return elems;
}
// 16.0: [[self _orderedVisibleAppLayouts] array]

// 0x1c75c3594  (16.0 0x1c613ebf4)
- (UIRectCornerRadii)cornerRadiiForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout]) {
        double r = [self displayCornerRadius];                                           // 0x1c7d62020
        if (BSFloatIsZero(r) && ![self appLayoutContainsAnUnoccludedMaximizedDisplayItem:layout])
            r = [[self chamoisLayoutAttributes] stageCornerRaddii];                      // (sic) selector spelling "Raddii"
        return SBRectCornerRadiiForRadius(r / [self scaleForIndex:index]);               // SpringBoardUIServices 0x1a44befc4
    }
    return [super cornerRadiiForIndex:index];
}
// 16.0: same stage branch (condition isOrContainsAppLayout) but the else branch computed [attrs stripCornerRaddii]/scale locally.

// 0x1c75c36a4  (16.0 0x1c613ecf8 = constant 0xf)
- (NSUInteger)maskedCornersForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout])
        return [self appLayoutContainsAnUnoccludedMaximizedDisplayItem:layout] ? 0 : 0xf;   // maximized window: square corners
    return [super maskedCornersForIndex:index];
}

// 0x1c75c3750  (16.0 0x1c613ed00 = constant 1.0)
- (double)shadowOpacityForLayoutRole:(SBLayoutRole)role atIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    return [self _isAppLayoutEffectivelyOnStage:layout] ? 1.0 : [super shadowOpacityForLayoutRole:role atIndex:index];
}
// 0x1c75c37fc   - (long long)shadowStyleForLayoutRole:(long long)r inAppLayout:(id)l { return 5; }          // 16.0 same (0x1c613ed08)
// 0x1c75c3804   - (BOOL)shouldUseWallpaperGradientTreatment { return YES; }                                  // 16.0 same
// 0x1c75c380c  (16.0 0x1c613ed18, 171 instr: dimming/perspective/3D-transform based gradient extent)
- (SBSwitcherGradientWallpaperAttributes)wallpaperGradientAttributesForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout]) return SBSwitcherGradientWallpaperAttributesMakeEmpty();  // 0x1c78951dc
    return [super wallpaperGradientAttributesForIndex:index];
}
// 0x1c75c38b4   - (long long)headerStyleForIndex:(NSUInteger)i { return 1; }                                  // 16.0 same
// 0x1c75c38bc   - (double)contentPageViewScaleForAppLayout:(id)l withScale:(double)s { return s; }            // 16.0 same (bare ret)
// 0x1c75c38c0  (16.0 0x1c613f1a8: stage layout 0, else (pile index==0 ? 1 : 0))
- (double)titleAndIconOpacityForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    return [self _isAppLayoutEffectivelyOnStage:layout] ? 0.0 : [super titleAndIconOpacityForIndex:index];
}
// 0x1c75c395c   - (double)titleOpacityForIndex:(NSUInteger)i { return 0.0; }
// 0x1c75c3964   - (double)dimmingAlphaForLayoutRole:(long long)r inAppLayout:(id)l { return 0.0; }
// 0x1c75c396c   - (double)backgroundOpacityForIndex:(NSUInteger)i { return 0.0; }          (all three: 16.0 same constants)

// 0x1c75c420c  (16.0 0x1c613faac: stage 0.0 else +/- attrs.stripTiltAngle by RTL)
- (double)perspectiveAngleForAppLayout:(SBAppLayout *)appLayout {
    return [self _isAppLayoutEffectivelyOnStage:appLayout] ? 0.0 : [super perspectiveAngleForAppLayout:appLayout];
}

// 0x1c75c4368   - (BOOL)shouldAnimateInsertionOrRemovalOfAppLayout:(id)l atIndex:(NSUInteger)i { return NO; }
// 0x1c75c4370   - (BOOL)shouldAccessoryDrawShadowForAppLayout:(id)l { return NO; }
// 0x1c75c3f6c   - (BOOL)shouldAllowGroupOpacityForAppLayout:(id)l { return NO; }                 // NEW
// 0x1c75c459c   - (double)spaceAccessoryViewIconHitTestOutsetForAppLayout:(id)l { return 10.0; }  // NEW
// 0x1c75c4594   - (BOOL)wantsSpaceAccessoryViewPointerInteractionsForAppLayout:(id)l { return YES; }

// 0x1c75c4498  (16.0 0x1c613fc78)   *** semantic inversion, see diff ***
- (BOOL)shouldPinLayoutRolesToSpace:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout]) return YES;
    return [super shouldPinLayoutRolesToSpace:index];
}
// 16.0: if (fullScreen.isOrContains(layout) || layout.isOrContains(fullScreen)) return NO; else return [super ...];

// 0x1c75c4530  (16.0 0x1c613fd28)
- (BOOL)shouldUseAnchorPointToPinLayoutRolesToSpace:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    return ![self _isAppLayoutEffectivelyOnStage:layout];          // NOTE: no [super] call any more
}
// 16.0: if (either contains the other) return [super ...]; else return YES.

// 0x1c75c45a4   - (BOOL)isResizeGrabberVisibleForAppLayout:(id)l { return NO; }   // NEW
```

### 2.4 Touch / selection / resize

```objc
// 0x1c75c3974  (16.0 0x1c613f254; logic unchanged, only addresses differ)
- (long long)touchBehaviorForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    if ([_fullScreenAppLayout containsItem:[appLayout itemForLayoutRole:role]])
        return [self _layoutRoleIsOccluded:role inAppLayout:appLayout] ? 1 : 2;
    return [super touchBehaviorForLayoutRole:role inAppLayout:appLayout];
}

// 0x1c75c3a44   NEW
- (BOOL)isItemResizingAllowedForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    return [self appLayoutContainsOnlyResizableApps:appLayout]
        && BSFloatIsZero([self _continuousExposeStripRevealProgress])
        && [self _isAppLayoutEffectivelyOnStage:appLayout];
}

// 0x1c75c5288   (16.0 -_enableItemResizeGrabbersForLayoutRole:inAppLayout: 0x1c6141bf0)
- (BOOL)_shouldEnableItemResizeGrabbersForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    if (!BSFloatIsZero([self _continuousExposeStripRevealProgress]) && [self _anyItemExceedsWidthThresholdToHideStrip]) return NO; // NEW clause
    if (![self isDisplayEmbedded]) return NO;
    if (![self _isAppLayoutEffectivelyOnStage:appLayout]) return NO;          // 16.0: [_fullScreenAppLayout isOrContainsAppLayout:appLayout]
    if (![self appLayoutContainsOnlyResizableApps:appLayout]) return NO;
    if (!SBLayoutRoleIsValidForSplitView(role)) return NO;                    // 0x1c7894a30
    return ![self _layoutRoleIsOccluded:role inAppLayout:appLayout];
    // 16.0 also required [self isChamoisWindowingUIEnabled] first; 16.2 dropped that check.
}

// 0x1c75c3aac  (16.0 0x1c613f324)
- (NSUInteger)activeCornersForTouchResizeForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    if (![self _shouldEnableItemResizeGrabbersForLayoutRole:role inAppLayout:appLayout])
        return [super activeCornersForTouchResizeForLayoutRole:role inAppLayout:appLayout];       // 16.0 returned 0 here
    NSUInteger idx = [[self appLayouts] indexOfObject:appLayout];
    if (idx == NSNotFound)                                                                          // NEW guard
        return [super activeCornersForTouchResizeForLayoutRole:role inAppLayout:appLayout];
    CGRect layoutFrame = [self frameForIndex:idx];
    CGRect bounds      = [self containerViewBounds];
    CGRect rect        = [self frameForLayoutRole:role inAppLayout:appLayout withBounds:bounds];
    double margin      = [[[self switcherSettings] chamoisSettings] pinWindowEdgeForResizeMargin];  // 0x1c78c2ff8
    if (CGRectGetMaxX(rect) < CGRectGetWidth(layoutFrame) - margin)  return 8;     // right edge free  -> bottom-right grabber (UIRectCornerBottomRight)
    if (CGRectGetMaxY(rect) < CGRectGetHeight(layoutFrame) - margin) return 4;     // bottom free      -> bottom-left
    if (CGRectGetMinY(rect) > margin)                                 return 4;     // not pinned to top
    if (CGRectGetMinX(rect) > margin)                                 return 4;     // not pinned to left
    return ([UIApp userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft) ? 4 : 8;
}
// (unchanged except: _enableItem... -> _shouldEnableItem..., NSNotFound guard, super fallback instead of 0)

// 0x1c75c3cf4  (16.0 0x1c613f514)
- (BOOL)shouldAllowContentViewTouchesForLayoutRole:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    if (![self _isAppLayoutEffectivelyOnStage:appLayout] || [self _isStripRevealedFromHidden]) return NO;
    return [super shouldAllowContentViewTouchesForLayoutRole:role inAppLayout:appLayout];
}
// 16.0: if (_fullScreenAppLayout.isOrContains(layout)) return [super ...]; return NO;

// 0x1c75c3d84  (16.0 0x1c613f5a0)
- (BOOL)isLayoutRoleSelectable:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    if (![self _isAppLayoutEffectivelyOnStage:appLayout] || [self _isStripRevealedFromHidden]) return YES;
    if ([super isLayoutRoleSelectable:role inAppLayout:appLayout]) return YES;
    return [self _layoutRoleIsOccluded:role inAppLayout:[self appLayoutContainingAppLayout:appLayout]];
}
// 16.0: if (!fullScreen.isOrContains(layout)) return YES; if ([super ...]) return YES; return occluded(role, appLayoutContainingAppLayout:)

// 0x1c75c3e40   (16.0 0x1c613f658)  - (BOOL)shouldSuppressHighlightEffectForLayoutRole:(long long)r inAppLayout:(id)l { return YES; }

// 0x1c75c3e48  (16.0 0x1c613f660)
- (BOOL)_layoutRoleIsOccluded:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    SBChamoisOverlappingModel *m = [self overlappingModelForAppLayout:appLayout];
    SBDisplayItem *item = [appLayout itemForLayoutRole:role];
    return [m isItemFullyOccluded:item] || [m isItemPartiallyOccluded:item]
        || [m isItemCoveredByFullyOccludedPeekingItem:item];                 // NEW 3rd clause (0x1c797a4ec)
}
// 16.0: _overlappingModelForAppLayout: (own implementation); isItemFullyOccluded || isItemPartiallyOccluded

// 0x1c75c4148   - (BOOL)isLayoutRoleDraggable:(long long)r inAppLayout:(id)l { return NO; }                   // 16.0 same
// 0x1c75c4150  (16.0 0x1c613f9e8)
- (BOOL)isLayoutRoleEligibleForContentDragSpringLoading:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    return [self _isAppLayoutEffectivelyOnStage:appLayout] ? [self _layoutRoleIsOccluded:role inAppLayout:appLayout] : YES;
}   // 16.0 condition was [_fullScreenAppLayout isOrContainsAppLayout:appLayout]
// 0x1c75c41b8  (16.0 0x1c613fa58)
- (BOOL)isLayoutRoleMatchMovedToScene:(SBLayoutRole)role inAppLayout:(SBAppLayout *)appLayout {
    if (role == SBLayoutRoleCenter /* == 4, const at 0x1c7a933b0 */) return YES;
    return [super isLayoutRoleMatchMovedToScene:role inAppLayout:appLayout];
}
```

### 2.5 Switcher chrome constants / home screen / dock / status bar

```objc
// 0x1c75c3f24 isScrollEnabled NO          0x1c75c3f2c shouldScrollViewBlockTouches NO     0x1c75c3f34 switcherHitTestsAsOpaque YES
// 0x1c75c3f3c isWallpaperRequiredForSwitcher YES    0x1c75c3f44 wallpaperStyle 1       0x1c75c3f4c isHomeScreenContentRequired NO
// 0x1c75c3f54 homeScreenAlpha 0.0          0x1c75c3f5c homeScreenBackdropBlurType 2     0x1c75c3f64 homeScreenBackdropBlurProgress 1.0
// (all identical in 16.0)

// 0x1c75c3f74  (16.0 0x1c613f73c)
- (double)homeScreenDimmingAlpha {
    CGRect cb = [self containerViewBounds];
    CGRect stage = [[self overlappingModelForAppLayout:_fullScreenAppLayout] stageArea];       // 0x1c797afcc (NEW)
    double ratio = (stage.size.width * stage.size.height) / (cb.size.width * cb.size.height);
    // literal pool: [0x1c7a91c50] = -0.7 (double), [0x1c7a91c58] = 0.3 (0x3fd3333333333334)
    double d = fmin(fmax(((ratio + -0.7) * 0.5) / 0.3 + 0.0, 0.0), 1.0);
    double strip = [self continuousExposeStripProgress];
    return d + (d * 0.5 - d) * strip;            // = d * (1 - 0.5*strip)
}
// 16.0: identical formula but stage frame came from [displayItemLayoutAttributesCalculator
//   initialStageFrameForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:]
//   and the progress was -_effectiveStripVisibleProgress.

// 0x1c75c4034  (16.0 0x1c613f91c)
- (BOOL)isContainerStatusBarVisible { return ![self appLayoutContainsAnUnoccludedMaximizedDisplayItem:_fullScreenAppLayout]; }

// 0x1c75c405c  (16.0 0x1c613f944)
- (BOOL)shouldConfigureInAppDockHiddenAssertion {
    double bbH   = [[self overlappingModelForAppLayout:_fullScreenAppLayout] boundingBox].size.height;
    double contH = [self containerViewBounds].size.height;
    double dockH = [self floatingDockHeight], topMargin = [self floatingDockViewTopMargin];
    if ([self isSoftwareKeyboardVisible]) return YES;
    if ((contH - bbH) < (dockH + topMargin)) return YES;      // no room under the windows for the floating dock
    return [self prefersDockHidden];                          // tail call
}
// 16.0: YES if isSoftwareKeyboardVisible || _anyDisplayItemsExceedDock (per-role frameForLayoutRole height vs dock) ; else prefersDockHidden.

// 0x1c75c411c  NEW
- (BOOL)wantsDockBehaviorAssertion { return ![self shouldConfigureInAppDockHiddenAssertion]; }
// 0x1c75c4138  (16.0 0x1c613f9d8 returned 0.0)    - (double)dockProgress { return 1.0; }
// 0x1c75c4140  NEW   - (long long)dockUpdateMode { return 3; }
// (16.0 also had -shouldConfigureInAppDockVisibleAssertion 0x1c613f9a0 = !(keyboardVisible || _anyDisplayItemsExceedDock) and
//  -hiddenContentStatusBarPartsForLayoutRole:inAppLayout: 0x1c613f898 = isHomeAffordanceSupported ? [super ...] : 0xa; both removed in 16.2.)

// 0x1c75c43d4  (16.0 0x1c613fb84)
- (BOOL)isHomeAffordanceSupportedForAppLayout:(SBAppLayout *)appLayout {
    return [self _isFullScreenAppLayout:appLayout] && [self isDisplayEmbedded] && [[self homeGrabberSettings] isEnabled];
}
// 0x1c75c4430  (16.0 0x1c613fc10)
- (NSSet *)visibleHomeAffordanceLayoutElements {
    return [self isHomeAffordanceSupportedForAppLayout:_fullScreenAppLayout] ? [NSSet setWithObject:_fullScreenAppLayout] : [NSSet set];
}
```

### 2.6 Event handlers

```objc
// 0x1c75c462c  (16.0 0x1c61402f8)
- (id)handleHoverEvent:(SBHoverSwitcherModifierEvent *)event {
    id response = [super handleHoverEvent:event];
    if ([self _wantsContinuousExposeHoverGestureForDismissingStrip]) {             // strip is (partially) revealed
        double x = [event position].x;                                              // d0 of -position
        SBSwitcherChamoisLayoutAttributes *attrs = [self chamoisLayoutAttributes];
        if (BSFloatGreaterThanFloat(x, [attrs stripWidth]) &&
            BSFloatLessThanFloat(x, [self containerViewBounds].size.width - [attrs stripWidth])) {   // pointer is over the middle of the screen
            id hide = [[SBUpdateContinuousExposeStripsPresentationResponse alloc] initWithPresentationOptions:0 dismissalOptions:1];
            response = SBAppendResponse(hide, response);
            id upd  = [[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:0xc updateMode:3];
            response = SBAppendResponse(upd, response);
        }
    }
    return response;
}
// 16.0: if (unoccludedStripProgress>0) { if (x>stripW && x<W-stripW) || event.phase==2 -> same two responses (options 0xc, mode 3) }
//   then displacement state machine: if _fullScreenAppDisplacementState==2 && ![self _stripFrame contains position] -> state=0,
//   append SBUpdateLayoutSwitcherEventResponse(options:4 updateMode:3).    (hover-exit/phase==2 and displacement logic are gone in 16.2)

// 0x1c75c4780  (16.0 0x1c613fe64)
- (id)handleTapAppLayoutEvent:(SBTapAppLayoutSwitcherModifierEvent *)event {
    id response = [super handleTapAppLayoutEvent:event];
    if (_handlesTapAppLayoutEvents && ![event isHandled]) {                       // both gates NEW in 16.2
        SBAppLayout *tapped = [event appLayout];
        if ([self _isAppLayoutEffectivelyOnStage:tapped]) {
            if ([self _isStripRevealedFromHidden]) {
                // tap on the (dimmed) stage while the strip is revealed: hide strip and re-activate the stage layout
                id hide = [[SBUpdateContinuousExposeStripsPresentationResponse alloc] initWithPresentationOptions:0 dismissalOptions:1];
                response = SBAppendResponse(hide, response);
                SBSwitcherTransitionRequest *req = [SBSwitcherTransitionRequest requestForActivatingAppLayout:_fullScreenAppLayout];
                id perf = [[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:NO];
                response = SBAppendResponse(perf, response);
            } else {
                // tap on a window of the stage layout: bring that window's item to the front
                SBDisplayItem *item = [tapped itemForLayoutRole:[event layoutRole]];
                SBMutableSwitcherTransitionRequest *req = [[SBMutableSwitcherTransitionRequest alloc] init];
                [req setAppLayout:[self appLayoutByBringingItemToFront:item inAppLayout:tapped]];     // 16.0 passed _fullScreenAppLayout as inAppLayout
                [req setActivatingDisplayItem:item];                                                 // NEW  (0x1c740ddf4)
                if ([event source] == 1) [req setSource:0x33];                                       // NEW  (UNSURE: 1 = pointer/keyboard tap; 0x33 transition source id)
                id perf = [[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:NO];
                response = SBAppendResponse(perf, response);
            }
        } else {
            // tap on a strip item
            SBMutableSwitcherTransitionRequest *req = [[SBMutableSwitcherTransitionRequest alloc] init];
            [req setAppLayout:tapped];
            if ([event modifierFlags] & UIKeyModifierShift /* 1<<17 */) [req setEntityInsertionPolicy:1];   // NEW (0x1c740dea8)
            if ([[tapped continuousExposeIdentifier] isEqualToString:[_fullScreenAppLayout continuousExposeIdentifier]])
                [req setSource:0x3f];                                                                // same as 16.0
            id perf = [[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:NO];
            response = SBAppendResponse(perf, response);
        }
        [event handleWithReason:@"Full Screen Continuous Expose"];    // 16.0 reason string: @"Continuous Expose"
    }
    return response;
}

// 0x1c75c4a28   NEW in this class (16.0 had no handleTapAppLayoutHeaderEvent: anywhere; SBSwitcherModifier 0x1c7895b5c is new too)
- (id)handleTapAppLayoutHeaderEvent:(SBTapAppLayoutHeaderSwitcherModifierEvent *)event {      // event class 0x1de235648 (new in 16.2)
    id response = [super handleTapAppLayoutHeaderEvent:event];
    if (_handlesTapAppLayoutHeaderEvents && ![event isHandled]) {
        SBDisplayItem *item = [[event appLayout] itemForLayoutRole:[event layoutRole]];
        id r;
        if ([self displayItemSupportsMultipleWindowsIndicator:item]) {                   // app has >1 window -> App Expose
            SBMutableSwitcherTransitionRequest *req = [[SBMutableSwitcherTransitionRequest alloc] init];
            [req setSource:3];
            [req setBundleIdentifierForAppExpose:[item bundleIdentifier]];
            r = [[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:NO];
        } else {                                                                          // single window -> pulse it
            SBPulseDisplayItemSwitcherModifier *pulse = [[SBPulseDisplayItemSwitcherModifier alloc] initWithDisplayItem:item];  // class NEW in 16.2
            r = [[SBAddModifierSwitcherEventResponse alloc] initWithModifier:pulse level:3];
        }
        response = SBAppendResponse(r, response);
        [event handleWithReason:@"Full Screen Continuous Expose"];
    }
    return response;
}

// 0x1c75c4bc0  (16.0 0x1c6140048 + block 0x1c61401b8)
- (id)handleTapOutsideToDismissEvent:(SBSwitcherModifierEvent *)event {
    id response = [super handleTapOutsideToDismissEvent:event];
    if ([self _isStripRevealedFromHidden]) {
        id hide = [[SBUpdateContinuousExposeStripsPresentationResponse alloc] initWithPresentationOptions:0 dismissalOptions:1];
        response = SBAppendResponse(hide, response);
        SBSwitcherTransitionRequest *req = [SBSwitcherTransitionRequest requestForActivatingAppLayout:_fullScreenAppLayout];
        id perf = [[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:NO];
        response = SBAppendResponse(perf, response);
    }
    return response;
}
// 16.0: if (![event isHandled] && [_fullScreenAppLayout itemForLayoutRole:SBLayoutRoleCenter] != nil) {
//   req = [SBMutableSwitcherTransitionRequest new];
//   req.appLayout = [_fullScreenAppLayout appLayoutWithItemsPassingTest:^BOOL(SBDisplayItem *i){ return [_fullScreenAppLayout layoutRoleForItem:i] != SBLayoutRoleCenter; }];
//   response = SBAppendResponse([[SBPerformTransitionSwitcherEventResponse alloc] initWithTransitionRequest:req gestureInitiated:NO], response); }
//   i.e. 16.0: tap outside a center window dismisses (removes) the center window.  16.2: that is gone from this class (UNSURE where it went).

// 0x1c75c4cc8   NEW  (keyboard window-cycling z-order bookkeeping)
- (id)handleTransitionEvent:(SBTransitionSwitcherModifierEvent *)event {
    id response = [super handleTransitionEvent:event];
    SBAppLayout *from = [event fromAppLayout], *to = [event toAppLayout];
    if ([event phase] == 2) {                                             // UNSURE: SBTransition phase enum; 3 is the animating phase (cf. SBTransitionSwitcherModifier 0x1c746a98c), so 2 = layout-prepare/begin
        if ([[to allItems] count] > 2 && [from isEqual:to]) {             // 3+ windows, transition stays within the same layout
            if (![event isKeyboardShortcutInitiated]) {                   // 0x1c7432e6c (NEW)
                [self _resetKeyboardNavigationZOrder];
            } else {
                NSDictionary *fromMap = [event fromDisplayItemLayoutAttributesMap];
                NSDictionary *toMap   = [event toDisplayItemLayoutAttributesMap];
                // global block 0x1c75c4fa8: keys sorted ascending by -[SBDisplayItemLayoutAttributes lastInteractionTime]
                //   (inner comparator block 0x1c75c5070: [@(tA) compare:@(tB)] with tX = [[map objectForKey:X] lastInteractionTime])
                NSArray *(^sortedKeys)(NSDictionary *) = ^NSArray *(NSDictionary *map) {
                    return [[map allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                        return [@([[map objectForKey:a] lastInteractionTime]) compare:@([[map objectForKey:b] lastInteractionTime])];
                    }];
                };
                SBDisplayItem *lastFrom = [sortedKeys(fromMap) lastObject];   // most recently used window before
                SBDisplayItem *lastTo   = [sortedKeys(toMap) lastObject];     // ... and after
                if (![lastFrom isEqual:lastTo]) {                             // the front window changed
                    NSArray *z = _zOrderedLeafAppLayoutsForKeyboardNavigation;
                    // block 0x1c75c5138: ^BOOL(SBAppLayout *l, NSUInteger i, BOOL *stop){ return [l containsItem:lastFrom]; }
                    NSUInteger idx  = [z indexOfObjectPassingTest:^BOOL(SBAppLayout *l, NSUInteger i, BOOL *stop){ return [l containsItem:lastFrom]; }];
                    NSUInteger next = (idx + 1) % [z count];
                    NSUInteger prev1 = ((NSInteger)idx > 0) ? idx : [z count];       // prev index = prev1 - 1 (wraps)
                    BOOL reset;
                    if ([z[next] containsItem:lastTo])        reset = NO;       // moved forward in the cycle -> keep list
                    else                                      reset = ![z[prev1 - 1] containsItem:lastTo];  // moved backward -> keep, else reset
                    if (reset) [self _resetKeyboardNavigationZOrder];
                }
            }
        }
    }
    return response;
}

// 0x1c75c5144   NEW  (SBPointerCrossedDisplayBoundarySwitcherModifierEvent is a NEW class in 16.2; base handler SBSwitcherModifier 0x1c7895b64 new)
- (id)handlePointerCrossedDisplayBoundaryEvent:(SBPointerCrossedDisplayBoundarySwitcherModifierEvent *)event {
    id response = [super handlePointerCrossedDisplayBoundaryEvent:event];
    if ([event edge] == [self _continuousExposeStripEdge] && BSFloatIsZero([self continuousExposeStripProgress])) {   // strip fully hidden, pointer hit the strip edge
        BOOL initial;
        if ([event direction] == 1)      initial = YES;
        else if ([event direction] == 0) initial = NO;
        else return response;                                             // other direction values: ignore
        id grab = [[SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse alloc] initForInitialPresentation:initial]; // class NEW in 16.2
        response = SBAppendResponse(grab, response);
    }
    return response;
}
```

---------------------------------------------------------------------------------------------------

## 3. 16.0 -> 16.2 diff

Legend: (a) bug fix / behavioural correction, (b) pure refactor (logic moved to `SBStripContinuousExposeSwitcherModifier`
or to a different helper; same observable result), (c) new feature.
"->strip" = the 16.0 logic is now implemented in the strip child and reached through `[super X]`.

### 3.1 The 37 worklist methods

| method | 16.0 (addr) did | 16.2 (addr) does | kind |
|---|---|---|---|
| `dockProgress` | returns 0.0 (0x1c613f9d8) | returns 1.0 (0x1c75c4138); goes with new `dockUpdateMode`=3 and `wantsDockBehaviorAssertion` | (c) new dock model |
| `maskedCornersForIndex:` | constant 0xf (0x1c613ecf8) | stage layout: 0 if it holds an unoccluded maximized item else 0xf; others `[super]` (->strip) (0x1c75c36a4) | (c) square corners for maximized window |
| `shadowOpacityForLayoutRole:atIndex:` | constant 1.0 (0x1c613ed00) | stage 1.0 else `[super]` (->strip) (0x1c75c3750) | (b) |
| `_anyItemExceedsWidthThresholdToHideStrip` | 73 instr: frameForLayoutRole width of each valid item vs `_widthThresholdToHideStrip` (0x1c61414bc) | `!overlappingModel.isContinuousExposeStripVisible` (0x1c75c5244) | (b) computation moved into `SBChamoisOverlappingModel` (but model API `isContinuousExposeStripVisible` is new) |
| `wallpaperGradientAttributesForIndex:` | 171 instr: perspective/3D position math for strip gradient (0x1c613ed18) | stage -> `MakeEmpty()`, else `[super]` (0x1c75c380c) | (b) ->strip |
| `scaleForIndex:` | stage scale * strip-hidden shrink; strip piles scale from cache (0x1c613ddb8) | stage -> `_fullScreenAppLayoutModifier scaleForIndex:`; else super (0x1c75c2f1c) | (b) ->strip; shrink moved to `scaleForLayoutRole:` (see below) |
| `anchorPointForIndex:` | stage -> super; strip -> pile math (0x1c613daf0) | stage -> (0.5,0.5) else super (0x1c75c2e74) | (b) ->strip |
| `topMostLayoutElements` | `[[self _orderedVisibleAppLayouts] array]` (0x1c613fb28) | super with stage layout moved to idx0; plus `continuousExposeStripTongueBackdropCaptureLayoutElement` inserted at idx0 then stage layout re-inserted at idx0 (0x1c75c4284) | (c) strip "tongue" backdrop capture element |
| `frameForIndex:` | contains-all test (one direction pair); shifts stage by `stripWidth*scale*0.5*K` (K from displacement state / unoccluded progress) (0x1c613d7c0) | `_isAppLayoutEffectivelyOnStage:` (adds "N windows sharing N-1 items" clause) -> pure `fullScreenAppLayoutModifier frameForIndex:`; no shift (0x1c75c2da4) | (a)+(b): broader on-stage test; shifting now done per role in `frameForLayoutRole:` |
| `adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:` | non-stage: x = RTL?1:0 (0x1c613e228) | non-stage: super; stage: passthrough (0x1c75c3080) | (b) ->strip |
| `adjustedSpaceAccessoryViewFrame:forAppLayout:` | non-stage: pile-index math using `_leftStripOriginX`, stripWidth (0x1c613e0d0) | non-stage: super (0x1c75c2fcc) | (b) ->strip |
| `scaleForLayoutRole:inAppLayout:` | super * occlusion scale (`stageOcclusionDodgingPeekScale` if fully occluded, `stageOccludedAppScale` if partially) * hover/touch highlight scale (0.98 / 0.9 / 1.1) for pile index 0 (0x1c613e410) | super * `1 + progress*(min((W-stripW-pad)/bbW,1)-1)` for on-stage layouts when strip reveal progress>0 (0x1c75c3360) | (c)/(a): new stage-squeeze scaling based on the overlapping model bounding box (16.0 used `containerBounds.width` of the model, not the bbox); highlight scale ->strip; occlusion scales no longer applied here (UNSURE: see 5) |
| `perspectiveAngleForAppLayout:` | stage 0 else +/-`stripTiltAngle` (0x1c613faac) | stage 0 else super (0x1c75c420c) | (b) ->strip |
| `shouldConfigureInAppDockHiddenAssertion` | keyboard \|\| `_anyDisplayItemsExceedDock` (per-role height scan) \|\| prefersDockHidden (0x1c613f944) | keyboard \|\| (containerH - overlappingModel.bbox.height) < dockH+dockTopMargin \|\| prefersDockHidden (0x1c75c405c) | (b) simplification using model bbox (slightly different geometry: bbox height rather than per-role frame heights) |
| `setHighlightedByHoverAppLayouts:` / `setHighlightedByTouchAppLayouts:` | ivar setters (0x1c6141dd0/dac) | forward to `_stripModifier` (0x1c75c2d04/ce4) | (b) |
| `highlightedByHoverAppLayouts` / `highlightedByTouchAppLayouts` | ivar getters (0x1c6141dc0/d9c) | forward to `_stripModifier` (0x1c75c2cf4/cd4) | (b) |
| `frameForLayoutRole:inAppLayout:withBounds:` | if the item is *partially occluded*: re-anchor origin around the model bbox using `scaleForLayoutRole:` (0x1c613e288) | if on stage and strip reveal progress>0: translate/scale-anchor frame so the (scaled) bbox sits right of the strip (full formula in 2.3) (0x1c75c310c) | (c) stage squeeze when strip revealed; occlusion-dodge re-anchor removed from this class (UNSURE) |
| `shouldUseAnchorPointToPinLayoutRolesToSpace:` | either-contains -> super else YES (0x1c613fd28) | `!onStage` (no super) (0x1c75c4530) | (b) (equal unless super returns YES for the stage layout) |
| `visibleAppLayouts` | `[[self _orderedVisibleAppLayouts] set]` (stage + visible piles) (0x1c613e5c0) | `[[super visibleAppLayouts] setByAddingObject:stage]` (0x1c75c34c0) | (b) ->strip |
| `handleTapOutsideToDismissEvent:` | if not handled and stage layout has a Center-role item: transition removing the Center item (0x1c6140048) | if strip is revealed-from-hidden: hide strip + re-activate stage layout (0x1c75c4bc0) | (c) behaviour changed/replaced (center-window dismissal removed here) |
| `homeScreenDimmingAlpha` | stage frame from `displayItemLayoutAttributesCalculator initialStageFrameForAppLayout:...`, progress `_effectiveStripVisibleProgress` (0x1c613f73c) | stage size from `overlappingModel.stageArea`, progress `continuousExposeStripProgress` (0x1c75c3f74) | (b) same formula/constants (-0.7, 0.5, 0.3) |
| `titleAndIconOpacityForIndex:` | stage 0; strip: 1 only for pile index 0 (0x1c613f1a8) | stage 0 else super (0x1c75c38c0) | (b) ->strip |
| `handleTapAppLayoutEvent:` | stage tap -> bring item to front inside `_fullScreenAppLayout`; strip tap -> transition (source 0x3f if same identifier); reason "Continuous Expose"; no flag/handled gating (0x1c613fe64) | gated by `_handlesTapAppLayoutEvents && !isHandled`; 3 cases: strip-revealed tap on stage, stage tap (activating item, source 0x33 for event.source==1, bring-to-front inside the *tapped* layout), strip tap (Shift -> entityInsertionPolicy 1); reason "Full Screen Continuous Expose" (0x1c75c4780) | (c)+(a): re-entrancy gating, `setActivatingDisplayItem:`, shift-click insertion |
| `isHomeAffordanceSupportedForAppLayout:` | isEqual(stage) && displayEmbedded && unoccludedMaximized && homeGrabber enabled (0x1c613fb84) | `_isFullScreenAppLayout:` (isEqual && unoccludedMaximized) && displayEmbedded && homeGrabber enabled (0x1c75c43d4) | (b) |
| `shouldAllowContentViewTouchesForLayoutRole:inAppLayout:` | stage.isOrContains -> super else NO (0x1c613f514) | NO if !onStage or strip revealed-from-hidden, else super (0x1c75c3cf4) | (a) blocks content touches while strip is revealed from hidden |
| `handleHoverEvent:` | strip dismissal on hover (x between stripW and W-stripW) **or event.phase==2**, plus displacement state-machine (0x1c61402f8) | strip dismissal on hover only when reveal progress>0 and x in the middle; no phase test, no displacement (0x1c75c462c) | (b)/(a): displacement removed; hover-exit dismissal dropped (UNSURE) |
| `cornerRadiiForIndex:` | stage (isOrContains) radius logic + inline strip radii (0x1c613ebf4) | stage radius logic, else super (0x1c75c3594) | (b) ->strip |
| `isLayoutRoleSelectable:inAppLayout:` | !stage.isOrContains -> YES; super; else occluded-of-containing-layout (0x1c613f5a0) | adds `\|\| _isStripRevealedFromHidden` -> YES (0x1c75c3d84) | (a)/(c) |
| `initWithFullScreenAppLayout:` | sets/allocs 2 sets, displacement state 0, layout cache (delegate self), stage child modifier (0x1c613d3cc) | stage child + strip child, tap flags YES, keyboard z-order snapshot (0x1c75c2990) | (b)+(c) |
| `.cxx_destruct` | releases 7 objects (0x1c6141e04) | releases 4 objects (0x1c75c55f4) | (b) |
| `isLayoutRoleEligibleForContentDragSpringLoading:inAppLayout:` | stage.isOrContains ? occluded : YES (0x1c613f9e8) | `_isAppLayoutEffectivelyOnStage` ? occluded : YES (0x1c75c4150) | (a) broader on-stage test |
| `shouldPinLayoutRolesToSpace:` | fullscreen-related -> NO, else super (0x1c613fc78) | on stage -> YES, else super (0x1c75c4498) | (a)/(c) **inverted for the stage layout** (stage windows are now pinned to the space; needed because the stage content is scaled/translated by `frameForLayoutRole`/`scaleForLayoutRole`) |
| `_layoutRoleIsOccluded:inAppLayout:` | fully \|\| partially occluded (0x1c613f660) | + `isItemCoveredByFullyOccludedPeekingItem:` (0x1c75c3e48) | (a) new model API |
| `activeCornersForTouchResizeForLayoutRole:inAppLayout:` | `_enableItemResizeGrabbers...` ? corner logic : 0 (0x1c613f324) | `_shouldEnableItemResizeGrabbers...` ? (NSNotFound guard + same corner logic) : super (0x1c75c3aac) | (a) |
| `touchBehaviorForLayoutRole:inAppLayout:` | same (0x1c613f254) | same (0x1c75c3974) | none (address shift only) |

### 3.2 Methods present only in one build

16.2 only (all in section 2): `descriptionBuilderWithMultilinePrefix:` 0x1c75c2ae8 (d), `continuousExposeStripProgress` 0x1c75c2d14 (c; replaces `_effectiveStripVisibleProgress`),
`_continuousExposeStripRevealProgress` 0x1c75c2d6c (c), `isItemResizingAllowedForLayoutRole:inAppLayout:` 0x1c75c3a44 (c),
`canSelectLeafWithModifierKeysInAppLayout:` 0x1c75c3eec (c keyboard), `activeLeafAppLayoutsReachableByKeyboardShortcut` 0x1c75c3f14 (c keyboard),
`shouldAllowGroupOpacityForAppLayout:` 0x1c75c3f6c (c), `wantsDockBehaviorAssertion` 0x1c75c411c (c), `dockUpdateMode` 0x1c75c4140 (c),
`_isFullScreenAppLayout:` 0x1c75c4378 (b), `spaceAccessoryViewIconHitTestOutsetForAppLayout:` 0x1c75c459c (c),
`isResizeGrabberVisibleForAppLayout:` 0x1c75c45a4 (c), `wantsContinuousExposeHoverGesture` 0x1c75c45ac (c), `_wantsContinuousExposeHoverGestureForDismissingStrip` 0x1c75c4600 (c),
`handleTapAppLayoutHeaderEvent:` 0x1c75c4a28 (c), `handleTransitionEvent:` 0x1c75c4cc8 (c), `handlePointerCrossedDisplayBoundaryEvent:` 0x1c75c5144 (c),
`_shouldEnableItemResizeGrabbersForLayoutRole:inAppLayout:` 0x1c75c5288 (rename of 16.0 `_enableItem...` 0x1c6141bf0, (a)), `_isAppLayoutEffectivelyOnStage:` 0x1c75c5334 (a/b),
`_isStripRevealedFromHidden` 0x1c75c54c4 (c), `_continuousExposeStripEdge` 0x1c75c5520 (c), `_resetKeyboardNavigationZOrder` 0x1c75c5550 (c),
`handlesTapAppLayoutEvents` / `setHandlesTapAppLayoutEvents:` / `handlesTapAppLayoutHeaderEvents` / `setHandlesTapAppLayoutHeaderEvents:` 0x1c75c55b4..55e4 (c).

16.0 only (all dropped / moved): `scrollViewContentOffset` 0x1c613d548, `numberOfRowsInGridSwitcher` 0x1c613d5c4 (forwarded to next), `numberOfVisibleContinuousExposeIdentifiersWhileInApp` 0x1c613d5c8,
`continuousExposeIdentifiers` 0x1c613d6a8, `_orderedVisibleAppLayouts` 0x1c613e60c, `_anyDisplayItemsExceedDock` 0x1c613e864, `opacityForLayoutRole:inAppLayout:atIndex:` 0x1c613ea88 (->strip),
`_wallpaperDimmingForIndex:` 0x1c613f0f4 (->strip), `hiddenContentStatusBarPartsForLayoutRole:inAppLayout:` 0x1c613f898 (removed, falls to default), `shouldConfigureInAppDockVisibleAssertion` 0x1c613f9a0 (removed),
`handleEvent:` 0x1c613fde0 (bumped `_modifierEventGenCount`, invalidated `_leftStripOriginX`), `handleTimerEvent:` 0x1c61401f8 (displacement 1->2 after 0.6 s timer, appended update response options 4 mode 3),
`handleHighlightEvent:` 0x1c6140504 (->strip), `handleSwitcherSettingsChangedEvent:` 0x1c614092c, `_currentLayoutCalculationsValidityToken` 0x1c61409c4, `buildLayoutCalculations` 0x1c6140a48 (->strip `buildLayoutCalculationsForCache:`),
`_appLayoutsForContinuousExposeIdentifierIgnoringStage:` 0x1c6140e84, `_continuousExposeIdentifiersIgnoringStage` 0x1c6140fcc, `_indexOfAppLayoutInAppLayoutsForContinuousExposeIdentifierIgnoringStage:` 0x1c61410ac,
`_leftStripOriginX` 0x1c6141120, `_invalidateLeftStripOriginX` 0x1c61411e0, `_positionForPositionIn3DContainerSpace:layerPosition:layerSize:layerAnchorPoint:layerTransform:containerPerspective:` 0x1c61411f0,
`_overlappingModelForAppLayout:` 0x1c6141330 (now base `SBSwitcherModifier overlappingModelForAppLayout:` 0x1c7652fc4; both builds have that base method), `_effectiveStripVisibleProgress` 0x1c6141464,
`_anyItemOverlapsStrip` 0x1c6141658, `_widthThresholdToHideStrip` 0x1c61416ec, `_itemsValidForOverlapping` 0x1c61417c4, `_isGroupForAppLayoutHighlightedFromTouch:/Hover:` 0x1c6141910/0x1c6141a80,
`_stripFrame` 0x1c6141c94, `appPileBundleIDToBringForwardIfAny` (+setter) 0x1c6141d7c/d8c, `fullScreenAppDisplacementState` (+setter) 0x1c6141de4/df4.
Most of the strip ones live on in `SBStripContinuousExposeSwitcherModifier` (`_stripFrame`, `_positionForPositionIn3DContainerSpace:...`, `_isGroupForAppLayoutHighlightedFrom*`, `_wallpaperDimmingForIndex:`, `_orderedVisibleAppLayoutsIgnoringProgress:`, `buildLayoutCalculationsForCache:` ...).
Genuinely **dropped features** (no equivalent found in the strip modifier's method list): fullscreen "displacement" state/timer (`_fullScreenAppDisplacementState`, 0.6 s timer, `SBTimerEventSwitcherEventResponse`), `appPileBundleIDToBringForwardIfAny`, `_anyDisplayItemsExceedDock`, `hiddenContentStatusBarParts...` override, `shouldConfigureInAppDockVisibleAssertion` override.

### 3.3 Table of every 16.2 method with 16.0 counterpart

| # | selector | 16.2 | 16.0 |
|---|---|---|---|
| 1 | initWithFullScreenAppLayout: | 0x1c75c2990 | 0x1c613d3cc |
| 2 | descriptionBuilderWithMultilinePrefix: | 0x1c75c2ae8 | - |
| 3 | highlightedByTouchAppLayouts | 0x1c75c2cd4 | 0x1c6141d9c |
| 4 | setHighlightedByTouchAppLayouts: | 0x1c75c2ce4 | 0x1c6141dac |
| 5 | highlightedByHoverAppLayouts | 0x1c75c2cf4 | 0x1c6141dc0 |
| 6 | setHighlightedByHoverAppLayouts: | 0x1c75c2d04 | 0x1c6141dd0 |
| 7 | continuousExposeStripProgress | 0x1c75c2d14 | - |
| 8 | _continuousExposeStripRevealProgress | 0x1c75c2d6c | - |
| 9 | frameForIndex: | 0x1c75c2da4 | 0x1c613d7c0 |
| 10 | anchorPointForIndex: | 0x1c75c2e74 | 0x1c613daf0 |
| 11 | scaleForIndex: | 0x1c75c2f1c | 0x1c613ddb8 |
| 12 | adjustedSpaceAccessoryViewFrame:forAppLayout: | 0x1c75c2fcc | 0x1c613e0d0 |
| 13 | adjustedSpaceAccessoryViewAnchorPoint:forAppLayout: | 0x1c75c3080 | 0x1c613e228 |
| 14 | frameForLayoutRole:inAppLayout:withBounds: | 0x1c75c310c | 0x1c613e288 |
| 15 | scaleForLayoutRole:inAppLayout: | 0x1c75c3360 | 0x1c613e410 |
| 16 | visibleAppLayouts | 0x1c75c34c0 | 0x1c613e5c0 |
| 17 | appLayoutsToCacheSnapshots | 0x1c75c353c | 0x1c613ea30 |
| 18 | appLayoutsToCacheFullsizeSnapshots | 0x1c75c3588 | 0x1c613ea7c |
| 19 | cornerRadiiForIndex: | 0x1c75c3594 | 0x1c613ebf4 |
| 20 | maskedCornersForIndex: | 0x1c75c36a4 | 0x1c613ecf8 |
| 21 | shadowOpacityForLayoutRole:atIndex: | 0x1c75c3750 | 0x1c613ed00 |
| 22 | shadowStyleForLayoutRole:inAppLayout: | 0x1c75c37fc | 0x1c613ed08 |
| 23 | shouldUseWallpaperGradientTreatment | 0x1c75c3804 | 0x1c613ed10 |
| 24 | wallpaperGradientAttributesForIndex: | 0x1c75c380c | 0x1c613ed18 |
| 25 | headerStyleForIndex: | 0x1c75c38b4 | 0x1c613f19c |
| 26 | contentPageViewScaleForAppLayout:withScale: | 0x1c75c38bc | 0x1c613f1a4 |
| 27 | titleAndIconOpacityForIndex: | 0x1c75c38c0 | 0x1c613f1a8 |
| 28 | titleOpacityForIndex: | 0x1c75c395c | 0x1c613f23c |
| 29 | dimmingAlphaForLayoutRole:inAppLayout: | 0x1c75c3964 | 0x1c613f244 |
| 30 | backgroundOpacityForIndex: | 0x1c75c396c | 0x1c613f24c |
| 31 | touchBehaviorForLayoutRole:inAppLayout: | 0x1c75c3974 | 0x1c613f254 |
| 32 | isItemResizingAllowedForLayoutRole:inAppLayout: | 0x1c75c3a44 | - |
| 33 | activeCornersForTouchResizeForLayoutRole:inAppLayout: | 0x1c75c3aac | 0x1c613f324 |
| 34 | shouldAllowContentViewTouchesForLayoutRole:inAppLayout: | 0x1c75c3cf4 | 0x1c613f514 |
| 35 | isLayoutRoleSelectable:inAppLayout: | 0x1c75c3d84 | 0x1c613f5a0 |
| 36 | shouldSuppressHighlightEffectForLayoutRole:inAppLayout: | 0x1c75c3e40 | 0x1c613f658 |
| 37 | _layoutRoleIsOccluded:inAppLayout: | 0x1c75c3e48 | 0x1c613f660 |
| 38 | canSelectLeafWithModifierKeysInAppLayout: | 0x1c75c3eec | - |
| 39 | activeLeafAppLayoutsReachableByKeyboardShortcut | 0x1c75c3f14 | - |
| 40-48 | isScrollEnabled, shouldScrollViewBlockTouches, switcherHitTestsAsOpaque, isWallpaperRequiredForSwitcher, wallpaperStyle, isHomeScreenContentRequired, homeScreenAlpha, homeScreenBackdropBlurType, homeScreenBackdropBlurProgress | 0x1c75c3f24 .. 0x1c75c3f64 | 0x1c613f6f4 .. 0x1c613f734 |
| 49 | shouldAllowGroupOpacityForAppLayout: | 0x1c75c3f6c | - |
| 50 | homeScreenDimmingAlpha | 0x1c75c3f74 | 0x1c613f73c |
| 51 | isContainerStatusBarVisible | 0x1c75c4034 | 0x1c613f91c |
| 52 | shouldConfigureInAppDockHiddenAssertion | 0x1c75c405c | 0x1c613f944 |
| 53 | wantsDockBehaviorAssertion | 0x1c75c411c | - |
| 54 | dockProgress | 0x1c75c4138 | 0x1c613f9d8 |
| 55 | dockUpdateMode | 0x1c75c4140 | - |
| 56 | isLayoutRoleDraggable:inAppLayout: | 0x1c75c4148 | 0x1c613f9e0 |
| 57 | isLayoutRoleEligibleForContentDragSpringLoading:inAppLayout: | 0x1c75c4150 | 0x1c613f9e8 |
| 58 | isLayoutRoleMatchMovedToScene:inAppLayout: | 0x1c75c41b8 | 0x1c613fa58 |
| 59 | perspectiveAngleForAppLayout: | 0x1c75c420c | 0x1c613faac |
| 60 | topMostLayoutElements | 0x1c75c4284 | 0x1c613fb28 |
| 61 | shouldAnimateInsertionOrRemovalOfAppLayout:atIndex: | 0x1c75c4368 | 0x1c613fb74 |
| 62 | shouldAccessoryDrawShadowForAppLayout: | 0x1c75c4370 | 0x1c613fb7c |
| 63 | _isFullScreenAppLayout: | 0x1c75c4378 | - |
| 64 | isHomeAffordanceSupportedForAppLayout: | 0x1c75c43d4 | 0x1c613fb84 |
| 65 | visibleHomeAffordanceLayoutElements | 0x1c75c4430 | 0x1c613fc10 |
| 66 | shouldPinLayoutRolesToSpace: | 0x1c75c4498 | 0x1c613fc78 |
| 67 | shouldUseAnchorPointToPinLayoutRolesToSpace: | 0x1c75c4530 | 0x1c613fd28 |
| 68 | wantsSpaceAccessoryViewPointerInteractionsForAppLayout: | 0x1c75c4594 | 0x1c613fdd8 |
| 69 | spaceAccessoryViewIconHitTestOutsetForAppLayout: | 0x1c75c459c | - |
| 70 | isResizeGrabberVisibleForAppLayout: | 0x1c75c45a4 | - |
| 71 | wantsContinuousExposeHoverGesture | 0x1c75c45ac | - |
| 72 | _wantsContinuousExposeHoverGestureForDismissingStrip | 0x1c75c4600 | - |
| 73 | handleHoverEvent: | 0x1c75c462c | 0x1c61402f8 |
| 74 | handleTapAppLayoutEvent: | 0x1c75c4780 | 0x1c613fe64 |
| 75 | handleTapAppLayoutHeaderEvent: | 0x1c75c4a28 | - |
| 76 | handleTapOutsideToDismissEvent: | 0x1c75c4bc0 | 0x1c6140048 |
| 77 | handleTransitionEvent: (+3 blocks 0x1c75c4fa8/5070/5138) | 0x1c75c4cc8 | - |
| 78 | handlePointerCrossedDisplayBoundaryEvent: | 0x1c75c5144 | - |
| 79 | _anyItemExceedsWidthThresholdToHideStrip | 0x1c75c5244 | 0x1c61414bc |
| 80 | _shouldEnableItemResizeGrabbersForLayoutRole:inAppLayout: | 0x1c75c5288 | 0x1c6141bf0 (`_enableItem...`) |
| 81 | _isAppLayoutEffectivelyOnStage: (+block 0x1c75c54ac) | 0x1c75c5334 | - |
| 82 | _isStripRevealedFromHidden | 0x1c75c54c4 | - |
| 83 | _continuousExposeStripEdge | 0x1c75c5520 | - |
| 84 | _resetKeyboardNavigationZOrder | 0x1c75c5550 | - |
| 85-89 | fullScreenAppLayout, handlesTapAppLayoutEvents(+set), handlesTapAppLayoutHeaderEvents(+set) | 0x1c75c55a4..55e4 | 0x1c6141d6c (only `fullScreenAppLayout`) |
| - | .cxx_destruct | 0x1c75c55f4 | 0x1c6141e04 |

### 3.4 Behavioural fixes / changes worth porting (summary)

* Stage layout detection broadened from "contains all items of the other" to `_isAppLayoutEffectivelyOnStage:` (adds "same item count == `maximumNumberOfAppsOnStage` and exactly N-1 shared items") - used by *every* query. (a)
* Stage squeeze when the strip is revealed from its hidden state is now real geometry: scale = 1+progress*(min((W-stripW-pad)/bboxW,1)-1) and a bbox-anchored translation; no more `_fullScreenAppDisplacementState` timer shift. (c)
* Strip-revealed-from-hidden interactions: content touches blocked, everything selectable, tap on stage / tap outside re-activate the stage layout and hide the strip. (a)/(c)
* `shouldPinLayoutRolesToSpace:` flipped to YES for stage layouts. (a)
* Shift-click on a strip item sets `entityInsertionPolicy = 1`; stage tap sets `activatingDisplayItem`; taps respect `isHandled`/`handlesTap*` flags. (c)
* Maximized (unoccluded) stage window has square corners (`maskedCornersForIndex:` = 0). (c)
* Dock: `dockProgress` 0 -> 1.0, `dockUpdateMode` 3, `wantsDockBehaviorAssertion = !shouldConfigureInAppDockHiddenAssertion`. (c)
* `_layoutRoleIsOccluded` also counts "covered by fully-occluded peeking item". (a)
* Resize: grabbers disabled while strip is (partially) revealed from hidden; `isItemResizingAllowed...` / `isResizeGrabberVisible...` overrides; `isChamoisWindowingUIEnabled` requirement dropped. (a)/(c)
* Keyboard cycling z-order bookkeeping (`handleTransitionEvent:`), new `activeLeafAppLayoutsReachableByKeyboardShortcut`, `canSelectLeafWithModifierKeysInAppLayout:`. (c)
* Pointer-crossed-display-boundary -> edge-protect grabber presentation. (c)
* Header tap: multi-window app -> App Expose transition, single window -> pulse modifier. (c)

---------------------------------------------------------------------------------------------------

## 4. Dependencies (non-UIKit / non-Foundation)

"16.0" column = does the same member exist in 16.0 (address) or NEW.  `SBSwitcherModifier` query methods used through `self`
(`appLayouts`, `containerViewBounds`, `chamoisLayoutAttributes`, `switcherSettings`, `isRTLEnabled`, `isDisplayEmbedded`, `homeGrabberSettings`,
`displayCornerRadius`, `floatingDockHeight`, `floatingDockViewTopMargin`, `isSoftwareKeyboardVisible`, `prefersStripHidden`, `prefersDockHidden`,
`appLayoutContainingAppLayout:`, `appLayoutContainsAnUnoccludedMaximizedDisplayItem:`, `appLayoutContainsOnlyResizableApps:`, `appLayoutByBringingItemToFront:inAppLayout:`,
`displayItemSupportsMultipleWindowsIndicator:`) are `SBSwitcherQueryProviding/ContextProviding` protocol methods answered via the modifier chain/root (SBRoutingSwitcherModifier / SBDefaultImplementationsSwitcherModifier);
all of them exist in 16.0 (the 16.0 body of this class calls them).  Query methods that are NEW in 16.2: `continuousExposeStripProgress` (16.0 name: `continuousExposeAppStripUnoccludedProgress`),
`wantsContinuousExposeHoverGesture`, `activeLeafAppLayoutsReachableByKeyboardShortcut` (+ `inactiveAppLayoutsReachableByKeyboardShortcut` in strip), `continuousExposeStripTongueBackdropCaptureLayoutElement`,
`appLayoutOnContinuousExposeStage` (used by the strip; answered by `SBContinuousExposeRootSwitcherModifier` ivar `_effectiveAppLayoutOnStage`), `isContinuousExposeStripVisible` (model), `dockUpdateMode`/`wantsDockBehaviorAssertion` overrides.

| class / function | member | 16.2 addr | 16.0 |
|---|---|---|---|
| SBChainableModifier | `-addChildModifier:` | 0x1c78d8e40 | 0x1c6428fb4 |
| SBChainableModifier | `-addChildModifier:atLevel:key:` (callers' init, not this class) | 0x1c78d8e4c | 0x1c6428fc0 |
| SBChainableModifierEvent | `-isHandled` / `-handleWithReason:` | 0x1c763ebd8 / 0x1c763e8cc | 0x1c61b10e8 / 0x1c61b0ddc |
| SBSwitcherModifier | `-overlappingModelForAppLayout:` | 0x1c7652fc4 | 0x1c61c4450 |
| SBSwitcherModifier | `-handleTapAppLayoutHeaderEvent:` | 0x1c7895b5c | NEW |
| SBSwitcherModifier | `-handlePointerCrossedDisplayBoundaryEvent:` | 0x1c7895b64 | NEW |
| SBSwitcherModifier | `-handleHoverEvent:` / `-handleTapAppLayoutEvent:` / `-handleTapOutsideToDismissEvent:` / `-handleTransitionEvent:` | 0x1c7895b3c / ..5acc / ..5ac4 / ..5a64 | 0x1c63e9318 / ..92a8 / ..92a0 / ..9240 |
| SBFullScreenAppLayoutSwitcherModifier | `-initWithActiveAppLayout:` | 0x1c75cc198 | 0x1c614883c |
| SBStripContinuousExposeSwitcherModifier (class) | `-init`, `-highlightedBy{Touch,Hover}AppLayouts`, `-setHighlightedBy...:` | 0x1c75de0cc, 0x1c75e0728/38/4c/5c | class NEW |
| SBPulseDisplayItemSwitcherModifier (class) | `-initWithDisplayItem:` | 0x1c74c6bd0 | class NEW |
| SBAppLayout | `-itemForLayoutRole:` | 0x1c72a765c | 0x1c5e35204 |
| SBAppLayout | `-containsItem:` / `-isOrContainsAppLayout:` / `-containsAllItemsFromAppLayout:` / `-allItems` / `-continuousExposeIdentifier` | 0x1c7724f84 / 0x1c7725510 / 0x1c7724e70 / 0x1c72a3354 / 0x1c77265c4 | 0x1c628c2bc / 0x1c628c798 / 0x1c628c1a8 / 0x1c5e30ee8 / 0x1c628d514 |
| SBAppLayout | `-zOrderedLeafAppLayouts` | 0x1c7725460 | NEW |
| SBChamoisOverlappingModel | `-boundingBox` / `-centerForItem:` / `-isItemFullyOccluded:` / `-isItemPartiallyOccluded:` | 0x1c797afe4 / 0x1c797a298 / 0x1c797a480 / 0x1c797a414 | 0x1c64bff20 / 0x1c64bfb70 / 0x1c64bfcc0 / 0x1c64bfc54 |
| SBChamoisOverlappingModel | `-isItemCoveredByFullyOccludedPeekingItem:` / `-stageArea` / `-isContinuousExposeStripVisible` | 0x1c797a4ec / 0x1c797afcc / 0x1c797a558 | NEW |
| SBSwitcherChamoisLayoutAttributes | `-stripWidth` / `-screenEdgePadding` / `-stageCornerRaddii` (sic) | 0x1c78c3c44 / 0x1c78c3c34 / 0x1c78c3cc4 | 0x1c6414f38 / 0x1c6414f28 / 0x1c6414fb8 |
| SBSwitcherChamoisSettings | `-pinWindowEdgeForResizeMargin` / `-maximumNumberOfAppsOnStage` ; SBAppSwitcherSettings `-chamoisSettings` | 0x1c78c2ff8 / 0x1c78c3020 ; 0x1c782cf88 | 0x1c6414784 / 0x1c64147ac ; 0x1c6385014 |
| SBSwitcherTransitionRequest | `+requestForActivatingAppLayout:` / `-setAppLayout:` / `-setSource:` / `-setBundleIdentifierForAppExpose:` | 0x1c740d548 / 0x1c740dde0 / 0x1c740de78 / 0x1c740de98 | 0x1c5f95b1c / 0x1c5f961f4 / 0x1c5f96278 / 0x1c5f96298 |
| SBSwitcherTransitionRequest | `-setEntityInsertionPolicy:` / `-setActivatingDisplayItem:` | 0x1c740dea8 / 0x1c740ddf4 | NEW |
| SBMutableSwitcherTransitionRequest | `+alloc/init` (class) | class exists both | exists |
| SBTapAppLayoutSwitcherModifierEvent | `-appLayout` / `-layoutRole` | 0x1c748f398 / 0x1c748f3a8 | 0x1c6014a60 / 0x1c6014a70 |
| SBTapAppLayoutSwitcherModifierEvent | `-source` / `-modifierFlags` | 0x1c748f3c8 / 0x1c748f3b8 | NEW |
| SBTransitionSwitcherModifierEvent | `-fromAppLayout` `-toAppLayout` `-phase` `-fromDisplayItemLayoutAttributesMap` `-toDisplayItemLayoutAttributesMap` | 0x1c7432ab4 / ..2af8 / ..2a74 / ..2e14 / ..2e30 | 0x1c5fba2cc / ..a310 / ..a28c / ..a62c / ..a648 |
| SBTransitionSwitcherModifierEvent | `-isKeyboardShortcutInitiated` | 0x1c7432e6c | NEW |
| SBDisplayItemLayoutAttributes | `-lastInteractionTime` | 0x1c75d0c2c | 0x1c614c804 |
| SBHoverSwitcherModifierEvent | `-position` / `-phase` | 0x1c793ba3c / 0x1c793ba2c | 0x1c6485734 / 0x1c6485724 |
| SBPointerCrossedDisplayBoundarySwitcherModifierEvent (class) | `-edge` / `-direction` | 0x1c7464c50 / 0x1c7464c30 | class NEW |
| SBUpdateContinuousExposeStripsPresentationResponse | `-initWithPresentationOptions:dismissalOptions:` | 0x1c795b844 | 0x1c64a490c |
| SBUpdateLayoutSwitcherEventResponse | `-initWithOptions:updateMode:` | 0x1c7867d88 | 0x1c63bd6f8 |
| SBPerformTransitionSwitcherEventResponse | `-initWithTransitionRequest:gestureInitiated:` | 0x1c7904194 | 0x1c64501e8 |
| SBAddModifierSwitcherEventResponse | `-initWithModifier:level:` | 0x1c747b3c0 | 0x1c6000818 |
| SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse (class) | `-initForInitialPresentation:` | 0x1c741790c | class NEW |
| NSArray category | `-sb_arrayByInsertingOrMovingObject:toIndex:` | 0x1c74dcbd4 | 0x1c605d920 |
| C function | `_SBAppendSwitcherModifierResponse` | 0x1c773a35c | 0x1c62a07b4 |
| C function | `_SBLayoutRoleIsValidForSplitView` | 0x1c7894a30 | 0x1c63e827c |
| C function | `_SBSwitcherGradientWallpaperAttributesMakeEmpty` | 0x1c78951dc | 0x1c63e8a00 |
| SpringBoardUIServices | `_SBRectCornerRadiiForRadius` | 0x1a44befc4 | exists (16.0 call in `cornerRadiiForIndex:`) |
| BaseBoard | `_BSFloatGreaterThanFloat` / `_BSFloatLessThanFloat` / `_BSFloatIsZero` | 0x18e4fb38c / 0x18e4fdc0c / 0x18e4f22d0 | exist |
| data | `_SBLayoutRoleCenter` (= 4) | 0x1c7a933b0 | 0x1c65d0040 |
| BSDescriptionBuilder (description only) | `appendBodySectionWithName:multilinePrefix:block:`, `appendObject:withName:`, `appendBool:withName:`, `-succinctDescriptionBuilder` | - | - |
| CF constants | `@"Full Screen Continuous Expose"` (CFSTR 0x1e18b2b40), assertion `@"SBFullScreenContinuousExposeSwitcherModifier.m"` line 45 | - | 16.0: `@"Continuous Expose"`, line 58 |
| UIKit/CG used | `CGRectGet{MinX,MaxX,MinY,MaxY,Width,Height}`, `[UIApp userInterfaceLayoutDirection]`, `UIKeyModifierShift` (1<<17) | - | - |

Event/response class members the 16.2 class additionally needs vs 16.0: `SBPointerCrossedDisplayBoundarySwitcherModifierEvent`, `SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse`,
`SBPulseDisplayItemSwitcherModifier`, `SBStripContinuousExposeSwitcherModifier`, `-[SBSwitcherModifier handleTapAppLayoutHeaderEvent:]` and `handlePointerCrossedDisplayBoundaryEvent:` dispatch (event routing in `SBChainableModifier handleEvent:` / `SBSwitcherModifier`),
`-[SBChamoisOverlappingModel isContinuousExposeStripVisible/stageArea/isItemCoveredByFullyOccludedPeekingItem:]`, `-[SBTransitionSwitcherModifierEvent isKeyboardShortcutInitiated]`,
`-[SBTapAppLayoutSwitcherModifierEvent source/modifierFlags]`, `-[SBAppLayout zOrderedLeafAppLayouts]`, `-[SBSwitcherTransitionRequest setEntityInsertionPolicy:/setActivatingDisplayItem:]`.

---------------------------------------------------------------------------------------------------

## 5. Wiring (how 16.2 creates / uses the class)

Classref slot: 16.2 0x1db40d590 (16.0: 0x1db4d6f18).  Scan of all SpringBoard `__text` for `adrp #0x1db40d000 / ldr #0x590` yields every user:

| 16.2 caller | address | use |
|---|---|---|
| `-[SBContinuousExposeRootSwitcherModifier floorModifierForTransitionEvent:]` | 0x1c78180e8 (classref loads 0x1c7818180 isKindOf, 0x1c7818374 alloc) | If `[event toEnvironmentMode] == 3` (full-screen CE) and no `toAppExposeBundleID`: reuse the existing floor modifier if it is a `SBFullScreenContinuousExposeSwitcherModifier` whose `fullScreenAppLayout` `isEqual:` `[event toAppLayout]`; otherwise `[[SBFullScreenContinuousExposeSwitcherModifier alloc] initWithFullScreenAppLayout:toAppLayout]` and copy `highlightedByTouchAppLayouts` / `highlightedByHoverAppLayouts` from the previous full-screen floor modifier (if there was one). (16.0 additionally required `appPileBundleIDToBringForwardIfAny` == `ambiguouslyLaunchedBundleIDIfAny` for reuse, and copied `fullScreenAppDisplacementState`.) |
| `-[SBContinuousExposeRootSwitcherModifier floorModifierForGestureEvent:]` | 0x1c78183f0 (0x1c78184b8 isKindOf, 0x1c78184d0 alloc) | NEW. For a Continuous-Expose window-drag gesture (`isContinuousExposeWindowDragEvent`), phase 1: remember current floor modifier; phase 2 (changed): if the drag's `selectedAppLayout` `containsAnyItemFromAppLayout:` `[self proposedAppLayoutForContinuousExposeWindowDrag]` and the floor isn't already a full-screen CE modifier -> `[[... alloc] initWithFullScreenAppLayout:proposed]`; if it does not contain any item, restore the stored initial floor modifier (after `setState:0` on it) unless it is already current; phase 3 (end): drop stored initial floor. |
| `-[SBContinuousExposeRootSwitcherModifier _effectiveEnvironmentMode]` | 0x1c7819cb8 (0x1c7819d10) | `isKindOfClass:` -> environment mode 3 (no floor or HomeScreen CE = 1, AppSwitcher/AppExpose CE = 2, InlineAppExpose = 2, anything else = 1). Also the root's ivar `_effectiveAppLayoutOnStage` (0x68) answers `appLayoutOnContinuousExposeStage` used by the strip child. |
| `-[_SBContinuousExposeWindowDragContentSwitcherModifier initWithGestureID:initialAppLayout:selectedDisplayItem:]` | 0x1c762a3b0 (0x1c762a464) | children in order: `SBContinuousExposeWindowDragSwitcherModifier` (level 0, key nil), then `[[SBFullScreenContinuousExposeSwitcherModifier alloc] initWithFullScreenAppLayout:initialAppLayout]` with `setHandlesTapAppLayoutEvents:NO` + `setHandlesTapAppLayoutHeaderEvents:NO` (level 1), then `SBAppSwitcherContinuousExposeSwitcherModifier` (alloc/init, both handle-flags NO, level 2). |
| `-[_SBContinuousExposePeekContentSwitcherModifier initWithAppLayout:configuration:]` | 0x1c78e5a04 (0x1c78e5a88) | ivar `_fullScreenContinuousExposeAppLayoutModifier`(0x60) = full-screen CE modifier for `appLayout`, both handle-flags NO, `addChildModifier:atLevel:0 key:nil`; then `_appSwitcherModifier` (SBAppSwitcherContinuousExposeSwitcherModifier, flags NO) at level 1. |
| `-[SBContinuousExposePeekTransitionModifier initWithTransitionID:fromAppLayout:toAppLayout:direction:]` | 0x1c76ed9e0 (0x1c76eda94, 0x1c76edac8) | creates `_fromFullScreenContinuousExposeModifier` (0x88) from `fromAppLayout` and, if `direction == 1 && toAppLayout`, `_toFullScreenContinuousExposeModifier` (0x90); not added as children here (used as helper models; UNSURE how queried). |

16.0 callers: only `SBContinuousExposeRootSwitcherModifier floorModifierForTransitionEvent:` (0x1c6370db8; classref loads 0x1c6370e74/0x1c6371188) and `_effectiveEnvironmentMode` (0x1c6372ae0).  The three peek/drag users above are new in 16.2.

Root context: `SBContinuousExposeRootSwitcherModifier` (a `SBFluidSwitcherRootSwitcherModifier` subclass) owns one "floor" modifier (`-floorModifier`); the full-screen CE modifier is the floor for the "app on stage" state.
It is not created by `SBFullScreenSwitcherRootSwitcherModifier` (that one belongs to the non-CE full-screen mode).

### Children added by the 16.2 init (order matters for the chain)

1. `[self addChildModifier:_fullScreenAppLayoutModifier]` - `SBFullScreenAppLayoutSwitcherModifier initWithActiveAppLayout:fullScreenAppLayout` (0x1c75cc198).
2. `[self addChildModifier:_stripModifier]` - `SBStripContinuousExposeSwitcherModifier alloc/init` (0x1c75de0cc).

Both use the level-less `addChildModifier:` (0x1c78d8e40); no gesture delegate, transition delegate or `setDelegate:` is installed (16.0 set `_stripLayoutCache.delegate = self`; the strip child now owns its own `SBSwitcherLayoutCalculationsCache` and conforms to the cache delegate protocol itself).
Because the child chain is consulted by `[super X]`, the ordering means: this class answers first (stage app), then falls to the chain (strip child; `SBFullScreenAppLayoutSwitcherModifier` is also asked for the layouts it knows).

---------------------------------------------------------------------------------------------------

## 6. Open uncertainties

* Numeric enum meanings are taken verbatim from the assembly, names guessed: transition `phase == 2` in `handleTransitionEvent:` (3 is the animation phase in `SBTransitionSwitcherModifier`, so 2 is probably "prepare/begin layout"); tap `source == 1` -> request source `0x33`; strip-tap request source `0x3f` (unchanged from 16.0); header-tap source `3`; `entityInsertionPolicy 1`; response `options 0xc / updateMode 3` and `dismissalOptions 1`; `SBAddModifierSwitcherEventResponse level 3`; `shadowStyle 5`, `wallpaperStyle 1`, `homeScreenBackdropBlurType 2`, `headerStyle 1`, `dockUpdateMode 3`.
* `handleTapAppLayoutHeaderEvent:` event class is `SBTapAppLayoutHeaderSwitcherModifierEvent` (class dump line 111442); it is NEW in 16.2 and must be added with the handler if backported.
* How `[super X]` picks among the two children + strip when both answer (SBChainableModifier child-chain semantics) is described in the strip spec; here it is treated as "ask the chain".
* Features that exist in 16.0's version of this class and have no counterpart in the 16.2 class or strip modifier method list (could have moved to `SBFullScreenAppLayoutSwitcherModifier`, `_SBFullScreenAppFloorSwitcherModifier`, `SBSwitcherModifier` base, or be genuinely removed): tap-outside dismissal of a Center-role window; hover-exit (`phase == 2`) strip dismissal; occlusion-dodge frame/scale compensation (`stageOcclusionDodgingPeekScale`, `stageOccludedAppScale`, partially-occluded re-anchor); `hiddenContentStatusBarPartsForLayoutRole:`; `shouldConfigureInAppDockVisibleAssertion`; `appPileBundleIDToBringForwardIfAny`.
* `peek transition` modifier's use of its from/to full-screen CE modifiers not traced.
* `descriptionBuilderWithMultilinePrefix:` reconstructed from key names only (debug aid).
