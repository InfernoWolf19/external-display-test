// Y1Workspace.x : delta sweep family F1 (specs/DELTA-SWEEP-0.7.9.md): main workspace / scene manager / scene handle methods of SpringBoard 16.2 (20C65) that 16.0 (20A8372)
// only runs for the MAIN display.  Setup: constructor (needs nothing from Tweak.x).  Log prefix "[y1]" (Backport162.debug only).  Unslid cache addresses.
//
//  y1_appremoved  An application entity that is removed (app killed / its card removed / its scene destroyed) is looked up in the layout state of EVERY connected window
//                 scene, not only the main display's, and the app-exited transaction runs for the display of the dying scene:
//       -[SBMainWorkspace _removeApplicationEntitiesFromWorkspace:error:]  16.0 0x1c5f036fc / 16.2 0x1c7377ba0: a scene is not destroyed while ANY display lays it out (16.0: main only,
//            so the scene of a window on the extended display was destroyed under the layout).  Same sets / messages / error as 16.2 (code 2: not destroyed synchronously / laid out / not found).
//       -[SBMainWorkspace _cleanupForRemovedAppEntity:] 16.2 0x1c7377338 (NEW; the body of 16.0 _applicationEntityWasRemovedFromAppSwitcher: 0x1c5f02f58 with the any-display lookup):
//            when the entity is still laid out on some display an "ApplicationEntity was removed = %@" workspace event runs [self setCurrentTransaction:[self _selectTransactionForAppEntityRemoved:entity]].
//            16.0 _applicationEntityWasRemovedFromAppSwitcher: (called by _SBWorkspaceNoteApplicationEntityWasRemovedFromAppSwitcher) forwards to it; 16.2 -_destroyApplicationSceneEntity:
//            0x1c737708c additionally calls it when the scene is already gone and no UIDestroySceneAction can be sent (scene nil and (no persistence id or process not running)).
//       -[SBMainWorkspace _selectTransactionForAppEntityRemoved:] 16.0 0x1c5f0191c / 16.2 0x1c7375c68: the contingency plan and the request use the window scene of the display of the
//            scene's settings (sb_displayIdentityForSceneManagers; embedded scene when that display is gone): its switcherController as layout context and createRequestWithOptions:0
//            displayConfiguration:[ws _fbsDisplayConfiguration] (16.0: the coordinator = main display and createRequestWithOptions:0).
//  y1_scenestyle  -[SBDeviceApplicationSceneHandle _modifyApplicationSceneSettings:fromRequestContext:entity:] 16.0 0x1c5e2b9a8 / 16.2 0x1c729dfb4: 16.2 sets the scene's
//            userInterfaceStyle (app's supportedUserInterfaceStyle, else the arbiter's current style) for every display, 16.0 only inside [[settings displayIdentity] isMainDisplay]:
//            apps on the extended display stayed light when the iPad was dark.  (The 16.2 screenBoundsIgnoresSceneOrientation property needs the 16.2 UIKit client: not portable here.)
//  y1_extaction   -[SBSystemShellExternalDisplaySceneManager _handleAction:forScene:] 16.0 0x1c63ae37c: 16.2 handles UIDestroySceneAction (UIActionType 0x23) in the base class
//            -[SBSceneManager _handleAction:forScene:] 0x1c72e3b58 for every scene manager, 16.0 only in SBMainDisplaySceneManager 0x1c5e70a78: an app window on the extended display
//            that asks to close its own scene (requestSceneSessionDestruction) got no answer.  The 16.0 main display branch (identical code, uses only SBSceneManager API) runs for it.
//  y1_takescene   -[SBSceneManager takeScene:fromSceneManager:] (16.2 0x1c73e9a3c; the 16.2 caller block 0x1c784e3f8 of SBToAppsWorkspaceTransaction transaction:performTransition...):
//            after a scene moved to another display the new scene handle gets setWantsEnhancedWindowingEnabled: = isChamoisWindowingUIEnabled of the NEW display's switcher controller.
//
// Not ported (reasons in the table of the spec): the 16.2 isKeyboardVisibleForSpringBoard... / didDismissViewController presenter variants (need an export of the G3B hosted keyboard
// controller: NEEDS EDIT IN G3B.x), SBSuspendedWorkspaceTransaction animation fence for non-main displays (inlined into a 108 instruction block sequence), privacy preflight.
// Needs a device: (appremoved) kill an app that has a window on the monitor from the switcher / with a crash: the monitor must return to its home screen / the remaining windows, the
// scene must not be torn down before the layout changes; (scenestyle) dark mode on the iPad, open an app on the monitor: it is dark; (extaction) close a window from inside an app on the
// monitor; (takescene) drag a window to the other display.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define Y1_ON(n) BP_OnName(n)

