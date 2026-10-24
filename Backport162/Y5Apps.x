// Y5Apps.x : delta sweep family F2/F3 (specs/DELTA-SWEEP-0.7.9.md): app / scene view plumbing that follows the window scene.  Setup: constructor.  Log prefix "[y5]".
//
//  y5_sbpool     Status bars of a scene view controller come from the reuse pool of ITS window scene (-[SBStatusBarManager reusePool]).
//                (a) 16.2 remembers the pool in a weak ivar when it makes the bar (-[SBDeviceApplicationSceneViewController _createStatusBar] 0x1c75bc038, weak ivar +0xf34) and
//                    recycles the bar into THAT pool (-_removeStatusBar 0x1c75bcefc); 16.0 asked the CURRENT scene's pool (0x1c613214c), so a window that was dragged to the other
//                    display handed its bar to the wrong display's pool (the bar keeps the first display's target screen, the other pool grows).  Ported: the pool is kept as an
//                    associated object when a new bar appears, and -[SBStatusBarReusePool recycleStatusBar:] is redirected to it while -_removeStatusBar runs (thread local).
//                (b) -[SBStatusBarReusePool getReusableStatusBarWithReason:withFrame:] 16.2 0x1c78911f4 sets the modern bar's target screen to the pool's window scene screen when it
//                    makes a new bar (16.0: the default, the main screen).  Applied on every bar handed out (the pool belongs to one scene, so it is the same screen).
//  y5_classicsize  +[SBApplication(Classic_Internal) _defaultLaunchingSizeForDisplayConfiguration:classicMode:] 16.2 0x1c733bc90 (16.0 0x1c5ec8834): the iPhone window size table of the
//                  classic modes is used on every display; 16.0 used it only when [[config identity] isMainRootDisplay] and answered the display bounds on the extended display (an iPhone-only
//                  app launched there got a monitor sized scene).  Ported: for a non main display config and a classic mode the 16.0 method runs with the embedded display's config (the table
//                  does not read the config), modes -1 / 0 (display bounds) keep the real config.
// Needs a device: drag an app window from the iPad to the monitor and back: no stale status bar frames; launch an iPhone-only app on the monitor: iPhone sized window.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

typedef struct { double a, b, c, d; } Y5Rect;      // CGRect: four doubles (HFA, d0..d3)
typedef struct { double w, h; } Y5Size;            // CGSize (HFA, d0..d1)

@interface Y5WeakObj : NSObject { @public __weak id obj; } @end
@implementation Y5WeakObj @end

static const void *kY5Pool = &kY5Pool;
static __thread void *tY5Pool;                     // unretained: the pool recycleStatusBar: is redirected to while _removeStatusBar runs
static IMP gY5Create, gY5Remove, gY5Recycle, gY5Reusable, gY5ClassicSize;

static id Y5_PoolOf(id vc) { return BPX_Obj0(BPX_Obj0(BPX_Obj0(BPX_Obj0(vc, "sceneHandle"), "_windowScene"), "statusBarManager"), "reusePool"); }

