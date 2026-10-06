// SwitcherDismissFix
//
// iPadOS 16.0 (build 20A8372), app switcher: leaving the switcher for the Home Screen (tap on empty space, or the
// automatic dismissal of an empty switcher) is a one-frame cut. SwitcherTrace showed why: for every switcher -> home
// transition SpringBoard creates no transition modifier, and the transition modifier is what animates.
//
//   -[SBMainSwitcherRootSwitcherModifier transitionModifierForMainTransitionEvent:] (also reached through
//   SBContinuousExposeRootSwitcherModifier, which defers to it) and the FullScreenFluid variant build the modifier
//   from the event's environment modes (1 = home, 2 = app switcher, 3 = app). For switcher -> home they return nil
//   unless a peek is valid (SBHomeToGridSwitcherModifier) or the style is the iPhone deck (SBHomeToDeckSwitcherModifier).
//   Both of those are built as  initWithTransitionID:direction:0 multitaskingModifier:...  (direction 0 = toward home,
//   1 = toward the switcher).
//
// 16.2 fixes the Stage Manager case with a new class, SBContinuousExposeToHomeSwitcherModifier, which wraps
//   SBHomeToGridSwitcherModifier initWithTransitionID:direction:0 multitaskingModifier:[[root multitaskingModifier] copy]
// (plus anchor-point / perspective / shadow adjustments). This tweak builds that inner modifier directly: when the
// original returns nil for an animated, non-gesture 2 -> 1 transition, it returns SBHomeToGridSwitcherModifier with
// direction 0. Everything else keeps whatever SpringBoard returned.
//
// 0.1.0 passed direction 1 (the wrong way round; windows flew off to the right). 0.2.0 uses 0.
//
// 0.3.0 (this branch) also ports the 16.2 wrapper class itself. SBContinuousExposeToHomeSwitcherModifier does not exist in
// 16.0, so it is created at run time (SDFContinuousExposeToHomeSwitcherModifier, a subclass of
// SBTransitionSwitcherModifier) with exactly the 16.2 behaviour, decoded from the 16.2 binary:
//   ivars: _direction (long long), the Stage Manager modifier (kept as an associated object)
//   init:  super initWithTransitionID:; store both; add child
//          SBHomeToGridSwitcherModifier initWithTransitionID:direction:(direction != 0) multitaskingModifier:[ce copy]
//   _isEffectivelyHome = (isPreparingLayout && direction == 1) || (isUpdatingLayout && direction == 0)
//   when effectively home:  anchorPointForIndex: -> (0.5, 0.5);  shouldUseAnchorPointToPinLayoutRolesToSpace: -> YES;
//     perspectiveAngleForAppLayout: -> 0;  adjustedSpaceAccessoryViewFrame:forAppLayout: -> the frame unchanged;
//     adjustedSpaceAccessoryViewAnchorPoint:forAppLayout: -> (0.5, 0.5);  otherwise [super ...]
//   headerStyleForIndex:, shadowStyleForLayoutRole:inAppLayout:, homeScreenBackdropBlurType: answered by the Stage
//     Manager modifier, temporarily attached via performTransactionWithTemporaryChildModifier:usingBlock:
// If any piece cannot be resolved the tweak falls back to the 0.2.0 behaviour (plain SBHomeToGridSwitcherModifier).
//
// Files (resolved under the jailbreak root with libroot):
//   <jbroot>/tmp/SwitcherDismissFix.off    kill switch: create it and the tweak returns the original result (checked
//                                          at most once a second)
//   <jbroot>/tmp/SwitcherDismissFix.plain  create it to use the 0.2.0 behaviour (no ported wrapper), for comparison
//   <jbroot>/tmp/SwitcherDismissFix.debug  create it to log each time the fix is applied
//   <jbroot>/tmp/SwitcherDismissFix.log    that log (rotated at 256 KiB)

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>
#import <rootless.h>

static char gOffPath[1024], gPlainPath[1024], gDebugPath[1024], gLogPath[1024], gLogOldPath[1030];
static pthread_mutex_t gMu = PTHREAD_MUTEX_INITIALIZER;

