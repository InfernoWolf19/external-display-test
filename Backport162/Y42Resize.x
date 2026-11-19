// Y42Resize.x : delta sweep pass 5, the item resize gesture modifier of iPadOS 16.2.  Setup: constructor (priority 101: the Logos hooks of G1C / G3B on the same selectors are installed AFTER it and wrap it).
// Log prefix "[y42]".  NOT device tested.
//
//  y42_resize  SBItemResizeGestureSwitcherModifier of 16.2 (20C65), the whole bodies recompiled from the 16.2 machine code by tools/a2c/a2c.py (Y42ResizeLift.c):
//     -handleGestureEvent: 0x1c76be31c (16.0 0x1c622bcd8)                        the selected item frame comes from -_initialScaledFrameInScreenCoordinatesForSelectedDisplayItemInAppLayout:, a nil app layout asserts
//     -_responseForGestureUpdateAtGestureEnd: 0x1c76be610 (+ block invoke 0x1c76bed0c)   (16.0 0x1c622bf98)  the stage area of the resize comes from [[self overlappingModelForAppLayout:] stageAreaForResizing],
//                                                                                the resize ends with newAppLayoutsGenCount, an SBUpdateLayoutSwitcherEventResponse (options 0x1e, update mode 3) and the strip presentation response
//     -_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly: 0x1c76bed98 (16.0 0x1c622c5dc)   the committed size is an ATTRIBUTED size (SBDisplayItemAttributedSizeInfer, a 16.2 function: Y34LiftRT.c builtin), the new size /
//                                                                                center are put on the item layout attributes (attributesByModifyingNormalizedCenter: / ...AttributedSize:), and the orientation response of 16.2 is appended here
//     -_initialScaledFrameInScreenCoordinatesForSelectedDisplayItemInAppLayout: 0x1c76bfa80 (new)    -_anyItemExceedsWidthThresholdToHideStrip 0x1c76bfd40 (16.0 0x1c622d588)
//  The orientation response that G1C.x appended after the 16.0 body is now produced by the 16.2 body itself: G1C's wrapper is switched off through gY42ResizeLifted.  G3B's wrappers (orthogonal items) still wrap it.
// Switch y42_resize (kill file Backport162.off.y42_resize).  Installed only on build 20A8372; ANOMALY y42-resize (always on) names the build.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreGraphics/CoreGraphics.h>
#import "Y17Common.h"
#import "BPX.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Y42ResizeLift.c
extern uint64_t y42_rs_event(uint64_t self, uint64_t cmd, uint64_t event);
extern uint64_t y42_rs_end(uint64_t self, uint64_t cmd, uint64_t end);
extern uint64_t y42_rs_scene(uint64_t self, uint64_t cmd, double w, double h, double cx, double cy, uint64_t only);
extern uint64_t y42_rs_any(uint64_t self, uint64_t cmd);
extern void y42_rs_init(double out[4], uint64_t self, uint64_t cmd, uint64_t layout);
extern const char *y42_resize_preflight(void);

volatile int gY42ResizeLifted;          // read by G1C.x (its orientation response wrapper steps aside)
static IMP gY42OrigEvent, gY42OrigEnd, gY42OrigScene, gY42OrigAny;

