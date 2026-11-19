// Y42Peek.x : delta sweep pass 4 (block capable recompiler), Split View peek routing of iPadOS 16.2.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_peek   -[SBPeekSplitViewRoutingSwitcherModifier responseForProposedChildResponse:childModifier:event:]  16.2 0x1c74e7210 (16.0 0x1c6065a50): the 16.2 body also asks the peeking app layout
//             for itemForLayoutRole: and puts the item on the transition request (activatingDisplayItem, an associated object in 16.0: G1D.x / Y7Requests.x) before setPeekConfiguration:
//             -[SBPeekSplitViewRoutingSwitcherModifier routingModifier:event:forModifier:]  16.2 0x1c74e7a88 (16.0 0x1c6066294): routes one more event type (0xf) to the peeking / non peeking modifier.
//   Both are NOT re-typed: Y42PeekLift.c is the 16.2 machine code recompiled by tools/a2c/a2c.py with their stack blocks (arm64e pacda isa / pacia invoke, descriptors) and the six block
//   invoke bodies (0x1c74e77ac, 0x1c74e7878, 0x1c74e8018, 0x1c74e8024, 0x1c74e8030, 0x1c74e8054).  Verified with tools/a2c/tests/tracecmp.py (tests/tc_all.py peek): every message / C call, every retain /
//   release / autorelease / claim / storeStrong in order, the PAC operations, block images, memory and result equal to the Unicorn emulation of the 16.2 code on 24 seeds per body.
//   What can break on a device: (1) the stack blocks are signed with the real pacda / pacia keys; the children (SBChainableModifier response transformers, appLayoutWithItemsPassingTest:) call the invoke through
//   the signed pointer: an authentication failure crashes there; (2) the 16.2 body sends -setActivatingDisplayItem: to a mutable transition request: if no accessor exists (G1D.x adds it) the 16.0 body runs
//   (ANOMALY y42 once); (3) a missing class / symbol keeps the 16.0 body.
// Switch y42_peek (kill file Backport162.off.y42_peek).  Installed only on build 20A8372; ANOMALY y42-peek (always on) names the build.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Y42PeekLift.c
extern uint64_t y42_peek_response(uint64_t self, uint64_t cmd, uint64_t response, uint64_t child, uint64_t event);
extern uint64_t y42_peek_routing(uint64_t self, uint64_t cmd, uint64_t routing, uint64_t event, uint64_t forModifier);
extern const char *y42_peek_preflight(void);

static IMP gY42OrigResponse, gY42OrigRouting;

static BOOL Y42_RequestAccessor(void) {
    static BOOL ok;
    if (!ok) {
        Class r = NSClassFromString(@"SBMutableSwitcherTransitionRequest");
        ok = r && class_getInstanceMethod(r, sel_registerName("setActivatingDisplayItem:")) != NULL;
        if (!ok) BP_Anomaly("y42", @"[y42] y42_peek: SBMutableSwitcherTransitionRequest has no setActivatingDisplayItem: yet (G1D.x adds it): the 16.0 body ran");
    }
    return ok;
}

// the 16.2 method returns a +0 / autoreleased response exactly like the machine code (the recompiled body balances its own retains); ARC does not touch the raw integers
static id Y42_Response(id self, SEL _cmd, id response, id child, id event) {
    if (!BP_OnName("y42_peek") || !Y42_RequestAccessor()) return ((id (*)(id, SEL, id, id, id))gY42OrigResponse)(self, _cmd, response, child, event);
    return (__bridge id)(void *)(uintptr_t)y42_peek_response((uint64_t)(uintptr_t)(__bridge void *)self, (uint64_t)(uintptr_t)(void *)_cmd, (uint64_t)(uintptr_t)(__bridge void *)response,
                                                              (uint64_t)(uintptr_t)(__bridge void *)child, (uint64_t)(uintptr_t)(__bridge void *)event);
}
static id Y42_Routing(id self, SEL _cmd, id routing, id event, id forModifier) {
    if (!BP_OnName("y42_peek")) return ((id (*)(id, SEL, id, id, id))gY42OrigRouting)(self, _cmd, routing, event, forModifier);
    return (__bridge id)(void *)(uintptr_t)y42_peek_routing((uint64_t)(uintptr_t)(__bridge void *)self, (uint64_t)(uintptr_t)(void *)_cmd, (uint64_t)(uintptr_t)(__bridge void *)routing,
                                                             (uint64_t)(uintptr_t)(__bridge void *)event, (uint64_t)(uintptr_t)(__bridge void *)forModifier);
}

__attribute__((constructor)) static void Y42Peek_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_peek")) return;
        Class peek = NSClassFromString(@"SBPeekSplitViewRoutingSwitcherModifier");
        if (!peek) { BP_Anomaly("y42", @"[y42] y42_peek NOT installed: SBPeekSplitViewRoutingSwitcherModifier missing"); return; }
        const char *miss = y42_peek_preflight();
        if (miss) { BP_Anomaly("y42", @"[y42] y42_peek NOT installed: the recompiled 16.2 bodies cannot resolve: %s: the 16.0 bodies keep running", miss); return; }
        const char *sels[] = { "responseForProposedChildResponse:childModifier:event:", "routingModifier:event:forModifier:" };
        for (int k = 0; k < 2; k++)
            if (!class_getInstanceMethod(peek, sel_registerName(sels[k]))) { BP_Anomaly("y42", @"[y42] y42_peek NOT installed: -[SBPeekSplitViewRoutingSwitcherModifier %s] does not exist", sels[k]); return; }
        gY42OrigResponse = BPX_Replace(peek, sels[0], (IMP)Y42_Response);
        gY42OrigRouting = BPX_Replace(peek, sels[1], (IMP)Y42_Routing);
        BP_Log(@"[y42] installed y42_peek");
        BP_Anomaly("y42-peek", @"[y42] y42_peek active (NOT device tested): the 16.2 -responseForProposedChildResponse:childModifier:event: and -routingModifier:event:forModifier: (recompiled, stack blocks signed with the real pacda / pacia) replace the 16.0 code; OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_peek", __DATE__, __TIME__);
    }
}
#pragma clang diagnostic pop
