// X6InCall.x : gap G6 / audit rows A1 + A2, the in-call half (specs/GAPS-IMPLEMENTED-0.7.9.md section G6).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses).  Switch: incallscene.  Setup: X6_Setup().  Log prefix "[x6]" (Backport162.debug only).
//
// 16.2 mechanism: an SBInCallPresentationSession follows its scene handle's display.
//  * 16.0 SBInCallPresentationSession (init 0x1c60f0a10) is given a UIScreen and the MAIN display's scene manager (SBMainWorkspace
//    inCallPresentationManager:createPresentationSessionWithSceneHandle: 0x1c5efeb60: screen = [windowSceneForDisplayIdentity:[handle displayIdentity]] screen, sceneManager = [coordinator
//    mainDisplaySceneManager]) and registers everything itself in init, so a session of a call app on the extended display observes the layout transitions of the iPad.
//  * 16.2 (0x1c7372e7c) passes neither: ivars _screen / _sceneManager are gone, -_sceneManager 0x1c7583494 / -_screen 0x1c75834e0 read a weak window scene (+0x168) that
//    -initWithSceneHandle:... (0x1c75754c0) and -transitionToSceneHandleIfNeeded: (0x1c7575954) set from [windowSceneManager windowSceneForDisplayIdentity:[handle displayIdentity]].
//    transitionToSceneHandleIfNeeded:(new): if new == old return; for old: removeSceneUpdateContributer: / removeActionConsumer: / removeObserver: / [statusBarStateProvider
//    removeStatusBarObserver:] / [[_sceneManager _layoutStateTransitionCoordinator] removeObserver:] / invalidate _ignoreSuspendedUnderLockAssertion; then _sceneHandle = new,
//    window scene = scene of new's display, the same five add* calls, and (only a main display scene manager implements it) _ignoreSuspendedUnderLockAssertion =
//    [_sceneManager acquireIgnoreSuspendedUnderLockAssertionForSceneIdentifier:[new sceneIdentifier] reason:@"SBInCallPresentationSession - %@"].
//  * -sceneHandle:replacedWithSceneHandle: 0x1c757a10c: if [_sceneHandle isEqual:old] transitionToSceneHandleIfNeeded:new.  Sent by SBSceneHandle (SpringBoardUI)
//    -_noteReplacedWithSceneHandle: (16.2 0x1f2ccc7ec: [self _enumerateObserversWithBlock:^(observer, behavior){ if (behavior.replacedWithSceneHandle) [observer sceneHandle:self
//    replacedWithSceneHandle:new] }]), which -[SBSceneManager takeScene:fromSceneManager:] 16.2 0x1c73e9a3c calls (G4B.x already called it; 16.0's SpringBoardUI has no such method, so it did nothing).
//  * SBSceneManager takeScene:fromSceneManager: first calls the OLD manager's observers with sceneManager:old didTransferManagementOfScene:scene toSceneManager:self (callout block
//    0x1c73e9c70, G4B.x); the only implementer is SBInCallPresentationManager 0x1c76696ac: session = [self sessionForSceneIdentifier:[scene identifier]] (0x1c7669a1c: the session whose scene
//    handle has that identifier); if there is one and the new manager is not in _observedSceneManagers: [newManager addObserver:self], remember it; then [self _runZombieChecksForScene:scene].
//  * -[SBInCallPresentationManager _runZombieChecksForScene:] 16.0 0x1c61dd4c0 looked the handle up in the MAIN display scene manager; 16.2 0x1c766ba00 in [[SBSceneManagerCoordinator
//    sharedInstance] sceneManagerForDisplayIdentity:[[[scene settings] displayConfiguration] identity]].
//
// Port.  A runtime cannot remove the 16.0 ivars, so the 16.0 session keeps _screen / _sceneManager and the port keeps them equal to what 16.2 derives: after the workspace made a session,
// _sceneManager is moved to the scene manager of its window scene (observer re-registered); transitionToSceneHandleIfNeeded: and sceneHandle:replacedWithSceneHandle: are the 16.2
// methods written against the 16.0 ivars; the manager gets sessionForSceneIdentifier: / didTransferManagementOfScene:toSceneManager: and the 16.2 _runZombieChecksForScene:;
// SBSceneHandle gets _noteReplacedWithSceneHandle:.  Not display related and not ported: the non modal call suppression (SBInCallPresentationManager acquireNonModalSuppression...,
// session setNonModalPresentationsSuppressed:, used by SBTransientOverlayScenePresenter _updateFeaturePolicies).
// Needs a device: a FaceTime / call app scene on the extended display while the monitor is unplugged (migration) must keep its in-call session working on the iPad.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BP.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define X6_ON() BP_OnName("incallscene")

