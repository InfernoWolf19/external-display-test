// G2F.x : two DELIBERATE, switchable deviations from stock 16.0 and 16.2 in the zoom of a stage / full-screen window to / from a home screen icon
//   g2f_closepivot (default ON): the window shrinks about its own centre (symmetric shrink);
//   g2f_closecrop  (default ON): the card is cropped to the icon-shaped box together with the icon overlay (no nested outer card).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Kill switch files Backport162.off.g2f_closepivot / Backport162.off.g2f_closecrop.
// Setup: G2F_Setup(). Log lines (Backport162.debug): "[g2f] ...". Spec: specs/CLOSE-CROP-0.7.6.md (evidence, numbers, what is unproven).
//
// ===== Part 1: g2f_closepivot =====
// Symptom (user, home swipe close of a stage window to the home screen): the window "narrows suddenly" at the start: its left edge moves inward about twice as fast as its right edge
// (recordings af7310bc / 0dee8146: left +42 px, right -20 px in one frame; the shape itself keeps its aspect 1.64).
//
// Mechanism (read from the binaries; 16.0 and 16.2 identical up to registers, so stock behaviour):
//  * -[SBFullScreenToHomeIconZoomSwitcherModifier frameForIndex:] (16.2 0x1c75b2c34, 16.0 0x1c6128574) answers, while zooming, a box with the ICON's aspect (a square) of side min(w, h) of the card
//    centred on the icon ({{483.75,337},{834,834}} for the 1194x834 window, scale 0.0911 = icon size / 834).  The item container keeps the window's own size: block 0x1c744326c of
//    -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] sets bounds = R.size (block_invoke_19 0x1c744634c, R = frameForLayoutRole:inAppLayout:withBounds: = {0,0,1194,834}).
//  * Pinned layout (shouldPinLayoutRolesToSpace: and shouldUseAnchorPointToPinLayoutRolesToSpace: YES, 16.2 asm 0x1c7443a54 / 0x1c7443a70; our G1B gives both YES to the zoom modifier): the layer
//    anchor point becomes (anchor.x * frame.w - R.x) / R.w, (anchor.y * frame.h - R.y) / R.h  (0x1c74438a4: [sp,#0xb8] = anchor.x * frame.w; 0x1c7443b34..0x1c7443b48), with anchor =
//    anchorPointForIndex: = (0.5, 0.5) of the zoom modifier (16.2 0x1c75b2d8c).  With the 834-wide space and the 1194-wide window that is x = 417 / 1194 = 0.349: the whole window scales about
//    a point 417 pt from its left edge (not its centre, 597) while that point travels to the icon centre.  The left edge therefore moves inward ~ twice as fast as the right edge.
//    (Block 0x1c7444200..0x1c74442c4 compensates the position when the anchor changes so the window does not jump at the hand-off.)
//
// Fix (default ON): the pivot of the pinned zoom is the window's own centre.  Only the anchor the root answers for the zoom layout changes: anchorPointForIndex: returns
// (0.5 * fullyPresented.w / frame.w, 0.5 * fullyPresented.h / frame.h) instead of (0.5, 0.5), with frame = frameForIndex: (the icon box) and fullyPresented = fullyPresentedFrameForIndex:frame:
// (the card's unzoomed frame, the same call -[SBFluidSwitcherViewController frameForPageViewOfContainer:fullyPresented:] 16.2 0x1c72a5224 makes).  The block then computes
//    anchor.x * frame.w = 0.5 * fullyPresented.w = 0.5 * R.w  ->  layer anchor (0.5, 0.5), baseX = frame.x + (0.5 - anchor.x) * frame.w = icon centre - R.w / 2, centre = baseX + R.w / 2 = icon centre.
// So the window centre travels to the SAME screen point as before (the icon centre; frame, scale and every spring are untouched), the container bounds, accessories (their anchor / frame come from
// adjustedSpaceAccessoryView* of the zoom modifier, which ignore this answer) and the icon overlay stay as they were, and the layer anchor equals the one of the gesture phase (0.5, 0.5), so
// the anchor compensation block has nothing to change at the hand-off (no jump).
// Applies only when the composed answers say: pinned to space through the anchor point AND fullyPresented size != frame size (only the icon zoom answers a fullyPresented frame different from its
// frame).  Everything else (3 -> 2 close, window drags, strip, classic mode, a zoom with the anchor flag off) is untouched.
//
// Open from an icon (home -> app) uses the same modifier class and gets the same pivot, so the window ends the open with the anchor it starts the next close with.
//
// ===== Part 2: g2f_closecrop (0.7.6) =====
// Symptom (user screenshot 24.webp = frame t 2.276 s of recording 83f40670, Dopamine window 1056x646 closing to its icon): TWO nested shapes mid-close, an outer rounded rectangle with the
// window's aspect (641 x 392 px in the video, 1.64, darker) and, centred in it, a narrower lighter one (478 x 392 px, 1.22) that carries the icon glyph.
//
// Mechanism (read from the binaries, identical in 16.0 and 16.2; stock behaviour, NOT caused by g1c_fillbounds, the pin or g2f_closepivot - the 0dee8146 recording made without them shows it too):
//  * Two different things are drawn.  (a) The CARD = the item container (SBFluidSwitcherItemContainer) with bounds = R.size = the window size (role frame {{0,-0.5},{1056,646}} even though
//    the zoom hands frameForLayoutRole: bounds {646,646}, see the "[g1c] close roleFrame" lines), scaled uniformly, aspect constant 1.63.  (b) The ICON OVERLAY = an accessory view of the
//    layout (-[SBFluidSwitcherViewController _performModifierIconOverlayVisibilityUpdateResponse:] 16.2 0x1c745cb0c -> -[SBFluidSwitcherSpaceOverlayAccessoryView
//    configureOverlayForIconZoomWithView:crossfadeViews:] 0x1c758c308, crossfade views = the leaf containers' page views) whose bounds the layout block animates (accessory "bounds" with the
//    layout spring) to adjustedSpaceAccessoryViewFrame:forAppLayout: = frameForIndex: = the icon box (646x646).  The box is concentric with the card.
//  * The overlay's icon morph is driven by its ASPECT: -[SBFluidSwitcherIconOverlayView _currentFadeValue] 0x1c7736730 = (bounds.w/bounds.h - a0) / (a1 - a0) with a0 = the icon view's initial aspect
//    and a1 = the crossfade frame's aspect (window); _iconOverlayScale 0x1c72d73f0 and -setMorphFraction: use it.  So the overlay is cropped from the window's aspect to the icon box while the
//    card itself keeps the window's aspect: the overlay is the narrower inner shape, the card (its content crossfading out through the overlay's _setCrossfadeViewsAlpha: 0x1c7736b28) the outer one.
//    The width ratio inner / outer measured in the recording (0.81, 0.775, 0.747, 0.72, 0.707 over five frames) converges to 646 / 1056 = 0.612 = box / window, as this predicts.
//  * 16.2 and 16.0 have identical code for all of it (+ the 16.2 accessory-scale additions, which the zoom does not use), so stock iPadOS shows the same nested look.
//
// Fix (default ON, deliberate): the card is cropped with the overlay.  After -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] ran (G2B's port or the stock block,
// whichever is installed), for an icon zoom of a single-window layout (pin + fullyPresented != frame, as the pivot) a rounded mask view (UIView.maskView of the item container, nothing in the
// switcher touches it) is created over the container bounds and its bounds are animated, in the same pass and with the SAME animation attributes as the overlay's bounds (layoutSettings /
// layoutUpdateMode of animationAttributesForLayoutElement:, corner radius with cornerRadiusSettings), to the centred box (min(frame.w, R.w) x min(frame.h, R.h)).  Card and overlay then share one
// silhouette that goes from the window's aspect to the icon box together with the zoom; the outer card is gone.  When the zoom is over (a later pass without the zoom answers, e.g. the second
// phase of an open) the mask animates back to the full bounds and is removed; -[SBFluidSwitcherItemContainer prepareForReuse] drops it too.
// Needs the centred pivot (g2f_closepivot) because the box is concentric with the card only then.
//
// ===== Diagnostics (Backport162.debug) =====
// For a home swipe close armed by G1C ("[g1c] close: trace armed"): one dump per transition phase (1, 2) of the stage layout right after the layout pass, and for phase 2 again 50 ms and 100 ms
// later ("[g2f] close dump <tag> ..."): the root's answers and, for the item container and every accessory view of the layout, class, frame, bounds, centre, alpha, scale, presentation values,
// clipping / mask state and the subview tree, plus the icon overlay's fade value.  One recording + log pins the cause even if the crop is wrong.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <dlfcn.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2F_ON() BP_OnName("g2f_closepivot")
#define G2F_CROP_ON() BP_OnName("g2f_closecrop")
#define G2F_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static IMP gG2FOrigAnchor, gG2FOrigLayout, gG2FOrigReuse;
static NSString *gG2FLastSig;

