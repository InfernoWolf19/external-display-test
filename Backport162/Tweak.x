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
//             The 16.0 black blanking window is kept as a fallback unless the opt-in feature "nowindow" is on.

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

#import "BP.h"

static const char *const kFeatureNames[F_COUNT] = {
    "scale", "autohost", "blank", "disconnect", "discswitch", "activedisplay", "gesturegate", "lockedptr", "nowindow", "directhook",
    "group1b", "group1b.apptoapp", "group1c", "g1c_piles", "group2", "g2b", "g2bproto", "g2blayout", "g2bkeys", "g2baperture", "g2btongue", "cgregion",
    "g3handle", "g3snapshot", "g3topaff", "g3switcher", "g3canvas", "g3embedded", "g3bootorient",
    "g3b_banner", "g3b_menu", "g3b_pip", "g3b_kbwindow", "g3b_statusbar", "g3b_orient", "g3b_grid", "g3b_guide", "g3b_split", "g3b_preflightlog", "g3b_axroles",
    "clonemirror", "edu", "edunative", "presubset", "deferact", "lockedptr2", "migrate", "focuslock", "arrange", "methodology0",
    "g3c",
};
// Opt-in features (need Backport162.on.<name>): the user directive is "everything on", so only features that the specs mark as
// behaviour-neutral (diagnostic) or mutually conflicting stay opt-in.
//   group1b.apptoapp  conflicts with group1c's replacement of the same Root class
//   g3bootorient      boot-orientation tweak, behaviour-neutral unless asked for
//   g3b_preflightlog, g3b_axroles   diagnostics / role registration of accessibility tools
//   edunative         alternative native alert instead of the SpringBoardEducation remote alert
//   methodology0      keyboard-following active display instead of the 16.2 pointer-following default
static const BOOL kOptIn[F_COUNT] = {
    [F_G1B_APPTOAPP] = YES, [F_G1C_PILES] = YES, [F_G3BOOTORIENT] = YES, [F_G3B_PREFLIGHTLOG] = YES, [F_G3B_AXROLES] = YES, [F_EDUNATIVE] = YES, [F_METHODOLOGY0] = YES,
};

static char gOffPath[1024], gDebugPath[1024], gLogPath[1024], gLogOldPath[1030], gTmpDir[900];
static pthread_mutex_t gMu = PTHREAD_MUTEX_INITIALIZER, gSlotMu = PTHREAD_MUTEX_INITIALIZER;

