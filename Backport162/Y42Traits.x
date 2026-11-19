// Y42Traits.x : delta sweep pass 4 (block capable recompiler), the orientation request handling of the traits scene participant of iPadOS 16.2.  Setup: constructor.  Log prefix "[y42]".  NOT device tested.
//
//  y42_traits  16.2 moved the "alter ego" scene orientation request (the scene is asked to rotate before it is shown: desired orientations, the initial device orientation, the fence / transition context
//              broadcast) out of SBTraitsSceneParticipantDelegate into a NEW class SBTraitsSceneOrientationRequestAssistant (16.2 only, 12 functions 0x1c78246e0 ..: init 0x1c78246e0, invalidate 0x1c782476c,
//              checkValidityAgainstUpdateReasons: 0x1c7824818, setUpForTransitionContextIfNeeded: 0x1c7824a00, _startSceneOrientationRequestWithDesiredOrientations:error: 0x1c7824cfc,
//              _performCoalescedBroadcastArbitrationUpdateWithReason: 0x1c7824f3c, traitsDelegate 0x1c7825078, errorDomain 0x1c78250a4, .cxx_destruct 0x1c78250d0 and the blocks 0x1c78249ac 0x1c7824cd8 0x1c7825008)
//              and rewrote six methods of the delegate:  -_supportedOrientations 0x1c77736b8 (16.0 0x1c62d8...), -actuateOrientationSettingsWithContext: 0x1c7773c68, -needsActuationForUpdateReasons: 0x1c77743e4,
//              -scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext: 0x1c7774a98, -_resetToInitialState 0x1c77750bc, -didChangeSettingsForParticipant:context: 0x1c77752c8 (with their blocks and the
//              16.2 C function SBTraitsSceneParticipantDelegateOrientationChangeInspector 0x1c7772d24, which 16.0 does not export).  All of it is NOT re-typed: Y42TraitsLift.c is the 16.2 machine code recompiled
//              by tools/a2c/a2c.py (stack blocks with arm64e pointer signing, indirect block calls).  Verified with tools/a2c/tests/tracecmp.py on 24 seeds per body (every message / C call, every retain / release /
//              autorelease / claim / storeStrong in order, PAC operations, block images, memory, result).
//   The assistant class is created at run time (ivars _traitsDelegate weak, _errorDomain; its .cxx_destruct is the recompiled one).  The 16.2 delegate has one ivar the 16.0 delegate does not have that these
//   rows use, _orientationRequestActionAssistant: it lives in a RUNTIME SUBCLASS "Y42TraitsSceneParticipantDelegate" (Y34Ext.h: class_addIvar, own .cxx_destruct, -class / -isMemberOfClass: shims) that every
//   SBTraitsSceneParticipantDelegate allocation produces (+allocWithZone: of the base class swapped, as Y34ClassicSupport.x does).  The 16.0 alter ego ivars / methods stay where they are (the other
//   delegate methods are the 16.0 ones, the rows above no longer use them).  The scene handle state the assistant reads and writes (-_setSettingUpSceneOrientationRequest: and the initial / supported
//   orientation accessors, -_setInterfaceOrientationFromUserResizing:) is G3.x; the install is refused (ANOMALY y42, all misses named) when a piece is missing.
//   What can break on a device: the runtime subclass of a class created for EVERY scene (identity shimmed; an instance that is not of the subclass runs the 16.0 methods), signed stack blocks (arm64e),
//   the run time created assistant class (ARC ivar layout of runtime-added ivars is not known to the runtime: the recompiled destructor releases them), a scene that rotates differently (16.2 request flow).
// Switch y42_traits (kill file Backport162.off.y42_traits).  Installed only on build 20A8372; ANOMALY y42-traits (always on) names the build.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Y17Common.h"
#import "Y34Ext.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