static IMP gY1OrigRemove, gY1OrigWasRemoved, gY1OrigDestroy, gY1OrigSelect, gY1OrigModify, gY1OrigExtAction, gY1OrigTake;

// ---------------------------------------------------------------------------------------------- shared: the entity is laid out on some display
static BOOL Y1_EntityLaidOut(NSString *uid) {
    if (!uid) return NO;
    for (id ws in BPY_ConnectedScenes()) {
        id elements = BPX_Obj0(BPX_Obj0(BPX_Obj0(ws, "layoutStateProvider"), "layoutState"), "elements");
        for (id el in elements) {
            NSString *u = BPX_Obj0(BPX_Obj0(BPX_Obj0(el, "workspaceEntity"), "applicationSceneEntity"), "uniqueIdentifier");
            if ([u isEqualToString:uid]) return YES;
        }
    }
    return NO;
}

// ---------------------------------------------------------------------------------------------- _removeApplicationEntitiesFromWorkspace:error: (16.2 0x1c7377ba0)
static BOOL Y1_RemoveEntities(id self, SEL _cmd, id entities, NSError **error) {
    if (!Y1_ON("y1_appremoved")) return gY1OrigRemove ? ((BOOL (*)(id, SEL, id, NSError **))gY1OrigRemove)(self, _cmd, entities, error) : YES;
    Class fbsm = NSClassFromString(@"FBSceneManager");
    id sm = fbsm ? BPX_Obj0((id)fbsm, "sharedInstance") : nil;
    NSMutableSet *laidOut = [NSMutableSet set], *notFound = [NSMutableSet set], *destroyed = [NSMutableSet set];
    for (id entity in entities) {
        NSString *uid = BPX_Obj0(entity, "uniqueIdentifier");
        if (Y1_EntityLaidOut(uid)) [laidOut addObject:uid];
        if (uid && ![laidOut containsObject:uid]) {
            if (BPX_Obj1(sm, "sceneWithIdentifier:", uid)) {
                BPY_SEND(void, (id, id), sm, "destroyScene:withTransitionContext:", uid, nil);
                [destroyed addObject:uid];
            } else [notFound addObject:uid];
        }
    }
    NSError *err = nil;
    BOOL ret = YES;
    for (NSString *uid in [destroyed allObjects]) {
        if (!BPX_Obj1(sm, "sceneWithIdentifier:", uid)) continue;
        NSString *m = [NSString stringWithFormat:@"The scene with identifier — %@ — was not destroyed synchronously by FBSceneManager as we relied upon", uid];
        NSLog(@"%@", m);
        err = [NSError errorWithDomain:@"SBWorkspaceErrorDomain" code:2 userInfo:@{ NSLocalizedFailureReasonErrorKey: m }];
        ret = NO;
        break;
    }
    if (ret) {
        NSMutableString *msg = [NSMutableString string];
        if (laidOut.count) {
            [msg appendString:@"The following scenes where not destroyed since they are laid out as foreground and we were asked to not remove their sessions (destroySessions flag is false): "];
            [msg appendString:laidOut.description];
        }
        if (notFound.count) {
            [msg appendString:@"\n The following scenes couldn't be found: "];
            [msg appendString:notFound.description];
        }
        if (msg.length) {
            NSLog(@"%@", msg);
            err = [NSError errorWithDomain:@"SBWorkspaceErrorDomain" code:2 userInfo:@{ NSLocalizedFailureReasonErrorKey: msg }];
        }
    }
    if (error) *error = err;
    BPY_LOG(@"[y1] removeApplicationEntities: %lu entities, %lu laid out on some display, %lu destroyed, %lu not found -> %d", (unsigned long)[entities count], (unsigned long)laidOut.count,
            (unsigned long)destroyed.count, (unsigned long)notFound.count, (int)ret);
    return ret;
}

