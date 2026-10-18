# External display unplug: what happens to the windows that were on it (16.2 vs 16.0 vs our port), 0.7.4

Addresses: 16.2 (20C65) / 16.0 (20A8372) SpringBoard cache vmaddrs. Static analysis only (no 16.2 device observation).
Confidence tags: HIGH = read in the disassembly, MED = inferred from it, UNSURE = needs a device/log check.

## 1. Verdict

Answer to the question: **(a), with a no-op workspace transition on top.** In 16.2 the apps of the unplugged display are moved into the
embedded scene manager and shown by the iPad's switcher (strip); NOTHING in the disconnect path activates one of them, puts one on the
iPad's stage, or changes the iPad's environment mode. The only workspace request issued is entity-less (no activating entity, no
requested frontmost entity); it copies the iPad's own window-picker role and unlocked environment mode back into itself. (HIGH for "no
code activates an app"; MED for the end state "iPad stays where it was, app only in the strip" because it was not seen on a 16.2 device.)
So our device log (home screen stays, ids update strip `[..Filza] -> [..Filza, Reynard]`, transition `modes 1->1 from=nil to=nil`) is
what the 16.2 code path produces too. "The window should appear on the iPad display" is NOT a 16.2 behaviour; it would be a deliberate
deviation (see 5.4).

Not (b): no `activatingEntity`/`_setRequestedFrontmostEntity:`/`requestedLayoutState` in the request, no `_focusNewlyAddedApplicationIfNeeded...`
trigger (that one needs an added entity in a layout transition), `kfc windowSceneDidDisconnect:` only moves keyboard focus.
Not (c): `SBMainWorkspace`, `SBMainDisplayLayoutStateManager`, `SBWindowSceneManager _sceneDidDisconnect:` (0x1c74bf88c, only removeObject:),
`SBSceneManagerCoordinator displayMonitor:willDisconnectIdentity:` (0x1c77ae2dc, only connected=NO / hide / drop reference),
`SBDisplayManager displayMonitor:willDisconnectIdentity:` (0x1c7990b4c) have no app-migration code (call sequences diffed against 16.0:
identical or power-log/logging only).

## 2. The 16.2 chain (in call order) and what each step does to the apps

1. `SBExternalDisplayWindowSceneDelegate -sceneDidDisconnect:` 16.2 0x1c746826c (16.0 0x1c5fed4f8): kfc suppress, `ws.invalidating = YES`,
   then `[[SBMainSwitcherControllerCoordinator sharedInstance] windowSceneDidDisconnect:ws]` (16.0 only if the screen still had a display
   configuration), then status bar assertion / system gesture manager / alert items / interaction event sources / multi display coordinator /
   cover sheet, `[super sceneDidDisconnect:]`, invalidate. Already ported (Group4Focus.x `sceneDidDisconnect:`, order verified).
