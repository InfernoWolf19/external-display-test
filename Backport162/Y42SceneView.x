// Y42SceneView.x : delta sweep pass 4 (block capable recompiler), the 16.2 init chain of the scene views.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_sceneview  16.2 gave the scene views a new designated init that carries the content AND the container orientation:
//     -[SBDeviceApplicationSceneView initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:]   0x1c773c654 (284 instructions, three block invokes 0x1c773caf4 / 0x1c773cc40 / 0x1c773ccb8)
//     -[SBApplicationSceneView initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:]          0x1c7962f44
//     SpringBoardUI -[SBSceneView initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:]      0x1f2cca72c (16.0: ...orientation:hostRequester: 0x1f1188810)
//     SpringBoardUI -[SBSceneView invalidate] 0x1f2cc5f28 (16.0 0x1f11896b4), -sceneHandle:didUpdateContentState: 0x1f2ccb3e0 (16.0 0x1f118e814), -_configureLiveHostView 0x1f2ccb470 (16.0 name _configureHostView)
//   NONE of it is re-typed: Y42SceneViewLift.c is the 16.2 machine code recompiled by tools/a2c/a2c.py (stack blocks with arm64e pointer signing, the mutable static request counter of the SpringBoardUI image
//   as a zero initialised cell, the os_log call sites with our image).  The scene view layouts are the same in both builds (SBSceneView, SBApplicationSceneView) or by name (SBDeviceApplicationSceneView, whose two new
//   ivars live in the runtime subclass of Y34ClassicSupport.x); the instances are allocated by the callers.  The three new inits are ADDED (the 16.0 callers keep the 16.0 init selector and its chain, Y34ClassicSupport.x);
//   -invalidate and -sceneHandle:didUpdateContentState: of SBSceneView replace the 16.0 methods (16.0 body as fallback while the switch is off); -_configureLiveHostView is a new method.
//   Verified with tools/a2c/tests/tracecmp.py on 16 seeds per body (every message / C call, every retain / release / autorelease / claim / storeStrong in order, PAC operations, block images, memory).
//   Class identity: every CLS() of the recompiled bodies is the REAL class (tools/a2c/tests/clsuse.py lists them: super receivers SBSceneView / SBApplicationSceneView / SBDeviceApplicationSceneView, allocations of
//   SBApplicationSceneViewStatusBarDescriptor / the placeholder provider / SBApplicationSceneBackgroundView / SBSceneHandleBlockObserver, class method receivers, the SBDeviceApplicationSceneHandle type check).
//   The Y34 +allocWithZone: swap decides which allocations become the runtime subclass; the 16.2 init chain works on both.
//   ON-INSTALL SELF TEST (10 s after launch, main queue): one SBDeviceApplicationSceneView is allocated, initWithFrame:, checked (-class answers the 16.0 class, the instance is of the runtime subclass when
//   Y34ClassicSupport is active, the extra ivars read zero) and released; the result (including that the instance was deallocated) is logged as ANOMALY y42-sceneview-selftest.  The path of the earlier crash
//   (the dealloc of the recompiled class chain) is exactly what it exercises.
//   What can break on a device: the stack blocks (arm64e signing), the observers registered by the init (SBSceneHandleBlockObserver blocks), the 16.2 invalidate on 16.0 created views.
//   The 16.2 -_windowManagementStyleDidChange: observer of the device scene view needs Y34ClassicSupport.x: without it the 16.0 init selector is used (ANOMALY y42, once).
// Switch y42_sceneview (kill file Backport162.off.y42_sceneview).  Installed only on build 20A8372; ANOMALY y42-sceneview (always on) names the build.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern uint64_t y42_sbs_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t content, uint64_t container, uint64_t requester);
extern void y42_sbs_invalidate(uint64_t self, uint64_t cmd);
extern void y42_sbs_state(uint64_t self, uint64_t cmd, uint64_t handle, uint64_t state);
extern void y42_sbs_live(uint64_t self, uint64_t cmd);
extern uint64_t y42_asv_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t content, uint64_t container, uint64_t requester);
extern uint64_t y42_dsv_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t content, uint64_t container, uint64_t requester);
extern const char *y42_sceneview_preflight(void);
extern char kBPG3BContainerOri;                       // G3B.x

static IMP gOrigInvalidate, gOrigState;

#define Y42_P(o) ((uint64_t)(uintptr_t)(__bridge void *)(o))
#define Y42_C(c) ((uint64_t)(uintptr_t)(void *)(c))

