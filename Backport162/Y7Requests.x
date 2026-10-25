// Y7Requests.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): switcher transition request fields that 16.2 added.  Setup: constructor.  Log prefix "[y7]".
//
//  y7_inspolicy  SBSwitcherTransitionRequest.entityInsertionPolicy (new in 16.2, ivar after activatingDisplayItem) is set by -[SBFullScreenContinuousExposeSwitcherModifier
//                handleTapAppLayoutEvent:] 0x1c75c48cc (policy 1 when the tap carries the Shift modifier, G1C.x sends -setEntityInsertionPolicy: for it) and read by
//                -[SBMainSwitcherControllerCoordinator _configureRequest:forSwitcherTransitionRequest:withEventLabel:] 0x1c76d21f0, which passes it as the policy of
//                [ctx setEntities:withPolicy:centerEntity:floatingEntity:] (16.0 0x1c623e164 passes the constant 0 there; the context method itself did not change, policy 1 is
//                implemented by 16.0).  The selector did not exist in 16.0, so the Shift-tap request carried nothing (and mutableCopyWithZone: 16.2 0x1c740dc2c copies both new fields).
//                Ported: accessors on the request (associated object), the copy in -mutableCopyWithZone: for entityInsertionPolicy and activatingDisplayItem (G1D.x keeps the latter
//                as an associated object, the 16.0 copy dropped it), and the policy handed to the one setEntities:withPolicy: call of the 16.0 body (thread local around the call).
// Needs a device with a hardware keyboard: hold Shift and click a window in the Stage Manager strip: the window is added to the stage next to the current one instead of replacing it.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static const void *kY7Policy = &kY7Policy;
static __thread long long tY7Policy;                // policy handed to setEntities:withPolicy: while the wrapped _configureRequest runs (0 = none)
static IMP gY7OrigCopy, gY7OrigConfigure, gY7OrigSetEntities;

static long long Y7_GetPolicy(id self, SEL _cmd) {
    NSNumber *n = objc_getAssociatedObject(self, kY7Policy);
    return n ? n.longLongValue : 0;
}
static void Y7_SetPolicy(id self, SEL _cmd, long long v) {
    objc_setAssociatedObject(self, kY7Policy, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// -[SBSwitcherTransitionRequest mutableCopyWithZone:]
static id Y7_Copy(id self, SEL _cmd, NSZone *zone) {
    id c = gY7OrigCopy ? ((id (*)(id, SEL, NSZone *))gY7OrigCopy)(self, _cmd, zone) : nil;
    if (!c || !BP_OnName("y7_inspolicy")) return c;
    if (BPY_Responds(self, "activatingDisplayItem") && BPY_Responds(c, "setActivatingDisplayItem:")) BPX_SetObj1(c, "setActivatingDisplayItem:", BPX_Obj0(self, "activatingDisplayItem"));
    long long p = BPX_LL0(self, "entityInsertionPolicy");
    if (p && BPY_Responds(c, "setEntityInsertionPolicy:")) BPY_SEND(void, (long long), c, "setEntityInsertionPolicy:", p);
    return c;
}

// -[SBMainSwitcherControllerCoordinator _configureRequest:forSwitcherTransitionRequest:withEventLabel:]
static void Y7_Configure(id self, SEL _cmd, id wreq, id req, id label) {
    long long prev = tY7Policy;
    tY7Policy = (BP_OnName("y7_inspolicy") && BPY_Responds(req, "entityInsertionPolicy")) ? BPX_LL0(req, "entityInsertionPolicy") : 0;
    if (tY7Policy) BPY_LOG(@"[y7] request %p carries the entity insertion policy %lld", (__bridge void *)req, tY7Policy);
    if (gY7OrigConfigure) ((void (*)(id, SEL, id, id, id))gY7OrigConfigure)(self, _cmd, wreq, req, label);
    tY7Policy = prev;
}
// -[SBWorkspaceApplicationSceneTransitionContext setEntities:withPolicy:centerEntity:floatingEntity:]
static void Y7_SetEntities(id self, SEL _cmd, id entities, long long policy, id center, id floating) {
    if (policy == 0 && tY7Policy) policy = tY7Policy;
    if (gY7OrigSetEntities) ((void (*)(id, SEL, id, long long, id, id))gY7OrigSetEntities)(self, _cmd, entities, policy, center, floating);
}

__attribute__((constructor)) static void Y7_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class rq = NSClassFromString(@"SBSwitcherTransitionRequest"), co = NSClassFromString(@"SBMainSwitcherControllerCoordinator"), cx = NSClassFromString(@"SBWorkspaceApplicationSceneTransitionContext");
        if (!rq || !co || !cx || !class_getInstanceMethod(rq, sel_registerName("mutableCopyWithZone:")) ||
            !class_getInstanceMethod(co, sel_registerName("_configureRequest:forSwitcherTransitionRequest:withEventLabel:")) ||
            !class_getInstanceMethod(cx, sel_registerName("setEntities:withPolicy:centerEntity:floatingEntity:"))) {
            BP_Log(@"[y7] NOT installed (class or selector missing)");
            return;
        }
        if (!class_getInstanceMethod(rq, sel_registerName("entityInsertionPolicy"))) {
            class_addMethod(rq, sel_registerName("entityInsertionPolicy"), (IMP)Y7_GetPolicy, "q16@0:8");
            class_addMethod(rq, sel_registerName("setEntityInsertionPolicy:"), (IMP)Y7_SetPolicy, "v24@0:8q16");
        }
        gY7OrigCopy = BPX_Replace(rq, "mutableCopyWithZone:", (IMP)Y7_Copy);
        gY7OrigConfigure = BPX_Replace(co, "_configureRequest:forSwitcherTransitionRequest:withEventLabel:", (IMP)Y7_Configure);
        gY7OrigSetEntities = BPX_Replace(cx, "setEntities:withPolicy:centerEntity:floatingEntity:", (IMP)Y7_SetEntities);
        BP_Log(@"[y7] installed (switch y7_inspolicy): entity insertion policy of switcher transition requests");
    }
}
#pragma clang diagnostic pop
