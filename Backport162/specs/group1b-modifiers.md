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

### 1.3 SBInvalidateContinuousExposeIdentifiersEventResponse  (NEW; response type 34 in 16.2; class object 0x1de231228)

Superclass `SBSwitcherModifierEventResponse`. Ivars `_animated` (BOOL) +0x28, `_transitioningFromAppLayout` +0x30, `_transitioningToAppLayout` +0x38 (strong).
`initWithTransitioningFromAppLayout:transitioningToAppLayout:animated:` (0x1c760b674: super init, store 3 values), `type` -> 0x22 = 34 (0x1c760b72c), getters (0x1c760b734/44/54).
Consumer `-[SBFluidSwitcherViewController _performInvalidateContinuousExposeIdentifiersResponse:]` (0x1c745ec0c):
`[self _updateContinuousExposeIdentifiersTransitioningFromAppLayout:[r transitioningFromAppLayout] toAppLayout:[r transitioningToAppLayout] animated:[r animated]]`
(the VC method exists in 16.0 @0x1c5fde0d0; its 16.2 body @0x1c7457450 now rebuilds the `InSwitcher`/`InStrip` lists - VC group).
Producers: `SBContinuousExposeRootSwitcherModifier -handleEvent:` (0x1c7819254) and `SBContinuousExposeWindowDragDestinationSwitcherModifier -handleGestureEvent:` (0x1c74f3cc0).

Root `handleEvent:` (16.2) reconstructed (X = the phase named in the table, "or not animated" = the same code also runs for non-animated events):
```objc
- (id)handleEvent:(SBSwitcherModifierEvent *)event {                                     // 0x1c7819254
    id invalidate = nil;
    if ([event isTransitionEvent]) {
        SBAppLayout *to = [event toAppLayout], *from = [event fromAppLayout]; BOOL animated = [event isAnimated];
        // run only when  phase == X  ||  !animated   (the event is seen once per phase; this picks exactly one of them)
        if      (to && from  && ([event phase] == 2 || !animated)) { _effectiveAppLayoutOnStage = to;  invalidate = [[SBInvalidate... alloc] initWithTransitioningFromAppLayout:from transitioningToAppLayout:to animated:animated]; }
        else if (!to && from && ([event phase] == 3 || !animated)) { _effectiveAppLayoutOnStage = nil; invalidate = [... from:from to:nil animated:animated]; }
        else if (to && !from && ([event phase] == 1 || !animated)) { _effectiveAppLayoutOnStage = to;  invalidate = [... from:nil to:to animated:animated]; }
        else if (!to && !from && ([event phase] == 1 || !animated)) { _effectiveAppLayoutOnStage = nil; invalidate = [... from:nil to:nil animated:animated]; }
    }
    return SBAppendSwitcherModifierResponse(invalidate, [super handleEvent:event]);
}
```
16.0: the identical `_updateContinuousExposeIdentifiers...` call was made inline by `-[SBFluidSwitcherViewController performTransitionWithContext:animated:completion:]` blocks
(`_block_invoke` @0x1c5fc50c4 and `_block_invoke_9` @0x1c5fc5d9c) and by `_rebuildCachedAdjustedAppLayouts` (0x1c5fde084). In 16.2 only `_rebuildCachedAdjustedAppLayouts` (0x1c7457404) and the response remain.
The new `_effectiveAppLayoutOnStage` ivar (+0x68) is what `appLayoutOnContinuousExposeStage` (0x1c7819c3c) returns.
Effect: the identifier lists are refreshed from the modifier layer at the right transition phase and also during drags (drag destination), instead of the VC guessing from the transition blocks. Behaviour fix: stale identifier lists after multi-phase transitions (confidence medium).
**PORTABILITY: PARTIAL.** Class trivial (type: pick 40, 34 is taken in 16.0). Consumer = `_performEventResponse:` hook (type 40) calling the 16.0 VC method (exists). Do NOT emit it from a Root `handleEvent:` hook on 16.0 (the 16.0 VC already calls the method for transitions: double invalidation); its only needed producer is the drag-destination port (4.x) while a window is dragged.

---------------------------------------------------------------------------------------------------

## 2. Priority 2: transitions

All are `SBTransitionSwitcherModifier` subclasses (so they get `transitionID`, `transitionWillBegin`, `transitionWillUpdate`, `isPreparingLayout/isUpdatingLayout`, the event's from/to data and `[super X]` queries
that resolve through the transition chain). Phase/timer pattern used by several: a `SBTimerEventSwitcherEventResponse initWithDelay:validator:reason:` response is returned from
`transitionWillBegin`/`WillUpdate`; the reason string is `@"<ClassConst>:<UUID>"` so concurrent instances do not collide; `handleTimerEvent:` compares the reason with `isEqualToString:` and
advances `_animationPhase`, returning `SBUpdateLayoutSwitcherEventResponse initWithOptions:updateMode:` (updateMode 2 = apply without animation (UNSURE), 3 = animate).
Extra: `SBSwitcherModifierEventResponse responseByAppendingResponse:toResponse:` is the class-method form of `SBAppendSwitcherModifierResponse`.

### 2.0 Where the transitions are created (wiring)

* `SBContinuousExposeAppToAppModifier -didMoveToParentModifier:` (16.2 @0x1c759598c; 16.0 @0x1c610b99c) - see 4.8. 16.2 creates `FullScreenToStrip` or `...Crossblur`, 16.0 created the old `SBContinuousExposeCrossblurModifier`.
* `SBContinuousExposeRootSwitcherModifier -transitionModifierForMainTransitionEvent:` (0x1c781859c): `SwitcherToAppExpose` (2.3) for 2->2 transitions where the App Expose bundle id changes.
* `SBiPadOSPlatformSwitcherModifier -handleTransitionEvent:` (0x1c75a6fac): `SBiPadOSWindowModeChangeTransitionModifier` (2.4).
* `SBContinuousExposeAppDragAndDropGestureSwitcherModifier -handleTransitionEvent:` (0x1c7638bc4): `DragAndDropToApp` (2.5).
* `SBContinuousExposePeekSwitcherModifier -handleTransitionEvent:` (0x1c78e54e4): `PeekTransition` (2.6).
* Transition-event flags that the creators read are NEW ivars on `SBTransitionSwitcherModifierEvent` (BOOLs at +0x38 `_iPadOSWindowingModeChangeEvent`, +0x39 `_commandTabTransition`, +0x3a `_launchingFromDockTransition`) set by
  `-[SBMainSwitcherControllerCoordinator transitionEventForContext:identifier:phase:animated:]` (16.2 @0x1c76d3e1c, setters at 0x1c76d485c/74/a4) from the transition request source:
  `source == 0x40` -> windowing-mode change, `== 0x10` -> command-tab, `== 0x18 || 0x19` -> launching from dock (`0x41` configuration change and `0x3e` move displays already existed in 16.0: same coordinator method @0x1c6241040+).
  PORT: add the three flags as associated-object properties (`isiPadOSWindowingModeChangeEvent`, `isCommandTabTransition`, `isLaunchingFromDockTransition` + setters) on `SBTransitionSwitcherModifierEvent` and set them from a `%hook` of the coordinator method (PORTABLE; read `source` through the request exactly as the original does).

### 2.1 SBContinuousExposeFullScreenToStripTransitionSwitcherModifier  (NEW; class object 0x1de230058)

16.0: **new** (16.0 used `SBContinuousExposeCrossblurModifier` for every app-to-app change that left the target outside the switcher bounds). Ivars: `_animationPhase` +0x88 (0..2), `_outgoingAppLayout` +0x90, `_timerReason` +0x98.
Role: the app layout that LEAVES the stage (full-screen app or window group) flies into its strip slot. Everything not equal to `_outgoingAppLayout` is answered by `[super]`.
```objc
- (id)initWithTransitionID:(id)tid outgoingAppLayout:(SBAppLayout *)out {                    // 0x1c758a898
    self = [super initWithTransitionID:tid];
    if (self) { _outgoingAppLayout = out; _animationPhase = 0;
        _timerReason = [NSString stringWithFormat:@"%@:%@", @"SBContinuousExposeFullScreenToStripTransitionSwitcherModifierTimerEventReason", [[NSUUID UUID] UUIDString]]; }
    return self;
}
- (id)transitionWillBegin {                                                                  // 0x1c758a994
    id r = [super transitionWillBegin];
    if (_animationPhase == 0) {            // two identical 0.14 s timers (sic): they fire back to back and drive phase 0->1->2
        r = [SBSwitcherModifierEventResponse responseByAppendingResponse:[[SBTimerEventSwitcherEventResponse alloc] initWithDelay:0.14 validator:nil reason:_timerReason] toResponse:r];
        r = [SBSwitcherModifierEventResponse responseByAppendingResponse:[[SBTimerEventSwitcherEventResponse alloc] initWithDelay:0.14 validator:nil reason:_timerReason] toResponse:r];
    }
    return r;
}
- (id)handleTimerEvent:(id)event {                                                           // 0x1c758aab4
    id r = [super handleTimerEvent:event];
    if ([[event reason] isEqualToString:_timerReason] && (_animationPhase == 0 || _animationPhase == 1)) {
        long long mode = (_animationPhase == 0) ? 2 : 3;  _animationPhase = (_animationPhase == 0) ? 1 : 2;
        r = [SBSwitcherModifierEventResponse responseByAppendingResponse:[[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:0x1e updateMode:mode] toResponse:r];
    }
    return r;
}
// per-layout queries; "O" = [_outgoingAppLayout isEqual:[[self appLayouts] objectAtIndex:index]] (or the passed layout)
- (CGRect)frameForIndex:(NSUInteger)i {                                                      // 0x1c758abd4
    if (!O) return [super frameForIndex:i];
    if (_animationPhase == 0) return [[self _overlappingModelForAppLayout:layout] boundingBox];      // start on the stage
    CGRect f = [super frameForIndex:i];
    if (_animationPhase == 1) return CGRectMake(f.origin.x * 0.1, f.origin.y * 1.065, f.size.width, f.size.height);  // staging position
    return f;                                                                                          // phase 2: final strip frame
}
- (CGRect)frameForIconOverlayInAppLayout:(SBAppLayout *)l { return O ? [[self _overlappingModelForAppLayout:l] boundingBox] : [super frameForIconOverlayInAppLayout:l]; }   // 0x1c758ad24
- (CGRect)adjustedSpaceAccessoryViewFrame:(CGRect)f forAppLayout:(id)l { return f; }          // 0x1c758ad20 (no adjustment)
- (UIRectCornerRadii)cornerRadiiForIndex:(NSUInteger)i {                                     // 0x1c758ae04
    if (O && _animationPhase == 0) return SBRectCornerRadiiForRadius([[self chamoisLayoutAttributes] stageCornerRaddii] / [self scaleForIndex:i]);
    return [super cornerRadiiForIndex:i];
}
- (CGPoint)anchorPointForIndex:(NSUInteger)i { return (O && _animationPhase < 2) ? CGPointMake(0.5, 0.5) : [super anchorPointForIndex:i]; }       // 0x1c758af18
- (double)perspectiveAngleForAppLayout:(id)l  { return (O && _animationPhase == 0) ? 0.0 : [super perspectiveAngleForAppLayout:l]; }                // 0x1c758afdc
- (double)scaleForIndex:(NSUInteger)i {                                                      // 0x1c758b070
    if (O) { if (_animationPhase == 0) return [[[self switcherSettings] animationSettings] crossblurDosidoSmallScale]; if (_animationPhase == 1) return 0.32; }
    return [super scaleForIndex:i];
}
- (double)opacityForLayoutRole:(long long)r inAppLayout:(id)l atIndex:(NSUInteger)i { return (O && _animationPhase < 2) ? 0.0 : [super ...]; }   // 0x1c758b164: hidden until the final phase
- (double)titleAndIconOpacityForIndex:(NSUInteger)i { return (O && _animationPhase < 2) ? 0.0 : [super ...]; }                                      // 0x1c758b210
- (BOOL)shouldAllowGroupOpacityForAppLayout:(id)l { return SBFIsChamoisFullScreenToStripGroupOpacityAvailable() ? O : [super ...]; }   // 0x1c758b2c8 (flag defaults to YES in 16.2, see below)
- (id)animationAttributesForLayoutElement:(id)el {                                           // 0x1c758b344
    id a = [[super animationAttributesForLayoutElement:el] mutableCopy];
    id ls = [[[[self switcherSettings] animationSettings] crossblurDosidoSettings] copy]; ls.response = 0.4; ls.dampingRatio = 1.0;
    a.layoutUpdateMode = 3; a.layoutSettings = ls;
    id os = [[[[self switcherSettings] animationSettings] crossblurDosidoSettings] copy]; os.response = 0.15; a.opacitySettings = os;
    return a;
}
- (SBChamoisOverlappingModel *)_overlappingModelForAppLayout:(SBAppLayout *)l {              // 0x1c758b490
    return [[self displayItemLayoutAttributesCalculator] overlappingModelForAppLayout:[self appLayoutContainingAppLayout:l]
              containerOrientation:[self switcherInterfaceOrientation] chamoisLayoutAttributes:[self chamoisLayoutAttributes]
              floatingDockHeight:[self floatingDockHeight] screenScale:[self screenScale] bounds:[self containerViewBounds]
              prefersStripHidden:[self prefersStripHidden] prefersDockHidden:[self prefersDockHidden]];
}
```
Feature flag: `_SBFIsChamoisFullScreenToStripGroupOpacityAvailable` (SpringBoardFoundation @0x18ee09a10, os-feature "SBChamoisFullScreenToStripGroupOpacity"; default function @0x18ee09a6c returns YES) - treat as YES.
Effect: the outgoing window no longer pops: it is laid out invisible at its stage frame (phase 0, small dosido scale), repositioned to a staging spot (0.1x, 1.065y at scale 0.32, still invisible), then animated to its real strip slot while fading in (response 0.4 / damping 1.0; opacity response 0.15). Replaces the 16.0 behaviour where the outgoing layout simply cross-faded (`SBContinuousExposeCrossblurModifier`). Confidence high on the mechanics, medium on the intent.
**PORTABILITY: PARTIAL.** Pure class, all queries are 16.0 chain queries except `shouldAllowGroupOpacityForAppLayout:` (16.2-only query; skip it: group opacity is then not applied, cosmetic) and `-overlappingModelForAppLayout:containerOrientation:...` / `chamoisLayoutAttributes.stageCornerRaddii`/`stripTiltAngle`, `crossblurDosido*` settings which all exist in 16.0 (selectors verified). Needs the creator (4.8, `AppToApp didMoveToParentModifier:` hook) and is only correct together with the 16.2 strip/stage modifiers' frames (the `[super frameForIndex:]` must return the strip slot). Code: hooks 2.1.

