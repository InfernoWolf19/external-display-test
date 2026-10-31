// Y29Blur.x : delta sweep pass 3, switcher blur rows (F3).  Setup: constructor.  Log prefix "[y29]".
//
//  y24_blurraster  SBBlurItemContainerParameters gets 16.2's shouldRasterize (new ivar +0x8; 16.2 init -initWithBlurRadius:shouldRasterize:rasterizationScale:inputQuality:inputIntermediateBitDepth:
//                  blurAnimationSettings: 0x1c78400a0).  The class has exactly two creators in both builds (call sites of the init found by scanning the whole SpringBoard text): the iPhone
//                  SBFullScreenToHomeSystemApertureSwitcherModifier (16.2 passes YES) and +defaultCrossblurBlurParameters (16.2 0x1c7840144 passes shouldRasterize = NO, 16.0 0x1c6396d94 has no such
//                  argument).  Ported: -shouldRasterize (associated flag, YES when never set = what every 16.0 container did) and +defaultCrossblurBlurParameters marks its result NO.
//                  -[SBFluidSwitcherViewController _blurItemContainer:blurParameters:withAnimationUpdateMode:]  16.2 0x1c743f438 (16.0 0x1c5fc6858): the container layer's rasterizationScale /
//                  shouldRasterize are only set when the parameters ask for it (16.2 0x1c743f5cc `[a3 shouldRasterize]`); 16.0 always rasterized.  Ported: the layer's two properties are restored to
//                  their previous values after the 16.0 body when the parameters say NO.
//  y24_blurroot    -[SBFluidSwitcherViewController _applyRootContentViewBlurRadiusWithCompletion:]  16.2 0x1c74429e8 (16.0 0x1c5fc9e04): when the root content view blur radius is zero and the
//                  content view's layer has no filters there is nothing to animate: 16.2 calls the completion block at once with (finished YES, retargeted NO) (0x1c7442bf4..c0c); 16.0 ran the blur
//                  animation anyway and completed after the animation duration.  Ported as that early out (radius = [_rootModifier rootContentViewBlurRadius], layer = [_contentView layer]).
//  Not ported, with the reason: -[SBFluidSwitcherViewController _ensureSubviewOrdering] (16.2 0x1c74473b0 additionally brings the _reopenClosedWindowsButton view to the front) and
//  -_orderedViewsForLayoutElement:excludeSwitcherHostedElements: (16.2 0x1c7450094 handles layout element types 6 and 7): both exist for 16.2 objects this port does not have: the reopen button view
//  (16.2 only ivar +0x720, created by -_updateReopenClosedWindowsButtonPresence, 16.0 has neither) and layout elements of type 6 / 7 (no modifier of this port returns them: every source reads
//  switcherLayoutElementType, none produces a value above 5).
// Needs a device: Stage Manager transitions with the cross blur (opening an app over the strip / dosido) are not slower than before; closing the last blurred state returns promptly.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY29OrigCross, gY29OrigBlur, gY29OrigRoot;
static char kY29NoRaster;

