// G3C.x  (0.6.5)  Top-affordance "Zoom" on a full-screen (maximized) Stage Manager app.
//
// Report: with the tweak, "Zoom" in the three-dots menu of a full-screen app does nothing at all (stock 16.0 only toggles the status bar),
// while the expectation is that the app goes back to a Stage Manager window.  Details and evidence: specs/AUDIT-ZOOM-0.6.5.md.
//
// Mechanism (all addresses 16.0 20A8372 / 16.2 20C65):
//   * The menu item sends action type 9 to -[SBMedusaDecoratedDeviceApplicationSceneViewController
//     _topAffordanceViewController:handleActionType:transitionSource:] (16.0 0x1c632ba50 / 16.2 0x1c77ccb6c).  16.0's request block
//     (block_invoke_2.65, 0x1c632c18c) TOGGLES the item's sizing policy, only the policy:
//         [ctx _setRequestedFrontmostEntity:e];  p = [ctx requestedLayoutAttributesForEntity:e];
//         p = [p attributesByModifyingSizingPolicy:(p.sizingPolicy == Largest(mask) ? Smallest(mask) : Largest(mask))];
//         [ctx setRequestedLayoutAttributes:p forEntity:e];
//   * A window that was never resized by the user has the stored size (1,1) (the whole container; written by the auto layout), so after
//     the toggle it is a "snap-to-grid" (policy 0) window of full size: the only visible change is the status bar (stock 16.0).
//   * With group 2b the auto layout write-back derives the sizing policy from the size again (16.2 _SBPreferredDisplayItemSizingPolicy
//     0x1c7954330: policy 0 and size (1,1) -> 2 "maximized"), so the toggle is undone and nothing changes at all (the regression).
//   * 16.2's own Zoom request (block_invoke_2.67, 0x1c77cd2e8) resets the attributed size with SBDisplayItemAttributedSizeUnspecified()
//     (0x1c75cedc4) before it applies the sizing policy.  An Unspecified size is resolved by the calculator's frame code to the LIVE
//     chamois defaultWindowSize snapped to the grid (16.0 _frameForLayoutRole 0x1c6119d30: _SBDisplayItemSizeIsUnspecified ->
//     defaultWindowSize -> nearestGridSizeForProposedSize; 16.2 0x1c75a3b34..0x1c75a3b8c: size <= 0 -> defaultWindowSize
//     sizeInBounds:defaultSize:screenEdgePadding:), then the write-back stores the real size and the policy follows from it.
//
// ROUND 2 (device log): the stored size of a never-windowed item is UNSPECIFIED ({0,0}), not (1,1).  The calculator resolves (policy 0,
// Unspecified) to chamoisLayoutAttributes.defaultWindowSize snapped by the grid; with the 16.0 settings builder (0x1c6413524 ->
// _defaultAppSizeForContainerBounds 0x1c641391c) that is the whole container, so "window" and "maximized" look identical and the write-back
// (_SBPreferredDisplayItemSizingPolicy 0x1c7954330) derives policy 2.  16.2's builder (0x1c78c0f50) picks the default window from its column
// grid: the SECOND largest width (index count-2, 0x1c78c1534..0x1c78c1548), i.e. one grid step below full screen.  See specs/AUDIT-ZOOM-0.6.5.md "Round 2".
//
// What this file does: when the Zoom request leaves a never-windowed item (policy 0, Unspecified size, or a full-size stored size) it stores an
// EXPLICIT size = the live grid's size one step below full width (-[SBDisplayItemLayoutGrid gridSizeAtIndexFromFullWidth:1 ...], the same
// grid and the same index 16.2 uses for its default window).  That is the state a hand-resized window has (policy 0 + explicit size), which the
// user confirmed toggles fine.  Also when Zoom would maximize an item whose Unspecified default window already IS the whole container (nothing
// would visibly change), the press goes to the window directly.  Switch: "g3c" (Backport162.off.g3c).  No number is invented.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>
#import <time.h>

