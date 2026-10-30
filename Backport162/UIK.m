// UIK.m : Backport162UIK, the iPadOS 16.2 (20C65) UIKit half of the port that runs INSIDE APPS (filter com.apple.UIKit, Backport162UIK.plist).
// Spec: specs/UIKIT-APP-0.7.9.md (per item: the 16.2 mechanism with addresses, what is ported, switch, log lines, test, unproven).
//
// Why a separate in-app dylib: the 16.2 external display / Stage Manager work has an app side that lives in UIKitCore (every app), not in SpringBoard.
// 16.0 UIKit lacks it, so SpringBoard-side ports alone leave the apps behaving the 16.0 way.
//
// SAFETY RULES of this file (it runs inside EVERY app of the device):
//  * Plain Objective-C runtime hooks (class_replaceMethod on the 16.0 method, the saved IMP is called for the unchanged cases). No Substrate, no code patching, no
//    signal handlers, no atexit, no threads, no ObjC messages at load.
//  * Nothing happens at load except: build / process checks, install of the hooks. Every hook is installed by UIK_Hook(), which checks that the class and the method exist
//    and that the method type encoding is the one the port was written against; otherwise it logs ONCE (always, into the UIK log) and skips that hook.
//  * Every hook is behind a kill file (checked at most once a second, no respring):  <jbroot>/tmp/Backport162.off (everything), Backport162.off.uik (this dylib),
//    Backport162.off.uik_screenbounds (U1), Backport162.off.uik_keyboard (K1), Backport162.off.uik_screenlife (U2). A kill file makes the hook call the original.
//  * Nothing throws: no @try is needed because the hooks only read ivars through the runtime (type checked at install) and send selectors that exist in both builds
//    (checked at install). Receivers were checked against the 16.0 AND the 16.2 disassembly (see the spec).
//  * Log: <jbroot>/var/mobile/Library/Caches/Backport162.uik.log (apps may read <jbroot> but write only <jbroot>/var/mobile; first writable directory of kUIKDirs wins).
//    Missing selectors / ivars / encodings are logged once per key, always. Everything else needs <jbroot>/tmp/Backport162.debug (same file the other halves use).
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/sysctl.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <stdarg.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <time.h>
#import <unistd.h>

// ---------------------------------------------------------------- switches

enum { UIK_SW_ALL = 0, UIK_SW_UIK, UIK_SW_SCREENBOUNDS, UIK_SW_KEYBOARD, UIK_SW_SCREENLIFE, UIK_SW_COUNT };
static const char *const kUIKSwitchNames[UIK_SW_COUNT] = { "Backport162.off", "Backport162.off.uik", "Backport162.off.uik_screenbounds", "Backport162.off.uik_keyboard", "Backport162.off.uik_screenlife" };
static const char kUIKTmp[] = "/var/jb/tmp";
static const char *const kUIKDirs[] = { "/var/jb/var/mobile/Library/Caches", "/var/jb/var/mobile", "/var/mobile/Library/Caches", "/var/mobile" };
#define UIK_DIR_COUNT ((int)(sizeof kUIKDirs / sizeof kUIKDirs[0]))
#define UIK_LOG_FILE "Backport162.uik.log"
#define UIK_LOG_MAX (512 * 1024)

typedef struct { uint64_t next; int present; } UIKFileState;
static UIKFileState gUIKFiles[UIK_SW_COUNT + 1];        // [UIK_SW_COUNT] = Backport162.debug

static int UIK_FilePresent(int i, const char *name) {
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    UIKFileState *s = &gUIKFiles[i];
    if (now >= s->next) {
        char p[160];
        snprintf(p, sizeof p, "%s/%s", kUIKTmp, name);
        s->present = access(p, F_OK) == 0;
        s->next = now + 1000000000ull;
    }
    return s->present;
}
// YES when the feature `sw` (UIK_SW_SCREENBOUNDS ...) is on: not killed by Backport162.off, Backport162.off.uik or its own file.
static BOOL UIK_On(int sw) {
    if (UIK_FilePresent(UIK_SW_ALL, kUIKSwitchNames[UIK_SW_ALL])) return NO;
    if (UIK_FilePresent(UIK_SW_UIK, kUIKSwitchNames[UIK_SW_UIK])) return NO;
    return !UIK_FilePresent(sw, kUIKSwitchNames[sw]);
}
static BOOL UIK_Debug(void) { return UIK_FilePresent(UIK_SW_COUNT, "Backport162.debug") != 0; }