int G1C_CloseTraceState(unsigned *serial);                                            // G1C.x: -1 = no traced home swipe close, else the transition phase (0 = gesture, 1..3)

static BOOL G2F_Pin(id self, const char *sel, unsigned long long i) {
    SEL s = sel_registerName(sel);
    return [self respondsToSelector:s] && ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(self, s, i);
}

// The icon zoom, as the composed root answers it for index i: pinned to the space through the anchor point AND a fullyPresented frame of another size than the frame (only the icon zoom).
// f = frameForIndex: (the icon box), fp = fullyPresentedFrameForIndex:frame: (the card's unzoomed frame).
static BOOL G2F_ZoomRects(id root, unsigned long long i, CGRect *fOut, CGRect *fpOut) {
    if (!G2F_Pin(root, "shouldPinLayoutRolesToSpace:", i) || !G2F_Pin(root, "shouldUseAnchorPointToPinLayoutRolesToSpace:", i)) return NO;   // the layout block reads the anchor as a pin anchor only then (0x1c7443a54 / 0x1c7443a70)
    SEL frS = @selector(frameForIndex:), fpS = sel_registerName("fullyPresentedFrameForIndex:frame:");
    if (![root respondsToSelector:frS] || ![root respondsToSelector:fpS]) return NO;
    CGRect f = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(root, frS, i);
    if (!(f.size.width > 0.0) || !(f.size.height > 0.0)) return NO;
    CGRect fp = ((CGRect (*)(id, SEL, unsigned long long, CGRect))objc_msgSend)(root, fpS, i, f);
    if (fabs(fp.size.width - f.size.width) < 1e-6 && fabs(fp.size.height - f.size.height) < 1e-6) return NO;     // not an icon-shaped space (gesture phase, other pinned layouts)
    *fOut = f; *fpOut = fp;
    return YES;
}

