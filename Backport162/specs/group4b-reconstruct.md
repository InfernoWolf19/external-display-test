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