#import "BP.h"

#pragma clang diagnostic ignored "-Wundeclared-selector"

// ------------------------------------------------------------------------------------------------ helpers

// interface declarations for the hooked classes (Logos only emits @class, ARC needs a visible @interface to message them)
@interface SBMedusaDecoratedDeviceApplicationSceneViewController : UIViewController @end
@interface SBWorkspaceApplicationSceneTransitionContext : NSObject @end

@interface NSObject (BPG3C)
- (id)requestedLayoutAttributesForEntity:(id)entity;
- (long long)sizingPolicy;
- (id)attributesByModifyingSize:(CGSize)size;
- (void)setRequestedLayoutAttributes:(id)attrs forEntity:(id)entity;
@end

// The Zoom request is built by a block that runs inside requestTransitionWithOptions:...builder: (synchronously or a run-loop turn later):
// the handler hook arms the fix for a short time, the attributes setter consumes it.
static uint64_t gG3CArmedUntil;                         // clock_gettime_nsec_np(CLOCK_UPTIME_RAW) deadline, 0 = not armed
static const uint64_t kG3CWindowNs = 3ull * 1000000000ull;

static BOOL G3C_On(void) { return BP_OnName("g3c"); }

static BOOL G3C_Armed(void) {
    uint64_t until = gG3CArmedUntil;
    return until != 0 && clock_gettime_nsec_np(CLOCK_UPTIME_RAW) < until;
}

// SBDisplayItemLayoutAttributes._size (16.0 data model: fractions of the container when both components <= 1, absolute points otherwise).
static BOOL G3C_ReadSize(id attrs, CGSize *out) {
    if (!attrs || !out) return NO;
    Ivar iv = class_getInstanceVariable(object_getClass(attrs), "_size");
    const char *enc = iv ? ivar_getTypeEncoding(iv) : NULL;
    if (!enc || strncmp(enc, "{CGSize", 7) != 0) return NO;
    memcpy(out, (const char *)(__bridge void *)attrs + ivar_getOffset(iv), sizeof(CGSize));
    return YES;
}

// "Full size": the item fills its container (stored size (1,1), or the absolute size of the screen in either orientation).
static BOOL G3C_IsFullSize(id attrs) {
    CGSize s;
    if (!G3C_ReadSize(attrs, &s)) return NO;
    if (s.width <= 0 || s.height <= 0) return NO;                       // already Unspecified
    if (s.width <= 1.0001 && s.height <= 1.0001) return s.width >= 0.9999 && s.height >= 0.9999;
    CGSize sc = [UIScreen mainScreen].bounds.size;
    return (s.width >= sc.width * 0.995 && s.height >= sc.height * 0.995) || (s.width >= sc.height * 0.995 && s.height >= sc.width * 0.995);
}

// Live objects of the switcher the Zoom was pressed in (set by the handler hook, used while armed).
static __weak id gG3CSwitcherVC;