// ---------------------------------------------------------------------------------------------- _cleanupForRemovedAppEntity: (16.2 0x1c7377338) and its callers
static void Y1_Cleanup(id self, SEL _cmd, id entity) {
    NSString *uid = BPX_Obj0(entity, "uniqueIdentifier");
    if (!uid) return;
    if (!Y1_EntityLaidOut(uid)) return;
    Class evc = NSClassFromString(@"FBWorkspaceEvent");
    id queue = BPX_Obj0(self, "eventQueue");
    if (!evc || !queue) return;
    __weak id weakSelf = self;
    void (^handler)(void) = ^{
        id ws = weakSelf;
        if (!ws) return;
        id txn = BPX_Obj1(ws, "_selectTransactionForAppEntityRemoved:", entity);
        BPX_SetObj1(ws, "setCurrentTransaction:", txn);
    };
    id ev = BPY_SEND(id, (id, id), (id)evc, "eventWithName:handler:", [NSString stringWithFormat:@"ApplicationEntity was removed = %@", uid], handler);
    BPX_SetObj1(queue, "executeOrPrependEvent:", ev);
    BPY_LOG(@"[y1] app entity %@ removed but still laid out on a display: app exited transaction queued", uid);
}
// 16.0 -_applicationEntityWasRemovedFromAppSwitcher: (0x1c5f02f58, main display only)
static void Y1_WasRemoved(id self, SEL _cmd, id entity) {
    if (Y1_ON("y1_appremoved")) { Y1_Cleanup(self, _cmd, entity); return; }
    if (gY1OrigWasRemoved) ((void (*)(id, SEL, id))gY1OrigWasRemoved)(self, _cmd, entity);
}
// 16.2 -_destroyApplicationSceneEntity: 0x1c737708c: scene already gone and no destroy action possible -> cleanup
static void Y1_Destroy(id self, SEL _cmd, id entity) {
    BOOL cleanup = NO;
    if (Y1_ON("y1_appremoved")) {
        NSString *uid = BPX_Obj0(entity, "uniqueIdentifier");
        if (uid) {
            Class fbsm = NSClassFromString(@"FBSceneManager");
            id sm = fbsm ? BPX_Obj0((id)fbsm, "sharedInstance") : nil;
            if (!BPX_Obj1(sm, "sceneWithIdentifier:", uid)) {
                id app = BPX_Obj0(BPX_Obj0(entity, "sceneHandle"), "application");
                Class sh = NSClassFromString(@"SBApplicationSceneHandle");
                id pid = (app && sh) ? BPY_SEND(id, (id, id), (id)sh, "lookupOrCreatePersistenceIDFromApplication:sceneID:", app, uid) : nil;
                BOOL running = BPX_Bool0(BPX_Obj0(app, "processState"), "isRunning");
                cleanup = !(pid && running);
            }
        }
    }
    if (gY1OrigDestroy) ((void (*)(id, SEL, id))gY1OrigDestroy)(self, _cmd, entity);
    if (cleanup) Y1_Cleanup(self, NULL, entity);
}