// -[SBContinuousExposeRootSwitcherModifier anchorPointForIndex:]  (composed answer, what the layout block reads through the root; 16.2 block 0x1c744330c)
static CGPoint G2F_Anchor(id self, SEL _cmd, unsigned long long i) {
    CGPoint r = ((CGPoint (*)(id, SEL, unsigned long long))gG2FOrigAnchor)(self, _cmd, i);
    if (fabs(r.x - 0.5) > 1e-9 || fabs(r.y - 0.5) > 1e-9 || !G2F_ON()) return r;                    // only the zoom's (0.5, 0.5)
    @try {
        CGRect f, fp;
        if (!G2F_ZoomRects(self, i, &f, &fp)) return r;
        CGPoint a = CGPointMake(0.5 * fp.size.width / f.size.width, 0.5 * fp.size.height / f.size.height);
        if (!isfinite(a.x) || !isfinite(a.y) || a.x <= 0.0 || a.y <= 0.0 || a.x > 8.0 || a.y > 8.0) { G2F_LOG(@"[g2f] idx %llu: anchor %@ out of range, left at (0.5, 0.5)", i, NSStringFromCGPoint(a)); return r; }
        if (BP_LogEnabled()) {
            double scale = [self respondsToSelector:@selector(scaleForIndex:)] ? ((double (*)(id, SEL, unsigned long long))objc_msgSend)(self, @selector(scaleForIndex:), i) : 0.0;
            NSString *sig = [NSString stringWithFormat:@"%@|%@|%@", NSStringFromCGSize(f.size), NSStringFromCGSize(fp.size), NSStringFromCGPoint(a)];
            if (![sig isEqualToString:gG2FLastSig]) {
                gG2FLastSig = sig;
                BP_Log(@"[g2f] zoom pivot idx %llu: anchor (0.5, 0.5) -> %@ (frame %@ icon box centre %@, fully presented %@, scale %.4f): the window scales about its own centre %@ pt from its left edge instead of %.1f; layer anchor becomes (%.3f, %.3f) (stock %.3f, %.3f)",
                       i, NSStringFromCGPoint(a), NSStringFromCGSize(f.size), NSStringFromCGPoint(CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f))), NSStringFromCGSize(fp.size), scale,
                       [NSString stringWithFormat:@"%.1f", 0.5 * fp.size.width], 0.5 * f.size.width,
                       0.5, 0.5, (0.5 * f.size.width) / fp.size.width, (0.5 * f.size.height) / fp.size.height);
            }
        }
        return a;
    } @catch (NSException *e) {
        G2F_LOG(@"[g2f] exception %@", e);
    }
    return r;
}

