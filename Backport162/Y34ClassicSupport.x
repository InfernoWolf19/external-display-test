// Y34ClassicSupport.x : delta sweep pass 4, SBDeviceApplicationSceneView(ClassicSupport) of iPadOS 16.2.  Setup: constructor.  Log prefix "[y34]".
//
//  y34_classicsupport  16.2 changed how a scene view hosts a live (classic) app view: the weak ivar _wrappedHostView of 16.0 became _currentHostView (set for EVERY host view in
//    -_configureSceneLiveHostView:) and a strong _snapshottingInfoAssertion (the scene hosting info of the snapshotting assertion stack, G3.x) sits next to it, the wrapper view is looked up
//    through -_useClassicWrapperView, and the view re-evaluates its containment when the window management style changes.  A 16.0 instance has no room for the two ivars: the 16.2 class
//    is a RUNTIME SUBCLASS "Y34DeviceApplicationSceneView" (Y34Ext.h), +[SBDeviceApplicationSceneView allocWithZone:] allocates it.  Rows ported (16.2 addresses, all recompiled from the
//    machine code, Y34ClassicSupportLift.c, call-trace equal to the original on the modelled environment):
//      -noteApplicationClassicPhoneSceneOrientationPreferenceChangingForUserAction: 0x1c773ecdc  (posts SBClassicPhoneSceneOrientationPreferenceChanged, G3B.x observes it: the 16.0
//                                                                    direct call into the traits participant is gone)
//      -_createClassicWrapperViewIfNecessaryForHostView: 0x1c773ed90   (allocates the Y34ClassicWrapperView of Y34ClassicWrapper.x; no _wrappedHostView store any more)
//      -_configureSceneLiveHostView: 0x1c773ef38, -_invalidateSceneLiveHostView: 0x1c773f00c, -_transitionViewForHostView 0x1c773f080, -_layoutLiveHostView: 0x1c773f0e8,
//      -_windowManagementStyleDidChange: 0x1c773ee88 (new), -didMoveToWindow 0x1c773d7c8 (new), -dealloc 0x1c72dd094
//    plus: -initWithSceneHandle:referenceSize:orientation:hostRequester: of the subclass calls the 16.0 init and registers the 16.2 observer of
//    SBSwitcherControllerWindowManagementStyleDidChangeNotification (16.2 init 0x1c773c654 adds exactly this, the rest of the 16.0 init is identical), the subclass' -.cxx_destruct
//    releases the two ivars, and -[SBSceneView _updateLiveViewContainment] (SpringBoardUI, new in 16.2, 0x1f2ccb588, 26 instructions) is added: re-sends _configureSceneLiveHostView: /
//    _configureSceneLiveSnapshotView: for the current _hostView / _liveSnapshotView.
//    The G3.x hooks of _configureSceneLiveHostView: / _invalidateSceneLiveHostView: / didMoveToWindow (associated object approximation of the same assertion logic) stay for
//    instances that are not the subclass; for the subclass the 16.2 bodies replace them.
//  A piece that cannot be installed (class, symbol, ivar) leaves the 16.0 scene view alone: ANOMALY y34 once.  If an instance of the scene view is not the subclass the 16.0 methods run.
// Needs a device: classic (iPhone-only) app in a Stage Manager window; toggle Stage Manager off / on with the app open (containment re-evaluated), rotate button of a classic phone app.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "Y34Ext.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// objc_storeWeak under a private name: a runtime-added weak ivar is a plain void ** for ARC (no cast to id __autoreleasing * allowed)
extern void *y34_storeWeak(void **location, void *obj) __asm__("_objc_storeWeak");
extern void y34_sv_note(void *self, void *cmd, uint8_t userAction);
extern void *y34_sv_create(void *self, void *cmd, void *host);
extern void y34_sv_configure(void *self, void *cmd, void *host);
extern void y34_sv_invalidate(void *self, void *cmd, void *host);
extern void *y34_sv_transition(void *self, void *cmd);
extern void y34_sv_layout(void *self, void *cmd, void *host);
extern void y34_sv_wms(void *self, void *cmd, void *note);
extern void y34_sv_move(void *self, void *cmd);
extern void y34_sv_dealloc(void *self, void *cmd);
extern const char *y34_classicsupport_preflight(void);

static Class gSvBase, gSvExt;
static Ivar gIvAssertion, gIvCurrentHost;
static IMP gOrigAlloc;

