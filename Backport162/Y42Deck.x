// Y42Deck.x : delta sweep pass 4 (block capable recompiler), the app suggestion handling of the card deck switcher of iPadOS 16.2.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_deck  SBDeckSwitcherViewController (the iPhone style card deck; the iPad Stage Manager switcher does not use it):
//     -performTransitionWithContext:animated:completion:                       16.2 0x1c73151d8 (16.0 0x1c5ea2514)  block invoke 0x1c77c9724
//     -layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext: 0x1c77c97c0 (16.0 0x1c632894c)
//     -layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:   0x1c77c99cc (16.0 0x1c6328aec)  block invokes 0x1c77c9c40, 0x1c77c9c4c
//     new: -_assertionReason 0x1c77c9e2c, -appSuggestionManager 0x1c77c9ecc, -setAppSuggestionManager: 0x1c77c9f00, and the init step of 0x1c77c95e8 (the weak ivar is set to [SBAppSuggestionManager sharedInstance])
//   16.2 keeps the app suggestion model of the deck from updating while the deck is not shown (disableListeningForUpdatesForReason: / enableListeningForUpdatesForReason:, the reason string is
//   -_assertionReason) and reads the model through a NEW weak ivar _appSuggestionManager (16.0 instances have no room for it, the subclass of the class has no free slot: the ivar of the 16.2
//   class is in a RUNTIME SUBCLASS "Y42DeckSwitcherViewController" (Y34Ext.h: class_addIvar, objc_storeWeak by hand, own .cxx_destruct, -class / -isMemberOfClass: shims) that every
//   SBDeckSwitcherViewController allocation produces (+allocWithZone: of the base class swapped, as Y34ClassicSupport.x does); the recompiled bodies find the ivar BY NAME through the subclass).
//   The three methods are NOT re-typed: Y42DeckLift.c is the 16.2 machine code recompiled by tools/a2c (stack blocks with arm64e pointer signing included); verified with tools/a2c/tests/tracecmp.py
//   (calls, ownership events in order, PAC logs, block images) on 24 seeds per body.  The 16.0 init (dataSource:debugName:) gets the one step 16.2 adds: the weak manager.
//   Also: -invalidate 0x1c77c96a0 (recompiled, added: the manager stops listening, then [super invalidate]) and the gesture begin (16.2 -handleFluidSwitcherGestureManager:didBeginGesture: 0x1c77c9ccc, hand ported into the
//   16.0 -handleGestureDidBegin: the 16.0 gesture manager still sends: see Y42_DeckGesture).  NOT ported: the 16.2 init selector with shouldObserveChamoisWindowingChanges: (16.0 callers send the 16.0 init selector,
//   which is hooked above; nothing in 16.0 sends the 16.2 selector; the 16.2 init is the 16.0 init plus the manager step, 0x1c77c95e8).
//   What can break on a device: the runtime subclass (class identity is shimmed, KVO / archiving do not apply to the deck), signed stack blocks (arm64e pacda / pacia), the weak ivar teardown.
//   An instance that is not of the subclass (a subclass of the deck allocated by its own +alloc) runs the 16.0 methods.
// Switch y42_deck (kill file Backport162.off.y42_deck).  Installed only on build 20A8372; ANOMALY y42-deck (always on) names the build.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "Y34Ext.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern void *y42_storeWeak(void **location, void *obj) __asm__("_objc_storeWeak");
extern void y42_deck_perform(uint64_t self, uint64_t cmd, uint64_t context, uint64_t animated, uint64_t completion);
extern void y42_deck_begin(uint64_t self, uint64_t cmd, uint64_t coordinator, uint64_t context);
extern void y42_deck_end(uint64_t self, uint64_t cmd, uint64_t coordinator, uint64_t context);
extern uint64_t y42_deck_reason(uint64_t self, uint64_t cmd);
extern uint64_t y42_deck_getmanager(uint64_t self, uint64_t cmd);
extern void y42_deck_setmanager(uint64_t self, uint64_t cmd, uint64_t manager);
extern void y42_deck_invalidate(uint64_t self, uint64_t cmd);
extern const char *y42_deck_preflight(void);

