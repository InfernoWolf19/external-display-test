// Z2OrientTraits.m : port of the 16.2 orientation re-architecture, area 1 + 2: the traits flow of the switcher (specs/ORIENTATION-0.7.9.md sections 1, 2).
//
// 16.2 (20C65) moved the whole participant / orientation evaluation of SBSwitcherController into SBSwitcherTraitsAssistant and changed the decision logic of
//   -[SBSwitcherController switcherOrientation:elementsOrientations:forTransitionRequest:previousLayoutState:layoutState:]   16.2 0x1c7600950   16.0 0x1c6178cec
// in three places, moved the "follow up rotation" out of that method into -layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext: (16.2 0x1c76042cc,
// the 16.0 method is a 3 instruction stub 0x1c617c79c), removed the ivar _waitingFollowupTransition, gave every orientation transition request a unique label
// (-_enqueueOrientationTransitionWithActuationContext:... 16.2 0x1c760212c, label "%@-%ld") and added -actuateOrientationForTraitsDelegate:withContext:reasons: (0x1c7601958).
// The 16.0 ivar layout of SBSwitcherController cannot grow (subclasses follow it), so the one new ivar (_needsOrientationReevaluation, 16.2 +0x7a) is an associated object and
// the 16.0 helpers that already do the work (participant creation, policies, element orientation map, app transition context update) are called from a body that is the
// 16.2 body statement by statement.  Switches (default on, Backport162.off.<name> kill files; every replaced IMP runs the saved 16.0 IMP when its switch is off):
//   or_traits    the 16.2 body of switcherOrientation:... (decision rules, follow-up in transitionDidBegin, actuation context handling)
//   or_label     unique label "<label>-<n>" of orientation transition requests
//   or_extinputs the arbiter input of an EXTERNAL display (SBTraitsExternalDisplayPipelineManager -inputs, 16.0 0x1c616fa60 / 16.2 0x1c75f7740, same body) is the display's
//                real orientation and is refreshed when the scene changes: 16.0 builds the input object once (lazy ivar _inputs) from [windowScene interfaceOrientation] at the
//                first call and never again; everything that follows the monitor's "device orientation" then resolves against that snapshot.  DEVIATION from the 16.2 body (which
//                has the same lazy cache) because on 16.2 the scene is already in its final orientation at that moment; documented in ORIENTATION-0.7.9.md section 2.
//   or_extreal   last line guard: a layout state orientation of an external display that contradicts the display shape is replaced by the real orientation (logged GUARD)
// Logs: grep "z2o:" in Backport162.log (debug only).

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "BPY.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

