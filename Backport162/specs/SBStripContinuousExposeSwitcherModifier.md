# SBStripContinuousExposeSwitcherModifier (iPadOS 16.2, build 20C65)

Class does NOT exist in 16.0 (20A8372). Its logic was inlined in
`SBFullScreenContinuousExposeSwitcherModifier` (16.0); in 16.2 it was split out into this
child modifier. Superclass: `SBSwitcherModifier`. Protocol: `SBSwitcherLayoutCalculationsCacheDelegate`
(16.2 form: `-buildLayoutCalculationsForCache:`; the 16.0 form was `-buildLayoutCalculations`).
Class object 0x1de230be8. All addresses below are 16.2 unslid vm addresses.
Method dump: `sb162_objc.txt` line 102450. Annotated disassembly used for this spec: `sp/strip_annot.txt` (scratchpad).

Conventions used in the code below:
- `UIApp` is the UIKit global (`_UIApp`, GOT 0x1d83f13e8). `[UIApp userInterfaceLayoutDirection] == 1` means RTL.
- "RTL" = `UIUserInterfaceLayoutDirectionRightToLeft` (== 1).
- Ivar names are the real ones; offsets are from the class dump.
- `// UNSURE:` marks anything not fully nailed down.
- All CGRect results are returned in d0-d3 (x,y,w,h); CGPoint in d0-d1; UIRectCornerRadii in d0-d3.

---------------------------------------------------------------------------------------------------

## 1. Purpose and how it fits

Role: it owns the layout of the **Continuous Expose strip** (the vertical column of
off-stage window groups/"piles" docked at the leading screen edge in Stage Manager on iPadOS 16).
It answers the `SBSwitcherQueryProviding` layout queries (`frameForIndex:`, `scaleForIndex:`,
`anchorPointForIndex:`, opacity, corner radii, wallpaper gradient, title/header/shadow style, ...) for every
app layout that is *not* on the stage. The stage app(s) are answered by the creator
(`SBFullScreenContinuousExposeSwitcherModifier` / the home-screen variant) before it calls `[super ...]`.

### Creators (found by scanning all of SpringBoard __text for the class ref at 0x1db40d128)

Only two creators, both `alloc/init` + `addChildModifier:`:

1. `-[SBFullScreenContinuousExposeSwitcherModifier initWithFullScreenAppLayout:]` 0x1c75c2990
   (classref load at 0x1c75c2a58). Stored in that class's ivar `_stripModifier` (+0x60) and added with
   `[self addChildModifier:_stripModifier]` (0x1c7d4af60 = `-[SBChainableModifier addChildModifier:]`).
2. `-[SBHomeScreenContinuousExposeSwitcherModifier init]` 0x1c77f3898 (classref load at 0x1c77f3900),
   ivar `_stripModifier` (+0x60), same `addChildModifier:`.

Both of those are "floor" modifiers created by `-[SBContinuousExposeRootSwitcherModifier floorModifierForTransitionEvent:]`
(0x1c78181xx) / `floorModifierForGestureEvent:` and `_effectiveEnvironmentMode` (0x1c7819cdc/d10),
and by `_SBContinuousExposeWindowDragContentSwitcherModifier` / `SBContinuousExposePeekTransitionModifier`
/ `_SBContinuousExposePeekContentSwitcherModifier`.

### How it is called (SBChainableModifier query chain)

`SBChainableModifier` (0x1dd7ea1e8) implements a query chain (`_nextQueryModifier`, `_queryCache`).
A parent calls `[super frameForIndex:idx]`-style messages; `SBSwitcherModifier`'s dynamic base implementation forwards to the next
modifier in the chain, which here is this child strip modifier. Evidence: FullScreen 16.2
`-frameForIndex:` (0x1c75c2da4) does `if ([self _isAppLayoutEffectivelyOnStage:layout]) return [_fullScreenAppLayoutModifier frameForIndex:idx];
else return [super frameForIndex:idx];` and
`-wallpaperGradientAttributesForIndex:` (0x1c75c380c) returns `SBSwitcherGradientWallpaperAttributesMakeEmpty()` for staged layouts
and `[super ...]` otherwise. So **every strip query is reached via the parent's `[super X]`**.
Inside this class `[super frameForIndex:]`, `[super opacityForLayoutRole:...]`, `[super cornerRadiiForIndex:]`,
`[super appLayoutsForContinuousExposeIdentifier:]`, `[super handleEvent:]`, `[super handleHighlightEvent:]`,
`[super animationAttributesForLayoutElement:]` continue down the chain (further modifiers, finally the
`SBFluidSwitcherViewController` context provider).

Context data (`SBSwitcherContextProviding`, answered by `SBFluidSwitcherViewController` unless overridden by an
intermediate modifier) used by this class and **new in 16.2** (none of these 5 selectors exist anywhere in 16.0):

| selector | 16.2 provider impl | default |
|---|---|---|
| `continuousExposeIdentifiersInStrip` | `-[SBFluidSwitcherViewController continuousExposeIdentifiersInStrip]` 0x1c74373dc (ivar) ; override `SBOverrideContinuousExposeIdentifiersSwitcherModifier` 0x1c798bda8 | stored array |
| `continuousExposeStripProgress` | VC 0x1c7436c2c (bool ivar ? 1.0 : 0.0); overrides: FullScreen 0x1c75c2d14, HomeScreen 0x1c77f3e60, RevealStrips gesture 0x1c7817520, WindowDrag 0x1c760a11c | 0.0/1.0 |
| `requireStripContentsInViewHierarchy` | VC 0x1c7436c4c (returns NO); overrides `SBTransitionSwitcherModifier` 0x1c746a124, `SBGestureSwitcherModifier` 0x1c7828710 | NO |
| `appLayoutOnContinuousExposeStage` | VC 0x1c74388d0 (returns nil) ; overrides `SBContinuousExposeRootSwitcherModifier` 0x1c7819c3c, `SBContinuousExposeWindowDragSwitcherModifier` 0x1c760a10c | nil |
| `continuousExposeIdentifiersGenerationCount` | VC 0x1c74364a4 (ivar) | counter |

### Superclass contract for each overridden method (SBSwitcherModifier query protocol)

`index` is always an index into `[self appLayouts]` (NSArray<SBAppLayout*>), i.e. the switcher's flat list of items.
Unless noted the caller is `SBFluidSwitcherViewController` (via the modifier root) while building/animating
item containers (`_layoutAppLayout:roleMask:`, `_applyStyleToAppLayout:`), and the value is a plain
number/struct consumed immediately; queries are pure (cacheable per event - `SBChainableModifierMethodCache`).