### 2.2 SBContinuousExposeFullScreenToStripCrossblurTransitionSwitcherModifier  (NEW; class object 0x1de237b28)

16.0 predecessor: `SBContinuousExposeCrossblurModifier` (initWithTransitionID:fromAppLayout:toAppLayout:, 16 methods, fixed 2-phase). Used (see AppToApp 4.8) for command-tab and dock launches. Ivars: `_toAppLayout` +0x88, `_fromAppLayout` +0x90, `_animationPhase` +0x98 (0..4),
`_timerReason` +0xa0, `_toAppLayoutInitialFrame` (CGRect) +0xa8, `_toAppLayoutInitialScale` +0xc8, `_toAppLayoutInitialCornerRadius` (UIRectCornerRadii) +0xd0.
```objc
- (instancetype)initWithTransitionID:(id)tid toAppLayout:(SBAppLayout *)to fromAppLayout:(SBAppLayout *)from {   // 0x1c788f894 (note the argument order)
    self = [super initWithTransitionID:tid]; _toAppLayout = to; _fromAppLayout = from; _animationPhase = 0;
    _timerReason = [NSString stringWithFormat:@"%@:%@", @"SBContinuousExposeFullScreenToStripCrossblurTransitionSwitcherModifierTimerEventReason", [[NSUUID UUID] UUIDString]];
    return self;
}
- (void)didMoveToParentModifier:(id)parent {                                                // 0x1c788f9b4
    [super didMoveToParentModifier:parent];
    if (parent) {
        NSUInteger idx = [[self appLayouts] indexOfObject:_toAppLayout];
        NSAssert(idx != NSNotFound, @"We must know about _toAppLayout");                       // line 0x59
        _toAppLayoutInitialFrame = [super frameForIndex:idx]; _toAppLayoutInitialScale = [super scaleForIndex:idx]; _toAppLayoutInitialCornerRadius = [super cornerRadiiForIndex:idx];
    }
}
- (id)transitionWillUpdate { id r = [super transitionWillUpdate]; if (_animationPhase == 0) r = Append(timer(0.045, _timerReason), r); return r; }      // 0x1c788fb0c
- (id)handleTimerEvent:(id)event {                                                          // 0x1c788fbd8: phase machine
    id r = [super handleTimerEvent:event];
    if ([[event reason] isEqualToString:_timerReason]) switch (_animationPhase) {
        case 0: _animationPhase = 1; r = [self _updateLayoutWithAnimationUpdateMode:2 appendResponse:Append(timer(0.01), r)]; break;
        case 1: _animationPhase = 2; r = [self _updateLayoutWithAnimationUpdateMode:3 appendResponse:Append(timer(0.25), r)]; break;
        case 2: _animationPhase = 3; r = [self _updateLayoutWithAnimationUpdateMode:2 appendResponse:Append(timer(0.01), r)]; break;
        case 3: _animationPhase = 4; r = [self _updateLayoutWithAnimationUpdateMode:3 appendResponse:r]; break;
    }
    return r;
}
- (id)_updateLayoutWithAnimationUpdateMode:(long long)m appendResponse:(id)r { return Append([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:0xc updateMode:m], r); }   // 0x1c788fdc0
// F = [_fromAppLayout isEqual:layout],  T = [_toAppLayout isEqual:layout]
- frameForIndex:     F && phase<=2 -> [[self overlappingModelForAppLayout:layout] boundingBox];  T && phase==0 -> _toAppLayoutInitialFrame;  else [super]            // 0x1c788fe40
- scaleForIndex:     F: phase<=2 -> crossblurDosidoLargeScale; phase==3 -> [super]-0.02; else [super].   T: phase==0 -> _toAppLayoutInitialScale; phase==1 -> crossblurDosidoSmallScale; else [super]   // 0x1c788ff84
- opacityForLayoutRole:inAppLayout:atIndex:  F: phase<4 -> 0.0 else [super];  T: phase==0 -> 0.0, phase==1 -> 0.1, else [super]                                   // 0x1c7890104
- perspectiveAngleForAppLayout:  F: phase<3 -> 0.0 else [super];  T: phase==0 -> stripTiltAngle (negated when UIApp.userInterfaceLayoutDirection==RTL) else [super]      // 0x1c78901f4
- anchorPointForIndex:  F: phase<3 -> (0.5,0.5);  T: phase==0 -> (RTL ? (0.5, 0.0) : (0.0, 0.5))  /* sic: RTL result looks like a 16.2 bug */  else [super]              // 0x1c78902f8
- cornerRadiiForIndex:  F: phase<=2 -> SBRectCornerRadiiForRadius(stageCornerRaddii / scaleForIndex);  T: phase==0 -> _toAppLayoutInitialCornerRadius else [super]  // 0x1c789040c
- titleAndIconOpacityForIndex:  F: phase<3 -> 0.0;  T: phase<2 -> 0.0;  else [super]                                                                                      // 0x1c7890564
- shouldAllowGroupOpacityForAppLayout:  flag ? F : [super]                                                                                                              // 0x1c789064c
- animationAttributesForLayoutElement: a = [[super ..] mutableCopy]; s = [crossblurDosidoSettings copy]; s.response=0.45; s.dampingRatio=0.92; a.layoutUpdateMode=3; a.layoutSettings = a.opacitySettings = s   // 0x1c78906c8
```
Effect: dock/command-tab launches cross-blur the outgoing layout (large scale, fading out after phase 3) and the incoming one (starts at its strip frame/scale/tilt at opacity 0, grows to the stage) in 4 timed steps (0.045/0.01/0.25/0.01 s). 16.0's version was a single-step crossblur. Confidence high on structure.
**PORTABILITY: PARTIAL** (same as 2.1: needs the AppToApp creator, `command-tab`/`dock launch` event flags (2.0), and drops the 16.2-only group-opacity query).

### 2.3 SBContinuousExposeSwitcherToAppExposeSwitcherModifier  (NEW; class object 0x1de235788)

16.0: **new** (switcher <-> App Expose 2->2 transitions fell through to the generic grid transition). Ivars `_appExposeModifier` +0x88 (SBAppExposeContinuousExposeSwitcherModifier), `_timerReason` +0x90, `_appLayoutsVisibleBeforeTransition` +0x98 (NSSet), `_appExposeBundleID` +0xa0, `_direction` +0xa8 (0 = ToAppExpose, nonzero = ToSwitcher).
Creator (Root `transitionModifierForMainTransitionEvent:`, 0x1c7818d44): for a 2->2 transition whose from/to App Expose bundle ids differ:
`bid = toBID ?: fromBID; dir = (toBID == nil); appExpose = SafeCast([[self floorModifierForTransitionEvent:e] copy], SBAppExposeContinuousExposeSwitcherModifier); m = [[SwitcherToAppExpose alloc] initWithTransitionID:tid appExposeBundleID:bid direction:dir appExposeModifier:appExpose]`.
```objc
- (instancetype)initWithTransitionID:(id)tid appExposeBundleID:(NSString *)bid direction:(NSUInteger)d appExposeModifier:(id)m {     // 0x1c77b5f94
    self = [super initWithTransitionID:tid];
    NSAssert(bid, @"appExposeBundleID"); NSAssert(m, @"appExposeModifier");                // lines 0x25, 0x26
    _appExposeBundleID = [bid copy]; _direction = d; _appExposeModifier = m;
    _timerReason = [NSString stringWithFormat:@"SBContinuousExposeSwitcherToAppExposeSwitcherModifier:%@", [[NSUUID UUID] UUIDString]];
    [self addChildModifier:[[SBRouteToAppExposeSwitcherModifier alloc] initWithTransitionID:tid appExposeModifier:[_appExposeModifier copy]]];   // default level
    return self;
}
- (id)transitionWillBegin {                                                                  // 0x1c77b62b0
    id r = [super transitionWillBegin];
    _appLayoutsVisibleBeforeTransition = [super visibleAppLayouts];
    [self addChildModifier:_appExposeModifier atLevel:1 key:nil];
    r = Append([SBInvalidateAdjustedAppLayoutsSwitcherEventResponse new], r);
    return Append([[SBTimerEventSwitcherEventResponse alloc] initWithDelay:0 validator:nil reason:_timerReason], r);
}
- (id)handleTimerEvent:(id)event {                                                           // 0x1c77b63e8
    id r = [super handleTimerEvent:event];
    if ([[event reason] isEqualToString:_timerReason]) {
        SBAppLayout *first = [[self appLayoutsForContinuousExposeIdentifier:[[self continuousExposeIdentifiersInSwitcher] firstObject]] firstObject];   // 16.2-only context
        if (first) { r = Append([[SBScrollToAppLayoutSwitcherEventResponse alloc] initWithAppLayout:first alignment:0 animated:NO], r);
                     r = Append([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:2 updateMode:2], r); }
    }
    return r;
}
- (id)transitionWillUpdate { [self removeChildModifier:_appExposeModifier]; _appExposeModifier = nil; return [super transitionWillUpdate]; }   // 0x1c77b6578
- (NSSet *)visibleAppLayouts { return [[super visibleAppLayouts] setByAddingObjectsFromSet:_appLayoutsVisibleBeforeTransition]; }               // 0x1c77b66b8
- (CGRect)frameForIndex:(NSUInteger)i {                                                      // 0x1c77b65ec
    CGRect f = [super frameForIndex:i];
    if (_appExposeModifier) f = CGRectOffset(f, [UIApp isRTLEnabled] ? [self switcherViewBounds].size.width : -[self switcherViewBounds].size.width, 0);   // slide the switcher content off to the side
    return f;
}
- (id)animationAttributesForLayoutElement:(id)el { a = [[super ..] mutableCopy]; a.layoutSettings = [[[self switcherSettings] animationSettings] toggleAppSwitcherSettings]; return a; }   // 0x1c77b6734
```
Effect: the App Expose layer (child modifier) slides in over the switcher (and vice versa) with the toggle-app-switcher spring, keeping the previously visible layouts alive for the duration. Confidence medium (intent), high (mechanics).
**PORTABILITY: PARTIAL.** `SBRouteToAppExposeSwitcherModifier` and `SBAppExposeContinuousExposeSwitcherModifier` exist in 16.0 (selector `initWithTransitionID:appExposeModifier:` to verify before use), but 16.0's Root has no creator for this case and `continuousExposeIdentifiersInSwitcher` is 16.2-only (use 16.0 `continuousExposeIdentifiers`). Worth porting only with the App Expose backport.

