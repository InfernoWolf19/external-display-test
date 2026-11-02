// Y34ClassicTypes.x : delta sweep pass 4, the supported type bits of classic (iPhone-only) apps.  Setup: constructor.  Log prefix "[y34]".
//
//  y34_lazytypes    -[SBApplication(Classic_Internal) _calculateSupportedTypesLazilyIfNecessary]  16.2 0x1c7339fb0 (16.0 0x1c5ec6f58): fills _supportedTypes (+0xc0) from the launch snapshots
//                   of the snapshot manifest and the SDK generation flags.  The 16.2 body (1244 instructions, 257 more than 16.0: the device class / idiom tests are inline, and the
//                   snapshot loop knows the 12.9 inch iPad Pro sizes) is NOT re-typed: Y34LazyTypes.c is the 16.2 machine code recompiled to C by tools/a2c/a2c.py.  Proven against the
//                   Unicorn emulation of the original code (tools/a2c/tests/lazy_test.py): 22704 inputs per device class x 3 classes, 16.0 and 16.2 differ on 256 (no home button, a type 1
//                   app, screens from 954 x 1373 up with launch snapshots), the lifted 16.2 code agrees with the emulated 16.2 code on all of them.
//  y34_splashtypes  -[SBApplication(Classic_Internal) _calculateSupportedTypesForSplashBoard]  16.2 0x1c733c13c (16.0 0x1c5ec8d2c): the same for apps with usesSplashBoard.  Hand ported
//                   (Y34SplashTypes.h, pure function): the only change against 16.0 is the last step, `sydney && !isBeta` (16.0) became `sydney` (16.2 does not ask isBeta any more).
//                   tools/a2c/tests/splash_test.py compares Y34_SplashTypes with the lifted 16.2 code and with the emulated 16.0 / 16.2 code on 65536 cases (all 12 query combinations x isBeta x seeds).
// Callers (-[SBApplication(Classic_Private) _defaultClassicMode / _canLaunchInClassicMode: / _recalculateApplicationSupportedTypes]) and callees (SBApplicationInfo is*Linked / wantsFullScreen /
// usesSplashBoard, -_isNewEnoughToKnowAbout2020Phones / RoundPads, -_bypassesClassicMode, -_supportsApplicationType:) were compared 16.0 vs 16.2: identical but the ivar offsets.
// A body that cannot be installed (a symbol / class / ivar / selector of the preflight is missing) is NOT replaced: ANOMALY y34 is written once and the 16.0 body keeps running.
// Needs a device: with an iPhone-only app on the 12.9 inch iPad (Y26Classic.x y24_classicmode then sees the 16.2 type bits: "[y26] classic mode of ... (16.0 body: ...)" in the debug log).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "Y34SplashTypes.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

// Y34LazyTypes.c
extern void y34_lazy_types(void *self, void *cmd);
extern const char *y34_lazy_types_preflight(void);

// CFString constants of the recompiled code (tools/a2c/liftdev.h CFSTR_): created once, kept for the process lifetime
void *lift_cfstr(const char *utf8) {
    static NSMutableDictionary *cache;
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; lock = [NSLock new]; });
    NSString *key = [NSString stringWithUTF8String:utf8 ?: ""];
    [lock lock];
    NSString *s = cache[key];
    if (!s) { s = [key copy]; cache[key] = s; }
    [lock unlock];
    return (__bridge void *)s;
}

static IMP gY34OrigLazy, gY34OrigSplash;

static void Y34_Lazy(id self, SEL _cmd) {
    if (!BP_OnName("y34_lazytypes")) { ((void (*)(id, SEL))gY34OrigLazy)(self, _cmd); return; }
    y34_lazy_types((__bridge void *)self, (void *)_cmd);
}