static id G3C_Obj(id o, const char *sel) {
    SEL s = sel_registerName(sel);
    return (o && [o respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(o, s) : nil;
}

static BOOL G3C_IsUnspecified(id attrs) {
    CGSize s;
    return G3C_ReadSize(attrs, &s) && s.width == 0 && s.height == 0;
}

// Grid size for the item.  index >= 0: gridSizeAtIndexFromFullWidth:index (0 = full width, 1 = one step below, the 16.2 default window pick);
// index < 0: nearestGridSizeForProposedSize:(defaultWindowSize) = what the frame code does for an Unspecified size.  Returns NO on any miss.
static BOOL G3C_GridSize(id vc, id entity, long long index, CGSize *out, CGSize *container) {
    if (!vc || !entity || !out) return NO;
    SEL calcS = sel_registerName("displayItemLayoutAttributesCalculator"), boundsS = sel_registerName("containerViewBounds");
    if (![vc respondsToSelector:calcS] || ![vc respondsToSelector:boundsS]) return NO;
    id calc = G3C_Obj(vc, "displayItemLayoutAttributesCalculator");
    id grid = G3C_Obj(calc, "_chamoisLayoutGridCache");
    id attrs = G3C_Obj(vc, "chamoisLayoutAttributes");
    id handle = G3C_Obj(entity, "sceneHandle");
    id item = G3C_Obj(handle, "displayItemRepresentation");
    SEL infoS = sel_registerName("layoutRestrictionInfoForItem:");
    if (!grid || !attrs || !item || ![calc respondsToSelector:infoS]) return NO;
    id info = ((id (*)(id, SEL, id))objc_msgSend)(calc, infoS, item);
    CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(vc, boundsS);
    SEL oS = sel_registerName("switcherInterfaceOrientation"), scS = sel_registerName("screenScale");
    long long orient = [vc respondsToSelector:oS] ? ((long long (*)(id, SEL))objc_msgSend)(vc, oS) : 0;
    double scale = [vc respondsToSelector:scS] ? ((double (*)(id, SEL))objc_msgSend)(vc, scS) : 0;
    if (bounds.size.width <= 0 || bounds.size.height <= 0 || scale <= 0) return NO;
    CGSize r = CGSizeZero;
    if (index >= 0) {
        SEL gS = sel_registerName("gridSizeAtIndexFromFullWidth:forBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:");
        if (![grid respondsToSelector:gS]) return NO;
        r = ((CGSize (*)(id, SEL, unsigned long long, CGRect, long long, id, double, id))objc_msgSend)(grid, gS, (unsigned long long)index, bounds, orient, info, scale, attrs);
    } else {
        SEL nS = sel_registerName("nearestGridSizeForProposedSize:inBounds:contentOrientation:layoutRestrictionInfo:screenScale:chamoisLayoutAttributes:");
        SEL dS = sel_registerName("defaultWindowSize");
        if (![grid respondsToSelector:nS] || ![attrs respondsToSelector:dS]) return NO;
        CGSize def = ((CGSize (*)(id, SEL))objc_msgSend)(attrs, dS);
        r = ((CGSize (*)(id, SEL, CGSize, CGRect, long long, id, double, id))objc_msgSend)(grid, nS, def, bounds, orient, info, scale, attrs);
    }
    if (r.width <= 0 || r.height <= 0) return NO;
    *out = r;
    if (container) *container = bounds.size;
    return YES;
}

static BOOL G3C_IsContainer(CGSize s, CGSize c) { return s.width >= c.width - 0.5 && s.height >= c.height - 0.5; }

static id G3C_FixedAttributes(id ctx, id attrs, id entity) {
    SEL reqS = @selector(requestedLayoutAttributesForEntity:), polS = @selector(sizingPolicy), modS = @selector(attributesByModifyingSize:);
    if (![ctx respondsToSelector:reqS] || ![attrs respondsToSelector:polS] || ![attrs respondsToSelector:modS]) return attrs;
    id prev = ((id (*)(id, SEL, id))objc_msgSend)(ctx, reqS, entity);
    if (!prev || ![prev respondsToSelector:polS]) return attrs;
    long long newPolicy = ((long long (*)(id, SEL))objc_msgSend)(attrs, polS);
    long long prevPolicy = ((long long (*)(id, SEL))objc_msgSend)(prev, polS);
    BOOL unspec = G3C_IsUnspecified(attrs), full = G3C_IsFullSize(attrs);
    { CGSize sn = CGSizeZero; BOOL okn = G3C_ReadSize(attrs, &sn);
      BP_Log(@"[g3c] setRequestedLayoutAttributes while armed: prevPolicy %lld newPolicy %lld size %s{%g, %g} unspecified %d fullSize %d", prevPolicy, newPolicy, okn ? "" : "(unreadable) ", sn.width, sn.height, unspec, full); }
    if (!unspec && !full) return attrs;                                    // explicit smaller size: the hand-resized case, untouched
    id vc = gG3CSwitcherVC;
    CGSize win = CGSizeZero, cont = CGSizeZero;
    BOOL leaving = (newPolicy == 0 && prevPolicy != 0);                    // maximized / zoomed -> snap-to-grid
    BOOL stay = (newPolicy != 0 && prevPolicy == 0 && unspec);             // window -> maximize, but the Unspecified window may already be full screen
    if (!leaving && !stay) return attrs;
    if (stay) {
        CGSize def = CGSizeZero;
        if (!G3C_GridSize(vc, entity, -1, &def, &cont) || !G3C_IsContainer(def, cont)) return attrs;     // a real smaller default window: maximize is visible, keep it
        BP_Log(@"[g3c] zoom: default window {%g, %g} already fills the container: the press leaves full screen instead", def.width, def.height);
    }
    if (!G3C_GridSize(vc, entity, 1, &win, &cont) || G3C_IsContainer(win, cont)) { BP_Log(@"[g3c] zoom: no grid size below full screen (vc %d), request untouched", vc != nil); return attrs; }
    id base = stay ? prev : attrs;                                          // stay: keep policy 0 of the current state
    CGSize frac = CGSizeMake(win.width / cont.width, win.height / cont.height);   // fractions of the container (<= 1) = 16.0 data model, also read by the 16.2 emulation
    id out = ((id (*)(id, SEL, CGSize))objc_msgSend)(base, modS, frac);
    if (!out) return attrs;
    BP_Log(@"[g3c] zoom: stored size {%g, %g} of {%g, %g} (grid index 1 from full width), policy %lld", win.width, win.height, cont.width, cont.height, stay ? prevPolicy : newPolicy);
    gG3CArmedUntil = 0;
    return out;
}

// ------------------------------------------------------------------------------------------------ hooks

%group G3C_Zoom

%hook SBMedusaDecoratedDeviceApplicationSceneViewController

// 16.0 0x1c632ba50 / 16.2 0x1c77ccb6c; action type 9 = the "Zoom" (maximization) item (UIAction block 0x1c645abb8 sends 9).
- (void)_topAffordanceViewController:(id)vc handleActionType:(long long)type transitionSource:(long long)source {
    if (type == 9) BP_Log(@"[g3c] handleActionType 9 (Zoom) seen, switch %d", G3C_On());
    if (type == 9 && G3C_On()) {
        // the decorated VC has no -_windowScene: scene handle -> window scene -> switcher controller -> content (fluid switcher) view controller
        id handle = G3C_Obj((id)self, "sceneHandle");
        id ws = G3C_Obj(handle, "_windowScene");
        id sc = G3C_Obj(ws, "switcherController");
        id fvc = G3C_Obj(sc, "contentViewController");
        Class fluid = NSClassFromString(@"SBFluidSwitcherViewController");
        gG3CSwitcherVC = (fvc && fluid && [fvc isKindOfClass:fluid]) ? fvc : nil;
        if (!gG3CSwitcherVC) BP_Log(@"[g3c] switcher view controller not found (handle %d windowScene %d switcherController %d content %@)", handle != nil, ws != nil, sc != nil, fvc ? NSStringFromClass(object_getClass(fvc)) : @"nil");
        gG3CArmedUntil = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + kG3CWindowNs;
    }
    %orig(vc, type, source);
}

%end

%hook SBWorkspaceApplicationSceneTransitionContext

// 16.0 0x1c61ccac4: dictionary store keyed by the entity's unique identifier.
- (void)setRequestedLayoutAttributes:(id)attrs forEntity:(id)entity {
    id use = attrs;
    if (attrs && entity && G3C_Armed() && G3C_On()) use = G3C_FixedAttributes(self, attrs, entity);
    %orig(use, entity);
}

%end

%end // G3C_Zoom

void G3C_Setup(void) {
    %init(G3C_Zoom);
}
