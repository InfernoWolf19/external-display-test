// Y42FullScreen.x : delta sweep pass 4 (block capable recompiler), the full screen always live overlay of iPadOS 16.2.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_fullscreen  -[SBFullScreenAlwaysLiveLiveContentOverlay initWithSceneHandle:referenceSize:containerOrientation:]  16.2 0x1c74d0d24 (16.0 0x1c6053fdc): the 16.2 init creates the device scene view with the
//   new init that carries content AND container orientation (the content orientation follows the handle: _supportsMixedOrientation), sets content / container orientation of the transform wrapper and
//   registers as observer.  Same 10 ivars in both builds; NOT re-typed: Y42FullScreenLift.c is the 16.2 machine code recompiled by tools/a2c/a2c.py, tracecmp equal on 24 seeds (367 calls with ownership events).
//   Needs the 16.2 scene view init of Y42SceneView.x (the recompiled body allocates SBDeviceApplicationSceneView, which is the Y34 runtime subclass when Y34ClassicSupport.x is active, and sends it):
//   without it (switch off / not installed) the 16.0 init runs (ANOMALY y42 once).
//   Class identity: the CLS() uses are the super receiver SBFullScreenAlwaysLiveLiveContentOverlay and the allocations of SBDeviceApplicationSceneView / SBOrientationTransformWrapperView (specs/Y42-CLASS-USES.md).
// Switch y42_fullscreen (kill file Backport162.off.y42_fullscreen).  Installed only on build 20A8372; ANOMALY y42-fullscreen (always on) names the build.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern uint64_t y42_fsal_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t containerOrientation);
extern const char *y42_fullscreen_preflight(void);

static IMP gOrigInit;
typedef void *(*Y42FsOrig)(void *, SEL, id, CGSize, long long);

__attribute__((ns_returns_retained)) static id Y42_FsInit(id __attribute__((ns_consumed)) self, SEL _cmd, id handle, CGSize size, long long container) {
    Class dsv = NSClassFromString(@"SBDeviceApplicationSceneView");
    SEL newInit = sel_registerName("initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:hostRequester:");
    void *raw = (__bridge_retained void *)self;       // an init consumes self (+1) and returns +1
    if (BP_OnName("y42_fullscreen") && dsv && class_getInstanceMethod(dsv, newInit)) {
        uint64_t r = y42_fsal_init((uint64_t)(uintptr_t)raw, (uint64_t)(uintptr_t)(void *)_cmd, (uint64_t)(uintptr_t)(__bridge void *)handle, size.width, size.height, (uint64_t)container);
        return (__bridge_transfer id)(void *)(uintptr_t)r;
    }
    static BOOL once;
    if (!once && BP_OnName("y42_fullscreen")) { once = YES; BP_Anomaly("y42", @"[y42] y42_fullscreen: SBDeviceApplicationSceneView has no 16.2 init yet (Y42SceneView.x): the 16.0 init ran"); }
    return (__bridge_transfer id)((Y42FsOrig)gOrigInit)(raw, _cmd, handle, size, container);
}

__attribute__((constructor)) static void Y42FullScreen_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_fullscreen")) return;
        Class c = NSClassFromString(@"SBFullScreenAlwaysLiveLiveContentOverlay");
        if (!c) { BP_Anomaly("y42", @"[y42] y42_fullscreen NOT installed: SBFullScreenAlwaysLiveLiveContentOverlay missing"); return; }
        NSMutableArray *missing = [NSMutableArray array];
        SEL init = sel_registerName("initWithSceneHandle:referenceSize:containerOrientation:");
        if (!class_getInstanceMethod(c, init)) [missing addObject:@"-[SBFullScreenAlwaysLiveLiveContentOverlay initWithSceneHandle:referenceSize:containerOrientation:]"];
        const char *ivn[] = { "_containerOrientation", "_sceneHandle", "_sceneView", "_transformWrapperView" };
        for (size_t k = 0; k < sizeof ivn / sizeof ivn[0]; k++) if (!BP_IvarLookup(c, ivn[k])) [missing addObject:[NSString stringWithFormat:@"ivar %s", ivn[k]]];
        const char *miss = y42_fullscreen_preflight();
        if (miss) [missing addObject:[NSString stringWithFormat:@"unresolved names of the recompiled body: %s", miss]];
        if (missing.count) { BP_Anomaly("y42", @"[y42] y42_fullscreen NOT installed: missing %@: the 16.0 overlay stays", [missing componentsJoinedByString:@", "]); return; }
        gOrigInit = BPX_Replace(c, "initWithSceneHandle:referenceSize:containerOrientation:", (IMP)Y42_FsInit);
        BP_Log(@"[y42] installed y42_fullscreen");
        BP_Anomaly("y42-fullscreen", @"[y42] y42_fullscreen active (NOT device tested): the 16.2 -[SBFullScreenAlwaysLiveLiveContentOverlay initWithSceneHandle:referenceSize:containerOrientation:] (recompiled) replaces the 16.0 init; OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_fullscreen", __DATE__, __TIME__);
    }
}
#pragma clang diagnostic pop
