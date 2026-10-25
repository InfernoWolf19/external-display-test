// Y11Modifiers.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): transition modifiers whose 16.2 versions only treat THEIR layout specially.  Setup: constructor.  Log prefix "[y11]".
//
//  y11_removal  SBEntityRemovalCrossblurSwitcherModifier and SBEntityRemovalSlideOffscreenSwitcherModifier (the transitions that remove one app layout: 16.2 0x1c760bd3c.. / 0x1c7414268..).  16.0 answered
//               the removal geometry for EVERY index (container bounds frame, final scale, final alpha, layout settings for every element, visible layouts = only the removed one), which is right for
//               a full screen deck but makes every other window of a Stage Manager stage slide / blur away with the removed one.  16.2 applies the removal values only to the removed layout
//               (-[NSObject isEqual:] on _appLayout) while it is not in the preparation phase and asks the super class for everything else:
//                 visibleAppLayouts           super set plus _appLayout (16.0: just _appLayout)
//                 frameForIndex:              removed layout, not preparing: the bounding box of its overlapping model under Stage Manager (+ the slide offset of the Slide variant), the
//                                             container bounds otherwise; every other case: super
//                 scaleForIndex: / opacityForLayoutRole:inAppLayout:atIndex: (Crossblur only): the 16.0 formulas for the removed layout while not preparing, super for the rest
//                 animationAttributesForLayoutElement:   the 16.0 attributes only for the app layout element that equals _appLayout, super for the rest
//               Ported: wrappers that run the 16.0 body in exactly those cases and the super implementation otherwise; Stage Manager frame = overlapping model bounding box (the slide offset of the
//               16.0 body is kept: it is the difference of the 16.0 result and the container bounds).  Reached from -[SBContinuousExposeRootSwitcherModifier transitionModifierForMainTransitionEvent:].
//  y11_tapreq   SBShelfCarouselSwitcherModifier / SBSlideOverPeekSwitcherModifier / SBPeekSplitViewRoutingSwitcherModifier -handleTapAppLayoutEvent: 16.2 (0x1c78e4460 / 0x1c75dda00 / 0x1c74e7108) build
//               their request with +[SBSwitcherTransitionRequest requestForTapAppLayoutEvent:] (appLayout + activatingDisplayItem of the tapped role + pointer source) instead of
//               +requestForActivatingAppLayout:.  G1C.x adds requestForTapAppLayoutEvent: to 16.0; here the old request is replaced by it for the duration of those three handlers.
//               Not ported: -[SBPeekSplitViewRoutingSwitcherModifier responseForProposedChildResponse:childModifier:event:] 16.2 sets activatingDisplayItem on its request too (Split View peek only).
// Needs a device: with a window of the stage being removed (app closed from the switcher) the other windows stay in place; tapping a window in the shelf activates that window.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y11Rect;      // CGRect (HFA, d0..d3)

// ---- one set of IMPs per class ----
typedef struct {
    IMP oVisible, oFrame, oScale, oAnim, oOpacity;       // the 16.0 implementations
    IMP sVisible, sFrame, sScale, sAnim, sOpacity;       // the super class implementations
    Class cls;
} Y11Set;
static Y11Set gSlide, gBlur;

static Y11Set *Y11_SetFor(id self) { return [self isKindOfClass:gSlide.cls] ? &gSlide : &gBlur; }
static id Y11_RemovedLayout(id self) {
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_appLayout");
    return iv ? object_getIvar(self, iv) : nil;
}
// 16.2 test of the first lines of every method: this index is the removed layout and the preparation phase is over
static BOOL Y11_IsRemovedNow(id self, unsigned long long i) {
    id removed = Y11_RemovedLayout(self);
    NSArray *ls = BPX_Obj0(self, "appLayouts");
    if (!removed || i >= [ls count]) return NO;
    return [removed isEqual:[ls objectAtIndex:i]] && !BPX_Bool0(self, "isPreparingLayout");
}
static id Y11_Model(id self, id layout) {
    if (BPY_Responds(self, "overlappingModelForAppLayout:")) return BPX_Obj1(self, "overlappingModelForAppLayout:", layout);
    id calc = BPX_Obj0(self, "displayItemLayoutAttributesCalculator");
    if (!calc || !layout) return nil;
    id container = BPX_Obj1(self, "appLayoutContainingAppLayout:", layout) ?: layout;
    long long ori = BPX_LL0(self, "switcherInterfaceOrientation");
    id attrs = BPX_Obj0(self, "chamoisLayoutAttributes");
    double dock = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("floatingDockHeight"));
    double scale = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("screenScale"));
    Y11Rect bounds = ((Y11Rect (*)(id, SEL))objc_msgSend)(self, sel_registerName("containerViewBounds"));
    BOOL strip = BPX_Bool0(self, "prefersStripHidden"), dockH = BPX_Bool0(self, "prefersDockHidden");
    return ((id (*)(id, SEL, id, long long, id, double, double, Y11Rect, BOOL, BOOL))objc_msgSend)(calc, sel_registerName("overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:"),
                                                                                                  container, ori, attrs, dock, scale, bounds, strip, dockH);
}