// ==================================================================================================================================================================================
// Part 2: crop of the card to the icon box (g2f_closecrop) and the close dump
// ==================================================================================================================================================================================
typedef struct { double tl, bl, br, tr; } G2FRadii;                                   // UIRectCornerRadii (HFA of 4 doubles)
static const void *kG2FMask = &kG2FMask;                                              // associated object of the item container: our mask view

static id G2F_IvarObj(id o, const char *name) {
    Ivar iv = o ? class_getInstanceVariable(object_getClass(o), name) : NULL;
    return iv ? BP_ObjIvar(o, iv) : nil;
}
static id G2F_Obj(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}
static id G2F_Obj1(id o, const char *sel, id a) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL, id))objc_msgSend)(o, s, a) : nil;
}
static long long G2F_LL(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((long long (*)(id, SEL))objc_msgSend)(o, s) : 0;
}
static BOOL G2F_Bool(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((BOOL (*)(id, SEL))objc_msgSend)(o, s) : NO;
}
static double G2F_Dbl(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((double (*)(id, SEL))objc_msgSend)(o, s) : 0.0;
}
static double G2F_MinRadius(G2FRadii r) { return fmin(fmin(r.tl, r.bl), fmin(r.br, r.tr)); }

// +[UIView sb_animateWithSettings:mode:animations:completion:] exactly as the layout block uses it (16.0 0x1c68c0f00 stub, 16.2 the same selector).  Update mode 0 would assert in UIKit (not a
// legal answer), no settings = no animation: then the block just runs (what the layout block does for a nil settings object is the same through its own fallbacks).
static void G2F_Animate(id settings, long long mode, void (^anims)(void), void (^done)(BOOL, BOOL)) {
    Class ui = [UIView class];
    SEL s = sel_registerName("sb_animateWithSettings:mode:animations:completion:");
    if (settings && mode > 0 && [ui respondsToSelector:s]) {
        void (^c)(BOOL, BOOL) = done ?: ^(BOOL a, BOOL b) {};
        ((void (*)(Class, SEL, id, long long, void (^)(void), void (^)(BOOL, BOOL)))objc_msgSend)(ui, s, settings, mode, anims, c);
    } else {
        anims();
        if (done) done(YES, NO);
    }
}

static BOOL G2F_RoleInMask(unsigned long long mask, long long role) {                 // 16.2 / 16.0: SBLayoutRoleMaskContainsRole, as the layout block tests it
    static BOOL (*fn)(unsigned long long, long long); static dispatch_once_t once;
    dispatch_once(&once, ^{ fn = (BOOL (*)(unsigned long long, long long))dlsym(RTLD_DEFAULT, "SBLayoutRoleMaskContainsRole"); });
    if (fn) return fn(mask, role);
    return role >= 0 && role < 64 && ((mask >> role) & 1);
}

