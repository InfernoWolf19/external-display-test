// Y8Layout.x : delta sweep family F3 (specs/DELTA-SWEEP-0.7.9.md): per display answers of the layout model.  Setup: constructor.  Log prefix "[y8]".
//
//  y8_extorient  SBMainDisplayLayoutState gained _isDisplayExternal (16.2 ivar +0x3a, -isDisplayExternal 0x1c7722920, set by the layout state manager from the request's display).  Its
//                -_defaultInterfaceOrientation (instance method, 16.2 0x1c7721500) answers Portrait (1) for an external display state and the main display's active interface orientation
//                otherwise (SBLayoutState's own answer is 1, 0x1c766f718); -[SBLayoutState interfaceOrientation] 16.2 0x1c7291884 asks it when the state has no orientation of its own.  16.0 had
//                only the class method +_defaultInterfaceOrientation (0x1c5e643ac: the main display's active orientation, 0x1c5e1f9a8 -interfaceOrientation calls it), so an external state without an
//                orientation reported the iPad's rotation to the Stage Manager frame code (the layout state orientation drives coordinate spaces and scene entity frames under Stage Manager).
//                Ported: -isDisplayExternal derived from displayOrdinal (1 = external, the ordinal of -[SBAppLayout preferredDisplayOrdinal]) and a wrapper of -interfaceOrientation that
//                answers 1 for such a state when its own orientation is 0.
//  y8_insethome  -[SBAppLayout isInsetForHomeAffordance] 16.2 0x1c77270e8 (16.0 0x1c628e03c): on the iPad idiom the per item inset test only runs when the layout's preferred window scene
//                (-_preferredWindowScene, new 0x1c77272bc: the external scene for ordinal 1, else the main scene) is NOT in Stage Manager; with Stage Manager the answer is NO (a window has no
//                home indicator inset, in particular not on the monitor).  16.0 always ran the item test.  Ported: the new method and a wrapper.
//  y8_spotlight  -[SBSpotlightCrossblurToFullscreenSwitcherModifier frameForIndex:] 16.2 0x1c734746c (16.0 0x1c5ed32d8: the container bounds for the layout being opened): with Stage Manager the opened
//                window's own bounding box ([[calculator overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:
//                prefersDockHidden:] boundingBox]); visibleAppLayouts 16.2 0x1c7347aac adds the opened layout to the super class's visible set (16.0: only the opened layout, so the
//                other windows of the stage vanished behind the crossblur).  Opening an app from Spotlight (iPad) with Stage Manager: the window grows from / to its stage frame.
//  y8_stateeq    -[SBMainDisplayLayoutState isEqual:] 16.2 0x1c72a0934 / hash 0x1c7721ad0 also compare the display ordinal (and isDisplayExternal, derived from it here): two layout states of different
//                displays with the same elements are not equal.  Ported for -isEqual: (equal only when the ordinals match too); the hash keeps the 16.0 value (equal objects still hash equal).
// Needs a device: with the monitor in Stage Manager open a window on it (iPad held portrait and landscape): its frame is not rotated or inset by the iPad's state.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y8Rect;       // CGRect (HFA, d0..d3)
static IMP gY8OrigOrient, gY8OrigInset, gY8OrigSFrame, gY8OrigSVisible;
static IMP gY8SuperVisible, gY8OrigEq;

// -[SBMainDisplayLayoutState isDisplayExternal]
static BOOL Y8_IsExternal(id self, SEL _cmd) { return BPX_LL0(self, "displayOrdinal") == 1; }