// ------------------------------------------------------------------------------------------------ helpers (receiver checked, missing selector logged once per class + selector)
static NSMutableSet *gZ2OMissing;
static void Z2O_NoteMissing(id o, SEL s, const char *who) {
    @synchronized ([NSObject class]) {
        if (!gZ2OMissing) gZ2OMissing = [NSMutableSet new];
        NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(object_getClass(o)), sel_getName(s)];
        if ([gZ2OMissing containsObject:key]) return;
        [gZ2OMissing addObject:key];
    }
    BP_Log(@"z2o: GUARD selector missing: -[%s %s] (needed by %s), answering nil / 0 / NO", class_getName(object_getClass(o)), sel_getName(s), who);
}
static BOOL Z2O_Has(id o, const char *sel, const char *who) {
    if (!o) return NO;
    SEL s = sel_registerName(sel);
    if ([o respondsToSelector:s]) return YES;
    Z2O_NoteMissing(o, s, who);
    return NO;
}
static id Z2O_Obj0(id o, const char *sel, const char *who) { return Z2O_Has(o, sel, who) ? ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : nil; }
static id Z2O_Obj1(id o, const char *sel, id a, const char *who) { return Z2O_Has(o, sel, who) ? ((id (*)(id, SEL, id))objc_msgSend)(o, sel_registerName(sel), a) : nil; }
static long long Z2O_LL0(id o, const char *sel, const char *who) { return Z2O_Has(o, sel, who) ? ((long long (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : 0; }
static BOOL Z2O_Bool0(id o, const char *sel, const char *who) { return Z2O_Has(o, sel, who) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : NO; }
static CGRect Z2O_Rect0(id o, const char *sel, const char *who) { return Z2O_Has(o, sel, who) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, sel_registerName(sel)) : CGRectZero; }

static Ivar Z2O_Iv(id o, const char *name) {
    if (!o) return NULL;
    for (Class c = object_getClass(o); c; c = class_getSuperclass(c)) {
        Ivar v = class_getInstanceVariable(c, name);
        if (v) return v;
    }
    static NSMutableSet *seen;
    @synchronized ([NSObject class]) {
        if (!seen) seen = [NSMutableSet new];
        NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(object_getClass(o)), name];
        if ([seen containsObject:key]) return NULL;
        [seen addObject:key];
    }
    BP_Log(@"z2o: GUARD ivar missing: %s.%s", class_getName(object_getClass(o)), name);
    return NULL;
}
static id Z2O_IvObj(id o, const char *name) { Ivar v = Z2O_Iv(o, name); return (v && o) ? object_getIvar(o, v) : nil; }
static BOOL Z2O_IvBool(id o, const char *name) { Ivar v = Z2O_Iv(o, name); return (v && o) ? *(BOOL *)((uint8_t *)(__bridge void *)o + ivar_getOffset(v)) : NO; }
static void Z2O_SetIvBool(id o, const char *name, BOOL b) { Ivar v = Z2O_Iv(o, name); if (v && o) *(BOOL *)((uint8_t *)(__bridge void *)o + ivar_getOffset(v)) = b; }
static void Z2O_SetIvLL(id o, const char *name, long long x) { Ivar v = Z2O_Iv(o, name); if (v && o) *(long long *)((uint8_t *)(__bridge void *)o + ivar_getOffset(v)) = x; }
static void Z2O_SetIvObj(id o, const char *name, id val) {      // strong ivar of an ARC compiled class: object_setIvar retains the new and releases the old value (ivar layout says strong)
    Ivar v = Z2O_Iv(o, name);
    if (v && o) object_setIvar(o, v, val);
}

static const char kZ2OReeval;     // _needsOrientationReevaluation (16.2 ivar +0x7a, absent in the 16.0 layout)
static BOOL Z2O_GetReeval(id o) { return [objc_getAssociatedObject(o, &kZ2OReeval) boolValue]; }
static void Z2O_SetReeval(id o, BOOL b) { objc_setAssociatedObject(o, &kZ2OReeval, b ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

static BOOL Z2O_ValidOri(long long o) { return o >= 1 && o <= 4; }
static BOOL Z2O_IsLandscapeOri(long long o) { return o == 3 || o == 4; }
static const char *Z2O_Tag(id switcher) { return Z2O_Bool0(Z2O_Obj0(switcher, "windowScene", "z2o tag"), "isExternalDisplayWindowScene", "z2o tag") ? "ext" : "main"; }

// shape of a window scene's canvas: 2 landscape, 1 portrait, 0 unknown
static int Z2O_SceneShape(id scene) {
    id cs = Z2O_Obj0(scene, "coordinateSpace", "z2o shape");
    CGRect b = Z2O_Rect0(cs, "bounds", "z2o shape");
    if (b.size.width <= 0 || b.size.height <= 0) return 0;
    return b.size.width > b.size.height ? 2 : 1;
}
// the real orientation of an external display: the scene's own interface orientation when it agrees with the canvas shape, else derived from the shape
// (the stack from the calculator to the page containers uses the iPad convention: landscape shaped canvas <-> landscape orientation, 16.0 logs show 3 for the 2560x1440 monitor)
static long long Z2O_RealOrientation(id scene, long long *outSceneOri) {
    long long so = Z2O_LL0(scene, "interfaceOrientation", "z2o real");
    if (outSceneOri) *outSceneOri = so;
    int shape = Z2O_SceneShape(scene);
    if (shape == 0) return Z2O_ValidOri(so) ? so : 1;
    if (Z2O_ValidOri(so) && (Z2O_IsLandscapeOri(so) == (shape == 2))) return so;
    return shape == 2 ? 3 : 1;
}

// ------------------------------------------------------------------------------------------------ 1. -switcherOrientation:elementsOrientations:forTransitionRequest:previousLayoutState:layoutState:
typedef void (*Z2OSwOriFn)(id, SEL, long long *, id __autoreleasing *, id, id, id);
static Z2OSwOriFn sSwOri;
static IMP sEnqueue, sInputs;
static long sEnqCounter;

typedef struct { long long own, nonPrimary, primary; BOOL reeval; } Z2OPolicy;

// 16.2 0x1c7600b80 .. 0x1c7600c80 (16.0 0x1c6178f20 .. 0x1c6178ff8).  Changes against 16.0:
//  * chamois: system gesture OR (from the switcher into an app) -> own policy 5 AND re-evaluate; otherwise inSwitcher ? 5 : 4  (16.0: inSwitcher ? 5 : 4 only)
//  * non primary overlay policy = phone app on pad ? 3 : primary policy for the stable in app paths (16.0: always 3)
//  * the 16.0 branch "_waitingFollowupTransition -> 1,1,1" is gone with the ivar
static Z2OPolicy Z2O_GuardPolicy(BOOL reeval, BOOL phoneOnPad) {          // the 16.2 label 0x1c7600c58: own 5, primary 3, non primary = phone app on pad ? 3 : primary
    Z2OPolicy p = {5, 3, 3, reeval};
    p.nonPrimary = phoneOnPad ? 3 : p.primary;
    return p;
}
static Z2OPolicy Z2O_Decide(id notes, BOOL chamois, BOOL phoneOnPad, BOOL havePrimaryEntity) {
    Z2OPolicy p = {0, 3, 3, NO};
    BOOL sysGesture = Z2O_Bool0(notes, "isSystemGesture", "z2o decide");
    if (chamois) {
        if (sysGesture || (Z2O_Bool0(notes, "fromSwitcher", "z2o decide") && Z2O_Bool0(notes, "inApp", "z2o decide"))) { p.reeval = YES; p.own = 5; }
        else { p.reeval = NO; p.own = Z2O_Bool0(notes, "inSwitcher", "z2o decide") ? 5 : 4; }
        return p;                                                            // non primary 3, primary 3
    }
    if (sysGesture || Z2O_Bool0(notes, "isPIPRestore", "z2o decide")) { (void)Z2O_Bool0(notes, "movingToSingleApp", "z2o decide"); return Z2O_GuardPolicy(YES, phoneOnPad); }
    if (Z2O_Bool0(notes, "fromHomeScreenToApp", "z2o decide") || Z2O_Bool0(notes, "stableInAppOrMovingBetweenSingleApp", "z2o decide")) {
        if (!havePrimaryEntity) { (void)Z2O_Bool0(notes, "movingToSingleApp", "z2o decide"); return Z2O_GuardPolicy(YES, phoneOnPad); }
        p.own = phoneOnPad ? 4 : 3;
        p.reeval = NO;
        p.primary = Z2O_Bool0(notes, "movingToSingleApp", "z2o decide") ? 6 : 4;
        p.nonPrimary = phoneOnPad ? 3 : p.primary;
        return p;
    }
    if (Z2O_Bool0(notes, "fromAppToHomeScreen", "z2o decide")) { (void)Z2O_Bool0(notes, "movingToSingleApp", "z2o decide"); return Z2O_GuardPolicy(YES, phoneOnPad); }
    if (Z2O_Bool0(notes, "stableInHomeScreen", "z2o decide")) {
        p.own = 2; p.reeval = NO;
        p.primary = Z2O_Bool0(notes, "movingToSingleApp", "z2o decide") ? 6 : 4;
        p.nonPrimary = phoneOnPad ? 3 : p.primary;
        return p;
    }
    (void)Z2O_Bool0(notes, "movingToSingleApp", "z2o decide");
    return Z2O_GuardPolicy(!Z2O_Bool0(notes, "inSwitcher", "z2o decide"), phoneOnPad);   // 16.2 0x1c7601118: re-evaluate = !inSwitcher
}

static BOOL Z2O_FlowReady(id sw) {
    static const char *need[] = { "_traitsParticipant", "_arbiterActuationContext", "_panGestureRecognizerRequestedOrientation", "_isPublishedOrientationLocked", "_canDetermineActiveOrientation",
                                  "_evaluatingLayoutStateOrientation", "_primaryElementTraitsParticipantDelegate", "_waitingFollowupTransition" };
    for (size_t i = 0; i < sizeof need / sizeof need[0]; i++) if (!Z2O_Iv(sw, need[i])) return NO;
    SEL sels[] = { sel_registerName("_setupSwitcherTraitsParticipantAndPolicySpecifiers"), sel_registerName("_createTraitsParticipantsForLayoutElementsIfNeeded:shouldPerformFirstResolution:"),
                   sel_registerName("_updateParticipantsAndPoliciesWithSwitcherPolicy:nonPrimaryOverlayPolicy:primaryOverlayPolicy:"),
                   sel_registerName("_updateAppTransitionContext:withOrientationActuationContext:accountForSceneState:"), sel_registerName("_currentElementsOrientationsForLayoutState:") };
    for (size_t i = 0; i < sizeof sels / sizeof sels[0]; i++) if (![sw respondsToSelector:sels[i]]) { Z2O_NoteMissing(sw, sels[i], "switcherOrientation flow"); return NO; }
    if (!NSClassFromString(@"SBSwitcherLayoutTransitionNotes") || !NSClassFromString(@"SBAnimationUtilities")) { BP_Log(@"z2o: GUARD class missing for the traits flow"); return NO; }
    return YES;
}

// External display guard (or_extreal): the container orientation of a layout state must agree with the display's canvas
static long long Z2O_GuardExternal(id sw, long long o, id request) {
    id scene = Z2O_Obj0(sw, "windowScene", "z2o guard");
    if (!Z2O_Bool0(scene, "isExternalDisplayWindowScene", "z2o guard")) return o;
    long long sceneOri = 0, real = Z2O_RealOrientation(scene, &sceneOri);
    int shape = Z2O_SceneShape(scene);
    BOOL consistent = Z2O_ValidOri(o) && (shape == 0 || Z2O_IsLandscapeOri(o) == (shape == 2));
    BPY_LOG(@"z2o: ext display state orientation: participant %lld, scene orientation %lld, canvas shape %d -> real %lld (%@) request %@", o, sceneOri, shape, real, consistent ? @"consistent" : @"CONTRADICTS", Z2O_Obj0(request, "eventLabel", "z2o guard"));
    if (consistent) return o;
    if (!BP_OnName("or_extreal")) { BP_Log(@"z2o: ext display orientation %lld contradicts the canvas shape %d (guard switch or_extreal is off, kept)", o, shape); return o; }
    BP_Log(@"z2o: GUARD(or_extreal) external display layout state orientation %lld contradicts canvas shape %d (scene orientation %lld): using %lld", o, shape, sceneOri, real);
    return real;
}

// Which rotation machinery is live in 16.0?  16.0 gates the traits arbiter orientation actuation behind feature flags (_SBTraitsArbiterActuationEnabled 0x1c5f9bdf4 =
// os_feature_enabled(SpringBoard, TraitsArbiterActuation) || ...; _SBPostModernRotationEnabled 0x1c616e980 = PostModernRotation || TraitsArbiterActuation || the rotation defaults);
// 16.2 removed the flags (every role except a fixed exclusion list actuates, 0x1c7414d24) together with the pre modern rotation code.  One line per run names the live state.
static void Z2O_LogRotationMachinery(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL (*act)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "_SBTraitsArbiterActuationEnabled");
        BOOL (*pm)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "_SBPostModernRotationEnabled");
        BOOL (*forRole)(id) = (BOOL (*)(id))dlsym(RTLD_DEFAULT, "_SBTraitsArbiterOrientationActuationEnabledForRole");
        BP_Log(@"z2o: 16.0 rotation machinery: TraitsArbiterActuationEnabled=%@ PostModernRotationEnabled=%@ (role actuation function %@; 16.2 has no flags)",
               act ? (act() ? @"YES" : @"NO") : @"(symbol not found)", pm ? (pm() ? @"YES" : @"NO") : @"(symbol not found)", forRole ? @"present" : @"not found");
    });
}