static void SDF_InitPaths(void) {
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    const char *t = tmp.fileSystemRepresentation;
    snprintf(gOffPath, sizeof gOffPath, "%s/SwitcherDismissFix.off", t);
    snprintf(gPlainPath, sizeof gPlainPath, "%s/SwitcherDismissFix.plain", t);
    snprintf(gDebugPath, sizeof gDebugPath, "%s/SwitcherDismissFix.debug", t);
    snprintf(gLogPath, sizeof gLogPath, "%s/SwitcherDismissFix.log", t);
    snprintf(gLogOldPath, sizeof gLogOldPath, "%s.1", gLogPath);
}

// A file test, cached for one second.
static BOOL SDF_FileFlag(const char *path, uint64_t *next, BOOL *last) {
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < *next) return *last;
    *next = t + 1000000000ull;
    *last = path[0] && access(path, F_OK) == 0;
    return *last;
}
static BOOL SDF_Killed(void)  { static uint64_t n; static BOOL l; return SDF_FileFlag(gOffPath, &n, &l); }
static BOOL SDF_Plain(void)   { static uint64_t n; static BOOL l; return SDF_FileFlag(gPlainPath, &n, &l); }
static BOOL SDF_Logging(void) { static uint64_t n; static BOOL l; return SDF_FileFlag(gDebugPath, &n, &l); }

static void SDF_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void SDF_Log(NSString *fmt, ...) {
    if (!SDF_Logging()) return;
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmv;
    localtime_r(&ts.tv_sec, &tmv);
    NSString *line = [NSString stringWithFormat:@"%02d:%02d:%02d.%03ld %@\n", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, ts.tv_nsec / 1000000, msg];
    pthread_mutex_lock(&gMu);
    struct stat st;
    if (stat(gLogPath, &st) == 0 && st.st_size > 256 * 1024) rename(gLogPath, gLogOldPath);
    int fd = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        const char *u = line.UTF8String;
        (void)!write(fd, u, strlen(u));
        close(fd);
    }
    pthread_mutex_unlock(&gMu);
}

// ---------------------------------------------------------------- the missing case

@interface SBTransitionSwitcherModifierEvent : NSObject
- (long long)fromEnvironmentMode;
- (long long)toEnvironmentMode;
- (BOOL)isAnimated;
- (BOOL)isGestureInitiated;
- (id)transitionID;
@end

@interface SBHomeToSwitcherSwitcherModifier : NSObject
- (id)initWithTransitionID:(id)transitionID direction:(long long)direction multitaskingModifier:(id)multitaskingModifier;
@end

@interface SBFluidSwitcherRootSwitcherModifier : NSObject
- (id)multitaskingModifier;
- (id)_newMultitaskingModifier;
@end
@interface SBFullScreenFluidSwitcherRootSwitcherModifier : SBFluidSwitcherRootSwitcherModifier
@end
@interface SBMainSwitcherRootSwitcherModifier : SBFluidSwitcherRootSwitcherModifier
@end


// ---------------------------------------------------------------- the ported 16.2 wrapper class

@interface SBChainableModifier : NSObject
- (void)addChildModifier:(id)modifier;
- (void)performTransactionWithTemporaryChildModifier:(id)modifier usingBlock:(void (^)(void))block;
@end

static Class gWrapperClass;             // SDFContinuousExposeToHomeSwitcherModifier, NULL if it could not be built
static Class gWrapperSuper;             // SBTransitionSwitcherModifier
static ptrdiff_t gDirectionOffset;
static const char kCEKey = 0;           // associated-object key for the Stage Manager modifier

static long long W_Direction(id self_) { return *(long long *)((uint8_t *)(__bridge void *)self_ + gDirectionOffset); }

static BOOL W_BoolQuery(id self_, SEL sel) { return ((BOOL (*)(id, SEL))objc_msgSend)(self_, sel); }

// (_isEffectivelyHome of the 16.2 class)
static BOOL W_IsHome(id self_) {
    long long d = W_Direction(self_);
    BOOL preparing = W_BoolQuery(self_, @selector(isPreparingLayout));
    BOOL updating = W_BoolQuery(self_, @selector(isUpdatingLayout));
    return (preparing && d == 1) || (updating && d == 0);
}