// -[SBLayoutState interfaceOrientation]   (hot: asked for every frame during layout / drag; the ivar offset is looked up once, the switch is read only for a state without an orientation)
static long long Y8_Orient(id self, SEL _cmd) {
    static ptrdiff_t off = -2;                                  // _interfaceOrientation of SBLayoutState (+0x8 in 20A8372); -1 = not found
    if (off == -2) { Ivar iv = class_getInstanceVariable(NSClassFromString(@"SBLayoutState"), "_interfaceOrientation"); off = iv ? ivar_getOffset(iv) : -1; }
    if (off >= 0 && *(long long *)((uint8_t *)(__bridge void *)self + off) == 0 && BP_OnName("y8_extorient") &&
        BPY_Responds(self, "isDisplayExternal") && BPX_Bool0(self, "isDisplayExternal")) return 1;       // 16.2 -[SBMainDisplayLayoutState _defaultInterfaceOrientation] 0x1c7721500
    return gY8OrigOrient ? ((long long (*)(id, SEL))gY8OrigOrient)(self, _cmd) : 0;
}

// -[SBAppLayout _preferredWindowScene]  16.2 0x1c77272bc
static id Y8_PreferredScene(id self, SEL _cmd) {
    id main = nil, ext = nil;
    id scenes = BPX_Obj0(BPX_WindowSceneManager(), "connectedWindowScenes");
    for (id s in scenes) {
        if (!main && BPX_Bool0(s, "isMainDisplayWindowScene")) main = s;
        if (!ext && BPX_Bool0(s, "isExternalDisplayWindowScene")) ext = s;
    }
    return (ext && BPX_LL0(self, "preferredDisplayOrdinal") == 1) ? ext : main;
}
// -[SBAppLayout isInsetForHomeAffordance]
static BOOL Y8_Inset(id self, SEL _cmd) {
    if (BP_OnName("y8_insethome")) {
        long long idiom = BPX_LL0(BPX_Obj0((id)NSClassFromString(@"UIDevice"), "currentDevice"), "userInterfaceIdiom");
        if ((idiom & ~4LL) != 1) return NO;                                    // 16.2 0x1c7727144: the per item test only runs on the iPad idiom (1 / 5)
        id sc = BPX_Obj0(BPX_Obj0(self, "_preferredWindowScene"), "switcherController");
        if (sc && BPX_Bool0(sc, "isChamoisWindowingUIEnabled")) return NO;
    }
    return gY8OrigInset ? ((BOOL (*)(id, SEL))gY8OrigInset)(self, _cmd) : NO;
}

// -[SBSpotlightCrossblurToFullscreenSwitcherModifier frameForIndex:]
static Y8Rect Y8_SpotFrame(id self, SEL _cmd, unsigned long long i) {
    if (BP_OnName("y8_spotlight") && BPY_SEND(BOOL, (unsigned long long), self, "_isToAppLayoutAtIndex:", i) && BPX_Bool0(self, "isChamoisWindowingUIEnabled")) {
        id layouts = BPX_Obj0(self, "appLayouts");
        id layout = i < [layouts count] ? [layouts objectAtIndex:i] : nil;
        if (layout) {
            id calc = BPX_Obj0(self, "displayItemLayoutAttributesCalculator");
            id container = BPX_Obj1(self, "appLayoutContainingAppLayout:", layout);
            long long ori = BPX_LL0(self, "switcherInterfaceOrientation");
            id attrs = BPX_Obj0(self, "chamoisLayoutAttributes");
            double dock = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("floatingDockHeight"));
            double scale = ((double (*)(id, SEL))objc_msgSend)(self, sel_registerName("screenScale"));
            Y8Rect bounds = ((Y8Rect (*)(id, SEL))objc_msgSend)(self, sel_registerName("containerViewBounds"));
            BOOL strip = BPX_Bool0(self, "prefersStripHidden"), dockH = BPX_Bool0(self, "prefersDockHidden");
            id model = ((id (*)(id, SEL, id, long long, id, double, double, Y8Rect, BOOL, BOOL))objc_msgSend)(calc, sel_registerName("overlappingModelForAppLayout:containerOrientation:chamoisLayoutAttributes:floatingDockHeight:screenScale:bounds:prefersStripHidden:prefersDockHidden:"),
                                                                                                           container, ori, attrs, dock, scale, bounds, strip, dockH);
            if (model) return ((Y8Rect (*)(id, SEL))objc_msgSend)(model, sel_registerName("boundingBox"));
        }
    }
    Y8Rect z = {0, 0, 0, 0};
    return gY8OrigSFrame ? ((Y8Rect (*)(id, SEL, unsigned long long))gY8OrigSFrame)(self, _cmd, i) : z;
}
// -[SBSpotlightCrossblurToFullscreenSwitcherModifier visibleAppLayouts]
static id Y8_SpotVisible(id self, SEL _cmd) {
    if (BP_OnName("y8_spotlight") && gY8SuperVisible) {
        id base = ((id (*)(id, SEL))gY8SuperVisible)(self, _cmd);
        Ivar iv = NULL;
        for (Class c = object_getClass(self); c && !iv; c = class_getSuperclass(c)) iv = class_getInstanceVariable(c, "_toAppLayout");
        id to = iv ? object_getIvar(self, iv) : nil;
        if (to && [base respondsToSelector:@selector(setByAddingObject:)]) return [base setByAddingObject:to];
    }
    return gY8OrigSVisible ? ((id (*)(id, SEL))gY8OrigSVisible)(self, _cmd) : nil;
}