// ---------------------------------------------------------------------------------------------- _selectTransactionForAppEntityRemoved: (16.2 0x1c7375c68)
static id Y1_Select(id self, SEL _cmd, id entity) {
    if (!Y1_ON("y1_appremoved")) return gY1OrigSelect ? ((id (*)(id, SEL, id))gY1OrigSelect)(self, _cmd, entity) : nil;
    id lockOut = BPX_Obj0(BPX_App(), "lockOutController");
    if (BPX_Bool0(lockOut, "isLockedOut")) return BPY_SEND(id, (id, BOOL, BOOL, id), self, "_selectTransactionForReturningToTheLockScreenFromApp:animated:forceToBuddy:withResult:", entity, NO, NO, nil);
    id settings = BPX_Obj0(BPX_Obj0(BPX_Obj0(entity, "sceneHandle"), "sceneIfExists"), "settings");
    id ident = BPX_Obj0(settings, "sb_displayIdentityForSceneManagers");
    id wsm = BPX_WindowSceneManager();
    id ws = BPY_SceneForIdentity(ident) ?: BPX_Obj0(wsm, "embeddedDisplayWindowScene");
    Class cpc = NSClassFromString(@"SBMainWorkspaceLayoutStateContingencyPlan");
    id plan = cpc ? [[cpc alloc] init] : nil;
    id ctx = BPY_SEND(id, (id, id), plan, "transitionContextForLayoutContext:failedEntities:", BPX_Obj0(ws, "switcherController"), [NSSet setWithObject:entity]);
    if (!ctx) return nil;
    BPX_SetBool1(ctx, "setAnimationDisabled:", YES);
    id req = BPY_SEND(id, (unsigned long long, id), self, "createRequestWithOptions:displayConfiguration:", 0ULL, BPX_Obj0(ws, "_fbsDisplayConfiguration"));
    BPX_SetObj1(req, "setApplicationContext:", ctx);
    Class tc = NSClassFromString(@"SBAppExitedWorkspaceTransaction");
    id txn = tc ? BPY_SEND(id, (id), [tc alloc], "initWithTransitionRequest:", req) : nil;
    BPY_LOG(@"[y1] app exited transaction for %@ on window scene %@ (display %@)", BPX_Obj0(entity, "uniqueIdentifier"), ws, ident);
    return txn;   // 16.2 returns the new transaction (+1 from alloc: ARC hands it over autoreleased, the caller expects +0)
}

// ---------------------------------------------------------------------------------------------- scene user interface style for every display
static void Y1_Modify(id self, SEL _cmd, id settings, id ctx, id entity) {
    if (gY1OrigModify) ((void (*)(id, SEL, id, id, id))gY1OrigModify)(self, _cmd, settings, ctx, entity);
    if (!Y1_ON("y1_scenestyle")) return;
    id ident = BPX_Obj0(settings, "displayIdentity");
    if (!ident || BPX_Bool0(ident, "isMainDisplay")) return;               // the main display already got it from the 16.0 body
    if (!BPY_Responds(settings, "setUserInterfaceStyle:")) return;
    id app = BPX_Obj0(self, "application");
    long long style = BPX_LL0(BPX_Obj0(app, "info"), "supportedUserInterfaceStyle");
    if (style == 0) {
        Class arb = NSClassFromString(@"UIUserInterfaceStyleArbiter");
        style = BPX_LL0(arb ? BPX_Obj0((id)arb, "sharedInstance") : nil, "currentStyle");
    }
    BPY_SEND(void, (long long), settings, "setUserInterfaceStyle:", style);
    BPY_LOG(@"[y1] scene settings on display %@: userInterfaceStyle %lld", ident, style);
}

// ---------------------------------------------------------------------------------------------- UIDestroySceneAction for scenes of the extended display
static BOOL Y1_ExtAction(id self, SEL _cmd, id action, id scene) {
    if (Y1_ON("y1_extaction") && action && BPX_LL0(action, "UIActionType") == 0x23) {
        Class mc = NSClassFromString(@"SBMainDisplaySceneManager");
        SEL s = sel_registerName("_handleAction:forScene:");
        Method m = mc ? class_getInstanceMethod(mc, s) : NULL;
        if (m) {
            BPY_LOG(@"[y1] UIDestroySceneAction of %@ handled by the base-class path (extended display)", BPX_Obj0(scene, "identifier"));
            return ((BOOL (*)(id, SEL, id, id))method_getImplementation(m))(self, _cmd, action, scene);
        }
    }
    return gY1OrigExtAction ? ((BOOL (*)(id, SEL, id, id))gY1OrigExtAction)(self, _cmd, action, scene) : NO;
}

