// UIKU2b.m : UIK U2, the two default scene handlers of UIApplication of iPadOS 16.2 (20C65), in apps (part of Backport162UIK.dylib, installed by UIK_InstallU2b from UIK.m, after UIK_InstallU2 which adds
// -[UIScene _preventAutoInvalidationForReason:] / the assertion bookkeeping the handlers use).
//
//   __UIApplicationSceneConnectionHandler_block_invoke      16.2 0x1893148b4 (16.0 0x1891de700): migrates the windows of EVERY _UIPlaceholderWindowScene to the connecting scene (16.0: only the one of the scene's
//                                                           screen) and drops the auto invalidation assertion of the default scene
//   __UIApplicationSceneDisconnectionHandler_block_invoke_3 16.2 0x1895f2db8 (16.0 0x1894ba73c): takes [placeholderScene _preventAutoInvalidationForReason:@"default scene disconnected"] into a static
//
// Both are bodies of GLOBAL blocks in UIKitCore's __AUTH_CONST.__const (16.0 20A8372: block 0x1df142c20 for the connection handler, block 0x1df142c40 for the disconnection handler; flags 0x50000000):
// the invoke pointer at block + 0x10 is signed (key IA, address diversified, diversity 0).  The bodies are Y42U2Lift.c (recompiled 16.2 machine code, verified with tools/a2c/tests/tracecmp.py against the
// emulation of the original code: calls, ownership events, memory, 120 seeds each).  This file replaces the two invoke pointers (vm_protect VM_PROT_COPY on the page) AFTER checking
//   * the build (20A8372, UIK_BuildMatches by the caller) and the image: the block flags, the old invoke pointer == the 16.0 address + the UIKitCore slide (ptrauth_strip), and the 8 instruction words at that target
//   * every class / selector / function / ivar the recompiled bodies use (the preflight of Y42U2Lift.c and a table of (selector, receiver classes) below)
// Any miss: nothing is replaced, ONE ANOMALY line names every missing piece, the 16.0 handlers stay.  Switch uik_defscene (kill file Backport162.off.uik_defscene, read at every call: the wrapper then calls the 16.0
// body).  Exception barrier: an exception inside a recompiled body is logged (ANOMALY u2b-exception with the reason) and the 16.0 body runs.  NOT device tested.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <string.h>
#if __has_include(<ptrauth.h>)
#import <ptrauth.h>
#endif

#ifndef VM_PROT_COPY
#define VM_PROT_COPY ((vm_prot_t)0x10)
#endif

// Y42U2Lift.c
extern void y42_u2_conn(uint64_t block, uint64_t scene, uint64_t fbsScene);
extern void y42_u2_disc(uint64_t block, uint64_t scene);
extern const char *y42_u2_preflight(void);
// UIK.m
extern void UIK_U2b_Problem(const char *key, const char *text);
extern BOOL UIK_U2b_On(void);

typedef struct { uint64_t block; uint64_t invoke; uint32_t words[8]; const char *name; } U2bSpec;
// 16.0 20A8372 addresses (unslid)
static const U2bSpec kU2b[2] = {
    { 0x1df142c20ull, 0x1891de700ull, { 0xd503237f, 0xd10743ff, 0x6d1623e9, 0xa9176ffc, 0xa91867fa, 0xa9195ff8, 0xa91a57f6, 0xa91b4ff4 }, "__UIApplicationSceneConnectionHandler_block_invoke" },
    { 0x1df142c40ull, 0x1894ba73cull, { 0xd503237f, 0xd10583ff, 0xa9106ffc, 0xa91167fa, 0xa9125ff8, 0xa91357f6, 0xa9144ff4, 0xa9157bfd }, "__UIApplicationSceneDisconnectionHandler_block_invoke_3" },
};
static void *gU2bOrig[2];          // the 16.0 invoke (signed as a plain function pointer)
static BOOL gU2bFlag[2];

static void U2b_Exc(int which, NSException *e) {
    char key[48], text[480];
    snprintf(key, sizeof key, "u2b-exception-%d", which);
    snprintf(text, sizeof text, "[uik] U2 default scene handler %s: exception %s: %s inside the recompiled 16.2 body: the 16.0 handler runs (build 20A8372)", kU2b[which].name, e.name.UTF8String, e.reason.UTF8String);
    UIK_U2b_Problem(key, text);
}