### 2.4 SBiPadOSWindowModeChangeTransitionModifier  (NEW; class object 0x1de234478)

Ivars `_fromAppLayout` +0x88, `_toAppLayout` +0x90. `initWithTransitionID:fromAppLayout:toAppLayout:` (0x1c77311c4; asserts non-nil from/to, lines 0x10/0x11).
```objc
- (BOOL)isLayoutRoleMatchMovedToScene:(long long)r inAppLayout:(SBAppLayout *)l {                   // 0x1c7731318
    return [_fromAppLayout containsAnyItemFromAppLayout:l] || [_toAppLayout containsAnyItemFromAppLayout:l] ? YES : [super isLayoutRoleMatchMovedToScene:r inAppLayout:l];
}   // content "match-move" so the scene does not jump between windowing modes
- (NSUInteger)maskedCornersForIndex:(NSUInteger)i {                                                  // 0x1c77313bc
    SBAppLayout *l = [[self appLayouts] objectAtIndex:i];  NSUInteger m = [super maskedCornersForIndex:i];
    if ([_toAppLayout isOrContainsAppLayout:l] && (![self isChamoisWindowingUIEnabled] || [self appLayoutContainsAnUnoccludedMaximizedDisplayItem:l])) m = 0;   // no corner masking while a maximized window changes mode
    return m;
}
```
Creator `-[SBiPadOSPlatformSwitcherModifier handleTransitionEvent:]` (16.2 @0x1c75a6fac, 16.0 @0x1c611cd74 exists): after `[super]`, `if ([event isiPadOSWindowingModeChangeEvent] && [event phase]==1 && [event isAnimated] && _currentUnlockedEnvironmentMode==3 && from && to) [self addChildModifier:[[SBiPadOSWindowModeChangeTransitionModifier alloc] initWithTransitionID:[event transitionID] fromAppLayout:from toAppLayout:to]];`
Effect: switching Stage Manager on/off (windowing mode change) no longer drops the corner mask/scene match-move mid-animation (visual glitch fix; confidence medium).
**PORTABILITY: PORTABLE** (new class, both queries are 16.0 chain queries; creator = `%hook SBiPadOSPlatformSwitcherModifier -handleTransitionEvent:` plus the event flag of 2.0; `_currentUnlockedEnvironmentMode` read by name via `class_getInstanceVariable`). Code: hooks 2.4.

### 2.5 SBContinuousExposeDragAndDropToAppTransitionSwitcherModifier  (NEW; class object 0x1de2333e8)

No ivars. Five overrides: `animationAttributesForLayoutElement:` (0x1c76e6360: mutable copy of super, `layoutSettings = [[switcherSettings medusaSettings] resizeAnimationSettings]`, `updateMode = 3`),
`appLayoutsToResignActive` -> empty dictionary `__NSDictionary0__struct` (0x1c76e6410: no app is resigned), `keyboardSuppressionMode` -> `[SBSwitcherKeyboardSuppressionMode suppressionModeNone]` (0x1c76e641c),
`asyncRenderingAttributesForAppLayout:` -> `SBSwitcherAsyncRenderingAttributesMake(NO, NO)` (0x1c76e6428), `shouldPerformCrossfadeForReduceMotion` -> NO (0x1c76e6434).
Creator: `SBContinuousExposeAppDragAndDropGestureSwitcherModifier -handleTransitionEvent:` (0x1c7638bc4), see 3.x. Effect: the transition that ends an app-icon drag-and-drop (dropping an app/icon onto the stage to open it as a window) uses the window-resize spring, keeps every app active and the keyboard unsuppressed, and never cross-fades (16.0 had no such transition: it used the generic one). Confidence medium.
**PORTABILITY: PORTABLE as a class** (all five are 16.0 queries); its creator (3.x, drag-and-drop gesture root) is new.

### 2.6 SBContinuousExposePeekTransitionModifier  (NEW; class object 0x1de2334d8)