static void Z2O_SwitcherOrientation(id self, SEL _cmd, long long *outOri, id __autoreleasing *outMap, id request, id prev, id state) {
    Z2O_LogRotationMachinery();
    if (!BP_OnName("or_traits") || !outOri || !outMap || !request || !state || !prev || !Z2O_FlowReady(self)) {     // nil arguments: the 16.0 body raises its NSAssert exactly like 16.2
        sSwOri(self, _cmd, outOri, outMap, request, prev, state);
        return;
    }
    long long src = Z2O_LL0(request, "source", "z2o swo");
    id label = Z2O_Obj0(request, "eventLabel", "z2o swo");
    BOOL isFollowup = [label isKindOfClass:[NSString class]] && [(NSString *)label containsString:@"FollowupRotation"];       // 16.2 containsString:, 16.0 isEqualToString:
    Class notesCls = NSClassFromString(@"SBSwitcherLayoutTransitionNotes");
    id notes = ((id (*)(id, SEL, id, id, id))objc_msgSend)([notesCls alloc], sel_registerName("initWithFromPreviousState:currentLayoutState:transitionRequest:"), prev, state, request);
    *outOri = 0;
    BOOL fromHomeToApp = Z2O_Bool0(notes, "fromHomeScreenToApp", "z2o swo");
    if (src != 14 && !fromHomeToApp && !Z2O_Bool0(notes, "changingApps", "z2o swo")) {
        if (Z2O_Bool0(self, "_isUnderUILock", "z2o swo")) { BPY_LOG(@"z2o: swo (%s) skipped: under UI lock, request %@", Z2O_Tag(self), label); return; }
        if (!Z2O_IvObj(self, "_traitsParticipant") && Z2O_LL0(state, "unlockedEnvironmentMode", "z2o swo") == 1) { BPY_LOG(@"z2o: swo (%s) skipped: no traits participant while locked, request %@", Z2O_Tag(self), label); return; }
    }
    Z2O_SetIvBool(self, "_evaluatingLayoutStateOrientation", YES);                  // 16.2 _noteLayoutStateEvaluationBegan
    if (!Z2O_IvObj(self, "_traitsParticipant")) ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("_setupSwitcherTraitsParticipantAndPolicySpecifiers"));
    id primaryElement = Z2O_Has(state, "elementWithRole:", "z2o swo") ? ((id (*)(id, SEL, long long))objc_msgSend)(state, sel_registerName("elementWithRole:"), 1) : nil;
    id primaryEntity = Z2O_Obj0(primaryElement, "workspaceEntity", "z2o swo");
    id sceneHandle = Z2O_Obj0(Z2O_Obj0(primaryEntity, "applicationSceneEntity", "z2o swo"), "sceneHandle", "z2o swo");
    id app = Z2O_Obj0(sceneHandle, "application", "z2o swo");
    BOOL phoneOnPad = Z2O_Bool0(app, "classicAppPhoneAppRunningOnPad", "z2o swo");
    BOOL inHome = Z2O_Bool0(notes, "inHomeScreen", "z2o swo");
    Z2O_SetIvBool(self, "_isPublishedOrientationLocked", fromHomeToApp);            // 16.2 +0x88
    Z2O_SetIvBool(self, "_canDetermineActiveOrientation", inHome ? Z2O_IvBool(self, "_canDetermineActiveOrientation") : YES);   // 16.2 +0x89: keeps the old value in the home screen (16.0: !inHomeScreen)
    Z2O_SetIvLL(self, "_panGestureRecognizerRequestedOrientation", 0);
    Z2O_SetIvBool(self, "_waitingFollowupTransition", NO);                          // the ivar does not exist in 16.2: never waiting
    BOOL chamois = Z2O_Bool0(self, "isChamoisWindowingUIEnabled", "z2o swo");
    Z2OPolicy pol = Z2O_Decide(notes, chamois, phoneOnPad, primaryEntity != nil);
    Z2O_SetReeval(self, pol.reeval);                                                // 16.2 strb w19, [self, #0x7a]
    id elements = Z2O_Obj0(state, "elements", "z2o swo");
    ((void (*)(id, SEL, id, BOOL))objc_msgSend)(self, sel_registerName("_createTraitsParticipantsForLayoutElementsIfNeeded:shouldPerformFirstResolution:"), elements, NO);
    BPY_LOG(@"z2o: swo (%s) request '%@' src %lld followup %d chamois %d phoneOnPad %d: own policy %lld non primary %lld primary %lld reevaluate %d", Z2O_Tag(self), label, src, (int)isFollowup, (int)chamois, (int)phoneOnPad, pol.own, pol.nonPrimary, pol.primary, (int)pol.reeval);
    Z2O_SetIvObj(self, "_arbiterActuationContext", nil);
    ((void (*)(id, SEL, long long, long long, long long))objc_msgSend)(self, sel_registerName("_updateParticipantsAndPoliciesWithSwitcherPolicy:nonPrimaryOverlayPolicy:primaryOverlayPolicy:"), pol.own, pol.nonPrimary, pol.primary);

    id actuation = Z2O_IvObj(self, "_arbiterActuationContext");
    id appContext = Z2O_Obj0(request, "applicationContext", "z2o swo");
    id switcherParticipant = Z2O_IvObj(self, "_traitsParticipant");
    if (!(src == 14 && !isFollowup) && actuation) {
        BOOL accountForSceneState = phoneOnPad ? NO : !chamois;                      // 16.2 0x1c7600e74 .. 0x1c7600f2c (16.0: !phoneOnPad)
        ((void (*)(id, SEL, id, id, BOOL))objc_msgSend)(self, sel_registerName("_updateAppTransitionContext:withOrientationActuationContext:accountForSceneState:"), appContext, actuation, accountForSceneState);
    } else if (phoneOnPad) {                                                         // 16.2 0x1c7600e84: only while not live resizing and with a scene on the primary delegate
        if (!Z2O_Bool0(appContext, "isInLiveResize", "z2o swo") && Z2O_Obj0(Z2O_IvObj(self, "_primaryElementTraitsParticipantDelegate"), "scene", "z2o swo")) {
            long long cur = Z2O_LL0(self, "interfaceOrientation", "z2o swo"), to = Z2O_LL0(switcherParticipant, "currentOrientation", "z2o swo");
            if (cur != to) {
                id settings = ((id (*)(id, SEL, long long, long long))objc_msgSend)((id)NSClassFromString(@"SBAnimationUtilities"), sel_registerName("animationSettingsForRotationFromInterfaceOrientation:toInterfaceOrientation:"), cur, to);
                if (Z2O_Has(appContext, "setAnimationSettings:", "z2o swo")) ((void (*)(id, SEL, id))objc_msgSend)(appContext, sel_registerName("setAnimationSettings:"), settings);
            }
        }
    }
    long long container = Z2O_LL0(switcherParticipant, "currentOrientation", "z2o swo");
    container = Z2O_GuardExternal(self, container, request);
    *outOri = container;
    id map = Z2O_Obj1(self, "_currentElementsOrientationsForLayoutState:", state, "z2o swo");   // = 16.2 _orientationsForLayoutStateElements:withAssociatedParticipants: (same map, same assertion)
    *outMap = map;
    Z2O_SetIvBool(self, "_evaluatingLayoutStateOrientation", NO);                   // 16.2 _noteLayoutStateEvaluationEnded...
    BPY_LOG(@"z2o: swo (%s) -> container orientation %lld, element orientations %@", Z2O_Tag(self), container, map);
}