extern void BP_InstallCrashRecorder(const char *tmpDir);
static void BP_InitPaths(void) {
    NSString *tmp = ROOT_PATH_NS(@"/tmp");
    const char *t = tmp.fileSystemRepresentation;
    snprintf(gTmpDir, sizeof gTmpDir, "%s", t);
    snprintf(gOffPath, sizeof gOffPath, "%s/Backport162.off", t);
    snprintf(gDebugPath, sizeof gDebugPath, "%s/Backport162.debug", t);
    snprintf(gLogPath, sizeof gLogPath, "%s/Backport162.log", t);
    snprintf(gLogOldPath, sizeof gLogOldPath, "%s.1", gLogPath);
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

// Per-name switch state, cached one second. The first F_COUNT slots belong to the enum features, further slots are made
// on demand for sub-switches that packages check by name (a name that is also in kFeatureNames shares that slot).
typedef struct { char name[40]; uint64_t nextOff, nextOn; BOOL off, on; } BPSlot;
enum { kSlotMax = 160 };
static BPSlot gSlots[kSlotMax];
static int gSlotCount;

static int BP_SlotFor(const char *name) {         // gMu held
    if (gSlotCount == 0) {
        for (int i = 0; i < F_COUNT; i++) snprintf(gSlots[i].name, sizeof gSlots[i].name, "%s", kFeatureNames[i] ? kFeatureNames[i] : "");
        gSlotCount = F_COUNT;
    }
    for (int i = 0; i < gSlotCount; i++) if (strcmp(gSlots[i].name, name) == 0) return i;
    if (gSlotCount >= kSlotMax) return -1;
    snprintf(gSlots[gSlotCount].name, sizeof gSlots[0].name, "%s", name);
    return gSlotCount++;
}
static BOOL BP_SlotOn(int i, BOOL wantOnFile) {   // gMu held; killed was checked by the caller
    BPSlot *s = &gSlots[i];
    uint64_t t = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    char p[1200];
    if (t >= s->nextOff) {
        s->nextOff = t + 1000000000ull;
        snprintf(p, sizeof p, "%s/Backport162.off.%s", gTmpDir, s->name);
        s->off = gTmpDir[0] && access(p, F_OK) == 0;
    }
    if (s->off) return NO;
    if (!wantOnFile) return YES;
    if (t >= s->nextOn) {
        s->nextOn = t + 1000000000ull;
        snprintf(p, sizeof p, "%s/Backport162.on.%s", gTmpDir, s->name);
        s->on = gTmpDir[0] && access(p, F_OK) == 0;
    }
    return s->on;
}
BOOL BP_OnName(const char *name) {
    if (BP_Killed()) return NO;
    pthread_mutex_lock(&gSlotMu);
    int i = BP_SlotFor(name);
    BOOL r = i >= 0 ? BP_SlotOn(i, NO) : YES;
    pthread_mutex_unlock(&gSlotMu);
    return r;
}
BOOL BP_OptInName(const char *name) {
    if (BP_Killed()) return NO;
    pthread_mutex_lock(&gSlotMu);
    int i = BP_SlotFor(name);
    BOOL r = i >= 0 ? BP_SlotOn(i, YES) : NO;
    pthread_mutex_unlock(&gSlotMu);
    return r;
}
BOOL BP_On(int f) {
    if (f < 0 || f >= F_COUNT || BP_Killed()) return NO;
    pthread_mutex_lock(&gSlotMu);
    if (gSlotCount == 0) (void)BP_SlotFor(kFeatureNames[0]);
    BOOL r = BP_SlotOn(f, kOptIn[f]);
    pthread_mutex_unlock(&gSlotMu);
    return r;
}

void BP_Log(NSString *fmt, ...) {
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
    if (!(isfinite(orig.width) && isfinite(orig.height) && orig.width > 0 && orig.height > 0)) return orig;
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

static const char kWakeGestureKey = 0, kWakeHelperKey = 0, kWakeSceneKey = 0;
static const long long kMouseDownGestureType = 0x42;     // 16.0 value of what 16.2 calls 0x43
static BOOL gWeBlanked;


// The gesture's target. UIGestureRecognizer does not retain its target, and the external scene's gesture manager can
// outlive the cover sheet controller, so the target is this small object, owned by the gesture itself, and not the
// controller.
@interface BPWeakBox : NSObject
@property (nonatomic, weak) id object;
@end
@implementation BPWeakBox
@end

@interface BPWakeTarget : NSObject
- (void)wake:(id)gesture;
@end
@implementation BPWakeTarget
- (void)wake:(id)gesture {
    if (!BP_On(F_BLANK)) return;
    Class c = NSClassFromString(@"SBLockScreenManager");
    id mgr = [c respondsToSelector:@selector(sharedInstanceIfExists)] ? [c performSelector:@selector(sharedInstanceIfExists)] : nil;
    if ([mgr respondsToSelector:@selector(_wakeScreenForMouseButtonDown:)]) {
        BP_Log(@"blank: mouse button down while screen off, waking");
        [mgr performSelector:@selector(_wakeScreenForMouseButtonDown:) withObject:gesture];
    }
}
@end

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

// 16.0's external-display gesture manager only arms an explicit set of system-gesture types and refuses 0x42 (verified
// at 0x1c6365c28: types <= 0x39 from a bitmask, plus 0x68/0x69); 16.2 accepts the renumbered 0x43. Without this the wake
// gesture would be registered but never enabled.
%hook SBExternalDisplaySystemGestureManager
- (BOOL)_shouldEnableSystemGestureWithType:(unsigned long long)type {
    if (type == 0x42 && BP_On(F_BLANK)) return YES;
    return %orig;
}
%end

%hook SBExternalDisplayCoverSheetController

- (id)_initWithWindowScene:(id)scene lockStateProvider:(id)provider backlightController:(id)backlight windowFactory:(id)factory externalDisplayCoverSheetViewController:(id)vc {
    id me = %orig;
    if (!me || !BP_On(F_BLANK) || !BP_BlankReady()) return me;
    Class gc = NSClassFromString(@"SBFMouseButtonDownGestureRecognizer");
    id mgr = [(SBWindowScene *)scene systemGestureManager];
    if (!gc || !mgr) { BP_Log(@"blank: wake gesture unavailable (class %p, manager %p)", gc, mgr); return me; }
    BPWakeTarget *helper = [[BPWakeTarget alloc] init];
    SBFMouseButtonDownGestureRecognizer *g = [[gc alloc] initWithTarget:helper action:@selector(wake:)];
    objc_setAssociatedObject(g, &kWakeHelperKey, helper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // the gesture owns its target
    objc_setAssociatedObject(me, &kWakeGestureKey, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BPWeakBox *box = [[BPWeakBox alloc] init];
    box.object = scene;
    objc_setAssociatedObject(g, &kWakeSceneKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);        // weak: the scene may go first
    @try {
        ((void (*)(id, SEL, id, long long))objc_msgSend)(mgr, @selector(addGestureRecognizer:withType:), g, kMouseDownGestureType);
    } @catch (NSException *e) {                 // 16.0 NSAsserts on a duplicate type
        BP_Log(@"blank: gesture registration failed: %@", e);
        objc_setAssociatedObject(me, &kWakeGestureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return me;
    }
    [g setEnabled:![me _isScreenOn]];
    BP_Log(@"blank: wake gesture installed");
    return me;
}

- (void)dealloc {
    // Take the wake gesture out of play: disable it and, if the manager still exists, remove it.
    id g = objc_getAssociatedObject(self, &kWakeGestureKey);
    if (g) {
        [g setEnabled:NO];
        id scene = ((BPWeakBox *)objc_getAssociatedObject(g, &kWakeSceneKey)).object;
        id mgr = [scene respondsToSelector:@selector(systemGestureManager)] ? [scene systemGestureManager] : nil;
        if ([mgr respondsToSelector:@selector(removeGestureRecognizer:)]) [mgr performSelector:@selector(removeGestureRecognizer:) withObject:g];
    }
    %orig;
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
    // 16.2 has no blanking window: the display itself is blanked (feature "nowindow", on by default, does the same here;
    // create Backport162.off.nowindow to bring the 16.0 black window back as a fallback).
    if (BP_On(F_NOWINDOW) && BP_On(F_BLANK) && BP_BlankReady()) return;
    %orig;
}

%end

void BP4_InstallIfSupported(void);     // Group4Connect.m
void BP_G4_Setup(void);                // Group4Focus.x
void BP2B_Early(void);                 // G2B.x   (protocol hooks: before any message to a modifier class)
void G1B_Setup(void);                  // G1B.x
void BP_G2_Setup(void);                // G2.x
void BP2B_Setup(void);                 // G2B.x
void G1C_Setup(void);                  // G1C.x
void BP_G3_Setup(void);                // G3.x
void BP_G3B_Setup(void);               // G3B.x
void G3C_Setup(void);                  // G3C.x
void G4B_Setup(void);                  // G4B.x

// ---------------------------------------------------------------- entry

%ctor {
    @autoreleasepool {
        BP_InitPaths();
        if (!BP_BuildMatches()) return;
        BP_InstallCrashRecorder(gTmpDir);   // own crash report: <jbroot>/tmp/Backport162.crash (ReportCrash writes nothing for some of these crashes)
        BP_Log(@"Backport162 0.6.0 loaded");
        // BP2B_Early() must run before any message reaches a modifier class (+initialize of SBSwitcherModifier builds the
        // protocol tables); nothing above this line touches those classes.
        BP2B_Early();
        %init;
        BP4_InstallIfSupported();
        BP_G4_Setup();                 // group 4: external display
        G1B_Setup();                   // group 1b: modifier/event/response classes
        BP_G2_Setup();                 // group 2: layout data
        BP2B_Setup();                  // group 2b: switcher view
        G1C_Setup();                   // group 1c: modifier rewrites (its %init(G1C_VCIds) is last, after group 2b)
        BP_G3_Setup();                 // group 3: plumbing
        BP_G3B_Setup();                // group 3b
        G3C_Setup();                   // group 3c: Zoom on a full-screen app
        G4B_Setup();                   // group 4b
    }
}
