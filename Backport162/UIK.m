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
#import <os/lock.h>
#import <fcntl.h>
#import <stdarg.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <time.h>
#import <unistd.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

// ---------------------------------------------------------------- switches

enum { UIK_SW_ALL = 0, UIK_SW_UIK, UIK_SW_SCREENBOUNDS, UIK_SW_KEYBOARD, UIK_SW_SCREENLIFE, UIK_SW_KBFRAME, UIK_SW_KBPLACE, UIK_SW_KBOVERLAP, UIK_SW_HIDEFIX, UIK_SW_K4ACC, UIK_SW_COUNT };
static const char *const kUIKSwitchNames[UIK_SW_COUNT] = { "Backport162.off", "Backport162.off.uik", "Backport162.off.uik_screenbounds", "Backport162.off.uik_keyboard", "Backport162.off.uik_screenlife", "Backport162.off.uik_kbframe", "Backport162.off.uik_kbplace", "Backport162.off.uik_kboverlap", "Backport162.off.uik_hidefix", "Backport162.off.uik_k4acc" };
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
    enum { kMax = 240 };
    static char seen[kMax][64];
    static int n;
    for (int i = 0; i < n; i++) if (strncmp(seen[i], key, 63) == 0) return;
    if (n < kMax) snprintf(seen[n++], 64, "%s", key);
    va_list ap;
    va_start(ap, fmt);
    UIK_Vlog(fmt, ap);
    va_end(ap);
}

