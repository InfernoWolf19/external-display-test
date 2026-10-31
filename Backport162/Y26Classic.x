// Y26Classic.x : delta sweep pass 3, classic (iPhone-only) apps on the iPad.  Setup: constructor.  Log prefix "[y26]".
//
//  y24_classicmode  -[SBApplication(Classic_Internal) _classicModeFromSupportedTypes]  16.2 0x1c733c334 (16.0 0x1c5ec8f44): the classic mode (0 = not classic, 1..16 = the iPhone screen size row
//                   used by +_defaultLaunchingSizeForDisplayConfiguration:classicMode: / Y5Apps.x y5_classicsize, -1 = splash board app without supported types) an application gets from its
//                   supported screen types.  It is a ~1500 instruction decision tree over: [_appInfo usesSplashBoard], -_useSupportedTypesForSplashBoard, -_bypassesClassicMode, SBFEffectiveDeviceClass()
//                   (2 = iPad), SBFEffectiveHomeButtonType() (== 2 = no home button), -_supportsApplicationType: (bit per iPhone / iPad screen type), the rounded main screen reference size against
//                   fixed sizes (BSSizeEqualToSize / BSSizeGreaterThanOrEqualToSize / BSSizeLessThanSize), [_appInfo isSydneyLinked], SBHScreenTypeForCurrentDevice() == 31 and the class method
//                   +KJHKJHw39rq9w87q903475q0983rskjd.  The tree was NOT re-typed by hand: Y26ClassicTables.h is generated from the 16.2 machine code (arm64 emulation of the function with these queries as
//                   the free variables, all paths explored, equal subtrees merged: 296 nodes for no home button, 23 otherwise; the same procedure on the 16.0 body gives 283 / 23 nodes).
//                   Differences found (16.2 vs 16.0), all in the branch of devices WITHOUT home button (the M2 iPad Pro) for applications that do not support the iPad (no type 2):
//                     * main screen >= 1024 x 1366 (the 12.9 inch iPad Pro): type 128 -> mode 7, else type 64 -> mode 6 (16.0 answered 3 / 2 / 1 from types 8 / 4);
//                     * main screen >= 1192 x 1590: type 1024 -> 9, type 512 -> 8 (no iPad has such a screen yet);
//                     * 820 x 1180 (iPad Air) with screen type 31, type 524288 and KJH: 0 instead of 14.
//                   Devices with a home button (any other SBFEffectiveHomeButtonType) give identical answers in both builds (checked leaf by leaf).
//                   Not covered by the tree (device class other than 2, the iPhone branches of the function) -> the 16.0 body runs, logged once.
//                   The supported types themselves come from -_calculateSupportedTypesLazilyIfNecessary / -_calculateSupportedTypesForSplashBoard (16.0 bodies still run: see DELTA-SWEEP, Pass 3).
// Needs a device: with an iPhone-only app installed (supporting the 4.7 inch launch size) open it in a window on the 12.9 inch iPad: the window is the 7th classic size row (375 x 667), not
// the 4 inch one.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"
#import "Y26ClassicTables.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY26OrigMode;

typedef long long (*Y26_IntFn)(void);
typedef CGSize (*Y26_RoundFn)(CGSize, CGFloat);
typedef BOOL (*Y26_SizeCmpFn)(CGSize, CGSize);
static Y26_IntFn gY26DeviceClass, gY26HomeButton, gY26ScreenType;
static Y26_RoundFn gY26Round;
static Y26_SizeCmpFn gY26Eq, gY26Ge, gY26Lt;

static id Y26_AppInfo(id app) {
    Ivar iv = class_getInstanceVariable(object_getClass(app), "_appInfo");
    return BP_ObjIvar(app, iv);
}

static BOOL Y26_Flag(id app, long long idx, BOOL *ok) {
    switch (idx) {
        case 0: { id info = Y26_AppInfo(app); if (!BPY_Responds(info, "usesSplashBoard")) { *ok = NO; return NO; } return BPY_SEND(BOOL, (), info, "usesSplashBoard"); }
        case 1: if (!BPY_Responds(app, "_useSupportedTypesForSplashBoard")) { *ok = NO; return NO; } return BPY_SEND(BOOL, (), app, "_useSupportedTypesForSplashBoard");
        case 2: if (!BPY_Responds(app, "_bypassesClassicMode")) { *ok = NO; return NO; } return BPY_SEND(BOOL, (), app, "_bypassesClassicMode");
        case 3: { id info = Y26_AppInfo(app); if (!BPY_Responds(info, "isSydneyLinked")) { *ok = NO; return NO; } return BPY_SEND(BOOL, (), info, "isSydneyLinked"); }
        case 4: { id cls = (id)object_getClass(app); SEL s = sel_registerName("KJHKJHw39rq9w87q903475q0983rskjd"); if (!cls || ![cls respondsToSelector:s]) { *ok = NO; return NO; } return ((BOOL (*)(id, SEL))objc_msgSend)(cls, s); }
        case 5: return gY26ScreenType() == 31;
    }
    *ok = NO;
    return NO;
}

