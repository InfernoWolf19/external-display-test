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
// What this file does: when the user's Zoom request changes a full-size item to the smallest policy 0 (leaving maximized) it applies the
// same primitive 16.2 uses (Unspecified size) to the requested attributes, so the item comes back with the live default window size.
// A window the user resized before keeps its stored size (not full size -> untouched), exactly like on 16.0 and as the user reports.
// No window size is invented here; nothing is computed.  Switch: "g3c" (Backport162.off.g3c).

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

static id G3C_FixedAttributes(id ctx, id attrs, id entity) {
    SEL reqS = @selector(requestedLayoutAttributesForEntity:), polS = @selector(sizingPolicy), modS = @selector(attributesByModifyingSize:);
    if (![ctx respondsToSelector:reqS] || ![attrs respondsToSelector:polS] || ![attrs respondsToSelector:modS]) return attrs;
    id prev = ((id (*)(id, SEL, id))objc_msgSend)(ctx, reqS, entity);
    if (!prev || ![prev respondsToSelector:polS]) return attrs;
    long long newPolicy = ((long long (*)(id, SEL))objc_msgSend)(attrs, polS);
    long long prevPolicy = ((long long (*)(id, SEL))objc_msgSend)(prev, polS);
    { CGSize sn = CGSizeZero; BOOL okn = G3C_ReadSize(attrs, &sn);
      BP_Log(@"[g3c] setRequestedLayoutAttributes while armed: prevPolicy %lld newPolicy %lld size %s{%g, %g} fullSize %d", prevPolicy, newPolicy, okn ? "" : "(unreadable) ", sn.width, sn.height, G3C_IsFullSize(attrs)); }
    // leaving maximized / zoomed-to-fill for snap-to-grid (policy 0) while the stored size is still the whole container
    if (newPolicy != 0 || prevPolicy == 0 || !G3C_IsFullSize(attrs)) return attrs;
    id out = ((id (*)(id, SEL, CGSize))objc_msgSend)(attrs, modS, CGSizeZero);   // == SBDisplayItemAttributedSizeUnspecified() in the 16.0 model
    if (!out) return attrs;
    BP_Log(@"[g3c] zoom: full-size item leaves policy %lld for policy 0, stored size reset to Unspecified (default window size)", prevPolicy);
    gG3CArmedUntil = 0;
    return out;
}

// ------------------------------------------------------------------------------------------------ hooks

%group G3C_Zoom

%hook SBMedusaDecoratedDeviceApplicationSceneViewController

// 16.0 0x1c632ba50 / 16.2 0x1c77ccb6c; action type 9 = the "Zoom" (maximization) item (UIAction block 0x1c645abb8 sends 9).
- (void)_topAffordanceViewController:(id)vc handleActionType:(long long)type transitionSource:(long long)source {
    if (type == 9) BP_Log(@"[g3c] handleActionType 9 (Zoom) seen, switch %d", G3C_On());
    if (type == 9 && G3C_On()) gG3CArmedUntil = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + kG3CWindowNs;
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
