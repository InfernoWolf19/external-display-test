# Group 1b: Continuous Expose (Stage Manager) switcher modifiers, gesture modifiers and transitions (iPadOS 16.2 20C65 vs 16.0 20A8372)

Everything below is read from the SpringBoard binary of the iPadOS 16.2 shared cache (build 20C65) and compared with
16.0 (20A8372). All 16.2 addresses are unslid vm addresses (`0x1c7...` = `__TEXT.__text`). "16.0:" gives the 16.0 address or
`new`. Method dumps: `sb162_objc.txt` / `sb160n_objc.txt`; annotated disassembly: `g1b/162/<Class>.txt`, `g1b/160/<Class>.txt`
(scratchpad). Already specified elsewhere and NOT repeated: `SBStripContinuousExposeSwitcherModifier.md`,
`SBFullScreenContinuousExposeSwitcherModifier.md`; `SBContinuousExposeToHomeSwitcherModifier` is ported (SwitcherDismissFix 0.3.0).

Tag legend used for PORTABILITY: **PORTABLE** (hook on an existing 16.0 class, or a pure new class that only needs things 16.0 has),
**PARTIAL: why**, **NOT PORTABLE: why**.
`// UNSURE:` marks anything not fully nailed down. "ARM idiom" notes: a block is `___N-[Class sel]_block_invoke`; its literal
holds the invoke pointer at +0x10.

---------------------------------------------------------------------------------------------------

## 0. Cross-cutting facts that every section below relies on

### 0.1 Event type enum (`-[SBSwitcherModifierEvent type]`, read from every subclass)

16.0 and 16.2 agree for types 1..35. 16.2 appends three event classes (all absent from 16.0):

| type | class (16.2) | 16.0 |
|---|---|---|
| 1 Transition, 2 Gesture, 3 ForcePressGesture, 4 ScrunchGesture, 5 DragAndDropGesture, 6 IndirectPanGesture, 7 ReduceMotionChanged, 8 SwitcherSettingsChanged, 9 HomeGestureSettingsChanged, 10 MedusaSettingsChanged, 11 HomeGrabberSettingsChanged, 12 Highlight, 13 SwipeToKill, 14 Insertion, 15 Removal, 16 Timer, 17 TapOutsideToDismiss, **18 TapAppLayout**, 19 TapSlideOverTongue, 20 Scroll, 21 UpdateFocusedAppLayout, 22 ResizeProgress, 23 BlurProgress, 24 RepositionProgress, 25 SceneReady, 26 CardDrop, 27 SlideOverEdgeProtectTongue, 28 MorphToPIPChanged, 29 AnimatablePropertyChanged, 30 ShelfFocusedDisplayItemsChanged, 31 PrepareForSceneUpdate, 32 ItemResizeGesture, 33 Hover, 34 UpdateWindowingMode, 35 ContinuousExposeIdentifiersChanged | identical |
| **36** | `SBContinuousExposeStripEdgeProtectTongueSwitcherModifierEvent` (`type` @0x1c75ca480) | new |
| **37** | `SBTapAppLayoutHeaderSwitcherModifierEvent` (`type` @0x1c77b1620) | new |
| **38** | `SBPointerCrossedDisplayBoundarySwitcherModifierEvent` (`type` @0x1c7464c28) | new |

`-[SBSwitcherModifier _handleEvent:]` (16.2 @0x1c7895274; 16.0 @0x1c63e8a98) is a jump table `switch(event.type)` that calls
`handle<X>Event:`; for 16.2 the table has 0x27 entries (types 0..0x26). For an out-of-range type it returns the result of
`[super _handleEvent:]` (nil). **So a 16.0 process silently ignores types 36..38** (no crash) unless `_handleEvent:` is hooked.
New `SBSwitcherModifier` handlers in 16.2 (all return nil by default; base impl @ 0x1c7895ab8..): `handleContinuousExposeStripEdgeProtectTongueEvent:`,
`handlePointerCrossedDisplayBoundaryEvent:`, `handleTapAppLayoutHeaderEvent:`. PORT: hook `-[SBSwitcherModifier _handleEvent:]`
(PORTABLE, one hook): `%orig` first; if `event.type` is 36/37/38 and `self` responds to the corresponding handler selector,
return `[self handleXEvent:event]` (the base handler does not exist in 16.0, so `respondsToSelector:` is the guard; subclasses
created at run time simply define the method). Do not forget the nil/`SBAppendSwitcherModifierResponse` convention: the handler
returns an `SBSwitcherModifierEventResponse` (or nil).

### 0.2 Event-response type enum (`-[SBSwitcherModifierEventResponse type]`)

16.2 inserted a response at 34, **renumbering 34..36 to 35..37**, and appended two:

| type 16.2 | class | 16.0 |
|---|---|---|
| 1..33 | PerformTransition, CompleteGesture, Haptic, ..., UpdateContinuousExposeStripsPresentation (33) | identical numbers |
| **34** | `SBInvalidateContinuousExposeIdentifiersEventResponse` (@0x1c760b72c = 0x22) | new (34 was RequestSystemApertureElementSuppression) |
| 35 / 36 / 37 | RequestSystemApertureElementSuppression / Relinquish... / InitiateSystemApertureBounce | 34 / 35 / 36 |
| **38** | `SBSetInterfaceOrientationFromUserResizingEventResponse` (0x26) | new |
| **39** | `SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse` (0x27) | new |

Consequence for a port: `-[SBFluidSwitcherViewController _performEventResponse:]` switches on this number (16.0 @0x1c5fe2024, 16.2
@0x1c745b6f0). A response class created at run time in 16.0 must therefore use a type number that 16.0 does not use (>= 37, e.g.
the 16.2 numbers 38/39, and 34 must NOT be reused) and `_performEventResponse:` must be hooked to recognise it. See each response
class below.

### 0.3 Query / context protocol additions (these cannot be dispatched through 16.0's chain)

`+[SBChainableModifier querySelectors]` is built once from `+queryProtocol` (`SBSwitcherQueryProviding` incl. its
`...DefaultImplementationProviding` / `...MultitaskingQueryProviding` parents) and `+contextSelectors` from `SBSwitcherContextProviding`
(`newCacheWithSelectorList:subsequentMethodCacheFunc:cachingDictionary:` @0x1c642acc0). A selector that is not in the 16.0
protocol is never forwarded by the chain: `[super sel]` from a modifier is a plain message to `SBSwitcherModifier`, which does not
implement it in 16.0. Protocol deltas (protocol lists compared 16.0 vs 16.2):

* `SBSwitcherQueryDefaultImplementationProviding` + : `adjustedSpaceAccessoryViewScale:forAppLayout:`,
  `clippingFrameForLayoutRole:inAppLayout:atIndex:withBounds:`, `continuousExposeStripTongueAttributes`,
  `isContinuousExposeStripVisible`, `proposedAppLayoutForContinuousExposeWindowDrag`,
  `spaceAccessoryViewIconHitTestOutsetForAppLayout:`, `wantsContinuousExposeHoverGesture`; - : `adjustedContinuousExposeIdentifiersForIdentifiers:`
