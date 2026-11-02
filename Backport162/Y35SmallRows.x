// Y35SmallRows.x : delta sweep pass 4, small rows next to the classic cluster.  Setup: constructor.  Log prefix "[y35]".
//
//  y35_medusaend  -[SBMedusaDecoratedDeviceApplicationSceneViewController layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:]  16.2 0x1c77cc710 (16.0 0x1c632b5e8):
//                 16.2 only forwards the callback to the wrapped _deviceApplicationSceneViewController (when it responds to it); the 16.0 body sent
//                 -_presentTransientErrorMessageIfNeededForLayoutStateTransitionContext: afterwards (the "app unavailable" message of the classic Medusa decorated controller), which 16.2 no
//                 longer does.  The 16.2 body is 34 instructions and is ported 1:1 (tools/a2c/tests/mdiff.py: the lifted texts differ exactly by that one send).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY35OrigMedusaEnd;

static void Y35_MedusaEnd(id self, SEL _cmd, id coordinator, id context) {
    if (!BP_OnName("y35_medusaend")) { ((void (*)(id, SEL, id, id))gY35OrigMedusaEnd)(self, _cmd, coordinator, context); return; }
    id vc = BPX_IvarObj(self, "_deviceApplicationSceneViewController");        // 16.2: ldr x0, [self, _deviceApplicationSceneViewController]
    if (vc && [vc respondsToSelector:_cmd]) ((void (*)(id, SEL, id, id))objc_msgSend)(vc, _cmd, coordinator, context);
}

__attribute__((constructor)) static void Y35_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBMedusaDecoratedDeviceApplicationSceneViewController");
        SEL s = sel_registerName("layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:");
        if (!c || !class_getInstanceMethod(c, s) || !BP_IvarLookup(c, "_deviceApplicationSceneViewController")) {
            BP_Anomaly("y35", @"[y35] y35_medusaend NOT installed: class %p / selector / ivar _deviceApplicationSceneViewController missing: the 16.0 body (with the transient error message) keeps running", (__bridge void *)c);
            return;
        }
        gY35OrigMedusaEnd = BPX_Replace(c, "layoutStateTransitionCoordinator:transitionWillEndWithTransitionContext:", (IMP)Y35_MedusaEnd);
        BP_Log(@"[y35] installed y35_medusaend");
    }
}
#pragma clang diagnostic pop
