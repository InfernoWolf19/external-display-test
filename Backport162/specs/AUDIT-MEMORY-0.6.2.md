# AUDIT-MEMORY-0.6.2: autorelease-pool over-release after dragging an app from the strip onto the stage

Scope: static analysis of the path gesture type 9 -> SBGestureRootSwitcherModifier handleGestureEvent: -> window-drag root (G1C) -> G1B/G1C event, response and
modifier classes -> G2B data model / layout -> G2 overlapping controller -> G3 / G3B / G4B hooks that run on scene updates.
Symptom (build 2789c32): EXC_BAD_ACCESS in objc_release <- AutoreleasePoolPage::releaseUntil <- objc_autoreleasePoolPop <- __processEventQueue (main thread),
i.e. an object that sits in a pool was freed (or is stale memory) when the pool popped.

Method: every IMP / block / Logos hook we install was checked against the 16.0 class dump (sb160n_objc.txt) for (1) return KIND (object / void / BOOL / scalar /
struct): 321 table entries, 148 %hook methods, 52 replacement blocks, 27 C IMPs; (2) ownership convention implied by the selector family
(alloc / new / copy / mutableCopy / init, leading underscores ignored); (3) every id-returning send helper (G1B_Send0/1, BP2B_Obj/Obj1, BP_G2_Obj, G4B_Obj,
BP_G3B_Send0, ...) against the real return type of the selector it is aimed at; (4) every ivar write (object_setIvar, memcpy, ivar_getOffset). ARC code generation
of the suspicious patterns was confirmed with clang 18 (-target arm64-apple-ios15 -fobjc-arc -O0/-O2, LLVM IR).

## Findings (ranked)

### 1. [FIXED] G2B.m:1878 `-[SBFluidSwitcherViewController _dispatchEventAndHandleAction:]` replaced by a block that RETURNS an object (HIGH confidence, most likely culprit)

