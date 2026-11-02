// Y38SceneUpdater.x : S1 system UI scene family, steps 2 and 3 (DELTA-SWEEP-0.7.9.md Pass 4 section 1): SBSceneSettingsUpdater (updatesGeometry, setActive:withTransitionContext:) and SBSceneManager
// (single scene / pointer UI scene presentation binder methods).  Setup: constructor.  Log prefix "[y38]".  Switch y38_updater (default ON, kill file Backport162.off.y38_updater).
//
// SBSceneSettingsUpdater, 16.2 (16.0 in brackets):
//   -initWithScene:displayConfiguration:traitsRole:persistentIdentifier:level:updatesGeometry: 0x1c74d90b0 stores _updatesGeometry (new ivar byte 0x20; _scene moves 0x20 -> 0x28) BEFORE the 16.0 init sequence
//   (setLevel:, setDisplayConfiguration:, _setPersistenceIdentifier:, _createTraitsParticipantIfNeededWithRole:) [0x1c6059f14 six argument init: always updates geometry]; -updatesGeometry 0x1c74da4cc;
//   -setActive:withTransitionContext: 0x1c74d95f8 (scene activateWithTransitionContext:ctx / deactivateWithTransitionContext:ctx) [-setActive: 0x1c605a988 passed nil];
//   -setDisplayConfiguration: 0x1c74d93c8 same body but +safeUpdateScene:withDisplayConfiguration:updateGeometry:_updatesGeometry [0x1c605a75c: +safeUpdateScene:withDisplayConfiguration:];
//   +safeUpdateScene:withDisplayConfiguration: 0x1c74d98ec is now `updateGeometry:NO` (!) [0x1c605a154 always set the frame]; its only caller is -[SBSceneManager takeScene:fromSceneManager:];
//   +safeUpdateScene:withDisplayConfiguration:updateGeometry: 0x1c74d98f4 (block 0x1c74d99b4: [self __updateSceneSettings:settings forDisplayConfiguration:cfg updateGeometry:geometry]);
//   +__updateSceneSettings:forDisplayConfiguration:updateGeometry: 0x1c74da1f8: [settings isUISubclass] (else assertion "Settings must be an UI subclass"), setScreenReferenceDisplayModeStatus:[SBDisplayReferenceModeMonitor
//   referenceModeStatusForDisplayWithConfiguration:cfg] (a dispatch_once monitor), setDisplayConfiguration:, setFrame:[cfg bounds] only when updateGeometry, then +__updateSceneInsetSettings:forDisplayConfiguration:
//   [0x1c605b01c +__updateSceneInsetAndGeometrySettings: did inset, setDisplayConfiguration:, setFrame: unconditionally].
// SBSceneManager, 16.2: -addSingleSceneToPresentationBinder: 0x1c73ee064 / -removeSingleSceneFromPresentationBinder: 0x1c73ee06c (category ChamoisDevelopmentShimming; tracked collection _boundSingleScenes),
//   -addPointerUISceneToPresentationBinder: 0x1c73ee074 / -remove... 0x1c73ee07c (_boundPointerUIScenes), -_addSceneToPresentationBinder:trackedCollection: 0x1c73ee084 (16.0 -addSceneToPresentationBinder:
//   0x1c5f7324c plus [collection addObject:scene]), -_removeSceneFromPresentationBinder:trackedCollection: 0x1c73ee17c.  The two tracked collections are new ivars (associated sets here).
//
// Port: the 16.0 methods are the 16.2 ones with the new flag; everything below is the 16.2 body.  The per instance flag is an associated object; the 16.0 six argument init keeps its default (YES).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double x, y, w, h; } Y38URect;
static char kY38Geom, kY38SingleSet, kY38PointerSet;
#define Y38U_SET(o, k, v) objc_setAssociatedObject((o), &(k), (v), OBJC_ASSOCIATION_RETAIN_NONATOMIC)
#define Y38U_GET(o, k)    objc_getAssociatedObject((o), &(k))
#define Y38U_NEWRET __attribute__((ns_returns_retained))
#define Y38U_CONSUMED __attribute__((ns_consumed))
#define ADD(c, sel, imp, types) class_addMethod((c), sel_registerName(sel), (IMP)(imp), (types))

static IMP gY38UInit, gY38USetDisplay, gY38USafe2, gY38UInsetGeom;
static __thread int tY38InitGeom = -1;                                         // updatesGeometry of the init that is running (its setDisplayConfiguration: runs before the flag can be stored)
static BOOL Y38U_On(void) { return BP_OnName("y38_updater"); }