2. `SBMainSwitcherControllerCoordinator -windowSceneDidDisconnect:` 16.2 0x1c76c85e0 (16.0 0x1c62359ec; 106 -> 275 insns). 16.2 PREPENDS
   the migration, then runs the 16.0 tail (+ one extra `removeObjectForKey:` of the 16.2-only `_currentWindowingModeCompatibleAppLayoutsByWindowScene`).
   Migration, exact:
   ```
   ws = SBSafeCast(SBWindowScene, scene); if (!ws) -> skip everything (0x1c76c863c)
   extSC = [self switcherControllerForWindowScene:ws]
   if ([ws isExternalDisplayWindowScene] && [[ws _fbsDisplayIdentity] sb_displayWindowingMode] == 1) {   // 0x1c76c865c..0x1c76c8684
     embSM = SBSafeCast(SBMainDisplaySceneManager, [[[SBApp windowSceneManager] embeddedDisplayWindowScene] sceneManager])   // not nil-checked
     moved = NO
     for layout in [self appLayoutsForSwitcherController:extSC]            // external switcher's list, BEFORE the tail removes it
       for item in [layout allItems] {
         owner  = [self _switcherControllerForDisplayItem:item]            // 16.2-only, 0x1c76e3130
         handle = [owner _deviceApplicationSceneHandleForDisplayItem:item] // 16.2 SBSwitcherController method 0x1c76065ec
         scene  = [handle sceneIfExists]
         if (scene) { [embSM takeScene:scene fromSceneManager:[[extSC windowScene] sceneManager]]; moved = YES }
       }
     if (moved) [[SBMainWorkspace mainWorkspace] requestTransitionWithOptions:0
                      builder:  <global block 0x1e18ede40, invoke 0x1c76c8b20>   // ^(req){ [req setSource:0x11]; }  0x11 = "ExternalDisplay"
                      validator:<stack block, invoke 0x1c76c8b2c, captures embSM> // ^BOOL(req){ [req modifyApplicationContext:^(ctx){ (0x1c76c8bbc)
                           ls = [embSM currentLayoutState];
                           if (SBLayoutRoleIsValid(ls.windowPickerRole)) ctx.requestedWindowPickerRole = ls.windowPickerRole;
                           if (ls.unlockedEnvironmentMode == 2) ctx.requestedUnlockedEnvironmentMode = 2; }]; return YES; }
   }
   16.0 tail (also in 16.2): invalidate+drop per-scene dicts, unparent switcher VC + hide its window, removeObserver x2, remove maps,
   [appInteractionEventSource removeObserver:], [self _notifySwitcherControllersAppLayoutsDidChange]
   ```
   Source 0x11 = "ExternalDisplay" (description table 16.2 0x1d7b401a0 idx 0x11, fn 0x1c78ed2b0; the same string is idx 0x11 of 16.0's table
   0x1d7baab10 / fn 0x1c643b7cc, so the enum value exists in 16.0). It is functionally inert: the only consumers found
   (`_SBMainWorkspaceTransitionSourceIsUserEventDriven` 0x1c78ed340, `..MapInternalTransitionSourceToExternalTransitionSource` 0x1c78ed2d4,
   callers 0x1c7293c3c / 0x1c75c6df8 / 0x1c77bd400) return the same for 0x11 as for 0 (unspecified); no `cmp #0x11` on a request source exists.
3. What makes the strip show the app is NOT the migration but the model filter: `appLayoutsForSwitcherController:` (16.2 0x1c76e2354, 16.0
   0x1c624d488, same algorithm in both, ported in G1D.x:141): for the main display scene the accepted `preferredDisplayOrdinal` mask is
   "all ordinals except those of the CONNECTED non-main window scenes"; when the external scene leaves `_switcherControllersByWindowScene`
   (tail of step 2) its layouts fall to the main display. The layout keeps `preferredDisplayOrdinal == 1`. (HIGH; matches the log.)
4. `-[SBSceneManager takeScene:fromSceneManager:]` 16.2 0x1c73e9a3c (16.0 0x1c5f72cf4): 16.2 = `[old _doObserverCalloutWithBlock:^(obs){ obs
   sceneManager:old didTransferManagementOfScene:scene toSceneManager:self }]` (only if the observer responds; the ONLY implementer is
   `SBInCallPresentationManager` 0x1c76696ac, 16.2-only), `existingSceneHandleForScene:`, the 16.0 body (`_sceneWillMoveToSceneManager:`,
   `safeUpdateScene:withDisplayConfiguration:`, `_addScene:`), `[oldHandle _noteReplacedWithSceneHandle:newHandle]` (-> observers'
   `sceneHandle:replacedWithSceneHandle:`, only `SBInCallPresentationSession` 0x1c757a10c implements it).
5. The transition itself (`SBWorkspace requestTransitionWithOptions:builder:validator:` 16.2 0x1c729193c; `SBMainWorkspace` thunk 0x1c7291904 /
   16.0 0x1c5e1fa50 -> super): `req = [self createRequestWithOptions:0]; builder(req); [self _executeTransitionRequest:req options:0 validator:v]`
   (16.2 0x1c7291e98, 16.0 0x1c5e1ffe4). The VALIDATOR runs first inside the queued event block (16.2 0x1c7373d48 blraa at 0x1c7373d98;
   16.0 0x1c5effa74 blraa at 0x1c5effac4), then `_determineSourceForTransitionRequest:` (0x1c72925b0, skipped when source != 0), then
   `policyAggregator allowsTransitionRequest:`. Default request = main display (`SBMainDisplayLayoutStateManager
   _layoutStateForApplicationTransitionContext:` 16.2 0x1c72952ec / 16.0 0x1c5e23430, previous entities carried over) -> from home to home.
   The same function in 16.2 only gained isDisplayExternal / previous+empty placeholder entities (unrelated).