// ------------------------------------------------------------------------------------------------ 2. -layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext: (16.2 0x1c76042cc)
static IMP sDidBegin;
static void Z2O_TransitionDidBegin(id self, SEL _cmd, id coordinator, id context) {
    if (!BP_OnName("or_traits") || !Z2O_Iv(self, "_canDetermineActiveOrientation") || !Z2O_Iv(self, "_publisherTraitsParticipant") ||
        ![self respondsToSelector:sel_registerName("_enqueueOrientationTransitionWithActuationContext:suggestedAnimator:completionTask:validator:label:")]) {
        if (sDidBegin) ((void (*)(id, SEL, id, id))sDidBegin)(self, _cmd, coordinator, context);
        return;
    }
    if (Z2O_GetReeval(self)) {
        __weak id weakSelf = self;
        BOOL (^validator)(id) = ^BOOL(id request) { id me = weakSelf; if (!me) return NO; BOOL f = Z2O_GetReeval(me); Z2O_SetReeval(me, NO); return f; };   // 16.2 0x1c7604400
        BPY_LOG(@"z2o: transitionDidBegin (%s): re-evaluation pending, enqueue FollowupRotation", Z2O_Tag(self));
        ((void (*)(id, SEL, id, id, id, id, id))objc_msgSend)(self, sel_registerName("_enqueueOrientationTransitionWithActuationContext:suggestedAnimator:completionTask:validator:label:"), nil, nil, nil, validator, @"FollowupRotation");
    }
    id toState = Z2O_Obj0(context, "toLayoutState", "z2o didBegin");
    Z2O_SetIvBool(self, "_canDetermineActiveOrientation", Z2O_LL0(toState, "unlockedEnvironmentMode", "z2o didBegin") != 1);
    id pub = Z2O_IvObj(self, "_publisherTraitsParticipant");
    if (Z2O_Has(pub, "setNeedsUpdatePreferencesWithReason:", "z2o didBegin")) ((void (*)(id, SEL, id))objc_msgSend)(pub, sel_registerName("setNeedsUpdatePreferencesWithReason:"), @"Layout state change did begin");
}

