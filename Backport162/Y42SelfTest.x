// Y42SelfTest.x : on-install self test of the runtime subclasses of the Y34 / Y42 ports (a lesson of the SpringBoard crash caused by the dealloc of a runtime subclass).  Setup: constructor.  NOT device tested.
//
//  15 s after launch (main queue, after every constructor and the boot sequence) every runtime class is checked WITHOUT creating an instance (class structure: superclass, instance size, added ivars behind the base instance, own
//  .cxx_destruct, identity shims).  The earlier version created bare allocated instances and released them: that crashed SpringBoard (build 387).  Classes: Y34ClassicWrapperView, Y42DeckSwitcherViewController, Y42TraitsSceneParticipantDelegate, SBTraitsSceneOrientationRequestAssistant (the SBSceneView of
//  Y34DeviceApplicationSceneView is tested by Y42SceneView.x).  The result of each class is logged ALWAYS as ANOMALY y42-selftest (class, ivars, teardown).  A class that is not installed is reported as such.
// Switch y42_selftest (kill file Backport162.off.y42_selftest).  Only on build 20A8372.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"

// NO instance is created here: a self test must never be able to crash SpringBoard (build 387 died in the release of a bare allocated instance of one of these classes: never init'ed objects reach hand ported
// teardown code with half built state).  Only the class structure is checked: the runtime subclass exists, its superclass is the 16.0 class, every added ivar is there and lies behind the instance of the base
// class, the identity shims (-class, -isMemberOfClass:) and the teardown method (.cxx_destruct) are defined by the subclass itself.  The instance level check of the device scene view (a properly init'ed UIView)
// is Y42SceneView.x.
static void Y42ST_One(const char *extName, const char *baseName, const char *const *ivars, int nIvars, BOOL shims) {
    Class ext = objc_getClass(extName);
    Class base = objc_getClass(baseName);
    if (!ext || !base) { BP_Anomaly("y42-selftest", @"[y42] self test %s: class %s: not installed (the 16.0 class is used)", extName, ext ? baseName : extName); return; }
    NSMutableArray *bad = [NSMutableArray array];
    if (class_getSuperclass(ext) != base && ext != base) [bad addObject:@"superclass is not the base class"];
    size_t baseSize = class_getInstanceSize(base), extSize = class_getInstanceSize(ext);
    if (ext != base && extSize <= baseSize) [bad addObject:[NSString stringWithFormat:@"instance size %zu not larger than the base %zu", extSize, baseSize]];
    for (int k = 0; k < nIvars; k++) {
        Ivar iv = class_getInstanceVariable(ext, ivars[k]);
        if (!iv) [bad addObject:[NSString stringWithFormat:@"ivar %s missing", ivars[k]]];
        else if (ext != base && (size_t)ivar_getOffset(iv) < baseSize) [bad addObject:[NSString stringWithFormat:@"ivar %s at %td lies inside the base instance (%zu)", ivars[k], ivar_getOffset(iv), baseSize]];
    }
    unsigned n = 0; Method *ms = class_copyMethodList(ext, &n);
    BOOL dtor = NO, cls = NO, mem = NO;
    for (unsigned k = 0; k < n; k++) { const char *nm = sel_getName(method_getName(ms[k])); if (!strcmp(nm, ".cxx_destruct")) dtor = YES; if (!strcmp(nm, "class")) cls = YES; if (!strcmp(nm, "isMemberOfClass:")) mem = YES; }
    free(ms);
    if (ext != base && !dtor) [bad addObject:@"no own .cxx_destruct (the added ivars would not be released)"];
    if (shims && (!cls || !mem)) [bad addObject:@"identity shims (-class / -isMemberOfClass:) missing"];
    BP_Anomaly("y42-selftest", @"[y42] self test %s (class structure only, no instance): %@ ; instance size %zu (base %zu), %d added ivar(s), own .cxx_destruct %@, identity shims %@ (OS build 20A8372)", extName, bad.count ? [@"FAILED: " stringByAppendingString:[bad componentsJoinedByString:@"; "]] : @"OK", extSize, baseSize, nIvars, dtor ? @"yes" : @"no", shims ? (cls && mem ? @"yes" : @"NO") : @"not required");
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
            Y42ST_One("Y42DeckSwitcherViewController", "SBDeckSwitcherViewController", dk, 1, YES);
            Y42ST_One("Y42TraitsSceneParticipantDelegate", "SBTraitsSceneParticipantDelegate", td, 1, YES);
            Y42ST_One("SBTraitsSceneOrientationRequestAssistant", "SBTraitsSceneOrientationRequestAssistant", as, 2, NO);
        });
    }
}