static Class gDeckBase, gDeckExt;
static Ivar gIvManager;
static IMP gOrigAlloc, gOrigInit, gOrigPerform, gOrigBegin, gOrigEnd, gOrigGesture;

#define Y42_P(o) ((uint64_t)(uintptr_t)(__bridge void *)(o))
#define Y42_C(c) ((uint64_t)(uintptr_t)(void *)(c))

static BOOL Y42_Mine(id self) { return gDeckExt && [self isKindOfClass:gDeckExt]; }

static void Y42_DeckPerform(id self, SEL _cmd, id context, BOOL animated, id completion) {
    if (!BP_OnName("y42_deck") || !Y42_Mine(self)) { ((void (*)(id, SEL, id, BOOL, id))gOrigPerform)(self, _cmd, context, animated, completion); return; }
    y42_deck_perform(Y42_P(self), Y42_C(_cmd), Y42_P(context), animated, Y42_P(completion));
}
static void Y42_DeckBegin(id self, SEL _cmd, id coordinator, id context) {
    if (!BP_OnName("y42_deck") || !Y42_Mine(self)) { ((void (*)(id, SEL, id, id))gOrigBegin)(self, _cmd, coordinator, context); return; }
    y42_deck_begin(Y42_P(self), Y42_C(_cmd), Y42_P(coordinator), Y42_P(context));
}
static void Y42_DeckEnd(id self, SEL _cmd, id coordinator, id context) {
    if (!BP_OnName("y42_deck") || !Y42_Mine(self)) { ((void (*)(id, SEL, id, id))gOrigEnd)(self, _cmd, coordinator, context); return; }
    y42_deck_end(Y42_P(self), Y42_C(_cmd), Y42_P(coordinator), Y42_P(context));
}
static id Y42_DeckReason(id self, SEL _cmd) { return (__bridge id)(void *)(uintptr_t)y42_deck_reason(Y42_P(self), Y42_C(_cmd)); }
static id Y42_DeckGetManager(id self, SEL _cmd) {
    if (!Y42_Mine(self)) return nil;
    return (__bridge id)(void *)(uintptr_t)y42_deck_getmanager(Y42_P(self), Y42_C(_cmd));
}
static void Y42_DeckSetManager(id self, SEL _cmd, id manager) { if (Y42_Mine(self)) y42_deck_setmanager(Y42_P(self), Y42_C(_cmd), Y42_P(manager)); }

// -invalidate: NEW in the 16.2 deck (0x1c77c96a0: the manager stops listening for the reason, then [super invalidate]); the 16.0 deck inherits SBFluidSwitcherViewController's
static void Y42_DeckInvalidate(id self, SEL _cmd) {
    if (BP_OnName("y42_deck") && Y42_Mine(self)) { y42_deck_invalidate(Y42_P(self), Y42_C(_cmd)); return; }
    struct objc_super sup = { self, class_getSuperclass(gDeckBase) };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}
