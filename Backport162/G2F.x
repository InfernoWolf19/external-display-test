// G2F.x : symmetric shrink of the zoom to / from a home screen icon under Stage Manager (DELIBERATE, switchable deviation from stock 16.0 and 16.2).
// 16.0 = 20A8372, 16.2 = 20C65 (unslid cache addresses). Switch: g2f_closepivot (default ON, kill switch file Backport162.off.g2f_closepivot).
// Setup: G2F_Setup(). Log lines (Backport162.debug): "[g2f] ...". Spec: specs/CLOSE-PIVOT-0.7.6.md.
//
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import "BP.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wundeclared-selector"

#define G2F_ON() BP_OnName("g2f_closepivot")
#define G2F_LOG(...) do { if (BP_LogEnabled()) BP_Log(__VA_ARGS__); } while (0)

static IMP gG2FOrigAnchor;
static NSString *gG2FLastSig;

static BOOL G2F_Pin(id self, const char *sel, unsigned long long i) {
    SEL s = sel_registerName(sel);
    return [self respondsToSelector:s] && ((BOOL (*)(id, SEL, unsigned long long))objc_msgSend)(self, s, i);
}

// -[SBContinuousExposeRootSwitcherModifier anchorPointForIndex:]  (composed answer, what the layout block reads through the root; 16.2 block 0x1c744330c)
static CGPoint G2F_Anchor(id self, SEL _cmd, unsigned long long i) {
    CGPoint r = ((CGPoint (*)(id, SEL, unsigned long long))gG2FOrigAnchor)(self, _cmd, i);
    if (fabs(r.x - 0.5) > 1e-9 || fabs(r.y - 0.5) > 1e-9 || !G2F_ON()) return r;                    // only the zoom's (0.5, 0.5)
    @try {
        if (!G2F_Pin(self, "shouldPinLayoutRolesToSpace:", i) || !G2F_Pin(self, "shouldUseAnchorPointToPinLayoutRolesToSpace:", i)) return r;   // the layout block reads the anchor as a pin anchor only then (0x1c7443a54 / 0x1c7443a70)
        SEL frS = @selector(frameForIndex:), fpS = sel_registerName("fullyPresentedFrameForIndex:frame:");
        if (![self respondsToSelector:frS] || ![self respondsToSelector:fpS]) return r;
        CGRect f = ((CGRect (*)(id, SEL, unsigned long long))objc_msgSend)(self, frS, i);
        if (!(f.size.width > 0.0) || !(f.size.height > 0.0)) return r;
        CGRect fp = ((CGRect (*)(id, SEL, unsigned long long, CGRect))objc_msgSend)(self, fpS, i, f);
        if (fabs(fp.size.width - f.size.width) < 1e-6 && fabs(fp.size.height - f.size.height) < 1e-6) return r;     // not an icon-shaped space (gesture phase, other pinned layouts)
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

void G2F_Setup(void) {
    if (!G2F_ON()) return;
    Class c = NSClassFromString(@"SBContinuousExposeRootSwitcherModifier");
    SEL s = NSSelectorFromString(@"anchorPointForIndex:");
    Method m = c ? class_getInstanceMethod(c, s) : NULL;
    Class iz = NSClassFromString(@"SBFullScreenToHomeIconZoomSwitcherModifier");
    if (!m || !iz || ![iz instancesRespondToSelector:NSSelectorFromString(@"fullyPresentedFrameForIndex:frame:")]) { BP_Log(@"[g2f] SBContinuousExposeRootSwitcherModifier anchorPointForIndex: / icon zoom fullyPresentedFrameForIndex:frame: not found, not installed"); return; }
    gG2FOrigAnchor = method_getImplementation(m);
    class_replaceMethod(c, s, (IMP)G2F_Anchor, method_getTypeEncoding(m));
    BP_Log(@"[g2f] installed (zoom to / from an icon pivots about the window's own centre)");
}
#pragma clang diagnostic pop