static BOOL Y29_ShouldRasterize(id self, SEL _cmd) {
    return ![objc_getAssociatedObject(self, &kY29NoRaster) boolValue];
}
// +defaultCrossblurBlurParameters returns a new (autoreleased) object per call
static id Y29_DefaultCrossblur(id cls, SEL _cmd) {
    id p = gY29OrigCross ? ((id (*)(id, SEL))gY29OrigCross)(cls, _cmd) : nil;
    if (p && BP_OnName("y24_blurraster")) objc_setAssociatedObject(p, &kY29NoRaster, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return p;
}
static void Y29_BlurContainer(id self, SEL _cmd, id container, id params, long long mode) {
    id layer = (container && BP_OnName("y24_blurraster") && BPY_Responds(params, "shouldRasterize") && !BPY_SEND(BOOL, (), params, "shouldRasterize")) ? Y17_Obj0("blurraster", container, "layer") : nil;
    BOOL hadRaster = NO; double hadScale = 0;
    if (layer) { hadRaster = BPY_SEND(BOOL, (), layer, "shouldRasterize"); hadScale = BPY_SEND(double, (), layer, "rasterizationScale"); }
    if (gY29OrigBlur) ((void (*)(id, SEL, id, id, long long))gY29OrigBlur)(self, _cmd, container, params, mode);
    if (layer) {
        BPY_SEND(void, (double), layer, "setRasterizationScale:", hadScale);
        BPY_SEND(void, (BOOL), layer, "setShouldRasterize:", hadRaster);
    }
}
typedef BOOL (*Y29_ZeroFn)(double);
static void Y29_ApplyRoot(id self, SEL _cmd, void (^completion)(BOOL, BOOL)) {
    if (BP_OnName("y24_blurroot")) {
        static Y29_ZeroFn isZero; static dispatch_once_t once;
        dispatch_once(&once, ^{ isZero = (Y29_ZeroFn)dlsym(RTLD_DEFAULT, "BSFloatIsZero"); if (!isZero) BP_Log(@"[y29] GUARD(blurroot) BSFloatIsZero does not resolve: not applied"); });
        Ivar mi = class_getInstanceVariable(object_getClass(self), "_rootModifier");
        Ivar ci = class_getInstanceVariable(object_getClass(self), "_contentView");
        id modifier = BP_ObjIvar(self, mi), content = BP_ObjIvar(self, ci);
        if (isZero && modifier && content && BPY_Responds(modifier, "rootContentViewBlurRadius")) {
            double radius = BPY_SEND(double, (), modifier, "rootContentViewBlurRadius");
            id filters = Y17_Obj0("blurroot", Y17_Obj0("blurroot", content, "layer"), "filters");
            if (isZero(radius) && !filters) {
                BPY_LOG(@"[y29] root blur radius already zero and no filters: completion without animation");
                if (completion) completion(YES, NO);
                return;
            }
        } else if (!mi || !ci) Y17_GuardOnce("blurroot", self, "_rootModifier / _contentView ivars");
    }
    if (gY29OrigRoot) ((void (*)(id, SEL, void (^)(BOOL, BOOL)))gY29OrigRoot)(self, _cmd, completion);
}

__attribute__((constructor)) static void Y29_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class bp = NSClassFromString(@"SBBlurItemContainerParameters");
        Class vc = NSClassFromString(@"SBFluidSwitcherViewController");
        if (bp && vc && class_getClassMethod(bp, sel_registerName("defaultCrossblurBlurParameters")) && class_getInstanceMethod(vc, sel_registerName("_blurItemContainer:blurParameters:withAnimationUpdateMode:"))) {
            if (!class_getInstanceMethod(bp, sel_registerName("shouldRasterize"))) class_addMethod(bp, sel_registerName("shouldRasterize"), (IMP)Y29_ShouldRasterize, "B16@0:8");
            Class meta = object_getClass((id)bp);
            gY29OrigCross = BPX_Replace(meta, "defaultCrossblurBlurParameters", (IMP)Y29_DefaultCrossblur);
            gY29OrigBlur = BPX_Replace(vc, "_blurItemContainer:blurParameters:withAnimationUpdateMode:", (IMP)Y29_BlurContainer);
            n++;
        } else BP_Log(@"[y29] GUARD(blurraster) SBBlurItemContainerParameters / SBFluidSwitcherViewController blur selectors missing: not installed");
        if (vc && class_getInstanceMethod(vc, sel_registerName("_applyRootContentViewBlurRadiusWithCompletion:"))) {
            gY29OrigRoot = BPX_Replace(vc, "_applyRootContentViewBlurRadiusWithCompletion:", (IMP)Y29_ApplyRoot);
            n++;
        } else BP_Log(@"[y29] GUARD(blurroot) -_applyRootContentViewBlurRadiusWithCompletion: missing: not installed");
        BP_Log(@"[y29] installed %d group(s) (switches y24_blurraster, y24_blurroot)", n);
    }
}
#pragma clang diagnostic pop