// the selectors the 16.2 bodies send that the 16.0 class lacks are added by other ports (G1B / G1C / G2 / G2B constructors run after this one): checked at the first call, the 16.0 bodies run until they exist
static BOOL Y42R_Ready(id self) {
    static BOOL ok;
    if (ok) return YES;
    const char *need[] = { "overlappingModelForAppLayout:", "layoutRestrictionInfoForItem:", "chamoisLayoutAttributes", "newAppLayoutsGenCount", "continuousExposeStripProgress" };
    for (int k = 0; k < 5; k++)
        if (![self respondsToSelector:sel_registerName(need[k])]) {
            BP_Anomaly("y42", @"[y42] y42_resize: -[%@ %s] does not exist (yet): the 16.0 body runs", NSStringFromClass(object_getClass(self)), need[k]);
            return NO;
        }
    ok = YES;
    return YES;
}
#define Y42R_U(o) ((uint64_t)(uintptr_t)(__bridge void *)(o))
static id Y42R_Event(id self, SEL _cmd, id event) {
    if (!BP_OnName("y42_resize") || !Y42R_Ready(self)) return ((id (*)(id, SEL, id))gY42OrigEvent)(self, _cmd, event);
    return (__bridge id)(void *)(uintptr_t)y42_rs_event(Y42R_U(self), (uint64_t)(uintptr_t)(void *)_cmd, Y42R_U(event));
}
static id Y42R_End(id self, SEL _cmd, BOOL end) {
    if (!BP_OnName("y42_resize") || !Y42R_Ready(self)) return ((id (*)(id, SEL, BOOL))gY42OrigEnd)(self, _cmd, end);
    return (__bridge id)(void *)(uintptr_t)y42_rs_end(Y42R_U(self), (uint64_t)(uintptr_t)(void *)_cmd, end ? 1 : 0);
}
static id Y42R_Scene(id self, SEL _cmd, CGSize size, CGPoint center, BOOL only) {
    if (!BP_OnName("y42_resize") || !Y42R_Ready(self)) return ((id (*)(id, SEL, CGSize, CGPoint, BOOL))gY42OrigScene)(self, _cmd, size, center, only);
    return (__bridge id)(void *)(uintptr_t)y42_rs_scene(Y42R_U(self), (uint64_t)(uintptr_t)(void *)_cmd, size.width, size.height, center.x, center.y, only ? 1 : 0);
}
static CGRect Y42R_Initial(id self, SEL _cmd, id layout) {
    double o[4];
    y42_rs_init(o, Y42R_U(self), (uint64_t)(uintptr_t)(void *)_cmd, Y42R_U(layout));
    return CGRectMake(o[0], o[1], o[2], o[3]);
}
static BOOL Y42R_Any(id self, SEL _cmd) {
    if (!BP_OnName("y42_resize") || !Y42R_Ready(self)) return ((BOOL (*)(id, SEL))gY42OrigAny)(self, _cmd);
    return y42_rs_any(Y42R_U(self), (uint64_t)(uintptr_t)(void *)_cmd) & 1;
}

__attribute__((constructor(101))) static void Y42Resize_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_resize")) return;
        Class c = NSClassFromString(@"SBItemResizeGestureSwitcherModifier");
        if (!c) { BP_Anomaly("y42", @"[y42] y42_resize NOT installed: SBItemResizeGestureSwitcherModifier missing"); return; }
        const char *miss = y42_resize_preflight();
        if (miss) { BP_Anomaly("y42", @"[y42] y42_resize NOT installed: the recompiled 16.2 bodies cannot resolve: %s: the 16.0 bodies keep running", miss); return; }
        const char *sels[] = { "handleGestureEvent:", "_responseForGestureUpdateAtGestureEnd:", "_responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly:", "_anyItemExceedsWidthThresholdToHideStrip" };
        for (int k = 0; k < 4; k++)
            if (!class_getInstanceMethod(c, sel_registerName(sels[k]))) { BP_Anomaly("y42", @"[y42] y42_resize NOT installed: -[SBItemResizeGestureSwitcherModifier %s] does not exist", sels[k]); return; }
        gY42OrigEvent = BPX_Replace(c, sels[0], (IMP)Y42R_Event);
        gY42OrigEnd = BPX_Replace(c, sels[1], (IMP)Y42R_End);
        gY42OrigScene = BPX_Replace(c, sels[2], (IMP)Y42R_Scene);
        gY42OrigAny = BPX_Replace(c, sels[3], (IMP)Y42R_Any);
        class_addMethod(c, sel_registerName("_initialScaledFrameInScreenCoordinatesForSelectedDisplayItemInAppLayout:"), (IMP)Y42R_Initial, "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8@16");
        gY42ResizeLifted = 1;
        BP_Log(@"[y42] installed y42_resize");
        BP_Anomaly("y42-resize", @"[y42] y42_resize active (NOT device tested): the 16.2 SBItemResizeGestureSwitcherModifier handleGestureEvent: / _responseForGestureUpdateAtGestureEnd: / _responseForSceneSizeUpdateToSize:center:sceneUpdatesOnly: / _initialScaledFrameInScreenCoordinates... / _anyItemExceedsWidthThresholdToHideStrip (recompiled) replace the 16.0 bodies on build 20A8372");
    }
}
#pragma clang diagnostic pop
