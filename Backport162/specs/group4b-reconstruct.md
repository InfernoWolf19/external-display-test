# Group 4b reconstruct: the pieces group 4 called NOT PORTABLE

Build under test: iPadOS 16.0 `20A8372`. Reference: iPadOS 16.2 `20C65`. Addresses are `16.0 / 16.2` vm addresses (dyld shared
cache, unslid) unless a daemon is named. backboardd addresses are file vmaddrs of the 16.0 `backboardd` binary
(`bbd/backboardd`, source version 540.1.1.0.0, arm64e, stripped; image base 0x100000000, add the ASLR slide of image 0).
Companion files: `group4b-reconstruct.hooks.m` (Logos source for SpringBoard) and `group4b-backboardd.x` (separate Theos target
for backboardd, filter plist and Makefile fragment inside the file header).

Read first (not repeated): `STATUS.md`, `group4-connect-service-lock.md`, `group4-disconnect-focus-pointer.md`, `REVIEW-0.5.0.md`.
Per-piece tag: DONE (complete reconstruction, nothing known missing) or UNSURE:<what to check on a device>.
Order of this file = order of the work package: 1 clone mirroring, 2 education, 3 presentation update subset, 4 deferred
activation, 5 per-scene pointer lock, 6 window migration + focus-lock reasons, 7 settings/arrangement, 8 display-mode facts.
(autoext and mirrorsvc are not reinstalled: ExtendedDisplayEnabler provides them.)

---------------------------------------------------------------------------------------------------

## 1. Clone mirroring (`cloneMirroringMode`, `_setCloneMirroringMode:forDisplay:`, BKS destination API)   [UNSURE: see 1.7]

### 1.1 What the 16.2 BackBoardServices function really is

`BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay(NSString *displayUUID, BKSDisplayServicesCloneMirroringMode mode)`
(16.2 `0x18e488274`, block `0x18e4886ec`), fully decoded. It is a client-side request stack plus one MIG message.

```objc
// BKSDisplayServices.m (16.2).  Returns id<BSInvalidatable> (a BSSimpleAssertion, reason "CloneMirroring").
static NSMutableDictionary<NSString *, NSMutableArray<_BKSCloneMirroringModeRequest *> *> *sRequests;   // 0x1da520000+0x9c0, lazily created

id BKSDisplayServicesSetMainDisplayCloneMirroringModeForDestinationDisplay(NSString *displayUUID, unsigned long long mode) {
    NSCParameterAssert(displayUUID);   // "Value for 'displayUUID' was unexpectedly nil. Expected %@." BKSDisplayServices.m:0x145; also asserts NSString class
    if (!sRequests) sRequests = [NSMutableDictionary new];
    _BKSCloneMirroringModeRequest *req = [_BKSCloneMirroringModeRequest new];  req.displayUUID = displayUUID;  req.mode = mode;   // 2 ivars: mode @8, displayUUID @0x10
    NSString *ident = [NSString stringWithFormat:@"%@:%@", displayUUID, NSStringFromBKSDisplayServicesCloneMirroringMode(mode)];
    BSSimpleAssertion *a = [[BSSimpleAssertion alloc] initWithIdentifier:ident forReason:@"CloneMirroring" invalidationBlock:^(BSSimpleAssertion *x) {
        /* block 0x18e4886ec, see below */ }];
    NSUInteger before = [sRequests[displayUUID] count];
    [sRequests bs_addObject:req toCollectionClass:[NSMutableArray class] forKey:displayUUID];   // append
    if (before == 0) {                       // only the FIRST request for a destination talks to backboardd
        char uuid[0x400] = {0};  CFStringGetCString((CFStringRef)displayUUID, uuid, 0x400, kCFStringEncodingUTF8);
        mach_port_t p = _BKSServerPortHelper("com.apple.backboard.display.services", ...);
        _BKSDisplaySetCloneMirroringModeForDestinationDisplay(p, uuid, (uint8_t)mode);          // MIG id 0x5b9174
    }
    return a;
}
// invalidation block:
//   old = [[sRequests[uuid] firstObject] mode];  [sRequests bs_removeObject:req fromCollectionForKey:uuid];
//   new = [[sRequests[uuid] firstObject] mode];  char uuid[0x400] = ...;
//   if ([sRequests[uuid] count] == 0)  _BKSDisplayRemoveCloneMirroringModeForDestinationDisplay(port, uuid);   // MIG id 0x5b9175
//   else if (old != new)               _BKSDisplaySetCloneMirroringModeForDestinationDisplay(port, uuid, new);
```
Semantics: per destination display (hardware UUID string) a FIFO of requests; the OLDEST live request wins; the daemon sees only
"set mode for destination" and "remove destination". The modes are `0 default, 1 forceMirroring, 2 disableMirroring, 3 replay`
(`_NSStringFromBKSDisplayServicesCloneMirroringMode`, table 0x1d5a668b8: "default" "forceMirroring" "disableMirroring" "replay").
The old global call also changed in 16.2: `BKSDisplayServicesSetCloneMirroringMode(mode)` (16.2 0x18e488214) now sends a SIMPLE
message (id 0x5b9173, size 0x24, mode byte) with no port, whereas 16.0 (0x18e201090 -> `__BKSDisplaySetCloneMirroringMode`
0x18e235c04) sends a COMPLEX message (id 0x5b9173, size 0x34, 1 port descriptor made from a process-wide receive port, mode byte at +0x38).
Also all MIG ids above 0x5b9173 in the BKS display subsystem shifted by 2 in 16.2 (16.0 `SetVirtualDisplayClientPID` = 0x5b9174,
`DisplayIsTethered` = 0x5b9175; 16.2 puts the two new routines there). So 16.2 client code cannot talk to a 16.0 daemon and the
numbers 0x5b9174/0x5b9175 MUST NOT be reused on 16.0 (they would hit SetVirtualDisplayClientPID / DisplayIsTethered).

### 1.2 How SpringBoard 16.2 uses it

`-[SBDisplayManager _setCloneMirroringMode:forDisplay:]` (16.2 0x1c79917ac), decoded in `group4-connect-service-lock.md` 2.5; the
only caller is `-assertionCoordinator:updatedAssertionPreferences:oldPreferences:forDisplay:` (0x1c7991098). The value comes from
`SBDisplayAssertionPreferences.cloneMirroringMode` (ivar 0x28; `copyWithZone:` 0x1c7953638 copies it; `isEqual:`/`hash` include it).
Producers (found with the selector xref `setCloneMirroringMode:`): `-[SBSystemShellExtendedDisplayControllerPolicy assertionPreferencesForDisplay:displayConfiguration:]`
(0x1c77dd1cc) sets `2` (`SBDisplayCloneMirroringMode.Disabled`), `-[SBNonInteractiveDisplayControllerPolicy assertionPreferencesForDisplay:...]`
(0x1c78e9808) and `-[SBMirroredDisplayController _updateDisplayAssertion]` (0x1c7466510) set `1` (`.Default`). Mapping in `_setCloneMirroringMode`:
SB 1 -> BKS 0, SB 2 -> BKS 2, anything else `NSAssert` ("unexpected mirroring mode: %lu"); SB 0 ("no preference") releases the token; the main
display never calls BKS. Tokens live in `_rootIdentityToCloneMirroringModeTokens` (0x60), values in `_rootIdentityToCloneMirroringMode` (0x58).
The assertion stack only forwards the preferences of the ACTIVE assertion (`__SBActiveAssertion`, 16.0 0x1c60551a0: the highest-level
assertion with `wantsControlOfDisplay`), so while SpringBoard does not want control of the display the mode is 0 (released).