typedef void (*U2bConnFn)(void *, void *, void *);
typedef void (*U2bDiscFn)(void *, void *);
static void U2b_Conn(void *block, void *scene, void *fbs) {
    if (UIK_U2b_On()) {
        @try { y42_u2_conn((uint64_t)(uintptr_t)block, (uint64_t)(uintptr_t)scene, (uint64_t)(uintptr_t)fbs); return; }
        @catch (NSException *e) { U2b_Exc(0, e); }
    }
    ((U2bConnFn)gU2bOrig[0])(block, scene, fbs);
}
static void U2b_Disc(void *block, void *scene) {
    if (UIK_U2b_On()) {
        @try { y42_u2_disc((uint64_t)(uintptr_t)block, (uint64_t)(uintptr_t)scene); return; }
        @catch (NSException *e) { U2b_Exc(1, e); }
    }
    ((U2bDiscFn)gU2bOrig[1])(block, scene);
}

// (selector, receiver classes the recompiled bodies send it to: at least one of them must implement it, instance or class side)
typedef struct { const char *sel; const char *cls[4]; } U2bSel;
__attribute__((unused)) static const U2bSel kU2bSels[] = {
    { "_appAdoptsUISceneLifecycle", { "UIApplication" } },
    { "_defaultSceneIfExists", { "UIApplication" } },
    { "isFrontBoard", { "UIApplication" } },
    { "disablesFrontBoardImplicitWindowScenes", { "UIApplication" } },
    { "_scenesIncludingInternal:", { "UIApplication" } },
    { "_FBSScene", { "UIScene", "UIWindowScene", "UIApplication" } },
    { "_fbsScene", { "UIScene", "UIWindowScene", "UIApplication" } },
    { "_uiWindowSceneFromFBSScene:", { "UIApplication" } },
    { "_placeholderWindowSceneForScreen:create:", { "UIApplication", "_UIPlaceholderWindowScene" } },
    { "_preventAutoInvalidationForReason:", { "_UIPlaceholderWindowScene", "UIWindowScene", "UIScene" } },
    { "invalidate", { "UIScene", "UIWindowScene" } },
    { "_isMainScreen", { "UIScreen" } },
    { "_isMainLikeScreen", { "UIScreen" } },
    { "screen", { "UIWindow", "UIWindowScene", "_UIPlaceholderWindowScene" } },
    { "_keyWindow", { "UIWindowScene", "UIApplication", "UIWindow" } },
    { "_allWindowsIncludingInternalWindows:onlyVisibleWindows:", { "UIWindowScene", "UIApplication", "UIScreen" } },
    { "setWindowScene:", { "UIWindow" } },
    { "windowScene", { "UIWindow" } },
    { "_makeKeyWindowIgnoringOldKeyWindow:transferringScenes:", { "UIWindow", "UIApplication" } },
    { "statusBarManager", { "UIWindowScene" } },
    { "updateStatusBarAppearance", { "UIStatusBarManager", "UIApplication" } },
};
__attribute__((unused)) static BOOL U2b_Has(const char *clsName, const char *sel) {
    Class c = objc_getClass(clsName);
    if (!c) return NO;
    SEL s = sel_registerName(sel);
    return class_getInstanceMethod(c, s) != NULL || class_getClassMethod(c, s) != NULL;
}

__attribute__((unused)) static uintptr_t U2b_Slide(void) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (nm && strstr(nm, "/UIKitCore.framework/UIKitCore")) return (uintptr_t)_dyld_get_image_vmaddr_slide(i);
    }
    return (uintptr_t)-1;
}

