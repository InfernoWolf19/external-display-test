// Y42SceneVC.x : delta sweep pass 4 (block capable recompiler), SBSceneViewController of iPadOS 16.2: the container orientation.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_scenevc  -[SBSceneViewController initWithSceneHandle:]  16.2 0x1c72e7614 (16.0 0x1c5e7479c): the 16.2 init stores _containerOrientation = 1 next to _contentOrientation = 1 (recompiled and read: the only
//               difference to 16.0 is that one store).  The ivar does not exist in the 16.0 instances (and the subclasses of the controller are 16.0 classes that place their own ivars behind the 16.0 layout), so it
//               is the per object associated object G3B.x already keeps (kBPG3BContainerOri, read by the adapter -containerOrientation): the init wraps the 16.0 init and stores 1 through that key.
//               -[SBSceneViewController viewDidLoad]  16.2 0x1c72e7db8 (16.0 0x1c5e74f34): NOT re-typed, Y42SceneVCLift.c is the 16.2 machine code recompiled (the scene view is created with
//               newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester: of the scene handle, G3B.x; ivars _sceneView / _sceneHandle exist in both layouts); verified with
//               tools/a2c/tests/tracecmp.py (calls and ownership events, 24 seeds).
//   Needs from G3B.x: -contentOrientation / -containerOrientation on SBSceneViewController and the new factory on SBDeviceApplicationSceneHandle (asked at the first use; until they exist the 16.0 viewDidLoad runs, ANOMALY y42).
// Switch y42_scenevc (kill file Backport162.off.y42_scenevc).  Installed only on build 20A8372; ANOMALY y42-scenevc (always on) names the build.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern char kBPG3BContainerOri;                       // G3B.x
extern void y42_svc_viewdidload(uint64_t self, uint64_t cmd);
extern const char *y42_scenevc_preflight(void);

static IMP gOrigInit, gOrigViewDidLoad;

static BOOL Y42_SvcPieces(void) {
    static BOOL ok;
    if (ok) return YES;
    Class vc = NSClassFromString(@"SBSceneViewController");
    Class h = NSClassFromString(@"SBDeviceApplicationSceneHandle");
    NSMutableArray *miss = [NSMutableArray array];
    if (!vc || !class_getInstanceMethod(vc, sel_registerName("contentOrientation"))) [miss addObject:@"-[SBSceneViewController contentOrientation]"];
    if (!vc || !class_getInstanceMethod(vc, sel_registerName("containerOrientation"))) [miss addObject:@"-[SBSceneViewController containerOrientation]"];
    if (!h || !class_getInstanceMethod(h, sel_registerName("newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:"))) [miss addObject:@"-[SBDeviceApplicationSceneHandle newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:]"];
    if (miss.count) { BP_Anomaly("y42", @"[y42] y42_scenevc: missing %@ (G3B.x): the 16.0 viewDidLoad ran", [miss componentsJoinedByString:@", "]); return NO; }
    ok = YES;
    return YES;
}

static void Y42_SvcViewDidLoad(id self, SEL _cmd) {
    if (!BP_OnName("y42_scenevc") || !Y42_SvcPieces()) { ((void (*)(id, SEL))gOrigViewDidLoad)(self, _cmd); return; }
    y42_svc_viewdidload((uint64_t)(uintptr_t)(__bridge void *)self, (uint64_t)(uintptr_t)(void *)_cmd);
}

// 16.0 -initWithSceneHandle:, then the one store 16.2 adds (0x1c72e76a4 .. : _containerOrientation = 1)
typedef void *(*Y42SvcInitFn)(void *, SEL, id);
__attribute__((ns_returns_retained)) static id Y42_SvcInit(id __attribute__((ns_consumed)) self, SEL _cmd, id handle) {
    void *raw = (__bridge_retained void *)self;
    void *r = ((Y42SvcInitFn)gOrigInit)(raw, _cmd, handle);
    id me = (__bridge_transfer id)r;
    if (me && BP_OnName("y42_scenevc")) objc_setAssociatedObject(me, &kBPG3BContainerOri, @(1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return me;
}

__attribute__((constructor)) static void Y42SceneVC_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_scenevc")) return;
        Class vc = NSClassFromString(@"SBSceneViewController");
        if (!vc) { BP_Anomaly("y42", @"[y42] y42_scenevc NOT installed: SBSceneViewController missing"); return; }
        NSMutableArray *missing = [NSMutableArray array];
        if (!class_getInstanceMethod(vc, sel_registerName("initWithSceneHandle:"))) [missing addObject:@"-[SBSceneViewController initWithSceneHandle:]"];
        if (!class_getInstanceMethod(vc, sel_registerName("viewDidLoad"))) [missing addObject:@"-[SBSceneViewController viewDidLoad]"];
        if (!BP_IvarLookup(vc, "_sceneView")) [missing addObject:@"ivar _sceneView"];
        if (!BP_IvarLookup(vc, "_sceneHandle")) [missing addObject:@"ivar _sceneHandle"];
        const char *miss = y42_scenevc_preflight();
        if (miss) [missing addObject:[NSString stringWithFormat:@"unresolved names of the recompiled body: %s", miss]];
        if (missing.count) { BP_Anomaly("y42", @"[y42] y42_scenevc NOT installed: missing %@: the 16.0 controller stays", [missing componentsJoinedByString:@", "]); return; }
        Method im = class_getInstanceMethod(vc, sel_registerName("initWithSceneHandle:"));
        gOrigInit = method_getImplementation(im);
        class_replaceMethod(vc, sel_registerName("initWithSceneHandle:"), (IMP)Y42_SvcInit, method_getTypeEncoding(im));
        Method vm = class_getInstanceMethod(vc, sel_registerName("viewDidLoad"));
        gOrigViewDidLoad = method_getImplementation(vm);
        class_replaceMethod(vc, sel_registerName("viewDidLoad"), (IMP)Y42_SvcViewDidLoad, method_getTypeEncoding(vm));
        BP_Log(@"[y42] installed y42_scenevc");
        BP_Anomaly("y42-scenevc", @"[y42] y42_scenevc active (NOT device tested): the 16.2 -viewDidLoad (recompiled) and the container orientation store of the 16.2 -initWithSceneHandle: replace the 16.0 code of SBSceneViewController; OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_scenevc", __DATE__, __TIME__);
    }
}
#pragma clang diagnostic pop