// 16.2 -handleFluidSwitcherGestureManager:didBeginGesture: 0x1c77c9ccc (50 instructions, read from the machine code: retain manager / gesture, [_appSuggestionController setShowSuggestions:NO],
// manager = weak _appSuggestionManager, [manager disableListeningForUpdatesForReason:[self _assertionReason]], release, [super handleFluidSwitcherGestureManager:didBeginGesture:]).
// The 16.0 gesture manager still sends -handleGestureDidBegin: (16.0 0x1c6328db4: setShowSuggestions:NO, [super handleGestureDidBegin:]) to the deck; the protocol was renamed in 16.2, so the 16.2 steps are
// done in this 16.0 entry point and the super call keeps the 16.0 selector (the 16.0 superclass has no 16.2 selector).  Hand ported (the super selector differs, the recompiled body cannot be used).
static void Y42_DeckGesture(id self, SEL _cmd, id gesture) {
    if (!BP_OnName("y42_deck") || !Y42_Mine(self)) { ((void (*)(id, SEL, id))gOrigGesture)(self, _cmd, gesture); return; }
    id keep = gesture;
    Ivar ic = class_getInstanceVariable(gDeckBase, "_appSuggestionController");
    id controller = BP_ObjIvar(self, ic);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, sel_registerName("setShowSuggestions:"), NO);
    id manager = (__bridge id)(void *)(uintptr_t)y42_deck_getmanager(Y42_P(self), sel_registerName("appSuggestionManager"));
    id reason = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("_assertionReason"));
    ((void (*)(id, SEL, id))objc_msgSend)(manager, sel_registerName("disableListeningForUpdatesForReason:"), reason);
    struct objc_super sup = { self, class_getSuperclass(gDeckBase) };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, keep);
}
static id Y42_DeckAlloc(id self, SEL _cmd, void *zone) {
    Class use = (self == (id)gDeckBase) ? gDeckExt : (Class)self;
    return ((id (*)(id, SEL, void *))gOrigAlloc)((id)use, _cmd, zone);
}
// the weak ivar of the subclass is destroyed by hand (a runtime-added ivar is not known to the runtime)
static void Y42_DeckDestruct(id self, SEL _cmd) { y42_storeWeak(Y34_IvarSlot(self, gIvManager), NULL); }

// 16.0 -initWithSwitcherController:rootModifier:liveContentOverlayCoordinator:delegate:dataSource:debugName:, then the step 16.2 adds (0x1c77c9674 ..): the weak manager
typedef void *(*Y42DeckInitFn)(void *, SEL, id, id, id, id, id, id);
__attribute__((ns_returns_retained)) static id Y42_DeckInit(id __attribute__((ns_consumed)) self, SEL _cmd, id controller, id modifier, id coordinator, id delegate, id source, id name) {
    void *raw = (__bridge_retained void *)self;
    void *r = ((Y42DeckInitFn)gOrigInit)(raw, _cmd, controller, modifier, coordinator, delegate, source, name);
    id me = (__bridge_transfer id)r;
    if (me && BP_OnName("y42_deck") && Y42_Mine(me)) {
        Class m = NSClassFromString(@"SBAppSuggestionManager");
        id mgr = m ? ((id (*)(id, SEL))objc_msgSend)((id)m, sel_registerName("sharedInstance")) : nil;
        y42_storeWeak(Y34_IvarSlot(me, gIvManager), (__bridge void *)mgr);
    }
    return me;
}