void UIK_InstallU2b(void) {
#if __has_feature(ptrauth_calls)
    char miss[1400]; miss[0] = 0;
    size_t n = 0;
#define U2B_MISS(...) do { int w_ = snprintf(miss + n, sizeof miss - n, __VA_ARGS__); if (w_ > 0 && (size_t)w_ < sizeof miss - n) n += (size_t)w_; } while (0)
    uintptr_t slide = U2b_Slide();
    if (slide == (uintptr_t)-1) U2B_MISS(" UIKitCore image not found;");
    const char *pf = y42_u2_preflight();
    if (pf) U2B_MISS(" unresolved names of the recompiled bodies: %s;", pf);
    for (size_t k = 0; k < sizeof kU2bSels / sizeof kU2bSels[0]; k++) {
        BOOL ok = NO;
        for (int j = 0; j < 4 && kU2bSels[k].cls[j]; j++) if (U2b_Has(kU2bSels[k].cls[j], kU2bSels[k].sel)) { ok = YES; break; }
        if (!ok) U2B_MISS(" selector %s (%s%s);", kU2bSels[k].sel, kU2bSels[k].cls[0], kU2bSels[k].cls[1] ? " ..." : "");
    }
    uint64_t *slot[2] = { 0, 0 }; void *newInvoke[2] = { (void *)U2b_Conn, (void *)U2b_Disc };
    if (!miss[0]) {
        for (int w = 0; w < 2; w++) {
            uintptr_t blk = (uintptr_t)kU2b[w].block + slide;
            uint64_t flags = 0; vm_size_t got = 0;
            // read through vm_read_overwrite: a wrong address is reported, not dereferenced
            if (vm_read_overwrite(mach_task_self(), (vm_address_t)(blk + 8), 4, (vm_address_t)&flags, &got) != KERN_SUCCESS) { U2B_MISS(" block %s unreadable at %p;", kU2b[w].name, (void *)blk); continue; }
            if ((uint32_t)flags != 0x50000000u) { U2B_MISS(" block %s flags 0x%x (expected 0x50000000);", kU2b[w].name, (unsigned)(uint32_t)flags); continue; }
            void *old = *(void *volatile *)(blk + 0x10);
            void *oldStripped = ptrauth_strip(old, ptrauth_key_asia);
            if ((uintptr_t)oldStripped != (uintptr_t)kU2b[w].invoke + slide) { U2B_MISS(" block %s invoke %p != 16.0 address %p + slide;", kU2b[w].name, oldStripped, (void *)((uintptr_t)kU2b[w].invoke + slide)); continue; }
            void *signedOld = ptrauth_sign_unauthenticated(oldStripped, ptrauth_key_asia, ptrauth_blend_discriminator((void *)(blk + 0x10), 0));
            if (signedOld != old) { U2B_MISS(" block %s invoke pointer is not signed with key IA, address diversity, diversity 0;", kU2b[w].name); continue; }
            const uint32_t *code = (const uint32_t *)oldStripped; BOOL same = YES;
            uint32_t buf[8]; vm_size_t got2 = 0;
            if (vm_read_overwrite(mach_task_self(), (vm_address_t)code, sizeof buf, (vm_address_t)buf, &got2) != KERN_SUCCESS) same = NO;
            else for (int i = 0; i < 8; i++) if (buf[i] != kU2b[w].words[i]) same = NO;
            if (!same) { U2B_MISS(" the code at the invoke of %s is not the 16.0 20A8372 code;", kU2b[w].name); continue; }
            slot[w] = (uint64_t *)(blk + 0x10);
            gU2bOrig[w] = ptrauth_sign_unauthenticated(oldStripped, ptrauth_key_function_pointer, 0);
        }
    }
    if (miss[0] || !slot[0] || !slot[1]) {
        UIK_U2b_Problem("u2b-notinstalled", [[NSString stringWithFormat:@"[uik] U2 default scene handlers NOT installed (build 20A8372): the 16.0 handlers stay; missing:%s", miss] UTF8String]);
        return;
    }
    // the replacement: the page holding the blocks becomes a private writable copy (the shared cache __AUTH_CONST page), the pointer is re-signed for its slot
    for (int w = 0; w < 2; w++) {
        vm_address_t pg = (vm_address_t)((uintptr_t)slot[w] & ~(uintptr_t)(vm_page_size - 1));
        kern_return_t kr = vm_protect(mach_task_self(), pg, vm_page_size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (kr != KERN_SUCCESS) {
            UIK_U2b_Problem("u2b-protect", [[NSString stringWithFormat:@"[uik] U2 default scene handlers: vm_protect(VM_PROT_COPY) of %p failed (%d): handler %s stays the 16.0 one (build 20A8372)", (void *)pg, kr, kU2b[w].name] UTF8String]);
            if (w == 1 && gU2bFlag[0]) UIK_U2b_Problem("u2b-partial", "[uik] U2 default scene handlers: only the connection handler was replaced (build 20A8372)");
            continue;
        }
        void *fresh = ptrauth_sign_unauthenticated(ptrauth_strip(newInvoke[w], ptrauth_key_function_pointer), ptrauth_key_asia, ptrauth_blend_discriminator((void *)slot[w], 0));
        *(void *volatile *)slot[w] = fresh;
        vm_protect(mach_task_self(), pg, vm_page_size, FALSE, VM_PROT_READ);
        gU2bFlag[w] = YES;
    }
    UIK_U2b_Problem("u2b-installed", "[uik] U2 default scene handlers installed (build 20A8372): connection handler and disconnection handler of UIApplication are the recompiled 16.2 bodies");
#undef U2B_MISS
#else
    UIK_U2b_Problem("u2b-notinstalled", "[uik] U2 default scene handlers NOT installed (build 20A8372): the process is not arm64e (the invoke pointers are signed)");
#endif
}
