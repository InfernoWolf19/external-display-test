// Y27Views.x : delta sweep pass 3, switcher view rows (F3).  Setup: constructor.  Log prefix "[y27]".
//
//  y24_topaffordance  SBTopAffordanceViewController (the window title dots).  16.2 removed the expanded dots / pill mode (-_setTopAffordanceMode:animated:, -_updateDotsForTopAffordanceMode:animated:,
//                     -presentTransientMessage..., the pill views).  In 16.0 the mode is 0 for every window of the Stage Manager UI (the only writers, -setTopAffordanceMode:animated: 0x1c645789c and
//                     the pill message path, never run there), so what remained visible of the 16.0 code is:
//                     * -viewDidLoad (16.2 0x1c790bdb0): the dots alpha follows the presence controller ([[_affordancePresenceController currentPresence] == 0] ? 1 : 0) and nothing else;
//                       16.0 0x1c6457330 ends in -_updateDotsForTopAffordanceMode:animated: which ALSO moves the dots' centre Y constraint to _defaultCenterYOffset + _additionalTopInset.  Ported by
//                       replacing -_updateDotsForTopAffordanceMode:animated: (16.0 0x1c6459608, the only remaining callers are viewDidLoad and -setAdditionalTopInset:) with the alpha only update.
//                     * -setAdditionalTopInset: (16.0 0x1c64578a0): 16.2 has the plain synthesized setter (0x1c790e410), the dots no longer follow the inset.  Ported: store only.
//                     * -isExpanded (16.2 0x1c790c078) = [dotsView isHeld] (16.0 0x1c64575e8: mode != 0 || isHeld).
//                     * -dismissAnimated: (16.2 0x1c790c0b0): if expanded, dismiss the dots' context menu; 16.0 0x1c6457810 first ran -_setTopAffordanceMode:0 (participant re registration and the dots update).
//                     * -setHidden:forReason:animated: (16.2 0x1c790e0e4): hiding dismisses the menu first, then forwards to the presence controller (16.0 only forwarded).
//                     * -_setSystemPointerInteractionEnabled: (16.2 0x1c790df38): apply when the flag changes; 16.0 0x1c645b028 skipped it while the view was animating (_isAnimating, a pill animation flag).
//  y24_overlayscale   -[SBFluidSwitcherSpaceOverlayAccessoryView layoutSubviews]  16.2 0x1c758c9c4 (16.0 0x1c61065c0): the footer (title / icon pill, ivar _footerView) frame is pixel aligned with
//                     the view's own trait collection display scale (UIRectIntegralWithScale(frame, [[self traitCollection] displayScale]) at 0x1c758cb7c) where 16.0 uses [[UIScreen mainScreen] scale]
//                     (0x1c610670c): an icon overlay on the monitor was aligned to the iPad's pixel grid.  Ported: after the 16.0 body the footer's bounds / position / transform are set again with the
//                     16.2 scale when the two scales differ (same sequence: frame = x midX - w/2, y maxY, w = _contentScale * bounds.width, h = footer intrinsic height; sb_setBoundsAndPositionFromFrame:,
//                     transform = scale(_inverseContentScale)).  -prepareForReuse (16.2 0x1c758c730) removes one more subview that exists only in 16.2 (EQUIVALENT: no such view in 16.0).
// Needs a device: Stage Manager window title dots: tap and hold opens the menu, hiding the dots (full screen app) closes an open menu; an icon zoom overlay on the monitor has crisp edges.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "Y17Common.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

static IMP gY27OrigUpdateDots, gY27OrigIsExpanded, gY27OrigDismiss, gY27OrigSetHidden, gY27OrigPointer, gY27OrigInset, gY27OrigLayout;

static id Y27_Ivar(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    if (!iv) { Y17_GuardOnce("topaffordance", o, name); return nil; }
    return BP_ObjIvar(o, iv);
}