static struct objc_super W_Super(id self_) {
    struct objc_super sup;
    sup.receiver = self_;
    sup.super_class = gWrapperSuper;
    return sup;
}

static id W_Init(id self_, SEL _cmd, id transitionID, long long direction, id ceModifier) {
    if (!ceModifier) return nil;
    struct objc_super sup = W_Super(self_);
    id me = ((id (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, @selector(initWithTransitionID:), transitionID);
    if (!me) return nil;
    *(long long *)((uint8_t *)(__bridge void *)me + gDirectionOffset) = direction;
    objc_setAssociatedObject(me, &kCEKey, ceModifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class gridCls = NSClassFromString(@"SBHomeToGridSwitcherModifier");
    SEL initSel = @selector(initWithTransitionID:direction:multitaskingModifier:);
    if (!gridCls || ![gridCls instancesRespondToSelector:initSel]) return nil;
    id copyOfCE = [ceModifier copy];
    id child = ((id (*)(id, SEL, id, long long, id))objc_msgSend)([gridCls alloc], initSel, transitionID, direction != 0, copyOfCE);
    if (!child) return nil;
    [(SBChainableModifier *)me addChildModifier:child];
    return me;
}

static CGPoint W_AnchorPointForIndex(id self_, SEL _cmd, unsigned long long index) {
    if (W_IsHome(self_)) return CGPointMake(0.5, 0.5);
    struct objc_super sup = W_Super(self_);
    return ((CGPoint (*)(struct objc_super *, SEL, unsigned long long))objc_msgSendSuper)(&sup, _cmd, index);
}

static BOOL W_ShouldUseAnchorPoint(id self_, SEL _cmd, long long space) {
    if (W_IsHome(self_)) return YES;
    struct objc_super sup = W_Super(self_);
    return ((BOOL (*)(struct objc_super *, SEL, long long))objc_msgSendSuper)(&sup, _cmd, space);
}

static double W_PerspectiveAngle(id self_, SEL _cmd, id appLayout) {
    if (W_IsHome(self_)) return 0.0;
    struct objc_super sup = W_Super(self_);
    return ((double (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, appLayout);
}

static CGRect W_AdjustedAccessoryFrame(id self_, SEL _cmd, CGRect frame, id appLayout) {
    if (W_IsHome(self_)) return frame;
    struct objc_super sup = W_Super(self_);
    return ((CGRect (*)(struct objc_super *, SEL, CGRect, id))objc_msgSendSuper)(&sup, _cmd, frame, appLayout);
}

static CGPoint W_AdjustedAccessoryAnchor(id self_, SEL _cmd, CGPoint point, id appLayout) {
    if (W_IsHome(self_)) return CGPointMake(0.5, 0.5);
    struct objc_super sup = W_Super(self_);
    return ((CGPoint (*)(struct objc_super *, SEL, CGPoint, id))objc_msgSendSuper)(&sup, _cmd, point, appLayout);
}

// The three queries answered by the Stage Manager modifier while it is temporarily attached to this one.
static long long W_AskCE(id self_, void (^ask)(id ce, long long *result)) {
    id ce = objc_getAssociatedObject(self_, &kCEKey);
    __block long long result = 0;
    if (!ce) return 0;
    [(SBChainableModifier *)self_ performTransactionWithTemporaryChildModifier:ce usingBlock:^{ ask(ce, &result); }];
    return result;
}

static long long W_HeaderStyle(id self_, SEL _cmd, unsigned long long index) {
    return W_AskCE(self_, ^(id ce, long long *r) { *r = ((long long (*)(id, SEL, unsigned long long))objc_msgSend)(ce, _cmd, index); });
}

static long long W_ShadowStyle(id self_, SEL _cmd, long long role, id appLayout) {
    return W_AskCE(self_, ^(id ce, long long *r) { *r = ((long long (*)(id, SEL, long long, id))objc_msgSend)(ce, _cmd, role, appLayout); });
}

static long long W_BackdropBlurType(id self_, SEL _cmd) {
    return W_AskCE(self_, ^(id ce, long long *r) { *r = ((long long (*)(id, SEL))objc_msgSend)(ce, _cmd); });
}

typedef struct { const char *selName; IMP imp; const char *fallbackTypes; } WrapperMethod;

// Builds the class once. Returns NULL (and logs why) if anything it relies on is not there.
static Class SDF_WrapperClass(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            Class super_ = NSClassFromString(@"SBTransitionSwitcherModifier");
            Class donor = NSClassFromString(@"SBDefaultImplementationsSwitcherModifier");
            if (!super_ || !donor) { SDF_Log(@"wrapper: SBTransitionSwitcherModifier or the defaults class is missing"); return; }
            (void)[super_ class];       // make sure +initialize (which sets up the query machinery) has run
            (void)[donor class];
            if (![super_ instancesRespondToSelector:@selector(isPreparingLayout)] || ![super_ instancesRespondToSelector:@selector(isUpdatingLayout)] ||
                ![super_ instancesRespondToSelector:@selector(initWithTransitionID:)] ||
                ![super_ instancesRespondToSelector:@selector(performTransactionWithTemporaryChildModifier:usingBlock:)] ||
                ![super_ instancesRespondToSelector:@selector(addChildModifier:)]) { SDF_Log(@"wrapper: base class lacks a required method"); return; }

            const WrapperMethod methods[] = {
                { "anchorPointForIndex:",                              (IMP)W_AnchorPointForIndex,       "{CGPoint=dd}24@0:8Q16" },
                { "shouldUseAnchorPointToPinLayoutRolesToSpace:",      (IMP)W_ShouldUseAnchorPoint,      "B24@0:8q16" },
                { "perspectiveAngleForAppLayout:",                     (IMP)W_PerspectiveAngle,          "d24@0:8@16" },
                { "adjustedSpaceAccessoryViewFrame:forAppLayout:",     (IMP)W_AdjustedAccessoryFrame,    "{CGRect={CGPoint=dd}{CGSize=dd}}56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48" },
                { "adjustedSpaceAccessoryViewAnchorPoint:forAppLayout:", (IMP)W_AdjustedAccessoryAnchor, "{CGPoint=dd}40@0:8{CGPoint=dd}16@32" },
                { "headerStyleForIndex:",                              (IMP)W_HeaderStyle,               "q24@0:8Q16" },
                { "shadowStyleForLayoutRole:inAppLayout:",             (IMP)W_ShadowStyle,               "q32@0:8q16@24" },
                { "homeScreenBackdropBlurType",                        (IMP)W_BackdropBlurType,          "q16@0:8" },
            };
            // Every method we override must already be answerable by the base class: the super calls (and, for the
            // three queries, the Stage Manager modifier we ask) depend on it.
            for (size_t i = 0; i < sizeof methods / sizeof methods[0]; i++) {
                SEL sel = sel_registerName(methods[i].selName);
                if (![super_ instancesRespondToSelector:sel]) { SDF_Log(@"wrapper: base class does not respond to %s", methods[i].selName); return; }
            }

            Class cls = objc_allocateClassPair(super_, "SDFContinuousExposeToHomeSwitcherModifier", 0);
            if (!cls) { SDF_Log(@"wrapper: objc_allocateClassPair failed"); return; }
            class_addIvar(cls, "_sdfDirection", sizeof(long long), 3, @encode(long long));
            for (size_t i = 0; i < sizeof methods / sizeof methods[0]; i++) {
                SEL sel = sel_registerName(methods[i].selName);
                Method donorMethod = class_getInstanceMethod(donor, sel);
                const char *types = donorMethod ? method_getTypeEncoding(donorMethod) : methods[i].fallbackTypes;
                class_addMethod(cls, sel, methods[i].imp, types);
            }
            class_addMethod(cls, sel_registerName("initWithTransitionID:direction:continuousExposeModifier:"), (IMP)W_Init, "@40@0:8@16q24@32");
            objc_registerClassPair(cls);
            Ivar iv = class_getInstanceVariable(cls, "_sdfDirection");
            if (!iv) { SDF_Log(@"wrapper: ivar missing"); return; }
            gDirectionOffset = ivar_getOffset(iv);
            gWrapperSuper = super_;
            gWrapperClass = cls;
            SDF_Log(@"wrapper class SDFContinuousExposeToHomeSwitcherModifier registered (direction ivar at +%td)", gDirectionOffset);
        } @catch (NSException *ex) {
            SDF_Log(@"wrapper: exception while building the class: %@", ex);
        }
    });
    return gWrapperClass;
}

enum { kEnvHome = 1, kEnvSwitcher = 2 };
enum { kDirectionToHome = 0 };      // Apple builds every switcher -> home modifier with direction 0

// Returns the modifier to use when `original` is nil for a switcher -> home transition on the grid style, else nil.
static id SDF_SwitcherToHomeModifier(SBFluidSwitcherRootSwitcherModifier *root, id event) {
    if (SDF_Killed()) return nil;
    @try {
        SBTransitionSwitcherModifierEvent *e = event;
        if (![e respondsToSelector:@selector(fromEnvironmentMode)] || ![e respondsToSelector:@selector(toEnvironmentMode)] ||
            ![e respondsToSelector:@selector(isAnimated)] || ![e respondsToSelector:@selector(isGestureInitiated)] ||
            ![e respondsToSelector:@selector(transitionID)]) return nil;
        if (e.fromEnvironmentMode != kEnvSwitcher || e.toEnvironmentMode != kEnvHome) return nil;
        if (!e.isAnimated || e.isGestureInitiated) return nil;

        if (![root respondsToSelector:@selector(_newMultitaskingModifier)]) return nil;

        Class cls = NSClassFromString(@"SBHomeToGridSwitcherModifier");
        SEL initSel = @selector(initWithTransitionID:direction:multitaskingModifier:);
        if (!cls || ![cls instancesRespondToSelector:initSel]) return nil;
        // Stage Manager root: 16.2 passes a copy of the root's multitasking modifier; other roots use the usual factory call.
        id multitasking = nil;
        Class ceRoot = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
        if (ceRoot && [root isKindOfClass:ceRoot] && [root respondsToSelector:@selector(multitaskingModifier)]) {
            multitasking = [[root multitaskingModifier] copy];
        } else {
            multitasking = [root _newMultitaskingModifier];
        }
        if (!multitasking) return nil;
        BOOL isCE = ceRoot && [root isKindOfClass:ceRoot];
        if (isCE && !SDF_Plain()) {
            Class wrapper = SDF_WrapperClass();
            SEL wInit = sel_registerName("initWithTransitionID:direction:continuousExposeModifier:");
            if (wrapper && [wrapper instancesRespondToSelector:wInit]) {
                id w = ((id (*)(id, SEL, id, long long, id))objc_msgSend)([wrapper alloc], wInit, e.transitionID, (long long)kDirectionToHome, multitasking);
                if (w) {
                    SDF_Log(@"added ported SBContinuousExposeToHome wrapper %@ (direction %d) for transition %@ (root %@)", NSStringFromClass([w class]), (int)kDirectionToHome, e.transitionID, NSStringFromClass([root class]));
                    return w;
                }
                SDF_Log(@"wrapper init returned nil; falling back to the plain modifier");
            }
        }
        SBHomeToSwitcherSwitcherModifier *m = [cls alloc];
        id result = [m initWithTransitionID:e.transitionID direction:kDirectionToHome multitaskingModifier:multitasking];
        SDF_Log(@"added switcher->home modifier %@ (direction %d, multitasking %@) for transition %@ (root %@)", NSStringFromClass([result class]), (int)kDirectionToHome, NSStringFromClass([multitasking class]), e.transitionID, NSStringFromClass([root class]));
        return result;
    } @catch (NSException *ex) {
        SDF_Log(@"exception: %@", ex);
        return nil;
    }
}

%hook SBFullScreenFluidSwitcherRootSwitcherModifier
- (id)transitionModifierForMainTransitionEvent:(id)event {
    id original = %orig;
    if (original) return original;
    id added = SDF_SwitcherToHomeModifier(self, event);
    return added ?: original;
}
%end

%hook SBMainSwitcherRootSwitcherModifier
- (id)transitionModifierForMainTransitionEvent:(id)event {
    id original = %orig;
    if (original) return original;
    id added = SDF_SwitcherToHomeModifier(self, event);
    return added ?: original;
}
%end

%ctor {
    @autoreleasepool {
        SDF_InitPaths();
        %init;
    }
}