| method | args | returns | caller expectation |
|---|---|---|---|
| `appLayoutsForContinuousExposeIdentifier:` | NSString id | NSArray<SBAppLayout*> | layouts of that group in z-order, first = frontmost |
| `frameForIndex:` | NSUInteger | CGRect | container-space frame of the *unscaled* item (origin = top-left; size from the generic layout). Container applies `scaleForIndex:` about `anchorPointForIndex:` |
| `anchorPointForIndex:` | NSUInteger | CGPoint (unit space) | layer anchor point for scale/rotation |
| `scaleForIndex:` | NSUInteger | double | uniform scale |
| `cornerRadiiForIndex:` / `maskedCornersForIndex:` | NSUInteger | UIRectCornerRadii / UIRectCorner mask | item chrome |
| `opacityForLayoutRole:inAppLayout:atIndex:` | role (SBLayoutRole), layout, index | double alpha | |
| `shadowOpacityForLayoutRole:atIndex:`, `shadowStyleForLayoutRole:inAppLayout:` | | double / enum | |
| `wallpaperGradientAttributesForIndex:` | NSUInteger | `SBSwitcherGradientWallpaperAttributes{leadingAlpha,trailingAlpha}` | drives left/right gradient behind strip items |
| `headerStyleForIndex:`, `titleAndIconOpacityForIndex:`, `titleOpacityForIndex:`, `backgroundOpacityForIndex:`, `dimmingAlphaForLayoutRole:inAppLayout:`, `contentPageViewScaleForAppLayout:withScale:` | | enum/double | |
| `perspectiveAngleForAppLayout:` | layout | double radians (y-axis rotation) | |
| `adjustedSpaceAccessoryView{Frame,AnchorPoint,Scale}:...forAppLayout:` | proposed value + layout | adjusted value | group "space accessory view" (the pile header/icon strip overlay) |
| `visibleAppLayouts` | - | NSSet<SBAppLayout*> | layouts that must have item containers in the view hierarchy |
| `topMostLayoutElements` | - | NSArray | topmost-ordered elements for z ordering (hit-testing) |
| `inactiveAppLayoutsReachableByKeyboardShortcut` | - | NSArray<SBAppLayout*> | keyboard Cmd-` navigation list |
| `isHomeAffordanceSupportedForAppLayout:` | layout | BOOL | |
| `animationAttributesForLayoutElement:` | element | SBSwitcherAnimationAttributes (mutable copy ok) | |
| `handleEvent:` | SBSwitcherModifierEvent | `SBChainableModifierEventResponse` (may be nil; combine with `SBAppendSwitcherModifierResponse`) | |
| `handleHighlightEvent:` | SBHighlightSwitcherModifierEvent | response | |
| `buildLayoutCalculationsForCache:` | SBSwitcherLayoutCalculationsCache | NSDictionary<NSString*, SBSwitcherLayoutCalculations*> | called by the cache on a token miss |
| `_currentLayoutCalculationsValidityToken` | - | SBSwitcherLayoutCalculationsCacheValidityToken | fresh token each call; cache compares with `isEqual:` |

---------------------------------------------------------------------------------------------------

## 2. Ivars (offsets from class dump; slot addresses in `__objc_ivar` at 0x1db416300)

| offset | name | type | meaning |
|---|---|---|---|
| 0x60 | `_requireStripContentsInViewHierarchy` | BOOL | last observed value of `[self requireStripContentsInViewHierarchy]`; edge triggers an update-layout response in `handleEvent:` |
| 0x68 | `_stripLayoutCache` | SBSwitcherLayoutCalculationsCache* | caches per-group frame+scale; `delegate = self` |
| 0x70 | `_modifierEventGenCount` | unsigned long long | incremented on every `handleEvent:`; part of cache validity token |
| 0x78 | `_cached_appStripOriginX` | double | memo for `_appStripOriginX` (0 = invalid) |
| 0x80 | `_cached_appStripUnocclusionProgress` | double | the strip progress for which 0x78 was computed (-1.0 = invalid) |
| 0x88 | `_highlightedByTouchAppLayouts` | NSMutableSet<SBAppLayout*>* | layouts currently touch-highlighted (property, retain) |
| 0x90 | `_highlightedByHoverAppLayouts` | NSMutableSet<SBAppLayout*>* | layouts currently hover-highlighted (property, retain) |

Ivar-slot map seen in code: slot 0x300->0x88, 0x304->0x90, 0x308->0x68, 0x30c->0x70, 0x310->0x60, 0x314->0x78, 0x318->0x80.
Total instance size 0x98.

---------------------------------------------------------------------------------------------------

## 3. Methods (all 46 + 8 blocks)

Notation: `self.chamois` = `[self chamoisLayoutAttributes]` (SBSwitcherChamoisLayoutAttributes*),
`self.settings` = `[[self switcherSettings] chamoisSettings]` (SBSwitcherChamoisSettings*).

```objc
#pragma mark - lifecycle / ivars

// 0x1c75de0cc
- (instancetype)init {
    self = [super init];                                   // objc_msgSendSuper2 sel "init"
    if (self) {
        _highlightedByTouchAppLayouts = [NSMutableSet new];        // objc_alloc_init(NSMutableSet) -> +0x88
        _highlightedByHoverAppLayouts = [NSMutableSet new];        // -> +0x90
        _stripLayoutCache = [SBSwitcherLayoutCalculationsCache new]; // -> +0x68
        [_stripLayoutCache setDelegate:self];                       // 0x1c7da7720 setDelegate:
        // _cached_appStripOriginX / _cached_appStripUnocclusionProgress are left 0.0 (not -1.0)
    }
    return self;
}

// 0x1c75e0728
- (NSMutableSet *)highlightedByTouchAppLayouts { return _highlightedByTouchAppLayouts; }
// 0x1c75e0738
- (void)setHighlightedByTouchAppLayouts:(NSMutableSet *)s { objc_storeStrong(&_highlightedByTouchAppLayouts, s); }
// 0x1c75e074c
- (NSMutableSet *)highlightedByHoverAppLayouts { return _highlightedByHoverAppLayouts; }
// 0x1c75e075c
- (void)setHighlightedByHoverAppLayouts:(NSMutableSet *)s { objc_storeStrong(&_highlightedByHoverAppLayouts, s); }

// 0x1c75e0770
- (void).cxx_destruct {
    objc_storeStrong(&_highlightedByHoverAppLayouts, nil);   // +0x90
    objc_storeStrong(&_highlightedByTouchAppLayouts, nil);   // +0x88
    objc_storeStrong(&_stripLayoutCache, nil);               // +0x68
}

#pragma mark - group / stage helpers

// 0x1c75de180
- (NSArray *)appLayoutsForContinuousExposeIdentifier:(NSString *)identifier {
    NSArray *layouts = [super appLayoutsForContinuousExposeIdentifier:identifier];   // msgSendSuper2 sel @0x18237e000+0xf00
    SBAppLayout *stage = [self appLayoutOnContinuousExposeStage];                    // 0x1c7d4ef00
    if (stage != nil && BSEqualStrings(identifier, [stage continuousExposeIdentifier])) {
        // group identifier is the stage's own group: drop the layouts that are (effectively) on stage
        // block (0x1c75de2a8, sig "B16@?0@\"SBAppLayout\"8", captures self at +0x20):
        //   ^BOOL(SBAppLayout *l){ return ![self _isAppLayoutEffectivelyOnStage:l]; }
        return [layouts bs_filter:^BOOL(SBAppLayout *l){ return ![self _isAppLayoutEffectivelyOnStage:l]; }];
    }
    return layouts;
}

// 0x1c75dff60
- (NSUInteger)_indexInContinuousExposeIdentifierPileForAppLayout:(SBAppLayout *)layout {
    NSString *ident = [layout continuousExposeIdentifier];
    NSArray *pile = [self appLayoutsForContinuousExposeIdentifier:ident];   // NOTE: self-call => stage layouts filtered
    NSUInteger i = [pile indexOfObject:layout];
    return (i == NSNotFound) ? 0 : i;                                        // 0x7fffffffffffffff -> 0
}

// 0x1c75e0584
- (BOOL)_isAppLayoutEffectivelyOnStage:(SBAppLayout *)layout {
    SBAppLayout *stage = [self appLayoutOnContinuousExposeStage];
    BOOL result = NO;
    if (stage) {
        if ([stage containsAllItemsFromAppLayout:layout] || [layout containsAllItemsFromAppLayout:stage]) {
            result = YES;
        } else {
            NSUInteger max = [[[self switcherSettings] chamoisSettings] maximumNumberOfAppsOnStage];   // x21
            if ([[stage allItems] count] == max) {
                NSArray *items = [layout allItems];
                if ([items count] == max) {
                    // block 0x1c75e071c (sig "B16@?0@\"SBDisplayItem\"8", captures stage at +0x20):
                    //   ^BOOL(SBDisplayItem *it){ return [stage containsItem:it]; }   (tail-call -[SBAppLayout containsItem:])
                    NSArray *shared = [items bs_filter:^BOOL(SBDisplayItem *it){ return [stage containsItem:it]; }];
                    result = ([shared count] == max - 1);   // layout differs from stage by exactly one item
                }
            }
        }
    }
    return result;
}

// 0x1c75dfa58
- (id)animationAttributesForLayoutElement:(id)element {
    SBSwitcherAnimationAttributes *a = [[super animationAttributesForLayoutElement:element] mutableCopy]; // super sel @0x182891000+0x800
    [a setUpdateMode:3];
    return a;
}

#pragma mark - strip origin cache