* `SBSwitcherQueryProviding` + : `activeLeafAppLayoutsReachableByKeyboardShortcut`, `canSelectLeafWithModifierKeysInAppLayout:`,
  `inactiveAppLayoutsReachableByKeyboardShortcut`, `shouldAllowGroupOpacityForAppLayout:`; - : `shouldConfigureInAppDockVisibleAssertion`
* `SBSwitcherMultitaskingQueryProviding` + : `adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:`,
  `adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:`
* `SBSwitcherContextProviding` + : `appLayoutOnContinuousExposeStage`, `continuousExposeIdentifiersGenerationCount`,
  `continuousExposeIdentifiersInStrip`, `continuousExposeIdentifiersInSwitcher`, `continuousExposeStripProgress`,
  `continuousExposeStripTongueBackdropCaptureLayoutElement`, `draggingAppLayoutsForContinuousExposeWindowDrag`,
  `layoutRestrictionInfoForItem:`, `newContinuousExposeIdentifiersGenerationCount`, `proposedAppLayoutsForContinuousExposeWindowDrag`,
  `requireStripContentsInViewHierarchy`, `supportedContentInterfaceOrientationsForItem:`; - : `continuousExposeAppStripUnoccludedProgress`,
  `continuousExposeIdentifiers`, `numberOfVisibleContinuousExposeIdentifiersWhileInApp`
* The Continuous Expose identifier model was split: 16.0 has one list `continuousExposeIdentifiers` (+ `...IgnoringStage`,
  `...InStripFromIdentifiers:`, `adjustedContinuousExposeIdentifiersForIdentifiers:`); 16.2 has `...InSwitcher` and `...InStrip`
  with a generation count. Any 16.2 class that answers/overrides the new identifier queries has no direct 16.0 counterpart
  and must be mapped onto the 16.0 single-list API (called out per class).

### 0.4 Subclassing contract for modifiers created at run time (from SwitcherDismissFix 0.3.0 + what the chain code does)

* `SBChainableModifier` is abstract: `-init` asserts `[self class]` is not exactly `SBChainableModifier`; it creates
  `_queryCache` / `_contextCache` from `[self class]` (`+newQueryCache`/`+newContextCache`). `+initialize` calls
  `+_initalizeIMPCaching` for each class when the class is first messaged, so **every query/context method must be added with
  `class_addMethod` before the first message to the new class** (i.e. before `objc_registerClassPair` + first `alloc`).
* How `[super query]` works (decoded from 16.0 `+[SBChainableModifier _initalizeIMPCaching]` @0x1c642a6c0): when `+initialize` runs for the
  class that introduced `+queryProtocol` (`SBSwitcherModifier`, `+baseClassForQueryProtocol` @0x1c642a4d8) it walks
  `protocol_copyMethodDescriptionList(queryProtocol)` (and all parent protocols) and, for every selector the base class does not
  implement itself, `class_addMethod`s a **query trampoline** (`_SBChainableModifierMethodCacheQueryTrampolineForMethod(sel, types, idx)`
  @0x1c62acb8c) on `SBSwitcherModifier` (context methods likewise via `newContextCache`). `[super X]` from any modifier therefore lands in that trampoline,
  which dispatches through the per-instance method cache to the next modifier in the stack that overrides X (finally the
  `SBFluidSwitcherViewController` provider). `provideNextQueryImplementation:forSelector:` (0x1c5f5a850) builds a throw-away
  `SBSwitcherModifier-<Class>-<UUID>` dynamic subclass (`makeDynamicSubclassWithDescriptor:implementation:forSelector:ofProtocol:` 0x1c5f5a9dc,
  `imp_implementationWithBlock`) and inserts an instance of it after the modifier.
  **Consequences:** (a) the trampoline set is frozen when 16.0's `SBSwitcherModifier` initialised, so a 16.2-only selector (0.3) has NO
  trampoline in 16.0: `[super newSel]` from a run-time class is an unrecognized-selector crash, so every `[super X]` in this file is
  guarded with `class_getInstanceMethod(superclass, X)` (G1B_HasSuper); (b) a modifier participates in a query only if its class's IMP
  for that selector differs from the trampoline, hence override only selectors that are in the 16.0 protocol (0.3), and add them
  before the class's first message. Use the type encodings of
  `SBDefaultImplementationsSwitcherModifier` (the "donor") for the added methods; `[super sel]` must be sent with
  `objc_msgSendSuper` using the **runtime-created class's superclass** (`SBSwitcherModifier` or `SBTransitionSwitcherModifier`
  etc.), exactly like `W_Super` in SwitcherDismissFix.
* Event handlers (`handleXEvent:`, `_handleEvent:`) are plain methods dispatched by `SBChainableModifier -handleEvent:` over the
  modifier stack: they may be added at any time. `-setState:`, `-didMoveToParentModifier:` are plain methods too.
* Children are attached with `-addChildModifier:`, `-addChildModifier:atLevel:key:` (0x1c6428fc0 in 16.0) and
  `-performTransactionWithTemporaryChildModifier:usingBlock:`; all exist in 16.0.
* Class names: the classes below do not exist in 16.0, so the run-time class can carry the 16.2 name (guard with
  `NSClassFromString(name) == nil`). Ivars are added with `class_addIvar` (new class: legal); use `ivar_getOffset(class_getInstanceVariable(...))`
  looked up once, never a constant.
* Response / event classes (`SBSwitcherModifierEventResponse` / `SBSwitcherModifierEvent` subclasses) have no machinery: plain
  `NSObject` subclasses with `-type`.

### 0.5 Helper API used throughout (all present in 16.0 unless noted)

`SBAppendSwitcherModifierResponse(newResponse, existing)` (16.2 @0x1c773a35c; 16.0 symbol of the same name): returns a
`SBChainedSwitcherModifierEventResponse`-style combination of the new response followed by the existing one (either may be nil).
`SBUpdateLayoutSwitcherEventResponse initWithOptions:updateMode:`, `SBTimerEventSwitcherEventResponse initWithDelay:validator:reason:`,
`SBAddModifierSwitcherEventResponse`, `SBPerformTransitionSwitcherEventResponse`, etc. are unchanged between builds.

---------------------------------------------------------------------------------------------------

## 1. Priority 1: new support classes

### 1.1 SBFilteringSwitcherModifier  (NEW in 16.2; class object 0x1de235fa8, +_SBFilteringPassthroughTargetSwitcherModifier 0x1de235fd0)

Superclass `SBSwitcherModifier`; adopts `SBRoutingSwitcherModifierDelegate`. 16.0: **new** (the protocol and `SBRoutingSwitcherModifier`
exist in 16.0, with the same required delegate methods except `fallbackModifierForRoutingModifier:`, see below).