static void Y5_CreateSB(id self, SEL _cmd) {
    id before = BPX_IvarObj(self, "_statusBar");
    if (gY5Create) ((void (*)(id, SEL))gY5Create)(self, _cmd);
    if (!BP_OnName("y5_sbpool")) return;
    id after = BPX_IvarObj(self, "_statusBar");
    if (!before && after) {
        id pool = Y5_PoolOf(self);
        if (pool) {
            Y5WeakObj *w = [Y5WeakObj new];
            w->obj = pool;
            objc_setAssociatedObject(self, kY5Pool, w, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}
static void Y5_RemoveSB(id self, SEL _cmd) {
    Y5WeakObj *w = BP_OnName("y5_sbpool") ? objc_getAssociatedObject(self, kY5Pool) : nil;
    id pool = w ? w->obj : nil;
    void *prev = tY5Pool;
    if (pool) {
        tY5Pool = (__bridge void *)pool;
        if (BP_LogEnabled() && pool != Y5_PoolOf(self)) BPY_LOG(@"[y5] status bar of %p recycled into the pool it came from (%p), not the current scene's", (__bridge void *)self, (__bridge void *)pool);
    }
    if (gY5Remove) ((void (*)(id, SEL))gY5Remove)(self, _cmd);
    tY5Pool = prev;
    if (w) objc_setAssociatedObject(self, kY5Pool, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// -[SBStatusBarReusePool recycleStatusBar:]
static void Y5_Recycle(id self, SEL _cmd, id bar) {
    void *p = tY5Pool;
    id target = p ? (__bridge id)p : self;
    if (gY5Recycle) ((void (*)(id, SEL, id))gY5Recycle)(target, _cmd, bar);
}
// -[SBStatusBarReusePool getReusableStatusBarWithReason:withFrame:]
static id Y5_Reusable(id self, SEL _cmd, id reason, Y5Rect frame) {
    id bar = gY5Reusable ? ((id (*)(id, SEL, id, Y5Rect))gY5Reusable)(self, _cmd, reason, frame) : nil;
    if (bar && BP_OnName("y5_sbpool") && BPY_Responds(bar, "_usesModernBar") && BPX_Bool0(bar, "_usesModernBar")) {
        id modern = BPX_Obj0(bar, "statusBar");
        id screen = BPX_Obj0(BPX_Obj0(self, "windowScene"), "screen");
        if (modern && screen && BPY_Responds(modern, "setTargetScreen:")) BPX_SetObj1(modern, "setTargetScreen:", screen);
    }
    return bar;
}

// +[SBApplication(Classic_Internal) _defaultLaunchingSizeForDisplayConfiguration:classicMode:]
static Y5Size Y5_ClassicSize(id self, SEL _cmd, id config, long long mode) {
    id use = config;
    if (BP_OnName("y5_classicsize") && mode != -1 && mode != 0 && config && !BPX_Bool0(BPX_Obj0(config, "identity"), "isMainRootDisplay")) {
        id main = BPX_Obj0(BPX_Obj0(BPX_WindowSceneManager(), "embeddedDisplayWindowScene"), "_fbsDisplayConfiguration");
        if (main) use = main;
    }
    Y5Size r = {0, 0};
    if (gY5ClassicSize) r = ((Y5Size (*)(id, SEL, id, long long))gY5ClassicSize)(self, _cmd, use, mode);
    return r;
}

__attribute__((constructor)) static void Y5_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class vc = NSClassFromString(@"SBDeviceApplicationSceneViewController"), pool = NSClassFromString(@"SBStatusBarReusePool"), app = NSClassFromString(@"SBApplication");
        SEL cs = sel_registerName("_defaultLaunchingSizeForDisplayConfiguration:classicMode:");
        if (!vc || !pool || !app) { BP_Log(@"[y5] NOT installed (class missing)"); return; }
        if (class_getInstanceMethod(vc, sel_registerName("_createStatusBar")) && class_getInstanceMethod(vc, sel_registerName("_removeStatusBar")) &&
            class_getInstanceMethod(pool, sel_registerName("recycleStatusBar:")) && class_getInstanceMethod(pool, sel_registerName("getReusableStatusBarWithReason:withFrame:"))) {
            gY5Create = BPX_Replace(vc, "_createStatusBar", (IMP)Y5_CreateSB);
            gY5Remove = BPX_Replace(vc, "_removeStatusBar", (IMP)Y5_RemoveSB);
            gY5Recycle = BPX_Replace(pool, "recycleStatusBar:", (IMP)Y5_Recycle);
            gY5Reusable = BPX_Replace(pool, "getReusableStatusBarWithReason:withFrame:", (IMP)Y5_Reusable);
        } else BP_Log(@"[y5] status bar pool part NOT installed (selector missing)");
        Method cm = class_getClassMethod(app, cs);
        if (cm) {
            gY5ClassicSize = method_getImplementation(cm);
            class_replaceMethod(object_getClass(app), cs, (IMP)Y5_ClassicSize, method_getTypeEncoding(cm));
        } else BP_Log(@"[y5] classic size part NOT installed (class method missing)");
        BP_Log(@"[y5] installed (switches y5_sbpool, y5_classicsize)");
    }
}
#pragma clang diagnostic pop
