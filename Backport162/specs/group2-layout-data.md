# Group 2: switcher view controller + layout data layer (16.2 / 20C65 -> 16.0 / 20A8372)

Scope: the data / layout classes that the already written specs
(`SBStripContinuousExposeSwitcherModifier.md`, `SBFullScreenContinuousExposeSwitcherModifier.md`, section 4 "Dependencies")
list as 16.2-only, and `SBFluidSwitcherViewController` (+ item container classes).

Conventions
- "160" = 20A8372, "162" = 20C65. Addresses are unslid vm addresses (160 / 162).
- Each item has: 16.0 behaviour, 16.2 behaviour (ObjC reconstruction), what it fixes (confidence), PORTABILITY.
- Portability tags: PORTABLE (hook on existing 16.0 class or new class, no ivar added to a system class),
  PARTIAL (works with a limitation, stated), NOT PORTABLE (stated why).
- ivars can NOT be added to existing classes at runtime. Where 16.2 adds an ivar to a system class the spec proposes an
  associated object (`objc_setAssociatedObject`), or a runtime subclass + `alloc` swizzle (only when instances are created
  by our own code or by a single known factory).
- Companion draft code: `group2-layout-data.hooks.m` (same item numbering in comments).
- Tools used: `ipsw dsc disass`, class dumps `sb160n_objc.txt` / `sb162_objc.txt`; every selector below is taken from the
  annotated disassembly (stub -> selector map), not guessed.

---------------------------------------------------------------------------------------------------

## 0. Framework finding that affects every "new context / query selector" (read first)

`SBSwitcherModifier` (and so every modifier, old and new) answers the switcher "query" protocol
(`SBSwitcherQueryProviding` + `SBSwitcherMultitaskingQueryProviding` + `SBSwitcherQueryDefaultImplementationProviding`)
and "context" protocol (`SBSwitcherContextProviding`) through generated trampolines, not through hand written methods.

`+[SBChainableModifier _initalizeIMPCaching]` (162 0x1c78da54c, called from `+initialize` 0x1c78d7ef4; 160 equivalent exists)
does, for the class that is `+baseClassForQueryProtocol` (SBSwitcherModifier):

```objc
for (Protocol *p = [cls queryProtocol]; p; p = (single sub protocol of p)) {      // "Multiple sub protocols not currently supported" (assert, SBChainableModifier.m:0x256 / 0x280)
    methods = protocol_copyMethodDescriptionList(p, YES /*required*/, YES /*instance*/, &n);
    for each (sel, types): if (![cls instancesRespondToSelector:sel])               // else assert "Cannot implement %@ on an implementer of +queryProtocol - it messes up the caching implementation" (line 0x248)
        class_addMethod(cls, sel, _SBChainableModifierMethodCacheQueryTrampolineForMethod(sel, types), types);
        record sel in the selector list
}
// same for [cls contextProtocol] with _SBChainableModifierMethodCacheContextTrampolineForMethod (0x1c774738c), assert line 0x272
```

The trampoline for a selector is chosen by a static table of 85 type-encoding strings at 162 0x1e18ee780 (16 bytes per entry:
encoding C-string pointer, trampoline IMP); the per-modifier method cache (`SBChainableModifierMethodCache`) then dispatches by
the selector's index in that selector list. Consequences for the backport:

1. The 16.2 protocol delta (below) is NOT present in the 16.0 protocol objects, so on 16.0 a `SBSwitcherModifier` subclass that calls
   `[self continuousExposeIdentifiersInStrip]` gets "unrecognized selector". `-provideNextQueryImplementation:forSelector:`
   / `-providePreviousContextImplementation:forSelector:` (category `RuntimeProviding`, exists in both builds, 160 0x1c5f5a850 / 0x1c5f5a90c) also
   refuse selectors that are not in the protocol (`protocol_getMethodDescription` returns NULL -> assertion/nil).
2. Two ways to get the new selectors:
   * (A) Faithful: hook the class methods `+[SBSwitcherModifier contextProtocol]`, `+queryProtocol` (and `+[SBChainableModifier baseClassForQueryProtocol]`
     stays as is) to return **extended protocol objects** (build with `objc_allocateProtocol`, copy every required method description of the
     original with `protocol_copyMethodDescriptionList`, add the 16.2 ones with `protocol_addMethod`, add the same parent protocol,
     `objc_registerProtocol`). It has to be installed in the tweak `%ctor`, before the first modifier class receives `+initialize`
     (SpringBoard creates the switcher after tweaks are loaded; verify in a log line printed from `+initialize`). The new selectors then get
     trampolines and take part in the chain (overrides in child modifiers work exactly as in 16.2). Unverified at runtime: the final link of the
     context chain (root -> VC) must forward unknown-to-16.0 selectors to the delegate with plain `objc_msgSend`; the 16.0 VC already answers
     all the 109 old context selectors that way, so a VC `%new` method with the same name is expected to be enough. CONFIDENCE medium.
   * (B) Cheap: `%new` methods with the new names on `SBSwitcherModifier` that go to the root modifier's `delegate` (the VC) directly
     (`BP_RootContextProvider`) and ignore chain overrides. Good enough for pure reads like `continuousExposeStripProgress`; WRONG for
     selectors that child modifiers override (stage layout, strip progress in FullScreen/WindowDrag/RevealStrips, identifiers override).
   The draft code implements (B) and the extended-protocol builder for (A) (`BP_G2_ExtendedProtocols`), switchable with one macro.

16.2 protocol deltas (from `SBSwitcherContextProviding` etc. in the class dumps):

| protocol | NEW in 162 | REMOVED from 160 |
|---|---|---|
| SBSwitcherContextProviding (95 -> 104) | `appLayoutOnContinuousExposeStage`, `continuousExposeIdentifiersGenerationCount`, `continuousExposeIdentifiersInStrip`, `continuousExposeIdentifiersInSwitcher`, `continuousExposeStripProgress`, `continuousExposeStripTongueBackdropCaptureLayoutElement`, `draggingAppLayoutsForContinuousExposeWindowDrag`, `layoutRestrictionInfoForItem:`, `newContinuousExposeIdentifiersGenerationCount`, `proposedAppLayoutsForContinuousExposeWindowDrag`, `requireStripContentsInViewHierarchy`, `supportedContentInterfaceOrientationsForItem:` | `continuousExposeAppStripUnoccludedProgress`, `continuousExposeIdentifiers`, `numberOfVisibleContinuousExposeIdentifiersWhileInApp` |
| SBSwitcherQueryProviding (108 -> 111) | `activeLeafAppLayoutsReachableByKeyboardShortcut`, `canSelectLeafWithModifierKeysInAppLayout:`, `inactiveAppLayoutsReachableByKeyboardShortcut`, `shouldAllowGroupOpacityForAppLayout:` | `shouldConfigureInAppDockVisibleAssertion` |
| SBSwitcherMultitaskingQueryProviding (7 -> 9) | `adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:`, `adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:` | - |
| SBSwitcherQueryDefaultImplementationProviding (50 -> 54) | `adjustedSpaceAccessoryViewScale:forAppLayout:`, `isContinuousExposeStripVisible`, `proposedAppLayoutForContinuousExposeWindowDrag`, `spaceAccessoryViewIconHitTestOutsetForAppLayout:`, `wantsContinuousExposeHoverGesture` | `adjustedContinuousExposeIdentifiersForIdentifiers:` |

(The strip/full-screen specs already cite most of these; the point here is that all of them need the framework step above.)

---------------------------------------------------------------------------------------------------

## A1. SBSwitcherLayoutCalculationsCache, its validity token, the delegate API

Classes: `SBSwitcherLayoutCalculationsCache` (160 class 0x1de0a2008 / 162 0x1de235288),
`SBSwitcherLayoutCalculationsCacheValidityToken` (160 0x1de0a20a8 / 162 0x1de235328), `SBSwitcherLayoutCalculations` (unchanged: `_scale` +0x8, `_frame` +0x10),
protocol `SBSwitcherLayoutCalculationsCacheDelegate`.

### ivars

| class | 160 | 162 |
|---|---|---|
| Cache | `_cachedLayoutCalculationsByKey` 0x8, `_validityToken` **0x10**, `_delegate` (weak) **0x18** | `_cachedLayoutCalculationsByKey` 0x8, `_delegate` (weak) **0x10**, `_validityToken` **0x18** |
| Token | `_appLayoutsGenCount` 0x8, `_switcherInterfaceOrientation` 0x10, `_modifierEventGenCount` 0x18, `_containerViewBounds` 0x20 | `_appLayoutsGenCount` 0x8, **`_continuousExposeIdentifiersGenCount` 0x10 (new)**, `_switcherInterfaceOrientation` 0x18, `_modifierEventGenCount` 0x20, `_containerViewBounds` 0x28 |

### 16.0 behaviour

```objc
// 160 0x1c63012cc
- (id)init { if ((self = [super init])) _cachedLayoutCalculationsByKey = @{}; return self; }          // __NSDictionary0
// 160 0x1c630132c
- (CGRect)frameForKey:(id)key validityToken:(id)token fallback:(CGRect (^)(void))fallback {
    [self _updateLayoutCalculationsIfNecessaryForValidityToken:token];          // 160 0x1c630158c
    SBSwitcherLayoutCalculations *c = _cachedLayoutCalculationsByKey[key];
    if (c) return [c frame];
    os_log_info(SBLogAppSwitcher(), "Cache didn't have layoutCalculations for key %@", key);
    return fallback();
}
// 160 0x1c630146c  scaleForKey:validityToken:fallback:  same with -scale (double), fallback returns double
// 160 0x1c630158c
- (void)_updateLayoutCalculationsIfNecessaryForValidityToken:(id)token {
    if (![_validityToken isEqual:token]) {                                      // isEqual: sent to the OLD token (nil -> NO -> rebuild)
        id delegate = self.delegate;                                            // weak
        NSAssert(delegate, @"Must have set delegate by now");                   // SBSwitcherLayoutCalculationsCache.m
        _cachedLayoutCalculationsByKey = [delegate buildLayoutCalculations];    // 16.0 delegate method, no argument
        _validityToken = token;                                                 // objc_storeStrong
    }
}
// token init (160 0x1c630184c): initWithAppLayoutsGenCount:switcherInterfaceOrientation:containerViewBounds:modifierEventGenCount:
// token isEqual: (160 0x1c63018d4): same class && appLayoutsGenCount == && orientation == && CGRectEqualToRect(bounds) && modifierEventGenCount ==
```