## 3. 16.0 vs 16.2

| piece | 16.0 | 16.2 | our port (G4B.x group G4B_Migrate, line ~1515) |
|---|---|---|---|
| migrate prelude in `windowSceneDidDisconnect:` | none: scenes stay with the dying external manager | loop + `takeScene` + transition | present, same loop |
| scene handle lookup | coordinator `_deviceApplicationSceneHandleForDisplayItem:` 0x1c623fa90 asks `[[wsm activeDisplayWindowScene] sceneManager]` (at unplug our `activeDisplayWindowScene` already answers the EMBEDDED scene, log "falling back to the embedded scene") | method moved to SBSwitcherController (0x1c76065ec): `[[owner windowScene] sceneManager] existingSceneHandleForSceneIdentity:` of the app's scene id, requires `isDeviceApplicationSceneHandle`; `owner` = coordinator `_switcherControllerForDisplayItem:` 0x1c76e3130 (first controller whose scene manager holds a handle for `[FBSSceneIdentity identityForIdentifier:item.uniqueIdentifier]`, block 0x1c76e31e0) | calls the 16.0 coordinator method (embedded manager lookup). MISMATCH, see 5.1 |
| request builder / validator | n/a | builder = `setSource:0x11`, validator = context copy + YES | builder = context copy, validator nil, no source. MISMATCH, see 5.2 |
| takeScene observer callout | none | `didTransferManagementOfScene:toSceneManager:` | missing (in-call only), 5.3 |
| `_noteReplacedWithSceneHandle:` | none | yes | ported (hook of takeScene) |
| compat map cleanup | n/a | `removeObjectForKey:` at the tail | missing (G1D keeps its own map, never removes the scene), 5.3 |
| `SBWindowSceneContext -sceneManager` | `[SBSceneManagerCoordinator sceneManagerForDisplayIdentity:]` of the scene's display (0x1c6500ad4) | reads it from the FBSScene's transientLocalSettings (0x1c79bdacc) | unchanged; UNSURE whether `[scene sceneManager]` is still right this late in the 16.0 teardown (our log shows n=1, so it was) |

## 4. Why our observed end state equals 16.2 (HIGH unless noted)

- Entity-less request (no `setRequestedFrontmostEntity`, no `activatingEntity`; `_layoutStateForApplicationTransitionContext:` has no
  entity to place) => iPad layout state unchanged: log `GLITCH main transition: from mode 1 to mode 1 ... from=nil to=nil`.
- Picker role / unlocked-mode copy only matters when the iPad is already in an app (mode 2 stays 2, Add-Another-Window picker kept).
- `kfc windowSceneDidDisconnect:` 16.2 0x1c77c3b14 only removes keyboard focus from the dead scene and re-evaluates.

## 5. What is missing in our port and the faithful port

All edits would be in G4B.x group G4B_Migrate (the only hook on `SBMainSwitcherControllerCoordinator -windowSceneDidDisconnect:`; it is
also reached from Group4Focus.x:667 `[coord windowSceneDidDisconnect:ws]`, which is the 16.2 call site, do not duplicate it).

5.1 Handle lookup (do it exactly like 16.2). Replace the call to the 16.0 coordinator method by C helpers on the 16.0 binary:
```
static id G4B_OwnerSwitcher(id coord, id item) {            // 16.2 0x1c76e3130 / block 0x1c76e31e0
  NSMapTable *m = ivar(coord, "_switcherControllersByWindowScene");     // 16.0 has it
  id ident = [FBSSceneIdentity identityForIdentifier:[item uniqueIdentifier]];
  for (id ws in [[m keyEnumerator] allObjects]) { id sc = [m objectForKey:ws];
     if ([[[sc windowScene] sceneManager] existingSceneHandleForSceneIdentity:ident]) return sc; }
  return nil; }
static id G4B_SceneHandle(id owner, id item) {              // 16.2 SBSwitcherController 0x1c76065ec
  id mgr = [[owner windowScene] sceneManager];
  id app = [[SBApplicationController sharedInstance] applicationForDisplayItem:item];
  id ident = app ? [mgr sceneIdentityForApplication:app uniqueIdentifier:[item uniqueIdentifier]] : nil;
  id h = ident ? [mgr existingSceneHandleForSceneIdentity:ident] : nil;
  return [h isDeviceApplicationSceneHandle] ? h : nil; }
```
`scene = [G4B_SceneHandle(G4B_OwnerSwitcher(self,item), item) sceneIfExists]`; keep `from = [[extSC windowScene] sceneManager]` (16.2 uses the
external switcher's manager for every item, not the owner's). Do NOT add these as `%new` on SBSwitcherController/coordinator unless the
names are made BP-unique (16.0 coordinator already has a different `_deviceApplicationSceneHandleForDisplayItem:`; G2B.m:880 sends the same
selector to the calculator class, no collision). Do not nil-check/skip on `embSM` class: 16.2 does not (a nil embSM would still set `moved`);
keep our guard only as a logged last-line crash guard.
UNSURE: why the 16.0 coordinator lookup (embedded manager) found the handle in our log; if the embedded manager already knew the Reynard
handle the takeScene may have been a partial no-op. Log per item: owner SM pointer, embSM, extSM, `[extSM existingSceneHandleForScene:sc]`.