static void Y34_Splash(id self, SEL _cmd) {
    if (!BP_OnName("y34_splashtypes")) { ((void (*)(id, SEL))gY34OrigSplash)(self, _cmd); return; }
    Class cls = object_getClass(self);
    Ivar ivInfo = BP_IvarLookup(cls, "_appInfo");
    Ivar ivTypes = BP_IvarLookup(cls, "_supportedTypes");
    if (!ivInfo || !ivTypes) {
        BP_Anomaly("y34", @"[y34] splashtypes: ivar _appInfo %p / _supportedTypes %p missing on %s: the 16.0 body ran", (void *)ivInfo, (void *)ivTypes, class_getName(cls));
        ((void (*)(id, SEL))gY34OrigSplash)(self, _cmd);
        return;
    }
    // the queries in the order of the 16.2 body (0x1c733c174 ..); the receiver is re-read from the ivar like the machine code does (a nil _appInfo answers NO everywhere)
    unsigned long long *types = (unsigned long long *)((char *)(__bridge void *)self + ivar_getOffset(ivTypes));
    id (^info)(void) = ^id { return BP_ObjIvar(self, ivInfo); };
    Y34SplashQuery q;
    q.monarch = BPY_SEND(BOOL, (), info(), "isMonarchLinked");
    q.tigris = BPY_SEND(BOOL, (), info(), "isTigrisLinked");
    q.peace = BPY_SEND(BOOL, (), info(), "isPeaceLinked");
    q.yukon = BPY_SEND(BOOL, (), info(), "isYukonLinked");
    q.azul = BPY_SEND(BOOL, (), info(), "isAzulLinked");
    q.new2020Phones = BPY_SEND(BOOL, (), self, "_isNewEnoughToKnowAbout2020Phones");
    q.newRoundPads = BPY_SEND(BOOL, (), self, "_isNewEnoughToKnowAboutRoundPads");
    q.sky = BPY_SEND(BOOL, (), info(), "isSkyLinked");
    q.sydney = BPY_SEND(BOOL, (), info(), "isSydneyLinked");
    q.supportsType2 = BPY_SEND(BOOL, (unsigned long long), self, "_supportsApplicationType:", 2ull);
    q.wantsFullScreen = q.supportsType2 ? BPY_SEND(BOOL, (), info(), "wantsFullScreen") : 0;
    // the block above keeps the type 2 step first (it writes the ivar before the type 1 query asks _supportsApplicationType: again)
    unsigned long long t = *types;
    if (q.supportsType2) {
        Y34SplashQuery only2 = q; only2.supportsType1 = 0;
        t = Y34_SplashTypes(t, only2);
        *types = t;
    }
    q.supportsType1 = BPY_SEND(BOOL, (unsigned long long), self, "_supportsApplicationType:", 1ull);
    if (q.supportsType1) {
        Y34SplashQuery only1 = q; only1.supportsType2 = 0;
        *types = Y34_SplashTypes(*types, only1);
    }
}

__attribute__((constructor)) static void Y34Types_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class app = NSClassFromString(@"SBApplication");
        Class info = NSClassFromString(@"SBApplicationInfo");
        if (!app || !info) { BP_Anomaly("y34", @"[y34] types: SBApplication %p / SBApplicationInfo %p missing: not installed", (__bridge void *)app, (__bridge void *)info); return; }
        // lazy
        const char *miss = y34_lazy_types_preflight();
        if (miss) {
            BP_Anomaly("y34", @"[y34] y34_lazytypes NOT installed: the recompiled 16.2 body cannot resolve: %s: the 16.0 body keeps running", miss);
        } else if (!class_getInstanceMethod(app, sel_registerName("_calculateSupportedTypesLazilyIfNecessary"))) {
            BP_Anomaly("y34", @"[y34] y34_lazytypes NOT installed: -[SBApplication _calculateSupportedTypesLazilyIfNecessary] does not exist");
        } else {
            gY34OrigLazy = BPX_Replace(app, "_calculateSupportedTypesLazilyIfNecessary", (IMP)Y34_Lazy);
            BP_Log(@"[y34] installed y34_lazytypes");
        }
        // splash board
        const char *sels[] = { "isMonarchLinked", "isTigrisLinked", "isPeaceLinked", "isYukonLinked", "isAzulLinked", "isSkyLinked", "isSydneyLinked", "wantsFullScreen" };
        const char *missSel = NULL;
        for (size_t k = 0; k < sizeof sels / sizeof sels[0]; k++) if (!class_getInstanceMethod(info, sel_registerName(sels[k]))) { missSel = sels[k]; break; }
        if (!missSel && !class_getInstanceMethod(app, sel_registerName("_isNewEnoughToKnowAbout2020Phones"))) missSel = "_isNewEnoughToKnowAbout2020Phones";
        if (!missSel && !class_getInstanceMethod(app, sel_registerName("_isNewEnoughToKnowAboutRoundPads"))) missSel = "_isNewEnoughToKnowAboutRoundPads";
        if (!missSel && !class_getInstanceMethod(app, sel_registerName("_supportsApplicationType:"))) missSel = "_supportsApplicationType:";
        if (missSel) {
            BP_Anomaly("y34", @"[y34] y34_splashtypes NOT installed: selector %s is missing: the 16.0 body keeps running", missSel);
        } else if (!class_getInstanceMethod(app, sel_registerName("_calculateSupportedTypesForSplashBoard"))) {
            BP_Anomaly("y34", @"[y34] y34_splashtypes NOT installed: -[SBApplication _calculateSupportedTypesForSplashBoard] does not exist");
        } else {
            gY34OrigSplash = BPX_Replace(app, "_calculateSupportedTypesForSplashBoard", (IMP)Y34_Splash);
            BP_Log(@"[y34] installed y34_splashtypes");
        }
    }
}
#pragma clang diagnostic pop