* What was wrong: the 16.0 method is `- (void)_dispatchEventAndHandleAction:(id)action` (dump 0x1c5fe17e4). The tongue hook replaced it with
  `^id(id me, id ev) { id r = oDisp ? ((id (*)(id, SEL, id))oDisp)(me, sel, ev) : nil; ...; return r; }`.
  A void method does not set x0, so `r` is whatever the original left in x0. The original ends with a chain of `objc_release_x8` calls (disassembly), i.e. x0 is
  the last object it released, very often an object that has just been DEALLOCATED (the dispatched event copy). ARC compiled the cast call with
  `clang.arc.attachedcall(retainAutoreleasedReturnValue)` (retain of the stale pointer, writes into freed memory) and `return r` as `objc_autoreleaseReturnValue(r)`
  (queues the stale pointer in the CALLER's autorelease pool; the caller is void and ignores it). When the pool pops, objc_release hits freed / re-used memory:
  exactly "EXC_BAD_ACCESS in objc_release <- AutoreleasePoolPage::releaseUntil <- objc_autoreleasePoolPop <- __processEventQueue".
* Why a drag triggers it: every event dispatch in the switcher goes through this method; a window drag dispatches a stream of gesture / resize / blur / transition events
  (each with copies that die inside the call), so the stale x0 is almost always a freed object, and it crashes within seconds. No log line is written because nothing
  of ours fails.
* Fix: the block is now void (`^(id me, id ev)`), calls the original through a `void (*)` cast and returns nothing. The ObjC type encoding of the replaced method
  ("v24@0:8@16", taken from the original Method) now matches the implementation.

### 2. [FIXED] id-returning send helpers aimed at VOID selectors (same mechanism as 1; MEDIUM)

`BP2B_Obj / BP2B_Obj1 / G1B_Send0` return `id`; ARC retains (and, through the helper's `return`, autoreleases) whatever the callee leaves in x0. Used on void methods
they retain / release / autorelease a stale pointer (immediate crash in objc_retain when x0 is not an object, or a stale autorelease in the pool when the helper is
not inlined). Every site is now a void send:

* G2B.m: `layoutIfNeeded` x6 (item-container / overlay / underlay views, in `_layoutAppLayout:roleMask:completion:`, which runs for every window on every
  layout pass during the drag), `_dispatchEventAndHandleAction:` x3 (blur began/done blocks, `BP2B_DispatchTap`), `_ensureSubviewOrdering` x2, `_handleEventResponse:`,
  `dismissContinuousExposeStripEdgeProtectTongue`. New helpers `BP2B_Void0 / BP2B_Void1` (G2B.m:33-34).
* G1B.x:533 `presentContinuousExposeStripRevealGrabberTongueImmediately` / `tickle...` through `G1B_Send0` -> `G1B_SendV0` (new helper in G1BKit.h:101).

(Casts whose result is discarded, e.g. G4B.x:795 / G3B.x:206 `postPresentable:...` through `(id (*)())`, compile to `unsafeClaimAutoreleasedReturnValue` and are harmless.)

### 3. [FIXED] G1C.x:2877 object stored with `object_setIvar` in a `class_addIvar`'ed ivar (LOW, latent dangling pointer)

`BP162HomeScreenContinuousExposeSwitcherModifier` gets `_stripModifier` ("@") from class_addIvar (G1C.x:2915). A run-time ivar has no ARC layout, so object_setIvar
stores UNRETAINED and nothing releases it; the pointer dangles as soon as the strip child modifier is removed. Nothing reads the ivar today, so it was harmless, but it
was the one instance of pattern (a). The strip is now kept in an associated object (`kHsStrip`, retained). The ivar declaration stays (harmless, unused).
All other `G1C_SetIvarObj / object_setIvar` targets are ivars declared by 16.0 ARC classes (`_initialAppLayout`, `_selectedDisplayItem`, `_destinationModifier`,
`_continuousExposeIdentifiers`, `_appLayoutToOrderFront`, `_queue_*Assertion`, ...), whose layout makes object_setIvar a retaining store. OK.

### 4. [VERIFIED OK, do not "fix"] copy / mutableCopy / init / new family methods in Logos hooks and block IMPs

* Pass-through hooks `id c = %orig; ...; return c;` on copy/mutableCopy/init methods (G1C.x:2671 `copyWithZone:` of the window-drag event, G2.x:553 `mutableCopyWithZone:`,
  G2.x:1345 `copyWithZone:`, G3.x:326 / 405, G3B.x:339 / 1037, Tweak.x:343, G2B.m:1408 TapEvent `copyWithZone:`, G2B.m:652 `initWithPlistRepresentation:`) are
  accidentally correct: the original returns +1, ARC retains it again (attachedcall) and returns it autoreleased, so the caller ends with exactly one owned reference and
  the pool drops the extra one. (Confirmed in IR, -O0 and -O2.) Adding ns_returns_retained to these would LEAK; leave them alone.
* The four fresh-object copy IMPs (G1B.x:414 HeaderEv_Copy, G1B.x:443 TongueEv_Copy, G1C.x:490 IdsEv_Copy, G2B.m:628 attributes copyWithZone:) are correct with
  ns_returns_retained (attribute on a block literal is honoured: IR shows no autoreleaseReturnValue).
* All `init*` IMPs return the object produced by `[super init...]` (or nil) - ownership-neutral under ARC (nil only leaks the half-built object).
* Factory pattern `return objc_msgSend-cast([cls alloc], init...)` is balanced under ARC (the temp from `alloc` is released, the cast result is retained+autoreleased): no leak, no over-release.

### 5. [NOTE, unchanged] fragile but currently balanced

* G1C.x:350 `_newMultitaskingModifier` (family `new`) returns `[m copy]` autoreleased (+0). Only our own G1C_GridRoot_TransitionChild calls it (via G1B_Send0, +0
  expectation), and 16.0's `_newMultitaskingModifier` callers live in other root classes, so it is consistent. If this class ever gets a 16.0 caller, add
  ns_returns_retained AND consume the result at the call site.
* G3B.x:1019 (hook) + G3B.x:810 (BPMedusaHostedKeyboardWindowController): `newMedusaHostedKeyboardWindowLevelAssertion...`: the inner method leaks one reference
  (ARC retains the +1 it got through an id cast) and the hook returns its +1 as autoreleased; the two errors cancel. Not touched (fixing one half alone would turn
  it into an over-release).

### 6. [CHECKED, no defect found]

* Event / response / modifier classes built with G1B_MakeClass: scalar state in class_addIvar ivars (no objects), object state in RETAIN associated objects.
  No other class_addIvar object ivar exists. G1C_IvarRaw / G1C_SetIvarX names verified against the dump (types and sizes match).
* `__bridge_transfer` in G3B.x:1435 / 1507 (newSceneView... returns +1) balanced; CFBridgingRetain / CFRelease pairs in G2B region fallback balanced;
  CFAutorelease of CGRegion "Create" results in G2.x balanced.
* `__unsafe_unretained` (G3B.x:1090 thread-local switcher override): only used inside the scope of %orig, owner alive.
* Blocks: stack blocks passed to Apple (animations / completions) are copied by the callee; blocks stored in locals are heap-copied by ARC; no unretained capture of
  objects that outlive their owner. dispatch_after / dispatch_async blocks capture __weak.
* G4B lockedptr2 / deferact / presubset hooks, G3 snapshot / handle hooks, Group4Focus hooks: only retained associated objects, __weak boxes and by-name strong ivars.
* SBAppendSwitcherModifierResponse -> SBAppendChainableModifierResponse (0x1c648a670) is a plain +0 ARC function (retain x1 / release, autoreleaseReturnValue): no consumed arguments.

## Files changed

* Backport162/G2B.m: void replacement block for `_dispatchEventAndHandleAction:`; `BP2B_Void0/1`; 13 call sites.
* Backport162/G1BKit.h: `G1B_SendV0`.
* Backport162/G1B.x: grabber consumer uses `G1B_SendV0`.
* Backport162/G1C.x: `kHsStrip` associated object instead of unretained run-time ivar.
* logos.pl run on G1B.x and G1C.x (clean). G2B.m is plain ObjC (no Logos).