// 0x1c75dffd4
- (double)_appStripOriginX {
    double progress = [self continuousExposeStripProgress];                 // 0x1c7d5a540
    // recompute if never computed (cached origin == 0) or progress changed
    if (_cached_appStripOriginX == 0.0 || !BSFloatEqualToFloat(_cached_appStripUnocclusionProgress, progress)) {
        _cached_appStripUnocclusionProgress = progress;
        SBSwitcherChamoisLayoutAttributes *a = [self chamoisLayoutAttributes];
        double stripWidth = [a stripWidth];
        double x = progress * (stripWidth + [a screenEdgePadding]) - stripWidth;   // LTR: slides from -stripWidth (hidden) to +edgePadding
        if ([UIApp userInterfaceLayoutDirection] == 1 /*RTL*/) {
            x = [self containerViewBounds].size.width - x;                       // d2 of containerViewBounds
        }
        _cached_appStripOriginX = x;
    }
    return _cached_appStripOriginX;
    // quirk: if the computed origin happens to be exactly 0.0 the memo is considered invalid on every call.
}

// 0x1c75e0098
- (void)_invalidateAppStripOriginX {
    _cached_appStripOriginX = 0.0;                 // str xzr
    _cached_appStripUnocclusionProgress = -1.0;    // 0xbff0000000000000
}

// 0x1c75e00b8
- (CGRect)_stripFrame {
    CGRect b = [self containerViewBounds];
    double stripWidth = [[self chamoisLayoutAttributes] stripWidth];
    double h = CGRectGetHeight(b);
    double x = 0.0;
    if ([UIApp userInterfaceLayoutDirection] == 1) x = CGRectGetWidth(b);        // strip on the trailing edge in RTL
    return CGRectMake(x, 0.0, stripWidth, h);
}

#pragma mark - geometry queries

// 0x1c75de2cc
- (CGRect)frameForIndex:(NSUInteger)index {
    CGRect superFrame = [super frameForIndex:index];            // only .size (d2,d3) used; selector @0x182a98000+0
    double w = superFrame.size.width, h = superFrame.size.height;
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    NSString *ident = [layout continuousExposeIdentifier];
    id token = [self _currentLayoutCalculationsValidityToken];
    // fallback block (stack block @0x1c75de464, sig "{CGRect={CGPoint=dd}{CGSize=dd}}8@?0", captures self(+0x20), index(+0x28))
    CGRect cached = [_stripLayoutCache frameForKey:ident validityToken:token fallback:^CGRect{
        // body @0x1c75de464:
        CGRect sf = [super frameForIndex:index];
        double stripWidth = [[self chamoisLayoutAttributes] stripWidth];
        CGRect bounds = [self containerViewBounds];
        BOOL rtl = ([UIApp userInterfaceLayoutDirection] == 1);
        double x = rtl ? (0.5 * sf.size.width + bounds.size.width)           // just off the trailing edge
                       : (0.0 - stripWidth - 0.5 * sf.size.width);           // just off the leading edge
        double y = 0.5 * bounds.size.height;
        return CGRectMake(x, y, sf.size.width, sf.size.height);               // centre-form frame
    }];
    double x = cached.origin.x, y = cached.origin.y;     // cache stores CENTRE-form frames (y = centre y, x unused for strip ids)
    NSArray *stripIds = [self continuousExposeIdentifiersInStrip];
    if ([stripIds containsObject:[layout continuousExposeIdentifier]]) {
        x = [self _appStripOriginX];                      // LIVE strip origin, NOT baked into the cache (16.2 change)
    }
    x -= 0.5 * w;
    y -= 0.5 * h;
    return CGRectMake(x, y, w, h);
    // UNSURE: the cached frame's width/height are NOT used; size always comes from [super frameForIndex:].
}

// 0x1c75de53c
- (CGPoint)anchorPointForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    NSArray *group = [self appLayoutsForContinuousExposeIdentifier:[layout continuousExposeIdentifier]];
    NSUInteger perGroup = [[[self switcherSettings] chamoisSettings] numberOfVisibleItemsPerGroup];
    NSUInteger n = MIN([group count], perGroup);            // csel cc  (16.0 used the raw count; see section 5)
    double ax = 0.0;
    if (n >= 2) {
        SBSwitcherChamoisLayoutAttributes *a = [self chamoisLayoutAttributes];
        double cardScale  = [a stripCardScale];             // d8
        double stackDist  = [a stripStackDistance];         // d9
        id token = [self _currentLayoutCalculationsValidityToken];
        NSString *ident = [layout continuousExposeIdentifier];
        // fallback = GLOBAL block @0x1e18ecc00, invoke 0x1c75de788: logs os_log_error "group frame not in cache"
        // via _SBLogAppSwitcher and returns CGRectMake(0,0,400,400)
        CGRect gf = [_stripLayoutCache frameForKey:ident validityToken:token fallback:kGroupFrameNotInCacheBlock];
        double frameW = gf.size.width;                      // d2 (fmov d10,d2)
        // fallback stack block (invoke 0x1c75de7e0 "d8@?0") returns captured cardScale
        double cachedScale = [_stripLayoutCache scaleForKey:[layout continuousExposeIdentifier]
                                              validityToken:token
                                                   fallback:^double{ return cardScale; }];   // d11
        NSUInteger pileIdx = [group indexOfObject:layout];
        if (pileIdx == NSNotFound) pileIdx = 0;
        double unit = (stackDist / frameW) * (cardScale / cachedScale);
        ax = unit * (double)pileIdx - ((double)n - 1.0) * unit;       // 0 for the last/front card, negative for earlier ones
    }
    if ([UIApp userInterfaceLayoutDirection] == 1) ax = 1.0 - ax;
    return CGPointMake(ax, 0.5);
}

// 0x1c75de7e8
- (double)scaleForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    id token = [self _currentLayoutCalculationsValidityToken];
    // fallback block @0x1c75de9cc (captures self): ^double{ return [[self chamoisLayoutAttributes] stripCardScale]; }
    double scale = [_stripLayoutCache scaleForKey:[layout continuousExposeIdentifier] validityToken:token
                                         fallback:^double{ return [[self chamoisLayoutAttributes] stripCardScale]; }];
    NSArray *group = [self appLayoutsForContinuousExposeIdentifier:[layout continuousExposeIdentifier]];
    if ([group count] >= 2) {
        double itemH = [self frameForIndex:index].size.height;            // d9 = d3
        NSUInteger pileIdx = [group indexOfObject:layout];
        if (pileIdx == NSNotFound) pileIdx = 0;
        // fallback = GLOBAL block @0x1e18ecc20, invoke 0x1c75dea10: returns CGRectZero (GOT _CGRectZero)
        double cachedH = [_stripLayoutCache frameForKey:[layout continuousExposeIdentifier] validityToken:token
                                               fallback:kCGRectZeroBlock].size.height;   // d10 = d3
        double denom = (itemH == 0.0) ? 400.0 : itemH;                    // 0x4079000000000000
        scale = (scale * cachedH) / denom + (double)pileIdx * (-0.01);     // literal 0x1c7a916c0 = -0.01
    }
    scale *= [self _highlightScaleForAppLayout:layout];                    // NEW in 16.2 (was in scaleForLayoutRole in 16.0)
    return scale;
}

// 0x1c75dea24
- (double)_highlightScaleForAppLayout:(SBAppLayout *)layout {
    double r = 1.0;
    if ([self _indexInContinuousExposeIdentifierPileForAppLayout:layout] == 0) {   // only the front card of a group
        BOOL hover = [self _isGroupForAppLayoutHighlightedFromHover:layout];
        BOOL touch = [self _isGroupForAppLayoutHighlightedFromTouch:layout];
        if (hover && touch)      r = 0.98;       // literal 0x1c7a91a38
        else if (!hover || touch) r = touch ? 0.9 : 1.0;   // touch only -> 0.9 (0x1c7a90ee0); neither -> 1.0
        else                     r = 1.1;        // hover only -> 1.1 (0x1c7a90e60)
    }
    return r;
}
// decode: w8 = (!hover)|touch ; d0 = touch ? 0.9 : 1.0 ; r = (w8 != 0) ? d0 : 1.1