5.2 Request, exact slots. `requestTransitionWithOptions:0 builder:^(req){ [req setSource:0x11]; } validator:^BOOL(req){ [req
modifyApplicationContext:^(ctx){...}]; return YES; }` (our context block is already identical to 0x1c76c8bbc; `SBLayoutRoleIsValid` is
`dlsym`-resolved in our code, 16.2 calls it unconditionally). Verified that on 16.0 the validator also runs first in the event block
(0x1c5effa74), so the swap is behaviour-compatible; the difference to today is only that `[embSM currentLayoutState]` is read when the
event executes (queued behind a running transaction) instead of at request time, and `source` becomes ExternalDisplay instead of 0.
No existing hook collides: the 3-arg variant is only used here (G3/G3C/G1D use the `displayConfiguration:` variants); the only hook on the
path is G1D.x:2130 `SBMainWorkspace createRequestWithOptions:` which passes through unless the PiP-restore TLS entity is set; G1B/G1C
`setSource:` calls are on their own requests.

5.3 Smaller 16.2 pieces (all inert for app windows, listed for completeness): (i) in the takeScene hook (G4B.x:1582) before `%orig`:
`[other _doObserverCalloutWithBlock:^(id obs){ if ([obs respondsToSelector:@selector(sceneManager:didTransferManagementOfScene:toSceneManager:)]) [obs
sceneManager:other didTransferManagementOfScene:scene toSceneManager:self]; }]` (no implementer exists on 16.0; only matters if the in-call
presentation port adds one); (ii) remove the external window scene key from G1D's compat map (`G1D_CompatMap`, weak keys, so only a stale
entry) after `%orig`; (iii) other 16.2 disconnect handlers not ported: `SBPIPController _windowSceneDidDisconnect:` 16.0 0x1c64721cc / 16.2
0x1c7927a24 (per-context `_updateOffScreenHyperregionComposersForContext:` before `_moveContext:toWindowScene:`), `SBFluidSwitcherViewController
invalidate` 0x1c5fc335c / 0x1c743bc98 (observer/delegate teardown + invalidated flag),
`SBTransientOverlayPresentationManager windowSceneDidDisconnect:` 0x1c616ca94 / 0x1c75f45c0 (`...InWindowScene:` + `outerCompletionHandler`
API only, same effect), `SBDisplayAssertionCoordinator rootDisplayDidDisconnect:` 0x1c633af88 / 0x1c77de838 (logging + new
`updatedAssertionPreferences:oldPreferences:forDisplay:`).

