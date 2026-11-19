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
        // alloc / init through ARC's own family rules (a cast objc_msgSend call leaves the +1 of alloc unbalanced: the test itself would leak the object); non views are not init'ed (a bare alloc is a valid object
        // for dealloc and the 16.0 designated initialisers must not run here)
        id v = [(Class)ext alloc];
        if (isView) v = [(UIView *)v initWithFrame:CGRectZero];
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
    if (weak == nil) { BP_Anomaly("y42-selftest", @"[y42] self test %s: %@ ; teardown OK: deallocated (OS build 20A8372)", extName, res); return; }
    BP_Anomaly("y42-selftest", @"[y42] self test %s: %@ ; teardown NOT YET: still alive right after the release (retain count %ld), re-checked after 1 s (OS build 20A8372)", extName, res, (long)CFGetRetainCount((__bridge CFTypeRef)weak) - 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        id s = weak;
        BP_Anomaly("y42-selftest", @"[y42] self test %s after 1 s: %@", extName, s ? [NSString stringWithFormat:@"FAILED: still alive, retain count %ld: a LEAK of the runtime subclass (what holds it is not visible from here)", (long)CFGetRetainCount((__bridge CFTypeRef)s) - 1] : @"teardown OK: deallocated");
    });
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