extern void *y42t_storeWeak(void **location, void *obj) __asm__("_objc_storeWeak");
extern uint64_t y42_as_init(uint64_t self, uint64_t cmd, uint64_t delegate, uint64_t domain);
extern void y42_as_invalidate(uint64_t self, uint64_t cmd);
extern void y42_as_check(uint64_t self, uint64_t cmd, uint64_t reasons);
extern void y42_as_setup(uint64_t self, uint64_t cmd, uint64_t context);
extern void y42_as_start(uint64_t self, uint64_t cmd, uint64_t orientations, uint64_t errorOut);
extern void y42_as_perform(uint64_t self, uint64_t cmd, uint64_t reason);
extern uint64_t y42_as_delegate(uint64_t self, uint64_t cmd);
extern uint64_t y42_as_errordomain(uint64_t self, uint64_t cmd);
extern void y42_as_destruct(uint64_t self, uint64_t cmd);
extern uint64_t y42_td_supported(uint64_t self, uint64_t cmd);
extern void y42_td_actuate(uint64_t self, uint64_t cmd, uint64_t context);
extern uint64_t y42_td_needs(uint64_t self, uint64_t cmd, uint64_t reasons);
extern void y42_td_scene(uint64_t self, uint64_t cmd, uint64_t scene, uint64_t diff, uint64_t old, uint64_t context);
extern void y42_td_reset(uint64_t self, uint64_t cmd);
extern void y42_td_didchange(uint64_t self, uint64_t cmd, uint64_t participant, uint64_t context);
extern const char *y42_traits_preflight(void);

static Class gTdBase, gTdExt;
static Ivar gIvAssistant;
static IMP gOrigAlloc, gOrigSupported, gOrigActuate, gOrigNeeds, gOrigScene, gOrigReset, gOrigDidChange;

#define Y42_P(o) ((uint64_t)(uintptr_t)(__bridge void *)(o))
#define Y42_C(c) ((uint64_t)(uintptr_t)(void *)(c))

static BOOL Y42_Mine(id self) { return gTdExt && [self isKindOfClass:gTdExt]; }
// the scene handle state of the 16.2 assistant (G3.x): asked at the first use, until it is there the 16.0 methods run
static BOOL Y42_HandleState(void) {
    static BOOL ok;
    if (ok) return YES;
    Class h = NSClassFromString(@"SBDeviceApplicationSceneHandle");
    const char *need[] = { "_setSettingUpSceneOrientationRequest:", "_isSettingUpSceneOrientationRequest", "_setInitialDeviceOrientationFromSceneOrientationRequestSetup:", "_initialDeviceOrientationFromSceneOrientationRequestSetup",
                           "_setSupportedInterfaceOrientationsFromSceneOrientationRequestSetup:", "_supportedInterfaceOrientationsFromSceneOrientationRequestSetup", "_setInterfaceOrientationFromUserResizing:" };
    NSMutableArray *miss = [NSMutableArray array];
    for (size_t k = 0; k < sizeof need / sizeof need[0]; k++) if (!h || !class_getInstanceMethod(h, sel_registerName(need[k]))) [miss addObject:[NSString stringWithUTF8String:need[k]]];
    if (miss.count) { BP_Anomaly("y42", @"[y42] y42_traits: SBDeviceApplicationSceneHandle misses %@ (G3.x): the 16.0 methods ran", [miss componentsJoinedByString:@", "]); return NO; }
    ok = YES;
    return YES;
}
#define Y42_USE(self) (BP_OnName("y42_traits") && Y42_Mine(self) && Y42_HandleState())