// ------------------------------------------------------------------------------------------------ 3. -_enqueueOrientationTransition...label: unique request label (16.2 0x1c7602254..0x1c7602288)
static void Z2O_Enqueue(id self, SEL _cmd, id ctx, id animator, id completion, id validator, id label) {
    if (BP_OnName("or_label") && label) {
        long n = sEnqCounter++;                                                      // 16.2: a global counter, read, incremented
        id nl = [NSString stringWithFormat:@"%@-%ld", label, n];
        BPY_LOG(@"z2o: enqueue orientation transition '%@'", nl);
        label = nl;
    }
    ((void (*)(id, SEL, id, id, id, id, id))sEnqueue)(self, _cmd, ctx, animator, completion, validator, label);
}

// ------------------------------------------------------------------------------------------------ 4. -actuateOrientationForTraitsDelegate:withContext:reasons: (16.2 0x1c7601958, new)
static void Z2O_Actuate(id self, SEL _cmd, id delegate, id ctx, long long reasons) {
    id overlay = Z2O_Obj1(self, "_liveOverlayForTraitsDelegate:", delegate, "z2o actuate");
    id animator = Z2O_Obj0(overlay, "prepareOverlayForContentRotation", "z2o actuate");
    SEL u = sel_registerName("updateOrientationForTraitsDelegate:withUpdateReasons:suggestedAnimator:actuationContext:");
    if (![self respondsToSelector:u]) { Z2O_NoteMissing(self, u, "actuateOrientationForTraitsDelegate"); return; }
    ((void (*)(id, SEL, id, long long, id, id))objc_msgSend)(self, u, delegate, reasons, animator, ctx);
}