Purpose: a "view splitter". It wraps one child modifier (`_modifier`) and a set of app layouts (`_appLayoutsToFilter`) so that the
child only ever sees (and only answers for) the given app layouts / their display items, while every other app layout is answered
by the rest of the modifier stack (the "passthrough" target). It is built on `SBRoutingSwitcherModifier`, whose delegate it is.
Used by: `SBContinuousExposeWindowDragRootSwitcherModifier -gestureChildModifierForGestureEvent:activeTransitionModifier:`
(0x1c7461234, + block @0x1c74611xx) and `SBContinuousExposePeekSwitcherModifier -initWithAppLayout:configuration:` (0x1c78e5184).
Both give `@[the dragged / peeked app layout]` and a content modifier (`_SBContinuousExposeWindowDragContentSwitcherModifier` /
`_SBContinuousExposePeekContentSwitcherModifier`, sections 3.x).

`_SBFilteringPassthroughTargetSwitcherModifier` (0x1de235fd0): empty subclass of `SBSwitcherModifier`, no ivars, no methods
(class dump has no methods). It only exists as a distinct object that the routing modifier can address as "everything else".

Ivars: `_routingModifier` +0x60 (SBRoutingSwitcherModifier), `_passthroughModifier` +0x68, `_displayItemsToFilter` +0x70 (NSSet),
`_appLayoutsToFilter` +0x78 (NSArray, copy), `_modifier` +0x80.

```objc
// ---- 16.2 reconstruction ------------------------------------------------------------------------------------------
- (instancetype)initWithAppLayouts:(NSArray *)appLayouts modifier:(SBSwitcherModifier *)modifier {      // 0x1c77f09d8
    NSParameterAssert / NSAssertionHandler checks (file "SBFilteringSwitcherModifier.m", lines 0x24 and 0x25):
        appLayouts != nil  ("appLayoutsToFilter"),  modifier != nil ("modifier")   // handleFailureInMethod only; continues
    self = [super init];
    if (self) {
        _appLayoutsToFilter = [appLayouts copy];
        _modifier = modifier;                                    // strong
        _passthroughModifier = [[_SBFilteringPassthroughTargetSwitcherModifier alloc] init];
        _routingModifier = [[SBRoutingSwitcherModifier alloc] initWithModifiers:@[ _modifier, _passthroughModifier ] delegate:self];
        [self addChildModifier:_routingModifier atLevel:0 key:nil];
        // 0x1c77f0b20: displayItemsToFilter = NSSet( flatten( compactMap(appLayouts, ^(SBAppLayout *l){ return [l allItems]; }) ) )
        //   (block literal 0x1e18f0180, invoke 0x1c77f0c3c = "return [layout allItems]")
        _displayItemsToFilter = [NSSet setWithArray:[[appLayouts bs_compactMap:^id(SBAppLayout *l){ return [l allItems]; }] bs_flatten]];
    }
    return self;
}

- (void)didMoveToParentModifier:(SBChainableModifier *)parent {                                        // 0x1c77f0c44
    [super didMoveToParentModifier:parent];
    if (parent) {
        // The routing modifier set itself as delegate of every modifier it routes to (SBRoutingSwitcherModifier
        // -didMoveToParentModifier: loops over _modifiers calling setDelegate:self; 16.0 @0x1c609cf8c does the same).
        if ([_passthroughModifier delegate]) {
            [_passthroughModifier setDelegate:nil];
            // Hang the passthrough target off THIS modifier too (level 1), so that asking it falls through to whatever lies
            // beneath the filtering modifier in the parent's stack.
            [self addChildModifier:_passthroughModifier atLevel:1 key:nil];
            [self newAppLayoutsGenCount];     // invalidate cached appLayouts of the routing modifier
        }
    }
}

- (void)setState:(long long)state {                                                                     // 0x1c77f0ce0
    long long old = [self state];
    if (state == 1 && old != 1) [self newAppLayoutsGenCount];    // UNSURE: state 1 = "completed" (the parent removes completed children); the cache is invalidated when the filter goes away
    [super setState:state];
}
```

Delegate methods (`SBRoutingSwitcherModifierDelegate`), all 16.2 addresses:

```objc
// 0x1c77f0d48  routingModifier:event:forModifier:   - decides which routed modifier sees which event (nil = skip)
- (SBSwitcherModifierEvent *)routingModifier:(id)routing event:(SBSwitcherModifierEvent *)event forModifier:(id)forModifier {
    switch (event.type) {
    case 18 /* TapAppLayout */:
        if (forModifier == _modifier) {                       // content modifier only sees taps on filtered layouts
            if ([_appLayoutsToFilter containsObject:event.appLayout]) return event; }
        if (forModifier == _passthroughModifier) {            // everything else only sees taps on non-filtered layouts
            if (![_appLayoutsToFilter containsObject:event.appLayout]) return event; }
        return nil;
    case 1 /* Transition */: {
        SBTransitionSwitcherModifierEvent *e = [event copy];
        SBAppLayout *from = e.fromAppLayout, *to = e.toAppLayout;
        if (from) e.fromAppLayout = [[self routingModifier:_routingModifier filteredAppLayouts:@[from] forModifier:forModifier] firstObject];
        if (to)   e.toAppLayout   = [[self routingModifier:_routingModifier filteredAppLayouts:@[to]   forModifier:forModifier] firstObject];
        // Environment modes: 1 = home screen, 2 = app switcher, 3 = app. After filtering a side may have lost its app layout.
        if      (e.fromEnvironmentMode == 3 && e.fromAppLayout == nil) e.fromEnvironmentMode = 1;
        else if (e.fromEnvironmentMode == 1 && e.fromAppLayout != nil) e.fromEnvironmentMode = 3;
        if      (e.toEnvironmentMode   == 3 && e.toAppLayout   == nil) e.toEnvironmentMode   = 1;
        else if (e.toEnvironmentMode   == 1 && e.toAppLayout   != nil) e.toEnvironmentMode   = 3;
        return e; }
    default: return event;                                    // all other event types are broadcast unchanged
    }
}

// 0x1c77f1084  routingModifier:filteredAppLayouts:forModifier:
- (NSArray *)routingModifier:(id)routing filteredAppLayouts:(NSArray *)layouts forModifier:(id)forModifier {
    if (forModifier == _modifier)     // keep only the display items that are in _displayItemsToFilter (block 0x1c77f1154 -> inner 0x1c77f11dc)
        return [layouts bs_compactMap:^(SBAppLayout *l){ return [l appLayoutWithItemsPassingTest:^BOOL(SBDisplayItem *i){ return  [_displayItemsToFilter containsObject:i]; }]; }];
    else                              // every other modifier: the complement (block 0x1c77f11f4 -> inner 0x1c77f127c : !contains)
        return [layouts bs_compactMap:^(SBAppLayout *l){ return [l appLayoutWithItemsPassingTest:^BOOL(SBDisplayItem *i){ return ![_displayItemsToFilter containsObject:i]; }]; }];
    // compactMap drops layouts for which appLayoutWithItemsPassingTest: returned nil (no item passed)
}
// 0x1c77f12ac  routingModifier:modifierForAppLayout:
- (id)routingModifier:(id)routing modifierForAppLayout:(SBAppLayout *)l {
    return [l containsAnyItemFromSet:_displayItemsToFilter] ? _modifier : _passthroughModifier;
}
// 0x1c77f1310  routingModifier:filteredContinuousExposeIdentifiers:forModifier:   -> returns identifiers unchanged
// 0x1c77f1338  routingModifier:containerViewBoundsForModifier:  -> [super containerViewBounds]       (CGRect, tail call objc_msgSendSuper2)
// 0x1c77f1370  routingModifier:switcherViewBoundsForModifier:   -> [super switcherViewBounds]
// 0x1c77f13a8  scrollModifierForRoutingModifier:                -> _passthroughModifier
// 0x1c77f13b8  homeScreenModifierForRoutingModifier:            -> _passthroughModifier
// 0x1c77f13c8  transactionCompletionOptionsModifierForRoutingModifier: -> _passthroughModifier
// 0x1c77f13d8  routingModifier:animationAttributesModifierForLayoutElement:(SBSwitcherLayoutElement *)el
//                 -> (el.switcherLayoutElementType == 0 /* app layout */ && [_appLayoutsToFilter containsObject:el]) ? _modifier : _passthroughModifier
// 0x1c77f144c  fallbackModifierForRoutingModifier:             -> _passthroughModifier        (16.2-only protocol method)
// 0x1c77f145c  appLayoutsToFilter, 0x1c77f146c modifier        (getters)
```