// ------------------------------------------------------------------------------------------------ SBSceneSettingsUpdater
static BOOL Y38U_Geometry(id self) {
    id v = Y38U_GET(self, kY38Geom);
    if (v) return [v boolValue];
    return tY38InitGeom >= 0 ? (BOOL)tY38InitGeom : YES;                         // 16.0 initializer: geometry is always updated
}
static BOOL Y38U_UpdatesGeometry(id self, SEL _cmd) { return Y38U_Geometry(self); }                                      // 0x1c74da4cc
static Y38U_NEWRET id Y38U_InitGeom(Y38U_CONSUMED id self, SEL _cmd, id scene, id cfg, id role, id ident, double level, BOOL geometry) {      // 0x1c74d90b0
    int prev = tY38InitGeom;
    tY38InitGeom = geometry ? 1 : 0;
    id me = ((Y38U_NEWRET id (*)(Y38U_CONSUMED id, SEL, id, id, id, id, double))gY38UInit)(self, sel_registerName("initWithScene:displayConfiguration:traitsRole:persistentIdentifier:level:"), scene, cfg, role, ident, level);
    tY38InitGeom = prev;
    if (me) Y38U_SET(me, kY38Geom, @(geometry));
    return me;
}
static void Y38U_SetActiveCtx(id self, SEL _cmd, BOOL active, id ctx) {                                                    // 0x1c74d95f8
    id scene = BPX_IvarObj(self, "_scene");
    if (active) BPX_SetObj1(scene, "activateWithTransitionContext:", ctx);
    else BPX_SetObj1(scene, "deactivateWithTransitionContext:", ctx);
}
static id Y38U_RefMonitor(void) {                                                                                           // block 0x1c74da320
    static id mon; static dispatch_once_t once;
    dispatch_once(&once, ^{ Class c = NSClassFromString(@"SBDisplayReferenceModeMonitor"); mon = c ? [[c alloc] init] : nil; });
    return mon;
}
static void Y38U_UpdateSettings(id cls, SEL _cmd, id settings, id cfg, BOOL geometry) {                                    // 0x1c74da1f8
    if (!BPX_Bool0(settings, "isUISubclass")) { BP_Anomaly("y38-updater", @"Settings must be an UI subclass (16.2 asserts): %@", settings); return; }
    id mon = Y38U_RefMonitor();
    if (mon && [mon respondsToSelector:sel_registerName("referenceModeStatusForDisplayWithConfiguration:")] && [settings respondsToSelector:sel_registerName("setScreenReferenceDisplayModeStatus:")]) {
        long long st = ((long long (*)(id, SEL, id))objc_msgSend)(mon, sel_registerName("referenceModeStatusForDisplayWithConfiguration:"), cfg);
        ((void (*)(id, SEL, long long))objc_msgSend)(settings, sel_registerName("setScreenReferenceDisplayModeStatus:"), st);
    } else BP_Anomaly("y38-updater", @"reference display mode monitor / setter missing: screen reference display mode status not set");
    BPX_SetObj1(settings, "setDisplayConfiguration:", cfg);
    if (geometry) {
        Y38URect b = ((Y38URect (*)(id, SEL))objc_msgSend)(cfg, sel_registerName("bounds"));
        ((void (*)(id, SEL, Y38URect))objc_msgSend)(settings, sel_registerName("setFrame:"), b);
    }
    SEL ins = sel_registerName("__updateSceneInsetSettings:forDisplayConfiguration:");
    if ([cls respondsToSelector:ins]) ((void (*)(id, SEL, id, id))objc_msgSend)(cls, ins, settings, cfg);
}
static void Y38U_SafeGeom(id cls, SEL _cmd, id scene, id cfg, BOOL geometry) {                                            // 0x1c74d98f4
    if (!cfg) return;
    ((void (*)(id, SEL, id, id))objc_msgSend)(cls, sel_registerName("safeUpdateScene:withBlock:"), scene, ^(id settings, id ctx) {                 // block 0x1c74d99b4
        if (BPX_Bool0(settings, "isUISubclass")) Y38U_UpdateSettings(cls, NULL, settings, cfg, geometry);
        else BP_Anomaly("y38-updater", @"safeUpdateScene:withDisplayConfiguration:updateGeometry: block got non UI settings %@", settings);
    });
}
static void Y38U_Safe2(id cls, SEL _cmd, id scene, id cfg) {                                                              // 0x1c74d98ec: updateGeometry:NO
    if (!Y38U_On()) { if (gY38USafe2) ((void (*)(id, SEL, id, id))gY38USafe2)(cls, _cmd, scene, cfg); return; }
    Y38U_SafeGeom(cls, NULL, scene, cfg, NO);
}
static void Y38U_InsetGeom(id cls, SEL _cmd, id settings, id cfg) {                                                       // 16.0 __updateSceneInsetAndGeometrySettings: = the 16.2 body with geometry YES
    if (!Y38U_On()) { if (gY38UInsetGeom) ((void (*)(id, SEL, id, id))gY38UInsetGeom)(cls, _cmd, settings, cfg); return; }
    Y38U_UpdateSettings(cls, NULL, settings, cfg, YES);
}
// -setDisplayConfiguration: 16.2 0x1c74d93c8
static void Y38U_SetDisplay(id self, SEL _cmd, id cfg) {
    if (!Y38U_On()) { if (gY38USetDisplay) ((void (*)(id, SEL, id))gY38USetDisplay)(self, _cmd, cfg); return; }
    Class c = object_getClass(self);
    Ivar ivCfg = BP_IvarLookup(c, "_displayConfiguration");
    id cur = BP_ObjIvar(self, ivCfg);
    if ((cur == nil && cfg == nil) || [cur isEqual:cfg]) return;
    BP_SetObjIvar(self, ivCfg, [cfg copy]);
    BPX_Obj0(BPX_IvarObj(self, "_sceneTraitsDelegate"), "invalidate");
    BPX_Obj0(BPX_IvarObj(self, "_traitsParticipant"), "invalidate");
    id scene = BPX_IvarObj(self, "_scene");
    ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)((id)object_getClass(self), sel_registerName("safeUpdateScene:withDisplayConfiguration:updateGeometry:"), scene, cfg, Y38U_Geometry(self));
    ((void (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("_createTraitsParticipantIfNeededWithRole:"), BPX_IvarObj(self, "_traitsRole"));
    BPX_SetBool1(BPX_IvarObj(self, "_sceneTraitsDelegate"), "setOrientationActuationAnimatable:", cfg != nil);
}

// ------------------------------------------------------------------------------------------------ SBSceneManager
static NSMutableSet *Y38U_Set(id mgr, const void *key) {
    NSMutableSet *s = objc_getAssociatedObject(mgr, key);
    if (!s) { s = [NSMutableSet set]; objc_setAssociatedObject(mgr, key, s, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return s;
}
static void Y38U_BinderAdd(id self, SEL _cmd, id scene, NSMutableSet *collection) {                                        // 0x1c73ee084
    Ivar st = BP_IvarLookup(object_getClass(self), "_state");
    long long state = st ? *(long long *)((char *)(__bridge void *)self + ivar_getOffset(st)) : 0;
    if (state != 0) { BP_Anomaly("y38-binder", @"cannot respond to non-destruction scene events after the scene manager invalidated (16.2 asserts): add %@", scene); return; }
    BPX_Obj1(BPX_IvarObj(self, "_boundScenes"), "addObject:", scene);
    BPX_Obj1(BPX_IvarObj(self, "_presentationBinder"), "addScene:", scene);
    [collection addObject:scene];
    if (BPX_Obj0(scene, "workspaceIdentifier")) BPX_Obj1(BPX_IvarObj(self, "_workspaceScenes"), "addObject:", scene);
    BPX_Obj1(BPX_IvarObj(self, "_allScenes"), "addObject:", scene);
}
static void Y38U_BinderRemove(id self, SEL _cmd, id scene, NSMutableSet *collection) {                                     // 0x1c73ee17c
    Ivar st = BP_IvarLookup(object_getClass(self), "_state");
    long long state = st ? *(long long *)((char *)(__bridge void *)self + ivar_getOffset(st)) : 0;
    if (state != 0) { BP_Anomaly("y38-binder", @"cannot respond to non-destruction scene events after the scene manager invalidated (16.2 asserts): remove %@", scene); return; }
    BPX_Obj1(BPX_IvarObj(self, "_boundScenes"), "removeObject:", scene);
    BPX_Obj1(BPX_IvarObj(self, "_presentationBinder"), "removeScene:", scene);
    [collection removeObject:scene];
    if (BPX_Obj0(scene, "workspaceIdentifier")) BPX_Obj1(BPX_IvarObj(self, "_workspaceScenes"), "removeObject:", scene);
    BPX_Obj1(BPX_IvarObj(self, "_allScenes"), "removeObject:", scene);
}
static void Y38U_AddSingle(id self, SEL _cmd, id scene) { Y38U_BinderAdd(self, NULL, scene, Y38U_Set(self, &kY38SingleSet)); }           // 0x1c73ee064
static void Y38U_RemoveSingle(id self, SEL _cmd, id scene) { Y38U_BinderRemove(self, NULL, scene, Y38U_Set(self, &kY38SingleSet)); }  // 0x1c73ee06c
static void Y38U_AddPointer(id self, SEL _cmd, id scene) { Y38U_BinderAdd(self, NULL, scene, Y38U_Set(self, &kY38PointerSet)); }       // 0x1c73ee074
static void Y38U_RemovePointer(id self, SEL _cmd, id scene) { Y38U_BinderRemove(self, NULL, scene, Y38U_Set(self, &kY38PointerSet)); } // 0x1c73ee07c
static void Y38U_AddTracked(id self, SEL _cmd, id scene, id collection) { Y38U_BinderAdd(self, NULL, scene, collection); }
static void Y38U_RemoveTracked(id self, SEL _cmd, id scene, id collection) { Y38U_BinderRemove(self, NULL, scene, collection); }

__attribute__((constructor)) static void Y38U_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class up = NSClassFromString(@"SBSceneSettingsUpdater");
        Class upm = up ? object_getClass(up) : Nil;
        if (up && upm && class_getInstanceMethod(up, sel_registerName("initWithScene:displayConfiguration:traitsRole:persistentIdentifier:level:")) && class_getInstanceMethod(up, sel_registerName("setDisplayConfiguration:")) &&
            class_getInstanceMethod(upm, sel_registerName("safeUpdateScene:withDisplayConfiguration:")) && class_getInstanceMethod(upm, sel_registerName("safeUpdateScene:withBlock:")) &&
            class_getInstanceMethod(upm, sel_registerName("__updateSceneInsetSettings:forDisplayConfiguration:"))) {
            ADD(up, "initWithScene:displayConfiguration:traitsRole:persistentIdentifier:level:updatesGeometry:", Y38U_InitGeom, "@60@0:8@16@24@32@40d48B56");
            ADD(up, "updatesGeometry", Y38U_UpdatesGeometry, "B16@0:8");
            ADD(up, "setActive:withTransitionContext:", Y38U_SetActiveCtx, "v28@0:8B16@20");
            ADD(upm, "safeUpdateScene:withDisplayConfiguration:updateGeometry:", Y38U_SafeGeom, "v36@0:8@16@24B32");
            ADD(upm, "__updateSceneSettings:forDisplayConfiguration:updateGeometry:", Y38U_UpdateSettings, "v36@0:8@16@24B32");
            gY38UInit = method_getImplementation(class_getInstanceMethod(up, sel_registerName("initWithScene:displayConfiguration:traitsRole:persistentIdentifier:level:")));      // the 16.0 init is called as is
            gY38USetDisplay = BPX_Replace(up, "setDisplayConfiguration:", (IMP)Y38U_SetDisplay);
            gY38USafe2 = BPX_Replace(upm, "safeUpdateScene:withDisplayConfiguration:", (IMP)Y38U_Safe2);
            if (class_getInstanceMethod(upm, sel_registerName("__updateSceneInsetAndGeometrySettings:forDisplayConfiguration:"))) gY38UInsetGeom = BPX_Replace(upm, "__updateSceneInsetAndGeometrySettings:forDisplayConfiguration:", (IMP)Y38U_InsetGeom);
            n++;
        } else BP_Anomaly("y38-install", @"[y38] SBSceneSettingsUpdater selectors missing: updater port not installed");
        Class sm = NSClassFromString(@"SBSceneManager");
        if (sm && class_getInstanceMethod(sm, sel_registerName("addSceneToPresentationBinder:"))) {
            ADD(sm, "addSingleSceneToPresentationBinder:", Y38U_AddSingle, "v24@0:8@16");
            ADD(sm, "removeSingleSceneFromPresentationBinder:", Y38U_RemoveSingle, "v24@0:8@16");
            ADD(sm, "addPointerUISceneToPresentationBinder:", Y38U_AddPointer, "v24@0:8@16");
            ADD(sm, "removePointerUISceneFromPresentationBinder:", Y38U_RemovePointer, "v24@0:8@16");
            ADD(sm, "_addSceneToPresentationBinder:trackedCollection:", Y38U_AddTracked, "v32@0:8@16@24");
            ADD(sm, "_removeSceneFromPresentationBinder:trackedCollection:", Y38U_RemoveTracked, "v32@0:8@16@24");
            n++;
        } else BP_Anomaly("y38-install", @"[y38] SBSceneManager addSceneToPresentationBinder: missing: single scene binder methods not added");
        BP_Log(@"[y38] updater/binder installed %d group(s) (switch y38_updater)", n);
    }
}
#pragma clang diagnostic pop
