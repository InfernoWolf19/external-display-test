// Backport162
//
// Brings iPadOS 16.2 (20C65) Stage Manager and external display behaviour to iPadOS 16.0 (20A8372) SpringBoard.
// The 16.2 behaviour is reimplemented here from a reading of the 16.2 binary; see specs/ and WORKLIST.md in this
// directory for what was compared and why. Every feature is independent and has its own off switch.
//
// Safety:
//   * Only active on build 20A8372; any other build leaves SpringBoard untouched.
//   * <jbroot>/tmp/Backport162.off            kill switch for everything (checked at most once a second)
//   * <jbroot>/tmp/Backport162.off.<feature>  switch off one feature (names below)
//   * <jbroot>/tmp/Backport162.debug          create it to log what the features do
//   * <jbroot>/tmp/Backport162.log            that log (rotated at 256 KiB)
//
// Features (group 4, external display):
//   scale     SBSystemShellExtendedDisplayControllerPolicy: the display size is the preferred mode's pixel size times
//             a logical scale. 16.2 clamps that scale, per axis, to the monitor's [minimumLogicalScale,
//             maximumLogicalScale] (and uses 1.0 for display type 2). 16.0 only clamped it in a path the size
//             calculation does not use.
//   autohost  SBSystemShellExternalDisplaySceneManager: 16.2 does not auto-host the keyboard arbiter scene on the
//             external display while +[UIKeyboard usesInputSystemUI] is NO.
//   blank     SBExternalDisplayCoverSheetController: while the iPad screen is off, 16.0 covers the external display
//             with a black window (the monitor stays on). 16.2 has no such window: it blanks the display through
//             BackBoard (BKSDisplayServicesSetDisplayBlanked, so the monitor can sleep) and adds a mouse-button-down
//             gesture, enabled only while the screen is off, that wakes the iPad (SBLockScreenManager
//             _wakeScreenForMouseButtonDown:). 16.0 registers that gesture with system-gesture type 0x42 (0x43 in 16.2).

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <pthread.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <time.h>
#import <unistd.h>
#import <rootless.h>

// ---------------------------------------------------------------- switches and logging

enum { F_SCALE, F_AUTOHOST, F_BLANK, F_COUNT };
static const char *const kFeatureNames[F_COUNT] = { "scale", "autohost", "blank" };

static char gOffPath[1024], gDebugPath[1024], gLogPath[1024], gLogOldPath[1030];
static char gFeatureOffPath[F_COUNT][1100];
static pthread_mutex_t gMu = PTHREAD_MUTEX_INITIALIZER;

static void BP_InitPaths(void) {
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    const char *t = tmp.fileSystemRepresentation;
    snprintf(gOffPath, sizeof gOffPath, "%s/Backport162.off", t);
    snprintf(gDebugPath, sizeof gDebugPath, "%s/Backport162.debug", t);
    snprintf(gLogPath, sizeof gLogPath, "%s/Backport162.log", t);
    snprintf(gLogOldPath, sizeof gLogOldPath, "%s.1", gLogPath);
    for (int i = 0; i < F_COUNT; i++) snprintf(gFeatureOffPath[i], sizeof gFeatureOffPath[i], "%s/Backport162.off.%s", t, kFeatureNames[i]);
}

// A file test, cached for one second.
static BOOL BP_FileFlag(const char *path, uint64_t *next, BOOL *last) {
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (t < *next) return *last;
    *next = t + 1000000000ull;
    *last = path[0] && access(path, F_OK) == 0;
    return *last;
}
static BOOL BP_Killed(void)  { static uint64_t n; static BOOL l; return BP_FileFlag(gOffPath, &n, &l); }
static BOOL BP_Logging(void) { static uint64_t n; static BOOL l; return BP_FileFlag(gDebugPath, &n, &l); }
static BOOL BP_FeatureOff(int f) {
    static uint64_t n[F_COUNT]; static BOOL l[F_COUNT];
    return BP_FileFlag(gFeatureOffPath[f], &n[f], &l[f]);
}
static BOOL BP_On(int f) { return !BP_Killed() && !BP_FeatureOff(f); }