16.0 counterpart: the peek was driven by `SBPeekHomeScreenContinuousExposeSwitcherModifier` (a home-screen floor modifier, see 4.x Root). Ivars `_fromFullScreenContinuousExposeModifier` +0x88, `_toFullScreenContinuousExposeModifier` +0x90, `_fromAppLayout` +0x98, `_toAppLayout` +0xa0, `_direction` +0xa8 (0 = peek PRESENTATION, created when a peek begins; 1 = peek DISMISSAL, stored in the peek modifier's `_dismissalTransitionModifier`; see 3.1).
`initWithTransitionID:fromAppLayout:toAppLayout:direction:` (0x1c76ed9e0; asserts fromAppLayout, line 0x18): `_fromFullScreenCEModifier = [[SBFullScreenContinuousExposeSwitcherModifier alloc] initWithFullScreenAppLayout:from]`; if `direction == 1 && to` also `_toFullScreenCEModifier = ... initWithFullScreenAppLayout:to`.
Overrides (all special-cased for direction 1 = dismissal only, phase >= 2; otherwise `[super]`): `visibleAppLayouts` adds `_fromAppLayout` (0x1c76edb5c); `frameForIndex:`/`frameForLayoutRole:inAppLayout:withBounds:`/`scaleForIndex:`/`scaleForLayoutRole:inAppLayout:` evaluate the layout through the matching full-screen CE modifier attached as a temporary child
(`performTransactionWithTemporaryChildModifier:usingBlock:`; blocks at 0x1c76edee8, 0x1c76edea0, 0x1c76ee510, 0x1c76ee1dc, 0x1c76ee198, 0x1c76ee6f0 - phase >= 2 only, using the *from* modifier for the from layout and the *to* modifier for the to layout) and
`frameForLayoutRole:` additionally calls `frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:` (16.2-only SBSwitcherModifier method) and offsets x by `+/-(4 * screenEdgePadding)` toward the screen centre; `topMostLayoutElements` moves the to-layout (the peeked window, filtered with
`appLayoutWithItemsPassingTest:`) to index 0 unless `fromAppLayout containsAllItemsFromAppLayout:to`; `isLayoutRoleMatchMovedToScene:` YES when to/from share items; `animationAttributesForLayoutElement:` = new `SBMutableSwitcherAnimationAttributes` with `updateMode = 3`, `layoutSettings = [[[switcherSettings] chamoisSettings] appToAppLayoutSettings]`.
Creator: `SBContinuousExposePeekSwitcherModifier -handleTransitionEvent:` (0x1c78e54e4, 3.1). UNSURE: the exact per-block geometry (kept as `[child frameForIndex:]` queries).
**PORTABILITY: NOT PORTABLE as a faithful class**: depends on the peek modifier family (3.x, new in 16.2) and the 16.2-only `frameForContinuousExposePeekingDisplayItem:...`. In 16.0 the peek is `SBPeekHomeScreenContinuousExposeSwitcherModifier`; leave 16.0's peek untouched. No code drafted.

---------------------------------------------------------------------------------------------------

## 4. Priority 4: CHANGED classes (wiring first)

Method-level diffs below were produced by diffing the call / selector / constant / ivar sequence of every logic-changed method (WORKLIST.md) between 16.0 and 16.2
(`mdiff.py`); the reconstructions are given where the change is behavioural. Pure ivar-offset shifts (16.2 inserted ivars earlier in the object) are not listed.

### 4.1 SBContinuousExposeRootSwitcherModifier  (superclass SBFullScreenFluidSwitcherRootSwitcherModifier; 9 logic-changed + 7 new methods)

Ivars: 16.0 `_currentAppLayout` +0x60; 16.2 adds `_effectiveAppLayoutOnStage` +0x68, `_isStripTonguePresented` (BOOL) +0x70, `_initialFloorModifierForContinuousExposeWindowDrag` +0x78.
Removed in 16.2 (strip ordering moved into the Full-Screen / Strip modifiers, 0.3): `_adjustedAppLayoutsForAppLayouts:`, `adjustedAppLayoutsForAppLayouts:`, `adjustedContinuousExposeIdentifiersForIdentifiers:`, `_continuousExposeIdentifiersInStripFromIdentifiers:ignoringAppLayoutOnStage:`, `appLayoutsForContinuousExposeIdentifier:`.

```objc
// ---- floor modifier factory for transitions: 16.2 0x1c78180e8 (16.0 0x1c6370db8)
- (SBSwitcherModifier *)floorModifierForTransitionEvent:(SBTransitionSwitcherModifierEvent *)e {
    if (!e) return [[SBHomeScreenContinuousExposeSwitcherModifier alloc] init];
    SBSwitcherModifier *floor = [self floorModifier];              // the floor currently installed (reused when it already fits)
    NSString *bid = [e toAppExposeBundleID]; SBAppLayout *toAL = [e toAppLayout];
    switch ([e toEnvironmentMode]) {
    case 1:  /* home */     return (floor && [floor isKindOfClass:[SBHomeScreenContinuousExposeSwitcherModifier class]]) ? floor : [[SBHomeScreenContinuousExposeSwitcherModifier alloc] init];
    case 2:  /* switcher */ if (!bid) return [self multitaskingModifier];                                  // grid / app switcher (SBAppSwitcherContinuousExposeSwitcherModifier)
                            { SBAppExposeContinuousExposeSwitcherModifier *ae = BSSafeCast(NSClassFromString(@"SBAppExposeContinuousExposeSwitcherModifier"), floor);
                              return (ae && [[ae bundleIdentifier] isEqualToString:bid]) ? floor : [[SBAppExposeContinuousExposeSwitcherModifier alloc] initWithBundleIdentifier:bid]; }
    case 3:  /* app */ {
        NSSet *touch = nil, *hover = nil; SBSwitcherModifier *reuse = nil;
        if (!bid && floor && [floor isKindOfClass:[SBFullScreenContinuousExposeSwitcherModifier class]]) {
            SBFullScreenContinuousExposeSwitcherModifier *fs = (id)floor;
            if ([[fs fullScreenAppLayout] isEqual:toAL]) reuse = floor;                 // same stage layout: keep the modifier (and its state)
            touch = [fs highlightedByTouchAppLayouts]; hover = [fs highlightedByHoverAppLayouts];   // carried over even when replaced
        }
        if (reuse) return reuse;
        if (bid) { SBInlineAppExposeContinuousExposeSwitcherModifier *ia = BSSafeCast(NSClassFromString(@"SBInlineAppExposeContinuousExposeSwitcherModifier"), floor);
                   return (ia && [[ia appExposeBundleIdentifier] isEqualToString:bid]) ? ia : [[SBInlineAppExposeContinuousExposeSwitcherModifier alloc] initWithActiveAppLayout:toAL appExposeBundleIdentifier:bid]; }
        SBFullScreenContinuousExposeSwitcherModifier *n = [[SBFullScreenContinuousExposeSwitcherModifier alloc] initWithFullScreenAppLayout:toAL];
        if (touch) [n setHighlightedByTouchAppLayouts:touch];  if (hover) [n setHighlightedByHoverAppLayouts:hover];
        return n; }
    default: return nil;
    }
}
```
16.0 differences (so a port of this method should NOT be done wholesale): 16.0 also (a) used `[e ambiguouslyLaunchedBundleIDIfAny]` / `appPileBundleIDToBringForwardIfAny` / `fullScreenAppDisplacementState` to carry stage state across floor replacements (all gone in 16.2), and (b) for `toEnvironmentMode==1` with a valid `toPeekConfiguration` created `SBPeekHomeScreenContinuousExposeSwitcherModifier initWithAppLayout:configuration:` as the floor (16.2 moved peek into a child modifier, 3.1).

```objc
// ---- NEW 16.2 0x1c78183f0: the floor modifier while a window is dragged
- (SBSwitcherModifier *)floorModifierForGestureEvent:(SBGestureSwitcherModifierEvent *)e {
    if ([e isContinuousExposeWindowDragEvent]) {
        long long phase = [e phase]; SBSwitcherModifier *floor = [self floorModifier];
        SBAppLayout *sel = [e selectedAppLayout], *proposed = [self proposedAppLayoutForContinuousExposeWindowDrag];   // 16.2-only query
        BOOL contains = [proposed containsAnyItemFromAppLayout:sel];
        SBSwitcherModifier *r = nil;
        switch (phase) {
        case 1 /*begin*/:  _initialFloorModifierForContinuousExposeWindowDrag = floor; break;
        case 3 /*end*/:    _initialFloorModifierForContinuousExposeWindowDrag = nil;   break;
        case 2 /*change*/: if (contains) { if (![floor isKindOfClass:[SBFullScreenContinuousExposeSwitcherModifier class]])
                                               r = [[SBFullScreenContinuousExposeSwitcherModifier alloc] initWithFullScreenAppLayout:proposed]; }   // dragged window is over the stage: show it as the stage
                           else if (![floor isEqual:_initialFloorModifierForContinuousExposeWindowDrag]) {                      // dragged back out: restore
                               [_initialFloorModifierForContinuousExposeWindowDrag setState:0]; /* UNSURE: revived */ r = _initialFloorModifierForContinuousExposeWindowDrag; }
                           break;
        }
        if (r) return r;
    }
    return [self floorModifier];
}
```
(UNSURE: the exact restore branch at 0x1c7818530..55c; state 0 = active.)

```objc
// ---- 0x1c7819254 handleEvent:  - see 1.3 (emits SBInvalidateContinuousExposeIdentifiersEventResponse)
// ---- 0x1c7819470 handleTransitionEvent: (16.0 0x1c6371a34: only stored _currentAppLayout)
- (id)handleTransitionEvent:(SBTransitionSwitcherModifierEvent *)e {
    id r = [super handleTransitionEvent:e];
    _currentAppLayout = [e toAppLayout];
    if (([e phase] == 2 || ![e isAnimated]) && SBPeekConfigurationIsValid([e toPeekConfiguration]) && ![self childModifierByKey:@"SBContinuousExposePeekModifierKey"])
        [self addChildModifier:[[SBContinuousExposePeekSwitcherModifier alloc] initWithAppLayout:[e toAppLayout] configuration:[e toPeekConfiguration]] atLevel:2 key:@"SBContinuousExposePeekModifierKey"];
    return r;
}
// ---- 0x1c7819cb8 _effectiveEnvironmentMode   (16.0 0x1c6372a88)
- (long long)_effectiveEnvironmentMode {
    id f = [self floorModifier];
    if (!f || [f isKindOfClass:SBHomeScreenContinuousExposeSwitcherModifier.class]) return 1;
    if ([f isKindOfClass:SBFullScreenContinuousExposeSwitcherModifier.class]) return 3;
    if ([f isKindOfClass:SBAppSwitcherContinuousExposeSwitcherModifier.class] || [f isKindOfClass:SBAppExposeContinuousExposeSwitcherModifier.class]) return 2;   // 16.0: only AppSwitcherCE
    return [f isKindOfClass:SBInlineAppExposeContinuousExposeSwitcherModifier.class] ? 2 : 1;                                                               // 16.0: always 1
}
// ---- 0x1c7819b74 handleContinuousExposeStripEdgeProtectTongueEvent: (see 1.8)
- (id)handleContinuousExposeStripEdgeProtectTongueEvent:(id)e { id r = [super ...]; _isStripTonguePresented = [e isTonguePresented]; return Append([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:4 updateMode:2], r); }
- (SBSwitcherContinuousExposeStripTongueAttributes)continuousExposeStripTongueAttributes { return Make(_isStripTonguePresented ? 2 : 1, [UIApp isRTLEnabled] ? 2 : 1); }   // 0x1c7819c54
- (SBAppLayout *)appLayoutOnContinuousExposeStage { return _effectiveAppLayoutOnStage; }                                                        // 0x1c7819c3c
- (BOOL)shouldUseWallpaperGradientTreatment { return YES; }  // 0x1c7819c4c
- (BOOL)shouldScaleContentToFillBoundsAtIndex:(NSUInteger)i { return NO; } 0x1c7819ca8   - (BOOL)shouldUseNonuniformSnapshotScalingForLayoutRole:(long long)r inAppLayout:(id)l { return NO; } 0x1c7819cb0   // UNSURE: returns 0
```
`gestureModifierForGestureEvent:` (16.2 0x1c7818d78 / 16.0 0x1c6371600): switch on `[e gestureType]` (1..12):
type 1 -> `SBHomeGestureRootSwitcherModifier initWithStartingEnvironmentMode:[self _effectiveEnvironmentMode] multitaskingModifier:[SBAppSwitcherContinuousExposeSwitcherModifier new]` + `setEnsuresSelectedAppLayoutUsesAnchorPointSpacePinning:YES` (same in 16.0);
**type 3 -> NEW `SBGridSwipeUpGestureRootSwitcherModifier initWithStartingEnvironmentMode:[self _effectiveEnvironmentMode] multitaskingModifier:[SBAppSwitcherContinuousExposeSwitcherModifier new]`** (16.0: plain `SBGridSwipeUpGestureSwitcherModifier initWithGestureID:`, no root);
**type 7 -> NEW `SBContinuousExposeDragAndDropGestureRootSwitcherModifier initWithStartingEnvironmentMode:3 appLayout:_currentAppLayout`** (16.0: `SBContinuousExposePendingEvictionRootSwitcherModifier`, removed in 16.2 with `SBContinuousExposePendingEvictionGestureModifier`);
type 9 -> `SBContinuousExposeWindowDragRootSwitcherModifier initWithStartingEnvironmentMode:[self _effectiveEnvironmentMode] initialAppLayout:(_currentAppLayout ?: [[SBAppLayout homeScreenAppLayout] appLayoutByModifyingPreferredDisplayOrdinal:[self displayOrdinal]])` (16.0 `initWithInitialAppLayout:`);
type 10 -> `SBItemResizeGestureRootSwitcherModifier initWithStartingEnvironmentMode:3 selectedLayoutRole:[e selectedLayoutRole]`; type 11 -> `SBRevealContinuousExposeStripsRootSwitcherModifier initWithInitialAppLayout:_currentAppLayout`; type 12 -> `SBRevealContinuousExposeStripOverflowRootSwitcherModifier initWithInitialAppLayout:_currentAppLayout`; other types nil.
`transitionModifierForMainTransitionEvent:` (0x1c781859c): same dispatcher as 16.0 (App-to-App / switcher<->app / switcher->home via `SBContinuousExposeToHomeSwitcherModifier` ... already ported) with these differences: sets the three event flags (2.0) on `SBContinuousExposeAppToAppModifier` (`setContinuousExposeConfigurationChangeTransition:`, `setCommandTabTransition:`, `setLaunchingFromDockTransition:`), returns `nil` for `isiPadOSWindowingModeChangeEvent` events (so the iPadOS platform modifier handles them), and adds `SBContinuousExposeSwitcherToAppExposeSwitcherModifier` (2.3), `SBPulseTransitionSwitcherModifier`, `SBWindowCommitSwitcherModifier` / `SBWindowDeclineSwitcherModifier` / `SBWindowDeleteSwitcherModifier` / `SBEntityRemoval*` (all exist in 16.0).
`handleContinuousExposeIdentifiersChangedEvent:` (0x1c78195b8, blocks 0x1c7819a8c/b00): same slide-modifier spawning as 16.0 but with the two-list API: `previousContinuousExposeIdentifiersInSwitcher/InStrip`, creates `SBContinuousExposeIdentifierSlideModifier initWithContinuousExposeIdentifier:previousContinuousExposeIdentifiersInSwitcher:previousContinuousExposeIdentifiersInStrip:direction:` (direction codes 5 instead of 4 for the added-with-position case), only when `[self _effectiveEnvironmentMode] == 3` and the event is animated.

**What it fixes / adds.** (a) `_effectiveEnvironmentMode` returned 1 (home) for App Expose and inline App Expose floors in 16.0, so gestures started from them (home gesture, window drag, strip reveal) began in the wrong environment mode - a real bug (confidence high). (b) peek moved to a child modifier; (c) drag-time floor swap; (d) new gesture roots.
**PORTABILITY.**
* `_effectiveEnvironmentMode`: **PORTABLE** hook on the existing 16.0 `SBContinuousExposeRootSwitcherModifier` (hooks 4.1; `%orig`, then return 2 when the floor is an App Expose / inline App Expose modifier).
* type 3 / type 9 gesture roots: **PARTIAL**: type 3 (Grid swipe-up root) is a thin new class (new, PORTABLE as a class, hooks 4.1) that only matters for the gesture-initiated switcher->home transition `SBContinuousExposeToHomeSwitcherModifier` (already ported for the non-gesture case); wiring needs a `%hook` of Root `gestureModifierForGestureEvent:` (exists in 16.0) returning the new root for type 3.
* `handleEvent:` invalidate / `handleTransition peek` / `floorModifierForGestureEvent:` / `handleContinuousExposeStripEdgeProtectTongueEvent:`: **NOT PORTABLE as such** (need the 16.2 query `proposedAppLayoutForContinuousExposeWindowDrag`, the new floor lifecycle, the peek family, and ivars on the Root class: 3 new ivars = use associated objects if ever needed).
* Do not replace `floorModifierForTransitionEvent:` or `transitionModifierForMainTransitionEvent:` wholesale: they are coupled to the 16.2 FullScreen/Strip split.
* Base-class handlers (`handleTapAppLayoutHeaderEvent:` etc.): PORTABLE via the `_handleEvent:` hook of 0.1 (hooks section 0.1).

### 4.2 SBAppSwitcherContinuousExposeSwitcherModifier  (the Stage Manager "all windows" switcher; 18 changed methods, ~65 new)

16.0 ivars `_previousContentOffset`, `_isScrollingForward`; 16.2 adds `_ongoingAppLayoutRemovals` +0x78, `_appLayoutLayoutCalculationsCache` +0x80 (`SBSwitcherLayoutCalculationsCache`, delegate = self), `_modifierEventGenCount` +0x88, `_cachedPileBoundingFrameByPileIdentifier` +0x90, `_cachedFittedContentSize` +0x98, `_cached_compactedBoundingBoxSizesByAppLayout` +0xa8, `_handlesTapAppLayoutEvents` +0xb0, `_handlesTapAppLayoutHeaderEvents` +0xb1 (both default YES, `init` 0x1c780f6bc also adds an `SBDefaultImplementationsSwitcherModifier` child at level 1 and creates the cache).
It was **rewritten around piles** (same architecture as `SBStripContinuousExposeSwitcherModifier`): `scaleForIndex:` (0x1c780ff80) is now `[cache scaleForKey:appLayout validityToken:[self _currentLayoutCalculationsValidityToken] fallback:^{1.0}]`, `frameForIndex:` (0x1c780fe78) is `_frameForIndex:withScaleApplied:NO scrollOffsetApplied:YES`, `_fittedContentSize` (0x1c7812504) returns `_cachedFittedContentSize`, `snapshotScaleForAppLayout:` -> `_defaultCardScale`, `opacityForLayoutRole:inAppLayout:atIndex:` -> `1.0` only when `_indexOfAppLayoutInItsPile:` < `chamoisSettings.numberOfVisibleItemsPerGroup` else 0 (older cards of a pile are invisible), and `buildLayoutCalculationsForCache:` builds frames / scales / pile bounding boxes in one pass. The old `_numberOfColumns/_rowForIndex:/_columnForIndex:/_scaledCardSize` grid helpers are gone.
New behaviour surface: `handleTapAppLayoutEvent:`, `handleTapAppLayoutHeaderEvent:` (Pulse, 1.4), `handleRemovalEvent:`, `handleEvent:`, `handleTapOutsideToDismissEvent:`, keyboard-navigation (`activeLeafAppLayoutsReachableByKeyboardShortcut`, `inactiveAppLayoutsReachableByKeyboardShortcut`, `neighboringAppLayoutsForFocusedAppLayout:`), reopen-closed-windows button (`reopenClosedWindowsButtonAlpha/Scale`, `appLayoutToScrollToBeforeReopeningClosedWindows`), plus button style/alpha, `adjustedContinuousExposeIdentifiersIn...` queries, `activityModeForAppLayout:`/`jetsamModeForAppLayout:`, `appLayoutsToResignActive`, `clippingFrameForIndex:withBounds:`, shelf blur frame/opacity, dock window level priority.
**PORTABILITY: NOT PORTABLE** as a faithful port (a 140-method rewrite sharing the Strip modifier's new calculation cache, 9 new ivars on a class that 16.0 allocates itself). Keep the 16.0 class. Selected small fixes that are hookable on the 16.0 class if wanted: none identified without the new `SBSwitcherLayoutCalculationsCache` (a new class, itself portable). Tap handling switches `handlesTapAppLayoutEvents/HeaderEvents` are used by the peek / drag content modifiers (3.1, 3.2) to disable the child's tap handling: for a 16.0 port of those, hook `handleTapAppLayoutEvent:` of 16.0's `SBAppSwitcherContinuousExposeSwitcherModifier` and honour an associated-object flag.

### 4.3 SBInlineAppExposeContinuousExposeSwitcherModifier  (11 changed, 19 new methods)

New ivars `_showingReopenClosedWindowsButton` +0x60 (all other ivars shift by 8: `_activeAppLayout` 0x60->0x68), `_numberOfHiddenAppLayouts` +0x90. Removed: `_overlappingModelForAppLayout:` (now the base `overlappingModelForAppLayout:`), `adjustedContinuousExposeIdentifiersForIdentifiers:`, `shouldSuppressHighlightEffectForLayoutRole:inAppLayout:`.
Changed methods (diff): `titleAndIconOpacityForIndex:` 1->20 (hides title/icon of the active app layout: `[activeAppLayout isEqual:layout] ? 0 : [super]`, UNSURE inversion), `handleTransitionEvent:` 6->16 (at `phase == 2`, when `fromAppExposeBundleID` / `toAppExposeBundleID` differ: appends `_responseToUpdateReopenClosedWindowsButtonPresenceIfNeeded` and an `SBInvalidateReopenButtonTextSwitcherEventResponse`), `homeScreenDimmingAlpha` (uses `overlappingModelForAppLayout:`.`stageArea` instead of `initialStageFrameForAppLayout:...`), `frameForLayoutRole:inAppLayout:withBounds:` and `frameForIndex:` (RTL-aware via `userInterfaceLayoutDirection`, `_numberOfInlineAppExposeColumns` instead of `chamoisLayoutAttributes.defaultWindowSize/_scaleForInlineAppExposeAppLayouts`), `_isLayoutRoleOccluded:inAppLayout:` (adds `isItemCoveredByFullyOccludedPeekingItem:`), `handleTapAppLayoutEvent:` (gated by `isHandled`; builds `requestForTapAppLayoutEvent:` + `setAppLayout:` + `setActivatingDisplayItem:` instead of `requestForActivatingAppLayout:`), `scaleForLayoutRole:inAppLayout:` (uses `partiallyOccludedStageScaleForItemWithSize:[sizeForItem:]` instead of `stageOccludedAppScale`), `_inlineAppExposeAppLayouts` (`continuousExposeIdentifiersInSwitcher` + filter on `_appExposeBundleIdentifier containsString:`), `handleHighlightEvent:` (ignores handled events). New: header-tap pulse (`handleTapAppLayoutHeaderEvent:` -> Pulse), reopen-closed-windows button (`isShowingReopenClosedWindowsButton`, `reopenClosedWindowsButtonAlpha/Scale`, `_canShowReopenClosedWindowsButton`), plus-button style/alpha, `appExposeAccessoryButtonsBundleIdentifier`, `handleInsertionEvent:`, `handleTimerEvent:`, `spaceAccessoryViewIconHitTestOutsetForAppLayout:`.
**PORTABILITY: PARTIAL.** The geometry/occlusion/tap diffs depend on `SBChamoisOverlappingModel` / `SBSwitcherChamoisLayoutAttributes` new members (`stageArea`, `isItemCoveredByFullyOccludedPeekingItem:`, `partiallyOccludedStageScaleForItemWithSize:`; group 1a/2). The reopen-closed-windows button and new queries are 16.2-only protocol (0.3). The tap-event fix (`requestForTapAppLayoutEvent:` / `setActivatingDisplayItem:`) is the same as in the FullScreen modifier spec and can be hooked on 16.0's class once `SBTapAppLayoutSwitcherModifierEvent` gets `source`/`modifierFlags` (hooks: not drafted; shares the FullScreen port).

### 4.4 SBContinuousExposeWindowDragSwitcherModifier  (gesture modifier, 11 changed, 10 new; superclass SBGestureSwitcherModifier)

Ivar delta: removed `_translation`; added `_sizeOfSelectedDisplayItem` (CGSize) +0xb0, `_dragBeganInOtherSwitcher` +0xc0, `_dragBeganInAnyStrip` +0xc1, `_dragBeganOnAnyStage` +0xc2 (all later ivars shift: `_selectedDisplayItem` 0xd0->0xd8, `_destinationModifier` 0xc0->0xc8, `_initialAppLayout` 0xc8->0xd0).
Behaviour (from the diff of `handleGestureEvent:` 0x1c7609578 and queries): window drags can now begin in another display's switcher (`_dragBeganInOtherSwitcher`), from a strip or from a stage (`isDraggingFromContinuousExposeStrips` result stored as `_dragBeganInAnyStrip`, `_dragBeganOnAnyStage` from `draggingAppLayoutsForContinuousExposeWindowDrag`), the dragged item size is tracked (`sizeOfSelectedDisplayItem`), the anchor point is the `locationInSelectedDisplayItem` (translation based logic removed), at gesture end it appends `SBUpdateLayoutSwitcherEventResponse (2,2)` then `(8,3)`, and hides the strip (`SBUpdateContinuousExposeStripsPresentationResponse initWithPresentationOptions:0 dismissalOptions:1`) when `continuousExposeStripProgress` != 0 after a drop. `scaleForIndex:` returns 0.6 for the dragged item when `_dragBeganInAnyStrip` or `_dragBeganOnAnyStage` (and `_anyProposedAppLayoutContainsSelectedDisplayItem`), `frameForIndex:` compares `_sizeOfSelectedDisplayItem` with the item's size before using `SBRectWithSize`, `perspectiveAngleForAppLayout:` is RTL-aware, `animationAttributesForLayoutElement:` uses `windowDragAnimationSettings` (fluid behaviour settings) for the dragged element instead of `resizeAnimationSettings`+`updateMode 3`, `_appLayoutContainingDisplayItem:` no longer logs/asserts (16.0 logged "Expected an app layout containing item"), new queries `visibleAppLayouts`, `opacityForLayoutRole:inAppLayout:atIndex:`, `shouldUseAnchorPointToPinLayoutRolesToSpace:`, `isSwitcherWindowVisible`, `isSwitcherWindowUserInteractionEnabled`, `continuousExposeStripProgress`, `appLayoutOnContinuousExposeStage`, `_anyItemExceedsWidthThresholdToHideStrip`, `_anyProposedAppLayoutContainsSelectedDisplayItem`.
**PORTABILITY: NOT PORTABLE** as a whole (new ivars on the class that 16.0's drag root allocates, plus 16.2-only context `draggingAppLayoutsForContinuousExposeWindowDrag`/`proposedAppLayoutForContinuousExposeWindowDrag`, multi-display drag, `SBDisplayItemLayoutAttributes attributedSize/normalizedCenter` model change). Individually hookable on the 16.0 class (PARTIAL): `animationAttributesForLayoutElement:` (use `windowDragAnimationSettings`), `_appLayoutContainingDisplayItem:` (drop the log), RTL `perspectiveAngleForAppLayout:`. Not drafted (cosmetic).

### 4.5 SBHomeScreenContinuousExposeSwitcherModifier  (1 changed: init; +3 new / -4 removed methods)

`init` (16.2 0x1c77f3898, 16.0 0x1c634e174): the 16.0 version built a `SBGridLayoutSwitcherModifier initWithAlignment:layoutDirection:` (`_gridLayoutModifier` +0x68) and a home-screen modifier; 16.2 builds `_stripModifier = [SBStripContinuousExposeSwitcherModifier new]` (ivar +0x60, added with `addChildModifier:`, see the Strip spec) and the home-screen modifier now at +0x68. New: `continuousExposeStripProgress`, `isResizeGrabberVisibleForAppLayout:`, `responseForProposedChildResponse:childModifier:event:`; removed: `appLayoutsToCacheSnapshots`, `dimmingAlphaForLayoutRole:inAppLayout:`, `scrollViewContentOffset`, `topMostLayoutElements` (the strip modifier answers them).
**PORTABILITY: NOT PORTABLE alone**: only meaningful with the Strip modifier port (spec SBStripContinuousExposeSwitcherModifier.md).

### 4.6 SBContinuousExposeWindowDragDestinationSwitcherModifier (8 changed), WindowDragRoot (2), WindowDrop

Ivar delta: removed `_translation`, `_draggingFromStrips`, `_hasForegroundedSelectedDisplayItem`; added `_initialSelectedDisplayItemLayoutAttributes` +0x90, `_dragBeganInOtherSwitcher` +0x98, `_lastAppLayoutForStripCalculation` +0xb0.
* `_widthThresholdToHideStrips` (0x1c74f3d8c, 8->3 instrs) is now `[[self overlappingModelForAppLayout:...] widthThresholdToHideStrip]` (the threshold became a property of `SBChamoisOverlappingModel`, new in 16.2) instead of `chamoisSettings widthThresholdToHideContinuousExposeStripsForStageWithItemCount:bounds:chamoisLayoutAttributes:`.
* `handleGestureEvent:` (0x1c74f3330): no longer uses translation; recomputes the strip cancel zone with `stripWidth` / `continuousExposeStripProgress` and RTL; remembers `_lastAppLayoutForStripCalculation`; sets `[self setUnlockedEnvironmentMode:3]`; when the proposed layout changes appends `SBInvalidateContinuousExposeIdentifiersEventResponse (from:_lastAppLayoutForStripCalculation to:proposed animated:YES)` (1.3).
* `_frameForSelectedDisplayItem` / `_appLayoutByAddingItem:toAppLayout:size:center:`: use `attributedSize`/`normalizedCenter` (`attributesByModifyingNormalizedCenter:`, `initWithContentOrientation:lastInteractionTime:sizingPolicy:attributedSize:normalizedCenter:`, `_SBDisplayItemAttributedSizeInfer`, `sizeInBounds:defaultSize:screenEdgePadding:`) and drags between switchers (`draggingAppLayoutsForContinuousExposeWindowDrag`).
* New `proposedAppLayoutForContinuousExposeWindowDrag` query (answers the proposed layout to Root.`floorModifierForGestureEvent:`) and `_anyProposedAppLayoutContainsSelectedDisplayItem`.
* `SBContinuousExposeWindowDragRootSwitcherModifier` (changed `gestureChildModifierForGestureEvent:activeTransitionModifier:` 0x1c7461188, `handleTransitionEvent:` 0x1c7461458, new `handleGestureEvent:` 0x1c74613a0, `animationAttributesForLayoutElement:` 0x1c746159c, `appLayoutsToResignActive` -> empty dict, `debugPotentialChildModifiers`; init renamed `initWithStartingEnvironmentMode:initialAppLayout:`): the gesture child is now `SBFilteringSwitcherModifier initWithAppLayouts:@[selectedAppLayout] modifier:[_SBContinuousExposeWindowDragContentSwitcherModifier initWithGestureID: initialAppLayout: selectedDisplayItem:]` (1.1, 3.2) so the dragged window is rendered by its own content stack; at gesture phase 1 `handleGestureEvent:` appends `SBInvalidateAdjustedAppLayoutsSwitcherEventResponse`; `handleTransitionEvent:` sets the gesture modifier's `state = 1` (done) at transition phase 1 (when the target layout equals the initial layout; else at phase 3); `animationAttributesForLayoutElement:` uses `medusaSettings.resizeAnimationSettings` + `updateMode 3` for the selected layout (so the 16.0 drag-modifier animation moved here).
* `SBContinuousExposeWindowDropSwitcherModifier` (transition after a drag; class unchanged except): new `handleTransitionEvent:` (0x1c79a5eb4; for `toEnvironmentMode == 1` (drop onto home) with reduce-motion off picks `SBFullScreenToHomeCenterZoomDownSwitcherModifier` (offset factor from `homeGestureSettings`) or `SBFullScreenToHomeIconZoomSwitcherModifier initWithTransitionID:appLayout:direction:1`, `setShouldForceDefaultAnchorPointForTransition: isChamoisWindowingUIEnabled`, `addChildModifier:`), new `shouldUseAnchorPointToPinLayoutRolesToSpace:` (NO for the selected item), `transitionDidEnd` appends `SBInvalidateAdjustedAppLayoutsSwitcherEventResponse`.
**PORTABILITY:** WindowDrop `handleTransitionEvent:` home-drop zoom: **PORTABLE (small, hookable on the 16.0 class** if the targets exist: `SBFullScreenToHomeCenterZoomDownSwitcherModifier`, `SBFullScreenToHomeIconZoomSwitcherModifier` exist in 16.0; not drafted). Drag destination/root/drag modifier: **NOT PORTABLE** (data model change `attributedSize`/`normalizedCenter` is in `SBDisplayItemLayoutAttributes`, a group-2 class).

### 4.7 SBContinuousExposeIdentifierSlideModifier  (6 changed; 8 new)

Ivar delta: `_isWaitingToPrepareLayout` +0x60, `_isWaitingToBeginAnimation` +0x61 (unchanged); 16.0 `_overrideWithPreviousIdentifiers` (+0x62) and `_previousContinuousExposeIdentifiers` (NSOrderedSet) are replaced by `_uniqueAnimationIdentifier` +0x68 (NSString, `[[NSUUID UUID] UUIDString]`), `_previousContinuousExposeIdentifiersInSwitcher` +0x78, `_previousContinuousExposeIdentifiersInStrip` +0x80 (NSArrays); `_continuousExposeIdentifier` +0x70, `_direction` +0x88.
```objc
- (instancetype)initWithContinuousExposeIdentifier:(NSString *)ident previousContinuousExposeIdentifiersInSwitcher:(NSArray *)sw previousContinuousExposeIdentifiersInStrip:(NSArray *)strip direction:(NSUInteger)dir {   // 0x1c78701f0
    self = [super init];  asserts (lines 0x20,0x21,0x22) ident, sw, strip non-nil;
    _continuousExposeIdentifier = [ident copy]; _previousInSwitcher = [sw copy]; _previousInStrip = [strip copy]; _direction = dir; _uniqueAnimationIdentifier = [[NSUUID UUID] UUIDString];
    return self;
}
- (NSString *)_waitingToPrepareLayoutReason { return [NSString stringWithFormat:@"%@-WaitingToPrepareLayout", _uniqueAnimationIdentifier]; }   // 0x1c78712c4
- (NSString *)_waitingToAnimateReason       { return [NSString stringWithFormat:@"%@-WaitingToAnimate", _uniqueAnimationIdentifier]; }            // 0x1c7871308 (16.0 used fixed class-wide strings)
- (void)_performBlockWithIdentifiersInSwitcher:(NSArray *)sw identifiersInStrip:(NSArray *)strip block:(void (^)(void))b {                   // 0x1c787134c
    SBOverrideContinuousExposeIdentifiersSwitcherModifier *o = [[... alloc] initWithContinuousExposeIdentifiersInSwitcher:sw continuousExposeIdentifiersInStrip:strip];
    [self performTransactionWithTemporaryChildModifier:o usingBlock:b];       // replaces 16.0's _overrideWithPreviousIdentifiers flag + own continuousExposeIdentifiers override
}
- (id)handleContinuousExposeIdentifiersChangedEvent:(id)event {                                                                            // 0x1c7870e9c
    id r = [super ...];
    if ([event isAnimated]) {
        if (_direction == 0 /*add*/ && !_isWaitingToPrepareLayout && !_isWaitingToBeginAnimation) {       // phase 1: hold the new group off-screen
            r = Append([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:2 updateMode:2], r);
            r = Append([[SBTimerEventSwitcherEventResponse alloc] initWithDelay:0 validator:nil reason:[self _waitingToPrepareLayoutReason]], r);
            _isWaitingToPrepareLayout = YES; }
        else if (_direction == 1 /*remove*/ && !_isWaitingToBeginAnimation) r = Append([self _beginAnimation], r);
    }
    return r;
}
- (id)handleTimerEvent:(id)e {                                                                                                               // 0x1c7871040
    id r = [super handleTimerEvent:e];
    if (_direction != 0) { if (_isWaitingToBeginAnimation && [[e reason] isEqualToString:[self _waitingToAnimateReason]]) [self setState:1]; }   // done
    else if (_isWaitingToPrepareLayout && [[e reason] isEqualToString:[self _waitingToPrepareLayoutReason]]) r = Append([self _beginAnimation], r);   // (+ clears the flag)
    return r;
}
- (id)_beginAnimation {                                                                                                                       // 0x1c78711b4
    r = [[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:0xc updateMode:3];
    r = Append([[SBTimerEventSwitcherEventResponse alloc] initWithDelay:([[[[self switcherSettings] chamoisSettings] appToAppLayoutSettings] response] * 0.5) validator:nil reason:[self _waitingToAnimateReason]], r);
    _isWaitingToBeginAnimation = YES;  (_isWaitingToPrepareLayout = NO)  return r;
}
// geometry (frameForIndex: 0x1c7870404, scaleForIndex: 0x1c78708c8, anchorPointForIndex: 0x1c78706ac - the last two are NEW):
//   for the layout whose continuousExposeIdentifier == _continuousExposeIdentifier:
//     direction 0 while _isWaitingToPrepareLayout: frame = off-screen slot at the strip edge: x = LTR: -(stripWidth + screenEdgePadding) - 0.5*width ; RTL: containerBounds.maxX + screenEdgePadding + stripWidth - 0.5*width  (UNSURE RTL arithmetic)
//     direction 1 while _isWaitingToBeginAnimation: frame / scale / anchor are evaluated "as they were" through _performBlockWithIdentifiersInSwitcher:(_previousInSwitcher) identifiersInStrip:(_previousInStrip), so the removed group animates from its old slot
//     otherwise [super]
- adjustedSpaceAccessoryViewFrame:forAppLayout: (0x1c7870ad0), animationAttributesForLayoutElement: (0x1c7870da4): same gating, accessory views follow the group; animation settings = chamoisSettings.appToAppLayoutSettings.
```
Effect: removal/insertion slide animations of window groups in the strip are computed from the real previous lists instead of a global "override" flag (which affected all queries issued during the flag), and animations of concurrent insertions no longer cross-talk (per-instance reasons). Confidence medium-high.
**PORTABILITY: PARTIAL**: the 16.0 class is hookable only for the cosmetic bits; porting the two-list model needs 1.2 and the 16.2 `...InSwitcher/InStrip` queries. Recommended: keep 16.0's Slide modifier unchanged (its reason strings are class constants in 16.0 and the methods `_waitingTo*Reason` do not exist there); no code drafted.

### 4.8 SBContinuousExposeAppToAppModifier  (5 changed; superclass SBTransitionSwitcherModifier)

Ivar delta: removed `_shouldSendFromIdentifierToBack` (+0x88) and `_shouldSendToIdentifierToFront` (+0x89); added `_commandTabTransition` +0x89, `_launchingFromDockTransition` +0x8a (`_continuousExposeConfigurationChangeTransition` +0x88 reused). Properties with setters (`setCommandTabTransition:`, `setLaunchingFromDockTransition:`).
```objc
- (void)didMoveToParentModifier:(id)parent {                                                       // 16.2 0x1c759598c  (16.0 0x1c610b99c)
    [super didMoveToParentModifier:parent];
    if (!parent || !_toAppLayout) return;
    if ([_toAppLayout containsAnyItemFromAppLayout:_fromAppLayout]) return;           // 16.0: continuousExposeIdentifier equality
    if (![[self appLayouts] containsObject:_toAppLayout]) return;                     // 16.0: !isAppLayoutVisibleInSwitcherBounds:
    SBSwitcherModifier *c = ([self isCommandTabTransition] || [self isLaunchingFromDockTransition])
        ? [[SBContinuousExposeFullScreenToStripCrossblurTransitionSwitcherModifier alloc] initWithTransitionID:[self transitionID] toAppLayout:_toAppLayout fromAppLayout:_fromAppLayout]
        : [[SBContinuousExposeFullScreenToStripTransitionSwitcherModifier alloc] initWithTransitionID:[self transitionID] outgoingAppLayout:_fromAppLayout];
    [self addChildModifier:c];                       // 16.0: [[SBContinuousExposeCrossblurModifier alloc] initWithTransitionID:fromAppLayout:toAppLayout:]
}
- (id)transitionWillBegin {                           // 0x1c7595b40 (16.0 0x1c610bac0: also reordered identifiers using _shouldSendFromIdentifierToBack / _shouldSendToIdentifierToFront)
    return Append([[SBUpdateLayoutSwitcherEventResponse alloc] initWithOptions:2 updateMode:2], [super transitionWillBegin]); }
- (BOOL)asyncRenderingDisabled { return _BSEqualObjects(_fromAppLayout, _toAppLayout) || [_fromAppLayout containsAllItemsFromAppLayout:_toAppLayout]; }   // 0x1c7595acc (16.0: equal only)
- (id)animationAttributesForLayoutElement:(id)el {   // 0x1c7595bd8
    a = [[super ...] mutableCopy];
    if ([el switcherLayoutElementType] != 0 || [_toAppLayout isEqual:el] || [_fromAppLayout isEqual:el]) { a.layoutUpdateMode = 3; a.layoutSettings = Fluid(response 0.4, damping 1.0); }      // the two layouts + accessories
    else { s = Fluid(response 0.54, damping 0.92); a.layoutSettings = a.positionSettings = a.opacitySettings = s; a.updateMode = 3; }                                                       // everything else (other windows)
    return a;   // 16.0: only when to == from and same orientation: layoutUpdateMode 3 + [self _layoutSettings]
}
- (BOOL)isLayoutRoleMatchMovedToScene:(long long)role inAppLayout:(SBAppLayout *)l {   // 0x1c7595f80
    if ([super ...]) return YES;
    if ([_toAppLayout isEqual:l]) return [self isContinuousExposeConfigurationChangeTransition];
    // layout different: item must be in both from and to; compare the item's size in from/to attribute maps (sizeInBounds:defaultSize:screenEdgePadding: of each) and sizingPolicy; match-move when size or sizing policy differ
    ...
}
- opacityForLayoutRole:inAppLayout:atIndex: -> [self isPreparingLayout] ? 0.0 : [super ..] (0x1c7595e68);  topMostLayoutElements: moves the to-layout's centre leaf (leafAppLayoutForRole:4) to the front unless equal to from's (0x1c7595d44);  perspectiveAngleForAppLayout: toAppLayout during phase 1 -> 0.0 (0x1c7595ef4)
```
Effect: new transition family (2.1/2.2) replaces the single 16.0 crossblur, and identifier reordering moved out (done by the strip / identifiers model).
**PORTABILITY: PARTIAL.** Hook `-didMoveToParentModifier:` of the 16.0 class (exists) to add the new children INSTEAD of (not in addition to) the 16.0 crossblur: call the original, then `removeChildModifier:` the `SBContinuousExposeCrossblurModifier` it added, add the 2.1/2.2 modifier. Risky: 16.0's own `transitionWillBegin` still runs its identifier reordering; keep it. Only enable behind its own switch (`off.group1b.apptoapp`). Needs the event flags (2.0). Code: hooks 4.8.

### 4.9 SBCycleContinuousExposeGroupAppLayoutsSwitcherModifier (2 changed), SBRevealContinuousExposeStripsGestureModifier (1 changed + 5 new), SBRevealContinuousExposeStripOverflowGestureModifier (2 changed), ...RootSwitcherModifier (1)

* **Cycle** (keyboard shortcut cycling windows of a group): `_completeIfNeededIgnoringHover:` (0x1c7589b7c) now also checks `[self state] != 1` before completing (no double completion; +1 compare), and `handleContinuousExposeIdentifiersChangedEvent:` (0x1c758977c) uses `continuousExposeIdentifiersGenerationCount` and skips the re-order when the event `isAnimated`; new `handleTransitionEvent:` finishes the modifier when the transition begins. Fix for stale ordering after a keyboard cycle (confidence medium). **PORTABLE-ish (PARTIAL)**: `[self state] != 1` guard can be added by hooking `_completeIfNeededIgnoringHover:` (exists in 16.0 @0x1c610455c); generation-count is the 16.2 identifier model (skip).
* **RevealStrips gesture** (the strip reveal pan): `handleGestureEvent:` (0x1c781783c): indirect-pan (pointer) aware: `isIndirectPanGestureEvent` -> RTL-aware direction, thresholds 0.2 (indirect) vs 0.1 progress, uses `chamoisLayoutAttributes.stripWidth`, end decision uses `isCanceled` and `_BSFloatGreaterThanOrEqualToFloat(progress, threshold)`; new `handleTransitionEvent:` (state=1 at transition phase >= 2), `continuousExposeStripProgress` (returns `_progress`; 16.0 `continuousExposeAppStripUnoccludedProgress`), `cornerRadiiForIndex:` (the initial layout gets `displayCornerRadius` (or stage radius) scaled by 1/scale during the reveal), `shadowOpacityForLayoutRole:atIndex:` (fades with `_progress` when the layout is full-bounds), `animationAttributesForLayoutElement:` (tracking response 0.15, damping 0.85, `updateMode 5` for app layouts). **NOT PORTABLE** (renamed progress query, indirect-pan events are 16.2 gesture-manager changes).
* **RevealStripOverflow gesture** (`frameForIndex:`, `_finalScaleForFullScreenAppLayout`): only `_overlappingModelForAppLayout:` -> `overlappingModelForAppLayout:` (16.0 had a private copy; method removed) - no behaviour change (confidence high). The Root's `transitionChildModifierForMainTransitionEvent:activeGestureModifier:` (+1 instr) likewise.
* **Gesture workspace transactions** (3.5).

---------------------------------------------------------------------------------------------------

## 3. Priority 3: peek and drag/drop (new in 16.2)

### 3.1 SBContinuousExposePeekSwitcherModifier  (NEW; class object 0x1de2387f8)

Ivars: `_contentModifier` +0x60, `_dismissalTransitionModifier` +0x68, `_appLayout` +0x70, `_configuration` +0x78 (SBPeekConfiguration, long long). Created by Root `handleTransitionEvent:` (4.1) at level 2, key `@"SBContinuousExposePeekModifierKey"`, whenever a transition event carries a valid `toPeekConfiguration` (a "peek": an app is shown over the current Stage Manager layout temporarily, e.g. from a notification / Slide Over-like peek).
```objc
- (instancetype)initWithAppLayout:(SBAppLayout *)l configuration:(long long)c {                                      // 0x1c78e50c4
    self = [super init]; NSAssert(l, @"appLayout");                                                                  // line 0x2c
    _appLayout = l; _configuration = c;
    _contentModifier = [[_SBContinuousExposePeekContentSwitcherModifier alloc] initWithAppLayout:l configuration:c];
    [self addChildModifier:[[SBFilteringSwitcherModifier alloc] initWithAppLayouts:@[l] modifier:_contentModifier]];  // content only sees the peeked layout (1.1)
    return self;
}
- (void)setState:(long long)s { if (s == 1 && [self state] != 1) [self newAppLayoutsGenCount]; [super setState:s]; }         // 0x1c78e52ec
- (NSArray *)appLayoutsToEnsureExistForMainTransitionEvent:(id)e { return @[]; }                                           // 0x1c78e52e0
- (BOOL)isSwitcherWindowVisible { return YES; }  - transactionCompletionOptions { return [UIApp isReduceMotionEnabled] ? 6 : 2; }   // 0x1c78e594c / 0x1c78e5954
- (NSArray *)appLayoutsForContinuousExposeIdentifier:(id)ident { r = [super ...]; if ([[_appLayout continuousExposeIdentifier] isEqualToString:ident]) r = [r bs_filter:^(l){ ... /* block 0x1c78e591c: drops layouts contained in _appLayout? UNSURE */ }]; return r; }
- (id)handleScrollEvent:(id)e { r = [super ..]; if (phase == 0 && [e isUserInitiated] && ![self childModifierByKey:@"UserScrollingModifier"]) [self addChildModifier:[SBScrollingSwitcherModifier new] atLevel:? key:@"UserScrollingModifier"]; log; return r; }   // 0x1c78e566c
- (id)handleTransitionEvent:(id)e {                                                                                 // 0x1c78e5410
    r = [super ..];
    // presentation: phase == 2, animated, toPeekConfiguration valid, fromPeekConfiguration invalid:
    //     [self addChildModifier:[[SBContinuousExposePeekTransitionModifier alloc] initWithTransitionID:tid fromAppLayout:from toAppLayout:to direction:0]]
    // dismissal: phase == 2, animated, from valid && to invalid:  _dismissalTransitionModifier = [[...PeekTransition alloc] ... direction:1]; [self addChildModifier:_dismissalTransitionModifier]
    // end: at phase 3 (and no peek on the to side) append SBInvalidateAdjustedAppLayoutsSwitcherEventResponse and [self setState:1]
    // also appends SBInvalidateAdjustedAppLayoutsSwitcherEventResponse at the start of a presentation (phase 2)
    return r;
}
- (id)handleEvent:(id)e { r = [super ..]; if (_dismissalTransitionModifier && [_dismissalTransitionModifier state] == 1) { r = Append([SBInvalidateAdjustedAppLayoutsSwitcherEventResponse new], r); [self setState:1]; } return r; }   // 0x1c78e5354
```
**PORTABILITY: NOT PORTABLE** (peek over Stage Manager is an unreleased-in-16.0 feature that needs `SBTransitionSwitcherModifierEvent toPeekConfiguration` handling in the Coordinator, `frameForContinuousExposePeekingDisplayItem:...` and the 2.6 transition). 16.0's peek (`SBPeekHomeScreenContinuousExposeSwitcherModifier`) is a different design; leave it.

### 3.2 _SBContinuousExposePeekContentSwitcherModifier  /  _SBContinuousExposeWindowDragContentSwitcherModifier  (NEW; class objects 0x1de238820 / 0x1de2316d8)

* Peek content (ivars `_fullScreenContinuousExposeAppLayoutModifier` +0x60, `_appSwitcherModifier` +0x68, `_appLayout` +0x70, `_configuration` +0x78): init (0x1c78e5a04) builds `SBFullScreenContinuousExposeSwitcherModifier initWithFullScreenAppLayout:l` (taps/header taps disabled) at level 0 and `SBAppSwitcherContinuousExposeSwitcherModifier` (taps disabled) at level 1. Queries: `adjustedAppLayoutsForAppLayouts:` (two `bs_filter:` passes: the peeked layout first then the rest, `arrayByAddingObjectsFromArray:`), `frameForLayoutRole:inAppLayout:withBounds:` (peeked layout: `frameForContinuousExposePeekingDisplayItem:inAppLayout:bounds:defaultFrameForLayoutRole:`), `scaleForLayoutRole:` (peeked layout -> 1.0), `shouldAllowContentViewTouchesForLayoutRole:` (NO for the peeked layout), `isLayoutRoleSelectable:` YES, `switcherHitTestsAsOpaque` NO, `keyboardSuppressionMode` = `suppressionModeForAllScenes`, `handleTapAppLayoutEvent:` (builds `requestForTapAppLayoutEvent:` with `setPeekConfiguration:1` and performs it: tapping the peeked window promotes it), `responseForProposedChildResponse:childModifier:event:` (drops tap-app-layout (type 18) responses coming from the full-screen child and all responses from the app-switcher child).
  **NOT PORTABLE** (peek family).
* Window-drag content (ivar `_selectedDisplayItem` +0x60; `initWithGestureID:initialAppLayout:selectedDisplayItem:` 0x1c762a3b0): composes `SBContinuousExposeWindowDragSwitcherModifier` (level 0), a `SBFullScreenContinuousExposeSwitcherModifier initWithFullScreenAppLayout:initialAppLayout` (taps off, level 1) and `SBAppSwitcherContinuousExposeSwitcherModifier` (taps off, level 2); `adjustedAppLayoutsForAppLayouts:` (0x1c762a510) returns the layouts containing `_selectedDisplayItem` first followed by the others. Used inside the Filtering modifier of the drag root (4.6). **NOT PORTABLE** (depends on the 16.2 drag modifier + 3 FullScreen/AppSwitcher 16.2 classes).

### 3.3 SBContinuousExposeDragAndDropGestureRootSwitcherModifier + SBContinuousExposeAppDragAndDropGestureSwitcherModifier  (NEW)

Root (gesture type 7; `initWithStartingEnvironmentMode:appLayout:` 0x1c7970ed8 asserts `appLayout` when mode == 3 (line 0x1d); ivar `_appLayout` +0x80): `gestureChildModifierForGestureEvent:activeTransitionModifier:` (0x1c7970fe0): when `currentEnvironmentMode == 3` and the stage already holds fewer items than `chamoisSettings.maximumNumberOfAppsOnStage`, `evicted = nil`, else `evicted = firstObject(sortedArrayUsingComparator(allItems of _appLayout by lastInteractionTime))` (the window that a drop would push out); returns `SBContinuousExposeAppDragAndDropGestureSwitcherModifier initWithGestureID: appLayout: displayItemThatWouldBeEvicted:`; `handleTransitionEvent:` handles the event "<class> handling drag and drop initiated transition." (`handleWithReason:`); `transitionChildModifierForMainTransitionEvent:` returns nil.
App drag-and-drop gesture modifier (superclass `SBGestureSwitcherModifier`, ~30 methods, 18 ivars): tracks a dragged app's platter (`_platterFrame`, `_location`, `_hasPlatterized`, `_hasPreviewLifted`, `_dropAction`, `_draggedSceneIdentifier`, blur state machine `_isBlurring/_isBlurred/_needsBlurBecauseFramesWillMismatch/_hasResizedEnoughToUnblur`, `_isResizing`, `_shouldPushInFullScreenContent`), previews which window would be evicted (`_displayItemThatWouldBeEvictedIfAny`), shows resize UI (`_showResizeUI`), handles resize/blur progress and scene-ready events, and on end creates `SBContinuousExposeDragAndDropToAppTransitionSwitcherModifier` (2.5).
Replaces 16.0's `SBContinuousExposePendingEvictionRootSwitcherModifier/GestureModifier` (gesture type 7 = "pending eviction" preview in 16.0).
**PORTABILITY: NOT PORTABLE** (a drag-and-drop-of-apps-into-Stage-Manager feature: needs `SBDragAndDropGestureSwitcherModifierEvent` fields, resize/blur progress events and the 16.2 gesture manager; 16.0 keeps type 7 = pending eviction).

### 3.4 SBGridSwipeUpGestureRootSwitcherModifier  (NEW; class object 0x1de22d538; gesture type 3)

Ivar `_multitaskingModifier` +0x80. `initWithStartingEnvironmentMode:multitaskingModifier:` (0x1c74073bc; asserts the modifier, line 0x1a); `gestureType` -> 3; `gestureChildModifierForGestureEvent:activeTransitionModifier:` -> `[[SBGridSwipeUpGestureSwitcherModifier alloc] initWithGestureID:[e gestureID] delayCompletionUntilTransitionBegins:YES]` (16.0 class exists; the init with `delayCompletionUntilTransitionBegins:` UNSURE for 16.0); `transitionChildModifierForMainTransitionEvent:activeGestureModifier:` -> for `from == 2 && to == 1` returns `[[SBContinuousExposeToHomeSwitcherModifier alloc] initWithTransitionID:tid direction:0 continuousExposeModifier:SafeCast([self _newMultitaskingModifier], SBAppSwitcherContinuousExposeSwitcherModifier)]` (the 16.2 wrapper already ported in SwitcherDismissFix 0.3.0 for the non-gesture case), else nil; `_newMultitaskingModifier` -> `[_multitaskingModifier copy]`.
Fix: swipe-up from the Stage Manager switcher to home now has a proper transition (the gesture counterpart of SwitcherDismissFix). Confidence high.
**PORTABILITY: PARTIAL.** Class reconstruction is small (hooks 4.1/3.4), needs `SBGestureRootSwitcherModifier` subclassing contract: 16.2 renamed `_gestureModifier` -> `gestureModifier` (property) and `SBGridSwipeUpGestureSwitcherModifier initWithGestureID:delayCompletionUntilTransitionBegins:` must be checked in 16.0 (`initWithGestureID:` is what 16.0 calls). Use together with the Root `gestureModifierForGestureEvent:` hook for type 3 and the SwitcherDismissFix wrapper class (`SDFContinuousExposeToHomeSwitcherModifier`). Not drafted as code (depends on that tweak's class).

### 3.5 Gesture workspace transactions

* `SBContinuousExposeStripRevealGestureWorkspaceTransaction` (16.2 class object 0x1de22de48) == renamed `SBRevealContinuousExposeStripsGestureWorkspaceTransaction` (16.0). `_gestureType` 0xb; ivar `_completedGestureWithTransitionRequest` (+0x198, was +0x190 because the base class gained a field); `_canBeInterrupted` returns YES until the gesture completed with a transition request; the override point changed from `completeGestureWithTransitionRequest:` (16.0 @0x1c5fa7f50) to `handleTransitionRequestForGestureComplete:fromGestureManager:` (16.2 @0x1c7420d38, sets the flag then `[super]`), because `SBFluidSwitcherGestureWorkspaceTransaction` itself was refactored in 16.2.
* `SBContinuousExposeStripOverflowGestureWorkspaceTransaction` (0x1de233320) == renamed `SBRevealContinuousExposeStripOverflowGestureWorkspaceTransaction`; only `_gestureType` -> 0xc.
* `-[SBFluidSwitcherGestureManager _fluidSwitcherGestureTransactionClassForGestureType:]` (16.2 0x1c72caff8, 16.0 0x1c5e58868) maps types 1..12 -> classes; types 0xb/0xc map to the two classes above (16.0 identical with old names).
**PORTABILITY: PORTABLE / NOT NEEDED.** The 16.0 classes and mapping already work in 16.0; the 16.2 rename and API change are internal to 16.2's refactored base class. Nothing to port.

---------------------------------------------------------------------------------------------------

## SUMMARY (group 1b)

### Portability table

| class / piece | verdict | note |
|---|---|---|
| Event types 36/37/38 dispatch (`_handleEvent:` hook) | PORTABLE | 16.0 ignores types > 35; one hook on `SBSwitcherModifier` |
| SBFilteringSwitcherModifier + passthrough target (1.1) | PORTABLE | built on 16.0 `SBRoutingSwitcherModifier`; `fallbackModifier...` never called in 16.0 |
| SBOverrideContinuousExposeIdentifiersSwitcherModifier (1.2) | PARTIAL | 16.0 has one identifier list; override `continuousExposeIdentifiers` only |
| SBInvalidateContinuousExposeIdentifiersEventResponse (1.3) | PARTIAL | use response type 40 (34 is taken in 16.0); consumer calls the existing 16.0 VC method; only useful with the drag-destination port |
| SBPulseDisplayItemSwitcherModifier (1.4) | PORTABLE | stage layout injected (`setStageAppLayout:`) because `appLayoutOnContinuousExposeStage` is 16.2-only |
| SBTapAppLayoutHeaderSwitcherModifierEvent (1.5) | PORTABLE | emission hook is inert unless the FullScreen header-tap handler exists |
| SBPointerCrossedDisplayBoundarySwitcherModifierEvent (1.6) | PARTIAL | class trivial; producer needs group-4 pointer-between-scenes detection + `preferredArrangementOfDisplay:relativeTo:` |
| SBPresentContinuousExposeStripEdgeProtectGrabberEventResponse (1.7) | PARTIAL | class trivial; no grabber UI in 16.0 (consumer no-ops) |
| SBContinuousExposeStripEdgeProtectTongueSwitcherModifierEvent (1.8) | PORTABLE (class) | flow PARTIAL |
| SBContinuousExposeStripTongueView (1.9) | PARTIAL | view fully reconstructed (runtime UIView subclass); VC hosting needs 4 ivars + accessory element type 6: not drafted |
| SBSetInterfaceOrientationFromUserResizingEventResponse (1.10) | PARTIAL | consumer delegate selector and producer context are 16.2-only |
| FullScreenToStrip + Crossblur transitions (2.1/2.2) | PARTIAL | full code drafted; installed only through the opt-in AppToApp hook (4.8) |
| SwitcherToAppExpose (2.3) | PARTIAL | not drafted; only with an App Expose backport |
| iPadOSWindowModeChange (2.4) | PORTABLE | code + creator hook drafted; needs transition-event flags (2.0, drafted) |
| DragAndDropToApp (2.5) | PORTABLE (class) | creator (3.3) NOT PORTABLE |
| PeekTransition (2.6), Peek family (3.1, 3.2) | NOT PORTABLE | new feature; 16.0 keeps `SBPeekHomeScreen...` |
| AppDragAndDrop gesture + DnD root (3.3) | NOT PORTABLE | replaces 16.0 pending-eviction; needs new gesture events |
| GridSwipeUp root (3.4) | PARTIAL | small; pairs with SwitcherDismissFix wrapper; not drafted |
| Reveal*GestureWorkspaceTransaction renames (3.5) | NOT NEEDED | 16.0 classes work as they are |
| Root `_effectiveEnvironmentMode` (4.1) | PORTABLE | real fix, drafted |
| Root floor/gesture/transition factories (4.1) | NOT PORTABLE wholesale | coupled to the FullScreen/Strip split |
| AppSwitcherCE, InlineAppExpose, WindowDrag(+Destination, Root), HomeScreenCE (4.2-4.6) | NOT PORTABLE / PARTIAL | rewrites on new data model (`SBSwitcherLayoutCalculationsCache`, `attributedSize/normalizedCenter`) |
| Slide modifier (4.7), AppToApp (4.8), Cycle/Reveal (4.9) | PARTIAL | see sections; AppToApp hook drafted as opt-in |

### Confidence
High: all event/response numbers, class/ivar layouts, the Filtering routing logic, Pulse, window-mode-change, DnD-to-app, FullScreenToStrip and Crossblur numeric behaviour, Root `_effectiveEnvironmentMode`/gesture dispatch, AppToApp wiring, transaction renames.
Medium: intent of the transition choreography, the drag-time floor swap in `floorModifierForGestureEvent:`, Slide direction semantics (0 = add, 1 = remove), orientation constants of 1.10, Peek phase conditions.
Low / not read in full: block bodies of PeekTransition, AppSwitcherCE rewrite internals, DnD gesture modifier body, `isLayoutRoleMatchMovedToScene` size comparison in AppToApp.

### Open questions
1. `SBUpdateLayoutSwitcherEventResponse` option bits and `updateMode` values (2 = no-animation, 3 = animate are inferred from use).
2. `SBChainableModifier` state 1 semantics (completed/removed) is inferred, not read from `setState:`.
3. Does a 16.0 `SBRoutingSwitcherModifier` accept a delegate that never answers `fallbackModifierForRoutingModifier:`? Reading 16.0 says yes (selector not used), untested.
4. Whether `SBGridSwipeUpGestureSwitcherModifier initWithGestureID:delayCompletionUntilTransitionBegins:` exists in 16.0 (3.4).
5. Request accessor name used by `transitionEventForContext:` hook (`request` vs `transitionRequest`; both tried).
6. `_SBFIsChamoisFullScreenToStripGroupOpacityAvailable` is an os feature flag; default YES in 16.2 (decoded); the group-opacity query itself is not in the 16.0 protocol so it cannot be reproduced.

### Suggested install order (smallest risk first)
1. `G1B_Base` (event dispatch, inert alone) + event/response classes + `G1B_InstallTransitionEventFlags` + `G1B_Coordinator`.
2. `G1B_Root` (`_effectiveEnvironmentMode` fix) - independent, safest visible fix.
3. Filtering, Override-ids, Pulse classes (inert until used).
4. `G1B_Platform` + window-mode-change class (corner-mask fix during windowing mode change).
5. Only with the FullScreen/Strip ports: header-tap emission (`G1B_Header`), pointer event, grabber response.
6. Opt-in last: `G1B_AppToApp` (new FullScreenToStrip / Crossblur choreography).

### Draft file
`group1b-modifiers.hooks.m`: drafted = 0.1, 1.1, 1.2, 1.3, 1.4, 1.5-1.8, 1.9 (view only), 1.10, 2.0, 2.1, 2.2, 2.4, 2.5, 4.1 (`_effectiveEnvironmentMode`), 4.8. Not drafted: 2.3, 2.6, 3.x, 4.2-4.7, 4.9 (reasons in the spec).
