// Y42Shelf.x : delta sweep pass 4 (block capable recompiler), the shelf live content overlay path of iPadOS 16.2.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_shelf   -[SBShelfLiveContentOverlayCoordinator _addOverlaysIfNeededForTransitionContext:]  16.2 0x1c798ac94 (16.0 0x1c64cf838), and the one method of the overlay class it needs:
//              -[SBShelfLiveContentOverlay initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:livePortalView:isInsetForHomeAffordance:]  16.2 0x1c798b6b8.
//   The 16.2 coordinator body is NOT re-typed: Y42ShelfLift.c is the 16.2 machine code recompiled by tools/a2c/a2c.py, including the stack block (arm64e pacda isa / pacia invoke, descriptor) it passes to
//   bs_firstObjectPassingTest: and its invoke 0x1c798b338.  16.2 differs from 16.0 in two things: the overlay is created with the new init that carries the content AND the container orientation
//   (16.0: referenceOrientation:) and the content orientation is looked up with the layout state (-interfaceOrientationForElementIdentifier:, a 16.0 method).  The 16.2 init of the overlay class (84
//   instructions; the class has the same 11 ivars in both builds) is added as a method, recompiled as well: it asks the scene handle for newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:
//   (G3B.x adds that method to SBDeviceApplicationSceneHandle).
//   Verified with tools/a2c/tests/tracecmp.py against the Unicorn emulation of the 16.2 machine code on a modelled environment (every message, C call, retain / release / autorelease / claim / storeStrong
//   in order, the PAC operations, the block image and descriptor, memory and result): see the generator tools/a2c/gen_y42.py and tests/tc_all.py.
//   What can break on a device: (1) the block is built on the C stack of the recompiled function and signed with the REAL pacda / pacia keys exactly like the machine code, bs_firstObjectPassingTest: calls the
//   invoke through the signed pointer: an authentication failure would crash right there (the invoke is a C function of this image, address-diversified pacia, the isa signed pacda with the block address);
//   (2) the os_log_impl debug lines pass OUR image as the log call site; (3) a missing symbol / selector (SBLogShelfLiveContent, kCAFilterBox, bs_map: ...) keeps the 16.0 body (ANOMALY y42 once).
// Switch y42_shelf (kill file Backport162.off.y42_shelf).  Installed only on build 20A8372; ANOMALY y42-shelf (always on) names the build.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Y42ShelfLift.c
extern void y42_shelf_add(void *self, void *cmd, void *context);
extern uint64_t y42_shelf_init(uint64_t self, uint64_t cmd, uint64_t handle, double w, double h, uint64_t contentOri, uint64_t containerOri, uint64_t portal, uint64_t inset);
extern const char *y42_shelf_preflight(void);

static IMP gY42OrigAdd;

// the new init asks the scene handle for the 16.2 scene view factory (G3B.x); without it the 16.0 body runs
static BOOL Y42_HandleFactory(void) {
    static BOOL ok, checked;
    if (!checked) {
        Class h = NSClassFromString(@"SBDeviceApplicationSceneHandle");
        ok = h && class_getInstanceMethod(h, sel_registerName("newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester:")) != NULL;
        if (ok) checked = YES;       // G3B may install later in the launch: ask again until it is there
        else BP_Anomaly("y42", @"[y42] y42_shelf: SBDeviceApplicationSceneHandle has no newSceneViewWithReferenceSize:contentOrientation:containerOrientation:hostRequester: yet: the 16.0 body ran");
    }
    return ok;
}

static void Y42_ShelfAdd(id self, SEL _cmd, id context) {
    if (!BP_OnName("y42_shelf") || !Y42_HandleFactory()) { ((void (*)(id, SEL, id))gY42OrigAdd)(self, _cmd, context); return; }
    y42_shelf_add((__bridge void *)self, (void *)_cmd, (__bridge void *)context);
}

__attribute__((constructor)) static void Y42Shelf_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_shelf")) return;
        Class coord = NSClassFromString(@"SBShelfLiveContentOverlayCoordinator");
        Class overlay = NSClassFromString(@"SBShelfLiveContentOverlay");
        if (!coord || !overlay) { BP_Anomaly("y42", @"[y42] y42_shelf NOT installed: SBShelfLiveContentOverlayCoordinator %p / SBShelfLiveContentOverlay %p missing", (__bridge void *)coord, (__bridge void *)overlay); return; }
        const char *miss = y42_shelf_preflight();
        if (miss) { BP_Anomaly("y42", @"[y42] y42_shelf NOT installed: the recompiled 16.2 body cannot resolve: %s: the 16.0 body keeps running", miss); return; }
        // every selector the recompiled body sends to a 16.0 class that is not in the 16.0 SpringBoard dumps (BaseBoard / Foundation / QuartzCore categories): ALL misses are named at once
        struct { const char *c; const char *s; BOOL cls; } need[] = {
            { "NSArray", "bs_map:", NO }, { "NSArray", "bs_flatten", NO }, { "NSArray", "bs_firstObjectPassingTest:", NO }, { "NSArray", "arrayByAddingObjectsFromArray:", NO },
            { "NSSet", "setWithArray:", YES }, { "SBAppLayout", "containsAnyItemFromSet:", NO }, { "SBAppLayout", "itemForLayoutRole:", NO }, { "SBAppLayout", "leafAppLayouts", NO }, { "CALayer", "setShouldRasterize:", NO },
        };
        NSMutableArray *missing = [NSMutableArray array];
        for (size_t k = 0; k < sizeof need / sizeof need[0]; k++) {
            Class nc = NSClassFromString([NSString stringWithUTF8String:need[k].c]);
            SEL ns = sel_registerName(need[k].s);
            BOOL ok = nc && (need[k].cls ? class_getClassMethod(nc, ns) != NULL : class_getInstanceMethod(nc, ns) != NULL);
            if (!ok) [missing addObject:[NSString stringWithFormat:@"%c[%s %s]", need[k].cls ? '+' : '-', need[k].c, need[k].s]];
        }
        if (missing.count) { BP_Anomaly("y42", @"[y42] y42_shelf NOT installed: missing selectors: %@: the 16.0 body keeps running", [missing componentsJoinedByString:@", "]); return; }
        SEL initSel = sel_registerName("initWithSceneHandle:referenceSize:contentOrientation:containerOrientation:livePortalView:isInsetForHomeAffordance:");
        if (!class_getInstanceMethod(coord, sel_registerName("_addOverlaysIfNeededForTransitionContext:"))) { BP_Anomaly("y42", @"[y42] y42_shelf NOT installed: -[SBShelfLiveContentOverlayCoordinator _addOverlaysIfNeededForTransitionContext:] does not exist"); return; }
        if (!class_getInstanceMethod(overlay, initSel) && !class_addMethod(overlay, initSel, (IMP)y42_shelf_init, "@@:@{CGSize=dd}qq@B")) { BP_Anomaly("y42", @"[y42] y42_shelf NOT installed: class_addMethod of the 16.2 overlay init failed"); return; }
        gY42OrigAdd = BPX_Replace(coord, "_addOverlaysIfNeededForTransitionContext:", (IMP)Y42_ShelfAdd);
        BP_Log(@"[y42] installed y42_shelf");
        BP_Anomaly("y42-shelf", @"[y42] y42_shelf active (NOT device tested): the 16.2 -_addOverlaysIfNeededForTransitionContext: (recompiled, stack block signed with the real pacda / pacia) and the 16.2 overlay init replace the 16.0 code; OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_shelf", __DATE__, __TIME__);
    }
}
#pragma clang diagnostic pop