### 16.2 behaviour (verified in disassembly)

```objc
// 162 0x1c779ebf8   -init                       identical to 16.0
// 162 0x1c779ec58   -frameForKey:validityToken:fallback:   identical except it calls [self rebuildIfNecessaryForValidityToken:token]
// 162 0x1c779ed98   -scaleForKey:validityToken:fallback:   identical except same renamed call
// 162 0x1c779eeb8   NEW name for 160's _updateLayoutCalculationsIfNecessaryForValidityToken:
- (void)rebuildIfNecessaryForValidityToken:(SBSwitcherLayoutCalculationsCacheValidityToken *)token {
    if (![_validityToken isEqual:token]) {
        id<SBSwitcherLayoutCalculationsCacheDelegate> d = self.delegate;
        NSAssert(d, @"Must have set delegate by now");      // SBSwitcherLayoutCalculationsCache.m line 0x36 = 54
        _cachedLayoutCalculationsByKey = [d buildLayoutCalculationsForCache:self];     // <- the only API change: the cache passes itself
        _validityToken = token;
    }
}
// 162 0x1c779efdc   -validityToken   plain getter (readonly property)
// 162 0x1c779efa4 / 0x1c779efd0  -delegate / -setDelegate:   weak ivar accessors (objc_loadWeakRetained / objc_storeWeak)

// token, 162 0x1c779f184
- (instancetype)initWithAppLayoutsGenCount:(NSUInteger)appLayoutsGen
       continuousExposeIdentifiersGenCount:(NSUInteger)ceIdsGen                  // NEW
              switcherInterfaceOrientation:(NSInteger)orientation
                       containerViewBounds:(CGRect)bounds
                     modifierEventGenCount:(NSUInteger)eventGen;
// token isEqual: 162 0x1c779f210  (compared in this order)
//   self == other -> YES; ![other isKindOfClass:token class] -> NO;
//   _appLayoutsGenCount, _continuousExposeIdentifiersGenCount (0x10), _switcherInterfaceOrientation (0x18) as integers,
//   CGRectEqualToRect(_containerViewBounds), _modifierEventGenCount (0x20).
```
`SBSwitcherLayoutCalculationsCacheDelegate` required method: 160 `-buildLayoutCalculations`, 162 `-buildLayoutCalculationsForCache:`.
No `hash` override in either build.

So functionally the cache is unchanged. What changed is **what invalidates it**: the 16.2 token also carries the strip identifier list
generation (`-[SBFluidSwitcherViewController continuousExposeIdentifiersGenerationCount]`), so a re-order / insertion of strip groups
that does not change `appLayoutsGenerationCount` now rebuilds the layout dictionary. (Who calls it: `SBStripContinuousExposeSwitcherModifier -_currentLayoutCalculationsValidityToken`
162 0x1c75dfacc and `SBAppSwitcherContinuousExposeSwitcherModifier` 0x1c7812878; the latter also calls `rebuildIfNecessaryForValidityToken:` directly from
`_boundingFrameForPileWithIdentifier:withScrollOffsetApplied:` 0x1c7813800.)

Bug fixed (confidence high for the mechanism, medium for the user-visible symptom): stale strip frames/scales after the strip identifier set
changes without an app-layout generation change (identifier-only re-order from `SBContinuousExposeIdentifiersChangedModifierEvent`; the
16.0 `SBFullScreenContinuousExposeSwitcherModifier` used `appLayoutsGenCount` only).

### PORTABILITY (A1)

PORTABLE, without touching the system cache class' layout:
1. Keep using the 16.0 cache class. Add `%new -rebuildIfNecessaryForValidityToken:` that forwards to `_updateLayoutCalculationsIfNecessaryForValidityToken:` (so ported 16.2 code runs unchanged)
   and `%new -validityToken` that reads the ivar `_validityToken` by name (`class_getInstanceVariable` / `object_getIvar`, never an offset; the offset differs between builds: 0x10 vs 0x18).
2. The 16.0 cache sends `buildLayoutCalculations` (no argument). The new delegate classes (the ported strip modifier) implement `-buildLayoutCalculations`
   as `return [self buildLayoutCalculationsForCache:nil]` (or pass `[self layoutCache]`), so both API forms exist on the same object.
   The cache only uses the token through `isEqual:` / `objc_storeStrong`, therefore any object with a correct `isEqual:` is accepted.
3. New class `BP162SwitcherLayoutCalculationsCacheValidityToken` (full reconstruction in the hooks file, 5 fields, `isEqual:` as above, plus `hash` for safety).
   16.0's `SBSwitcherLayoutCalculationsCacheValidityToken` cannot get the extra field (no ivar addition); do not hook its init.
4. Alternative if the original 4 argument token must keep working for the old 16.0 FullScreen modifier: nothing to do, it keeps working untouched.

Not portable: nothing in this item.

---------------------------------------------------------------------------------------------------

## A2. Context-provider selectors (who implements them, where the data comes from)

All are `SBSwitcherContextProviding` selectors, new in 16.2 (see the table in section 0). The final provider is
`SBFluidSwitcherViewController` (VC); several are overridden by modifiers in the chain. "ivar" names are the real ones.

### A2.1 Implementers (162 addresses) and 16.0 equivalent

