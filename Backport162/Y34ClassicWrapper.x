// Y34ClassicWrapper.x : delta sweep pass 4, SBDeviceApplicationSceneClassicWrapperView of iPadOS 16.2.  Setup: constructor.  Log prefix "[y34]".
//
//  y34_classicwrapper  The 16.2 wrapper view differs from 16.0 in four ivars (_appSwitcherDefaults, _chamoisEnabledObserver, _chamoisSettings, _canRasterize), the scaled app rasterization
//    and a rewritten layout.  A 16.0 instance has no room for the ivars, so the 16.2 class is a RUNTIME SUBCLASS "Y34ClassicWrapperView" (Y34Ext.h) with the ivars under their 16.2 names;
//    Y34ClassicSupport.x allocates it (the 16.2 -_createClassicWrapperViewIfNecessaryForHostView: asks for the class by name, Y34LiftRT.c answers the subclass).  Its methods (16.2 addresses):
//      -initWithSceneHandle:                      0x1c78cfc5c  hand ported (the machine code builds a block): super init with CGRectZero, scene handle, the host positioning view
//                                                                 (alloc / initWithFrame:[self bounds], addSubview:), minification filter kCAFilterBox / magnification filter kCAFilterLinearlySampledLinear on its layer
//                                                                 (the two constants the machine code loads), and when SBFIsChamoisWindowingUIAvailable(): [[SBAppSwitcherDomain rootSettings] chamoisSettings]
//                                                                 (+ addKeyObserver:, _canRasterize = rasterizeScaledApps), [[SBDefaults localDefaults] appSwitcherDefaults], and an
//                                                                 observeDefault:@"chamoisWindowingEnabled" onQueue:main withBlock:{ [weakSelf _windowingModeChanged] } observer
//      -dealloc 0x1c78cff4c, -.cxx_destruct (the new ivars), -settings:changedValueForKey: 0x1c78d0b58, -_windowingModeChanged 0x1c78d0bd4 (empty), -_shouldRasterizePositioningLayer 0x1c78d0bd8
//                                                                 hand ported (os_log debug lines dropped), -layoutSubviews 0x1c78d0208 recompiled from the machine code (Y34ClassicWrapperLift.c)
//    The other 16.2 methods of the class (addContentView:, removeContentView:, setOrientation:, accessors, _effectiveSceneBounds, _isProbablyScreenSized, wantsBlackBackground) are
//    identical to 16.0 (tools/a2c/tests/mdiff.py: equal after ivar names), +shouldUseWrapperViewForSceneHandle: is Y31Misc.x y24_wrapperview.
//  Any missing piece (class, symbol) leaves the 16.0 wrapper view in place: ANOMALY y34 once.
// Needs a device: a classic (iPhone-only) app in a Stage Manager window scaled down: the positioning layer is rasterized only while the chamois rasterizeScaledApps setting is on.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"
#import "Y34Ext.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern void objc_msgSendSuper2(void);      // private (not in the SDK headers): the machine code of 16.2 uses it for [super initWithFrame:]
extern void y34_wv_layout(void *self, void *cmd);
extern const char *y34_classicwrapper_preflight(void);

static Class gWvBase, gWvExt;
static Ivar gIvDefaults, gIvObserver, gIvSettings, gIvRaster, gIvPositioning, gIvSceneHandle;
static BOOL (*gAvailable)(void);
static BOOL (*gFloatIsOne)(double);
static NSString *const *gFilterMin, *const *gFilterMag;

static BOOL Y34_Raster(id self) { return gIvRaster ? *((BOOL *)((char *)(__bridge void *)self + ivar_getOffset(gIvRaster))) : NO; }
static void Y34_SetRaster(id self, BOOL v) { if (gIvRaster) *((BOOL *)((char *)(__bridge void *)self + ivar_getOffset(gIvRaster))) = v; }

static void Y34_WvLayout(id self, SEL _cmd) { y34_wv_layout((__bridge void *)self, (void *)_cmd); }
static void Y34_WvWindowingModeChanged(id self, SEL _cmd) { }       // 0x1c78d0bd4: ret

static void Y34_WvSettings(id self, SEL _cmd, id settings, id key) {   // 0x1c78d0b58
    id mine = Y34_ObjGet(self, gIvSettings);
    if (mine != settings) return;
    if (![key isEqualToString:@"rasterizeScaledApps"]) return;
    Y34_SetRaster(self, BPY_SEND(BOOL, (), mine, "rasterizeScaledApps"));
    BPY_SEND(void, (), self, "setNeedsLayout");
}