**What it changes / fixes.** Nothing by itself; it is infrastructure for the peek and window-drag modifiers (3.x) so they can restyle
exactly one window (the dragged / peeked one) without the strip / stage modifiers having to special-case it (in 16.0 the drag logic was
interleaved with the stage logic in `SBContinuousExposeWindowDragSwitcherModifier`; confidence high).

**Wiring.** Created by the drag-root modifier (event type 2 gesture, `gestureChildModifierForGestureEvent:...`) and the peek modifier init.
Not reachable from any root-modifier factory directly.

**PORTABILITY: PORTABLE (new class, full reconstruction).** Needs only things that exist in 16.0: `SBRoutingSwitcherModifier
initWithModifiers:delegate:` (16.0 @0x1c609cee8), `addChildModifier:atLevel:key:`, `newAppLayoutsGenCount` (all selectors verified present in the
16.0 binary), `bs_compactMap:`, `bs_flatten`, `-[SBAppLayout allItems / appLayoutWithItemsPassingTest: / containsAnyItemFromSet:]`.
Differences to honour on 16.0:
1. `fallbackModifierForRoutingModifier:` is never called by the 16.0 routing modifier (the 16.0 class has no `_currentModifierOrFallback`;
   it passes `_currentModifier`, possibly nil, as the `forModifier:` argument to `routingModifier:containerViewBoundsForModifier:`
   and friends; the three bounds delegate methods above ignore their `forModifier:` argument, so this is harmless).
   Still implement it (harmless).
2. The class must be a run-time class (`objc_allocateClassPair(SBSwitcherModifier, "SBFilteringSwitcherModifier", 0)`) with 5 ivars
   and the delegate protocol added (`class_addProtocol(cls, objc_getProtocol("SBRoutingSwitcherModifierDelegate"))`, present in 16.0).
   `_SBFilteringPassthroughTargetSwitcherModifier` is a trivial `objc_allocateClassPair(SBSwitcherModifier, ..., 0)` with no methods.
3. Query methods are not overridden by this class (the routing modifier does the work), so the "override only 16.0 query selectors"
   rule is automatically satisfied.
Code: `group1b-modifiers.hooks.m` section 1.1.

---------------------------------------------------------------------------------------------------

### 1.2 SBOverrideContinuousExposeIdentifiersSwitcherModifier  (NEW in 16.2; class object 0x1de23a2d8)

Superclass `SBSwitcherModifier`. 16.0: **new** (in 16.0 the same idea is the flag `_overrideWithPreviousIdentifiers` (+0x62) inside
`SBContinuousExposeIdentifierSlideModifier`, which answers `continuousExposeIdentifiers` itself and returns
`_previousContinuousExposeIdentifiers` while the flag is set; 16.2 factored it out).

Ivars: `_overrideContinuousExposeIdentifiersInSwitcher` +0x60 (NSArray copy), `_overrideContinuousExposeIdentifiersInStrip` +0x68 (NSArray copy).

```objc
- (instancetype)initWithContinuousExposeIdentifiersInSwitcher:(NSArray *)sw continuousExposeIdentifiersInStrip:(NSArray *)strip {  // 0x1c798bba4
    self = [super init];
    if (self) { _overrideContinuousExposeIdentifiersInSwitcher = [sw copy]; _overrideContinuousExposeIdentifiersInStrip = [strip copy]; }   // nil allowed
    return self;
}
- (void)didMoveToParentModifier:(id)parent {                    // 0x1c798bc50
    [super didMoveToParentModifier:parent];
    if (parent) [self newContinuousExposeIdentifiersGenerationCount];     // context call; invalidates the cached identifier lists
}
- (void)setState:(long long)state {                             // 0x1c798bca4
    if (state == 1 && [self state] != 1) {
        if ([self parentModifier] != nil || [self delegate] != nil) [self newContinuousExposeIdentifiersGenerationCount];
    }
    [super setState:state];
}
// context overrides: answer context requests made by any modifier stacked after this one (others fall through via [super])
- (NSArray *)continuousExposeIdentifiersInSwitcher {            // 0x1c798bd44
    return _overrideContinuousExposeIdentifiersInSwitcher ?: [super continuousExposeIdentifiersInSwitcher];
}
- (NSArray *)continuousExposeIdentifiersInStrip {               // 0x1c798bda8
    return _overrideContinuousExposeIdentifiersInStrip ?: [super continuousExposeIdentifiersInStrip];
}
// 0x1c798be0c / 0x1c798be1c: getters overrideContinuousExposeIdentifiersInSwitcher / InStrip
```

**Used by** `-[SBContinuousExposeIdentifierSlideModifier _performBlockWithIdentifiersInSwitcher:identifiersInStrip:block:]`
(0x1c78713a4): it creates this modifier with the *previous* identifier lists and calls `performTransactionWithTemporaryChildModifier:usingBlock:`
so that the block's `[self frameForIndex:...]`-style evaluation sees the layout as it was before the identifiers changed (see 4.x Slide).

**Bug / behaviour fixed.** It removes the 16.0 state-flag approach (`_overrideWithPreviousIdentifiers`), which leaked "previous"
identifiers into every query made while the flag was set (confidence medium: inferred from the structural change, no crash reproduced).