__attribute__((constructor)) static void Y42Deck_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_deck")) return;
        gDeckBase = NSClassFromString(@"SBDeckSwitcherViewController");
        if (!gDeckBase) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: SBDeckSwitcherViewController missing"); return; }
        SEL initSel = sel_registerName("initWithSwitcherController:rootModifier:liveContentOverlayCoordinator:delegate:dataSource:debugName:");
        const char *sels[] = { "performTransitionWithContext:animated:completion:", "layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:", "layoutStateTransitionCoordinator:transitionDidEndWithTransitionContext:" };
        for (int k = 0; k < 3; k++)
            if (!class_getInstanceMethod(gDeckBase, sel_registerName(sels[k]))) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: -[SBDeckSwitcherViewController %s] does not exist", sels[k]); return; }
        if (!class_getInstanceMethod(gDeckBase, initSel) || !BP_IvarLookup(gDeckBase, "_appSuggestionController")) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: the 16.0 init / _appSuggestionController of SBDeckSwitcherViewController is missing"); return; }
        if (!NSClassFromString(@"SBAppSuggestionManager")) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: SBAppSuggestionManager missing"); return; }
        Method am = class_getClassMethod(gDeckBase, @selector(allocWithZone:));
        gOrigAlloc = am ? method_getImplementation(am) : NULL;
        if (!gOrigAlloc) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: +allocWithZone: not found"); return; }
        static const Y34IvarSpec ivars[] = { { "_appSuggestionManager", sizeof(void *), 3, "@" } };
        gDeckExt = Y34_MakeExt("SBDeckSwitcherViewController", "Y42DeckSwitcherViewController", ivars, 1);
        if (!gDeckExt) return;
        gIvManager = class_getInstanceVariable(gDeckExt, "_appSuggestionManager");
        if (!gIvManager) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: the subclass ivar is missing"); gDeckExt = Nil; return; }
        Y34_AddIdentityShims(gDeckExt, gDeckBase);
        lift_register_ext("SBDeckSwitcherViewController", (__bridge void *)gDeckExt);
        const char *miss = y42_deck_preflight();
        if (miss) { BP_Anomaly("y42", @"[y42] y42_deck NOT installed: unresolved names of the recompiled 16.2 bodies: %s: the 16.0 deck stays", miss); gDeckExt = Nil; return; }
        class_addMethod(gDeckExt, sel_registerName(".cxx_destruct"), (IMP)Y42_DeckDestruct, "v@:");
        if (!class_getInstanceMethod(gDeckBase, sel_registerName("_assertionReason"))) class_addMethod(gDeckBase, sel_registerName("_assertionReason"), (IMP)Y42_DeckReason, "@@:");
        if (!class_getInstanceMethod(gDeckBase, sel_registerName("appSuggestionManager"))) class_addMethod(gDeckBase, sel_registerName("appSuggestionManager"), (IMP)Y42_DeckGetManager, "@@:");
        if (!class_getInstanceMethod(gDeckBase, sel_registerName("setAppSuggestionManager:"))) class_addMethod(gDeckBase, sel_registerName("setAppSuggestionManager:"), (IMP)Y42_DeckSetManager, "v@:@");
        gOrigPerform = BPX_Replace(gDeckBase, sels[0], (IMP)Y42_DeckPerform);
        gOrigBegin = BPX_Replace(gDeckBase, sels[1], (IMP)Y42_DeckBegin);
        gOrigEnd = BPX_Replace(gDeckBase, sels[2], (IMP)Y42_DeckEnd);
        class_addMethod(gDeckBase, sel_registerName("invalidate"), (IMP)Y42_DeckInvalidate, "v@:");
        if (class_getInstanceMethod(gDeckBase, sel_registerName("handleGestureDidBegin:"))) gOrigGesture = BPX_Replace(gDeckBase, "handleGestureDidBegin:", (IMP)Y42_DeckGesture);
        else BP_Anomaly("y42", @"[y42] y42_deck: -[SBDeckSwitcherViewController handleGestureDidBegin:] does not exist: the 16.2 gesture begin step is not installed");
        gOrigInit = BPX_Replace(gDeckBase, "initWithSwitcherController:rootModifier:liveContentOverlayCoordinator:delegate:dataSource:debugName:", (IMP)Y42_DeckInit);
        Class meta = object_getClass((id)gDeckBase);
        class_replaceMethod(meta, @selector(allocWithZone:), (IMP)Y42_DeckAlloc, method_getTypeEncoding(am));
        BP_Log(@"[y42] installed y42_deck");
        BP_Anomaly("y42-deck", @"[y42] y42_deck active (NOT device tested): every SBDeckSwitcherViewController is allocated as the runtime subclass Y42DeckSwitcherViewController (+allocWithZone: replaced; -class answers SBDeckSwitcherViewController); the 16.2 performTransition / transitionDidBegin / transitionDidEnd (recompiled) replace the 16.0 code; OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_deck", __DATE__, __TIME__);
    }
}
#pragma clang diagnostic pop