// 0x1c75dead4
- (CGRect)adjustedSpaceAccessoryViewFrame:(CGRect)frame forAppLayout:(SBAppLayout *)layout {
    NSArray *stripIds = [self continuousExposeIdentifiersInStrip];
    if ([stripIds indexOfObject:[layout continuousExposeIdentifier]] != NSNotFound) {
        frame.origin.x = [self _appStripOriginX] + (-0.5 * frame.size.width);
    }
    return frame;
}

// 0x1c75deb90
- (CGPoint)adjustedSpaceAccessoryViewAnchorPoint:(CGPoint)point forAppLayout:(SBAppLayout *)layout {
    return CGPointMake(([UIApp userInterfaceLayoutDirection] == 1) ? 1.0 : 0.0, point.y);
}

// 0x1c75debd4
- (double)adjustedSpaceAccessoryViewScale:(double)scale forAppLayout:(SBAppLayout *)layout {
    return scale / [self _highlightScaleForAppLayout:layout];
}

// 0x1c75def2c
- (UIRectCornerRadii)cornerRadiiForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    if ([self _isAppLayoutEffectivelyOnStage:layout]) {
        return [super cornerRadiiForIndex:index];                       // selector @0x182433000+0x780
    }
    double r = [[self chamoisLayoutAttributes] stripCornerRaddii];      // sic
    return SBRectCornerRadiiForRadius(r / [self scaleForIndex:index]);  // counter-scale so on-screen radius == r
}

// 0x1c75df018
- (NSUInteger)maskedCornersForIndex:(NSUInteger)index { return 0xF; }   // all four corners

// 0x1c75df020
- (double)shadowOpacityForLayoutRole:(NSInteger)role atIndex:(NSUInteger)index { return 1.0; }

// 0x1c75df028
- (NSInteger)shadowStyleForLayoutRole:(NSInteger)role inAppLayout:(SBAppLayout *)l { return 5; }   // UNSURE: enum name (SBSwitcherShadowStyle)

// 0x1c75df48c
- (NSInteger)headerStyleForIndex:(NSUInteger)index { return 1; }       // UNSURE: enum name

// 0x1c75df494
- (double)contentPageViewScaleForAppLayout:(SBAppLayout *)l withScale:(double)scale { return scale; }

// 0x1c75df510
- (double)titleOpacityForIndex:(NSUInteger)index { return 0.0; }

// 0x1c75df518
- (double)dimmingAlphaForLayoutRole:(NSInteger)role inAppLayout:(SBAppLayout *)l { return 0.0; }

// 0x1c75df520
- (double)backgroundOpacityForIndex:(NSUInteger)index { return 0.0; }

// 0x1c75df5dc
- (BOOL)isHomeAffordanceSupportedForAppLayout:(SBAppLayout *)l { return NO; }

// 0x1c75df498
- (double)titleAndIconOpacityForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    return ([self _indexInContinuousExposeIdentifierPileForAppLayout:layout] == 0) ? 1.0 : 0.0;   // only front card shows title/icon
}

// 0x1c75df528
- (double)perspectiveAngleForAppLayout:(SBAppLayout *)layout {
    NSInteger dir = [UIApp userInterfaceLayoutDirection];
    double tilt = [[self chamoisLayoutAttributes] stripTiltAngle];
    return (dir == 1) ? -tilt : tilt;
}

// 0x1c75dee60
- (double)opacityForLayoutRole:(NSInteger)role inAppLayout:(SBAppLayout *)layout atIndex:(NSUInteger)index {
    double o = [super opacityForLayoutRole:role inAppLayout:layout atIndex:index];    // selector @0x182394a00
    NSUInteger pileIdx = [self _indexInContinuousExposeIdentifierPileForAppLayout:layout];
    NSUInteger perGroup = [[[self switcherSettings] chamoisSettings] numberOfVisibleItemsPerGroup];
    return (pileIdx > perGroup) ? 0.0 : o;       // csel hi (unsigned >)
    // NOTE: '>' not '>='. _orderedVisibleAppLayouts keeps only `perGroup` items per group,
    // so a card with pileIdx == perGroup is faded in but not in visibleAppLayouts.  UNSURE whether intentional.
}

// 0x1c75df3e4
- (double)_wallpaperDimmingForIndex:(NSUInteger)index {
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    BOOL hover = [self _isGroupForAppLayoutHighlightedFromHover:layout];
    NSUInteger pileIdx = [self _indexInContinuousExposeIdentifierPileForAppLayout:layout];
    if (hover && pileIdx == 0) return 0.0;
    double d = (double)pileIdx * 0.25 + 0.1;       // literal 0x1c7a90d68 = 0.1
    return hover ? d + 0.1 : d;
}

// 0x1c75df030
- (SBSwitcherGradientWallpaperAttributes)wallpaperGradientAttributesForIndex:(NSUInteger)index {
    // returns {leadingAlpha (d0), trailingAlpha (d1)}
    SBAppLayout *layout = [[self appLayouts] objectAtIndex:index];
    double dimming = [self _wallpaperDimmingForIndex:index];                       // d8
    double lead = 0.0, trail = 0.0;                                                // d9, d10
    if (!BSFloatLessThanOrEqualToFloat(dimming, 0.0)) {
        double angle = [self perspectiveAngleForAppLayout:layout];                 // d13
        lead = trail = dimming;
        if (!BSFloatEqualToFloat(angle, 0.0)) {
            SBSwitcherChamoisLayoutAttributes *a = [self chamoisLayoutAttributes];
            double edgePad     = [a screenEdgePadding];                            // [sp+0x38]
            double stripWidth  = [a stripWidth];                                   // [sp+0x30]
            double perspective = [a containerPerspective];                         // [sp+0x28]
            CGRect f   = [self frameForIndex:index];                               // d9..d12
            double sc  = [self scaleForIndex:index];                               // d14
            CGPoint ap = [self anchorPointForIndex:index];                         // d0(x) d1(y)
            CGPoint c  = UIRectGetCenter(f);
            CATransform3D S = CATransform3DMakeScale(sc, sc, 1.0);
            CATransform3D R = CATransform3DMakeRotation(angle, 0.0, 1.0, 0.0);
            CATransform3D T = CATransform3DConcat(S, R);
            // projected x of left and right edge of the card:
            double leftX  = [self _positionForPositionIn3DContainerSpace:CGPointMake(-0.5 * f.size.width, 0.0)
                                                           layerPosition:c layerSize:f.size
                                                        layerAnchorPoint:ap layerTransform:T
                                                    containerPerspective:perspective].x;      // [sp+0x10]
            double rightX = [self _positionForPositionIn3DContainerSpace:CGPointMake( 0.5 * f.size.width, 0.0)
                                                           layerPosition:c layerSize:f.size
                                                        layerAnchorPoint:ap layerTransform:T
                                                    containerPerspective:perspective].x;      // d9
            double extra = 0.25;                                                   // fmov d0,#0.25
            if (!BSFloatIsZero([a minimumDefaultWindowSize].width)) {              // d0 of CGSize
                extra = [self prefersStripHidden] ? 0.25 : 0.6;                    // 0x1c7a90d98 = 0.6
            }
            double maxDim = dimming + extra;                                       // d11
            double dLeft, dRight, range = maxDim - dimming, span = stripWidth - edgePad;
            if ([UIApp userInterfaceLayoutDirection] == 1) {
                double maxX = CGRectGetMaxX([self containerViewBounds]);
                dLeft  = range * ((maxX - leftX)  - edgePad) / span;
                dRight = range * ((maxX - rightX) - edgePad) / span;
            } else {
                dLeft  = range * (leftX  - edgePad) / span;
                dRight = range * (rightX - edgePad) / span;
            }
            trail = MAX(dimming, MIN(dimming + dLeft,  maxDim));                   // d10  (returned as x1)
            lead  = MAX(dimming, MIN(dimming + dRight, maxDim));                   // d9   (returned as x0)
        }
    }
    (void)SBSwitcherGradientWallpaperAttributesMakeEmpty();                        // result discarded; call is dead (0x1c75df3ac)
    return (SBSwitcherGradientWallpaperAttributes){ lead, trail };
    // UNSURE: which of leftX/rightX feeds lead vs trail was derived from register flow (d9->d0, d10->d1): x0 comes from the
    // SECOND position call (+0.5*w), x1 from the first (-0.5*w). The RTL branch uses CGRectGetMaxX(containerViewBounds) twice (once per edge).
}