static void G2F_DropMask(id c) {
    UIView *m = objc_getAssociatedObject(c, kG2FMask);
    if (!m) return;
    objc_setAssociatedObject(c, kG2FMask, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([c respondsToSelector:@selector(maskView)] && [(UIView *)c maskView] == m) [(UIView *)c setMaskView:nil];
}

// -[SBFluidSwitcherItemContainer prepareForReuse]: a recycled container never keeps our mask.
static void G2F_Reuse(id self, SEL _cmd) {
    G2F_DropMask(self);
    if (gG2FOrigReuse) ((void (*)(id, SEL))gG2FOrigReuse)(self, _cmd);
}

// The crop itself, run right after the layout pass of one app layout.  c / r0 were read BEFORE the pass (r0 = the container's presentation corner radius, the radius the card has when the
// zoom starts; the pass already stored the target radii in the model).
static void G2F_Crop(id vc, id appLayout, unsigned long long roleMask, id root, NSUInteger idx, id c, long long role, double r0) {
    if (![c isKindOfClass:[UIView class]]) return;
    UIView *cv = (UIView *)c;
    CGRect f = CGRectZero, fp = CGRectZero;
    BOOL zoom = G2F_ZoomRects(root, idx, &f, &fp);
    UIView *mask = objc_getAssociatedObject(c, kG2FMask);
    if (!zoom && !mask) return;
    if (!G2F_RoleInMask(roleMask, role)) return;                                       // the layout block lays out the roles in the mask only (a zero mask lays out none)
    id attrs = G2F_Obj1(root, "animationAttributesForLayoutElement:", appLayout);
    long long upd = G2F_LL(attrs, "updateMode");
    long long lm = G2F_LL(attrs, "layoutUpdateMode"); if (!lm) lm = upd;              // MODE(): the specific mode, else the update mode
    long long cm = G2F_LL(attrs, "cornerRadiusUpdateMode"); if (!cm) cm = upd;
    id ls = G2F_Obj(attrs, "layoutSettings");
    id cs = G2F_Obj(attrs, "cornerRadiusSettings") ?: ls;
    CGRect cb = cv.bounds;
    CGPoint mid = CGPointMake(CGRectGetMidX(cb), CGRectGetMidY(cb));
    double r1 = 0.0;
    if ([c respondsToSelector:sel_registerName("contentCornerRadii")]) r1 = G2F_MinRadius(((G2FRadii (*)(id, SEL))objc_msgSend)(c, sel_registerName("contentCornerRadii")));
    if (!zoom) {                                                                       // the zoom is over (or never ours): the card gets its full size back with the overlay
        if (fabs(mask.bounds.size.width - cb.size.width) < 0.01 && fabs(mask.bounds.size.height - cb.size.height) < 0.01 && fabs(mask.layer.cornerRadius - r1) < 0.01) return;   // already on its way back
        __weak UIView *wc = cv;
        void (^done)(BOOL, BOOL) = ^(BOOL fin, BOOL ret) { UIView *sc = wc; if (!ret && sc && objc_getAssociatedObject(sc, kG2FMask) == mask) { G2F_DropMask(sc); G2F_LOG(@"[g2f] crop: mask released"); } };
        G2F_LOG(@"[g2f] crop: zoom over, mask %@ -> container bounds %@ (update mode %lld)", NSStringFromCGSize(mask.bounds.size), NSStringFromCGSize(cb.size), lm);
        G2F_Animate(ls, lm, ^{ mask.bounds = CGRectMake(0, 0, cb.size.width, cb.size.height); mask.center = mid; }, done);
        G2F_Animate(cs, cm, ^{ mask.layer.cornerRadius = r1; }, nil);
        return;
    }
    CGRect R = ((CGRect (*)(id, SEL, long long, id, CGRect))objc_msgSend)(root, sel_registerName("frameForLayoutRole:inAppLayout:withBounds:"), role, appLayout, CGRectMake(0, 0, f.size.width, f.size.height));
    double roleScale = [root respondsToSelector:sel_registerName("scaleForLayoutRole:inAppLayout:")] ? ((double (*)(id, SEL, long long, id))objc_msgSend)(root, sel_registerName("scaleForLayoutRole:inAppLayout:"), role, appLayout) : 1.0;
    if (fabs(roleScale - 1.0) > 1e-6 || !(R.size.width > 0.0) || !(R.size.height > 0.0)) { G2F_LOG(@"[g2f] crop: role scale %.4f / role frame %@ not usable, not cropped", roleScale, NSStringFromCGRect(R)); return; }
    CGSize T = CGSizeMake(fmin(f.size.width, cb.size.width), fmin(f.size.height, cb.size.height));
    if (T.width >= cb.size.width - 0.5 && T.height >= cb.size.height - 0.5) return;   // the card already has the icon box's shape (a square window): nothing to crop
    if (!mask) {
        mask = [[UIView alloc] initWithFrame:cb];
        mask.backgroundColor = [UIColor blackColor];
        mask.layer.cornerRadius = r0 >= 0.0 ? r0 : r1;
        mask.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(c, kG2FMask, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [UIView performWithoutAnimation:^{ cv.maskView = mask; }];
        G2F_LOG(@"[g2f] crop: mask created over container bounds %@ radius %.2f, cropping to %@ (frame %@ role frame %@ fully presented %@, bounds update mode %lld)", NSStringFromCGSize(cb.size), mask.layer.cornerRadius, NSStringFromCGSize(T),
                NSStringFromCGSize(f.size), NSStringFromCGRect(R), NSStringFromCGSize(fp.size), lm);
    }
    CGSize cur = mask.bounds.size;
    if (fabs(cur.width - T.width) < 0.01 && fabs(cur.height - T.height) < 0.01 && fabs(mask.layer.cornerRadius - r1) < 0.01) return;   // a later pass of the same zoom: already on its way
    G2F_Animate(ls, lm, ^{ mask.bounds = CGRectMake(0, 0, T.width, T.height); mask.center = mid; }, nil);
    G2F_Animate(cs, cm, ^{ mask.layer.cornerRadius = r1; }, nil);
}

// ---------------------------------------------------------------------------------------------------- close dump (diagnostics only)
static void G2F_LogView(NSString *tag, UIView *v, int depth, int *budget) {
    if (!v || ![v isKindOfClass:[UIView class]] || *budget <= 0) return;
    (*budget)--;
    CALayer *l = v.layer;
    CALayer *p = [l presentationLayer] ?: l;
    NSMutableString *extra = [NSMutableString string];
    if ([v respondsToSelector:sel_registerName("isContentClippingEnabled")] && G2F_Bool(v, "isContentClippingEnabled")) {
        CGRect cf = ((CGRect (*)(id, SEL))objc_msgSend)(v, sel_registerName("contentClippingFrame"));
        [extra appendFormat:@" contentClip %@", NSStringFromCGRect(cf)];
    }
    if (v.maskView) [extra appendFormat:@" maskView %@ presBounds %@ r %.2f", NSStringFromCGRect(v.maskView.bounds), NSStringFromCGRect([v.maskView.layer.presentationLayer bounds]), v.maskView.layer.cornerRadius];
    if ([v respondsToSelector:sel_registerName("_currentFadeValue")]) [extra appendFormat:@" fade %.4f", G2F_Dbl(v, "_currentFadeValue")];
    BP_Log(@"[g2f] close dump %@ %*s%@ %p frame %@ bounds %@ centre %@ alpha %.3f hidden %d clips %d cr %.2f | presentation bounds %@ pos %@ scale %.4f alpha %.3f cr %.2f%@",
           tag, depth * 2, "", NSStringFromClass([v class]), (__bridge void *)v, NSStringFromCGRect(v.frame), NSStringFromCGRect(v.bounds), NSStringFromCGPoint(v.center), v.alpha, v.hidden, v.clipsToBounds, l.cornerRadius,
           NSStringFromCGRect(p.bounds), NSStringFromCGPoint(p.position), p.transform.m11, p.opacity, p.cornerRadius, extra);
    if (depth >= 4) return;
    for (UIView *sv in v.subviews) G2F_LogView(tag, sv, depth + 1, budget);
}

static void G2F_Dump(id vc, id appLayout, NSString *tag) {
    id root = G2F_IvarObj(vc, "_rootModifier");
    NSArray *aps = G2F_Obj(vc, "appLayouts");
    NSUInteger idx = aps ? [aps indexOfObject:appLayout] : NSNotFound;
    if (!root || idx == NSNotFound) return;
    CGRect f = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(root, @selector(frameForIndex:), idx);
    CGRect fp = [root respondsToSelector:sel_registerName("fullyPresentedFrameForIndex:frame:")] ? ((CGRect (*)(id, SEL, unsigned long long, CGRect))objc_msgSend)(root, sel_registerName("fullyPresentedFrameForIndex:frame:"), idx, f) : CGRectNull;
    double S = [root respondsToSelector:@selector(scaleForIndex:)] ? ((double (*)(id, SEL, unsigned long long))objc_msgSend)(root, @selector(scaleForIndex:), idx) : 0.0;
    CGPoint an = [root respondsToSelector:@selector(anchorPointForIndex:)] ? ((CGPoint (*)(id, SEL, unsigned long long))objc_msgSend)(root, @selector(anchorPointForIndex:), idx) : CGPointZero;
    CGRect adj = [root respondsToSelector:sel_registerName("adjustedSpaceAccessoryViewFrame:forAppLayout:")] ? ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(root, sel_registerName("adjustedSpaceAccessoryViewFrame:forAppLayout:"), f, appLayout) : CGRectNull;
    BOOL clips = [root respondsToSelector:sel_registerName("clipsToBoundsAtIndex:")] && ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(root, sel_registerName("clipsToBoundsAtIndex:"), idx);
    BP_Log(@"[g2f] close dump %@ root answers idx %lu: frame %@ fullyPresented %@ scale %.4f anchor %@ adjustedAccessoryFrame %@ clipsToBounds %d", tag, (unsigned long)idx, NSStringFromCGRect(f), NSStringFromCGRect(fp), S, NSStringFromCGPoint(an), NSStringFromCGRect(adj), clips);
    NSArray *leafs = G2F_Obj(appLayout, "leafAppLayouts") ?: @[];
    int budget = 70;
    for (id leaf in leafs) {
        UIView *c = G2F_Obj1(vc, "_itemContainerForAppLayoutIfExists:", leaf);
        BP_Log(@"[g2f] close dump %@ item container of %@: %@", tag, leaf, c ? @"" : @"(none)");
        G2F_LogView(tag, c, 0, &budget);
        UIView *pv = G2F_IvarObj(c, "_pageView");
        if (pv) BP_Log(@"[g2f] close dump %@ page view %@ frame %@ alpha %.3f contentView %@", tag, NSStringFromClass([pv class]), NSStringFromCGRect(pv.frame), pv.alpha, NSStringFromClass([G2F_Obj(c, "contentView") class]));
    }
    for (NSString *key in @[@"_visibleOverlayAccessoryViews", @"_visibleUnderlayAccessoryViews"]) {
        id d = G2F_IvarObj(vc, key.UTF8String);
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        for (id k in [(NSDictionary *)d allKeys]) {
            UIView *a = [(NSDictionary *)d objectForKey:k];
            BP_Log(@"[g2f] close dump %@ %@ of %@:", tag, key, k);
            G2F_LogView(tag, a, 0, &budget);
        }
    }
}

static unsigned gG2FDumpSerial;
static int gG2FDumpDone;                                                              // bit per phase already dumped for this serial

// After the layout pass: the dump of the stage layout of a traced home swipe close (armed in G1C: home gesture in mode 3).
static void G2F_MaybeDump(id vc, id appLayout) {
    unsigned serial = 0;
    int ph = G1C_CloseTraceState(&serial);
    if (ph < 1 || ph > 2) return;
    id root = G2F_IvarObj(vc, "_rootModifier");
    id stage = G2F_Obj(root, "appLayoutOnContinuousExposeStage");
    if (!stage || ![stage isEqual:appLayout]) return;
    if (serial != gG2FDumpSerial) { gG2FDumpSerial = serial; gG2FDumpDone = 0; }
    if (gG2FDumpDone & (1 << ph)) return;
    gG2FDumpDone |= 1 << ph;
    G2F_Dump(vc, appLayout, [NSString stringWithFormat:@"p%d+0", ph]);
    if (ph != 2) return;
    NSArray *later = @[@[@0.05, @"p2+3f"], @[@0.10, @"p2+6f"]];                       // ~3 and ~6 frames at 60 fps
    for (NSArray *e in later) {
        NSString *tag = e[1];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([e[0] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!BP_LogEnabled() || gG2FDumpSerial != serial) return;
            @try { G2F_Dump(vc, appLayout, tag); } @catch (NSException *ex) { BP_Log(@"[g2f] close dump exception %@", ex); }
        });
    }
}

// -[SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion:] (G2B's port or the stock method, whichever is installed): the pass runs first and unchanged, then the crop / dump.
static void G2F_Layout(id vc, SEL _cmd, id appLayout, unsigned long long roleMask, id completion) {
    id c = nil, leaf = nil; long long role = 0; double r0 = -1.0; id root = nil; NSUInteger idx = NSNotFound;
    BOOL crop = appLayout && G2F_CROP_ON() && G2F_ON();                               // the box is concentric with the card only about the window's own centre
    if (crop) {
        @try {
            root = G2F_IvarObj(vc, "_rootModifier");
            NSArray *leafs = G2F_Obj(appLayout, "leafAppLayouts");
            NSArray *aps = G2F_Obj(vc, "appLayouts");
            idx = aps ? [aps indexOfObject:appLayout] : NSNotFound;
            if (root && leafs.count == 1 && idx != NSNotFound && G2F_Bool(vc, "isChamoisWindowingUIEnabled")) {   // one window per layout; classic switcher untouched
                leaf = leafs.firstObject;
                c = G2F_Obj1(vc, "_itemContainerForAppLayoutIfExists:", leaf);
                id item = [G2F_Obj(leaf, "allItems") firstObject];
                role = item ? ((long long (*)(id, SEL, id))objc_msgSend)(appLayout, sel_registerName("layoutRoleForItem:"), item) : 0;
                if (c) r0 = G2F_Dbl(c, "effectivePageViewPresentationCornerRadius");
            }
        } @catch (NSException *e) { c = nil; G2F_LOG(@"[g2f] exception %@", e); }
    }
    ((void (*)(id, SEL, id, unsigned long long, id))gG2FOrigLayout)(vc, _cmd, appLayout, roleMask, completion);
    if (!appLayout) return;
    @try {
        if (!c && leaf) c = G2F_Obj1(vc, "_itemContainerForAppLayoutIfExists:", leaf);       // created by the pass itself (r0 stays -1: the mask then starts at the target radius)
        if (c && root) G2F_Crop(vc, appLayout, roleMask, root, idx, c, role, r0);
    } @catch (NSException *e) { G2F_LOG(@"[g2f] crop exception %@", e); }
    if (BP_LogEnabled()) {
        @try { G2F_MaybeDump(vc, appLayout); } @catch (NSException *e) { BP_Log(@"[g2f] close dump exception %@", e); }
    }
}

void G2F_Setup(void) {
    if (G2F_ON()) {
        Class c = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
        SEL s = NSSelectorFromString(@"anchorPointForIndex:");
        Method m = c ? class_getInstanceMethod(c, s) : NULL;
        Class iz = NSClassFromString(@"SBFullScreenToHomeIconZoomSwitcherModifier");
        if (!m || !iz || ![iz instancesRespondToSelector:NSSelectorFromString(@"fullyPresentedFrameForIndex:frame:")]) { BP_Log(@"[g2f] SBContinuousExposeRootSwitcherModifier anchorPointForIndex: / icon zoom fullyPresentedFrameForIndex:frame: not found, pivot not installed"); }
        else {
            gG2FOrigAnchor = method_getImplementation(m);
            class_replaceMethod(c, s, (IMP)G2F_Anchor, method_getTypeEncoding(m));
            BP_Log(@"[g2f] installed (zoom to / from an icon pivots about the window's own centre)");
        }
    }
    // The layout pass wrapper carries the crop and the close dump (a pass-through when both are off and the debug log is off).
    Class vcc = NSClassFromString(@"SBFluidSwitcherViewController");
    SEL ls = NSSelectorFromString(@"_layoutAppLayout:roleMask:completion:");
    Method lm = vcc ? class_getInstanceMethod(vcc, ls) : NULL;
    Class ic = NSClassFromString(@"SBFluidSwitcherItemContainer");
    SEL rs = NSSelectorFromString(@"prepareForReuse");
    Method rm = ic ? class_getInstanceMethod(ic, rs) : NULL;
    if (!lm || !rm || ![UIView instancesRespondToSelector:@selector(setMaskView:)]) { BP_Log(@"[g2f] SBFluidSwitcherViewController _layoutAppLayout:roleMask:completion: / item container prepareForReuse not found, crop and close dump not installed"); return; }
    gG2FOrigLayout = method_getImplementation(lm);
    class_replaceMethod(vcc, ls, (IMP)G2F_Layout, method_getTypeEncoding(lm));
    gG2FOrigReuse = method_getImplementation(rm);
    class_replaceMethod(ic, rs, (IMP)G2F_Reuse, method_getTypeEncoding(rm));
    BP_Log(@"[g2f] installed (layout pass wrapper: crop of the card to the icon box %@, close dump with Backport162.debug)", G2F_CROP_ON() && G2F_ON() ? @"ON" : @"off");
}
#pragma clang diagnostic pop
