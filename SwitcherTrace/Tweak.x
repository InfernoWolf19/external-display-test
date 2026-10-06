// SwitcherTrace
//
// Diagnostic only. iPadOS 16.0 (build 20A8372): leaving the app switcher (swipe up and hold with nothing running,
// or tapping empty space) cuts to the Home Screen in a single frame instead of animating. Every hook below observes
// and then calls the original unchanged; nothing about the switcher's behaviour is altered.
//
// What it records (SpringBoard, only while the debug file exists):
//   * transition events reaching the switcher's root modifier: id, phase, animated, from/to environment mode, and the
//     class of the response that came back;
//   * gesture events, once per phase change;
//   * tap on empty space (_handleDismissTapGesture:, handleTapOutsideToDismissEvent:) and its response;
//   * the transition request the view controller is told to perform (source, animationDisabled, animation settings);
//   * which animation controller the coordinator returns for a request;
//   * animated flags on dismiss / performTransition calls;
//   * the empty-switcher timer (handleTimerEvent: on the home-gesture-to-switcher modifier) and the configured
//     emptySwitcherDismissDelay.
//
// Files (resolved under the jailbreak root with libroot, like the other tweaks here):
//   <jbroot>/tmp/SwitcherTrace.debug   create it to switch tracing on, delete it to switch it off
//   <jbroot>/tmp/SwitcherTrace.log     the trace (rotated at 256 KiB, one .1 backup)
//
// Cost while the debug file does not exist: one access() per second at most, from whichever hook fires.

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <time.h>
#import <unistd.h>
#import <rootless.h>

// ---------------------------------------------------------------- paths and logging

static char gDebugPath[1024], gLogPath[1024], gLogOldPath[1030];
static pthread_mutex_t gMu = PTHREAD_MUTEX_INITIALIZER;
static const off_t kMaxLog = 256 * 1024;

static void ST_InitPaths(void) {
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    snprintf(gDebugPath, sizeof gDebugPath, "%s/SwitcherTrace.debug", tmp.fileSystemRepresentation);
    snprintf(gLogPath, sizeof gLogPath, "%s/SwitcherTrace.log", tmp.fileSystemRepresentation);
    snprintf(gLogOldPath, sizeof gLogOldPath, "%s.1", gLogPath);
}

static BOOL ST_On(void) {
    static uint64_t next;
    static BOOL last;
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < next) return last;
    next = t + 1000000000ull;
    last = gDebugPath[0] && access(gDebugPath, F_OK) == 0;
    return last;
}

static void ST_LogRaw(const char *line) {
    pthread_mutex_lock(&gMu);
    struct stat st;
    if (stat(gLogPath, &st) == 0 && st.st_size > kMaxLog) rename(gLogPath, gLogOldPath);
    int fd = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        (void)!write(fd, line, strlen(line));
        close(fd);
    }
    pthread_mutex_unlock(&gMu);
}

static void ST_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ST_Log(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmv;
    localtime_r(&ts.tv_sec, &tmv);
    char head[48];
    snprintf(head, sizeof head, "%02d:%02d:%02d.%03ld ", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, ts.tv_nsec / 1000000);
    NSString *line = [NSString stringWithFormat:@"%s%@\n", head, msg];
    ST_LogRaw(line.UTF8String);
}

// ---------------------------------------------------------------- safe accessors

