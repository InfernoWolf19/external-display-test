// Y10Pip.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): Picture in Picture under Stage Manager / on the second display.  Setup: constructor.  Log prefix "[y10]".
//
//  y10_portallevel  -[SBDisplayPortalManager _createPortalForSourceView:sourceWindowScene:targetWindowScene:traitsRole:] 16.2 0x1c765172c (16.0 0x1c61c2bd8) gives the portal window the window
//                   level of the source view's window (0x1c7651868..0x1c7651888).  16.0 leaves the new UIWindow at the default level, so the portal of a PiP window that is being dragged
//                   (-[SBPIPController containerViewControllerDidBeginInteraction:] -> createPortalsForSourceView:usingTraitsRole:) shows on the other display below the windows of that display.
//                   Ported: wrapper that sets the level on the returned window.
//  y10_autopip      +[SBAutoPIPWorkspaceTransaction shouldAutoPIPEnteringBackgroundForRequest:foundEntity:tetheringMode:transitionStyle:reason:] 16.2 0x1c76bfe88 (16.0 0x1c622d8a0): when the switcher of the
//                   request's display is in Stage Manager the entity that goes to PiP is the FIRST of ALL the previous entities of the transition that is an application scene entity and passes
//                   +_doesPegasusAllowEntityToAutoPIP:pipCoordinator: (0x1c76c0460 = -[pipCoordinator shouldStartPictureInPictureForApplicationWithProcessIdentifierEnteringBackground:scenePersistenceIdentifier:
//                   pipContentType:0]); otherwise (full screen) the previous entity of layout role 1, or role 2 in a split.  16.0 only ever looked at roles 1 / 2, so a video playing in another window of
//                   the stage did not start PiP when the stage was left.  The rest of the 16.0 body (analogous entity still present, Screen Time, removal context, source 0x3e, shouldStart..., tethering,
//                   transition style) is the same sequence as 16.2's.  Ported: in Stage Manager the 16.2 candidate is computed and handed to the 16.0 body by answering
//                   -[SBWorkspaceApplicationSceneTransitionContext previousApplicationSceneEntityForLayoutRole:] (role 1 -> candidate, other roles -> nil) for that one call.
//                   Not ported: the PiP content type that 16.2 passes as 0 to shouldStart... / tetheringMode... (16.0 reads activation setting 53); only matters for the rare content types.
//  y10_morphframe   -[SBFullScreenToHomePIPSwitcherModifier frameForIndex:] 16.2 0x1c77df1ac (16.0 0x1c633b7e0): while the morph to PiP applies, the frame is a rectangle of the size of the SUPER
//                   class' frame for the index (the window's own frame) centred on -morphToPIPTargetCenter; 16.0 used the size of the whole container bounds.  Identical for a full screen app; with Stage
//                   Manager a window that goes to PiP shrinks from its own size instead of jumping to full screen size first.  Ported: wrapper.
//  y10_stashscene   SBPIPEnvironmentDependentOverrideAssertion (the PiP stash assertion) 16.2 has _windowScene (ivar 0x38), -initWithReason:identifier:windowScene:invalidationBlock: 0x1c77d2240 and
//                   -_layoutCoordinator 0x1c77d23d8 = [[windowScene sceneManager] _layoutStateTransitionCoordinator]; the allowed environment mode is taken from that scene's layout state.  16.0 observes
//                   the MAIN display's layout transitions and takes the first allowed mode from the active display; a stash assertion acquired for the PiP of the other display
//                   (-[SBPIPController _acquireStashAssertionForWindowScene:withReason:identifier:customAllowedEnvironmentModes:] 0x1c792a9dc) was therefore dropped by main display transitions.
//                   Ported: the scene is remembered (thread local around the acquire, associated object on the assertion before its init body runs) and -_layoutCoordinator answers its coordinator;
//                   the initial mode is read with the scene's switcher controller as the active one (Y3_PushActive).
// Needs a device with the monitor in Stage Manager: (1) play a video, make it PiP, drag the PiP window across to the other display: the live copy stays on top there.  (2) with a video in one of
// two stage windows, go home: PiP starts.  (3) a window going to PiP shrinks from its own frame.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y10Rect;      // CGRect (HFA, d0..d3)
typedef struct { double x, y; } Y10Point;           // CGPoint (HFA, d0..d1)