#pragma mark - visible / ordering

// 0x1c75dec4c
- (NSOrderedSet *)_orderedVisibleAppLayoutsIgnoringProgress:(BOOL)ignoringProgress {
    NSMutableOrderedSet *result = [NSMutableOrderedSet new];
    if (BSFloatGreaterThanFloat([self continuousExposeStripProgress], 0.0)
        || [self requireStripContentsInViewHierarchy]
        || ignoringProgress) {
        NSArray *ids = [self continuousExposeIdentifiersInStrip];
        NSUInteger perGroup = [[[self switcherSettings] chamoisSettings] numberOfVisibleItemsPerGroup];
        NSCountedSet *seen = [NSCountedSet new];
        for (NSUInteger i = 0; i < [ids count]; i++) {
            NSString *ident = ids[i];
            for (SBAppLayout *l in [self appLayoutsForContinuousExposeIdentifier:ident]) {   // stage layouts already filtered out
                [seen addObject:ident];
                if ([seen countForObject:ident] <= perGroup) [result addObject:l];           // first `perGroup` layouts of each group
            }
        }
    }
    return result;     // returned as the mutable set itself
}

// 0x1c75debfc
- (NSSet *)visibleAppLayouts {
    return [[self _orderedVisibleAppLayoutsIgnoringProgress:NO] set];
}

// 0x1c75df58c
- (NSArray *)topMostLayoutElements {
    return [[self _orderedVisibleAppLayoutsIgnoringProgress:NO] array];
}

// 0x1c75df5e4
- (NSArray *)inactiveAppLayoutsReachableByKeyboardShortcut {
    return [[self _orderedVisibleAppLayoutsIgnoringProgress:YES] array];     // ignores strip progress (strip may be hidden)
}

#pragma mark - 3D helper

// 0x1c75e0174
- (CGPoint)_positionForPositionIn3DContainerSpace:(CGPoint)space
                                    layerPosition:(CGPoint)position
                                        layerSize:(CGSize)size
                                 layerAnchorPoint:(CGPoint)anchor
                                   layerTransform:(CATransform3D)transform       // passed by pointer in x2
                             containerPerspective:(double)perspective {           // 9th arg on stack ([fp+0x10])
    CGRect bounds = [self containerViewBounds];
    double ptX = space.x + size.width  * (0.5 - anchor.x);                       // d0
    double ptY = space.y + size.height * (0.5 - anchor.y);                       // d1
    // QuartzCore private; returns homogeneous (x,y,z,w) in d0..d3
    CAPoint4 p = CAPointApplyTransform(&transform, ptX, ptY, 0.0, 1.0);          // UNSURE: exact prototype
    double halfW = bounds.size.width * 0.5, halfH = bounds.size.height * 0.5;    // d8, d9
    double x1 = p.x + (position.x - halfW);
    double y1 = p.y + (position.y - halfH);
    CATransform3D P = CATransform3DIdentity;                                     // GOT 0x1d83ef7b8
    P.m34 = -1.0 / perspective;                                                  // offset 0x58 in struct
    CAPoint4 q = CAPointApplyTransform(&P, x1, y1, p.z /*d2 passed through*/, 1.0 /*UNSURE d3*/ );
    return CGPointMake(halfW + q.x / q.w, halfH + q.y / q.w);
}

#pragma mark - highlight sets

// 0x1c75e02b4
- (BOOL)_isGroupForAppLayoutHighlightedFromTouch:(SBAppLayout *)layout {
    if ([self _isAppLayoutEffectivelyOnStage:layout]) return NO;
    NSString *ident = [layout continuousExposeIdentifier];
    for (SBAppLayout *l in _highlightedByTouchAppLayouts) {            // fast enumeration of the live set
        if ([[l continuousExposeIdentifier] isEqualToString:ident]) return YES;
    }
    return NO;
}

// 0x1c75e041c  (identical, iterates _highlightedByHoverAppLayouts, ivar slot 0x304)
- (BOOL)_isGroupForAppLayoutHighlightedFromHover:(SBAppLayout *)layout {
    if ([self _isAppLayoutEffectivelyOnStage:layout]) return NO;
    NSString *ident = [layout continuousExposeIdentifier];
    for (SBAppLayout *l in _highlightedByHoverAppLayouts) {
        if ([[l continuousExposeIdentifier] isEqualToString:ident]) return YES;
    }
    return NO;
}

#pragma mark - events

// 0x1c75df634
- (id)handleEvent:(id)event {
    [self _invalidateAppStripOriginX];
    _modifierEventGenCount++;
    BOOL require = [self requireStripContentsInViewHierarchy];
    id response = nil;
    if (_requireStripContentsInViewHierarchy != require) {
        _requireStripContentsInViewHierarchy = require;
        // options:2 updateMode:0
        response = SBAppendSwitcherModifierResponse([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:2 updateMode:0], nil);
    }
    id superResponse = [super handleEvent:event];                       // selector @0x183095000+0x880
    return SBAppendSwitcherModifierResponse(response, superResponse);
}

// 0x1c75df73c
- (id)handleHighlightEvent:(SBHighlightSwitcherModifierEvent *)event {
    id response = [super handleHighlightEvent:event];                   // selector @0x184b77000+0x58e
    SBAppLayout *layout = [event appLayout];
    if (![event isHandled] && layout != nil) {
        NSUInteger phase = [event phase];
        BOOL onStage = [self _isAppLayoutEffectivelyOnStage:layout];
        BOOL isHover = [event isHoverEvent];
        BOOL phaseIsEnd = (phase - 1) < 2;                              // phase == 1 || phase == 2   UNSURE: enum names (began=0 ?, ended/cancelled=1,2 ?)
        if (!onStage && !phaseIsEnd) {
            // begin: add to hover or touch set
            [(isHover ? _highlightedByHoverAppLayouts : _highlightedByTouchAppLayouts) addObject:layout];
        } else {
            NSMutableSet *set = (isHover && phaseIsEnd) ? _highlightedByHoverAppLayouts : _highlightedByTouchAppLayouts;
            if ([set containsObject:layout]) {
                [set removeObject:layout];
            } else {
                // remove any member that overlaps the event's layout
                for (SBAppLayout *m in [set copy]) {
                    if ([m containsAnyItemFromAppLayout:layout]) [set removeObject:m];
                }
            }
            // NOTE: a hover event that is on-stage or whose phase is not 1/2 falls into the TOUCH set here (as compiled).
        }
        SBUpdateLayoutSwitcherEventResponse *upd = [[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:0xc updateMode:0];
        response = SBAppendSwitcherModifierResponse(upd, response);
        [event handleWithReason:@"Full Screen Continuous Expose"];      // string literal @0x1e18b2b40 (copied from FullScreen class)
    }
    return response;
}

#pragma mark - layout-calculations cache (SBSwitcherLayoutCalculationsCacheDelegate)

// 0x1c75dfacc
- (id)_currentLayoutCalculationsValidityToken {
    SBSwitcherLayoutCalculationsCacheValidityToken *t = [SBSwitcherLayoutCalculationsCacheValidityToken alloc];
    return [t initWithAppLayoutsGenCount:[self appLayoutsGenerationCount]
              continuousExposeIdentifiersGenCount:[self continuousExposeIdentifiersGenerationCount]   // NEW in 16.2
                     switcherInterfaceOrientation:[self switcherInterfaceOrientation]
                              containerViewBounds:[self containerViewBounds]
                            modifierEventGenCount:_modifierEventGenCount];
}

// 0x1c75dfb68
- (NSDictionary *)buildLayoutCalculationsForCache:(SBSwitcherLayoutCalculationsCache *)cache {
    NSArray *ids = [self continuousExposeIdentifiersInStrip];
    NSUInteger n = [ids count];
    SBSwitcherChamoisLayoutAttributes *a = [self chamoisLayoutAttributes];
    double stripWidth   = [a stripWidth];
    double stackDist    = [a stripStackDistance];      // d11
    double cardScale    = [a stripCardScale];          // d8
    double itemSpacing  = [a stripInterItemSpacing];   // d9
    CGRect bounds       = [self containerViewBounds];  // x,y,w,h = d12,d10,d14,d15
    NSUInteger perGroup = [[[self switcherSettings] chamoisSettings] numberOfVisibleItemsPerGroup];   // x20
    double availH = bounds.size.height;
    if (![self prefersDockHidden]) availH -= [self floatingDockHeight];            // [sp+0x18]
    // heap block (retainBlock) @0x1c75dff38, sig "d16@?0Q8"; captures bounds(+0x20..+0x38), stripWidth(+0x40), stackDist(+0x48), perGroup(+0x50)
    double (^widthLimitForCount)(NSUInteger) = ^double(NSUInteger count) {
        return bounds.size.width - 2.0 * stripWidth + stackDist * (double)(perGroup - count);
    };
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithCapacity:n];
    double y = 0.0;                                                                 // d14
    for (NSUInteger i = 0; i < n; i++) {
        NSString *ident = ids[i];
        NSArray *group = [self appLayoutsForContinuousExposeIdentifier:ident];
        NSUInteger cnt = [group count];                                            // x19
        SBAppLayout *first = [group firstObject];
        SBChamoisOverlappingModel *m = [self overlappingModelForAppLayout:first];  // 0x1c7652fc4
        CGRect bb = [m boundingBox];                                               // d10 = w, d11 = h used
        double limit = widthLimitForCount(cnt);
        double scale = cardScale;
        if (bb.size.width > limit) scale = cardScale * (limit / bb.size.width);    // fcmp d10,d0 ; b.le
        double scaledH = bb.size.height * scale;                                   // d15
        SBSwitcherLayoutCalculations *calc = [SBSwitcherLayoutCalculations new];
        [calc setScale:scale];
        [calc setFrame:CGRectMake(0.0, y + scaledH * 0.5, bb.size.width, bb.size.height)];   // centre-form: y = centre; x = 0 (live origin applied in frameForIndex:)
        [dict setObject:calc forKey:ident];
        y = (i + 1 < n) ? y + scaledH + itemSpacing : y + scaledH;                 // fcsel cc
    }
    // vertically centre the stack inside the dock-adjusted height
    double yOff = (availH + 0.0) * 0.5 - (y * 0.5);                               // d8 = (availH+0)*0.5 - d10, d10 = y*0.5
    for (NSString *k in dict) {                                                    // (dict is retained for the loop; only the values are mutated)
        SBSwitcherLayoutCalculations *c = [dict objectForKey:k];
        CGRect f = [c frame];
        f.origin.y += yOff;
        [c setFrame:f];                                                            // x,w,h unchanged
    }
    return dict;
    // UNSURE: widthLimitForCount semantic: arithmetic is exact (width - 2*stripWidth + stackDist*(perGroup-count)); the stored
    // value is only used as the "too wide" limit for the card scale shrink.  (The 16.0 inline version used the identical block.)
}