static BOOL Y34_WvShouldRasterize(id self, SEL _cmd) {                 // 0x1c78d0bd8
    if (!Y34_Raster(self)) return NO;
    if (!BPY_SEND(BOOL, (), Y34_ObjGet(self, gIvDefaults), "chamoisWindowingEnabled")) return NO;
    id layer = BPY_SEND(id, (), BP_ObjIvar(self, gIvPositioning), "layer");
    double m11 = 0, m22 = 0;
    if (layer) { CATransform3D t = ((CATransform3D (*)(id, SEL))objc_msgSend)(layer, sel_registerName("transform")); m11 = t.m11; m22 = t.m22; }   // arm64 has no _stret variant: the 128 byte result goes through x8
    return !gFloatIsOne((m11 + m22) * 0.5);
}

static void Y34_WvDealloc(id self, SEL _cmd) {                         // 0x1c78cff4c
    BPY_SEND(void, (), Y34_ObjGet(self, gIvObserver), "invalidate");
    BPY_SEND(void, (id), Y34_ObjGet(self, gIvSettings), "removeKeyObserver:", self);
    struct objc_super sup = { self, gWvBase };
    ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}
// the three object ivars of the subclass are released by hand (not known to ARC / the runtime)
static void Y34_WvDestruct(id self, SEL _cmd) {
    Y34_ObjRelease(self, gIvDefaults);
    Y34_ObjRelease(self, gIvObserver);
    Y34_ObjRelease(self, gIvSettings);
}

typedef void *(*Y34InitFrameFn)(struct objc_super *, SEL, CGRect);
__attribute__((ns_returns_retained)) static id Y34_WvInit(id __attribute__((ns_consumed)) self, SEL _cmd, id handle) {   // 0x1c78cfc5c
    void *raw = (__bridge_retained void *)self;                       // handed to the super init (an init consumes its receiver and returns +1)
    struct objc_super sup = { (__bridge id)raw, gWvBase };
    void *r = ((Y34InitFrameFn)objc_msgSendSuper2)(&sup, sel_registerName("initWithFrame:"), CGRectZero);
    id me = (__bridge_transfer id)r;
    if (!me) return nil;
    if (gIvSceneHandle) object_setIvar(me, gIvSceneHandle, handle);
    if (BP_ObjIvar(me, gIvPositioning)) return me;
    Class pv = NSClassFromString(@"_SBDeviceApplicationSceneClassicHostPositioningView");
    CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(me, sel_registerName("bounds"));
    id view = ((id (*)(id, SEL, CGRect))objc_msgSend)([pv alloc], sel_registerName("initWithFrame:"), bounds);
    object_setIvar(me, gIvPositioning, view);
    BPY_SEND(void, (id), me, "addSubview:", BP_ObjIvar(me, gIvPositioning));
    id layer = BPY_SEND(id, (), BP_ObjIvar(me, gIvPositioning), "layer");
    BPY_SEND(void, (id), layer, "setMinificationFilter:", *gFilterMin);
    BPY_SEND(void, (id), layer, "setMagnificationFilter:", *gFilterMag);
    if (!gAvailable()) return me;
    id root = BPY_SEND(id, (), (id)NSClassFromString(@"SBAppSwitcherDomain"), "rootSettings");
    id settings = BPY_SEND(id, (), root, "chamoisSettings");
    Y34_ObjSet(me, gIvSettings, settings);
    BPY_SEND(void, (id), settings, "addKeyObserver:", me);
    Y34_SetRaster(me, BPY_SEND(BOOL, (), settings, "rasterizeScaledApps"));
    id defaults = BPY_SEND(id, (), BPY_SEND(id, (), (id)NSClassFromString(@"SBDefaults"), "localDefaults"), "appSwitcherDefaults");
    Y34_ObjSet(me, gIvDefaults, defaults);
    __weak id weakSelf = me;
    void (^changed)(void) = ^{ id s = weakSelf; BPY_SEND(void, (), s, "_windowingModeChanged"); };
    id observer = ((id (*)(id, SEL, id, id, id))objc_msgSend)(defaults, sel_registerName("observeDefault:onQueue:withBlock:"), @"chamoisWindowingEnabled", dispatch_get_main_queue(), changed);
    Y34_ObjSet(me, gIvObserver, observer);
    return me;
}

