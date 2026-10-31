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

__attribute__((constructor)) static void UIK_Init(void) {
    if (!UIK_BuildMatches() || !UIK_IsApp()) return;
    Dl_info di;
    if (UIK_Debug() && dladdr((void *)&UIK_Init, &di)) UIK_Log("Backport162UIK loaded, image base %p", di.dli_fbase);
    UIK_InstallU1();
    UIK_InstallK1();
}