// -[SBMainDisplayLayoutState isEqual:]
static BOOL Y8_StateEq(id self, SEL _cmd, id other) {
    BOOL r = gY8OrigEq ? ((BOOL (*)(id, SEL, id))gY8OrigEq)(self, _cmd, other) : NO;
    if (r && other && other != self && BP_OnName("y8_stateeq") && [other isKindOfClass:[self class]]) return BPX_LL0(self, "displayOrdinal") == BPX_LL0(other, "displayOrdinal");
    return r;
}

__attribute__((constructor)) static void Y8_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class ls = NSClassFromString(@"SBLayoutState"), ml = NSClassFromString(@"SBMainDisplayLayoutState"), al = NSClassFromString(@"SBAppLayout");
        if (!ls || !ml || !al || !class_getInstanceMethod(ls, sel_registerName("interfaceOrientation")) || !class_getInstanceMethod(al, sel_registerName("isInsetForHomeAffordance")) ||
            !class_getInstanceMethod(ml, sel_registerName("displayOrdinal"))) {
            BP_Log(@"[y8] NOT installed (class or selector missing)");
            return;
        }
        if (!class_getInstanceMethod(ml, sel_registerName("isDisplayExternal"))) class_addMethod(ml, sel_registerName("isDisplayExternal"), (IMP)Y8_IsExternal, "B16@0:8");
        if (!class_getInstanceMethod(al, sel_registerName("_preferredWindowScene"))) class_addMethod(al, sel_registerName("_preferredWindowScene"), (IMP)Y8_PreferredScene, "@16@0:8");
        gY8OrigEq = BPX_Replace(ml, "isEqual:", (IMP)Y8_StateEq);
        gY8OrigOrient = BPX_Replace(ls, "interfaceOrientation", (IMP)Y8_Orient);
        gY8OrigInset = BPX_Replace(al, "isInsetForHomeAffordance", (IMP)Y8_Inset);
        Class sp = NSClassFromString(@"SBSpotlightCrossblurToFullscreenSwitcherModifier");
        if (sp && class_getInstanceMethod(sp, sel_registerName("frameForIndex:")) && class_getInstanceMethod(sp, sel_registerName("_isToAppLayoutAtIndex:"))) {
            Method sm = class_getInstanceMethod(class_getSuperclass(sp), sel_registerName("visibleAppLayouts"));
            gY8SuperVisible = sm ? method_getImplementation(sm) : NULL;
            gY8OrigSFrame = BPX_Replace(sp, "frameForIndex:", (IMP)Y8_SpotFrame);
            gY8OrigSVisible = BPX_Replace(sp, "visibleAppLayouts", (IMP)Y8_SpotVisible);
        }
        BP_Log(@"[y8] installed (switches y8_extorient, y8_insethome, y8_spotlight, y8_stateeq)");
    }
}
#pragma clang diagnostic pop