static void BP_Log(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void BP_Log(NSString *fmt, ...) {
    if (!BP_Logging()) return;
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

static BOOL BP_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}

// ---------------------------------------------------------------- private interfaces

@interface CADisplayMode : NSObject
- (NSUInteger)width;
- (NSUInteger)height;
@end

@interface CADisplay : NSObject
- (double)minimumLogicalScale;
- (double)maximumLogicalScale;
- (long long)displayType;
@end

@interface SBSystemShellExtendedDisplayControllerPolicy : NSObject
- (id)_preferredModeForDisplayForTargetCADisplay:(id)display;
@end

@interface FBScene : NSObject
- (NSString *)identifier;
@end

// ---------------------------------------------------------------- feature: scale

static inline double BP_Clamp(double v, double lo, double hi) {
    double a = (v < lo) ? lo : v;     // max(lo, v)
    return (hi > a) ? a : hi;         // min(hi, a)   (the order 16.2 uses)
}

%hook SBSystemShellExtendedDisplayControllerPolicy

- (CGSize)_preferredSizeInPixelsForTargetCADisplay:(id)display {
    CGSize orig = %orig;
    if (!display || !BP_On(F_SCALE)) return orig;
    CADisplayMode *mode = [self _preferredModeForDisplayForTargetCADisplay:display];
    double W = (double)[mode width], H = (double)[mode height];
    if (!(W > 0) || !(H > 0)) return orig;
    CADisplay *d = (CADisplay *)display;
    CGSize out;
    if ([d displayType] == 2) {
        out = CGSizeMake(W, H);
    } else {
        double mn = [d minimumLogicalScale], mx = [d maximumLogicalScale];
        if (!(mx > 0) || mn > mx) return orig;
        double sx = BP_Clamp(orig.width / W, mn, mx), sy = BP_Clamp(orig.height / H, mn, mx);
        out = CGSizeMake(sx * W, sy * H);
    }
    if (fabs(out.width - orig.width) > 0.5 || fabs(out.height - orig.height) > 0.5)
        BP_Log(@"scale: pixel size %.0fx%.0f -> %.0fx%.0f (mode %.0fx%.0f)", orig.width, orig.height, out.width, out.height, W, H);
    return out;
}

%end

// ---------------------------------------------------------------- feature: autohost

static NSString *BP_KeyboardArbiterSceneIdentifier(void) {
    static NSString *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *p = dlsym(RTLD_DEFAULT, "_UIKeyboardArbiter_SceneIdentifier");
        if (p) s = *(__unsafe_unretained NSString **)p;
    });
    return s;
}

static BOOL BP_UsesInputSystemUI(void) {
    Class c = NSClassFromString(@"UIKeyboard");
    if (!c || ![c respondsToSelector:@selector(usesInputSystemUI)]) return YES;   // unknown: do not change behaviour
    return ((BOOL (*)(id, SEL))objc_msgSend)(c, @selector(usesInputSystemUI));
}

%hook SBSystemShellExternalDisplaySceneManager

- (BOOL)_shouldAutoHostScene:(FBScene *)scene {
    BOOL r = %orig;
    if (!r || !BP_On(F_AUTOHOST) || BP_UsesInputSystemUI()) return r;
    NSString *arbiter = BP_KeyboardArbiterSceneIdentifier();
    if (arbiter && [arbiter isEqualToString:scene.identifier]) {
        BP_Log(@"autohost: not hosting keyboard arbiter scene %@", scene.identifier);
        return NO;
    }
    return r;
}

%end


// ---------------------------------------------------------------- feature: blank

@interface SBFMouseButtonDownGestureRecognizer : NSObject
- (instancetype)initWithTarget:(id)target action:(SEL)action;
- (void)setEnabled:(BOOL)enabled;
@end

@interface SBDisplayConfigurationStub : NSObject
- (NSString *)hardwareIdentifier;
@end

@interface SBWindowScene : NSObject
- (SBDisplayConfigurationStub *)_sbDisplayConfiguration;
- (id)systemGestureManager;
@end