**PORTABILITY: PARTIAL.** `continuousExposeIdentifiersInSwitcher` / `...InStrip` / `newContinuousExposeIdentifiersGenerationCount` do not exist in the
16.0 context protocol (0.3), so a 16.0 version has to override the 16.0 selector instead. 16.0 has a single list:
`continuousExposeIdentifiers` (context, answered by `SBFluidSwitcherViewController`, overridden by
`SBFullScreenContinuousExposeSwitcherModifier`, `SBOverrideAppLayoutsSwitcherModifier`, `SBContinuousExposeIdentifierSlideModifier`) which is the 16.2
"InSwitcher" list; `continuousExposeIdentifiersInStripFromIdentifiers:` derives the strip list. A faithful 16.0 class
(`SBOverrideContinuousExposeIdentifiersSwitcherModifier`, same name, same init) therefore overrides ONLY `continuousExposeIdentifiers`
(returns the "InSwitcher" override) and ignores the strip override, and `newContinuousExposeIdentifiersGenerationCount` must be mapped onto the
16.0 generation notion (`continuousExposeIdentifiersChangedGenerationCount` / `newAppLayoutsGenCount`; UNSURE which one 16.0 uses to invalidate
`SBFullScreenContinuousExposeSwitcherModifier`'s cached identifiers). Only useful together with the Slide modifier port (4.x); standalone it
has no consumer. Code: hooks section 1.2 (guarded: builds only if `continuousExposeIdentifiers` is a context selector of the 16.0 base).

---------------------------------------------------------------------------------------------------

### 1.4 SBPulseDisplayItemSwitcherModifier  (NEW in 16.2; class object 0x1de22ec58)

Superclass `SBSwitcherModifier`. 16.0: new (no header-tap handling at all; a tap on a window header went through the ordinary
`SBTapAppLayoutSwitcherModifierEvent`). Ivars: `_displayItem` +0x60, `_displayItemToPulse` +0x68.
Created by `SBFullScreenContinuousExposeSwitcherModifier -handleTapAppLayoutHeaderEvent:` (0x1c75c4b2c, single-window case; see that spec),
`SBInlineAppExposeContinuousExposeSwitcherModifier` (0x1c7686cf8) and `SBAppSwitcherContinuousExposeSwitcherModifier` (0x1c780fb88), each wrapped in
`[[SBAddModifierSwitcherEventResponse alloc] initWithModifier:pulse level:3]`.

```objc
- (instancetype)initWithDisplayItem:(SBDisplayItem *)item {                              // 0x1c74c6bd0
    self = [super init];
    if (self) { _displayItem = item; _displayItemToPulse = item; }                        // both strong, same object
    return self;
}
// 0x1c74c6c60  The modifier is attached when the header is tapped; it IMMEDIATELY receives the same TapAppLayoutHeader event.
- (id)handleTapAppLayoutHeaderEvent:(SBTapAppLayoutHeaderSwitcherModifierEvent *)event {
    id response = [super handleTapAppLayoutHeaderEvent:event];
    response = SBAppendSwitcherModifierResponse([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:4 updateMode:3], response);
    CGFloat delay = [[[self switcherSettings] animationSettings] pulseSecondStageDelay];          // SBSwitcherAnimationSettings (exists in 16.0)
    response = SBAppendSwitcherModifierResponse([[SBTimerEventSwitcherEventResponse alloc] initWithDelay:delay validator:nil
                                                                         reason:@"SBPulseDisplayItemSwitcherModifierTimerReason"], response);
    return response;
}
// 0x1c74c6d6c  second stage: stop pulsing and complete.
- (id)handleTimerEvent:(SBTimerSwitcherModifierEvent *)event {
    id response = [super handleTimerEvent:event];
    if ([[event reason] isEqualToString:@"SBPulseDisplayItemSwitcherModifierTimerReason"]) {
        _displayItemToPulse = nil;
        response = SBAppendSwitcherModifierResponse([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:4 updateMode:3], response);
        [self setState:1];                                     // modifier is done; its parent removes it
    }
    return response;
}
// 0x1c74c6e6c  query (exists in 16.0)
- (double)scaleForLayoutRole:(long long)role inAppLayout:(SBAppLayout *)layout {
    double s = [super scaleForLayoutRole:role inAppLayout:layout];
    if ([[layout itemForLayoutRole:role] isEqual:_displayItemToPulse]) s *= [[[self switcherSettings] animationSettings] pulseScale];
    return s;
}
// 0x1c74c6f44  query
- (id)animationAttributesForLayoutElement:(SBSwitcherLayoutElement *)el {
    id attrs = [[super animationAttributesForLayoutElement:el] mutableCopy];
    if ([el switcherLayoutElementType] == 0 /* app layout */ && [(SBAppLayout *)el containsItem:_displayItemToPulse])
        [attrs setLayoutSettings:[[[self switcherSettings] animationSettings] pulseScaleSettings]];
    return attrs;
}
// 0x1c74c7034  query: no async rendering for the pulsing window
- (SBSwitcherAsyncRenderingAttributes)asyncRenderingAttributesForAppLayout:(SBAppLayout *)l {
    return [l containsItem:_displayItemToPulse] ? SBSwitcherAsyncRenderingAttributesMake(NO, NO) : [super asyncRenderingAttributesForAppLayout:l];
}
// 0x1c74c70b4  query: put the pulsed window's app layout on top when it is (inside) the stage layout
- (NSArray *)topMostLayoutElements {
    SBAppLayout *pulseLayout = [[self appLayouts] bs_firstObjectPassingTest:^BOOL(SBAppLayout *l){ return [l containsItem:_displayItem]; }];   // block 0x1c74c71e8
    if ([[self appLayoutOnContinuousExposeStage] isOrContainsAppLayout:pulseLayout])                    // 16.2-only context call
        return [[super topMostLayoutElements] sb_arrayByInsertingOrMovingObject:pulseLayout toIndex:0];
    return [super topMostLayoutElements];
}
```

Effect: tapping the title bar of a single-window app's window plays a two-stage scale "pulse" (scale by `pulseScale`, animated with
`pulseScaleSettings`, back after `pulseSecondStageDelay`) and brings that window to the front of the z-order for the duration. Confidence high.
Not a bug fix: a new feature (header tap = pulse, or App Expose when the app has several windows).

**PORTABILITY: PORTABLE (new class) with one substitution.** Every selector it calls exists in 16.0 (verified in the selector tables) except
`appLayoutOnContinuousExposeStage` (16.2-only context method). In 16.0, take the stage layout from the creator: add a plain method
`setStageAppLayout:` (associated object; the creator, which has `_fullScreenAppLayout`, sets it), and use it in `topMostLayoutElements`;
fall back to `[super topMostLayoutElements]` when it is nil. All five queries are in the 16.0 query protocol (so the chain picks them up);
`handleTapAppLayoutHeaderEvent:` only fires if 0.1 (the `_handleEvent:` hook) and the event emission (1.5) are in place. Usable standalone:
a tweak can also `performSelector` the handler directly. Code: hooks 1.4.

---------------------------------------------------------------------------------------------------