5.4 If the user still wants the window ON the iPad stage after unplug (NOT 16.2; flag it as a deviation, own kill switch): add to the
validator context an activating entity for the migrated item (e.g. `[ctx setRequestedFrontmostEntity:entity]` /
`SBDeviceApplicationSceneEntity` for the item's handle in the embedded manager) plus `requestedUnlockedEnvironmentMode = 2`, which then goes
through the normal app-activation transition (our G1C AppToApp / ToHome modifiers). Not analysed further here.

## 6. Uncertainty / next evidence

- No 16.2 device log of an unplug exists; (a) rests on the disassembly. A 16.2-device test "unplug with window on the extended display,
  iPad at home screen" would settle the end state; expected: app only in the strip.
- Whether the migrated card is correctly rendered in the strip (snapshot lookup still keyed by the old display) is outside this path
  (`g1d: snapshot cache ... no scene handle provider` lines at 04:07:47 come from the DYING external switcher's image cache, 16.2 logs the same).
- Suggested BP_Log additions in G4B_Migrate: per-item owner/handle/scene pointers, `source` and request description after the request is
  built, and the iPad's `unlockedEnvironmentMode` / frontmost entity before and after.

## 7. 0.7.8: sections 5.1 / 5.2 ported (user: "the windows on the extended display don't move to the iPad upon disconnect")

Evidence from the eight logged unplugs that reached `windowSceneDidDisconnect:` with the old code: `migrate: moved 0 scenes` six times, `moved 1` twice (13493fb8, 76c96b37). The 16.0 coordinator lookup `_deviceApplicationSceneHandleForDisplayItem:` asks `[[windowSceneManager activeDisplayWindowScene] sceneManager]`, which already answers the embedded scene at unplug, so for an app that lives only in the external scene manager no handle was found and nothing was handed to the iPad's scene manager (the app then only existed in the dying external manager).
* Handle lookup now as in 16.2: identity `[FBSSceneIdentity identityForIdentifier:[item uniqueIdentifier]]`, owner = the switcher controller (of `_switcherControllersByWindowScene`) whose window scene's scene manager has a handle for it (16.2 `_switcherControllerForDisplayItem:` 0x1c76e3130), handle = that manager's `existingSceneHandleForSceneIdentity:` if `isDeviceApplicationSceneHandle` (16.2 SBSwitcherController 0x1c76065ec); `takeScene:fromSceneManager:` source = `[[extSwitcher windowScene] sceneManager]`.
* Request as in 16.2: builder `^(req){ [req setSource:0x11]; }`, validator = the context copy block returning YES.
* Debug-independent log line per item: `migrate: item ... identity ... owner switcher P handle P scene P (external manager P, embedded manager P)` then `migrate: moved N scenes`. Expected for a window on the extended display: owner = the external switcher, handle and scene non-nil, N >= 1.
* Not changed: the end state is the one described in section 1 (apps in the iPad's strip / switcher, nothing activated on the iPad stage, iPad stays where it was). If the user wants the window ON the stage after unplug, that is the deviation of 5.4 (own kill switch), to be done only on request after this build is tested.
* Unproven: that the identity string equals the scene identifier of the handle (16.2 does the same, unverified on a 16.0 device); that the external switcher still lists the layouts at this point (it did in the `moved 1` logs); the visible result on the iPad.

## 8. migrate_stage: windows of the extended display on the iPad's STAGE after unplug (DELIBERATE deviation from 16.2)

User demand (twice): after the unplug the windows that were on the extended display must be on the iPad, on its stage, not only in the strip while the iPad sits on the Home Screen. Section 1 stands: stock 16.2 does NOT do this. Code: G4B.x group G4B_Migrate (request) and G4B_MigrateStage (hook), helpers `G4B_MigrateStagePlan / ...Apply / ...Merge`. Kill switch `Backport162.off.migrate_stage` (restores section 7 exactly: the plan is never built, the hook is not installed). Nothing here was run on a device.

Design
* WHAT goes on the stage: the windows of the external switcher's current stage layout (`[[extSwitcher layoutState] appLayout]`, items with a layout role 1, 2, 5..9) whose scene was handed to the embedded manager. Read in the `windowSceneDidDisconnect:` hook BEFORE `%orig` (the external scene is still alive); the embedded handle of each is looked up right after `takeScene:` with `existingSceneHandleForSceneIdentity:` (device application handle). Windows that were only in the external strip are not touched (they are already in the iPad's switcher list). Front window = largest `lastInteractionTime` of the layout attributes, then the other windows in role order. At most `[[[SBAppSwitcherDomain rootSettings] chamoisSettings] maximumNumberOfAppsOnStage]` (the cap G1C.x uses for drops; 4 if unreadable); the surplus stays in the strip.
* HOW: same transition call as section 7 (source 0x11, `requestTransitionWithOptions:0 builder:validator:`, main display). The validator (runs first in the queued event, so the iPad's state is the one at execution time) reads `[embSM currentLayoutState]`: mode 1 (Home Screen) or 3 (stage) -> `setEntities:withPolicy:0 centerEntity:nil floatingEntity:nil` with `SBDeviceApplicationSceneEntity initWithApplicationSceneHandle:` objects (roles 1, 2, 5.. in front-first order, as the zoom request of G3C.x), `setRequestedLayoutAttributes:forEntity:` = the external window's own attributes (sizing policy, attributed size, centre: 16.2's attributed size scales with the container and clamps to the default size when the container got smaller, G2B.m `BP2B_SizeForAttributedSize`, so a monitor-sized window does not overflow the iPad; a zoomed window stays zoomed), `setActivatingEntity:` + `_setRequestedFrontmostEntity:` of the front window (16.0 0x1c61ccc80 reads the requested attributes first, then stamps lastInteractionTime), `requestedUnlockedEnvironmentMode = 3`. Mode 2 (iPad in the app switcher) keeps the entity-less request of section 7 (the switcher already shows the windows).
* Mode: with a role 1 app entity and no peek `_layoutStateForApplicationTransitionContext:` (16.0 0x1c5e23430) derives mode 3 by itself when the requested mode is 0 (0x1c5e24c94: not home, no valid peek -> 3); the explicit 3 additionally steers around the ambiguous-launch rule (`-[SBRecentAppLayouts _transitionContextRepresentsAmbiguousLaunch:forApplicationSceneEntity:` 0x1c64ef6c0: app supports multiwindow, > 1 recents of that bundle, source not in {3, 0xb, 0xc, 0x23, 0x2d, 0x33, 0x35}, no actions) which would otherwise pick the App Expose mode 2 (0x1c5e250c0..0x1c5e25178: with bundle id set the mode becomes 3 only if the requested mode is >= 3).
* MERGE with the iPad's own stage (mode 3): the previous layout's entities exist in the context only inside `_layoutStateForApplicationTransitionContext:` (the wrapper fills `previousEntities`), so G4B.x hooks that method (second hook next to G3C.x's, only for contexts carrying the migrate marker): every previous entity that is not home / previous / empty and not already requested goes into the first free role of {1, 2, 5..9} (G3C.x `G3C_EndPeekPick` rule), in previous role order, while the total stays <= the stage limit; the rest stay in the strip. Home Screen (mode 1): previous entities are only the home entity, nothing to merge. If the iPad was peeking (add-window peek) the hook leaves the merge to G3C.x.
* Fallbacks (each logged, behaviour = section 7): no layout state / stage layout of the external display, no handle after `takeScene:`, missing selector, exception (all wrapped in `@try`), iPad in mode 2.

Log lines of an unplug (with `Backport162.debug`; BP_Log):
`migrate: item ... handle ... scene ...` (unchanged), `migrate: moved N scenes ...`, `migrate_stage: iPad layout state before: mode M peek P`, `migrate_stage: on the iPad stage (front first): <uid>(was role R, time T) ...; stay in the strip: ... (stage limit L)`, then in the queued event `migrate_stage: request built: iPad mode before M -> 3, K entities, front <entity>`, `migrate_stage: iPad stage windows kept behind the migrated ones: <role:entity> ...; left in the strip ...: ...`, `migrate_stage: layout state <state>` (elements, mode 3, peek 1), then the usual `GLITCH main transition: from mode M to mode 3` lines (G1C ToHome/AppToApp transition). The old behaviour shows `from=nil to=nil`.

Unproven / risks
* That the main body of 16.0 accepts a request with entities for scenes of ANOTHER display's former manager (they are the embedded manager's handles now, like a card tap) and that the transaction activates / foregrounds them (scene settings from the external display configuration are updated by `takeScene:`).
* Source 0x11 with an entity request: the ambiguous-launch rule is steered around only by the explicit mode 3 (traced by hand, not run). If a multi-window app (two windows in recents) opens App Expose instead, switch the source for the stage request to 0x23 (SceneRequest, used by G1D for new windows).
* Duplicate layouts: the external layout (`preferredDisplayOrdinal` 1) stays in the iPad's recents next to the new main-display stage layout with the same items; how the strip shows that, and the coordinator's end-of-transition model checks, are not analysed.
* Window geometry on the iPad (copied attributes) and keyboard focus after the transition (no completion handler like `_configureRequest:`'s) were not looked at beyond the above.
