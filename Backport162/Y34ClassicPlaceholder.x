// Y34ClassicPlaceholder.x : delta sweep pass 4, classic (iPhone-only) app launch image / zoom view path.  Setup: constructor.  Log prefix "[y34]".
//
//  y34_placeholder  16.2 bodies recompiled to C by tools/a2c (Y34PlaceholderLift.c, verified call by call against the Unicorn emulation of the originals, tools/a2c/tests/tracecmp.py):
//    -[SBDeviceApplicationSceneViewPlaceholderContentViewProvider sceneView:requestsPlaceholderContentViewWithContext:]   16.2 0x1c72a9bf8 (16.0 0x1c5e3780c)   REPLACED
//        16.2 (1) drops the [[sceneHandle displayIdentity] isMainRootDisplay] gate of the classic default launching size, (2) takes the scale from the display configuration it holds, (3) swaps the
//        reference size (BSSizeSwap) when the container and the snapshot orientation disagree under Stage Manager / for classic apps and no longer requires classicAppFullScreen, (4) calls
//        -_contentViewFromSceneHandle:...customContainerBounds: and (5) sets setContentOrientation: on the placeholder view.
//    -[SBDeviceApplicationSceneViewPlaceholderContentViewProvider _contentViewFromSceneHandle:displayConfiguration:orientation:snapshot:size:statusBarDescriptor:hasOrientationMismatchForClassicApp:customContainerBounds:]
//        16.2 0x1c7922f04: does not exist in 16.0 (16.0 has the sizeMatchesContentSize: variant): ADDED to the class
//    +[SBUIController(SBUIAnimationController) zoomViewForDeviceApplicationSceneHandle:...hasOrientationMismatchForClassicApp:customContainerBounds:]  16.2 0x1c77b55d4: not in 16.0 (the
//        16.0 selector ends in sizeMatchesContentSize:): ADDED to SBUIController (class method).  Its only 16.2 caller is the method above, so the 16.0 pair stays unused.
//    Callees checked 16.0 vs 16.2 (tools/a2c/tests/calleediff.py, selcheck.py, kindcheck.py): see specs/DELTA-SWEEP Pass 4.
//  A body whose preflight (C symbol / class / ivar) fails is NOT installed: ANOMALY y34 once and the 16.0 body keeps running.
// Needs a device: open an iPhone-only app from the icon with Stage Manager on: launch image placeholder sized / oriented like the 16.2 one (debug log "[y34] placeholder ...").

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Y34PlaceholderLift.c
extern uint64_t y34_ph_request(uint64_t self, uint64_t cmd, uint64_t sceneView, uint64_t context);
extern uint64_t y34_ph_contentView(uint64_t self, uint64_t cmd, uint64_t handle, uint64_t config, uint64_t orientation, uint64_t snapshot, double sw, double sh, uint64_t statusBar, uint8_t mismatch,
                                   double bx, double by, double bw, double bh);
extern uint64_t y34_zoom_view(uint64_t self, uint64_t cmd, uint64_t handle, uint64_t config, uint64_t orientation, uint64_t snapshot, double sw, double sh, uint64_t statusBar, uint8_t decode,
                              uint8_t mismatch, double bx, double by, double bw, double bh);
extern const char *y34_placeholder_preflight(void);

#define Y34_P(o) ((uint64_t)(uintptr_t)(__bridge void *)(o))
static IMP gY34OrigRequest;

static id Y34_PhRequest(id self, SEL _cmd, id sceneView, id context) {
    if (!BP_OnName("y34_placeholder")) return ((id (*)(id, SEL, id, id))gY34OrigRequest)(self, _cmd, sceneView, context);
    uint64_t r = y34_ph_request(Y34_P(self), (uint64_t)(uintptr_t)(void *)_cmd, Y34_P(sceneView), Y34_P(context));
    return (__bridge id)(void *)(uintptr_t)r;
}
static id Y34_PhContentView(id self, SEL _cmd, id handle, id config, long long orientation, id snapshot, CGSize size, id statusBar, BOOL mismatch, CGRect bounds) {
    uint64_t r = y34_ph_contentView(Y34_P(self), (uint64_t)(uintptr_t)(void *)_cmd, Y34_P(handle), Y34_P(config), (uint64_t)orientation, Y34_P(snapshot), size.width, size.height, Y34_P(statusBar), mismatch,
                                    bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
    return (__bridge id)(void *)(uintptr_t)r;
}
static id Y34_ZoomView(id self, SEL _cmd, id handle, id config, long long orientation, id snapshot, CGSize size, id statusBar, BOOL decode, BOOL mismatch, CGRect bounds) {
    uint64_t r = y34_zoom_view(Y34_P(self), (uint64_t)(uintptr_t)(void *)_cmd, Y34_P(handle), Y34_P(config), (uint64_t)orientation, Y34_P(snapshot), size.width, size.height, Y34_P(statusBar), decode, mismatch,
                               bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
    return (__bridge id)(void *)(uintptr_t)r;
}

__attribute__((constructor)) static void Y34Placeholder_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class prov = NSClassFromString(@"SBDeviceApplicationSceneViewPlaceholderContentViewProvider");
        Class ui = NSClassFromString(@"SBUIController");
        const char *miss = y34_placeholder_preflight();
        if (!prov || !ui || miss) {
            BP_Anomaly("y34", @"[y34] y34_placeholder NOT installed: provider %p SBUIController %p, unresolved names of the recompiled 16.2 bodies: %s: the 16.0 launch image path keeps running", (__bridge void *)prov, (__bridge void *)ui, miss ?: "-");
            return;
        }
        SEL cvSel = sel_registerName("_contentViewFromSceneHandle:displayConfiguration:orientation:snapshot:size:statusBarDescriptor:hasOrientationMismatchForClassicApp:customContainerBounds:");
        SEL zoomSel = sel_registerName("zoomViewForDeviceApplicationSceneHandle:displayConfiguration:interfaceOrientation:snapshot:snapshotSize:statusBarDescriptor:decodeImage:hasOrientationMismatchForClassicApp:customContainerBounds:");
        SEL reqSel = sel_registerName("sceneView:requestsPlaceholderContentViewWithContext:");
        if (!class_getInstanceMethod(prov, reqSel)) { BP_Anomaly("y34", @"[y34] y34_placeholder NOT installed: -[%s sceneView:requestsPlaceholderContentViewWithContext:] does not exist", class_getName(prov)); return; }
        // the callees first: the replaced entry point sends the new selectors
        BOOL a1 = class_addMethod(prov, cvSel, (IMP)Y34_PhContentView, "@@:@@q@{CGSize=dd}@B{CGRect={CGPoint=dd}{CGSize=dd}}");
        BOOL a2 = class_addMethod(object_getClass((id)ui), zoomSel, (IMP)Y34_ZoomView, "@@:@@q@{CGSize=dd}@BB{CGRect={CGPoint=dd}{CGSize=dd}}");
        if (!a1 || !a2) BP_Anomaly("y34", @"[y34] placeholder: the 16.2 callee selector already exists (content view %d, zoom view %d): the existing implementation is used", a1, a2);
        gY34OrigRequest = BPX_Replace(prov, "sceneView:requestsPlaceholderContentViewWithContext:", (IMP)Y34_PhRequest);
        BP_Log(@"[y34] installed y34_placeholder (callees added: %d %d)", a1, a2);
    }
}
#pragma clang diagnostic pop