static unsigned long long Y42_TdSupported(id self, SEL _cmd) {
    if (!Y42_USE(self)) return ((unsigned long long (*)(id, SEL))gOrigSupported)(self, _cmd);
    return y42_td_supported(Y42_P(self), Y42_C(_cmd));
}
static void Y42_TdActuate(id self, SEL _cmd, id context) {
    if (!Y42_USE(self)) { ((void (*)(id, SEL, id))gOrigActuate)(self, _cmd, context); return; }
    y42_td_actuate(Y42_P(self), Y42_C(_cmd), Y42_P(context));
}
static BOOL Y42_TdNeeds(id self, SEL _cmd, long long reasons) {
    if (!Y42_USE(self)) return ((BOOL (*)(id, SEL, long long))gOrigNeeds)(self, _cmd, reasons);
    return y42_td_needs(Y42_P(self), Y42_C(_cmd), (uint64_t)reasons) & 1;
}
static void Y42_TdScene(id self, SEL _cmd, id scene, id diff, id old, id context) {
    if (!Y42_USE(self)) { ((void (*)(id, SEL, id, id, id, id))gOrigScene)(self, _cmd, scene, diff, old, context); return; }
    y42_td_scene(Y42_P(self), Y42_C(_cmd), Y42_P(scene), Y42_P(diff), Y42_P(old), Y42_P(context));
}
static void Y42_TdReset(id self, SEL _cmd) {
    if (!Y42_USE(self)) { ((void (*)(id, SEL))gOrigReset)(self, _cmd); return; }
    y42_td_reset(Y42_P(self), Y42_C(_cmd));
}
static void Y42_TdDidChange(id self, SEL _cmd, id participant, id context) {
    if (!Y42_USE(self)) { ((void (*)(id, SEL, id, id))gOrigDidChange)(self, _cmd, participant, context); return; }
    y42_td_didchange(Y42_P(self), Y42_C(_cmd), Y42_P(participant), Y42_P(context));
}
static id Y42_TdAlloc(id self, SEL _cmd, void *zone) {
    Class use = (self == (id)gTdBase) ? gTdExt : (Class)self;
    return ((id (*)(id, SEL, void *))gOrigAlloc)((id)use, _cmd, zone);
}
// the assistant ivar of the subclass is released by hand (a runtime-added ivar is not known to the runtime)
static void Y42_TdDestruct(id self, SEL _cmd) { Y34_ObjRelease(self, gIvAssistant); }