#define Y34_S(o) ((__bridge void *)(o))
static void Y34_SvNote(id self, SEL _cmd, BOOL userAction) { y34_sv_note(Y34_S(self), (void *)_cmd, userAction); }
static id Y34_SvCreate(id self, SEL _cmd, id host) { return (__bridge id)y34_sv_create(Y34_S(self), (void *)_cmd, Y34_S(host)); }
static void Y34_SvConfigure(id self, SEL _cmd, id host) { y34_sv_configure(Y34_S(self), (void *)_cmd, Y34_S(host)); }
static void Y34_SvInvalidate(id self, SEL _cmd, id host) { y34_sv_invalidate(Y34_S(self), (void *)_cmd, Y34_S(host)); }
static id Y34_SvTransition(id self, SEL _cmd) { return (__bridge id)y34_sv_transition(Y34_S(self), (void *)_cmd); }
static void Y34_SvLayout(id self, SEL _cmd, id host) { y34_sv_layout(Y34_S(self), (void *)_cmd, Y34_S(host)); }
static void Y34_SvWms(id self, SEL _cmd, id note) { y34_sv_wms(Y34_S(self), (void *)_cmd, Y34_S(note)); }
static void Y34_SvMove(id self, SEL _cmd) { y34_sv_move(Y34_S(self), (void *)_cmd); }
static void Y34_SvDealloc(id self, SEL _cmd) { y34_sv_dealloc(Y34_S(self), (void *)_cmd); }
static void Y34_SvDestruct(id self, SEL _cmd) {
    void **w = Y34_IvarSlot(self, gIvCurrentHost);
    y34_storeWeak(w, NULL);                           // objc_destroyWeak: unregisters the weak slot
    Y34_ObjRelease(self, gIvAssertion);
}

// the 16.0 init of the base class, then the 16.2 observer of the window management style (see the header)
typedef void *(*Y34SvInitFn)(struct objc_super *, SEL, id, CGSize, long long, id);
__attribute__((ns_returns_retained)) static id Y34_SvInit(id __attribute__((ns_consumed)) self, SEL _cmd, id handle, CGSize size, long long orientation, id requester) {
    void *raw = (__bridge_retained void *)self;
    struct objc_super sup = { (__bridge id)raw, gSvBase };
    void *r = ((Y34SvInitFn)objc_msgSendSuper)(&sup, _cmd, handle, size, orientation, requester);
    id me = (__bridge_transfer id)r;
    if (me) [[NSNotificationCenter defaultCenter] addObserver:me selector:sel_registerName("_windowManagementStyleDidChange:") name:@"SBSwitcherControllerWindowManagementStyleDidChangeNotification" object:nil];
    return me;
}

static id Y34_SvAlloc(id self, SEL _cmd, void *zone) {
    Class use = (self == (id)gSvBase) ? gSvExt : (Class)self;
    return ((id (*)(id, SEL, void *))gOrigAlloc)((id)use, _cmd, zone);
}

// -[SBSceneView _updateLiveViewContainment] 16.2 0x1f2ccb588 (SpringBoardUI)
static void Y34_UpdateLiveViewContainment(id self, SEL _cmd) {
    Class sv = NSClassFromString(@"SBSceneView");
    id host = BP_ObjIvar(self, BP_IvarLookup(sv, "_hostView"));
    if (host) BPY_SEND(void, (id), self, "_configureSceneLiveHostView:", host);
    id snap = BP_ObjIvar(self, BP_IvarLookup(sv, "_liveSnapshotView"));
    if (snap) BPY_SEND(void, (id), self, "_configureSceneLiveSnapshotView:", snap);
}