// returns YES and the mode when the tree could be evaluated
static BOOL Y26_Eval(id app, long long *mode) {
    long long hb = gY26HomeButton();
    const Y26Node *tab = (hb == 2) ? Y26_Tab_hb2 : Y26_Tab_other;
    int cur = (hb == 2) ? Y26_Tab_hb2_root : Y26_Tab_other_root;
    CGRect b = ((CGRect (*)(id, SEL))objc_msgSend)((id)[UIScreen mainScreen], sel_registerName("_referenceBounds"));
    CGSize screen = gY26Round(b.size, 1.0);
    for (int guard = 0; guard < 1024; guard++) {
        const Y26Node *n = &tab[cur];
        BOOL v;
        switch (n->kind) {
            case 0: *mode = n->a; return YES;
            case 1: { BOOL ok = YES; v = Y26_Flag(app, n->a, &ok); if (!ok) { Y17_GuardOnce("classicmode", app, "flag query of the classic mode tree"); return NO; } break; }
            case 2: if (!BPY_Responds(app, "_supportsApplicationType:")) { Y17_GuardOnce("classicmode", app, "_supportsApplicationType:"); return NO; }
                    v = BPY_SEND(BOOL, (unsigned long long), app, "_supportsApplicationType:", (unsigned long long)n->a); break;
            case 3: {
                CGSize c = CGSizeMake(n->w, n->h);
                Y26_SizeCmpFn f = n->op == 0 ? gY26Eq : (n->op == 1 ? gY26Ge : gY26Lt);
                v = n->a == 0 ? f(screen, c) : f(c, screen);
                break;
            }
            default: return NO;
        }
        cur = v ? n->yes : n->no;
    }
    return NO;
}

static long long Y26_ClassicMode(id self, SEL _cmd) {
    long long orig = gY26OrigMode ? ((long long (*)(id, SEL))gY26OrigMode)(self, _cmd) : 0;
    if (!BP_OnName("y24_classicmode")) return orig;
    if (gY26DeviceClass() != 2) { Y17_GuardOnce("classicmode", self, "device class 2 (the tree covers the iPad branch only): 16.0 body"); return orig; }
    long long mode = 0;
    if (!Y26_Eval(self, &mode)) return orig;
    if (mode != orig && BP_LogEnabled()) BP_Log(@"[y26] classic mode of %@: %lld (16.0 body: %lld)", BPX_Obj0(self, "bundleIdentifier") ?: self, mode, orig);
    return mode;
}

__attribute__((constructor)) static void Y26_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        gY26DeviceClass = (Y26_IntFn)dlsym(RTLD_DEFAULT, "SBFEffectiveDeviceClass");
        gY26HomeButton = (Y26_IntFn)dlsym(RTLD_DEFAULT, "SBFEffectiveHomeButtonType");
        gY26ScreenType = (Y26_IntFn)dlsym(RTLD_DEFAULT, "SBHScreenTypeForCurrentDevice");
        gY26Round = (Y26_RoundFn)dlsym(RTLD_DEFAULT, "BSSizeRoundForScale");
        gY26Eq = (Y26_SizeCmpFn)dlsym(RTLD_DEFAULT, "BSSizeEqualToSize");
        gY26Ge = (Y26_SizeCmpFn)dlsym(RTLD_DEFAULT, "BSSizeGreaterThanOrEqualToSize");
        gY26Lt = (Y26_SizeCmpFn)dlsym(RTLD_DEFAULT, "BSSizeLessThanSize");
        Class app = NSClassFromString(@"SBApplication");
        if (!gY26DeviceClass || !gY26HomeButton || !gY26ScreenType || !gY26Round || !gY26Eq || !gY26Ge || !gY26Lt || !app || !class_getInstanceMethod(app, sel_registerName("_classicModeFromSupportedTypes"))) {
            BP_Log(@"[y26] GUARD(classicmode) not installed: SBFEffectiveDeviceClass %p HomeButtonType %p SBHScreenTypeForCurrentDevice %p BSSizeRoundForScale %p Eq %p Ge %p Lt %p SBApplication %p",
                   (void *)gY26DeviceClass, (void *)gY26HomeButton, (void *)gY26ScreenType, (void *)gY26Round, (void *)gY26Eq, (void *)gY26Ge, (void *)gY26Lt, (__bridge void *)app);
            return;
        }
        gY26OrigMode = BPX_Replace(app, "_classicModeFromSupportedTypes", (IMP)Y26_ClassicMode);
        BP_Log(@"[y26] installed y24_classicmode");
    }
}
#pragma clang diagnostic pop