@interface BPY10WeakBox : NSObject { @public __weak id obj; }
@end
@implementation BPY10WeakBox
@end

static const void *kY10Scene = &kY10Scene;
static __thread __unsafe_unretained id tY10StashScene;          // window scene of the stash assertion being acquired
static __thread __unsafe_unretained id tY10Ctx;                 // transition context whose previous entities are overridden
static __thread __unsafe_unretained id tY10Cand;                // the Stage Manager candidate entity (nil = none)
static __thread BOOL tY10Armed;
static IMP gY10OrigPortal, gY10OrigAuto, gY10OrigPrevEntity, gY10OrigFrame, gY10OrigAcquire, gY10OrigInit, gY10OrigCoord;
static IMP gY10SuperFrame;

// -[SBDisplayPortalManager _createPortalForSourceView:sourceWindowScene:targetWindowScene:traitsRole:]
static id Y10_Portal(id self, SEL _cmd, id view, id srcScene, id dstScene, id role) {
    id win = gY10OrigPortal ? ((id (*)(id, SEL, id, id, id, id))gY10OrigPortal)(self, _cmd, view, srcScene, dstScene, role) : nil;
    if (win && view && BP_OnName("y10_portallevel") && BPY_Responds(win, "setWindowLevel:")) {
        id srcWin = BPX_Obj0(view, "window");
        if (srcWin) {
            double lvl = ((double (*)(id, SEL))objc_msgSend)(srcWin, sel_registerName("windowLevel"));
            BPY_SEND(void, (double), win, "setWindowLevel:", lvl);
            BPY_LOG(@"[y10] portal window of %@ gets the source window level %.1f", view, lvl);
        }
    }
    return win;
}

// +[SBAutoPIPWorkspaceTransaction shouldAutoPIPEnteringBackgroundForRequest:foundEntity:tetheringMode:transitionStyle:reason:]
static BOOL Y10_AutoPIP(id self, SEL _cmd, id req, id *outEntity, long long *outMode, long long *outStyle, long long reason) {
    id ctx = nil, cand = nil;
    BOOL arm = NO;
    if (req && BP_OnName("y10_autopip") && BPY_Responds(req, "applicationContext")) {
        id lock = BPX_Obj0((id)NSClassFromString(@"SBLockScreenManager"), "sharedInstance");
        if (!(lock && BPX_Bool0(lock, "isUILocked"))) {
            id scene = BPY_SceneForIdentity(BPX_Obj0(req, "displayIdentity"));
            id sc = BPX_Obj0(scene, "switcherController");
            if (sc && BPX_Bool0(sc, "isChamoisWindowingUIEnabled")) {
                ctx = BPX_Obj0(req, "applicationContext");
                id pip = BPX_Obj0(BPX_Obj0(req, "workspace"), "pipCoordinator");
                for (id e in BPX_Obj0(ctx, "previousEntities")) {
                    if (!BPX_Bool0(e, "isApplicationSceneEntity")) continue;
                    id app = BPX_Obj0(e, "application");
                    int pid = (int)BPX_LL0(BPX_Obj0(app, "processState"), "pid");
                    id ident = BPX_Obj0(BPX_Obj0(e, "sceneHandle"), "persistenceIdentifier");
                    if (BPY_SEND(BOOL, (int, id, long long), pip, "shouldStartPictureInPictureForApplicationWithProcessIdentifierEnteringBackground:scenePersistenceIdentifier:pipContentType:", pid, ident, 0LL)) { cand = e; break; }
                }
                arm = ctx != nil;
            }
        }
    }
    id sCtx = tY10Ctx, sCand = tY10Cand; BOOL sArm = tY10Armed;
    tY10Ctx = arm ? ctx : nil; tY10Cand = arm ? cand : nil; tY10Armed = arm;
    if (arm) BPY_LOG(@"[y10] auto PiP, Stage Manager: candidate %@ among %lu previous entities", cand, (unsigned long)[BPX_Obj0(ctx, "previousEntities") count]);
    BOOL r = gY10OrigAuto ? ((BOOL (*)(id, SEL, id, id *, long long *, long long *, long long))gY10OrigAuto)(self, _cmd, req, outEntity, outMode, outStyle, reason) : NO;
    tY10Ctx = sCtx; tY10Cand = sCand; tY10Armed = sArm;
    return r;
}
// -[SBWorkspaceApplicationSceneTransitionContext previousApplicationSceneEntityForLayoutRole:]
static id Y10_PrevEntity(id self, SEL _cmd, long long role) {
    if (tY10Armed && tY10Ctx == self) return role == 1 ? tY10Cand : nil;
    return gY10OrigPrevEntity ? ((id (*)(id, SEL, long long))gY10OrigPrevEntity)(self, _cmd, role) : nil;
}