static id ST_Obj(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o || ![o respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(o, s);
}
static long long ST_Int(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o || ![o respondsToSelector:s]) return -999;
    return ((long long (*)(id, SEL))objc_msgSend)(o, s);
}
// BOOL-returning accessors leave the upper bits of x0 undefined, so they need their own cast.
static int ST_Bool(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    if (!o || ![o respondsToSelector:s]) return -1;
    return ((BOOL (*)(id, SEL))objc_msgSend)(o, s) ? 1 : 0;
}
static NSString *ST_Cls(id o) { return o ? NSStringFromClass([o class]) : @"nil"; }
static NSString *ST_Desc(id o) {
    if (!o) return @"nil";
    NSString *d = [o description] ?: @"?";
    d = [d stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return d.length > 360 ? [[d substringToIndex:360] stringByAppendingString:@"..."] : d;
}

// Describe a response: its class, and for a perform-transition response the request it carries.
static NSString *ST_Response(id r) {
    if (!r) return @"nil";
    id req = ST_Obj(r, "transitionRequest");
    if (!req) return ST_Cls(r);
    return [NSString stringWithFormat:@"%@{request source=%lld animationDisabled=%lld settings=%@ gestureInitiated=%d | %@}",
            ST_Cls(r), ST_Int(req, "source"), ST_Int(req, "animationDisabled"), ST_Cls(ST_Obj(req, "animationSettings")),
            ST_Bool(r, "isGestureInitiated"), ST_Desc(req)];
}

static NSString *ST_Event(id e) {
    return [NSString stringWithFormat:@"%@ id=%@ phase=%lld animated=%d gestureInitiated=%d from=%lld to=%lld type=%lld",
            ST_Cls(e), ST_Desc(ST_Obj(e, "transitionID")), ST_Int(e, "phase"), ST_Bool(e, "isAnimated"),
            ST_Bool(e, "isGestureInitiated"), ST_Int(e, "fromEnvironmentMode"), ST_Int(e, "toEnvironmentMode"), ST_Int(e, "type")];
}

// ---------------------------------------------------------------- hooks

@interface SBFluidSwitcherRootSwitcherModifier : NSObject
@end
@interface SBGridSwitcherModifier : NSObject
@end
@interface SBHomeGestureToSwitcherSwitcherModifier : NSObject
@end
@interface SBFluidSwitcherViewController : NSObject
@end
@interface SBMainSwitcherControllerCoordinator : NSObject
@end
@interface SBSwitcherController : NSObject
@end
@interface SBFluidSwitcherAnimationSettings : NSObject
@end

%hook SBFluidSwitcherRootSwitcherModifier
- (id)handleTransitionEvent:(id)event {
    BOOL on = ST_On();
    if (on) ST_Log(@"root.handleTransitionEvent > %@", ST_Event(event));
    id r = %orig;
    if (on) ST_Log(@"root.handleTransitionEvent < %@", ST_Response(r));
    return r;
}
- (id)handleGestureEvent:(id)event {
    id r = %orig;
    if (ST_On()) {
        static long long lastPhase = -1, lastType = -1;
        long long ph = ST_Int(event, "phase"), ty = ST_Int(event, "type");
        if (ph != lastPhase || ty != lastType) {
            lastPhase = ph; lastType = ty;
            ST_Log(@"root.handleGestureEvent %@ gestureID=%@ phase=%lld type=%lld -> %@", ST_Cls(event),
                   ST_Desc(ST_Obj(event, "gestureID")), ph, ty, ST_Response(r));
        }
    }
    return r;
}
%end

%hook SBGridSwitcherModifier
- (id)handleTapOutsideToDismissEvent:(id)event {
    id r = %orig;
    if (ST_On()) ST_Log(@"grid.handleTapOutsideToDismissEvent %@ -> %@", ST_Cls(event), ST_Response(r));
    return r;
}
%end

%hook SBHomeGestureToSwitcherSwitcherModifier
- (id)handleTimerEvent:(id)event {
    id r = %orig;
    if (ST_On()) ST_Log(@"homeGestureToSwitcher.handleTimerEvent %@ | %@ -> %@", ST_Cls(event), ST_Desc(event), ST_Response(r));
    return r;
}
%end

%hook SBFluidSwitcherViewController
- (void)_handleDismissTapGesture:(id)gesture {
    if (ST_On()) ST_Log(@"viewController._handleDismissTapGesture state=%lld", ST_Int(gesture, "state"));
    %orig;
}
- (void)_performModifierPerformTransitionResponse:(id)response {
    if (ST_On()) ST_Log(@"viewController._performModifierPerformTransitionResponse %@", ST_Response(response));
    %orig;
}
- (id)_transitionEventForTransitionWithContext:(id)context identifier:(id)identifier phase:(unsigned long long)phase animated:(BOOL)animated {
    id r = %orig;
    if (ST_On()) ST_Log(@"viewController._transitionEventForTransition id=%@ phase=%llu animated=%d -> %@", ST_Desc(identifier), phase, animated, ST_Event(r));
    return r;
}
- (double)_delayForTransitionWithContext:(id)context animated:(BOOL)animated {
    double d = %orig;
    if (ST_On()) ST_Log(@"viewController._delayForTransition animated=%d -> %.3f s", animated, d);
    return d;
}
%end

%hook SBMainSwitcherControllerCoordinator
- (id)animationControllerForTransitionRequest:(id)request ancillaryTransitionRequests:(id)requests {
    id r = %orig;
    if (ST_On()) ST_Log(@"coordinator.animationControllerForTransitionRequest source=%lld animationDisabled=%lld -> %@",
                        ST_Int(request, "source"), ST_Int(request, "animationDisabled"), ST_Cls(r));
    return r;
}
- (BOOL)dismissMainSwitcherNoninteractivelyAnimated:(BOOL)animated {
    if (ST_On()) ST_Log(@"coordinator.dismissMainSwitcherNoninteractively animated=%d", animated);
    return %orig;
}
- (BOOL)_dismissSwitcherNoninteractivelyToAppLayout:(id)layout dismissFloatingSwitcher:(BOOL)floating animated:(BOOL)animated {
    if (ST_On()) ST_Log(@"coordinator._dismissSwitcherNoninteractivelyToAppLayout layout=%@ animated=%d", ST_Cls(layout), animated);
    return %orig;
}
%end

%hook SBSwitcherController
- (void)performTransitionWithContext:(id)context animated:(BOOL)animated completion:(id)completion {
    if (ST_On()) ST_Log(@"switcherController.performTransition animated=%d context=%@", animated, ST_Desc(context));
    %orig;
}
%end

%hook SBFluidSwitcherAnimationSettings
- (double)emptySwitcherDismissDelay {
    double d = %orig;
    if (ST_On()) ST_Log(@"settings.emptySwitcherDismissDelay = %.3f s", d);
    return d;
}
%end

%ctor {
    @autoreleasepool {
        ST_InitPaths();
        %init;
    }
}