#pragma mark - blocks (summary)

// 0x1c75de2a8  ___83-...appLayoutsForContinuousExposeIdentifier:_block_invoke : return ![block->self _isAppLayoutEffectivelyOnStage:arg];
// 0x1c75de464  ___57-...frameForIndex:_block_invoke : fallback frame (see frameForIndex:)
// 0x1c75de788  ___63-...anchorPointForIndex:_block_invoke : (global) os_log_error(_SBLogAppSwitcher, "group frame not in cache"); return {0,0,400,400}
//                 (cold part 0x1c7a0373c does the __os_log_error_impl; only if os_log_type_enabled(log, OS_LOG_TYPE_ERROR))
// 0x1c75de7e0  ___63-...anchorPointForIndex:_block_invoke.7 : return block->capturedDouble (+0x20)
// 0x1c75de9cc  ___57-...scaleForIndex:_block_invoke : return [[block->self chamoisLayoutAttributes] stripCardScale];
// 0x1c75dea10  ___57-...scaleForIndex:_block_invoke_2 : (global) return CGRectZero
// 0x1c75dff38  ___75-...buildLayoutCalculationsForCache:_block_invoke : see widthLimitForCount
// 0x1c75e071c  ___74-...:_isAppLayoutEffectivelyOnStage:_block_invoke : return [block->stage containsItem:arg];
```

Notes:
- `numberOfVisibleItemsPerGroup` / `maximumNumberOfAppsOnStage` are on `SBSwitcherChamoisSettings` (0x1c78c2ee8 / 0x1c78c3020); `[[self switcherSettings] chamoisSettings]` is `SBAppSwitcherSettings -chamoisSettings`.
- `SBAppendSwitcherModifierResponse(a, b)` consumes both and returns the combined response (nil-tolerant on either side).
- Block literals are stack blocks with signature strings in `__TEXT.__objc_methtype`; global blocks (0x1e18ecc00, 0x1e18ecc20) are used for the capture-less fallbacks.

---------------------------------------------------------------------------------------------------

## 4. Dependencies (non-public-UIKit/Foundation)

Legend: "16.0" = exists in 20A8372 (same selector/function name); "changed" refers to `WORKLIST.md` (body-diffed methods).

### Classes created / messaged

| entity | 16.2 addr | in 16.0? | body changed? |
|---|---|---|---|
| `SBSwitcherLayoutCalculationsCache` -init | 0x1c779ebf8 | yes 0x1c63012cc | ivar layout changed (16.2: dict 0x8, delegate 0x10, token 0x18; 16.0: dict 0x8, token 0x10, delegate 0x18). Not in WORKLIST but **API changed** |
| `-[SBSwitcherLayoutCalculationsCache setDelegate:]` | 0x1c779efd0 | yes 0x1c63016a0 | trivial |
| `-frameForKey:validityToken:fallback:` | 0x1c779ec58 | yes 0x1c630132c | **semantics changed**: 16.2 calls `rebuildIfNecessaryForValidityToken:` (new, 0x1c779eeb8), looks up `_cachedLayoutCalculationsByKey[key].frame`; on a miss it `os_log`s (type 1 = INFO, format arg = key) and invokes the fallback block |
| `-scaleForKey:validityToken:fallback:` | 0x1c779ed98 | yes 0x1c630146c | same change |
| `-rebuildIfNecessaryForValidityToken:` | 0x1c779eeb8 | **no** (16.0: `_updateLayoutCalculationsIfNecessaryForValidityToken:` 0x1c630158c) | NEW. `if (![_validityToken isEqual:token]) { _cachedLayoutCalculationsByKey = [delegate buildLayoutCalculationsForCache:self]; _validityToken = token; }` ; asserts "Must have set delegate by now" (SBSwitcherLayoutCalculationsCache.m line 54) |
| `-validityToken` | 0x1c779efdc | no | new getter |
| `SBSwitcherLayoutCalculationsCacheDelegate` protocol | 0x1db427c48 | yes, but selector `buildLayoutCalculations` (no arg) + `_currentLayoutCalculationsValidityToken` | **changed signature**: `buildLayoutCalculationsForCache:` |
| `SBSwitcherLayoutCalculationsCacheValidityToken` -initWithAppLayoutsGenCount:continuousExposeIdentifiersGenCount:switcherInterfaceOrientation:containerViewBounds:modifierEventGenCount: | 0x1c779f184 | **no** (16.0: 4-arg form 0x1c630184c without ContinuousExposeIdentifiers gen) | NEW field `_continuousExposeIdentifiersGenCount` (+0x10), ivar layout shifted; `isEqual:` 0x1c779f210 (16.0 0x1c63018d4) must also compare it |
| `SBSwitcherLayoutCalculations` (-frame/-setFrame:/-scale/-setScale:) | 0x1c779f15c/f168/f174/f17c | yes | unchanged layout |
| `SBUpdateLayoutSwitcherEventResponse -initWithOptions:updateMode:` | 0x1c7867d88 | yes 0x1c63bd6f8 | no |
| `SBSwitcherAnimationAttributes -setUpdateMode:` | 0x1c795537c | yes 0x1c649e48c | no |
| `SBChamoisOverlappingModel -boundingBox` | 0x1c797afe4 | yes 0x1c64bff20 | no (class gained 27 methods, `initWithItems:...` signature changed - WORKLIST) |
| `SBSwitcherModifier -overlappingModelForAppLayout:` | 0x1c7652fc4 | yes 0x1c61c4450 (16.0 FullScreen also had private `_overlappingModelForAppLayout:` 0x1c6141330) | not listed |
| `SBSwitcherChamoisLayoutAttributes` stripWidth 0x1c78c3c44, stripCardScale 0x1c78c3ca4, stripStackDistance 0x1c78c3c94, stripInterItemSpacing 0x1c78c3c64, stripCornerRaddii 0x1c78c3cb4, stripTiltAngle 0x1c78c3c74, screenEdgePadding 0x1c78c3c34, containerPerspective 0x1c78c3c24, minimumDefaultWindowSize 0x1c78c3be4 | listed | yes (16.0 0x1c6414f38 ...) | accessors unchanged; class has `isEqual:`/`copyWithZone:` changed + 31 new methods (CLASS_DELTA). The *values* come from `SBSwitcherChamoisSettings -layoutAttributesFor...` which is heavily changed (WORKLIST 0.43) |
| `SBSwitcherChamoisSettings` numberOfVisibleItemsPerGroup 0x1c78c2ee8, maximumNumberOfAppsOnStage 0x1c78c3020; `SBAppSwitcherSettings -chamoisSettings` 0x1c782cf88 | | yes (0x1c6414674, 0x1c64147ac, 0x1c6385014) | accessors unchanged |
| `SBAppLayout` -continuousExposeIdentifier 0x1c77265c4 | | yes 0x1c628d514 | **changed (WORKLIST sim 0.86, block 0.64)** |
| `SBAppLayout` -allItems 0x1c72a3354, -containsAllItemsFromAppLayout: 0x1c7724e70, -containsAnyItemFromAppLayout: 0x1c7724e00, -containsItem: 0x1c7724f84 | | yes (0x1c5e30ee8, 0x1c628c1a8, 0x1c628c138, 0x1c628c2bc) | no |
| `SBHighlightSwitcherModifierEvent` -appLayout/-phase/-isHoverEvent 0x1c7420d08 | | yes (0x1c5fa7f24) | no |
| `SBChainableModifierEvent` -isHandled 0x1c763ebd8, -handleWithReason: 0x1c763e8cc | | yes (0x1c61b10e8, 0x1c61b0ddc) | no |
| `SBChainableModifier -addChildModifier:` 0x1c78d8e40 (used by creators) | | yes | not listed |

### Context-provider selectors (SBSwitcherContextProviding)

Present in both builds (provided by `SBFluidSwitcherViewController`): `appLayouts` (16.2 0x1c72a33a8), `appLayoutsForContinuousExposeIdentifier:` (0x1c74373ec),
`chamoisLayoutAttributes` (0x1c7437110, body changed per WORKLIST 0.91), `switcherSettings` (0x1c7437084), `containerViewBounds` (0x1c74367c4),
`prefersStripHidden` (0x1c743794c, WORKLIST changed 0.67), `prefersDockHidden` (0x1c74379ac, WORKLIST changed 0.25),
`floatingDockHeight` (0x1c7436a08), `appLayoutsGenerationCount` (0x1c7436478), `switcherInterfaceOrientation` (0x1c72a563c).

**New in 16.2 only (must be added to the 16.0 context provider / protocol):**
`continuousExposeIdentifiersInStrip`, `continuousExposeStripProgress`, `requireStripContentsInViewHierarchy`,
`appLayoutOnContinuousExposeStage`, `continuousExposeIdentifiersGenerationCount` (addresses in section 1).
Also new and used by the strip's parents: `_continuousExposeStripRevealProgress` etc.

### C functions

| function | 16.2 | 16.0 | note |
|---|---|---|---|
| `SBAppendSwitcherModifierResponse` | 0x1c773a35c | 0x1c62a07b4 | same |
| `SBSwitcherGradientWallpaperAttributesMakeEmpty` | 0x1c78951dc (returns {0,0}) | 0x1c63e8a00 | same |
| `SBRectCornerRadiiForRadius` | SpringBoardUIServices export | same | |
| `SBLogAppSwitcher` | 0x1c783db94 | 0x1c6394750 | same |
| `CAPointApplyTransform`, `CATransform3DMakeScale/MakeRotation/Concat` | QuartzCore | same | private/semi-private |
| `UIRectGetCenter`, `BSEqualStrings`, `BSFloat*` | UIKit / BaseBoard | same | |

---------------------------------------------------------------------------------------------------

## 5. 16.0 equivalent and behavioural differences (the bug-fix candidates)

16.0 class: `SBFullScreenContinuousExposeSwitcherModifier` (class dump `sb160n_objc.txt` line 53588). 16.0 ivars used:
`_fullScreenAppLayout` (0x90), `_stripLayoutCache` (0x80), `_modifierEventGenCount` (0x88), `_cached_leftStripOriginX` (0x78),
`_highlightedByTouch/HoverAppLayouts` (0xa0/0xa8), `_fullScreenAppDisplacementState` (0xb0),
`_expectedTimerEventReason`/`_timerEventGenerationCount` (0x70/0x68).

| 16.2 strip method | 16.0 method (addr) | difference |
|---|---|---|
| `init` | `initWithFullScreenAppLayout:` 0x1c613d3cc | cache/sets now created in the child; no fullScreenAppLayout; 16.2 does not initialise `_cached_appStripUnocclusionProgress` to -1 (0) |
| `appLayoutsForContinuousExposeIdentifier:` | `_appLayoutsForContinuousExposeIdentifierIgnoringStage:` 0x1c6140e84 (+ block 0x1c6140f9c) | 16.0 removed layouts that `containsAnyItemFromAppLayout:_fullScreenAppLayout`; 16.2 removes only layouts `_isAppLayoutEffectivelyOnStage:` (stage-aware, handles stage with `maximumNumberOfAppsOnStage` items) and only for the stage's own group id |
| `_indexInContinuousExposeIdentifierPileForAppLayout:` | `_indexOfAppLayoutInAppLayoutsForContinuousExposeIdentifierIgnoringStage:` 0x1c61410ac | same logic; 16.2 uses the overridden `appLayoutsForContinuousExposeIdentifier:` |
| group ids source | `_continuousExposeIdentifiersIgnoringStage` 0x1c6140fcc (removed full-screen group id if it had no other layouts) + `continuousExposeIdentifiers` 0x1c613d6a8 + `numberOfVisibleContinuousExposeIdentifiersWhileInApp` 0x1c613d5c8 | 16.2: `[self continuousExposeIdentifiersInStrip]` supplied by the VC/overrides; **no cap on number of groups** |
| `frameForIndex:` | 0x1c613d7c0 | 16.0: cache frame's x was baked in (`_leftStripOriginX` 0x1c6141120 inside `buildLayoutCalculations`); 16.2 puts x = live `_appStripOriginX` at query time (cache is progress-independent) |
| `anchorPointForIndex:` | 0x1c613daf0 | 16.0 used full group count (`_appLayoutsForContinuousExposeIdentifierIgnoringStage:`) with no cap; 16.2 `MIN(count, numberOfVisibleItemsPerGroup)` |
| `scaleForIndex:` | 0x1c613ddb8 | same formula (-0.01 per stacked card, 400.0 guard); 16.2 multiplies by `_highlightScaleForAppLayout:`. In 16.0 the hover/touch scale (0.98/0.9/1.1) lived in `scaleForLayoutRole:inAppLayout:` 0x1c613e410, and also applied stage occlusion scales |
| `_highlightScaleForAppLayout:`, `adjustedSpaceAccessoryViewScale:forAppLayout:` | (inline in 0x1c613e410) / none | NEW: accessory view scale is divided by the highlight scale so the accessory is not scaled with the card |
| `adjustedSpaceAccessoryViewFrame:forAppLayout:` | 0x1c613e0d0 | 16.0 paged the strip: x was offset by `+/- stripWidth * floor(identifierIndex / numberOfVisibleContinuousExposeIdentifiersWhileInApp)` relative to `_leftStripOriginX` (UNSURE exact formula; RTL negates); 16.2: single column, `x = _appStripOriginX - w/2` for strip ids only, frame untouched otherwise |
| `adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:` | 0x1c613e228 | 16.0 had a fullscreen check; 16.2 unconditional |
| `visibleAppLayouts` / `_orderedVisibleAppLayoutsIgnoringProgress:` | 0x1c613e5c0 / `_orderedVisibleAppLayouts` 0x1c613e60c | 16.0: started with the full-screen layout, capped total identifiers, per-group cap; 16.2: no stage layout (parent adds it via `setByAddingObject:`), gated on strip progress > 0 / `requireStripContentsInViewHierarchy` / ignoringProgress |
| `topMostLayoutElements` | 0x1c613fb28 | same shape (`[ordered array]`); 16.2 FullScreen also overrides it (0x1c75c4284, 41 instrs) and presumably merges its own element - not verified |
| `inactiveAppLayoutsReachableByKeyboardShortcut` | none | NEW (keyboard navigation of strip items) |
| `opacityForLayoutRole:inAppLayout:atIndex:` | 0x1c613ea88 | 16.0 returned super opacity for fullscreen / same-id layouts and 0 if `environment == 3`; 16.2 pure strip logic (`pileIdx > perGroup` -> 0) |
| `cornerRadiiForIndex:` | 0x1c613ebf4 | 16.0 handled fullscreen (`displayCornerRadius`, `stageCornerRaddii`, `appLayoutContainsAnUnoccludedMaximizedDisplayItem:`); 16.2 only stage->super, strip-> `stripCornerRaddii / scale` |
| `wallpaperGradientAttributesForIndex:` | 0x1c613ed18 | same projection math; 16.0 returned MakeEmpty for the fullscreen layout, 16.2 moved that check to the parent |
| `_wallpaperDimmingForIndex:` | 0x1c613f0f4 | same formula, 16.0 used `_indexOf...IgnoringStage` |
| `titleAndIconOpacityForIndex:` | 0x1c613f1a8 | 16.0 returned 0 for fullscreen layout first |
| `perspectiveAngleForAppLayout:` | 0x1c613faac | 16.0 returned 0 for fullscreen layout |
| `isHomeAffordanceSupportedForAppLayout:` | 0x1c613fb84 (fullscreen-dependent) | strip always NO |
| `_positionForPositionIn3DContainerSpace:...` | 0x1c61411f0 | same |
| `_isGroupForAppLayoutHighlightedFromTouch/Hover:` | 0x1c6141910 / 0x1c6141a80 | 16.0 excluded layouts that `containsAnyItemFromAppLayout:_fullScreenAppLayout`; 16.2 excludes `_isAppLayoutEffectivelyOnStage:` |
| `_isAppLayoutEffectivelyOnStage:` | none | NEW (stage membership incl. "swap one item" case) |
| `handleEvent:` | 0x1c613fde0 | 16.0 only `_invalidateLeftStripOriginX; genCount++; [super handleEvent:]`. 16.2 additionally emits `SBUpdateLayoutSwitcherEventResponse(options 2)` when `requireStripContentsInViewHierarchy` flips |
| `handleHighlightEvent:` | 0x1c6140504 | same set bookkeeping; 16.0 also (a) started a displacement timer (`...DisplaceFullScreenAppLayoutTimerEventReason`, `initWithDelay:validator:reason:`) and managed `_fullScreenAppDisplacementState` on hover begin when `_anyItemOverlapsStrip`, `_effectiveStripVisibleProgress==1`, strip not hidden; these moved to the FullScreen parent / other modifiers in 16.2 |
| (16.0 only) `handleSwitcherSettingsChangedEvent:` | 0x1c614092c | 16.0 returned an update-layout response; no equivalent in 16.2 strip |
| `animationAttributesForLayoutElement:` | none in 16.0 FullScreen | NEW: forces updateMode 3 on strip elements |
| `_currentLayoutCalculationsValidityToken` | 0x1c61409c4 | adds `continuousExposeIdentifiersGenCount` |
| `buildLayoutCalculationsForCache:` | `buildLayoutCalculations` 0x1c6140a48 (+block 0x1c6140e5c) | 16.0: loop capped at `numberOfVisibleContinuousExposeIdentifiersWhileInApp`, ids from `_continuousExposeIdentifiersIgnoringStage`, **frame.x = `_leftStripOriginX`**, containerBounds via `[super containerViewBounds]`; 16.2: all strip ids, x=0, bounds via self |
| `_appStripOriginX` / `_invalidateAppStripOriginX` | `_leftStripOriginX` 0x1c6141120 / `_invalidateLeftStripOriginX` 0x1c61411e0 | 16.0: `origin = min(padding, max(progress*(stripWidth+2*padding) - (stripWidth+padding), -(stripWidth+padding)))` with `progress = _effectiveStripVisibleProgress` (0x1c6141464) and memoized by `!= 0` only (invalidated per event). 16.2: `origin = progress*(stripWidth+padding) - stripWidth` with `progress = continuousExposeStripProgress`; memo keyed on (origin != 0, progress equal); invalidated per event too |
| `_stripFrame` | 0x1c6141c94 | same |
| `.cxx_destruct` / accessors | 0x1c6141e04 ... | trivial |

### Top behavioural differences (likely the fixes backported by 20C65)
1. Strip origin is no longer baked into the layout cache; animation/progress changes do not need cache rebuilds and the strip tracks `continuousExposeStripProgress` smoothly (frameForIndex + `_appStripOriginX`).
2. Strip item set is no longer capped to `numberOfVisibleContinuousExposeIdentifiersWhileInApp`; overflow is handled by the new strip-overflow reveal gesture classes (see WORKLIST `SBRevealContinuousExposeStripOverflow*`). Per-group card cap (`numberOfVisibleItemsPerGroup`) is now applied consistently (anchor point, visibility, opacity).
3. "On stage" is determined by `_isAppLayoutEffectivelyOnStage:` (stage layout from `appLayoutOnContinuousExposeStage`, supports stage with N items and one-item swaps) rather than by comparison with the single full-screen layout.
4. Highlight (hover/touch) scale moved into `scaleForIndex:` and is compensated in `adjustedSpaceAccessoryViewScale:`.
5. Layout cache validity now includes `continuousExposeIdentifiersGenerationCount`; `handleEvent:` forces a layout update when `requireStripContentsInViewHierarchy` changes (strip views get added to the hierarchy before they are revealed).
6. Keyboard navigation list (`inactiveAppLayoutsReachableByKeyboardShortcut`) and `animationAttributesForLayoutElement:` (updateMode 3) are new.

---------------------------------------------------------------------------------------------------

## 6. Open uncertainties

- `widthLimitForCount` block in `buildLayoutCalculationsForCache:` uses container **width** minus twice the strip width plus `stackDistance*(perGroup-count)` as the limit against which the group's bounding-box **width** is compared; arithmetic is exact, intent unclear.
- Exact prototype of `CAPointApplyTransform` (returns four doubles; 2nd call's `z`/`w` arguments are taken from the first call's return registers d2/d3 - transcribed as written).
- Which of left/right projected edge feeds `leadingAlpha` vs `trailingAlpha` in `wallpaperGradientAttributesForIndex:` (derived from register flow: x0 <- second call, x1 <- first call).
- Enum names for `shadowStyle` (5), `headerStyle` (1), highlight event `phase` values (1,2 treated as end/cancel, 0 and >=3 as begin).
- The `SBSwitcherGradientWallpaperAttributesMakeEmpty()` call at the tail of `wallpaperGradientAttributesForIndex:` is dead (result ignored).
- In `handleHighlightEvent:`, hover events that are on-stage or have phase 0/>=3 operate on the TOUCH set (verified in the branch structure, 0x1c75df8d4); likely an upstream quirk.
- `opacityForLayoutRole:...` uses `>` (pile index > perGroup) whereas `_orderedVisibleAppLayouts` keeps `<= perGroup` entries *per group counted from 1*; an off-by-one in upstream or intended fade-in slot.
- Initial `_cached_appStripUnocclusionProgress` is 0 not -1; first `_appStripOriginX` call is still correct because `_cached_appStripOriginX == 0` forces recompute.
