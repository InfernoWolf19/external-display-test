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
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

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
static id UIK_ClsId(Class c, SEL s) { return ((id (*)(id, SEL))objc_msgSend)((id)c, s); }
static BOOL UIK_ClsB(Class c, SEL s) { return ((BOOL (*)(id, SEL))objc_msgSend)((id)c, s); }

// +[UIKeyboardVisualModeManager softwareKeyboardAllowedOnExternalScreen]
static BOOL UIK_ExternalSWKeyboardFlag(void) {
    static BOOL value, done;
    if (!done) {
        id pc = UIK_ClsId(gKPC, sSharedPrefs);
        id v = pc ? ((id (*)(id, SEL, id))objc_msgSend)(pc, sPrefValue, @"ChamoisExternalSWKeyboard") : nil;
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
static BOOL uik_cls_swAllowedExternal(id self, SEL _cmd) { return UIK_ExternalSWKeyboardFlag(); }
static BOOL uik_cls_swAllowedActive(id self, SEL _cmd) { return UIK_SWKeyboardAllowed(); }

// -[UIKeyboardSceneDelegate keyboardScreen] / -textEntryFocusOnExternalDisplay
static id uik_ksd_keyboardScreen(id self, SEL _cmd) { return UIK_Id(UIK_Id(self, sScene), sScreen); }
static BOOL uik_ksd_externalFocus(id self, SEL _cmd) { return !UIK_B(UIK_Id(UIK_Id(self, sScene), sScreen), sIsEmbeddedScreen); }
// -[UIKeyboardSceneDelegate expectedInputViewSetIsCustom]: the responder has an input view controller, or an input view with a positive height
static BOOL uik_ksd_expectCustom(id self, SEL _cmd) {
    if (!gKHaveResponder) return NO;
    id r = UIK_Id(self, sResponder);
    if (UIK_Id(r, sInputVC)) return YES;
    id iv = UIK_Id(r, sInputView);
    if (!iv) return NO;
    CGRect f = ((CGRect (*)(id, SEL))objc_msgSend)(iv, sFrame);
    return f.size.height > 0;
}
// -[UIKeyboardSceneDelegate expectedInputModeIsSpecialized]: [[[UIKeyboardInputModeController sharedInputModeController] currentInputMode] isSpecializedInputMode]
static BOOL uik_ksd_expectSpecialized(id self, SEL _cmd) {
    if (!gKHaveSpecialized) return NO;
    id ctl = UIK_ClsId(objc_getClass("UIKeyboardInputModeController"), sInputModeCtl);
    return UIK_B(UIK_Id(ctl, sCurrentInputMode), sIsSpecialized);
}
// -[UIKeyboardSceneDelegate _windowHostingScene:didMoveFromScreen:toScreen:]
static void uik_ksd_didMove(id self, SEL _cmd, id scene, id from, id to) {
    if (!UIK_On(UIK_SW_KEYBOARD)) return;
    UIK_Log("K1 keyboard scene delegate %p: window hosting scene %p moved from screen %p to screen %p, forceReloadInputViews", (__bridge void *)self, (__bridge void *)scene, (__bridge void *)from, (__bridge void *)to);
    if ([self respondsToSelector:sForceReload]) ((void (*)(id, SEL))objc_msgSend)(self, sForceReload);
}
// -[UIKeyboardVisualModeManager textEntryFocusOnExternalDisplay] / -expectedInputModeIsSpecialized (forward to the delegate, NO without one)
static BOOL uik_vmm_externalFocus(id self, SEL _cmd) { id d = UIK_Id(self, sDelegate); return d ? UIK_B(d, sTextEntryExt) : NO; }
static BOOL uik_vmm_expectSpecialized(id self, SEL _cmd) { id d = UIK_Id(self, sDelegate); return d ? UIK_B(d, sExpectSpecialized) : NO; }

static void UIK_Rate(const char *what, BOOL allowed) {
    static int n;
    if (n < 40 && UIK_Debug()) { n++; UIK_Log("K1 %s: software keyboard %s for the active keyboard scene delegate", what, allowed ? "allowed" : "NOT allowed (text entry focus on the external display)"); }
}
static void uik_showKeyboard(id self, SEL _cmd, BOOL ignore) {
    if (UIK_On(UIK_SW_KEYBOARD) && !UIK_SWKeyboardAllowed()) {
        UIK_Rate("_showKeyboardIgnoringPolicyDelegate: returns without showing", NO);
        return;
    }
    orig_showKeyboard(self, _cmd, ignore);
}
static BOOL uik_shouldMinimizeHW(id self, SEL _cmd) {
    if (UIK_On(UIK_SW_KEYBOARD) && !UIK_SWKeyboardAllowed()) { UIK_Rate("_shouldMinimizeForHardwareKeyboard answers YES", NO); return YES; }
    return orig_shouldMinimizeHW(self, _cmd);
}
static BOOL uik_scribble(id self, SEL _cmd) {
    BOOL r = orig_scribble(self, _cmd);
    if (r && UIK_On(UIK_SW_KEYBOARD) && !UIK_SWKeyboardAllowed()) return NO;
    return r;
}
static BOOL uik_showKeyboardButton(id self, SEL _cmd) {
    if (!UIK_On(UIK_SW_KEYBOARD)) return orig_showKeyboardButton(self, _cmd);
    id ki = UIK_ClsId(gKImpl, sActiveInstance);
    BOOL x = UIK_B(ki, sIsMinimized) || UIK_B(UIK_Id(ki, sDelegateAsResponder), sSuppressSW) || UIK_B(ki, sScribble);
    return x && UIK_SWKeyboardAllowed();
}
// -[UIKeyboardVisualModeManager visualMode] 16.2 0x1898b574c (1 = regular, 2 = minimized), without the keyboard camera term
static int uik_visualMode(id self, SEL _cmd) {
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
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(a, s, ident, reason, dispatch_get_main_queue(), inv);
}
static BOOL UIK_U2On(void) { return UIK_On(UIK_SW_SCREENLIFE); }

// ---- UIScreen
static void uik_registerStaticNotifs(id self, SEL _cmd) { (void)self; (void)_cmd; }          // 16.2 has no scene counting: nothing to register
static void uik_realDisconnect(id screen, SEL cmd) {
    objc_setAssociatedObject(screen, &kUScreenNeedsDisc, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIK_Log("U2 disconnecting screen %p", (__bridge void *)screen);
    ((void (*)(id, SEL))orig_disconnectScreenU2)(screen, cmd);
}
// the only 16.0 caller is +_FBSDisplayIdentityDisconnected: (16.2 0x18949be00: prevention set exists -> needsDisconnection, else disconnect)
static void uik_disconnectScreenU2(id self, SEL _cmd) {
    if (!UIK_U2On()) { ((void (*)(id, SEL))orig_disconnectScreenU2)(self, _cmd); return; }
    if (objc_getAssociatedObject(self, &kUScreenSet)) { objc_setAssociatedObject(self, &kUScreenNeedsDisc, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); UIK_Log("U2 screen %p: disconnection deferred", (__bridge void *)self); return; }
    uik_realDisconnect(self, _cmd);
}
static id uik_preventDisconnection(id self, SEL _cmd, NSString *reason) {                    // 0x18996babc
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
// -[_UIWindowSceneDisplaySettingsDiffAction _performActionsForUIScene:withUpdatedFBSScene:settingsDiff:fromSettings:transitionContext:lifecycleActionType:] 16.2 0x1895fd4fc
static void uik_displayAction(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {
    Class ws = objc_getClass("UIWindowScene");
    if (!UIK_U2On() || !ws || ![uiScene isKindOfClass:ws]) { ((void (*)(id, SEL, id, id, id, id, id, unsigned long long))orig_dispActionU2)(self, _cmd, uiScene, fbs, diff, from, ctx, type); return; }
    unsigned char flags = from == nil ? 2 : 0;
    id insp = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("sceneSettingsDisplayDiffInspector"));
    ((void (*)(id, SEL, id, void *))objc_msgSend)(insp, sel_registerName("inspectDiff:withContext:"), diff, &flags);
    if (!(flags & 3)) return;
    id cfg = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(fbs, sel_registerName("settings")), sel_registerName("displayConfiguration"));
    id ident = ((id (*)(id, SEL))objc_msgSend)(cfg, sel_registerName("identity"));
    id screen = ((id (*)(id, SEL, id))objc_msgSend)((id)objc_getClass("UIScreen"), sel_registerName("_screenWithFBSDisplayIdentity:"), ident);
    if (!screen) return;
    if (flags & 1) {
        id app = [UIApplication sharedApplication];
        if (!((BOOL (*)(id, SEL))objc_msgSend)(app, sel_registerName("isFrontBoard"))) ((void (*)(id, SEL, id))objc_msgSend)(screen, sel_registerName("_updateDisplayConfiguration:"), cfg);
    }
    long long status = ((long long (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(fbs, sel_registerName("uiSettings")), sel_registerName("screenReferenceDisplayModeStatus"));
    ((void (*)(id, SEL, long long))objc_msgSend)(screen, sel_registerName("_setReferenceDisplayModeStatus:"), status);
}

// ---- _UIScreenBasedWindowScene
static BOOL uik_yes(id self, SEL _cmd) { (void)self; (void)_cmd; return YES; }
static id uik_sceneScreen(id s) { return (__bridge id)*(void **)((char *)(__bridge void *)s + gUScreenOff); }
static BOOL uik_sceneNeedsInv(id s) { return [objc_getAssociatedObject(s, &kUSceneNeedsInv) boolValue]; }
static BOOL uik_sceneHasInvalidated(id s) { return ((BOOL (*)(id, SEL))objc_msgSend)(s, sel_registerName("_hasInvalidated")); }
static id uik_preventAutoInvalidation(id self, SEL _cmd, NSString *reason) {                // 0x1895fea08
    if (!self) return nil;
    Class c = object_getClass(self);
    if (!((BOOL (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("autoInvalidates")) || uik_sceneNeedsInv(self)) return nil;
    NSMutableSet *set = objc_getAssociatedObject(self, &kUSceneSet);
    if (!set) { set = [NSMutableSet set]; objc_setAssociatedObject(self, &kUSceneSet, set, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (!objc_getAssociatedObject(self, &kUSceneScreenAssertion)) {
        NSString *r = [NSString stringWithFormat:@"%s: %p: prevent screen disconnection", class_getName(c), (__bridge void *)self];
        id sa = ((id (*)(id, SEL, id))objc_msgSend)(uik_sceneScreen(self), sel_registerName("_preventDisconnectionForReason:"), r);
        objc_setAssociatedObject(self, &kUSceneScreenAssertion, sa, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSString *ident = [NSString stringWithFormat:@"%s-%p-%lu", class_getName(c), (__bridge void *)self, ++gUCounter];
    __weak id w = self;
    id a = UIK_NewSimpleAssertion(ident, reason, ^(id as) {                                   // block 0x1895fed6c
        id s = w;
        if (s) ((void (*)(id, SEL, id))objc_msgSend)(s, sel_registerName("_removeAutoInvalidationPreventionAssertion:"), as);
    });
    if (a) [set addObject:a];
    UIK_Log("U2 preventing auto invalidation of scene %p: %s (assertions %lu)", (__bridge void *)self, reason.UTF8String, (unsigned long)[set count]);
    return a;
}
static void uik_performInvalidationIfNeeded(id self, SEL _cmd) {                            // 0x1895fe834
    if (!self || !uik_sceneNeedsInv(self) || uik_sceneHasInvalidated(self)) return;
    objc_setAssociatedObject(self, &kUSceneNeedsInv, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIK_Log("U2 performing invalidation for scene %p", (__bridge void *)self);
    ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("_invalidate"));
    Class c = object_getClass(self);
    id key = (__bridge id)*(void **)((char *)(__bridge void *)self + gULookupOff);
    id q = ((id (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("unassociationCacheAccessQueue"));
    dispatch_sync((dispatch_queue_t)q, ^{ ((void (*)(id, SEL, id))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("unassociationCache")), sel_registerName("removeObjectForKey:"), key); });
}
static void uik_removeAutoInvalidationAssertion(id self, SEL _cmd, id assertion) {          // 0x1895fedd0
    NSMutableSet *set = objc_getAssociatedObject(self, &kUSceneSet);
    if (![set containsObject:assertion]) { UIK_Problem("u2-removeassertion", "U2 _removeAutoInvalidationPreventionAssertion: for an assertion that is not held (16.2 asserts)"); return; }
    [set removeObject:assertion];
    if ([set count] == 0) {
        ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("_performInvalidationIfNeeded"));
        id sa = objc_getAssociatedObject(self, &kUSceneScreenAssertion);
        if (sa) ((void (*)(id, SEL))objc_msgSend)(sa, sel_registerName("invalidate"));
        objc_setAssociatedObject(self, &kUSceneScreenAssertion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void uik_screenDisconnected(id self, SEL _cmd, NSNotification *n) {                 // 0x1895ff670
    id screen = n.object;
    if (![screen isKindOfClass:objc_getClass("UIScreen")] || uik_sceneScreen(self) != screen) return;
    id sa = objc_getAssociatedObject(self, &kUSceneScreenAssertion);
    if (sa) UIK_Problem("u2-disconnect-assertion", "U2 screen is disconnecting while an assertion should prevent it (16.2 logs a fault)");
    if (sa) ((void (*)(id, SEL))objc_msgSend)(sa, sel_registerName("invalidate"));
    objc_setAssociatedObject(self, &kUSceneScreenAssertion, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kUSceneNeedsInv, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("_performInvalidationIfNeeded"));
}
static IMP orig_detachU2, orig_unassocU2;
static void uik_detachWindow(id self, SEL _cmd, id window) {                                // 0x18949e658
    if (!UIK_U2On()) { ((void (*)(id, SEL, id))orig_detachU2)(self, _cmd, window); return; }
    IMP sup = class_getMethodImplementation(class_getSuperclass(gUSceneCls), _cmd);
    ((void (*)(id, SEL, id))sup)(self, _cmd, window);
    Class c = object_getClass(self);
    if (!((BOOL (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("autoInvalidates"))) return;
    BOOL *reg = (BOOL *)((char *)(__bridge void *)self + gUEvalOff);
    if (*reg || uik_sceneHasInvalidated(self)) return;
    *reg = YES;
    __weak id w = self;
    [[NSRunLoop mainRunLoop] performBlock:^{
        id s = w;
        if (!s || uik_sceneHasInvalidated(s)) return;
        __block BOOL hasWindows = NO;
        void (^each)(id, BOOL *) = ^(id win, BOOL *stop) { hasWindows = YES; if (stop) *stop = YES; };
        ((void (*)(id, SEL, BOOL, BOOL, BOOL, BOOL *, id))objc_msgSend)(s, sel_registerName("_enumerateWindowsIncludingInternalWindows:onlyVisibleWindows:asCopy:stopped:withBlock:"), YES, NO, NO, NULL, each);
        if (!hasWindows) {
            objc_setAssociatedObject(s, &kUSceneNeedsInv, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIK_Log("U2 marking scene %p as needing invalidation", (__bridge void *)s);
            NSSet *set = objc_getAssociatedObject(s, &kUSceneSet);
            if (!set || [set count] == 0) ((void (*)(id, SEL))objc_msgSend)(s, sel_registerName("_performInvalidationIfNeeded"));
        }
        *(BOOL *)((char *)(__bridge void *)s + gUEvalOff) = NO;
    }];
}
// +[_UIScreenBasedWindowScene _unassociatedWindowSceneForScreen:create:] 0x18908ca30: the scene is made OUTSIDE the cache queue block
static id uik_unassociated(id cls, SEL _cmd, id screen, BOOL create) {
    if (!UIK_U2On()) return ((id (*)(id, SEL, id, BOOL))orig_unassocU2)(cls, _cmd, screen, create);
    __block id key = nil, ctx = nil;
    __block BOOL created = NO;
    id q = ((id (*)(id, SEL))objc_msgSend)(cls, sel_registerName("unassociationCacheAccessQueue"));
    dispatch_sync((dispatch_queue_t)q, ^{
        id k = ((id (*)(id, SEL))objc_msgSend)(screen, sel_registerName("displayIdentity"));
        if (!k) k = ((id (*)(id, SEL))objc_msgSend)(screen, sel_registerName("_name"));
        key = k;
        id cache = ((id (*)(id, SEL))objc_msgSend)(cls, sel_registerName("unassociationCache"));
        ctx = ((id (*)(id, SEL, id))objc_msgSend)(cache, sel_registerName("objectForKey:"), key);
        if (ctx || !create) return;
        created = YES;
        ctx = [[objc_getClass("_UISceneUnassociatedContext") alloc] init];
        id sess = ((id (*)(id, SEL, id, id, id))objc_msgSend)([objc_getClass("UISceneSession") alloc], sel_registerName("_initWithPersistentIdentifier:sessionRole:configurationName:"), [[NSUUID UUID] UUIDString], @"_UIScreenBasedSceneSession", nil);
        id cfg = ((id (*)(id, SEL))objc_msgSend)(sess, sel_registerName("configuration"));
        ((void (*)(id, SEL, Class))objc_msgSend)(cfg, sel_registerName("setSceneClass:"), Nil);
        ((void (*)(id, SEL, Class))objc_msgSend)(cfg, sel_registerName("setDelegateClass:"), Nil);
        ((void (*)(id, SEL, id))objc_msgSend)(cfg, sel_registerName("setStoryboard:"), nil);
        ((void (*)(id, SEL, id))objc_msgSend)(sess, sel_registerName("_updateConfiguration:"), cfg);
        ((void (*)(id, SEL, id))objc_msgSend)(ctx, sel_registerName("setSession:"), sess);
        ((void (*)(id, SEL, id, id))objc_msgSend)(cache, sel_registerName("setObject:forKey:"), ctx, key);
    });
    if (created && ctx && key) {
        id sess = ((id (*)(id, SEL))objc_msgSend)(ctx, sel_registerName("session"));
        id scene = ((id (*)(id, SEL, id, id, id))objc_msgSend)([cls alloc], sel_registerName("initWithScreen:session:lookupKey:"), screen, sess, key);
        ((void (*)(id, SEL, id))objc_msgSend)(ctx, sel_registerName("setScene:"), scene);
        NSString *const *pn = (NSString *const *)dlsym(RTLD_DEFAULT, "_UISceneWillConnectNotification");
        [[NSNotificationCenter defaultCenter] postNotificationName:pn ? *pn : @"_UISceneWillConnectNotification" object:scene];
        ((void (*)(id, SEL, id))objc_msgSend)(sess, sel_registerName("_setScene:"), scene);
    }
    return ((id (*)(id, SEL))objc_msgSend)(ctx, sel_registerName("scene"));
}

// ---- live resize
static void uik_inLiveResizeDidChange(id self, SEL _cmd) {                                  // 0x189dfbeb0
    if (!self) return;
    BOOL live = ((BOOL (*)(id, SEL))objc_msgSend)(self, sel_registerName("_isInLiveResize"));
    [[NSNotificationCenter defaultCenter] postNotificationName:live ? @"UIWindowSceneDidBeginLiveResizeNotification" : @"UIWindowSceneDidEndLiveResizeNotification" object:self];
}
static BOOL uik_isInLiveResize(id self, SEL _cmd) {                                         // 0x189dfbe78
    id s = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("_effectiveUISettings"));
    return ((BOOL (*)(id, SEL))objc_msgSend)(s, sel_registerName("inLiveResize"));
}
static void uik_observeInLiveResize(id self, SEL _cmd, id block) { ((void (*)(id, SEL, unsigned long long, id))objc_msgSend)(self, sel_registerName("_observeOtherSetting:withBlock:"), 0x28, block); }
static char kULiveInsp;
static id uik_liveInspector(id self, SEL _cmd) {
    id i = objc_getAssociatedObject(self, &kULiveInsp);
    if (!i) {
        i = [[objc_getClass("UIApplicationSceneSettingsDiffInspector") alloc] init];
        ((void (*)(id, SEL, id))objc_msgSend)(i, sel_registerName("observeInLiveResizeWithBlock:"), ^(void *ctx) { *(unsigned char *)ctx |= 1; });
        objc_setAssociatedObject(self, &kULiveInsp, i, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return i;
}
static void uik_setLiveInspector(id self, SEL _cmd, id i) { objc_setAssociatedObject(self, &kULiveInsp, i, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void uik_liveAction(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {   // 0x189e7a2ac
    if (![uiScene isKindOfClass:objc_getClass("UIWindowScene")]) { UIK_Problem("u2-live", "U2 live resize action for a scene that is not a UIWindowScene (16.2 asserts)"); return; }
    unsigned char flag = 0;
    ((void (*)(id, SEL, id, void *))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("sceneSettingsLiveResizeDiffInspector")), sel_registerName("inspectDiff:withContext:"), diff, &flag);
    if (flag & 1) ((void (*)(id, SEL))objc_msgSend)(uiScene, sel_registerName("_inLiveResizeDidChange"));
}
static void uik_nonInteractiveAction(id self, SEL _cmd, id uiScene, id fbs, id diff, id from, id ctx, unsigned long long type) {   // 0x1895fd6f0
    if (!((BOOL (*)(id, SEL))objc_msgSend)(uiScene, sel_registerName("_hasLifecycle"))) return;
    id settings = ((id (*)(id, SEL))objc_msgSend)(uiScene, sel_registerName("_effectiveSettings"));
    id blk = gUUpdateBlock(uiScene, from, settings, ctx);
    if (!blk) return;
    void (^b)(void) = blk;
    gUPerformChanges(ctx, ^{                                                                  // block 0x1895fd824
        b();
        id mux = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("_UISceneLifecycleMultiplexer"), sel_registerName("sharedInstance"));
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(mux, sel_registerName("uiScene:transitionedFromState:withTransitionContext:"), uiScene, from, ctx);
    }, nil);
}
static id uik_firstOfClass(NSArray *a, const char *name) { Class c = objc_getClass(name); for (id o in a) if (c && [o isKindOfClass:c]) return o; return nil; }
static id uik_appActions(id self, SEL _cmd) {
    NSArray *a = ((id (*)(id, SEL))orig_appActionsU2)(self, _cmd);
    if (!UIK_U2On() || ![a isKindOfClass:[NSArray class]] || uik_firstOfClass(a, "_UIWindowSceneLiveResizeDiffAction")) return a;
    NSMutableArray *m = [a mutableCopy];
    id w = uik_firstOfClass(m, "_UIWindowSceneWindowingModeDiffAction");
    if (!w) { UIK_Problem("u2-appactions", "U2 initialSettingsDiffActions: no _UIWindowSceneWindowingModeDiffAction in the array, live resize action not added"); return a; }
    [m insertObject:[[gULiveCls alloc] init] atIndex:[m indexOfObject:w] + 1];
    return m;
}
static id uik_extActions(id self, SEL _cmd) {
    NSArray *a = ((id (*)(id, SEL))orig_extActionsU2)(self, _cmd);
    if (!UIK_U2On() || ![a isKindOfClass:[NSArray class]] || !gUNonCls) return a;
    id d = uik_firstOfClass(a, "_UIWindowSceneDisplaySettingsDiffAction"), g = uik_firstOfClass(a, "_UIWindowSceneGeometrySettingsDiffAction"), o = uik_firstOfClass(a, "_UIWindowSceneOcclusionSettingsDiffAction"), w = uik_firstOfClass(a, "_UIWindowSceneWindowingModeDiffAction");
    if (!d || !g || !o || !w || !uik_firstOfClass(a, "_UIWindowSceneLifecycleSettingsDiffAction")) { UIK_Problem("u2-extactions", "U2 external screen initialSettingsDiffActions has an unexpected content: left as is"); return a; }
    return @[d, [[gUNonCls alloc] init], w, [[gULiveCls alloc] init], g, o];                  // 16.2 order
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
        id pc = tp ? ((id (*)(id, SEL))objc_msgSend)((id)tp, sel_registerName("sharedPreferencesController")) : nil;
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
static BOOL uik_needsConvert(id self, SEL _cmd) {                                          // 0x189abed7c
    if (!UIK_K2Cached()) return NO;
    id d = ((id (*)(id, SEL))objc_msgSend)((id)objc_getClass("UIKeyboardSceneDelegate"), sel_registerName("activeKeyboardSceneDelegate"));
    id vm = ((id (*)(id, SEL))objc_msgSend)(d, sel_registerName("visualModeManager"));
    return vm && ((BOOL (*)(id, SEL))objc_msgSend)(vm, sel_registerName("windowingModeEnabled"));
}
static id uik_convertUserInfoK2(id self, SEL _cmd, id info) {                               // 0x189abefa4 (the 16.0 conversion towards the controller's own window scene)
    id win = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("_window"));
    id scene = ((id (*)(id, SEL))objc_msgSend)(win, sel_registerName("windowScene"));
    return ((id (*)(id, SEL, id, id))objc_msgSend)(self, sel_registerName("convertUserInfo:toWindowScene:"), info, scene);
}
static void uik_postNotification(id self, SEL _cmd, NSString *name, id info) {              // 0x189abf33c
    id view = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("view"));
    id win = ((id (*)(id, SEL))objc_msgSend)(view, sel_registerName("window"));
    id screen = ((id (*)(id, SEL))objc_msgSend)(((id (*)(id, SEL))objc_msgSend)(win, sel_registerName("windowScene")), sel_registerName("screen"));
    if (!screen) screen = ((id (*)(id, SEL))objc_msgSend)(win, sel_registerName("screen"));
    id out = info;
    if (uik_needsConvert(self, 0)) out = ((id (*)(id, SEL, id))objc_msgSend)(self, sel_registerName("convertUserInfo:"), info);
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:screen userInfo:out];
}
static void uik_postCorresp(id self, SEL _cmd, NSString *name, id info) {
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
static void uik_ncPost(id self, SEL _cmd, NSString *name, id object, id info) {
    NSString *s = tK2Suppress;
    if (s && name && (s == name || [s isEqualToString:name])) { tK2Suppress = nil; return; }
    ((void (*)(id, SEL, id, id, id))orig_ncPostK2)(self, _cmd, name, object, info);
}
static void UIK_InstallK2(void) {
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

__attribute__((constructor)) static void UIK_Init(void) {
    if (!UIK_BuildMatches() || !UIK_IsApp()) return;
    Dl_info di;
    if (UIK_Debug() && dladdr((void *)&UIK_Init, &di)) UIK_Log("Backport162UIK loaded, image base %p", di.dli_fbase);
    UIK_InstallU1();
    UIK_InstallK1();
    UIK_InstallU2();
    UIK_InstallK2();
}
