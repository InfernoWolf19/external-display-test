# Group 4: external display CONNECT path, display service, suspend-under-lock, education, mirroring

Build under test: iPadOS 16.0 `20A8372`. Reference: iPadOS 16.2 `20C65`.
Addresses are `16.0 / 16.2` vm addresses inside `SpringBoard` unless a framework is named.
Companion file: `group4-connect-service-lock.hooks.m` (drafted hooks, compile-checked as plain ObjC/ARC against stubbed Foundation, `-Wall -Wextra` clean).
Already DONE in `Tweak.x` and not repeated here: sizing transform (`scale`), keyboard-arbiter auto-host (`autohost`), cover-sheet blanking (`blank`).

All ObjC below is reconstructed from the annotated disassembly. Selectors were taken from the resolved `objc_msgSend$` stubs, constants from the instruction stream. Where control flow is summarised rather than transcribed I say so. Log statements are omitted (they are `os_log` calls to `SBLogDisplayControlling` / `SBLogFBDisplayManagerCallbacks` / `SBLogDisplayAssertions`).

---------------------------------------------------------------------------------------------------

## 0. Result in one page

What 16.2 changed in this group is mostly a **re-layering** (the controller no longer asks the policy a dozen questions; the policy hands back preference objects; SBDisplayManager keeps per-display records and applies assertion *deltas*). Almost all of that is internal. Four things are real behaviour:

| # | Item | User-visible? | Port |
|---|------|---------------|------|
| 1 | **Hardware-window auto-extend** in `SBSystemShellExtendedDisplayControllerPolicy` (keyboard + pointer present at connect, or arriving within 4 s, makes the display start in extended/Stage Manager mode; user choice overrides) | **Yes, high** | PORTABLE (hooks) |
| 2 | **`-[SBExternalDisplayService setDisplayMirroringEnabled:forDisplay:]` ignores its argument in 16.0** (can only turn mirroring ON) | **Yes, high** (bug) | PORTABLE (hook) |
| 3 | Education rework (first-run alert once per reason, then a tappable pill banner on each connect, deep link to Display Arrangement settings) | Yes, medium | NOT PORTABLE |
| 4 | Clone-mirroring assertion (`cloneMirroringMode`, `BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay`) | Backboardd-side effect only | NOT PORTABLE (BKS symbol absent in 16.0) |
| 5 | Controller/policy hardening against a display that disconnects mid-connect or mid-update (`_displayDisconnectedSignal`) | Robustness, unproven | PARTIAL (2 entry points) |
| 6 | Provider drops its controller entry on disconnect | Robustness (avoids an exception on fast reconnect) | PORTABLE |
| 7 | `SBNonInteractiveDisplaySceneManager` suspend-under-lock + cover-sheet visibility notifications | Marginal (only with a second, system-shell, display) | PARTIAL |
| 8 | 100 ms deferred activation of external display assertions | Unknown (probably removes a connect-time glitch) | NOT PORTABLE (risk) |
| 9 | Everything else (records, per-display power-log/arrangement/idle-sleep setters, `SBDisplayArrangementItem`, service init split, `preferredArrangementOfDisplay:relativeTo:`, Chamois availability wrapper, preferences objects, `activeDisplayTrackingMethodology`) | No (refactor) | nothing to port |

Ranking by user-visible value (high to low): 1, 2, 3, 7, 5, 6, 8, 4, 9.
Ranking by porting risk (low to high): 2, 6, 7(covernote only), 5, 1, 7(nilock), 8, 3, 4.

Confidence: items 1 and 2 are read straight from the code and I am sure about *what the code does* (high). The product-level reading "it makes plugging in a keyboard and mouse switch the external display into Stage Manager" is medium-high: it is the only consumer of those flags that I found. Items 5-8 are medium to low on *why*.

---------------------------------------------------------------------------------------------------

## 1. The connect path, 16.0 vs 16.2

```
FBDisplayManager --didConnectIdentity--> SBDisplayManager
  16.0: displayMonitor:didConnectIdentity:withConfiguration:   (346 insns, everything inline)
  16.2: displayMonitor:didConnectIdentity:withConfiguration:   (88 insns, log + forward)
          -> _connectToIdentity:withConfiguration:forDisplayManagerInit:NO      (new, 413 insns, same body + records)
        SBDisplayManager.init now calls _connectToIdentity:...forDisplayManagerInit:YES for the main display
        (16.0 called displayMonitor:didConnectIdentity: itself)

SBDisplayManager --factories--> SBSceneHostingDisplayControllerProvider.displayControllerInfoForConnectingDisplay:
   -> SBSceneHostingDisplayController(policy)           policy = SBSystemShellExtendedDisplayControllerPolicy
   -> _connectControllerWithInfo:toDisplay:configuration:      or SBNonInteractiveDisplayControllerPolicy
        -> controller connectToDisplayIdentity:...       -> policy connectToDisplayController:displayConfiguration:
        -> updateTransformsWithCompletion: { completion: _createDisplayAssertionPreferences -> assertion update -> "displayConnect" root transaction }
```

---------------------------------------------------------------------------------------------------

## 2. SBDisplayManager

Class layout change (ivars, 16.0 -> 16.2):

```
16.0                                       16.2
0x20 NSMutableSet  _connectedIdentities    0x20 NSMutableDictionary _connectedIdentityToRecordMap   (identity -> _SBDisplayIdentityRecord)
                                           0x48 _rootIdentityToDisableSleepReasons
                                           0x50 _rootIdentityToDisplayArrangementItems
                                           0x58 _rootIdentityToCloneMirroringMode
                                           0x60 _rootIdentityToCloneMirroringModeTokens
0x48 _powerLogReporter                     0x68 _powerLogReporter          (and everything after shifts +0x20; _lock 0x68 -> 0x88)
@property NSSet *connectedIdentities       @property NSArray *connectedIdentities   (allKeys of the record map)
```

New class `_SBDisplayIdentityRecord` (16.2 `0x1c7992a2c..0x1c7992cbc`): `BSAtomicSignal _invalidationSignal; BOOL _connectedAtInit; FBSDisplayIdentity *_displayIdentity`. `-isValid` = signal not signalled, `-invalidate` signals, `-didConnectAtInit`.

### 2.1 `-displayMonitor:didConnectIdentity:withConfiguration:` 0x1c64d47a4 / 0x1c798ff88 (346 -> 88 insns)

(a) 16.0: logs; if `[config hardwareIdentifier]` is nil and `![config isMainDisplay]` logs an error (and continues). Then inline: if `[_connectedIdentities containsObject:identity]` it returns silently; otherwise `addObject:`; if root identity: `[_assertionCoordinator rootDisplayDidConnect:]`, create layout publisher and CADisplay mutation queue if missing, signpost; iterate `_factories` for `displayControllerInfoForConnectingDisplay:configuration:` (NSAssert at SBDisplayManager.m:0xc4 if two factories answer), `_connectControllerWithInfo:toDisplay:configuration:`; call observers `displayManager:didConnectToRootDisplay:` (root only) and `displayManager:didConnectIdentity:withConfiguration:`.

(b) 16.2:

```objc
- (void)displayMonitor:(id)monitor didConnectIdentity:(FBSDisplayIdentity *)identity withConfiguration:(FBSDisplayConfiguration *)configuration {
    os_log_debug(SBLogFBDisplayManagerCallbacks, "%@ %@", proem, [configuration _sbLoggingDescription]);
    if (![configuration hardwareIdentifier] && ![configuration isMainDisplay])
        os_log_error(SBLogFBDisplayManagerCallbacks, "... %@", identity);          // no behaviour change, still connects
    [self _connectToIdentity:identity withConfiguration:configuration forDisplayManagerInit:NO];
}
```

(c) Refactor. Confidence high (same body moved).
(d) none.

### 2.2 NEW `-_connectToIdentity:withConfiguration:forDisplayManagerInit:` 0x1c7990164 (413 insns) and `_SBDisplayIdentityRecord`

(b) 16.2:

```objc
- (void)_connectToIdentity:(FBSDisplayIdentity *)identity withConfiguration:(FBSDisplayConfiguration *)configuration forDisplayManagerInit:(BOOL)init {
    _SBDisplayIdentityRecord *existing = _connectedIdentityToRecordMap[identity];               // ivar 0x20
    if ([existing didConnectAtInit]) { os_log(SBLogDisplayControlling, "... %@", identity); return; }   // NEW: tolerate FrontBoard replaying the main display
    NSAssert(existing == nil, @"told an identity is connecting when we're already tracking it. is frontboard telling us things out of order?: %@", identity); // SBDisplayManager.m:0xde
    _SBDisplayIdentityRecord *record = [[_SBDisplayIdentityRecord alloc] initWithIdentity:identity connectedAtInit:init];
    _connectedIdentityToRecordMap[identity] = record;
    BOOL isRoot = [identity isRootIdentity];
    if (isRoot) {
        [_assertionCoordinator rootDisplayDidConnect:identity];                                // ivar 0x18
        if (!_rootIdentityToLayoutPublisherMap[identity])                                      // 0x28
            _rootIdentityToLayoutPublisherMap[identity] = [self _createAndActivateLayoutPublisherForConnectingDisplay:identity];
        if (!_rootIdentityToCADisplayQueueMap[identity]) {                                     // 0x30
            NSString *label = [NSString stringWithFormat:@"%@:%@:CADisplayMutation", [self class], identity];
            _rootIdentityToCADisplayQueueMap[identity] = BSDispatchQueueCreate(label, [[BSDispatchQueueAttributes serial] serviceClass:0x19 /*QOS_CLASS_USER_INITIATED*/]);
        }
        os_signpost_event(SBLogDisplayControlling, ..., identity);
        if ([identity isExternal]) {
            // NEW: external displays only start asserting 100 ms later, if still connected
            dispatch_after(dispatch_time(0, 100 * NSEC_PER_MSEC /*0x5f5e100*/), dispatch_get_main_queue(), ^{
                if ([record isValid]) [_assertionCoordinator activateAssertionsForDisplay:identity];   // block 0x1c79907d8
            });
        } else {
            [_assertionCoordinator activateAssertionsForDisplay:identity];                      // 0x1c79904b8
        }
    }
    id info = nil;
    for (id factory in _factories) {                                                            // 0x70
        id i = [factory displayControllerInfoForConnectingDisplay:identity configuration:configuration];
        if (i) { NSAssert(info == nil, @"multiple factories want to provide a controller for the same display: %@; how it started: %@; how it's going: %@", identity, info, i); /* :0x108 */ info = i; }
    }
    if (info) [self _connectControllerWithInfo:info toDisplay:identity configuration:configuration];
    NSArray *observers; os_unfair_lock_lock(&_lock); observers = [_lock_observers copy]; os_unfair_lock_unlock(&_lock);   // 0x88 / 0x90
    if (isRoot) for (id o in observers) if ([o respondsToSelector:@selector(displayManager:didConnectToRootDisplay:)]) [o displayManager:self didConnectToRootDisplay:identity];
    for (id o in observers) if ([o respondsToSelector:@selector(displayManager:didConnectIdentity:withConfiguration:)]) [o displayManager:self didConnectIdentity:identity withConfiguration:configuration];
}
```

(c) Two small behaviour changes: (i) a duplicate connect for a display that was connected during `init` no longer asserts (16.0 ignored *any* duplicate silently; 16.2 ignores the init case and asserts on the rest, a tightening); (ii) the external-display assertion activation is deferred by 100 ms (see 2.6). Confidence high on the code, low on the user-visible reason for (ii).
(d) `SBDisplayAssertionCoordinator -activateAssertionsForDisplay:` and `_SBDisplayAssertionStack -activateAssertionsForDisplay:` / `_activated` ivar (16.2 only, see 2.6).

### 2.3 `-initWithDisplayManager:sceneManagerCoordinator:assertionCoordinator:powerLogReporter:` 0x1c64d3e80 / 0x1c798f60c (112 -> 134)

(a) 16.0 allocated `_connectedIdentities = [NSMutableSet set]`, then called `displayMonitor:didConnectIdentity:withConfiguration:` for `[_displayManager mainConfiguration]` and `_beginMonitoringForConnectingDisplays`.
(b) 16.2: same, with `_connectedIdentityToRecordMap = [NSMutableDictionary new]`, four additional `NSMutableDictionary`s (`_rootIdentityToDisableSleepReasons`, `...DisplayArrangementItems`, `...CloneMirroringMode`, `...CloneMirroringModeTokens`), and `[self _connectToIdentity:main.identity withConfiguration:main forDisplayManagerInit:YES]`.
(c) Refactor (storage for 2.5). (d) none.

### 2.4 `-displayMonitor:willDisconnectIdentity:` 0x1c64d509c / 0x1c7990b4c (307 -> 297)

(a) 16.0: after the observer `willDisconnectIdentity` callouts and controller teardown (`[_assertionCoordinator invalidateAssertionForDerivedDisplayDisconnect:]`, `displayIdentityDidDisconnect:`), for a root identity it did `rootDisplayDidDisconnect:`, layout publisher teardown, and **reported a default power-log entry** (`[SBDisplayPowerLogEntry entryForDisplay:[CADisplay immutableCADisplay] mode:0 zoom:0]` -> `reportPowerLogEntry:`), then `[_connectedIdentities removeObject:]`.
(b) 16.2: the power-log report is gone from here (it now happens through 2.5 `_setPowerLogEntry:nil`), and the identity is removed by `[_connectedIdentityToRecordMap[identity] invalidate]; [... removeObjectForKey:identity]` (so the pending 100 ms activation block sees `isValid == NO`). Order unchanged otherwise.
(c) Refactor; side effect: the power log no longer gets a synthetic "display off" entry from this method, it gets it from the assertion delta. Confidence medium. (d) record class.

### 2.5 Assertion deltas: `assertionCoordinator:updatedAssertionPreferences:oldPreferences:forDisplay:` 0x1c7991098 and the new setters

(a) 16.0: one delegate method, `-assertionCoordinator:activeAssertionPreferencesHaveChanged:` 0x1c64d5608 (289 insns), receives a dictionary display -> active `SBDisplayAssertionPreferences` for *all* displays and recomputes everything: builds the whole `FBSDisplayArrangement` array (`SBExternalDisplayArrangementItem` -> `initWithDisplayUUID:relativeToDisplayUUID:alongEdge:atOffset:`) and calls `BKSDisplayServicesSetArrangement`; `NSAssert(powerLogEntry, "powerLogEntry must be non-nil")` (SBDisplayManager.m:0x143) then `reportPowerLogEntry:`; unions every `disableSystemIdleSleepReason`, sorts and joins with `|`, and flips the global `_SBWorkspaceSetPreventIdleSleepForReason(YES/NO, ...)` if the string changed.

(b) 16.2, per display, with the old preferences passed but unused:

```objc
- (void)assertionCoordinator:(id)c updatedAssertionPreferences:(SBDisplayAssertionPreferences *)p oldPreferences:(id)old forDisplay:(FBSDisplayIdentity *)d {
    [self _setPowerLogEntry:p.powerLogEntry forDisplay:d];                       // 0x1c799167c
    [self _setDisplayArrangementItem:p.displayArrangement forDisplay:d];         // 0x1c7991278
    [self _setCloneMirroringMode:p.cloneMirroringMode forDisplay:d];             // 0x1c79917ac   (new field)
    [self _setDisableIdleSleepReason:p.disableSystemIdleSleepReason forDisplay:d]; // 0x1c7991bd4
}

- (void)_setPowerLogEntry:(SBDisplayPowerLogEntry *)entry forDisplay:(FBSDisplayIdentity *)d {
    NSAssert([d isRootIdentity], @"Invalid parameter not satisfying: %@", @"[rootIdentity isRootIdentity]");   // :0x19c
    if (!entry) entry = [SBDisplayPowerLogEntry entryForDisplay:[_displayManager configurationForIdentity:d] mode:0 zoom:0]; // was an assertion in 16.0
    [_powerLogReporter reportPowerLogEntry:entry];                               // ivar 0x68
}

- (void)_setDisplayArrangementItem:(SBDisplayArrangementItem *)item forDisplay:(FBSDisplayIdentity *)d {
    SBDisplayArrangementItem *cur = _rootIdentityToDisplayArrangementItems[d];   // 0x50
    if ([cur isEqual:item] || (!cur && !item)) return;
    if (item) _rootIdentityToDisplayArrangementItems[d] = item; else [_rootIdentityToDisplayArrangementItems removeObjectForKey:d];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:_rootIdentityToDisplayArrangementItems.count];
    for (FBSDisplayIdentity *k in _rootIdentityToDisplayArrangementItems) {      // identical construction to 16.0, iterating the dictionary
        SBDisplayArrangementItem *it = _rootIdentityToDisplayArrangementItems[k];
        NSString *hw  = [[_displayManager configurationForIdentity:k] hardwareIdentifier];
        NSString *rel = [[_displayManager configurationForIdentity:it.relativeDisplayIdentity] hardwareIdentifier];
        if (hw) [out addObject:[[BKSDisplayArrangementItem alloc] initWithDisplayUUID:hw relativeToDisplayUUID:rel alongEdge:it.edge atOffset:it.offset]];
        else os_log_fault(SBLogDisplayControlling, "...");
    }
    BKSDisplayServicesSetArrangement(out);
}

- (void)_setDisableIdleSleepReason:(NSString *)reason forDisplay:(FBSDisplayIdentity *)d {
    NSAssert([d isRootIdentity], @"Invalid parameter not satisfying: %@", @"[rootIdentity isRootIdentity]");   // line number not decoded
    NSString *old = _rootIdentityToDisableSleepReasons[d];                       // 0x48
    if ([old isEqualToString:reason] || (!old && !reason)) return;
    NSUInteger before = _rootIdentityToDisableSleepReasons.count;
    if (reason) _rootIdentityToDisableSleepReasons[d] = reason; else [_rootIdentityToDisableSleepReasons removeObjectForKey:d];
    NSString *joined = [[[_rootIdentityToDisableSleepReasons allValues] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"|"];
    id s = [<class with +sharedInstance and -setSystemIdleSleepDisabled:forReason:> sharedInstance];   // classref not resolvable here; FBSystemService is the only class in the dumps with that selector
    if (_rootIdentityToDisableSleepReasons.count) [s setSystemIdleSleepDisabled:YES forReason:joined];
    if (before)                                     [s setSystemIdleSleepDisabled:NO  forReason:_disableIdleSleepReason];  // ivar 0x40 = previous joined string
    _disableIdleSleepReason = joined;                                            // (stored when the string changed)
}

- (void)_setCloneMirroringMode:(unsigned long long)mode forDisplay:(FBSDisplayIdentity *)d {
    NSAssert([d isRootIdentity], ...);                                           // :0x1a8
    NSUInteger cur = [_rootIdentityToCloneMirroringMode[d] unsignedIntegerValue]; // 0x58
    if (mode == 0) {                                                             // SBDisplayCloneMirroringMode 0 = Invalid (no preference): release
        [_rootIdentityToCloneMirroringModeTokens[d] invalidate];                 // 0x60
        [_rootIdentityToCloneMirroringMode removeObjectForKey:d];
        return;
    }
    if (cur == mode) return;
    _rootIdentityToCloneMirroringMode[d] = @(mode);
    int bks;                                                                     // SB 1 = ".Default" -> BKS 0 ; SB 2 = ".Disabled" -> BKS 2 ; else NSAssert("unexpected mirroring mode: %lu", :0x1bd)
    if ([d isMainDisplay]) { /* log only */ return; }
    id token = BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay([[_displayManager configurationForIdentity:d] hardwareIdentifier], bks);
    id oldToken = _rootIdentityToCloneMirroringModeTokens[d];
    _rootIdentityToCloneMirroringModeTokens[d] = token;
    [oldToken invalidate];
}
```