// visibleAppLayouts
static id Y11_Visible(id self, SEL _cmd) {
    Y11Set *s = Y11_SetFor(self);
    id removed = Y11_RemovedLayout(self);
    if (BP_OnName("y11_removal") && s->sVisible && removed) {
        id base = ((id (*)(id, SEL))s->sVisible)(self, _cmd);
        if ([base respondsToSelector:@selector(setByAddingObject:)]) return [base setByAddingObject:removed];
    }
    return s->oVisible ? ((id (*)(id, SEL))s->oVisible)(self, _cmd) : nil;
}
// frameForIndex:
static Y11Rect Y11_Frame(id self, SEL _cmd, unsigned long long i) {
    Y11Set *s = Y11_SetFor(self);
    Y11Rect z = {0, 0, 0, 0};
    if (BP_OnName("y11_removal") && s->sFrame) {
        if (!Y11_IsRemovedNow(self, i)) return ((Y11Rect (*)(id, SEL, unsigned long long))s->sFrame)(self, _cmd, i);
        Y11Rect r = s->oFrame ? ((Y11Rect (*)(id, SEL, unsigned long long))s->oFrame)(self, _cmd, i) : z;       // container bounds (+ the slide offset of the Slide variant)
        if (BPX_Bool0(self, "isChamoisWindowingUIEnabled")) {
            id model = Y11_Model(self, Y11_RemovedLayout(self));
            if (model && BPY_Responds(model, "boundingBox")) {
                Y11Rect cb = ((Y11Rect (*)(id, SEL))objc_msgSend)(self, sel_registerName("containerViewBounds"));
                Y11Rect bb = ((Y11Rect (*)(id, SEL))objc_msgSend)(model, sel_registerName("boundingBox"));
                bb.y += r.y - cb.y;
                return bb;
            }
        }
        return r;
    }
    return s->oFrame ? ((Y11Rect (*)(id, SEL, unsigned long long))s->oFrame)(self, _cmd, i) : z;
}
// scaleForIndex:
static double Y11_Scale(id self, SEL _cmd, unsigned long long i) {
    Y11Set *s = Y11_SetFor(self);
    if (BP_OnName("y11_removal") && s->sScale && !Y11_IsRemovedNow(self, i)) return ((double (*)(id, SEL, unsigned long long))s->sScale)(self, _cmd, i);
    return s->oScale ? ((double (*)(id, SEL, unsigned long long))s->oScale)(self, _cmd, i) : 1.0;
}
// animationAttributesForLayoutElement:
static id Y11_Anim(id self, SEL _cmd, id element) {
    Y11Set *s = Y11_SetFor(self);
    if (BP_OnName("y11_removal") && s->sAnim) {
        id removed = Y11_RemovedLayout(self);
        BOOL mine = BPX_LL0(element, "switcherLayoutElementType") == 0 && removed && [element isEqual:removed];
        if (!mine) return ((id (*)(id, SEL, id))s->sAnim)(self, _cmd, element);
    }
    return s->oAnim ? ((id (*)(id, SEL, id))s->oAnim)(self, _cmd, element) : nil;
}
// opacityForLayoutRole:inAppLayout:atIndex: (Crossblur)
static double Y11_Opacity(id self, SEL _cmd, long long role, id layout, unsigned long long i) {
    Y11Set *s = Y11_SetFor(self);
    if (BP_OnName("y11_removal") && s->sOpacity) {
        id removed = Y11_RemovedLayout(self);
        if (!(removed && layout && [removed isEqual:layout] && !BPX_Bool0(self, "isPreparingLayout"))) return ((double (*)(id, SEL, long long, id, unsigned long long))s->sOpacity)(self, _cmd, role, layout, i);
    }
    return s->oOpacity ? ((double (*)(id, SEL, long long, id, unsigned long long))s->oOpacity)(self, _cmd, role, layout, i) : 1.0;
}