// Line without the once-per-key dedupe (the K4RING dump needs every line).
static void UIK_Problem_NoDedupe(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void UIK_Problem_NoDedupe(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    UIK_Vlog(fmt, ap);
    va_end(ap);
}

// ---------------------------------------------------------------- guarded sends and the exception barrier of every hook
// The dylib is injected into every app: an exception raised inside a hook is a crash of that app.  UIK_SEND sends the selector only when the receiver implements it (nil receiver: like ObjC; a miss answers
// nil / NO / 0 / CGRectZero through uik_missing_imp), so a selector of 16.2 that 16.0 does not have can never raise doesNotRecognizeSelector.  Every hook IMP below is wrapped in a narrow @try / @catch
// that logs ANOMALY uik-exception once per hook and answers with the original 16.0 implementation (or the zero value for an added method).
typedef void (*uik_fn)(void);
extern void uik_missing_imp(void) __asm__("_uik_missing_imp");
__asm__(".text\n.p2align 2\n_uik_missing_imp:\n movi d0, #0\n movi d1, #0\n movi d2, #0\n movi d3, #0\n mov x0, #0\n mov x1, #0\n ret\n");
static inline uik_fn UIK_Imp(id o, const char *s) {
    if (!o) return (uik_fn)objc_msgSend;
    return class_getInstanceMethod(object_getClass(o), sel_registerName(s)) ? (uik_fn)objc_msgSend : (uik_fn)uik_missing_imp;
}
#define UIK_SEND(T, recv, name, ...) ({ id uik_r_ = (recv); ((T)UIK_Imp(uik_r_, name))(uik_r_, sel_registerName(name), ##__VA_ARGS__); })
static void uik_exc(const char *hook, NSException *e) {
    char key[64]; snprintf(key, sizeof key, "uikexc_%s", hook);
    UIK_Problem(key, "uik-exception in hook %s (build 20A8372): %s: %s; the original 16.0 implementation answered instead", hook, e.name.UTF8String, e.reason.UTF8String ?: "-");
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
// Replaces instance method `sn` (meta = NO) or class method `sn` (meta = YES) of class `cn`. `enc` is the type encoding the port was written for (NULL = do not
// check). Returns NO (and logs once) when the class or method is missing or has another encoding; the original IMP (the 16.0 one, or the inherited one) is stored in *orig.
static BOOL UIK_HookEx(const char *cn, BOOL meta, const char *sn, const char *enc, IMP imp, IMP *orig) {
    Class c = objc_getClass(cn);
    if (!c) { UIK_Problem(cn, "skip hook %s %s: class not found", cn, sn); return NO; }
    SEL sel = sel_registerName(sn);
    Class target = meta ? object_getClass((id)c) : c;
    Method m = class_getInstanceMethod(target, sel);
    if (!m) { UIK_Problem(sn, "skip hook %c[%s %s]: selector not found", meta ? '+' : '-', cn, sn); return NO; }
    const char *have = method_getTypeEncoding(m);
    if (enc && (!have || !UIK_EncMatch(have, enc))) {
        UIK_Problem(sn, "skip hook %c[%s %s]: type encoding %s, expected %s", meta ? '+' : '-', cn, sn, have ? have : "(null)", enc);
        return NO;
    }
    *orig = method_getImplementation(m);
    class_replaceMethod(target, sel, imp, have);
    UIK_Log("hooked %c[%s %s]", meta ? '+' : '-', cn, sn);
    return YES;
}
static BOOL UIK_Hook(const char *cn, const char *sn, const char *enc, IMP imp, IMP *orig) { return UIK_HookEx(cn, NO, sn, enc, imp, orig); }
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
static CGRect uik_boundsFor_body(id self, SEL _cmd, long long o) { return orig_boundsFor(self, _cmd, UIK_NoSwap(self, o, "_boundsForInterfaceOrientation:") ? 1 : o); }
static CGRect uik_boundsFor(id self, SEL _cmd, long long o) {
    @try { return uik_boundsFor_body(self, _cmd, o); }
    @catch (NSException *e_) { uik_exc("uik_boundsFor", e_); if (orig_boundsFor) { return ((CGRect (*)(id, SEL, long long))(uik_fn)orig_boundsFor)(self, _cmd, o); } return CGRectZero; }
}

static CGRect uik_unjailedFor_body(id self, SEL _cmd, long long o) { return orig_unjailedFor(self, _cmd, UIK_NoSwap(self, o, "_unjailedReferenceBoundsForInterfaceOrientation:") ? 1 : o); }
static CGRect uik_unjailedFor(id self, SEL _cmd, long long o) {
    @try { return uik_unjailedFor_body(self, _cmd, o); }
    @catch (NSException *e_) { uik_exc("uik_unjailedFor", e_); if (orig_unjailedFor) { return ((CGRect (*)(id, SEL, long long))(uik_fn)orig_unjailedFor)(self, _cmd, o); } return CGRectZero; }
}

static CGRect uik_mainSceneFor_body(id self, SEL _cmd, long long o) { return orig_mainSceneFor(self, _cmd, UIK_NoSwap(self, o, "_mainSceneBoundsForInterfaceOrientation:") ? 1 : o); }
static CGRect uik_mainSceneFor(id self, SEL _cmd, long long o) {
    @try { return uik_mainSceneFor_body(self, _cmd, o); }
    @catch (NSException *e_) { uik_exc("uik_mainSceneFor", e_); if (orig_mainSceneFor) { return ((CGRect (*)(id, SEL, long long))(uik_fn)orig_mainSceneFor)(self, _cmd, o); } return CGRectZero; }
}


static void uik_connectScreen_body(id self, SEL _cmd) {
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
static void uik_connectScreen(id self, SEL _cmd) {
    @try { uik_connectScreen_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_connectScreen", e_); if (orig_connectScreen) { ((void (*)(id, SEL))(uik_fn)orig_connectScreen)(self, _cmd); }  }
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

// ---------------------------------------------------------------- K1: no software keyboard for text entry on the external display (16.2 UIKeyboardVisualModeManager / UIKeyboardImpl)
//
// 16.2 (UIKitCore 16.0 has none of this):
//   +[UIKeyboardVisualModeManager softwareKeyboardAllowedOnExternalScreen]               16.2 0x1898b5584: the UIKeyboardPreferencesController preference "ChamoisExternalSWKeyboard"
//                                                                                        (valueForPreferenceKey:, boolValue, cached by dispatch_once): NO unless someone sets it
//   +[UIKeyboardVisualModeManager softwareKeyboardAllowedForActiveKeyboardSceneDelegate] 16.2 0x1898b5664:
//        d = [UIKeyboardSceneDelegate activeKeyboardSceneDelegate]; if (!d) YES;
//        windowing = [[d visualModeManager] windowingModeEnabled]; embedded = [d isKeyboardOnEmbeddedScreen];
//        allowed = windowing ? [VMM windowingSoftwareKeyboardAllowed] : YES;
//        if (embedded || !allowed) return embedded && allowed;  return [VMM softwareKeyboardAllowedOnExternalScreen];
//     16.0 spread the same test (without the external flag) over -[UIKeyboardInputMode isAllowedForTraits:], -[UIKeyboardImpl automaticMinimizationEnabled] and
//     +[UIAssistantBarButtonItemProvider _isShowKeyboardButtonVisible]; 16.2 calls the function from those three AND from three NEW places:
//   -[UIKeyboardImpl _showKeyboardIgnoringPolicyDelegate:]          16.2 0x189b08ce4: after the two shouldSuppressSoftwareKeyboard tests: if (!allowed) return (keyboard is not shown)
//   -[UIKeyboardImpl _shouldMinimizeForHardwareKeyboard]            16.0 0x18909f044 / 16.2 0x1891d56b4: if (!allowed) return YES (minimized), then the old body
//   -[UIKeyboardImpl _showsScribbleIconsInAssistantView]            16.0 0x1899cf688 / 16.2 0x189b12918: after (suppressSoftwareKeyboard || floatingForced): if (!allowed) return NO
//   +[UIAssistantBarButtonItemProvider _isShowKeyboardButtonVisible] 16.0 0x189cf6384 / 16.2 0x189e41c90: (isMinimized || _suppressSoftwareKeyboard || scribble icons) && allowed
// Also new in 16.2: -[UIKeyboardSceneDelegate keyboardScreen] (= [[self scene] screen]) 0x189837eb8, -textEntryFocusOnExternalDisplay (= ![[[self scene] screen] _isEmbeddedScreen])
// 0x189839bd4, -expectedInputViewSetIsCustom 0x189839940, -expectedInputModeIsSpecialized 0x189839ac4, -_windowHostingScene:didMoveFromScreen:toScreen: 0x189839c24 (log,
// [self forceReloadInputViews]; called by -[UIScene _noteDisplayIdentityDidChangeWithConfiguration:] for every scene component that responds), -[UIKeyboardVisualModeManager
// textEntryFocusOnExternalDisplay] 0x1898b5e4c / -expectedInputModeIsSpecialized 0x1898b5f50 (delegate forwarding) and a new -[UIKeyboardVisualModeManager visualMode]
// 16.0 0x189779e74 / 16.2 0x1898b574c, ported below WITHOUT the keyboard camera term (the keyboard camera session class and keyboardCameraNotification: are 16.2 only).
// Effect: with the monitor as the keyboard scene's screen a software keyboard is never shown, anywhere (16.2 needs the hardware keyboard that the extended display
// requires anyway); the minimized accessory bar is what remains with a hardware keyboard.

static Class gKSD, gVMM, gKImpl, gKPC, gABBIP;
static SEL sActiveKSD, sVMM, sWindowingEnabled, sEmbeddedKB, sWindowingSWAllowed, sSharedPrefs, sPrefValue, sBoolValue, sActiveInstance, sIsMinimized, sDelegate, sAccessoryOnly, sScene, sScreen, sIsEmbeddedScreen, sCurrentDevice, sHWKB, sResponder, sInputVC, sInputView, sFrame, sInputModeCtl, sCurrentInputMode, sIsSpecialized, sForceReload, sDelegateAsResponder, sSuppressSW, sScribble, sExpectCustom, sExpectSpecialized, sTextEntryExt;
static BOOL gKHaveSpecialized, gKHaveResponder;
static BOOL (*orig_shouldMinimizeHW)(id, SEL);
static BOOL (*orig_scribble)(id, SEL);
static void (*orig_showKeyboard)(id, SEL, BOOL);
static BOOL (*orig_showKeyboardButton)(id, SEL);
static int (*orig_visualMode)(id, SEL);

// Message senders that answer nil / NO for a nil receiver (like ObjC) and for a receiver that does not implement the selector (a 16.0 difference then reads as "no").
static BOOL UIK_Responds(id o, SEL s) { return o && class_getInstanceMethod(object_getClass(o), s) != NULL; }
static id UIK_Id(id o, SEL s) { return UIK_Responds(o, s) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil; }
static BOOL UIK_B(id o, SEL s) { return UIK_Responds(o, s) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO; }
static id UIK_ClsId(Class c, SEL s) { return (c && class_getClassMethod(c, s)) ? ((id (*)(id, SEL))objc_msgSend)((id)c, s) : nil; }
static BOOL UIK_ClsB(Class c, SEL s) { return (c && class_getClassMethod(c, s)) ? ((BOOL (*)(id, SEL))objc_msgSend)((id)c, s) : NO; }

// +[UIKeyboardVisualModeManager softwareKeyboardAllowedOnExternalScreen]
static BOOL UIK_ExternalSWKeyboardFlag(void) {
    static BOOL value, done;
    if (!done) {
        id pc = UIK_ClsId(gKPC, sSharedPrefs);
        id v = UIK_Responds(pc, sPrefValue) ? ((id (*)(id, SEL, id))objc_msgSend)(pc, sPrefValue, @"ChamoisExternalSWKeyboard") : nil;
        value = (v && [v respondsToSelector:sBoolValue]) ? UIK_B(v, sBoolValue) : NO;
        done = YES;
        UIK_Log("K1 ChamoisExternalSWKeyboard preference = %d", (int)value);
    }
    return value;
}
// +[UIKeyboardVisualModeManager softwareKeyboardAllowedForActiveKeyboardSceneDelegate]
static BOOL UIK_SWKeyboardAllowed(void) {
    id d = UIK_ClsId(gKSD, sActiveKSD);
    if (!d) return YES;
    BOOL windowing = UIK_B(UIK_Id(d, sVMM), sWindowingEnabled);
    BOOL embedded = UIK_B(UIK_ClsId(gKSD, sActiveKSD), sEmbeddedKB);
    BOOL allowed = windowing ? UIK_ClsB(gVMM, sWindowingSWAllowed) : YES;
    if (embedded || !allowed) return embedded && allowed;
    return UIK_ExternalSWKeyboardFlag();
}
static BOOL uik_cls_swAllowedExternal_body(id self, SEL _cmd) { return UIK_ExternalSWKeyboardFlag(); }
static BOOL uik_cls_swAllowedExternal(id self, SEL _cmd) {
    @try { return uik_cls_swAllowedExternal_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_cls_swAllowedExternal", e_); return 0; }
}

static BOOL uik_cls_swAllowedActive_body(id self, SEL _cmd) { return UIK_SWKeyboardAllowed(); }
static BOOL uik_cls_swAllowedActive(id self, SEL _cmd) {
    @try { return uik_cls_swAllowedActive_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_cls_swAllowedActive", e_); return 0; }
}


// -[UIKeyboardSceneDelegate keyboardScreen] / -textEntryFocusOnExternalDisplay
static id uik_ksd_keyboardScreen_body(id self, SEL _cmd) { return UIK_Id(UIK_Id(self, sScene), sScreen); }
static id uik_ksd_keyboardScreen(id self, SEL _cmd) {
    @try { return uik_ksd_keyboardScreen_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_ksd_keyboardScreen", e_); return nil; }
}

static BOOL uik_ksd_externalFocus_body(id self, SEL _cmd) { return !UIK_B(UIK_Id(UIK_Id(self, sScene), sScreen), sIsEmbeddedScreen); }
static BOOL uik_ksd_externalFocus(id self, SEL _cmd) {
    @try { return uik_ksd_externalFocus_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_ksd_externalFocus", e_); return 0; }
}

// -[UIKeyboardSceneDelegate expectedInputViewSetIsCustom]: the responder has an input view controller, or an input view with a positive height
static BOOL uik_ksd_expectCustom_body(id self, SEL _cmd) {
    if (!gKHaveResponder) return NO;
    id r = UIK_Id(self, sResponder);
    if (UIK_Id(r, sInputVC)) return YES;
    id iv = UIK_Id(r, sInputView);
    if (!iv) return NO;
    CGRect f = ((CGRect (*)(id, SEL))objc_msgSend)(iv, sFrame);
    return f.size.height > 0;
}
static BOOL uik_ksd_expectCustom(id self, SEL _cmd) {
    @try { return uik_ksd_expectCustom_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_ksd_expectCustom", e_); return 0; }
}

// -[UIKeyboardSceneDelegate expectedInputModeIsSpecialized]: [[[UIKeyboardInputModeController sharedInputModeController] currentInputMode] isSpecializedInputMode]
static BOOL uik_ksd_expectSpecialized_body(id self, SEL _cmd) {
    if (!gKHaveSpecialized) return NO;
    id ctl = UIK_ClsId(objc_getClass("UIKeyboardInputModeController"), sInputModeCtl);
    return UIK_B(UIK_Id(ctl, sCurrentInputMode), sIsSpecialized);
}
static BOOL uik_ksd_expectSpecialized(id self, SEL _cmd) {
    @try { return uik_ksd_expectSpecialized_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_ksd_expectSpecialized", e_); return 0; }
}

// -[UIKeyboardSceneDelegate _windowHostingScene:didMoveFromScreen:toScreen:]
static void uik_ksd_didMove_body(id self, SEL _cmd, id scene, id from, id to) {
    if (!UIK_On(UIK_SW_KEYBOARD)) return;
    UIK_Log("K1 keyboard scene delegate %p: window hosting scene %p moved from screen %p to screen %p, forceReloadInputViews", (__bridge void *)self, (__bridge void *)scene, (__bridge void *)from, (__bridge void *)to);
    if ([self respondsToSelector:sForceReload]) ((void (*)(id, SEL))objc_msgSend)(self, sForceReload);
}
static void uik_ksd_didMove(id self, SEL _cmd, id scene, id from, id to) {
    @try { uik_ksd_didMove_body(self, _cmd, scene, from, to); }
    @catch (NSException *e_) { uik_exc("uik_ksd_didMove", e_);  }
}

// -[UIKeyboardVisualModeManager textEntryFocusOnExternalDisplay] / -expectedInputModeIsSpecialized (forward to the delegate, NO without one)
static BOOL uik_vmm_externalFocus_body(id self, SEL _cmd) { id d = UIK_Id(self, sDelegate); return d ? UIK_B(d, sTextEntryExt) : NO; }
static BOOL uik_vmm_externalFocus(id self, SEL _cmd) {
    @try { return uik_vmm_externalFocus_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_vmm_externalFocus", e_); return 0; }
}

static BOOL uik_vmm_expectSpecialized_body(id self, SEL _cmd) { id d = UIK_Id(self, sDelegate); return d ? UIK_B(d, sExpectSpecialized) : NO; }
static BOOL uik_vmm_expectSpecialized(id self, SEL _cmd) {
    @try { return uik_vmm_expectSpecialized_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_vmm_expectSpecialized", e_); return 0; }
}


static void UIK_Rate(const char *what, BOOL allowed) {
    static int n;
    if (n < 40 && UIK_Debug()) { n++; UIK_Log("K1 %s: software keyboard %s for the active keyboard scene delegate", what, allowed ? "allowed" : "NOT allowed (text entry focus on the external display)"); }
}
static void uik_showKeyboard_body(id self, SEL _cmd, BOOL ignore) {
    if (UIK_On(UIK_SW_KEYBOARD) && !UIK_SWKeyboardAllowed()) {
        UIK_Rate("_showKeyboardIgnoringPolicyDelegate: returns without showing", NO);
        return;
    }
    orig_showKeyboard(self, _cmd, ignore);
}
static void uik_showKeyboard(id self, SEL _cmd, BOOL ignore) {
    @try { uik_showKeyboard_body(self, _cmd, ignore); }
    @catch (NSException *e_) { uik_exc("uik_showKeyboard", e_); if (orig_showKeyboard) { ((void (*)(id, SEL, BOOL))(uik_fn)orig_showKeyboard)(self, _cmd, ignore); }  }
}

static BOOL uik_shouldMinimizeHW_body(id self, SEL _cmd) {
    if (UIK_On(UIK_SW_KEYBOARD) && !UIK_SWKeyboardAllowed()) { UIK_Rate("_shouldMinimizeForHardwareKeyboard answers YES", NO); return YES; }
    return orig_shouldMinimizeHW(self, _cmd);
}
static BOOL uik_shouldMinimizeHW(id self, SEL _cmd) {
    @try { return uik_shouldMinimizeHW_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_shouldMinimizeHW", e_); if (orig_shouldMinimizeHW) { return ((BOOL (*)(id, SEL))(uik_fn)orig_shouldMinimizeHW)(self, _cmd); } return 0; }
}

static BOOL uik_scribble_body(id self, SEL _cmd) {
    BOOL r = orig_scribble(self, _cmd);
    if (r && UIK_On(UIK_SW_KEYBOARD) && !UIK_SWKeyboardAllowed()) return NO;
    return r;
}
static BOOL uik_scribble(id self, SEL _cmd) {
    @try { return uik_scribble_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_scribble", e_); if (orig_scribble) { return ((BOOL (*)(id, SEL))(uik_fn)orig_scribble)(self, _cmd); } return 0; }
}

static BOOL uik_showKeyboardButton_body(id self, SEL _cmd) {
    if (!UIK_On(UIK_SW_KEYBOARD)) return orig_showKeyboardButton(self, _cmd);
    id ki = UIK_ClsId(gKImpl, sActiveInstance);
    BOOL x = UIK_B(ki, sIsMinimized) || UIK_B(UIK_Id(ki, sDelegateAsResponder), sSuppressSW) || UIK_B(ki, sScribble);
    return x && UIK_SWKeyboardAllowed();
}
static BOOL uik_showKeyboardButton(id self, SEL _cmd) {
    @try { return uik_showKeyboardButton_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_showKeyboardButton", e_); if (orig_showKeyboardButton) { return ((BOOL (*)(id, SEL))(uik_fn)orig_showKeyboardButton)(self, _cmd); } return 0; }
}

// -[UIKeyboardVisualModeManager visualMode] 16.2 0x1898b574c (1 = regular, 2 = minimized), without the keyboard camera term
static int uik_visualMode_body(id self, SEL _cmd) {
    if (!UIK_On(UIK_SW_KEYBOARD)) return orig_visualMode(self, _cmd);
    BOOL chamois = UIK_B(self, sWindowingEnabled);
    id ki = UIK_ClsId(gKImpl, sActiveInstance);
    BOOL hw = UIK_B(UIK_ClsId(objc_getClass("UIDevice"), sCurrentDevice), sHWKB);
    BOOL minimized = UIK_B(UIK_ClsId(gKImpl, sActiveInstance), sIsMinimized);
    id del = UIK_Id(self, sDelegate);
    BOOL custom = UIK_B(del, sExpectCustom);
    BOOL external = UIK_B(self, sTextEntryExt);
    BOOL special = UIK_B(self, sExpectSpecialized);
    int mode;
    if (!chamois) mode = 1;
    else if (!ki) mode = (hw && !external) ? ((custom || special) ? 1 : 2) : (hw ? 2 : 1);
    else if (!hw) mode = (UIK_B(UIK_Id(self, sDelegate), sAccessoryOnly) || minimized) ? 2 : 1;
    else if (custom || special) mode = external ? 2 : 1;
    else mode = minimized ? 2 : 1;
    return mode;
}
static int uik_visualMode(id self, SEL _cmd) {
    @try { return uik_visualMode_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_visualMode", e_); if (orig_visualMode) { return ((int (*)(id, SEL))(uik_fn)orig_visualMode)(self, _cmd); } return 0; }
}


static void UIK_AddMethod(Class c, BOOL meta, const char *sn, const char *enc, IMP imp) {
    Class target = meta ? object_getClass((id)c) : c;
    if (!class_addMethod(target, sel_registerName(sn), imp, enc)) UIK_Log("K1 %c[%s %s] already exists, not added", meta ? '+' : '-', class_getName(c), sn);
    else UIK_Log("K1 added %c[%s %s]", meta ? '+' : '-', class_getName(c), sn);
}
static BOOL UIK_ClsHas(Class c, BOOL meta, const char *sn) { return c && class_getInstanceMethod(meta ? object_getClass((id)c) : c, sel_registerName(sn)) != NULL; }

static void UIK_InstallK1(void) {
    gKSD = objc_getClass("UIKeyboardSceneDelegate");
    gVMM = objc_getClass("UIKeyboardVisualModeManager");
    gKImpl = objc_getClass("UIKeyboardImpl");
    gKPC = objc_getClass("UIKeyboardPreferencesController");
    gABBIP = objc_getClass("UIAssistantBarButtonItemProvider");
    if (!gKSD || !gVMM || !gKImpl || !gKPC || !gABBIP) { UIK_Problem("K1classes", "K1 skipped: a keyboard class is missing (KSD %p VMM %p Impl %p Prefs %p Assistant %p)", (__bridge void *)gKSD, (__bridge void *)gVMM, (__bridge void *)gKImpl, (__bridge void *)gKPC, (__bridge void *)gABBIP); return; }
    sActiveKSD = sel_registerName("activeKeyboardSceneDelegate"); sVMM = sel_registerName("visualModeManager"); sWindowingEnabled = sel_registerName("windowingModeEnabled");
    sEmbeddedKB = sel_registerName("isKeyboardOnEmbeddedScreen"); sWindowingSWAllowed = sel_registerName("windowingSoftwareKeyboardAllowed");
    sSharedPrefs = sel_registerName("sharedPreferencesController"); sPrefValue = sel_registerName("valueForPreferenceKey:"); sBoolValue = sel_registerName("boolValue");
    sActiveInstance = sel_registerName("activeInstance"); sIsMinimized = sel_registerName("isMinimized"); sDelegate = sel_registerName("delegate");
    sAccessoryOnly = sel_registerName("showingAccessoryViewOnly"); sScene = sel_registerName("scene"); sScreen = sel_registerName("screen"); sIsEmbeddedScreen = sel_registerName("_isEmbeddedScreen");
    sCurrentDevice = sel_registerName("currentDevice"); sHWKB = sel_registerName("_isHardwareKeyboardAvailable"); sResponder = sel_registerName("responder");
    sInputVC = sel_registerName("inputViewController"); sInputView = sel_registerName("inputView"); sFrame = sel_registerName("frame");
    sInputModeCtl = sel_registerName("sharedInputModeController"); sCurrentInputMode = sel_registerName("currentInputMode"); sIsSpecialized = sel_registerName("isSpecializedInputMode");
    sForceReload = sel_registerName("forceReloadInputViews"); sDelegateAsResponder = sel_registerName("delegateAsResponder"); sSuppressSW = sel_registerName("_suppressSoftwareKeyboard");
    sScribble = sel_registerName("_showsScribbleIconsInAssistantView"); sExpectCustom = sel_registerName("expectedInputViewSetIsCustom"); sExpectSpecialized = sel_registerName("expectedInputModeIsSpecialized");
    sTextEntryExt = sel_registerName("textEntryFocusOnExternalDisplay");
    // every selector the ported bodies send must exist in 16.0 (checked against the 16.0 disassembly); a missing one skips the whole item, logged once
    BOOL ok = YES;
    ok &= UIK_ClsHas(gKSD, YES, "activeKeyboardSceneDelegate") && UIK_ClsHas(gKSD, NO, "visualModeManager") && UIK_ClsHas(gKSD, NO, "isKeyboardOnEmbeddedScreen");
    ok &= UIK_ClsHas(gVMM, NO, "windowingModeEnabled") && UIK_ClsHas(gVMM, YES, "windowingSoftwareKeyboardAllowed") && UIK_ClsHas(gVMM, NO, "delegate");
    ok &= UIK_ClsHas(gKPC, YES, "sharedPreferencesController") && UIK_ClsHas(gKPC, NO, "valueForPreferenceKey:");
    ok &= UIK_ClsHas(gKImpl, YES, "activeInstance") && UIK_ClsHas(gKImpl, NO, "isMinimized") && UIK_ClsHas(gKImpl, NO, "delegateAsResponder") && UIK_ClsHas(gKImpl, NO, "_showsScribbleIconsInAssistantView");
    ok &= UIK_ClsHas(objc_getClass("UIScreen"), NO, "_isEmbeddedScreen") && UIK_ClsHas(objc_getClass("UIDevice"), NO, "_isHardwareKeyboardAvailable");
    if (!ok) { UIK_Problem("K1sel", "K1 skipped: a selector the 16.2 keyboard logic sends is missing in this UIKit (see the lines above)"); return; }
    if (!UIK_ClsHas(gKSD, NO, "scene") || !UIK_ClsHas(gKSD, NO, "showingAccessoryViewOnly") || !UIK_ClsHas(gKSD, NO, "forceReloadInputViews"))
        UIK_Problem("K1ksd", "K1: UIKeyboardSceneDelegate lacks scene / showingAccessoryViewOnly / forceReloadInputViews: the dependent terms read as NO / are skipped");
    gKHaveResponder = UIK_ClsHas(gKSD, NO, "responder");
    if (!gKHaveResponder) UIK_Problem("responder", "K1: -[UIKeyboardSceneDelegate responder] missing, expectedInputViewSetIsCustom answers NO");
    Class imc = objc_getClass("UIKeyboardInputMode");
    gKHaveSpecialized = UIK_ClsHas(imc, NO, "isSpecializedInputMode") && UIK_ClsHas(objc_getClass("UIKeyboardInputModeController"), YES, "sharedInputModeController") && UIK_ClsHas(objc_getClass("UIKeyboardInputModeController"), NO, "currentInputMode");
    if (!gKHaveSpecialized) UIK_Problem("specialized", "K1: UIKeyboardInputMode isSpecializedInputMode missing, expectedInputModeIsSpecialized answers NO");

    // the 16.2 methods that 16.0 lacks (16.2 callers: the scene component dispatch, the ported hooks below)
    UIK_AddMethod(gVMM, YES, "softwareKeyboardAllowedOnExternalScreen", "B16@0:8", (IMP)uik_cls_swAllowedExternal);
    UIK_AddMethod(gVMM, YES, "softwareKeyboardAllowedForActiveKeyboardSceneDelegate", "B16@0:8", (IMP)uik_cls_swAllowedActive);
    UIK_AddMethod(gKSD, NO, "keyboardScreen", "@16@0:8", (IMP)uik_ksd_keyboardScreen);
    UIK_AddMethod(gKSD, NO, "textEntryFocusOnExternalDisplay", "B16@0:8", (IMP)uik_ksd_externalFocus);
    UIK_AddMethod(gKSD, NO, "expectedInputViewSetIsCustom", "B16@0:8", (IMP)uik_ksd_expectCustom);
    UIK_AddMethod(gKSD, NO, "expectedInputModeIsSpecialized", "B16@0:8", (IMP)uik_ksd_expectSpecialized);
    UIK_AddMethod(gKSD, NO, "_windowHostingScene:didMoveFromScreen:toScreen:", "v40@0:8@16@24@32", (IMP)uik_ksd_didMove);
    UIK_AddMethod(gVMM, NO, "textEntryFocusOnExternalDisplay", "B16@0:8", (IMP)uik_vmm_externalFocus);
    UIK_AddMethod(gVMM, NO, "expectedInputModeIsSpecialized", "B16@0:8", (IMP)uik_vmm_expectSpecialized);

    UIK_Hook("UIKeyboardImpl", "_showKeyboardIgnoringPolicyDelegate:", "v@:B", (IMP)uik_showKeyboard, (IMP *)&orig_showKeyboard);
    UIK_Hook("UIKeyboardImpl", "_shouldMinimizeForHardwareKeyboard", "B@:", (IMP)uik_shouldMinimizeHW, (IMP *)&orig_shouldMinimizeHW);
    UIK_Hook("UIKeyboardImpl", "_showsScribbleIconsInAssistantView", "B@:", (IMP)uik_scribble, (IMP *)&orig_scribble);
    UIK_HookEx("UIAssistantBarButtonItemProvider", YES, "_isShowKeyboardButtonVisible", "B@:", (IMP)uik_showKeyboardButton, (IMP *)&orig_showKeyboardButton);
    UIK_Hook("UIKeyboardVisualModeManager", "visualMode", "i@:", (IMP)uik_visualMode, (IMP *)&orig_visualMode);
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

// ---------------------------------------------------------------- U2: scene based UIScreen lifecycle, auto invalidation of the screen based window scenes, live resize (16.2)
//
// 16.2 UIKitCore (16.0 -> 16.2, decoded from the machine code, DELTA-SWEEP-0.7.9.md Pass 4 section 4):
//  UIScreen   -_preventDisconnectionForReason: 0x18996babc (NEW)  +_FBSDisplayIdentityDisconnected: 0x18949bcb4 (deferred disconnect)  -_disconnectScreen 0x18996b94c
//             the foreground scene counting is gone (+_registerForStaticNotificationsIfNecessary, only called from -initWithDisplayConfiguration:forceMainScreen:); the reference display mode
//             status is set by -[_UIWindowSceneDisplaySettingsDiffAction _performActionsForUIScene:...] 0x1895fd4fc instead.
//  _UIScreenBasedWindowScene +autoInvalidates 0x1895fe7b0, -_preventAutoInvalidationForReason: 0x1895fea08 (NEW), -_performInvalidationIfNeeded 0x1895fe834 (NEW),
//             -_removeAutoInvalidationPreventionAssertion: 0x1895fedd0 (NEW), -_detachWindow: 0x18949e658, -_screenDisconnected: 0x1895ff670, +_unassociatedWindowSceneForScreen:create: 0x18908ca30.
//  Live resize: _UIWindowSceneLiveResizeDiffAction (NEW) 0x189e7a2ac, -[UIWindowScene _isInLiveResize] 0x189dfbe78, -_inLiveResizeDidChange 0x189dfbeb0, -[UIApplicationSceneSettingsDiffInspector
//             observeInLiveResizeWithBlock:] 0x1898de02c (= _observeOtherSetting:0x28), registered by -[UIApplicationSceneSpecification initialSettingsDiffActions] 0x189253a94 and
//             -[UIApplicationExternalScreenSceneSpecification initialSettingsDiffActions] 0x1898de2d4 (which also swaps _UIWindowSceneLifecycleSettingsDiffAction for the NEW
//             _UIWindowSceneNonInteractiveExternalDisplayLifecycleSettingsDiffAction 0x1895fd6f0: the same update block, then [[_UISceneLifecycleMultiplexer sharedInstance]
//             uiScene:transitionedFromState:withTransitionContext:]).
// State the 16.0 classes have no ivar for lives in associated objects (UIScreen: the prevention assertion set, needsDisconnection - bit 6 of _screenFlags is hasSetOverscanCompensation in
// 16.0; scene: _needsInvalidation, the assertion set, the screen assertion); _invalidationHandlerRegistered of 16.0 is the 16.2 _invalidationEvaluatorRegistered.
// NOT in this port (exact): __UIApplicationSceneDisconnectionHandler_block_invoke_3 0x1895f2db8 / __UIApplicationSceneConnectionHandler_block_invoke 0x1893148b4 (the only caller of
// -_preventAutoInvalidationForReason: takes the assertion for a disconnecting default scene), so no scene takes an auto invalidation assertion yet; and the debug description builders.
// The private C functions the NonInteractiveExternalDisplay lifecycle action calls (_UISceneLifecycleSettingsUpdateBlockWithCanvasAndTransitionContext 16.0 0x189144ac4) are found from the
// exported _UISceneSettingsDiffActionPerformChangesWithTransitionContextAndCompletion (16.0 0x1898216dc) by the fixed offset of the 20A8372 cache; the first 8 instruction words at the target are
// checked, otherwise that action is NOT installed (logged).

static char kUScreenSet, kUScreenNeedsDisc, kUSceneSet, kUSceneScreenAssertion, kUSceneNeedsInv;
static unsigned long gUCounter;
static IMP orig_disconnectScreenU2, orig_dispActionU2, orig_appActionsU2, orig_extActionsU2;
static ptrdiff_t gUFlagsOff = -1, gUScreenOff = -1, gULookupOff = -1, gUEvalOff = -1;
static Class gUSceneCls, gULiveCls, gUNonCls;
static id (*gUUpdateBlock)(id, id, id, id);
static void (*gUPerformChanges)(id, id, id);

static id UIK_NewSimpleAssertion(NSString *ident, NSString *reason, void (^inv)(id)) {
    Class c = objc_getClass("BSSimpleAssertion");
    SEL s = sel_registerName("initWithIdentifier:forReason:queue:invalidationBlock:");
    id a = [c alloc];
    if (!UIK_Responds(a, s)) return nil;
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(a, s, ident, reason, dispatch_get_main_queue(), inv);
}
static BOOL UIK_U2On(void) { return UIK_On(UIK_SW_SCREENLIFE); }

// ---- UIScreen
static void uik_registerStaticNotifs_body(id self, SEL _cmd) { (void)self; (void)_cmd; }
static void uik_registerStaticNotifs(id self, SEL _cmd) {
    @try { uik_registerStaticNotifs_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_registerStaticNotifs", e_);  }
}
          // 16.2 has no scene counting: nothing to register
static void uik_realDisconnect(id screen, SEL cmd) {
    objc_setAssociatedObject(screen, &kUScreenNeedsDisc, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIK_Log("U2 disconnecting screen %p", (__bridge void *)screen);
    ((void (*)(id, SEL))orig_disconnectScreenU2)(screen, cmd);
}
// the only 16.0 caller is +_FBSDisplayIdentityDisconnected: (16.2 0x18949be00: prevention set exists -> needsDisconnection, else disconnect)
static void uik_disconnectScreenU2_body(id self, SEL _cmd) {
    if (!UIK_U2On()) { ((void (*)(id, SEL))orig_disconnectScreenU2)(self, _cmd); return; }
    if (objc_getAssociatedObject(self, &kUScreenSet)) { objc_setAssociatedObject(self, &kUScreenNeedsDisc, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); UIK_Log("U2 screen %p: disconnection deferred", (__bridge void *)self); return; }
    uik_realDisconnect(self, _cmd);
}
static void uik_disconnectScreenU2(id self, SEL _cmd) {
    @try { uik_disconnectScreenU2_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_disconnectScreenU2", e_); if (orig_disconnectScreenU2) { ((void (*)(id, SEL))(uik_fn)orig_disconnectScreenU2)(self, _cmd); }  }
}

static id uik_preventDisconnection_body(id self, SEL _cmd, NSString *reason) {                    // 0x18996babc
    if (!self || gUFlagsOff < 0) return nil;
    unsigned short flags = *(unsigned short *)((char *)(__bridge void *)self + gUFlagsOff);
    if (!(flags & 0x20) || objc_getAssociatedObject(self, &kUScreenNeedsDisc)) return nil;   // connected and not needing disconnection
    NSMutableSet *set = objc_getAssociatedObject(self, &kUScreenSet);
    if (!set) { set = [NSMutableSet set]; objc_setAssociatedObject(self, &kUScreenSet, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSString *ident = [NSString stringWithFormat:@"UIScreen-%p-%lu", (__bridge void *)self, ++gUCounter];
    __weak id w = self;
    id a = UIK_NewSimpleAssertion(ident, reason, ^(id as) {                                   // block 0x18996bd28
        id s = w;
        if (!s) return;
        NSMutableSet *st = objc_getAssociatedObject(s, &kUScreenSet);
        if (![st containsObject:as]) return;
        [st removeObject:as];
        if ([st count] == 0 && objc_getAssociatedObject(s, &kUScreenNeedsDisc)) uik_realDisconnect(s, sel_registerName("_disconnectScreen"));
    });
    if (a) [set addObject:a];
    UIK_Log("U2 preventing disconnection of screen %p: %s", (__bridge void *)self, reason.UTF8String);
    return a;
}
static id uik_preventDisconnection(id self, SEL _cmd, NSString *reason) {
    @try { return uik_preventDisconnection_body(self, _cmd, reason); }
    @catch (NSException *e_) { uik_exc("uik_preventDisconnection", e_); return nil; }
}

// -[_UIWindowSceneDisplaySettingsDiffAction _performActionsForUIScene:withUpdatedFBSScene:settingsDiff:fromSettings:transitionContext:lifecycleActionType:] 16.2 0x1895fd4fc
static void uik_displayAction_body(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {
    Class ws = objc_getClass("UIWindowScene");
    if (!UIK_U2On() || !ws || ![uiScene isKindOfClass:ws]) { ((void (*)(id, SEL, id, id, id, id, id, unsigned long long))orig_dispActionU2)(self, _cmd, uiScene, fbs, diff, from, ctx, type); return; }
    unsigned char flags = from == nil ? 2 : 0;
    id insp = UIK_SEND(id (*)(id, SEL), self, "sceneSettingsDisplayDiffInspector");
    UIK_SEND(void (*)(id, SEL, id, void *), insp, "inspectDiff:withContext:", diff, &flags);
    if (!(flags & 3)) return;
    id cfg = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), fbs, "settings"), "displayConfiguration");
    id ident = UIK_SEND(id (*)(id, SEL), cfg, "identity");
    id screen = UIK_SEND(id (*)(id, SEL, id), (id)objc_getClass("UIScreen"), "_screenWithFBSDisplayIdentity:", ident);
    if (!screen) return;
    if (flags & 1) {
        id app = [UIApplication sharedApplication];
        if (!UIK_SEND(BOOL (*)(id, SEL), app, "isFrontBoard")) UIK_SEND(void (*)(id, SEL, id), screen, "_updateDisplayConfiguration:", cfg);
    }
    long long status = UIK_SEND(long long (*)(id, SEL), UIK_SEND(id (*)(id, SEL), fbs, "uiSettings"), "screenReferenceDisplayModeStatus");
    UIK_SEND(void (*)(id, SEL, long long), screen, "_setReferenceDisplayModeStatus:", status);
}
static void uik_displayAction(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {
    @try { uik_displayAction_body(self, _cmd, uiScene, fbs, diff, from, ctx, type); }
    @catch (NSException *e_) { uik_exc("uik_displayAction", e_); if (orig_dispActionU2) { ((void (*)(id, SEL, id, id, id, id, id, unsigned long long))(uik_fn)orig_dispActionU2)(self, _cmd, uiScene, fbs, diff, from, ctx, type); }  }
}


// ---- _UIScreenBasedWindowScene
static BOOL uik_yes(id self, SEL _cmd) { (void)self; (void)_cmd; return YES; }
static id uik_sceneScreen(id s) { return (__bridge id)*(void **)((char *)(__bridge void *)s + gUScreenOff); }
static BOOL uik_sceneNeedsInv(id s) { return [objc_getAssociatedObject(s, &kUSceneNeedsInv) boolValue]; }
static BOOL uik_sceneHasInvalidated(id s) { return UIK_SEND(BOOL (*)(id, SEL), s, "_hasInvalidated"); }
static id uik_preventAutoInvalidation_body(id self, SEL _cmd, NSString *reason) {                // 0x1895fea08
    if (!self) return nil;
    Class c = object_getClass(self);
    if (!UIK_SEND(BOOL (*)(id, SEL), (id)c, "autoInvalidates") || uik_sceneNeedsInv(self)) return nil;
    NSMutableSet *set = objc_getAssociatedObject(self, &kUSceneSet);
    if (!set) { set = [NSMutableSet set]; objc_setAssociatedObject(self, &kUSceneSet, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (!objc_getAssociatedObject(self, &kUSceneScreenAssertion)) {
        NSString *r = [NSString stringWithFormat:@"%s: %p: prevent screen disconnection", class_getName(c), (__bridge void *)self];
        id sa = UIK_SEND(id (*)(id, SEL, id), uik_sceneScreen(self), "_preventDisconnectionForReason:", r);
        objc_setAssociatedObject(self, &kUSceneScreenAssertion, sa, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *ident = [NSString stringWithFormat:@"%s-%p-%lu", class_getName(c), (__bridge void *)self, ++gUCounter];
    __weak id w = self;
    id a = UIK_NewSimpleAssertion(ident, reason, ^(id as) {                                   // block 0x1895fed6c
        id s = w;
        if (s) UIK_SEND(void (*)(id, SEL, id), s, "_removeAutoInvalidationPreventionAssertion:", as);
    });
    if (a) [set addObject:a];
    UIK_Log("U2 preventing auto invalidation of scene %p: %s (assertions %lu)", (__bridge void *)self, reason.UTF8String, (unsigned long)[set count]);
    return a;
}
static id uik_preventAutoInvalidation(id self, SEL _cmd, NSString *reason) {
    @try { return uik_preventAutoInvalidation_body(self, _cmd, reason); }
    @catch (NSException *e_) { uik_exc("uik_preventAutoInvalidation", e_); return nil; }
}

static void uik_performInvalidationIfNeeded_body(id self, SEL _cmd) {                            // 0x1895fe834
    if (!self || !uik_sceneNeedsInv(self) || uik_sceneHasInvalidated(self)) return;
    objc_setAssociatedObject(self, &kUSceneNeedsInv, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIK_Log("U2 performing invalidation for scene %p", (__bridge void *)self);
    UIK_SEND(void (*)(id, SEL), self, "_invalidate");
    Class c = object_getClass(self);
    id key = (__bridge id)*(void **)((char *)(__bridge void *)self + gULookupOff);
    id q = UIK_SEND(id (*)(id, SEL), (id)c, "unassociationCacheAccessQueue");
    dispatch_sync((dispatch_queue_t)q, ^{ UIK_SEND(void (*)(id, SEL, id), UIK_SEND(id (*)(id, SEL), (id)c, "unassociationCache"), "removeObjectForKey:", key); });
}
static void uik_performInvalidationIfNeeded(id self, SEL _cmd) {
    @try { uik_performInvalidationIfNeeded_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_performInvalidationIfNeeded", e_);  }
}

static void uik_removeAutoInvalidationAssertion_body(id self, SEL _cmd, id assertion) {          // 0x1895fedd0
    NSMutableSet *set = objc_getAssociatedObject(self, &kUSceneSet);
    if (![set containsObject:assertion]) { UIK_Problem("u2-removeassertion", "U2 _removeAutoInvalidationPreventionAssertion: for an assertion that is not held (16.2 asserts)"); return; }
    [set removeObject:assertion];
    if ([set count] == 0) {
        UIK_SEND(void (*)(id, SEL), self, "_performInvalidationIfNeeded");
        id sa = objc_getAssociatedObject(self, &kUSceneScreenAssertion);
        if (sa) UIK_SEND(void (*)(id, SEL), sa, "invalidate");
        objc_setAssociatedObject(self, &kUSceneScreenAssertion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void uik_removeAutoInvalidationAssertion(id self, SEL _cmd, id assertion) {
    @try { uik_removeAutoInvalidationAssertion_body(self, _cmd, assertion); }
    @catch (NSException *e_) { uik_exc("uik_removeAutoInvalidationAssertion", e_);  }
}

static void uik_screenDisconnected_body(id self, SEL _cmd, NSNotification *n) {                 // 0x1895ff670
    id screen = n.object;
    if (![screen isKindOfClass:objc_getClass("UIScreen")] || uik_sceneScreen(self) != screen) return;
    id sa = objc_getAssociatedObject(self, &kUSceneScreenAssertion);
    if (sa) UIK_Problem("u2-disconnect-assertion", "U2 screen is disconnecting while an assertion should prevent it (16.2 logs a fault)");
    if (sa) UIK_SEND(void (*)(id, SEL), sa, "invalidate");
    objc_setAssociatedObject(self, &kUSceneScreenAssertion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kUSceneNeedsInv, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIK_SEND(void (*)(id, SEL), self, "_performInvalidationIfNeeded");
}
static void uik_screenDisconnected(id self, SEL _cmd, NSNotification *n) {
    @try { uik_screenDisconnected_body(self, _cmd, n); }
    @catch (NSException *e_) { uik_exc("uik_screenDisconnected", e_);  }
}

static IMP orig_detachU2, orig_unassocU2;
static void uik_detachWindow_body(id self, SEL _cmd, id window) {                                // 0x18949e658
    if (!UIK_U2On()) { ((void (*)(id, SEL, id))orig_detachU2)(self, _cmd, window); return; }
    IMP sup = class_getMethodImplementation(class_getSuperclass(gUSceneCls), _cmd);
    ((void (*)(id, SEL, id))sup)(self, _cmd, window);
    Class c = object_getClass(self);
    if (!UIK_SEND(BOOL (*)(id, SEL), (id)c, "autoInvalidates")) return;
    BOOL *reg = (BOOL *)((char *)(__bridge void *)self + gUEvalOff);
    if (*reg || uik_sceneHasInvalidated(self)) return;
    *reg = YES;
    __weak id w = self;
    [[NSRunLoop mainRunLoop] performBlock:^{
        id s = w;
        if (!s || uik_sceneHasInvalidated(s)) return;
        __block BOOL hasWindows = NO;
        void (^each)(id, BOOL *) = ^(id win, BOOL *stop) { hasWindows = YES; if (stop) *stop = YES; };
        UIK_SEND(void (*)(id, SEL, BOOL, BOOL, BOOL, BOOL *, id), s, "_enumerateWindowsIncludingInternalWindows:onlyVisibleWindows:asCopy:stopped:withBlock:", YES, NO, NO, NULL, each);
        if (!hasWindows) {
            objc_setAssociatedObject(s, &kUSceneNeedsInv, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIK_Log("U2 marking scene %p as needing invalidation", (__bridge void *)s);
            NSSet *set = objc_getAssociatedObject(s, &kUSceneSet);
            if (!set || [set count] == 0) UIK_SEND(void (*)(id, SEL), s, "_performInvalidationIfNeeded");
        }
        *(BOOL *)((char *)(__bridge void *)s + gUEvalOff) = NO;
    }];
}
static void uik_detachWindow(id self, SEL _cmd, id window) {
    @try { uik_detachWindow_body(self, _cmd, window); }
    @catch (NSException *e_) { uik_exc("uik_detachWindow", e_); if (orig_detachU2) { ((void (*)(id, SEL, id))(uik_fn)orig_detachU2)(self, _cmd, window); }  }
}

// +[_UIScreenBasedWindowScene _unassociatedWindowSceneForScreen:create:] 0x18908ca30: the scene is made OUTSIDE the cache queue block
static id uik_unassociated_body(id cls, SEL _cmd, id screen, BOOL create) {
    if (!UIK_U2On()) return ((id (*)(id, SEL, id, BOOL))orig_unassocU2)(cls, _cmd, screen, create);
    __block id key = nil, ctx = nil;
    __block BOOL created = NO;
    id q = UIK_SEND(id (*)(id, SEL), cls, "unassociationCacheAccessQueue");
    dispatch_sync((dispatch_queue_t)q, ^{
        id k = UIK_SEND(id (*)(id, SEL), screen, "displayIdentity");
        if (!k) k = UIK_SEND(id (*)(id, SEL), screen, "_name");
        key = k;
        id cache = UIK_SEND(id (*)(id, SEL), cls, "unassociationCache");
        ctx = UIK_SEND(id (*)(id, SEL, id), cache, "objectForKey:", key);
        if (ctx || !create) return;
        created = YES;
        ctx = [[objc_getClass("_UISceneUnassociatedContext") alloc] init];
        id sess = UIK_SEND(id (*)(id, SEL, id, id, id), [objc_getClass("UISceneSession") alloc], "_initWithPersistentIdentifier:sessionRole:configurationName:", [[NSUUID UUID] UUIDString], @"_UIScreenBasedSceneSession", nil);
        id cfg = UIK_SEND(id (*)(id, SEL), sess, "configuration");
        UIK_SEND(void (*)(id, SEL, Class), cfg, "setSceneClass:", Nil);
        UIK_SEND(void (*)(id, SEL, Class), cfg, "setDelegateClass:", Nil);
        UIK_SEND(void (*)(id, SEL, id), cfg, "setStoryboard:", nil);
        UIK_SEND(void (*)(id, SEL, id), sess, "_updateConfiguration:", cfg);
        UIK_SEND(void (*)(id, SEL, id), ctx, "setSession:", sess);
        UIK_SEND(void (*)(id, SEL, id, id), cache, "setObject:forKey:", ctx, key);
    });
    if (created && ctx && key) {
        id sess = UIK_SEND(id (*)(id, SEL), ctx, "session");
        id scene = UIK_SEND(id (*)(id, SEL, id, id, id), [cls alloc], "initWithScreen:session:lookupKey:", screen, sess, key);
        UIK_SEND(void (*)(id, SEL, id), ctx, "setScene:", scene);
        NSString *const *pn = (NSString *const *)dlsym(RTLD_DEFAULT, "_UISceneWillConnectNotification");
        [[NSNotificationCenter defaultCenter] postNotificationName:pn ? *pn : @"_UISceneWillConnectNotification" object:scene];
        UIK_SEND(void (*)(id, SEL, id), sess, "_setScene:", scene);
    }
    return UIK_SEND(id (*)(id, SEL), ctx, "scene");
}
static id uik_unassociated(id cls, SEL _cmd, id screen, BOOL create) {
    @try { return uik_unassociated_body(cls, _cmd, screen, create); }
    @catch (NSException *e_) { uik_exc("uik_unassociated", e_); if (orig_unassocU2) { return ((id (*)(id, SEL, id, BOOL))(uik_fn)orig_unassocU2)(cls, _cmd, screen, create); } return nil; }
}


// ---- live resize
static void uik_inLiveResizeDidChange_body(id self, SEL _cmd) {                                  // 0x189dfbeb0
    if (!self) return;
    BOOL live = UIK_SEND(BOOL (*)(id, SEL), self, "_isInLiveResize");
    [[NSNotificationCenter defaultCenter] postNotificationName:live ? @"UIWindowSceneDidBeginLiveResizeNotification" : @"UIWindowSceneDidEndLiveResizeNotification" object:self];
}
static void uik_inLiveResizeDidChange(id self, SEL _cmd) {
    @try { uik_inLiveResizeDidChange_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_inLiveResizeDidChange", e_);  }
}

static BOOL uik_isInLiveResize_body(id self, SEL _cmd) {                                         // 0x189dfbe78
    id s = UIK_SEND(id (*)(id, SEL), self, "_effectiveUISettings");
    return UIK_SEND(BOOL (*)(id, SEL), s, "inLiveResize");
}
static BOOL uik_isInLiveResize(id self, SEL _cmd) {
    @try { return uik_isInLiveResize_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_isInLiveResize", e_); return 0; }
}

static void uik_observeInLiveResize_body(id self, SEL _cmd, id block) { UIK_SEND(void (*)(id, SEL, unsigned long long, id), self, "_observeOtherSetting:withBlock:", 0x28, block); }
static void uik_observeInLiveResize(id self, SEL _cmd, id block) {
    @try { uik_observeInLiveResize_body(self, _cmd, block); }
    @catch (NSException *e_) { uik_exc("uik_observeInLiveResize", e_);  }
}

static char kULiveInsp;
static id uik_liveInspector_body(id self, SEL _cmd) {
    id i = objc_getAssociatedObject(self, &kULiveInsp);
    if (!i) {
        i = [[objc_getClass("UIApplicationSceneSettingsDiffInspector") alloc] init];
        UIK_SEND(void (*)(id, SEL, id), i, "observeInLiveResizeWithBlock:", ^(void *ctx) { *(unsigned char *)ctx |= 1; });
        objc_setAssociatedObject(self, &kULiveInsp, i, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return i;
}
static id uik_liveInspector(id self, SEL _cmd) {
    @try { return uik_liveInspector_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_liveInspector", e_); return nil; }
}

static void uik_setLiveInspector_body(id self, SEL _cmd, id i) { objc_setAssociatedObject(self, &kULiveInsp, i, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void uik_setLiveInspector(id self, SEL _cmd, id i) {
    @try { uik_setLiveInspector_body(self, _cmd, i); }
    @catch (NSException *e_) { uik_exc("uik_setLiveInspector", e_);  }
}

static void uik_liveAction_body(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {   // 0x189e7a2ac
    if (![uiScene isKindOfClass:objc_getClass("UIWindowScene")]) { UIK_Problem("u2-live", "U2 live resize action for a scene that is not a UIWindowScene (16.2 asserts)"); return; }
    unsigned char flag = 0;
    UIK_SEND(void (*)(id, SEL, id, void *), UIK_SEND(id (*)(id, SEL), self, "sceneSettingsLiveResizeDiffInspector"), "inspectDiff:withContext:", diff, &flag);
    if (flag & 1) UIK_SEND(void (*)(id, SEL), uiScene, "_inLiveResizeDidChange");
}
static void uik_liveAction(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {
    @try { uik_liveAction_body(self, _cmd, uiScene, fbs, diff, from, ctx, type); }
    @catch (NSException *e_) { uik_exc("uik_liveAction", e_);  }
}

static void uik_nonInteractiveAction_body(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {   // 0x1895fd6f0
    if (!UIK_SEND(BOOL (*)(id, SEL), uiScene, "_hasLifecycle")) return;
    id settings = UIK_SEND(id (*)(id, SEL), uiScene, "_effectiveSettings");
    id blk = gUUpdateBlock(uiScene, from, settings, ctx);
    if (!blk) return;
    void (^b)(void) = blk;
    gUPerformChanges(ctx, ^{                                                                  // block 0x1895fd824
        b();
        id mux = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("_UISceneLifecycleMultiplexer"), "sharedInstance");
        UIK_SEND(void (*)(id, SEL, id, id, id), mux, "uiScene:transitionedFromState:withTransitionContext:", uiScene, from, ctx);
    }, nil);
}
static void uik_nonInteractiveAction(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {
    @try { uik_nonInteractiveAction_body(self, _cmd, uiScene, fbs, diff, from, ctx, type); }
    @catch (NSException *e_) { uik_exc("uik_nonInteractiveAction", e_);  }
}

static id uik_firstOfClass(NSArray *a, const char *name) { Class c = objc_getClass(name); for (id o in a) if (c && [o isKindOfClass:c]) return o; return nil; }
static id uik_appActions_body(id self, SEL _cmd) {
    NSArray *a = ((id (*)(id, SEL))orig_appActionsU2)(self, _cmd);
    if (!UIK_U2On() || ![a isKindOfClass:[NSArray class]] || uik_firstOfClass(a, "_UIWindowSceneLiveResizeDiffAction")) return a;
    NSMutableArray *m = [a mutableCopy];
    id w = uik_firstOfClass(m, "_UIWindowSceneWindowingModeDiffAction");
    if (!w) { UIK_Problem("u2-appactions", "U2 initialSettingsDiffActions: no _UIWindowSceneWindowingModeDiffAction in the array, live resize action not added"); return a; }
    [m insertObject:[[gULiveCls alloc] init] atIndex:[m indexOfObject:w] + 1];
    return m;
}
static id uik_appActions(id self, SEL _cmd) {
    @try { return uik_appActions_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_appActions", e_); if (orig_appActionsU2) { return ((id (*)(id, SEL))(uik_fn)orig_appActionsU2)(self, _cmd); } return nil; }
}

static id uik_extActions_body(id self, SEL _cmd) {
    NSArray *a = ((id (*)(id, SEL))orig_extActionsU2)(self, _cmd);
    if (!UIK_U2On() || ![a isKindOfClass:[NSArray class]] || !gUNonCls) return a;
    id d = uik_firstOfClass(a, "_UIWindowSceneDisplaySettingsDiffAction"), g = uik_firstOfClass(a, "_UIWindowSceneGeometrySettingsDiffAction"), o = uik_firstOfClass(a, "_UIWindowSceneOcclusionSettingsDiffAction"), w = uik_firstOfClass(a, "_UIWindowSceneWindowingModeDiffAction");
    if (!d || !g || !o || !w || !uik_firstOfClass(a, "_UIWindowSceneLifecycleSettingsDiffAction")) { UIK_Problem("u2-extactions", "U2 external screen initialSettingsDiffActions has an unexpected content: left as is"); return a; }
    return @[d, [[gUNonCls alloc] init], w, [[gULiveCls alloc] init], g, o];                  // 16.2 order
}
static id uik_extActions(id self, SEL _cmd) {
    @try { return uik_extActions_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_extActions", e_); if (orig_extActionsU2) { return ((id (*)(id, SEL))(uik_fn)orig_extActionsU2)(self, _cmd); } return nil; }
}


static Class UIK_MakeAction(const char *name, SEL perform, IMP imp) {
    Class c = objc_getClass(name);
    if (c) return c;
    c = objc_allocateClassPair([NSObject class], name, 0);
    if (!c) return Nil;
    Protocol *p = objc_getProtocol("_UISceneSettingsDiffAction");
    if (p) class_addProtocol(c, p);
    class_addMethod(c, perform, imp, "v64@0:8@16@24@32@40@48Q56");
    return c;                                                                                 // registered by the caller after adding the rest
}
static void UIK_InstallU2(void) {
    NSMutableArray *missing = [NSMutableArray array];
    Class screen = objc_getClass("UIScreen");
    gUSceneCls = objc_getClass("_UIScreenBasedWindowScene");
    Class kb = objc_getClass("_UIKeyboardWindowScene"), ph = objc_getClass("_UIPlaceholderWindowScene"), win = objc_getClass("UIWindowScene");
    Class insp = objc_getClass("UIApplicationSceneSettingsDiffInspector"), dispAct = objc_getClass("_UIWindowSceneDisplaySettingsDiffAction");
    Class appSpec = objc_getClass("UIApplicationSceneSpecification"), extSpec = objc_getClass("UIApplicationExternalScreenSceneSpecification");
    if (!screen) [missing addObject:@"class UIScreen"];
    if (!gUSceneCls) [missing addObject:@"class _UIScreenBasedWindowScene"];
    if (!win) [missing addObject:@"class UIWindowScene"];
    if (!insp) [missing addObject:@"class UIApplicationSceneSettingsDiffInspector"];
    if (!dispAct) [missing addObject:@"class _UIWindowSceneDisplaySettingsDiffAction"];
    if (!appSpec || !extSpec) [missing addObject:@"classes UIApplicationSceneSpecification / UIApplicationExternalScreenSceneSpecification"];
    if (!objc_getClass("BSSimpleAssertion") || !class_getInstanceMethod(objc_getClass("BSSimpleAssertion"), sel_registerName("initWithIdentifier:forReason:queue:invalidationBlock:"))) [missing addObject:@"-[BSSimpleAssertion initWithIdentifier:forReason:queue:invalidationBlock:]"];
    if (!objc_getClass("_UISceneUnassociatedContext") || !objc_getClass("UISceneSession")) [missing addObject:@"classes _UISceneUnassociatedContext / UISceneSession"];
    if (screen) {
        Ivar f = class_getInstanceVariable(screen, "_screenFlags");
        if (f) gUFlagsOff = ivar_getOffset(f); else [missing addObject:@"ivar UIScreen._screenFlags"];
        if (!class_getInstanceMethod(screen, sel_registerName("_disconnectScreen"))) [missing addObject:@"-[UIScreen _disconnectScreen]"];
        if (!class_getClassMethod(screen, sel_registerName("_registerForStaticNotificationsIfNecessary"))) [missing addObject:@"+[UIScreen _registerForStaticNotificationsIfNecessary]"];
    }
    if (gUSceneCls) {
        Ivar a = class_getInstanceVariable(gUSceneCls, "_screen"), b = class_getInstanceVariable(gUSceneCls, "_lookupKey"), c = class_getInstanceVariable(gUSceneCls, "_invalidationHandlerRegistered");
        if (a) gUScreenOff = ivar_getOffset(a); else [missing addObject:@"ivar _UIScreenBasedWindowScene._screen"];
        if (b) gULookupOff = ivar_getOffset(b); else [missing addObject:@"ivar _UIScreenBasedWindowScene._lookupKey"];
        if (c) gUEvalOff = ivar_getOffset(c); else [missing addObject:@"ivar _UIScreenBasedWindowScene._invalidationHandlerRegistered"];
        const char *needs[] = { "_hasInvalidated", "_invalidate", "_screenDisconnected:", "_detachWindow:" };
        for (size_t i = 0; i < sizeof needs / sizeof *needs; i++) if (!class_getInstanceMethod(gUSceneCls, sel_registerName(needs[i]))) [missing addObject:[NSString stringWithFormat:@"-[_UIScreenBasedWindowScene %s]", needs[i]]];
        if (!class_getClassMethod(gUSceneCls, sel_registerName("_unassociatedWindowSceneForScreen:create:")) || !class_getClassMethod(gUSceneCls, sel_registerName("unassociationCache")) || !class_getClassMethod(gUSceneCls, sel_registerName("unassociationCacheAccessQueue"))) [missing addObject:@"+[_UIScreenBasedWindowScene _unassociatedWindowSceneForScreen:create: / unassociationCache / unassociationCacheAccessQueue]"];
    }
    if (win && !class_getInstanceMethod(win, sel_registerName("_effectiveUISettings"))) [missing addObject:@"-[UIWindowScene _effectiveUISettings]"];
    if (insp && !class_getInstanceMethod(insp, sel_registerName("_observeOtherSetting:withBlock:"))) [missing addObject:@"-[UIApplicationSceneSettingsDiffInspector _observeOtherSetting:withBlock:]"];
    if (appSpec && !class_getInstanceMethod(appSpec, sel_registerName("initialSettingsDiffActions"))) [missing addObject:@"-[UIApplicationSceneSpecification initialSettingsDiffActions]"];
    if (extSpec && !class_getInstanceMethod(extSpec, sel_registerName("initialSettingsDiffActions"))) [missing addObject:@"-[UIApplicationExternalScreenSceneSpecification initialSettingsDiffActions]"];
    SEL perform = sel_registerName("_performActionsForUIScene:withUpdatedFBSScene:settingsDiff:fromSettings:transitionContext:lifecycleActionType:");
    if (dispAct && !class_getInstanceMethod(dispAct, perform)) [missing addObject:@"-[_UIWindowSceneDisplaySettingsDiffAction _performActionsForUIScene:...]"];
    if ([missing count]) { UIK_Problem("u2-install", "U2 NOT installed (build 20A8372), needs: %s", [[missing componentsJoinedByString:@", "] UTF8String]); return; }

    // the lifecycle action of the external display scenes needs two functions: the exported one and (by fixed offset) the private one
    void *ref = dlsym(RTLD_DEFAULT, "_UISceneSettingsDiffActionPerformChangesWithTransitionContextAndCompletion");
    BOOL haveNon = NO;
    if (!ref) UIK_Problem("u2-ref", "U2 NonInteractiveExternalDisplay lifecycle action NOT installed: symbol _UISceneSettingsDiffActionPerformChangesWithTransitionContextAndCompletion (UIKitCore) not found");
    else {
        uintptr_t r = (uintptr_t)ref;
#if __has_feature(ptrauth_calls)
        r = (uintptr_t)ptrauth_strip(ref, ptrauth_key_function_pointer);
#endif
        uintptr_t t = r - (0x1898216dcULL - 0x189144ac4ULL);                                 // 20A8372: the exported function minus the private one
        static const unsigned int want[8] = { 0xd503237f, 0xd10203ff, 0xa9045ff8, 0xa90557f6, 0xa9064ff4, 0xa9077bfd, 0x9101c3fd, 0xaa0303f6 };
        BOOL same = YES;
        for (int i = 0; i < 8; i++) if (((const unsigned int *)t)[i] != want[i]) same = NO;
        if (!same) UIK_Problem("u2-update", "U2 NonInteractiveExternalDisplay lifecycle action NOT installed: the instruction words at _UISceneLifecycleSettingsUpdateBlockWithCanvasAndTransitionContext (exported function - 0x6dcc18 = %p) are not the 20A8372 ones", (void *)t);
        else {
            void *tp = (void *)t, *rp = (void *)r;
#if __has_feature(ptrauth_calls)
            tp = ptrauth_sign_unauthenticated(tp, ptrauth_key_function_pointer, 0);
            rp = ref;
#endif
            gUUpdateBlock = (id (*)(id, id, id, id))tp;
            gUPerformChanges = (void (*)(id, id, id))rp;
            haveNon = YES;
        }
    }
    if (!objc_getClass("_UISceneLifecycleMultiplexer") || !class_getInstanceMethod(win, sel_registerName("_hasLifecycle")) || !class_getInstanceMethod(win, sel_registerName("_effectiveSettings"))) haveNon = NO;

    // UIScreen
    class_replaceMethod(object_getClass((id)screen), sel_registerName("_registerForStaticNotificationsIfNecessary"), (IMP)uik_registerStaticNotifs, "v16@0:8");
    UIK_Hook("UIScreen", "_disconnectScreen", "v16@0:8", (IMP)uik_disconnectScreenU2, &orig_disconnectScreenU2);
    class_addMethod(screen, sel_registerName("_preventDisconnectionForReason:"), (IMP)uik_preventDisconnection, "@24@0:8@16");
    UIK_Hook("_UIWindowSceneDisplaySettingsDiffAction", "_performActionsForUIScene:withUpdatedFBSScene:settingsDiff:fromSettings:transitionContext:lifecycleActionType:", NULL, (IMP)uik_displayAction, &orig_dispActionU2);
    // scene
    Class metas[3] = { gUSceneCls, kb, ph };
    for (int i = 0; i < 3; i++) if (metas[i]) class_addMethod(object_getClass((id)metas[i]), sel_registerName("autoInvalidates"), (IMP)uik_yes, "B16@0:8");
    class_addMethod(gUSceneCls, sel_registerName("_preventAutoInvalidationForReason:"), (IMP)uik_preventAutoInvalidation, "@24@0:8@16");
    class_addMethod(gUSceneCls, sel_registerName("_performInvalidationIfNeeded"), (IMP)uik_performInvalidationIfNeeded, "v16@0:8");
    class_addMethod(gUSceneCls, sel_registerName("_removeAutoInvalidationPreventionAssertion:"), (IMP)uik_removeAutoInvalidationAssertion, "v24@0:8@16");
    class_replaceMethod(gUSceneCls, sel_registerName("_screenDisconnected:"), (IMP)uik_screenDisconnected, "v24@0:8@16");
    UIK_Hook("_UIScreenBasedWindowScene", "_detachWindow:", NULL, (IMP)uik_detachWindow, &orig_detachU2);
    UIK_HookEx("_UIScreenBasedWindowScene", YES, "_unassociatedWindowSceneForScreen:create:", NULL, (IMP)uik_unassociated, &orig_unassocU2);
    // live resize
    class_addMethod(win, sel_registerName("_isInLiveResize"), (IMP)uik_isInLiveResize, "B16@0:8");
    class_addMethod(win, sel_registerName("_inLiveResizeDidChange"), (IMP)uik_inLiveResizeDidChange, "v16@0:8");
    class_addMethod(insp, sel_registerName("observeInLiveResizeWithBlock:"), (IMP)uik_observeInLiveResize, "v24@0:8@?16");
    gULiveCls = UIK_MakeAction("_UIWindowSceneLiveResizeDiffAction", perform, (IMP)uik_liveAction);
    if (gULiveCls && !objc_getClass("_UIWindowSceneLiveResizeDiffAction")) {
        class_addMethod(gULiveCls, sel_registerName("sceneSettingsLiveResizeDiffInspector"), (IMP)uik_liveInspector, "@16@0:8");
        class_addMethod(gULiveCls, sel_registerName("setSceneSettingsLiveResizeDiffInspector:"), (IMP)uik_setLiveInspector, "v24@0:8@16");
        objc_registerClassPair(gULiveCls);
    }
    if (haveNon) {
        gUNonCls = UIK_MakeAction("_UIWindowSceneNonInteractiveExternalDisplayLifecycleSettingsDiffAction", perform, (IMP)uik_nonInteractiveAction);
        if (gUNonCls && !objc_getClass("_UIWindowSceneNonInteractiveExternalDisplayLifecycleSettingsDiffAction")) objc_registerClassPair(gUNonCls);
    }
    if (!gULiveCls) { UIK_Problem("u2-liveclass", "U2 live resize action class could not be made: registration skipped"); return; }
    UIK_Hook("UIApplicationSceneSpecification", "initialSettingsDiffActions", NULL, (IMP)uik_appActions, &orig_appActionsU2);
    UIK_Hook("UIApplicationExternalScreenSceneSpecification", "initialSettingsDiffActions", NULL, (IMP)uik_extActions, &orig_extActionsU2);
    UIK_Log("U2 installed (non interactive lifecycle action: %d)", (int)haveNon);
}

// ---------------------------------------------------------------- K2: keyboard notification frames in a Stage Manager window (16.2 UIInputWindowController)
//
// 16.0 (UIKitCore 0x18997ecc8 -postToCorrespondingWindowSceneWithNotification:userInfo:, called by the blocks of -postValidatedStartNotifications:withInfo: 0x1891b1434 / End 0x1891b0adc right before
// the plain [nc postNotificationName:object:screen userInfo:]): when the app was linked against the iOS 16.0 SDK (_dyld_program_sdk_at_least 0x0010000000000002) AND the keyboard windowing mode is enabled AND
// the visual mode is not windowed, a SECOND notification with the keyboard frames CONVERTED into the scene's coordinate space is posted.  An app that reads UIKeyboardFrameEndUserInfoKey and converts it
// from the screen to its own window then gets a frame that is already window relative, finds no overlap with its window and does not move its UI (Reynard, Telegram windowed).
// 16.2 (-postNotificationName:userInfo: 0x189abf33c, -needsConvertToSceneCoordinates 0x189abed7c, -convertUserInfo: 0x189abefa4): ONE notification per name; the frames are converted only when
// needsConvertToSceneCoordinates (windowing mode enabled AND the app opted in: TextInput pref AlwaysConvertToSceneCoordinates, or the bundle id is in {com.apple.MobileAddressBook, com.apple.mobilenotes},
// or in {com.tinyspeck.chatlyio, com.hammerandchisel.discord, com.apple.Pages, com.apple.Numbers, com.apple.Keynote} while the app is NOT linked against the 16.0 SDK; pref AlwaysNotConvertToSceneCoordinates
// vetoes), otherwise they stay in UIScreen coordinates ("Warning - Keyboard frames in keyboard notifications are in UIScreen coordinates").
// Port (switch uik_keyboard): the 16.0 method posts nothing unless needsConvert (the caller's plain post is then the one 16.2 notification) and otherwise posts the converted one with object = the screen and
// drops the plain post that follows it (thread local, narrow hook of -[NSNotificationCenter postNotificationName:object:userInfo:]); the three 16.2 methods are added.
static IMP orig_postCorrespK2, orig_ncPostK2;
static __thread __unsafe_unretained NSString *tK2Suppress;
static BOOL UIK_K2Cached(void) {
    static BOOL cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class tp = objc_getClass("TIPreferencesController");
        id pc = tp ? UIK_SEND(id (*)(id, SEL), (id)tp, "sharedPreferencesController") : nil;
        SEL vf = sel_registerName("valueForPreferenceKey:");
        id v = (pc && [pc respondsToSelector:vf]) ? ((id (*)(id, SEL, id))objc_msgSend)(pc, vf, @"AlwaysConvertToSceneCoordinates") : nil;
        cached = [v respondsToSelector:@selector(boolValue)] && [v boolValue];
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (!cached) {
            cached = [@[@"com.apple.MobileAddressBook", @"com.apple.mobilenotes"] containsObject:bid];
            if (!cached) {
                BOOL (*sdk)(unsigned long long) = (BOOL (*)(unsigned long long))dlsym(RTLD_DEFAULT, "_dyld_program_sdk_at_least");
                BOOL linkedNew = sdk ? sdk(0x0010000000000002ULL) : YES;
                cached = [@[@"com.tinyspeck.chatlyio", @"com.hammerandchisel.discord", @"com.apple.Pages", @"com.apple.Numbers", @"com.apple.Keynote"] containsObject:bid];
                if (cached && linkedNew) { cached = NO; NSLog(@"Warning - Keyboard frames in keyboard notifications are in UIScreen coordinates"); }
            }
        }
        if (cached) {
            id n = (pc && [pc respondsToSelector:vf]) ? ((id (*)(id, SEL, id))objc_msgSend)(pc, vf, @"AlwaysNotConvertToSceneCoordinates") : nil;
            if ([n respondsToSelector:@selector(boolValue)] && [n boolValue]) cached = NO;
        }
    });
    return cached;
}
static BOOL uik_needsConvert_body(id self, SEL _cmd) {                                          // 0x189abed7c
    if (!UIK_K2Cached()) return NO;
    id d = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIKeyboardSceneDelegate"), "activeKeyboardSceneDelegate");
    id vm = UIK_SEND(id (*)(id, SEL), d, "visualModeManager");
    return vm && UIK_SEND(BOOL (*)(id, SEL), vm, "windowingModeEnabled");
}
static BOOL uik_needsConvert(id self, SEL _cmd) {
    @try { return uik_needsConvert_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_needsConvert", e_); return 0; }
}

static id uik_convertUserInfoK2_body(id self, SEL _cmd, id info) {                               // 0x189abefa4 (the 16.0 conversion towards the controller's own window scene)
    id win = UIK_SEND(id (*)(id, SEL), self, "_window");
    id scene = UIK_SEND(id (*)(id, SEL), win, "windowScene");
    return UIK_SEND(id (*)(id, SEL, id, id), self, "convertUserInfo:toWindowScene:", info, scene);
}
static id uik_convertUserInfoK2(id self, SEL _cmd, id info) {
    @try { return uik_convertUserInfoK2_body(self, _cmd, info); }
    @catch (NSException *e_) { uik_exc("uik_convertUserInfoK2", e_); return nil; }
}

static void uik_postNotification_body(id self, SEL _cmd, NSString *name, id info) {              // 0x189abf33c
    id view = UIK_SEND(id (*)(id, SEL), self, "view");
    id win = UIK_SEND(id (*)(id, SEL), view, "window");
    id screen = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), win, "windowScene"), "screen");
    if (!screen) screen = UIK_SEND(id (*)(id, SEL), win, "screen");
    id out = info;
    if (uik_needsConvert(self, 0)) out = UIK_SEND(id (*)(id, SEL, id), self, "convertUserInfo:", info);
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:screen userInfo:out];
}
static void uik_postNotification(id self, SEL _cmd, NSString *name, id info) {
    @try { uik_postNotification_body(self, _cmd, name, info); }
    @catch (NSException *e_) { uik_exc("uik_postNotification", e_);  }
}

static void uik_postCorresp_body(id self, SEL _cmd, NSString *name, id info) {
    if (!UIK_On(UIK_SW_KEYBOARD)) { ((void (*)(id, SEL, id, id))orig_postCorrespK2)(self, _cmd, name, info); return; }
    BOOL conv = uik_needsConvert(self, 0);
    static BOOL seen[2];
    if (!seen[conv]) {
        seen[conv] = YES;
        id fv = [info isKindOfClass:[NSDictionary class]] ? info[UIKeyboardFrameEndUserInfoKey] : nil;
        NSString *fs = [fv respondsToSelector:@selector(CGRectValue)] ? NSStringFromCGRect([fv CGRectValue]) : @"-";
        UIK_Problem(conv ? "k2-converted" : "k2-screen", "K2 keyboard notification %s: frames %s (bundle %s, windowing mode %d, end frame %s)", name.UTF8String, conv ? "converted to the scene (16.2 allowlist)" : "left in UIScreen coordinates (16.2)",
            [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?", (int)uik_needsConvert(self, 0),
            fs.UTF8String);
    }
    if (!conv) return;                                                                      // the caller's plain post is the only 16.2 notification
    uik_postNotification(self, _cmd, name, info);
    tK2Suppress = name;                                                                     // ... and the plain post that follows is not a 16.2 notification
}
static void uik_postCorresp(id self, SEL _cmd, NSString *name, id info) {
    @try { uik_postCorresp_body(self, _cmd, name, info); }
    @catch (NSException *e_) { uik_exc("uik_postCorresp", e_); if (orig_postCorrespK2) { ((void (*)(id, SEL, NSString *, id))(uik_fn)orig_postCorrespK2)(self, _cmd, name, info); }  }
}

static void uik_ncPost_body(id self, SEL _cmd, NSString *name, id object, id info) {
    NSString *s = tK2Suppress;
    if (s && name && (s == name || [s isEqualToString:name])) { tK2Suppress = nil; return; }
    ((void (*)(id, SEL, id, id, id))orig_ncPostK2)(self, _cmd, name, object, info);
}
static void uik_ncPost(id self, SEL _cmd, NSString *name, id object, id info) {
    @try { uik_ncPost_body(self, _cmd, name, object, info); }
    @catch (NSException *e_) { uik_exc("uik_ncPost", e_); if (orig_ncPostK2) { ((void (*)(id, SEL, NSString *, id, id))(uik_fn)orig_ncPostK2)(self, _cmd, name, object, info); }  }
}

// K2 is WITHDRAWN until proven (coordinator order after a device report: with K2 the UI no longer shifts for the keyboard in a full screen app either).  Decode so far: 16.0
// -postToCorrespondingWindowSceneWithNotification:userInfo: (0x18997ecc8) posts one extra notification per name BEFORE the caller's plain [nc post...object:screen] : object = nil, userInfo converted to the
// scene when (linked >= 16.0 SDK && windowing mode && !useVisualModeWindowed && scene.screen == keyboard window screen), else the unconverted info (object nil).  16.2 posts exactly ONE
// (-postNotificationName:userInfo: object = screen).  Full screen apps evidently depend on the 16.0 extra notification; the K2 port dropped it.  The K2 code stays compiled but is not installed (UIK_K2_PROVEN 0).
#define UIK_K2_PROVEN 0
static void UIK_InstallK2(void) {
    if (!UIK_K2_PROVEN) { UIK_Log("K2 not installed: withdrawn until the full screen keyboard behaviour is proven (16.0 behaviour kept)"); return; }
    NSMutableArray *missing = [NSMutableArray array];
    Class iwc = objc_getClass("UIInputWindowController"), ksd = objc_getClass("UIKeyboardSceneDelegate"), nc = objc_getClass("NSNotificationCenter");
    if (!iwc) [missing addObject:@"class UIInputWindowController"];
    else {
        const char *n[] = { "postToCorrespondingWindowSceneWithNotification:userInfo:", "convertUserInfo:toWindowScene:", "_window", "view" };
        for (size_t i = 0; i < sizeof n / sizeof *n; i++) if (!class_getInstanceMethod(iwc, sel_registerName(n[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIInputWindowController %s]", n[i]]];
    }
    if (!ksd || !class_getClassMethod(ksd, sel_registerName("activeKeyboardSceneDelegate"))) [missing addObject:@"+[UIKeyboardSceneDelegate activeKeyboardSceneDelegate]"];
    if (!nc || !class_getInstanceMethod(nc, sel_registerName("postNotificationName:object:userInfo:"))) [missing addObject:@"-[NSNotificationCenter postNotificationName:object:userInfo:]"];
    if ([missing count]) { UIK_Problem("k2-install", "K2 NOT installed (build 20A8372), needs: %s", [[missing componentsJoinedByString:@", "] UTF8String]); return; }
    class_addMethod(iwc, sel_registerName("needsConvertToSceneCoordinates"), (IMP)uik_needsConvert, "B16@0:8");
    class_addMethod(iwc, sel_registerName("convertUserInfo:"), (IMP)uik_convertUserInfoK2, "@24@0:8@16");
    class_addMethod(iwc, sel_registerName("postNotificationName:userInfo:"), (IMP)uik_postNotification, "v32@0:8@16@24");
    UIK_Hook("UIInputWindowController", "postToCorrespondingWindowSceneWithNotification:userInfo:", NULL, (IMP)uik_postCorresp, &orig_postCorrespK2);
    UIK_Hook("NSNotificationCenter", "postNotificationName:object:userInfo:", NULL, (IMP)uik_ncPost, &orig_ncPostK2);
    UIK_Log("K2 installed");
}

// ---- always-on ring of the last 30 keyboard notification frames (K3 conversions and K4 answers, every one, NOT deduped by rounded values), written when a hide ends
// Entry: time, kind (K4 = notificationsFrame answer at a notification site, K3 = convertRect to screen space), the UIKit code range index of the caller (K4), the 16.0 answer (old) / the input rect (K3), the
// result, the keyboard view frame (placeheldView.superview.frame, screen coordinates), hostView.frame, the host window frame, the container frame, placement visible, windowing mode.  A hide that ends
// (didEndTransition with an invisible placement or an empty frame) flushes the ring as "K4RING" lines (at most once per 2 s): the whole sequence of show, bar-only and hide of the phase.
typedef struct { double t; int kind; int site; CGRect a, b, kb, host, win, cont; int vis; int wm; } UIKRingE;
static UIKRingE gUIKRing[30];
static int gUIKRingN;
static os_unfair_lock gUIKRingLock = OS_UNFAIR_LOCK_INIT;
static double UIK_Now(void) { struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); return (double)ts.tv_sec + ts.tv_nsec / 1e9; }
static void UIK_RingAdd(UIKRingE e) {
    os_unfair_lock_lock(&gUIKRingLock);
    gUIKRing[gUIKRingN % 30] = e; gUIKRingN++;
    os_unfair_lock_unlock(&gUIKRingLock);
}
static void UIK_RingFlush(const char *why) {
    static double last;
    double now = UIK_Now();
    if (now - last < 2.0) return;
    last = now;
    UIKRingE copy[30]; int n;
    os_unfair_lock_lock(&gUIKRingLock);
    n = gUIKRingN < 30 ? gUIKRingN : 30;
    for (int i = 0; i < n; i++) copy[i] = gUIKRing[(gUIKRingN - n + i) % 30];
    os_unfair_lock_unlock(&gUIKRingLock);
    UIK_Problem_NoDedupe("K4RING begin (%s): last %d keyboard frames, oldest first (build 20A8372)", why, n);
    for (int i = 0; i < n; i++) {
        UIKRingE *e = &copy[i];
        UIK_Problem_NoDedupe("K4RING %d %+.3fs %s site %d | %s %s -> %s | keyboard view (screen) %s | hostView %s | window %s | container %s | placement visible %d windowing %d",
            i, e->t - now, e->kind ? "K3" : "K4", e->site, e->kind ? "in" : "16.0 answer", NSStringFromCGRect(e->a).UTF8String, NSStringFromCGRect(e->b).UTF8String,
            NSStringFromCGRect(e->kb).UTF8String, NSStringFromCGRect(e->host).UTF8String, NSStringFromCGRect(e->win).UTF8String, NSStringFromCGRect(e->cont).UTF8String, e->vis, e->wm);
    }
    UIK_Problem_NoDedupe("K4RING end");
}

// ---------------------------------------------------------------- K3: keyboard frame of a Stage Manager WINDOW in real UIScreen coordinates (16.2 -[UIInputWindowController convertRectFromContainerCoordinateSpaceToScreenSpace:])
//
// Source of every UIKeyboard*UserInfoKey frame (generateNotificationsForStart: / the post*Notifications paths).  16.0 0x189131f50: r = [view convertRect:r toView:nil]; r = [_window convertRect:r toWindow:nil]; then,
// only when windowing mode is OFF on an iPad app, an actualSceneFrame adjustment of text effects windows.  With Stage Manager on, an app window that is not at the screen origin therefore got a frame
// that is NOT in screen coordinates; an app converting it from the screen to its window (Reynard, Telegram) finds no overlap and does not move its UI (full screen: window == screen, no error).
// 16.2 0x189267db0: r = [view convertRect:r toView:nil]; then  SpringBoard                                  -> [_window convertRect:r toWindow:nil]
//                                                            windowing mode off && text effects window && hosted in another process -> the same
//                                                            everything else (every app with windowing mode on)  -> [_window.windowScene.coordinateSpace convertRect:r toCoordinateSpace:_window.screen.coordinateSpace]
static IMP orig_cr3;
static CGRect uik_convertRectK3_body(id self, SEL _cmd, CGRect r) {
    if (!UIK_On(UIK_SW_KBFRAME)) return ((CGRect (*)(id, SEL, CGRect))orig_cr3)(self, _cmd, r);
    id view = UIK_SEND(id (*)(id, SEL), self, "view");
    CGRect in = r;
    r = UIK_SEND(CGRect (*)(id, SEL, CGRect, id), view, "convertRect:toView:", r, nil);
    BOOL viaWindow = NO;
    if ([(id)[UIApplication sharedApplication] respondsToSelector:sel_registerName("_isSpringBoard")] && UIK_SEND(BOOL (*)(id, SEL), [UIApplication sharedApplication], "_isSpringBoard")) viaWindow = YES;
    else {
        id d = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIKeyboardSceneDelegate"), "activeKeyboardSceneDelegate");
        id vm = UIK_SEND(id (*)(id, SEL), d, "visualModeManager");
        BOOL wm = vm && UIK_SEND(BOOL (*)(id, SEL), vm, "windowingModeEnabled");
        if (!wm) {
            id w = UIK_SEND(id (*)(id, SEL), self, "_window");
            if (UIK_SEND(BOOL (*)(id, SEL), w, "_isTextEffectsWindow") && UIK_SEND(BOOL (*)(id, SEL), w, "_isHostedInAnotherProcess")) viaWindow = YES;
        }
    }
    id win = UIK_SEND(id (*)(id, SEL), self, "_window");
    if (viaWindow) r = UIK_SEND(CGRect (*)(id, SEL, CGRect, id), win, "convertRect:toWindow:", r, nil);
    else {
        id sp = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), win, "windowScene"), "coordinateSpace");
        id tp = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), win, "screen"), "coordinateSpace");
        r = UIK_SEND(CGRect (*)(id, SEL, CGRect, id), sp, "convertRect:toCoordinateSpace:", r, tp);
    }
    @try {
        UIKRingE e3; memset(&e3, 0, sizeof e3);
        e3.t = UIK_Now(); e3.kind = 1; e3.site = viaWindow ? 1 : 0; e3.a = in; e3.b = r;
        e3.win = win ? UIK_SEND(CGRect (*)(id, SEL), win, "frame") : CGRectZero;
        e3.vis = -1; e3.wm = -1;
        UIK_RingAdd(e3);
    } @catch (NSException *e_) { uik_exc("K3Ring", e_); }
    static int n;
    if (n < 3 && !CGRectEqualToRect(r, in) && !viaWindow) {
        n++;
        UIK_Problem("k3-frame", "K3 keyboard frame converted to UIScreen coordinates as 16.2 (build 20A8372 converted it with convertRect:toWindow:nil): %s -> %s (bundle %s)", NSStringFromCGRect(in).UTF8String, NSStringFromCGRect(r).UTF8String, [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
    }
    return r;
}
static CGRect uik_convertRectK3(id self, SEL _cmd, CGRect r) {
    @try { return uik_convertRectK3_body(self, _cmd, r); }
    @catch (NSException *e_) { uik_exc("uik_convertRectK3", e_); if (orig_cr3) { return ((CGRect (*)(id, SEL, CGRect))(uik_fn)orig_cr3)(self, _cmd, r); } return CGRectZero; }
}

static void UIK_InstallK3(void) {
    Class iwc = objc_getClass("UIInputWindowController");
    const char *n[] = { "convertRectFromContainerCoordinateSpaceToScreenSpace:", "_window", "view" };
    NSMutableArray *missing = [NSMutableArray array];
    if (!iwc) [missing addObject:@"class UIInputWindowController"];
    else for (size_t i = 0; i < sizeof n / sizeof *n; i++) if (!class_getInstanceMethod(iwc, sel_registerName(n[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIInputWindowController %s]", n[i]]];
    if (![UIApplication instancesRespondToSelector:sel_registerName("_isSpringBoard")]) [missing addObject:@"-[UIApplication _isSpringBoard]"];
    if (![UIWindow instancesRespondToSelector:sel_registerName("_isHostedInAnotherProcess")]) [missing addObject:@"-[UIWindow _isHostedInAnotherProcess]"];
    if ([missing count]) { UIK_Problem("k3-install", "K3 NOT installed (build 20A8372), needs: %s", [[missing componentsJoinedByString:@", "] UTF8String]); return; }
    UIK_Hook("UIInputWindowController", "convertRectFromContainerCoordinateSpaceToScreenSpace:", NULL, (IMP)uik_convertRectK3, &orig_cr3);
    UIK_Log("K3 installed");
}

// ---------------------------------------------------------------- K4: the frame of the keyboard notifications is the REAL keyboard view (16.2 -[UIInputWindowControllerHostingItem notificationsFrame] 0x189ac79e4)
//
// 16.0 gives every notification path (generateNotificationsForStart:, its block, didEndTransitionWithController:, the viewDidLayoutSubviews / moveFromPlacement: blocks, _visibleFrame, prepareKeyboardHeightChange...,
// constructNotificationInfoForScrollWithMode:, completeTransition block, camera presentation, postTransitionEndNotification, willRotate block, _forcePreLayoutHostViewFrame, viewWillLayoutSubviews)
// -[HostingItem visibleFrame] = hostView.frame: the app side input container, which in a Stage Manager window lies BELOW the window (Telegram {0,1042,786,212} for a 786x1042 window: the keyboard is reported under the
// window, no overlap).  16.2 calls -notificationsFrame at every one of those sites (the only remaining visibleFrame callers are -[UIInputWindowControllerHosting visibleFrame] and notificationsFrame itself):
//   windowing mode off -> visibleFrame;  on -> -fullScreenFrame (0x189ac7ba0): placement invisible -> CGRectZero; floating keyboard / floating assistant without accessory -> applicator popoverFrame;
//   input view not a placeholder or an accessory view exists -> hostView.frame; else the frame of placeheldView.superview (the view of the hosted system keyboard scene) converted FROM its screen coordinate space
//   INTO the coordinate space of the host window's scene, repaired when it misses hostView.frame (y := hostView.origin.y, else hostView.frame) or lies below the container (y += height when it meets the container);
//   then, only for a text effects notification owner window hosted in another process, hostView.frame when the result meets it.
// Port: -visibleFrame of the item is replaced; calls made from the 16.0 code ranges of the notification sites (fixed addresses from the anchor -[UIInputWindowController didEndTransitionWithController:]
// 0x18997e324, every range start checked for pacibsp) answer notificationsFrame, every other caller keeps the 16.0 answer; -notificationsFrame and -fullScreenFrame are added.  Switch uik_kbframe.
static IMP orig_vfK4;
static uintptr_t gK4Slide;
static BOOL gK4Ok;
static const uintptr_t kK4R[][2] = { {0x189086038,0x1890860d0}, {0x189288b08,0x189288b84}, {0x18997e324,0x18997e470}, {0x18997efa0,0x18997f014}, {0x18997f088,0x18997f4a8}, {0x18997f4a8,0x18997f598}, {0x18997f6d0,0x18997f7f0},
    {0x18997fc78,0x18997fdb8}, {0x1899805c0,0x189980790}, {0x18998170c,0x1899817e0}, {0x18998306c,0x1899831a4}, {0x1899831a4,0x1899832f4}, {0x1899832f4,0x189983394}, {0x1899840a0,0x1899841e4}, {0x189984824,0x189984978},
    {0x18998788c,0x1899879b4}, {0x189988b0c,0x189988bc8}, {0x189c612b8,0x189c614e4} };
// every send of the K4 port is answered only when the receiver implements the selector: a selector that exists in 16.2 but not in the app's 16.0 UIKit must not raise doesNotRecognizeSelector
// inside the app (Reynard 20:12:05 crashed in -[UIInputWindowController viewWillLayoutSubviews] through an unguarded send); a miss answers nil / NO / CGRectZero and is logged once as ANOMALY k4-missing
static BOOL K4_Can(id o, const char *s) {
    SEL sel = sel_registerName(s);
    if (o && [o respondsToSelector:sel]) return YES;
    if (o) {
        static NSMutableSet *seen;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
        NSString *key = [NSString stringWithFormat:@"%s %s", object_getClassName(o), s];
        @synchronized (seen) {
            if (![seen containsObject:key]) { [seen addObject:key]; UIK_Problem("k4-missing", "K4 selector %s is not implemented by %s (build 20A8372): nil / NO / zero answered", s, object_getClassName(o)); }
        }
    }
    return NO;
}
static id K4_O(id o, const char *s) { return K4_Can(o, s) ? ((id (*)(id, SEL))objc_msgSend)(o, sel_registerName(s)) : nil; }
static BOOL K4_B(id o, const char *s) { return K4_Can(o, s) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, sel_registerName(s)) : NO; }
static CGRect K4_R(id o, const char *s) { return K4_Can(o, s) ? ((CGRect (*)(id, SEL))objc_msgSend)(o, sel_registerName(s)) : CGRectZero; }
// ---- K4 accessory case (documented deviation, switch uik_k4acc, default ON): an input accessory view (Telegram's input bar) AND the keyboard
// 16.2 answers hostView.frame here: in 16.2 the keyboard lives inside the host view, so that frame IS the whole input area.  In 16.0 the keyboard stays in a separate hosted window and hostView.frame is only the accessory
// (device Telegram: {0,779,786,80.5} while the keyboard covers {0,698.5,786,340} in the window: the app shifted by ~80 instead of ~161).  The union of the accessory frame and the REAL keyboard rectangle (the hosted keyboard
// view's frame, converted into the host window's scene exactly like the placeholder branch) is answered while the keyboard is really on screen; the accessory alone when it is hidden, minimised, or only the bar is shown.
// "Really on screen": placement visible (checked by the caller), _UIKeyboardAutomaticIsOnScreen(), [UIKeyboardImpl activeInstance] not minimised, the hosted keyboard view and its window not hidden / transparent with a non empty frame.
static BOOL K4_KeyboardShown(id sv) {
    if (!sv) return NO;
    BOOL (*onScreen)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "UIKeyboardAutomaticIsOnScreen");
    if (onScreen && !onScreen()) return NO;
    id ki = UIK_ClsId(gKImpl, sActiveInstance);
    if (ki && UIK_B(ki, sIsMinimized)) return NO;
    id w = K4_O(sv, "window");
    if (!w || K4_B(w, "isHidden") || K4_B(sv, "isHidden")) return NO;
    if (K4_Can(w, "alpha") && UIK_SEND(double (*)(id, SEL), w, "alpha") < 0.01) return NO;
    if (K4_Can(sv, "alpha") && UIK_SEND(double (*)(id, SEL), sv, "alpha") < 0.01) return NO;
    CGRect f = K4_R(sv, "frame");
    return f.size.height > 0 && f.size.width > 0;
}
static CGRect K4_AccessoryFrame(id self, id host) {
    CGRect acc = K4_R(host, "frame");
    if (!UIK_On(UIK_SW_K4ACC)) return acc;
    id ph = K4_O(K4_O(K4_O(self, "inputViewSet"), "inputView"), "placeheldView");
    id sv = K4_O(ph, "superview");
    if (!K4_KeyboardShown(sv)) return acc;
    id space = K4_O(K4_O(K4_O(host, "window"), "windowScene"), "coordinateSpace");
    id sspace = K4_O(K4_O(K4_O(sv, "window"), "screen"), "coordinateSpace");
    if (!K4_Can(space, "convertRect:fromCoordinateSpace:") || !sspace) return acc;
    CGRect kb = UIK_SEND(CGRect (*)(id, SEL, CGRect, id), space, "convertRect:fromCoordinateSpace:", K4_R(sv, "frame"), sspace);
    if (CGRectIsEmpty(kb) || CGRectIsNull(kb)) return acc;
    CGRect u = CGRectUnion(acc, kb);
    UIK_Problem("k4-accessory", "K4 accessory case: input accessory frame %s, keyboard %s (hosted keyboard view converted into the host scene) -> answered the union %s (16.2 puts the keyboard into the host view frame; 16.0 keeps it in a separate window) (build 20A8372)",
        NSStringFromCGRect(acc).UTF8String, NSStringFromCGRect(kb).UTF8String, NSStringFromCGRect(u).UTF8String);
    return u;
}
static CGRect uik_fullScreenFrameK4_body(id self, SEL _cmd) {                                      // 0x189ac7ba0
    id p = K4_O(self, "placement");
    if (p && !K4_B(p, "isVisible")) return CGRectZero;
    BOOL popover = NO;
    if (UIK_SEND(BOOL (*)(id, SEL), (id)objc_getClass("UIKeyboardImpl"), "isFloating")) popover = YES;
    else if (K4_B(p, "isFloatingAssistantView") && !K4_O(K4_O(self, "inputViewSet"), "inputAccessoryView")) popover = YES;
    if (popover) return K4_R(K4_O(self, "applicator"), "popoverFrame");
    id host = K4_O(self, "hostView");
    id ivs = K4_O(self, "inputViewSet");
    if (!K4_B(ivs, "isInputViewPlaceholder")) return K4_R(host, "frame");
    if (K4_O(K4_O(self, "inputViewSet"), "inputAccessoryView")) return K4_AccessoryFrame(self, host);
    id ph = K4_O(K4_O(K4_O(self, "inputViewSet"), "inputView"), "placeheldView");
    id sv = K4_O(ph, "superview");
    if (!sv) return K4_R(host, "frame");
    id sv2 = K4_O(ph, "superview");
    id space = K4_O(K4_O(K4_O(host, "window"), "windowScene"), "coordinateSpace");
    CGRect f = K4_R(sv2, "frame");
    id sspace = K4_O(K4_O(K4_O(sv2, "window"), "screen"), "coordinateSpace");
    CGRect r = K4_Can(space, "convertRect:fromCoordinateSpace:") ? UIK_SEND(CGRect (*)(id, SEL, CGRect, id), space, "convertRect:fromCoordinateSpace:", f, sspace) : f;
    CGRect hf = K4_R(K4_O(self, "hostView"), "frame");
    if (CGRectIsEmpty(CGRectIntersection(r, hf))) {
        id h2 = K4_O(self, "hostView");
        CGPoint o = K4_Can(h2, "origin") ? UIK_SEND(CGPoint (*)(id, SEL), h2, "origin") : K4_R(h2, "frame").origin;      // 16.2 UIView(Geometry) origin = frame origin
        r.origin.y = o.y;
        if (CGRectIsEmpty(CGRectIntersection(r, K4_R(K4_O(self, "hostView"), "frame")))) return K4_R(K4_O(self, "hostView"), "frame");
        return r;
    }
    CGFloat hy = K4_R(K4_O(self, "hostView"), "frame").origin.y;
    CGRect cf = K4_R(K4_O(self, "containerView"), "frame");
    if (hy >= CGRectGetMaxY(cf)) {
        if (CGRectIntersectsRect(K4_R(K4_O(self, "containerView"), "frame"), r)) r.origin.y = r.origin.y + r.size.height;
    }
    return r;
}
static CGRect uik_fullScreenFrameK4(id self, SEL _cmd) {
    @try { return uik_fullScreenFrameK4_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_fullScreenFrameK4", e_); return CGRectZero; }
}

static CGRect uik_notificationsFrameK4_body(id self, SEL _cmd) {                                   // 0x189ac79e4
    id d = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIKeyboardSceneDelegate"), "activeKeyboardSceneDelegate");
    id vm = d ? K4_O(d, "visualModeManager") : nil;
    if (!(vm && K4_B(vm, "windowingModeEnabled"))) return ((CGRect (*)(id, SEL))orig_vfK4)(self, sel_registerName("visibleFrame"));
    CGRect r = uik_fullScreenFrameK4(self, 0);
    id w = K4_O(K4_O(self, "hostView"), "window");
    if (!K4_B(w, "_isHostedInAnotherProcess")) return r;
    if (!K4_B(K4_O(K4_O(self, "hostView"), "window"), "_isTextEffectsWindowNotificationOwner")) return r;
    CGRect hf = K4_R(K4_O(self, "hostView"), "frame");
    if (CGRectIsEmpty(CGRectIntersection(r, hf))) return r;
    return K4_R(K4_O(self, "hostView"), "frame");
}
static CGRect uik_notificationsFrameK4(id self, SEL _cmd) {
    @try { return uik_notificationsFrameK4_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_notificationsFrameK4", e_); return CGRectZero; }
}

static UIKRingE K4_RingEntry(id self, int site, CGRect old, CGRect nf) {
    UIKRingE e; memset(&e, 0, sizeof e);
    e.t = UIK_Now(); e.kind = 0; e.site = site; e.a = old; e.b = nf;
    id host = K4_O(self, "hostView");
    id ph = K4_O(K4_O(K4_O(self, "inputViewSet"), "inputView"), "placeheldView");
    id sv = K4_O(ph, "superview");
    e.kb = sv ? K4_R(sv, "frame") : CGRectZero;
    e.host = K4_R(host, "frame");
    e.win = K4_R(K4_O(host, "window"), "frame");
    e.cont = K4_R(K4_O(self, "containerView"), "frame");
    id p = K4_O(self, "placement");
    e.vis = p ? K4_B(p, "isVisible") : -1;
    id d = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIKeyboardSceneDelegate"), "activeKeyboardSceneDelegate");
    id vm = d ? K4_O(d, "visualModeManager") : nil;
    e.wm = vm ? K4_B(vm, "windowingModeEnabled") : -1;
    return e;
}
static void K4_Diag(id self, CGRect old, CGRect nf) {
    id host = K4_O(self, "hostView");
    id win = K4_O(host, "window");
    id scene = K4_O(win, "windowScene");
    id space = K4_O(scene, "coordinateSpace");
    id ph = K4_O(K4_O(K4_O(self, "inputViewSet"), "inputView"), "placeheldView");
    id sv = K4_O(ph, "superview");
    id sw = K4_O(sv, "window");
    id screen = K4_O(sw, "screen");
    CGRect svf = sv ? K4_R(sv, "frame") : CGRectZero;
    CGRect cont = K4_R(K4_O(self, "containerView"), "frame");
    CGRect svwin = sw ? K4_R(sw, "frame") : CGRectZero;
    CGRect sceneB = space ? UIK_SEND(CGRect (*)(id, SEL), space, "bounds") : CGRectZero;
    CGRect screenB = screen ? UIK_SEND(CGRect (*)(id, SEL), K4_O(screen, "coordinateSpace"), "bounds") : CGRectZero;
    CGRect winF = win ? K4_R(win, "frame") : CGRectZero;
    CGRect hostF = K4_R(host, "frame");
    CGRect conv = sv ? UIK_SEND(CGRect (*)(id, SEL, CGRect, id), space, "convertRect:fromCoordinateSpace:", svf, K4_O(screen, "coordinateSpace")) : CGRectZero;
    char key_[64]; snprintf(key_, sizeof key_, "k4s%ld_%ld_%ld_%ld", (long)(svf.origin.y / 8), (long)(svf.size.height / 8), (long)(hostF.origin.y / 8), (long)(winF.size.height / 8));
    UIK_Problem(key_, "K4 input: hostView %s old %s -> result %s | placeheld superview frame %s (its window frame %s, screen bounds %s) converted into the host scene %s | host window frame %s, scene bounds %s, container frame %s (build 20A8372)",
        NSStringFromCGRect(hostF).UTF8String, NSStringFromCGRect(old).UTF8String, NSStringFromCGRect(nf).UTF8String, NSStringFromCGRect(svf).UTF8String, NSStringFromCGRect(svwin).UTF8String, NSStringFromCGRect(screenB).UTF8String,
        NSStringFromCGRect(conv).UTF8String, NSStringFromCGRect(winF).UTF8String, NSStringFromCGRect(sceneB).UTF8String, NSStringFromCGRect(cont).UTF8String);
}

// ---- K4 hide fix (documented deviation, switch uik_hidefix, default ON): the stuck shift after a keyboard hide / minimise
// The app moves its UI by the overlap of the LAST keyboard end frame it received.  When the keyboard hides (or shrinks to the assistant bar) and the last end frame it was told still overlaps the app window,
// the UI stays shifted by that overlap (device: Telegram in a window, chat ~50-58 pt too high, the assistant bar height).  The hide transition ends in -[UIInputWindowController didEndTransitionWithController:]
// (K4 site 2): when the placement is then invisible (or the frame empty) and the last end frame posted by UIKit (observed: UIKeyboardWillShow / WillChangeFrame / WillHide / DidShow / DidChangeFrame / DidHide,
// the userInfo END frame, screen coordinates) intersects the host window in screen coordinates, ONE correcting UIKeyboardWillHideNotification + DidHideNotification is posted: begin = the last end frame, end = a
// zero height rect at the screen bottom edge, same userInfo shape as the stock hide (frames, centers, duration 0.25, curve 7, local), same object as the stock posts.  Never when the last end frame had no
// overlap (the normal case), never twice for one hide (the correction itself becomes the last end frame).
static CGRect gHFLastEnd;
static id gHFLastObj;
static BOOL gHFHave;
static BOOL gHFPosting;
static void UIK_HideFixObserve(NSNotification *n) {
    if (gHFPosting) return;
    NSValue *v = n.userInfo[@"UIKeyboardFrameEndUserInfoKey"];
    if (![v isKindOfClass:[NSValue class]]) return;
    gHFLastEnd = [v CGRectValue]; gHFLastObj = n.object; gHFHave = YES;
}
static void UIK_HideFixInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *names = @[@"UIKeyboardWillShowNotification", @"UIKeyboardDidShowNotification", @"UIKeyboardWillHideNotification", @"UIKeyboardDidHideNotification", @"UIKeyboardWillChangeFrameNotification", @"UIKeyboardDidChangeFrameNotification"];
        for (NSString *nm in names) [[NSNotificationCenter defaultCenter] addObserverForName:nm object:nil queue:nil usingBlock:^(NSNotification *n) { @try { UIK_HideFixObserve(n); } @catch (NSException *e_) { uik_exc("K4HideFixObserve", e_); } }];
    });
}
static void UIK_HideFix(id item) {
    if (!UIK_On(UIK_SW_HIDEFIX) || !gHFHave) return;
    id host = K4_O(item, "hostView");
    id win = K4_O(host, "window");
    id scene = K4_O(win, "windowScene");
    id sp = K4_O(scene, "coordinateSpace");
    id screen = K4_O(win, "screen");
    id tp = K4_O(screen, "coordinateSpace");
    if (!win || !sp || !tp) return;
    CGRect wb = K4_R(win, "bounds");
    CGRect winScreen = K4_Can(sp, "convertRect:toCoordinateSpace:") ? UIK_SEND(CGRect (*)(id, SEL, CGRect, id), sp, "convertRect:toCoordinateSpace:", wb, tp) : wb;
    CGRect sb = K4_Can(tp, "bounds") ? UIK_SEND(CGRect (*)(id, SEL), tp, "bounds") : CGRectZero;
    CGRect last = gHFLastEnd;
    CGRect ov = CGRectIntersection(last, winScreen);
    if (CGRectIsNull(ov) || ov.size.height < 0.5 || ov.size.width < 0.5 || last.size.height < 0.5 || sb.size.height < 1) return;     // the last end frame did not cover the window: nothing is stuck
    CGRect end = CGRectMake(last.origin.x, CGRectGetMaxY(sb), last.size.width, 0);
    NSValue *bf = [NSValue valueWithCGRect:last], *ef = [NSValue valueWithCGRect:end];
    NSValue *bc = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(last), CGRectGetMidY(last))], *ec = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(end), CGRectGetMidY(end))];
    NSDictionary *info = @{ @"UIKeyboardFrameBeginUserInfoKey": bf, @"UIKeyboardFrameEndUserInfoKey": ef, @"UIKeyboardCenterBeginUserInfoKey": bc, @"UIKeyboardCenterEndUserInfoKey": ec,
        @"UIKeyboardAnimationDurationUserInfoKey": @0.25, @"UIKeyboardAnimationCurveUserInfoKey": @7, @"UIKeyboardIsLocalUserInfoKey": @YES };
    UIK_Problem("k4-hidefix", "K4 hide fix (documented deviation, kill file uik_hidefix): the keyboard hid but the last end frame the app received %s still covered its window %s (overlap %s): posted a correcting UIKeyboardWillHide / DidHide with end frame %s (bundle %s, build 20A8372)",
        NSStringFromCGRect(last).UTF8String, NSStringFromCGRect(winScreen).UTF8String, NSStringFromCGRect(ov).UTF8String, NSStringFromCGRect(end).UTF8String, [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
    id obj = gHFLastObj;
    gHFPosting = YES;
    @try {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIKeyboardWillHideNotification" object:obj userInfo:info];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIKeyboardDidHideNotification" object:obj userInfo:info];
    } @finally { gHFPosting = NO; }
    gHFLastEnd = end; gHFLastObj = obj;
}
// the CALLER of the hooked method is identified by its return address: it must be read in the hook entry (the wrapper below), NOT in this body: once the compiler stops inlining the body into the
// @try wrapper (the body grew with the ring log / hide fix) __builtin_return_address(0) of the body is an address of the wrapper, no K4 range ever matched and K4 silently answered the 16.0 frame
// (device log of the build compiled Nov 21 13:46: no K4 input lines at all in Telegram).
__attribute__((noinline)) static CGRect uik_visibleFrameK4_body(id self, SEL _cmd, uintptr_t rawRa) {
    if (!gK4Ok || !UIK_On(UIK_SW_KBFRAME)) return ((CGRect (*)(id, SEL))orig_vfK4)(self, _cmd);
    uintptr_t ra = rawRa & 0x7fffffffffULL;
    BOOL hit = NO; int hitIdx = -1;
    for (size_t i = 0; i < sizeof kK4R / sizeof *kK4R; i++) if (ra >= kK4R[i][0] + gK4Slide && ra < kK4R[i][1] + gK4Slide) { hit = YES; hitIdx = (int)i; break; }
    CGRect old = ((CGRect (*)(id, SEL))orig_vfK4)(self, _cmd);
    if (!hit) return old;
    CGRect nf = uik_notificationsFrameK4(self, _cmd);
    @try {
        UIKRingE re_ = K4_RingEntry(self, hitIdx, old, nf);
        UIK_RingAdd(re_);
        if (hitIdx == 2 && (re_.vis == 0 || nf.size.height == 0 || re_.host.size.height == 0)) { UIK_HideFix(self); UIK_RingFlush("a hide ended: didEndTransitionWithController: with an invisible placement / empty frame"); }      // site 2 = -[UIInputWindowController didEndTransitionWithController:]
    } @catch (NSException *e_) { uik_exc("K4Ring", e_); }
    static int nd; if (nd < 40) { nd++; K4_Diag(self, old, nf); }
    static int n;
    if (n < 6 && !CGRectEqualToRect(old, nf)) {
        n++;
        UIK_Problem(n == 1 ? "k4-frame-1" : n == 2 ? "k4-frame-2" : n == 3 ? "k4-frame-3" : n == 4 ? "k4-frame-4" : n == 5 ? "k4-frame-5" : "k4-frame-6", "K4 keyboard notification frame is the real keyboard view as 16.2 notificationsFrame (build 20A8372 used hostView.frame): %s -> %s (bundle %s)", NSStringFromCGRect(old).UTF8String, NSStringFromCGRect(nf).UTF8String, [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
    }
    return nf;
}
static CGRect uik_visibleFrameK4(id self, SEL _cmd) {
    uintptr_t rawRa = (uintptr_t)__builtin_return_address(0);
    @try { return uik_visibleFrameK4_body(self, _cmd, rawRa); }
    @catch (NSException *e_) { uik_exc("uik_visibleFrameK4", e_); if (orig_vfK4) { return ((CGRect (*)(id, SEL))(uik_fn)orig_vfK4)(self, _cmd); } return CGRectZero; }
}

static void UIK_InstallK4(void) {
    Class iwc = objc_getClass("UIInputWindowController"), item = objc_getClass("UIInputWindowControllerHostingItem");
    NSMutableArray *missing = [NSMutableArray array];
    if (!item) [missing addObject:@"class UIInputWindowControllerHostingItem"];
    else {
        const char *n[] = { "visibleFrame", "placement", "inputViewSet", "hostView", "containerView", "applicator" };
        for (size_t i = 0; i < sizeof n / sizeof *n; i++) if (!class_getInstanceMethod(item, sel_registerName(n[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIInputWindowControllerHostingItem %s]", n[i]]];
    }
    Method am = iwc ? class_getInstanceMethod(iwc, sel_registerName("didEndTransitionWithController:")) : NULL;
    if (!am) [missing addObject:@"-[UIInputWindowController didEndTransitionWithController:] (address anchor)"];
    if ([missing count]) { UIK_Problem("k4-install", "K4 NOT installed (build 20A8372), needs: %s", [[missing componentsJoinedByString:@", "] UTF8String]); return; }
    uintptr_t anchor = (uintptr_t)method_getImplementation(am) & 0x7fffffffffULL;
    uintptr_t slide = anchor - 0x18997e324;
    for (size_t i = 0; i < sizeof kK4R / sizeof *kK4R; i++) {
        uint32_t w = *(const uint32_t *)(kK4R[i][0] + slide);
        if (w != 0xd503237f) { UIK_Problem("k4-install", "K4 NOT installed (build 20A8372): the code at %#lx is not a function start (word %#x, slide %#lx)", (unsigned long)kK4R[i][0], w, (unsigned long)slide); return; }
    }
    gK4Slide = slide;
    class_addMethod(item, sel_registerName("fullScreenFrame"), (IMP)uik_fullScreenFrameK4, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8");
    class_addMethod(item, sel_registerName("notificationsFrame"), (IMP)uik_notificationsFrameK4, "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8");
    if (!UIK_Hook("UIInputWindowControllerHostingItem", "visibleFrame", NULL, (IMP)uik_visibleFrameK4, &orig_vfK4)) return;
    UIK_HideFixInstall();
    gK4Ok = YES;
    UIK_Log("K4 installed (slide %#lx)", (unsigned long)slide);
}

// ---------------------------------------------------------------- K5: placements of the assistant bar / accessory view of a windowed keyboard (16.2 UIInputViewSetPlacement*)
//
// Device test of K4: Telegram in a window shifted too far up when only the assistant bar (shortcut bar) was visible.  The keyboard rect of the notification is the frame of the placeholder view's superview
// (K4), whose position inside the hosting container comes from the placements.  16.2 changed two of them for the windowed visual mode:
//  * -[UIInputViewSetPlacementAssistantOnScreen subPlacements] 16.0 0x189972e54: when useVisualModeWindowed ALWAYS [AccessoryOnScreen placement] (cached in _cachedSecondaryPlacement) as the single sub placement.
//    16.2 0x189ab2c58 asks [[KSD active] inputViews] and calls the new -subPlacementsForInputViewSet: (AssistantOnScreen 0x189ab2cd0): the sub placement exists only when useVisualModeWindowed AND the input view
//    set has an inputAccessoryView, else nil (base class -subPlacementsForInputViewSet: 0x189ab0e4c = [self subPlacements]).
//  * -[UIInputViewSetPlacementAccessoryOnScreen verticalConstraintForInputViewSet:hostView:containerView:] 16.0 0x1899711bc / 16.2 0x189ab0f18: the item whose bottom / top is pinned to the container bottom is
//    the accessory view, else the input view, else the host view; 16.2 uses the HOST VIEW when [[[[container _rootInputWindowController] placement] subPlacements] firstObject] is this placement.
// Switch uik_kbplace.  (-[UIInputWindowControllerHosting reloadForPlacementForInputViewSet:] 0x189ac6208 passes the new input view set explicitly; the 16.0 reloadForPlacement reads the scene delegate's
// current one through subPlacements: documented difference.)
static IMP orig_aosSubK5, orig_vcK5;
static id uik_aosSubForSetK5_body(id self, SEL _cmd, id ivs) {                                  // 0x189ab2cd0
    id d = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIKeyboardSceneDelegate"), "activeKeyboardSceneDelegate");
    id vm = d ? K4_O(d, "visualModeManager") : nil;
    if (!(vm && K4_B(vm, "useVisualModeWindowed"))) return nil;
    if (!ivs || !K4_O(ivs, "inputAccessoryView")) return nil;
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_cachedSecondaryPlacement");
    id cached = iv ? object_getIvar(self, iv) : nil;
    if (!cached) {
        cached = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIInputViewSetPlacementAccessoryOnScreen"), "placement");
        if (iv) object_setIvar(self, iv, cached);
    }
    return cached ? @[cached] : nil;
}
static id uik_aosSubForSetK5(id self, SEL _cmd, id ivs) {
    @try { return uik_aosSubForSetK5_body(self, _cmd, ivs); }
    @catch (NSException *e_) { uik_exc("uik_aosSubForSetK5", e_); return nil; }
}

static id uik_aosSubK5_body(id self, SEL _cmd) {                                                 // 0x189ab2c58
    if (!UIK_On(UIK_SW_KBPLACE)) return ((id (*)(id, SEL))orig_aosSubK5)(self, _cmd);
    id d = UIK_SEND(id (*)(id, SEL), (id)objc_getClass("UIKeyboardSceneDelegate"), "activeKeyboardSceneDelegate");
    return uik_aosSubForSetK5(self, _cmd, d ? K4_O(d, "inputViews") : nil);
}
static id uik_aosSubK5(id self, SEL _cmd) {
    @try { return uik_aosSubK5_body(self, _cmd); }
    @catch (NSException *e_) { uik_exc("uik_aosSubK5", e_); if (orig_aosSubK5) { return ((id (*)(id, SEL))(uik_fn)orig_aosSubK5)(self, _cmd); } return nil; }
}

static id uik_baseSubForSetK5_body(id self, SEL _cmd, id ivs) { return K4_O(self, "subPlacements"); }
static id uik_baseSubForSetK5(id self, SEL _cmd, id ivs) {
    @try { return uik_baseSubForSetK5_body(self, _cmd, ivs); }
    @catch (NSException *e_) { uik_exc("uik_baseSubForSetK5", e_); return nil; }
}
   // 0x189ab0e4c
static id uik_vcK5_body(id self, SEL _cmd, id ivs, id host, id container) {                      // 0x189ab0f18
    if (!UIK_On(UIK_SW_KBPLACE)) return ((id (*)(id, SEL, id, id, id))orig_vcK5)(self, _cmd, ivs, host, container);
    id root = K4_O(container, "_rootInputWindowController");
    id first = [K4_O(K4_O(root, "placement"), "subPlacements") firstObject];
    id item;
    if (first == self) item = host;
    else {
        item = K4_O(ivs, "inputAccessoryView");
        if (!item) { id iv = K4_O(ivs, "inputView"); item = iv ?: host; }
    }
    if (!item) return nil;
    if (!UIK_SEND(BOOL (*)(id, SEL, id), item, "isDescendantOfView:", container)) return nil;
    BOOL hasAcc = K4_O(ivs, "inputAccessoryView") != nil;
    return UIK_SEND(id (*)(id, SEL, id, long long, long long, id, long long, double, double), (id)objc_getClass("NSLayoutConstraint"), "constraintWithItem:attribute:relatedBy:toItem:attribute:multiplier:constant:", item, hasAcc ? 4 : 3, 0, container, 4, 1.0, 0.0);
}
static id uik_vcK5(id self, SEL _cmd, id ivs, id host, id container) {
    @try { return uik_vcK5_body(self, _cmd, ivs, host, container); }
    @catch (NSException *e_) { uik_exc("uik_vcK5", e_); if (orig_vcK5) { return ((id (*)(id, SEL, id, id, id))(uik_fn)orig_vcK5)(self, _cmd, ivs, host, container); } return nil; }
}

static void UIK_InstallK5(void) {
    Class aos = objc_getClass("UIInputViewSetPlacementAssistantOnScreen"), acc = objc_getClass("UIInputViewSetPlacementAccessoryOnScreen"), base = objc_getClass("UIInputViewSetPlacement");
    NSMutableArray *missing = [NSMutableArray array];
    if (!aos || !class_getInstanceMethod(aos, sel_registerName("subPlacements"))) [missing addObject:@"-[UIInputViewSetPlacementAssistantOnScreen subPlacements]"];
    if (!acc || !class_getInstanceMethod(acc, sel_registerName("verticalConstraintForInputViewSet:hostView:containerView:"))) [missing addObject:@"-[UIInputViewSetPlacementAccessoryOnScreen verticalConstraintForInputViewSet:hostView:containerView:]"];
    if (!base) [missing addObject:@"class UIInputViewSetPlacement"];
    if (aos && !class_getInstanceVariable(aos, "_cachedSecondaryPlacement")) [missing addObject:@"ivar _cachedSecondaryPlacement"];
    if (![UIView instancesRespondToSelector:sel_registerName("_rootInputWindowController")]) [missing addObject:@"-[UIView _rootInputWindowController]"];
    if ([missing count]) { UIK_Problem("k5-install", "K5 NOT installed (build 20A8372), needs: %s", [[missing componentsJoinedByString:@", "] UTF8String]); return; }
    class_addMethod(base, sel_registerName("subPlacementsForInputViewSet:"), (IMP)uik_baseSubForSetK5, "@24@0:8@16");
    class_addMethod(aos, sel_registerName("subPlacementsForInputViewSet:"), (IMP)uik_aosSubForSetK5, "@24@0:8@16");
    BOOL a = UIK_Hook("UIInputViewSetPlacementAssistantOnScreen", "subPlacements", NULL, (IMP)uik_aosSubK5, &orig_aosSubK5);
    BOOL b = UIK_Hook("UIInputViewSetPlacementAccessoryOnScreen", "verticalConstraintForInputViewSet:hostView:containerView:", NULL, (IMP)uik_vcK5, &orig_vcK5);
    UIK_Log("K5 installed (sub placements %d, vertical constraint %d)", (int)a, (int)b);
    if (UIK_On(UIK_SW_KBPLACE)) UIK_Problem("k5-active", "K5 active (build 20A8372): the assistant bar sub placement exists only with an accessory view, accessory constraint as 16.2 (bundle %s)", [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
}

// ---------------------------------------------------------------- K6: UIKit's own keyboard overlap (16.2 UIKeyboardSceneDelegate verticalOverlapForView:usingKeyboardInfo: / visibleFrameInView:)
//
// What UIKit itself uses to move scroll views / text views / layout guides for the keyboard (apart from the notification frame of K4).
// -verticalOverlapForView:usingKeyboardInfo:  16.0 0x189012aa4 -> 16.2 0x189148ce8.  Both: 0 unless _UIKeyboardAutomaticIsOnScreen(), the container root controller is docked, the input views are not split.
//   16.2 adds: 0 when [[inputViews] inputView] is nil; 0 when the container's placement isFloatingAssistantView; 0 when it isFloating; 0 when the view has no _window; (16.0 and 16.2) 0 when the view is a descendant of the
//   input view or the accessory view.  With a notification info: the end frame is converted from the scene's SCREEN coordinate space into the scene coordinate space and then into the view (16.0 and 16.2).  Without info: 16.2
//   takes [containerRootController visibleFrame]; its MinY == 0 means "keyboard frame on top of the screen": 0 (and a fault log, here ANOMALY k6-top, never an exception); else the frame is converted the same way.  Then:
//   empty -> 0, else max(0, MaxY(view.bounds) - MinY(frame)).
// -visibleFrameInView:  16.0 0x1896fa154 -> 16.2 0x189834be0: zero when the container is undocked or the arbiter client says the remote keyboard is undocked; else [container visibleFrame].  16.0 converts it with
//   [view.window convertRect:fromView:nil]; 16.2 (view without window: unconverted) converts it from [[[container _window] screen] coordinateSpace] to [[view.window windowScene] coordinateSpace].
// Switch uik_kboverlap.  ANOMALY k6-overlap / k6-visible (always on, deduped by rounded values): notification end frame, result, frames, per app.
static IMP orig_voK6, orig_vfK6;
static BOOL K6_Rect(CGRect r) { return CGRectIsEmpty(r) || CGRectIsNull(r); }
static double uik_verticalOverlapK6_body(id self, SEL _cmd, id view, id info) {
    BOOL (*onScreen)(void) = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "UIKeyboardAutomaticIsOnScreen");
    if (!onScreen || !onScreen()) return 0;
    id container = UIK_SEND(id (*)(id, SEL), self, "containerRootController");
    if (UIK_SEND(BOOL (*)(id, SEL), container, "isUndocked")) return 0;
    if (UIK_SEND(BOOL (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "inputViews"), "_inputViewIsSplit")) return 0;
    id iv = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "inputViews"), "inputView");
    if (!iv) return 0;
    if (UIK_SEND(BOOL (*)(id, SEL), UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "containerRootController"), "placement"), "isFloatingAssistantView")) return 0;
    if (UIK_SEND(BOOL (*)(id, SEL), UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "containerRootController"), "placement"), "isFloating")) return 0;
    if (!UIK_SEND(id (*)(id, SEL), view, "_window")) return 0;
    id ivNow = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "inputViews"), "inputView");
    if (UIK_SEND(BOOL (*)(id, SEL, id), view, "isDescendantOfView:", ivNow)) return 0;
    id accNow = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "inputViews"), "inputAccessoryView");
    if (UIK_SEND(BOOL (*)(id, SEL, id), view, "isDescendantOfView:", accNow)) return 0;
    CGRect r;
    id scene = UIK_SEND(id (*)(id, SEL), self, "scene");
    id sceneSpace = UIK_SEND(id (*)(id, SEL), scene, "coordinateSpace");
    id screenSpace = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), scene, "screen"), "coordinateSpace");
    BOOL haveInfo = info != nil;
    if (haveInfo) {
        id fv = [info objectForKey:UIKeyboardFrameEndUserInfoKey];
        r = [fv respondsToSelector:@selector(CGRectValue)] ? [fv CGRectValue] : CGRectZero;
    } else {
        r = UIK_SEND(CGRect (*)(id, SEL), container, "visibleFrame");
        if (CGRectGetMinY(r) == 0) { UIK_Problem("k6-top", "K6 verticalOverlapForView:usingKeyboardInfo: without info: the container's visibleFrame is on top of the screen %s (16.2 faults 'Keyboard frame should not be on top of the screen'; build 20A8372): answered 0", NSStringFromCGRect(r).UTF8String); return 0; }
    }
    r = UIK_SEND(CGRect (*)(id, SEL, CGRect, id), sceneSpace, "convertRect:fromCoordinateSpace:", r, screenSpace);
    r = UIK_SEND(CGRect (*)(id, SEL, CGRect, id), sceneSpace, "convertRect:toCoordinateSpace:", r, view);
    if (K6_Rect(r)) return 0;
    CGRect bounds = UIK_SEND(CGRect (*)(id, SEL), view, "bounds");
    double o = CGRectGetMaxY(bounds) - CGRectGetMinY(r);
    return o > 0 ? o : 0;
}
static double uik_verticalOverlapK6(id self, SEL _cmd, id view, id info) {
    double res = 0;
    BOOL ok = NO;
    if (UIK_On(UIK_SW_KBOVERLAP)) {
        @try { res = uik_verticalOverlapK6_body(self, _cmd, view, info); ok = YES; }
        @catch (NSException *e_) { uik_exc("uik_verticalOverlapK6", e_); }
    }
    if (!ok) return orig_voK6 ? ((double (*)(id, SEL, id, id))(uik_fn)orig_voK6)(self, _cmd, view, info) : 0;
    @try {
        id fv = [info isKindOfClass:[NSDictionary class]] ? info[UIKeyboardFrameEndUserInfoKey] : nil;
        CGRect end = [fv respondsToSelector:@selector(CGRectValue)] ? [fv CGRectValue] : CGRectZero;
        CGRect vb = UIK_SEND(CGRect (*)(id, SEL), view, "bounds");
        char key[96]; snprintf(key, sizeof key, "k6o_%ld_%ld_%ld_%ld", (long)(end.origin.y / 8), (long)(end.size.height / 8), (long)(res / 8), (long)(CGRectGetMaxY(vb) / 8));
        UIK_Problem(key, "K6 overlap (build 20A8372): notification end frame %s, verticalOverlap %.1f for a view with bounds %s (bundle %s)", NSStringFromCGRect(end).UTF8String, res, NSStringFromCGRect(vb).UTF8String, [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
    } @catch (NSException *e_) { }
    return res;
}
static CGRect uik_visibleFrameInViewK6_body(id self, SEL _cmd, id view) {
    id container = UIK_SEND(id (*)(id, SEL), self, "containerRootController");
    if (UIK_SEND(BOOL (*)(id, SEL), container, "isUndocked")) return CGRectZero;
    Class ksd = objc_getClass("UIKeyboardSceneDelegate");
    id client = UIK_SEND(id (*)(id, SEL), (id)ksd, "automaticKeyboardArbiterClient");
    id active = UIK_SEND(id (*)(id, SEL), (id)ksd, "activeKeyboardSceneDelegate");
    if (UIK_SEND(BOOL (*)(id, SEL, BOOL), client, "remoteKeyboardUndocked:", active != self)) return CGRectZero;
    CGRect vf = UIK_SEND(CGRect (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "containerRootController"), "visibleFrame");
    id win = UIK_SEND(id (*)(id, SEL), view, "window");
    if (!win) return vf;
    id space1 = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "containerRootController"), "_window"), "screen"), "coordinateSpace");
    id space2 = UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), UIK_SEND(id (*)(id, SEL), view, "window"), "windowScene"), "coordinateSpace");
    return UIK_SEND(CGRect (*)(id, SEL, CGRect, id), space1, "convertRect:toCoordinateSpace:", vf, space2);
}
static CGRect uik_visibleFrameInViewK6(id self, SEL _cmd, id view) {
    CGRect res = CGRectZero;
    BOOL ok = NO;
    if (UIK_On(UIK_SW_KBOVERLAP)) {
        @try { res = uik_visibleFrameInViewK6_body(self, _cmd, view); ok = YES; }
        @catch (NSException *e_) { uik_exc("uik_visibleFrameInViewK6", e_); }
    }
    if (!ok) return orig_vfK6 ? ((CGRect (*)(id, SEL, id))(uik_fn)orig_vfK6)(self, _cmd, view) : CGRectZero;
    @try {
        CGRect raw = UIK_SEND(CGRect (*)(id, SEL), UIK_SEND(id (*)(id, SEL), self, "containerRootController"), "visibleFrame");
        char key[96]; snprintf(key, sizeof key, "k6v_%ld_%ld_%ld_%ld", (long)(res.origin.y / 8), (long)(res.size.height / 8), (long)(raw.origin.y / 8), (long)(raw.size.height / 8));
        UIK_Problem(key, "K6 visibleFrameInView (build 20A8372): container visibleFrame %s -> %s (16.0 convertRect:fromView:nil would give the window relative frame; bundle %s)", NSStringFromCGRect(raw).UTF8String, NSStringFromCGRect(res).UTF8String, [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
    } @catch (NSException *e_) { }
    return res;
}
static void UIK_InstallK6(void) {
    Class ksd = objc_getClass("UIKeyboardSceneDelegate");
    NSMutableArray *missing = [NSMutableArray array];
    if (!ksd) [missing addObject:@"class UIKeyboardSceneDelegate"];
    else {
        const char *n[] = { "verticalOverlapForView:usingKeyboardInfo:", "visibleFrameInView:", "containerRootController", "inputViews", "scene" };
        for (size_t i = 0; i < sizeof n / sizeof *n; i++) if (!class_getInstanceMethod(ksd, sel_registerName(n[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIKeyboardSceneDelegate %s]", n[i]]];
        const char *c[] = { "automaticKeyboardArbiterClient", "activeKeyboardSceneDelegate" };
        for (size_t i = 0; i < sizeof c / sizeof *c; i++) if (!class_getClassMethod(ksd, sel_registerName(c[i]))) [missing addObject:[NSString stringWithFormat:@"+[UIKeyboardSceneDelegate %s]", c[i]]];
    }
    if (!dlsym(RTLD_DEFAULT, "UIKeyboardAutomaticIsOnScreen")) [missing addObject:@"_UIKeyboardAutomaticIsOnScreen"];
    Class iwc = objc_getClass("UIInputWindowController");
    const char *ic[] = { "isUndocked", "placement", "visibleFrame", "_window" };
    for (size_t i = 0; i < sizeof ic / sizeof *ic; i++) if (!iwc || !class_getInstanceMethod(iwc, sel_registerName(ic[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIInputWindowController %s]", ic[i]]];
    Class pl = objc_getClass("UIInputViewSetPlacement");
    const char *pc[] = { "isFloatingAssistantView", "isFloating" };
    for (size_t i = 0; i < sizeof pc / sizeof *pc; i++) if (!pl || !class_getInstanceMethod(pl, sel_registerName(pc[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIInputViewSetPlacement %s]", pc[i]]];
    Class vs = objc_getClass("UIInputViewSet");
    const char *vc[] = { "_inputViewIsSplit", "inputView", "inputAccessoryView" };
    for (size_t i = 0; i < sizeof vc / sizeof *vc; i++) if (!vs || !class_getInstanceMethod(vs, sel_registerName(vc[i]))) [missing addObject:[NSString stringWithFormat:@"-[UIInputViewSet %s]", vc[i]]];
    if ([missing count]) { UIK_Problem("k6-install", "K6 NOT installed (build 20A8372), needs: %s", [[missing componentsJoinedByString:@", "] UTF8String]); return; }
    BOOL a = UIK_Hook("UIKeyboardSceneDelegate", "verticalOverlapForView:usingKeyboardInfo:", NULL, (IMP)uik_verticalOverlapK6, &orig_voK6);
    BOOL b = UIK_Hook("UIKeyboardSceneDelegate", "visibleFrameInView:", NULL, (IMP)uik_visibleFrameInViewK6, &orig_vfK6);
    UIK_Log("K6 installed (verticalOverlap %d, visibleFrameInView %d)", (int)a, (int)b);
    if (UIK_On(UIK_SW_KBOVERLAP)) UIK_Problem("k6-active", "K6 active (build 20A8372): UIKeyboardSceneDelegate verticalOverlapForView:usingKeyboardInfo: and visibleFrameInView: as 16.2 (bundle %s)", [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "?");
}

__attribute__((constructor)) static void UIK_Init(void) {
    if (!UIK_BuildMatches() || !UIK_IsApp()) return;
    Dl_info di;
    if (UIK_Debug() && dladdr((void *)&UIK_Init, &di)) UIK_Log("Backport162UIK loaded, image base %p", di.dli_fbase);
    UIK_InstallU1();
    UIK_InstallK1();
    UIK_InstallU2();
    UIK_InstallK2();
    UIK_InstallK3();
    UIK_InstallK4();
    UIK_InstallK5();
    UIK_InstallK6();
}