__attribute__((constructor)) static void Y34Wrapper_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y34_classicwrapper")) return;
        gWvBase = NSClassFromString(@"SBDeviceApplicationSceneClassicWrapperView");
        const char *miss = y34_classicwrapper_preflight();
        gAvailable = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "SBFIsChamoisWindowingUIAvailable");
        gFloatIsOne = (BOOL (*)(double))dlsym(RTLD_DEFAULT, "BSFloatIsOne");
        gFilterMin = (NSString *const *)dlsym(RTLD_DEFAULT, "kCAFilterBox");
        gFilterMag = (NSString *const *)dlsym(RTLD_DEFAULT, "kCAFilterLinearlySampledLinear");
        Class defaultsCls = NSClassFromString(@"SBDefaults"), domain = NSClassFromString(@"SBAppSwitcherDomain"), pv = NSClassFromString(@"_SBDeviceApplicationSceneClassicHostPositioningView");
        if (!gWvBase || miss || !gAvailable || !gFloatIsOne || !gFilterMin || !gFilterMag || !defaultsCls || !domain || !pv) {
            BP_Anomaly("y34", @"[y34] y34_classicwrapper NOT installed: base %p, recompiled layoutSubviews needs '%s', SBFIsChamoisWindowingUIAvailable %p BSFloatIsOne %p kCAFilterBox %p kCAFilterLinearlySampledLinear %p SBDefaults %p SBAppSwitcherDomain %p positioning view %p: the 16.0 wrapper view stays",
                       (__bridge void *)gWvBase, miss ?: "-", (void *)gAvailable, (void *)gFloatIsOne, (void *)gFilterMin, (void *)gFilterMag, (__bridge void *)defaultsCls, (__bridge void *)domain, (__bridge void *)pv);
            return;
        }
        static const Y34IvarSpec ivars[] = {
            { "_appSwitcherDefaults", sizeof(void *), 3, "@" }, { "_chamoisEnabledObserver", sizeof(void *), 3, "@" }, { "_chamoisSettings", sizeof(void *), 3, "@" }, { "_canRasterize", 1, 0, "B" },
        };
        gWvExt = Y34_MakeExt("SBDeviceApplicationSceneClassicWrapperView", "Y34ClassicWrapperView", ivars, 4);
        if (!gWvExt) return;
        gIvDefaults = class_getInstanceVariable(gWvExt, "_appSwitcherDefaults");
        gIvObserver = class_getInstanceVariable(gWvExt, "_chamoisEnabledObserver");
        gIvSettings = class_getInstanceVariable(gWvExt, "_chamoisSettings");
        gIvRaster = class_getInstanceVariable(gWvExt, "_canRasterize");
        gIvPositioning = class_getInstanceVariable(gWvBase, "_positioningView");
        gIvSceneHandle = class_getInstanceVariable(gWvBase, "_sceneHandle");
        if (!gIvDefaults || !gIvObserver || !gIvSettings || !gIvRaster || !gIvPositioning || !gIvSceneHandle) {
            BP_Anomaly("y34", @"[y34] y34_classicwrapper NOT installed: an ivar is missing (_positioningView %p _sceneHandle %p)", (void *)gIvPositioning, (void *)gIvSceneHandle);
            return;
        }
        class_addMethod(gWvExt, sel_registerName("initWithSceneHandle:"), (IMP)Y34_WvInit, "@@:@");
        class_addMethod(gWvExt, sel_registerName("dealloc"), (IMP)Y34_WvDealloc, "v@:");
        class_addMethod(gWvExt, sel_registerName(".cxx_destruct"), (IMP)Y34_WvDestruct, "v@:");
        class_addMethod(gWvExt, sel_registerName("layoutSubviews"), (IMP)Y34_WvLayout, "v@:");
        class_addMethod(gWvExt, sel_registerName("settings:changedValueForKey:"), (IMP)Y34_WvSettings, "v@:@@");
        class_addMethod(gWvExt, sel_registerName("_windowingModeChanged"), (IMP)Y34_WvWindowingModeChanged, "v@:");
        class_addMethod(gWvExt, sel_registerName("_shouldRasterizePositioningLayer"), (IMP)Y34_WvShouldRasterize, "B@:");
        Protocol *p = objc_getProtocol("PTSettingsKeyObserver");
        if (p) class_addProtocol(gWvExt, p);
        lift_register_ext("SBDeviceApplicationSceneClassicWrapperView", (__bridge void *)gWvExt);
        BP_Log(@"[y34] installed y34_classicwrapper (runtime subclass Y34ClassicWrapperView)");
    }
}
#pragma clang diagnostic pop