static void Y42_SbsInvalidate(id self, SEL _cmd) {
    if (!BP_OnName("y42_sceneview")) { ((void (*)(id, SEL))gOrigInvalidate)(self, _cmd); return; }
    y42_sbs_invalidate(Y42_P(self), Y42_C(_cmd));
}
static void Y42_SbsState(id self, SEL _cmd, id handle, long long state) {
    if (!BP_OnName("y42_sceneview")) { ((void (*)(id, SEL, id, long long))gOrigState)(self, _cmd, handle, state); return; }
    y42_sbs_state(Y42_P(self), Y42_C(_cmd), Y42_P(handle), (uint64_t)state);
}
static void Y42_SbsLive(id self, SEL _cmd) { y42_sbs_live(Y42_P(self), Y42_C(_cmd)); }

// the device scene view init registers -_windowManagementStyleDidChange: as observer selector (Y34ClassicSupport.x adds it): without it the 16.0 init selector builds the view
typedef void *(*Y42DsvOldInit)(void *, SEL, id, CGSize, long long, id);
__attribute__((ns_returns_retained)) static id Y42_DsvInit(id __attribute__((ns_consumed)) self, SEL _cmd, id handle, CGSize size, long long content, long long container, id requester) {
    if (BP_OnName("y42_sceneview") && class_getInstanceMethod(object_getClass(self), sel_registerName("_windowManagementStyleDidChange:"))) {
        void *raw1 = (__bridge_retained void *)self;       // the recompiled init consumes this +1 (like every init) and returns +1
        uint64_t r = y42_dsv_init((uint64_t)(uintptr_t)raw1, Y42_C(_cmd), Y42_P(handle), size.width, size.height, (uint64_t)content, (uint64_t)container, Y42_P(requester));
        return (__bridge_transfer id)(void *)(uintptr_t)r;
    }
    static BOOL once;
    if (!once) { once = YES; BP_Anomaly("y42", @"[y42] y42_sceneview: no -_windowManagementStyleDidChange: on %s (Y34ClassicSupport.x): the 16.0 init selector builds the device scene view", class_getName(object_getClass(self))); }
    void *raw = (__bridge_retained void *)self;
    void *r = ((Y42DsvOldInit)objc_msgSend)(raw, sel_registerName("initWithSceneHandle:referenceSize:orientation:hostRequester:"), handle, size, content, requester);
    id me = (__bridge_transfer id)r;
    if (me) objc_setAssociatedObject(me, &kBPG3BContainerOri, @(container), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return me;
}

static void Y42_SelfTest(void) {
    @autoreleasepool {
        Class base = NSClassFromString(@"SBDeviceApplicationSceneView");
        if (!base) return;
        Class ext = NSClassFromString(@"Y34DeviceApplicationSceneView");
        __weak id weak = nil;
        NSString *res;
        @autoreleasepool {
            id v = ((id (*)(id, SEL))objc_msgSend)((id)base, sel_registerName("alloc"));
            v = ((id (*)(id, SEL, CGRect))objc_msgSend)(v, sel_registerName("initWithFrame:"), CGRectZero);
            if (!v) { BP_Anomaly("y42-sceneview-selftest", @"[y42] self test FAILED: alloc / initWithFrame: of SBDeviceApplicationSceneView answered nil"); return; }
            BOOL classOK = ([v class] == base) && [v isKindOfClass:base];
            BOOL isExt = ext && object_getClass(v) == ext;
            Ivar ia = ext ? class_getInstanceVariable(ext, "_snapshottingInfoAssertion") : NULL, ih = ext ? class_getInstanceVariable(ext, "_currentHostView") : NULL;
            BOOL ivOK = !ext || (!isExt) || (ia && ih && *(void **)((char *)(__bridge void *)v + ivar_getOffset(ia)) == NULL && *(void **)((char *)(__bridge void *)v + ivar_getOffset(ih)) == NULL);
            BOOL responds = [v respondsToSelector:sel_registerName("initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:")];
            res = [NSString stringWithFormat:@"-class answers %s (%@), instance of %s (runtime subclass %@), extra ivars zero %@, 16.2 init selector present %@", class_getName([v class]), classOK ? @"OK" : @"WRONG", class_getName(object_getClass(v)), isExt ? @"yes" : @"no", ivOK ? @"yes" : @"NO", responds ? @"yes" : @"NO"];
            weak = v;
            if (!(classOK && ivOK && responds)) res = [@"FAILED: " stringByAppendingString:res];
        }
        // the instance went out of scope above: the dealloc of the whole recompiled / hand ported chain has run when the weak reference is nil
        BP_Anomaly("y42-sceneview-selftest", @"[y42] self test %@ ; teardown %@ (OS build 20A8372)", res, weak == nil ? @"OK: the view was deallocated" : @"NOT DONE: the view is still alive");
    }
}

__attribute__((constructor)) static void Y42SceneView_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_sceneview")) return;
        Class sbs = NSClassFromString(@"SBSceneView"), asv = NSClassFromString(@"SBApplicationSceneView"), dsv = NSClassFromString(@"SBDeviceApplicationSceneView");
        if (!sbs || !asv || !dsv) { BP_Anomaly("y42", @"[y42] y42_sceneview NOT installed: SBSceneView %p / SBApplicationSceneView %p / SBDeviceApplicationSceneView %p missing", (__bridge void *)sbs, (__bridge void *)asv, (__bridge void *)dsv); return; }
        NSMutableArray *missing = [NSMutableArray array];
        SEL initNew = sel_registerName("initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:");
        SEL invalidate = sel_registerName("invalidate"), state = sel_registerName("sceneHandle:didUpdateContentState:"), live = sel_registerName("_configureLiveHostView");
        if (!class_getInstanceMethod(sbs, invalidate)) [missing addObject:@"-[SBSceneView invalidate]"];
        if (!class_getInstanceMethod(sbs, state)) [missing addObject:@"-[SBSceneView sceneHandle:didUpdateContentState:]"];
        const char *ivn[] = { "_sceneHandle", "_referenceSize", "_orientation", "_requestedDisplayMode", "_effectiveDisplayMode", "_invalidated", "_presenter", "_hostingPriority", "_hostingIdentifier", "_hostView", "_backgroundView" };
        for (size_t k = 0; k < sizeof ivn / sizeof ivn[0]; k++) if (!BP_IvarLookup(sbs, ivn[k])) [missing addObject:[NSString stringWithFormat:@"ivar SBSceneView.%s", ivn[k]]];
        const char *dvn[] = { "_statusBarDescriptor", "_statusBarAlpha", "_grabberSettings", "_medusaSettings", "_sceneHandleObserver" };
        for (size_t k = 0; k < sizeof dvn / sizeof dvn[0]; k++) if (!BP_IvarLookup(dsv, dvn[k])) [missing addObject:[NSString stringWithFormat:@"ivar SBDeviceApplicationSceneView.%s", dvn[k]]];
        const char *miss = y42_sceneview_preflight();
        if (miss) [missing addObject:[NSString stringWithFormat:@"unresolved names of the recompiled bodies: %s", miss]];
        if (missing.count) { BP_Anomaly("y42", @"[y42] y42_sceneview NOT installed: missing %@: the 16.0 scene views stay", [missing componentsJoinedByString:@", "]); return; }
        BOOL ok = YES;
        if (!class_getInstanceMethod(sbs, initNew)) ok = ok && class_addMethod(sbs, initNew, (IMP)y42_sbs_init, "@@:@{CGSize=dd}qq@");
        if (!class_getInstanceMethod(asv, initNew) || class_getInstanceMethod(asv, initNew) == class_getInstanceMethod(sbs, initNew)) ok = ok && class_addMethod(asv, initNew, (IMP)y42_asv_init, "@@:@{CGSize=dd}qq@");
        if (!class_getInstanceMethod(dsv, initNew) || class_getInstanceMethod(dsv, initNew) == class_getInstanceMethod(asv, initNew)) ok = ok && class_addMethod(dsv, initNew, (IMP)Y42_DsvInit, "@@:@{CGSize=dd}qq@");
        if (!class_getInstanceMethod(sbs, live)) ok = ok && class_addMethod(sbs, live, (IMP)Y42_SbsLive, "v@:");
        if (!ok) { BP_Anomaly("y42", @"[y42] y42_sceneview NOT (completely) installed: class_addMethod failed for one of the 16.2 methods"); return; }
        gOrigInvalidate = BPX_Replace(sbs, "invalidate", (IMP)Y42_SbsInvalidate);
        gOrigState = BPX_Replace(sbs, "sceneHandle:didUpdateContentState:", (IMP)Y42_SbsState);
        BP_Log(@"[y42] installed y42_sceneview");
        BP_Anomaly("y42-sceneview", @"[y42] y42_sceneview active (NOT device tested): the 16.2 init chain of SBDeviceApplicationSceneView / SBApplicationSceneView / SBSceneView (content AND container orientation, recompiled, three signed stack blocks), -invalidate, -sceneHandle:didUpdateContentState:, -_configureLiveHostView; OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_sceneview", __DATE__, __TIME__);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (BP_OnName("y42_sceneview")) Y42_SelfTest(); });
    }
}
#pragma clang diagnostic pop