// ---- y24_topaffordance ----
static void Y27_UpdateDots(id self, SEL _cmd, long long mode, BOOL animated) {
    if (!BP_OnName("y24_topaffordance")) { if (gY27OrigUpdateDots) ((void (*)(id, SEL, long long, BOOL))gY27OrigUpdateDots)(self, _cmd, mode, animated); return; }
    id presence = Y27_Ivar(self, "_affordancePresenceController");
    id dots = Y27_Ivar(self, "_dotsView");
    if (!dots || !BPY_Responds(dots, "setAlpha:")) return;
    long long p = BPY_Responds(presence, "currentPresence") ? BPY_SEND(long long, (), presence, "currentPresence") : 0;
    BPY_SEND(void, (double), dots, "setAlpha:", p == 0 ? 1.0 : 0.0);
}
static void Y27_SetInset(id self, SEL _cmd, double inset) {
    if (!BP_OnName("y24_topaffordance")) { if (gY27OrigInset) ((void (*)(id, SEL, double))gY27OrigInset)(self, _cmd, inset); return; }
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_additionalTopInset");
    if (!iv) { Y17_GuardOnce("topaffordance", self, "_additionalTopInset"); return; }
    *(double *)((char *)(__bridge void *)self + ivar_getOffset(iv)) = inset;
}
static BOOL Y27_IsExpanded(id self, SEL _cmd) {
    if (!BP_OnName("y24_topaffordance")) return gY27OrigIsExpanded ? ((BOOL (*)(id, SEL))gY27OrigIsExpanded)(self, _cmd) : NO;
    id dots = BPY_Responds(self, "dotsView") ? BPY_SEND(id, (), self, "dotsView") : nil;
    return BPY_Responds(dots, "isHeld") ? BPY_SEND(BOOL, (), dots, "isHeld") : NO;
}
static void Y27_Dismiss(id self, SEL _cmd, BOOL animated) {
    if (!BP_OnName("y24_topaffordance")) { if (gY27OrigDismiss) ((void (*)(id, SEL, BOOL))gY27OrigDismiss)(self, _cmd, animated); return; }
    if (!BPY_SEND(BOOL, (), self, "isExpanded")) return;
    id dots = BPY_SEND(id, (), self, "dotsView");
    id interaction = Y17_Obj0("topaffordance", dots, "contextMenuInteraction");
    if (BPY_Responds(interaction, "dismissMenu")) BPY_SEND(void, (), interaction, "dismissMenu");
    else Y17_GuardOnce("topaffordance", interaction, "dismissMenu");
}
static void Y27_SetHidden(id self, SEL _cmd, BOOL hidden, id reason, BOOL animated) {
    if (!BP_OnName("y24_topaffordance")) { if (gY27OrigSetHidden) ((void (*)(id, SEL, BOOL, id, BOOL))gY27OrigSetHidden)(self, _cmd, hidden, reason, animated); return; }
    if (hidden) BPY_SEND(void, (BOOL), self, "dismissAnimated:", animated);
    id presence = Y27_Ivar(self, "_affordancePresenceController");
    if (BPY_Responds(presence, "setHidden:forReason:animated:")) BPY_SEND(void, (BOOL, id, BOOL), presence, "setHidden:forReason:animated:", hidden, reason, animated);
    else Y17_GuardOnce("topaffordance", presence, "setHidden:forReason:animated:");
}
static void Y27_SetPointer(id self, SEL _cmd, BOOL enabled) {
    if (!BP_OnName("y24_topaffordance")) { if (gY27OrigPointer) ((void (*)(id, SEL, BOOL))gY27OrigPointer)(self, _cmd, enabled); return; }
    Ivar iv = class_getInstanceVariable(object_getClass(self), "_isSystemPointerInteractionEnabled");
    if (!iv) { Y17_GuardOnce("topaffordance", self, "_isSystemPointerInteractionEnabled"); return; }
    BOOL *flag = (BOOL *)((char *)(__bridge void *)self + ivar_getOffset(iv));
    if (*flag == enabled) return;
    *flag = enabled;
    id dots = Y27_Ivar(self, "_dotsView");
    if (BPY_Responds(dots, "setPointerInteractionEnabled:")) BPY_SEND(void, (BOOL), dots, "setPointerInteractionEnabled:", enabled);
    else Y17_GuardOnce("topaffordance", dots, "setPointerInteractionEnabled:");
}

