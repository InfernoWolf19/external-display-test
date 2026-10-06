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
// Files (resolved under the jailbreak root with libroot):
//   <jbroot>/tmp/SwitcherDismissFix.off    kill switch: create it and the tweak returns the original result (checked
//                                          at most once a second)
//   <jbroot>/tmp/SwitcherDismissFix.debug  create it to log each time the fix is applied
//   <jbroot>/tmp/SwitcherDismissFix.log    that log (rotated at 256 KiB)

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>
#import <rootless.h>

static char gOffPath[1024], gDebugPath[1024], gLogPath[1024], gLogOldPath[1030];
static pthread_mutex_t gMu = PTHREAD_MUTEX_INITIALIZER;

static void SDF_InitPaths(void) {
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    const char *t = tmp.fileSystemRepresentation;
    snprintf(gOffPath, sizeof gOffPath, "%s/SwitcherDismissFix.off", t);
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