// ------------------------------------------------------------------------------------------------ 5. -[SBTraitsExternalDisplayPipelineManager inputs]
static id Z2O_ExtInputs(id self, SEL _cmd) {
    id cached = Z2O_IvObj(self, "_inputs");
    if (!BP_OnName("or_extinputs")) return sInputs ? ((id (*)(id, SEL))sInputs)(self, _cmd) : nil;
    id scene = Z2O_Obj0(Z2O_Obj0(self, "sceneDelegate", "z2o inputs"), "windowScene", "z2o inputs");
    if (!scene) return sInputs ? ((id (*)(id, SEL))sInputs)(self, _cmd) : cached;       // no scene yet: the 16.0 body (it reads nil -> orientation 0, like 16.2)
    long long sceneOri = 0, real = Z2O_RealOrientation(scene, &sceneOri);
    long long cachedOri = cached ? Z2O_LL0(Z2O_Obj0(cached, "deviceOrientationInputs", "z2o inputs"), "currentDeviceOrientation", "z2o inputs") : -1;
    if (cached && cachedOri == real) {
        static __weak id sKeptScene; static long long sKeptOri = -2;
        if (sKeptScene != scene || sKeptOri != real) {                                  // one line per scene / orientation: the monitor's arbiter input is the question of the whole data path
            sKeptScene = scene; sKeptOri = real;
            BPY_LOG(@"z2o: external display arbiter input kept: device orientation %lld (scene orientation %lld, canvas shape %d)", real, sceneOri, Z2O_SceneShape(scene));
        }
        return cached;
    }
    Class idiomC = NSClassFromString(@"SBFTraitsArbitrationInterfaceIdiomInputs"), oriC = NSClassFromString(@"SBFTraitsArbitrationDeviceOrientationInputs"), inC = NSClassFromString(@"SBFTraitsArbitrationInputs");
    SEL si = sel_registerName("initWithIsPad:"), so = sel_registerName("initWithCurrentDeviceOrientation:nonFlatDeviceOrientation:"), sa = sel_registerName("initWithInterfaceIdiomInputs:deviceOrientationInputs:keyboardInputs:");
    if (!idiomC || !oriC || !inC || ![idiomC instancesRespondToSelector:si] || ![oriC instancesRespondToSelector:so] || ![inC instancesRespondToSelector:sa]) {
        BP_Log(@"z2o: GUARD(or_extinputs) arbiter input classes / init selectors missing, the 16.0 cached input is used");
        return sInputs ? ((id (*)(id, SEL))sInputs)(self, _cmd) : cached;
    }
    BOOL isPad = Z2O_LL0((id)[UIDevice currentDevice], "userInterfaceIdiom", "z2o inputs") == 1;
    id idiom = ((id (*)(id, SEL, BOOL))objc_msgSend)([idiomC alloc], si, isPad);
    id ori = ((id (*)(id, SEL, long long, long long))objc_msgSend)([oriC alloc], so, real, real);
    id fresh = ((id (*)(id, SEL, id, id, id))objc_msgSend)([inC alloc], sa, idiom, ori, nil);
    Z2O_SetIvObj(self, "_inputs", fresh);
    BP_Log(@"z2o: external display arbiter input: device orientation %lld -> %lld (scene orientation %lld, canvas shape %d)%@", cachedOri, real, sceneOri, Z2O_SceneShape(scene), cached ? @" REFRESHED" : @"");
    return fresh;
}