__attribute__((constructor)) static void Y42Traits_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        if (!BP_OnName("y42_traits")) return;
        gTdBase = NSClassFromString(@"SBTraitsSceneParticipantDelegate");
        if (!gTdBase) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: SBTraitsSceneParticipantDelegate missing"); return; }
        if (NSClassFromString(@"SBTraitsSceneOrientationRequestAssistant")) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: SBTraitsSceneOrientationRequestAssistant already exists"); return; }
        struct { const char *s; } dsel[] = { { "_supportedOrientations" }, { "actuateOrientationSettingsWithContext:" }, { "needsActuationForUpdateReasons:" },
            { "scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:" }, { "_resetToInitialState" }, { "didChangeSettingsForParticipant:context:" } };
        NSMutableArray *missing = [NSMutableArray array];
        for (size_t k = 0; k < sizeof dsel / sizeof dsel[0]; k++) if (!class_getInstanceMethod(gTdBase, sel_registerName(dsel[k].s))) [missing addObject:[NSString stringWithFormat:@"-[SBTraitsSceneParticipantDelegate %s]", dsel[k].s]];
        if (!BP_IvarLookup(gTdBase, "_orientationMode")) [missing addObject:@"ivar _orientationMode"];
        if (!BP_IvarLookup(gTdBase, "_fallbackFence_90210730")) [missing addObject:@"ivar _fallbackFence_90210730"];
        if (!BP_IvarLookup(gTdBase, "_sceneClientSettingsDiffInspector")) [missing addObject:@"ivar _sceneClientSettingsDiffInspector"];
        if (!BP_IvarLookup(gTdBase, "_canDetermineActiveOrientation")) [missing addObject:@"ivar _canDetermineActiveOrientation"];
        if (!BP_IvarLookup(gTdBase, "_actuateOrientationAlongsideBlock")) [missing addObject:@"ivar _actuateOrientationAlongsideBlock"];
        if (missing.count) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: missing %@: the 16.0 delegate stays", [missing componentsJoinedByString:@", "]); return; }
        Method am = class_getClassMethod(gTdBase, @selector(allocWithZone:));
        gOrigAlloc = am ? method_getImplementation(am) : NULL;
        if (!gOrigAlloc) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: +allocWithZone: not found"); return; }

        // 1. the 16.2 only class (ivars and every method before the registration, so that the runtime sees the destructor)
        Class assistant = objc_allocateClassPair([NSObject class], "SBTraitsSceneOrientationRequestAssistant", 0);
        if (!assistant) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: objc_allocateClassPair of the assistant failed"); return; }
        BOOL ok = class_addIvar(assistant, "_traitsDelegate", sizeof(void *), 3, "@") && class_addIvar(assistant, "_errorDomain", sizeof(void *), 3, "@");
        ok = ok && class_addMethod(assistant, sel_registerName("initWithTraitsSceneDelegate:errorDomain:"), (IMP)y42_as_init, "@@:@@");
        ok = ok && class_addMethod(assistant, sel_registerName("invalidate"), (IMP)y42_as_invalidate, "v@:");
        ok = ok && class_addMethod(assistant, sel_registerName("checkValidityAgainstUpdateReasons:"), (IMP)y42_as_check, "v@:q");
        ok = ok && class_addMethod(assistant, sel_registerName("setUpForTransitionContextIfNeeded:"), (IMP)y42_as_setup, "v@:@");
        ok = ok && class_addMethod(assistant, sel_registerName("_startSceneOrientationRequestWithDesiredOrientations:error:"), (IMP)y42_as_start, "v@:Q^@");
        ok = ok && class_addMethod(assistant, sel_registerName("_performCoalescedBroadcastArbitrationUpdateWithReason:"), (IMP)y42_as_perform, "v@:@");
        ok = ok && class_addMethod(assistant, sel_registerName("traitsDelegate"), (IMP)y42_as_delegate, "@@:");
        ok = ok && class_addMethod(assistant, sel_registerName("errorDomain"), (IMP)y42_as_errordomain, "@@:");
        ok = ok && class_addMethod(assistant, sel_registerName(".cxx_destruct"), (IMP)y42_as_destruct, "v@:");
        if (!ok) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: building the assistant class failed"); objc_disposeClassPair(assistant); return; }
        objc_registerClassPair(assistant);

        // 2. the runtime subclass of the delegate with the one 16.2 ivar the rows use
        static const Y34IvarSpec ivars[] = { { "_orientationRequestActionAssistant", sizeof(void *), 3, "@" } };
        gTdExt = Y34_MakeExt("SBTraitsSceneParticipantDelegate", "Y42TraitsSceneParticipantDelegate", ivars, 1);
        if (!gTdExt) return;
        gIvAssistant = class_getInstanceVariable(gTdExt, "_orientationRequestActionAssistant");
        if (!gIvAssistant) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: the subclass ivar is missing"); gTdExt = Nil; return; }
        Y34_AddIdentityShims(gTdExt, gTdBase);
        lift_register_ext("SBTraitsSceneParticipantDelegate", (__bridge void *)gTdExt);
        const char *miss = y42_traits_preflight();
        if (miss) { BP_Anomaly("y42", @"[y42] y42_traits NOT installed: unresolved names of the recompiled 16.2 bodies: %s: the 16.0 delegate stays (the assistant class and the delegate subclass exist but are unused)", miss); gTdExt = Nil; return; }
        class_addMethod(gTdExt, sel_registerName(".cxx_destruct"), (IMP)Y42_TdDestruct, "v@:");
        gOrigSupported = BPX_Replace(gTdBase, dsel[0].s, (IMP)Y42_TdSupported);
        gOrigActuate = BPX_Replace(gTdBase, dsel[1].s, (IMP)Y42_TdActuate);
        gOrigNeeds = BPX_Replace(gTdBase, dsel[2].s, (IMP)Y42_TdNeeds);
        gOrigScene = BPX_Replace(gTdBase, dsel[3].s, (IMP)Y42_TdScene);
        gOrigReset = BPX_Replace(gTdBase, dsel[4].s, (IMP)Y42_TdReset);
        gOrigDidChange = BPX_Replace(gTdBase, dsel[5].s, (IMP)Y42_TdDidChange);
        Class meta = object_getClass((id)gTdBase);
        class_replaceMethod(meta, @selector(allocWithZone:), (IMP)Y42_TdAlloc, method_getTypeEncoding(am));
        BP_Log(@"[y42] installed y42_traits");
        BP_Anomaly("y42-traits", @"[y42] y42_traits active (NOT device tested): the 16.2 orientation request assistant class (run time created) and the six recompiled 16.2 delegate methods replace the 16.0 alter ego code; every SBTraitsSceneParticipantDelegate is allocated as the runtime subclass Y42TraitsSceneParticipantDelegate (+allocWithZone: replaced, -class answers the 16.0 class); OS build 20A8372, tweak object compiled %s %s; kill file Backport162.off.y42_traits", __DATE__, __TIME__);
    }
}
#pragma clang diagnostic pop