static void Y11_Patch(Y11Set *s, Class c, BOOL withOpacity) {
    s->cls = c;
    Class sup = class_getSuperclass(c);
    #define Y11_SUPER(SEL_NAME) ({ Method m_ = sup ? class_getInstanceMethod(sup, sel_registerName(SEL_NAME)) : NULL; m_ ? method_getImplementation(m_) : NULL; })
    s->sVisible = Y11_SUPER("visibleAppLayouts");
    s->sFrame = Y11_SUPER("frameForIndex:");
    s->sScale = Y11_SUPER("scaleForIndex:");
    s->sAnim = Y11_SUPER("animationAttributesForLayoutElement:");
    s->sOpacity = Y11_SUPER("opacityForLayoutRole:inAppLayout:atIndex:");
    #undef Y11_SUPER
    s->oVisible = BPX_Replace(c, "visibleAppLayouts", (IMP)Y11_Visible);
    s->oFrame = BPX_Replace(c, "frameForIndex:", (IMP)Y11_Frame);
    s->oScale = BPX_Replace(c, "scaleForIndex:", (IMP)Y11_Scale);
    s->oAnim = BPX_Replace(c, "animationAttributesForLayoutElement:", (IMP)Y11_Anim);
    if (withOpacity) s->oOpacity = BPX_Replace(c, "opacityForLayoutRole:inAppLayout:atIndex:", (IMP)Y11_Opacity);
}

// ---- y11_tapreq ----
static __thread __unsafe_unretained id tY11Tap;                 // the tap event while one of the three handlers runs
static IMP gY11OrigReq, gY11OrigShelf, gY11OrigSlide, gY11OrigPeek;
static id Y11_ReqActivating(id cls, SEL _cmd, id layout) {
    id ev = tY11Tap;
    if (ev && layout && BP_OnName("y11_tapreq") && BPY_Responds((id)cls, "requestForTapAppLayoutEvent:") && [layout isEqual:BPX_Obj0(ev, "appLayout")]) {
        id r = BPX_Obj1((id)cls, "requestForTapAppLayoutEvent:", ev);
        if (r) return r;
    }
    return gY11OrigReq ? ((id (*)(id, SEL, id))gY11OrigReq)(cls, _cmd, layout) : nil;
}
static id Y11_HandleTap(IMP orig, id self, SEL _cmd, id event) {
    id saved = tY11Tap;
    tY11Tap = event;
    id r = orig ? ((id (*)(id, SEL, id))orig)(self, _cmd, event) : nil;
    tY11Tap = saved;
    return r;
}
static id Y11_ShelfTap(id self, SEL _cmd, id e) { return Y11_HandleTap(gY11OrigShelf, self, _cmd, e); }
static id Y11_SlideTap(id self, SEL _cmd, id e) { return Y11_HandleTap(gY11OrigSlide, self, _cmd, e); }
static id Y11_PeekTap(id self, SEL _cmd, id e) { return Y11_HandleTap(gY11OrigPeek, self, _cmd, e); }

__attribute__((constructor)) static void Y11_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class sl = NSClassFromString(@"SBEntityRemovalSlideOffscreenSwitcherModifier"), bl = NSClassFromString(@"SBEntityRemovalCrossblurSwitcherModifier");
        if (sl && bl && class_getInstanceVariable(sl, "_appLayout") && class_getInstanceVariable(bl, "_appLayout") && class_getInstanceMethod(sl, sel_registerName("frameForIndex:")) &&
            class_getInstanceMethod(bl, sel_registerName("opacityForLayoutRole:inAppLayout:atIndex:")) && class_getInstanceMethod(sl, sel_registerName("animationAttributesForLayoutElement:"))) {
            Y11_Patch(&gSlide, sl, NO);
            Y11_Patch(&gBlur, bl, YES);
            n++;
        }
        Class rq = NSClassFromString(@"SBSwitcherTransitionRequest");
        Class sh = NSClassFromString(@"SBShelfCarouselSwitcherModifier"), so = NSClassFromString(@"SBSlideOverPeekSwitcherModifier"), pk = NSClassFromString(@"SBPeekSplitViewRoutingSwitcherModifier");
        if (rq && class_getClassMethod(rq, sel_registerName("requestForActivatingAppLayout:")) && sh && so && pk) {
            gY11OrigReq = BPX_Replace(object_getClass((id)rq), "requestForActivatingAppLayout:", (IMP)Y11_ReqActivating);
            gY11OrigShelf = BPX_Replace(sh, "handleTapAppLayoutEvent:", (IMP)Y11_ShelfTap);
            gY11OrigSlide = BPX_Replace(so, "handleTapAppLayoutEvent:", (IMP)Y11_SlideTap);
            gY11OrigPeek = BPX_Replace(pk, "handleTapAppLayoutEvent:", (IMP)Y11_PeekTap);
            n++;
        }
        BP_Log(@"[y11] installed %d of 2 groups (switches y11_removal, y11_tapreq)", n);
    }
}
#pragma clang diagnostic pop