### 1.5 SBTapAppLayoutHeaderSwitcherModifierEvent  (NEW; event type 37; class object 0x1de235648)

Superclass `SBSwitcherModifierEvent`. Ivars `_appLayout` +0x18, `_layoutRole` +0x20 (long long). Methods: `initWithAppLayout:layoutRole:` (0x1c77b1594: super init, store,
no copy), `type` -> 37 (0x1c77b1620), `copyWithZone:` -> `[[Class alloc] initWithAppLayout:layoutRole:]` (0x1c77b1628; note: does not copy the
base `handled` state), `descriptionBuilderWithMultilinePrefix:` (appends `appLayout` succinct description and `_SBLayoutRoleDescription(layoutRole)`), getters.

Emitted by `-[SBFluidSwitcherViewController overlayAccessoryView:didSelectHeaderForRole:]` (16.2 @0x1c7451324; 16.0 @0x1c5fd8118):
```objc
- (void)overlayAccessoryView:(id)view didSelectHeaderForRole:(long long)role {
    SBAppLayout *layout = [[_visibleOverlayAccessoryViews allKeysForObject:view] firstObject];      // _visibleOverlayAccessoryViews ivar +0x6c8
    if (layout) {
        id event = [self isChamoisWindowingUIEnabled]                                              // Stage Manager on
                 ? [[SBTapAppLayoutHeaderSwitcherModifierEvent alloc] initWithAppLayout:layout layoutRole:role]            // NEW: type 37
                 : [[SBTapAppLayoutSwitcherModifierEvent alloc] initWithAppLayout:layout layoutRole:role modifierFlags:0];  // type 18 (16.0 always this)
        [self _dispatchEventAndHandleAction:event];
    } else { os_log SBLogAppSwitcher error }
}
```
**PORTABILITY: PORTABLE.** New plain class (type 37); hook `-[SBFluidSwitcherViewController overlayAccessoryView:didSelectHeaderForRole:]` (exists in 16.0) to
send the new event when `isChamoisWindowingUIEnabled` and `_dispatchEventAndHandleAction:` exist (both do in 16.0: 0x1c5fe17e4), and 0.1 for dispatch.
Because the 16.0 modifier stack does not implement `handleTapAppLayoutHeaderEvent:` (only the ported FullScreen/Pulse versions would), the hook must only
swap the event when at least one modifier of the stack handles it; otherwise 16.0 behaviour (type 18) is kept. Option: have the hook call `%orig` unless
`SBFullScreenContinuousExposeSwitcherModifier` responds to `handleTapAppLayoutHeaderEvent:` (i.e. the FullScreen port is active).

### 1.6 SBPointerCrossedDisplayBoundarySwitcherModifierEvent  (NEW; event type 38; class object 0x1de22e1b8)

Ivars `_edge` (unsigned int) +0x18, `_direction` (unsigned long long) +0x20. `initWithDirection:edge:` (0x1c7464bc4: super init, stores), `type` -> 38 (0x1c7464c28),
getters/setters for both. No copyWithZone: override. `direction`: 0 = pointer entered this display, 1 = pointer left this display (decoded below). `edge` = the
`SBExternalDisplayArrangementItem` edge (`-edge`) of the neighbour as seen from THIS display (UIRectEdge-like value; pass through unchanged).