static void X6_SetIvar(id o, const char *name, id v) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    BP_SetObjIvar(o, iv, v);
}

// 16.2 -_sceneManager / -_screen (windowScene.sceneManager / .screen); here the ivars that the 16.0 session methods read
static id X6_SessionSceneManager(id self, SEL _cmd) { return BPX_IvarObj(self, "_sceneManager"); }
static id X6_SessionScreen(id self, SEL _cmd) { return BPX_IvarObj(self, "_screen"); }

static id X6_WindowSceneFor(id handle) {
    return BPX_Obj1(BPX_WindowSceneManager(), "windowSceneForDisplayIdentity:", BPX_Obj0(handle, "displayIdentity"));
}

static void X6_ObserveLayout(id session, id sceneManager, BOOL add) {
    id coord = BPX_Obj0(sceneManager, "_layoutStateTransitionCoordinator");
    BPX_SetObj1(coord, add ? "addObserver:" : "removeObserver:", session);
}

// 16.0 init registered the layout observer and the ignore-suspended assertion against the main display scene manager; move them to the scene manager of the window scene (16.2 -_sceneManager)
static void X6_RetargetSceneManager(id session) {
    id ws = BPX_IvarObj(session, "_windowScene");
    id newSM = BPX_Obj0(ws, "sceneManager");
    id oldSM = BPX_IvarObj(session, "_sceneManager");
    if (!newSM || newSM == oldSM) return;
    BP_Log(@"[x6] in-call session %@: scene manager %@ -> %@ (display of its scene handle)", session, oldSM, newSM);
    X6_ObserveLayout(session, oldSM, NO);
    X6_SetIvar(session, "_sceneManager", newSM);
    X6_SetIvar(session, "_screen", BPX_Obj0(ws, "screen"));
    X6_ObserveLayout(session, newSM, YES);
    if (![newSM respondsToSelector:sel_registerName("acquireIgnoreSuspendedUnderLockAssertionForSceneIdentifier:reason:")]) {     // 16.2 acquires it for a main display scene manager only
        id a = BPX_IvarObj(session, "_ignoreSuspendedUnderLockAssertion");
        if ([a respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(a, @selector(invalidate));
        X6_SetIvar(session, "_ignoreSuspendedUnderLockAssertion", nil);
    }
}

// -transitionToSceneHandleIfNeeded: 16.2 0x1c7575954, against the 16.0 ivars
static void X6_Transition(id self, SEL _cmd, id newHandle) {
    id old = BPX_IvarObj(self, "_sceneHandle");
    if (old == newHandle) return;
    if (old) {
        BPX_SetObj1(old, "removeSceneUpdateContributer:", self);
        BPX_SetObj1(old, "removeActionConsumer:", self);
        BPX_SetObj1(old, "removeObserver:", self);
        BPX_SetObj1(BPX_Obj0(old, "statusBarStateProvider"), "removeStatusBarObserver:", self);
        X6_ObserveLayout(self, BPX_IvarObj(self, "_sceneManager"), NO);
        id a = BPX_IvarObj(self, "_ignoreSuspendedUnderLockAssertion");
        if ([a respondsToSelector:@selector(invalidate)]) ((void (*)(id, SEL))objc_msgSend)(a, @selector(invalidate));
        X6_SetIvar(self, "_ignoreSuspendedUnderLockAssertion", nil);
    }
    X6_SetIvar(self, "_sceneHandle", newHandle);
    id ws = X6_WindowSceneFor(newHandle);
    X6_SetIvar(self, "_windowScene", ws);
    X6_SetIvar(self, "_screen", BPX_Obj0(ws, "screen"));
    id sm = BPX_Obj0(ws, "sceneManager");
    if (sm) X6_SetIvar(self, "_sceneManager", sm);
    BPX_SetObj1(newHandle, "addSceneUpdateContributer:", self);
    BPX_SetObj1(newHandle, "addActionConsumer:", self);
    BPX_SetObj1(newHandle, "addObserver:", self);
    BPX_SetObj1(BPX_Obj0(newHandle, "statusBarStateProvider"), "addStatusBarObserver:", self);
    id cur = BPX_IvarObj(self, "_sceneManager");
    X6_ObserveLayout(self, cur, YES);
    NSString *sid = BPX_Obj0(newHandle, "sceneIdentifier");
    SEL ign = sel_registerName("acquireIgnoreSuspendedUnderLockAssertionForSceneIdentifier:reason:");
    if (sid && [cur respondsToSelector:ign]) {                      // only the main display scene manager implements it (16.2: isKindOfClass:)
        id as = ((id (*)(id, SEL, id, id))objc_msgSend)(cur, ign, sid, [NSString stringWithFormat:@"SBInCallPresentationSession - %@", sid]);
        X6_SetIvar(self, "_ignoreSuspendedUnderLockAssertion", as);
    }
    BP_Log(@"[x6] in-call session %@ moved to scene handle %@ (window scene %@, scene manager %@)", self, newHandle, ws, cur);
}
// -sceneHandle:replacedWithSceneHandle: 16.2 0x1c757a10c
static void X6_Replaced(id self, SEL _cmd, id oldHandle, id newHandle) {
    if (X6_ON() && [BPX_IvarObj(self, "_sceneHandle") isEqual:oldHandle]) X6_Transition(self, NULL, newHandle);
}

// SBSceneHandle -_noteReplacedWithSceneHandle: 16.2 (SpringBoardUI 0x1f2ccc7ec)
static void X6_NoteReplaced(id self, SEL _cmd, id newHandle) {
    SEL en = sel_registerName("_enumerateObserversWithBlock:");
    if (![self respondsToSelector:en]) return;
    void (^blk)(id, id) = ^(id observer, id behavior) {
        SEL s = sel_registerName("sceneHandle:replacedWithSceneHandle:");
        if ([observer respondsToSelector:s]) ((void (*)(id, SEL, id, id))objc_msgSend)(observer, s, self, newHandle);
    };
    ((void (*)(id, SEL, id))objc_msgSend)(self, en, blk);
}

// SBInCallPresentationManager -sessionForSceneIdentifier: 16.2 0x1c7669a1c
static id X6_SessionForSceneIdentifier(id self, SEL _cmd, id ident) {
    NSDictionary *d = BPX_IvarObj(self, "_clientIdentifierToPresentationSession");
    for (id session in [d objectEnumerator])
        if ([BPX_Obj0(BPX_Obj0(session, "sceneHandle"), "sceneIdentifier") isEqual:ident]) return session;
    return nil;
}
// -sceneManager:didTransferManagementOfScene:toSceneManager: 16.2 0x1c76696ac
static void X6_DidTransfer(id self, SEL _cmd, id manager, id scene, id newManager) {
    if (!X6_ON()) return;
    id session = ((id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("sessionForSceneIdentifier:"), BPX_Obj0(scene, "identifier"));
    if (session) {
        NSMutableSet *observed = BPX_IvarObj(self, "_observedSceneManagers");
        if (![observed containsObject:newManager]) {
            BPX_SetObj1(newManager, "addObserver:", self);
            [observed addObject:newManager];
        }
    }
    BPX_SetObj1(self, "_runZombieChecksForScene:", scene);
    BPX_LOG(@"[x6] in-call manager: scene %@ transferred %@ -> %@ (session %@)", BPX_Obj0(scene, "identifier"), manager, newManager, session);
}

// -_runZombieChecksForScene: 16.2 0x1c766ba00 (16.0 0x1c61dd4c0: always the main display scene manager)
static IMP gX6OrigZombie;
static void X6_Zombie(id self, SEL _cmd, id scene) {
    if (!X6_ON()) { if (gX6OrigZombie) ((void (*)(id, SEL, id))gX6OrigZombie)(self, _cmd, scene); return; }
    Class coordC = NSClassFromString(@"SBSceneManagerCoordinator");
    id ident = BPX_Obj0(BPX_Obj0(BPX_Obj0(scene, "settings"), "displayConfiguration"), "identity");
    id sm = BPX_Obj1(coordC ? BPX_Obj0((id)coordC, "sharedInstance") : nil, "sceneManagerForDisplayIdentity:", ident);
    id handle = BPX_Obj1(sm, "existingSceneHandleForScene:", scene);
    if (handle) BPX_SetObj1(self, "_runZombieChecksForSceneHandle:", handle);
}

// the workspace builds the session with the main display scene manager (16.0 0x1c5efeb60)
static IMP gX6OrigCreate;
static id X6_Create(id self, SEL _cmd, id manager, id handle) {
    id session = gX6OrigCreate ? ((id (*)(id, SEL, id, id))gX6OrigCreate)(self, _cmd, manager, handle) : nil;
    if (session && X6_ON()) X6_RetargetSceneManager(session);
    return session;
}

void X6_Setup(void) {
    Class sess = NSClassFromString(@"SBInCallPresentationSession");
    Class mgr = NSClassFromString(@"SBInCallPresentationManager");
    Class handle = NSClassFromString(@"SBSceneHandle");
    Class mw = NSClassFromString(@"SBMainWorkspace");
    SEL createS = sel_registerName("inCallPresentationManager:createPresentationSessionWithSceneHandle:");
    if (!sess || !mgr || !handle || !mw || !class_getInstanceMethod(mw, createS) || !class_getInstanceMethod(mgr, sel_registerName("_runZombieChecksForScene:"))
        || !class_getInstanceMethod(handle, sel_registerName("_enumerateObserversWithBlock:"))) {
        BP_Log(@"[x6] in-call per scene NOT installed (class or selector missing)");
        return;
    }
    class_addMethod(sess, sel_registerName("_sceneManager"), (IMP)X6_SessionSceneManager, "@16@0:8");
    class_addMethod(sess, sel_registerName("_screen"), (IMP)X6_SessionScreen, "@16@0:8");
    class_addMethod(sess, sel_registerName("transitionToSceneHandleIfNeeded:"), (IMP)X6_Transition, "v24@0:8@16");
    class_addMethod(sess, sel_registerName("sceneHandle:replacedWithSceneHandle:"), (IMP)X6_Replaced, "v32@0:8@16@24");
    class_addMethod(handle, sel_registerName("_noteReplacedWithSceneHandle:"), (IMP)X6_NoteReplaced, "v24@0:8@16");
    class_addMethod(mgr, sel_registerName("sessionForSceneIdentifier:"), (IMP)X6_SessionForSceneIdentifier, "@24@0:8@16");
    class_addMethod(mgr, sel_registerName("sceneManager:didTransferManagementOfScene:toSceneManager:"), (IMP)X6_DidTransfer, "v40@0:8@16@24@32");
    gX6OrigZombie = BPX_Replace(mgr, "_runZombieChecksForScene:", (IMP)X6_Zombie);
    gX6OrigCreate = BPX_Replace(mw, "inCallPresentationManager:createPresentationSessionWithSceneHandle:", (IMP)X6_Create);
    BP_Log(@"[x6] in-call presentation sessions follow their scene handle's display (switch incallscene)");
}
#pragma clang diagnostic pop
