// Y33HomeDiag.x : diagnostics only, NO behaviour change.  Setup: constructor.  Log prefix "[y33]".
//
// What the SpringBoard side of the app switcher asks the home screen to do while a switcher dismiss runs (settled ToHome, in flight dismiss, grid open): the values the switcher content controller
// delegate (SBMainSwitcherControllerCoordinator) receives, with the animation mode and a timestamp, to see WHY the home icons stay hidden for ~0.7 s after a settled dismiss (the stock
// answers are identical in 16.0 and 16.2, so a log of what is applied when is the way to find the difference).  Everything is written only while Backport162.debug exists;
// each wrapper calls the original unchanged.  Selectors (16.0 sb160n_objc.txt): switcherContentController:set{HomeScreenAlpha,HomeScreenScale,HomeScreenBackdropBlurProgress,
// HomeScreenDimmingAlpha,WallpaperScale}:withAnimationMode:completion: and switcherContentController:setHomeScreenBackdropBlurType:.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY33Alpha, gY33Scale, gY33Progress, gY33Dim, gY33WScale, gY33BlurType;
typedef void (*Y33_DblFn)(id, SEL, id, double, long long, id);
typedef void (*Y33_TypeFn)(id, SEL, id, long long);

#define Y33_DBL(NAME, ORIG, LABEL) \
static void NAME(id self, SEL _cmd, id controller, double v, long long mode, id completion) { \
    if (BP_LogEnabled()) BP_Log(@"[y33] home " LABEL " %.4f mode %lld%@", v, mode, completion ? @" (completion)" : @""); \
    if (ORIG) ((Y33_DblFn)ORIG)(self, _cmd, controller, v, mode, completion); \
}
Y33_DBL(Y33_SetAlpha, gY33Alpha, "alpha")
Y33_DBL(Y33_SetScale, gY33Scale, "scale")
Y33_DBL(Y33_SetProgress, gY33Progress, "backdrop blur progress")
Y33_DBL(Y33_SetDim, gY33Dim, "dimming alpha")
Y33_DBL(Y33_SetWScale, gY33WScale, "wallpaper scale")

static void Y33_SetBlurType(id self, SEL _cmd, id controller, long long type) {
    if (BP_LogEnabled()) BP_Log(@"[y33] home backdrop blur type %lld", type);
    if (gY33BlurType) ((Y33_TypeFn)gY33BlurType)(self, _cmd, controller, type);
}

__attribute__((constructor)) static void Y33_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBMainSwitcherControllerCoordinator");
        if (!c) { BP_Anomaly("notinstalled", @"[y33] SBMainSwitcherControllerCoordinator missing: home screen diagnostics not installed"); return; }
        int n = 0;
        struct { const char *sel; IMP imp; IMP *orig; } t[] = {
            { "switcherContentController:setHomeScreenAlpha:withAnimationMode:completion:", (IMP)Y33_SetAlpha, &gY33Alpha },
            { "switcherContentController:setHomeScreenScale:withAnimationMode:completion:", (IMP)Y33_SetScale, &gY33Scale },
            { "switcherContentController:setHomeScreenBackdropBlurProgress:withAnimationMode:completion:", (IMP)Y33_SetProgress, &gY33Progress },
            { "switcherContentController:setHomeScreenDimmingAlpha:withAnimationMode:completion:", (IMP)Y33_SetDim, &gY33Dim },
            { "switcherContentController:setWallpaperScale:withAnimationMode:completion:", (IMP)Y33_SetWScale, &gY33WScale },
            { "switcherContentController:setHomeScreenBackdropBlurType:", (IMP)Y33_SetBlurType, &gY33BlurType },
        };
        for (size_t i = 0; i < sizeof t / sizeof t[0]; i++) {
            if (!class_getInstanceMethod(c, sel_registerName(t[i].sel))) { BP_Anomaly("notinstalled", @"[y33] %s missing: not logged", t[i].sel); continue; }
            *t[i].orig = BPX_Replace(c, t[i].sel, t[i].imp);
            n++;
        }
        BP_Log(@"[y33] installed %d home screen diagnostics (debug only output)", n);
    }
}
#pragma clang diagnostic pop
