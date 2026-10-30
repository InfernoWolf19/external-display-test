// Z2OrientDelegate.m : port of the 16.2 orientation re-architecture, area 2b: SBTraitsSceneParticipantDelegate (specs/ORIENTATION-0.7.9.md section 3).
//
// 16.2 removed the iPhone-on-iPad restriction from the participant delegate of every app scene: 16.0 -_sanitizedMask:forApplication: (0x1c62d89b0) narrows the supported orientations
// of a "classic phone app running on pad" to portrait (0x6) or, with classicAppPhoneOnPadPrefersLandscape, to landscape (0x18) BEFORE the traits arbiter sees them; 16.2 (0x1c7773a88, 25
// instructions) only handles portrait-upside-down and intersects with the legal orientations.  The restriction moved into the switcher traits assistant's guiding participants
// (portrait-only / landscape-only, G3B.x BPG3BTraitsGuide) which are chosen per window (user resized orientation, old style mixed orientation, prefers landscape) and can therefore
// be LANDSCAPE for an iPhone window that the user made landscape under Stage Manager; with the 16.0 restriction still in place such a window can never leave portrait.
// Switch or_delegate (default on).  Condition: the guide is installed (switch g3b_guide on and class BPG3BTraitsGuide present); otherwise the 16.0 body runs and one log line says why
// (the restriction must not disappear without its replacement).
// Not ported here (decoded, reasons in the spec): the scene orientation request assistant (alter ego replacement), needsActuationForUpdateReasons: (framework side settings accessor).
// Logs: grep "z2o:".

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "BPY.h"

static IMP sSanitize, sDockSupported, sDockSuper;

static unsigned long long Z2OD_Sanitize(id self, SEL _cmd, unsigned long long mask, id application) {
    if (!BP_OnName("or_delegate")) return ((unsigned long long (*)(id, SEL, unsigned long long, id))sSanitize)(self, _cmd, mask, application);
    static BOOL warned;
    if (!BP_OnName("g3b_guide") || !NSClassFromString(@"BPG3BTraitsGuide")) {
        if (!warned) { warned = YES; BP_Log(@"z2o: GUARD(or_delegate) the traits guide (g3b_guide / BPG3BTraitsGuide) is not active: the 16.0 phone-on-pad mask restriction stays"); }
        return ((unsigned long long (*)(id, SEL, unsigned long long, id))sSanitize)(self, _cmd, mask, application);
    }
    SEL up = sel_registerName("_isAllowedToHavePortraitUpsideDown"), legal = sel_registerName("_allLegalOrientations");
    if (![self respondsToSelector:up] || ![self respondsToSelector:legal]) {
        if (!warned) { warned = YES; BP_Log(@"z2o: GUARD(or_delegate) %s / %s missing on %s, the 16.0 body runs", sel_getName(up), sel_getName(legal), class_getName(object_getClass(self))); }
        return ((unsigned long long (*)(id, SEL, unsigned long long, id))sSanitize)(self, _cmd, mask, application);
    }
    // 16.2 0x1c7773aac: if (mask == 4 && !allowedToHavePortraitUpsideDown) return 2; return mask & legalOrientations
    if (mask == 4 && !((BOOL (*)(id, SEL))objc_msgSend)(self, up)) return 2;
    return ((unsigned long long (*)(id, SEL))objc_msgSend)(self, legal) & mask;
}

// SBFloatingDockRootViewController -supportedInterfaceOrientations: 16.0 0x1c6336398 locks the dock to the window's current orientation mask while a presentation transition runs (when the
// traits arbiter actuation is enabled for the dock role, together with setNeedsUpdateOfSupportedInterfaceOrientations in _begin/_endPresentationTransition 16.0 0x1c5e6036c / 0x1c5e61c28);
// 16.2 has no override (the method is absent from the 16.2 class, _beginPresentationTransition / _endPresentationTransition only keep the legacy window assertion branch): the superclass
// answer.  Switch or_dock.  The setNeeds... calls stay (without the override they only re-query the superclass answer).
static unsigned long long Z2OD_DockSupported(id self, SEL _cmd) {
    if (BP_OnName("or_dock") && sDockSuper) return ((unsigned long long (*)(id, SEL))sDockSuper)(self, _cmd);
    return ((unsigned long long (*)(id, SEL))sDockSupported)(self, _cmd);
}

__attribute__((constructor)) static void Z2OD_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        Class c = NSClassFromString(@"SBTraitsSceneParticipantDelegate");
        SEL s = sel_registerName("_sanitizedMask:forApplication:");
        Method m = c ? class_getInstanceMethod(c, s) : NULL;
        if (m) {
            sSanitize = method_getImplementation(m);
            class_replaceMethod(c, s, (IMP)Z2OD_Sanitize, method_getTypeEncoding(m));
        } else BP_Log(@"z2o: GUARD SBTraitsSceneParticipantDelegate -_sanitizedMask:forApplication: not found, not replaced");
        Class dock = NSClassFromString(@"SBFloatingDockRootViewController");
        SEL ds = sel_registerName("supportedInterfaceOrientations");
        Method dm = dock ? class_getInstanceMethod(dock, ds) : NULL;
        Method sm = dock ? class_getInstanceMethod(class_getSuperclass(dock), ds) : NULL;
        if (dm && sm && method_getImplementation(dm) != method_getImplementation(sm)) {
            sDockSupported = method_getImplementation(dm);
            sDockSuper = method_getImplementation(sm);
            class_replaceMethod(dock, ds, (IMP)Z2OD_DockSupported, method_getTypeEncoding(dm));
        } else BP_Log(@"z2o: GUARD SBFloatingDockRootViewController -supportedInterfaceOrientations has no own implementation (dock %d, method %d, super %d), not replaced", dock != Nil, dm != NULL, sm != NULL);
        BP_Log(@"z2o: delegate installed sanitizedMask=%d dockSupported=%d (switches or_delegate, or_dock)", sSanitize != NULL, sDockSupported != NULL);
    }
}
