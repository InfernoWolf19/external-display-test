// Y42SelfTest.x : on-install self test of the runtime subclasses of the Y34 / Y42 ports (a lesson of the SpringBoard crash caused by the dealloc of a runtime subclass).  Setup: constructor.  NOT device tested.
//
//  15 s after launch (main queue, after every constructor and the boot sequence) one instance of every runtime class is created off-screen WITHOUT running the 16.0 designated initialisers (the bare
//  NSObject init, -initWithFrame: for views) and checked: -class answers the 16.0 class, -isKindOfClass: of the base, the instance really is of the runtime subclass, every added ivar reads zero, and the instance
//  is deallocated when released (weak reference nil).  Classes: Y34ClassicWrapperView, Y42DeckSwitcherViewController, Y42TraitsSceneParticipantDelegate, SBTraitsSceneOrientationRequestAssistant (the SBSceneView of
//  Y34DeviceApplicationSceneView is tested by Y42SceneView.x).  The result of each class is logged ALWAYS as ANOMALY y42-selftest (class, ivars, teardown).  A class that is not installed is reported as such.
// Switch y42_selftest (kill file Backport162.off.y42_selftest).  Only on build 20A8372.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

static void Y42ST_One(const char *extName, const char *baseName, const char *const *ivars, int nIvars, BOOL isView) {
    Class ext = objc_getClass(extName);
    Class base = objc_getClass(baseName);
    if (!ext || !base) { BP_Anomaly("y42-selftest", @"[y42] self test %s: class %s %s: not installed (the 16.0 class is used)", extName, ext ? baseName : extName, "missing"); return; }
    __weak id weak = nil;
    NSString *res = nil;
    @autoreleasepool {
        id v = ((id (*)(id, SEL))objc_msgSend)((id)ext, sel_registerName("alloc"));
        if (isView) v = ((id (*)(id, SEL, CGRect))objc_msgSend)(v, sel_registerName("initWithFrame:"), CGRectZero);
        else { IMP ni = class_getMethodImplementation([NSObject class], sel_registerName("init")); v = ((id (*)(id, SEL))ni)(v, sel_registerName("init")); }
        if (!v) { BP_Anomaly("y42-selftest", @"[y42] self test %s FAILED: alloc / init answered nil", extName); return; }
        BOOL isExt = object_getClass(v) == ext;
        Class shown = [v class];
        BOOL classOK = (shown == base || strcmp(class_getName(shown), baseName) == 0 || shown == ext) && [v isKindOfClass:base];
        BOOL ivOK = YES;
        for (int k = 0; k < nIvars; k++) {
            Ivar iv = class_getInstanceVariable(ext, ivars[k]);
            if (!iv || *(void **)((char *)(__bridge void *)v + ivar_getOffset(iv)) != NULL) ivOK = NO;
        }
        res = [NSString stringWithFormat:@"-class answers %s (%@), object class %s (%@), %d added ivar(s) zero %@", class_getName(shown), classOK ? @"OK" : @"WRONG", class_getName(object_getClass(v)), isExt ? @"runtime subclass" : @"not the runtime subclass", nIvars, ivOK ? @"yes" : @"NO"];
        if (!(classOK && ivOK)) res = [@"FAILED: " stringByAppendingString:res];
        weak = v;
    }
    BP_Anomaly("y42-selftest", @"[y42] self test %s: %@ ; teardown %@ (OS build 20A8372)", extName, res, weak == nil ? @"OK: deallocated" : @"NOT DONE: still alive");
}

__attribute__((constructor)) static void Y42SelfTest_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_selftest")) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!BP_OnName("y42_selftest")) return;
            static const char *const wv[] = { "_appSwitcherDefaults", "_chamoisEnabledObserver", "_chamoisSettings" };
            static const char *const dk[] = { "_appSuggestionManager" };
            static const char *const td[] = { "_orientationRequestActionAssistant" };
            static const char *const as[] = { "_traitsDelegate", "_errorDomain" };
            Y42ST_One("Y34ClassicWrapperView", "SBDeviceApplicationSceneClassicWrapperView", wv, 3, YES);
            Y42ST_One("Y42DeckSwitcherViewController", "SBDeckSwitcherViewController", dk, 1, NO);
            Y42ST_One("Y42TraitsSceneParticipantDelegate", "SBTraitsSceneParticipantDelegate", td, 1, NO);
            Y42ST_One("SBTraitsSceneOrientationRequestAssistant", "SBTraitsSceneOrientationRequestAssistant", as, 2, NO);
        });
    }
}