### 1.3 What 16.0 backboardd does today (the "other path")

All of this is in the 16.0 `backboardd` binary, class `BKTVOutController` (ivars: `_workQueue` @8, `_queue_replayCloneContextIDs` @0x10,
`_queue_currentVirtualDisplayClientPID` @0x18 (int), `_queue_currentCloneMirroringClient` @0x20, `_blankingContext` @0x28,
`_systemShellObserving` @0x30, `_queue_cloneRotationDisabled` @0x38, `_queue_forceTVOutMode` @0x39, `_queue_tvOutDisplayHasAvailableModes` @0x3a,
`_tvOutMode` @0x3c) and `_BKCloneMirroringClient` (`mode`, `versionedPID`, `delegate`, port sentinel + watcher).

* Receiving: BKS display server subsystem (`mig_subsystem` at 0x1000e56a8, ids 0x5b9168..0x5b9182, lookup function `0x1000997f4`:
  `idx = id - 0x5b9168; if (idx > 0x1a) return NULL; return table[idx].stub`; each descriptor is 0x28 bytes, stub at +8). The stub of id
  0x5b9173 is 0x100098644. It validates a complex message (size 0x34, 1 descriptor), checks the entitlement
  `com.apple.backboardd.virtualDisplay` of the sender (helper 0x10001615c: pid == self, or no entitlement required, or
  `-[BSAuditToken hasEntitlement:]`), and runs block `0x100025e4c`, which builds `BSAuditToken initWithAuditToken:`, `BSPort initWithPort:`,
  `_BKCloneMirroringClient initWithMode:port:auditToken:` and does `dispatch_async(controller._workQueue, block 0x10004ecb4)` where the
  controller is the `BKTVOutController` singleton (`0x10004ce50`, a C function taking the class).
* Block `0x10004ecb4`: `if (new.mode == cur.mode) return;  if (cur.mode != 0 && new.versionedPID != cur.versionedPID) { log "Ignoring request to set mirroring mode to %lu, current setting %lu is owned by vpid %@"; return; }  cur = new; new.delegate = controller; reapply(controller);`
  i.e. ONE global owner process at a time; mode 0 releases.
* `reapply(controller)` = `0x10004cffc`: for every `CAWindowServerDisplay` `d` in `[[CAWindowServer serverIfRunning] displays]`: if `d.name == "Wireless"`, or
  `d.name == "TVOut"` and `!_queue_forceTVOutMode`: `if (main && [main.clones containsObject:d]) [main removeClone:d]; updateClone(controller, d);`.
* `updateClone(controller, d)` = `0x10004c930` (decoded completely): `tag = d.tag; mode = [controller._queue_currentCloneMirroringClient mode]`.
  `tag & 0x60` (CarPlay) -> log, return. `d == main` -> log, return. `disable = defaults.disableCloneMirroring || mode == 2`.
  `dpTether = [BKTetherController sharedInstance].isTethered ? .usesDisplayPortTethering : NO`. If `!disable` and the capability
  `display-mirroring` (BSSystemHasCapability, cached at 0x10010c9f0) is set: `[main addClone:d options:{rotationDisabled, overscan/scaling/YUV flags, replay context ids if mode == 3}]`.
  Then, always: `w0 = (forced || dpTether) ? 1 : defaults.forceCloneMirroring; w8 = dpTether ? (w0 & ~[d.name isEqual:"TVOut"]) : w0;`
  `d.tag = (tag & ~5) | (((tag & 0x78) == 0) << 2) | w8` (bit 0 = "mirrored"), `d.processId = controller._queue_currentVirtualDisplayClientPID`.
  `forced` = `(mode & ~2) == 1` (mode 1 or 3). Note mode 2 skips only the `addClone`; removal of an existing clone is done by the sweep in `reapply`.