// ---- y24_overlayscale ----
typedef CGRect (*Y27_IntegralFn)(CGRect, CGFloat);
static void Y27_Layout(id self, SEL _cmd) {
    if (gY27OrigLayout) ((void (*)(id, SEL))gY27OrigLayout)(self, _cmd);
    if (!BP_OnName("y24_overlayscale")) return;
    static Y27_IntegralFn integral; static dispatch_once_t once;
    dispatch_once(&once, ^{ integral = (Y27_IntegralFn)dlsym(RTLD_DEFAULT, "UIRectIntegralWithScale"); if (!integral) BP_Log(@"[y27] GUARD(overlayscale) UIRectIntegralWithScale does not resolve: the iPad scale stays"); });
    if (!integral) return;
    id footer = Y27_Ivar(self, "_footerView");
    if (!footer) return;
    id trait = Y17_Obj0("overlayscale", self, "traitCollection");
    if (!BPY_Responds(trait, "displayScale")) return;
    double scale = BPY_SEND(double, (), trait, "displayScale");
    double mainScale = BPY_SEND(double, (), (id)[UIScreen mainScreen], "scale");
    if (scale == mainScale) return;                                   // the 16.0 body already used this scale
    Ivar cs = class_getInstanceVariable(object_getClass(self), "_contentScale");
    if (!cs || !BPY_Responds(self, "_inverseContentScale") || !BPY_Responds(footer, "intrinsicContentSize") || !BPY_Responds(footer, "sb_setBoundsAndPositionFromFrame:") || !BPY_Responds(footer, "setTransform:")) {
        Y17_GuardOnce("overlayscale", self, "_contentScale / _inverseContentScale / footer sizing selectors"); return;
    }
    CGRect bounds = BPY_SEND(CGRect, (), self, "bounds");
    double inverse = BPY_SEND(double, (), self, "_inverseContentScale");
    double w = *(double *)((char *)(__bridge void *)self + ivar_getOffset(cs)) * CGRectGetWidth(bounds);
    CGSize intrinsic = BPY_SEND(CGSize, (), footer, "intrinsicContentSize");
    CGRect frame = integral(CGRectMake(CGRectGetMidX(bounds) + w * -0.5, CGRectGetMaxY(bounds), w, intrinsic.height), scale);
    BPY_SEND(void, (CGRect), footer, "sb_setBoundsAndPositionFromFrame:", frame);
    BPY_SEND(void, (CGAffineTransform), footer, "setTransform:", CGAffineTransformMakeScale(inverse, inverse));
    BPY_LOG(@"[y27] overlay accessory footer aligned at display scale %.1f (main screen %.1f)", scale, mainScale);
}

__attribute__((constructor)) static void Y27_Setup(void) {
    if (!BPY_BuildOK()) return;
    @autoreleasepool {
        int n = 0;
        Class ta = NSClassFromString(@"SBTopAffordanceViewController");
        static const char *tas[] = { "_updateDotsForTopAffordanceMode:animated:", "setAdditionalTopInset:", "isExpanded", "dismissAnimated:", "setHidden:forReason:animated:", "_setSystemPointerInteractionEnabled:" };
        BOOL all = ta != Nil;
        for (size_t i = 0; all && i < sizeof tas / sizeof tas[0]; i++) if (!class_getInstanceMethod(ta, sel_registerName(tas[i]))) all = NO;
        if (all) {
            gY27OrigUpdateDots = BPX_Replace(ta, "_updateDotsForTopAffordanceMode:animated:", (IMP)Y27_UpdateDots);
            gY27OrigInset = BPX_Replace(ta, "setAdditionalTopInset:", (IMP)Y27_SetInset);
            gY27OrigIsExpanded = BPX_Replace(ta, "isExpanded", (IMP)Y27_IsExpanded);
            gY27OrigDismiss = BPX_Replace(ta, "dismissAnimated:", (IMP)Y27_Dismiss);
            gY27OrigSetHidden = BPX_Replace(ta, "setHidden:forReason:animated:", (IMP)Y27_SetHidden);
            gY27OrigPointer = BPX_Replace(ta, "_setSystemPointerInteractionEnabled:", (IMP)Y27_SetPointer);
            n++;
        } else BP_Log(@"[y27] GUARD(topaffordance) SBTopAffordanceViewController or one of its methods missing: not installed");
        Class ov = NSClassFromString(@"SBFluidSwitcherSpaceOverlayAccessoryView");
        if (ov && class_getInstanceMethod(ov, sel_registerName("layoutSubviews"))) { gY27OrigLayout = BPX_Replace(ov, "layoutSubviews", (IMP)Y27_Layout); n++; }
        else BP_Log(@"[y27] GUARD(overlayscale) SBFluidSwitcherSpaceOverlayAccessoryView layoutSubviews missing: not installed");
        BP_Log(@"[y27] installed %d group(s) (switches y24_topaffordance, y24_overlayscale)", n);
    }
}
#pragma clang diagnostic pop