| selector | VC impl (162) | overrides in modifiers (162) | 16.0 equivalent |
|---|---|---|---|
| `continuousExposeIdentifiersInStrip` | 0x1c74373dc: returns ivar `_continuousExposeIdentifiersInStrip` (162 +0x630, `NSArray`) | `SBOverrideContinuousExposeIdentifiersSwitcherModifier` 0x1c798bda8: `return _overrideContinuousExposeIdentifiersInStrip ?: [super continuousExposeIdentifiersInStrip]` (ivar +0x68; class is new in 162, `initWithContinuousExposeIdentifiersInSwitcher:continuousExposeIdentifiersInStrip:`) | none; the only id list was `continuousExposeIdentifiers` (NSOrderedSet, VC 160 0x1c5fbed10, ivar `_continuousExposeIdentifiers` 0x618) |
| `continuousExposeIdentifiersInSwitcher` | 0x1c74373cc: ivar `_continuousExposeIdentifiersInSwitcher` (162 +0x628) | `SBOverrideContinuousExposeIdentifiersSwitcherModifier` 0x1c798bd44 (same pattern, ivar +0x60) | same as above |
| `continuousExposeStripProgress` | 0x1c7436c2c: `(_continuousExposeStripsPresentationOptions & 1) ? 1.0 : 0.0` (byte test of ivar 162 +0x640) | `SBFullScreenContinuousExposeSwitcherModifier` 0x1c75c2d14: `(![self _anyItemExceedsWidthThresholdToHideStrip] && ![self prefersStripHidden]) ? 1.0 : [self _continuousExposeStripRevealProgress]`; `SBHomeScreenContinuousExposeSwitcherModifier` 0x1c77f3e60: `0.0`; `SBRevealContinuousExposeStripsGestureModifier` 0x1c7817520: returns a double ivar (gesture progress); `SBContinuousExposeWindowDragSwitcherModifier` 0x1c760a11c: `p = [super ...]; if ([self _anyItemExceedsWidthThresholdToHideStrip] && ![proposedAppLayout containsItem:selectedItem] && [initialAppLayout containsItem:selectedItem]) p = 1.0; return p;` | `continuousExposeAppStripUnoccludedProgress` VC 160 0x1c5fbe5c0: **identical expression** on the same ivar (`_continuousExposeStripsPresentationOptions`, 160 +0x628) |
| `requireStripContentsInViewHierarchy` | 0x1c7436c4c: `return NO` | `SBTransitionSwitcherModifier` 0x1c746a124: `return YES`, `SBGestureSwitcherModifier` 0x1c7828710: `return YES` | none (16.0 strip contents were always in the hierarchy while ids existed) |
| `appLayoutOnContinuousExposeStage` | 0x1c74388d0: `return nil` | `SBContinuousExposeRootSwitcherModifier` 0x1c7819c3c: returns ivar `_effectiveAppLayoutOnStage` (root +0x68), `SBContinuousExposeWindowDragSwitcherModifier` 0x1c760a10c: `return [_<ivar> proposedAppLayout]` (tail call into an object ivar, the window-drag's destination helper) | none; stage membership was `containsAnyItemFromAppLayout:_fullScreenAppLayout` inside the full screen CE modifier |
| `continuousExposeIdentifiersGenerationCount` | 0x1c74364a4: returns ivar `_continuousExposeIdentifiersGenerationCount` (162 +0x4b8) | none | 160 ivar `_continuousExposeIdentifiersChangedGenerationCount` (+0x630) was only used as the event's `generationCount` |
| `newContinuousExposeIdentifiersGenerationCount` | 0x1c74364b4: `return ++_continuousExposeIdentifiersGenerationCount` | none | 160 inlined `++_continuousExposeIdentifiersChangedGenerationCount` in `_updateContinuousExposeIdentifiers...` |
| `layoutRestrictionInfoForItem:` | 0x1c74371c8: `return [[self displayItemLayoutAttributesCalculator] layoutRestrictionInfoForItem:item]` | - | the calculator was called directly by the modifiers |
| `supportedContentInterfaceOrientationsForItem:` | 0x1c7436408: `[[[self dataSource] switcherContentController:self deviceApplicationSceneHandleForDisplayItem:item] supportedInterfaceOrientations]` | - | - |
| `continuousExposeStripTongueBackdropCaptureLayoutElement` | 0x1c743690c: ivar `_continuousExposeStripTongueBackdropCaptureLayoutElement` (162 +0x668) | - | none (tongue is new, see B) |
| `draggingAppLayoutsForContinuousExposeWindowDrag` | 0x1c74388d8: `[[[self _delegate-weak] switcherCoordinator] draggingAppLayouts]` | - | none (cross-display window drag, new) |
| `proposedAppLayoutsForContinuousExposeWindowDrag` | 0x1c7438944: set; `[[switcherCoordinator] enumerateSwitcherControllersWithBlock:^(SBSwitcherController *c, BOOL *stop){ SBFluidSwitcherViewController *vc = BSSafeCast(@"SBFluidSwitcherViewController", [c contentViewController]); id l = [[vc rootModifier] proposedAppLayoutForContinuousExposeWindowDrag]; if (l) [set addObject:l]; }]` | - | none |

`appLayoutsForContinuousExposeIdentifier:` exists in both builds on the VC (160 0x1c5fbed20 / 162 0x1c74373ec). Both:
```objc
NSArray *r = _appLayoutsForContinuousExposeIdentifiers[identifier];           // dictionary cache, cleared (set to nil) on every identifier update
if (!r) { NSMutableArray *a = [NSMutableArray new];
          for (SBAppLayout *l in [self _unadjustedAppLayouts]) if ([[l continuousExposeIdentifier] isEqualToString:identifier]) [a addObject:l];
          cache = [(cache ?: @{}) bs_dictionaryByAddingEntriesFromDictionary:@{identifier : a}]; r = a; }
return r;
```
**But in 16.0 `SBContinuousExposeRootSwitcherModifier -appLayoutsForContinuousExposeIdentifier:` (160 0x1c6372158) sat in front of it and re-ordered / filtered the pile
(`adjustedAppLayoutsForAppLayouts:` 0x1c63721d0, `_adjustedAppLayoutsForAppLayouts:` 0x1c6372784), all deleted in 162 (the filtering by stage moved into the strip modifier,
`_isAppLayoutEffectivelyOnStage:`).** That is the modifier group's business; for the data layer it means: the VC list is the unfiltered list in both builds.

### A2.2 Where the strip id lists come from

16.0: VC `_updateContinuousExposeIdentifiersTransitioningFromAppLayout:toAppLayout:animated:` (160 0x1c5fde0d0):
```objc
if (![self isChamoisWindowingUIEnabled]) return;
NSMutableOrderedSet *ids = [NSMutableOrderedSet new];
for (SBAppLayout *l in [self _unadjustedAppLayouts]) [ids addObject:[l continuousExposeIdentifier]];
_continuousExposeIdentifiers = [_rootModifier adjustedContinuousExposeIdentifiersForIdentifiers:ids];   // root CE modifier 160 0x1c6372248
_appLayoutsForContinuousExposeIdentifiers = nil;
++_continuousExposeIdentifiersChangedGenerationCount;
if (animated) { event = [[SBContinuousExposeIdentifiersChangedModifierEvent alloc] initWithPreviousContinuousExposeIdentifiers:oldIds ?: [NSOrderedSet orderedSet]
                                                                            transitioningFromAppLayout:from transitioningToAppLayout:to generationCount:_gen];
                [self _dispatchEventAndHandleAction:event]; }
```
16.2 (`0x1c7457450`, 69 insns):
```objc
- (void)_updateContinuousExposeIdentifiersTransitioningFromAppLayout:(SBAppLayout *)from toAppLayout:(SBAppLayout *)to animated:(BOOL)animated {
    if (![self isChamoisWindowingUIEnabled]) return;
    NSArray *prevInSwitcher = _continuousExposeIdentifiersInSwitcher ?: @[];          // __NSArray0
    NSArray *prevInStrip    = _continuousExposeIdentifiersInStrip    ?: @[];
    _continuousExposeIdentifiersInStrip    = [_rootModifier adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:prevInStrip];
    _continuousExposeIdentifiersInSwitcher = [_rootModifier adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:prevInSwitcher
                                                                                                                       identifiersInStrip:_continuousExposeIdentifiersInStrip];
    [self newContinuousExposeIdentifiersGenerationCount];                              // ++gen (result unused)
    _appLayoutsForContinuousExposeIdentifiers = nil;
    event = [[SBContinuousExposeIdentifiersChangedModifierEvent alloc] initWithPreviousContinuousExposeIdentifiersInSwitcher:prevInSwitcher
                                                                           previousContinuousExposeIdentifiersInStrip:prevInStrip
                                                                                           transitioningFromAppLayout:from
                                                                                             transitioningToAppLayout:to
                                                                                                             animated:animated];   // event is now ALWAYS dispatched (16.0: only if animated)
    [self _dispatchEventAndHandleAction:event];
}
```
Differences: (1) two lists (strip vs switcher) instead of one ordered set; (2) the 16.0 list was built from unadjusted layouts' ids, in 16.2 the modifier builds
the list itself from `[self appLayouts]` and the previous lists (persisting user order); (3) the event is always dispatched and the event class has a different
init (`animated:` flag, two previous lists; the 160 class had `previousContinuousExposeIdentifiers` + `generationCount`).

The 16.2 list builders are `SBAppSwitcherContinuousExposeSwitcherModifier` methods (modifier layer, ~330 and ~60 instructions; reconstructed in the modifier group's spec, only the verified outline is given here):
* `-adjustedContinuousExposeIdentifiersInSwitcherFromPreviousIdentifiersInSwitcher:identifiersInStrip:` (162 0x1c7811880), fully read (the 2nd argument, previous switcher ids, is NOT used; the 3rd, `strip`, is):
  ```objc
  NSMutableArray *r = [NSMutableArray new];
  NSString *stageId = [[self appLayoutOnContinuousExposeStage] continuousExposeIdentifier];
  if (stageId && ![strip containsObject:stageId]) [r insertObject:stageId atIndex:0];
  [r addObjectsFromArray:strip];
  for (SBAppLayout *l in [self appLayouts]) {
      NSString *i = [[self appLayoutContainingAppLayout:l] continuousExposeIdentifier];
      if (!BSEqualStrings(i, stageId) && ![r containsObject:i]) [r addObject:i];     // note: BSEqualStrings(i, stageId) skips the stage group even when it is in `strip`
  }
  return r;      // switcher list = [stage id] + strip ids + every other id, in appLayouts (recency) order
  ```
* `-adjustedContinuousExposeIdentifiersInStripFromPreviousIdentifiersInStrip:` (162 0x1c7811a50), verified outline: collects distinct `continuousExposeIdentifier`s of `appLayoutContainingAppLayout:` for each of `[self appLayouts]`, skipping layouts for which
  `[stageLayout containsAnyItemFromAppLayout:]` is true, and stops as soon as the collection reaches `[[self chamoisLayoutAttributes] numberOfRowsWhileInApp]` (the same attribute 16.0's VC `numberOfVisibleContinuousExposeIdentifiersWhileInApp` returned,
  160 0x1c5fbecd8); then re-merges the result with the previous strip ids (preserving the previous relative order: `bs_filter:` of the previous list by membership, pairwise `replaceObjectAtIndex:withObject:` / `removeObject:`) and
  special-cases the stage group id (`appLayoutsForContinuousExposeIdentifier:` count == 1 -> compares with the stage layout via `isOrContainsAppLayout:`; otherwise inserts the stage id at index 0, dropping the last element when the cap is reached).
* `SBRoutingSwitcherModifier` (0x1c7532ca4 / 0x1c7532ab4) forwards both queries down the chain; the Deck/Grid/MixedGrid/ShelfCarousel/_GridFloor modifiers (0x1c77b2ccc ... ) pass the argument through.
  The VC calls them on `_rootModifier`, so the whole modifier stack takes part.

Bug / behaviour fixed (confidence medium): 16.0 recomputed the id set from scratch on every layout change and filtered by `numberOfVisibleContinuousExposeIdentifiersWhileInApp` inside the strip; in 16.2 the
strip list is stable (previous order preserved), capped at construction time, and the strip and the app-switcher/Expose list can differ.

### A2.3 PORTABILITY

* `continuousExposeStripProgress`, `requireStripContentsInViewHierarchy`, `continuousExposeIdentifiersGenerationCount`, `newContinuousExposeIdentifiersGenerationCount`,
  `continuousExposeIdentifiersInStrip`/`InSwitcher`, `layoutRestrictionInfoForItem:`, `supportedContentInterfaceOrientationsForItem:`: PORTABLE as `%new` methods on the 16.0 VC.
  The data they return that has no 16.0 ivar (`InStrip`, `InSwitcher`, the generation count) lives in associated objects on the VC (`kBP_G2_VCState`); the generation count could reuse
  `_continuousExposeIdentifiersChangedGenerationCount` by name but its meaning is the same and it is already bumped by the 16.0 update method, so the port simply returns it (`continuousExposeIdentifiersGenerationCount`)
  and implements `newContinuousExposeIdentifiersGenerationCount` as `++` on that ivar found by name (`BP_G2_SetIvarRaw`).
* `continuousExposeStripProgress` on the VC: forward to `continuousExposeAppStripUnoccludedProgress` (identical, verified).
* Modifier-side overrides (Transition/Gesture YES, FullScreen/HomeScreen/RevealStrips/WindowDrag progress, Root stage layout, Override* identifier modifiers): these are methods on 16.0 classes that EXIST
  (`SBTransitionSwitcherModifier`, `SBGestureSwitcherModifier`, `SBHomeScreenContinuousExposeSwitcherModifier`, `SBContinuousExposeRootSwitcherModifier`, `SBContinuousExposeWindowDragSwitcherModifier`)
  except `SBOverrideContinuousExposeIdentifiersSwitcherModifier`, which is NEW (class does not exist in 16.0; its 16.0 counterpart is probably `SBOverrideAppLayoutsSwitcherModifier -continuousExposeIdentifiers` 0x1c5f9a898, UNSURE). All
  except the new class can be added as `%new`/hook, but ONLY if the section-0 protocol extension is active, otherwise they are never called through the chain.
  The Root modifier's `_effectiveAppLayoutOnStage` is a new ivar on a system class: associated object `kBP_G2_RootStage` (the root's `+0x68` slot is `_currentAppLayout +0x60`'s neighbour in 16.0: do NOT write to it).
* `appLayoutOnContinuousExposeStage`: PARTIAL, needs the root modifier to track the effective stage layout (done in Root `handleTransitionEvent:`/`_effectiveEnvironmentMode` in 16.2; modifier group).
* `draggingAppLayoutsForContinuousExposeWindowDrag`, `proposedAppLayoutsForContinuousExposeWindowDrag`, `continuousExposeStripTongueBackdropCaptureLayoutElement`: NOT PORTABLE as a faithful copy: they depend on
  `SBMainSwitcherControllerCoordinator -draggingAppLayouts` / `-enumerateSwitcherControllersWithBlock:` (162 0x1c76e2df8 / 0x1c76e2214, both absent in 16.0, cross-display window dragging) and on the tongue view
  (`SBContinuousExposeStripTongueView`, absent in 16.0). Stub versions returning `nil` are safe (they only matter for cross-display drag / the tongue).
* The `_update...Identifiers...` rewrite (A2.2): PARTIAL. The 16.0 method can be hooked (`%hook SBFluidSwitcherViewController`) to additionally fill `InStrip`/`InSwitcher` using a C port of the two
  list builders (they only use public-in-tweak data: `appLayouts`, `appLayoutContainingAppLayout:`, `continuousExposeIdentifier`, `containsAnyItemFromAppLayout:`, `numberOfRowsWhileInApp`); the new event class
  (`initWithPreviousContinuousExposeIdentifiersInSwitcher:...animated:`) cannot be added as an ivar-extended 16.0 class, but is a plain `SBSwitcherModifierEvent` subclass: NEW class `BP162ContinuousExposeIdentifiersChangedEvent`
  (reconstruction in hooks file once the event dispatch table is understood; modifiers dispatch on `[event type]`, 162 0x1c76f4c10 returns the CE-identifiers-changed type constant, which must be read from the 16.0 event class).

---------------------------------------------------------------------------------------------------

## A3. SBChamoisOverlappingModel (+ SBMutableChamoisOverlappingModel)

The value object that the auto-layout controller (A4) produces and the calculator / modifiers read: for each `SBDisplayItem` of a stage it stores a center, size and
occlusion flags. 160 class 0x1de0a6e78, 162 0x1dd7ecad8; mutable subclass `SBMutableChamoisOverlappingModel` (160 0x1de0a6ea0, 162 0x1dd7ecb00).

### ivars

| ivar | 160 offset | 162 offset |
|---|---|---|
| `_items` (NSMutableArray), `_centersForItems`, `_sizesForItems` (NSMutableDictionary of NSValue), `_userConfiguredSizesBeforeAutoResizingForItems` | 0x8, 0x10, 0x18, 0x20 | same |
| `_unoccludedPeekingCentersForItems` | - | 0x28 (new) |
| `_coveredForItems` (item -> NSNumber BOOL) | - | 0x30 (new) |
| `_partiallyOccludedForItems`, `_fullyOccludedForItems` | 0x28, 0x30 | 0x38, 0x40 |
| `_overlappingScaleAnchorCentersForItems` | - | 0x48 (new) |
| `_widthThresholdToHideStrip` (double) | - | 0x50 (new) |
| `_compactedCentersForItems` | - | 0x58 (new) |
| `_containerBounds` (CGRect) | 0x38 | 0x60 |
| `_stageArea` (CGRect) | - | 0x80 (new) |
| `_boundingBox` (CGRect) | 0x58 | 0xa0 |
| `_compactedBoundingBox` (CGRect) | - | 0xc0 (new) |
| `_stageAreaForResizing` (CGRect) | - | 0xe0 (new) |

(160 total size 0x78, 162 0x100.)

### New / changed API (162 addresses), all reconstructed from disassembly

```objc
// 0x1c797a010  designated init. 160: -initWithItems:centersForItems:sizesForItems:userConfiguredSizesBeforeAutoResizingForItems:containerBounds:boundingBox:  (0x1c64bf918)
- (instancetype)initWithItems:(NSArray *)items centersForItems:(NSDictionary *)centers sizesForItems:(NSDictionary *)sizes containerBounds:(CGRect)bounds {
    self = [super init];
    if (self) {
        NSParameterAssert(items); NSParameterAssert(centers); NSParameterAssert(sizes);          // cbz -> assertion paths
        _items = [items mutableCopy]; _centersForItems = [centers mutableCopy]; _sizesForItems = [sizes mutableCopy];
        _userConfiguredSizesBeforeAutoResizingForItems = [NSMutableDictionary new];              // 16.0 copied a passed-in dictionary; 16.2 starts empty
        _unoccludedPeekingCentersForItems = [NSMutableDictionary new];
        _partiallyOccludedForItems = [NSMutableDictionary new];  _fullyOccludedForItems = [NSMutableDictionary new];  _coveredForItems = [NSMutableDictionary new];
        _overlappingScaleAnchorCentersForItems = [NSMutableDictionary new];
        _widthThresholdToHideStrip = 0;  _compactedCentersForItems = [NSMutableDictionary new];
        _containerBounds = bounds;       // _boundingBox / _stageArea / _compactedBoundingBox / _stageAreaForResizing = CGRectZero (set later by the controller)
    }
    return self;
}
// 0x1c797a298 centerForItem:               [[_centersForItems objectForKey:item] CGPointValue]            (unchanged)
// 0x1c797a2e4 sizeForItem:                 [[_sizesForItems objectForKey:item] CGSizeValue]               (unchanged)
// 0x1c797a330 userConfiguredSizeBeforeOverlappingForItem:  [_userConfiguredSizesBeforeAutoResizingForItems[item] CGSizeValue]   (unchanged)
// 0x1c797a37c unoccludedPeekingCenterForItem:   [_unoccludedPeekingCentersForItems[item] CGPointValue]       NEW
// 0x1c797a3c8 overlappingScaleAnchorCenterForItem: [_overlappingScaleAnchorCentersForItems[item] CGPointValue]  NEW
// 0x1c797a6e0 compactedCenterForItem:      [_compactedCentersForItems[item] CGPointValue]                 NEW
// 0x1c797a414 isItemPartiallyOccluded:     [_partiallyOccludedForItems[item] boolValue]                   (unchanged)
// 0x1c797a480 isItemFullyOccluded:         [_fullyOccludedForItems[item] boolValue]                       (unchanged)
// 0x1c797a4ec isItemCoveredByFullyOccludedPeekingItem:  [_coveredForItems[item] boolValue]                 NEW
// 0x1c797a558 isContinuousExposeStripVisible  NEW:
- (BOOL)isContinuousExposeStripVisible {
    for (SBDisplayItem *item in _items)
        if (BSFloatGreaterThanOrEqualToFloat([self sizeForItem:item].width, [self widthThresholdToHideStrip])) return NO;   // any window at least as wide as the threshold hides the strip
    return YES;                                                                                                              // (no items -> YES)
}
// 0x1c797a680 modelByModifyingModelWithBlock:  mc = [self mutableCopy]; block(mc); return mc;                 (unchanged)
// 0x1c797a72c mutableCopyWithZone:  m = [SBMutableChamoisOverlappingModel new]; copies (mutableCopy) items, centers, sizes, userConfiguredSizes, unoccludedPeekingCenters,
//   overlappingScaleAnchorCenters, covered, partiallyOccluded, fullyOccluded, compactedCenters; copies containerBounds, stageArea, boundingBox, widthThresholdToHideStrip,
//   compactedBoundingBox, stageAreaForResizing; returns m.
// 0x1c797afe4 boundingBox / 0x1c797afcc stageArea / 0x1c797b00c compactedBoundingBox / 0x1c797b038 stageAreaForResizing: plain getters (+ setters).
```
`SBMutableChamoisOverlappingModel` (all mutators are `[[self <dictGetter>] setObject:<boxed value> forKey:item]`, no copy-on-write):
`addItem:withCenter:size:` 0x1c797b0f4 (insert at index 0 if not present, then `setCenter:forItem:` + `setSize:forItem:`), `setCenter:forItem:` 0x1c797b1b0, `setSize:forItem:` 0x1c797b248,
`setUserConfiguredSizeBeforeOverlapping:forItem:` 0x1c797b2e0 (these 4 exist in 160), and NEW `setUnoccludedPeekingCenterForItem:forItem:` 0x1c797b378,
`setOverlappingScaleAnchorCenter:forItem:` 0x1c797b410, `setCoveredByFullyOccludedPeekingItem:forItem:` 0x1c797b4a8, `setCompactedCenter:forItem:` 0x1c797b658
(`setPartiallyOccluded:forItem:` 0x1c797b538 and `setFullyOccluded:forItem:` 0x1c797b5c8 exist in 160).

### What it fixes / is for (confidence medium)
* `isContinuousExposeStripVisible` + `widthThresholdToHideStrip`: the strip is hidden when any window is as wide as a threshold computed by the controller (A4,
  `_widthThresholdToHideContinuousExposeStripForModel:...`); 16.0 had no such model-level notion (it used `prefersStripHidden` and an unconditional strip). Needed by the 16.2 modifiers' `_anyItemExceedsWidthThresholdToHideStrip`.
* `stageArea`: the rectangle (container minus strip / dock / margins) windows are laid out in; 16.0 recomputed it from `initialStageFrame` in `modelForPreferredModel:`.
* `unoccludedPeekingCenters`, `coveredForItems`, `isItemCoveredByFullyOccludedPeekingItem:`: windows that are fully occluded "peek" out from behind the occluder at the screen edge; items beneath such a peeking item are flagged covered
  (A4 `_flagItemsCoveredByFullyOccludedPeekingItemsInModel:`). Fixes the 16.0 behaviour where fully hidden windows could not be reached/were drawn on top of each other.
* `compactedCenters` / `compactedBoundingBox`: layout with the horizontal/vertical spacing "compacted" (used while a window is being dragged/resized, A4).
* `overlappingScaleAnchorCenters`: anchor point for the scale-down of partially overlapping windows.

### PORTABILITY (A3)
* The 16.0 class already holds 16.2's `_items`, `_centersForItems`, `_sizesForItems`, `_userConfiguredSizes...`, `_partiallyOccludedForItems`, `_fullyOccludedForItems`, `_containerBounds`, `_boundingBox` (offsets differ; irrelevant because they are only accessed through
  the existing accessors).
* The 8 new ivars: **ivars cannot be added to the 16.0 class**. Chosen approach: ONE associated object (`BP162OverlapExtras`) per model instance holding the 4 dictionaries, the double and the 3 CGRects, with the new accessors/mutators
  added by `class_addMethod` (struct encodings written out). `mutableCopyWithZone:` (16.0 allocates the mutable class itself via `alloc init`, then copies by setters) is hooked to carry the extras over (deep copy of the dictionaries).
  The 4-argument `initWithItems:centersForItems:sizesForItems:containerBounds:` is added as a wrapper over the 16.0 6-argument init (passing `@{}` for the user-configured sizes and `CGRectZero` for the bounding box).
  Alternative considered: runtime subclass with real ivars + `+allocWithZone:` swizzle; rejected because mutableCopy hard-codes `SBMutableChamoisOverlappingModel` (second subclass needed) and because associated storage is only touched by the ported controller.
* PORTABLE (draft: hooks file, section A3). Costs: associated-object lookup per access (the controller makes tens of accesses per layout pass; negligible).
* Model equality is not defined (no `isEqual:`), so nothing else depends on layout.

---------------------------------------------------------------------------------------------------

## A4. SBChamoisOverlappingController (the Stage Manager auto-layout algorithm)

Stateless NSObject (162 class 0x1dd7d70c0; only ivar `_reentrancyGuard` BOOL at +0x8, new in 162). It turns a "preferred" `SBChamoisOverlappingModel` (window centers/sizes as the user left them)
into a resolved model: windows are sorted, grouped in columns, spacing is compacted / expanded to fit the stage area, windows that are completely hidden behind others are moved so a sliver "peeks" out,
and per-window occlusion / scale-anchor data for the renderer is produced. 162 total ~5.8k instructions (0x1c73c9b2c-0x1c73cf6.. ); 160 had 16 methods (0x1c5f550d0-0x1c5f595d0).

Old (160) API: `-modelForPreferredModel:initialStageFrame:layoutAttributes:draggingItem:modelBeforeDragging:` (160 0x1c5f550d0). The 160 pipeline was
`mc=[model mutableCopy]; mc.boundingBox=stageFrame; snap; sortedX; constrainH(to stageFrame); columns; constrainV; totalWidth; (if tw<bb.w shrink bb); compactV (no-op); compactH; expandH; expandV; verticalCenter; (!dragging)? hCenter + single item center=bbCenter; dodge; bb=_boundingBoxForModel recentered on stageFrame`
i.e. the stage frame was an INPUT chosen by the calculator; in 162 the controller derives the stage area itself (`_stageAreaForModel:...`), supports a `stageInset`, re-runs itself once if the resulting columns changed, and fills the new model fields.

New public API (162):
```objc
// 0x1c73c9b2c
- (SBChamoisOverlappingModel *)modelByPerformingAutoLayoutForModel:(SBChamoisOverlappingModel *)model
                                           chamoisLayoutAttributes:(SBSwitcherChamoisLayoutAttributes *)attrs
                                                      draggingItem:(SBDisplayItem *)dragging
                                               modelBeforeDragging:(SBChamoisOverlappingModel *)before
                                                floatingDockHeight:(double)dockH
                                                            bounds:(CGRect)bounds
                                                       screenScale:(double)scale
                                                prefersStripHidden:(BOOL)stripHidden
                                                 prefersDockHidden:(BOOL)dockHidden {
    return [self _modelByPerformingAutoLayoutForModel:model chamoisLayoutAttributes:attrs draggingItem:dragging modelBeforeDragging:before
                                   floatingDockHeight:dockH bounds:bounds screenScale:scale prefersStripHidden:stripHidden prefersDockHidden:dockHidden
                                           stageInset:UIEdgeInsetsZero];                    // *UIEdgeInsetsZero via GOT 0x1d83f15e8
}
```
Notation below: `Rgn(r)` = `CGRegionCreateWithRect(r)` + `CFAutorelease` (= `SBSafeAutoreleasedRegionFromCGRect`, 162 0x1c77fd474; nil-safe); `CGRegion*` are CoreGraphics SPI functions
(`CGRegionCreateUnionWithRegion/DifferenceWithRegion/IntersectionWithRegion`, `CGRegionIsEmpty`, `CGRegionGetBoundingBox`, `CGRegionEqualToRegion`, `CGRegionIntersectsRegion`; 162 stubs 0x1c9cd0250..0x1c9cd02c0).
`BSFloat*` = BaseBoard epsilon compares. `item rect` = `{center.x - size.w/2, center.y - size.h/2, size.w, size.h}`. Items order: `model.items` is FRONT-TO-BACK (mutable `addItem:` inserts at index 0).

### A4.1 `_modelByPerformingAutoLayoutForModel:...stageInset:` (162 0x1c73c9b6c, ~750 insns), verified line by line

```objc
- (id)_modelByPerformingAutoLayoutForModel:(model) chamoisLayoutAttributes:(attrs) draggingItem:(dragging) modelBeforeDragging:(before)
                        floatingDockHeight:(double)dockH bounds:(CGRect)bounds screenScale:(double)scale
                        prefersStripHidden:(BOOL)ps prefersDockHidden:(BOOL)pd stageInset:(UIEdgeInsets)inset {   // inset passed on the stack: top,left,bottom,right
    if (!model || [[model items] count] == 0) return nil;
    SBMutableChamoisOverlappingModel *mc = [model mutableCopy];
    double thr = [self _widthThresholdToHideContinuousExposeStripForModel:mc chamoisLayoutAttributes:attrs bounds:bounds];
    CGRect r = [self _stageAreaForModel:mc chamoisLayoutAttributes:attrs floatingDockHeight:dockH bounds:bounds prefersStripHidden:ps prefersDockHidden:pd
                         widthThresholdToHideContinuousExposeStrip:thr];
    CGRect stage = CGRectMake(r.origin.x + inset.left, r.origin.y + inset.top, r.size.width - (inset.left + inset.right), r.size.height - (inset.top + inset.bottom));
    [mc setContainerBounds:bounds];  [mc setStageArea:stage];  [mc setWidthThresholdToHideStrip:thr];
    [self _snapPositionToNearestEdgesIfNecessary:mc draggingItem:dragging];
    NSArray *sorted = [self _itemsSortedByXInModel:mc modelBeforeDragging:before chamoisLayoutAttributes:attrs draggingItem:dragging];
    [self _constrainModelHorizontally:mc toStageArea:stage];
    NSArray *cols = [self _columnsOfItemsSortedByXInModel:mc withItemsSortedByX:sorted modelBeforeDragging:before chamoisLayoutAttributes:attrs draggingItem:dragging];
    [self _constrainModelVertically:mc toStageArea:stage];
    double tw = [self _totalWidthOfColumns:cols inModel:mc chamoisLayoutAttributes:attrs];                  // d9, kept in [sp+0x28]
    if (BSFloatLessThanFloat(tw, stage.size.width)) {                                                        // content narrower than the stage: shrink the stage area to the content and centre it
        double rightGap = bounds.size.width - (stage.origin.x + stage.size.width);                           // d8
        double shift = (stage.size.width - tw) * 0.5;
        if (BSFloatGreaterThanFloat(stage.origin.x, rightGap)) shift -= (stage.origin.x - rightGap) * 0.5;   // bias towards the screen centre when the left margin (strip side) is larger
        stage.origin.x += shift;  stage.size.width = tw;
    }
    [mc setStageArea:stage];
    [self _compactSpacingVerticallyForModel:mc withColumns:cols chamoisLayoutAttributes:attrs];              // no-op body in 162
    [self _compactSpacingHorizontallyForModel:mc withColumns:cols chamoisLayoutAttributes:attrs];
    [self _expandSpacingHorizontallyForModel:mc withColumns:cols modelBeforeDragging:before chamoisLayoutAttributes:attrs draggingItem:dragging stageArea:stage];
    [self _expandSpacingVerticallyForModel:mc withColumns:cols chamoisLayoutAttributes:attrs stageArea:stage];
    [self _verticallyCenterModel:mc withColumns:cols stageArea:stage];
    if (!dragging) {
        [self _horizontallyCenterModel:mc stageArea:stage];
        if ([[mc items] count] == 1) { SBDisplayItem *only = [[mc items] firstObject];
            CGPoint c = [mc centerForItem:only];  CGPoint sc = UIRectGetCenter(stage);
            [mc setCenter:CGPointMake(c.x, sc.y) forItem:only]; }                                            // single window: keep x, centre y on the stage
    }
    [self _dodgeFullyOccludedWindowsToNearestVisibleEdgeInModel:mc chamoisLayoutAttributes:attrs draggingItem:dragging bounds:bounds];
    if (!_reentrancyGuard) {
        // 1. columns changed after the dodge pass? -> run the whole layout once more on the result
        NSArray *sorted2 = [self _itemsSortedByXInModel:mc modelBeforeDragging:before chamoisLayoutAttributes:attrs draggingItem:dragging];
        NSArray *cols2 = [self _columnsOfItemsSortedByXInModel:mc withItemsSortedByX:sorted2 modelBeforeDragging:before chamoisLayoutAttributes:attrs draggingItem:dragging];
        if (![self _isColumnOfItems:cols equalToColumnOfItems:cols2]) {
            _reentrancyGuard = YES;
            mc = [[self _modelByPerformingAutoLayoutForModel:mc ... same arguments ... stageInset:inset] mutableCopy];
            _reentrancyGuard = NO;
        }
        // 2. only when the caller passed UIEdgeInsetsZero: if some windows are fully occluded and peeking at a screen edge (and NO window is exactly the container size)
        //    the stage area is inset by stageOcclusionDodgingPeekLength on that side and the layout is run again.
        if (UIEdgeInsetsEqualToEdgeInsets(inset, UIEdgeInsetsZero)) {
            BOOL anyFull = NO, anyFullScreen = NO;
            for (item in mc.items) { anyFull |= [mc isItemFullyOccluded:item]; CGSize s = [mc sizeForItem:item]; anyFullScreen |= (s.width == bounds.size.width && s.height == bounds.size.height); }
            if (!anyFullScreen && anyFull) {
                double peekScale = [attrs stageOcclusionDodgingPeekScale], pad = [attrs screenEdgePadding], peekLen = [attrs stageOcclusionDodgingPeekLength];
                double leftInset = 0, rightInset = 0;
                for (item in mc.items) if ([mc isItemFullyOccluded:item]) {
                    CGPoint pc = [mc unoccludedPeekingCenterForItem:item];
                    if (pc.x == 0 && pc.y == 0) continue;                                          // (CGPointZero from GOT 0x1d83e1c50) -> no peek position
                    double half = [mc sizeForItem:item].width * 0.5 * peekScale;
                    if (BSFloatLessThanFloat(pc.x - half, pad)) leftInset = peekLen;               // item peeks at the left edge
                    else if (BSFloatGreaterThanFloat(pc.x + half, bounds.size.width - pad)) rightInset = peekLen;   // ... right edge
                }
                if (leftInset != 0 || rightInset != 0) {
                    _reentrancyGuard = YES;
                    mc = [[self _modelByPerformingAutoLayoutForModel:mc ... same ... stageInset:UIEdgeInsetsMake(0, leftInset, 0, rightInset)] mutableCopy];
                    _reentrancyGuard = NO;
                }
            }
        }
    }
    // overlapping scale anchors
    NSDictionary *anchors = [self _overlappingScaleAnchorCentersForModel:mc chamoisLayoutAttributes:attrs];
    for (item in mc.items) [mc setOverlappingScaleAnchorCenter:[anchors[item] CGPointValue] forItem:item];
    // bounding boxes (plain and "compacted")
    double compact = [attrs switcherPileCompactingFactor];
    CGPoint bc = UIRectGetCenter(bounds);                                             // container centre
    CGRect bb = CGRectNull-ish accumulation (start at +/-DBL_MAX), cbb likewise;
    for (item in mc.items) {
        CGSize s = [mc sizeForItem:item];  CGPoint c; double k;
        if ([mc isItemFullyOccluded:item]) { c = [mc unoccludedPeekingCenterForItem:item]; k = [attrs stageOcclusionDodgingPeekScale]; }
        else { c = [mc centerForItem:item]; CGPoint a = [mc overlappingScaleAnchorCenterForItem:item];
               k = [mc isItemPartiallyOccluded:item] ? [attrs partiallyOccludedStageScaleForItemWithSize:s] : 1.0;
               c.x -= (c.x - a.x) * (1 - k);  c.y -= (c.y - a.y) * (1 - k); }                      // scale about the anchor
        CGRect rect = CGRectMake(c.x - s.width*k/2, c.y - s.height*k/2, s.width*k, s.height*k);   bb = union(bb, rect);
        CGPoint cc = CGPointMake(bc.x + compact*(c.x - bc.x), bc.y + compact*(c.y - bc.y));        // pull towards the container centre
        [mc setCompactedCenter:cc forItem:item];
        cbb = union(cbb, CGRectMake(cc.x - s.width*k/2, cc.y - s.height*k/2, s.width*k, s.height*k));
    }
    [mc setBoundingBox:UIRectRoundToScale(bb, scale)];   [mc setCompactedBoundingBox:UIRectRoundToScale(cbb, scale)];
    [self _flagItemsCoveredByFullyOccludedPeekingItemsInModel:mc chamoisLayoutAttributes:attrs];
    // stage area for resizing = stage area WITHOUT inset, centred around the (already centred) columns
    CGRect r2 = [self _stageAreaForModel:mc chamoisLayoutAttributes:attrs floatingDockHeight:dockH bounds:bounds prefersStripHidden:ps prefersDockHidden:pd widthThresholdToHideContinuousExposeStrip:thr];
    NSArray *s3 = [self _itemsSortedByXInModel:mc modelBeforeDragging:nil chamoisLayoutAttributes:attrs draggingItem:nil];
    NSArray *c3 = [self _columnsOfItemsSortedByXInModel:mc withItemsSortedByX:s3 modelBeforeDragging:nil chamoisLayoutAttributes:attrs draggingItem:nil];
    double w3 = r2.size.width;
    if ([c3 count] >= 2 && BSFloatLessThanFloat([self _totalWidthOfColumns:c3 inModel:mc chamoisLayoutAttributes:attrs], r2.size.width)) {
        double rightGap2 = bounds.size.width - (prevStage.x + prevStage.w);     // from the first pass values saved at [sp+0x30]/[sp+0x38] (stage.w, stage.x after the first shrink)
        double shift = (r2.size.width - tw) * 0.5;                              // tw = FIRST pass total width ([sp+0x28])
        if (BSFloatGreaterThanFloat(r2.origin.x, rightGap2)) shift -= (r2.origin.x - rightGap2) * 0.5;
        r2.origin.x += shift;  w3 = tw;
    }
    [mc setStageAreaForResizing:CGRectMake(r2.origin.x, r2.origin.y, w3, r2.size.height)];
    return mc;
}
```
UNSURE items: the `[sp+0x30/0x38]` values used for `rightGap2` are the first-pass shrunk stage width/x (stored at 0x1c73c9ebc); `UIRectRoundToScale` argument order (rect, scale). Everything else is a literal translation.

### A4.2 helpers (all 162 addresses; every selector/constant verified)

```objc
// 0x1c73caf94
- (double)_widthThresholdToHideContinuousExposeStripForModel:(m) chamoisLayoutAttributes:(a) bounds:(CGRect)b {
    if ([a usesStripAreaForOverlapping] && [[m items] count] >= 2) {
        cols = [self _columnsOfItemsSortedByXInModel:m withItemsSortedByX:[self _itemsSortedByXInModel:m modelBeforeDragging:nil chamoisLayoutAttributes:a draggingItem:nil]
                                 modelBeforeDragging:nil chamoisLayoutAttributes:a draggingItem:nil];
        if (BSFloatGreaterThanFloat([self _totalWidthOfColumns:cols inModel:m chamoisLayoutAttributes:a], b.size.width + [a screenEdgePadding] * -3.0)) return 0.0;   // never show the strip
    }
    double s = MIN([a stripWidth], (b.size.width - [a minimumDefaultWindowSize].width) * 0.5);
    double v = ([[m items] count] > 1) ? s : s * 0.5;
    return b.size.width - 2 * v;                         // a window at least this wide hides the strip (see A3 isContinuousExposeStripVisible)
}
// 0x1c73cb104
- (CGRect)_stageAreaForModel:(m) chamoisLayoutAttributes:(a) floatingDockHeight:(double)dockH bounds:(CGRect)b prefersStripHidden:(BOOL)ps prefersDockHidden:(BOOL)pd widthThresholdToHideContinuousExposeStrip:(double)thr {
    double pad = [a screenEdgePadding], strip = [a stripWidth], minW = [a minimumDefaultWindowSize].width, maxHDock = [a maximumWindowHeightWithDock];
    double maxItemW = -DBL_MAX; BOOL anyWide = NO, anyTall = NO, anyFull = NO;                  // w24, w23, w27 (sticky)
    double twoPad = 2*pad;
    for (item in [m items]) { CGSize s = [m sizeForItem:item]; maxItemW = MAX(maxItemW, s.width);
        if (!anyWide) anyWide = BSFloatGreaterThanOrEqualToFloat(s.width, thr);                              // sticky
        if (!anyTall) anyTall = BSFloatGreaterThanFloat(s.height, (b.size.height - dockH) - twoPad);           // sticky
        if (!anyFull) anyFull = BSFloatGreaterThanFloat(s.width, b.size.width - twoPad) ? BSFloatGreaterThanFloat(s.height, b.size.height - twoPad) : NO; }   // sticky
    if (anyFull) return CGRectMake(b.origin.x, b.origin.y, b.size.width, b.size.height);   // a (nearly) full-screen window: stage == container bounds
    double cap = MIN(strip, (b.size.width - minW) * 0.5);
    double stripSide = (ps && pd) ? 0 : pad;
    if (!ps) stripSide = anyWide ? pad : MIN(cap, (b.size.width - maxItemW) * 0.5);
    double otherSide = MIN(stripSide, pad);
    double height = pd ? (b.size.height - twoPad) : (anyTall ? (b.size.height - twoPad) : maxHDock);
    CGRect out;  out.origin.y = (ps && pd) ? 0 : pad;  out.size.height = (ps && pd) ? b.size.height : height;     // NOTE: bounds.origin.y is not added (container origin is 0)
    BOOL rtl = ([UIApp userInterfaceLayoutDirection] == UIUserInterfaceLayoutDirectionRightToLeft);
    out.origin.x = rtl ? otherSide : stripSide;  out.size.width = b.size.width - stripSide - otherSide;
    return out;
}
```
(`_stageAreaForModel`: fully decoded; the first FP argument is `floatingDockHeight`; the caller then applies `stageInset` to the returned rect.)

```objc
// 0x1c73cb40c  _snapPositionToNearestEdgesIfNecessary:draggingItem:   (unchanged vs 160 except bs_reverse instead of reverseObjectEnumerator)
- (void)_snap(m) draggingItem:(dragging) {
    if ([[m items] count] < 2) return;
    for (a in [[m items] bs_reverse]) for (b in [m items]) {
        if (dragging && ([dragging isEqual:a] || [dragging isEqual:b])) break;           // both tests jump to the same exit (UNSURE: 'break' vs 'continue', same in 160)
        if ([a isEqual:b]) continue;
        double aL=cx(a)-w(a)/2, bL=cx(b)-w(b)/2, aR=cx(a)+w(a)/2, bR=cx(b)+w(b)/2;
        if (fabs(aL - bL) < 44) setCenterX(b, aL + w(b)/2);          // left edges
        if (fabs(aR - bR) < 44) setCenterX(b, aR - w(b)/2);          // right edges
        similarly with cy/h: tops then bottoms (threshold 44.0 = 0x4046000000000000);
    }
}
// 0x1c73cb878  _itemsSortedByXInModel:modelBeforeDragging:chamoisLayoutAttributes:draggingItem:
//   n==1 -> return items.
//   byCenter = items sorted ascending by centerX; byMin = ascending by minX (cx-w/2); byMax = DESCENDING by maxX (cx+w/2)   (comparator blocks 0x1c73cbd64 / 0x1c73cbe18 / 0x1c73cbf14)
//   left = byMin.firstObject; right = byMax.firstObject
//   BOOL allow = YES;
//   if (dragging && [m.items containsObject:dragging] && before && [before.items containsObject:dragging]) {
//       double bx = [before centerForItem:dragging].x, nx = [m centerForItem:dragging].x;
//       if ([dragging isEqual:left] && BSFloatGreaterThanFloat(bx, nx)) allow = YES;
//       else if (![dragging isEqual:right]) allow = YES;
//       else allow = !BSFloatLessThanFloat(bx, nx);
//   }
//   NSArray *r = byCenter;
//   if (allow && ![r.firstObject isEqual:left]) {                       // pin the left-edge window first
//       if (!BSFloatEqualToFloat(minX(r.firstObject), minX(left)) || (dragging && [dragging isEqual:left])) r = [r sb_arrayByInsertingOrMovingObject:left toIndex:0];
//   }
//   if (![r.lastObject isEqual:right] && (!allow || ![left isEqual:right])) {   // pin the right-edge window last
//       if (!BSFloatEqualToFloat(maxX(r.lastObject), maxX(right)) || (dragging && [dragging isEqual:right])) r = [r sb_arrayByAddingOrMovingObject:right];
//   }
//   return r;
// 0x1c73cc00c  _constrainModelHorizontally:toStageArea:   for each item: x' = c.x; if (c.x - w/2 < stage.minX) x' = stage.minX + w/2; if (x' + w/2 > stage.maxX) x' = stage.maxX - w/2; setCenter(x', c.y)
// 0x1c73cc184  _constrainModelVertically:toStageArea:     same with y/h and stage.minY/maxY
```
`_columnsOfItemsSortedByXInModel:withItemsSortedByX:modelBeforeDragging:chamoisLayoutAttributes:draggingItem:` (0x1c73cc2fc):
```objc
gap = [attrs stageInterItemSpacing]; limit = [attrs maximumWindowHeightWithDock] + 2*gap;
NSMutableArray *columns = [NSMutableArray new], *col = nil; CGRegionRef colRegion = NULL;
for (item in sortedByX) {
    c = center(item); s = size(item);
    CGRegionRef reg = Rgn(CGRectMake(c.x - (s.w+gap)/2, c.y - (s.h+gap)/2, s.w + gap, s.h + gap));        // item grown by the gap
    if (col) {
        double iMin = c.x - s.w/2, iMax = c.x + s.w/2;  CGRect bb = CGRegionGetBoundingBox(colRegion); double cMin = bb.x, cMax = bb.x + bb.w;
        if ((BSFloatGreaterThanOrEqualToFloat(cMin, iMin) && BSFloatLessThanOrEqualToFloat(cMax, iMax)) ||      // column's x-range inside the item's
            (BSFloatGreaterThanOrEqualToFloat(iMin, cMin) && BSFloatLessThanOrEqualToFloat(iMax, cMax))) {      // or the item's inside the column's
            CGRegionRef u = CFAutorelease(CGRegionCreateUnionWithRegion(colRegion, reg));
            if (!CGRegionEqualToRegion(u, colRegion) && !CGRegionEqualToRegion(u, reg) && !BSFloatGreaterThanFloat(CGRegionGetBoundingBox(u).size.height, limit)) {
                [col addObject:item]; colRegion = u; continue; }
        }
    }
    col = [NSMutableArray arrayWithObject:item]; [columns addObject:col]; colRegion = reg;
}
// second phase: vertical order inside every column
for (col in columns) {
    [col sortUsingComparator:^(a,b){ return [@(cy(a)) compare:@(cy(b))]; }];             // block 0x1c73ccb80
    if ([col count] < 2) continue;
    NSArray *byC = [col sortedArrayUsingComparator: by centerY ascending];                // 0x1c73ccc2c
    NSArray *byT = [col sortedArrayUsingComparator: by minY (cy-h/2) ascending];          // 0x1c73ccce4
    NSArray *byB = [col sortedArrayUsingComparator: by maxY (cy+h/2) descending];         // 0x1c73ccde0
    top = byT.firstObject; bottom = byB.firstObject;
    same "allow"/pin logic as _itemsSortedByX but on y: result = byC; pin `top` to index 0 and `bottom` to the end;
    [col removeAllObjects]; [col addObjectsFromArray:result];
}
return columns;
```
```objc
// 0x1c73cced8
- (double)_totalWidthOfColumns:(cols) inModel:(m) chamoisLayoutAttributes:(a) { double gap=[a stageInterItemSpacing], t=0; for (i,col): w=max(width of items in col, 0); t = (i==0)? t+w : t+w+gap; return t; }
// 0x1c73cd068 _compactSpacingVertically...: loops over columns and does nothing (the body optimised away: only -count calls remain). Reproduce as a no-op.
// 0x1c73cd17c
- (void)_compactSpacingHorizontallyForModel:(m) withColumns:(cols) chamoisLayoutAttributes:(a) {
    if ([cols count] < 2) return;  gap = [a stageInterItemSpacing];
    sorted = [cols sortedArrayUsingComparator: by each column's minimum left edge (min over items of cx - w/2) ascending];      // block 0x1c73cd4ac
    double prevMax = -DBL_MAX;
    for (i, col in sorted) {
        minL = +DBL_MAX, maxR = -DBL_MAX over items (cx -/+ w/2);
        if (i != 0) { double g = minL - prevMax; if (BSFloatGreaterThanFloat(g, gap)) { double d = gap - g; for (item in col) setCenter(cx + d, cy); maxR += d; } }
        prevMax = MAX(prevMax, maxR);
    }
}
```
`_expandSpacingHorizontallyForModel:withColumns:modelBeforeDragging:chamoisLayoutAttributes:draggingItem:stageArea:` (0x1c73cd714), `stageArea` x=d0 (d10), w=d2 (d9):
```objc
if ([cols count] < 2) return;  gap = [a stageInterItemSpacing];
for (col in cols) for (item in col) if (BSFloatGreaterThanOrEqualToFloat([m sizeForItem:item].width, stage.size.width)) return;     // some window as wide as the stage: nothing to expand
first = [cols.firstObject sorted ascending by minX].firstObject;  last = [cols.lastObject sorted DEScending by maxX].firstObject;
double L = cx(first) - w(first)/2, R = cx(last) + w(last)/2;
if (dragging && [dragging isEqual:last] && before && [before.items containsObject:dragging] && [m.items containsObject:dragging])
    R = MAX(R, [before centerForItem:dragging].x + w(last)/2);                    // do not let the dragged right-most window shrink the content range
if (BSFloatGreaterThanFloat(L, stage.origin.x)) { double d = L - stage.origin.x; for (col)(item) setCenter(cx - d, cy); L -= d; R -= d; }       // flush left
double width = R - L;
if (BSFloatLessThanFloat(width, stage.size.width) && [cols count]) {
    double slack = stage.size.width - width, prevMax = +DBL_MAX;
    for (i, col in cols) { minL, maxR over items;
        if (i != 0) { double g = prevMax - minL;                               // negative gap
            if (BSFloatGreaterThanFloat(g, -gap)) { double d = MIN(gap + g, slack); for (item) setCenter(cx + d, cy); maxR += d; } }
        prevMax = maxR; }
}
// 0x1c73ce0e8 _expandSpacingVertically...(m, cols, a, stage): per column: top = cy(first)-h/2, colH = cy(last)+h/2 - top; if (colH < stage.h && [col count] >= 2) { slack = stage.h - colH; prevBottom = +DBL_MAX;
//    for (j,item in col) { bottom = cy+h/2; if (j != 0) { g = prevBottom - (cy - h/2); if (g > -gap) { d = MIN(gap + g, slack); setCenter(cx, cy + d); prevBottom = bottom + d; } else prevBottom = bottom; } else prevBottom = bottom; } }
// 0x1c73ce3f0 _verticallyCenterModel:withColumns:stageArea:  per column (items sorted top->bottom): if count>=2: shift = stageMidY - ((top + bottom)/2) and apply to all items;
//    count==1: three candidate centres {stageMidY, stage.minY + h/2, stage.maxY - h/2}; pick the one nearest (|d| rounded with frinta; ties favour mid, then top, then bottom) and setCenter(cx, thatY).
// 0x1c73ce72c _horizontallyCenterModel:stageArea:  bb = [self _boundingBoxForModel:m]; shift = (stage.x + stage.w/2) - (bb.x + bb.w/2); every item cx += shift.
// 0x1c73cf450 _boundingBoxForModel:  union (CGRectUnion; first rect taken as-is when the accumulator IsEmpty) of all item rects.
// 0x1c73cf628 _isColumnOfItems:equalToColumnOfItems:  same count, and for each i same sub-count and BSEqualObjects element-wise.
```
`_fullyOccludedItemsInModel:chamoisLayoutAttributes:` (0x1c73cefcc):
```objc
gap = [a stageInterItemSpacing]; peekLen = [a stageOcclusionDodgingPeekLength]; out = [NSMutableArray new]; CGRegionRef acc = NULL;
for (item in [m items]) {                                                  // front to back
    rect = itemRect; CGRegionRef reg = Rgn(rect); CGRegionRef grown = Rgn(rect grown by gap/2 on each side);
    if (acc) { CGRegionRef vis = CFAutorelease(CGRegionCreateDifferenceWithRegion(reg, acc));
               if (CGRegionIsEmpty(vis) || BSFloatLessThanFloat(CGRegionGetBoundingBox(vis).size.width, peekLen)) [out addObject:item];       // visible part narrower than the peek length
               acc = Union(acc, grown); }
    else acc = grown;
}
return out;
// 0x1c73cf21c _flagItemsCoveredByFullyOccludedPeekingItemsInModel:chamoisLayoutAttributes:
CGRegionRef acc = NULL;
for (item in [m items]) { s = size; BOOL full = [m isItemFullyOccluded:item];
    CGPoint c; double k; if (full) { c = [m unoccludedPeekingCenterForItem:item]; k = [a stageOcclusionDodgingPeekScale]; }
    else { c = [m centerForItem:item]; k = [m isItemPartiallyOccluded:item] ? [a partiallyOccludedStageScaleForItemWithSize:s] : 1.0; }
    CGRegionRef reg = Rgn(CGRectMake(c.x - s.w*0.5*k, c.y - s.h*0.5*k, s.w*k, s.h*k));
    if (acc) { [mc setCoveredByFullyOccludedPeekingItem:CGRegionIntersectsRegion(reg, acc) forItem:item]; if (full) acc = Union(acc, reg); }
    else { acc = full ? reg : NULL; [mc setCoveredByFullyOccludedPeekingItem:NO forItem:item]; }
}
```
`_overlappingScaleAnchorCentersForModel:chamoisLayoutAttributes:` (0x1c73ca8d4): Phase 1 clusters `items` (front-to-back order) into groups of adjacent occluded windows:
```objc
gap=[a stageInterItemSpacing]; groups=[NSMutableArray new]; [groups addObject:[NSMutableArray new]]; CGRegionRef acc = NULL; i=0;
for (item in items) { rect = itemRect(item); reg = Rgn(rect); last = groups.lastObject;
    if (!acc) [last addObject:item];                                                                                   // first item
    else { prev = items[i-1];
           BOOL a1 = [m isItemPartiallyOccluded:item] ? YES : [m isItemFullyOccluded:item];
           BOOL a2 = [m isItemPartiallyOccluded:prev] ? YES : [m isItemFullyOccluded:prev];
           CGRegionRef ov = Intersection(acc, reg);
           BOOL join = NO;
           if (a1 && a2 && CGRegionIsEmpty(ov)) {                                                                        // both occluded-ish, rectangles do not overlap ...
               CGRegionRef near = Intersection(acc, Rgn(rect grown by 2*gap+1 in both dimensions, same centre));       // ... but touch within the gap
               double w = 2.0 (sentinel), h = ...: if (!CGRegionIsEmpty(near)) { w = bbox(near).w; h = bbox(near).h; } else { w = d13; h = d14 (constants from GOT 0x1d83e1c78+0x10: CGRectNull size => huge) }
               join = (w < 2.0 && h > 2.0) || (w > 2.0 && h < 2.0);                                                       // edge-adjacent (thin contact strip)
           }
           if (join) { acc = Union(acc, reg); [last addObject:item]; i++; continue; }
           [groups addObject:[[NSMutableArray alloc] initWithObjects:item, nil]]; }
    acc = reg; i++; }
// Phase 2
bb = [self _boundingBoxForModel:m]; result = [NSMutableDictionary new];
for (group in groups) { CGRegionRef u = NULL; for (item in group) { reg = Rgn(itemRect(item)); u = u ? Union(u, reg) : reg; }
    CGRect g = CGRegionGetBoundingBox(u);  CGPoint ctr = UIRectGetCenter(g);
    // X
    double dc = fabs(ctr.x - CGRectGetMidX(bb)), dl = fabs(g.minX - bb.minX), dr = fabs(g.maxX - bb.maxX);
    double ax = ctr.x;  if (!(BSFloatLessThanOrEqualToFloat(dc, dl) && BSFloatLessThanOrEqualToFloat(dc, dr))) ax = BSFloatLessThanOrEqualToFloat(dl, dr) ? g.minX : g.maxX;
    // Y
    double ec = fabs(ctr.y - CGRectGetMidY(bb)), et = fabs(g.minY - bb.minY), eb = fabs(g.maxY - bb.maxY);
    double ay = ctr.y;
    if (!(BSFloatLessThanOrEqualToFloat(ec, et) && BSFloatLessThanOrEqualToFloat(ec, eb)) && !BSFloatLessThanOrEqualToFloat(fabs(ec - MAX(et, eb)), 12.0))
        ay = BSFloatLessThanOrEqualToFloat(et, eb) ? g.minY : g.maxY;
    for (item in group) result[item] = [NSValue valueWithCGPoint:CGPointMake(ax, ay)]; }
return result;
```
(UNSURE in anchors: the Y rule's tie handling and the `join` thresholds; they come from the `fcmp`/`BSFloat` chain at 0x1c73cae14-0x1c73cae3c.)

`_dodgeFullyOccludedWindowsToNearestVisibleEdgeInModel:chamoisLayoutAttributes:draggingItem:bounds:` (0x1c73ce890, 165 insns of region loops), faithful outline with all arithmetic:
```objc
copy = model ? [model mutableCopy] : nil;                    // pre-snap copy (final centres are restored from it)
[self _snapPositionToNearestEdgesIfNecessary:model draggingItem:nil];                           // the snap is applied to the MODEL itself, with no dragging item
NSArray *fully = [self _fullyOccludedItemsInModel:model chamoisLayoutAttributes:a];
gap=[a stageInterItemSpacing]; peekLen=[a stageOcclusionDodgingPeekLength]; pad=[a screenEdgePadding]; pk=[a stageOcclusionDodgingPeekScale]; strip=[a usesStripAreaForOverlapping];
CGRegionRef occ = NULL;                                                                            // union of the grown rects of the non-occluded items seen so far (front items)
for (item in [model items]) {
    CGPoint c = [model centerForItem:item]; CGSize s = [model sizeForItem:item];
    if (![fully containsObject:item]) {
        [model setPartiallyOccluded:NO forItem:item]; [model setFullyOccluded:NO forItem:item]; [model setUnoccludedPeekingCenterForItem:CGPointZero forItem:item];
        reg = Rgn(rect); grown = Rgn(CGRectMake(rect.x - gap/2, rect.y - gap/2, s.w + gap, s.h + gap));
        if (occ) { if (CGRegionIntersectsRegion(occ, reg)) [model setPartiallyOccluded:YES forItem:item]; occ = Union(occ, grown); } else occ = grown;
        continue; }
    // fully occluded item: look for the nearest position where >= peekLen of it is visible
    double hw = s.w*0.5, hh = s.h*0.5;
    // left: slide centre left in steps of peekLen until visible width >= peekLen
    double xL = c.x; CGRegionRef vis = NULL;
    do { xL -= peekLen; vis = Diff(Rgn(CGRectMake(xL - hw, c.y - hh, s.w, s.h)), occ); } while (!vis || CGRegionIsEmpty(vis) || BSFloatLessThanFloat(bbox(vis).size.width, peekLen));
    double visWL = bbox(vis).size.width;  double leftScore = xL + visWL - peekLen;
    // right
    double xR = c.x;  do { xR += peekLen; vis = Diff(Rgn(CGRectMake(xR - hw, c.y - hh, s.w, s.h)), occ); } while (!vis || CGRegionIsEmpty(vis) || BSFloatLessThanFloat(bbox(vis).size.width, peekLen));
    double rightScore = xR - bbox(vis).size.width + peekLen;
    // down: slide centre down in steps of peekLen/2 until the visible height > pad/2
    double yD = c.y;  do { yD += peekLen*0.5; vis = Diff(Rgn(CGRectMake(c.x - hw, yD - hh, s.w, s.h)), occ); } while (!vis || CGRegionIsEmpty(vis) || BSFloatLessThanOrEqualToFloat(bbox(vis).size.height, pad*0.5));
    double visH = bbox(vis).size.height;
    double kk = 1 - pk;
    double cxL = MAX((gap + leftScore) - kk*pad, pad*0.5 + pk*pad);                              // candidate centre x when peeking from the left
    double cxR = MIN(kk*pad + (rightScore - gap), bounds.size.width - pad*0.5 - pk*pad);          // from the right
    double cyV = kk*hh + (pad*0.5 + (yD - visH) - gap);                                           // candidate centre y when peeking from the bottom
    BOOL leftOff = BSFloatLessThanFloat(cxL - pk*pad, 0), rightOff = BSFloatGreaterThanFloat(pk*pad + cxR, bounds.size.width), botOff = BSFloatGreaterThanFloat(pk*pad + cyV, bounds.size.height);
    double dL = round(fabs(cxL - c.x)), dR = round(fabs(cxR - c.x)), dV = round(fabs(cyV - c.y));
    double bbW = [self _boundingBoxForModel:model].size.width;
    CGPoint pc;
    if (!strip && !botOff && BSFloatLessThanFloat(dV, dR*0.5) && BSFloatLessThanFloat(dV, dL*0.5) && BSFloatGreaterThanFloat(dL, bounds.size.width/8) && BSFloatGreaterThanFloat(dR, bounds.size.width/8))
         pc = CGPointMake(c.x, cyV);                                                            // vertical peek from the bottom
    else if (!leftOff && BSFloatLessThanFloat(cxL - pad, -bbW*0.5 + bounds.size.width*0.5) && BSFloatLessThanOrEqualToFloat(dL, dR*1.5)) pc = CGPointMake(cxL, c.y);
    else if (rightOff) pc = CGPointMake(cxL, c.y);
    else if (BSFloatGreaterThanFloat(pad + cxR, bounds.size.width*0.5 + bbW*0.5) && BSFloatLessThanOrEqualToFloat(dR, dL*1.5)) pc = CGPointMake(cxR, c.y);
    else pc = BSFloatLessThanOrEqualToFloat(dR, dL) ? CGPointMake(cxR, c.y) : CGPointMake(cxL, c.y);
    [model setPartiallyOccluded:NO forItem:item]; [model setFullyOccluded:YES forItem:item]; [model setUnoccludedPeekingCenterForItem:pc forItem:item];
}
if (copy) for (item in [copy items]) [model setCenter:[copy centerForItem:item] forItem:item];       // restore the pre-snap centres
```
(UNSURE: the order of the two "left"/"right" `else if` after the vertical test follows 0x1c73cedbc-0x1c73cee44; `leftOff` makes the left branch skipped. The vertical branch condition list is exactly the 5-term and at 0x1c73ced64-0x1c73cedb8.)

### What the 162 algorithm fixes vs 160 (confidence medium; behavioural inference from the code)
* Stage area is now computed from the container, dock, strip state and window sizes (`_stageAreaForModel`), instead of being passed in. Result: windows no longer overlap the strip / dock inconsistently when `prefersStripHidden`/`prefersDockHidden` change (the 16.0 calculator had to precompute the frame).
* Strip hides (`widthThresholdToHideStrip`) when windows are too wide; 16.0 had no such automatic hide (a separate `SBSwitcherChamoisSettings widthThresholdToHideContinuousExposeStripsForStageWithItemCount:bounds:` 160 0x1c64138a0 existed and is removed in 162).
* Fully occluded windows get a proper peek position that also respects the dock / strip (`usesStripAreaForOverlapping`), flags for items covered by those peeking windows, scale anchors and the "compacted" layout used by the app switcher piles (switcherPileCompactingFactor).
* `stageAreaForResizing` supports live resize against the final stage area.
* Re-layout when the column structure changes after dodging (reentrancy guard) fixes jumps after a window is dragged out of / into a column.

### PORTABILITY (A4)
PORTABLE as a NEW class `BP162ChamoisOverlappingController` (draft in the hooks file, section A4): it has no system ivars; it needs (1) the A3 model extras, (2) the A5 layout attributes extras
(`usesStripAreaForOverlapping`, `partiallyOccludedStageScaleForItemWithSize:`, `switcherPileCompactingFactor`, `stageInterItemSpacing`, `maximumWindowHeightWithDock`, `minimumDefaultWindowSize`, `stripWidth`, `screenEdgePadding`, `stageOcclusionDodgingPeekLength/Scale`),
(3) the CoreGraphics region SPI (resolved by `dlsym`; the 16.0 controller already links `CGRegion*`? UNVERIFIED, so every use is guarded), (4) `-[NSArray bs_reverse]`, `-sb_arrayByInsertingOrMovingObject:toIndex:`, `-sb_arrayByAddingOrMovingObject:` (exist in 16.0: the 16.0 binary has `sb_arrayByInsertingOrMovingObject:toIndex:` 160 0x1c605d920; `sb_arrayByAddingOrMovingObject:` and `bs_reverse` guarded with fallbacks).
The 16.0 controller class is left untouched. The 16.0 caller (`SBDisplayItemLayoutAttributesCalculator _appLayoutByPerformingAutoLayoutIfNeededInAppLayout:...`, see A7) has to be redirected to the new class: the call site passes the 16.2 arguments, so this is done by hooking the calculator method, not the controller.