Emitted by `-[SBFluidSwitcherViewController pointerDidMoveToFromWindowScene:toWindowScene:]` (0x1c745f938, new in 16.2; called by
`-[SBSystemPointerInteractionManager pointerDidMoveToFromWindowScene:toWindowScene:]` @0x1c73e8990 and
`-[SBMultiDisplayUserInteractionCoordinator eventSnifferHandledPointerInteractionQualifyingEvent:]` @0x1c795e9b8):
```objc
- (void)pointerDidMoveToFromWindowScene:(UIWindowScene *)from toWindowScene:(UIWindowScene *)to {
    UIWindowScene *mine = [[_switcherController windowScene] ...];             // _switcherController weak ivar +0x6a0
    if (!mine || !from || !to) return;
    id event;
    if (mine == from) {          // pointer LEAVES this display
        arrangement = [[SBApp externalDisplayService] preferredArrangementOfDisplay:[to _fbsDisplayIdentity] relativeTo:[from _fbsDisplayIdentity]];
        event = [[SBPointerCrossedDisplayBoundarySwitcherModifierEvent alloc] initWithDirection:1 edge:[arrangement edge]];
    } else if (mine == to) {     // pointer ENTERS this display
        arrangement = [[SBApp externalDisplayService] preferredArrangementOfDisplay:[from _fbsDisplayIdentity] relativeTo:[to _fbsDisplayIdentity]];
        event = [[SBPointerCrossedDisplayBoundarySwitcherModifierEvent alloc] initWithDirection:0 edge:[arrangement edge]];
    } else return;
    if (event) [self _dispatchEventAndHandleAction:event];
}
```
(`preferredArrangementOfDisplay:relativeTo:` is new in 16.2 `SBExternalDisplayService`; it replaces 16.0's `preferredArrangementOfDisplay:`; group 4 covers it.)
Consumer: `SBFullScreenContinuousExposeSwitcherModifier -handlePointerCrossedDisplayBoundaryEvent:` (see its spec) -> `SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse`.
**PORTABILITY: PARTIAL.** The event class is trivial and portable, but its only producer is the VC method above, whose callers
(`SBSystemPointerInteractionManager`, `SBMultiDisplayUserInteractionCoordinator`) and the observer protocol selector do not exist in 16.0; a port needs a
16.0 hook that detects a pointer crossing between window scenes (group 4: pointer routing / `SBMultiDisplayUserInteractionCoordinator`, whose 16.0 form should be checked)
and the arrangement/edge query (group 4). Provide the class + `G1B_DispatchPointerCrossed(from, to, edgeProvider)` and wire it from the group 4 detection.

### 1.7 SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse  (NEW; response type 39; class object 0x1de22dc18)

Superclass `SBSwitcherModifierEventResponse`. Ivar `_initialPresentation` (BOOL) +0x28. `initForInitialPresentation:` (0x1c741790c), `type` -> 39 (0x1c7417960),
`isInitialPresentation` / `setInitialPresentation:` (0x1c7417968/78).
Consumer: `-[SBFluidSwitcherViewController _performPresentContinuousExposeStripEdgeProtectGrabberResponse:]` (0x1c745ed48):
```objc
SBSwitcherController *sc = _switcherController;
if ([response isInitialPresentation]) [sc presentContinuousExposeStripRevealGrabberTongueImmediately];     // SBSwitcherController 0x1c7606c3c -> [_gestureManager ...] (ivar +0xd8)
else                                  [sc tickleContinuousExposeStripRevealGrabberTongueIfVisible];        // 0x1c7606c44
```
Also `SBMainSwitcherControllerCoordinator _acquireAssertion:/_updateAssertion:/_reqlinquishAssertion:` instantiate this class (UNSURE: probably to broadcast the same presentation request to other displays' switchers).
**PORTABILITY: PARTIAL.** The response class is trivial; its consumer needs a "strip reveal grabber tongue" (`SBFluidSwitcherGestureManager`
`presentContinuousExposeStripRevealGrabberTongueImmediately` / `tickle...IfVisible`) that 16.0 does not have (the 16.0 gesture manager only has the
slide-over tongue and `tapReceivedForGrabberTongueAtEdge:`). Port = new response class + `_performEventResponse:` hook (type 39) that calls those two selectors if the controller
responds, else no-op; the grabber UI itself belongs to the gesture-manager/strip-reveal spec (group 1c) and the `SBRevealContinuousExposeStripsGestureModifier` (4.x).

### 1.8 SBContinuousExposeStripEdgeProtectTongueSwitcherModifierEvent  (NEW; event type 36; class object 0x1de2307d8)

Ivar `_tonguePresented` (BOOL) +0x18. `initWithTonguePresented:` (0x1c75ca42c), `type` -> 36 (0x1c75ca480), `copyWithZone:` -> new with same flag (0x1c75ca488),
`isTonguePresented` (0x1c75ca4d0). Emitted with YES by `-[SBFluidSwitcherViewController presentContinuousExposeStripEdgeProtectTongue]` (0x1c744f4e0) and NO
by `dismissContinuousExposeStripEdgeProtectTongue` (0x1c744f540), via `_dispatchEventAndHandleAction:`. Consumer:
`SBContinuousExposeRootSwitcherModifier -handleContinuousExposeStripEdgeProtectTongueEvent:` (0x1c7819b74, sets `_isStripTonguePresented` ivar +0x70, see Root 4.x) which
feeds `continuousExposeStripTongueAttributes` (0x1c7819c54) -> the VC's `_updateContinuousExposeStripTonguePresence` -> `SBContinuousExposeStripTongueView` (1.9).
**PORTABILITY: PORTABLE as a class; the flow is PARTIAL** (VC methods that emit it are new; see 1.9).

### 1.9 SBContinuousExposeStripTongueView  (NEW UIView; class object 0x1de239e78)

The "edge protect tongue" that appears at the strip edge of the screen (a small pill with a chevron, same look as the slide-over tongue: it re-uses the image
`SlideOverTongueMask`). `UIView` subclass, delegate protocol `SBContinuousExposeStripTongueViewDelegate` (`continuousExposeStripTongueViewTapped:`,
`continuousExposeStripTongueView:didFinishAnimatingToState:`). Ivars: `_tongueContainerView` +0x1b0, `_chevronImageView` +0x1b8, `_tongueMaskView` +0x1c0,
`_backdropView` +0x1c8 (`_UIBackdropView`), `_tapGestureRecognizer` +0x1d0, `_bitmapMaskSize` (CGSize) +0x1d8, `_animating` (BOOL) +0x1e8, `_delegate` (weak) +0x1f0,
`_attributes` (struct {unsigned long long state; unsigned long long direction;}) +0x1f8.
Attributes: `SBSwitcherContinuousExposeStripTongueAttributes {state, direction}`; `_SBSwitcherContinuousExposeStripTongueAttributesNone()` = {0,0},
`...Make(state, direction)`. state: 0 none, 1 collapsed (horizontally squashed: transform scale(0,1) on backdrop/mask/chevron), 2 expanded (chevron alpha 1; transform identity).
direction: 1 = strip on the leading (left) edge, 2 = right edge (UNSURE naming; behaviour decoded below).

```objc
- (instancetype)initWithFrame:(CGRect)frame {                                         // 0x1c797196c
    self = [super initWithFrame:frame];
    if (self) {
        _attributes = (struct){0, 0};
        UIImage *mask = [UIImage imageNamed:@"SlideOverTongueMask"];                  // SpringBoard asset catalog image, exists in 16.0
        _bitmapMaskSize = [mask size];
        _tongueContainerView = [[UIView alloc] initWithFrame:(CGRect){0, 0, _bitmapMaskSize}];
        _tongueContainerView.layer.anchorPoint = CGPointMake(1.0, 0.5);
        [self addSubview:_tongueContainerView];
        _backdropView = [[_UIBackdropView alloc] initWithPrivateStyle:-2];            // 0xfffffffffffffffe
        [[_backdropView inputSettings] setBlurRadius:0];  [[_backdropView inputSettings] setScale:1.0];  [[_backdropView inputSettings] setBackdropVisible:YES];
        [_backdropView setGroupName:@"SBContinuousExposeStripTongueBackdropName"];
        [_tongueContainerView addSubview:_backdropView];
        _tongueMaskView = [[UIImageView alloc] initWithImage:mask];
        _tongueMaskView.contentMode = UIViewContentModeScaleToFill;                    // 0
        _tongueMaskView.layer.compositingFilter = kCAFilterDestOut;
        [_tongueContainerView addSubview:_tongueMaskView];
        UIImage *chevron = [UIImage systemImageNamed:@"chevron.compact.left"
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:44.0]];    // mov x8,#0x4046000000000000 -> double 44.0
        _chevronImageView = [[UIImageView alloc] initWithImage:chevron];
        _chevronImageView.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;   // 3
        _chevronImageView.tintColor = [UIColor blackColor];
        CAFilter *f = [CAFilter filterWithType:kCAFilterVibrantColorMatrix];
        [f setValue:[NSValue valueWithCAColorMatrix:M] forKey:@"inputColorMatrix"];      // M below
        _chevronImageView.layer.filters = @[ f ];
        [_tongueContainerView addSubview:_chevronImageView];
        _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_handleTap:)];
        [_tongueContainerView addGestureRecognizer:_tapGestureRecognizer];
        self.isAccessibilityElement = YES;  self.accessibilityIdentifier = @"continuous-expose-strip-tongue";
    }
    return self;
}
// CAColorMatrix M (20 floats, row-major m11..m45, from 0x1c7a93930):
//   { 1.37625, -0.734516, -0.141733, 0, 0.5,   -0.373512, 1.016302, -0.142790, 0, 0.5,   -0.374569, -0.732931, 1.6075, 0, 0.5,   0,0,0,1,0 }
```

```objc
- (void)setAttributes:(SBSwitcherContinuousExposeStripTongueAttributes)attrs animated:(BOOL)animated {     // 0x1c7971d54
    unsigned long long oldState = _attributes.state;
    _attributes = attrs;
    SBFloatingSwitcherSettings *fs = [[SBAppSwitcherDomain rootSettings] floatingSwitcherSettings];        // 16.0 has it
    if (oldState != attrs.state) {
        id settings; long long mode;
        if (animated) { settings = (attrs.state == 1) ? [fs tongueExpandedToCollapsedAnimationSettings] : [fs tongueCollapsedToExpandedAnimationSettings]; mode = 3; }
        else          { settings = nil; mode = 2; }
        _animating = YES;
        [UIView sb_animateWithSettings:settings mode:mode animations:^{            // block 0x1c7971f1c
            [weakSelf _updateSubviewLayoutForCollapsedOrExpandedState]; [weakSelf _updateSubviewOpacityForCollapsedOrExpandedState];   // UNSURE: 2nd call cut by my trace; opacity is the only other helper
        } completion:^(BOOL finished) {                                            // block 0x1c7971f58
            if (!finished) return;
            SBContinuousExposeStripTongueView *v = weakSelf; if (!v) return;
            v->_animating = NO;
            [[v delegate] continuousExposeStripTongueView:v didFinishAnimatingToState:v->_attributes.state];
        }];
    }
}
- (void)layoutSubviews { [super layoutSubviews]; [self _updateContainerPosition]; [self _updateContainerTransform]; [self _updateSubviewLayoutForCollapsedOrExpandedState]; }   // 0x1c7971fe8
- (void)_updateContainerPosition {                                                  // 0x1c7972044
    CGRect b = self.bounds;  _tongueContainerView.center = CGPointMake(_attributes.direction == 1 ? 0 : b.size.width, b.size.height * 0.5);
}
- (void)_updateContainerTransform {                                                 // 0x1c79720a8
    _tongueContainerView.transform = (_attributes.direction == 2) ? CGAffineTransformIdentity : CGAffineTransformMakeScale(-1, 1);
}
- (void)_updateSubviewLayoutForCollapsedOrExpandedState {                           // 0x1c7972144
    CGAffineTransform t = (_attributes.state == 1) ? CGAffineTransformMakeScale(0, 1) : CGAffineTransformIdentity;
    _backdropView.transform = _tongueMaskView.transform = _chevronImageView.transform = t;
    CGFloat cx = (_attributes.state == 1) ? _bitmapMaskSize.width : _bitmapMaskSize.width * 0.5;
    CGFloat cy = floor(_bitmapMaskSize.height * 0.5);
    _backdropView.center = _tongueMaskView.center = _chevronImageView.center = CGPointMake(cx, cy);
}
- (void)_updateSubviewOpacityForCollapsedOrExpandedState { _chevronImageView.alpha = (_attributes.state == 2) ? 1.0 : 0.0; }              // 0x1c7972298
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { return [_tongueContainerView pointInside:[self convertPoint:p toView:_tongueContainerView] withEvent:e]; }   // 0x1c79722c8
- (void)_handleTap:(UITapGestureRecognizer *)tap { [[self delegate] continuousExposeStripTongueViewTapped:self]; }                          // 0x1c7972340
// delegate (weak) 0x1c7972398/0x1c79723cc; attributes 0x1c79723e0; isAnimating 0x1c79723f4
```
Hosting (VC, 16.2): `_updateContinuousExposeStripTonguePresence` (0x1c7459648): `attrs = [_rootModifier continuousExposeStripTongueAttributes]`; if state == 2 and no view: create
the view (delegate = VC, subview of `_contentView`), a capture-only `_UIBackdropView` (`_continuousExposeStripTongueCaptureOnlyBackdropView`, group
`SBContinuousExposeStripTongueBackdropName`, `CABackdropLayer.captureOnly = NO`) and an `SBSwitcherAccessoryLayoutElement initWithType:6` (`_continuousExposeStripTongueBackdropCaptureLayoutElement`),
`_ensureSubviewOrdering`, `_layoutContinuousExposeStripTongueAnimated:completion:` (0x1c744306c); set attributes `{1, direction}` non-animated, then `attrs` animated. When the state
goes back to 0 the view is torn down after `isAnimating` ends. A tap -> `continuousExposeStripTongueViewTapped:` (0x1c745f818) ORs bit 1 into
`_continuousExposeStripsPresentationOptions` (+0x640), sends `SBUpdateLayoutSwitcherEventResponse initWithOptions:0x1e updateMode:3` through `_handleEventResponse:` and dismisses the tongue.
**PORTABILITY: PARTIAL.** The view is a pure UIKit/private-UIKit class (all APIs exist in 16.0; `SlideOverTongueMask`, `floatingSwitcherSettings.tongue*AnimationSettings` exist in 16.0, shown by the 16.0
slide-over tongue) and can be created at run time as a `UIView` subclass with `objc_allocateClassPair` (all its state in ivars added with `class_addIvar`). The VC side cannot be
reproduced faithfully: `SBFluidSwitcherViewController` would need 4 new ivars (impossible to add to an existing class; use associated objects), a new accessory layout element type 6,
subview ordering support, and root-modifier attributes (`continuousExposeStripTongueAttributes` is a query not in the 16.0 protocol). Recommended: build the view class (hooks 1.9) and host it from a
`%hook SBFluidSwitcherViewController` using associated objects only if the strip-reveal feature (4.x) is ported; otherwise skip.

### 1.10 SBSetInterfaceOrientationFromUserResizingEventResponse  (NEW; response type 38; class object 0x1de236958)

Ivars `_displayItem` +0x28, `_desiredOrientation` (long long) +0x30. `initWithDisplayItem:desiredContentOrientation:` (0x1c7818020), `type` -> 38 (0x1c78180ac), getters.
Producer: `-[SBItemResizeGestureSwitcherModifier _responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:]` (0x1c76bed98; the response is created at 0x1c76bf0ac): when
`[[self layoutRestrictionInfoForItem:item] layoutRestrictions] & 0xA) == 0x2` (16.2-only context `layoutRestrictionInfoForItem:`), orientation = (size.width > size.height) ? 3 (landscape) : 1 (portrait)
(`csinc` idiom; UNSURE about the exact UIInterfaceOrientation constants) and the new response wraps the usual perform-transition response as a child (`[orientResponse addChildResponse:performTransition]`).
Consumer: `-[SBFluidSwitcherViewController _performSetInterfaceOrientationFromUserResizingResponse:]` (0x1c745ec9c):
```objc
SBDisplayItem *item = [response displayItem]; long long o = [response desiredOrientation];
if (item && o) { id d = [self delegate]; if ([d respondsToSelector:@selector(switcherContentController:setInterfaceOrientationFromUserResizing:forDisplayItem:)])
        [d switcherContentController:self setInterfaceOrientationFromUserResizing:o forDisplayItem:item]; }
```
Effect: while the user resizes a window that is restricted to one orientation (e.g. apps that only support portrait or landscape), the app's interface orientation
follows the window's aspect ratio (landscape when wider than tall). Confidence medium.
**PORTABILITY: PARTIAL.** Response class and `_performEventResponse:` hook (type 38) are trivial, but the delegate selector
`switcherContentController:setInterfaceOrientationFromUserResizing:forDisplayItem:` (implemented by `SBSwitcherController`/`SBSceneManager` side in 16.2) and the producer's `layoutRestrictionInfoForItem:` do not exist in 16.0 => no consumer. NOT useful on its own; port only together with an
orientation-lock backport (out of group 1b).

---------------------------------------------------------------------------------------------------