@interface SBExternalDisplayCoverSheetController : NSObject
- (BOOL)_isScreenOn;
- (id)_sbWindowScene;
@end

static const char kWakeGestureKey = 0;
static const long long kMouseDownGestureType = 0x42;     // 16.0 value of what 16.2 calls 0x43
static BOOL gWeBlanked;

static void (*gSetBlanked)(NSString *, BOOL);
static BOOL BP_BlankReady(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gSetBlanked = (void (*)(NSString *, BOOL))dlsym(RTLD_DEFAULT, "BKSDisplayServicesSetDisplayBlanked"); });
    return gSetBlanked != NULL;
}

static void BP_SetExternalBlanked(id controller, BOOL blanked) {
    SBWindowScene *scene = [controller _sbWindowScene];
    NSString *hw = [[scene _sbDisplayConfiguration] hardwareIdentifier];
    if (!hw) { BP_Log(@"blank: no hardwareIdentifier, not changing the display"); return; }
    gSetBlanked(hw, blanked);
    gWeBlanked = blanked;
    BP_Log(@"blank: display %@ blanked=%d", hw, blanked);
}

%hook SBExternalDisplayCoverSheetController

- (id)_initWithWindowScene:(id)scene lockStateProvider:(id)provider backlightController:(id)backlight windowFactory:(id)factory externalDisplayCoverSheetViewController:(id)vc {
    id me = %orig;
    if (!me || !BP_On(F_BLANK) || !BP_BlankReady()) return me;
    Class gc = NSClassFromString(@"SBFMouseButtonDownGestureRecognizer");
    id mgr = [(SBWindowScene *)scene systemGestureManager];
    if (!gc || !mgr) { BP_Log(@"blank: wake gesture unavailable (class %p, manager %p)", gc, mgr); return me; }
    SBFMouseButtonDownGestureRecognizer *g = [[gc alloc] initWithTarget:me action:@selector(_wakeScreenForMouseButtonDown:)];
    objc_setAssociatedObject(me, &kWakeGestureKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, id, long long))objc_msgSend)(mgr, @selector(addGestureRecognizer:withType:), g, kMouseDownGestureType);
    [g setEnabled:![me _isScreenOn]];
    BP_Log(@"blank: wake gesture installed");
    return me;
}

%new
- (void)_wakeScreenForMouseButtonDown:(id)gesture {
    Class c = NSClassFromString(@"SBLockScreenManager");
    id mgr = [c respondsToSelector:@selector(sharedInstanceIfExists)] ? [c performSelector:@selector(sharedInstanceIfExists)] : nil;
    if ([mgr respondsToSelector:@selector(_wakeScreenForMouseButtonDown:)]) {
        BP_Log(@"blank: mouse button down while screen off, waking");
        [mgr performSelector:@selector(_wakeScreenForMouseButtonDown:) withObject:gesture];
    }
}

- (void)_setScreenOn:(BOOL)on {
    BOOL was = [self _isScreenOn];
    %orig;
    if (was == on) return;
    BOOL active = BP_On(F_BLANK) && BP_BlankReady();
    if (active) {
        BP_SetExternalBlanked(self, !on);
        id g = objc_getAssociatedObject(self, &kWakeGestureKey);
        [g setEnabled:!on];
    } else if (on && gWeBlanked && BP_BlankReady()) {
        BP_SetExternalBlanked(self, NO);     // the feature was switched off while the display was blanked
    }
}

- (void)_setBlankingWindowVisible:(BOOL)visible fadeDuration:(double)duration {
    if (BP_On(F_BLANK) && BP_BlankReady()) return;      // 16.2: no blanking window, the display itself is blanked
    %orig;
}

%end

void BP4_InstallIfSupported(void);     // Group4Connect.m

// ---------------------------------------------------------------- entry

%ctor {
    @autoreleasepool {
        BP_InitPaths();
        if (!BP_BuildMatches()) return;
        BP_Log(@"Backport162 0.3.0 loaded");
        %init;
        BP4_InstallIfSupported();
    }
}