// ---------------------------------------------------------------------------------------------- takeScene:fromSceneManager:
static void Y1_Take(id self, SEL _cmd, id scene, id other) {
    if (gY1OrigTake) ((void (*)(id, SEL, id, id))gY1OrigTake)(self, _cmd, scene, other);
    if (!Y1_ON("y1_takescene") || !scene) return;
    id handle = BPX_Obj1(self, "existingSceneHandleForScene:", scene);
    if (!BPY_Responds(handle, "setWantsEnhancedWindowingEnabled:") || ![handle isKindOfClass:NSClassFromString(@"SBDeviceApplicationSceneHandle")]) return;
    id ws = BPX_Obj0(self, "_windowScene") ?: BPX_Obj0(self, "windowScene");
    id sc = BPX_Obj0(ws, "switcherController");
    if (!ws || !sc) return;
    BOOL chamois = BPX_Bool0(sc, "isChamoisWindowingUIEnabled");
    BPX_SetBool1(handle, "setWantsEnhancedWindowingEnabled:", chamois);
    BPY_LOG(@"[y1] scene %@ taken by %@: wantsEnhancedWindowingEnabled = %d", BPX_Obj0(scene, "identifier"), ws, (int)chamois);
}

__attribute__((constructor)) static void Y1_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class mw = NSClassFromString(@"SBMainWorkspace"), dh = NSClassFromString(@"SBDeviceApplicationSceneHandle");
        Class ext = NSClassFromString(@"SBSystemShellExternalDisplaySceneManager"), sm = NSClassFromString(@"SBSceneManager");
        if (!mw || !dh || !ext || !sm) { BP_Log(@"[y1] NOT installed (class missing)"); return; }
        SEL rm = sel_registerName("_removeApplicationEntitiesFromWorkspace:error:");
        if (class_getInstanceMethod(mw, rm)) gY1OrigRemove = BPX_Replace(mw, "_removeApplicationEntitiesFromWorkspace:error:", (IMP)Y1_RemoveEntities);
        class_addMethod(mw, sel_registerName("_cleanupForRemovedAppEntity:"), (IMP)Y1_Cleanup, "v24@0:8@16");
        gY1OrigWasRemoved = BPX_Replace(mw, "_applicationEntityWasRemovedFromAppSwitcher:", (IMP)Y1_WasRemoved);
        gY1OrigDestroy = BPX_Replace(mw, "_destroyApplicationSceneEntity:", (IMP)Y1_Destroy);
        gY1OrigSelect = BPX_Replace(mw, "_selectTransactionForAppEntityRemoved:", (IMP)Y1_Select);
        gY1OrigModify = BPX_Replace(dh, "_modifyApplicationSceneSettings:fromRequestContext:entity:", (IMP)Y1_Modify);
        gY1OrigExtAction = BPX_Replace(ext, "_handleAction:forScene:", (IMP)Y1_ExtAction);
        gY1OrigTake = BPX_Replace(sm, "takeScene:fromSceneManager:", (IMP)Y1_Take);
        BP_Log(@"[y1] installed: remove %d wasRemoved %d destroy %d select %d modify %d extaction %d take %d (switches y1_appremoved y1_scenestyle y1_extaction y1_takescene)", gY1OrigRemove != NULL,
               gY1OrigWasRemoved != NULL, gY1OrigDestroy != NULL, gY1OrigSelect != NULL, gY1OrigModify != NULL, gY1OrigExtAction != NULL, gY1OrigTake != NULL);
    }
}
#pragma clang diagnostic pop