// -[SBFullScreenToHomePIPSwitcherModifier frameForIndex:]
static Y10Rect Y10_Frame(id self, SEL _cmd, unsigned long long i) {
    Y10Rect z = {0, 0, 0, 0};
    if (BP_OnName("y10_morphframe") && gY10SuperFrame && BPY_Responds(self, "_shouldApplyMorphToPipToIndex:") && BPY_SEND(BOOL, (unsigned long long), self, "_shouldApplyMorphToPipToIndex:", i)) {
        Y10Rect sf = ((Y10Rect (*)(id, SEL, unsigned long long))gY10SuperFrame)(self, _cmd, i);
        Y10Point c = ((Y10Point (*)(id, SEL))objc_msgSend)(self, sel_registerName("morphToPIPTargetCenter"));
        Y10Rect r = { c.x - sf.w / 2.0, c.y - sf.h / 2.0, sf.w, sf.h };         // _SBUnintegralizedRectCenteredAboutPoint
        return r;
    }
    return gY10OrigFrame ? ((Y10Rect (*)(id, SEL, unsigned long long))gY10OrigFrame)(self, _cmd, i) : z;
}

// -[SBPIPController _acquireStashAssertionForWindowScene:withReason:identifier:customAllowedEnvironmentModes:]
static id Y10_Acquire(id self, SEL _cmd, id scene, long long reason, id ident, id modes) {
    id saved = tY10StashScene;
    tY10StashScene = BP_OnName("y10_stashscene") ? scene : nil;
    id r = gY10OrigAcquire ? ((id (*)(id, SEL, id, long long, id, id))gY10OrigAcquire)(self, _cmd, scene, reason, ident, modes) : nil;
    tY10StashScene = saved;
    return r;
}
// -[SBPIPEnvironmentDependentOverrideAssertion initWithReason:identifier:invalidationBlock:]
static id Y10_Init(id self, SEL _cmd, long long reason, id ident, id block) {
    id scene = tY10StashScene;
    void *prev = NULL;
    BOOL pushed = NO;
    if (self && scene && BPX_Bool0(scene, "isExternalDisplayWindowScene")) {
        BPY10WeakBox *b = [BPY10WeakBox new];
        b->obj = scene;
        objc_setAssociatedObject(self, kY10Scene, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        id sc = BPX_Obj0(scene, "switcherController");
        if (sc) { prev = Y3_PushActive(sc); pushed = YES; }
        BPY_LOG(@"[y10] stash assertion %p is bound to the layout transitions of scene %@", (__bridge void *)self, scene);
    }
    id r = gY10OrigInit ? ((id (*)(id, SEL, long long, id, id))gY10OrigInit)(self, _cmd, reason, ident, block) : nil;
    if (pushed) Y3_PopActive(prev);
    return r;
}
// -[SBPIPEnvironmentDependentOverrideAssertion _layoutCoordinator]
static id Y10_Coord(id self, SEL _cmd) {
    BPY10WeakBox *b = objc_getAssociatedObject(self, kY10Scene);
    id scene = b ? b->obj : nil;
    if (scene && BP_OnName("y10_stashscene")) {
        id c = BPX_Obj0(BPX_Obj0(scene, "sceneManager"), "_layoutStateTransitionCoordinator");
        if (c) return c;
    }
    return gY10OrigCoord ? ((id (*)(id, SEL))gY10OrigCoord)(self, _cmd) : nil;
}

__attribute__((constructor)) static void Y10_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class pm = NSClassFromString(@"SBDisplayPortalManager");
        if (pm && class_getInstanceMethod(pm, sel_registerName("_createPortalForSourceView:sourceWindowScene:targetWindowScene:traitsRole:"))) {
            gY10OrigPortal = BPX_Replace(pm, "_createPortalForSourceView:sourceWindowScene:targetWindowScene:traitsRole:", (IMP)Y10_Portal); n++;
        }
        Class ap = NSClassFromString(@"SBAutoPIPWorkspaceTransaction"), cx = NSClassFromString(@"SBWorkspaceApplicationSceneTransitionContext");
        if (ap && cx && class_getClassMethod(ap, sel_registerName("shouldAutoPIPEnteringBackgroundForRequest:foundEntity:tetheringMode:transitionStyle:reason:")) &&
            class_getInstanceMethod(cx, sel_registerName("previousApplicationSceneEntityForLayoutRole:"))) {
            gY10OrigAuto = BPX_Replace(object_getClass((id)ap), "shouldAutoPIPEnteringBackgroundForRequest:foundEntity:tetheringMode:transitionStyle:reason:", (IMP)Y10_AutoPIP);
            gY10OrigPrevEntity = BPX_Replace(cx, "previousApplicationSceneEntityForLayoutRole:", (IMP)Y10_PrevEntity); n++;
        }
        Class mo = NSClassFromString(@"SBFullScreenToHomePIPSwitcherModifier");
        if (mo && class_getInstanceMethod(mo, sel_registerName("frameForIndex:")) && class_getInstanceMethod(mo, sel_registerName("_shouldApplyMorphToPipToIndex:")) &&
            class_getInstanceMethod(mo, sel_registerName("morphToPIPTargetCenter"))) {
            Method sm = class_getInstanceMethod(class_getSuperclass(mo), sel_registerName("frameForIndex:"));
            gY10SuperFrame = sm ? method_getImplementation(sm) : NULL;
            if (gY10SuperFrame) { gY10OrigFrame = BPX_Replace(mo, "frameForIndex:", (IMP)Y10_Frame); n++; }
        }
        Class pc = NSClassFromString(@"SBPIPController"), ea = NSClassFromString(@"SBPIPEnvironmentDependentOverrideAssertion");
        if (pc && ea && class_getInstanceMethod(pc, sel_registerName("_acquireStashAssertionForWindowScene:withReason:identifier:customAllowedEnvironmentModes:")) &&
            class_getInstanceMethod(ea, sel_registerName("initWithReason:identifier:invalidationBlock:")) && class_getInstanceMethod(ea, sel_registerName("_layoutCoordinator"))) {
            gY10OrigAcquire = BPX_Replace(pc, "_acquireStashAssertionForWindowScene:withReason:identifier:customAllowedEnvironmentModes:", (IMP)Y10_Acquire);
            gY10OrigInit = BPX_Replace(ea, "initWithReason:identifier:invalidationBlock:", (IMP)Y10_Init);
            gY10OrigCoord = BPX_Replace(ea, "_layoutCoordinator", (IMP)Y10_Coord); n++;
        }
        BP_Log(@"[y10] installed %d of 4 PiP groups (switches y10_portallevel, y10_autopip, y10_morphframe, y10_stashscene)", n);
    }
}
#pragma clang diagnostic pop