New preference field: `SBDisplayAssertionPreferences._cloneMirroringMode` (ivar 0x28, included in the copy/isEqual/hash).

(c) Refactor except two details: `powerLogEntry` may now be nil (defaulted instead of asserting) and `cloneMirroringMode` is brand new. Mirroring semantics: the extended policy asserts `SBDisplayCloneMirroringMode.Disabled (2)`, the non-interactive policy asserts `.Default (1)`; with BackBoard this stops backboardd cloning the main display onto the external one. Confidence: high that this is the intent, medium on the BKS side.
(d) `BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay` (BackBoardServices `0x18e488274` in 16.2; `symaddr` finds nothing in the 16.0 cache), `_BKSCloneMirroringModeRequest` class (16.2 only), `SBDisplayAssertionCoordinator -assertionStack:updatedAssertionPreferences:oldPreferences:` replacing `...activeAssertionPreferencesHaveChanged:`, `_SBDisplayCloneMirroringModeDescription`. => NOT PORTABLE (the delta machinery is refactor; the mirroring-mode part has no 16.0 backend).

### 2.6 Deferred activation: `SBDisplayAssertionCoordinator -activateAssertionsForDisplay:` 0x1c77de510, `_SBDisplayAssertionStack -activateAssertionsForDisplay:` 0x1c74d1898

(b) 16.2 stack: `NSAssert([_rootIdentity isEqual:rootIdentity]); NSAssert(!_invalidated); NSAssert(!_activated); _activated = YES; [self _evalAndApplyOldPreferences:[SBDisplayAssertionPreferences new] newPreferences:_lastPreferences /*ivar 0x20*/];` i.e. until activated the stack does not call its delegate, so assertions acquired during connect do not produce intermediate delegate callbacks; for externals the first evaluation is 100 ms after connect.
(c) Probably removes a transient where the first evaluation of a freshly connected external display flips `wantsControl`/arrangement/power-log several times. I could not confirm a symptom; low confidence. (d) new `_activated` ivar (stack 0x19), new coordinator method. NOT PORTABLE: the stack class would need a new ivar and its evaluation path gated; high risk for an unproven benefit.

---------------------------------------------------------------------------------------------------

## 3. SBSceneHostingDisplayController (+ SBSceneHostingDisplayPreferences, Provider)

New ivar `BSAtomicSignal *_displayDisconnectedSignal` (0xb0); new `-isConnected`; removed `_preferredOverscanAdjustment`, `_preferredLogicalScale`, `_preferredPointScale`, `_preferredModeForDisplay` (replaced by `SBSceneHostingDisplayPreferences`).

New value class `SBSceneHostingDisplayPreferences` (16.2 `0x1c788f4f4`): `{_Bool keepOtherModes (0x8), FBSDisplayConfigurationRequest *displayConfigurationRequest (0x10), double contentsScale (0x18), CADisplayModeCriteria *CADisplayModeCriteria (0x20), CGSize logicalScale (0x28)}`, `NSCopying`. Its consumers are exactly the already-DONE sizing transform; see the existing notes (section 1 there) and `Tweak.x` `scale`.

### 3.1 `-connectToDisplayIdentity:configuration:displayManager:sceneManager:caDisplayQueue:assertion:` 0x1c5f47120 / 0x1c73bbc30 and its block 0x1c5f47584 / 0x1c73bbfac

(a) 16.0: main-thread assertion, "connecting to multiple displays" assertion (`SBSceneHostingDisplayController.m`), store identity/manager/sceneManager/`_currentConfiguration`/assertion, `_caDisplay = [config CADisplay]`, layout publisher, `[_policy connectToDisplayController:self displayConfiguration:_currentConfiguration]`, `[_readyToTransformDisplaysSignal signal]`, then **only if the policy responds to `displayController:transformDisplayConfiguration:withBuilder:`** `[_displayManager updateTransformsWithCompletion:block]`, otherwise logs and runs the block directly. Block: `_connectionCompleted = YES; _currentDisplayAssertionPreferences = [self _createDisplayAssertionPreferences]; [_displayAssertion updateWithPreferences:..]; [self _runRootUpdateTransactionWithLabel:__SBDisplayControllerTransactionLabel([self class],"displayConnect") completion:nil]`.

(b) 16.2:

```objc
// ... same up to the policy connect ...
_displayDisconnectedSignal = [BSAtomicSignal new];                       // ivar 0xb0, created before the policy is told
[_policy connectToDisplayController:self displayConfiguration:_currentConfiguration];
[_readyToTransformDisplaysSignal signal];
[_displayManager updateTransformsWithCompletion:^{                       // always (the transform is now mandatory)
    if ([self->_displayDisconnectedSignal hasBeenSignalled]) { os_log(...); return; }   // NEW
    self->_connectionCompleted = YES;
    self->_currentDisplayAssertionPreferences = [self _createDisplayAssertionPreferences];
    [self->_displayAssertion updateWithPreferences:self->_currentDisplayAssertionPreferences];
    self->_presentedConfiguration = self->_currentConfiguration;         // NEW store (0x98 -> 0xa0)
    [self _runRootUpdateTransactionWithLabel:__SBDisplayControllerTransactionLabel([self class], "displayConnect") completion:nil];
}];
```

(c) Fix for a race: unplugging a display between connect and the transform completion no longer builds an assertion/transaction for a dead controller. Confidence medium (race, not reproduced). (d) `BSAtomicSignal` exists in 16.0 (used elsewhere), no external dependency. PARTIAL port (hooks.m `discguard`).

### 3.2 `-displayIdentityDidUpdate:configuration:` 0x1c5f476fc / 0x1c73bc150 and `-observeValueForKeyPath:` / logging only. Refactor.

### 3.3 `-displayIdentityDidDisconnect:` 0x1c5f47a64 / 0x1c73bc47c and block 0x1c5f47c94 / 0x1c73bc730

(b) 16.2:

```objc
BSDispatchQueueAssertMain-style assert (isMainThread);                   // "this call must be made on the main thread", :0x110
[_displayDisconnectedSignal signal];                                     // NEW, first thing
[_policy displayControllerWillDisconnect:self sceneManager:_sceneManager];   // NEW protocol method
BSBlockTransaction *t = [[BSBlockTransaction alloc] initWithBlock:^(BSTransaction *txn, void (^done)(BOOL)) {
    [_policy displayControllerDidDisconnect:self transaction:txn sceneManager:_sceneManager];   // 16.0: displayControllerDidDisconnect:sceneManager:
    [_sceneManager invalidate];
    [_blankingWindow setHidden:YES]; _blankingWindow = nil;
    done(YES);
}];
t.debugName = __SBDisplayControllerTransactionLabel([self class], "disconnect");
[self _runRootTransaction:t withLabel:... completion:...];
```
(c) Teardown now has a synchronous "will" phase (the extended policy uses it to cancel its observers/timers before the asynchronous transaction runs) and the "did" phase receives the transaction. Refactor + hardening. (d) protocol methods `displayControllerWillDisconnect:sceneManager:` and `displayControllerDidDisconnect:transaction:sceneManager:` (the policies are the only implementers; both are in this group).

### 3.4 `-_createDisplayAssertionPreferences` 0x1c5f4a328 / 0x1c73bed8c (94 -> 27)

(a) 16.0 built the preferences itself: `wantsControlOfDisplay = _connectionCompleted ? ([policy respondsTo displayControllerShouldHaveControlOfDisplay:] ? [policy ...] : YES) : NO`; `displayArrangement = [policy displayArrangementForDisplayController:]` (optional); `disableSystemIdleSleepReason = __SBPreventIdleSleepReason(displayIdentity, [self class])`; `powerLogEntry = policy powerLogEntryForDisplayConfiguration:` or the default `[SBDisplayPowerLogEntry entryForDisplay:_caDisplay mode:0 zoom:0]`.
(b) 16.2: `NSParameterAssert(_displayIdentity); return [_policy assertionPreferencesForDisplay:self displayConfiguration:_currentConfiguration];`. The policies build the object (see 4.4 and 5.3).
(c) Refactor, with one subtle loss: the `_connectionCompleted` gate on `wantsControlOfDisplay` (16.0: `_connectionCompleted ? [policy ...] : NO`) is gone in 16.2, and `requestUpdate:` bit 0 has no such gate either. A `requestUpdate:1/7` that arrives before the connect completion block (for example the new mirroring-preference observer) could therefore assert control early in 16.2. I did not find compensating code; the 100 ms activation deferral (2.6) may be the intended cover. The hooks keep the 16.0 gate because they hook the 16.0 callee. (d) policy protocol `assertionPreferencesForDisplay:displayConfiguration:`.

### 3.5 `-_updatePolicyForPresentation:` 0x1c5f48b44 / 0x1c73bd620 (92 -> 47) and `_enqueueEvaluateAndApplyPresentationUpdate` blocks `_2` 0x1c5f4972c / 0x1c73be154 and `_3` 0x1c5f49970 / 0x1c73be3c0

(b) 16.2 drops the `displayController:shouldUpdatePresentationWithSceneManager:displayConfiguration:` gate (the policies now do `![_lastPresentationUpdateDisplayConfiguration isEqual:config]` themselves, see 4.5), and both blocks check `[_displayDisconnectedSignal hasBeenSignalled]` in addition to `_presentationUpdateInvalidationSignal` before touching the display (log and return when set).
(c) hardening, same family as 3.1/3.3. PARTIAL (hooks.m `discguard` guards the two entry points).

### 3.6 `_ensureCADisplayUpToDate:completion:` 0x1c5f48424 / 0x1c73bce50 and `transformDisplayConfiguration:withBuilder:` 0x1c5f46bf8 / 0x1c73bb2b8

Already covered and implemented (`scale`): per-axis clamp of the logical scale to `[minimumLogicalScale, maximumLogicalScale]` (unity for display type 2), criteria-based mode choice, optional retention of other modes.

### 3.7 SBSceneHostingDisplayControllerProvider

| Method (16.0 / 16.2) | Change |
|---|---|
| `displayManager:didConnectIdentity:withConfiguration:` 0x1c5ed1ea0 / 0x1c7345f0c | resolver factory call is `resolverForPhysicalDisplay:` (16.0: `resolverForPhysicalDisplay:caDisplay:` with `[config CADisplay]`). The windowing-mode resolver factory API changed. Refactor, but the callee class is outside this group. |
| `displayControllerInfoForConnectingDisplay:configuration:` 0x1c5ed2044 / 0x1c73460b4 | adds a debug log after recording the controller. Same NSAssert ("we can only track one controller per physical display", `_lock_rootDisplaysToControllerMap`, an NSMapTable with weak values). |
| `displayManager:didDisconnectIdentity:` 0x1c5ed1f90 / 0x1c7345fe0 | **16.2 also removes `[_lock_rootDisplaysToControllerMap removeObjectForKey:identity]`** (under `_lock`) before `updateTransformsWithCompletion:`. 16.0 relied on the weak value dying. |
| `transformDisplayConfiguration:` 0x1c5ed2218 / 0x1c73460b4+ | calls `[policyFactory transformDisplayConfiguration:config forControllersWithBuilder:builder]` (16.0: `transformDisplayForControllersWithBuilder:`); logging moved to `SBLogDisplayTransforming`. Refactor. |

(c) The map cleanup is the only functional change: with a quick unplug/replug while the previous controller is still alive (it is released asynchronously after the "disconnect" transaction) 16.0 hits the NSAssert and raises. Confidence medium. PORTABLE (`provmap`, uses the lock ivar located by name).

---------------------------------------------------------------------------------------------------

## 4. SBSystemShellExtendedDisplayControllerPolicy

16.2 ivars: `_externalDisplayDefaults 0x18`, ... (all shifted -8 because `_caDisplay` is gone), plus
`BSContinuousMachTimer *_timerForAttachedDevicesToAffectDisplayAssertion 0x88`, `BOOL _didConnectToRequiredDevicesDuringTimerWindow 0x90`, `int _userMirroringPreference 0x94` (0 auto, 1 mirror, 2 extend), `BSAtomicSignal *_displayDisconnectSignal 0x98`. Now also conforms to `SBMousePointerHardwareConnectionObserver`.
Removed (16.0): `displayControllerShouldHaveControlOfDisplay:`, `displayArrangementForDisplayController:`, `powerLogEntryForDisplayConfiguration:`, `preferredDisplayMode...`, `preferredOverscanCompensation...`, `preferredPointScale...`, `preferredLogicalScale...`, `displayController:transformDisplayConfiguration:withBuilder:`, `_preferredSizeIn{Pixels,Points}ForTargetCADisplay:`, `_preferredContentsScale`, `_preferredModeForDisplayForTargetCADisplay:`, `displayController:shouldUpdatePresentation...`.

### 4.1 `-connectToDisplayController:displayConfiguration:` 0x1c63386b4 / 0x1c77dba48 (253 -> 393) and blocks

(a) 16.0:

```objc
objc_storeWeak(&_displayController, controller);
_displayIdentity = config.identity;  _caDisplay = [config CADisplay];
NSAssert(connectionType == 1 || connectionType == 2, @"can only handle .Wired displays or .Wireless displays (unsupported, but we'll run)");
_displayModeSettings = [_externalDisplayDefaults displayModeSettingsForDisplay:_displayIdentity];
_displayModeSettingsToken = [_externalDisplayDefaults observeDisplayModeSettingsOnQueue:main withBlock:^{ /* settings changed */ [controller requestUpdate:3]; }];   // block 0x1c6338b68
[_externalDisplayDefaults setMirroringEnabled:YES];            // <<< unconditional
_externalDisplayDefaultsToken = [_externalDisplayDefaults observeDefault:@"mirroringEnabled" onQueue:main withBlock:^{ [controller requestUpdate:4]; }];  // block 0x1c6338c78
_contentScale = [_externalDisplayDefaults contentsScale];
_displayScaleMapping = [SBDisplayScaleMapping mappingWithDisplay:_caDisplay allowWirelessDisplays:[_externalDisplayDefaults allowWirelessDisplaysForExtendedDisplayMode]];
```
and `displayControllerShouldHaveControlOfDisplay:` (0x1c6339774) is `return ![_externalDisplayDefaults isMirroringEnabled];`.
So in 16.0 every connect forces "mirroring" and no SpringBoard code ever sets it back to NO (callers of `setMirroringEnabled:` in 16.0: this method, the education observer, and the service block, all with YES), i.e. the display can never become extended from the connect path.

(b) 16.2 (order within the method approximate; the set of calls is exact):