// ------------------------------------------------------------------------------------------------ setup
static IMP Z2O_Replace(const char *cls, const char *sel, IMP imp) {
    Class c = NSClassFromString([NSString stringWithUTF8String:cls]);
    SEL s = sel_registerName(sel);
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    if (!m) { BP_Log(@"z2o: GUARD -[%s %s] not found, not replaced", cls, sel); return NULL; }
    IMP prev = method_getImplementation(m);
    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));
    return prev;
}

__attribute__((constructor)) static void Z2O_TraitsSetup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        sSwOri = (Z2OSwOriFn)Z2O_Replace("SBSwitcherController", "switcherOrientation:elementsOrientations:forTransitionRequest:previousLayoutState:layoutState:", (IMP)Z2O_SwitcherOrientation);
        sDidBegin = Z2O_Replace("SBSwitcherController", "layoutStateTransitionCoordinator:transitionDidBeginWithTransitionContext:", (IMP)Z2O_TransitionDidBegin);
        sEnqueue = Z2O_Replace("SBSwitcherController", "_enqueueOrientationTransitionWithActuationContext:suggestedAnimator:completionTask:validator:label:", (IMP)Z2O_Enqueue);
        sInputs = Z2O_Replace("SBTraitsExternalDisplayPipelineManager", "inputs", (IMP)Z2O_ExtInputs);
        Class sc = NSClassFromString(@"SBSwitcherController");
        BOOL added = NO;
        if (sc && !class_getInstanceMethod(sc, sel_registerName("actuateOrientationForTraitsDelegate:withContext:reasons:")))
            added = class_addMethod(sc, sel_registerName("actuateOrientationForTraitsDelegate:withContext:reasons:"), (IMP)Z2O_Actuate, "v32@0:8@16@24q32");
        BP_Log(@"z2o: traits installed swo=%d didbegin=%d enqueue=%d extinputs=%d actuate=%d (switches or_traits, or_label, or_extinputs, or_extreal)", sSwOri != NULL, sDidBegin != NULL, sEnqueue != NULL, sInputs != NULL, (int)added);
    }
}

#pragma clang diagnostic pop