* Display connect path: `availableModesDidChange` (0x10004d7a4) calls `updateClone` for every new `TVOut`/`Wireless` display (log strings "Available modes changed
  (%@) on %@; clones:%@", "Setting up clone"), and `removeClone` when the display lost all modes.
* Only `BKTVOutController` touches `addClone:`/`removeClone:` (`bl 0x10009e2e0` once, `bl 0x1000a4de0` three times, all inside it), so this is the
  single decision point for "mirror or not".
* SpringBoard 16.0 never calls `BKSDisplayServicesSetCloneMirroringMode` (no import in `SpringBoard`; FrontBoard imports the stub but has no caller);
  the only 16.0 caller in the whole cache is MediaExperience (`FigRoutingManagerSetMirroringModeOnBKSDisplayServices`, AirPlay mirroring, mode 1).
  So on 16.0 backboardd clones EVERY external `TVOut`/`Wireless` display automatically (default mode 0); SpringBoard's extended mode works
  only because the external display then has its own render contexts. 16.2 adds the explicit "SpringBoard owns this destination: do not clone it" request,
  which closes the window between "display appears" and "SpringBoard has a context on it" (inferred, UNSURE) and stops AirPlay's forced mirroring from
  fighting an extended display.

### 1.4 What 16.2 backboardd does (no binary available here)

Not extracted. From the client protocol: three routines (set legacy global mode, set per-destination mode, remove per-destination mode) and a request
key that is the display hardware UUID (`-[FBSDisplayConfiguration hardwareIdentifier]`, which equals the daemon's `-[CAWindowServerDisplay uniqueId]`; the
daemon already uses `uniqueId` with `screenInfoForScreenID:` in the Wireless branch). The new design below only needs the observable contract: "destination
mode 2 => `updateClone` does not add (and the sweep removes) the clone for that display".

### 1.5 Design for 16.0

Two sides, both new.

SpringBoard (hooks.m, feature `clonemirror`):
1. `SBDisplayAssertionPreferences` gets `cloneMirroringMode` (associated object, `%new` getter/setter) and `copyWithZone:` / `isEqual:` / `hash` / `description` hooks that carry it.
2. `-[SBSceneHostingDisplayController _createDisplayAssertionPreferences]` (16.0 0x1c5f4a328) is hooked: after `%orig` it asks the policy (`_policy` ivar)
   via a `%new` method `displayControllerCloneMirroringMode:` added to `SBSystemShellExtendedDisplayControllerPolicy` (returns 2) and
   `SBNonInteractiveDisplayControllerPolicy` (returns 1) and sets the field. (`SBMirroredDisplayController` asserts `1`; 1 maps to "no daemon request" in 16.0, so it is not hooked.)
3. `-[SBDisplayManager assertionCoordinator:activeAssertionPreferencesHaveChanged:]` (16.0 0x1c64d5608) is hooked: after `%orig` the dictionary
   display -> active prefs is walked and `-_bp_setCloneMirroringMode:forDisplay:` (`%new`, exact port of 16.2 `_setCloneMirroringMode:forDisplay:` with the two dictionaries kept
   as associated objects) is called for every display present, and with 0 for displays that vanished from the dictionary. `displayMonitor:willDisconnectIdentity:` releases the token.
4. `BP_BKSSetCloneModeForDestination(uuid, bksMode)` is a faithful C/ObjC re-implementation of the 16.2 BKS function (request FIFO per UUID, token = small `G4BCloneToken` object with `invalidate`)
   whose transport is `G4B_SendCloneMsg(uuid, mode, remove)`:
   * primary transport: a custom MIG message to `com.apple.backboard.display.services` (ids `0x5b9fa0` set / `0x5b9fa1` remove, send + receive with a 0.5 s timeout) handled by the new backboardd tweak;
   * if the reply does not arrive or is `MIG_BAD_ID` (-303) (stock 16.0 backboardd), fall back once to the 16.0 BKS global API `BKSDisplayServicesSetCloneMirroringMode(mode)` resolved with `dlsym`
     (semantic: global instead of per destination, only if the sender holds `com.apple.backboardd.virtualDisplay`; UNSURE whether SpringBoard does).
   The 16.0 daemon translation of SB modes: BKS 0 (Default) = remove the destination override (so mediaserverd's forced mirroring and the user default keep working), BKS 2 = override "disabled".

backboardd (`group4b-backboardd.x`, Theos target `Backport162BBD`, filter `backboardd`):
1. Hook the routine lookup `0x1000997f4` (12 instructions, leaf, no PAC prologue; prologue words verified) so ids `0x5b9fa0/0x5b9fa1` return our `mig_routine_t`; everything else calls the original.
2. Our routine validates the message (size, NUL-terminated UUID, trailer audit token), accepts only SpringBoard (`proc_pidpath` suffix `/SpringBoard`, euid mobile or root), stores `uuid -> mode` in a dictionary
   (owner pid recorded, `DISPATCH_SOURCE_TYPE_PROC` exit watcher clears the owner's entries) and runs `reapply(controller)` (the original `0x10004cffc`) on `controller._workQueue`.
3. Hook `updateClone` (`0x10004c930`, prologue verified): if an override exists for `[d uniqueId]`, swap `controller._queue_currentCloneMirroringClient` for a proxy `_BKCloneMirroringClient`
   subclass whose `mode` is the override (raw pointer swap through `ivar_getOffset`, restored right after the original returns), so the whole original decision tree (CarPlay/self checks, options
   dictionary, tags, process id) is reused unchanged.

### 1.6 Failure behaviour

If the tweak is not loaded in backboardd, SB falls back to the legacy global call (or does nothing); if neither works the 16.0 behaviour is unchanged. Every step is guarded and logged under `Backport162.debug`.

### 1.7 Tag

UNSURE. (a) Whether `FBSDisplayConfiguration.hardwareIdentifier` equals `CAWindowServerDisplay.uniqueId` (check: log both; the hook logs the UUID it sends and the daemon logs the UUID it compares). (b) Whether stock
16.0 clones an extended-mode external display at all (read the daemon log `Add display clone` / `Display is already cloned` in the oslog with the extended display plugged in); if it does not, the feature is a harmless
no-op. (c) The hook of `0x1000997f4` as a non-PAC leaf: on arm64e Dopamine (ElleKit) leaf hooks with a 16-byte patch are fine in principle but untested. (d) `mach_msg` on the BKS port with an unknown id: the BS MIG listener may drop
the message without a reply (then the SB side times out after 0.5 s and uses the fallback; harmless).

---------------------------------------------------------------------------------------------------

## 2. Education rework (`SBExternalDisplayEducationObserver` / `Session` / `PillViewController`)   [UNSURE: 2.6]

All three classes, the notification contract and the defaults key are decoded below; the code is in the hooks file (group `G4B_Edu`).

### 2.1 Defaults key (SpringBoardFoundation)

16.2 `SBExternalDisplayDefaults` (`-_bindAndRegisterDefaults` 0x18ee1100c) binds seven properties with `_bindProperty:withDefaultKey:toDefaultValue:options:`; the new one is
`unsigned long long externalDisplayEducationReasons` <-> defaults key **`SBExternalDisplayEducationReasons`** (default `@0`; the neighbours are `SBExternalDisplayMirroringEnabled`,
`SBExternalDisplayArrangementEdge/Offset`, `SBDisplayModeSettings`, `SBExtendedDisplayContentsScaleAndDontFileRadars`). 16.0 has instead two BOOL properties
`extendedDisplayEverEnabledWithHardwareReqsSatisfied` / `...WithoutHardwareReqsSatisfied` and `-hasShownAllExtendedDisplayEducations`. Reconstruction: `%new externalDisplayEducationReasons` /
`setExternalDisplayEducationReasons:` on `SBExternalDisplayDefaults`, stored with `CFPreferences` (`com.apple.springboard`, key above); if the key is absent the value is migrated from the
16.0 booleans (WithHardwareReqsSatisfied -> bit 1, Without... -> bit 2). Bits: **1** = "hardware requirements satisfied" alert was presented, **2** = "not satisfied" alert was presented
(mask `_SBExternalDisplayEducationReasonMaskDescription` is log text only).

### 2.2 Observer (16.2 `SBExternalDisplayEducationObserver`, ivars `_bannerPoster` @8, `_educationSession` @0x10)

* Created in `-[SpringBoard applicationDidFinishLaunching:]` (16.2 0x1c734bea4): `[[SBExternalDisplayEducationObserver alloc] initWithBannerPoster:[self bannerManager]]`, stored in `SpringBoard._displayConnectionObserver`.
  (16.0 creates the OLD observer there at 0x1c5ed795c, only if `_SBIsDeviceChamoisCapable() && ![defaults hasShownAllExtendedDisplayEducations]`, together with a BSSimpleAssertion
  "com.apple.SpringBoardEducation.external-display" / "Has not presented all external display educations".) Port: hook `hasShownAllExtendedDisplayEducations` to return YES, which makes the stock
  code create neither the old observer nor the assertion; then create the new one after `%orig` and keep it in an associated object (the ivar's type is the old class).
* `initWithBannerPoster:` (0x1c77d2958): stores the poster; observes on the default `NSNotificationCenter` the four notifications `...PolicyConnectNotification` (`_extendedDisplayControllerDidConnect:`),
  `...PolicyDisconnectNotification` (`_extendedDisplayControllerDidDisconnect:`), `...PolicyDeviceConnectionWindowExpiredNotification` (`_deviceConnectionWindowExpired:`),
  `...ControllerHardwareAvailabilityNotification` (`_hardwareAvailabilityChanged:`). `dealloc` removes itself.
* Handlers: userInfo keys `kSBSystemShellExtendedDisplayControllerDisplayIdentityKey` (required, NSAssert "no displayIdentity for notification userInfo"),
  `...HardwareAvailabilityIsAvailableKey` (required on connect + hardware), `...FiredDuringDeviceConnectionWindowKey` (required on hardware).
  connect: assert no session; `_educationSession = [[Session alloc] initWithDisplayIdentity:id hardwareAvailability:avail bannerPoster:_bannerPoster]; [session displayConnected]`.
  disconnect: assert a session; `[session displayDisconnected]; _educationSession = nil`. windowExpired: `[session deviceConnectionWindowExpired]`.
  hardware: if `[session.displayIdentity isEqual:id]` -> `[session updateHardwareAvailability:avail withinDisplayConnectionWindow:inWindow]`, else NSAssert ("being told hardware availability changed but we're not tracking...").
  The port replaces the NSAsserts by logged early returns.
* Producer of the four notifications: the 16.2 `SBSystemShellExtendedDisplayControllerPolicy` (decoded in `group4-connect-service-lock.md` 4.1-4.3). On 16.0 nobody posts them (Group4Connect.m's
  autoext producer is not installed), so the group also contains a PASSIVE producer (observation only, it changes no decision): hook `connectToDisplayController:displayConfiguration:` (after `%orig`:
  post Connect with `met = [policy _areRuntimeAvailabilityRequirementsMet]`, open a 4 s window, observe `SBHardwareKeyboardAvailabilityChangedNotification` and the policy's `_mousePointerManager`),
  `displayControllerDidDisconnect:sceneManager:` (post Disconnect), and the 4 s timer posts WindowExpired unless disconnected; every hardware change posts HardwareAvailability with `inWindow` = window still open.

### 2.3 Session (16.2 `SBExternalDisplayEducationSession`, 0x1c77d3164..0x1c77d5084; ivars: `_displayIdentity` 8, `_displayDisconnectSignal` 0x10, `_isHardwareAvailable` 0x18, `_isHardwareAvailableDuringDisplayConnectionWindow` 0x19, `_bannerPoster` 0x20, `_previousPresentedReasons` 0x28, `_isPresenting` 0x30, `_alertHandle` 0x38, `_xpcConnection` 0x40, `_listener` 0x48, `_educationBannerViewController` 0x50, `_bannerDismissTimer` 0x58)

```objc
- (instancetype)initWithDisplayIdentity:(id)ident hardwareAvailability:(BOOL)hw bannerPoster:(id)poster {
    _displayIdentity = ident; _isHardwareAvailable = hw; _isHardwareAvailableDuringDisplayConnectionWindow = hw; _bannerPoster = poster;
    _bannerDismissTimer = [[BSAbsoluteMachTimer alloc] initWithIdentifier:[NSString stringWithFormat:@"SBExternalDisplayEducationSession-%@.bannerDismissTimer", ident]];
    _displayDisconnectSignal = [BSAtomicSignal new];
    _previousPresentedReasons = [[SBDefaults localDefaults].externalDisplayDefaults externalDisplayEducationReasons];   // log "creating session with previous reasons"
}
- (void)displayConnected {                     // 0x1c77d33c4
    reasons = _previousPresentedReasons;
    if (reasons == 0)                          [self _presentEducationAlert:^(NSUInteger ok){ if (ok) { r |= _isHardwareAvailableDuringDisplayConnectionWindow ? 1 : 2; defaults.externalDisplayEducationReasons = r; } }];   // block 0x7b8
    else if (_isHardwareAvailableDuringDisplayConnectionWindow) {
        if (reasons & 1) [self _presentBanner];                                                   // "have presented satisfied alert before. rolling banner now"
        else             [self _presentEducationAlert:^(ok){ if (ok) defaults.reasons = prev | 1; }];  // block 0x978, "haven't presented satisfied alert before"
    } else if (reasons == 3) [self _presentBanner];                                               // "have presented both alerts before"
    /* else: wait for deviceConnectionWindowExpired or a hardware change */
}
- (void)deviceConnectionWindowExpired {        // 0x1c77d3fe8; log "device connection window expired"
    if (_isHardwareAvailableDuringDisplayConnectionWindow || _isPresenting) return;
    if (_previousPresentedReasons & 2) [self _presentBanner];
    else [self _presentEducationAlert:^(ok){ if (ok) defaults.reasons = prev | 2; }];            // block 0x4238 (same shape as the other two)
}
- (void)updateHardwareAvailability:(BOOL)avail withinDisplayConnectionWindow:(BOOL)inWindow {   // 0x1c77d3ab4
    if (!_isHardwareAvailable && !avail) return;
    _isHardwareAvailable = avail;
    if (inWindow && !_isHardwareAvailableDuringDisplayConnectionWindow) _isHardwareAvailableDuringDisplayConnectionWindow = avail;
    if (_isHardwareAvailableDuringDisplayConnectionWindow && !_isPresenting) {
        if (!(_previousPresentedReasons & 1)) [self _presentEducationAlert:^(ok){ if (ok) defaults.reasons = prev | 1; }];   // block 0x3e8c
        else [self _presentBanner];
    } else if (_isPresenting) {
        if (_xpcConnection) [[_xpcConnection remoteObjectProxy] externalDisplayHardwareRequirementsSatisfiedChanged:_isHardwareAvailable];
        else if (_educationBannerViewController) [_educationBannerViewController updateExtendedDisplayEnabled:_isHardwareAvailableDuringDisplayConnectionWindow];
    }
}
- (void)displayDisconnected {                  // 0x1c77d4394
    [_displayDisconnectSignal signal];
    if (_isPresenting) { [self _dismissEducationAlert:@"Display Disconnected"]; [self _dismissBanner:@"Display Disconnected"]; }
}
```
Alert (`_presentEducationAlert:` 0x1c77d4628; NSAssert "we can only show education banner / alert once per display connection session" when `_isPresenting`; NSAssert on nil completion):
`_isPresenting = YES; _listener = [NSXPCListener anonymousListener]; _listener.delegate = self; [_listener activate];`
`def = [[SBSRemoteAlertDefinition alloc] initWithServiceName:@"com.apple.SpringBoardEducation" viewControllerClassName:@"SBERemoteViewController"]; def.prefersEmbeddedDisplayPresentation = YES;`
`cfg = [SBSRemoteAlertConfigurationContext new]; cfg.xpcEndpoint = [[_listener endpoint] _endpoint]; _alertHandle = [SBSRemoteAlertHandle newHandleWithDefinition:def configurationContext:cfg];`
`act = [SBSRemoteAlertActivationContext new]; act.userInfo = @{ SBEducationRemoteViewControllerEducationTypeKey: @1 /* 16.0 Stage Manager = @0 at 0x1c5fbc728 */, SBEducationRemoteViewControllerHasPointerAndKeyboardConnectedKey: @(_isHardwareAvailableDuringDisplayConnectionWindow) };`
`responder = [BSActionResponder responderWithHandler:^(BSActionResponse *resp){ ... }]; responder.queue = main; act.actions = [NSSet setWithObject:[[BSAction alloc] initWithInfo:nil responder:responder]]; [_alertHandle activateWithContext:act];`
Response block (0x1c77d497c): `if (resp.error) { log; result = 0; } else { flag = [resp.info flagForSetting:1]; result = (flag == BSSettingFlagUndefined(NSIntegerMax)) ? 0 : (flag == No ? 2 : 1); log "received response from user. externalDisplayEnabled: %{bool}u"; defaults.mirroringEnabled = (result == 2); } completion(result);`
So the remote alert answers "extended" (flag Yes -> 1) or "mirror" (flag No -> 2), and the session writes `mirroringEnabled` itself.
Listener delegate (0x1c77d4ed8): if disconnected -> reject; else `newConnection.exportedObject = self; exportedInterface = interfaceWithProtocol:SBRemoteHandshakeProtocol; remoteObjectInterface = interfaceWithProtocol:SBExternalDisplayHardwareRequirementsChangedProtocol; [newConnection resume]; _xpcConnection = newConnection`. `wakeUpConnection` is empty (exists to make the connection come up).
`_dismissEducationAlert:reason` (0x1c77d4490): via `_xpcConnection` -> `[[_xpcConnection remoteObjectProxy] dismissAnimated:YES]`, else via `[_alertHandle invalidate]` (logs which path).
Banner (`_presentBanner` 0x1c77d4b30, same NSAssert): `_isPresenting = YES; _educationBannerViewController = [[SBExternalDisplayEducationPillViewController alloc] initWithExtendedDisplayEnabled:_isHardwareAvailableDuringDisplayConnectionWindow]; vc.delegate = self; NSError *e; [_bannerPoster postPresentable:vc withOptions:1 userInfo:nil error:&e]` (error: log "error while presenting education banner: %@"), then `[_bannerDismissTimer scheduleWithFireInterval:3.0 leewayInterval:0.05 queue:main handler:^{ [weakSelf _dismissBanner:@"Timer"]; }]`.
`_dismissBanner:reason` (0x1c77d4dc8): `[_bannerPoster revokePresentablesWithIdentification:[BNPresentableIdentification uniqueIdentificationForPresentable:_educationBannerViewController] reason:reason options:0 userInfo:nil error:NULL]`.
Pill tap (0x1c77d4e50): `[_bannerDismissTimer invalidate]; _bannerDismissTimer = nil; [self _dismissBanner:@"User Interaction"]; _SBWorkspaceActivateApplicationFromURL([NSURL URLWithString:@"prefs:root=DISPLAY&path=DISPLAY_ARRANGEMENT"], nil);`

### 2.4 Pill view controller (`SBExternalDisplayEducationPillViewController : UIViewController <BNPresentable>`, ivars `_extendedDisplayEnabled` 0x380, `_pillView` 0x388, `_delegate` weak 0x390)

* `initWithExtendedDisplayEnabled:`: `loadViewIfNeeded; self.preferredContentSize = [_pillView intrinsicContentSize]`.
* `viewDidLoad`: leading accessory `UIImageView(image: systemImage "display" with configurationWithHierarchicalColor:UIColor.labelColor)`, trailing accessory `UIImageView(systemImage "chevron.right")`;
  `title = localized "STAGE_MANAGER_EXTENDED_DISPLAY"` (main bundle, empty table value); `_pillView = [[PLPillView alloc] initWithLeadingAccessoryView:lead trailingAccessoryView:trail]`;
  `centerContentItems = @[[[PLPillContentItem alloc] initWithText:title style:1], [self _pillSubtitleContentItem]]`; frame = view.bounds, autoresizing flexible both (0x12), `addSubview:`;
  `UITapGestureRecognizer(target:self action:@selector(_handleSingleTap:))` with 1 touch, 1 tap.
* `_pillSubtitleContentItem`: `PLPillContentItem(text: localized(_extendedDisplayEnabled ? "STAGE_MANAGER_EXTENDED_DISPLAY_ON" : "STAGE_MANAGER_EXTENDED_DISPLAY_OFF"), style: 2)`.
* `updateExtendedDisplayEnabled:` (no-op if unchanged): stores, `[_pillView updateCenterContentItem:centerContentItems[1] withContentItem:[self _pillSubtitleContentItem]]`.
* `_handleSingleTap:` -> `[_delegate pillViewControllerDidReceiveUserTap:self]`.
* BNPresentable: `requestIdentifier` = "ExternalDisplayEducation", `requesterIdentifier` = "com.apple.SpringBoard.ExternalDisplayEducation", `presentableDescription` = "External Display Education",
  `presentableBehavior` = 1, `viewController` = self. Everything else (dragging/touch-outside flags, `presentableType`) is not implemented (optional); BannerKit reads them with `respondsToSelector:`.
* Localised strings: the three keys live in the SpringBoard strings of 16.2; whether 16.0's table has them is unknown, so the port falls back to English `Extended Display` / `On` / `Off` when `localizedStringForKey:` returns the key itself.
* 16.0 has everything the pill needs: `PLPillView`, `PLPillContentItem initWithText:style:`, `updateCenterContentItem:withContentItem:` (PlatterKit 16.0 dump), `BNPosting` on `SBBannerManager`
  (`postPresentable:withOptions:userInfo:error:`, `revokePresentablesWithIdentification:reason:options:userInfo:error:`), `BNPresentableIdentification +uniqueIdentificationForPresentable:`.

### 2.5 New protocols (absent in 16.0): `SBRemoteHandshakeProtocol { wakeUpConnection }`, `SBExternalDisplayHardwareRequirementsChangedProtocol { dismissAnimated:, externalDisplayHardwareRequirementsSatisfiedChanged: }`,
`SBExternalDisplayEducationPillViewControllerDelegate { pillViewControllerDidReceiveUserTap: }`; declared in the hooks file with the 16.2 names (NSXPCInterface needs real Protocol objects;
the remote side matches by selector).

### 2.6 Tag UNSURE

(a) The remote alert content lives in the `SpringBoardEducation` service (`SBERemoteViewController`), outside the cache and not extracted here. 16.0 SpringBoard already presents it with `EducationType = 0`
(Stage Manager, `0x1c5fbc728`); 16.2 sends `EducationType = 1` (constant object at 0x1e18f9e58, +0x10 = 1) plus `HasPointerAndKeyboardConnected`. If the 16.0 service does not know type 1 it shows the wrong page
or nothing. Check on device: `ls /System/Library/CoreServices/SpringBoardEducation.app` and `strings` for `HasPointerAndKeyboardConnected` / `externalDisplayHardwareRequirementsSatisfiedChanged`.
Mitigation shipped: `Backport162.on.edunative` replaces the remote alert by a native `UIAlertController` in a SpringBoard window on the iPad (same results 1/2, same reason bits). Default stays remote (faithful).
(b) English strings of the pill. (c) The passive notification producer must not double the work of ExtendedDisplayEnabler (it only observes).

---------------------------------------------------------------------------------------------------

## 3. Presentation-update scene subset (`boundPointerUIScenes`, policy `displayController:updatePresentationWithSceneManager:displayConfiguration:completion:`)   [DONE, UNSURE only on which scenes qualify]

### 3.1 What `boundPointerUIScenes` is

16.2 `SBSceneManager` gets a third tracked collection `_boundPointerUIScenes` (`BSCopyingCacheSet`, ivar 0x68; 16.0 has no such ivar, `_boundScenes` 0x58 / `_allScenes` 0x60).
`-[SBSceneManager(ChamoisDevelopmentShimming) boundPointerUIScenes]` (0x1c73ee05c) returns it as an `NSSet`; `addPointerUISceneToPresentationBinder:` (0x1c73ee074) and
`removePointerUISceneFromPresentationBinder:` (0x1c73ee07c) are tail calls into the new generic helpers `_addSceneToPresentationBinder:trackedCollection:` /
`_removeSceneFromPresentationBinder:trackedCollection:` with that collection (the existing `addSceneToPresentationBinder:` becomes the same call with the other collection; helper body: assert valid
("cannot respond to non-destruction scene events after invalidation", SBSceneManager.m:0x569), `addObject:` to `_boundScenes`, `[_presentationBinder addScene:]`, `addObject:` to the tracked collection, workspace
identifier set, `_allScenes`).
The only producer is `-[SBMousePointerManager pointerClientController:sceneDidActivate:]` (16.0 0x1c607eed4 / 16.2 0x1c75023d8) and `...sceneWillDeactivate:` (0x1c607ef74 / 0x1c7502478): both look up
`[[SBSceneManagerCoordinator sharedInstance] sceneManagerForDisplayIdentity:[scene.settings sb_displayIdentityForSceneManagers]]` and call `addSceneToPresentationBinder:` (16.0) /
`addPointerUISceneToPresentationBinder:` (16.2) / the remove variants. So `boundPointerUIScenes` = "the PointerUI client scenes (one per display) that are currently active".

### 3.2 The policy method

16.0 (0x1c6339470, 56 insns; the "did the configuration change" gate is a separate policy method called by the controller before, `displayController:shouldUpdatePresentationWithSceneManager:displayConfiguration:` =
`![_lastPresentationUpdateDisplayConfiguration isEqual:config]` + store): `scenes = [sceneManager allScenes]`; empty -> `completion()`; else for each scene apply the block (below) with a
`__block` counter, `completion()` when the counter reaches the count (block 0x1c63396b4).
16.2 (0x1c77dcbe0, 126 insns):
```objc
- (void)displayController:(id)c updatePresentationWithSceneManager:(SBSceneManager *)sm displayConfiguration:(FBSDisplayConfiguration *)cfg completion:(void (^)(void))completion {
    BOOL changed = ![_lastPresentationUpdateDisplayConfiguration isEqual:cfg];            // ivar 0x78 (gate moved here)
    if (changed) _lastPresentationUpdateDisplayConfiguration = cfg;
    NSMutableSet *scenes = [NSMutableSet set];
    NSSet *bound = [sm boundPointerUIScenes];  if (bound) [scenes unionSet:bound];
    if (_currentScene /* 0x68 */) [scenes addObject:_currentScene];
    __block NSUInteger done = 0;
    if (changed && scenes.count) {
        log "running update as display changed and we have scenes to update";
        [scenes enumerateObjectsUsingBlock:^(FBScene *scene, BOOL *stop) {                // block 0x1c77dce6c
            FBSMutableSceneSettings *s = [[scene settings] mutableCopy];
            [s setDisplayConfiguration:cfg];  [s setFrame:[cfg bounds]];
            [scene updateSettings:s withTransitionContext:nil completion:^(BOOL ok){ if (++done == scenes.count) completion(); }];   // identical to 16.0
        }];
    } else completion();
}
```
Effective change: only the extended-display scene and the PointerUI scenes are re-settinged on a display-configuration change instead of every scene the scene manager owns (the extended display's app scenes get their frame
from layout, not from this call). Plus: an unchanged configuration completes immediately (16.0 never reached this call in that case).

### 3.3 Port

Group `G4B_PreSubset`: (1) `%new` on `SBSceneManager`: `boundPointerUIScenes`, `addPointerUISceneToPresentationBinder:`, `removePointerUISceneFromPresentationBinder:` backed by an associated `NSHashTable` (weak); (2) hooks on
`-[SBMousePointerManager pointerClientController:sceneDidActivate:]` / `sceneWillDeactivate:` that run `%orig` and then register/unregister the scene with the same scene-manager lookup the original uses;
(3) hook `-[SBSystemShellExtendedDisplayControllerPolicy displayController:updatePresentationWithSceneManager:displayConfiguration:completion:]` as a complete replacement of the 16.0 body: because the 16.0 controller already
ran the `shouldUpdate...` gate (and stored the configuration), `changed` is always YES here; if neither a bound pointer scene nor `_currentScene` exists the method completes immediately (16.2 does the same). Safety net: if the
subset is empty although `[sm allScenes]` is not, the first update still falls back to `%orig` once (so a missing producer cannot freeze the display at the old size); `Backport162.off.presubset` restores the 16.0 behaviour.
The non-interactive policy (16.2 0x1c78e92ec) was not changed in this respect and is not touched.
Confidence: DONE for the code path; UNSURE whether 16.2's PointerUI scenes need the config frame at all on 16.0 (check: log lines `presubset: updating N scenes`).

---------------------------------------------------------------------------------------------------

## 4. 100 ms deferred activation of external-display assertions   [DONE; behaviour benefit UNSURE]

### 4.1 16.2 mechanism (all decoded)

* `-[SBDisplayManager _connectToIdentity:withConfiguration:forDisplayManagerInit:]` (0x1c7990164): after creating the layout publisher and CADisplay queue of a ROOT identity: `if ([identity isExternal]) dispatch_after(100 ms, main, ^{ if ([record isValid]) [_assertionCoordinator activateAssertionsForDisplay:identity]; })` else `[_assertionCoordinator activateAssertionsForDisplay:identity]` immediately.
* `-[SBDisplayAssertionCoordinator activateAssertionsForDisplay:]` (0x1c77de510): `NSAssert([root isRootIdentity])`; log; `[_assertionStackMap[root] activateAssertionsForDisplay:root]`.
* `-[_SBDisplayAssertionStack activateAssertionsForDisplay:]` (0x1c74d1898): NSAsserts `[_rootIdentity isEqual:root]`, `!_invalidated`, `!_activated`; log "activating assertions for display"; `_activated = YES` (new ivar @0x19);
  `[self _evalAndApplyOldPreferences:[NSMapTable new] newPreferences:_assertionControlPreferences]` (everything collected so far is applied as one change).
* Every mutator of the stack (`acquireAssertionForDisplay:...` 0x1c74d1cc4 and 0x1c74d1ffc, `invalidateAssertionForDerivedDisplayDisconnect:` 0x1c74d2278, `_assertion:updatedPreferences:` 0x1c74d24e0, `_assertionDidInvalidate:` 0x1c74d2690)
  became `old = [_assertionControlPreferences copy]; mutate; if (_activated) [self _evalAndApplyOldPreferences:old newPreferences:_assertionControlPreferences];`
  and `_evalAndApply...` itself NSAsserts `_activated`.
* The coordinator's delegate method changed `assertionCoordinator:activeAssertionPreferencesHaveChanged:` (global dictionary) -> `assertionStack:updatedAssertionPreferences:oldPreferences:` (per display) - already covered by item 1.3.

Net effect: for an external display, nothing (no `didGainControl`, no delegate callback, no arrangement / power-log / idle-sleep / clone-mode update) happens for the first 100 ms after connect, and then all the assertions acquired in that window take effect at once.
It also removes the `_connectionCompleted` race noted in `group4-connect-service-lock.md` 3.4.

### 4.2 Port (group `G4B_DeferAct`)

16.0 stack methods are ObjC methods, so no runtime subclass is needed: the `_activated` ivar is an associated flag that is only ever set to "pending" for external displays (everything else behaves as "activated", so nothing existing can stall):
1. `%new -[_SBDisplayAssertionStack activateAssertionsForDisplay:]` (clears the pending flag, then calls the stock `_evalAndApplyOldPreferences:` with an empty `NSMapTable` and `_assertionControlPreferences`) and `%new -[SBDisplayAssertionCoordinator activateAssertionsForDisplay:]`.
2. Hook `-[SBDisplayAssertionCoordinator _createDisplayAssertionStackForRootDisplay:]` (16.0 0x1c633b2a0): after `%orig`, for `[identity isExternal]` mark the new stack pending and `dispatch_after(100 ms)`: if the stack is still the one in `_assertionStackMap[identity]` and not `_invalidated`, call `activateAssertionsForDisplay:` (the equivalent of `[record isValid]`).
3. Hook `-[_SBDisplayAssertionStack _evalAndApplyOldPreferences:newPreferences:]`: if the stack is pending -> return (this is the 16.2 `if (_activated)` guard applied at the single sink instead of at each of the 5 call sites, which is equivalent because `old` is only used by the sink).
Edge: `invalidateForDisplayDisconnect` of a pending stack never activates (the timer re-checks `_invalidated`); if SpringBoard sleeps the main queue for >100 ms the activation simply runs late.
Feature switch `deferact` (ON by default). If it ever shows a connect regression (display stays black), `Backport162.off.deferact` restores 16.0 behaviour; UNSURE only because no symptom was identified for the original.

---------------------------------------------------------------------------------------------------

## 5. Per-window-scene `SBLockedPointerManager`, `_UIPointerUnlockAction`, suppress-preferred-status, pointer-assertion display scoping   [UNSURE: 5.6]

### 5.1 Complete 16.2 picture (everything below is decoded; addresses 16.2)

* **Ownership.** One manager per `SBWindowScene`: `SBAbstractWindowSceneDelegate _configureForConnectingWindowScene:` creates `[[SBLockedPointerManager alloc] initWithWindowScene:ws]` and stores it in the `SBWindowSceneContext`
  (`-[SBWindowScene lockedPointerManager]` 0x1c77f804c). The main-display manager is no longer a `SpringBoard` ivar. `SBAbstractWindowSceneDelegate sceneDidDisconnect:` calls `[[ws lockedPointerManager] invalidate]`.
* **Clients.** `SBMainDisplaySceneManager` (0x1c7882574) AND the new `SBSystemShellExternalDisplaySceneManager _appSceneClientSettingsDiffInspector` (0x1c7858e94, only on iPad idiom: `UIApplicationSceneClientSettingsDiffInspector observePreferredPointerLockStateWithBlock:`; block 0x1c7859008)
  route a scene's `preferredPointerLockStatus` change to `[[[SBApp windowSceneManager] windowSceneForDisplayIdentity:[sceneHandle displayIdentity]] lockedPointerManager] clientWithSceneIdentifier:sid prefersPointerLockStatus:status]`.
  16.0 has no diff inspector on the external scene manager at all (its `_scene:didUpdateClientSettingsWithDiff:...` 0x1c63ae5ac is a bare `[super ...]`), so apps on an external display could never lock the pointer.
* **New ivars** (0x30 suppress set, `_windowScene` weak @0x48, `_queue_isInvalidated` @0x50) and conformance `BSInvalidatable`, `SBSceneManagerObserver`.
* **`initWithWindowScene:`** (0x1c76b8c68) = 16.0 `initWithSceneManager:` (`PSPointerClientController`, serial queue `com.apple.SpringBoardFramework.SBLockedPointerManager.stateSerialQueue`, prefs dict) + `NSMutableSet` + observers on `[ws sceneManager]` and `[ws layoutStateTransitionCoordinator]` + weak scene.
  (16.0 `initWithSceneManager:` 0x1c62276b0 already takes the scene manager as a parameter and observes `[sm _layoutStateTransitionCoordinator]`, so the 16.0 initializer can build a manager for ANY display.)
* **`invalidate`** (0x1c76b9298): remove observers from the scene manager and coordinator; `dispatch_sync(queue)`: invalidate + nil both assertions, `_queue_isInvalidated = YES`.
* **Invalid guards**: every entry point snapshots `_queue_isInvalidated` with `dispatch_sync(queue)` and, if set, logs and returns (`prefersPointerLockStatus`, `suppressPreferredLockStatus`, both layout-transition callbacks, both foreground-handle callbacks, `sceneHandle:didUpdateSettingsWithDiff:`, `_queue_updateLockForLayoutState:` ("Ignoring request to update pointer lock state ... because I'm invalidated")).
* **`_updateLockForLayoutState:`** -> `_notInvalidated_updateLockForLayoutState:` (0x1c76ba034): `if (!state) state = [[ws layoutStateProvider] layoutState]` (16.0: main display `currentLayoutState`), `dispatch_async(queue, ^{ [self _queue_updateLockForLayoutState:state]; })`.
* **`_queue_updateLockForLayoutState:`** (0x1c76ba124) exactly: `invalidated -> log,return; h = [self _possibleSceneHandleForLockingPointerFromLayoutState:state]; sid = h.sceneIdentifier; cur = _queue_sceneIdentifierThatHasLockedPointer; shouldLock = [self _queue_prefersLockForSceneIdentifier:sid] && ![_suppressSet containsObject:sid] && [self _shouldAllowPointerLockedForScene:h]; if (shouldLock && !cur) [self _queue_lockPointerForSceneIdentifier:sid]; else if (!shouldLock && cur) [self _queue_unlockPointer];`
* **`clientWithSceneIdentifier:prefersPointerLockStatus:`** (0x1c76b8d74): `dispatch_sync(queue){ inv = _queue_isInvalidated; if (!inv) _queue_preferred[sid] = @(status); }` then `[self _notInvalidated_updateLockForLayoutState:nil]` (or log if invalidated).
* **`clientWithSceneIdentifier:suppressPreferredLockStatus:`** (0x1c76b8fc4, NEW): `dispatch_sync(queue){ inv = ...; if (!inv) { has = [set contains:sid]; if (suppress && !has) add; else if (!suppress && has) remove; } }`; if not invalidated:
  `vc = SBSafeCast([[ws switcherController] contentViewController], SBFluidSwitcherViewController); [vc clientWithSceneIdentifier:sid suppressPreferredPointerLockStatusUpdated:suppress]; [self _notInvalidated_updateLockForLayoutState:nil]`.
* **`sceneHandle:didDestroyScene:`** (0x1c76b9b80, NEW): if not invalidated: `prefs removeObjectForKey:[scene identifier]; suppressSet removeObject:[scene identifier]; [self _notInvalidated_updateLockForLayoutState:nil]`.
* **`_shouldAllowPointerLockedForScene:`** (0x1c76b9e5c): `ccOK = ([[[SBControlCenterController sharedInstance] _controlCenterWindow].windowScene isEqual:_windowScene]) ? ![CC isPresented] : YES; coverOK = ![[SBCoverSheetPresentationManager sharedInstance] isPresented]; sceneOK = scene exists && effectivelyForeground && (!settings.isUISubclass || (deactivationReasons & ~0x100) == 0)  [16.0 same, except ccOK was !CC.isPresented]; return ccOK && coverOK && sceneOK` (log "shouldAllow:%d isAllowedBasedOnControlCenterState:%d ...").
* **`_queue_lockPointerForSceneIdentifier:`** (0x1c76ba3dc): `assert queue; log "Locking pointer for scene %@"; if (cur) [self _setPointerLockStatus:0 forSceneWithIdentifier:cur]; reason = "Scene %@ requested locked pointer"; display = [[[ws _fbsDisplayConfiguration] hardwareIdentifier]; _backboardAssertion = [[BKSMousePointerService sharedInstance] pointerSuppressionAssertionOnDisplay:display forReason:reason withOptionsMask:2]; _hiddenAssertion = [_pointerClientController persistentlyHidePointerAssertionForReason:4]; cur = sid; [self _setPointerLockStatus:1 forSceneWithIdentifier:sid];`
  (16.0 0x1c6228214 is identical with `display:nil` and 8-byte lower ivar offsets.) `_queue_unlockPointer` (0x1c76ba590 / 0x1c6228318) only gained log lines.
* **`_UIPointerUnlockAction`** (UIKit class, `UIActionType` 0x32 in the `cmp x0,#0x30` ladder of `-[SBSceneManager _handleAction:forScene:]`, 16.2 0x1c72e3f38): `[[[self _windowScene] lockedPointerManager] clientWithSceneIdentifier:[scene identifier] suppressPreferredLockStatus:YES]; return YES;`.
  Producer: UIKit `-[UIWindowScene _unlockPointerLockState:]` (the user presses the system "unlock pointer" gesture/Esc; class and method exist in UIKitCore 16.0 and 16.2).
* **`-[SBFluidSwitcherViewController didSelectContainer:modifierFlags:]`** (0x1c7452050): first thing: `uid = [[[container appLayout] itemForLayoutRole:1] uniqueIdentifier]; if (uid) [[[self _sbWindowScene] lockedPointerManager] clientWithSceneIdentifier:uid suppressPreferredLockStatus:NO];` then the 16.0 body.
* **`-[SBFluidSwitcherViewController clientWithSceneIdentifier:suppressPreferredPointerLockStatusUpdated:]`** (0x1c7451f0c, NEW): `overlay = [self liveOverlayForSceneIdentifier:sid]; for (appLayout in [_liveContentOverlays allKeysForObject:overlay]) [[self _itemContainerForAppLayoutIfExists:appLayout] setPreferredPointerLockStatusSuppressed:suppress];`
* **`SBFluidSwitcherItemContainer`** (NEW ivar `_preferredPointerLockStatusSuppressed` @0x2d5): setter (0x1c75e161c) `if changed { store; [self setContentViewBlocksTouches:[self contentViewBlocksTouches]]; [self setSelectable:_selectable]; }`;
  `setContentViewBlocksTouches:` (0x1c75e15c8) now stores `pageView.blocksTouches = (suppressed != 0) | value`; `setSelectable:` (0x1c75e15f4) stores `_selectable = (suppressed != 0) | value`.
  Meaning: after the app releases the lock, its window in the switcher shows as a normal selectable window whose page view eats touches, so the user must click it again; the click (`didSelectContainer`) lifts the suppression and the lock is re-acquired.

### 5.2 Pointer-assertion display scoping: the real 16.2 effect (evidence)

* The 16.0 BackBoardServices `pointerSuppressionAssertionOnDisplay:forReason:withOptionsMask:` already takes a display UUID; `nil`/empty maps to the key `"<main>"` (`BKSMousePointerService` 0x18e2047a8 `_locked_infoForDisplayUUID:createIfNeeded:`).
* The 16.0 backboardd resolves every UUID the same way for all its display services (helper 0x10001f1f4): `nil` or `"<main>"` -> main display; anything else -> `[CAWindowServer displayWithUniqueId:]` (falling back to the "Wireless" display); unknown -> log "unknown displayUUID". So an explicit hardware identifier of the external display
  is a first-class, already supported argument on 16.0, and the explicit hardware identifier of the main display resolves to the main display as well (but creates a separate per-display info entry from `"<main>"`; effect identical, the assertion id is `mouse-pointer-suppression:<uuid>`).
* Therefore the real 16.2 effect of the argument change is NOT for the iPad (nil and its own UUID mean the same display) but for the external display: its manager's lock must act on THAT display; with `nil` it would lock/hide the pointer on the iPad. That also explains why the earlier hook was a no-op on 16.0: with one global
  manager that only serves the iPad scene manager, the argument could only ever be the main display. With per-scene managers the argument matters.
* Decision: embedded scene -> keep `nil` (bit-identical to 16.0, no new per-display info entry); external scenes -> `[[ws _fbsDisplayConfiguration] hardwareIdentifier]` captured on the main thread when the manager is created (the review of 0.5.0 found that reading UIKit objects on the manager's serial queue is a race).

### 5.3 Port design (group `G4B_LockedPtr`, feature `lockedptr2`; the old 0.5.0 `lockedptr` BKSMousePointerService hook is to be removed)

* No new class is needed: 16.0 `SBLockedPointerManager` is parametric; instances are created with `initWithSceneManager:[ws sceneManager]` (wrapped as `%new initWithWindowScene:`) and their per-scene state (weak scene box, hardware id, suppress set, invalidated flag) lives in associated objects.
* `%new -[SBWindowScene lockedPointerManager]`: embedded scene -> the existing global manager (`SpringBoard._lockedPointerManager`, found by ivar name; NOT cached while still nil), external scene -> lazily created per-scene instance. Main thread only.
* Hooks on `SBLockedPointerManager`: invalid guards on the 9 entry points; full replacements of `_queue_updateLockForLayoutState:`, `_queue_lockPointerForSceneIdentifier:`, `_shouldAllowPointerLockedForScene:` (only when the instance has a scene box, i.e. always after first use through the scene getter; otherwise `%orig`); `_updateLockForLayoutState:` nil-state default from the instance's own scene manager.
  `%new`: `invalidate`, `clientWithSceneIdentifier:suppressPreferredLockStatus:`, `sceneHandle:didDestroyScene:`, `_notInvalidated_updateLockForLayoutState:`.
* `SBSystemShellExternalDisplaySceneManager`: hook `_scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:` (after `%orig`): if the scene's client `preferredPointerLockStatus` differs from the old client settings' value, forward to the display's manager (same effect as the 16.2 inspector block; the inspector class itself is avoided to stay independent of its API).
* `SBSceneManager _handleAction:forScene:` hook: `_UIPointerUnlockAction` -> suppress YES, return YES.
* `SBAbstractWindowSceneDelegate sceneDidDisconnect:` hook: `[[ws lockedPointerManager] invalidate]` for non-embedded scenes (the global manager is never invalidated, as in 16.0).
* `SBFluidSwitcherViewController didSelectContainer:modifierFlags:` hook (unsuppress), `%new clientWithSceneIdentifier:suppressPreferredPointerLockStatusUpdated:`; `SBFluidSwitcherItemContainer`: `%new preferredPointerLockStatusSuppressed` + hooks on `setContentViewBlocksTouches:` and `setSelectable:` implementing the OR (the stock 16.0 `setSelectable:` is a plain store).

### 5.6 Tag UNSURE
(a) `-[SBSystemShellExternalDisplaySceneManager _scene:didUpdateClientSettingsWithDiff:...]` exists in 16.0 (0x1c63ae5ac) but its `[super ...]` target (`SBSceneManager`, 0x1c5f74a9c) was not decoded; check on device that the hook fires (`lockedptr2: client prefers` log) when a game on the monitor requests a lock.
(b) `preferredPointerLockStatus` is read from `[scene clientSettings]` by selector name (the 16.0 main inspector block reads the same selector, `0x1c63d696c`); if the settings object does not answer, the external forwarding is silently skipped.
(c) The iPad (embedded) path is unchanged except for the new "suppress" semantics and the CC rule; the first on-device check is a game that locks the pointer on the iPad, then release it with the unlock gesture and click the window again.
(d) `SBFluidSwitcherItemContainer` hooks only matter in Stage Manager layouts and are in the same group; if `setSelectable:` is inlined elsewhere the flag may not propagate (cosmetic).

---------------------------------------------------------------------------------------------------