```objc
- (void)connectToDisplayController:(SBSceneHostingDisplayController *)controller displayConfiguration:(FBSDisplayConfiguration *)config {
    NSAssert([NSThread isMainThread], @"this call must be made on the main thread");        // :0x… SBSystemShellExtendedDisplayControllerPolicy.m
    objc_storeWeak(&_displayController, controller);
    _displayIdentity = config.identity;
    _displayDisconnectSignal = [BSAtomicSignal new];                                           // 0x98
    NSAssert(connectionType == wired || connectionType == wireless, @"can only handle .Wired displays or .Wireless displays (unsupported, but we'll run)");
    _displayModeSettings = [_externalDisplayDefaults displayModeSettingsForDisplay:_displayIdentity];
    _displayModeSettingsToken = [_externalDisplayDefaults observeDisplayModeSettingsOnQueue:main withBlock:^{            // 0x1c77dc120
        SBSDisplayModeSettings *s = [defaults displayModeSettingsForDisplay:id]; NSAssert(s, @"got nil SBSDisplayModeSettings for display: %@", id);   // :0xb2
        if (![self->_displayModeSettings isEqual:s]) { self->_displayModeSettings = s; [controller requestUpdate:3]; } }];
    _contentScale = [_externalDisplayDefaults contentsScale];
    _displayScaleMapping = [SBDisplayScaleMapping mappingWithDisplay:id allowWirelessDisplays:[_externalDisplayDefaults allowWirelessDisplaysForExtendedDisplayMode]];
    BOOL met = [self _areRuntimeAvailabilityRequirementsMet];
    _didConnectToRequiredDevicesDuringTimerWindow = met;                                       // 0x90
    [_externalDisplayDefaults setMirroringEnabled:!met];                                       // 16.0: YES
    _timerForAttachedDevicesToAffectDisplayAssertion = [[BSContinuousMachTimer alloc] initWithIdentifier:[NSString stringWithFormat:@"%@-%@", NSStringFromClass([self class]), _displayIdentity]];
    [_timer scheduleWithFireInterval:4.0 leewayInterval:0.5 queue:main handler:^(BSContinuousMachTimer *t) {               // 0x1c77dc284
        if (![self->_displayDisconnectSignal hasBeenSignalled])
            [[NSNotificationCenter defaultCenter] postNotificationName:@"SBSystemShellExtendedDisplayControllerPolicyDeviceConnectionWindowExpiredNotification" object:self userInfo:@{kIdentity: [id rootIdentity]}]; }];
    _userMirroringPreference = 0;                                                              // 0x94
    _externalDisplayDefaultsToken = [_externalDisplayDefaults observeDefault:@"mirroringEnabled" onQueue:main withBlock:^{  // 0x1c77dc3c0 (installed AFTER the set above)
        self->_userMirroringPreference = [self->_externalDisplayDefaults isMirroringEnabled] ? 1 : 2;
        [controller requestUpdate:7]; }];                                                      // 16.0: 4
    [_mousePointerManager addObserver:self];                                                   // new
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_keyboardAvailabilityChanged:) name:SBHardwareKeyboardAvailabilityChangedNotification object:nil];  // new
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SBSystemShellExtendedDisplayControllerPolicyConnectNotification" object:self
        userInfo:@{@"kSBSystemShellExtendedDisplayControllerHardwareAvailabilityIsAvailableKey": @(met),
                   @"kSBSystemShellExtendedDisplayControllerFiredDuringDeviceConnectionWindowKey": @YES /*constant object*/,
                   @"kSBSystemShellExtendedDisplayControllerDisplayIdentityKey": [id rootIdentity]}];
}
```
`requestUpdate:` bit mask (identical in 16.0 and 16.2, `SBSceneHostingDisplayController -requestUpdate:`): bit0 = recompute assertion preferences, bit1 = enqueue presentation update, bit2 = run a "policyRequested" root update transaction. So 16.0's default observer (mask 4) did not even recompute `wantsControl`.

### 4.2 `_wantsControlOfDisplay` 0x1c77dd1f8 (new), `_hardwareAvailabilityChanged` 0x1c77dd8e4 (new), `_keyboardAvailabilityChanged:` 0x1c77dd65c and `mousePointerManager:hardwarePointingDeviceAttachedDidChange:` 0x1c77dd658 (new)

```objc
- (BOOL)_wantsControlOfDisplay {
    switch (_userMirroringPreference) { case 1: return NO; case 0: return _didConnectToRequiredDevicesDuringTimerWindow; default: return YES; }
}
- (void)_keyboardAvailabilityChanged:(NSNotification *)n { [self _hardwareAvailabilityChanged]; }          // each is a bare `b`
- (void)mousePointerManager:(SBMousePointerManager *)m hardwarePointingDeviceAttachedDidChange:(BOOL)a { [self _hardwareAvailabilityChanged]; }
- (void)_hardwareAvailabilityChanged {
    BOOL met = [self _areRuntimeAvailabilityRequirementsMet];
    BOOL inWindow = [_timerForAttachedDevicesToAffectDisplayAssertion isScheduled];
    if (inWindow && !_didConnectToRequiredDevicesDuringTimerWindow && met) {
        os_log(SBLogDisplayControlling, "...");
        _didConnectToRequiredDevicesDuringTimerWindow = YES;
        [controller requestUpdate:7];            // controller = objc_loadWeakRetained(&_displayController)
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"SBSystemShellExtendedDisplayControllerHardwareAvailabilityNotification" object:self
        userInfo:@{IsAvailable: @(met), FiredDuringDeviceConnectionWindow: @(inWindow), Identity: [_displayIdentity rootIdentity]}];
}
```
`_areRuntimeAvailabilityRequirementsMet` (0x1c6339f38 / 0x1c77dd660) and `_currentRuntimeMask` have the same call sequence in both builds (offsets differ): `mask = SBBitmaskUnionIf(0, 1, ^{pointer attached}) | SBBitmaskUnionIf(.., 2, ^{hardware keyboard available})`, compared with `[_runtimeAvailabilitySettings extendedDisplayRequirements]` (defaults: `requirePointer = YES`, `requireHardwareKeyboard = YES`).

### 4.3 `displayControllerWillDisconnect:sceneManager:` 0x1c77dc440 (new) / `displayControllerDidDisconnect:` 0x1c6338c84 -> 0x1c77dc558

16.0 `DidDisconnect`: invalidate `_displayModeSettingsToken`, `_externalDisplayDefaultsToken`, then `[_currentScene invalidate]`. 16.2 `WillDisconnect`: `[_displayDisconnectSignal signal]; invalidate both tokens (and nil them); [_mousePointerManager removeObserver:self]; [[NSNotificationCenter defaultCenter] removeObserver:self]; post "...PolicyDisconnectNotification" {Identity}`; `DidDisconnect(transaction)` just `[_currentScene invalidate]`.

### 4.4 `displayPreferencesForDisplayController:` 0x1c77dd034 and `assertionPreferencesForDisplay:displayConfiguration:` 0x1c77dd0e8 (new)