// ---------------------------------------------------------------- log

static void UIK_Write(const char *line) {
    static int dirIdx = -2;
    static char path[200];
    if (dirIdx == -2) {
        dirIdx = -1;
        for (int i = 0; i < UIK_DIR_COUNT; i++) {
            char p[200];
            snprintf(p, sizeof p, "%s/%s", kUIKDirs[i], UIK_LOG_FILE);
            int fd = open(p, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
            if (fd < 0) continue;
            close(fd);
            snprintf(path, sizeof path, "%s", p);
            dirIdx = i;
            break;
        }
    }
    if (dirIdx < 0) return;                                // nowhere to write: stay silent (the hooks still work)
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    struct stat st;
    if (fstat(fd, &st) == 0 && st.st_size > UIK_LOG_MAX) {
        char old[220];
        snprintf(old, sizeof old, "%s.1", path);
        rename(path, old);
        close(fd);
        fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
        if (fd < 0) return;
    }
    (void)!write(fd, line, strlen(line));
    close(fd);
}
static void UIK_Vlog(const char *fmt, va_list ap) {
    char msg[480];
    vsnprintf(msg, sizeof msg, fmt, ap);
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tmv;
    localtime_r(&ts.tv_sec, &tmv);
    char line[640];
    snprintf(line, sizeof line, "%02d:%02d:%02d.%03d [%s %d] %s\n", tmv.tm_hour, tmv.tm_min, tmv.tm_sec, (int)(ts.tv_nsec / 1000000), getprogname(), (int)getpid(), msg);
    UIK_Write(line);
}
// Debug line (only with Backport162.debug).
static void UIK_Log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void UIK_Log(const char *fmt, ...) {
    if (!UIK_Debug()) return;
    va_list ap;
    va_start(ap, fmt);
    UIK_Vlog(fmt, ap);
    va_end(ap);
}
// Problem line (always, once per `key`: a missing class / selector / ivar / encoding that made a part of the port skip).
static void UIK_Problem(const char *key, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void UIK_Problem(const char *key, const char *fmt, ...) {
    enum { kMax = 48 };
    static char seen[kMax][64];
    static int n;
    for (int i = 0; i < n; i++) if (strncmp(seen[i], key, 63) == 0) return;
    if (n < kMax) snprintf(seen[n++], 64, "%s", key);
    va_list ap;
    va_start(ap, fmt);
    UIK_Vlog(fmt, ap);
    va_end(ap);
}

// ---------------------------------------------------------------- hook installation

// Type encodings are compared without the frame offsets (digits): only the argument / return types have to match.
static BOOL UIK_EncMatch(const char *have, const char *want) {
    while (*have || *want) {
        while (*have >= '0' && *have <= '9') have++;
        while (*want >= '0' && *want <= '9') want++;
        if (*have != *want) return NO;
        if (!*have) break;
        have++;
        want++;
    }
    return YES;
}
// Replaces instance method `sn` of class `cn`. `enc` is the type encoding the port was written for (NULL = do not check). Returns NO (and logs once) when the class or
// method is missing or has another encoding; the original IMP (the 16.0 one, or the inherited one) is stored in *orig.
static BOOL UIK_Hook(const char *cn, const char *sn, const char *enc, IMP imp, IMP *orig) {
    Class c = objc_getClass(cn);
    if (!c) { UIK_Problem(cn, "skip hook %s %s: class not found", cn, sn); return NO; }
    SEL sel = sel_registerName(sn);
    Method m = class_getInstanceMethod(c, sel);
    if (!m) { UIK_Problem(sn, "skip hook -[%s %s]: selector not found", cn, sn); return NO; }
    const char *have = method_getTypeEncoding(m);
    if (enc && (!have || !UIK_EncMatch(have, enc))) {
        UIK_Problem(sn, "skip hook -[%s %s]: type encoding %s, expected %s", cn, sn, have ? have : "(null)", enc);
        return NO;
    }
    *orig = method_getImplementation(m);
    class_replaceMethod(c, sel, imp, have);
    UIK_Log("hooked -[%s %s]", cn, sn);
    return YES;
}
// YES when instances of class `cn` respond to `sn` (used for selectors the port sends itself).
static BOOL UIK_Has(const char *cn, const char *sn) {
    Class c = objc_getClass(cn);
    if (!c || !class_getInstanceMethod(c, sel_registerName(sn))) { UIK_Problem(sn, "needed selector -[%s %s] not found: dependent hooks skipped", cn, sn); return NO; }
    return YES;
}

// ---------------------------------------------------------------- U1: UIScreen bounds of a main-like external display ignore the interface orientation
//
// 16.2 UIScreen (UIKitCore 16.0 -> 16.2 addresses):
//   -_boundsForInterfaceOrientation:                      0x188f91da8 -> 0x1890c7fc0
//   -_unjailedReferenceBoundsForInterfaceOrientation:     0x18937e674 -> 0x1894b4d00
//   -_mainSceneBoundsForInterfaceOrientation:             0x188f91f04 -> 0x1890c8150
//   -_connectScreen                                       0x18902b55c -> 0x189161788
// 16.0 swaps width and height of the (display native) rect when the orientation is landscape (3 / 4). 16.2 does that only for screens that are not external or are external
// but not main-like; an external MAIN-LIKE screen (the Stage Manager extended display, UIKitMainLike) is never swapped. 16.2 -_connectScreen additionally puts such a screen
// at portrait (1) without notification. screenBoundsIgnoresSceneOrientation (scene setting 0x2a) is NOT read by anything in 16.2 UIKit (spec): the behaviour is this one.

@interface UIScreen (BPUIK)
- (BOOL)_isExternal;
- (BOOL)_isMainLikeScreen;
- (void)_updateTraits;
- (void)_computeMetrics;
@end

typedef CGRect (*UIKBoundsFn)(id, SEL, long long);
static UIKBoundsFn orig_boundsFor, orig_unjailedFor, orig_mainSceneFor;
static void (*orig_connectScreen)(id, SEL);
static ptrdiff_t gUIKOrientationOffset = -1;                // UIScreen ivar _interfaceOrientation (long long)

static BOOL UIK_ExternalMainLike(id screen) {
    return [(UIScreen *)screen _isExternal] && [(UIScreen *)screen _isMainLikeScreen];
}
// 16.2 selection: external main-like -> never swapped. Asking the 16.0 body with portrait (1) returns the unswapped rect (16.0 swaps only for 3 / 4).
static inline BOOL UIK_NoSwap(id self, long long o, const char *what) {
    if (o != 3 && o != 4) return NO;
    if (!UIK_On(UIK_SW_SCREENBOUNDS) || !UIK_ExternalMainLike(self)) return NO;
    static BOOL logged;
    if (!logged && UIK_Debug()) { logged = YES; UIK_Log("U1 %s: main-like external screen %p, orientation %lld not applied to the bounds (16.2)", what, (__bridge void *)self, o); }
    return YES;
}
static CGRect uik_boundsFor(id self, SEL _cmd, long long o) { return orig_boundsFor(self, _cmd, UIK_NoSwap(self, o, "_boundsForInterfaceOrientation:") ? 1 : o); }
static CGRect uik_unjailedFor(id self, SEL _cmd, long long o) { return orig_unjailedFor(self, _cmd, UIK_NoSwap(self, o, "_unjailedReferenceBoundsForInterfaceOrientation:") ? 1 : o); }
static CGRect uik_mainSceneFor(id self, SEL _cmd, long long o) { return orig_mainSceneFor(self, _cmd, UIK_NoSwap(self, o, "_mainSceneBoundsForInterfaceOrientation:") ? 1 : o); }

static void uik_connectScreen(id self, SEL _cmd) {
    orig_connectScreen(self, _cmd);                         // 16.0 body: _updateUserInterfaceIdiom, _updateCapabilities, _updateTraits, connected flag
    if (gUIKOrientationOffset < 0 || !UIK_On(UIK_SW_SCREENBOUNDS) || !UIK_ExternalMainLike(self)) return;
    // 16.2: [self _setInterfaceOrientation:UIInterfaceOrientationPortrait andNotify:NO] (no notification): orientation 1, then _updateTraits and _computeMetrics when it changed
    long long *p = (long long *)((char *)(__bridge void *)self + gUIKOrientationOffset);
    if (*p == 1) return;
    *p = 1;
    [(UIScreen *)self _updateTraits];
    [(UIScreen *)self _computeMetrics];
    UIK_Log("U1 _connectScreen: main-like external screen %p put at portrait without notification (16.2)", (__bridge void *)self);
}

static void UIK_InstallU1(void) {
    if (!UIK_Has("UIScreen", "_isExternal") || !UIK_Has("UIScreen", "_isMainLikeScreen")) return;
    const char *rectEnc = "{CGRect={CGPoint=dd}{CGSize=dd}}24@0:8q16";
    UIK_Hook("UIScreen", "_boundsForInterfaceOrientation:", rectEnc, (IMP)uik_boundsFor, (IMP *)&orig_boundsFor);
    UIK_Hook("UIScreen", "_unjailedReferenceBoundsForInterfaceOrientation:", rectEnc, (IMP)uik_unjailedFor, (IMP *)&orig_unjailedFor);
    UIK_Hook("UIScreen", "_mainSceneBoundsForInterfaceOrientation:", rectEnc, (IMP)uik_mainSceneFor, (IMP *)&orig_mainSceneFor);
    Ivar iv = class_getInstanceVariable(objc_getClass("UIScreen"), "_interfaceOrientation");
    const char *ivEnc = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (iv && ivEnc && strcmp(ivEnc, "q") == 0) gUIKOrientationOffset = ivar_getOffset(iv);
    else UIK_Problem("_interfaceOrientation", "UIScreen ivar _interfaceOrientation %s: _connectScreen part of U1 skipped", iv ? "has another type" : "not found");
    if (gUIKOrientationOffset >= 0 && UIK_Has("UIScreen", "_updateTraits") && UIK_Has("UIScreen", "_computeMetrics"))
        UIK_Hook("UIScreen", "_connectScreen", "v16@0:8", (IMP)uik_connectScreen, (IMP *)&orig_connectScreen);
}

// ---------------------------------------------------------------- entry

static BOOL UIK_BuildMatches(void) {
    char buf[64] = {0};
    size_t n = sizeof buf;
    if (sysctlbyname("kern.osversion", buf, &n, NULL, 0) != 0) return NO;
    return strcmp(buf, "20A8372") == 0;
}
// Apps only: the main executable is inside an .app bundle (not an .appex extension, not a daemon) and is not SpringBoard (it loads UIKit too).
static BOOL UIK_IsApp(void) {
    char path[1024];
    uint32_t size = sizeof path;
    if (_NSGetExecutablePath(path, &size) != 0) return NO;
    if (!strstr(path, ".app/") || strstr(path, ".appex/")) return NO;
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    return strcmp(base, "SpringBoard") != 0;
}

__attribute__((constructor)) static void UIK_Init(void) {
    if (!UIK_BuildMatches() || !UIK_IsApp()) return;
    Dl_info di;
    if (UIK_Debug() && dladdr((void *)&UIK_Init, &di)) UIK_Log("Backport162UIK loaded, image base %p", di.dli_fbase);
    UIK_InstallU1();
}