__attribute__((constructor)) static void Y34Support_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y34_classicsupport")) return;
        gSvBase = NSClassFromString(@"SBDeviceApplicationSceneView");
        Class sceneView = NSClassFromString(@"SBSceneView");
        SEL initSel = sel_registerName("initWithSceneHandle:referenceSize:orientation:hostRequester:");
        if (!gSvBase || !sceneView || !class_getInstanceMethod(gSvBase, initSel) || !BP_IvarLookup(sceneView, "_hostView") || !BP_IvarLookup(sceneView, "_liveSnapshotView")) {
            BP_Anomaly("y34", @"[y34] y34_classicsupport NOT installed: SBDeviceApplicationSceneView %p SBSceneView %p, init selector %p: the 16.0 scene view stays",
                       (__bridge void *)gSvBase, (__bridge void *)sceneView, gSvBase ? (void *)class_getInstanceMethod(gSvBase, initSel) : NULL);
            return;
        }
        Class handle = NSClassFromString(@"SBDeviceApplicationSceneHandle");
        if (!handle || !class_getInstanceMethod(handle, sel_registerName("_sceneHostingInfoForSnapshottingAssertionWithView:"))) {
            BP_Anomaly("y34", @"[y34] y34_classicsupport NOT installed: SBDeviceApplicationSceneHandle (%p) has no -_sceneHostingInfoForSnapshottingAssertionWithView: (the 16.2 snapshotting assertion stack of G3.x, switch g3snapshot)", (__bridge void *)handle);
            return;
        }
        static const Y34IvarSpec ivars[] = { { "_snapshottingInfoAssertion", sizeof(void *), 3, "@" }, { "_currentHostView", sizeof(void *), 3, "@" } };
        gSvExt = Y34_MakeExt("SBDeviceApplicationSceneView", "Y34DeviceApplicationSceneView", ivars, 2);
        if (!gSvExt) return;
        gIvAssertion = class_getInstanceVariable(gSvExt, "_snapshottingInfoAssertion");
        gIvCurrentHost = class_getInstanceVariable(gSvExt, "_currentHostView");
        if (!gIvAssertion || !gIvCurrentHost) { BP_Anomaly("y34", @"[y34] y34_classicsupport NOT installed: the subclass ivars are missing"); return; }
        // the recompiled bodies find the two ivars by name through the subclass: registered before the preflight (which resolves them); a failed preflight leaves it unused
        lift_register_ext("SBDeviceApplicationSceneView", (__bridge void *)gSvExt);
        const char *miss = y34_classicsupport_preflight();
        if (miss) { BP_Anomaly("y34", @"[y34] y34_classicsupport NOT installed: unresolved names of the recompiled 16.2 bodies: %s: the 16.0 scene view stays", miss); return; }
        // the new 16.2 method of the base SBSceneView
        if (!class_getInstanceMethod(sceneView, sel_registerName("_updateLiveViewContainment")))
            class_addMethod(sceneView, sel_registerName("_updateLiveViewContainment"), (IMP)Y34_UpdateLiveViewContainment, "v@:");
        class_addMethod(gSvExt, initSel, (IMP)Y34_SvInit, "@@:@{CGSize=dd}q@");
        class_addMethod(gSvExt, sel_registerName("dealloc"), (IMP)Y34_SvDealloc, "v@:");
        class_addMethod(gSvExt, sel_registerName(".cxx_destruct"), (IMP)Y34_SvDestruct, "v@:");
        class_addMethod(gSvExt, sel_registerName("noteApplicationClassicPhoneSceneOrientationPreferenceChangingForUserAction:"), (IMP)Y34_SvNote, "v@:B");
        class_addMethod(gSvExt, sel_registerName("_createClassicWrapperViewIfNecessaryForHostView:"), (IMP)Y34_SvCreate, "@@:@");
        class_addMethod(gSvExt, sel_registerName("_configureSceneLiveHostView:"), (IMP)Y34_SvConfigure, "v@:@");
        class_addMethod(gSvExt, sel_registerName("_invalidateSceneLiveHostView:"), (IMP)Y34_SvInvalidate, "v@:@");
        class_addMethod(gSvExt, sel_registerName("_transitionViewForHostView"), (IMP)Y34_SvTransition, "@@:");
        class_addMethod(gSvExt, sel_registerName("_layoutLiveHostView:"), (IMP)Y34_SvLayout, "v@:@");
        class_addMethod(gSvExt, sel_registerName("_windowManagementStyleDidChange:"), (IMP)Y34_SvWms, "v@:@");
        class_addMethod(gSvExt, sel_registerName("didMoveToWindow"), (IMP)Y34_SvMove, "v@:");
        // allocation of the base class gives the subclass (the instance needs the room for the two ivars)
        Class meta = object_getClass((id)gSvBase);
        Method am = class_getClassMethod(gSvBase, @selector(allocWithZone:));
        gOrigAlloc = am ? method_getImplementation(am) : NULL;
        if (!gOrigAlloc) { BP_Anomaly("y34", @"[y34] y34_classicsupport: +allocWithZone: not found, the subclass is never allocated"); return; }
        class_replaceMethod(meta, @selector(allocWithZone:), (IMP)Y34_SvAlloc, method_getTypeEncoding(am));
        BP_Log(@"[y34] installed y34_classicsupport (runtime subclass Y34DeviceApplicationSceneView)");
    }
}
#pragma clang diagnostic pop