```objc
- (SBSceneHostingDisplayPreferences *)displayPreferencesForDisplayController:(id)c {
    FBSDisplayConfigurationRequest *req = [FBSDisplayConfigurationRequest new];
    req.overscanCompensation = _FBSDisplayOverscanCompensationForDisplayValue([_displayModeSettings overscanCompensation]);
    CGFloat ls = [_displayScaleMapping logicalScaleForDisplayScale:[_displayModeSettings scale]];
    return [[SBSceneHostingDisplayPreferences alloc] initWithDisplayConfigurationRequest:req logicalScale:CGSizeMake(ls, ls) contentsScale:_contentScale keepOtherModes:/*w5, not decoded*/];
}
- (SBDisplayAssertionPreferences *)assertionPreferencesForDisplay:(id)display displayConfiguration:(id)cfg {
    SBDisplayAssertionPreferences *p = [SBDisplayAssertionPreferences new];
    p.wantsControlOfDisplay = [self _wantsControlOfDisplay];
    p.displayArrangement = [_externalDisplayService preferredArrangementOfExternalDisplay:_displayIdentity];
    p.powerLogEntry = [SBDisplayPowerLogEntry entryForDisplay:cfg mode:0 zoom:_SBDisplayPowerLogZoomLevelFromScale([_displayModeSettings scale])];
    p.disableSystemIdleSleepReason = __SBPreventIdleSleepReason(_displayIdentity, [self class]);
    p.cloneMirroringMode = 2;          // SBDisplayCloneMirroringMode.Disabled
    return p;
}
```
The non-interactive policy (`displayPreferences...` 0x1c78e9674, `assertion...` 0x1c78e96f0) returns the unit preferences (logical scale 1x1, contentsScale 1.0, request from the scene's `uiClientSettings`) and `wantsControl = !disablesMirroring`... (same condition as 16.0 `displayControllerShouldHaveControlOfDisplay:`), power-log default entry, idle-sleep reason, `cloneMirroringMode = 1 (Default)`.
(c) Refactor except the `_wantsControlOfDisplay` rule (4.2) and `cloneMirroringMode`.

### 4.5 `displayController:updatePresentationWithSceneManager:displayConfiguration:completion:` 0x1c6339470 / 0x1c77dcbe0 (56 -> 126)

(a) 16.0: apply the new display configuration/frame to **every** scene (`[sceneManager allScenes]` enumerate -> `updateSettings:withTransitionContext:`). The "did the configuration change" gate lived in the controller (`shouldUpdatePresentation...` = `![_lastPresentationUpdateDisplayConfiguration isEqual:config]` + store).
(b) 16.2: gate moved here (`if (![_lastPresentationUpdateDisplayConfiguration isEqual:config]) { store; ... }`) and the scene set is `[sceneManager boundPointerUIScenes] ∪ {_currentScene}` instead of all scenes (the per-scene block gained a guard before applying).
(c) Scope reduction (fewer scenes churned on a mode change). Confidence medium. (d) `-[SBSceneManager boundPointerUIScenes]` (BSCopyingCacheSet ivar 0x68) is 16.2-only. NOT PORTABLE.

### 4.6 Smaller items

`settings:changedValueForKey:` 0x1c633a1bc / 0x1c77ddad8 (7 -> 1): 16.0 asked the controller for `requestUpdate:` when a prototype setting changed; 16.2 does nothing (the sizing no longer depends on PT settings keys). `displayController:didBeginTransaction:...` / `_fetchOrCreateSceneWithDisplayConfiguration:deactivationReasons:sceneManager:` (scene manager now passed in) are signature-level refactors. `externalDisplayServiceDidUpdatePreferredDisplayArrangement:` unchanged.

---------------------------------------------------------------------------------------------------

## 5. SBExternalDisplayService

### 5.1 `-setDisplayMirroringEnabled:forDisplay:` 0x1c6332afc / 0x1c77d5db4, block 0x1c6332be0 / 0x1c77d5ebc

(a) 16.0 (the XPC protocol is `setDisplayMirroringEnabled:(NSNumber *)enabled forDisplay:(NSString *)hardwareIdentifier`; the client `-[SBSExternalDisplayService setMirroringEnabled:forDisplay:]` 0x191bd4f70 sends `@(enabled)`):

```objc
- (void)setDisplayMirroringEnabled:(NSNumber *)enabled forDisplay:(NSString *)hw {      // 'enabled' is never read
    BSProcess *proc = [[BSServiceConnection currentContext] remoteProcess];
    BSDispatchMain(^{
        id identity = [self _extendedModeDisplayIdentityForHardwareIdentifier:hw error:NULL];
        if (identity && ![_defaults isMirroringEnabled]) {
            os_log(SBLogDisplayControlling, "...");
            [_defaults setMirroringEnabled:YES];                                         // always YES
            [self _notifyOfPropertyChangesForDisplayIdentity:identity requestingProcess:proc];
        }
    });
}
```
(b) 16.2: the block captures `enabled`:

```objc
        BOOL want = [enabled boolValue];
        if (identity && want != [_defaults isMirroringEnabled]) {
            [_defaults setMirroringEnabled:want];
            [self _notifyOfPropertyChangesForDisplayIdentity:identity requestingProcess:proc];
        }
```
(c) **Bug fix.** In 16.0 a client asking for extended mode (`enabled == NO`) gets mirroring forced ON instead, so the Settings control for "use as separate display" can never switch a display to extended through the service. Together with 4.1 (connect forces YES) it explains why a 16.0 external display never leaves mirroring on its own. Confidence: high on the code; the UI (Settings bundle) is not in the cache so I cannot name the exact control. PORTABLE (hooks.m `mirrorsvc`; YES requests are passed through to the original).
(d) none (all selectors exist in 16.0; `BSServiceConnection +currentContext` is used by the original).

### 5.2 Everything else in the service

| Method | Change |
|---|---|
| `initWithDisplayManager:` 0x1c63321d0 / 0x1c77d52a4 (78 -> 2) | now `return [self initWithDisplayManager:m configureConnectionListener:YES]`; new designated init 0x1c77d52ac (102 insns) = the old body with the listener setup (`listenerWithConfigurator:` + `activate`) made conditional. Test seam. Refactor. |
| `preferredArrangementOfDisplay:` | replaced by `preferredArrangementOfDisplay:relativeTo:` 0x1c77d5620 and `preferredArrangementOfExternalDisplay:` 0x1c77d5510. External-vs-main case is the 16.0 code (`windowingMode == 1` -> `SBDisplayArrangementItem(display, relative: mainIdentity, edge: defaults.arrangementEdge, offset: defaults.arrangementOffset)`); the new overload also returns the inverse arrangement (opposite edge from a 4-entry table, negated offset) when `display` is main and `relativeTo` is external. Groundwork for multiple displays. |
| `listener:didReceiveConnection:withContext:` 0x1c6333130 / 0x1c77d63f4 | capability gate `[[SBPlatformController sharedInstance] isChamoisCapable]` replaced by `_SBFIsChamoisExternalDisplayControllerAvailable()` (SpringBoardFoundation `0x18ee096e4`: a cached feature-availability wrapper for the feature named `SBChamoisExternalDisplayController`: a defaults override, otherwise an `os_feature_enabled` check; the domain/feature strings were not decoded). Same decision on shipping hardware; 16.0 has no such symbol. |
| `_supportedScalesForDisplay:error:` 0x1c6333af0 / 0x1c77d6d98, block of `setDisplayModeSettings:...` | `[config CADisplay]` no longer fetched (CADisplay dependency removed with the preferences refactor). |
| `setDisplayMirroringEnabled` block, `_displayInfo...` | see 5.1 / only the string constant of a block descriptor changed. |

---------------------------------------------------------------------------------------------------

## 6. Suspend under lock: SBNonInteractiveDisplaySceneManager and the cover-sheet notifications

16.0: `SBNonInteractiveDisplaySceneManager : SBSceneManager` has only `-_shouldAutoHostScene:` (0x1c626b6f8). The suspend-under-lock machinery (`SBSuspendedUnderLockManager`, delegate protocol) was implemented only by `SBMainDisplaySceneManager` and `SBSystemShellExternalDisplaySceneManager`. 16.2 gives the class the same delegate (15 methods, `0x1c77034e4..0x1c770389c`), plus ivar `_lazy_suspendedUnderLockManager` (0xe0).

(b) 16.2 reconstruction (all verified, trivial bodies):

```objc
- (instancetype)initWithReference:(id)r sceneIdentityProvider:(id)p presentationBinder:(id)b {          // 0x1c77034e4
    if ((self = [super initWithReference:r sceneIdentityProvider:p presentationBinder:b])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_externalCoverSheetVisibilityDidPresent:) name:SBExternalDisplayCoverSheetDidPresent object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_externalCoverSheetVisibilityDidDismiss:) name:SBExternalDisplayCoverSheetDidDismiss object:nil];
    } return self; }
- (void)dealloc { removeObserver for both names; [super dealloc]; }                                        // 0x1c77035a4
- (void)_externalCoverSheetVisibilityDidPresent:(NSNotification *)n { [self setSuspendedUnderLock:YES]; }  // 0x1c77037d8
- (void)_externalCoverSheetVisibilityDidDismiss:(NSNotification *)n { [self setSuspendedUnderLock:NO]; }   // 0x1c77037e0
- (void)setSuspendedUnderLock:(BOOL)l { [self setSuspendedUnderLock:l alongsideWillChangeBlock:nil alongsideDidChangeBlock:nil]; }   // 0x1c77036e0
- (void)setSuspendedUnderLock:(BOOL)l alongsideWillChangeBlock:(id)w alongsideDidChangeBlock:(id)d {       // 0x1c77036ec
    BSDispatchQueueAssertMain();
    if (!_lazy_suspendedUnderLockManager)
        _lazy_suspendedUnderLockManager = [[SBSuspendedUnderLockManager alloc] initWithDelegate:self eventQueue:[[SBMainWorkspace mainWorkspace] eventQueue]];
    [_lazy_suspendedUnderLockManager setSuspendedUnderLock:l alongsideWillChangeBlock:w alongsideDidChangeBlock:d];
}
- (BOOL)isSuspendedUnderLock { BSDispatchQueueAssertMain(); return [_lazy_suspendedUnderLockManager isSuspendedUnderLock]; }   // 0x1c77036a0
- (id)suspendedUnderLockManagerVisibleScenes:(id)m { return [self externalForegroundApplicationSceneHandles]; }          // 0x1c770389c
- (BOOL)suspendedUnderLockManager:(id)m shouldPreventSuspendUnderLockForScene:(id)s { return NO; }                      // 0x1c7703890
- (BOOL)suspendedUnderLockManager:(id)m shouldPreventUnderLockForScene:(id)s { return NO; }                             // 0x1c7703888
- (id)suspendedUnderLockManager:(id)m sceneHandleForScene:(id)s { return [super existingSceneHandleForScene:s]; }       // 0x1c7703834
- (id)suspendedUnderLockManagerDisplayConfiguration:(id)m { return [[self displayIdentity] currentConfiguration]; }      // 0x1c77037e8
- (id)externalApplicationSceneHandles { return [super externalApplicationSceneHandles]; }                               // 0x1c7703654
- (id)runningApplicationScenes:(id)x { return [self externalApplicationSceneHandles]; }                                 // 0x1c7703898
- (BOOL)_shouldAutoHostScene:(id)s { return YES; }                                                                      // 0x1c770364c
```
Producer side, `SBExternalDisplayCoverSheetController`:
`-_postNotificationForExternalCoverSheetVisibilityDidChange:(BOOL)presented` 0x1c7791248 = `[[NSNotificationCenter defaultCenter] postNotificationName:(presented ? @"SBExternalDisplayCoverSheetDidPresent" : @"SBExternalDisplayCoverSheetDidDismiss") object:self]`. `-_updateExternalDisplayCoverSheetExistence` 0x1c62f34d4 / 0x1c77908f8 calls it right after `_setCoverSheetWindowVisible:fadeDuration:` (and in 16.2 also after `_setScreenOn:` -> `BKSDisplayServicesSetDisplayBlanked`, the already-DONE `blank` feature). The same method still calls `[systemShellSceneManager setSuspendedUnderLock:]` directly; the cast `_BSSafeCast(windowScene.sceneManager, SBSystemShellExternalDisplaySceneManager)` is now an NSAssert (`"failed to get a SBSystemShellExternalDisplaySceneManager. instead we got: %@"`), and `_embeddedHasAnyLockState` became `_shouldShowExternalCoverSheet` = `[_lockStateProvider hasAnyLockState]`.

(c) What it buys (inference): `_updateExternalDisplayCoverSheetExistence` safe-casts the window scene's manager to `SBSystemShellExternalDisplaySceneManager` and asserts otherwise, so a cover sheet can only exist for a system-shell display; a non-interactive display has none and (in 16.0) nothing suspended its scenes while the iPad was locked. With the notification those scenes are suspended like the main display's. The observers use `object:nil`, so the trigger is *any* external cover sheet, i.e. it only fires when a system-shell display is also connected: effectively groundwork for several external displays. Confidence: medium on the mechanism, medium-high on "marginal for a single external display".
(d) `SBSuspendedUnderLockManager initWithDelegate:eventQueue:`, `SBMainWorkspace +mainWorkspace/-eventQueue`, `SBSceneManager existingSceneHandleForScene: / externalApplicationSceneHandles / externalForegroundApplicationSceneHandles` all exist in 16.0. PARTIAL port (`covernote` is PORTABLE; `nilock` adds methods to the class with an associated-object manager, no ivar).

---------------------------------------------------------------------------------------------------

## 7. Education

16.0 `SBExternalDisplayEducationObserver` (`<SBDisplayManagerObserver>`, ivars `_managerObserverToken`, `_awaitingPresentationAssertion`), created in `-[SpringBoard applicationDidFinishLaunching:]` (0x1c5ed795c): on `displayManager:didConnectToRootDisplay:` (0x1c6331f08) `if (!defaults.extendedDisplayEverEnabledWithHardwareReqsSatisfied && !defaults.extendedDisplayEverEnabledWithoutHardwareReqsSatisfied) defaults.mirroringEnabled = YES;` and `invalidateAssertionIfNeeded` drops the awaiting-presentation assertion once `hasShownAllExtendedDisplayEducations`.

16.2 replaces it with an observer of the four policy notifications of 4.1-4.3 and a per-display `SBExternalDisplayEducationSession`:

```objc
@interface SBExternalDisplayEducationObserver : NSObject { id<BNPosting> _bannerPoster; SBExternalDisplayEducationSession *_educationSession; }
- (instancetype)initWithBannerPoster:(id<BNPosting>)p;     // 0x1c77d2958; created in -[SpringBoard applicationDidFinishLaunching:] (0x1c734bea4)
  // observes: ...PolicyConnectNotification -> _extendedDisplayControllerDidConnect:     0x1c77d2ad4  (new Session; NSAssert if one already exists; [session displayConnected])
  //           ...PolicyDisconnectNotification -> _extendedDisplayControllerDidDisconnect: 0x1c77d2cac ([session displayDisconnected]; nil)
  //           ...DeviceConnectionWindowExpiredNotification -> _deviceConnectionWindowExpired: 0x1c77d2dc8
  //           ...HardwareAvailabilityNotification -> _hardwareAvailabilityChanged: 0x1c77d2ed8 ([session updateHardwareAvailability:withinDisplayConnectionWindow:])
```
`SBExternalDisplayEducationSession` (0x1c77d3164..0x1c77d5078): `{displayIdentity, displayDisconnectSignal, isHardwareAvailable, isHardwareAvailableDuringDisplayConnectionWindow, bannerPoster, previousPresentedReasons (= defaults.externalDisplayEducationReasons bitmask), isPresenting, alertHandle, xpcConnection, listener, educationBannerViewController, bannerDismissTimer}`.
Reason bits (written with `setExternalDisplayEducationReasons:` by the alert completion blocks 0x1c77d37b8 / 0x1c77d3978 / 0x1c77d4238 / 0x1c77d3e8c): `1` = alert shown for "hardware present in the connection window", `2` = alert shown for "window expired without hardware". Flow (re-derived from the branch structure; the decisions below are exact, the log/format strings are not decoded):

* `displayConnected`: `reasons == 0` -> alert. Else if the hardware was present in the window: mask 1 clear -> alert, mask 1 set -> banner. Else (no hardware yet): `reasons == 3` -> banner, otherwise wait (the window expiry or a hardware change decides).
* `deviceConnectionWindowExpired` (only if no hardware in the window and nothing is presenting): mask 2 set -> banner, else alert.
* `updateHardwareAvailability:withinDisplayConnectionWindow:`: ignores no-hardware -> no-hardware; stores the new availability; the first availability seen inside the window is latched in `isHardwareAvailableDuringDisplayConnectionWindow`; if nothing is presenting it behaves like `displayConnected` for the hardware case, if an alert is up it tells it over XPC (`externalDisplayHardwareRequirementsSatisfiedChanged:`), if the pill is up it calls `updateExtendedDisplayEnabled:`.
* `_presentEducationAlert:` builds an `SBSRemoteAlertHandle` (service `com.apple.SpringBoardEducation`, view controller class `SBERemoteViewController`, `prefersEmbeddedDisplayPresentation`, anonymous XPC endpoint for the `SBRemoteHandshakeProtocol`, userInfo `{hardware-in-window: BOOL}`); the response action carries a flag: `2` -> `defaults.setMirroringEnabled:YES` (user picked mirroring), `1` -> NO (extended); completion records the reason bit. `NSAssert("we can only show education banner / alert once per display connection session")`.
* `_presentBanner`: `SBExternalDisplayEducationPillViewController initWithExtendedDisplayEnabled:` (a `BNPresentable` hosting a `PLPillView`) posted through `BNPosting postPresentable:withOptions:userInfo:error:`, auto-dismissed by a `BSAbsoluteMachTimer`; tap (`pillViewControllerDidReceiveUserTap:` 0x1c77d4e50) dismisses and opens `prefs:root=DISPLAY&path=DISPLAY_ARRANGEMENT` via `_SBWorkspaceActivateApplicationFromURL`.
* `displayDisconnected`: signal; dismiss alert/banner with reason "Display Disconnected".

(c) User-visible: first-run teaching alert plus a recurring status pill ("extended display on/off", tap for settings). Medium value, high confidence in what it does.
(d) BannerKit poster (`BNPosting`, present in 16.0 as `SBBannerManager`), `PLPillView`, the remote alert content of `SBERemoteViewController` (outside SpringBoard; the 16.0 strings `com.apple.SpringBoardEducation.external-display` and `SBERemoteViewController` exist but the external-display page is not guaranteed), `externalDisplayEducationReasons` (SpringBoardFoundation; 16.0 has the two BOOLs `extendedDisplayEverEnabledWith[out]HardwareReqsSatisfied`), `_SBExternalDisplayEducationReasonMaskDescription`, the policy notifications. NOT PORTABLE. (hooks.m only suppresses the 16.0 observer's forced mirroring and posts the notifications.)

---------------------------------------------------------------------------------------------------

## 8. Remaining classes

* `SBDisplayArrangementItem` 0x1c7715aac..: base class (same four ivars, now `BSDescriptionStreamable`, `isEqual:`/`hash` over identity, relative identity, edge, offset); `SBExternalDisplayArrangementItem` is an empty subclass kept for compatibility. Refactor.
* `SBExternalDisplaySettings` (PTSettings, 0x1c74235f4 / 0x1c7423d8c): new `long long activeDisplayTrackingMethodology` (ivar 0x40, default set in `setDefaultValues`; row "Active Display Tracking" with `possibleValues:titles:`). Consumers are `-[SBWindowSceneManager activeDisplayWindowScene]` 0x1c74bf1f0 and `-[SBWorkspaceKeyboardFocusController _initWithWorkspace:...]` / `settings:changedValueForKey:` (other groups). Internal prototype setting. NOT PORTABLE alone.
* `SBExternalDisplayRuntimeAvailabilitySettings _moduleWithSectionTitle:` 0x1c5fabc44 / 0x1c7423fd8: adds a call to `_SBFIsChamoisExternalDisplayControllerAvailable()` to decide whether to show the section. Prototype UI only. Defaults (`requirePointer = requireHardwareKeyboard = YES`) unchanged.

---------------------------------------------------------------------------------------------------

## 9. Open questions and risks

1. **Who clears `mirroringEnabled` in 16.0?** Within SpringBoard nothing; only an external writer of the defaults domain (Settings via a different path, `defaults write`, or the service bug fixed in 5.1) can. If a 16.0 UI writes the domain directly, the `autoext` observer sees it as a user preference (1/2), which is the intended 16.2 meaning.
2. **Defaults vs actual state.** In 16.2 when the hardware arrives inside the window the display becomes extended but `defaults.mirroringEnabled` stays `YES` (it was set to `!met` at connect), so `_displayInfoForDisplayIdentity:` reports mirroring to Settings while the display is extended. This is faithful to 16.2; I kept it.
3. **Weak ivar read.** `_displayController` is a weak ivar. `BP4_Ivar` uses `object_getIvar`, which loads weak ivars correctly on Apple runtimes; if this ever returns nil the only effect is a missed `requestUpdate:`.
4. **Timer type.** 16.2 uses `BSContinuousMachTimer` (counts across sleep). The hook uses `dispatch_after` (does not). Only matters if the iPad sleeps inside the 4 s window.
5. **Observer ordering at connect.** `displayManager:didConnectToRootDisplay:` observers run after the controller connected; the 16.0 education observer would overwrite the decision, hence `hk_eduConnect`.
6. **Nilock trigger.** The notification producer exists only for system-shell displays; the feature is EXPERIMENTAL and off unless `Backport162.on.nilock` exists.
7. **Self-triggered observer.** The hook sets `mirroringEnabled` and only then registers its observer (same order as 16.2). If the defaults layer delivered that very change late, `userPref` would be set to the value the automatic rule produced anyway (`mirror` when `!met`, `extend` when `met`), which pins the automatic decision and disables the hardware-window upgrade for that connection. Same exposure in 16.2; not observed.
8. Not decoded (no effect on the port): the `keepOtherModes` flag of the extended policy's `displayPreferences`, the exact format strings of the new `os_log` lines, and the NSAssert line numbers of `SBSystemShellExtendedDisplayControllerPolicy.m`.
9. Verification status: nothing here was run on a device. `hooks.m` was syntax-checked with clang (`-fobjc-arc -fblocks -Wall -Wextra`) against hand-written stubs for Foundation/objc/dispatch, both with and without `__APPLE__`.

---------------------------------------------------------------------------------------------------

## 10. Address index (16.0 / 16.2)

SBDisplayManager: `displayMonitor:didConnectIdentity:withConfiguration:` 0x1c64d47a4 / 0x1c798ff88; `_connectToIdentity:...forDisplayManagerInit:` - / 0x1c7990164 (block 0x1c79907d8); `initWith...powerLogReporter:` 0x1c64d3e80 / 0x1c798f60c; `willDisconnectIdentity:` 0x1c64d509c / 0x1c7990b4c; `assertionCoordinator:activeAssertionPreferencesHaveChanged:` 0x1c64d5608 / -; `assertionCoordinator:updatedAssertionPreferences:oldPreferences:forDisplay:` - / 0x1c7991098; `_setDisplayArrangementItem:forDisplay:` - / 0x1c7991278; `_setPowerLogEntry:forDisplay:` - / 0x1c799167c; `_setCloneMirroringMode:forDisplay:` - / 0x1c79917ac; `_setDisableIdleSleepReason:forDisplay:` - / 0x1c7991bd4; `_SBDisplayIdentityRecord initWithIdentity:connectedAtInit:` - / 0x1c7992a2c.
Assertions: `SBDisplayAssertionCoordinator activateAssertionsForDisplay:` - / 0x1c77de510; `assertionStack:updatedAssertionPreferences:oldPreferences:` - / 0x1c77deb20; `_SBDisplayAssertionStack activateAssertionsForDisplay:` - / 0x1c74d1898; `_evalAndApplyOldPreferences:newPreferences:` 0x1c6055690 / 0x1c74d2744.
SBSceneHostingDisplayController: connect 0x1c5f47120 / 0x1c73bbc30; didUpdate 0x1c5f476fc / 0x1c73bc150; didDisconnect 0x1c5f47a64 / 0x1c73bc47c; `_ensureCADisplayUpToDate:completion:` 0x1c5f48424 / 0x1c73bce50; `_updatePolicyForPresentation:` 0x1c5f48b44 / 0x1c73bd620; `_createDisplayAssertionPreferences` 0x1c5f4a328 / 0x1c73bed8c; `requestUpdate:` 0x1c5f46ddc / 0x1c73bb8ec; `isConnected` - / 0x1c73bb840. SBSceneHostingDisplayPreferences init - / 0x1c788f4f4.
Provider: didConnect 0x1c5ed1ea0 / 0x1c7345f0c; didDisconnect 0x1c5ed1f90 / 0x1c7345fe0; infoForConnecting 0x1c5ed2044 / 0x1c73460b4; transformDisplayConfiguration: 0x1c5ed2218 / 0x1c7346334.
Extended policy: `connectToDisplayController:displayConfiguration:` 0x1c63386b4 / 0x1c77dba48; `displayControllerShouldHaveControlOfDisplay:` 0x1c6339774 / -; `_wantsControlOfDisplay` - / 0x1c77dd1f8; `_hardwareAvailabilityChanged` - / 0x1c77dd8e4; `displayPreferencesForDisplayController:` - / 0x1c77dd034; `assertionPreferencesForDisplay:displayConfiguration:` - / 0x1c77dd0e8; `displayControllerWillDisconnect:sceneManager:` - / 0x1c77dc440; `updatePresentation...` 0x1c6339470 / 0x1c77dcbe0; `_areRuntimeAvailabilityRequirementsMet` 0x1c6339f38 / 0x1c77dd660; `settings:changedValueForKey:` 0x1c633a1bc / 0x1c77ddad8.
Non-interactive policy: `displayPreferencesForDisplayController:` - / 0x1c78e9674; `assertionPreferencesForDisplay:displayConfiguration:` - / 0x1c78e96f0; `updatePresentation...` 0x1c6437860 / 0x1c78e92ec; `connectToDisplayController:` 0x1c643688c / 0x1c78e832c.
Non-interactive scene manager: see section 6 (all `0x1c77034e4..0x1c770389c`).
Cover sheet: `_postNotificationForExternalCoverSheetVisibilityDidChange:` - / 0x1c7791248; `_updateExternalDisplayCoverSheetExistence` 0x1c62f34d4 / 0x1c77908f8; `_setCoverSheetWindowVisible:fadeDuration:` 0x1c62f3a54 / 0x1c7790c50; `_setScreenOn:` 0x1c62f367c / 0x1c7790b4c.
Service: `setDisplayMirroringEnabled:forDisplay:` 0x1c6332afc / 0x1c77d5db4 (block 0x1c6332be0 / 0x1c77d5ebc); `initWithDisplayManager:` 0x1c63321d0 / 0x1c77d52a4; `initWith...configureConnectionListener:` - / 0x1c77d52ac; `preferredArrangementOfDisplay:relativeTo:` - / 0x1c77d5620.
Education: Observer init - / 0x1c77d2958, Session init - / 0x1c77d3164, `displayConnected` - / 0x1c77d33c4, `_presentEducationAlert:` - / 0x1c77d4628, `_presentBanner` - / 0x1c77d4b30, Pill `initWithExtendedDisplayEnabled:` - / 0x1c77e7d18; 16.0 observer `displayManager:didConnectToRootDisplay:` 0x1c6331f08.
Settings: `SBExternalDisplaySettings setDefaultValues` 0x1c5fab324 / 0x1c74235f4; `activeDisplayTrackingMethodology` - / 0x1c7423d8c.
Frameworks: `_SBFIsChamoisExternalDisplayControllerAvailable` SpringBoardFoundation 16.2 0x18ee096e4 (absent in 16.0); `BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay` BackBoardServices 16.2 0x18e488274 (absent in 16.0); `-[SBSExternalDisplayService setMirroringEnabled:forDisplay:]` SpringBoardServices 16.0 0x191bd4f70.
